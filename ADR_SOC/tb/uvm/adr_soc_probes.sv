/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_soc_probes.sv
 Module/class Name             : adr_soc_probes, adr_soc_probes_bind
 Author                        : Vijay Bogati
 Description                   : UVM white-box probes bound into adr_soc_top: fabric monitor interfaces and the C-UVM handshake path
***************************************************************/

// UVM bench only (sim/adr_soc_uvm.f; a simulator with UVM 1.2). The Verilator bench does not use it.
// Everything the UVM bench sees inside the chip is collected here, so the bench top only has
// pins. adr_soc_probes_bind (end of this file, a second vopt top in the Makefile) binds one
// adr_soc_probes into every adr_soc_top. Inside it, adr_soc_top.<signal> is an upward name: it
// means the chip this instance sits in, so no path from the bench top is written anywhere.
// Read only: the probes drive nothing into the chip.
//
// No parameters and no ports, on purpose: some simulators size a bound module's ports from its
// default parameters (the overrides only reach the module body), which cut the AXI structs to
// one bit. The probes are therefore the ADR_AXI_PROBE and ADR_APB_PROBE macros of the VIPs.
//
// It sets, for the environment:
//   axi_<port>_vif   one adr_axi_if per crossbar port: 4 initiators, 5 targets
//   apb_vif_<n>      one adr_apb_if per APB slot, in slot order (adr_soc_pkg)
//   c_sync_ack_path  HDL path of system control SCRATCH1, where the base test acknowledges
//                    C-UVM requests (uvm_hdl_deposit)
// The interfaces use the fabric reset sys_rst_n, so the monitors forget open transactions when
// the debugger resets the SoC.

`include "adr_axi_probe.svh"
`include "adr_apb_probe.svh"

module adr_soc_probes;
  import uvm_pkg::*;

  localparam int unsigned NumApbSlots = adr_soc_pkg::NumApbSlots;
  localparam string       Env         = "uvm_test_top.env";

  wire clk       = adr_soc_top.clk_i;
  wire sys_rst_n = adr_soc_top.sys_rst_n;

  // ---- AXI4 crossbar ports: initiators, then targets ----
  adr_axi_if i_axi_cpu_if        (.clk(clk), .rst_n(sys_rst_n));
  adr_axi_if i_axi_debug_init_if (.clk(clk), .rst_n(sys_rst_n));
  adr_axi_if i_axi_dma_if        (.clk(clk), .rst_n(sys_rst_n));
  adr_axi_if i_axi_eth_if        (.clk(clk), .rst_n(sys_rst_n));
  adr_axi_if i_axi_rom_if        (.clk(clk), .rst_n(sys_rst_n));
  adr_axi_if i_axi_sram_if       (.clk(clk), .rst_n(sys_rst_n));
  adr_axi_if i_axi_ddr_if        (.clk(clk), .rst_n(sys_rst_n));
  adr_axi_if i_axi_clint_if      (.clk(clk), .rst_n(sys_rst_n));
  adr_axi_if i_axi_debug_tgt_if  (.clk(clk), .rst_n(sys_rst_n));
  `ADR_AXI_PROBE(i_axi_cpu_if,        adr_soc_top.cpu_req,      adr_soc_top.cpu_resp)
  `ADR_AXI_PROBE(i_axi_debug_init_if, adr_soc_top.dbg_init_req, adr_soc_top.dbg_init_resp)
  `ADR_AXI_PROBE(i_axi_dma_if,        adr_soc_top.dma_req,      adr_soc_top.dma_resp)
  `ADR_AXI_PROBE(i_axi_eth_if,        adr_soc_top.eth_req,      adr_soc_top.eth_resp)
  `ADR_AXI_PROBE(i_axi_rom_if,        adr_soc_top.rom_req,      adr_soc_top.rom_resp)
  `ADR_AXI_PROBE(i_axi_sram_if,       adr_soc_top.sram_req,     adr_soc_top.sram_resp)
  `ADR_AXI_PROBE(i_axi_ddr_if,        adr_soc_top.ddr_req,      adr_soc_top.ddr_resp)
  `ADR_AXI_PROBE(i_axi_clint_if,      adr_soc_top.clint_req,    adr_soc_top.clint_resp)
  `ADR_AXI_PROBE(i_axi_debug_tgt_if,  adr_soc_top.dbg_tgt_req,  adr_soc_top.dbg_tgt_resp)

  initial begin
    uvm_config_db #(virtual adr_axi_if)::set(null, Env, "axi_cpu_vif",        i_axi_cpu_if);
    uvm_config_db #(virtual adr_axi_if)::set(null, Env, "axi_debug_init_vif", i_axi_debug_init_if);
    uvm_config_db #(virtual adr_axi_if)::set(null, Env, "axi_dma_vif",        i_axi_dma_if);
    uvm_config_db #(virtual adr_axi_if)::set(null, Env, "axi_eth_vif",        i_axi_eth_if);
    uvm_config_db #(virtual adr_axi_if)::set(null, Env, "axi_rom_vif",        i_axi_rom_if);
    uvm_config_db #(virtual adr_axi_if)::set(null, Env, "axi_sram_vif",       i_axi_sram_if);
    uvm_config_db #(virtual adr_axi_if)::set(null, Env, "axi_ddr_vif",        i_axi_ddr_if);
    uvm_config_db #(virtual adr_axi_if)::set(null, Env, "axi_clint_vif",      i_axi_clint_if);
    uvm_config_db #(virtual adr_axi_if)::set(null, Env, "axi_debug_tgt_vif",  i_axi_debug_tgt_if);
  end

  // ---- APB slots ----
  adr_apb_if i_apb_if [NumApbSlots] (.clk(clk), .rst_n(sys_rst_n));
  for (genvar slot = 0; slot < NumApbSlots; slot++) begin : g_apb_probe
    `ADR_APB_PROBE(i_apb_if[slot], adr_soc_top.apb_req[slot], adr_soc_top.apb_resp[slot])
    initial uvm_config_db #(virtual adr_apb_if)::set(null, Env, $sformatf("apb_vif_%0d", slot),
                                                      i_apb_if[slot]);
  end

  // ---- C-UVM handshake: SCRATCH1 path, built from where this instance sits in the chip ----
  initial begin
    string here;
    int    dot;
    here = $sformatf("%m");                        // <top>.<dut>.i_soc_probes
    dot  = here.len() - 1;
    while (dot > 0 && here[dot] != ".") dot--;
    uvm_config_db #(string)::set(null, Env, "c_sync_ack_path",
                                 {here.substr(0, dot - 1), ".i_periph.i_sysctrl.scratch_q[1]"});
  end

endmodule

// A second top (Makefile): some simulators do not apply a bind written outside any module.
module adr_soc_probes_bind;
  bind adr_soc_top adr_soc_probes i_soc_probes ();
endmodule
