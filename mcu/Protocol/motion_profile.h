#ifndef MOTION_PROFILE_H
#define MOTION_PROFILE_H
#include <stdint.h>
float motion_blend(float t);
uint32_t motion_duration(const uint16_t from[6],const uint16_t to[6],uint32_t requested,unsigned ceiling);
#endif
