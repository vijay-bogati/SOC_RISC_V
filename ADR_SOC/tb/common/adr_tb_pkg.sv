/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_tb_pkg.sv
 Module/class Name             : adr_tb_pkg
 Author                        : Vijay Bogati
 Description                   : Testbench definitions: clocks, run control, board settings and JTAG debugger constants
***************************************************************/

// Every constant used by tb_top and tb_adr_soc, in one place.
// The device models (adr_tb_spi_mem, adr_tb_i2c_dev, adr_tb_usb_host, adr_tb_otp_macro)
// keep their own constants, so each can be reused without this package.
// Delays are numbers of time units: every bench module sets timeunit 1ns and timeprecision 1ps.

package adr_tb_pkg;

  // ---- Clocks and reset ----
  localparam int unsigned ClkHalfPeriod = 5;   // system clock: 10 ns period, 100 MHz
  // Ethernet SerDes clock of the 64-bit SerDes interface. Default 2.56 ns, 390.625 MHz, the 25G
  // rate; with ADR_ETH_10G defined (make ETH_RATE=10), 6.4 ns, 156.25 MHz, the 10G rate. The RTL
  // sets Count125us from the same define. Neither half period puts an edge on a rising edge of
  // the system clock (5 ns + n x 10 ns).
`ifdef ADR_ETH_10G
  localparam realtime     EthHalfPeriod = 3.2;
`else
  localparam realtime     EthHalfPeriod = 1.28;
`endif
  // USB clock: 20.832 ns, 48.003 MHz, 4 clocks per bit (12 Mbit/s full speed, inside its 0.25%).
  // Not 10.417: with a half period of 10.416 ns no edge ever lands on a rising edge of the system
  // clock (5 ns + n x 10 ns), so the clock-domain crossings behave the same on both simulators.
  localparam realtime     UsbHalfPeriod = 10.416;
  localparam int unsigned ResetCycles   = 20;  // system clocks in reset at the start
  localparam int unsigned RtcDivBits    = 4;   // CLINT time base: system clock / 2**RtcDivBits

  // ---- Run control ----
  localparam longint      DefaultMaxCycles = 64'd20_000_000;  // timeout unless +max_cycles=<n>
  localparam int unsigned UartCyclesPerBit = 32;              // UART0 divisor 2, 16x oversampling
  localparam logic [7:0]  EndPass          = 8'h04;           // EOT, END_PASS in c_tests/adr_lib.c
  localparam logic [7:0]  EndFail          = 8'h15;           // NAK, END_FAIL in c_tests/adr_lib.c

  // ---- Board: what the testbench puts on the chip's pins ----
  localparam logic [3:0]  BootPins      = 4'hA;
  localparam logic [23:0] SpiDeviceId   = 24'hA10001;
  localparam logic [23:0] QspiDeviceId  = 24'hA10003;
  localparam logic [6:0]  I2cDeviceAddr = 7'h50;
  localparam logic [7:0]  AdcLevelCh0   = 8'h5A;  // ADC input level on channel 0
  localparam logic [7:0]  AdcLevelCh1   = 8'hC3;  // ADC input level on channel 1

  // ---- JTAG timing and polling limits ----
  localparam int unsigned TckHalfCycles     = 4;     // TCK is one eighth of the system clock
  localparam int unsigned TapResetTcks      = 6;     // TMS-high cycles to reach Test-Logic-Reset
  localparam int unsigned DmiScanBits       = 41;    // addr[7], data[32], op[2]
  localparam int unsigned DmiIdleTcks       = 16;    // lets a DMI request cross clock domains
  localparam int unsigned CmdPollLimit      = 2000;  // abstractcs and sbcs busy polls
  localparam int unsigned StatusPollLimit   = 500;   // dmstatus polls
  localparam int unsigned MailboxPollLimit  = 200;   // reads of a mailbox slot
  localparam int unsigned MailboxPollGap    = 2000;  // system clocks between those reads
  localparam int unsigned NdmResetCycles    = 50;    // system clocks ndmreset is held

  // ---- JTAG instructions (RISC-V debug transport module) ----
  localparam logic [4:0] IrIdcode = 5'h01, IrDtmcs = 5'h10, IrDmi = 5'h11;

  // ---- Values the debugger expects to read ----
  localparam logic [31:0] ExpectedIdcode = 32'h0000_0001;  // JtagIdcode in adr_soc_pkg
  localparam logic [3:0]  DtmVersion013  = 4'd1;
  localparam logic [5:0]  DmiAddrBits    = 6'd7;
  localparam logic [3:0]  DmVersion013   = 4'd2;

  // ---- Debug module registers (RISC-V Debug Specification 0.13) ----
  localparam logic [6:0] DmData0 = 7'h04, DmData1 = 7'h05, DmControl = 7'h10, DmStatus = 7'h11,
                         DmAbstractCs = 7'h16, DmCommand = 7'h17, DmProgBuf0 = 7'h20,
                         DmProgBuf1 = 7'h21, DmSbCs = 7'h38, DmSbAddr0 = 7'h39, DmSbAddr1 = 7'h3A,
                         DmSbData0 = 7'h3C, DmSbData1 = 7'h3D;
  localparam logic [31:0] CtrlActive = 32'h1, CtrlNdmReset = 32'h2, CtrlResume = 32'h4000_0000,
                          CtrlHalt = 32'h8000_0000;
  localparam logic [31:0] StatusAllHalted = 32'h1 << 9, StatusAllRunning = 32'h1 << 11,
                          StatusAllResumeAck = 32'h1 << 17;
  localparam logic [31:0] AbsBusy = 32'h1 << 12, AbsCmdErrMask = 32'h7 << 8;
  localparam logic [31:0] CmdSize64 = 32'h3 << 20, CmdPostExec = 32'h1 << 18,
                          CmdTransfer = 32'h1 << 17, CmdWrite = 32'h1 << 16;
  localparam logic [31:0] SbReadOnAddr = 32'h1 << 20, SbAccess64 = 32'h3 << 17,
                          SbBusy = 32'h1 << 21, SbErrorMask = 32'h7 << 12;

  // ---- Shared with c_tests/debug.c of both benches: change them together ----
  localparam logic [63:0] MbBase = 64'h8007_0000;
  localparam logic [63:0] MbReady = MbBase + 64'h000, MbSpin = MbBase + 64'h008,
                          MbSbaTarget = MbBase + 64'h100, MbDone = MbBase + 64'h200;
  localparam logic [63:0] ReadyValue = 64'h5245_4144, DoneValue = 64'h444F_4E45;
  localparam logic [63:0] SwWrote = 64'h1122_3344_5566_7788;    // in s11
  localparam logic [63:0] SbaPattern = 64'hDEAD_BEEF_1234_5678;
  localparam logic [63:0] ResumeValue = 64'h5A5A;               // written to s10 to end the spin

  // ---- Registers, CSRs and instructions the debugger uses ----
  localparam logic [31:0] RegS9 = 32'h1000 + 25, RegS10 = 32'h1000 + 26, RegS11 = 32'h1000 + 27,
                          CsrDpc = 32'h7B1;
  localparam logic [31:0] BadRegister = 32'h9000;          // no such register: must give cmderr
  localparam logic [63:0] S9TestValue = 64'd41;            // written to s9, then incremented
  localparam logic [31:0] InsnAddiS9  = 32'h001C_8C93;     // addi s9, s9, 1
  localparam logic [31:0] InsnEbreak  = 32'h0010_0073;

endpackage
