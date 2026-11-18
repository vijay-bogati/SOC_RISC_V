/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_soc_netlist.f
 Module/class Name             : File list
 Author                        : Vijay Bogati
 Description                   : Gate-level file list: synthesized netlist, memory model and testbench
***************************************************************/

// Gate-level file list (make ... NETLIST=1): the synthesized netlist instead of the RTL.
// The netlist is zero-delay and uses generic Yosys gates. The boot ROM and SRAM storage stay
// black boxes in synthesis, like memory macros, so their behavioural model is compiled here and
// loads +rom= and +sram= exactly as in RTL runs. Build the netlist first with make syn.
${ADR_ROOT}/rtl/adr_soc/mem/adr_mem_model.sv
${ADR_ROOT}/syn/out/adr_soc_top_syn.v

// Testbench, the same as for RTL
${ADR_ROOT}/tb/common/adr_tb_pkg.sv
${ADR_ROOT}/rtl/third_party_ip/spi/tb/adr_tb_spi_mem.sv
${ADR_ROOT}/rtl/third_party_ip/i2c/tb/adr_tb_i2c_dev.sv
${ADR_ROOT}/rtl/adr_ip/usb/tb/adr_tb_usb_host.sv
${ADR_ROOT}/rtl/adr_ip/otp/tb/adr_tb_otp_macro.sv
${ADR_ROOT}/tb/verilator/tb_adr_soc.sv
${ADR_ROOT}/tb/verilator/tb_top.sv
