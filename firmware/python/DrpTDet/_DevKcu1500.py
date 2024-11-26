#!/usr/bin/env python3
#-----------------------------------------------------------------------------
# This file is part of the 'Camera link gateway'. It is subject to
# the license terms in the LICENSE.txt file found in the top-level directory
# of this distribution and at:
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
# No part of the 'Camera link gateway', including this file, may be
# copied, modified, propagated, or distributed except according to the terms
# contained in the LICENSE.txt file.
#-----------------------------------------------------------------------------
import pyrogue as pr

import axipcie                                 as pcie
import l2si_drp                                as drp


class DevKcu1500(pr.Device):
    def __init__(self,
                 numDmaLanes = 4,
                 numTimingLanes = 8,
                 pgp3     = False,
                 **kwargs):
        super().__init__(**kwargs)

        self.add(pcie.AxiPcieCore(
            useSpi=True,
            offset      = 0x0000_0000,
            numDmaLanes = numDmaLanes,
            expand      = False,
        ))

        self.add(drp.MigToPcieDma(
            name     = 'MigToPcieDma',
            offset    = 0x0080_0000,
            numLanes  = numDmaLanes,
            expand    = False,
        ))

        self.add(drp.TDetSemi(
            name     = 'TDetSemi',
            offset    = 0x00A0_0000,
            numLanes  = int(numTimingLanes/2),
            expand    = False,
        ))

        self.add(drp.TDetTiming(
            name     = 'TDetTiming',
            offset    = 0x00C0_0000,
            numLanes  = numTimingLanes,
            expand    = False,
        ))

        self.add(drp.I2CBus(
            name      = 'I2CBus',
            offset    = 0x00E0_0000,
            expand    = False,
        ))
