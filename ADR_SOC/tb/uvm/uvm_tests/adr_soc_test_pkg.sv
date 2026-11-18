/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_soc_test_pkg.sv
 Module/class Name             : adr_soc_test_pkg, adr_soc_base_test, adr_debug_test, adr_sba_test
 Author                        : Vijay Bogati
 Description                   : UVM SoC tests: the base test (C program, C-UVM handshake, verdict), the debug and SBA tests
***************************************************************/

// UVM bench only (a simulator with UVM 1.2). Selected with +UVM_TESTNAME (the Makefile picks it per test).
// adr_soc_base_test runs any of the C tests: the program is loaded with +sram= as in the
// Verilator bench, and the test ends when the program sends EOT or NAK on UART0, or on timeout.
// Tests that need the testbench to act extend this class and start their sequence (uvm_sequence/adr_soc_seq_pkg.sv)
// in test_body(). The Makefile maps a C test to its UVM test with UVM_TEST_<test>.
// The USB host is the USB agent's driver: usb_host() runs the SoC host sequence (the transfer
// usb.c expects) in every test; a test that sends its own USB transfers overrides usb_host().
// Loopbacks are run-time arguments (+loopback_<name>, see tb/uvm/adr_soc_tb_forces.svh), not test settings.

package adr_soc_test_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import adr_tb_pkg::*;
  import adr_soc_env_pkg::*;
  import adr_soc_seq_pkg::*;

  class adr_soc_base_test extends uvm_test;
    `uvm_component_utils(adr_soc_base_test)

    adr_soc_env_config cfg;
    adr_soc_env        env;
    bit                timed_out;
    bit                c_sync_on;  // the program uses the C-UVM handshake (not +no_c_sync)

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      cfg = adr_soc_env_config::type_id::create("cfg");
      if (!$value$plusargs("max_cycles=%d", cfg.max_cycles)) cfg.max_cycles = DefaultMaxCycles;
      if ($test$plusargs("no_fabric_mon")) cfg.fabric_mon = 1'b0;
      if ($test$plusargs("no_cov"))        cfg.coverage   = 1'b0;
      uvm_config_db #(adr_soc_env_config)::set(this, "env", "cfg", cfg);
      env = adr_soc_env::type_id::create("env", this);
      c_sync_on = !$test$plusargs("no_c_sync");
    endfunction

    // Extended by tests that drive the testbench side; runs alongside the program.
    virtual task test_body();
    endtask

    // The USB host's part. By default the SoC host sequence: when the device connects, bus reset,
    // SOF, SETUP, OUT, then IN until the device answers, as the Verilator bench's host model does.
    // A test with its own USB transfers overrides this and starts its sequences on env.usb.sqr.
    virtual task usb_host();
      adr_soc_usb_host_seq seq = adr_soc_usb_host_seq::type_id::create("usb_host_seq");
      seq.start(env.usb.sqr);
    endtask

    // Extended by tests whose program asks the bench to act (adr_tb_request in the C test).
    // It returns when the bench has done its part; the program is then acknowledged.
    virtual task handle_request(int unsigned code);
      `uvm_error("C_SYNC", $sformatf("the program sent request %0d, which this test does not handle", code))
    endtask

    task serve_requests();
      forever begin
        int unsigned code;
        env.c_sync.requests.get(code);
        handle_request(code);
        env.c_sync.acknowledge(code);
      end
    endtask

    task run_phase(uvm_phase phase);
      phase.raise_objection(this);
      fork
        test_body();
        serve_requests();
        usb_host();
      join_none
      fork
        wait (env.eot.done);
        begin
          do @(cfg.tb_vif.mon_cb); while (cfg.tb_vif.mon_cb.cycle < cfg.max_cycles);
          $display("\n[TB] TIMEOUT after %0d cycles", cfg.tb_vif.mon_cb.cycle);
          timed_out = 1'b1;
        end
      join_any
      disable fork;
      phase.drop_objection(this);
    endtask

    // The Makefile looks for this exact line, so a crash or a hang can never count as a pass.
    // With the handshake, the program's end-of-test word must have come and agree with the UART.
    function void report_phase(uvm_phase phase);
      uvm_report_server server = uvm_report_server::get_server();
      int errors;
      if (c_sync_on && env.eot.done) begin
        if (!env.c_sync.end_seen)
          `uvm_error("C_SYNC", "the program ended without its end-of-test word")
        else if ((env.c_sync.end_failures == 0) != env.eot.passed)
          `uvm_error("C_SYNC", "the end-of-test word and the UART result disagree")
      end
      errors = server.get_severity_count(UVM_ERROR) + server.get_severity_count(UVM_FATAL);
      if (env.eot.passed && !timed_out && errors == 0) $display("[TOP] VERDICT: PASS");
      else                                             $display("[TOP] VERDICT: FAIL");
    endfunction
  endclass

  // Test 'debug' (tb/uvm/c_tests/debug.c): the debugger sequence on the JTAG agent while the program runs.
  // The debugger must finish its steps before the program ends.
  class adr_debug_test extends adr_soc_base_test;
    `uvm_component_utils(adr_debug_test)

    adr_soc_debug_seq seq;
    bit               seq_done;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task test_body();
      seq = adr_soc_debug_seq::type_id::create("seq");
      seq.start(env.jtag.sqr);
      seq_done = !env.eot.done;
      $display("[JTAG] %0d failed", seq.failures);
    endtask

    function void report_phase(uvm_phase phase);
      if (!seq_done) `uvm_error("JTAG", "the program ended before the debugger sequence finished")
      super.report_phase(phase);
    endfunction
  endclass

  // Test 'sba' (tb/uvm/c_tests/sba.c): the program's request 1 runs the system bus access
  // sequence on the JTAG agent; the program then checks the results from its side.
  class adr_sba_test extends adr_soc_base_test;
    `uvm_component_utils(adr_sba_test)

    localparam int unsigned SbaRequest = 1;  // SBA_REQUEST in sba.c

    adr_soc_sba_seq seq;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    task handle_request(int unsigned code);
      if (code != SbaRequest) begin
        super.handle_request(code);
        return;
      end
      seq = adr_soc_sba_seq::type_id::create("seq");
      seq.start(env.jtag.sqr);
      $display("[JTAG] %0d failed", seq.failures);
    endtask

    function void report_phase(uvm_phase phase);
      if (seq == null) `uvm_error("JTAG", "the program ended without asking for the system bus access sequence")
      super.report_phase(phase);
    endfunction
  endclass

endpackage
