-- Title      : WhiteRabbit PTP Core
-- Project    : WhiteRabbit
-------------------------------------------------------------------------------
-- File       : wr_core.vhd
-- Author     : Grzegorz Daniluk
-- Company    : Elproma Elektronika, CERN BE-CO-HT
-- Created    : 2011-02-02
-- Last update: 2013-03-19
-- Platform   : FPGA-generics
-- Standard   : VHDL
-------------------------------------------------------------------------------
-- Description:
-- WR PTP Core is a HDL module implementing a complete gigabit Ethernet 
-- interface (MAC + PCS + PHY) with integrated PTP slave ordinary clock 
-- compatible with White Rabbit protocol. It performs subnanosecond clock 
-- synchronization via WR protocol and also acts as an Ethernet "gateway", 
-- providing access to TX/RX interfaces of the built-in WR MAC.
--
-- Starting from version 2.0 all modules are interconnected with pipelined
-- wishbone interface (using wb crossbars). Separate pipelined wishbone bus is 
-- used for passing packets between Endpoint, Mini-NIC and External 
-- MAC interface.
-------------------------------------------------------------------------------
--
-- Copyright (c) 2011, 2012 Elproma Elektronika
-- Copyright (c) 2012, 2013 CERN
--
-- This source file is free software; you can redistribute it   
-- and/or modify it under the terms of the GNU Lesser General   
-- Public License as published by the Free Software Foundation; 
-- either version 2.1 of the License, or (at your option) any   
-- later version.                                               
--
-- This source is distributed in the hope that it will be       
-- useful, but WITHOUT ANY WARRANTY; without even the implied   
-- warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR      
-- PURPOSE.  See the GNU Lesser General Public License for more 
-- details.                                                     
--
-- You should have received a copy of the GNU Lesser General    
-- Public License along with this source; if not, download it   
-- from http://www.gnu.org/licenses/lgpl-2.1.html
--
-------------------------------------------------------------------------------
-- Revisions  :
-- Date        Version  Author          Description
-- 2011-02-02  1.0      greg.d          Created
-- 2011-10-25  2.0      greg.d          Redesigned and wishbonized
-- 2012-03-05  3.0      wterpstra       Added SDB descriptors
-------------------------------------------------------------------------------


-- Memory map:

-- Master interconnect:
--  0x00000000: I/D Memory
--  0x00020000: Peripheral interconnect
--      +0x000: Minic
--      +0x100: Endpoint
--      +0x200: Softpll
--      +0x300: PPS gen
--      +0x400: Syscon
--      +0x500: UART
--      +0x600: OneWire
--      +0x700: Auxillary space (Etherbone config, etc)

library ieee;
use ieee.std_logic_1164.all;

library work;
use work.wrcore_pkg.all;
use work.genram_pkg.all;
use work.wishbone_pkg.all;
use work.endpoint_pkg.all;
use work.wr_fabric_pkg.all;
use work.sysc_wbgen2_pkg.all;

entity wr_core is
  generic(
    --if set to 1, then blocks in PCS use smaller calibration counter to speed 
    --up simulation
    g_simulation                : integer                        := 0;
    g_with_external_clock_input : boolean                        := false;
    --
    g_phys_uart                 : boolean                        := true;
    g_virtual_uart              : boolean                        := false;
    g_aux_clks                  : integer                        := 1;
    g_rx_buffer_size            : integer                        := 1024;
    g_dpram_initf               : string                         := "default";
    g_dpram_size                : integer                        := 90112/4;  --in 32-bit words
    g_interface_mode            : t_wishbone_interface_mode      := PIPELINED;
    g_address_granularity       : t_wishbone_address_granularity := WORD;
    g_aux_sdb                   : t_sdb_device                   := c_wrc_periph3_sdb
    );
  port(
    ---------------------------------------------------------------------------
    -- Clocks/resets
    ---------------------------------------------------------------------------

    -- system reference clock (any frequency <= f(clk_ref_i))
    clk_sys_i : in std_logic;

    -- DDMTD offset clock (125.x MHz)
    clk_dmtd_i : in std_logic;

    -- Timing reference (125 MHz)
    clk_ref_i : in std_logic;

    -- Aux clocks (i.e. the FMC clock), which can be disciplined by the WR Core
    clk_aux_i : in std_logic_vector(g_aux_clks-1 downto 0) := (others => '0');

    -- External 10 MHz reference (cesium, GPSDO, etc.), used in Grandmaster mode
    clk_ext_i : in std_logic := '0';

    -- External PPS input (cesium, GPSDO, etc.), used in Grandmaster mode
    pps_ext_i : in std_logic := '0';

    rst_n_i : in std_logic;

    -----------------------------------------
    --Timing system
    -----------------------------------------
    dac_hpll_load_p1_o : out std_logic;
    dac_hpll_data_o    : out std_logic_vector(15 downto 0);

    dac_dpll_load_p1_o : out std_logic;
    dac_dpll_data_o    : out std_logic_vector(15 downto 0);

    -- PHY I/f
    phy_ref_clk_i : in std_logic;

    phy_tx_data_o      : out std_logic_vector(7 downto 0);
    phy_tx_k_o         : out std_logic;
    phy_tx_disparity_i : in  std_logic;
    phy_tx_enc_err_i   : in  std_logic;

    phy_rx_data_i     : in std_logic_vector(7 downto 0);
    phy_rx_rbclk_i    : in std_logic;
    phy_rx_k_i        : in std_logic;
    phy_rx_enc_err_i  : in std_logic;
    phy_rx_bitslide_i : in std_logic_vector(3 downto 0);

    phy_rst_o    : out std_logic;
    phy_loopen_o : out std_logic;

    -----------------------------------------
    --GPIO
    -----------------------------------------
    led_act_o  : out std_logic;
    led_link_o : out std_logic;
    scl_o      : out std_logic;
    scl_i      : in  std_logic := '1';
    sda_o      : out std_logic;
    sda_i      : in  std_logic := '1';
    sfp_scl_o  : out std_logic;
    sfp_scl_i  : in  std_logic := '1';
    sfp_sda_o  : out std_logic;
    sfp_sda_i  : in  std_logic := '1';
    sfp_det_i  : in  std_logic := '1';
    btn1_i     : in  std_logic := '1';
    btn2_i     : in  std_logic := '1';

    -----------------------------------------
    --UART
    -----------------------------------------
    uart_rxd_i : in  std_logic := '0';
    uart_txd_o : out std_logic;

    -----------------------------------------
    -- 1-wire
    -----------------------------------------
    owr_pwren_o : out std_logic_vector(1 downto 0);
    owr_en_o    : out std_logic_vector(1 downto 0);
    owr_i       : in  std_logic_vector(1 downto 0) := (others => '1');

    -----------------------------------------
    --External WB interface
    -----------------------------------------
    wb_adr_i   : in  std_logic_vector(c_wishbone_address_width-1 downto 0)   := (others => '0');
    wb_dat_i   : in  std_logic_vector(c_wishbone_data_width-1 downto 0)      := (others => '0');
    wb_dat_o   : out std_logic_vector(c_wishbone_data_width-1 downto 0);
    wb_sel_i   : in  std_logic_vector(c_wishbone_address_width/8-1 downto 0) := (others => '0');
    wb_we_i    : in  std_logic                                               := '0';
    wb_cyc_i   : in  std_logic                                               := '0';
    wb_stb_i   : in  std_logic                                               := '0';
    wb_ack_o   : out std_logic;
    wb_err_o   : out std_logic;
    wb_rty_o   : out std_logic;
    wb_stall_o : out std_logic;

    -----------------------------------------
    -- Auxillary WB master
    -----------------------------------------
    aux_adr_o   : out std_logic_vector(c_wishbone_address_width-1 downto 0);
    aux_dat_o   : out std_logic_vector(c_wishbone_data_width-1 downto 0);
    aux_dat_i   : in  std_logic_vector(c_wishbone_data_width-1 downto 0);
    aux_sel_o   : out std_logic_vector(c_wishbone_address_width/8-1 downto 0);
    aux_we_o    : out std_logic;
    aux_cyc_o   : out std_logic;
    aux_stb_o   : out std_logic;
    aux_ack_i   : in  std_logic := '1';
    aux_stall_i : in  std_logic := '0';

    -----------------------------------------
    -- External Fabric I/F
    -----------------------------------------
    ext_snk_adr_i   : in  std_logic_vector(1 downto 0)  := "00";
    ext_snk_dat_i   : in  std_logic_vector(15 downto 0) := x"0000";
    ext_snk_sel_i   : in  std_logic_vector(1 downto 0)  := "00";
    ext_snk_cyc_i   : in  std_logic                     := '0';
    ext_snk_we_i    : in  std_logic                     := '0';
    ext_snk_stb_i   : in  std_logic                     := '0';
    ext_snk_ack_o   : out std_logic;
    ext_snk_err_o   : out std_logic;
    ext_snk_stall_o : out std_logic;

    ext_src_adr_o   : out std_logic_vector(1 downto 0);
    ext_src_dat_o   : out std_logic_vector(15 downto 0);
    ext_src_sel_o   : out std_logic_vector(1 downto 0);
    ext_src_cyc_o   : out std_logic;
    ext_src_stb_o   : out std_logic;
    ext_src_we_o    : out std_logic;
    ext_src_ack_i   : in  std_logic := '1';
    ext_src_err_i   : in  std_logic := '0';
    ext_src_stall_i : in  std_logic := '0';

    ------------------------------------------
    -- External TX Timestamp I/F
    ------------------------------------------
    txtsu_port_id_o      : out std_logic_vector(4 downto 0);
    txtsu_frame_id_o     : out std_logic_vector(15 downto 0);
    txtsu_ts_value_o     : out std_logic_vector(31 downto 0);
    txtsu_ts_incorrect_o : out std_logic;
    txtsu_stb_o          : out std_logic;
    txtsu_ack_i          : in  std_logic := '1';

    -----------------------------------------
    -- Timecode/Servo Control
    -----------------------------------------

    tm_link_up_o         : out std_logic;
    -- DAC Control
    tm_dac_value_o       : out std_logic_vector(23 downto 0);
    tm_dac_wr_o          : out std_logic;
    -- Aux clock lock enable
    tm_clk_aux_lock_en_i : in  std_logic := '0';
    -- Aux clock locked flag
    tm_clk_aux_locked_o  : out std_logic;
    -- Timecode output
    tm_time_valid_o      : out std_logic;
    tm_tai_o             : out std_logic_vector(39 downto 0);
    tm_cycles_o          : out std_logic_vector(27 downto 0);
    -- 1PPS output
    pps_p_o              : out std_logic;
    pps_led_o            : out std_logic;

    dio_o       : out std_logic_vector(3 downto 0);
    rst_aux_n_o : out std_logic;

    link_ok_o : out std_logic
    );
end wr_core;

architecture struct of wr_core is

  function f_choose_lm32_firmware_file return string is
  begin
    if(g_dpram_initf = "default") then
      if(g_simulation /= 0) then
        report "[WR Core] Using simulation LM32 firmware." severity note;
        return "wrc-simulation.ram";
      else
        report "[WR Core] Using release LM32 firmware." severity note;
        return "wrc-release.ram";
      end if;
    else
      report "[WR Core] Using user-provided LM32 firmware." severity note;
      return g_dpram_initf;
    end if;
  end function;

  function f_check_if_lm32_firmware_necessary return boolean is
  begin
    if(g_dpram_initf /= "") then
      return true;
    else
      return false;
    end if;
  end function;

  signal rst_wrc_n : std_logic;
  signal rst_net_n : std_logic;

  -----------------------------------------------------------------------------
  --PPS generator
  -----------------------------------------------------------------------------
  signal s_pps_csync : std_logic;
  signal pps_valid   : std_logic;

  signal ppsg_wb_in  : t_wishbone_slave_in;
  signal ppsg_wb_out : t_wishbone_slave_out;

  -----------------------------------------------------------------------------
  --Timing system
  -----------------------------------------------------------------------------
  signal spll_wb_in  : t_wishbone_slave_in;
  signal spll_wb_out : t_wishbone_slave_out;

  -----------------------------------------------------------------------------
  --Endpoint
  -----------------------------------------------------------------------------

  signal ep_txtsu_port_id           : std_logic_vector(4 downto 0);
  signal ep_txtsu_frame_id          : std_logic_vector(15 downto 0);
  signal ep_txtsu_ts_value          : std_logic_vector(31 downto 0);
  signal ep_txtsu_ts_incorrect      : std_logic;
  signal ep_txtsu_stb, ep_txtsu_ack : std_logic;
  signal ep_led_link                : std_logic;

  constant c_mnic_memsize_log2 : integer := f_log2_size(g_dpram_size);

  -----------------------------------------------------------------------------
  --Mini-NIC
  -----------------------------------------------------------------------------
  signal mnic_mem_data_o : std_logic_vector(31 downto 0);
  signal mnic_mem_addr_o : std_logic_vector(c_mnic_memsize_log2-1 downto 0);
  signal mnic_mem_data_i : std_logic_vector(31 downto 0);
  signal mnic_mem_wr_o   : std_logic;
  signal mnic_txtsu_ack  : std_logic;

  -----------------------------------------------------------------------------
  --Dual-port RAM
  -----------------------------------------------------------------------------
  signal dpram_wbb_i : t_wishbone_slave_in;
  signal dpram_wbb_o : t_wishbone_slave_out;

  -----------------------------------------------------------------------------
  --WB Peripherials
  -----------------------------------------------------------------------------
  signal periph_slave_i : t_wishbone_slave_in_array(0 to 2);
  signal periph_slave_o : t_wishbone_slave_out_array(0 to 2);
  signal sysc_in_regs   : t_sysc_in_registers;
  signal sysc_out_regs  : t_sysc_out_registers;

  -----------------------------------------------------------------------------
  --WB Secondary Crossbar
  -----------------------------------------------------------------------------
  constant c_secbar_layout : t_sdb_record_array(7 downto 0) :=
    (0 => f_sdb_embed_device(c_xwr_mini_nic_sdb, x"00000000"),
     1 => f_sdb_embed_device(c_xwr_endpoint_sdb, x"00000100"),
     2 => f_sdb_embed_device(c_xwr_softpll_ng_sdb, x"00000200"),
     3 => f_sdb_embed_device(c_xwr_pps_gen_sdb, x"00000300"),
     4 => f_sdb_embed_device(c_wrc_periph0_sdb, x"00000400"),  -- Syscon
     5 => f_sdb_embed_device(c_wrc_periph1_sdb, x"00000500"),  -- UART
     6 => f_sdb_embed_device(c_wrc_periph2_sdb, x"00000600"),  -- 1-Wire
     7 => f_sdb_embed_device(g_aux_sdb, x"00000700")           -- aux WB bus
     );

  constant c_secbar_sdb_address : t_wishbone_address := x"00000800";
  constant c_secbar_bridge_sdb  : t_sdb_bridge       :=
    f_xwb_bridge_layout_sdb(true, c_secbar_layout, c_secbar_sdb_address);

  signal secbar_master_i : t_wishbone_master_in_array(7 downto 0);
  signal secbar_master_o : t_wishbone_master_out_array(7 downto 0);

  -----------------------------------------------------------------------------
  --WB intercon
  -----------------------------------------------------------------------------
  constant c_layout : t_sdb_record_array(1 downto 0) :=
    (0 => f_sdb_embed_device(f_xwb_dpram(g_dpram_size), x"00000000"),
     1 => f_sdb_embed_bridge(c_secbar_bridge_sdb, x"00020000"));
  constant c_sdb_address : t_wishbone_address := x"00030000";

  signal cbar_slave_i  : t_wishbone_slave_in_array (2 downto 0);
  signal cbar_slave_o  : t_wishbone_slave_out_array(2 downto 0);
  signal cbar_master_i : t_wishbone_master_in_array(1 downto 0);
  signal cbar_master_o : t_wishbone_master_out_array(1 downto 0);

  -----------------------------------------------------------------------------
  --External WB interface
  -----------------------------------------------------------------------------
  signal ext_wb_in  : t_wishbone_slave_in;
  signal ext_wb_out : t_wishbone_slave_out;

  -----------------------------------------------------------------------------
  -- External Tx TSU interface
  -----------------------------------------------------------------------------

  --===========================--
  --         For SPEC          --
  --===========================--

  signal hpll_auxout  : std_logic_vector(2 downto 0);
  signal dmpll_auxout : std_logic_vector(2 downto 0);

  signal clk_ref_slv : std_logic_vector(0 downto 0);
  signal clk_rx_slv  : std_logic_vector(0 downto 0);

  signal s_dummy_addr : std_logic_vector(31 downto 0);

  signal softpll_irq : std_logic;

  signal lm32_irq_slv : std_logic_vector(31 downto 0);


  signal ep_wb_in  : t_wishbone_slave_in;
  signal ep_wb_out : t_wishbone_slave_out;

  signal minic_wb_in  : t_wishbone_slave_in;
  signal minic_wb_out : t_wishbone_slave_out;

  signal ep_src_out : t_wrf_source_out;
  signal ep_src_in  : t_wrf_source_in;
  signal ep_snk_out : t_wrf_sink_out;
  signal ep_snk_in  : t_wrf_sink_in;


  signal mux_src_out : t_wrf_source_out_array(1 downto 0);
  signal mux_src_in  : t_wrf_source_in_array(1 downto 0);
  signal mux_snk_out : t_wrf_sink_out_array(1 downto 0);
  signal mux_snk_in  : t_wrf_sink_in_array(1 downto 0);
  signal mux_class   : t_wrf_mux_class(1 downto 0);

  signal dummy : std_logic_vector(31 downto 0);

  signal spll_out_locked : std_logic_vector(g_aux_clks downto 0);

  signal dac_dpll_data    : std_logic_vector(15 downto 0);
  signal dac_dpll_sel     : std_logic_vector(3 downto 0);
  signal dac_dpll_load_p1 : std_logic;

  signal clk_fb     : std_logic_vector(g_aux_clks downto 0);
  signal out_enable : std_logic_vector(g_aux_clks downto 0);

  --component chipscope_ila
  --  port (
  --    CONTROL : inout std_logic_vector(35 downto 0);
  --    CLK     : in    std_logic;
  --    TRIG0   : in    std_logic_vector(31 downto 0);
  --    TRIG1   : in    std_logic_vector(31 downto 0);
  --    TRIG2   : in    std_logic_vector(31 downto 0);
  --    TRIG3   : in    std_logic_vector(31 downto 0));
  --end component;

  --component chipscope_icon
  --  port (
  --    CONTROL0 : inout std_logic_vector (35 downto 0));
  --end component;

  --signal CONTROL : std_logic_vector(35 downto 0);
  --signal CLK     : std_logic;
  --signal TRIG0   : std_logic_vector(31 downto 0);
  --signal TRIG1   : std_logic_vector(31 downto 0);
  --signal TRIG2   : std_logic_vector(31 downto 0);
  --signal TRIG3   : std_logic_vector(31 downto 0);
begin

  rst_aux_n_o <= rst_net_n;

  -----------------------------------------------------------------------------
  -- PPS generator
  -----------------------------------------------------------------------------
  PPS_GEN : xwr_pps_gen
    generic map(
      g_interface_mode       => PIPELINED,
      g_address_granularity  => BYTE,
      g_ref_clock_rate       => 125000000,
      g_ext_clock_rate       => 10000000,
      g_with_ext_clock_input => g_with_external_clock_input)
    port map(
      clk_ref_i => clk_ref_i,
      clk_sys_i => clk_sys_i,
      clk_ext_i => clk_ext_i,

      rst_n_i => rst_net_n,

      slave_i => ppsg_wb_in,
      slave_o => ppsg_wb_out,

      -- Single-pulse PPS output for synchronizing endpoint to
      pps_in_i    => pps_ext_i,
      pps_csync_o => s_pps_csync,
      pps_out_o   => pps_p_o,
      pps_led_o   => pps_led_o,
      pps_valid_o => pps_valid,

      tm_utc_o        => tm_tai_o,
      tm_cycles_o     => tm_cycles_o,
      tm_time_valid_o => tm_time_valid_o
      );

  -----------------------------------------------------------------------------
  -- Software PLL
  -----------------------------------------------------------------------------

  U_SOFTPLL : xwr_softpll_ng
    generic map(
      g_with_ext_clock_input => g_with_external_clock_input,
      g_reverse_dmtds        => false,
      g_divide_input_by_2    => true,
      g_with_undersampling   => false,
      g_with_period_detector => false,
      g_with_debug_fifo      => true,

      g_bb_ref_divider      => 8,
      g_bb_feedback_divider => 50,
      g_bb_log2_gating      => 13,

      g_tag_bits            => 22,
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE,
      g_num_ref_inputs      => 1,
      g_num_outputs         => 1 + g_aux_clks)
    port map(
      clk_sys_i => clk_sys_i,
      rst_n_i   => rst_net_n,

      -- Reference inputs (i.e. the RX clocks recovered by the PHYs)
      clk_ref_i(0) => phy_rx_rbclk_i,
      -- Feedback clocks (i.e. the outputs of the main or aux oscillator)
      clk_fb_i     => clk_fb,
      -- DMTD Offset clock
      clk_dmtd_i   => clk_dmtd_i,

      clk_ext_i => clk_ext_i,
      sync_p_i  => pps_ext_i,

      -- DMTD oscillator drive
      dac_dmtd_data_o => dac_hpll_data_o,
      dac_dmtd_load_o => dac_hpll_load_p1_o,

      -- Output channel DAC value
      dac_out_data_o => dac_dpll_data,  --: out std_logic_vector(15 downto 0);
      -- Output channel select (0 = channel 0, etc. )
      dac_out_sel_o  => dac_dpll_sel,   --for now use only one output
      dac_out_load_o => dac_dpll_load_p1,

      out_enable_i => out_enable,

      out_locked_o => spll_out_locked,

      slave_i => spll_wb_in,
      slave_o => spll_wb_out,

      debug_o => dio_o
      );

  clk_fb(0)                       <= clk_ref_i;
  clk_fb(g_aux_clks downto 1)     <= clk_aux_i;
  out_enable(0)                   <= '1';
  out_enable(g_aux_clks downto 1) <= (others => tm_clk_aux_lock_en_i);

  dac_dpll_data_o    <= dac_dpll_data;
  dac_dpll_load_p1_o <= '1' when (dac_dpll_load_p1 = '1' and dac_dpll_sel = x"0") else '0';

  tm_dac_value_o <= x"00" & dac_dpll_data;
  tm_dac_wr_o    <= '1' when (dac_dpll_load_p1 = '1' and dac_dpll_sel = x"1") else '0';

  locked_spll : if g_aux_clks > 0 generate
    tm_clk_aux_locked_o <= spll_out_locked(1);  -- !!! what if more than one clock?! FIXME
  end generate;

  softpll_irq <= spll_wb_out.int;

  -----------------------------------------------------------------------------
  -- Endpoint
  -----------------------------------------------------------------------------
  U_Endpoint : xwr_endpoint
    generic map (
      g_interface_mode      => PIPELINED,
      g_address_granularity => BYTE,
      g_simulation          => false,
      g_pcs_16bit           => false,
      g_rx_buffer_size      => g_rx_buffer_size,
      g_with_rx_buffer      => true,
      g_with_flow_control   => false,
      g_with_timestamper    => true,
      g_with_dpi_classifier => true,
      g_with_vlans          => false,
      g_with_rtu            => false,
      g_with_leds           => true)
    port map (
      clk_ref_i      => clk_ref_i,
      clk_sys_i      => clk_sys_i,
      clk_dmtd_i     => clk_dmtd_i,
      rst_n_i        => rst_net_n,
      pps_csync_p1_i => s_pps_csync,
      pps_valid_i    => pps_valid,

      phy_rst_o                     => phy_rst_o,
      phy_loopen_o                  => phy_loopen_o,
      phy_ref_clk_i                 => phy_ref_clk_i,
      phy_tx_data_o(7 downto 0)     => phy_tx_data_o,
      phy_tx_data_o(15 downto 8)    => dummy(7 downto 0),
      phy_tx_k_o(0)                 => phy_tx_k_o,
      phy_tx_k_o(1)                 => dummy(8),
      phy_tx_disparity_i            => phy_tx_disparity_i,
      phy_tx_enc_err_i              => phy_tx_enc_err_i,
      phy_rx_data_i(7 downto 0)     => phy_rx_data_i,
      phy_rx_data_i(15 downto 8)    => x"00",
      phy_rx_clk_i                  => phy_rx_rbclk_i,
      phy_rx_k_i(0)                 => phy_rx_k_i,
      phy_rx_k_i(1)                 => '0',
      phy_rx_enc_err_i              => phy_rx_enc_err_i,
      phy_rx_bitslide_i(3 downto 0) => phy_rx_bitslide_i,
      phy_rx_bitslide_i(4)          => '0',

      src_o => ep_src_out,
      src_i => ep_src_in,
      snk_o => ep_snk_out,
      snk_i => ep_snk_in,

      txtsu_port_id_o      => ep_txtsu_port_id,
      txtsu_frame_id_o     => ep_txtsu_frame_id,
      txtsu_ts_value_o     => ep_txtsu_ts_value,
      txtsu_ts_incorrect_o => ep_txtsu_ts_incorrect,
      txtsu_stb_o          => ep_txtsu_stb,
      txtsu_ack_i          => ep_txtsu_ack,
      wb_i                 => ep_wb_in,
      wb_o                 => ep_wb_out,
      led_link_o           => ep_led_link,
      led_act_o            => led_act_o);

  ep_txtsu_ack <= txtsu_ack_i or mnic_txtsu_ack;
  led_link_o   <= ep_led_link;
  link_ok_o    <= ep_led_link;

  tm_link_up_o <= ep_led_link;

  -----------------------------------------------------------------------------
  -- Mini-NIC
  -----------------------------------------------------------------------------
  MINI_NIC : xwr_mini_nic
    generic map (
      g_interface_mode       => PIPELINED,
      g_address_granularity  => BYTE,
      g_memsize_log2         => f_log2_size(g_dpram_size),
      g_buffer_little_endian => false)
    port map (
      clk_sys_i => clk_sys_i,
      rst_n_i   => rst_net_n,

      mem_data_o => mnic_mem_data_o,
      mem_addr_o => mnic_mem_addr_o,
      mem_data_i => mnic_mem_data_i,
      mem_wr_o   => mnic_mem_wr_o,

      src_o => mux_snk_in(0),
      src_i => mux_snk_out(0),
      snk_o => mux_src_in(0),
      snk_i => mux_src_out(0),

      txtsu_port_id_i     => ep_txtsu_port_id,
      txtsu_frame_id_i    => ep_txtsu_frame_id,
      txtsu_tsval_i       => ep_txtsu_ts_value,
      txtsu_tsincorrect_i => ep_txtsu_ts_incorrect,
      txtsu_stb_i         => ep_txtsu_stb,
      txtsu_ack_o         => mnic_txtsu_ack,

      wb_i => minic_wb_in,
      wb_o => minic_wb_out
      );

  lm32_irq_slv(31 downto 1) <= (others => '0');
  lm32_irq_slv(0)           <= softpll_irq;  -- according to the doc, it's active low.

  -----------------------------------------------------------------------------
  -- LM32
  -----------------------------------------------------------------------------  
  LM32_CORE : xwb_lm32
    generic map(g_profile => "medium_icache_debug")
    port map(
      clk_sys_i => clk_sys_i,
      rst_n_i   => rst_wrc_n,
      irq_i     => lm32_irq_slv,

      dwb_o => cbar_slave_i(0),
      dwb_i => cbar_slave_o(0),
      iwb_o => cbar_slave_i(1),
      iwb_i => cbar_slave_o(1)
      );

  -----------------------------------------------------------------------------
  -- Dual-port RAM
  -----------------------------------------------------------------------------  
  DPRAM : xwb_dpram
    generic map(
      g_size                  => g_dpram_size,
      g_init_file             => f_choose_lm32_firmware_file,
      g_must_have_init_file   => f_check_if_lm32_firmware_necessary,
      g_slave1_interface_mode => PIPELINED,
      g_slave2_interface_mode => PIPELINED,
      g_slave1_granularity    => BYTE,
      g_slave2_granularity    => WORD)  
    port map(
      clk_sys_i => clk_sys_i,
      rst_n_i   => rst_n_i,

      slave1_i => cbar_master_o(0),
      slave1_o => cbar_master_i(0),
      slave2_i => dpram_wbb_i,
      slave2_o => dpram_wbb_o
      );

  dpram_wbb_i.cyc                                 <= '1';
  dpram_wbb_i.stb                                 <= '1';
  dpram_wbb_i.adr(c_mnic_memsize_log2-1 downto 0) <= mnic_mem_addr_o;
  dpram_wbb_i.sel                                 <= "1111";
  dpram_wbb_i.we                                  <= mnic_mem_wr_o;
  dpram_wbb_i.dat                                 <= mnic_mem_data_o;
  mnic_mem_data_i                                 <= dpram_wbb_o.dat;

  -----------------------------------------------------------------------------
  -- WB Peripherials
  -----------------------------------------------------------------------------
  PERIPH : wrc_periph
    generic map(
      g_phys_uart    => g_phys_uart,
      g_virtual_uart => g_virtual_uart,
      g_mem_words    => g_dpram_size)
    port map(
      clk_sys_i   => clk_sys_i,
      rst_n_i     => rst_n_i,
      rst_net_n_o => rst_net_n,
      rst_wrc_n_o => rst_wrc_n,

      led_red_o   => open,              --led_red_o,
      led_green_o => open,              --led_green_o,
      scl_o       => scl_o,
      scl_i       => scl_i,
      sda_o       => sda_o,
      sda_i       => sda_i,
      sfp_scl_o   => sfp_scl_o,
      sfp_scl_i   => sfp_scl_i,
      sfp_sda_o   => sfp_sda_o,
      sfp_sda_i   => sfp_sda_i,
      sfp_det_i   => sfp_det_i,
      memsize_i   => "0000",
      btn1_i      => btn1_i,
      btn2_i      => btn2_i,

      slave_i => periph_slave_i,
      slave_o => periph_slave_o,

      uart_rxd_i => uart_rxd_i,
      uart_txd_o => uart_txd_o,

      owr_pwren_o => owr_pwren_o,
      owr_en_o    => owr_en_o,
      owr_i       => owr_i
      );

  U_Adapter : wb_slave_adapter
    generic map(
      g_master_use_struct  => true,
      g_master_mode        => PIPELINED,
      g_master_granularity => BYTE,
      g_slave_use_struct   => false,
      g_slave_mode         => g_interface_mode,
      g_slave_granularity  => g_address_granularity)
    port map (
      clk_sys_i  => clk_sys_i,
      rst_n_i    => rst_n_i,
      master_i   => ext_wb_out,
      master_o   => ext_wb_in,
      sl_adr_i   => wb_adr_i,
      sl_dat_i   => wb_dat_i,
      sl_sel_i   => wb_sel_i,
      sl_cyc_i   => wb_cyc_i,
      sl_stb_i   => wb_stb_i,
      sl_we_i    => wb_we_i,
      sl_dat_o   => wb_dat_o,
      sl_ack_o   => wb_ack_o,
      sl_err_o   => wb_err_o,
      sl_rty_o   => wb_rty_o,
      sl_stall_o => wb_stall_o);

  -----------------------------------------------------------------------------
  -- WB intercon
  -----------------------------------------------------------------------------
  WB_CON : xwb_sdb_crossbar
    generic map(
      g_num_masters => 3,
      g_num_slaves  => 2,
      g_registered  => true,
      g_wraparound  => true,
      g_layout      => c_layout,
      g_sdb_addr    => c_sdb_address
      )  
    port map(
      clk_sys_i => clk_sys_i,
      rst_n_i   => rst_n_i,
      -- Master connections (INTERCON is a slave)
      slave_i   => cbar_slave_i,
      slave_o   => cbar_slave_o,
      -- Slave connections (INTERCON is a master)
      master_i  => cbar_master_i,
      master_o  => cbar_master_o
      );

  cbar_slave_i(2) <= ext_wb_in;
  ext_wb_out      <= cbar_slave_o(2);

  --chipscope_ila_1 : chipscope_ila
  --  port map (
  --    CONTROL => CONTROL,
  --    CLK     => clk_sys_i,
  --    TRIG0   => TRIG0,
  --    TRIG1   => TRIG1,
  --    TRIG2   => TRIG2,
  --    TRIG3   => TRIG3);

  --chipscope_icon_1 : chipscope_icon
  --  port map (
  --    CONTROL0 => CONTROL);

  --TRIG0(15 downto 0)  <= ep_snk_in.dat;
  --trig0(17 downto 16) <= ep_snk_in.adr;
  --trig0(19 downto 18) <= ep_snk_in.sel;
  --trig0(20) <= ep_snk_in.cyc;
  --trig0(21) <= ep_snk_in.stb;
  --trig0(22) <= ep_snk_in.we;
  --trig0(23) <= ep_snk_out.ack;
  --trig0(24) <= ep_snk_out.stall;
  --trig0(26) <= ep_snk_out.err;

  --TRIG1(15 downto 0)  <= mux_snk_in(0).dat;
  --trig1(17 downto 16) <= mux_snk_in(0).adr;
  --trig1(19 downto 18) <= mux_snk_in(0).sel;
  --trig1(20) <= mux_snk_in(0).cyc;
  --trig1(21) <= mux_snk_in(0).stb;
  --trig1(22) <= mux_snk_in(0).we;
  --trig1(23) <= mux_snk_out(0).ack;
  --trig1(24) <= mux_snk_out(0).stall;
  --trig1(26) <= mux_snk_out(0).err;

  --TRIG2(15 downto 0)  <= mux_snk_in(1).dat;
  --trig2(17 downto 16) <= mux_snk_in(1).adr;
  --trig2(19 downto 18) <= mux_snk_in(1).sel;
  --trig2(20) <= mux_snk_in(1).cyc;
  --trig2(21) <= mux_snk_in(1).stb;
  --trig2(22) <= mux_snk_in(1).we;
  --trig2(23) <= mux_snk_out(1).ack;
  --trig2(24) <= mux_snk_out(1).stall;
  --trig2(26) <= mux_snk_out(1).err;
  -----------------------------------------------------------------------------
  -- WB Secondary Crossbar
  -----------------------------------------------------------------------------
  WB_SECONDARY_CON : xwb_sdb_crossbar
    generic map(
      g_num_masters => 1,
      g_num_slaves  => 8,
      g_registered  => true,
      g_wraparound  => true,
      g_layout      => c_secbar_layout,
      g_sdb_addr    => c_secbar_sdb_address
      )
    port map(
      clk_sys_i  => clk_sys_i,
      rst_n_i    => rst_n_i,
      -- Master connections (INTERCON is a slave)
      slave_i(0) => cbar_master_o(1),
      slave_o(0) => cbar_master_i(1),
      -- Slave connections (INTERCON is a master)
      master_i   => secbar_master_i,
      master_o   => secbar_master_o
      );

  secbar_master_i(0) <= minic_wb_out;
  minic_wb_in        <= secbar_master_o(0);
  secbar_master_i(1) <= ep_wb_out;
  ep_wb_in           <= secbar_master_o(1);
  secbar_master_i(2) <= spll_wb_out;
  spll_wb_in         <= secbar_master_o(2);
  secbar_master_i(3) <= ppsg_wb_out;
  ppsg_wb_in         <= secbar_master_o(3);
  --peripherials
  secbar_master_i(4) <= periph_slave_o(0);
  secbar_master_i(5) <= periph_slave_o(1);
  secbar_master_i(6) <= periph_slave_o(2);
  periph_slave_i(0)  <= secbar_master_o(4);
  periph_slave_i(1)  <= secbar_master_o(5);
  periph_slave_i(2)  <= secbar_master_o(6);


  aux_adr_o <= secbar_master_o(7).adr;
  aux_dat_o <= secbar_master_o(7).dat;
  aux_sel_o <= secbar_master_o(7).sel;
  aux_cyc_o <= secbar_master_o(7).cyc;
  aux_stb_o <= secbar_master_o(7).stb;
  aux_we_o  <= secbar_master_o(7).we;

  secbar_master_i(7).dat   <= aux_dat_i;
  secbar_master_i(7).ack   <= aux_ack_i;
  secbar_master_i(7).stall <= aux_stall_i;
  secbar_master_i(7).err   <= '0';
  secbar_master_i(7).rty   <= '0';

  --secbar_master_i(6).err <= '0';
  --secbar_master_i(5).err <= '0';
  --secbar_master_i(4).err <= '0';
  --secbar_master_i(3).err <= '0';
  --secbar_master_i(2).err <= '0';
  --secbar_master_i(1).err <= '0';
  --secbar_master_i(0).err <= '0';

  --secbar_master_i(6).rty <= '0';
  --secbar_master_i(5).rty <= '0';
  --secbar_master_i(4).rty <= '0';
  --secbar_master_i(3).rty <= '0';
  --secbar_master_i(2).rty <= '0';
  --secbar_master_i(1).rty <= '0';
  --secbar_master_i(0).rty <= '0';



  -----------------------------------------------------------------------------
  -- WBP MUX
  -----------------------------------------------------------------------------
  U_WBP_Mux : xwrf_mux
    generic map(
      g_muxed_ports => 2)
    port map (
      clk_sys_i   => clk_sys_i,
      rst_n_i     => rst_n_i,
      ep_src_o    => ep_snk_in,
      ep_src_i    => ep_snk_out,
      ep_snk_o    => ep_src_in,
      ep_snk_i    => ep_src_out,
      mux_src_o   => mux_src_out,
      mux_src_i   => mux_src_in,
      mux_snk_o   => mux_snk_out,
      mux_snk_i   => mux_snk_in,
      mux_class_i => mux_class);

  mux_class(0)  <= x"0f";
  mux_class(1)  <= x"f0";
  ext_src_adr_o <= mux_src_out(1).adr;
  ext_src_dat_o <= mux_src_out(1).dat;
  ext_src_stb_o <= mux_src_out(1).stb;
  ext_src_cyc_o <= mux_src_out(1).cyc;
  ext_src_sel_o <= mux_src_out(1).sel;
  ext_src_we_o  <= '1';

  mux_src_in(1).ack   <= ext_src_ack_i;
  mux_src_in(1).stall <= ext_src_stall_i;
  mux_src_in(1).err   <= ext_src_err_i;

  mux_snk_in(1).adr <= ext_snk_adr_i;
  mux_snk_in(1).dat <= ext_snk_dat_i;
  mux_snk_in(1).stb <= ext_snk_stb_i;
  mux_snk_in(1).cyc <= ext_snk_cyc_i;
  mux_snk_in(1).sel <= ext_snk_sel_i;
  mux_snk_in(1).we  <= ext_snk_we_i;

  ext_snk_ack_o   <= mux_snk_out(1).ack;
  ext_snk_err_o   <= mux_snk_out(1).err;
  ext_snk_stall_o <= mux_snk_out(1).stall;

  -----------------------------------------------------------------------------
  -- External Tx Timestamping I/F
  -----------------------------------------------------------------------------
  txtsu_port_id_o      <= ep_txtsu_port_id;
  txtsu_frame_id_o     <= ep_txtsu_frame_id;
  txtsu_ts_value_o     <= ep_txtsu_ts_value;
  txtsu_ts_incorrect_o <= ep_txtsu_ts_incorrect;
  txtsu_stb_o          <= '1' when (ep_txtsu_stb = '1' and (ep_txtsu_frame_id /= x"0000")) else
                          '0';

end struct;
