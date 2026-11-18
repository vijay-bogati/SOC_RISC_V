# OpenTitan `usbdev` (USB device) in the ADR SoC

The OpenTitan full-speed USB device, with the primitives and TL-UL bus adapters it needs. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/lowRISC/opentitan, `hw/ip/usbdev` |
| Vendored in | `rtl/third_party_ip/usb` |
| Modules used | `usbdev` and its parts, `prim_*`, `tlul_*`, `top_pkg` |
| Where in ADR | Inside `i_usb` (`adr_usb`) |
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
| USB device, with its primitives and bus adapters | `usb/rtl` | github.com/lowRISC/opentitan, `hw/ip/usbdev`, `prim`, `prim_generic`, `tlul`, and `top_pkg` from `hw/top_earlgrey` | `a78922f1`, tag `Earlgrey-PROD-M6-RC7`. Not newer, because later versions need Verilator 5.048 | Apache 2.0, see `LICENSE` |

## 2. ADR notes

- `sim/usb_files.sv` compiles the OpenTitan files as one unit, because some use assertion macros without including them, and those macros clash with the common cells ones of the same name. It also undefines `SIMULATION`, which only adds a random-delay model to the synchronizers.
- Our own generic primitives are in `rtl/adr_ip/usb/rtl/adr_usb_prims.sv`.

<!-- integration: generated, do not edit -->
## 3. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `usbdev` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 1 |
| Reset style of the vendored code | Mixed: asynchronous in 32 files, synchronous in 5 of 77 files |

#### `usbdev` as `i_usbdev` (`rtl/adr_ip/usb/rtl/adr_usb.sv:114`)

All parameters at their defaults.

Ports: 49 connected by name; tied to constants: `alert_rx_i` = `'{default: prim_alert_pkg::ALERT_RX_DEFAULT}`, `usb_rx_d_i` = `1'b0`, `usb_aon_bus_reset_i` = `1'b0`, `usb_aon_sense_lost_i` = `1'b0`, `usb_aon_bus_not_idle_i` = `1'b0`, `usb_aon_wake_detect_active_i` = `1'b0`, `ram_cfg_i` = `'0`; left open: `alert_tx_o`, `usb_tx_se0_o`, `usb_tx_d_o`, `usb_rx_enable_o`, `usb_tx_use_d_se0_o`, `usb_aon_suspend_req_o`, `usb_aon_wake_ack_o`, `usb_ref_val_o`, `usb_ref_pulse_o`.

<!-- integration: end -->

## 4. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/hw/ip/usbdev/README.md`](upstream/hw/ip/usbdev/README.md)
- [`upstream/hw/ip/usbdev/doc/checklist.md`](upstream/hw/ip/usbdev/doc/checklist.md)
- [`upstream/hw/ip/usbdev/doc/interfaces.md`](upstream/hw/ip/usbdev/doc/interfaces.md)
- [`upstream/hw/ip/usbdev/doc/programmers_guide.md`](upstream/hw/ip/usbdev/doc/programmers_guide.md)
- [`upstream/hw/ip/usbdev/doc/registers.md`](upstream/hw/ip/usbdev/doc/registers.md)
- [`upstream/hw/ip/usbdev/doc/theory_of_operation.md`](upstream/hw/ip/usbdev/doc/theory_of_operation.md)
- [`upstream/hw/ip/usbdev/doc/wake_resume.md`](upstream/hw/ip/usbdev/doc/wake_resume.md)
- and 2 figures used by them

Only `hw/ip/usbdev/README.md` and `hw/ip/usbdev/doc/` were copied, with the repository license.

## 5. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `usb` | USB device, against a host model in the testbench | 12 |

## 6. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 65: USB is full speed and device only.
- Item 66: USB uses an older OpenTitan release.
- Item 67: USB registers hang if `usb_clk_i` stops.
- Item 85: No wake from USB.
- Item 88: USB is outside clock gating,
- Item 91: No USB software.
- Item 71: Ethernet and USB tests are sanity tests.
- Item 107: Ethernet and USB don't use DDR4 in their tests,

## 7. Related documents

- [`../../adr_ip/adr_usb.md`](../../adr_ip/adr_usb.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
