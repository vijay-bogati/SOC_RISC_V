# ADR SoC limitations, to revisit

Last updated 2026-11-16 (items 113 and 114: debug system bus access). The limitations of USB, Ethernet, DDR4 and the placeholders are in their own section at the end. Status means:
- **Confirmed:** seen in simulation or in the upstream source or README.
- **Expected:** reasoned from the design, not measured yet.

## Decisions to make

These can cause real problems in software or on silicon.

| # | Limitation | Impact | Options | Status |
|---|---|---|---|---|
| 1 | **Bus errors do not trap the CPU.** The write-through cache ignores AXI error responses, so a bad access completes with fixed error data (`0xCA11AB1EBADCAB1E`, or `0xDEA110C8` in an empty peripheral slot). The new bus error monitor records it and can raise an interrupt, but that arrives after the instruction has already finished. | Software can detect a wild pointer, but can't stop the instruction that caused it. The recorded address may belong to a neighbouring transfer when several are outstanding. | Use PMP to cover unmapped ranges where a precise fault is needed. Check whether another CVA6 cache option reports errors. | Confirmed |
| 2 | **PLIC is fixed at 30 sources and 2 targets.** Its register file is generated for these sizes, and addresses are hardcoded to `0x0C00_0000`. | The RTL uses 27 of them, with one each per timer channel and PWM timer. The other 3, 13, 29 and 30, are reserved for the placeholders, so none is spare: 23 went to I2C on 2026-11-07. | Fine for now. Combine channels, or regenerate the registers with the upstream `gen_plic_addrmap.py` if more are needed. | Confirmed |
| 3 | **PLIC edge sources have no event counter.** GPIO and timer are edge sources because their interrupts are one-cycle pulses. | An edge that arrives while the same source is waiting to be completed is lost. | Software should re-check the peripheral's state after completing an interrupt. | Confirmed in source |
| 30 | **GPIO has edge interrupts only.** The IP has rising, falling and both-edge modes, but the feature list also asks for level interrupts. | **Feature gap.** A device that holds an interrupt line low may be missed after its first edge. | Add level logic in our own wrapper, use software polling after an edge, or replace the IP. | Confirmed in source |
| 31 | **Timer has no interrupt status register.** | Software knows which timer fired only because each has its own PLIC source, and it can't tell compare from overflow. | Add status in our own wrapper if software needs it. | Confirmed in source |
| 36 | **QSPI has no memory-mapped flash access (XIP).** The IP is driven through registers only, so the CPU can't execute from flash. The `0x2000_0000` window is not mapped. | **Feature gap** if the chip must boot from flash. Software has to copy code to SRAM first. | Add a read-only XIP front end of our own, or choose another controller. | Confirmed in source |
| 37 | **I2C had no interrupt output.** | Resolved on 2026-11-07: our own `adr_i2c` APB block replaced the AXI4-Lite wrapper and added a level interrupt on source 23, for done, missed ACK, received data and FIFO overflow. | None. | Resolved, tested by `uart_i2c` and `i2c` |
| 112 | **A write to an absent I2C device reports two missed ACKs.** The unmodified `i2c_master` doesn't stop after the address is not acknowledged: it still sends the data byte, which is not acknowledged either, so MISS_ACK is set twice and the interrupt fires twice. | Software that counts interrupts sees two events for one failed transfer, and the bus carries a data byte nobody accepts. | Accept and document for drivers, or stop the command in our wrapper on the first missed ACK, which needs care with the unmodified engine's queues. | Confirmed in simulation, 2026-11-07 |
| 51 | **DMA is not cache-coherent in hardware.** The CPU's data cache doesn't see writes from bus masters. | **Software rule:** read such buffers through the uncached alias (bit 32 of the address), or call `dcache_invalidate()` first. Every driver must follow this, and a mistake gives stale data. `dcache_invalidate()` works in machine mode only and costs the whole cache. | Settled on 2026-11-06, with the two methods above, tested by `test_coherency()` in `tb/verilator/c_tests/dma.c`. Hardware coherence was rejected as too large a change, and flushing on `fence` as too costly once an OS runs. | Confirmed in simulation, on Verilator |
| 52 | **DMA is memory-to-memory only.** There are no peripheral request lines, so it can't pace itself to a UART or SPI FIFO. | **Feature gap** for peripheral transfers. Software must drive peripherals itself. | Add request lines in `adr_dma`. | Confirmed |
| 56 | **No analog blocks.** PLL, regulators, bandgap, power-on reset circuit, ADC analog and the OTP macro aren't implemented. All clocks are input pins, with power-on reset supplied from outside. | **Feature gap for silicon.** These must come from a foundry or analog team. | Add macro wrappers once a process is chosen. | Confirmed |
| 57 | **No power management beyond clock gating.** No sleep modes, power domains or wake-up control. | **Feature gap** for low-power use. The always-on timer interrupt doesn't wake anything yet. | Design a power controller if low power is required. | Confirmed |
| 58 | **No embedded flash controller.** Flash access is through QSPI only. | **Feature gap** if required. | Decide whether they're needed. | Confirmed |
| 59 | **The design has no pad ring,** and peripherals have both dedicated ports and pin-mux routes. The pin mux offers only PWM, UART1 TX and SPI outputs. Inputs of muxed functions are not routed. | Pin assignment isn't final. | Decide with the package and pin plan. | Confirmed |
| 4 | **Memories are simulation models.** ROM and SRAM use `adr_mem_model`, and DDR4 uses LiteDRAM's model (item 72). | Not usable for implementation. | Add technology macro wrappers once the target process is chosen. | Confirmed |
| 5 | **CLINT time base needs a real clock.** `rtc_i` is driven by the testbench. | `mtime` will not count on silicon or FPGA without one. | Add a clock source and pin once the clocking design exists. | Confirmed |
| 64 | **The CPU has more extensions than the feature list says.** The upstream configuration also enables `B`, `Zcb`, `Zicond`, `Zicntr` and `Zihpm`, while `FEATURES.md` lists RV64GC. | **Verification gap:** no test exercises them directly, so a problem would stay hidden until software uses them. They also add area. | Keep and test them, using the architecture tests in item 17, or turn off the ones not needed. | Confirmed in configuration |

## Performance

Accepted for now. Only revisit if a benchmark misses a requirement.

| # | Limitation | Impact | Options | Status |
|---|---|---|---|---|
| 6 | **One CPU AXI port.** | Instruction and data misses share one path. | Measure with CoreMark before changing anything. | Expected |
| 7 | **64-bit fabric.** | Peak 800 MB/s at 100 MHz. A 128-bit cache line takes 2 beats. DMA is the most affected. | Measure DMA and CPU traffic together. | Expected |
| 53 | **SRAM serves one burst at a time.** To avoid deadlocks, DMA read requests wait for FIFO space (see `adr_dma`), and `adr_axi_mem` collects each write before starting it, so write bursts over 16 beats aren't allowed. | CPU and DMA access to SRAM is fully serialized, and DMA throughput is limited. | Use a dual-port or banked memory design if measurements call for it. | Confirmed |
| 54 | **DMA channels run one at a time,** with 8-beat bursts. | A long transfer delays the other channels. | Split large transfers in software. | Confirmed |
| 8 | **Round-robin arbitration, with no CPU priority.** | Long DMA and Ethernet bursts can delay the CPU. | Limit DMA burst length. | Arbiter confirmed, effect expected |
| 9 | **Write-through data cache.** | Every store goes on the bus and can compete with DMA. | CVA6 also has a write-back configuration. | Expected |
| 10 | **Peripheral access is slow.** A UART register read takes about 8 clocks through the bridges. | Register-heavy drivers run slower. | Usually acceptable. | Confirmed |

## Functional restrictions

| # | Limitation | Impact | Status |
|---|---|---|---|
| 11 | **UART rejects a divisor of 1.** | Top baud rate is the clock divided by 32, or 3.125 Mbaud at 100 MHz. | Confirmed |
| 12 | **Atomics work on SRAM and DDR4 only.** Every other target answers an AXI atomic (ATOP) with SLVERR, and with the R beat an AtomicLoad, Swap or Compare needs: the ROM (`axi_atop_filter_intf` in `adr_rom`), the APB slots including the PLIC (the filter inside `axi_to_axi_lite`), and since 2026-11-15 the CLINT and the debug memory (an `axi_atop_filter` in front of each). Before that fix the CLINT and debug memory ignored `aw.atop`, took an atomic as a plain write of the operand and never sent the R beat, so the CPU hung; recorded as an exception (design behaviour missing from the specification). | Don't use atomics outside SRAM and DDR4: they fail with an error response, which the CPU does not trap on (item 1). Checked by the `amo` test (`ADR_TEST_PLAN.pdf` NEG-06 to NEG-10), which passes | Fixed for CLINT and debug memory 2026-11-15 (regression rerun); the AMO negative tests are not written yet |
| 13 | **Boot ROM writes are ignored.** | No error is returned, so a stray write goes unnoticed. | Expected, untested |
| 14 | **PLIC needs 32-bit accesses.** Byte strobes are not passed through. | Byte or halfword writes may corrupt a register. | Confirmed in source |
| 32 | **Timer behaviour is fixed.** The prescaler is 3 bits (divide by 8 at most), the count restarts at compare or overflow, there is no one-shot mode, a compare value of 0 is ignored, and writing compare resets the count. | Software must allow for this. | Confirmed in source |
| 33 | **GPIO status clears on read, and an input needs its enable bit set.** A pin's input logic only runs with `GPIOEN` set, and pad configuration outputs are unused. | Reading status twice loses events; a pin left disabled reads stale. | Confirmed in source |
| 38 | **SPI is half-duplex with a fixed clock mode.** It sends then receives, never both at once, and has no CPOL/CPHA settings. | Devices needing full duplex or other SPI modes won't work. | Confirmed in source |
| 39 | **Quad mode covers the whole QSPI transfer,** including command and address. | The flash must support 4-line commands (QPI). Common 1-1-4 reads aren't possible. | Confirmed in source |
| 42 | **PWM channels share timers.** The 8 pins come from 4 timers with 2 pins each, so paired pins share a period, and counters are 16-bit. The IP has 16 outputs; we use 8. | Only 4 independent PWM frequencies. | Confirmed |
| 43 | **Watchdog has no lock against disabling.** | Runaway software could turn it off. | Confirmed |
| 45 | **AES handles single blocks only.** There are no CBC, CTR or GCM modes in hardware, and no DMA path. | Software must do chaining and move all data. | Confirmed |
| 46 | **AES has no side-channel protection and keeps key material.** The key schedule stays in registers after use, with no clear command. Timing is constant, but there is no masking. | Not suitable for high-security key handling as it stands. | Confirmed |
| 47 | **AES area.** The schedule is held in 60 32-bit registers, which is large. | Expect a size cost; generating round keys on the fly would save area, at some complexity. | Expected, not synthesized |
| 49 | **System control has placeholder values.** Chip ID and version are placeholders. Boot pins are readable, but nothing uses them, and the CPU always starts from the boot ROM. | Boot source can't be chosen in hardware. | Confirmed |
| 60 | **ADC is 8-bit, with 2 channels and manual start.** No scan mode or continuous conversion. | Software starts each conversion. | Confirmed |
| 61 | **OTP has no read protection, and its macro interface is our own assumption.** The key is a fixed value, a soft guard only. | A real macro will need adapting, and secrets stored in OTP are readable by software. | Expected |
| 15 | **One hart only.** | CLINT, PLIC and debug are set up for a single core. | Confirmed |
| 26 | **Debug has no authentication or trigger module.** | Anyone with JTAG access has full control, which matters on a shipped part. The debug module's trigger registers are absent. | Confirmed in upstream README |
| 27 | **Debug bus is 64-bit at most, and JTAG must run slower than the system clock.** | Only TCK at one eighth of the clock has been tested. | Confirmed in upstream README |
| 28 | **JTAG IDCODE is a placeholder.** | A real part needs an assigned manufacturer ID. | Confirmed |
| 113 | **System bus access reports every SLVERR as `sberror` 7 ("other").** Since 2026-11-16, SBA follows the RISC-V Debug specification's error rules (upstream `riscv-dbg` v0.5.0 backported, see `THIRD_PARTY.md`): DECERR gives 2, a misaligned address 3, an unsupported size 4. | A debugger can't tell an SLVERR from a peripheral (for example an atomic filter or `PSLVERR`) from other target errors. | Expected from the RTL; not simulated yet. Check written: test `sba` (`ADR_TEST_PLAN.pdf` NEG-11, NEG-14), not run |
| 114 | **An 8 or 16-bit system bus write to an APB peripheral writes its whole 32-bit register.** Every APB block except I2C ignores `PSTRB` (`MICROARCHITECTURE.md`, section 4.2), the same as for CPU byte stores. | Debugger byte writes to a peripheral register corrupt its other bytes. Use 32-bit SBA for peripheral registers, which touches only that register. | Expected from the RTL; not simulated yet. Check written: test `sba` (`ADR_TEST_PLAN.pdf` NEG-16), not run |

## Verification gaps

| # | Gap | Status |
|---|---|---|
| 16 | **Questa 2021.2_1 needs modified copies of three third-party files,** plus `+acc=bcglnprst` because `vopt` crashes without the `g` flag. See `THIRD_PARTY.md`. Formal equivalence results for the copies are in the same file. | Confirmed |
| 17 | **No CPU compliance run.** RISC-V architecture tests, supervisor mode, the MMU and Linux boot are all untested on this SoC. | Confirmed |
| 20 | **No random traffic or formal checks on the fabric.** Only the accesses in the C tests have been exercised. | Confirmed |
| 40 | **SPI and I2C are tested against our own simple device models,** not vendor flash or device models. Clock divider and prescale were tested at one setting each, with no clock stretching. | Confirmed |
| 41 | **AddressSanitizer reports an out-of-bounds read** in Verilator's generated code for the unmodified CVA6 instruction cache. It's a read in the simulator only, not a design defect. A fix would mean a newer Verilator or a change upstream. | Confirmed |
| 44 | **PWM tested by sampling through GPIO inputs,** so duty cycles are checked to about 6%, and only sawtooth mode with the set-then-reset output is covered. | Confirmed |
| 48 | **AES tested with 4 published vectors only.** The longer NIST test suites (KAT, Monte Carlo) have not been run. | Confirmed |
| 55 | **DMA tests are directed, not random.** Peripheral-register targets are untested. Only bus errors on the CPU and on DMA reads and writes are covered by the bus monitor test. | Confirmed |
| 62 | **`misc` test depth.** The pin mux checks only PWM and the UART1 idle level on the pads, not data or SPI. Clock gating is tested on the timer only, and without proving the clock actually stopped. Gating timing across clock domains hasn't been analysed. | Confirmed |
| 34 | **UART tested at 8N1 and divisor 2 only.** Parity, stop-bit options, error flags and other baud rates are untested. Peripherals are tested through testbench loopbacks, not external device models. | Confirmed |
| 35 | **Timer tests cover one compare and one overflow per scenario.** Long runs and all prescaler values are untested. | Confirmed |
| 29 | **Debug test uses our own JTAG driver, not OpenOCD or GDB.** Real debugger tools have not been connected. | Confirmed |

## Older third-party IP

| # | Block | Limitation | Status |
|---|---|---|---|
| 23 | SPI (`apb_spi_master`) | Last updated in 2018. | Confirmed |
| 24 | PWM (`apb_adv_timer`) | 4 timers with 2 pins each make the 8 channels, so paired pins share a period. | Confirmed |

## New IP: USB, Ethernet, DDR4 and placeholders

Added on 2026-11-06. All three blocks are bring-up quality: they pass sanity tests in simulation only, against simple test partners. None has been on an FPGA or silicon in this design.

### Ethernet

| # | Limitation | Impact | Options | Status |
|---|---|---|---|---|
| 68 | **Ethernet has no descriptor rings or address filter.** Software gives one buffer at a time and sees every frame. | **Feature gap** for sustained traffic or an OS driver. A frame arriving while the receive FIFO is full is lost. | Add rings and filtering in `adr_eth`. | Confirmed |
| 69 | **A transmit bus error still sends a frame** with the bus's error data. | The far end receives a frame with a valid CRC and bad data. | Software must check before sending, or use a store-and-forward check in `adr_eth`. | Confirmed in simulation |
| 74 | **TX done means the memory read finished, not that the frame was sent.** The flag comes from the memory engine, when the frame is in the MAC's FIFO. | Software can't tell when a frame has left the pins, and a stopped transmit clock still reports done. | Add a done signal from the MAC's transmit side. | Confirmed in source |
| 75 | **Frames must fit the 4 KiB FIFOs.** A longer frame is dropped, on transmit as well, while TX done is still reported. There are no jumbo frames. | A frame over 4 KiB is lost, with nothing telling software. | Connect the FIFO overflow status, or check the length in software. | Confirmed in source |
| 76 | **25G is unproven.** The MAC and PCS are designed for 10G/25G and FPGA-proven upstream, but this SoC has only looped back at the SerDes interface, on a 156.25 MHz (10G) clock. No timing work has been done for 390.625 MHz, and the analog SerDes is outside the SoC. | **Reaching 25G needs a SerDes and timing closure at 390.625 MHz.** Nothing here proves it would close on a real process. | Try it on an FPGA with a 25G transceiver, then in the target process. | Confirmed |
| 111 | **The bus monitor holds at most 4 initiators,** and all 4 are in use. Its STATUS register has 4 read bits and 4 write bits. | A 5th bus master, such as real PCIe or graphics, would overlap the write bits. | Change the register layout when adding one. | Confirmed in source |
| 109 | **Sustained 25G isn't possible with this memory path.** It's 64 bits on `clk_i`, which is 6.4 Gbit/s at 100 MHz, shared with the other bus masters. Each frame is stored in a FIFO, then sent at the line rate. | **Single frames go at line rate, but sustained traffic is limited** to what the fabric can deliver, and receive frames are dropped when the FIFO fills. | Raise the fabric clock to about 390 MHz or more, or widen the path. | Confirmed in source |
| 110 | **Only one line rate at a time, and no 1G.** This MAC doesn't do 1G or lower, and the rate is fixed by the clocks and `Count125us`. The earlier 1G GMII MAC was replaced. | A 1G link can't be used. | Add the 1G MAC back as a second port if needed. | Confirmed |
| 77 | **No MDIO.** The SoC can't read or configure the PHY's registers, or see link state. | **Feature gap:** software can't detect link up or down. GPIO could be used for this instead. | Add an MDIO master. | Confirmed |
| 78 | **No pause frames, VLAN, checksum offload, timestamps or counters.** The MAC's error and overflow status signals are left unconnected, apart from bad-CRC frames. | Dropped frames aren't counted. All protocol work is in software, and there's no flow control if the receiver falls behind. | Connect the status signals to counters. Add the others as needed. | Confirmed in source |
| 79 | **Ethernet is outside clock gating,** with no `CLK_EN` bit. **Its resets need `eth_tx_clk_i` and `eth_rx_clk_i` running.** | It can't be gated to save power. Without the SerDes clocks, that side stays in reset. | Add a gate if power matters. | Confirmed in source |
| 80 | **The FIFOs are plain RTL arrays,** two of 4 KiB, not memory macros. | Costs area on silicon, as flip-flops unless a tool maps them to RAM. | Map them to macros for implementation. | Expected |
| 70 | **`verilog-ethernet` is the final MIT version.** Upstream moved to `taxi` under a different license, and only FPGA use is proven. | No more upstream fixes. No silicon history. | Accept for now. | Confirmed |
| 81 | **One upstream file set is modified:** `lfsr` is renamed `eth_lfsr` in three files, because `common_cells` has a different module of that name. | An exception to the rule that third-party code is unmodified. It must be reapplied on any update. | Keep, as documented in `THIRD_PARTY.md`. | Confirmed |

### USB device

| # | Limitation | Impact | Options | Status |
|---|---|---|---|---|
| 65 | **USB is full speed and device only.** OpenTitan `usbdev` runs at 12 Mbit/s, with no high speed (480 Mbit/s) or host mode. | **Feature gap** for anything needing more. Open high-speed cores are FPGA-level only. | Accept, or look for a high-speed core with a ULPI or UTMI transceiver. | Confirmed |
| 66 | **USB uses an older OpenTitan release.** Newer versions need Verilator 5.048, and the project has 5.020. | Upstream fixes after October 2024 aren't included. | Move up after a simulator upgrade. | Confirmed |
| 67 | **USB registers hang if `usb_clk_i` stops.** | A register access never finishes, which stalls the CPU. | Keep the clock running, or add a timeout or a clock-off response in the bridge. | Confirmed in source |
| 82 | **It needs an accurate clock.** The start-of-frame reference outputs that a real part uses to trim its oscillator aren't connected. | `usb_clk_i` must be a precise 48 MHz from outside, such as a crystal. No clock tolerance has been tested. | Connect the reference outputs to an adjustable oscillator, if the SoC gets one. | Confirmed in source |
| 83 | **Limits of the block:** 12 endpoints, 64-byte packets and a 2 KiB buffer of 32 packets. It has no DMA, so the CPU copies every packet. | Throughput depends on software, and USB adds CPU load. Isochronous use is untested. | Accept. Faster use would need a different core. | Confirmed in source |
| 84 | **Single-ended pins only.** The differential receiver input and the alternate transmit outputs aren't brought out, and the transceiver is outside the SoC. | Limits which transceivers can connect. The D+ pull-up also needs an external circuit. | Bring the other signals out when a transceiver is chosen. | Confirmed in source |
| 85 | **No wake from USB.** The always-on wake logic isn't included, and its inputs are tied off. Link suspend only raises an interrupt. | The block can't track the bus while its clock is off, or wake the SoC. No suspend or resume has been tested. | Add `usbdev_aon_wake` along with a power controller. | Confirmed in source |
| 86 | **Alerts aren't collected.** The block reports bus integrity failures on an alert output, which isn't connected. | A corrupted register access in the block goes unnoticed by software. | Add an alert status bit or interrupt in `adr_usb`. | Confirmed in source |
| 87 | **All 18 interrupts share PLIC source 28.** | Software must read `INTR_STATE` to see which one fired. | Accept. | Confirmed in source |
| 88 | **USB is outside clock gating,** with no `CLK_EN` bit. | It can't be gated from system control. | Add a gate, along with a safe response for register accesses, as item 67 needs. | Confirmed in source |
| 89 | **Generic primitives.** `adr_usb_prims.sv` hand-writes wrappers for OpenTitan's generic primitives, including the packet buffer RAM, and the generated `top_pkg` is copied from Earl Grey. | The RAM is a behavioural model, and needs a macro. Security-hardened cells are not used. | Replace them for a target process. | Confirmed |
| 90 | **The simulators check it differently.** OpenTitan's assertions are active on Questa, but compiled out on Verilator. A false `vlog-7033` multiple-driver error in `usbdev.sv` is suppressed on Questa, in `vlog` and `vsim`, for the whole design. | An assertion failure would only show on Questa. A real instance of that error elsewhere in the design wouldn't be reported. | Scope the suppression if a newer Questa allows it. | Confirmed |
| 91 | **No USB software.** There's no enumeration, descriptors or class driver, only the register-level test. | The chip can't appear as a real USB device yet. | Write a device stack. | Confirmed |

### DDR4

| # | Limitation | Impact | Options | Status |
|---|---|---|---|---|
| 72 | **DDR4 is a simulation model only.** The generated core contains LiteDRAM's DFI-level memory model, with no PHY or memory device, runs on `clk_i`, and has a reduced 32 MiB geometry. | **Not usable on silicon or FPGA.** Passing tests don't prove real DRAM timing, training or init. | Generate a core with a real PHY, add a clock crossing and an init sequence. LPDDR4 needs a separate flow, as `litedram_gen` doesn't support it. | Confirmed |
| 73 | **A system reset doesn't reset the DDR4 core,** as the generated core has no reset input. Since 2026-11-15 a warm reset (watchdog, software, debug module) first drains the DDR4 port: `adr_ddr_drain` stops new transactions, and `adr_rst_gen` asserts the reset once none is outstanding, or after 1,024 clocks (then `RESET_CAUSE[4]` is set). Memory contents survive a warm reset. | A core that cannot finish a transaction within 1,024 clocks still gets cut; `RESET_CAUSE[4]` shows it, and only a power-on reset clears the core. Reset during DDR4 traffic is not yet tested (`ADR_TEST_PLAN.pdf` NEW-14). | For a real part, generate the core with a reset input on the power-on reset. | Drain added 2026-11-15 (regression rerun); reset during traffic not yet run |
| 92 | **No LPDDR4.** `litedram_gen` accepts SDR, DDR2, DDR3 and DDR4 only. LiteDRAM's LPDDR4 support is tied to its own PHYs and simulation flow. | **Feature gap** against the plan, which asked for DDR4 or LPDDR4. | Build a separate flow around LiteDRAM's LPDDR4 PHY when needed. | Confirmed in source |
| 93 | **No DFI port.** The model sits inside the generated core, so there's no boundary to attach a PHY to, though the plan called for the controller up to DFI. | A real PHY can't be connected to this core as it stands. | Write a generator variant that brings DFI out. | Confirmed |
| 94 | **No init or training.** Software runs no init sequence, the "init done" flag is unused, and the user port isn't held back. There's no read or write levelling. | This only works because the model needs none. Real DRAM would fail at once. | Add a software init routine, and hold the port until it finishes. | Confirmed |
| 95 | **Timing is set for 100 MHz only.** The core runs on `clk_i` with timing values worked out at generation, for a 1:4 ratio. Other frequencies need regenerating. | `clk_i` can't change without a new core. No DDR speed grade has been exercised. | Give it its own clock and a crossing. | Confirmed in source |
| 96 | **Address space limits.** The 32 MiB size is fixed in `adr_soc_pkg`, and CVA6's upstream cached and executable rules end at `0xBFFF_FFFF`. | At most 768 MiB fits at this base address without changing the CPU configuration. | Extend those rules in `cpu_user_cfg()` for larger parts. | Confirmed in source |
| 97 | **Performance is unmeasured,** with one AXI port shared by all initiators, and an atomics unit in front allowing 1 write in flight. | Throughput and latency under CPU, DMA and Ethernet load are unknown. | Measure under real traffic. | Expected |
| 98 | **No ECC.** | Bit errors in DRAM aren't detected. | LiteDRAM has ECC options, and they need a wider data path. | Confirmed |
| 99 | **Control registers are open.** Software can take the controller out of hardware control through the registers at `0x1002_0000`, which would stop DDR4 accesses. Only one register is touched by the test. | A stray write could hang memory access. | Restrict access with PMP. | Expected |
| 100 | **The core is generated code,** about 12,000 lines, and isn't meant to be read or edited. Regenerating needs LiteX and LiteDRAM installed at the pinned commits, and adds a date stamp to the file. | It's hard to review, and small settings can have large effects. Two settings caused hangs during bring-up. | Keep the settings file and `scripts/gen_ddr.py` as the source. | Confirmed |
| 101 | **DDR4 is outside clock gating and always built.** The 32 MiB model is in every test's simulation. | Slower and larger simulations, including tests that don't use DDR4. | Make it optional at build time if run time matters. | Confirmed |

### Shared effects on the SoC

| # | Limitation | Impact | Options | Status |
|---|---|---|---|---|
| 102 | **New clock inputs have had no crossing analysis.** `eth_tx_clk_i`, `eth_rx_clk_i` and `usb_clk_i` cross into `clk_i` through upstream FIFOs. Simulation only used one set of frequencies, chosen so that no clock edges coincide. | Real crossing problems wouldn't show up in these tests. Timing analysis hasn't been done either. | Run CDC analysis, and test other clock ratios. | Confirmed |
| 103 | **More bus masters, and no priority.** Ethernet is a fourth initiator with round-robin arbitration, and there's no timeout on any bus. | Ethernet traffic can delay the CPU, and a stuck target hangs its initiator for good, as USB can without its clock. | Measure it. Add a bus timeout if needed. | Expected |
| 104 | **SRAM write buffer.** `adr_axi_mem` now holds each write until its burst has arrived, with a limit of 16 beats. | A longer write burst to SRAM or ROM would hang. Current masters use at most 8 beats. Writes take a little longer, and all cycle baselines moved. | Keep any new master to 16 beats or fewer. | Confirmed in source |

### Placeholders

| # | Limitation | Impact | Options | Status |
|---|---|---|---|---|
| 105 | **PCIe, MIPI and graphics are stubs.** `rtl/placeholders/` only fixes a register port. They're not built, not connected and never simulated, and no IP candidate has been chosen. Register slots `0x1001_6000` to `0x1001_8000` and PLIC sources 29, 30 and 13 are reserved for them in the docs, but memory windows and crossbar ports aren't. | No function exists. They'd need analog PHYs, bus masters, and in the case of graphics DDR4 bandwidth. | Survey IP when these become a priority. | Confirmed |

### Verification of the new IP

| # | Gap | Status |
|---|---|---|
| 71 | **Ethernet and USB tests are sanity tests.** Ethernet is looped back at the SerDes interface on a 156.25 MHz (10G) clock, with no bad-CRC frames, bit errors, bit slip, link loss, SerDes model or back-to-back traffic. USB uses our own simple host, with no enumeration, stalls, data toggle errors, suspend or real clock tolerance. | Confirmed |
| 106 | **DDR4 is tested on a model at DFI level.** The test covers CPU access, cache refills, DMA, atomics and running code, with no real DRAM timing, refresh stress, training, or traffic from Ethernet. | Confirmed |
| 107 | **Ethernet and USB don't use DDR4 in their tests,** and no test runs all the new blocks at the same time. | Confirmed |
| 108 | **Our own test partners.** The USB host and the Ethernet loopback were written for these tests, so a shared misunderstanding of a protocol wouldn't be caught, unlike with a vendor model. | Confirmed |
