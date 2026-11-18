# verilog-ethernet (10G/25G MAC and PCS) in the ADR SoC

Alex Forencich's Ethernet library, its final version before the move to `fpganinja/taxi`. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/alexforencich/verilog-ethernet |
| Vendored in | `rtl/third_party_ip/ethernet` |
| Modules used | `eth_mac_phy_10g_fifo` with its MAC, PCS (64b/66b) and `lib/axis` FIFOs |
| Where in ADR | Inside `i_eth` (`adr_eth`) |
| Changes | `lfsr` was renamed `eth_lfsr` (module and file) to avoid a name clash; documented in `docs/THIRD_PARTY.md`. The rest is unmodified. |
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
| Ethernet 10G/25G MAC, PCS and FIFOs | `ethernet/rtl` | github.com/alexforencich/verilog-ethernet, including its `lib/axis` | `77320a94`. The final version; upstream has moved to `fpganinja/taxi` under a different license | MIT, see `COPYING` |

## 2. ADR notes

- Two upstream constructs need relaxed settings in the yosys-slang synthesis check: an out-of-range select in `axis_baser_rx_64.v` inside a branch that only runs with PTP timestamps on (off in ADR), and `eth_lfsr`'s nested elaboration-time loops, which need a higher unroll limit. Verilator accepts them as they are.

<!-- integration: generated, do not edit -->
## 3. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `eth_mac_phy_10g_fifo` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 1 |
| Reset style of the vendored code | Synchronous, active-high (`if (rst)` in 8 of 15 files): the clock must run during reset |

#### `eth_mac_phy_10g_fifo` as `i_mac` (`rtl/adr_ip/eth/rtl/adr_eth.sv:200`)

| Parameter | Value in ADR |
|---|---|
| `DATA_WIDTH` | `64` |
| `AXIS_DATA_WIDTH` | `64` |
| `COUNT_125US` | `Count125us` |
| `TX_FIFO_DEPTH` | `4096` |
| `RX_FIFO_DEPTH` | `4096` |

Ports: 49 connected by name; tied to constants: `ptp_sample_clk` = `1'b0`, `tx_axis_tuser` = `1'b0`, `m_axis_tx_ptp_ts_ready` = `1'b1`, `ptp_ts_96` = `'0`, `ptp_ts_step` = `1'b0`, `cfg_tx_prbs31_enable` = `1'b0`, `cfg_rx_prbs31_enable` = `1'b0`; left open: `m_axis_tx_ptp_ts_96`, `m_axis_tx_ptp_ts_tag`, `m_axis_tx_ptp_ts_valid`, `rx_axis_tuser`, `tx_error_underflow`, `tx_fifo_overflow`, `tx_fifo_bad_frame`, `tx_fifo_good_frame`, `rx_error_bad_frame`, `rx_error_bad_fcs`, `rx_bad_block`, `rx_fifo_overflow`, `rx_fifo_good_frame`.

<!-- integration: end -->

## 4. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/COPYING`](upstream/COPYING)
- [`upstream/README.md`](upstream/README.md)

## 5. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `eth` | Ethernet, looped back at the SerDes interface | 18 |

## 6. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 68: Ethernet has no descriptor rings or address filter.
- Item 76: 25G is unproven.
- Item 109: Sustained 25G isn't possible with this memory path.
- Item 79: Ethernet is outside clock gating,
- Item 70: `verilog-ethernet` is the final MIT version.
- Item 71: Ethernet and USB tests are sanity tests.
- Item 107: Ethernet and USB don't use DDR4 in their tests,

## 7. Related documents

- [`../../adr_ip/adr_eth.md`](../../adr_ip/adr_eth.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
