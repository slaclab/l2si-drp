#-----------------------------------------------------------------------------
# This file is part of the LCLS2 PGP Firmware Library'. It is subject to 
# the license terms in the LICENSE.txt file found in the top-level directory 
# of this distribution and at: 
#    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
# No part of the LCLS2 PGP Firmware Library', including this file, may be 
# copied, modified, propagated, or distributed except according to the terms 
# contained in the LICENSE.txt file.
#-----------------------------------------------------------------------------
import l2si_drp
import pyrogue as pr
import rogue.hardware.axi
import pyrogue.utilities.prbs


class PcieControl(pr.Device):

    def __init__(self,devname='/dev/datadev_1',tdet=True,gpu=False,**kwargs):
        pr.Device.__init__(self,name=f'PcieControl',**kwargs)
        
        self._dataMap = rogue.hardware.axi.AxiMemMap(devname)
        self.add(l2si_drp.DevKcu1500(memBase=self._dataMap,expand=True,tdet=tdet,gpu=gpu))
