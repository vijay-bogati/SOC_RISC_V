/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_i2c_if.sv
 Module/class Name             : adr_i2c_if
 Author                        : Vijay Bogati
 Description                   : UVM I2C agent interface: the bus, the master's pins and the slave's pull-downs, with pin-level assertions
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). The Verilator bench does not use it.
// A protocol interface: the agent is timed by the master's SCL, and SDA edges while SCL is high
// mark START and STOP.
//   scl, sda   bus levels after the open-drain wired-AND (the bench drives them)
//   sda_low    the slave driver's pull-down on SDA; the bench ANDs it into sda
//   scl_low    the slave driver's pull-down on SCL (clock stretching); the bench ANDs it into scl
//   mst_*      the master's own pin outputs, which the bench resolves into scl and sda
// scl_rise samples SDA just before each rising edge of SCL, where a receiver takes the bit.
//
// clk and rst_n (the system clock and reset) are used only by the assertions (ADR_ASSERTIONS_PLAN
// 5.3), which sample on clk and are off during reset. A failure calls uvm_report_error with the
// plan ID, so it fails the UVM verdict.
//   I2C-A01  scl, sda and the master's pins are never X or Z after reset
//   I2C-A02  a START or STOP (SDA changing while SCL is high) comes only between bytes: after a
//            whole number of 9-clock bytes since the last START, plus the SCL rising edge that
//            the STOP or repeated START needs. (The plan's wording, "SDA changes
//            while SCL is high only as a START or STOP", is true by definition; this is the rule
//            it is meant to enforce.)
//   I2C-A03  the master never drives SCL or SDA high: each pin is released or pulled low
//   I2C-A04  while the slave holds SCL low (scl_low), SCL is low
//   I2C-A05  every SCL high period lasts at least min_scl_high clocks
//   I2C-A06  after a STOP, the bus stays free for at least min_bus_free clocks before a START
//   I2C-C01  repeated START; NACK on the address; NACK on data; a stretch in a read; a stretch
//            after an ACK
// min_scl_high and min_bus_free are set from outside (a scoreboard that sees the master's timing
// register); 0 switches A05 or A06 off. Each check uses the smaller of the value at the start
// and at the end of the period, so a change of setting between transfers cannot fail it.

interface adr_i2c_if (
  input logic clk,
  input logic rst_n
);

  import uvm_pkg::*;

  logic scl;
  logic sda;
  logic sda_low = 1'b0;
  logic scl_low = 1'b0;
  logic mst_scl_o, mst_scl_t;     // master pins: output level and tri-state (high = released)
  logic mst_sda_o, mst_sda_t;

  int unsigned min_scl_high = 0;  // clocks; 0: I2C-A05 off
  int unsigned min_bus_free = 0;  // clocks; 0: I2C-A06 off

  clocking scl_rise @(posedge scl);
    input sda;
  endclocking

  // Values just before each system clock edge, for the procedural part of the checks.
  clocking sys_cb @(posedge clk);
    input rst_n, scl, sda, scl_low;
  endclocking

  // ---- Bus tracking for A02, A05, A06 and the cover properties ----
  logic        scl_q = 1'b1, sda_q = 1'b1, scl_low_q = 1'b0;
  bit          active      = 1'b0;   // between a START and a STOP
  bit          reading     = 1'b0;   // the address byte asked for a read
  int unsigned clocks      = 0;      // SCL rising edges since the last START
  int unsigned high_clks   = 0;      // system clocks since SCL rose
  int unsigned high_min    = 0;      // min_scl_high when SCL rose
  int unsigned free_clks   = 0;      // system clocks since the last STOP
  int unsigned free_min    = 0;      // min_bus_free at the STOP
  bit          mid_byte    = 1'b0;   // A02 failed on this clock
  bit          short_high  = 1'b0;   // A05 failed on this clock
  bit          short_free  = 1'b0;   // A06 failed on this clock
  int unsigned short_len   = 0;
  bit          rep_start   = 1'b0;   // C01 events on this clock
  bit          nack_addr   = 1'b0;
  bit          nack_data   = 1'b0;
  bit          stretch_rd  = 1'b0;
  bit          stretch_ack = 1'b0;

  function automatic int unsigned smaller(int unsigned a, int unsigned b);
    return (a < b) ? a : b;
  endfunction

  always @(sys_cb) begin
    logic s_scl, s_sda, s_low;
    s_scl = sys_cb.scl;
    s_sda = sys_cb.sda;
    s_low = sys_cb.scl_low;
    {mid_byte, short_high, short_free, rep_start, nack_addr, nack_data, stretch_rd, stretch_ack} = '0;
    if (sys_cb.rst_n !== 1'b1 || $isunknown({s_scl, s_sda})) begin
      active    = 1'b0;
      clocks    = 0;
      high_clks = 0;
      free_clks = 32'hFFFF_FFFF;
    end else begin
      // SCL high time (A05), from the rising edge to the falling edge.
      if (scl_q === 1'b0 && s_scl === 1'b1) begin
        high_clks = 0;
        high_min  = min_scl_high;
        clocks++;
        if (clocks % 9 == 0 && clocks > 0) begin  // the acknowledge bit of a byte
          if (s_sda === 1'b1) begin
            if (clocks == 9) nack_addr = 1'b1;
            else if (!reading) nack_data = 1'b1;  // in a read, the master's NACK ends it
          end
        end else if (clocks % 9 == 8) begin       // the last bit of a byte
          if (clocks == 8) reading = s_sda;       // the address byte's read/write bit
        end
      end else if (s_scl === 1'b1) begin
        if (high_clks < 32'hFFFF_FFFF) high_clks++;
      end
      if (scl_q === 1'b1 && s_scl === 1'b0) begin
        if (high_clks + 1 < smaller(high_min, min_scl_high)) begin
          short_high = 1'b1;
          short_len  = high_clks + 1;
        end
      end

      // START and STOP: SDA changes while SCL stays high (A02, A06).
      if (scl_q === 1'b1 && s_scl === 1'b1 && sda_q !== s_sda) begin
        // A STOP or repeated START follows whole bytes plus its own SCL rising edge: 9n + 1.
        if (active && clocks % 9 != 1) mid_byte = 1'b1;
        if (s_sda === 1'b0) begin                                   // START
          if (free_clks != 32'hFFFF_FFFF && free_clks + 1 < smaller(free_min, min_bus_free)) begin
            short_free = 1'b1;
            short_len  = free_clks + 1;
          end
          rep_start = active;
          active    = 1'b1;
          clocks    = 0;
          reading   = 1'b0;
          free_clks = 32'hFFFF_FFFF;
        end else begin                                              // STOP
          active    = 1'b0;
          free_clks = 0;
          free_min  = min_bus_free;
        end
      end else if (!active && free_clks != 32'hFFFF_FFFF) free_clks++;

      // Clock stretching by the slave (C01).
      if (scl_low_q !== 1'b1 && s_low === 1'b1) begin
        if (reading) stretch_rd = 1'b1;
        else if (clocks % 9 == 0 && clocks > 0) stretch_ack = 1'b1;
      end
    end
    scl_q     = s_scl;
    sda_q     = s_sda;
    scl_low_q = s_low;
  end

  // ---- Assertions ----
  a_i2c_known: assert property (@(posedge clk) disable iff (rst_n !== 1'b1)
                                !$isunknown({scl, sda, mst_scl_o, mst_scl_t, mst_sda_o, mst_sda_t}))
    else uvm_report_error("I2C-A01", "scl, sda or a master pin is X or Z after reset");

  a_i2c_start_stop_between_bytes: assert property (@(posedge clk) disable iff (rst_n !== 1'b1) !mid_byte)
    else uvm_report_error("I2C-A02", $sformatf("START or STOP inside a byte (%0d clocks after the START)", clocks));

  a_i2c_open_drain: assert property (@(posedge clk) disable iff (rst_n !== 1'b1)
                                     !(mst_scl_t === 1'b0 && mst_scl_o === 1'b1) &&
                                     !(mst_sda_t === 1'b0 && mst_sda_o === 1'b1))
    else uvm_report_error("I2C-A03", "the master drives SCL or SDA high (open drain broken)");

  a_i2c_stretch_holds_scl: assert property (@(posedge clk) disable iff (rst_n !== 1'b1) scl_low |-> !scl)
    else uvm_report_error("I2C-A04", "SCL is high while the slave holds it low");

  a_i2c_scl_high_time: assert property (@(posedge clk) disable iff (rst_n !== 1'b1) !short_high)
    else uvm_report_error("I2C-A05", $sformatf("SCL high for %0d clocks, less than %0d", short_len, min_scl_high));

  a_i2c_bus_free_time: assert property (@(posedge clk) disable iff (rst_n !== 1'b1) !short_free)
    else uvm_report_error("I2C-A06", $sformatf("START %0d clocks after a STOP, less than %0d", short_len, min_bus_free));

  // ---- Cover properties (I2C-C01) ----
  c_i2c_repeated_start:   cover property (@(posedge clk) disable iff (rst_n !== 1'b1) rep_start);
  c_i2c_nack_address:     cover property (@(posedge clk) disable iff (rst_n !== 1'b1) nack_addr);
  c_i2c_nack_data:        cover property (@(posedge clk) disable iff (rst_n !== 1'b1) nack_data);
  c_i2c_stretch_in_read:  cover property (@(posedge clk) disable iff (rst_n !== 1'b1) stretch_rd);
  c_i2c_stretch_after_ack: cover property (@(posedge clk) disable iff (rst_n !== 1'b1) stretch_ack);

endinterface
