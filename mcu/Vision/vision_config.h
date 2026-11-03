#ifndef VISION_CONFIG_H
#define VISION_CONFIG_H
/* Centimetres, same paper origin and axes as the preserved motor model. */
#define VISION_MAP_POINT_COUNT 5u
#define VISION_MAP_POINTS {{10.0f,10.0f},{20.0f,10.0f},{15.0f,20.0f},{5.0f,20.0f},{25.0f,20.0f}}
#define VISION_X_MAX 30.0f
#define VISION_Y_MAX 26.0f
#define VISION_LINK_MS 500u
/* FRAME_ID is the oldest classified ROI timestamp, not the UART cadence. */
#define VISION_SOURCE_MS 2500u
#define VISION_STABLE_MS 1000u
#define VISION_SAMPLE_MS 500u
#define VISION_MIN_SAMPLES 5u
#define VISION_SCENE_QUIET_MS 1000u
#define VISION_TRACK_MISS_MS 500u
#define VISION_IDLE_MS 2000u
#define VISION_HOME_SETTLE_MS 1000u
#define VISION_JITTER_PX 10.0f
#define VISION_ASSOCIATE_PX 45.0f
#define VISION_MARKER_MOVE_PX 45.0f
#define VISION_NEIGHBOUR_CM 3.0f
#define VISION_REMAIN_MATCH_PX 22.0f
#define VISION_POSE_MOVE_MS 300u
/* OLED: 4-pin SSD1306, software I2C PB6=SCL, PB7=SDA, external pullups to 3V3. */
#define OLED_I2C_ADDRESS 0x3cu
#define OLED_COLUMN_OFFSET 0u /* SH1106-compatible module: set 2 and review init. */
#endif
