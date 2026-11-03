// 48/32 unsigned restoring divider, one transaction in 48 clocks.
// Used only for frame-rate AWB statistics, not for per-pixel division.
module frame_divider_v8(input wire clk,rst,start,input wire[31:0]denominator,
 input wire[47:0]numerator,output reg[47:0]quotient,output reg done);
 reg busy;reg[5:0]left;reg[47:0]bits;reg[31:0]den,rem;
 wire[32:0]trial={rem,bits[47]};wire ge=trial>={1'b0,den};
 wire[32:0]difference=trial-{1'b0,den};
 always @(posedge clk)begin
 if(rst)begin busy<=0;left<=0;bits<=0;den<=1;rem<=0;quotient<=0;done<=0;end
 else begin
 done<=0;
 if(start && !busy)begin busy<=1;left<=47;bits<=numerator;den<=denominator==0?1:denominator;rem<=0;end
 else if(busy)begin
 rem<=ge?difference[31:0]:trial[31:0];bits<={bits[46:0],ge};
 if(left==0)begin quotient<={bits[46:0],ge};done<=1;busy<=0;end else left<=left-1'b1;
 end
 end
 end
endmodule
