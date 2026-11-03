#include "stm32f1xx.h"
#include "board_config.h"
#include "motor_control.h"
#include "robot_control.h"
#include "robot_display.h"
#include <stddef.h>

static MotorControl motor;
static RobotControl robot;
static VisionParser parser;
static volatile uint32_t milliseconds;
static bool pwm_started;
typedef struct {
    volatile unsigned head,tail,fault; uint8_t data[512];
} RxRing;
static RxRing vision_rx;
void SysTick_Handler(void) { milliseconds++; }
static void pin(GPIO_TypeDef *gpio,unsigned n,unsigned mode) {
    volatile uint32_t *reg=n<8?&gpio->CRL:&gpio->CRH; unsigned shift=(n&7u)*4;
    *reg=(*reg&~(15u<<shift))|((uint32_t)mode<<shift);
}
static void timer_init(TIM_TypeDef *timer,bool four) {
    timer->CR1=timer->CCER=0; timer->PSC=63; timer->ARR=BOARD_PWM_PERIOD_US-1;
    timer->CCR1=timer->CCR2=timer->CCR3=timer->CCR4=0;
    timer->CCMR1=(6u<<4)|TIM_CCMR1_OC1PE|(6u<<12)|TIM_CCMR1_OC2PE;
    if(four) timer->CCMR2=(6u<<4)|TIM_CCMR2_OC3PE|(6u<<12)|TIM_CCMR2_OC4PE;
    timer->CR1=TIM_CR1_ARPE; timer->EGR=TIM_EGR_UG;
}
static void uart_init(USART_TypeDef *uart,unsigned clock,IRQn_Type irq) {
    uart->CR1=uart->CR2=uart->CR3=0;
    uart->BRR=(clock+115200u/2)/115200u;
    NVIC_SetPriority(irq,2); NVIC_EnableIRQ(irq);
    uart->CR1=USART_CR1_UE|USART_CR1_RE|USART_CR1_RXNEIE; /* receive only */
}
static void board_init(void) {
    RCC->APB2ENR|=RCC_APB2ENR_AFIOEN|RCC_APB2ENR_IOPAEN|RCC_APB2ENR_IOPBEN;
    RCC->APB1ENR|=RCC_APB1ENR_TIM2EN|RCC_APB1ENR_TIM3EN|RCC_APB1ENR_USART3EN;
    (void)RCC->APB2ENR;
    AFIO->MAPR&=~(AFIO_MAPR_TIM2_REMAP|AFIO_MAPR_TIM3_REMAP|AFIO_MAPR_USART3_REMAP);
    const unsigned pins[]={0,1,2,3,6,7};
    for(unsigned i=0;i<6;i++) { GPIOA->BRR=1u<<pins[i]; pin(GPIOA,pins[i],2); }
    timer_init(TIM2,true); timer_init(TIM3,false);
    pin(GPIOB,11,8); GPIOB->BSRR=1u<<11;
    uart_init(USART3,32000000u,USART3_IRQn);
    /* Optional latching stop input PB12 to GND, using an internal pull-up. */
    pin(GPIOB,12,8); GPIOB->BSRR=1u<<12;
    if(SysTick_Config(SystemCoreClock/1000u)) while(1) {}
}
static void uart_irq(USART_TypeDef *uart,RxRing *rx) {
    uint32_t sr=uart->SR;
    if(sr&(USART_SR_RXNE|USART_SR_ORE|USART_SR_FE|USART_SR_NE|USART_SR_PE)) {
        uint8_t b=(uint8_t)uart->DR;
        if(sr&(USART_SR_ORE|USART_SR_FE|USART_SR_NE|USART_SR_PE)) rx->fault=1;
        else if(sr&USART_SR_RXNE) {
            unsigned next=(rx->head+1u)%sizeof(rx->data);
            if(next==rx->tail) rx->fault=1;
            else { rx->data[rx->head]=b; __DMB(); rx->head=next; }
        }
    }
}
void USART3_IRQHandler(void) { uart_irq(USART3,&vision_rx); }
static bool take(RxRing *rx,uint8_t *out) {
    if(rx->tail==rx->head) return false; __DMB();
    *out=rx->data[rx->tail]; rx->tail=(rx->tail+1u)%sizeof(rx->data); return true;
}
static void write_pwm(const uint16_t p[6]) {
    TIM2->CCR1=p[0]; TIM2->CCR2=p[1]; TIM2->CCR3=p[2]; TIM2->CCR4=p[3]; TIM3->CCR1=p[4]; TIM3->CCR2=p[5];
    if(!pwm_started) {
        TIM2->EGR=TIM_EGR_UG; TIM3->EGR=TIM_EGR_UG; TIM2->CNT=TIM3->CNT=0;
        TIM2->CCER=TIM_CCER_CC1E|TIM_CCER_CC2E|TIM_CCER_CC3E|TIM_CCER_CC4E; TIM3->CCER=TIM_CCER_CC1E|TIM_CCER_CC2E;
        const unsigned pins[]={0,1,2,3,6,7}; for(unsigned i=0;i<6;i++) pin(GPIOA,pins[i],0xa);
        TIM2->CR1|=TIM_CR1_CEN; TIM3->CR1|=TIM_CR1_CEN; pwm_started=true;
    }
}
static void flush_vision(void) {
    uint32_t saved=__get_PRIMASK(); __disable_irq();
    vision_rx.tail=vision_rx.head; vision_rx.fault=0; parser.used=0;
    __set_PRIMASK(saved); robot.flush_rx=false;
}
int main(void) {
    const MotorConfig config={.period_us=BOARD_PWM_PERIOD_US,.min_us=BOARD_MIN_US,.max_us=BOARD_MAX_US,
        .initial_us=BOARD_INITIAL_US,.rate_us_s=BOARD_RATE_US_S,.configured=BOARD_SIX_TEST_PROFILE!=0};
    const MotorHal hal={write_pwm};
    motor_init(&motor,&config,hal); board_init(); oled_init();
    robot_init(&robot,&motor,NULL,milliseconds);
    uint32_t last_tick=milliseconds-1,last_display=milliseconds-200;
    for(;;) {
        uint32_t now=milliseconds;
        if(!(GPIOB->IDR&(1u<<12)) && robot.state!=ROBOT_STOP) robot_pause(&robot,"STOP INPUT");
        if(robot.flush_rx) flush_vision();
        if(vision_rx.fault) { flush_vision(); robot_link_error(&robot,now); }
        uint8_t byte;
        if(robot.state!=ROBOT_STOP && !motor.armed) robot_pause(&robot,"OPERATOR HOLD");
        for(unsigned budget=0;budget<256 && take(&vision_rx,&byte);budget++) {
            VisionPacket packet;
            if(vision_feed(&parser,byte,&packet)) robot_observe(&robot,&packet,now);
        }
        if(now!=last_tick) { last_tick=now; motor_tick(&motor,now); robot_tick(&robot,now); }
        if(now-last_display>=200u) {
            char lines[8][22]; last_display=now; robot.errors+=parser.errors; parser.errors=0;
            robot_display_lines(&robot,now,lines); oled_present((const char (*)[22])lines);
        }
        oled_service(now);
    }
}
