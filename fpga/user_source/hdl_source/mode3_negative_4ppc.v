// Combinational four-pixel negative effect for MODE 3.
// The leading byte of every 32-bit lane is padding and is preserved.
module mode3_negative_4ppc (
    input  wire [3:0]   I_mode,
    input  wire [127:0] I_data,
    output wire [127:0] O_data
);
    function [23:0] negative24;
        input [23:0] rgb;
        begin
            negative24 = {~rgb[23:16], ~rgb[15:8], ~rgb[7:0]};
        end
    endfunction

    wire [23:0] n0 = negative24(I_data[119:96]);
    wire [23:0] n1 = negative24(I_data[87:64]);
    wire [23:0] n2 = negative24(I_data[55:32]);
    wire [23:0] n3 = negative24(I_data[23:0]);

    wire [127:0] negative_data = {
        I_data[127:120], n0,
        I_data[95:88],  n1,
        I_data[63:56],  n2,
        I_data[31:24],  n3
    };

    assign O_data = (I_mode == 4'd3) ? negative_data : I_data;
endmodule
