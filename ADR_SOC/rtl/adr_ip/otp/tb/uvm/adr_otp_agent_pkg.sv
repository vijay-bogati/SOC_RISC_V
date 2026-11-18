/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_otp_agent_pkg.sv
 Module/class Name             : adr_otp_agent_pkg
 Author                        : Vijay Bogati
 Description                   : UVM OTP agent: item, configuration, monitor, macro slave driver and agent
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). Reusable at IP level (adr_otp_ctrl) and SoC level.
//
// Monitor: one item per macro operation, from the accepted request to its done pulse.
//
// Slave driver (active agent): a one-time-programmable memory of 32 words. Programming only
// turns bits on, and contents are kept until the simulation ends. A read takes 8 clocks and a
// program takes 32. It follows the testbench model adr_tb_otp_macro clock for clock, so a C test
// takes the same number of cycles as on the Verilator bench. mem[] can be read and preset by a
// test (backdoor), for example to start with fuses already blown.

package adr_otp_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class adr_otp_item extends uvm_sequence_item;
    bit          write;  // program; otherwise read
    logic [4:0]  addr;
    logic [31:0] wdata;  // program: bits to turn on
    logic [31:0] rdata;  // read: value returned

    `uvm_object_utils_begin(adr_otp_item)
      `uvm_field_int(write, UVM_ALL_ON)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(wdata, UVM_ALL_ON)
      `uvm_field_int(rdata, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "adr_otp_item");
      super.new(name);
    endfunction

    function string convert2string();
      return write ? $sformatf("program word %0d with %8h", addr, wdata)
                   : $sformatf("read word %0d: %8h", addr, rdata);
    endfunction
  endclass

  class adr_otp_config extends uvm_object;
    `uvm_object_utils(adr_otp_config)

    virtual adr_otp_if      vif;
    uvm_active_passive_enum is_active = UVM_ACTIVE;

    function new(string name = "adr_otp_config");
      super.new(name);
    endfunction
  endclass

  class adr_otp_monitor extends uvm_monitor;
    `uvm_component_utils(adr_otp_monitor)

    uvm_analysis_port #(adr_otp_item) ap;
    adr_otp_config                    cfg;
    int unsigned                      reads, programs;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_otp_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_otp_config not set for the monitor")
    endfunction

    task run_phase(uvm_phase phase);
      adr_otp_item item;
      forever begin
        @(cfg.vif.mon_cb);
        if (item == null) begin
          if (cfg.vif.mon_cb.rst_n === 1'b1 && cfg.vif.mon_cb.req === 1'b1) begin
            item = adr_otp_item::type_id::create("item");
            item.write = cfg.vif.mon_cb.we;
            item.addr  = cfg.vif.mon_cb.addr;
            item.wdata = cfg.vif.mon_cb.wdata;
          end
        end else if (cfg.vif.mon_cb.done === 1'b1) begin
          item.rdata = cfg.vif.mon_cb.rdata;
          if (item.write) programs++;
          else            reads++;
          `uvm_info("OTP", item.convert2string(), UVM_HIGH)
          ap.write(item);
          item = null;
        end
      end
    endtask

    function void report_phase(uvm_phase phase);
      `uvm_info("OTP", $sformatf("%0d reads, %0d programs", reads, programs), UVM_LOW)
    endfunction
  endclass

  // The macro. Register names and steps are those of adr_tb_otp_macro.
  class adr_otp_slave_driver extends uvm_driver #(adr_otp_item);
    `uvm_component_utils(adr_otp_slave_driver)

    adr_otp_config cfg;
    logic [31:0]   mem [32] = '{default: 32'h0};

    logic [5:0]    wait_q    = '0;
    logic          running_q = 1'b0;
    logic          we_q      = 1'b0;
    logic [4:0]    addr_q    = '0;
    logic [31:0]   wdata_q   = '0;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_otp_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_otp_config not set for the slave driver")
    endfunction

    // Every branch reads only values from before the edge, so the updates can be made in place.
    task run_phase(uvm_phase phase);
      forever begin
        logic done = 1'b0;
        @(cfg.vif.drv_cb);
        if (cfg.vif.drv_cb.req && !running_q) begin
          running_q = 1'b1;
          we_q      = cfg.vif.drv_cb.we;
          addr_q    = cfg.vif.drv_cb.addr;
          wdata_q   = cfg.vif.drv_cb.wdata;
          wait_q    = cfg.vif.drv_cb.we ? 6'd31 : 6'd7;
        end else if (running_q) begin
          if (wait_q == '0) begin
            running_q = 1'b0;
            done      = 1'b1;
            if (we_q) mem[addr_q] = mem[addr_q] | wdata_q;
            else      cfg.vif.drv_cb.rdata <= mem[addr_q];
          end else begin
            wait_q = wait_q - 6'd1;
          end
        end
        cfg.vif.drv_cb.done <= done;
      end
    endtask
  endclass

  class adr_otp_agent extends uvm_agent;
    `uvm_component_utils(adr_otp_agent)

    adr_otp_config       cfg;
    adr_otp_monitor      mon;
    adr_otp_slave_driver drv;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_otp_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_otp_config not set for the agent")
      uvm_config_db #(adr_otp_config)::set(this, "*", "cfg", cfg);
      mon = adr_otp_monitor::type_id::create("mon", this);
      if (cfg.is_active == UVM_ACTIVE) drv = adr_otp_slave_driver::type_id::create("drv", this);
    endfunction
  endclass

endpackage
