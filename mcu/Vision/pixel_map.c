#include "pixel_map.h"
#include <math.h>
bool pixel_map_fit(PixelMap *m,const float p[][2],const float w[][2],unsigned count) {
    m->valid=false;
    if(count<3) return false;
    float pc[2]={0},wc[2]={0};
    for(unsigned i=0;i<count;i++) for(unsigned j=0;j<2;j++) {
        if(!isfinite(p[i][j])||!isfinite(w[i][j])) return false;
        pc[j]+=p[i][j];wc[j]+=w[i][j];
    }
    for(unsigned j=0;j<2;j++) {pc[j]/=count;wc[j]/=count;}
    /* Centering removes the large pixel origin from the normal equations.
       Solve the remaining 2x2 covariance system for each world axis. */
    float uu=0,uv=0,vv=0,cross[2][2]={{0}},pixel_area=0,world_area=0;
    for(unsigned i=0;i<count;i++) {
        float u=p[i][0]-pc[0],v=p[i][1]-pc[1];
        uu+=u*u;uv+=u*v;vv+=v*v;
        for(unsigned axis=0;axis<2;axis++) {
            float d=w[i][axis]-wc[axis];cross[axis][0]+=u*d;cross[axis][1]+=v*d;
        }
        for(unsigned j=i+1;j<count;j++) for(unsigned k=j+1;k<count;k++) {
            float a=(p[j][0]-p[i][0])*(p[k][1]-p[i][1])-(p[j][1]-p[i][1])*(p[k][0]-p[i][0]);
            float b=(w[j][0]-w[i][0])*(w[k][1]-w[i][1])-(w[j][1]-w[i][1])*(w[k][0]-w[i][0]);
            pixel_area=fmaxf(pixel_area,fabsf(a));world_area=fmaxf(world_area,fabsf(b));
        }
    }
    float det=uu*vv-uv*uv,trace=uu+vv;
    /* Retain the minimum spread and reject near-collinear pixel samples. */
    if(pixel_area<1000.0f || world_area<1.0f || !isfinite(det) || !isfinite(trace) || trace<1 || det/(trace*trace)<0.0016f) return false;
    for(unsigned axis=0;axis<2;axis++) {
        unsigned k=axis*3;
        m->a[k]=(cross[axis][0]*vv-cross[axis][1]*uv)/det;
        m->a[k+1]=(cross[axis][1]*uu-cross[axis][0]*uv)/det;
        m->a[k+2]=wc[axis]-m->a[k]*pc[0]-m->a[k+1]*pc[1];
    }
    for(unsigned i=0;i<6;i++) if(!isfinite(m->a[i])) return false;
    if(fabsf(m->a[0]*m->a[4]-m->a[1]*m->a[3])<1e-8f) return false;
    m->valid=true; return true;
}
bool pixel_map_apply(const PixelMap *m,float u,float v,float *x,float *y) {
    if(!m->valid || !isfinite(u) || !isfinite(v)) return false;
    *x=m->a[0]*u+m->a[1]*v+m->a[2]; *y=m->a[3]*u+m->a[4]*v+m->a[5];
    return isfinite(*x)&&isfinite(*y);
}
