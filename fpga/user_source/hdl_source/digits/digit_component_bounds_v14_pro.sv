// Four row-run records in synchronous RAM, with shared serial geometry.
// Coarse pixels arrive every eight clocks. The shortest two-ended runs are
// sixteen clocks apart; four read/compare steps plus commit take nine clocks.
// Frame-border desk and speckles are excluded; EOF reunites disconnected pen.
module digit_component_bounds_v14_pro #(parameter SLOTS=4)(
 input wire clk,rst_n,valid,sof,eof,hit,input wire[7:0] x,y,
 output reg bbox_valid,done,busy,output reg[7:0] xmin,xmax,ymin,ymax,
 output reg[14:0] area
);
 localparam IDLE=0,CLEAR=1,RUN_READ=2,RUN_MATCH=3,RUN_COMMIT=4,
            SEED_READ=5,SEED=6,MERGE_READ=7,MERGE=8,COMPARE=9;
 reg[3:0] state;
 // used, border, xl, xh, yl, yh, hits. No asynchronous array reset.
 (* ram_style="bram" *) reg[48:0] records[0:SLOTS-1];
 reg[48:0] ram_q;reg[1:0] addr,seed,slot,free_slot;
 wire used=ram_q[48],border=ram_q[47];
 wire[7:0] xl=ram_q[46:39],xh=ram_q[38:31],yl=ram_q[30:23],yh=ram_q[22:15];
 wire[14:0] hits=ram_q[14:0];
 reg[7:0] run_start,length,rxl,rxh,ry;
 reg[8:0] run_n;
 reg run_border,merged_border,found,free_found,eof_pending;
 reg[7:0] uxl,uxh,uyl,uyh,sxl,sxh,syl,syh;
 reg[14:0] total;
 wire run_match=used&&(!border||run_border)&&ry>=yh&&
   {1'b0,ry}<={1'b0,yh}+9'd2&&
   {1'b0,rxl}<={1'b0,xh}+9'd2&&{1'b0,rxh}+9'd2>={1'b0,xl};
 wire free_match=!used||({1'b0,ry}>{1'b0,yh}+9'd2&&hits<15'd6);
 wire stroke_match=addr!=seed&&used&&!border&&hits>=15'd6&&
   {1'b0,xl}<={1'b0,sxh}+9'd2&&{1'b0,sxl}<={1'b0,xh}+9'd2&&
   {1'b0,yl}<={1'b0,syh}+9'd2&&{1'b0,syl}<={1'b0,yh}+9'd2;
 wire add_component=(state==RUN_MATCH&&run_match)||(state==MERGE&&stroke_match);
 wire ram_we=state==CLEAR||(state==RUN_MATCH&&run_match)||
             (state==RUN_COMMIT&&(found||free_found));
 wire[48:0] ram_d=state==CLEAR?49'd0:
   state==RUN_MATCH?{1'b0,ram_q[47:0]}:
   found?{1'b1,merged_border,uxl,uxh,uyl,uyh,total}:
         {1'b1,run_border,rxl,rxh,ry,ry,6'd0,run_n};
 always @(posedge clk)begin
  ram_q<=records[addr];
  if(ram_we)records[addr]<=ram_d;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin
   state<=IDLE;bbox_valid<=0;done<=0;busy<=0;xmin<=0;xmax<=0;ymin<=0;ymax<=0;area<=0;
   run_start<=0;length<=0;addr<=0;seed<=0;slot<=0;free_slot<=0;
   rxl<=0;rxh<=0;ry<=0;run_n<=0;run_border<=0;merged_border<=0;found<=0;free_found<=0;eof_pending<=0;
   uxl<=0;uxh<=0;uyl<=0;uyh<=0;sxl<=0;sxh<=0;syl<=0;syh<=0;total<=0;
  end else begin
   done<=0;
   if(sof)begin
    state<=CLEAR;addr<=0;busy<=0;length<=0;run_start<=0;eof_pending<=0;
   end else begin
    if(eof)eof_pending<=1;
    // Pixel/run accumulation stays live during the previous record scan.
    if(valid&&!busy)begin
     if(hit&&length==0)run_start<=x;
     if(!hit||x==159)begin
      length<=0;
      if(state==IDLE&&({1'b0,length}+hit)!=0)begin
       rxl<=run_start;rxh<=hit?x:x-1'b1;ry<=y;run_n<={1'b0,length}+hit;
       run_border<=run_start<=1||(hit?x:x-1'b1)>=158||y<=1||y>=88;
       uxl<=run_start;uxh<=hit?x:x-1'b1;uyl<=y;uyh<=y;
       total<={7'd0,length}+hit;merged_border<=run_start<=1||(hit?x:x-1'b1)>=158||y<=1||y>=88;
       addr<=0;found<=0;free_found<=0;state<=RUN_READ;
      end
     end else if(hit)length<=length+1'b1;
    end
    if(add_component)begin
     if(xl<uxl)uxl<=xl;if(xh>uxh)uxh<=xh;
     if(yl<uyl)uyl<=yl;if(yh>uyh)uyh<=yh;total<=total+hits;
    end
    case(state)
     IDLE:if(eof||eof_pending)begin
      busy<=1;seed<=0;addr<=0;state<=SEED_READ;area<=0;bbox_valid<=0;eof_pending<=0;
     end
     CLEAR:if(addr==SLOTS-1)state<=IDLE;else addr<=addr+1'b1;
     RUN_READ:state<=RUN_MATCH;
     RUN_MATCH:begin
      if(free_match&&!free_found)begin free_slot<=addr;free_found<=1;end
      if(run_match)begin
       if(!found)begin slot<=addr;found<=1;end
       merged_border<=merged_border||border;
      end
      if(addr==SLOTS-1)begin
       // Include a match first discovered in the final record. The write
       // itself occurs next clock, after the final accumulated bounds settle.
       if(found||run_match)addr<=found?slot:addr;
       else if(free_found||free_match)addr<=free_found?free_slot:addr;
       state<=RUN_COMMIT;
      end else begin addr<=addr+1'b1;state<=RUN_READ;end
     end
     RUN_COMMIT:state<=IDLE;
     SEED_READ:state<=SEED;
     SEED:begin
      if(used&&!border&&hits>=15'd6&&xl>1&&xh<158&&yl>1&&yh<88)begin
       sxl<=xl;sxh<=xh;syl<=yl;syh<=yh;
       uxl<=xl;uxh<=xh;uyl<=yl;uyh<=yh;total<=hits;addr<=0;state<=MERGE_READ;
      end else if(seed==SLOTS-1)begin busy<=0;done<=1;state<=IDLE;end
      else begin seed<=seed+1'b1;addr<=seed+1'b1;state<=SEED_READ;end
     end
     MERGE_READ:state<=MERGE;
     MERGE:if(addr==SLOTS-1)state<=COMPARE;else begin addr<=addr+1'b1;state<=MERGE_READ;end
     COMPARE:begin
      if({1'b0,uxh}>={1'b0,uxl}+9'd1&&{1'b0,uyh}>={1'b0,uyl}+9'd3&&total>area)begin
       bbox_valid<=1;xmin<=uxl;xmax<=uxh;ymin<=uyl;ymax<=uyh;area<=total;
      end
      if(seed==SLOTS-1)begin busy<=0;done<=1;state<=IDLE;end
      else begin seed<=seed+1'b1;addr<=seed+1'b1;state<=SEED_READ;end
     end
     default:state<=IDLE;
    endcase
   end
  end
 end
endmodule
