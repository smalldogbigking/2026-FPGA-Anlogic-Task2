// Four-pixel, four-level brightness pseudo-color heatmap for MODE 6.
// The green channel is used as the brightness proxy.  Two MSBs select
// dark-blue, cyan, yellow, or red; this keeps the live video path shallow.
module mode6_heatmap_4ppc (
    input  wire [3:0]   I_mode,
    input  wire [127:0] I_data,
    output wire [127:0] O_data
);
    function [23:0] heat24;
        input [23:0] rgb;
        reg [7:0] g;
        begin
            g = rgb[15:8];
            case (g[7:6])
                2'b00: heat24 = 24'h0040ff;
                2'b01: heat24 = 24'h00ffff;
                2'b10: heat24 = 24'hffff00;
                default: heat24 = 24'hff0000;
            endcase
        end
    endfunction

    wire [23:0] h0 = heat24(I_data[119:96]);
    wire [23:0] h1 = heat24(I_data[87:64]);
    wire [23:0] h2 = heat24(I_data[55:32]);
    wire [23:0] h3 = heat24(I_data[23:0]);

    wire [127:0] heat_data = {
        I_data[127:120], h0,
        I_data[95:88],  h1,
        I_data[63:56],  h2,
        I_data[31:24],  h3
    };

    function [7:0] edge24;
        input [23:0] rgb;
        reg [7:0] r, g, b;
        begin
            r = rgb[23:16]; g = rgb[15:8]; b = rgb[7:0];
            // One-LUT approximation of luminance edge contrast.  Keeping a
            // single-bit decision avoids extending the live video critical path.
            edge24 = (r[7] ^ g[7] ^ b[7]) ? 8'hff : 8'h00;
        end
    endfunction

    wire [7:0] e0 = edge24(I_data[119:96]);
    wire [7:0] e1 = edge24(I_data[87:64]);
    wire [7:0] e2 = edge24(I_data[55:32]);
    wire [7:0] e3 = edge24(I_data[23:0]);
    wire [127:0] edge_data = {
        I_data[127:120], e0, e0, e0,
        I_data[95:88],  e1, e1, e1,
        I_data[63:56],  e2, e2, e2,
        I_data[31:24],  e3, e3, e3
    };

    // MODE11 uses the same shallow lane-local path as the established image
    // effects.  A frame-level tracker can consume this mask later without
    // placing counters or bounding-box feedback in the MIPI write domain.
    function [23:0] target24;
        input [23:0] rgb;
        begin
            if (rgb[23] && !rgb[15] && !rgb[7])
                target24 = 24'hff2020;
            else if (rgb[15] && !rgb[23] && !rgb[7])
                target24 = 24'h20ff20;
            else
                target24 = 24'h101010;
        end
    endfunction
    wire [127:0] target_data = {
        I_data[127:120], target24(I_data[119:96]),
        I_data[95:88],   target24(I_data[87:64]),
        I_data[63:56],   target24(I_data[55:32]),
        I_data[31:24],   target24(I_data[23:0])
    };

    assign O_data = (I_mode == 4'd6) ? heat_data :
                    (I_mode == 4'd7) ? edge_data :
                    (I_mode == 4'd11) ? target_data : I_data;
endmodule
