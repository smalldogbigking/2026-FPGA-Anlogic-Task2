// Font-derived 32x32 glyphs; synchronous ROM, ONE registered lookup stage.
// Delay the overlay hit/color/background RGB by the same stage.
module osd_anlu_rom #(parameter FONT_FILE="assets/anlu32.hex")(
 input wire clk,valid,glyph,
 input wire [4:0] row,col,
 output reg out_valid,pixel
);
 reg [31:0] font[0:63];
 initial $readmemh(FONT_FILE,font);
 always @(posedge clk) begin
 out_valid<=valid;pixel<=valid && font[{glyph,row}][31-col];
 end
endmodule
