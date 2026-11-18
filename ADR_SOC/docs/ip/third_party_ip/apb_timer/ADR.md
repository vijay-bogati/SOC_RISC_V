# APB timer in the ADR SoC

Up-counting timers with compare. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/pulp-platform/apb_timer |
| Vendored in | `rtl/third_party_ip/timer` |
| Modules used | `apb_timer`, `timer` |
| Where in ADR | `i_periph.i_timer`, APB slot 3 |
| Timers | 8, one PLIC source each (4 to 11, edge) |
| Clock | Gated by `CLK_EN` bit 8 |
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
| Timer | `timer` | github.com/pulp-platform/apb_timer | `03eba2e6` (1 commit after `v0.1.0`) | Solderpad 0.51 |

## 2. ADR configuration: Timer

`apb_timer`, with 8 channels. Each channel `k` is at `0x10 * k`.

| Offset | Register | Notes |
|---|---|---|
| `0x0` | TIMER | Current count |
| `0x4` | CTRL | `[0]` enable, `[5:3]` prescaler |
| `0x8` | CMP | **Writing it also resets the count** |

Compare and overflow share one PLIC source per channel, and no status register tells them apart. The count restarts at compare or overflow, and a compare value of 0 is ignored.


<!-- integration: generated, do not edit -->
## 3. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `apb_timer`, `timer` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 1 |
| Reset style of the vendored code | Asynchronous, active-low (`negedge` reset in 1 of 2 files) |

#### `apb_timer` as `i_timer` (`rtl/adr_soc/periph/adr_periph_subsys.sv:125`)

| Parameter | Value in ADR |
|---|---|
| `APB_ADDR_WIDTH` | `12` |
| `TIMER_CNT` | `NumTimers` |

Ports: 11 connected by name; none tied to constants; none left open.

<!-- integration: end -->

## 4. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/CHANGELOG.md`](upstream/CHANGELOG.md)
- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/README.md`](upstream/README.md)

## 5. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `periph` | UART1, GPIO, timer | 31 |
| `misc` | Pin mux, ADC, OTP, always-on timer, clock gating | 35 |

## 6. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 31: Timer has no interrupt status register.
- Item 32: Timer behaviour is fixed.
- Item 35: Timer tests cover one compare and one overflow per scenario.

## 7. Related documents

- [`../../adr_soc/adr_periph_subsys.md`](../../adr_soc/adr_periph_subsys.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
