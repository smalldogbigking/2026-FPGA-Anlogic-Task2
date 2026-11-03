#include "motor_control.h"
#include "calibration.h"
#include "pick_config.h"
#include "motion_profile.h"
#include <math.h>
#include <string.h>
static const uint16_t home_pose[6]=PICK_HOME_US,left_pose[6]=PICK_LEFT_US,right_pose[6]=PICK_RIGHT_US;
enum {HOME_CLOSE,HOME_CH5,HOME_OTHERS,OPEN_HOME,TARGET_OTHERS,TARGET_CH5,GRIP_CLOSE,
      CARRY_CH5,CARRY_OTHERS,DROP_TURN,DROP_EXTEND,DROP_CH5,GRIP_OPEN,RETURN_CH5,RETURN_OTHERS,PHASE_COUNT};
static const char *const stages[]={"HOME_CLOSE","HOME_CH5","HOME_OTHERS","OPEN_HOME","TARGET_OTHERS","TARGET_CH5",
    "GRIP_CLOSE","CARRY_HOME_CH5","CARRY_HOME_OTHERS","DROP_TURN","DROP_EXTEND","DROP_CH5","GRIP_OPEN","RETURN_CH5","RETURN_HOME_CLOSED"};
static bool in_range(const MotorControl *s,const uint16_t p[6]) {
    for(unsigned i=0;i<6;i++) if(p[i]<s->config.min_us[i] || p[i]>s->config.max_us[i]) return false;
    return true;
}
bool pick_ready(const MotorControl *s) {
    CalibrationInfo info=calibration_info(); uint16_t opened,closed;
    return s->ready && info.ready && info.fixed_channel==2 && info.fixed_pulse==1382 && info.gripper_channel==1 && info.fit_mask==60 &&
        !strcmp(info.unit,"cm") && calibration_grip(false,&opened) && calibration_grip(true,&closed) &&
        /* Keep original calibrated direction, but allow the runtime CH1 tuning.
           The spatial model and its recorded gripper values remain untouched. */
        opened<closed && PICK_OPEN_US<PICK_CLOSE_US &&
        PICK_OPEN_US>=s->config.min_us[0] && PICK_CLOSE_US<=s->config.max_us[0] &&
        in_range(s,home_pose) && in_range(s,left_pose) && in_range(s,right_pose);
}
static bool grip_phase(unsigned p) { return p==HOME_CLOSE || p==OPEN_HOME || p==GRIP_CLOSE || p==GRIP_OPEN; }
static uint32_t settle(const PickCycle *a) {
    if(!a->phase_moves)return 0;
    if(grip_phase(a->phase) || a->phase==RETURN_OTHERS)return PICK_GRIP_SETTLE_MS;
    if(a->phase==HOME_CH5 || a->phase==TARGET_CH5 || a->phase==CARRY_CH5 ||
       a->phase==DROP_CH5 || a->phase==RETURN_CH5 || a->phase==DROP_TURN)return PICK_HEAVY_SETTLE_MS;
    return PICK_POSE_SETTLE_MS;
}
static void launch(MotorControl *s,uint32_t now) {
    PickCycle *a=&s->automatic; const uint16_t *pose=home_pose; unsigned mask=46;
    if(a->phase==TARGET_OTHERS || a->phase==TARGET_CH5) pose=a->pick;
    else if(a->phase>=DROP_TURN && a->phase<=GRIP_OPEN) pose=a->left?left_pose:right_pose;
    if(grip_phase(a->phase)) mask=1;
    else if(a->phase==HOME_CH5 || a->phase==TARGET_CH5 || a->phase==CARRY_CH5 || a->phase==DROP_CH5 || a->phase==RETURN_CH5) mask=16;
    else if(a->phase==DROP_TURN) mask=32;
    else if(a->phase==DROP_EXTEND) mask=14;
    else if(a->phase==RETURN_OTHERS) mask=47; /* Empty claw closes during final raised return. */
    uint16_t proposed[6]; memcpy(proposed,s->current,sizeof(proposed));
    for(unsigned i=0;i<6;i++) if(mask&(1u<<i)) proposed[i]=pose[i];
    if(a->phase==OPEN_HOME || a->phase==GRIP_OPEN) proposed[0]=PICK_OPEN_US;
    if(a->phase==HOME_CLOSE || a->phase==GRIP_CLOSE) proposed[0]=PICK_CLOSE_US;
    unsigned requested=grip_phase(a->phase)?PICK_GRIP_MOVE_MS:a->move_ms;
    if(a->phase==RETURN_OTHERS && requested<PICK_GRIP_MOVE_MS)requested=PICK_GRIP_MOVE_MS;
    a->phase_moves=memcmp(s->current,proposed,sizeof(proposed))!=0;
    /* Use the per-joint quintic limits, not the teaching tool's legacy 600 us/s
       average-rate floor. An unchanged phase needs neither motion nor settling. */
    requested=a->phase_moves?(unsigned)motion_duration(s->current,proposed,requested,s->config.rate_us_s):0u;
    memcpy(s->start,s->current,sizeof(s->start)); memcpy(s->target,proposed,sizeof(s->target));
    s->started_ms=now; s->duration_ms=requested; a->settling=false;
}
static const char *preflight(MotorControl *s,unsigned duration,uint32_t now) {
    if(!s->armed) return "DISARMED";
    if(s->automatic.busy || (s->duration_ms && now-s->started_ms<s->duration_ms)) return "BUSY";
    if(!pick_ready(s)) return "AUTO_CONFIG";
    return duration<20 || duration>60000?"RANGE":NULL;
}
const char *pick_start_batch(MotorControl *s,uint16_t job,uint16_t duration,float x,float y,float z,unsigned category,bool more_targets,uint32_t now) {
    PickCycle *a=&s->automatic;
    if(!job) return "JOB_ID";
    if(category!=1 && category!=2) return "CATEGORY";
    if(!isfinite(x)||!isfinite(y)||!isfinite(z)) return "COORDINATE";
    if(a->last_job_id==job) {
        if(x!=a->xyz[0] || y!=a->xyz[1] || z!=a->xyz[2] || duration!=a->last_job_duration || a->left!=(category==1) || more_targets!=a->last_job_more_targets) return "JOB_CONFLICT";
        return NULL;
    }
    if(a->last_job_id) { uint16_t delta=(uint16_t)(job-a->last_job_id); if(!delta || delta>=0x8000) return "JOB_OLD"; }
    const char *error=preflight(s,duration,now); if(error) return error;
    if(a->transfer_ready && (s->current[4]!=home_pose[4] || s->current[0]!=PICK_OPEN_US))return "TRANSFER_POSE";
    uint16_t pulse[6]; memcpy(pulse,s->current,sizeof(pulse)); pulse[0]=PICK_OPEN_US;
    if(!calibration_xyz(x,y,z,pulse)) return "OUTSIDE_MODEL";
    if(!in_range(s,pulse)) return "RANGE";
    memcpy(a->pick,pulse,sizeof(pulse)); a->xyz[0]=x; a->xyz[1]=y; a->xyz[2]=z;
    a->job_id=a->last_job_id=job; a->last_job_duration=a->move_ms=duration;
    a->left=category==1; a->homing=false; a->busy=true;
    a->more_targets=a->last_job_more_targets=more_targets;
    a->phase=a->transfer_ready?TARGET_OTHERS:(a->home_ready?OPEN_HOME:HOME_CLOSE);
    a->home_ready=false; a->transfer_ready=false; a->error="NONE";
    launch(s,now); return NULL;
}
const char *pick_start_category(MotorControl *s,uint16_t job,uint16_t duration,float x,float y,float z,unsigned category,uint32_t now) {
    return pick_start_batch(s,job,duration,x,y,z,category,false,now);
}
const char *pick_start(MotorControl *s,uint16_t job,uint16_t duration,float x,float y,float z,uint32_t now) {
    return pick_start_category(s,job,duration,x,y,z,x<PICK_SPLIT_X_CM?1u:2u,now);
}
const char *pick_home(MotorControl *s,uint16_t duration,uint32_t now) {
    const char *error=preflight(s,duration,now); if(error) return error;
    PickCycle *a=&s->automatic; a->move_ms=duration; a->homing=true; a->busy=true; a->home_ready=false;
    a->transfer_ready=a->more_targets=false; a->phase=HOME_CLOSE; a->error="NONE";
    launch(s,now); return NULL;
}
void pick_abort(MotorControl *s,const char *reason) {
    PickCycle *a=&s->automatic; if(a->busy) a->error=reason;
    a->busy=false; a->home_ready=false; a->settling=false; a->transfer_ready=a->more_targets=false;
}
void pick_tick(MotorControl *s,uint32_t now) {
    PickCycle *a=&s->automatic; if(!a->busy) return;
    if(!s->armed) { pick_abort(s,"LOCKED"); return; }
    if(s->duration_ms && now-s->started_ms<s->duration_ms) return;
    s->duration_ms=0;
    if(!a->settling) { a->settling=true; a->settled_at=now; return; }
    if(now-a->settled_at<settle(a)) return;
    if(a->phase==RETURN_CH5 && a->more_targets && !a->homing) {
        /* Handoff only after CH5 is fully commanded raised and settled.
           Keep CH1 open and the other joints at the drop pose. */
        a->busy=false; a->home_ready=false; a->transfer_ready=true; a->settling=false;
        a->completed_id=a->job_id; return;
    }
    a->phase++;
    if((a->homing && a->phase==OPEN_HOME) || a->phase==PHASE_COUNT) {
        a->busy=false; a->home_ready=true; a->transfer_ready=false; a->settling=false; if(!a->homing) a->completed_id=a->job_id; return;
    }
    launch(s,now);
}
const char *pick_stage(const MotorControl *s) {
    const PickCycle *a=&s->automatic;
    if(!a->busy) return a->error && strcmp(a->error,"NONE")?"ABORTED":a->transfer_ready?"NEXT_READY":"IDLE";
    return a->phase<PHASE_COUNT?stages[a->phase]:"INVALID";
}
uint32_t pick_remaining(const MotorControl *s,uint32_t now) {
    const PickCycle *a=&s->automatic; if(!a->busy) return 0;
    if(a->settling) { uint32_t elapsed=now-a->settled_at,ms=settle(a); return elapsed>=ms?0:ms-elapsed; }
    uint32_t elapsed=now-s->started_ms;
    return (elapsed>=s->duration_ms?0:s->duration_ms-elapsed)+settle(a);
}
