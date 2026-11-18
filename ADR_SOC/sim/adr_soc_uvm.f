/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_soc_uvm.f
 Module/class Name             : File list
 Author                        : Vijay Bogati
 Description                   : UVM bench file list: the UVM agents, environment, tests and top (after the simulator's design list)
***************************************************************/

// For a simulator with UVM 1.2 (make ... TB=uvm with SIM=questa, vcs or xcelium). The Makefile gives
// the simulator's design list first (sim/questa.f, or the generated VCS/Xcelium list), which also
// brings the Verilator bench (tb_top); it is compiled but not used as a top here. The Verilator file
// lists do not include any of these.

// UVM UART agent (IP level)
${ADR_ROOT}/rtl/third_party_ip/uart/tb/uvm/adr_uart_if.sv
${ADR_ROOT}/rtl/third_party_ip/uart/tb/uvm/adr_uart_agent_pkg.sv

// UVM JTAG agent and RISC-V debug layer (IP level)
${ADR_ROOT}/rtl/third_party_ip/debug/tb/uvm/adr_jtag_if.sv
${ADR_ROOT}/rtl/third_party_ip/debug/tb/uvm/adr_jtag_agent_pkg.sv
${ADR_ROOT}/rtl/third_party_ip/debug/tb/uvm/adr_riscv_dbg_pkg.sv

// UVM agents for the other pin groups (IP level)
${ADR_ROOT}/rtl/third_party_ip/gpio/tb/uvm/adr_gpio_if.sv
${ADR_ROOT}/rtl/third_party_ip/gpio/tb/uvm/adr_gpio_agent_pkg.sv
${ADR_ROOT}/rtl/third_party_ip/pwm/tb/uvm/adr_pwm_if.sv
${ADR_ROOT}/rtl/third_party_ip/pwm/tb/uvm/adr_pwm_agent_pkg.sv
${ADR_ROOT}/rtl/third_party_ip/spi/tb/uvm/adr_spi_if.sv
${ADR_ROOT}/rtl/third_party_ip/spi/tb/uvm/adr_spi_agent_pkg.sv
${ADR_ROOT}/rtl/third_party_ip/i2c/tb/uvm/adr_i2c_if.sv
${ADR_ROOT}/rtl/third_party_ip/i2c/tb/uvm/adr_i2c_agent_pkg.sv
${ADR_ROOT}/rtl/adr_ip/otp/tb/uvm/adr_otp_if.sv
${ADR_ROOT}/rtl/adr_ip/otp/tb/uvm/adr_otp_agent_pkg.sv
${ADR_ROOT}/rtl/adr_ip/adc/tb/uvm/adr_adc_if.sv
${ADR_ROOT}/rtl/adr_ip/adc/tb/uvm/adr_adc_agent_pkg.sv
${ADR_ROOT}/rtl/adr_ip/eth/tb/uvm/adr_eth_serdes_if.sv
${ADR_ROOT}/rtl/adr_ip/eth/tb/uvm/adr_eth_agent_pkg.sv
${ADR_ROOT}/rtl/adr_ip/usb/tb/uvm/adr_usb_if.sv
${ADR_ROOT}/rtl/adr_ip/usb/tb/uvm/adr_usb_agent_pkg.sv

// Bus monitors for the fabric (AXI4 crossbar ports, APB slots)
${ADR_ROOT}/tb/uvm/vip/axi/adr_axi_if.sv
${ADR_ROOT}/tb/uvm/vip/axi/adr_axi_monitor_pkg.sv
${ADR_ROOT}/tb/uvm/vip/apb/adr_apb_if.sv
${ADR_ROOT}/tb/uvm/vip/apb/adr_apb_monitor_pkg.sv
+incdir+${ADR_ROOT}/tb/uvm/vip/axi
+incdir+${ADR_ROOT}/tb/uvm/vip/apb
+incdir+${ADR_ROOT}/tb/uvm

// SoC environment (scoreboards first), test sequences, tests and top
${ADR_ROOT}/tb/uvm/adr_soc_tb_if.sv
${ADR_ROOT}/tb/uvm/adr_soc_sb_pkg.sv
${ADR_ROOT}/tb/uvm/adr_soc_env_pkg.sv
${ADR_ROOT}/tb/uvm/uvm_sequence/adr_soc_seq_pkg.sv
${ADR_ROOT}/tb/uvm/uvm_tests/adr_soc_test_pkg.sv
${ADR_ROOT}/tb/uvm/adr_soc_probes.sv
${ADR_ROOT}/tb/uvm/adr_soc_uvm_top.sv
