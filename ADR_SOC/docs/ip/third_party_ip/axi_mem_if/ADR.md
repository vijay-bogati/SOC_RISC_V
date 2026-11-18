# PULP AXI memory interface in the ADR SoC

`axi2mem`, an AXI4 to single-port memory adapter. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/pulp-platform/axi_mem_if |
| Vendored in | `rtl/third_party_ip/common/axi_mem_if` |
| Modules used | `axi2mem` |
| Where in ADR | `adr_axi_mem` (ROM and SRAM) and `i_debug.i_debug_slave` |
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
| AXI memory adapter | `common/axi_mem_if` | github.com/pulp-platform/axi_mem_if | `b4947015` | See its `LICENSE` |

## 2. ADR notes

- `adr_axi_mem` collects each write's address and data before passing it to `axi2mem`, because the two could otherwise wait on each other (bug fixed on 2026-11-06).

<!-- integration: generated, do not edit -->
## 3. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `axi2mem` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 2 |
| Reset style of the vendored code | Asynchronous, active-low (`negedge` reset in 1 of 1 files) |

#### `axi2mem` as `i_debug_slave` (`rtl/adr_soc/debug/adr_debug.sv:181`)

| Parameter | Value in ADR |
|---|---|
| `AXI_ID_WIDTH` | `TgtIdWidth` |
| `AXI_ADDR_WIDTH` | `AddrWidth` |
| `AXI_DATA_WIDTH` | `DataWidth` |
| `AXI_USER_WIDTH` | `UserWidth` |

Ports: 11 connected by name; tied to constants: `user_i` = `'0`; left open: `user_o`.

#### `axi2mem` as `i_adapter` (`rtl/adr_soc/mem/adr_axi_mem.sv:185`)

| Parameter | Value in ADR |
|---|---|
| `AXI_ID_WIDTH` | `IdWidth` |
| `AXI_ADDR_WIDTH` | `64` |
| `AXI_DATA_WIDTH` | `64` |
| `AXI_USER_WIDTH` | `UserWidth` |

Ports: 11 connected by name; tied to constants: `user_i` = `'0`; left open: `user_o`.

<!-- integration: end -->

## 4. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/CHANGELOG.md`](upstream/CHANGELOG.md)
- [`upstream/LICENSE`](upstream/LICENSE)

## 5. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `smoke` | CPU, memories, illegal instruction trap, UART0, error target | 18 |
| `debug` | JTAG, debug module, system bus access | 30 |
| `dma` | DMA, and cache coherency methods | 26 |

## 6. Known limitations in ADR

None recorded for this block in `docs/LIMITATIONS.md`.

## 7. Related documents

- [`../../adr_soc/adr_mem_subsys.md`](../../adr_soc/adr_mem_subsys.md)
- [`../../adr_soc/adr_debug.md`](../../adr_soc/adr_debug.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
