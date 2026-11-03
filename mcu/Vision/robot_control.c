#include "robot_control.h"
#include "vision_config.h"
#include "calibration.h"
#include "pick_config.h"
#include <math.h>
#include <string.h>

static float distance2(float x,float y,float a,float b) { float dx=x-a,dy=y-b; return dx*dx+dy*dy; }
static void state(RobotControl *s,RobotState next,const char *message,uint32_t now) {
    s->state=next; s->state_since=now; s->message=message;
}
const char *robot_state_name(RobotState x) {
    static const char *const names[]={"HOME","MAP","REMOVE S3","IDLE","CONFIRM","PICK","SETTLE","STOP"};
    return (unsigned)x<8?names[x]:"INVALID";
}
static void clear_tracks(RobotControl *s,uint32_t now) {
    memset(s->tracks,0,sizeof(s->tracks)); s->scene_changed=now; s->last_any=now; s->packet_count=0;
}
static void marker_reset(RobotControl *s) {
    s->marker_tracking=false; s->recording=false; s->sample_count=0;
}
static bool vision_fresh(const RobotControl *s,uint32_t now) {
    return s->have_seq && now-s->last_rx<=VISION_LINK_MS && s->have_frame && now-s->last_frame_at<=VISION_SOURCE_MS;
}
void robot_pause(RobotControl *s,const char *reason) {
    if(s->state==ROBOT_GRAB && s->next_item<s->batch_count && s->event) s->event("sort_error",s->batch+s->next_item,s->next_item);
    pick_abort(s->motor,reason); s->motor->armed=false;
    s->motor->duration_ms=0;
    memcpy(s->motor->target,s->motor->current,sizeof(s->motor->target));
    memcpy(s->motor->start,s->motor->current,sizeof(s->motor->start));
    s->state=ROBOT_STOP; s->message=reason; s->flush_rx=true;
}
void robot_restart(RobotControl *s,bool remap,uint32_t now) {
    if(s->motor->automatic.busy || s->motor->duration_ms) return;
    if(remap) { memset(&s->map,0,sizeof(s->map)); memset(s->picked,0,sizeof(s->picked)); s->map_step=0; s->wait_move=false; }
    s->batch_count=s->next_item=s->completed=0;
    marker_reset(s); clear_tracks(s,now); s->have_seq=s->have_frame=false;
    s->home_settling=false;
    s->motor->armed=true; s->motor->output_started=true;
    s->motor->automatic.error="NONE";
    const char *error=pick_home(s->motor,VISION_POSE_MOVE_MS,now);
    if(error) { robot_pause(s,error); return; }
    state(s,ROBOT_HOME,"HOME CLOSED",now); s->flush_rx=true;
}
void robot_init(RobotControl *s,MotorControl *motor,RobotEvent event,uint32_t now) {
    static const float points[VISION_MAP_POINT_COUNT][2]=VISION_MAP_POINTS;
    memset(s,0,sizeof(*s)); s->motor=motor; s->event=event;
    memcpy(s->map_world,points,sizeof(points)); s->job=1;
    robot_restart(s,false,now);
}
void robot_link_error(RobotControl *s,uint32_t now) {
    s->errors++;
    if(s->state==ROBOT_GRAB || s->state==ROBOT_HOME || s->state==ROBOT_COOLDOWN) return;
    clear_tracks(s,now); marker_reset(s); s->have_seq=false; s->message="UART RESYNC";
}
static void mapping(RobotControl *s,const VisionPacket *p,uint32_t now) {
    const VisionTarget *marker=NULL; unsigned count=0;
    s->display_target_valid=p->count!=0;
    if(p->count) s->display_target=p->targets[0];
    for(unsigned i=0;i<p->count;i++) {
        const VisionTarget *t=p->targets+i;
        if((t->flags&7)==7 && t->shape==2 && t->digit==3) { marker=t; count++; }
    }
    if(count!=1) { marker_reset(s); s->message=count?"ONE S3 ONLY":"PLACE S3"; return; }
    s->display_target=*marker;
    if(s->wait_move) {
        unsigned previous=s->map_step-1;
        if(distance2(marker->u,marker->v,s->map_pixels[previous][0],s->map_pixels[previous][1])<VISION_MARKER_MOVE_PX*VISION_MARKER_MOVE_PX) {
            marker_reset(s); s->message="MOVE S3 TO POINT"; return;
        }
        s->wait_move=false;
    }
    if(!s->marker_tracking || now-s->marker_last>VISION_LINK_MS ||
       distance2(marker->u,marker->v,s->marker_u,s->marker_v)>VISION_JITTER_PX*VISION_JITTER_PX) {
        marker_reset(s); s->marker_tracking=true; s->marker_u=marker->u; s->marker_v=marker->v;
        s->marker_since=now; s->source_start=s->frame_steps;
    }
    s->marker_last=now;
    if(now-s->marker_since<VISION_STABLE_MS || s->frame_steps==s->source_start) { s->message="WAIT STABLE"; return; }
    if(!s->recording) {
        s->recording=true; s->sample_since=now; s->sample_u=s->sample_v=0; s->sample_count=0; s->sample_frame_start=s->frame_steps;
    }
    s->sample_count++; s->sample_u+=marker->u; s->sample_v+=marker->v; s->message="RECORD 0.5S";
    if(now-s->sample_since<VISION_SAMPLE_MS || s->sample_count<VISION_MIN_SAMPLES || s->frame_steps==s->sample_frame_start) return;
    s->map_pixels[s->map_step][0]=s->sample_u/s->sample_count; s->map_pixels[s->map_step][1]=s->sample_v/s->sample_count;
    s->map_step++; marker_reset(s);
    if(s->map_step<VISION_MAP_POINT_COUNT) { s->wait_move=true; s->message="MOVE S3 TO POINT"; return; }
    if(!pixel_map_fit(&s->map,(const float (*)[2])s->map_pixels,(const float (*)[2])s->map_world,VISION_MAP_POINT_COUNT)) {
        s->map_step=0; s->wait_move=false; s->message="BAD MAP RETRY"; return;
    }
    /* Existing PWM interpolation must support all selected physical points. */
    for(unsigned i=0;i<VISION_MAP_POINT_COUNT;i++) {
        uint16_t pwm[6]={0};
        if(!calibration_xyz(s->map_world[i][0],s->map_world[i][1],0,pwm)) { s->map.valid=false; s->map_step=0; s->message="MAP OUTSIDE MODEL"; return; }
    }
    s->remove_clear=false; state(s,ROBOT_REMOVE_MARKER,"REMOVE MARKER S3",now);
}
static bool suppressed(RobotControl *s,const VisionTarget *t) {
    for(unsigned i=0;i<4;i++) if(s->picked[i].used && distance2(t->u,t->v,s->picked[i].u,s->picked[i].v)<VISION_REMAIN_MATCH_PX*VISION_REMAIN_MATCH_PX) return true;
    return false;
}
static void update_tombstones(RobotControl *s,const VisionPacket *p,uint32_t now) {
    for(unsigned i=0;i<4;i++) if(s->picked[i].used) {
        bool present=false;
        for(unsigned j=0;j<p->count;j++) if((p->targets[j].flags&1) && distance2(p->targets[j].u,p->targets[j].v,s->picked[i].u,s->picked[i].v)<VISION_REMAIN_MATCH_PX*VISION_REMAIN_MATCH_PX) present=true;
        if(present) s->picked[i].missing=false;
        else if(!s->picked[i].missing) { s->picked[i].missing=true; s->picked[i].missing_since=now; }
        else if(now-s->picked[i].missing_since>=VISION_STABLE_MS) s->picked[i].used=false;
    }
}
static void confirming(RobotControl *s,const VisionPacket *p,uint32_t now) {
    update_tombstones(s,p,now);
    for(unsigned i=0;i<4;i++) s->tracks[i].seen=false;
    unsigned observed=0;
    /* Global nearest-pair matching prevents slot reordering from relabeling objects. */
    bool consumed[4]={false,false,false,false};
    for(unsigned pass=0;pass<4;pass++) {
        int best_track=-1,best_target=-1; float best=VISION_ASSOCIATE_PX*VISION_ASSOCIATE_PX;
        for(unsigned i=0;i<4;i++) if(s->tracks[i].used && !s->tracks[i].seen) {
            for(unsigned j=0;j<p->count;j++) if(!consumed[j] && (p->targets[j].flags&1) && !suppressed(s,p->targets+j)) {
                float d=distance2(s->tracks[i].u,s->tracks[i].v,p->targets[j].u,p->targets[j].v);
                if(d<best) { best=d; best_track=(int)i; best_target=(int)j; }
            }
        }
        if(best_track<0) break;
        RobotTrack *q=s->tracks+best_track; const VisionTarget *t=p->targets+best_target;
        unsigned category=(t->flags&7)==7?vision_category(t->shape,t->digit):0;
        bool reset=now-q->last_seen>VISION_LINK_MS || q->shape!=t->shape || q->digit!=t->digit || q->category!=category ||
            distance2(t->u,t->v,q->anchor_u,q->anchor_v)>VISION_JITTER_PX*VISION_JITTER_PX;
        if(reset) {
            q->samples=0; q->anchor_u=t->u; q->anchor_v=t->v; q->stable_since=now; q->frame_start=s->frame_steps; q->ready=false; s->scene_changed=now;
        }
        if(q->samples<1000) q->samples++;
        q->u+=((float)t->u-q->u)/q->samples; q->v+=((float)t->v-q->v)/q->samples;
        q->shape=t->shape; q->digit=t->digit; q->category=(uint8_t)category; q->seen=true; q->last_seen=now;
        q->ready=category && q->samples>=VISION_MIN_SAMPLES && now-q->stable_since>=VISION_STABLE_MS && s->frame_steps!=q->frame_start;
        consumed[best_target]=true; observed++;
    }
    for(unsigned j=0;j<p->count;j++) if(!consumed[j] && (p->targets[j].flags&1) && !suppressed(s,p->targets+j)) {
        const VisionTarget *t=p->targets+j; observed++;
        for(unsigned i=0;i<4;i++) if(!s->tracks[i].used) {
            RobotTrack *q=s->tracks+i; memset(q,0,sizeof(*q)); q->used=q->seen=true;
            q->u=q->anchor_u=t->u; q->v=q->anchor_v=t->v; q->shape=t->shape; q->digit=t->digit;
            q->category=(uint8_t)(((t->flags&7)==7)?vision_category(t->shape,t->digit):0);
            q->samples=1; q->stable_since=q->last_seen=now; q->frame_start=s->frame_steps; s->scene_changed=now; break;
        }
    }
    for(unsigned i=0;i<4;i++) {
        RobotTrack *q=s->tracks+i;
        if(q->used && !q->seen) {
            q->ready=false; s->scene_changed=now;
            if(now-q->last_seen>=VISION_TRACK_MISS_MS) memset(q,0,sizeof(*q));
        }
    }
    s->packet_count=(uint8_t)observed;
    if(observed) {
        s->last_any=now;
        bool changed=s->batch_count==0;
        for(unsigned i=0;i<4;i++) if(s->tracks[i].used && !s->tracks[i].ready) changed=true;
        if(s->state==ROBOT_IDLE && changed) { s->batch_count=0; state(s,ROBOT_CONFIRM,"WAIT STABLE",now); }
    }
}
void robot_observe(RobotControl *s,const VisionPacket *p,uint32_t now) {
    if(s->state==ROBOT_GRAB || s->state==ROBOT_HOME || s->state==ROBOT_COOLDOWN || s->state==ROBOT_STOP) { s->ignore_count++; return; }
    if(s->have_seq && now-s->last_rx>VISION_LINK_MS) { s->have_seq=false; clear_tracks(s,now); marker_reset(s); }
    if(s->have_seq) { uint16_t ds=(uint16_t)(p->seq-s->last_seq); if(!ds || ds>=0x8000) return; }
    s->last_seq=p->seq; s->have_seq=true; s->last_rx=now; s->packets++;
    if(!s->have_frame) { s->last_frame=p->frame; s->have_frame=true; s->last_frame_at=now; s->frame_steps++; }
    else {
        uint16_t df=(uint16_t)(p->frame-s->last_frame);
        if(df && df<0x8000) { s->last_frame=p->frame; s->last_frame_at=now; s->frame_steps++; }
        else if(df>=0x8000 && now-s->last_frame_at>VISION_SOURCE_MS) {
            s->last_frame=p->frame; s->last_frame_at=now; s->frame_steps++; clear_tracks(s,now); marker_reset(s);
        }
    }
    if(!vision_fresh(s,now)) { clear_tracks(s,now); marker_reset(s); s->message="WAIT SORT/SOURCE"; return; }
    if(s->state==ROBOT_MAP) { if(p->count) mapping(s,p,now); else { marker_reset(s); s->display_target_valid=false; s->message="PLACE S3"; } return; }
    if(s->state==ROBOT_REMOVE_MARKER) {
        bool present=false;
        for(unsigned i=0;i<p->count;i++) if((p->targets[i].flags&7)==7 && p->targets[i].shape==2 && p->targets[i].digit==3) present=true;
        if(present) s->remove_clear=false;
        else if(!s->remove_clear) { s->remove_clear=true; s->marker_since=now; }
        else if(now-s->marker_since>=VISION_STABLE_MS) { clear_tracks(s,now); state(s,ROBOT_IDLE,"WAIT TARGETS",now); }
        return;
    }
    confirming(s,p,now);
}
unsigned robot_confirmed(const RobotControl *s) { unsigned n=0; for(unsigned i=0;i<4;i++) if(s->tracks[i].used && s->tracks[i].ready) n++; return n; }
static void square_alert(RobotControl *s,const RobotItem *item,unsigned index,uint32_t now) {
    if(!s->event) return;
    unsigned slot=0; uint32_t oldest=0;
    for(unsigned i=0;i<4;i++) {
        RobotAlert *a=s->alerts+i;
        if(a->used && distance2(a->u,a->v,item->u,item->v)<VISION_REMAIN_MATCH_PX*VISION_REMAIN_MATCH_PX) {
            if(now-a->at<10000u) return;
            slot=i; break;
        }
        if(!a->used) { slot=i; oldest=0xffffffffu; }
        else if(oldest!=0xffffffffu && now-a->at>=oldest) { oldest=now-a->at; slot=i; }
    }
    s->alerts[slot].used=true; s->alerts[slot].u=item->u; s->alerts[slot].v=item->v; s->alerts[slot].at=now;
    s->event("square_alert",item,index);
}
static void freeze_batch(RobotControl *s,uint32_t now) {
    s->batch_count=0; s->completed=0; s->next_item=0;
    for(unsigned i=0;i<4;i++) if(s->tracks[i].used) {
        RobotTrack *q=s->tracks+i; RobotItem *item=s->batch+s->batch_count++;
        memset(item,0,sizeof(*item)); item->u=q->u; item->v=q->v; item->shape=q->shape; item->digit=q->digit; item->category=q->category;
        item->status=ITEM_WAIT; item->reason="READY";
        uint16_t pwm[6]={0};
        if(!pixel_map_apply(&s->map,item->u,item->v,&item->x,&item->y) || item->x<0 || item->x>VISION_X_MAX || item->y<0 || item->y>VISION_Y_MAX || !calibration_xyz(item->x,item->y,0,pwm)) {
            item->status=ITEM_BLOCKED; item->reason="OUTSIDE MODEL";
        } else if(item->category>=3) { item->status=ITEM_SKIP; item->reason=item->category==3?"MARKER":"SQUARE ALERT"; }
    }
    /* Lexicographic order: physical X ascending, then physical Y ascending. */
    for(unsigned i=1;i<s->batch_count;i++) {
        RobotItem item=s->batch[i]; unsigned j=i;
        while(j && (item.x<s->batch[j-1].x || (item.x==s->batch[j-1].x && item.y<s->batch[j-1].y))) { s->batch[j]=s->batch[j-1]; j--; }
        s->batch[j]=item;
    }
    for(unsigned i=0;i<s->batch_count;i++) for(unsigned j=i+1;j<s->batch_count;j++) {
        if(distance2(s->batch[i].x,s->batch[i].y,s->batch[j].x,s->batch[j].y)<VISION_NEIGHBOUR_CM*VISION_NEIGHBOUR_CM) {
            if(s->batch[i].status==ITEM_WAIT) { s->batch[i].status=ITEM_BLOCKED; s->batch[i].reason="TOO CLOSE"; }
            if(s->batch[j].status==ITEM_WAIT) { s->batch[j].status=ITEM_BLOCKED; s->batch[j].reason="TOO CLOSE"; }
        }
    }
    bool work=false;
    for(unsigned i=0;i<s->batch_count;i++) {
        if(s->batch[i].status==ITEM_WAIT) work=true;
        if(s->batch[i].category==4) square_alert(s,s->batch+i,i,now);
    }
    if(work) { state(s,ROBOT_GRAB,"BATCH LOCKED",now); s->flush_rx=true; }
    else { state(s,ROBOT_IDLE,"NO PICKABLE TARGET",now); }
}
static void grab_tick(RobotControl *s,uint32_t now) {
    MotorControl *m=s->motor;
    if(!m->armed || (m->automatic.error && strcmp(m->automatic.error,"NONE"))) { robot_pause(s,m->automatic.error?m->automatic.error:"MOTOR STOP"); return; }
    if(m->automatic.busy) { s->message=pick_stage(m); return; }
    if(s->next_item<s->batch_count && s->batch[s->next_item].status==ITEM_ACTIVE) {
        RobotItem *item=s->batch+s->next_item; item->status=ITEM_DONE; s->completed++;
        for(unsigned i=0;i<4;i++) if(!s->picked[i].used) { s->picked[i].used=true; s->picked[i].missing=false; s->picked[i].u=item->u; s->picked[i].v=item->v; break; }
        if(s->event) s->event("sort_done",item,s->next_item); s->next_item++;
    }
    while(s->next_item<s->batch_count && s->batch[s->next_item].status!=ITEM_WAIT) s->next_item++;
    if(s->next_item==s->batch_count) {
        /* Never re-enable vision until a final closed-home return has finished,
           including an unexpectedly shortened batch at a raised handoff. */
        if(!m->automatic.home_ready) {
            const char *error=pick_home(m,VISION_POSE_MOVE_MS,now);
            if(error)robot_pause(s,error);else s->message="FINAL HOME";
            return;
        }
        state(s,ROBOT_COOLDOWN,"HOME CLOSED",now); s->flush_rx=true; return;
    }
    RobotItem *item=s->batch+s->next_item;
    /* Classified entry explicitly overrides the legacy X<15 side policy. */
    s->job++; if(!s->job) s->job=1;
    bool more_targets=false;
    for(unsigned i=s->next_item+1;i<s->batch_count;i++)if(s->batch[i].status==ITEM_WAIT)more_targets=true;
    const char *error=pick_start_batch(m,s->job,VISION_POSE_MOVE_MS,item->x,item->y,0,item->category,more_targets,now);
    if(error) { robot_pause(s,error); return; }
    item->status=ITEM_ACTIVE; if(s->event) s->event("sort_started",item,s->next_item);
}
void robot_tick(RobotControl *s,uint32_t now) {
    MotorControl *m=s->motor;
    if(s->state==ROBOT_STOP) return;
    if(!m->armed) { robot_pause(s,"DISARMED"); return; }
    if(s->state==ROBOT_HOME) {
        if(m->automatic.busy) return;
        if(!m->automatic.home_ready) { robot_pause(s,"HOME FAILED"); return; }
        if(!s->home_settling) { s->home_settling=true; s->state_since=now; return; }
        if(now-s->state_since<VISION_HOME_SETTLE_MS) return;
        clear_tracks(s,now); s->have_seq=s->have_frame=false; s->flush_rx=true;
        state(s,s->map.valid?ROBOT_IDLE:ROBOT_MAP,s->map.valid?"WAIT TARGETS":"PLACE S3",now); return;
    }
    if(s->state==ROBOT_GRAB) { grab_tick(s,now); return; }
    if(s->state==ROBOT_COOLDOWN) {
        if(now-s->state_since<VISION_HOME_SETTLE_MS) return;
        clear_tracks(s,now); s->have_seq=s->have_frame=false; s->flush_rx=true;
        state(s,ROBOT_IDLE,"WAIT NEW OBSERVATION",now); return;
    }
    if(!vision_fresh(s,now)) {
        if(s->state==ROBOT_CONFIRM) { clear_tracks(s,now); state(s,ROBOT_IDLE,"VISION WAIT",now); }
        marker_reset(s); s->message=s->have_seq && now-s->last_rx<=VISION_LINK_MS?"WAIT SORT/SOURCE":"UART WAIT"; return;
    }
    if(s->state==ROBOT_CONFIRM) {
        if(now-s->last_any>=VISION_IDLE_MS) { clear_tracks(s,now); state(s,ROBOT_IDLE,"NO TARGETS",now); return; }
        unsigned n=0; bool all=true;
        for(unsigned i=0;i<4;i++) if(s->tracks[i].used) { n++; if(!s->tracks[i].ready || !s->tracks[i].seen || now-s->tracks[i].last_seen>VISION_LINK_MS) all=false; }
        s->message=all?"CONFIRMED":"WAIT STABLE/LABEL";
        if(n && all && n==s->packet_count && now-s->scene_changed>=VISION_SCENE_QUIET_MS) freeze_batch(s,now);
    }
}
