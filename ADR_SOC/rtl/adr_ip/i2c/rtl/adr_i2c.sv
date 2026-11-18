/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_i2c.sv
 Module/class Name             : adr_i2c
 Author                        : Vijay Bogati
 Description                   : I2C master with an APB register interface and an interrupt
***************************************************************/

// The I2C engine is the unmodified verilog-i2c i2c_master, fed by three unmodified axis_fifo
// queues: commands, write data and read data. This block replaces that project's AXI4-Lite
// register wrapper with an APB one, keeping the same register map, and adds the interrupt.
//
// Registers (32-bit, word offsets):
//   0x00 STATUS      [0] busy  [1] bus_cont  [2] bus_act  [3] miss_ack (write 1 to clear)
//                    [8] cmd_empty  [9] cmd_full  [10] cmd_ovf (write 1 to clear)
//                    [11] wr_empty  [12] wr_full  [13] wr_ovf (write 1 to clear)
//                    [14] rd_empty  [15] rd_full
//   0x04 COMMAND     [6:0] address  [8] start  [9] read  [10] write  [11] write_multiple  [12] stop
//                    A write with any of bits 8-12 set queues a command. Reads return the last one.
//   0x08 DATA        write: [7:0] byte to send, [9] last byte of a write_multiple, queued
//                    read:  [7:0] received byte, [8] valid, [9] last; a valid read removes it.
//                    Reads 0 when nothing has been received.
//   0x0C PRESCALE    [15:0] clock divider, one quarter of the SCL period in clock cycles
//   0x10 IRQ_ENABLE  [3:0] one bit per IRQ_STATUS bit
//   0x14 IRQ_STATUS  [0] done: the controller went idle with no command queued (write 1 to clear)
//                    [1] miss_ack: same flag as STATUS[3] (write 1 to clear)
//                    [2] rx_ready: received data is waiting (clears when it is read)
//                    [3] overflow: STATUS cmd_ovf or wr_ovf (clear them in STATUS)
// The interrupt is high while any enabled IRQ_STATUS bit is set, so its PLIC source is
// level-triggered. Byte strobes are honoured, as in the original wrapper: DATA[9] is only
// taken from a write that covers both low bytes.

module adr_i2c #(
  parameter int unsigned FifoDepth       = 32,
  parameter logic [15:0] DefaultPrescale = 16'd1
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  // APB target
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [4:0]  paddr_i,
  input  logic [31:0] pwdata_i,
  input  logic [3:0]  pstrb_i,
  output logic [31:0] prdata_o,
  output logic        pready_o,
  output logic        pslverr_o,
  output logic        irq_o,
  // I2C pins: open-drain, a line is released when its _t output is high
  input  logic        scl_i,
  output logic        scl_o,
  output logic        scl_t,
  input  logic        sda_i,
  output logic        sda_o,
  output logic        sda_t
);

  localparam logic [4:0] RegStatus    = 5'h00;
  localparam logic [4:0] RegCommand   = 5'h04;
  localparam logic [4:0] RegData      = 5'h08;
  localparam logic [4:0] RegPrescale  = 5'h0C;
  localparam logic [4:0] RegIrqEnable = 5'h10;
  localparam logic [4:0] RegIrqStatus = 5'h14;

  logic rst;  // the third-party blocks use a synchronous active-high reset
  assign rst = ~rst_ni;

  logic access, write, read;
  assign access    = psel_i && penable_i;
  assign write     = access && pwrite_i;
  assign read      = access && !pwrite_i;
  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Register state
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic [6:0]  cmd_address_q;
  logic [4:0]  cmd_bits_q;  // {stop, write_multiple, write, read, start}, last command written
  logic [15:0] prescale_q;
  logic        missed_ack_q, cmd_ovf_q, wr_ovf_q, done_q, busy_q;
  logic [3:0]  irq_enable_q;

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Command queue: a COMMAND write with any command bit set pushes one entry.
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic [6:0]  cmd_wr_address;
  logic [4:0]  cmd_wr_bits;
  logic        cmd_push, cmd_in_ready;
  logic [6:0]  cmd_address;
  logic        cmd_start, cmd_read, cmd_write, cmd_write_multiple, cmd_stop;
  logic        cmd_valid, cmd_ready;

  assign cmd_wr_address = pstrb_i[0] ? pwdata_i[6:0] : cmd_address_q;
  assign cmd_wr_bits    = pwdata_i[12:8];
  assign cmd_push       = write && (paddr_i == RegCommand) && pstrb_i[1] && (|cmd_wr_bits);

  axis_fifo #(
    .DEPTH        ( FifoDepth ),
    .DATA_WIDTH   ( 12        ),
    .KEEP_ENABLE  ( 0         ),
    .LAST_ENABLE  ( 0         ),
    .ID_ENABLE    ( 0         ),
    .DEST_ENABLE  ( 0         ),
    .USER_ENABLE  ( 0         ),
    .FRAME_FIFO   ( 0         )
  ) i_cmd_fifo (
    .clk                ( clk_i ),
    .rst                ( rst   ),
    .s_axis_tdata       ( {cmd_wr_address, cmd_wr_bits[0], cmd_wr_bits[1], cmd_wr_bits[2],
                           cmd_wr_bits[3], cmd_wr_bits[4]} ),
    .s_axis_tkeep       ( 1'b0         ),
    .s_axis_tvalid      ( cmd_push     ),
    .s_axis_tready      ( cmd_in_ready ),
    .s_axis_tlast       ( 1'b0         ),
    .s_axis_tid         ( 8'd0         ),
    .s_axis_tdest       ( 8'd0         ),
    .s_axis_tuser       ( 1'b0         ),
    .m_axis_tdata       ( {cmd_address, cmd_start, cmd_read, cmd_write, cmd_write_multiple,
                           cmd_stop} ),
    .m_axis_tkeep       (              ),
    .m_axis_tvalid      ( cmd_valid    ),
    .m_axis_tready      ( cmd_ready    ),
    .m_axis_tlast       (              ),
    .m_axis_tid         (              ),
    .m_axis_tdest       (              ),
    .m_axis_tuser       (              ),
    .status_overflow    (              ),
    .status_bad_frame   (              ),
    .status_good_frame  (              ),
    .status_full        (              ),
    .status_empty       (              )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Write data queue: a DATA write that covers the low byte pushes one byte.
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic       wr_push, wr_in_ready;
  logic [7:0] wr_data;
  logic       wr_valid, wr_ready, wr_last;

  assign wr_push = write && (paddr_i == RegData) && pstrb_i[0];

  axis_fifo #(
    .DEPTH        ( FifoDepth ),
    .DATA_WIDTH   ( 8         ),
    .KEEP_ENABLE  ( 0         ),
    .LAST_ENABLE  ( 1         ),
    .ID_ENABLE    ( 0         ),
    .DEST_ENABLE  ( 0         ),
    .USER_ENABLE  ( 0         ),
    .FRAME_FIFO   ( 0         )
  ) i_write_fifo (
    .clk                ( clk_i ),
    .rst                ( rst   ),
    .s_axis_tdata       ( pwdata_i[7:0]              ),
    .s_axis_tkeep       ( 1'b0                       ),
    .s_axis_tvalid      ( wr_push                    ),
    .s_axis_tready      ( wr_in_ready                ),
    .s_axis_tlast       ( pstrb_i[1] && pwdata_i[9]  ),
    .s_axis_tid         ( 8'd0                       ),
    .s_axis_tdest       ( 8'd0                       ),
    .s_axis_tuser       ( 1'b0                       ),
    .m_axis_tdata       ( wr_data  ),
    .m_axis_tkeep       (          ),
    .m_axis_tvalid      ( wr_valid ),
    .m_axis_tready      ( wr_ready ),
    .m_axis_tlast       ( wr_last  ),
    .m_axis_tid         (          ),
    .m_axis_tdest       (          ),
    .m_axis_tuser       (          ),
    .status_overflow    (          ),
    .status_bad_frame   (          ),
    .status_good_frame  (          ),
    .status_full        (              ),
    .status_empty       (              )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Read data queue: a DATA read takes the oldest byte, if there is one.
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic [7:0] rx_data_in;
  logic       rx_valid_in, rx_ready_in, rx_last_in;
  logic [7:0] rx_data;
  logic       rx_valid, rx_last, rx_pop;

  assign rx_pop = read && (paddr_i == RegData) && rx_valid;

  axis_fifo #(
    .DEPTH        ( FifoDepth ),
    .DATA_WIDTH   ( 8         ),
    .KEEP_ENABLE  ( 0         ),
    .LAST_ENABLE  ( 1         ),
    .ID_ENABLE    ( 0         ),
    .DEST_ENABLE  ( 0         ),
    .USER_ENABLE  ( 0         ),
    .FRAME_FIFO   ( 0         )
  ) i_read_fifo (
    .clk                ( clk_i ),
    .rst                ( rst   ),
    .s_axis_tdata       ( rx_data_in  ),
    .s_axis_tkeep       ( 1'b0        ),
    .s_axis_tvalid      ( rx_valid_in ),
    .s_axis_tready      ( rx_ready_in ),
    .s_axis_tlast       ( rx_last_in  ),
    .s_axis_tid         ( 8'd0        ),
    .s_axis_tdest       ( 8'd0        ),
    .s_axis_tuser       ( 1'b0        ),
    .m_axis_tdata       ( rx_data  ),
    .m_axis_tkeep       (          ),
    .m_axis_tvalid      ( rx_valid ),
    .m_axis_tready      ( rx_pop   ),
    .m_axis_tlast       ( rx_last  ),
    .m_axis_tid         (          ),
    .m_axis_tdest       (          ),
    .m_axis_tuser       (          ),
    .status_overflow    (          ),
    .status_bad_frame   (          ),
    .status_good_frame  (          ),
    .status_full        (              ),
    .status_empty       (              )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // I2C engine
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic busy, bus_control, bus_active, missed_ack;

  i2c_master i_master (
    .clk                       ( clk_i              ),
    .rst                       ( rst                ),
    .s_axis_cmd_address        ( cmd_address        ),
    .s_axis_cmd_start          ( cmd_start          ),
    .s_axis_cmd_read           ( cmd_read           ),
    .s_axis_cmd_write          ( cmd_write          ),
    .s_axis_cmd_write_multiple ( cmd_write_multiple ),
    .s_axis_cmd_stop           ( cmd_stop           ),
    .s_axis_cmd_valid          ( cmd_valid          ),
    .s_axis_cmd_ready          ( cmd_ready          ),
    .s_axis_data_tdata         ( wr_data            ),
    .s_axis_data_tvalid        ( wr_valid           ),
    .s_axis_data_tready        ( wr_ready           ),
    .s_axis_data_tlast         ( wr_last            ),
    .m_axis_data_tdata         ( rx_data_in         ),
    .m_axis_data_tvalid        ( rx_valid_in        ),
    .m_axis_data_tready        ( rx_ready_in        ),
    .m_axis_data_tlast         ( rx_last_in         ),
    .scl_i                     ( scl_i              ),
    .scl_o                     ( scl_o              ),
    .scl_t                     ( scl_t              ),
    .sda_i                     ( sda_i              ),
    .sda_o                     ( sda_o              ),
    .sda_t                     ( sda_t              ),
    .busy                      ( busy               ),
    .bus_control               ( bus_control        ),
    .bus_active                ( bus_active         ),
    .missed_ack                ( missed_ack         ),
    .prescale                  ( prescale_q         ),
    .stop_on_idle              ( 1'b0               )
  );

  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  // Status and interrupt
  // ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
  logic [15:0] status;
  logic [3:0]  irq_status;

  assign status = {!rx_ready_in, !rx_valid, wr_ovf_q, !wr_in_ready, !wr_valid, cmd_ovf_q,
                   !cmd_in_ready, !cmd_valid, 4'b0, missed_ack_q, bus_active, bus_control, busy};
  assign irq_status = {cmd_ovf_q || wr_ovf_q, rx_valid, missed_ack_q, done_q};

  // Write-1-to-clear requests, from STATUS or IRQ_STATUS.
  logic clear_missed_ack, clear_cmd_ovf, clear_wr_ovf, clear_done;
  assign clear_missed_ack = write && pstrb_i[0] &&
                            (((paddr_i == RegStatus) && pwdata_i[3]) ||
                             ((paddr_i == RegIrqStatus) && pwdata_i[1]));
  assign clear_cmd_ovf    = write && (paddr_i == RegStatus) && pstrb_i[1] && pwdata_i[10];
  assign clear_wr_ovf     = write && (paddr_i == RegStatus) && pstrb_i[1] && pwdata_i[13];
  assign clear_done       = write && (paddr_i == RegIrqStatus) && pstrb_i[0] && pwdata_i[0];

  always_comb begin
    unique case (paddr_i)
      RegStatus:    prdata_o = {16'b0, status};
      RegCommand:   prdata_o = {19'b0, cmd_bits_q[4], cmd_bits_q[3], cmd_bits_q[2], cmd_bits_q[1],
                                cmd_bits_q[0], 1'b0, cmd_address_q};
      // The FIFO's data output is undefined while it is empty, so it is masked to 0.
      RegData:      prdata_o = rx_valid ? {22'b0, rx_last, 1'b1, rx_data} : '0;
      RegPrescale:  prdata_o = {16'b0, prescale_q};
      RegIrqEnable: prdata_o = {28'b0, irq_enable_q};
      RegIrqStatus: prdata_o = {28'b0, irq_status};
      default:      prdata_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      cmd_address_q <= '0;
      cmd_bits_q    <= '0;
      prescale_q    <= DefaultPrescale;
      missed_ack_q  <= 1'b0;
      cmd_ovf_q     <= 1'b0;
      wr_ovf_q      <= 1'b0;
      done_q        <= 1'b0;
      busy_q        <= 1'b0;
      irq_enable_q  <= '0;
      irq_o         <= 1'b0;
    end else begin
      if (write && paddr_i == RegCommand) begin
        if (pstrb_i[0]) cmd_address_q <= pwdata_i[6:0];
        if (pstrb_i[1]) cmd_bits_q    <= cmd_wr_bits;
      end
      if (write && paddr_i == RegPrescale) begin
        if (pstrb_i[0]) prescale_q[7:0]  <= pwdata_i[7:0];
        if (pstrb_i[1]) prescale_q[15:8] <= pwdata_i[15:8];
      end
      if (write && paddr_i == RegIrqEnable && pstrb_i[0]) irq_enable_q <= pwdata_i[3:0];

      // A new event wins over a clear in the same cycle, so it is never lost.
      missed_ack_q <= (missed_ack_q && !clear_missed_ack) || missed_ack;
      cmd_ovf_q    <= (cmd_ovf_q && !clear_cmd_ovf) || (cmd_push && !cmd_in_ready);
      wr_ovf_q     <= (wr_ovf_q && !clear_wr_ovf) || (wr_push && !wr_in_ready);

      busy_q <= busy;
      done_q <= (done_q && !clear_done) || (busy_q && !busy && !cmd_valid);

      irq_o <= |(irq_status & irq_enable_q);
    end
  end

endmodule
