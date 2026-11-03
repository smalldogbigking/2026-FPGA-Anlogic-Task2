#ifndef ARM_CALIBRATION_H
#define ARM_CALIBRATION_H
#include <stdbool.h>
#include <stdint.h>
typedef struct {
    unsigned ready,point_count,plane_count,pose_count,revision,fixed_channel,fixed_pulse,grip_verified,gripper_channel,fit_mask;
    const char *project_id,*data_sha256,*unit;
} CalibrationInfo;
CalibrationInfo calibration_info(void);
bool calibration_xyz(float x,float y,float z,uint16_t out[6]);
bool calibration_pose(unsigned index,uint16_t out[6]);
bool calibration_grip(bool closed,uint16_t *out);
unsigned calibration_duration(const uint16_t current[6],const uint16_t target[6],unsigned requested);
const char *calibration_signature(void);
#endif
