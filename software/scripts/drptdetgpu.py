#!/usr/bin/env python3
##############################################################################
## This file is part of 'PGP PCIe APP DEV'.
## It is subject to the license terms in the LICENSE.txt file found in the
## top-level directory of this distribution and at:
##    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
## No part of 'PGP PCIe APP DEV', including this file,
## may be copied, modified, propagated, or distributed except according to
## the terms contained in the LICENSE.txt file.
##############################################################################

import sys
import argparse

import l2si_drp
import pyrogue.pydm

#################################################################

# Set the argument parser
parser = argparse.ArgumentParser()

# Convert str to bool
argBool = lambda s: s.lower() in ['true', 't', 'yes', '1']

# Add arguments
parser.add_argument(
    "--dev",
    type     = str,
    required = False,
    default  = '/dev/datagpu_0',
    help     = "path to device",
)

# Get the arguments
args = parser.parse_args()

#################################################################

with l2si_drp.DrpTDetGpuRoot(pollEn=False, devname=args.dev) as root:
     pyrogue.pydm.runPyDM(serverList = root.zmqServer.address)

#################################################################
