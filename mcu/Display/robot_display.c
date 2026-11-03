#include "robot_display.h"
#include "vision_config.h"
#include <stdio.h>
#include <string.h>
#include <math.h>
#include <stdarg.h>
static void line(char out[22],const char *format,...) {
    va_list ap; va_start(ap,format); vsnprintf(out,22,format,ap); va_end(ap); out[21]=0;
}
static void decimal(char out[8],float x) {
    if(!isfinite(x) || fabsf(x)>1999) { strcpy(out,"---"); return; }
    unsigned value=(unsigned)floorf(fabsf(x)*10+0.5f),whole=value/10; char *p=out;
    if(x<0) *p++='-';
    if(whole>=1000) *p++=(char)('0'+whole/1000%10);
    if(whole>=100) *p++=(char)('0'+whole/100%10);
    if(whole>=10) *p++=(char)('0'+whole/10%10);
    *p++=(char)('0'+whole%10); *p++='.'; *p++=(char)('0'+value%10); *p=0;
}
static void target_line(char out[22],unsigned index,char status,unsigned shape,unsigned digit,unsigned category,float x,float y) {
    char a[8],b[8]; decimal(a,x); decimal(b,y);
    line(out,"%c%u%c%uC%u %s %s",status,index+1,shape==1?'O':shape==2?'S':'?',digit,category,a,b);
}
void robot_display_lines(const RobotControl *s,uint32_t now,char out[8][22]) {
    memset(out,0,8*22);
    if(s->state==ROBOT_MAP) {
        unsigned step=s->map_step<VISION_MAP_POINT_COUNT?s->map_step:VISION_MAP_POINT_COUNT-1; char x[8],y[8];
        line(out[0],"MAP %u/%u  SQUARE 3",step+1,VISION_MAP_POINT_COUNT);
        decimal(x,s->map_world[step][0]); decimal(y,s->map_world[step][1]); line(out[1],"CM %s %s",x,y);
        if(s->display_target_valid) {
            decimal(x,s->display_target.u); decimal(y,s->display_target.v); line(out[2],"PX %s %s",x,y);
            line(out[3],"S%u D%u C%u %s",s->display_target.shape,s->display_target.digit,s->display_target.category,s->marker_tracking?"FOUND":"WAIT");
        } else { line(out[2],"PX --- ---"); line(out[3],"TARGET --- WAIT"); }
        unsigned stable=s->marker_tracking?(unsigned)((now-s->marker_since)*100u/VISION_STABLE_MS):0; if(stable>100) stable=100;
        line(out[4],"STABLE %3u%%",stable);
        unsigned ms=s->recording?(unsigned)(now-s->sample_since):0; if(ms>9999) ms=9999;
        line(out[5],"REC %ums N=%u",ms,s->sample_count);
        if(s->sample_count) { decimal(x,s->sample_u/s->sample_count); decimal(y,s->sample_v/s->sample_count); line(out[6],"AVG %s %s",x,y); }
        else line(out[6],"NEED 500MS + 5 PKTS");
        line(out[7],"%s",s->message); return;
    }
    if(s->state==ROBOT_GRAB || s->state==ROBOT_COOLDOWN || (s->state==ROBOT_IDLE && s->batch_count)) {
        if(s->state==ROBOT_IDLE) line(out[0],"IDLE NOW%u DONE%u",s->packet_count,s->completed);
        else line(out[0],"%s LOCK%u DONE%u",robot_state_name(s->state),s->batch_count,s->completed);
        if(s->state==ROBOT_IDLE) line(out[1],"LAST BATCH / CM");
        else if(s->next_item<s->batch_count) {
            const RobotItem *t=s->batch+s->next_item;
            line(out[1],"#%u %c%u C%u %s",s->next_item+1,t->shape==1?'O':'S',t->digit,t->category,t->category==1?"LEFT":t->category==2?"RIGHT":"SKIP");
        } else line(out[1],"HOME / CLAW CLOSED");
        for(unsigned i=0;i<s->batch_count;i++) {
            const RobotItem *t=s->batch+i; static const char icons[]={'+','>','*','-','!'};
            target_line(out[i+2],i,t->status<=ITEM_BLOCKED?icons[t->status]:'?',t->shape,t->digit,t->category,t->x,t->y);
        }
        line(out[6],"%s",s->message);
        line(out[7],s->state==ROBOT_GRAB?"RX IGNORED / LOCKED":"+WAIT >NOW *OK -SKIP"); return;
    }
    line(out[0],"%s  N%u OK%u",robot_state_name(s->state),s->packet_count,robot_confirmed(s));
    line(out[1],"XY:CM O:CIRCLE S:SQR");
    unsigned at=0;
    for(unsigned i=0;i<4;i++) if(s->tracks[i].used) {
        const RobotTrack *q=s->tracks+i; float x=0,y=0;
        pixel_map_apply(&s->map,q->u,q->v,&x,&y);
        target_line(out[at+2],at,q->ready?'+':'?',q->shape,q->digit,q->category,x,y); at++;
    }
    if(s->state==ROBOT_REMOVE_MARKER) line(out[2],"REMOVE S3 THEN WAIT");
    if(s->state==ROBOT_STOP) { line(out[2],"HOLD PWM / NO RESUME"); line(out[3],"RESET TO RESUME"); }
    line(out[6],"%s",s->message);
    line(out[7],"RX:%s E:%lu",s->have_seq && now-s->last_rx<=VISION_LINK_MS?"OK":"WAIT",(unsigned long)s->errors);
}
/* Original compact 5x7 uppercase glyphs; 21 columns x 8 rows, no paging. */
typedef struct {char c;uint8_t bits[5];} Glyph;
static const Glyph font[]={
 {'0',{0x3e,0x51,0x49,0x45,0x3e}},{'1',{0,0x42,0x7f,0x40,0}},{'2',{0x42,0x61,0x51,0x49,0x46}},
 {'3',{0x21,0x41,0x45,0x4b,0x31}},{'4',{0x18,0x14,0x12,0x7f,0x10}},{'5',{0x27,0x45,0x45,0x45,0x39}},
 {'6',{0x3c,0x4a,0x49,0x49,0x30}},{'7',{1,0x71,9,5,3}},{'8',{0x36,0x49,0x49,0x49,0x36}},{'9',{6,0x49,0x49,0x29,0x1e}},
 {'A',{0x7e,0x11,0x11,0x11,0x7e}},{'B',{0x7f,0x49,0x49,0x49,0x36}},{'C',{0x3e,0x41,0x41,0x41,0x22}},
 {'D',{0x7f,0x41,0x41,0x22,0x1c}},{'E',{0x7f,0x49,0x49,0x49,0x41}},{'F',{0x7f,9,9,9,1}},
 {'G',{0x3e,0x41,0x49,0x49,0x7a}},{'H',{0x7f,8,8,8,0x7f}},{'I',{0,0x41,0x7f,0x41,0}},
 {'J',{0x20,0x40,0x41,0x3f,1}},{'K',{0x7f,8,0x14,0x22,0x41}},{'L',{0x7f,0x40,0x40,0x40,0x40}},
 {'M',{0x7f,2,0x0c,2,0x7f}},{'N',{0x7f,4,8,0x10,0x7f}},{'O',{0x3e,0x41,0x41,0x41,0x3e}},
 {'P',{0x7f,9,9,9,6}},{'Q',{0x3e,0x41,0x51,0x21,0x5e}},{'R',{0x7f,9,0x19,0x29,0x46}},
 {'S',{0x46,0x49,0x49,0x49,0x31}},{'T',{1,1,0x7f,1,1}},{'U',{0x3f,0x40,0x40,0x40,0x3f}},
 {'V',{0x1f,0x20,0x40,0x20,0x1f}},{'W',{0x3f,0x40,0x38,0x40,0x3f}},{'X',{0x63,0x14,8,0x14,0x63}},
 {'Y',{7,8,0x70,8,7}},{'Z',{0x61,0x51,0x49,0x45,0x43}},
 {'.',{0,0x60,0x60,0,0}},{',',{0,0x40,0x20,0,0}},{':',{0,0x36,0x36,0,0}},{'-',{8,8,8,8,8}},
 {'+',{8,8,0x3e,8,8}},{'>',{0,0x41,0x22,0x14,8}},{'*',{0x14,8,0x3e,8,0x14}},
 {'?',{2,1,0x51,9,6}},{'!',{0,0,0x5f,0,0}},{'/',{0x20,0x10,8,4,2}},
 {'#',{0x14,0x7f,0x14,0x7f,0x14}},{'%',{0x63,0x13,8,0x64,0x63}},{'=',{0x14,0x14,0x14,0x14,0x14}},
 {'_',{0x40,0x40,0x40,0x40,0x40}},{'(',{0,0x1c,0x22,0x41,0}},{')',{0,0x41,0x22,0x1c,0}}
};
void display_bitmap(const char lines[8][22],uint8_t pixels[1024]) {
    memset(pixels,0,1024);
    for(unsigned row=0;row<8;row++) for(unsigned col=0;col<21 && lines[row][col];col++) {
        char c=lines[row][col]; if(c>='a'&&c<='z') c=(char)(c-'a'+'A');
        for(unsigned j=0;j<sizeof(font)/sizeof(font[0]);j++) if(c==font[j].c) { memcpy(pixels+128*row+col*6,font[j].bits,5); break; }
    }
}
