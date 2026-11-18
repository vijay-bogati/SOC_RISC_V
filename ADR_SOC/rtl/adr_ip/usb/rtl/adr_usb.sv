/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_usb.sv
 Module/class Name             : adr_usb
 Author                        : Vijay Bogati
 Description                   : USB 2.0 full-speed device: OpenTitan usbdev with an APB register port
***************************************************************/

// ADR SoC - USB 2.0 full-speed device: OpenTitan usbdev with an APB register port.
// The block runs entirely on its own clock, so register accesses cross into that clock. It
// has its own 2 KiB packet buffer, is not a bus master, and so has no DMA coherency concern.
//
// usb_clk_i must run whenever software touches these registers, or the access waits forever.
// A real part needs 48 MHz. The block's wake logic isn't included, so it can't wake the SoC.
//
// Registers and packet buffer: as documented upstream, at the same offsets. 32-bit accesses only.

module adr_usb (
  input  logic        clk_i,
  input  logic        rst_ni,
  // Registers
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [11:0] paddr_i,
  input  logic [31:0] pwdata_i,
  output logic [31:0] prdata_o,
  output logic        pready_o,
  output logic        pslverr_o,
  output logic        irq_o,
  // USB
  input  logic        usb_clk_i,
  input  logic        usb_rst_ni,
  input  logic        dp_i,
  input  logic        dn_i,
  output logic        dp_o,
  output logic        dp_en_o,
  output logic        dn_o,
  output logic        dn_en_o,
  input  logic        sense_i,
  output logic        dp_pullup_o,
  output logic        dn_pullup_o
);

  typedef enum logic [1:0] { Idle, Request, Response, Done } state_e;
  state_e state_q;

  tlul_pkg::tl_h2d_t bus_req, bus_req_intg, usb_req;
  tlul_pkg::tl_d2h_t bus_rsp, usb_rsp;
  logic [31:0]       rdata_q;
  logic              err_q;

  always_comb begin
    bus_req           = tlul_pkg::TL_H2D_DEFAULT;
    bus_req.a_valid   = (state_q == Request);
    bus_req.a_opcode  = pwrite_i ? tlul_pkg::PutFullData : tlul_pkg::Get;
    bus_req.a_size    = 2'd2;
    bus_req.a_address = {20'b0, paddr_i[11:2], 2'b00};
    bus_req.a_mask    = 4'hF;
    bus_req.a_data    = pwrite_i ? pwdata_i : tlul_pkg::BlankedAData;
    bus_req.d_ready   = (state_q == Response);
  end

  assign pready_o  = (state_q == Done);
  assign prdata_o  = rdata_q;
  assign pslverr_o = err_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      state_q <= Idle;
      rdata_q <= '0;
      err_q   <= 1'b0;
    end else begin
      unique case (state_q)
        Idle:     if (psel_i && penable_i) state_q <= Request;
        Request:  if (bus_rsp.a_ready) state_q <= Response;
        Response: if (bus_rsp.d_valid) begin
          rdata_q <= bus_rsp.d_data;
          err_q   <= bus_rsp.d_error;
          state_q <= Done;
        end
        Done:     state_q <= Idle;
        default:  state_q <= Idle;
      endcase
    end
  end

  // usbdev checks bus integrity, so requests must carry it.
  tlul_cmd_intg_gen #(
    .EnableDataIntgGen ( 1'b1 )
  ) i_intg (
    .tl_i ( bus_req      ),
    .tl_o ( bus_req_intg )
  );

  tlul_fifo_async #(
    .ReqDepth ( 4 ),
    .RspDepth ( 4 )
  ) i_cross (
    .clk_h_i  ( clk_i        ),
    .rst_h_ni ( rst_ni       ),
    .clk_d_i  ( usb_clk_i    ),
    .rst_d_ni ( usb_rst_ni   ),
    .tl_h_i   ( bus_req_intg ),
    .tl_h_o   ( bus_rsp      ),
    .tl_d_o   ( usb_req      ),
    .tl_d_i   ( usb_rsp      )
  );

  logic [17:0] irqs;
  assign irq_o = |irqs;

  // Alerts report bus integrity failures. Nothing in this SoC collects them.
  usbdev i_usbdev (
    .clk_i                        ( usb_clk_i  ),
    .rst_ni                       ( usb_rst_ni ),
    .clk_aon_i                    ( usb_clk_i  ),
    .rst_aon_ni                   ( usb_rst_ni ),
    .tl_i                         ( usb_req    ),
    .tl_o                         ( usb_rsp    ),
    .alert_rx_i                   ( '{default: prim_alert_pkg::ALERT_RX_DEFAULT} ),
    .alert_tx_o                   (            ),
    .cio_usb_dp_i                 ( dp_i       ),
    .cio_usb_dn_i                 ( dn_i       ),
    .usb_rx_d_i                   ( 1'b0       ),
    .cio_usb_dp_o                 ( dp_o       ),
    .cio_usb_dp_en_o              ( dp_en_o    ),
    .cio_usb_dn_o                 ( dn_o       ),
    .cio_usb_dn_en_o              ( dn_en_o    ),
    .usb_tx_se0_o                 (            ),
    .usb_tx_d_o                   (            ),
    .cio_sense_i                  ( sense_i    ),
    .usb_dp_pullup_o              ( dp_pullup_o ),
    .usb_dn_pullup_o              ( dn_pullup_o ),
    .usb_rx_enable_o              (            ),
    .usb_tx_use_d_se0_o           (            ),
    .usb_aon_suspend_req_o        (            ),
    .usb_aon_wake_ack_o           (            ),
    .usb_aon_bus_reset_i          ( 1'b0       ),
    .usb_aon_sense_lost_i         ( 1'b0       ),
    .usb_aon_bus_not_idle_i       ( 1'b0       ),
    .usb_aon_wake_detect_active_i ( 1'b0       ),
    .usb_ref_val_o                (            ),
    .usb_ref_pulse_o              (            ),
    .ram_cfg_i                    ( '0         ),
    .intr_pkt_received_o          ( irqs[0]    ),
    .intr_pkt_sent_o              ( irqs[1]    ),
    .intr_powered_o               ( irqs[2]    ),
    .intr_disconnected_o          ( irqs[3]    ),
    .intr_host_lost_o             ( irqs[4]    ),
    .intr_link_reset_o            ( irqs[5]    ),
    .intr_link_suspend_o          ( irqs[6]    ),
    .intr_link_resume_o           ( irqs[7]    ),
    .intr_av_out_empty_o          ( irqs[8]    ),
    .intr_rx_full_o               ( irqs[9]    ),
    .intr_av_overflow_o           ( irqs[10]   ),
    .intr_link_in_err_o           ( irqs[11]   ),
    .intr_link_out_err_o          ( irqs[12]   ),
    .intr_rx_crc_err_o            ( irqs[13]   ),
    .intr_rx_pid_err_o            ( irqs[14]   ),
    .intr_rx_bitstuff_err_o       ( irqs[15]   ),
    .intr_frame_o                 ( irqs[16]   ),
    .intr_av_setup_empty_o        ( irqs[17]   )
  );

endmodule
