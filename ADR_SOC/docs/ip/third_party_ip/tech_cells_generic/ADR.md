# PULP generic tech cells in the ADR SoC

Behavioural models of technology cells: clock gate, clock mux, clock inverter. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/pulp-platform/tech_cells_generic |
| Vendored in | `rtl/third_party_ip/common/tech_cells` |
| Modules used | `tc_clk_gating` through `pulp_clock_gating`, plus the other `tc_clk_*` cells used by CVA6 and the debug module |
| Where in ADR | Every clock gate in `i_lsio` and `i_periph` (9 cells), and inside the PWM block (4 cells) |
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
| Tech cells | `common/tech_cells` | github.com/pulp-platform/tech_cells_generic | `7968dd6e` (as vendored by CVA6) | Solderpad 0.51 |

## 2. ADR notes

- `pulp_clock_gating` is a latch-based gate. Synthesis on 2026-11-08 found exactly one latch per gate and no other latches. A real chip replaces `tc_clk_gating` with the library's integrated clock-gate cell.

<!-- integration: generated, do not edit -->
## 3. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `tc_clk_gating`, `pulp_clock_gating` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 9 |
| Reset style of the vendored code | Asynchronous, active-low (`negedge` reset in 1 of 4 files) |

#### `pulp_clock_gating` as `i_gate_uart1` (`rtl/adr_soc/lsio/adr_lsio_subsys.sv:79`)

All parameters at their defaults.

Ports: 4 connected by name; tied to constants: `test_en_i` = `1'b0`; none left open.

#### `pulp_clock_gating` as `i_gate_gpio` (`rtl/adr_soc/lsio/adr_lsio_subsys.sv:81`)

All parameters at their defaults.

Ports: 4 connected by name; tied to constants: `test_en_i` = `1'b0`; none left open.

#### `pulp_clock_gating` as `i_gate_spi` (`rtl/adr_soc/lsio/adr_lsio_subsys.sv:83`)

All parameters at their defaults.

Ports: 4 connected by name; tied to constants: `test_en_i` = `1'b0`; none left open.

#### `pulp_clock_gating` as `i_gate_qspi` (`rtl/adr_soc/lsio/adr_lsio_subsys.sv:85`)

All parameters at their defaults.

Ports: 4 connected by name; tied to constants: `test_en_i` = `1'b0`; none left open.

#### `pulp_clock_gating` as `i_gate_i2c` (`rtl/adr_soc/lsio/adr_lsio_subsys.sv:87`)

All parameters at their defaults.

Ports: 4 connected by name; tied to constants: `test_en_i` = `1'b0`; none left open.

#### `pulp_clock_gating` as `i_gate_timer` (`rtl/adr_soc/periph/adr_periph_subsys.sv:82`)

All parameters at their defaults.

Ports: 4 connected by name; tied to constants: `test_en_i` = `1'b0`; none left open.

#### `pulp_clock_gating` as `i_gate_pwm` (`rtl/adr_soc/periph/adr_periph_subsys.sv:84`)

All parameters at their defaults.

Ports: 4 connected by name; tied to constants: `test_en_i` = `1'b0`; none left open.

#### `pulp_clock_gating` as `i_gate_aes` (`rtl/adr_soc/periph/adr_periph_subsys.sv:86`)

All parameters at their defaults.

Ports: 4 connected by name; tied to constants: `test_en_i` = `1'b0`; none left open.

#### `pulp_clock_gating` as `i_gate_adc` (`rtl/adr_soc/periph/adr_periph_subsys.sv:88`)

All parameters at their defaults.

Ports: 4 connected by name; tied to constants: `test_en_i` = `1'b0`; none left open.

<!-- integration: end -->

## 4. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/CHANGELOG.md`](upstream/CHANGELOG.md)
- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/README.md`](upstream/README.md)

## 5. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `misc` | Pin mux, ADC, OTP, always-on timer, clock gating | 35 |

## 6. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 57: No power management beyond clock gating.
- Item 79: Ethernet is outside clock gating,
- Item 88: USB is outside clock gating,
- Item 101: DDR4 is outside clock gating and always built.

## 7. Related documents

- [`../../adr_soc/adr_lsio_subsys.md`](../../adr_soc/adr_lsio_subsys.md)
- [`../../adr_soc/adr_periph_subsys.md`](../../adr_soc/adr_periph_subsys.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
