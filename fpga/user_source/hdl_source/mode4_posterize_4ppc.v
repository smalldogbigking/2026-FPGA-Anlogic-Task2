// Combinational four-pixel posterize effect for MODE 4.
// Each RGB channel is quantized to four evenly spaced levels: 0, 85, 170, 255.
// The leading byte of every 32-bit lane is padding and is preserved.
module mode4_posterize_4ppc (
    input  wire [3:0]   I_mode,
    input  wire [127:0] I_data,
    output wire [127:0] O_data
);
    function [7:0] poster8;
        input [7:0] c;
        begin
            poster8 = {4{c[7:6]}};
        end
    endfunction

    function [23:0] poster24;
        input [23:0] rgb;
        begin
            poster24 = {poster8(rgb[23:16]), poster8(rgb[15:8]), poster8(rgb[7:0])};
        end
    endfunction

    wire [23:0] p0 = poster24(I_data[119:96]);
    wire [23:0] p1 = poster24(I_data[87:64]);
    wire [23:0] p2 = poster24(I_data[55:32]);
    wire [23:0] p3 = poster24(I_data[23:0]);

    wire [127:0] poster_data = {
        I_data[127:120], p0,
        I_data[95:88],  p1,
        I_data[63:56],  p2,
        I_data[31:24],  p3
    };

    assign O_data = ((I_mode == 4'd4) || (I_mode == 4'd8)) ? poster_data : I_data;
endmodule
