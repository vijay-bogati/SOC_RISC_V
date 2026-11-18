# Third-party IP

Every source file under `rtl/third_party_ip/` is unmodified upstream code, apart from the rename described below and the generated DDR4 core, pinned to the versions below, though files have moved from their upstream folders. Each block keeps its license files and file headers; where several upstream projects share a folder, their licenses are named `LICENSE.<project>`. Only the files the design compiles are kept, plus all license files. Symlinks were copied as regular files, because the shared folder cannot store symlinks.

| Block | Path | Upstream | Version / commit | License |
|---|---|---|---|---|
| CVA6 CPU | `cva6/core`, `cva6/common` | github.com/openhwfoundation/cva6 | `v5.3.0` / `2ef1c1b1` | See `cva6/LICENSE` (Solderpad 0.51), `LICENSE.Berkeley`, `LICENSE.SiFive` |
| CVFPU | `cva6/core/cvfpu` | github.com/openhwgroup/cvfpu | `3116391b` | See its `LICENSE` |
| HPDcache | `cva6/core/cache_subsystem/hpdcache` | github.com/openhwgroup/cv-hpdcache | `04de8089` | See its `LICENSE` |
| AXI | `common/axi` | github.com/pulp-platform/axi | `697f13ff` (as vendored by CVA6) | Solderpad 0.51 |
| Common cells | `common/common_cells` | github.com/pulp-platform/common_cells | `dc555643` (as vendored by CVA6) | Solderpad 0.51 |
| Tech cells | `common/tech_cells` | github.com/pulp-platform/tech_cells_generic | `7968dd6e` (as vendored by CVA6) | Solderpad 0.51 |
| FPGA support | `cva6/vendor/pulp-platform/fpga-support` | github.com/pulp-platform/fpga-support | `a3ba269c` (as vendored by CVA6) | See its `LICENSE` |
| AXI memory adapter | `common/axi_mem_if` | github.com/pulp-platform/axi_mem_if | `b4947015` | See its `LICENSE` |
| RISC-V atomics | `common/axi_riscv_atomics` | github.com/pulp-platform/axi_riscv_atomics | `550881f1` | Solderpad 0.51 |
| CLINT | `clint` | github.com/openhwfoundation/cva6 | `v5.3.0` / `2ef1c1b1` | Solderpad 0.51 (file headers) |
| AXI types package | `clint/rtl/ariane_axi_pkg.sv` | github.com/openhwfoundation/cva6 | `v5.3.0` / `2ef1c1b1` | See `cva6/LICENSE` and file header. Needed only because the CLINT's default parameters refer to it |
| PLIC | `plic` | github.com/pulp-platform/rv_plic | `5b5c5a4c` | Apache 2.0 |
| Register interface | `common/register_interface` | github.com/pulp-platform/register_interface | `73de8e51` | Solderpad 0.51 |
| Debug module | `debug` | github.com/pulp-platform/riscv-dbg | `e19d69ef` (v0.4.1); `dm_sba`, `dm_csrs` and `dm_top` with the system bus access fixes of v0.5.0 backported in `debug/backport/` | Solderpad 0.51, see its `LICENSE` and `LICENSE.SiFive` |
| GPIO | `gpio` | github.com/pulp-platform/apb_gpio | `f82caeb7` (2 commits after `v0.2.0`) | Solderpad 0.51 |
| Timer | `timer` | github.com/pulp-platform/apb_timer | `03eba2e6` (1 commit after `v0.1.0`) | Solderpad 0.51 |
| SPI register interface | `spi/rtl` (`apb_spi_master.sv`, `spi_master_apb_if.sv`) | github.com/pulp-platform/apb_spi_master | `v0.1.0` / `3fce8108` | Solderpad 0.51 |
| SPI core | `spi/rtl` (other `spi_master_*.sv`) | github.com/pulp-platform/axi_spi_master | `v0.1.1` / `ee219078` | Solderpad 0.51 |
| I2C master | `i2c/rtl` | github.com/alexforencich/verilog-i2c | `a65be404` | MIT, see `COPYING`. Only `i2c_master.v` and `axis_fifo.v` are built, under our own `adr_i2c` APB block. `i2c_master_axil.v`, the upstream AXI4-Lite wrapper, was unused after 2026-11-07 and was removed from the vendored copy on 2026-11-08; the remaining files are unchanged |
| PWM | `pwm` | github.com/pulp-platform/apb_adv_timer | `v1.0.4` / `c8faec1e` | Solderpad 0.51 |
| AES S-boxes | `aes_sbox/rtl` | github.com/secworks/aes | `80dc4718` | BSD-2-Clause |
| DMA copy engine, Ethernet memory engine (`axi_cdma`, `axi_dma`) | `dma/rtl` | github.com/alexforencich/verilog-axi | `516bd5da` | MIT, see `COPYING` |
| USB device, with its primitives and bus adapters | `usb/rtl` | github.com/lowRISC/opentitan, `hw/ip/usbdev`, `prim`, `prim_generic`, `tlul`, and `top_pkg` from `hw/top_earlgrey` | `a78922f1`, tag `Earlgrey-PROD-M6-RC7`. Not newer, because later versions need Verilator 5.048 | Apache 2.0, see `LICENSE` |
| DDR4 controller and memory model | `ddr/rtl/litedram_core.v`, generated, not copied | github.com/enjoy-digital/litedram at `f2d22975` and github.com/enjoy-digital/litex at `9187839f`, through `scripts/gen_ddr.py` and `ddr/ddr4_sim.yml` | BSD, see `ddr/LICENSE.litedram` and `ddr/LICENSE.litex` |
| Ethernet 10G/25G MAC, PCS and FIFOs | `ethernet/rtl` | github.com/alexforencich/verilog-ethernet, including its `lib/axis` | `77320a94`. The final version; upstream has moved to `fpganinja/taxi` under a different license | MIT, see `COPYING` |
| APB UART wrapper | `uart/rtl` (`apb_uart*.sv`) | github.com/pulp-platform/apb_uart | `8182a85d` | Solderpad 0.51, see `uart/LICENSE.apb_uart` |
| OBI UART | `uart/rtl` (`obi_uart*.sv`) | github.com/pulp-platform/obi_peripherals | `v0.1.1` / `079894a6` | See `uart/LICENSE.obi_uart` |
| OBI | `uart/rtl` (`obi_pkg.sv`, `apb_to_obi.sv`, `include/obi`) | github.com/pulp-platform/obi | `v0.1.7` / `0155fc34` | See `uart/LICENSE.obi` |
| APB | `common/apb` | github.com/pulp-platform/apb | `v0.2.4` / `77ddf073` | See `common/apb/LICENSE` |
| Assertions header | `uart/rtl/include/common_cells` | github.com/pulp-platform/common_cells | `v1.39.0` / `9ca8a765` | Solderpad 0.51, see `uart/LICENSE.common_cells` |

Upstream's top-level `Flist.cva6` and `hpdcache.Flist` are replaced by our `sim/cva6.f`.

The assertions header comes first in the include path because the OBI code needs a newer version than the one CVA6 vendors.

## Generated DDR4 core

`ddr/rtl/litedram_core.v` is generated, not copied, so don't edit it by hand. It includes LiteDRAM's DFI-level memory model, and is for simulation only. To regenerate it, install LiteX and LiteDRAM at the commits in the table above in a private Python environment, then:

```
python scripts/gen_ddr.py rtl/third_party_ip/ddr/ddr4_sim.yml <output folder>
```

Copy `<output folder>/gateware/litedram_core.v` to `ddr/rtl/`, and `<output folder>/csr.csv` to `ddr/`. The tool ends with an error about a missing `tapcfg` package, which comes after the files are written, from a simulator helper this project doesn't use. The file's date stamp changes each time.

## USB device files

`usb/rtl` holds only the OpenTitan files that `usbdev` needs, unmodified and in one folder. Our own `rtl/adr_ip/usb/rtl/adr_usb_prims.sv` replaces the wrappers that OpenTitan normally generates, and `sim/usb_files.sv` compiles the files as one unit. Newer OpenTitan needs Verilator 5.048, so this release can only move up after a simulator upgrade.

## Placeholders

`rtl/placeholders/` has no third-party code. Its stubs are our own, and no IP has been chosen for PCIe, MIPI or graphics. Check the license, version and silicon history of any candidate before adding it here.

## Renamed module in the Ethernet MAC

`verilog-ethernet` and `common_cells` both define a module called `lfsr`, with different ports, and both are needed. In `ethernet/rtl`, the Ethernet one is renamed `eth_lfsr`: the file `lfsr.v` became `eth_lfsr.v`, and the instances are renamed in `axis_baser_rx_64.v`, `axis_baser_tx_64.v`, `eth_phy_10g_rx_if.v` and `eth_phy_10g_tx_if.v`. Nothing else in those files differs from upstream. Reapply this if the block is ever updated.

## Backported upstream fixes (all simulators and synthesis)

The owner approved this on 2026-11-16. Unlike the simulator-compatibility copies below, these copies change the design, so every simulator and synthesis use them. `sim/adr_soc.f` lists them before the `-y .../debug/rtl` library folder, so they replace the upstream modules of the same name. The upstream files in `debug/rtl/` stay unmodified and match v0.4.1 exactly.

### `debug/backport/`: RISC-V Debug specification rules for system bus access

Reason: at `e19d69ef` (v0.4.1), system bus access broke the specification's error rules:
- It forced `sbaccess` to 64-bit on every cycle, so other sizes were silently changed instead of being supported or rejected with `sberror` 4.
- It had no alignment check (`sberror` 3).
- It had no bus-error input, so a DECERR or SLVERR never set `sberror` 2 or 7. The debugger saw success and, on a read, got the error data.

Upstream fixed all of this in v0.5.0 (`05b43dd`, 2022-04-04): PR #106 (commits `b804c05`, `8814cb2`, `7119e13`) adds 8/16/32-bit accesses with byte-lane shifting and the size and alignment errors, #12 (`f3a024c`) adds the bad-address and other errors, and #127 corrects the `sbcs` reset value. These are backported as they are; nothing in them is our own logic. `adr_debug.sv` (our code) drives the two new error inputs from the AXI response: DECERR gives `master_r_err_i` (`sberror` 2) and SLVERR gives `master_r_other_err_i` (`sberror` 7). It also gives the AXI size from the byte enables instead of a fixed 8 bytes.

- `dm_sba.sv`: upstream v0.5.0, unchanged except for a two-line note after the license header.
- `dm_csrs.sv` and `dm_top.sv`: v0.4.1 with only the system bus hunks of v0.5.0, plus the same note:

```
dm_csrs.sv (v0.4.1 line numbers)
@@ 528-533: fixed sbcs fields
-    sbcs_d.sbaccess128          = 1'b0;
-    sbcs_d.sbaccess64           = logic'(BusWidth == 32'd64);
-    sbcs_d.sbaccess32           = logic'(BusWidth == 32'd32);
-    sbcs_d.sbaccess16           = 1'b0;
-    sbcs_d.sbaccess8            = 1'b0;
-    sbcs_d.sbaccess             = (BusWidth == 32'd64) ? 3'd3 : 3'd2;
+    sbcs_d.sbaccess128          = logic'(BusWidth >= 32'd128);
+    sbcs_d.sbaccess64           = logic'(BusWidth >= 32'd64);
+    sbcs_d.sbaccess32           = logic'(BusWidth >= 32'd32);
+    sbcs_d.sbaccess16           = logic'(BusWidth >= 32'd16);
+    sbcs_d.sbaccess8            = logic'(BusWidth >= 32'd8);
@@ 588 and 616: both resets of sbcs
-      sbcs_q         <= '0;
+      sbcs_q         <= '{default: '0,  sbaccess: 3'd2};

dm_top.sv (v0.4.1 line numbers)
@@ after 51: ports
+  input  logic                  master_r_err_i,
+  input  logic                  master_r_other_err_i, // *other_err_i has priority over *err_i
@@ after 166: i_dm_sba connections
+    .master_r_err_i,
+    .master_r_other_err_i,
```

Not taken from v0.5.0, because they are not system bus fixes or would change other behaviour: the `dmi_rst_ni` change (`dm_csrs` response FIFO flush and synchronous DTM reset), and the `sberror` write-1-to-clear change in `dm_csrs`. Upstream had to correct that change again in v0.8.0 (#155), so the original per-bit clear is kept. Also not taken: the later interface changes in v0.9.0 and newer (`next_dm_addr_i`, `ndmreset_ack_i`) and the 8-byte aligned halt, resume and exception addresses of v0.7.0, which would move the debug ROM entry points CVA6 uses and need their own regression.

Effects on the benches: both benches write `sbaccess` = 64-bit before every access and use aligned addresses, so their accesses are unchanged. The new `sbaccess` reset value (32-bit) only matters for a debugger that does not set it.

When riscv-dbg is updated to v0.5.0 or later, delete `debug/backport/` and its lines in `sim/adr_soc.f`, and connect the error inputs as `adr_debug.sv` does now.

## Modified copies for the commercial simulators (Questa, VCS, Xcelium)

The owner approved modifying third-party files this way on 2026-11-05, on condition that each change and its reason are documented here. The upstream files in `rtl/third_party_ip/` stay unmodified, and Verilator uses them. The commercial-simulator flows compile the copies in `sim/compat_fixes/` instead: Questa through `sim/questa.f`, VCS and Xcelium through `sim/vcs.f` / `sim/xcelium.f` and a design list the Makefile generates with the CVA6 write buffer replaced, because those simulators stop on a module defined twice. The changes keep the same logic (formal equivalence below); on any simulator, every test should give the same cycle count as on Verilator. Each copy keeps its upstream license and adds a note at the top.

Retry the upstream files when moving to a newer Questa (the copies were made for Questa 2021.2_1), and delete a copy if it is no longer needed. Reapply these changes if the upstream versions are ever updated.

### `sim/compat_fixes/id_queue.sv`
Upstream: `common/common_cells/src/id_queue.sv` (`dc555643`).

Reason: Questa stops with an internal error, `vgentd.c(671)`, while generating code for this module. A bit select on an element of a packed struct array is what triggers it. `free` is the last member of the struct and therefore bit 0, so the logic is the same.

Three lines changed (upstream line numbers):
```
235  linked_data_d[head_tail_q[match_in_idx].head][0]   = 1'b1;
  -> linked_data_d[head_tail_q[match_in_idx].head].free   = 1'b1;
260  linked_data_d[head_tail_q[match_out_idx].head][0]   = 1'b1;
  -> linked_data_d[head_tail_q[match_out_idx].head].free   = 1'b1;
400  linked_data_q[i][0] <= 1'b1;
  -> linked_data_q[i].free <= 1'b1;
```

### `sim/compat_fixes/wt_dcache_wbuffer.sv`
Upstream: `cva6/core/cache_subsystem/wt_dcache_wbuffer.sv` (`v5.3.0` / `2ef1c1b1`).

Reason: `p_tx_stat` assigns `evict = 0` and may then assign `evict = 1`, and it reads `dirty_rd_en`. `p_buffer` does the same with `dirty_rd_en` and reads `evict`. When both are 1, each process's momentary 1-0-1 retriggers the other forever in zero time, and Questa stops with `vsim-3601: Iteration limit reached`. Hardware settles at once, and Verilator does not model these glitches. Assigning `evict` once removes its glitch, so the retriggering stops. The settled value is the same.

In `p_tx_stat` (upstream line numbers):
```
322      added: automatic logic evict_next;
323      evict     = 1'b0;  -> evict_next = 1'b0;
333      evict    = 1'b1;   -> evict_next = 1'b1;
337      evict = 1'b1;      -> evict_next = 1'b1;
347      added before the end of the block: evict = evict_next;
```

### `sim/compat_fixes/dm_mem.sv`
Upstream: `debug/rtl/dm_mem.sv` (`e19d69ef`).

Reason: `p_hart_ctrl_queue` assigns `cmdbusy_o`, `go` and `resume` a default and may then override them, and `p_rw_logic` reads them. `p_rw_logic` does the same with signals that `p_hart_ctrl_queue` reads. When the debugger halts the CPU, the momentary changes retrigger both processes forever in zero time, and Questa stops with `vsim-3601: Iteration limit reached`. Assigning these three signals once at the end of the process removes their glitches. All three are only written in that process, never read there, so the settled values are the same. Changing `cmdbusy_o` alone did not stop the loop.

Changes against upstream:
```
@@ upstream line 136
+    automatic logic cmdbusy_o_next;
+    automatic logic go_next;
+    automatic logic resume_next;
@@ upstream line 140
-    go               = 1'b0;
-    resume           = 1'b0;
-    cmdbusy_o        = 1'b1;
+    go_next               = 1'b0;
+    resume_next           = 1'b0;
+    cmdbusy_o_next        = 1'b1;
@@ upstream line 146
-        cmdbusy_o = 1'b0;
+        cmdbusy_o_next = 1'b0;
@@ upstream line 165
-        cmdbusy_o = 1'b1;
-        go        = 1'b1;
+        cmdbusy_o_next = 1'b1;
+        go_next        = 1'b1;
@@ upstream line 174
-        cmdbusy_o = 1'b1;
-        resume = 1'b1;
+        cmdbusy_o_next = 1'b1;
+        resume_next = 1'b1;
@@ upstream line 182
-        cmdbusy_o = 1'b1;
-        go        = 1'b0;
+        cmdbusy_o_next = 1'b1;
+        go_next        = 1'b0;
@@ upstream line 203
+    cmdbusy_o = cmdbusy_o_next;
+    go = go_next;
+    resume = resume_next;
```

### Formal equivalence of the copies (2026-11-05)
Each copy was compared with its upstream file using the Yosys `equiv_*` flow, with the slang front end, from OSS CAD Suite `2026-11-04` (Yosys 0.70+329). Flow: `prep -flatten`, `async2sync`, `equiv_make`, `equiv_simple`, `equiv_induct`, `equiv_status -assert`. All three were checked at their real SoC parameters, extracted from a full `adr_soc_top` elaboration. Each check also had a deliberately broken copy as a control.

| Copy | Proof | Broken control |
|---|---|---|
| `id_queue.sv` | Proven on all 3 real SoC instances, extracted from the full elaboration (2 in the burst splitter, 1 in the width downsizer; ID width 6, data width 2), 170 equivalence cells each. Also proven standalone with `FULL_BW` on, and at capacity 8 with ID width 3 and data width 4 | Caught: `equiv_status` reported 4 unproven cells |
| `dm_mem.sv` | Proven at SoC parameters, 423 equivalence cells | Caught: 1 unproven cell |
| `wt_dcache_wbuffer.sv` | Proven at SoC parameters, 7183 equivalence cells, with and without `-undef` | Partial: the solver reported 17 cells as failing and 0 in the proof, but the run never completed. With `-undef` it aborted, and without it, it hit a 15-minute limit before the final status |

Limits of these results: Yosys proves the synthesized logic, assuming the slang front end reads both versions correctly, and registers are matched by name. Simulation-only `initial` blocks and assertions were ignored. Each proof holds for the parameters listed, not for every parameter value.

Check every license again before any release or tapeout.
