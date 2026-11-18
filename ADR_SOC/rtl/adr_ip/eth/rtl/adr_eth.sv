/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_eth.sv
 Module/class Name             : adr_eth
 Author                        : Vijay Bogati
 Description                   : Ethernet: 10G/25G MAC and digital PHY layer, with its own memory access and registers
***************************************************************/

// ADR SoC - Ethernet: 10G/25G MAC and digital PHY layer, with its own memory access and registers.
// The analog SerDes is outside the SoC. The line rate comes from its clocks: 390.625 MHz gives 25G
// and 156.25 MHz gives 10G, with Count125us set to match. The default is 25G; defining ADR_ETH_10G
// at build time (make ETH_RATE=10) gives 10G.
// Software gives one buffer at a time for each direction. There are no descriptor rings.
// The MAC adds the preamble and CRC on transmit, and pads short frames to 60 bytes.
// On receive it checks the CRC and removes it. Frames with a bad CRC never reach memory.
//
// The data cache doesn't see what this block writes: read receive buffers uncached.
//
// Registers (32-bit):
//   0x00 CTRL       [0] transmit enable, [1] receive enable,
//                   [2] interrupt on transmit done, [3] interrupt on receive done
//   0x04 STATUS     [0] transmit busy, [1] transmit done, [2] transmit bus error,
//                   [3] receive busy,  [4] receive done,  [5] receive bus error,
//                   [6] bad frame dropped; write 1 to clear bits 1, 2, 4, 5 and 6
//                   [8] receive block lock, [9] receive high bit error rate, [10] link good
//   0x08 TX_ADDR_LO, 0x0C TX_ADDR_HI, 0x10 TX_LEN   frame to send, length in bytes
//   0x14 TX_START   write 1 to send
//   0x18 RX_ADDR_LO, 0x1C RX_ADDR_HI, 0x20 RX_SIZE  buffer for the next frame
//   0x24 RX_START   write 1 to wait for a frame
//   0x28 RX_LEN     bytes written by the last receive; a longer frame is cut at RX_SIZE

module adr_eth #(
  parameter int unsigned IdWidth    = 4,
  parameter int unsigned LenWidth   = 16,
  parameter int unsigned MaxBurst   = 8,
`ifdef ADR_ETH_10G
  parameter real         Count125us = 125000.0 / 6.4,   // PHY clocks in 125 us, at 156.25 MHz (10G)
`else
  parameter real         Count125us = 125000.0 / 2.56,  // PHY clocks in 125 us, at 390.625 MHz (25G)
`endif
  parameter type         axi_req_t  = logic,
  parameter type         axi_resp_t = logic
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  // Registers
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [7:0]  paddr_i,
  input  logic [31:0] pwdata_i,
  output logic [31:0] prdata_o,
  // Memory access
  output axi_req_t    axi_req_o,
  input  axi_resp_t   axi_resp_i,
  output logic        irq_o,
  // SerDes, with data and sync header per 66-bit block
  input  logic        tx_clk_i,
  input  logic        tx_rst_ni,
  input  logic        rx_clk_i,
  input  logic        rx_rst_ni,
  output logic [63:0] serdes_tx_data_o,
  output logic [1:0]  serdes_tx_hdr_o,
  input  logic [63:0] serdes_rx_data_i,
  input  logic [1:0]  serdes_rx_hdr_i,
  output logic        serdes_rx_bitslip_o,
  output logic        serdes_rx_reset_req_o
);

  localparam int unsigned Ifg = 12;  // standard gap between frames, in bytes

  logic                tx_en_q, rx_en_q, tx_irq_en_q, rx_irq_en_q;
  logic                tx_pending_q, tx_active_q, tx_done_q, tx_error_q;
  logic                rx_pending_q, rx_active_q, rx_done_q, rx_error_q, bad_frame_q;
  logic [63:0]         tx_addr_q, rx_addr_q;
  logic [LenWidth-1:0] tx_len_q, rx_size_q, rx_len_q;

  logic                tx_desc_ready, rx_desc_ready;
  logic [3:0]          tx_status_error, rx_status_error;
  logic                tx_status_valid, rx_status_valid;
  logic [LenWidth-1:0] rx_status_len;
  logic                bad_frame;
  logic [2:0]          link_sync_q [2];

  logic [63:0] tx_tdata, rx_tdata;
  logic [7:0]  tx_tkeep, rx_tkeep;
  logic        tx_tvalid, tx_tready, tx_tlast, rx_tvalid, rx_tready, rx_tlast;
  logic        rx_block_lock, rx_high_ber, rx_status;

  axi_dma #(
    .AXI_DATA_WIDTH    ( 64       ),
    .AXI_ADDR_WIDTH    ( 64       ),
    .AXI_ID_WIDTH      ( IdWidth  ),
    .AXI_MAX_BURST_LEN ( MaxBurst ),
    .AXIS_DATA_WIDTH   ( 64       ),
    .AXIS_USER_ENABLE  ( 0        ),
    .LEN_WIDTH         ( LenWidth ),
    .TAG_WIDTH         ( 1        ),
    .ENABLE_UNALIGNED  ( 1        )
  ) i_dma (
    .clk                           ( clk_i               ),
    .rst                           ( ~rst_ni             ),
    .s_axis_read_desc_addr         ( tx_addr_q           ),
    .s_axis_read_desc_len          ( tx_len_q            ),
    .s_axis_read_desc_tag          ( 1'b0                ),
    .s_axis_read_desc_id           ( '0                  ),
    .s_axis_read_desc_dest         ( '0                  ),
    .s_axis_read_desc_user         ( '0                  ),
    .s_axis_read_desc_valid        ( tx_pending_q        ),
    .s_axis_read_desc_ready        ( tx_desc_ready       ),
    .m_axis_read_desc_status_tag   (                     ),
    .m_axis_read_desc_status_error ( tx_status_error     ),
    .m_axis_read_desc_status_valid ( tx_status_valid     ),
    .m_axis_read_data_tdata        ( tx_tdata            ),
    .m_axis_read_data_tkeep        ( tx_tkeep            ),
    .m_axis_read_data_tvalid       ( tx_tvalid           ),
    .m_axis_read_data_tready       ( tx_tready           ),
    .m_axis_read_data_tlast        ( tx_tlast            ),
    .m_axis_read_data_tid          (                     ),
    .m_axis_read_data_tdest        (                     ),
    .m_axis_read_data_tuser        (                     ),
    .s_axis_write_desc_addr        ( rx_addr_q           ),
    .s_axis_write_desc_len         ( rx_size_q           ),
    .s_axis_write_desc_tag         ( 1'b0                ),
    .s_axis_write_desc_valid       ( rx_pending_q        ),
    .s_axis_write_desc_ready       ( rx_desc_ready       ),
    .m_axis_write_desc_status_len  ( rx_status_len       ),
    .m_axis_write_desc_status_tag  (                     ),
    .m_axis_write_desc_status_id   (                     ),
    .m_axis_write_desc_status_dest (                     ),
    .m_axis_write_desc_status_user (                     ),
    .m_axis_write_desc_status_error( rx_status_error     ),
    .m_axis_write_desc_status_valid( rx_status_valid     ),
    .s_axis_write_data_tdata       ( rx_tdata            ),
    .s_axis_write_data_tkeep       ( rx_tkeep            ),
    .s_axis_write_data_tvalid      ( rx_tvalid           ),
    .s_axis_write_data_tready      ( rx_tready           ),
    .s_axis_write_data_tlast       ( rx_tlast            ),
    .s_axis_write_data_tid         ( '0                  ),
    .s_axis_write_data_tdest       ( '0                  ),
    .s_axis_write_data_tuser       ( 1'b0                ),
    .m_axi_awid                    ( axi_req_o.aw.id     ),
    .m_axi_awaddr                  ( axi_req_o.aw.addr   ),
    .m_axi_awlen                   ( axi_req_o.aw.len    ),
    .m_axi_awsize                  ( axi_req_o.aw.size   ),
    .m_axi_awburst                 ( axi_req_o.aw.burst  ),
    .m_axi_awlock                  ( axi_req_o.aw.lock   ),
    .m_axi_awcache                 ( axi_req_o.aw.cache  ),
    .m_axi_awprot                  ( axi_req_o.aw.prot   ),
    .m_axi_awvalid                 ( axi_req_o.aw_valid  ),
    .m_axi_awready                 ( axi_resp_i.aw_ready ),
    .m_axi_wdata                   ( axi_req_o.w.data    ),
    .m_axi_wstrb                   ( axi_req_o.w.strb    ),
    .m_axi_wlast                   ( axi_req_o.w.last    ),
    .m_axi_wvalid                  ( axi_req_o.w_valid   ),
    .m_axi_wready                  ( axi_resp_i.w_ready  ),
    .m_axi_bid                     ( axi_resp_i.b.id     ),
    .m_axi_bresp                   ( axi_resp_i.b.resp   ),
    .m_axi_bvalid                  ( axi_resp_i.b_valid  ),
    .m_axi_bready                  ( axi_req_o.b_ready   ),
    .m_axi_arid                    ( axi_req_o.ar.id     ),
    .m_axi_araddr                  ( axi_req_o.ar.addr   ),
    .m_axi_arlen                   ( axi_req_o.ar.len    ),
    .m_axi_arsize                  ( axi_req_o.ar.size   ),
    .m_axi_arburst                 ( axi_req_o.ar.burst  ),
    .m_axi_arlock                  ( axi_req_o.ar.lock   ),
    .m_axi_arcache                 ( axi_req_o.ar.cache  ),
    .m_axi_arprot                  ( axi_req_o.ar.prot   ),
    .m_axi_arvalid                 ( axi_req_o.ar_valid  ),
    .m_axi_arready                 ( axi_resp_i.ar_ready ),
    .m_axi_rid                     ( axi_resp_i.r.id     ),
    .m_axi_rdata                   ( axi_resp_i.r.data   ),
    .m_axi_rresp                   ( axi_resp_i.r.resp   ),
    .m_axi_rlast                   ( axi_resp_i.r.last   ),
    .m_axi_rvalid                  ( axi_resp_i.r_valid  ),
    .m_axi_rready                  ( axi_req_o.r_ready   ),
    .read_enable                   ( tx_en_q             ),
    .write_enable                  ( rx_en_q             ),
    .write_abort                   ( 1'b0                )
  );

  // The engine has no use for these AXI fields.
  assign axi_req_o.aw.qos    = '0;
  assign axi_req_o.aw.region = '0;
  assign axi_req_o.aw.atop   = '0;
  assign axi_req_o.aw.user   = '0;
  assign axi_req_o.w.user    = '0;
  assign axi_req_o.ar.qos    = '0;
  assign axi_req_o.ar.region = '0;
  assign axi_req_o.ar.user   = '0;

  // The FIFOs hold whole frames, and a frame that doesn't fit is dropped, not stalled. So the
  // MAC never holds up memory access, and a read and a write to the same memory can't deadlock.
  eth_mac_phy_10g_fifo #(
    .DATA_WIDTH    ( 64        ),
    .AXIS_DATA_WIDTH ( 64      ),
    .COUNT_125US   ( Count125us ),
    .TX_FIFO_DEPTH ( 4096      ),
    .RX_FIFO_DEPTH ( 4096      )
  ) i_mac (
    .rx_clk                 ( rx_clk_i        ),
    .rx_rst                 ( ~rx_rst_ni      ),
    .tx_clk                 ( tx_clk_i        ),
    .tx_rst                 ( ~tx_rst_ni      ),
    .logic_clk              ( clk_i           ),
    .logic_rst              ( ~rst_ni         ),
    .ptp_sample_clk         ( 1'b0            ),
    .tx_axis_tdata          ( tx_tdata        ),
    .tx_axis_tkeep          ( tx_tkeep        ),
    .tx_axis_tvalid         ( tx_tvalid       ),
    .tx_axis_tready         ( tx_tready       ),
    .tx_axis_tlast          ( tx_tlast        ),
    .tx_axis_tuser          ( 1'b0            ),
    .m_axis_tx_ptp_ts_96    (                 ),
    .m_axis_tx_ptp_ts_tag   (                 ),
    .m_axis_tx_ptp_ts_valid (                 ),
    .m_axis_tx_ptp_ts_ready ( 1'b1            ),
    .rx_axis_tdata          ( rx_tdata        ),
    .rx_axis_tkeep          ( rx_tkeep        ),
    .rx_axis_tvalid         ( rx_tvalid       ),
    .rx_axis_tready         ( rx_tready       ),
    .rx_axis_tlast          ( rx_tlast        ),
    .rx_axis_tuser          (                 ),
    .serdes_tx_data         ( serdes_tx_data_o ),
    .serdes_tx_hdr          ( serdes_tx_hdr_o  ),
    .serdes_rx_data         ( serdes_rx_data_i ),
    .serdes_rx_hdr          ( serdes_rx_hdr_i  ),
    .serdes_rx_bitslip      ( serdes_rx_bitslip_o ),
    .serdes_rx_reset_req    ( serdes_rx_reset_req_o ),
    .tx_error_underflow     (                 ),
    .tx_fifo_overflow       (                 ),
    .tx_fifo_bad_frame      (                 ),
    .tx_fifo_good_frame     (                 ),
    .rx_error_bad_frame     (                 ),
    .rx_error_bad_fcs       (                 ),
    .rx_bad_block           (                 ),
    .rx_block_lock          ( rx_block_lock   ),
    .rx_high_ber            ( rx_high_ber     ),
    .rx_status              ( rx_status       ),
    .rx_fifo_overflow       (                 ),
    .rx_fifo_bad_frame      ( bad_frame       ),
    .rx_fifo_good_frame     (                 ),
    .ptp_ts_96              ( '0              ),
    .ptp_ts_step            ( 1'b0            ),
    .cfg_ifg                ( 8'(Ifg)         ),
    .cfg_tx_enable          ( tx_en_q         ),
    .cfg_rx_enable          ( rx_en_q         ),
    .cfg_tx_prbs31_enable   ( 1'b0            ),
    .cfg_rx_prbs31_enable   ( 1'b0            )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Registers
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic write;
  assign write = psel_i && penable_i && pwrite_i;
  assign irq_o = (tx_done_q && tx_irq_en_q) || (rx_done_q && rx_irq_en_q);

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      {tx_en_q, rx_en_q, tx_irq_en_q, rx_irq_en_q}       <= '0;
      {tx_pending_q, tx_active_q, tx_done_q, tx_error_q} <= '0;
      {rx_pending_q, rx_active_q, rx_done_q, rx_error_q} <= '0;
      bad_frame_q <= 1'b0;
      link_sync_q[0] <= '0;
      link_sync_q[1] <= '0;
      tx_addr_q   <= '0;
      rx_addr_q   <= '0;
      tx_len_q    <= '0;
      rx_size_q   <= '0;
      rx_len_q    <= '0;
    end else begin
      if (write) begin
        unique case (paddr_i)
          8'h00: {rx_irq_en_q, tx_irq_en_q, rx_en_q, tx_en_q} <= pwdata_i[3:0];
          8'h04: begin
            if (pwdata_i[1]) tx_done_q   <= 1'b0;
            if (pwdata_i[2]) tx_error_q  <= 1'b0;
            if (pwdata_i[4]) rx_done_q   <= 1'b0;
            if (pwdata_i[5]) rx_error_q  <= 1'b0;
            if (pwdata_i[6]) bad_frame_q <= 1'b0;
          end
          8'h08: tx_addr_q[31:0]  <= pwdata_i;
          8'h0C: tx_addr_q[63:32] <= pwdata_i;
          8'h10: tx_len_q         <= pwdata_i[LenWidth-1:0];
          8'h14: if (pwdata_i[0] && tx_en_q && !tx_pending_q && !tx_active_q &&
                     tx_len_q != '0) begin
            tx_pending_q <= 1'b1;
            tx_done_q    <= 1'b0;
            tx_error_q   <= 1'b0;
          end
          8'h18: rx_addr_q[31:0]  <= pwdata_i;
          8'h1C: rx_addr_q[63:32] <= pwdata_i;
          8'h20: rx_size_q        <= pwdata_i[LenWidth-1:0];
          8'h24: if (pwdata_i[0] && rx_en_q && !rx_pending_q && !rx_active_q &&
                     rx_size_q != '0) begin
            rx_pending_q <= 1'b1;
            rx_done_q    <= 1'b0;
            rx_error_q   <= 1'b0;
          end
          default: ;
        endcase
      end

      if (tx_pending_q && tx_desc_ready) begin
        tx_pending_q <= 1'b0;
        tx_active_q  <= 1'b1;
      end
      if (tx_status_valid) begin
        tx_active_q <= 1'b0;
        tx_done_q   <= 1'b1;
        if (tx_status_error != 4'd0) tx_error_q <= 1'b1;
      end

      if (rx_pending_q && rx_desc_ready) begin
        rx_pending_q <= 1'b0;
        rx_active_q  <= 1'b1;
      end
      if (rx_status_valid) begin
        rx_active_q <= 1'b0;
        rx_done_q   <= 1'b1;
        rx_len_q    <= rx_status_len;
        if (rx_status_error != 4'd0) rx_error_q <= 1'b1;
      end

      if (bad_frame) bad_frame_q <= 1'b1;
      link_sync_q[0] <= {rx_status, rx_high_ber, rx_block_lock};
      link_sync_q[1] <= link_sync_q[0];
    end
  end

  always_comb begin
    unique case (paddr_i)
      8'h00:   prdata_o = {28'b0, rx_irq_en_q, tx_irq_en_q, rx_en_q, tx_en_q};
      8'h04:   prdata_o = {21'b0, link_sync_q[1], 1'b0, bad_frame_q, rx_error_q, rx_done_q, rx_pending_q | rx_active_q,
                           tx_error_q, tx_done_q, tx_pending_q | tx_active_q};
      8'h08:   prdata_o = tx_addr_q[31:0];
      8'h0C:   prdata_o = tx_addr_q[63:32];
      8'h10:   prdata_o = 32'(tx_len_q);
      8'h18:   prdata_o = rx_addr_q[31:0];
      8'h1C:   prdata_o = rx_addr_q[63:32];
      8'h20:   prdata_o = 32'(rx_size_q);
      8'h28:   prdata_o = 32'(rx_len_q);
      default: prdata_o = '0;
    endcase
  end

endmodule
