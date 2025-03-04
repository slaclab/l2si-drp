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

import l2si_drp                                as drp
import axipcie                                 as pcie
import surf.protocols.pgp                      as pgp

class DevKcu1500(pr.Device):
    def __init__(self,
                 numDmaLanes = 4,
                 numTimingLanes = 8,
                 numPgpLanes = 4,
                 tdet     = True,
                 gpu      = False,
                 pgp3     = False,
                 **kwargs):
        super().__init__(**kwargs)

        self.add(pcie.AxiPcieCore(
            offset      = 0x0000_0000,
            numDmaLanes = numDmaLanes,
            expand      = False,
        ))

        if tdet:
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

        elif numPgpLanes:
            self.add(drp.MigIlvToPcieDma(
                name     = 'MigIlvToPcieDma',
                offset    = 0x0080_0000,
                numLanes  = numDmaLanes,
                expand    = False,
            ))

            for i in range(numPgpLanes):
                self.add(pgp.Pgp3AxiL(
                    name    = f'Pgp3AxiL[{i}]',
                    offset  = 0x00A0_8000 + i*0x10000,
                    numVc   = 1,
                    writeEn = True,
                ))
                self.add(pr.RemoteVariable(
                    name        = f'RxLinkId[{i}]',
                    description = 'PGP LinkID Received',
                    offset      = 0x00A4_0000 + i*4,
                    bitSize     = 32,
                    bitOffset   = 0,
                    mode        = 'RO',
                    base        = pr.UInt
                ))
                self.add(pr.RemoteVariable(
                    name        = f'TxLinkId[{i}]',
                    description = 'PGP LinkID Advertised',
                    offset      = 0x00A4_0010 + i*4,
                    bitSize     = 32,
                    bitOffset   = 0,
                    mode        = 'RW',
                    base        = pr.UInt
                ))

            self.add(pr.RemoteVariable(
                name       = 'PgpQPllLock',
                offset     = 0x00A4_0020,
                bitSize    = 1,
                bitOffset  = 0,
                mode       = 'RO',
                base       = pr.UInt
            ))

            def addReset(name,offset):
                self.add(pr.RemoteVariable(
                    name       = name,
                    offset     = 0x00A4_0024,
                    bitSize    = 1,
                    bitOffset  = offset,
                    mode       = 'RW',
                    base       = pr.UInt
                ))

            addReset('PgpQPllReset',0)
            addReset('PgpTxReset',1)
            addReset('PgpRxReset',2)

        if gpu:
            self.add(pcie.AxiGpuAsyncCore(
                name     = 'AxiGpuAsyncCore',
                offset    = 0x00D0_0000,
                expand    = False,
            ))

        self.add(drp.I2CBus(
            name     = 'I2CBus',
            offset    = 0x00E0_0000,
            expand    = False,
        ))
