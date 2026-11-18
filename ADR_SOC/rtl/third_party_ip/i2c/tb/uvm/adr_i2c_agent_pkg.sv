/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_i2c_agent_pkg.sv
 Module/class Name             : adr_i2c_agent_pkg
 Author                        : Vijay Bogati
 Description                   : UVM I2C agent: item, configuration, monitor, register slave driver, coverage and agent
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). Reusable at IP level and SoC level.
// The agent works from the bus alone: SCL edges for bits, SDA edges while SCL is high for START
// and STOP. No system clock.
//
// Monitor: one item per transfer, from a START to the next STOP or repeated START: the address,
// the direction, each data byte and each acknowledge bit (0 = acknowledged), and whether it began
// with a repeated START.
//
// Slave driver (active agent): a device at cfg.device_addr with a one-byte register. A write
// stores each byte it receives; a read returns the register for as long as the master
// acknowledges. Other addresses get no acknowledge. The slave changes SDA only just after a
// falling edge of SCL. A test can read or preset the register with peek() and poke() (backdoor).
// Clock stretching (cfg.stretch_ns > 0): the slave holds SCL low for that long once per byte,
// while SCL is already low: after acknowledging a written byte (SDA released first), and before
// each byte it sends (with the first bit already on SDA). The master must wait for SCL to rise.
// The default, 0, never touches SCL.
//
// adr_i2c_coverage holds cg_i2c (ADR_COVERAGE_PLAN 4.2), one sample per monitor item.

package adr_i2c_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class adr_i2c_item extends uvm_sequence_item;
    logic [6:0] addr;
    bit         read;
    bit         addr_ack;  // the address was acknowledged
    logic [7:0] data [$];
    logic       acks [$];  // acknowledge bit after each data byte (0 = acknowledged)
    bit         rep_start; // began with a repeated START (no STOP before it)

    `uvm_object_utils_begin(adr_i2c_item)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(read, UVM_ALL_ON)
      `uvm_field_int(addr_ack, UVM_ALL_ON)
      `uvm_field_int(rep_start, UVM_ALL_ON)
      `uvm_field_queue_int(data, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "adr_i2c_item");
      super.new(name);
    endfunction

    function string convert2string();
      string text = $sformatf("%s device 0x%2h (%s)", read ? "read from" : "write to", addr,
                              addr_ack ? "acknowledged" : "no acknowledge");
      foreach (data[i]) text = {text, $sformatf(" %2h%s", data[i], acks[i] === 1'b0 ? "" : "-nak")};
      return text;
    endfunction
  endclass

  class adr_i2c_config extends uvm_object;
    `uvm_object_utils(adr_i2c_config)

    virtual adr_i2c_if      vif;
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    logic [6:0]             device_addr = 7'h50;
    int unsigned            stretch_ns  = 0;    // clock stretching per byte; 0: none

    function new(string name = "adr_i2c_config");
      super.new(name);
    endfunction
  endclass

  class adr_i2c_monitor extends uvm_monitor;
    `uvm_component_utils(adr_i2c_monitor)

    uvm_analysis_port #(adr_i2c_item) ap;
    adr_i2c_config                    cfg;
    int unsigned                      transfers;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_i2c_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_i2c_config not set for the monitor")
    endfunction

    // Each START opens a transfer; the next STOP or repeated START closes it.
    task run_phase(uvm_phase phase);
      bit repeated = 1'b0;
      @(negedge cfg.vif.sda iff cfg.vif.scl === 1'b1);
      forever begin
        adr_i2c_item item = adr_i2c_item::type_id::create("item");
        item.rep_start = repeated;
        fork
          collect(item);
        join_none
        @(cfg.vif.sda iff cfg.vif.scl === 1'b1);
        disable fork;
        transfers++;
        `uvm_info("I2C", item.convert2string(), UVM_HIGH)
        ap.write(item);
        repeated = (cfg.vif.sda === 1'b0);  // SDA fell: a repeated START opens the next transfer
        if (!repeated) @(negedge cfg.vif.sda iff cfg.vif.scl === 1'b1);  // after STOP
      end
    endtask

    // Nine clocks per byte: eight bits, most significant first, then the acknowledge bit.
    task collect(adr_i2c_item item);
      logic [7:0] value;
      for (int byte_no = 0; ; byte_no++) begin
        repeat (8) begin
          @(cfg.vif.scl_rise);
          value = {value[6:0], cfg.vif.scl_rise.sda};
        end
        @(cfg.vif.scl_rise);
        if (byte_no == 0) begin
          item.addr     = value[7:1];
          item.read     = value[0];
          item.addr_ack = (cfg.vif.scl_rise.sda === 1'b0);
        end else begin
          item.data.push_back(value);
          item.acks.push_back(cfg.vif.scl_rise.sda);
        end
      end
    endtask

    function void report_phase(uvm_phase phase);
      `uvm_info("I2C", $sformatf("%0d transfers", transfers), UVM_LOW)
    endfunction
  endclass

  class adr_i2c_slave_driver extends uvm_driver #(adr_i2c_item);
    `uvm_component_utils(adr_i2c_slave_driver)

    adr_i2c_config cfg;
    logic [7:0]    stored_byte = 8'h00;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_i2c_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_i2c_config not set for the slave driver")
    endfunction

    function logic [7:0] peek();
      return stored_byte;
    endfunction

    function void poke(logic [7:0] value);
      stored_byte = value;
    endfunction

    // A STOP or a repeated START ends whatever the slave was doing and frees SDA.
    task run_phase(uvm_phase phase);
      @(negedge cfg.vif.sda iff cfg.vif.scl === 1'b1);
      forever begin
        fork
          respond();
        join_none
        @(cfg.vif.sda iff cfg.vif.scl === 1'b1);
        disable fork;
        cfg.vif.sda_low <= 1'b0;
        cfg.vif.scl_low <= 1'b0;
        if (cfg.vif.sda !== 1'b0) @(negedge cfg.vif.sda iff cfg.vif.scl === 1'b1);  // after STOP
      end
    endtask

    task get_byte(output logic [7:0] value);
      repeat (8) begin
        @(cfg.vif.scl_rise);
        value = {value[6:0], cfg.vif.scl_rise.sda};
      end
    endtask

    // Clock stretching: called while SCL is low; holds it low for cfg.stretch_ns.
    task stretch();
      if (cfg.stretch_ns == 0) return;
      cfg.vif.scl_low <= 1'b1;
      #(cfg.stretch_ns * 1ns);
      cfg.vif.scl_low <= 1'b0;
    endtask

    // Pull SDA low for the acknowledge clock: from the falling edge after the eighth bit to the
    // falling edge after the ninth.
    task acknowledge();
      @(negedge cfg.vif.scl);
      cfg.vif.sda_low <= 1'b1;
      @(negedge cfg.vif.scl);
    endtask

    // Called on a falling edge of SCL: puts out the byte, then frees SDA for the master. The
    // stretch comes after the first bit is on SDA, so SDA is stable when SCL is released.
    task put_byte(logic [7:0] value);
      for (int i = 7; i >= 0; i--) begin
        cfg.vif.sda_low <= !value[i];
        if (i == 7) stretch();
        @(negedge cfg.vif.scl);
      end
      cfg.vif.sda_low <= 1'b0;
    endtask

    task respond();
      logic [7:0] header, value;
      get_byte(header);
      if (header[7:1] != cfg.device_addr) return;  // not addressed: stay off the bus
      acknowledge();
      if (header[0]) begin
        forever begin                                // read: the master acknowledges each byte
          put_byte(stored_byte);
          @(cfg.vif.scl_rise);
          if (cfg.vif.scl_rise.sda !== 1'b0) return; // no acknowledge: the master is done
          @(negedge cfg.vif.scl);
        end
      end else begin
        cfg.vif.sda_low <= 1'b0;
        forever begin                                // write: store and acknowledge each byte
          get_byte(value);
          stored_byte = value;
          acknowledge();
          cfg.vif.sda_low <= 1'b0;
          stretch();
        end
      end
    endtask
  endclass

  // cg_i2c: one sample per transfer. Address (the device or another), direction, data bytes,
  // acknowledge kind, repeated START, and the slave's clock stretching from the configuration
  // (none, short below 1000 ns, long). A read's last byte is NACKed by the master by design, so
  // only a write byte without acknowledge, or a read byte NACKed before the last, counts as a
  // NACK on data.
  class adr_i2c_coverage extends uvm_subscriber #(adr_i2c_item);
    `uvm_component_utils(adr_i2c_coverage)

    typedef enum { AckAll, NackAddress, NackData } ack_e;
    typedef enum { StretchNone, StretchShort, StretchLong } stretch_e;

    adr_i2c_config cfg;

    covergroup cg_i2c with function sample(bit device, bit read, int unsigned bytes, ack_e ack,
                                           bit rep_start, stretch_e stretch);
      option.per_instance       = 1;
      option.get_inst_coverage  = 1;  // get_inst_coverage() reports this instance only
      cp_addr: coverpoint device {
        bins device = {1'b1};
        bins other  = {1'b0};
      }
      cp_dir: coverpoint read {
        bins write = {1'b0};
        bins read  = {1'b1};
      }
      cp_bytes: coverpoint bytes {
        bins one  = {1};
        bins few  = {[2:4]};
        bins more = {[5:$]};
      }
      cp_ack: coverpoint ack;
      cp_rep_start: coverpoint rep_start {
        bins no  = {1'b0};
        bins yes = {1'b1};
      }
      cp_stretch: coverpoint stretch;
      x_dir_ack:     cross cp_dir, cp_ack;
      x_dir_stretch: cross cp_dir, cp_stretch;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_i2c = new();
      cg_i2c.set_inst_name({get_full_name(), ".cg_i2c"});
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (cfg == null && !uvm_config_db #(adr_i2c_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_i2c_config not set for the coverage")
    endfunction

    function void write(adr_i2c_item t);
      ack_e     ack     = AckAll;
      stretch_e stretch = StretchNone;
      if (!t.addr_ack) ack = NackAddress;
      else foreach (t.acks[i])
        if (t.acks[i] !== 1'b0 && (!t.read || i < t.acks.size() - 1)) ack = NackData;
      if (cfg.stretch_ns >= 1000)  stretch = StretchLong;
      else if (cfg.stretch_ns > 0) stretch = StretchShort;
      cg_i2c.sample(t.addr == cfg.device_addr, t.read, t.data.size(), ack, t.rep_start, stretch);
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("cg_i2c %.1f%%", cg_i2c.get_inst_coverage()), UVM_LOW)
    endfunction
  endclass

  class adr_i2c_agent extends uvm_agent;
    `uvm_component_utils(adr_i2c_agent)

    adr_i2c_config       cfg;
    adr_i2c_monitor      mon;
    adr_i2c_slave_driver drv;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_i2c_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_i2c_config not set for the agent")
      uvm_config_db #(adr_i2c_config)::set(this, "*", "cfg", cfg);
      mon = adr_i2c_monitor::type_id::create("mon", this);
      if (cfg.is_active == UVM_ACTIVE) drv = adr_i2c_slave_driver::type_id::create("drv", this);
    endfunction
  endclass

endpackage
