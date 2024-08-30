#!/usr/bin/env python3
import pyrogue as pr
import DrpTDetGpu
import pyrogue.interfaces

class DrpTDetGpuRoot(pr.Root):

    def __init__(self,pollEn=True,index=0):
        pr.Root.__init__(self,name='DrpPgpTDet',description='Tester', pollEn=pollEn)

        self.add(DrpTDetGpu.PcieControl(index=index, expand=True))

        self.zmqServer = pyrogue.interfaces.ZmqServer(root=self, addr='127.0.0.1', port=0)
        self.addInterface(self.zmqServer)

    def start(self,**kwargs):
        super().start(**kwargs)
        self.ReadAll()