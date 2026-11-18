/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_gpio_agent_pkg.sv
 Module/class Name             : adr_gpio_agent_pkg
 Author                        : Vijay Bogati
 Description                   : UVM GPIO agent: item, configuration, monitor and agent (passive)
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). Reusable at IP level and SoC level.
// The monitor writes one item each time the outputs or the direction bits change, with the inputs
// at that moment. It has no clock: it reacts to the pins. Items are printed at UVM_HIGH; a count is reported at the end.

package adr_gpio_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class adr_gpio_item extends uvm_sequence_item;
    logic [15:0] out;
    logic [15:0] dir;
    logic [15:0] in;

    `uvm_object_utils_begin(adr_gpio_item)
      `uvm_field_int(out, UVM_ALL_ON)
      `uvm_field_int(dir, UVM_ALL_ON)
      `uvm_field_int(in, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "adr_gpio_item");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf("out %4h dir %4h in %4h", out, dir, in);
    endfunction
  endclass

  class adr_gpio_config extends uvm_object;
    `uvm_object_utils(adr_gpio_config)

    virtual adr_gpio_if vif;
    uvm_active_passive_enum is_active = UVM_PASSIVE;  // active: the driver sets drv_in

    function new(string name = "adr_gpio_config");
      super.new(name);
    endfunction
  endclass

  class adr_gpio_monitor extends uvm_monitor;
    `uvm_component_utils(adr_gpio_monitor)

    uvm_analysis_port #(adr_gpio_item) ap;
    adr_gpio_config                    cfg;
    int unsigned                       changes;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_gpio_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_gpio_config not set for the monitor")
    endfunction

    // Every change of the outputs or direction bits, once the values have settled in that time step.
    task run_phase(uvm_phase phase);
      forever begin
        @(cfg.vif.out or cfg.vif.dir);
        #0;
        if ($isunknown({cfg.vif.out, cfg.vif.dir})) continue;
        begin
          adr_gpio_item item = adr_gpio_item::type_id::create("item");
          item.out = cfg.vif.out;
          item.dir = cfg.vif.dir;
          item.in  = cfg.vif.in;
          changes++;
          `uvm_info("GPIO", item.convert2string(), UVM_HIGH)
          ap.write(item);
        end
      end
    endtask

    function void report_phase(uvm_phase phase);
      `uvm_info("GPIO", $sformatf("%0d output or direction changes", changes), UVM_LOW)
    endfunction
  endclass

  // Puts each item's in value on the interface's drv_in (the levels the bench feeds the chip where
  // it has no loopback). drv_in starts at 0. out and dir of the item are not used.
  class adr_gpio_driver extends uvm_driver #(adr_gpio_item);
    `uvm_component_utils(adr_gpio_driver)

    adr_gpio_config cfg;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_gpio_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_gpio_config not set for the driver")
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        seq_item_port.get_next_item(req);
        cfg.vif.drv_in = req.in;
        seq_item_port.item_done();
      end
    endtask
  endclass

  // Sets the input levels once.
  class adr_gpio_drive_seq extends uvm_sequence #(adr_gpio_item);
    `uvm_object_utils(adr_gpio_drive_seq)

    logic [15:0] in;

    function new(string name = "adr_gpio_drive_seq");
      super.new(name);
    endfunction

    task body();
      req = adr_gpio_item::type_id::create("req");
      start_item(req);
      req.in = in;
      finish_item(req);
    endtask
  endclass

  // Passive: monitor only. Active (cfg.is_active): also a sequencer and a driver for the inputs.
  class adr_gpio_agent extends uvm_agent;
    `uvm_component_utils(adr_gpio_agent)

    adr_gpio_config                 cfg;
    adr_gpio_monitor                mon;
    uvm_sequencer #(adr_gpio_item)  sqr;
    adr_gpio_driver                 drv;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_gpio_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_gpio_config not set for the agent")
      uvm_config_db #(adr_gpio_config)::set(this, "mon", "cfg", cfg);
      mon = adr_gpio_monitor::type_id::create("mon", this);
      if (cfg.is_active == UVM_ACTIVE) begin
        uvm_config_db #(adr_gpio_config)::set(this, "drv", "cfg", cfg);
        sqr = uvm_sequencer #(adr_gpio_item)::type_id::create("sqr", this);
        drv = adr_gpio_driver::type_id::create("drv", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if (cfg.is_active == UVM_ACTIVE) drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

endpackage
