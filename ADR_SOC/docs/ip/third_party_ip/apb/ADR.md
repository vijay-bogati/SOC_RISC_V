# PULP APB library in the ADR SoC

The APB4 types and macros used for every peripheral slot. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/pulp-platform/apb |
| Vendored in | `rtl/third_party_ip/common/apb` |
| Modules used | `apb_pkg`, `apb/typedef.svh` (`APB_TYPEDEF_ALL`) |
| Where in ADR | `adr_soc_pkg` (types `apb_req_t`, `apb_resp_t`) and every subsystem with APB slots |
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
| APB | `common/apb` | github.com/pulp-platform/apb | `v0.2.4` / `77ddf073` | See `common/apb/LICENSE` |

<!-- integration: generated, do not edit -->
## 2. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `APB_TYPEDEF_ALL` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 0 (the modules are used inside other third-party blocks only) |
| Reset style of the vendored code | No reset found in 1 files (combinational or initial values) |

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
| `serial` | SPI, QSPI, I2C, free slots | 19 |
| `sys` | Bus error monitor, system control | 23 |

## 5. Known limitations in ADR

None recorded for this block in `docs/LIMITATIONS.md`.

## 6. Related documents

- [`../../protocols/APB.md`](../../protocols/APB.md)
- [`../axi/ADR.md`](../axi/ADR.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
