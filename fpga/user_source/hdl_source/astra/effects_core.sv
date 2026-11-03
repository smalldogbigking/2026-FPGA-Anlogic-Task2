// Algorithm-level 4-stage pixel pipeline. No ready/backpressure.
// I_window = {p00,p01,p02,p10,p11,p12,p20,p21,p22}; center is p11.
// A beat sampled at edge n appears after edge n+3. Metadata follows RGB.
module effects_core #(parameter WIDTH=1280,HEIGHT=720,PRECOMPUTED=0)(
 input wire clk,rst_n,valid,sof,eol,
 input wire [11:0] x,y,
 input wire [3:0] mode,
 input wire [1:0] quality,
 input wire [7:0] frame_mean,
 input wire [7:0] binary_t,edge_t,heat_lo,heat_hi,
 input wire [215:0] window_rgb,
 output reg out_valid,out_sof,out_eol,
 output reg [11:0] out_x,out_y,
 output reg [3:0] out_mode,
 output reg [23:0] out_rgb,
 output reg red_hit,green_hit,edge_hit,output reg[4:0] red_perimeter,green_perimeter,
 input wire[71:0] window_luma,input wire[17:0] window_red
);
 `include "pixel_math.vh"

 // One synchronous palette ERAM. Contents evaluated at elaboration only;
 // no runtime RGB desaturation arithmetic or 35-way constant mux.
 (* rom_style="bram" *) reg[23:0] cartoon_palette_rom[0:127];
 reg[23:0] cartoon_rgb3;reg cartoon_grey3;integer palette_index;
 initial begin
  for(palette_index=0;palette_index<128;palette_index=palette_index+1)
   cartoon_palette_rom[palette_index]=cartoon_from_key({1'b0,palette_index[6:1],7'd0,palette_index[0]});
 end

 function [23:0] saturation_y;
 input [23:0] p;input [7:0] y;
 reg signed [9:0] r,g,b;
 begin
 r=$signed({1'b0,p[23:16]})-$signed({1'b0,y});
 g=$signed({1'b0,p[15:8]})-$signed({1'b0,y});
 b=$signed({1'b0,p[7:0]})-$signed({1'b0,y});
 saturation_y={clip10($signed({1'b0,p[23:16]})+(r>>>1)),clip10($signed({1'b0,p[15:8]})+(g>>>1)),clip10($signed({1'b0,p[7:0]})+(b>>>1))};
 end endfunction
 function [7:0] med3;
 input [7:0] a,b,c;
 begin med3=(a>b)?((b>c)?b:((a>c)?c:a)):((a>c)?a:((b>c)?c:b));end
 endfunction
 // Detector-only warm-red tolerance. Display highlight retains its existing gate.
 reg [7:0] ys[0:8];
 reg [23:0] p1,blur1,median1;
 reg [3:0] red_votes1,green_votes1,detect_votes1;reg[8:0] red_mask1,green_mask1;
 reg [3:0] m1,m2,m3;
 reg [1:0] q1;
 reg [7:0] bt1,et1,lo1,hi1,mean1;
 reg [25:0] meta1,meta2,meta3;
 reg v1,v2,v3;
 reg [23:0] color2,color3;reg[14:0] poster_key2;reg rh3,edge3;reg[4:0] rp3;
 reg rh2,gh2,edge2;
 always @(posedge clk) if(v2) cartoon_rgb3<=cartoon_palette_rom[{poster_key2[13:8],poster_key2[0]}];
 reg[4:0] rp2,gp2;
 integer i,rv,gv,dv,n;
 reg [11:0] rr,gg,bb;
 reg signed [10:0] gx,gy;
 reg [10:0] mag,heat_bound;
 reg [7:0] span;reg signed [9:0] heat_n;
 reg [2:0] bin;
 integer sobel_left,sobel_right,sobel_top,sobel_bottom;
 integer contrast_votes,tone_delta,luma_delta;
 reg edge_now,red_now,green_now,red_candidate;
 reg [3:0] red_run;
 reg [23:0] p,satp,blur_sat,negative,tone_p,tone_blur;
 reg [7:0] tone_y;
 reg [1:0] cl;
 reg [23:0] palette,poster_input,poster_color;
 function[11:0] gaussian_total;input[215:0]w;input integer offset;
 reg[11:0] corners,edges;reg[7:0]center;
 begin
 corners=({4'd0,w[215-offset-:8]}+{4'd0,w[167-offset-:8]})+({4'd0,w[71-offset-:8]}+{4'd0,w[23-offset-:8]});
 edges=({4'd0,w[191-offset-:8]}+{4'd0,w[143-offset-:8]})+({4'd0,w[95-offset-:8]}+{4'd0,w[47-offset-:8]});
 center=w[119-offset-:8];gaussian_total=corners+(edges<<1)+{2'd0,center,2'd0};
 end endfunction
 function [7:0] gaussian8;input[11:0] total;reg[11:0] rounded;
 begin rounded=total+12'd8;gaussian8=rounded[11:4];end endfunction
 always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
 v1<=0;v2<=0;v3<=0;cartoon_grey3<=0;meta3<=0;m3<=0;rh3<=0;edge3<=0;rp3<=0;color3<=0;poster_key2<=0;out_valid<=0;out_sof<=0;out_eol<=0;
 out_x<=0;out_y<=0;out_rgb<=0;out_mode<=0;
 red_hit<=0;green_hit<=0;edge_hit<=0;red_perimeter<=0;green_perimeter<=0;rp2<=0;gp2<=0;red_mask1<=0;green_mask1<=0;
 p1<=0;blur1<=0;median1<=0;detect_votes1<=0;red_votes1<=0;green_votes1<=0;
 m1<=0;m2<=0;q1<=0;bt1<=104;et1<=64;lo1<=0;hi1<=255;mean1<=128;meta1<=0;meta2<=0;
 rh2<=0;gh2<=0;edge2<=0;red_run<=0;
 for(i=0;i<9;i=i+1) ys[i]<=0;
 color2<=0;
 end else begin
 v1<=valid;v2<=v1;v3<=v2;out_valid<=v3;
 out_sof<=v3 && meta3[25]; out_eol<=v3 && meta3[24];
 red_hit<=v3 && rh3;green_hit<=1'b0;edge_hit<=v3 && edge3;
 if(valid) begin
 meta1<={sof,eol,x,y};m1<=mode;q1<=quality;mean1<=frame_mean;
 bt1<=binary_t;et1<=edge_t;lo1<=heat_lo;hi1<=heat_hi;
 rv=0;gv=0;dv=0;rr=0;gg=0;bb=0;red_mask1<=0;green_mask1<=0;
 for(i=0;i<9;i=i+1) begin
 p=window_rgb[215-i*24 -:24];ys[i]<=PRECOMPUTED?window_luma[71-i*8 -:8]:luma8(p);cl=color_class(p);
 if(PRECOMPUTED?window_red[17-i*2]:detect_red(p))dv=dv+1;
 if(PRECOMPUTED?window_red[16-i*2]:(cl==1)) begin rv=rv+1;red_mask1[8-i]<=1;end
 if(cl==2) begin gv=gv+1;green_mask1[8-i]<=1;end
 // Gaussian 1 2 1 / 2 4 2 / 1 2 1, total weight 16.
 n=(i==4)?4:((i==1||i==3||i==5||i==7)?2:1);
 // Balanced weighted sum follows the window classification loop.
 end
 p1<=window_rgb[119:96];
 // Independent of K2: RGB median across the center row removes impulse
 // specks before cartoon hue quantization without another line RAM.
 median1<={med3(window_rgb[143:136],window_rgb[119:112],window_rgb[95:88]),
           med3(window_rgb[135:128],window_rgb[111:104],window_rgb[87:80]),
           med3(window_rgb[127:120],window_rgb[103:96],window_rgb[79:72])};
 detect_votes1<=dv;red_votes1<=rv;green_votes1<=gv;
 blur1<={gaussian8(gaussian_total(window_rgb,0)),gaussian8(gaussian_total(window_rgb,8)),gaussian8(gaussian_total(window_rgb,16))};
 end
 if(v1) begin
 meta2<=meta1;m2<=m1;
 // Form nonnegative sums first.  Subtracting unsigned 8-bit operands
 // directly can wrap a negative gradient into a huge positive edge.
 sobel_left=4*med3(ys[0],ys[3],ys[6]);
 sobel_right=4*med3(ys[2],ys[5],ys[8]);
 sobel_top=4*med3(ys[0],ys[1],ys[2]);
 sobel_bottom=4*med3(ys[6],ys[7],ys[8]);
 gx=sobel_right-sobel_left;
 gy=sobel_bottom-sobel_top;
 if(gx<0)gx=-gx; if(gy<0)gy=-gy;
 mag=gx+gy;
 // A single hot/color sensor pixel can create a large raw Sobel gradient.
 // A real boundary normally has several neighbors contrasting the center.
 contrast_votes=0;
 for(i=0;i<9;i=i+1) if(i!=4) begin
  luma_delta=$signed({1'b0,ys[i]})-$signed({1'b0,ys[4]});
  if(luma_delta<0)luma_delta=-luma_delta;
  if(luma_delta>=5)contrast_votes=contrast_votes+1;
 end
 edge_now=(mag>=et1) && (contrast_votes>=3);
 // The center chroma must agree with a 5/9 neighborhood majority.
 // Sparse sensor specks fail the majority; coherent colored patches pass.
 red_candidate=(color_class(p1)==1 && color_class(blur1)==1 && red_votes1>=5);
 red_now=red_candidate && red_run>=4;
 if(!red_candidate || meta1[23:12]<=1)red_run<=red_candidate?4'd1:0;
 else if(red_run<15)red_run<=red_run+1'b1;
 green_now=1'b0;
 edge2<=edge_now;
 rh2<=detect_red(blur1) && detect_votes1>=5;gh2<=green_now;
 rp2<=red_now ? ((red_mask1[1]?0:3)+(red_mask1[3]?0:3)+(red_mask1[5]?0:3)+(red_mask1[7]?0:3)+(red_mask1[0]?0:2)+(red_mask1[2]?0:2)+(red_mask1[6]?0:2)+(red_mask1[8]?0:2)) : 0;
 gp2<=0;
 // Keep the pixel path arithmetic-free.  Frame statistics still adapt the
 // binary/edge/heat thresholds; applying a 32-bit signed brightness offset
 // to all three RGB channels here costs DSPs and closes the MIPI timing margin.
 tone_p=p1;
 tone_blur=blur1;
 tone_y=ys[4];
 satp=saturation_y(tone_p,ys[4]);negative=~satp;
 
 
 
 
 poster_input=(m1==8)?median1:tone_blur;
 poster_key2<=cartoon_key(poster_input);
 
 // Strong warm tone with true black preserved (no constant orange offset).
 
 span=(hi1>lo1)?(hi1-lo1):32; if(span<32)span=32;
 heat_n=$signed({1'b0,tone_y})-$signed({1'b0,lo1});
 bin=0;heat_bound=0;
 for(i=1;i<8;i=i+1)begin
  heat_bound=0;
  if(i&1)heat_bound=heat_bound+{3'd0,span};
  if(i&2)heat_bound=heat_bound+{2'd0,span,1'b0};
  if(i&4)heat_bound=heat_bound+{1'd0,span,2'b0};
  if(heat_n>=0 && {heat_n[7:0],3'd0}>=heat_bound)bin=i;
 end
 case(bin)
 0:palette=24'h2800ff;1:palette=24'h0060ff;2:palette=24'h00c8ff;3:palette=24'h00ff80;
 4:palette=24'h80ff00;5:palette=24'hffff00;6:palette=24'hff7000;default:palette=24'hff0020;
 endcase
 
 // Use this pixel's decision, not edge2 (which is the PREVIOUS pixel
 // until the nonblocking assignments above commit).
 
 // Gaussian 3x3 suppresses Bayer/ISP chroma speckles. Restore only
 // strong, coherent boundaries from the center pixel.
 // Per-pixel edge-preserving cartoon color: smooth and quantize inside
 // detected contours without the fixed 16x16 square mosaic.
 
 
 // Keep a recognizable camera scene, with orientation-colored edges.
 
 // Non-target colors remain a denoised natural image, avoiding the old
 // grey backdrop and colored halo around white reflections.
 
 // Only the selected style crosses the register boundary. This is the
 // same 4-stage latency with 24 RGB FF rather than 12 independent RGB banks.
 case(m1)
 1:color2<={tone_y,tone_y,tone_y};
 // Binary mode removed from public menu; no binary color datapath.
 3:color2<=negative;
 4:color2<=0;
 // Former SEPIA code falls through to RAW; public mode numbers are retained.
 6:color2<=palette;
 7:color2<=edge_now?24'hffffff:24'h000000;
 8:color2<=0;
 10:color2<=edge_now && mag>=et1 ?
              ((gx>gy)?24'hff40e8:24'h18d8ff) : tone_blur;
 11:color2<=red_now?24'hff1010:tone_p;
 default:color2<=p1;
 endcase
 end
 red_perimeter<=v3?rp3:0;green_perimeter<=0;
 if(!v1)red_run<=0;
 if(v2)begin
 meta3<=meta2;m3<=m2;rh3<=rh2;edge3<=edge2;rp3<=rp2;
 cartoon_grey3<=poster_key2[14];
 color3<=m2==8 ? (edge2?24'h303440:{3{poster_key2[7:0]}}) : color2;
 end
 if(v3) begin out_rgb<=(m3==8 && !edge3 && !cartoon_grey3)?cartoon_rgb3:color3;out_x<=meta3[23:12];out_y<=meta3[11:0];out_mode<=m3; end
 else out_rgb<=0;
 end
 end
endmodule
