/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_riscv_dbg_pkg.sv
 Module/class Name             : adr_riscv_dbg_pkg, adr_riscv_dbg_base_seq
 Author                        : Vijay Bogati
 Description                   : UVM RISC-V debug layer on the JTAG agent: spec constants and DMI, abstract command and system bus tasks
***************************************************************/

// UVM benches only (a simulator with UVM 1.2). Reusable wherever a RISC-V Debug Specification 0.13 debug transport
// module sits behind a JTAG TAP (IP level or SoC level).
// adr_riscv_dbg_base_seq runs on the JTAG agent's sequencer and gives a test sequence the steps a
// debugger uses: TAP reset, raw scans, DMI read/write, abstract commands (register access, program
// buffer), system bus access and status waits. A test sequence extends it and writes body().
// Only RISC-V debug values are here. Chip values (IDCODE, addresses, polling limits) belong to the
// test. The Verilator bench (tb_top) keeps its own copy of these values in adr_tb_pkg.

package adr_riscv_dbg_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import adr_jtag_agent_pkg::*;

  // ---- Debug transport module: JTAG instructions and register fields ----
  localparam logic [31:0] IrIdcode = 32'h01, IrDtmcs = 32'h10, IrDmi = 32'h11;
  localparam logic [3:0]  DtmVersion013 = 4'd1;

  // ---- DMI scan: addr[abits], data[32], op[2] ----
  localparam logic [1:0] DmiOpNop = 2'd0, DmiOpRead = 2'd1, DmiOpWrite = 2'd2;
  localparam logic [1:0] DmiOk = 2'd0;

  // ---- Debug module registers ----
  localparam logic [6:0] DmData0 = 7'h04, DmData1 = 7'h05, DmControl = 7'h10, DmStatus = 7'h11,
                         DmAbstractCs = 7'h16, DmCommand = 7'h17, DmProgBuf0 = 7'h20,
                         DmProgBuf1 = 7'h21, DmSbCs = 7'h38, DmSbAddr0 = 7'h39, DmSbAddr1 = 7'h3A,
                         DmSbData0 = 7'h3C, DmSbData1 = 7'h3D;
  localparam logic [3:0]  DmVersion013 = 4'd2;

  // ---- dmcontrol, dmstatus, abstractcs, command and sbcs fields ----
  localparam logic [31:0] CtrlActive = 32'h1, CtrlNdmReset = 32'h2, CtrlResume = 32'h4000_0000,
                          CtrlHalt = 32'h8000_0000;
  localparam logic [31:0] StatusAllHalted = 32'h1 << 9, StatusAllRunning = 32'h1 << 11,
                          StatusAllResumeAck = 32'h1 << 17;
  localparam logic [31:0] AbsBusy = 32'h1 << 12, AbsCmdErrMask = 32'h7 << 8;
  localparam logic [31:0] CmdSize64 = 32'h3 << 20, CmdPostExec = 32'h1 << 18,
                          CmdTransfer = 32'h1 << 17, CmdWrite = 32'h1 << 16;
  localparam logic [31:0] SbReadOnAddr = 32'h1 << 20, SbAccess64 = 32'h3 << 17,
                          SbBusy = 32'h1 << 21, SbErrorMask = 32'h7 << 12;

  // ---- Abstract command register numbers ----
  function automatic logic [31:0] gpr(int unsigned n);  // x0 to x31
    return 32'h1000 + n;
  endfunction
  localparam logic [31:0] CsrDpc = 32'h7B1;

  // ---- Instructions for the program buffer ----
  localparam logic [31:0] InsnEbreak = 32'h0010_0073;

  class adr_riscv_dbg_base_seq extends uvm_sequence #(adr_jtag_item);
    `uvm_object_utils(adr_riscv_dbg_base_seq)

    // Set by the test before start(): the chip's DMI address width and the polling limits.
    int unsigned dmi_abits         = 7;
    int unsigned dmi_idle_tcks     = 16;    // lets a DMI request cross clock domains
    int unsigned cmd_poll_limit    = 2000;  // abstractcs and sbcs busy polls
    int unsigned status_poll_limit = 500;   // dmstatus polls

    int unsigned dmi_errors;  // DMI scans that returned a status other than OK

    function new(string name = "adr_riscv_dbg_base_seq");
      super.new(name);
    endfunction

    // ---- JTAG level ----
    task tap_reset();
      adr_jtag_item item = adr_jtag_item::type_id::create("tap_reset");
      start_item(item);
      item.op = JtagTapReset;
      finish_item(item);
    endtask

    task scan(input logic [31:0] ir, input logic [63:0] value, input int unsigned bits,
              input int unsigned idle, output logic [63:0] out);
      adr_jtag_item item = adr_jtag_item::type_id::create("scan");
      start_item(item);
      item.op        = JtagScan;
      item.ir        = ir;
      item.dr_in     = value;
      item.dr_bits   = bits;
      item.idle_tcks = idle;
      finish_item(item);
      out = item.dr_out;
    endtask

    task wait_clocks(int unsigned n);
      adr_jtag_item item = adr_jtag_item::type_id::create("wait");
      start_item(item);
      item.op          = JtagWait;
      item.wait_clocks = n;
      finish_item(item);
    endtask

    // ---- DMI: a request scan, then a nop scan that returns the result ----
    task dmi_scan(input logic [6:0] addr, input logic [31:0] data, input logic [1:0] op,
                  output logic [63:0] out);
      scan(IrDmi, (64'(addr) << 34) | (64'(data) << 2) | 64'(op), dmi_abits + 34, dmi_idle_tcks, out);
    endtask

    task dmi_read(input logic [6:0] addr, output logic [31:0] data);
      logic [63:0] out;
      dmi_scan(addr, 32'd0, DmiOpRead, out);
      dmi_scan(7'd0, 32'd0, DmiOpNop, out);
      if (out[1:0] !== DmiOk) dmi_errors++;
      data = out[33:2];
    endtask

    task dmi_write(input logic [6:0] addr, input logic [31:0] data);
      logic [63:0] out;
      dmi_scan(addr, data, DmiOpWrite, out);
      dmi_scan(7'd0, 32'd0, DmiOpNop, out);
      if (out[1:0] !== DmiOk) dmi_errors++;
    endtask

    // ---- Debug module status ----
    task dm_wait(input logic [31:0] status_bits, output bit ok);
      logic [31:0] status;
      ok = 1'b0;
      for (int unsigned i = 0; i < status_poll_limit; i++) begin
        dmi_read(DmStatus, status);
        if ((status & status_bits) === status_bits) begin
          ok = 1'b1;
          return;
        end
      end
    endtask

    // ---- Abstract commands ----
    // Waits until abstractcs is no longer busy; ok when cmderr is 0.
    task abstract_wait(output bit ok);
      logic [31:0] cs;
      ok = 1'b0;
      for (int unsigned i = 0; i < cmd_poll_limit; i++) begin
        dmi_read(DmAbstractCs, cs);
        if ((cs & AbsBusy) === 32'd0) begin
          ok = (cs & AbsCmdErrMask) === 32'd0;
          return;
        end
      end
    endtask

    task abstract_cmd(input logic [31:0] command, output bit ok);
      dmi_write(DmCommand, command);
      abstract_wait(ok);
    endtask

    task read_reg(input logic [31:0] register, output bit ok, output logic [63:0] value);
      logic [31:0] low, high;
      value = '0;
      abstract_cmd(CmdSize64 | CmdTransfer | register, ok);
      if (!ok) return;
      dmi_read(DmData1, high);
      dmi_read(DmData0, low);
      value = {high, low};
    endtask

    task write_reg(input logic [31:0] register, input logic [63:0] value, output bit ok);
      dmi_write(DmData0, value[31:0]);
      dmi_write(DmData1, value[63:32]);
      abstract_cmd(CmdSize64 | CmdTransfer | CmdWrite | register, ok);
    endtask

    // ---- System bus access, 64-bit ----
    task sb_wait(output bit ok);
      logic [31:0] cs;
      ok = 1'b0;
      for (int unsigned i = 0; i < cmd_poll_limit; i++) begin
        dmi_read(DmSbCs, cs);
        if ((cs & SbBusy) === 32'd0) begin
          ok = (cs & SbErrorMask) === 32'd0;
          return;
        end
      end
    endtask

    task sb_read(input logic [63:0] addr, output bit ok, output logic [63:0] value);
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

    task sb_write(input logic [63:0] addr, input logic [63:0] value, output bit ok);
      dmi_write(DmSbCs, SbAccess64);
      dmi_write(DmSbAddr1, addr[63:32]);
      dmi_write(DmSbAddr0, addr[31:0]);
      dmi_write(DmSbData1, value[63:32]);
      dmi_write(DmSbData0, value[31:0]);
      sb_wait(ok);
    endtask

    // Reads addr up to `tries` times, gap_clocks system clocks apart, until it holds want.
    task sb_poll(input logic [63:0] addr, input logic [63:0] want, input int unsigned tries,
                 input int unsigned gap_clocks, output bit ok);
      logic [63:0] value;
      bit read_ok;
      ok = 1'b0;
      for (int unsigned i = 0; i < tries; i++) begin
        sb_read(addr, read_ok, value);
        if (!read_ok) return;
        if (value === want) begin
          ok = 1'b1;
          return;
        end
        wait_clocks(gap_clocks);
      end
    endtask
  endclass

endpackage
