// All inputs MUST be in clk domain. Source timestamp is metadata belonging
// to the particular DDR frame being displayed, not the latest camera SOF.
module frame_metrics #(parameter CLK_HZ=74250000)(
 input wire clk,rst_n,display_sof,source_sof,
 input wire source_timestamp_valid,
 input wire [31:0] displayed_source_timestamp,
 output reg [31:0] ticks,latency_ticks,
 output reg latency_valid,
 output reg [15:0] display_fps,source_fps
);
 reg [31:0] second_count;
 reg [15:0] dcount,scount;
 always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin ticks<=0;latency_ticks<=0;latency_valid<=0;display_fps<=0;source_fps<=0;second_count<=0;dcount<=0;scount<=0;end
 else begin
 ticks<=ticks+1'b1;
 if(second_count==CLK_HZ-1) begin
 second_count<=0;display_fps<=dcount+display_sof;source_fps<=scount+source_sof;dcount<=0;scount<=0;
 end else begin second_count<=second_count+1'b1;dcount<=dcount+display_sof;scount<=scount+source_sof;end
 if(display_sof) begin latency_valid<=source_timestamp_valid;latency_ticks<=ticks-displayed_source_timestamp;end
 end
 end
endmodule
