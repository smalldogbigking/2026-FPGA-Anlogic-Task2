#include "stm32f1xx.h"

/* HSI/2 * 16 = nominal 64MHz, no external crystal assumed.
 * APB1=32MHz, TIM2/3=64MHz, APB2=64MHz. Measure actual timing on board.
 * SystemInit runs before C data initialization: no RAM state is used here.
 */
uint32_t SystemCoreClock = 64000000u;
const uint8_t AHBPrescTable[16] = {0,0,0,0,0,0,0,0,1,2,3,4,6,7,8,9};
const uint8_t APBPrescTable[8] = {0,0,0,0,1,2,3,4};

void SystemInit(void) {
    RCC->CR |= RCC_CR_HSION;
    while (!(RCC->CR & RCC_CR_HSIRDY)) {}
    RCC->CFGR &= ~RCC_CFGR_SW;
    while ((RCC->CFGR & RCC_CFGR_SWS) != RCC_CFGR_SWS_HSI) {}
    RCC->CR &= ~(RCC_CR_PLLON | RCC_CR_CSSON | RCC_CR_HSEON);
    while (RCC->CR & RCC_CR_PLLRDY) {}
    FLASH->ACR = FLASH_ACR_PRFTBE | FLASH_ACR_LATENCY_2;
    RCC->CFGR = RCC_CFGR_PPRE1_DIV2 | RCC_CFGR_ADCPRE_DIV8 | RCC_CFGR_PLLMULL16;
    RCC->CR |= RCC_CR_PLLON;
    while (!(RCC->CR & RCC_CR_PLLRDY)) {}
    RCC->CFGR |= RCC_CFGR_SW_PLL;
    while ((RCC->CFGR & RCC_CFGR_SWS) != RCC_CFGR_SWS_PLL) {}
    SCB->VTOR = FLASH_BASE;
}

void SystemCoreClockUpdate(void) {
    /* This application never changes its configured clock tree at runtime. */
    SystemCoreClock = 64000000u;
}
