#-----------------------------------------------------------------------------
# This file is part of the LCLS2 PGP Firmware Library'. It is subject to 
# the license terms in the LICENSE.txt file found in the top-level directory 
# of this distribution and at: 
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
# No part of the LCLS2 PGP Firmware Library', including this file, may be 
# copied, modified, propagated, or distributed except according to the terms 
# contained in the LICENSE.txt file.
#-----------------------------------------------------------------------------
import pyrogue as pr
import l2si_drp
import pyrogue.interfaces
import logging

class Root(pr.Root):

    def __init__(self,name,description,pollEn,devname,gpu):
        pr.Root.__init__(self,name=name,description=description,pollEn=pollEn)

        self.add(l2si_drp.PcieControl(devname=devname, expand=True, tdet=tdet, gpu=gpu))

        self.zmqServer = pyrogue.interfaces.ZmqServer(root=self, addr='127.0.0.1', port=0)
        self.addInterface(self.zmqServer)

    def start(self,**kwargs):
        super().start(**kwargs)
        self.ReadAll()

        if self.PcieControl.DevKcu1500.AxiPcieCore.AxiVersion.DRIVER_TYPE_ID_G.get()==0:
            # remove the I2c bus
            pass

class DrpTDetRoot(Root):
    def __init__(self,pollEn=True,devname='/dev/datadev_1'):
        Root.__init__(self,name='DrpTDet',description='Timing receiver',
                      pollEn=pollEn, devname=devname, gpu=False)

class DrpTDetGpuRoot(Root):
    def __init__(self,pollEn=True,devname='/dev/datagpu_0'):
        Root.__init__(self,name='DrpTDetGpu',description='Timing receiver',
                      pollEn=pollEn, devname=devname, gpu=True)

class DrpPgpIlvRoot(pr.Root):
    def __init__(self,pollEn=True,devname='/dev/datadev_1'):
        pr.Root.__init__(self,name='DrpPgpIlv',description='HSD receiver',
                      pollEn=pollEn)

        self.add(l2si_drp.PcieControl(devname=devname, expand=True, tdet=False, gpu=False))

        self.zmqServer = pyrogue.interfaces.ZmqServer(root=self, addr='127.0.0.1', port=0)
        self.addInterface(self.zmqServer)

    def start(self,**kwargs):
        super().start(**kwargs)
        self.ReadAll()
