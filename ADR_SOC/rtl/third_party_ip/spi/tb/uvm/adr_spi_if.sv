/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_spi_if.sv
 Module/class Name             : adr_spi_if
 Author                        : Vijay Bogati
 Description                   : UVM SPI agent interface: serial clock, chip selects and four data lines each way, with pin-level assertions
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). The Verilator bench does not use it.
// A protocol interface: the agent is timed by the master's serial clock, and chip select 0
// frames each transfer. Used for SPI and QSPI, mode 0:
//   sdo    from the master (SPI: MOSI is line 0)
//   sdi    to the master (SPI: MISO is line 1); held low while chip select 0 is high
//   quad   high while the master uses all four lines
// sclk_rise samples the lines just before each rising edge of sclk, where the master samples.
//
// clk and rst_n (the system clock and reset) are used only by the assertions (ADR_ASSERTIONS_PLAN
// 5.2), which sample the pins on clk and are off during reset. A failure calls uvm_report_error
// with the plan ID, so it fails the UVM verdict.
//   SPI-A01  csn and sclk are never X or Z after reset
//   SPI-A02  at most one chip select is low at a time
//   SPI-A03  sclk changes only while a chip select is low (or on the clock it goes high)
//   SPI-A04  sclk is low (mode 0 idle) when a chip select goes low and when it goes high
//   SPI-A05  sdo is stable at each rising edge of sclk
//   SPI-A06  with single_line set (an SPI master, one line each way): sdo lines 1-3 stay 0
//   SPI-A07  quad is stable at each rising edge of sclk. (The plan's "quad changes only while no
//            chip select is low" does not hold for this master: its idle mode is quad receive,
//            and it switches to single for a one-line transfer after selecting the device.)
//   SPI-C01  a quad transfer; a chip-select change between transfers; back-to-back transfers

interface adr_spi_if (
  input logic clk,
  input logic rst_n
);

  import uvm_pkg::*;

  logic       sclk;
  logic [3:0] csn;
  logic       quad;
  logic [3:0] sdo;
  logic [3:0] sdi;
  logic [3:0] slave_out = 4'b0000;  // written by the slave driver on falling edges of sclk

  bit single_line = 1'b0;  // set by the agent for an SPI (not QSPI) master: enables SPI-A06

  assign sdi = csn[0] ? 4'b0000 : slave_out;

  clocking sclk_rise @(posedge sclk);
    input csn, quad, sdo, sdi;
  endclocking

  // ---- Assertions ----
  wire selected = (csn != 4'hF);  // a chip select is low

  a_spi_known: assert property (@(posedge clk) disable iff (rst_n !== 1'b1) !$isunknown({csn, sclk}))
    else uvm_report_error("SPI-A01", $sformatf("csn %b / sclk %b is X or Z after reset", csn, sclk));

  a_spi_one_select: assert property (@(posedge clk) disable iff (rst_n !== 1'b1) $countones(~csn) <= 1)
    else uvm_report_error("SPI-A02", $sformatf("more than one chip select low: csn %b", csn));

  a_spi_sclk_while_selected: assert property (@(posedge clk) disable iff (rst_n !== 1'b1)
                                              $changed(sclk) |-> selected || $past(selected))
    else uvm_report_error("SPI-A03", "sclk changed with no chip select low");

  a_spi_sclk_idle_at_select: assert property (@(posedge clk) disable iff (rst_n !== 1'b1)
                                              ($rose(selected) || $fell(selected)) |-> !sclk)
    else uvm_report_error("SPI-A04", "sclk is not low (mode 0 idle) when a chip select changes");

  a_spi_sdo_stable: assert property (@(posedge clk) disable iff (rst_n !== 1'b1) $rose(sclk) |-> $stable(sdo))
    else uvm_report_error("SPI-A05", $sformatf("sdo changed at a rising edge of sclk (now %b)", sdo));

  a_spi_single_line: assert property (@(posedge clk) disable iff (rst_n !== 1'b1 || !single_line)
                                      sdo[3:1] == 3'b000)
    else uvm_report_error("SPI-A06", $sformatf("SPI master drives sdo lines 1-3: %b", sdo[3:1]));

  a_spi_quad_stable: assert property (@(posedge clk) disable iff (rst_n !== 1'b1) $rose(sclk) |-> $stable(quad))
    else uvm_report_error("SPI-A07", "quad changed at a rising edge of sclk");

  // ---- Cover properties (SPI-C01) ----
  // Which chip select the last transfer used, and clocks since it ended.
  int unsigned last_cs   = 0;
  int unsigned idle_clks = 32'hFFFF_FFFF;
  bit          new_cs    = 1'b0;  // a transfer on a different chip select from the last one
  bit          quick     = 1'b0;  // a transfer starting within 16 clocks of the last one's end

  always @(posedge clk) begin
    new_cs = 1'b0;
    quick  = 1'b0;
    if (rst_n !== 1'b1) begin
      idle_clks = 32'hFFFF_FFFF;
    end else if (!$isunknown(csn)) begin
      if (csn != 4'hF) begin
        automatic int unsigned cs = 0;
        while (cs < 3 && csn[cs] !== 1'b0) cs++;
        if (idle_clks != 32'hFFFF_FFFF && idle_clks != 0) begin  // first clock of a transfer
          new_cs = (cs != last_cs);
          quick  = (idle_clks <= 16);
        end
        last_cs   = cs;
        idle_clks = 0;
      end else if (idle_clks != 32'hFFFF_FFFF) idle_clks++;
    end
  end

  c_spi_quad_transfer: cover property (@(posedge clk) disable iff (rst_n !== 1'b1) selected && $rose(sclk) && quad);
  c_spi_cs_change:     cover property (@(posedge clk) disable iff (rst_n !== 1'b1) new_cs);
  c_spi_back_to_back:  cover property (@(posedge clk) disable iff (rst_n !== 1'b1) quick);

endinterface
