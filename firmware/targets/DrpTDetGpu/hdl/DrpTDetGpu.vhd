-------------------------------------------------------------------------------
-- File       : DrpTDet.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-24
-- Last update: 2024-07-08
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- This file is part of 'axi-pcie-dev'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'axi-pcie-dev', including this file, 
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
use surf.AxiDmaPkg.all;
use surf.I2cPkg.all;
use surf.Pgp3Pkg.all;
use surf.SsiPkg.all;

library axi_pcie_core;
use axi_pcie_core.AxiPciePkg.all;
use axi_pcie_core.MigPkg.all;

library lcls_timing_core;
use lcls_timing_core.TimingPkg.all;

library l2si_core;
use l2si_core.L2SiPkg.all;

use work.AppMigPkg.all;

library unisim;
use unisim.vcomponents.all;

entity DrpTDetGpu is
   generic (
      TPD_G        : time := 1 ns;
      DMA_AXIS_CONFIG_G : AxiStreamConfigType := ssiAxiStreamConfig(dataBytes => 16, tDestBits => 8, tIdBits => 3);  --- 16 Byte (128-bit) tData interface
      BUILD_INFO_G : BuildInfoType);
   port (
      ---------------------
      --  Application Ports
      ---------------------
      timingRefClkP : in    sl;
      timingRefClkN : in    sl;
      timingRxP     : in    sl;
      timingRxN     : in    sl;
      timingTxP     : out   sl;
      timingTxN     : out   sl;
      userRefClkP   : in    sl;
      userRefClkN   : in    sl;
      --------------
      --  Core Ports
      --------------
      -- System Ports
      emcClk        : in    sl;
      userClkP      : in    sl;
      userClkN      : in    sl;
      swDip         : in    slv(3 downto 0);
      led           : out   slv(7 downto 0);
      i2cScl        : inout sl;
      i2cSda        : inout sl;
      i2cRstL       : out   sl;
      noi2cScl      : inout sl;
      noi2cSda      : inout sl;
      -- QSFP[0] Ports
      qsfp0RstL     : out   sl;
      qsfp0LpMode   : out   sl;
      qsfp0ModSelL  : out   sl;
      qsfp0ModPrsL  : in    sl;
      -- QSFP[1] Ports
      qsfp1RstL     : out   sl;
      qsfp1LpMode   : out   sl;
      qsfp1ModSelL  : out   sl;
      qsfp1ModPrsL  : in    sl;
      -- Boot Memory Ports 
      flashCsL      : out   sl;
      flashMosi     : out   sl;
      flashMiso     : in    sl;
      flashHoldL    : out   sl;
      flashWp       : out   sl;
      -- DDR Ports
      ddrClkP       : in    slv (1 downto 0);
      ddrClkN       : in    slv (1 downto 0);
      ddrOut        : out   DdrOutArray (1 downto 0);
      ddrInOut      : inout DdrInOutArray(1 downto 0);
      -- PCIe Ports
      pciRstL       : in    sl;
      pciRefClkP    : in    sl;
      pciRefClkN    : in    sl;
      pciRxP        : in    slv(7 downto 0);
      pciRxN        : in    slv(7 downto 0);
      pciTxP        : out   slv(7 downto 0);
      pciTxN        : out   slv(7 downto 0);
      -- Extended PCIe Interface
      pciExtRefClkP : in    sl;
      pciExtRefClkN : in    sl;
      pciExtRxP     : in    slv(7 downto 0);
      pciExtRxN     : in    slv(7 downto 0);
      pciExtTxP     : out   slv(7 downto 0);
      pciExtTxN     : out   slv(7 downto 0));
end DrpTDetGpu;

architecture top_level of DrpTDetGpu is

   signal sysClks    : slv(1 downto 0);
   signal sysRsts    : slv(1 downto 0);
   signal clk200     : slv(1 downto 0);
   signal rst200     : slv(1 downto 0);
   signal irst200    : slv(1 downto 0);
   signal urst200    : slv(1 downto 0);
   signal userClk156 : sl;
   signal userReset  : slv(1 downto 0);
   signal userSwDip  : slv(3 downto 0);
   signal userLed    : slv(7 downto 0);

   signal axilClks         : slv (1 downto 0);
   signal axilRsts         : slv (1 downto 0);
   signal axilReadMasters  : AxiLiteReadMasterArray (1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray (1 downto 0);
   signal axilWriteMasters : AxiLiteWriteMasterArray(1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray (1 downto 0);

   signal dmaObMasters : AxiStreamMasterArray (9 downto 0);
   signal dmaObSlaves  : AxiStreamSlaveArray (9 downto 0);
   signal dmaIbMasters : AxiStreamMasterArray (9 downto 0);
   signal dmaIbSlaves  : AxiStreamSlaveArray (9 downto 0);
   signal cpuIbMasters : AxiStreamMasterArray (9 downto 0);
   signal cpuIbSlaves  : AxiStreamSlaveArray (9 downto 0);

   signal usrReadMaster  : AxiReadMasterType;
   signal usrReadSlave   : AxiReadSlaveType;
   signal usrWriteMaster : AxiWriteMasterType;
   signal usrWriteSlave  : AxiWriteSlaveType;

   signal hwClks         : slv (7 downto 0);
   signal hwRsts         : slv (7 downto 0);
   signal hwObMasters    : AxiStreamMasterArray(7 downto 0);
   signal hwObSlaves     : AxiStreamSlaveArray (7 downto 0);
   signal hwIbMasters    : AxiStreamMasterArray(7 downto 0);
   signal hwIbSlaves     : AxiStreamSlaveArray (7 downto 0);
   signal hwIbAlmostFull : slv (7 downto 0);
   signal hwIbFull       : slv (7 downto 0);

   signal memReady        : slv (1 downto 0);
   signal memWriteMasters : AxiWriteMasterArray(7 downto 0);
   signal memWriteSlaves  : AxiWriteSlaveArray (7 downto 0);
   signal memReadMasters  : AxiReadMasterArray (7 downto 0);
   signal memReadSlaves   : AxiReadSlaveArray (7 downto 0);

   constant MIGTPCI_INDEX_C : integer := 0;
   constant TDETSEM_INDEX_C : integer := 1;
   constant TDETTIM_INDEX_C : integer := 2;
   constant I2C_INDEX_C     : integer := 3;

   constant CORE_I2C_C          : boolean                                                 := false;
   constant NUM_AXIL0_MASTERS_C : integer                                                 := ite(CORE_I2C_C, 3, 4);
   signal mAxil0ReadMasters     : AxiLiteReadMasterArray (NUM_AXIL0_MASTERS_C-1 downto 0) := (others => AXI_LITE_READ_MASTER_INIT_C);
   signal mAxil0ReadSlaves      : AxiLiteReadSlaveArray (NUM_AXIL0_MASTERS_C-1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_OK_C);
   signal mAxil0WriteMasters    : AxiLiteWriteMasterArray(NUM_AXIL0_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_MASTER_INIT_C);
   signal mAxil0WriteSlaves     : AxiLiteWriteSlaveArray (NUM_AXIL0_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_OK_C);

   constant NUM_AXIL1_MASTERS_C : integer                                                 := 3;
   signal mAxil1ReadMasters     : AxiLiteReadMasterArray (NUM_AXIL1_MASTERS_C-1 downto 0) := (others => AXI_LITE_READ_MASTER_INIT_C);
   signal mAxil1ReadSlaves      : AxiLiteReadSlaveArray (NUM_AXIL1_MASTERS_C-1 downto 0)  := (others => AXI_LITE_READ_SLAVE_EMPTY_OK_C);
   signal mAxil1WriteMasters    : AxiLiteWriteMasterArray(NUM_AXIL1_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_MASTER_INIT_C);
   signal mAxil1WriteSlaves     : AxiLiteWriteSlaveArray (NUM_AXIL1_MASTERS_C-1 downto 0) := (others => AXI_LITE_WRITE_SLAVE_EMPTY_OK_C);

   constant AXIL0_CROSSBAR_MASTERS_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL0_MASTERS_C-1 downto 0) := (
      0                  => (baseAddr => x"00800000",
            addrBits     => 21,
            connectivity => x"FFFF"),
      1                  => (baseAddr => x"00A00000",
            addrBits     => 21,
            connectivity => x"FFFF"),
      2                  => (baseAddr => x"00C00000",
            addrBits     => 20,
            connectivity => x"FFFF"),
      3                  => (baseAddr => x"00E00000",
            addrBits     => 21,
            connectivity => x"FFFF"));
   constant AXIL1_CROSSBAR_MASTERS_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL1_MASTERS_C-1 downto 0) := (
      0                  => (baseAddr => x"00800000",
            addrBits     => 21,
            connectivity => x"FFFF"),
      1                  => (baseAddr => x"00A00000",
            addrBits     => 21,
            connectivity => x"FFFF"),
      2                  => (baseAddr => x"00C00000",
            addrBits     => 20,
            connectivity => x"FFFF"));

   constant AXILT_CROSSBAR_MASTERS_CONFIG_C : AxiLiteCrossbarMasterConfigArray(0 downto 0) := (
      0 => AXIL0_CROSSBAR_MASTERS_CONFIG_C(TDETTIM_INDEX_C));

   signal tdetAxilReadMasters  : AxiLiteReadMasterArray (1 downto 0);
   signal tdetAxilReadSlaves   : AxiLiteReadSlaveArray (1 downto 0);
   signal tdetAxilWriteMasters : AxiLiteWriteMasterArray(1 downto 0);
   signal tdetAxilWriteSlaves  : AxiLiteWriteSlaveArray (1 downto 0);

   signal mtpIbMasters        : AxiStreamMasterArray (9 downto 0);
   signal mtpIbSlaves         : AxiStreamSlaveArray (9 downto 0);
   signal mtpAxilReadMasters  : AxiLiteReadMasterArray (1 downto 0);
   signal mtpAxilReadSlaves   : AxiLiteReadSlaveArray (1 downto 0);
   signal mtpAxilWriteMasters : AxiLiteWriteMasterArray(1 downto 0);
   signal mtpAxilWriteSlaves  : AxiLiteWriteSlaveArray (1 downto 0);

   signal ttimAxilReadMasters  : AxiLiteReadMasterArray (1 downto 0);
   signal ttimAxilReadSlaves   : AxiLiteReadSlaveArray (1 downto 0);
   signal ttimAxilWriteMasters : AxiLiteWriteMasterArray(1 downto 0);
   signal ttimAxilWriteSlaves  : AxiLiteWriteSlaveArray (1 downto 0);

   signal ttimAxilReadMaster  : AxiLiteReadMasterType;
   signal ttimAxilReadSlave   : AxiLiteReadSlaveType;
   signal ttimAxilWriteMaster : AxiLiteWriteMasterType;
   signal ttimAxilWriteSlave  : AxiLiteWriteSlaveType;
   
   signal gpuReadMaster   : AxiLiteReadMasterType;
   signal gpuReadSlave    : AxiLiteReadSlaveType;
   signal gpuWriteMaster  : AxiLiteWriteMasterType;
   signal  gpuWriteSlave   : AxiLiteWriteSlaveType;


   signal migConfig : MigConfigArray(7 downto 0) := (others => MIG_CONFIG_INIT_C);
   signal migStatus : MigStatusArray(7 downto 0);


   signal mmcmClkOut : Slv3Array(1 downto 0);
   signal mmcmRstOut : Slv3Array(1 downto 0);

   constant NDET_C       : integer := 8;
   signal tdetClk        : sl;
   signal tdetRst        : sl;
   signal tdetAlmostFull : slv(NDET_C-1 downto 0);
   signal tdetTimingMsgs : TimingMessageArray (NDET_C-1 downto 0);
   signal tdetTimingRds  : slv (NDET_C-1 downto 0);
   signal tdetInhibitCts : TriggerInhibitCountsArray(NDET_C-1 downto 0);
   signal tdetInhibitRds : slv (NDET_C-1 downto 0);
   signal tdetAxisM      : AxiStreamMasterArray (NDET_C-1 downto 0);
   signal tdetAxisS      : AxiStreamSlaveArray (NDET_C-1 downto 0);
   signal timingRefClk   : sl;
   signal userRefClock   : sl;

   constant DEVICE_MAP_C : I2cAxiLiteDevArray(3 downto 0) := (
      -----------------------
      -- PC821 I2C DEVICES --
      -----------------------
      -- PCA9548A I2C Mux
      0 => MakeI2cAxiLiteDevType("1110100", 8, 0, '0'),
      -- QSFP1, QSFP0, EEPROM;  I2C Mux = 1, 4, 5
      1 => MakeI2cAxiLiteDevType("1010000", 8, 8, '0'),
      -- SI570                  I2C Mux = 2
      2 => MakeI2cAxiLiteDevType("1011101", 8, 8, '0'),
      -- Fan                    I2C Mux = 3
      3 => MakeI2cAxiLiteDevType("1001100", 8, 8, '0'));

   signal rdDescReq    : AxiReadDmaDescReqArray(7 downto 0);
   signal rdDescRet    : AxiReadDmaDescRetArray(7 downto 0);
   signal rdDescReqAck : slv(7 downto 0);
   signal rdDescRetAck : slv(7 downto 0);

   signal qsfpModPrsL : slv(1 downto 0);

   constant AXIO_STREAM_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C    => false,
      TDATA_BYTES_C => 16,
      TDEST_BITS_C  => 0,
      TID_BITS_C    => 0,
      TKEEP_MODE_C  => TKEEP_NORMAL_C,
      TUSER_BITS_C  => 2,
      TUSER_MODE_C  => TUSER_NORMAL_C);

   constant DMA_STREAM_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C    => false,
      TDATA_BYTES_C => 32,
      TDEST_BITS_C  => 0,
      TID_BITS_C    => 0,
      TKEEP_MODE_C  => TKEEP_NORMAL_C,
      TUSER_BITS_C  => 2,
      TUSER_MODE_C  => TUSER_NORMAL_C);

   signal monClkRate : Slv29Array(1 downto 0);
   signal monClkLock : slv (1 downto 0);
   signal monClkFast : slv (1 downto 0);
   signal monClkSlow : slv (1 downto 0);

begin

   qsfpModPrsL(0) <= qsfp0ModPrsL;
   qsfpModPrsL(1) <= qsfp1ModPrsL;

   --
   --  Use MGTREFCLK1 (non-programmable) for 156.25 MHz base clock
   --
   U_BUFG_GT : BUFG_GT
      port map (
         I       => userRefClock,
         CE      => '1',
         CLR     => '0',
         CEMASK  => '1',
         CLRMASK => '1',
         DIV     => "000",              -- Divide by 1
         O       => userClk156);

   U_pgpRefClk : IBUFDS_GTE3
      generic map (
         REFCLK_EN_TX_PATH  => '0',
         REFCLK_HROW_CK_SEL => "00",    -- 2'b00: ODIV2
         REFCLK_ICNTL_RX    => "00")
      port map (
         I     => userRefClkP,
         IB    => userRefClkN,
         CEB   => '0',
         ODIV2 => userRefClock,
         O     => open);

   U_AxilXbar0 : entity surf.AxiLiteCrossbar
      generic map (NUM_SLAVE_SLOTS_G  => 1,
                   NUM_MASTER_SLOTS_G => AXIL0_CROSSBAR_MASTERS_CONFIG_C'length,
                   MASTERS_CONFIG_G   => AXIL0_CROSSBAR_MASTERS_CONFIG_C)
      port map (axiClk              => axilClks (0),
                axiClkRst           => axilRsts (0),
                sAxiWriteMasters(0) => axilWriteMasters(0),
                sAxiWriteSlaves (0) => axilWriteSlaves (0),
                sAxiReadMasters (0) => axilReadMasters (0),
                sAxiReadSlaves (0)  => axilReadSlaves (0),
                mAxiWriteMasters    => mAxil0WriteMasters,
                mAxiWriteSlaves     => mAxil0WriteSlaves,
                mAxiReadMasters     => mAxil0ReadMasters,
                mAxiReadSlaves      => mAxil0ReadSlaves);

   U_AxilXbar1 : entity surf.AxiLiteCrossbar
      generic map (NUM_SLAVE_SLOTS_G  => 1,
                   NUM_MASTER_SLOTS_G => AXIL1_CROSSBAR_MASTERS_CONFIG_C'length,
                   MASTERS_CONFIG_G   => AXIL1_CROSSBAR_MASTERS_CONFIG_C)
      port map (axiClk              => axilClks (1),
                axiClkRst           => axilRsts (1),
                sAxiWriteMasters(0) => axilWriteMasters(1),
                sAxiWriteSlaves (0) => axilWriteSlaves (1),
                sAxiReadMasters (0) => axilReadMasters (1),
                sAxiReadSlaves (0)  => axilReadSlaves (1),
                mAxiWriteMasters    => mAxil1WriteMasters,
                mAxiWriteSlaves     => mAxil1WriteSlaves,
                mAxiReadMasters     => mAxil1ReadMasters,
                mAxiReadSlaves      => mAxil1ReadSlaves);

   ttimAxilReadMasters (0)            <= mAxil0ReadMasters (TDETTIM_INDEX_C);
   ttimAxilWriteMasters(0)            <= mAxil0WriteMasters(TDETTIM_INDEX_C);
   mAxil0ReadSlaves (TDETTIM_INDEX_C) <= ttimAxilReadSlaves (0);
   mAxil0WriteSlaves(TDETTIM_INDEX_C) <= ttimAxilWriteSlaves (0);

   U_AxilAsync : entity surf.AxiLiteAsync
      generic map (TPD_G => TPD_G)
      port map (sAxiClk         => axilClks(1),
                sAxiClkRst      => axilRsts(1),
                sAxiReadMaster  => mAxil1ReadMasters (TDETTIM_INDEX_C),
                sAxiReadSlave   => mAxil1ReadSlaves (TDETTIM_INDEX_C),
                sAxiWriteMaster => mAxil1WriteMasters(TDETTIM_INDEX_C),
                sAxiWriteSlave  => mAxil1WriteSlaves (TDETTIM_INDEX_C),
                mAxiClk         => axilClks(0),
                mAxiClkRst      => axilRsts(0),
                mAxiReadMaster  => ttimAxilReadMasters (1),
                mAxiReadSlave   => ttimAxilReadSlaves (1),
                mAxiWriteMaster => ttimAxilWriteMasters(1),
                mAxiWriteSlave  => ttimAxilWriteSlaves (1));

   U_AxilXbarT : entity surf.AxiLiteCrossbar
      generic map (NUM_SLAVE_SLOTS_G  => 2,
                   NUM_MASTER_SLOTS_G => 1,
                   MASTERS_CONFIG_G   => AXILT_CROSSBAR_MASTERS_CONFIG_C)
      port map (axiClk              => axilClks (0),
                axiClkRst           => axilRsts (0),
                sAxiWriteMasters    => ttimAxilWriteMasters,
                sAxiWriteSlaves     => ttimAxilWriteSlaves,
                sAxiReadMasters     => ttimAxilReadMasters,
                sAxiReadSlaves      => ttimAxilReadSlaves,
                mAxiWriteMasters(0) => ttimAxilWriteMaster,
                mAxiWriteSlaves (0) => ttimAxilWriteSlave,
                mAxiReadMasters (0) => ttimAxilReadMaster,
                mAxiReadSlaves (0)  => ttimAxilReadSlave);

   tdetAxilReadMasters (0)            <= mAxil0ReadMasters (TDETSEM_INDEX_C);
   tdetAxilWriteMasters(0)            <= mAxil0WriteMasters(TDETSEM_INDEX_C);
   mAxil0ReadSlaves (TDETSEM_INDEX_C) <= tdetAxilReadSlaves (0);
   mAxil0WriteSlaves(TDETSEM_INDEX_C) <= tdetAxilWriteSlaves(0);

   tdetAxilReadMasters (1)            <= mAxil1ReadMasters (TDETSEM_INDEX_C);
   tdetAxilWriteMasters(1)            <= mAxil1WriteMasters(TDETSEM_INDEX_C);
   mAxil1ReadSlaves (TDETSEM_INDEX_C) <= tdetAxilReadSlaves (1);
   mAxil1WriteSlaves(TDETSEM_INDEX_C) <= tdetAxilWriteSlaves(1);

   mtpAxilReadMasters (0)             <= mAxil0ReadMasters (MIGTPCI_INDEX_C);
   mtpAxilWriteMasters(0)             <= mAxil0WriteMasters(MIGTPCI_INDEX_C);
   mAxil0ReadSlaves (MIGTPCI_INDEX_C) <= mtpAxilReadSlaves (0);
   mAxil0WriteSlaves(MIGTPCI_INDEX_C) <= mtpAxilWriteSlaves(0);

   mtpAxilReadMasters (1)             <= mAxil1ReadMasters (MIGTPCI_INDEX_C);
   mtpAxilWriteMasters(1)             <= mAxil1WriteMasters(MIGTPCI_INDEX_C);
   mAxil1ReadSlaves (MIGTPCI_INDEX_C) <= mtpAxilReadSlaves (1);
   mAxil1WriteSlaves(MIGTPCI_INDEX_C) <= mtpAxilWriteSlaves(1);

   U_I2C : entity surf.AxiI2cRegMaster
      generic map (DEVICE_MAP_G   => DEVICE_MAP_C,
                   AXI_CLK_FREQ_G => 125.0E+6)
      port map (scl            => i2cScl,
                sda            => i2cSda,
                axiReadMaster  => mAxil0ReadMasters (I2C_INDEX_C),
                axiReadSlave   => mAxil0ReadSlaves (I2C_INDEX_C),
                axiWriteMaster => mAxil0WriteMasters(I2C_INDEX_C),
                axiWriteSlave  => mAxil0WriteSlaves (I2C_INDEX_C),
                axiClk         => axilClks(0),
                axiRst         => axilRsts(0));

   U_Timing : entity work.TDetTiming
      generic map (NDET_G          => 8,
                   AXIL_BASEADDR_G => AXIL0_CROSSBAR_MASTERS_CONFIG_C(TDETTIM_INDEX_C).baseAddr)
      port map (                        -- AXI-Lite Interface
         axilClk         => axilClks(0),
         axilRst         => axilRsts(0),
         axilReadMaster  => ttimAxilReadMaster,
         axilReadSlave   => ttimAxilReadSlave,
         axilWriteMaster => ttimAxilWriteMaster,
         axilWriteSlave  => ttimAxilWriteSlave,
         -- Timing Interface
         tdetClk         => tdetClk,
         tdetAlmostFull  => tdetAlmostFull,
         tdetTimingMsgs  => tdetTimingMsgs,
         tdetTimingRds   => tdetTimingRds,
         tdetInhibitCts  => tdetInhibitCts,
         tdetInhibitRds  => tdetInhibitRds,
         tdetAxisMaster  => tdetAxisM,
         tdetAxisSlave   => tdetAxisS,
         -- Timing Phy Ports
         timingRxP       => timingRxP,
         timingRxN       => timingRxN,
         timingTxP       => timingTxP,
         timingTxN       => timingTxN,
         timingRefClkInP => timingRefClkP,
         timingRefClkInN => timingRefClkN,
         timingRefClkOut => timingRefClk);

   tdetClk <= mmcmClkOut(0)(2);
   tdetRst <= mmcmRstOut(0)(2);

   GEN_SEMI : for i in 0 to 1 generate
      clk200 (i)  <= mmcmClkOut(i)(0);
      axilClks(i) <= mmcmClkOut(i)(1);
      axilRsts(i) <= mmcmRstOut(i)(1);

      -- Forcing BUFG for reset that's used everywhere      
      U_BUFG : BUFG
         port map (
            I => mmcmRstOut(i)(0),
            O => rst200(i));

      irst200(i) <= rst200(i) or userReset(i);
      -- Forcing BUFG for reset that's used everywhere      
      U_BUFGU : BUFG
         port map (
            I => irst200(i),
            O => urst200(i));

      U_MMCM : entity surf.ClockManagerUltraScale
         generic map (INPUT_BUFG_G       => false,
                      NUM_CLOCKS_G       => 3,
                      CLKIN_PERIOD_G     => 6.4,
                      DIVCLK_DIVIDE_G    => 1,
                      CLKFBOUT_MULT_F_G  => 8.0,   -- 1.25 GHz
                      CLKOUT0_DIVIDE_F_G => 6.25,  -- 200 MHz
                      CLKOUT1_DIVIDE_G   => 10,    -- 125 MHz
                      CLKOUT2_DIVIDE_G   => 8)     -- 156.25 MHz
         port map (clkIn  => userClk156,
                   rstIn  => '0',
                   clkOut => mmcmClkOut(i),
                   rstOut => mmcmRstOut(i));

      U_Hw : entity work.TDetSemi
         generic map (DEBUG_G => (i < 1))
         port map (
            ------------------------      
            --  Top Level Interfaces
            ------------------------         
            -- AXI-Lite Interface (axilClk domain)
            axilClk         => axilClks (i),
            axilRst         => axilRsts (i),
            axilReadMaster  => tdetAxilReadMasters (i),
            axilReadSlave   => tdetAxilReadSlaves (i),
            axilWriteMaster => tdetAxilWriteMasters(i),
            axilWriteSlave  => tdetAxilWriteSlaves (i),
            -- DMA Interface (dmaClk domain)
            dmaClks         => hwClks (4*i+3 downto 4*i),
            dmaRsts         => hwRsts (4*i+3 downto 4*i),
            dmaObMasters    => hwObMasters (4*i+3 downto 4*i),
            dmaObSlaves     => hwObSlaves (4*i+3 downto 4*i),
            dmaIbMasters    => hwIbMasters (4*i+3 downto 4*i),
            dmaIbSlaves     => hwIbSlaves (4*i+3 downto 4*i),
            dmaIbAlmostFull => hwIbAlmostFull(4*i+3 downto 4*i),
            dmaIbFull       => hwIbFull (4*i+3 downto 4*i),
            ------------------
            --  TDET Ports
            ------------------       
            tdetClk         => tdetClk,
            tdetClkRst      => tdetRst,
            tdetAlmostFull  => tdetAlmostFull(4*i+3 downto 4*i),
            tdetTimingMsgs  => tdetTimingMsgs(4*i+3 downto 4*i),
            tdetTimingRds   => tdetTimingRds (4*i+3 downto 4*i),
            tdetInhibitCts  => tdetInhibitCts(4*i+3 downto 4*i),
            tdetInhibitRds  => tdetInhibitRds(4*i+3 downto 4*i),
            tdetAxisMaster  => tdetAxisM (4*i+3 downto 4*i),
            tdetAxisSlave   => tdetAxisS (4*i+3 downto 4*i),
            modPrsL         => qsfpModPrsL(i));

      GEN_HWDMA : for j in 4*i+0 to 4*i+3 generate
         U_HwDma : entity work.AppToMigDma
            generic map (AXI_BASE_ADDR_G => (toSlv(j, 2) & toSlv(0, 30)))
            port map (sAxisClk        => hwClks (j),
                      sAxisRst        => hwRsts (j),
                      sAxisMaster     => hwIbMasters (j),
                      sAxisSlave      => hwIbSlaves (j),
                      sAlmostFull     => hwIbAlmostFull (j),
                      sFull           => hwIbFull (j),
                      mAxiClk         => clk200 (i),
                      mAxiRst         => urst200 (i),
                      mAxiWriteMaster => memWriteMasters(j),
                      mAxiWriteSlave  => memWriteSlaves (j),
                      rdDescReq       => rdDescReq (j),  -- exchange
                      rdDescReqAck    => rdDescReqAck (j),
                      rdDescRet       => rdDescRet (j),
                      rdDescRetAck    => rdDescRetAck (j),
                      memReady        => memReady (i),
                      config          => migConfig (j),
                      status          => migStatus (j));
         U_ObFifo : entity surf.AxiStreamFifoV2
            generic map (FIFO_ADDR_WIDTH_G   => 4,
                         SLAVE_AXI_CONFIG_G  => DMA_STREAM_CONFIG_C,
                         MASTER_AXI_CONFIG_G => PGP3_AXIS_CONFIG_C)
            port map (sAxisClk    => sysClks (i),
                      sAxisRst    => sysRsts (i),
                      sAxisMaster => dmaObMasters(j+i),
                      sAxisSlave  => dmaObSlaves (j+i),
                      sAxisCtrl   => open,
                      mAxisClk    => hwClks (j),
                      mAxisRst    => hwRsts (j),
                      mAxisMaster => hwObMasters (j),
                      mAxisSlave  => hwObSlaves (j));
      end generate;

      U_Mig2Pcie : entity work.MigToPcieDma
         generic map (LANES_G       => 4,
                      MONCLKS_G     => 4,
                      AXIS_CONFIG_G => AXIO_STREAM_CONFIG_C,
                      DEBUG_G       => true)
--                     DEBUG_G          => (i<1) )
         port map (axiClk          => clk200(i),
                   axiRst          => rst200(i),
                   usrRst          => userReset(i),
                   axiReadMasters  => memReadMasters(4*i+3 downto 4*i),
                   axiReadSlaves   => memReadSlaves (4*i+3 downto 4*i),
                   rdDescReq       => rdDescReq (4*i+3 downto 4*i),
                   rdDescAck       => rdDescReqAck (4*i+3 downto 4*i),
                   rdDescRet       => rdDescRet (4*i+3 downto 4*i),
                   rdDescRetAck    => rdDescRetAck (4*i+3 downto 4*i),
                   axisMasters     => mtpIbMasters (5*i+4 downto 5*i),
                   axisSlaves      => mtpIbSlaves (5*i+4 downto 5*i),
                   axilClk         => axilClks (i),
                   axilRst         => axilRsts (i),
                   axilWriteMaster => mtpAxilWriteMasters(i),
                   axilWriteSlave  => mtpAxilWriteSlaves (i),
                   axilReadMaster  => mtpAxilReadMasters (i),
                   axilReadSlave   => mtpAxilReadSlaves (i),
                   monClk(0)       => axilClks (1-i),
                   monClk(1)       => timingRefClk,
                   monClk(2)       => clk200 (0),
                   monClk(3)       => clk200 (1),
                   migConfig       => migConfig (4*i+3 downto 4*i),
                   migStatus       => migStatus (4*i+3 downto 4*i));

      GEN_DMAIB : for j in 5*i to 5*i+4 generate
         U_IbFifo : entity surf.AxiStreamFifoV2
            generic map (
               -- General Configurations
               INT_PIPE_STAGES_G   => 1,
               PIPE_STAGES_G       => 1,
               -- FIFO configurations
               FIFO_ADDR_WIDTH_G   => 4,
               -- AXI Stream Port Configurations
               SLAVE_AXI_CONFIG_G  => AXIO_STREAM_CONFIG_C,
               MASTER_AXI_CONFIG_G => DMA_AXIS_CONFIG_G) --DMA_STREAM_CONFIG_C
            port map (
               -- Slave Port
               sAxisClk    => clk200(i),
               sAxisRst    => rst200(i),
               sAxisMaster => mtpIbMasters(j),
               sAxisSlave  => mtpIbSlaves (j),
               -- Master Port
               mAxisClk    => sysClks(i),
               mAxisRst    => sysRsts(i),
               mAxisMaster => dmaIbMasters(j),
               mAxisSlave  => dmaIbSlaves (j));
      end generate;
   end generate;
   
   AxiPcieGpuAsyncCore_inst : entity axi_pcie_core.AxiPcieGpuAsyncCore
      generic map (
         TPD_G             => TPD_G,
         MAX_BUFFERS_G     => 4,
         DMA_AXIS_CONFIG_G => DMA_AXIS_CONFIG_G
         )
      port map (
         axilClk         => axilClks (0),
         axilRst         => axilRsts (0),
         axilReadMaster  => gpuReadMaster,
         axilReadSlave   => gpuReadSlave,
         axilWriteMaster => gpuWriteMaster,
         axilWriteSlave  => gpuWriteSlave,
         axisClk         => sysClks(0),
         axisRst         => sysRsts(0),
         sAxisMaster     => dmaIbMasters(0),
         sAxisSlave      => dmaIbSlaves (0),
         mAxisMaster     => open,
         mAxisSlave      => AXI_STREAM_SLAVE_FORCE_C,
         bypassMaster    => cpuIbMasters(0),
         bypassSlave     => cpuIbSlaves(0),
         -- AXI4 Interfaces (axiClk domain)
         axiClk          => sysClks(0),
         axiRst          => sysRsts(0),
         axiWriteMaster  => usrWriteMaster,
         axiWriteSlave   => usrWriteSlave,
         axiReadMaster   => usrReadMaster,
         axiReadSlave    => usrReadSlave
         );
         
    cpuIbMasters(4 downto 1) <= dmaIbMasters(4 downto 1);     
    dmaIbSlaves(4 downto 1)  <= cpuIbSlaves(4 downto 1);  
    
   U_Core : entity axi_pcie_core.XilinxKcu1500Core
      generic map (
         TPD_G             => TPD_G,
         DRIVER_TYPE_ID_G  => toSlv(0, 32),
         DMA_SIZE_G        => 5,
         BUILD_INFO_G      => BUILD_INFO_G,
         DMA_AXIS_CONFIG_G => DMA_AXIS_CONFIG_G) --DMA_STREAM_CONFIG_C
      port map (
         ------------------------      
         --  Top Level Interfaces
         ------------------------
         userClk156                        => open,  -- one programmable clock
--      userSwDip       => userSwDip,
--      userLed         => userLed,
         -- System Clock and Reset
         dmaClk                            => sysClks(0),
         dmaRst                            => sysRsts(0),
         -- DMA Interfaces
         dmaObMasters (5*0+4 downto 5*0)   => dmaObMasters   (5*0+4 downto 5*0),
         dmaObSlaves (5*0+4 downto 5*0)    => dmaObSlaves    (5*0+4 downto 5*0),
         dmaIbMasters (5*0+4 downto 5*0)   => cpuIbMasters   (5*0+4 downto 5*0),
         dmaIbSlaves (5*0+4 downto 5*0)    => cpuIbSlaves    (5*0+4 downto 5*0),
         -- User General Purpose AXI4 Interfaces (dmaClk domain)
         usrReadMaster                     => usrReadMaster,
         usrReadSlave                      => usrReadSlave,
         usrWriteMaster                    => usrWriteMaster,
         usrWriteSlave                     => usrWriteSlave,
         -- AXI-Lite Interface
         appClk                            => axilClks (0),
         appRst                            => axilRsts (0),
         appReadMaster                     => axilReadMasters (0),
         appReadSlave                      => axilReadSlaves (0),
         appWriteMaster                    => axilWriteMasters(0),
         appWriteSlave                     => axilWriteSlaves (0),
         -- AXI-Lite Interface
         gpuReadMaster                     => gpuReadMaster,
         gpuReadSlave                      => gpuReadSlave,
         gpuWriteMaster                    => gpuWriteMaster,
         gpuWriteSlave                     => gpuWriteSlave,
         --------------
         --  Core Ports
         --------------
         emcClk                            => emcClk,
         userClkP                          => userClkP,
         userClkN                          => userClkN,
         --  Pass unmapped I2c bus
         i2cRstL                           => i2cRstL,
         i2cScl                            => noi2cScl,
         i2cSda                            => noi2cSda,
--      swDip           => swDip,
--      led             => led,
         -- QSFP[0] Ports
         qsfp0RstL                         => qsfp0RstL,
         qsfp0LpMode                       => qsfp0LpMode,
         qsfp0ModSelL                      => qsfp0ModSelL,
         qsfp0ModPrsL                      => qsfp0ModPrsL,
         -- QSFP[1] Ports
         qsfp1RstL                         => qsfp1RstL,
         qsfp1LpMode                       => qsfp1LpMode,
         qsfp1ModSelL                      => qsfp1ModSelL,
         qsfp1ModPrsL                      => qsfp1ModPrsL,
         -- Boot Memory Ports 
         flashCsL                          => flashCsL,
         flashMosi                         => flashMosi,
         flashMiso                         => flashMiso,
         flashHoldL                        => flashHoldL,
         flashWp                           => flashWp,
         -- PCIe Ports 
         pciRstL                           => pciRstL,
         pciRefClkP                        => pciRefClkP,
         pciRefClkN                        => pciRefClkN,
         pciRxP                            => pciRxP,
         pciRxN                            => pciRxN,
         pciTxP                            => pciTxP,
         pciTxN                            => pciTxN);

   U_Extended : entity axi_pcie_core.XilinxKcu1500PcieExtendedCore
      generic map (TPD_G             => TPD_G,
                   BUILD_INFO_G      => BUILD_INFO_G,
                   DRIVER_TYPE_ID_G  => toSlv(1, 32),
                   DMA_SIZE_G        => 5,
                   DMA_AXIS_CONFIG_G => DMA_AXIS_CONFIG_G) --DMA_STREAM_CONFIG_C
      port map (
         ------------------------      
         --  Top Level Interfaces
         ------------------------        
         -- DMA Interfaces
         dmaClk         => sysClks(1),
         dmaRst         => sysRsts(1),
         --
         dmaObMasters   => dmaObMasters (5*1+4 downto 5*1),
         dmaObSlaves    => dmaObSlaves (5*1+4 downto 5*1),
         dmaIbMasters   => dmaIbMasters (5*1+4 downto 5*1),
         dmaIbSlaves    => dmaIbSlaves (5*1+4 downto 5*1),
         -- AXI-Lite Interface
         appClk         => axilClks (1),
         appRst         => axilRsts (1),
         appReadMaster  => axilReadMasters (1),
         appReadSlave   => axilReadSlaves (1),
         appWriteMaster => axilWriteMasters(1),
         appWriteSlave  => axilWriteSlaves (1),
         --------------
         --  Core Ports
         --------------   
         -- Extended PCIe Ports 
         pciRstL        => pciRstL,
         pciExtRefClkP  => pciExtRefClkP,
         pciExtRefClkN  => pciExtRefClkN,
         pciExtRxP      => pciExtRxP,
         pciExtRxN      => pciExtRxN,
         pciExtTxP      => pciExtTxP,
         pciExtTxN      => pciExtTxN);

   U_MIG0 : entity work.MigA
      port map (axiReady        => memReady(0),
                --
                axiClk          => clk200 (0),
                axiRst          => urst200 (0),
                axiWriteMasters => memWriteMasters(3 downto 0),
                axiWriteSlaves  => memWriteSlaves (3 downto 0),
                axiReadMasters  => memReadMasters (3 downto 0),
                axiReadSlaves   => memReadSlaves (3 downto 0),
                --
                ddrClkP         => ddrClkP (0),
                ddrClkN         => ddrClkN (0),
                ddrOut          => ddrOut (0),
                ddrInOut        => ddrInOut(0));

   U_MIG1 : entity work.MigB
      port map (axiReady        => memReady(1),
                --
                axiClk          => clk200 (1),
                axiRst          => urst200 (1),
                axiWriteMasters => memWriteMasters(7 downto 4),
                axiWriteSlaves  => memWriteSlaves (7 downto 4),
                axiReadMasters  => memReadMasters (7 downto 4),
                axiReadSlaves   => memReadSlaves (7 downto 4),
                --
                ddrClkP         => ddrClkP (1),
                ddrClkN         => ddrClkN (1),
                ddrOut          => ddrOut (1),
                ddrInOut        => ddrInOut(1));

   -- Unused user signals
   userLed <= (others => '0');

end top_level;
