#export GIT_BYPASS = 1
#export OVERRIDE_SUBMODULE_LOCKS = 1

# Define the Hardware Type in the axi-pcie-core
export PCIE_HW_TYPE = XilinxKcu1500

# Define target part
export PRJ_PART = xcku115-flvb2104-2-e

export BOARD_PART = xilinx.com:kcu1500:part0:1.1

export REMOVE_UNUSED_CODE = 1

# Define the number of MIG cores
export NUM_MIG_CORES = 0

# Select either GEN1 or GEN2 or GEN3 PCIe
export PCIE_GEN_NUM = GEN3
export EXTENDED_PCIE = 1

# BYPASS Partial Reconfiguration
export BYPASS_RECONFIG = 1

export TIMING_EXT_PKG = 1

# Define target output
target: prom

# Use top level makefile
include ../../targets/shared_config.mk
include ../../submodules/ruckus/system_vivado.mk
