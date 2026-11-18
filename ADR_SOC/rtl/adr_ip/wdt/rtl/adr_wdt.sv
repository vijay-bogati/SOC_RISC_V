/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_wdt.sv
 Module/class Name             : adr_wdt
 Author                        : Vijay Bogati
 Description                   : Watchdog timer with an APB register interface
***************************************************************/

// While enabled, the counter runs down from LOAD. Each time it reaches zero it reloads
// and raises EXPIRED, which drives the interrupt. If it reaches zero again while EXPIRED
// is still set, software has stopped responding, so the watchdog requests a system reset.
//
// Registers (32-bit, word offsets):
//   0x00 CTRL    [0] enable
//   0x04 LOAD    reload value in clock cycles
//   0x08 COUNT   current count, read-only
//   0x0C KICK    write KickKey to reload the counter; other values have no effect
//   0x10 STATUS  [0] expired, write 1 to clear

module adr_wdt #(
  parameter logic [31:0] KickKey = 32'h5AFE_C0DE
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
  output logic        irq_o,
  output logic        reset_req_o
);

  logic        enable_q;
  logic        expired_q;
  logic [31:0] load_q;
  logic [31:0] count_q;
  logic        write, kick;

  assign write     = psel_i && penable_i && pwrite_i;
  assign kick      = write && (paddr_i == 5'h0C) && (pwdata_i == KickKey);
  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;
  assign irq_o     = expired_q;

  always_comb begin
    unique case (paddr_i)
      5'h00:   prdata_o = {31'b0, enable_q};
      5'h04:   prdata_o = load_q;
      5'h08:   prdata_o = count_q;
      5'h10:   prdata_o = {31'b0, expired_q};
      default: prdata_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q    <= 1'b0;
      expired_q   <= 1'b0;
      load_q      <= '1;
      count_q     <= '1;
      reset_req_o <= 1'b0;
    end else begin
      if (write && paddr_i == 5'h00) begin
        enable_q <= pwdata_i[0];
        count_q  <= load_q;  // starting or stopping always begins from a full count
      end else if (write && paddr_i == 5'h04) begin
        load_q  <= pwdata_i;
        count_q <= pwdata_i;
      end else if (kick) begin
        count_q <= load_q;
      end else if (enable_q) begin
        if (count_q == '0) begin
          count_q <= load_q;
          if (expired_q) reset_req_o <= 1'b1;
          expired_q <= 1'b1;
        end else begin
          count_q <= count_q - 32'd1;
        end
      end
      if (write && paddr_i == 5'h10 && pwdata_i[0]) expired_q <= 1'b0;
    end
  end

endmodule
