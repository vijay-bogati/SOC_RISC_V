# SPI master core in the ADR SoC

Source of the SPI core files used by `apb_spi_master`. Its AXI wrapper is not used. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/pulp-platform/axi_spi_master |
| Vendored in | `rtl/third_party_ip/spi` |
| Modules used | `spi_master_clkgen`, `spi_master_controller`, `spi_master_fifo`, `spi_master_rx`, `spi_master_tx` |
| Where in ADR | Inside `i_lsio.i_spi` and `i_lsio.i_qspi` |
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
| SPI core | `spi/rtl` (other `spi_master_*.sv`) | github.com/pulp-platform/axi_spi_master | `v0.1.1` / `ee219078` | Solderpad 0.51 |

<!-- integration: generated, do not edit -->
## 2. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `spi_master_clkgen`, `spi_master_controller`, `spi_master_fifo`, `spi_master_rx`, `spi_master_tx` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 0 (the modules are used inside other third-party blocks only) |
| Reset style of the vendored code | Asynchronous, active-low (`negedge` reset in 7 of 7 files) |

<!-- integration: end -->

## 3. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/CHANGELOG.md`](upstream/CHANGELOG.md)
- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/README.md`](upstream/README.md)

## 4. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `serial` | SPI, QSPI, I2C, free slots | 19 |

## 5. Known limitations in ADR

None recorded for this block in `docs/LIMITATIONS.md`.

## 6. Related documents

- [`../apb_spi_master/ADR.md`](../apb_spi_master/ADR.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
