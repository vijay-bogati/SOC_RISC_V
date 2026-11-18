/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_usb_prims.sv
 Module/class Name             : prim_flop, prim_flop_2sync, prim_buf, prim_clock_mux2, prim_ram_1p
 Author                        : Vijay Bogati
 Description                   : Primitives the USB device needs, mapped to OpenTitan's generic versions
***************************************************************/

// ADR SoC - primitives the USB device needs, mapped to OpenTitan's generic versions.
// OpenTitan normally generates these thin wrappers with its own tool. A technology library
// would replace them here.

module prim_flop #(
  parameter int               Width      = 1,
  parameter logic [Width-1:0] ResetValue = 0
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [Width-1:0] d_i,
  output logic [Width-1:0] q_o
);
  prim_generic_flop #(.Width(Width), .ResetValue(ResetValue)) u_impl (.*);
endmodule

module prim_flop_2sync #(
  parameter int               Width             = 16,
  parameter logic [Width-1:0] ResetValue        = '0,
  parameter bit               EnablePrimCdcRand = 1
) (
  input  logic             clk_i,
  input  logic             rst_ni,
  input  logic [Width-1:0] d_i,
  output logic [Width-1:0] q_o
);
  prim_generic_flop_2sync #(
    .Width(Width), .ResetValue(ResetValue), .EnablePrimCdcRand(EnablePrimCdcRand)
  ) u_impl (.*);
endmodule

module prim_buf #(
  parameter int Width = 1
) (
  input  logic [Width-1:0] in_i,
  output logic [Width-1:0] out_o
);
  prim_generic_buf #(.Width(Width)) u_impl (.*);
endmodule

module prim_clock_mux2 #(
  parameter bit NoFpgaBufG = 1'b0
) (
  input  logic clk0_i,
  input  logic clk1_i,
  input  logic sel_i,
  output logic clk_o
);
  prim_generic_clock_mux2 #(.NoFpgaBufG(NoFpgaBufG)) u_impl (.*);
endmodule

module prim_ram_1p
  import prim_ram_1p_pkg::*;
#(
  parameter int Width           = 32,
  parameter int Depth           = 128,
  parameter int DataBitsPerMask = 1,
  parameter     MemInitFile     = "",
  localparam int Aw             = $clog2(Depth)
) (
  input  logic             clk_i,
  input  logic             req_i,
  input  logic             write_i,
  input  logic [Aw-1:0]    addr_i,
  input  logic [Width-1:0] wdata_i,
  input  logic [Width-1:0] wmask_i,
  output logic [Width-1:0] rdata_o,
  input  ram_1p_cfg_t      cfg_i
);
  prim_generic_ram_1p #(
    .Width(Width), .Depth(Depth), .DataBitsPerMask(DataBitsPerMask), .MemInitFile(MemInitFile)
  ) u_impl (.*);
endmodule
