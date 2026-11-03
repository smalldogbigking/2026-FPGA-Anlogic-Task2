// Standalone reference implementation for MODE10; active datapath is folded
// into mode1_grayscale_4ppc.v to preserve the timing closure of the chain.
module mode10_neon_4ppc(input wire [3:0] I_mode,input wire [127:0] I_data,output wire [127:0] O_data);
  function [23:0] neon24; input [23:0] rgb; reg e; begin e=rgb[23]^rgb[15]^rgb[7]; neon24=e?24'h00ffff:24'h100020; end endfunction
  wire [23:0] a=neon24(I_data[119:96]),b=neon24(I_data[87:64]),c=neon24(I_data[55:32]),d=neon24(I_data[23:0]);
  wire [127:0] n={I_data[127:120],a,I_data[95:88],b,I_data[63:56],c,I_data[31:24],d};
  assign O_data=(I_mode==4'd10)?n:I_data;
endmodule
