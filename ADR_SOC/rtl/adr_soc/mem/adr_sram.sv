/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_sram.sv
 Module/class Name             : adr_sram
 Author                        : Vijay Bogati
 Description                   : On-chip SRAM: an AXI4 target memory
***************************************************************/

// RISC-V atomics (AMOs, and LR/SC) arrive as AXI atomic transactions. The memory can't perform
// them, so an atomics unit in front of it carries them out as plain reads and writes.

`include "axi/assign.svh"

module adr_sram #(
  parameter int unsigned AddrWidth = 64,
  parameter int unsigned DataWidth = 64,
  parameter int unsigned IdWidth   = 1,
  parameter int unsigned UserWidth = 1,
  parameter int unsigned NumWords  = 1024,
  parameter type         req_t     = logic,
  parameter type         resp_t    = logic
) (
  input  logic  clk_i,
  input  logic  rst_ni,
  input  req_t  slv_req_i,
  output resp_t slv_resp_o
);

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AddrWidth ),
    .AXI_DATA_WIDTH ( DataWidth ),
    .AXI_ID_WIDTH   ( IdWidth   ),
    .AXI_USER_WIDTH ( UserWidth )
  ) bus_in (), bus_mem ();

  `AXI_ASSIGN_FROM_REQ(bus_in, slv_req_i)
  `AXI_ASSIGN_TO_RESP(slv_resp_o, bus_in)

  axi_riscv_atomics_wrap #(
    .AXI_ADDR_WIDTH     ( AddrWidth ),
    .AXI_DATA_WIDTH     ( DataWidth ),
    .AXI_ID_WIDTH       ( IdWidth   ),
    .AXI_USER_WIDTH     ( UserWidth ),
    .AXI_MAX_WRITE_TXNS ( 1         ),
    .RISCV_WORD_WIDTH   ( 64        )
  ) i_atomics (
    .clk_i,
    .rst_ni,
    .slv ( bus_in  ),
    .mst ( bus_mem )
  );

  adr_axi_mem #(
    .IdWidth   ( IdWidth   ),
    .UserWidth ( UserWidth ),
    .NumWords  ( NumWords  ),
    .ReadOnly  ( 1'b0      ),
    .ImageArg  ( "sram"    )
  ) i_mem (
    .clk_i,
    .rst_ni,
    .slv ( bus_mem )
  );

endmodule
