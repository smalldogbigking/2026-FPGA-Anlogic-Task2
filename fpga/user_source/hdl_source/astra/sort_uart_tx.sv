// Same 75 MHz domain as the published detector snapshot. No wide-bus CDC.
module sort_uart_tx #(parameter CLK_HZ=74250000,BAUD=115200,RATE=10)(
 input wire clk,rst_n,enable,input wire[3:0] valid_slots,
 input wire[287:0] records,input wire[15:0] frame_id,
 output reg tx,output wire busy,output reg[15:0] packet_seq,input wire ms_tick);
 localparam BIT_TICKS=(CLK_HZ+BAUD/2)/BAUD;
 // Reuse the existing button-controller millisecond enable (same clock domain).
 reg[$clog2(1000/RATE)-1:0] cadence;
 reg[287:0] frozen;reg[3:0] mask;reg[15:0] frozen_frame;
 reg[2:0] count,slot;reg[5:0] index,total;reg[3:0] field;
 reg[15:0] crc;reg active,byte_busy;reg[9:0] shift;
 reg[$clog2(BIT_TICKS)-1:0] ticks;reg[3:0] bits;
 reg[7:0] next_byte;integer k;reg[2:0] n;
 function[15:0] crc_byte;input[15:0] c;input[7:0] b;integer j;reg[15:0] v;begin
 v=c^{b,8'd0};for(j=0;j<8;j=j+1)v=v[15]?(v<<1)^16'h1021:v<<1;crc_byte=v;end endfunction
 assign busy=active || byte_busy;
 always @*begin
 next_byte=0;
 case(index)
  0:next_byte=8'ha5;1:next_byte=8'h5a;2:next_byte=1;3:next_byte=1;
  4:next_byte=packet_seq[7:0];5:next_byte=packet_seq[15:8];
  6:next_byte=frozen_frame[7:0];7:next_byte=frozen_frame[15:8];
  8:next_byte={5'd0,count};9:next_byte=count*9;
  default:if(index==total-2)next_byte=crc[7:0];
   else if(index==total-1)next_byte=crc[15:8];
   else case(field)
    0:next_byte={5'd0,slot};
    1:next_byte=frozen[slot*72+8+:8];
    2:next_byte=frozen[slot*72+16+:8];
    3:next_byte=frozen[slot*72+24+:8];
    4:next_byte=frozen[slot*72+32+:8];
    5:next_byte=frozen[slot*72+40+:8];
    6:next_byte=frozen[slot*72+48+:8];
    7:next_byte=frozen[slot*72+56+:8];
    default:next_byte=frozen[slot*72+64+:8];
   endcase
 endcase
 end
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin tx<=1;cadence<=0;frozen<=0;mask<=0;frozen_frame<=0;count<=0;slot<=0;
 index<=0;total<=12;field<=0;crc<=16'hffff;active<=0;byte_busy<=0;shift<=1023;ticks<=0;bits<=0;packet_seq<=0;end
 else begin
  if(ms_tick && cadence==1000/RATE-1)begin
   cadence<=0;
   if(!busy)begin
    // COUNT=0 heartbeat outside ACTIVE, including exit and camera settling.
    frozen<=records;mask<=enable?valid_slots:4'd0;frozen_frame<=frame_id;
    n=0;for(k=0;k<4;k=k+1)if(enable && valid_slots[k])n=n+1'b1;
    count<=n;total<=12+n*9;index<=0;field<=0;slot<=0;crc<=16'hffff;active<=1;
   end
  end else if(ms_tick)cadence<=cadence+1'b1;
  if(active && !byte_busy)begin
   if(index>=10 && index<total-2 && !mask[slot])slot<=slot+1'b1;
   else begin
    shift<={1'b1,next_byte,1'b0};tx<=0;bits<=0;ticks<=0;byte_busy<=1;
    if(index>=2 && index<total-2)crc<=crc_byte(crc,next_byte);
    if(index>=10 && index<total-2)begin
     if(field==8)begin field<=0;slot<=slot+1'b1;end else field<=field+1'b1;
    end
    if(index==total-1)begin active<=0;packet_seq<=packet_seq+1'b1;end
    else index<=index+1'b1;
   end
  end
  if(byte_busy)begin
   if(ticks==BIT_TICKS-1)begin
    ticks<=0;shift<={1'b1,shift[9:1]};tx<=shift[1];
    if(bits==9)begin byte_busy<=0;tx<=1;end else bits<=bits+1'b1;
   end else ticks<=ticks+1'b1;
  end
 end end
endmodule
