module mode8_cartoon_4ppc(input wire [3:0] I_mode,input wire [127:0] I_data,output wire [127:0] O_data);
 function [23:0] q; input [23:0] x; begin q={x[23:22],6'b0,x[15:14],6'b0,x[7:6],6'b0}; end endfunction
 wire [127:0] d={I_data[127:120],q(I_data[119:96]),I_data[95:88],q(I_data[87:64]),I_data[63:56],q(I_data[55:32]),I_data[31:24],q(I_data[23:0])};
 assign O_data=(I_mode==4'd8)?d:I_data;
endmodule
