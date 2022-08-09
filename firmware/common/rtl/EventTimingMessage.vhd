-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Converts eventTimingMessages into an AXI Stream bus
-------------------------------------------------------------------------------
-- This file is part of 'L2SI Core'. It is subject to
-- the license terms in the LICENSE.txt file found in the top-level directory
-- of this distribution and at:
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html.
-- No part of 'L2SI Core', including this file, may be
-- copied, modified, propagated, or distributed except according to the terms
-- contained in the LICENSE.txt file.
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

library surf;
use surf.StdRtlPkg.all;
use surf.AxiStreamPkg.all;

library lcls_timing_core;
use lcls_timing_core.TimingPkg.all;

entity EventTimingMessage is
   generic (
      TPD_G               : time                 := 1 ns;
      PIPE_STAGES_G       : natural              := 0;
      NUM_DETECTORS_G     : integer range 1 to 8 := 8;
      EVENT_AXIS_CONFIG_G : AxiStreamConfigType);
   port (
      -- Clock and Reset
      eventClk                 : in  sl;
      eventRst                 : in  sl;
      -- Input Streams
      eventTimingMessagesValid : in  slv(NUM_DETECTORS_G-1 downto 0);
      eventTimingMessages      : in  TimingMessageArray(NUM_DETECTORS_G-1 downto 0);
      eventTimingMessagesRd    : out slv(NUM_DETECTORS_G-1 downto 0);
      -- Output Streams
      eventTimingMsgMasters    : out AxiStreamMasterArray(NUM_DETECTORS_G-1 downto 0);
      eventTimingMsgSlaves     : in  AxiStreamSlaveArray(NUM_DETECTORS_G-1 downto 0));
end entity EventTimingMessage;

architecture mapping of EventTimingMessage is

   constant TIM_AXIS_CONFIG_C : AxiStreamConfigType := (
      TSTRB_EN_C    => false,
      TDATA_BYTES_C => 48,
      TDEST_BITS_C  => 0,
      TID_BITS_C    => 0,
      TKEEP_MODE_C  => TKEEP_NORMAL_C,
      TUSER_BITS_C  => 0,
      TUSER_MODE_C  => TUSER_NORMAL_C);

   --
   --  Format the data for software (psana) consumption
   --
   function toSlvFormatted(msg : TimingMessageType) return slv is
     variable v : slv(967 downto 0) := (others=>'0');
     variable i : integer := 0;
   begin
     assignSlv(i, v, msg.pulseId);                             -- [63:0]
     assignSlv(i, v, msg.timeStamp);                           -- [127:64]
     for j in msg.fixedRates'range loop                        -- [207:128]
       assignSlv(i, v, "0000000" & msg.fixedRates(j));
     end loop;
     for j in msg.acRates'range loop                           -- [255:208]
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
     return v;
   end function;

   constant TDATA_BYTES_C : integer := EVENT_AXIS_CONFIG_G.TDATA_BYTES_C;
   constant TDATA_LINES_C : integer := wordCount( toSlvFormatted(TIMING_MESSAGE_INIT_C)'length, EVENT_AXIS_CONFIG_G.TDATA_BYTES_C );
     
   type RegType is record
     length      : slv(bitSize(TDATA_LINES_C)-1 downto 0);
     sof         : sl;
     user        : slv(TDATA_LINES_C*8-1 downto 0);
     axisSlave   : AxiStreamSlaveType;
     axisMaster  : AxiStreamMasterType;
   end record;

   constant REG_INIT_C : RegType := (
     length      => (others=>'0'),
     sof         => '0',
     user        => (others=>'0'),
     axisSlave   => AXI_STREAM_SLAVE_INIT_C,
     axisMaster  => axiStreamMasterInit(EVENT_AXIS_CONFIG_G) );

   type RegArray is array(natural range<>) of RegType;

   signal r   : RegArray(NUM_DETECTORS_G-1 downto 0) := (others=>REG_INIT_C);
   signal rin : RegArray(NUM_DETECTORS_G-1 downto 0);
   
begin

   comb : process ( r, eventRst,eventTimingMessagesValid, eventTimingMessages, eventTimingMsgSlaves ) is
     variable v : RegType;
   begin
     for i in NUM_DETECTORS_G-1 downto 0 loop
       v := r(i);
       v.axisSlave.tReady := '0';

       if eventTimingMsgSlaves(i).tReady = '1' then
         v.axisMaster.tValid := '0';
       end if;

       if v.axisMaster.tValid = '0' then
         if r(i).length = 0 then
           if eventTimingMessagesValid(i) = '1' then
             v.length := toSlv(TDATA_LINES_C,r(i).length'length);
             v.user(toSlvFormatted(TIMING_MESSAGE_INIT_C)'range) := toSlvFormatted(eventTimingMessages(i));
             v.sof := '1';
             v.axisSlave.tReady := '1';
           end if;
         else
           v.axisMaster.tValid := '1';
           if r(i).length = toSlv(1,r(i).length'length) then
             v.axisMaster.tLast := '1';
           else
             v.axisMaster.tLast := '0';
           end if;
           v.axisMaster.tData(TDATA_BYTES_C*8-1 downto 0) :=
             r(i).user(TDATA_BYTES_C*8-1 downto 0);
           ssiSetUserSof(EVENT_AXIS_CONFIG_G, v.axisMaster, r(i).sof);
           v.length := r(i).length-1;
           v.sof    := '0';
           v.user := toSlv(0,TDATA_BYTES_C*8) & r(i).user(r(i).user'length downto TDATA_BYTES_C*8);
         end if;
       end if;

       if eventRst = '1' then
         v := REG_INIT_C;
       end if;
       
       r_in(i) <= v;

       eventTimingMsgMasters(i) <= r(i).axisMaster;
       eventTimingMessagesRd(i) <= r_in(i).axisSlave.tReady;
     end loop;

   end process comb;

   seq : process ( eventClk ) is
   begin
     if rising_edge(eventClk) then
       for i in NUM_DETECTORS_G-1 downto 0 loop
         r(i) <= r_in(i); 
       end loop;
     end if;
   end process seq;
   
end mapping;
