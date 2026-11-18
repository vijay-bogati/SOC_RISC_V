/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_axi_if.sv
 Module/class Name             : adr_axi_if
 Author                        : Vijay Bogati
 Description                   : UVM AXI4 monitor interface: the five channels of one AXI4 port, with ATOPs
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). The Verilator bench does not use it.
// Wide enough for any port of the fabric: IDs up to 8 bits, 64-bit address and data. The bench
// connects a port's request and response signals to it; narrower fields are zero-extended.
// clk and rst_n are the port's own clock and reset (the fabric's, not the bench's), so the
// monitor forgets outstanding transactions when the fabric is reset.

interface adr_axi_if (
  input logic clk,
  input logic rst_n
);

  // Write address
  logic        aw_valid, aw_ready;
  logic [7:0]  aw_id;
  logic [63:0] aw_addr;
  logic [7:0]  aw_len;
  logic [2:0]  aw_size;
  logic [1:0]  aw_burst;
  logic        aw_lock;
  logic [5:0]  aw_atop;
  // Write data
  logic        w_valid, w_ready;
  logic [63:0] w_data;
  logic [7:0]  w_strb;
  logic        w_last;
  // Write response
  logic        b_valid, b_ready;
  logic [7:0]  b_id;
  logic [1:0]  b_resp;
  // Read address
  logic        ar_valid, ar_ready;
  logic [7:0]  ar_id;
  logic [63:0] ar_addr;
  logic [7:0]  ar_len;
  logic [2:0]  ar_size;
  logic [1:0]  ar_burst;
  logic        ar_lock;
  // Read data
  logic        r_valid, r_ready;
  logic [7:0]  r_id;
  logic [63:0] r_data;
  logic [1:0]  r_resp;
  logic        r_last;

  // Values as they were just before each rising edge, as the port's logic sees them.
  clocking mon_cb @(posedge clk);
    input rst_n;
    input aw_valid, aw_ready, aw_id, aw_addr, aw_len, aw_size, aw_burst, aw_lock, aw_atop;
    input w_valid, w_ready, w_data, w_strb, w_last;
    input b_valid, b_ready, b_id, b_resp;
    input ar_valid, ar_ready, ar_id, ar_addr, ar_len, ar_size, ar_burst, ar_lock;
    input r_valid, r_ready, r_id, r_data, r_resp, r_last;
  endclocking

endinterface
