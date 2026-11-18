/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_adc_ctrl.sv
 Module/class Name             : adr_adc_ctrl
 Author                        : Vijay Bogati
 Description                   : Controller for an 8-bit successive-approximation ADC with two input channels
***************************************************************/

// ADR SoC - controller for an 8-bit successive-approximation ADC with two input channels.
// The analog part is outside this block: it compares the selected input with dac_code_o
// and reports the result on compare_i. Only the digital side is implemented here.
//
// Registers (32-bit):
//   0x00 CTRL    [0] start (write 1), [1] channel, [2] interrupt when done
//   0x04 STATUS  [0] busy, [1] done, write 1 to bit 1 to clear
//   0x08 DATA    [7:0] last result
//   0x0C DIV     clock cycles per conversion bit, minus 1. At least 2, as compare_i arrives
//                through a 2-flop synchronizer in the SoC

module adr_adc_ctrl (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [3:0]  paddr_i,
  input  logic [31:0] pwdata_i,
  output logic [31:0] prdata_o,
  output logic        pready_o,
  output logic        pslverr_o,
  output logic        channel_o,
  output logic [7:0]  dac_code_o,
  input  logic        compare_i,   // high when the input is at or above dac_code_o
  output logic        irq_o
);

  logic       busy_q, done_q, irq_en_q;
  logic [7:0] result_q, trial_bit_q, div_q, div_count_q;
  logic       write;

  assign write      = psel_i && penable_i && pwrite_i;
  assign pready_o   = 1'b1;
  assign pslverr_o  = 1'b0;
  assign irq_o      = done_q && irq_en_q;
  assign dac_code_o = busy_q ? (result_q | trial_bit_q) : result_q;

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      busy_q      <= 1'b0;
      done_q      <= 1'b0;
      irq_en_q    <= 1'b0;
      channel_o   <= 1'b0;
      result_q    <= '0;
      trial_bit_q <= '0;
      div_q       <= 8'd3;
      div_count_q <= '0;
    end else begin
      if (write && paddr_i == 4'h0) begin
        irq_en_q <= pwdata_i[2];
        if (pwdata_i[0] && !busy_q) begin
          channel_o   <= pwdata_i[1];
          busy_q      <= 1'b1;
          done_q      <= 1'b0;
          result_q    <= '0;
          trial_bit_q <= 8'h80;
          div_count_q <= div_q;
        end
      end
      if (write && paddr_i == 4'h4 && pwdata_i[1]) done_q <= 1'b0;
      if (write && paddr_i == 4'hC) div_q <= pwdata_i[7:0];

      if (busy_q) begin
        if (div_count_q != '0) begin
          div_count_q <= div_count_q - 8'd1;
        end else begin
          if (compare_i) result_q <= result_q | trial_bit_q;
          trial_bit_q <= trial_bit_q >> 1;
          div_count_q <= div_q;
          if (trial_bit_q[0]) begin
            busy_q <= 1'b0;
            done_q <= 1'b1;
          end
        end
      end
    end
  end

  always_comb begin
    unique case (paddr_i)
      4'h0:    prdata_o = {29'b0, irq_en_q, channel_o, 1'b0};
      4'h4:    prdata_o = {30'b0, done_q, busy_q};
      4'h8:    prdata_o = {24'b0, result_q};
      4'hC:    prdata_o = {24'b0, div_q};
      default: prdata_o = '0;
    endcase
  end

endmodule
