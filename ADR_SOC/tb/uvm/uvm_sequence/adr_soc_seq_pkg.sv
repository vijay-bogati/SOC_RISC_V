/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_soc_seq_pkg.sv
 Module/class Name             : adr_soc_seq_pkg, adr_soc_debug_seq, adr_soc_sba_seq, adr_soc_usb_host_seq
 Author                        : Vijay Bogati
 Description                   : UVM SoC test sequences: one sequence per test that needs the testbench to act
***************************************************************/

// UVM bench only (a simulator with UVM 1.2). Each sequence runs alongside a C program and plays the testbench's part.
//
// adr_soc_debug_seq (test 'debug', with tb/uvm/c_tests/debug.c): the external debugger on the JTAG agent.
// It makes exactly the same JTAG scans, in the same order and with the same timing, as the
// Verilator bench's debugger in tb_top, so the debug test takes the same number of cycles on
// both benches. Steps: TAP and DTM identity, debug module on, system bus access while the CPU
// runs, halt, register and CSR access, program buffer, a bad command and its error, resume,
// then a reset of the SoC through the debug module. The program checks its side and reports.
//
// adr_soc_sba_seq (test 'sba', with tb/uvm/c_tests/sba.c; UVM bench only, no Verilator twin): the
// debugger's system bus access by size and its errors (ADR_TEST_PLAN NEG-11 to NEG-16). The debug
// module is the backported riscv-dbg (docs/THIRD_PARTY.md) and adr_debug turns AXI DECERR into
// sberror 2 and SLVERR into sberror 7. Steps: sbcs after the debug module is switched on;
// 8/16/32/64-bit writes and reads in SRAM; misaligned and 128-bit accesses (sberror 3 and 4, no
// bus access); no new access while sberror is set; DECERR from the crossbar and from an empty
// peripheral slot (2); 32-bit accesses to two PWM registers sharing a 64-bit word, the neighbour
// unchanged; SLVERR from the PWM with its clock gated (7). Each error is then cleared by writing 1s.
//
// adr_soc_usb_host_seq (every test, from the base test's usb_host(); used by tb/uvm/c_tests/usb.c):
// the USB host on the USB agent. When the device connects: bus reset, SOF, SETUP with 8 bytes,
// OUT with 4 bytes to endpoint 1, then IN tokens to endpoint 1 until the device returns the 8
// expected bytes, which it ACKs. The steps and gaps are those of the Verilator bench's host model
// (adr_tb_usb_host), so the usb test takes the same number of cycles on both benches. The program
// learns the result from the device's status, so this sequence reports but does not fail a test.

package adr_soc_seq_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import adr_riscv_dbg_pkg::*;
  import adr_usb_agent_pkg::*;

  // Chip and test values, shared with tb_top and debug.c. Imported by name because
  // adr_tb_pkg also has its own copy of the debug spec values in adr_riscv_dbg_pkg.
  import adr_tb_pkg::ExpectedIdcode, adr_tb_pkg::DmiAddrBits, adr_tb_pkg::DmiIdleTcks,
         adr_tb_pkg::CmdPollLimit, adr_tb_pkg::StatusPollLimit, adr_tb_pkg::MailboxPollLimit,
         adr_tb_pkg::MailboxPollGap, adr_tb_pkg::NdmResetCycles;
  import adr_tb_pkg::MbReady, adr_tb_pkg::MbSpin, adr_tb_pkg::MbSbaTarget, adr_tb_pkg::MbDone,
         adr_tb_pkg::ReadyValue, adr_tb_pkg::DoneValue, adr_tb_pkg::SwWrote,
         adr_tb_pkg::SbaPattern, adr_tb_pkg::ResumeValue;
  import adr_tb_pkg::RegS9, adr_tb_pkg::RegS10, adr_tb_pkg::RegS11, adr_tb_pkg::BadRegister,
         adr_tb_pkg::S9TestValue, adr_tb_pkg::InsnAddiS9;

  class adr_soc_debug_seq extends adr_riscv_dbg_base_seq;
    `uvm_object_utils(adr_soc_debug_seq)

    int unsigned failures;

    function new(string name = "adr_soc_debug_seq");
      super.new(name);
      dmi_abits         = DmiAddrBits;
      dmi_idle_tcks     = DmiIdleTcks;
      cmd_poll_limit    = CmdPollLimit;
      status_poll_limit = StatusPollLimit;
    endfunction

    // Same line format as tb_top, so the logs of the two benches can be compared.
    function void report(string name, bit ok);
      $display("  %s  JTAG: %s", ok ? "PASS" : "FAIL", name);
      if (!ok) begin
        failures++;
        `uvm_error("JTAG", name)
      end
    endfunction

    task body();
      logic [63:0] out, value, spin_addr;
      logic [31:0] data;
      bit ok;

      tap_reset();

      // ---- TAP and debug transport module ----
      scan(IrIdcode, 64'd0, 32, 0, out);  // IDCODE is selected after reset anyway
      report("IDCODE reads the configured value", out[31:0] === ExpectedIdcode);
      scan(IrDtmcs, 64'd0, 32, 0, out);
      report("DTM version is 0.13", out[3:0] === DtmVersion013);
      report("DMI address is 7 bits", out[9:4] === DmiAddrBits);

      // ---- Debug module on ----
      dmi_write(DmControl, CtrlActive);
      dmi_read(DmStatus, data);
      report("debug module is version 0.13", data[3:0] === DmVersion013);
      dmi_read(DmControl, data);
      report("debug module active reads back", (data & CtrlActive) === CtrlActive);

      // ---- System bus access while the CPU runs ----
      sb_poll(MbReady, ReadyValue, MailboxPollLimit, MailboxPollGap, ok);
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

      // ---- Halt ----
      dmi_write(DmControl, CtrlActive | CtrlHalt);
      dm_wait(StatusAllHalted, ok);
      report("CPU halts on request", ok);
      dmi_write(DmControl, CtrlActive);
      if (!ok) return;

      // ---- Registers and CSRs ----
      read_reg(RegS11, ok, value);
      report("abstract command reads a register", ok && value === SwWrote);
      read_reg(CsrDpc, ok, value);
      report("dpc points at the spin loop", ok && value >= spin_addr && value <= spin_addr + 64'd8);
      write_reg(RegS9, S9TestValue, ok);
      report("abstract command writes a register", ok);
      read_reg(RegS9, ok, value);
      report("written register reads back", ok && value === S9TestValue);

      // ---- Program buffer: run one instruction on the halted CPU ----
      dmi_write(DmProgBuf0, InsnAddiS9);
      dmi_write(DmProgBuf1, InsnEbreak);
      abstract_cmd(CmdSize64 | CmdPostExec, ok);
      report("program buffer runs", ok);
      read_reg(RegS9, ok, value);
      report("program buffer changed the register", ok && value === S9TestValue + 64'd1);

      // ---- A bad register number must report an error, which can then be cleared ----
      abstract_cmd(CmdSize64 | CmdTransfer | BadRegister, ok);
      dmi_read(DmAbstractCs, data);
      report("bad abstract command reports cmderr", (data & AbsCmdErrMask) !== 32'd0);
      dmi_write(DmAbstractCs, AbsCmdErrMask);
      dmi_read(DmAbstractCs, data);
      report("cmderr clears", (data & AbsCmdErrMask) === 32'd0);

      // ---- Resume: the new s10 value releases the program from its spin loop ----
      write_reg(RegS10, ResumeValue, ok);
      report("register write for resume", ok);
      dmi_write(DmControl, CtrlActive | CtrlResume);
      dm_wait(StatusAllResumeAck, ok);
      report("CPU acknowledges resume", ok);
      dmi_write(DmControl, CtrlActive);
      dm_wait(StatusAllRunning, ok);
      report("CPU is running after resume", ok);

      // ---- Reset the rest of the SoC; the program reports its second boot itself ----
      sb_poll(MbDone, DoneValue, MailboxPollLimit, MailboxPollGap, ok);
      report("program finishes first boot", ok);
      dmi_write(DmControl, CtrlActive | CtrlNdmReset);
      wait_clocks(NdmResetCycles);
      dmi_write(DmControl, CtrlActive);
      dmi_read(DmControl, data);
      report("debug link survives the SoC reset", (data & CtrlActive) === CtrlActive);

      report("no DMI scan reported an error", dmi_errors == 0);
    endtask
  endclass

  class adr_soc_sba_seq extends adr_riscv_dbg_base_seq;
    `uvm_object_utils(adr_soc_sba_seq)

    // Shared with sba.c.
    localparam logic [63:0] SramWord   = 64'h8007_0400;         // MbBase + 0x400, not used by the program
    localparam logic [63:0] Pattern    = 64'h0011_2233_4455_6677;
    localparam logic [63:0] SbaResult  = 64'hCAFE_F00D_BEEF_A577;
    localparam logic [63:0] NoTarget   = 64'h4000_0000;         // hits no crossbar rule: DECERR
    localparam logic [63:0] EmptySlot  = 64'h1000_5000;         // free peripheral slot: DECERR
    localparam logic [63:0] PwmCh1Th   = 64'h1000_9010;         // PWM timer 0 channel 1 threshold
    localparam logic [63:0] PwmCh2Th   = 64'h1000_9014;         // its neighbour in the same 64-bit word
    localparam logic [63:0] ClkEn      = 64'h1000_D01C;         // system control CLK_EN
    localparam logic [31:0] ClkPwm     = 32'h1 << 6;
    localparam logic [31:0] Ch1Value   = 32'h1234, Ch2First = 32'h5678, Ch2Value = 32'h0ABC;

    // sbcs fields (RISC-V Debug Specification 0.13.2, section 3.12.18)
    localparam logic [2:0] Size8 = 3'd0, Size16 = 3'd1, Size32 = 3'd2, Size64 = 3'd3, Size128 = 3'd4;
    localparam logic [2:0] ErrNone = 3'd0, ErrBadAddr = 3'd2, ErrAlign = 3'd3, ErrSize = 3'd4, ErrOther = 3'd7;

    int unsigned failures;

    function new(string name = "adr_soc_sba_seq");
      super.new(name);
      dmi_abits         = DmiAddrBits;
      dmi_idle_tcks     = DmiIdleTcks;
      cmd_poll_limit    = CmdPollLimit;
      status_poll_limit = StatusPollLimit;
    endfunction

    function void report(string name, bit ok);
      $display("  %s  JTAG: %s", ok ? "PASS" : "FAIL", name);
      if (!ok) begin
        failures++;
        `uvm_error("JTAG", name)
      end
    endfunction

    static function logic [2:0] sberror(logic [31:0] cs);
      return cs[14:12];
    endfunction

    // Wait until sbbusy is 0; cs is the last sbcs read.
    task sba_idle(output logic [31:0] cs);
      for (int unsigned i = 0; i < cmd_poll_limit; i++) begin
        dmi_read(DmSbCs, cs);
        if ((cs & SbBusy) === 32'd0) return;
      end
      report("system bus access finishes (sbbusy clears)", 1'b0);
    endtask

    // One read of 1 << size bytes; value holds them in its low bits, the rest is 0.
    task sba_read(input logic [2:0] size, input logic [63:0] addr, output logic [31:0] cs,
                  output logic [63:0] value);
      logic [31:0] low, high;
      dmi_write(DmSbCs, SbReadOnAddr | (32'(size) << 17));
      dmi_write(DmSbAddr1, addr[63:32]);
      dmi_write(DmSbAddr0, addr[31:0]);
      sba_idle(cs);
      dmi_read(DmSbData0, low);
      high = 32'd0;
      if (size == Size64) dmi_read(DmSbData1, high);
      value = {high, low};
      if (size < Size64) value &= (64'd1 << (8 << size)) - 64'd1;
    endtask

    // One write of 1 << size bytes from the low bits of value. Writing sbdata0 starts it.
    task sba_write(input logic [2:0] size, input logic [63:0] addr, input logic [63:0] value,
                   output logic [31:0] cs);
      dmi_write(DmSbCs, 32'(size) << 17);
      dmi_write(DmSbAddr1, addr[63:32]);
      dmi_write(DmSbAddr0, addr[31:0]);
      if (size == Size64) dmi_write(DmSbData1, value[63:32]);
      dmi_write(DmSbData0, value[31:0]);
      sba_idle(cs);
    endtask

    // sberror is write-1-to-clear.
    task sba_clear(string what);
      logic [31:0] cs;
      dmi_write(DmSbCs, SbErrorMask);
      dmi_read(DmSbCs, cs);
      report({what, ": sberror clears by writing 1s"}, sberror(cs) === ErrNone);
    endtask

    task body();
      logic [31:0] cs, clk_en;
      logic [63:0] value;

      // ---- sbcs after the debug module is switched on ----
      dmi_write(DmControl, CtrlActive);
      dmi_read(DmSbCs, cs);
      report("sbversion is 1", cs[31:29] === 3'd1);
      report("sbaccess resets to 2 (32-bit)", cs[19:17] === Size32);
      report("sbasize is 64", cs[11:5] === 7'd64);
      report("sbaccess8/16/32/64 supported, 128 not", cs[4:0] === 5'b01111);
      report("no sberror, not busy", sberror(cs) === ErrNone && (cs & SbBusy) === 32'd0);

      // ---- Sizes in SRAM: a 64-bit pattern, then 32, 16 and 8-bit writes over parts of it ----
      sba_write(Size64, SramWord, Pattern, cs);
      report("64-bit write completes", sberror(cs) === ErrNone);
      sba_read(Size64, SramWord, cs, value);
      report("64-bit read returns it", sberror(cs) === ErrNone && value === Pattern);
      sba_write(Size32, SramWord + 64'd4, 64'hCAFE_F00D, cs);
      sba_read(Size64, SramWord, cs, value);
      report("32-bit write changes only bytes 7:4", sberror(cs) === ErrNone && value === 64'hCAFE_F00D_4455_6677);
      sba_write(Size16, SramWord + 64'd2, 64'hBEEF, cs);
      sba_read(Size64, SramWord, cs, value);
      report("16-bit write changes only bytes 3:2", sberror(cs) === ErrNone && value === 64'hCAFE_F00D_BEEF_6677);
      sba_write(Size8, SramWord + 64'd1, 64'hA5, cs);
      sba_read(Size64, SramWord, cs, value);
      report("8-bit write changes only byte 1", sberror(cs) === ErrNone && value === SbaResult);
      sba_read(Size8, SramWord + 64'd1, cs, value);
      report("8-bit read returns byte 1", sberror(cs) === ErrNone && value === 64'hA5);
      sba_read(Size16, SramWord + 64'd2, cs, value);
      report("16-bit read returns bytes 3:2", sberror(cs) === ErrNone && value === 64'hBEEF);
      sba_read(Size32, SramWord + 64'd4, cs, value);
      report("32-bit read returns bytes 7:4", sberror(cs) === ErrNone && value === 64'hCAFE_F00D);

      // ---- Misaligned: sberror 3, and no bus access ----
      sba_write(Size32, SramWord + 64'd2, 64'h1234_5678, cs);
      report("misaligned 32-bit write gives sberror 3", sberror(cs) === ErrAlign);
      // While sberror is set no new access starts: this aligned write must be dropped too.
      sba_write(Size64, SramWord, 64'h0, cs);
      report("no access while sberror is set (it stays 3)", sberror(cs) === ErrAlign);
      sba_clear("alignment error");
      sba_read(Size64, SramWord, cs, value);
      report("SRAM unchanged by the misaligned and the blocked write", sberror(cs) === ErrNone && value === SbaResult);
      sba_read(Size16, SramWord + 64'd1, cs, value);
      report("misaligned 16-bit read gives sberror 3", sberror(cs) === ErrAlign);
      sba_clear("alignment error on a read");
      sba_write(Size64, SramWord + 64'd4, 64'h0, cs);
      report("misaligned 64-bit write gives sberror 3", sberror(cs) === ErrAlign);
      sba_clear("alignment error on a 64-bit write");

      // ---- Unsupported size: sberror 4 ----
      sba_read(Size128, SramWord, cs, value);
      report("128-bit read gives sberror 4", sberror(cs) === ErrSize);
      sba_clear("size error");

      // ---- No target: DECERR becomes sberror 2 ----
      sba_read(Size64, NoTarget, cs, value);
      report("read with no crossbar target gives sberror 2", sberror(cs) === ErrBadAddr);
      sba_clear("bad address on a read");
      sba_write(Size64, NoTarget, Pattern, cs);
      report("write with no crossbar target gives sberror 2", sberror(cs) === ErrBadAddr);
      sba_clear("bad address on a write");
      sba_read(Size32, EmptySlot, cs, value);
      report("read of an empty peripheral slot gives sberror 2", sberror(cs) === ErrBadAddr);
      sba_clear("bad address in the peripheral window");

      // ---- 32-bit accesses to APB registers that share a 64-bit word ----
      sba_write(Size32, PwmCh1Th, 64'(Ch1Value), cs);
      report("32-bit write to PWM CH1_TH completes", sberror(cs) === ErrNone);
      sba_write(Size32, PwmCh2Th, 64'(Ch2First), cs);
      report("32-bit write to PWM CH2_TH completes", sberror(cs) === ErrNone);
      sba_read(Size32, PwmCh1Th, cs, value);
      report("CH1_TH reads back", sberror(cs) === ErrNone && value === 64'(Ch1Value));
      sba_read(Size32, PwmCh2Th, cs, value);
      report("CH2_TH reads back", sberror(cs) === ErrNone && value === 64'(Ch2First));
      sba_write(Size32, PwmCh2Th, 64'(Ch2Value), cs);
      sba_read(Size32, PwmCh1Th, cs, value);
      report("32-bit write to CH2_TH leaves CH1_TH unchanged", sberror(cs) === ErrNone && value === 64'(Ch1Value));
      sba_read(Size64, PwmCh1Th, cs, value);
      report("64-bit read returns both registers", sberror(cs) === ErrNone && value === {32'(Ch2Value), 32'(Ch1Value)});

      // ---- Gated peripheral: SLVERR becomes sberror 7 ----
      sba_read(Size32, ClkEn, cs, value);
      clk_en = value[31:0];
      report("CLK_EN reads with the PWM clock on", sberror(cs) === ErrNone && (clk_en & ClkPwm) !== 32'd0);
      sba_write(Size32, ClkEn, 64'(clk_en & ~ClkPwm), cs);
      report("32-bit write gates the PWM clock", sberror(cs) === ErrNone);
      sba_read(Size32, PwmCh1Th, cs, value);
      report("read of the gated PWM gives sberror 7", sberror(cs) === ErrOther);
      sba_clear("other error on a read");
      sba_write(Size32, PwmCh1Th, 64'h0, cs);
      report("write to the gated PWM gives sberror 7", sberror(cs) === ErrOther);
      sba_clear("other error on a write");
      sba_write(Size32, ClkEn, 64'(clk_en), cs);
      report("CLK_EN restored", sberror(cs) === ErrNone);
      sba_read(Size32, PwmCh1Th, cs, value);
      report("PWM answers again and kept CH1_TH", sberror(cs) === ErrNone && value === 64'(Ch1Value));

      report("no DMI scan reported an error", dmi_errors == 0);
    endtask
  endclass

  class adr_soc_usb_host_seq extends adr_usb_host_base_seq;
    `uvm_object_utils(adr_soc_usb_host_seq)

    // Transfer contents, the same as usb.c and the Verilator bench's host model.
    logic [10:0] sof_frame   = 11'h123;
    byte         setup_first = 8'h40, out_first = 8'h60, in_first = 8'h10;
    int unsigned setup_len   = 8,     out_len   = 4,     in_len   = 8;
    int unsigned in_attempts = 2000;
    bit          in_received;

    function new(string name = "adr_soc_usb_host_seq");
      super.new(name);
    endfunction

    static function void count_up(output logic [7:0] bytes [$], input byte first, input int unsigned len);
      bytes.delete();
      for (int i = 0; i < len; i++) bytes.push_back(8'(first + i));
    endfunction

    task body();
      logic [7:0] bytes [$], expected [$], rx [$];

      wait_connect();
      idle(200);
      bus_reset(60);   // SE0 for 5 us at 12 bits per us
      idle(200);
      sof(sof_frame);
      idle(100);

      token(PidSetup, 7'd0, 4'd0);
      idle(4);
      count_up(bytes, setup_first, setup_len);
      data(PidData0, bytes);
      receive(rx);
      `uvm_info("USB_HOST", $sformatf("SETUP answered with %0d bytes", rx.size()), UVM_MEDIUM)
      idle(100);

      token(PidOut, 7'd0, 4'd1);
      idle(4);
      count_up(bytes, out_first, out_len);
      data(PidData0, bytes);
      receive(rx);
      `uvm_info("USB_HOST", $sformatf("OUT answered with %0d bytes", rx.size()), UVM_MEDIUM)
      idle(100);

      count_up(expected, in_first, in_len);
      for (int attempt = 0; attempt < in_attempts; attempt++) begin
        token(PidIn, 7'd0, 4'd1);
        receive(rx);
        if (rx.size() > 1 && data_good(rx, expected)) begin
          idle(4);
          handshake(PidAck);
          in_received = 1'b1;
          break;
        end
        idle(200);
      end
      `uvm_info("USB_HOST", in_received ? "IN data received and acknowledged"
                                        : "no good IN data from the device", UVM_LOW)
    endtask
  endclass


endpackage
