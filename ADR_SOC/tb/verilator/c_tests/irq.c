/***************************************************************
 Project name                  : ADR SoC
 File Name                     : irq.c
 Module/class Name             : main (test 'irq')
 Author                        : Vijay Bogati
 Description                   : Interrupt test: CLINT timer and software interrupts, PLIC external interrupts
***************************************************************/

// ADR SoC - interrupt test: CLINT timer and software interrupts, PLIC external interrupts.
// UART0's transmit-empty interrupt is the PLIC source because it can be raised on demand.

#include "adr_lib.h"

#define CLINT_BASE     0x02000000UL
#define CLINT_MSIP     (*(volatile uint32_t *)(CLINT_BASE + 0x0000))
#define CLINT_MTIMECMP (*(volatile uint64_t *)(CLINT_BASE + 0x4000))
#define CLINT_MTIME    (*(volatile uint64_t *)(CLINT_BASE + 0xBFF8))
#define MTIMECMP_NEVER 0xFFFFFFFFFFFFFFFFUL

#define SRC_UART0 1
#define UART_IER_THRE 0x02

static volatile uint64_t irq_soft_count;
static volatile uint64_t irq_timer_count;
static volatile uint64_t irq_ext_count;
static volatile uint64_t irq_timer_mtime;
static volatile uint32_t irq_claimed_id;

void adr_irq(uint64_t cause) {
  switch (cause) {
    case IRQ_M_SOFT:
      irq_soft_count = irq_soft_count + 1;
      CLINT_MSIP = 0;
      break;
    case IRQ_M_TIMER:
      irq_timer_count = irq_timer_count + 1;
      irq_timer_mtime = CLINT_MTIME;
      CLINT_MTIMECMP = MTIMECMP_NEVER;
      break;
    case IRQ_M_EXT:
      irq_ext_count = irq_ext_count + 1;
      irq_claimed_id = PLIC_CLAIM(CTX_M);
      UART_REG(UART_IER) = 0;  // removes the source
      PLIC_CLAIM(CTX_M) = irq_claimed_id;
      break;
    default:
      uart_puts("  FAIL  unexpected interrupt\n");
      break;
  }
}

static void test_mtime(void) {
  uint64_t first = CLINT_MTIME;
  WAIT_FOR(CLINT_MTIME > first + 10);
  check("mtime counts", CLINT_MTIME > first + 10);
}

static void test_software_interrupt(void) {
  SET_CSR(mie, 1UL << IRQ_M_SOFT);

  CLINT_MSIP = 1;
  WAIT_FOR(READ_CSR(mip) & (1UL << IRQ_M_SOFT));
  check("msip sets mip.MSIP", (READ_CSR(mip) >> IRQ_M_SOFT) & 1);
  check("no trap while mstatus.MIE is off", irq_soft_count == 0);
  check("msip reads back", CLINT_MSIP == 1);

  SET_CSR(mstatus, MSTATUS_MIE);
  WAIT_FOR(irq_soft_count != 0);
  CLEAR_CSR(mstatus, MSTATUS_MIE);
  check("software interrupt taken once", irq_soft_count == 1);
  check("mcause reports software interrupt", trap_cause == ((1UL << 63) | IRQ_M_SOFT));
  check("clearing msip clears mip.MSIP", !((READ_CSR(mip) >> IRQ_M_SOFT) & 1));

  CLEAR_CSR(mie, 1UL << IRQ_M_SOFT);
}

static void test_timer_interrupt(void) {
  CLINT_MTIMECMP = MTIMECMP_NEVER;
  check("no timer pending when mtimecmp is far away", !((READ_CSR(mip) >> IRQ_M_TIMER) & 1));
  check("mtimecmp reads back", CLINT_MTIMECMP == MTIMECMP_NEVER);

  SET_CSR(mie, 1UL << IRQ_M_TIMER);
  SET_CSR(mstatus, MSTATUS_MIE);
  uint64_t deadline = CLINT_MTIME + 200;
  CLINT_MTIMECMP = deadline;
  check("timer not fired before the deadline", irq_timer_count == 0);
  WAIT_FOR(irq_timer_count != 0);
  CLEAR_CSR(mstatus, MSTATUS_MIE);
  CLEAR_CSR(mie, 1UL << IRQ_M_TIMER);

  check("timer interrupt taken once", irq_timer_count == 1);
  check("timer fired at or after the deadline", irq_timer_mtime >= deadline);
  check("mcause reports timer interrupt", trap_cause == ((1UL << 63) | IRQ_M_TIMER));
  check("raising mtimecmp clears mip.MTIP", !((READ_CSR(mip) >> IRQ_M_TIMER) & 1));
}

static void uart_raise_irq(void) {
  while (!(UART_REG(UART_LSR) & 0x40)) {}  // let earlier text finish
  UART_REG(UART_IER) = UART_IER_THRE;
}

static void test_plic_registers(void) {
  PLIC_PRIORITY(SRC_UART0) = 5;
  check("priority reads back", PLIC_PRIORITY(SRC_UART0) == 5);
  PLIC_PRIORITY(SRC_UART0) = 0;

  PLIC_THRESHOLD(CTX_M) = 3;
  check("threshold reads back", PLIC_THRESHOLD(CTX_M) == 3);
  PLIC_THRESHOLD(CTX_M) = 0;

  PLIC_ENABLE(CTX_M) = 1U << SRC_UART0;
  check("enable reads back", PLIC_ENABLE(CTX_M) == (1U << SRC_UART0));
  PLIC_ENABLE(CTX_M) = 0;

  check("nothing to claim when idle", PLIC_CLAIM(CTX_M) == 0);
}

static void test_plic_machine_mode(void) {
  uart_raise_irq();
  WAIT_FOR(PLIC_PENDING & (1U << SRC_UART0));
  uint32_t pending = PLIC_PENDING;
  uint64_t mip_masked = READ_CSR(mip);

  PLIC_PRIORITY(SRC_UART0) = 3;
  PLIC_THRESHOLD(CTX_M) = 3;
  PLIC_ENABLE(CTX_M) = 1U << SRC_UART0;
  for (int i = 0; i < 100; i++) { __asm__ volatile("nop"); }
  uint64_t mip_at_threshold = READ_CSR(mip);

  PLIC_THRESHOLD(CTX_M) = 2;
  WAIT_FOR(READ_CSR(mip) & (1UL << IRQ_M_EXT));
  uint64_t mip_enabled = READ_CSR(mip);

  SET_CSR(mie, 1UL << IRQ_M_EXT);
  SET_CSR(mstatus, MSTATUS_MIE);
  WAIT_FOR(irq_ext_count != 0);
  CLEAR_CSR(mstatus, MSTATUS_MIE);
  CLEAR_CSR(mie, 1UL << IRQ_M_EXT);

  check("UART interrupt shows as pending", pending & (1U << SRC_UART0));
  check("disabled source does not reach the CPU", !((mip_masked >> IRQ_M_EXT) & 1));
  check("priority at threshold is blocked", !((mip_at_threshold >> IRQ_M_EXT) & 1));
  check("priority above threshold sets mip.MEIP", (mip_enabled >> IRQ_M_EXT) & 1);
  check("external interrupt taken once", irq_ext_count == 1);
  check("mcause reports external interrupt", trap_cause == ((1UL << 63) | IRQ_M_EXT));
  check("claim returns the UART source", irq_claimed_id == SRC_UART0);
  check("complete clears mip.MEIP", !((READ_CSR(mip) >> IRQ_M_EXT) & 1));
  check("nothing left to claim", PLIC_CLAIM(CTX_M) == 0);

  PLIC_ENABLE(CTX_M) = 0;
  PLIC_THRESHOLD(CTX_M) = 0;
}

static void test_plic_supervisor_context(void) {
  PLIC_PRIORITY(SRC_UART0) = 1;
  PLIC_THRESHOLD(CTX_S) = 0;
  PLIC_ENABLE(CTX_S) = 1U << SRC_UART0;
  uart_raise_irq();
  WAIT_FOR(READ_CSR(mip) & (1UL << IRQ_S_EXT));
  uint64_t mip_raised = READ_CSR(mip);

  uint32_t id = PLIC_CLAIM(CTX_S);
  UART_REG(UART_IER) = 0;
  PLIC_CLAIM(CTX_S) = id;
  for (int i = 0; i < 100; i++) { __asm__ volatile("nop"); }
  uint64_t mip_cleared = READ_CSR(mip);
  PLIC_ENABLE(CTX_S) = 0;
  PLIC_PRIORITY(SRC_UART0) = 0;

  check("supervisor context sets mip.SEIP", (mip_raised >> IRQ_S_EXT) & 1);
  check("supervisor context does not set mip.MEIP", !((mip_raised >> IRQ_M_EXT) & 1));
  check("supervisor claim returns the UART source", id == SRC_UART0);
  check("supervisor complete clears mip.SEIP", !((mip_cleared >> IRQ_S_EXT) & 1));
}

int main(void) {
  CLINT_MTIMECMP = MTIMECMP_NEVER;  // the reset value would fire immediately
  adr_test_begin("ADR SoC interrupt test");
  test_mtime();
  test_software_interrupt();
  test_timer_interrupt();
  test_plic_registers();
  test_plic_machine_mode();
  test_plic_supervisor_context();
  return adr_test_end();
}
