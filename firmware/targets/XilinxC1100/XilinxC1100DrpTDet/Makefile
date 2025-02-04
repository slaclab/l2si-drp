# Define target part
export PRJ_PART = XCU55N-FSVH2892-2L-E

export BUILD_PCIE_GEN4 = 1

export REMOVE_UNUSED_CODE = 1

export TIMING_EXT_PKG = 1

export TOP_DIR = $(abspath $(PWD)/../../..)

# Define target output
target: prom

# Use top level makefile
include $(TOP_DIR)/targets/shared_config.mk
include $(TOP_DIR)/submodules/ruckus/system_vivado.mk
