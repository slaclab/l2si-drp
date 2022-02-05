-------------------------------------------------------------------------------
-- File       : DiagnBusFill.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2021-01-26
-- Last update: 2021-01-27
-------------------------------------------------------------------------------
-- Description:
--
--  Simulate diagnosticBus population from an application that processes a
--  fraction of the events.  The diagnosticBus.strobe signal should have the
--  same interval as the timingframe.strobe but with delay long enough to
--  includes the results of the algorithm when triggered and invalidate results
--  when not triggered.
--
--  Solve with a state machine that has two behaviors:
--  (1) prior to triggering the slow application for the first time, return
--  invalidated results upon timing frame strobe along with timing message;
--  (2) consequent to triggering, FIFO timing frame and results from application.
--  On each consequent timing frame strobe, if application data waiting, pull
--  application data and merge with timing message FIFO.  If not application
--  data waiting, invalidate results and merge with timing message FIFO.
--
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

library lcls_timing_core;
use lcls_timing_core.TimingPkg.all;

library amc_carrier_core;
use amc_carrier_core.AmcCarrierPkg.all;

library unisim;
use unisim.vcomponents.all;

entity DiagnBusFill is
   generic (
     TPD_G            : time             := 1 ns;
     NUM_VAR_G        : integer          := 31;
     MAX_DELAY_G      : integer          := 100 );
   port (
      ------------------------      
      --  Top Level Interfaces
      ------------------------
     timingClk       : in  sl;
     timingRst       : in  sl;
     timingBus       : in  TimingBusType;
     --
     diagnClk        : out sl;
     diagnRst        : out sl;
     diagnBus        : out DiagnosticBusType;
     --
     appClk          : in  sl;
     appRst          : in  sl;
     appTrig         : in  sl; -- application module trigger
     appTrigValid    : in  sl; -- apptrig valid strobe
     appDataValid    : in  sl; -- application module data valid strobe
     appData         : in  Slv32Array(NUM_VAR_G-1 downto 0);
     appSevr         : in  Slv2Array (NUM_VAR_G-1 downto 0);
     appFixed        : in  slv       (NUM_VAR_G-1 downto 0) );
end DiagnBusFill;

architecture mapping of DiagnBusFill is

  signal timingMessageValid : sl;
  signal timingMessage      : TimingMessageType;
  signal timingMessageSlv   : slv(TIMING_MESSAGE_BITS_C-1 downto 0);
  signal timingStrobe       : sl;
  
  type AppStateType is (INIT_S, WAIT_S, RUN_S);
  type RegType is record
    state    : AppStateType;
    rden     : sl;
    appValid : sl;
    appSevr  : Slv2Array (31 downto 0);
    appFixed : slv       (31 downto 0);
  end record;

  constant REG_INIT_C : RegType := (
    state    => INIT_S,
    rden     => '0',
    appValid => '0',
    appSevr  => (others=>"11"),
    appFixed => (others=>'1') );

  signal r    : RegType := REG_INIT_C;
  signal r_in : RegType;

  constant ADDR_WIDTH_C : positive := log2(MAX_DELAY_G);

begin

  diagnClk                     <= appClk;
  diagnRst                     <= appRst;
  diagnBus.strobe              <= r.rden;
  diagnBus.data(appData'range) <= appData;
  diagnBus.sevr                <= r.appSevr;
  diagnBus.fixed               <= r.appFixed;
  diagnBus.mpsIgnore           <= (others=>'1');
  diagnBus.timingMessage       <= timingMessage;
  
  U_MsgFifo : entity surf.FifoAsync
    generic map (
      FWFT_EN_G => true,
      DATA_WIDTH_G => TIMING_MESSAGE_BITS_C,
      ADDR_WIDTH_G => ADDR_WIDTH_C )
    port map (
      -- Asynchronous Reset
      rst           => timingRst,
      -- Write Ports (wr_clk domain)
      wr_clk        => timingClk,
      wr_en         => timingBus.strobe,
      din           => toSlv(timingBus.message),
      -- Read Ports (rd_clk domain)
      rd_clk        => appClk,
      rd_en         => r.rden,
      dout          => timingMessageSlv,
      valid         => timingMessageValid );

  timingMessage <= toTimingMessageType(timingMessageSlv);
  
  -- make sure timingStrobe trails timingMessageValid
  U_SyncStrobe : entity surf.SynchronizerOneShot
    generic map (
      RELEASE_DELAY_G => 10 )
    port map (
      clk     => appClk,
      dataIn  => timingBus.strobe,
      dataOut => timingStrobe );
    
  comb : process (r, appRst, appTrig, appTrigValid, appDataValid,
                  timingMessage, timingMessageValid, timingStrobe ) is
    variable v : RegType;
  begin
    v := r;

    v.rden := '0';
    
    case(r.state) is
      when INIT_S =>
        if appTrigValid='1' and appTrig='1' then
          v.state := WAIT_S;
        end if;
        if timingStrobe='1' then
          v.rden := timingMessageValid;
        end if;
      when WAIT_S =>
        if appDataValid='1' then
          v.state := RUN_S;
        end if;
      when RUN_S  =>
        if timingStrobe='1' then
          v.rden     := timingMessageValid;
        end if;
    end case;
  
    if appDataValid='1' then
      v.appValid := '1';
      v.appSevr (appSevr'range)  := appSevr;
      v.appFixed(appFixed'range) := appFixed;
    end if;
    if r.rden='1' then
      v.appValid := '0';
      v.appSevr  := (others=>"11");
      v.appFixed := (others=>'1');
    end if;

    if appRst = '1' then
      v := REG_INIT_C;
    end if;

    r_in <= v;
  end process comb;

  seq : process ( appClk ) is
  begin
    if rising_edge(appClk) then
      r <= r_in;
    end if;
  end process seq;

end mapping;
