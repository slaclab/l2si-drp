source /cds/sw/ds/ana/conda2/manage/bin/psconda.sh
#conda activate ps-4.6.1
conda activate ps-4.6.3

# Python Package directories
export AXIPCIE_DIR=${PWD}/../firmware/submodules/axi-pcie-core/python
export SURF_DIR=${PWD}/../firmware/submodules/surf/python
export L2_DIR=${PWD}/../firmware/submodules/l2si-core/python
export L1_DIR=${PWD}/../firmware/submodules/lcls-timing-core/python
export L2F_DIR=${PWD}/../firmware/submodules/lcls2-pgp-fw-lib/python

# Setup python path
export PYTHONPATH=${PWD}/python:${SURF_DIR}:${AXIPCIE_DIR}:${L2F_DIR}:${L1_DIR}:${L2_DIR}:${PWD}/../firmware/python:${PYTHONPATH}
