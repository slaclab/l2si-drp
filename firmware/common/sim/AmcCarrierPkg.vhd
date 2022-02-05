-------------------------------------------------------------------------------
-- Company    : SLAC National Accelerator Laboratory
-------------------------------------------------------------------------------
-- Description: Common AMC Carrier Core VHDL package
-------------------------------------------------------------------------------
-- This file is part of 'LCLS2 Common Carrier Core'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'LCLS2 Common Carrier Core', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library surf;
use surf.StdRtlPkg.all;

library lcls_timing_core;
use lcls_timing_core.TimingPkg.all;

package AmcCarrierPkg is

   constant BSA_DIAGNOSTIC_OUTPUTS_C : integer := 31;
  
   type DiagnosticBusType is record
      strobe        : sl;
      data          : Slv32Array(31 downto 0);
      sevr          : Slv2Array (31 downto 0);  -- (0=NONE, 1=MINOR, 2=MAJOR, 3=INVALID)
      fixed         : slv (31 downto 0);        -- do not add/average (static)
      mpsIgnore     : slv (31 downto 0);        -- MPS ignores value
      timingMessage : TimingMessageType;
   end record;
   type DiagnosticBusArray is array (natural range <>) of DiagnosticBusType;
   constant DIAGNOSTIC_BUS_INIT_C : DiagnosticBusType := (
      strobe        => '0',
      data          => (others => (others => '0')),
      sevr          => (others => (others => '1')),
      fixed         => (others => '0'),
      mpsIgnore     => (others => '0'),
      timingMessage => TIMING_MESSAGE_INIT_C);

   constant DIAGNOSTIC_BUS_BITS_C : integer := 1 + 32*36 + TIMING_MESSAGE_BITS_C;

   function toSlv (b             : DiagnosticBusType) return slv;
   function toDiagnosticBus (vec : slv) return DiagnosticBusType;

end package AmcCarrierPkg;

package body AmcCarrierPkg is

   function toSlv (b : DiagnosticBusType) return slv is
      variable vector : slv(DIAGNOSTIC_BUS_BITS_C-1 downto 0) := (others => '0');
      variable i      : integer                               := 0;
   begin
      vector(TIMING_MESSAGE_BITS_C-1 downto 0) := toSlv(b.timingMessage);
      i                                        := TIMING_MESSAGE_BITS_C;
      for j in 0 to 31 loop
         assignSlv(i, vector, b.data (j));
         assignSlv(i, vector, b.sevr (j));
         assignSlv(i, vector, b.fixed (j));
         assignSlv(i, vector, b.mpsIgnore(j));
      end loop;
      assignSlv(i, vector, b.strobe);
      return vector;
   end function;

   function toDiagnosticBus (vec : slv) return DiagnosticBusType is
      variable b : DiagnosticBusType;
      variable i : integer := 0;
   begin
      b.timingMessage := toTimingMessageType(vec(TIMING_MESSAGE_BITS_C-1 downto 0));
      i               := TIMING_MESSAGE_BITS_C;
      for j in 0 to 31 loop
         assignRecord(i, vec, b.data (j));
         assignRecord(i, vec, b.sevr (j));
         assignRecord(i, vec, b.fixed (j));
         assignRecord(i, vec, b.mpsIgnore(j));
      end loop;
      assignRecord(i, vec, b.strobe);
      return b;
   end function;

end package body AmcCarrierPkg;
