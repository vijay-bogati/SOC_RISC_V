# CLINT in the ADR SoC

The core-local interruptor: `mtime`, `mtimecmp` and the software interrupt. This note says how ADR uses it. Upstream has no separate document for it.

| | |
|---|---|
| Upstream | github.com/openhwgroup/cva6 (`corev_apu/clint`) |
| Vendored in | `rtl/third_party_ip/clint` |
| Modules used | `clint`, plus `ariane_axi_pkg` which its default parameters need |
| Where in ADR | `i_core.i_clint`, crossbar target 3 at `0x0200_0000` |
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
| CLINT | `clint` | github.com/openhwfoundation/cva6 | `v5.3.0` / `2ef1c1b1` | Solderpad 0.51 (file headers) |

## 2. ADR configuration: CLINT

Machine software and timer interrupts for one hart. `mtime` counts rising edges of `rtc_i`, and resets with the system.

| Offset from `0x0200_0000` | Register |
|---|---|
| `0x0000` | `msip` |
| `0x4000` | `mtimecmp` |
| `0xBFF8` | `mtime` |


<!-- integration: generated, do not edit -->
## 3. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `clint` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 1 |
| Reset style of the vendored code | Asynchronous, active-low (`negedge` reset in 2 of 3 files) |

#### `clint` as `i_clint` (`rtl/adr_soc/core/adr_core_complex.sv:114`)

| Parameter | Value in ADR |
|---|---|
| `CVA6Cfg` | `CpuCfg` |
| `AXI_ADDR_WIDTH` | `AddrWidth` |
| `AXI_DATA_WIDTH` | `DataWidth` |
| `AXI_ID_WIDTH` | `TgtIdWidth` |
| `NR_CORES` | `1` |
| `axi_req_t` | `tgt_req_t` |
| `axi_resp_t` | `tgt_resp_t` |

Ports: 8 connected by name; tied to constants: `testmode_i` = `1'b0`; none left open.

<!-- integration: end -->

## 4. Upstream documents

Upstream has no separate document for this block; the source comments are its documentation.

## 5. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `irq` | CLINT, PLIC | 31 |

## 6. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 5: CLINT time base needs a real clock.

## 7. Related documents

- [`../../adr_soc/adr_core_complex.md`](../../adr_soc/adr_core_complex.md)
- [`../cva6/ADR.md`](../cva6/ADR.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
