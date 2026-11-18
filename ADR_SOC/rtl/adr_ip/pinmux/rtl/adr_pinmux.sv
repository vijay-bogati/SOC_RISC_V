/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_pinmux.sv
 Module/class Name             : adr_pinmux
 Author                        : Vijay Bogati
 Description                   : Pin mux. Each GPIO pad can carry GPIO, alternate function 1 or alternate function 2
***************************************************************/

// ADR SoC - pin mux. Each GPIO pad can carry GPIO, alternate function 1 or alternate function 2.
// Pad inputs always reach every function; only the outputs are selected.
//
// Registers (32-bit), two bits per pad: 0 = GPIO, 1 = function 1, 2 = function 2, 3 = GPIO.
//   0x00 pads 0-7   [1:0] pad 0 ... [15:14] pad 7
//   0x04 pads 8-15  [1:0] pad 8 ... [15:14] pad 15

module adr_pinmux #(
  parameter int unsigned NumPads = 16
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [2:0]  paddr_i,
  input  logic [31:0] pwdata_i,
  output logic [31:0] prdata_o,
  output logic        pready_o,
  output logic        pslverr_o,
  input  logic [NumPads-1:0] gpio_out_i,
  input  logic [NumPads-1:0] gpio_dir_i,
  input  logic [NumPads-1:0] func1_out_i,
  input  logic [NumPads-1:0] func1_dir_i,
  input  logic [NumPads-1:0] func2_out_i,
  input  logic [NumPads-1:0] func2_dir_i,
  output logic [NumPads-1:0] pad_out_o,
  output logic [NumPads-1:0] pad_dir_o
);

  logic [15:0] sel_q [2];
  logic [1:0]  sel [NumPads];

  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;
  assign prdata_o  = {16'b0, sel_q[paddr_i[2]]};

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      sel_q[0] <= '0;
      sel_q[1] <= '0;
    end else if (psel_i && penable_i && pwrite_i) begin
      sel_q[paddr_i[2]] <= pwdata_i[15:0];
    end
  end

  always_comb begin
    for (int p = 0; p < int'(NumPads); p++) begin
      sel[p] = sel_q[p / 8][2 * (p % 8) +: 2];
      unique case (sel[p])
        2'd1: begin
          pad_out_o[p] = func1_out_i[p];
          pad_dir_o[p] = func1_dir_i[p];
        end
        2'd2: begin
          pad_out_o[p] = func2_out_i[p];
          pad_dir_o[p] = func2_dir_i[p];
        end
        default: begin
          pad_out_o[p] = gpio_out_i[p];
          pad_dir_o[p] = gpio_dir_i[p];
        end
      endcase
    end
  end

endmodule
