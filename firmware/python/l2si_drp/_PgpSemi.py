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

import surf.protocols.batcher as batcher
import surf.protocols.pgp     as pgp

class PgpLaneWrapper(pr.Device):
    def __init__(self,
                 name        = 'PgpSemi',
                 description = 'Pgp Application',
                 numLanes    = 1,
                 **kwargs):
        super().__init__(
            name        = name,
            description = description,
            **kwargs
        )

        for i in range(numLanes):
            self.add(pgp.Pgp3AxiL(
                name    = 'Pgp3AxiL_%d'%i,
                offset  = 0x10000*i,
            ))

        for i in range(numLanes):
            self.add(pr.RemoteVariable(
                name    = 'rxLinkId_%d'%i,
                offset  = 0x40000 + 4*i,
                bitSize = 32,
                mode    = 'RO',
            ))

            self.add(pr.RemoteVariable(
                name    = 'txLinkId_%d'%i,
                offset  = 0x40010 + 4*i,
                bitSize = 32,
                mode    = 'RW',
            ))

        self.add(pr.RemoteVariable(
            name    = 'qpllLock',
            offset  = 0x40020,
            bitSize = 4,
            mode    = 'RO',
        ))

        self.add(pr.RemoteVariable(
            name    = 'qpllReset',
            offset  = 0x40024,
            bitSize = 1,
            bitOffset = 0,
            mode    = 'RW',
        ))

        self.add(pr.RemoteVariable(
            name    = 'txReset',
            offset  = 0x40024,
            bitSize = 1,
            bitOffset = 1,
            mode    = 'RW',
        ))

        self.add(pr.RemoteVariable(
            name    = 'rxReset',
            offset  = 0x40024,
            bitSize = 1,
            bitOffset = 2,
            mode    = 'RW',
        ))


        
class PgpSemi(pr.Device):
    def __init__(self,
                 name        = 'PgpSemi',
                 description = 'Pgp Application',
                 numLanes    = 1,
                 **kwargs):
        super().__init__(
            name        = name,
            description = description,
            **kwargs
        )

        self.add(PgpLaneWrapper(
            name      = 'PgpLaneWrapper',
            offset    = 0x00000,
        ))

        for i in range(numLanes):
            self.add(batcher.AxiStreamBatcherEventBuilder(
                name      = 'AxiStreamBatcherEB_%d'%i,
                offset    = 0x80000 + 0x10000*i,
            ))

