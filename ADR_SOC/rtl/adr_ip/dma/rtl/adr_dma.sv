/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_dma.sv
 Module/class Name             : adr_dma
 Author                        : Vijay Bogati
 Description                   : Memory-to-memory DMA with several channels sharing one copy engine
***************************************************************/

// ADR SoC - memory-to-memory DMA with several channels sharing one copy engine.
// Channels take turns, and each transfer runs to completion before the next one starts.
//
// Read flow control: the SRAM serves one burst at a time. If this block refused read data
// because its FIFO was full, the memory would wait on it while it waited to write to the
// memory, and both would stop. So a read burst is only requested when the FIFO is sure to
// have room for all of it, and read data is never refused.
//
// Registers (32-bit), channel n at offset 0x20 * n:
//   0x00 SRC_LO, 0x04 SRC_HI   source address
//   0x08 DST_LO, 0x0C DST_HI   destination address
//   0x10 LEN                   length in bytes, up to 2^LenWidth - 1
//   0x14 CTRL     [0] start (write 1), [1] interrupt when finished
//   0x18 STATUS   [0] busy, [1] done, [2] bus error; write 1 to clear bits 1 and 2

module adr_dma #(
  parameter int unsigned NumChannels = 4,
  parameter int unsigned IdWidth     = 4,
  parameter int unsigned LenWidth    = 24,
  parameter int unsigned MaxBurst    = 8,
  parameter int unsigned ReadCredit  = 12,  // engine FIFO stops reads at 16 beats
  parameter type         axi_req_t   = logic,
  parameter type         axi_resp_t  = logic
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
  output logic        pready_o,
  output logic        pslverr_o,
  // Memory access
  output axi_req_t    axi_req_o,
  input  axi_resp_t   axi_resp_i,
  output logic        irq_o
);

  localparam int unsigned ChIdxWidth = $clog2(NumChannels);

  logic [63:0]         src_q [NumChannels];
  logic [63:0]         dst_q [NumChannels];
  logic [LenWidth-1:0] len_q [NumChannels];
  logic [NumChannels-1:0] pending_q, active_q, done_q, error_q, irq_en_q;
  logic [ChIdxWidth-1:0]  next_q;

  logic write;
  logic [ChIdxWidth-1:0] reg_ch;
  logic [2:0]            reg_idx;
  assign write     = psel_i && penable_i && pwrite_i;
  assign reg_ch    = paddr_i[5+:ChIdxWidth];
  assign reg_idx   = paddr_i[4:2];
  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;
  assign irq_o     = |(done_q & irq_en_q);

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Round-robin choice of the next pending channel
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic                  have_choice;
  logic [ChIdxWidth-1:0] choice;
  always_comb begin
    have_choice = 1'b0;
    choice      = '0;
    for (int i = 0; i < int'(NumChannels); i++) begin
      automatic logic [ChIdxWidth-1:0] c = ChIdxWidth'((int'(next_q) + i) % int'(NumChannels));
      if (!have_choice && pending_q[c]) begin
        have_choice = 1'b1;
        choice      = c;
      end
    end
  end

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Copy engine
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic                  desc_valid, desc_ready, status_valid;
  logic [7:0]            status_tag;
  logic [3:0]            status_error;
  logic                  transfer_open_q;

  // Beats requested but not yet written. A burst can read one beat more than it writes, when
  // source and destination have different alignment, and one write burst can need two read
  // bursts. So the count can't just fall to zero by itself: it clears when a write burst ends
  // with no read outstanding, as nothing is then waiting to be written.
  logic       engine_ar_valid, engine_ar_ready, ar_allowed;
  logic [7:0] beats_in_flight_q;
  logic [1:0] reads_open_q;
  assign ar_allowed = (int'(beats_in_flight_q) + int'(axi_req_o.ar.len) + 1) <= int'(ReadCredit);
  assign axi_req_o.ar_valid = engine_ar_valid && ar_allowed;
  assign engine_ar_ready    = axi_resp_i.ar_ready && ar_allowed;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      beats_in_flight_q <= '0;
      reads_open_q      <= '0;
    end else begin
      automatic int count   = int'(beats_in_flight_q);
      automatic int reads   = int'(reads_open_q);
      automatic bit ar_fire = axi_req_o.ar_valid && axi_resp_i.ar_ready;
      automatic bit r_end   = axi_resp_i.r_valid && axi_req_o.r_ready && axi_resp_i.r.last;
      automatic bit w_fire  = axi_req_o.w_valid && axi_resp_i.w_ready;
      if (ar_fire) reads++;
      if (r_end)   reads--;
      if (w_fire && count > 0) count--;
      if (w_fire && axi_req_o.w.last && reads == 0) count = 0;
      if (ar_fire) count += int'(axi_req_o.ar.len) + 1;
      if (status_valid) count = 0;
      beats_in_flight_q <= 8'(count);
      reads_open_q      <= 2'(reads);
    end
  end

  // One transfer at a time, so that a channel's transfers finish in order.
  assign desc_valid = have_choice && !transfer_open_q;

  axi_cdma #(
    .AXI_DATA_WIDTH    ( 64       ),
    .AXI_ADDR_WIDTH    ( 64       ),
    .AXI_ID_WIDTH      ( IdWidth  ),
    .AXI_MAX_BURST_LEN ( MaxBurst ),
    .LEN_WIDTH         ( LenWidth ),
    .TAG_WIDTH         ( 8        ),
    .ENABLE_UNALIGNED  ( 1        )
  ) i_engine (
    .clk                      ( clk_i                  ),
    .rst                      ( ~rst_ni                ),
    .s_axis_desc_read_addr    ( src_q[choice]          ),
    .s_axis_desc_write_addr   ( dst_q[choice]          ),
    .s_axis_desc_len          ( len_q[choice]          ),
    .s_axis_desc_tag          ( 8'(choice)             ),
    .s_axis_desc_valid        ( desc_valid             ),
    .s_axis_desc_ready        ( desc_ready             ),
    .m_axis_desc_status_tag   ( status_tag             ),
    .m_axis_desc_status_error ( status_error           ),
    .m_axis_desc_status_valid ( status_valid           ),
    .m_axi_awid               ( axi_req_o.aw.id        ),
    .m_axi_awaddr             ( axi_req_o.aw.addr      ),
    .m_axi_awlen              ( axi_req_o.aw.len       ),
    .m_axi_awsize             ( axi_req_o.aw.size      ),
    .m_axi_awburst            ( axi_req_o.aw.burst     ),
    .m_axi_awlock             ( axi_req_o.aw.lock      ),
    .m_axi_awcache            ( axi_req_o.aw.cache     ),
    .m_axi_awprot             ( axi_req_o.aw.prot      ),
    .m_axi_awvalid            ( axi_req_o.aw_valid     ),
    .m_axi_awready            ( axi_resp_i.aw_ready    ),
    .m_axi_wdata              ( axi_req_o.w.data       ),
    .m_axi_wstrb              ( axi_req_o.w.strb       ),
    .m_axi_wlast              ( axi_req_o.w.last       ),
    .m_axi_wvalid             ( axi_req_o.w_valid      ),
    .m_axi_wready             ( axi_resp_i.w_ready     ),
    .m_axi_bid                ( axi_resp_i.b.id        ),
    .m_axi_bresp              ( axi_resp_i.b.resp      ),
    .m_axi_bvalid             ( axi_resp_i.b_valid     ),
    .m_axi_bready             ( axi_req_o.b_ready      ),
    .m_axi_arid               ( axi_req_o.ar.id        ),
    .m_axi_araddr             ( axi_req_o.ar.addr      ),
    .m_axi_arlen              ( axi_req_o.ar.len       ),
    .m_axi_arsize             ( axi_req_o.ar.size      ),
    .m_axi_arburst            ( axi_req_o.ar.burst     ),
    .m_axi_arlock             ( axi_req_o.ar.lock      ),
    .m_axi_arcache            ( axi_req_o.ar.cache     ),
    .m_axi_arprot             ( axi_req_o.ar.prot      ),
    .m_axi_arvalid            ( engine_ar_valid        ),
    .m_axi_arready            ( engine_ar_ready        ),
    .m_axi_rid                ( axi_resp_i.r.id        ),
    .m_axi_rdata              ( axi_resp_i.r.data      ),
    .m_axi_rresp              ( axi_resp_i.r.resp      ),
    .m_axi_rlast              ( axi_resp_i.r.last      ),
    .m_axi_rvalid             ( axi_resp_i.r_valid     ),
    .m_axi_rready             ( axi_req_o.r_ready      ),
    .enable                   ( 1'b1                   )
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

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Registers
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      pending_q       <= '0;
      active_q        <= '0;
      done_q          <= '0;
      error_q         <= '0;
      irq_en_q        <= '0;
      next_q          <= '0;
      transfer_open_q <= 1'b0;
      for (int i = 0; i < int'(NumChannels); i++) begin
        src_q[i] <= '0;
        dst_q[i] <= '0;
        len_q[i] <= '0;
      end
    end else begin
      if (write) begin
        unique case (reg_idx)
          3'd0: src_q[reg_ch][31:0]  <= pwdata_i;
          3'd1: src_q[reg_ch][63:32] <= pwdata_i;
          3'd2: dst_q[reg_ch][31:0]  <= pwdata_i;
          3'd3: dst_q[reg_ch][63:32] <= pwdata_i;
          3'd4: len_q[reg_ch]        <= pwdata_i[LenWidth-1:0];
          3'd5: begin
            irq_en_q[reg_ch] <= pwdata_i[1];
            if (pwdata_i[0] && !pending_q[reg_ch] && !active_q[reg_ch]) begin
              if (len_q[reg_ch] == '0) begin
                done_q[reg_ch] <= 1'b1;  // nothing to copy
              end else begin
                pending_q[reg_ch] <= 1'b1;
                done_q[reg_ch]    <= 1'b0;
                error_q[reg_ch]   <= 1'b0;
              end
            end
          end
          3'd6: begin
            if (pwdata_i[1]) done_q[reg_ch]  <= 1'b0;
            if (pwdata_i[2]) error_q[reg_ch] <= 1'b0;
          end
          default: ;
        endcase
      end

      if (desc_valid && desc_ready) begin
        pending_q[choice] <= 1'b0;
        active_q[choice]  <= 1'b1;
        transfer_open_q   <= 1'b1;
        next_q            <= ChIdxWidth'((int'(choice) + 1) % int'(NumChannels));
      end

      if (status_valid) begin
        active_q[status_tag[ChIdxWidth-1:0]] <= 1'b0;
        done_q[status_tag[ChIdxWidth-1:0]]   <= 1'b1;
        if (status_error != 4'd0) error_q[status_tag[ChIdxWidth-1:0]] <= 1'b1;
        transfer_open_q <= 1'b0;
      end
    end
  end

  always_comb begin
    unique case (reg_idx)
      3'd0:    prdata_o = src_q[reg_ch][31:0];
      3'd1:    prdata_o = src_q[reg_ch][63:32];
      3'd2:    prdata_o = dst_q[reg_ch][31:0];
      3'd3:    prdata_o = dst_q[reg_ch][63:32];
      3'd4:    prdata_o = 32'(len_q[reg_ch]);
      3'd5:    prdata_o = {30'b0, irq_en_q[reg_ch], 1'b0};
      3'd6:    prdata_o = {29'b0, error_q[reg_ch], done_q[reg_ch],
                           pending_q[reg_ch] | active_q[reg_ch]};
      default: prdata_o = '0;
    endcase
  end

endmodule
