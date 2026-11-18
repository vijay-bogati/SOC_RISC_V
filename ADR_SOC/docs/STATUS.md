# ADR SoC verification status

Release of 2026-11-18. Every result below is from **Verilator 5.020**, on the RTL, with the
Ethernet block at 25G. The raw summaries are in `results/summary_verilator.txt` (the regression) and
`results/summary_verilator_extra.txt` (the tests run on request), with each test's `sim.log` in
`results/verilator/<test>/`.

## Regression (`make regress`)

| Test | Result | Cycles |
|---|---|---|
| `smoke` | PASS | 218,689 |
| `irq` | PASS | 429,084 |
| `debug` | PASS | 202,132 |
| `periph` | PASS | 491,335 |
| `serial` | PASS | 280,972 |
| `timers` | PASS | 561,025 |
| `aes` | PASS | 245,205 |
| `sys` | PASS | 381,746 |
| `eth` | PASS | 287,990 |
| `usb` | PASS | 176,988 |
| `ddr` | PASS | 378,615 |

All 11 pass: 235 self-checks in the C programs, plus the debugger's own checks in `debug`.

## Tests run on request (`make sim TEST=<name>`)

| Test | Covers | Result | Cycles |
|---|---|---|---|
| `dma` | DMA copies, cache coherency methods | PASS | 548,396 |
| `misc` | Pin mux, ADC, OTP, always-on timer, clock gating | PASS | 577,955 |
| `uart_i2c` | UART0/UART1 and I2C registers, I2C transfer and interrupt | PASS | 666,998 |
| `i2c` | The I2C part of uart_i2c alone | PASS | 410,673 |
| `amo` | Atomics to targets that reject them (NEG-06..NEG-10) | PASS | 1,442,879 |

## Provided, not validated in this release

| Item | State |
|---|---|
| Questa, VCS and Xcelium flows (`SIM=questa`, `SIM=vcs`, `SIM=xcelium`) | Set up in the Makefile; every test should give the cycle counts above |
| UVM environment (`tb/uvm/`, `TB=uvm`) | Agents, bus monitors, scoreboards, cover groups and assertions written; needs a simulator with UVM 1.2 |
| `sba` (debug system bus access sizes and errors) | UVM bench only; written, not run |
| Code coverage (`make coverage`) | Flow exists; nothing collected |
| Gate-level regression (`NETLIST=1`) | Netlist builds with `make syn`; the gate-level regression is the next step |

## Next steps

1. Gate-level regression on Verilator, comparing every cycle count with RTL.
2. Validate the baseline bench and the UVM environment on a commercial simulator.
3. Collect code and functional coverage, and close the gaps in `ADR_COVERAGE_PLAN.pdf`.
4. The planned tests in `ADR_TEST_PLAN.pdf` section 6.

The detailed plan is `docs/pdf/ADR_VERIFICATION_PLAN.pdf`; every known gap is in `LIMITATIONS.md`.
