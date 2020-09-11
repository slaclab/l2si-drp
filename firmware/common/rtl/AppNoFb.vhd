-------------------------------------------------------------------------------
-- File       : AppNoFb.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-26
-- Last update: 2020-08-18
-------------------------------------------------------------------------------
-- Description: AppNoFb File
-------------------------------------------------------------------------------
-- This file is part of 'axi-pcie-core'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'axi-pcie-core', including this file, 
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

library l2si_core;
use l2si_core.L2SiPkg.all;

library unisim;
use unisim.vcomponents.all;

entity AppNoFb is
   generic (
      TPD_G            : time             := 1 ns;
      NUM_LANES_G      : integer          := 4;
      AXI_BASE_ADDR_G  : slv(31 downto 0) := x"0000_0000";
      AXIS_CONFIG_G    : AxiStreamConfigType );
   port (
      ------------------------      
      --  Top Level Interfaces
      ------------------------    
      -- AXI-Lite Interface
      axilClk         : in  sl;
      axilRst         : in  sl;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType;
      -- Trigger Interface
      triggerClk      : in  sl;
      triggerData     : in  TriggerEventDataArray(NUM_LANES_G-1 downto 0);
      -- Timing Interface
      tdetClk         : in  sl;
      tdetClkRst      : in  sl;
      tdetAxisMaster  : in  AxiStreamMasterArray (NUM_LANES_G-1 downto 0);
      tdetAxisSlave   : out AxiStreamSlaveArray  (NUM_LANES_G-1 downto 0);
      -- DMA Interface
      dmaClks         : in  slv                 (NUM_LANES_G-1 downto 0);
      dmaRsts         : in  slv                 (NUM_LANES_G-1 downto 0);
      txOpCodeEn      : out slv                 (NUM_LANES_G-1 downto 0);
      txOpCode        : out Slv8Array           (NUM_LANES_G-1 downto 0);
      pgpIbMasters    : in  AxiStreamMasterArray(NUM_LANES_G-1 downto 0);
      pgpIbSlaves     : out AxiStreamSlaveArray (NUM_LANES_G-1 downto 0);
      dmaIbMasters    : out AxiStreamMasterArray(NUM_LANES_G-1 downto 0);
      dmaIbSlaves     : in  AxiStreamSlaveArray (NUM_LANES_G-1 downto 0) );
end AppNoFb;

architecture mapping of AppNoFb is

   constant NUM_LANES_C       : natural := NUM_LANES_G;

   constant NUM_AXI_MASTERS_C : integer := NUM_LANES_C;
   constant AXI_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXI_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXI_MASTERS_C, AXI_BASE_ADDR_G, 18, 16);
   signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray (NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadMasters  : AxiLiteReadMasterArray (NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray  (NUM_AXI_MASTERS_C-1 downto 0);
   
begin

   ---------------------
   -- AXI-Lite Crossbar
   ---------------------
   U_XBAR : entity surf.AxiLiteCrossbar
      generic map (
         TPD_G              => TPD_G,
         NUM_SLAVE_SLOTS_G  => 1,
         NUM_MASTER_SLOTS_G => NUM_AXI_MASTERS_C,
         MASTERS_CONFIG_G   => AXI_CONFIG_C)
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

   GEN_LANE : for i in 0 to NUM_LANES_C-1 generate
     U_App : entity work.AppLaneNoFb
       generic map ( AXIS_CONFIG_G   => AXIS_CONFIG_G )
       port map (
         -- AXI-Lite Interface
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMasters (i),
         axilReadSlave   => axilReadSlaves  (i),
         axilWriteMaster => axilWriteMasters(i),
         axilWriteSlave  => axilWriteSlaves (i),
         -- Trigger Interface
         triggerClk      => triggerClk,
         triggerData     => triggerData    (i),
         -- Timing Interface
         tdetClk         => tdetClk,
         tdetClkRst      => tdetClkRst,
         tdetAxisMaster  => tdetAxisMaster (i),
         tdetAxisSlave   => tdetAxisSlave  (i),
         -- DMA Interface
         dmaClk          => dmaClks        (i),
         dmaRst          => dmaRsts        (i),
         txOpCodeEn      => txOpCodeEn     (i),
         txOpCode        => txOpCode       (i),
         pgpIbMaster     => pgpIbMasters   (i),
         pgpIbSlave      => pgpIbSlaves    (i),
         dmaIbMaster     => dmaIbMasters   (i),
         dmaIbSlave      => dmaIbSlaves    (i) );
                  
   end generate;
   
end mapping;
