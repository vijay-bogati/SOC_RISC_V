/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_periph_subsys.sv
 Module/class Name             : adr_periph_subsys
 Author                        : Vijay Bogati
 Description                   : Peripheral subsystem: timers, security, system control and the analog-side blocks
***************************************************************/

//   timer, PWM, watchdog, AES, bus error monitor, system control, ADC controller,
//   OTP controller, always-on timer, and the synchronizers on the asynchronous inputs.
//
// Each block has its own APB slot from the APB bridge. System control holds CLK_EN, which
// gates the timer, PWM, AES and ADC clocks here and the low-speed I/O clocks in adr_lsio_subsys.

module adr_periph_subsys
  import adr_soc_pkg::*;
(
  input  logic      clk_i,
  input  logic      rst_ni,      // system reset
  input  logic      por_rst_ni,  // power-on reset, for state that survives system resets
  // APB slots
  input  apb_req_t  timer_apb_req_i,
  output apb_resp_t timer_apb_resp_o,
  input  apb_req_t  pwm_apb_req_i,
  output apb_resp_t pwm_apb_resp_o,
  input  apb_req_t  wdt_apb_req_i,
  output apb_resp_t wdt_apb_resp_o,
  input  apb_req_t  aes_apb_req_i,
  output apb_resp_t aes_apb_resp_o,
  input  apb_req_t  bus_mon_apb_req_i,
  output apb_resp_t bus_mon_apb_resp_o,
  input  apb_req_t  sys_apb_req_i,
  output apb_resp_t sys_apb_resp_o,
  input  apb_req_t  adc_apb_req_i,
  output apb_resp_t adc_apb_resp_o,
  input  apb_req_t  otp_apb_req_i,
  output apb_resp_t otp_apb_resp_o,
  input  apb_req_t  aon_apb_req_i,
  output apb_resp_t aon_apb_resp_o,
  // PWM outputs, to the pins and the pin mux
  output logic [NumPwmPins-1:0] pwm_o,
  // Always-on timer clock
  input  logic rtc_i,
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
  // System control
  input  logic [3:0]  boot_pins_i,
  input  logic        debug_reset_i,
  input  logic        ddr_drain_timeout_i,
  output logic        system_reset_req_o,
  output logic [31:0] clk_en_o,
  // Bus error monitor inputs, one per crossbar initiator
  input  logic [NumInitiators-1:0]       read_error_i,
  input  logic [NumInitiators-1:0]       write_error_i,
  input  logic [NumInitiators-1:0][63:0] last_read_addr_i,
  input  logic [NumInitiators-1:0][63:0] last_write_addr_i,
  // Interrupts, to the PLIC
  output logic [NumTimers-1:0] timer_irq_o,  // overflow or compare, one per timer
  output logic [3:0]           pwm_irq_o,    // one per PWM timer
  output logic                 wdt_irq_o,
  output logic                 aes_irq_o,
  output logic                 bus_mon_irq_o,
  output logic                 adc_irq_o,
  output logic                 otp_irq_o,
  output logic                 aon_irq_o
);

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Gated clocks
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic clk_timer, clk_pwm, clk_aes, clk_adc;

  pulp_clock_gating i_gate_timer (
    .clk_i, .en_i ( clk_en_o[ClkTimer] ), .test_en_i ( 1'b0 ), .clk_o ( clk_timer ) );
  pulp_clock_gating i_gate_pwm (
    .clk_i, .en_i ( clk_en_o[ClkPwm]   ), .test_en_i ( 1'b0 ), .clk_o ( clk_pwm   ) );
  pulp_clock_gating i_gate_aes (
    .clk_i, .en_i ( clk_en_o[ClkAes]   ), .test_en_i ( 1'b0 ), .clk_o ( clk_aes   ) );
  pulp_clock_gating i_gate_adc (
    .clk_i, .en_i ( clk_en_o[ClkAdc]   ), .test_en_i ( 1'b0 ), .clk_o ( clk_adc   ) );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Synchronizers: these inputs come from outside, with no relation to clk_i.
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic [3:0] boot_pins_sync;
  logic       adc_compare_sync;

  for (genvar i = 0; i < 4; i++) begin : gen_boot_sync
    sync i_sync (
      .clk_i,
      .rst_ni,
      .serial_i ( boot_pins_i[i]    ),
      .serial_o ( boot_pins_sync[i] )
    );
  end

  sync i_adc_compare_sync (
    .clk_i,
    .rst_ni,
    .serial_i ( adc_compare_i    ),
    .serial_o ( adc_compare_sync )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Timer: 8 channels, each with an overflow and a compare pulse
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic [2*NumTimers-1:0] timer_events;

  for (genvar i = 0; i < int'(NumTimers); i++) begin : gen_timer_irq
    assign timer_irq_o[i] = timer_events[2*i] | timer_events[2*i + 1];
  end

  apb_timer #(
    .APB_ADDR_WIDTH ( 12        ),
    .TIMER_CNT      ( NumTimers )
  ) i_timer (
    .HCLK    ( clk_timer                    ),
    .HRESETn ( rst_ni                       ),
    .PADDR   ( timer_apb_req_i.paddr[11:0]  ),
    .PWDATA  ( timer_apb_req_i.pwdata       ),
    .PWRITE  ( timer_apb_req_i.pwrite       ),
    .PSEL    ( timer_apb_req_i.psel         ),
    .PENABLE ( timer_apb_req_i.penable      ),
    .PRDATA  ( timer_apb_resp_o.prdata      ),
    .PREADY  ( timer_apb_resp_o.pready      ),
    .PSLVERR ( timer_apb_resp_o.pslverr     ),
    .irq_o   ( timer_events                 )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // PWM: four timers, each with independent period, driving two output pins.
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic [3:0] pwm_ch [4];
  assign pwm_o = {pwm_ch[3][1:0], pwm_ch[2][1:0], pwm_ch[1][1:0], pwm_ch[0][1:0]};

  apb_adv_timer #(
    .APB_ADDR_WIDTH ( 12 ),
    .EXTSIG_NUM     ( 32 ),
    .TIMER_NBITS    ( 16 )
  ) i_pwm (
    .HCLK            ( clk_pwm                    ),
    .HRESETn         ( rst_ni                     ),
    .PADDR           ( pwm_apb_req_i.paddr[11:0]  ),
    .PWDATA          ( pwm_apb_req_i.pwdata       ),
    .PWRITE          ( pwm_apb_req_i.pwrite       ),
    .PSEL            ( pwm_apb_req_i.psel         ),
    .PENABLE         ( pwm_apb_req_i.penable      ),
    .PRDATA          ( pwm_apb_resp_o.prdata      ),
    .PREADY          ( pwm_apb_resp_o.pready      ),
    .PSLVERR         ( pwm_apb_resp_o.pslverr     ),
    .dft_cg_enable_i ( 1'b0                       ),
    .low_speed_clk_i ( 1'b0                       ),
    .ext_sig_i       ( '0                         ),
    .events_o        ( pwm_irq_o                  ),
    .ch_0_o          ( pwm_ch[0]                  ),
    .ch_1_o          ( pwm_ch[1]                  ),
    .ch_2_o          ( pwm_ch[2]                  ),
    .ch_3_o          ( pwm_ch[3]                  )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Watchdog and AES
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic wdt_reset_req;

  adr_wdt i_wdt (
    .clk_i,
    .rst_ni,
    .psel_i      ( wdt_apb_req_i.psel       ),
    .penable_i   ( wdt_apb_req_i.penable    ),
    .pwrite_i    ( wdt_apb_req_i.pwrite     ),
    .paddr_i     ( wdt_apb_req_i.paddr[4:0] ),
    .pwdata_i    ( wdt_apb_req_i.pwdata     ),
    .prdata_o    ( wdt_apb_resp_o.prdata    ),
    .pready_o    ( wdt_apb_resp_o.pready    ),
    .pslverr_o   ( wdt_apb_resp_o.pslverr   ),
    .irq_o       ( wdt_irq_o                ),
    .reset_req_o ( wdt_reset_req            )
  );

  adr_aes i_aes (
    .clk_i     ( clk_aes                  ),
    .rst_ni,
    .psel_i    ( aes_apb_req_i.psel       ),
    .penable_i ( aes_apb_req_i.penable    ),
    .pwrite_i  ( aes_apb_req_i.pwrite     ),
    .paddr_i   ( aes_apb_req_i.paddr[6:0] ),
    .pwdata_i  ( aes_apb_req_i.pwdata     ),
    .prdata_o  ( aes_apb_resp_o.prdata    ),
    .pready_o  ( aes_apb_resp_o.pready    ),
    .pslverr_o ( aes_apb_resp_o.pslverr   ),
    .irq_o     ( aes_irq_o                )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Bus error monitor and system control
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  adr_bus_monitor #(
    .NumInitiators ( NumInitiators )
  ) i_bus_monitor (
    .clk_i,
    .rst_ni,
    .psel_i      ( bus_mon_apb_req_i.psel       ),
    .penable_i   ( bus_mon_apb_req_i.penable    ),
    .pwrite_i    ( bus_mon_apb_req_i.pwrite     ),
    .paddr_i     ( bus_mon_apb_req_i.paddr[3:0] ),
    .pwdata_i    ( bus_mon_apb_req_i.pwdata     ),
    .prdata_o    ( bus_mon_apb_resp_o.prdata    ),
    .pready_o    ( bus_mon_apb_resp_o.pready    ),
    .pslverr_o   ( bus_mon_apb_resp_o.pslverr   ),
    .read_error_i,
    .write_error_i,
    .last_read_addr_i,
    .last_write_addr_i,
    .irq_o       ( bus_mon_irq_o                )
  );

  adr_sysctrl i_sysctrl (
    .clk_i,
    .por_rst_ni,
    .sys_rst_ni    ( rst_ni                   ),
    .psel_i        ( sys_apb_req_i.psel       ),
    .penable_i     ( sys_apb_req_i.penable    ),
    .pwrite_i      ( sys_apb_req_i.pwrite     ),
    .paddr_i       ( sys_apb_req_i.paddr[4:0] ),
    .pwdata_i      ( sys_apb_req_i.pwdata     ),
    .prdata_o      ( sys_apb_resp_o.prdata    ),
    .pready_o      ( sys_apb_resp_o.pready    ),
    .pslverr_o     ( sys_apb_resp_o.pslverr   ),
    .boot_pins_i   ( boot_pins_sync           ),
    .debug_reset_i,
    .wdt_reset_i   ( wdt_reset_req            ),
    .ddr_drain_timeout_i,
    .system_reset_req_o,
    .clk_en_o
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // ADC controller, OTP controller, always-on timer
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  adr_adc_ctrl i_adc (
    .clk_i       ( clk_adc                  ),
    .rst_ni,
    .psel_i      ( adc_apb_req_i.psel       ),
    .penable_i   ( adc_apb_req_i.penable    ),
    .pwrite_i    ( adc_apb_req_i.pwrite     ),
    .paddr_i     ( adc_apb_req_i.paddr[3:0] ),
    .pwdata_i    ( adc_apb_req_i.pwdata     ),
    .prdata_o    ( adc_apb_resp_o.prdata    ),
    .pready_o    ( adc_apb_resp_o.pready    ),
    .pslverr_o   ( adc_apb_resp_o.pslverr   ),
    .channel_o   ( adc_channel_o            ),
    .dac_code_o  ( adc_dac_code_o           ),
    .compare_i   ( adc_compare_sync         ),
    .irq_o       ( adc_irq_o                )
  );

  adr_otp_ctrl i_otp (
    .clk_i,
    .rst_ni,
    .psel_i        ( otp_apb_req_i.psel       ),
    .penable_i     ( otp_apb_req_i.penable    ),
    .pwrite_i      ( otp_apb_req_i.pwrite     ),
    .paddr_i       ( otp_apb_req_i.paddr[4:0] ),
    .pwdata_i      ( otp_apb_req_i.pwdata     ),
    .prdata_o      ( otp_apb_resp_o.prdata    ),
    .pready_o      ( otp_apb_resp_o.pready    ),
    .pslverr_o     ( otp_apb_resp_o.pslverr   ),
    .macro_req_o   ( otp_req_o                ),
    .macro_we_o    ( otp_we_o                 ),
    .macro_addr_o  ( otp_addr_o               ),
    .macro_wdata_o ( otp_wdata_o              ),
    .macro_rdata_i ( otp_rdata_i              ),
    .macro_done_i  ( otp_done_i               ),
    .irq_o         ( otp_irq_o                )
  );

  adr_aon_timer i_aon_timer (
    .clk_i,
    .por_rst_ni,
    .rtc_i,
    .psel_i     ( aon_apb_req_i.psel       ),
    .penable_i  ( aon_apb_req_i.penable    ),
    .pwrite_i   ( aon_apb_req_i.pwrite     ),
    .paddr_i    ( aon_apb_req_i.paddr[4:0] ),
    .pwdata_i   ( aon_apb_req_i.pwdata     ),
    .prdata_o   ( aon_apb_resp_o.prdata    ),
    .pready_o   ( aon_apb_resp_o.pready    ),
    .pslverr_o  ( aon_apb_resp_o.pslverr   ),
    .irq_o      ( aon_irq_o                )
  );

endmodule
