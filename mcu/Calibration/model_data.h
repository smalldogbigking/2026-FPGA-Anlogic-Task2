/* Generated calibration: input coordinates are CENTIMETRES. */
#ifndef ARM_MODEL_DATA_H
#define ARM_MODEL_DATA_H
#include <math.h>
#include <stdint.h>
#ifndef MODEL_ALLOW_SIMULATION
#define MODEL_ALLOW_SIMULATION 0
#endif
#define MODEL_SIMULATION_ONLY 0
#define MODEL_READY (!MODEL_SIMULATION_ONLY || MODEL_ALLOW_SIMULATION)
#define MODEL_FIXED_CHANNEL 2
#define MODEL_FIXED_PULSE_US 1382
#define MODEL_GRIPPER_CHANNEL 1
#define MODEL_FIT_MASK 60u
#define MODEL_GRIP_VERIFIED 1
#define MODEL_PROJECT_ID "3fdb98897f6644758688d60778e46ede"
#define MODEL_REVISION 7
#define MODEL_DATA_SHA256 "8c27a97238575755c38c9ef935de8f09a5084da5f4a8e694474dd84e75b7e5ff"
#define MODEL_UNIT "cm"
#define MODEL_CONTROL_SHA256 "2eaf2091daa076bfe275f5def650c4ee8eae468ba86c56ee87017bad3ff04b23"
#define MODEL_POINT_COUNT 31
#define MODEL_PLANE_COUNT 1
#define MODEL_POSE_COUNT 7
#define MODEL_PERIOD_US 20000u
#define MODEL_RATE_US_S 600u
#define MODEL_GRIP_OPEN_US 1000u
#define MODEL_GRIP_CLOSE_US 1600u
#define MODEL_WORKSPACE_X 50.0f
#define MODEL_WORKSPACE_Y 50.0f
typedef struct {float x,y,p[4];} ModelPoint;
typedef struct {float z;unsigned first,count;} ModelPlane;
static const ModelPoint model_points[]={
{30.0f,52.0f,{1936.0f,1951.0f,926.0f,1692.0f}},
{30.0f,40.0f,{1843.0f,1490.0f,1265.0f,1692.0f}},
{30.0f,30.0f,{1675.0f,1368.0f,1417.0f,1692.0f}},
{30.0f,20.0f,{1647.0f,1142.0f,1637.0f,1692.0f}},
{20.0f,20.0f,{2165.0f,758.0f,1696.0f,1816.0f}},
{20.0f,30.0f,{2265.0f,944.0f,1475.0f,1816.0f}},
{20.0f,40.0f,{2266.0f,1292.0f,1213.0f,1816.0f}},
{20.0f,50.0f,{2196.0f,1670.0f,984.0f,1770.0f}},
{10.0f,50.0f,{2136.0f,1860.0f,894.0f,1863.0f}},
{10.0f,40.0f,{2136.0f,1425.0f,1192.0f,1903.0f}},
{8.0f,32.0f,{2086.0f,1253.0f,1345.0f,1933.0f}},
{12.0f,18.0f,{2020.0f,891.0f,1682.0f,1990.0f}},
{10.0f,10.0f,{2020.0f,750.0f,1863.0f,2098.0f}},
{0.0f,10.0f,{2020.0f,931.0f,1676.0f,2206.0f}},
{0.0f,20.0f,{2020.0f,1086.0f,1508.0f,2105.0f}},
{0.0f,30.0f,{2020.0f,1320.0f,1331.0f,2025.0f}},
{0.0f,40.0f,{2020.0f,1590.0f,1151.0f,1976.0f}},
{0.0f,50.0f,{2020.0f,2080.0f,791.0f,1947.0f}},
{60.0f,50.0f,{2020.0f,2080.0f,791.0f,1369.0f}},
{60.0f,40.0f,{2020.0f,1560.0f,1181.0f,1339.0f}},
{60.0f,30.0f,{2020.0f,1360.0f,1311.0f,1289.0f}},
{60.0f,20.0f,{2020.0f,1100.0f,1501.0f,1199.0f}},
{54.0f,20.0f,{2020.0f,1000.0f,1591.0f,1279.0f}},
{50.0f,30.0f,{2020.0f,1200.0f,1421.0f,1399.0f}},
{50.0f,40.0f,{2020.0f,1440.0f,1241.0f,1439.0f}},
{50.0f,50.0f,{2020.0f,1890.0f,931.0f,1460.0f}},
{40.0f,50.0f,{2020.0f,1700.0f,1061.0f,1570.0f}},
{40.0f,40.0f,{2020.0f,1390.0f,1308.0f,1570.0f}},
{40.0f,30.0f,{2020.0f,1120.0f,1498.0f,1530.0f}},
{40.0f,20.0f,{2020.0f,830.0f,1748.0f,1530.0f}},
{54.0f,6.0f,{1610.0f,700.0f,2198.0f,1539.0f}},
};
static const unsigned model_triangles[][3]={
{30,12,13},
{3,12,30},
{29,3,30},
{4,12,3},
{12,4,11},
{12,14,13},
{14,12,11},
{29,22,23},
{21,22,30},
{22,29,30},
{28,29,23},
{22,20,23},
{20,22,21},
{10,14,11},
{1,0,7},
{0,25,18},
{8,0,17},
{0,8,7},
{10,15,14},
{6,1,7},
{26,1,27},
{26,0,1},
{0,26,25},
{16,15,10},
{9,16,10},
{4,5,11},
{5,10,11},
{9,5,6},
{5,9,10},
{29,28,3},
{3,28,2},
{28,24,27},
{24,28,23},
{24,20,19},
{20,24,23},
{24,19,18},
{25,24,18},
{28,1,2},
{1,28,27},
{24,26,27},
{26,24,25},
{9,6,7},
{8,9,7},
{16,9,17},
{9,8,17},
{5,3,2},
{5,4,3},
{1,5,2},
{6,5,1},
};
static const ModelPlane model_planes[]={
{0.0f,0,49},
};
static const uint16_t model_limits[4][2]={
{500,3000},
{500,3000},
{500,3000},
{500,3000},
};
static const uint16_t model_poses[][4]={
{1540,1169,1761,1539},
{1540,1897,1191,1409},
{1539,1897,1270,1613},
{1539,1137,2000,1613},
{1539,1882,1221,1868},
{1539,1255,1755,2152},
{1539,1966,1143,1529},
};

static int model_plane(unsigned plane,float x,float y,float out[4]){
    const ModelPlane *p=&model_planes[plane];
    for(unsigned i=p->first;i<p->first+p->count;i++){
        const unsigned *tri=model_triangles[i];
        const ModelPoint *a=&model_points[tri[0]],*b=&model_points[tri[1]],*c=&model_points[tri[2]];
        float bx=b->x-a->x,by=b->y-a->y,cx=c->x-a->x,cy=c->y-a->y;
        float det=bx*cy-by*cx;if(fabsf(det)<1e-9f)continue;
        float u=((x-a->x)*cy-(y-a->y)*cx)/det;
        float v=(bx*(y-a->y)-by*(x-a->x))/det;
        if(u< -1e-6f || v< -1e-6f || u+v>1.000001f)continue;
        for(unsigned k=0;k<4;k++)out[k]=(1-u-v)*a->p[k]+u*b->p[k]+v*c->p[k];
        return 1;
    }
    return 0;
}
static int model_predict(float x,float y,float z,uint16_t out[4]){
    if(!MODEL_READY)return 0;
    if(!isfinite(x)||!isfinite(y)||!isfinite(z)||x<0||x>MODEL_WORKSPACE_X||y<0||y>MODEL_WORKSPACE_Y)return 0;
    x=x/MODEL_WORKSPACE_X*100.0f;y=y/MODEL_WORKSPACE_Y*100.0f;
    int exact=-1,lo=-1,hi=-1;
    for(unsigned i=0;i<MODEL_PLANE_COUNT;i++){
        if(fabsf(model_planes[i].z-z)<1e-6f)exact=(int)i;
        if(model_planes[i].z<z)lo=(int)i;
        if(model_planes[i].z>z && hi<0)hi=(int)i;
    }
    float values[4],a[4],b[4];
    if(exact>=0){if(!model_plane((unsigned)exact,x,y,values))return 0;}
    else{
        if(lo<0||hi<0||!model_plane((unsigned)lo,x,y,a)||!model_plane((unsigned)hi,x,y,b))return 0;
        float t=(z-model_planes[lo].z)/(model_planes[hi].z-model_planes[lo].z);
        for(unsigned k=0;k<4;k++)values[k]=(1-t)*a[k]+t*b[k];
    }
    uint16_t result[4];
    for(unsigned k=0;k<4;k++){
        if(!isfinite(values[k])||values[k]<model_limits[k][0]-.001f||values[k]>model_limits[k][1]+.001f)return 0;
        result[k]=(uint16_t)floorf(values[k]+.5f);
    }
    for(unsigned k=0;k<4;k++)out[k]=result[k];
    return 1;
}
static int model_pose(unsigned index,uint16_t out[4]){
    if(!MODEL_READY)return 0;
#if MODEL_POSE_COUNT == 0
    (void)index;(void)out;(void)model_poses;return 0;
#else
    if(index>=MODEL_POSE_COUNT)return 0;
    for(unsigned k=0;k<4;k++)out[k]=model_poses[index][k];
    return 1;
#endif
}
#endif
