/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_lsio_subsys.sv
 Module/class Name             : adr_lsio_subsys
 Author                        : Vijay Bogati
 Description                   : Low-speed I/O subsystem: the serial bus interfaces and the GPIO pads
***************************************************************/

//   UART0, UART1, GPIO, SPI, QSPI, I2C, and the pin mux that shares the GPIO pads with PWM,
//   UART1 and SPI.
//
// Each block has its own APB slot from the APB bridge. UART1, GPIO, SPI, QSPI and I2C run on
// gated clocks, switched by CLK_EN in system control; UART0 carries the console and the pin mux
// holds the pad setting, so both stay on clk_i.

module adr_lsio_subsys
  import adr_soc_pkg::*;
(
  input  logic      clk_i,
  input  logic      rst_ni,      // system reset
  input  logic [31:0] clk_en_i,  // CLK_EN from system control
  // APB slots
  input  apb_req_t  uart0_apb_req_i,
  output apb_resp_t uart0_apb_resp_o,
  input  apb_req_t  uart1_apb_req_i,
  output apb_resp_t uart1_apb_resp_o,
  input  apb_req_t  gpio_apb_req_i,
  output apb_resp_t gpio_apb_resp_o,
  input  apb_req_t  spi_apb_req_i,
  output apb_resp_t spi_apb_resp_o,
  input  apb_req_t  qspi_apb_req_i,
  output apb_resp_t qspi_apb_resp_o,
  input  apb_req_t  i2c_apb_req_i,
  output apb_resp_t i2c_apb_resp_o,
  input  apb_req_t  mux_apb_req_i,
  output apb_resp_t mux_apb_resp_o,
  // UARTs
  input  logic      uart0_rx_i,
  output logic      uart0_tx_o,
  input  logic      uart1_rx_i,
  output logic      uart1_tx_o,
  // GPIO pads, through the pin mux
  input  logic [NumGpioPins-1:0] gpio_in_i,
  output logic [NumGpioPins-1:0] gpio_out_o,
  output logic [NumGpioPins-1:0] gpio_dir_o,  // 1: output
  input  logic [NumPwmPins-1:0]  pwm_i,       // PWM outputs, pin mux function 1
  // SPI master: single data line, four chip selects
  output logic       spi_sclk_o,
  output logic [3:0] spi_csn_o,
  output logic       spi_mosi_o,
  input  logic       spi_miso_i,
  // QSPI master
  output logic       qspi_sclk_o,
  output logic [3:0] qspi_csn_o,
  output logic [1:0] qspi_mode_o,  // 0: single line, 1: quad output, 2: quad input
  output logic [3:0] qspi_sdo_o,
  input  logic [3:0] qspi_sdi_i,
  // I2C master: open-drain, a line is released when its _t output is high
  input  logic       i2c_scl_i,
  output logic       i2c_scl_o,
  output logic       i2c_scl_t,
  input  logic       i2c_sda_i,
  output logic       i2c_sda_o,
  output logic       i2c_sda_t,
  // Interrupts, to the PLIC
  output logic       uart0_irq_o,
  output logic       uart1_irq_o,
  output logic       gpio_irq_o,
  output logic       spi_irq_o,   // threshold or end of transfer
  output logic       qspi_irq_o,
  output logic       i2c_irq_o
);

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Gated clocks
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic clk_uart1, clk_gpio, clk_spi, clk_qspi, clk_i2c;

  pulp_clock_gating i_gate_uart1 (
    .clk_i, .en_i ( clk_en_i[ClkUart1] ), .test_en_i ( 1'b0 ), .clk_o ( clk_uart1 ) );
  pulp_clock_gating i_gate_gpio (
    .clk_i, .en_i ( clk_en_i[ClkGpio]  ), .test_en_i ( 1'b0 ), .clk_o ( clk_gpio  ) );
  pulp_clock_gating i_gate_spi (
    .clk_i, .en_i ( clk_en_i[ClkSpi]   ), .test_en_i ( 1'b0 ), .clk_o ( clk_spi   ) );
  pulp_clock_gating i_gate_qspi (
    .clk_i, .en_i ( clk_en_i[ClkQspi]  ), .test_en_i ( 1'b0 ), .clk_o ( clk_qspi  ) );
  pulp_clock_gating i_gate_i2c (
    .clk_i, .en_i ( clk_en_i[ClkI2c]   ), .test_en_i ( 1'b0 ), .clk_o ( clk_i2c   ) );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // UARTs. Registers are word-spaced: address bits [4:2] select the register.
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  apb_uart i_uart0 (
    .CLK     ( clk_i                       ),
    .RSTN    ( rst_ni                      ),
    .PSEL    ( uart0_apb_req_i.psel        ),
    .PENABLE ( uart0_apb_req_i.penable     ),
    .PWRITE  ( uart0_apb_req_i.pwrite      ),
    .PADDR   ( uart0_apb_req_i.paddr[4:2]  ),
    .PWDATA  ( uart0_apb_req_i.pwdata      ),
    .PRDATA  ( uart0_apb_resp_o.prdata     ),
    .PREADY  ( uart0_apb_resp_o.pready     ),
    .PSLVERR ( uart0_apb_resp_o.pslverr    ),
    .INT     ( uart0_irq_o                 ),
    .OUT1N   (                             ),
    .OUT2N   (                             ),
    .RTSN    (                             ),
    .DTRN    (                             ),
    .CTSN    ( 1'b0                        ),
    .DSRN    ( 1'b0                        ),
    .DCDN    ( 1'b0                        ),
    .RIN     ( 1'b1                        ),
    .SIN     ( uart0_rx_i                  ),
    .SOUT    ( uart0_tx_o                  )
  );

  apb_uart i_uart1 (
    .CLK     ( clk_uart1                   ),
    .RSTN    ( rst_ni                      ),
    .PSEL    ( uart1_apb_req_i.psel        ),
    .PENABLE ( uart1_apb_req_i.penable     ),
    .PWRITE  ( uart1_apb_req_i.pwrite      ),
    .PADDR   ( uart1_apb_req_i.paddr[4:2]  ),
    .PWDATA  ( uart1_apb_req_i.pwdata      ),
    .PRDATA  ( uart1_apb_resp_o.prdata     ),
    .PREADY  ( uart1_apb_resp_o.pready     ),
    .PSLVERR ( uart1_apb_resp_o.pslverr    ),
    .INT     ( uart1_irq_o                 ),
    .OUT1N   (                             ),
    .OUT2N   (                             ),
    .RTSN    (                             ),
    .DTRN    (                             ),
    .CTSN    ( 1'b0                        ),
    .DSRN    ( 1'b0                        ),
    .DCDN    ( 1'b0                        ),
    .RIN     ( 1'b1                        ),
    .SIN     ( uart1_rx_i                  ),
    .SOUT    ( uart1_tx_o                  )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // GPIO
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic [NumGpioPins-1:0] gpio_core_out, gpio_core_dir;

  apb_gpio #(
    .APB_ADDR_WIDTH ( 12          ),
    .PAD_NUM        ( NumGpioPins )
  ) i_gpio (
    .HCLK            ( clk_gpio                    ),
    .HRESETn         ( rst_ni                      ),
    .dft_cg_enable_i ( 1'b0                        ),
    .PADDR           ( gpio_apb_req_i.paddr[11:0]  ),
    .PWDATA          ( gpio_apb_req_i.pwdata       ),
    .PWRITE          ( gpio_apb_req_i.pwrite       ),
    .PSEL            ( gpio_apb_req_i.psel         ),
    .PENABLE         ( gpio_apb_req_i.penable      ),
    .PRDATA          ( gpio_apb_resp_o.prdata      ),
    .PREADY          ( gpio_apb_resp_o.pready      ),
    .PSLVERR         ( gpio_apb_resp_o.pslverr     ),
    .gpio_in         ( gpio_in_i                   ),
    .gpio_in_sync    (                             ),
    .gpio_out        ( gpio_core_out               ),
    .gpio_dir        ( gpio_core_dir               ),
    .gpio_padcfg     (                             ),
    .interrupt       ( gpio_irq_o                  )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // SPI and QSPI
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic [1:0] spi_events, qspi_events;  // threshold, end of transfer
  assign spi_irq_o  = |spi_events;
  assign qspi_irq_o = |qspi_events;

  apb_spi_master #(
    .BUFFER_DEPTH   ( 10 ),
    .APB_ADDR_WIDTH ( 12 )
  ) i_spi (
    .HCLK     ( clk_spi                    ),
    .HRESETn  ( rst_ni                     ),
    .PADDR    ( spi_apb_req_i.paddr[11:0]  ),
    .PWDATA   ( spi_apb_req_i.pwdata       ),
    .PWRITE   ( spi_apb_req_i.pwrite       ),
    .PSEL     ( spi_apb_req_i.psel         ),
    .PENABLE  ( spi_apb_req_i.penable      ),
    .PRDATA   ( spi_apb_resp_o.prdata      ),
    .PREADY   ( spi_apb_resp_o.pready      ),
    .PSLVERR  ( spi_apb_resp_o.pslverr     ),
    .events_o ( spi_events                 ),
    .spi_clk  ( spi_sclk_o                 ),
    .spi_csn0 ( spi_csn_o[0]               ),
    .spi_csn1 ( spi_csn_o[1]               ),
    .spi_csn2 ( spi_csn_o[2]               ),
    .spi_csn3 ( spi_csn_o[3]               ),
    .spi_mode (                            ),
    .spi_sdo0 ( spi_mosi_o                 ),
    .spi_sdo1 (                            ),
    .spi_sdo2 (                            ),
    .spi_sdo3 (                            ),
    .spi_sdi0 ( 1'b0                       ),
    .spi_sdi1 ( spi_miso_i                 ),
    .spi_sdi2 ( 1'b0                       ),
    .spi_sdi3 ( 1'b0                       )
  );

  apb_spi_master #(
    .BUFFER_DEPTH   ( 10 ),
    .APB_ADDR_WIDTH ( 12 )
  ) i_qspi (
    .HCLK     ( clk_qspi                   ),
    .HRESETn  ( rst_ni                     ),
    .PADDR    ( qspi_apb_req_i.paddr[11:0] ),
    .PWDATA   ( qspi_apb_req_i.pwdata      ),
    .PWRITE   ( qspi_apb_req_i.pwrite      ),
    .PSEL     ( qspi_apb_req_i.psel        ),
    .PENABLE  ( qspi_apb_req_i.penable     ),
    .PRDATA   ( qspi_apb_resp_o.prdata     ),
    .PREADY   ( qspi_apb_resp_o.pready     ),
    .PSLVERR  ( qspi_apb_resp_o.pslverr    ),
    .events_o ( qspi_events                ),
    .spi_clk  ( qspi_sclk_o                ),
    .spi_csn0 ( qspi_csn_o[0]              ),
    .spi_csn1 ( qspi_csn_o[1]              ),
    .spi_csn2 ( qspi_csn_o[2]              ),
    .spi_csn3 ( qspi_csn_o[3]              ),
    .spi_mode ( qspi_mode_o                ),
    .spi_sdo0 ( qspi_sdo_o[0]              ),
    .spi_sdo1 ( qspi_sdo_o[1]              ),
    .spi_sdo2 ( qspi_sdo_o[2]              ),
    .spi_sdo3 ( qspi_sdo_o[3]              ),
    .spi_sdi0 ( qspi_sdi_i[0]              ),
    .spi_sdi1 ( qspi_sdi_i[1]              ),
    .spi_sdi2 ( qspi_sdi_i[2]              ),
    .spi_sdi3 ( qspi_sdi_i[3]              )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // I2C master: verilog-i2c engine and FIFOs behind our APB register block
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  adr_i2c i_i2c (
    .clk_i     ( clk_i2c                   ),
    .rst_ni,
    .psel_i    ( i2c_apb_req_i.psel        ),
    .penable_i ( i2c_apb_req_i.penable     ),
    .pwrite_i  ( i2c_apb_req_i.pwrite      ),
    .paddr_i   ( i2c_apb_req_i.paddr[4:0]  ),
    .pwdata_i  ( i2c_apb_req_i.pwdata      ),
    .pstrb_i   ( i2c_apb_req_i.pstrb       ),
    .prdata_o  ( i2c_apb_resp_o.prdata     ),
    .pready_o  ( i2c_apb_resp_o.pready     ),
    .pslverr_o ( i2c_apb_resp_o.pslverr    ),
    .irq_o     ( i2c_irq_o                 ),
    .scl_i     ( i2c_scl_i                 ),
    .scl_o     ( i2c_scl_o                 ),
    .scl_t     ( i2c_scl_t                 ),
    .sda_i     ( i2c_sda_i                 ),
    .sda_o     ( i2c_sda_o                 ),
    .sda_t     ( i2c_sda_t                 )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Pin mux: function 1 is PWM on pads 0-7; function 2 is UART1 TX and SPI on pads 0-3.
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic [NumGpioPins-1:0] func1_out, func1_dir, func2_out, func2_dir;
  assign func1_out = NumGpioPins'(pwm_i);
  assign func1_dir = NumGpioPins'(8'hFF);
  assign func2_out = NumGpioPins'({spi_mosi_o, spi_csn_o[0], spi_sclk_o, uart1_tx_o});
  assign func2_dir = NumGpioPins'(4'hF);

  adr_pinmux #(
    .NumPads ( NumGpioPins )
  ) i_pinmux (
    .clk_i,
    .rst_ni,
    .psel_i      ( mux_apb_req_i.psel       ),
    .penable_i   ( mux_apb_req_i.penable    ),
    .pwrite_i    ( mux_apb_req_i.pwrite     ),
    .paddr_i     ( mux_apb_req_i.paddr[2:0] ),
    .pwdata_i    ( mux_apb_req_i.pwdata     ),
    .prdata_o    ( mux_apb_resp_o.prdata    ),
    .pready_o    ( mux_apb_resp_o.pready    ),
    .pslverr_o   ( mux_apb_resp_o.pslverr   ),
    .gpio_out_i  ( gpio_core_out            ),
    .gpio_dir_i  ( gpio_core_dir            ),
    .func1_out_i ( func1_out                ),
    .func1_dir_i ( func1_dir                ),
    .func2_out_i ( func2_out                ),
    .func2_dir_i ( func2_dir                ),
    .pad_out_o   ( gpio_out_o               ),
    .pad_dir_o   ( gpio_dir_o               )
  );

endmodule
