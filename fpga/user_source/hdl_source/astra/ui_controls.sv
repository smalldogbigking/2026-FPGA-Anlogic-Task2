// Debounced ACTIVE-LOW buttons, synchronized to pixel/system clock.
// Requests are presets only. fps_request does NOT change sensor/HDMI clocks.
module ui_controls #(parameter DEBOUNCE_CYCLES=1500000)(
 input wire clk,rst_n,k3_n,k4_n,frame_start,k2_n,
 output reg [1:0] quality,fps_request,output reg beauty
);
 reg [1:0] sync3,sync4,sync2;reg stable2,request2;reg [31:0] count2;
 reg stable3,stable4;
 reg [31:0] count3,count4;
 reg [1:0] req3,req4;
 always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
 sync2<=3;stable2<=1;request2<=0;count2<=0;beauty<=0;sync3<=3;sync4<=3;stable3<=1;stable4<=1;count3<=0;count4<=0;req3<=0;req4<=0;quality<=0;fps_request<=0;
 end else begin
 sync2<={sync2[0],k2_n};
 if(sync2[1]==stable2)count2<=0;
 else if(count2==DEBOUNCE_CYCLES-1)begin stable2<=sync2[1];count2<=0;if(!sync2[1])request2<=!request2;end else count2<=count2+1'b1;
 sync3<={sync3[0],k3_n};sync4<={sync4[0],k4_n};
 if(sync3[1]==stable3)count3<=0;
 else if(count3==DEBOUNCE_CYCLES-1) begin
 stable3<=sync3[1];count3<=0;if(!sync3[1])req3<=(req3==2)?0:req3+1'b1;
 end else count3<=count3+1'b1;
 if(sync4[1]==stable4)count4<=0;
 else if(count4==DEBOUNCE_CYCLES-1) begin
 stable4<=sync4[1];count4<=0;if(!sync4[1])req4<=(req4==2)?0:req4+1'b1;
 end else count4<=count4+1'b1;
 if(frame_start)begin beauty<=request2;quality<=req4;fps_request<=req3;end
 end
 end
endmodule

// Single/double/long button actions. Millisecond counters avoid wide debounce trees.
module advanced_controls_pro #(parameter CLK_HZ=74250000,DEBOUNCE_MS=20,LONG_MS=1200,DOUBLE_MS=350)(
 input wire clk,rst_n,k2_n,k3_n,k4_n,frame_start,
 output reg[1:0] quality,fps_request,beauty_mode,
 output wire beauty,output reg calibrate,photo_request,output reg face_track,input wire lock,output wire ms_tick
);
 localparam DIV=CLK_HZ/1000;
 reg[16:0] tick_count;wire ms=tick_count==DIV-1;
 assign ms_tick=ms;
 reg[2:0] sync0,sync1,stable;reg[4:0] debounce[0:2];
 reg[10:0] held[0:2];reg[2:0] fired;
 reg pending;reg[8:0] double_wait;
 reg[1:0] q_req,f_req,b_req;integer i;
 assign beauty=beauty_mode!=0;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 tick_count<=0;sync0<=7;sync1<=7;stable<=7;fired<=0;pending<=0;double_wait<=0;
 quality<=0;fps_request<=0;beauty_mode<=0;q_req<=0;f_req<=0;b_req<=0;calibrate<=0;photo_request<=0;face_track<=0;
 for(i=0;i<3;i=i+1)begin debounce[i]<=0;held[i]<=0;end
 end else begin
 calibrate<=0;photo_request<=0;
 sync0<={k4_n,k3_n,k2_n};sync1<=sync0;
 tick_count<=ms?0:tick_count+1'b1;
 if(frame_start)begin quality<=q_req;fps_request<=f_req;beauty_mode<=b_req;end
 if(lock)begin
 pending<=0;double_wait<=0;stable<=7;sync0<=7;sync1<=7;fired<=7;face_track<=0;
 for(i=0;i<3;i=i+1)begin debounce[i]<=0;held[i]<=0;end
 end else if(ms)begin
  if(pending)begin
   if(double_wait>=DOUBLE_MS-1)begin pending<=0;b_req<=(b_req==1)?0:1;end
   else double_wait<=double_wait+1'b1;
  end
  for(i=0;i<3;i=i+1)begin
   if(sync1[i]==stable[i])debounce[i]<=0;
   else if(debounce[i]>=DEBOUNCE_MS-1)begin
    stable[i]<=sync1[i];debounce[i]<=0;
    if(!sync1[i])begin held[i]<=0;fired[i]<=0;end
    else if(!fired[i])begin
     if(i==0)begin
      if(pending && double_wait<DOUBLE_MS)begin pending<=0;b_req<=2;end
      else begin pending<=1;double_wait<=0;end
     end else if(i==1)f_req<=f_req==2?0:f_req+1'b1;
     else q_req<=q_req==2?0:q_req+1'b1;
    end
   end else debounce[i]<=debounce[i]+1'b1;
   if(!stable[i] && !fired[i])begin
    if(held[i]>=LONG_MS-1)begin
     fired[i]<=1;
     if(i==0)begin calibrate<=1;b_req<=2;pending<=0;end
     else if(i==1)photo_request<=1;
     else face_track<=!face_track;
    end else held[i]<=held[i]+1'b1;
   end
  end
 end
 end end
endmodule
