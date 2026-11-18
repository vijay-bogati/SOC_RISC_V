# APB UART in the ADR SoC

A 16550-style UART: `apb_uart` is an APB wrapper (via `apb_to_obi`) around the OBI UART of `obi_peripherals`. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/pulp-platform/apb_uart, with github.com/pulp-platform/obi_peripherals and github.com/pulp-platform/obi |
| Vendored in | `rtl/third_party_ip/uart` |
| Modules used | `apb_uart`, `apb_uart_wrap`, `apb_to_obi`, `obi_uart` and its RX/TX |
| Where in ADR | `i_lsio.i_uart0` (APB slot 0) and `i_lsio.i_uart1` (slot 1) |
| PLIC sources | 1 (UART0), 2 (UART1), level |
| Clock | UART0 always runs (console); UART1 gated by `CLK_EN` bit 0 |
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
| APB UART wrapper | `uart/rtl` (`apb_uart*.sv`) | github.com/pulp-platform/apb_uart | `8182a85d` | Solderpad 0.51, see `uart/LICENSE.apb_uart` |

## 2. ADR configuration: UART0, UART1

`apb_uart` wrapping `obi_uart`, 16550-style. Register `n` is at offset `4 * n`.

| Offset | Read | Write |
|---|---|---|
| `0x00` | RBR, or DLL when DLAB = 1 | THR, or DLL when DLAB = 1 |
| `0x04` | IER, or DLM when DLAB = 1 | IER, or DLM when DLAB = 1 |
| `0x08` | IIR | FCR |
| `0x0C` | LCR | LCR |
| `0x10` | MCR | MCR |
| `0x14` | LSR | |
| `0x18` | MSR | |
| `0x1C` | SCR | SCR |

- A bit takes 16 x divisor clocks. A divisor of 1 is rejected, so the fastest rate is `clk_i` / 32.
- The active-low modem inputs are tied so that CTS, DSR and DCD look asserted and RI does not. Modem outputs are unconnected.


## 3. ADR notes

- Synthesis reports a false combinational loop on `character_length` in `obi_uart_rx.sv` before optimisation; it is removed by synthesis and has no effect.
- See also [`../obi_peripherals/ADR.md`](../obi_peripherals/ADR.md) and [`../obi/ADR.md`](../obi/ADR.md).

<!-- integration: generated, do not edit -->
## 4. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `apb_uart`, `apb_uart_wrap`, `apb_to_obi`, `obi_uart` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 2 |
| Reset style of the vendored code | Asynchronous, active-low (`negedge` reset in 7 of 12 files) |

#### `apb_uart` as `i_uart0` (`rtl/adr_soc/lsio/adr_lsio_subsys.sv:93`)

All parameters at their defaults.

Ports: 21 connected by name; tied to constants: `CTSN` = `1'b0`, `DSRN` = `1'b0`, `DCDN` = `1'b0`, `RIN` = `1'b1`; left open: `OUT1N`, `OUT2N`, `RTSN`, `DTRN`.

#### `apb_uart` as `i_uart1` (`rtl/adr_soc/lsio/adr_lsio_subsys.sv:117`)

All parameters at their defaults.

Ports: 21 connected by name; tied to constants: `CTSN` = `1'b0`, `DSRN` = `1'b0`, `DCDN` = `1'b0`, `RIN` = `1'b1`; left open: `OUT1N`, `OUT2N`, `RTSN`, `DTRN`.

<!-- integration: end -->

## 5. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/CHANGELOG.md`](upstream/CHANGELOG.md)
- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/README.md`](upstream/README.md)

## 6. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `smoke` | CPU, memories, illegal instruction trap, UART0, error target | 18 |
| `periph` | UART1, GPIO, timer | 31 |
| `uart_i2c` | UART0, UART1 and I2C register write and read-back, I2C interrupt through the PLIC | 37 |

## 7. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 11: UART rejects a divisor of 1.
- Item 34: UART tested at 8N1 and divisor 2 only.

## 8. Related documents

- [`../../adr_soc/adr_lsio_subsys.md`](../../adr_soc/adr_lsio_subsys.md)
- [`../../protocols/APB.md`](../../protocols/APB.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
