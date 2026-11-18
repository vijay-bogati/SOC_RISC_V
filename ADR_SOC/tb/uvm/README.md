# tb/uvm/ - UVM SoC environment

Needs a simulator with UVM 1.2 (Questa, VCS or Xcelium: `make sim SIM=<sim> TB=uvm TEST=<test>`).
**Not validated in this release**; the SoC regression is proven on the Verilator bench.

| File / folder | Contents |
|---|---|
| `adr_soc_uvm_top.sv` | Top: clocks and reset, one interface per pin group, the board, the chip, `run_test` |
| `adr_soc_tb_if.sv` | Clocks (system, Ethernet, USB), reset, the cycle count and the timeout |
| `adr_soc_tb_forces.svh` | The board: per-test loopbacks (`+loopback_<name>`) and the fixed wiring |
| `adr_soc_env_pkg.sv` | Environment: one agent per pin group, fabric monitors, scoreboards, coverage, end-of-test checker and the C-UVM handshake |
| `adr_soc_sb_pkg.sv` | Scoreboards for UART0, UART1, SPI, QSPI and I2C: APB transfers against pin monitors through a register and FIFO model |
| `adr_soc_probes.sv` | Bound probes that connect the fabric monitors to the AXI and APB ports |
| `vip/axi/`, `vip/apb/` | AXI4 and APB monitors with protocol checks, one per crossbar port and APB slot |
| `uvm_tests/` | Tests: `adr_soc_base_test` (runs a C program to its end), `adr_debug_test`, `adr_sba_test` |
| `uvm_sequence/` | Sequences: the JTAG debugger, debug system bus access checks, the USB host |
| `c_tests/` | The UVM bench's C programs (with the C-UVM handshake) |

Reusable IP-level agents live next to their block, in `rtl/*/*/tb/uvm/`:

- UART, I2C, SPI/QSPI, GPIO and PWM;
- JTAG with a RISC-V debug (DMI) layer;
- OTP, ADC, Ethernet SerDes and USB.

**C-UVM handshake.** A C program writes tagged words to the system control SCRATCH0 register:

- end of test, with its failure count;
- checkpoints;
- requests to the bench.

The APB monitor passes them to the environment. The test answers each request through SCRATCH1.
