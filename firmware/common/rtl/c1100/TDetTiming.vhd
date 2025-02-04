------------------------------------------------------------------------------
-- Title      : 
-------------------------------------------------------------------------------
-- File       : TDetTiming.vhd
-- Author     : Matt Weaver <weaver@slac.stanford.edu>
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2015-07-08
-- Last update: 2025-02-03
-- Platform   : 
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- This file is part of 'LCLS2 XPM Core'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'LCLS2 XPM Core', including this file,
-- may be copied, modified, propagated, or distributed except according to
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------
 
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;

library lcls_timing_core;
use lcls_timing_core.TimingPkg.all;

library l2si_core;
use l2si_core.L2SiPkg.all;
use l2si_core.XpmPkg.all;

library unisim;
use unisim.vcomponents.all;

entity TDetTiming is
   generic (
      TPD_G               : time             := 1 ns;
      NDET_G              : natural          := 1;
      AXIL_BASEADDR_G     : slv(31 downto 0) := (others=>'0');
      AXIL_RINGB_G        : boolean          := false;
      SIMULATION_G        : boolean          := false );
   port (
      --------------------------------------------
      -- Trigger Interface (Timing clock domain)
      --------------------------------------------
      triggerClk       : out sl;
      triggerData      : out TriggerEventDataArray(NDET_G-1 downto 0);
      --------------------------------------------
      -- Readout Interface
      ----------------t----------------------------
      tdetClk          : in  sl;
      tdetRst          : in  sl := '0';
      tdetAlmostFull   : in  slv                      (NDET_G-1 downto 0);
      tdetTimingMsgs   : out TimingMessageArray       (NDET_G-1 downto 0);
      tdetTimingRds    : in  slv                      (NDET_G-1 downto 0);
      tdetInhibitCts   : out TriggerInhibitCountsArray(NDET_G-1 downto 0);
      tdetInhibitRds   : in  slv                      (NDET_G-1 downto 0);
      tdetAxisMaster   : out AxiStreamMasterArray     (NDET_G-1 downto 0);
      tdetAxisSlave    : in  AxiStreamSlaveArray      (NDET_G-1 downto 0);
      ----------------
      -- Core Ports --
      ----------------   
      -- AXI-Lite Interface (axilClk domain)
      axilClk          : in  sl;
      axilRst          : in  sl;
      axilReadMaster   : in  AxiLiteReadMasterType;
      axilReadSlave    : out AxiLiteReadSlaveType;
      axilWriteMaster  : in  AxiLiteWriteMasterType;
      axilWriteSlave   : out AxiLiteWriteSlaveType;
      -- LCLS Timing Ports
      timingRxP        : in  sl;
      timingRxN        : in  sl;
      timingTxP        : out sl;
      timingTxN        : out sl;
      userClk156       : in  sl := '1';
      timingRefClkOut  : out sl;
      timingRecClkOut  : out sl;
      timingBusOut     : out TimingBusType );
end TDetTiming;

architecture mapping of TDetTiming is

   signal timingRefClk   : sl;
   signal timingRefClkDiv: sl;
   signal rxControl      : TimingPhyControlType;
   signal rxStatus       : TimingPhyStatusType;
   signal rxCdrStable    : sl;
   signal rxUsrClk       : sl;
   signal rxData         : slv(15 downto 0);
   signal rxDataK        : slv(1 downto 0);
   signal rxDispErr      : slv(1 downto 0);
   signal rxDecErr       : slv(1 downto 0);
   signal rxOutClk       : sl;
   signal rxRst          : sl;
   signal txStatus       : TimingPhyStatusType := TIMING_PHY_STATUS_INIT_C;
   signal txUsrClk       : sl;
   signal txUsrRst       : sl;
   signal txOutClk       : sl;
   signal localReg       : slv(31 downto 0);
   signal loopback       : slv(2 downto 0);
   signal fbTx           : TimingPhyType;
   signal timingPhy      : TimingPhyType;
   signal timingBus      : TimingBusType;
   signal timingMode     : sl;
   signal tdetAxisCtrl   : AxiStreamCtrlArray(NDET_G-1 downto 0);

   constant TIMING_CO_INDEX_C : integer := 0;
   constant TIMING_GT_INDEX_C : integer := 1;
   constant TEM_INDEX_C       : integer := 2;
   constant TDET_TIM_INDEX_C  : integer := 3;
   constant NUM_AXI_MASTERS_C : integer := 4;
   constant AXIL_MASTERS_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXI_MASTERS_C-1 downto 0) := genAxiLiteConfig( NUM_AXI_MASTERS_C, AXIL_BASEADDR_G, 21, 16);
   signal axilReadMasters  : AxiLiteReadMasterArray (NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray  (NUM_AXI_MASTERS_C-1 downto 0);
   signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray (NUM_AXI_MASTERS_C-1 downto 0);

   constant TDET_AXIS_CONFIG_C : AxiStreamConfigType := (
     TSTRB_EN_C    => false,
     TDATA_BYTES_C => 32,
     TDEST_BITS_C  => 1,
     TID_BITS_C    => 0,
     TKEEP_MODE_C  => TKEEP_NORMAL_C,
     TUSER_BITS_C  => 2,
     TUSER_MODE_C  => TUSER_NORMAL_C );

   signal refClk, refClkDiv2, refRst, mmcmRst, mmcmLocked : sl;
   
begin

   triggerClk      <= rxOutClk;
   timingRecClkOut <= rxOutClk;
   timingBusOut    <= timingBus;
   timingRefClkOut <= refClkDiv2;
   mmcmRst         <= localReg(31);
   loopback        <= localReg(2 downto 0);
   
   U_AxilXbar0 : entity surf.AxiLiteCrossbar
    generic map ( NUM_SLAVE_SLOTS_G  => 1,
                  NUM_MASTER_SLOTS_G => AXIL_MASTERS_CONFIG_C'length,
                  MASTERS_CONFIG_G   => AXIL_MASTERS_CONFIG_C )
    port map    ( axiClk              => axilClk,
                  axiClkRst           => axilRst,
                  sAxiWriteMasters(0) => axilWriteMaster,
                  sAxiWriteSlaves (0) => axilWriteSlave ,
                  sAxiReadMasters (0) => axilReadMaster ,
                  sAxiReadSlaves  (0) => axilReadSlave  ,
                  mAxiWriteMasters    => axilWriteMasters,
                  mAxiWriteSlaves     => axilWriteSlaves ,
                  mAxiReadMasters     => axilReadMasters ,
                  mAxiReadSlaves      => axilReadSlaves  );
  
   -------------------------------------------------------------------------------------------------
   -- Clock Buffers
   -------------------------------------------------------------------------------------------------

     --------------------------
     -- Reference LCLS-II Clock
     --------------------------
     U_371MHz : entity surf.ClockManagerUltraScale
       generic map(
         TPD_G              => TPD_G,
         SIMULATION_G       => SIMULATION_G,
         TYPE_G             => "MMCM",
         INPUT_BUFG_G       => false,
         FB_BUFG_G          => true,
         RST_IN_POLARITY_G  => '1',
         NUM_CLOCKS_G       => 1,
         -- MMCM attributes
         BANDWIDTH_G        => "OPTIMIZED",
         CLKIN_PERIOD_G     => 6.4,     -- 156.25 MHz
         DIVCLK_DIVIDE_G    => 7,       -- 22.321 MHz = 156.25MHz/7
         CLKFBOUT_MULT_F_G  => 52.000,  -- 1160.714 MHz = 22.321 MHz x 52
         CLKOUT0_DIVIDE_F_G => 3.125)   -- 371.429 MHz = 1160.714 MHz/3.125
       port map(
         clkIn     => userClk156,
         rstIn     => mmcmRst,
         clkOut(0) => refClk,
         rstOut(0) => refRst,
         locked    => mmcmLocked);

      U_refClkDiv2 : BUFGCE_DIV
         generic map (
            BUFGCE_DIVIDE => 2)
         port map (
            I   => refClk,
            CE  => '1',
            CLR => '0',
            O   => refClkDiv2);
   
   -------------------------------------------------------------------------------------------------
   -- GTY Timing Receiver
   -------------------------------------------------------------------------------------------------

   TimingGtyCoreWrapper_1 : entity lcls_timing_core.TimingGtCoreWrapper
     generic map ( TPD_G            => TPD_G,
                   EXTREF_G         => false,
                   AXIL_BASE_ADDR_G => AXIL_MASTERS_CONFIG_C(1).baseAddr,
                   ADDR_BITS_G      => 12,
                   GTY_DRP_OFFSET_G => x"00008000"
                   )
     port map (
       axilClk        => axilClk,
       axilRst        => axilRst,
       axilReadMaster => axilReadMasters (TIMING_GT_INDEX_C),
       axilReadSlave  => axilReadSlaves  (TIMING_GT_INDEX_C),
       axilWriteMaster=> axilWriteMasters(TIMING_GT_INDEX_C),
       axilWriteSlave => axilWriteSlaves (TIMING_GT_INDEX_C),
       stableClk      => axilClk,
       stableRst      => axilRst,
       gtRefClk       => '0',       -- Using GTGREFCLK instead
       gtRefClkDiv2   => refClkDiv2,
       gtRxP          => timingRxP,
       gtRxN          => timingRxN,
       gtTxP          => timingTxP,
       gtTxN          => timingTxN,
       -- GTGREFCLK Interface Option
       gtgRefClk       => refClk,
       cpllRefClkSel   => "111",
       -- Rx ports
       rxControl      => rxControl,
       rxStatus       => rxStatus,
       rxUsrClkActive => mmcmLocked,
--         rxCdrStable    => rxCdrStable,
       rxUsrClk       => rxUsrClk,
       rxData         => rxData,
       rxDataK        => rxDataK,
       rxDispErr      => rxDispErr,
       rxDecErr       => rxDecErr,
       rxOutClk       => rxOutClk,
       txControl      => timingPhy.control,
       txStatus       => txStatus,
       txUsrClk       => txUsrClk,
       txUsrClkActive => mmcmLocked,
       txData         => timingPhy.data,
       txDataK        => timingPhy.dataK,
       txOutClk       => txUsrClk,
       loopback       => loopback(2 downto 0));
   
   txUsrRst         <= not (txStatus.resetDone);
   rxRst            <= not (rxStatus.resetDone);
   rxUsrClk         <= rxOutClk;
   
   TimingCore_1 : entity lcls_timing_core.TimingCore
     generic map ( TPD_G             => TPD_G,
                   CLKSEL_MODE_G     => "LCLSII",
                   USE_TPGMINI_G     => false,
                   ASYNC_G           => false,
                   AXIL_BASE_ADDR_G  => AXIL_MASTERS_CONFIG_C(0).baseAddr )
     port map (
         gtTxUsrClk      => txUsrClk,
         gtTxUsrRst      => txUsrRst,
         gtRxRecClk      => rxOutClk,
         gtRxData        => rxData,
         gtRxDataK       => rxDataK,
         gtRxDispErr     => rxDispErr,
         gtRxDecErr      => rxDecErr,
         gtRxControl     => rxControl,
         gtRxStatus      => rxStatus,
         gtLoopback      => open, -- TPGMINI
         appTimingClk    => rxOutClk,
         appTimingRst    => rxRst,
         appTimingBus    => timingBus,
         appTimingMode   => timingMode,
         tpgMiniTimingPhy=> open, -- TPGMINI
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMasters (TIMING_CO_INDEX_C),
         axilReadSlave   => axilReadSlaves  (TIMING_CO_INDEX_C),
         axilWriteMaster => axilWriteMasters(TIMING_CO_INDEX_C),
         axilWriteSlave  => axilWriteSlaves (TIMING_CO_INDEX_C) );

   timingPhy.data    <= fbTx.data;
   timingPhy.dataK   <= fbTx.dataK;
   timingPhy.control <= rxControl;
   
   U_TEM : entity l2si_core.TriggerEventManager
      generic map (
        NUM_DETECTORS_G                => NDET_G,
        AXIL_BASE_ADDR_G               => AXIL_MASTERS_CONFIG_C(TEM_INDEX_C).baseAddr,
        EN_LCLS_II_INHIBIT_COUNTS_G    => true,
        EVENT_AXIS_CONFIG_G            => TDET_AXIS_CONFIG_C,
        TRIGGER_CLK_IS_TIMING_RX_CLK_G => true )
      port map (
         timingRxClk      => rxOutClk,
         timingRxRst      => rxRst,
         timingBus        => timingBus,
         timingMode       => timingMode,
         timingTxClk      => txUsrClk,
         timingTxRst      => txUsrRst,
         timingTxPhy      => fbTx,
         triggerClk       => rxOutClk,
         triggerRst       => rxRst,
         triggerData      => triggerData,
         eventClk         => tdetClk,
         eventRst         => tdetRst,
         eventTimingMessages   => tdetTimingMsgs,
         eventTimingMessagesRd => tdetTimingRds,
         eventInhibitCounts    => tdetInhibitCts,
         eventInhibitCountsRd  => tdetInhibitRds,
         eventAxisMasters => tdetAxisMaster,
         eventAxisSlaves  => tdetAxisSlave,
         eventAxisCtrl    => tdetAxisCtrl,
         axilClk          => axilClk,
         axilRst          => axilRst,
         axilReadMaster   => axilReadMasters (TEM_INDEX_C),
         axilReadSlave    => axilReadSlaves  (TEM_INDEX_C),
         axilWriteMaster  => axilWriteMasters(TEM_INDEX_C),
         axilWriteSlave   => axilWriteSlaves (TEM_INDEX_C) );

   U_TDET_TIM_AXI : entity surf.AxiLiteRegs
     generic map (
       INI_WRITE_REG_G   => (0 => x"0000_0000")
     )
     port map (
       axiClk           => axilClk,
       axiClkRst        => axilRst,
       axiReadMaster    => axilReadMasters (TDET_TIM_INDEX_C),
       axiReadSlave     => axilReadSlaves  (TDET_TIM_INDEX_C),
       axiWriteMaster   => axilWriteMasters(TDET_TIM_INDEX_C),
       axiWriteSlave    => axilWriteSlaves (TDET_TIM_INDEX_C),
       writeRegister(0) => localReg,
       readRegister (0) => x"00FACE00" );
       
     
   GEN_DET : for i in 0 to NDET_G-1 generate
      tdetAxisCtrl(i).pause    <= tdetAlmostFull(i);
      tdetAxisCtrl(i).overflow <= '0';
      tdetAxisCtrl(i).idle     <= '0';
   end generate;
   
end mapping;
