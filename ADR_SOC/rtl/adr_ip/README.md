# rtl/adr_ip/ - blocks designed for ADR

Each block has `rtl/` (the design) and, where it has one, `tb/` (a simulation model of what sits
outside the chip, and `tb/uvm/` with its reusable UVM agent). Every block has a datasheet with its
registers in [`docs/ip/adr_ip/`](../../docs/ip/adr_ip/) (PDF in `docs/pdf/ip/adr_ip/`).

| Block | Contents |
|---|---|
| `adc/` | 8-bit SAR ADC controller, 2 channels: runs the binary search against the off-chip DAC and comparator; UVM agent for the analog side |
| `aes/` | AES with 128, 192 and 256-bit keys; round and key logic designed for ADR, S-boxes open-source |
| `aon_timer/` | 64-bit always-on timer on the real-time clock, on the power-on reset, with a compare interrupt |
| `bus_monitor/` | Bus error monitor: flags which crossbar initiator got an error response, records the first error address, raises an interrupt |
| `ddr/` | DDR4 wrapper: atomics unit and the generated LiteDRAM controller |
| `dma/` | 4-channel DMA (64-bit addresses, up to 16 MiB - 1 per copy) around an open-source AXI copy engine |
| `eth/` | 10G/25G Ethernet registers and memory access around the open-source MAC and PCS; UVM SerDes agent |
| `i2c/` | I2C APB registers and interrupt around the open-source I2C master |
| `otp/` | Controller for a 32 x 32-bit one-time-programmable memory (read, keyed bit program); OTP macro model and UVM agent |
| `pinmux/` | Pin mux for the shared GPIO pads |
| `sysctrl/` | System control: chip ID, boot pins, reset cause and software reset, two words that survive system resets, peripheral clock enables |
| `usb/` | USB 2.0 full-speed device wrapper around OpenTitan `usbdev` (APB to TL-UL, clock crossing); USB host model and UVM agent |
| `wdt/` | Watchdog |
