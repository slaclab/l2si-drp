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

class TDetSemi(pr.Device):
    def __init__(self,
                 name        = 'TDetSemi',
                 description = 'Timing Detector',
                 numLanes    = 1,
                 **kwargs):
        super().__init__(
            name        = name,
            description = description,
            **kwargs
        )

        for i in range(numLanes):

            self.add(pr.RemoteVariable(
                name      = 'Length_%d'%i,
                offset    = 0x0 + 4*i,
                bitSize   = 23,
                mode      = 'RW',
            ))

            self.add(pr.RemoteVariable(
                name      = 'Clear_%d'%i,
                offset    = 0x0 + 4*i,
                bitSize   = 1,
                bitOffset = 30,
                mode      = 'RW',
            ))

            self.add(pr.RemoteVariable(
                name      = 'Enable_%d'%i,
                offset    = 0x0 + 4*i,
                bitSize   = 1,
                bitOffset = 31,
                mode      = 'RW',
            ))

        self.add(pr.RemoteVariable(
            name      = 'ModPrsL',
            offset    = 0x20,
            bitSize   = 1,
            mode      = 'RO',
        ))

