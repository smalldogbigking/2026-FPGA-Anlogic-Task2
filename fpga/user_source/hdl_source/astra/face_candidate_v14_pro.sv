// OpenCV LBP 20-stage frontal-face model, Q12 leaves; sequential hardware.
// Single 96x54 integral frame, 5-bit gray, 18-bit summed area. No video stall.
module face_candidate_v14_pro #(parameter WIDTH=1280,HEIGHT=720)(
 input wire clk,rst_n,valid,sof,enable,input wire[11:0] x,y,input wire[23:0] rgb,
 output reg result_valid,output reg[47:0] result_box,output reg[7:0] confidence,
 output reg result_update,output reg[47:0] measurement_box,output reg[7:0] measurement_age
);
 (* ram_style="bram" *) reg[17:0] integral_ram[0:6143];
 reg[17:0] read_data;wire[12:0] scan_addr;wire scan_busy,scan_done,scan_found;
 wire[6:0] bx,by,bsize;
 reg capture,start,wr;reg[2:0] view;wire zoom=view!=0;wire close_view=view==6;reg[12:0] wr_addr;reg[17:0] wr_value;
 reg[11:0] sample_x,sample_y;reg[6:0] gx,gy;reg[1:0] step_x,step_y;
 reg[17:0] row_sum;reg[12:0] count;reg first_row;
 wire sample=capture&&valid&&gy<54&&x==sample_x&&y==sample_y;
 wire[9:0] raw_lum={2'd0,rgb[23:16]}+{1'd0,rgb[15:8],1'b0}+{2'd0,rgb[7:0]};
 // Four-pixel horizontal box prefilter before decimation prevents single
 // Bayer/noise samples from flipping LBP comparisons. No extra image buffer.
 reg[7:0] l0,l1,l2;
 always @(posedge clk)if(valid)begin
 l0<=raw_lum[9:2];l1<=x==0?raw_lum[9:2]:l0;l2<=x<2?raw_lum[9:2]:l1;
 end
 wire[9:0] lum={2'b0,raw_lum[9:2]}+{2'b0,l0}+{2'b0,l1}+{2'b0,l2};
 // Full frame, center, four quadrants, then a closer center view. Freeze the
 // view while detected; this covers small faces outside the old center ROI.
 wire[11:0] origin_x=view==0?0:(view==2||view==4)?0:(view==3||view==5)?640:close_view?480:320;
 wire[11:0] origin_y=view==0?0:(view==2||view==3)?0:(view==4||view==5)?360:close_view?270:180;
 wire[11:0] first_x=origin_x+(close_view?1:zoom?3:6);
 wire[11:0] first_y=origin_y+(close_view?1:zoom?3:6);
 wire[12:0] row_addr=({6'd0,gy}<<6)+({6'd0,gy}<<5)+gx;
 wire[12:0] read_addr=capture?(gy==0?13'd0:row_addr-13'd96):scan_addr;
 always @(posedge clk)begin
  read_data<=integral_ram[read_addr];
  if(wr)integral_ram[wr_addr]<=wr_value+(first_row?18'd0:read_data);
 end
 lbp_cascade_engine_plus engine(clk,rst_n,enable,start,scan_addr,read_data,scan_busy,scan_done,scan_found,bx,by,bsize);
 reg[1:0] stable,misses;reg[6:0] last_x,last_y,last_size;reg[2:0] publish;
 reg[7:0] capture_age,result_age;reg[11:0] measured[0:2];
 reg[11:0] scaled[0:3];reg[7:0] grid_coord;reg[1:0] publish_wait;
 // 13*g+floor(g/3) == floor(40*g/3), evaluated only at elaboration.
 // A single shared synchronous small LUT ROM removes the division and
 // chained additions from the coordinate/filter path. TD maps this small
 // shared table to one ERAM; no extra DSP is required.
 (* ram_style="distributed",rom_style="distributed" *) reg[11:0] coordinate_rom[0:255];
 reg[11:0] full_mapped,measured_coordinate;integer coordinate_index;
 initial for(coordinate_index=0;coordinate_index<256;coordinate_index=coordinate_index+1)
  coordinate_rom[coordinate_index]=(coordinate_index*40)/3;
 always @(posedge clk)full_mapped<=coordinate_rom[grid_coord];
 wire[11:0] mapped=(close_view?(full_mapped>>2):zoom?(full_mapped>>1):full_mapped)+((publish==1||publish==2)?origin_x:origin_y);
 // Four coordinates reuse one inertial filter during serial publication.
 // 3/4-step for movement, half-step for small jitter,3px deadband.
 // Control uses the raw accepted box below, never this display smoothing.
 reg[11:0] previous_coordinate;
 always @*case(publish)
 1:previous_coordinate=result_box[47:36];2:previous_coordinate=result_box[35:24];
 3:previous_coordinate=result_box[23:12];default:previous_coordinate=result_box[11:0];endcase
 wire[11:0] next_measured_coordinate=(publish==2||publish==4)?(mapped==0?12'd0:mapped-12'd1):mapped;
 wire signed[12:0] coordinate_delta=$signed({1'b0,measured_coordinate})-$signed({1'b0,previous_coordinate});
 wire signed[12:0] coordinate_step=(coordinate_delta>24 || coordinate_delta< -24)?(coordinate_delta-(coordinate_delta>>>2)):(coordinate_delta>>>1);
 wire[11:0] filtered_coordinate=!result_valid?measured_coordinate:
 (coordinate_delta>=-3 && coordinate_delta<=3)?previous_coordinate:previous_coordinate+coordinate_step;
 // Require two separate captured images with a nearby grouped candidate.
 // Never drive the controller from an interpolated display coordinate.
 wire nearby=(bx+8'd10>=last_x)&&(last_x+8'd10>=bx)&&(by+8'd10>=last_y)&&(last_y+8'd10>=by)&&
             (bsize+8'd12>=last_size)&&(last_size+8'd12>=bsize);
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin capture<=0;start<=0;wr<=0;view<=0;sample_x<=6;sample_y<=6;gx<=0;gy<=0;step_x<=0;step_y<=0;row_sum<=0;count<=0;wr_addr<=0;wr_value<=0;first_row<=1;result_valid<=0;result_box<=0;confidence<=0;stable<=0;misses<=0;last_x<=0;last_y<=0;publish<=0;publish_wait<=0;measured_coordinate<=0;grid_coord<=0;result_update<=0;measurement_box<=0;measurement_age<=0;capture_age<=0;result_age<=0;last_size<=0;end
  else begin
   start<=0;wr<=0;result_update<=0;
   if(!enable)begin view<=0;capture<=0;result_valid<=0;confidence<=0;stable<=0;misses<=0;publish<=0;publish_wait<=0;capture_age<=0;result_age<=0;end
   else begin
    if(sof)begin
     if(capture_age!=255)capture_age<=capture_age+1'b1;
     if(result_age!=255)result_age<=result_age+1'b1;
     if(result_age>=30)begin result_valid<=0;confidence<=0;end
    end
    if(sof&&!capture&&!scan_busy&&!scan_done&&publish==0)begin capture<=1;capture_age<=0;sample_x<=first_x;sample_y<=first_y;gx<=0;gy<=0;step_x<=0;step_y<=0;row_sum<=0;count<=0;end
    if(sample)begin
     wr<=1;wr_addr<=row_addr;first_row<=gy==0;wr_value<=row_sum+lum[9:5];row_sum<=row_sum+lum[9:5];count<=count+1'b1;
     if(gx==95)begin gx<=0;gy<=gy+1'b1;sample_x<=first_x;step_x<=0;row_sum<=0;sample_y<=sample_y+(close_view?(step_y==2?4:3):zoom?(step_y==0?6:7):(step_y==2?14:13));step_y<=step_y==2?0:step_y+1'b1;end
     else begin gx<=gx+1'b1;sample_x<=sample_x+(close_view?(step_x==2?4:3):zoom?(step_x==0?6:7):(step_x==2?14:13));step_x<=step_x==2?0:step_x+1'b1;end
    end
    if(capture&&valid&&x==WIDTH-1&&y==HEIGHT-1)begin capture<=0;if(count==5184)start<=1;end
    if(scan_done)begin
     if(scan_found)begin
      last_x<=bx;last_y<=by;last_size<=bsize;misses<=0;stable<=nearby?(stable==3?3:stable+1'b1):1;
      if(stable!=0 && nearby && capture_age<=15)begin publish<=1;publish_wait<=0;grid_coord<={1'b0,bx};end
     end else begin if(!result_valid || misses==1)view<=view==6?0:view+1'b1;stable<=0;if(misses>=1)begin result_valid<=0;confidence<=0;end else misses<=misses+1'b1;end
    end
    // Three clocks per coordinate: ROM read, geometry register, filter.
    // All four output coordinates still commit together in twelve clocks.
    if(publish!=0)begin
     if(publish_wait==0)publish_wait<=1;
     else if(publish_wait==1)begin measured_coordinate<=next_measured_coordinate;publish_wait<=2;end
     else begin
      publish_wait<=0;
    case(publish)
     1:begin scaled[3]<=filtered_coordinate;measured[2]<=measured_coordinate;grid_coord<={1'b0,bx}+{1'b0,bsize};publish<=2;end
     2:begin scaled[2]<=filtered_coordinate;measured[1]<=measured_coordinate;grid_coord<={1'b0,by};publish<=3;end
     3:begin scaled[1]<=filtered_coordinate;measured[0]<=measured_coordinate;grid_coord<={1'b0,by}+{1'b0,bsize};publish<=4;end
     4:begin result_box<={scaled[3],scaled[2],scaled[1],filtered_coordinate};result_valid<=1;confidence<=8'd200;result_age<=0;measurement_box<={measured[2],measured[1],measured[0],measured_coordinate};measurement_age<=capture_age;result_update<=1;publish<=0;end
    endcase
     end
    end
   end
  end
 end
endmodule

module lbp_cascade_engine_plus(
 input wire clk,rst_n,enable,start,output reg[12:0] address,input wire[17:0] data,
 output reg busy,done,found,output reg[6:0] best_x,best_y,best_size
);
 (* ram_style="bram" *) reg[66:0] nodes[0:255];
 (* ram_style="bram" *) reg[31:0] masks[0:1535];
 initial begin
  $readmemh("../user_source/hdl_source/astra/face_lbp_nodes.hex",nodes);
  $readmemh("../user_source/hdl_source/astra/face_lbp_masks.hex",masks);
 end
 reg[7:0] node_index;reg[66:0] node_q,meta;reg[31:0] mask_q;
 reg[7:0] code;reg[2:0] scale;reg[6:0] wx,wy,win,fx,fy,fw,fh,cx,cy;
 reg[4:0] state;reg[3:0] corner;reg zero_corner;reg[17:0] corners[0:15];
 reg[3:0] cell_index;reg[2:0] neighbor;
 reg[18:0] plus_sum,minus_sum;reg[18:0] center,cell_sum;
 reg signed[19:0] score,total;
 // Group neighbouring full-cascade hits. A single isolated passing window
 // no longer becomes a target; only a confirmed spatial cluster is published.
 reg candidate_seen;reg[6:0] candidate_x,candidate_y,candidate_size;
 wire grouped_hit=candidate_seen && candidate_size==win &&
 (wx+8'd4>=candidate_x)&&(candidate_x+8'd4>=wx)&&
 (wy+8'd4>=candidate_y)&&(candidate_y+8'd4>=wy);
 function[6:0] scaled;input[4:0] v;input[2:0] s;reg[8:0] t;begin
 case(s)0:t={4'd0,v}<<2;1:t=({4'd0,v}<<2)+v+2;2:t=({4'd0,v}<<2)+({4'd0,v}<<1)+2;3:t=({4'd0,v}<<3)-v+2;default:t={4'd0,v}<<3;endcase
 scaled=t[8:2];end endfunction
 function[3:0] ring;input[2:0] n;begin case(n)0:ring=0;1:ring=1;2:ring=2;3:ring=6;4:ring=10;5:ring=9;6:ring=8;default:ring=4;endcase end endfunction
 always @(posedge clk)begin node_q<=nodes[node_index];mask_q<=masks[{node_index,code[7:5]}];end
 always @*begin
 case(corner[1:0])0:cx=wx+fx;1:cx=wx+fx+fw;2:cx=wx+fx+(fw<<1);3:cx=wx+fx+(fw<<1)+fw;endcase
 case(corner[3:2])0:cy=wy+fy;1:cy=wy+fy+fh;2:cy=wy+fy+(fh<<1);3:cy=wy+fy+(fh<<1)+fh;endcase
 end
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin state<=0;busy<=0;done<=0;found<=0;best_x<=0;best_y<=0;best_size<=0;node_index<=0;address<=0;meta<=0;code<=0;scale<=0;wx<=0;wy<=0;win<=24;fx<=0;fy<=0;fw<=0;fh<=0;corner<=0;zero_corner<=0;cell_index<=0;neighbor<=0;plus_sum<=0;minus_sum<=0;center<=0;cell_sum<=0;score<=0;total<=0;candidate_seen<=0;candidate_x<=0;candidate_y<=0;candidate_size<=0;end
 else begin done<=0;
 if(!enable)begin busy<=0;state<=0;found<=0;end
 else case(state)
 0:if(start)begin busy<=1;found<=0;best_size<=0;candidate_seen<=0;scale<=0;wx<=0;wy<=0;win<=24;node_index<=0;score<=0;state<=1;end
 1:state<=2;
 2:begin meta<=node_q;state<=3;end
 3:begin fx<=scaled(meta[36:32],scale);state<=4;end
 4:begin fy<=scaled(meta[41:37],scale);state<=5;end
 5:begin fw<=scaled({1'b0,meta[45:42]},scale);state<=6;end
 6:begin fh<=scaled({1'b0,meta[49:46]},scale);corner<=0;state<=7;end
 7:begin zero_corner<=cx==0||cy==0||cx>96||cy>54;address<=((cy-13'd1)<<6)+((cy-13'd1)<<5)+cx-13'd1;state<=8;end
 8:state<=9;
 9:begin corners[corner]<=zero_corner?18'd0:data;if(corner==15)begin cell_index<=5;neighbor<=0;state<=10;end else begin corner<=corner+1'b1;state<=7;end end
 10:begin plus_sum<={1'b0,corners[cell_index]}+{1'b0,corners[cell_index+5]};minus_sum<={1'b0,corners[cell_index+1]}+{1'b0,corners[cell_index+4]};state<=11;end
 11:begin cell_sum<=plus_sum-minus_sum;state<=12;end
 12:begin
   if(cell_index==5)begin center<=cell_sum;cell_index<=0;neighbor<=0;state<=10;end
   else begin code[7-neighbor]<=cell_sum>=center;if(neighbor==7)state<=13;else begin neighbor<=neighbor+1'b1;cell_index<=ring(neighbor+3'd1);state<=10;end end
  end
 13:state<=14;
 14:begin total<=score+(mask_q[code[4:0]]?$signed(meta[15:0]):$signed(meta[31:16]));state<=15;end
 15:begin
  if(meta[50]&&total<$signed(meta[66:51]))state<=17;
  else if(node_index==138)begin
   candidate_seen<=1;candidate_x<=wx;candidate_y<=wy;candidate_size<=win;
   // A lone full 20-stage hit can seed temporal confirmation. Prefer a
   // spatial group when present, but do not require both spatial AND
   // temporal agreement for small faces with only one passing window.
   if((!found) || (grouped_hit && win>=best_size))begin found<=1;best_x<=wx;best_y<=wy;best_size<=win;end
   state<=17;
  end else begin score<=meta[50]?20'sd0:total;node_index<=node_index+1'b1;state<=1;end
 end
 17:begin
  node_index<=0;score<=0;
  if(wx+win+1<=96)begin wx<=wx+1;state<=1;end
  else if(wy+win+1<=54)begin wx<=0;wy<=wy+1;state<=1;end
  else if(scale<4)begin wx<=0;wy<=0;scale<=scale+1'b1;win<=win+6;state<=1;end
  else begin busy<=0;done<=1;state<=0;end
 end
 default:state<=0;
 endcase
 end end
endmodule
