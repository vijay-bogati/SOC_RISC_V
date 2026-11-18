# results/ - sample results (Verilator 5.020, 2026-11-18)

| File | Contents |
|---|---|
| `summary_verilator.txt` | The regression (`make regress`): test, PASS or FAIL, cycle count |
| `summary_verilator_extra.txt` | The tests run on request (`dma`, `misc`, `uart_i2c`, `i2c`, `amo`) |
| `verilator/<test>/sim.log` | Each test's log: the program's `PASS`/`FAIL` lines from UART0, the result line with the cycle count, and the bench's `[TOP] VERDICT` |
| `verilator/uart_i2c/waves.fst` | Sample waveform of the `uart_i2c` test: the low-speed I/O subsystem (UART0, UART1, GPIO, SPI, QSPI, I2C, pin mux), the I2C device model, clock, reset and cycle count. Open with GTKWave |

A run writes into this folder, so running the tests yourself replaces these files. Commands:
`sim/README.md`.
