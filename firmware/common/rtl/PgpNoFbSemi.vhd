-------------------------------------------------------------------------------
-- File       : HardwareSemi.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-26
-- Last update: 2020-09-08
-------------------------------------------------------------------------------
-- Description: HardwareSemi File
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

entity PgpNoFbSemi is
   generic (
      TPD_G            : time             := 1 ns;
      RATE_G           : string           := "10.3125Gbps";
      REFCLK_SELECT_G  : string           := "156M";
      NUM_VC_G         : integer          := 1;
      NUM_LANES_G      : integer          := 4;
      AXIS_CONFIG_G    : AxiStreamConfigType;
      AXIL_CLK_FREQ_G  : real             := 125.0E6;
      AXI_BASE_ADDR_G  : slv(31 downto 0) := x"0000_0000" );
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
      dmaClks         : out slv                 (NUM_LANES_G-1 downto 0);
      dmaRsts         : out slv                 (NUM_LANES_G-1 downto 0);
      dmaObMasters    : in  AxiStreamMasterArray(NUM_LANES_G-1 downto 0);
      dmaObSlaves     : out AxiStreamSlaveArray (NUM_LANES_G-1 downto 0);
      dmaIbMasters    : out AxiStreamMasterArray(NUM_LANES_G-1 downto 0);
      dmaIbSlaves     : in  AxiStreamSlaveArray (NUM_LANES_G-1 downto 0);
      --
      fifoThres       : in  slv                 (15 downto 0) := toSlv(511,16);
      fifoDepth       : out Slv16Array          (NUM_LANES_G-1 downto 0);
      ---------------------
      --  PgpNoFbSemi Ports
      ---------------------    
      -- QSFP[0] Ports
      qsfp0RefClkP    : in  sl;
      qsfp0RefClkN    : in  sl;
      qsfp0RxP        : in  slv(NUM_LANES_G-1 downto 0);
      qsfp0RxN        : in  slv(NUM_LANES_G-1 downto 0);
      qsfp0TxP        : out slv(NUM_LANES_G-1 downto 0);
      qsfp0TxN        : out slv(NUM_LANES_G-1 downto 0);
      qsfp0RefClkMon  : out sl );
end PgpNoFbSemi;

architecture mapping of PgpNoFbSemi is

   constant NUM_LANES_C       : natural := NUM_LANES_G;

   signal pgpIbMasters     : AxiStreamMasterArray(NUM_LANES_C-1 downto 0);
   signal pgpIbSlaves      : AxiStreamSlaveArray (NUM_LANES_C-1 downto 0);

   signal txOpCodeEn       : slv                 (NUM_LANES_C-1 downto 0);
   signal txOpCode         : Slv8Array           (NUM_LANES_C-1 downto 0);
   signal rxOpCodeEn       : slv                 (NUM_LANES_C-1 downto 0);
   signal rxOpCode         : Slv8Array           (NUM_LANES_C-1 downto 0);

   signal idmaClks         : slv                 (NUM_LANES_C-1 downto 0);
   signal idmaRsts         : slv                 (NUM_LANES_C-1 downto 0);

   constant NUM_AXI_MASTERS_C : integer := 2;
   constant AXI_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXI_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXI_MASTERS_C, AXI_BASE_ADDR_G, 21, 20);
   signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray (NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadMasters  : AxiLiteReadMasterArray (NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray  (NUM_AXI_MASTERS_C-1 downto 0);
   
begin

   dmaClks <= idmaClks;
   dmaRsts <= idmaRsts;

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

   --------------
   -- PGP Modules
   --------------
   U_Pgp : entity work.PgpLaneWrapper
      generic map (
         TPD_G            => TPD_G,
         RATE_G           => RATE_G,
         REFCLK_WIDTH_G   => 1,
         REFCLK_SELECT_G  => REFCLK_SELECT_G,
         NUM_VC_G         => NUM_VC_G,
         NUM_LANES_G      => NUM_LANES_G,
         AXIL_CLK_FREQ_G  => AXIL_CLK_FREQ_G,
         AXI_BASE_ADDR_G  => AXI_CONFIG_C(0).baseAddr )
      port map (
         -- QSFP[0] Ports
         qsfp0RefClkP    => qsfp0RefClkP,
         qsfp0RefClkN    => qsfp0RefClkN,
         qsfp0RxP        => qsfp0RxP    ,
         qsfp0RxN        => qsfp0RxN    ,
         qsfp0TxP        => qsfp0TxP    ,
         qsfp0TxN        => qsfp0TxN    ,
         qsfp0RefClkMon  => qsfp0RefClkMon,
         -- DMA Interfaces (dmaClk domain)
         dmaClks         => idmaClks    ,
         dmaRsts         => idmaRsts    ,
         dmaObMasters    => dmaObMasters,
         dmaObSlaves     => dmaObSlaves ,
         dmaIbMasters    => pgpIbMasters,
         dmaIbSlaves     => pgpIbSlaves ,
         dmaIbFull       => (others=>'0'),
         -- OOB Signals
         txOpCodeEn      => txOpCodeEn,
         txOpCode        => txOpCode,
         rxOpCodeEn      => rxOpCodeEn,
         rxOpCode        => rxOpCode,
         fifoThres       => fifoThres,
         fifoDepth       => fifoDepth,
         -- AXI-Lite Interface (axilClk domain)
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMasters (0),
         axilReadSlave   => axilReadSlaves  (0),
         axilWriteMaster => axilWriteMasters(0),
         axilWriteSlave  => axilWriteSlaves (0));

   U_App : entity work.AppNoFb
       generic map ( NUM_LANES_G      => NUM_LANES_G,
                     AXIS_CONFIG_G    => AXIS_CONFIG_G,
                     AXI_BASE_ADDR_G  => AXI_CONFIG_C(1).baseAddr )
       port map ( axilClk         => axilClk,
                  axilRst         => axilRst,
                  axilWriteMaster => axilWriteMasters(1),
                  axilWriteSlave  => axilWriteSlaves (1),
                  axilReadMaster  => axilReadMasters (1),
                  axilReadSlave   => axilReadSlaves  (1),
                  --
                  triggerClk      => triggerClk,
                  triggerData     => triggerData,
                  --
                  tdetClk         => tdetClk,
                  tdetClkRst      => tdetClkRst,
                  tdetAxisMaster  => tdetAxisMaster,
                  tdetAxisSlave   => tdetAxisSlave,
                  --
                  dmaClks         => idmaClks,
                  dmaRsts         => idmaRsts,
                  txOpCodeEn      => txOpCodeEn,
                  txOpCode        => txOpCode,
                  pgpIbMasters    => pgpIbMasters,
                  pgpIbSlaves     => pgpIbSlaves,
                  dmaIbMasters    => dmaIbMasters,
                  dmaIbSlaves     => dmaIbSlaves );

end mapping;
