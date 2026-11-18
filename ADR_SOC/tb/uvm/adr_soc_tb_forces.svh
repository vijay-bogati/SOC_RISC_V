/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_soc_tb_forces.svh
 Module/class Name             : included in adr_soc_uvm_top
 Author                        : Vijay Bogati
 Description                   : UVM bench board: run-time loopbacks (transmit to receive) and the fixed board wiring between chip pins and interfaces
***************************************************************/

// UVM bench only (a simulator with UVM 1.2). `include'd inside module adr_soc_uvm_top, so it uses the top's
// names directly; it is not a module and is not in the file list. It must come before the chip
// instance, which connects to the board signals declared here.
// Run-time arguments, all off by default (the VIP drivers then feed the chip):
//   +loopback_uart1  UART1 transmit to UART1 receive
//   +loopback_gpio   GPIO pins 0-7 to GPIO inputs 8-15, where the pins are outputs
//   +loopback_pwm    PWM outputs to GPIO inputs 0-7
//   +loopback_eth    SerDes transmit (data and sync header) to SerDes receive
//   +loopback_all    all of them
// These are procedural assignments, not force statements. The environment reads the same
// arguments (read_loopbacks) to make the agent of a looped interface passive.
//
// The second part is the fixed board wiring that no test changes. The chip has no pad ring: its
// pins are core-level (separate output, enable and input), so the bench does what pads and the
// PCB would do. With a pad ring in the chip (inout pads), this part shrinks to wires and pull-ups.

// ---- Board signals: chip pins with no single interface signal; the chip instance in the top
// uses them, so this file is included before it ----
logic       uart1_rx;                // UART1 receive: transmit side or the UART1 driver
logic [1:0] qspi_mode;               // QSPI mode, gives the agent's quad flag
logic [7:0] gpio_in_hi, gpio_in_lo;  // GPIO inputs 15-8 and 7-0, one procedural assign each
assign i_gpio_if.in = {gpio_in_hi, gpio_in_lo};

// ---- Loopbacks ----
initial begin : tb_forces
  // UART1
  if ($test$plusargs("loopback_uart1") || $test$plusargs("loopback_all"))
    assign uart1_rx = i_uart1_if.tx;
  else
    assign uart1_rx = i_uart1_if.rx;

  // GPIO inputs 15-8
  if ($test$plusargs("loopback_gpio") || $test$plusargs("loopback_all"))
    assign gpio_in_hi = i_gpio_if.out[7:0] & i_gpio_if.dir[7:0];
  else
    assign gpio_in_hi = i_gpio_if.drv_in[15:8];

  // GPIO inputs 7-0
  if ($test$plusargs("loopback_pwm") || $test$plusargs("loopback_all"))
    assign gpio_in_lo = i_pwm_if.pwm;
  else
    assign gpio_in_lo = i_gpio_if.drv_in[7:0];

  // Ethernet
  if ($test$plusargs("loopback_eth") || $test$plusargs("loopback_all")) begin
    assign i_eth_if.rx_data = i_eth_if.tx_data;
    assign i_eth_if.rx_hdr  = i_eth_if.tx_hdr;
  end else begin
    assign i_eth_if.rx_data = i_eth_if.drv_data;
    assign i_eth_if.rx_hdr  = i_eth_if.drv_hdr;
  end
end

// ---- Fixed board wiring (continuous assignments) ----
// SPI: one data line each way; the chip drives MOSI on line 0 of the agent's four (in the top),
// lines 1-3 are unused (MISO is line 1 of sdi, also in the top)
assign i_spi_if.sdo[3:1] = 3'b000;
assign i_spi_if.quad = 1'b0;

// QSPI: quad when the master's mode is not single
assign i_qspi_if.quad = (qspi_mode != 2'b00);

// I2C: open-drain wired-AND of the master's pins and the slave agent's pull-downs (SCL low for
// clock stretching, SDA low for acknowledge and read data)
assign i_i2c_if.scl = (i_i2c_if.mst_scl_o | i_i2c_if.mst_scl_t) & ~i_i2c_if.scl_low;
assign i_i2c_if.sda = (i_i2c_if.mst_sda_o | i_i2c_if.mst_sda_t) & ~i_i2c_if.sda_low;

// USB: the device's drivers, else the host driver, else D+ pulled up by the device and D- down
assign i_usb_if.dp = i_usb_if.dev_dp_en ? i_usb_if.dev_dp
                                        : (i_usb_if.host_drive ? i_usb_if.host_dp : i_usb_if.dev_pullup);
assign i_usb_if.dn = i_usb_if.dev_dn_en ? i_usb_if.dev_dn
                                        : (i_usb_if.host_drive ? i_usb_if.host_dn : 1'b0);
