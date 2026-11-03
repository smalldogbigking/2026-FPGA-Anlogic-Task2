// Composition only. Detection is performed before OSD in the algorithm chain.
module hdmi_mixer_fast #(parameter H_OFFSET=0,V_OFFSET=0,IMG_WIDTH=1280,IMG_HEIGHT=720,DEBUG_MODE=0)(
 input wire[19:0] pan_hz_bcd,tilt_hz_bcd,pan_duty_bcd,tilt_duty_bcd,
 input wire gesture_valid,input wire [2:0] gesture_value,input wire [47:0] gesture_box,
 input wire remote_control,input wire[2:0] sort_phase,input wire[11:0] sort_digits,sort_classes,
 input wire [191:0] after_histogram,input wire [191:0] histogram,input wire [31:0] balance_gains,input wire [7:0] scene_mean,digit_threshold,input wire [14:0] digit_ink,input wire [3:0] digit_state,input wire motion_valid,input wire [47:0] motion_box,input wire [11:0] motion_count,
 input wire[7:0] target_valid,input wire[383:0] target_boxes,input wire[15:0] target_shapes,
 input wire digit_valid,input wire[2:0] digit_value,input wire[47:0] digit_box,
 input wire I_clk,I_rst_n,I_video_vsync,I_video_hsync,I_video_de,I_video_user,I_video_last,
 input wire [3:0] I_debug_status,input wire [1:0] I_quality,I_fps,
 input wire beauty,input wire [1:0] red_shape,green_shape,input wire[7:0] processing_us,
 input wire red_box_valid,green_box_valid,input wire [47:0] red_box,green_box,
 input wire [31:0] source_ms,source_seq,now_gray,input wire source_valid,
 output wire O_video_rd_en,input wire [23:0] I_video_rd_data,
 output wire O_hdmi_vsync,O_hdmi_hsync,O_hdmi_de,output wire [23:0] O_hdmi_data,
 output wire O_hdmi_user,O_hdmi_last,
 input wire freeze,face_track,calibration_busy,calibration_valid,
 input wire[1:0] correction_mode,center_seconds,photo_status,
 input wire[15:0] exposure_status,wb_status,
 input wire[7:0] gain_status,tone_status,photo_error,face_confidence,
 input wire face_valid,input wire[47:0] face_box
);

 // Frame-atomic metadata remains frozen with the DDR read bank during SD capture.
 reg [0:0] d_gesture_valid;
 reg [2:0] d_gesture_value;
 reg [47:0] d_gesture_box;
 reg d_remote_control;reg[2:0] d_sort_phase;reg[11:0] d_sort_digits,d_sort_classes;
 reg [191:0] d_after_histogram;
 reg [191:0] d_histogram;
 reg [31:0] d_balance_gains;
 reg [7:0] d_scene_mean;
 reg [7:0] d_digit_threshold;
 reg [14:0] d_digit_ink;
 reg [3:0] d_digit_state;
 reg [19:0] d_pan_hz_bcd,d_tilt_hz_bcd,d_pan_duty_bcd,d_tilt_duty_bcd;
 reg [0:0] d_motion_valid;
 reg [47:0] d_motion_box;
 reg [11:0] d_motion_count;
 reg [7:0] d_target_valid;
 reg [383:0] d_target_boxes;
 reg [15:0] d_target_shapes;
 reg [0:0] d_digit_valid;
 reg [2:0] d_digit_value;
 reg [47:0] d_digit_box;
 reg [3:0] d_I_debug_status;
 reg [1:0] d_I_quality;
 reg [1:0] d_I_fps;
 reg [0:0] d_beauty;
 reg [1:0] d_red_shape;
 reg [1:0] d_green_shape;
 reg [7:0] d_processing_us;
 reg [0:0] d_red_box_valid;
 reg [0:0] d_green_box_valid;
 reg [47:0] d_red_box;
 reg [47:0] d_green_box;
 reg [0:0] d_face_track;
 reg [0:0] d_calibration_busy;
 reg [0:0] d_calibration_valid;
 reg [1:0] d_correction_mode;
 reg [1:0] d_center_seconds;
 reg [15:0] d_exposure_status;
 reg [15:0] d_wb_status;
 reg [7:0] d_gain_status;
 reg [7:0] d_tone_status;
 reg [7:0] d_face_confidence;
 reg [0:0] d_face_valid;
 reg [47:0] d_face_box;
 always @(posedge I_clk or negedge I_rst_n)begin
 if(!I_rst_n)begin
 d_gesture_valid<=0;
 d_gesture_value<=0;
 d_gesture_box<=0;
 d_remote_control<=0;d_sort_phase<=0;d_sort_digits<=0;d_sort_classes<=0;
 d_after_histogram<=0;
 d_histogram<=0;
 d_balance_gains<=0;
 d_scene_mean<=0;
 d_digit_threshold<=0;
 d_digit_ink<=0;
 d_digit_state<=0;
 d_pan_hz_bcd<=0;d_tilt_hz_bcd<=0;d_pan_duty_bcd<=0;d_tilt_duty_bcd<=0;
 d_motion_valid<=0;
 d_motion_box<=0;
 d_motion_count<=0;
 d_target_valid<=0;
 d_target_boxes<=0;
 d_target_shapes<=0;
 d_digit_valid<=0;
 d_digit_value<=0;
 d_digit_box<=0;
 d_I_debug_status<=0;
 d_I_quality<=0;
 d_I_fps<=0;
 d_beauty<=0;
 d_red_shape<=0;
 d_green_shape<=0;
 d_processing_us<=0;
 d_red_box_valid<=0;
 d_green_box_valid<=0;
 d_red_box<=0;
 d_green_box<=0;
 d_face_track<=0;
 d_calibration_busy<=0;
 d_calibration_valid<=0;
 d_correction_mode<=0;
 d_center_seconds<=0;
 d_exposure_status<=0;
 d_wb_status<=0;
 d_gain_status<=0;
 d_tone_status<=0;
 d_face_confidence<=0;
 d_face_valid<=0;
 d_face_box<=0;
 end else if(I_video_user && !freeze)begin
 d_gesture_valid<=gesture_valid;
 d_gesture_value<=gesture_value;
 d_gesture_box<=gesture_box;
 d_remote_control<=remote_control;d_sort_phase<=sort_phase;d_sort_digits<=sort_digits;d_sort_classes<=sort_classes;
 d_after_histogram<=after_histogram;
 d_histogram<=histogram;
 d_balance_gains<=balance_gains;
 d_scene_mean<=scene_mean;
 d_digit_threshold<=digit_threshold;
 d_digit_ink<=digit_ink;
 d_digit_state<=digit_state;
 d_pan_hz_bcd<=pan_hz_bcd;d_tilt_hz_bcd<=tilt_hz_bcd;d_pan_duty_bcd<=pan_duty_bcd;d_tilt_duty_bcd<=tilt_duty_bcd;
 d_motion_valid<=motion_valid;
 d_motion_box<=motion_box;
 d_motion_count<=motion_count;
 d_target_valid<=target_valid;
 d_target_boxes<=target_boxes;
 d_target_shapes<=target_shapes;
 d_digit_valid<=digit_valid;
 d_digit_value<=digit_value;
 d_digit_box<=digit_box;
 d_I_debug_status<=I_debug_status;
 d_I_quality<=I_quality;
 d_I_fps<=I_fps;
 d_beauty<=beauty;
 d_red_shape<=red_shape;
 d_green_shape<=green_shape;
 d_processing_us<=processing_us;
 d_red_box_valid<=red_box_valid;
 d_green_box_valid<=green_box_valid;
 d_red_box<=red_box;
 d_green_box<=green_box;
 d_face_track<=face_track;
 d_calibration_busy<=calibration_busy;
 d_calibration_valid<=calibration_valid;
 d_correction_mode<=correction_mode;
 d_center_seconds<=center_seconds;
 d_exposure_status<=exposure_status;
 d_wb_status<=wb_status;
 d_gain_status<=gain_status;
 d_tone_status<=tone_status;
 d_face_confidence<=face_confidence;
 d_face_valid<=face_valid;
 d_face_box<=face_box;
 end end
 reg [11:0] x,y;
 wire [11:0] sx=I_video_user?12'd0:x,sy=I_video_user?12'd0:y;
 reg [31:0] ts0,ts1,seq0,seq1,gray0,gray1,last_seq;
 reg sv0,sv1;reg [31:0] now_binary;
 integer i;
 always @*begin now_binary[31]=gray1[31];for(i=30;i>=0;i=i-1)now_binary[i]=now_binary[i+1]^gray1[i];end
 wire update=I_video_user && sv1 && seq1!=last_seq;
 reg [31:0] seconds;
 reg [7:0] fps_count;
 reg [15:0] fps,latency;
 reg lat_valid;
 reg [11:0] count_bcd;
 always @(posedge I_clk or negedge I_rst_n)begin
  if(!I_rst_n)begin
   x<=0;y<=0;ts0<=0;ts1<=0;seq0<=0;seq1<=0;gray0<=0;gray1<=0;last_seq<=0;sv0<=0;sv1<=0;
   seconds<=0;fps_count<=0;fps<=0;latency<=0;lat_valid<=0;count_bcd<=0;
  end else begin
   ts0<=source_ms;ts1<=ts0;seq0<=source_seq;seq1<=seq0;gray0<=now_gray;gray1<=gray0;sv0<=source_valid;sv1<=sv0;
   if(I_video_de)begin
    if(I_video_last)begin x<=0;y<=sy+1'b1;end else begin x<=sx+1'b1;y<=sy;end
   end else if(I_video_user)begin x<=0;y<=0;end
   if(freeze)begin seconds<=seconds;fps_count<=fps_count;end
   else if(seconds==74999999)begin seconds<=0;fps<=fps_count+update;fps_count<=0;end
   else begin seconds<=seconds+1'b1;if(update)fps_count<=fps_count+1'b1;end
   if(I_video_user && !freeze)begin
    last_seq<=seq1;latency<=now_binary-ts1;lat_valid<=sv1;
    if(count_bcd[3:0]==9)begin count_bcd[3:0]<=0;
     if(count_bcd[7:4]==9)begin count_bcd[7:4]<=0;count_bcd[11:8]<=(count_bcd[11:8]==9)?0:count_bcd[11:8]+1'b1;end
     else count_bcd[7:4]<=count_bcd[7:4]+1'b1;
    end else count_bcd[3:0]<=count_bcd[3:0]+1'b1;
   end
  end
 end
 wire [7:0] fb;wire [11:0] lb;wire lv;
 // Convert after VS (blanking), before active picture. The sampled latency
 // includes capture-frame buffering up to the previous active frame start.
 reg vs_d;always @(posedge I_clk)vs_d<=I_video_vsync;
 metric_display_format_v4 fmt(I_clk,I_rst_n,I_video_vsync&&!vs_d && !freeze,fps,latency,lat_valid,fb,lb,lv);
 wire [7:0] display_valid=(|d_target_valid)?d_target_valid:(d_red_box_valid?8'd1:8'd0);
 wire [383:0] display_boxes=(|d_target_valid)?d_target_boxes:{336'd0,d_red_box};
 wire [15:0] display_shapes=(|d_target_valid)?d_target_shapes:{14'd0,d_red_shape};
 wire [23:0] diagnostic_rgb;
 diagnostic_overlay_v11 diagnostic(I_clk,I_rst_n,I_video_user,I_video_de,sx,sy,I_video_rd_data,d_I_debug_status,d_histogram,d_scene_mean,d_digit_threshold,d_digit_ink,d_digit_state,d_balance_gains,d_motion_valid,d_motion_box,d_motion_count,d_gesture_valid,d_gesture_value,d_gesture_box,d_beauty,d_after_histogram,diagnostic_rgb);
 osd_overlay_v4 osd(.clk(I_clk),.rst_n(I_rst_n),.remote_control(d_remote_control),.sort_phase(d_sort_phase),.sort_digits(d_sort_digits),.sort_classes(d_sort_classes),
 .pan_hz_bcd(d_pan_hz_bcd),.tilt_hz_bcd(d_tilt_hz_bcd),.pan_duty_bcd(d_pan_duty_bcd),.tilt_duty_bcd(d_tilt_duty_bcd),
 .in_vs(I_video_vsync),.in_hs(I_video_hsync),.in_de(I_video_de),.in_user(I_video_user),.in_last(I_video_last),
 .target_valid(display_valid),.target_boxes(display_boxes),.target_shapes(display_shapes),.digit_valid(d_digit_valid),.digit_value(d_digit_value),.digit_box(d_digit_box),
 .in_x(sx),.in_y(sy),.in_rgb(diagnostic_rgb),.mode(d_I_debug_status),
 .beauty(d_beauty),.red_shape(d_red_shape),.green_shape(d_green_shape),.processing_us(d_processing_us),.quality_preset(d_I_quality),.fps_preset(d_I_fps),.content_fps_bcd(fb),.latency_ms_bcd(lb),.latency_valid(lv),.cnt_bcd(count_bcd),
 .red_box_valid(d_red_box_valid),.red_box(d_red_box),.green_box_valid(d_green_box_valid),.green_box(d_green_box),
 .face_track(d_face_track),.gesture_valid(d_gesture_valid),.gesture_value(d_gesture_value),.face_valid(d_face_valid),.face_confidence(d_face_confidence),.face_box(d_face_box),
 .motion_count(d_motion_count),.correction_mode(d_correction_mode),.center_seconds(d_center_seconds),.photo_status(photo_status),.calibration_busy(d_calibration_busy),.calibration_valid(d_calibration_valid),.exposure_status(d_exposure_status),.wb_status(d_wb_status),.gain_status(d_gain_status),.tone_status(d_tone_status),.scene_mean(d_scene_mean),.photo_error(photo_error),
 .out_vs(O_hdmi_vsync),.out_hs(O_hdmi_hsync),.out_de(O_hdmi_de),.out_user(O_hdmi_user),.out_last(O_hdmi_last),.out_rgb(O_hdmi_data));
 assign O_video_rd_en=I_video_de;
endmodule

