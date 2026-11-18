# PULP AXI RISC-V atomics in the ADR SoC

Resolves RISC-V AMOs (as AXI ATOPs) and LR/SC (as AXI exclusive accesses) in front of a memory that can't do them itself. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/pulp-platform/axi_riscv_atomics |
| Vendored in | `rtl/third_party_ip/common/axi_riscv_atomics` |
| Modules used | `axi_riscv_atomics_wrap` (`axi_riscv_amos`, `axi_riscv_lrsc`) |
| Where in ADR | `i_mem.i_sram.i_atomics` and inside `i_mem.i_ddr` |
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
| RISC-V atomics | `common/axi_riscv_atomics` | github.com/pulp-platform/axi_riscv_atomics | `550881f1` | Solderpad 0.51 |

## 2. ADR configuration: Atomic operations

| Target | Behaviour |
|---|---|
| SRAM | Resolved by `axi_riscv_atomics_wrap` in front of the memory, inside `adr_sram`, with a 64-bit word width |
| DDR4 | The same, with its own `axi_riscv_atomics_wrap` inside `adr_ddr` |
| Boot ROM | Stopped by `axi_atop_filter_intf` inside `adr_rom` |
| Other targets | Not supported, and not tested |


<!-- integration: generated, do not edit -->
## 3. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `axi_riscv_atomics_wrap`, `axi_riscv_amos`, `axi_riscv_lrsc` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 2 |
| Reset style of the vendored code | Asynchronous, active-low (`negedge` reset in 3 of 6 files) |

#### `axi_riscv_atomics_wrap` as `i_atomics` (`rtl/adr_ip/ddr/rtl/adr_ddr.sv:91`)

| Parameter | Value in ADR |
|---|---|
| `AXI_ADDR_WIDTH` | `AddrWidth` |
| `AXI_DATA_WIDTH` | `DataWidth` |
| `AXI_ID_WIDTH` | `IdWidth` |
| `AXI_USER_WIDTH` | `UserWidth` |
| `AXI_MAX_WRITE_TXNS` | `1` |
| `RISCV_WORD_WIDTH` | `64` |

Ports: 4 connected by name; none tied to constants; none left open.

#### `axi_riscv_atomics_wrap` as `i_atomics` (`rtl/adr_soc/mem/adr_sram.sv:46`)

| Parameter | Value in ADR |
|---|---|
| `AXI_ADDR_WIDTH` | `AddrWidth` |
| `AXI_DATA_WIDTH` | `DataWidth` |
| `AXI_ID_WIDTH` | `IdWidth` |
| `AXI_USER_WIDTH` | `UserWidth` |
| `AXI_MAX_WRITE_TXNS` | `1` |
| `RISCV_WORD_WIDTH` | `64` |

Ports: 4 connected by name; none tied to constants; none left open.

<!-- integration: end -->

## 4. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/CHANGELOG.md`](upstream/CHANGELOG.md)
- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/README.md`](upstream/README.md)

## 5. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `irq` | CLINT, PLIC | 31 |
| `ddr` | DDR4 from the CPU and DMA, atomics, running code | 18 |

## 6. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 12: Atomics work on SRAM and DDR4 only.
- Item 62: `misc` test depth.

## 7. Related documents

- [`../../protocols/AXI4.md`](../../protocols/AXI4.md)
- [`../../adr_soc/adr_mem_subsys.md`](../../adr_soc/adr_mem_subsys.md)
- [`../../adr_ip/adr_ddr.md`](../../adr_ip/adr_ddr.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
