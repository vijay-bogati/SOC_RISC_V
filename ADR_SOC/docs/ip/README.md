# ADR SoC IP documents

One document for every block in the SoC, including the two buses. The folders mirror `rtl/`:

| Folder | Contents |
|---|---|
| [`protocols/`](protocols/) | How ADR uses AXI4 and APB: signals, widths, ports, slots, behaviour |
| [`adr_soc/`](adr_soc/) | Our own SoC subsystems, from `rtl/adr_soc/` |
| [`adr_ip/`](adr_ip/) | Our own IP blocks, from `rtl/adr_ip/` |
| [`third_party_ip/`](third_party_ip/) | One folder per upstream repository, from `rtl/third_party_ip/`: `ADR.md` says how ADR uses it, and `upstream/` holds that project's own documents and license, copied unchanged at the commit we vendored |

**PDF copies:** `docs/pdf/ip/`, one PDF per block in the same folders, built by `scripts/ip_docs_to_pdf.py` (see the main `README.md`). These Markdown files are their source: edit here, then rebuild.

`docs/MICROARCHITECTURE.md` stays the specification of the whole chip; these documents are the per-block reference. Where both cover a block, the text was taken from the specification on 2026-11-08, so update both when a block changes. Interface tables come from the RTL: `python3 scripts/ip_ports.py <file> <module>` prints them again.

## Buses

| Document | Covers |
|---|---|
| [AXI4](protocols/AXI4.md) | The 64-bit fabric: initiators, targets, AXI4 signal to RTL field mapping, widths, atomics, error responses |
| [APB](protocols/APB.md) | The 32-bit peripheral bus: the bridge, APB4 signals, the 21 slots, software rules |

## SoC subsystems (our own RTL)

| Instance | Document | Contains |
|---|---|---|
| (top) | [adr_soc_top](adr_soc/adr_soc_top.md) | Connections, memory map, top-level ports |
| `i_rst_gen` | [adr_rst_gen](adr_soc/adr_rst_gen.md) | Reset synchronizers for every clock domain |
| `i_core` | [adr_core_complex](adr_soc/adr_core_complex.md) | CVA6, CLINT, PLIC |
| `i_debug` | [adr_debug](adr_soc/adr_debug.md) | JTAG, debug module, system bus access |
| `i_interconnect` | [adr_interconnect](adr_soc/adr_interconnect.md) | Crossbar, error target, bus observation, `adr_apb_bridge` |
| `i_mem` | [adr_mem_subsys](adr_soc/adr_mem_subsys.md) | Boot ROM, SRAM, DDR4, `adr_axi_mem`, `adr_mem_model` |
| `i_lsio` | [adr_lsio_subsys](adr_soc/adr_lsio_subsys.md) | UART0, UART1, GPIO, SPI, QSPI, I2C, pin mux, their clock gates |
| `i_periph` | [adr_periph_subsys](adr_soc/adr_periph_subsys.md) | Timer, PWM, watchdog, AES, bus monitor, system control, ADC, OTP, always-on timer, synchronizers, clock gates |

## Our own IP blocks

| Block | Document | APB slot | PLIC | Built on |
|---|---|---|---|---|
| I2C controller | [adr_i2c](adr_ip/adr_i2c.md) | 7 | 23 | [verilog-i2c](third_party_ip/verilog-i2c/ADR.md) |
| Watchdog | [adr_wdt](adr_ip/adr_wdt.md) | 9 | 19 | |
| AES | [adr_aes](adr_ip/adr_aes.md) | 10 | 20 | [secworks AES S-boxes](third_party_ip/secworks_aes/ADR.md) |
| Bus error monitor | [adr_bus_monitor](adr_ip/adr_bus_monitor.md) | 11 | 21 | |
| System control | [adr_sysctrl](adr_ip/adr_sysctrl.md) | 12 | | |
| DMA | [adr_dma](adr_ip/adr_dma.md) | 13 | 22 | [verilog-axi](third_party_ip/verilog-axi/ADR.md) `axi_cdma` |
| Pin mux | [adr_pinmux](adr_ip/adr_pinmux.md) | 14 | | |
| ADC controller | [adr_adc_ctrl](adr_ip/adr_adc_ctrl.md) | 15 | 24 | |
| OTP controller | [adr_otp_ctrl](adr_ip/adr_otp_ctrl.md) | 16 | 25 | |
| Always-on timer | [adr_aon_timer](adr_ip/adr_aon_timer.md) | 17 | 26 | |
| Ethernet | [adr_eth](adr_ip/adr_eth.md) | 18 | 27 | [verilog-ethernet](third_party_ip/verilog-ethernet/ADR.md), [verilog-axi](third_party_ip/verilog-axi/ADR.md) `axi_dma` |
| USB device | [adr_usb](adr_ip/adr_usb.md) | 19 | 28 | [OpenTitan usbdev](third_party_ip/opentitan_usbdev/ADR.md) |
| DDR4 | [adr_ddr](adr_ip/adr_ddr.md) | 20 (control) | | [LiteDRAM](third_party_ip/litedram/ADR.md), [atomics](third_party_ip/axi_riscv_atomics/ADR.md) |

## Third-party IP

Versions and licenses are recorded in `docs/THIRD_PARTY.md`, which stays the reference.

| Block | Note | Upstream documents | Used for |
|---|---|---|---|
| CVA6 | [ADR.md](third_party_ip/cva6/ADR.md) | [upstream](third_party_ip/cva6/upstream/) | CPU |
| CVFPU | [ADR.md](third_party_ip/cvfpu/ADR.md) | [upstream](third_party_ip/cvfpu/upstream/) | FPU inside CVA6 |
| CLINT | [ADR.md](third_party_ip/clint/ADR.md) | none upstream | Timer and software interrupts |
| rv_plic | [ADR.md](third_party_ip/rv_plic/ADR.md) | [upstream](third_party_ip/rv_plic/upstream/) | PLIC |
| riscv-dbg | [ADR.md](third_party_ip/riscv-dbg/ADR.md) | [upstream](third_party_ip/riscv-dbg/upstream/) | Debug module and JTAG |
| PULP axi | [ADR.md](third_party_ip/axi/ADR.md) | [upstream](third_party_ip/axi/upstream/) | Fabric, crossbar, APB bridge |
| PULP apb | [ADR.md](third_party_ip/apb/ADR.md) | [upstream](third_party_ip/apb/upstream/) | APB types |
| common_cells | [ADR.md](third_party_ip/common_cells/ADR.md) | [upstream](third_party_ip/common_cells/upstream/) | FIFOs, synchronizers, reset synchronizers |
| tech_cells_generic | [ADR.md](third_party_ip/tech_cells_generic/ADR.md) | [upstream](third_party_ip/tech_cells_generic/upstream/) | Clock gates |
| register_interface | [ADR.md](third_party_ip/register_interface/ADR.md) | [upstream](third_party_ip/register_interface/upstream/) | APB to the PLIC registers |
| axi_mem_if | [ADR.md](third_party_ip/axi_mem_if/ADR.md) | [upstream](third_party_ip/axi_mem_if/upstream/) | `axi2mem` for ROM, SRAM, debug memory |
| axi_riscv_atomics | [ADR.md](third_party_ip/axi_riscv_atomics/ADR.md) | [upstream](third_party_ip/axi_riscv_atomics/upstream/) | Atomics at SRAM and DDR4 |
| apb_uart | [ADR.md](third_party_ip/apb_uart/ADR.md) | [upstream](third_party_ip/apb_uart/upstream/) | UART0, UART1 |
| obi_peripherals | [ADR.md](third_party_ip/obi_peripherals/ADR.md) | [upstream](third_party_ip/obi_peripherals/upstream/) | UART core |
| obi | [ADR.md](third_party_ip/obi/ADR.md) | [upstream](third_party_ip/obi/upstream/) | APB to OBI for the UARTs |
| apb_gpio | [ADR.md](third_party_ip/apb_gpio/ADR.md) | [upstream](third_party_ip/apb_gpio/upstream/) | GPIO |
| apb_timer | [ADR.md](third_party_ip/apb_timer/ADR.md) | [upstream](third_party_ip/apb_timer/upstream/) | Timer |
| apb_spi_master | [ADR.md](third_party_ip/apb_spi_master/ADR.md) | [upstream](third_party_ip/apb_spi_master/upstream/) | SPI and QSPI registers |
| axi_spi_master | [ADR.md](third_party_ip/axi_spi_master/ADR.md) | [upstream](third_party_ip/axi_spi_master/upstream/) | SPI core |
| verilog-i2c | [ADR.md](third_party_ip/verilog-i2c/ADR.md) | [upstream](third_party_ip/verilog-i2c/upstream/) | I2C engine |
| apb_adv_timer | [ADR.md](third_party_ip/apb_adv_timer/ADR.md) | [upstream](third_party_ip/apb_adv_timer/upstream/) | PWM |
| secworks aes | [ADR.md](third_party_ip/secworks_aes/ADR.md) | [upstream](third_party_ip/secworks_aes/upstream/) | AES S-boxes |
| verilog-axi | [ADR.md](third_party_ip/verilog-axi/ADR.md) | [upstream](third_party_ip/verilog-axi/upstream/) | DMA and Ethernet memory engines |
| verilog-ethernet | [ADR.md](third_party_ip/verilog-ethernet/ADR.md) | [upstream](third_party_ip/verilog-ethernet/upstream/) | Ethernet MAC and PCS |
| OpenTitan usbdev | [ADR.md](third_party_ip/opentitan_usbdev/ADR.md) | [upstream](third_party_ip/opentitan_usbdev/upstream/) | USB device |
| LiteDRAM, LiteX | [ADR.md](third_party_ip/litedram/ADR.md) | [upstream](third_party_ip/litedram/upstream/) | DDR4 controller, generated |

The upstream documents were fetched on 2026-11-08 from each repository at the commit in `docs/THIRD_PARTY.md`, documentation files only (README, `doc/` or `docs/`, license). For CVA6, only the user manual and the 64-bit MMU chapter were taken; for OpenTitan, only `hw/ip/usbdev`. They are not ADR documents and are not edited.
