/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_usb_agent_pkg.sv
 Module/class Name             : adr_usb_agent_pkg, adr_usb_item, adr_usb_config, adr_usb_monitor, adr_usb_host_item, adr_usb_host_driver, adr_usb_host_base_seq, adr_usb_agent
 Author                        : Vijay Bogati
 Description                   : UVM USB agent: full-speed bus monitor, and a host driver with its sequencer and host sequences when active
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). Reusable at IP level (adr_usb) and SoC level.
// Passive: the monitor only. Active (cfg.is_active): also the host, a driver that puts
// full-speed packets on the host_* signals of adr_usb_if, and its sequencer. Sequences extend
// adr_usb_host_base_seq and build transfers from its steps: wait_connect, bus_reset, idle,
// sof, token, data, handshake and receive (the device's answer comes back in the item).
// The Verilator bench keeps its own host model, adr_tb_usb_host; the driver makes the same
// bus levels at the same clock edges, so a C test takes the same cycles on both benches.
//
// The monitor decodes full-speed packets in both directions: a packet starts when the bus goes
// from J (idle) to K, bits are taken in the middle of each bit time (cfg.clocks_per_bit USB
// clocks), NRZI-decoded (no change = 1), stuffed bits after six ones are dropped, and SE0 ends
// the packet. It checks the sync byte and the PID check bits, and reports connect and bus
// reset (SE0 for longer than cfg.reset_bits bits while connected).

package adr_usb_agent_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  class adr_usb_item extends uvm_sequence_item;
    bit         from_device;
    logic [7:0] bytes [$];  // PID first, then data and CRC; the sync byte is removed

    `uvm_object_utils_begin(adr_usb_item)
      `uvm_field_int(from_device, UVM_ALL_ON)
      `uvm_field_queue_int(bytes, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "adr_usb_item");
      super.new(name);
    endfunction

    function string pid_name();
      if (bytes.size() == 0) return "empty";
      case (bytes[0][3:0])
        4'h1: return "OUT";
        4'h9: return "IN";
        4'h5: return "SOF";
        4'hD: return "SETUP";
        4'h3: return "DATA0";
        4'hB: return "DATA1";
        4'h2: return "ACK";
        4'hA: return "NAK";
        4'hE: return "STALL";
        default: return $sformatf("PID %2h", bytes[0]);
      endcase
    endfunction

    function string convert2string();
      return $sformatf("%s %s, %0d bytes after the PID", from_device ? "device" : "host  ",
                       pid_name(), bytes.size() ? bytes.size() - 1 : 0);
    endfunction
  endclass

  class adr_usb_config extends uvm_object;
    `uvm_object_utils(adr_usb_config)

    virtual adr_usb_if     vif;
    uvm_active_passive_enum is_active      = UVM_PASSIVE;  // active: host driver and sequencer
    int unsigned            clocks_per_bit = 4;
    int unsigned            reset_bits     = 20;

    function new(string name = "adr_usb_config");
      super.new(name);
    endfunction
  endclass

  class adr_usb_monitor extends uvm_monitor;
    `uvm_component_utils(adr_usb_monitor)

    uvm_analysis_port #(adr_usb_item) ap;
    adr_usb_config                    cfg;
    int unsigned                      host_packets, device_packets, bus_resets;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      ap = new("ap", this);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_usb_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_usb_config not set for the monitor")
    endfunction

    task run_phase(uvm_phase phase);
      typedef enum { Idle, Packet } state_e;
      state_e      state = Idle;
      adr_usb_item item;
      logic        last_j = 1'b0;   // previous sample was J
      logic        level;           // NRZI level of the previous bit (1 = J)
      logic        connected = 1'b0;
      int unsigned se0_clocks = 0, wait_clocks = 0, ones = 0, bit_count = 0;
      logic [7:0]  shift;
      forever begin
        logic dp, dn, j, k, se0;
        @(cfg.vif.mon_cb);
        if (cfg.vif.mon_cb.rst_n !== 1'b1) begin
          state = Idle;
          continue;
        end
        dp  = cfg.vif.mon_cb.dp;
        dn  = cfg.vif.mon_cb.dn;
        j   = (dp === 1'b1 && dn === 1'b0);
        k   = (dp === 1'b0 && dn === 1'b1);
        se0 = (dp === 1'b0 && dn === 1'b0);

        if (cfg.vif.mon_cb.dev_pullup === 1'b1 && !connected) `uvm_info("USB", "device connected", UVM_MEDIUM)
        connected = (cfg.vif.mon_cb.dev_pullup === 1'b1);

        case (state)
          Idle: begin
            if (se0 && connected) begin
              se0_clocks++;
              if (se0_clocks == cfg.reset_bits * cfg.clocks_per_bit) begin
                bus_resets++;
                `uvm_info("USB", "bus reset", UVM_MEDIUM)
              end
            end else begin
              se0_clocks = 0;
            end
            if (k && last_j) begin                 // first sync bit: J to K is a 0
              item = adr_usb_item::type_id::create("item");
              item.from_device = (cfg.vif.mon_cb.dev_dp_en === 1'b1);
              level       = 1'b0;
              ones        = 0;
              shift       = 8'h00;                 // first bit 0
              bit_count   = 1;
              wait_clocks = cfg.clocks_per_bit + cfg.clocks_per_bit / 2;
              state       = Packet;
            end
          end
          Packet: begin
            if (--wait_clocks == 0) begin
              wait_clocks = cfg.clocks_per_bit;
              if (se0) begin
                packet_done(item, bit_count);
                state = Idle;
              end else begin
                logic now     = j;
                logic decoded = (now == level);
                level = now;
                if (ones == 6) begin
                  ones = 0;                        // stuffed bit
                end else begin
                  ones  = decoded ? ones + 1 : 0;
                  shift = {decoded, shift[7:1]};
                  if (++bit_count == 8) begin
                    item.bytes.push_back(shift);
                    bit_count = 0;
                  end
                end
              end
            end
          end
        endcase
        last_j = j;
      end
    endtask

    // bytes[0] is the sync byte (0x80); it is checked and removed.
    function void packet_done(adr_usb_item item, int unsigned left_bits);
      if (item.bytes.size() < 2) begin
        `uvm_error("USB", $sformatf("packet of %0d bytes", item.bytes.size()))
        return;
      end
      if (item.bytes[0] !== 8'h80) `uvm_error("USB", $sformatf("sync byte is %2h", item.bytes[0]))
      void'(item.bytes.pop_front());
      if (item.bytes[0][7:4] !== ~item.bytes[0][3:0])
        `uvm_error("USB", $sformatf("PID %2h fails its check bits", item.bytes[0]))
      if (item.from_device) device_packets++;
      else                  host_packets++;
      `uvm_info("USB", item.convert2string(), UVM_HIGH)
      ap.write(item);
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info("USB", $sformatf("%0d host packets, %0d device packets, %0d bus resets",
                                 host_packets, device_packets, bus_resets), UVM_LOW)
    endfunction
  endclass


  // ---------------------------------------------------------------- host side

  localparam logic [7:0] PidOut = 8'hE1, PidIn = 8'h69, PidSof = 8'hA5, PidSetup = 8'h2D;
  localparam logic [7:0] PidData0 = 8'hC3, PidData1 = 8'h4B;
  localparam logic [7:0] PidAck = 8'hD2, PidNak = 8'h5A, PidStall = 8'h1E;

  // Token CRC over the 11 bits, sent most significant bit first.
  function automatic logic [4:0] usb_crc5(logic [10:0] value);
    logic [4:0] crc = 5'h1F;
    for (int i = 0; i < 11; i++) begin
      logic feedback = value[i] ^ crc[4];
      crc = {crc[3:0], 1'b0};
      if (feedback) crc ^= 5'h05;
    end
    return ~crc;
  endfunction

  // Data CRC: start at 16'hFFFF, add each byte, invert at the end; sent most significant bit first.
  function automatic logic [15:0] usb_crc16_add(logic [15:0] crc_in, logic [7:0] value);
    logic [15:0] crc = crc_in;
    for (int i = 0; i < 8; i++) begin
      logic feedback = value[i] ^ crc[15];
      crc = {crc[14:0], 1'b0};
      if (feedback) crc ^= 16'h8005;
    end
    return crc;
  endfunction

  // One step of the host. The driver fills rx_bytes for UsbReceive.
  typedef enum {
    UsbWaitConnect,  // wait for reset to end and the device's D+ pull-up
    UsbIdle,         // bus released (J through the pull-up) for 'bits' bit times
    UsbBusReset,     // SE0 for 'bits' bit times, then the bus is released
    UsbToken,        // token packet 'pid' with the 11 bits 'token' (address and endpoint, or frame)
    UsbData,         // data packet 'pid' with 'data' and its CRC16
    UsbHandshake,    // handshake packet 'pid'
    UsbReceive       // wait up to 'timeout_clocks' for a device packet and receive it
  } adr_usb_host_op_e;

  class adr_usb_host_item extends uvm_sequence_item;
    adr_usb_host_op_e op;
    int unsigned      bits;
    logic [7:0]       pid;
    logic [10:0]      token;
    logic [7:0]       data [$];
    int unsigned      timeout_clocks = 400;
    logic [7:0]       rx_bytes [$];   // UsbReceive: sync byte, PID, data, CRC; empty if none came

    `uvm_object_utils_begin(adr_usb_host_item)
      `uvm_field_enum(adr_usb_host_op_e, op, UVM_ALL_ON)
      `uvm_field_int(bits, UVM_ALL_ON)
      `uvm_field_int(pid, UVM_ALL_ON)
      `uvm_field_int(token, UVM_ALL_ON)
      `uvm_field_queue_int(data, UVM_ALL_ON)
      `uvm_field_int(timeout_clocks, UVM_ALL_ON)
      `uvm_field_queue_int(rx_bytes, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "adr_usb_host_item");
      super.new(name);
    endfunction

    function string convert2string();
      return $sformatf("%s pid %2h token %3h, %0d data bytes, %0d bytes received", op.name(), pid,
                       token, data.size(), rx_bytes.size());
    endfunction
  endclass

  // Full-speed host on adr_usb_if. Each bit lasts cfg.clocks_per_bit USB clocks; the host changes
  // its lines just after a falling edge and samples the bus at falling edges, so it never races
  // the device, which works on rising edges. NRZI: a 0 toggles the level, a 1 keeps it; a 0 is
  // stuffed after six ones. A packet ends with two bit times of SE0 and one of J.
  class adr_usb_host_driver extends uvm_driver #(adr_usb_host_item);
    `uvm_component_utils(adr_usb_host_driver)

    adr_usb_config cfg;
    logic          level;  // NRZI level, 1 is J
    int unsigned   ones;
    int unsigned   packets_sent, packets_received;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_usb_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_usb_config not set for the host driver")
    endfunction

    task clocks(int unsigned n);
      repeat (n) @(negedge cfg.vif.clk);
    endtask

    task release_bus(int unsigned bits);
      cfg.vif.host_drive = 1'b0;
      clocks(bits * cfg.clocks_per_bit);
    endtask

    task line(logic dp, logic dn);
      cfg.vif.host_drive = 1'b1;
      cfg.vif.host_dp    = dp;
      cfg.vif.host_dn    = dn;
      clocks(cfg.clocks_per_bit);
    endtask

    task send_bit(logic b);
      if (!b) level = ~level;
      line(level, ~level);
      if (b) begin
        if (++ones == 6) begin
          ones  = 0;
          level = ~level;
          line(level, ~level);
        end
      end else begin
        ones = 0;
      end
    endtask

    task send_byte(logic [7:0] value);
      for (int i = 0; i < 8; i++) send_bit(value[i]);
    endtask

    task start_packet(logic [7:0] pid);
      level = 1'b1;
      ones  = 0;
      send_byte(8'h80);  // sync
      send_byte(pid);
    endtask

    task end_packet();
      line(1'b0, 1'b0);
      line(1'b0, 1'b0);
      line(1'b1, 1'b0);
      cfg.vif.host_drive = 1'b0;
      packets_sent++;
    endtask

    task send_token(logic [7:0] pid, logic [10:0] value);
      logic [4:0] crc = usb_crc5(value);
      start_packet(pid);
      for (int i = 0; i < 11; i++) send_bit(value[i]);
      for (int i = 4; i >= 0; i--) send_bit(crc[i]);
      end_packet();
    endtask

    task send_data(logic [7:0] pid, logic [7:0] bytes [$]);
      logic [15:0] crc = 16'hFFFF;
      start_packet(pid);
      foreach (bytes[i]) begin
        send_byte(bytes[i]);
        crc = usb_crc16_add(crc, bytes[i]);
      end
      crc = ~crc;
      for (int i = 15; i >= 0; i--) send_bit(crc[i]);
      end_packet();
    endtask

    // Waits for the device to start a packet (it drives K), then takes each bit in its middle,
    // NRZI-decodes it, drops stuffed bits, and stops at SE0. rx_bytes[0] is the sync byte.
    task receive(adr_usb_host_item item);
      int unsigned waited = 0, rx_ones = 0, bit_count = 1;  // the first sync bit is the K seen here
      logic        last = 1'b0, done;
      logic [7:0]  shift = '0;
      item.rx_bytes.delete();
      while (!(cfg.vif.dev_dp_en && !cfg.vif.dp && cfg.vif.dn) && waited <= item.timeout_clocks) begin
        clocks(1);
        waited++;
      end
      done = (waited > item.timeout_clocks);
      if (!done) clocks(cfg.clocks_per_bit / 2);  // to the middle of the bit
      while (!done) begin
        clocks(cfg.clocks_per_bit);
        if (!cfg.vif.dp && !cfg.vif.dn) begin
          done = 1'b1;
        end else begin
          logic now     = cfg.vif.dp;
          logic decoded = (now == last);
          last = now;
          if (rx_ones == 6) begin
            rx_ones = 0;
          end else begin
            rx_ones = decoded ? rx_ones + 1 : 0;
            shift   = {decoded, shift[7:1]};
            if (++bit_count == 8) begin
              bit_count = 0;
              item.rx_bytes.push_back(shift);
            end
          end
        end
      end
      while (cfg.vif.dev_dp_en) clocks(1);
      if (item.rx_bytes.size() != 0) packets_received++;
    endtask

    task run_phase(uvm_phase phase);
      cfg.vif.host_drive = 1'b0;
      cfg.vif.host_dp    = 1'b1;
      cfg.vif.host_dn    = 1'b0;
      forever begin
        seq_item_port.get_next_item(req);
        `uvm_info("USB_HOST", req.convert2string(), UVM_HIGH)
        case (req.op)
          UsbWaitConnect: begin
            wait (cfg.vif.rst_n === 1'b1);
            if (cfg.vif.dev_pullup !== 1'b1) @(posedge cfg.vif.dev_pullup);
          end
          UsbIdle:      release_bus(req.bits);
          UsbBusReset: begin
            repeat (req.bits) line(1'b0, 1'b0);
            cfg.vif.host_drive = 1'b0;
          end
          UsbToken:     send_token(req.pid, req.token);
          UsbData:      send_data(req.pid, req.data);
          UsbHandshake: begin
            start_packet(req.pid);
            end_packet();
          end
          UsbReceive:   receive(req);
        endcase
        seq_item_port.item_done();
      end
    endtask

    function void report_phase(uvm_phase phase);
      `uvm_info("USB_HOST", $sformatf("%0d packets sent, %0d received", packets_sent, packets_received), UVM_LOW)
    endfunction
  endclass

  // Host steps for sequences; a transfer is a series of these. Each returns when the bus step is
  // done, so a sequence keeps exact control of the gaps between packets.
  class adr_usb_host_base_seq extends uvm_sequence #(adr_usb_host_item);
    `uvm_object_utils(adr_usb_host_base_seq)

    function new(string name = "adr_usb_host_base_seq");
      super.new(name);
    endfunction

    protected task step(adr_usb_host_op_e op, int unsigned bits = 0, logic [7:0] pid = '0,
                        logic [10:0] token = '0);
      adr_usb_host_item item = adr_usb_host_item::type_id::create("item");
      start_item(item);
      item.op    = op;
      item.bits  = bits;
      item.pid   = pid;
      item.token = token;
      finish_item(item);
    endtask

    task wait_connect();                       step(UsbWaitConnect);                    endtask
    task idle(int unsigned bits);               step(UsbIdle, bits);                     endtask
    task bus_reset(int unsigned bits);          step(UsbBusReset, bits);                 endtask
    task handshake(logic [7:0] pid);            step(UsbHandshake, 0, pid);              endtask
    task sof(logic [10:0] frame);               step(UsbToken, 0, PidSof, frame);        endtask

    // Token to an address (7 bits) and endpoint (4 bits).
    task token(logic [7:0] pid, logic [6:0] addr, logic [3:0] endp);
      step(UsbToken, 0, pid, {endp, addr});
    endtask

    task data(logic [7:0] pid, logic [7:0] bytes [$]);
      adr_usb_host_item item = adr_usb_host_item::type_id::create("item");
      start_item(item);
      item.op   = UsbData;
      item.pid  = pid;
      item.data = bytes;
      finish_item(item);
    endtask

    // The device's next packet (sync byte first), or an empty queue if none comes in time.
    task receive(output logic [7:0] rx_bytes [$], input int unsigned timeout_clocks = 400);
      adr_usb_host_item item = adr_usb_host_item::type_id::create("item");
      start_item(item);
      item.op             = UsbReceive;
      item.timeout_clocks = timeout_clocks;
      finish_item(item);
      rx_bytes = item.rx_bytes;
    endtask

    // 1 if rx_bytes is a DATA0 or DATA1 packet carrying exactly 'expected' with a good CRC16.
    function bit data_good(logic [7:0] rx_bytes [$], logic [7:0] expected [$]);
      logic [15:0] crc = 16'hFFFF;
      int unsigned len = expected.size();
      if (rx_bytes.size() != len + 4) return 1'b0;
      if (rx_bytes[1] != PidData0 && rx_bytes[1] != PidData1) return 1'b0;
      for (int i = 0; i < len; i++) begin
        if (rx_bytes[2 + i] != expected[i]) return 1'b0;
        crc = usb_crc16_add(crc, rx_bytes[2 + i]);
      end
      crc = ~crc;
      for (int i = 0; i < 8; i++) begin
        if (rx_bytes[2 + len][i]     != crc[15 - i]) return 1'b0;
        if (rx_bytes[2 + len + 1][i] != crc[7 - i])  return 1'b0;
      end
      return 1'b1;
    endfunction
  endclass

  class adr_usb_agent extends uvm_agent;
    `uvm_component_utils(adr_usb_agent)

    adr_usb_config                     cfg;
    adr_usb_monitor                    mon;
    uvm_sequencer #(adr_usb_host_item) sqr;
    adr_usb_host_driver                drv;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_usb_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_usb_config not set for the agent")
      uvm_config_db #(adr_usb_config)::set(this, "mon", "cfg", cfg);
      mon = adr_usb_monitor::type_id::create("mon", this);
      if (cfg.is_active == UVM_ACTIVE) begin
        uvm_config_db #(adr_usb_config)::set(this, "drv", "cfg", cfg);
        sqr = uvm_sequencer #(adr_usb_host_item)::type_id::create("sqr", this);
        drv = adr_usb_host_driver::type_id::create("drv", this);
      end
    endfunction

    function void connect_phase(uvm_phase phase);
      if (cfg.is_active == UVM_ACTIVE) drv.seq_item_port.connect(sqr.seq_item_export);
    endfunction
  endclass

endpackage
