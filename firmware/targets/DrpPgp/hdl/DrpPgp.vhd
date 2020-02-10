-------------------------------------------------------------------------------
-- File       : DrpPgp.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-24
-- Last update: 2020-02-09
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
use surf.Pgp3Pkg.all;
use surf.I2cPkg.all;

library axi_pcie_core;
use axi_pcie_core.AxiPciePkg.all;
use axi_pcie_core.MigPkg.all;

use work.AppMigPkg.all;

library unisim;
use unisim.vcomponents.all;

entity DrpPgp is
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
      ddrClkP      : in    slv          (0 downto 0);
      ddrClkN      : in    slv          (0 downto 0);
      ddrOut       : out   DdrOutArray  (0 downto 0);
      ddrInOut     : inout DdrInOutArray(0 downto 0);
      -- PCIe Ports
      pciRstL      : in    sl;
      pciRefClkP   : in    sl;
      pciRefClkN   : in    sl;
      pciRxP       : in    slv(7 downto 0);
      pciRxN       : in    slv(7 downto 0);
      pciTxP       : out   slv(7 downto 0);
      pciTxN       : out   slv(7 downto 0) );
end DrpPgp;

architecture top_level of DrpPgp is

   signal sysClks    : slv(0 downto 0);
   signal sysRsts    : slv(0 downto 0);
   signal clk200     : slv(0 downto 0);
   signal rst200     : slv(0 downto 0);
   signal rst200u    : slv(0 downto 0);
   signal irst200    : slv(0 downto 0);
   signal urst200    : slv(0 downto 0);
   signal userClk156 : sl;
   signal userReset  : slv(1 downto 0);
   signal userSwDip  : slv(3 downto 0);
   signal userLed    : slv(7 downto 0);

   signal axilClks         : slv                    (0 downto 0);
   signal axilRsts         : slv                    (0 downto 0);
   signal axilReadMasters  : AxiLiteReadMasterArray (0 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray  (0 downto 0);
   signal axilWriteMasters : AxiLiteWriteMasterArray(0 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray (0 downto 0);

   signal dmaObMasters    : AxiStreamMasterArray (4 downto 0);
   signal dmaObSlaves     : AxiStreamSlaveArray  (4 downto 0);
   signal dmaIbMasters    : AxiStreamMasterArray (4 downto 0);
   signal dmaIbSlaves     : AxiStreamSlaveArray  (4 downto 0);

   signal hwClks          : slv                 (3 downto 0);
   signal hwRsts          : slv                 (3 downto 0);
   signal hwObMasters     : AxiStreamMasterArray(3 downto 0);
   signal hwObSlaves      : AxiStreamSlaveArray (3 downto 0);
   signal hwIbMasters     : AxiStreamMasterArray(3 downto 0);
   signal hwIbSlaves      : AxiStreamSlaveArray (3 downto 0);
   signal hwIbAlmostFull  : slv                 (3 downto 0);
   signal hwIbFull        : slv                 (3 downto 0);

   signal memReady        : slv                (0 downto 0);
   signal memWriteMasters : AxiWriteMasterArray(3 downto 0);
   signal memWriteSlaves  : AxiWriteSlaveArray (3 downto 0);
   signal memReadMasters  : AxiReadMasterArray (3 downto 0);
   signal memReadSlaves   : AxiReadSlaveArray  (3 downto 0);

   constant MIGTPCI_INDEX_C   : integer := 0;
   constant HWSEM_INDEX_C     : integer := 1;
   constant I2C_INDEX_C       : integer := 2;

   constant NUM_AXIL0_MASTERS_C : integer := 3;
   signal mAxil0ReadMasters  : AxiLiteReadMasterArray (NUM_AXIL0_MASTERS_C-1 downto 0) := (others=>AXI_LITE_READ_MASTER_INIT_C);
   signal mAxil0ReadSlaves   : AxiLiteReadSlaveArray  (NUM_AXIL0_MASTERS_C-1 downto 0) := (others=>AXI_LITE_READ_SLAVE_EMPTY_OK_C);
   signal mAxil0WriteMasters : AxiLiteWriteMasterArray(NUM_AXIL0_MASTERS_C-1 downto 0) := (others=>AXI_LITE_WRITE_MASTER_INIT_C);
   signal mAxil0WriteSlaves  : AxiLiteWriteSlaveArray (NUM_AXIL0_MASTERS_C-1 downto 0) := (others=>AXI_LITE_WRITE_SLAVE_EMPTY_OK_C);

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

   signal pgpAxilReadMasters  : AxiLiteReadMasterArray (0 downto 0);
   signal pgpAxilReadSlaves   : AxiLiteReadSlaveArray  (0 downto 0);
   signal pgpAxilWriteMasters : AxiLiteWriteMasterArray(0 downto 0);
   signal pgpAxilWriteSlaves  : AxiLiteWriteSlaveArray (0 downto 0);

   signal mtpIbMasters        : AxiStreamMasterArray   (4 downto 0);
   signal mtpIbSlaves         : AxiStreamSlaveArray    (4 downto 0);
   signal mtpAxilReadMasters  : AxiLiteReadMasterArray (0 downto 0);
   signal mtpAxilReadSlaves   : AxiLiteReadSlaveArray  (0 downto 0);
   signal mtpAxilWriteMasters : AxiLiteWriteMasterArray(0 downto 0);
   signal mtpAxilWriteSlaves  : AxiLiteWriteSlaveArray (0 downto 0);

   signal migConfig : MigConfigArray(3 downto 0) := (others=>MIG_CONFIG_INIT_C);
   signal migStatus : MigStatusArray(3 downto 0);
   

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

   signal rdDescReq : AxiReadDmaDescReqArray(3 downto 0);
   signal rdDescRet : AxiReadDmaDescRetArray(3 downto 0);
   signal rdDescReqAck : slv(3 downto 0);
   signal rdDescRetAck : slv(3 downto 0);

   signal qsfpModPrsL  : slv(0 downto 0);

   constant AXIO_STREAM_CONFIG_C : AxiStreamConfigType := (
     TSTRB_EN_C    => false,
     TDATA_BYTES_C => 16,
     TDEST_BITS_C  => 0,
     TID_BITS_C    => 0,
     TKEEP_MODE_C  => TKEEP_NORMAL_C,
     TUSER_BITS_C  => 2,
     TUSER_MODE_C  => TUSER_NORMAL_C);

   signal monClkRate : Slv29Array(0 downto 0);
   signal monClkLock : slv       (0 downto 0);
   signal monClkFast : slv       (0 downto 0);
   signal monClkSlow : slv       (0 downto 0);

   signal pgpRefClkP : Slv2Array(0 downto 0);
   signal pgpRefClkN : Slv2Array(0 downto 0);
   signal pgpRxP     : Slv4Array(0 downto 0);
   signal pgpRxN     : Slv4Array(0 downto 0);
   signal pgpTxP     : Slv4Array(0 downto 0);
   signal pgpTxN     : Slv4Array(0 downto 0);
   signal pgpRefClkMon : slv    (0 downto 0);   

begin

  i2c_rst_l      <= '1';
  qsfpModPrsL(0) <= qsfp0ModPrsL;
  qsfp0ModSelL   <= '0';  -- enable I2C
  qsfp1ModSelL   <= '0';  -- enable I2C

  pgpRefClkP(0) <= qsfp0RefClkP;
  pgpRefClkN(0) <= qsfp0RefClkN;
  pgpRxP    (0) <= qsfp0RxP;
  pgpRxN    (0) <= qsfp0RxN;
  qsfp0TxP      <=  pgpTxP    (0);
  qsfp0TxN      <=  pgpTxN    (0);


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

  pgpAxilReadMasters (0) <= mAxil0ReadMasters (HWSEM_INDEX_C);
  pgpAxilWriteMasters(0) <= mAxil0WriteMasters(HWSEM_INDEX_C);
  mAxil0ReadSlaves (HWSEM_INDEX_C) <= pgpAxilReadSlaves (0);
  mAxil0WriteSlaves(HWSEM_INDEX_C) <= pgpAxilWriteSlaves(0);

  mtpAxilReadMasters (0) <= mAxil0ReadMasters (MIGTPCI_INDEX_C);
  mtpAxilWriteMasters(0) <= mAxil0WriteMasters(MIGTPCI_INDEX_C);
  mAxil0ReadSlaves (MIGTPCI_INDEX_C) <= mtpAxilReadSlaves (0);
  mAxil0WriteSlaves(MIGTPCI_INDEX_C) <= mtpAxilWriteSlaves(0);

  U_I2C : entity surf.AxiI2cRegMaster
    generic map ( DEVICE_MAP_G   => DEVICE_MAP_C,
                  AXI_CLK_FREQ_G => 125.0E+6 )
    port map ( scl            => scl,
               sda            => sda,
               axiReadMaster  => mAxil0ReadMasters (I2C_INDEX_C),
               axiReadSlave   => mAxil0ReadSlaves  (I2C_INDEX_C),
               axiWriteMaster => mAxil0WriteMasters(I2C_INDEX_C),
               axiWriteSlave  => mAxil0WriteSlaves (I2C_INDEX_C),
               axiClk         => axilClks(0),
               axiRst         => axilRsts(0) );

  GEN_SEMI : for i in 0 to 0 generate
    clk200  (i) <= mmcmClkOut(i)(0);
    axilClks(i) <= mmcmClkOut(i)(1);
    axilRsts(i) <= mmcmRstOut(i)(1);

    -- Forcing BUFG for reset that's used everywhere      
    U_BUFG : BUFG
      port map (
        I => mmcmRstOut(i)(0),
        O => rst200(i));
    
    rst200u(i) <= rst200(i) or userReset(i);

    U_RSTU : entity surf.RstSync
      port map (
        clk      => clk200 (i),
        asyncRst => rst200u(i),
        syncRst  => irst200(i) );
    
    -- Forcing BUFG for reset that's used everywhere      
    U_BUFGU : BUFG
      port map (
        I => irst200(i),
        O => urst200(i));

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
        -- QSFP Ports
        qsfp0RefClkP    => pgpRefClkP(i),
        qsfp0RefClkN    => pgpRefClkN(i),
        qsfp0RxP        => pgpRxP    (i),
        qsfp0RxN        => pgpRxN    (i),
        qsfp0TxP        => pgpTxP    (i),
        qsfp0TxN        => pgpTxN    (i),
        qsfp0RefClkMon  => pgpRefClkMon(i) );

     GEN_HWDMA : for j in 4*i+0 to 4*i+3 generate
       U_HwDma : entity work.AppToMigDma
         generic map ( AXI_BASE_ADDR_G     => (toSlv(j,2) & toSlv(0,30)) )
         port map ( sAxisClk        => hwClks         (j),
                    sAxisRst        => hwRsts         (j),
                    sAxisMaster     => hwIbMasters    (j),
                    sAxisSlave      => hwIbSlaves     (j),
                    sAlmostFull     => hwIbAlmostFull (j),
                    sFull           => hwIbFull       (j),
                    mAxiClk         => clk200         (i),
                    mAxiRst         => urst200        (i),
                    mAxiWriteMaster => memWriteMasters(j),
                    mAxiWriteSlave  => memWriteSlaves (j),
                    rdDescReq       => rdDescReq      (j), -- exchange
                    rdDescReqAck    => rdDescReqAck   (j),
                    rdDescRet       => rdDescRet      (j),
                    rdDescRetAck    => rdDescRetAck   (j),
                    memReady        => memReady       (i),
                    config          => migConfig      (j),
                    status          => migStatus      (j) );
       U_ObFifo : entity surf.AxiStreamFifoV2
         generic map ( FIFO_ADDR_WIDTH_G   => 4,
                       SLAVE_AXI_CONFIG_G  => AXIO_STREAM_CONFIG_C,
                       MASTER_AXI_CONFIG_G => PGP3_AXIS_CONFIG_C )
         port map ( sAxisClk    => sysClks     (i),
                    sAxisRst    => sysRsts     (i),
                    sAxisMaster => dmaObMasters(j+i),
                    sAxisSlave  => dmaObSlaves (j+i),
                    sAxisCtrl   => open,
                    mAxisClk    => hwClks      (j),
                    mAxisRst    => hwRsts      (j),
                    mAxisMaster => hwObMasters (j),
                    mAxisSlave  => hwObSlaves  (j) );
     end generate;

     U_Mig2Pcie : entity work.MigToPcieDma
       generic map ( LANES_G          => 4,
                     MONCLKS_G        => 4,
                     AXIS_CONFIG_G    => AXIO_STREAM_CONFIG_C,
                     DEBUG_G          => true )
--                     DEBUG_G          => (i<1) )
       port map ( axiClk          => clk200(i),
                  axiRst          => rst200(i),
                  usrRst          => userReset(i),
                  axiReadMasters  => memReadMasters(4*i+3 downto 4*i),
                  axiReadSlaves   => memReadSlaves (4*i+3 downto 4*i),
                  rdDescReq       => rdDescReq     (4*i+3 downto 4*i),
                  rdDescAck       => rdDescReqAck  (4*i+3 downto 4*i),
                  rdDescRet       => rdDescRet     (4*i+3 downto 4*i),
                  rdDescRetAck    => rdDescRetAck  (4*i+3 downto 4*i),
                  axisMasters     => mtpIbMasters  (5*i+4 downto 5*i),
                  axisSlaves      => mtpIbSlaves   (5*i+4 downto 5*i),
                  axilClk         => axilClks        (i),
                  axilRst         => axilRsts        (i),
                  axilWriteMaster => mtpAxilWriteMasters(i),
                  axilWriteSlave  => mtpAxilWriteSlaves (i),
                  axilReadMaster  => mtpAxilReadMasters (i),
                  axilReadSlave   => mtpAxilReadSlaves  (i),
                  monClk(0)       => axilClks       (i),
                  monClk(1)       => sysClks        (i),
                  monClk(2)       => clk200         (i),
                  monClk(3)       => pgpRefClkMon   (i),
                  migConfig       => migConfig      (4*i+3 downto 4*i),
                  migStatus       => migStatus      (4*i+3 downto 4*i) );

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
            MASTER_AXI_CONFIG_G => AXIO_STREAM_CONFIG_C)
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

  U_Core : entity axi_pcie_core.XilinxKcu1500Core
    generic map (
      TPD_G             => TPD_G,
      DRIVER_TYPE_ID_G  => toSlv(0,32),
      DMA_SIZE_G        => 5,
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
      dmaObMasters    => dmaObMasters   (5*0+4 downto 5*0),
      dmaObSlaves     => dmaObSlaves    (5*0+4 downto 5*0),
      dmaIbMasters    => dmaIbMasters   (5*0+4 downto 5*0),
      dmaIbSlaves     => dmaIbSlaves    (5*0+4 downto 5*0),
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

  U_MIG0 : entity work.MigA
    port map ( axiReady        => memReady(0),
               --
               axiClk          => clk200         (0),
               axiRst          => urst200        (0),
               axiWriteMasters => memWriteMasters(3 downto 0),
               axiWriteSlaves  => memWriteSlaves (3 downto 0),
               axiReadMasters  => memReadMasters (3 downto 0),
               axiReadSlaves   => memReadSlaves  (3 downto 0),
               --
               ddrClkP         => ddrClkP (0),
               ddrClkN         => ddrClkN (0),
               ddrOut          => ddrOut  (0),
               ddrInOut        => ddrInOut(0) );

  -- Unused user signals
  userLed <= (others => '0');

end top_level;

                    
    
