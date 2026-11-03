// Registered ROI geometry. Preserve the raw RED-channel contrast of black ink
// on red paper, including red-tinted/grey strokes. Threshold is learned per ROI
// by the shared digit core, before any display highlight/box is applied.
module sort_roi_adapter #(parameter BLACK_TEXT=1,GUARD=8)(
 input wire[11:0] x,y,input wire[23:0] rgb,input wire[47:0] box,
 output wire[23:0] digit_rgb,input wire circle,input wire clk,rst_n);
 // White compatibility excludes white desk corners with a central rectangle.
 // The central 1/2 x 5/8 stays well inside a circular silhouette, even with
 // smoothed/jittering boxes. The former 5/8 x 3/4 touched the dark rim.
 reg[47:0] geometry_box;reg[11:0] mx,my;
 reg[12:0] left_edge,right_edge,top_edge,bottom_edge;
 reg geometry_valid;
 always @(posedge clk or negedge rst_n)begin
  if(!rst_n)begin geometry_box<=0;mx<=0;my<=0;left_edge<=0;right_edge<=0;top_edge<=0;bottom_edge<=0;geometry_valid<=0;end
  else begin
   geometry_box<=box;
   mx<=BLACK_TEXT?((box[35:24]-box[47:36])>>2):
     (circle?((box[35:24]-box[47:36])>>2):GUARD);
   my<=BLACK_TEXT?(((box[11:0]-box[23:12])>>3)+((box[11:0]-box[23:12])>>4)):(circle?((box[11:0]-box[23:12])>>3):GUARD);
   left_edge<={1'b0,geometry_box[47:36]}+{1'b0,mx};
   right_edge<={1'b0,geometry_box[35:24]}-{1'b0,mx};
   top_edge<={1'b0,geometry_box[23:12]}+{1'b0,my};
   bottom_edge<={1'b0,geometry_box[11:0]}-{1'b0,my};
   geometry_valid<=geometry_box[35:24]>=geometry_box[47:36] && geometry_box[11:0]>=geometry_box[23:12] &&
    geometry_box[35:24]>=mx && geometry_box[11:0]>=my;
  end
 end
 // ROI owners change only during inference reset/blanking; allow two clocks
 // for geometry to settle before the next full raster is captured.
 wire inside_roi=geometry_valid && ({1'b0,x}>=left_edge) && ({1'b0,x}<=right_edge) &&
  ({1'b0,y}>=top_edge) && ({1'b0,y}<=bottom_edge);
 wire white_ink=rgb[23:16]>=170 && rgb[15:8]>=170 && rgb[7:0]>=170;
 // Low bits tag central pixels and reject strongly saturated red. R is never
 // binarized here. Fixed RGB-neutral tests discarded real red-tinted strokes,
 // while their loose +80 tolerance admitted a whole dim-red card as black.
 wire strong_red=({3'd0,rgb[23:16]}>{1'b0,rgb[15:8],2'b00}+11'd8) ||
                 ({3'd0,rgb[23:16]}>{1'b0,rgb[7:0],2'b00}+11'd8);
 assign digit_rgb=BLACK_TEXT?(inside_roi?{rgb[23:16],15'd0,strong_red}:24'hffffff):
                   (inside_roi && white_ink?24'h000000:24'hffffff);
endmodule
