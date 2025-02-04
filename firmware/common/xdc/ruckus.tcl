# Load RUCKUS library
source -quiet $::env(RUCKUS_DIR)/vivado_proc.tcl

# Get the family type
set family [getFpgaFamily]

if { ${family} == "kintexu" } {
   # Load Source Code
   loadConstraints -path "$::DIR_PATH/XilinxKcu1500Core.xdc"
   loadConstraints -path "$::DIR_PATH/XilinxKcu1500PciePhy.xdc"
   loadConstraints -path "$::DIR_PATH/XilinxKcu1500App0.xdc"
   loadConstraints -path "$::DIR_PATH/XilinxKcu1500App1.xdc"
}
