module servo_pwm_telemetry #(parameter CLK_HZ=74250000)(
 input wire clk,rst_n,video_vs,pan_pwm,tilt_pwm,
 output wire[19:0] pan_hz_bcd,tilt_hz_bcd,pan_duty_bcd,tilt_duty_bcd
);
 wire[7:0] ph,th;wire[9:0] pd,td;wire[10:0] pw,tw;
 reg vs_d;always @(posedge clk or negedge rst_n)if(!rst_n)vs_d<=0;else vs_d<=video_vs;
 wire start=video_vs&&!vs_d;
 pwm_signal_monitor #(.CLK_HZ(CLK_HZ)) p(clk,rst_n,pan_pwm,ph,pd,pw);
 pwm_signal_monitor #(.CLK_HZ(CLK_HZ)) t(clk,rst_n,tilt_pwm,th,td,tw);
 motor_decimal a(clk,rst_n,start,{8'd0,ph},pan_hz_bcd);
 motor_decimal b(clk,rst_n,start,{8'd0,th},tilt_hz_bcd);
 motor_decimal c(clk,rst_n,start,{6'd0,pd},pan_duty_bcd);
 motor_decimal d(clk,rst_n,start,{6'd0,td},tilt_duty_bcd);
endmodule
// Decimal conversion runs over 16 clocks, well outside the pixel critical path.
module motor_decimal(input wire clk,rst_n,start,input wire [15:0] value,output reg [19:0] bcd);
 reg [35:0] work,next;reg [4:0] left;integer i;
 always @*begin
  next=work;
  for(i=0;i<5;i=i+1)if(next[16+i*4+:4]>=5)next[16+i*4+:4]=next[16+i*4+:4]+4'd3;
  next=next<<1;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin work<=0;left<=0;bcd<=0;end
  else if(start && left==0)begin work<={20'd0,value};left<=16;end
  else if(left!=0)begin work<=next;left<=left-1'b1;if(left==1)bcd<=next[35:16];end
 end
endmodule


module pwm_signal_monitor #(parameter CLK_HZ=74250000)(
 input wire clk,rst_n,pwm,
 output reg [7:0] hz,output reg [9:0] duty_x100,output reg [10:0] width_us
);
 localparam TICKS=CLK_HZ/1000000;
 localparam FRACTION_QUARTERS=(CLK_HZ%1000000)/250000;
 reg [1:0] tick_quarter;
 reg [6:0] tick;
 wire tick_end=(tick==TICKS-1+((tick_quarter+FRACTION_QUARTERS)>=4));reg [19:0] second_us,high_total;
 reg [14:0] pulse_us;reg [7:0] rising_count;reg pwm_d;
 // Divide the one-second high time by 100 over 20 clocks. Keeping the
 // division out of the PWM comparison path preserves the 75 MHz timing.
 reg [19:0] dividend;reg [6:0] remainder;reg [9:0] quotient;
 reg [4:0] division_left;
 wire [7:0] shifted_remainder={remainder,dividend[19]};
 wire subtract_100=shifted_remainder>=8'd100;
 wire rise=pwm && !pwm_d;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin tick<=0;tick_quarter<=0;second_us<=0;high_total<=0;pulse_us<=0;rising_count<=0;pwm_d<=0;hz<=0;duty_x100<=0;width_us<=0;dividend<=0;remainder<=0;quotient<=0;division_left<=0;end
  else begin
   if(division_left!=0)begin
    dividend<=dividend<<1;
    remainder<=subtract_100?shifted_remainder-8'd100:shifted_remainder;
    quotient<={quotient[8:0],subtract_100};division_left<=division_left-1'b1;
    if(division_left==1)duty_x100<={quotient[8:0],subtract_100};
   end
   pwm_d<=pwm;
   if(rise)begin rising_count<=rising_count+1'b1;pulse_us<=0;end
   if(!pwm && pwm_d)width_us<=pulse_us;
   if(tick_end)begin
    tick<=0;tick_quarter<=tick_quarter+FRACTION_QUARTERS;
    if(pwm)pulse_us<=rise?15'd1:pulse_us+1'b1;
    if(second_us==999999)begin
     second_us<=0;hz<=rising_count+rise;rising_count<=0;
     dividend<=high_total+pwm;remainder<=0;quotient<=0;division_left<=20;high_total<=0;
    end else begin second_us<=second_us+1'b1;if(pwm)high_total<=high_total+1'b1;end
   end else tick<=tick+1'b1;
  end
 end
endmodule
