# rtl/adr_soc/ - SoC top level and subsystems

The top level only connects subsystems; all logic lives in the subsystem that owns it. The hierarchy
is in [`docs/MICROARCHITECTURE.md`](../../docs/MICROARCHITECTURE.md), section 2.

| File | Contents |
|---|---|
| `adr_soc_pkg.sv` | Parameters, address map, APB slots, `CLK_EN` bits, APB types, interrupt numbers, CPU configuration |
| `adr_soc_top.sv` | Top level, connections only |
| `rst/adr_rst_gen.sv` | Every reset: the system reset and one synchronizer per clock domain |
| `core/adr_core_complex.sv` | CVA6 CPU, CLINT and PLIC |
| `debug/adr_debug.sv` | Debug subsystem: JTAG transport, RISC-V debug module, and its target and initiator bus ports |
| `interconnect/adr_interconnect.sv` | 64-bit AXI4 crossbar and address map, error target, bus observation, APB bridge |
| `interconnect/adr_apb_bridge.sv` | AXI4 to the 32-bit APB slots, with replies for clock-gated peripherals |
| `mem/adr_mem_subsys.sv` | Boot ROM, SRAM and DDR4 |
| `mem/adr_rom.sv`, `mem/adr_sram.sv`, `mem/adr_axi_mem.sv`, `mem/adr_mem_model.sv` | Memory targets, atomics handling and the behavioural memory |
| `lsio/adr_lsio_subsys.sv` | UART0, UART1, GPIO, SPI, QSPI, I2C, pin mux, and their clock gates |
| `periph/adr_periph_subsys.sv` | Timer, PWM, watchdog, AES, bus monitor, system control, ADC, OTP, always-on timer, and their clock gates |

Each subsystem has a datasheet in [`docs/ip/adr_soc/`](../../docs/ip/adr_soc/).
