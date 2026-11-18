/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_uart_agent_pkg.sv
 Module/class Name             : adr_uart_agent_pkg
 Author                        : Vijay Bogati
 Description                   : UVM UART agent: item, configuration, monitors, driver, coverage and agent, 8N1
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). Reusable at IP level and SoC level.
// The monitor decodes 8N1 frames from adr_uart_if.tx, counting system clocks per bit, and writes
// one adr_uart_item per byte to its analysis port, on the clock where the middle of the stop bit
// is reached. That is the same clock on which the Verilator bench's decoder handles the byte, so a
// subscriber that reads its bench's cycle count in write() gets the same count as the Verilator
// bench. The agent has no time base of its own. The number of bytes is reported at the end.
// With cfg.monitor_rx a second monitor (rx_mon) decodes the rx line the same way: the bytes sent
// into the DUT, whoever drives the line.
// adr_uart_coverage holds cg_uart (ADR_COVERAGE_PLAN 4.2): one sample per byte, from the
// monitors it is connected to (tx_export: from the DUT, rx_export: to the DUT).

package adr_uart_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // One byte seen on the line.
  class adr_uart_item extends uvm_sequence_item;
    rand logic [7:0] data;

    `uvm_object_utils_begin(adr_uart_item)
      `uvm_field_int(data, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "adr_uart_item");
      super.new(name);
    endfunction
  endclass

  class adr_uart_config extends uvm_object;
    `uvm_object_utils(adr_uart_config)

    virtual adr_uart_if vif;
    int unsigned        cycles_per_bit = 32;  // system clocks per bit: divisor x 16
    uvm_active_passive_enum is_active = UVM_PASSIVE;  // active: the driver owns the rx line
    bit                 monitor_rx = 1'b0;    // also decode the rx line (rx_mon)

    function new(string name = "adr_uart_config");
      super.new(name);
    endfunction
  endclass

  class adr_uart_monitor extends uvm_monitor;
    `uvm_component_utils(adr_uart_monitor)

    uvm_analysis_port #(adr_uart_item) ap;
    adr_uart_config                    cfg;
    bit                                rx_side;  // decode the rx line instead of tx
    int unsigned                       bytes;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_uart_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_uart_config not set for the monitor")
    endfunction

    // Wait half a bit after the falling edge, check the start bit is still low,
    // take 8 bits one bit apart (LSB first), then report in the middle of the stop bit.
    task run_phase(uvm_phase phase);
      typedef enum { Idle, Start, Data, Stop } state_e;
      state_e      state   = Idle;
      int unsigned count   = 0;
      int unsigned bit_idx = 0;
      logic [7:0]  shift   = '0;
      logic        line;
      forever begin
        @(cfg.vif.mon_cb);
        line = rx_side ? cfg.vif.mon_cb.rx : cfg.vif.mon_cb.tx;
        if (cfg.vif.mon_cb.rst_n !== 1'b1) begin
          state = Idle;
          count = 0;
          bit_idx = 0;
          shift = '0;
          continue;
        end
        case (state)
          Idle: if (line === 1'b0) begin
            state = Start;
            count = cfg.cycles_per_bit / 2 - 1;
          end
          Start: if (count == 0) begin
            state   = (line === 1'b0) ? Data : Idle;  // high again: a glitch
            count   = cfg.cycles_per_bit - 1;
            bit_idx = 0;
          end else count--;
          Data: if (count == 0) begin
            shift = {line, shift[7:1]};
            count = cfg.cycles_per_bit - 1;
            if (bit_idx == 7) state = Stop;
            bit_idx++;
          end else count--;
          Stop: if (count == 0) begin
            adr_uart_item item = adr_uart_item::type_id::create("item");
            item.data  = shift;
            bytes++;
            ap.write(item);
            state = Idle;
          end else count--;
        endcase
      end
    endtask

    function void report_phase(uvm_phase phase);
      `uvm_info("UART", $sformatf("%0d bytes %s", bytes, rx_side ? "sent to the DUT (rx line)" : "received from the DUT"), UVM_LOW)
    endfunction
  endclass

  // Sends each item's byte on the rx line: start bit, 8 data bits LSB first, one stop bit, no
  // parity, cycles_per_bit clocks per bit. The line is idle high between bytes.
  class adr_uart_driver extends uvm_driver #(adr_uart_item);
    `uvm_component_utils(adr_uart_driver)

    adr_uart_config cfg;
    int unsigned    sent;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_uart_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_uart_config not set for the driver")
    endfunction

    task run_phase(uvm_phase phase);
      cfg.vif.rx <= 1'b1;
      forever begin
        seq_item_port.get_next_item(req);
        send(req.data);
        sent++;
        seq_item_port.item_done();
      end
    endtask

    task send(logic [7:0] data);
      logic [9:0] frame = {1'b1, data, 1'b0};
      @(posedge cfg.vif.clk);
      for (int i = 0; i < 10; i++) begin
        cfg.vif.rx <= frame[i];
        repeat (cfg.cycles_per_bit) @(posedge cfg.vif.clk);
      end
    endtask

    function void report_phase(uvm_phase phase);
      `uvm_info("UART", $sformatf("%0d bytes sent to the chip", sent), UVM_LOW)
    endfunction
  endclass

  // Sends the given bytes in order.
  class adr_uart_send_seq extends uvm_sequence #(adr_uart_item);
    `uvm_object_utils(adr_uart_send_seq)

    logic [7:0] bytes [$];

    function new(string name = "adr_uart_send_seq");
      super.new(name);
    endfunction

    task body();
      foreach (bytes[i]) begin
        req = adr_uart_item::type_id::create("req");
        start_item(req);
        req.data = bytes[i];
        finish_item(req);
      end
    endtask
  endclass

  // cg_uart: one sample per byte. Data class, direction, crossed; bit time against the configured
  // rate. Frame is always 8N1 here (the monitors decode only 8N1), so it has no coverpoint yet.
  `uvm_analysis_imp_decl(_uart_tx)
  `uvm_analysis_imp_decl(_uart_rx)

  class adr_uart_coverage extends uvm_component;
    `uvm_component_utils(adr_uart_coverage)

    uvm_analysis_imp_uart_tx #(adr_uart_item, adr_uart_coverage) tx_export;  // from the DUT
    uvm_analysis_imp_uart_rx #(adr_uart_item, adr_uart_coverage) rx_export;  // to the DUT
    adr_uart_config cfg;

    covergroup cg_uart with function sample(logic [7:0] data, bit to_dut, bit nominal_rate);
      option.per_instance       = 1;
      option.get_inst_coverage  = 1;  // get_inst_coverage() reports this instance only
      cp_data: coverpoint data {
        bins zero      = {8'h00};
        bins ones      = {8'hFF};
        bins printable = {[8'h20:8'h7E]};
        bins control   = {[8'h01:8'h1F], 8'h7F};
        bins others    = {[8'h80:8'hFE]};
      }
      cp_dir: coverpoint to_dut {
        bins from_dut = {1'b0};
        bins to_dut   = {1'b1};
      }
      cp_rate: coverpoint nominal_rate {
        bins configured = {1'b1};
      }
      x_dir_data: cross cp_dir, cp_data;
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      tx_export = new("tx_export", this);
      rx_export = new("rx_export", this);
      cg_uart   = new();
      cg_uart.set_inst_name({get_full_name(), ".cg_uart"});
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (cfg == null && !uvm_config_db #(adr_uart_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_uart_config not set for the coverage")
    endfunction

    // The bit time in use: the interface's (kept up to date by a scoreboard), else the configured.
    function bit nominal();
      return cfg.vif.cycles_per_bit == 0 || cfg.vif.cycles_per_bit == cfg.cycles_per_bit;
    endfunction

    function void write_uart_tx(adr_uart_item t);
      cg_uart.sample(t.data, 1'b0, nominal());
    endfunction

    function void write_uart_rx(adr_uart_item t);
      cg_uart.sample(t.data, 1'b1, nominal());
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("cg_uart %.1f%%", cg_uart.get_inst_coverage()), UVM_LOW)
    endfunction
  endclass

  // Passive: monitor only. Active (cfg.is_active): also a sequencer and a driver on the rx line.
  // cfg.monitor_rx adds rx_mon on the rx line.
  class adr_uart_agent extends uvm_agent;
    `uvm_component_utils(adr_uart_agent)

    adr_uart_config                 cfg;
    adr_uart_monitor                mon;
    adr_uart_monitor                rx_mon;
    uvm_sequencer #(adr_uart_item)  sqr;
    adr_uart_driver                 drv;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_uart_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_uart_config not set for the agent")
      uvm_config_db #(adr_uart_config)::set(this, "mon", "cfg", cfg);
      mon = adr_uart_monitor::type_id::create("mon", this);
      if (cfg.monitor_rx) begin
        uvm_config_db #(adr_uart_config)::set(this, "rx_mon", "cfg", cfg);
        rx_mon = adr_uart_monitor::type_id::create("rx_mon", this);
        rx_mon.rx_side = 1'b1;
      end
      if (cfg.is_active == UVM_ACTIVE) begin
        uvm_config_db #(adr_uart_config)::set(this, "drv", "cfg", cfg);
        sqr = uvm_sequencer #(adr_uart_item)::type_id::create("sqr", this);
        drv = adr_uart_driver::type_id::create("drv", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if (cfg.is_active == UVM_ACTIVE) drv.seq_item_port.connect(sqr.seq_item_export);
      cfg.vif.cycles_per_bit = cfg.cycles_per_bit;  // bit time for the interface's checks
    endfunction
  endclass

endpackage
