// Integrated motion front end. Original decisions retained, three pipeline clocks.
module motion_frontend_v11(
 input wire clk,rst_n,valid,sof,input wire[11:0] x,y,input wire[23:0] rgb,input wire[7:0] mean,
 output reg[7:0] filtered,output wire out_valid,out_sof,output wire[11:0] out_x,out_y,output wire[7:0] out_mean
);
 wire[9:0] rb={2'd0,rgb[23:16]}+{2'd0,rgb[7:0]};
 wire[9:0] total=rb+{1'd0,rgb[15:8],1'b0};
 reg[7:0] h0,h1,a1,b1,c1,median2;
 reg[33:0]meta1,meta2,meta3;
 function[7:0] med3;input[7:0]a,b,c;
 begin med3=a>b?(b>c?b:(a>c?c:a)):(a>c?a:(b>c?c:b));end endfunction
 assign {out_valid,out_sof,out_x,out_y,out_mean}=meta3;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin h0<=0;h1<=0;a1<=0;b1<=0;c1<=0;median2<=0;filtered<=0;meta1<=0;meta2<=0;meta3<=0;end
 else begin
 if(valid)begin h1<=x==0?total[9:2]:h0;h0<=total[9:2];end
 a1<=total[9:2];b1<=h0;c1<=h1;
 meta1<={valid,sof,x,y,mean};meta2<=meta1;meta3<=meta2;
 median2<=meta1[31:20]>=2?med3(a1,b1,c1):a1;
 filtered<=median2;
 end end
endmodule
module motion_v11 #(parameter WIDTH=1280,HEIGHT=720)(
 input wire clk,rst_n,valid,sof,input wire[11:0] x,y,input wire[23:0] rgb,input wire[7:0] mean,
 output wire box_valid,output wire[47:0] box,output wire[11:0] changed
);
 wire[7:0] filtered,fmean;wire v,s;wire[11:0] px,py;
 motion_frontend_v11 front(clk,rst_n,valid,sof,x,y,rgb,mean,filtered,v,s,px,py,fmean);
 motion_v11_filter_core #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) core(
 .pre_filtered(filtered),.clk(clk),.rst_n(rst_n),.valid(v),.sof(s),.x(px),.y(py),
 .rgb(24'd0),.mean(fmean),.box_valid(box_valid),.box(box),.changed(changed));
endmodule
// Noise-robust 80x45 motion grid: horizontal median before frame difference,
// adjacent horizontal + vertical support removes scattered noise hits.
module motion_v11_filter_core #(parameter WIDTH=1280,HEIGHT=720)(
 input wire[7:0] pre_filtered,
 input wire clk,rst_n,valid,sof,input wire [11:0] x,y,
 input wire [23:0] rgb,input wire [7:0] mean,
 output reg box_valid,output reg [47:0] box,output reg [11:0] changed
);
 localparam [11:0] LAST_X=WIDTH-1,LAST_Y=HEIGHT-1;
 localparam COLS=(WIDTH+15)/16,ROWS=(HEIGHT+15)/16,N=COLS*ROWS;
 reg [7:0] previous[0:N-1];reg [7:0] old,now;
 reg [11:0] addr_q,xq,yq;reg sample_q,warm;
 reg [11:0] hits,xmin,xmax,ymin,ymax;
 reg [7:0] last_mean;reg signed [9:0] delta;
 reg [COLS-1:0] upper_hits;reg left_hit;reg [1:0] exposure_quiet;
 wire sample=valid && x[3:0]==0 && y[3:0]==0;
 wire [11:0] address=(y>>4)*COLS+(x>>4);
 wire[7:0] filtered=pre_filtered;
 wire signed [10:0] difference=$signed({1'b0,now})-$signed({1'b0,old})-delta;
 wire moving=difference>24 || difference < -24;
 wire supported=moving && xq>=16 && yq>=16 && left_hit && upper_hits[xq>>4];
 wire [11:0] bx=xq>=16?xq-16:0,by=yq>=16?yq-16:0;
 wire signed [9:0] mean_step=$signed({1'b0,mean})-$signed({1'b0,last_mean});
 always @(posedge clk)begin
  if(sample)begin old<=previous[address];now<=filtered;end
  if(sample_q)previous[addr_q]<=now;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin sample_q<=0;addr_q<=0;xq<=0;yq<=0;warm<=0;hits<=0;xmin<=4095;xmax<=0;ymin<=4095;ymax<=0;box_valid<=0;box<=0;changed<=0;last_mean<=128;delta<=0;upper_hits<=0;left_hit<=0;exposure_quiet<=0;end
  else begin
   sample_q<=sample;addr_q<=address;xq<=x;yq<=y;
   if(sof)begin hits<=0;xmin<=4095;xmax<=0;ymin<=4095;ymax<=0;upper_hits<=0;left_hit<=0;last_mean<=mean;delta<=mean_step;
    if(mean_step>10 || mean_step< -10)exposure_quiet<=2;else if(exposure_quiet!=0)exposure_quiet<=exposure_quiet-1'b1;
   end
   if(sample_q && warm)begin
    left_hit<=moving;upper_hits[xq>>4]<=moving;
    if(supported && exposure_quiet==0)begin
     hits<=hits+1'b1;
     if(bx<xmin)xmin<=bx;if(xq>xmax)xmax<=xq;
     if(by<ymin)ymin<=by;if(yq>ymax)ymax<=yq;
    end
   end
   if(valid && x==WIDTH-1 && y==HEIGHT-1)begin
    warm<=1;changed<=hits;
    // A dispersed full-frame change is exposure/noise, not a moving object.
    box_valid<=warm && exposure_quiet==0 && hits>=3 && hits<N/2 &&
     !((xmax-xmin)>WIDTH*3/4 && (ymax-ymin)>HEIGHT*3/4);
    box<={xmin,((xmax+12'd15>=WIDTH)?LAST_X:xmax+12'd15),ymin,((ymax+12'd15>=HEIGHT)?LAST_Y:ymax+12'd15)};
   end
  end
 end
endmodule
