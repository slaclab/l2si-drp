# Load RUCKUS library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

# Load Source Code
loadSource -dir "$::DIR_PATH/rtl"

# Get the family type
set family [getFpgaFamily]

if { ${family} == "kintexu" } {
   loadSource -dir "$::DIR_PATH/rtl/kcu1500"
} else {
   loadSource -dir "$::DIR_PATH/rtl/c1100"
}

loadRuckusTcl "$::DIR_PATH/mig"
#loadRuckusTcl "$::DIR_PATH/pciex"
#loadRuckusTcl "$::DIR_PATH/coregen"
loadRuckusTcl "$::DIR_PATH/xdc"

