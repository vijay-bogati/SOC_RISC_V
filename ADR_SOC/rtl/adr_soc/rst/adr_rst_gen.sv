/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_rst_gen.sv
 Module/class Name             : adr_rst_gen
 Author                        : Vijay Bogati
 Description                   : Reset generation: every reset in the SoC, in one place
***************************************************************/

// The system reset is asserted by the power-on reset, by the debug module (ndmreset) or by a
// reset request from the watchdog or software (through system control). Each clock domain then
// gets its own copy of the system reset, asserted at once and released in step with that
// domain's clock, so no flip-flop leaves reset at a different time from its neighbours.
//
// Clock domains: the system clock, the USB clock, and the Ethernet transmit and receive clocks.
// A new clock domain gets its synchronizer here.
//
// The power-on reset is passed on unchanged for the debug module and JTAG logic, which must
// stay out of the system reset so a debugger stays attached across it.
//
// Warm resets drain the DDR4 port first. The DDR4 core is not reset by the system reset, so a
// transaction open in it must finish before the initiators and the crossbar are reset. On a
// watchdog, software or debug-module request, the state machine below (on the power-on reset)
// raises ddr_drain_o, which stops new DDR4 transactions, and asserts the system reset when
// ddr_idle_i shows nothing outstanding, or after DrainTimeout clocks. A timeout gives a one-clock
// ddr_drain_timeout_o pulse, recorded in system control's RESET_CAUSE. The request is held
// here from its first clock, so a one-clock software request still resets the system; the
// reset stays asserted while the request stays high. The power-on reset is not delayed.

module adr_rst_gen #(
  parameter int unsigned DrainTimeout = 1024  // clocks to wait for the DDR4 port before a warm reset
) (
  input  logic clk_i,              // system clock
  input  logic rst_ni,             // power-on reset
  input  logic debug_reset_i,      // ndmreset from the debug module
  input  logic system_reset_req_i, // from system control: watchdog or software
  output logic ddr_drain_o,        // stop new DDR4 transactions
  input  logic ddr_idle_i,         // no DDR4 transaction outstanding
  output logic ddr_drain_timeout_o,// one clock: a warm reset went ahead without the DDR4 port idle
  input  logic usb_clk_i,
  input  logic eth_tx_clk_i,
  input  logic eth_rx_clk_i,
  output logic sys_rst_no,
  output logic usb_rst_no,
  output logic eth_tx_rst_no,
  output logic eth_rx_rst_no
);

  // ---- Warm reset sequence: run, drain the DDR4 port, reset ----
  typedef enum logic [1:0] { Run, Drain, Reset } state_e;

  state_e                            state_q;
  localparam int unsigned           WaitBits = $clog2(DrainTimeout);
  localparam logic [WaitBits-1:0]   LastWait = WaitBits'(DrainTimeout - 1);
  logic [WaitBits-1:0]              wait_q;
  logic                              warm_req;

  assign warm_req = debug_reset_i | system_reset_req_i;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q             <= Run;
      wait_q              <= '0;
      ddr_drain_timeout_o <= 1'b0;
    end else begin
      ddr_drain_timeout_o <= 1'b0;
      unique case (state_q)
        Run:   if (warm_req) begin
                 state_q <= Drain;
                 wait_q  <= '0;
               end
        Drain: if (ddr_idle_i) state_q <= Reset;
               else if (wait_q == LastWait) begin
                 state_q             <= Reset;
                 ddr_drain_timeout_o <= 1'b1;
               end else wait_q <= wait_q + 1'b1;
        Reset: if (!warm_req) state_q <= Run;   // asserted for at least one clock
        default: state_q <= Run;
      endcase
    end
  end

  assign ddr_drain_o = (state_q == Drain);

  rstgen i_sys_rst (
    .clk_i       ( clk_i                       ),
    .rst_ni      ( rst_ni & (state_q != Reset) ),
    .test_mode_i ( 1'b0                        ),
    .rst_no      ( sys_rst_no                  ),
    .init_no     (                             )
  );

  rstgen i_usb_rst (
    .clk_i       ( usb_clk_i  ),
    .rst_ni      ( sys_rst_no ),
    .test_mode_i ( 1'b0       ),
    .rst_no      ( usb_rst_no ),
    .init_no     (            )
  );

  rstgen i_eth_tx_rst (
    .clk_i       ( eth_tx_clk_i  ),
    .rst_ni      ( sys_rst_no    ),
    .test_mode_i ( 1'b0          ),
    .rst_no      ( eth_tx_rst_no ),
    .init_no     (               )
  );

  rstgen i_eth_rx_rst (
    .clk_i       ( eth_rx_clk_i  ),
    .rst_ni      ( sys_rst_no    ),
    .test_mode_i ( 1'b0          ),
    .rst_no      ( eth_rx_rst_no ),
    .init_no     (               )
  );

endmodule
