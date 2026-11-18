/***************************************************************
 Project name                  : ADR SoC
 File Name                     : tc_sram_wrapper_syn.sv
 Module/class Name             : tc_sram_wrapper
 Author                        : Vijay Bogati
 Description                   : Synthesis-only drop-in for CVA6's tc_sram_wrapper, with plain vector ports
***************************************************************/

// Used by synthesis instead of rtl/third_party_ip/cva6/common/local/util/tc_sram_wrapper.sv,
// which simulation keeps using unchanged. Same module name, parameters and behaviour: it only
// passes everything through to tc_sram.
//
// Why: yosys-slang (Yosys 0.70+329) drops the connection of ports whose types are type
// parameters (addr_t/data_t/be_t [NumPorts-1:0]) when this wrapper passes them on to tc_sram.
// rdata_o then reads as X, and the unused memory is removed, so the CVA6 instruction and data
// caches never hit in the netlist. Declaring the ports as plain logic vectors avoids it.

module tc_sram_wrapper #(
  parameter int unsigned NumWords     = 32'd1024,
  parameter int unsigned DataWidth    = 32'd128,
  parameter int unsigned ByteWidth    = 32'd8,
  parameter int unsigned NumPorts     = 32'd2,
  parameter int unsigned Latency      = 32'd1,
  parameter              SimInit      = "none",
  parameter bit          PrintSimCfg  = 1'b0,
  // Dependent parameters, as in the original; do not override.
  parameter int unsigned AddrWidth = (NumWords > 32'd1) ? $clog2(NumWords) : 32'd1,
  parameter int unsigned BeWidth   = (DataWidth + ByteWidth - 32'd1) / ByteWidth
) (
  input  logic                                 clk_i,
  input  logic                                 rst_ni,
  input  logic [NumPorts-1:0]                  req_i,
  input  logic [NumPorts-1:0]                  we_i,
  input  logic [NumPorts-1:0][AddrWidth-1:0]   addr_i,
  input  logic [NumPorts-1:0][DataWidth-1:0]   wdata_i,
  input  logic [NumPorts-1:0][BeWidth-1:0]     be_i,
  output logic [NumPorts-1:0][DataWidth-1:0]   rdata_o
);

  tc_sram #(
    .NumWords    ( NumWords    ),
    .DataWidth   ( DataWidth   ),
    .ByteWidth   ( ByteWidth   ),
    .NumPorts    ( NumPorts    ),
    .Latency     ( Latency     ),
    .SimInit     ( SimInit     ),
    .PrintSimCfg ( PrintSimCfg )
  ) i_tc_sram (
    .clk_i   ( clk_i   ),
    .rst_ni  ( rst_ni  ),
    .req_i   ( req_i   ),
    .we_i    ( we_i    ),
    .be_i    ( be_i    ),
    .wdata_i ( wdata_i ),
    .addr_i  ( addr_i  ),
    .rdata_o ( rdata_o )
  );

endmodule
