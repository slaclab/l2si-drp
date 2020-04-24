library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;


library surf;
use surf.StdRtlPkg.all;
use surf.AxiPkg.all;
use surf.AxiLitePkg.all;
use surf.AxiStreamPkg.all;

library l2si_core;
use l2si_core.L2SiPkg.all;
use l2si_core.XpmMiniPkg.all;
use l2si_core.XpmPkg.all;

library lcls_timing_core;
use lcls_timing_core.TPGPkg.all;
use lcls_timing_core.TimingPkg.all;

library unisim;
use unisim.vcomponents.all;

entity DrpTDetSim is
end DrpTDetSim;

architecture top_level_app of DrpTDetSim is

  signal axiClk, axiRst, axilRst : sl;
  signal axilWriteMaster     : AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
  signal axilWriteSlave      : AxiLiteWriteSlaveType;
  signal axilReadMaster      : AxiLiteReadMasterType := AXI_LITE_READ_MASTER_INIT_C;
  signal axilReadSlave       : AxiLiteReadSlaveType := AXI_LITE_READ_SLAVE_INIT_C;
  signal tdetAxilWriteMaster     : AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
  signal tdetAxilWriteSlave      : AxiLiteWriteSlaveType;
  signal tdetAxilReadMaster      : AxiLiteReadMasterType := AXI_LITE_READ_MASTER_INIT_C;
  signal tdetAxilReadSlave       : AxiLiteReadSlaveType := AXI_LITE_READ_SLAVE_INIT_C;
  signal axilDone : sl;
  
  signal axisClk, axisRst    : sl;
  
  constant NDET_C : integer := 4;
  signal tdetClk    : sl;
  signal tdetRst    : sl;
  signal timingTrig : TriggerEventDataArray(NDET_C-1 downto 0);
  signal tdetAxisM : AxiStreamMasterArray (NDET_C-1 downto 0);
  signal tdetAxisS : AxiStreamSlaveArray  (NDET_C-1 downto 0) := (others=>AXI_STREAM_SLAVE_FORCE_C);
  signal tdetTimingMsgs : TimingMessageArray(NDET_C-1 downto 0);
  
  signal sysClk, sysRst : sl;

  --  TPG, XPM simulation
  signal timingClk   : sl;
  signal timingRst   : sl;
  signal timingBus   : TimingBusType;
  signal tpgStatus   : TPGStatusType;
  signal tpgConfig   : TPGConfigType := TPG_CONFIG_INIT_C;
  signal tpgStream   : TimingSerialType;
  signal tpgAdvance  : sl;
  signal tpgFiducial : sl;

  signal xpmStatus   : XpmMiniStatusType;
  signal xpmConfig   : XpmMiniConfigType := XPM_MINI_CONFIG_INIT_C;
  signal xpmStream   : XpmMiniStreamType := XPM_MINI_STREAM_INIT_C;

  signal dsTx        : TimingPhyType := TIMING_PHY_INIT_C;
  signal fbTx        : TimingPhyType := TIMING_PHY_INIT_C;
  signal gtRxStatus  : TimingPhyStatusType := TIMING_PHY_STATUS_INIT_C;

  signal tdetAlmostFull : slv(NDET_C-1 downto 0);
  signal hwClks         : slv(NDET_C-1 downto 0);
  signal hwRsts         : slv(NDET_C-1 downto 0);
  signal hwIbAlmostFull : slv(NDET_C-1 downto 0) := (others=>'0');
  signal hwIbFull       : slv(NDET_C-1 downto 0) := (others=>'0');
  signal hwObMasters    : AxiStreamMasterArray(NDET_C-1 downto 0) := (others=>AXI_STREAM_MASTER_INIT_C);
  signal hwObSlaves     : AxiStreamSlaveArray (NDET_C-1 downto 0);
  signal hwIbMasters    : AxiStreamMasterArray(NDET_C-1 downto 0);
  signal hwIbSlaves     : AxiStreamSlaveArray (NDET_C-1 downto 0) := (others=>AXI_STREAM_SLAVE_FORCE_C);

  constant TDET_AXIS_CONFIG_C : AxiStreamConfigType := (
     TSTRB_EN_C    => false,
     TDATA_BYTES_C => 32,
     TDEST_BITS_C  => 1,
     TID_BITS_C    => 0,
     TKEEP_MODE_C  => TKEEP_NORMAL_C,
     TUSER_BITS_C  => 2,
     TUSER_MODE_C  => TUSER_NORMAL_C );
   
  
begin

  gtRxStatus.resetDone <= '1';

  tpgConfig.pulseIdWrEn <= '0';
  
  process is
  begin
    xpmConfig.partition.l0Select.reset   <= '1';
    wait for 1 us;
    xpmConfig.partition.l0Select.reset   <= '0';
    xpmConfig.partition.pipeline.depth_clks <= toSlv(0,16);
    xpmConfig.partition.pipeline.depth_fids <= toSlv(90,8);
    for i in xpmConfig.dsLink'range loop
      xpmConfig.dsLink(i).txReset <= '1';
    end loop;
    wait for 1 us;
    for i in xpmConfig.dsLink'range loop
      xpmConfig.dsLink(i).txReset <= '0';
    end loop;
    wait for 10 us;
    xpmConfig.partition.l0Select.enabled <= '1';
    xpmConfig.partition.l0Select.rateSel <= x"0000"; -- 1MHz
    xpmConfig.partition.l0Select.destSel <= x"8000"; -- DontCare
    for i in 0 to 7 loop
      wait for 20 us;
      xpmConfig.partition.message.header <= toSlv(i,8);
      wait until axiClk = '0';
      xpmConfig.partition.message.insert <= '1';
      wait until axiClk = '1';
      wait until axiClk = '0';
      xpmConfig.partition.message.insert <= '0';
    end loop;
    wait;
  end process;
  
  U_TPG : entity lcls_timing_core.TPGMini
    generic map (
      NARRAYSBSA     => 1,
      STREAM_INTF    => true )
    port map (
      -- Register Interface
      statusO        => tpgStatus,
      configI        => tpgConfig,
      -- TPG Interface
      txClk          => timingClk,
      txRst          => timingRst,
      txRdy          => '1',
      streams    (0) => tpgStream,
      advance    (0) => tpgAdvance,
      fiducial       => tpgFiducial );

  xpmStream.fiducial   <= tpgFiducial;
  xpmStream.advance(0) <= tpgAdvance;
  xpmStream.streams(0) <= tpgStream;

  tpgAdvance <= tpgStream.ready;
  --process (timingClk)
  --begin
  --  if rising_edge(timingClk) then
  --    tpgAdvance <= tpgStream.ready;
  --  end if;
  --end process;
  
  U_Xpm : entity l2si_core.XpmMini
    port map ( regclk       => axiClk,
               regrst       => axiRst,
               update       => '0',
               config       => xpmConfig,
               status       => xpmStatus,
               dsRxClk  (0) => timingClk,
               dsRxRst  (0) => timingRst,
               dsRx     (0) => TIMING_RX_INIT_C,
               dsTx     (0) => dsTx,
               timingClk    => timingClk,
               timingRst    => timingRst,
               timingStream => xpmStream );

   TimingCore_1 : entity lcls_timing_core.TimingCore
     generic map ( CLKSEL_MODE_G     => "LCLSII",
                   USE_TPGMINI_G     => false,
                   ASYNC_G           => true )
     port map (
         gtTxUsrClk      => timingClk,
         gtTxUsrRst      => timingRst,
         gtRxRecClk      => timingClk,
         gtRxData        => dsTx.data,
         gtRxDataK       => dsTx.dataK,
         gtRxDispErr     => "00",
         gtRxDecErr      => "00",
         gtRxControl     => open,
         gtRxStatus      => gtRxStatus,
         gtLoopback      => open,
         appTimingClk    => timingClk,
         appTimingRst    => timingRst,
         appTimingBus    => timingBus,
         tpgMiniTimingPhy=> open, -- TPGMINI
         axilClk         => axiClk,
         axilRst         => axiRst,
         axilReadMaster  => AXI_LITE_READ_MASTER_INIT_C,
         axilReadSlave   => open,
         axilWriteMaster => AXI_LITE_WRITE_MASTER_INIT_C,
         axilWriteSlave  => open );

   U_TEM : entity l2si_core.TriggerEventManager
      generic map (
        NUM_DETECTORS_G                => NDET_C,
        AXIL_BASE_ADDR_G               => x"00000000",
        EVENT_AXIS_CONFIG_G            => TDET_AXIS_CONFIG_C,
        TRIGGER_CLK_IS_TIMING_RX_CLK_G => true )
      port map (
         timingRxClk      => timingClk,
         timingRxRst      => timingRst,
         timingBus        => timingBus,
         timingTxClk      => timingClk,
         timingTxRst      => timingRst,
         timingTxPhy      => fbTx,
         triggerClk       => timingClk,
         triggerRst       => timingRst,
         triggerData      => timingTrig,
         eventClk         => tdetClk,
         eventRst         => tdetRst,
         eventTimingMessages => tdetTimingMsgs,
         eventAxisMasters => tdetAxisM,
         eventAxisSlaves  => tdetAxisS,
         eventAxisCtrl    => (others => AXI_STREAM_CTRL_UNUSED_C),
         axilClk          => axiClk,
         axilRst          => axiRst,
         axilReadMaster   => axilReadMaster,
         axilReadSlave    => axilReadSlave,
         axilWriteMaster  => axilWriteMaster,
         axilWriteSlave   => axilWriteSlave );

     -- tdetStatus
     -- tdetTiming
    U_Hw : entity work.TDetSemi
      port map (
        ------------------------      
        --  Top Level Interfaces
        ------------------------         
        -- AXI-Lite Interface (axilClk domain)
        axilClk         => axiClk,
        axilRst         => axiRst,
        axilReadMaster  => tdetAxilReadMaster,
        axilReadSlave   => tdetAxilReadSlave ,
        axilWriteMaster => tdetAxilWriteMaster,
        axilWriteSlave  => tdetAxilWriteSlave ,
        -- DMA Interface (dmaClk domain)
        dmaClks         => hwClks        ,
        dmaRsts         => hwRsts        ,
        dmaObMasters    => hwObMasters   ,
        dmaObSlaves     => hwObSlaves    ,
        dmaIbMasters    => hwIbMasters   ,
        dmaIbSlaves     => hwIbSlaves    ,
        dmaIbAlmostFull => hwIbAlmostFull,
        dmaIbFull       => hwIbFull      ,
        ------------------
        --  TDET Ports
        ------------------       
        tdetClk         => tdetClk,
        tdetClkRst      => tdetRst,
        tdetAlmostFull  => tdetAlmostFull,
        tdetTimingMsgs  => tdetTimingMsgs,
        tdetAxisMaster  => tdetAxisM,
        tdetAxisSlave   => tdetAxisS,
        modPrsL         => '0' );
  
  process is
  begin
    timingClk <= '1';
    wait for 2.7 ns;
    timingClk <= '0';
    wait for 2.7 ns;
  end process;

  process is
  begin
    sysClk <= '1';
    wait for 2.0 ns;
    sysClk <= '0';
    wait for 2.0 ns;
  end process;
  
  process is
  begin
    axiClk <= '1';
    wait for 2.5 ns;
    axiClk <= '0';
    wait for 2.5 ns;
  end process;

  process is
  begin
    axiRst <= '1';
    axilRst <= '1';
    wait for 200 ns;
    axiRst <= '0';
    wait for 200 ns;
    axilRst <= '0';
    wait;
  end process;

  process is
  begin
    axisClk <= '1';
    wait for 3.2 ns;
    axisClk <= '0';
    wait for 3.2 ns;
  end process;

  axisRst <= axiRst;
  sysRst  <= axiRst;

  tdetClk <= axisClk;
  tdetRst <= axisRst;
  timingRst <= axisRst;

  U_AxiLite : entity work.AxiLiteWriteMasterSim
    generic map ( CMDS => ( (addr => x"00000020", value => x"0a0b0c0d"),
                            (addr => x"00000104", value => x"00000000"),
                            (addr => x"00000108", value => x"00000010"),
                            (addr => x"0000010C", value => x"00000000"),
                            (addr => x"00000100", value => x"00000003") ) )
    port map ( clk    => axiClk,
               rst    => axilRst,
               master => axilWriteMaster,
               slave  => axilWriteSlave,
               done   => axilDone );

  U_AxiLiteTDet : entity work.AxiLiteWriteMasterSim
    generic map ( CMDS => ( (addr => x"00000000", value => x"00000008"),
                            (addr => x"00000000", value => x"10000000") ) )
    port map ( clk    => axiClk,
               rst    => axiRst,
               master => tdetAxilWriteMaster,
               slave  => tdetAxilWriteSlave,
               done   => open );

  U_Record : entity work.AxiStreamRecord
    generic map ( filename => "tdet.xtc" )
    port map ( axisClk    => hwClks     (0),
               axisMaster => hwIbMasters(0),
               axisSlave  => hwIbSlaves (0) );
  
end architecture;
