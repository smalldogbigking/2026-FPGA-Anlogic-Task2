/* 31 four-point subsets x 16 left/right patterns. Fake command timing only. */
#include "motor_control.h"
#include "board_config.h"
#include "pick_config.h"
#include "vision_config.h"
#include "calibration_samples.h"
#include <stdio.h>
#include <string.h>

int main(void) {
    const MotorConfig config={.period_us=BOARD_PWM_PERIOD_US,.min_us=BOARD_MIN_US,.max_us=BOARD_MAX_US,
        .initial_us=BOARD_INITIAL_US,.rate_us_s=BOARD_RATE_US_S,.configured=true};
    unsigned total=0,count=0;
    printf("{\"tick_ms\":10,\"objects_per_batch\":4,\"hardware_tested\":false,\"batches\":[");
    for(unsigned start=0;start<31;start++) for(unsigned pattern=0;pattern<16;pattern++) {
        unsigned indices[4];for(unsigned i=0;i<4;i++)indices[i]=(start+7*i)%31;
        for(unsigned i=1;i<4;i++) for(unsigned j=i;j>0;j--) {
            const float *a=reference_xyz[indices[j]],*b=reference_xyz[indices[j-1]];
            if(a[0]>b[0] || (a[0]==b[0] && a[1]>=b[1]))break;
            unsigned t=indices[j];indices[j]=indices[j-1];indices[j-1]=t;
        }
        MotorControl motor;motor_init(&motor,&config,(MotorHal){0});
        motor.armed=true;motor.output_started=true;motor.automatic.home_ready=true;
        unsigned elapsed=0;
        for(unsigned item=0;item<4;item++) {
            const float *xyz=reference_xyz[indices[item]];unsigned category=(pattern>>item)&1?1:2;
            const char *error;
#ifdef PICK_CONTINUOUS_BATCH_API
            error=pick_start_batch(&motor,(uint16_t)(item+1),VISION_POSE_MOVE_MS,xyz[0],xyz[1],0,category,item<3,elapsed);
#else
            error=pick_start_category(&motor,(uint16_t)(item+1),VISION_POSE_MOVE_MS,xyz[0],xyz[1],0,category,elapsed);
#endif
            if(error){fprintf(stderr,"start %u pattern %u item %u: %s\n",start,pattern,item,error);return 1;}
            while(motor.automatic.busy && elapsed<240000){
                elapsed+=10;motor_tick(&motor,elapsed);
#ifdef PICK_CONTINUOUS_BATCH_API
                const char *stage=pick_stage(&motor);
                if(!strcmp(stage,"TARGET_OTHERS") && (motor.current[4]!=2191 || motor.target[4]!=2191 || motor.current[0]!=PICK_OPEN_US))return 6;
                if(!strcmp(stage,"TARGET_CH5"))for(unsigned j=1;j<6;j++)if(j!=4 && motor.current[j]!=motor.automatic.pick[j])return 7;
                if(!strcmp(stage,"RETURN_CH5") && (motor.current[3]!=1598 || motor.target[0]!=PICK_OPEN_US))return 8;
                if(!strcmp(stage,"RETURN_HOME_CLOSED") && (motor.current[4]!=2191 || item!=3))return 9;
#endif
            }
            if(motor.automatic.busy || motor.automatic.completed_id!=item+1)return 2;
#ifdef PICK_CONTINUOUS_BATCH_API
            if(item<3 && (!motor.automatic.transfer_ready || motor.automatic.home_ready ||
                motor.current[0]!=PICK_OPEN_US || motor.current[4]!=2191))return 3;
#endif
        }
        const uint16_t home[6]=PICK_HOME_US;
        for(unsigned i=0;i<6;i++)if(motor.current[i]!=home[i])return 4;
        if(!motor.automatic.home_ready)return 5;
        printf("%s{\"start\":%u,\"pattern\":%u,\"ms\":%u}",count?",":"",start,pattern,elapsed);
        total+=elapsed;count++;
    }
    printf("],\"count\":%u,\"mean_batch_ms\":%.2f}\n",count,(double)total/count);
    return 0;
}
