/***************************************************************
 Project name                  : ADR SoC
 File Name                     : misc.c
 Module/class Name             : main (test 'misc')
 Author                        : Vijay Bogati
 Description                   : Test of pin mux, ADC controller, OTP controller and always-on timer
***************************************************************/

// ADR SoC - test of the remaining system blocks: pin mux, ADC controller, OTP controller,
// always-on timer and peripheral clock gating. The testbench provides the ADC analog model
// (channel 0 reads 0x5A, channel 1 reads 0xC3) and an OTP macro model.

#include "adr_lib.h"

#define GPIO_BASE 0x10002000UL
#define GPIO_DIR (*(volatile uint32_t *)(GPIO_BASE + 0x00))
#define GPIO_EN  (*(volatile uint32_t *)(GPIO_BASE + 0x04))
#define GPIO_IN  (*(volatile uint32_t *)(GPIO_BASE + 0x08))
#define GPIO_OUT (*(volatile uint32_t *)(GPIO_BASE + 0x0C))

#define PWM_BASE 0x10009000UL
#define PWM_TIM(t, off) (*(volatile uint32_t *)(PWM_BASE + 0x40 * (t) + (off)))
#define PWM_CLK_EN (*(volatile uint32_t *)(PWM_BASE + 0x104))

#define TIMER_COUNT0 (*(volatile uint32_t *)(0x10003000UL))
#define TIMER_CTRL0  (*(volatile uint32_t *)(0x10003004UL))

#define SYS_BASE 0x1000D000UL
#define SYS_RESET    (*(volatile uint32_t *)(SYS_BASE + 0x0C))
#define SYS_SCRATCH0 (*(volatile uint32_t *)(SYS_BASE + 0x10))
#define SYS_SCRATCH1 (*(volatile uint32_t *)(SYS_BASE + 0x14))
#define SYS_CLK_EN   (*(volatile uint32_t *)(SYS_BASE + 0x1C))
#define SOFT_RESET_KEY 0x52535421U
#define CLK_GPIO  (1U << 7)
#define CLK_TIMER (1U << 8)

#define BMON_STATUS (*(volatile uint32_t *)0x1000C000UL)

#define MUX_BASE  0x10010000UL
#define MUX_LOW   (*(volatile uint32_t *)(MUX_BASE + 0x00))
#define MUX_HIGH  (*(volatile uint32_t *)(MUX_BASE + 0x04))

#define ADC_BASE  0x10011000UL
#define ADC_CTRL   (*(volatile uint32_t *)(ADC_BASE + 0x00))
#define ADC_STATUS (*(volatile uint32_t *)(ADC_BASE + 0x04))
#define ADC_DATA   (*(volatile uint32_t *)(ADC_BASE + 0x08))
#define ADC_DIV    (*(volatile uint32_t *)(ADC_BASE + 0x0C))
#define ADC_START 1U
#define ADC_CH1   2U
#define ADC_IRQ   4U
#define ADC_DONE  2U

#define OTP_BASE  0x10012000UL
#define OTP_ADDR   (*(volatile uint32_t *)(OTP_BASE + 0x00))
#define OTP_WDATA  (*(volatile uint32_t *)(OTP_BASE + 0x04))
#define OTP_RDATA  (*(volatile uint32_t *)(OTP_BASE + 0x08))
#define OTP_CMD    (*(volatile uint32_t *)(OTP_BASE + 0x0C))
#define OTP_KEY    (*(volatile uint32_t *)(OTP_BASE + 0x10))
#define OTP_STATUS (*(volatile uint32_t *)(OTP_BASE + 0x14))
#define OTP_IRQ_EN (*(volatile uint32_t *)(OTP_BASE + 0x18))
#define OTP_READ 1U
#define OTP_PROGRAM 2U
#define OTP_BUSY 1U
#define OTP_DONE 2U
#define OTP_ERROR 4U
#define OTP_PROGRAM_KEY 0x4F545021U

#define AON_BASE  0x10013000UL
#define AON_CTRL     (*(volatile uint32_t *)(AON_BASE + 0x00))
#define AON_COUNT_LO (*(volatile uint32_t *)(AON_BASE + 0x04))
#define AON_CMP_LO   (*(volatile uint32_t *)(AON_BASE + 0x0C))
#define AON_CMP_HI   (*(volatile uint32_t *)(AON_BASE + 0x10))
#define AON_STATUS   (*(volatile uint32_t *)(AON_BASE + 0x14))

#define SRC_ADC 24
#define SRC_OTP 25
#define SRC_AON 26

// Untouched SRAM keeps these across the system reset.
#define MB(offset)    (*(volatile uint64_t *)(0x80070000UL + (offset)))
#define MB_FAILURES   MB(0x308)
#define MB_REACHED    MB(0x310)
#define REACHED_VALUE 0x4D495343UL

static volatile uint32_t irq_count;
static volatile uint32_t last_id;

void adr_irq(uint64_t cause) {
  if (cause != IRQ_M_EXT) return;
  uint32_t id = PLIC_CLAIM(CTX_M);
  last_id = id;
  irq_count = irq_count + 1;
  if (id == SRC_ADC) ADC_STATUS = ADC_DONE;
  if (id == SRC_OTP) OTP_STATUS = OTP_DONE;
  if (id == SRC_AON) AON_STATUS = 1;
  PLIC_CLAIM(CTX_M) = id;
}

static void irq_on(uint32_t source) {
  PLIC_PRIORITY(source) = 1;
  PLIC_THRESHOLD(CTX_M) = 0;
  PLIC_ENABLE(CTX_M) = 1U << source;
  irq_count = 0;
  last_id = 0;
  SET_CSR(mie, 1UL << IRQ_M_EXT);
  SET_CSR(mstatus, MSTATUS_MIE);
}

static void irq_off(uint32_t source) {
  CLEAR_CSR(mstatus, MSTATUS_MIE);
  CLEAR_CSR(mie, 1UL << IRQ_M_EXT);
  PLIC_ENABLE(CTX_M) = 0;
  PLIC_PRIORITY(source) = 0;
}

static void settle(void) {
  for (int i = 0; i < 200; i++) { __asm__ volatile("nop"); }
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Pin mux. Pads 0-7 loop back to pads 8-15 in the testbench.
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
static void test_pinmux(void) {
  GPIO_EN = 0xFFFF;
  GPIO_DIR = 0x00FF;
  GPIO_OUT = 0x0003;
  settle();
  check("pads default to GPIO", MUX_LOW == 0 && MUX_HIGH == 0 && ((GPIO_IN >> 8) & 0x3) == 0x3);

  // Function 1 on pad 0 is PWM 0, which is idle and low, so the pad must drop.
  MUX_LOW = 0x0001;
  check("mux register reads back", MUX_LOW == 0x0001);
  settle();
  check("function 1 replaces GPIO on its pad only", ((GPIO_IN >> 8) & 0x3) == 0x2);

  // PWM 0 running on pad 0 must toggle pin 8.
  PWM_CLK_EN = 1;
  PWM_TIM(0, 0x04) = 1U << 12;                // sawtooth
  PWM_TIM(0, 0x08) = 100U << 16;              // period
  PWM_TIM(0, 0x0C) = 50U | (2U << 16);        // set at 50, reset at the end
  PWM_TIM(0, 0x00) = 4;                       // update
  PWM_TIM(0, 0x00) = 8;                       // reset
  PWM_TIM(0, 0x00) = 1;                       // start
  int high = 0, low = 0;
  for (int i = 0; i < 200; i++) {
    if ((GPIO_IN >> 8) & 1) high++;
    else low++;
  }
  PWM_TIM(0, 0x00) = 2;
  PWM_CLK_EN = 0;
  check("PWM reaches the pad through the mux", high > 0 && low > 0);

  // Function 2 on pad 0 is UART1 transmit, which idles high.
  GPIO_OUT = 0x0000;
  MUX_LOW = 0x0002;
  settle();
  check("function 2 on pad 0 carries UART1 transmit", ((GPIO_IN >> 8) & 1) == 1);

  MUX_LOW = 0;
  settle();
  check("selecting GPIO again restores the pad", ((GPIO_IN >> 8) & 1) == 0);
  GPIO_DIR = 0;
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// ADC
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
static int adc_read(uint32_t channel_bit, uint32_t *out) {
  ADC_CTRL = ADC_START | channel_bit;
  WAIT_FOR(ADC_STATUS & ADC_DONE);
  if (!(ADC_STATUS & ADC_DONE)) return 0;
  *out = ADC_DATA;
  ADC_STATUS = ADC_DONE;
  return 1;
}

static void test_adc(void) {
  uint32_t value = 0;
  check("ADC channel 0 converts to the expected value", adc_read(0, &value) && value == 0x5A);
  check("ADC channel 1 converts to the expected value", adc_read(ADC_CH1, &value) && value == 0xC3);
  ADC_DIV = 2;  // the compare input's synchronizer takes 2 clocks, so this is the fastest
  check("ADC works at the fastest divider", adc_read(0, &value) && value == 0x5A);
  ADC_DIV = 3;
  check("ADC done clears", !(ADC_STATUS & ADC_DONE));

  irq_on(SRC_ADC);
  ADC_CTRL = ADC_START | ADC_IRQ;
  WAIT_FOR(irq_count != 0);
  irq_off(SRC_ADC);
  ADC_CTRL = 0;
  check("ADC done raises its interrupt", irq_count == 1 && last_id == SRC_ADC);
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// OTP
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
static int otp_command(uint32_t command) {
  OTP_CMD = command;
  WAIT_FOR(OTP_STATUS & OTP_DONE);
  return (OTP_STATUS & OTP_DONE) != 0;
}

static uint32_t otp_read(uint32_t address) {
  OTP_ADDR = address;
  otp_command(OTP_READ);
  OTP_STATUS = OTP_DONE;
  return OTP_RDATA;
}

static void otp_program(uint32_t address, uint32_t bits) {
  OTP_ADDR = address;
  OTP_WDATA = bits;
  OTP_KEY = OTP_PROGRAM_KEY;
  otp_command(OTP_PROGRAM);
  OTP_STATUS = OTP_DONE | OTP_ERROR;
}

static void test_otp(void) {
  check("blank OTP reads zero", otp_read(4) == 0);

  otp_program(4, 0x0000F00F);
  check("programmed bits read back", otp_read(4) == 0x0000F00F);
  check("another word is unaffected", otp_read(5) == 0);

  // Programming can only turn bits on.
  otp_program(4, 0x00000FF0);
  check("programming adds bits and never clears them", otp_read(4) == 0x0000FFFF);

  // Without the key nothing changes.
  OTP_ADDR = 6;
  OTP_WDATA = 0xFFFFFFFF;
  otp_command(OTP_PROGRAM);
  check("program without the key reports an error", OTP_STATUS & OTP_ERROR);
  OTP_STATUS = OTP_DONE | OTP_ERROR;
  check("program without the key changes nothing", otp_read(6) == 0);

  // The key allows only one command.
  OTP_KEY = OTP_PROGRAM_KEY;
  (void)otp_read(7);
  OTP_ADDR = 7;
  OTP_WDATA = 0x1;
  otp_command(OTP_PROGRAM);
  check("the key is used up by the next command", OTP_STATUS & OTP_ERROR);
  OTP_STATUS = OTP_DONE | OTP_ERROR;

  OTP_ADDR = 40;
  otp_command(OTP_READ);
  check("an address above 31 reports an error", OTP_STATUS & OTP_ERROR);
  OTP_STATUS = OTP_DONE | OTP_ERROR;

  irq_on(SRC_OTP);
  OTP_IRQ_EN = 1;
  OTP_ADDR = 4;
  OTP_CMD = OTP_READ;
  WAIT_FOR(irq_count != 0);
  irq_off(SRC_OTP);
  OTP_IRQ_EN = 0;
  check("OTP done raises its interrupt", irq_count == 1 && last_id == SRC_OTP);
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Always-on timer
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
static void test_aon_first_boot(void) {
  check("always-on timer starts stopped at zero", AON_CTRL == 0 && AON_COUNT_LO == 0);
  AON_CTRL = 1;
  WAIT_FOR(AON_COUNT_LO > 10);
  check("always-on timer counts", AON_COUNT_LO > 10);

  irq_on(SRC_AON);
  AON_CMP_HI = 0;
  AON_CMP_LO = AON_COUNT_LO + 20;
  check("no match before the compare value", AON_STATUS == 0);
  WAIT_FOR(irq_count != 0);
  irq_off(SRC_AON);
  check("compare match raises its interrupt", irq_count == 1 && last_id == SRC_AON);
  check("writing status clears the match", AON_STATUS == 0);
  AON_CMP_HI = 0xFFFFFFFF;
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Clock gating. A gated peripheral answers with a bus error instead of hanging the bus.
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
static void test_clock_gating(void) {
  check("all peripheral clocks start enabled", SYS_CLK_EN == 0xFFFFFFFF);

  TIMER_CTRL0 = 0;
  TIMER_COUNT0 = 0;
  TIMER_CTRL0 = 1;
  settle();
  SYS_CLK_EN = ~CLK_TIMER;
  BMON_STATUS = 0xFF;
  (void)TIMER_COUNT0;
  __asm__ volatile("fence");
  WAIT_FOR(BMON_STATUS != 0);
  check("reading a gated peripheral reports a bus error", BMON_STATUS != 0);
  BMON_STATUS = 0xFF;
  settle();

  SYS_CLK_EN = 0xFFFFFFFF;
  uint32_t first = TIMER_COUNT0;
  settle();
  check("the timer runs again after its clock returns", TIMER_COUNT0 > first);
  TIMER_CTRL0 = 0;
  check("re-enabled peripherals answer normally", BMON_STATUS == 0);
}

int main(void) {
  adr_test_begin("ADR SoC remaining system blocks test");
  uint32_t boot = SYS_SCRATCH0;
  SYS_SCRATCH0 = boot + 1;

  if (boot == 0) {
    test_pinmux();
    test_adc();
    test_otp();
    test_aon_first_boot();
    test_clock_gating();

    // A system reset must not stop the always-on timer or lose OTP contents.
    SYS_SCRATCH1 = AON_COUNT_LO;
    MB_FAILURES = (uint64_t)adr_test_end();
    MB_REACHED = REACHED_VALUE;
    while (!(UART_REG(UART_LSR) & 0x40)) {}
    SYS_RESET = SOFT_RESET_KEY;
    for (int i = 0; i < 200000; i++) { __asm__ volatile("nop"); }
    check("software reset did not happen", 0);
    return adr_test_end();
  }

  check("first boot reached the reset step", MB_REACHED == REACHED_VALUE);
  check("first boot checks passed", MB_FAILURES == 0);
  check("always-on timer stayed enabled through the reset", AON_CTRL == 1);
  check("always-on timer kept counting through the reset", AON_COUNT_LO > SYS_SCRATCH1);
  check("OTP contents survive a system reset", otp_read(4) == 0x0000FFFF);
  check("clock enables return to all on", SYS_CLK_EN == 0xFFFFFFFF);
  return adr_test_end();
}
