-------------------------------------------------------------------------------
-- File       : HardwareSemi.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-26
-- Last update: 2019-12-16
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

library axi_pcie_core;
use axi_pcie_core.AxiPciePkg.all;
use surf.Pgp3Pkg.all;

library unisim;
use unisim.vcomponents.all;

entity HardwareSemi is
   generic (
      TPD_G            : time             := 1 ns;
      REFCLK_SELECT_G  : string           := "156M";
      AXIL_CLK_FREQ_G  : real             := 125.0E6;
      AXI_ERROR_RESP_G : slv(1 downto 0)  := AXI_RESP_DECERR_C;
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
      -- DMA Interface
      dmaClks         : out slv                 (3 downto 0);
      dmaRsts         : out slv                 (3 downto 0);
      dmaObMasters    : in  AxiStreamMasterArray(3 downto 0);
      dmaObSlaves     : out AxiStreamSlaveArray (3 downto 0);
      dmaIbMasters    : out AxiStreamMasterArray(3 downto 0);
      dmaIbSlaves     : in  AxiStreamSlaveArray (3 downto 0);
      dmaIbAlmostFull : in  slv                 (3 downto 0);
      dmaIbFull       : in  slv                 (3 downto 0);
      axiCtrl         : in  AxiCtrlType := AXI_CTRL_UNUSED_C;
      locLinkId       : in  Slv32Array          (3 downto 0) := (others=>X"00000000");
      remLinkId       : out Slv32Array          (3 downto 0);
      --
      fifoThres       : in  slv                 (15 downto 0) := toSlv(511,16);
      fifoDepth       : out Slv16Array          (3 downto 0);
      ---------------------
      --  HardwareSemi Ports
      ---------------------    
      -- QSFP[0] Ports
      qsfp0RefClkP    : in  slv(1 downto 0);
      qsfp0RefClkN    : in  slv(1 downto 0);
      qsfp0RxP        : in  slv(3 downto 0);
      qsfp0RxN        : in  slv(3 downto 0);
      qsfp0TxP        : out slv(3 downto 0);
      qsfp0TxN        : out slv(3 downto 0);
      qsfp0RefClkMon  : out sl );
end HardwareSemi;

architecture mapping of HardwareSemi is

   constant NUM_LANES_C       : natural := 4;

   signal txOpCodeEn       : slv                 (NUM_LANES_C-1 downto 0);
   signal txOpCode         : Slv8Array           (NUM_LANES_C-1 downto 0);
   signal rxOpCodeEn       : slv                 (NUM_LANES_C-1 downto 0);
   signal rxOpCode         : Slv8Array           (NUM_LANES_C-1 downto 0);

   signal idmaClks         : slv                 (NUM_LANES_C-1 downto 0);
   signal idmaRsts         : slv                 (NUM_LANES_C-1 downto 0);

   signal sAxisCtrl : AxiStreamCtrlArray(NUM_LANES_C-1 downto 0) := (others=>AXI_STREAM_CTRL_UNUSED_C);
   
   constant DEBUG_C : boolean := false;

   component ila_0
     port ( clk     : in sl;
            probe0  : in slv(255 downto 0) );
   end component;

   signal sAxiCtrl : AxiCtrlType;
begin

   dmaClks <= idmaClks;
   dmaRsts <= idmaRsts;

  GEN_DEBUG : if DEBUG_C generate
    U_SPAUSE : entity surf.Synchronizer
      port map ( clk      => idmaClks(0),
                 dataIn   => axiCtrl .pause,
                 dataOut  => sAxiCtrl.pause );
    U_SOFLOW : entity surf.Synchronizer
      port map ( clk      => idmaClks(0),
                 dataIn   => axiCtrl .overflow,
                 dataOut  => sAxiCtrl.overflow );
    U_ILA : ila_0
      port map ( clk                  => idmaClks(0),
                 probe0(           0) => sAxisCtrl(0).idle,
                 probe0(           1) => sAxisCtrl(0).pause,
                 probe0(           2) => sAxisCtrl(0).overflow,
                 probe0(           3) => dmaIbAlmostFull(0),
                 probe0(           4) => txOpCodeEn(0),
                 probe0(12 downto  5) => txOpCode(0),
                 probe0(          13) => sAxiCtrl.pause,
                 probe0(          14) => sAxiCtrl.overflow,
                 probe0(          15) => dmaIbFull(0),
                 probe0(255 downto 16) => (others=>'0') );
  end generate;
   
   --------------
   -- PGP Modules
   --------------
   U_Pgp : entity work.PgpLaneWrapper
      generic map (
         TPD_G            => TPD_G,
         REFCLK_WIDTH_G   => 1,
         REFCLK_SELECT_G  => REFCLK_SELECT_G,
         NUM_VC_G         => 1,
         AXIL_CLK_FREQ_G  => AXIL_CLK_FREQ_G,
         AXI_BASE_ADDR_G  => AXI_BASE_ADDR_G )
      port map (
         -- QSFP[0] Ports
         qsfp0RefClkP    => qsfp0RefClkP(0)  ,
         qsfp0RefClkN    => qsfp0RefClkN(0)  ,
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
         dmaIbMasters    => dmaIbMasters,
         dmaIbSlaves     => dmaIbSlaves ,
         dmaIbFull       => dmaIbFull   ,
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
         axilReadMaster  => axilReadMaster ,
         axilReadSlave   => axilReadSlave  ,
         axilWriteMaster => axilWriteMaster,
         axilWriteSlave  => axilWriteSlave );

   GEN_LANE : for i in 0 to NUM_LANES_C-1 generate
     U_TxOpCode : entity work.AppTxOpCode
       port map ( clk          => idmaClks       (i),
                  rst          => idmaRsts       (i),
                  rxFull       => dmaIbAlmostFull(i),
                  txFull       => '0',
                  txOpCodeEn   => txOpCodeEn     (i),
                  txOpCode     => txOpCode       (i) );
   end generate;
   
end mapping;
