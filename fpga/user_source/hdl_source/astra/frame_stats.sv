// Frame-stable histogram statistics; public interface and EOF/SOF timing
// are unchanged. Dense parameterisations retain the original implementation.
module frame_stats #(parameter WIDTH=1280,HEIGHT=720,SAMPLE_LOG2=4)(
 input wire clk,rst_n,sof,eof,valid,input wire [11:0] x,y,
 input wire [7:0] luma,output wire [7:0] mean,binary_t,edge_t,heat_lo,heat_hi,
 output wire stats_valid,frame_bad,busy
);
 generate if(SAMPLE_LOG2>=2)begin: sparse
  frame_stats_ram #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.SAMPLE_LOG2(SAMPLE_LOG2)) impl(.*);
 end else begin: dense
  frame_stats_dense #(.WIDTH(WIDTH),.HEIGHT(HEIGHT),.SAMPLE_LOG2(SAMPLE_LOG2)) impl(.*);
 end endgenerate
endmodule

// Frame-stable histogram statistics. SOF may coincide with first valid pixel.
// EOF is a separate pulse AFTER last pixel. Leave >=18 clocks from EOF to SOF.
// A complete raster is required; partial frames retain previous thresholds.
module frame_stats_ram #(parameter WIDTH=1280,HEIGHT=720,SAMPLE_LOG2=4)(
 input wire clk,rst_n,sof,eof,valid,
 input wire [11:0] x,y,
 input wire [7:0] luma,
 output reg [7:0] mean,binary_t,edge_t,heat_lo,heat_hi,
 output reg stats_valid,frame_bad,busy
);
 localparam N=((WIDTH+(1<<SAMPLE_LOG2)-1)>>SAMPLE_LOG2)*((HEIGHT+(1<<SAMPLE_LOG2)-1)>>SAMPLE_LOG2);
 localparam CW=$clog2(N+1);
 reg [CW-1:0] center_count,center_sum;
 // One RAM word stores full-frame and central histogram counts. Every
 // sample has at least four clocks before the next, so one synchronous
 // read and one delayed write replace 32 parallel resettable counters.
 (* ram_style="bram" *) reg [2*CW-1:0] hist_ram[0:15];
 reg [2*CW-1:0] bin_read;
 reg [15:0] hist_seen,center_seen;
 reg write_bin,write_center,hist_was_seen,center_was_seen;
 reg [3:0] write_addr;
 reg [7:0] center_median;reg median_found;
 wire sample=valid && ((x & ((1<<SAMPLE_LOG2)-1))==0) && ((y & ((1<<SAMPLE_LOG2)-1))==0);
 wire center_sample=sample && x>=WIDTH/4 && x<WIDTH-WIDTH/4 && y>=HEIGHT/4 && y<HEIGHT-HEIGHT/4;
 reg [19:0] count,cumulative;
 reg [31:0] sample_sum,divide_residue;
 reg [31:0] divide_divisor;
 reg [7:0] divide_quotient;
 reg [2:0] divide_bit;
 reg divide_active;
 reg [4:0] scan;
 reg [7:0] next_mean,low,high;
 reg low_found,high_found,pending;
 wire request=sample && (!busy || sof);
 wire first_scan=eof && count==N && !valid;
 wire [3:0] read_addr=first_scan?4'd0:busy?(scan[3:0]+4'd1):luma[7:4];
 wire [CW-1:0] old_hist=hist_was_seen?bin_read[CW-1:0]:{CW{1'b0}};
 wire [CW-1:0] old_center=center_was_seen?bin_read[2*CW-1:CW]:{CW{1'b0}};
 wire [CW-1:0] new_hist=old_hist+1'b1;
 wire [CW-1:0] new_center=old_center+write_center;
 wire [CW-1:0] scan_hist=hist_seen[scan[3:0]]?bin_read[CW-1:0]:{CW{1'b0}};
 wire [CW-1:0] scan_center=center_seen[scan[3:0]]?bin_read[2*CW-1:CW]:{CW{1'b0}};
 always @(posedge clk)begin
  bin_read<=hist_ram[read_addr];
  if(write_bin)hist_ram[write_addr]<={new_center,new_hist};
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin hist_seen<=0;center_seen<=0;write_bin<=0;write_center<=0;write_addr<=0;hist_was_seen<=0;center_was_seen<=0;end
  else begin
   write_bin<=request;
   if(sof)begin hist_seen<=0;center_seen<=0;end
   if(request)begin
    write_addr<=luma[7:4];write_center<=center_sample && !sof;
    hist_was_seen<=!sof && hist_seen[luma[7:4]];
    center_was_seen<=!sof && center_seen[luma[7:4]];
    hist_seen[luma[7:4]]<=1;
    if(center_sample && !sof)center_seen[luma[7:4]]<=1;
   end
  end
 end


 integer i,cum,span,t;
 always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
 center_count<=0;center_sum<=0;center_median<=128;median_found<=0;count<=0;sample_sum<=0;divide_residue<=0;divide_divisor<=0;divide_quotient<=0;
 divide_bit<=0;divide_active<=0;
 mean<=128;binary_t<=104;edge_t<=64;heat_lo<=32;heat_hi<=224;
 stats_valid<=0;frame_bad<=0;busy<=0;scan<=0;cumulative<=0;pending<=0;
 next_mean<=128;low<=0;high<=255;low_found<=0;high_found<=0;
 end else begin
 stats_valid<=0;
 if(sof) begin
 if(busy) begin frame_bad<=1;busy<=0;end
 divide_active<=0;
 if(pending) begin
 mean<=next_mean;
 t=center_median;
 binary_t<=(t<1)?1:(t>254)?254:t;
 heat_lo<=low;heat_hi<=high;
 span=high-low;t=20+(span>>3);edge_t<=(t>48)?48:t;
 stats_valid<=1;
 end
 pending<=0;
 center_count<=0;count<=sample?1:0;sample_sum<=sample?luma:0;
 end else begin
 if(center_sample && !busy)center_count<=center_count+1'b1;
 if(sample && !busy) begin
 count<=count+1'b1;sample_sum<=sample_sum+luma;
 end
 if(eof) begin
 frame_bad<=(count!=N)||valid;
 if(count==N && !valid) begin
 // Eight restoring-subtraction clocks calculate the actual sampled mean.
 // They overlap the 16-cycle percentile scan in vertical blanking.
     divide_residue<=sample_sum;divide_divisor<=(N<<7);divide_quotient<=0;
     divide_bit<=7;divide_active<=1;
     center_sum<=0;median_found<=0;busy<=1;scan<=0;cumulative<=0;low_found<=0;high_found<=0;low<=0;high<=255;
 end
 end else if(busy) begin
 if(divide_active) begin
 if(divide_residue >= divide_divisor) begin
 divide_residue<=divide_residue-divide_divisor;
 divide_quotient[divide_bit]<=1'b1;
 end
 divide_divisor<=divide_divisor>>1;
 if(divide_bit==0) begin
 next_mean<=divide_quotient | ((divide_residue>=divide_divisor)?8'd1:8'd0);
 divide_active<=0;
 end else divide_bit<=divide_bit-1'b1;
 end
 if(scan<16) begin
 if(!median_found && center_count!=0 && center_sum+scan_center>=(center_count+1)/2)begin center_median<=scan*16+8;median_found<=1;end
 center_sum<=center_sum+scan_center;
 cum=cumulative+scan_hist;cumulative<=cum;
 if(!low_found && cum>=(N+9)/10) begin low<=scan*16;low_found<=1;end
 if(!high_found && cum>=(N*9+9)/10) begin high<=scan*16+15;high_found<=1;end
 scan<=scan+1'b1;
 end else begin
 busy<=0;pending<=1;
 end
 end
 end
 end
 end
endmodule

// Frame-stable histogram statistics. SOF may coincide with first valid pixel.
// EOF is a separate pulse AFTER last pixel. Leave >=18 clocks from EOF to SOF.
// A complete raster is required; partial frames retain previous thresholds.
module frame_stats_dense #(parameter WIDTH=1280,HEIGHT=720,SAMPLE_LOG2=4)(
 input wire clk,rst_n,sof,eof,valid,
 input wire [11:0] x,y,
 input wire [7:0] luma,
 output reg [7:0] mean,binary_t,edge_t,heat_lo,heat_hi,
 output reg stats_valid,frame_bad,busy
);
 localparam N=((WIDTH+(1<<SAMPLE_LOG2)-1)>>SAMPLE_LOG2)*((HEIGHT+(1<<SAMPLE_LOG2)-1)>>SAMPLE_LOG2);
 localparam CW=$clog2(N+1);
 reg [CW-1:0] hist[0:15];
 reg [CW-1:0] center_hist[0:15],center_count,center_sum;
 reg [7:0] center_median;reg median_found;
 wire sample=valid && ((x & ((1<<SAMPLE_LOG2)-1))==0) && ((y & ((1<<SAMPLE_LOG2)-1))==0);
 wire center_sample=sample && x>=WIDTH/4 && x<WIDTH-WIDTH/4 && y>=HEIGHT/4 && y<HEIGHT-HEIGHT/4;
 reg [19:0] count,cumulative;
 reg [31:0] sample_sum,divide_residue;
 reg [31:0] divide_divisor;
 reg [7:0] divide_quotient;
 reg [2:0] divide_bit;
 reg divide_active;
 reg [4:0] scan;
 reg [7:0] next_mean,low,high;
 reg low_found,high_found,pending;

 integer i,cum,span,t;
 always @(posedge clk or negedge rst_n) begin
 if(!rst_n) begin
 for(i=0;i<16;i=i+1) begin hist[i]<=0;center_hist[i]<=0;end
 center_count<=0;center_sum<=0;center_median<=128;median_found<=0;count<=0;sample_sum<=0;divide_residue<=0;divide_divisor<=0;divide_quotient<=0;
 divide_bit<=0;divide_active<=0;
 mean<=128;binary_t<=104;edge_t<=64;heat_lo<=32;heat_hi<=224;
 stats_valid<=0;frame_bad<=0;busy<=0;scan<=0;cumulative<=0;pending<=0;
 next_mean<=128;low<=0;high<=255;low_found<=0;high_found<=0;
 end else begin
 stats_valid<=0;
 if(sof) begin
 if(busy) begin frame_bad<=1;busy<=0;end
 divide_active<=0;
 if(pending) begin
 mean<=next_mean;
 t=center_median;
 binary_t<=(t<1)?1:(t>254)?254:t;
 heat_lo<=low;heat_hi<=high;
 span=high-low;t=20+(span>>3);edge_t<=(t>48)?48:t;
 stats_valid<=1;
 end
 pending<=0;
 for(i=0;i<16;i=i+1) begin hist[i]<=0;center_hist[i]<=0;end
 center_count<=0;count<=sample?1:0;sample_sum<=sample?luma:0;
 if(sample) hist[luma[7:4]]<=1;
 end else begin
 if(center_sample && !busy)begin center_hist[luma[7:4]]<=center_hist[luma[7:4]]+1'b1;center_count<=center_count+1'b1;end
 if(sample && !busy) begin
 hist[luma[7:4]]<=hist[luma[7:4]]+1'b1;
 count<=count+1'b1;sample_sum<=sample_sum+luma;
 end
 if(eof) begin
 frame_bad<=(count!=N)||valid;
 if(count==N && !valid) begin
 // Eight restoring-subtraction clocks calculate the actual sampled mean.
 // They overlap the 16-cycle percentile scan in vertical blanking.
     divide_residue<=sample_sum;divide_divisor<=(N<<7);divide_quotient<=0;
     divide_bit<=7;divide_active<=1;
     center_sum<=0;median_found<=0;busy<=1;scan<=0;cumulative<=0;low_found<=0;high_found<=0;low<=0;high<=255;
 end
 end else if(busy) begin
 if(divide_active) begin
 if(divide_residue >= divide_divisor) begin
 divide_residue<=divide_residue-divide_divisor;
 divide_quotient[divide_bit]<=1'b1;
 end
 divide_divisor<=divide_divisor>>1;
 if(divide_bit==0) begin
 next_mean<=divide_quotient | ((divide_residue>=divide_divisor)?8'd1:8'd0);
 divide_active<=0;
 end else divide_bit<=divide_bit-1'b1;
 end
 if(scan<16) begin
 if(!median_found && center_count!=0 && center_sum+center_hist[scan]>=(center_count+1)/2)begin center_median<=scan*16+8;median_found<=1;end
 center_sum<=center_sum+center_hist[scan];
 cum=cumulative+hist[scan];cumulative<=cum;
 if(!low_found && cum>=(N+9)/10) begin low<=scan*16;low_found<=1;end
 if(!high_found && cum>=(N*9+9)/10) begin high<=scan*16+15;high_found<=1;end
 scan<=scan+1'b1;
 end else begin
 busy<=0;pending<=1;
 end
 end
 end
 end
 end
endmodule
