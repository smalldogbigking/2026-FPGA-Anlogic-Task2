// Same pixel clock as target metadata. 20 ms PWM, 1000..2000 us limits.
// Directions depend on the pan/tilt mount; change parameters, not wiring.
module servo_tracker_v11 #(parameter CLK_HZ=74250000,REVERSE_PAN=0,REVERSE_TILT=1)(
 input wire clk,rst_n,enable,frame_start,target_valid,
 input wire [47:0] box,
 output reg pan_pwm,tilt_pwm,output reg [10:0] pan_us,tilt_us
);
 localparam TICKS=CLK_HZ/1000000;
 localparam FRACTION_QUARTERS=(CLK_HZ%1000000)/250000;
 reg [1:0] tick_quarter;
 reg [6:0] tick;
 wire tick_end=(tick==TICKS-1+((tick_quarter+FRACTION_QUARTERS)>=4));reg [14:0] period;reg [10:0] active_pan,active_tilt;
 reg [1:0] frames;reg active_enable;
 wire [12:0] sumx={1'b0,box[47:36]}+{1'b0,box[35:24]};
 wire [12:0] sumy={1'b0,box[23:12]}+{1'b0,box[11:0]};
 wire signed [13:0] ex=$signed({1'b0,sumx[12:1]})-14'sd640;
 wire signed [13:0] ey=$signed({1'b0,sumy[12:1]})-14'sd360;
 reg signed [13:0] step_x,step_y,next_x,next_y;
 always @* begin
  step_x=(ex>16 || ex< -16)?(ex>>>5):0;
  step_y=(ey>12 || ey< -12)?(ey>>>5):0;
  if(step_x>8)step_x=8;if(step_x< -8)step_x=-8;
  if(step_y>8)step_y=8;if(step_y< -8)step_y=-8;
  next_x=$signed({1'b0,pan_us})+(REVERSE_PAN?-step_x:step_x);
  next_y=$signed({1'b0,tilt_us})+(REVERSE_TILT?-step_y:step_y);
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin tick<=0;tick_quarter<=0;period<=0;pan_us<=1500;tilt_us<=1500;active_pan<=1500;active_tilt<=1500;pan_pwm<=0;tilt_pwm<=0;frames<=0;active_enable<=0;end
  else begin
   // Frame-atomic position update; hold the last command when target is lost.
   if(frame_start)begin
    frames<=frames+1'b1;
    if(enable && target_valid && frames==0)begin
     pan_us<=(next_x<1000)?1000:(next_x>2000)?2000:next_x[10:0];
     tilt_us<=(next_y<1000)?1000:(next_y>2000)?2000:next_y[10:0];
    end
   end
   if(tick_end)begin
    tick<=0;tick_quarter<=tick_quarter+FRACTION_QUARTERS;
    if(period==19999)begin period<=0;active_enable<=enable;active_pan<=pan_us;active_tilt<=tilt_us;end
    else period<=period+1'b1;
   end else tick<=tick+1'b1;
   // Disabling tracking removes pulses. Pulse widths latch at period start.
   pan_pwm<=active_enable && period<active_pan;
   tilt_pwm<=active_enable && period<active_tilt;
  end
 end
endmodule

// Three-second neutral positioning on each RED/FACE tracking entry.
module servo_tracker_pro #(parameter CLK_HZ=74250000,REVERSE_PAN=0,REVERSE_TILT=1)(
 input wire clk,rst_n,enable,face_source,frame_start,target_valid,input wire[47:0] box,
 input wire target_update,input wire[7:0] target_age,
 output reg pan_pwm,tilt_pwm,output reg[10:0] pan_us,tilt_us,
 output wire ready,output wire[1:0] center_seconds,
 input wire manual_enable,input wire[10:0] manual_pan_us,manual_tilt_us
);
 localparam TICKS=CLK_HZ/1000000;
 localparam FRACTION_QUARTERS=(CLK_HZ%1000000)/250000;
 reg [1:0] tick_quarter;
 reg[6:0] tick;
 wire tick_end=(tick==TICKS-1+((tick_quarter+FRACTION_QUARTERS)>=4));reg[14:0] period;reg[7:0] homing;
 reg was_enabled,was_face,active_enable;reg[10:0] active_pan,active_tilt;
 wire entry=enable && (!was_enabled || face_source!=was_face);
 wire[12:0] sx={1'b0,box[47:36]}+{1'b0,box[35:24]},sy={1'b0,box[23:12]}+{1'b0,box[11:0]};
 wire signed[10:0] ex=$signed({1'b0,sx[11:1]})-12'sd640,ey=$signed({1'b0,sy[10:1]})-11'sd360;
 reg signed[10:0] prev_x,prev_y;
 reg signed[8:0] velocity_x,velocity_y;
 reg signed[5:0] last_dx,last_dy;
 reg have_sample;
 // Snapshot each NEW detector observation once (RED: one frame, FACE: one scan). One shared arithmetic path
 // evaluates X then Y in 24 pixel clocks (<0.4us at 75MHz), instead of chaining
 // center/delta/filter/prediction/slew/position through a single 13.33ns path.
 // Missing updates HOLD position; stale display boxes never integrate again.
 // Both commands commit
 // together. PWM period and pulse-width latches remain independent.
 reg[3:0] phase;reg axis;
 reg signed[10:0] sample_x,sample_y,work_error;
 reg signed[12:0] work_math;
 reg signed[8:0] pending_velocity;
 reg signed[5:0] work_step;
 reg work_jump;reg[10:0] pending_pan;
 wire signed[10:0] sample_sel=axis?sample_y:sample_x;
 wire signed[10:0] previous_sel=axis?prev_y:prev_x;
 wire signed[8:0] velocity_sel=axis?velocity_y:velocity_x;
 wire signed[5:0] last_sel=axis?last_dy:last_dx;
 wire[10:0] pulse_sel=axis?tilt_us:pan_us;
 wire reverse_sel=axis?REVERSE_TILT:REVERSE_PAN;
 wire signed[12:0] deadzone=axis?13'sd16:13'sd20;
 wire signed[12:0] jump_limit=axis?13'sd120:13'sd160;
 wire signed[12:0] step_ext={{7{work_step[5]}},work_step};
 reg[10:0] goal_pan,goal_tilt;
 reg[2:0] sample_span;
 reg signed[12:0] budget_step;
 always @* begin
  case(sample_span)
   2:budget_step=step_ext<<<1;
   3:budget_step=(step_ext<<<1)+step_ext;
   4:budget_step=step_ext<<<2;
   5:budget_step=(step_ext<<<2)+step_ext;
   6:budget_step=(step_ext<<<2)+(step_ext<<<1);
   default:budget_step=step_ext;
  endcase
  if(face_source && work_error<=192 && work_error>=-192)
   budget_step=(work_error>96 || work_error< -96)?(step_ext<<<1):step_ext;
  if(!face_source)budget_step=step_ext;
 end
 reg[7:0] frames_since_update;
 wire fresh_observation=target_update && (!face_source || target_age<=15);
 wire[10:0] clamped_pulse=work_math<13'sd1000 ? 11'd1000 :
                         work_math>13'sd2000 ? 11'd2000 :work_math[10:0];
 assign ready=enable && homing==0 && !entry;
 assign center_seconds=(homing>100)?3:(homing>50)?2:(homing>0)?1:0;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 tick<=0;tick_quarter<=0;period<=0;homing<=0;was_enabled<=0;was_face<=0;active_enable<=0;
 active_pan<=1500;active_tilt<=1500;pan_us<=1500;tilt_us<=1500;
 pan_pwm<=0;tilt_pwm<=0;prev_x<=0;prev_y<=0;
 velocity_x<=0;velocity_y<=0;last_dx<=0;last_dy<=0;have_sample<=0;
 phase<=0;axis<=0;sample_x<=0;sample_y<=0;work_error<=0;work_math<=0;
 pending_velocity<=0;work_step<=0;work_jump<=0;pending_pan<=1500;frames_since_update<=255;
 goal_pan<=1500;goal_tilt<=1500;sample_span<=1;
 end else begin
 was_enabled<=enable;was_face<=face_source;
 if(frame_start && frames_since_update!=255)frames_since_update<=frames_since_update+1'b1;
 if(entry)begin
 goal_pan<=1500;goal_tilt<=1500;
 homing<=151;frames_since_update<=255;pan_us<=1500;tilt_us<=1500;phase<=0;
 have_sample<=0;velocity_x<=0;velocity_y<=0;last_dx<=0;last_dy<=0;
 end else if(!enable || manual_enable)begin
 goal_pan<=pan_us;goal_tilt<=tilt_us;
 phase<=0;have_sample<=0;velocity_x<=0;velocity_y<=0;last_dx<=0;last_dy<=0;
 end else if(phase==0)begin
  if(!target_valid || frames_since_update>=30)begin
   have_sample<=0;velocity_x<=0;velocity_y<=0;last_dx<=0;last_dy<=0;
  end
  if(ready && target_valid && fresh_observation)begin
   sample_x<=ex;sample_y<=ey;axis<=0;phase<=1;frames_since_update<=0;
   sample_span<=frames_since_update>=5?3'd6:frames_since_update[2:0]+3'd1;
  end
 end else begin
  case(phase)
   1:begin work_error<=sample_sel;work_math<=$signed(sample_sel)-$signed(previous_sel);phase<=2;end
   2:begin
    work_jump<=!have_sample || work_math>jump_limit || work_math< -jump_limit;
    work_math<=work_math-$signed(velocity_sel);phase<=3;
   end
   3:begin // Round the 1/4 residual away from zero so velocity decays fully.
    if(face_source)work_math<=work_math>=0?((work_math+13'sd1)>>>1):-((-work_math+13'sd1)>>>1);
    else work_math<=work_math>=0?((work_math+13'sd3)>>>2):-((-work_math+13'sd3)>>>2);phase<=4;
   end
   4:begin work_math<=work_jump?13'sd0:work_math+$signed(velocity_sel);phase<=5;end
   5:begin pending_velocity<=work_math[8:0];
    // FACE has capture/scan/actuator delay; the larger finite motion budget
    // requires earlier braking. Prediction is in observation-interval units.
    work_math<=face_source?((sample_span<=2)?(work_math<<<4):
      (sample_span<=4)?(work_math<<<3):((work_math<<<2)+(work_math<<<1))):(work_math<<<4);phase<=6;end
   6:begin
    if(face_source && ((work_error>=0 && work_math>=0)||(work_error<=0 && work_math<=0)))work_math<=work_error;
    else work_math<=work_math+$signed(work_error);phase<=7;
   end
   7:begin // Gain schedule on predicted error: faster far away, /64 nearby.
    // No inter-measurement integration; velocity prediction brakes on approach.
    if(work_math>192 || work_math< -192)
     work_step<=work_math>=384?6'sd12:work_math<=-384?-6'sd12:
      ((work_math>>>5)+((work_math<0 && |work_math[4:0])?13'sd1:13'sd0));
    else work_step<=((work_math>>>6)+((work_math<0 && |work_math[5:0])?13'sd1:13'sd0));phase<=8;
   end
   8:begin
    if(work_step>6'sd8)work_step<=6'sd8;
    else if(work_step< -6'sd8)work_step<=-6'sd8;
    else if(work_step==0 && work_math>deadzone)work_step<=6'sd1;
    else if(work_step==0 && work_math< -deadzone)work_step<=-6'sd1;
    phase<=9;
   end
   9:begin
    if(work_step>last_sel+6'sd2)work_step<=last_sel+6'sd2;
    else if(work_step<last_sel-6'sd2)work_step<=last_sel-6'sd2;
    // Braking is immediate: acceleration is limited, deceleration is not.
    if((last_sel>0 && work_step>=0 && work_step<last_sel) ||
       (last_sel<0 && work_step<=0 && work_step>last_sel))work_step<=work_step;
    phase<=10;
   end
   10:begin
    if(work_jump || ($signed(work_error)<=deadzone && $signed(work_error)>=-deadzone) ||
       (work_error>0 && work_math<=0) || (work_error<0 && work_math>=0) ||
       (work_error>0 && work_step<0) || (work_error<0 && work_step>0))work_step<=0;
    phase<=11;
   end
   11:begin work_math<=$signed({2'b0,pulse_sel})+(reverse_sel?-budget_step:budget_step);phase<=12;end
   12:begin
    if(!axis)begin
     pending_pan<=clamped_pulse;prev_x<=work_error;
     velocity_x<=pending_velocity;last_dx<=work_step;axis<=1;phase<=1;
    end else begin
     if(face_source)begin goal_pan<=pending_pan;goal_tilt<=clamped_pulse;end
     else begin pan_us<=pending_pan;tilt_us<=clamped_pulse;end
     prev_y<=work_error;
     velocity_y<=pending_velocity;last_dy<=work_step;have_sample<=1;phase<=0;
    end
   end
   default:phase<=0;
  endcase
 end
 // A fresh FACE observation authorizes one finite movement budget, scaled by
 // its update interval. Spend it at the RED rate (<=8us/frame), never repeatedly
 // integrate a stale box. New results replace the budget, loss/age stop motion.
 if(frame_start && ready && face_source && !manual_enable)begin
  if(target_valid && have_sample && target_age<=15 && frames_since_update<8)begin
   if(goal_pan>pan_us)pan_us<=goal_pan-pan_us>8?pan_us+11'd8:goal_pan;
   else pan_us<=pan_us-goal_pan>8?pan_us-11'd8:goal_pan;
   if(goal_tilt>tilt_us)tilt_us<=goal_tilt-tilt_us>8?tilt_us+11'd8:goal_tilt;
   else tilt_us<=tilt_us-goal_tilt>8?tilt_us-11'd8:goal_tilt;
  end else begin goal_pan<=pan_us;goal_tilt<=tilt_us;end
 end
 if(tick_end)begin
 tick<=0;tick_quarter<=tick_quarter+FRACTION_QUARTERS;
 if(period==19999)begin
 period<=0;active_enable<=enable;active_pan<=manual_enable?manual_pan_us:pan_us;active_tilt<=manual_enable?manual_tilt_us:tilt_us;
 if(homing>0 && !entry)homing<=homing-1'b1;
 end else period<=period+1'b1;
 end else tick<=tick+1'b1;
 pan_pwm<=active_enable && period<active_pan;tilt_pwm<=active_enable && period<active_tilt;
 end end
endmodule
