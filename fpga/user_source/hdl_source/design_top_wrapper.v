

module design_top_wrapper #(parameter ENABLE_FACE=1) (
    input wire        I_sys_clk,
    input wire        I_rst_n,
    input wire I_uart_rx,output wire O_uart_tx,output wire O_sort_uart_tx,
      
    output wire       O_cam_scl,
    inout  wire       IO_cam_sda,
    output wire       O_cam_24m,
    output wire       O_cam_rst,
      
    input wire [2:0]  I_button,
    input wire [3:0]  I_switch,

    output wire O_servo_pan,O_servo_tilt,
    output wire O_photo_led,O_photo_buzz,
    output wire       O_screen_pwm,
    output wire       O_tmds_ch0_p,
    output wire       O_tmds_ch1_p,
    output wire       O_tmds_ch2_p,
    output wire       O_tmds_clk_p,

    inout wire        IO_rx_clk_pad_n, 
    inout wire        IO_rx_clk_pad_p, 
    inout wire[3:0]   IO_rx_data_pad_n,
    inout wire[3:0]   IO_rx_data_pad_p,

    output wire[12:0] ddr_addr,
    output wire[ 1:0] ddr_ba,
    output wire[ 0:0] ddr_cke,
    output wire[ 0:0] ddr_odt,
    output wire[ 0:0] ddr_cs_n,
    output wire       ddr_ras_n,
    output wire       ddr_cas_n,
    output wire       ddr_we_n,
    output wire[ 0:0] ddr_ck_p,
    output wire[ 0:0] ddr_ck_n,
    inout wire[1:0]   ddr_dm,
    inout wire[15:0]  ddr_dq,
    inout wire[1:0]   ddr_dqs_p,
    inout wire[1:0]   ddr_dqs_n   
);


    wire        	S_100m_clk;
    wire        	S_24m_clk;
    wire        	S_aux_50m_clk;
	wire        	S_10m_clk;
		
	wire        	S_pll_lock;
    wire        	S_rst_n;
	reg  [17:0] 	S_cam_power_cnt;
	reg         	S_cam_pwdnb;
	reg         	S_cam_i2c_ready;
	(* keep = "true" *) wire [15:0] S_cam_sensor_id;
	(* keep = "true" *) wire        S_cam_sensor_id_ok;
	(* keep = "true" *) wire        S_cam_i2c_error;
	localparam integer CAM_PWDNB_LOW_CYCLES = 23810;  // >= 1 ms at 23.809524 MHz
	localparam integer CAM_I2C_START_CYCLES = 142857; // release + >= 5 ms
	
	wire [15:0] 	S_ae;
    wire [15:0] 	S_ag;
    wire 			S_cam_cfg_done;
    wire 			S_ae_cfg_done;
    wire 			S_ae_req; 
	
	wire        	S_csi_rx_clk;  
    wire        	S_hs_rx_valid;  
    wire[15:0]  	S_hs_rx_data;   
	wire[1:0]   	S_lane_error;
	
	wire        	S_csi_frame_start;       
	wire        	S_csi_frame_end;         
	wire        	S_csi_valid;             
	wire[31:0]  	S_csi_data;  
	(* keep = "true" *) wire [15:0] S_csi_data_length;
		
	wire        	S_raw10_frame_start; 
	wire        	S_raw10_frame_end;   
	wire        	S_raw10_valid;       
	wire [39:0] 	S_raw10_data;

	wire 			S_axis_tlast;  
	wire 			S_axis_tuser;  
	wire [39:0]		S_axis_tdata;  
	wire 			S_axis_tvalid; 
	
	wire [39:0]		S_raw_tdata ;
	wire			S_raw_tlast ;
	wire 			S_raw_tvalid;
	wire 			S_raw_tuser ;
	
	wire			S_ISP_O_tready;
	wire [127:0]	S_ISP_O_tdata ;
	wire 			S_ISP_O_tlast ;
	wire 			S_ISP_O_tuser ;
	wire 			S_ISP_O_tvalid; 

    // Capture the switch value at camera frame boundaries for the HDMI mode.
    wire [3:0]   S_mode_requested;
    wire [3:0]   S_mode_decoded;
    local_mode_decode compact_switches(.code(S_mode_requested),.mode(S_mode_decoded));
    wire [3:0]   S_mode_active;
    reg  [3:0]   S_mode_video;
    reg  [3:0]   S_mode_hdmi_sync1;
    reg  [3:0]   S_mode_hdmi_sync2;
    reg  [3:0]   S_mode_display;
	

    wire        S_ddr_clk;
    wire        S_hdmi_pixel_clk;
    wire        S_hdmi_serial_clk;
    wire        S_hdmi_rst_n;
    wire        S_video_out_rst_n;


    wire        S_vi_128b_frame_start;
    wire        S_vi_128b_valid;      
    wire[127:0] S_vi_128b_data;    
    
    wire        S_video_out_rd_busy;
    wire        S_video_in_wr_busy; 
    wire[1:0]   S_video_out_rp;     

    wire        S_ddr_user_wr_en;       
    wire        S_ddr_user_rd_en;       
    wire[24:0]  S_ddr_user_addr;        
    wire[127:0] S_ddr_user_wr_data;     
    wire        S_ddr_user_ready;       
    wire        S_ddr_user_rd_valid;    
    wire[127:0] S_ddr_user_rd_data;     

    wire        S_vi_ddr_wr_en;   
    wire[24:0]  S_vi_ddr_wr_addr; 
    wire[127:0] S_vi_ddr_wr_data;
    wire        S_vi_ddr_wr_ready;

    wire        S_vo_ddr_rd_en;   
    wire[24:0]  S_vo_ddr_rd_addr; 
    wire        S_vo_ddr_rd_ready;
    wire        S_vo_dbg_fifo_rst;
    wire        S_vo_dbg_ddr_rd_valid;
    wire        S_vo_dbg_fifo_rd_en;
    wire        S_vo_dbg_fifo_empty;

    wire        S_init_calib_complete; 
    wire[24:0]  S_mc_app_addr;          
    wire[2:0]   S_mc_app_cmd;           
    wire        S_mc_app_en;            
    wire[127:0] S_mc_app_wdf_data;      
    wire        S_mc_app_wdf_end;       
    wire[15:0]  S_mc_app_wdf_mask;      
    wire        S_mc_app_wdf_wren;      
    wire[127:0] S_mc_app_rd_data;       
    wire        S_mc_app_rd_data_end;   
    wire        S_mc_app_rd_data_valid; 
    wire        S_mc_app_rdy;           
    wire        S_mc_app_wdf_rdy;       
    wire        S_mc_dbg_fifo_afull;
    wire        S_mc_dbg_app_rdy;
    wire        S_mc_dbg_wdf_rdy;
    wire        S_mc_dbg_cmd_pop;

    wire        S_hdmi_vsync;
    wire        S_hdmi_hsync;
    wire        S_hdmi_de;
    wire        S_hdmi_user;
    wire        S_hdmi_last;
    wire        S_video_out_vsync;
    wire        S_hdmi_window_rd_en;
    wire        S_hdmi_out_vsync;
    wire        S_hdmi_out_hsync;
    wire        S_hdmi_out_de;
    wire[23:0]  S_hdmi_out_data;

    wire[23:0]  S_video_rd_data;
    wire[23:0]  S_effect_video_data;
    wire        S_effect_vsync, S_effect_hsync, S_effect_de;
    wire        S_effect_user, S_effect_last;
    reg         S_dbg_raw_seen;
    reg         S_dbg_isp_seen;
    reg         S_dbg_ddr_wr_seen;
    reg         S_dbg_ddr_rd_seen;
    reg         S_dbg_cam_cfg_seen;
    reg         S_dbg_hs_seen;
    reg         S_dbg_csi_seen;
    reg         S_dbg_raw10_seen;
    reg         S_dbg_isp_fs_seen;
    reg         S_dbg_isp_valid_seen;
    reg         S_dbg_ddr_req_seen;
    reg         S_dbg_ddr_ready_seen;
    reg [1:0]   S_dbg_raw_seen_sync;
    reg [1:0]   S_dbg_isp_seen_sync;
    reg [1:0]   S_dbg_ddr_wr_seen_sync;
    reg [1:0]   S_dbg_ddr_rd_seen_sync;
    reg [1:0]   S_dbg_cam_cfg_seen_sync;
    reg [1:0]   S_dbg_hs_seen_sync;
    reg [1:0]   S_dbg_csi_seen_sync;
    reg [1:0]   S_dbg_raw10_seen_sync;
    reg [1:0]   S_dbg_isp_fs_seen_sync;
    reg [1:0]   S_dbg_isp_valid_seen_sync;
    reg [1:0]   S_dbg_ddr_req_seen_sync;
    reg [1:0]   S_dbg_ddr_ready_seen_sync;
    reg         S_dbg_video_nonzero_seen;
    reg         S_dbg_rd_req_seen;
    reg         S_dbg_rd_valid_seen;
    reg         S_dbg_rd_nonzero_seen;
    reg [1:0]   S_dbg_rd_req_seen_sync;
    reg [1:0]   S_dbg_rd_valid_seen_sync;
    reg [1:0]   S_dbg_rd_nonzero_seen_sync;
    reg         S_dbg_mc_init_seen;
    reg         S_dbg_mc_app_rdy_seen;
    reg         S_dbg_mc_wdf_rdy_seen;
    reg         S_dbg_mc_cmd_pop_seen;
    reg [1:0]   S_dbg_mc_init_seen_sync;
    reg [1:0]   S_dbg_mc_app_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_wdf_rdy_seen_sync;
    reg [1:0]   S_dbg_mc_cmd_pop_seen_sync;
    wire[3:0]   S_hdmi_debug_status;
    wire[7:0] V8_target_valid;wire[383:0] V8_target_boxes;wire[15:0] V8_target_shapes;wire V8_digit_valid;wire[2:0] V8_digit_value;wire[47:0] V8_digit_box;
    wire [1:0] PRO_correction_mode;
    wire[3:0] USB_remote_mode;
    wire USB_lease_alive;reg USB_control_active;
    wire PRO_calibrate,PRO_photo_request,PRO_face_request,PRO_track_ready;
    // Shared FACE detector, red tracker and camera PWM remain available.
    wire PRO_face_track;
    wire [1:0] PRO_center_seconds;
    wire PRO_cal_busy,PRO_cal_valid,PRO_face_valid;
    wire PRO_face_update;wire[47:0] PRO_face_measurement_box;wire[7:0] PRO_face_measurement_age;
    wire [47:0] PRO_face_box;wire [7:0] PRO_face_confidence,PRO_tone;
    wire [15:0] PRO_wb;
    wire PRO_freeze=1'b0;wire PRO_freeze_ack_ddr;reg PRO_ack_meta,PRO_ack_sync;
    wire PRO_sd_busy=1'b0;reg [7:0] PRO_sd_error_code;
    wire [9:0] PRO_sd_progress;wire PRO_hdmi_user,PRO_hdmi_last;
    wire [3:0] PRO_effective_mode=USB_control_active?(USB_lease_alive?USB_remote_mode:4'd0):(S_mode_hdmi_sync2==13?4'd13:(PRO_face_request?4'd12:S_mode_hdmi_sync2));
    wire SORT_enable=PRO_effective_mode==13;
    wire[31:0] V4_source_seq;wire V4_source_valid;wire USB_commit;
    wire[2:0] SORT_phase;wire SORT_face,SORT_active;wire[10:0] SORT_pan,SORT_tilt;
    wire[287:0] SORT_records;wire[3:0] SORT_valid;wire[15:0] SORT_frame,SORT_sequence;
    wire[11:0] SORT_digits,SORT_classes;wire[7:0] SORT_shapes;wire SORT_uart_busy,SORT_ms_tick;
    // A stopped source cannot remain valid merely because HDMI is refreshing.
    reg[15:0] SORT_seen_frame;reg[3:0] SORT_stale_frames;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)begin
      if(!S_hdmi_rst_n)begin SORT_seen_frame<=0;SORT_stale_frames<=15;end
      else if(S_hdmi_user)begin
        SORT_seen_frame<=V4_source_seq[15:0];
        if(V4_source_valid && SORT_seen_frame!=V4_source_seq[15:0])SORT_stale_frames<=0;
        else if(SORT_stale_frames!=15)SORT_stale_frames<=SORT_stale_frames+1'b1;
      end
    end
    wire SORT_source_ok=V4_source_valid && SORT_stale_frames<15;
    sort_mode_ctrl sort_scene(.clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.enable(SORT_enable),
      .frame_start(S_hdmi_user),.face_valid(PRO_face_valid),.source_valid(SORT_source_ok),
      .phase(SORT_phase),.face_enable(SORT_face),.vision_enable(SORT_active),.pan_us(SORT_pan),.tilt_us(SORT_tilt));
    sort_uart_tx sort_uart(.clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.enable(SORT_active),
      .valid_slots(SORT_valid),.records(SORT_records),.frame_id(SORT_frame),.tx(O_sort_uart_tx),.busy(SORT_uart_busy),.packet_seq(SORT_sequence),.ms_tick(SORT_ms_tick));
    assign PRO_face_track=ENABLE_FACE && (PRO_effective_mode==12 || SORT_face);
    wire PRO_show_red=(PRO_effective_mode==10 && PRO_track_ready) || SORT_active;
    wire [15:0] PRO_exposure_i2c;wire [7:0] PRO_gain_i2c;
    reg [15:0] PRO_exp_meta,PRO_exposure;reg [7:0] PRO_gain_meta,PRO_gain;
    reg [1:0] PRO_mode_meta,PRO_mode_i2c;
    reg PRO_cal_toggle,PRO_cal_meta,PRO_cal_sync,PRO_cal_last;
    reg PRO_freeze_meta_i2c,PRO_freeze_i2c;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)begin
      if(!S_hdmi_rst_n)begin PRO_cal_toggle<=0;PRO_ack_meta<=0;PRO_ack_sync<=0;PRO_exp_meta<=0;PRO_exposure<=0;PRO_gain_meta<=0;PRO_gain<=0;end
      else begin
        if(PRO_calibrate)PRO_cal_toggle<=~PRO_cal_toggle;
        PRO_ack_meta<=PRO_freeze_ack_ddr;PRO_ack_sync<=PRO_ack_meta;
        PRO_exp_meta<=PRO_exposure_i2c;PRO_exposure<=PRO_exp_meta;PRO_gain_meta<=PRO_gain_i2c;PRO_gain<=PRO_gain_meta;
      end
    end
    always @(posedge S_24m_clk or negedge S_rst_n)begin
      if(!S_rst_n)begin PRO_mode_meta<=0;PRO_mode_i2c<=0;PRO_cal_meta<=0;PRO_cal_sync<=0;PRO_cal_last<=0;PRO_freeze_meta_i2c<=0;PRO_freeze_i2c<=0;end
      else begin PRO_mode_meta<=PRO_correction_mode;PRO_mode_i2c<=PRO_mode_meta;PRO_cal_meta<=PRO_cal_toggle;PRO_cal_sync<=PRO_cal_meta;PRO_cal_last<=PRO_cal_sync;PRO_freeze_meta_i2c<=PRO_freeze;PRO_freeze_i2c<=PRO_freeze_meta_i2c;end
    end
    wire V5_beauty;wire [1:0] V5_red_shape,V5_green_shape;wire [7:0] V5_processing_us;
    wire[1:0]   S_quality_preset;
    wire[1:0]   S_fps_preset;
    wire[1:0] USB_remote_beauty,USB_remote_quality,USB_remote_fps;
    wire USB_calibrate,USB_photo_request,USB_recenter,USB_video_busy;
    wire USB_manual,USB_show,USB_led,USB_alarm,USB_wb_override,USB_ae_override;
    wire[3:0] USB_saturation;
    wire[10:0] USB_pan,USB_tilt;wire[7:0] USB_wb_r,USB_wb_b,USB_gain;
    wire[15:0] USB_exp;wire USB_photo_ack,USB_photo_ok;wire[7:0] USB_photo_token;
    reg[7:0] PRO_photo_token;
    function[3:0] legacy_mode;input[3:0] m;begin
    case(m)0,1:legacy_mode=m;2:legacy_mode=3;3:legacy_mode=0;4:legacy_mode=6;5:legacy_mode=7;
    6:legacy_mode=8;7:legacy_mode=10;8:legacy_mode=12;9:legacy_mode=13;
    10:legacy_mode=14;13:legacy_mode=0;default:legacy_mode=0;endcase end endfunction
    // Data held for a video frame; toggle crosses three flops before atomic capture.
    reg[24:0] USB_ae_bundle;reg USB_ae_toggle;
    (* async_reg="true" *) reg[2:0] USB_ae_sync;
    reg[24:0] USB_ae_meta,USB_ae_sync_data,USB_ae_i2c;reg USB_ae_seen;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)
    if(!S_hdmi_rst_n)begin USB_ae_bundle<=0;USB_ae_toggle<=0;end
    else if(USB_commit && USB_ae_bundle!={USB_ae_override,USB_exp,USB_gain})begin USB_ae_bundle<={USB_ae_override,USB_exp,USB_gain};USB_ae_toggle<=~USB_ae_toggle;end
    always @(posedge S_24m_clk or negedge S_rst_n)
    if(!S_rst_n)begin USB_ae_sync<=0;USB_ae_meta<=0;USB_ae_sync_data<=0;USB_ae_i2c<=0;USB_ae_seen<=0;end
    else begin USB_ae_sync<={USB_ae_sync[1:0],USB_ae_toggle};USB_ae_meta<=USB_ae_bundle;USB_ae_sync_data<=USB_ae_meta;
    if(USB_ae_seen!=USB_ae_sync[2])begin USB_ae_seen<=USB_ae_sync[2];USB_ae_i2c<=USB_ae_sync_data;end end

    reg USB_vs_d;
    assign USB_commit=S_hdmi_vsync && !USB_vs_d;
    wire[1:0] LOCAL_quality,LOCAL_fps,LOCAL_beauty_mode;
    wire LOCAL_beauty,LOCAL_calibrate,LOCAL_photo_request,LOCAL_face_request;
    reg [1:0] PRO_photo_status;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)begin
     if(!S_hdmi_rst_n)begin USB_control_active<=0;USB_vs_d<=0;end
     else begin
      USB_vs_d<=S_hdmi_vsync;
      if(USB_commit&&!PRO_sd_busy&&!PRO_freeze)USB_control_active<=S_mode_hdmi_sync2==15;
     end
    end
    assign PRO_correction_mode=USB_control_active?(USB_lease_alive?USB_remote_beauty:2'd0):LOCAL_beauty_mode;
    assign S_quality_preset=USB_control_active?(USB_lease_alive?USB_remote_quality:2'd0):LOCAL_quality;
    assign S_fps_preset=USB_control_active?(USB_lease_alive?USB_remote_fps:2'd0):LOCAL_fps;
    assign V5_beauty=PRO_correction_mode!=0;
    assign PRO_calibrate=USB_control_active?USB_calibrate:LOCAL_calibrate;
    assign PRO_photo_request=USB_control_active?USB_photo_request:LOCAL_photo_request;
    assign PRO_face_request=USB_control_active?1'b0:LOCAL_face_request;

    wire        S_lane_error_any;
    wire        S_csi_packet_start;
    reg         S_csi_length_active_d;
    reg [10:0]  S_mipi_line_count;
    reg         S_mipi_length_error;
    reg         S_mipi_lane_error;
    reg         S_mipi_frame_seen;
    reg         S_mipi_frame_done;
    reg         S_mipi_last_length_error;
    reg         S_mipi_last_line_error;
    reg         S_mipi_last_lane_error;
    wire[3:0]   S_mipi_diag_status_async;
    reg [3:0]   S_mipi_diag_status_sync1;
    reg [3:0]   S_mipi_diag_status_sync2;


    assign O_screen_pwm = 1'b1;
    assign S_video_out_vsync = ~S_hdmi_vsync;
	
	
    assign S_rst_n 		= S_pll_lock;
    wire S_hdmi_pll_lock;
    wire S_hdmi_clocks_ready = I_rst_n && S_pll_lock && S_hdmi_pll_lock;
    wire S_hdmi_serial_rst_n;
    hdmi_reset_domains u_hdmi_resets(
        .pixel_clk(S_hdmi_pixel_clk), .serial_clk(S_hdmi_serial_clk),
        .clocks_ready(S_hdmi_clocks_ready),
        .pixel_rst_n(S_hdmi_rst_n), .serial_rst_n(S_hdmi_serial_rst_n)
    );

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw_seen <= 1'b0;
        else if(S_raw10_frame_start | S_axis_tvalid)
            S_dbg_raw_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_seen <= 1'b0;
        else if(S_ISP_O_tuser | S_ISP_O_tvalid)
            S_dbg_isp_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_wr_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_wr_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_rd_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_ddr_rd_seen <= 1'b1;
    end

    always @(posedge S_24m_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_cam_cfg_seen <= 1'b0;
        else if(S_cam_cfg_done)
            S_dbg_cam_cfg_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_hs_seen <= 1'b0;
        else if(S_hs_rx_valid)
            S_dbg_hs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_csi_seen <= 1'b0;
        else if(S_csi_frame_start | S_csi_valid)
            S_dbg_csi_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_raw10_seen <= 1'b0;
        else if(S_raw10_frame_start | S_raw10_valid)
            S_dbg_raw10_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_fs_seen <= 1'b0;
        else if(S_ISP_O_tuser)
            S_dbg_isp_fs_seen <= 1'b1;
    end

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_isp_valid_seen <= 1'b0;
        else if(S_ISP_O_tvalid)
            S_dbg_isp_valid_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_req_seen <= 1'b0;
        else if(S_vi_ddr_wr_en)
            S_dbg_ddr_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_ddr_ready_seen <= 1'b0;
        else if(S_ddr_user_ready)
            S_dbg_ddr_ready_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_req_seen <= 1'b0;
        else if(S_vo_ddr_rd_en)
            S_dbg_rd_req_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_valid_seen <= 1'b0;
        else if(S_ddr_user_rd_valid)
            S_dbg_rd_valid_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_video_out_rst_n) begin
        if(!S_video_out_rst_n)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_video_out_vsync)
            S_dbg_rd_nonzero_seen <= 1'b0;
        else if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
            S_dbg_rd_nonzero_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_init_seen <= 1'b0;
        else if(S_init_calib_complete)
            S_dbg_mc_init_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_app_rdy_seen <= 1'b0;
        else if(S_mc_dbg_app_rdy)
            S_dbg_mc_app_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_wdf_rdy_seen <= 1'b0;
        else if(S_mc_dbg_wdf_rdy)
            S_dbg_mc_wdf_rdy_seen <= 1'b1;
    end

    always @(posedge S_ddr_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_dbg_mc_cmd_pop_seen <= 1'b0;
        else if(S_mc_dbg_cmd_pop)
            S_dbg_mc_cmd_pop_seen <= 1'b1;
    end

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_dbg_cam_cfg_seen_sync <= 2'b00;
            S_dbg_hs_seen_sync      <= 2'b00;
            S_dbg_csi_seen_sync     <= 2'b00;
            S_dbg_raw10_seen_sync   <= 2'b00;
            S_dbg_raw_seen_sync    <= 2'b00;
            S_dbg_isp_seen_sync    <= 2'b00;
            S_dbg_ddr_wr_seen_sync <= 2'b00;
            S_dbg_ddr_rd_seen_sync <= 2'b00;
            S_dbg_isp_fs_seen_sync  <= 2'b00;
            S_dbg_isp_valid_seen_sync <= 2'b00;
            S_dbg_ddr_req_seen_sync <= 2'b00;
            S_dbg_ddr_ready_seen_sync <= 2'b00;
            S_dbg_video_nonzero_seen <= 1'b0;
            S_dbg_rd_req_seen_sync <= 2'b00;
            S_dbg_rd_valid_seen_sync <= 2'b00;
            S_dbg_rd_nonzero_seen_sync <= 2'b00;
            S_dbg_mc_init_seen_sync <= 2'b00;
            S_dbg_mc_app_rdy_seen_sync <= 2'b00;
            S_dbg_mc_wdf_rdy_seen_sync <= 2'b00;
            S_dbg_mc_cmd_pop_seen_sync <= 2'b00;
        end
        else begin
            S_dbg_cam_cfg_seen_sync <= {S_dbg_cam_cfg_seen_sync[0], S_dbg_cam_cfg_seen};
            S_dbg_hs_seen_sync      <= {S_dbg_hs_seen_sync[0],      S_dbg_hs_seen};
            S_dbg_csi_seen_sync     <= {S_dbg_csi_seen_sync[0],     S_dbg_csi_seen};
            S_dbg_raw10_seen_sync   <= {S_dbg_raw10_seen_sync[0],   S_dbg_raw10_seen};
            S_dbg_raw_seen_sync    <= {S_dbg_raw_seen_sync[0],    S_dbg_raw_seen};
            S_dbg_isp_seen_sync    <= {S_dbg_isp_seen_sync[0],    S_dbg_isp_seen};
            S_dbg_ddr_wr_seen_sync <= {S_dbg_ddr_wr_seen_sync[0], S_dbg_ddr_wr_seen};
            S_dbg_ddr_rd_seen_sync <= {S_dbg_ddr_rd_seen_sync[0], S_dbg_ddr_rd_seen};
            S_dbg_isp_fs_seen_sync  <= {S_dbg_isp_fs_seen_sync[0],  S_dbg_isp_fs_seen};
            S_dbg_isp_valid_seen_sync <= {S_dbg_isp_valid_seen_sync[0], S_dbg_isp_valid_seen};
            S_dbg_ddr_req_seen_sync <= {S_dbg_ddr_req_seen_sync[0], S_dbg_ddr_req_seen};
            S_dbg_ddr_ready_seen_sync <= {S_dbg_ddr_ready_seen_sync[0], S_dbg_ddr_ready_seen};
            S_dbg_rd_req_seen_sync <= {S_dbg_rd_req_seen_sync[0], S_dbg_rd_req_seen};
            S_dbg_rd_valid_seen_sync <= {S_dbg_rd_valid_seen_sync[0], S_dbg_rd_valid_seen};
            S_dbg_rd_nonzero_seen_sync <= {S_dbg_rd_nonzero_seen_sync[0], S_dbg_rd_nonzero_seen};
            S_dbg_mc_init_seen_sync <= {S_dbg_mc_init_seen_sync[0], S_dbg_mc_init_seen};
            S_dbg_mc_app_rdy_seen_sync <= {S_dbg_mc_app_rdy_seen_sync[0], S_dbg_mc_app_rdy_seen};
            S_dbg_mc_wdf_rdy_seen_sync <= {S_dbg_mc_wdf_rdy_seen_sync[0], S_dbg_mc_wdf_rdy_seen};
            S_dbg_mc_cmd_pop_seen_sync <= {S_dbg_mc_cmd_pop_seen_sync[0], S_dbg_mc_cmd_pop_seen};
            if(S_hdmi_window_rd_en && (S_video_rd_data != 24'd0))
                S_dbg_video_nonzero_seen <= 1'b1;
        end
    end

    assign S_lane_error_any = |S_lane_error;

    // A RAW10 line contains 1280 * 10 / 8 = 1600 bytes.  The CSI parser
    // reports the number of 16-bit lane words, therefore the expected value
    // is 1600 / 2 = 800 = 16'h0320.  Count one long packet whenever that
    // decoded length changes from zero to non-zero.
    assign S_csi_packet_start = (S_csi_data_length != 16'd0) &&
                                !S_csi_length_active_d;

    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n) begin
            S_csi_length_active_d      <= 1'b0;
            S_mipi_line_count          <= 11'd0;
            S_mipi_length_error        <= 1'b0;
            S_mipi_lane_error          <= 1'b0;
            S_mipi_frame_seen          <= 1'b0;
            S_mipi_frame_done          <= 1'b0;
            S_mipi_last_length_error   <= 1'b0;
            S_mipi_last_line_error     <= 1'b0;
            S_mipi_last_lane_error     <= 1'b0;
        end
        else begin
            S_csi_length_active_d <= (S_csi_data_length != 16'd0);

            if(S_csi_frame_start) begin
                S_mipi_line_count   <= 11'd0;
                S_mipi_length_error <= 1'b0;
                S_mipi_lane_error   <= 1'b0;
                S_mipi_frame_seen   <= 1'b1;
            end
            else begin
                if(S_csi_packet_start) begin
                    S_mipi_line_count <= S_mipi_line_count + 11'd1;
                    if(S_csi_data_length != 16'h0320)
                        S_mipi_length_error <= 1'b1;
                end

                if(S_lane_error_any)
                    S_mipi_lane_error <= 1'b1;
            end

            // Publish only a completed frame, so the HDMI-domain diagnostic
            // sees a stable result rather than counters changing every line.
            if(S_csi_frame_end) begin
                S_mipi_frame_done        <= 1'b1;
                S_mipi_last_length_error <= S_mipi_length_error;
                S_mipi_last_line_error   <= (S_mipi_line_count != 11'd720);
                S_mipi_last_lane_error   <= S_mipi_lane_error |
                                            S_lane_error_any;
            end
        end
    end

    // Diagnostic result codes consumed by hdmi_mixer DEBUG_MODE=4:
    // 0=config incomplete, 1=no HS traffic, 2=no completed CSI frame,
    // 3=lane error, 4=wrong RAW10 line length, 5=wrong lines/frame,
    // 6=the observed MIPI frame structure is correct, 7=I2C error.
    // I2C error has the highest priority because O_cfg_done only indicates
    // that the write sequencer reached its end; it does not prove that every
    // sensor register write was acknowledged successfully.
    assign S_mipi_diag_status_async =
        S_cam_i2c_error              ? 4'd7 :
        !S_cam_cfg_done              ? 4'd0 :
        !S_dbg_hs_seen               ? 4'd1 :
        !(S_mipi_frame_seen &&
          S_mipi_frame_done)         ? 4'd2 :
        S_mipi_last_lane_error       ? 4'd3 :
        S_mipi_last_length_error     ? 4'd4 :
        S_mipi_last_line_error       ? 4'd5 : 4'd6;

    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_mipi_diag_status_sync1 <= 4'd0;
            S_mipi_diag_status_sync2 <= 4'd0;
        end
        else begin
            S_mipi_diag_status_sync1 <= S_mipi_diag_status_async;
            S_mipi_diag_status_sync2 <= S_mipi_diag_status_sync1;
        end
    end

    assign S_vo_dbg_fifo_rst = 1'b0;
    assign S_vo_dbg_ddr_rd_valid = 1'b0;
    assign S_vo_dbg_fifo_rd_en = 1'b0;
    assign S_vo_dbg_fifo_empty = 1'b0;
    assign S_mc_dbg_fifo_afull = 1'b0;
    assign S_mc_dbg_app_rdy = 1'b0;
    assign S_mc_dbg_wdf_rdy = 1'b0;
    assign S_mc_dbg_cmd_pop = 1'b0;

    // The active mode changes only at camera frame boundaries and remains
    // stable for a complete frame.  Synchronize its display copy into the
    // HDMI pixel domain for the OSD badge.
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n) begin
        if(!S_hdmi_rst_n) begin
            S_mode_hdmi_sync1 <= 4'd0;
            S_mode_hdmi_sync2 <= 4'd0;
            S_mode_display <= 4'd0;
        end else begin
            S_mode_hdmi_sync1 <= S_mode_active;
            S_mode_hdmi_sync2 <= S_mode_hdmi_sync1;
            if (S_hdmi_user)
                S_mode_display <= S_mode_hdmi_sync2;
        end
    end

    assign S_hdmi_debug_status = S_mode_display;
	
	// J9 pin 37 is connected to the module's PWDNB/XSHUTDN input.
	// Hold the sensor in power-down after PLL lock, then allow its internal
	// power-up sequence to finish before the first I2C transaction.
	always @(posedge S_24m_clk or negedge S_pll_lock) begin
		if (!S_pll_lock) begin
			S_cam_power_cnt <= 18'd0;
			S_cam_pwdnb <= 1'b0;
			S_cam_i2c_ready <= 1'b0;
		end else begin
			if (S_cam_power_cnt < CAM_I2C_START_CYCLES)
				S_cam_power_cnt <= S_cam_power_cnt + 1'b1;
			if (S_cam_power_cnt >= CAM_PWDNB_LOW_CYCLES)
				S_cam_pwdnb <= 1'b1;
			if (S_cam_power_cnt >= CAM_I2C_START_CYCLES - 1)
				S_cam_i2c_ready <= 1'b1;
		end
	end

	assign O_cam_rst 	= S_cam_pwdnb;
    assign O_cam_24m 	= S_24m_clk;
	
	
	
	
    hdmi_capture_pll u_hdmi_pll(
        .refclk(I_sys_clk), .reset(~I_rst_n),
        .pixel_clk(S_hdmi_pixel_clk), .serial_clk(S_hdmi_serial_clk),
        .lock(S_hdmi_pll_lock)
    );

    PLL u_PLL(
        .refclk      ( I_sys_clk         ),
        .reset    	 ( ~I_rst_n          ),
        
        .clk0_out    ( S_100m_clk        ),
        .clk1_out    ( S_24m_clk         ),

        .clk4_out    (                   ),
        .clk5_out    (                   ),

        .lock        ( S_pll_lock        )

    );


	

  
  wire [7:0] V4_scene_mean;
  wire V4_scene_toggle;
  ae_set u_ae_set (
      .external_enable(USB_ae_i2c[24]),.external_exp(USB_ae_i2c[23:8]),.external_gain(USB_ae_i2c[7:0]),
      .I_mean(V4_scene_mean),.I_mean_toggle(V4_scene_toggle),
      .correction_mode(PRO_mode_i2c),.calibrate(PRO_cal_sync^PRO_cal_last),.freeze(PRO_freeze_i2c),.exposure_status(PRO_exposure_i2c),.gain_status(PRO_gain_i2c),
      .I_clk(S_24m_clk),
      .I_rst(~S_rst_n),
      .I_btn(4'b1111),
      .I_cam_cfg_done(S_cam_cfg_done),
      .I_ae_cfg_done(S_ae_cfg_done),
      .O_ae_req(S_ae_req),
      .O_ae(S_ae),
      .O_ag(S_ag)
  );
  
    uicfgcs520 #(
      .CLK_DIV(23809524 / 100000 - 1)
  ) u_uicfgcs520 (
      .I_clk(S_24m_clk),  //系统时钟输入
      .I_rst_n(S_cam_i2c_ready), // SC520CS power-up delay completed
      .I_ae_req(S_ae_req),
      .I_ae(S_ae),
      .I_ag(S_ag),
      .O_cam_scl(O_cam_scl),  //I2C总线，SCL时钟
      .IO_cam_sda(IO_cam_sda),  //I2C总线，SDA数据
      .O_cfg_done(S_cam_cfg_done),  //摄像头寄存器初始化完成
      .O_ae_cfg_done(S_ae_cfg_done),  //AE配置完成
      .O_sensor_id(S_cam_sensor_id),
      .O_sensor_id_ok(S_cam_sensor_id_ok),
      .O_iic_error(S_cam_i2c_error)
  );
	
    mipi_dphy_rx_ph1p_mipiio_wrapper#(
        .DPHY_RX_LOCATION      ( "DPHY0" ),
        .HS_EQUALIZER          ( "3dB"   ),// 828 Mbps/Lane接收均衡
        .HS_VGA_GAIN           ( "8dB" ),//"-3dB","-1.5dB","0dB","1.5dB","3dB","4.5dB","6dB","7.5dB"
        .LANE_NUM              ( 2       ),
        .BYTE_NUM              ( 1       )
    )u_mipi_dphy_rx_ph1p_mipiio_wrapper(
        .I_lp_clk              ( S_100m_clk       ),
        .I_rst                 ( ~S_rst_n         ),

        .I_clk_lane_in_delay   ( 6'd0             ),
        .I_data_lane0_in_delay ( 6'd0             ),
        .I_data_lane1_in_delay ( 6'd0             ),
        .I_data_lane2_in_delay ( 6'd0             ),
        .I_data_lane3_in_delay ( 6'd0             ),

        .I_lane_invert         ( 4'b0000          ),
     
        .O_hs_rx_clk           ( S_csi_rx_clk     ),
        .O_hs_rx_valid         ( S_hs_rx_valid    ),
        .O_hs_rx_data          ( S_hs_rx_data     ),
      
        .O_lp_rx_lane0_p       (  ),
        .O_lp_rx_lane0_n       (  ),
      
        .I_lp_tx_en            ( 1'b0             ),
        .I_lp_tx_lane0_p       ( 1'b1             ),
        .I_lp_tx_lane0_n       ( 1'b1             ),
      
        .O_lane_match_error    (                  ),
        .O_lane_error          ( S_lane_error     ),
      
        .IO_rx_clk_pad_n       ( IO_rx_clk_pad_n  ),
        .IO_rx_clk_pad_p       ( IO_rx_clk_pad_p  ),
        .IO_rx_data_pad_n      ( IO_rx_data_pad_n ),
        .IO_rx_data_pad_p      ( IO_rx_data_pad_p )
    );
	
	
 //  cwc cwc_inst
 //(
 //    .probe0(S_hs_rx_valid),
 //    .probe1(S_hs_rx_data),
 //    .probe2(S_lane_error),
 //    .clk(S_csi_rx_clk)
 //);

 //csi 解码为RAW数据
csi_unpacket_2lane u_csi_unpacket(
.I_clk                 ( S_csi_rx_clk       ),
.I_rst_n               ( S_rst_n        	),
.I_hs_valid            ( S_hs_rx_valid     ),
.I_hs_data             ( S_hs_rx_data      ),

.O_csi_frame_start     ( S_csi_frame_start ),
.O_csi_frame_end       ( S_csi_frame_end   ),
.O_csi_valid           ( S_csi_valid       ),
.O_csi_data            ( S_csi_data        ),
.O_data_length         ( S_csi_data_length )
);


//解码为RAW8
raw10_unpacket_2lane u_raw10_unpacket (
.I_clk  (S_csi_rx_clk),
.I_rst_n(S_rst_n),

.I_csi_frame_start(S_csi_frame_start),
.I_csi_frame_end  (S_csi_frame_end),
.I_csi_valid      (S_csi_valid),
.I_csi_data       (S_csi_data),

.O_raw10_frame_start(S_raw10_frame_start),
.O_raw10_frame_end  (S_raw10_frame_end),
.O_raw10_valid      (S_raw10_valid),
.O_raw10_data       (S_raw10_data)
  );


//将数据转为stream流
uial2axis #(
.IMG_WIDTH(1280),
.IMG_HEIGHT(720),
.INPUT_DATA_WIDTH(40)
) 
u_uial2axis (
.I_native_clk(S_csi_rx_clk),
.I_rst_n     (S_rst_n),
.I_data      (S_raw10_data       ),
.I_data_valid(S_raw10_valid      ),
.I_data_start(S_raw10_frame_start),
.I_data_end  (S_raw10_frame_end  ),
.axis_tvalid (S_axis_tvalid),
.axis_tdata  (S_axis_tdata ),
.axis_tuser  (S_axis_tuser ),
.axis_tlast  (S_axis_tlast )
);
	

// SC520CS原厂HD模式已经直接输出1280x720 RAW10，无需FPGA窗口裁剪。
assign S_raw_tdata  = S_axis_tdata;
assign S_raw_tlast  = S_axis_tlast;
assign S_raw_tvalid = S_axis_tvalid;
assign S_raw_tuser  = S_axis_tuser;


//cwc1 cwc1_Inst
//  (
//      .probe0(S_axis_tuser),
//      .probe1(S_axis_tvalid),
//      .probe2(S_axis_tlast),
//      .probe3(S_axis_tdata),
//      .probe4(S_ISP_O_tuser),
//      .probe5(S_ISP_O_tvalid),
//      .probe6(S_ISP_O_tlast),
//      .probe7(S_ISP_O_tdata),
//      .probe8 (S_raw_tdata ),
//      .probe9 (S_raw_tlast ),
//      .probe10(S_raw_tvalid),
//      .probe11(S_raw_tuser ),
//      .clk(S_csi_rx_clk)
//  );


//ISP算法顶层模块
isp_top u_isp_top (
.axi4s_video_aclk(S_csi_rx_clk),
.I_rst_n         (S_rst_n),
.I_tlast         (S_raw_tlast	),
.I_tuser         (S_raw_tuser	),
.I_tdata         (S_raw_tdata	),
.I_tvalid        (S_raw_tvalid	),
.I_tdest         (),
.O_tready        (S_ISP_O_tready),
.O_tdata         (S_ISP_O_tdata ),
.O_tlast         (S_ISP_O_tlast ),
.O_tuser         (S_ISP_O_tuser ),
.O_tvalid        (S_ISP_O_tvalid),
.I_tready        ()
  );

    // SW4..SW1 select mode[3:0]. Changes are accepted only after the complete
    // vector has remained stable for the debounce interval.
    switch_status_filter #(
        .DEBOUNCE_CYCLES ( 750000 )
    ) u_switch_status_filter (
        .I_clk          ( S_csi_rx_clk     ),
        .I_rst_n        ( S_rst_n          ),
        .I_switch_async ( I_switch         ),
        .O_status       ( S_mode_requested )
    );

    // SC520CS asserts tuser as a frame-boundary marker and it is not required
    // to overlap tvalid. Commit on tuser alone; requiring tuser && tvalid keeps
    // the mode stuck at reset value on this camera pipeline.
    always @(posedge S_csi_rx_clk or negedge S_rst_n) begin
        if(!S_rst_n)
            S_mode_video <= 4'd0;
        else if(S_ISP_O_tuser)
            S_mode_video <= S_mode_decoded;
    end

    assign S_mode_active = S_mode_video;

    // The 4ppc RGB byte groups are not pixel-aligned.  They must pass
    // unchanged through DDR; all mode effects run on unpacked RGB888 below.

    wire [1:0] V4_read_bank;
    wire [31:0] V4_published_ms,V4_published_seq,V4_source_ms,V4_now_gray;
    wire V4_published_valid;
    video_in u_video_in(
        .I_fps_preset(S_fps_preset),.I_read_bank(V4_read_bank),
        .O_source_ms(V4_published_ms),.O_source_seq(V4_published_seq),.O_source_valid(V4_published_valid),.O_now_gray(V4_now_gray),
        .I_rst_n              (  S_rst_n             ),

        .I_camera_clk         ( S_csi_rx_clk          ),
        // Clear the capture FIFO on CSI frame-start, before the ISP pixels arrive.
        // Packed RGB SOF coincides with the first pixels; using it for the FIFO
        // reset discards the first burst and prevents complete-frame publication.
        .I_camera_frame_start ( S_csi_frame_start ),
        .I_camera_valid       ( S_ISP_O_tvalid),
          .I_camera_data        ( S_ISP_O_tdata      ),
        .I_mipi_rx_error      ( 1'b0			      ),

        .I_ddr_clk            ( S_ddr_clk             ),
		.I_display_pause      ( PRO_freeze                  ),
        .I_video_out_rd_busy  ( S_video_out_rd_busy   ),
        .O_video_in_wr_busy   ( S_video_in_wr_busy    ),
        .O_video_out_rp       ( S_video_out_rp        ),

        .O_ddr_user_wr_en     ( S_vi_ddr_wr_en        ),
        .O_ddr_user_addr      ( S_vi_ddr_wr_addr      ),
        .O_ddr_user_wr_data   ( S_vi_ddr_wr_data      ),
        .I_ddr_user_ready     ( S_ddr_user_ready      )
    );



    assign S_ddr_user_wr_en    = S_vi_ddr_wr_en;

    assign S_ddr_user_rd_en    = S_vo_ddr_rd_en;

    assign S_ddr_user_addr     = S_vi_ddr_wr_en ? S_vi_ddr_wr_addr :
                                 S_vo_ddr_rd_en ? S_vo_ddr_rd_addr : 'd0;

    assign S_ddr_user_wr_data  = S_vi_ddr_wr_data;


    assign S_video_out_rst_n = S_hdmi_rst_n;

    video_out u_video_out(
        .I_freeze(PRO_freeze),.O_freeze_ack(PRO_freeze_ack_ddr),
        .I_source_ms(V4_published_ms),.I_source_seq(V4_published_seq),.I_source_valid(V4_published_valid),
        .O_source_ms(V4_source_ms),.O_source_seq(V4_source_seq),.O_source_valid(V4_source_valid),.O_read_bank(V4_read_bank),
        .I_rst_n             ( S_video_out_rst_n    ),
        .I_ddr_clk           ( S_ddr_clk            ),
 
        .O_video_out_rd_busy ( S_video_out_rd_busy  ),
        .I_video_in_wr_busy  ( S_video_in_wr_busy   ),
        .I_video_out_rp      ( S_video_out_rp       ),
 
        .O_ddr_user_rd_en    ( S_vo_ddr_rd_en       ),
        .O_ddr_user_addr     ( S_vo_ddr_rd_addr     ),
        .I_ddr_user_ready    ( S_ddr_user_ready     ),
        .I_ddr_user_rd_valid ( S_ddr_user_rd_valid  ),
        .I_ddr_user_rd_data  ( S_ddr_user_rd_data   ),

        .I_dsi_clk           ( S_hdmi_pixel_clk     ),
        .I_video_vsync       ( S_video_out_vsync    ),
        .I_video_rd_en       ( S_hdmi_de            ),
        .O_vdieo_data        ( S_video_rd_data      )
    );

    // Process complete RGB888 pixels after DDR byte unpacking.  The adapter
    // preserves the full 720p raster and aligns the pipeline with HDMI timing.
    wire V11_gesture_valid;wire [2:0] V11_gesture_value;wire [47:0] V11_gesture_box;
    wire [191:0] V11_after_histogram;wire [191:0] V11_histogram;wire [31:0] V11_gains;
    wire [7:0] V11_threshold;wire [14:0] V11_ink;wire [3:0] V11_state;
    wire V11_motion_valid;wire [47:0] V11_motion_box;wire [11:0] V11_motion_count;
    wire [10:0] V11_pan_us,V11_tilt_us;
    wire [19:0] DF_pan_hz_bcd,DF_tilt_hz_bcd,DF_pan_duty_bcd,DF_tilt_duty_bcd;
    servo_pwm_telemetry pwm_stats(.clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.video_vs(S_effect_vsync),
      .pan_pwm(O_servo_pan),.tilt_pwm(O_servo_tilt),.pan_hz_bcd(DF_pan_hz_bcd),.tilt_hz_bcd(DF_tilt_hz_bcd),
      .pan_duty_bcd(DF_pan_duty_bcd),.tilt_duty_bcd(DF_tilt_duty_bcd));

    wire V4_rvalid,V4_gvalid;
    wire [47:0] V4_rbox,V4_gbox;
    servo_tracker_pro #(.REVERSE_PAN(1),.REVERSE_TILT(1)) servo(.clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),.enable(SORT_enable || ((PRO_face_track || PRO_effective_mode==10 || USB_manual) && !USB_recenter)),.manual_enable(SORT_enable || USB_manual),.manual_pan_us(SORT_enable?SORT_pan:USB_pan),.manual_tilt_us(SORT_enable?SORT_tilt:USB_tilt),.face_source(PRO_face_track),.frame_start(S_effect_user),.target_valid(PRO_face_track?PRO_face_valid:V4_rvalid),.target_update(PRO_face_track?PRO_face_update:S_effect_user),.target_age(PRO_face_track?PRO_face_measurement_age:8'd0),.box(PRO_face_track?PRO_face_measurement_box:V4_rbox),.pan_pwm(O_servo_pan),.tilt_pwm(O_servo_tilt),.pan_us(V11_pan_us),.tilt_us(V11_tilt_us),.ready(PRO_track_ready),.center_seconds(PRO_center_seconds));

    video_stream_adapter #(.WIDTH(1280), .HEIGHT(720),.ENABLE_FACE(ENABLE_FACE)) u_video_stream_adapter (
        .clk(S_hdmi_pixel_clk), .rst_n(S_hdmi_rst_n),
        .in_vs(S_hdmi_vsync), .in_hs(S_hdmi_hsync),
        .in_de(S_hdmi_de), .in_user(S_hdmi_user), .in_last(S_hdmi_last),
        .ddr_rgb(S_video_rd_data), .requested_mode(legacy_mode(PRO_effective_mode)),.sort_active(SORT_active),.sort_source_frame(V4_source_seq[15:0]),.sort_records(SORT_records),.sort_valid(SORT_valid),.sort_frame(SORT_frame),.sort_digits(SORT_digits),.sort_classes(SORT_classes),.sort_shapes(SORT_shapes),.external_wb(USB_wb_override),.external_r(USB_wb_r),.external_b(USB_wb_b),.external_saturation(USB_saturation),
        .correction_mode(PRO_correction_mode),.calibrate(PRO_calibrate),.freeze(PRO_freeze),.recognition_ready(PRO_track_ready),.face_track(PRO_face_track),.calibration_busy(PRO_cal_busy),.calibration_valid(PRO_cal_valid),.wb_status(PRO_wb),.tone_status(PRO_tone),.face_valid(PRO_face_valid),.face_box(PRO_face_box),.face_confidence(PRO_face_confidence),.face_update(PRO_face_update),.face_measurement_box(PRO_face_measurement_box),.face_measurement_age(PRO_face_measurement_age),
        .quality(S_quality_preset),.target_valid(V8_target_valid),.target_boxes(V8_target_boxes),.target_shapes(V8_target_shapes),.digit_valid(V8_digit_valid),.digit_value(V8_digit_value),.digit_box(V8_digit_box),.beauty(V5_beauty),.red_shape(V5_red_shape),.green_shape(V5_green_shape),.processing_us(V5_processing_us),
        .gesture_valid(V11_gesture_valid),.gesture_value(V11_gesture_value),.gesture_box(V11_gesture_box),.after_histogram(V11_after_histogram),.histogram(V11_histogram),.balance_gains(V11_gains),.digit_threshold(V11_threshold),.digit_ink(V11_ink),.digit_state(V11_state),.motion_valid(V11_motion_valid),.motion_box(V11_motion_box),.motion_count(V11_motion_count),
        .scene_mean(V4_scene_mean),.scene_toggle(V4_scene_toggle),
        .out_vs(S_effect_vsync), .out_hs(S_effect_hsync),
        .out_de(S_effect_de), .out_user(S_effect_user),
        .out_last(S_effect_last), .out_rgb(S_effect_video_data),
        .red_box_valid(V4_rvalid),.green_box_valid(V4_gvalid),.red_box(V4_rbox),.green_box(V4_gbox)
    );



    mc_to_user_interface u_mc_to_user_interface(
        .I_clk                   ( S_ddr_clk               ),
        .I_rst_n                 ( S_rst_n                 ),

        .I_ddr_user_wr_en        ( S_ddr_user_wr_en        ),
        .I_ddr_user_rd_en        ( S_ddr_user_rd_en        ),
        .I_ddr_user_addr         ( S_ddr_user_addr         ),
        .I_ddr_user_wr_data      ( S_ddr_user_wr_data      ),
        .O_ddr_user_ready        ( S_ddr_user_ready        ),
        .O_ddr_user_rd_valid     ( S_ddr_user_rd_valid     ),
        .O_ddr_user_rd_data      ( S_ddr_user_rd_data      ),
            
        .O_mc_app_en             ( S_mc_app_en             ),
        .O_mc_app_addr           ( S_mc_app_addr           ),
        .O_mc_app_cmd            ( S_mc_app_cmd            ),
        .I_mc_app_rdy            ( S_mc_app_rdy            ),
        .O_mc_app_wdf_wren       ( S_mc_app_wdf_wren       ),
        .O_mc_app_wdf_data       ( S_mc_app_wdf_data       ),
        .O_mc_app_wdf_end        ( S_mc_app_wdf_end        ),
        .O_mc_app_wdf_mask       ( S_mc_app_wdf_mask       ),
        .I_mc_app_wdf_rdy        ( S_mc_app_wdf_rdy        ),
        .I_mc_app_rd_data        ( S_mc_app_rd_data        ),
        .I_mc_app_rd_data_end    ( S_mc_app_rd_data_end    ),
        .I_mc_app_rd_data_valid  ( S_mc_app_rd_data_valid  )
    );



    ph1p35_324_ddr_wrapper u_ph1p35_324_ddr_wrapper(
        .I_sys_clk              ( I_sys_clk              ),
        .I_sys_rst_n            ( S_rst_n                ),

        .O_ddr_clk              ( S_ddr_clk              ),
        .O_init_calib_complete  ( S_init_calib_complete  ),
        .I_mc_app_addr          ( S_mc_app_addr          ),
        .I_mc_app_cmd           ( S_mc_app_cmd           ),
        .I_mc_app_en            ( S_mc_app_en            ),
        .I_mc_app_wdf_data      ( S_mc_app_wdf_data      ),
        .I_mc_app_wdf_end       ( S_mc_app_wdf_end       ),
        .I_mc_app_wdf_mask      ( S_mc_app_wdf_mask      ),
        .I_mc_app_wdf_wren      ( S_mc_app_wdf_wren      ),
        .O_mc_app_rd_data       ( S_mc_app_rd_data       ),
        .O_mc_app_rd_data_end   ( S_mc_app_rd_data_end   ),
        .O_mc_app_rd_data_valid ( S_mc_app_rd_data_valid ),
        .O_mc_app_rdy           ( S_mc_app_rdy           ),
        .O_mc_app_wdf_rdy       ( S_mc_app_wdf_rdy       ),

        .ddr_addr               ( ddr_addr               ),
        .ddr_ba                 ( ddr_ba                 ),
        .ddr_cke                ( ddr_cke                ),
        .ddr_odt                ( ddr_odt                ),
        .ddr_cs_n               ( ddr_cs_n               ),
        .ddr_ras_n              ( ddr_ras_n              ),
        .ddr_cas_n              ( ddr_cas_n              ),
        .ddr_we_n               ( ddr_we_n               ),
        .ddr_ck_p               ( ddr_ck_p               ),
        .ddr_ck_n               ( ddr_ck_n               ),
        .ddr_dm                 ( ddr_dm                 ),
        .ddr_dq                 ( ddr_dq                 ),
        .ddr_dqs_p              ( ddr_dqs_p              ),
        .ddr_dqs_n              ( ddr_dqs_n              )
    );



    uivtc #(
        .H_ActiveSize ( 1280 ),
        .H_FrameSize  ( 1650 ),
        .H_SyncStart  ( 1390 ),
        .H_SyncEnd    ( 1430 ),
        .V_ActiveSize ( 720  ),
        .V_FrameSize  ( 750  ),
        .V_SyncStart  ( 725  ),
        .V_SyncEnd    ( 730  )
    )u_hdmi_vtc(
        .I_vtc_rstn    ( S_hdmi_rst_n    ),
        .I_vtc_clk     ( S_hdmi_pixel_clk ),
        .O_vtc_vs      ( S_hdmi_vsync     ),
        .O_vtc_hs      ( S_hdmi_hsync     ),
        .O_vtc_de_valid( S_hdmi_de        ),
        .O_vtc_user    ( S_hdmi_user      ),
        .O_vtc_last    ( S_hdmi_last      )
    );

    // K3/K4 (active low) cycle the processing-quality and displayed-FPS
    // presets at frame boundaries. HDMI timing remains a stable 720p raster.
    advanced_controls_pro u_ui_controls(
        .clk          ( S_hdmi_pixel_clk ),
        .rst_n        ( S_hdmi_rst_n ),
        .lock(USB_control_active),.k2_n(I_button[2]),.beauty(LOCAL_beauty),.ms_tick(SORT_ms_tick),
        .beauty_mode(LOCAL_beauty_mode),.calibrate(LOCAL_calibrate),.photo_request(LOCAL_photo_request),.face_track(LOCAL_face_request),
        .k3_n         ( I_button[0] ),
        .k4_n         ( I_button[1] ),
        .frame_start  ( S_hdmi_user ),
        .quality      ( LOCAL_quality ),
        .fps_request  ( LOCAL_fps )
    );

    hdmi_mixer_fast #(
        .H_OFFSET   ( 0    ),
        .V_OFFSET   ( 0    ),
        .IMG_WIDTH  ( 1280 ),
        .IMG_HEIGHT ( 720  ),
        // Normal camera display.  Set to 4 only when the MIPI diagnostic
        // full-screen status page is needed.
        .DEBUG_MODE ( 0    )
    )u_hdmi_mixer(
        .remote_control(USB_control_active),.sort_phase(SORT_phase),.sort_digits(SORT_digits),.sort_classes(SORT_classes),
        .pan_hz_bcd(DF_pan_hz_bcd),.tilt_hz_bcd(DF_tilt_hz_bcd),.pan_duty_bcd(DF_pan_duty_bcd),.tilt_duty_bcd(DF_tilt_duty_bcd),
        .freeze(PRO_freeze),.face_track(PRO_face_track),.center_seconds(PRO_center_seconds),.correction_mode(PRO_correction_mode),.calibration_busy(PRO_cal_busy),.calibration_valid(PRO_cal_valid),.exposure_status(PRO_exposure),.wb_status(PRO_wb),.gain_status(PRO_gain),.tone_status(PRO_tone),.face_valid(PRO_face_valid),.face_box(PRO_face_box),.face_confidence(PRO_face_confidence),.photo_status(PRO_photo_status),.photo_error(PRO_sd_error_code),.O_hdmi_user(PRO_hdmi_user),.O_hdmi_last(PRO_hdmi_last),
        .I_clk           ( S_hdmi_pixel_clk   ),
        .I_rst_n         ( S_hdmi_rst_n       ),
        .I_video_vsync   ( S_effect_vsync     ),
        .I_video_hsync   ( S_effect_hsync     ),
        .I_video_de      ( S_effect_de        ),
        .I_video_user    ( S_effect_user      ),
        .I_video_last    ( S_effect_last      ),
        .gesture_valid(V11_gesture_valid),.gesture_value(V11_gesture_value),.gesture_box(V11_gesture_box),.after_histogram(V11_after_histogram),.histogram(V11_histogram),.balance_gains(V11_gains),.digit_threshold(V11_threshold),.digit_ink(V11_ink),.digit_state(V11_state),.motion_valid(V11_motion_valid),.motion_box(V11_motion_box),.motion_count(V11_motion_count),
        .scene_mean(V4_scene_mean),.I_debug_status  ( PRO_effective_mode),
        .I_quality       ( S_quality_preset    ),.target_valid(PRO_show_red?V8_target_valid:8'd0),.target_boxes(V8_target_boxes),.target_shapes(SORT_active?{8'd0,SORT_shapes}:V8_target_shapes),.digit_valid(V8_digit_valid),.digit_value(V8_digit_value),.digit_box(V8_digit_box),.beauty(V5_beauty),.red_shape(V5_red_shape),.green_shape(V5_green_shape),.processing_us(V5_processing_us),
        .I_fps           ( S_fps_preset        ),
        .red_box_valid(PRO_show_red && V4_rvalid),.green_box_valid(V4_gvalid),.red_box(V4_rbox),.green_box(V4_gbox),
        .source_ms(V4_source_ms),.source_seq(V4_source_seq),.source_valid(V4_source_valid),.now_gray(V4_now_gray),
        .O_video_rd_en   ( S_hdmi_window_rd_en),
        .I_video_rd_data ( S_effect_video_data),
        .O_hdmi_vsync    ( S_hdmi_out_vsync   ),
        .O_hdmi_hsync    ( S_hdmi_out_hsync   ),
        .O_hdmi_de       ( S_hdmi_out_de      ),
        .O_hdmi_data     ( S_hdmi_out_data    )
    );

    // A screenshot is assembled from one protected DDR bank. Pixel timing
    // and HDMI clocks continue, while algorithm/display metadata stays fixed.
    reg [10:0] PRO_photo_x,PRO_photo_y;
    wire [10:0] PRO_px=PRO_hdmi_user?11'd0:PRO_photo_x;
    wire [10:0] PRO_py=PRO_hdmi_user?11'd0:PRO_photo_y;
    reg [27:0] PRO_toast;
    reg [15:0] PRO_sound_count;
    always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)begin
      if(!S_hdmi_rst_n)begin PRO_photo_x<=0;PRO_photo_y<=0;PRO_photo_status<=0;PRO_photo_token<=0;PRO_sd_error_code<=0;PRO_toast<=0;PRO_sound_count<=0;end
      else begin
        if(S_hdmi_out_de)begin
          if(PRO_hdmi_last)begin PRO_photo_x<=0;PRO_photo_y<=PRO_py+1'b1;end
          else begin PRO_photo_x<=PRO_px+1'b1;PRO_photo_y<=PRO_py;end
        end else if(PRO_hdmi_user)begin PRO_photo_x<=0;PRO_photo_y<=0;end
        if(PRO_photo_request && PRO_photo_status!=1)begin
          PRO_photo_token<=PRO_photo_token+1'b1;PRO_sd_error_code<=USB_lease_alive?0:8'h91;
          PRO_photo_status<=USB_lease_alive?1:3;PRO_toast<=28'd222750000;
        end
        if(USB_photo_ack && USB_photo_token==PRO_photo_token && PRO_photo_status==1)begin
          PRO_photo_status<=USB_photo_ok?2:3;PRO_sd_error_code<=USB_photo_ok?0:8'h92;PRO_toast<=28'd222750000;
        end else if(PRO_photo_status==1 && PRO_toast==1)begin PRO_photo_status<=3;PRO_sd_error_code<=8'h93;end
        else if(PRO_toast!=0)begin PRO_toast<=PRO_toast-1'b1;if(PRO_toast==1 && PRO_photo_status==2)PRO_photo_status<=0;end
        if(USB_alarm || PRO_toast>28'd207900000)begin
          if(PRO_sound_count==37124)PRO_sound_count<=0;else PRO_sound_count<=PRO_sound_count+1'b1;
        end else PRO_sound_count<=0;
      end
    end
    reg[5:0] USB_blink_count;always @(posedge S_hdmi_pixel_clk or negedge S_hdmi_rst_n)if(!S_hdmi_rst_n)USB_blink_count<=0;else if(USB_commit)USB_blink_count<=USB_blink_count==29?0:USB_blink_count+1'b1;
    assign O_photo_led=(PRO_photo_status==2 && PRO_toast!=0)||(USB_led && USB_blink_count<15);
    assign O_photo_buzz=(USB_alarm || (PRO_photo_status==2 && PRO_toast>28'd207900000))?(PRO_sound_count<18563):1'b1;

    // Independent low-bandwidth USB preview taps final HDMI after OSD.
    wire[12:0] USB_sumx={1'b0,V4_rbox[47:36]}+{1'b0,V4_rbox[35:24]};
    wire[12:0] USB_sumy={1'b0,V4_rbox[23:12]}+{1'b0,V4_rbox[11:0]};
    wire[10:0] USB_actual_pan=SORT_enable?SORT_pan:(USB_manual?USB_pan:V11_pan_us),USB_actual_tilt=SORT_enable?SORT_tilt:(USB_manual?USB_tilt:V11_tilt_us);
    wire[255:0] USB_status_base={{7'd0,V4_source_valid},
      PRO_tone,
      V11_threshold,
      {5'd0,PRO_center_seconds,PRO_track_ready},
      V4_source_seq[15:8],
      V4_source_seq[7:0],
      PRO_wb[7:0],
      PRO_wb[15:8],
      PRO_exposure[15:8],
      PRO_exposure[7:0],
      PRO_gain,
      V4_scene_mean,
      PRO_photo_token,
      {6'd0,PRO_photo_status},
      {5'd0,USB_actual_tilt[10:8]},
      USB_actual_tilt[7:0],
      {5'd0,USB_actual_pan[10:8]},
      USB_actual_pan[7:0],
      {4'd0,USB_sumy[12:9]},
      USB_sumy[8:1],
      {4'd0,USB_sumx[12:9]},
      USB_sumx[8:1],
      (SORT_active?SORT_shapes:V8_target_shapes[7:0]),
      {4'd0,V8_target_valid[3:0]},
      {5'd0,(SORT_enable?SORT_phase:V11_gesture_value)},
      {5'd0,V8_digit_value},
      S_fps_preset==0?8'd60:S_fps_preset==1?8'd30:8'd15,
      {2'd0,S_fps_preset,S_quality_preset,PRO_correction_mode},
      {V4_rvalid,V11_gesture_valid,V8_digit_valid,(PRO_photo_status==1),PRO_cal_valid,PRO_cal_busy,USB_lease_alive,USB_control_active},
      {4'd0,PRO_effective_mode},
      {4'd0,S_mode_hdmi_sync2},
      8'd5};
    wire[63:0] USB_face_or_sort=SORT_active?{SORT_sequence,SORT_frame,
      2'd0,SORT_classes[11:9],SORT_digits[11:9],2'd0,SORT_classes[8:6],SORT_digits[8:6],
      2'd0,SORT_classes[5:3],SORT_digits[5:3],2'd0,SORT_classes[2:0],SORT_digits[2:0]}:
      {{4'd0,PRO_face_box[11:8]},PRO_face_box[7:0],{4'd0,PRO_face_box[23:20]},PRO_face_box[19:12],
       {4'd0,PRO_face_box[35:32]},PRO_face_box[31:24],{4'd0,PRO_face_box[47:44]},PRO_face_box[43:36]};
    wire[351:0] USB_status={{3'd0,(USB_saturation!=15),(USB_saturation==15?(PRO_correction_mode==1?4'd7:PRO_correction_mode==2?4'd8:4'd6):USB_saturation)},PRO_sd_error_code,
     USB_face_or_sort,
     PRO_face_confidence,{1'b0,USB_ae_override,USB_wb_override,USB_alarm,USB_led,USB_show,USB_manual,PRO_face_valid},USB_status_base};
    usb_host_bridge usb(.clk(S_hdmi_pixel_clk),.rst_n(S_hdmi_rst_n),
      .rx(I_uart_rx),.tx(O_uart_tx),.control_mode(USB_control_active),
      .frame_boundary(USB_commit),.freeze(PRO_freeze),.photo_busy(PRO_sd_busy),.calibration_busy(PRO_cal_busy),
      .video_sof(PRO_hdmi_user),.video_de(S_hdmi_out_de),
      .video_x({1'b0,PRO_px}),.video_y({1'b0,PRO_py}),.video_rgb(S_hdmi_out_data),.status_bytes(USB_status),
      .remote_mode(USB_remote_mode),.remote_beauty(USB_remote_beauty),
      .remote_quality(USB_remote_quality),.remote_fps(USB_remote_fps),
      .calibrate(USB_calibrate),.photo_request(USB_photo_request),.recenter(USB_recenter),
      .lease_alive(USB_lease_alive),.video_busy(USB_video_busy),
      .manual_enable(USB_manual),.manual_pan(USB_pan),.manual_tilt(USB_tilt),.hdmi_show(USB_show),.led_blink(USB_led),.alarm(USB_alarm),
      .wb_override(USB_wb_override),.ae_override(USB_ae_override),.wb_r(USB_wb_r),.wb_b(USB_wb_b),.exposure_gain(USB_gain),.exposure(USB_exp),
      .photo_ack(USB_photo_ack),.photo_ack_token(USB_photo_token),.photo_ack_ok(USB_photo_ok),.saturation_level(USB_saturation));

    hdmi_tx u_hdmi_tx(
        .I_pixel_clk        ( S_hdmi_pixel_clk  ),
        .I_serial_clk       ( S_hdmi_serial_clk ),
        .I_rst              ( ~S_hdmi_rst_n     ),
        .I_serial_rst       ( ~S_hdmi_serial_rst_n ),
        .I_key_in           ( 1'b0              ),
        .I_edid_read_trig   ( 1'b0              ),
        .O_edid_read_valid  (                   ),
        .O_edid_read_data   (                   ),
        .I_video_rgb_enable ( 1'b1              ),
        .I_video_in_vs      ( S_hdmi_out_vsync  ),
        .I_video_in_de      ( S_hdmi_out_de     ),
        .I_video_in_user    ( PRO_hdmi_user     ),
        .I_video_in_valid   ( 1'b0              ),
        .I_video_in_last    ( PRO_hdmi_last     ),
        .O_video_in_ready   (                   ),
        .I_video_in_data    ( USB_show?S_hdmi_out_data:24'd0 ),
        .I_audio_valid      ( 1'b0              ),
        .I_audio_left_data  ( 24'd0             ),
        .I_audio_right_data ( 24'd0             ),
        .I_i2s_BCLK         ( 1'b0              ),
        .I_i2s_LRCK         ( 1'b0              ),
        .I_i2s_DOUT         ( 1'b0              ),
        .O_ddc_scl          (                   ),
        .O_hdmi_clk_p       (                   ),
        .O_hdmi_tx_p        (                   ),
        .O_tmds_ch0_p       ( O_tmds_ch0_p      ),
        .O_tmds_ch1_p       ( O_tmds_ch1_p      ),
        .O_tmds_ch2_p       ( O_tmds_ch2_p      ),
        .O_tmds_clk_p       ( O_tmds_clk_p      )
    );

    
endmodule
