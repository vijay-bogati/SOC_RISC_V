# ADR SoC feature list

This is the target for the design. Blocks are built from open-source IP and our own integration code.

## Processor
- One RV64GC (RV64IMAFDC) core with machine, supervisor and user modes
- MMU with Sv39 translation, and physical memory protection
- 16 KiB instruction cache and 32 KiB data cache
- JTAG debug with program buffer and system bus access
- Coprocessor port turned off, as nothing is connected to it; illegal instructions trap

## Interconnect
- 64-bit AXI4 crossbar with 4 initiators: CPU, debug, DMA, Ethernet
- Unmapped addresses return a decode error
- 32-bit APB for peripherals

## Memory map

| Block | Base | Size |
|---|---|---|
| Debug module | `0x0000_0000` | 4 KiB |
| Boot ROM (reset vector) | `0x0001_0000` | 32 KiB |
| CLINT | `0x0200_0000` | 64 KiB |
| PLIC | `0x0C00_0000` | 64 MiB |
| Peripherals | `0x1000_0000` | 4 KiB each: UART0 `+0x0000`, UART1 `+0x1000`, GPIO `+0x2000`, timer `+0x3000`, SPI `+0x4000`, QSPI `+0x6000`, I2C `+0x7000`, PWM `+0x9000`, watchdog `+0xA000`, AES `+0xB000`, bus error monitor `+0xC000`, system control `+0xD000`, DMA `+0xE000`, pin mux `+0x10000`, ADC `+0x11000`, OTP `+0x12000`, always-on timer `+0x13000`, Ethernet `+0x14000`, USB `+0x15000` |
| SRAM | `0x8000_0000` | 512 KiB |
| DDR4 | `0x9000_0000` | 32 MiB in simulation |
| SRAM, uncached alias | `0x1_8000_0000` | 512 KiB |
| DDR4, uncached alias | `0x1_9000_0000` | 32 MiB in simulation |

## Peripherals
- 2 UARTs, 16550-style
- 1 SPI master and 1 QSPI flash controller
- 1 I2C master
- 16-pin GPIO with edge interrupts, as level interrupts aren't available yet
- 8-channel 32-bit timer, 8-channel PWM from 4 timers, watchdog
- 1 DMA engine with 4 channels
- DDR4 memory controller
- USB 2.0 full-speed device (12 Mbit/s)
- 10G/25G Ethernet MAC and PCS with its own memory access, to an external SerDes
- AES with 128, 192 and 256-bit keys
- System control block, bus error monitor, pin mux, ADC controller, OTP controller, always-on timer, peripheral clock gating

## Placeholders

PCIe, MIPI C-PHY and D-PHY, and graphics are stubs in `rtl/placeholders/`. Each only fixes a register port. They aren't connected, aren't built with the design, and have never been simulated.

| Placeholder | Reserved register slot | Reserved PLIC source |
|---|---|---|
| PCIe | `0x1001_6000` | 29 |
| MIPI | `0x1001_7000` | 30 |
| Graphics | `0x1001_8000` | 13 |

These are reservations only, so an access returns a decode error today.

## Status

The test regression passes on Verilator 5.020; `STATUS.md` and `results/summary_verilator.txt` have the latest run. These are bring-up tests in simulation, and `LIMITATIONS.md` lists what they don't cover.

| Block | Status |
|---|---|
| CPU, crossbar, boot ROM, SRAM, UART0, error target | Integrated, `smoke` test passes in simulation |
| CLINT, PLIC | Integrated, `irq` test passes in simulation |
| JTAG debug | Integrated, `debug` test passes in simulation |
| UART1, GPIO, 8-channel timer | Integrated, `periph` test passes in simulation. GPIO has edge interrupts only, see `LIMITATIONS.md` |
| SPI, QSPI, I2C | Integrated, `serial` test passes in simulation. QSPI has no memory-mapped flash access, see `LIMITATIONS.md`. I2C registers and interrupt also tested by `uart_i2c`, and by the quicker I2C-only test `i2c` |
| PWM, watchdog | Integrated, `timers` test passes in simulation. The watchdog is our own design |
| AES | Integrated, `aes` test passes in simulation with FIPS-197 vectors. Round and key logic is our own; S-boxes are open-source |
| Bus error monitor, system control | Integrated, `sys` test passes in simulation. Both are our own designs |
| Ethernet | Integrated, 10G/25G, with `eth` looped back at the SerDes interface in the testbench. No real line rate or SerDes is exercised |
| USB device | Integrated, full speed only, tested against a simple host model in the testbench |
| DDR4 | Integrated with a simulation model only, 32 MiB, `ddr` test. No PHY or real memory device yet, and no LPDDR4 |
| PCIe, MIPI, graphics | Placeholder stubs only, outside the build |
| DMA | Integrated, `dma` test passes in simulation. Four-channel control is our own design around an open-source copy engine |
| Pin mux, ADC and OTP controllers, clock gating, always-on timer | Integrated, `misc` test passes in simulation. All our own designs; ADC and OTP analog parts are testbench models |
| Analog: PLL, regulators, power-on reset, power domains | Not planned, see `LIMITATIONS.md` |
| Memory macros | Behavioural models only |

Known limitations are listed in `LIMITATIONS.md`. The verification status is in `STATUS.md`.
