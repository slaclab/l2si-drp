#!/usr/bin/env python3
import pyrogue as pr
import DrpTDet
import pyrogue.interfaces
import logging

class DrpTDetRoot(pr.Root):

    def __init__(self,pollEn=True,devname='/dev/datadev_1'):
        pr.Root.__init__(self,name='DrpTDet',description='Tester', pollEn=pollEn)

        self.add(DrpTDet.PcieControl(devname=devname, expand=True))

        self.zmqServer = pyrogue.interfaces.ZmqServer(root=self, addr='127.0.0.1', port=0)
        self.addInterface(self.zmqServer)

    def start(self,**kwargs):
        super().start(**kwargs)
        self.ReadAll()

        if self.PcieControl.DevKcu1500.AxiPcieCore.AxiVersion.DRIVER_TYPE_ID_G.get()==0:
            # remove the I2c bus
            pass
