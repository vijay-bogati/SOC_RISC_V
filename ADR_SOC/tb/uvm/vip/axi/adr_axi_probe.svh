/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_axi_probe.svh
 Module/class Name             : ADR_AXI_PROBE (macro)
 Author                        : Vijay Bogati
 Description                   : Copies one AXI4 port's request and response structs onto an adr_axi_if, read only
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). The Verilator bench does not use it.
// `ADR_AXI_PROBE(IF, REQ, RESP): IF is an adr_axi_if instance, REQ and RESP the port's AXI4
// request and response structs (as made by AXI_TYPEDEF_ALL), usually hierarchical names. Narrower
// IDs, addresses and data are zero-extended into the interface. Nothing is driven into the port.
// A macro, not a module: some simulators size the ports of a bound module from its default
// parameters, so a type-parameterised probe module cannot be bound.

`ifndef ADR_AXI_PROBE_SVH
`define ADR_AXI_PROBE_SVH

`define ADR_AXI_PROBE(IF, REQ, RESP) \
  assign IF.aw_valid = REQ.aw_valid;   assign IF.aw_ready = RESP.aw_ready; \
  assign IF.aw_id    = REQ.aw.id;      assign IF.aw_addr  = REQ.aw.addr;   \
  assign IF.aw_len   = REQ.aw.len;     assign IF.aw_size  = REQ.aw.size;   \
  assign IF.aw_burst = REQ.aw.burst;   assign IF.aw_lock  = REQ.aw.lock;   \
  assign IF.aw_atop  = REQ.aw.atop;                                        \
  assign IF.w_valid  = REQ.w_valid;    assign IF.w_ready  = RESP.w_ready;  \
  assign IF.w_data   = REQ.w.data;     assign IF.w_strb   = REQ.w.strb;    \
  assign IF.w_last   = REQ.w.last;                                         \
  assign IF.b_valid  = RESP.b_valid;   assign IF.b_ready  = REQ.b_ready;   \
  assign IF.b_id     = RESP.b.id;      assign IF.b_resp   = RESP.b.resp;   \
  assign IF.ar_valid = REQ.ar_valid;   assign IF.ar_ready = RESP.ar_ready; \
  assign IF.ar_id    = REQ.ar.id;      assign IF.ar_addr  = REQ.ar.addr;   \
  assign IF.ar_len   = REQ.ar.len;     assign IF.ar_size  = REQ.ar.size;   \
  assign IF.ar_burst = REQ.ar.burst;   assign IF.ar_lock  = REQ.ar.lock;   \
  assign IF.r_valid  = RESP.r_valid;   assign IF.r_ready  = REQ.r_ready;   \
  assign IF.r_id     = RESP.r.id;      assign IF.r_data   = RESP.r.data;   \
  assign IF.r_resp   = RESP.r.resp;    assign IF.r_last   = RESP.r.last;

`endif
