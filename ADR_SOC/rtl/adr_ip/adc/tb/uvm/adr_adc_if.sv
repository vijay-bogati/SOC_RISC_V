/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_adc_if.sv
 Module/class Name             : adr_adc_if
 Author                        : Vijay Bogati
 Description                   : UVM ADC agent interface: the controller's channel and DAC code, and the analog comparator
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). The Verilator bench does not use it.
// The analog side has no clock: the comparator output follows its inputs at once. It is high
// while the selected channel's input level is at or above the controller's DAC code. The ADC
// agent sets the input levels.

interface adr_adc_if ();

  logic       channel;
  logic [7:0] dac_code;
  logic [7:0] level [2];  // analog input level of channels 0 and 1, set by the ADC agent
  logic       compare;

  assign compare = (channel ? level[1] : level[0]) >= dac_code;

endinterface
