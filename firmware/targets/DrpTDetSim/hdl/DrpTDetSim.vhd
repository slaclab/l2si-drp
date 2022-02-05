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

library work;
use work.AmcCarrierPkg.all;

library unisim;
use unisim.vcomponents.all;

entity DrpTDetSim is
end DrpTDetSim;

architecture top_level_app of DrpTDetSim is

  signal axiClk, axiRst, axilRst : sl;
  signal axisClk, axisRst    : sl;
  signal sysClk, sysRst : sl;

  --  TPG, XPM simulation
  signal timingClk   : sl;
  signal timingRst   : sl;
  signal timingBus   : TimingBusType := TIMING_BUS_INIT_C;
  signal timingMessage : TimingMessageType;
  signal timingMessageSlv : slv(TIMING_MESSAGE_BITS_C-1 downto 0);
  signal timingRx    : TimingRxType := TIMING_RX_INIT_C;

  signal tpgConfig   : TPGConfigType := TPG_CONFIG_INIT_C;

  signal appTrig      : sl;  -- axisClk
  signal appTrigI     : sl;  -- timingClk
  signal appTrigQ     : sl;  -- intermediate
  signal appDataValid : sl;
  signal appData      : Slv32Array(4 downto 0);
  signal appPulseId   : slv(15 downto 0);

  signal diagnBus     : DiagnosticBusType;
  signal diagnClk     : sl;
  signal diagnRst     : sl;
begin

  tpgConfig.pulseIdWrEn <= '0';
  
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
  timingRst <= axisRst;

  U_TPG : entity lcls_timing_core.TPGMini
    port map (
      configI => tpgConfig,
      txClk   => timingClk,
      txRst   => timingRst,
      txRdy   => '1',
      txData  => timingRx.data,
      txDataK => timingRx.dataK );

  timingBus.stream  <= TIMING_STREAM_INIT_C;
  timingBus.modesel <= '1';
  U_TimingRx : entity lcls_timing_core.TimingFrameRx
    port map (
      rxClk   => timingClk,
      rxRst   => timingRst,
      rxData  => timingRx,
      messageDelay        => (others=>'0'),
      messageDelayRst     => '0',
      timingMessage       => timingMessage,
      timingMessageStrobe => timingBus.strobe,
      timingMessageValid  => timingBus.valid );

  U_Reg : entity surf.RegisterVector
    generic map ( WIDTH_G => timingMessageSlv'length )
    port map ( clk   => timingClk,
               en    => timingBus.strobe,
               sig_i => toSlv(timingMessage),
               reg_o => timingMessageSlv );

  timingBus.message <= toTimingMessageType(timingMessageSlv);
  
  U_DUT : entity work.DiagnBusFill
    generic map ( NUM_VAR_G => appData'length )
    port map (
      timingClk => timingClk,
      timingRst => timingRst,
      timingBus => timingBus,
      diagnClk  => diagnClk,
      diagnRst  => diagnRst,
      diagnBus  => diagnBus,
      appClk        => axisClk,
      appRst        => axisRst,
      appTrig       => appTrig,
      appTrigValid  => appTrig,
      appDataValid  => appDataValid,
      appData       => appData,
      appSevr       => (others=>"00"),
      appFixed      => (others=>'0') );

  U_AppFifo : entity surf.FifoAsync
    generic map (
      FWFT_EN_G    => true,
      DATA_WIDTH_G => 16,
      ADDR_WIDTH_G => 4 )
    port map (
       -- Asynchronous Reset
      rst           => timingRst,
      -- Write Ports (wr_clk domain)
      wr_clk        => timingClk,
      wr_en         => appTrigI,
      din           => timingBus.message.pulseId(15 downto 0),
      -- Read Ports (rd_clk domain)
      rd_clk        => axisClk,
      rd_en         => appDataValid,
      dout          => appPulseId );

  appTrigI <= timingBus.message.fixedRates(1) and timingBus.strobe;

  process ( timingClk ) is
  begin
    if rising_edge(timingClk) then
      appTrigQ <= appTrigI;
    end if;
  end process;
  
  U_AppValid : entity surf.SynchronizerOneShot
    port map ( clk     => axisClk,
               dataIn  => appTrigQ,
               dataOut => appTrig );

  U_AppDelay : entity surf.SlvDelayFifo
    generic map ( DATA_WIDTH_G => 1,
                  DELAY_BITS_G => 12 )
    port map ( clk         => axisClk,
               rst         => axisRst,
               delay       => toSlv(1000,12),
               inputData   => "1",
               inputValid  => appTrig,
               outputValid => appDataValid );

  GEN_APP : for i in 0 to 4 generate
    appData(i) <= toSlv(i,16) & appPulseId;
  end generate;

  validate : process ( diagnBus ) is
    variable i : integer;
  begin
    if diagnBus.strobe = '1' then
      for i in 0 to 30 loop
        if diagnBus.timingMessage.fixedRates(1)='0' or i>4 then
          assert (diagnBus.sevr(i)="11") report "validation failed for non-app";
        else
          assert (diagnBus.sevr(i)="00") report "sevr failed";
          assert (diagnBus.fixed(i)='0') report "fixed failed";
          assert (diagnBus.data(i)(31 downto 16)=toSlv(i,16)) report "index failed";
          assert (diagnBus.data(i)(15 downto 0)=diagnBus.timingMessage.pulseId(15 downto 0)) report "data pid failed";
        end if;
      end loop;
    end if;
  end process;
            
end architecture;
