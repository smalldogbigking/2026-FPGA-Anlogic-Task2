#include "stm32f1xx.h"
#include "robot_display.h"
#include "vision_config.h"
static uint8_t framebuffer[1024];
static bool connected,pending;
static unsigned segment;
static uint32_t last_try,last_step;
static void delay(void) { for(volatile unsigned i=0;i<12;i++) __NOP(); }
static void scl(bool high) { if(high) GPIOB->BSRR=1u<<6; else GPIOB->BRR=1u<<6; delay(); }
static void sda(bool high) { if(high) GPIOB->BSRR=1u<<7; else GPIOB->BRR=1u<<7; delay(); }
static bool clock_high(void) {
    scl(true); for(unsigned i=0;i<50;i++) { if(GPIOB->IDR&(1u<<6)) return true; delay(); } return false;
}
static void stop(void) { scl(false); sda(false); scl(true); sda(true); }
static bool byte(uint8_t x) {
    for(unsigned i=0;i<8;i++) { scl(false); sda((x&0x80)!=0); if(!clock_high()) return false; x<<=1; }
    scl(false); sda(true); if(!clock_high()) return false;
    bool ack=(GPIOB->IDR&(1u<<7))==0; scl(false); return ack;
}
static bool begin(uint8_t control) {
    sda(true); if(!clock_high()) { stop(); return false; }
    sda(false); scl(false);
    if(!byte(OLED_I2C_ADDRESS<<1) || !byte(control)) { stop(); return false; } return true;
}
static bool commands(const uint8_t *data,unsigned n) {
    if(!begin(0)) return false;
    for(unsigned i=0;i<n;i++) if(!byte(data[i])) { stop(); return false; }
    stop(); return true;
}
static bool configure(void) {
    static const uint8_t init[]={0xae,0xd5,0x80,0xa8,0x3f,0xd3,0x00,0x40,0x8d,0x14,0x20,0x02,0xa1,0xc8,0xda,0x12,0x81,0x7f,0xd9,0xf1,0xdb,0x40,0xa4,0xa6,0xaf};
    /* Nine clocks recover an interrupted I2C transaction, with bounded waits. */
    sda(true); for(unsigned i=0;i<9;i++) { scl(false); scl(true); } stop();
    return commands(init,sizeof(init));
}
void oled_init(void) {
    RCC->APB2ENR|=RCC_APB2ENR_IOPBEN;
    GPIOB->BSRR=(1u<<6)|(1u<<7);
    GPIOB->CRL=(GPIOB->CRL&~0xff000000u)|0x66000000u; /* 2MHz GPIO open-drain */
    connected=configure(); pending=false; last_try=last_step=0;
}
bool oled_connected(void) { return connected; }
void oled_present(const char lines[8][22]) { display_bitmap(lines,framebuffer); segment=0; pending=true; }
void oled_service(uint32_t now) {
    if(!connected) { if(now-last_try<1000) return; last_try=now; connected=configure(); return; }
    if(!pending || now-last_step<2) return;
    last_step=now; unsigned page=segment/4,col=(segment%4)*32+OLED_COLUMN_OFFSET;
    uint8_t cmd[3]={(uint8_t)(0xb0+page),(uint8_t)(col&15),(uint8_t)(0x10+(col>>4))};
    if(!commands(cmd,3) || !begin(0x40)) { connected=false; stop(); return; }
    for(unsigned i=0;i<32;i++) if(!byte(framebuffer[segment*32+i])) { connected=false; stop(); return; }
    stop(); segment++; if(segment==32) pending=false;
}
