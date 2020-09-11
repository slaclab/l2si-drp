-------------------------------------------------------------------------------
-- File       : PgpLaneRx.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-26
-- Last update: 2020-08-18
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
use surf.AxiStreamPkg.all;
use surf.Pgp3Pkg.all;

library axi_pcie_core;
use axi_pcie_core.AxiPciePkg.all;

entity PgpLaneRx is
   generic (
      TPD_G             : time     := 1 ns;
      LANE_G            : natural  := 0;
      NUM_VC_G          : positive := 16;
      USE_FLOW_G        : boolean := false );
   port (
      -- DMA Interface (dmaClk domain)
      dmaClk       : in  sl;
      dmaRst       : in  sl;
      dmaIbMaster  : out AxiStreamMasterType;
      dmaIbSlave   : in  AxiStreamSlaveType;
      dmaIbFull    : in  sl := '0';
      fifoThres    : in  slv(15 downto 0);
      fifoDepth    : out slv(15 downto 0);
      frameDrop    : out sl;
      frameTrunc   : out sl;
      sAxisCtrl    : out AxiStreamCtrlType;
      -- PGP Interface (pgpClk domain)
      pgpClk       : in  sl;
      pgpRst       : in  sl;
      rxlinkReady  : in  sl := '1';
      pgpRxMasters : in  AxiStreamMasterArray(NUM_VC_G-1 downto 0);
      pgpRxCtrl    : out AxiStreamCtrlArray(NUM_VC_G-1 downto 0));
end PgpLaneRx;

architecture mapping of PgpLaneRx is

   signal pgpMasters : AxiStreamMasterArray(NUM_VC_G-1 downto 0);
   signal rxMasters  : AxiStreamMasterArray(NUM_VC_G-1 downto 0);
   signal rxSlaves   : AxiStreamSlaveArray (NUM_VC_G-1 downto 0);
   signal rxCtrl     : AxiStreamCtrlArray  (NUM_VC_G-1 downto 0);

   signal rxMaster : AxiStreamMasterType;
   signal rxSlave  : AxiStreamSlaveType;

   constant FIFO_ADDR_WIDTH_C : integer := 10;
   signal fifoThresS : slv(FIFO_ADDR_WIDTH_C-1 downto 0);
   
begin

   frameDrop  <= '0';
   frameTrunc <= '0';
   pgpRxCtrl  <= rxCtrl;

   GEN_CTRL0 : if NUM_VC_G < 2 generate
     sAxisCtrl  <= rxCtrl(0);
   end generate;
   GEN_CTRL1 : if NUM_VC_G > 1 generate
     sAxisCtrl  <= rxCtrl(1);
   end generate;
 
   BLOWOFF_FILTER : process (pgpRxMasters, rxlinkReady) is
      variable tmp : AxiStreamMasterArray(NUM_VC_G-1 downto 0);
      variable i   : natural;
   begin
      tmp := pgpRxMasters;
      for i in NUM_VC_G-1 downto 0 loop
         if (rxlinkReady = '0') then
            tmp(i).tValid := '0';
         end if;
      end loop;
      pgpMasters <= tmp;
   end process;
   
   GEN_VEC :
   for i in NUM_VC_G-1 downto 0 generate

     PGP_FIFO : entity surf.AxiStreamFifoV2
       generic map (
         -- General Configurations
         TPD_G               => TPD_G,
         INT_PIPE_STAGES_G   => 1,
         PIPE_STAGES_G       => 1,
         SLAVE_READY_EN_G    => false,
         VALID_THOLD_G       => 128,
         VALID_BURST_MODE_G  => true,
         -- FIFO configurations
         MEMORY_TYPE_G       => "block",
         GEN_SYNC_FIFO_G     => true,
         FIFO_ADDR_WIDTH_G   => 12,
         FIFO_FIXED_THRESH_G => true,
         FIFO_PAUSE_THRESH_G => 512,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => PGP3_AXIS_CONFIG_C,
         MASTER_AXI_CONFIG_G => PGP3_AXIS_CONFIG_C)
       port map (
         -- Slave Port
         sAxisClk    => pgpClk,
         sAxisRst    => pgpRst,
         sAxisMaster => pgpMasters(i),
         sAxisCtrl   => rxCtrl    (i),
         -- Master Port
         mAxisClk    => pgpClk,
         mAxisRst    => pgpRst,
         mAxisMaster => rxMasters(i),
         mAxisSlave  => rxSlaves (i));

   end generate GEN_VEC;

   U_Mux : entity surf.AxiStreamMux
     generic map (
       TPD_G                => TPD_G,
       NUM_SLAVES_G         => NUM_VC_G,
       MODE_G               => "INDEXED",
       ILEAVE_EN_G          => true,
       ILEAVE_ON_NOTVALID_G => false,
       ILEAVE_REARB_G       => 128,
       PIPE_STAGES_G        => 1)
     port map (
       -- Clock and reset
       axisClk      => pgpClk,
       axisRst      => pgpRst,
       -- Slaves
       sAxisMasters => rxMasters,
       sAxisSlaves  => rxSlaves,
       -- Master
       mAxisMaster  => rxMaster,
       mAxisSlave   => rxSlave);
   
   ASYNC_FIFO : entity surf.AxiStreamFifoV2
     generic map (
       -- General Configurations
       TPD_G               => TPD_G,
       INT_PIPE_STAGES_G   => 1,
       PIPE_STAGES_G       => 1,
       SLAVE_READY_EN_G    => true,
       VALID_THOLD_G       => 1,
       -- FIFO configurations
       MEMORY_TYPE_G       => "block",
       GEN_SYNC_FIFO_G     => false,
       FIFO_ADDR_WIDTH_G   => FIFO_ADDR_WIDTH_C,
       -- AXI Stream Port Configurations
       SLAVE_AXI_CONFIG_G  => PGP3_AXIS_CONFIG_C,
       MASTER_AXI_CONFIG_G => PGP3_AXIS_CONFIG_C)
     port map (
       -- Slave Port
       sAxisClk    => pgpClk,
       sAxisRst    => pgpRst,
       sAxisMaster => rxMaster,
       sAxisSlave  => rxSlave,
       fifoWrCnt   => fifoDepth(FIFO_ADDR_WIDTH_C-1 downto 0),
       -- Master Port
       mAxisClk    => dmaClk,
       mAxisRst    => dmaRst,
       mAxisMaster => dmaIbMaster,
       mAxisSlave  => dmaIbSlave);

   GEN_FIFOD : if (FIFO_ADDR_WIDTH_C < 16) generate
     fifoDepth(15 downto FIFO_ADDR_WIDTH_C) <= (others=>'0');
   end generate;

end mapping;
