#!/usr/bin/env python3
import DrpTDetGpu
import pyrogue as pr
import rogue.hardware.axi
import pyrogue.utilities.prbs


class PcieControl(pr.Device):

    def __init__(self,index=0,**kwargs):
        pr.Device.__init__(self,name=f'PcieControl[{index}]',**kwargs)

        self._dataMap = rogue.hardware.axi.AxiMemMap(f'/dev/datagpu_{index}')

        self.add(DrpTDetGpu.DevKcu1500(memBase=self._dataMap, expand=True))