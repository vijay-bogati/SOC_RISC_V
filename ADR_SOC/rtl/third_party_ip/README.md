# rtl/third_party_ip/ - open-source IP

Third-party blocks, copied from their upstream repositories at the commits listed in
[`docs/THIRD_PARTY.md`](../../docs/THIRD_PARTY.md), with their licence files and headers kept.

- The upstream files are not modified.
- The few changes ADR needs are kept outside the upstream files and documented in `docs/THIRD_PARTY.md`, each with its reason:
  - backported upstream fixes in `debug/backport/`;
  - simulator-compatible copies in `sim/compat_fixes/`;
  - a synthesis drop-in in `syn/fixes/`.

| Folder | Upstream |
|---|---|
| `cva6/` | CVA6 RV64GC CPU (OpenHW), with CVFPU and HPDcache |
| `common/` | pulp-platform AXI, APB, common cells, tech cells, register interface, AXI memory adapter, RISC-V atomics |
| `clint/`, `plic/` | CLINT (from CVA6) and PLIC (pulp-platform `rv_plic`) |
| `debug/` | RISC-V debug module (pulp-platform `riscv-dbg`) |
| `uart/`, `gpio/`, `timer/`, `spi/`, `pwm/` | pulp-platform APB peripherals |
| `i2c/` | I2C master (alexforencich `verilog-i2c`) |
| `dma/` | AXI DMA engines (alexforencich `verilog-axi`) |
| `ethernet/` | 10G/25G MAC and PCS (alexforencich `verilog-ethernet`) |
| `usb/` | USB device (lowRISC OpenTitan `usbdev` and primitives) |
| `ddr/` | DDR4 controller generated with LiteDRAM/LiteX |
| `aes_sbox/` | AES S-boxes (secworks `aes`) |

Folders named `tb/` here hold ADR's own models and UVM agents for that interface, not upstream code.
