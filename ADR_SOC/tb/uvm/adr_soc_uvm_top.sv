/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_soc_uvm_top.sv
 Module/class Name             : adr_soc_uvm_top
 Author                        : Vijay Bogati
 Description                   : UVM SoC bench top: clocks and reset interface, pin interfaces, the board, the chip, run_test
***************************************************************/

// UVM bench (make ... TB=uvm with SIM=questa, vcs or xcelium); the Verilator bench is tb/verilator/.
//   i_tb_if                  adr_soc_tb_if.sv: clocks, reset, RTC tick, clocks since reset
//   i_<group>_if             one interface per pin group, handed to the environment below
//   `include board           adr_soc_tb_forces.svh: board signals, +loopback_<name> loopbacks,
//                            fixed wiring (SPI/QSPI mapping, I2C and USB bus resolution)
//   i_dut                    the chip; adr_soc_probes.sv is bound into it (fabric monitors and
//                            the C-UVM handshake path), so this file has no path into the chip
//   uvm_test_top.env         adr_soc_env_pkg.sv, tests in uvm_tests/, chosen with +UVM_TESTNAME
// The chip sees the same pins and the same clocks as on the Verilator bench, so a C test takes
// the same number of cycles on both (with the loopbacks it uses, e.g. for periph
// SIM_ARGS="+loopback_gpio +loopback_uart1").
// The UART, SPI and I2C interfaces hold pin-level assertions (ADR_ASSERTIONS_PLAN 5.1-5.3);
// +no_sva switches them off for speed or debug, never in a regression.

module adr_soc_uvm_top;
  timeunit 1ns;      // time declarations come first in a module (IEEE 1800)
  timeprecision 1ps;

  import uvm_pkg::*;
  import adr_tb_pkg::*;        // chip settings, e.g. BootPins
  import adr_soc_test_pkg::*;  // registers the tests with the factory

  // ---- Clocks, reset and time base ----
  adr_soc_tb_if i_tb_if ();

  // ---- One interface per pin group ----
  // A clock is passed where the protocol needs one: UART (the monitor counts system clocks per
  // bit), JTAG (the bench makes TCK from clk), OTP (a synchronous macro port), Ethernet (the
  // SerDes clock) and USB (the reference clock for recovering bits). SPI/QSPI and I2C are timed
  // by their own pins (SCLK and chip select, SCL and SDA); they get the system clock and reset
  // only for their assertions. ADC, GPIO and PWM are timed by level changes.
  adr_uart_if       i_uart0_if (.clk(i_tb_if.clk),     .rst_n(i_tb_if.rst_n));
  adr_uart_if       i_uart1_if (.clk(i_tb_if.clk),     .rst_n(i_tb_if.rst_n));
  adr_jtag_if       i_jtag_if  (.clk(i_tb_if.clk),     .rst_n(i_tb_if.rst_n));
  adr_gpio_if       i_gpio_if  ();
  adr_pwm_if        i_pwm_if   ();
  adr_spi_if        i_spi_if   (.clk(i_tb_if.clk),     .rst_n(i_tb_if.rst_n));
  adr_spi_if        i_qspi_if  (.clk(i_tb_if.clk),     .rst_n(i_tb_if.rst_n));
  adr_i2c_if        i_i2c_if   (.clk(i_tb_if.clk),     .rst_n(i_tb_if.rst_n));
  adr_otp_if        i_otp_if   (.clk(i_tb_if.clk),     .rst_n(i_tb_if.rst_n));
  adr_adc_if        i_adc_if   ();
  adr_eth_serdes_if i_eth_if   (.clk(i_tb_if.eth_clk), .rst_n(i_tb_if.rst_n));
  adr_usb_if        i_usb_if   (.clk(i_tb_if.usb_clk), .rst_n(i_tb_if.rst_n));

  // ---- Board: signals the chip uses, loopbacks (+loopback_<name>) and fixed wiring ----
  `include "adr_soc_tb_forces.svh"

  // ---- The chip ----
  adr_soc_top i_dut (
    .clk_i                     ( i_tb_if.clk         ),
    .rst_ni                    ( i_tb_if.rst_n       ),
    .rtc_i                     ( i_tb_if.rtc         ),
    .boot_pins_i               ( BootPins            ),
    // UART
    .uart0_rx_i                ( i_uart0_if.rx       ),
    .uart0_tx_o                ( i_uart0_if.tx       ),
    .uart1_rx_i                ( uart1_rx            ),
    .uart1_tx_o                ( i_uart1_if.tx       ),
    // GPIO and PWM
    .gpio_in_i                 ( i_gpio_if.in        ),
    .gpio_out_o                ( i_gpio_if.out       ),
    .gpio_dir_o                ( i_gpio_if.dir       ),
    .pwm_o                     ( i_pwm_if.pwm        ),
    // SPI and QSPI
    .spi_sclk_o                ( i_spi_if.sclk       ),
    .spi_csn_o                 ( i_spi_if.csn        ),
    .spi_mosi_o                ( i_spi_if.sdo[0]     ),
    .spi_miso_i                ( i_spi_if.sdi[1]     ),
    .qspi_sclk_o               ( i_qspi_if.sclk      ),
    .qspi_csn_o                ( i_qspi_if.csn       ),
    .qspi_mode_o               ( qspi_mode           ),
    .qspi_sdo_o                ( i_qspi_if.sdo       ),
    .qspi_sdi_i                ( i_qspi_if.sdi       ),
    // I2C
    .i2c_scl_i                 ( i_i2c_if.scl        ),
    .i2c_scl_o                 ( i_i2c_if.mst_scl_o  ),
    .i2c_scl_t                 ( i_i2c_if.mst_scl_t  ),
    .i2c_sda_i                 ( i_i2c_if.sda        ),
    .i2c_sda_o                 ( i_i2c_if.mst_sda_o  ),
    .i2c_sda_t                 ( i_i2c_if.mst_sda_t  ),
    // Ethernet SerDes; the bench's link is always aligned, so bit-slip and reset requests are unused
    .eth_tx_clk_i              ( i_tb_if.eth_clk     ),
    .eth_rx_clk_i              ( i_tb_if.eth_clk     ),
    .eth_serdes_tx_data_o      ( i_eth_if.tx_data    ),
    .eth_serdes_tx_hdr_o       ( i_eth_if.tx_hdr     ),
    .eth_serdes_rx_data_i      ( i_eth_if.rx_data    ),
    .eth_serdes_rx_hdr_i       ( i_eth_if.rx_hdr     ),
    .eth_serdes_rx_bitslip_o   (                     ),
    .eth_serdes_rx_reset_req_o (                     ),
    // USB full speed; VBUS always present; the D- pull-up (low speed only) is unused
    .usb_clk_i                 ( i_tb_if.usb_clk     ),
    .usb_dp_i                  ( i_usb_if.dp         ),
    .usb_dn_i                  ( i_usb_if.dn         ),
    .usb_dp_o                  ( i_usb_if.dev_dp     ),
    .usb_dp_en_o               ( i_usb_if.dev_dp_en  ),
    .usb_dn_o                  ( i_usb_if.dev_dn     ),
    .usb_dn_en_o               ( i_usb_if.dev_dn_en  ),
    .usb_sense_i               ( 1'b1                ),
    .usb_dp_pullup_o           ( i_usb_if.dev_pullup ),
    .usb_dn_pullup_o           (                     ),
    // ADC and OTP macro ports
    .adc_channel_o             ( i_adc_if.channel    ),
    .adc_dac_code_o            ( i_adc_if.dac_code   ),
    .adc_compare_i             ( i_adc_if.compare    ),
    .otp_req_o                 ( i_otp_if.req        ),
    .otp_we_o                  ( i_otp_if.we         ),
    .otp_addr_o                ( i_otp_if.addr       ),
    .otp_wdata_o               ( i_otp_if.wdata      ),
    .otp_rdata_i               ( i_otp_if.rdata      ),
    .otp_done_i                ( i_otp_if.done       ),
    // JTAG; the monitor checks TDO is enabled exactly in Shift-DR and Shift-IR
    .jtag_tck_i                ( i_jtag_if.tck       ),
    .jtag_tms_i                ( i_jtag_if.tms       ),
    .jtag_trst_ni              ( i_jtag_if.trst_n    ),
    .jtag_tdi_i                ( i_jtag_if.tdi       ),
    .jtag_tdo_o                ( i_jtag_if.tdo       ),
    .jtag_tdo_oe_o             ( i_jtag_if.tdo_oe    )
  );

  // ---- UVM: interfaces to the environment; the test is chosen with +UVM_TESTNAME ----
  `define ADR_SET_VIF(TYPE, NAME, INST) \
    uvm_config_db #(virtual TYPE)::set(null, "uvm_test_top.env", `"NAME`", INST);

  initial begin
    `ADR_SET_VIF(adr_soc_tb_if,     tb_vif,    i_tb_if)
    `ADR_SET_VIF(adr_uart_if,       uart0_vif, i_uart0_if)
    `ADR_SET_VIF(adr_uart_if,       uart1_vif, i_uart1_if)
    `ADR_SET_VIF(adr_jtag_if,       jtag_vif,  i_jtag_if)
    `ADR_SET_VIF(adr_gpio_if,       gpio_vif,  i_gpio_if)
    `ADR_SET_VIF(adr_pwm_if,        pwm_vif,   i_pwm_if)
    `ADR_SET_VIF(adr_spi_if,        spi_vif,   i_spi_if)
    `ADR_SET_VIF(adr_spi_if,        qspi_vif,  i_qspi_if)
    `ADR_SET_VIF(adr_i2c_if,        i2c_vif,   i_i2c_if)
    `ADR_SET_VIF(adr_otp_if,        otp_vif,   i_otp_if)
    `ADR_SET_VIF(adr_adc_if,        adc_vif,   i_adc_if)
    `ADR_SET_VIF(adr_eth_serdes_if, eth_vif,   i_eth_if)
    `ADR_SET_VIF(adr_usb_if,        usb_vif,   i_usb_if)
    run_test("adr_soc_base_test");
  end

  // +no_sva: the bench's own pin-level assertions off (the RTL's are not touched).
  initial
    if ($test$plusargs("no_sva")) begin
      $assertoff(0, i_uart0_if, i_uart1_if, i_spi_if, i_qspi_if, i_i2c_if);
      $display("[TB] bench assertions off (+no_sva)");
    end

  `undef ADR_SET_VIF

endmodule
