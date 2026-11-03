#include "motion_profile.h"
#include <math.h>
float motion_blend(float t) {
    if(t<=0) return 0; if(t>=1) return 1;
    return t*t*t*(10.0f+t*(-15.0f+6.0f*t));
}
uint32_t motion_duration(const uint16_t a[6],const uint16_t b[6],uint32_t requested,unsigned ceiling) {
    /* Command-space limits: us/s and us/s^2. CH5/6 have larger inertia.
       Quintic peak velocity=1.875*d/T, acceleration=5.774*d/T^2. */
    static const float speed[6]={1700,1100,1200,1050,850,800};
    static const float accel[6]={9000,5000,5000,4200,2800,2500};
    float ms=(float)requested;
    for(unsigned i=0;i<6;i++) {
        float d=fabsf((float)b[i]-a[i]),v=fminf(speed[i],(float)ceiling);
        if(v<1) v=1;
        ms=fmaxf(ms,1875.0f*d/v);
        ms=fmaxf(ms,1000.0f*sqrtf(5.774f*d/accel[i]));
    }
    return (uint32_t)ceilf(ms);
}
