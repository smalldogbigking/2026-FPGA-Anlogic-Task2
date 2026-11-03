// Scene-adaptive clipped histogram equalization, bounded +/-24 with a brightness deadband.
// Clip limit follows valid sample count, tone strength follows occupied-bin span.
// Sequential divider runs in vertical blanking, never in the pixel path.
module histogram_curve_pro(input wire clk,rst_n,start,input wire [191:0] histogram,output reg [127:0] offsets);
 reg [3:0] state;reg [23:0] weighted;reg [7:0] scene_mean;reg signed [8:0] bias;reg [3:0] idx;reg [15:0] total,limited,cdf,redistribute;
 reg [11:0] clip_limit;reg [3:0] lo_bin,hi_bin;reg have_bin;
 reg launch;reg [23:0] numerator,denominator;wire done;wire [23:0] quotient;
 reg [11:0] count;integer i,j;reg signed [8:0] target,prior;
 always @*begin
  count=0;
  for(j=0;j<16;j=j+1)if(idx==j)count=histogram[j*12+:12];
 end
 wire [11:0] capped=(count>clip_limit)?clip_limit:count;
 udiv24 divide(clk,rst_n,launch,numerator,denominator,done,quotient);
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin state<=0;weighted<=0;scene_mean<=128;idx<=0;total<=0;limited<=0;cdf<=0;redistribute<=0;launch<=0;numerator<=0;denominator<=1;offsets<=0;clip_limit<=384;lo_bin<=0;hi_bin<=15;have_bin<=0;end
 else begin
  launch<=0;
  case(state)
   0:if(start)begin weighted<=0;idx<=0;total<=0;limited<=0;have_bin<=0;lo_bin<=0;hi_bin<=15;state<=1;end
   1:begin total<=total+count;weighted<=weighted+(count*( {1'b0,idx,4'b0}+9'd8));
    if(count>=24)begin if(!have_bin)lo_bin<=idx;hi_bin<=idx;have_bin<=1;end
    if(idx==15)state<=7;else idx<=idx+1'b1;end
   7:begin numerator<=weighted;denominator<=total==0?1:total;launch<=1;state<=8;end
   8:if(done)begin scene_mean<=quotient[7:0];state<=2;end
   2:begin clip_limit<=(total>>3)>512?12'd512:((total>>3)<80?12'd80:(total>>3));
    limited<=0;idx<=0;state<=5;end
   5:begin limited<=limited+capped;if(idx==15)state<=6;else idx<=idx+1'b1;end
   6:begin redistribute<=(total-limited)>>4;denominator<=(limited+((total-limited)&16'hfff0))==0?16'd1:limited+((total-limited)&16'hfff0);cdf<=0;idx<=0;state<=3;end
   3:begin numerator<=({8'b0,cdf}<<8)-cdf;launch<=1;cdf<=cdf+capped+redistribute;state<=4;end
   4:if(done)begin
    target=($signed({1'b0,quotient[7:0]})-$signed({1'b0,idx,4'b0}))>>>((have_bin && hi_bin-lo_bin<=5)?1:((have_bin && hi_bin-lo_bin>=12)?3:2));
    // Histogram-dependent bidirectional correction; never a fixed curve.
    if(target>8)target=8;if(target< -8)target=-8;
    bias=scene_mean<120?(120-$signed({1'b0,scene_mean}))>>>2:scene_mean>136?(136-$signed({1'b0,scene_mean}))>>>2:0;
    if(bias>24)bias=24;if(bias< -24)bias=-24;
    target=target+bias;
    if(scene_mean<112 && target<0)target=0;
    if(scene_mean>160 && target>0)target=0;
    if(target>24)target=24;if(target< -24)target=-24;
    // Keep the endpoint knots monotone when exposure lift exceeds one bin.
    // target is already bounded to +/-24. Only the knots adjacent to
    // the endpoints can cross their endpoint; all other knots have >=32
    // codes of headroom. This is exactly the old idx*16 clamp.
    if(idx==1 && target< -16)target= -16;
    if(idx==14 && target>16)target=16;
    if(idx==0 || idx==15 || total<64)target=0;
    prior=$signed(offsets[idx*8+:8]);
    // Slew bound: no scene cut can change the tone correction by >2/frame.
    if(target>prior+2)target=prior+2;if(target<prior-2)target=prior-2;
    offsets[idx*8+:8]<=target;
    if(idx==15)state<=0;else begin idx<=idx+1'b1;state<=3;end
   end
   default:state<=0;
  endcase
 end end
endmodule

// Histogram of actual K2 output (after the spatial denoiser), before modes/OSD.
// One read/modify/write RAM shares the sparse 16x16 sampling interval.
// Histogram publication takes sixteen blanking clocks after EOF; OSD captures
// it at the following SOF, so video timing and displayed bins are unchanged.
module beauty_hist_pro #(parameter WIDTH=1280,HEIGHT=720)(input wire clk,rst_n,valid,sof,input wire [11:0] x,y,input wire [23:0] rgb,output reg [191:0] histogram);
 (* ram_style="bram" *) reg[11:0] counts[0:15];reg[11:0] read_count;
 reg[15:0] seen;reg write_count,was_seen,busy;reg[3:0] write_addr;reg[4:0] scan;
 wire[9:0] s={2'b0,rgb[23:16]}+{1'b0,rgb[15:8],1'b0}+{2'b0,rgb[7:0]};
 wire sample=valid && !sof && x[3:0]==0 && y[3:0]==0 && !busy;
 wire eof=valid && x==WIDTH-1 && y==HEIGHT-1;
 wire[3:0] addr=eof?4'd0:busy?(scan[3:0]+4'd1):s[9:6];
 always @(posedge clk)begin
  read_count<=counts[addr];
  if(write_count)counts[write_addr]<=was_seen?read_count+12'd1:12'd1;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin histogram<=0;seen<=0;write_count<=0;write_addr<=0;was_seen<=0;busy<=0;scan<=0;end
  else begin
   write_count<=sample;write_addr<=s[9:6];was_seen<=seen[s[9:6]];
   if(sof)begin seen<=0;busy<=0;write_count<=0;end
   else if(sample)seen[s[9:6]]<=1;
   if(eof)begin busy<=1;scan<=0;end
   else if(busy)begin
    histogram[scan[3:0]*12+:12]<=seen[scan[3:0]]?read_count:12'd0;
    if(scan==15)busy<=0;else scan<=scan+1'b1;
   end
  end
 end
endmodule
