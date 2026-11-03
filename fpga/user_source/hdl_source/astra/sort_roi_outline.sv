// SORT-only six probes on three outer-contour rows. Probe columns lie outside
// the central printed-glyph rectangle, so character holes do not affect shape.
// Axis-aligned, nearly square cards are required; partial probe patterns reject.
module sort_roi_outline(input wire clk,rst_n,enable,valid,sof,
 input wire[11:0] x,y,input wire[23:0] rgb,input wire[47:0] box,
 output reg shape_valid,output reg[1:0] shape);
 wire[7:0] px=x[10:3],left_x=box[46:39],right_x=box[34:27];
 wire[6:0] py=y[9:3],top_y=box[21:15],last_y=box[9:3];
 wire[8:0] width={1'b0,right_x}-{1'b0,left_x}+9'd1;
 wire[7:0] height={1'b0,last_y}-{1'b0,top_y}+8'd1;
 wire[7:0] column_left=left_x+(width>>3),column_right=right_x-(width>>3)+1'b1;
 wire[6:0] row_top=top_y+(height>>3),row_mid=top_y+(height>>1),row_bottom=last_y-(height>>3)+1'b1;
 wire red=rgb[23:21]>=3 && rgb[23:21]>rgb[15:13] && rgb[23:21]>rgb[7:5];
 wire[8:0] h9={1'b0,height};
 wire aspect_ok=width>=8 && height>=8 && width>=h9-(h9>>2) && width<=h9+(h9>>2);
 reg[5:0] probes;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin probes<=0;shape_valid<=0;shape<=0;end
 else if(!enable)begin probes<=0;shape_valid<=0;shape<=0;end
 else begin
  if(sof)begin
   shape_valid<=0;shape<=0;probes<=0;
   if(aspect_ok && probes[3:2]==2'b11)begin
    if({probes[5:4],probes[1:0]}==0)begin shape_valid<=1;shape<=1;end
    else if({probes[5:4],probes[1:0]}==4'b1111)begin shape_valid<=1;shape<=3;end
   end
  end
  if(valid && !sof && x[2:0]==0 && y[2:0]==0 && red)begin
   if(py==row_top)begin if(px==column_left)probes[0]<=1;if(px==column_right)probes[1]<=1;end
   if(py==row_mid)begin if(px==column_left)probes[2]<=1;if(px==column_right)probes[3]<=1;end
   if(py==row_bottom)begin if(px==column_left)probes[4]<=1;if(px==column_right)probes[5]<=1;end
  end
 end end
endmodule
