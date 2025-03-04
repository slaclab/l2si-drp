-------------------------------------------------------------------------------
-- File       : Application.vhd
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- This file is part of 'Camera link gateway'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'Camera link gateway', including this file,
-- may be copied, modified, propagated, or distributed except according to
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;

entity Application is
   generic (
      TPD_G             : time             := 1 ns;
      AXI_BASE_ADDR_G   : slv(31 downto 0) := x"00C0_0000";
      DMA_AXIS_CONFIG_G : AxiStreamConfigType;
      DMA_SIZE_G        : positive);
   port (
      -- AXI-Lite Interface
      axilClk               : in  sl;
      axilRst               : in  sl;
      axilReadMaster        : in  AxiLiteReadMasterType;
      axilReadSlave         : out AxiLiteReadSlaveType;
      axilWriteMaster       : in  AxiLiteWriteMasterType;
      axilWriteSlave        : out AxiLiteWriteSlaveType;
      -- Trigger Event streams (axilClk domain)
      eventTrigMsgMasters   : in  AxiStreamMasterArray(DMA_SIZE_G-1 downto 0);
      eventTrigMsgSlaves    : out AxiStreamSlaveArray(DMA_SIZE_G-1 downto 0);
      eventTimingMsgMasters : in  AxiStreamMasterArray(DMA_SIZE_G-1 downto 0);
      eventTimingMsgSlaves  : out AxiStreamSlaveArray(DMA_SIZE_G-1 downto 0);
      -- DMA Interface (dmaClk domain)
      dmaClk                : in  sl;
      dmaRst                : in  sl;
      dmaIbMasters          : out AxiStreamMasterArray(DMA_SIZE_G-1 downto 0);
      dmaIbSlaves           : in  AxiStreamSlaveArray(DMA_SIZE_G-1 downto 0);
      dmaObMasters          : in  AxiStreamMasterArray(DMA_SIZE_G-1 downto 0);
      dmaObSlaves           : out AxiStreamSlaveArray(DMA_SIZE_G-1 downto 0));
end Application;

architecture mapping of Application is

   constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(DMA_SIZE_G-1 downto 0) := genAxiLiteConfig(DMA_SIZE_G, AXI_BASE_ADDR_G, 22, 19);

   signal axilWriteMasters : AxiLiteWriteMasterArray(DMA_SIZE_G-1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray(DMA_SIZE_G-1 downto 0);
   signal axilReadMasters  : AxiLiteReadMasterArray(DMA_SIZE_G-1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray(DMA_SIZE_G-1 downto 0);

begin

   --------------------
   -- AXI-Lite Crossbar
   --------------------
   U_AXIL_XBAR : entity surf.AxiLiteCrossbar
      generic map (
         TPD_G              => TPD_G,
         NUM_SLAVE_SLOTS_G  => 1,
         NUM_MASTER_SLOTS_G => DMA_SIZE_G,
         MASTERS_CONFIG_G   => AXIL_CONFIG_C)
      port map (
         axiClk              => axilClk,
         axiClkRst           => axilRst,
         sAxiWriteMasters(0) => axilWriteMaster,
         sAxiWriteSlaves(0)  => axilWriteSlave,
         sAxiReadMasters(0)  => axilReadMaster,
         sAxiReadSlaves(0)   => axilReadSlave,
         mAxiWriteMasters    => axilWriteMasters,
         mAxiWriteSlaves     => axilWriteSlaves,
         mAxiReadMasters     => axilReadMasters,
         mAxiReadSlaves      => axilReadSlaves);

   -------------------
   -- Application Lane
   -------------------
   GEN_VEC :
   for i in DMA_SIZE_G-1 downto 0 generate
      U_Lane : entity surf.AxiStreamFifoV2
         generic map (
            TPD_G                => TPD_G,
            SLAVE_AXI_CONFIG_G   => EVENT_AXIS_CONFIG_G,
            MASTER_AXI_CONFIG_G  => DMA_AXIS_CONFIG_G)
         port map (
            -- Slave Port
            sAxisClk             => axilClk,
            sAxisRst             => axilRst,
            sAxisMaster          => eventTimingMsgMasters(i),
            sAxisSlave           => eventTimingMsgSlaves (i),
            -- Master Port
            mAxisClk             => dmaClk,
            mAxisRst             => dmaRst,
            mAxisMaster          => dmaIbMasters(i),
            mAxisSlave           => dmaIbSlaves (i) );

      dmaObSlaves(i) <= AXI_STREAM_SLAVE_FORCE_C;
   end generate GEN_VEC;

end mapping;
