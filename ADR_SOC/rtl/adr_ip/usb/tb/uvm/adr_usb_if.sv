/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_usb_if.sv
 Module/class Name             : adr_usb_if
 Author                        : Vijay Bogati
 Description                   : UVM USB agent interface: full-speed bus lines, the device's drivers and its pull-up
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). The Verilator bench does not use it.
// clk is the USB clock (four clocks per bit). dp and dn are the bus levels, which the bench works
// out from the device, the host and the pull-up. The dev_* signals are the device's own outputs,
// the host_* signals the USB agent's host driver (adr_usb_host_driver), which changes them just
// after falling edges of clk, so they can never race the device's sampling.

interface adr_usb_if (
  input logic clk,
  input logic rst_n
);

  logic dp, dn;                   // bus
  logic dev_dp, dev_dn;           // device outputs
  logic dev_dp_en, dev_dn_en;     // device output enables
  logic dev_pullup;               // device pull-up on D+ (connected)
  logic host_drive = 1'b0;        // the host driver drives the bus
  logic host_dp    = 1'b1;        // host levels while host_drive is high
  logic host_dn    = 1'b0;

  clocking mon_cb @(posedge clk);
    input rst_n, dp, dn, dev_dp_en, dev_pullup;
  endclocking

endinterface
