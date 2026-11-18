# APB advanced timer (PWM) in the ADR SoC

Four advanced timers with PWM outputs. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/pulp-platform/apb_adv_timer |
| Vendored in | `rtl/third_party_ip/pwm` |
| Modules used | `apb_adv_timer` and its timer modules |
| Where in ADR | `i_periph.i_pwm`, APB slot 8; 8 pins to `adr_pinmux` function 1 |
| PLIC sources | 15 to 18, edge |
| Clock | Gated by `CLK_EN` bit 6; each of its 4 timers also has its own internal `pulp_clock_gating` |
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
| PWM | `pwm` | github.com/pulp-platform/apb_adv_timer | `v1.0.4` / `c8faec1e` | Solderpad 0.51 |

## 2. ADR configuration: PWM

`apb_adv_timer` with 16-bit counters. Each of the 4 timers `t` is at `0x40 * t`.

| Offset | Register |
|---|---|
| `0x00` | CMD: `[0]` start, `[1]` stop, `[2]` update, `[3]` reset |
| `0x04` | CFG |
| `0x08` | TH: period thresholds |
| `0x0C` to `0x18` | Channel 0-3 thresholds |
| `0x1C` to `0x28` | Channel 0-3 LUT |
| `0x2C` | COUNTER |
| `0x100` | EVENT_CFG, shared |
| `0x104` | CH_EN, per-timer clock enable, shared |

The 8 pins are channels 0 and 1 of each timer: `pwm_o[1:0]` from timer 0, up to `pwm_o[7:6]` from timer 3. Paired pins share a period, so there are only 4 independent frequencies.


<!-- integration: generated, do not edit -->
## 3. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `apb_adv_timer` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 1 |
| Reset style of the vendored code | Asynchronous, active-low (`negedge` reset in 7 of 8 files) |

#### `apb_adv_timer` as `i_pwm` (`rtl/adr_soc/periph/adr_periph_subsys.sv:149`)

| Parameter | Value in ADR |
|---|---|
| `APB_ADDR_WIDTH` | `12` |
| `EXTSIG_NUM` | `32` |
| `TIMER_NBITS` | `16` |

Ports: 18 connected by name; tied to constants: `dft_cg_enable_i` = `1'b0`, `low_speed_clk_i` = `1'b0`, `ext_sig_i` = `'0`; none left open.

<!-- integration: end -->

## 4. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/doc/APB_ADV_TIMER_reference.xlsx`](upstream/doc/APB_ADV_TIMER_reference.xlsx)

Upstream documents the registers only in a spreadsheet, `doc/APB_ADV_TIMER_reference.xlsx`.

## 5. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `timers` | PWM, watchdog | 18 |
| `misc` | Pin mux, ADC, OTP, always-on timer, clock gating | 35 |

## 6. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 42: PWM channels share timers.
- Item 44: PWM tested by sampling through GPIO inputs,

## 7. Related documents

- [`../../adr_soc/adr_periph_subsys.md`](../../adr_soc/adr_periph_subsys.md)
- [`../../adr_ip/adr_pinmux.md`](../../adr_ip/adr_pinmux.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
