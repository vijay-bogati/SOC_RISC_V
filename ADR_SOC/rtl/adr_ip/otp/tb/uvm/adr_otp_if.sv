/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_otp_if.sv
 Module/class Name             : adr_otp_if
 Author                        : Vijay Bogati
 Description                   : UVM OTP agent interface: the OTP controller's macro port
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). The Verilator bench does not use it.
// req, we, addr and wdata come from the OTP controller; rdata and done go back to it and are
// written by the slave driver through drv_cb, so they change just after a rising edge of clk,
// like register outputs. Like the macro model, they hold no value until the first clock.

interface adr_otp_if (
  input logic clk,
  input logic rst_n
);

  logic        req;
  logic        we;
  logic [4:0]  addr;
  logic [31:0] wdata;
  logic [31:0] rdata;
  logic        done;

  // Values as they were just before each rising edge, as clocked logic sees them.
  clocking mon_cb @(posedge clk);
    input rst_n, req, we, addr, wdata, rdata, done;
  endclocking

  clocking drv_cb @(posedge clk);
    input  req, we, addr, wdata;
    output rdata, done;
  endclocking

endinterface
