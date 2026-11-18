# tb/verilator/ - the SoC bench (proven on Verilator)

| File | Contents |
|---|---|
| `tb_top.sv` | Simulation top: clock and reset, the JTAG debugger used by the `debug` test, end-of-test detection and the `[TOP] VERDICT` line |
| `tb_adr_soc.sv` | The board: the chip, SPI and QSPI memory models, I2C device, OTP macro, USB host, loopbacks for UART1, GPIO, PWM and Ethernet |
| `c_tests/` | One C program per test, the boot stub, start-up code, linker script and the test library |

Each C test runs on the CVA6 CPU, checks the hardware from software, and prints its result on
UART0; the bench turns that into the verdict and the cycle count. The same bench also runs on Questa,
VCS and Xcelium (flows provided). Commands: [`sim/README.md`](../../sim/README.md).

| Test | Covers | Checks |
|---|---|---|
| `smoke` | CPU, memories, illegal instruction trap, UART0, error target | 18 |
| `irq` | CLINT, PLIC | 31 |
| `debug` | JTAG, debug module, system bus access | 30 |
| `periph` | UART1, GPIO, timer | 31 |
| `serial` | SPI, QSPI, I2C, free slots | 19 |
| `timers` | PWM, watchdog | 18 |
| `aes` | AES, with FIPS-197 vectors | 17 |
| `sys` | Bus error monitor, system control | 23 |
| `eth` | Ethernet, looped back at the SerDes interface | 18 |
| `usb` | USB device, against a host model in the testbench | 12 |
| `ddr` | DDR4 from the CPU and DMA, atomics, running code | 18 |
| `dma` | DMA, and cache coherency methods (run with `TEST=dma`) | 26 |
| `misc` | Pin mux, ADC, OTP, always-on timer, clock gating (run with `TEST=misc`) | 35 |
| `uart_i2c` | UART0, UART1 and I2C register write and read-back, I2C interrupt through the PLIC | 37 |
| `i2c` | The I2C part of `uart_i2c` alone, for a quick I2C check | 23 |
| `amo` | Atomics to targets that do not support them: SLVERR, nothing written | |

The first eleven are the default regression (`make regress`).
