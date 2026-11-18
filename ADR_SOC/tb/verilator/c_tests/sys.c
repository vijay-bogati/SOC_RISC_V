/***************************************************************
 Project name                  : ADR SoC
 File Name                     : sys.c
 Module/class Name             : main (test 'sys')
 Author                        : Vijay Bogati
 Description                   : System blocks test: bus error monitor, system control and reset causes
***************************************************************/

// ADR SoC - system blocks test: bus error monitor, system control and reset causes.
// The scratch registers survive system resets, so they carry state between boots.

#include "adr_lib.h"

#define BMON_BASE 0x1000C000UL
#define BMON(off)    (*(volatile uint32_t *)(BMON_BASE + (off)))
#define BMON_STATUS  BMON(0x00)
#define BMON_ADDR_LO BMON(0x04)
#define BMON_ADDR_HI BMON(0x08)
#define BMON_IRQ_EN  BMON(0x0C)
#define READ_ERROR_CPU  (1U << 0)
#define WRITE_ERROR_CPU (1U << 4)

#define SYS_BASE 0x1000D000UL
#define SYS(off)      (*(volatile uint32_t *)(SYS_BASE + (off)))
#define SYS_CHIP_ID   SYS(0x00)
#define SYS_VERSION   SYS(0x04)
#define SYS_CAUSE     SYS(0x08)
#define SYS_RESET     SYS(0x0C)
#define SYS_SCRATCH0  SYS(0x10)
#define SYS_SCRATCH1  SYS(0x14)
#define SYS_BOOT_PINS SYS(0x18)
#define CAUSE_POWER_ON 1U
#define CAUSE_DEBUG    2U
#define CAUSE_WATCHDOG 4U
#define CAUSE_SOFTWARE 8U
#define SOFT_RESET_KEY 0x52535421U

#define WDT_BASE 0x1000A000UL
#define WDT_CTRL (*(volatile uint32_t *)(WDT_BASE + 0x00))
#define WDT_LOAD (*(volatile uint32_t *)(WDT_BASE + 0x04))

#define SRC_BMON 21
#define UNMAPPED_ADDR 0x40000000UL
#define EMPTY_SLOT_ADDR 0x10080000UL

// Each stage of the test, kept in SCRATCH0 across resets. SCRATCH1 holds failures so far.
enum { STAGE_POWER_ON = 0, STAGE_AFTER_SOFT = 1, STAGE_AFTER_WATCHDOG = 2 };

static volatile uint32_t irq_count;
static volatile uint32_t last_id;

void adr_irq(uint64_t cause) {
  if (cause != IRQ_M_EXT) return;
  uint32_t id = PLIC_CLAIM(CTX_M);
  last_id = id;
  irq_count = irq_count + 1;
  if (id == SRC_BMON) BMON_STATUS = 0xFF;
  PLIC_CLAIM(CTX_M) = id;
}

static void test_bus_monitor(void) {
  BMON_STATUS = 0xFF;
  check("no bus errors recorded after normal start-up", BMON_STATUS == 0);

  (void)*(volatile uint64_t *)UNMAPPED_ADDR;
  __asm__ volatile("fence");
  WAIT_FOR(BMON_STATUS != 0);
  check("unmapped read sets the CPU read error bit", BMON_STATUS == READ_ERROR_CPU);
  check("the address of the bad read is recorded",
        BMON_ADDR_LO == (uint32_t)UNMAPPED_ADDR && BMON_ADDR_HI == 0);

  // A second error must not replace the first address.
  (void)*(volatile uint32_t *)EMPTY_SLOT_ADDR;
  __asm__ volatile("fence");
  check("first error address is kept", BMON_ADDR_LO == (uint32_t)UNMAPPED_ADDR);
  BMON_STATUS = READ_ERROR_CPU;
  check("writing 1 clears a status bit", BMON_STATUS == 0);

  *(volatile uint64_t *)(UNMAPPED_ADDR + 0x100) = 1;
  __asm__ volatile("fence");
  WAIT_FOR(BMON_STATUS != 0);
  check("unmapped write sets the CPU write error bit", BMON_STATUS == WRITE_ERROR_CPU);
  check("the address of the bad write is recorded",
        BMON_ADDR_LO == (uint32_t)(UNMAPPED_ADDR + 0x100));
  BMON_STATUS = 0xFF;

  (void)*(volatile uint32_t *)EMPTY_SLOT_ADDR;
  __asm__ volatile("fence");
  WAIT_FOR(BMON_STATUS != 0);
  check("an empty peripheral slot is also recorded",
        BMON_STATUS == READ_ERROR_CPU && BMON_ADDR_LO == (uint32_t)EMPTY_SLOT_ADDR);
  BMON_STATUS = 0xFF;

  // Good accesses leave no record.
  volatile uint64_t good = 1;
  good = good + SYS_CHIP_ID;
  check("good accesses are not recorded", BMON_STATUS == 0);

  PLIC_PRIORITY(SRC_BMON) = 1;
  PLIC_THRESHOLD(CTX_M) = 0;
  PLIC_ENABLE(CTX_M) = 1U << SRC_BMON;
  irq_count = 0;
  last_id = 0;
  BMON_IRQ_EN = 1;
  SET_CSR(mie, 1UL << IRQ_M_EXT);
  SET_CSR(mstatus, MSTATUS_MIE);
  (void)*(volatile uint64_t *)UNMAPPED_ADDR;
  WAIT_FOR(irq_count != 0);
  CLEAR_CSR(mstatus, MSTATUS_MIE);
  CLEAR_CSR(mie, 1UL << IRQ_M_EXT);
  BMON_IRQ_EN = 0;
  PLIC_ENABLE(CTX_M) = 0;
  PLIC_PRIORITY(SRC_BMON) = 0;
  check("a bus error can raise an interrupt", irq_count == 1 && last_id == SRC_BMON);
  check("the handler cleared the record", BMON_STATUS == 0);
}

static void test_identity(void) {
  check("chip ID reads ADR1", SYS_CHIP_ID == 0x41445231);
  check("version reads 1.0", SYS_VERSION == 0x00010000);
  check("boot pins read the testbench value", SYS_BOOT_PINS == 0xA);
  SYS_CHIP_ID = 0;
  check("chip ID is read-only", SYS_CHIP_ID == 0x41445231);
}

static void finish_stage(uint32_t next_stage) {
  SYS_SCRATCH1 = SYS_SCRATCH1 + (uint32_t)adr_test_end();
  SYS_SCRATCH0 = next_stage;
  while (!(UART_REG(UART_LSR) & 0x40)) {}
}

static void stage_power_on(void) {
  check("first boot reports a power-on reset", SYS_CAUSE == CAUSE_POWER_ON);
  check("scratch starts at zero", SYS_SCRATCH1 == 0);
  test_identity();
  test_bus_monitor();

  SYS_CAUSE = CAUSE_POWER_ON;
  check("reset cause clears", SYS_CAUSE == 0);
  SYS_RESET = 0x12345678;
  for (int i = 0; i < 200; i++) { __asm__ volatile("nop"); }
  check("wrong key does not reset the system", SYS_CAUSE == 0 && SYS_SCRATCH0 == 0);

  finish_stage(STAGE_AFTER_SOFT);
  SYS_RESET = SOFT_RESET_KEY;
  for (int i = 0; i < 200000; i++) { __asm__ volatile("nop"); }
  check("software reset did not happen", 0);
  SYS_SCRATCH0 = 0xBAD;
}

static void stage_after_soft(void) {
  check("second boot reports a software reset", SYS_CAUSE == CAUSE_SOFTWARE);
  check("bus monitor settings were reset", BMON_IRQ_EN == 0);
  SYS_CAUSE = 0xF;

  finish_stage(STAGE_AFTER_WATCHDOG);
  WDT_LOAD = 2000;
  WDT_CTRL = 1;
  for (int i = 0; i < 200000; i++) { __asm__ volatile("nop"); }
  check("watchdog reset did not happen", 0);
  SYS_SCRATCH0 = 0xBAD;
}

static void stage_after_watchdog(void) {
  check("third boot reports a watchdog reset", SYS_CAUSE == CAUSE_WATCHDOG);
  check("no earlier stage failed", SYS_SCRATCH1 == 0);
}

int main(void) {
  adr_test_begin("ADR SoC system blocks test");
  uint32_t stage = SYS_SCRATCH0;
  if (stage == STAGE_POWER_ON) {
    stage_power_on();
  } else if (stage == STAGE_AFTER_SOFT) {
    stage_after_soft();
  } else if (stage == STAGE_AFTER_WATCHDOG) {
    stage_after_watchdog();
  } else {
    check("test reached an expected stage", 0);
  }
  return adr_test_end();
}
