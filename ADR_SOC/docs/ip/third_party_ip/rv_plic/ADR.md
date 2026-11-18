# PLIC (`rv_plic`) in the ADR SoC

The RISC-V platform-level interrupt controller. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/pulp-platform/rv_plic |
| Vendored in | `rtl/third_party_ip/plic` |
| Modules used | `plic_top` and its generated register file |
| Where in ADR | `i_core.i_plic`, behind `apb_to_reg` on APB slot 4 at `0x0C00_0000` |
| Size | 30 sources, 2 targets (machine and supervisor context of hart 0), priorities 0 to 7 |
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
| PLIC | `plic` | github.com/pulp-platform/rv_plic | `5b5c5a4c` | Apache 2.0 |

## 2. ADR configuration: PLIC

`plic_top` connects through `apb_to_reg`. The register block is generated for exactly 30 sources and 2 targets, and supports 32-bit accesses only.

| Offset from `0x0C00_0000` | Register |
|---|---|
| `0x0000 + 4 * source` | Priority, 0 to 7 |
| `0x1000` | Pending |
| `0x2000 + 0x80 * context` | Enable |
| `0x20_0000 + 0x1000 * context` | Threshold |
| `0x20_0004 + 0x1000 * context` | Claim and complete |

Context 0 is machine mode, and context 1 is supervisor mode.

**Edge sources have no event counter.** An edge that arrives while the same source is waiting to be completed is lost, so software should re-check the peripheral's state after completing an interrupt.


## 3. ADR configuration: Interrupt map

Source `n` is bit `n-1` of the PLIC source vector. Source 0 means "no interrupt".

| Source | Block | Type | Signal |
|---|---|---|---|
| 1 | UART0 | Level | `INT` |
| 2 | UART1 | Level | `INT` |
| 3 | GPIO | Edge | `interrupt` |
| 4-11 | Timer 0-7 | Edge | Overflow OR compare, per timer |
| 12 | SPI | Edge | Threshold OR end of transfer |
| 13 | Reserved for graphics | | Tied to 0 |
| 14 | QSPI | Edge | Threshold OR end of transfer |
| 15-18 | PWM timer 0-3 | Edge | `events_o` |
| 19 | Watchdog | Level | `EXPIRED` |
| 20 | AES | Level | Done AND enable |
| 21 | Bus error monitor | Level | Any status AND enable |
| 22 | DMA | Level | Any channel done AND enable |
| 23 | I2C | Level | Any IRQ_STATUS bit AND its enable |
| 24 | ADC | Level | Done AND enable |
| 25 | OTP | Level | Done AND enable |
| 26 | Always-on timer | Level | Match |
| 27 | Ethernet | Level | Done AND enable |
| 28 | USB device | Level | Any enabled USB event |
| 29 | Reserved for PCIe | | Tied to 0 |
| 30 | Reserved for MIPI | | Tied to 0 |

Clear a level source's cause in the peripheral before completing it in the PLIC, or it fires again.


<!-- integration: generated, do not edit -->
## 4. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `plic_top` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 1 |
| Reset style of the vendored code | Asynchronous, active-low (`negedge` reset in 3 of 4 files) |

#### `plic_top` as `i_plic` (`rtl/adr_soc/core/adr_core_complex.sv:159`)

| Parameter | Value in ADR |
|---|---|
| `N_SOURCE` | `NumIrqSources` |
| `N_TARGET` | `NumIrqTargets` |
| `MAX_PRIO` | `MaxIrqPriority` |
| `reg_req_t` | `plic_req_t` |
| `reg_rsp_t` | `plic_rsp_t` |

Ports: 7 connected by name; none tied to constants; none left open.

<!-- integration: end -->

## 5. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/README.md`](upstream/README.md)
- [`upstream/doc/rv_plic_reg.hjson`](upstream/doc/rv_plic_reg.hjson)

Upstream has no prose document; `doc/rv_plic_reg.hjson` is its register description.

## 6. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `irq` | CLINT, PLIC | 31 |

## 7. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 2: PLIC is fixed at 30 sources and 2 targets.
- Item 3: PLIC edge sources have no event counter.
- Item 14: PLIC needs 32-bit accesses.
- Item 87: All 18 interrupts share PLIC source 28.

## 8. Related documents

- [`../../adr_soc/adr_core_complex.md`](../../adr_soc/adr_core_complex.md)
- [`../register_interface/ADR.md`](../register_interface/ADR.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
