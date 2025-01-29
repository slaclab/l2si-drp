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

class MigChannel(pr.Device):
    def __init__(self,
                 name        = 'MigChannel',
                 description = 'Local RAM to PCIE',
                 blockSize   = 21, 
                **kwargs):
        super().__init__(
            name        = name,
            description = description,
            **kwargs
        )

        self.add(pr.RemoteVariable(
            name      = 'BlockSize',
            offset    = 0x00,
            bitSize   = 4,
            mode      = 'RW',
        ))

        self.add(pr.RemoteVariable(
            name      = 'BlocksPause',
            offset    = 0x04,
            bitSize   = 30-blockSize,
            bitOffset = 8,
            mode      = 'RW',
        ))

        self.add(pr.RemoteVariable(
            name      = 'BlocksFree',
            offset    = 0x08,
            bitSize   = 30-blockSize,
            mode      = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name      = 'BlocksQueued',
            offset    = 0x8,
            bitSize   = 30-blockSize,
            bitOffset = 12,
            mode      = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name      = 'WriteQueCnt',
            offset    = 0x0c,
            bitSize   = 30-blockSize,
            mode      = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name      = 'WriteIndex',
            offset    = 0x10,
            bitSize   = 30-blockSize,
            mode      = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name      = 'WriteCompleteIndex',
            offset    = 0x14,
            bitSize   = 30-blockSize,
            mode      = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name      = 'ReadIndex',
            offset    = 0x18,
            bitSize   = 30-blockSize,
            mode      = 'RO',
        ))

        def oflow(name,offset):
            self.add(pr.RemoteVariable(
                name      = name,
                offset    = offset,
                bitSize   = 8,
                mode      = 'RO',
            ))

        oflow('ibAxisOflows',0x1c)
        oflow('dmaOflows',0x1d)
        oflow('hwIbOflow[0]',0x20)
        oflow('hwIbOflow[1]',0x21)
        oflow('hwIbOflow[2]',0x22)
        oflow('hwIbOflow[3]',0x23)

class MigIlvToPcieDma(pr.Device):
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

        self.add(pr.RemoteVariable(
            name      = 'MonEnable',
            offset    = 0,
            bitSize   = 1,
            mode      = 'RW',
        ))

        self.add(pr.RemoteVariable(
            name      = 'UserReset',
            offset    = 0,
            bitOffset = 31,
            bitSize   = 1,
            mode      = 'RW',
        ))

        self.add(MigChannel(
            name      = f'Channel[0]',
            offset    = 0x80,
            blockSize = blockSize,
        ))

        for i in range(monClks):

            self.add(pr.RemoteVariable(
                name     = 'MonClkRate_%d'%i,
                offset   = 0x100+4*i,
                bitSize  = 29,
                disp     = '{}',
                mode     = 'RO',
            ))

