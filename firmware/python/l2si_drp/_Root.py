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
import pyrogue.interfaces.simulation

import rogue

class Root(pr.Root):
    """ A generic Root class that sets up all of the common sub-devices and hardware connections that a PGP project would have."""
    def __init__(self,
                 dev      = '/dev/datadev_0',# path to PCIe device
                 pollEn   = True,            # Enable automatic polling registers
                 initRead = True,            # Read all registers at start of the system            
                 numLanes = 4,               # Number of PGP lanes
                 enVcMask = 0xD,             # Enable lane mask: Don't connect data stream (VC1) by default because intended for C++ process
                 pgp3     = False,           # Not used here but capture so it doesn't go into super call
                 **kwargs):
        
        super().__init__(**kwargs)
        
        # Simplify the Command Tab
        self.WriteAll.hidden      = True        
        self.ReadAll.hidden       = True        
        self.SaveState.hidden     = True        
        self.SaveConfig.hidden    = True        
        self.LoadConfig.hidden    = True        
        self.Initialize.hidden    = True        
        self.SetYamlConfig.hidden = True        
        self.GetYamlConfig.hidden = True        
        self.GetYamlState.hidden  = True        
        self.HardReset.hidden     = True        
        self.CountReset.hidden    = True        
        self.ClearLog.hidden      = True        
        self.numLanes              = numLanes        
        
        # Enable Init after config
        self.InitAfterConfig._default = True
          
        # Create PCIE memory mapped interface
        if (dev != 'sim'):
            # Set the timeout
            self._timeout = 1.0 # 1.0 default
            # Start up flags
            self._pollEn   = pollEn
            self._initRead = initRead
        else:
            # Set the timeout
            self._timeout = 100.0 # firmware simulation slow and timeout base on real time (not simulation time)
            # Start up flags
            self._pollEn   = False
            self._initRead = False


        # Create arrays to be filled
