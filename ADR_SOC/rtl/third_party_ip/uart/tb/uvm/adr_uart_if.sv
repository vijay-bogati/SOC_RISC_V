/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_uart_if.sv
 Module/class Name             : adr_uart_if
 Author                        : Vijay Bogati
 Description                   : UVM UART agent interface: the two UART lines, sampled on the system clock, with pin-level assertions
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). The Verilator bench does not use it.
// tx is the line the DUT transmits on; rx is the line into the DUT, idle high until a driver uses it.
//
// Pin-level assertions on tx (ADR_ASSERTIONS_PLAN 5.1), on the system clock, off during reset.
// A failure calls uvm_report_error with the plan ID, so it fails the UVM verdict.
//   UART-A01  tx is never X or Z after reset
//   UART-A02  tx is high (idle) on the first clock after reset
//   UART-A03  once tx changes, it holds for at least cycles_per_bit - 1 clocks
//   UART-A04  the stop bit is high: tx is high 9.5 bit times after a start bit's falling edge
//   UART-C01  two frames back to back (the next start bit one frame after the last)
//   UART-C02  a frame with data 0x00, and one with data 0xFF
// cycles_per_bit is the bit time in system clocks. The agent sets it from its configuration, and
// a scoreboard that follows the divisor registers keeps it up to date; 0 switches A03, A04 and
// the cover properties off. The checks assume 8 data bits, no parity and one stop bit (8N1).

interface adr_uart_if (
  input logic clk,
  input logic rst_n
);

  import uvm_pkg::*;

  logic tx;
  logic rx = 1'b1;

  int unsigned cycles_per_bit = 0;  // bit time for the checks; 0: timing checks off

  // Values as they were just before each rising edge, as clocked logic sees them.
  clocking mon_cb @(posedge clk);
    input rst_n, tx, rx;
  endclocking

  // ---- Frame tracking for A03, A04 and the cover properties ----
  // Uses the clocking block's samples (values just before the edge), like the concurrent
  // assertions below, so it never races the DUT's or the reset's update of the same edge.
  logic        tx_q          = 1'b1;
  int unsigned hold          = 0;     // clocks since tx last changed (saturates)
  bit          in_frame      = 1'b0;
  int unsigned frame_count   = 0;     // clocks since the start bit's falling edge
  int unsigned since_start   = 0;     // clocks since the last start bit (saturates)
  logic [7:0]  data_bits     = '0;
  bit          short_bit     = 1'b0;  // A03 failed on this clock
  int unsigned short_len    = 0;     // the level's length when A03 failed
  bit          bad_stop      = 1'b0;  // A04 failed on this clock
  bit          back_to_back  = 1'b0;  // C01 seen on this clock
  bit          frame_zero    = 1'b0;  // C02 seen on this clock
  bit          frame_ones    = 1'b0;

  always @(mon_cb) begin
    logic line;
    line         = mon_cb.tx;
    short_bit    = 1'b0;
    bad_stop     = 1'b0;
    back_to_back = 1'b0;
    frame_zero   = 1'b0;
    frame_ones   = 1'b0;
    if (mon_cb.rst_n !== 1'b1 || cycles_per_bit == 0) begin
      tx_q        = line;
      hold        = 0;
      in_frame    = 1'b0;
      since_start = 0;
    end else begin
      // A03: every level lasts about one bit or more (one clock of tolerance).
      if (line !== tx_q) begin
        if (hold + 1 < cycles_per_bit - 1) begin
          short_bit = 1'b1;
          short_len = hold + 1;
        end
        hold = 0;
      end else if (hold < 32'hFFFF_FFFF) hold++;
      if (since_start < 32'hFFFF_FFFF) since_start++;

      // A04 and the cover properties: follow each frame from its start bit.
      if (!in_frame) begin
        if (tx_q === 1'b1 && line === 1'b0) begin
          // A start one frame (10 bits) after the last, within one clock: back to back.
          if (since_start >= 10 * cycles_per_bit - 1 && since_start <= 10 * cycles_per_bit + 1)
            back_to_back = 1'b1;
          in_frame    = 1'b1;
          frame_count = 0;
          since_start = 0;
        end
      end else begin
        frame_count++;
        for (int i = 1; i <= 8; i++)
          if (frame_count == i * cycles_per_bit + cycles_per_bit / 2) data_bits[i - 1] = line;
        if (frame_count == 9 * cycles_per_bit + cycles_per_bit / 2) begin
          if (line !== 1'b1) bad_stop = 1'b1;
          frame_zero = (data_bits == 8'h00);
          frame_ones = (data_bits == 8'hFF);
          in_frame   = 1'b0;
        end
      end
      tx_q = line;
    end
  end

  // ---- Assertions and cover properties ----
  a_uart_tx_known: assert property (@(posedge clk) disable iff (rst_n !== 1'b1) !$isunknown(tx))
    else uvm_report_error("UART-A01", "tx is X or Z after reset");

  a_uart_tx_idle_after_reset: assert property (@(posedge clk) $rose(rst_n) |-> tx === 1'b1)
    else uvm_report_error("UART-A02", "tx is not high (idle) on the first clock after reset");

  a_uart_tx_bit_time: assert property (@(posedge clk) disable iff (rst_n !== 1'b1) !short_bit)
    else uvm_report_error("UART-A03", $sformatf("tx changed %0d clocks after its last change; one bit is %0d clocks",
                                                short_len, cycles_per_bit));

  a_uart_stop_bit: assert property (@(posedge clk) disable iff (rst_n !== 1'b1) !bad_stop)
    else uvm_report_error("UART-A04", "tx is not high in the middle of the stop bit (framing)");

  c_uart_back_to_back: cover property (@(posedge clk) disable iff (rst_n !== 1'b1) back_to_back);
  c_uart_data_zero:    cover property (@(posedge clk) disable iff (rst_n !== 1'b1) frame_zero);
  c_uart_data_ones:    cover property (@(posedge clk) disable iff (rst_n !== 1'b1) frame_ones);

endinterface
