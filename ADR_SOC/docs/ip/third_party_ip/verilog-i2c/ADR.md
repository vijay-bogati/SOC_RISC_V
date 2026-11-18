# verilog-i2c (I2C master engine) in the ADR SoC

Alex Forencich's I2C master. ADR uses its byte engine and FIFOs under our own APB register block. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/alexforencich/verilog-i2c |
| Vendored in | `rtl/third_party_ip/i2c` |
| Modules used | `i2c_master`, `axis_fifo` |
| Where in ADR | Inside `i_lsio.i_i2c` (`adr_i2c`) |
| Testbench model | `rtl/third_party_ip/i2c/tb/adr_tb_i2c_dev.sv` is our own device model, not upstream |
| Changes | Upstream `i2c_master_axil.v` was removed from the vendored copy on 2026-11-08, as nothing used it after `adr_i2c` replaced it. The remaining files are unmodified. |
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
| I2C master | `i2c/rtl` | github.com/alexforencich/verilog-i2c | `a65be404` | MIT, see `COPYING`. Only `i2c_master.v` and `axis_fifo.v` are built, under our own `adr_i2c` APB block. `i2c_master_axil.v`, the upstream AXI4-Lite wrapper, was unused after 2026-11-07 and was removed from the vendored copy on 2026-11-08; the remaining files are unchanged |

<!-- integration: generated, do not edit -->
## 2. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `i2c_master`, `axis_fifo` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 4 |
| Reset style of the vendored code | Synchronous, active-high (`if (rst)` in 2 of 2 files): the clock must run during reset |

#### `i2c_master` as `i_master` (`rtl/adr_ip/i2c/rtl/adr_i2c.sv:230`)

All parameters at their defaults.

Ports: 30 connected by name; tied to constants: `stop_on_idle` = `1'b0`; none left open.

#### `axis_fifo` as `i_cmd_fifo` (`rtl/adr_ip/i2c/rtl/adr_i2c.sv:108`)

| Parameter | Value in ADR |
|---|---|
| `DEPTH` | `FifoDepth` |
| `DATA_WIDTH` | `12` |
| `KEEP_ENABLE` | `0` |
| `LAST_ENABLE` | `0` |
| `ID_ENABLE` | `0` |
| `DEST_ENABLE` | `0` |
| `USER_ENABLE` | `0` |
| `FRAME_FIFO` | `0` |

Ports: 23 connected by name; tied to constants: `s_axis_tkeep` = `1'b0`, `s_axis_tlast` = `1'b0`, `s_axis_tid` = `8'd0`, `s_axis_tdest` = `8'd0`, `s_axis_tuser` = `1'b0`; left open: `m_axis_tkeep`, `m_axis_tlast`, `m_axis_tid`, `m_axis_tdest`, `m_axis_tuser`, `status_overflow`, `status_bad_frame`, `status_good_frame`, `status_full`, `status_empty`.

#### `axis_fifo` as `i_write_fifo` (`rtl/adr_ip/i2c/rtl/adr_i2c.sv:154`)

| Parameter | Value in ADR |
|---|---|
| `DEPTH` | `FifoDepth` |
| `DATA_WIDTH` | `8` |
| `KEEP_ENABLE` | `0` |
| `LAST_ENABLE` | `1` |
| `ID_ENABLE` | `0` |
| `DEST_ENABLE` | `0` |
| `USER_ENABLE` | `0` |
| `FRAME_FIFO` | `0` |

Ports: 23 connected by name; tied to constants: `s_axis_tkeep` = `1'b0`, `s_axis_tid` = `8'd0`, `s_axis_tdest` = `8'd0`, `s_axis_tuser` = `1'b0`; left open: `m_axis_tkeep`, `m_axis_tid`, `m_axis_tdest`, `m_axis_tuser`, `status_overflow`, `status_bad_frame`, `status_good_frame`, `status_full`, `status_empty`.

#### `axis_fifo` as `i_read_fifo` (`rtl/adr_ip/i2c/rtl/adr_i2c.sv:199`)

| Parameter | Value in ADR |
|---|---|
| `DEPTH` | `FifoDepth` |
| `DATA_WIDTH` | `8` |
| `KEEP_ENABLE` | `0` |
| `LAST_ENABLE` | `1` |
| `ID_ENABLE` | `0` |
| `DEST_ENABLE` | `0` |
| `USER_ENABLE` | `0` |
| `FRAME_FIFO` | `0` |

Ports: 23 connected by name; tied to constants: `s_axis_tkeep` = `1'b0`, `s_axis_tid` = `8'd0`, `s_axis_tdest` = `8'd0`, `s_axis_tuser` = `1'b0`; left open: `m_axis_tkeep`, `m_axis_tid`, `m_axis_tdest`, `m_axis_tuser`, `status_overflow`, `status_bad_frame`, `status_good_frame`, `status_full`, `status_empty`.

<!-- integration: end -->

## 3. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/COPYING`](upstream/COPYING)
- [`upstream/README.md`](upstream/README.md)

## 4. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `serial` | SPI, QSPI, I2C, free slots | 19 |
| `uart_i2c` | UART0, UART1 and I2C register write and read-back, I2C interrupt through the PLIC | 37 |
| `i2c` | The I2C part of `uart_i2c` alone, for a quick I2C check: registers, one transfer, interrupt through the PLIC. Not in the default `TESTS` list | 23 |

## 5. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 37: I2C had no interrupt output.
- Item 112: A write to an absent I2C device reports two missed ACKs.
- Item 40: SPI and I2C are tested against our own simple device models,

## 6. Related documents

- [`../../adr_ip/adr_i2c.md`](../../adr_ip/adr_i2c.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
