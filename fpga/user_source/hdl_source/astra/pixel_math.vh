// Include INSIDE a module. RGB888 is {R,G,B}; explicit widths are intentional.
function [7:0] luma8;
 input [23:0] p;
 reg [15:0] s,r,g,b,sr,sg,sb;
 begin r={8'd0,p[23:16]};g={8'd0,p[15:8]};b={8'd0,p[7:0]};
 // Balanced exact 77R + 150G + 29B tree; avoid a long left-associated chain.
 sr=((r<<6)+(r<<3))+((r<<2)+r);
 sg=((g<<7)+(g<<4))+((g<<2)+(g<<1));
 sb=((b<<4)+(b<<3))+((b<<2)+b);
 s=(sr+sb)+sg; luma8=s[15:8]; end
endfunction
function [7:0] clip8;
 input integer n;
 begin clip8=(n<0)?0:(n>255)?255:n; end
endfunction
function [7:0] clip10;
 input signed [9:0] v;
 begin clip10=v[9]?8'd0:v[8]?8'd255:v[7:0];end
endfunction
function [23:0] saturation;
 input [23:0] p;
 reg [7:0] y;
 reg signed [9:0] r,g,b;
 begin
 y=luma8(p);
 r=$signed({1'b0,p[23:16]})-$signed({1'b0,y});
 g=$signed({1'b0,p[15:8]})-$signed({1'b0,y});
 b=$signed({1'b0,p[7:0]})-$signed({1'b0,y});
 saturation={clip10($signed({1'b0,p[23:16]})+(r>>>1)),clip10($signed({1'b0,p[15:8]})+(g>>>1)),clip10($signed({1'b0,p[7:0]})+(b>>>1))};
 end
endfunction
function [7:0] quant3;
 input [7:0] c;
 begin quant3=(c<64)?0:(c<176)?128:255; end
endfunction
function [1:0] color_class;
 input [23:0] p;
 reg[7:0] r,g,b,mn,mx,d,margin,cg,cb,dr,rg;
 reg[9:0] warm,violet;
 begin
 r=p[23:16];g=p[15:8];b=p[7:0];
 mx=(r>g)?r:g; if(b>mx) mx=b;
 mn=(r<g)?r:g; if(b<mn) mn=b;
 d=mx-mn; margin=4+(mx>>5);
 cg=g>b?g-b:0;cb=b>g?b-g:0;dr=r>b?r-b:0;rg=r>g?r-g:0;
 warm={cg,2'b0};violet={1'b0,cb,1'b0}+{2'b0,cb};
 color_class=0;
 // Demand meaningful chroma as well as channel dominance. This rejects
 // low-saturation spill/reflections while retaining pastel markers.
 if(mx>=18 && d>=12 && {d,3'b0}>={3'b0,mx}) begin
 if({1'b0,r}>={1'b0,g}+{1'b0,margin} && {1'b0,r}>={1'b0,b}+{1'b0,margin} && warm<={2'b0,dr} && violet<={2'b0,rg}) color_class=1;
 else if({1'b0,g}>={1'b0,r}+{1'b0,margin} && {1'b0,g}>={1'b0,b}+{1'b0,margin}) color_class=2;
 end
 end
endfunction

function [7:0] palette_shade;
 input [7:0] c,y;
 begin
 palette_shade=c;
 if(y<40)palette_shade=c>>2;
 else if(y<72)palette_shade=c>>1;
 else if(y<112)palette_shade=c-(c>>2);
 else if(y>176)palette_shade=c+((8'd255-c)>>2);
 end
endfunction
// Same sunlit palette, bounded arithmetic avoids 32-bit pixel multipliers.
// Identical palette and brightness bins, constant lookup replaces dynamic
// per-channel shading arithmetic after the pixel luma/hue calculations.
function [23:0] vivid_poster;
 input [23:0] p;
 reg [7:0] r,g,b,y,mx,mn,level,chroma;
 reg [10:0] chroma_scaled;
 reg [9:0] green4,red3;
 reg [2:0] hue,shade;
 begin
 r=p[23:16];g=p[15:8];b=p[7:0];y=luma8(p);
 mx=(r>g)?r:g;if(b>mx)mx=b;mn=(r<g)?r:g;if(b<mn)mn=b;
 chroma=mx-mn;chroma_scaled=(mx<96)?{chroma,3'b0}:{1'b0,chroma,2'b0};
 green4={g,2'd0};red3={1'b0,r,1'b0}+{2'd0,r};
 hue=0;shade=3;
 if(mx<16 || (chroma<((mx<96)?5:8)) || chroma_scaled<{3'b0,mx})begin
  level=y<40?32:y<80?80:y<112?144:y<144?208:255;
  vivid_poster={level,level,level};
 end else begin
  if(r>=g && r>=b)begin
   if({1'b0,b}>{1'b0,g}+9'd12)hue=1;
   else if(green4>red3)hue=2;
   else hue=3;
  end else if(g>=b)hue=r>b?4:5;
  else hue=r>g?6:7;
  shade=y<40?0:y<72?1:y<112?2:y>176?4:3;
  case({hue,shade})
   6'd8:vivid_poster=24'h35252d;
   6'd9:vivid_poster=24'h6b4a5a;
   6'd10:vivid_poster=24'ha16f87;
   6'd11:vivid_poster=24'hd694b4;
   6'd12:vivid_poster=24'he0aec6;
   6'd16:vivid_poster=24'h3b2c1b;
   6'd17:vivid_poster=24'h765936;
   6'd18:vivid_poster=24'hb28752;
   6'd19:vivid_poster=24'hedb36d;
   6'd20:vivid_poster=24'hf1c691;
   6'd24:vivid_poster=24'h3b201d;
   6'd25:vivid_poster=24'h76413a;
   6'd26:vivid_poster=24'hb26258;
   6'd27:vivid_poster=24'hed8275;
   6'd28:vivid_poster=24'hf1a197;
   6'd32:vivid_poster=24'h212d1b;
   6'd33:vivid_poster=24'h425b36;
   6'd34:vivid_poster=24'h638a52;
   6'd35:vivid_poster=24'h84b76d;
   6'd36:vivid_poster=24'ha2c991;
   6'd40:vivid_poster=24'h192e2a;
   6'd41:vivid_poster=24'h335d54;
   6'd42:vivid_poster=24'h4d8d7e;
   6'd43:vivid_poster=24'h66bba8;
   6'd44:vivid_poster=24'h8cccbd;
   6'd48:vivid_poster=24'h2a2535;
   6'd49:vivid_poster=24'h554b6a;
   6'd50:vivid_poster=24'h8072a0;
   6'd51:vivid_poster=24'haa97d5;
   6'd52:vivid_poster=24'hbfb1df;
   6'd56:vivid_poster=24'h1b2a35;
   6'd57:vivid_poster=24'h36546b;
   6'd58:vivid_poster=24'h527ea2;
   6'd59:vivid_poster=24'h6da8d7;
   6'd60:vivid_poster=24'h91bde1;
   default:vivid_poster=24'hffffff;
  endcase
 end
 end
endfunction
function [14:0] poster_key;
 input [23:0] p;
 reg [7:0] r,g,b,y,mx,mn,level,chroma;
 reg [10:0] chroma_scaled;
 reg [9:0] green4,red3;
 reg [2:0] hue,shade;
 begin
 r=p[23:16];g=p[15:8];b=p[7:0];y=luma8(p);
 mx=(r>g)?r:g;if(b>mx)mx=b;mn=(r<g)?r:g;if(b<mn)mn=b;
 chroma=mx-mn;chroma_scaled=(mx<96)?{chroma,3'b0}:{1'b0,chroma,2'b0};
 green4={g,2'd0};red3={1'b0,r,1'b0}+{2'd0,r};
 hue=0;shade=3;
 if(mx<16 || (chroma<((mx<96)?5:8)) || chroma_scaled<{3'b0,mx})begin
  level=y<40?32:y<80?80:y<112?144:y<144?208:255;
  poster_key={1'b1,6'd0,level};
 end else begin
  if(r>=g && r>=b)begin
   if({1'b0,b}>{1'b0,g}+9'd12)hue=1;
   else if(green4>red3)hue=2;
   else hue=3;
  end else if(g>=b)hue=r>b?4:5;
  else hue=r>g?6:7;
  shade=y<40?0:y<72?1:y<112?2:y>176?4:3;
  poster_key={1'b0,hue,shade,8'd0};
 end
 end
endfunction
function [23:0] poster_from_key;
 input [14:0] key;
 begin
 if(key[14])poster_from_key={key[7:0],key[7:0],key[7:0]};
 else begin
  case(key[13:8])
   6'd8:poster_from_key=24'h35252d;
   6'd9:poster_from_key=24'h6b4a5a;
   6'd10:poster_from_key=24'ha16f87;
   6'd11:poster_from_key=24'hd694b4;
   6'd12:poster_from_key=24'he0aec6;
   6'd16:poster_from_key=24'h3b2c1b;
   6'd17:poster_from_key=24'h765936;
   6'd18:poster_from_key=24'hb28752;
   6'd19:poster_from_key=24'hedb36d;
   6'd20:poster_from_key=24'hf1c691;
   6'd24:poster_from_key=24'h3b201d;
   6'd25:poster_from_key=24'h76413a;
   6'd26:poster_from_key=24'hb26258;
   6'd27:poster_from_key=24'hed8275;
   6'd28:poster_from_key=24'hf1a197;
   6'd32:poster_from_key=24'h212d1b;
   6'd33:poster_from_key=24'h425b36;
   6'd34:poster_from_key=24'h638a52;
   6'd35:poster_from_key=24'h84b76d;
   6'd36:poster_from_key=24'ha2c991;
   6'd40:poster_from_key=24'h192e2a;
   6'd41:poster_from_key=24'h335d54;
   6'd42:poster_from_key=24'h4d8d7e;
   6'd43:poster_from_key=24'h66bba8;
   6'd44:poster_from_key=24'h8cccbd;
   6'd48:poster_from_key=24'h2a2535;
   6'd49:poster_from_key=24'h554b6a;
   6'd50:poster_from_key=24'h8072a0;
   6'd51:poster_from_key=24'haa97d5;
   6'd52:poster_from_key=24'hbfb1df;
   6'd56:poster_from_key=24'h1b2a35;
   6'd57:poster_from_key=24'h36546b;
   6'd58:poster_from_key=24'h527ea2;
   6'd59:poster_from_key=24'h6da8d7;
   6'd60:poster_from_key=24'h91bde1;
   default:poster_from_key=24'hffffff;
  endcase
 end
 end
endfunction


// Existing vivid hues/shades are unchanged. Only colors previously rejected
// as grey can take this secondary, half-chroma palette. Neutral noise remains grey.
function [14:0] cartoon_key;
 input [23:0] p;
 reg [14:0] k;reg [7:0] r,g,b,mx,mn,d,y;reg [2:0] hue,shade;
 begin
 k=poster_key(p);r=p[23:16];g=p[15:8];b=p[7:0];y=luma8(p);
 mx=r>g?r:g;if(b>mx)mx=b;mn=r<g?r:g;if(b<mn)mn=b;d=mx-mn;
 if(k[14] && mx>=24 && d>=((mx<96)?5:8) &&
    ((mx<96)?({d,4'd0}>={4'd0,mx}):({d,3'd0}>={3'd0,mx})))begin
  if(r>=g && r>=b)begin
   if({1'b0,b}>{1'b0,g}+9'd12)hue=1;
   else if({g,2'd0}>({1'd0,r,1'b0}+{2'd0,r}))hue=2;
   else hue=3;
  end else if(g>=b)hue=r>b?4:5;else hue=r>g?6:7;
  shade=y<40?0:y<72?1:y<112?2:y>176?4:3;
  k={1'b0,hue,shade,7'd0,1'b1};
 end
 cartoon_key=k;
 end
endfunction
function [23:0] cartoon_from_key;
 input [14:0] key;
 reg [23:0] p;reg [9:0] total;reg [7:0] grey;reg [8:0] r,g,b;
 begin
 p=poster_from_key(key);
 total={2'd0,p[23:16]}+{1'd0,p[15:8],1'b0}+{2'd0,p[7:0]};grey=total[9:2];
 r={1'b0,p[23:16]}+{1'b0,grey};g={1'b0,p[15:8]}+{1'b0,grey};b={1'b0,p[7:0]}+{1'b0,grey};
 cartoon_from_key=(!key[14] && key[0])?{r[8:1],g[8:1],b[8:1]}:p;
 end
endfunction

 function detect_red;
 input [23:0] p;
 reg [7:0] r,g,b,mx,mn,d,margin,cg,cb,dr,rg;
 reg [10:0] warm;
 reg [9:0] purple;
 begin
 r=p[23:16];g=p[15:8];b=p[7:0];
 mx=r>g?r:g;if(b>mx)mx=b;mn=r<g?r:g;if(b<mn)mn=b;
 d=mx-mn;margin=4+(mx>>5);
 cg=g>b?g-b:0;cb=b>g?b-g:0;dr=r>b?r-b:0;rg=r>g?r-g:0;
 warm={1'b0,cg,2'b0}+{3'b0,cg};purple={1'b0,cb,1'b0}+{2'b0,cb};
 detect_red=mx>=18 && d>=12 && {d,2'b0}>={2'b0,mx} &&
 {1'b0,r}>={1'b0,g}+{1'b0,margin} && {1'b0,r}>={1'b0,b}+{1'b0,margin} &&
 warm<={2'b0,dr,1'b0} && purple<={2'b0,rg};
 end endfunction
