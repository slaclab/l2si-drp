# QSFP0 Lane 0
set_property PACKAGE_PIN AU46 [get_ports timingRxN]
set_property PACKAGE_PIN AU45 [get_ports timingRxP]
set_property PACKAGE_PIN AU41 [get_ports timingTxN]
set_property PACKAGE_PIN AU40 [get_ports timingTxP]

# False I2c bus
set_property -dict { PACKAGE_PIN AN23  IOSTANDARD LVCMOS18 } [get_ports { noi2cScl }];
set_property -dict { PACKAGE_PIN AP23  IOSTANDARD LVCMOS18 } [get_ports { noi2cSda }];

# QSFP1 MGTREFCLK1 (non-programmable)
set_property PACKAGE_PIN AN37 [get_ports {userRefClkN}]
set_property PACKAGE_PIN AN36 [get_ports {userRefClkP}]
create_clock -period 6.400 -name userRefClkP [get_ports userRefClkP]

set_property -dict {PACKAGE_PIN AP24 IOSTANDARD LVCMOS18} [get_ports sda]
set_property -dict {PACKAGE_PIN AN24 IOSTANDARD LVCMOS18} [get_ports scl]
set_property -dict {PACKAGE_PIN AL24 IOSTANDARD LVCMOS18} [get_ports i2c_rst_l]

create_clock -period 3.332 -name ddrClkP0 [get_ports {ddrClkP[0]}]
create_clock -period 3.332 -name ddrClkP1 [get_ports {ddrClkP[1]}]
set_clock_groups -asynchronous \
                 -group [get_clocks -include_generated_clocks {ddrClkP0}] \
                 -group [get_clocks -include_generated_clocks {ddrClkP1}] \
                 -group [get_clocks -include_generated_clocks pciRefClkP] \
                 -group [get_clocks -include_generated_clocks pciExtRefClkP] \
                 -group [get_clocks -include_generated_clocks userClkP] \
                 -group [get_clocks -include_generated_clocks userRefClkP]

create_generated_clock -name timingRefClk [get_pins -hier -filter {NAME =~ U_Timing/U_371MHz/MmcmGen.U_Mmcm/CLKOUT0}]
create_generated_clock -name timingRecClk [get_pins -hier -filter {NAME =~ U_Timing/TimingGthCoreWrapper_1/LOCREF_G.U_TimingGthCore/inst/*/RXOUTCLK}]
create_generated_clock -name timingTxClk [get_pins -hier -filter {NAME =~ U_Timing/TimingGthCoreWrapper_1/LOCREF_G.TIMING_TXCLK_BUFG_GT/O}]
create_generated_clock -name clk200_0 [get_pins {GEN_SEMI[0].U_MMCM/MmcmGen.U_Mmcm/CLKOUT0}]
create_generated_clock -name axilClk0 [get_pins {GEN_SEMI[0].U_MMCM/MmcmGen.U_Mmcm/CLKOUT1}]
create_generated_clock -name tdetClk0 [get_pins {GEN_SEMI[0].U_MMCM/MmcmGen.U_Mmcm/CLKOUT2}]
create_generated_clock -name clk200_1 [get_pins {GEN_SEMI[1].U_MMCM/MmcmGen.U_Mmcm/CLKOUT0}]
create_generated_clock -name axilClk1 [get_pins {GEN_SEMI[1].U_MMCM/MmcmGen.U_Mmcm/CLKOUT1}]

set_clock_groups -asynchronous \
                 -group [get_clocks timingRefClk] \
                 -group [get_clocks timingRecClk] \
                 -group [get_clocks timingTxClk] \
                 -group [get_clocks clk200_0] \
                 -group [get_clocks clk200_1] \
                 -group [get_clocks axilClk0] \
                 -group [get_clocks axilClk1] \
                 -group [get_clocks tdetClk0]

set_false_path -through [get_pins {GEN_SEMI[0].U_MMCM/RstOutGen[0].RstSync_1/syncRst_reg/Q}]
set_false_path -through [get_pins {GEN_SEMI[0].U_MMCM/RstOutGen[2].RstSync_1/syncRst_reg/Q}]
set_false_path -through [get_pins {GEN_SEMI[1].U_MMCM/RstOutGen[0].RstSync_1/syncRst_reg/Q}]
set_false_path -through [get_pins {GEN_SEMI[1].U_MMCM/RstOutGen[2].RstSync_1/syncRst_reg/Q}]

