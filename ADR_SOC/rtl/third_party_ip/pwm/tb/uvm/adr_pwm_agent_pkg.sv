/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_pwm_agent_pkg.sv
 Module/class Name             : adr_pwm_agent_pkg
 Author                        : Vijay Bogati
 Description                   : UVM PWM agent: item, configuration, monitor and agent (passive)
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). Reusable at IP level and SoC level.
// The monitor measures each output in simulation time, with no clock: at every rising edge after
// the first it writes one item with the period (rising edge to rising edge) and the high time.

package adr_pwm_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class adr_pwm_item extends uvm_sequence_item;
    int unsigned channel;
    realtime     period;  // rising edge to rising edge
    realtime     high;    // rising edge to falling edge

    `uvm_object_utils_begin(adr_pwm_item)
      `uvm_field_int(channel, UVM_ALL_ON | UVM_DEC)
    `uvm_object_utils_end

    function new(string name = "adr_pwm_item");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf("channel %0d period %0t high %0t", channel, period, high);
    endfunction
  endclass

  class adr_pwm_config extends uvm_object;
    `uvm_object_utils(adr_pwm_config)

    virtual adr_pwm_if vif;

    function new(string name = "adr_pwm_config");
      super.new(name);
    endfunction
  endclass

  class adr_pwm_monitor extends uvm_monitor;
    `uvm_component_utils(adr_pwm_monitor)

    uvm_analysis_port #(adr_pwm_item) ap;
    adr_pwm_config                    cfg;
    int unsigned                      periods [8];

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_pwm_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_pwm_config not set for the monitor")
    endfunction

    // On every change of the outputs, check each channel for a rising or falling edge.
    task run_phase(uvm_phase phase);
      realtime    rise_at [8];
      realtime    fall_at [8];
      bit         seen_rise [8] = '{default: 1'b0};
      bit         seen_fall [8] = '{default: 1'b0};  // a fall since the last rise
      logic [7:0] last = '0;
      forever begin
        logic [7:0] now;
        @(cfg.vif.pwm);
        now = cfg.vif.pwm;
        for (int ch = 0; ch < 8; ch++) begin
          if (now[ch] === 1'b0 && last[ch] === 1'b1) begin
            fall_at[ch]   = $realtime;
            seen_fall[ch] = 1'b1;
          end else if (now[ch] === 1'b1 && last[ch] === 1'b0) begin  // a real 0 to 1 edge, not from X
            if (seen_rise[ch] && seen_fall[ch]) begin
              adr_pwm_item item = adr_pwm_item::type_id::create("item");
              item.channel = ch;
              item.period  = $realtime - rise_at[ch];
              item.high    = fall_at[ch] - rise_at[ch];
              periods[ch]++;
              `uvm_info("PWM", item.convert2string(), UVM_HIGH)
              ap.write(item);
            end
            seen_rise[ch] = 1'b1;
            seen_fall[ch] = 1'b0;
            rise_at[ch]   = $realtime;
          end
        end
        last = now;
      end
    endtask

    function void report_phase(uvm_phase phase);
      string s = "";
      foreach (periods[ch]) s = {s, $sformatf(" %0d", periods[ch])};
      `uvm_info("PWM", {"periods measured on channels 0-7:", s}, UVM_LOW)
    endfunction
  endclass

  class adr_pwm_agent extends uvm_agent;
    `uvm_component_utils(adr_pwm_agent)

    adr_pwm_config  cfg;
    adr_pwm_monitor mon;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_pwm_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_pwm_config not set for the agent")
      uvm_config_db #(adr_pwm_config)::set(this, "mon", "cfg", cfg);
      mon = adr_pwm_monitor::type_id::create("mon", this);
    endfunction
  endclass

endpackage
