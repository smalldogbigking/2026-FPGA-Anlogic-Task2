// Combinational four-pixel binary selector for MODE 2.
// MODE 1 already converts every RGB lane to equal-valued grayscale.  Reuse
// that red byte here instead of repeating a three-channel luminance multiply.
// Other modes pass through unchanged so the module can be chained after MODE 1.
module mode2_binary_4ppc (
    input  wire [3:0]   I_mode,
    input  wire [127:0] I_data,
    output wire [127:0] O_data
);
    function [7:0] binary8;
        input [7:0] gray;
        begin
            // A slightly lower fixed threshold gives a decisive black/white
            // result on the SC520CS indoor image.  The comparison is kept
            // explicit so a future frame-average threshold can replace it.
            binary8 = (gray >= 8'd104) ? 8'hff : 8'h00;
        end
    endfunction

    wire [7:0] y0 = binary8(I_data[119:112]);
    wire [7:0] y1 = binary8(I_data[87:80]);
    wire [7:0] y2 = binary8(I_data[55:48]);
    wire [7:0] y3 = binary8(I_data[23:16]);

    wire [127:0] binary_data = {
        I_data[127:120], y0, y0, y0,
        I_data[95:88],   y1, y1, y1,
        I_data[63:56],   y2, y2, y2,
        I_data[31:24],   y3, y3, y3
    };

    assign O_data = (I_mode == 4'd2) ? binary_data : I_data;
endmodule
