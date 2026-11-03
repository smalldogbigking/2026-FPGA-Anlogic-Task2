// White-reference calibrated, smoothly interpolated separable lens-color balance.
// RAW meter drives the real SC520CS exposure loop. Colored scenes cannot drive AWB.
// Pixel path remains four clocks. Calibration is volatile until FPGA reset.
module isp_balance_v11 #(parameter WIDTH=1280,HEIGHT=720,CAL_FRAMES=180)(
 input wire clk,rst_n,beauty,input wire [4:0] timing,
 input wire [11:0] x,y,input wire [23:0] rgb,
 output reg [4:0] out_timing,output reg [11:0] out_x,out_y,
 output reg [23:0] out_rgb,output reg [7:0] raw_mean,
 output reg stats_toggle,output reg [191:0] histogram,
 output wire [31:0] balance_gains,
 input wire [1:0] correction_mode,input wire calibrate,
 output reg calibration_busy,calibration_valid,
 output wire [15:0] wb_status,output wire [7:0] tone_status,
 input wire freeze,input wire external_wb,input wire[7:0] external_r,external_b
);
 localparam COLS=(WIDTH+15)/16,ROWS=(HEIGHT+15)/16;
 // Two axes model smooth center/corner tint. Adjacent 16-pixel gains are
 // interpolated, so calibration introduces no coarse square-ring boundaries.
 // Interleave adjacent anchors into two banks. Each bank has one
 // synchronous read and one calibration write, allowing real dual-port RAM.
 // Each bank stores FIX at addresses 0..63 and immutable AUTO at 64..127.
 // Mode selects the ADDRESS, not the data after two asynchronous reads.
 // Independent, unconditional synchronous reads fit simple dual-port ERAM.
 (* ram_style="bram" *) reg [35:0] gain_x_even[0:127],gain_x_odd[0:127];
 (* ram_style="bram" *) reg [35:0] gain_y_even[0:127],gain_y_odd[0:127];
 initial begin
 gain_x_even[0]=36'h4002fe34c;
 gain_x_odd[0]=36'h400306350;
 gain_x_even[1]=36'h40030e354;
 gain_x_odd[1]=36'h400317359;
 gain_x_even[2]=36'h40032135e;
 gain_x_odd[2]=36'h40032a364;
 gain_x_even[3]=36'h40033536a;
 gain_x_odd[3]=36'h400341370;
 gain_x_even[4]=36'h40034d376;
 gain_x_odd[4]=36'h40035837d;
 gain_x_even[5]=36'h400365384;
 gain_x_odd[5]=36'h40037238b;
 gain_x_even[6]=36'h40037e393;
 gain_x_odd[6]=36'h40038b39a;
 gain_x_even[7]=36'h4003983a2;
 gain_x_odd[7]=36'h4003a43a9;
 gain_x_even[8]=36'h4003b23b1;
 gain_x_odd[8]=36'h4003bf3b8;
 gain_x_even[9]=36'h4003ca3c0;
 gain_x_odd[9]=36'h4003d73c7;
 gain_x_even[10]=36'h4003e33ce;
 gain_x_odd[10]=36'h4003ef3d5;
 gain_x_even[11]=36'h4003fa3dc;
 gain_x_odd[11]=36'h4004053e2;
 gain_x_even[12]=36'h4004103e9;
 gain_x_odd[12]=36'h40041a3ef;
 gain_x_even[13]=36'h4004233f5;
 gain_x_odd[13]=36'h40042d3fb;
 gain_x_even[14]=36'h400436400;
 gain_x_odd[14]=36'h40043d405;
 gain_x_even[15]=36'h40044540a;
 gain_x_odd[15]=36'h40044c40e;
 gain_x_even[16]=36'h400453412;
 gain_x_odd[16]=36'h400459416;
 gain_x_even[17]=36'h40045d419;
 gain_x_odd[17]=36'h40046241c;
 gain_x_even[18]=36'h40046641e;
 gain_x_odd[18]=36'h400469421;
 gain_x_even[19]=36'h40046c422;
 gain_x_odd[19]=36'h40046d424;
 gain_x_even[20]=36'h40046f425;
 gain_x_odd[20]=36'h40046f425;
 gain_x_even[21]=36'h40046f425;
 gain_x_odd[21]=36'h40046e425;
 gain_x_even[22]=36'h40046c424;
 gain_x_odd[22]=36'h40046a423;
 gain_x_even[23]=36'h400467422;
 gain_x_odd[23]=36'h400465420;
 gain_x_even[24]=36'h40046141e;
 gain_x_odd[24]=36'h40045c41c;
 gain_x_even[25]=36'h400456419;
 gain_x_odd[25]=36'h400450416;
 gain_x_even[26]=36'h40044b412;
 gain_x_odd[26]=36'h40044440e;
 gain_x_even[27]=36'h40043c40a;
 gain_x_odd[27]=36'h400435406;
 gain_x_even[28]=36'h40042d401;
 gain_x_odd[28]=36'h4004243fc;
 gain_x_even[29]=36'h40041c3f7;
 gain_x_odd[29]=36'h4004123f2;
 gain_x_even[30]=36'h4004093ed;
 gain_x_odd[30]=36'h4004003e7;
 gain_x_even[31]=36'h4003f63e2;
 gain_x_odd[31]=36'h4003ec3dc;
 gain_x_even[32]=36'h4003e23d6;
 gain_x_odd[32]=36'h4003d83d1;
 gain_x_even[33]=36'h4003ce3cb;
 gain_x_odd[33]=36'h4003c43c5;
 gain_x_even[34]=36'h4003ba3c0;
 gain_x_odd[34]=36'h4003b13ba;
 gain_x_even[35]=36'h4003a73b5;
 gain_x_odd[35]=36'h40039e3b0;
 gain_x_even[36]=36'h4003963ab;
 gain_x_odd[36]=36'h40038e3a6;
 gain_x_even[37]=36'h4003863a2;
 gain_x_odd[37]=36'h40037f39e;
 gain_x_even[38]=36'h40037939a;
 gain_x_odd[38]=36'h400373397;
 gain_x_even[39]=36'h40036e394;
 gain_x_odd[39]=36'h40036a392;
 gain_y_even[0]=36'h000f31f59;
 gain_y_odd[0]=36'h000f4bf70;
 gain_y_even[1]=36'h000f63f85;
 gain_y_odd[1]=36'h000f77f98;
 gain_y_even[2]=36'h000f8afa8;
 gain_y_odd[2]=36'h000f9afb6;
 gain_y_even[3]=36'h000fa9fc3;
 gain_y_odd[3]=36'h000fb6fce;
 gain_y_even[4]=36'h000fc1fd7;
 gain_y_odd[4]=36'h000fcbfdf;
 gain_y_even[5]=36'h000fd3fe6;
 gain_y_odd[5]=36'h000fdafec;
 gain_y_even[6]=36'h000fe0ff0;
 gain_y_odd[6]=36'h000fe5ff4;
 gain_y_even[7]=36'h000fe9ff7;
 gain_y_odd[7]=36'h000fecffa;
 gain_y_even[8]=36'h000ff0ffc;
 gain_y_odd[8]=36'h000ff1ffd;
 gain_y_even[9]=36'h000ff3ffe;
 gain_y_odd[9]=36'h000ff4fff;
 gain_y_even[10]=36'h000ff5000;
 gain_y_odd[10]=36'h000ff6000;
 gain_y_even[11]=36'h000ff6000;
 gain_y_odd[11]=36'h000ff6000;
 gain_y_even[12]=36'h000ff6000;
 gain_y_odd[12]=36'h000ff5000;
 gain_y_even[13]=36'h000ff5000;
 gain_y_odd[13]=36'h000ff5fff;
 gain_y_even[14]=36'h000ff3fff;
 gain_y_odd[14]=36'h000ff3fff;
 gain_y_even[15]=36'h000ff1ffe;
 gain_y_odd[15]=36'h000ff0ffe;
 gain_y_even[16]=36'h000feeffd;
 gain_y_odd[16]=36'h000fedffd;
 gain_y_even[17]=36'h000febffc;
 gain_y_odd[17]=36'h000fe7ffb;
 gain_y_even[18]=36'h000fe4ff9;
 gain_y_odd[18]=36'h000fe1ff7;
 gain_y_even[19]=36'h000fdcff5;
 gain_y_odd[19]=36'h000fd7ff2;
 gain_y_even[20]=36'h000fd0fef;
 gain_y_odd[20]=36'h000fcafeb;
 gain_y_even[21]=36'h000fc2fe6;
 gain_y_odd[21]=36'h000fb9fe0;
 gain_y_even[22]=36'h000faefd9;
 end


 initial begin
 gain_x_even[64]=36'h40039f3bc;
 gain_x_odd[64]=36'h4003a23be;
 gain_x_even[65]=36'h4003a53c0;
 gain_x_odd[65]=36'h4003a93c1;
 gain_x_even[66]=36'h4003ac3c3;
 gain_x_odd[66]=36'h4003b03c6;
 gain_x_even[67]=36'h4003b43c8;
 gain_x_odd[67]=36'h4003b83ca;
 gain_x_even[68]=36'h4003bc3cc;
 gain_x_odd[68]=36'h4003c13ce;
 gain_x_even[69]=36'h4003c63d2;
 gain_x_odd[69]=36'h4003cb3d4;
 gain_x_even[70]=36'h4003cf3d8;
 gain_x_odd[70]=36'h4003d43da;
 gain_x_even[71]=36'h4003d93dd;
 gain_x_odd[71]=36'h4003de3df;
 gain_x_even[72]=36'h4003e33e2;
 gain_x_odd[72]=36'h4003e83e5;
 gain_x_even[73]=36'h4003ec3e8;
 gain_x_odd[73]=36'h4003f13eb;
 gain_x_even[74]=36'h4003f63ed;
 gain_x_odd[74]=36'h4003fa3f0;
 gain_x_even[75]=36'h4003fe3f2;
 gain_x_odd[75]=36'h4004023f5;
 gain_x_even[76]=36'h4004063f7;
 gain_x_odd[76]=36'h40040a3fa;
 gain_x_even[77]=36'h40040e3fc;
 gain_x_odd[77]=36'h4004103fe;
 gain_x_even[78]=36'h400414400;
 gain_x_odd[78]=36'h400416402;
 gain_x_even[79]=36'h40041a404;
 gain_x_odd[79]=36'h40041c405;
 gain_x_even[80]=36'h400420407;
 gain_x_odd[80]=36'h400421408;
 gain_x_even[81]=36'h400422409;
 gain_x_odd[81]=36'h40042540a;
 gain_x_even[82]=36'h40042640b;
 gain_x_odd[82]=36'h40042740c;
 gain_x_even[83]=36'h40042840d;
 gain_x_odd[83]=36'h40042840e;
 gain_x_even[84]=36'h40042a40e;
 gain_x_odd[84]=36'h40042a40e;
 gain_x_even[85]=36'h40042a40e;
 gain_x_odd[85]=36'h40042940e;
 gain_x_even[86]=36'h40042840e;
 gain_x_odd[86]=36'h40042840e;
 gain_x_even[87]=36'h40042740d;
 gain_x_odd[87]=36'h40042640c;
 gain_x_even[88]=36'h40042440b;
 gain_x_odd[88]=36'h40042240a;
 gain_x_even[89]=36'h400420409;
 gain_x_odd[89]=36'h40041e408;
 gain_x_even[90]=36'h40041c407;
 gain_x_odd[90]=36'h40041a405;
 gain_x_even[91]=36'h400416404;
 gain_x_odd[91]=36'h400414402;
 gain_x_even[92]=36'h400410400;
 gain_x_odd[92]=36'h40040e3fe;
 gain_x_even[93]=36'h40040a3fd;
 gain_x_odd[93]=36'h4004073fb;
 gain_x_even[94]=36'h4004033f8;
 gain_x_odd[94]=36'h4004003f7;
 gain_x_even[95]=36'h4003fc3f5;
 gain_x_odd[95]=36'h4003f83f2;
 gain_x_even[96]=36'h4003f53f0;
 gain_x_odd[96]=36'h4003f13ee;
 gain_x_even[97]=36'h4003ed3ec;
 gain_x_odd[97]=36'h4003ea3ea;
 gain_x_even[98]=36'h4003e63e8;
 gain_x_odd[98]=36'h4003e23e6;
 gain_x_even[99]=36'h4003df3e4;
 gain_x_odd[99]=36'h4003db3e2;
 gain_x_even[100]=36'h4003d83e0;
 gain_x_odd[100]=36'h4003d53de;
 gain_x_even[101]=36'h4003d23dd;
 gain_x_odd[101]=36'h4003d03db;
 gain_x_even[102]=36'h4003cd3da;
 gain_x_odd[102]=36'h4003cc3d9;
 gain_x_even[103]=36'h4003c93d8;
 gain_x_odd[103]=36'h4003c83d7;
 gain_y_even[64]=36'h000fb2fc1;
 gain_y_odd[64]=36'h000fbcfca;
 gain_y_even[65]=36'h000fc6fd2;
 gain_y_odd[65]=36'h000fcdfd9;
 gain_y_even[66]=36'h000fd4fdf;
 gain_y_odd[66]=36'h000fdafe4;
 gain_y_even[67]=36'h000fdffea;
 gain_y_odd[67]=36'h000fe4fed;
 gain_y_even[68]=36'h000fe8ff1;
 gain_y_odd[68]=36'h000fecff4;
 gain_y_even[69]=36'h000ff0ff6;
 gain_y_odd[69]=36'h000ff2ff8;
 gain_y_even[70]=36'h000ff4ffa;
 gain_y_odd[70]=36'h000ff6ffc;
 gain_y_even[71]=36'h000ff7ffd;
 gain_y_odd[71]=36'h000ff8ffe;
 gain_y_even[72]=36'h000ffaffe;
 gain_y_odd[72]=36'h000ffaffe;
 gain_y_even[73]=36'h000ffcfff;
 gain_y_odd[73]=36'h000ffc000;
 gain_y_even[74]=36'h000ffc000;
 gain_y_odd[74]=36'h000ffc000;
 gain_y_even[75]=36'h000ffc000;
 gain_y_odd[75]=36'h000ffc000;
 gain_y_even[76]=36'h000ffc000;
 gain_y_odd[76]=36'h000ffc000;
 gain_y_even[77]=36'h000ffc000;
 gain_y_odd[77]=36'h000ffc000;
 gain_y_even[78]=36'h000ffc000;
 gain_y_odd[78]=36'h000ffc000;
 gain_y_even[79]=36'h000ffafff;
 gain_y_odd[79]=36'h000ffafff;
 gain_y_even[80]=36'h000ff9ffe;
 gain_y_odd[80]=36'h000ff8ffe;
 gain_y_even[81]=36'h000ff8ffe;
 gain_y_odd[81]=36'h000ff7ffe;
 gain_y_even[82]=36'h000ff6ffd;
 gain_y_odd[82]=36'h000ff4ffd;
 gain_y_even[83]=36'h000ff2ffc;
 gain_y_odd[83]=36'h000ff1ffb;
 gain_y_even[84]=36'h000feeffa;
 gain_y_odd[84]=36'h000fecff8;
 gain_y_even[85]=36'h000fe9ff6;
 gain_y_odd[85]=36'h000fe5ff4;
 gain_y_even[86]=36'h000fe1ff1;
 end
 (* ram_style="bram" *) reg [35:0] cal_sum_x[0:79],cal_sum_y[0:44];
 reg [35:0] sx_read,sy_read;
 reg sx_en,sy_en;reg [6:0] sx_idx;reg [5:0] sy_idx;reg first_capture;
 reg [23:0] capture_rgb;
 wire eof=timing[2] && x==WIDTH-1 && y==HEIGHT-1;
 reg [7:0] cal_frame;reg [3:0] cal_state;reg [6:0] cal_idx;
 reg vertical_axis;
 // Capture and divider scans never overlap. Reuse each axis' synchronous
 // read port rather than infer a second read port and a register-array mux.
 wire [35:0] cal_sums=vertical_axis?sy_read:sx_read;
 reg div_launch;reg [23:0] div_num,div_den;wire div_done;wire [23:0] div_q;
 reg [11:0] result_r,held_b,center_r,center_b;
 reg bad_capture,profile_attempted;reg anchor_bad;reg[6:0] bad_anchors;reg div_pending;reg [23:0] div_held;
 wire [11:0] result_b=held_b;
 wire[11:0] result_g=clamp_gain(div_done?div_q:div_held);
 wire signed[12:0] vertical_g=$signed({1'b0,result_g})-13'sd1024;
 wire signed [12:0] vertical_r=$signed({1'b0,result_r})-$signed({1'b0,center_r});
 wire signed [12:0] vertical_b=$signed({1'b0,result_b})-$signed({1'b0,center_b});
 udiv24 calibration_divider(clk,rst_n,div_launch,div_num,div_den,div_done,div_q);
 wire collect=!freeze && calibration_busy && cal_state==0 && cal_frame>=CAL_FRAMES-16;
 wire capture_x=collect && timing[2] && y==HEIGHT/2 && x[3:0]==0 && (x>>4)<COLS;
 wire capture_y=collect && timing[2] && x==WIDTH/2 && y[3:0]==0 && (y>>4)<ROWS;
 function [11:0] clamp_gain;input [23:0] a;
 begin clamp_gain=a<512?12'd512:a>2047?12'd2047:a[11:0];end endfunction
 function [35:0] accumulate;input [35:0] old;input [23:0] c;input clear;
 begin accumulate=clear?{4'd0,c[23:16],4'd0,c[15:8],4'd0,c[7:0]}:
 {old[35:24]+{4'd0,c[23:16]},old[23:12]+{4'd0,c[15:8]},old[11:0]+{4'd0,c[7:0]}};end endfunction
 // Read-modify-write only once per 16 clocks; no reset on RAM.
 always @(posedge clk)begin
  sx_read<=cal_sum_x[(cal_state!=0 && !vertical_axis)?cal_idx:x[10:4]];
  sy_read<=cal_sum_y[(cal_state!=0 && vertical_axis)?cal_idx[5:0]:y[9:4]];
  if(sx_en)cal_sum_x[sx_idx]<=accumulate(sx_read,capture_rgb,first_capture);
  if(sy_en)cal_sum_y[sy_idx]<=accumulate(sy_read,capture_rgb,first_capture);
 end
 wire gain_commit;
 reg[11:0] center_green_sum;
 // Preserve chroma by calibrating multiplicative R/G/B flat-field gains.
 // The old additive luminance lift raised all channels equally (gray veil)
 // and under-corrected dark edges. The same serial divider now handles G.
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)center_green_sum<=0;
 else if(sx_en && sx_idx==WIDTH/32)
 center_green_sum<=first_capture?{4'd0,capture_rgb[15:8]}:center_green_sum+capture_rgb[15:8];
 end
 function signed[7:0] tone_limit;input signed[13:0] d;
 begin tone_limit=d>127?8'sd127:d< -127?-8'sd127:d[7:0];end endfunction
 reg signed [7:0] awb_r,awb_b;
 wire [35:0] gx0,gx1,gy0,gy1;
 reg[35:0] gx_even,gx_odd,gy_even,gy_odd;reg[23:0] p0,p1,p2;
 reg ix_odd,iy_odd,ix_last,iy_last;
 assign gx0=ix_odd?gx_odd:gx_even;
 assign gx1=ix_last?gx0:(ix_odd?gx_even:gx_odd);
 assign gy0=iy_odd?gy_odd:gy_even;
 assign gy1=iy_last?gy0:(iy_odd?gy_even:gy_odd);
 reg [10:0] gain_r,gain_b,gain_g;
 reg [18:0] prod_r,prod_b,prod_g;
 reg [4:0] t0,t1,t2;reg [11:0] x0,x1,x2,y0,y1,y2;reg en0,en1,en2;
 wire auto_mode=correction_mode==2'b01;
 wire fixed_mode=correction_mode==2'b10;
 wire correction_on=beauty && (auto_mode || (fixed_mode && calibration_valid));
 wire [6:0] ix=x<WIDTH?(x>>4):0;
 wire [5:0] iy=y<HEIGHT?(y>>4):0;
 // Exact Q4 DDA interpolation for the continuous raster. Reset at each
 // 16-pixel/16-row anchor; add the endpoint difference once per pixel/row.
 // This replaces four parallel fractional multipliers without changing gain.
 reg signed [15:0] acc_xg,acc_yg;reg signed[12:0] step_xg;reg signed[11:0] step_yg,row_g;
 reg signed [15:0] acc_xr,acc_xb;reg signed [15:0] acc_yr,acc_yb;
 reg signed [12:0] step_xr,step_xb;reg signed [11:0] step_yr,step_yb;
 reg signed [11:0] row_r,row_b;
 wire signed [12:0] dxr=$signed(gx1[23:12])-$signed(gx0[23:12]);
 wire signed [12:0] dxb=$signed(gx1[11:0])-$signed(gx0[11:0]);
 wire signed [12:0] dyr=$signed(gy1[23:12])-$signed(gy0[23:12]);
 wire signed [12:0] dyb=$signed(gy1[11:0])-$signed(gy0[11:0]);
 wire signed [15:0] next_xr=acc_xr+step_xr,next_xb=acc_xb+step_xb;
 wire signed [15:0] next_yr=acc_yr+step_yr,next_yb=acc_yb+step_yb;
 wire signed [11:0] xr=x0[3:0]==0?$signed(gx0[23:12]):$signed(next_xr)>>>4;
 wire signed [11:0] xb=x0[3:0]==0?$signed(gx0[11:0]):$signed(next_xb)>>>4;
 wire signed [11:0] yr=y0[3:0]==0?$signed(gy0[23:12]):$signed(next_yr)>>>4;
 wire signed [11:0] yb=y0[3:0]==0?$signed(gy0[11:0]):$signed(next_yb)>>>4;
 wire signed[12:0] dxg=$signed(gx1[35:24])-$signed(gx0[35:24]);
 wire signed[12:0] dyg=$signed(gy1[35:24])-$signed(gy0[35:24]);
 wire signed[15:0] next_xg=acc_xg+step_xg,next_yg=acc_yg+step_yg;
 wire signed[11:0] xg=x0[3:0]==0?$signed(gx0[35:24]):$signed(next_xg)>>>4;
 wire signed[11:0] yg=y0[3:0]==0?$signed(gy0[35:24]):$signed(next_yg)>>>4;
 wire signed[12:0] gg=xg+((x0==0 && t0[2])?yg:row_g);
 wire signed [12:0] gr=xr+((x0==0 && t0[2])?yr:row_r);
 wire signed [12:0] gb=xb+((x0==0 && t0[2])?yb:row_b);
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin acc_xg<=0;acc_yg<=0;step_xg<=0;step_yg<=0;row_g<=0;acc_xr<=0;acc_xb<=0;acc_yr<=0;acc_yb<=0;step_xr<=0;step_xb<=0;step_yr<=0;step_yb<=0;row_r<=0;row_b<=0;end
 else if(t0[2])begin
  if(x0[3:0]==0)begin
   acc_xg<=$signed(gx0[35:24])<<<4;step_xg<=dxg;acc_xr<=$signed(gx0[23:12])<<<4;acc_xb<=$signed(gx0[11:0])<<<4;step_xr<=dxr;step_xb<=dxb;
  end else begin acc_xg<=next_xg;acc_xr<=next_xr;acc_xb<=next_xb;end
  if(x0==0)begin
   row_g<=yg;row_r<=yr;row_b<=yb;
   if(y0[3:0]==0)begin acc_yg<=$signed(gy0[35:24])<<<4;step_yg<=dyg;acc_yr<=$signed(gy0[23:12])<<<4;acc_yb<=$signed(gy0[11:0])<<<4;step_yr<=dyr;step_yb<=dyb;end
   else begin acc_yg<=next_yg;acc_yr<=next_yr;acc_yb<=next_yb;end
  end
 end end
 wire [11:0] report_base_r=auto_mode?((WIDTH==1280 && HEIGHT==720)?12'd1062:12'd1024):(calibration_valid?center_r:12'd1024);
 wire [11:0] report_base_b=auto_mode?((WIDTH==1280 && HEIGHT==720)?12'd1038:12'd1024):(calibration_valid?center_b:12'd1024);
 wire signed [12:0] override_r=$signed({1'b0,external_r,4'b0})-$signed({1'b0,report_base_r});
 wire signed [12:0] override_b=$signed({1'b0,external_b,4'b0})-$signed({1'b0,report_base_b});
 wire signed [12:0] effective_r=gr+(external_wb?override_r:(auto_mode?awb_r:10'sd0));
 wire signed [12:0] effective_b=gb+(external_wb?override_b:(auto_mode?awb_b:10'sd0));
 wire [9:0] sum_y={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
 wire [7:0] lum=sum_y[9:2];
 // The raw histogram also uses the 16-pixel sampling interval for a
 // one-read/one-write RAM. No data reset or 16 parallel incrementers.
 (* ram_style="bram" *) reg [11:0] counts_ram[0:15];
 reg [11:0] count_read;reg [15:0] count_seen;
 reg count_write,count_was_seen;reg [3:0] count_addr;
 reg last_count_write;reg [3:0] last_count_addr;reg [11:0] last_count_value;
 reg hist_busy;reg [4:0] hist_scan;reg [18:0] meter_sum;
 wire sample=timing[2] && !timing[1] && x[3:0]==0 && y[3:0]==0;
 wire hist_request=sample && !freeze && !hist_busy;
 wire [3:0] hist_raddr=(eof && !freeze)?4'd0:hist_busy?(freeze?hist_scan[3:0]:hist_scan[3:0]+4'd1):lum[7:4];
 // Forward a same-address read-before-write collision. Normal raster
 // requests are 16 clocks apart; this also preserves dense test stimuli.
 wire [11:0] count_previous=count_was_seen?((last_count_write && last_count_addr==count_addr)?last_count_value:count_read):12'd0;
 wire [11:0] scan_count=(last_count_write && last_count_addr==hist_scan[3:0])?last_count_value:count_read;
 always @(posedge clk)begin
  count_read<=counts_ram[hist_raddr];
  if(count_write)counts_ram[count_addr]<=count_previous+1'b1;
  last_count_write<=count_write;last_count_addr<=count_addr;last_count_value<=count_previous+1'b1;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin count_seen<=0;count_write<=0;count_was_seen<=0;count_addr<=0;end
  else begin
   count_write<=hist_request;
   if(!freeze && timing[1])count_seen<=0;
   if(hist_request)begin count_addr<=lum[7:4];count_was_seen<=count_seen[lum[7:4]];count_seen[lum[7:4]]<=1;end
  end
 end
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin raw_mean<=128;stats_toggle<=0;histogram<=0;meter_sum<=0;hist_busy<=0;hist_scan<=0;end
 else if(!freeze)begin
  if(timing[1])begin meter_sum<=0;hist_busy<=0;end
  if(sample && x>=128 && x<1152 && y>=96 && y<608)meter_sum<=meter_sum+lum;
  if(eof)begin
   if(WIDTH==1280 && HEIGHT==720)raw_mean<=meter_sum[18:11];
   hist_busy<=1;hist_scan<=0;
  end else if(hist_busy && !timing[1])begin
   if(hist_scan<16)begin
    histogram[hist_scan[3:0]*12+:12]<=count_seen[hist_scan[3:0]]?scan_count:12'd0;
    hist_scan<=hist_scan+1'b1;
   end else begin hist_busy<=0;stats_toggle<=~stats_toggle;end
  end
 end end
 function [7:0] clipped;input [19:0] v;reg [20:0] rounded;
 begin rounded={1'b0,v}+21'd512;clipped=(rounded>=21'd261120)?255:rounded[17:10];end endfunction
 function [7:0] tone;input [7:0] c;input signed [9:0] d;reg signed [10:0] q;
 begin q=$signed({1'b0,c})+d;tone=q<0?0:q>255?255:q[7:0];end endfunction
 wire [7:0] corrected_r=clipped(prod_r),corrected_b=clipped(prod_b),corrected_g=clipped(prod_g);
 wire [7:0] maxc=(corrected_r>corrected_g)?((corrected_r>corrected_b)?corrected_r:corrected_b):((corrected_g>corrected_b)?corrected_g:corrected_b);
 wire [7:0] minc=(corrected_r<corrected_g)?((corrected_r<corrected_b)?corrected_r:corrected_b):((corrected_g<corrected_b)?corrected_g:corrected_b);
 // Keep the neutral-pixel predicate out of the RGB multiplier -> counter CE
 // path. RGB, range, sample/frame tags and AWB eligibility travel together.
 // Only this statistics tap gains two clocks; the video remains four clocks.
 reg [23:0] meter_rgb3,meter_rgb4;
 reg [7:0] meter_min3,meter_max3;
 reg meter_sample3,meter_center3,meter_center4,neutral4;
 reg meter_sof3,meter_sof4,meter_eof3,meter_eof4;
 reg meter_awb3,meter_awb4;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   meter_rgb3<=0;meter_rgb4<=0;meter_min3<=0;meter_max3<=0;
   meter_sample3<=0;meter_center3<=0;meter_center4<=0;neutral4<=0;
   meter_sof3<=0;meter_sof4<=0;meter_eof3<=0;meter_eof4<=0;meter_awb3<=0;meter_awb4<=0;
  end else begin
   meter_rgb3<={corrected_r,corrected_g,corrected_b};meter_rgb4<=meter_rgb3;
   meter_min3<=minc;meter_max3<=maxc;
   meter_sample3<=t2[2] && !t2[1] && x2[3:0]==0 && y2[3:0]==0;
   meter_center3<=x2>=WIDTH/4 && x2<3*WIDTH/4 && y2>=HEIGHT/4 && y2<3*HEIGHT/4;
   meter_center4<=meter_center3;
   neutral4<=meter_sample3 && meter_min3>24 && meter_max3<244 &&
     (meter_max3-meter_min3)<=((meter_max3>>2)+2);
   meter_sof3<=t2[1];meter_sof4<=meter_sof3;
   meter_eof3<=t2[2] && x2==WIDTH-1 && y2==HEIGHT-1;meter_eof4<=meter_eof3;
   meter_awb3<=!freeze && beauty && auto_mode && !calibration_busy;meter_awb4<=meter_awb3;
  end
 end
 reg [19:0] rs,gs,bs;reg [11:0] neutral_n,rim_n;reg [9:0] center_n;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin rs<=0;gs<=0;bs<=0;neutral_n<=0;center_n<=0;rim_n<=0;awb_r<=0;awb_b<=0;end
 else begin
   if(meter_sof4)begin rs<=0;gs<=0;bs<=0;neutral_n<=0;center_n<=0;rim_n<=0;end
   if(neutral4)begin
    rs<=rs+meter_rgb4[23:16];gs<=gs+meter_rgb4[15:8];bs<=bs+meter_rgb4[7:0];neutral_n<=neutral_n+1'b1;
    if(meter_center4)center_n<=center_n+1'b1;else rim_n<=rim_n+1'b1;
  end
  // Manual calibration does not reset the independent automatic AWB state.
  if(meter_eof4 && meter_awb4 && neutral_n>=96 && center_n>=24 && rim_n>=24)begin
   if(rs+(gs>>5)<gs && awb_r<96)awb_r<=awb_r+1;else if(rs>gs+(gs>>5) && awb_r> -96)awb_r<=awb_r-1;
   if(bs+(gs>>5)<gs && awb_b<96)awb_b<=awb_b+1;else if(bs>gs+(gs>>5) && awb_b> -96)awb_b<=awb_b-1;
  end
 end end
 // Report the gain actually applied at the image center, not unity when
 // the white-reference spatial profile contains a non-unity calibration.
 // Automatic factory profile is a separate half-strength immutable ROM.
 // Manual calibration writes only the fixed-mode RAM; invalid FIXED bypasses.
 wire signed [12:0] report_r=$signed({1'b0,report_base_r})+(auto_mode?awb_r:10'sd0);
 wire signed [12:0] report_b=$signed({1'b0,report_base_b})+(auto_mode?awb_b:10'sd0);
 wire [11:0] display_r=!correction_on?12'd1024:report_r<512?12'd512:report_r>2047?12'd2047:report_r[11:0];
 wire [11:0] display_b=!correction_on?12'd1024:report_b<512?12'd512:report_b>2047?12'd2047:report_b[11:0];
 assign balance_gains={display_r[11:4],display_r[11:4],display_b[11:4],display_b[11:4]};
 assign wb_status=external_wb?{external_r,external_b}:{display_r[11:4],display_b[11:4]};
 wire [127:0] offsets;reg [127:0] frozen_offsets;reg [127:0] frame_offsets;reg old_toggle;
 always @(posedge clk or negedge rst_n)if(!rst_n)old_toggle<=0;else old_toggle<=stats_toggle;
 histogram_curve_pro curve(clk,rst_n,stats_toggle!=old_toggle,histogram,offsets);
 always @(posedge clk or negedge rst_n)if(!rst_n)frame_offsets<=0;else if(!freeze && timing[1])frame_offsets<=offsets;
 wire [127:0] use_offsets=auto_mode?frame_offsets:(calibration_valid?frozen_offsets:128'd0);
 // Fetch both tone anchors one stage earlier, alongside gain calculation.
 // A mode/offset mux and a signed subtract no longer feed a multiply,
 // interpolation add and clamp in the same cycle. No video delay is added.
 wire [9:0] y1sum={2'b0,p0[23:16]}+{1'b0,p0[15:8],1'b0}+{2'b0,p0[7:0]};
 wire [7:0] ylum=y1sum[9:2];
 wire signed [7:0] d0=use_offsets[ylum[7:4]*8+:8];
 wire signed [7:0] d1=use_offsets[((ylum[7:4]==15)?4'd15:ylum[7:4]+4'd1)*8+:8];
 reg signed [7:0] tone_base1;
 reg signed [8:0] tone_step1;
 reg [3:0] tone_fraction1;
 wire signed [12:0] interp=tone_step1*$signed({1'b0,tone_fraction1});
 reg signed [7:0] delta2;
 wire signed[9:0] combined_delta=$signed(delta2);
 assign tone_status=use_offsets[8*8+:8]+8'd128;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 calibration_busy<=0;calibration_valid<=0;cal_frame<=0;cal_state<=0;cal_idx<=0;vertical_axis<=0;
 sx_en<=0;sy_en<=0;sx_idx<=0;sy_idx<=0;first_capture<=0;capture_rgb<=0;div_launch<=0;div_num<=0;div_den<=1;held_b<=1024;result_r<=1024;center_r<=1024;center_b<=1024;bad_capture<=0;anchor_bad<=0;bad_anchors<=0;profile_attempted<=0;frozen_offsets<=0;div_pending<=0;div_held<=0;
 end else begin
 div_launch<=0;if(div_done)begin div_pending<=1;div_held<=div_q;end
 sx_en<=capture_x;sy_en<=capture_y;sx_idx<=x>>4;sy_idx<=y>>4;
 capture_rgb<=rgb;first_capture<=cal_frame==CAL_FRAMES-16;
 if(!freeze && calibrate && !calibration_busy)begin calibration_busy<=1;calibration_valid<=0;profile_attempted<=1;cal_frame<=0;cal_state<=0;bad_capture<=0;bad_anchors<=0;anchor_bad<=0;end
 else if(!freeze && calibration_busy)case(cal_state)
  0:if(eof)begin if(cal_frame==CAL_FRAMES-1)begin cal_idx<=0;vertical_axis<=0;cal_state<=1;end else cal_frame<=cal_frame+1'b1;end
  1:cal_state<=2;
  2:begin div_num<={2'd0,center_green_sum,10'd0};div_den<={12'd0,cal_sums[35:24]};div_launch<=1;cal_state<=3;
    anchor_bad<=cal_sums[35:24]<128 || cal_sums[23:12]<128 || cal_sums[11:0]<128 || cal_sums[35:24]>4072 || cal_sums[23:12]>4072 || cal_sums[11:0]>4072;
    if(cal_sums[35:24]<128 || cal_sums[23:12]<128 || cal_sums[11:0]<128 || cal_sums[35:24]>4072 || cal_sums[23:12]>4072 || cal_sums[11:0]>4072)begin
     if(bad_anchors<127)bad_anchors<=bad_anchors+1'b1;
     if(bad_anchors>=15)bad_capture<=1;
    end
   end
  3:if(div_done || div_pending)begin div_pending<=0;result_r<=clamp_gain(div_done?div_q:div_held);cal_state<=4;end
  4:begin div_num<={2'd0,center_green_sum,10'd0};div_den<={12'd0,cal_sums[11:0]};div_launch<=1;cal_state<=5;end
  5:if(div_done || div_pending)begin
   div_pending<=0;held_b<=clamp_gain(div_done?div_q:div_held);cal_state<=7;
  end
  7:begin div_num<={2'd0,center_green_sum,10'd0};div_den<={12'd0,cal_sums[23:12]};div_launch<=1;cal_state<=8;end
  8:if(div_done || div_pending)begin
   div_pending<=0;
   if(!vertical_axis)begin
    if(cal_idx==WIDTH/32 && !anchor_bad)begin center_r<=result_r;center_b<=held_b;end
    if(cal_idx==COLS-1)begin vertical_axis<=1;cal_idx<=0;cal_state<=1;end else begin cal_idx<=cal_idx+1'b1;cal_state<=1;end
   end else begin
    if(cal_idx==ROWS-1)begin cal_state<=6;end else begin cal_idx<=cal_idx+1'b1;cal_state<=1;end
   end
  end
  // Publish the complete profile only at the next frame boundary.
  6:if(timing[1])begin calibration_busy<=0;calibration_valid<=!bad_capture;frozen_offsets<=offsets;cal_state<=0;end
  default:cal_state<=0;
 endcase
 end end
 // RAM data is never asynchronously reset. Calibration control keeps its
 // reset; the data write port is an independent synchronous-only process.
 assign gain_commit=rst_n && !freeze && !anchor_bad && calibration_busy && cal_state==8 && (div_done || div_pending);
 always @(posedge clk)begin
  if(gain_commit && !vertical_axis)begin
   if(cal_idx[0])gain_x_odd[cal_idx[6:1]]<={result_g,result_r,result_b};
   else gain_x_even[cal_idx[6:1]]<={result_g,result_r,result_b};
  end
  if(gain_commit && vertical_axis)begin
   if(cal_idx[0])gain_y_odd[cal_idx[5:1]]<={vertical_g[11:0],vertical_r[11:0],vertical_b[11:0]};
   else gain_y_even[cal_idx[5:1]]<={vertical_g[11:0],vertical_r[11:0],vertical_b[11:0]};
  end
 end
 always @(posedge clk)begin
  // When the base anchor is odd, the next even anchor is in the next word.
  // The final base anchor reuses itself instead of reading beyond its bank.
  gx_even<=gain_x_even[{auto_mode,((ix[0] && ix<COLS-1)?ix[6:1]+6'd1:ix[6:1])}];
  gx_odd<=gain_x_odd[{auto_mode,ix[6:1]}];
  gy_even<=gain_y_even[{auto_mode,1'b0,((iy[0] && iy<ROWS-1)?iy[5:1]+5'd1:iy[5:1])}];
  gy_odd<=gain_y_odd[{auto_mode,1'b0,(iy[5:1]>21?5'd21:iy[5:1])}];
  ix_odd<=ix[0];iy_odd<=iy[0];ix_last<=ix>=COLS-1;iy_last<=iy>=ROWS-1;
 end
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin t0<=0;t1<=0;t2<=0;out_timing<=0;x0<=0;x1<=0;x2<=0;out_x<=0;y0<=0;y1<=0;y2<=0;out_y<=0;p0<=0;p1<=0;p2<=0;out_rgb<=0;en0<=0;en1<=0;en2<=0;gain_r<=11'd1024;gain_b<=11'd1024;prod_r<=0;prod_b<=0;prod_g<=0;gain_g<=1024;delta2<=0;tone_base1<=0;tone_step1<=0;tone_fraction1<=0;end
 else begin
  gain_r<=(!en0 || (fixed_mode && !calibration_valid && !external_wb))?11'd1024:effective_r<512?11'd512:effective_r>2047?11'd2047:effective_r[10:0];
  gain_b<=(!en0 || (fixed_mode && !calibration_valid && !external_wb))?11'd1024:effective_b<512?11'd512:effective_b>2047?11'd2047:effective_b[10:0];
  gain_g<=!en0?11'd1024:gg<512?11'd512:gg>2047?11'd2047:gg[10:0];
  prod_g<=p1[15:8]*$unsigned(gain_g);
  prod_r<=p1[23:16]*$unsigned(gain_r);prod_b<=p1[7:0]*$unsigned(gain_b);
  tone_base1<=d0;tone_step1<=$signed({d1[7],d1})-$signed({d0[7],d0});tone_fraction1<=ylum[3:0];
  delta2<=tone_limit($signed(tone_base1)+(interp>>>4));
  t0<=timing;t1<=t0;t2<=t1;out_timing<=t2;
  x0<=x;x1<=x0;x2<=x1;out_x<=x2;y0<=y;y1<=y0;y2<=y1;out_y<=y2;
  p0<=rgb;p1<=p0;p2<=p1;en0<=correction_on;en1<=en0;en2<=en1;
  out_rgb<=en2?{tone(corrected_r,combined_delta),tone(corrected_g,combined_delta),tone(corrected_b,combined_delta)}:p2;
 end end
endmodule
