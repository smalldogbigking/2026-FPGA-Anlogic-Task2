// Four-pixel sepia; green proxy plus reduced blue gives strong warm tint.
module mode5_sepia_4ppc(input wire [3:0] I_mode,input wire [127:0] I_data,output wire [127:0] O_data);
 function [23:0] sepia24; input [23:0] x; begin sepia24={x[15:8],x[15:8],x[15:8]>>1}; end endfunction
 wire [23:0] s0=sepia24(I_data[119:96]),s1=sepia24(I_data[87:64]),s2=sepia24(I_data[55:32]),s3=sepia24(I_data[23:0]);
 wire [127:0] d={I_data[127:120],s0,I_data[95:88],s1,I_data[63:56],s2,I_data[31:24],s3};
 assign O_data=(I_mode==4'd5)?d:I_data;
endmodule
