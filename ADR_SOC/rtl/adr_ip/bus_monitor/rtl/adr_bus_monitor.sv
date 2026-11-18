/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_bus_monitor.sv
 Module/class Name             : adr_bus_monitor
 Author                        : Vijay Bogati
 Description                   : Bus error monitor
***************************************************************/

// ADR SoC - bus error monitor.
// The CPU does not trap on AXI error responses, so this block records them and can raise
// an interrupt. It watches the read and write responses at every crossbar initiator port.
//
// The address is the most recent one issued on that channel by the initiator that got the
// error. With several transfers outstanding it may belong to a neighbouring transfer.
//
// Registers (32-bit):
//   0x00 STATUS    [3:0] read error per initiator, [7:4] write error per initiator; write 1 to clear
//   0x04 ADDR_LO   address of the first error since STATUS was last all clear
//   0x08 ADDR_HI
//   0x0C IRQ_EN    [0] interrupt while any STATUS bit is set

module adr_bus_monitor #(
  parameter int unsigned NumInitiators = 4
) (
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
  // One bit per initiator, high for the cycle an error response is accepted
  input  logic [NumInitiators-1:0]       read_error_i,
  input  logic [NumInitiators-1:0]       write_error_i,
  input  logic [NumInitiators-1:0][63:0] last_read_addr_i,
  input  logic [NumInitiators-1:0][63:0] last_write_addr_i,
  output logic        irq_o
);

  logic [NumInitiators-1:0] read_status_q, write_status_q;
  logic [63:0]              addr_q;
  logic                     irq_en_q;
  logic                     write, any_set, any_new;
  logic [63:0]              new_addr;

  assign write     = psel_i && penable_i && pwrite_i;
  assign pready_o  = 1'b1;
  assign pslverr_o = 1'b0;
  assign any_set   = (|read_status_q) || (|write_status_q);
  assign any_new   = (|read_error_i) || (|write_error_i);
  assign irq_o     = any_set && irq_en_q;

  // The lowest-numbered initiator wins if two report errors in the same cycle.
  always_comb begin
    new_addr = '0;
    for (int i = int'(NumInitiators) - 1; i >= 0; i--) begin
      if (write_error_i[i]) new_addr = last_write_addr_i[i];
      if (read_error_i[i])  new_addr = last_read_addr_i[i];
    end
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      read_status_q  <= '0;
      write_status_q <= '0;
      addr_q         <= '0;
      irq_en_q       <= 1'b0;
    end else begin
      if (any_new && !any_set) addr_q <= new_addr;
      read_status_q  <= read_status_q | read_error_i;
      write_status_q <= write_status_q | write_error_i;
      if (write && paddr_i == 4'h0) begin
        read_status_q  <= (read_status_q & ~pwdata_i[NumInitiators-1:0]) | read_error_i;
        write_status_q <= (write_status_q & ~pwdata_i[4+:NumInitiators]) | write_error_i;
      end
      if (write && paddr_i == 4'hC) irq_en_q <= pwdata_i[0];
    end
  end

  always_comb begin
    unique case (paddr_i)
      4'h0:    prdata_o = (32'(write_status_q) << 4) | 32'(read_status_q);
      4'h4:    prdata_o = addr_q[31:0];
      4'h8:    prdata_o = addr_q[63:32];
      4'hC:    prdata_o = {31'b0, irq_en_q};
      default: prdata_o = '0;
    endcase
  end

endmodule
