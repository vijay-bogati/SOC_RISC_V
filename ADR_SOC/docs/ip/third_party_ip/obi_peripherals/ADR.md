# OBI peripherals (UART core) in the ADR SoC

Source of the OBI UART core used inside `apb_uart`. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/pulp-platform/obi_peripherals |
| Vendored in | `rtl/third_party_ip/uart` |
| Modules used | `obi_uart` with `obi_uart_rx`, `obi_uart_tx`, `obi_uart_register`, `obi_uart_baudgen`, `obi_uart_interrupts`, `obi_uart_modem`, `obi_uart_pkg` |
| Where in ADR | Inside `i_lsio.i_uart0` and `i_lsio.i_uart1` |
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
| OBI UART | `uart/rtl` (`obi_uart*.sv`) | github.com/pulp-platform/obi_peripherals | `v0.1.1` / `079894a6` | See `uart/LICENSE.obi_uart` |

<!-- integration: generated, do not edit -->
## 2. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `obi_uart`, `obi_uart_rx`, `obi_uart_tx`, `obi_uart_register`, `obi_uart_baudgen`, `obi_uart_interrupts`, `obi_uart_modem` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 0 (the modules are used inside other third-party blocks only) |
| Reset style of the vendored code | Asynchronous, active-low (`negedge` reset in 7 of 12 files) |

<!-- integration: end -->

## 3. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/CHANGELOG.md`](upstream/CHANGELOG.md)
- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/README.md`](upstream/README.md)

## 4. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `periph` | UART1, GPIO, timer | 31 |

## 5. Known limitations in ADR

None recorded for this block in `docs/LIMITATIONS.md`.

## 6. Related documents

- [`../apb_uart/ADR.md`](../apb_uart/ADR.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
