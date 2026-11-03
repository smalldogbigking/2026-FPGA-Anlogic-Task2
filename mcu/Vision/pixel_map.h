#ifndef PIXEL_MAP_H
#define PIXEL_MAP_H
#include <stdbool.h>
typedef struct { float a[6]; bool valid; } PixelMap;
/* All count point pairs contribute to a least-squares planar affine fit. */
bool pixel_map_fit(PixelMap *map,const float pixels[][2],const float world[][2],unsigned count);
bool pixel_map_apply(const PixelMap *map,float u,float v,float *x,float *y);
#endif
