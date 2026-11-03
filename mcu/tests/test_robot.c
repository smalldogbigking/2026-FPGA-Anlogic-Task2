#include "robot_control.h"
#include "robot_display.h"
#include "vision_config.h"
#include "motion_profile.h"
#include "calibration.h"
#include "board_config.h"
#include "pick_config.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <stdlib.h>
#include "calibration_samples.h"
static unsigned checks,writes,started,done,alerts;
#define CHECK(x) do { checks++; if(!(x)) { fprintf(stderr,"FAIL line %u: %s\n",__LINE__,#x); exit(1); } } while(0)
static MotorControl motor; static RobotControl robot; static uint32_t now; static uint16_t seq,frame;
static uint16_t output[6];
static void pwm(const uint16_t p[6]) { writes++; for(unsigned i=0;i<6;i++) { CHECK(p[i]>=500 && p[i]<=3000); output[i]=p[i]; } }
static void event(const char *kind,const RobotItem *t,unsigned i) {
    (void)i; CHECK(t->digit>=1 && t->digit<=5);
    if(!strcmp(kind,"sort_started")) started++; if(!strcmp(kind,"sort_done")) done++; if(!strcmp(kind,"square_alert")) alerts++;
}
static void advance(unsigned ms) {
    for(unsigned i=0;i<ms;i+=10) { now+=10; motor_tick(&motor,now); robot_tick(&robot,now); }
}
static void init(void) {
    const MotorConfig c={.period_us=20000,.min_us=BOARD_MIN_US,.max_us=BOARD_MAX_US,.initial_us=BOARD_INITIAL_US,.rate_us_s=2000,.configured=true};
    motor_init(&motor,&c,(MotorHal){pwm}); now=0; seq=frame=0; started=done=alerts=0;
    robot_init(&robot,&motor,event,now);
    advance(6000); CHECK(robot.state==ROBOT_MAP); CHECK(motor.armed); CHECK(output[0]==PICK_CLOSE_US); CHECK(output[4]==2191); CHECK(output[5]==1683);
}
static VisionTarget target(unsigned slot,unsigned shape,unsigned digit,unsigned u,unsigned v) {
    VisionTarget t={(uint8_t)slot,(uint8_t)vision_category(shape,digit),(uint8_t)shape,(uint8_t)digit,(uint16_t)u,(uint16_t)v,15}; return t;
}
static void observe(VisionPacket *p) {
    p->seq=++seq; p->frame=++frame; robot_observe(&robot,p,now); robot_tick(&robot,now);
}
static void packets(VisionPacket *p,unsigned count) { for(unsigned i=0;i<count;i++) { advance(100); observe(p); } }
static void dump_display(const char *name);
static void map_robot(void) {
    init();
    static bool shown[2];
    const unsigned coordinates[VISION_MAP_POINT_COUNT][2]={{300,300},{500,300},{400,500},{200,500},{600,500}};
    for(unsigned point=0;point<VISION_MAP_POINT_COUNT;point++) {
        char lines[8][22],header[22];robot_display_lines(&robot,now,lines);
        snprintf(header,sizeof(header),"MAP %u/5  SQUARE 3",point+1);CHECK(!strcmp(lines[0],header));
        if(point==3) CHECK(!strcmp(lines[1],"CM 5.0 20.0"));
        if(point==4) CHECK(!strcmp(lines[1],"CM 25.0 20.0"));
        VisionPacket p={0}; p.count=1; p.targets[0]=target(0,2,3,coordinates[point][0],coordinates[point][1]);
        unsigned start_step=robot.map_step;
        for(unsigned i=0;i<40 && robot.map_step==start_step;i++) {
            p.targets[0].u=(uint16_t)(coordinates[point][0]+(i%3)-1); packets(&p,1);
            if(point>=3 && i==1 && !shown[point-3]) {
                dump_display(point==3?"oled_mapping_4":"oled_mapping_5");shown[point-3]=true;
            }
        }
        CHECK(robot.map_step==point+1);
        if(point+1<VISION_MAP_POINT_COUNT) {
            CHECK(robot.state==ROBOT_MAP && !robot.map.valid);
            packets(&p,6); CHECK(robot.map_step==point+1); CHECK(!robot.recording);
        }
    }
    CHECK(robot.map.valid); CHECK(robot.state==ROBOT_REMOVE_MARKER);
    float x,y; CHECK(pixel_map_apply(&robot.map,500,400,&x,&y)); CHECK(fabsf(x-20)<.1f && fabsf(y-15)<.1f);
    VisionPacket empty={0}; packets(&empty,13); CHECK(robot.state==ROBOT_IDLE);
}
static void dump_display(const char *name) {
    char lines[8][22],file[160];uint8_t pixels[1024];
    robot_display_lines(&robot,now,lines); display_bitmap(lines,pixels);
    snprintf(file,sizeof(file),"tests/%s.pgm",name); FILE *f=fopen(file,"wb"); CHECK(f!=NULL);
    fprintf(f,"P5\n128 64\n255\n");
    for(unsigned y=0;y<64;y++) for(unsigned x=0;x<128;x++) fputc((pixels[(y/8)*128+x]>>(y%8))&1?255:0,f);
    fclose(f);
    snprintf(file,sizeof(file),"tests/%s.txt",name); f=fopen(file,"wb"); CHECK(f!=NULL);
    for(unsigned i=0;i<8;i++) { CHECK(strlen(lines[i])<=21); fprintf(f,"%s\n",lines[i]); } fclose(f);
}
static void parser_tests(void) {
    const uint8_t vector[]={0xa5,0x5a,1,1,0x34,0x12,0x70,4,2,0x12,0,1,1,3,0x80,2,0x40,1,15,1,3,2,3,0xf0,0,0xa0,0,7,0xb7,7};
    VisionParser parser={0}; VisionPacket p; unsigned received=0;
    CHECK(vision_crc(vector+2,sizeof(vector)-4)==0x07b7);
    for(unsigned i=0;i<100;i++) CHECK(!vision_feed(&parser,0xff,&p));
    for(unsigned i=0;i<sizeof(vector);i++) if(vision_feed(&parser,vector[i],&p)) received++;
    CHECK(received==1 && p.count==2 && p.seq==0x1234 && p.frame==0x0470);
    CHECK(p.targets[0].digit==3 && p.targets[0].u==640 && p.targets[1].shape==2);
    uint8_t broken[sizeof(vector)]; memcpy(broken,vector,sizeof(vector)); broken[18]^=1;
    for(unsigned i=0;i<sizeof(vector);i++) CHECK(!vision_feed(&parser,broken[i],&p));
    for(unsigned i=0;i<sizeof(vector);i++) if(vision_feed(&parser,vector[i],&p)) received++;
    CHECK(received==2 && parser.errors>=1);
    memcpy(broken,vector,sizeof(vector)); broken[19]=0; unsigned crc=vision_crc(broken+2,sizeof(broken)-4);
    broken[28]=(uint8_t)crc; broken[29]=(uint8_t)(crc>>8);
    for(unsigned i=0;i<sizeof(broken);i++) CHECK(!vision_feed(&parser,broken[i],&p));
    for(unsigned d=1;d<=5;d++) { CHECK(vision_category(1,d)==(d&1?1u:2u)); CHECK(vision_category(2,d)==(d==3?3u:4u)); }
    CHECK(vision_category(1,0)==0 && vision_category(3,4)==0);
    uint8_t heartbeat[]={0xa5,0x5a,1,1,1,0,1,0,0,0,0,0};
    crc=vision_crc(heartbeat+2,8);heartbeat[10]=(uint8_t)crc;heartbeat[11]=(uint8_t)(crc>>8);
    for(unsigned i=0;i<sizeof(heartbeat);i++) if(vision_feed(&parser,heartbeat[i],&p)) received++;
    CHECK(p.count==0 && received==3);
}
static void mapping_tests(void) {
    PixelMap m; const float p[VISION_MAP_POINT_COUNT][2]={{300,300},{500,300},{400,500},{200,500},{600,500}},w[VISION_MAP_POINT_COUNT][2]=VISION_MAP_POINTS;
    CHECK(pixel_map_fit(&m,p,w,VISION_MAP_POINT_COUNT)); float x,y;
    CHECK(pixel_map_apply(&m,100,100,&x,&y)); CHECK(fabsf(x)<.001f && fabsf(y)<.001f);
    CHECK(pixel_map_fit(&m,p,w,3)); /* Exact three-point affine case remains valid. */
    const float bad[VISION_MAP_POINT_COUNT][2]={{1,1},{2,2},{3,3},{4,4},{5,5}};
    CHECK(!pixel_map_fit(&m,bad,w,VISION_MAP_POINT_COUNT)); CHECK(!m.valid);
    CHECK(!pixel_map_fit(&m,p,w,2) && !m.valid);
    /* Each appended point must affect the least-squares solution. Independent
       closed-form coefficients: centered U/V covariance is diagonal here. */
    for(unsigned added=3;added<5;added++) {
        float shifted[VISION_MAP_POINT_COUNT][2];memcpy(shifted,w,sizeof(shifted));shifted[added][0]+=1;
        CHECK(pixel_map_fit(&m,p,(const float (*)[2])shifted,VISION_MAP_POINT_COUNT));
        CHECK(fabsf(m.a[0]-(added==3?.048f:.052f))<.000001f);
        CHECK(fabsf(m.a[1]-1.0f/600.0f)<.000001f);
        CHECK(pixel_map_apply(&m,400,420,&x,&y) && fabsf(x-15.2f)<.0001f && fabsf(y-16)<.0001f);
    }
    /* Rotation, skew and a reversed pixel axis must map an independent point. */
    float skew[VISION_MAP_POINT_COUNT][2];
    for(unsigned i=0;i<VISION_MAP_POINT_COUNT;i++) {
        skew[i][0]=700-12*w[i][0]+3*w[i][1];skew[i][1]=80+2*w[i][0]+15*w[i][1];
    }
    CHECK(pixel_map_fit(&m,(const float (*)[2])skew,w,VISION_MAP_POINT_COUNT));
    CHECK(pixel_map_apply(&m,602.5f,367.5f,&x,&y) && fabsf(x-12.5f)<.001f && fabsf(y-17.5f)<.001f);
    skew[4][0]=NAN;CHECK(!pixel_map_fit(&m,(const float (*)[2])skew,w,VISION_MAP_POINT_COUNT) && !m.valid);
    CHECK(!pixel_map_fit(&m,p,bad,VISION_MAP_POINT_COUNT) && !m.valid); /* World points collinear. */
    for(unsigned i=0;i<VISION_MAP_POINT_COUNT;i++) {skew[i][0]=p[i][0];skew[i][1]=100+.001f*w[i][1];}
    CHECK(!pixel_map_fit(&m,(const float (*)[2])skew,w,VISION_MAP_POINT_COUNT) && !m.valid);
    map_robot();
    init(); VisionPacket p0={0};p0.count=1;p0.targets[0]=target(0,2,3,300,300);
    for(unsigned i=0;i<40;i++) { advance(100); p0.seq=++seq; p0.frame=7; robot_observe(&robot,&p0,now); robot_tick(&robot,now); }
    CHECK(robot.map_step==0); CHECK(!robot.map.valid); /* New SEQ cannot thaw a frozen source. */
    init(); packets(&p0,6); dump_display("oled_mapping");
}
static void phase_check(void) {
    const char *phase=pick_stage(&motor);
    if(!strcmp(phase,"TARGET_OTHERS")) { CHECK(motor.target[4]==2191 && motor.target[0]==PICK_OPEN_US); }
    if(!strcmp(phase,"TARGET_CH5")) { CHECK(motor.current[2]==motor.automatic.pick[2] && motor.current[5]==motor.automatic.pick[5]); }
    if(!strcmp(phase,"CARRY_HOME_CH5")) { CHECK(motor.target[4]==2191 && motor.target[0]==PICK_CLOSE_US); }
    if(!strcmp(phase,"CARRY_HOME_OTHERS")) { CHECK(motor.current[4]==2191 && motor.target[0]==PICK_CLOSE_US); }
    if(!strcmp(phase,"DROP_TURN")) { CHECK(motor.target[2]==2157 && motor.target[3]==1098 && motor.target[4]==2191 && motor.target[0]==PICK_CLOSE_US); }
    if(!strcmp(phase,"DROP_EXTEND")) { CHECK(motor.current[5]==(motor.automatic.left?2456:1005) && motor.target[4]==2191); }
    if(!strcmp(phase,"DROP_CH5")) { CHECK(motor.current[3]==1598 && motor.target[4]==1270); }
    if(!strcmp(phase,"RETURN_CH5")) { CHECK(motor.target[4]==2191 && motor.target[0]==PICK_OPEN_US && motor.current[3]==1598); }
    if(!strcmp(phase,"RETURN_HOME_CLOSED")) { CHECK(motor.current[4]==2191 && motor.target[0]==PICK_CLOSE_US); }
}
static void batch_tests(void) {
    map_robot();
    VisionPacket p={0}; p.count=4;
    p.targets[0]=target(0,1,3,500,400); p.targets[1]=target(1,1,2,300,400);
    p.targets[2]=target(2,2,3,400,500); p.targets[3]=target(3,2,4,600,400);
    /* Deliberately wrong wire class; policy must use shape+digit. */
    for(unsigned i=0;i<4;i++) p.targets[i].category=3;
    for(unsigned k=0;k<20 && robot.state!=ROBOT_GRAB;k++) {
        for(unsigned i=0;i<4;i++) { p.targets[i].slot=(uint8_t)((i+k)%4); p.targets[i].v=(uint16_t)((i==2?500:400)+(k%3)-1); }
        packets(&p,1);
    }
    CHECK(robot.state==ROBOT_GRAB && robot.batch_count==4);
    CHECK(robot.batch[0].digit==2 && robot.batch[0].category==2);
    CHECK(robot.batch[1].shape==2 && robot.batch[1].status==ITEM_SKIP);
    CHECK(robot.batch[2].category==1 && robot.batch[3].category==4);
    CHECK(robot.batch[0].x<robot.batch[1].x && robot.batch[1].x<robot.batch[2].x);
    RobotItem locked[4];memcpy(locked,robot.batch,sizeof(locked));
    unsigned guard=0; const char *previous=""; unsigned opened=0,returned=0;bool handed_off=false;
    while(robot.state==ROBOT_GRAB && guard++<20000) {
        advance(10);
        if(guard%10==0) {
            VisionPacket spoof={0};spoof.count=1;spoof.targets[0]=target(0,1,5,100,100);observe(&spoof);robot_link_error(&robot,now);
        }
        for(unsigned i=0;i<4;i++) {
            CHECK(robot.batch[i].u==locked[i].u && robot.batch[i].v==locked[i].v);
            CHECK(robot.batch[i].shape==locked[i].shape && robot.batch[i].digit==locked[i].digit && robot.batch[i].category==locked[i].category);
        }
        if(motor.automatic.busy) {
            phase_check();
            if(strcmp(previous,pick_stage(&motor))) {
                previous=pick_stage(&motor);
                if(!strcmp(previous,"OPEN_HOME"))opened++;
                if(!strcmp(previous,"RETURN_HOME_CLOSED"))returned++;
                CHECK(strcmp(previous,"FINAL_CLOSE") && strcmp(previous,"HOME_CLOSE"));
                if(robot.completed==1 && !strcmp(previous,"TARGET_OTHERS")) {
                    CHECK(motor.start[0]==PICK_OPEN_US && motor.start[4]==2191 && motor.start[3]==1598 && motor.start[5]==1005);
                    handed_off=true;
                }
            }
        }
        if(robot.completed==0 && motor.automatic.busy) CHECK(!motor.automatic.left); /* Even at x<15 goes RIGHT. */
        if(robot.completed==1 && motor.automatic.busy) CHECK(motor.automatic.left); /* Odd at x>=15 goes LEFT. */
        if(guard==100) dump_display("oled_grabbing");
    }
    CHECK(guard<20000 && robot.state==ROBOT_COOLDOWN); CHECK(started==2 && done==2 && alerts==1);
    CHECK(opened==1 && returned==1 && handed_off); CHECK(output[0]==PICK_CLOSE_US && output[4]==2191 && output[5]==1683);
    dump_display("oled_completed");
    advance(1200); CHECK(robot.state==ROBOT_IDLE);
    packets(&p,25); CHECK(started==2); CHECK(robot.state!=ROBOT_GRAB); /* Old picked locations remain suppressed. */
}
static void absence_tests(void) {
    map_robot(); VisionPacket p={0};p.count=1;p.targets[0]=target(0,1,1,300,400);
    packets(&p,5); CHECK(robot.state==ROBOT_CONFIRM); dump_display("oled_confirming");
    VisionPacket empty={0};packets(&empty,25);CHECK(robot.state==ROBOT_IDLE && started==0);
    /* One new observation then link silence never starts a task. */
    packets(&p,1);advance(1000); CHECK(robot.state==ROBOT_IDLE && started==0);
    map_robot();p.targets[0].flags=1;packets(&p,30);CHECK(robot.state==ROBOT_CONFIRM && started==0);
    map_robot();p.targets[0]=target(0,1,1,300,400);p.count=2;p.targets[1]=target(1,1,2,330,400);
    packets(&p,20); CHECK(started==0 && robot.state!=ROBOT_GRAB); /* 1.5cm neighbours blocked. */
    map_robot();p.count=1;p.targets[0]=target(0,1,1,1200,600);packets(&p,20);CHECK(started==0); /* Out of physical/model range. */
    map_robot(); p.targets[0]=target(0,1,1,300,400);
    for(unsigned i=0;i<20;i++) { p.targets[0].u=(uint16_t)(300+(i%4)*12);packets(&p,1); }
    CHECK(started==0); /* Motion restarts the spatial stability window. */
    map_robot();p.count=2;p.targets[0]=target(0,2,1,300,400);p.targets[1]=target(1,2,5,500,400);
    packets(&p,20);CHECK(started==0 && alerts==2);packets(&p,20);CHECK(alerts==2);
}
static void control_and_motion_tests(void) {
    init(); CHECK(motor.armed);
    robot_pause(&robot,"LOCAL STOP"); CHECK(robot.state==ROBOT_STOP && !motor.armed);
    uint16_t held[6];memcpy(held,output,sizeof(held));advance(3000);CHECK(!memcmp(held,output,sizeof(held)));
    robot_restart(&robot,false,now);advance(6000);CHECK(robot.state==ROBOT_MAP && motor.armed);
    float last=-1;
    for(unsigned i=0;i<=1000;i++) { float s=motion_blend(i/1000.0f);CHECK(s>=last-.000001f && s>=0 && s<=1.000001f); last=s; }
    CHECK(motion_blend(0)==0 && motion_blend(1)==1);
    uint16_t a[6]={1500,1500,1500,1500,1500,1500},b[6]={1500,1500,1500,1500,2500,2500};
    unsigned ms=motion_duration(a,b,20,2000);CHECK(ms<3750);
    for(unsigned j=4;j<6;j++) {float velocity=1875.0f*1000/ms,accel=5.774f*1000*1000000/((float)ms*ms); CHECK(velocity<=(j==4?850.001f:800.001f) && accel<=(j==4?2800.01f:2500.01f));}
    uint16_t pulse[6]={1600};CHECK(calibration_xyz(10,10,0,pulse));CHECK(!calibration_xyz(10,10,1,pulse));CHECK(!calibration_xyz(0,0,0,pulse));
    for(unsigned i=0;i<31;i++) {
        CHECK(calibration_xyz(reference_xyz[i][0],reference_xyz[i][1],reference_xyz[i][2],pulse));
        CHECK(pulse[0]==1600 && pulse[1]==1382);
        for(unsigned j=0;j<4;j++) CHECK(abs((int)pulse[j+2]-reference_pwm[i][j])<=1);
    }
    map_robot(); VisionPacket p={0};p.count=1;p.targets[0]=target(0,1,2,300,400);
    seq=frame=65534; robot.have_seq=robot.have_frame=false;
    packets(&p,5); CHECK(robot.last_seq==3 && robot.last_frame==3); CHECK(robot.state==ROBOT_CONFIRM);
    unsigned samples=robot.tracks[0].samples; robot_observe(&robot,&p,now); CHECK(robot.tracks[0].samples==samples);
    /* Same X: Y must order the frozen batch, independently of incoming slot. */
    map_robot();p.count=2;p.targets[0]=target(0,1,2,400,500);p.targets[1]=target(1,1,1,400,350);
    for(unsigned i=0;i<20 && robot.state!=ROBOT_GRAB;i++) packets(&p,1);
    CHECK(robot.state==ROBOT_GRAB && robot.batch[0].y<robot.batch[1].y);
    advance(1200); robot_pause(&robot,"TEST STOP"); uint16_t snapshot[6];memcpy(snapshot,output,sizeof(snapshot));
    advance(4000);CHECK(robot.state==ROBOT_STOP && !memcmp(snapshot,output,sizeof(snapshot)));
    robot_restart(&robot,false,now);advance(15000);CHECK(robot.state==ROBOT_IDLE && robot.map.valid && output[0]==PICK_CLOSE_US);
}
static void tuned_motion_tests(void) {
    /* Runtime CH1 tuning must work without changing the preserved model values. */
    init();uint16_t original_open,original_close;
    CHECK(calibration_grip(false,&original_open) && calibration_grip(true,&original_close));
    CHECK(original_open==1000 && original_close==1600);
    CHECK(PICK_OPEN_US==1000 && PICK_CLOSE_US==1500 && pick_ready(&motor));
    MotorControl local;MotorConfig config=motor.config;
    config.min_us[0]=1100;motor_init(&local,&config,(MotorHal){0});
    CHECK(local.ready && !pick_ready(&local)); /* Opening must obey the board envelope. */
    config=motor.config;motor_init(&local,&config,(MotorHal){0});local.armed=true;
    CHECK(pick_home(&local,VISION_POSE_MOVE_MS,0)==NULL);
    CHECK(local.duration_ms==0 && pick_remaining(&local,0)==0);
    unsigned at=0;
    while(local.automatic.busy && at<100) {at+=10;motor_tick(&local,at);}
    CHECK(!local.automatic.busy && local.automatic.home_ready && at<100);
    /* Check actual quintic peak bounds for each joint, small/large travel and
       a reduced board ceiling. Requested times remain minimum segment times. */
    const float speed[6]={1700,1100,1200,1050,850,800};
    const float accel[6]={9000,5000,5000,4200,2800,2500};
    const unsigned distances[]={1,50,650,1000};
    for(unsigned joint=0;joint<6;joint++) for(unsigned d=0;d<4;d++) for(unsigned cap=0;cap<2;cap++) {
        uint16_t from[6]={1500,1500,1500,1500,1500,1500},to[6];memcpy(to,from,sizeof(to));
        to[joint]=(uint16_t)(1500+distances[d]);unsigned ceiling=cap?400:BOARD_RATE_US_S;
        unsigned ms=motion_duration(from,to,20,ceiling);
        double seconds=ms/1000.0,delta=distances[d];
        CHECK(ms>=20 && 1.875*delta/seconds<=fmin(speed[joint],ceiling)+.001);
        CHECK(5.774*delta/(seconds*seconds)<=accel[joint]+.01);
        CHECK(motion_duration(from,to,5000,ceiling)>=5000);
    }
}
static void frozen_batch(unsigned layout,unsigned pattern) {
    init();robot.state=ROBOT_GRAB;robot.batch_count=4;robot.next_item=robot.completed=0;
    const float xy[4][2]={{5,20},{10,10},{20,10},{25,20}};
    for(unsigned i=0;i<4;i++) {
        RobotItem *t=robot.batch+i;memset(t,0,sizeof(*t));t->x=xy[i][0];t->y=xy[i][1];
        t->u=100+20*t->x;t->v=100+20*t->y;t->shape=1;t->digit=(pattern>>i)&1?1:2;t->category=t->digit==1?1:2;t->status=ITEM_WAIT;
    }
    if(layout==1){robot.batch[1].status=ITEM_SKIP;robot.batch[2].status=ITEM_BLOCKED;}
    if(layout==2){robot.batch[1].status=ITEM_SKIP;robot.batch[2].status=ITEM_BLOCKED;robot.batch[3].status=ITEM_SKIP;}
}
static void continuous_tests(void) {
    /* Every side pattern plus skip/blocked positions and a single pickable tail. */
    for(unsigned layout=0;layout<3;layout++)for(unsigned pattern=0;pattern<16;pattern++) {
        frozen_batch(layout,pattern);unsigned opened=0,returns=0,last_done=0,guard=0;const char *previous="";
        unsigned expected=layout==0?4:layout==1?2:1;
        while(robot.state==ROBOT_GRAB && guard++<15000) {
            advance(10);
            if(motor.automatic.busy) {
                phase_check();const char *stage=pick_stage(&motor);
                if(strcmp(stage,previous)) {
                    if(!strcmp(stage,"OPEN_HOME"))opened++;
                    if(!strcmp(stage,"RETURN_HOME_CLOSED"))returns++;
                    CHECK(strcmp(stage,"HOME_CLOSE") && strcmp(stage,"FINAL_CLOSE"));previous=stage;
                }
            }
            if(robot.completed!=last_done && robot.completed<expected) {
                CHECK(motor.current[0]==PICK_OPEN_US && motor.current[4]==2191);
                CHECK(motor.current[3]==1598 && !strcmp(pick_stage(&motor),"TARGET_OTHERS"));
                CHECK(returns==0 && opened==1);last_done=robot.completed;
            }
            if(guard%10==0){VisionPacket spoof={0};observe(&spoof);robot_link_error(&robot,now);}
        }
        CHECK(guard<15000 && robot.state==ROBOT_COOLDOWN && robot.completed==expected);
        CHECK(opened==1 && returns==1 && started==expected && done==expected);
        const uint16_t home[6]=PICK_HOME_US;CHECK(!memcmp(motor.current,home,sizeof(home)) && motor.automatic.home_ready);
    }
    /* Stop during drop lift, at the raised handoff itself, and during next XY.
       Pause must hold PWM, clear permission to continue, and never self-resume. */
    for(unsigned stop=0;stop<3;stop++) {
        frozen_batch(1,5);unsigned guard=0;bool hit=false;
        while(guard++<10000 && !hit) {
            now+=10;motor_tick(&motor,now);
            const char *stage=pick_stage(&motor);
            hit=stop==0?!strcmp(stage,"RETURN_CH5"):stop==1?motor.automatic.transfer_ready:
                robot.completed==1 && !strcmp(stage,"TARGET_OTHERS");
            if(!hit)robot_tick(&robot,now);
        }
        CHECK(hit);robot_pause(&robot,"CONTINUOUS STOP");uint16_t held[6];memcpy(held,output,sizeof(held));
        advance(2000);CHECK(robot.state==ROBOT_STOP && !motor.automatic.transfer_ready && !memcmp(held,output,sizeof(held)));
    }
    /* If the planned remainder is cancelled internally, finish a closed-home
       return before cooldown; this cannot be triggered by changing vision. */
    frozen_batch(1,0);unsigned guard=0;
    while(motor.automatic.completed_id==0 && guard++<10000){now+=10;motor_tick(&motor,now);if(motor.automatic.busy || !motor.automatic.transfer_ready)robot_tick(&robot,now);}
    CHECK(motor.automatic.transfer_ready);robot.batch[3].status=ITEM_SKIP;robot_tick(&robot,now);
    CHECK(robot.state==ROBOT_GRAB && motor.automatic.busy && motor.automatic.homing);
    advance(10000);CHECK(robot.state==ROBOT_IDLE && motor.automatic.home_ready && output[0]==PICK_CLOSE_US);
    /* Batch continuation is part of job identity, and an invalid next point
       must not move an already raised empty claw. */
    frozen_batch(1,0);MotorControl local=motor;local.hal.write_pwm=NULL;
    CHECK(pick_start_batch(&local,10,300,5,20,0,1,true,0)==NULL);
    CHECK(!strcmp(pick_start_batch(&local,10,300,5,20,0,1,false,0),"JOB_CONFLICT"));
    unsigned at=0;while(local.automatic.busy && at<60000){at+=10;motor_tick(&local,at);}
    CHECK(local.automatic.transfer_ready);uint16_t held[6];memcpy(held,local.current,sizeof(held));
    CHECK(!strcmp(pick_start_batch(&local,11,300,0,0,0,1,false,at),"OUTSIDE_MODEL"));CHECK(!memcmp(held,local.current,sizeof(held)));
    local.current[4]=2000;CHECK(!strcmp(pick_start_batch(&local,11,300,10,10,0,1,false,at),"TRANSFER_POSE"));
}
int main(void) {
    parser_tests();mapping_tests();batch_tests();absence_tests();control_and_motion_tests();tuned_motion_tests();continuous_tests();
    printf("PASS %u checks, real calibrated model, fake PWM only; no serial/hardware access.\n",checks);
    return 0;
}
