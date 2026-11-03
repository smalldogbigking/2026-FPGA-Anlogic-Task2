// Stable 16x16 region color: previous complete tile mean, current full-res outlines.
// A bounded one-frame color lag is traded for flat, noise-free interiors.
module cartoon_regions_v8 #(parameter WIDTH=1280,HEIGHT=720)(
 input wire clk,rst_n,valid,input wire[11:0] x,y,input wire[23:0] rgb,
 output reg[23:0] color,output reg color_valid);
 localparam COLS=(WIDTH+15)/16,ROWS=(HEIGHT+15)/16;
 reg[47:0] row_sums[0:COLS-1];(* ram_style="bram" *) reg[23:0] colors[0:COLS*ROWS-1];
 reg[47:0] column;reg[11:0] sr,sg,sb;reg filled;
 wire[12:0] rr={1'b0,sr}+rgb[23:16],gg={1'b0,sg}+rgb[15:8],bb={1'b0,sb}+rgb[7:0];
 wire[16:0] tr={1'b0,column[47:32]}+rr,tg={1'b0,column[31:16]}+gg,tb={1'b0,column[15:0]}+bb;
 wire interior=x>=16 && x<WIDTH-16 && y>=16 && y<HEIGHT-16;
 wire[15:0] tile=(y>>4)*COLS+(x>>4);
 always @(posedge clk)begin
 color<=colors[tile];
 if(valid)begin
  if(x[3:0]==0)column<=row_sums[x>>4];
  if(x[3:0]==15)begin
   row_sums[x>>4]<=(y[3:0]==0)?{3'd0,rr,3'd0,gg,3'd0,bb}:{tr[15:0],tg[15:0],tb[15:0]};
   if(y[3:0]==15)colors[tile]<={tr[15:8],tg[15:8],tb[15:8]};
  end
 end
 end
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin sr<=0;sg<=0;sb<=0;filled<=0;color_valid<=0;end
 else begin
 color_valid<=valid && filled && interior;
 if(valid)begin
 if(x==WIDTH-2 && y==HEIGHT-2)filled<=1;
 if(x[3:0]==0)begin sr<=rgb[23:16];sg<=rgb[15:8];sb<=rgb[7:0];end
 else begin sr<=rr[11:0];sg<=gg[11:0];sb<=bb[11:0];end
 end
 end
 end
endmodule
