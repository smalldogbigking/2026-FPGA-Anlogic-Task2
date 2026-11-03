#include "vision_protocol.h"
#include <string.h>
uint16_t vision_crc(const uint8_t *p,unsigned n) {
    uint16_t c=0xffff;
    while(n--) { c^=(uint16_t)*p++<<8;
        for(unsigned k=0;k<8;k++) c=(uint16_t)((c&0x8000)?((uint32_t)c<<1)^0x1021u:(uint32_t)c<<1);
    } return c;
}
static unsigned le16(const uint8_t *p) { return p[0]|((unsigned)p[1]<<8); }
static void drop(VisionParser *p) { --p->used; memmove(p->bytes,p->bytes+1,p->used); }
bool vision_feed(VisionParser *p,uint8_t byte,VisionPacket *out) {
    if(p->used==sizeof(p->bytes)) { drop(p); p->errors++; }
    p->bytes[p->used++]=byte;
    for(;;) {
        while(p->used && p->bytes[0]!=0xa5) drop(p);
        if(p->used<2) return false;
        if(p->bytes[1]!=0x5a) { drop(p); continue; }
        if(p->used<10) return false;
        unsigned count=p->bytes[8],size=12+9*count;
        if(p->bytes[2]!=1 || p->bytes[3]!=1 || count>4 || p->bytes[9]!=9*count) { drop(p); p->errors++; continue; }
        if(p->used<size) return false;
        if(vision_crc(p->bytes+2,size-4)!=le16(p->bytes+size-2)) { drop(p); p->errors++; continue; }
        VisionPacket packet={0}; unsigned slots=0; bool good=true;
        packet.seq=(uint16_t)le16(p->bytes+4); packet.frame=(uint16_t)le16(p->bytes+6); packet.count=(uint8_t)count;
        for(unsigned i=0;i<count;i++) {
            const uint8_t *r=p->bytes+10+9*i; VisionTarget *t=packet.targets+i;
            t->slot=r[0]; t->category=r[1]; t->shape=r[2]; t->digit=r[3];
            t->u=(uint16_t)le16(r+4); t->v=(uint16_t)le16(r+6); t->flags=r[8];
            if(t->slot>3 || t->category>4 || t->shape>3 || t->digit>5 || t->u>=1280 || t->v>=720 || (t->flags&0xf0)) good=false;
            if(t->slot<=3) { if(slots&(1u<<t->slot)) good=false; slots|=1u<<t->slot; }
        }
        p->used=(uint8_t)(p->used-size); memmove(p->bytes,p->bytes+size,p->used);
        if(!good) { p->errors++; continue; }
        *out=packet; p->packets++; return true;
    }
}
unsigned vision_category(unsigned shape,unsigned digit) {
    if(digit<1 || digit>5) return 0;
    if(shape==1) return (digit&1)?1u:2u;
    if(shape==2) return digit==3?3u:4u;
    return 0;
}
