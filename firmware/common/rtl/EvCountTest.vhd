------------------------------------------------------------------------------
-- File       : EvCountTest.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2017-03-06
-- Last update: 2019-04-05
-------------------------------------------------------------------------------
-- Description: Receives transfer requests representing data buffers pending
-- in local DRAM and moves data to CPU host memory over PCIe AXI interface.
-- Captures histograms of local DRAM buffer depth and PCIe target address FIFO
-- depth.  Needs an AxiStream to AXI channel to write histograms to host memory.
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
use surf.AxiDmaPkg.all;
use work.AppMigPkg.all;

entity EvCountTest is
   generic ( LANES_G : integer := 4 );
   port    ( -- Clock and reset
             axisClk          : in  sl;
             axisRst          : in  sl;
             axisMasters      : in  AxiStreamMasterArray(LANES_G-1 downto 0);
             axisSlaves       : in  AxiStreamSlaveArray (LANES_G-1 downto 0);
             debug            : out sl );
end EvCountTest;

architecture mapping of EvCountTest is

  type RegType is record
    -- Debug
    axisFirst      : Slv2Array           (LANES_G-1 downto 0);
    evCount        : Slv16Array          (LANES_G-1 downto 0);
    evCountDiff    : slv                 (16*LANES_G-1 downto 0);
  end record;

  constant REG_INIT_C : RegType := (
    axisFirst      => (others=>"01"),
    evCount        => (others=>(others=>'0')),
    evCountDiff    => (others=>'0') );

  signal r   : RegType := REG_INIT_C;
  signal rin : RegType;

  component ila_0
    port ( clk : in sl;
           probe0 : in slv(255 downto 0) );
  end component;
  
begin

  U_ILAA : ila_0
    port map ( clk                    => axisClk,
               probe0( 63 downto   0) => r.evCountDiff,
               probe0( 79 downto  64) => r.evCount(0),
               probe0( 95 downto  80) => r.evCount(1),
               probe0(111 downto  96) => r.evCount(2),
               probe0(127 downto 112) => r.evCount(3),
               probe0(255 downto 128) => (others=>'0') );

  comb : process ( axisRst, r, axisMasters, axisSlaves) is
    variable v       : RegType;
  begin
    v := r;
    
    for i in 0 to LANES_G-1 loop
      if (axisMasters(i).tValid = '1' and axisSlaves(i).tReady = '1') then
        v.axisFirst(i) := r.axisFirst(i)(0) & axisMasters(i).tLast;
        if r.axisFirst(i)(1) = '1' then
          v.evCount(i)  := axisMasters(i).tData(47 downto 32);
          v.evCountDiff(16*i+15 downto 16*i) := v.evCount(i) - r.evCount(i);
        end if;
      end if;
    end loop;
    
    if axisRst = '1' then
      v := REG_INIT_C;
    end if;

    rin <= v;

  end process comb;

  seq: process(axisClk) is
  begin
    if rising_edge(axisClk) then
      r <= rin;
    end if;
  end process seq;
      
 end mapping;



