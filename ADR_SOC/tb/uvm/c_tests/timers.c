/***************************************************************
 Project name                  : ADR SoC
 File Name                     : timers.c
 Module/class Name             : main (test 'timers')
 Author                        : Vijay Bogati
 Description                   : PWM and watchdog test
***************************************************************/

// ADR SoC - PWM and watchdog test.
// The testbench routes PWM outputs 0-7 to GPIO inputs 0-7, so software can measure them.
// The last step lets the watchdog reset the SoC, and the second boot reports the result.

#include "adr_lib.h"

#define PWM_BASE 0x10009000UL
#define PWM_TIM(t, off) (*(volatile uint32_t *)(PWM_BASE + 0x40 * (t) + (off)))
#define PWM_CMD(t)     PWM_TIM(t, 0x00)
#define PWM_CFG(t)     PWM_TIM(t, 0x04)
#define PWM_TH(t)      PWM_TIM(t, 0x08)
#define PWM_CH_TH(t, c) PWM_TIM(t, 0x0C + 4 * (c))
#define PWM_COUNTER(t) PWM_TIM(t, 0x2C)
#define PWM_EVENT_CFG  (*(volatile uint32_t *)(PWM_BASE + 0x100))
#define PWM_CLK_EN     (*(volatile uint32_t *)(PWM_BASE + 0x104))
#define CMD_START  0x01U
#define CMD_STOP   0x02U
#define CMD_UPDATE 0x04U
#define CMD_RESET  0x08U
#define CFG_SAWTOOTH (1U << 12)
#define CFG_PRESC(p) ((uint32_t)(p) << 16)
#define OP_SET_THEN_RESET (2U << 16)  // high from the threshold to the end of the period
#define NUM_PWM_TIMERS 4
#define PWM_PERIOD 1000

#define GPIO_BASE 0x10002000UL
#define GPIO_EN   (*(volatile uint32_t *)(GPIO_BASE + 0x04))
#define GPIO_IN   (*(volatile uint32_t *)(GPIO_BASE + 0x08))

#define WDT_BASE 0x1000A000UL
#define WDT_CTRL   (*(volatile uint32_t *)(WDT_BASE + 0x00))
#define WDT_LOAD   (*(volatile uint32_t *)(WDT_BASE + 0x04))
#define WDT_COUNT  (*(volatile uint32_t *)(WDT_BASE + 0x08))
#define WDT_KICK   (*(volatile uint32_t *)(WDT_BASE + 0x0C))
#define WDT_STATUS (*(volatile uint32_t *)(WDT_BASE + 0x10))
#define WDT_KEY 0x5AFEC0DEU

#define SRC_PWM0 15
#define SRC_WDT  19

// Untouched SRAM keeps these across the watchdog's system reset.
#define MB(offset)    (*(volatile uint64_t *)(0x80070000UL + (offset)))
#define MB_BOOT_COUNT MB(0x300)
#define MB_FAILURES   MB(0x308)
#define MB_REACHED    MB(0x310)   // proves the first boot got as far as the reset step
#define REACHED_VALUE 0x57445254UL

static volatile uint32_t irq_count;
static volatile uint32_t last_id;

void adr_irq(uint64_t cause) {
  if (cause != IRQ_M_EXT) return;
  uint32_t id = PLIC_CLAIM(CTX_M);
  last_id = id;
  irq_count = irq_count + 1;
  if (id == SRC_WDT) WDT_STATUS = 1;
  if (id >= SRC_PWM0 && id < SRC_PWM0 + NUM_PWM_TIMERS) {
    PWM_EVENT_CFG = 0;
    PWM_CMD(id - SRC_PWM0) = CMD_STOP;
  }
  PLIC_CLAIM(CTX_M) = id;
}

static void enable_only(uint32_t source) {
  PLIC_PRIORITY(source) = 1;
  PLIC_THRESHOLD(CTX_M) = 0;
  PLIC_ENABLE(CTX_M) = 1U << source;
  uint32_t stale = PLIC_CLAIM(CTX_M);
  if (stale) PLIC_CLAIM(CTX_M) = stale;
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
// PWM
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
static void pwm_start(int timer, uint32_t period, uint32_t th0, uint32_t th1, uint32_t presc) {
  PWM_CFG(timer) = CFG_SAWTOOTH | CFG_PRESC(presc);
  PWM_TH(timer) = period << 16;
  PWM_CH_TH(timer, 0) = th0 | OP_SET_THEN_RESET;
  PWM_CH_TH(timer, 1) = th1 | OP_SET_THEN_RESET;
  PWM_CMD(timer) = CMD_UPDATE;
  PWM_CMD(timer) = CMD_RESET;
  PWM_CMD(timer) = CMD_START;
}

// Percentage of samples for which each of the 8 input pins was high.
static void measure_duty(uint32_t percent[8]) {
  uint32_t high[8] = {0};
  const uint32_t samples = 1000;
  for (uint32_t s = 0; s < samples; s++) {
    uint32_t pins = GPIO_IN;
    for (int p = 0; p < 8; p++) high[p] += (pins >> p) & 1;
  }
  for (int p = 0; p < 8; p++) percent[p] = high[p] * 100 / samples;
}

static int near(uint32_t value, uint32_t target) {
  return value + 6 >= target && value <= target + 6;
}

static void test_pwm(void) {
  GPIO_EN = 0xFFFF;
  PWM_CLK_EN = 0xF;

  uint32_t idle[8];
  measure_duty(idle);
  int ok = 1;
  for (int p = 0; p < 8; p++) ok &= idle[p] == 0;
  check("PWM outputs are low before starting", ok);

  // Each timer has its own pair of duty cycles. High from the threshold to the period end.
  pwm_start(0, PWM_PERIOD, 750, 250, 0);  // 25%, 75%
  pwm_start(1, PWM_PERIOD, 500, 900, 0);  // 50%, 10%
  pwm_start(2, PWM_PERIOD, 100, 600, 0);  // 90%, 40%
  pwm_start(3, PWM_PERIOD, 300, 700, 0);  // 70%, 30%
  uint32_t duty[8];
  measure_duty(duty);
  static const uint32_t want[8] = {25, 75, 50, 10, 90, 40, 70, 30};
  ok = 1;
  for (int p = 0; p < 8; p++) {
    if (!near(duty[p], want[p])) {
      ok = 0;
      uart_puts("  pin ");
      uart_puthex((uint64_t)p);
      uart_puts(" duty ");
      uart_puthex(duty[p]);
      uart_puts("\n");
    }
  }
  check("all 8 PWM outputs have their own duty cycle", ok);

  for (int t = 0; t < NUM_PWM_TIMERS; t++) PWM_CMD(t) = CMD_STOP;
  uint32_t stopped = PWM_COUNTER(0);
  for (int i = 0; i < 2000; i++) { __asm__ volatile("nop"); }
  check("stopped PWM timer holds its count", PWM_COUNTER(0) == stopped);

  // A larger prescaler counts more slowly over the same time.
  pwm_start(0, 60000, 100, 100, 0);
  pwm_start(1, 60000, 100, 100, 7);
  for (int i = 0; i < 4000; i++) { __asm__ volatile("nop"); }
  PWM_CMD(0) = CMD_STOP;
  PWM_CMD(1) = CMD_STOP;
  uint32_t fast = PWM_COUNTER(0), slow = PWM_COUNTER(1);
  check("PWM prescaler slows the count", slow > 0 && slow * 4 < fast);

  // Each timer's channel 0 event reaches its own PLIC source.
  ok = 1;
  for (int t = 0; t < NUM_PWM_TIMERS; t++) {
    enable_only(SRC_PWM0 + t);
    PWM_EVENT_CFG = (1U << (16 + t)) | ((uint32_t)(4 * t) << (4 * t));
    pwm_start(t, PWM_PERIOD, 100, 100, 0);
    WAIT_FOR(irq_count != 0);
    disable_all(SRC_PWM0 + t);
    PWM_EVENT_CFG = 0;
    PWM_CMD(t) = CMD_STOP;
    if (irq_count == 0 || last_id != (uint32_t)(SRC_PWM0 + t)) ok = 0;
  }
  check("each PWM timer event reaches its own PLIC source", ok);
  PWM_CLK_EN = 0;
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Watchdog
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Printing is slow compared with these timeouts, so every test records its results,
// stops the watchdog, and only then reports. Otherwise it could reset the SoC mid-test.
static void test_wdt_basics(void) {
  check("watchdog is off after reset", WDT_CTRL == 0 && WDT_STATUS == 0);

  WDT_LOAD = 100000;
  check("load value reads back", WDT_LOAD == 100000);
  uint32_t held = WDT_COUNT;
  for (int i = 0; i < 200; i++) { __asm__ volatile("nop"); }
  check("disabled watchdog does not count", WDT_COUNT == held);

  WDT_CTRL = 1;
  uint32_t first = WDT_COUNT;
  for (int i = 0; i < 200; i++) { __asm__ volatile("nop"); }
  uint32_t later = WDT_COUNT;
  WDT_KICK = 0x12345678;
  uint32_t after_wrong = WDT_COUNT;
  WDT_KICK = WDT_KEY;
  uint32_t after_right = WDT_COUNT;
  WDT_CTRL = 0;

  check("enabled watchdog counts down", later < first);
  check("wrong key does not reload", after_wrong < later);
  check("correct key reloads", after_right > later);
}

static void test_wdt_kick_prevents_expiry(void) {
  WDT_LOAD = 2000;
  WDT_CTRL = 1;
  for (int i = 0; i < 40; i++) {
    for (int j = 0; j < 100; j++) { __asm__ volatile("nop"); }
    WDT_KICK = WDT_KEY;
  }
  uint32_t status = WDT_STATUS;
  WDT_CTRL = 0;
  check("regular kicks prevent expiry", status == 0);
}

static void test_wdt_interrupt(void) {
  WDT_LOAD = 20000;
  enable_only(SRC_WDT);
  WDT_CTRL = 1;
  WAIT_FOR(irq_count != 0);
  WDT_CTRL = 0;
  disable_all(SRC_WDT);
  check("expiry raises the watchdog interrupt", irq_count == 1 && last_id == SRC_WDT);
  check("writing status clears expiry", WDT_STATUS == 0);
}

static void wdt_reset_soc(void) {
  int failed = adr_test_end();
  MB_FAILURES = (uint64_t)failed;
  while (!(UART_REG(UART_LSR) & 0x40)) {}  // let the text finish before the reset

  // Never clear the expiry and never kick: the second expiry resets the SoC.
  WDT_LOAD = 2000;
  MB_REACHED = REACHED_VALUE;
  WDT_CTRL = 1;
  for (int i = 0; i < 200000; i++) { __asm__ volatile("nop"); }
  MB_REACHED = 0;
  uart_puts("  FAIL  watchdog did not reset the SoC\n");
}

int main(void) {
  adr_test_begin("ADR SoC PWM and watchdog test");
  uint64_t boot = MB_BOOT_COUNT;
  MB_BOOT_COUNT = boot + 1;

  if (boot == 0) {
    test_pwm();
    test_wdt_basics();
    test_wdt_kick_prevents_expiry();
    test_wdt_interrupt();
    wdt_reset_soc();
    return 1;
  }

  check("watchdog reset restarted the program from the boot ROM", boot == 1);
  check("first boot reached the reset step", MB_REACHED == REACHED_VALUE);
  check("watchdog registers were reset", WDT_CTRL == 0 && WDT_STATUS == 0);
  check("first boot checks passed", MB_FAILURES == 0);
  return adr_test_end();
}
