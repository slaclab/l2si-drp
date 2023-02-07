-------------------------------------------------------------------------------
-- File       : TDetSemi.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-26
-- Last update: 2023-02-07
-------------------------------------------------------------------------------
-- Description: TDetSemi File
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
use surf.SsiPkg.all;
use surf.Pgp3Pkg.all;

library lcls_timing_core;
use lcls_timing_core.TimingPkg.all;

library l2si_core;
use l2si_core.L2SiPkg.all;
use l2si_core.XpmExtensionPkg.all;

library unisim;
use unisim.vcomponents.all;

entity TDetSemi is
  generic (
    TPD_G            : time             := 1 ns;
    NUM_LANES_G      : integer          := 4;
    DEBUG_G          : boolean          := false );
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
    dmaClks         : out slv                 (NUM_LANES_G-1 downto 0);
    dmaRsts         : out slv                 (NUM_LANES_G-1 downto 0);
    dmaObMasters    : in  AxiStreamMasterArray(NUM_LANES_G-1 downto 0);
    dmaObSlaves     : out AxiStreamSlaveArray (NUM_LANES_G-1 downto 0);
    dmaIbMasters    : out AxiStreamMasterArray(NUM_LANES_G-1 downto 0);
    dmaIbSlaves     : in  AxiStreamSlaveArray (NUM_LANES_G-1 downto 0);
    dmaIbAlmostFull : in  slv                 (NUM_LANES_G-1 downto 0);
    dmaIbFull       : in  slv                 (NUM_LANES_G-1 downto 0);
    axiCtrl         : in  AxiCtrlType := AXI_CTRL_UNUSED_C;
    ---------------------
    --  TDetSemi Ports
    ---------------------
    tdetClk         : in  sl;
    tdetClkRst      : in  sl;
    tdetTimingMsgs  : in  TimingMessageArray       (NUM_LANES_G-1 downto 0);
    tdetTimingRds   : out slv                      (NUM_LANES_G-1 downto 0);
    tdetInhibitCts  : in  TriggerInhibitCountsArray(NUM_LANES_G-1 downto 0);
    tdetInhibitRds  : out slv                      (NUM_LANES_G-1 downto 0);
    tdetAxisMaster  : in  AxiStreamMasterArray     (NUM_LANES_G-1 downto 0);
    tdetAxisSlave   : out AxiStreamSlaveArray      (NUM_LANES_G-1 downto 0);
    tdetAlmostFull  : out slv                      (NUM_LANES_G-1 downto 0);
    modPrsL         : in  sl );
end TDetSemi;

architecture mapping of TDetSemi is

  signal intObMasters     : AxiStreamMasterArray(NUM_LANES_G-1 downto 0);
  signal intObSlaves      : AxiStreamSlaveArray (NUM_LANES_G-1 downto 0);
  signal dmaObAlmostFull  : slv                 (NUM_LANES_G-1 downto 0) := (others=>'0');

  signal txOpCodeEn       : slv                 (NUM_LANES_G-1 downto 0);
  signal txOpCode         : Slv8Array           (NUM_LANES_G-1 downto 0);
  signal rxOpCodeEn       : slv                 (NUM_LANES_G-1 downto 0);
  signal rxOpCode         : Slv8Array           (NUM_LANES_G-1 downto 0);

  signal idmaClks         : slv                 (NUM_LANES_G-1 downto 0);
  signal idmaRsts         : slv                 (NUM_LANES_G-1 downto 0);

  signal sAxisCtrl : AxiStreamCtrlArray(NUM_LANES_G-1 downto 0) := (others=>AXI_STREAM_CTRL_UNUSED_C);

  type AxiRegType is record
    enable    : slv(NUM_LANES_G-1 downto 0);
    aFull     : slv(NUM_LANES_G-1 downto 0);
    clear     : slv(NUM_LANES_G-1 downto 0);
    length    : Slv23Array(NUM_LANES_G-1 downto 0);
    axilWriteSlave  : AxiLiteWriteSlaveType;
    axilReadSlave   : AxiLiteReadSlaveType;
  end record;
  constant AXI_REG_INIT_C : AxiRegType := (
    enable    => (others=>'0'),
    aFull     => (others=>'0'),
    clear     => (others=>'0'),
    length    => (others=>(others=>'0')),
    axilWriteSlave => AXI_LITE_WRITE_SLAVE_INIT_C,
    axilReadSlave  => AXI_LITE_READ_SLAVE_INIT_C );

  signal a    : AxiRegType := AXI_REG_INIT_C;
  signal ain  : AxiRegType;
  signal as   : AxiRegType;
  
  constant TDET_USER_BITS_C : integer := 2048;
  
  type StateType is (IDLE_S,
                     WAIT_S,
                     HDR1_S,
                     HDR2_S,
                     HDR3_S,
                     SEND_S,
                     USER_S);
  type StateArray is array(natural range<>) of StateType;
  
  type RegType is record
    state       : StateType;
    length      : slv(22 downto 0);
    count       : slv(31 downto 0);
    event       : sl;
    timingMsgRd : sl;
    inhibitCtRd : sl;
    user        : slv(TDET_USER_BITS_C-1 downto 0);
    transHeader : slv(6 downto 0);
    axisSlave  : AxiStreamSlaveType;
    txMaster    : AxiStreamMasterType;
  end record;

  constant REG_INIT_C : RegType := (
    state       => IDLE_S,
    length      => (others=>'0'),
    count       => (others=>'0'),
    event       => '0',
    timingMsgRd => '0',
    inhibitCtRd => '0',
    user        => (others=>'0'),
    transHeader => (others=>'0'),
    axisSlave   => AXI_STREAM_SLAVE_INIT_C,
    txMaster    => AXI_STREAM_MASTER_INIT_C );

  type RegArray is array(natural range<>) of RegType;

  signal r   : RegArray(NUM_LANES_G-1 downto 0) := (others=>REG_INIT_C);
  signal rin : RegArray(NUM_LANES_G-1 downto 0);

  signal t_dataI   : slv(63 downto 0);
  signal t_dataO   : slv(63 downto 0);
  
  constant DEBUG_C : boolean := DEBUG_G;

  component ila_0
    port ( clk     : in sl;
           probe0  : in slv(255 downto 0) );
  end component;

  --
  --  Format the data for software (psana) consumption
  --
  constant TIMING_MSG_FORMAT_LEN_C : integer := 968+XPM_INHIBIT_COUNTS_LEN_C;
  function toSlvFormatted(msg : TimingMessageType;
                          inh : TriggerInhibitCountsType) return slv is
    variable v : slv(TIMING_MSG_FORMAT_LEN_C-1 downto 0) := (others=>'0');
    variable i : integer := 0;
  begin
    assignSlv(i, v, msg.pulseId);                             -- [63:0]
    assignSlv(i, v, msg.timeStamp);                           -- [127:64]
    for j in 0 to msg.fixedRates'length-1 loop                -- [207:128]
      assignSlv(i, v, "0000000" & msg.fixedRates(j));
    end loop;
    for j in 0 to msg.acRates'length-1 loop                   -- [255:208]
      assignSlv(i, v, "0000000" & msg.acRates(j));
    end loop;
    assignSlv(i, v, resize(msg.acTimeSlot,8));                   -- [263:256]
    assignSlv(i, v, resize(msg.acTimeSlotPhase,16));             -- [279:264]
    assignSlv(i, v, "0000000" & msg.beamRequest(0));             -- [287:280]
    assignSlv(i, v, resize(msg.beamRequest(7 downto 4),8));    -- [295:288]
    assignSlv(i, v, msg.beamRequest(31 downto 16));           -- [311:296]
    for j in msg.beamEnergy'range loop                        -- [375:312]
      assignSlv(i, v, msg.beamEnergy(j));
    end loop;
    for j in msg.photonWavelen'range loop                     -- [407:376]
      assignSlv(i, v, msg.photonWavelen(j));
    end loop;
    assignSlv(i, v, msg.control(16));                         -- [423:408]
    for j in msg.mpsLimit'range loop
      assignSlv(i, v, "0000000" & msg.mpsLimit(j));              -- [551:424]
    end loop;
    for j in msg.mpsClass'range loop                          -- [679:552]
      assignSlv(i, v, resize(msg.mpsClass(j),8));
    end loop;
    for j in msg.control'range loop                           -- [967:680]
      assignSlv(i, v, msg.control(j));
    end loop;
    assignSlv(i, v, toSlv(inh));
    return v;
  end function;
  
begin

  dmaClks <= idmaClks;
  dmaRsts <= idmaRsts;

  t_dataI <= tdetAxisMaster(0).tData(t_dataI'range);
  t_dataO <= r(0).txMaster.tData(t_dataO'range);
  
  GEN_LANE : for i in 0 to NUM_LANES_G-1 generate
    idmaClks(i)     <= tdetClk;
    idmaRsts(i)     <= tdetClkRst;
    dmaIbMasters(i) <= r(i).txMaster;
    ----------------------------------------
    -- Emulate PGP Read of TDET Registers --
    ----------------------------------------
    --if v.txMaster.tValid = '0' then
    --  v.txMaster := saxisMasters(i);
    --  saxisSlaves  (i).tReady <= '1';
    --end if;
    dmaObSlaves (i) <= AXI_STREAM_SLAVE_FORCE_C;
  end generate;

  acomb : process ( a, axilRst, axilReadMaster, axilWriteMaster, modPrsL ) is
    variable v  : AxiRegType;
    variable ep : AxiLiteEndpointType;
  begin
    v := a;

    axiSlaveWaitTxn ( ep, axilWriteMaster, axilReadMaster, v.axilWriteSlave, v.axilReadSlave );
    for i in 0 to NUM_LANES_G-1 loop
      axiSlaveRegister( ep, toSlv(i*4,8), 0, v.length(i)  );
      axiSlaveRegister( ep, toSlv(i*4,8),30, v.clear (i) );
      axiSlaveRegister( ep, toSlv(i*4,8),31, v.enable(i) );
    end loop;
    axiSlaveRegisterR( ep, x"20", 0, modPrsL);

    axiSlaveDefault ( ep, v.axilWriteSlave, v.axilReadSlave );

    if axilRst = '1' then
      v := AXI_REG_INIT_C;
    end if;

    ain <= v;

    axilReadSlave  <= a.axilReadSlave;
    axilWriteSlave <= a.axilWriteSlave;
  end process acomb;

  aseq : process ( axilClk ) is
  begin
    if rising_edge(axilClk) then
      a <= ain;
    end if;
  end process aseq;

  GEN_DEBUG : if DEBUG_C generate
    U_ILA : ila_0
      port map ( clk       => tdetClk,
                 probe0(0) => as.enable(0),
                 probe0(1) => dmaIbSlaves(0).tReady,
                 probe0(2) => r(0).axisSlave.tReady,
                 probe0(3) => r(0).txMaster.tValid,
                 probe0(4) => tdetAxisMaster(0).tValid,
                 probe0(5) => tdetAxisMaster(0).tLast,
                 probe0(6) => tdetAxisMaster(0).tDest(0),
                 probe0(7) => r(0).event,
                 probe0(71 downto 8) => r(0).txMaster.tData(63 downto 0),
                 probe0(255 downto 72) => (others=>'0') );
  end generate;
  
  U_AFullS : entity surf.SynchronizerVector
    generic map ( WIDTH_G => NUM_LANES_G )
    port map ( clk => tdetClk, dataIn => dmaIbAlmostFull, dataOut => tdetAlmostFull );
  U_ClearS : entity surf.SynchronizerVector
    generic map ( WIDTH_G => NUM_LANES_G )
    port map ( clk => tdetClk, dataIn => a.clear, dataOut => as.clear );
  G_LengthS : for i in 0 to NUM_LANES_G-1 generate
    U_LengthS : entity surf.SynchronizerVector
      generic map ( WIDTH_G => a.length(i)'length )
      port map ( clk => tdetClk, dataIn => a.length(i), dataOut => as.length(i) );
  end generate;
  U_EnableS : entity surf.SynchronizerVector
    generic map ( WIDTH_G => a.enable'length )
    port map ( clk => tdetClk, dataIn => a.enable, dataOut => as.enable );
  
--  comb : process ( r, tdetClkRst, tdetEventMaster, tdetTransMaster, strigBus, as, dmaIbSlaves ) is
  comb : process ( r, tdetClkRst, tdetAxisMaster, tdetTimingMsgs, tdetInhibitCts, as, dmaIbSlaves ) is
    variable v : RegType;
    variable i,j : integer;
    constant DATALEN : integer := PGP3_AXIS_CONFIG_C.TDATA_BYTES_C*8;
  begin
    for i in 0 to NUM_LANES_G-1 loop
      v := r(i);
      v.axisSlave.tReady  := '0';
      v.timingMsgRd       := '0';
      v.inhibitCtRd       := '0';
      
      if dmaIbSlaves(i).tReady = '1' then
        v.txMaster.tValid := '0';
      end if;

      if as.enable(i) = '0' then
        v.axisSlave.tReady := '1';
      end if;
      
      case r(i).state is
        when WAIT_S =>
          v.state := IDLE_S;
        when IDLE_S =>
          if as.enable(i) = '1' and v.txMaster.tValid = '0' then
            if tdetAxisMaster(i).tValid = '1' then
              v.state           := HDR1_S;
              v.event           := not tdetAxisMaster(i).tDest(0);
              ssiSetUserSof(PGP3_AXIS_CONFIG_C, v.txMaster, '1');
              v.txMaster.tValid := '1';
              v.txMaster.tLast  := '0';
              v.txMaster.tKeep  := genTKeep(PGP3_AXIS_CONFIG_C);
              v.txMaster.tData(63 downto 0) := tdetAxisMaster(i).tData(63 downto 0);
              v.transHeader     := tdetAxisMaster(i).tData(62 downto 56);
            end if;
          end if;
        when HDR1_S =>
          if v.txMaster.tValid = '0' then
            v.state           := HDR2_S;
            ssiSetUserSof(PGP3_AXIS_CONFIG_C, v.txMaster, '0');
            v.txMaster.tValid := '1';
            v.txMaster.tLast  := '0';
            v.txMaster.tData(63 downto 0) := tdetAxisMaster(i).tData(127 downto 64);
            v.txMaster.tKeep  := genTKeep(PGP3_AXIS_CONFIG_C);
          end if;
        when HDR2_S =>
          if v.txMaster.tValid = '0' then
            v.state           := HDR3_S;
            v.txMaster.tValid := '1';
            v.txMaster.tLast  := '0';
            v.txMaster.tData(63 downto 0) := tdetAxisMaster(i).tData(191 downto 128);
            v.txMaster.tKeep  := genTKeep(PGP3_AXIS_CONFIG_C);
          end if;
        when HDR3_S =>
          if v.txMaster.tValid = '0' then
            v.axisSlave.tReady:= '1';
            v.txMaster.tValid := '1';
            v.txMaster.tData(63 downto 0) := toSlv(0,64);
            v.txMaster.tKeep  := genTKeep(PGP3_AXIS_CONFIG_C);
            if r(i).event = '1' then
              v.txMaster.tLast    := '0';
              if as.length(i) = 0 then
                -- Workaround for small payload DMA problem;  pad to 256 bytes
                v.length          := toSlv(2048,r(i).length'length);
                -- v.length          := resize(strigBus(i).userlen,r(i).length'length);
                v.user(toSlvFormatted(TIMING_MESSAGE_INIT_C,tdetInhibitCts(i))'range)
                  := toSlvFormatted(tdetTimingMsgs(i),tdetInhibitCts(i));
                v.timingMsgRd     := '1';
                v.inhibitCtRd     := '1';
                v.state           := USER_S;
              else
                v.length          := as.length(i);
                v.state           := SEND_S;
              end if;
            elsif as.length(i) = 0 and r(i).transHeader/=toSlv(10,7) then
              -- slowupdate carries no payload
              v.txMaster.tLast    := '0';
              -- Workaround for small payload DMA problem;  pad to 256 bytes
              v.length          := toSlv(2048,r(i).length'length);
              -- v.length          := resize(strigBus(i).userlen,r(i).length'length);
              v.user(toSlv(tdetInhibitCts(i))'range)
                := toSlv(tdetInhibitCts(i));
              v.inhibitCtRd     := '1';
              v.state           := USER_S;
            else
              v.txMaster.tLast    := '1';
              v.state             := WAIT_S;
            end if;
          end if;
        when SEND_S =>
          if v.txMaster.tValid = '0' then
            for j in 0 to PGP3_AXIS_CONFIG_C.TDATA_BYTES_C/4-1 loop
              v.txMaster.tData(32*j+31 downto 32*j)  :=  resize(r(i).length - j, 32);
            end loop;
            v.txMaster.tValid := '1';
            v.txMaster.tLast  := '1';
            v.length          := toSlv(0,as.length(i)'length);
            j := conv_integer(r(i).length);
            if j <= PGP3_AXIS_CONFIG_C.TDATA_BYTES_C/4 then
              v.txMaster.tKeep  := genTKeep(4*j);
              v.state           := IDLE_S;
            else
              v.txMaster.tLast := '0';
              v.txMaster.tKeep := genTKeep(PGP3_AXIS_CONFIG_C);
              v.length         := r(i).length - PGP3_AXIS_CONFIG_C.TDATA_BYTES_C/4;
              v.state          := SEND_S;
            end if;
            if r(i).event = '1' then
              v.event    := '0';
              v.count    := r(i).count + 1;
              v.txMaster.tData(31 downto 0) := resize(r(i).count,32);
            end if;
          end if;
        when USER_S =>
          if v.txMaster.tValid = '0' then
            v.txMaster.tValid := '1';
            v.txMaster.tData(DATALEN-1 downto 0) :=
              r(i).user(DATALEN-1 downto 0);
            v.user(TDET_USER_BITS_C-1 downto 0) :=
              toSlv(0,DATALEN) & r(i).user(TDET_USER_BITS_C-1 downto DATALEN);
            v.length := r(i).length - DATALEN;
            if r(i).length <= DATALEN then
              v.txMaster.tLast := '1';
              v.txMaster.tKeep := genTKeep(conv_integer(r(i).length)/8);
              v.state          := IDLE_S;
            else
              v.txMaster.tLast := '0';
              v.txMaster.tKeep := genTKeep(PGP3_AXIS_CONFIG_C);
            end if;
          end if;
        when others => null;
      end case;

      tdetAxisSlave  (i) <= v.axisSlave;
      tdetTimingRds  (i) <= r(i).timingMsgRd;
      tdetInhibitRds (i) <= r(i).inhibitCtRd;

      if tdetClkRst = '1' or as.clear(i) = '1' then
        v := REG_INIT_C;
      end if;

      rin(i) <= v;
    end loop;

    tdetAlmostFull <= as.aFull;
    
  end process;

  process (tdetClk) is
  begin
    if rising_edge(tdetClk) then
      for i in 0 to NUM_LANES_G-1 loop
        r(i) <= rin(i);
      end loop;
    end if;
  end process;

end mapping;
