# QSFP0 MGTREFCLK0 (programmable)
set_property PACKAGE_PIN AV39 [get_ports { timingRefClkN }]
set_property PACKAGE_PIN AV38 [get_ports { timingRefClkP }]
# QSFP0 MGTREFCLK1 (non-programmable)
set_property PACKAGE_PIN AU36 [get_ports { usrRefClkP }]
set_property PACKAGE_PIN AU37 [get_ports { usrRefClkN }]
# QSFP0 Lane 0
set_property PACKAGE_PIN AU46 [get_ports timingRxN]
set_property PACKAGE_PIN AU45 [get_ports timingRxP]
set_property PACKAGE_PIN AU41 [get_ports timingTxN]
set_property PACKAGE_PIN AU40 [get_ports timingTxP]

create_clock -period 5.380 -name timingRefClkP [get_ports timingRefClkP]

# QSFP1 MGTREFCLK0 (non-programmable)
set_property PACKAGE_PIN AR36 [get_ports { pgpRefClkP[0] }]
set_property PACKAGE_PIN AR37 [get_ports { pgpRefClkN[0] }]
# QSFP1 MGTREFCLK1 (non-programmable)
set_property PACKAGE_PIN AN36 [get_ports { pgpRefClkP[1] }]
set_property PACKAGE_PIN AN37 [get_ports { pgpRefClkN[1] }]

# QSFP1 Lane 0
set_property PACKAGE_PIN AN40 [get_ports { pgpTxP }]
set_property PACKAGE_PIN AN45 [get_ports { pgpRxP }]
set_property PACKAGE_PIN AN46 [get_ports { pgpRxN }]
set_property PACKAGE_PIN AN41 [get_ports { pgpTxN }]

create_clock -period 6.400 -name pgpRefClkP [get_ports {pgpRefClkP[1]}]

set_property -dict {PACKAGE_PIN AP24 IOSTANDARD LVCMOS18} [get_ports sda]
set_property -dict {PACKAGE_PIN AN24 IOSTANDARD LVCMOS18} [get_ports scl]
set_property -dict {PACKAGE_PIN AL24 IOSTANDARD LVCMOS18} [get_ports i2c_rst_l]

create_clock -period 3.332 -name ddrClkP0 [get_ports {ddrClkP[0]}]
create_clock -period 3.332 -name ddrClkP1 [get_ports {ddrClkP[1]}]
set_clock_groups -asynchronous \
                 -group [get_clocks -include_generated_clocks {ddrClkP0}] \
                 -group [get_clocks -include_generated_clocks {ddrClkP1}] \
                 -group [get_clocks -include_generated_clocks pciRefClkP] \
                 -group [get_clocks -include_generated_clocks timingRefClkP] \
                 -group [get_clocks -include_generated_clocks pgpRefClkP]

create_generated_clock -name clk200_0 [get_pins {GEN_SEMI[0].U_MMCM/MmcmGen.U_Mmcm/CLKOUT0}]
create_generated_clock -name axilClk0 [get_pins {GEN_SEMI[0].U_MMCM/MmcmGen.U_Mmcm/CLKOUT1}]
create_generated_clock -name tdetClk0 [get_pins {GEN_SEMI[0].U_MMCM/MmcmGen.U_Mmcm/CLKOUT2}]

create_generated_clock -name phyRxClk [get_clocks -of_objects [get_pins {GEN_SEMI[0].U_Hw/U_Pgp/GEN_LANE[0].U_Lane/U_Pgp/U_Pgp3GthUsIpWrapper_1/GEN_10G.U_Pgp3GthUsIp/inst/gen_gtwizard_gthe3_top.Pgp3GthUsIp10G_gtwizard_gthe3_inst/gen_gtwizard_gthe3.gen_tx_user_clocking_internal.gen_single_instance.gtwiz_userclk_tx_inst/gen_gtwiz_userclk_tx_main.bufg_gt_usrclk2_inst/O}]]

set_clock_groups -asynchronous \
                 -group [get_clocks clk200_0] \
                 -group [get_clocks axilClk0] \
                 -group [get_clocks tdetClk0] \
		 -group [get_clocks phyRxClk] \
		 -group [get_clocks -include_generated_clocks pgpRefClkP] \
		 -group [get_clocks -include_generated_clocks timingRefClkP]

create_generated_clock -name timingRecClk [get_pins {U_Timing/TimingGthCoreWrapper_1/GEN_EXTREF.U_TimingGthCore/inst/gen_gtwizard_gthe3_top.TimingGth_extref_gtwizard_gthe3_inst/gen_gtwizard_gthe3.gen_channel_container[0].gen_enabled_channel.gthe3_channel_wrapper_inst/channel_inst/gthe3_channel_gen.gen_gthe3_channel_inst[0].GTHE3_CHANNEL_PRIM_INST/RXOUTCLK}]

set_clock_groups -asynchronous \
                 -group [get_clocks -include_generated_clocks timingRefClkP] \
                 -group [get_clocks timingRecClk]


set_false_path -through [get_pins {GEN_SEMI[0].U_MMCM/RstOutGen[0].RstSync_1/syncRst_reg/Q}]
set_false_path -through [get_pins {GEN_SEMI[0].U_MMCM/RstOutGen[2].RstSync_1/syncRst_reg/Q}]


