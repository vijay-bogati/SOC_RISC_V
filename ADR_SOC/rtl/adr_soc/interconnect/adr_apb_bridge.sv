/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_apb_bridge.sv
 Module/class Name             : adr_apb_bridge
 Author                        : Vijay Bogati
 Description                   : APB bridge: one crossbar target port to the APB slots of every block
***************************************************************/

//   64-bit AXI4 - axi_dw_converter - 32-bit AXI4 - axi_to_axi_lite - AXI4-Lite - axi_lite_to_apb
//
// The width converter splits each 64-bit access into 32-bit ones. axi_to_axi_lite turns bursts
// into single transfers and stops atomics; its AXI4-Lite output is only the input format of
// axi_lite_to_apb, as no block uses AXI4-Lite. axi_lite_to_apb decodes the address into one of
// NumApbSlots slots and returns a decode error when no slot matches.
//
// Peripheral clock gating: a peripheral whose clock is off can't answer, so the bridge replies
// for it at once with an error. Otherwise the access could wait forever.

`include "axi/typedef.svh"

module adr_apb_bridge
  import adr_soc_pkg::*;
#(
  parameter int unsigned IdWidth   = 1,
  parameter int unsigned UserWidth = 1,
  parameter type         slv_aw_chan_t = logic,
  parameter type         slv_w_chan_t  = logic,
  parameter type         slv_b_chan_t  = logic,
  parameter type         slv_ar_chan_t = logic,
  parameter type         slv_r_chan_t  = logic,
  parameter type         slv_req_t     = logic,
  parameter type         slv_resp_t    = logic
) (
  input  logic                         clk_i,
  input  logic                         rst_ni,
  input  slv_req_t                     slv_req_i,
  output slv_resp_t                    slv_resp_o,
  input  logic [31:0]                  clk_en_i,    // CLK_EN from system control
  output apb_req_t  [NumApbSlots-1:0]  apb_req_o,
  input  apb_resp_t [NumApbSlots-1:0]  apb_resp_i
);

  typedef logic [AddrWidth-1:0]      addr_t;
  typedef logic [ApbDataWidth-1:0]   data_t;
  typedef logic [ApbDataWidth/8-1:0] strb_t;
  typedef logic [IdWidth-1:0]        id_t;
  typedef logic [UserWidth-1:0]      user_t;

  `AXI_TYPEDEF_ALL(narrow, addr_t, id_t, data_t, strb_t, user_t)
  `AXI_LITE_TYPEDEF_ALL(lite, addr_t, data_t, strb_t)

  narrow_req_t  narrow_req;
  narrow_resp_t narrow_resp;
  lite_req_t    lite_req;
  lite_resp_t   lite_resp;
  apb_resp_t [NumApbSlots-1:0] apb_resp_gated;

  axi_dw_converter #(
    .AxiMaxReads         ( 4             ),
    .AxiSlvPortDataWidth ( DataWidth     ),
    .AxiMstPortDataWidth ( ApbDataWidth  ),
    .AxiAddrWidth        ( AddrWidth     ),
    .AxiIdWidth          ( IdWidth       ),
    .aw_chan_t           ( slv_aw_chan_t ),
    .mst_w_chan_t        ( narrow_w_chan_t ),
    .slv_w_chan_t        ( slv_w_chan_t  ),
    .b_chan_t            ( slv_b_chan_t  ),
    .ar_chan_t           ( slv_ar_chan_t ),
    .mst_r_chan_t        ( narrow_r_chan_t ),
    .slv_r_chan_t        ( slv_r_chan_t  ),
    .axi_mst_req_t       ( narrow_req_t  ),
    .axi_mst_resp_t      ( narrow_resp_t ),
    .axi_slv_req_t       ( slv_req_t     ),
    .axi_slv_resp_t      ( slv_resp_t    )
  ) i_width_down (
    .clk_i,
    .rst_ni,
    .slv_req_i  ( slv_req_i   ),
    .slv_resp_o ( slv_resp_o  ),
    .mst_req_o  ( narrow_req  ),
    .mst_resp_i ( narrow_resp )
  );

  axi_to_axi_lite #(
    .AxiAddrWidth    ( AddrWidth     ),
    .AxiDataWidth    ( ApbDataWidth  ),
    .AxiIdWidth      ( IdWidth       ),
    .AxiUserWidth    ( UserWidth     ),
    .AxiMaxWriteTxns ( 4             ),
    .AxiMaxReadTxns  ( 4             ),
    .FallThrough     ( 1'b0          ),
    .full_req_t      ( narrow_req_t  ),
    .full_resp_t     ( narrow_resp_t ),
    .lite_req_t      ( lite_req_t    ),
    .lite_resp_t     ( lite_resp_t   )
  ) i_to_lite (
    .clk_i,
    .rst_ni,
    .test_i     ( 1'b0        ),
    .slv_req_i  ( narrow_req  ),
    .slv_resp_o ( narrow_resp ),
    .mst_req_o  ( lite_req    ),
    .mst_resp_i ( lite_resp   )
  );

  axi_pkg::xbar_rule_64_t [NumApbSlots-1:0] slot_map;
  assign slot_map[SlotUart0]  = '{ idx: SlotUart0,  start_addr: Uart0Base,  end_addr: Uart0Base + SlotSize };
  assign slot_map[SlotUart1]  = '{ idx: SlotUart1,  start_addr: Uart1Base,  end_addr: Uart1Base + SlotSize };
  assign slot_map[SlotGpio]   = '{ idx: SlotGpio,   start_addr: GpioBase,   end_addr: GpioBase + SlotSize };
  assign slot_map[SlotTimer]  = '{ idx: SlotTimer,  start_addr: TimerBase,  end_addr: TimerBase + SlotSize };
  assign slot_map[SlotSpi]    = '{ idx: SlotSpi,    start_addr: SpiBase,    end_addr: SpiBase + SlotSize };
  assign slot_map[SlotQspi]   = '{ idx: SlotQspi,   start_addr: QspiBase,   end_addr: QspiBase + SlotSize };
  assign slot_map[SlotI2c]    = '{ idx: SlotI2c,    start_addr: I2cBase,    end_addr: I2cBase + SlotSize };
  assign slot_map[SlotPwm]    = '{ idx: SlotPwm,    start_addr: PwmBase,    end_addr: PwmBase + SlotSize };
  assign slot_map[SlotWdt]    = '{ idx: SlotWdt,    start_addr: WdtBase,    end_addr: WdtBase + SlotSize };
  assign slot_map[SlotAes]    = '{ idx: SlotAes,    start_addr: AesBase,    end_addr: AesBase + SlotSize };
  assign slot_map[SlotBusMon] = '{ idx: SlotBusMon, start_addr: BusMonBase, end_addr: BusMonBase + SlotSize };
  assign slot_map[SlotSys]    = '{ idx: SlotSys,    start_addr: SysBase,    end_addr: SysBase + SlotSize };
  assign slot_map[SlotDma]    = '{ idx: SlotDma,    start_addr: DmaBase,    end_addr: DmaBase + SlotSize };
  assign slot_map[SlotMux]    = '{ idx: SlotMux,    start_addr: MuxBase,    end_addr: MuxBase + SlotSize };
  assign slot_map[SlotAdc]    = '{ idx: SlotAdc,    start_addr: AdcBase,    end_addr: AdcBase + SlotSize };
  assign slot_map[SlotOtp]    = '{ idx: SlotOtp,    start_addr: OtpBase,    end_addr: OtpBase + SlotSize };
  assign slot_map[SlotAon]    = '{ idx: SlotAon,    start_addr: AonBase,    end_addr: AonBase + SlotSize };
  assign slot_map[SlotEth]    = '{ idx: SlotEth,    start_addr: EthBase,    end_addr: EthBase + SlotSize };
  assign slot_map[SlotUsb]    = '{ idx: SlotUsb,    start_addr: UsbBase,    end_addr: UsbBase + SlotSize };
  assign slot_map[SlotDdr]    = '{ idx: SlotDdr,    start_addr: DdrCtlBase, end_addr: DdrCtlBase + DdrCtlSize };
  assign slot_map[SlotPlic]   = '{ idx: SlotPlic,   start_addr: PlicBase,   end_addr: PlicBase + PlicSize };

  axi_lite_to_apb #(
    .NoApbSlaves      ( NumApbSlots  ),
    .NoRules          ( NumApbSlots  ),
    .AddrWidth        ( AddrWidth    ),
    .DataWidth        ( ApbDataWidth ),
    .PipelineRequest  ( 1'b1         ),
    .PipelineResponse ( 1'b1         ),
    .axi_lite_req_t   ( lite_req_t   ),
    .axi_lite_resp_t  ( lite_resp_t  ),
    .apb_req_t        ( apb_req_t    ),
    .apb_resp_t       ( apb_resp_t   ),
    .rule_t           ( axi_pkg::xbar_rule_64_t )
  ) i_to_apb (
    .clk_i,
    .rst_ni,
    .axi_lite_req_i  ( lite_req       ),
    .axi_lite_resp_o ( lite_resp      ),
    .apb_req_o       ( apb_req_o      ),
    .apb_resp_i      ( apb_resp_gated ),
    .addr_map_i      ( slot_map       )
  );

  // Replies for peripherals whose clock is off.
  logic [NumApbSlots-1:0] slot_clk_on;

  always_comb begin
    slot_clk_on             = '1;
    slot_clk_on[SlotUart1]  = clk_en_i[ClkUart1];
    slot_clk_on[SlotSpi]    = clk_en_i[ClkSpi];
    slot_clk_on[SlotQspi]   = clk_en_i[ClkQspi];
    slot_clk_on[SlotI2c]    = clk_en_i[ClkI2c];
    slot_clk_on[SlotPwm]    = clk_en_i[ClkPwm];
    slot_clk_on[SlotGpio]   = clk_en_i[ClkGpio];
    slot_clk_on[SlotTimer]  = clk_en_i[ClkTimer];
    slot_clk_on[SlotAes]    = clk_en_i[ClkAes];
    slot_clk_on[SlotAdc]    = clk_en_i[ClkAdc];
    for (int i = 0; i < int'(NumApbSlots); i++) begin
      apb_resp_gated[i] = apb_resp_i[i];
      if (!slot_clk_on[i]) begin
        apb_resp_gated[i].pready  = 1'b1;
        apb_resp_gated[i].pslverr = 1'b1;
        apb_resp_gated[i].prdata  = '0;
      end
    end
  end

endmodule
