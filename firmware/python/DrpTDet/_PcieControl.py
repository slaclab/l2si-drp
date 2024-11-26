#!/usr/bin/env python3
import DrpTDet
import pyrogue as pr
import rogue.hardware.axi
import pyrogue.utilities.prbs


class PcieControl(pr.Device):

    def __init__(self,devname='/dev/datadev_1',**kwargs):
        pr.Device.__init__(self,name=f'PcieControl',**kwargs)
        
        self._dataMap = rogue.hardware.axi.AxiMemMap(devname)
        self.add(DrpTDet.DevKcu1500(memBase=self._dataMap,expand=True))
