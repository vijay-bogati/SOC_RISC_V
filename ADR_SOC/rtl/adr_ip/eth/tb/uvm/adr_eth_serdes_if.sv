/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_eth_serdes_if.sv
 Module/class Name             : adr_eth_serdes_if
 Author                        : Vijay Bogati
 Description                   : UVM Ethernet agent interface: the 10GBASE-R SerDes transmit side, one 66-bit block per clock
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). The Verilator bench does not use it.
// clk is the transmit clock; data and hdr are the scrambled 64-bit block and its 2-bit sync header.

interface adr_eth_serdes_if (
  input logic clk,
  input logic rst_n
);

  logic [63:0] tx_data;
  logic [1:0]  tx_hdr;
  logic [63:0] rx_data;   // into the chip; the bench loops tx back to rx
  logic [1:0]  rx_hdr;
  logic [63:0] drv_data;  // the driver's scrambled blocks, used when the bench has no loopback
  logic [1:0]  drv_hdr;

  clocking mon_cb @(posedge clk);
    input rst_n, tx_data, tx_hdr;
  endclocking

  // The receive side into the chip, for the receive monitor.
  clocking rx_mon_cb @(posedge clk);
    input rst_n, rx_data, rx_hdr;
  endclocking

  // The driver's outputs change just after each rising edge.
  clocking drv_cb @(posedge clk);
    output drv_data, drv_hdr;
  endclocking

endinterface
