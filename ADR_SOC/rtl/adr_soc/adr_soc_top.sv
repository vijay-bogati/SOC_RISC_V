/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_soc_top.sv
 Module/class Name             : adr_soc_top
 Author                        : Vijay Bogati
 Description                   : Top level. This file only connects the subsystems; it holds no logic of its own
***************************************************************/

//   i_rst_gen       adr_rst_gen        every reset
//   i_core          adr_core_complex   CPU, CLINT, PLIC
//   i_debug         adr_debug          JTAG and the debug module
//   i_interconnect  adr_interconnect   AXI4 crossbar, error target, APB bridge
//   i_mem           adr_mem_subsys     boot ROM, SRAM, DDR4
//   i_dma           adr_dma            DMA engine
//   i_eth           adr_eth            10G/25G Ethernet
//   i_usb           adr_usb            USB 2.0 full-speed device
//   i_lsio          adr_lsio_subsys    UARTs, GPIO, SPI, QSPI, I2C, pin mux
//   i_periph        adr_periph_subsys  timer, PWM, watchdog, AES, bus monitor, system control,
//                                      ADC, OTP, always-on timer
//
// rst_ni is the power-on reset. It resets the debug module and JTAG logic, so a debugger
// stays attached while the debug module resets the rest of the SoC through sys_rst_n.
// Every reset is made in adr_rst_gen.

`include "axi/typedef.svh"

module adr_soc_top
  import adr_soc_pkg::*;
(
  input  logic clk_i,
  input  logic rst_ni,      // power-on reset
  input  logic rtc_i,       // CLINT time base; mtime counts its rising edges
  input  logic uart0_rx_i,
  output logic uart0_tx_o,
  input  logic uart1_rx_i,
  output logic uart1_tx_o,
  // GPIO
  input  logic [NumGpioPins-1:0] gpio_in_i,
  output logic [NumGpioPins-1:0] gpio_out_o,
  output logic [NumGpioPins-1:0] gpio_dir_o,  // 1: output
  // SPI
  output logic       spi_sclk_o,
  output logic [3:0] spi_csn_o,
  output logic       spi_mosi_o,
  input  logic       spi_miso_i,
  // QSPI
  output logic       qspi_sclk_o,
  output logic [3:0] qspi_csn_o,
  output logic [1:0] qspi_mode_o,  // 0: single line, 1: quad output, 2: quad input
  output logic [3:0] qspi_sdo_o,
  input  logic [3:0] qspi_sdi_i,
  // Ethernet: 64-bit data and 2-bit sync header to an external SerDes. 390.625 MHz gives 25G.
  input  logic        eth_tx_clk_i,
  input  logic        eth_rx_clk_i,
  output logic [63:0] eth_serdes_tx_data_o,
  output logic [1:0]  eth_serdes_tx_hdr_o,
  input  logic [63:0] eth_serdes_rx_data_i,
  input  logic [1:0]  eth_serdes_rx_hdr_i,
  output logic        eth_serdes_rx_bitslip_o,
  output logic        eth_serdes_rx_reset_req_o,
  // USB full-speed device, to an external transceiver. A real part needs 48 MHz on usb_clk_i.
  input  logic       usb_clk_i,
  input  logic       usb_dp_i,
  input  logic       usb_dn_i,
  output logic       usb_dp_o,
  output logic       usb_dp_en_o,
  output logic       usb_dn_o,
  output logic       usb_dn_en_o,
  input  logic       usb_sense_i,
  output logic       usb_dp_pullup_o,
  output logic       usb_dn_pullup_o,
  // I2C: open-drain, a line is released when its _t output is high
  input  logic       i2c_scl_i,
  output logic       i2c_scl_o,
  output logic       i2c_scl_t,
  input  logic       i2c_sda_i,
  output logic       i2c_sda_o,
  output logic       i2c_sda_t,
  // PWM
  output logic [NumPwmPins-1:0] pwm_o,
  // Boot configuration pins, readable by software
  input  logic [3:0] boot_pins_i,
  // ADC analog side
  output logic       adc_channel_o,
  output logic [7:0] adc_dac_code_o,
  input  logic       adc_compare_i,
  // OTP macro
  output logic        otp_req_o,
  output logic        otp_we_o,
  output logic [4:0]  otp_addr_o,
  output logic [31:0] otp_wdata_o,
  input  logic [31:0] otp_rdata_i,
  input  logic        otp_done_i,
  // JTAG debug port
  input  logic jtag_tck_i,
  input  logic jtag_tms_i,
  input  logic jtag_trst_ni,
  input  logic jtag_tdi_i,
  output logic jtag_tdo_o,
  output logic jtag_tdo_oe_o
);

  localparam config_pkg::cva6_cfg_t CpuCfg = build_config_pkg::build_config(cpu_user_cfg());

  localparam int unsigned InitIdWidth = CpuCfg.AxiIdWidth;
  localparam int unsigned TgtIdWidth  = InitIdWidth + $clog2(NumInitiators);
  localparam int unsigned UserWidth   = CpuCfg.AxiUserWidth;

  typedef logic [AddrWidth-1:0]   addr_t;
  typedef logic [DataWidth-1:0]   data_t;
  typedef logic [DataWidth/8-1:0] strb_t;
  typedef logic [InitIdWidth-1:0] init_id_t;
  typedef logic [TgtIdWidth-1:0]  tgt_id_t;
  typedef logic [UserWidth-1:0]   user_t;

  `AXI_TYPEDEF_ALL(init, addr_t, init_id_t, data_t, strb_t, user_t)
  `AXI_TYPEDEF_ALL(tgt, addr_t, tgt_id_t, data_t, strb_t, user_t)

  // AXI4 links, named initiator_to_interconnect and interconnect_to_target.
  init_req_t  cpu_req,   dma_req,   eth_req,   dbg_init_req;
  init_resp_t cpu_resp,  dma_resp,  eth_resp,  dbg_init_resp;
  tgt_req_t   rom_req,   sram_req,  ddr_req,   clint_req,  dbg_tgt_req;
  tgt_resp_t  rom_resp,  sram_resp, ddr_resp,  clint_resp, dbg_tgt_resp;

  // APB slots, decoded by the APB bridge in the interconnect.
  apb_req_t  [NumApbSlots-1:0] apb_req;
  apb_resp_t [NumApbSlots-1:0] apb_resp;

  // Resets, debug, system control and bus observation
  logic sys_rst_n, usb_rst_n, eth_tx_rst_n, eth_rx_rst_n;
  logic ndmreset, debug_req, system_reset_req;
  logic ddr_drain, ddr_idle, ddr_drain_timeout;  // DDR4 drain before a warm reset
  logic [31:0] clk_en;
  logic [NumInitiators-1:0]       read_error, write_error;
  logic [NumInitiators-1:0][63:0] last_read_addr, last_write_addr;

  // Interrupts
  logic                     uart0_irq, uart1_irq, gpio_irq, spi_irq, qspi_irq, i2c_irq;
  logic [NumTimers-1:0]     timer_irq;
  logic [3:0]               pwm_irq;
  logic                     wdt_irq, aes_irq, bus_mon_irq, adc_irq, otp_irq, aon_irq;
  logic                     dma_irq, eth_irq, usb_irq;
  logic [NumIrqSources-1:0] irq_sources;

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Resets
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  adr_rst_gen i_rst_gen (
    .clk_i,
    .rst_ni,
    .debug_reset_i      ( ndmreset         ),
    .system_reset_req_i ( system_reset_req ),
    .ddr_drain_o        ( ddr_drain        ),
    .ddr_idle_i         ( ddr_idle         ),
    .ddr_drain_timeout_o( ddr_drain_timeout),
    .usb_clk_i,
    .eth_tx_clk_i,
    .eth_rx_clk_i,
    .sys_rst_no         ( sys_rst_n        ),
    .usb_rst_no         ( usb_rst_n        ),
    .eth_tx_rst_no      ( eth_tx_rst_n     ),
    .eth_rx_rst_no      ( eth_rx_rst_n     )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Core complex: CPU, CLINT, PLIC
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  adr_core_complex #(
    .CpuCfg         ( CpuCfg         ),
    .TgtIdWidth     ( TgtIdWidth     ),
    .init_aw_chan_t ( init_aw_chan_t ),
    .init_w_chan_t  ( init_w_chan_t  ),
    .init_b_chan_t  ( init_b_chan_t  ),
    .init_ar_chan_t ( init_ar_chan_t ),
    .init_r_chan_t  ( init_r_chan_t  ),
    .init_req_t     ( init_req_t     ),
    .init_resp_t    ( init_resp_t    ),
    .tgt_req_t      ( tgt_req_t      ),
    .tgt_resp_t     ( tgt_resp_t     )
  ) i_core (
    .clk_i,
    .rst_ni          ( sys_rst_n          ),
    .rtc_i,
    .debug_req_i     ( debug_req          ),
    .cpu_req_o       ( cpu_req            ),
    .cpu_resp_i      ( cpu_resp           ),
    .clint_req_i     ( clint_req          ),
    .clint_resp_o    ( clint_resp         ),
    .plic_apb_req_i  ( apb_req[SlotPlic]  ),
    .plic_apb_resp_o ( apb_resp[SlotPlic] ),
    .irq_sources_i   ( irq_sources        )
  );

  // Interrupt sources: source n is bit n-1, numbered in adr_soc_pkg.
  always_comb begin
    irq_sources                = '0;
    irq_sources[IrqUart0 - 1]  = uart0_irq;
    irq_sources[IrqUart1 - 1]  = uart1_irq;
    irq_sources[IrqGpio - 1]   = gpio_irq;
    irq_sources[IrqSpi - 1]    = spi_irq;
    irq_sources[IrqQspi - 1]   = qspi_irq;
    irq_sources[IrqI2c - 1]    = i2c_irq;
    irq_sources[IrqWdt - 1]    = wdt_irq;
    irq_sources[IrqAes - 1]    = aes_irq;
    irq_sources[IrqBusMon - 1] = bus_mon_irq;
    irq_sources[IrqDma - 1]    = dma_irq;
    irq_sources[IrqAdc - 1]    = adc_irq;
    irq_sources[IrqOtp - 1]    = otp_irq;
    irq_sources[IrqAon - 1]    = aon_irq;
    irq_sources[IrqEth - 1]    = eth_irq;
    irq_sources[IrqUsb - 1]    = usb_irq;
    for (int i = 0; i < 4; i++) irq_sources[IrqPwm0 - 1 + i] = pwm_irq[i];
    for (int i = 0; i < int'(NumTimers); i++) irq_sources[IrqTimer0 - 1 + i] = timer_irq[i];
  end

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Debug
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  adr_debug #(
    .CpuCfg      ( CpuCfg      ),
    .TgtIdWidth  ( TgtIdWidth  ),
    .UserWidth   ( UserWidth   ),
    .tgt_req_t   ( tgt_req_t   ),
    .tgt_resp_t  ( tgt_resp_t  ),
    .init_req_t  ( init_req_t  ),
    .init_resp_t ( init_resp_t )
  ) i_debug (
    .clk_i,
    .rst_ni,
    .sys_rst_ni    ( sys_rst_n     ),
    .jtag_tck_i,
    .jtag_tms_i,
    .jtag_trst_ni,
    .jtag_tdi_i,
    .jtag_tdo_o,
    .jtag_tdo_oe_o,
    .debug_req_o   ( debug_req     ),
    .debug_reset_o ( ndmreset      ),
    .slv_req_i     ( dbg_tgt_req   ),
    .slv_resp_o    ( dbg_tgt_resp  ),
    .mst_req_o     ( dbg_init_req  ),
    .mst_resp_i    ( dbg_init_resp )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Interconnect: crossbar, error target, APB bridge, bus observation
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  adr_interconnect #(
    .InitIdWidth    ( InitIdWidth    ),
    .TgtIdWidth     ( TgtIdWidth     ),
    .UserWidth      ( UserWidth      ),
    .init_aw_chan_t ( init_aw_chan_t ),
    .init_w_chan_t  ( init_w_chan_t  ),
    .init_b_chan_t  ( init_b_chan_t  ),
    .init_ar_chan_t ( init_ar_chan_t ),
    .init_r_chan_t  ( init_r_chan_t  ),
    .init_req_t     ( init_req_t     ),
    .init_resp_t    ( init_resp_t    ),
    .tgt_aw_chan_t  ( tgt_aw_chan_t  ),
    .tgt_w_chan_t   ( tgt_w_chan_t   ),
    .tgt_b_chan_t   ( tgt_b_chan_t   ),
    .tgt_ar_chan_t  ( tgt_ar_chan_t  ),
    .tgt_r_chan_t   ( tgt_r_chan_t   ),
    .tgt_req_t      ( tgt_req_t      ),
    .tgt_resp_t     ( tgt_resp_t     )
  ) i_interconnect (
    .clk_i,
    .rst_ni            ( sys_rst_n       ),
    .cpu_req_i         ( cpu_req         ),
    .cpu_resp_o        ( cpu_resp        ),
    .debug_req_i       ( dbg_init_req    ),
    .debug_resp_o      ( dbg_init_resp   ),
    .dma_req_i         ( dma_req         ),
    .dma_resp_o        ( dma_resp        ),
    .eth_req_i         ( eth_req         ),
    .eth_resp_o        ( eth_resp        ),
    .rom_req_o         ( rom_req         ),
    .rom_resp_i        ( rom_resp        ),
    .sram_req_o        ( sram_req        ),
    .sram_resp_i       ( sram_resp       ),
    .ddr_req_o         ( ddr_req         ),
    .ddr_resp_i        ( ddr_resp        ),
    .clint_req_o       ( clint_req       ),
    .clint_resp_i      ( clint_resp      ),
    .debug_req_o       ( dbg_tgt_req     ),
    .debug_resp_i      ( dbg_tgt_resp    ),
    .clk_en_i          ( clk_en          ),
    .apb_req_o         ( apb_req         ),
    .apb_resp_i        ( apb_resp        ),
    .read_error_o      ( read_error      ),
    .write_error_o     ( write_error     ),
    .last_read_addr_o  ( last_read_addr  ),
    .last_write_addr_o ( last_write_addr )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Memories: boot ROM, SRAM, DDR4
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  adr_mem_subsys #(
    .IdWidth   ( TgtIdWidth ),
    .UserWidth ( UserWidth  ),
    .req_t     ( tgt_req_t  ),
    .resp_t    ( tgt_resp_t )
  ) i_mem (
    .clk_i,
    .rst_ni         ( sys_rst_n         ),
    .ddr_drain_i    ( ddr_drain         ),
    .ddr_idle_o     ( ddr_idle          ),
    .rom_req_i      ( rom_req           ),
    .rom_resp_o     ( rom_resp          ),
    .sram_req_i     ( sram_req          ),
    .sram_resp_o    ( sram_resp         ),
    .ddr_req_i      ( ddr_req           ),
    .ddr_resp_o     ( ddr_resp          ),
    .ddr_apb_req_i  ( apb_req[SlotDdr]  ),
    .ddr_apb_resp_o ( apb_resp[SlotDdr] )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // DMA
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  adr_dma #(
    .NumChannels ( 4           ),
    .IdWidth     ( InitIdWidth ),
    .axi_req_t   ( init_req_t  ),
    .axi_resp_t  ( init_resp_t )
  ) i_dma (
    .clk_i,
    .rst_ni     ( sys_rst_n                       ),
    .psel_i     ( apb_req[SlotDma].psel           ),
    .penable_i  ( apb_req[SlotDma].penable        ),
    .pwrite_i   ( apb_req[SlotDma].pwrite         ),
    .paddr_i    ( apb_req[SlotDma].paddr[7:0]     ),
    .pwdata_i   ( apb_req[SlotDma].pwdata         ),
    .prdata_o   ( apb_resp[SlotDma].prdata        ),
    .pready_o   ( apb_resp[SlotDma].pready        ),
    .pslverr_o  ( apb_resp[SlotDma].pslverr       ),
    .axi_req_o  ( dma_req                         ),
    .axi_resp_i ( dma_resp                        ),
    .irq_o      ( dma_irq                         )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Ethernet, on its own transmit and receive clocks. Its registers always answer at once.
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  assign apb_resp[SlotEth].pready  = 1'b1;
  assign apb_resp[SlotEth].pslverr = 1'b0;

  adr_eth #(
    .IdWidth    ( InitIdWidth ),
    .axi_req_t  ( init_req_t  ),
    .axi_resp_t ( init_resp_t )
  ) i_eth (
    .clk_i,
    .rst_ni       ( sys_rst_n                   ),
    .psel_i       ( apb_req[SlotEth].psel       ),
    .penable_i    ( apb_req[SlotEth].penable    ),
    .pwrite_i     ( apb_req[SlotEth].pwrite     ),
    .paddr_i      ( apb_req[SlotEth].paddr[7:0] ),
    .pwdata_i     ( apb_req[SlotEth].pwdata     ),
    .prdata_o     ( apb_resp[SlotEth].prdata    ),
    .axi_req_o    ( eth_req                     ),
    .axi_resp_i   ( eth_resp                    ),
    .irq_o        ( eth_irq                     ),
    .tx_clk_i     ( eth_tx_clk_i                ),
    .tx_rst_ni    ( eth_tx_rst_n                ),
    .rx_clk_i     ( eth_rx_clk_i                ),
    .rx_rst_ni    ( eth_rx_rst_n                ),
    .serdes_tx_data_o      ( eth_serdes_tx_data_o      ),
    .serdes_tx_hdr_o       ( eth_serdes_tx_hdr_o       ),
    .serdes_rx_data_i      ( eth_serdes_rx_data_i      ),
    .serdes_rx_hdr_i       ( eth_serdes_rx_hdr_i       ),
    .serdes_rx_bitslip_o   ( eth_serdes_rx_bitslip_o   ),
    .serdes_rx_reset_req_o ( eth_serdes_rx_reset_req_o )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // USB device, on its own clock
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  adr_usb i_usb (
    .clk_i,
    .rst_ni      ( sys_rst_n                    ),
    .psel_i      ( apb_req[SlotUsb].psel        ),
    .penable_i   ( apb_req[SlotUsb].penable     ),
    .pwrite_i    ( apb_req[SlotUsb].pwrite      ),
    .paddr_i     ( apb_req[SlotUsb].paddr[11:0] ),
    .pwdata_i    ( apb_req[SlotUsb].pwdata      ),
    .prdata_o    ( apb_resp[SlotUsb].prdata     ),
    .pready_o    ( apb_resp[SlotUsb].pready     ),
    .pslverr_o   ( apb_resp[SlotUsb].pslverr    ),
    .irq_o       ( usb_irq                      ),
    .usb_clk_i,
    .usb_rst_ni  ( usb_rst_n                    ),
    .dp_i        ( usb_dp_i                     ),
    .dn_i        ( usb_dn_i                     ),
    .dp_o        ( usb_dp_o                     ),
    .dp_en_o     ( usb_dp_en_o                  ),
    .dn_o        ( usb_dn_o                     ),
    .dn_en_o     ( usb_dn_en_o                  ),
    .sense_i     ( usb_sense_i                  ),
    .dp_pullup_o ( usb_dp_pullup_o              ),
    .dn_pullup_o ( usb_dn_pullup_o              )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Low-speed I/O: UARTs, GPIO, SPI, QSPI, I2C, pin mux
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  adr_lsio_subsys i_lsio (
    .clk_i,
    .rst_ni           ( sys_rst_n           ),
    .clk_en_i         ( clk_en              ),
    .uart0_apb_req_i  ( apb_req[SlotUart0]  ),
    .uart0_apb_resp_o ( apb_resp[SlotUart0] ),
    .uart1_apb_req_i  ( apb_req[SlotUart1]  ),
    .uart1_apb_resp_o ( apb_resp[SlotUart1] ),
    .gpio_apb_req_i   ( apb_req[SlotGpio]   ),
    .gpio_apb_resp_o  ( apb_resp[SlotGpio]  ),
    .spi_apb_req_i    ( apb_req[SlotSpi]    ),
    .spi_apb_resp_o   ( apb_resp[SlotSpi]   ),
    .qspi_apb_req_i   ( apb_req[SlotQspi]   ),
    .qspi_apb_resp_o  ( apb_resp[SlotQspi]  ),
    .i2c_apb_req_i    ( apb_req[SlotI2c]    ),
    .i2c_apb_resp_o   ( apb_resp[SlotI2c]   ),
    .mux_apb_req_i    ( apb_req[SlotMux]    ),
    .mux_apb_resp_o   ( apb_resp[SlotMux]   ),
    .uart0_rx_i,
    .uart0_tx_o,
    .uart1_rx_i,
    .uart1_tx_o,
    .gpio_in_i,
    .gpio_out_o,
    .gpio_dir_o,
    .pwm_i            ( pwm_o               ),
    .spi_sclk_o,
    .spi_csn_o,
    .spi_mosi_o,
    .spi_miso_i,
    .qspi_sclk_o,
    .qspi_csn_o,
    .qspi_mode_o,
    .qspi_sdo_o,
    .qspi_sdi_i,
    .i2c_scl_i,
    .i2c_scl_o,
    .i2c_scl_t,
    .i2c_sda_i,
    .i2c_sda_o,
    .i2c_sda_t,
    .uart0_irq_o      ( uart0_irq           ),
    .uart1_irq_o      ( uart1_irq           ),
    .gpio_irq_o       ( gpio_irq            ),
    .spi_irq_o        ( spi_irq             ),
    .qspi_irq_o       ( qspi_irq            ),
    .i2c_irq_o        ( i2c_irq             )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Peripherals: timer, PWM, watchdog, AES, bus monitor, system control, ADC, OTP, AON timer
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  adr_periph_subsys i_periph (
    .clk_i,
    .rst_ni             ( sys_rst_n            ),
    .por_rst_ni         ( rst_ni               ),
    .timer_apb_req_i    ( apb_req[SlotTimer]   ),
    .timer_apb_resp_o   ( apb_resp[SlotTimer]  ),
    .pwm_apb_req_i      ( apb_req[SlotPwm]     ),
    .pwm_apb_resp_o     ( apb_resp[SlotPwm]    ),
    .wdt_apb_req_i      ( apb_req[SlotWdt]     ),
    .wdt_apb_resp_o     ( apb_resp[SlotWdt]    ),
    .aes_apb_req_i      ( apb_req[SlotAes]     ),
    .aes_apb_resp_o     ( apb_resp[SlotAes]    ),
    .bus_mon_apb_req_i  ( apb_req[SlotBusMon]  ),
    .bus_mon_apb_resp_o ( apb_resp[SlotBusMon] ),
    .sys_apb_req_i      ( apb_req[SlotSys]     ),
    .sys_apb_resp_o     ( apb_resp[SlotSys]    ),
    .adc_apb_req_i      ( apb_req[SlotAdc]     ),
    .adc_apb_resp_o     ( apb_resp[SlotAdc]    ),
    .otp_apb_req_i      ( apb_req[SlotOtp]     ),
    .otp_apb_resp_o     ( apb_resp[SlotOtp]    ),
    .aon_apb_req_i      ( apb_req[SlotAon]     ),
    .aon_apb_resp_o     ( apb_resp[SlotAon]    ),
    .pwm_o,
    .rtc_i,
    .adc_channel_o,
    .adc_dac_code_o,
    .adc_compare_i,
    .otp_req_o,
    .otp_we_o,
    .otp_addr_o,
    .otp_wdata_o,
    .otp_rdata_i,
    .otp_done_i,
    .boot_pins_i,
    .debug_reset_i      ( ndmreset             ),
    .ddr_drain_timeout_i( ddr_drain_timeout    ),
    .system_reset_req_o ( system_reset_req     ),
    .clk_en_o           ( clk_en               ),
    .read_error_i       ( read_error           ),
    .write_error_i      ( write_error          ),
    .last_read_addr_i   ( last_read_addr       ),
    .last_write_addr_i  ( last_write_addr      ),
    .timer_irq_o        ( timer_irq            ),
    .pwm_irq_o          ( pwm_irq              ),
    .wdt_irq_o          ( wdt_irq              ),
    .aes_irq_o          ( aes_irq              ),
    .bus_mon_irq_o      ( bus_mon_irq          ),
    .adc_irq_o          ( adc_irq              ),
    .otp_irq_o          ( otp_irq              ),
    .aon_irq_o          ( aon_irq              )
  );

endmodule
