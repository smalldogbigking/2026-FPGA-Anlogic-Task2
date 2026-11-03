// Confirm a red-disc candidate in two consecutive COMPLETE frames before
// publishing it.  A one-frame false red blob cannot flash a large box.
// candidate_valid/box are outputs of the red color_blob_tracker after EOF.
module circle_box_confirm_v4 #(
 parameter [11:0] POSITION_TOLERANCE=12'd64
)(
 input wire clk,rst_n,frame_start,
 input wire candidate_valid,
 input wire [47:0] candidate_box,
 output reg box_valid,
 output reg [47:0] box, input wire [1:0] candidate_shape,output reg [1:0] shape
);
 reg last_valid;reg[1:0] last_shape,shape_streak;
 reg [47:0] last_box;
 reg [1:0] misses;
 // One signed subtraction per coordinate supplies both the distance
 // predicate and smoothing delta, avoiding two absolute-difference subtractors.
 localparam signed [12:0] TOLERANCE={1'b0,POSITION_TOLERANCE};
 wire signed [12:0] last_delta[0:3],box_delta[0:3];
 wire [3:0] near_previous;wire [47:0] smoothed_box;
 genvar c;
 generate for(c=0;c<4;c=c+1)begin: coordinates
  assign last_delta[c]=$signed({1'b0,candidate_box[c*12+:12]})-$signed({1'b0,last_box[c*12+:12]});
  assign box_delta[c]=$signed({1'b0,candidate_box[c*12+:12]})-$signed({1'b0,box[c*12+:12]});
  assign near_previous[c]=last_delta[c]>=-TOLERANCE && last_delta[c]<=TOLERANCE;
  // floor((3*p+c+2)/4) = p + floor((c-p)/4) + (c-p)[1].
  // The 12-bit modular sum is exact because a convex weighted mean remains
  // in 0..4095. Sign extension of delta[12:2] preserves negative rounding.
  wire [11:0] lowpass=box[c*12+:12]+{box_delta[c][12],box_delta[c][12:2]}+box_delta[c][1];
  assign smoothed_box[c*12+:12]=(box_delta[c]>=-13'sd2 && box_delta[c]<=13'sd2)?box[c*12+:12]:lowpass;
 end endgenerate
 wire similar=last_valid && (&near_previous);
 wire smooth_motion=box_valid &&
  box_delta[3]>=-13'sd127 && box_delta[3]<=13'sd127 &&
  box_delta[1]>=-13'sd127 && box_delta[1]<=13'sd127;
 always @(posedge clk or negedge rst_n) begin
  if(!rst_n) begin
   shape<=0;shape_streak<=0;last_shape<=0;last_valid<=0;last_box<=0;box_valid<=0;box<=0;misses<=0;
  end else if(frame_start) begin
   last_valid<=candidate_valid;last_shape<=candidate_shape;
   if(candidate_valid)begin
    last_box<=candidate_box;
    if(last_valid && candidate_shape==last_shape)begin if(shape_streak<3)shape_streak<=shape_streak+1'b1;end
    else shape_streak<=1;
   end else shape_streak<=0;
   if(candidate_valid && similar) begin
    if(!box_valid || (candidate_shape==last_shape && shape_streak>=2))shape<=candidate_shape;
    if(smooth_motion)box<=smoothed_box;
    else box<=candidate_box;
    box_valid<=1;misses<=0;
   end else if(box_valid) begin
    if(misses==1) begin box_valid<=0;misses<=0;end
    else misses<=misses+1'b1;
   end
  end
 end
endmodule

