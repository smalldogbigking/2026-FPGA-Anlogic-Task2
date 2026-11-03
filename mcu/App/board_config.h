#ifndef BOARD_CONFIG_H
#define BOARD_CONFIG_H
#include "pick_config.h"
/* Autonomous firmware, using the supplied calibrated home pose with CH1 closed.
 * Boot enables PWM at this known command pose; physical starting position has
 * no feedback. These 500..3000 envelopes are inherited, not newly measured limits.
 * PB12 stop input latches a stop and retains the last PWM. Reset to resume.
 */
#define BOARD_SIX_TEST_PROFILE 1
#define BOARD_PWM_PERIOD_US 20000u
#define BOARD_RATE_US_S 2000u /* ceiling; per-joint motion limits also apply */
#define BOARD_MIN_US     {500,500,500,500,500,500}
#define BOARD_MAX_US     {3000,3000,3000,3000,3000,3000} /* user-selected test envelope, not measured limits */
#define BOARD_INITIAL_US PICK_HOME_US
/* CH1..6: PA0, PA1, PA2, PA3, PA6, PA7, identical to the original project.
 * FPGA RX=PB11/USART3; no UART TX or PC port. SSD1306 SCL=PB6 SDA=PB7. */
#endif
