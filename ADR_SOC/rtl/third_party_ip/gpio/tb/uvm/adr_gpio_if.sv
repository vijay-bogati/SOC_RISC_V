/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_gpio_if.sv
 Module/class Name             : adr_gpio_if
 Author                        : Vijay Bogati
 Description                   : UVM GPIO agent interface: 16 GPIO outputs, direction bits and inputs
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). The Verilator bench does not use it.
// No clock: GPIO pins are static levels, so the monitor reacts to changes.
// out and dir come from the GPIO block; in goes to it and is driven by the bench (a loopback at SoC level).

interface adr_gpio_if ();

  logic [15:0] out;
  logic [15:0] dir;
  logic [15:0] in;
  logic [15:0] drv_in = '0;  // the driver's input levels, used where the bench has no loopback

endinterface
