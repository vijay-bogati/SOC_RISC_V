/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_wave_dump.sv
 Module/class Name             : adr_wave_dump
 Author                        : Vijay Bogati
 Description                   : Optional waveform dump for the Verilator bench (waves.fst in the test's results folder)
***************************************************************/

// Not in any file list: added only to a separate waves build through VERILATOR_EXTRA (see sim/README.md),
// so the normal Verilator build and its cycle counts are unchanged. Bound into tb_top, it dumps the whole
// bench to waves.fst in the test's results folder (the run's working directory). Open it with GTKWave.
module adr_wave_dump;
  initial begin
    $dumpfile("waves.fst");
    $dumpvars(0, tb_top);
  end
endmodule

bind tb_top adr_wave_dump u_adr_wave_dump();
