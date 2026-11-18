/***************************************************************
 Project name                  : ADR SoC
 File Name                     : tb_top.sv
 Module/class Name             : tb_top
 Author                        : Vijay Bogati
 Description                   : Simulation top: clock, reset, JTAG debugger, run end and verdict line
***************************************************************/

// Shared by Verilator and the commercial simulators (Questa, VCS, Xcelium).
// Drives clock and reset, ends the run, and prints one verdict line that the Makefile checks.
// With +jtag_test it also acts as a debugger, driving the JTAG pins through the sequence that
// the c_tests/debug.c program expects. The bench itself is tb_adr_soc, and every constant is in adr_tb_pkg.
// Only the JTAG engine process drives the pins. Verilator copies a task into every place that
// calls it, so if each debugger step ran the bit-level tasks itself, they would expand into one
// function too large for the C++ compiler to finish.

module tb_top;
  import adr_tb_pkg::*;

  timeunit 1ns;
  timeprecision 1ps;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic done, pass;
  logic jtag_tck = 1'b0, jtag_tms = 1'b0, jtag_tdi = 1'b0, jtag_trst_n = 1'b0, jtag_tdo;

  always #(ClkHalfPeriod) clk = ~clk;

  tb_adr_soc i_bench (
    .clk_i        ( clk         ),
    .rst_ni       ( rst_n       ),
    .done_o       ( done        ),
    .pass_o       ( pass        ),
    .jtag_tck_i   ( jtag_tck    ),
    .jtag_tms_i   ( jtag_tms    ),
    .jtag_trst_ni ( jtag_trst_n ),
    .jtag_tdi_i   ( jtag_tdi    ),
    .jtag_tdo_o   ( jtag_tdo    )
  );

  logic [4:0] current_ir = IrIdcode;
  int         status_errors = 0;
  int         failures = 0;

  task automatic report(input string name, input bit ok);
    $display("  %s  JTAG: %s", ok ? "PASS" : "FAIL", name);
    if (!ok) failures++;
  endtask

  // ---- JTAG pin level. TCK runs at one eighth of the system clock. ----
  task automatic tck(input logic tms, input logic tdi, output logic tdo);
    jtag_tms = tms;
    jtag_tdi = tdi;
    repeat (TckHalfCycles) @(negedge clk);
    tdo = jtag_tdo;
    jtag_tck = 1'b1;
    repeat (TckHalfCycles) @(negedge clk);
    jtag_tck = 1'b0;
  endtask

  task automatic tap_reset();
    logic unused;
    repeat (TapResetTcks) tck(1'b1, 1'b0, unused);
    tck(1'b0, 1'b0, unused);  // Run-Test/Idle
  endtask

  task automatic shift(input logic [63:0] value, input int bits, output logic [63:0] out);
    logic bit_out, unused;
    out = '0;
    for (int i = 0; i < bits; i++) begin
      tck(i == bits - 1, value[i], bit_out);
      out[i] = bit_out;
    end
    tck(1'b1, 1'b0, unused);  // Update
    tck(1'b0, 1'b0, unused);  // Run-Test/Idle
  endtask

  task automatic write_ir(input logic [4:0] ir);
    logic unused;
    logic [63:0] out;
    if (ir == current_ir) return;
    tck(1'b1, 1'b0, unused);  // to Shift-IR
    tck(1'b1, 1'b0, unused);
    tck(1'b0, 1'b0, unused);
    tck(1'b0, 1'b0, unused);
    shift(64'(ir), 5, out);
    current_ir = ir;
  endtask

  task automatic scan_dr(input logic [4:0] ir, input logic [63:0] value, input int bits,
                         output logic [63:0] out);
    logic unused;
    write_ir(ir);
    tck(1'b1, 1'b0, unused);  // to Shift-DR
    tck(1'b0, 1'b0, unused);
    tck(1'b0, 1'b0, unused);
    shift(value, bits, out);
  endtask

  // ---- JTAG engine: runs one request at a time for the debugger tasks below. ----
  logic        engine_busy = 1'b0, engine_tap_reset;
  logic [4:0]  engine_ir;
  logic [63:0] engine_value, engine_out;
  int          engine_bits, engine_idle;

  initial begin
    logic unused;
    forever begin
      wait (engine_busy);
      if (engine_tap_reset) begin
        tap_reset();
      end else begin
        scan_dr(engine_ir, engine_value, engine_bits, engine_out);
        repeat (engine_idle) tck(1'b0, 1'b0, unused);
      end
      engine_busy = 1'b0;
    end
  end

  task automatic engine_tap_reset_request();
    engine_tap_reset = 1'b1;
    engine_busy = 1'b1;
    wait (!engine_busy);
  endtask

  task automatic engine_scan(input logic [4:0] ir, input logic [63:0] value, input int bits,
                             input int idle, output logic [63:0] out);
    engine_tap_reset = 1'b0;
    engine_ir = ir;
    engine_value = value;
    engine_bits = bits;
    engine_idle = idle;
    engine_busy = 1'b1;
    wait (!engine_busy);
    out = engine_out;
  endtask

  // ---- Debug module access: 41-bit scans of addr[7], data[32], op[2]. ----
  task automatic dmi_scan(input logic [6:0] addr, input logic [31:0] data, input logic [1:0] op,
                          output logic [63:0] out);
    // The 16 idle clocks let the request cross clock domains.
    engine_scan(IrDmi, 64'({addr, data, op}), DmiScanBits, DmiIdleTcks, out);
  endtask

  task automatic dmi_read(input logic [6:0] addr, output logic [31:0] data);
    logic [63:0] out;
    dmi_scan(addr, 32'd0, 2'd1, out);
    dmi_scan(7'd0, 32'd0, 2'd0, out);
    if (out[1:0] !== 2'b00) status_errors++;
    data = out[33:2];
  endtask

  task automatic dmi_write(input logic [6:0] addr, input logic [31:0] data);
    logic [63:0] out;
    dmi_scan(addr, data, 2'd2, out);
    dmi_scan(7'd0, 32'd0, 2'd0, out);
    if (out[1:0] !== 2'b00) status_errors++;
  endtask

  // ---- Abstract commands ----
  task automatic abstract_cmd(input logic [31:0] command, output bit ok);
    logic [31:0] cs;
    ok = 1'b0;
    dmi_write(DmCommand, command);
    for (int i = 0; i < CmdPollLimit && done !== 1'b1; i++) begin
      dmi_read(DmAbstractCs, cs);
      if ((cs & AbsBusy) === 32'd0) begin
        ok = (cs & AbsCmdErrMask) === 32'd0;
        return;
      end
    end
  endtask

  task automatic read_reg(input logic [31:0] register, output bit ok, output logic [63:0] value);
    logic [31:0] low, high;
    value = '0;
    abstract_cmd(CmdSize64 | CmdTransfer | register, ok);
    if (!ok) return;
    dmi_read(DmData1, high);
    dmi_read(DmData0, low);
    value = {high, low};
  endtask

  task automatic write_reg(input logic [31:0] register, input logic [63:0] value, output bit ok);
    dmi_write(DmData0, value[31:0]);
    dmi_write(DmData1, value[63:32]);
    abstract_cmd(CmdSize64 | CmdTransfer | CmdWrite | register, ok);
  endtask

  // ---- System bus access ----
  task automatic sb_wait(output bit ok);
    logic [31:0] cs;
    ok = 1'b0;
    for (int i = 0; i < CmdPollLimit && done !== 1'b1; i++) begin
      dmi_read(DmSbCs, cs);
      if ((cs & SbBusy) === 32'd0) begin
        ok = (cs & SbErrorMask) === 32'd0;
        return;
      end
    end
  endtask

  task automatic sb_read(input logic [63:0] addr, output bit ok, output logic [63:0] value);
    logic [31:0] low, high;
    value = '0;
    dmi_write(DmSbCs, SbReadOnAddr | SbAccess64);
    dmi_write(DmSbAddr1, addr[63:32]);
    dmi_write(DmSbAddr0, addr[31:0]);
    sb_wait(ok);
    if (!ok) return;
    dmi_read(DmSbData0, low);
    dmi_read(DmSbData1, high);
    value = {high, low};
  endtask

  task automatic sb_write(input logic [63:0] addr, input logic [63:0] value, output bit ok);
    dmi_write(DmSbCs, SbAccess64);
    dmi_write(DmSbAddr1, addr[63:32]);
    dmi_write(DmSbAddr0, addr[31:0]);
    dmi_write(DmSbData1, value[63:32]);
    dmi_write(DmSbData0, value[31:0]);
    sb_wait(ok);
  endtask

  task automatic sb_poll(input logic [63:0] addr, input logic [63:0] want, output bit ok);
    logic [63:0] value;
    bit read_ok;
    ok = 1'b0;
    for (int i = 0; i < MailboxPollLimit && done !== 1'b1; i++) begin
      sb_read(addr, read_ok, value);
      if (!read_ok) return;
      if (value === want) begin
        ok = 1'b1;
        return;
      end
      repeat (MailboxPollGap) @(negedge clk);
    end
  endtask

  task automatic dm_wait(input logic [31:0] status_bit, output bit ok);
    logic [31:0] status;
    ok = 1'b0;
    for (int i = 0; i < StatusPollLimit && done !== 1'b1; i++) begin
      dmi_read(DmStatus, status);
      if ((status & status_bit) === status_bit) begin
        ok = 1'b1;
        return;
      end
    end
  endtask

  // ---- The sequence that c_tests/debug.c expects ----
  task automatic debugger_sequence();
    logic [63:0] out, value, spin_addr;
    logic [31:0] data;
    bit ok, ok2;

    engine_tap_reset_request();

    // After reset the TAP selects IDCODE, and bit 0 of an IDCODE is always 1.
    engine_scan(IrIdcode, 64'd0, 32, 0, out);
    report("IDCODE reads the configured value", out[31:0] === ExpectedIdcode);

    engine_scan(IrDtmcs, 64'd0, 32, 0, out);
    report("DTM version is 0.13", out[3:0] === DtmVersion013);
    report("DMI address is 7 bits", out[9:4] === DmiAddrBits);

    dmi_write(DmControl, CtrlActive);
    dmi_read(DmStatus, data);
    report("debug module is version 0.13", data[3:0] === DmVersion013);
    dmi_read(DmControl, data);
    report("debug module active reads back", (data & CtrlActive) === CtrlActive);

    // System bus access works while the CPU is running.
    sb_poll(MbReady, ReadyValue, ok);
    report("system bus reads a value the CPU wrote", ok);
    if (!ok) return;
    dmi_read(DmStatus, data);
    report("CPU is running before halt", (data & StatusAllRunning) === StatusAllRunning);

    sb_read(MbSpin, ok, spin_addr);
    report("system bus reads the spin address", ok);
    sb_write(MbSbaTarget, SbaPattern, ok);
    report("system bus write completes", ok);
    sb_read(MbSbaTarget, ok, value);
    report("system bus write reads back", ok && value === SbaPattern);

    // Halt.
    dmi_write(DmControl, CtrlActive | CtrlHalt);
    dm_wait(StatusAllHalted, ok);
    report("CPU halts on request", ok);
    dmi_write(DmControl, CtrlActive);
    if (!ok) return;

    // Registers and CSRs.
    read_reg(RegS11, ok, value);
    report("abstract command reads a register", ok && value === SwWrote);
    read_reg(CsrDpc, ok, value);
    report("dpc points at the spin loop", ok && value >= spin_addr && value <= spin_addr + 64'd8);
    write_reg(RegS9, S9TestValue, ok);
    report("abstract command writes a register", ok);
    read_reg(RegS9, ok, value);
    report("written register reads back", ok && value === S9TestValue);

    // Program buffer: run one instruction on the halted CPU.
    dmi_write(DmProgBuf0, InsnAddiS9);
    dmi_write(DmProgBuf1, InsnEbreak);
    abstract_cmd(CmdSize64 | CmdPostExec, ok);
    report("program buffer runs", ok);
    read_reg(RegS9, ok, value);
    report("program buffer changed the register", ok && value === S9TestValue + 64'd1);

    // A bad register number must report an error and then be clearable.
    dmi_write(DmCommand, CmdSize64 | CmdTransfer | BadRegister);
    for (int i = 0; i < CmdPollLimit; i++) begin
      dmi_read(DmAbstractCs, data);
      if ((data & AbsBusy) === 32'd0) break;
    end
    dmi_read(DmAbstractCs, data);
    report("bad abstract command reports cmderr", (data & AbsCmdErrMask) !== 32'd0);
    dmi_write(DmAbstractCs, AbsCmdErrMask);
    dmi_read(DmAbstractCs, data);
    report("cmderr clears", (data & AbsCmdErrMask) === 32'd0);

    // Resume: the new s10 value releases the program from its spin loop.
    write_reg(RegS10, ResumeValue, ok);
    report("register write for resume", ok);
    dmi_write(DmControl, CtrlActive | CtrlResume);
    dm_wait(StatusAllResumeAck, ok);
    report("CPU acknowledges resume", ok);
    dmi_write(DmControl, CtrlActive);
    dm_wait(StatusAllRunning, ok2);
    report("CPU is running after resume", ok2);

    // Reset the rest of the SoC. The program reports the second boot itself.
    sb_poll(MbDone, DoneValue, ok);
    report("program finishes first boot", ok);
    dmi_write(DmControl, CtrlActive | CtrlNdmReset);
    repeat (NdmResetCycles) @(negedge clk);
    dmi_write(DmControl, CtrlActive);
    dmi_read(DmControl, data);
    report("debug link survives the SoC reset", (data & CtrlActive) === CtrlActive);

    report("no DMI scan reported an error", status_errors == 0);
  endtask

  initial begin
    bit jtag_test;
    jtag_test = $test$plusargs("jtag_test");

    repeat (ResetCycles) @(negedge clk);
    rst_n = 1'b1;
    jtag_trst_n = 1'b1;

    if (jtag_test) begin
      debugger_sequence();
      if (done === 1'b1) report("debugger sequence ended before the program did", 1'b0);
      $display("[JTAG] %0d failed", failures);
    end

    wait (done === 1'b1);
    // The Makefile looks for this exact line, so a crash or a hang can never count as a pass.
    if (pass === 1'b1 && failures == 0) $display("[TOP] VERDICT: PASS");
    else                                $display("[TOP] VERDICT: FAIL");
    $finish;
  end

endmodule
