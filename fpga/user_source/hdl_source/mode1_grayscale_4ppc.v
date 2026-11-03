// Combinational four-pixel selector for the first incremental image mode.
// The 8-bit padding byte in each 32-bit lane is preserved exactly.
module mode1_grayscale_4ppc (
    input  wire [3:0]   I_mode,
    input  wire [127:0] I_data,
    output wire [127:0] O_data
);
    function [7:0] gray8;
        input [23:0] rgb;
        reg [7:0] r;
        reg [7:0] g;
        reg [7:0] b;
        reg [17:0] sum;
        begin
            r = rgb[23:16];
            g = rgb[15:8];
            b = rgb[7:0];
            // round-down((77*R + 150*G + 29*B) / 256), shifts only.
            sum = ({10'd0,r} << 6) + ({10'd0,r} << 3)
                + ({10'd0,r} << 2) +  {10'd0,r}
                + ({10'd0,g} << 7) + ({10'd0,g} << 4)
                + ({10'd0,g} << 2) + ({10'd0,g} << 1)
                + ({10'd0,b} << 4) + ({10'd0,b} << 3)
                + ({10'd0,b} << 2) +  {10'd0,b};
            gray8 = sum[15:8];
        end
    endfunction

    wire [7:0] y0 = gray8(I_data[119:96]);
    wire [7:0] y1 = gray8(I_data[87:64]);
    wire [7:0] y2 = gray8(I_data[55:32]);
    wire [7:0] y3 = gray8(I_data[23:0]);

    wire [127:0] gray_data = {
        I_data[127:120], y0, y0, y0,
        I_data[95:88],   y1, y1, y1,
        I_data[63:56],   y2, y2, y2,
        I_data[31:24],   y3, y3, y3
    };

    // Pencil mode: inexpensive high-bit contrast produces dark strokes on white paper.
    wire e0 = (y0[7]^y1[7]) | (y0[6]^y1[6]);
    wire e1 = (y0[7]^y1[7]) | (y1[7]^y2[7]) | (y0[6]^y1[6]) | (y1[6]^y2[6]);
    wire e2 = (y1[7]^y2[7]) | (y2[7]^y3[7]) | (y1[6]^y2[6]) | (y2[6]^y3[6]);
    wire e3 = (y2[7]^y3[7]) | (y2[6]^y3[6]);
    wire [7:0] p0 = e0 ? 8'h18 : 8'he8;
    wire [7:0] p1 = e1 ? 8'h18 : 8'he8;
    wire [7:0] p2 = e2 ? 8'h18 : 8'he8;
    wire [7:0] p3 = e3 ? 8'h18 : 8'he8;
    wire [127:0] pencil_data = {
        I_data[127:120], p0, p0, p0,
        I_data[95:88], p1, p1, p1,
        I_data[63:56], p2, p2, p2,
        I_data[31:24], p3, p3, p3
    };    assign O_data = (I_mode == 4'd1) ? gray_data :
                    (I_mode == 4'd9) ? pencil_data : I_data;
endmodule

