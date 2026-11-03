// Sparse median-luma histogram, exact bright-paper cluster mean. A single
// synchronous RAM port performs clear/read/modify/write sequentially; samples
// are 16 clocks apart, so no arithmetic or array multiplexers are replicated.
module digit_paper_level_v14_pro(
 input wire clk,rst_n,valid,sof,eof,input wire[11:0] x,y,input wire[7:0] lum,
 output reg done,output wire busy,output reg[7:0] paper_level,
 input wire roi_mode,output reg roi_quality
);
 localparam IDLE=0,CLEAR=1,UPDATE_WAIT=2,UPDATE_WRITE=3,SCAN_READ=4,
            SCAN_LOOK=5,LOW_READ=6,LOW_ADD=7,DIV_START=8,DIV_WAIT=9,
            ROI_COUNT_READ=10,ROI_COUNT_ADD=11,ROI_LOW_READ=12,
            ROI_LOW_LOOK=13,ROI_HIGH_READ=14,ROI_HIGH_LOOK=15,
            ROI_VERIFY_READ=16,ROI_VERIFY_ADD=17;
 // 64 four-level bins resolve dim ink/card contrast without another ERAM.
 // The legacy bright-paper path still uses precisely bins0..15 and16steps.
 (* ram_style="bram" *) reg[31:0] hist_bins[0:63];
 reg[31:0] ram_q;reg[5:0] ram_addr;
 reg[7:0] h0,h1,sample_lum;
 function[7:0] med3;input[7:0] a,b,c;
 begin med3=a>b?(b>c?b:(a>c?c:a)):(a>c?a:(b>c?c:b));end endfunction
 wire[7:0] m=med3(lum,h0,h1);
 reg[4:0] state;reg[1:0] span;reg eof_pending;
 reg[19:0] total_sum;reg[11:0] total_count;
 reg[11:0] roi_cumulative,roi_trim,roi_dark_count;reg[5:0] roi_low_bin;
 reg[7:0] roi_split_sum;
 wire[12:0] roi_count_next={1'b0,roi_cumulative}+{1'b0,ram_q[31:20]};
 wire[7:0] roi_mid_bin={2'd0,roi_low_bin}+{2'd0,ram_addr}+8'd1;
 wire[12:0] roi_dark_next={1'b0,roi_dark_count}+(({1'b0,ram_addr,1'b0}<roi_split_sum)?{1'b0,ram_q[31:20]}:13'd0);
 wire[14:0] roi_dark_triple={2'd0,roi_dark_next}+{1'b0,roi_dark_next,1'b0};
 wire divider_done;wire[7:0] quotient;
 assign busy=state!=IDLE;
 wire ram_we=state==CLEAR||state==UPDATE_WRITE;
 wire[31:0] ram_d=state==CLEAR?32'd0:
                  {ram_q[31:20]+12'd1,ram_q[19:0]+{12'd0,sample_lum}};
 // No asynchronous reset on memory: TD can infer one small ERAM.
 always @(posedge clk)begin
  ram_q<=hist_bins[ram_addr];
  if(ram_we)hist_bins[ram_addr]<=ram_d;
 end
 digit_paper_mean8 divide(.clk(clk),.rst_n(rst_n),.start(state==DIV_START),
   .numerator(total_sum),.denominator(total_count),.done(divider_done),.quotient(quotient));
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   h0<=0;h1<=0;sample_lum<=0;state<=IDLE;ram_addr<=0;span<=0;eof_pending<=0;
   total_sum<=0;total_count<=0;done<=0;paper_level<=154;
   roi_cumulative<=0;roi_trim<=0;roi_low_bin<=0;roi_quality<=0;roi_dark_count<=0;roi_split_sum<=0;
  end else begin
   done<=0;
   if(valid)begin h0<=lum;h1<=x==0?lum:h0;end
   if(eof)eof_pending<=1;
   if(sof&&state==IDLE)begin state<=CLEAR;ram_addr<=0;eof_pending<=0;end
   else case(state)
    IDLE:begin
     if(eof||eof_pending)begin
      ram_addr<=roi_mode?0:15;state<=roi_mode?ROI_COUNT_READ:SCAN_READ;eof_pending<=0;
      if(roi_mode)begin total_count<=0;roi_cumulative<=0;roi_quality<=0;end
     end
     else if(valid&&(roi_mode?(x[1:0]==3&&y[0]):(x[3:0]==15&&y[3:0]==15)))begin
      ram_addr<=roi_mode?m[7:2]:{2'd0,m[7:4]};sample_lum<=m;state<=UPDATE_WAIT;
     end
    end
    CLEAR:if(ram_addr==(roi_mode?63:15))state<=IDLE;else ram_addr<=ram_addr+1'b1;
    UPDATE_WAIT:state<=UPDATE_WRITE;
    UPDATE_WRITE:state<=IDLE;
    SCAN_READ:state<=SCAN_LOOK;
    SCAN_LOOK:begin
     // A sheet must supply at least 160/3600 samples. Rare bright impulses
     // cannot force threshold 255. Two neighbouring lower bins are included.
     if(ram_q[31:20]>=160)begin
      total_sum<=ram_q[19:0];total_count<=ram_q[31:20];span<=0;
      if(ram_addr==0)state<=DIV_START;
      else begin ram_addr<=ram_addr-1'b1;state<=LOW_READ;end
     end else if(ram_addr==0)state<=IDLE;
     else begin ram_addr<=ram_addr-1'b1;state<=SCAN_READ;end
    end
    LOW_READ:state<=LOW_ADD;
    LOW_ADD:begin
     total_sum<=total_sum+ram_q[19:0];total_count<=total_count+ram_q[31:20];
     if(span==1||ram_addr==0)state<=DIV_START;
     else begin span<=span+1'b1;ram_addr<=ram_addr-1'b1;state<=LOW_READ;end
    end
    DIV_START:state<=DIV_WAIT;
    DIV_WAIT:if(divider_done)begin paper_level<=quotient;done<=1;state<=IDLE;end
    // The same histogram RAM is idle in SORT. Sample local pooled coordinates
    // at 4x2 pitch (at most 560 central samples), then trim at least two / 1/32
    // of samples from each tail. A cold/hot pixel cannot set the threshold.
    ROI_COUNT_READ:state<=ROI_COUNT_ADD;
    ROI_COUNT_ADD:begin
     total_count<=total_count+ram_q[31:20];
     if(ram_addr==63)begin ram_addr<=0;roi_cumulative<=0;state<=ROI_LOW_READ;end
     else begin ram_addr<=ram_addr+1'b1;state<=ROI_COUNT_READ;end
    end
    ROI_LOW_READ:begin roi_trim<=(total_count>>5)<2?12'd2:(total_count>>5);state<=ROI_LOW_LOOK;end
    ROI_LOW_LOOK:begin
     if(roi_count_next>=roi_trim || ram_addr==63)begin
      roi_low_bin<=ram_addr;ram_addr<=63;roi_cumulative<=0;state<=ROI_HIGH_READ;
     end else begin roi_cumulative<=roi_count_next[11:0];ram_addr<=ram_addr+1'b1;state<=ROI_LOW_READ;end
    end
    ROI_HIGH_READ:state<=ROI_HIGH_LOOK;
    ROI_HIGH_LOOK:begin
     if(roi_count_next>=roi_trim || ram_addr==0)begin
      paper_level<=roi_mid_bin<<1;roi_split_sum<=roi_mid_bin;
      // At least four4-level bins of robust contrast, plus a sparse dark
      // mode: noise around a blank card's mean must not become a glyph.
      roi_quality<=total_count>=16 && {1'b0,ram_addr}>={1'b0,roi_low_bin}+7'd4;
      roi_dark_count<=0;ram_addr<=0;state<=ROI_VERIFY_READ;
     end else begin roi_cumulative<=roi_count_next[11:0];ram_addr<=ram_addr-1'b1;state<=ROI_HIGH_READ;end
    end
    ROI_VERIFY_READ:state<=ROI_VERIFY_ADD;
    ROI_VERIFY_ADD:begin
     roi_dark_count<=roi_dark_next[11:0];
     if(ram_addr==63)begin
      roi_quality<=roi_quality && roi_dark_triple<{3'd0,total_count};done<=1;state<=IDLE;
     end else begin ram_addr<=ram_addr+1'b1;state<=ROI_VERIFY_READ;end
    end
    default:state<=IDLE;
   endcase
  end
 end
endmodule
// A mean of unsigned 8bit pixels cannot exceed 255, so only quotient bits
// 7..0 need testing. 20bit sum and 12bit count cover 3600 samples exactly.
module digit_paper_mean8(
 input wire clk,rst_n,start,input wire[19:0] numerator,input wire[11:0] denominator,
 output reg done,output reg[7:0] quotient
);
 reg active;reg[2:0] bit_index;reg[19:0] remainder;reg[18:0] divisor;
 wire subtract=remainder>={1'b0,divisor};
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin active<=0;bit_index<=0;remainder<=0;divisor<=0;quotient<=0;done<=0;end
  else begin
   done<=0;
   if(start&&!active)begin active<=1;bit_index<=7;remainder<=numerator;divisor<={denominator,7'd0};quotient<=0;end
   else if(active)begin
    if(subtract)remainder<=remainder-{1'b0,divisor};
    quotient<={quotient[6:0],subtract};divisor<=divisor>>1;
    if(bit_index==0)begin active<=0;done<=1;end else bit_index<=bit_index-1'b1;
   end
  end
 end
endmodule

