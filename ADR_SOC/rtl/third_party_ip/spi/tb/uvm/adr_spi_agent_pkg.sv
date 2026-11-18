/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_spi_agent_pkg.sv
 Module/class Name             : adr_spi_agent_pkg
 Author                        : Vijay Bogati
 Description                   : UVM SPI agent: item, configuration, monitor, memory slave driver, coverage and agent
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). Reusable at IP level and SoC level, for SPI and QSPI, mode 0.
// The agent works from the bus alone: serial clock edges and chip selects. No system clock.
//
// Monitor: one item per chip select low period, on any of the four chip selects (item.cs), with
// the bytes from the master (sdo) and to the master (sdi), sampled on rising edges of sclk; four
// bits per edge while quad is high. Only chip select 0 has the slave, so on the others the
// master reads zeros.
//
// Slave driver (active agent): a serial memory on chip select 0, 24-bit addresses.
//   0x9F  read the 3-byte device ID (repeats while the master keeps clocking)
//   0x03  3-byte address, then read data; the address counts up
//   0x02  3-byte address, then write data; the address counts up
// Bytes come in on rising edges and go out on falling edges, most significant bit first, and
// the line width is taken at every edge, so a master may switch between one and four lines
// between phases. Chip select high ends a command. Unwritten bytes read as 0xFF, like an erased
// flash. A test can read or preset the memory with peek() and poke() (backdoor).
//
// adr_spi_coverage holds cg_spi (ADR_COVERAGE_PLAN 4.2), one sample per monitor item.
// cfg.single_line marks an SPI (not QSPI) master; the agent passes it to the interface, where it
// enables the check that data lines 1-3 stay low.

package adr_spi_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class adr_spi_item extends uvm_sequence_item;
    int unsigned cs;       // chip select of the transfer, 0-3
    bit         quad;      // the last byte used four lines
    logic [7:0] mosi [$];  // from the master; mosi[0] is the command
    logic [7:0] miso [$];  // to the master, the same number of bytes

    `uvm_object_utils_begin(adr_spi_item)
      `uvm_field_int(cs, UVM_ALL_ON)
      `uvm_field_int(quad, UVM_ALL_ON)
      `uvm_field_queue_int(mosi, UVM_ALL_ON)
      `uvm_field_queue_int(miso, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "adr_spi_item");
      super.new(name);
    endfunction

    function string convert2string();
      string text = $sformatf("chip select %0d, %0d bytes (master/slave):", cs, mosi.size());
      foreach (mosi[i]) text = {text, $sformatf(" %2h/%2h", mosi[i], miso[i])};
      return text;
    endfunction
  endclass

  class adr_spi_config extends uvm_object;
    `uvm_object_utils(adr_spi_config)

    virtual adr_spi_if      vif;
    uvm_active_passive_enum is_active = UVM_ACTIVE;
    logic [23:0]            device_id = 24'h000000;
    bit                     single_line = 1'b0;  // SPI master: one data line each way

    function new(string name = "adr_spi_config");
      super.new(name);
    endfunction
  endclass

  // Collects whole bytes from the lines at one rising edge of sclk.
  class adr_spi_shifter;
    logic [7:0]  mosi_byte, miso_byte;
    int unsigned bit_total;

    // Returns 1 when a byte is complete.
    function bit take(logic quad, logic [3:0] from_master, logic [3:0] to_master);
      if (quad) begin
        mosi_byte = {mosi_byte[3:0], from_master};
        miso_byte = {miso_byte[3:0], to_master};
        bit_total += 4;
      end else begin
        mosi_byte = {mosi_byte[6:0], from_master[0]};
        miso_byte = {miso_byte[6:0], to_master[1]};
        bit_total += 1;
      end
      if (bit_total < 8) return 1'b0;
      bit_total = 0;
      return 1'b1;
    endfunction
  endclass

  class adr_spi_monitor extends uvm_monitor;
    `uvm_component_utils(adr_spi_monitor)

    uvm_analysis_port #(adr_spi_item) ap;
    adr_spi_config                    cfg;
    int unsigned                      transfers;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_spi_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_spi_config not set for the monitor")
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        adr_spi_item    item    = adr_spi_item::type_id::create("item");
        adr_spi_shifter shifter = new();
        int unsigned    cs      = 0;
        wait (cfg.vif.csn inside {[4'h0:4'hE]});  // a chip select low (no X)
        while (cs < 3 && cfg.vif.csn[cs] !== 1'b0) cs++;
        item.cs = cs;
        fork
          forever begin
            @(cfg.vif.sclk_rise);
            if (shifter.take(cfg.vif.sclk_rise.quad, cfg.vif.sclk_rise.sdo, cfg.vif.sclk_rise.sdi)) begin
              item.quad = cfg.vif.sclk_rise.quad;
              item.mosi.push_back(shifter.mosi_byte);
              item.miso.push_back(shifter.miso_byte);
            end
          end
        join_none
        wait (cfg.vif.csn[cs] !== 1'b0);
        disable fork;
        if (item.mosi.size() > 0) begin
          transfers++;
          `uvm_info("SPI", item.convert2string(), UVM_HIGH)
          ap.write(item);
        end
      end
    endtask

    function void report_phase(uvm_phase phase);
      `uvm_info("SPI", $sformatf("%0d transfers", transfers), UVM_LOW)
    endfunction
  endclass

  class adr_spi_slave_driver extends uvm_driver #(adr_spi_item);
    `uvm_component_utils(adr_spi_slave_driver)

    typedef enum { GetCommand, GetAddress, TakeData, GiveData, GiveId, Skip } step_e;

    adr_spi_config cfg;
    logic [7:0]    memory [logic [23:0]];

    step_e         step;
    logic [7:0]    command;
    logic [23:0]   address;
    int unsigned   address_bytes, id_byte;
    logic [7:0]    in_byte, out_byte;
    int unsigned   in_bits, out_bits;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_spi_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_spi_config not set for the slave driver")
    endfunction

    function logic [7:0] peek(logic [23:0] addr);
      return memory.exists(addr) ? memory[addr] : 8'hFF;
    endfunction

    function void poke(logic [23:0] addr, logic [7:0] value);
      memory[addr] = value;
    endfunction

    // One command per chip select low period.
    task run_phase(uvm_phase phase);
      forever begin
        wait (cfg.vif.csn[0] === 1'b0);
        step     = GetCommand;
        in_bits  = 0;
        out_bits = 0;
        fork
          forever begin
            @(cfg.vif.sclk_rise);
            if (step inside {GetCommand, GetAddress, TakeData}) bits_in();
          end
          forever begin
            @(negedge cfg.vif.sclk);
            if (step inside {GiveData, GiveId}) bits_out();
          end
        join_none
        wait (cfg.vif.csn[0] !== 1'b0);
        disable fork;
        cfg.vif.slave_out <= 4'b0000;
      end
    endtask

    // Rising edge: shift in one or four bits; act on each whole byte.
    function void bits_in();
      if (cfg.vif.sclk_rise.quad) begin
        in_byte = {in_byte[3:0], cfg.vif.sclk_rise.sdo};
        in_bits += 4;
      end else begin
        in_byte = {in_byte[6:0], cfg.vif.sclk_rise.sdo[0]};
        in_bits += 1;
      end
      if (in_bits < 8) return;
      in_bits = 0;
      case (step)
        GetCommand: begin
          command       = in_byte;
          address_bytes = 0;
          id_byte       = 0;
          if (in_byte == 8'h9F)                        step = GiveId;
          else if (in_byte == 8'h03 || in_byte == 8'h02) step = GetAddress;
          else                                         step = Skip;
        end
        GetAddress: begin
          address = {address[15:0], in_byte};
          if (++address_bytes == 3) step = (command == 8'h02) ? TakeData : GiveData;
        end
        TakeData: begin
          memory[address] = in_byte;
          address++;
        end
        default: ;
      endcase
    endfunction

    // Falling edge: put out the next one or four bits, starting a new byte when needed.
    function void bits_out();
      if (out_bits == 0) begin
        if (step == GiveId) begin
          out_byte = cfg.device_id[8 * (2 - id_byte) +: 8];
          id_byte  = (id_byte + 1) % 3;
        end else begin
          out_byte = peek(address);
          address++;
        end
        out_bits = 8;
      end
      if (cfg.vif.quad) begin
        cfg.vif.slave_out <= out_byte[7:4];
        out_byte = out_byte << 4;
        out_bits = (out_bits > 4) ? out_bits - 4 : 0;
      end else begin
        cfg.vif.slave_out <= {2'b00, out_byte[7], 1'b0};  // one-line data goes out on line 1
        out_byte = out_byte << 1;
        out_bits--;
      end
    endfunction
  endclass

  // cg_spi: one sample per transfer. Command, lines (crossed), length in bytes, chip select, and
  // the address of a read or write within the 256-byte memory of the Verilator bench's model.
  // Instances are per controller (option.per_instance), which gives the controller x chip
  // select cross of the plan.
  class adr_spi_coverage extends uvm_subscriber #(adr_spi_item);
    `uvm_component_utils(adr_spi_coverage)

    covergroup cg_spi with function sample(logic [7:0] command, bit quad, int unsigned length,
                                           int unsigned cs, bit has_addr, logic [7:0] addr);
      option.per_instance       = 1;
      option.get_inst_coverage  = 1;  // get_inst_coverage() reports this instance only
      cp_command: coverpoint command {
        bins id    = {8'h9F};
        bins read  = {8'h03};
        bins write = {8'h02};
        bins other = {[8'h00:8'h01], [8'h04:8'h9E], [8'hA0:8'hFF]};  // not default: crossed below
      }
      cp_lines: coverpoint quad {
        bins one  = {1'b0};
        bins four = {1'b1};
      }
      cp_length: coverpoint length {
        bins one   = {1};
        bins few   = {[2:4]};
        bins some  = {[5:16]};
        bins many  = {[17:$]};
      }
      cp_cs: coverpoint cs {
        bins cs[] = {[0:3]};
      }
      cp_addr: coverpoint addr iff (has_addr) {
        bins low    = {[8'h00:8'h55]};
        bins middle = {[8'h56:8'hAA]};
        bins top    = {[8'hAB:8'hFF]};
      }
      x_command_lines: cross cp_command, cp_lines {
        ignore_bins other = binsof(cp_command.other);
      }
    endgroup

    function new(string name, uvm_component parent);
      super.new(name, parent);
      cg_spi = new();
      cg_spi.set_inst_name({get_full_name(), ".cg_spi"});
    endfunction

    function void write(adr_spi_item t);
      bit has_addr = (t.mosi[0] inside {8'h02, 8'h03}) && t.mosi.size() >= 4;
      cg_spi.sample(t.mosi[0], t.quad, t.mosi.size(), t.cs, has_addr, has_addr ? t.mosi[3] : 8'h00);
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("COV", $sformatf("cg_spi %.1f%%", cg_spi.get_inst_coverage()), UVM_LOW)
    endfunction
  endclass

  class adr_spi_agent extends uvm_agent;
    `uvm_component_utils(adr_spi_agent)

    adr_spi_config       cfg;
    adr_spi_monitor      mon;
    adr_spi_slave_driver drv;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_spi_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_spi_config not set for the agent")
      uvm_config_db #(adr_spi_config)::set(this, "*", "cfg", cfg);
      mon = adr_spi_monitor::type_id::create("mon", this);
      if (cfg.is_active == UVM_ACTIVE) drv = adr_spi_slave_driver::type_id::create("drv", this);
    endfunction

    function void connect_phase(uvm_phase phase);
      cfg.vif.single_line = cfg.single_line;  // enables SPI-A06 in the interface
    endfunction
  endclass

endpackage
