# APB GPIO in the ADR SoC

General-purpose I/O with edge interrupts. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/pulp-platform/apb_gpio |
| Vendored in | `rtl/third_party_ip/gpio` |
| Modules used | `apb_gpio` |
| Where in ADR | `i_lsio.i_gpio`, APB slot 2; pads through `adr_pinmux` |
| Pins | 16 (`NumGpioPins`) |
| PLIC source | 3, edge |
| Clock | Gated by `CLK_EN` bit 7 |
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
| GPIO | `gpio` | github.com/pulp-platform/apb_gpio | `f82caeb7` (2 commits after `v0.2.0`) | Solderpad 0.51 |

## 2. ADR configuration: GPIO

`apb_gpio`, with 16 pads. Only the low-order registers are relevant.

| Offset | Register | Notes |
|---|---|---|
| `0x00` | PADDIR | 1 = output |
| `0x04` | GPIOEN | An input pin's logic runs only with its bit set |
| `0x08` | PADIN | Synchronized input |
| `0x0C` | PADOUT | |
| `0x10` | PADOUTSET | Write 1 to set |
| `0x14` | PADOUTCLR | Write 1 to clear |
| `0x18` | INTEN | |
| `0x1C` | INTTYPE | 2 bits per pin, pins 0-15 |
| `0x24` | INTSTATUS | **Clears on read** |

Interrupts are edge-only: rising, falling or both. Pad configuration outputs are unused. Outputs go through the pin mux (section 13.6).


<!-- integration: generated, do not edit -->
## 3. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `apb_gpio` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 1 |
| Reset style of the vendored code | Asynchronous, active-low (`negedge` reset in 1 of 1 files) |

#### `apb_gpio` as `i_gpio` (`rtl/adr_soc/lsio/adr_lsio_subsys.sv:149`)

| Parameter | Value in ADR |
|---|---|
| `APB_ADDR_WIDTH` | `12` |
| `PAD_NUM` | `NumGpioPins` |

Ports: 17 connected by name; tied to constants: `dft_cg_enable_i` = `1'b0`; left open: `gpio_in_sync`, `gpio_padcfg`.

<!-- integration: end -->

## 4. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/docs/APB_GPIO_reference.md`](upstream/docs/APB_GPIO_reference.md)
- [`upstream/docs/APB_GPIO_reference.xlsx`](upstream/docs/APB_GPIO_reference.xlsx)

## 5. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `periph` | UART1, GPIO, timer | 31 |
| `misc` | Pin mux, ADC, OTP, always-on timer, clock gating | 35 |

## 6. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 30: GPIO has edge interrupts only.
- Item 33: GPIO status clears on read, and an input needs its enable bit set.
- Item 44: PWM tested by sampling through GPIO inputs,

## 7. Related documents

- [`../../adr_soc/adr_lsio_subsys.md`](../../adr_soc/adr_lsio_subsys.md)
- [`../../adr_ip/adr_pinmux.md`](../../adr_ip/adr_pinmux.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
