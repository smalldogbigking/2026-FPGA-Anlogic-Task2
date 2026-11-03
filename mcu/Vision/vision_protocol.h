#ifndef VISION_PROTOCOL_H
#define VISION_PROTOCOL_H
#include <stdbool.h>
#include <stdint.h>
#define VISION_MAX_TARGETS 4u
typedef struct { uint8_t slot,category,shape,digit; uint16_t u,v; uint8_t flags; } VisionTarget;
typedef struct { uint16_t seq,frame; uint8_t count; VisionTarget targets[4]; } VisionPacket;
typedef struct { uint8_t bytes[48],used; uint32_t errors,packets; } VisionParser;
uint16_t vision_crc(const uint8_t *data,unsigned length);
bool vision_feed(VisionParser *parser,uint8_t byte,VisionPacket *packet);
/* Local policy: wire shape 1=circle, 2=square. Incoming class is telemetry only. */
unsigned vision_category(unsigned shape,unsigned digit);
#endif
