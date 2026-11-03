// Scene sequencing only. Motion planning and grasp decisions belong to MCU.
module sort_mode_ctrl #(
 parameter FACE_POSE_FRAMES=90, FACE_HOLD_FRAMES=90, RETURN_FRAMES=90,
 parameter SETTLE_FRAMES=60, FACE_TIMEOUT_FRAMES=1800,
 parameter PAN_DOWN_US=1500,TILT_DOWN_US=1500,PAN_FACE_US=1500,TILT_FACE_US=1100
)(input wire clk,rst_n,enable,frame_start,face_valid,source_valid,
 output reg[2:0] phase,output wire face_enable,vision_enable,
 output wire[10:0] pan_us,tilt_us);
 localparam OFF=0,UP=1,WAIT_FACE=2,RECORD=3,DOWN=4,SETTLE=5,ACTIVE=6,FAULT=7;
 reg[10:0] frames;reg[1:0] face_agree;
 assign face_enable=enable && (phase==UP || phase==WAIT_FACE || phase==RECORD);
 assign vision_enable=enable && phase==ACTIVE && source_valid;
 assign pan_us=face_enable?PAN_FACE_US:PAN_DOWN_US;
 assign tilt_us=face_enable?TILT_FACE_US:TILT_DOWN_US;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin phase<=OFF;frames<=0;face_agree<=0;end
  else if(!enable)begin phase<=OFF;frames<=0;face_agree<=0;end
  else if(frame_start)begin
   if(frames!=2047)frames<=frames+1'b1;
   case(phase)
    OFF:begin phase<=UP;frames<=0;end
    UP:if(frames>=FACE_POSE_FRAMES-1)begin phase<=WAIT_FACE;frames<=0;end
    WAIT_FACE:begin
     if(face_valid && source_valid)begin
      if(face_agree==2)begin phase<=RECORD;frames<=0;end
      else face_agree<=face_agree+1'b1;
     end else face_agree<=0;
     if(frames>=FACE_TIMEOUT_FRAMES-1)begin phase<=FAULT;frames<=0;end
    end
    RECORD:if(frames>=FACE_HOLD_FRAMES-1)begin phase<=DOWN;frames<=0;end
    DOWN:if(frames>=RETURN_FRAMES-1)begin phase<=SETTLE;frames<=0;end
    SETTLE:if(frames>=SETTLE_FRAMES-1 && source_valid)begin phase<=ACTIVE;frames<=0;end
    ACTIVE:if(!source_valid)begin phase<=SETTLE;frames<=0;end
    default:begin phase<=FAULT;frames<=0;end
   endcase
  end
 end
endmodule
