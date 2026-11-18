# Placeholders

These are stubs, not working IP. They aren't in `sim/adr_soc.f`, aren't instantiated in the SoC, and have never been simulated. Each only fixes a register port, and was checked to compile on its own with `verilator --lint-only`.

| Folder | Block | Reserved slot and PLIC source | What a real version needs |
|---|---|---|---|
| `pcie/` | PCIe | `0x1001_6000`, source 29 | A controller and a SerDes PHY, which is analog. It would add a crossbar initiator and target, plus the DMA coherency rules in `docs/MICROARCHITECTURE.md` section 8.3. |
| `mipi/` | MIPI C-PHY and D-PHY | `0x1001_7000`, source 30 | A CSI or DSI protocol block and an analog PHY. |
| `gpu/` | Graphics | `0x1001_8000`, source 13 | A display or 2D engine, with a crossbar initiator for its memory access. It depends on DDR. |

No open-source candidate has been chosen or checked for any of these. Check the license, version and silicon history at the source before using one.
