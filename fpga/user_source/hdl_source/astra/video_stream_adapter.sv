module video_stream_adapter #(parameter WIDTH=1280,HEIGHT=720,H_TOTAL=1650,ENABLE_FACE=1)(
 input wire clk,rst_n,in_vs,in_hs,in_de,in_user,in_last,
 input wire [23:0] ddr_rgb,input wire [3:0] requested_mode,
 input wire [1:0] quality,input wire beauty,
 output wire out_vs,out_hs,out_de,out_user,out_last,
 output wire [23:0] out_rgb,
 output wire red_box_valid,green_box_valid,output wire [1:0] red_shape,green_shape,output reg [7:0] processing_us,
 output wire [7:0] scene_mean,output wire scene_toggle,
 output wire [47:0] red_box,green_box,
 output wire[7:0] target_valid,output wire[383:0] target_boxes,output wire[15:0] target_shapes,
 output wire gesture_valid,output wire [2:0] gesture_value,output wire [47:0] gesture_box,
 output wire [191:0] after_histogram,output wire [191:0] histogram,output wire [31:0] balance_gains,
 output wire motion_valid,output wire [47:0] motion_box,output wire [11:0] motion_count,
 output wire [7:0] digit_threshold,output wire [14:0] digit_ink,output wire [3:0] digit_state,
 output wire digit_valid,output wire[2:0] digit_value,output wire[47:0] digit_box,
 input wire [1:0] correction_mode,input wire calibrate,freeze,recognition_ready,face_track,
 output wire calibration_busy,calibration_valid,output wire[15:0] wb_status,output wire[7:0] tone_status,
 output wire face_valid,output wire[47:0] face_box,output wire[7:0] face_confidence,
 output wire face_update,output wire[47:0] face_measurement_box,output wire[7:0] face_measurement_age,
 input wire external_wb,input wire[7:0] external_r,external_b,
 input wire sort_active,input wire[15:0] sort_source_frame,
 output wire[287:0] sort_records,output wire[3:0] sort_valid,output wire[15:0] sort_frame,
 output wire[11:0] sort_digits,sort_classes,output wire[7:0] sort_shapes,
 input wire[3:0] external_saturation
);
 localparam DELAY=H_TOTAL+6;
 reg [4:0] timing0,timing1;
 reg [11:0] x,y,x0,y0,x1,y1;
 wire [11:0] sx=in_user?12'd0:x,sy=in_user?12'd0:y;
 reg [3:0] mode_frame;
 reg [1:0] quality_frame;reg beauty_frame;reg [3:0] saturation_frame;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)saturation_frame<=15;
  else if(in_user && !freeze)saturation_frame<=external_saturation;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)begin timing0<=0;timing1<=0;x<=0;y<=0;x0<=0;y0<=0;x1<=0;y1<=0;mode_frame<=0;quality_frame<=0;beauty_frame<=0;end
  else begin
   timing0<={in_vs,in_hs,in_de,in_user,in_last};timing1<=timing0;
   x0<=sx;y0<=sy;x1<=x0;y1<=y0;
   if(in_user && !freeze)begin mode_frame<=requested_mode;quality_frame<=quality;beauty_frame<=beauty;end
   if(in_de)begin
    if(in_last)begin x<=0;y<=sy+1'b1;end
    else begin x<=sx+1'b1;y<=sy;end
   end else if(in_user)begin x<=0;y<=0;end
  end
 end
 wire [4:0] clean_t;wire [11:0] clean_x,clean_y;wire [23:0] clean_rgb;
 wire [4:0] balanced_t;wire [11:0] balanced_x,balanced_y;wire [23:0] balanced_rgb;
 isp_balance_v11 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) balance(clk,rst_n,beauty_frame,timing1,x1,y1,ddr_rgb,balanced_t,balanced_x,balanced_y,balanced_rgb,scene_mean,scene_toggle,histogram,balance_gains,correction_mode,calibrate,calibration_busy,calibration_valid,wb_status,tone_status,freeze,external_wb,external_r,external_b);
 motion_v11 #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) motion(clk,rst_n,clean_t[2],clean_t[1],clean_x,clean_y,clean_rgb,scene_mean,motion_valid,motion_box,motion_count);
 input_conditioner #(.WIDTH(WIDTH)) conditioner(clk,rst_n,balanced_t,balanced_x,balanced_y,balanced_rgb,quality_frame,beauty_frame,scene_mean,clean_t,clean_x,clean_y,clean_rgb,correction_mode,calibration_valid,freeze,saturation_frame);
 beauty_hist_pro #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) compare_hist(clk,rst_n,clean_t[2],clean_t[1],clean_x,clean_y,clean_rgb,after_histogram);
 // Delay original center pixel and ALL timing by one line + one pixel +
 // five pipeline clocks. No memory reset: warm-up suppresses uninitialized RAM.
 // Physical RAM is rounded to a power of two, but the circular address
 // still wraps at DELAY. This preserves every pixel/timing cycle while
 // preventing TD from converting the out-of-range read guard into LUT RAM.
 localparam RASTER_AW=$clog2(DELAY+1);
 (* ram_style="bram" *) reg [28:0] raster[0:(1<<RASTER_AW)-1];
 reg [RASTER_AW-1:0] ptr,readptr;reg [11:0] filled;
 reg [28:0] delayed;
 always @(posedge clk)begin
  delayed<=raster[readptr];
  if(rst_n)raster[ptr]<={clean_t,clean_rgb};
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin ptr<=0;readptr<=1;filled<=0;end
  else begin ptr<=(ptr==DELAY)?0:ptr+1'b1;readptr<=(readptr==DELAY)?0:readptr+1'b1;if(filled<DELAY)filled<=filled+1'b1;end
 end
 wire[7:0] tv;wire[383:0] tb;wire[15:0] ts;
 // Bound the mode-reset load. A single decoded LUT otherwise drives hundreds
 // of asynchronous reset pins across the device and fails recovery timing.
 // Replication changes placement only; reset and enable behavior are identical.
 (* max_fanout=32 *) wire red_enable=sort_active || (!face_track && (mode_frame==11 || (mode_frame==14 && recognition_ready)));
 (* max_fanout=32 *) wire red_reset_n=rst_n && red_enable;
 // Publish only persistent targets. Geometry is smoothed and classification
 // must agree for three frames before replacing the displayed label.
 target_publish_serial publish_targets(clk,red_reset_n,clean_t[1],freeze,tv,tb,ts,target_valid,target_boxes,target_shapes);
 // HAND removed: keep status ports tied off for protocol compatibility.
 assign gesture_valid=1'b0;assign gesture_value=3'd0;assign gesture_box=48'd0;
 generate if(ENABLE_FACE)begin: optional_face
 face_candidate_v14_pro #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) face_detector(.clk(clk),.rst_n(rst_n),.valid(clean_t[2]),.sof(clean_t[1]),.enable(face_track && recognition_ready),.x(clean_x),.y(clean_y),.rgb(clean_rgb),.result_valid(face_valid),.result_box(face_box),.confidence(face_confidence),.result_update(face_update),.measurement_box(face_measurement_box),.measurement_age(face_measurement_age));
 end else begin: no_face
 assign face_valid=0;assign face_box=0;assign face_confidence=0;assign face_update=0;assign face_measurement_box=0;assign face_measurement_age=0;
 end endgenerate
 wire[47:0] sort_roi;wire sort_digit_reset,sort_digit_enable;wire[23:0] sort_rgb;wire[1:0] sort_roi_shape;
 sort_roi_adapter #(.BLACK_TEXT(1)) sort_pixels(balanced_x,balanced_y,balanced_rgb,sort_roi,sort_rgb,1'b1,clk,rst_n);
 wire measured_valid;wire[1:0] measured_shape;
 // TRACK and SORT now share the hole-filled silhouette classification.
 // Do not override it with six sparse probes that can land on handwriting.
 assign measured_valid=sort_roi_shape==1 || sort_roi_shape==3;
 assign measured_shape=sort_roi_shape;
 sort_target_round_robin sort_poll(.clk(clk),.rst_n(rst_n),.enable(sort_active),.sof(balanced_t[1]),
 .source_frame(sort_source_frame),.target_valid(target_valid[3:0]),.target_boxes(target_boxes[191:0]),.target_shapes(target_shapes[7:0]),
 .digit_valid(digit_valid),.digit(digit_value),.roi_box(sort_roi),.digit_reset(sort_digit_reset),.digit_enable(sort_digit_enable),
 .records(sort_records),.record_valid(sort_valid),.record_frame(sort_frame),.digits(sort_digits),.classes(sort_classes),.roi_shape(sort_roi_shape),.measured_shape_valid(measured_valid),.measured_shape(measured_shape),.sort_shapes(sort_shapes));
 // Isolate ROI/mode pixel selection from the original luma/pooling path.
 // This delays only the analysis tap by one clock; HDMI timing is unchanged.
 reg[23:0] digit_rgb_q;reg[11:0] digit_x_q,digit_y_q;
 reg digit_valid_q,digit_sof_q,digit_enable_q;
 always @(posedge clk)begin
  digit_rgb_q<=sort_active?sort_rgb:balanced_rgb;digit_x_q<=balanced_x;digit_y_q<=balanced_y;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin digit_valid_q<=0;digit_sof_q<=0;digit_enable_q<=0;end
  else begin digit_valid_q<=balanced_t[2];digit_sof_q<=balanced_t[1];digit_enable_q<=(mode_frame==12 && !sort_active)||sort_digit_enable;end
 end
 digit_video_v8 digits(clk,rst_n && !sort_digit_reset,digit_valid_q,digit_sof_q,digit_x_q,digit_y_q,digit_rgb_q,digit_enable_q,digit_threshold,digit_ink,digit_state,digit_valid,digit_value,digit_box,sort_active,sort_roi);
 wire pv,rbv,gbv,stats_done;wire [1:0] rs,gs;
 reg measuring;reg [6:0] micro_ticks;reg [7:0] micro_count;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin measuring<=0;micro_ticks<=0;micro_count<=0;processing_us<=0;end
  else if(in_user)begin measuring<=1;micro_ticks<=0;micro_count<=0;end
  else if(measuring)begin
   if(micro_ticks==74)begin micro_ticks<=0;micro_count<=micro_count+1'b1;end else micro_ticks<=micro_ticks+1'b1;
   if(out_user)begin measuring<=0;processing_us<=micro_count;end
  end
 end
 wire [7:0] effect_mean;
 wire [23:0] prgb;wire [47:0] rb,gb;
 wire [3:0] pm;
 image_pipeline #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) u_image_pipeline(
  .clk(clk),.rst_n(rst_n),.valid(clean_t[2]),.x(clean_x),.y(clean_y),.rgb(clean_rgb),
  .requested_mode((sort_active || mode_frame==14)?4'd11:mode_frame),.quality(quality_frame),
  .out_valid(pv),.out_sof(),.out_eol(),.out_x(),.out_y(),.out_mode(pm),.out_rgb(prgb),
  .red_box_valid(),.green_box_valid(),.red_box(),.green_box(),
  .red_shape(),.green_shape(),.target_valid(),.target_boxes(),.target_shapes(),.tracker_overflow(),.frame_mean(effect_mean),.statistics_valid(stats_done),.statistics_bad());
 // Red analysis uses the same denoised pixels as the highlight, so a visible red
 // patch and its box cannot disagree due to different ISP branches. Digit/hand/
 // face use balanced full-resolution pixels before display pixelation.
 red_analysis_pipeline #(.WIDTH(WIDTH),.HEIGHT(HEIGHT)) recognition(
 .clk(clk),.rst_n(red_reset_n),.valid(clean_t[2] && red_enable),.x(clean_x),.y(clean_y),.rgb(clean_rgb),
 .box_valid(rbv),.box(rb),.shape(rs),.target_valid(tv[3:0]),.target_boxes(tb[191:0]),.target_shapes(ts[7:0]));
 assign gbv=0;assign gb=0;assign gs=0;assign tv[7:4]=0;assign tb[383:192]=0;assign ts[15:8]=0;
 circle_box_confirm_v4 red_confirm(clk,red_reset_n,clean_t[1],rbv,rb,red_box_valid,red_box,rs,red_shape);
 circle_box_confirm_v4 green_confirm(clk,rst_n,clean_t[1],gbv,gb,green_box_valid,green_box,gs,green_shape);
 assign {out_vs,out_hs,out_de,out_user,out_last}=(filled==DELAY)?delayed[28:24]:5'd0;
 assign out_rgb=!out_de?24'd0:(pv?prgb:delayed[23:0]);
endmodule


// Four targets share one arithmetic unit and one 16x12 history ERAM.
// Read/modify/write coordinates in 40 SOF blanking clocks, before the
// 64-clock SORT ownership check and the delayed HDMI SOF. Frame-visible
// geometry, confirmation, smoothing and shape filters match the V2 publisher.
module target_publish_serial(input wire clk,red_reset_n,trigger,freeze,
 input wire[7:0]tv,input wire[383:0]tb,input wire[15:0]ts,
 output reg[7:0]target_valid,output reg[383:0]target_boxes,output reg[15:0]target_shapes);
 (* ram_style="distributed" *) reg[11:0] candidate_coords[0:15];
 reg[11:0] candidate_q;reg[3:0] candidate_seen;reg[1:0]candidate_shape[0:3];
 reg[2:0]agree[0:3],shape_agree[0:3],missing[0:3];
 reg busy;reg[1:0]phase,slot,coord;reg[11:0]incoming_coordinate;reg[47:0]blended_box;
 reg[1:0]kind,previous_kind;reg present,old_valid;
 reg[2:0]old_agree,old_shape_agree,old_missing;
 reg[9:0]distance_sum;reg distance_far;
 wire signed[12:0]dd=$signed({1'b0,incoming_coordinate})-$signed({1'b0,(candidate_seen[slot]?candidate_q:12'd0)});
 wire[12:0]ad=dd[12]?-dd:dd;
 wire[13:0]weighted=({2'b0,target_boxes[coord*12+:12]}<<1)+{2'b0,target_boxes[coord*12+:12]}+{2'b0,incoming_coordinate}+14'd2;
 // Memory has no asynchronous reset; the four valid bits mask old contents.
 always @(posedge clk)begin
  candidate_q<=candidate_coords[{slot,coord}];
  if(red_reset_n && busy && phase==2 && present)
   candidate_coords[{slot,coord}]<=incoming_coordinate;
 end
 wire close_enough=!distance_far && distance_sum<=128;
 wire publish_box=present && close_enough && old_agree>=2;
 wire next_valid=present?(close_enough?(old_agree>=2?1'b1:old_valid):1'b0):
                         (old_missing>=2?1'b0:old_valid);
 wire[1:0] next_shape=publish_box && (!old_valid || (old_shape_agree>=2 && previous_kind==kind))?kind:target_shapes[1:0];
 integer i;
 always @(posedge clk or negedge red_reset_n)begin
 if(!red_reset_n)begin
 target_valid<=0;target_boxes<=0;target_shapes<=0;busy<=0;phase<=0;slot<=0;coord<=0;
 incoming_coordinate<=0;candidate_seen<=0;blended_box<=0;kind<=0;previous_kind<=0;present<=0;old_valid<=0;
 old_agree<=0;old_shape_agree<=0;old_missing<=0;distance_sum<=0;distance_far<=0;
 for(i=0;i<4;i=i+1)begin candidate_shape[i]<=0;agree[i]<=0;shape_agree[i]<=0;missing[i]<=0;end
 end else begin
 if(trigger && !freeze && !busy)begin busy<=1;phase<=0;slot<=0;end
 if(busy)case(phase)
 0:begin
  kind<=ts[slot*2+:2];previous_kind<=candidate_shape[slot];present<=tv[slot];old_valid<=target_valid[0];
  old_agree<=agree[slot];old_shape_agree<=shape_agree[slot];old_missing<=missing[slot];
  distance_sum<=0;distance_far<=0;coord<=0;phase<=1;
 end
 1:begin
  // Input boxes are frame registers. Fetch just this coordinate while
  // the same-address history RAM read completes.
  incoming_coordinate<=tb[({slot,coord}*12)+:12];phase<=2;
 end
 2:begin
  distance_sum<=distance_sum+{2'd0,ad[7:0]};distance_far<=distance_far || (|ad[12:8]);
  blended_box[coord*12+:12]<=old_valid?weighted[13:2]:incoming_coordinate;
  if(coord==3)phase<=3;else begin coord<=coord+1'b1;phase<=1;end
 end
 3:begin
  if(present)begin
   missing[slot]<=0;candidate_seen[slot]<=1;candidate_shape[slot]<=kind;
   if(previous_kind==kind)begin if(old_shape_agree<4)shape_agree[slot]<=old_shape_agree+1'b1;end
   else shape_agree[slot]<=1;
   if(close_enough)begin if(old_agree<4)agree[slot]<=old_agree+1'b1;end
   else agree[slot]<=1;
  end else begin agree[slot]<=0;shape_agree[slot]<=0;if(old_missing<2)missing[slot]<=old_missing+1'b1;end
  // Rotate four lanes in SOF blanking. Constant slices eliminate the
  // 192-bit indexed read/write network. Four rotations restore slot order
  // by clock 40, before SORT reads at 64 and HDMI's line-delayed SOF.
  target_boxes[191:0]<={publish_box?blended_box:target_boxes[47:0],target_boxes[191:48]};
  target_valid[3:0]<={next_valid,target_valid[3:1]};
  target_shapes[7:0]<={next_shape,target_shapes[7:2]};
  phase<=0;if(slot==3)busy<=0;else slot<=slot+1'b1;
 end
 endcase
 end end
endmodule
