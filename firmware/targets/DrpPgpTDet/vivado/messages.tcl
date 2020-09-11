########################################################
## Get variables and Custom Procedures
########################################################

source -quiet $::env(RUCKUS_DIR)/vivado/env_var.tcl
source -quiet $::env(RUCKUS_DIR)/vivado/proc.tcl

########################################################
## Message Suppression
########################################################
set_msg_config -suppress -id {Synth 8-3848};# SYNTH: Net xxx does not have driver
