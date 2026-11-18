# APB SPI master in the ADR SoC

An SPI master with single and quad modes, driven through registers. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/pulp-platform/apb_spi_master (registers) with github.com/pulp-platform/axi_spi_master (core) |
| Vendored in | `rtl/third_party_ip/spi` |
| Modules used | `apb_spi_master`, `spi_master_apb_if`, and the `spi_master_*` core files |
| Where in ADR | `i_lsio.i_spi` (APB slot 5, single line) and `i_lsio.i_qspi` (slot 6, quad) |
| PLIC sources | 12 (SPI), 14 (QSPI), edge |
| Clock | Gated by `CLK_EN` bits 1 (SPI) and 3 (QSPI) |
| Testbench model | `rtl/third_party_ip/spi/tb/adr_tb_spi_mem.sv` is our own flash model, not upstream |
| Changes | None: the vendored files are unmodified. |
| Integration owner | Vijay Bogati |
| Document revision | 2.0 |
| Date | 2026-11-14 |

### Revision history

| Revision | Date | Change |
|---|---|---|
| 1.0 | 2026-11-08 | First issue: version, license, configuration, upstream documents |
| 2.0 | 2026-11-14 | Integration section generated from the RTL (instances, parameters, tied and open ports, reset style); standard cover table |

## 1. Version and license

From `docs/THIRD_PARTY.md`, the record of every vendored file:

| Block | Path | Upstream | Version / commit | License |
|---|---|---|---|---|
| SPI register interface | `spi/rtl` (`apb_spi_master.sv`, `spi_master_apb_if.sv`) | github.com/pulp-platform/apb_spi_master | `v0.1.0` / `3fce8108` | Solderpad 0.51 |

## 2. ADR configuration: SPI, QSPI

Two instances of `apb_spi_master`, with `BUFFER_DEPTH` 10.

| Offset | Register | Notes |
|---|---|---|
| `0x00` | STATUS | Write: `[0]` read, `[1]` write, `[2]` quad read, `[3]` quad write, `[4]` soft reset, `[11:8]` chip select |
| `0x04` | CLKDIV | `[7:0]` |
| `0x08` | SPICMD | Command word |
| `0x0C` | SPIADR | Address word |
| `0x10` | SPILEN | `[5:0]` command bits, `[13:8]` address bits, `[31:16]` data bits |
| `0x14` | SPIDUM | `[15:0]` read dummy, `[31:16]` write dummy |
| `0x18` | TXFIFO | |
| `0x20` | RXFIFO | |
| `0x24` | INTCFG | Thresholds and counters; `[31]` interrupt enable |
| `0x28` | INTSTA | |

| Instance | Pins |
|---|---|
| SPI | SCLK, 4 chip selects, MOSI on `sdo0`, MISO on `sdi1`. Other data lines are tied off |
| QSPI | SCLK, 4 chip selects, 4 data out, 4 data in, and a mode output (0 single, 1 quad out, 2 quad in) |

SPI is half-duplex, sending and then receiving, with no CPOL or CPHA settings. Quad mode covers the whole transfer, including command and address, so 1-1-4 reads aren't possible. QSPI has no memory-mapped access.


<!-- integration: generated, do not edit -->
## 3. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `apb_spi_master`, `spi_master_apb_if` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 2 |
| Reset style of the vendored code | Asynchronous, active-low (`negedge` reset in 7 of 7 files) |

#### `apb_spi_master` as `i_spi` (`rtl/adr_soc/lsio/adr_lsio_subsys.sv:179`)

| Parameter | Value in ADR |
|---|---|
| `BUFFER_DEPTH` | `10` |
| `APB_ADDR_WIDTH` | `12` |

Ports: 25 connected by name; tied to constants: `spi_sdi0` = `1'b0`, `spi_sdi2` = `1'b0`, `spi_sdi3` = `1'b0`; left open: `spi_mode`, `spi_sdo1`, `spi_sdo2`, `spi_sdo3`.

#### `apb_spi_master` as `i_qspi` (`rtl/adr_soc/lsio/adr_lsio_subsys.sv:210`)

| Parameter | Value in ADR |
|---|---|
| `BUFFER_DEPTH` | `10` |
| `APB_ADDR_WIDTH` | `12` |

Ports: 25 connected by name; none tied to constants; none left open.

<!-- integration: end -->

## 4. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/CHANGELOG.md`](upstream/CHANGELOG.md)
- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/README.md`](upstream/README.md)

## 5. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `serial` | SPI, QSPI, I2C, free slots | 19 |

## 6. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 36: QSPI has no memory-mapped flash access (XIP).
- Item 38: SPI is half-duplex with a fixed clock mode.
- Item 39: Quad mode covers the whole QSPI transfer,
- Item 40: SPI and I2C are tested against our own simple device models,

## 7. Related documents

- [`../axi_spi_master/ADR.md`](../axi_spi_master/ADR.md)
- [`../../adr_soc/adr_lsio_subsys.md`](../../adr_soc/adr_lsio_subsys.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
