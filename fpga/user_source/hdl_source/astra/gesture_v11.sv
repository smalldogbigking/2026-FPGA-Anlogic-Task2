// Skin-independent edge-to-silhouette hand front end for a clean background.
// The old two-border interpolation treated curved wall shading as a hand.
// Here a slowly following row background freezes only on a local contour edge.
// Median filtering rejects isolated pixels; filled edge pairs preserve fingers.
module gesture_gray_frontend_v11(
 input wire clk,rst_n,valid,sof,enable,input wire[11:0] x,y,input wire[23:0] rgb,
 output reg foreground,output wire out_valid,out_sof,out_enable,
 output wire[11:0] out_x,out_y,output reg[7:0] background_level,foreground_threshold
);
 wire[9:0] lum_sum={2'd0,rgb[23:16]}+{1'd0,rgb[15:8],1'b0}+{2'd0,rgb[7:0]};
 wire[7:0] lum=lum_sum[9:2];
 wire signed[8:0] chroma=$signed({1'b0,rgb[23:16]})-$signed({1'b0,rgb[7:0]});
 function[7:0] med3;input[7:0]a,b,c;
 begin med3=a>b?(b>c?b:(a>c?c:a)):(a>c?a:(b>c?c:b));end endfunction
 function signed[8:0] medc;input signed[8:0]a,b,c;
 begin medc=a>b?(b>c?b:(a>c?c:a)):(a>c?a:(b>c?c:b));end endfunction
 reg[7:0] h0,h1,a1,b1,c1,median2;
 reg signed[8:0] ch0,ch1,ca1,cb1,cc1,chmed;
 reg[26:0] meta1,meta2,meta3;
 reg[7:0] history_y[0:3];reg signed[8:0] history_c[0:3];
 reg signed[12:0] bg_y_q4;reg signed[13:0] bg_c_q4;
 reg contour_active,entry_chroma,entry_positive;reg[2:0] settle;
 wire signed[12:0] y_error=$signed({1'b0,median2,4'b0})-bg_y_q4;
 wire signed[13:0] c_error=$signed({chmed[8],chmed,4'b0})-bg_c_q4;
 wire signed[9:0] dy=$signed({1'b0,median2})-$signed(bg_y_q4>>>4);
 wire signed[10:0] dc=$signed(chmed)-$signed(bg_c_q4>>>4);
 wire signed[9:0] edge_y=$signed({1'b0,median2})-$signed({1'b0,history_y[3]});
 wire signed[9:0] edge_c=$signed(chmed)-$signed(history_c[3]);
 wire edge_hit=edge_y>=10 || edge_y<=-10 || edge_c>=18 || edge_c<=-18;
 wire departed=dy>=12 || dy<=-12 || dc>=20 || dc<=-20;
 wire opposite_edge=entry_chroma?(entry_positive?edge_c<=-18:edge_c>=18):(entry_positive?edge_y<=-10:edge_y>=10);
 wire near_background=dy<16 && dy>-16 && dc<18 && dc>-18;
 wire edge_closure=contour_active && opposite_edge && dy<40 && dy>-40 && dc<48 && dc>-48;
 wire returned=near_background || edge_closure;
 wire entering=edge_hit && departed && settle==0;
 assign {out_valid,out_sof,out_enable,out_x,out_y}=meta3;
 integer i;
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 h0<=0;h1<=0;a1<=0;b1<=0;c1<=0;median2<=0;
 ch0<=0;ch1<=0;ca1<=0;cb1<=0;cc1<=0;chmed<=0;
 meta1<=0;meta2<=0;meta3<=0;foreground<=0;contour_active<=0;entry_chroma<=0;entry_positive<=0;settle<=0;
 bg_y_q4<=13'sd2048;bg_c_q4<=0;background_level<=128;foreground_threshold<=12;
 for(i=0;i<4;i=i+1)begin history_y[i]<=0;history_c[i]<=0;end
 end else begin
 if(valid)begin
 h0<=lum;h1<=x==0?lum:h0;ch0<=chroma;ch1<=x==0?chroma:ch0;
 end
 a1<=lum;b1<=h0;c1<=h1;ca1<=chroma;cb1<=ch0;cc1<=ch1;
 median2<=meta1[23:12]>=2?med3(a1,b1,c1):a1;
 chmed<=meta1[23:12]>=2?medc(ca1,cb1,cc1):ca1;
 meta1<={valid,sof,enable,x,y};meta2<=meta1;meta3<=meta2;
 foreground<=0;
 if(meta2[26])begin
 for(i=3;i>0;i=i-1)begin history_y[i]<=history_y[i-1];history_c[i]<=history_c[i-1];end
 history_y[0]<=median2;history_c[0]<=chmed;
 if(!meta2[24] || meta2[23:12]<32)begin
 contour_active<=0;settle<=0;bg_y_q4<=$signed({1'b0,median2,4'b0});bg_c_q4<=$signed({chmed[8],chmed,4'b0});
 end else begin
 // Hysteresis avoids thin holes due to quantisation while local median
 // suppresses impulses. Do not let isolated gradient noise accumulate.
 foreground<=(contour_active || entering) && !returned;
 if(settle!=0)settle<=settle-1'b1;
 if(returned)begin
 contour_active<=0;
 if(contour_active)begin settle<=5;bg_y_q4<=$signed({1'b0,median2,4'b0});bg_c_q4<=$signed({chmed[8],chmed,4'b0});end
 end else if(entering)begin
 contour_active<=1;
 if(!contour_active)begin
 entry_chroma<=!(edge_y>=10 || edge_y<=-10);
 entry_positive<=(edge_y>=10 || edge_y<=-10)?edge_y>=0:edge_c>=0;
 end
 end
 if(!contour_active && !entering)begin
 bg_y_q4<=bg_y_q4+(y_error>>>4);bg_c_q4<=bg_c_q4+(c_error>>>4);
 end
 if(meta2[23:12]==64)background_level<=bg_y_q4[11:4];
 end
 end
 end end
endmodule

module gesture_v11(
 input wire clk,rst_n,valid,sof,enable,input wire[11:0] x,y,input wire[23:0] rgb,
 output wire result_valid,output wire[2:0] gesture,output wire[47:0] box
);
 wire foreground,v,s,e;wire[11:0]px,py;wire[7:0]bg,threshold;
 gesture_gray_frontend_v11 front(clk,rst_n,valid,sof,enable,x,y,rgb,foreground,v,s,e,px,py,bg,threshold);
 gesture_v11_edge_core core(.pre_foreground(foreground),.clk(clk),.rst_n(rst_n),
 .valid(v),.sof(s),.enable(e),.x(px),.y(py),.rgb(24'd0),
 .result_valid(result_valid),.gesture(gesture),.box(box));
endmodule
module gesture_v11_edge_core(
 input wire pre_foreground,
 input wire clk,rst_n,valid,sof,enable,input wire [11:0] x,y,
 input wire [23:0] rgb,output reg result_valid,output reg [2:0] gesture,
 output reg [47:0] box
);
 reg mask[0:4095]; // synthesis ram_style=bram
 reg mask_pixel,mask_inside;wire pixel=mask_inside?mask_pixel:1'b0;
 reg [11:0] rdaddr;reg [4:0] state;
 wire foreground=pre_foreground;
 reg capture_frame;
 wire in_roi=valid && enable && capture_frame && x<1280 && y<720 && state==0;
 // 128 x 30 uses the SAME 4096-cell RAM as the previous 64 x 45 grid.
 // Ten-pixel horizontal cells keep adjacent real fingers separate.
 reg[3:0] within_x;reg[6:0] cell_x;
 reg[4:0] within_y,cell_y;
 wire[3:0] sub_x=x==0?0:within_x;
 wire[4:0] sub_y=y==0?0:within_y;
 wire[6:0] px=x==0?0:cell_x;wire[4:0] py=y==0?0:cell_y;
 wire sample=in_roi && sub_x==9 && sub_y==23;
 reg[3:0] row_foreground;
 reg[7:0] block_columns[0:127]; // synthesis ram_style=bram
 reg[7:0] column_sum;
 wire[7:0] row_total={4'd0,row_foreground}+foreground;
 wire[7:0] block_total=(sub_y==0)?row_total:column_sum+row_total;
 wire block_foreground=block_total>=78 && py<30;
 always @(posedge clk)begin
  if(in_roi && sub_x==0)column_sum<=block_columns[px];
  if(in_roi && sub_x==9)block_columns[px]<=block_total;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin row_foreground<=0;within_x<=0;cell_x<=0;within_y<=0;cell_y<=0;end
  else if(in_roi)begin
   if(sub_x==0)row_foreground<=foreground;else if(sub_x!=9)row_foreground<=row_foreground+foreground;
   if(x==0)begin within_x<=1;cell_x<=0;end
   else if(sub_x==9)begin within_x<=0;cell_x<=cell_x+1'b1;end
   else within_x<=sub_x+1'b1;
   if(x==1279)begin
    if(y==0)begin within_y<=1;cell_y<=0;end
    else if(sub_y==23)begin within_y<=0;cell_y<=cell_y+1'b1;end
    else within_y<=sub_y+1'b1;
   end
  end
 end
 reg [6:0] xmin,xmax,sx;reg[4:0] ymin,ymax,sy,stop_y;
 reg[1:0] miss_count;reg [12:0] area;reg [7:0] run_length;reg [3:0] runs;
 reg [7:0] peak_run;reg [5:0] narrow_rows;
 reg [5:0] votes[0:5];reg [2:0] best,candidate,last_candidate;reg [1:0] stable;
 reg [47:0] captured_box;integer i;
 reg visited[0:4095]; // synthesis ram_style=bram
 reg [11:0] queue[0:4095]; // synthesis ram_style=bram
 reg seen;reg [11:0] qread,current,scan_addr,clear_addr;
 reg [12:0] head,tail,component_area,best_area;
 reg [6:0] cxl,cxh,bxl,bxh;reg[4:0] cyl,cyh,byl,byh;reg [1:0] direction;
 wire new_component=(state==9 && pixel && !seen);
 wire add_neighbor=(state==14 && pixel && !seen && tail<4096);
 wire [11:0] queue_write_addr=new_component?12'd0:tail[11:0];
 wire visited_write=rst_n&&(state==6||new_component||add_neighbor);
 wire[11:0] visited_write_addr=state==6?clear_addr:rdaddr;
 always @(posedge clk)begin
  seen<=visited[rdaddr];qread<=queue[head[11:0]];
  if(new_component || add_neighbor)queue[queue_write_addr]<=rdaddr;
  // Same write clocks/data as the FSM, expressed as a synchronous RAM port.
  if(visited_write)visited[visited_write_addr]<=state!=6;
 end
 wire contour_exit=state==3 && !(pixel && sx>=xmin && sx<=xmax) && run_length>=1;
 wire [3:0] completed_runs=runs+((run_length>=1)?1'b1:1'b0);
 always @(posedge clk)begin
  if(sample)mask[{py,px}]<=block_foreground;
  // Only 30 frame rows are written. The remaining square-memory rows must
  // read as background, otherwise uninitialised RAM creates phantom hands.
  // Keep the address guard OUTSIDE the synchronous RAM read. Both the
  // data and guard register on the same edge, so pixel latency is unchanged.
  mask_pixel<=mask[rdaddr];mask_inside<=rdaddr[11:7]<30;
 end
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin capture_frame<=0;head<=0;tail<=0;component_area<=0;best_area<=0;current<=0;scan_addr<=0;clear_addr<=0;cxl<=0;cxh<=0;cyl<=0;cyh<=0;bxl<=0;bxh<=0;byl<=0;byh<=0;direction<=0;state<=0;rdaddr<=0;xmin<=127;xmax<=0;ymin<=31;ymax<=0;area<=0;sx<=0;sy<=0;stop_y<=0;peak_run<=0;narrow_rows<=0;run_length<=0;runs<=0;best<=0;candidate<=0;last_candidate<=0;stable<=0;result_valid<=0;gesture<=0;box<=0;captured_box<=0;miss_count<=0;for(i=0;i<6;i=i+1)votes[i]<=0;end
  else begin
   if(sof)capture_frame<=enable && state==0;
   if(sof && state==0)begin xmin<=127;xmax<=0;ymin<=31;ymax<=0;area<=0;if(!enable)begin result_valid<=0;stable<=0;miss_count<=0;end end
   if(sample && block_foreground)begin area<=area+1'b1;if(px<xmin)xmin<=px;if(px>xmax)xmax<=px;if(py<ymin)ymin<=py;if(py>ymax)ymax<=py;end
   case(state)
    0:if(enable && capture_frame && valid && x==1279 && y==719)begin
     if(area>=28 && area<2600)begin clear_addr<=0;best_area<=0;state<=6;end
     else begin stable<=0;if(miss_count>=2)result_valid<=0;else miss_count<=miss_count+1'b1;end
    end
    6:begin if(clear_addr==4095)begin scan_addr<=0;state<=7;end else clear_addr<=clear_addr+1'b1;end
    7:begin rdaddr<=scan_addr;state<=8;end
    8:state<=9;
    9:begin
     if(pixel && !seen)begin
      head<=0;tail<=1;component_area<=1;
      cxl<=rdaddr[6:0];cxh<=rdaddr[6:0];cyl<=rdaddr[11:7];cyh<=rdaddr[11:7];state<=10;
     end else if(scan_addr==4095)state<=17;
     else begin scan_addr<=scan_addr+1'b1;state<=7;end
    end
    10:if(head<tail)state<=11;else state<=16;
    11:begin current<=qread;head<=head+1'b1;direction<=0;state<=12;end
    12:begin
     case(direction)
      0:if(current[6:0]!=0)begin rdaddr<=current-1'b1;state<=13;end else state<=15;
      1:if(current[6:0]!=127)begin rdaddr<=current+1'b1;state<=13;end else state<=15;
      2:if(current[11:7]!=0)begin rdaddr<=current-12'd128;state<=13;end else state<=15;
      3:if(current[11:7]!=31)begin rdaddr<=current+12'd128;state<=13;end else state<=15;
     endcase
    end
    13:state<=14;
    14:begin
     if(pixel && !seen && tail<4096)begin
      tail<=tail+1'b1;component_area<=component_area+1'b1;
      if(rdaddr[6:0]<cxl)cxl<=rdaddr[6:0];if(rdaddr[6:0]>cxh)cxh<=rdaddr[6:0];
      if(rdaddr[11:7]<cyl)cyl<=rdaddr[11:7];if(rdaddr[11:7]>cyh)cyh<=rdaddr[11:7];
     end
     state<=15;
    end
    15:if(direction==3)state<=10;else begin direction<=direction+1'b1;state<=12;end
    16:begin
     if(component_area>best_area)begin best_area<=component_area;bxl<=cxl;bxh<=cxh;byl<=cyl;byh<=cyh;end
     if(scan_addr==4095)state<=17;else begin scan_addr<=scan_addr+1'b1;state<=7;end
    end
    17:begin
     // A real hand's wrist often continues into the bottom frame border.
     // Rejecting the last active row made ordinary raised hands disappear completely.
     if(best_area>=28 && bxh>bxl+7 && byh>byl+3 && bxl>2 && bxh<125 && byl>0 && byh<30)begin
      xmin<=bxl;xmax<=bxh;ymin<=byl;ymax<=byh;
      narrow_rows<=0;peak_run<=0;sy<=byl+1;stop_y<=byl+((byh-byl)>>1);sx<=0;run_length<=0;runs<=0;
      captured_box<={(({5'd0,bxl}<<3)+({5'd0,bxl}<<1)),(({5'd0,bxh}<<3)+({5'd0,bxh}<<1)+12'd9),(({7'd0,byl}<<4)+({7'd0,byl}<<3)),(({7'd0,byh}<<4)+({7'd0,byh}<<3)+12'd23)};
      for(i=0;i<6;i=i+1)votes[i]<=0;state<=1;
     end else begin stable<=0;state<=0;if(miss_count>=2)result_valid<=0;else miss_count<=miss_count+1'b1;end
    end
    1:begin rdaddr<={sy,sx};state<=2;end
    2:state<=3;
    3:begin
     if(pixel && sx>=xmin && sx<=xmax)begin
      run_length<=run_length+1'b1;
      if(run_length+1'b1>peak_run)peak_run<=run_length+1'b1;
     end
     else begin run_length<=0;if(contour_exit && runs<7)runs<=runs+1'b1;end
     if(sx==127)begin
      if(completed_runs==1 && {peak_run,1'b0}<=({1'b0,xmax}-{1'b0,xmin}+1))narrow_rows<=narrow_rows+1'b1;
      peak_run<=0;
      if(completed_runs>=1 && completed_runs<=5)votes[completed_runs]<=votes[completed_runs]+1'b1;
      run_length<=0;runs<=0;sx<=0;
      if(sy==stop_y)begin best<=1;state<=4;end else begin sy<=sy+1'b1;state<=1;end
     end else begin sx<=sx+1'b1;state<=1;end
    end
    4:begin
     // Require support from several rows to reject random foreground speckles.
     if(votes[5]>=2 || votes[4]>=2 || votes[3]>=2)candidate<=3; // OPEN
     else if(votes[2]>=2)candidate<=2; // V/TWO
     else if(votes[1]>=2)candidate<=(narrow_rows>=2)?1:4; // POINT/FIST
     else candidate<=0;
     state<=5;
    end
    5:begin
     last_candidate<=candidate;
     if(candidate!=0 && candidate==last_candidate)begin
      miss_count<=0;
      if(stable<3)stable<=stable+1'b1;
      if(stable>=1)begin result_valid<=1;gesture<=candidate;box<=captured_box;end
     end else begin stable<=0;if(candidate==0)begin if(miss_count>=2)result_valid<=0;else miss_count<=miss_count+1'b1;end end
     state<=0;
    end
    default:state<=0;
   endcase
  end
 end
endmodule
