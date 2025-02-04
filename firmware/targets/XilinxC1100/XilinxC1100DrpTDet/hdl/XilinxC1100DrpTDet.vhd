-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- This file is part of 'lcls2-pgp-pcie-apps'.
-- It is subject to the license terms in the LICENSE.txt file found in the
-- top-level directory of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'lcls2-pgp-pcie-apps', including this file,
-- may be copied, modified, propagated, or distributed except according to
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;
use surf.Pgp3Pkg.all;
use surf.SsiPkg.all;

library lcls2_pgp_fw_lib;

library axi_pcie_core;

library lcls_timing_core;
use lcls_timing_core.TimingPkg.all;

library l2si_core;
use l2si_core.L2SiPkg.all;

library unisim;
use unisim.vcomponents.all;

entity XilinxC1100DrpTDet is
  generic (
    TPD_G          : time    := 1 ns;
    ROGUE_SIM_EN_G : boolean := false;
    PGP_TYPE_G     : string  := "PGP4";
    RATE_G         : string  := "6.25Gbps";
    BUILD_INFO_G   : BuildInfoType);
  port (
    ---------------------
    --  Application Ports
    ---------------------
    -- QSFP[0] Ports
    qsfp0RefClkP : in    sl;
    qsfp0RefClkN : in    sl;
    qsfp0RxP     : in    slv(3 downto 0);
    qsfp0RxN     : in    slv(3 downto 0);
    qsfp0TxP     : out   slv(3 downto 0);
    qsfp0TxN     : out   slv(3 downto 0);
    -- QSFP[1] Ports
    qsfp1RefClkP : in    sl;
    qsfp1RefClkN : in    sl;
    qsfp1RxP     : in    slv(3 downto 0);
    qsfp1RxN     : in    slv(3 downto 0);
    qsfp1TxP     : out   slv(3 downto 0);
    qsfp1TxN     : out   slv(3 downto 0);
    -- HBM Ports
    hbmCatTrip   : out   sl;  -- HBM Catastrophic Over temperature Output signal to Satellite Controller: active HIGH indicator to Satellite controller to indicate the HBM has exceeds its maximum allowable temperature
    --------------
    --  Core Ports
    --------------
    -- System Ports
    userClkP     : in    sl;
    userClkN     : in    sl;
    hbmRefClkP   : in    sl;
    hbmRefClkN   : in    sl;
    -- SI5394 Ports
    si5394Scl    : inout sl;
    si5394Sda    : inout sl;
    si5394IrqL   : in    sl;
    si5394LolL   : in    sl;
    si5394LosL   : in    sl;
    si5394RstL   : out   sl;
    -- PCIe Ports
    pciRstL      : in    sl;
    pciRefClkP   : in    slv(0 downto 0);
    pciRefClkN   : in    slv(0 downto 0);
    pciRxP       : in    slv(7 downto 0);
    pciRxN       : in    slv(7 downto 0);
    pciTxP       : out   slv(7 downto 0);
    pciTxN       : out   slv(7 downto 0));
end XilinxC1100DrpTDet;

architecture top_level of XilinxC1100DrpTDet is

  constant DMA_AXIS_CONFIG_C : AxiStreamConfigType := ssiAxiStreamConfig(8, TKEEP_COMP_C, TUSER_FIRST_LAST_C, 8, 2);  -- 64-bit interface
  constant AXIL_CLK_FREQ_C   : real                := 156.25E+6;  -- units of Hz
  constant DMA_SIZE_C        : positive            := 8;

  constant BUFF_INDEX_C       : natural  := 0;
  constant MIGTPCI_INDEX_C    : natural  := 1;
  constant TDETSEM_INDEX_C    : natural  := 2;
  constant TDETTIM_INDEX_C    : natural  := 3;
  constant NUM_AXIL_MASTERS_C : positive := 4;

  constant AXIL_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL_MASTERS_C-1 downto 0) := (
    BUFF_INDEX_C    => (
      baseAddr     => x"0010_0000",
      addrBits     => 20,
      connectivity => x"FFFF"),
    MIGTPCI_INDEX_C => (
      baseAddr     => x"0080_0000",
      addrBits     => 21,
      connectivity => x"FFFF"),
    TDETSEM_INDEX_C => (
      baseAddr     => x"00A0_0000",
      addrBits     => 21,
      connectivity => x"FFFF"),
    TDETTIM_INDEX_C => (
      baseAddr     => x"00C0_0000",
      addrBits     => 22,
      connectivity => x"FFFF"));

  signal hbmRefClk  : sl;
  signal userClk    : sl;
  signal userClkBuf : sl;
  signal userClk25  : sl;
  signal userRst25  : sl;
  signal userClk156 : sl;
  signal userClock156 : sl;
  
  signal axilClk          : sl;
  signal axilRst          : sl;
  signal axilReadMaster   : AxiLiteReadMasterType;
  signal axilReadSlave    : AxiLiteReadSlaveType;
  signal axilWriteMaster  : AxiLiteWriteMasterType;
  signal axilWriteSlave   : AxiLiteWriteSlaveType;
  signal axilReadMasters  : AxiLiteReadMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
  signal axilReadSlaves   : AxiLiteReadSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0);
  signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXIL_MASTERS_C-1 downto 0);
  signal axilWriteSlaves  : AxiLiteWriteSlaveArray(NUM_AXIL_MASTERS_C-1 downto 0);

  signal dmaClk        : sl;
  signal dmaRst        : sl;
  signal dmaObMasters  : AxiStreamMasterArray(DMA_SIZE_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
  signal dmaObSlaves   : AxiStreamSlaveArray(DMA_SIZE_C-1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);
  signal dmaIbMasters  : AxiStreamMasterArray(DMA_SIZE_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
  signal dmaIbSlaves   : AxiStreamSlaveArray(DMA_SIZE_C-1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);
  signal buffIbMasters : AxiStreamMasterArray(DMA_SIZE_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
  signal buffIbSlaves  : AxiStreamSlaveArray(DMA_SIZE_C-1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);

  signal pgpIbMasters : AxiStreamMasterArray(DMA_SIZE_C-1 downto 0)     := (others => AXI_STREAM_MASTER_INIT_C);
  signal pgpIbSlaves  : AxiStreamSlaveArray(DMA_SIZE_C-1 downto 0)      := (others => AXI_STREAM_SLAVE_FORCE_C);
  signal pgpObMasters : AxiStreamQuadMasterArray(DMA_SIZE_C-1 downto 0) := (others => (others => AXI_STREAM_MASTER_INIT_C));
  signal pgpObSlaves  : AxiStreamQuadSlaveArray(DMA_SIZE_C-1 downto 0)  := (others => (others => AXI_STREAM_SLAVE_FORCE_C));

  signal eventTrigMsgMasters : AxiStreamMasterArray(DMA_SIZE_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
  signal eventTrigMsgSlaves  : AxiStreamSlaveArray(DMA_SIZE_C-1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);
  signal eventTrigMsgCtrl    : AxiStreamCtrlArray(DMA_SIZE_C-1 downto 0)   := (others => AXI_STREAM_CTRL_UNUSED_C);

  signal eventTimingMsgMasters : AxiStreamMasterArray(DMA_SIZE_C-1 downto 0) := (others => AXI_STREAM_MASTER_INIT_C);
  signal eventTimingMsgSlaves  : AxiStreamSlaveArray(DMA_SIZE_C-1 downto 0)  := (others => AXI_STREAM_SLAVE_FORCE_C);

  signal hwClks          : slv                 (7 downto 0);
  signal hwRsts          : slv                 (7 downto 0);
  signal hwObMasters     : AxiStreamMasterArray(7 downto 0);
  signal hwObSlaves      : AxiStreamSlaveArray (7 downto 0);
  signal hwIbMasters     : AxiStreamMasterArray(7 downto 0);
  signal hwIbSlaves      : AxiStreamSlaveArray (7 downto 0);
  signal hwIbAlmostFull  : slv                 (7 downto 0);
  signal hwIbFull        : slv                 (7 downto 0);

  constant NDET_C   : integer := 8;
  signal tdetClk    : sl;
  signal tdetRst    : sl;
  signal tdetAlmostFull : slv(NDET_C-1 downto 0);
  signal tdetTimingMsgs : TimingMessageArray       (NDET_C-1 downto 0);
  signal tdetTimingRds  : slv                      (NDET_C-1 downto 0);
  signal tdetInhibitCts : TriggerInhibitCountsArray(NDET_C-1 downto 0);
  signal tdetInhibitRds : slv                      (NDET_C-1 downto 0);
  signal tdetAxisM      : AxiStreamMasterArray     (NDET_C-1 downto 0);
  signal tdetAxisS      : AxiStreamSlaveArray      (NDET_C-1 downto 0);

  constant DMA_STREAM_CONFIG_C : AxiStreamConfigType := (
    TSTRB_EN_C    => false,
    TDATA_BYTES_C => 32,
    TDEST_BITS_C  => 0,
    TID_BITS_C    => 0,
    TKEEP_MODE_C  => TKEEP_NORMAL_C,
    TUSER_BITS_C  => 2,
    TUSER_MODE_C  => TUSER_NORMAL_C);
  
begin

  U_BUFG : BUFG
    port map (
      I => userClk,
      O => userClkBuf);

  ---------------------------
  -- AXI-Lite clock and Reset
  ---------------------------
  U_axilClk : entity surf.ClockManagerUltraScale
    generic map(
      TPD_G              => TPD_G,
      SIMULATION_G       => ROGUE_SIM_EN_G,
      TYPE_G             => "MMCM",
      INPUT_BUFG_G       => false,
      FB_BUFG_G          => true,
      RST_IN_POLARITY_G  => '1',
      NUM_CLOCKS_G       => 1,
      -- MMCM attributes
      BANDWIDTH_G        => "OPTIMIZED",
      CLKIN_PERIOD_G     => 10.0,    -- 100MHz
      DIVCLK_DIVIDE_G    => 8,       -- 12.5MHz = 100MHz/8
      CLKFBOUT_MULT_F_G  => 96.875,  -- 1210.9375MHz = 96.875 x 12.5MHz
      CLKOUT0_DIVIDE_F_G => 7.75)    -- 156.25MHz = 1210.9375MHz/7.75
    port map(
      -- Clock Input
      clkIn     => userClkBuf,
      rstIn     => dmaRst,
      -- Clock Outputs
      clkOut(0) => axilClk,
      -- Reset Outputs
      rstOut(0) => axilRst);

  -----------------------------------
  -- Reference 25 MHz clock and Reset
  -----------------------------------
  U_userClk25 : entity surf.ClockManagerUltraScale
    generic map(
      TPD_G             => TPD_G,
      SIMULATION_G      => ROGUE_SIM_EN_G,
      TYPE_G            => "PLL",
      INPUT_BUFG_G      => false,
      FB_BUFG_G         => true,
      RST_IN_POLARITY_G => '1',
      NUM_CLOCKS_G      => 1,
      -- MMCM attributes
      CLKIN_PERIOD_G    => 10.0,     -- 100 MHz
      CLKFBOUT_MULT_G   => 10,       -- 1GHz = 10 x 100 MHz
      CLKOUT0_DIVIDE_G  => 40)       -- 25MHz = 1GHz/40
    port map(
      -- Clock Input
      clkIn     => userClkBuf,
      rstIn     => dmaRst,
      -- Clock Outputs
      clkOut(0) => userClk25,
      -- Reset Outputs
      rstOut(0) => userRst25);

  -----------------------
  -- AXI-PCIE-CORE Module
  -----------------------
  U_Core : entity axi_pcie_core.XilinxVariumC1100Core
    generic map (
      TPD_G                => TPD_G,
      ROGUE_SIM_EN_G       => ROGUE_SIM_EN_G,
      ROGUE_SIM_CH_COUNT_G => 4,     -- 4 Virtual Channels per DMA lane
      BUILD_INFO_G         => BUILD_INFO_G,
      DMA_AXIS_CONFIG_G    => DMA_AXIS_CONFIG_C,
      DMA_SIZE_G           => DMA_SIZE_C)
    port map (
      ------------------------
      --  Top Level Interfaces
      ------------------------
      userClk        => userClk,
      hbmRefClk      => hbmRefClk,
      -- DMA Interfaces
      dmaClk         => dmaClk,
      dmaRst         => dmaRst,
      dmaObMasters   => dmaObMasters,
      dmaObSlaves    => dmaObSlaves,
      dmaIbMasters   => dmaIbMasters,
      dmaIbSlaves    => dmaIbSlaves,
      -- AXI-Lite Interface
      appClk         => axilClk,
      appRst         => axilRst,
      appReadMaster  => axilReadMaster,
      appReadSlave   => axilReadSlave,
      appWriteMaster => axilWriteMaster,
      appWriteSlave  => axilWriteSlave,
      --------------
      --  Core Ports
      --------------
      -- System Ports
      userClkP       => userClkP,
      userClkN       => userClkN,
      hbmRefClkP     => hbmRefClkP,
      hbmRefClkN     => hbmRefClkN,
      -- SI5394 Ports
      si5394Scl      => si5394Scl,
      si5394Sda      => si5394Sda,
      si5394IrqL     => si5394IrqL,
      si5394LolL     => si5394LolL,
      si5394LosL     => si5394LosL,
      si5394RstL     => si5394RstL,
      -- PCIe Ports
      pciRstL        => pciRstL,
      pciRefClkP     => pciRefClkP,
      pciRefClkN     => pciRefClkN,
      pciRxP         => pciRxP,
      pciRxN         => pciRxN,
      pciTxP         => pciTxP,
      pciTxN         => pciTxN);

  ---------------------
  -- AXI-Lite Crossbar
  ---------------------
  U_XBAR : entity surf.AxiLiteCrossbar
    generic map (
      TPD_G              => TPD_G,
      NUM_SLAVE_SLOTS_G  => 1,
      NUM_MASTER_SLOTS_G => NUM_AXIL_MASTERS_C,
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

  U_HbmDmaBuffer : entity axi_pcie_core.HbmDmaBuffer
    generic map (
      TPD_G             => TPD_G,
      DMA_SIZE_G        => DMA_SIZE_C,
      DMA_AXIS_CONFIG_G => DMA_AXIS_CONFIG_C,
      AXIL_BASE_ADDR_G  => AXIL_CONFIG_C(BUFF_INDEX_C).baseAddr)
    port map (
      -- HBM Interface
      hbmRefClk        => hbmRefClk,
      hbmCatTrip       => hbmCatTrip,
      -- AXI-Lite Interface (axilClk domain)
      axilClk          => axilClk,
      axilRst          => axilRst,
      axilReadMaster   => axilReadMasters (BUFF_INDEX_C),
      axilReadSlave    => axilReadSlaves  (BUFF_INDEX_C),
      axilWriteMaster  => axilWriteMasters(BUFF_INDEX_C),
      axilWriteSlave   => axilWriteSlaves (BUFF_INDEX_C),
      -- Trigger Event streams (eventClk domain)
      eventClk         => axilClk,
      eventTrigMsgCtrl => eventTrigMsgCtrl,
      -- AXI Stream Interface (axisClk domain)
      axisClk          => dmaClk,
      axisRst          => dmaRst,
      sAxisMasters     => hwIbMasters,
      sAxisSlaves      => hwIbSlaves,
      mAxisMasters     => dmaIbMasters,
      mAxisSlaves      => dmaIbSlaves);

  GEN_OBFIFO : for i in 0 to NDET_C-1 generate
    hwIbAlmostFull(i) <= eventTrigMsgCtrl(i).pause;
    U_ObFifo : entity surf.AxiStreamFifoV2
      generic map ( FIFO_ADDR_WIDTH_G   => 4,
                    SLAVE_AXI_CONFIG_G  => DMA_STREAM_CONFIG_C,
                    MASTER_AXI_CONFIG_G => PGP3_AXIS_CONFIG_C )
      port map ( sAxisClk    => dmaClk,
                 sAxisRst    => dmaRst,
                 sAxisMaster => dmaObMasters(i),
                 sAxisSlave  => dmaObSlaves (i),
                 sAxisCtrl   => open,
                 mAxisClk    => hwClks      (i),
                 mAxisRst    => hwRsts      (i),
                 mAxisMaster => hwObMasters (i),
                 mAxisSlave  => hwObSlaves  (i) );
  end generate;

  U_Hw : entity work.TDetSemi
    generic map ( NUM_LANES_G => 8 )
    port map (
      ------------------------      
      --  Top Level Interfaces
      ------------------------         
      -- AXI-Lite Interface (axilClk domain)
      axilClk         => axilClk,
      axilRst         => axilRst,
      axilReadMaster  => axilReadMasters (TDETSEM_INDEX_C),
      axilReadSlave   => axilReadSlaves  (TDETSEM_INDEX_C),
      axilWriteMaster => axilWriteMasters(TDETSEM_INDEX_C),
      axilWriteSlave  => axilWriteSlaves (TDETSEM_INDEX_C),
      -- DMA Interface (dmaClk domain)
      dmaClks         => hwClks        ,
      dmaRsts         => hwRsts        ,
      dmaObMasters    => hwObMasters   ,
      dmaObSlaves     => hwObSlaves    ,
      dmaIbMasters    => hwIbMasters   ,
      dmaIbSlaves     => hwIbSlaves    ,
      dmaIbAlmostFull => hwIbAlmostFull,
      dmaIbFull       => hwIbFull      ,
      ------------------
      --  TDET Ports
      ------------------       
      tdetClk         => tdetClk,
      tdetClkRst      => tdetRst,
      tdetAlmostFull  => tdetAlmostFull,
      tdetTimingMsgs  => tdetTimingMsgs,
      tdetTimingRds   => tdetTimingRds ,
      tdetInhibitCts  => tdetInhibitCts,
      tdetInhibitRds  => tdetInhibitRds,
      tdetAxisMaster  => tdetAxisM,
      tdetAxisSlave   => tdetAxisS,
      modPrsL         => '0' );
  
  ------------------
  -- Hardware Module
  ------------------
  U_Timing : entity work.TDetTiming
    generic map (
      NDET_G              => NDET_C,
      AXIL_BASEADDR_G     => AXIL_CONFIG_C(TDETTIM_INDEX_C).baseAddr )
    port map ( -- AXI-Lite Interface
      axilClk          => axilClk,
      axilRst          => axilRst,
      axilReadMaster   => axilReadMasters (TDETTIM_INDEX_C),
      axilReadSlave    => axilReadSlaves  (TDETTIM_INDEX_C),
      axilWriteMaster  => axilWriteMasters(TDETTIM_INDEX_C),
      axilWriteSlave   => axilWriteSlaves (TDETTIM_INDEX_C),
      -- Timing Interface
      tdetClk          => tdetClk   ,
      tdetAlmostFull   => tdetAlmostFull,
      tdetTimingMsgs   => tdetTimingMsgs,
      tdetTimingRds    => tdetTimingRds,
      tdetInhibitCts   => tdetInhibitCts,
      tdetInhibitRds   => tdetInhibitRds,
      tdetAxisMaster   => tdetAxisM ,
      tdetAxisSlave    => tdetAxisS ,
      -- Timing Phy Ports
      timingRxP        => qsfp0RxP(0),
      timingRxN        => qsfp0RxN(0),
      timingTxP        => qsfp0TxP(0),
      timingTxN        => qsfp0TxN(0),
      userClk156       => userClk156,
      timingRefClkOut  => open );


  U_QSFP0_DUMMY : entity surf.Gtye4ChannelDummy
    generic map ( WIDTH_G => 3 )
    port map ( refClk  => axilClk,
               gtRxP   => qsfp0RxP(3 downto 1),
               gtRxN   => qsfp0RxN(3 downto 1),
               gtTxP   => qsfp0TxP(3 downto 1),
               gtTxN   => qsfp0TxN(3 downto 1) );
  
  U_QSFP1_DUMMY : entity surf.Gtye4ChannelDummy
    generic map ( WIDTH_G => 4 )
    port map ( refClk  => axilClk,
               gtRxP   => qsfp1RxP,
               gtRxN   => qsfp1RxN,
               gtTxP   => qsfp1TxP,
               gtTxN   => qsfp1TxN );
  
  ------------------------
  -- GT Clocking
  ------------------------
  U_IBUFDS : IBUFDS_GTE4
    generic map (
      REFCLK_EN_TX_PATH  => '0',
      REFCLK_HROW_CK_SEL => "00",    -- 2'b00: ODIV2 = O
      REFCLK_ICNTL_RX    => "00")
    port map (
      I     => qsfp0RefClkP,
      IB    => qsfp0RefClkN,
      CEB   => '0',
      ODIV2 => userClock156,
      O     => open );

  U_BUFG_GT : BUFG_GT
    port map (
      I       => userClock156,
      CE      => '1',
      CEMASK  => '1',
      CLR     => '0',
      CLRMASK => '1',
      DIV     => "000",
      O       => userClk156);
  
end top_level;
