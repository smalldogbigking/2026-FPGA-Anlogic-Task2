// Generic synchronous, read-before-write two-line store. No memory reset.
// Produces INTERIOR pixels only: x=1..WIDTH-2, y=1..HEIGHT-2.
// Caller supplies ordered raster coordinates and valid, including SOF pixel.
// Output center coordinate is (input_x-1,input_y-1). Do not wire out_valid
// directly as 720p DE: integration must restore a one-pixel border.
module window3x3 #(parameter WIDTH=1280,HEIGHT=720,BITS=24)(
 input wire clk,rst_n,valid,
 input wire [11:0] x,y,
 input wire [BITS-1:0] pixel,
 output reg out_valid,
 output reg [11:0] out_x,out_y,
 output reg [BITS*9-1:0] window_data
);
 reg [BITS-1:0] line1[0:WIDTH-1],line2[0:WIDTH-1];
 reg [BITS-1:0] a,b,c,al,all,bl,bll,cl,cll;
 reg [11:0] qx,qy;
 reg qvalid;
 always @(posedge clk) begin
 if(valid && x<WIDTH && y<HEIGHT) begin
 a<=line2[x];b<=line1[x];c<=pixel;
 line1[x]<=pixel;
 end
 if(qvalid)line2[qx]<=b;
 end
 always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
 qvalid<=0;qx<=0;qy<=0;out_valid<=0;out_x<=0;out_y<=0;window_data<=0;
 al<=0;all<=0;bl<=0;bll<=0;cl<=0;cll<=0;
 end else begin
 qvalid<=valid && x<WIDTH && y<HEIGHT;qx<=x;qy<=y;
 out_valid<=qvalid && qx>=2 && qy>=2;
 if(qvalid) begin
 if(qx==0) begin al<=a;all<=a;bl<=b;bll<=b;cl<=c;cll<=c; end
 else begin all<=al;al<=a;bll<=bl;bl<=b;cll<=cl;cl<=c;end
 if(qx>=2 && qy>=2) begin
 window_data<={all,al,a,bll,bl,b,cll,cl,c};out_x<=qx-1'b1;out_y<=qy-1'b1;
 end
 end
 end
 end
endmodule
