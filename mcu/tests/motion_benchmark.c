/* Deterministic command timing only; never opens hardware or a serial port. */
#include "motor_control.h"
#include "board_config.h"
#include "pick_config.h"
#include "vision_config.h"
#include "calibration_samples.h"
#include <stdio.h>

int main(void) {
    const MotorConfig config={.period_us=BOARD_PWM_PERIOD_US,.min_us=BOARD_MIN_US,
        .max_us=BOARD_MAX_US,.initial_us=BOARD_INITIAL_US,.rate_us_s=BOARD_RATE_US_S,.configured=true};
    unsigned total=0,minimum=120000,maximum=0,count=0;
    printf("{\"hardware_tested\":false,\"tick_ms\":10,\"cycles\":[");
    for(unsigned point=0;point<31;point++) for(unsigned category=1;category<=2;category++) {
        MotorControl motor; motor_init(&motor,&config,(MotorHal){0});
        motor.armed=true; motor.output_started=true; motor.automatic.home_ready=true;
        const char *error=pick_start_category(&motor,1,VISION_POSE_MOVE_MS,
            reference_xyz[point][0],reference_xyz[point][1],0,category,0);
        if(error) { fprintf(stderr,"point %u: %s\n",point,error);return 1; }
        unsigned elapsed=0;
        while(motor.automatic.busy && elapsed<120000) { elapsed+=10;motor_tick(&motor,elapsed); }
        const uint16_t home[6]=PICK_HOME_US;
        if(motor.automatic.busy || motor.automatic.completed_id!=1) return 2;
        for(unsigned i=0;i<6;i++) if(motor.current[i]!=home[i]) return 3;
        printf("%s{\"point\":%u,\"category\":%u,\"ms\":%u}",count?",":"",point+1,category,elapsed);
        total+=elapsed;if(elapsed<minimum)minimum=elapsed;if(elapsed>maximum)maximum=elapsed;count++;
    }
    printf("],\"count\":%u,\"total_ms\":%u,\"mean_ms\":%.2f,\"min_ms\":%u,\"max_ms\":%u}\n",
        count,total,(double)total/count,minimum,maximum);
    return 0;
}
