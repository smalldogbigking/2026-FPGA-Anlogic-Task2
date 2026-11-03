// Independent mode descriptor table for the HDMI status badge.
// Seven ASCII slots are provided; unused slots are spaces.
module mode_descriptor_rom (
    input  wire [3:0] mode,
    output reg  [7:0] c0, c1, c2, c3, c4, c5, c6
);
    always @(*) begin
        c0=8'h20; c1=8'h20; c2=8'h20; c3=8'h20;
        c4=8'h20; c5=8'h20; c6=8'h20;
        case(mode)
            4'd0: begin c0="R"; c1="A"; c2="W"; end
            4'd1: begin c0="G"; c1="R"; c2="A"; c3="Y"; end
            4'd2: begin c0="B"; c1="W"; end
            4'd3: begin c0="N"; c1="E"; c2="G"; end
            4'd4: begin c0="P"; c1="O"; c2="S"; c3="T"; end
            4'd5: begin c0="S"; c1="E"; c2="P"; c3="I"; c4="A"; end
            4'd6: begin c0="H"; c1="E"; c2="A"; c3="T"; end
            4'd7: begin c0="S"; c1="O"; c2="B"; c3="E"; c4="L"; end
            4'd8: begin c0="C"; c1="A"; c2="R"; c3="T"; c4="O"; c5="O"; c6="N"; end
            4'd9: begin c0="P"; c1="E"; c2="N"; c3="C"; c4="I"; c5="L"; end
            4'd10: begin c0="N"; c1="E"; c2="O"; c3="N"; end
            4'd11: begin c0="R"; c1="G"; c2="B"; c3="B"; c4="O"; c5="X"; end
            4'd12: begin c0="R"; c1="G"; c2="B"; c3="B"; c4="O"; c5="X"; end
            4'd13: begin c0="R"; c1="G"; c2="B"; c3="P"; c4="W"; c5="M"; end
            4'd14: begin c0="D"; c1="I"; c2="G"; c3="I"; c4="T"; end
            4'd15: begin c0="I"; c1="N"; c2="F"; c3="O"; end
            default: begin c0="R"; c1="A"; c2="W"; end
        endcase
    end
endmodule
