/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_core_complex.sv
 Module/class Name             : adr_core_complex
 Author                        : Vijay Bogati
 Description                   : Core complex: the CPU and its two interrupt controllers
***************************************************************/

//   cva6  RV64GC CPU, one AXI4 initiator port
//   clint machine timer and software interrupts, on a crossbar target port, behind an
//         axi_atop_filter: the CLINT ignores AXI atomics, so they get an error response
//         (with the read beat an atomic needs) instead of being taken as plain writes
//   plic  external interrupts from every block, on an APB slot
//
// The interrupt sources arrive as one vector, already mapped to PLIC source numbers.

`include "register_interface/typedef.svh"
`include "register_interface/assign.svh"

module adr_core_complex
  import adr_soc_pkg::*;
#(
  parameter config_pkg::cva6_cfg_t CpuCfg = config_pkg::cva6_cfg_empty,
  parameter int unsigned TgtIdWidth = 1,
  parameter type         init_aw_chan_t = logic,
  parameter type         init_w_chan_t  = logic,
  parameter type         init_b_chan_t  = logic,
  parameter type         init_ar_chan_t = logic,
  parameter type         init_r_chan_t  = logic,
  parameter type         init_req_t     = logic,
  parameter type         init_resp_t    = logic,
  parameter type         tgt_req_t      = logic,
  parameter type         tgt_resp_t     = logic
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,          // system reset
  input  logic                     rtc_i,           // CLINT time base
  input  logic                     debug_req_i,     // from the debug module
  // CPU initiator port
  output init_req_t                cpu_req_o,
  input  init_resp_t               cpu_resp_i,
  // CLINT target port
  input  tgt_req_t                 clint_req_i,
  output tgt_resp_t                clint_resp_o,
  // PLIC APB slot and interrupt sources
  input  apb_req_t                 plic_apb_req_i,
  output apb_resp_t                plic_apb_resp_o,
  input  logic [NumIrqSources-1:0] irq_sources_i
);

  logic                     timer_irq;
  logic                     soft_irq;
  logic [NumIrqTargets-1:0] irq_targets;

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // CPU
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  cva6 #(
    .CVA6Cfg       ( CpuCfg         ),
    .axi_ar_chan_t ( init_ar_chan_t ),
    .axi_aw_chan_t ( init_aw_chan_t ),
    .axi_w_chan_t  ( init_w_chan_t  ),
    .b_chan_t      ( init_b_chan_t  ),
    .r_chan_t      ( init_r_chan_t  ),
    .noc_req_t     ( init_req_t     ),
    .noc_resp_t    ( init_resp_t    )
  ) i_cpu (
    .clk_i,
    .rst_ni,
    .boot_addr_i   ( BootAddr    ),
    .hart_id_i     ( '0          ),
    .irq_i         ( irq_targets ),
    .ipi_i         ( soft_irq    ),
    .time_irq_i    ( timer_irq   ),
    .debug_req_i,
    .rvfi_probes_o (             ),
    .cvxif_req_o   (             ),
    .cvxif_resp_i  ( '0          ),
    .noc_req_o     ( cpu_req_o   ),
    .noc_resp_i    ( cpu_resp_i  )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // CLINT: machine timer and software interrupts
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Its AXI-Lite front end does not look at aw.atop: an atomic would be a plain write of the
  // operand, answered without the R beat an AtomicLoad, Swap or Compare waits for. The filter
  // answers atomics itself with SLVERR and passes everything else unchanged.
  tgt_req_t  clint_req;
  tgt_resp_t clint_resp;

  axi_atop_filter #(
    .AxiIdWidth      ( TgtIdWidth ),
    .AxiMaxWriteTxns ( 1          ),
    .req_t           ( tgt_req_t  ),
    .resp_t          ( tgt_resp_t )
  ) i_clint_atop_filter (
    .clk_i,
    .rst_ni,
    .slv_req_i  ( clint_req_i  ),
    .slv_resp_o ( clint_resp_o ),
    .mst_req_o  ( clint_req    ),
    .mst_resp_i ( clint_resp   )
  );

  clint #(
    .CVA6Cfg        ( CpuCfg     ),
    .AXI_ADDR_WIDTH ( AddrWidth  ),
    .AXI_DATA_WIDTH ( DataWidth  ),
    .AXI_ID_WIDTH   ( TgtIdWidth ),
    .NR_CORES       ( 1          ),
    .axi_req_t      ( tgt_req_t  ),
    .axi_resp_t     ( tgt_resp_t )
  ) i_clint (
    .clk_i,
    .rst_ni,
    .testmode_i  ( 1'b0         ),
    .axi_req_i   ( clint_req    ),
    .axi_resp_o  ( clint_resp   ),
    .rtc_i,
    .timer_irq_o ( timer_irq    ),
    .ipi_o       ( soft_irq     )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // PLIC: word accesses only, because the register bus has no byte strobes here.
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  REG_BUS #(
    .ADDR_WIDTH ( 32 ),
    .DATA_WIDTH ( 32 )
  ) plic_bus (clk_i);

  apb_to_reg i_plic_apb_to_reg (
    .clk_i,
    .rst_ni,
    .penable_i ( plic_apb_req_i.penable     ),
    .pwrite_i  ( plic_apb_req_i.pwrite      ),
    .paddr_i   ( plic_apb_req_i.paddr[31:0] ),
    .psel_i    ( plic_apb_req_i.psel        ),
    .pwdata_i  ( plic_apb_req_i.pwdata      ),
    .prdata_o  ( plic_apb_resp_o.prdata     ),
    .pready_o  ( plic_apb_resp_o.pready     ),
    .pslverr_o ( plic_apb_resp_o.pslverr    ),
    .reg_o     ( plic_bus                   )
  );

  `REG_BUS_TYPEDEF_ALL(plic, logic [31:0], logic [31:0], logic [3:0])
  plic_req_t plic_req;
  plic_rsp_t plic_rsp;
  `REG_BUS_ASSIGN_TO_REQ(plic_req, plic_bus)
  `REG_BUS_ASSIGN_FROM_RSP(plic_bus, plic_rsp)

  plic_top #(
    .N_SOURCE  ( NumIrqSources  ),
    .N_TARGET  ( NumIrqTargets  ),
    .MAX_PRIO  ( MaxIrqPriority ),
    .reg_req_t ( plic_req_t     ),
    .reg_rsp_t ( plic_rsp_t     )
  ) i_plic (
    .clk_i,
    .rst_ni,
    .req_i         ( plic_req        ),
    .resp_o        ( plic_rsp        ),
    .le_i          ( irq_edge_mask() ),
    .irq_sources_i ( irq_sources_i   ),
    .eip_targets_o ( irq_targets     )
  );

endmodule
