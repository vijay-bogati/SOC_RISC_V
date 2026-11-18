/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_apb_if.sv
 Module/class Name             : adr_apb_if
 Author                        : Vijay Bogati
 Description                   : UVM APB monitor interface: one APB4 slot, 64-bit address and 32-bit data
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). The Verilator bench does not use it.
// clk and rst_n are the bus's own clock and reset. The bench connects one slot of the APB
// bridge to each interface.

interface adr_apb_if (
  input logic clk,
  input logic rst_n
);

  logic        psel;
  logic        penable;
  logic        pwrite;
  logic [63:0] paddr;
  logic [31:0] pwdata;
  logic [3:0]  pstrb;
  logic        pready;
  logic [31:0] prdata;
  logic        pslverr;

  // Values as they were just before each rising edge, as the bus's logic sees them.
  clocking mon_cb @(posedge clk);
    input rst_n, psel, penable, pwrite, paddr, pwdata, pstrb, pready, prdata, pslverr;
  endclocking

endinterface
