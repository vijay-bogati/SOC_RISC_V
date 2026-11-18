/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_soc_pkg.sv
 Module/class Name             : adr_soc_pkg
 Author                        : Vijay Bogati
 Description                   : System parameters, address map, APB slots and CPU configuration
***************************************************************/

`include "apb/typedef.svh"

package adr_soc_pkg;

  // Fabric geometry.
  localparam int unsigned AddrWidth    = 64;
  localparam int unsigned DataWidth    = 64;
  localparam int unsigned ApbDataWidth = 32;

  // Fabric initiators.
  localparam int unsigned NumInitiators = 4;
  localparam int unsigned InitCpu       = 0;
  localparam int unsigned InitDebug     = 1;
  localparam int unsigned InitDma       = 2;
  localparam int unsigned InitEth       = 3;

  // Fabric targets. Unmapped addresses route to the error target.
  localparam int unsigned NumTargets = 7;
  localparam int unsigned TgtRom     = 0;
  localparam int unsigned TgtSram    = 1;
  localparam int unsigned TgtPeriph  = 2;  // APB peripherals and the PLIC
  localparam int unsigned TgtClint   = 3;
  localparam int unsigned TgtDebug   = 4;
  localparam int unsigned TgtError   = 5;
  localparam int unsigned TgtDdr     = 6;
  localparam int unsigned NumRules   = 9;

  // Address map.
  localparam logic [63:0] DebugBase  = 64'h0000_0000;
  localparam logic [63:0] DebugSize  = 64'h0000_1000;
  localparam logic [63:0] RomBase    = 64'h0001_0000;
  localparam logic [63:0] RomSize    = 64'h0000_8000;  // 32 KiB
  localparam logic [63:0] ClintBase  = 64'h0200_0000;
  localparam logic [63:0] ClintSize  = 64'h0001_0000;
  localparam logic [63:0] PlicBase   = 64'h0C00_0000;
  localparam logic [63:0] PlicSize   = 64'h0400_0000;
  localparam logic [63:0] PeriphBase = 64'h1000_0000;
  localparam logic [63:0] PeriphSize = 64'h0010_0000;
  localparam logic [63:0] SramBase   = 64'h8000_0000;
  localparam logic [63:0] SramSize   = 64'h0008_0000;  // 512 KiB
  localparam logic [63:0] DdrBase    = 64'h9000_0000;  // inside CVA6's cached, executable range
  localparam logic [63:0] DdrSize    = 64'h0200_0000;  // 32 MiB, the simulation model's size

  // The CPU's data cache doesn't see DMA writes. Setting this bit in a memory address reaches
  // the same memory uncached, so the CPU can read what a bus master wrote.
  localparam logic [63:0] UncachedAliasOffset = 64'h1_0000_0000;

  // Peripheral slots, 4 KiB each. Free and reserved slots return a bus error.
  // Free: 0x5000, 0x8000, 0xF000, 0x19000 to 0x1FFFF and 0x30000 up.
  localparam logic [63:0] SlotSize  = 64'h0000_1000;
  localparam logic [63:0] Uart0Base = PeriphBase + 64'h0000;
  localparam logic [63:0] Uart1Base = PeriphBase + 64'h1000;
  localparam logic [63:0] GpioBase  = PeriphBase + 64'h2000;
  localparam logic [63:0] TimerBase = PeriphBase + 64'h3000;
  localparam logic [63:0] SpiBase   = PeriphBase + 64'h4000;
  localparam logic [63:0] QspiBase  = PeriphBase + 64'h6000;
  localparam logic [63:0] I2cBase   = PeriphBase + 64'h7000;
  localparam logic [63:0] PwmBase   = PeriphBase + 64'h9000;
  localparam logic [63:0] WdtBase   = PeriphBase + 64'hA000;
  localparam logic [63:0] AesBase   = PeriphBase + 64'hB000;
  localparam logic [63:0] BusMonBase = PeriphBase + 64'hC000;
  localparam logic [63:0] SysBase   = PeriphBase + 64'hD000;
  localparam logic [63:0] DmaBase   = PeriphBase + 64'hE000;
  localparam logic [63:0] MuxBase   = PeriphBase + 64'h10000;
  localparam logic [63:0] AdcBase   = PeriphBase + 64'h11000;
  localparam logic [63:0] OtpBase   = PeriphBase + 64'h12000;
  localparam logic [63:0] AonBase   = PeriphBase + 64'h13000;
  localparam logic [63:0] EthBase   = PeriphBase + 64'h14000;
  localparam logic [63:0] UsbBase   = PeriphBase + 64'h15000;
  localparam logic [63:0] DdrCtlBase = PeriphBase + 64'h20000;
  localparam logic [63:0] DdrCtlSize = 64'h0001_0000;

  // Reserved for blocks that are only stubs today, in rtl/placeholders. Nothing decodes these.
  localparam logic [63:0] PcieBase  = PeriphBase + 64'h16000;
  localparam logic [63:0] MipiBase  = PeriphBase + 64'h17000;
  localparam logic [63:0] GpuBase   = PeriphBase + 64'h18000;

  localparam logic [63:0] BootAddr = RomBase;

  // JTAG IDCODE placeholder; a real part needs an assigned manufacturer ID.
  localparam logic [31:0] JtagIdcode = 32'h0000_0001;

  // Interrupts. The PLIC register block is fixed at 30 sources and 2 targets.
  // Source n is bit n-1 of the source vector; source 0 means "no interrupt".
  localparam int unsigned NumIrqSources  = 30;
  localparam int unsigned NumIrqTargets  = 2;  // 0: machine mode, 1: supervisor mode
  localparam int unsigned MaxIrqPriority = 7;

  localparam int unsigned NumGpioPins = 16;
  localparam int unsigned NumTimers   = 8;
  localparam int unsigned NumPwmPins  = 8;

  localparam int unsigned IrqUart0  = 1;
  localparam int unsigned IrqUart1  = 2;
  localparam int unsigned IrqGpio   = 3;
  localparam int unsigned IrqTimer0 = 4;   // timers use sources 4 to 11, one per channel
  localparam int unsigned IrqSpi    = 12;
  localparam int unsigned IrqQspi   = 14;
  localparam int unsigned IrqPwm0   = 15;  // PWM timers use sources 15 to 18, one per timer
  localparam int unsigned IrqWdt    = 19;
  localparam int unsigned IrqAes    = 20;
  localparam int unsigned IrqBusMon = 21;
  localparam int unsigned IrqDma    = 22;
  localparam int unsigned IrqI2c    = 23;  // level: high while an enabled I2C event is set
  localparam int unsigned IrqAdc    = 24;
  localparam int unsigned IrqOtp    = 25;
  localparam int unsigned IrqAon    = 26;
  localparam int unsigned IrqEth    = 27;
  localparam int unsigned IrqUsb    = 28;

  // Reserved for the stubs above, and tied to 0 until they are real.
  localparam int unsigned IrqGpu    = 13;
  localparam int unsigned IrqPcie   = 29;
  localparam int unsigned IrqMipi   = 30;

  // GPIO, timer, SPI and PWM interrupts are one-cycle pulses, so those sources are edge-triggered.
  function automatic logic [NumIrqSources-1:0] irq_edge_mask();
    logic [NumIrqSources-1:0] mask = '0;
    mask[IrqGpio - 1] = 1'b1;
    mask[IrqSpi - 1] = 1'b1;
    mask[IrqQspi - 1] = 1'b1;
    for (int i = 0; i < 4; i++) mask[IrqPwm0 - 1 + i] = 1'b1;
    for (int i = 0; i < int'(NumTimers); i++) mask[IrqTimer0 - 1 + i] = 1'b1;
    return mask;
  endfunction

  // APB slots. The APB bridge decodes one slot per block; each subsystem serves its own.
  localparam int unsigned NumApbSlots = 21;
  localparam int unsigned SlotUart0  = 0;
  localparam int unsigned SlotUart1  = 1;
  localparam int unsigned SlotGpio   = 2;
  localparam int unsigned SlotTimer  = 3;
  localparam int unsigned SlotPlic   = 4;
  localparam int unsigned SlotSpi    = 5;
  localparam int unsigned SlotQspi   = 6;
  localparam int unsigned SlotI2c    = 7;
  localparam int unsigned SlotPwm    = 8;
  localparam int unsigned SlotWdt    = 9;
  localparam int unsigned SlotAes    = 10;
  localparam int unsigned SlotBusMon = 11;
  localparam int unsigned SlotSys    = 12;
  localparam int unsigned SlotDma    = 13;
  localparam int unsigned SlotMux    = 14;
  localparam int unsigned SlotAdc    = 15;
  localparam int unsigned SlotOtp    = 16;
  localparam int unsigned SlotAon    = 17;
  localparam int unsigned SlotEth    = 18;
  localparam int unsigned SlotUsb    = 19;
  localparam int unsigned SlotDdr    = 20;

  // CLK_EN bits in system control, one gated clock each. Bits 2 and 5 are free and have no gate.
  localparam int unsigned ClkUart1 = 0, ClkSpi = 1, ClkFree2 = 2, ClkQspi = 3, ClkI2c = 4,
                          ClkFree5 = 5, ClkPwm = 6, ClkGpio = 7, ClkTimer = 8, ClkAes = 9,
                          ClkAdc = 10, NumGatedClks = 11;

  // APB request and response, 32-bit data on the 64-bit address space.
  typedef logic [AddrWidth-1:0]      apb_addr_t;
  typedef logic [ApbDataWidth-1:0]   apb_data_t;
  typedef logic [ApbDataWidth/8-1:0] apb_strb_t;
  `APB_TYPEDEF_ALL(apb, apb_addr_t, apb_data_t, apb_strb_t)

  // CPU configuration: upstream RV64GC settings, with device regions marked as
  // non-idempotent so that reads with side effects are never speculated.
  // The coprocessor port is off because nothing is connected to it. While it is on, the CPU
  // offers illegal instructions to that port and waits forever for an answer, instead of trapping.
  function automatic config_pkg::cva6_user_cfg_t cpu_user_cfg();
    config_pkg::cva6_user_cfg_t cfg = cva6_config_pkg::cva6_cfg;
    cfg.CvxifEn               = 1'b0;
    cfg.NrNonIdempotentRules  = unsigned'(2);
    cfg.NonIdempotentAddrBase = 1024'({PeriphBase, ClintBase});
    cfg.NonIdempotentLength   = 1024'({64'h1000_0000, 64'h0E00_0000});
    return cfg;
  endfunction

endpackage
