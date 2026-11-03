// Shared blanking-time validation and classification; one ROI and one MLP.
module sort_target_round_robin #(parameter MAX_WAIT=24,MAX_AGE=120,MOVE_LIMIT=12,CONFIRM_VISITS=2,REPLACE_VISITS=3)(
 input wire clk,rst_n,enable,sof,input wire[15:0] source_frame,
 input wire[3:0] target_valid,input wire[191:0] target_boxes,input wire[7:0] target_shapes,
 input wire digit_valid,input wire[2:0] digit,
 output reg[47:0] roi_box,output wire digit_reset,digit_enable,
 output reg[287:0] records,output wire[3:0] record_valid,output reg[15:0] record_frame,
 output wire[11:0] digits,classes,output reg[1:0] roi_shape,input wire measured_shape_valid,input wire[1:0] measured_shape,output wire[7:0] sort_shapes);
 reg[1:0] slot,scan,state;reg[5:0] wait_frames;reg[15:0] capture_frame;
 (* ram_style="bram" *) reg[63:0] cache_mem[0:3];reg[63:0] cache_read;
 reg[2:0] saved_digit[0:3];reg[1:0] saved_shape[0:3];
 // Keep independent consensus across visits. Resetting the shared digit core
 // for another ROI must not discard a slot's voting history or let one
 // transient result replace a confirmed label.
 reg[2:0] candidate_digit[0:3],candidate_count[0:3];reg[1:0] misses[0:3];
 reg[6:0] age[0:3];reg[15:0] cache_frame;reg[3:0] good,published_mask;
 reg[3:0] vphase,seen;reg[6:0] delay_count;reg[1:0] vslot,coord;
 reg[47:0] check_box,cache_box;reg[1:0] check_shape;
 reg cache_bad,owner_bad;reg[15:0] oldest;
 reg[11:0] av,bv;reg signed[12:0] diff;
 reg[12:0] cx,cy;reg[47:0] packet_box;reg[2:0] pd,pc;reg[7:0] flags;
 reg accepted;reg[15:0] delta;reg[1:0] packet_shape;
 function[2:0] classify;input[1:0] shape;input[2:0] d;begin
 if(d<1 || d>5)classify=0;
 else if(shape==3)classify=d==3?3:4;
 else if(shape==1)classify=d[0]?1:2;else classify=0;end endfunction
 assign digit_reset=enable && state!=2;
 assign digit_enable=enable && state==2;
 assign record_valid=enable && vphase==0?published_mask:4'd0;
 genvar g;generate for(g=0;g<4;g=g+1)begin:labels
 assign digits[g*3+:3]=good[g]?saved_digit[g]:3'd0;
 assign sort_shapes[g*2+:2]=target_valid[g]?(good[g]?saved_shape[g]:target_shapes[g*2+:2]):2'd0;
 assign classes[g*3+:3]=good[g]?classify(saved_shape[g],saved_digit[g]):3'd0;
 end endgenerate
 always @*begin
 av=check_box[coord*12+:12];bv=(vphase==3)?roi_box[coord*12+:12]:cache_box[coord*12+:12];
 diff=$signed({1'b0,av})-$signed({1'b0,bv});
 accepted=good[vslot] && !cache_bad && age[vslot]<MAX_AGE;
 packet_box=accepted?cache_box:check_box;
 cx={1'b0,packet_box[47:36]}+{1'b0,packet_box[35:24]};cy={1'b0,packet_box[23:12]}+{1'b0,packet_box[11:0]};
 packet_shape=accepted?saved_shape[vslot]:check_shape;
 pd=accepted?saved_digit[vslot]:3'd0;pc=accepted?classify(packet_shape,pd):3'd0;
 flags={4'd0,(cx[12:1]>=160 && cx[12:1]<1120 && cy[12:1]>=90 && cy[12:1]<630),
  (packet_shape==1 || packet_shape==3),accepted,target_valid[vslot]};delta=source_frame-cache_frame;
 end
 always @(posedge clk)begin
  cache_read<=cache_mem[vslot];
  // One fixed write port. Refresh ownership geometry EVERY frame, keeping
  // the last measurement timestamp until the owner's visit completes.
  // Comparing to a stale recognition box accumulated benign hand motion
  // across other slots' visits and repeatedly destroyed the second vote.
  if(rst_n && enable && vphase==4 && target_valid[vslot])
   cache_mem[vslot]<={check_box,(state==2 && vslot==slot && !owner_bad && (digit_valid || wait_frames>=MAX_WAIT))?capture_frame:(seen[vslot]?cache_frame:source_frame)};
 end
 integer j;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 slot<=0;scan<=0;state<=0;wait_frames<=0;roi_box<=0;roi_shape<=0;capture_frame<=0;good<=0;
 vphase<=0;seen<=0;vslot<=0;coord<=0;delay_count<=0;published_mask<=0;records<=0;record_frame<=0;
 check_box<=0;cache_box<=0;cache_frame<=0;check_shape<=0;cache_bad<=0;owner_bad<=0;oldest<=0;
 for(j=0;j<4;j=j+1)begin saved_digit[j]<=0;saved_shape[j]<=0;age[j]<=127;candidate_digit[j]<=0;candidate_count[j]<=0;misses[j]<=0;end
 end else if(!enable)begin good<=0;seen<=0;state<=0;slot<=0;scan<=0;vphase<=0;published_mask<=0;
  for(j=0;j<4;j=j+1)begin candidate_digit[j]<=0;candidate_count[j]<=0;misses[j]<=0;end
 end
 else begin
  if(sof)begin vphase<=1;delay_count<=64;vslot<=0;coord<=0;owner_bad<=0;
   oldest<=0;record_frame<=source_frame;published_mask<=0;if(state==2)wait_frames<=wait_frames+1'b1;
  end
  case(vphase)
   1:if(delay_count!=0)delay_count<=delay_count-1'b1;
     else begin check_box<=target_boxes[vslot*48+:48];cache_box<=cache_read[63:16];cache_frame<=cache_read[15:0];check_shape<=target_shapes[vslot*2+:2];
      cache_bad<=!target_valid[vslot] || !seen[vslot] || saved_shape[vslot]!=target_shapes[vslot*2+:2];
      coord<=0;vphase<=2;if(age[vslot]!=127)age[vslot]<=age[vslot]+1'b1;end
   2:begin if(diff>MOVE_LIMIT || diff< -MOVE_LIMIT)cache_bad<=1;
    if(coord==3)begin coord<=0;vphase<=3;end else coord<=coord+1'b1;end
   3:begin
    if(state==2 && vslot==slot && (diff>MOVE_LIMIT || diff< -MOVE_LIMIT || !target_valid[vslot] || check_shape!=roi_shape))owner_bad<=1;
    if(coord==3)vphase<=4;else coord<=coord+1'b1;
   end
   4:begin
    seen[vslot]<=target_valid[vslot];
    if(!good[vslot] || cache_bad)saved_shape[vslot]<=check_shape;
    // Retarget only during SOF blanking after all four motion checks. A
    // stable owner follows modest per-frame movement; jumps still abort.
    if(state==2 && vslot==slot && !owner_bad)roi_box<=check_box;
    good[vslot]<=accepted;
    if(cache_bad || (good[vslot] && saved_shape[vslot]!=check_shape))begin
     good[vslot]<=0;candidate_count[vslot]<=0;misses[vslot]<=0;
    end
    records[vslot*72+:72]<={flags,4'd0,cy[12:9],cy[8:1],4'd0,cx[12:9],cx[8:1],5'd0,pd,
     6'd0,(packet_shape==1?2'd1:packet_shape==3?2'd2:packet_shape==2?2'd3:2'd0),5'd0,pc,6'd0,vslot};
    if(target_valid[vslot] && accepted && delta>=oldest)begin oldest<=delta;record_frame<=cache_frame;end
    if(vslot==3)vphase<=5;else begin vslot<=vslot+1'b1;vphase<=1;delay_count<=1;end
   end
   5:begin
    published_mask<=target_valid;vphase<=0;
    if(state==2)begin
     if(owner_bad)begin good[slot]<=0;candidate_count[slot]<=0;misses[slot]<=0;state<=0;scan<=slot+1'b1;end
     else if(digit_valid || wait_frames>=MAX_WAIT)begin
      if(digit_valid && digit>=1 && digit<=5 && measured_shape_valid)begin
       misses[slot]<=0;
       if(good[slot] && saved_digit[slot]==digit && saved_shape[slot]==measured_shape)begin
        candidate_count[slot]<=0;age[slot]<=0;
       end else begin
        if(candidate_digit[slot]==digit && candidate_count[slot]!=0)begin
         if(candidate_count[slot]<7)candidate_count[slot]<=candidate_count[slot]+1'b1;
        end else begin candidate_digit[slot]<=digit;candidate_count[slot]<=1;end
        if((candidate_digit[slot]==digit && candidate_count[slot]>=(good[slot]?REPLACE_VISITS-1:CONFIRM_VISITS-1)) ||
          (!good[slot] && CONFIRM_VISITS<=1))begin
         good[slot]<=1;saved_digit[slot]<=digit;saved_shape[slot]<=measured_shape;age[slot]<=0;candidate_count[slot]<=0;
        end
       end
      end else begin
       candidate_count[slot]<=0;
       if(misses[slot]>=1)begin good[slot]<=0;misses[slot]<=2;end else misses[slot]<=misses[slot]+1'b1;
      end
      state<=0;scan<=slot+1'b1;
     end
    end
   end
  endcase
  if(vphase==0 && !sof)begin
   if(state==0)begin
    if(target_valid[scan])begin roi_box<=target_boxes[scan*48+:48];roi_shape<=target_shapes[scan*2+:2];
     slot<=scan;capture_frame<=source_frame;wait_frames<=0;state<=1;end else scan<=scan+1'b1;
   end else if(state==1)state<=2;
  end
 end end
endmodule
