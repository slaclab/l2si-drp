-------------------------------------------------------------------------------
-- File       : DrpPgpIlvx2.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-24
-- Last update: 2021-09-27
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

library axi_pcie_core;
use axi_pcie_core.AxiPciePkg.all;
use axi_pcie_core.MigPkg.all;

use work.AppMigPkg.all;

library unisim;
use unisim.vcomponents.all;

entity DrpPgpIlv is
   generic (
      TPD_G        : time := 1 ns;
      BUILD_INFO_G : BuildInfoType);
   port (
      ---------------------
      --  Application Ports
      ---------------------
      -- QSFP[0] Ports
      qsfp0RefClkP  : in    slv(1 downto 0);
      qsfp0RefClkN  : in    slv(1 downto 0);
      qsfp0RxP      : in    slv(3 downto 0);
      qsfp0RxN      : in    slv(3 downto 0);
      qsfp0TxP      : out   slv(3 downto 0);
      qsfp0TxN      : out   slv(3 downto 0);
      -- QSFP[1] Ports
      qsfp1RefClkP  : in    slv(1 downto 0);
      qsfp1RefClkN  : in    slv(1 downto 0);
      qsfp1RxP      : in    slv(3 downto 0);
      qsfp1RxN      : in    slv(3 downto 0);
      qsfp1TxP      : out   slv(3 downto 0);
      qsfp1TxN      : out   slv(3 downto 0);
      --------------
      --  Core Ports
      --------------
      -- System Ports
      emcClk       : in    sl;
      userClkP     : in    sl;
      userClkN     : in    sl;
      swDip        : in    slv(3 downto 0);
      led          : out   slv(7 downto 0);
      scl          : inout sl;
      sda          : inout sl;
      i2c_rst_l    : out   sl;
      -- QSFP[0] Ports
      qsfp0RstL    : out   sl;
      qsfp0LpMode  : out   sl;
      qsfp0ModSelL : out   sl;
      qsfp0ModPrsL : in    sl;
      -- QSFP[1] Ports
      qsfp1RstL    : out   sl;
      qsfp1LpMode  : out   sl;
      qsfp1ModSelL : out   sl;
      qsfp1ModPrsL : in    sl;
      -- Boot Memory Ports 
      flashCsL     : out   sl;
      flashMosi    : out   sl;
      flashMiso    : in    sl;
      flashHoldL   : out   sl;
      flashWp      : out   sl;
      -- DDR Ports
      ddrClkP      : in    slv          (1 downto 0);
      ddrClkN      : in    slv          (1 downto 0);
      ddrOut       : out   DdrOutArray  (1 downto 0);
      ddrInOut     : inout DdrInOutArray(1 downto 0);
      -- PCIe Ports
      pciRstL      : in    sl;
      pciRefClkP   : in    sl;
      pciRefClkN   : in    sl;
      pciRxP       : in    slv(7 downto 0);
      pciRxN       : in    slv(7 downto 0);
      pciTxP       : out   slv(7 downto 0);
      pciTxN       : out   slv(7 downto 0);
      -- Extended PCIe Interface
      pciExtRefClkP   : in    sl;
      pciExtRefClkN   : in    sl;
      pciExtRxP       : in    slv(7 downto 0);
      pciExtRxN       : in    slv(7 downto 0);
      pciExtTxP       : out   slv(7 downto 0);
      pciExtTxN       : out   slv(7 downto 0) );
end DrpPgpIlv;

architecture top_level of DrpPgpIlv is

   signal sysClks    : slv(1 downto 0);
   signal sysRsts    : slv(1 downto 0);
   signal clk200     : slv(1 downto 0);
   signal rst200     : slv(1 downto 0);
   signal irst200    : slv(1 downto 0);
   signal urst200    : slv(1 downto 0);
   signal rst200U    : slv(1 downto 0);
   signal irst200U   : slv(1 downto 0);
   signal urst200U   : slv(1 downto 0);
   signal userClk156 : sl;
   signal userReset  : slv(1 downto 0);
   signal userSwDip  : slv(3 downto 0);
   signal userLed    : slv(7 downto 0);

   signal axilClks         : slv                    (1 downto 0);
   signal axilRsts         : slv                    (1 downto 0);
   signal axilReadMasters  : AxiLiteReadMasterArray (1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray  (1 downto 0);
   signal axilWriteMasters : AxiLiteWriteMasterArray(1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray (1 downto 0);

   signal dmaObMasters    : AxiStreamMasterArray (1 downto 0);
   signal dmaObSlaves     : AxiStreamSlaveArray  (1 downto 0);
   signal dmaIbMasters    : AxiStreamMasterArray (1 downto 0);
   signal dmaIbSlaves     : AxiStreamSlaveArray  (1 downto 0);

   signal hwClks          : slv                 (7 downto 0);
   signal hwRsts          : slv                 (7 downto 0);
   signal hwObMasters     : AxiStreamMasterArray(7 downto 0) := (others=>AXI_STREAM_MASTER_INIT_C);
   signal hwObSlaves      : AxiStreamSlaveArray (7 downto 0);
   signal hwIbMasters     : AxiStreamMasterArray(7 downto 0);
   signal hwIbSlaves      : AxiStreamSlaveArray (7 downto 0);
   signal hwIbAlmostFull  : slv                 (7 downto 0);
   signal hwIbFull        : slv                 (7 downto 0);
   signal hwIbOflow       : slv                 (7 downto 0);
   signal hwIbFifoThres   : Slv16Array          (1 downto 0);
   signal hwIbFifoDepth   : Slv16Array          (7 downto 0);

   signal memReady        : slv                (1 downto 0);
   signal memWriteMasters : AxiWriteMasterArray(7 downto 0);
   signal memWriteSlaves  : AxiWriteSlaveArray (7 downto 0);
   signal memReadMasters  : AxiReadMasterArray (7 downto 0);
   signal memReadSlaves   : AxiReadSlaveArray  (7 downto 0);

   constant MIGTPCI_INDEX_C   : integer := 0;
   constant HWSEM_INDEX_C     : integer := 1;
   constant I2C_INDEX_C       : integer := 2;

   constant NUM_AXIL0_MASTERS_C : integer := 3;
   signal mAxil0ReadMasters  : AxiLiteReadMasterArray (NUM_AXIL0_MASTERS_C-1 downto 0) := (others=>AXI_LITE_READ_MASTER_INIT_C);
   signal mAxil0ReadSlaves   : AxiLiteReadSlaveArray  (NUM_AXIL0_MASTERS_C-1 downto 0) := (others=>AXI_LITE_READ_SLAVE_EMPTY_OK_C);
   signal mAxil0WriteMasters : AxiLiteWriteMasterArray(NUM_AXIL0_MASTERS_C-1 downto 0) := (others=>AXI_LITE_WRITE_MASTER_INIT_C);
   signal mAxil0WriteSlaves  : AxiLiteWriteSlaveArray (NUM_AXIL0_MASTERS_C-1 downto 0) := (others=>AXI_LITE_WRITE_SLAVE_EMPTY_OK_C);

   constant NUM_AXIL1_MASTERS_C : integer := 3;
   signal mAxil1ReadMasters  : AxiLiteReadMasterArray (NUM_AXIL1_MASTERS_C-1 downto 0) := (others=>AXI_LITE_READ_MASTER_INIT_C);
   signal mAxil1ReadSlaves   : AxiLiteReadSlaveArray  (NUM_AXIL1_MASTERS_C-1 downto 0) := (others=>AXI_LITE_READ_SLAVE_EMPTY_OK_C);
   signal mAxil1WriteMasters : AxiLiteWriteMasterArray(NUM_AXIL1_MASTERS_C-1 downto 0) := (others=>AXI_LITE_WRITE_MASTER_INIT_C);
   signal mAxil1WriteSlaves  : AxiLiteWriteSlaveArray (NUM_AXIL1_MASTERS_C-1 downto 0) := (others=>AXI_LITE_WRITE_SLAVE_EMPTY_OK_C);
   
   constant AXIL0_CROSSBAR_MASTERS_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL0_MASTERS_C-1 downto 0) := (
     0 => (baseAddr     => x"00800000",
           addrBits     => 21,
           connectivity => x"FFFF"),
     1 => (baseAddr     => x"00A00000",
           addrBits     => 21,
           connectivity => x"FFFF"),
     2 => (baseAddr     => x"00E00000",
           addrBits     => 21,
           connectivity => x"FFFF") );
   constant AXIL1_CROSSBAR_MASTERS_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL1_MASTERS_C-1 downto 0) := (
     0 => (baseAddr     => x"00800000",
           addrBits     => 21,
           connectivity => x"FFFF"),
     1 => (baseAddr     => x"00A00000",
           addrBits     => 21,
           connectivity => x"FFFF"),
     2 => (baseAddr     => x"00E00000",
           addrBits     => 21,
           connectivity => x"FFFF") );

   signal i2cAxilReadMasters  : AxiLiteReadMasterArray (1 downto 0);
   signal i2cAxilReadSlaves   : AxiLiteReadSlaveArray  (1 downto 0);
   signal i2cAxilWriteMasters : AxiLiteWriteMasterArray(1 downto 0);
   signal i2cAxilWriteSlaves  : AxiLiteWriteSlaveArray (1 downto 0);

   signal i2cReadMaster  : AxiLiteReadMasterType;
   signal i2cReadSlave   : AxiLiteReadSlaveType;
   signal i2cWriteMaster : AxiLiteWriteMasterType;
   signal i2cWriteSlave  : AxiLiteWriteSlaveType;

   signal pgpAxilReadMasters  : AxiLiteReadMasterArray (1 downto 0);
   signal pgpAxilReadSlaves   : AxiLiteReadSlaveArray  (1 downto 0);
   signal pgpAxilWriteMasters : AxiLiteWriteMasterArray(1 downto 0);
   signal pgpAxilWriteSlaves  : AxiLiteWriteSlaveArray (1 downto 0);

   signal mtpIbMasters        : AxiStreamMasterArray   (1 downto 0);
   signal mtpIbSlaves         : AxiStreamSlaveArray    (1 downto 0);
   signal mtpAxisCtrl         : AxiStreamCtrlArray     (1 downto 0);
   signal mtpAxilReadMasters  : AxiLiteReadMasterArray (1 downto 0);
   signal mtpAxilReadSlaves   : AxiLiteReadSlaveArray  (1 downto 0);
   signal mtpAxilWriteMasters : AxiLiteWriteMasterArray(1 downto 0);
   signal mtpAxilWriteSlaves  : AxiLiteWriteSlaveArray (1 downto 0);

   signal migConfig : MigConfigArray(7 downto 0) := (others=>MIG_CONFIG_INIT_C);
   signal migStatus : MigStatusArray(7 downto 0);
   

   signal mmcmClkOut : Slv3Array(1 downto 0);
   signal mmcmRstOut : Slv3Array(1 downto 0);

   signal userRefClock : sl;
   
   constant DEVICE_MAP_C : I2cAxiLiteDevArray(3 downto 0) := (
    -----------------------
    -- PC821 I2C DEVICES --
    -----------------------
    -- PCA9548A I2C Mux
    0 => MakeI2cAxiLiteDevType( "1110100", 8, 0, '0' ),
    -- QSFP1, QSFP0, EEPROM;  I2C Mux = 1, 4, 5
    1 => MakeI2cAxiLiteDevType( "1010000", 8, 8, '0' ),
    -- SI570                  I2C Mux = 2
    2 => MakeI2cAxiLiteDevType( "1011101", 8, 8, '0' ),
    -- Fan                    I2C Mux = 3
    3 => MakeI2cAxiLiteDevType( "1001100", 8, 8, '0' ) );

   signal rdDescReq : AxiReadDmaDescReqArray(7 downto 0);
   signal rdDescRet : AxiReadDmaDescRetArray(7 downto 0);
   signal rdDescReqAck : slv(7 downto 0);
   signal rdDescRetAck : slv(7 downto 0);

   signal qsfpModPrsL  : slv(1 downto 0);

   constant AXIO_STREAM_CONFIG_C : AxiStreamConfigType := (
     TSTRB_EN_C    => false,
     TDATA_BYTES_C => 32,
     TDEST_BITS_C  => 0,
     TID_BITS_C    => 0,
     TKEEP_MODE_C  => TKEEP_NORMAL_C,
     TUSER_BITS_C  => 2,
     TUSER_MODE_C  => TUSER_NORMAL_C);

   constant AXI_ILV_CONFIG_C : AxiConfigType := axiConfig( 32, 32, 4, 8 );
   
   signal pgpRefClkP : Slv2Array(1 downto 0);
   signal pgpRefClkN : Slv2Array(1 downto 0);
   signal pgpRxP     : Slv4Array(1 downto 0);
   signal pgpRxN     : Slv4Array(1 downto 0);
   signal pgpTxP     : Slv4Array(1 downto 0);
   signal pgpTxN     : Slv4Array(1 downto 0);
   signal pgpRefClkMon : slv    (1 downto 0);   
   signal seqError   : slv      (1 downto 0);

begin

  i2c_rst_l      <= '1';
  qsfpModPrsL(0) <= qsfp0ModPrsL;
  qsfpModPrsL(1) <= qsfp1ModPrsL;
  qsfp0ModSelL   <= '0';  -- enable I2C
  qsfp1ModSelL   <= '0';  -- enable I2C

  pgpRefClkP(0) <= qsfp0RefClkP;
  pgpRefClkN(0) <= qsfp0RefClkN;
  pgpRxP    (0) <= qsfp0RxP;
  pgpRxN    (0) <= qsfp0RxN;
  qsfp0TxP      <=  pgpTxP    (0);
  qsfp0TxN      <=  pgpTxN    (0);

  pgpRefClkP(1) <= qsfp1RefClkP;
  pgpRefClkN(1) <= qsfp1RefClkN;
  pgpRxP    (1) <= qsfp1RxP;
  pgpRxN    (1) <= qsfp1RxN;
  qsfp1TxP      <=  pgpTxP    (1);
  qsfp1TxN      <=  pgpTxN    (1);

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
      I     => qsfp1RefClkP(1),
      IB    => qsfp1RefClkN(1),
      CEB   => '0',
      ODIV2 => userRefClock,
      O     => open );
  
  U_AxilXbar0 : entity surf.AxiLiteCrossbar
    generic map ( NUM_SLAVE_SLOTS_G  => 1,
                  NUM_MASTER_SLOTS_G => AXIL0_CROSSBAR_MASTERS_CONFIG_C'length,
                  MASTERS_CONFIG_G   => AXIL0_CROSSBAR_MASTERS_CONFIG_C )
    port map    ( axiClk              => axilClks        (0),
                  axiClkRst           => axilRsts        (0),
                  sAxiWriteMasters(0) => axilWriteMasters(0),
                  sAxiWriteSlaves (0) => axilWriteSlaves (0),
                  sAxiReadMasters (0) => axilReadMasters (0),
                  sAxiReadSlaves  (0) => axilReadSlaves  (0),
                  mAxiWriteMasters    => mAxil0WriteMasters,
                  mAxiWriteSlaves     => mAxil0WriteSlaves ,
                  mAxiReadMasters     => mAxil0ReadMasters ,
                  mAxiReadSlaves      => mAxil0ReadSlaves  );

  U_AxilXbar1 : entity surf.AxiLiteCrossbar
    generic map ( NUM_SLAVE_SLOTS_G  => 1,
                  NUM_MASTER_SLOTS_G => AXIL1_CROSSBAR_MASTERS_CONFIG_C'length,
                  MASTERS_CONFIG_G   => AXIL1_CROSSBAR_MASTERS_CONFIG_C )
    port map    ( axiClk              => axilClks        (1),
                  axiClkRst           => axilRsts        (1),
                  sAxiWriteMasters(0) => axilWriteMasters(1),
                  sAxiWriteSlaves (0) => axilWriteSlaves (1),
                  sAxiReadMasters (0) => axilReadMasters (1),
                  sAxiReadSlaves  (0) => axilReadSlaves  (1),
                  mAxiWriteMasters    => mAxil1WriteMasters,
                  mAxiWriteSlaves     => mAxil1WriteSlaves ,
                  mAxiReadMasters     => mAxil1ReadMasters ,
                  mAxiReadSlaves      => mAxil1ReadSlaves  );

  pgpAxilReadMasters (0) <= mAxil0ReadMasters (HWSEM_INDEX_C);
  pgpAxilWriteMasters(0) <= mAxil0WriteMasters(HWSEM_INDEX_C);
  mAxil0ReadSlaves (HWSEM_INDEX_C) <= pgpAxilReadSlaves (0);
  mAxil0WriteSlaves(HWSEM_INDEX_C) <= pgpAxilWriteSlaves(0);

  pgpAxilReadMasters (1) <= mAxil1ReadMasters (HWSEM_INDEX_C);
  pgpAxilWriteMasters(1) <= mAxil1WriteMasters(HWSEM_INDEX_C);
  mAxil1ReadSlaves (HWSEM_INDEX_C) <= pgpAxilReadSlaves (1);
  mAxil1WriteSlaves(HWSEM_INDEX_C) <= pgpAxilWriteSlaves(1);

  mtpAxilReadMasters (0) <= mAxil0ReadMasters (MIGTPCI_INDEX_C);
  mtpAxilWriteMasters(0) <= mAxil0WriteMasters(MIGTPCI_INDEX_C);
  mAxil0ReadSlaves (MIGTPCI_INDEX_C) <= mtpAxilReadSlaves (0);
  mAxil0WriteSlaves(MIGTPCI_INDEX_C) <= mtpAxilWriteSlaves(0);

  mtpAxilReadMasters (1) <= mAxil1ReadMasters (MIGTPCI_INDEX_C);
  mtpAxilWriteMasters(1) <= mAxil1WriteMasters(MIGTPCI_INDEX_C);
  mAxil1ReadSlaves (MIGTPCI_INDEX_C) <= mtpAxilReadSlaves (1);
  mAxil1WriteSlaves(MIGTPCI_INDEX_C) <= mtpAxilWriteSlaves(1);

  U_AXIL_ASYNC : entity surf.AxiLiteAsync
   port map (
      -- Slave Port
      sAxiClk         => axilClks(1),
      sAxiClkRst      => axilRsts(1),
      sAxiReadMaster  => mAxil1ReadMasters (I2C_INDEX_C),
      sAxiReadSlave   => mAxil1ReadSlaves  (I2C_INDEX_C),
      sAxiWriteMaster => mAxil1WriteMasters(I2C_INDEX_C),
      sAxiWriteSlave  => mAxil1WriteSlaves (I2C_INDEX_C),
      -- Master Port
      mAxiClk         => axilClks(0),
      mAxiClkRst      => axilRsts(0),
      mAxiReadMaster  => i2cAxilReadMasters (1),
      mAxiReadSlave   => i2cAxilReadSlaves  (1),
      mAxiWriteMaster => i2cAxilWriteMasters(1),
      mAxiWriteSlave  => i2cAxilWriteSlaves (1) );

  i2cAxilReadMasters (0) <= mAxil0ReadMasters (I2C_INDEX_C);
  i2cAxilWriteMasters(0) <= mAxil0WriteMasters(I2C_INDEX_C);
  mAxil0ReadSlaves  (I2C_INDEX_C) <= i2cAxilReadSlaves (0);
  mAxil0WriteSlaves (I2C_INDEX_C) <= i2cAxilWriteSlaves(0);

  U_AXIL_I2C : entity surf.AxiLiteCrossbar
    generic map ( NUM_SLAVE_SLOTS_G  => 2,
                  NUM_MASTER_SLOTS_G => 1,
                  MASTERS_CONFIG_G   => AXIL0_CROSSBAR_MASTERS_CONFIG_C(I2C_INDEX_C to I2C_INDEX_C) )
    port map    ( axiClk              => axilClks        (0),
                  axiClkRst           => axilRsts        (0),
                  sAxiWriteMasters    => i2cAxilWriteMasters,
                  sAxiWriteSlaves     => i2cAxilWriteSlaves ,
                  sAxiReadMasters     => i2cAxilReadMasters ,
                  sAxiReadSlaves      => i2cAxilReadSlaves  ,
                  mAxiWriteMasters(0) => i2cWriteMaster,
                  mAxiWriteSlaves (0) => i2cWriteSlave ,
                  mAxiReadMasters (0) => i2cReadMaster ,
                  mAxiReadSlaves  (0) => i2cReadSlave  );
    
  U_I2C : entity surf.AxiI2cRegMaster
    generic map ( DEVICE_MAP_G   => DEVICE_MAP_C,
                  AXI_CLK_FREQ_G => 125.0E+6 )
    port map ( scl            => scl,
               sda            => sda,
               axiReadMaster  => i2cReadMaster ,
               axiReadSlave   => i2cReadSlave  ,
               axiWriteMaster => i2cWriteMaster,
               axiWriteSlave  => i2cWriteSlave ,
               axiClk         => axilClks(0),
               axiRst         => axilRsts(0) );

  GEN_SEMI : for i in 0 to 1 generate
    clk200  (i) <= mmcmClkOut(i)(0);
    axilClks(i) <= mmcmClkOut(i)(1);
    axilRsts(i) <= mmcmRstOut(i)(1);

    irst200(i) <= sysRsts(i);

    -- Forcing BUFG for reset that's used everywhere      
    U_URST : entity surf.RstSync
      port map ( clk      => clk200 (i),
                 asyncRst => irst200(i),
                 syncRst  => urst200(i) );
    
    U_BUFG : BUFG
      port map (
        I => urst200(i),
        O => rst200(i));
    
    -- Forcing BUFG for reset that's used everywhere      
    irst200U(i) <= sysRsts(i) or userReset(i);

    U_URSTU : entity surf.RstSync
      port map ( clk      => clk200 (i),
                 asyncRst => irst200U(i),
                 syncRst  => urst200U(i) );
    
    U_BUFGUU : BUFG
      port map (
        I => urst200U(i),
        O => rst200U(i));

    U_MMCM : entity surf.ClockManagerUltraScale
      generic map ( INPUT_BUFG_G       => false,
                    NUM_CLOCKS_G       => 3,
                    CLKIN_PERIOD_G     => 6.4,
                    DIVCLK_DIVIDE_G    => 1,
                    CLKFBOUT_MULT_F_G  => 8.0,  -- 1.25 GHz
                    CLKOUT0_DIVIDE_F_G => 6.25, -- 200 MHz
                    CLKOUT1_DIVIDE_G   => 10,   -- 125 MHz
                    CLKOUT2_DIVIDE_G   =>  8 )  -- 156.25 MHz
      port map ( clkIn     => userClk156,
                 rstIn     => '0',
                 clkOut    => mmcmClkOut(i),
                 rstOut    => mmcmRstOut(i) );
    
    U_Hw : entity work.HardwareSemi
      generic map (
        REFCLK_SELECT_G => "186M",
        AXIL_CLK_FREQ_G => 125.0E6,
        AXI_BASE_ADDR_G => AXIL0_CROSSBAR_MASTERS_CONFIG_C(HWSEM_INDEX_C).baseAddr )
      port map (
        ------------------------      
        --  Top Level Interfaces
        ------------------------         
        -- AXI-Lite Interface (axilClk domain)
        axilClk         => axilClks        (i),
        axilRst         => axilRsts        (i),
        axilReadMaster  => pgpAxilReadMasters (i),
        axilReadSlave   => pgpAxilReadSlaves  (i),
        axilWriteMaster => pgpAxilWriteMasters(i),
        axilWriteSlave  => pgpAxilWriteSlaves (i),
        -- DMA Interface (dmaClk domain)
        dmaClks         => hwClks        (4*i+3 downto 4*i),
        dmaRsts         => hwRsts        (4*i+3 downto 4*i),
        dmaObMasters    => hwObMasters   (4*i+3 downto 4*i),
        dmaObSlaves     => hwObSlaves    (4*i+3 downto 4*i),
        dmaIbMasters    => hwIbMasters   (4*i+3 downto 4*i),
        dmaIbSlaves     => hwIbSlaves    (4*i+3 downto 4*i),
        dmaIbAlmostFull => hwIbAlmostFull(4*i+3 downto 4*i),
        dmaIbFull       => hwIbFull      (4*i+3 downto 4*i),
        --
        fifoThres       => hwIbFifoThres (i),
        fifoDepth       => hwIbFifoDepth (4*i+3 downto 4*i),
        -- QSFP Ports
        qsfp0RefClkP    => pgpRefClkP(i),
        qsfp0RefClkN    => pgpRefClkN(i),
        qsfp0RxP        => pgpRxP    (i),
        qsfp0RxN        => pgpRxN    (i),
        qsfp0TxP        => pgpTxP    (i),
        qsfp0TxN        => pgpTxN    (i),
        qsfp0RefClkMon  => pgpRefClkMon(i) );

    U_HwDma : entity work.AppIlvToMigDma
      generic map ( LANES_G       => 4,
                    AXIS_CONFIG_G => PGP3_AXIS_CONFIG_C )
      port map ( sAxisClk        => hwClks         (4*i+3 downto 4*i),
                 sAxisRst        => hwRsts         (4*i+3 downto 4*i),
                 sAxisMaster     => hwIbMasters    (4*i+3 downto 4*i),
                 sAxisSlave      => hwIbSlaves     (4*i+3 downto 4*i),
                 sAlmostFull     => hwIbAlmostFull (4*i+3 downto 4*i),
                 sFull           => hwIbFull       (4*i+3 downto 4*i),
                 sOverflow       => hwIbOflow      (4*i+3 downto 4*i),
                 mAxiClk         => clk200         (i),
                 mAxiRst         => rst200U        (i),
                 mAxiWriteMaster => memWriteMasters(i),
                 mAxiWriteSlave  => memWriteSlaves (i),
                 rdDescReq       => rdDescReq     (i),
                 rdDescReqAck    => rdDescReqAck  (i),
                 rdDescRet       => rdDescRet     (i),
                 rdDescRetAck    => rdDescRetAck  (i),
                 memReady        => memReady       (i),
                 config          => migConfig      (i),
                 status          => migStatus      (i) );

     U_Mig2Pcie : entity work.MigIlvToPcieDma
       generic map ( MONCLKS_G        => 4,
                     AXI_CONFIG_G     => AXI_ILV_CONFIG_C,
                     AXIS_CONFIG_G    => AXIO_STREAM_CONFIG_C )
--                     DEBUG_G          => (i<1) )
       port map ( axiClk          => clk200(i),
                  axiRst          => rst200(i),
                  seqError        => seqError      (i),
                  usrRst          => userReset(i),
                  axiReadMaster   => memReadMasters(i),
                  axiReadSlave    => memReadSlaves (i),
                  rdDescReq       => rdDescReq     (i),
                  rdDescAck       => rdDescReqAck  (i),
                  rdDescRet       => rdDescRet     (i),
                  rdDescRetAck    => rdDescRetAck  (i),
                  axisMasters     => mtpIbMasters  (i),
                  axisSlaves      => mtpIbSlaves   (i),
                  axisOflow       => mtpAxisCtrl   (i).overflow,
                  hwIbOflow       => hwIbOflow     (4*i+3 downto 4*i),
                  hwIbFifoThres   => hwIbFifoThres (i),
                  hwIbFifoDepth   => hwIbFifoDepth (4*i+3 downto 4*i),
                  axilClk         => axilClks        (i),
                  axilRst         => axilRsts        (i),
                  axilWriteMaster => mtpAxilWriteMasters(i),
                  axilWriteSlave  => mtpAxilWriteSlaves (i),
                  axilReadMaster  => mtpAxilReadMasters (i),
                  axilReadSlave   => mtpAxilReadSlaves  (i),
                  monClk(0)       => axilClks       (1-i),
                  monClk(1)       => sysClks        (1-i),
                  monClk(2)       => clk200         (i),
                  monClk(3)       => pgpRefClkMon   (i),
                  migConfig       => migConfig      (i),
                  migStatus       => migStatus      (i) );

      U_IbFifo : entity surf.AxiStreamFifoV2
         generic map (
            -- General Configurations
            INT_PIPE_STAGES_G   => 1,
            PIPE_STAGES_G       => 1,
            -- FIFO configurations
            FIFO_ADDR_WIDTH_G   => 4,
            -- AXI Stream Port Configurations
            SLAVE_AXI_CONFIG_G  => AXIO_STREAM_CONFIG_C,
            MASTER_AXI_CONFIG_G => AXIO_STREAM_CONFIG_C)
         port map (
            -- Slave Port
            sAxisClk    => clk200      (i),
            sAxisRst    => rst200      (i),
            sAxisMaster => mtpIbMasters(i),
            sAxisSlave  => mtpIbSlaves (i),
            sAxisCtrl   => mtpAxisCtrl (i),
            -- Master Port
            mAxisClk    => sysClks     (i),
            mAxisRst    => sysRsts     (i),
            mAxisMaster => dmaIbMasters(i),
            mAxisSlave  => dmaIbSlaves (i));
  end generate;

  U_Core : entity axi_pcie_core.XilinxKcu1500Core
    generic map (
      TPD_G             => TPD_G,
      DRIVER_TYPE_ID_G  => toSlv(0,32),
      DMA_SIZE_G        => 1,
      BUILD_INFO_G      => BUILD_INFO_G,
      DMA_AXIS_CONFIG_G => AXIO_STREAM_CONFIG_C )
    port map (
      ------------------------      
      --  Top Level Interfaces
      ------------------------
      userClk156      => open,  -- one programmable clock
--      userSwDip       => userSwDip,
--      userLed         => userLed,
      -- System Clock and Reset
      dmaClk          => sysClks(0),
      dmaRst          => sysRsts(0),
      -- DMA Interfaces
      dmaObMasters    => dmaObMasters   (0 downto 0),
      dmaObSlaves     => dmaObSlaves    (0 downto 0),
      dmaIbMasters    => dmaIbMasters   (0 downto 0),
      dmaIbSlaves     => dmaIbSlaves    (0 downto 0),
      --
      -- AXI-Lite Interface
      appClk          => axilClks        (0),
      appRst          => axilRsts        (0),
      appReadMaster   => axilReadMasters (0),
      appReadSlave    => axilReadSlaves  (0),
      appWriteMaster  => axilWriteMasters(0),
      appWriteSlave   => axilWriteSlaves (0),
      --------------
      --  Core Ports
      --------------
      emcClk          => emcClk,
      userClkP        => userClkP,
      userClkN        => userClkN,
--      swDip           => swDip,
--      led             => led,
      -- QSFP[0] Ports
      qsfp0RstL       => qsfp0RstL   ,
      qsfp0LpMode     => qsfp0LpMode ,
      qsfp0ModSelL    => open,
      qsfp0ModPrsL    => qsfp0ModPrsL,
      -- QSFP[1] Ports
      qsfp1RstL       => qsfp1RstL   ,
      qsfp1LpMode     => qsfp1LpMode ,
      qsfp1ModSelL    => open,
      qsfp1ModPrsL    => qsfp1ModPrsL,
      -- Boot Memory Ports 
      flashCsL        => flashCsL  ,
      flashMosi       => flashMosi ,
      flashMiso       => flashMiso ,
      flashHoldL      => flashHoldL,
      flashWp         => flashWp,
       -- PCIe Ports 
      pciRstL         => pciRstL,
      pciRefClkP      => pciRefClkP,
      pciRefClkN      => pciRefClkN,
      pciRxP          => pciRxP,
      pciRxN          => pciRxN,
      pciTxP          => pciTxP,
      pciTxN          => pciTxN );

  U_Extended : entity axi_pcie_core.XilinxKcu1500PcieExtendedCore
    generic map ( TPD_G             => TPD_G,
                  BUILD_INFO_G      => BUILD_INFO_G,
                  DRIVER_TYPE_ID_G  => toSlv(1,32),
                  DMA_SIZE_G        => 1,
                  DMA_AXIS_CONFIG_G => AXIO_STREAM_CONFIG_C )
    port map (
      ------------------------      
      --  Top Level Interfaces
      ------------------------        
      -- DMA Interfaces
      dmaClk         => sysClks(1),
      dmaRst         => sysRsts(1),
      --
      dmaObMasters    => dmaObMasters   (1 downto 1),
      dmaObSlaves     => dmaObSlaves    (1 downto 1),
      dmaIbMasters    => dmaIbMasters   (1 downto 1),
      dmaIbSlaves     => dmaIbSlaves    (1 downto 1),
      -- AXI-Lite Interface
      appClk         => axilClks        (1),
      appRst         => axilRsts        (1),
      appReadMaster  => axilReadMasters (1),
      appReadSlave   => axilReadSlaves  (1),
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

  U_MIG0 : entity work.Mig0D
    generic map ( AXI_CONFIG_G => AXI_ILV_CONFIG_C )
    port map ( axiReady        => memReady(0),
               --
               axiClk          => clk200         (0),
               axiRst          => rst200         (0),
               axiTrigger      => seqError       (0),
               axiWriteMaster  => memWriteMasters(0),
               axiWriteSlave   => memWriteSlaves (0),
               axiReadMaster   => memReadMasters (0),
               axiReadSlave    => memReadSlaves  (0),
               --
               ddrClkP         => ddrClkP (0),
               ddrClkN         => ddrClkN (0),
               ddrOut          => ddrOut  (0),
               ddrInOut        => ddrInOut(0) );

  U_MIG1 : entity work.Mig1D
    generic map ( AXI_CONFIG_G => AXI_ILV_CONFIG_C )
    port map ( axiReady        => memReady(1),
               --
               axiClk          => clk200         (1),
               axiRst          => rst200         (1),
               axiWriteMaster  => memWriteMasters(1),
               axiWriteSlave   => memWriteSlaves (1),
               axiReadMaster   => memReadMasters (1),
               axiReadSlave    => memReadSlaves  (1),
               --
               ddrClkP         => ddrClkP (1),
               ddrClkN         => ddrClkN (1),
               ddrOut          => ddrOut  (1),
               ddrInOut        => ddrInOut(1) );
  
  -- Unused user signals
  userLed <= (others => '0');

end top_level;
                    
