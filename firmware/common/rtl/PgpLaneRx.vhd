-------------------------------------------------------------------------------
-- File       : PgpLaneRx.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-26
-- Last update: 2020-02-09
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
      dmaIbFull    : in  sl;
      fifoThres    : in  slv(15 downto 0);
      fifoDepth    : out slv(15 downto 0);
      frameDrop    : out sl;
      frameTrunc   : out sl;
      sAxisCtrl    : out AxiStreamCtrlType;
      -- PGP Interface (pgpClk domain)
      pgpClk       : in  sl;
      pgpRst       : in  sl;
      pgpRxMasters : in  AxiStreamMasterArray(NUM_VC_G-1 downto 0);
      pgpRxCtrl    : out AxiStreamCtrlArray(NUM_VC_G-1 downto 0));
end PgpLaneRx;

architecture mapping of PgpLaneRx is

   function TdestRoutes return Slv8Array is
      variable retConf : Slv8Array(NUM_VC_G-1 downto 0);
   begin
      for i in NUM_VC_G-1 downto 0 loop
         retConf(i) := toSlv((32*LANE_G)+i, 8);
      end loop;
      return retConf;
   end function;

   signal intPgpRxMasters : AxiStreamMasterArray(NUM_VC_G-1 downto 0);
   signal intPgpRxCtrl    : AxiStreamCtrlArray  (NUM_VC_G-1 downto 0);

   signal rxMasters : AxiStreamMasterArray(NUM_VC_G-1 downto 0);
   signal rxSlaves  : AxiStreamSlaveArray(NUM_VC_G-1 downto 0);

   signal rxMaster : AxiStreamMasterType;
   signal rxSlave  : AxiStreamSlaveType;

   signal drop     : slv(NUM_VC_G-1 downto 0);
   signal trunc    : slv(NUM_VC_G-1 downto 0);

   constant FIFO_ADDR_WIDTH_C : integer := 10;
   signal fifoThresS : slv(FIFO_ADDR_WIDTH_C-1 downto 0);
   
begin

   frameDrop  <= uOr(drop);
   frameTrunc <= uOr(trunc);
   sAxisCtrl  <= intPgpRxCtrl(0);
   
   GEN_MUX : if NUM_VC_G > 1 generate

     GEN_VEC :
     for i in NUM_VC_G-1 downto 0 generate

       --
       --  Should never need to assert RxCtrl
       --    If we do, dump packet and assert eofe
       --
       PGP_FLOW : entity work.AxiStreamFlow
         generic map ( DEBUG_G => ite(LANE_G<1, i<1, false) )
         port map (
           clk         => pgpClk,
           rst         => pgpRst,
           sAxisMaster => pgpRxMasters   (i),
           sAxisCtrl   => pgpRxCtrl      (i),
           mAxisMaster => intPgpRxMasters(i),
           mAxisCtrl   => intPgpRxCtrl   (i),
           ibFull      => dmaIbFull,
           drop        => drop           (i),
           trunc       => trunc          (i) );
       

       PGP_FIFO : entity surf.AxiStreamFifoV2
         generic map (
           -- General Configurations
           TPD_G               => TPD_G,
           INT_PIPE_STAGES_G   => 1,
           PIPE_STAGES_G       => 1,
           SLAVE_READY_EN_G    => false,
--           VALID_THOLD_G       => 128,  -- Hold until enough to burst into the interleaving MUX
--           VALID_BURST_MODE_G  => true,
           -- FIFO configurations
           GEN_SYNC_FIFO_G     => true,
           FIFO_ADDR_WIDTH_G   => 10,
           FIFO_FIXED_THRESH_G => true,
           FIFO_PAUSE_THRESH_G => 1020,
           -- AXI Stream Port Configurations
           SLAVE_AXI_CONFIG_G  => PGP3_AXIS_CONFIG_C,
           MASTER_AXI_CONFIG_G => PGP3_AXIS_CONFIG_C)
         port map (
           -- Slave Port
           sAxisClk    => pgpClk,
           sAxisRst    => pgpRst,
           sAxisMaster => intPgpRxMasters(i),
           sAxisCtrl   => intPgpRxCtrl   (i),
           -- Master Port
           mAxisClk    => pgpClk,
           mAxisRst    => pgpRst,
           mAxisMaster => rxMasters(i),
           mAxisSlave  => rxSlaves(i));

     end generate GEN_VEC;

     U_Mux : entity surf.AxiStreamMux
       generic map (
         TPD_G                => TPD_G,
         NUM_SLAVES_G         => NUM_VC_G,
         MODE_G               => "ROUTED",
         TDEST_ROUTES_G       => TdestRoutes,
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
         GEN_SYNC_FIFO_G     => false,
         FIFO_ADDR_WIDTH_G   => 9,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => PGP3_AXIS_CONFIG_C,
         MASTER_AXI_CONFIG_G => PGP3_AXIS_CONFIG_C)
       port map (
         -- Slave Port
         sAxisClk    => pgpClk,
         sAxisRst    => pgpRst,
         sAxisMaster => rxMaster,
         sAxisSlave  => rxSlave,
         -- Master Port
         mAxisClk    => dmaClk,
         mAxisRst    => dmaRst,
         mAxisMaster => dmaIbMaster,
         mAxisSlave  => dmaIbSlave);

   end generate;

   GEN_NOMUX : if NUM_VC_G < 2 generate

     GEN_FLOW : if USE_FLOW_G generate
       PGP_FLOW : entity work.AxiStreamFlow
--       generic map ( DEBUG_G => LANE_G=0 )
         generic map ( DEBUG_G => false )
         port map (
           clk         => pgpClk,
           rst         => pgpRst,
           sAxisMaster => pgpRxMasters   (0),
           sAxisCtrl   => pgpRxCtrl      (0),
           mAxisMaster => intPgpRxMasters(0),
           mAxisCtrl   => intPgpRxCtrl   (0),
           ibFull      => dmaIbFull,
           drop        => drop           (0),
           trunc       => trunc          (0) );
     end generate;

     NO_GEN_FLOW : if not USE_FLOW_G generate
       pgpRxCtrl       <= intPgpRxCtrl;
       intPgpRxMasters <= pgpRxMasters;
       drop            <= (others=>'0');
       trunc           <= (others=>'0');
     end generate;

     U_SyncTh : entity surf.SynchronizerVector
       generic map ( WIDTH_G => FIFO_ADDR_WIDTH_C )
       port map ( clk      => pgpClk,
                  dataIn   => fifoThres(FIFO_ADDR_WIDTH_C-1 downto 0),
                  dataOut  => fifoThresS );

     --
     --  Not using FIXED_THRESH results in pause always asserted?
     --
     ASYNC_FIFO : entity surf.AxiStreamFifoV2
       generic map (
         -- General Configurations
         TPD_G               => TPD_G,
         INT_PIPE_STAGES_G   => 1,
         PIPE_STAGES_G       => 1,
         SLAVE_READY_EN_G    => false,
--         VALID_THOLD_G       => 128,  -- Hold until enough to burst into the interleaving MUX
--         VALID_BURST_MODE_G  => true,
         -- FIFO configurations
         GEN_SYNC_FIFO_G     => false,
         FIFO_ADDR_WIDTH_G   => FIFO_ADDR_WIDTH_C,
         FIFO_FIXED_THRESH_G => true,
         FIFO_PAUSE_THRESH_G => 511,
         -- AXI Stream Port Configurations
         SLAVE_AXI_CONFIG_G  => PGP3_AXIS_CONFIG_C,
         MASTER_AXI_CONFIG_G => PGP3_AXIS_CONFIG_C)
       port map (
         -- Slave Port
         sAxisClk    => pgpClk,
         sAxisRst    => pgpRst,
         sAxisMaster => intPgpRxMasters(0),
         sAxisCtrl   => intPgpRxCtrl   (0),
         --
         fifoPauseThresh => fifoThresS,
         fifoWrCnt       => fifoDepth(FIFO_ADDR_WIDTH_C-1 downto 0),
         -- Master Port
         mAxisClk    => dmaClk,
         mAxisRst    => dmaRst,
         mAxisMaster => dmaIbMaster,
         mAxisSlave  => dmaIbSlave);
   end generate;

   GEN_FIFOD : if (FIFO_ADDR_WIDTH_C < 16) generate
     fifoDepth(15 downto FIFO_ADDR_WIDTH_C) <= (others=>'0');
   end generate;
   
end mapping;
