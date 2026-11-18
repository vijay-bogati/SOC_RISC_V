/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_axi_mem.sv
 Module/class Name             : adr_axi_mem
 Author                        : Vijay Bogati
 Description                   : AXI4 target memory: protocol adapter plus storage
***************************************************************/

// The adapter serves one burst at a time, and once it starts a write it waits for the data. A
// master such as the DMA engine may need a read to finish before it can supply that data, and
// the two would then wait on each other. So write addresses and data are collected first, and a
// write only starts once all of its burst has arrived. Write bursts must fit in the buffer.

module adr_axi_mem #(
  parameter int unsigned IdWidth   = 1,
  parameter int unsigned UserWidth = 1,
  parameter int unsigned NumWords  = 1024,
  parameter bit          ReadOnly  = 1'b0,
  parameter string       ImageArg  = "",
  parameter int unsigned MaxWriteBeats = 16
) (
  input  logic  clk_i,
  input  logic  rst_ni,
  AXI_BUS.Slave slv
);

  localparam int unsigned ByteBits = 3;  // 8 bytes per 64-bit word

  logic                 req;
  logic                 we;
  logic [63:0]          addr;
  logic [7:0]           be;
  logic [63:0]          wdata;
  logic [63:0]          rdata;

  AXI_BUS #(
    .AXI_ADDR_WIDTH ( 64        ),
    .AXI_DATA_WIDTH ( 64        ),
    .AXI_ID_WIDTH   ( IdWidth   ),
    .AXI_USER_WIDTH ( UserWidth )
  ) mem_bus ();

  typedef struct packed {
    logic [63:0]          data;
    logic [7:0]           strb;
    logic                 last;
    logic [UserWidth-1:0] user;
  } w_beat_t;

  w_beat_t w_in, w_out;
  logic    w_full, w_empty;
  logic [$clog2(MaxWriteBeats):0] bursts_ready_q;
  logic    burst_in, burst_start;

  assign w_in = '{data: slv.w_data, strb: slv.w_strb, last: slv.w_last, user: slv.w_user};
  assign slv.w_ready = !w_full;

  fifo_v3 #(
    .DEPTH ( MaxWriteBeats ),
    .dtype ( w_beat_t      )
  ) i_write_buffer (
    .clk_i,
    .rst_ni,
    .flush_i    ( 1'b0                ),
    .testmode_i ( 1'b0                ),
    .full_o     ( w_full              ),
    .empty_o    ( w_empty             ),
    .usage_o    (                     ),
    .data_i     ( w_in                ),
    .push_i     ( slv.w_valid && !w_full ),
    .data_o     ( w_out               ),
    .pop_i      ( mem_bus.w_ready && !w_empty )
  );

  assign mem_bus.w_data  = w_out.data;
  assign mem_bus.w_strb  = w_out.strb;
  assign mem_bus.w_last  = w_out.last;
  assign mem_bus.w_user  = w_out.user;
  assign mem_bus.w_valid = !w_empty;

  // Write addresses are always taken straight away, as the atomics unit in front of this memory
  // sends no data until its address has been accepted.
  typedef struct packed {
    logic [IdWidth-1:0]   id;
    logic [63:0]          addr;
    logic [7:0]           len;
    logic [2:0]           size;
    logic [1:0]           burst;
    logic                 lock;
    logic [3:0]           cache;
    logic [2:0]           prot;
    logic [3:0]           qos;
    logic [3:0]           region;
    logic [5:0]           atop;
    logic [UserWidth-1:0] user;
  } aw_entry_t;

  aw_entry_t aw_in, aw_out;
  logic      aw_full, aw_empty;

  assign aw_in = '{id: slv.aw_id, addr: slv.aw_addr, len: slv.aw_len, size: slv.aw_size,
                   burst: slv.aw_burst, lock: slv.aw_lock, cache: slv.aw_cache,
                   prot: slv.aw_prot, qos: slv.aw_qos, region: slv.aw_region,
                   atop: slv.aw_atop, user: slv.aw_user};
  assign slv.aw_ready = !aw_full;

  fifo_v3 #(
    .DEPTH ( 4          ),
    .dtype ( aw_entry_t )
  ) i_address_buffer (
    .clk_i,
    .rst_ni,
    .flush_i    ( 1'b0                    ),
    .testmode_i ( 1'b0                    ),
    .full_o     ( aw_full                 ),
    .empty_o    ( aw_empty                ),
    .usage_o    (                         ),
    .data_i     ( aw_in                   ),
    .push_i     ( slv.aw_valid && !aw_full ),
    .data_o     ( aw_out                  ),
    .pop_i      ( burst_start             )
  );

  // A write starts once a whole burst is in the buffer.
  assign burst_in         = slv.w_valid && !w_full && slv.w_last;
  assign mem_bus.aw_valid = !aw_empty && (bursts_ready_q != '0);
  assign burst_start      = mem_bus.aw_valid && mem_bus.aw_ready;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      bursts_ready_q <= '0;
    end else if (burst_in && !burst_start) begin
      bursts_ready_q <= bursts_ready_q + 1'b1;
    end else if (burst_start && !burst_in) begin
      bursts_ready_q <= bursts_ready_q - 1'b1;
    end
  end

  assign mem_bus.aw_id     = aw_out.id;
  assign mem_bus.aw_addr   = aw_out.addr;
  assign mem_bus.aw_len    = aw_out.len;
  assign mem_bus.aw_size   = aw_out.size;
  assign mem_bus.aw_burst  = aw_out.burst;
  assign mem_bus.aw_lock   = aw_out.lock;
  assign mem_bus.aw_cache  = aw_out.cache;
  assign mem_bus.aw_prot   = aw_out.prot;
  assign mem_bus.aw_qos    = aw_out.qos;
  assign mem_bus.aw_region = aw_out.region;
  assign mem_bus.aw_atop   = aw_out.atop;
  assign mem_bus.aw_user   = aw_out.user;

  assign slv.b_valid       = mem_bus.b_valid;
  assign mem_bus.b_ready   = slv.b_ready;
  assign slv.b_id          = mem_bus.b_id;
  assign slv.b_resp        = mem_bus.b_resp;
  assign slv.b_user        = mem_bus.b_user;

  assign mem_bus.ar_valid  = slv.ar_valid;
  assign slv.ar_ready      = mem_bus.ar_ready;
  assign mem_bus.ar_id     = slv.ar_id;
  assign mem_bus.ar_addr   = slv.ar_addr;
  assign mem_bus.ar_len    = slv.ar_len;
  assign mem_bus.ar_size   = slv.ar_size;
  assign mem_bus.ar_burst  = slv.ar_burst;
  assign mem_bus.ar_lock   = slv.ar_lock;
  assign mem_bus.ar_cache  = slv.ar_cache;
  assign mem_bus.ar_prot   = slv.ar_prot;
  assign mem_bus.ar_qos    = slv.ar_qos;
  assign mem_bus.ar_region = slv.ar_region;
  assign mem_bus.ar_user   = slv.ar_user;

  assign slv.r_valid       = mem_bus.r_valid;
  assign mem_bus.r_ready   = slv.r_ready;
  assign slv.r_id          = mem_bus.r_id;
  assign slv.r_data        = mem_bus.r_data;
  assign slv.r_resp        = mem_bus.r_resp;
  assign slv.r_last        = mem_bus.r_last;
  assign slv.r_user        = mem_bus.r_user;

  axi2mem #(
    .AXI_ID_WIDTH   ( IdWidth   ),
    .AXI_ADDR_WIDTH ( 64        ),
    .AXI_DATA_WIDTH ( 64        ),
    .AXI_USER_WIDTH ( UserWidth )
  ) i_adapter (
    .clk_i,
    .rst_ni,
    .slave  ( mem_bus ),
    .req_o  ( req   ),
    .we_o   ( we    ),
    .addr_o ( addr  ),
    .be_o   ( be    ),
    .user_o (       ),
    .data_o ( wdata ),
    .user_i ( '0    ),
    .data_i ( rdata )
  );

  adr_mem_model #(
    .NumWords ( NumWords ),
    .ReadOnly ( ReadOnly ),
    .ImageArg ( ImageArg )
  ) i_storage (
    .clk_i,
    .req_i   ( req ),
    .we_i    ( we  ),
    .idx_i   ( 32'(addr[ByteBits +: $clog2(NumWords)]) ),
    .be_i    ( be    ),
    .wdata_i ( wdata ),
    .rdata_o ( rdata )
  );

endmodule
