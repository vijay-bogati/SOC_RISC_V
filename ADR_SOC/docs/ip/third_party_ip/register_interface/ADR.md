# PULP register interface in the ADR SoC

A simple request/response register bus, and adapters to it. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/pulp-platform/register_interface |
| Vendored in | `rtl/third_party_ip/common/register_interface` |
| Modules used | `reg_intf`, `apb_to_reg` |
| Where in ADR | `i_core.i_plic_apb_to_reg`, between APB slot 4 and the PLIC |
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
| Register interface | `common/register_interface` | github.com/pulp-platform/register_interface | `73de8e51` | Solderpad 0.51 |

<!-- integration: generated, do not edit -->
## 2. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `reg_intf`, `apb_to_reg` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 1 |
| Reset style of the vendored code | No reset found in 2 files (combinational or initial values) |

#### `apb_to_reg` as `i_plic_apb_to_reg` (`rtl/adr_soc/core/adr_core_complex.sv:133`)

All parameters at their defaults.

Ports: 11 connected by name; none tied to constants; none left open.

<!-- integration: end -->

## 3. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/CHANGELOG.md`](upstream/CHANGELOG.md)
- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/README.md`](upstream/README.md)
- [`upstream/docs/timing_diagrams.txt`](upstream/docs/timing_diagrams.txt)
- and 2 figures used by them

## 4. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `irq` | CLINT, PLIC | 31 |

## 5. Known limitations in ADR

None recorded for this block in `docs/LIMITATIONS.md`.

## 6. Related documents

- [`../rv_plic/ADR.md`](../rv_plic/ADR.md)
- [`../../protocols/APB.md`](../../protocols/APB.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
