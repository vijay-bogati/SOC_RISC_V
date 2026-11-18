/***************************************************************
 Project name                  : ADR SoC
 File Name                     : tb_adr_soc.sv
 Module/class Name             : tb_adr_soc
 Author                        : Vijay Bogati
 Description                   : SoC testbench: the DUT, pad wiring, device models and UART0 decoding, shared by every test
***************************************************************/

// Decodes UART0 transmit data and prints it. Software ends the run by sending
// one control character: EOT (0x04) for pass, NAK (0x15) for fail.
// Every constant is in adr_tb_pkg.

module tb_adr_soc
  import adr_tb_pkg::*;
(
  input  logic clk_i,
  input  logic rst_ni,
  output logic done_o,
  output logic pass_o,
  input  logic jtag_tck_i,
  input  logic jtag_tms_i,
  input  logic jtag_trst_ni,
  input  logic jtag_tdi_i,
  output logic jtag_tdo_o
);

  timeunit 1ns;
  timeprecision 1ps;

  logic uart_tx;

  // Time base for the CLINT: one rising edge every 2**RtcDivBits clocks.
  logic [RtcDivBits-1:0] rtc_count;
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) rtc_count <= '0;
    else         rtc_count <= rtc_count + 1'b1;
  end

  // Loopbacks: UART1 transmits to itself, GPIO pins 0-7 drive pins 8-15,
  // and PWM outputs drive GPIO inputs 0-7 so software can measure them.
  logic        uart1_loop;
  logic [15:0] gpio_out;
  logic [15:0] gpio_dir;
  logic [15:0] gpio_in;
  logic [7:0]  pwm;
  assign gpio_in = {gpio_out[7:0] & gpio_dir[7:0], pwm};

  // SPI memory models. SPI uses one data line; QSPI can also use four.
  logic       spi_sclk, spi_mosi, spi_miso;
  logic       qspi_sclk;
  logic [3:0] spi_csn, qspi_csn, qspi_sdo, qspi_sdi;
  logic [3:0] spi_sdi;
  logic [1:0] qspi_mode;
  assign spi_miso = spi_sdi[1];

  adr_tb_spi_mem #(.DeviceId(SpiDeviceId)) i_spi_mem (
    .clk_i, .rst_ni, .csn_i(spi_csn[0]), .sclk_i(spi_sclk), .quad_i(1'b0),
    .sdo_i({3'b000, spi_mosi}), .sdi_o(spi_sdi));
  adr_tb_spi_mem #(.DeviceId(QspiDeviceId)) i_qspi_mem (
    .clk_i, .rst_ni, .csn_i(qspi_csn[0]), .sclk_i(qspi_sclk), .quad_i(qspi_mode != 2'b00),
    .sdo_i(qspi_sdo), .sdi_o(qspi_sdi));

  // I2C bus: open-drain wired-AND, with one register device.
  logic i2c_scl_o, i2c_scl_t, i2c_sda_o, i2c_sda_t;
  logic dev_sda_low;
  logic i2c_scl, i2c_sda;
  assign i2c_scl = i2c_scl_o | i2c_scl_t;
  assign i2c_sda = (i2c_sda_o | i2c_sda_t) & ~dev_sda_low;

  adr_tb_i2c_dev #(.DeviceAddr(I2cDeviceAddr)) i_i2c_dev (
    .clk_i, .rst_ni, .scl_i(i2c_scl), .sda_i(i2c_sda), .sda_low_o(dev_sda_low));

  // Ethernet: looped back at the SerDes interface, on one SerDes clock: 390.625 MHz (25G), or
  // 156.25 MHz (10G) with ETH_RATE=10 (see EthHalfPeriod in adr_tb_pkg).
  // No edge of it lands on a rising edge of clk_i, so both simulators cross the clock domains
  // in the same way.
  logic        eth_clk = 1'b0;
  logic [63:0] eth_serdes_data;
  logic [1:0]  eth_serdes_hdr;
  always #(EthHalfPeriod) eth_clk = ~eth_clk;

  // USB: a host model on the bus, with a pull-down on D- and D+ pulled up by the device.
  // The clock is 48 MHz and a bit lasts four of them (12 Mbit/s). Its edges don't land on rising
  // edges of clk_i either.
  logic usb_clk = 1'b0;
  logic usb_dev_dp, usb_dev_dn, usb_dev_dp_en, usb_dev_dn_en, usb_pullup;
  logic usb_host_drive, usb_host_dp, usb_host_dn;
  logic usb_dp, usb_dn;
  always #(UsbHalfPeriod) usb_clk = ~usb_clk;
  assign usb_dp = usb_dev_dp_en ? usb_dev_dp : (usb_host_drive ? usb_host_dp : usb_pullup);
  assign usb_dn = usb_dev_dn_en ? usb_dev_dn : (usb_host_drive ? usb_host_dn : 1'b0);

  adr_tb_usb_host i_usb_host (
    .clk_i       ( usb_clk        ),
    .rst_ni,
    .connect_i   ( usb_pullup     ),
    .dp_i        ( usb_dp         ),
    .dn_i        ( usb_dn         ),
    .dev_drive_i ( usb_dev_dp_en  ),
    .drive_o     ( usb_host_drive ),
    .dp_o        ( usb_host_dp    ),
    .dn_o        ( usb_host_dn    )
  );

  // ADC analog model: fixed input levels on the two channels.
  logic       adc_channel, adc_compare;
  logic [7:0] adc_dac_code;
  assign adc_compare = (adc_channel ? AdcLevelCh1 : AdcLevelCh0) >= adc_dac_code;

  // OTP macro model.
  logic        otp_req, otp_we, otp_done;
  logic [4:0]  otp_addr;
  logic [31:0] otp_wdata, otp_rdata;
  adr_tb_otp_macro i_otp_macro (
    .clk_i, .req_i(otp_req), .we_i(otp_we), .addr_i(otp_addr),
    .wdata_i(otp_wdata), .rdata_o(otp_rdata), .done_o(otp_done));

  adr_soc_top i_dut (
    .clk_i,
    .rst_ni,
    .rtc_i      ( rtc_count[RtcDivBits-1] ),
    .uart0_rx_i ( 1'b1         ),
    .uart0_tx_o ( uart_tx      ),
    .uart1_rx_i ( uart1_loop   ),
    .uart1_tx_o ( uart1_loop   ),
    .gpio_in_i  ( gpio_in      ),
    .gpio_out_o ( gpio_out     ),
    .gpio_dir_o ( gpio_dir     ),
    .spi_sclk_o ( spi_sclk ),
    .spi_csn_o  ( spi_csn  ),
    .spi_mosi_o ( spi_mosi ),
    .spi_miso_i ( spi_miso ),
    .qspi_sclk_o ( qspi_sclk ),
    .qspi_csn_o  ( qspi_csn  ),
    .qspi_mode_o ( qspi_mode ),
    .qspi_sdo_o  ( qspi_sdo  ),
    .qspi_sdi_i  ( qspi_sdi  ),
    .eth_tx_clk_i              ( eth_clk         ),
    .eth_rx_clk_i              ( eth_clk         ),
    .eth_serdes_tx_data_o      ( eth_serdes_data ),
    .eth_serdes_tx_hdr_o       ( eth_serdes_hdr  ),
    .eth_serdes_rx_data_i      ( eth_serdes_data ),
    .eth_serdes_rx_hdr_i       ( eth_serdes_hdr  ),
    .eth_serdes_rx_bitslip_o   (                 ),
    .eth_serdes_rx_reset_req_o (                 ),
    .usb_clk_i       ( usb_clk       ),
    .usb_dp_i        ( usb_dp        ),
    .usb_dn_i        ( usb_dn        ),
    .usb_dp_o        ( usb_dev_dp    ),
    .usb_dp_en_o     ( usb_dev_dp_en ),
    .usb_dn_o        ( usb_dev_dn    ),
    .usb_dn_en_o     ( usb_dev_dn_en ),
    .usb_sense_i     ( 1'b1          ),
    .usb_dp_pullup_o ( usb_pullup    ),
    .usb_dn_pullup_o (               ),
    .i2c_scl_i   ( i2c_scl   ),
    .i2c_scl_o,
    .i2c_scl_t,
    .i2c_sda_i   ( i2c_sda   ),
    .i2c_sda_o,
    .i2c_sda_t,
    .pwm_o       ( pwm       ),
    .boot_pins_i ( BootPins  ),
    .adc_channel_o  ( adc_channel  ),
    .adc_dac_code_o ( adc_dac_code ),
    .adc_compare_i  ( adc_compare  ),
    .otp_req_o      ( otp_req      ),
    .otp_we_o       ( otp_we       ),
    .otp_addr_o     ( otp_addr     ),
    .otp_wdata_o    ( otp_wdata    ),
    .otp_rdata_i    ( otp_rdata    ),
    .otp_done_i     ( otp_done     ),
    .jtag_tck_i,
    .jtag_tms_i,
    .jtag_trst_ni,
    .jtag_tdi_i,
    .jtag_tdo_o,
    .jtag_tdo_oe_o ()
  );

  typedef enum logic [1:0] { Idle, Start, Data, Stop } rx_state_e;

  rx_state_e    state;
  int unsigned  count;
  int unsigned  bit_idx;
  logic [7:0]   shift;
  longint       cycles;
  longint       max_cycles;

  // verilator lint_off BLKSEQ
  initial begin
    if (!$value$plusargs("max_cycles=%d", max_cycles)) max_cycles = DefaultMaxCycles;
  end
  // verilator lint_on BLKSEQ

`ifdef ADR_TB_TRACE
  // Optional log of CPU bus activity: +define+ADR_TB_TRACE at build time.
  always_ff @(posedge clk_i) begin
    if (rst_ni) begin
      if (i_dut.i_interconnect.init_req[0].ar_valid && i_dut.i_interconnect.init_resp[0].ar_ready)
        $display("%0d AR addr=%h len=%0d size=%0d", cycles, i_dut.i_interconnect.init_req[0].ar.addr,
                 i_dut.i_interconnect.init_req[0].ar.len, i_dut.i_interconnect.init_req[0].ar.size);
      if (i_dut.i_interconnect.init_req[0].aw_valid && i_dut.i_interconnect.init_resp[0].aw_ready)
        $display("%0d AW addr=%h len=%0d size=%0d atop=%h", cycles, i_dut.i_interconnect.init_req[0].aw.addr,
                 i_dut.i_interconnect.init_req[0].aw.len, i_dut.i_interconnect.init_req[0].aw.size, i_dut.i_interconnect.init_req[0].aw.atop);
      if (i_dut.i_interconnect.init_resp[0].r_valid && i_dut.i_interconnect.init_req[0].r_ready)
        $display("%0d  R data=%h resp=%0d last=%b", cycles, i_dut.i_interconnect.init_resp[0].r.data,
                 i_dut.i_interconnect.init_resp[0].r.resp, i_dut.i_interconnect.init_resp[0].r.last);
      if (i_dut.i_interconnect.init_resp[0].b_valid && i_dut.i_interconnect.init_req[0].b_ready)
        $display("%0d  B resp=%0d", cycles, i_dut.i_interconnect.init_resp[0].b.resp);
      if (i_dut.apb_req[0].psel && i_dut.apb_req[0].penable &&
          i_dut.apb_resp[0].pready)
        $display("%0d APB %s addr=%h wdata=%h strb=%b rdata=%h err=%b", cycles,
                 i_dut.apb_req[0].pwrite ? "WR" : "RD",
                 i_dut.apb_req[0].paddr, i_dut.apb_req[0].pwdata,
                 i_dut.apb_req[0].pstrb, i_dut.apb_resp[0].prdata,
                 i_dut.apb_resp[0].pslverr);
    end
  end
`endif

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state   <= Idle;
      count   <= 0;
      bit_idx <= 0;
      shift   <= '0;
      cycles  <= 0;
      done_o  <= 1'b0;
      pass_o  <= 1'b0;
    end else begin
      cycles <= cycles + 1;
      if (cycles == max_cycles && !done_o) begin
        $display("\n[TB] TIMEOUT after %0d cycles", cycles);
        done_o <= 1'b1;
      end
      unique case (state)
        Idle: if (!uart_tx) begin
          state <= Start;
          count <= UartCyclesPerBit / 2 - 1;
        end
        Start: begin
          if (count == 0) begin
            state   <= uart_tx ? Idle : Data;
            count   <= UartCyclesPerBit - 1;
            bit_idx <= 0;
          end else count <= count - 1;
        end
        Data: begin
          if (count == 0) begin
            shift <= {uart_tx, shift[7:1]};
            count <= UartCyclesPerBit - 1;
            if (bit_idx == 7) state <= Stop;
            bit_idx <= bit_idx + 1;
          end else count <= count - 1;
        end
        Stop: begin
          if (count == 0) begin
            state <= Idle;
            if (shift == EndPass) begin
              $display("\n[TB] RESULT: PASS (%0d cycles)", cycles);
              pass_o <= 1'b1;
              done_o <= 1'b1;
            end else if (shift == EndFail) begin
              $display("\n[TB] RESULT: FAIL (%0d cycles)", cycles);
              done_o <= 1'b1;
            end else begin
              $write("%c", shift);
              $fflush();
            end
          end else count <= count - 1;
        end
        default: state <= Idle;
      endcase
    end
  end

endmodule
