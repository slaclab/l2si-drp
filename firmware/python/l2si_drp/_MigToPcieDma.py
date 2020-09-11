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

class MigToPcieDma(pr.Device):
    def __init__(self,
                 name        = 'MigToPcieDma',
                 description = 'Local RAM to PCIE',
                 numLanes    = 1,
                 blockSize   = 21,
                 monClks     = 4,
                 **kwargs):
        super().__init__(
            name        = name,
            description = description,
            **kwargs
        )

        for i in range(numLanes):

            self.add(pr.RemoteVariable(
                name      = 'BlockSize_%d'%i,
                offset    = 0x0 + 32*i,
                bitSize   = 4,
                mode      = 'RW',
            ))

            self.add(pr.RemoteVariable(
                name      = 'BlocksPause_%d'%i,
                offset    = 0x4 + 32*i,
                bitSize   = 30-blockSize,
                bitOffset = 8,
                mode      = 'RW',
            ))

            self.add(pr.RemoteVariable(
                name      = 'BlocksFree_%d'%i,
                offset    = 0x8 + 32*i,
                bitSize   = 30-blockSize,
                mode      = 'RO',
            ))

            self.add(pr.RemoteVariable(
                name      = 'BlocksQueued_%d'%i,
                offset    = 0x8 + 32*i,
                bitSize   = 30-blockSize,
                bitOffset = 12,
                mode      = 'RO',
            ))

            self.add(pr.RemoteVariable(
                name      = 'WriteQueCnt_%d'%i,
                offset    = 0xc + 32*i,
                bitSize   = 30-blockSize,
                mode      = 'RO',
            ))

            self.add(pr.RemoteVariable(
                name      = 'WrIndex_%d'%i,
                offset    = 0x10 + 32*i,
                bitSize   = 30-blockSize,
                mode      = 'RO',
            ))

            self.add(pr.RemoteVariable(
                name      = 'WcIndex_%d'%i,
                offset    = 0x14 + 32*i,
                bitSize   = 30-blockSize,
                mode      = 'RO',
            ))

            self.add(pr.RemoteVariable(
                name      = 'RdIndex_%d'%i,
                offset    = 0x18 + 32*i,
                bitSize   = 30-blockSize,
                mode      = 'RO',
            ))

        for i in range(monClks):

            self.add(pr.RemoteVariable(
                name     = 'MonClkRate_%d'%i,
                offset   = 0x100+4*i,
                bitSize  = 29,
                mode     = 'RO',
            ))

