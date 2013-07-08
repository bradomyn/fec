--! @file xc_fec.vhd
--! @brief Wrapper for the FEC Forward Error Correction
--! @author Cesar Praods <c.prados@gsi.de>
--! @bug No know bugs.
--!
--! Copyright (C) 2011-2012 GSI Helmholtz Centre for Heavy Ion Research GmbH 
--!
--! Register map (all 4-byte values):
--!----------------------------------------------------------------------------
--! 0x00 RW: Ctrl Register
--!      0x00 :  Bit 0 FEC disable/enable (0/1)
--!              Bit 1 Bit Error Code disable/enable (0/1)
--!              Bit 2 Packet Error Code disable/enable (0/1)
--!              Bit 3 Packet Injector, debuging 
--!      0x01 :  Bit Error Code Algorithm
--!      0x02 :  Packet Error Code Algorith
--!      0x03 :  Reseverved
--! 0x01 R: Status Register
--!----------------------------------------------------------------------------
--! Fabric Interface
--!wr_core                     FEC                etherbone
--!=====================================================================================
--!wr_core_* <----->  fec_wr_*  |  fec_eb_* <-----> eb_*
--!----------------------------------------------------------------------------
--! This library is free software; you can redistribute it and/or
--! modify it under the terms of the GNU Lesser General Public
--! License as published by the Free Software Foundation; either
--! version 3 of the License, or (at your option) any later version.
--!
--! This library is distributed in the hope that it will be useful,
--! but WITHOUT ANY WARRANTY; without even the implied warranty of
--! MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
--! Lesser General Public License for more details.
--!  
---------------------------------------------------------------------------------

--! Standard library
library IEEE;
--! Standard packages    
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;

library work;
use work.wishbone_pkg.all;
use work.wr_fabric_pkg.all;
use work.genram_pkg.all;

entity xwb_fec is
  --generic( : natural := ;
  --         : natural := );  
  port (
   clk_i         : in  std_logic;    -- tranceiver clock domain
   nRSt_i        : in  std_logic;
   
   -----------------------------------------
   -- External Fabric I/F
   -----------------------------------------
   fec_wr_src_o  : out t_wrf_source_out;
   fec_wr_src_i  : in  t_wrf_source_in := c_dummy_src_in;
   fec_wr_snk_o  : out t_wrf_sink_out;
   fec_wr_snk_i  : in  t_wrf_sink_in   := c_dummy_snk_in;

   -----------------------------------------
   -- External Fabric I/F
   -----------------------------------------
   fec_eb_src_o  : out t_wrf_source_out;
   fec_eb_src_i  : in  t_wrf_source_in := c_dummy_src_in;
   fec_eb_snk_o  : out t_wrf_sink_out;
   fec_eb_snk_i  : in  t_wrf_sink_in   := c_dummy_snk_in;
    
   -----------------------------------------
   --External WB interface
   -----------------------------------------
   c_slave_i     : in  t_wishbone_slave_in;  -- Wishbone slave interface (sys_clk domain)
   c_slave_o     : out t_wishbone_slave_out);
end xwb_fec;

architecture behavioral of xwb_fec is

   -- External Fabric I/F
   signal src_a_out    : t_wrf_source_out;
   signal src_a_in     : t_wrf_source_in;
   signal snk_a_out    : t_wrf_sink_out;
   signal snk_a_in     : t_wrf_sink_in;   

   signal src_b_out    : t_wrf_source_out;
   signal src_b_in     : t_wrf_source_in;
   signal snk_b_out    : t_wrf_sink_out;
   signal snk_b_in     : t_wrf_sink_in;
   
   signal src_c_out    : t_wrf_source_out;
   signal src_c_in     : t_wrf_source_in;
   signal snk_c_out    : t_wrf_sink_out;
   signal snk_c_in     : t_wrf_sink_in;
  
   -- wb interface signals
   signal address :  unsigned(11 downto 0);
   alias  adr_hi  :  unsigned(4 downto 0) is address(9 downto 5);
   alias  adr_lo  :  unsigned(2 downto 0) is address(4 downto 2);
   signal data    :  std_logic_vector(31 downto 0);

   --wb registers
   signal s_ctrl_reg      :  std_logic_vector(31 downto 0);
   signal s_status_reg    :  std_logic_vector(31 downto 0);
   --
   signal s_fec_en        :  std_logic   := '0';  -- Disable the FEC 
   signal s_fec_bit_err   :  std_logic   := '0';  -- Disable Bit Error Code
   signal s_fec_pack_err  :  std_logic   := '0';  -- Disable Packet Error Code
   signal s_fec_inyector  :  std_logic   := '0';  -- Injector Packet

begin  -- behavioral

   s_fec_en <= s_status_reg(0);
   s_fec_inyector <= s_status_reg(3);

   -- I/F
   fec_wr_src_o   <= src_a_out;
   src_a_in       <= fec_wr_src_i;
   fec_wr_snk_o   <= snk_a_out;
   snk_a_in       <= fec_wr_snk_i;

   fec_eb_src_o   <= src_b_out;
   src_b_in       <= fec_eb_src_i;
   fec_eb_snk_o   <= snk_b_out;
   snk_b_in       <= fec_eb_snk_i;
   
   -- if fec disable, no encoding/decoding or inyector
   
   src_a_out <=   snk_b_in when s_fec_en = '1'        else
                  snk_c_in when s_fec_inyector = '1';

   src_a_in <=    snk_b_out when s_fec_en = '1'       else
                  snk_c_out when s_fec_inyector = '1';

   snk_a_out <=   src_b_in when s_fec_en = '1'        else
                  src_c_in when s_fec_inyector = '1';

   snk_a_in <=    src_b_out when s_fec_en = '1'        else
                  src_c_out when s_fec_inyector = '1';

   -- WB Interface
   --address       <= unsigned(c_slave_i.adr(11 downto 0));
	--address 		  <= to_integer(unsigned(c_slave_i.adr(5 downto 2)));
   data          <= c_slave_i.dat(31 downto 0);


   wb_if : process (clk_i)
   begin  -- process c_if

   if clk_i'event and clk_i = '1' then  -- rising clock edge
      if nRst_i = '0' then          	
         -- synchronous reset (active low)         
         c_slave_o.ack    <= '0';
         c_slave_o.rty    <= '0';
         c_slave_o.int    <= '0';
         c_slave_o.err    <= '0';
         c_slave_o.stall  <= '0';
         c_slave_o.dat    <= (others => '0');
      else
         c_slave_o.ack    <= '0';
         c_slave_o.err    <= '0';
         c_slave_o.stall  <= '0';
         c_slave_o.dat    <= (others => '0');

         --if(c_slave_i.cyc = '1' and c_slave_i.stb = '1' and  c_slave_i.stall = '0') then
         if(c_slave_i.cyc = '1' and c_slave_i.stb = '1') then
            if(c_slave_i.we = '1') then
               ---------------------------------------------------------------------
               -- Write standard config regs
               ---------------------------------------------------------------------
               case to_integer(unsigned(c_slave_i.adr(5 downto 2))) is
                  when 0 => 	s_ctrl_reg <= data; 
										c_slave_o.ack <= '1'; 
                  when others => c_slave_o.err <= '1';  
               end case;
            else
               -------------------------------------------------------------------
               -- Read standard config regs
               -------------------------------------------------------------------
               case to_integer(unsigned(c_slave_i.adr(5 downto 2))) is
                  when 0 => 	c_slave_o.dat <= s_ctrl_reg; 
										c_slave_o.ack <= '1'; 
                  when others => c_slave_o.err <= '1';  
               end case;
            end if;
         end if; -- if cyc & stb & !stall
      end if;  -- if nrst
   end if;  -- if clock edge
   end process wb_if;

end behavioral;


