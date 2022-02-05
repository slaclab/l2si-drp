-------------------------------------------------------------------------------
-- File       : PgpLaneWrapper.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-26
-- Last update: 2022-02-04
-------------------------------------------------------------------------------
-- Description: 
-------------------------------------------------------------------------------
-- This file is part of 'SLAC PGP Gen3 Card'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'SLAC PGP Gen3 Card', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;


library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;

library axi_pcie_core;
use axi_pcie_core.AxiPciePkg.all;
use surf.Pgp3Pkg.all;

library unisim;
use unisim.vcomponents.all;

entity PgpLaneWrapper is
   generic (
      TPD_G            : time             := 1 ns;
      RATE_G           : string           := "10.3125Gbps"; -- 3.125Gbps (unused)
      REFCLK_WIDTH_G   : positive         := 2;
      REFCLK_SELECT_G  : string           := "156M"; -- "156M" or "186M"
      NUM_VC_G         : positive         := 16;
      NUM_LANES_G      : integer          := 4;
      AXIL_CLK_FREQ_G  : real             := 125.0E6;
      AXI_BASE_ADDR_G  : slv(31 downto 0) := (others => '0') );
   port (
      -- QSFP[0] Ports
      qsfp0RefClkP    : in  sl;
      qsfp0RefClkN    : in  sl;
      qsfp0RxP        : in  slv(NUM_LANES_G-1 downto 0);
      qsfp0RxN        : in  slv(NUM_LANES_G-1 downto 0);
      qsfp0TxP        : out slv(NUM_LANES_G-1 downto 0);
      qsfp0TxN        : out slv(NUM_LANES_G-1 downto 0);
      qsfp0RefClkMon  : out sl;
      -- DMA Interface (dmaClk domain)
      dmaClks         : out slv                 (NUM_LANES_G-1 downto 0);
      dmaRsts         : out slv                 (NUM_LANES_G-1 downto 0);
      dmaObMasters    : in  AxiStreamMasterArray(NUM_LANES_G-1 downto 0);
      dmaObSlaves     : out AxiStreamSlaveArray (NUM_LANES_G-1 downto 0);
      dmaIbMasters    : out AxiStreamMasterArray(NUM_LANES_G-1 downto 0);
      dmaIbSlaves     : in  AxiStreamSlaveArray (NUM_LANES_G-1 downto 0);
      dmaIbFull       : in  slv                 (NUM_LANES_G-1 downto 0);
      sAxisCtrl       : out AxiStreamCtrlArray  (NUM_LANES_G-1 downto 0);
       -- OOB Signals
      txOpCodeEn      : in  slv                 (NUM_LANES_G-1 downto 0) := (others=>'0');
      txOpCode        : in  Slv8Array           (NUM_LANES_G-1 downto 0) := (others=>X"00");
      rxOpCodeEn      : out slv                 (NUM_LANES_G-1 downto 0);
      rxOpCode        : out Slv8Array           (NUM_LANES_G-1 downto 0);
      fifoThres       : in  slv                 (15 downto 0);
      fifoDepth       : out Slv16Array          (NUM_LANES_G-1 downto 0);
     -- AXI-Lite Interface (axilClk domain)
      axilClk         : in  sl;
      axilRst         : in  sl;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end PgpLaneWrapper;

architecture mapping of PgpLaneWrapper is

   constant NUM_AXI_MASTERS_C : natural := 5;

   constant AXI_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXI_MASTERS_C-1 downto 0) := genAxiLiteConfig(NUM_AXI_MASTERS_C, AXI_BASE_ADDR_G, 20, 16);

   signal axilWriteMasters : AxiLiteWriteMasterArray(NUM_AXI_MASTERS_C-1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray (NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadMasters  : AxiLiteReadMasterArray (NUM_AXI_MASTERS_C-1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray  (NUM_AXI_MASTERS_C-1 downto 0);

   signal pgpRxP : slv(7 downto 0);
   signal pgpRxN : slv(7 downto 0);
   signal pgpTxP : slv(7 downto 0);
   signal pgpTxN : slv(7 downto 0);

   signal qpllLock   : Slv2Array(7 downto 0);
   signal qpllClk    : Slv2Array(7 downto 0);
   signal qpllRefclk : Slv2Array(7 downto 0);
   signal qpllRst    : Slv2Array(7 downto 0);
   signal qpllRstF   : Slv2Array(7 downto 0);
   signal qpllLockS  : sl;

   signal obMasters : AxiStreamMasterArray(7 downto 0);
   signal obSlaves  : AxiStreamSlaveArray(7 downto 0);
   signal ibMasters : AxiStreamMasterArray(7 downto 0);
   signal ibSlaves  : AxiStreamSlaveArray(7 downto 0);

   signal pgpObMasters : AxiStreamMasterArray    (7 downto 0);
   signal pgpObSlaves  : AxiStreamSlaveArray     (7 downto 0);
   signal pgpIbMasters : AxiStreamQuadMasterArray(7 downto 0);
   signal pgpIbSlaves  : AxiStreamQuadSlaveArray (7 downto 0);

   signal refClk : slv((2*REFCLK_WIDTH_G)-1 downto 0);
   signal monClk : sl;
   attribute dont_touch           : string;
   attribute dont_touch of refClk : signal is "TRUE";

   signal idmaClks : slv(NUM_LANES_G-1 downto 0);
   signal rxLinkId, txLinkId, rxLinkIdS : Slv32Array(NUM_LANES_G-1 downto 0);
   
   type RegType is record
     txLinkId       : Slv32Array(NUM_LANES_G-1 downto 0);
     qpllReset      : sl;
     txReset        : sl;
     rxReset        : sl;
     axilWriteSlave : AxiLiteWriteSlaveType;
     axilReadSlave  : AxiLiteReadSlaveType;
   end record;

   constant REG_INIT_C : RegType := (
     txLinkId       => (others=>(others=>'0')),
     qpllReset      => '0',
     txReset        => '0',
     rxReset        => '0',
     axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C,
     axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C );

   signal r    : RegType;
   signal rin  : RegType;
   
begin

   dmaClks <= idmaClks;
   
   ------------------------
   -- Common PGP Clocking
   ------------------------
   GEN_REFCLK :
   for i in REFCLK_WIDTH_G-1 downto 0 generate

      U_QsfpRef0 : IBUFDS_GTE3
         generic map (
            REFCLK_EN_TX_PATH  => '0',
            REFCLK_HROW_CK_SEL => "00",  -- 2'b00: ODIV2 = O
            REFCLK_ICNTL_RX    => "00")
         port map (
            I     => qsfp0RefClkP,
            IB    => qsfp0RefClkN,
            CEB   => '0',
            ODIV2 => monClk,
            O     => refClk((2*i)+0));

      U_BUFG : BUFG_GT
        port map (
          I       => monClk,
          CE      => '1',
          CEMASK  => '1',
          CLR     => '0',
          CLRMASK => '1',
          DIV     => "000",
          O       => qsfp0RefClkMon );
      
   end generate GEN_REFCLK;

   GEN_PLL : if RATE_G = "10.3125Gbps" generate
     GEN_156 : if REFCLK_SELECT_G = "156M" generate
       U_QPLL : entity surf.Pgp3GthUsQpll
         generic map (
           TPD_G             => TPD_G )
         port map (
           -- Stable Clock and Reset
           stableClk  => axilClk,
           stableRst  => axilRst,
           -- QPLL Clocking
           pgpRefClk  => refClk    (0),
           qpllLock   => qpllLock  (3 downto 0),
           qpllClk    => qpllClk   (3 downto 0),
           qpllRefclk => qpllRefclk(3 downto 0),
           qpllRst    => qpllRst   (3 downto 0) );
     end generate;

     GEN_186 : if REFCLK_SELECT_G = "186M" generate
       U_QPLL : entity work.Pgp3GthUs186Qpll
         generic map (
           TPD_G             => TPD_G )
         port map (
           -- Stable Clock and Reset
           stableClk  => axilClk,
           stableRst  => axilRst,
           -- QPLL Clocking
           pgpRefClk  => refClk    (0),
           qpllLock   => qpllLock  (3 downto 0),
           qpllClk    => qpllClk   (3 downto 0),
           qpllRefclk => qpllRefclk(3 downto 0),
           qpllRst    => qpllRst   (3 downto 0) );
     end generate;
   end generate;

   --------------------------------
   -- Mapping QSFP[1:0] to PGP[7:0]
   --------------------------------
   MAP_QSFP : for i in NUM_LANES_G-1 downto 0 generate
      -- QSFP[0] to PGP[3:0]
      pgpRxP(i+0) <= qsfp0RxP(i);
      pgpRxN(i+0) <= qsfp0RxN(i);
      qsfp0TxP(i) <= pgpTxP(i+0);
      qsfp0TxN(i) <= pgpTxN(i+0);
   end generate MAP_QSFP;

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

   ------------
   -- PGP Lanes
   ------------
   GEN_LANE : for i in 0 to NUM_LANES_G-1 generate

      qpllRst(i) <= (r.qpllReset or qpllRstF(i)(1)) & (r.qpllReset or qpllRstF(i)(0));

      U_SyncTxId : entity surf.SynchronizerVector
        generic map ( WIDTH_G => 32 )
        port map ( clk        => idmaClks(i),
                   dataIn     => r.txLinkId(i),
                   dataOut    => txLinkId(i) );
      
      U_SyncRxId : entity surf.SynchronizerVector
        generic map ( WIDTH_G => 32 )
        port map ( clk        => axilClk,
                   dataIn     => rxLinkId(i),
                   dataOut    => rxLinkIdS(i) );

      U_Lane : entity work.PgpLane
        generic map (
          TPD_G            => TPD_G,
          LANE_G           => i,
          REFCLK_SELECT_G  => REFCLK_SELECT_G,
          RATE_G           => RATE_G,
          NUM_VC_G         => NUM_VC_G,
          AXIL_CLK_FREQ_G  => AXIL_CLK_FREQ_G,
          AXI_BASE_ADDR_G  => AXI_CONFIG_C(i).baseAddr )
        port map (
          -- QPLL Interface
          qpllLock        => qpllLock(i),
          qpllClk         => qpllClk(i),
          qpllRefclk      => qpllRefclk(i),
          qpllRst         => qpllRstF(i),
          -- PGP Serial Ports
          pgpRxP          => pgpRxP(i),
          pgpRxN          => pgpRxN(i),
          pgpTxP          => pgpTxP(i),
          pgpTxN          => pgpTxN(i),
          -- DMA Interface (dmaClk domain)
          dmaClk          => idmaClks  (i),
          dmaRst          => dmaRsts  (i),
          dmaObMaster     => obMasters(i),
          dmaObSlave      => obSlaves (i),
          dmaIbMaster     => ibMasters(i),
          dmaIbSlave      => ibSlaves (i),
          dmaIbFull       => dmaIbFull(i),
          sAxisCtrl       => sAxisCtrl(i),
          -- OOB Signals
          txOpCodeEn      => txOpCodeEn(i),
          txOpCode        => txOpCode  (i),
          txLinkId        => txLinkId  (i),
          rxOpCodeEn      => rxOpCodeEn(i),
          rxOpCode        => rxOpCode  (i),
          rxLinkId        => rxLinkId  (i),
          usrTxReset      => r.txReset,
          usrRxReset      => r.rxReset,
          fifoThres       => fifoThres,
          fifoDepth       => fifoDepth(i),
          -- AXI-Lite Interface (axilClk domain)
          axilClk         => axilClk,
          axilRst         => axilRst,
          axilReadMaster  => axilReadMasters(i),
          axilReadSlave   => axilReadSlaves(i),
          axilWriteMaster => axilWriteMasters(i),
          axilWriteSlave  => axilWriteSlaves(i));
      
      obMasters(i)    <= dmaObMasters(i);
      dmaObSlaves(i)  <= obSlaves(i);

      dmaIbMasters(i) <= ibMasters(i);
      ibSlaves(i)     <= dmaIbSlaves(i);

   end generate GEN_LANE;

   U_QPLLLOCKS : entity surf.Synchronizer
     port map ( clk     => axilClk,
                dataIn  => qpllLock(0)(0),
                dataOut => qpllLockS );
   
   comb : process ( r, axilRst, rxLinkIdS, qpllLockS, axilReadMasters, axilWriteMasters ) is
     variable v   : RegType;
     variable ep  : AxiLiteEndPointType;
   begin
     v := r;

     axiSlaveWaitTxn(ep, axilWriteMasters(4), axilReadMasters(4), v.axilWriteSlave, v.axilReadSlave);

     for i in 0 to NUM_LANES_G-1 loop
       axiSlaveRegisterR(ep, toSlv(0 +i*4,8), 0, rxLinkIdS(i) );
       axiSlaveRegister (ep, toSlv(16+i*4,8), 0, v.txLinkId(i) );
     end loop;

     axiSlaveRegisterR(ep, toSlv(32,8), 0, qpllLockS);
     axiSlaveRegister (ep, toSlv(36,8), 0, v.qpllReset);
     axiSlaveRegister (ep, toSlv(36,8), 1, v.txReset);
     axiSlaveRegister (ep, toSlv(36,8), 2, v.rxReset);
     
     axiSlaveDefault(ep, v.axilWriteSlave, v.axilReadSlave);

     axilWriteSlaves(4) <= r.axilWriteSlave;
     axilReadSlaves (4) <= r.axilReadSlave;

     if axilRst = '1' then
       v := REG_INIT_C;
     end if;

     rin <= v;

   end process comb;

   seq : process ( axilClk ) is
   begin
     if rising_edge(axilClk) then
       r <= rin;
     end if;
   end process;
   
end mapping;
