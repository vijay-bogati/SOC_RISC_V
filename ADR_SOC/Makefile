#***************************************************************
# Project name                  : ADR SoC
# File Name                     : Makefile
# Module/class Name             : Makefile
# Author                        : Vijay Bogati
# Description                   : Build, simulation (RTL or netlist; Verilator, Questa, VCS or Xcelium), regression and synthesis flow
#***************************************************************

# ADR SoC - build and simulate. SIM selects the simulator: verilator (default), questa, vcs or xcelium.
#   make regress      run every test in TESTS, PARALLEL at once (default 1), and write a summary
#   make regress_all  run every test on both simulators, sharing PARALLEL slots, and compare them
#   make sim          build what is missing and run one test (TEST=name)
#   make sw           build software images only
#   make verilate     build the Verilator simulator only
#   make questa_build compile the design for Questa once; every test shares this build
#   make vcs_build    the same for VCS (SIM=vcs), make xcelium_build for Xcelium (SIM=xcelium)
#   make coverage     run every test on Questa with code coverage and report it in results/coverage/
#   make clean        remove build outputs
# Each simulator has one shared build, and each test has its own folder: results/<sim>/<test>/.
# Waveforms (Questa .wlf, VCS .vpd, Xcelium .shm) are on for make sim and off for make regress.
# WAVES=0 or 1 overrides make sim.
# NETLIST=1 runs any of these on the synthesized gate netlist (syn/out/adr_soc_top_syn.v, from make syn)
# instead of the RTL, on either simulator, with its own build and results/<sim>_netlist/<test>/ folders.
# TB=uvm (Questa, VCS or Xcelium: a simulator with UVM 1.2) runs the tests on the UVM bench (tb/uvm/)
# instead of the Verilator bench (tb/verilator/), with its own build and results/<sim>_uvm/<test>/
# folders. UVM_TEST= picks the UVM test.
# Testbench layout: tb/common/ is shared by both benches; each bench has its own C tests
# (tb/verilator/c_tests/, tb/uvm/c_tests/), built into their own image folders.

ROOT      := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
BUILD_DIR ?= $(HOME)/.cache/adr_soc_build
TEST      ?= smoke
# Load limits for this VM (10 GB of memory). Building uses the memory, not the CPU: the Verilator
# step alone peaks at 6.7 GB (measured 2026-11-07), so only one build may run at a time, and
# JOBS=nproc (10) C++ compiles got the desktop killed by systemd-oomd. A test run is small (45 MB
# for smoke on Verilator). Every build and run is started in its own memory-capped scope at low
# priority, so if one grows too large only that job is killed. LIMIT= turns this off.
JOBS      ?= 2
PARALLEL  ?= 1
MEM_MAX   ?= 8G
LIMIT     ?= systemd-run --user --scope --quiet -p MemoryMax=$(MEM_MAX) nice -n 10
SIM       ?= verilator
WAVES     ?= 1
REGRESS_WAVES ?= 0
COVER     ?= 0
RESULTS_DIR ?= $(ROOT)/results
NETLIST   ?= 0
VIEW_0    :=
VIEW_1    := _netlist
TB        ?= sv
TBVIEW_sv :=
TBVIEW_uvm := _uvm
# Ethernet line rate: 25 (default, the spec rate: 390.625 MHz SerDes clock) or 10 (156.25 MHz).
# ETH_RATE=10 defines ADR_ETH_10G for the RTL and both benches, and builds and runs in its own
# folders (suffix _eth10g), so the two rates never share a build. The netlist is synthesized at 25G.
ETH_RATE  ?= 25
ifeq ($(ETH_RATE),10)
  ETHVIEW            := _eth10g
  ETH_DEFS_verilator := -DADR_ETH_10G
  ETH_DEFS_questa    := +define+ADR_ETH_10G
  ETH_DEFS_vcs       := +define+ADR_ETH_10G
  ETH_DEFS_xcelium   := +define+ADR_ETH_10G
  ifeq ($(NETLIST),1)
    $(error ETH_RATE=10 with NETLIST=1: the netlist is synthesized at 25G)
  endif
else ifneq ($(ETH_RATE),25)
  $(error ETH_RATE must be 25 or 10)
endif
VIEW      := $(VIEW_$(NETLIST))$(TBVIEW_$(TB))$(ETHVIEW)
ifeq ($(TB),uvm)
  ifeq ($(filter questa vcs xcelium,$(SIM)),)
    $(error TB=uvm needs SIM=questa, vcs or xcelium: Verilator 5.020 cannot run UVM)
  endif
  ifeq ($(NETLIST),1)
    $(error TB=uvm with NETLIST=1 is not set up yet)
  endif
endif
RUN_DIR     := $(RESULTS_DIR)/$(SIM)$(VIEW)
# C tests and their images, per bench. The Verilator bench's are also used for NETLIST=1.
C_DIR_sv    := tb/verilator/c_tests
C_DIR_uvm   := tb/uvm/c_tests
C_DIR       := $(C_DIR_$(TB))
# The UVM bench's C tests use the C-UVM handshake (-DADR_TB_SYNC). TB_SYNC=0 builds them without
# it, into their own folder: the images then equal the Verilator bench's, for an exact cycle check.
TB_SYNC     ?= 1
SYNC_DEFS_uvm_1 := -DADR_TB_SYNC
SYNCVIEW_uvm_0  := _nosync
SW_DIR      := $(BUILD_DIR)/sw$(TBVIEW_$(TB))$(SYNCVIEW_$(TB)_$(TB_SYNC))
QUESTA_DIR  := $(BUILD_DIR)/questa$(VIEW)
VCS_DIR     := $(BUILD_DIR)/vcs$(VIEW)
XCELIUM_DIR := $(BUILD_DIR)/xcelium$(VIEW)
VERILATOR_DIR := $(BUILD_DIR)/verilator$(VIEW)

TP := $(ROOT)/rtl/third_party_ip
TESTS ?= smoke irq debug periph serial timers aes sys eth usb ddr

# Extra simulator arguments for particular tests
TEST_ARGS_debug := +jtag_test

# UVM bench: the UVM test for each C test (UVM_TEST_<test>), else the base test, which just runs the program.
UVM_TEST_debug := adr_debug_test
UVM_TEST_sba   := adr_sba_test
UVM_TEST ?= $(or $(UVM_TEST_$(TEST)),adr_soc_base_test)
QUESTA_VSIM_uvm = -L $(UVM_HOME) -sv_lib $(UVM_HOME)/linux_x86_64/uvm_dpi +UVM_TESTNAME=$(UVM_TEST) +UVM_NO_RELNOTES \
  $(if $(filter 0,$(TB_SYNC)),+no_c_sync)

export ADR_ROOT := $(ROOT)

CROSS   := riscv64-unknown-elf-
SW_FLAGS := -march=rv64gc -mabi=lp64d -mcmodel=medany -O2 -g -ffreestanding \
            -fno-builtin -fno-common -nostdlib -nostartfiles -Wall -Wextra

VERILATOR_FLAGS := --binary -j $(JOBS) -O2 -Wno-fatal -Wno-style -Wno-lint \
  -Wno-PINCONNECTEMPTY -Wno-ASSIGNDLY -Wno-DECLFILENAME -Wno-UNUSED \
  -Wno-UNOPTFLAT -Wno-BLKANDNBLK --unroll-count 256 \
  -CFLAGS "-O1" --top-module tb_top --prefix Vtb_top $(VERILATOR_EXTRA)
VERILATOR_RTL_FLAGS := $(ETH_DEFS_verilator)

.PHONY: all syn syn_gate regress regress_all regress_summary coverage sim sim_verilator sim_questa sim_vcs sim_xcelium \
  run_verilator run_questa run_vcs run_xcelium sw verilate questa_build vcs_build xcelium_build clean
all: regress

BUILD_verilator := verilate
BUILD_questa    := questa_build
BUILD_vcs       := vcs_build
BUILD_xcelium   := xcelium_build

# Everything is built first, then up to PARALLEL tests run from that one shared build. The runs
# use run_<sim>, which has no build steps, so clock skew on the shared folder can't start several
# rebuilds at once. Every test runs even after a failure, then the target fails if any test failed.
regress:
	@mkdir -p $(RUN_DIR)
	@rm -f $(RESULTS_DIR)/summary_$(SIM)$(VIEW).txt
	@for t in $(TESTS); do $(MAKE) --no-print-directory sw TEST=$$t || exit 1; done
	@$(MAKE) --no-print-directory $(BUILD_$(SIM))
	@printf '%s\n' $(TESTS) | xargs -P $(PARALLEL) -I{} sh -c \
	  '$(MAKE) --no-print-directory run_$(SIM) WAVES=$(REGRESS_WAVES) TEST={} > $(RUN_DIR)/{}.out 2>&1; echo "finished {}"'
	@$(MAKE) --no-print-directory regress_summary

# Both simulators together, sharing up to PARALLEL slots across all their runs.
regress_all:
	@mkdir -p $(RESULTS_DIR)/verilator$(VIEW) $(RESULTS_DIR)/questa$(VIEW)
	@rm -f $(RESULTS_DIR)/summary_verilator$(VIEW).txt $(RESULTS_DIR)/summary_questa$(VIEW).txt
	@for t in $(TESTS); do $(MAKE) --no-print-directory sw TEST=$$t || exit 1; done
	@$(MAKE) --no-print-directory verilate
	@$(MAKE) --no-print-directory questa_build
	@for s in verilator questa; do for t in $(TESTS); do echo $$s:$$t; done; done | xargs -P $(PARALLEL) -I{} sh -c \
	  'x={}; s=$${x%%:*}; t=$${x##*:}; $(MAKE) --no-print-directory run_$$s SIM=$$s WAVES=$(REGRESS_WAVES) TEST=$$t > $(RESULTS_DIR)/$$s$(VIEW)/$$t.out 2>&1; echo "finished {}"'
	@failed=0; \
	$(MAKE) --no-print-directory regress_summary SIM=verilator || failed=1; \
	$(MAKE) --no-print-directory regress_summary SIM=questa || failed=1; \
	if cmp -s $(RESULTS_DIR)/summary_verilator$(VIEW).txt $(RESULTS_DIR)/summary_questa$(VIEW).txt; then \
	  echo "=== simulators agree on every cycle count ==="; \
	else echo "=== simulators differ ==="; failed=1; fi; \
	exit $$failed

regress_summary:
	@summary=$(RESULTS_DIR)/summary_$(SIM)$(VIEW).txt; : > $$summary; failed=0; \
	for t in $(TESTS); do \
	  log=$(RUN_DIR)/$$t/sim.log; \
	  if [ -d $(RUN_DIR)/$$t ]; then cat $(RUN_DIR)/$$t.out > $(RUN_DIR)/$$t/run.out; fi; \
	  rm -f $(RUN_DIR)/$$t.out; \
	  if grep -qE '^(# )?\[TOP\] VERDICT: PASS' $$log; then r=PASS; else r=FAIL; failed=1; fi; \
	  echo "$$t $$r $$(grep -oE '[0-9]+ cycles' $$log | tail -1)" >> $$summary; \
	done; \
	cat $$summary; \
	if [ $$failed = 0 ]; then echo "=== all tests passed: $(TESTS) ==="; fi; \
	exit $$failed

sim: sim_$(SIM)

sw: $(SW_DIR)/boot_rom.hex $(SW_DIR)/$(TEST).hex

$(SW_DIR)/boot_rom.elf: $(C_DIR)/boot_rom.S
	@mkdir -p $(@D)
	$(CROSS)gcc $(SW_FLAGS) -Wl,-Ttext=0x10000 -o $@ $<

$(SW_DIR)/$(TEST).elf: $(C_DIR)/crt0.S $(C_DIR)/adr_lib.c $(C_DIR)/adr_lib.h $(C_DIR)/$(TEST).c $(C_DIR)/link.ld
	@mkdir -p $(@D)
	$(CROSS)gcc $(SW_FLAGS) $(SYNC_DEFS_$(TB)_$(TB_SYNC)) -T $(C_DIR)/link.ld -o $@ $(C_DIR)/crt0.S $(C_DIR)/adr_lib.c $(C_DIR)/$(TEST).c

$(SW_DIR)/%.hex: $(SW_DIR)/%.elf scripts/bin2hex64.py
	$(CROSS)objcopy -O binary $< $(basename $@).bin
	python3 scripts/bin2hex64.py $(basename $@).bin $@

verilate: $(VERILATOR_DIR)/Vtb_top

SIM_SOURCES := sim/adr_soc.f sim/cva6.f sim/usb_files.sv \
  $(shell find rtl/adr_soc rtl/adr_ip tb/common tb/verilator -name '*.sv' -not -path '*/uvm/*') \
  $(wildcard rtl/third_party_ip/*/tb/*.sv rtl/third_party_ip/*/backport/*.sv)

$(BUILD_DIR)/verilator$(ETHVIEW)/Vtb_top: sim/verilator.vlt $(SIM_SOURCES)
	@mkdir -p $(@D)
	$(LIMIT) verilator $(VERILATOR_FLAGS) $(VERILATOR_RTL_FLAGS) --Mdir $(@D) $(TP)/cva6/verilator_config.vlt sim/verilator.vlt -f sim/adr_soc.f

syn/out/adr_soc_top_syn.v:
	@echo 'No netlist yet: run make syn first (about 2 hours).'; exit 1

# Gate level: the netlist is one flat module, so it is built with the same flags and its own folder.
NETLIST_SOURCES := sim/adr_soc_netlist.f syn/out/adr_soc_top_syn.v rtl/adr_soc/mem/adr_mem_model.sv $(wildcard tb/common/*.sv tb/verilator/*.sv) \
  $(wildcard rtl/adr_ip/*/tb/*.sv rtl/third_party_ip/*/tb/*.sv)
$(BUILD_DIR)/verilator_netlist/Vtb_top: $(NETLIST_SOURCES)
	@mkdir -p $(@D)
	$(LIMIT) verilator $(VERILATOR_FLAGS) --Mdir $(@D) -f sim/adr_soc_netlist.f

# A run passes only if it prints the verdict line, so a crash or a hang cannot count as a pass.
sim_verilator: sw verilate run_verilator

run_verilator:
	rm -rf $(RUN_DIR)/$(TEST)
	mkdir -p $(RUN_DIR)/$(TEST)
	cd $(RUN_DIR)/$(TEST) && $(LIMIT) $(VERILATOR_DIR)/Vtb_top \
	  +rom=$(SW_DIR)/boot_rom.hex +sram=$(SW_DIR)/$(TEST).hex $(TEST_ARGS_$(TEST)) $(SIM_ARGS) \
	  > sim.log 2>&1
	grep -q '^\[TOP\] VERDICT: PASS' $(RUN_DIR)/$(TEST)/sim.log

# One compile, shared by every test. +acc keeps all signals visible for waveforms.
questa_build: $(QUESTA_DIR)/.built

# +acc=bcglnprst, not plain +acc: without the g flag, vopt 2021.2_1 crashes on this design.
# Suppressing 7033 is safe: usbdev.sv drives different fields of one struct from two always_comb blocks.
# Suppressing 13276 is safe: those errors are in apb_to_obi generate branches that are not built.
$(BUILD_DIR)/questa$(ETHVIEW)/.built: sim/questa.f $(wildcard sim/compat_fixes/*.sv) $(SIM_SOURCES)
	@mkdir -p $(@D)
	rm -f $@
	cd $(@D) && rm -rf work && vlib work
	cd $(@D) && $(LIMIT) vlog -sv -work work -timescale 1ns/1ps -suppress 7033 $(ETH_DEFS_questa) -f $(ROOT)/sim/questa.f -l vlog.log
	cd $(@D) && $(LIMIT) vopt -work work +acc=bcglnprst $(COVER_VOPT_$(COVER)) -suppress 13276 tb_top -o tb_top_opt -l vopt.log
	touch $@

# UVM bench on Questa: the Questa design list plus the UVM files, against Questa's precompiled UVM 1.2
# (Questa links UVM 1.1d unless told otherwise). Same optimised top name, so run_questa serves both.
QUESTA_HOME ?= $(abspath $(dir $(shell which vsim 2>/dev/null))..)
UVM_HOME    ?= $(QUESTA_HOME)/uvm-1.2
UVM_SRC     ?= $(QUESTA_HOME)/verilog_src/uvm-1.2/src
UVM_SOURCES := sim/adr_soc_uvm.f $(shell find tb/uvm rtl/adr_ip rtl/third_party_ip -path '*/uvm/*' \( -name '*.sv' -o -name '*.svh' \))
$(BUILD_DIR)/questa_uvm$(ETHVIEW)/.built: sim/questa.f $(wildcard sim/compat_fixes/*.sv) $(SIM_SOURCES) $(UVM_SOURCES)
	@mkdir -p $(@D)
	rm -f $@
	cd $(@D) && rm -rf work && vlib work
	cd $(@D) && $(LIMIT) vlog -sv -work work -L $(UVM_HOME) +incdir+$(UVM_SRC) -timescale 1ns/1ps -suppress 7033 $(ETH_DEFS_questa) -f $(ROOT)/sim/questa.f -f $(ROOT)/sim/adr_soc_uvm.f -l vlog.log
	cd $(@D) && $(LIMIT) vopt -work work -L $(UVM_HOME) +acc=bcglnprst -suppress 13276 adr_soc_uvm_top adr_soc_probes_bind -o tb_top_opt -l vopt.log
	touch $@

# Gate level on Questa: same steps from the netlist file list, in its own folder.
$(BUILD_DIR)/questa_netlist/.built: $(NETLIST_SOURCES)
	@mkdir -p $(@D)
	rm -f $@
	cd $(@D) && rm -rf work && vlib work
	cd $(@D) && $(LIMIT) vlog -sv -work work -timescale 1ns/1ps -f $(ROOT)/sim/adr_soc_netlist.f -l vlog.log
	cd $(@D) && $(LIMIT) vopt -work work +acc=bcglnprst tb_top -o tb_top_opt -l vopt.log
	touch $@

QUESTA_DO_1 := log -r /*; run -all; quit -f
QUESTA_DO_0 := run -all; quit -f

# Only make coverage sets COVER=1. It uses its own build folder, as a coverage build differs from a normal one.
COVER_VOPT_1 := +cover=bcesft
COVER_VSIM_1 := -coverage
COVER_DO_1   = coverage save -onexit -testname $(TEST) cov.ucdb;

# Each test only loads its own program into the shared build, in its own results folder.
sim_questa: sw questa_build run_questa

run_questa:
	rm -rf $(RUN_DIR)/$(TEST)
	mkdir -p $(RUN_DIR)/$(TEST)
	cd $(RUN_DIR)/$(TEST) && $(LIMIT) vsim -c -lib $(QUESTA_DIR)/work tb_top_opt $(COVER_VSIM_$(COVER)) $(QUESTA_VSIM_$(TB)) -suppress 7033 -wlf waves.wlf -l sim.log \
	  +rom=$(SW_DIR)/boot_rom.hex +sram=$(SW_DIR)/$(TEST).hex $(TEST_ARGS_$(TEST)) $(SIM_ARGS) \
	  -do "$(COVER_DO_$(COVER)) $(QUESTA_DO_$(WAVES))" > /dev/null
	grep -q '^# \[TOP\] VERDICT: PASS' $(RUN_DIR)/$(TEST)/sim.log

# ---- VCS and Xcelium ----------------------------------------------------------------------------
# Set up like the Questa flow: one shared build per simulator and bench, every test in its own
# results folder, the same plusargs, and a pass only on the verdict line. The design file list is
# sim/vcs.f or sim/xcelium.f; TB=uvm adds sim/adr_soc_uvm.f and the UVM 1.2 library that ships with
# the simulator; NETLIST=1 uses sim/adr_soc_netlist.f. Waveforms (WAVES=1) are VPD for VCS and SHM
# for Xcelium, in the test's results folder.
# These simulators stop on a module defined twice, so the design list is generated per build with
# CVA6's write buffer replaced by its fixed copy (sim/compat_fixes/); the other two fixed copies
# replace modules that are otherwise found through -y, so sim/<sim>.f just lists them.
CS_DIR         = $(BUILD_DIR)/$(SIM)$(VIEW)
CS_UPSTREAM_WBUFFER := /rtl/third_party_ip/cva6/core/cache_subsystem/wt_dcache_wbuffer.sv
CS_FLIST_sv_0  = -f $(CS_DIR)/design.f -f $(ROOT)/sim/$(SIM).f
CS_FLIST_uvm_0 = $(CS_FLIST_sv_0) -f $(ROOT)/sim/adr_soc_uvm.f
CS_FLIST_sv_1  = -f $(ROOT)/sim/adr_soc_netlist.f
CS_FLIST       = $(CS_FLIST_$(TB)_$(NETLIST))
CS_DEPS_0      = $(CS_DIR)/design.f sim/$(SIM).f $(wildcard sim/compat_fixes/*.sv) $(SIM_SOURCES) $(if $(filter uvm,$(TB)),$(UVM_SOURCES))
CS_DEPS_1      = $(NETLIST_SOURCES)
CS_TOPS_sv     := tb_top
CS_TOPS_uvm    := adr_soc_uvm_top adr_soc_probes_bind
CS_TOP         = $(firstword $(CS_TOPS_$(TB)))
CS_PLUSARGS_uvm = +UVM_TESTNAME=$(UVM_TEST) +UVM_NO_RELNOTES $(if $(filter 0,$(TB_SYNC)),+no_c_sync)
CS_RUN_ARGS    = +rom=$(SW_DIR)/boot_rom.hex +sram=$(SW_DIR)/$(TEST).hex $(TEST_ARGS_$(TEST)) $(CS_PLUSARGS_$(TB)) $(SIM_ARGS)

$(BUILD_DIR)/%/design.f: sim/adr_soc.f sim/cva6.f
	@mkdir -p $(@D)
	sed 's#$(CS_UPSTREAM_WBUFFER)#/sim/compat_fixes/wt_dcache_wbuffer.sv#' sim/cva6.f > $(@D)/cva6.f
	sed 's#^-f .*/sim/cva6.f#-f $(@D)/cva6.f#' sim/adr_soc.f > $@

# VCS: compile and elaborate once into simv; UVM from -ntb_opts uvm-1.2.
VCS_UVM_uvm := -ntb_opts uvm-1.2
VCS_FLAGS   ?= -full64 -sverilog -timescale=1ns/1ps -debug_access+all +lint=TFIPC-L -j$(JOBS)
VCS_DO_1    := dump -file waves.vpd -type VPD; dump -add / -depth 0; run; quit
VCS_DO_0    := run; quit
vcs_build: $(VCS_DIR)/simv

$(VCS_DIR)/simv: $(CS_DEPS_$(NETLIST))
	@mkdir -p $(@D)
	cd $(@D) && $(LIMIT) vcs $(VCS_FLAGS) $(VCS_UVM_$(TB)) $(ETH_DEFS_vcs) $(CS_FLIST) \
	  $(addprefix -top ,$(CS_TOPS_$(TB))) -o simv -l vcs_build.log

sim_vcs: sw vcs_build run_vcs

run_vcs:
	rm -rf $(RUN_DIR)/$(TEST)
	mkdir -p $(RUN_DIR)/$(TEST)
	cd $(RUN_DIR)/$(TEST) && echo '$(VCS_DO_$(WAVES))' > run.tcl && \
	  $(LIMIT) $(VCS_DIR)/simv -l sim.log $(CS_RUN_ARGS) -ucli -do run.tcl > /dev/null 2>&1
	grep -q '^\[TOP\] VERDICT: PASS' $(RUN_DIR)/$(TEST)/sim.log

# Xcelium: elaborate once into a snapshot in the build folder, then run it per test with -R.
XRUN_UVM_uvm := -uvm -uvmhome CDNS-1.2
XRUN_FLAGS   ?= -64bit -sv -timescale 1ns/1ps -access +rwc
XRUN_DO_1     = database -open waves -shm -default; probe -create $(CS_TOP) -all -depth all -database waves; run; exit
XRUN_DO_0    := run; exit
xcelium_build: $(XCELIUM_DIR)/.built

$(XCELIUM_DIR)/.built: $(CS_DEPS_$(NETLIST))
	@mkdir -p $(@D)
	rm -f $@
	cd $(@D) && $(LIMIT) xrun $(XRUN_FLAGS) $(XRUN_UVM_$(TB)) $(ETH_DEFS_xcelium) $(CS_FLIST) \
	  $(addprefix -top ,$(CS_TOPS_$(TB))) -xmlibdirname $(@D)/xcelium.d -elaborate -l xrun_build.log
	touch $@

sim_xcelium: sw xcelium_build run_xcelium

run_xcelium:
	rm -rf $(RUN_DIR)/$(TEST)
	mkdir -p $(RUN_DIR)/$(TEST)
	cd $(RUN_DIR)/$(TEST) && echo '$(XRUN_DO_$(WAVES))' > run.tcl && \
	  $(LIMIT) xrun -64bit -R -xmlibdirname $(XCELIUM_DIR)/xcelium.d $(XRUN_UVM_$(TB)) -l sim.log $(CS_RUN_ARGS) \
	  -input run.tcl > /dev/null 2>&1
	grep -q '^\[TOP\] VERDICT: PASS' $(RUN_DIR)/$(TEST)/sim.log

COVER_DIR := $(RESULTS_DIR)/coverage
OWN_MODULES := $(basename $(notdir $(wildcard rtl/adr_ip/*/rtl/*.sv) $(filter-out %_pkg.sv,$(wildcard rtl/adr_soc/*.sv rtl/adr_soc/*/*.sv))))

# Runs every test with waveforms off, then merges them. Stops without a report if a test fails.
coverage:
	$(MAKE) --no-print-directory regress SIM=questa COVER=1 BUILD_DIR=$(BUILD_DIR)/coverage RESULTS_DIR=$(COVER_DIR)
	cd $(COVER_DIR) && vcover merge merged.ucdb $(TESTS:%=questa/%/cov.ucdb)
	cd $(COVER_DIR) && vcover report -summary merged.ucdb > summary.txt
	cd $(COVER_DIR) && for m in $(OWN_MODULES); do vcover report -du=$$m merged.ucdb; done > own_rtl.txt

# Full-chip synthesis with Yosys (oss-cad-suite, yosys-slang), generic gates, no PDK.
# Results go to syn/out/, beside results/; `make clean` does not touch them.
# syn runs both steps (about 2 h); syn_gate reruns only step 2 from the saved checkpoint (about 15 min).
YOSYS ?= $(firstword $(wildcard $(HOME)/tools/oss-cad-suite/bin/yosys) yosys)
# Synthesis reads its own copy of the simulation file lists: without the testbench files (paths
# containing /tb/), as it builds only adr_soc_top and slang rejects bench code that the simulators
# accept; and with syn/fixes/tc_sram_wrapper_syn.sv instead of CVA6's tc_sram_wrapper.sv, because
# yosys-slang drops that wrapper's type-parameter ports, which removed the cache memories.
SYN_CVA6_SRAM_WRAPPER := /rtl/third_party_ip/cva6/common/local/util/tc_sram_wrapper.sv
syn:
	@mkdir -p syn/out
	sed 's#$(SYN_CVA6_SRAM_WRAPPER)#/syn/fixes/tc_sram_wrapper_syn.sv#' sim/cva6.f > syn/out/cva6_syn.f
	grep -v '/tb/' sim/adr_soc.f | sed 's#/sim/cva6.f#/syn/out/cva6_syn.f#' > syn/out/adr_soc_syn.f
	cd $(ROOT) && ADR_ROOT=$(ROOT) $(LIMIT) $(YOSYS) -q -l syn/out/coarse.log syn/scripts/adr_soc_coarse.ys
	$(MAKE) syn_gate

syn_gate:
	cd $(ROOT) && $(LIMIT) $(YOSYS) -q -l syn/out/gate.log syn/scripts/adr_soc_gate.ys

clean:
	rm -rf $(BUILD_DIR)
