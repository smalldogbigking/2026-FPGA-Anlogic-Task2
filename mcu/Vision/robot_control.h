#ifndef ROBOT_CONTROL_H
#define ROBOT_CONTROL_H
#include "vision_protocol.h"
#include "pixel_map.h"
#include "motor_control.h"
#include "vision_config.h"
typedef enum {ROBOT_HOME,ROBOT_MAP,ROBOT_REMOVE_MARKER,ROBOT_IDLE,ROBOT_CONFIRM,ROBOT_GRAB,ROBOT_COOLDOWN,ROBOT_STOP} RobotState;
typedef enum {ITEM_WAIT,ITEM_ACTIVE,ITEM_DONE,ITEM_SKIP,ITEM_BLOCKED} ItemState;
typedef struct {
    bool used,seen,ready; uint8_t shape,digit,category; uint16_t samples;
    float u,v,anchor_u,anchor_v; uint32_t stable_since,last_seen,frame_start;
} RobotTrack;
typedef struct {
    float u,v,x,y; uint8_t shape,digit,category,status; const char *reason;
} RobotItem;
typedef struct {bool used; float u,v; uint32_t missing_since; bool missing;} RobotTombstone;
typedef struct {bool used; float u,v; uint32_t at;} RobotAlert;
typedef void (*RobotEvent)(const char *kind,const RobotItem *item,unsigned index);
typedef struct {
    MotorControl *motor; RobotEvent event; RobotState state; PixelMap map;
    RobotTrack tracks[4]; RobotItem batch[4]; RobotTombstone picked[4];
    RobotAlert alerts[4];
    float map_pixels[VISION_MAP_POINT_COUNT][2],map_world[VISION_MAP_POINT_COUNT][2],marker_u,marker_v,sample_u,sample_v;
    uint32_t state_since,last_rx,last_frame_at,frame_steps,scene_changed,last_any,marker_since,sample_since,sample_frame_start,marker_last;
    uint32_t source_start,ignore_count,packets,errors,alert_at;
    uint16_t last_seq,last_frame,job,sample_count;
    uint8_t map_step,batch_count,next_item,completed,packet_count;
    VisionTarget display_target;
    bool have_seq,have_frame,marker_tracking,recording,wait_move,remove_clear,flush_rx,alerted,display_target_valid,home_settling;
    const char *message;
} RobotControl;
void robot_init(RobotControl *s,MotorControl *motor,RobotEvent event,uint32_t now);
void robot_observe(RobotControl *s,const VisionPacket *packet,uint32_t now);
void robot_tick(RobotControl *s,uint32_t now);
void robot_pause(RobotControl *s,const char *reason);
void robot_restart(RobotControl *s,bool remap,uint32_t now);
void robot_link_error(RobotControl *s,uint32_t now);
const char *robot_state_name(RobotState state);
unsigned robot_confirmed(const RobotControl *s);
#endif
