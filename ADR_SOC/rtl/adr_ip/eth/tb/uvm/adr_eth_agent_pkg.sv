/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_eth_agent_pkg.sv
 Module/class Name             : adr_eth_agent_pkg
 Author                        : Vijay Bogati
 Description                   : UVM Ethernet agent: frame item, configuration, 10GBASE-R transmit monitor and agent (passive)
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). Reusable at IP level (adr_eth) and SoC level.
//
// The monitor takes one 66-bit block per clock from the SerDes transmit side and:
//   1. descrambles the 64 data bits (self-synchronising scrambler 1 + x^39 + x^58, bit 0 first);
//      the first block after reset is used only to fill the descrambler;
//   2. decodes 64b/66b blocks: sync header 2'b10 is data, 2'b01 is control with a block type in
//      the low byte (start in lane 0 or 4, terminate after 0 to 7 bytes, idle);
//   3. collects each frame from start to terminate, checks the preamble and start-of-frame
//      delimiter, and checks the frame check sequence (CRC-32) over the rest.
// A bad sync header, preamble or frame check sequence is reported as an error.
//
// Active agents also have a receive monitor (rx_mon, tag ETH_RX), the same decoder and checks on
// the receive side, so the frames the driver sends into the chip are decoded and published too.
//
// The driver (active agent only) feeds the SerDes receive side, one 66-bit block per clock: idle
// blocks when it has nothing to send, and each item as a frame (start block in lane 0 with the
// preamble and delimiter, data blocks, terminate block, then one idle block), scrambled with the
// same scrambler. It appends the frame check sequence unless the item's append_fcs is 0. Frames
// shorter than 60 bytes before the FCS are padded with zeros, as a MAC does.

package adr_eth_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  localparam logic [1:0] SyncData = 2'b10, SyncCtrl = 2'b01;
  localparam logic [7:0] BlockIdle = 8'h1e, BlockStart0 = 8'h78, BlockStart4 = 8'h33;

  // Number of data bytes before a terminate character, or -1 if the block type is not a terminate.
  function automatic int term_bytes(logic [7:0] block_type);
    case (block_type)
      8'h87: return 0;
      8'h99: return 1;
      8'haa: return 2;
      8'hb4: return 3;
      8'hcc: return 4;
      8'hd2: return 5;
      8'he1: return 6;
      8'hff: return 7;
      default: return -1;
    endcase
  endfunction

  // CRC-32 of IEEE 802.3, bit-reversed form, over the given bytes.
  function automatic logic [31:0] crc32(const ref logic [7:0] bytes [$], input int unsigned len);
    logic [31:0] crc = 32'hFFFF_FFFF;
    for (int unsigned i = 0; i < len; i++) begin
      crc ^= {24'h0, bytes[i]};
      for (int b = 0; b < 8; b++) crc = crc[0] ? (crc >> 1) ^ 32'hEDB8_8320 : crc >> 1;
    end
    return ~crc;
  endfunction

  class adr_eth_item extends uvm_sequence_item;
    logic [7:0] bytes [$];  // destination address to frame check sequence, without the preamble
    bit         fcs_ok;
    bit         append_fcs = 1'b1;  // driver only: bytes stop before the FCS, the driver adds it

    `uvm_object_utils_begin(adr_eth_item)
      `uvm_field_queue_int(bytes, UVM_ALL_ON)
      `uvm_field_int(fcs_ok, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "adr_eth_item");
      super.new(name);
    endfunction

    function string convert2string();
      string s = $sformatf("frame of %0d bytes, FCS %s", bytes.size(), fcs_ok ? "good" : "BAD");
      if (bytes.size() >= 14)
        s = {s, $sformatf(", to %2h:%2h:%2h:%2h:%2h:%2h, type %2h%2h", bytes[0], bytes[1], bytes[2],
                          bytes[3], bytes[4], bytes[5], bytes[12], bytes[13])};
      return s;
    endfunction
  endclass

  class adr_eth_config extends uvm_object;
    `uvm_object_utils(adr_eth_config)

    virtual adr_eth_serdes_if vif;
    uvm_active_passive_enum   is_active = UVM_PASSIVE;  // active: the driver feeds the receive side

    function new(string name = "adr_eth_config");
      super.new(name);
    endfunction
  endclass

  class adr_eth_monitor extends uvm_monitor;
    `uvm_component_utils(adr_eth_monitor)

    uvm_analysis_port #(adr_eth_item) ap;
    adr_eth_config                    cfg;
    int unsigned                      frames, bad_frames, idle_blocks;
    bit                               rx_side;      // set by the agent: watch the receive side
    string                            tag = "ETH";  // message tag, "ETH_RX" on the receive side

    logic [57:0] scrambled_history;  // [0] is the most recent scrambled bit
    bit          in_frame;
    logic [7:0]  raw [$];            // preamble, start-of-frame delimiter and frame

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_eth_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_eth_config not set for the monitor")
    endfunction

    function logic [63:0] descramble(logic [63:0] in);
      logic [63:0] out;
      for (int i = 0; i < 64; i++) begin
        out[i] = in[i] ^ scrambled_history[38] ^ scrambled_history[57];
        scrambled_history = {scrambled_history[56:0], in[i]};
      end
      return out;
    endfunction

    task run_phase(uvm_phase phase);
      int unsigned blocks = 0;
      forever begin
        logic [63:0] data;
        logic [1:0]  hdr;
        logic        rst_n;
        logic [63:0] raw_data;
        if (rx_side) begin
          @(cfg.vif.rx_mon_cb);
          rst_n    = cfg.vif.rx_mon_cb.rst_n;
          hdr      = cfg.vif.rx_mon_cb.rx_hdr;
          raw_data = cfg.vif.rx_mon_cb.rx_data;
        end else begin
          @(cfg.vif.mon_cb);
          rst_n    = cfg.vif.mon_cb.rst_n;
          hdr      = cfg.vif.mon_cb.tx_hdr;
          raw_data = cfg.vif.mon_cb.tx_data;
        end
        if (rst_n !== 1'b1 || $isunknown({raw_data, hdr})) begin
          blocks   = 0;
          in_frame = 1'b0;
          continue;
        end
        data = descramble(raw_data);
        if (blocks++ == 0) continue;  // the descrambler is filling
        block(hdr, data);
      end
    endtask

    function void block(logic [1:0] hdr, logic [63:0] data);
      logic [7:0] block_type = data[7:0];
      int         n;
      if (hdr == SyncData) begin
        if (in_frame) for (int i = 0; i < 8; i++) raw.push_back(data[8*i +: 8]);
        return;
      end
      if (hdr != SyncCtrl) begin
        `uvm_error(tag, $sformatf("bad sync header %b", hdr))
        return;
      end
      if (block_type == BlockStart0 || block_type == BlockStart4) begin
        if (in_frame) `uvm_error(tag, "start of a frame inside a frame")
        raw.delete();
        in_frame = 1'b1;
        for (int i = (block_type == BlockStart0) ? 1 : 5; i < 8; i++) raw.push_back(data[8*i +: 8]);
        return;
      end
      n = term_bytes(block_type);
      if (n >= 0 && in_frame) begin
        for (int i = 1; i <= n; i++) raw.push_back(data[8*i +: 8]);
        in_frame = 1'b0;
        frame_done();
      end else if (block_type == BlockIdle) begin
        idle_blocks++;
      end
    endfunction

    // raw holds 6 preamble bytes 0x55, the delimiter 0xD5, then the frame.
    function void frame_done();
      adr_eth_item item = adr_eth_item::type_id::create("item");
      logic [31:0] fcs;
      int unsigned len;
      if (raw.size() < 7 + 64) begin
        `uvm_error(tag, $sformatf("frame too short: %0d bytes with preamble", raw.size()))
        return;
      end
      for (int i = 0; i < 6; i++)
        if (raw[i] !== 8'h55) `uvm_error(tag, $sformatf("preamble byte %0d is %2h", i, raw[i]))
      if (raw[6] !== 8'hD5) `uvm_error(tag, $sformatf("start-of-frame delimiter is %2h", raw[6]))
      for (int i = 7; i < raw.size(); i++) item.bytes.push_back(raw[i]);
      len = item.bytes.size();
      fcs = crc32(item.bytes, len - 4);
      item.fcs_ok = {item.bytes[len-1], item.bytes[len-2], item.bytes[len-3], item.bytes[len-4]} === fcs;
      frames++;
      if (!item.fcs_ok) begin
        bad_frames++;
        `uvm_error(tag, {"bad frame check sequence: ", item.convert2string()})
      end
      `uvm_info(tag, item.convert2string(), UVM_HIGH)
      ap.write(item);
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info(tag, $sformatf("%0d frames %s (%0d with a bad FCS), %0d idle blocks", frames,
                                 rx_side ? "into the chip" : "from the chip",
                                 bad_frames, idle_blocks), UVM_LOW)
    endfunction
  endclass

  class adr_eth_driver extends uvm_driver #(adr_eth_item);
    `uvm_component_utils(adr_eth_driver)

    adr_eth_config cfg;
    int unsigned   frames;
    logic [57:0]   scrambled_history;  // [0] is the most recent scrambled bit
    logic [65:0]   blocks [$];         // {sync header, 64 data bits}, not yet scrambled

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_eth_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_eth_config not set for the driver")
    endfunction

    // The inverse of the monitor's descrambler.
    function logic [63:0] scramble(logic [63:0] in);
      logic [63:0] out;
      for (int i = 0; i < 64; i++) begin
        out[i] = in[i] ^ scrambled_history[38] ^ scrambled_history[57];
        scrambled_history = {scrambled_history[56:0], out[i]};
      end
      return out;
    endfunction

    // One frame as 64b/66b blocks, followed by one idle block.
    function void encode(adr_eth_item item);
      localparam logic [7:0] TermType [8] = '{8'h87, 8'h99, 8'haa, 8'hb4, 8'hcc, 8'hd2, 8'he1, 8'hff};
      logic [7:0]  frame [$] = item.bytes;
      logic [63:0] data;
      int unsigned pos = 0;
      if (item.append_fcs) begin
        logic [31:0] fcs;
        while (frame.size() < 60) frame.push_back(8'h00);
        fcs = crc32(frame, frame.size());
        for (int i = 0; i < 4; i++) frame.push_back(fcs[8*i +: 8]);
      end
      blocks.push_back({SyncCtrl, 8'hD5, {6{8'h55}}, BlockStart0});
      while (frame.size() - pos >= 8) begin
        for (int i = 0; i < 8; i++) data[8*i +: 8] = frame[pos + i];
        blocks.push_back({SyncData, data});
        pos += 8;
      end
      data = '0;
      data[7:0] = TermType[frame.size() - pos];
      for (int i = 0; pos + i < frame.size(); i++) data[8*(i+1) +: 8] = frame[pos + i];
      blocks.push_back({SyncCtrl, data});
      blocks.push_back({SyncCtrl, 56'h0, BlockIdle});
    endfunction

    task run_phase(uvm_phase phase);
      scrambled_history = '0;
      forever begin
        logic [65:0] blk;
        @(cfg.vif.drv_cb);
        if (blocks.size() == 0) begin
          adr_eth_item item;
          seq_item_port.try_next_item(item);
          if (item != null) begin
            encode(item);
            frames++;
            seq_item_port.item_done();
          end
        end
        blk = (blocks.size() != 0) ? blocks.pop_front() : {SyncCtrl, 56'h0, BlockIdle};
        cfg.vif.drv_cb.drv_hdr  <= blk[65:64];
        cfg.vif.drv_cb.drv_data <= scramble(blk[63:0]);
      end
    endtask

    function void report_phase(uvm_phase phase);
      `uvm_info("ETH", $sformatf("%0d frames sent to the chip", frames), UVM_LOW)
    endfunction
  endclass

  // Sends one frame: bytes from the destination address to the end of the payload.
  class adr_eth_frame_seq extends uvm_sequence #(adr_eth_item);
    `uvm_object_utils(adr_eth_frame_seq)

    logic [7:0] bytes [$];

    function new(string name = "adr_eth_frame_seq");
      super.new(name);
    endfunction

    task body();
      req = adr_eth_item::type_id::create("req");
      start_item(req);
      req.bytes = bytes;
      finish_item(req);
    endtask
  endclass

  // Passive: transmit monitor only. Active (cfg.is_active): also a sequencer and a driver on the
  // receive side.
  class adr_eth_agent extends uvm_agent;
    `uvm_component_utils(adr_eth_agent)

    adr_eth_config                 cfg;
    adr_eth_monitor                mon;     // transmit side, from the chip
    adr_eth_monitor                rx_mon;  // receive side, into the chip (active only)
    uvm_sequencer #(adr_eth_item)  sqr;
    adr_eth_driver                 drv;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_eth_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_eth_config not set for the agent")
      uvm_config_db #(adr_eth_config)::set(this, "mon", "cfg", cfg);
      mon = adr_eth_monitor::type_id::create("mon", this);
      if (cfg.is_active == UVM_ACTIVE) begin
        uvm_config_db #(adr_eth_config)::set(this, "drv", "cfg", cfg);
        uvm_config_db #(adr_eth_config)::set(this, "rx_mon", "cfg", cfg);
        rx_mon         = adr_eth_monitor::type_id::create("rx_mon", this);
        rx_mon.rx_side = 1'b1;
        rx_mon.tag     = "ETH_RX";
        sqr = uvm_sequencer #(adr_eth_item)::type_id::create("sqr", this);
        drv = adr_eth_driver::type_id::create("drv", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if (cfg.is_active == UVM_ACTIVE) drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

endpackage
