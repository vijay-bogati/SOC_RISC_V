/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_otp_ctrl.sv
 Module/class Name             : adr_otp_ctrl
 Author                        : Vijay Bogati
 Description                   : Controller for a one-time-programmable memory macro of 32 words of 32 bits
***************************************************************/

// ADR SoC - controller for a one-time-programmable memory macro of 32 words of 32 bits.
// Programming can only turn bits on, and needs the key written just before it. The macro
// itself is outside this block.
//
// Registers (32-bit):
//   0x00 ADDR    word address
//   0x04 WDATA   bits to program
//   0x08 RDATA   last word read
//   0x0C CMD     1 = read, 2 = program
//   0x10 KEY     write ProgramKey to allow one program command
//   0x14 STATUS  [0] busy, [1] done, [2] error; write 1 to clear bits 1 and 2
//   0x18 IRQ_EN  [0] interrupt when done
// An address above 31, or a program command without the key, sets error and does nothing.

module adr_otp_ctrl #(
  parameter logic [31:0] ProgramKey = 32'h4F54_5021
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [4:0]  paddr_i,
  input  logic [31:0] pwdata_i,
  output logic [31:0] prdata_o,
  output logic        pready_o,
  output logic        pslverr_o,
  output logic        macro_req_o,
  output logic        macro_we_o,
  output logic [4:0]  macro_addr_o,
  output logic [31:0] macro_wdata_o,
  input  logic [31:0] macro_rdata_i,
  input  logic        macro_done_i,
  output logic        irq_o
);

  logic [31:0] addr_q, wdata_q, rdata_q;
  logic        unlocked_q, busy_q, done_q, error_q, irq_en_q, is_read_q, requested_q;
  logic        write;

  assign write         = psel_i && penable_i && pwrite_i;
  assign pready_o      = 1'b1;
  assign pslverr_o     = 1'b0;
  assign irq_o         = done_q && irq_en_q;
  assign macro_req_o   = busy_q && !requested_q;
  assign macro_we_o    = !is_read_q;
  assign macro_addr_o  = addr_q[4:0];
  assign macro_wdata_o = wdata_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      addr_q      <= '0;
      wdata_q     <= '0;
      rdata_q     <= '0;
      unlocked_q  <= 1'b0;
      busy_q      <= 1'b0;
      done_q      <= 1'b0;
      error_q     <= 1'b0;
      irq_en_q    <= 1'b0;
      is_read_q   <= 1'b1;
      requested_q <= 1'b0;
    end else begin
      if (write) begin
        unique case (paddr_i)
          5'h00: if (!busy_q) addr_q  <= pwdata_i;
          5'h04: if (!busy_q) wdata_q <= pwdata_i;
          5'h10: unlocked_q <= (pwdata_i == ProgramKey);
          5'h18: irq_en_q   <= pwdata_i[0];
          5'h14: begin
            if (pwdata_i[1]) done_q  <= 1'b0;
            if (pwdata_i[2]) error_q <= 1'b0;
          end
          5'h0C: if (!busy_q) begin
            done_q <= 1'b0;
            unlocked_q <= 1'b0;  // the key allows only the next command
            if (addr_q > 32'd31 || pwdata_i[1:0] == 2'd0 || pwdata_i[1:0] == 2'd3 ||
                (pwdata_i[1] && !unlocked_q)) begin
              error_q <= 1'b1;
              done_q  <= 1'b1;
            end else begin
              is_read_q   <= pwdata_i[0];
              busy_q      <= 1'b1;
              requested_q <= 1'b0;
            end
          end
          default: ;
        endcase
      end

      if (macro_req_o) requested_q <= 1'b1;
      if (busy_q && requested_q && macro_done_i) begin
        if (is_read_q) rdata_q <= macro_rdata_i;
        busy_q <= 1'b0;
        done_q <= 1'b1;
      end
    end
  end

  always_comb begin
    unique case (paddr_i)
      5'h00:   prdata_o = addr_q;
      5'h04:   prdata_o = wdata_q;
      5'h08:   prdata_o = rdata_q;
      5'h14:   prdata_o = {29'b0, error_q, done_q, busy_q};
      5'h18:   prdata_o = {31'b0, irq_en_q};
      default: prdata_o = '0;
    endcase
  end

endmodule
