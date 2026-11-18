/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_adc_agent_pkg.sv
 Module/class Name             : adr_adc_agent_pkg
 Author                        : Vijay Bogati
 Description                   : UVM ADC agent: item, configuration, monitor, analog source driver and agent
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). Reusable at IP level (adr_adc_ctrl) and SoC level.
//
// Monitor: one item per DAC code the controller tries, with the comparator answer. Like the
// interface, the agent has no clock: it reacts to the controller's outputs.
//
// Analog source driver (active agent): puts cfg.level[] on the interface at the start of the run;
// a test can change a level at any time with set_level(). The comparator itself is in adr_adc_if.

package adr_adc_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class adr_adc_item extends uvm_sequence_item;
    logic       channel;
    logic [7:0] dac_code;
    logic       compare;

    `uvm_object_utils_begin(adr_adc_item)
      `uvm_field_int(channel, UVM_ALL_ON)
      `uvm_field_int(dac_code, UVM_ALL_ON)
      `uvm_field_int(compare, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "adr_adc_item");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf("channel %0d code %2h: input %s", channel, dac_code,
                       compare ? "at or above" : "below");
    endfunction
  endclass

  class adr_adc_config extends uvm_object;
    `uvm_object_utils(adr_adc_config)

    virtual adr_adc_if      vif;
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    logic [7:0]             level [2] = '{8'h00, 8'h00};

    function new(string name = "adr_adc_config");
      super.new(name);
    endfunction
  endclass

  class adr_adc_monitor extends uvm_monitor;
    `uvm_component_utils(adr_adc_monitor)

    uvm_analysis_port #(adr_adc_item) ap;
    adr_adc_config                    cfg;
    int unsigned                      steps;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_adc_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_adc_config not set for the monitor")
    endfunction

    // One item for every new DAC code or channel the controller puts out, once the comparator
    // has answered (the comparator has no delay, so its output is already settled).
    task run_phase(uvm_phase phase);
      forever begin
        @(cfg.vif.dac_code or cfg.vif.channel);
        #0;
        if ($isunknown({cfg.vif.channel, cfg.vif.dac_code})) continue;
        begin
          adr_adc_item item = adr_adc_item::type_id::create("item");
          item.channel  = cfg.vif.channel;
          item.dac_code = cfg.vif.dac_code;
          item.compare  = cfg.vif.compare;
          steps++;
          `uvm_info("ADC", item.convert2string(), UVM_HIGH)
          ap.write(item);
        end
      end
    endtask

    function void report_phase(uvm_phase phase);
      `uvm_info("ADC", $sformatf("%0d DAC code changes", steps), UVM_LOW)
    endfunction
  endclass

  class adr_adc_driver extends uvm_driver #(adr_adc_item);
    `uvm_component_utils(adr_adc_driver)

    adr_adc_config cfg;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_adc_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_adc_config not set for the driver")
    endfunction

    // At time 0, while the chip is still in reset.
    task run_phase(uvm_phase phase);
      set_level(0, cfg.level[0]);
      set_level(1, cfg.level[1]);
    endtask

    function void set_level(int unsigned channel, logic [7:0] value);
      cfg.level[channel]     = value;
      cfg.vif.level[channel] = value;
    endfunction
  endclass

  class adr_adc_agent extends uvm_agent;
    `uvm_component_utils(adr_adc_agent)

    adr_adc_config  cfg;
    adr_adc_monitor mon;
    adr_adc_driver  drv;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_adc_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_adc_config not set for the agent")
      uvm_config_db #(adr_adc_config)::set(this, "*", "cfg", cfg);
      mon = adr_adc_monitor::type_id::create("mon", this);
      if (cfg.is_active == UVM_ACTIVE) drv = adr_adc_driver::type_id::create("drv", this);
    endfunction
  endclass

endpackage
