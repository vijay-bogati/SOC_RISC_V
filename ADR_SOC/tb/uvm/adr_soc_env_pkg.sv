/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_soc_env_pkg.sv
 Module/class Name             : adr_soc_env_pkg
 Author                        : Vijay Bogati
 Description                   : UVM SoC environment: pin agents, fabric AXI/APB monitors, scoreboards, coverage, end-of-test checker and C-UVM handshake
***************************************************************/

// UVM bench only (a simulator with UVM 1.2). The Verilator bench (tb/verilator/) does not use it.
//
// The C program on the CPU does the checking and reports on UART0. The end-of-test checker
// prints that text and ends the test on EOT (pass) or NAK (fail), printing the same
// "[TB] RESULT" line as the Verilator bench, so cycle counts can be compared.
//
// Agents, one per pin group of the chip (interfaces and board wiring are in adr_soc_uvm_top):
//   uart0  passive  the program's report, read by the end-of-test checker
//   uart1  active   UART1 receive driver; passive when the run loops UART1 back (+loopback_uart1)
//   jtag   active   TRST with reset; the debugger when a test starts a sequence on jtag.sqr;
//                    the monitor checks the TAP's TDO enable
//   gpio   active   GPIO input driver; passive with both +loopback_gpio and +loopback_pwm
//   pwm    passive  PWM outputs (to GPIO inputs 0-7 with +loopback_pwm)
//   spi    slave    SPI memory on chip select 0
//   qspi   slave    QSPI memory on chip select 0
//   i2c    slave    I2C device with a one-byte register
//   otp    slave    OTP macro
//   adc    slave    analog input levels for the ADC comparator
//   eth    active   Ethernet frames out, SerDes receive driver; passive with +loopback_eth
//   usb    active   USB host driver and packet monitor; the base test runs the host sequence
// Loopbacks are chosen per run with +loopback_<name> (uart1, gpio, pwm, eth, all);
// adr_soc_tb_forces.svh (included in the top) makes the connections, and the environment reads
// the same arguments.
// Fabric monitors (step 3): an AXI4 monitor on each initiator and target port of the crossbar,
// and an APB monitor on each APB slot. They check the bus protocol and count transactions; their
// summary is printed at the end.
//
// Scoreboards (adr_soc_sb_pkg.sv): UART0, UART1, SPI, QSPI and I2C, each fed by its APB slot
// monitor and its pin monitors. They need the APB monitors, so +no_fabric_mon leaves them out.
// UART1's bytes into the chip come from its rx monitor, or from its tx monitor when the run loops
// UART1 back.
// Functional coverage: cg_uart (UART0, UART1), cg_spi (SPI, QSPI), cg_i2c, from the agents'
// coverage components; +no_cov leaves them out. Each prints its coverage at the end.
//
// C-UVM handshake: the program writes tagged words to system control SCRATCH0 (see adr_lib.h in
// tb/uvm/c_tests). adr_soc_c_sync watches the system control APB slot, records the end-of-test
// word and checkpoints, and passes requests to the test, which answers by writing SCRATCH1
// through the HDL backdoor.
//
// The slaves use the same settings as the Verilator bench's models (from adr_tb_pkg). The SPI and
// I2C slaves are protocol devices timed by SCLK and SCL, the OTP slave uses the macro port clock.

package adr_soc_env_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import adr_tb_pkg::*;
  import adr_uart_agent_pkg::*;
  import adr_jtag_agent_pkg::*;
  import adr_gpio_agent_pkg::*;
  import adr_pwm_agent_pkg::*;
  import adr_spi_agent_pkg::*;
  import adr_i2c_agent_pkg::*;
  import adr_otp_agent_pkg::*;
  import adr_adc_agent_pkg::*;
  import adr_eth_agent_pkg::*;
  import adr_usb_agent_pkg::*;
  import adr_axi_monitor_pkg::*;
  import adr_apb_monitor_pkg::*;
  import adr_soc_sb_pkg::*;

  // Monitored crossbar ports; adr_soc_probes sets their interfaces as "axi_<name>_vif".
  localparam int unsigned NumAxiPorts = 9;
  localparam string AxiPortNames [NumAxiPorts] = '{
    "cpu", "debug_init", "dma", "eth",                // initiators
    "rom", "sram", "ddr", "clint", "debug_tgt"        // targets
  };

  // APB slots, in slot order (adr_soc_pkg); adr_soc_probes sets their interfaces as "apb_vif_<n>".
  localparam int unsigned NumApbSlots = adr_soc_pkg::NumApbSlots;
  localparam string ApbSlotNames [NumApbSlots] = '{
    "uart0", "uart1", "gpio", "timer", "plic", "spi", "qspi", "i2c", "pwm", "wdt", "aes",
    "busmon", "sys", "dma", "mux", "adc", "otp", "aon", "eth", "usb", "ddr"
  };

  class adr_soc_env_config extends uvm_object;
    `uvm_object_utils(adr_soc_env_config)

    longint max_cycles = DefaultMaxCycles;

    // Loopbacks of this run (+loopback_<name>), filled by the environment.
    // With one off, that pin group's agent is active and its driver feeds the chip.
    bit loopback_uart1;
    bit loopback_gpio;  // GPIO pins 0-7 to inputs 8-15
    bit loopback_pwm;   // PWM outputs to GPIO inputs 0-7
    bit loopback_eth;

    // Fabric monitors, on by default. +no_fabric_mon (base test) clears it: the AXI monitors and
    // the APB monitors are then left out, apart from the system control slot's, which carries the
    // C-UVM handshake. This makes long regressions faster but skips the bus protocol checks.
    bit fabric_mon = 1'b1;

    // Functional coverage components, on by default; +no_cov (base test) clears it.
    bit coverage = 1'b1;

    // Filled by the environment from the interfaces set by the top module and adr_soc_probes.
    virtual adr_soc_tb_if     tb_vif;     // time base: clocks since reset
    virtual adr_uart_if       uart0_vif, uart1_vif;
    virtual adr_jtag_if       jtag_vif;
    virtual adr_gpio_if       gpio_vif;
    virtual adr_pwm_if        pwm_vif;
    virtual adr_spi_if        spi_vif, qspi_vif;
    virtual adr_i2c_if        i2c_vif;
    virtual adr_otp_if        otp_vif;
    virtual adr_adc_if        adc_vif;
    virtual adr_eth_serdes_if eth_vif;
    virtual adr_usb_if        usb_vif;

    function new(string name = "adr_soc_env_config");
      super.new(name);
    endfunction
  endclass

  // Prints UART0 and decides the result from the program's last character. The cycle count comes
  // from the bench's time base (adr_soc_tb_if). write() runs in the UART monitor's process on the
  // rising edge where the byte is decoded. It reads the count through the clocking block, i.e. as
  // sampled just before that edge: the count the clocked logic sees on that edge, the same count
  // the Verilator bench prints. (A direct read of tb_vif.cycle can already see that edge's update.)
  class adr_soc_eot extends uvm_subscriber #(adr_uart_item);
    `uvm_component_utils(adr_soc_eot)

    virtual adr_soc_tb_if tb_vif;
    bit                   done;
    bit                   passed;
    longint               end_cycle;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void write(adr_uart_item t);
      longint cycle = tb_vif.mon_cb.cycle;
      if (done) return;
      if (t.data == EndPass) begin
        $display("\n[TB] RESULT: PASS (%0d cycles)", cycle);
        passed    = 1'b1;
        done      = 1'b1;
        end_cycle = cycle;
      end else if (t.data == EndFail) begin
        $display("\n[TB] RESULT: FAIL (%0d cycles)", cycle);
        done      = 1'b1;
        end_cycle = cycle;
      end else begin
        $write("%c", t.data);
        $fflush();
      end
    endfunction
  endclass

  // The C-UVM handshake, on the system control slot. Words written to SCRATCH0 (offset 0x10):
  // bits 31:24 0xC5, bits 23:16 the event, bits 15:0 its argument.
  class adr_soc_c_sync extends uvm_subscriber #(adr_apb_item);
    `uvm_component_utils(adr_soc_c_sync)

    localparam logic [7:0] Tag = 8'hC5;
    localparam logic [7:0] EventEnd = 8'd1, EventCheckpoint = 8'd2, EventRequest = 8'd3;

    string                  ack_path;      // HDL path of SCRATCH1, set by adr_soc_probes
    bit                     end_seen;
    int unsigned            end_failures;  // failed checks, as the program counted them
    int unsigned            checkpoints;
    mailbox #(int unsigned) requests = new();

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void write(adr_apb_item t);
      logic [31:0] word = t.data;
      if (!t.write || t.addr[11:0] != 12'h010 || word[31:24] != Tag) return;
      case (word[23:16])
        EventEnd: begin
          end_seen     = 1'b1;
          end_failures = word[15:0];
          `uvm_info("C_SYNC", $sformatf("program finished with %0d failed checks", end_failures), UVM_LOW)
        end
        EventCheckpoint: begin
          checkpoints++;
          `uvm_info("C_SYNC", $sformatf("program checkpoint %0d", word[15:0]), UVM_MEDIUM)
        end
        EventRequest: begin
          `uvm_info("C_SYNC", $sformatf("program request %0d", word[15:0]), UVM_MEDIUM)
          void'(requests.try_put(word[15:0]));
        end
        default: `uvm_error("C_SYNC", $sformatf("unknown handshake word %h", word))
      endcase
    endfunction

    // Tells the program its request is done: the request word goes into SCRATCH1.
    function void acknowledge(int unsigned code);
      uvm_hdl_data_t word = {Tag, EventRequest, code[15:0]};
      if (!uvm_hdl_deposit(ack_path, word))
        `uvm_error("C_SYNC", {"could not write the acknowledge into ", ack_path})
    endfunction
  endclass

  `define ADR_GET_VIF(TYPE, NAME) \
    if (!uvm_config_db #(virtual TYPE)::get(this, "", `"NAME`", cfg.NAME)) \
      `uvm_fatal("NOVIF", `"NAME not set by the top module`")

  class adr_soc_env extends uvm_env;
    `uvm_component_utils(adr_soc_env)

    adr_soc_env_config cfg;
    adr_soc_eot        eot;
    adr_uart_agent     uart0, uart1;
    adr_jtag_agent     jtag;
    adr_gpio_agent     gpio;
    adr_pwm_agent      pwm;
    adr_spi_agent      spi, qspi;
    adr_i2c_agent      i2c;
    adr_otp_agent      otp;
    adr_adc_agent      adc;
    adr_eth_agent      eth;
    adr_usb_agent      usb;
    adr_axi_agent      axi [NumAxiPorts];
    adr_apb_agent      apb [NumApbSlots];
    adr_soc_c_sync     c_sync;
    adr_uart_sb        uart0_sb, uart1_sb;
    adr_spi_sb         spi_sb, qspi_sb;
    adr_i2c_sb         i2c_sb;
    adr_uart_coverage  uart0_cov, uart1_cov;
    adr_spi_coverage   spi_cov, qspi_cov;
    adr_i2c_coverage   i2c_cov;

    function new(string name, uvm_component parent);
      super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
      super.build_phase(phase);
      if (!uvm_config_db #(adr_soc_env_config)::get(this, "", "cfg", cfg))
        `uvm_fatal("NOCFG", "adr_soc_env_config not set")
      get_interfaces();
      read_loopbacks();
      eot = adr_soc_eot::type_id::create("eot", this);
      eot.tb_vif = cfg.tb_vif;
      build_serial_agents();
      build_memory_slaves();
      build_other_agents();
      build_fabric_monitors();
      build_scoreboards();
      build_coverage();
      c_sync = adr_soc_c_sync::type_id::create("c_sync", this);
      if (!uvm_config_db #(string)::get(this, "", "c_sync_ack_path", c_sync.ack_path))
        `uvm_fatal("NOCFG", "c_sync_ack_path not set by adr_soc_probes")
    endfunction

    function void get_interfaces();
      `ADR_GET_VIF(adr_soc_tb_if, tb_vif)
      `ADR_GET_VIF(adr_uart_if, uart0_vif)
      `ADR_GET_VIF(adr_uart_if, uart1_vif)
      `ADR_GET_VIF(adr_jtag_if, jtag_vif)
      `ADR_GET_VIF(adr_gpio_if, gpio_vif)
      `ADR_GET_VIF(adr_pwm_if, pwm_vif)
      `ADR_GET_VIF(adr_spi_if, spi_vif)
      `ADR_GET_VIF(adr_spi_if, qspi_vif)
      `ADR_GET_VIF(adr_i2c_if, i2c_vif)
      `ADR_GET_VIF(adr_otp_if, otp_vif)
      `ADR_GET_VIF(adr_adc_if, adc_vif)
      `ADR_GET_VIF(adr_eth_serdes_if, eth_vif)
      `ADR_GET_VIF(adr_usb_if, usb_vif)
    endfunction

    static function string on_off(bit on, string driver);
      string s;
      if (on) s = "on";
      else    s = {"off (", driver, " driver)"};
      return s;
    endfunction

    // Reads the run's loopbacks: the same +loopback_<name> arguments as adr_soc_tb_forces.svh.
    // Any other +loopback_<name>, e.g. a typo, stops the run: it would otherwise be ignored and
    // the test would run without the loopback it expects.
    function void read_loopbacks();
      bit    all = $test$plusargs("loopback_all");
      string old_arg;
      string args[$];
      if ($value$plusargs("no_loopback=%s", old_arg) || $value$plusargs("loopback=%s", old_arg))
        `uvm_fatal("ARGS", "use +loopback_uart1, +loopback_gpio, +loopback_pwm, +loopback_eth or +loopback_all; loopbacks are off by default")
      uvm_cmdline_processor::get_inst().get_plusargs(args);
      foreach (args[i]) begin
        string name;
        if (args[i].len() <= 10 || args[i].substr(0, 9) != "+loopback_") continue;
        name = args[i].substr(10, args[i].len() - 1);
        if (!(name inside {"uart1", "gpio", "pwm", "eth", "all"}))
          `uvm_fatal("ARGS", {"unknown loopback argument ", args[i],
                              " (use +loopback_uart1, +loopback_gpio, +loopback_pwm, +loopback_eth or +loopback_all)"})
      end
      cfg.loopback_uart1 = all || $test$plusargs("loopback_uart1");
      cfg.loopback_gpio  = all || $test$plusargs("loopback_gpio");
      cfg.loopback_pwm   = all || $test$plusargs("loopback_pwm");
      cfg.loopback_eth   = all || $test$plusargs("loopback_eth");
      `uvm_info("BOARD", {"loopbacks: uart1 ", on_off(cfg.loopback_uart1, "UART1"),
                          ", gpio ", on_off(cfg.loopback_gpio, "GPIO"),
                          ", pwm ",  on_off(cfg.loopback_pwm, "GPIO"),
                          ", eth ",  on_off(cfg.loopback_eth, "Ethernet")}, UVM_LOW)
    endfunction

    // UART0, UART1 and JTAG.
    function void build_serial_agents();
      adr_uart_config uart0_cfg = adr_uart_config::type_id::create("uart0_cfg");
      adr_uart_config uart1_cfg = adr_uart_config::type_id::create("uart1_cfg");
      adr_jtag_config jtag_cfg  = adr_jtag_config::type_id::create("jtag_cfg");

      uart0_cfg.vif            = cfg.uart0_vif;
      uart0_cfg.cycles_per_bit = UartCyclesPerBit;
      uvm_config_db #(adr_uart_config)::set(this, "uart0", "cfg", uart0_cfg);
      uart0 = adr_uart_agent::type_id::create("uart0", this);

      uart1_cfg.vif            = cfg.uart1_vif;
      uart1_cfg.cycles_per_bit = UartCyclesPerBit;  // the tests set UART1 to the UART0 rate
      uart1_cfg.is_active      = cfg.loopback_uart1 ? UVM_PASSIVE : UVM_ACTIVE;
      uart1_cfg.monitor_rx     = !cfg.loopback_uart1;  // looped back, rx is tx: mon sees it
      uvm_config_db #(adr_uart_config)::set(this, "uart1", "cfg", uart1_cfg);
      uart1 = adr_uart_agent::type_id::create("uart1", this);

      jtag_cfg.vif             = cfg.jtag_vif;
      jtag_cfg.tck_half_cycles = TckHalfCycles;
      jtag_cfg.reset_tcks      = TapResetTcks;
      jtag_cfg.ir_bits         = $bits(IrIdcode);
      jtag_cfg.reset_ir        = 32'(IrIdcode);
      jtag_cfg.trst_state      = TapRunTestIdle;  // the chip's TAP (dmi_jtag_tap) resets to Run-Test/Idle
      uvm_config_db #(adr_jtag_config)::set(this, "jtag", "cfg", jtag_cfg);
      jtag = adr_jtag_agent::type_id::create("jtag", this);
    endfunction

    // The slaves that replace the Verilator bench's memory-type device models.
    function void build_memory_slaves();
      adr_spi_config spi_cfg  = adr_spi_config::type_id::create("spi_cfg");
      adr_spi_config qspi_cfg = adr_spi_config::type_id::create("qspi_cfg");
      adr_i2c_config i2c_cfg  = adr_i2c_config::type_id::create("i2c_cfg");
      adr_otp_config otp_cfg  = adr_otp_config::type_id::create("otp_cfg");
      adr_adc_config adc_cfg  = adr_adc_config::type_id::create("adc_cfg");

      spi_cfg.vif       = cfg.spi_vif;
      spi_cfg.device_id = SpiDeviceId;
      spi_cfg.single_line = 1'b1;  // SPI master: one data line each way (SPI-A06)
      uvm_config_db #(adr_spi_config)::set(this, "spi", "cfg", spi_cfg);
      spi = adr_spi_agent::type_id::create("spi", this);

      qspi_cfg.vif       = cfg.qspi_vif;
      qspi_cfg.device_id = QspiDeviceId;
      uvm_config_db #(adr_spi_config)::set(this, "qspi", "cfg", qspi_cfg);
      qspi = adr_spi_agent::type_id::create("qspi", this);

      i2c_cfg.vif         = cfg.i2c_vif;
      i2c_cfg.device_addr = I2cDeviceAddr;
      // +i2c_stretch_ns=<n>: the I2C slave stretches SCL by n ns once per byte (default 0: never)
      void'($value$plusargs("i2c_stretch_ns=%d", i2c_cfg.stretch_ns));
      if (i2c_cfg.stretch_ns != 0)
        `uvm_info("I2C", $sformatf("slave clock stretching: %0d ns per byte", i2c_cfg.stretch_ns), UVM_LOW)
      uvm_config_db #(adr_i2c_config)::set(this, "i2c", "cfg", i2c_cfg);
      i2c = adr_i2c_agent::type_id::create("i2c", this);

      otp_cfg.vif = cfg.otp_vif;
      uvm_config_db #(adr_otp_config)::set(this, "otp", "cfg", otp_cfg);
      otp = adr_otp_agent::type_id::create("otp", this);

      adc_cfg.vif      = cfg.adc_vif;
      adc_cfg.level[0] = AdcLevelCh0;
      adc_cfg.level[1] = AdcLevelCh1;
      uvm_config_db #(adr_adc_config)::set(this, "adc", "cfg", adc_cfg);
      adc = adr_adc_agent::type_id::create("adc", this);
    endfunction

    // Monitors on GPIO, PWM, Ethernet and USB; GPIO and Ethernet also drive when their loopback is
    // off; USB always has its host driver.
    function void build_other_agents();
      adr_gpio_config gpio_cfg = adr_gpio_config::type_id::create("gpio_cfg");
      adr_pwm_config  pwm_cfg  = adr_pwm_config::type_id::create("pwm_cfg");
      adr_eth_config  eth_cfg  = adr_eth_config::type_id::create("eth_cfg");
      adr_usb_config  usb_cfg  = adr_usb_config::type_id::create("usb_cfg");

      gpio_cfg.vif       = cfg.gpio_vif;
      gpio_cfg.is_active = (cfg.loopback_gpio && cfg.loopback_pwm) ? UVM_PASSIVE : UVM_ACTIVE;
      uvm_config_db #(adr_gpio_config)::set(this, "gpio", "cfg", gpio_cfg);
      gpio = adr_gpio_agent::type_id::create("gpio", this);

      pwm_cfg.vif = cfg.pwm_vif;
      uvm_config_db #(adr_pwm_config)::set(this, "pwm", "cfg", pwm_cfg);
      pwm = adr_pwm_agent::type_id::create("pwm", this);

      eth_cfg.vif       = cfg.eth_vif;
      eth_cfg.is_active = cfg.loopback_eth ? UVM_PASSIVE : UVM_ACTIVE;
      uvm_config_db #(adr_eth_config)::set(this, "eth", "cfg", eth_cfg);
      eth = adr_eth_agent::type_id::create("eth", this);

      usb_cfg.vif       = cfg.usb_vif;
      usb_cfg.is_active = UVM_ACTIVE;
      uvm_config_db #(adr_usb_config)::set(this, "usb", "cfg", usb_cfg);
      usb = adr_usb_agent::type_id::create("usb", this);
    endfunction

    // One AXI monitor per crossbar port and one APB monitor per slot. With cfg.fabric_mon clear,
    // only the system control slot's APB monitor (the C-UVM handshake).
    function void build_fabric_monitors();
      if (!cfg.fabric_mon)
        `uvm_info("FABRIC", "fabric monitors off (+no_fabric_mon); only the system control APB monitor is kept", UVM_LOW)
      if (cfg.fabric_mon) foreach (AxiPortNames[i]) begin
        adr_axi_config axi_cfg = adr_axi_config::type_id::create({"axi_", AxiPortNames[i], "_cfg"});
        axi_cfg.port_name = {"axi_", AxiPortNames[i]};
        if (!uvm_config_db #(virtual adr_axi_if)::get(this, "", {axi_cfg.port_name, "_vif"}, axi_cfg.vif))
          `uvm_fatal("NOVIF", {axi_cfg.port_name, "_vif not set by adr_soc_probes"})
        uvm_config_db #(adr_axi_config)::set(this, axi_cfg.port_name, "cfg", axi_cfg);
        axi[i] = adr_axi_agent::type_id::create(axi_cfg.port_name, this);
      end
      foreach (ApbSlotNames[i]) begin
        adr_apb_config apb_cfg;
        if (!cfg.fabric_mon && i != adr_soc_pkg::SlotSys) continue;
        apb_cfg = adr_apb_config::type_id::create({"apb_", ApbSlotNames[i], "_cfg"});
        apb_cfg.slot_name = {"apb_", ApbSlotNames[i]};
        if (!uvm_config_db #(virtual adr_apb_if)::get(this, "", $sformatf("apb_vif_%0d", i), apb_cfg.vif))
          `uvm_fatal("NOVIF", $sformatf("apb_vif_%0d not set by adr_soc_probes", i))
        uvm_config_db #(adr_apb_config)::set(this, apb_cfg.slot_name, "cfg", apb_cfg);
        apb[i] = adr_apb_agent::type_id::create(apb_cfg.slot_name, this);
      end
    endfunction

    // UART0, UART1, SPI, QSPI and I2C scoreboards, when the APB monitors exist.
    function void build_scoreboards();
      if (!cfg.fabric_mon) begin
        `uvm_info("SB", "scoreboards off (they need the APB monitors, off with +no_fabric_mon)", UVM_LOW)
        return;
      end
      uart0_sb = adr_uart_sb::type_id::create("uart0_sb", this);
      uart0_sb.tag = "UART0_SB";
      uart0_sb.monitor_cycles_per_bit = UartCyclesPerBit;
      uart0_sb.vif = cfg.uart0_vif;
      uart1_sb = adr_uart_sb::type_id::create("uart1_sb", this);
      uart1_sb.tag = "UART1_SB";
      uart1_sb.monitor_cycles_per_bit = UartCyclesPerBit;
      uart1_sb.vif = cfg.uart1_vif;
      spi_sb  = adr_spi_sb::type_id::create("spi_sb", this);
      spi_sb.tag = "SPI_SB";
      qspi_sb = adr_spi_sb::type_id::create("qspi_sb", this);
      qspi_sb.tag = "QSPI_SB";
      i2c_sb  = adr_i2c_sb::type_id::create("i2c_sb", this);
      i2c_sb.vif = cfg.i2c_vif;
    endfunction

    // cg_uart, cg_spi and cg_i2c, unless +no_cov.
    // The agents' configuration objects come from the config_db entries set for the agents above
    // (the agents' own build_phase has not run yet).
    function void build_coverage();
      adr_uart_config uart_cfg;
      adr_i2c_config  i2c_cfg;
      if (!cfg.coverage) begin
        `uvm_info("COV", "functional coverage off (+no_cov)", UVM_LOW)
        return;
      end
      uart0_cov = adr_uart_coverage::type_id::create("uart0_cov", this);
      if (!uvm_config_db #(adr_uart_config)::get(this, "uart0", "cfg", uart_cfg)) `uvm_fatal("NOCFG", "uart0 cfg")
      uart0_cov.cfg = uart_cfg;
      uart1_cov = adr_uart_coverage::type_id::create("uart1_cov", this);
      if (!uvm_config_db #(adr_uart_config)::get(this, "uart1", "cfg", uart_cfg)) `uvm_fatal("NOCFG", "uart1 cfg")
      uart1_cov.cfg = uart_cfg;
      spi_cov  = adr_spi_coverage::type_id::create("spi_cov", this);
      qspi_cov = adr_spi_coverage::type_id::create("qspi_cov", this);
      i2c_cov  = adr_i2c_coverage::type_id::create("i2c_cov", this);
      if (!uvm_config_db #(adr_i2c_config)::get(this, "i2c", "cfg", i2c_cfg)) `uvm_fatal("NOCFG", "i2c cfg")
      i2c_cov.cfg = i2c_cfg;
    endfunction

    function void connect_phase(uvm_phase phase);
      // The bytes into the chip on UART1: its rx monitor, or tx itself when looped back.
      uvm_analysis_port #(adr_uart_item) uart1_in = cfg.loopback_uart1 ? uart1.mon.ap : uart1.rx_mon.ap;
      uart0.mon.ap.connect(eot.analysis_export);
      apb[adr_soc_pkg::SlotSys].mon.ap.connect(c_sync.analysis_export);
      if (uart0_sb != null) begin
        apb[adr_soc_pkg::SlotUart0].mon.ap.connect(uart0_sb.apb_export);
        uart0.mon.ap.connect(uart0_sb.tx_export);
        apb[adr_soc_pkg::SlotUart1].mon.ap.connect(uart1_sb.apb_export);
        uart1.mon.ap.connect(uart1_sb.tx_export);
        uart1_in.connect(uart1_sb.rx_export);
        apb[adr_soc_pkg::SlotSpi].mon.ap.connect(spi_sb.apb_export);
        spi.mon.ap.connect(spi_sb.spi_export);
        apb[adr_soc_pkg::SlotQspi].mon.ap.connect(qspi_sb.apb_export);
        qspi.mon.ap.connect(qspi_sb.spi_export);
        apb[adr_soc_pkg::SlotI2c].mon.ap.connect(i2c_sb.apb_export);
        i2c.mon.ap.connect(i2c_sb.i2c_export);
      end
      if (uart0_cov != null) begin
        uart0.mon.ap.connect(uart0_cov.tx_export);
        uart1.mon.ap.connect(uart1_cov.tx_export);
        uart1_in.connect(uart1_cov.rx_export);
        spi.mon.ap.connect(spi_cov.analysis_export);
        qspi.mon.ap.connect(qspi_cov.analysis_export);
        i2c.mon.ap.connect(i2c_cov.analysis_export);
      end
    endfunction

    // One line per crossbar port, and one for the APB slots that saw traffic.
    function void report_phase(uvm_phase phase);
      string slots = "";
      foreach (axi[i])
        if (axi[i] != null)
          `uvm_info("FABRIC", {axi[i].cfg.port_name, ": ", axi[i].mon.summary()}, UVM_LOW)
      foreach (apb[i])
        if (apb[i] != null && apb[i].mon.reads + apb[i].mon.writes > 0)
          slots = {slots, $sformatf(" %s %0d/%0d", ApbSlotNames[i], apb[i].mon.reads, apb[i].mon.writes)};
      `uvm_info("FABRIC", {"APB reads/writes per slot:", slots}, UVM_LOW)
    endfunction
  endclass

  `undef ADR_GET_VIF

endpackage
