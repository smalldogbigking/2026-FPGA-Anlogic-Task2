// Independent AUTO/FIXED exposure and sensor gain banks. Fixed white-reference
// calibration adapts for three seconds, then holds. Switching mode restores
// that bank through the normal I2C write handshake; OFF uses the default point.
module ae_set #(parameter CLK_HZ=23809524)(input wire I_clk,I_rst,input wire [3:0] I_btn,
 input wire I_ae_cfg_done,I_cam_cfg_done,input wire [7:0] I_mean,input wire I_mean_toggle,
 output reg O_ae_req,output reg [15:0] O_ae,O_ag,
 input wire [1:0] correction_mode,input wire calibrate,freeze,
 output wire [15:0] exposure_status,output wire [7:0] gain_status,
 input wire external_enable,input wire[15:0] external_exp,input wire[7:0] external_gain);
 reg [7:0] m0,m1,scene;
 reg [2:0] toggle_sync;reg seen,ready,initial_sent;
 reg [22:0] cooldown;reg [26:0] calibration_ticks;
 reg [1:0] applied_mode;
 reg [15:0] auto_ae,auto_ag,fixed_ae,fixed_ag;
 reg [15:0] next_ae,next_ag;
 wire calibrating=calibration_ticks!=0;
 assign exposure_status=O_ae;assign gain_status=O_ag[7:0];
 always @*begin
  next_ae=O_ae;next_ag=O_ag;
  if(scene<112)begin
   if(O_ae<1863)next_ae=O_ae+128;
   else if(O_ae<1991)next_ae=1991;
   else if(O_ag<80)next_ag=O_ag+4;
  end else if(scene>144)begin
   if(O_ag>16)next_ag=O_ag-4;
   else if(O_ae>256)next_ae=O_ae-128;
   else if(O_ae>32)next_ae=O_ae-16;
   else if(O_ae>8)next_ae=O_ae-4;
   else next_ae=4;
  end
 end
 always @(posedge I_clk or posedge I_rst)begin
  if(I_rst)begin
   m0<=128;m1<=128;scene<=128;toggle_sync<=0;seen<=0;ready<=0;cooldown<=0;
   O_ae_req<=0;O_ae<=1991;O_ag<=48;initial_sent<=0;calibration_ticks<=0;
   auto_ae<=1991;auto_ag<=48;fixed_ae<=1991;fixed_ag<=48;applied_mode<=0;
  end else begin
   m0<=I_mean;m1<=m0;toggle_sync<={toggle_sync[1:0],I_mean_toggle};O_ae_req<=0;
   if(toggle_sync[2]!=seen)begin seen<=toggle_sync[2];scene<=m1;ready<=1;end
   if(!freeze)begin
    if(calibrate)begin
     calibration_ticks<=CLK_HZ*3;fixed_ae<=O_ae;fixed_ag<=O_ag;
    end else if(calibrating)calibration_ticks<=calibration_ticks-1'b1;
    if(!I_cam_cfg_done)begin cooldown<=0;initial_sent<=0;end
    else if(cooldown<((calibrating)?CLK_HZ/8:CLK_HZ/4))cooldown<=cooldown+1'b1;
    else if(I_ae_cfg_done && !calibrate)begin
     cooldown<=0;
     if(!initial_sent)begin
      // Wait for camera table completion before sending the low-noise point.
      O_ae<=1991;O_ag<=48;O_ae_req<=1;initial_sent<=1;applied_mode<=0;
     end else if(calibrating)begin
      applied_mode<=2;
      if(ready)begin
       O_ae<=next_ae;O_ag<=next_ag;fixed_ae<=next_ae;fixed_ag<=next_ag;
       if(next_ae!=O_ae || next_ag!=O_ag)O_ae_req<=1;
      end
     end else if(external_enable)begin
      applied_mode<=3;O_ae<=external_exp;O_ag<={8'd0,external_gain};
      if(O_ae!=external_exp||O_ag!={8'd0,external_gain})O_ae_req<=1;
     end else if(applied_mode!=correction_mode)begin
      // Output registers remain stable throughout an in-flight I2C update.
      O_ae<=correction_mode==1?auto_ae:correction_mode==2?fixed_ae:16'd1991;
      O_ag<=correction_mode==1?auto_ag:correction_mode==2?fixed_ag:16'd48;
      O_ae_req<=1;applied_mode<=correction_mode;
     end else if(ready && correction_mode==1)begin
      O_ae<=next_ae;O_ag<=next_ag;auto_ae<=next_ae;auto_ag<=next_ag;
      if(next_ae!=O_ae || next_ag!=O_ag)O_ae_req<=1;
     end
    end
   end
  end
 end
endmodule
