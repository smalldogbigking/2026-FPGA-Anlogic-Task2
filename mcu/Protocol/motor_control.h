#ifndef MOTOR_CONTROL_H
#define MOTOR_CONTROL_H
#include <stdbool.h>
#include <stdint.h>
#include "pick_cycle.h"
/* Commanded PWM positions only. No PC commands, serial teaching or feedback. */
typedef struct {
    uint16_t period_us,min_us[6],max_us[6],initial_us[6],rate_us_s;
    bool configured;
} MotorConfig;
typedef struct { void (*write_pwm)(const uint16_t pulse_us[6]); } MotorHal;
typedef struct MotorControl {
    MotorConfig config; MotorHal hal;
    uint16_t current[6],target[6],start[6];
    uint32_t started_ms,duration_ms;
    bool armed,output_started,ready;
    PickCycle automatic;
} MotorControl;
void motor_init(MotorControl *motor,const MotorConfig *config,MotorHal hal);
void motor_tick(MotorControl *motor,uint32_t now);
#endif
