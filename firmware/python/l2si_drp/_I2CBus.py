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

import struct

class QSFPMonitor(pr.Device):
    def __init__(self,
                 name        = 'QSFPMonitor',
                 description = 'QSFP monitoring and diagnostics',
                 **kwargs):
        super().__init__(
            name        = name,
            description = description,
            **kwargs
        )

        self.add(pr.RemoteVariable(
            name      = 'page',
            offset    = (127<<2),
            bitSize   = 8,
            verify    = False,
            mode      = 'RW'
        ))

        self.add(pr.RemoteVariable(
            name      = 'TmpVccBlock',
            offset    = (22<<2),
            bitSize   = 32*6,
            mode      = 'RO'
        ))

        self.add(pr.RemoteVariable(
            name      = 'RxPwrBlock',
            offset    = (34<<2),
            bitSize   = 32*8,
            mode      = 'RO'
        ))

        self.add(pr.RemoteVariable(
            name      = 'TxBiasBlock',
            offset    = (42<<2),
            bitSize   = 32*8,
            mode      = 'RO'
        ))

        self.add(pr.RemoteVariable(
            name      = 'BaseIdBlock',
            offset    = (128<<2),
            bitSize   = 32*3,
            mode      = 'RO'
        ))

        self.add(pr.RemoteVariable(
            name      = 'DateBlock',
            offset    = (212<<2),
            bitSize   = 32*6,
            mode      = 'RO'
        ))

        self.add(pr.RemoteVariable(
            name      = 'DiagnType',
            offset    = (220<<2),
            bitSize   = 32,
            mode      = 'RO'
        ))


    def getDate(self):
        self.page.set(0)
        v = self.DateBlock.get()
        def toChar(sh,w=v):
            return (w>>(32*sh))&0xff

        r = '{:c}{:c}/{:c}{:c}/20{:c}{:c}'.format(toChar(2),toChar(3),toChar(4),toChar(5),toChar(0),toChar(1))
        return r

    def getRxPwr(self):  #mW
        #self.page.set(0)
        v = self.RxPwrBlock.get()

        def word(a,o):
            return (a >> (32*o))&0xff
        def tou16(a,o):
            return struct.unpack('H',struct.pack('BB',word(a,o+1),word(a,o)))[0]
        def pwr(lane,v=v):
            p = tou16(v,2*lane)
            return p * 0.0001
                
        return (pwr(0),pwr(1),pwr(2),pwr(3))


    def getTxBiasI(self):  #mA
        #self.page.set(0)
        v = self.TxBiasBlock.get()

        def word(a,o):
            return (a >> (32*o))&0xff
        def tou16(a,o):
            return struct.unpack('H',struct.pack('BB',word(a,o+1),word(a,o)))[0]
        def pwr(lane,v=v):
            p = tou16(v,2*lane)
            return p * 0.002
                
        return (pwr(0),pwr(1),pwr(2),pwr(3))


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

        self.add(QSFPMonitor(
            name   = 'QSFP',
            offset = 0x400
        ))

#        self.add(SI570(
#            name   = 'SI570',
#            offset = 0x800
#        ))

