# PULP common cells in the ADR SoC

Generic building blocks: FIFOs, arbiters, synchronizers, reset synchronizers, counters. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/pulp-platform/common_cells |
| Vendored in | `rtl/third_party_ip/common/common_cells (and `uart/rtl/include/common_cells` for the assertion header)` |
| Modules used | `rstgen`, `sync`, `fifo_v3`, `id_queue`, `rr_arb_tree`, `spill_register`, `cdc_*` and others used by the AXI library and CVA6 |
| Where in ADR | `i_rst_gen` (4 × `rstgen`), `i_periph` (`sync` on `boot_pins_i` and `adc_compare_i`), `adr_axi_mem` (`fifo_v3`), and inside most third-party blocks |
| Changes | A modified copy for the commercial simulators (Questa, VCS, Xcelium) of `src/id_queue.sv` is in `sim/compat_fixes/`, with a formal equivalence proof; Verilator builds the unmodified file. See `docs/THIRD_PARTY.md`. |
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
| Common cells | `common/common_cells` | github.com/pulp-platform/common_cells | `dc555643` (as vendored by CVA6) | Solderpad 0.51 |
| Assertions header | `uart/rtl/include/common_cells` | github.com/pulp-platform/common_cells | `v1.39.0` / `9ca8a765` | Solderpad 0.51, see `uart/LICENSE.common_cells` |

<!-- integration: generated, do not edit -->
## 2. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `rstgen`, `sync`, `fifo_v3`, `id_queue`, `rr_arb_tree`, `spill_register` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 8 |
| Reset style of the vendored code | Asynchronous, active-low (`negedge` reset in 12 of 28 files) |

#### `rstgen` as `i_sys_rst` (`rtl/adr_soc/rst/adr_rst_gen.sv:84`)

All parameters at their defaults.

Ports: 5 connected by name; tied to constants: `test_mode_i` = `1'b0`; left open: `init_no`.

#### `rstgen` as `i_usb_rst` (`rtl/adr_soc/rst/adr_rst_gen.sv:92`)

All parameters at their defaults.

Ports: 5 connected by name; tied to constants: `test_mode_i` = `1'b0`; left open: `init_no`.

#### `rstgen` as `i_eth_tx_rst` (`rtl/adr_soc/rst/adr_rst_gen.sv:100`)

All parameters at their defaults.

Ports: 5 connected by name; tied to constants: `test_mode_i` = `1'b0`; left open: `init_no`.

#### `rstgen` as `i_eth_rx_rst` (`rtl/adr_soc/rst/adr_rst_gen.sv:108`)

All parameters at their defaults.

Ports: 5 connected by name; tied to constants: `test_mode_i` = `1'b0`; left open: `init_no`.

#### `sync` as `i_sync` (`rtl/adr_soc/periph/adr_periph_subsys.sv:98`)

All parameters at their defaults.

Ports: 4 connected by name; none tied to constants; none left open.

#### `sync` as `i_adc_compare_sync` (`rtl/adr_soc/periph/adr_periph_subsys.sv:106`)

All parameters at their defaults.

Ports: 4 connected by name; none tied to constants; none left open.

#### `fifo_v3` as `i_write_buffer` (`rtl/adr_soc/mem/adr_axi_mem.sv:61`)

| Parameter | Value in ADR |
|---|---|
| `DEPTH` | `MaxWriteBeats` |
| `dtype` | `w_beat_t` |

Ports: 11 connected by name; tied to constants: `flush_i` = `1'b0`, `testmode_i` = `1'b0`; left open: `usage_o`.

#### `fifo_v3` as `i_address_buffer` (`rtl/adr_soc/mem/adr_axi_mem.sv:110`)

| Parameter | Value in ADR |
|---|---|
| `DEPTH` | `4` |
| `dtype` | `aw_entry_t` |

Ports: 11 connected by name; tied to constants: `flush_i` = `1'b0`, `testmode_i` = `1'b0`; left open: `usage_o`.

<!-- integration: end -->

## 3. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/CHANGELOG.md`](upstream/CHANGELOG.md)
- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/README.md`](upstream/README.md)

## 4. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `smoke` | CPU, memories, illegal instruction trap, UART0, error target | 18 |
| `sys` | Bus error monitor, system control | 23 |

## 5. Known limitations in ADR

None recorded for this block in `docs/LIMITATIONS.md`.

## 6. Related documents

- [`../../adr_soc/adr_rst_gen.md`](../../adr_soc/adr_rst_gen.md)
- [`../../adr_soc/adr_periph_subsys.md`](../../adr_soc/adr_periph_subsys.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
