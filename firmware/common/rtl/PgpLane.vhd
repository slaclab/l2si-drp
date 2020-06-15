-------------------------------------------------------------------------------
-- File       : PgpLane.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-26
-- Last update: 2020-06-14
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

entity PgpLane is
   generic (
      TPD_G            : time             := 1 ns;
      LANE_G           : natural          := 0;
      REFCLK_SELECT_G  : string           := "156M";
      NUM_VC_G         : positive         := 16;
      AXIL_CLK_FREQ_G  : real             := 125.0E+6;
      AXI_ERROR_RESP_G : slv(1 downto 0)  := AXI_RESP_DECERR_C;
      AXI_BASE_ADDR_G  : slv(31 downto 0) := (others => '0') );
   port (
      -- QPLL Interface
      qpllLock        : in  slv(1 downto 0);
      qpllClk         : in  slv(1 downto 0);
      qpllRefclk      : in  slv(1 downto 0);
      qpllRst         : out slv(1 downto 0);
      -- PGP Serial Ports
      pgpTxP          : out sl;
      pgpTxN          : out sl;
      pgpRxP          : in  sl;
      pgpRxN          : in  sl;
      -- DMA Interface (dmaClk domain)
      dmaClk          : out sl;
      dmaRst          : out sl;
      dmaObMaster     : in  AxiStreamMasterType;
      dmaObSlave      : out AxiStreamSlaveType;
      dmaIbMaster     : out AxiStreamMasterType;
      dmaIbSlave      : in  AxiStreamSlaveType;
      dmaIbFull       : in  sl;
      sAxisCtrl       : out AxiStreamCtrlType;
       -- OOB Signals (dmaClk domain)
      txOpCodeEn      : in  sl;
      txOpCode        : in  slv(7 downto 0);
      txLinkId        : in  slv(31 downto 0) := (others=>'0');
      rxOpCodeEn      : out sl;
      rxOpCode        : out slv(7 downto 0);
      rxLinkId        : out slv(31 downto 0);
      usrTxReset      : in  sl := '0';
      usrRxReset      : in  sl := '0';
      fifoThres       : in  slv(15 downto 0);
      fifoDepth       : out slv(15 downto 0);
     -- AXI-Lite Interface (axilClk domain)
      axilClk         : in  sl;
      axilRst         : in  sl;
      axilReadMaster  : in  AxiLiteReadMasterType;
      axilReadSlave   : out AxiLiteReadSlaveType;
      axilWriteMaster : in  AxiLiteWriteMasterType;
      axilWriteSlave  : out AxiLiteWriteSlaveType);
end PgpLane;

architecture mapping of PgpLane is

   signal pgpClk : sl;
   signal pgpRst : sl;

   signal pgpTxOut     : Pgp3TxOutType;
   signal pgpTxMasters : AxiStreamMasterArray(NUM_VC_G-1 downto 0);
   signal pgpTxSlaves  : AxiStreamSlaveArray(NUM_VC_G-1 downto 0);

   signal pgpRxMasters : AxiStreamMasterArray(NUM_VC_G-1 downto 0);
   signal pgpRxCtrl    : AxiStreamCtrlArray(NUM_VC_G-1 downto 0);

   signal pgpRxVcBlowoff : slv(15 downto 0);
   
   signal pgpTxIn      : Pgp3TxInType  := PGP3_TX_IN_INIT_C;
   signal pgpRxIn      : Pgp3RxInType  := PGP3_RX_IN_INIT_C;
   signal pgpRxOut     : Pgp3RxOutType;

   signal pgpRxIn_frameDrop  : sl;
   signal pgpRxIn_frameTrunc : sl;

begin

   dmaClk <= pgpClk;
   dmaRst <= pgpRst;

   rxOpCodeEn  <= pgpRxOut.opCodeEn;
   rxOpCode    <= pgpRxOut.opCodeData( 7 downto 0);
   rxLinkId    <= (others=>'0');
   
   -----------
   -- PGP Core
   -----------
   U_Pgp : entity surf.Pgp3GthUs
      generic map (
         TPD_G             => TPD_G,
--         RATE_G            => ite(REFCLK_SELECT_G = "156M", "10.3125Gbps", "10.3Gbps"),
         NUM_VC_G          => NUM_VC_G,
         EN_PGP_MON_G      => true,
         AXIL_CLK_FREQ_G   => AXIL_CLK_FREQ_G,
         AXIL_BASE_ADDR_G  => AXI_BASE_ADDR_G+x"0000_8000" ) 
--         DEBUG_G           => (LANE_G=0) )
      port map (
         -- Stable Clock and Reset
         stableClk       => axilClk,
         stableRst       => axilRst,
         -- QPLL Interface
         qpllLock        => qpllLock,
         qpllClk         => qpllClk,
         qpllRefclk      => qpllRefclk,
         qpllRst         => qpllRst,
         -- Gt Serial IO
         pgpGtTxP        => pgpTxP,
         pgpGtTxN        => pgpTxN,
         pgpGtRxP        => pgpRxP,
         pgpGtRxN        => pgpRxN,
         -- Clocking
         pgpClk          => pgpClk,
         pgpClkRst       => pgpRst,
         -- Non VC Rx Signals
         pgpRxIn         => pgpRxIn,
         pgpRxOut        => pgpRxOut,
         -- Non VC Tx Signals
         pgpTxIn         => pgpTxIn,
         pgpTxOut        => pgpTxOut,
         -- Frame Transmit Interface
         pgpTxMasters    => pgpTxMasters,
         pgpTxSlaves     => pgpTxSlaves,
         -- Frame Receive Interface
         pgpRxMasters    => pgpRxMasters,
         pgpRxCtrl       => pgpRxCtrl,
         -- AXI-Lite Register Interface (axilClk domain)
         -- usrTxReset      => usrTxReset,
         -- usrRxReset      => usrRxReset,
         axilClk         => axilClk,
         axilRst         => axilRst,
         axilReadMaster  => axilReadMaster,
         axilReadSlave   => axilReadSlave,
         axilWriteMaster => axilWriteMaster,
         axilWriteSlave  => axilWriteSlave );

   --------------
   -- PGP TX Path
   --------------
   U_Tx : entity work.PgpLaneTx
      generic map (
         TPD_G    => TPD_G,
         NUM_VC_G => NUM_VC_G)
      port map (
         -- DMA Interface (dmaClk domain)
         dmaClk       => pgpClk,
         dmaRst       => pgpRst,
         dmaObMaster  => dmaObMaster,
         dmaObSlave   => dmaObSlave,
         -- PGP Interface
         pgpClk       => pgpClk,
         pgpRst       => pgpRst,
         pgpRxOut     => pgpRxOut,
         pgpTxOut     => pgpTxOut,
         pgpTxMasters => pgpTxMasters,
         pgpTxSlaves  => pgpTxSlaves);

   --------------
   -- PGP RX Path
   --------------
   U_Rx : entity work.PgpLaneRx
      generic map (
         TPD_G    => TPD_G,
         LANE_G   => LANE_G,
         NUM_VC_G => NUM_VC_G )
      port map (
         -- DMA Interface (dmaClk domain)
         dmaClk       => pgpClk,
         dmaRst       => pgpRst,
         dmaIbMaster  => dmaIbMaster,
         dmaIbSlave   => dmaIbSlave,
         dmaIbFull    => dmaIbFull,
         frameDrop    => pgpRxIn_frameDrop,
         frameTrunc   => pgpRxIn_frameTrunc,
         sAxisCtrl    => sAxisCtrl,
         fifoThres    => fifoThres,
         fifoDepth    => fifoDepth,
         -- PGP RX Interface (pgpRxClk domain)
         pgpClk       => pgpClk,
         pgpRst       => pgpRst,
         rxLinkReady  => pgpRxOut.linkReady,
         pgpRxMasters => pgpRxMasters,
         pgpRxCtrl    => pgpRxCtrl);

   pgpTxIn.opCodeNumber <= toSlv(6,3);
   pgpTxIn.opCodeEn     <= txOpCodeEn;
   pgpTxIn.opCodeData   <= txLinkId & x"00" & txOpCode;
   pgpTxIn.resetTx      <= usrTxReset;
   pgpRxIn.resetRx      <= usrRxReset;

end mapping;
