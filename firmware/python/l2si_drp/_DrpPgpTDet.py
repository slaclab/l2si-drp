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
import l2si_drp

class DrpPgpTDet(pr.Device):
    def __init__(self,
                 numDmaLanes = 2,
                 numTimingLanes = 1,
                 numPgpLanes = 1,
                 pgp3     = False,
                 **kwargs):
        super().__init__(**kwargs)

        self.add(pcie.AxiPcieCore(
            offset      = 0x0000_0000,
            numDmaLanes = numDmaLanes,
            expand      = False,
        ))

        self.add(l2si_drp.MigToPcieDma(
            name     = 'MigToPcieDma',
            offset    = 0x0080_0000,
            numLanes  = numDmaLanes,
            expand    = False,
        ))

        self.add(l2si_drp.TDetSemi(
            name     = 'TDetSemi',
            offset    = 0x00A0_0000,
            numLanes  = numTimingLanes,
            expand    = False,
        ))

        self.add(l2si_drp.PgpSemi(
            name     = 'PgpSemi',
            offset    = 0x00B0_0000,
            numLanes  = numPgpLanes,
            expand    = False,
        ))

        self.add(l2si_drp.TDetTiming(
            name     = 'TDetTiming',
            offset    = 0x00C0_0000,
            numLanes  = numTimingLanes+numPgpLanes,
            expand    = False,
        ))

        self.add(l2si_drp.I2CBus(
            name     = 'I2CBus',
            offset    = 0x00E0_0000,
            expand    = False,
        ))
