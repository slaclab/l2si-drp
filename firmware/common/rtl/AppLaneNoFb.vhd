-------------------------------------------------------------------------------
-- File       : AppLaneNoFb.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-26
-- Last update: 2020-08-18
-------------------------------------------------------------------------------
-- Description: AppLaneNoFb File
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

library l2si_core;
use l2si_core.L2SiPkg.all;

library unisim;
use unisim.vcomponents.all;

entity AppLaneNoFb is
   generic (
      TPD_G            : time             := 1 ns;
      AXIS_CONFIG_G    : AxiStreamConfigType );
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
      -- Trigger Interface
      triggerClk      : in  sl;
      triggerData     : in  TriggerEventDataType;
      -- Timing Interface
      tdetClk         : in  sl;
      tdetClkRst      : in  sl;
      tdetAxisMaster  : in  AxiStreamMasterType;
      tdetAxisSlave   : out AxiStreamSlaveType;
      -- DMA Interface
      dmaClk          : in  sl;
      dmaRst          : in  sl;
      txOpCodeEn      : out sl;
      txOpCode        : out slv(7 downto 0);
      pgpIbMaster     : in  AxiStreamMasterType;
      pgpIbSlave      : out AxiStreamSlaveType;
      dmaIbMaster     : out AxiStreamMasterType;
      dmaIbSlave      : in  AxiStreamSlaveType );
end AppLaneNoFb;

architecture mapping of AppLaneNoFb is

  signal trigger : sl;

  signal pgpObMasters : AxiStreamMasterArray(3 downto 0);
  signal pgpObSlaves  : AxiStreamSlaveArray (3 downto 0);
  signal appObMasters : AxiStreamMasterArray(3 downto 0);
  signal appObSlaves  : AxiStreamSlaveArray (3 downto 0);
  signal tapMaster    : AxiStreamMasterType;
  signal tapSlave     : AxiStreamSlaveType;
  signal txMaster     : AxiStreamMasterType;
  signal txSlave      : AxiStreamSlaveType;
  constant tap        : slv(1 downto 0) := "00";

  signal maxiReadMaster  : AxiLiteReadMasterType;
  signal maxiReadSlave   : AxiLiteReadSlaveType;
  signal maxiWriteMaster : AxiLiteWriteMasterType;
  signal maxiWriteSlave  : AxiLiteWriteSlaveType;
  
begin

  trigger <= triggerData.valid and triggerData.l0Accept;
     
  U_SyncTrig : entity surf.SynchronizerFifo
    generic map ( DATA_WIDTH_G => 5 )
    port map ( rst     => dmaRst,
               wr_clk  => triggerClk,
               wr_en   => trigger,
               din     => triggerData.l0tag,
               rd_clk  => dmaClk,
               rd_en   => '1',
               valid   => txOpCodeEn,
               dout    => txOpCode(4 downto 0) );
  txOpCode(7 downto 5) <= "000";
  
  -------------------
  -- AXI Stream DEMUX
  -------------------
  U_DeMux : entity surf.AxiStreamDeMux
    generic map (
      TPD_G                => TPD_G,
      NUM_MASTERS_G        => 4,
      PIPE_STAGES_G        => 1)
    port map (
      -- Clock and reset
      axisClk      => dmaClk,
      axisRst      => dmaRst,
      -- Inbound Ports
      mAxisMasters => pgpObMasters,
      mAxisSlaves  => pgpObSlaves,
      -- Outbound Port
      sAxisMaster  => pgpIbMaster,
      sAxisSlave   => pgpIbSlave);

  process(appObSlaves, pgpObMasters, tapSlave, txMaster)
    variable appObMastersTmp : AxiStreamMasterArray(3 downto 0);
    variable pgpObSlavesTmp  : AxiStreamSlaveArray(3 downto 0);
    variable tapMasterTmp    : AxiStreamMasterType;
    variable txSlaveTmp      : AxiStreamSlaveType;
    variable vc              : natural;
  begin
    -- Init
    appObMastersTmp := pgpObMasters;
    pgpObSlavesTmp  := appObSlaves;

    -- Calculate the VC tap
    vc := conv_integer(tap);

    -- Event Builder
    tapMasterTmp       := pgpObMasters(vc);
    pgpObSlavesTmp(vc) := tapSlave;

    -- DMA Path after Event builder's FIFO
    appObMastersTmp(vc) := txMaster;
    txSlaveTmp          := appObSlaves(vc);

    -- Outputs
    tapMaster    <= tapMasterTmp;
    txSlave      <= txSlaveTmp;
    pgpObSlaves  <= pgpObSlavesTmp;
    appObMasters <= appObMastersTmp;
  end process;


  -----------------  
  -- AXI Stream MUX
  -----------------
  U_Mux : entity surf.AxiStreamMux
    generic map (
      TPD_G                => TPD_G,
      NUM_SLAVES_G         => 4,
      ILEAVE_EN_G          => true,
      ILEAVE_ON_NOTVALID_G => false,
      ILEAVE_REARB_G       => 128,
      PIPE_STAGES_G        => 1)
    port map (
      -- Clock and reset
      axisClk      => dmaClk,
      axisRst      => dmaRst,
      -- Inbound Ports
      sAxisMasters => appObMasters,
      sAxisSlaves  => appObSlaves,
      -- Outbound Port
      mAxisMaster  => dmaIbMaster,
      mAxisSlave   => dmaIbSlave);

  U_AxiSync : entity surf.AxiLiteAsync
    generic map ( NUM_ADDR_BITS_G => 16 )
    port map (
      sAxiClk         => axilClk,
      sAxiClkRst      => axilRst,
      sAxiReadMaster  => axilReadMaster,
      sAxiReadSlave   => axilReadSlave,
      sAxiWriteMaster => axilWriteMaster,
      sAxiWriteSlave  => axilWriteSlave,
      mAxiClk         => dmaClk,
      mAxiClkRst      => dmaRst,
      mAxiReadMaster  => maxiReadMaster,
      mAxiReadSlave   => maxiReadSlave,
      mAxiWriteMaster => maxiWriteMaster,
      mAxiWriteSlave  => maxiWriteSlave );

  ----------------------------------
  -- Event Builder
  ----------------------------------         
  U_EventBuilder : entity surf.AxiStreamBatcherEventBuilder
    generic map (
      TPD_G          => TPD_G,
      NUM_SLAVES_G   => 2,
      MODE_G         => "ROUTED",
      TDEST_ROUTES_G => (
        0           => "0000000-",   -- Trig on 0x0, Event on 0x1
        1           => "00000010"),  -- Map PGP[tap] to TDEST 0x2      
      TRANS_TDEST_G  => X"01",
      AXIS_CONFIG_G  => AXIS_CONFIG_G)
    port map (
      -- Clock and Reset
      axisClk         => dmaClk,
      axisRst         => dmaRst,
      -- AXI-Lite Interface (axisClk domain)
      axilReadMaster  => maxiReadMaster,
      axilReadSlave   => maxiReadSlave,
      axilWriteMaster => maxiWriteMaster,
      axilWriteSlave  => maxiWriteSlave,
      -- AXIS Interfaces
      sAxisMasters(0) => tdetAxisMaster,
      sAxisMasters(1) => tapMaster,   -- PGP[tap]
      sAxisSlaves(0)  => tdetAxisSlave,
      sAxisSlaves(1)  => tapSlave,    -- PGP[tap]
      mAxisMaster     => txMaster,
      mAxisSlave      => txSlave);

end mapping;
