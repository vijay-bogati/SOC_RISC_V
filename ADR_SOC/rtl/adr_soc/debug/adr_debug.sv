/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_debug.sv
 Module/class Name             : adr_debug
 Author                        : Vijay Bogati
 Description                   : Debug subsystem: JTAG transport, RISC-V debug module, and its two bus ports
***************************************************************/

//   JTAG pins - dmi_jtag - debug module (dm_top) -+- target port: the CPU fetches the debug ROM
//                                                 |  and uses the scratch memory while halted
//                                                 +- initiator port: system bus access, so the
//                                                    debugger reads and writes memory without
//                                                    halting the CPU
//
// System bus access follows the RISC-V Debug specification (backported upstream fixes, see
// docs/THIRD_PARTY.md): 8, 16, 32 and 64-bit accesses, each naturally aligned. A misaligned
// address sets sberror 3 and an unsupported size sberror 4, both without a bus access. An AXI
// DECERR sets sberror 2 (bad address) and an SLVERR sberror 7 (other error).
//
// rst_ni is the power-on reset. It resets the JTAG logic and the debug module, so a debugger
// stays attached while the debug module resets the rest of the SoC through debug_reset_o. The
// two bus adapters are part of the system and use sys_rst_ni.

`include "axi/assign.svh"

module adr_debug
  import adr_soc_pkg::*;
#(
  parameter config_pkg::cva6_cfg_t CpuCfg = config_pkg::cva6_cfg_empty,
  parameter int unsigned TgtIdWidth = 1,
  parameter int unsigned UserWidth  = 1,
  parameter type         tgt_req_t  = logic,
  parameter type         tgt_resp_t = logic,
  parameter type         init_req_t  = logic,
  parameter type         init_resp_t = logic
) (
  input  logic       clk_i,
  input  logic       rst_ni,       // power-on reset
  input  logic       sys_rst_ni,   // system reset
  // JTAG debug port
  input  logic       jtag_tck_i,
  input  logic       jtag_tms_i,
  input  logic       jtag_trst_ni,
  input  logic       jtag_tdi_i,
  output logic       jtag_tdo_o,
  output logic       jtag_tdo_oe_o,
  // To the CPU and the reset generator
  output logic       debug_req_o,
  output logic       debug_reset_o, // ndmreset
  // Target port: debug ROM and scratch memory, at DebugBase
  input  tgt_req_t   slv_req_i,
  output tgt_resp_t  slv_resp_o,
  // Initiator port: system bus access
  output init_req_t  mst_req_o,
  input  init_resp_t mst_resp_i
);

  typedef logic [AddrWidth-1:0]   addr_t;
  typedef logic [DataWidth-1:0]   data_t;
  typedef logic [DataWidth/8-1:0] strb_t;

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // JTAG transport
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic          dmi_rst_n;
  dm::dmi_req_t  dmi_req;
  logic          dmi_req_valid;
  logic          dmi_req_ready;
  dm::dmi_resp_t dmi_resp;
  logic          dmi_resp_valid;
  logic          dmi_resp_ready;

  dmi_jtag #(
    .IdcodeValue ( JtagIdcode )
  ) i_dmi_jtag (
    .clk_i,
    .rst_ni,
    .testmode_i       ( 1'b0           ),
    .dmi_rst_no       ( dmi_rst_n      ),
    .dmi_req_o        ( dmi_req        ),
    .dmi_req_valid_o  ( dmi_req_valid  ),
    .dmi_req_ready_i  ( dmi_req_ready  ),
    .dmi_resp_i       ( dmi_resp       ),
    .dmi_resp_ready_o ( dmi_resp_ready ),
    .dmi_resp_valid_i ( dmi_resp_valid ),
    .tck_i            ( jtag_tck_i     ),
    .tms_i            ( jtag_tms_i     ),
    .trst_ni          ( jtag_trst_ni   ),
    .td_i             ( jtag_tdi_i     ),
    .td_o             ( jtag_tdo_o     ),
    .tdo_oe_o         ( jtag_tdo_oe_o  )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Debug module
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic        dm_slave_req;
  logic        dm_slave_we;
  addr_t       dm_slave_addr;
  strb_t       dm_slave_be;
  data_t       dm_slave_wdata;
  data_t       dm_slave_rdata;
  logic        dm_master_req;
  addr_t       dm_master_addr;
  logic        dm_master_we;
  data_t       dm_master_wdata;
  strb_t       dm_master_be;
  logic        dm_master_gnt;
  logic        dm_master_rvalid;
  logic        dm_master_err;        // DECERR: sberror 2
  logic        dm_master_other_err;  // SLVERR: sberror 7
  data_t       dm_master_rdata;

  dm_top #(
    .NrHarts         ( 1                 ),
    .BusWidth        ( DataWidth         ),
    .DmBaseAddress   ( int'(DebugBase)   ),
    .SelectableHarts ( 1'b1              )
  ) i_debug_module (
    .clk_i,
    .rst_ni,
    .testmode_i       ( 1'b0                      ),
    .ndmreset_o       ( debug_reset_o             ),
    .dmactive_o       (                           ),
    .debug_req_o      ( debug_req_o               ),
    .unavailable_i    ( 1'b0                      ),
    .hartinfo_i       ( {ariane_pkg::DebugHartInfo} ),
    .slave_req_i      ( dm_slave_req              ),
    .slave_we_i       ( dm_slave_we               ),
    .slave_addr_i     ( dm_slave_addr             ),
    .slave_be_i       ( dm_slave_be               ),
    .slave_wdata_i    ( dm_slave_wdata            ),
    .slave_rdata_o    ( dm_slave_rdata            ),
    .master_req_o     ( dm_master_req             ),
    .master_add_o     ( dm_master_addr            ),
    .master_we_o      ( dm_master_we              ),
    .master_wdata_o   ( dm_master_wdata           ),
    .master_be_o      ( dm_master_be              ),
    .master_gnt_i     ( dm_master_gnt             ),
    .master_r_valid_i ( dm_master_rvalid          ),
    .master_r_err_i   ( dm_master_err             ),
    .master_r_other_err_i ( dm_master_other_err   ),
    .master_r_rdata_i ( dm_master_rdata           ),
    .dmi_rst_ni       ( dmi_rst_n                 ),
    .dmi_req_valid_i  ( dmi_req_valid             ),
    .dmi_req_ready_o  ( dmi_req_ready             ),
    .dmi_req_i        ( dmi_req                   ),
    .dmi_resp_valid_o ( dmi_resp_valid            ),
    .dmi_resp_ready_i ( dmi_resp_ready            ),
    .dmi_resp_o       ( dmi_resp                  )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Target port: CPU fetches and loads from the debug ROM and scratch memory
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // axi2mem does not look at aw.atop, so an axi_atop_filter in front answers atomics with
  // SLVERR (and the R beat an atomic needs) instead of letting them become plain writes.
  tgt_req_t  dm_slv_req;
  tgt_resp_t dm_slv_resp;

  axi_atop_filter #(
    .AxiIdWidth      ( TgtIdWidth ),
    .AxiMaxWriteTxns ( 1          ),
    .req_t           ( tgt_req_t  ),
    .resp_t          ( tgt_resp_t )
  ) i_atop_filter (
    .clk_i,
    .rst_ni     ( sys_rst_ni  ),
    .slv_req_i  ( slv_req_i   ),
    .slv_resp_o ( slv_resp_o  ),
    .mst_req_o  ( dm_slv_req  ),
    .mst_resp_i ( dm_slv_resp )
  );

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( AddrWidth  ),
    .AXI_DATA_WIDTH ( DataWidth  ),
    .AXI_ID_WIDTH   ( TgtIdWidth ),
    .AXI_USER_WIDTH ( UserWidth  )
  ) dm_slave_bus ();

  `AXI_ASSIGN_FROM_REQ(dm_slave_bus, dm_slv_req)
  `AXI_ASSIGN_TO_RESP(dm_slv_resp, dm_slave_bus)

  axi2mem #(
    .AXI_ID_WIDTH   ( TgtIdWidth ),
    .AXI_ADDR_WIDTH ( AddrWidth  ),
    .AXI_DATA_WIDTH ( DataWidth  ),
    .AXI_USER_WIDTH ( UserWidth  )
  ) i_debug_slave (
    .clk_i,
    .rst_ni ( sys_rst_ni     ),
    .slave  ( dm_slave_bus   ),
    .req_o  ( dm_slave_req   ),
    .we_o   ( dm_slave_we    ),
    .addr_o ( dm_slave_addr  ),
    .be_o   ( dm_slave_be    ),
    .user_o (                ),
    .data_o ( dm_slave_wdata ),
    .user_i ( '0             ),
    .data_i ( dm_slave_rdata )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Initiator port: system bus access
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // AXI size from the debug module's byte enables: it enables 1, 2, 4 or all 8 bytes of the
  // naturally aligned access the debugger selected (sbaccess), on reads and on writes.
  logic [1:0] dm_master_size;
  always_comb begin
    unique case ($countones(dm_master_be))
      1:       dm_master_size = 2'd0;
      2:       dm_master_size = 2'd1;
      4:       dm_master_size = 2'd2;
      default: dm_master_size = 2'd3;
    endcase
  end

  // Bus errors for sberror. axi_adapter ends a write in the cycle of the B handshake, and a read
  // in the cycle after the last R beat, so the R response is kept for one cycle. Only one access
  // is outstanding at a time.
  axi_pkg::resp_t sba_rresp_q;
  axi_pkg::resp_t sba_resp;
  logic           sba_b_done;

  always_ff @(posedge clk_i or negedge sys_rst_ni) begin
    if (!sys_rst_ni) begin
      sba_rresp_q <= axi_pkg::RESP_OKAY;
    end else if (mst_resp_i.r_valid && mst_req_o.r_ready && mst_resp_i.r.last) begin
      sba_rresp_q <= mst_resp_i.r.resp;
    end
  end

  assign sba_b_done          = mst_resp_i.b_valid && mst_req_o.b_ready;
  assign sba_resp            = sba_b_done ? mst_resp_i.b.resp : sba_rresp_q;
  assign dm_master_err       = dm_master_rvalid && (sba_resp == axi_pkg::RESP_DECERR);
  assign dm_master_other_err = dm_master_rvalid && (sba_resp == axi_pkg::RESP_SLVERR);

  axi_adapter #(
    .CVA6Cfg    ( CpuCfg      ),
    .DATA_WIDTH ( DataWidth   ),
    .axi_req_t  ( init_req_t  ),
    .axi_rsp_t  ( init_resp_t )
  ) i_debug_master (
    .clk_i,
    .rst_ni ( sys_rst_ni ),
    .req_i                 ( dm_master_req          ),
    .type_i                ( ariane_pkg::SINGLE_REQ ),
    .amo_i                 ( ariane_pkg::AMO_NONE   ),
    .gnt_o                 ( dm_master_gnt          ),
    .addr_i                ( dm_master_addr         ),
    .we_i                  ( dm_master_we           ),
    .wdata_i               ( dm_master_wdata        ),
    .be_i                  ( dm_master_be           ),
    .size_i                ( dm_master_size         ),
    .id_i                  ( '0                     ),
    .valid_o               ( dm_master_rvalid       ),
    .rdata_o               ( dm_master_rdata        ),
    .id_o                  (                        ),
    .critical_word_o       (                        ),
    .critical_word_valid_o (                        ),
    .axi_req_o             ( mst_req_o              ),
    .axi_resp_i            ( mst_resp_i             )
  );

endmodule
