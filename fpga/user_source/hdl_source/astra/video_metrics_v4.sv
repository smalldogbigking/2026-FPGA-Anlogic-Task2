// All inputs are in clk domain.  The source timestamp must travel with the
// DDR frame selected for display; a timestamp of the latest camera frame is
// not the latency of the frame currently on screen.
module video_metrics_v4 #(parameter integer CLK_HZ=74250000)(
 input wire clk,rst_n,display_sof,new_content_frame,
 input wire displayed_timestamp_valid,
 input wire [31:0] displayed_source_ms,
 output reg [31:0] now_ms,
 output reg [15:0] hdmi_fps,content_fps,
 output reg [15:0] latency_ms,
 output reg latency_valid
);
 reg [31:0] ms_div,sec_div;
 reg [15:0] hdmi_count,content_count;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   now_ms<=0;ms_div<=0;sec_div<=0;hdmi_count<=0;content_count<=0;
   hdmi_fps<=0;content_fps<=0;latency_ms<=0;latency_valid<=0;
  end else begin
   if(ms_div==CLK_HZ/1000-1) begin ms_div<=0;now_ms<=now_ms+1'b1;end
   else ms_div<=ms_div+1'b1;
   if(sec_div==CLK_HZ-1) begin
    sec_div<=0;
    hdmi_fps<=hdmi_count+display_sof;
    content_fps<=content_count+new_content_frame;
    hdmi_count<=0;content_count<=0;
   end else begin
    sec_div<=sec_div+1'b1;
    hdmi_count<=hdmi_count+display_sof;
    content_count<=content_count+new_content_frame;
   end
   if(display_sof) begin
    latency_valid<=displayed_timestamp_valid;
    if(displayed_timestamp_valid)
     latency_ms<=now_ms-displayed_source_ms;
   end
  end
 end
endmodule

// Frame-blanking formatter feeding osd_overlay_v4 directly.  Saturation
// avoids wrapping a three-digit readout when a metric exceeds its range.
module metric_display_format_v4(
 input wire clk,rst_n,display_sof,
 input wire [15:0] content_fps,latency_ms,
 input wire latency_valid,
 output wire [7:0] content_fps_bcd,
 output wire [11:0] latency_ms_bcd,
 output reg latency_valid_display
);
 wire [9:0] fps_clamped=(content_fps>16'd99)?10'd99:content_fps[9:0];
 wire [9:0] latency_clamped=(latency_ms>16'd999)?10'd999:latency_ms[9:0];
 wire [11:0] fps_digits;
 wire done_fps,done_latency;
 metric_bcd_v4 fps_decimal(.clk(clk),.rst_n(rst_n),.start(display_sof),
    .binary(fps_clamped),.bcd(fps_digits),.done(done_fps));
 metric_bcd_v4 latency_decimal(.clk(clk),.rst_n(rst_n),.start(display_sof),
    .binary(latency_clamped),.bcd(latency_ms_bcd),.done(done_latency));
 assign content_fps_bcd=fps_digits[7:0];
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n)latency_valid_display<=0;
  else if(done_latency)latency_valid_display<=latency_valid;
 end
endmodule

// Binary-to-BCD formatter runs during vertical blanking, ten clocks per
// conversion.  Clamp values before the input to 99 FPS and 999 ms.
module metric_bcd_v4(
 input wire clk,rst_n,start,
 input wire [9:0] binary,
 output reg [11:0] bcd,
 output reg done
);
 reg [9:0] source;
 reg [11:0] work;
 reg [3:0] count;
 reg busy;
 reg [11:0] adjusted;
 always @* begin
  adjusted=work;
  if(work[3:0]>=5) adjusted[3:0]=work[3:0]+4'd3;
  if(work[7:4]>=5) adjusted[7:4]=work[7:4]+4'd3;
  if(work[11:8]>=5) adjusted[11:8]=work[11:8]+4'd3;
 end
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   source<=0;work<=0;count<=0;busy<=0;bcd<=0;done<=0;
  end else begin
   done<=0;
   if(start) begin source<=binary;work<=0;count<=0;busy<=1;end
   else if(busy) begin
    work<={adjusted[10:0],source[9]};source<={source[8:0],1'b0};
    if(count==9) begin
     bcd<={adjusted[10:0],source[9]};busy<=0;done<=1;
    end else count<=count+1'b1;
   end
  end
 end
endmodule
