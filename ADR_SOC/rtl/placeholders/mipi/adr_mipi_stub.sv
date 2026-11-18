/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_mipi_stub.sv
 Module/class Name             : adr_mipi_stub
 Author                        : Vijay Bogati
 Description                   : Placeholder for MIPI C-PHY and D-PHY; not built and not tested
***************************************************************/

// ADR SoC - placeholder for MIPI C-PHY and D-PHY. Not part of the design, not built by default, and not tested.
// It only fixes a register port for later work. Registers: 0x00 reads an ID, all else reads 0.

module adr_mipi_stub (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [11:0] paddr_i,
  input  logic [31:0] pwdata_i,
  output logic [31:0] prdata_o,
  output logic        pready_o,
  output logic        pslverr_o,
  output logic        irq_o
);

  assign prdata_o  = (paddr_i == 12'h000) ? 32'h4D495049 : 32'h0;
  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;
  assign irq_o     = 1'b0;

  logic unused;
  assign unused = &{1'b0, clk_i, rst_ni, psel_i, penable_i, pwrite_i, pwdata_i};

endmodule
