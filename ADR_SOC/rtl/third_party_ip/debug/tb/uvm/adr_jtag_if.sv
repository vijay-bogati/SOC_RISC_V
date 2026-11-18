/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_jtag_if.sv
 Module/class Name             : adr_jtag_if
 Author                        : Vijay Bogati
 Description                   : UVM JTAG agent interface: the five JTAG pins, timed from the system clock
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). The Verilator bench does not use it.
// The driver makes TCK from clk (TCK edges fall on falling edges of clk), so the pins change at
// the same times as with the Verilator bench's JTAG tasks in tb_top. trst_n is held low by the
// driver until rst_n goes high. Initial values: every pin low, so TCK is idle and the TAP in reset.

interface adr_jtag_if (
  input logic clk,
  input logic rst_n
);

  logic tck    = 1'b0;
  logic tms    = 1'b0;
  logic tdi    = 1'b0;
  logic trst_n = 1'b0;
  logic tdo;
  logic tdo_oe;  // the TAP drives TDO (Shift-DR, Shift-IR); checked by the monitor

endinterface
