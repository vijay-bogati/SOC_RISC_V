/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_jtag_agent_pkg.sv
 Module/class Name             : adr_jtag_agent_pkg, adr_jtag_item, adr_jtag_config, adr_jtag_driver, adr_jtag_monitor, adr_jtag_agent
 Author                        : Vijay Bogati
 Description                   : UVM JTAG agent: item, configuration, driver, sequencer, TAP-state monitor with TDO enable check, agent (active)
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). Reusable for any IEEE 1149.1 TAP; it knows nothing about RISC-V debug,
// which is layered on top as sequences (adr_riscv_dbg_pkg).
//
// One item is one TAP operation:
//   JtagTapReset  TMS high for reset_tcks clocks, then one clock to Run-Test/Idle.
//   JtagScan      select ir (an IR scan only when it differs from the current instruction), scan
//                 dr_bits bits of dr_in through the data register, return what came out in dr_out,
//                 then idle_tcks clocks in Run-Test/Idle.
//   JtagWait      wait_clocks falling edges of the system clock, pins unchanged.
// Every operation starts and ends in Run-Test/Idle with TCK low.
//
// The monitor follows the TAP state machine on TCK rising edges and checks TDO's output enable:
// it must be high exactly while the TAP is in Shift-DR or Shift-IR (TDO is driven from the
// falling edge after entering the state until the falling edge after leaving it).

package adr_jtag_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum { JtagTapReset, JtagScan, JtagWait } adr_jtag_op_e;

  // IEEE 1149.1 TAP controller states.
  typedef enum {
    TapTestLogicReset, TapRunTestIdle,
    TapSelectDrScan, TapCaptureDr, TapShiftDr, TapExit1Dr, TapPauseDr, TapExit2Dr, TapUpdateDr,
    TapSelectIrScan, TapCaptureIr, TapShiftIr, TapExit1Ir, TapPauseIr, TapExit2Ir, TapUpdateIr
  } adr_jtag_tap_state_e;

  // The state after one TCK rising edge with this TMS.
  function automatic adr_jtag_tap_state_e jtag_next_state(adr_jtag_tap_state_e s, logic tms);
    case (s)
      TapTestLogicReset: return tms ? TapTestLogicReset : TapRunTestIdle;
      TapRunTestIdle:    return tms ? TapSelectDrScan   : TapRunTestIdle;
      TapSelectDrScan:   return tms ? TapSelectIrScan   : TapCaptureDr;
      TapCaptureDr:      return tms ? TapExit1Dr        : TapShiftDr;
      TapShiftDr:        return tms ? TapExit1Dr        : TapShiftDr;
      TapExit1Dr:        return tms ? TapUpdateDr       : TapPauseDr;
      TapPauseDr:        return tms ? TapExit2Dr        : TapPauseDr;
      TapExit2Dr:        return tms ? TapUpdateDr       : TapShiftDr;
      TapUpdateDr:       return tms ? TapSelectDrScan   : TapRunTestIdle;
      TapSelectIrScan:   return tms ? TapTestLogicReset : TapCaptureIr;
      TapCaptureIr:      return tms ? TapExit1Ir        : TapShiftIr;
      TapShiftIr:        return tms ? TapExit1Ir        : TapShiftIr;
      TapExit1Ir:        return tms ? TapUpdateIr       : TapPauseIr;
      TapPauseIr:        return tms ? TapExit2Ir        : TapPauseIr;
      TapExit2Ir:        return tms ? TapUpdateIr       : TapShiftIr;
      TapUpdateIr:       return tms ? TapSelectDrScan   : TapRunTestIdle;
    endcase
    return TapTestLogicReset;
  endfunction

  class adr_jtag_item extends uvm_sequence_item;
    adr_jtag_op_e op;
    logic [31:0]  ir;           // JtagScan: instruction
    logic [63:0]  dr_in;        // JtagScan: data shifted in, bit 0 first
    int unsigned  dr_bits;      // JtagScan: data register length, 1 to 64
    int unsigned  idle_tcks;    // JtagScan: Run-Test/Idle clocks after the scan
    int unsigned  wait_clocks;  // JtagWait: system clocks
    logic [63:0]  dr_out;       // JtagScan: data shifted out (response)

    `uvm_object_utils_begin(adr_jtag_item)
      `uvm_field_enum(adr_jtag_op_e, op, UVM_ALL_ON)
      `uvm_field_int(ir, UVM_ALL_ON)
      `uvm_field_int(dr_in, UVM_ALL_ON)
      `uvm_field_int(dr_bits, UVM_ALL_ON | UVM_DEC)
      `uvm_field_int(idle_tcks, UVM_ALL_ON | UVM_DEC)
      `uvm_field_int(wait_clocks, UVM_ALL_ON | UVM_DEC)
      `uvm_field_int(dr_out, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "adr_jtag_item");
      super.new(name);
    endfunction
  endclass

  class adr_jtag_config extends uvm_object;
    `uvm_object_utils(adr_jtag_config)

    virtual adr_jtag_if vif;
    int unsigned        tck_half_cycles = 4;      // system clocks per TCK half period
    int unsigned        reset_tcks      = 6;      // TMS-high clocks to reach Test-Logic-Reset
    int unsigned        ir_bits         = 5;      // instruction register length
    logic [31:0]        reset_ir        = 32'h1;  // instruction selected by a TAP reset (IDCODE)
    bit                 check_tdo_oe    = 1'b1;   // monitor: check TDO's output enable
    // State the TAP enters while TRST is low: Test-Logic-Reset in IEEE 1149.1; some TAPs go to
    // Run-Test/Idle instead, which the monitor must know to follow them from reset.
    adr_jtag_tap_state_e trst_state     = TapTestLogicReset;

    function new(string name = "adr_jtag_config");
      super.new(name);
    endfunction
  endclass

  typedef uvm_sequencer #(adr_jtag_item) adr_jtag_sequencer;

  class adr_jtag_driver extends uvm_driver #(adr_jtag_item);
    `uvm_component_utils(adr_jtag_driver)

    adr_jtag_config cfg;
    logic [31:0]    current_ir;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_jtag_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_jtag_config not set for the driver")
      current_ir = cfg.reset_ir;
    endfunction

    // TRST follows the system reset; then one item at a time.
    task run_phase(uvm_phase phase);
      cfg.vif.trst_n = 1'b0;
      wait (cfg.vif.rst_n === 1'b1);
      cfg.vif.trst_n = 1'b1;
      forever begin
        seq_item_port.get_next_item(req);
        case (req.op)
          JtagTapReset: tap_reset();
          JtagScan:     scan(req);
          JtagWait:     repeat (req.wait_clocks) @(negedge cfg.vif.clk);
        endcase
        seq_item_port.item_done();
      end
    endtask

    // One TCK clock: set TMS and TDI, half a period later sample TDO and raise TCK,
    // half a period later lower TCK.
    task tck(input logic tms, input logic tdi, output logic tdo);
      cfg.vif.tms = tms;
      cfg.vif.tdi = tdi;
      repeat (cfg.tck_half_cycles) @(negedge cfg.vif.clk);
      tdo = cfg.vif.tdo;
      cfg.vif.tck = 1'b1;
      repeat (cfg.tck_half_cycles) @(negedge cfg.vif.clk);
      cfg.vif.tck = 1'b0;
    endtask

    task tap_reset();
      logic unused;
      repeat (cfg.reset_tcks) tck(1'b1, 1'b0, unused);
      tck(1'b0, 1'b0, unused);  // Run-Test/Idle
      current_ir = cfg.reset_ir;
    endtask

    // From Shift-xR: shift the bits (TMS high on the last), Update-xR, then Run-Test/Idle.
    task shift(input logic [63:0] value, input int unsigned bits, output logic [63:0] out);
      logic bit_out, unused;
      out = '0;
      for (int unsigned i = 0; i < bits; i++) begin
        tck(i == bits - 1, value[i], bit_out);
        out[i] = bit_out;
      end
      tck(1'b1, 1'b0, unused);  // Update
      tck(1'b0, 1'b0, unused);  // Run-Test/Idle
    endtask

    task scan(adr_jtag_item item);
      logic        unused;
      logic [63:0] ir_out;
      if (item.ir != current_ir) begin
        tck(1'b1, 1'b0, unused);  // Select-DR-Scan
        tck(1'b1, 1'b0, unused);  // Select-IR-Scan
        tck(1'b0, 1'b0, unused);  // Capture-IR
        tck(1'b0, 1'b0, unused);  // Shift-IR
        shift(64'(item.ir), cfg.ir_bits, ir_out);
        current_ir = item.ir;
      end
      tck(1'b1, 1'b0, unused);    // Select-DR-Scan
      tck(1'b0, 1'b0, unused);    // Capture-DR
      tck(1'b0, 1'b0, unused);    // Shift-DR
      shift(item.dr_in, item.dr_bits, item.dr_out);
      repeat (item.idle_tcks) tck(1'b0, 1'b0, unused);
    endtask
  endclass

  // Follows the TAP state on TCK rising edges (TRST puts it in cfg.trst_state). On each rising
  // edge, before the state moves on, TDO's enable must equal "the TAP is in Shift-DR or Shift-IR":
  // the TAP updated the enable on the falling edge in between, from the same state.
  class adr_jtag_monitor extends uvm_monitor;
    `uvm_component_utils(adr_jtag_monitor)

    adr_jtag_config      cfg;
    adr_jtag_tap_state_e state;
    int unsigned         tcks, tdo_oe_errors;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_jtag_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_jtag_config not set for the monitor")
    endfunction

    task run_phase(uvm_phase phase);
      state = cfg.trst_state;
      fork
        forever begin
          @(negedge cfg.vif.trst_n);
          state = cfg.trst_state;
        end
        forever begin
          @(posedge cfg.vif.tck);
          if (cfg.vif.trst_n !== 1'b1) continue;
          tcks++;
          if (cfg.check_tdo_oe) begin
            logic expected = (state == TapShiftDr || state == TapShiftIr);
            if (cfg.vif.tdo_oe !== expected) begin
              tdo_oe_errors++;
              `uvm_error("JTAG_TDO", $sformatf("TDO enable is %b in %s, expected %b", cfg.vif.tdo_oe,
                                               state.name(), expected))
            end
          end
          state = jtag_next_state(state, cfg.vif.tms);
        end
      join
    endtask

    function void report_phase(uvm_phase phase);
      if (tcks != 0)
        `uvm_info("JTAG", $sformatf("%0d TCK cycles, TDO enable %s", tcks,
                                    !cfg.check_tdo_oe ? "not checked" :
                                    tdo_oe_errors == 0 ? "correct on every one" :
                                    $sformatf("wrong on %0d", tdo_oe_errors)), UVM_LOW)
    endfunction
  endclass

  // Active: the driver returns each scan's output in the item, which is all the debug sequences
  // need; the monitor checks the TAP's TDO enable.
  class adr_jtag_agent extends uvm_agent;
    `uvm_component_utils(adr_jtag_agent)

    adr_jtag_config    cfg;
    adr_jtag_sequencer sqr;
    adr_jtag_driver    drv;
    adr_jtag_monitor   mon;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_jtag_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_jtag_config not set for the agent")
      uvm_config_db #(adr_jtag_config)::set(this, "drv", "cfg", cfg);
      uvm_config_db #(adr_jtag_config)::set(this, "mon", "cfg", cfg);
      mon = adr_jtag_monitor::type_id::create("mon", this);
      sqr = adr_jtag_sequencer::type_id::create("sqr", this);
      drv = adr_jtag_driver::type_id::create("drv", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

endpackage
