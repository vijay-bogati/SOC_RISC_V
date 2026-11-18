/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_apb_monitor_pkg.sv
 Module/class Name             : adr_apb_monitor_pkg
 Author                        : Vijay Bogati
 Description                   : UVM APB monitor: transfer item, configuration, monitor with protocol checks, passive agent
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). Reusable on any APB4 slot, at IP level or SoC level.
//
// The monitor writes one item per transfer, on the clock where the access phase ends
// (PSEL, PENABLE and PREADY high). Checks, reported as UVM errors:
//   - PENABLE is high only with PSEL, and only after a setup clock (PSEL high, PENABLE low);
//   - PSTRB is 0 on a read (APB4);
//   - from the setup clock to the end of the access, PADDR, PWRITE, PWDATA and PSTRB do not change
//     and PSEL stays high.
// PSLVERR responses are counted, not reported as errors: tests cause them on purpose.

package adr_apb_monitor_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class adr_apb_item extends uvm_sequence_item;
    bit          write;
    logic [63:0] addr;
    logic [31:0] data;   // write data, or read data
    logic [3:0]  strb;
    bit          error;  // PSLVERR

    `uvm_object_utils_begin(adr_apb_item)
      `uvm_field_int(write, UVM_ALL_ON)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(data, UVM_ALL_ON)
      `uvm_field_int(strb, UVM_ALL_ON)
      `uvm_field_int(error, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "adr_apb_item");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf("%s %h %s %h%s", write ? "write" : "read ", addr, write ? "<-" : "->", data,
                       error ? " (PSLVERR)" : "");
    endfunction
  endclass

  class adr_apb_config extends uvm_object;
    `uvm_object_utils(adr_apb_config)

    virtual adr_apb_if vif;
    string             slot_name = "apb";

    function new(string name = "adr_apb_config");
      super.new(name);
    endfunction
  endclass

  class adr_apb_monitor extends uvm_monitor;
    `uvm_component_utils(adr_apb_monitor)

    uvm_analysis_port #(adr_apb_item) ap;
    adr_apb_config                    cfg;
    int unsigned                      reads, writes, error_responses;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_apb_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_apb_config not set for the monitor")
    endfunction

    task run_phase(uvm_phase phase);
      bit           in_transfer = 1'b0;  // a setup clock has been seen, the access has not ended
      logic [100:0] request;             // PADDR, PWRITE, PWDATA, PSTRB at the setup clock
      forever begin
        logic [100:0] now;
        @(cfg.vif.mon_cb);
        if (cfg.vif.mon_cb.rst_n !== 1'b1) begin
          in_transfer = 1'b0;
          continue;
        end
        now = {cfg.vif.mon_cb.paddr, cfg.vif.mon_cb.pwrite, cfg.vif.mon_cb.pwdata, cfg.vif.mon_cb.pstrb};

        if (cfg.vif.mon_cb.penable === 1'b1 && cfg.vif.mon_cb.psel !== 1'b1)
          `uvm_error(cfg.slot_name, "PENABLE high without PSEL")

        if (!in_transfer) begin
          if (cfg.vif.mon_cb.psel === 1'b1) begin
            if (cfg.vif.mon_cb.penable === 1'b1)
              `uvm_error(cfg.slot_name, "access clock without a setup clock before it")
            if (cfg.vif.mon_cb.pwrite === 1'b0 && cfg.vif.mon_cb.pstrb !== 4'b0)
              `uvm_error(cfg.slot_name, $sformatf("PSTRB %b on a read, must be 0", cfg.vif.mon_cb.pstrb))
            in_transfer = 1'b1;
            request     = now;
          end
          continue;
        end

        // Access phase: the request must not change until PREADY.
        if (cfg.vif.mon_cb.psel !== 1'b1 || now !== request) begin
          `uvm_error(cfg.slot_name, "PSEL dropped or the request changed before PREADY")
          in_transfer = 1'b0;
          continue;
        end
        if (cfg.vif.mon_cb.penable === 1'b1 && cfg.vif.mon_cb.pready === 1'b1) begin
          adr_apb_item item = adr_apb_item::type_id::create("item");
          item.write = cfg.vif.mon_cb.pwrite;
          item.addr  = cfg.vif.mon_cb.paddr;
          item.data  = item.write ? cfg.vif.mon_cb.pwdata : cfg.vif.mon_cb.prdata;
          item.strb  = cfg.vif.mon_cb.pstrb;
          item.error = cfg.vif.mon_cb.pslverr;
          if (item.write) writes++;
          else            reads++;
          if (item.error) error_responses++;
          `uvm_info(cfg.slot_name, item.convert2string(), UVM_HIGH)
          ap.write(item);
          in_transfer = 1'b0;
        end
      end
    endtask

    function string summary();
      return $sformatf("%0d reads, %0d writes, %0d PSLVERR", reads, writes, error_responses);
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info(cfg.slot_name, summary(), UVM_HIGH)
    endfunction
  endclass

  class adr_apb_agent extends uvm_agent;
    `uvm_component_utils(adr_apb_agent)

    adr_apb_config  cfg;
    adr_apb_monitor mon;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_apb_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_apb_config not set for the agent")
      uvm_config_db #(adr_apb_config)::set(this, "mon", "cfg", cfg);
      mon = adr_apb_monitor::type_id::create("mon", this);
    endfunction
  endclass

endpackage
