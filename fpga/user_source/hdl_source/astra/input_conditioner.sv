// Same median5/median3 arithmetic as the reference, retimed by THREE clocks.
// Split pair sort -> extrema -> median, avoiding a long comparator chain before ERAM.
// Every input control, coordinate and timing flag follows the same three clocks.
module input_conditioner #(parameter WIDTH=1280)(
 input wire clk,rst_n,input wire [4:0] timing,input wire [11:0] x,y,
 input wire [23:0] rgb,input wire [1:0] quality,input wire beauty,
 input wire [7:0] mean,
 output wire [4:0] out_timing,output wire [11:0] out_x,out_y,output wire [23:0] out_rgb,
 input wire [1:0] correction_mode,input wire calibration_valid,freeze,
 input wire [3:0] saturation_level
);
 function [7:0] med3;input[7:0]a,b,c;
 begin med3=(a>b)?((b>c)?b:((a>c)?c:a)):((a>c)?a:((b>c)?c:b));end endfunction
 reg[23:0] left1,left2,left3,left4;
 reg[23:0] lo_ab,hi_ab,lo_cd,hi_cd,last_h1,raw_h1,small_h1;
 reg[23:0] lo_max,hi_min,last_h2,raw_h2,small_h2,filtered_h3;
 reg[35:0] control[0:2];integer c,i;
 wire[4:0]ct;wire[11:0]cx,cy;wire[1:0]cq,cm;wire cb,cv,cf;
 assign {ct,cx,cy,cq,cb,cm,cv,cf}=control[2];
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 left1<=0;left2<=0;left3<=0;left4<=0;lo_ab<=0;hi_ab<=0;lo_cd<=0;hi_cd<=0;
 last_h1<=0;raw_h1<=0;small_h1<=0;lo_max<=0;hi_min<=0;last_h2<=0;raw_h2<=0;small_h2<=0;filtered_h3<=0;
 for(i=0;i<3;i=i+1)control[i]<=0;
 end else begin
 if(timing[2])begin left1<=rgb;left2<=left1;left3<=left2;left4<=left3;end
 control[0]<={timing,x,y,quality,beauty,correction_mode,calibration_valid,freeze};
 control[1]<=control[0];control[2]<=control[1];
 raw_h1<=rgb;last_h1<=left4;raw_h2<=raw_h1;last_h2<=last_h1;small_h2<=small_h1;
 for(c=0;c<3;c=c+1)begin
 lo_ab[c*8+:8]<=rgb[c*8+:8]>left1[c*8+:8]?left1[c*8+:8]:rgb[c*8+:8];
 hi_ab[c*8+:8]<=rgb[c*8+:8]>left1[c*8+:8]?rgb[c*8+:8]:left1[c*8+:8];
 lo_cd[c*8+:8]<=left2[c*8+:8]>left3[c*8+:8]?left3[c*8+:8]:left2[c*8+:8];
 hi_cd[c*8+:8]<=left2[c*8+:8]>left3[c*8+:8]?left2[c*8+:8]:left3[c*8+:8];
 small_h1[c*8+:8]<=med3(rgb[c*8+:8],left1[c*8+:8],left2[c*8+:8]);
 lo_max[c*8+:8]<=lo_ab[c*8+:8]>lo_cd[c*8+:8]?lo_ab[c*8+:8]:lo_cd[c*8+:8];
 hi_min[c*8+:8]<=hi_ab[c*8+:8]<hi_cd[c*8+:8]?hi_ab[c*8+:8]:hi_cd[c*8+:8];
 filtered_h3[c*8+:8]<=!control[1][4]?raw_h2[c*8+:8]:
   control[1][30:19]>=4?med3(lo_max[c*8+:8],hi_min[c*8+:8],last_h2[c*8+:8]):
   control[1][30:19]>=2?small_h2[c*8+:8]:raw_h2[c*8+:8];
 end
 end end
 input_conditioner_core #(.WIDTH(WIDTH)) core(
 .clk(clk),.rst_n(rst_n),.timing(ct),.x(cx),.y(cy),.rgb(raw_h2),.filtered(filtered_h3),
 .quality(cq),.beauty(cb),.mean(mean),.out_timing(out_timing),.out_x(out_x),.out_y(out_y),.out_rgb(out_rgb),
 .correction_mode(cm),.calibration_valid(cv),.freeze(cf),.saturation_level(saturation_level));
endmodule
// Four-clock raster pipeline with registered denoise/tone boundary. Effective-resolution selection precedes all modes.
module input_conditioner_core #(parameter WIDTH=1280)(
 input wire clk,rst_n,input wire [4:0] timing,input wire [11:0] x,y,
 input wire [23:0] rgb,filtered,input wire [1:0] quality,input wire beauty,
 input wire [7:0] mean,
 output reg [4:0] out_timing,output reg [11:0] out_x,out_y,output reg [23:0] out_rgb,
 input wire [1:0] correction_mode,input wire calibration_valid,freeze,
 input wire [3:0] saturation_level
);
 function [7:0] median3;
 input [7:0] a,b,c;
 begin median3=(a>b)?((b>c)?b:((a>c)?c:a)):((a>c)?a:((b>c)?c:b));end
 endfunction
 function [7:0] median5;
 input [7:0] a,b,c,d,e;
 reg [7:0] low_ab,high_ab,low_cd,high_cd,middle1,middle2;reg ab,cd;
 begin
 ab=a>b;cd=c>d;
 low_ab=ab?b:a;high_ab=ab?a:b;
 low_cd=cd?d:c;high_cd=cd?c:d;
 middle1=(low_ab>low_cd)?low_ab:low_cd;
 middle2=(high_ab<high_cd)?high_ab:high_cd;
 median5=median3(middle1,middle2,e);
 end endfunction
 // Average low-contrast neighborhoods; preserve boundaries with a median.
 function [7:0] denoise3;
 input [7:0] a,b,c;reg [7:0] hi,lo;reg [10:0] total;reg ab;
 begin ab=a>b;hi=ab?a:b;if(c>hi)hi=c;lo=ab?b:a;if(c<lo)lo=c;
 total={3'b0,a}+{1'b0,b,2'b0}+{2'b0,b,1'b0}+{3'b0,c}+11'd4;
 denoise3=(hi-lo<=32)?total[10:3]:median3(a,b,c);end
 endfunction
 function [7:0] tone;
 input [7:0] v;input [7:0] grey;input signed [9:0] delta;input signed [9:0] detail;input [3:0] strength;
 reg signed [11:0] z,d;
 begin
 d=$signed({1'b0,v})-$signed({1'b0,grey});
 // Modest chroma/contrast preserves color identity instead of amplifying tint.
 if(d>2)d=d-2;else if(d< -2)d=d+2;else d=0;
 // Quarter-step chroma gain shares the existing tone/sharpen stage. No DSP.
 case(strength)
 0:d=0;1:d=d>>>2;2:d=d>>>1;3:d=d-(d>>>2);
 4:d=d;5:d=d+(d>>>2);6:d=d+(d>>>1);
 7:d=d+(d>>>1)+(d>>>2);8:d=d<<<1;
 default:d=d+(d>>>1);
 endcase
 z=$signed({1'b0,grey})+delta+(($signed({1'b0,grey})-12'sd128)>>>4)+12'sd4+d+detail;
 tone=z<0?0:z>255?255:z[7:0];end
 endfunction
 reg [23:0] held,data1,read_pixel;
 localparam ROW_AW=$clog2(WIDTH/2);
 (* ram_style="bram" *) reg [23:0] row_pixels[0:(1<<ROW_AW)-1];
 reg [4:0] t1,t2,t3;reg [11:0] x3,y3;reg b3,tone3;reg [23:0] spatial2,spatial3,center2,selected3;reg [7:0] grey2;reg signed [9:0] delta2;reg [11:0] x1,y1,x2,y2;reg b2;reg [23:0] selected2;
 reg use_row,b1;reg signed[9:0] delta1;
 wire top_row=(quality==1)?!y[0]:(y[1:0]==0);
 wire block_start=(quality==1)?!x[0]:(x[1:0]==0);
 wire [10:0] address=(quality==1)?(x>>1):(x>>2);
 wire [ROW_AW-1:0] row_address=address<WIDTH/2?address[ROW_AW-1:0]:{ROW_AW{1'b0}};
 reg [3:0] strength;
 always @* begin
  case(saturation_level)
   0,1,2,3,4,5,6,7,8:strength=saturation_level;
   default:strength=correction_mode==1?4'd7:correction_mode==2?4'd8:4'd6;
  endcase
 end
 wire [23:0] sample=block_start?filtered:held;
 wire [23:0] selected=use_row?read_pixel:data1;
 reg [23:0] previous_row[0:WIDTH-1],older_row[0:WIDTH-1];
 reg [23:0] previous,older;
 wire [23:0] spatial=(y1>=2)?{denoise3(selected[23:16],previous[23:16],older[23:16]),denoise3(selected[15:8],previous[15:8],older[15:8]),denoise3(selected[7:0],previous[7:0],older[7:0])}:selected;
 function signed [9:0] sharpen;
 input [7:0] center,smooth_pixel;
 reg signed [9:0] e;
 begin e=($signed({1'b0,center})-$signed({1'b0,smooth_pixel}))>>>2;
 // Bound the high-pass; never re-inject salt/pepper rejected by the median.
 sharpen=e>6?10'sd6:e< -6?-10'sd6:e;end endfunction

 // Registered small DSP products replace nine parallel shift/add candidates.
 // Rounding corrections exactly preserve the original signed shift semantics.
 function signed [8:0] chroma; input[7:0] v,g; reg signed[8:0] d;
 begin d=$signed({1'b0,v})-$signed({1'b0,g});
 chroma=d>2?d-9'sd2:d< -2?d+9'sd2:9'sd0;end endfunction
 function signed[3:0] rounding_fix;input signed[8:0] d;input[3:0] gain;
 begin rounding_fix=(gain==3 && d[1:0]!=0)?4'sd1:
                    (gain==7 && d[1:0]==3)?-4'sd1:4'sd0;end endfunction
 function[7:0] finish_tone;input signed[11:0] product;
 input signed[9:0] base;input signed[3:0] detail;reg signed[12:0] z;
 begin z=$signed(base)+($signed(product)>>>2)+$signed(detail);
 finish_tone=z<0?0:z>255?255:z[7:0];end endfunction
 wire signed[8:0] cr=chroma(spatial2[23:16],grey2),
                      cg=chroma(spatial2[15:8],grey2),cb=chroma(spatial2[7:0],grey2);
 reg signed[11:0] prod_r3,prod_g3,prod_b3;
 reg signed[9:0] tone_base3;
 reg signed[3:0] detail_r3,detail_g3,detail_b3;
 wire[23:0] tone_result={finish_tone(prod_r3,tone_base3,detail_r3),
                       finish_tone(prod_g3,tone_base3,detail_g3),
                       finish_tone(prod_b3,tone_base3,detail_b3)};
 wire tone_enable=correction_mode==1 || (correction_mode==2 && calibration_valid);
 wire[9:0] grey_sum={2'd0,spatial[23:16]}+{1'd0,spatial[15:8],1'b0}+{2'd0,spatial[7:0]};
 always @(posedge clk) begin
  if(timing[2] && x<WIDTH)begin previous<=previous_row[x];older<=older_row[x];end
  if(t1[2] && x1<WIDTH)begin previous_row[x1]<=selected;older_row[x1]<=previous;end
 end
 // Memory read and write are synchronous; no reset on storage.
 always @(posedge clk)begin
  read_pixel<=row_pixels[row_address];
  if(timing[2] && quality!=0)begin
   if(top_row && block_start)row_pixels[row_address]<=filtered;
  end
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin held<=0;data1<=0;t1<=0;x1<=0;y1<=0;use_row<=0;b1<=0;delta1<=0;out_timing<=0;out_x<=0;out_y<=0;out_rgb<=0;t2<=0;x2<=0;y2<=0;b2<=0;prod_r3<=0;prod_g3<=0;prod_b3<=0;tone_base3<=0;detail_r3<=0;detail_g3<=0;detail_b3<=0;selected2<=0;t3<=0;x3<=0;y3<=0;b3<=0;tone3<=0;spatial2<=0;spatial3<=0;center2<=0;selected3<=0;grey2<=0;delta2<=0;end
  else begin
   if(timing[2])begin if(block_start)held<=filtered;end
   t1<=timing;x1<=x;y1<=y;b1<=beauty;
   t2<=t1;x2<=x1;y2<=y1;b2<=b1;selected2<=selected;
   spatial2<=spatial;center2<=(y1>=2)?previous:selected;grey2<=grey_sum[9:2];delta2<=delta1;
   t3<=t2;x3<=x2;y3<=y2;b3<=b2;tone3<=tone_enable;selected3<=selected2;spatial3<=spatial2;
   prod_r3<=cr*$signed({1'b0,strength});
   prod_g3<=cg*$signed({1'b0,strength});
   prod_b3<=cb*$signed({1'b0,strength});
   tone_base3<=$signed({1'b0,grey2})+delta2+(($signed({1'b0,grey2})-12'sd128)>>>4)+12'sd4;
   detail_r3<=sharpen(center2[23:16],spatial2[23:16])+rounding_fix(cr,strength);
   detail_g3<=sharpen(center2[15:8],spatial2[15:8])+rounding_fix(cg,strength);
   detail_b3<=sharpen(center2[7:0],spatial2[7:0])+rounding_fix(cb,strength);
   use_row<=quality!=0 && !top_row;
   data1<=(quality==0)?filtered:sample;
   // Real sensor AE + the adaptive histogram perform luminance adaptation.
   // Do not apply a second independent mean-based exposure correction.
   if(!freeze)delta1<=0;
   out_timing<=t3;out_x<=x3;out_y<=y3;
   out_rgb<=b3?(tone3?tone_result:spatial3):selected3;
  end
 end
endmodule

