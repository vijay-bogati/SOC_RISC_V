/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_soc.f
 Module/class Name             : File list
 Author                        : Vijay Bogati
 Description                   : RTL file list for the whole SoC and testbench, shared by both simulators
***************************************************************/

// ADR SoC file list. ADR_ROOT is exported by the Makefile.
// This include folder comes first because the OBI code needs a newer assertions header
// than the common cells library has.
+incdir+${ADR_ROOT}/rtl/third_party_ip/uart/rtl/include

// CPU, including FPU and caches
-f ${ADR_ROOT}/sim/cva6.f

// Packages and interfaces
${ADR_ROOT}/rtl/third_party_ip/common/axi/src/axi_intf.sv
${ADR_ROOT}/rtl/third_party_ip/common/axi/src/axi_atop_filter.sv
${ADR_ROOT}/rtl/third_party_ip/common/register_interface/src/reg_intf.sv
${ADR_ROOT}/rtl/third_party_ip/clint/rtl/ariane_axi_pkg.sv
${ADR_ROOT}/rtl/third_party_ip/debug/rtl/dm_pkg.sv
// Debug module files with upstream SBA fixes backported (docs/THIRD_PARTY.md). Listed here, so
// they are used instead of the same modules in the debug/rtl library folder below.
${ADR_ROOT}/rtl/third_party_ip/debug/backport/dm_sba.sv
${ADR_ROOT}/rtl/third_party_ip/debug/backport/dm_csrs.sv
${ADR_ROOT}/rtl/third_party_ip/debug/backport/dm_top.sv
${ADR_ROOT}/rtl/third_party_ip/common/tech_cells/src/rtl/tc_clk.sv
${ADR_ROOT}/rtl/third_party_ip/common/tech_cells/src/deprecated/cluster_clk_cells.sv
${ADR_ROOT}/rtl/third_party_ip/common/tech_cells/src/deprecated/pulp_clk_cells.sv
${ADR_ROOT}/rtl/third_party_ip/plic/rtl/plic_regmap.sv
${ADR_ROOT}/rtl/third_party_ip/common/apb/src/apb_pkg.sv
${ADR_ROOT}/rtl/third_party_ip/uart/rtl/obi_pkg.sv
${ADR_ROOT}/rtl/third_party_ip/uart/rtl/obi_uart_pkg.sv

+incdir+${ADR_ROOT}/rtl/third_party_ip/common/axi/include
+incdir+${ADR_ROOT}/rtl/third_party_ip/common/common_cells/include
+incdir+${ADR_ROOT}/rtl/third_party_ip/common/register_interface/include
+incdir+${ADR_ROOT}/rtl/third_party_ip/common/apb/include

// Library search paths: a module is read when it is first referenced
-y ${ADR_ROOT}/rtl/third_party_ip/common/axi/src
-y ${ADR_ROOT}/rtl/third_party_ip/common/common_cells/src
-y ${ADR_ROOT}/rtl/third_party_ip/common/common_cells/src/deprecated
-y ${ADR_ROOT}/rtl/third_party_ip/common/tech_cells/src/rtl
-y ${ADR_ROOT}/rtl/third_party_ip/common/axi_mem_if/src
-y ${ADR_ROOT}/rtl/third_party_ip/common/axi_riscv_atomics/src
-y ${ADR_ROOT}/rtl/third_party_ip/common/register_interface/src
-y ${ADR_ROOT}/rtl/third_party_ip/clint/rtl
-y ${ADR_ROOT}/rtl/third_party_ip/debug/rtl
-y ${ADR_ROOT}/rtl/third_party_ip/plic/rtl
-y ${ADR_ROOT}/rtl/third_party_ip/spi/rtl
-y ${ADR_ROOT}/rtl/third_party_ip/i2c/rtl
-y ${ADR_ROOT}/rtl/third_party_ip/aes_sbox/rtl
-y ${ADR_ROOT}/rtl/third_party_ip/dma/rtl
-y ${ADR_ROOT}/rtl/third_party_ip/ethernet/rtl
+incdir+${ADR_ROOT}/rtl/third_party_ip/usb/rtl
-y ${ADR_ROOT}/rtl/third_party_ip/pwm/rtl
-y ${ADR_ROOT}/rtl/third_party_ip/gpio/rtl
-y ${ADR_ROOT}/rtl/third_party_ip/timer/rtl
-y ${ADR_ROOT}/rtl/third_party_ip/uart/rtl
+libext+.sv+.v

// ADR SoC: package, then our IP blocks (rtl/adr_ip), then the subsystems (rtl/adr_soc)
${ADR_ROOT}/rtl/adr_soc/adr_soc_pkg.sv
${ADR_ROOT}/rtl/adr_ip/i2c/rtl/adr_i2c.sv
${ADR_ROOT}/rtl/adr_ip/wdt/rtl/adr_wdt.sv
${ADR_ROOT}/rtl/adr_ip/aes/rtl/adr_aes.sv
${ADR_ROOT}/rtl/adr_ip/bus_monitor/rtl/adr_bus_monitor.sv
${ADR_ROOT}/rtl/adr_ip/pinmux/rtl/adr_pinmux.sv
${ADR_ROOT}/rtl/adr_ip/adc/rtl/adr_adc_ctrl.sv
${ADR_ROOT}/rtl/adr_ip/otp/rtl/adr_otp_ctrl.sv
${ADR_ROOT}/rtl/adr_ip/aon_timer/rtl/adr_aon_timer.sv
${ADR_ROOT}/rtl/adr_ip/sysctrl/rtl/adr_sysctrl.sv
${ADR_ROOT}/rtl/adr_ip/dma/rtl/adr_dma.sv
${ADR_ROOT}/rtl/adr_ip/eth/rtl/adr_eth.sv
${ADR_ROOT}/sim/usb_files.sv
${ADR_ROOT}/rtl/adr_ip/usb/rtl/adr_usb_prims.sv
${ADR_ROOT}/rtl/adr_ip/usb/rtl/adr_usb.sv
${ADR_ROOT}/rtl/third_party_ip/ddr/rtl/litedram_core.v
${ADR_ROOT}/rtl/adr_ip/ddr/rtl/adr_ddr_drain.sv
${ADR_ROOT}/rtl/adr_ip/ddr/rtl/adr_ddr.sv
${ADR_ROOT}/rtl/adr_soc/rst/adr_rst_gen.sv
${ADR_ROOT}/rtl/adr_soc/core/adr_core_complex.sv
${ADR_ROOT}/rtl/adr_soc/debug/adr_debug.sv
${ADR_ROOT}/rtl/adr_soc/interconnect/adr_apb_bridge.sv
${ADR_ROOT}/rtl/adr_soc/interconnect/adr_interconnect.sv
${ADR_ROOT}/rtl/adr_soc/mem/adr_mem_model.sv
${ADR_ROOT}/rtl/adr_soc/mem/adr_axi_mem.sv
${ADR_ROOT}/rtl/adr_soc/mem/adr_rom.sv
${ADR_ROOT}/rtl/adr_soc/mem/adr_sram.sv
${ADR_ROOT}/rtl/adr_soc/mem/adr_mem_subsys.sv
${ADR_ROOT}/rtl/adr_soc/lsio/adr_lsio_subsys.sv
${ADR_ROOT}/rtl/adr_soc/periph/adr_periph_subsys.sv
${ADR_ROOT}/rtl/adr_soc/adr_soc_top.sv

// Testbench
${ADR_ROOT}/tb/common/adr_tb_pkg.sv
${ADR_ROOT}/rtl/third_party_ip/spi/tb/adr_tb_spi_mem.sv
${ADR_ROOT}/rtl/third_party_ip/i2c/tb/adr_tb_i2c_dev.sv
${ADR_ROOT}/rtl/adr_ip/usb/tb/adr_tb_usb_host.sv
${ADR_ROOT}/rtl/adr_ip/otp/tb/adr_tb_otp_macro.sv
${ADR_ROOT}/tb/verilator/tb_adr_soc.sv
${ADR_ROOT}/tb/verilator/tb_top.sv
