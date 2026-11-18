/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_soc_sb_pkg.sv
 Module/class Name             : adr_soc_sb_pkg
 Author                        : Vijay Bogati
 Description                   : UVM SoC scoreboards: UART, SPI/QSPI and I2C, register side (APB) against the pins
***************************************************************/

// UVM bench only (a simulator with UVM 1.2). Each scoreboard takes the APB transfers of its block's slot (from the
// fabric APB monitor) and the items of its pin monitors, keeps a small model of the block's
// registers and FIFOs, and checks that what the program wrote is what went out on the pins and
// that what came in on the pins is what the program read. Mismatches are UVM errors. Things the
// model does not cover (other line formats, odd bit lengths) are skipped with one UVM_LOW note,
// never guessed. A summary line per scoreboard is printed at the end.
//
// The scoreboards need the APB monitors, so the environment builds them only with the fabric
// monitors on (not with +no_fabric_mon). Register offsets are decoded from the low address bits
// only, as the blocks do.
//
// adr_uart_sb (UART0, UART1; obi_uart, 16550 layout)
//   THR writes (DLAB 0) against the bytes on tx, in order. A byte written while the line format
//   is not 8N1 or the divisor differs from the monitor's bit time switches the tx check off.
//   Bytes into the DUT (rx monitor, or the tx monitor when the bench loops tx to rx) against RBR
//   reads, through a model of the receive path: holding register plus 16-entry FIFO with the FIFO
//   on (new bytes dropped when full), holding register only with it off (overwritten). FCR bit 1
//   empties the FIFO but not the holding register. MCR loopback: THR bytes go to the receive
//   model and the pins are ignored. An RBR read with nothing in the model is counted, not an
//   error (software may read an empty register). Divisor writes also update the interface's bit
//   time for UART-A03/A04.
// adr_spi_sb (SPI, QSPI; apb_spi_master)
//   Each start (STATUS write with a read or write bit) is expanded into the expected transfer:
//   chip select, command and address bits from CMD/ADDR/LEN (left-aligned), dummy cycles (bytes
//   not compared), then for a write the data bits from the TX FIFO model, most significant first.
//   The monitor's item for that chip select must match: chip select, line mode, length and the
//   master's bytes. For a read, the data the slave returned is cut into 32-bit words (the last
//   one right-aligned with only its low bits compared) and checked against RXFIFO reads. Starts
//   with no or several chip selects, or lengths that are not whole bytes, are skipped.
// adr_i2c_sb (I2C; adr_i2c around verilog-i2c i2c_master)
//   Three streams, each matched in order: (1) transfers: each COMMAND that opens a transfer (start
//   bit, bus idle, or another address or direction, as the engine does) gives the expected
//   address and direction of the next monitor item; (2) bytes written to DATA against the data
//   bytes of write transfers on the bus; (3) data bytes of read transfers on the bus against DATA
//   reads with the valid bit. The engine sends the data byte even when the address is not
//   acknowledged, and reads one byte in the same case; the streams include those bytes. PRESCALE
//   writes set the interface's minimum SCL high and bus free times (I2C-A05/A06): the engine
//   holds each phase for at least PRESCALE clocks.

package adr_soc_sb_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import adr_apb_monitor_pkg::*;
  import adr_uart_agent_pkg::*;
  import adr_spi_agent_pkg::*;
  import adr_i2c_agent_pkg::*;

  `uvm_analysis_imp_decl(_sb_apb)
  `uvm_analysis_imp_decl(_sb_tx)
  `uvm_analysis_imp_decl(_sb_rx)
  `uvm_analysis_imp_decl(_sb_spi)
  `uvm_analysis_imp_decl(_sb_i2c)

  // ==========================================================================================
  // UART
  // ==========================================================================================
  class adr_uart_sb extends uvm_component;
    `uvm_component_utils(adr_uart_sb)

    localparam int unsigned RxCapacity = 17;  // holding register + 16-entry FIFO

    uvm_analysis_imp_sb_apb #(adr_apb_item, adr_uart_sb)  apb_export;
    uvm_analysis_imp_sb_tx  #(adr_uart_item, adr_uart_sb) tx_export;  // bytes on tx
    uvm_analysis_imp_sb_rx  #(adr_uart_item, adr_uart_sb) rx_export;  // bytes into the DUT

    string              tag = "UART_SB";
    int unsigned        monitor_cycles_per_bit;  // the monitors' bit time
    virtual adr_uart_if vif;                     // bit time for the interface's checks

    // Register copies (reset values of obi_uart)
    logic [7:0] lcr = 8'h00, mcr = 8'h00, dll = 8'h01, dlm = 8'h00;
    bit         fifo_en = 1'b0;

    logic [7:0] tx_q [$];
    logic [7:0] tx_dropped [$];   // bytes possibly in the shifter at a TX FIFO reset
    logic [7:0] rx_q [$];
    bit         tx_off;
    int unsigned tx_ok, tx_bad, rx_ok, rx_bad, empty_reads, rx_overruns, rx_flushed;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      apb_export = new("apb_export", this);
      tx_export  = new("tx_export", this);
      rx_export  = new("rx_export", this);
    endfunction

    function bit dlab();
      return lcr[7];
    endfunction

    function bit loopback();
      return mcr[4];
    endfunction

    function int unsigned cycles_per_bit();
      return 16 * {dlm, dll};
    endfunction

    function void update_bit_time();
      if (vif != null) vif.cycles_per_bit = cycles_per_bit();
    endfunction

    // Receive path: a byte reaches the holding register / FIFO.
    function void rx_push(logic [7:0] data);
      if (fifo_en) begin
        if (rx_q.size() < RxCapacity) rx_q.push_back(data);
        else rx_overruns++;
      end else begin
        if (rx_q.size() > 0) rx_overruns++;
        rx_q = '{data};
      end
    endfunction

    function void write_sb_apb(adr_apb_item t);
      logic [2:0] reg_no = t.addr[4:2];
      logic [7:0] data   = t.data[7:0];
      if (t.error) return;
      if (t.write) begin
        case (reg_no)
          3'd0: if (dlab()) begin
                  dll = data;
                  update_bit_time();
                end else if (loopback()) rx_push(data);
                else if (lcr[6:0] != 7'h03 || cycles_per_bit() != monitor_cycles_per_bit) begin
                  if (!tx_off)
                    `uvm_info(tag, $sformatf("THR written with LCR %h and %0d clocks per bit; the monitor decodes 8N1 at %0d: tx check off",
                                             lcr, cycles_per_bit(), monitor_cycles_per_bit), UVM_LOW)
                  tx_off = 1'b1;
                end else tx_q.push_back(data);
          3'd1: if (dlab()) begin
                  dlm = data;
                  update_bit_time();
                end
          3'd2: begin                                     // FCR
                  if (!data[0] && fifo_en && rx_q.size() > 1) begin
                    rx_flushed += rx_q.size() - 1;          // FIFO off: only the holding register stays
                    rx_q = rx_q[0:0];
                  end
                  fifo_en = data[0];
                  if (data[1] && rx_q.size() > 1) begin
                    rx_flushed += rx_q.size() - 1;
                    rx_q = rx_q[0:0];
                  end
                  if (data[2] && tx_q.size() > 0) begin     // the first may already be in the shifter
                    tx_dropped = '{tx_q[0]};
                    tx_q.delete();
                  end
                end
          3'd3: lcr = data;
          3'd4: mcr = data;
          default: ;
        endcase
      end else if (reg_no == 3'd0 && !dlab()) begin       // RBR
        if (rx_q.size() == 0) empty_reads++;
        else begin
          logic [7:0] expected = rx_q.pop_front();
          if (data === expected) rx_ok++;
          else begin
            rx_bad++;
            `uvm_error(tag, $sformatf("RBR read %h, but the byte received was %h", data, expected))
          end
        end
      end
    endfunction

    function void write_sb_tx(adr_uart_item t);
      if (tx_off || loopback()) return;
      if (tx_dropped.size() > 0 && tx_dropped[0] === t.data) begin
        tx_dropped.delete();                               // it was in the shifter at the FIFO reset
        tx_ok++;
        return;
      end
      tx_dropped.delete();
      if (tx_q.size() == 0) begin
        tx_bad++;
        `uvm_error(tag, $sformatf("byte %h on tx, but nothing was written to THR", t.data))
      end else begin
        logic [7:0] expected = tx_q.pop_front();
        if (t.data === expected) tx_ok++;
        else begin
          tx_bad++;
          `uvm_error(tag, $sformatf("byte %h on tx, but THR was written with %h", t.data, expected))
        end
      end
    endfunction

    function void write_sb_rx(adr_uart_item t);
      if (!loopback()) rx_push(t.data);                    // in MCR loopback the DUT ignores rx
    endfunction

    function void check_phase(uvm_phase phase);
      if (tx_q.size() > 0)
        `uvm_error(tag, $sformatf("%0d bytes written to THR never appeared on tx (first %h)", tx_q.size(), tx_q[0]))
    endfunction

    function void report_phase(uvm_phase phase);
      string off = "";
      if (tx_off) off = " (check switched off)";
      `uvm_info(tag, $sformatf("tx: %0d bytes matched, %0d wrong%s; rx: %0d bytes matched, %0d wrong, %0d left unread, %0d empty reads, %0d overruns, %0d flushed",
                               tx_ok, tx_bad, off, rx_ok, rx_bad,
                               rx_q.size(), empty_reads, rx_overruns, rx_flushed), UVM_LOW)
    endfunction
  endclass

  // ==========================================================================================
  // SPI and QSPI
  // ==========================================================================================
  // One expected transfer.
  class adr_spi_expect;
    int unsigned cs;
    bit          quad;
    bit          read;
    logic [7:0]  mosi [$];
    logic [7:0]  mask [$];      // bits of mosi to compare (0 for dummy and read-data bytes)
    int unsigned header_bytes;  // command, address and dummy bytes before the data
    int unsigned data_bits;
  endclass

  class adr_spi_sb extends uvm_component;
    `uvm_component_utils(adr_spi_sb)

    uvm_analysis_imp_sb_apb #(adr_apb_item, adr_spi_sb) apb_export;
    uvm_analysis_imp_sb_spi #(adr_spi_item, adr_spi_sb) spi_export;

    string tag = "SPI_SB";

    logic [31:0] cmd_reg = '0, addr_reg = '0, len_reg = '0, dummy_reg = '0;
    logic [31:0] tx_fifo [$];
    logic [31:0] rx_words [$];
    logic [31:0] rx_masks [$];
    adr_spi_expect expected [$];
    bit          rx_unknown;   // a skipped read left the RX FIFO model out of step
    int unsigned starts, skipped, xfer_ok, xfer_bad, rx_ok, rx_bad, empty_reads;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      apb_export = new("apb_export", this);
      spi_export = new("spi_export", this);
    endfunction

    function void skip(string why);
      skipped++;
      `uvm_info(tag, {"transfer not checked: ", why}, UVM_LOW)
    endfunction

    // Appends the top 'count' bits of 'value', most significant first, to the bit queue.
    static function void take_bits(ref bit bits [$], input logic [31:0] value, input int unsigned count);
      for (int i = 31; i > 31 - int'(count); i--) bits.push_back(value[i]);
    endfunction

    function void start(logic [31:0] status);
      adr_spi_expect e = new();
      bit          bits [$];
      bit          write    = status[1] | status[3];
      bit          read     = status[0] | status[2];
      logic [3:0]  cs_bits  = status[11:8];
      int unsigned cmd_len  = len_reg[5:0];
      int unsigned addr_len = len_reg[13:8];
      int unsigned data_len = len_reg[31:16];
      int unsigned dummy    = write ? dummy_reg[31:16] : dummy_reg[15:0];
      int unsigned header_bits;
      int unsigned words    = (data_len + 31) / 32;
      starts++;
      e.quad      = status[2] | status[3];
      e.read      = !write;
      e.data_bits = data_len;
      header_bits = cmd_len + addr_len + dummy * (e.quad ? 4 : 1);
      if (write && words > tx_fifo.size()) begin
        skip($sformatf("write of %0d words with %0d in the TX FIFO model", words, tx_fifo.size()));
        tx_fifo.delete();
        return;
      end
      if (write && read) begin
        skip("read and write bits both set");
        if (write) repeat (words) void'(tx_fifo.pop_front());
        return;
      end
      if ($countones(cs_bits) != 1 || cmd_len > 32 || addr_len > 32 || header_bits % 8 != 0 ||
          data_len % 8 != 0) begin
        skip($sformatf("chip selects %b, command %0d, address %0d, header %0d and data %0d bits",
                       cs_bits, cmd_len, addr_len, header_bits, data_len));
        if (write) repeat (words) void'(tx_fifo.pop_front());
        if (read) rx_unknown = 1'b1;
        return;
      end
      e.cs = 0;
      while (!cs_bits[e.cs]) e.cs++;
      take_bits(bits, cmd_reg, cmd_len);
      take_bits(bits, addr_reg, addr_len);
      for (int i = 0; i < bits.size(); i += 8) begin
        logic [7:0] b;
        for (int j = 0; j < 8; j++) b[7 - j] = bits[i + j];
        e.mosi.push_back(b);
        e.mask.push_back(8'hFF);
      end
      repeat ((header_bits - cmd_len - addr_len) / 8) begin   // dummy cycles: not compared
        e.mosi.push_back(8'h00);
        e.mask.push_back(8'h00);
      end
      e.header_bytes = header_bits / 8;
      if (write) begin
        int unsigned left = data_len;
        repeat (words) begin
          logic [31:0] word = tx_fifo.pop_front();
          int unsigned n    = (left > 32) ? 32 : left;
          for (int k = 0; k < int'(n) / 8; k++) begin
            e.mosi.push_back(word[31 - 8 * k -: 8]);
            e.mask.push_back(8'hFF);
          end
          left -= n;
        end
      end else begin
        repeat (data_len / 8) begin                            // the master's lines during a read
          e.mosi.push_back(8'h00);
          e.mask.push_back(8'h00);
        end
      end
      expected.push_back(e);
    endfunction

    function void write_sb_apb(adr_apb_item t);
      logic [3:0] reg_no = t.addr[5:2];
      if (t.error) return;
      if (t.write) begin
        case (reg_no)
          4'd0: begin
                  if (t.data[4]) begin                       // software reset
                    tx_fifo.delete();
                    rx_words.delete();
                    rx_masks.delete();
                    rx_unknown = 1'b0;
                  end
                  if (t.data[3:0] != 4'h0) start(t.data);
                end
          4'd2: cmd_reg   = t.data;
          4'd3: addr_reg  = t.data;
          4'd4: len_reg   = t.data;
          4'd5: dummy_reg = t.data;
          4'd6: tx_fifo.push_back(t.data);
          default: ;
        endcase
      end else if (reg_no == 4'd8) begin                     // RXFIFO
        if (rx_unknown) return;
        if (rx_words.size() == 0) empty_reads++;
        else begin
          logic [31:0] word = rx_words.pop_front();
          logic [31:0] mask = rx_masks.pop_front();
          if ((t.data & mask) === (word & mask)) rx_ok++;
          else begin
            rx_bad++;
            `uvm_error(tag, $sformatf("RXFIFO read %h, but the slave sent %h (mask %h)", t.data, word, mask))
          end
        end
      end
    endfunction

    function void write_sb_spi(adr_spi_item t);
      adr_spi_expect e;
      bit            ok;
      if (expected.size() == 0) begin
        xfer_bad++;
        `uvm_error(tag, {"transfer with no start command: ", t.convert2string()})
        return;
      end
      e  = expected.pop_front();
      ok = (t.cs == e.cs) && (t.quad == e.quad) && (t.mosi.size() == e.mosi.size());
      if (ok) foreach (e.mosi[i]) if ((t.mosi[i] & e.mask[i]) !== (e.mosi[i] & e.mask[i])) ok = 1'b0;
      if (ok) xfer_ok++;
      else begin
        string want = "";
        foreach (e.mosi[i]) want = {want, (e.mask[i] == 8'h00) ? " --" : $sformatf(" %2h", e.mosi[i])};
        xfer_bad++;
        `uvm_error(tag, $sformatf("transfer differs from the registers: expected chip select %0d, %s, %0d bytes:%s; got %s",
                                  e.cs, e.quad ? "quad" : "single", e.mosi.size(), want, t.convert2string()))
      end
      if (e.read && t.miso.size() >= e.header_bytes + e.data_bits / 8) begin
        int unsigned left = e.data_bits;
        int unsigned pos  = e.header_bytes;
        while (left > 0) begin
          int unsigned n    = (left > 32) ? 32 : left;
          logic [31:0] word = '0;
          for (int k = 0; k < int'(n) / 8; k++) word = {word[23:0], t.miso[pos + k]};
          rx_words.push_back(word);
          rx_masks.push_back((n == 32) ? 32'hFFFF_FFFF : ((32'd1 << n) - 1));
          pos  += n / 8;
          left -= n;
        end
      end else if (e.read) rx_unknown = 1'b1;
    endfunction

    function void check_phase(uvm_phase phase);
      if (expected.size() > 0)
        `uvm_error(tag, $sformatf("%0d started transfers never appeared on the bus (first on chip select %0d)",
                                  expected.size(), expected[0].cs))
    endfunction

    function void report_phase(uvm_phase phase);
      string note = "";
      if (rx_unknown) note = " (model out of step after a skipped read)";
      `uvm_info(tag, $sformatf("%0d starts: %0d transfers matched, %0d wrong, %0d not checked; RXFIFO: %0d words matched, %0d wrong, %0d left unread, %0d empty reads%s",
                               starts, xfer_ok, xfer_bad, skipped, rx_ok, rx_bad, rx_words.size(), empty_reads, note), UVM_LOW)
    endfunction
  endclass

  // ==========================================================================================
  // I2C
  // ==========================================================================================
  class adr_i2c_sb extends uvm_component;
    `uvm_component_utils(adr_i2c_sb)

    uvm_analysis_imp_sb_apb #(adr_apb_item, adr_i2c_sb) apb_export;
    uvm_analysis_imp_sb_i2c #(adr_i2c_item, adr_i2c_sb) i2c_export;

    string             tag = "I2C_SB";
    virtual adr_i2c_if vif;   // minimum times for I2C-A05/A06

    // Engine state as the commands leave it
    bit         bus_active;
    logic [6:0] cur_addr;
    bit         cur_read;

    logic [7:0] exp_addr [$];   // (1) transfers: address and direction
    bit         exp_read [$];
    logic [7:0] wr_regs  [$];   // (2) bytes written to DATA
    logic [7:0] wr_bus   [$];   //     write bytes seen on the bus
    logic [7:0] rd_bus   [$];   // (3) read bytes seen on the bus
    logic [7:0] rd_regs  [$];   //     valid bytes read from DATA
    int unsigned xfer_ok, xfer_bad, wr_ok, wr_bad, rd_ok, rd_bad;

    function new(string name, uvm_component parent);
      super.new(name, parent);
      apb_export = new("apb_export", this);
      i2c_export = new("i2c_export", this);
    endfunction

    function void match_writes();
      while (wr_regs.size() > 0 && wr_bus.size() > 0) begin
        logic [7:0] want = wr_regs.pop_front();
        logic [7:0] got  = wr_bus.pop_front();
        if (got === want) wr_ok++;
        else begin
          wr_bad++;
          `uvm_error(tag, $sformatf("byte %h written on the bus, but DATA was written with %h", got, want))
        end
      end
    endfunction

    function void match_reads();
      while (rd_bus.size() > 0 && rd_regs.size() > 0) begin
        logic [7:0] sent = rd_bus.pop_front();
        logic [7:0] got  = rd_regs.pop_front();
        if (got === sent) rd_ok++;
        else begin
          rd_bad++;
          `uvm_error(tag, $sformatf("DATA read %h, but the byte read on the bus was %h", got, sent))
        end
      end
    endfunction

    function void command(logic [31:0] d);
      logic [6:0] addr  = d[6:0];
      bit         start = d[8], rd = d[9], wr = d[10] | d[11], stop = d[12];
      if (rd || wr) begin
        if (start || !bus_active || addr != cur_addr || rd != cur_read) begin
          exp_addr.push_back(addr);
          exp_read.push_back(rd);
        end
        bus_active = 1'b1;
        cur_addr   = addr;
        cur_read   = rd;
      end
      if (stop) bus_active = 1'b0;
    endfunction

    function void write_sb_apb(adr_apb_item t);
      logic [2:0] reg_no = t.addr[4:2];
      if (t.error) return;
      if (t.write) begin
        case (reg_no)
          3'd1: command(t.data);
          3'd2: begin
                  wr_regs.push_back(t.data[7:0]);
                  match_writes();
                end
          3'd3: if (vif != null) begin
                  vif.min_scl_high = t.data[15:0];
                  vif.min_bus_free = t.data[15:0];
                end
          default: ;
        endcase
      end else if (reg_no == 3'd2 && t.data[8]) begin       // DATA read with a byte
        rd_regs.push_back(t.data[7:0]);
        match_reads();
      end
    endfunction

    function void write_sb_i2c(adr_i2c_item t);
      if (exp_addr.size() == 0) begin
        xfer_bad++;
        `uvm_error(tag, {"transfer with no command: ", t.convert2string()})
      end else begin
        logic [6:0] addr = exp_addr.pop_front();
        bit         rd   = exp_read.pop_front();
        if (t.addr == addr && t.read == rd) xfer_ok++;
        else begin
          xfer_bad++;
          `uvm_error(tag, $sformatf("transfer to 0x%2h (%s), but the commands asked for 0x%2h (%s)",
                                    t.addr, t.read ? "read" : "write", addr, rd ? "read" : "write"))
        end
      end
      foreach (t.data[i]) if (t.read) rd_bus.push_back(t.data[i]); else wr_bus.push_back(t.data[i]);
      match_writes();
      match_reads();
    endfunction

    function void check_phase(uvm_phase phase);
      if (exp_addr.size() > 0)
        `uvm_error(tag, $sformatf("%0d commanded transfers never appeared on the bus (first to 0x%2h)",
                                  exp_addr.size(), exp_addr[0]))
      if (wr_bus.size() > 0)
        `uvm_error(tag, $sformatf("%0d bytes written on the bus that were never written to DATA (first %h)",
                                  wr_bus.size(), wr_bus[0]))
      if (rd_regs.size() > 0)
        `uvm_error(tag, $sformatf("%0d valid DATA reads with no byte read on the bus (first %h)",
                                  rd_regs.size(), rd_regs[0]))
    endfunction

    function void report_phase(uvm_phase phase);
      `uvm_info(tag, $sformatf("transfers: %0d matched, %0d wrong; write bytes: %0d matched, %0d wrong, %0d never sent; read bytes: %0d matched, %0d wrong, %0d never read",
                               xfer_ok, xfer_bad, wr_ok, wr_bad, wr_regs.size(), rd_ok, rd_bad, rd_bus.size()), UVM_LOW)
    endfunction
  endclass

endpackage
