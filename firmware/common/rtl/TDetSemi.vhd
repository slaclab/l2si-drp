-------------------------------------------------------------------------------
-- File       : TDetSemi.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-10-26
-- Last update: 2020-02-11
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
    tdetTimingMsgs  : in  TimingMessageArray  (NUM_LANES_G-1 downto 0);
    tdetAxisMaster  : in  AxiStreamMasterArray(NUM_LANES_G-1 downto 0);
    tdetAxisSlave   : out AxiStreamSlaveArray (NUM_LANES_G-1 downto 0);
    tdetAlmostFull  : out slv                 (NUM_LANES_G-1 downto 0);
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
    clear     : sl;
    length    : slv(22 downto 0);
    axilWriteSlave  : AxiLiteWriteSlaveType;
    axilReadSlave   : AxiLiteReadSlaveType;
  end record;
  constant AXI_REG_INIT_C : AxiRegType := (
    enable    => (others=>'0'),
    aFull     => (others=>'0'),
    clear     => '0',
    length    => (others=>'0'),
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
    userrd      : sl;
    user        : slv(TDET_USER_BITS_C-1 downto 0);
    axisSlave  : AxiStreamSlaveType;
    txMaster    : AxiStreamMasterType;
  end record;

  constant REG_INIT_C : RegType := (
    state       => IDLE_S,
    length      => (others=>'0'),
    count       => (others=>'0'),
    event       => '0',
    userrd      => '0',
    user        => (others=>'0'),
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
    axiSlaveRegister( ep, x"00", 3, v.clear  );
    axiSlaveRegister( ep, x"00", 4, v.length );
    axiSlaveRegister( ep, x"00",28, v.enable );

    axiSlaveRegisterR( ep, x"0c", 0, modPrsL);

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
  U_ClearS : entity surf.Synchronizer
    port map ( clk => tdetClk, dataIn => a.clear, dataOut => as.clear );
  U_LengthS : entity surf.SynchronizerVector
    generic map ( WIDTH_G => a.length'length )
    port map ( clk => tdetClk, dataIn => a.length, dataOut => as.length );
  U_EnableS : entity surf.SynchronizerVector
    generic map ( WIDTH_G => a.enable'length )
    port map ( clk => tdetClk, dataIn => a.enable, dataOut => as.enable );
  
--  comb : process ( r, tdetClkRst, tdetEventMaster, tdetTransMaster, strigBus, as, dmaIbSlaves ) is
  comb : process ( r, tdetClkRst, tdetAxisMaster, tdetTimingMsgs, as, dmaIbSlaves ) is
    variable v : RegType;
    variable i,j : integer;
    constant DATALEN : integer := PGP3_AXIS_CONFIG_C.TDATA_BYTES_C*8;
  begin
    for i in 0 to NUM_LANES_G-1 loop
      v := r(i);
      v.axisSlave.tReady  := '0';
      v.userrd            := '0';
      
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
              if as.length = 0 then
                -- Workaround for small payload DMA problem;  pad to 256 bytes
                v.length          := toSlv(2048,r(i).length'length);
                -- v.length          := resize(strigBus(i).userlen,r(i).length'length);
                v.user(TIMING_MESSAGE_BITS_NO_BSA_C-1 downto 0)
                  := toSlvNoBsa(tdetTimingMsgs(i));
                v.userrd          := '1';  -- now signaled by v.axisSlave
                v.state           := USER_S;
              else
                v.length          := as.length;
                v.state           := SEND_S;
              end if;
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
            v.length          := toSlv(0,as.length'length);
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

      tdetAxisSlave (i)         <= v.axisSlave;

      if tdetClkRst = '1' or as.clear = '1' then
        v := REG_INIT_C;
      end if;

      rin(i) <= v;

      tdetAlmostFull <= as.aFull;
    end loop;
    
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
