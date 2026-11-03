// Shapes plus one panel with before/after histograms. Shared bar addressing
// preserves the exact pixels while avoiding 32 parallel coordinate comparators.
module diagnostic_overlay_v11(
 input wire clk,rst_n,sof,valid,input wire [11:0] x,y,
 input wire [23:0] rgb,input wire [3:0] mode,
 input wire [191:0] histogram,input wire [7:0] mean,digit_threshold,
 input wire [14:0] digit_ink,input wire [3:0] digit_state,
 input wire [31:0] gains,input wire motion_valid,input wire [47:0] motion_box,
 input wire [11:0] motion_count,input wire gesture_valid,input wire [2:0] gesture_value,input wire [47:0] gesture_box,input wire beauty,input wire [191:0] after_histogram,output reg [23:0] painted
);
 reg[6:0] heights[0:31];genvar j;
 generate for(j=0;j<16;j=j+1)begin:hist_bars
 always @(posedge clk or negedge rst_n)
 if(!rst_n)heights[j+16]<=0;else if(sof)heights[j+16]<=after_histogram[j*12+5+:7];
 always @(posedge clk or negedge rst_n)
 if(!rst_n)heights[j]<=0;else if(sof)heights[j]<=histogram[j*12+5+:7];
 end endgenerate
 wire[3:0] bin=x[7:4]-4'd1;
 wire before_column=x[3:0]<5;
 wire after_column=x[3:0]>=7 && x[3:0]<12;
 wire[6:0] height=heights[{after_column,bin}];
 wire[11:0] level=12'd700-y;
 wire hist_hit=x>=16 && x<272 && y>=573 && y<700 &&
               (before_column || after_column) && level<={5'd0,height};
 wire medge=motion_valid && mode==9 &&
 ((x>=motion_box[47:36] && x<=motion_box[35:24] && (y==motion_box[23:12] || y==motion_box[11:0])) ||
 (y>=motion_box[23:12] && y<=motion_box[11:0] && (x==motion_box[47:36] || x==motion_box[35:24])));
 wire hedge=mode==11 && gesture_valid &&
 ((x>=gesture_box[47:36] && x<=gesture_box[35:24] && (y==gesture_box[23:12] || y==gesture_box[11:0])) ||
 (y>=gesture_box[23:12] && y<=gesture_box[11:0] && (x==gesture_box[47:36] || x==gesture_box[35:24])));
 always @*begin
 painted=rgb;
 if(valid)begin
 if(beauty && x>=12 && x<276 && y>=548 && y<704)begin
 painted=24'h102038;if(hist_hit)painted=after_column ? 24'hffae60 : 24'h20bfff;
 if(y>=571 && y<576 && x>=16 && x<28)painted=24'h20bfff;
 if(y>=571 && y<576 && x>=144 && x<156)painted=24'hffae60;
 if(y==700 && x>=16 && x<272)painted=24'h607080;
 end
 if((mode==10 || mode==12) && ((x>=624 && x<=656 && y==360)||(y>=344 && y<=376 && x==640)))painted=24'h00ffff;
 if(medge)painted=24'hffff00;if(hedge)painted=24'h40ff80;
 end end
endmodule
