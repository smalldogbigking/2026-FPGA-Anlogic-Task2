#ifndef PICK_CYCLE_H
#define PICK_CYCLE_H
#include <stdbool.h>
#include <stdint.h>
struct MotorControl;
#define PICK_CONTINUOUS_BATCH_API 1
typedef struct {
    uint16_t job_id, completed_id, last_job_id, last_job_duration, move_ms;
    uint16_t pick[6];
    float xyz[3];
    uint32_t settled_at;
    unsigned phase;
    bool busy, home_ready, settling, homing, left, phase_moves;
    bool transfer_ready, more_targets, last_job_more_targets;
    const char *error;
} PickCycle;
bool pick_ready(const struct MotorControl *s);
const char *pick_start(struct MotorControl *s,uint16_t job,uint16_t move_ms,float x,float y,float z,uint32_t now);
const char *pick_start_category(struct MotorControl *s,uint16_t job,uint16_t move_ms,float x,float y,float z,unsigned category,uint32_t now);
/* more_targets keeps the empty claw open at raised CH5 after dropping.
   The next job may approach directly; the final job returns closed to home. */
const char *pick_start_batch(struct MotorControl *s,uint16_t job,uint16_t move_ms,float x,float y,float z,unsigned category,bool more_targets,uint32_t now);
const char *pick_home(struct MotorControl *s,uint16_t move_ms,uint32_t now);
void pick_tick(struct MotorControl *s,uint32_t now);
void pick_abort(struct MotorControl *s,const char *reason);
const char *pick_stage(const struct MotorControl *s);
uint32_t pick_remaining(const struct MotorControl *s,uint32_t now);
#endif
