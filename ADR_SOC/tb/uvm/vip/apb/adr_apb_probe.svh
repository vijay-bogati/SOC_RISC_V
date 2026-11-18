/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_apb_probe.svh
 Module/class Name             : ADR_APB_PROBE (macro)
 Author                        : Vijay Bogati
 Description                   : Copies one APB slot's request and response structs onto an adr_apb_if, read only
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). The Verilator bench does not use it.
// `ADR_APB_PROBE(IF, REQ, RESP): IF is an adr_apb_if instance, REQ and RESP the slot's APB request
// and response structs, usually hierarchical names. Nothing is driven into the slot. A macro for
// the same reason as ADR_AXI_PROBE (adr_axi_probe.svh).

`ifndef ADR_APB_PROBE_SVH
`define ADR_APB_PROBE_SVH

`define ADR_APB_PROBE(IF, REQ, RESP) \
  assign IF.psel    = REQ.psel;     assign IF.penable = REQ.penable; \
  assign IF.pwrite  = REQ.pwrite;   assign IF.paddr   = REQ.paddr;   \
  assign IF.pwdata  = REQ.pwdata;   assign IF.pstrb   = REQ.pstrb;   \
  assign IF.pready  = RESP.pready;  assign IF.prdata  = RESP.prdata; \
  assign IF.pslverr = RESP.pslverr;

`endif
