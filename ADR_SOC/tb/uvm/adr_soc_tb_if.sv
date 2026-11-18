/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_soc_tb_if.sv
 Module/class Name             : adr_soc_tb_if
 Author                        : Vijay Bogati
 Description                   : UVM SoC bench clocks, reset and time base: system, Ethernet and USB clocks, reset, RTC tick and clocks since reset
***************************************************************/

// UVM bench only (a simulator with UVM 1.2). One instance in adr_soc_uvm_top; everything else takes its clocks and
// reset from here. The values come from adr_tb_pkg, as on the Verilator bench (tb_top):
//   clk      system clock, ClkHalfPeriod
//   eth_clk  Ethernet SerDes clock, EthHalfPeriod (25G, or 10G with ADR_ETH_10G)
//   usb_clk  USB clock, UsbHalfPeriod (48 MHz, four clocks per full-speed bit)
//   rst_n    low for ResetCycles system clocks, then high
//   rtc      CLINT time base: one rising edge every 2**RtcDivBits system clocks
//   cycle    rising edges of clk since reset; the environment's time base for the "[TB] RESULT"
//            cycle count (compared with the Verilator bench) and the +max_cycles timeout

interface adr_soc_tb_if ();
  timeunit 1ns;      // time declarations come first in an interface (IEEE 1800)
  timeprecision 1ps;

  import adr_tb_pkg::*;

  logic clk = 1'b0, eth_clk = 1'b0, usb_clk = 1'b0;
  logic rst_n = 1'b0;
  always #(ClkHalfPeriod) clk = ~clk;
  always #(EthHalfPeriod) eth_clk = ~eth_clk;
  always #(UsbHalfPeriod) usb_clk = ~usb_clk;

  initial begin
    repeat (ResetCycles) @(negedge clk);
    rst_n = 1'b1;
  end

  logic [RtcDivBits-1:0] rtc_count;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) rtc_count <= '0;
    else        rtc_count <= rtc_count + 1'b1;
  end
  logic rtc;
  assign rtc = rtc_count[RtcDivBits-1];

  longint cycle;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) cycle <= 0;
    else        cycle <= cycle + 1;
  end

  // Values as they were just before each rising edge, as clocked logic sees them.
  clocking mon_cb @(posedge clk);
    input rst_n, cycle;
  endclocking

endinterface
