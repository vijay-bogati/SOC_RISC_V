/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_mem_model.sv
 Module/class Name             : adr_mem_model
 Author                        : Vijay Bogati
 Description                   : Single-port synchronous memory, behavioural model for simulation
***************************************************************/

// ADR SoC - single-port synchronous memory, behavioural model for simulation.
// The image named by the plusarg is loaded at time zero (64-bit hex words).
// Replace this module with a technology macro wrapper for implementation.

module adr_mem_model #(
  parameter int unsigned NumWords = 1024,
  parameter bit          ReadOnly = 1'b0,
  parameter string       ImageArg = "",
  localparam int unsigned IdxWidth = $clog2(NumWords)
) (
  input  logic                clk_i,
  input  logic                req_i,
  input  logic                we_i,
  // Fixed 32-bit width, so every size has the same port list: synthesis keeps
  // this module as a black box and builds its ports only once. Bits above
  // IdxWidth must be zero.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [31:0]         idx_i,
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [7:0]          be_i,
  input  logic [63:0]         wdata_i,
  output logic [63:0]         rdata_o
);

  logic [63:0] mem [NumWords];
  logic [IdxWidth-1:0] idx;

  assign idx = idx_i[IdxWidth-1:0];

  always_ff @(posedge clk_i) begin
    if (req_i) begin
      if (we_i) begin
        if (!ReadOnly) begin
          for (int b = 0; b < 8; b++) begin
            if (be_i[b]) mem[idx][b*8 +: 8] <= wdata_i[b*8 +: 8];
          end
        end
      end else begin
        rdata_o <= mem[idx];
      end
    end
  end

  // verilator lint_off BLKSEQ
  initial begin
    string image;
    for (int i = 0; i < int'(NumWords); i++) mem[i] = 64'h0;
    if (ImageArg != "" && $value$plusargs({ImageArg, "=%s"}, image)) begin
      $readmemh(image, mem);
    end
  end
  // verilator lint_on BLKSEQ

endmodule
