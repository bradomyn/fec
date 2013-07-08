library IEEE;
--! Standard packages    
use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use work.wr_fabric_pkg.all;

library work;
use work.wishbone_pkg.all;

package fec_pkg is

 constant c_xwr_wb_fec_sdb : t_sdb_device := (
    abi_class     => x"0000", -- undocumented device
    abi_ver_major => x"01",
    abi_ver_minor => x"01",
    wbd_endian    => c_sdb_endian_big,
    wbd_width     => x"7", -- 8/16/32-bit port granularity
    sdb_component => (
    addr_first    => x"0000000000000000",
    addr_last     => x"00000000000000ff",
    product => (
    vendor_id     => x"0000000000000651", -- GSI
    device_id     => x"1ad49e48",
    version       => x"00000001",
    date          => x"20130701",
    name          => "FEC                ")));

component xwb_fec
  port (
      clk_i          : in  std_logic;    -- tranceiver clock domain
      nRSt_i         : in  std_logic;
      -----------------------------------------
      fec_wr_src_o   : out t_wrf_source_out;
      fec_wr_src_i   : in  t_wrf_source_in := c_dummy_src_in;
      fec_wr_snk_o   : out t_wrf_sink_out;
      fec_wr_snk_i   : in  t_wrf_sink_in   := c_dummy_snk_in;

      -----------------------------------------
      -- External Fabric I/F
      -----------------------------------------
      fec_eb_src_o   : out t_wrf_source_out;
      fec_eb_src_i   : in  t_wrf_source_in := c_dummy_src_in;
      fec_eb_snk_o   : out t_wrf_sink_out;
      fec_eb_snk_i   : in  t_wrf_sink_in   := c_dummy_snk_in;

      -----------------------------------------
      --External WB interface
      -----------------------------------------
      c_slave_i      : in  t_wishbone_slave_in;  -- Wishbone slave interface (sys_clk domain)
      c_slave_o      : out t_wishbone_slave_out);

end component;

end fec_pkg;
