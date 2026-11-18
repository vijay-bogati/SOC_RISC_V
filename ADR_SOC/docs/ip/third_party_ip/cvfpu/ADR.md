# CVFPU floating-point unit in the ADR SoC

The floating-point unit inside CVA6, for the F and D extensions. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/openhwgroup/cvfpu |
| Vendored in | `rtl/third_party_ip/cva6/core/cvfpu` |
| Modules used | `fpnew_top` and its parts, instantiated by CVA6 |
| Where in ADR | Inside `i_core.i_cpu` |
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
| CVFPU | `cva6/core/cvfpu` | github.com/openhwgroup/cvfpu | `3116391b` | See its `LICENSE` |

<!-- integration: generated, do not edit -->
## 2. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `fpnew_top` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 0 (the modules are used inside other third-party blocks only) |
| Reset style of the vendored code | Asynchronous, active-low (`negedge` reset in 8 of 19 files) |

<!-- integration: end -->

## 3. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/README.md`](upstream/README.md)
- [`upstream/docs/README.md`](upstream/docs/README.md)
- and 5 figures used by them

## 4. Known limitations in ADR

None recorded for this block in `docs/LIMITATIONS.md`.

## 5. Related documents

- [`../cva6/ADR.md`](../cva6/ADR.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
