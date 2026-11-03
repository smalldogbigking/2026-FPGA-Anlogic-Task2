// 8N1, clock-enable UART. One pixel clock domain; no generated fabric clock.
module usb_uart_tx #(parameter CLK_HZ=74250000,BAUD=921600)(
 input wire clk,rst_n,start,input wire[7:0]data,output wire tx,output reg busy
);
 localparam DIV=(CLK_HZ+BAUD/2)/BAUD,CW=$clog2(DIV+1);
 reg[CW-1:0]counter;reg[3:0]bitpos;reg[9:0]shift;
 assign tx=busy?shift[0]:1'b1;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin busy<=0;counter<=0;bitpos<=0;shift<=10'h3ff;end
 else if(!busy)begin if(start)begin busy<=1;shift<={1'b1,data,1'b0};counter<=DIV-1;bitpos<=0;end end
 else if(counter==0)begin counter<=DIV-1;shift<={1'b1,shift[9:1]};if(bitpos==9)busy<=0;else bitpos<=bitpos+1'b1;end
 else counter<=counter-1'b1;
 end
endmodule
module usb_uart_rx #(parameter CLK_HZ=74250000,BAUD=921600)(
 input wire clk,rst_n,rx,output reg[7:0]data,output reg valid,framing_error
);
 localparam DIV=(CLK_HZ+BAUD/2)/BAUD,CW=$clog2(DIV+1);
 (* async_reg="true" *) reg[1:0]sync;
 reg[CW-1:0]counter;reg[1:0]state;reg[2:0]bitpos;reg[7:0]shift;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin sync<=3;counter<=0;state<=0;bitpos<=0;shift<=0;data<=0;valid<=0;framing_error<=0;end
 else begin
 sync<={sync[0],rx};valid<=0;framing_error<=0;
 case(state)
 0:if(!sync[1])begin state<=1;counter<=DIV/2-1;end
 1:if(counter==0)begin if(!sync[1])begin state<=2;counter<=DIV-1;bitpos<=0;end else state<=0;end else counter<=counter-1'b1;
 2:if(counter==0)begin shift[bitpos]<=sync[1];counter<=DIV-1;if(bitpos==7)state<=3;else bitpos<=bitpos+1'b1;end else counter<=counter-1'b1;
 3:if(counter==0)begin state<=0;if(sync[1])begin data<=shift;valid<=1;end else framing_error<=1;end else counter<=counter-1'b1;
 endcase
 end end
endmodule

// FPG1 packet transport. Preview owns a small ERAM, never stalls HDMI or DDR.
// Commands: A5 5A seq cmd arg0 arg1 arg2 CRC8(poly07, init0, over five data bytes).
// Replies: FPG1 type seq lenLE payload CRC16LE (CCITT-FALSE, excludes magic).
module usb_host_bridge #(parameter CLK_HZ=74250000,BAUD=921600,WIDTH=1280,HEIGHT=720,SAMPLE_STEP=8,SAMPLE_Y=8,STATUS_BYTES=44,CHUNK_ROWS=8)(
 input wire clk,rst_n,rx,control_mode,frame_boundary,freeze,photo_busy,calibration_busy,
 input wire video_sof,video_de,input wire[11:0]video_x,video_y,input wire[23:0]video_rgb,
 input wire[STATUS_BYTES*8-1:0]status_bytes,
 output wire tx,output reg[3:0]remote_mode,
 output reg[1:0]remote_beauty,remote_quality,remote_fps,
 output reg calibrate,photo_request,recenter,output wire lease_alive,
 output wire video_busy,
 output reg manual_enable,output reg[10:0] manual_pan,manual_tilt,
 output reg hdmi_show,led_blink,alarm,
 output reg wb_override,ae_override,output reg[7:0] wb_r,wb_b,exposure_gain,
 output reg[15:0] exposure,
 output reg photo_ack,output reg[7:0] photo_ack_token,output reg photo_ack_ok,
 output reg[3:0] saturation_level
);
 // A single8-row strip:320x8 maximum, two ERAMs instead of four.
 // USB scans strips over successive HDMI refreshes. HDMI never waits.
 localparam PW=WIDTH/SAMPLE_STEP,PH=HEIGHT/SAMPLE_Y;
 localparam STEP_BITS=$clog2(SAMPLE_STEP),Y_BITS=$clog2(SAMPLE_Y);
 localparam AW=$clog2(2*PW*CHUNK_ROWS+1),DEPTH=1<<AW;
 reg high_detail;reg capture_pending,capture_active,frame_ready;
 reg[15:0] strip_row;
 wire[15:0] preview_width=high_detail?2*PW:PW;
 wire[15:0] preview_height=high_detail?2*PH:PH;
 wire[15:0] strip_end=(strip_row+CHUNK_ROWS>preview_height)?preview_height:strip_row+CHUNK_ROWS;
 wire[7:0] strip_rows=strip_end-strip_row;
 wire[15:0] strip_pixels=high_detail?strip_rows*(2*PW):strip_rows*PW;
 wire[11:0] sample_row=high_detail?(video_y>>(Y_BITS-1)):(video_y>>Y_BITS);
 wire sample_grid=high_detail?
  (video_x[STEP_BITS-2:0]==SAMPLE_STEP/4-1 && video_y[Y_BITS-2:0]==SAMPLE_Y/4-1):
  (video_x[STEP_BITS-1:0]==SAMPLE_STEP/2-1 && video_y[Y_BITS-1:0]==SAMPLE_Y/2-1);
 wire strip_first=video_de && sample_grid && sample_row==strip_row &&
  video_x==(high_detail?SAMPLE_STEP/4-1:SAMPLE_STEP/2-1);
 wire strip_start=capture_pending && strip_first && !photo_busy;
 wire strip_sample=video_de && sample_grid && sample_row>=strip_row && sample_row<strip_end;

 localparam LEASE_FRAMES=300; // nominal 5s at fixed 60Hz HDMI scan
 wire[7:0]rx_data;wire rx_valid,rx_error,tx_busy;
 reg tx_start;reg[7:0]tx_data;
 usb_uart_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) uart_rx(clk,rst_n,rx,rx_data,rx_valid,rx_error);
 usb_uart_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) uart_tx(clk,rst_n,tx_start,tx_data,tx,tx_busy);
 function[7:0]crc8;input[7:0]c,b;reg[7:0]v;integer n;
 begin v=c^b;for(n=0;n<8;n=n+1)v=v[7]?(v<<1)^8'h07:v<<1;crc8=v;end endfunction
 reg[2:0]rx_pos;reg[7:0]req_seq,req_cmd,arg0,arg1,arg2,rx_crc;
 reg[19:0]rx_timeout;
 wire packet=rx_valid&&rx_pos==7&&rx_data==rx_crc;
 wire is_edge_command=req_cmd==2||req_cmd==3||req_cmd==6;
 reg cached;reg[7:0]last_seq,last_cmd,last_crc,last_status;
 wire duplicate=cached&&is_edge_command&&req_seq==last_seq&&req_cmd==last_cmd&&rx_crc==last_crc;
 reg[3:0]mode_req;reg[1:0]beauty_req,quality_req,fps_req;
 reg config_pending,cal_pending,photo_pending,recenter_pending;
 reg control_d,manual_req,show_req,led_req,alarm_req,wb_req,ae_req;
 reg[3:0] saturation_req;
 reg[10:0] pan_req,tilt_req;reg[7:0] wr_req,wb_req_value,gain_req;reg[15:0] exp_req;
 wire[23:0] args={arg2,arg1,arg0};
 function[10:0] clamp_us;input[10:0] v;begin clamp_us=v<1000?1000:v>2000?2000:v;end endfunction
 reg[8:0]lease;
 assign lease_alive=lease!=0;
 reg ack_pending,status_pending;reg[7:0]ack_seq,ack_cmd,ack_code,status_seq;
 reg[AW-1:0]capture_index;
 reg[6:0]capture_age;
 reg[7:0]frame_seq;reg[15:0]frame_counter,captured_counter;
 reg[STATUS_BYTES*8-1:0]captured_status;
 (* ram_style="bram" *) reg[7:0]pixels[0:DEPTH-1];
 reg[7:0]pixel_read;
 reg[3:0]tx_state;reg[1:0]tx_kind;reg[7:0]packet_seq,packet_cmd,packet_code;
 reg[15:0]payload_length,payload_index;reg[1:0]magic_index;
 reg[STATUS_BYTES*8-1:0]packet_status;
 reg[15:0]tx_crc;reg[7:0]crc_byte;reg[3:0]crc_left;
 reg crc_feed;reg[7:0]crc_feed_byte;
 reg[7:0]response;reg recognized;
 
 wire[AW-1:0]read_addr=payload_index>=10+STATUS_BYTES?payload_index-10-STATUS_BYTES:0;
 assign video_busy=capture_pending||capture_active||frame_ready||(tx_state!=0&&tx_kind==3);
 // A single physical write port is essential for TD ERAM inference.
 // Merge the first-pixel address before the RAM, not as two write statements.
 wire pixel_write=strip_start||(capture_active&&strip_sample&&capture_index<strip_pixels);
 wire[AW-1:0]pixel_write_addr=strip_start?{AW{1'b0}}:capture_index;
 always @(posedge clk)begin
 pixel_read<=pixels[read_addr];
 if(pixel_write)pixels[pixel_write_addr]<={video_rgb[23:21],video_rgb[15:13],video_rgb[7:6]};
 end
 reg[7:0]payload_byte;
 always @*begin
 payload_byte=0;
 if(tx_kind==1)begin
 if(payload_index==0)payload_byte=packet_cmd;
 else if(payload_index==1)payload_byte=packet_code;
 else payload_byte=packet_status[(payload_index-2)*8+:8];
 end else if(tx_kind==2)payload_byte=packet_status[payload_index*8+:8];
 else begin
 case(payload_index)
 0:payload_byte=captured_counter[7:0];1:payload_byte=captured_counter[15:8];
 2:payload_byte=preview_width[7:0];3:payload_byte=preview_width[15:8];4:payload_byte=preview_height[7:0];5:payload_byte=preview_height[15:8];6:payload_byte=2;
 default:begin
 if(payload_index<7+STATUS_BYTES)payload_byte=captured_status[(payload_index-7)*8+:8];
 else if(payload_index==7+STATUS_BYTES)payload_byte=strip_row[7:0];
 else if(payload_index==8+STATUS_BYTES)payload_byte=strip_row[15:8];
 else if(payload_index==9+STATUS_BYTES)payload_byte=strip_rows;
 else payload_byte=pixel_read;
 end
 endcase end
 end
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 rx_pos<=0;req_seq<=0;req_cmd<=0;arg0<=0;arg1<=0;arg2<=0;rx_crc<=0;rx_timeout<=0;
 cached<=0;last_seq<=0;last_cmd<=0;last_crc<=0;last_status<=0;
 mode_req<=0;beauty_req<=0;quality_req<=0;fps_req<=0;
 remote_mode<=0;remote_beauty<=0;remote_quality<=0;remote_fps<=0;lease<=0;
 config_pending<=0;cal_pending<=0;photo_pending<=0;recenter_pending<=0;calibrate<=0;photo_request<=0;recenter<=0;
 ack_pending<=0;status_pending<=0;ack_seq<=0;ack_cmd<=0;ack_code<=0;status_seq<=0;
 capture_pending<=0;capture_active<=0;frame_ready<=0;capture_index<=0;capture_age<=0;high_detail<=0;strip_row<=0;frame_seq<=0;frame_counter<=0;captured_counter<=0;captured_status<=0;
 tx_state<=0;tx_kind<=0;packet_seq<=0;packet_cmd<=0;packet_code<=0;payload_length<=0;payload_index<=0;magic_index<=0;packet_status<=0;
 manual_enable<=0;manual_pan<=1500;manual_tilt<=1500;hdmi_show<=1;led_blink<=0;alarm<=0;
 saturation_req<=15;saturation_level<=15;
 wb_override<=0;ae_override<=0;wb_r<=64;wb_b<=64;exposure_gain<=48;exposure<=1991;
 photo_ack<=0;photo_ack_token<=0;photo_ack_ok<=0;control_d<=0;
 manual_req<=0;show_req<=1;led_req<=0;alarm_req<=0;wb_req<=0;ae_req<=0;
 pan_req<=1500;tilt_req<=1500;wr_req<=64;wb_req_value<=64;gain_req<=48;exp_req<=1991;
 tx_start<=0;tx_data<=0;tx_crc<=16'hffff;crc_byte<=0;crc_left<=0;crc_feed<=0;crc_feed_byte<=0;
 end else begin
 calibrate<=0;photo_request<=0;recenter<=0;photo_ack<=0;tx_start<=0;crc_feed<=0;
 control_d<=control_mode;
 if(control_mode&&!control_d)begin
  saturation_req<=15;
  mode_req<=0;remote_mode<=0;beauty_req<=0;remote_beauty<=0;quality_req<=0;remote_quality<=0;fps_req<=0;remote_fps<=0;
  config_pending<=0;cal_pending<=0;photo_pending<=0;recenter_pending<=0;
  manual_req<=0;show_req<=1;led_req<=0;alarm_req<=0;wb_req<=0;ae_req<=0;
 end
 if(frame_boundary)begin
  saturation_level<=control_mode&&lease_alive?saturation_req:4'd15;
  manual_enable<=control_mode&&lease_alive&&manual_req;
  hdmi_show<=!control_mode||!lease_alive||show_req;
  led_blink<=control_mode&&lease_alive&&led_req;alarm<=control_mode&&lease_alive&&alarm_req;
  wb_override<=control_mode&&lease_alive&&wb_req;ae_override<=control_mode&&lease_alive&&ae_req;
  manual_pan<=pan_req;manual_tilt<=tilt_req;wb_r<=wr_req;wb_b<=wb_req_value;exposure<=exp_req;exposure_gain<=gain_req;
 end
 if(video_sof)frame_counter<=frame_counter+1'b1;
 if(frame_boundary)begin
 if(lease!=0&&!freeze&&!photo_busy)begin
 lease<=lease-1'b1;
 // A later QUERY renews the lease but must not resume a stale actuator command.
 if(lease==1)begin
 saturation_req<=15;saturation_level<=15;
 manual_req<=0;show_req<=1;led_req<=0;alarm_req<=0;wb_req<=0;ae_req<=0;
 manual_enable<=0;hdmi_show<=1;led_blink<=0;alarm<=0;wb_override<=0;ae_override<=0;
 config_pending<=0;cal_pending<=0;photo_pending<=0;recenter_pending<=0;
 remote_mode<=0;remote_beauty<=0;remote_quality<=0;remote_fps<=0;
 end
 end
 if(!control_mode)begin cal_pending<=0;photo_pending<=0;recenter_pending<=0;end
 else if(!freeze&&!photo_busy)begin
 if(config_pending)begin remote_mode<=mode_req;remote_beauty<=beauty_req;remote_quality<=quality_req;remote_fps<=fps_req;config_pending<=0;end
 if(cal_pending&&!photo_busy)begin calibrate<=1;cal_pending<=0;remote_beauty<=2;beauty_req<=2;end
 if(photo_pending&&!photo_busy)begin photo_request<=1;photo_pending<=0;end
 if(recenter_pending)begin recenter<=1;recenter_pending<=0;end
 end end
 // Receive parser; timeout recovers a truncated USB packet.
 if(rx_error)begin rx_pos<=0;rx_timeout<=0;end
 else if(rx_valid)begin
 rx_timeout<=0;
 case(rx_pos)
 0:if(rx_data==8'ha5)rx_pos<=1;
 1:if(rx_data==8'h5a)rx_pos<=2;else rx_pos<=(rx_data==8'ha5) ? 1 : 0;
 2:begin req_seq<=rx_data;rx_crc<=crc8(0,rx_data);rx_pos<=3;end
 3:begin req_cmd<=rx_data;rx_crc<=crc8(rx_crc,rx_data);rx_pos<=4;end
 4:begin arg0<=rx_data;rx_crc<=crc8(rx_crc,rx_data);rx_pos<=5;end
 5:begin arg1<=rx_data;rx_crc<=crc8(rx_crc,rx_data);rx_pos<=6;end
 6:begin arg2<=rx_data;rx_crc<=crc8(rx_crc,rx_data);rx_pos<=7;end
 7:begin
 rx_pos<=0;response=0;recognized=1;
 if(rx_data!=rx_crc)response=1;
 else if(duplicate)response=last_status;
 else case(req_cmd)
 1:if(!control_mode)response=4;else if(freeze||photo_busy)response=2;
   else if(arg0>14||arg1>2||arg2[7:4]!=0||arg2[1:0]>2||arg2[3:2]>2)response=3;
   else begin mode_req<=arg0[3:0];beauty_req<=arg1[1:0];quality_req<=arg2[1:0];fps_req<=arg2[3:2];config_pending<=1;end
 2:if(!control_mode)response=4;else if(freeze||photo_busy||cal_pending||calibration_busy)response=2;else begin cal_pending<=1;beauty_req<=2;wb_req<=0;ae_req<=0;end
 3:if(!control_mode)response=4;else if(freeze||photo_busy||photo_pending)response=2;else photo_pending<=1;
 4:if(video_busy||photo_busy)response=2;else if(arg0>1 || arg1!=0 || arg2!=0)response=3;else begin capture_pending<=1;capture_age<=0;frame_seq<=req_seq;high_detail<=arg0[0];strip_row<=0;end
 5:begin end // query status, accepted in every physical mode
 6:if(!control_mode)response=4;else if(freeze||photo_busy)response=2;else begin recenter_pending<=1;manual_req<=0;end
 7:if(!control_mode)response=4;else if(args[23:22]!=0)response=3;
   else begin pan_req<=clamp_us(args[10:0]);tilt_req<=clamp_us(args[21:11]);manual_req<=1;end
 8:if(!control_mode)response=4;else if(arg0>7)response=3;
   else begin show_req<=arg0[0];led_req<=arg0[1];alarm_req<=arg0[2];end
 9:if(!control_mode)response=4;else if(calibration_busy||cal_pending)response=2;else case(arg0)
  0:begin wb_req<=0;ae_req<=0;saturation_req<=15;end
  1:if(arg2!=0||arg1<40||arg1>96)response=3;else begin wr_req<=arg1;wb_req<=1;end
  2:if(arg2!=0||arg1<40||arg1>96)response=3;else begin wb_req_value<=arg1;wb_req<=1;end
  3:if({arg2,arg1}<4||{arg2,arg1}>1991)response=3;else begin exp_req<={arg2,arg1};ae_req<=1;end
  4:if(arg2!=0||arg1<16||arg1>80)response=3;else begin gain_req<=arg1;ae_req<=1;end
  5:if(arg2!=0||arg1>8)response=3;else saturation_req<=arg1[3:0];
  default:response=3;
 endcase
 10:begin photo_ack<=1;photo_ack_token<=arg0;photo_ack_ok<=arg1==1;end
 default:begin response=5;recognized=0;end
 endcase
 if(rx_data==rx_crc&&recognized)begin lease<=LEASE_FRAMES;
 if(!duplicate)begin cached<=1;last_seq<=req_seq;last_cmd<=req_cmd;last_crc<=rx_crc;last_status<=response;end
 end
 if(req_cmd==5&&response==0)begin status_pending<=1;status_seq<=req_seq;end
 else begin ack_pending<=1;ack_seq<=req_seq;ack_cmd<=req_cmd;ack_code<=response;end
 end
 endcase
 end else if(rx_pos!=0)begin
 if(rx_timeout==CLK_HZ/100-1)begin rx_pos<=0;rx_timeout<=0;end else rx_timeout<=rx_timeout+1'b1;
 end
 // Capture strips on raster coordinates without backpressure. Do not reuse
 // the strip RAM until its CRC and final UART byte have left the transmitter.
 if(frame_boundary&&(capture_pending||capture_active))begin
  if(capture_age==119)begin
   capture_pending<=0;capture_active<=0;ack_pending<=1;ack_seq<=frame_seq;ack_cmd<=4;ack_code<=6;
  end else capture_age<=capture_age+1'b1;
 end
 if(strip_start)begin
  capture_pending<=0;capture_active<=1;capture_index<=1;capture_age<=0;
  if(strip_row==0)begin captured_counter<=frame_counter;captured_status<=status_bytes;end
 end else if(capture_active&&strip_sample&&capture_index<strip_pixels)begin
  capture_index<=capture_index+1'b1;
  if(capture_index==strip_pixels-1)begin capture_active<=0;frame_ready<=1;end
 end
 // Bit-serial CRC: eight small cycles per byte, hidden inside UART bit time.
 if(crc_feed)begin crc_byte<=crc_feed_byte;crc_left<=8;end
 else if(crc_left!=0)begin
 tx_crc<=(tx_crc[15]^crc_byte[7])?(tx_crc<<1)^16'h1021:tx_crc<<1;
 crc_byte<=crc_byte<<1;crc_left<=crc_left-1'b1;
 end
 if(tx_state==0)begin
 if(ack_pending)begin
 tx_kind<=1;packet_seq<=ack_seq;packet_cmd<=ack_cmd;packet_code<=ack_code;packet_status<=status_bytes;payload_length<=2+STATUS_BYTES;ack_pending<=0;tx_state<=1;magic_index<=0;tx_crc<=16'hffff;
 end else if(status_pending)begin
 tx_kind<=2;packet_seq<=status_seq;packet_status<=status_bytes;payload_length<=STATUS_BYTES;status_pending<=0;tx_state<=1;magic_index<=0;tx_crc<=16'hffff;
 end else if(frame_ready)begin
 tx_kind<=3;packet_seq<=frame_seq;payload_length<=strip_pixels+10+STATUS_BYTES;frame_ready<=0;tx_state<=1;magic_index<=0;tx_crc<=16'hffff;
 end
 end else if(!tx_busy&&!tx_start&&crc_left==0&&!crc_feed)begin
 tx_start<=1;
 case(tx_state)
 1:begin
 case(magic_index)0:tx_data<="F";1:tx_data<="P";2:tx_data<="G";3:tx_data<="1";endcase
 if(magic_index==3)tx_state<=2;else magic_index<=magic_index+1'b1;
 end
 2:begin tx_data<=8'h80+tx_kind;crc_feed<=1;crc_feed_byte<=8'h80+tx_kind;tx_state<=3;end
 3:begin tx_data<=packet_seq;crc_feed<=1;crc_feed_byte<=packet_seq;tx_state<=4;end
 4:begin tx_data<=payload_length[7:0];crc_feed<=1;crc_feed_byte<=payload_length[7:0];tx_state<=5;end
 5:begin tx_data<=payload_length[15:8];crc_feed<=1;crc_feed_byte<=payload_length[15:8];payload_index<=0;tx_state<=6;end
 6:begin tx_data<=payload_byte;crc_feed<=1;crc_feed_byte<=payload_byte;
 if(payload_index==payload_length-1)tx_state<=7;else payload_index<=payload_index+1'b1;end
 7:begin tx_data<=tx_crc[7:0];tx_state<=8;end
 8:begin tx_data<=tx_crc[15:8];tx_state<=9;end
 9:begin
 tx_start<=0;tx_state<=0;
 if(tx_kind==3 && strip_end<preview_height)begin strip_row<=strip_end;capture_index<=0;capture_age<=0;capture_pending<=1;end
 end
 default:begin tx_start<=0;tx_state<=0;end
 endcase
 end
 end end
endmodule
