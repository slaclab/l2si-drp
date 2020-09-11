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
  signal xpmStream   : XpmStreamType := XPM_STREAM_INIT_C;

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
   
  signal appLaneWriteMaster     : AxiLiteWriteMasterType := AXI_LITE_WRITE_MASTER_INIT_C;
  signal appLaneWriteSlave      : AxiLiteWriteSlaveType;
  signal appLaneReadMaster      : AxiLiteReadMasterType := AXI_LITE_READ_MASTER_INIT_C;
  signal appLaneReadSlave       : AxiLiteReadSlaveType := AXI_LITE_READ_SLAVE_INIT_C;

  signal appLaneIbSlave         : AxiStreamSlaveType := AXI_STREAM_SLAVE_INIT_C;
  signal appLaneObMasters       : AxiStreamQuadMasterType := (others=>AXI_STREAM_MASTER_INIT_C);

  --
  
   constant MIGTPCI_INDEX_C   : integer := 0;
   constant TDETSEM_INDEX_C   : integer := 1;
   constant TDETTIM_INDEX_C   : integer := 2;
   constant I2C_INDEX_C       : integer := 3;

   constant NUM_AXIL0_MASTERS_C : integer := 4;
   signal mAxil0ReadMasters  : AxiLiteReadMasterArray (NUM_AXIL0_MASTERS_C-1 downto 0) := (others=>AXI_LITE_READ_MASTER_INIT_C);
   signal mAxil0ReadSlaves   : AxiLiteReadSlaveArray  (NUM_AXIL0_MASTERS_C-1 downto 0) := (others=>AXI_LITE_READ_SLAVE_EMPTY_OK_C);
   signal mAxil0WriteMasters : AxiLiteWriteMasterArray(NUM_AXIL0_MASTERS_C-1 downto 0) := (others=>AXI_LITE_WRITE_MASTER_INIT_C);
   signal mAxil0WriteSlaves  : AxiLiteWriteSlaveArray (NUM_AXIL0_MASTERS_C-1 downto 0) := (others=>AXI_LITE_WRITE_SLAVE_EMPTY_OK_C);

   constant NUM_AXIL1_MASTERS_C : integer := 3;
   signal mAxil1ReadMasters  : AxiLiteReadMasterArray (NUM_AXIL1_MASTERS_C-1 downto 0) := (others=>AXI_LITE_READ_MASTER_INIT_C);
   signal mAxil1ReadSlaves   : AxiLiteReadSlaveArray  (NUM_AXIL1_MASTERS_C-1 downto 0) := (others=>AXI_LITE_READ_SLAVE_EMPTY_OK_C);
   signal mAxil1WriteMasters : AxiLiteWriteMasterArray(NUM_AXIL1_MASTERS_C-1 downto 0) := (others=>AXI_LITE_WRITE_MASTER_INIT_C);
   signal mAxil1WriteSlaves  : AxiLiteWriteSlaveArray (NUM_AXIL1_MASTERS_C-1 downto 0) := (others=>AXI_LITE_WRITE_SLAVE_EMPTY_OK_C);
   
   constant AXIL0_CROSSBAR_MASTERS_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL0_MASTERS_C-1 downto 0) := (
     0 => (baseAddr     => x"00800000",
           addrBits     => 21,
           connectivity => x"FFFF"),
     1 => (baseAddr     => x"00A00000",
           addrBits     => 21,
           connectivity => x"FFFF"),
     2 => (baseAddr     => x"00C00000",
           addrBits     => 21,
           connectivity => x"FFFF"),
     3 => (baseAddr     => x"00E00000",
           addrBits     => 21,
           connectivity => x"FFFF") );
   constant AXIL1_CROSSBAR_MASTERS_CONFIG_C : AxiLiteCrossbarMasterConfigArray(NUM_AXIL1_MASTERS_C-1 downto 0) := (
     0 => (baseAddr     => x"00800000",
           addrBits     => 21,
           connectivity => x"FFFF"),
     1 => (baseAddr     => x"00A00000",
           addrBits     => 21,
           connectivity => x"FFFF"),
     2 => (baseAddr     => x"00C00000",
           addrBits     => 21,
           connectivity => x"FFFF") );

   constant AXILT_CROSSBAR_MASTERS_CONFIG_C : AxiLiteCrossbarMasterConfigArray(0 downto 0) := (
     0 => AXIL0_CROSSBAR_MASTERS_CONFIG_C(TDETTIM_INDEX_C) );

   signal axilRegs : Slv32Array(3 downto 0);
   signal axilClks : slv(1 downto 0);
   signal axilRsts : slv(1 downto 0);
   signal axilReadMasters  : AxiLiteReadMasterArray (1 downto 0);
   signal axilReadSlaves   : AxiLiteReadSlaveArray  (1 downto 0);
   signal axilWriteMasters : AxiLiteWriteMasterArray(1 downto 0);
   signal axilWriteSlaves  : AxiLiteWriteSlaveArray (1 downto 0);

   signal ttimAxilReadMasters  : AxiLiteReadMasterArray (1 downto 0);
   signal ttimAxilReadSlaves   : AxiLiteReadSlaveArray  (1 downto 0);
   signal ttimAxilWriteMasters : AxiLiteWriteMasterArray(1 downto 0);
   signal ttimAxilWriteSlaves  : AxiLiteWriteSlaveArray (1 downto 0);

   signal ttimAxilReadMaster  : AxiLiteReadMasterType;
   signal ttimAxilReadSlave   : AxiLiteReadSlaveType;
   signal ttimAxilWriteMaster : AxiLiteWriteMasterType;
   signal ttimAxilWriteSlave  : AxiLiteWriteSlaveType;

begin

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

  axilClks(0) <= axiClk;
  axilRsts(0) <= axiRst;
  axilClks(1) <= not axiClk;
  axilRsts(1) <= axiRst;
    
  GEN_MASTER : for i in 0 to 1 generate
    U_AxiLiteTDet : entity work.AxiLiteWriteMasterSim
      generic map ( CMDS => ( (addr => x"00C00000", value => x"00000008"),
                              (addr => x"00C00004", value => x"10000000") ) )
      port map ( clk    => axilClks(i),
                 rst    => axilRsts(i),
                 master => axilWriteMasters(i),
                 slave  => axilWriteSlaves (i),
                 done   => open );
  end generate;
  
  U_AxilXbar0 : entity surf.AxiLiteCrossbar
    generic map ( NUM_SLAVE_SLOTS_G  => 1,
                  NUM_MASTER_SLOTS_G => AXIL0_CROSSBAR_MASTERS_CONFIG_C'length,
                  MASTERS_CONFIG_G   => AXIL0_CROSSBAR_MASTERS_CONFIG_C )
    port map    ( axiClk              => axilClks        (0),
                  axiClkRst           => axilRsts        (0),
                  sAxiWriteMasters(0) => axilWriteMasters(0),
                  sAxiWriteSlaves (0) => axilWriteSlaves (0),
                  sAxiReadMasters (0) => axilReadMasters (0),
                  sAxiReadSlaves  (0) => axilReadSlaves  (0),
                  mAxiWriteMasters    => mAxil0WriteMasters,
                  mAxiWriteSlaves     => mAxil0WriteSlaves ,
                  mAxiReadMasters     => mAxil0ReadMasters ,
                  mAxiReadSlaves      => mAxil0ReadSlaves  );

  U_AxilXbar1 : entity surf.AxiLiteCrossbar
    generic map ( NUM_SLAVE_SLOTS_G  => 1,
                  NUM_MASTER_SLOTS_G => AXIL1_CROSSBAR_MASTERS_CONFIG_C'length,
                  MASTERS_CONFIG_G   => AXIL1_CROSSBAR_MASTERS_CONFIG_C )
    port map    ( axiClk              => axilClks        (1),
                  axiClkRst           => axilRsts        (1),
                  sAxiWriteMasters(0) => axilWriteMasters(1),
                  sAxiWriteSlaves (0) => axilWriteSlaves (1),
                  sAxiReadMasters (0) => axilReadMasters (1),
                  sAxiReadSlaves  (0) => axilReadSlaves  (1),
                  mAxiWriteMasters    => mAxil1WriteMasters,
                  mAxiWriteSlaves     => mAxil1WriteSlaves ,
                  mAxiReadMasters     => mAxil1ReadMasters ,
                  mAxiReadSlaves      => mAxil1ReadSlaves  );

  ttimAxilReadMasters (0) <= mAxil0ReadMasters (TDETTIM_INDEX_C);
  ttimAxilWriteMasters(0) <= mAxil0WriteMasters(TDETTIM_INDEX_C);
  mAxil0ReadSlaves (TDETTIM_INDEX_C) <= ttimAxilReadSlaves (0);
  mAxil0WriteSlaves(TDETTIM_INDEX_C) <= ttimAxilWriteSlaves (0);

  U_AxilAsync : entity surf.AxiLiteAsync
    generic map ( TPD_G => 1 ns )
    port map ( sAxiClk         => axilClks(1),
               sAxiClkRst      => axilRsts(1),
               sAxiReadMaster  => mAxil1ReadMasters (TDETTIM_INDEX_C),
               sAxiReadSlave   => mAxil1ReadSlaves  (TDETTIM_INDEX_C),
               sAxiWriteMaster => mAxil1WriteMasters(TDETTIM_INDEX_C),
               sAxiWriteSlave  => mAxil1WriteSlaves (TDETTIM_INDEX_C),
               mAxiClk         => axilClks(0),
               mAxiClkRst      => axilRsts(0),
               mAxiReadMaster  => ttimAxilReadMasters (1),
               mAxiReadSlave   => ttimAxilReadSlaves  (1),
               mAxiWriteMaster => ttimAxilWriteMasters(1),
               mAxiWriteSlave  => ttimAxilWriteSlaves (1) );
  
  U_AxilXbarT : entity surf.AxiLiteCrossbar
    generic map ( NUM_SLAVE_SLOTS_G  => 2,
                  NUM_MASTER_SLOTS_G => 1,
                  MASTERS_CONFIG_G   => AXILT_CROSSBAR_MASTERS_CONFIG_C )
    port map    ( axiClk              => axilClks        (0),
                  axiClkRst           => axilRsts        (0),
                  sAxiWriteMasters    => ttimAxilWriteMasters,
                  sAxiWriteSlaves     => ttimAxilWriteSlaves ,
                  sAxiReadMasters     => ttimAxilReadMasters ,
                  sAxiReadSlaves      => ttimAxilReadSlaves  ,
                  mAxiWriteMasters(0) => ttimAxilWriteMaster,
                  mAxiWriteSlaves (0) => ttimAxilWriteSlave ,
                  mAxiReadMasters (0) => ttimAxilReadMaster ,
                  mAxiReadSlaves  (0) => ttimAxilReadSlave  );

  U_TTim : entity surf.AxiLiteRegs
   generic map (
      NUM_WRITE_REG_G  => 4,
      NUM_READ_REG_G   => 4 )
   port map (
      -- AXI-Lite Bus
      axiClk         => axilClks(0),
      axiClkRst      => axilRsts(0),
      axiReadMaster  => ttimAxilReadMaster,
      axiReadSlave   => ttimAxilReadSlave,
      axiWriteMaster => ttimAxilWriteMaster,
      axiWriteSlave  => ttimAxilWriteSlave,
      writeRegister  => axilRegs,
      readRegister   => axilRegs
      );

end architecture;
