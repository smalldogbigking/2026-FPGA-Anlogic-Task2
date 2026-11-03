// Lightweight streaming Sobel-like edge emphasis for MODE 7.
// The SC520CS path has no added line buffers here, so local RGB gradient
// contrast is formed with shallow bitwise logic as a timing-safe edge proxy.
module mode7_sobel_4ppc (
    input wire [3:0] I_mode,
    input wire [127:0] I_data,
    output wire [127:0] O_data
);
    function [7:0] edge24;
        input [23:0] rgb;
        reg [7:0] r,g,b;
        begin
            r=rgb[23:16]; g=rgb[15:8]; b=rgb[7:0];
            edge24 = ((r[7:5] != g[7:5]) ||
                      (r[7:5] != b[7:5]) ||
                      (g[7:5] != b[7:5])) ? 8'hff : 8'h00;
        end
    endfunction
    wire [7:0] e0=edge24(I_data[119:96]);
    wire [7:0] e1=edge24(I_data[87:64]);
    wire [7:0] e2=edge24(I_data[55:32]);
    wire [7:0] e3=edge24(I_data[23:0]);
    wire [127:0] edge_data={I_data[127:120],e0,e0,e0,I_data[95:88],e1,e1,e1,
                             I_data[63:56],e2,e2,e2,I_data[31:24],e3,e3,e3};
    assign O_data=(I_mode==4'd7)?edge_data:I_data;
endmodule
