/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_interconnect.sv
 Module/class Name             : adr_interconnect
 Author                        : Vijay Bogati
 Description                   : Interconnect: every bus bridge in the SoC
***************************************************************/

//   axi_xbar        64-bit AXI4 crossbar, 4 initiators to 7 targets, with the address map
//   axi_err_slv     default target: an address that matches no range gets a decode error
//   adr_apb_bridge  the peripheral target port, down to the APB slots of every block
//   bus observation each initiator's last address and error responses, for the bus monitor
//
// Initiator and target ports are named per block. The peripheral and error targets are served
// inside, so they have no ports.

module adr_interconnect
  import adr_soc_pkg::*;
#(
  parameter int unsigned InitIdWidth = 1,
  parameter int unsigned TgtIdWidth  = 1,
  parameter int unsigned UserWidth   = 1,
  parameter type         init_aw_chan_t = logic,
  parameter type         init_w_chan_t  = logic,
  parameter type         init_b_chan_t  = logic,
  parameter type         init_ar_chan_t = logic,
  parameter type         init_r_chan_t  = logic,
  parameter type         init_req_t     = logic,
  parameter type         init_resp_t    = logic,
  parameter type         tgt_aw_chan_t  = logic,
  parameter type         tgt_w_chan_t   = logic,
  parameter type         tgt_b_chan_t   = logic,
  parameter type         tgt_ar_chan_t  = logic,
  parameter type         tgt_r_chan_t   = logic,
  parameter type         tgt_req_t      = logic,
  parameter type         tgt_resp_t     = logic
) (
  input  logic       clk_i,
  input  logic       rst_ni,        // system reset
  // Initiator ports
  input  init_req_t  cpu_req_i,
  output init_resp_t cpu_resp_o,
  input  init_req_t  debug_req_i,
  output init_resp_t debug_resp_o,
  input  init_req_t  dma_req_i,
  output init_resp_t dma_resp_o,
  input  init_req_t  eth_req_i,
  output init_resp_t eth_resp_o,
  // Target ports
  output tgt_req_t   rom_req_o,
  input  tgt_resp_t  rom_resp_i,
  output tgt_req_t   sram_req_o,
  input  tgt_resp_t  sram_resp_i,
  output tgt_req_t   ddr_req_o,
  input  tgt_resp_t  ddr_resp_i,
  output tgt_req_t   clint_req_o,
  input  tgt_resp_t  clint_resp_i,
  output tgt_req_t   debug_req_o,
  input  tgt_resp_t  debug_resp_i,
  // APB slots, and CLK_EN for the replies of gated peripherals
  input  logic [31:0]                 clk_en_i,
  output apb_req_t  [NumApbSlots-1:0] apb_req_o,
  input  apb_resp_t [NumApbSlots-1:0] apb_resp_i,
  // Bus observation, one per initiator, for the bus error monitor
  output logic [NumInitiators-1:0]       read_error_o,
  output logic [NumInitiators-1:0]       write_error_o,
  output logic [NumInitiators-1:0][63:0] last_read_addr_o,
  output logic [NumInitiators-1:0][63:0] last_write_addr_o
);

  init_req_t  [NumInitiators-1:0] init_req;
  init_resp_t [NumInitiators-1:0] init_resp;
  tgt_req_t   [NumTargets-1:0]    tgt_req;
  tgt_resp_t  [NumTargets-1:0]    tgt_resp;

  assign init_req[InitCpu]   = cpu_req_i;
  assign init_req[InitDebug] = debug_req_i;
  assign init_req[InitDma]   = dma_req_i;
  assign init_req[InitEth]   = eth_req_i;
  assign cpu_resp_o   = init_resp[InitCpu];
  assign debug_resp_o = init_resp[InitDebug];
  assign dma_resp_o   = init_resp[InitDma];
  assign eth_resp_o   = init_resp[InitEth];

  assign rom_req_o   = tgt_req[TgtRom];
  assign sram_req_o  = tgt_req[TgtSram];
  assign ddr_req_o   = tgt_req[TgtDdr];
  assign clint_req_o = tgt_req[TgtClint];
  assign debug_req_o = tgt_req[TgtDebug];
  assign tgt_resp[TgtRom]   = rom_resp_i;
  assign tgt_resp[TgtSram]  = sram_resp_i;
  assign tgt_resp[TgtDdr]   = ddr_resp_i;
  assign tgt_resp[TgtClint] = clint_resp_i;
  assign tgt_resp[TgtDebug] = debug_resp_i;

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Crossbar
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  localparam axi_pkg::xbar_cfg_t XbarCfg = '{
    NoSlvPorts:         unsigned'(NumInitiators),
    NoMstPorts:         unsigned'(NumTargets),
    MaxMstTrans:        unsigned'(8),
    MaxSlvTrans:        unsigned'(8),
    FallThrough:        1'b0,
    LatencyMode:        axi_pkg::CUT_ALL_AX,
    AxiIdWidthSlvPorts: unsigned'(InitIdWidth),
    AxiIdUsedSlvPorts:  unsigned'(InitIdWidth),
    UniqueIds:          1'b0,
    AxiAddrWidth:       unsigned'(AddrWidth),
    AxiDataWidth:       unsigned'(DataWidth),
    NoAddrRules:        unsigned'(NumRules)
  };

  axi_pkg::xbar_rule_64_t [NumRules-1:0] addr_map;
  assign addr_map[0] = '{ idx: TgtRom,    start_addr: RomBase,    end_addr: RomBase + RomSize };
  assign addr_map[1] = '{ idx: TgtSram,   start_addr: SramBase,   end_addr: SramBase + SramSize };
  assign addr_map[2] = '{ idx: TgtPeriph, start_addr: PeriphBase, end_addr: PeriphBase + PeriphSize };
  assign addr_map[3] = '{ idx: TgtPeriph, start_addr: PlicBase,   end_addr: PlicBase + PlicSize };
  assign addr_map[4] = '{ idx: TgtClint,  start_addr: ClintBase,  end_addr: ClintBase + ClintSize };
  assign addr_map[5] = '{ idx: TgtDebug,  start_addr: DebugBase,  end_addr: DebugBase + DebugSize };
  assign addr_map[6] = '{ idx: TgtSram,   start_addr: SramBase + UncachedAliasOffset,
                          end_addr: SramBase + UncachedAliasOffset + SramSize };
  assign addr_map[7] = '{ idx: TgtDdr,    start_addr: DdrBase,    end_addr: DdrBase + DdrSize };
  assign addr_map[8] = '{ idx: TgtDdr,    start_addr: DdrBase + UncachedAliasOffset,
                          end_addr: DdrBase + UncachedAliasOffset + DdrSize };

  localparam int unsigned TgtIdxWidth = $clog2(NumTargets);
  logic [NumInitiators-1:0][TgtIdxWidth-1:0] default_target;
  assign default_target = {NumInitiators{TgtIdxWidth'(TgtError)}};

  axi_xbar #(
    .Cfg           ( XbarCfg        ),
    .ATOPs         ( 1'b1           ),
    .slv_aw_chan_t ( init_aw_chan_t ),
    .mst_aw_chan_t ( tgt_aw_chan_t  ),
    .w_chan_t      ( init_w_chan_t  ),
    .slv_b_chan_t  ( init_b_chan_t  ),
    .mst_b_chan_t  ( tgt_b_chan_t   ),
    .slv_ar_chan_t ( init_ar_chan_t ),
    .mst_ar_chan_t ( tgt_ar_chan_t  ),
    .slv_r_chan_t  ( init_r_chan_t  ),
    .mst_r_chan_t  ( tgt_r_chan_t   ),
    .slv_req_t     ( init_req_t     ),
    .slv_resp_t    ( init_resp_t    ),
    .mst_req_t     ( tgt_req_t      ),
    .mst_resp_t    ( tgt_resp_t     ),
    .rule_t        ( axi_pkg::xbar_rule_64_t )
  ) i_xbar (
    .clk_i,
    .rst_ni,
    .test_i                ( 1'b0      ),
    .slv_ports_req_i       ( init_req  ),
    .slv_ports_resp_o      ( init_resp ),
    .mst_ports_req_o       ( tgt_req   ),
    .mst_ports_resp_i      ( tgt_resp  ),
    .addr_map_i            ( addr_map  ),
    .en_default_mst_port_i ( '1        ),
    .default_mst_port_i    ( default_target )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Unmapped addresses: decode error
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  axi_err_slv #(
    .AxiIdWidth ( TgtIdWidth           ),
    .req_t      ( tgt_req_t            ),
    .resp_t     ( tgt_resp_t           ),
    .Resp       ( axi_pkg::RESP_DECERR ),
    .ATOPs      ( 1'b1                 ),
    .MaxTrans   ( 4                    )
  ) i_error_target (
    .clk_i,
    .rst_ni,
    .test_i     ( 1'b0               ),
    .slv_req_i  ( tgt_req[TgtError]  ),
    .slv_resp_o ( tgt_resp[TgtError] )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // APB bridge, on the peripheral target port
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  adr_apb_bridge #(
    .IdWidth       ( TgtIdWidth    ),
    .UserWidth     ( UserWidth     ),
    .slv_aw_chan_t ( tgt_aw_chan_t ),
    .slv_w_chan_t  ( tgt_w_chan_t  ),
    .slv_b_chan_t  ( tgt_b_chan_t  ),
    .slv_ar_chan_t ( tgt_ar_chan_t ),
    .slv_r_chan_t  ( tgt_r_chan_t  ),
    .slv_req_t     ( tgt_req_t     ),
    .slv_resp_t    ( tgt_resp_t    )
  ) i_apb_bridge (
    .clk_i,
    .rst_ni,
    .slv_req_i  ( tgt_req[TgtPeriph]  ),
    .slv_resp_o ( tgt_resp[TgtPeriph] ),
    .clk_en_i,
    .apb_req_o,
    .apb_resp_i
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Bus observation: each initiator's last accepted address and its error responses
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  for (genvar i = 0; i < int'(NumInitiators); i++) begin : gen_bus_watch
    assign read_error_o[i]  = init_resp[i].r_valid && init_req[i].r_ready && init_resp[i].r.resp[1];
    assign write_error_o[i] = init_resp[i].b_valid && init_req[i].b_ready && init_resp[i].b.resp[1];
    always_ff @(posedge clk_i or negedge rst_ni) begin
      if (!rst_ni) begin
        last_read_addr_o[i]  <= '0;
        last_write_addr_o[i] <= '0;
      end else begin
        if (init_req[i].ar_valid && init_resp[i].ar_ready) last_read_addr_o[i]  <= init_req[i].ar.addr;
        if (init_req[i].aw_valid && init_resp[i].aw_ready) last_write_addr_o[i] <= init_req[i].aw.addr;
      end
    end
  end

endmodule
