// Executable integration REFERENCE, not a TD board top.
// Input: complete unpacked RGB888 raster (no ready), valid coordinates.
// Output: interior stream, WIDTH-2 by HEIGHT-2, with ORIGINAL coordinates.
// Add output border/timing adapter before connecting any HDMI transmitter.
module image_pipeline #(parameter WIDTH=1280,HEIGHT=720)(
 input wire clk,rst_n,valid,
 input wire [11:0] x,y,
 input wire [23:0] rgb,
 input wire [3:0] requested_mode,
 input wire [1:0] quality,
 output wire out_valid,out_sof,out_eol,
 output wire [11:0] out_x,out_y,
 output wire [3:0] out_mode,
 output wire [23:0] out_rgb,
 output wire red_box_valid,green_box_valid,tracker_overflow,
 output wire [47:0] red_box,green_box,
 output wire [7:0] frame_mean,
 output wire[7:0] target_valid,output wire[383:0] target_boxes,output wire[15:0] target_shapes,
 output wire statistics_valid,statistics_bad,output wire [1:0] red_shape,green_shape
);
 `include "pixel_math.vh"
 wire sof=valid && x==0 && y==0;
 reg eof;
 reg [3:0] frame_mode;
 wire [7:0] bt,et,lo,hi;
 wire stats_busy;
 always @(posedge clk or negedge rst_n) begin
 if(!rst_n)begin eof<=0;frame_mode<=0;end
 else begin eof<=valid && x==WIDTH-1 && y==HEIGHT-1;if(sof)frame_mode<=requested_mode;end
 end
 frame_stats #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) stats(
 clk,rst_n,sof,eof,valid,x,y,luma8(rgb),frame_mean,bt,et,lo,hi,statistics_valid,statistics_bad,stats_busy);
 wire wv;wire [11:0] wx,wy;wire [215:0] w;
 window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) windows(clk,rst_n,valid,x,y,rgb,wv,wx,wy,w);
 // Compute scalar luma and red flags ONCE before the line store. Identical
 // window timing avoids nine copies of the same per-pixel arithmetic.
 wire lum_v,red_v;wire[11:0] lum_x,lum_y,red_x,red_y;wire[71:0] lum_w;wire[17:0] red_w;
 window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BITS(8)) luma_windows(clk,rst_n,valid,x,y,luma8(rgb),lum_v,lum_x,lum_y,lum_w);
 window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BITS(2)) red_windows(clk,rst_n,valid,x,y,{detect_red(rgb),color_class(rgb)==1},red_v,red_x,red_y,red_w);
 wire rh,gh,edge_h;wire[4:0] red_edge_cost,green_edge_cost;
 effects_core #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.PRECOMPUTED(1)) effects(clk,rst_n,wv,wv && wx==1 && wy==1,wv && wx==WIDTH-2,
  wx,wy,frame_mode,quality,frame_mean,bt,et,lo,hi,w,out_valid,out_sof,out_eol,out_x,out_y,out_mode,out_rgb,rh,gh,edge_h,red_edge_cost,green_edge_cost,lum_w,red_w);
 // Area and perimeter MUST describe the same post-majority mask.
 wire mv;wire [11:0] mx,my;wire [8:0] mask_window;
 window3x3 #(.WIDTH(WIDTH-2),.HEIGHT(HEIGHT-2),.BITS(1)) masks(
 clk,rst_n,out_valid,out_x-12'd1,out_y-12'd1,rh,mv,mx,my,mask_window);
 wire [11:0] tx=mx+12'd1,ty=my+12'd1;
 wire [4:0] cost=(mask_window[1]?0:3)+(mask_window[3]?0:3)+(mask_window[5]?0:3)+(mask_window[7]?0:3)+
 (mask_window[0]?0:2)+(mask_window[2]?0:2)+(mask_window[6]?0:2)+(mask_window[8]?0:2);
 reg processed_eof;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)processed_eof<=0;
 else processed_eof<=mv && tx==WIDTH-3 && ty==HEIGHT-3;
 end
 wire rb,gb,ro,go;wire [31:0] ra,ga;
 color_blob_tracker red_tracker(clk,rst_n,mv && tx==2 && ty==2,processed_eof,mv,mv && tx==WIDTH-3,mask_window[4],mask_window[4]?cost:5'd0,tx,ty,
  red_box_valid,rb,ro,red_box[47:36],red_box[35:24],red_box[23:12],red_box[11:0],ra,red_shape,target_valid[3:0],target_boxes[191:0],target_shapes[7:0]);
 // Green specular reflections were repeatedly misclassified as targets.
 // Mode 11 now intentionally tracks only red regions; keep the interface
 // stable and tie the unused green outputs low for the existing OSD ports.
 assign green_box_valid=1'b0;
 assign green_box=48'd0;
 assign green_shape=2'd0;
 assign target_valid[7:4]=4'd0;
 assign target_boxes[383:192]=192'd0;
 assign target_shapes[15:8]=8'd0;
 assign tracker_overflow=ro;
endmodule

// V14 recognition branch: 1-bit line buffers instead of a second RGB pipeline.
// Calibrated pixels are classified BEFORE creative color enhancement.
module red_analysis_pipeline #(parameter WIDTH=1280,HEIGHT=720)(
 input wire clk,rst_n,valid,input wire[11:0] x,y,input wire[23:0] rgb,
 output wire box_valid,output wire[47:0] box,output wire[1:0] shape,
 output wire[3:0] target_valid,output wire[191:0] target_boxes,output wire[7:0] target_shapes
);
 // Include every color accepted by the VISIBLE highlight. effects_core
 // uses color_class()==1 with minimum saturation 1/8. The old detector's
 // 1/4 saturation plus extra skin veto made pale red markers glow while
 // yielding TARGETS:0 forever. Retain its stronger-red branch as well so
 // existing dark/warm-red tracking is not lost. Both predicates reject
 // the yellow/orange and warm skin fixtures; the 5/9 spatial mask rejects
 // isolated sensor speckles before any component can acquire a slot.
 `include "pixel_math.vh"
 wire[7:0] r=rgb[23:16],g=rgb[15:8],b=rgb[7:0];
 wire[8:0] gb_distance=g>b?{1'b0,g}-{1'b0,b}:{1'b0,b}-{1'b0,g};
 wire strong_red=detect_red(rgb) && (({1'b0,g,1'b0}+{2'b0,g}<={1'b0,r,1'b0}) || gb_distance<=16);
 wire target_red=(color_class(rgb)==1) || strong_red;
 reg hit,v;reg[11:0] px,py;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin hit<=0;v<=0;px<=0;py<=0;end
 else begin v<=valid;px<=x;py<=y;hit<=target_red;end
 end
 wire wv;wire[11:0] wx,wy;wire[8:0] w;
 window3x3 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.BITS(1)) denoise(clk,rst_n,v,px,py,hit,wv,wx,wy,w);
 wire[3:0] votes={3'd0,w[0]}+w[1]+w[2]+w[3]+w[4]+w[5]+w[6]+w[7]+w[8];
 // Shape classification uses area moments, not perimeter. Remove the unused
 // second line-window; retain the same 5/9 majority mask without losing an
 // extra border. EOF follows the last valid interior pixel by one clock.
 reg eof;always @(posedge clk or negedge rst_n)if(!rst_n)eof<=0;else eof<=wv&&wx==WIDTH-2&&wy==HEIGHT-2;
 // Four published targets plus two reserve candidates. Tiny completed
 // speckles are recycled by the same two-row/minimum-area rule.
 color_blob_tracker #(.SLOTS(6),.OUTPUTS(4),.MIN_AREA(256),.MIN_SIZE(12),.X_BITS($clog2(WIDTH)),.Y_BITS($clog2(HEIGHT))) detector(clk,rst_n,wv&&wx==1&&wy==1,eof,wv,wv&&wx==WIDTH-2,votes>=5,5'd0,wx,wy,
 box_valid,,,box[47:36],box[35:24],box[23:12],box[11:0],,shape,target_valid,target_boxes,target_shapes);
endmodule
