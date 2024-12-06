#!/usr/bin/env python3
##############################################################################
## This file is part of 'EPIX'.
## It is subject to the license terms in the LICENSE.txt file found in the 
## top-level directory of this distribution and at: 
##    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
## No part of 'EPIX', including this file, 
## may be copied, modified, propagated, or distributed except according to 
## the terms contained in the LICENSE.txt file.
##############################################################################

import pyrogue as pr

from surf.devices.transceivers import Qsfp
import surf.devices.silabs as silabs
import l2si_drp

import struct
import time

class I2CBus(pr.Device):
    def __init__(self,
                 name        = 'I2cBus',
                 description = 'Local bus',
                 **kwargs):
        super().__init__(
            name        = name,
            description = description,
            **kwargs
        )

        self.add(pr.RemoteVariable(
            name      = 'select',
            offset    = 0x0,
            bitSize   = 8,
            verify    = False,
            mode      = 'RW',
            enum = {
                0x00: 'None',
                0x02: 'QSFP1',
                0x04: 'SI570',
                0x08: 'Fan',
                0x10: 'QSFP0',
                0x20: 'EEPROM',
            }
        ))

        self.add(Qsfp(
            name   = 'QSFP',
            offset = 0x400
        ))

        self.add(l2si_drp.Si570(
            factory_freq = 156.25,
            name   = 'Si570',
            offset = 0x800,
        ))

    def programSi570(self, f):
        
        self.select.set(0x04)

        self.Si570.set_freq(None,None,f)
