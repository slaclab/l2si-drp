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

import lcls_timing_core
import l2si_core

class TDetTiming(pr.Device):
    def __init__(self,
                 name        = 'TDetTiming',
                 description = 'Template timed detector',
                 numLanes    = 1,
                 **kwargs):
        super().__init__(
            name        = name,
            description = description,
            **kwargs
        )

        self.add(lcls_timing_core.TimingCore(
            name      = 'TimingCore',
            offset    = 0x00000,
        ))

        self.add(lcls_timing_core.TimingGtCoreWrapper(
            name      = 'TimingGtCoreWrapper',
            offset    = 0x10000,
        ))

        self.add(l2si_core.TriggerEventManager(
            name      = 'TriggerEventManager',
            offset    = 0x20000,
            numDetectors = numLanes,
        ))
