// All-integer video clocks: 50*27/50 = 27 MHz, then 27*55/20 =
// 74.25 MHz and 27*55/4 = 371.25 MHz. No fractional feedback or SSC.
module hdmi_capture_pll (
    input wire refclk, reset,
    output wire pixel_clk, serial_clk, lock
);
    wire pixel_raw, ref27_clk, ref27_lock, video_lock;
    wire video_reset = reset || !ref27_lock;
    capture_ref27_pll u_ref27(.refclk(refclk), .reset(reset), .clk27(ref27_clk), .lock(ref27_lock));
    assign lock = ref27_lock && video_lock;
    PH1P_LOGIC_BUFG pixel_buf (.i(pixel_raw), .o(pixel_clk));
    ph1p_phy_pll_wrapper_25a56e5ce2f9 #(
        .FBKCLK("VCO_PHASE0"), .FBKCLK_INT("VCO_PHASE0"),
        .FIN("27.000000000"), .REFCLK_DIV(1), .FBCLK_DIV(55),
        .FRAC_ENABLE("DISABLE"), .SDM_FRAC(0),
        .CLKC0_ENABLE("ENABLE"), .CLKC0_DIV(20),
        .CLKC0_CPHASE(19), .CLKC0_FPHASE(0), .CLKC0_FPHASE_RSTSEL(0),
        .CLKC0_DUTY50("ENABLE"), .CLKC0_DUTY_INT(10),
        .CLKC1_ENABLE("ENABLE"), .CLKC1_DIV(4),
        .CLKC1_CPHASE(3), .CLKC1_FPHASE(0), .CLKC1_FPHASE_RSTSEL(0),
        .CLKC1_DUTY50("ENABLE"), .CLKC1_DUTY_INT(2),
        .PLL_USR_RST("ENABLE"), .PLL_FEED_TYPE("INTERNAL"),
        .PLL_FASTLOOP("DISABLE"), .LPF_RES(3), .LPF_CAP(0), .ICP_CUR(0),
        .FEEDBK_MODE("NOCOMP")
    ) u_pll (
        .refclk(ref27_clk), .reset(video_reset), .fbclk(1'b0),
        .clk0_en(1'b1), .clk0_out(pixel_raw), .clkb0_out(),
        .clk1_en(1'b1), .clk1_out(serial_clk), .clkb1_out(),
        .clk2_en(1'b0), .clk2_out(), .clkb2_out(),
        .clk3_en(1'b0), .clk3_out(), .clkb3_out(),
        .clk4_en(1'b0), .clk4_out(), .clkb4_out(),
        .clk5_en(1'b0), .clk5_out(), .clkb5_out(),
        .clk6_en(1'b0), .clk6_out(), .clkb6_out(),
        .drp_clk(1'b0), .drp_rstn(1'b1), .drp_sel(1'b0),
        .drp_rd(1'b0), .drp_wr(1'b0), .drp_addr(8'd0), .drp_wdata(8'd0),
        .drp_err(), .drp_rdy(), .drp_rdata(),
        .psclk(1'b0), .psclksel(3'd0), .psstep(1'b0), .psdown(1'b0),
        .cps_step(1'b0), .psdone(), .ssc_reset(1'b0), .clkc_rst(2'd0),
        .pllpd(1'b0), .wakeup(1'b1), .refclk_rst(1'b0), .lock(video_lock)
    );
endmodule

// Assert both domains immediately on reset/unlock. Each domain releases its
// own reset only on its own clock. No pixel-domain reset drives serial flops.
module hdmi_reset_domains (
    input wire pixel_clk, serial_clk, clocks_ready,
    output wire pixel_rst_n, serial_rst_n
);
    // Replicate the final reset stage near its loads instead of routing one
    // reset driver across the whole image-processing pipeline.
    (* async_reg="true", max_fanout=64 *) reg [3:0] pixel_release;
    (* async_reg="true" *) reg [3:0] serial_release;
    always @(posedge pixel_clk or negedge clocks_ready)
        if (!clocks_ready) pixel_release <= 4'b0000;
        else pixel_release <= {pixel_release[2:0],1'b1};
    always @(posedge serial_clk or negedge clocks_ready)
        if (!clocks_ready) serial_release <= 4'b0000;
        else serial_release <= {serial_release[2:0],1'b1};
    assign pixel_rst_n = pixel_release[3];
    assign serial_rst_n = serial_release[3];
endmodule

// Integer 27 MHz reference. The video PLL stays reset until this PLL locks.
module capture_ref27_pll(input wire refclk, reset, output wire clk27, lock);
    wire raw27;
    PH1P_LOGIC_BUFG ref_buffer(.i(raw27),.o(clk27));
    ph1p_phy_pll_wrapper_25a56e5ce2f9 #(
        .FBKCLK("VCO_PHASE0"), .FBKCLK_INT("VCO_PHASE0"),
        .FIN("50.000000000"), .REFCLK_DIV(1), .FBCLK_DIV(27),
        .FRAC_ENABLE("DISABLE"), .SDM_FRAC(0),
        .CLKC0_ENABLE("ENABLE"), .CLKC0_DIV(50), .CLKC0_CPHASE(49),
        .CLKC0_FPHASE(0), .CLKC0_FPHASE_RSTSEL(0),
        .CLKC0_DUTY50("ENABLE"), .CLKC0_DUTY_INT(25),
        .PLL_USR_RST("ENABLE"), .PLL_FEED_TYPE("INTERNAL"),
        .PLL_FASTLOOP("ENABLE"), .LPF_RES(0), .LPF_CAP(5), .ICP_CUR(29),
        .FEEDBK_MODE("NOCOMP")
    ) u_ref_pll (
        .refclk(refclk), .reset(reset), .fbclk(1'b0),
        .clk0_en(1'b1), .clk0_out(raw27), .clkb0_out(),
        .clk1_en(1'b0), .clk1_out(), .clkb1_out(),
        .clk2_en(1'b0), .clk2_out(), .clkb2_out(),
        .clk3_en(1'b0), .clk3_out(), .clkb3_out(),
        .clk4_en(1'b0), .clk4_out(), .clkb4_out(),
        .clk5_en(1'b0), .clk5_out(), .clkb5_out(),
        .clk6_en(1'b0), .clk6_out(), .clkb6_out(),
        .drp_clk(1'b0), .drp_rstn(1'b1), .drp_sel(1'b0),
        .drp_rd(1'b0), .drp_wr(1'b0), .drp_addr(8'd0), .drp_wdata(8'd0),
        .drp_err(), .drp_rdy(), .drp_rdata(),
        .psclk(1'b0), .psclksel(3'd0), .psstep(1'b0), .psdown(1'b0),
        .cps_step(1'b0), .psdone(), .ssc_reset(1'b0), .clkc_rst(2'd0),
        .pllpd(1'b0), .wakeup(1'b1), .refclk_rst(1'b0), .lock(lock)
    );
endmodule
