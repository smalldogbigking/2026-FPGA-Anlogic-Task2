// Pixel-aligned 720p overlay. x/y/rgb/de must describe the SAME input beat.
// Register glyph selection before the synchronous font ROM, then paint.
// Four registered stages delay RGB and vs/hs/de/user/last together.
// Requires the unchanged example ROMs anlogic_logo_rom and osd_char_lib.
module osd_overlay_v4 (
 input wire remote_control,input wire[2:0] sort_phase,input wire[11:0] sort_digits,sort_classes,
 input wire[19:0] pan_hz_bcd,tilt_hz_bcd,pan_duty_bcd,tilt_duty_bcd,
 input wire[7:0] target_valid,input wire[383:0] target_boxes,input wire[15:0] target_shapes,
 input wire digit_valid,input wire[2:0] digit_value,input wire[47:0] digit_box,
 input wire clk,rst_n,
 input wire in_vs,in_hs,in_de,in_user,in_last,
 input wire [11:0] in_x,in_y,
 input wire [23:0] in_rgb,
 input wire [3:0] mode,
 input wire [1:0] quality_preset,fps_preset,input wire beauty,input wire[1:0] red_shape,green_shape,input wire[7:0] processing_us,
 input wire [7:0] content_fps_bcd, // tens, units; real frame updates/s
 input wire [11:0] latency_ms_bcd, // hundreds, tens, units
 input wire latency_valid,
 input wire [11:0] cnt_bcd,
 input wire red_box_valid,
 input wire [47:0] red_box, // xmin,xmax,ymin,ymax, each 12 bits
 input wire green_box_valid,
 input wire [47:0] green_box,
 output reg out_vs,out_hs,out_de,out_user,out_last,
 output reg [23:0] out_rgb,
 input wire face_track,gesture_valid,input wire[2:0] gesture_value,
 input wire face_valid,input wire[7:0] face_confidence,input wire[47:0] face_box,
 input wire[1:0] correction_mode,center_seconds,photo_status,
 input wire calibration_busy,calibration_valid,input wire[15:0] exposure_status,wb_status,
 input wire[11:0] motion_count,input wire[7:0] gain_status,tone_status,scene_mean,photo_error
);
 function [7:0] digit;
 input [3:0] d;
 begin digit=(d<=9)?(8'h30+d):8'h20; end
 endfunction
 function[3:0] compact_mode;input[3:0] m;begin
 case(m)0,1,2:compact_mode=m;4:compact_mode=3;5:compact_mode=4;6:compact_mode=5;7:compact_mode=6;
 8:compact_mode=7;9:compact_mode=8;10:compact_mode=9;12:compact_mode=10;13:compact_mode=11;15:compact_mode=12;
 default:compact_mode=0;endcase end endfunction
 wire[3:0] display_mode=compact_mode(mode);
 function [7:0] hexchar;input[3:0] h;begin hexchar=h<10?8'd48+h:8'd65+h-10;end endfunction

 function [7:0] name_char;
 input [3:0] m;
 input [2:0] idx;
 begin
 name_char=8'h20;
 case(m)
 0:case(idx)0:name_char="R";1:name_char="A";2:name_char="W";endcase
 1:case(idx)0:name_char="G";1:name_char="R";2:name_char="A";3:name_char="Y";endcase
 2:case(idx)0:name_char="N";1:name_char="E";2:name_char="G";endcase
 3:case(idx)0:name_char="R";1:name_char="A";2:name_char="W";endcase
 4:case(idx)0:name_char="H";1:name_char="E";2:name_char="A";3:name_char="T";endcase
 5:case(idx)0:name_char="S";1:name_char="O";2:name_char="B";3:name_char="E";4:name_char="L";endcase
 6:case(idx)0:name_char="C";1:name_char="A";2:name_char="R";3:name_char="T";4:name_char="O";5:name_char="O";6:name_char="N";endcase
 7:case(idx)0:name_char="N";1:name_char="E";2:name_char="O";3:name_char="N";endcase
 8:case(idx)0:name_char="D";1:name_char="I";2:name_char="G";3:name_char="I";4:name_char="T";endcase
 9:case(idx)0:name_char="M";1:name_char="O";2:name_char="T";3:name_char="I";4:name_char="O";5:name_char="N";endcase
 10:case(idx)0:name_char="T";1:name_char="R";2:name_char="A";3:name_char="C";4:name_char="K";endcase
 12:case(idx)0:name_char="F";1:name_char="A";2:name_char="C";3:name_char="E";endcase
 13:case(idx)0:name_char="S";1:name_char="O";2:name_char="R";3:name_char="T";endcase
 11,14:case(idx)0:name_char="R";1:name_char="E";2:name_char="S";3:name_char="E";4:name_char="R";5:name_char="V";6:name_char="E";endcase
 15:case(idx)0:name_char="R";1:name_char="E";2:name_char="M";3:name_char="O";4:name_char="T";5:name_char="E";endcase
 endcase
 end
 endfunction
 // A blanking-time formatter writes a double-buffered character map.
 // Raster logic only reads character RAM and ONE shared synchronous font ROM.
 // RGB, boxes, logo and all five raster flags still use FOUR registered clocks.
 wire logo_area=in_x<160 && in_y<160;
 wire[14:0]logo_addr=(in_y<<7)+(in_y<<5)+in_x;wire[1:0]logo_pixel;
 logo_palette_v4 logo(clk,logo_area?logo_addr:15'd0,logo_pixel);
 wire[255:0] centers_bcd;wire[3:0]target_count;
 reg centers_start;always @(posedge clk or negedge rst_n)if(!rst_n)centers_start<=0;else centers_start<=in_user;
 target_centers_v8 #(.SLOTS(4)) centers(clk,rst_n,centers_start,target_valid,target_boxes,centers_bcd,target_count);
 wire[11:0] motion_bcd;wire motion_bcd_ready;
 metric_bcd_v4 motion_fmt(clk,rst_n,centers_start,motion_count>999?10'd999:motion_count[9:0],motion_bcd,motion_bcd_ready);

 reg[9:0]build_addr;reg[7:0]settle;reg busy,display_bank,write_bank,hud_ready;
 reg[4:0] build_row,build_col;reg[1:0] object_shape;reg[31:0] object_center;
 reg[19:0] freq_bcd,duty_bcd;
 reg[7:0] build_char;
 always @*begin
 build_row=build_addr[9:5];build_col=build_addr[4:0];
 object_shape=0;object_center=0;freq_bcd=0;duty_bcd=0;build_char=8'h20;
 case(build_row)
 0:case(build_col)
 0:build_char="M";1:build_char="O";2:build_char="D";3:build_char="E";4:build_char=":";
 5:build_char=display_mode>=10?"1":" ";6:build_char=digit(display_mode>=10?display_mode-10:display_mode);
 16:build_char=remote_control?"U":" ";17:build_char=remote_control?"S":" ";18:build_char=remote_control?"B":" ";
 default:if(build_col>=8 && build_col<15)build_char=name_char(mode,build_col-8);
 endcase
 1:case(build_col)
 0:build_char="F";1:build_char=digit(content_fps_bcd[7:4]);2:build_char=digit(content_fps_bcd[3:0]);
 4:build_char="S";5:build_char="E";6:build_char="T";7:build_char=fps_preset==0?"6":fps_preset==1?"3":"1";8:build_char=fps_preset==2?"5":"0";
 10:build_char=quality_preset==0?"7":quality_preset==1?"3":"1";
 11:build_char=quality_preset==0?"2":quality_preset==1?"6":"8";12:build_char="0";13:build_char="P";
 endcase
 2:case(build_col)
 0:build_char="D";1:build_char=latency_valid?digit(latency_ms_bcd[11:8]):"-";2:build_char=latency_valid?digit(latency_ms_bcd[7:4]):"-";3:build_char=latency_valid?digit(latency_ms_bcd[3:0]):"-";
 4:build_char="M";5:build_char="S";7:build_char="K";8:build_char="2";9:build_char=":";
 10:build_char=correction_mode==0?"O":correction_mode==1?"A":"F";11:build_char=correction_mode==0?"F":correction_mode==1?"U":"I";12:build_char=correction_mode==0?"F":correction_mode==1?"T":"X";13:build_char=correction_mode==1?"O":" ";
 endcase
 3:if(beauty)case(build_col)
 0:build_char="C";1:build_char="A";2:build_char="L";3:build_char=":";
 5:build_char=calibration_busy?"W":calibration_valid?"O":"-";6:build_char=calibration_busy?"A":calibration_valid?"K":"-";
 7:build_char=calibration_busy?"I":" ";8:build_char=calibration_busy?"T":" ";
 endcase
 4:if(mode==13)case(build_col)
 0:build_char="P";1:build_char="H";2:build_char="A";3:build_char="S";4:build_char="E";6:build_char=digit({1'b0,sort_phase});
 8:build_char=sort_phase==6?"R":"W";9:build_char=sort_phase==6?"U":"A";10:build_char=sort_phase==6?"N":"I";11:build_char=sort_phase==6?" ":"T";
 endcase else if(mode==10)case(build_col)
 0:build_char="T";1:build_char="A";2:build_char="R";3:build_char="G";4:build_char="E";5:build_char="T";6:build_char="S";7:build_char=":";9:build_char=digit(target_count);
 endcase else if(mode==8)case(build_col)
 0:build_char="D";1:build_char="I";2:build_char="G";3:build_char="I";4:build_char="T";5:build_char=":";7:build_char=digit_valid?digit({1'b0,digit_value}):"-";
 endcase else if(mode==9)case(build_col)
 0:build_char="M";1:build_char="O";2:build_char="T";3:build_char="I";4:build_char="O";5:build_char="N";6:build_char=":";
 8:build_char=digit(motion_bcd[11:8]);9:build_char=digit(motion_bcd[7:4]);10:build_char=digit(motion_bcd[3:0]);
 endcase  else if(mode==12)case(build_col)
 0:build_char="F";1:build_char="A";2:build_char="C";3:build_char="E";5:build_char=face_valid?"O":"-";6:build_char=face_valid?"K":"-";
 endcase
 5,6,7,8:if((mode==10 || mode==13) && target_valid[build_row-5])begin
 object_shape=target_shapes[(build_row-5)*2+:2];object_center=centers_bcd[(build_row-5)*32+:32];
 case(build_col)
 0:build_char="R";1:build_char=digit(build_row-4);
 3:build_char=object_shape==1?"C":object_shape==2?"T":object_shape==3?"S":"O";
 4:build_char=object_shape==1?"I":object_shape==2?"R":object_shape==3?"Q":"B";
 5:build_char=object_shape==2?"I":object_shape==0?"J":"R";
 7:build_char="X";8:build_char=digit(object_center[31:28]);9:build_char=digit(object_center[27:24]);10:build_char=digit(object_center[23:20]);11:build_char=digit(object_center[19:16]);
 19:build_char=mode==13?"D":" ";20:build_char=mode==13?(sort_digits[(build_row-5)*3+:3]!=0?digit({1'b0,sort_digits[(build_row-5)*3+:3]}):"-"):" ";
 22:build_char=mode==13?"C":" ";23:build_char=mode==13?digit({1'b0,sort_classes[(build_row-5)*3+:3]}):" ";
 13:build_char="Y";14:build_char=digit(object_center[15:12]);15:build_char=digit(object_center[11:8]);16:build_char=digit(object_center[7:4]);17:build_char=digit(object_center[3:0]);
 endcase end
 9:if(beauty)case(build_col)
 0:build_char="E";1:build_char="X";2:build_char="P";3:build_char=":";
 5:build_char=hexchar(exposure_status[15:12]);6:build_char=hexchar(exposure_status[11:8]);7:build_char=hexchar(exposure_status[7:4]);8:build_char=hexchar(exposure_status[3:0]);
 10:build_char="G";11:build_char=":";13:build_char=hexchar(gain_status[7:4]);14:build_char=hexchar(gain_status[3:0]);16:build_char="H";17:build_char="E";18:build_char="X";
 endcase
 10:if(beauty)case(build_col)
 0:build_char="W";1:build_char="B";3:build_char="R";4:build_char=":";5:build_char=hexchar(wb_status[15:12]);6:build_char=hexchar(wb_status[11:8]);
 8:build_char="B";9:build_char=":";10:build_char=hexchar(wb_status[7:4]);11:build_char=hexchar(wb_status[3:0]);13:build_char="Q";14:build_char="6";
 endcase
 11:if(beauty)case(build_col)
 0:build_char="Y";1:build_char=":";3:build_char=hexchar(scene_mean[7:4]);4:build_char=hexchar(scene_mean[3:0]);6:build_char="T";7:build_char="O";8:build_char="N";9:build_char="E";10:build_char=":";12:build_char=hexchar(tone_status[7:4]);13:build_char=hexchar(tone_status[3:0]);
 endcase
 12:if(center_seconds!=0)case(build_col)
 0:build_char="C";1:build_char="E";2:build_char="N";3:build_char="T";4:build_char="E";5:build_char="R";7:build_char=digit({2'd0,center_seconds});8:build_char="S";
 endcase
 13:if(photo_status!=0)case(build_col)
 0:build_char="P";1:build_char="H";2:build_char="O";3:build_char="T";4:build_char="O";5:build_char=":";
 7:build_char=photo_status==1?"S":photo_status==2?"O":"E";
 8:build_char=photo_status==1?"A":photo_status==2?"K":"R";9:build_char=photo_status==1?"V":photo_status==2?" ":"R";
 10:build_char=photo_status==1?"I":" ";11:build_char=photo_status==1?"N":" ";12:build_char=photo_status==1?"G":" ";
 14:build_char=photo_status==3?hexchar(photo_error[7:4]):" ";15:build_char=photo_status==3?hexchar(photo_error[3:0]):" ";
 endcase
 19,20:if((mode==10 || mode==12))begin
 freq_bcd=build_row==19?pan_hz_bcd:tilt_hz_bcd;duty_bcd=build_row==19?pan_duty_bcd:tilt_duty_bcd;
 case(build_col)
 0:build_char="A";1:build_char=build_row==19?"1":"2";2:build_char=":";
 3:build_char=digit(freq_bcd[11:8]);4:build_char=digit(freq_bcd[7:4]);5:build_char=digit(freq_bcd[3:0]);6:build_char="H";7:build_char="Z";9:build_char="D";
 10:build_char=digit(duty_bcd[15:12]);11:build_char=digit(duty_bcd[11:8]);12:build_char=".";13:build_char=digit(duty_bcd[7:4]);14:build_char=digit(duty_bcd[3:0]);15:build_char="%";
 endcase end
 30:case(build_col)
 0:build_char=8'h80;1:build_char=8'h81;2:build_char="C";3:build_char="N";4:build_char="T";5:build_char=digit(cnt_bcd[11:8]);6:build_char=digit(cnt_bcd[7:4]);7:build_char=digit(cnt_bcd[3:0]);
 endcase
 31:if(beauty)case(build_col)
 0:build_char="B";1:build_char="E";2:build_char="F";3:build_char="O";4:build_char="R";5:build_char="E";8:build_char="A";9:build_char="F";10:build_char="T";11:build_char="E";12:build_char="R";endcase
 endcase
 end

 (* ram_style="bram" *) reg[7:0] char_map[0:2047];
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin build_addr<=0;settle<=0;busy<=0;display_bank<=0;write_bank<=1;hud_ready<=0;end
 else if(in_user)begin settle<=128;busy<=1;build_addr<=0;write_bank<=!display_bank;end
 else if(busy)begin
 if(settle!=0)settle<=settle-1'b1;
 else if(build_addr==1023)begin busy<=0;display_bank<=write_bank;hud_ready<=1;end
 else build_addr<=build_addr+1'b1;
 end end
 always @(posedge clk)if(busy && settle==0)char_map[{write_bank,build_addr}]<=build_char;

 reg[9:0]read_addr;reg[3:0]glyph_row,glyph_col;reg text_area;
 wire[11:0] text_left=mode==13?12'd846:12'd910;
 wire[11:0] panel_left=mode==13?12'd836:12'd900;
 wire[11:0] text_py=in_y-16,text_px=in_x-text_left;
 // Glyph rows occupy the first half of each 32-pixel row, starting at y=24.
 always @*begin
 read_addr=0;glyph_row=0;glyph_col=0;text_area=0;
 if(in_x>=text_left && in_x<1230 && in_y>=24 && in_y<688 && text_py[4:0]>=8 && text_py[4:0]<24)begin
 read_addr={text_py[9:5],text_px[8:4]};glyph_row=text_py[3:0]-8;glyph_col=text_px[3:0];text_area=1;
 end else if(in_x>=176 && in_x<304 && in_y>=26 && in_y<42)begin
 read_addr=10'd960+((in_x-176)>>4);glyph_row=in_y-26;glyph_col=in_x-176;text_area=1;
 end else if(beauty && in_x>=16 && in_x<272 && in_y>=550 && in_y<566)begin
 read_addr=10'd992+((in_x-16)>>4);glyph_row=in_y-550;glyph_col=in_x-16;text_area=1;
 end end
 wire recognition_mode=mode>=8 && mode<=12;
 reg[11:0]panel_bottom;
 always @*begin
 panel_bottom=112;
 if(recognition_mode)panel_bottom=176;
 if(mode==10 || mode==13)panel_bottom=304;
 if(beauty)panel_bottom=400;
 if(center_seconds!=0)panel_bottom=432;
 if(photo_status!=0)panel_bottom=464;
 end
 wire main_panel=in_x>=panel_left && in_x<1240 && in_y>=16 && in_y<panel_bottom;
 wire pwm_panel=(mode==10 || mode==12) && in_x>=900 && in_x<1240 && in_y>=616 && in_y<680;
 wire panel=main_panel || pwm_panel;
 wire border=panel && (in_x<panel_left+12'd2 || in_x>=1238 || (main_panel && (in_y<18 || in_y>=panel_bottom-2)) || (pwm_panel && (in_y<618 || in_y>=678)));
 reg box_edge;reg[47:0]display_box;integer bi;
 always @*begin
 box_edge=0;display_box=0;
 for(bi=0;bi<4;bi=bi+1)begin
 display_box=target_boxes[bi*48+:48];
 if(target_valid[bi] && (mode==10 || mode==13) &&
 ((in_x>=display_box[47:36] && in_x<=display_box[35:24] && (in_y==display_box[23:12] || in_y==display_box[11:0])) ||
 (in_y>=display_box[23:12] && in_y<=display_box[11:0] && (in_x==display_box[47:36] || in_x==display_box[35:24]))))box_edge=1;
 end
 if(mode==8 && digit_valid &&
 ((in_x>=digit_box[47:36] && in_x<=digit_box[35:24] && (in_y==digit_box[23:12] || in_y==digit_box[11:0])) ||
 (in_y>=digit_box[23:12] && in_y<=digit_box[11:0] && (in_x==digit_box[47:36] || in_x==digit_box[35:24]))))box_edge=1;
 end
 wire face_edge=face_track && face_valid && center_seconds==0 &&
 ((in_x>=face_box[47:36] && in_x<=face_box[35:24] && (in_y==face_box[23:12] || in_y==face_box[11:0])) ||
 (in_y>=face_box[23:12] && in_y<=face_box[11:0] && (in_x==face_box[47:36] || in_x==face_box[35:24])));
 reg[7:0]q_char;reg[3:0]q_row,q_col;wire[15:0]glyph_bits;
 font_row_rom_pro font(clk,q_char,q_row,glyph_bits);
 reg[4:0]qt,rt,st;reg[23:0]qr,rr,sr;
 reg qbox,rbox,sbox,qface,rface,sface,qlogo,rlogo,slogo,qpanel,rpanel,spanel,qborder,rborder,sborder,qtext,rtext,stext;
 reg[3:0]rcol;reg[1:0]rlogo_pixel,slogo_pixel;
 always @(posedge clk)q_char<=char_map[{display_bank,read_addr}];
 always @(posedge clk or negedge rst_n)begin
 if(!rst_n)begin
 q_row<=0;q_col<=0;qt<=0;rt<=0;st<=0;qr<=0;rr<=0;sr<=0;
 qbox<=0;rbox<=0;sbox<=0;qface<=0;rface<=0;sface<=0;qlogo<=0;rlogo<=0;slogo<=0;
 qpanel<=0;rpanel<=0;spanel<=0;qborder<=0;rborder<=0;sborder<=0;qtext<=0;rtext<=0;stext<=0;
 rcol<=0;rlogo_pixel<=0;slogo_pixel<=0;out_vs<=0;out_hs<=0;out_de<=0;out_user<=0;out_last<=0;out_rgb<=0;
 end else begin
 qt<={in_vs,in_hs,in_de,in_user,in_last};qr<=in_rgb;q_row<=glyph_row;q_col<=glyph_col;
 qbox<=box_edge;qface<=face_edge;qlogo<=logo_area;qpanel<=panel;qborder<=border;qtext<=text_area && hud_ready;
 rt<=qt;rr<=qr;rbox<=qbox;rface<=qface;rlogo<=qlogo;rpanel<=qpanel;rborder<=qborder;rtext<=qtext;rcol<=q_col;rlogo_pixel<=logo_pixel;
 st<=rt;sr<=rr;sbox<=rbox;sface<=rface;slogo<=rlogo;spanel<=rpanel;sborder<=rborder;stext<=rtext && glyph_bits[15-rcol];slogo_pixel<=rlogo_pixel;
 {out_vs,out_hs,out_de,out_user,out_last}<=st;
 out_rgb<=!st[2]?24'd0:sborder?24'h00d8ff:stext?24'hffffff:
 slogo?slogo_pixel==0?24'h182030:slogo_pixel==1?24'hffffff:slogo_pixel==2?24'hff8a20:24'hf04040:
 spanel?24'h102038:sface?24'h00ff40:sbox?24'hffcc00:sr;
 end end
endmodule

