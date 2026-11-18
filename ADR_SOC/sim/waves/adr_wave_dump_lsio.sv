/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_wave_dump_lsio.sv
 Module/class Name             : adr_wave_dump_lsio
 Author                        : Vijay Bogati
 Description                   : Optional Verilator waveform dump of the UART, I2C and other low-speed I/O only
***************************************************************/

// Like adr_wave_dump.sv, but meant for a build with sim/waves/adr_wave_lsio.vlt, which limits tracing
// to the low-speed I/O subsystem (UART0, UART1, GPIO, SPI, QSPI, I2C, pin mux), the I2C device model
// and the bench top, so the file stays small (the whole SoC, with the Ethernet SerDes toggling every
// cycle, gives hundreds of MB). Verilator applies the scope there, not in $dumpvars.
// Added only to a separate waves build through VERILATOR_EXTRA (see sim/README.md).
module adr_wave_dump_lsio;
  initial begin
    $dumpfile("waves.fst");
    $dumpvars(0, tb_top);
  end
endmodule

bind tb_top adr_wave_dump_lsio u_adr_wave_dump_lsio();
