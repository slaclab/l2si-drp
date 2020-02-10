-------------------------------------------------------------------------------
-- File       : AxiLiteMasterProxy.vhd
-- Company    : SLAC National Accelerator Laboratory
-- Created    : 2015-07-08
-- Last update: 2019-04-23
-------------------------------------------------------------------------------
-- Description: AXI-Lite I2C Register Master
-------------------------------------------------------------------------------
-- This file is part of 'SLAC Firmware Standard Library'.
-- It is subject to the license terms in the LICENSE.txt file found in the 
-- top-level directory of this distribution and at: 
--    https://confluence.slac.stanford.edu/display/ppareg/LICENSE.html. 
-- No part of 'SLAC Firmware Standard Library', including this file, 
-- may be copied, modified, propagated, or distributed except according to 
-- the terms contained in the LICENSE.txt file.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;


library surf;
use surf.StdRtlPkg.all;
use surf.AxiLitePkg.all;

library unisim;
use unisim.vcomponents.all;

entity AxiLiteMasterProxy is
   port (
      -- Clocks and Resets
      axiClk          : in    sl;
      axiRst          : in    sl;
      -- AXI-Lite Register Interface
      sAxiReadMaster  : in    AxiLiteReadMasterType;
      sAxiReadSlave   : out   AxiLiteReadSlaveType;
      sAxiWriteMaster : in    AxiLiteWriteMasterType;
      sAxiWriteSlave  : out   AxiLiteWriteSlaveType;
      -- AXI-Lite Register Interface
      mAxiReadMaster  : out   AxiLiteReadMasterType;
      mAxiReadSlave   : in    AxiLiteReadSlaveType;
      mAxiWriteMaster : out   AxiLiteWriteMasterType;
      mAxiWriteSlave  : in    AxiLiteWriteSlaveType );
end AxiLiteMasterProxy;

architecture mapping of AxiLiteMasterProxy is

   type StateType is ( READY_S, ACK_S );
   
   type RegType is record
      sAxiWriteSlave  : AxiLiteWriteSlaveType;
      sAxiReadSlave   : AxiLiteReadSlaveType;
      req             : AxiLiteReqType;
      state           : StateType;
      rnw             : sl;
      done            : sl;
      resp            : slv(1 downto 0);
      addr            : slv(31 downto 0);
      data            : slv(31 downto 0);
   end record;
   constant REG_INIT_C : RegType := (
      sAxiWriteSlave  => AXI_LITE_WRITE_SLAVE_INIT_C,
      sAxiReadSlave   => AXI_LITE_READ_SLAVE_INIT_C,
      req             => AXI_LITE_REQ_INIT_C,
      state           => READY_S,
      rnw             => '0',
      done            => '1',
      resp            => "00",
      addr            => (others=>'0'),
      data            => (others=>'0') );

   signal r   : RegType := REG_INIT_C;
   signal rin : RegType;

   signal ack : AxiLiteAckType;

begin

   process(ack, axiRst, r, sAxiReadMaster, sAxiWriteMaster) is
      variable v      : RegType;
      variable axilEp : AxiLiteEndpointType;
      variable newCmd : sl;
   begin
      -- Latch the current value
      v := r;

      ------------------------      
      -- AXI-Lite Transactions
      ------------------------ 

      -- Determine the transaction type
      axiSlaveWaitTxn(axilEp, sAxiWriteMaster, sAxiReadMaster, v.sAxiWriteSlave, v.sAxiReadSlave);

      axiSlaveRegister (axilEp, toSlv( 0, 9), 0, v.rnw);
      axiSlaveRegisterR(axilEp, toSlv( 4, 9), 0, r.done);
      axiSlaveRegisterR(axilEp, toSlv( 4, 9), 1, r.resp);
      axiSlaveRegister (axilEp, toSlv( 8, 9), 0, v.addr);
      axiSlaveRegister (axilEp, toSlv(12, 9), 0, v.data);
      newCmd := '0';
      axiWrDetect     (axilEp, toSlv(0, 9), newcmd);
      
      -- Close out the transaction
      axiSlaveDefault(axilEp, v.sAxiWriteSlave, v.sAxiReadSlave, AXI_RESP_OK_C);

      -- State Machine
      case r.state is
         ----------------------------------------------------------------------
         when READY_S =>
            if (newCmd = '1') then
               -- Start the master AXI-Lite transaction
               v.req.request := '1';
               v.req.rnw     := v.rnw;
               v.req.address := r.addr;
               v.req.wrData  := r.data;
               v.done        := '0';
               -- Next state
               v.state       := ACK_S;
            end if;
         ----------------------------------------------------------------------
         when ACK_S =>
            -- AXI-Lite transaction handshaking
            if (ack.done = '1') then
               v.req.request := '0';
               v.done        := '1';
               v.data        := ack.rdData;
               v.resp        := ack.resp;
               -- Next state      
               v.state := READY_S;
            end if;
      end case;

      -- Reset
      if (axiRst = '1') then
         v := REG_INIT_C;
      end if;

      -- Register the variable for next clock cycle
      rin <= v;

      -- Outputs 
      sAxiReadSlave  <= r.sAxiReadSlave;
      sAxiWriteSlave <= r.sAxiWriteSlave;

   end process comb;

   seq : process (axiClk) is
   begin
      if rising_edge(axiClk) then
         r <= rin;
      end if;
   end process seq;

   U_AxiLiteMaster : entity surf.AxiLiteMaster
      port map (
         req             => r.req,
         ack             => ack,
         axilClk         => axiClk,
         axilRst         => axiRst,
         axilWriteMaster => mAxiWriteMaster,
         axilWriteSlave  => mAxiWriteSlave,
         axilReadMaster  => mAxiReadMaster,
         axilReadSlave   => mAxiReadSlave);

end mapping;
