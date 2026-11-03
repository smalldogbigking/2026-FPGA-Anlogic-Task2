#include "calibration.h"
#include "board_config.h"
#ifndef MODEL_HEADER
#define MODEL_HEADER "model_data.h"
#endif
#include MODEL_HEADER
#ifndef MODEL_CONTROL_SHA256
#define MODEL_CONTROL_SHA256 "UNAVAILABLE"
#endif
const char *calibration_signature(void){return MODEL_CONTROL_SHA256;}

CalibrationInfo calibration_info(void) {
    CalibrationInfo info={
        MODEL_READY && MODEL_PERIOD_US==BOARD_PWM_PERIOD_US,
        MODEL_POINT_COUNT,MODEL_PLANE_COUNT,MODEL_POSE_COUNT,MODEL_REVISION,
        MODEL_FIXED_CHANNEL,MODEL_FIXED_PULSE_US,MODEL_GRIP_VERIFIED,MODEL_GRIPPER_CHANNEL,MODEL_FIT_MASK,
        MODEL_PROJECT_ID,MODEL_DATA_SHA256,MODEL_UNIT
    };
    return info;
}
static bool expand(const uint16_t fitted[4],uint16_t out[6]) {
    if (!calibration_info().ready || MODEL_FIXED_CHANNEL<1 || MODEL_FIXED_CHANNEL>6 || MODEL_GRIPPER_CHANNEL<1 || MODEL_GRIPPER_CHANNEL>6 || MODEL_FIXED_CHANNEL==MODEL_GRIPPER_CHANNEL) return false;
    unsigned at=0;
    for (unsigned i=0;i<6;i++) {
        if(i+1==MODEL_GRIPPER_CHANNEL)continue;
        if(i+1!=MODEL_FIXED_CHANNEL && !(MODEL_FIT_MASK&(1u<<i)))return false;
        if(i+1!=MODEL_FIXED_CHANNEL && at>=4)return false;
        unsigned pulse=i+1==MODEL_FIXED_CHANNEL ? MODEL_FIXED_PULSE_US : fitted[at++];
        if (pulse<500 || pulse>3000) return false;
        out[i]=(uint16_t)pulse;
    }
    return at==4;
}
bool calibration_xyz(float x,float y,float z,uint16_t out[6]) {
    uint16_t fitted[4];
    if (!calibration_info().ready || !model_predict(x,y,z,fitted)) return false;
    return expand(fitted,out);
}
bool calibration_pose(unsigned index,uint16_t out[6]) {
    uint16_t fitted[4];
    if (!calibration_info().ready || !model_pose(index,fitted)) return false;
    return expand(fitted,out);
}
bool calibration_grip(bool closed,uint16_t *out) {
    if (!calibration_info().ready || !MODEL_GRIP_VERIFIED) return false;
    unsigned pulse=closed ? MODEL_GRIP_CLOSE_US : MODEL_GRIP_OPEN_US;
    if (pulse<500 || pulse>3000) return false;
    *out=(uint16_t)pulse;return true;
}
unsigned calibration_duration(const uint16_t current[6],const uint16_t target[6],unsigned requested) {
    unsigned maximum=0;
    for(unsigned i=0;i<6;i++) {
        unsigned d=target[i]>current[i] ? target[i]-current[i] : current[i]-target[i];
        if(d>maximum)maximum=d;
    }
    unsigned rate=MODEL_RATE_US_S;
    if(rate<1 || rate>BOARD_RATE_US_S)rate=BOARD_RATE_US_S;
    unsigned minimum=(maximum*1000u+rate-1u)/rate;
    return requested>minimum ? requested : minimum;
}
