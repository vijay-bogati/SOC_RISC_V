/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_axi_monitor_pkg.sv
 Module/class Name             : adr_axi_monitor_pkg
 Author                        : Vijay Bogati
 Description                   : UVM AXI4 monitor: transaction item, configuration, monitor with protocol checks, passive agent
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). Reusable on any AXI4 port, at IP level or SoC level.
//
// The monitor builds whole transactions from the handshakes on the five channels:
//   write   AW, its W beats (which may come before the AW), then B with the same ID
//   read    AR, then R beats with the same ID up to the last one
//   atomic  an AW with ATOP set: the write, and for loads, swaps and compares also R beats
// Responses with the same ID come back in request order (AXI4 rule); different IDs may mix.
// Each finished transaction goes to the analysis port. Checks, reported as UVM errors:
//   - while VALID is high and READY low, VALID stays high and the payload does not change
//     (all five channels: AW, W, AR from the initiator, B and R from the target);
//   - a B or R arrives only for an ID with a request outstanding;
//   - a write has len+1 W beats with WLAST on the last only; a read has len+1 R beats with RLAST
//     on the last only.
// SLVERR and DECERR responses are counted, not reported as errors: tests cause them on purpose.
// A reset of the port (rst_n low) drops everything outstanding.

package adr_axi_monitor_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  typedef enum { AxiRead, AxiWrite, AxiAtomic } adr_axi_kind_e;

  class adr_axi_item extends uvm_sequence_item;
    adr_axi_kind_e kind;
    logic [7:0]    id;
    logic [63:0]   addr;
    logic [7:0]    len;
    logic [2:0]    size;
    logic [1:0]    burst;
    logic          lock;
    logic [5:0]    atop;
    logic [63:0]   wdata [$];
    logic [7:0]    wstrb [$];
    logic [63:0]   rdata [$];
    logic [1:0]    resp;        // the worst response of the transaction
    longint        start_cycle;  // port clocks since reset, at the address handshake
    longint        end_cycle;    // at the last response
    bit            b_done;       // write response seen
    bit            r_done;       // last read beat seen

    `uvm_object_utils_begin(adr_axi_item)
      `uvm_field_enum(adr_axi_kind_e, kind, UVM_ALL_ON)
      `uvm_field_int(id, UVM_ALL_ON)
      `uvm_field_int(addr, UVM_ALL_ON)
      `uvm_field_int(len, UVM_ALL_ON | UVM_DEC)
      `uvm_field_int(size, UVM_ALL_ON | UVM_DEC)
      `uvm_field_int(atop, UVM_ALL_ON)
      `uvm_field_int(resp, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "adr_axi_item");
      super.new(name);
    endfunction

    function bit expects_read_data();
      return kind == AxiRead || (kind == AxiAtomic && atop[5]);
    endfunction

    function string convert2string();
      string text = $sformatf("%s id %0h addr %h len %0d size %0d", kind.name(), id, addr, len, size);
      if (kind == AxiAtomic) text = {text, $sformatf(" atop %h", atop)};
      if (wdata.size()) text = {text, $sformatf(" wdata[0] %h strb %h", wdata[0], wstrb[0])};
      if (rdata.size()) text = {text, $sformatf(" rdata[0] %h", rdata[0])};
      return {text, $sformatf(" resp %0d", resp)};
    endfunction
  endclass

  class adr_axi_config extends uvm_object;
    `uvm_object_utils(adr_axi_config)

    virtual adr_axi_if vif;
    string             port_name = "axi";

    function new(string name = "adr_axi_config");
      super.new(name);
    endfunction
  endclass

  class adr_axi_monitor extends uvm_monitor;
    `uvm_component_utils(adr_axi_monitor)

    uvm_analysis_port #(adr_axi_item) ap;
    adr_axi_config                    cfg;
    int unsigned                      reads, writes, atomics, error_responses;

    // Outstanding work: writes waiting for data, data waiting for its AW, writes and reads
    // waiting for responses (per ID, oldest first).
    protected adr_axi_item   aw_waiting [$];
    protected adr_axi_item   w_bursts [$];
    protected adr_axi_item   w_open;
    protected adr_axi_item   b_waiting [logic [7:0]][$];
    protected adr_axi_item   r_waiting [logic [7:0]][$];
    protected longint        cycle;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_axi_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_axi_config not set for the monitor")
    endfunction

    function void forget_all();
      aw_waiting.delete();
      w_bursts.delete();
      w_open = null;
      b_waiting.delete();
      r_waiting.delete();
    endfunction

    task run_phase(uvm_phase phase);
      forever begin
        @(cfg.vif.mon_cb);
        if (cfg.vif.mon_cb.rst_n !== 1'b1) begin
          forget_all();
          cycle = 0;
          continue;
        end
        cycle++;
        check_stable();
        take_aw();
        take_w();
        pair_writes();
        take_b();
        take_ar();
        take_r();
      end
    endtask

    // ---- Channel handshakes ----

    function void take_aw();
      adr_axi_item item;
      if (!(cfg.vif.mon_cb.aw_valid && cfg.vif.mon_cb.aw_ready)) return;
      item = adr_axi_item::type_id::create("write");
      item.kind        = (cfg.vif.mon_cb.aw_atop != 6'b0) ? AxiAtomic : AxiWrite;
      item.id          = cfg.vif.mon_cb.aw_id;
      item.addr        = cfg.vif.mon_cb.aw_addr;
      item.len         = cfg.vif.mon_cb.aw_len;
      item.size        = cfg.vif.mon_cb.aw_size;
      item.burst       = cfg.vif.mon_cb.aw_burst;
      item.lock        = cfg.vif.mon_cb.aw_lock;
      item.atop        = cfg.vif.mon_cb.aw_atop;
      item.resp        = 2'b00;
      item.start_cycle = cycle;
      aw_waiting.push_back(item);
      // Atomic loads, swaps and compares also answer on R, with the AW's ID.
      if (item.expects_read_data()) r_waiting[item.id].push_back(item);
    endfunction

    function void take_w();
      if (!(cfg.vif.mon_cb.w_valid && cfg.vif.mon_cb.w_ready)) return;
      if (w_open == null) w_open = adr_axi_item::type_id::create("wdata");
      w_open.wdata.push_back(cfg.vif.mon_cb.w_data);
      w_open.wstrb.push_back(cfg.vif.mon_cb.w_strb);
      if (cfg.vif.mon_cb.w_last) begin
        w_bursts.push_back(w_open);
        w_open = null;
      end
    endfunction

    // W bursts belong to AWs in order.
    function void pair_writes();
      while (aw_waiting.size() && w_bursts.size()) begin
        adr_axi_item item = aw_waiting.pop_front();
        adr_axi_item data = w_bursts.pop_front();
        item.wdata = data.wdata;
        item.wstrb = data.wstrb;
        if (item.wdata.size() != item.len + 1)
          `uvm_error(cfg.port_name, $sformatf("write burst has %0d W beats, AWLEN says %0d: %s",
                                              item.wdata.size(), item.len + 1, item.convert2string()))
        b_waiting[item.id].push_back(item);
      end
    endfunction

    function void take_b();
      adr_axi_item item;
      logic [7:0]  id;
      if (!(cfg.vif.mon_cb.b_valid && cfg.vif.mon_cb.b_ready)) return;
      id = cfg.vif.mon_cb.b_id;
      if (!b_waiting.exists(id) || b_waiting[id].size() == 0) begin
        `uvm_error(cfg.port_name, $sformatf("B with ID %0h, but no write with that ID has its data", id))
        return;
      end
      item = b_waiting[id].pop_front();
      item.resp   = worse(item.resp, cfg.vif.mon_cb.b_resp);
      item.b_done = 1'b1;
      // An atomic that also returns R data finishes when both its B and its last R are in.
      if (item.expects_read_data() && !item.r_done) return;
      item.end_cycle = cycle;
      finish(item);
    endfunction

    function void take_ar();
      adr_axi_item item;
      if (!(cfg.vif.mon_cb.ar_valid && cfg.vif.mon_cb.ar_ready)) return;
      item = adr_axi_item::type_id::create("read");
      item.kind        = AxiRead;
      item.id          = cfg.vif.mon_cb.ar_id;
      item.addr        = cfg.vif.mon_cb.ar_addr;
      item.len         = cfg.vif.mon_cb.ar_len;
      item.size        = cfg.vif.mon_cb.ar_size;
      item.burst       = cfg.vif.mon_cb.ar_burst;
      item.lock        = cfg.vif.mon_cb.ar_lock;
      item.resp        = 2'b00;
      item.start_cycle = cycle;
      r_waiting[item.id].push_back(item);
    endfunction

    function void take_r();
      adr_axi_item item;
      logic [7:0]  id;
      if (!(cfg.vif.mon_cb.r_valid && cfg.vif.mon_cb.r_ready)) return;
      id = cfg.vif.mon_cb.r_id;
      if (!r_waiting.exists(id) || r_waiting[id].size() == 0) begin
        `uvm_error(cfg.port_name, $sformatf("R with ID %0h, but no read with that ID is outstanding", id))
        return;
      end
      item = r_waiting[id][0];
      item.rdata.push_back(cfg.vif.mon_cb.r_data);
      item.resp = worse(item.resp, cfg.vif.mon_cb.r_resp);
      if (cfg.vif.mon_cb.r_last !== 1'b1) begin
        if (item.rdata.size() > item.len)
          `uvm_error(cfg.port_name, $sformatf("R beat %0d of a %0d-beat read has no RLAST: %s",
                                              item.rdata.size(), item.len + 1, item.convert2string()))
        return;
      end
      void'(r_waiting[id].pop_front());
      if (item.rdata.size() != item.len + 1)
        `uvm_error(cfg.port_name, $sformatf("RLAST after %0d beats of a %0d-beat read: %s",
                                            item.rdata.size(), item.len + 1, item.convert2string()))
      item.r_done = 1'b1;
      // An atomic finishes once both its B and its last R beat are in.
      if (item.kind == AxiAtomic && !item.b_done) return;
      item.end_cycle = cycle;
      finish(item);
    endfunction

    function logic [1:0] worse(logic [1:0] a, logic [1:0] b);
      // OKAY and EXOKAY are both good; SLVERR and DECERR are errors.
      return (b[1] && !a[1]) ? b : a;
    endfunction

    function void finish(adr_axi_item item);
      case (item.kind)
        AxiRead:   reads++;
        AxiWrite:  writes++;
        AxiAtomic: atomics++;
      endcase
      if (item.resp[1]) error_responses++;
      `uvm_info(cfg.port_name, item.convert2string(), UVM_HIGH)
      ap.write(item);
    endfunction

    // ---- VALID must stay high, and the payload unchanged, until READY ----

    protected bit          aw_held, w_held, ar_held, b_held, r_held;
    protected logic [93:0] aw_seen;
    protected logic [72:0] w_seen;
    protected logic [87:0] ar_seen;
    protected logic [9:0]  b_seen;
    protected logic [74:0] r_seen;

    function void check_stable();
      logic [93:0] aw_now = {cfg.vif.mon_cb.aw_id, cfg.vif.mon_cb.aw_addr, cfg.vif.mon_cb.aw_len,
                             cfg.vif.mon_cb.aw_size, cfg.vif.mon_cb.aw_burst, cfg.vif.mon_cb.aw_lock,
                             cfg.vif.mon_cb.aw_atop};
      logic [72:0] w_now  = {cfg.vif.mon_cb.w_data, cfg.vif.mon_cb.w_strb, cfg.vif.mon_cb.w_last};
      logic [87:0] ar_now = {cfg.vif.mon_cb.ar_id, cfg.vif.mon_cb.ar_addr, cfg.vif.mon_cb.ar_len,
                             cfg.vif.mon_cb.ar_size, cfg.vif.mon_cb.ar_burst, cfg.vif.mon_cb.ar_lock};
      logic [9:0]  b_now  = {cfg.vif.mon_cb.b_id, cfg.vif.mon_cb.b_resp};
      logic [74:0] r_now  = {cfg.vif.mon_cb.r_id, cfg.vif.mon_cb.r_data, cfg.vif.mon_cb.r_resp,
                             cfg.vif.mon_cb.r_last};
      if (aw_held && (cfg.vif.mon_cb.aw_valid !== 1'b1 || aw_now !== aw_seen))
        `uvm_error(cfg.port_name, "AW changed or dropped VALID before READY")
      if (w_held && (cfg.vif.mon_cb.w_valid !== 1'b1 || w_now !== w_seen))
        `uvm_error(cfg.port_name, "W changed or dropped VALID before READY")
      if (ar_held && (cfg.vif.mon_cb.ar_valid !== 1'b1 || ar_now !== ar_seen))
        `uvm_error(cfg.port_name, "AR changed or dropped VALID before READY")
      if (b_held && (cfg.vif.mon_cb.b_valid !== 1'b1 || b_now !== b_seen))
        `uvm_error(cfg.port_name, "B changed or dropped VALID before READY")
      if (r_held && (cfg.vif.mon_cb.r_valid !== 1'b1 || r_now !== r_seen))
        `uvm_error(cfg.port_name, "R changed or dropped VALID before READY")
      b_held  = cfg.vif.mon_cb.b_valid === 1'b1 && cfg.vif.mon_cb.b_ready !== 1'b1;
      r_held  = cfg.vif.mon_cb.r_valid === 1'b1 && cfg.vif.mon_cb.r_ready !== 1'b1;
      b_seen  = b_now;
      r_seen  = r_now;
      aw_held = cfg.vif.mon_cb.aw_valid === 1'b1 && cfg.vif.mon_cb.aw_ready !== 1'b1;
      w_held  = cfg.vif.mon_cb.w_valid === 1'b1 && cfg.vif.mon_cb.w_ready !== 1'b1;
      ar_held = cfg.vif.mon_cb.ar_valid === 1'b1 && cfg.vif.mon_cb.ar_ready !== 1'b1;
      aw_seen = aw_now;
      w_seen  = w_now;
      ar_seen = ar_now;
    endfunction

    function string summary();
      int unsigned open_count = aw_waiting.size();
      foreach (b_waiting[id]) open_count += b_waiting[id].size();
      foreach (r_waiting[id]) open_count += r_waiting[id].size();
      return $sformatf("%0d reads, %0d writes, %0d atomics, %0d error responses, %0d open at the end",
                       reads, writes, atomics, error_responses, open_count);
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info(cfg.port_name, summary(), UVM_HIGH)
    endfunction
  endclass

  class adr_axi_agent extends uvm_agent;
    `uvm_component_utils(adr_axi_agent)

    adr_axi_config  cfg;
    adr_axi_monitor mon;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_axi_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_axi_config not set for the agent")
      uvm_config_db #(adr_axi_config)::set(this, "mon", "cfg", cfg);
      mon = adr_axi_monitor::type_id::create("mon", this);
    endfunction
  endclass

endpackage
