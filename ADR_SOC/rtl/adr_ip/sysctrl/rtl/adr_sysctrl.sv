/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_sysctrl.sv
 Module/class Name             : adr_sysctrl
 Author                        : Vijay Bogati
 Description                   : System control: identity, boot pins, reset cause, software reset, scratch memory
***************************************************************/

// ADR SoC - system control: identity, boot pins, reset cause, software reset, scratch memory.
// Runs on the power-on reset, so the reset cause and scratch registers survive system resets.
// Reset requests leave through one clocked output: a requester that the system reset clears
// would otherwise drop its request before the next clock edge could record it.
//
// Registers (32-bit):
//   0x00 CHIP_ID      read-only
//   0x04 VERSION      read-only
//   0x08 RESET_CAUSE  [0] power-on, [1] debug module, [2] watchdog, [3] software,
//                     [4] a warm reset went ahead before the DDR4 port drained (adr_rst_gen
//                     timeout); write 1 to clear
//   0x0C SOFT_RESET   write SoftResetKey to reset the system; other values have no effect
//   0x10 SCRATCH0     kept across system resets
//   0x14 SCRATCH1     kept across system resets
//   0x18 BOOT_PINS    read-only, sampled pin values
//   0x1C CLK_EN       per-peripheral clock enables, all on after any reset

module adr_sysctrl #(
  parameter logic [31:0] ChipId       = 32'h4144_5231,  // "ADR1"
  parameter logic [31:0] Version      = 32'h0001_0000,
  parameter logic [31:0] SoftResetKey = 32'h5253_5421
) (
  input  logic        clk_i,
  input  logic        por_rst_ni,
  input  logic        sys_rst_ni,
  input  logic        psel_i,
  input  logic        penable_i,
  input  logic        pwrite_i,
  input  logic [4:0]  paddr_i,
  input  logic [31:0] pwdata_i,
  output logic [31:0] prdata_o,
  output logic        pready_o,
  output logic        pslverr_o,
  input  logic [3:0]  boot_pins_i,
  input  logic        debug_reset_i,
  input  logic        wdt_reset_i,
  input  logic        ddr_drain_timeout_i,  // one clock, from adr_rst_gen
  output logic        system_reset_req_o,
  output logic [31:0] clk_en_o
);

  logic [4:0]  cause_q;
  logic [31:0] scratch_q [2];
  logic        write, soft_request;

  assign write        = psel_i && penable_i && pwrite_i;
  assign soft_request = write && (paddr_i == 5'h0C) && (pwdata_i == SoftResetKey);
  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;

  always_ff @(posedge clk_i or negedge por_rst_ni) begin
    if (!por_rst_ni) begin
      cause_q      <= 5'b00001;
      scratch_q[0] <= '0;
      scratch_q[1] <= '0;
      system_reset_req_o <= 1'b0;
    end else begin
      system_reset_req_o <= soft_request || wdt_reset_i;
      if (write && paddr_i == 5'h08) cause_q <= cause_q & ~pwdata_i[4:0];
      if (write && paddr_i == 5'h10) scratch_q[0] <= pwdata_i;
      if (write && paddr_i == 5'h14) scratch_q[1] <= pwdata_i;
      // Hardware events take priority over a clear in the same cycle.
      if (debug_reset_i) cause_q[1] <= 1'b1;
      if (wdt_reset_i)   cause_q[2] <= 1'b1;
      if (soft_request)  cause_q[3] <= 1'b1;
      if (ddr_drain_timeout_i) cause_q[4] <= 1'b1;
    end
  end

  // Clock enables follow the system reset, unlike the state above.
  always_ff @(posedge clk_i or negedge sys_rst_ni) begin
    if (!sys_rst_ni) clk_en_o <= '1;
    else if (write && paddr_i == 5'h1C) clk_en_o <= pwdata_i;
  end

  always_comb begin
    unique case (paddr_i)
      5'h00:   prdata_o = ChipId;
      5'h04:   prdata_o = Version;
      5'h08:   prdata_o = {27'b0, cause_q};
      5'h10:   prdata_o = scratch_q[0];
      5'h14:   prdata_o = scratch_q[1];
      5'h18:   prdata_o = {28'b0, boot_pins_i};
      5'h1C:   prdata_o = clk_en_o;
      default: prdata_o = '0;
    endcase
  end

endmodule
