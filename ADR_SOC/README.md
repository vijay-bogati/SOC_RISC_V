# ADR SoC

An RV64GC SoC built from open-source IP and our own integration code, digital only for now.

ADR stands for *Aadhar*, meaning "foundation". ADR is a foundation, or reference, SoC: it helps industry engineers and technology enthusiasts understand how an SoC is built, and it is an open-source base from which larger, application-specific SoCs can be built, for consumer and multimedia, communications and networking, AI and compute, edge and embedded, automotive, healthcare, aerospace and security, and education and open hardware. `docs/MICROARCHITECTURE.md` section 1 lists the domains and what a derived SoC typically adds on top of ADR.

| Area | Blocks |
|---|---|
| CPU and debug | CVA6 RV64GC, JTAG debug |
| Bus and memory | 64-bit AXI4 crossbar, boot ROM, SRAM, DDR4 controller, bus error monitor |
| Interrupts and timers | PLIC, CLINT, 8-channel timer, PWM, watchdog, always-on timer |
| Serial and I/O | 2 UARTs, SPI, QSPI, I2C, GPIO, pin mux |
| High-speed | USB 2.0 full-speed device, 10G/25G Ethernet MAC and PCS |
| System | DMA, AES, system control, ADC controller, OTP controller |
| Placeholders | PCIe, MIPI and graphics stubs, outside the build |

Everything is verified in simulation, with self-checking C tests running on the CPU. The SoC regression passes on **Verilator 5.020** (open source); see `docs/STATUS.md` and `results/`. The same Makefile drives Questa, Synopsys VCS and Cadence Xcelium for anyone who has those tools, and a UVM environment is included for them. DDR4 uses a simulation memory model with no real PHY, and the USB and Ethernet analog parts are outside the SoC. `docs/MICROARCHITECTURE.md` has the design, and `docs/LIMITATIONS.md` has what isn't done or proven.

## Layout

| Folder | Contents |
|---|---|
| `rtl/adr_soc/` | SoC package and top level (connections only), with one folder per subsystem: `rst/`, `core/`, `debug/`, `interconnect/`, `mem/`, `lsio/`, `periph/`. The hierarchy is in `docs/MICROARCHITECTURE.md` section 2 |
| `rtl/adr_ip/<ip>/` | Our IP blocks, each with `rtl/` and `tb/` |
| `rtl/third_party_ip/<ip>/` | Open-source blocks, unmodified apart from what `docs/THIRD_PARTY.md` records, each with `rtl/` and `tb/` |
| `rtl/third_party_ip/common/` | Open-source libraries shared by several blocks |
| `rtl/third_party_ip/cva6/` | The CVA6 CPU |
| `rtl/placeholders/` | Stubs for PCIe, MIPI and graphics, outside the build |
| `tb/common/` | Testbench definitions shared by both SoC benches (`adr_tb_pkg.sv`) |
| `tb/verilator/` | The SoC bench, proven on Verilator: `tb_top.sv` with the JTAG debugger for the `debug` test, `tb_adr_soc.sv` with the board |
| `tb/verilator/c_tests/` | Its boot ROM stub, start-up code and C tests |
| `tb/uvm/` | The UVM SoC environment (a simulator with UVM 1.2): top, environment, `uvm_tests/`, `uvm_sequence/` and its own `c_tests/` |
| `sim/` | File lists and simulator settings for Verilator, Questa, VCS and Xcelium, fixed copies of three third-party files for the commercial simulators, and `usb_files.sv`. Run commands: `sim/README.md` |
| `syn/` | Yosys synthesis scripts (generic gates) |
| `scripts/` | Build helpers, the DDR4 core generator, the PDF builders, `ip_ports.py`, which prints a module's port table for the IP documents, and `wave_svg.py` and `block_svg.py`, which draw the timing and block diagrams of the IP documents from small JSON files kept next to each SVG in `docs/ip/*/images/` |
| `docs/` | Microarchitecture specification, feature list, status, limitations and third-party records, with PDF copies in `docs/pdf/`. The testbench plans are PDF only: `docs/pdf/ADR_VERIFICATION_PLAN.pdf` (top document), `ADR_TEST_PLAN.pdf`, `ADR_COVERAGE_PLAN.pdf` and `ADR_ASSERTIONS_PLAN.pdf` |
| `docs/ip/` | One document per block, including AXI4 and APB: `protocols/`, `adr_soc/`, `adr_ip/`, and `third_party_ip/<repo>/` with an ADR note and the upstream project's own documents. Start at `docs/ip/README.md` |
| `results/` | Sample results of the Verilator regression |

## Requirements

- Verilator 5.020 (the version the regression is proven on)
- `riscv64-unknown-elf-gcc`
- `make`, `g++` and `python3`
- Optional: Questa, VCS or Xcelium with UVM 1.2, for the commercial-simulator flows and the UVM environment
- Optional: Yosys from oss-cad-suite (with yosys-slang), for synthesis and gate-level runs

## Run

Every command runs from this folder. Verilator is the default simulator; add `SIM=questa`, `SIM=vcs` or `SIM=xcelium` to use another one. Each simulator has one shared build, which every test uses, and each test has its own results folder. `sim/README.md` lists every command and switch.

| Purpose | Command |
|---|---|
| One test | `make sim TEST=smoke` |
| The regression (11 tests, one at a time) | `make regress` |
| Only some tests | `make regress TESTS="eth misc sys"` |
| A lower cycle limit, so a hang shows up sooner | `make sim TEST=irq SIM_ARGS=+max_cycles=1000000` |
| Verilator waveforms (FST) | see `sim/README.md`, "Verilator" |
| Ethernet at 10G instead of 25G | add `ETH_RATE=10` |
| Gate-level netlist (after `make syn`) | add `NETLIST=1` |
| Another simulator | add `SIM=questa`, `SIM=vcs` or `SIM=xcelium` |
| The UVM environment | `make sim SIM=<questa, vcs or xcelium> TB=uvm TEST=irq` |
| Synthesis | `make syn` (about 2 hours), then `make syn_gate` to rerun the gate step |

`make regress` runs one test at a time by default (`PARALLEL=1`), with 2 compile jobs (`JOBS=2`), and caps every build and run at 8 GB (`MEM_MAX`), because a Verilator build of the full SoC peaks near 7 GB. Raise these on a larger machine. It builds anything missing first, runs every test even after a failure, and succeeds only if they all pass. A test passes only on its C self-checks and the bench's `[TOP] VERDICT: PASS` line, so a crash or a hang can never count as a pass.

### Where things go

| Output | Location |
|---|---|
| Shared builds | `~/.cache/adr_soc_build`. Change it with `BUILD_DIR=<path>`, and clear it with `make clean` |
| One test's results | `results/<sim>/<test>/`, for example `results/verilator/irq/`. Change `results` with `RESULTS_DIR=<path>` |
| In each test's folder | `sim.log` and the CPU trace logs; waveforms when they are on |
| Summary of a regression | `results/summary_<sim>.txt`: test, PASS or FAIL, cycle count |
| Synthesis (Yosys, generic gates) | `syn/out/`: gate netlist `adr_soc_top_syn.v`, checkpoint, gate counts, checks. `make clean` does not touch it |

A run replaces its test's folder, so a single run overwrites that test's regression results.

## PDF documents

The `docs/pdf/` folder has PDF copies of these documents. The microarchitecture specification includes the diagrams in `docs/images/`. After changing a document, rebuild them:

```
python3 -m venv ~/.cache/adr_docs_env
~/.cache/adr_docs_env/bin/pip install weasyprint markdown-it-py docutils openpyxl
~/.cache/adr_docs_env/bin/python scripts/docs_to_pdf.py
~/.cache/adr_docs_env/bin/python scripts/ip_docs_to_pdf.py
```

The verification, test, coverage and assertion plans are PDF only.

`scripts/ip_docs_to_pdf.py` writes one PDF per block to `docs/pdf/ip/`, in the same folders as `docs/ip/`. A third-party block's PDF holds the ADR note, then the upstream project's own documents and its license. `ip_docs_to_pdf.py own` rebuilds only our own documents.
