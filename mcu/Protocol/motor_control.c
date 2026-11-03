#include "motor_control.h"
#include "motion_profile.h"
#include <string.h>
void motor_init(MotorControl *s,const MotorConfig *config,MotorHal hal) {
    memset(s,0,sizeof(*s)); s->config=*config; s->hal=hal;
    s->ready=config->configured && config->period_us>=10000 && config->period_us<=30000 &&
        config->rate_us_s>=1 && config->rate_us_s<=2000;
    for(unsigned i=0;i<6;i++) {
        if(config->min_us[i]<500 || config->max_us[i]>3000 || config->min_us[i]>=config->max_us[i] ||
           config->initial_us[i]<config->min_us[i] || config->initial_us[i]>config->max_us[i]) s->ready=false;
        s->current[i]=s->target[i]=s->start[i]=config->initial_us[i];
    }
}
void motor_tick(MotorControl *s,uint32_t now) {
    uint32_t elapsed=now-s->started_ms;
    for(unsigned i=0;i<6;i++) {
        if(!s->duration_ms || elapsed>=s->duration_ms) s->current[i]=s->target[i];
        else {
            float t=motion_blend((float)elapsed/(float)s->duration_ms);
            float value=s->start[i]+((float)s->target[i]-s->start[i])*t;
            s->current[i]=(uint16_t)(value+0.5f);
        }
    }
    if(s->output_started && s->hal.write_pwm) s->hal.write_pwm(s->current);
    pick_tick(s,now);
}
