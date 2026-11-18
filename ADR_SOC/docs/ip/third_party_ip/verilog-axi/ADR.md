# verilog-axi (DMA engines) in the ADR SoC

Alex Forencich's AXI library. ADR uses its copy engine and its stream DMA engine. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/alexforencich/verilog-axi |
| Vendored in | `rtl/third_party_ip/dma` |
| Modules used | `axi_cdma`, `axi_dma` (`axi_dma_rd`, `axi_dma_wr`) |
| Where in ADR | `i_dma` (copy engine, crossbar initiator 2) and inside `i_eth` (memory engine, initiator 3) |
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
| DMA copy engine, Ethernet memory engine (`axi_cdma`, `axi_dma`) | `dma/rtl` | github.com/alexforencich/verilog-axi | `516bd5da` | MIT, see `COPYING` |

<!-- integration: generated, do not edit -->
## 2. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `axi_cdma`, `axi_dma`, `axi_dma_rd`, `axi_dma_wr` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 2 |
| Reset style of the vendored code | Synchronous, active-high (`if (rst)` in 3 of 4 files): the clock must run during reset |

#### `axi_cdma` as `i_engine` (`rtl/adr_ip/dma/rtl/adr_dma.sv:136`)

| Parameter | Value in ADR |
|---|---|
| `AXI_DATA_WIDTH` | `64` |
| `AXI_ADDR_WIDTH` | `64` |
| `AXI_ID_WIDTH` | `IdWidth` |
| `AXI_MAX_BURST_LEN` | `MaxBurst` |
| `LEN_WIDTH` | `LenWidth` |
| `TAG_WIDTH` | `8` |
| `ENABLE_UNALIGNED` | `1` |

Ports: 47 connected by name; tied to constants: `enable` = `1'b1`; none left open.

#### `axi_dma` as `i_dma` (`rtl/adr_ip/eth/rtl/adr_eth.sv:100`)

| Parameter | Value in ADR |
|---|---|
| `AXI_DATA_WIDTH` | `64` |
| `AXI_ADDR_WIDTH` | `64` |
| `AXI_ID_WIDTH` | `IdWidth` |
| `AXI_MAX_BURST_LEN` | `MaxBurst` |
| `AXIS_DATA_WIDTH` | `64` |
| `AXIS_USER_ENABLE` | `0` |
| `LEN_WIDTH` | `LenWidth` |
| `TAG_WIDTH` | `1` |
| `ENABLE_UNALIGNED` | `1` |

Ports: 79 connected by name; tied to constants: `s_axis_read_desc_tag` = `1'b0`, `s_axis_read_desc_id` = `'0`, `s_axis_read_desc_dest` = `'0`, `s_axis_read_desc_user` = `'0`, `s_axis_write_desc_tag` = `1'b0`, `s_axis_write_data_tid` = `'0`, `s_axis_write_data_tdest` = `'0`, `s_axis_write_data_tuser` = `1'b0`, `write_abort` = `1'b0`; left open: `m_axis_read_desc_status_tag`, `m_axis_read_data_tid`, `m_axis_read_data_tdest`, `m_axis_read_data_tuser`, `m_axis_write_desc_status_tag`, `m_axis_write_desc_status_id`, `m_axis_write_desc_status_dest`, `m_axis_write_desc_status_user`.

<!-- integration: end -->

## 3. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/COPYING`](upstream/COPYING)
- [`upstream/README.md`](upstream/README.md)

## 4. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `dma` | DMA, and cache coherency methods | 26 |
| `eth` | Ethernet, looped back at the SerDes interface | 18 |

## 5. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 51: DMA is not cache-coherent in hardware.
- Item 52: DMA is memory-to-memory only.
- Item 54: DMA channels run one at a time,
- Item 55: DMA tests are directed, not random.

## 6. Related documents

- [`../../adr_ip/adr_dma.md`](../../adr_ip/adr_dma.md)
- [`../../adr_ip/adr_eth.md`](../../adr_ip/adr_eth.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
