/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_pwm_if.sv
 Module/class Name             : adr_pwm_if
 Author                        : Vijay Bogati
 Description                   : UVM PWM agent interface: 8 PWM outputs
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). The Verilator bench does not use it.
// No clock: the monitor times the outputs' edges in simulation time.

interface adr_pwm_if ();

  logic [7:0] pwm;

endinterface
