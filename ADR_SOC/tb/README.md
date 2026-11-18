# tb/ - SoC testbenches

| Folder | Bench | Runs on |
|---|---|---|
| [`verilator/`](verilator/) | The SoC bench: the chip, the board around it and device models; C test programs run on the CPU and report through UART0 | Verilator (proven); flows provided for Questa, VCS and Xcelium |
| [`uvm/`](uvm/) | UVM SoC environment: one agent per pin group, AXI/APB protocol monitors, scoreboards, functional coverage, assertions, and a C-UVM handshake | a simulator with UVM 1.2 (Questa, VCS, Xcelium); not validated in this release |
| [`common/`](common/) | Definitions shared by both benches (`adr_tb_pkg.sv`) | both |

How to run them: [`sim/README.md`](../sim/README.md). The verification, test, coverage and assertion
plans are in `docs/pdf/` (`ADR_VERIFICATION_PLAN.pdf`, `ADR_TEST_PLAN.pdf`, `ADR_COVERAGE_PLAN.pdf`,
`ADR_ASSERTIONS_PLAN.pdf`).
