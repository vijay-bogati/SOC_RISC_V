# Running the ADR SoC simulations

All commands run from the project root (the folder with the `Makefile`). Verilator is the default
simulator, and the SoC test regression is proven on it. The same Makefile also drives Questa, VCS
and Xcelium (`SIM=questa`, `SIM=vcs`, `SIM=xcelium`) for anyone who has those tools. The full
background is in the top-level `README.md`, section "Run".

## Tools

| Tool | Status | Needed for |
|---|---|---|
| Verilator 5.020 | proven: the SoC test regression passes | `SIM=verilator` (default) |
| Questa (with its UVM 1.2) | flow provided | `SIM=questa`, the UVM bench (`TB=uvm`), `make coverage` |
| Synopsys VCS (with its UVM 1.2) | flow provided, not run here | `SIM=vcs`, the UVM bench (`TB=uvm`) |
| Cadence Xcelium (with its UVM 1.2) | flow provided, not run here | `SIM=xcelium`, the UVM bench (`TB=uvm`) |
| `riscv64-unknown-elf-gcc` | | the C test programs (built automatically) |
| `make`, `g++`, `python3` | | the flow |
| Yosys (oss-cad-suite, yosys-slang) | | only `make syn`, for gate-level runs |

The Verilator bench (`tb/verilator/`) runs on all four simulators. The UVM bench (`tb/uvm/`) needs a
simulator with UVM 1.2, so it does not run on Verilator.

## Files in this folder

| File | Used by |
|---|---|
| `adr_soc.f` | RTL file list for every simulator and for synthesis |
| `cva6.f` | CVA6 CPU file list (included by `adr_soc.f`) |
| `usb_files.sv` | the OpenTitan USB device sources, compiled as one unit |
| `adr_soc_netlist.f` | gate-level runs (`NETLIST=1`) |
| `adr_soc_uvm.f` | the UVM bench (`TB=uvm`), after the simulator's design list |
| `questa.f` | Questa design list: `adr_soc.f` plus the fixed copies in `compat_fixes/` |
| `vcs.f`, `xcelium.f` | VCS and Xcelium additions: library extensions and two of the fixed copies (the Makefile generates the design list with the third) |
| `compat_fixes/` | fixed copies of three third-party files for the commercial simulators (see `docs/THIRD_PARTY.md`) |
| `verilator.vlt` | Verilator lint waivers for the third-party folders |
| `waves/adr_wave_dump.sv`, `waves/adr_wave_dump_lsio.sv`, `waves/adr_wave_lsio.vlt` | optional Verilator waveform dumps, whole SoC or low-speed I/O only (not in any file list) |

## Tests

| Default regression (`TESTS`) | `smoke irq debug periph serial timers aes sys eth usb ddr` |
|---|---|
| Also available with `TEST=` | `i2c amo dma misc uart_i2c` |
| UVM bench only | `sba` (debug system bus access, `adr_sba_test`) |

The C programs are in `tb/verilator/c_tests/` (Verilator bench) and `tb/uvm/c_tests/` (UVM bench).
A test passes when its log has `[TOP] VERDICT: PASS`.

## Verilator

| Purpose | Command |
|---|---|
| One test (builds what is missing first) | `make sim TEST=irq` |
| Quick I2C check | `make sim TEST=i2c` |
| Full regression | `make regress` |
| Some tests only | `make regress TESTS="eth misc sys"` |
| Lower cycle limit, so a hang shows sooner | `make sim TEST=irq SIM_ARGS=+max_cycles=1000000` |
| Log CPU bus and APB activity | `make sim TEST=irq BUILD_DIR=/tmp/adr_trace VERILATOR_EXTRA=+define+ADR_TB_TRACE` |
| Gate-level netlist (after `make syn`) | `make sim TEST=smoke NETLIST=1`, `make regress NETLIST=1` |
| Ethernet at 10G instead of 25G | add `ETH_RATE=10` |
| Build only | `make verilate` |
| Waveforms (FST, open with GTKWave) | `make sim TEST=uart_i2c BUILD_DIR=$HOME/.cache/adr_soc_build_waves VERILATOR_EXTRA="--trace-fst --trace-structs sim/waves/adr_wave_dump.sv"` |
| Waveforms of the low-speed I/O only (small file) | `make sim TEST=uart_i2c BUILD_DIR=$HOME/.cache/adr_soc_build_waves_lsio VERILATOR_EXTRA="--trace-fst --trace-structs sim/waves/adr_wave_lsio.vlt sim/waves/adr_wave_dump_lsio.sv"` |

Results: `results/verilator/<test>/sim.log`; regression summary `results/summary_verilator.txt`
(test, PASS/FAIL, cycle count). Verilator writes to `sim.log`, not to the screen.

The Verilator bench dumps no waveforms by default. The waveform command above builds a separate
copy with `sim/waves/adr_wave_dump.sv` bound into `tb_top` (own `BUILD_DIR`, so the normal build is
not mixed with it) and writes `waves.fst` into the test's results folder. Dumping the whole SoC slows
the run and makes a large file, so use it for single tests.

## Commercial simulators: Questa, VCS, Xcelium

The three flows are set up the same way: one shared build per simulator and bench, each test in
`results/<sim>/<test>/` with its own `sim.log`, the same plusargs, and a pass only on the verdict
line. Every test should give the same cycle count as on Verilator.

| Purpose | Questa | VCS | Xcelium |
|---|---|---|---|
| One test, with waveforms | `make sim SIM=questa TEST=irq` | `make sim SIM=vcs TEST=irq` | `make sim SIM=xcelium TEST=irq` |
| One test, no waveforms | add `WAVES=0` | add `WAVES=0` | add `WAVES=0` |
| Full regression (waveforms off) | `make regress SIM=questa` | `make regress SIM=vcs` | `make regress SIM=xcelium` |
| Gate-level netlist (after `make syn`) | add `NETLIST=1` | add `NETLIST=1` | add `NETLIST=1` |
| Build only | `make questa_build SIM=questa` | `make vcs_build SIM=vcs` | `make xcelium_build SIM=xcelium` |
| Waveform file | `waves.wlf` | `waves.vpd` | `waves.shm/` |
| Simulator command | `vlog`, `vopt`, `vsim` | `vcs`, then `simv` | `xrun -elaborate`, then `xrun -R` |

Questa only: `make coverage` (a regression with code coverage, merged report in `results/coverage/`)
and `make regress_all` (Verilator and Questa together, then a cycle-count comparison).

The VCS and Xcelium flows use each simulator's own UVM 1.2 (`-ntb_opts uvm-1.2`,
`-uvm -uvmhome CDNS-1.2`). Their compile options are in the Makefile (`VCS_FLAGS`, `XRUN_FLAGS`) and
can be overridden on the command line, for example `make sim SIM=vcs TEST=smoke VCS_FLAGS="..."`.

### Large waveforms

`WAVES=1` records every signal of the SoC. A full test gives a waveform of more than 1 GB, mostly from
the Ethernet SerDes data, which toggles every cycle, and opening it can hang a viewer. Record only what
you need by overriding the simulator's run script on the command line; the run and its cycle count
stay the same. For example:

- Questa: `QUESTA_DO_1="log -r /tb_top/i_bench/i_dut/i_lsio/*; log -r /tb_top/i_bench/i_i2c_dev/*; run -all; quit -f"`
- VCS: `VCS_DO_1="dump -file waves.vpd -type VPD; dump -add /tb_top/i_bench/i_dut/i_lsio -depth 0; run; quit"`
- Xcelium: `XRUN_DO_1="database -open waves -shm -default; probe -create tb_top.i_bench.i_dut.i_lsio -all -depth all; run; exit"`

With Questa, an existing file can also be cut down with `wlfman filter -r <scope> ... -o small.wlf waves.wlf`.

## UVM bench (`TB=uvm`, Questa, VCS or Xcelium)

| Purpose | Command (shown for Questa; use `SIM=vcs` or `SIM=xcelium` the same way) |
|---|---|
| One test | `make sim SIM=questa TB=uvm TEST=irq` |
| Without waveforms | `make sim SIM=questa TB=uvm TEST=irq WAVES=0` |
| Debug system bus access test | `make sim SIM=questa TB=uvm TEST=sba` |
| A particular UVM test | add `UVM_TEST=<name>` (default `adr_soc_base_test`) |
| Regression | `make regress SIM=questa TB=uvm` (loopbacks off, so `periph`, `timers` and `eth` fail; run those one at a time with their loopbacks) |

Run-time options, given with `SIM_ARGS="..."`:

| Option | Effect |
|---|---|
| `+loopback_uart1`, `+loopback_gpio`, `+loopback_pwm`, `+loopback_eth` | connect that interface's transmit to its receive side. Give each test only its own: `periph` (gpio, uart1), `timers` (gpio, pwm), `eth` (eth), `misc` (gpio, pwm, uart1), `uart_i2c` (uart1) |
| `+i2c_stretch_ns=<n>` | the I2C slave agent stretches SCL for n ns once per byte |
| `+no_fabric_mon` | no AXI/APB protocol monitors and no scoreboards (faster) |
| `+no_cov` | no functional coverage |
| `+no_sva` | bench assertions off (debug only, never in a regression) |
| `+max_cycles=<n>` | timeout in clock cycles |

Example: `make sim SIM=questa TB=uvm TEST=periph WAVES=0 SIM_ARGS="+loopback_gpio +loopback_uart1"`.

Results: `results/<sim>_uvm/<test>/`; summary `results/summary_<sim>_uvm.txt`.

## Common switches

| Switch | Default | Meaning |
|---|---|---|
| `SIM` | `verilator` | `verilator`, `questa`, `vcs` or `xcelium` |
| `TB` | `sv` | `sv` (SystemVerilog bench) or `uvm` (Questa, VCS or Xcelium) |
| `TEST` / `TESTS` | `smoke` / list above | one test / the regression list |
| `NETLIST` | `0` | `1` runs on the synthesized netlist `syn/out/adr_soc_top_syn.v` |
| `ETH_RATE` | `25` | `10` builds the Ethernet block for 10G |
| `WAVES`, `REGRESS_WAVES` | `1`, `0` | commercial-simulator waveforms for single runs / regressions |
| `PARALLEL` | `1` | tests run at once in a regression (each commercial-simulator run needs a license) |
| `JOBS` | `2` | compile jobs per build |
| `MEM_MAX` | `8G` | memory cap for each build and run |
| `BUILD_DIR` | `~/.cache/adr_soc_build` | shared builds; `make clean` removes it |
| `RESULTS_DIR` | `results` | where test results go |

Each option gets its own build and results folder (for example `results/vcs_netlist/`,
`results/verilator_eth10g/`), so runs with different options can be kept and compared.

## Synthesis (for gate-level runs)

| Purpose | Command |
|---|---|
| Full synthesis, generic gates (about 2 h) | `make syn` |
| Rerun the gate step from the checkpoint (about 15 min) | `make syn_gate` |

Output in `syn/out/`; `make clean` does not touch it.
