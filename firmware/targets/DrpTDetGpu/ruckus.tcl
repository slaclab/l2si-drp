# Load RUCKUS environment and library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

# Load common and sub-module ruckus.tcl files
loadRuckusTcl $::env(TOP_DIR)/submodules
loadRuckusTcl $::env(TOP_DIR)/submodules/axi-pcie-core/hardware/XilinxKcu1500
loadRuckusTcl $::env(TOP_DIR)/submodules/axi-pcie-core/protocol/gpuAsync
loadRuckusTcl $::env(TOP_DIR)/submodules/axi-pcie-core/hardware/XilinxKcu1500/ddr
loadRuckusTcl $::env(TOP_DIR)/submodules/axi-pcie-core/hardware/XilinxKcu1500/pcie-extended

loadRuckusTcl $::env(TOP_DIR)/common
loadRuckusTcl $::env(TOP_DIR)/common/coregen

# Load local source Code and constraints
loadSource      -dir "$::DIR_PATH/hdl"
loadConstraints -dir "$::DIR_PATH/hdl"