/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_aon_timer.sv
 Module/class Name             : adr_aon_timer
 Author                        : Vijay Bogati
 Description                   : Always-on timer counting the slow clock, with a compare interrupt
***************************************************************/

// ADR SoC - always-on timer. Counts rising edges of the slow clock and raises an interrupt
// on a compare match. It runs on the power-on reset, so it keeps counting through system resets.
//
// Registers (32-bit):
//   0x00 CTRL     [0] enable
//   0x04 COUNT_LO read-only
//   0x08 COUNT_HI read-only
//   0x0C CMP_LO
//   0x10 CMP_HI
//   0x14 STATUS   [0] match, write 1 to clear

module adr_aon_timer (
  input  logic        clk_i,
  input  logic        por_rst_ni,
  input  logic        rtc_i,
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [4:0]  paddr_i,
  input  logic [31:0] pwdata_i,
  output logic [31:0] prdata_o,
  output logic        pready_o,
  output logic        pslverr_o,
  output logic        irq_o
);

  logic [2:0]  rtc_sync_q;
  logic        enable_q, match_q;
  logic [63:0] count_q, cmp_q;
  logic        write, tick;

  assign write     = psel_i && penable_i && pwrite_i;
  assign tick      = rtc_sync_q[1] && !rtc_sync_q[2];
  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;
  assign irq_o     = match_q;

  always_ff @(posedge clk_i or negedge por_rst_ni) begin
    if (!por_rst_ni) begin
      rtc_sync_q <= '0;
      enable_q   <= 1'b0;
      match_q    <= 1'b0;
      count_q    <= '0;
      cmp_q      <= '1;
    end else begin
      rtc_sync_q <= {rtc_sync_q[1:0], rtc_i};
      if (write) begin
        unique case (paddr_i)
          5'h00: enable_q <= pwdata_i[0];
          5'h0C: cmp_q[31:0]  <= pwdata_i;
          5'h10: cmp_q[63:32] <= pwdata_i;
          5'h14: if (pwdata_i[0]) match_q <= 1'b0;
          default: ;
        endcase
      end
      if (enable_q && tick) begin
        count_q <= count_q + 64'd1;
        if (count_q == cmp_q) match_q <= 1'b1;
      end
    end
  end

  always_comb begin
    unique case (paddr_i)
      5'h00:   prdata_o = {31'b0, enable_q};
      5'h04:   prdata_o = count_q[31:0];
      5'h08:   prdata_o = count_q[63:32];
      5'h0C:   prdata_o = cmp_q[31:0];
      5'h10:   prdata_o = cmp_q[63:32];
      5'h14:   prdata_o = {31'b0, match_q};
      default: prdata_o = '0;
    endcase
  end

endmodule
