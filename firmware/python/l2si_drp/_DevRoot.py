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
import rogue
import click

import axipcie

import l2si_drp

import surf.protocols.batcher as batcher
import l2si_core              as l2si

rogue.Version.minVersion('4.9.0')
#rogue.Version.minVersion('4.10.3')
# rogue.Version.exactVersion('4.10.3')

class DevRoot(l2si_drp.Root):

    def __init__(self,
                 dataDebug   = False,
                 dev         = '/dev/datadev_0',# path to PCIe device
                 pgp3        = True,            # true = PGPv3, false = PGP2b
                 pollEn      = True,            # Enable automatic polling registers
                 initRead    = True,            # Read all registers at start of the system
                 defaultFile = None,
                 hwType      = None,
                 **kwargs):

        # Set the min. firmware Versions
        self.PcieVersion = 0x04000000
        self.FebVersion  = 0x04000000

        # Set local variables
        self.defaultFile = defaultFile
        self.dev         = dev

        kwargs['timeout'] = 5000000 # 5 s

        devTarget      = None
        numPgpLanes    = 0
        numTimingLanes = 0
        if hwType == 'DrpPgpTDet':
            devTarget      = l2si_drp.DrpPgpTDet
            numPgpLanes    = 1
            numTimingLanes = 1

        numDmaLanes = numPgpLanes + numTimingLanes

        # Pass custom value to parent via super function
        super().__init__(
            dev         = dev,
            pgp3        = pgp3,
            pollEn      = pollEn,
            initRead    = initRead,
            numLanes    = numDmaLanes,
            **kwargs)

        # Create memory interface
        self.memMap = axipcie.createAxiPcieMemMap(dev, 'localhost', 8000)

        # Instantiate the top level Device and pass it the memory map
        self.add(devTarget(
            name           = 'PgpPcie',
            memBase        = self.memMap,
            numPgpLanes    = numPgpLanes,
            numTimingLanes = numTimingLanes,
            pgp3           = pgp3,
            expand         = True,
        ))

        # Create DMA streams
        vcs = [0,1,2] if dataDebug else [0,2]
        self.dmaStreams = axipcie.createAxiPcieDmaStreams(dev, {lane:{dest for dest in vcs} for lane in range(numDmaLanes)}, 'localhost', 8000)

        # Check if not doing simulation
        if (dev!='sim'):

            # Create arrays to be filled
            self._srp = [None for lane in range(numPgpLanes)]

            # Create the stream interface
            for lane in range(numPgpLanes):

                # SRP
                self._srp[lane] = rogue.protocols.srp.SrpV3()
                pr.streamConnectBiDir(self.dmaStreams[lane][0],self._srp[lane])

                # CameraLink Feb Board
                self.add(feb.ClinkFeb(
                    name       = (f'ClinkFeb[{lane}]'),
                    memBase    = self._srp[lane],
                    serial     = self.dmaStreams[lane][2],
                    camType    = self.camType[lane],
                    version3   = pgp3,
                    enableDeps = [self.ClinkPcie.Hsio.PgpMon[lane].RxRemLinkReady], # Only allow access if the PGP link is established
                    expand     = True,
                ))

        # Create arrays to be filled
        self._dbg = [None for lane in range(numPgpLanes)]
        self.unbatchers = [rogue.protocols.batcher.SplitterV1() for lane in range(numPgpLanes)]

        # Create the stream interface
        for lane in range(numPgpLanes):
            # Debug slave
            if dataDebug:
                # Connect the streams
                #self.dmaStreams[lane][1] >> self.unbatchers[lane] >> self._dbg[lane]
                self.dmaStreams[lane][1] >> self.unbatchers[lane]

        self.add(pr.LocalVariable(
            name        = 'RunState',
            description = 'Run state status, which is controlled by the StopRun() and StartRun() commands',
            mode        = 'RO',
            value       = False,
        ))

