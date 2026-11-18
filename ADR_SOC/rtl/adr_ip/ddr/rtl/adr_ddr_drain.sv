/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_ddr_drain.sv
 Module/class Name             : adr_ddr_drain
 Author                        : Vijay Bogati
 Description                   : AXI4 drain gate for the DDR4 port: stops new transactions on request and reports when none is outstanding
***************************************************************/

// ADR SoC - drain gate in front of the DDR4 memory port.
// The DDR4 core is not reset by a system reset, so a transaction still open in it when the rest
// of the chip resets would later answer an initiator that no longer exists. Before a warm reset
// (watchdog, software, debug module), the reset generator raises drain_i and waits for idle_o.
//
// With drain_i high, no new write or read address is passed on: AWREADY and ARREADY stay low
// towards the crossbar and AWVALID and ARVALID low towards the memory. An address already offered
// to the memory and not yet accepted is still passed through until it is, as AXI requires a VALID
// to stay high until its handshake. Write data, responses and everything else pass unchanged, so
// open transactions finish normally.
//
// idle_o is high when every accepted write has had its B response and every accepted read its
// last R beat, and no address is waiting at the memory. The counters count handshakes on the
// memory side. They run on the system reset: a drained port has nothing outstanding when that
// reset comes, and after a drain timeout the units behind this gate are reset too.

module adr_ddr_drain #(
  parameter int unsigned CountWidth = 8,      // outstanding transactions per direction
  parameter type         req_t      = logic,
  parameter type         resp_t     = logic
) (
  input  logic  clk_i,
  input  logic  rst_ni,      // system reset
  input  logic  drain_i,     // stop new transactions (from the reset generator)
  output logic  idle_o,      // nothing outstanding
  input  req_t  slv_req_i,   // from the crossbar
  output resp_t slv_resp_o,
  output req_t  mst_req_o,   // to the memory
  input  resp_t mst_resp_i
);

  logic [CountWidth-1:0] writes_q, reads_q;
  logic                  aw_waiting_q, ar_waiting_q;  // an address offered last clock, not accepted
  logic                  block_aw, block_ar;

  assign block_aw = drain_i && !aw_waiting_q;
  assign block_ar = drain_i && !ar_waiting_q;

  always_comb begin
    mst_req_o  = slv_req_i;
    slv_resp_o = mst_resp_i;
    if (block_aw) begin
      mst_req_o.aw_valid  = 1'b0;
      slv_resp_o.aw_ready = 1'b0;
    end
    if (block_ar) begin
      mst_req_o.ar_valid  = 1'b0;
      slv_resp_o.ar_ready = 1'b0;
    end
  end

  logic aw_done, b_done, ar_done, r_done;
  assign aw_done = mst_req_o.aw_valid && mst_resp_i.aw_ready;
  assign b_done  = mst_resp_i.b_valid && mst_req_o.b_ready;
  assign ar_done = mst_req_o.ar_valid && mst_resp_i.ar_ready;
  assign r_done  = mst_resp_i.r_valid && mst_req_o.r_ready && mst_resp_i.r.last;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      writes_q     <= '0;
      reads_q      <= '0;
      aw_waiting_q <= 1'b0;
      ar_waiting_q <= 1'b0;
    end else begin
      writes_q     <= writes_q + CountWidth'(aw_done) - CountWidth'(b_done);
      reads_q      <= reads_q + CountWidth'(ar_done) - CountWidth'(r_done);
      aw_waiting_q <= mst_req_o.aw_valid && !mst_resp_i.aw_ready;
      ar_waiting_q <= mst_req_o.ar_valid && !mst_resp_i.ar_ready;
    end
  end

  assign idle_o = (writes_q == '0) && (reads_q == '0) && !aw_waiting_q && !ar_waiting_q;

endmodule
