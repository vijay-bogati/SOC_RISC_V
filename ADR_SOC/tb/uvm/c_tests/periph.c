/***************************************************************
 Project name                  : ADR SoC
 File Name                     : periph.c
 Module/class Name             : main (test 'periph')
 Author                        : Vijay Bogati
 Description                   : Peripheral test: UART1, GPIO and timer, with their PLIC interrupts
***************************************************************/

// ADR SoC - peripheral test: UART1, GPIO and timer, with their PLIC interrupts,
// plus priority between PLIC sources. The testbench provides two loopbacks:
// UART1 transmit to receive, and GPIO pins 0-7 to pins 8-15 when driven as outputs.

#include "adr_lib.h"

// UART1, same register layout as UART0.
#define UART1_BASE 0x10001000UL
#define U1(n) (*(volatile uint32_t *)(UART1_BASE + 4 * (n)))
#define LSR_DATA_READY 0x01
#define LSR_TX_IDLE    0x40
#define IER_RX_DATA    0x01

#define GPIO_BASE 0x10002000UL
#define GPIO(off) (*(volatile uint32_t *)(GPIO_BASE + (off)))
#define GPIO_DIR       GPIO(0x00)
#define GPIO_EN        GPIO(0x04)
#define GPIO_IN        GPIO(0x08)
#define GPIO_OUT       GPIO(0x0C)
#define GPIO_SET       GPIO(0x10)
#define GPIO_CLR       GPIO(0x14)
#define GPIO_INT_EN    GPIO(0x18)
#define GPIO_INT_TYPE  GPIO(0x1C)
#define GPIO_INT_STAT  GPIO(0x24)
#define TYPE_FALL 0U
#define TYPE_RISE 1U
#define TYPE_BOTH 2U
#define LOOP_OUT_PIN 0    // driven by software
#define LOOP_IN_PIN  8    // receives the same level

#define TIMER_BASE 0x10003000UL
#define TIMER(k, off) (*(volatile uint32_t *)(TIMER_BASE + 0x10 * (k) + (off)))
#define TIMER_COUNT(k) TIMER(k, 0x0)
#define TIMER_CTRL(k)  TIMER(k, 0x4)
#define TIMER_CMP(k)   TIMER(k, 0x8)
#define TIMER_ENABLE   0x1U
#define TIMER_PRESCALE(p) ((uint32_t)(p) << 3)
#define NUM_TIMERS 8

#define SRC_UART1  2
#define SRC_GPIO   3
#define SRC_TIMER0 4

static volatile uint32_t irq_count;
static volatile uint32_t last_id;
static volatile uint32_t last_uart_byte;

// The handler claims, removes the cause, and completes.
void adr_irq(uint64_t cause) {
  if (cause != IRQ_M_EXT) {
    uart_puts("  FAIL  unexpected interrupt type\n");
    return;
  }
  uint32_t id = PLIC_CLAIM(CTX_M);
  last_id = id;
  irq_count = irq_count + 1;
  if (id == SRC_UART1) {
    last_uart_byte = U1(UART_THR);  // reading the receive register removes the source
  } else if (id == SRC_GPIO) {
    (void)GPIO_INT_STAT;
  } else if (id >= SRC_TIMER0 && id < SRC_TIMER0 + NUM_TIMERS) {
    TIMER_CTRL(id - SRC_TIMER0) = 0;
  }
  PLIC_CLAIM(CTX_M) = id;
}

static void enable_only(uint32_t source) {
  PLIC_PRIORITY(source) = 1;
  PLIC_THRESHOLD(CTX_M) = 0;
  PLIC_ENABLE(CTX_M) = 1U << source;
  irq_count = 0;
  last_id = 0;
  SET_CSR(mie, 1UL << IRQ_M_EXT);
  SET_CSR(mstatus, MSTATUS_MIE);
}

static void disable_all(uint32_t source) {
  CLEAR_CSR(mstatus, MSTATUS_MIE);
  CLEAR_CSR(mie, 1UL << IRQ_M_EXT);
  PLIC_ENABLE(CTX_M) = 0;
  PLIC_PRIORITY(source) = 0;
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// UART1
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
static void uart1_init(void) {
  U1(UART_IER) = 0x00;
  U1(UART_LCR) = 0x80;
  U1(UART_DLL) = 0x02;
  U1(UART_DLM) = 0x00;
  U1(UART_LCR) = 0x03;
  U1(UART_FCR) = 0x07;
}

static int uart1_recv(uint32_t *out) {
  WAIT_FOR(U1(UART_LSR) & LSR_DATA_READY);
  if (!(U1(UART_LSR) & LSR_DATA_READY)) return 0;
  *out = U1(UART_THR) & 0xFF;
  return 1;
}

static void test_uart1(void) {
  static const uint8_t pattern[8] = {0x55, 0xAA, 0x00, 0xFF, 0x01, 0x80, 0x7E, 0x41};
  uart1_init();

  int ok = 1;
  for (int i = 0; i < 8; i++) {
    uint32_t got = 0xFFFFFFFF;
    U1(UART_THR) = pattern[i];
    ok &= uart1_recv(&got) && got == pattern[i];
  }
  check("UART1 receives each byte it sends", ok);

  // Several bytes queued at once must come back in order.
  for (int i = 0; i < 8; i++) U1(UART_THR) = pattern[i];
  ok = 1;
  for (int i = 0; i < 8; i++) {
    uint32_t got = 0xFFFFFFFF;
    ok &= uart1_recv(&got) && got == pattern[i];
  }
  check("UART1 FIFOs keep bytes in order", ok);
  check("UART1 receive FIFO empties", !(U1(UART_LSR) & LSR_DATA_READY));

  enable_only(SRC_UART1);
  U1(UART_IER) = IER_RX_DATA;
  U1(UART_THR) = 0x5A;
  WAIT_FOR(irq_count != 0);
  disable_all(SRC_UART1);
  U1(UART_IER) = 0;
  check("UART1 receive interrupt taken", irq_count == 1);
  check("UART1 interrupt uses its PLIC source", last_id == SRC_UART1);
  check("UART1 handler read the byte", last_uart_byte == 0x5A);
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// GPIO
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
static void settle(void) {
  for (int i = 0; i < 200; i++) { __asm__ volatile("nop"); }
}

static void gpio_loop_set(int high) {
  if (high) GPIO_SET = 1U << LOOP_OUT_PIN;
  else      GPIO_CLR = 1U << LOOP_OUT_PIN;
}

static void test_gpio_io(void) {
  GPIO_EN = 0xFFFF;
  GPIO_INT_EN = 0;
  GPIO_DIR = 0x0000;
  GPIO_OUT = 0x00A5;
  settle();
  check("GPIO output register reads back", GPIO_OUT == 0x00A5);
  check("pins set as inputs do not drive", (GPIO_IN >> 8) == 0);

  GPIO_DIR = 0x00FF;
  settle();
  check("GPIO direction reads back", GPIO_DIR == 0x00FF);
  check("output value reaches the input pins", (GPIO_IN >> 8) == 0xA5);

  GPIO_OUT = 0x005A;
  settle();
  check("a new output value reaches the input pins", (GPIO_IN >> 8) == 0x5A);

  GPIO_OUT = 0;
  GPIO_SET = 0x0003;
  check("set register sets only named pins", GPIO_OUT == 0x0003);
  GPIO_CLR = 0x0001;
  check("clear register clears only named pins", GPIO_OUT == 0x0002);
  GPIO_OUT = 0;
  settle();
}

static void gpio_interrupt_case(const char *name, uint32_t type, int first, int second,
                                uint32_t expected_events) {
  gpio_loop_set(first);
  settle();
  (void)GPIO_INT_STAT;
  GPIO_INT_TYPE = type << (2 * LOOP_IN_PIN);
  GPIO_INT_EN = 1U << LOOP_IN_PIN;

  enable_only(SRC_GPIO);
  gpio_loop_set(second);
  WAIT_FOR(irq_count != 0 || expected_events == 0);
  settle();
  disable_all(SRC_GPIO);
  GPIO_INT_EN = 0;
  (void)GPIO_INT_STAT;

  check(name, irq_count == expected_events && (expected_events == 0 || last_id == SRC_GPIO));
}

static void test_gpio_interrupts(void) {
  GPIO_EN = 0xFFFF;
  GPIO_DIR = 0x00FF;
  gpio_interrupt_case("rising-edge mode fires on a rise", TYPE_RISE, 0, 1, 1);
  gpio_interrupt_case("rising-edge mode ignores a fall", TYPE_RISE, 1, 0, 0);
  gpio_interrupt_case("falling-edge mode fires on a fall", TYPE_FALL, 1, 0, 1);
  gpio_interrupt_case("falling-edge mode ignores a rise", TYPE_FALL, 0, 1, 0);
  gpio_interrupt_case("both-edge mode fires on a rise", TYPE_BOTH, 0, 1, 1);
  gpio_interrupt_case("both-edge mode fires on a fall", TYPE_BOTH, 1, 0, 1);

  // The status register records the pin and clears when read.
  gpio_loop_set(0);
  settle();
  GPIO_INT_TYPE = TYPE_RISE << (2 * LOOP_IN_PIN);
  GPIO_INT_EN = 1U << LOOP_IN_PIN;
  gpio_loop_set(1);
  settle();
  uint32_t first_read = GPIO_INT_STAT;
  uint32_t second_read = GPIO_INT_STAT;
  check("status register names the pin", first_read == (1U << LOOP_IN_PIN));
  check("reading status clears it", second_read == 0);
  GPIO_INT_EN = 0;
  gpio_loop_set(0);
  settle();

  // A pulse left in the PLIC by the status test must not leak into later tests.
  PLIC_PRIORITY(SRC_GPIO) = 1;
  PLIC_ENABLE(CTX_M) = 1U << SRC_GPIO;
  uint32_t id = PLIC_CLAIM(CTX_M);
  if (id) PLIC_CLAIM(CTX_M) = id;
  PLIC_ENABLE(CTX_M) = 0;
  PLIC_PRIORITY(SRC_GPIO) = 0;
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Timer
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
static void test_timer_counting(void) {
  TIMER_CTRL(0) = 0;
  TIMER_COUNT(0) = 0;
  settle();
  check("stopped timer does not count", TIMER_COUNT(0) == 0);

  TIMER_COUNT(0) = 0;
  TIMER_COUNT(1) = 0;
  TIMER_CMP(0) = 0;
  TIMER_CMP(1) = 0;
  TIMER_CTRL(0) = TIMER_ENABLE;
  TIMER_CTRL(1) = TIMER_ENABLE | TIMER_PRESCALE(3);
  settle();
  settle();
  TIMER_CTRL(0) = 0;
  TIMER_CTRL(1) = 0;
  uint32_t fast = TIMER_COUNT(0);
  uint32_t slow = TIMER_COUNT(1);
  check("enabled timer counts", fast > 100);
  check("prescaler slows the count", slow > 0 && slow * 3 < fast);

  TIMER_CMP(2) = 0x1234;
  check("compare register reads back", TIMER_CMP(2) == 0x1234);
  TIMER_CMP(2) = 0;
}

static void test_timer_channels(void) {
  int ok = 1;
  for (int k = 0; k < NUM_TIMERS; k++) {
    enable_only(SRC_TIMER0 + k);
    TIMER_CMP(k) = 100;
    TIMER_CTRL(k) = TIMER_ENABLE;
    WAIT_FOR(irq_count != 0);
    disable_all(SRC_TIMER0 + k);
    TIMER_CMP(k) = 0;
    if (irq_count != 1 || last_id != (uint32_t)(SRC_TIMER0 + k)) ok = 0;
  }
  check("all 8 timers interrupt on compare, each on its own source", ok);

  enable_only(SRC_TIMER0 + 5);
  TIMER_COUNT(5) = 0xFFFFFFF0U;
  TIMER_CTRL(5) = TIMER_ENABLE;
  WAIT_FOR(irq_count != 0);
  disable_all(SRC_TIMER0 + 5);
  check("timer interrupts on overflow", irq_count == 1 && last_id == SRC_TIMER0 + 5);
  check("timer restarts after overflow", TIMER_COUNT(5) < 0x1000);
  TIMER_COUNT(5) = 0;
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Priority between PLIC sources, using UART1 (level) and GPIO (edge).
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
static void raise_two_sources(void) {
  U1(UART_IER) = IER_RX_DATA;
  U1(UART_THR) = 0x33;
  WAIT_FOR(PLIC_PENDING & (1U << SRC_UART1));

  gpio_loop_set(0);
  settle();
  GPIO_INT_TYPE = TYPE_RISE << (2 * LOOP_IN_PIN);
  GPIO_INT_EN = 1U << LOOP_IN_PIN;
  gpio_loop_set(1);
  WAIT_FOR(PLIC_PENDING & (1U << SRC_GPIO));
}

static void clear_source(uint32_t id) {
  if (id == SRC_UART1) {
    (void)U1(UART_THR);
    U1(UART_IER) = 0;
  } else if (id == SRC_GPIO) {
    (void)GPIO_INT_STAT;
    GPIO_INT_EN = 0;
  }
  PLIC_CLAIM(CTX_M) = id;
}

static void priority_case(const char *name, uint32_t prio_uart, uint32_t prio_gpio,
                          uint32_t first, uint32_t second) {
  raise_two_sources();
  PLIC_PRIORITY(SRC_UART1) = prio_uart;
  PLIC_PRIORITY(SRC_GPIO) = prio_gpio;
  PLIC_ENABLE(CTX_M) = (1U << SRC_UART1) | (1U << SRC_GPIO);
  PLIC_THRESHOLD(CTX_M) = 0;
  settle();

  uint32_t id1 = PLIC_CLAIM(CTX_M);
  settle();
  uint32_t id2 = PLIC_CLAIM(CTX_M);
  settle();
  uint32_t id3 = PLIC_CLAIM(CTX_M);
  clear_source(id1);
  clear_source(id2);
  PLIC_ENABLE(CTX_M) = 0;
  check(name, id1 == first && id2 == second && id3 == 0);
  gpio_loop_set(0);
  settle();
}

static void test_priority(void) {
  priority_case("higher priority claims first (GPIO over UART1)", 2, 5, SRC_GPIO, SRC_UART1);
  priority_case("higher priority claims first (UART1 over GPIO)", 6, 1, SRC_UART1, SRC_GPIO);
  priority_case("equal priority claims the lower source number", 3, 3, SRC_UART1, SRC_GPIO);
  PLIC_PRIORITY(SRC_UART1) = 0;
  PLIC_PRIORITY(SRC_GPIO) = 0;
}

int main(void) {
  adr_test_begin("ADR SoC peripheral test");
  test_uart1();
  test_gpio_io();
  test_gpio_interrupts();
  test_timer_counting();
  test_timer_channels();
  test_priority();
  return adr_test_end();
}
