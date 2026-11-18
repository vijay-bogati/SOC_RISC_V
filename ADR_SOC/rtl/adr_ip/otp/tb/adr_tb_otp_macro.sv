/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_tb_otp_macro.sv
 Module/class Name             : adr_tb_otp_macro
 Author                        : Vijay Bogati
 Description                   : Testbench model of a one-time-programmable memory macro, for simulation only
***************************************************************/

// ADR SoC - testbench model of a one-time-programmable memory macro, for simulation only.
// Programming only turns bits on, and contents are kept until the simulation ends.
// A read takes 8 clocks and a program takes 32.

module adr_tb_otp_macro (
  input  logic        clk_i,
  input  logic        req_i,
  input  logic        we_i,
  input  logic [4:0]  addr_i,
  input  logic [31:0] wdata_i,
  output logic [31:0] rdata_o,
  output logic        done_o
);

  logic [31:0] mem [32] = '{default: 32'h0};
  logic [5:0]  wait_q = '0;
  logic        running_q = 1'b0;
  logic        we_q = 1'b0;
  logic [4:0]  addr_q = '0;
  logic [31:0] wdata_q = '0;

  always_ff @(posedge clk_i) begin
    done_o <= 1'b0;
    if (req_i && !running_q) begin
      running_q <= 1'b1;
      we_q      <= we_i;
      addr_q    <= addr_i;
      wdata_q   <= wdata_i;
      wait_q    <= we_i ? 6'd31 : 6'd7;
    end else if (running_q) begin
      if (wait_q == '0) begin
        running_q <= 1'b0;
        done_o    <= 1'b1;
        if (we_q) mem[addr_q] <= mem[addr_q] | wdata_q;
        else      rdata_o     <= mem[addr_q];
      end else begin
        wait_q <= wait_q - 6'd1;
      end
    end
  end

endmodule
