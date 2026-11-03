// One dark handwritten digit 1..5 on clean light paper. Full-frame 160x90
// 8x8 area pooling, automatic ink bounds, aspect-preserving 28x28 MLP.
// Minimum useful stroke width is roughly 4 pixels; only one digit at a time.
module digit_video_v8(
 input wire clk,rst_n,valid,sof,input wire[11:0] x,y,input wire[23:0] rgb,
 input wire enable,
 output wire [7:0] debug_threshold,output reg [14:0] debug_ink,output wire [3:0] debug_state,
 output reg result_valid,output reg[2:0] result_digit,output reg[47:0] result_box,
 input wire roi_mode,input wire[47:0] roi_box
);
 function [7:0] luma8; input [23:0] p;reg[15:0] sum; begin sum=p[23:16]*16'd77+p[15:8]*16'd150+p[7:0]*16'd29;luma8=sum[15:8];end endfunction
 (* ram_style="bram" *) reg bitmap[0:16383];reg read_bit,read_valid;
 wire rb,rd,req,we,op,mb,md;wire[13:0] addr;wire[9:0] oa;
 wire[2:0] predicted;wire signed[47:0] score,margin;
 reg launch,capture_frame;reg [7:0] xmin,xmax,ymin,ymax;
 reg [14:0] ink;reg[7:0] threshold;
 reg captured_ok;reg[47:0] captured_box;
 reg[9:0] normalized_ink;
 // Blank inputs and filled rectangles can have confident class-5 logits.
 // Require an actual sparse glyph as well as the model score/margin.
 wire prediction_ok=captured_ok && (roi_mode?(normalized_ink>=12 && normalized_ink<=400 && score>0 && margin>=48'sd4096):(margin>0));
 reg pending_valid;reg[2:0] pending_digit,last_digit;reg[47:0] pending_box;
 reg last_ok;reg [2:0] challenger,challenge_count,miss_count;
 assign debug_threshold=threshold;assign debug_state={captured_ok,rb,mb,result_valid};
 // SORT captures the selected object's local raster at 1/2/4/8 pixel pitch.
 // Reuse the SAME 160x90 bitmap, area-pool columns, component finder, resizer
 // and MLP. Full-frame DIGIT retains its original 8x8 path and thresholds.
 reg[11:0] crop_x,crop_y;reg[7:0] crop_lum;reg crop_valid,crop_last,crop_eligible,crop_ink_allowed;
 reg roi_eligible,roi_ink_allowed,roi_calibrated,roi_frame_quality;
 reg[2:0] roi_shift;
 reg[11:0] roi_last_x,roi_last_y;
 reg[7:0] roi_px,roi_py,roi_luma_pool;
 reg roi_first_x,roi_first_y,roi_end_x,roi_end_y,roi_point_valid,roi_end_capture;
 wire[12:0] roi_width={1'b0,roi_box[35:24]}-{1'b0,roi_box[47:36]}+13'd1;
 wire[12:0] roi_height={1'b0,roi_box[11:0]}-{1'b0,roi_box[23:12]}+13'd1;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin crop_x<=0;crop_y<=0;crop_lum<=255;crop_valid<=0;crop_last<=0;crop_eligible<=0;crop_ink_allowed<=0;roi_shift<=3;roi_last_x<=0;roi_last_y<=0;end
  else begin
   crop_x<=x-roi_box[47:36];crop_y<=y-roi_box[23:12];crop_lum<=roi_mode?rgb[23:16]:luma8(rgb);
   crop_eligible<=rgb[15:1]==0;crop_ink_allowed<=rgb[0]==0;
   crop_valid<=valid && x>=roi_box[47:36] && x<=roi_box[35:24] && y>=roi_box[23:12] && y<=roi_box[11:0];
   crop_last<=x==roi_box[35:24] && y==roi_box[11:0];
   roi_last_x<=roi_box[35:24]-roi_box[47:36];roi_last_y<=roi_box[11:0]-roi_box[23:12];
   roi_shift<=roi_width<=160 && roi_height<=90?0:roi_width<=320 && roi_height<=180?1:roi_width<=640 && roi_height<=360?2:3;
  end
 end
 wire[2:0] roi_pool_mask=roi_shift==0?3'd0:roi_shift==1?3'd1:roi_shift==2?3'd3:3'd7;
 // Separate coordinate subtraction from pitch selection, and pitch selection
 // from pooled address/area accumulation. The new ROI tap adds two clocks,
 // while the unchanged display and full-frame DIGIT path add none.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin roi_px<=0;roi_py<=0;roi_luma_pool<=255;roi_first_x<=0;roi_first_y<=0;roi_end_x<=0;roi_end_y<=0;roi_point_valid<=0;roi_end_capture<=0;roi_eligible<=0;roi_ink_allowed<=0;end
  else begin
   roi_px<=crop_x>>roi_shift;roi_py<=crop_y>>roi_shift;roi_luma_pool<=crop_lum;
   roi_first_x<=(crop_x[2:0]&roi_pool_mask)==0;roi_first_y<=(crop_y[2:0]&roi_pool_mask)==0;
   roi_end_x<=(crop_x[2:0]&roi_pool_mask)==roi_pool_mask || crop_x==roi_last_x;
   roi_end_y<=(crop_y[2:0]&roi_pool_mask)==roi_pool_mask || crop_y==roi_last_y;
   roi_point_valid<=crop_valid;roi_end_capture<=crop_last;roi_eligible<=crop_eligible;roi_ink_allowed<=crop_ink_allowed;
  end
 end
 wire[7:0] lum=roi_mode?roi_luma_pool:luma8(rgb);
 wire first_x=roi_mode?roi_first_x:x[2:0]==0,first_y=roi_mode?roi_first_y:y[2:0]==0;
 wire end_x=roi_mode?roi_end_x:x[2:0]==7,end_y=roi_mode?roi_end_y:y[2:0]==7;
 wire in_roi=roi_mode?roi_point_valid:(valid && x<1280 && y<720);
 reg scan_active,scan_fire,scan_hit,scan_center,scan_neighbor,scan_read_inside;
 reg[3:0] scan_phase;
 reg[13:0] scan_linear;
 reg[7:0] scan_x,scan_y,scan_px,scan_py,capture_xmax,capture_ymax;
 // Never start capturing halfway through a frame after inference finishes.
 // If inference overlaps SOF, preserve the old bitmap and skip that frame.
 wire collecting=enable && in_roi && capture_frame && !scan_active;
 wire sample=collecting && end_x && end_y;
 wire[7:0] px=roi_mode?roi_px:x[10:3],py=roi_mode?roi_py:{1'b0,y[9:3]};
 wire[13:0] capture_addr=({6'd0,py}<<7)+({6'd0,py}<<5)+{6'd0,px};
 wire dark_pixel=lum<threshold && (!roi_mode || roi_ink_allowed);
 // 8x8 area pooling removes isolated camera noise before bbox extraction.
 // One-pixel ROI guard prevents a single boundary speck from invalidating a digit.
 reg [3:0] row_ink;(* ram_style="bram" *) reg[6:0] column_ink[0:159];reg[6:0] previous_ink;
 wire[6:0] row_total=first_x?{6'd0,dark_pixel}:({3'd0,row_ink}+dark_pixel);
 wire[6:0] block_total=first_y?row_total:previous_ink+row_total;
 wire[6:0] pool_threshold=roi_mode?(roi_shift==0?7'd1:roi_shift==1?7'd1:roi_shift==2?7'd2:7'd4):7'd32;
 wire black=block_total>=pool_threshold && px>0 && px<159 && py>0 && py<89;
 wire bounds_valid,bounds_done,bounds_busy;
 wire[7:0] bounds_xmin,bounds_xmax,bounds_ymin,bounds_ymax;
 wire[14:0] bounds_area;
 reg bounds_eof;
 always @(posedge clk or negedge rst_n)if(!rst_n)bounds_eof<=0;
 else bounds_eof<=!roi_mode && sample && px==159 && py==89;
 digit_component_bounds_v14_pro components(
 .clk(clk),.rst_n(rst_n),.valid(!roi_mode && sample),.sof(!roi_mode && sample && px==0 && py==0),.eof(bounds_eof),
 .hit(black),.x(px),.y(py),.bbox_valid(bounds_valid),.done(bounds_done),.busy(bounds_busy),
 .xmin(bounds_xmin),.xmax(bounds_xmax),.ymin(bounds_ymin),.ymax(bounds_ymax),.area(bounds_area));
 wire paper_done,paper_busy,paper_roi_quality;wire[7:0] paper_estimate;
 digit_paper_level_v14_pro paper_stats(.clk(clk),.rst_n(rst_n),.valid(collecting && (!roi_mode || (roi_eligible && first_x && first_y))),.sof(sof),.eof(roi_mode?(sample && roi_end_capture):bounds_eof),
 .x(roi_mode?{4'd0,roi_px}:x),.y(roi_mode?{4'd0,roi_py}:y),.lum(lum),.done(paper_done),.busy(paper_busy),.paper_level(paper_estimate),.roi_mode(roi_mode),.roi_quality(paper_roi_quality));
 always @(posedge clk)begin
  if(collecting && first_x)previous_ink<=column_ink[px];
  if(collecting && end_x)column_ink[px]<=block_total;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)row_ink<=0;
  else if(collecting)begin
   if(first_x)row_ink<=dark_pixel;
   else if(!end_x)row_ink<=row_ink+dark_pixel;
  end
 end
 // Nine serial reads of the SAME bitmap remove isolated pixels; no second
 // bitmap or line buffers. In-place removal is exact: an isolated pixel has
 // no neighbour, so removing it cannot alter any other pixel's support.
 reg signed[8:0] scan_offset;reg scan_address_inside;
 always @*begin
  scan_offset=0;scan_address_inside=scan_x<=capture_xmax && scan_y<=capture_ymax;
  case(scan_phase)
   1:begin scan_offset=-161;scan_address_inside=scan_x>0 && scan_y>0;end
   2:begin scan_offset=-160;scan_address_inside=scan_y>0;end
   3:begin scan_offset=-159;scan_address_inside=scan_x<capture_xmax && scan_y>0;end
   4:begin scan_offset=-1;scan_address_inside=scan_x>0;end
   5:begin scan_offset=1;scan_address_inside=scan_x<capture_xmax;end
   6:begin scan_offset=159;scan_address_inside=scan_x>0 && scan_y<capture_ymax;end
   7:begin scan_offset=160;scan_address_inside=scan_y<capture_ymax;end
   8:begin scan_offset=161;scan_address_inside=scan_x<capture_xmax && scan_y<capture_ymax;end
   default:begin end
  endcase
  scan_address_inside=scan_address_inside && scan_x<=capture_xmax && scan_y<=capture_ymax;
 end
 wire[13:0] scan_addr=scan_linear+{{5{scan_offset[8]}},scan_offset};
 wire scan_filtered=scan_center && scan_neighbor;
 wire bitmap_we=sample || (scan_active && scan_phase==10);
 wire[13:0] bitmap_waddr=sample?capture_addr:scan_linear;
 wire bitmap_wdata=sample?black:scan_filtered;
 always @(posedge clk)begin
  read_valid<=req;
  if(req || (scan_active && scan_phase<=8))read_bit<=bitmap[scan_active?scan_addr:addr];
  if(bitmap_we)bitmap[bitmap_waddr]<=bitmap_wdata;
 end
 // SORT knows its owning card already. Union all supported ink instead of
 // applying the full-paper four-component selector, which cut disconnected
 // handwriting into partial glyphs. Unwritten cells are explicitly white.
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin scan_active<=0;scan_phase<=0;scan_fire<=0;scan_x<=0;scan_y<=0;scan_px<=0;scan_py<=0;scan_hit<=0;scan_center<=0;scan_neighbor<=0;scan_read_inside<=0;scan_linear<=0;capture_xmax<=0;capture_ymax<=0;end
  else begin
   scan_fire<=0;
   if(roi_mode && sample && roi_end_capture && roi_calibrated)begin scan_active<=1;scan_phase<=0;scan_x<=0;scan_y<=0;scan_linear<=0;capture_xmax<=px;capture_ymax<=py;end
   else if(scan_active)begin
    scan_phase<=scan_phase+1'b1;
    scan_read_inside<=scan_address_inside;
    if(scan_phase==1)begin scan_center<=read_bit && scan_read_inside;scan_neighbor<=0;end
    if(scan_phase>=2 && scan_phase<=9)scan_neighbor<=scan_neighbor || (read_bit && scan_read_inside);
    if(scan_phase==10)begin scan_fire<=1;scan_px<=scan_x;scan_py<=scan_y;scan_hit<=scan_filtered;end
    if(scan_phase==11)begin
     if(scan_x==159 && scan_y==89)scan_active<=0;
     else begin
      scan_linear<=scan_linear+1'b1;
      if(scan_x==159)begin scan_x<=0;scan_y<=scan_y+1'b1;end
      else scan_x<=scan_x+1'b1;
     end
    end
   end
  end
 end
 bbox_resizer_28x28 #(.IMAGE_WIDTH(160),.IMAGE_HEIGHT(90),.COORD_WIDTH(8),.ADDR_WIDTH(14)) resize(
 .clk(clk),.rst_n(rst_n),.start(launch),.bbox_valid(captured_ok),
 .bbox_x_min(xmin),.bbox_y_min(ymin),.bbox_x_max(xmax),.bbox_y_max(ymax),
 .busy(rb),.done(rd),.src_req(req),.src_addr(addr),.src_valid(read_valid),.src_pixel(read_bit),
 .out_we(we),.out_addr(oa),.out_pixel(op));
 digit_mlp_classifier mlp(clk,rst_n,we,oa,op,rd,mb,md,predicted,score,margin);
 integer j;reg[7:0] paper,drop;
 function[11:0] smooth;input[11:0] a,b;reg[13:0] total;reg[11:0] delta;begin delta=a>b?a-b:b-a;total={2'd0,a}+{1'b0,a,1'b0}+{2'd0,b}+2;smooth=delta<=2?a:delta>128?b:total[13:2];end endfunction
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   debug_ink<=0;xmin<=159;xmax<=0;ymin<=89;ymax<=0;ink<=0;threshold<=140;launch<=0;capture_frame<=0;
   captured_ok<=0;captured_box<=0;pending_valid<=0;pending_digit<=0;pending_box<=0;
   roi_calibrated<=0;roi_frame_quality<=0;normalized_ink<=0;
   result_valid<=0;result_digit<=0;result_box<=0;last_digit<=0;last_ok<=0;challenger<=0;challenge_count<=0;miss_count<=0;
  end else begin
   launch<=0;
   if(sof)begin
    capture_frame<=enable && !rb && !mb && !bounds_busy && !paper_busy && !launch && !scan_active;
    if(!roi_mode || !scan_active)ink<=0;
    result_valid<=enable && pending_valid;result_digit<=pending_digit;result_box<=pending_box;
    if(!enable)begin pending_valid<=0;last_ok<=0;challenge_count<=0;miss_count<=0;end
   end
   if(sample && enable)begin
    if(black)begin
     ink<=ink+1'b1;
    end
   end
   if(roi_mode && sample && roi_end_capture)begin
    xmin<=159;xmax<=0;ymin<=89;ymax<=0;ink<=0;
   end
   if(roi_mode && scan_fire)begin
    if(scan_hit)begin
     ink<=ink+1'b1;
     if(scan_px<xmin)xmin<=scan_px;if(scan_px>xmax)xmax<=scan_px;
     if(scan_py<ymin)ymin<=scan_py;if(scan_py>ymax)ymax<=scan_py;
    end
    if(scan_px==159 && scan_py==89)begin
     captured_ok<=roi_frame_quality && ink>=6 && xmax>xmin && {1'b0,ymax}>={1'b0,ymin}+9'd3;
     captured_box<=roi_box;debug_ink<=ink;launch<=1;
    end
   end
   if(launch)normalized_ink<=0;
   else if(we && op)normalized_ink<=normalized_ink+1'b1;
   if(enable && capture_frame && valid && x==1279 && y==719 && !rb && !mb)begin
    debug_ink<=ink;
   end
   if(paper_done && enable && roi_mode)begin
    // Robust card-specific calibration reuses the existing histogram RAM.
    // It finishes after the ROI, so each captured bitmap has one threshold.
    threshold<=paper_estimate;roi_calibrated<=1;roi_frame_quality<=paper_roi_quality;
   end
   if(paper_done && enable && !roi_mode)begin
    // The supported bright-paper cluster, not dark surrounding desk pixels,
    // sets the next frame's binary threshold.
    paper=paper_estimate;drop=(paper>>4)<8?8:(paper>>4);
    threshold<=paper>drop+8?paper-drop:8;
   end
   if(bounds_done && enable && !roi_mode)begin
    // Ignore the frame-border component (dark desk around light paper) and
    // tiny speckles. The biggest internal connected stroke supplies the box.
    captured_ok<=bounds_valid;debug_ink<=bounds_area;
    xmin<=bounds_xmin;xmax<=bounds_xmax;ymin<=bounds_ymin;ymax<=bounds_ymax;
    // SORT publishes the owning card ROI; no four variable-width shifts and
    // adders are needed merely to reconstruct a hidden debug ink rectangle.
    if(roi_mode)captured_box<=roi_box;
    else captured_box<={{1'b0,bounds_xmin,3'd0},({1'b0,bounds_xmax,3'd0}+12'd7),{1'b0,bounds_ymin,3'd0},({1'b0,bounds_ymax,3'd0}+12'd7)};
    launch<=1;
   end
   if(md && enable)begin
    last_ok<=prediction_ok;last_digit<=predicted;
    if(prediction_ok)begin
     miss_count<=0;
     if(!pending_valid)begin
      if(last_ok && last_digit==predicted)begin pending_valid<=1;pending_digit<=predicted+1'b1;pending_box<=captured_box;end
      challenge_count<=0;
     end else if(pending_digit==predicted+1'b1)begin
      challenge_count<=0;for(j=0;j<4;j=j+1)pending_box[j*12+:12]<=smooth(pending_box[j*12+:12],captured_box[j*12+:12]);
     end else begin
      if(challenger==predicted)begin
       if(challenge_count>=3)begin pending_digit<=predicted+1'b1;pending_box<=captured_box;challenge_count<=0;end
       else challenge_count<=challenge_count+1'b1;
      end else begin challenger<=predicted;challenge_count<=1;end
     end
    end else begin
     challenge_count<=0;
     if(miss_count>=2)begin pending_valid<=0;miss_count<=3;end
     else miss_count<=miss_count+1'b1;
    end
   end
  end
 end
endmodule

