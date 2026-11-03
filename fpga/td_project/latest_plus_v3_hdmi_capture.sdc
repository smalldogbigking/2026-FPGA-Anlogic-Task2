create_clock -name {sys_clk_50m} -period 20.000 -waveform {0.000 10.000} [get_ports {I_sys_clk}]
create_clock -name {mipi_rx_ck_pad} -period 2.415 -waveform {0.000 1.208} [get_nets {IO_rx_clk_pad_p}]


derive_clocks
rename_clock -name {HDMI_PIXEL_CLK} [get_clocks {u_hdmi_pll/u_pll/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {HDMI_SERIAL_CLK} [get_clocks {u_hdmi_pll/u_pll/u_PH1P_PHY_PLL.clkc[1]}]

rename_clock -name {HDMI_REF_27M} [get_clocks {u_hdmi_pll/u_ref27/u_ref_pll/u_PH1P_PHY_PLL.clkc[0]}]

rename_clock -name {pll_clk_100m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[0]}]
rename_clock -name {pll_clk_24m} [get_clocks {u_PLL/ph1p_phy_pll_wrapper_25a56e5ce2f9_Inst/u_PH1P_PHY_PLL.clkc[1]}]
# Both PLL stages use integer feedback; derive real clocks first, then
# name their output clocks so all CDC constraints bind to the active clocks.

rename_clock -name {MIPI_RX_BYTE_CLK} [get_clocks {u_mipi_dphy_rx_ph1p_mipiio_wrapper/u_ph1p_mipiio_rx_wrapper/u_PH1P_LOGIC_DPHY_MIPI_RX.o_fabric_div4_8_clk}]


set_clock_groups -asynchronous \
    -group [get_clocks {mipi_rx_ck_pad MIPI_RX_BYTE_CLK}] \
    -group [get_clocks {sys_clk_50m pll_clk_100m pll_clk_24m HDMI_REF_27M HDMI_PIXEL_CLK HDMI_SERIAL_CLK}] \
    -group [get_clocks {u_ph1p35_324_ddr_wrapper/u_ddr2/ddr_clk u_ph1p35_324_ddr_wrapper/u_ddr2/usr_clk}]

# Bundled-data CDC between the 74.25/23.809 MHz PLL outputs:
# brightness + toggle, button-mode request + calibration toggle + freeze,
# and the slowly changing sensor exposure/gain status returned for OSD.
# All first sampling stages have a following synchronizer; brightness/cal
# events are consumed only after the synchronized toggle. These transfers
# are stable for many cycles, not synchronous video pixel transfers.
# Bound propagation to 10ns (< one pixel-clock period) without relaxing
# either clock or the continuously running image-processing datapath.
set_max_delay -datapath_only 10.000 -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_clocks {pll_clk_24m}]
set_max_delay -datapath_only 10.000 -from [get_clocks {pll_clk_24m}] -to [get_clocks {HDMI_PIXEL_CLK}]


# Asynchronous USB UART input only; RX is sampled by its two-register synchronizer.
set_false_path -from [get_ports {I_uart_rx}]

# Bundled status/toggle CDC: hold is independent of the two PLL phases.
set_min_delay 0.000 -from [get_clocks {HDMI_PIXEL_CLK}] -to [get_clocks {pll_clk_24m}]
set_min_delay 0.000 -from [get_clocks {pll_clk_24m}] -to [get_clocks {HDMI_PIXEL_CLK}]
