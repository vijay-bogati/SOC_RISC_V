# LiteDRAM (DDR4 controller), generated with LiteX in the ADR SoC

Enjoy-Digital's DRAM controller generator. `scripts/gen_ddr.py` generates `litedram_core.v`, a controller with LiteDRAM's DFI-level memory model, for simulation only. This note says how ADR uses it. The upstream documents, at the exact commit vendored, are in [`upstream/`](upstream/).

| | |
|---|---|
| Upstream | github.com/enjoy-digital/litedram and github.com/enjoy-digital/litex |
| Vendored in | `rtl/third_party_ip/ddr` |
| Modules used | `litedram_core` (generated) |
| Where in ADR | Inside `i_mem.i_ddr` (`adr_ddr`) |
| Changes | Generated, not copied. Regenerating needs LiteX and LiteDRAM at the commits in `docs/THIRD_PARTY.md`. |
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
| DDR4 controller and memory model | `ddr/rtl/litedram_core.v`, generated, not copied | github.com/enjoy-digital/litedram at `f2d22975` and github.com/enjoy-digital/litex at `9187839f`, through `scripts/gen_ddr.py` and `ddr/ddr4_sim.yml` | BSD, see `ddr/LICENSE.litedram` and `ddr/LICENSE.litex` |

## 2. ADR configuration: DDR4 memory (`adr_ddr`)

A LiteDRAM core on crossbar target 6, with `axi_riscv_atomics_wrap` in front as for SRAM, both inside `adr_ddr`. **The generated core is for simulation only:** it includes LiteDRAM's DFI-level memory model in place of a PHY and a memory device, so the DRAM protocol timing it shows isn't proof against a real part.

| Item | Setting |
|---|---|
| Generator | `scripts/gen_ddr.py` with `rtl/third_party_ip/ddr/ddr4_sim.yml` |
| Size | 32 MiB, a reduced part so that the model stays small |
| Width | Native 64 bits, the same as the bus, with no width converter |
| Clock | `clk_i`. A real part needs its own clock and a crossing |
| Control registers | At `0x1002_0000`, listed in `rtl/third_party_ip/ddr/csr.csv` |
| Start-up | Under hardware control from reset, with no software init sequence |

- **Reset:** the generated core has no reset input. It starts from its initial values, and a system reset doesn't reset it.
- **Width setting:** with a native word wider than the bus, LiteDRAM's converter holds a lone access until the next one arrives, so a single CPU access hangs.
- **For a real part:** generate a core with its own PHY and geometry, add a clock crossing and an init sequence, and have the user port wait for init to finish. `litedram_gen` doesn't support LPDDR4.


<!-- integration: generated, do not edit -->
## 3. Integration in ADR

Generated from the RTL by `tp_integration.py` on 2026-11-14. Instances of `litedram_core` in our own RTL (`rtl/adr_soc`, `rtl/adr_ip`).

| Item | Value |
|---|---|
| Instances in our RTL | 1 |
| Reset style of the vendored code | Synchronous, active-high (`if (rst)` in 1 of 1 files): the clock must run during reset |

#### `litedram_core` as `i_core` (`rtl/adr_ip/ddr/rtl/adr_ddr.sv:102`)

All parameters at their defaults.

Ports: 46 connected by name; tied to constants: `sim_trace` = `1'b0`, `wb_ctrl_sel` = `4'hF`, `wb_ctrl_cti` = `3'b000`, `wb_ctrl_bte` = `2'b00`; left open: `init_done`, `init_error`, `user_clk`, `user_rst`.

<!-- integration: end -->

## 4. Upstream documents

Copied unchanged from the upstream repository at the vendored commit, with its license:

- [`upstream/LICENSE`](upstream/LICENSE)
- [`upstream/README.md`](upstream/README.md)
- [`upstream/doc/gen.md`](upstream/doc/gen.md)
- [`upstream/litex/LICENSE`](upstream/litex/LICENSE)
- [`upstream/litex/README.md`](upstream/litex/README.md)
- and 1 figures used by them

LiteX's README and license are in `upstream/litex/`, as LiteX is the generator framework.

## 5. Verification in ADR

| Test | Covers | Checks |
|---|---|---|
| `ddr` | DDR4 from the CPU and DMA, atomics, running code | 18 |

## 6. Known limitations in ADR

From `docs/LIMITATIONS.md`:

- Item 12: Atomics work on SRAM and DDR4 only.
- Item 41: AddressSanitizer reports an out-of-bounds read
- Item 68: Ethernet has no descriptor rings or address filter.
- Item 72: DDR4 is a simulation model only.
- Item 73: A system reset doesn't reset the DDR4 core,
- Item 92: No LPDDR4.
- Item 96: Address space limits.
- Item 101: DDR4 is outside clock gating and always built.
- Item 106: DDR4 is tested on a model at DFI level.
- Item 107: Ethernet and USB don't use DDR4 in their tests,

## 7. Related documents

- [`../../adr_ip/adr_ddr.md`](../../adr_ip/adr_ddr.md)
- `docs/MICROARCHITECTURE.md`: section numbers quoted above refer to it.
