// MODE9 reference wrapper; active implementation is integrated into MODE1.
module mode9_pencil_4ppc(input wire [3:0] I_mode,input wire [127:0] I_data,output wire [127:0] O_data);
 function [7:0] p; input [23:0] x; begin p=8'hff-((x[23:16]>>2)+(x[15:8]>>1)+(x[7:0]>>3)); end endfunction
 wire [127:0] d={I_data[127:120],p(I_data[119:96]),p(I_data[119:96]),p(I_data[119:96]),I_data[95:88],p(I_data[87:64]),p(I_data[87:64]),p(I_data[87:64]),I_data[63:56],p(I_data[55:32]),p(I_data[55:32]),p(I_data[55:32]),I_data[31:24],p(I_data[23:0]),p(I_data[23:0]),p(I_data[23:0])};
 assign O_data=(I_mode==4'd9)?d:I_data;
endmodule
