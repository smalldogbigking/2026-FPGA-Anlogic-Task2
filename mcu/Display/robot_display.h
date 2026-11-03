#ifndef ROBOT_DISPLAY_H
#define ROBOT_DISPLAY_H
#include "robot_control.h"
void robot_display_lines(const RobotControl *robot,uint32_t now,char lines[8][22]);
void display_bitmap(const char lines[8][22],uint8_t pixels[1024]);
void oled_init(void);
void oled_present(const char lines[8][22]);
void oled_service(uint32_t now);
bool oled_connected(void);
#endif
