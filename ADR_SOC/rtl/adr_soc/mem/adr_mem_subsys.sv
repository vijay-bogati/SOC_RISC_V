/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_mem_subsys.sv
 Module/class Name             : adr_mem_subsys
 Author                        : Vijay Bogati
 Description                   : Memory subsystem: every memory on the crossbar
***************************************************************/

//   boot ROM (adr_rom), SRAM (adr_sram) and DDR4 (adr_ddr), each on its own crossbar target
//   port, with the DDR4 controller's registers on an APB slot.
//
// Each memory holds its own adapter for RISC-V atomics: ROM rejects them, SRAM and DDR4 carry
// them out.

module adr_mem_subsys
  import adr_soc_pkg::*;
#(
  parameter int unsigned IdWidth   = 1,
  parameter int unsigned UserWidth = 1,
  parameter type         req_t     = logic,
  parameter type         resp_t    = logic
) (
  input  logic      clk_i,
  input  logic      rst_ni,       // system reset
  // DDR4 drain before a warm reset (adr_rst_gen)
  input  logic      ddr_drain_i,
  output logic      ddr_idle_o,
  // Crossbar target ports
  input  req_t      rom_req_i,
  output resp_t     rom_resp_o,
  input  req_t      sram_req_i,
  output resp_t     sram_resp_o,
  input  req_t      ddr_req_i,
  output resp_t     ddr_resp_o,
  // DDR4 controller registers
  input  apb_req_t  ddr_apb_req_i,
  output apb_resp_t ddr_apb_resp_o
);

  adr_rom #(
    .AddrWidth ( AddrWidth             ),
    .DataWidth ( DataWidth             ),
    .IdWidth   ( IdWidth               ),
    .UserWidth ( UserWidth             ),
    .NumWords  ( int'(RomSize / 64'd8) ),
    .req_t     ( req_t                 ),
    .resp_t    ( resp_t                )
  ) i_rom (
    .clk_i,
    .rst_ni,
    .slv_req_i  ( rom_req_i  ),
    .slv_resp_o ( rom_resp_o )
  );

  adr_sram #(
    .AddrWidth ( AddrWidth              ),
    .DataWidth ( DataWidth              ),
    .IdWidth   ( IdWidth                ),
    .UserWidth ( UserWidth              ),
    .NumWords  ( int'(SramSize / 64'd8) ),
    .req_t     ( req_t                  ),
    .resp_t    ( resp_t                 )
  ) i_sram (
    .clk_i,
    .rst_ni,
    .slv_req_i  ( sram_req_i  ),
    .slv_resp_o ( sram_resp_o )
  );

  adr_ddr #(
    .AddrWidth ( AddrWidth ),
    .DataWidth ( DataWidth ),
    .IdWidth   ( IdWidth   ),
    .UserWidth ( UserWidth ),
    .req_t     ( req_t     ),
    .resp_t    ( resp_t    )
  ) i_ddr (
    .clk_i,
    .rst_ni,
    .drain_i    ( ddr_drain_i                   ),
    .idle_o     ( ddr_idle_o                    ),
    .slv_req_i  ( ddr_req_i                     ),
    .slv_resp_o ( ddr_resp_o                    ),
    .psel_i     ( ddr_apb_req_i.psel            ),
    .penable_i  ( ddr_apb_req_i.penable         ),
    .pwrite_i   ( ddr_apb_req_i.pwrite          ),
    .paddr_i    ( ddr_apb_req_i.paddr[15:0]     ),
    .pwdata_i   ( ddr_apb_req_i.pwdata          ),
    .prdata_o   ( ddr_apb_resp_o.prdata         ),
    .pready_o   ( ddr_apb_resp_o.pready         ),
    .pslverr_o  ( ddr_apb_resp_o.pslverr        )
  );

endmodule
