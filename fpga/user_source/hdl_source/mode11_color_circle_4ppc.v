// MODE11: timing-safe red/green target segmentation.
// The camera delivers four RGB888 pixels per MIPI byte-clock.  This module
// classifies every lane independently and has no frame-state feedback on the
// camera write path.  That keeps the real-time SC520CS -> DDR -> HDMI path
// closed at the board's required pixel rate.  The highlighted mask is the
// detector output consumed by the later frame-level box tracker.
module mode11_color_circle_4ppc (
    input  wire [3:0]   I_mode,
    input  wire         I_tuser,
    input  wire         I_tlast,
    input  wire         I_tvalid,
    input  wire [127:0] I_data,
    output wire [127:0] O_data,
    output wire         O_tuser,
    output wire         O_tlast,
    output wire         O_tvalid
);
    function red_hit;
        input [23:0] rgb;
        begin
            red_hit = rgb[23] & ~rgb[15] & ~rgb[7];
        end
    endfunction
    function green_hit;
        input [23:0] rgb;
        begin
            green_hit = rgb[15] & ~rgb[23] & ~rgb[7];
        end
    endfunction
    function [23:0] classify;
        input [23:0] rgb;
        begin
            if (red_hit(rgb))       classify = 24'hff2020;
            else if (green_hit(rgb)) classify = 24'h20ff20;
            else                    classify = 24'h101010;
        end
    endfunction

    wire [23:0] p0 = classify(I_data[119:96]);
    wire [23:0] p1 = classify(I_data[87:64]);
    wire [23:0] p2 = classify(I_data[55:32]);
    wire [23:0] p3 = classify(I_data[23:0]);
    wire [127:0] segmented = {I_data[127:120],p0,I_data[95:88],p1,
                              I_data[63:56],p2,I_data[31:24],p3};

    assign O_data   = (I_mode == 4'd11) ? segmented : I_data;
    assign O_tuser  = I_tuser;
    assign O_tlast  = I_tlast;
    assign O_tvalid = I_tvalid;
endmodule
