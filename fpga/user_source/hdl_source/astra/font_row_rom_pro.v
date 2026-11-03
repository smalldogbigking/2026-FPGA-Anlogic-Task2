// Same reference glyphs, synchronous ERAM before the existing OSD q stage.
module font_row_rom_pro(input wire clk,input wire[7:0] ch,input wire[3:0] row,output reg[15:0] bits);
 wire[5:0] index=ch==8'h80 ? 6'd60 : ch==8'h81 ? 6'd61 : 
 ((ch>=8'h41 && ch<=8'h5a) || (ch>=8'h30 && ch<=8'h3a) || ch==8'h2d || ch==8'h2e || ch==8'h25)?ch[5:0]:6'd0;
 reg[15:0] rom[0:1023]; // synthesis rom_style=bram
 initial $readmemh("../user_source/hdl_source/astra/font_rows_pro.hex",rom);
 always @(posedge clk)bits<=rom[{index,row}];
endmodule
