/***************************************************************
 Project name                  : ADR SoC
 File Name                     : i2c.c
 Module/class Name             : main (test 'i2c')
 Author                        : Vijay Bogati
 Description                   : I2C-only test: the I2C part of uart_i2c, to check the I2C block quickly
***************************************************************/

// ADR SoC - I2C-only test: the I2C part of uart_i2c, to check the I2C block quickly.
// Checks reset values, write and read-back of the I2C registers, one transfer to the testbench
// device at address 0x50, the interrupt registers, and that the interrupt reaches the CPU
// through PLIC source 23. Keep it in step with the I2C part of uart_i2c.c.

#include "adr_lib.h"


#define I2C_BASE 0x10007000UL
#define I2C(off) (*(volatile uint32_t *)(I2C_BASE + (off)))
#define I2C_STATUS   0x00
#define I2C_COMMAND  0x04
#define I2C_DATA     0x08
#define I2C_PRESCALE 0x0C
#define I2C_IRQ_ENABLE 0x10
#define I2C_IRQ_STATUS 0x14
#define I2C_IRQ_DONE     (1U << 0)
#define I2C_IRQ_MISS_ACK (1U << 1)
#define I2C_IRQ_RX_READY (1U << 2)
#define I2C_IRQ_OVERFLOW (1U << 3)
#define SRC_I2C 23
#define I2C_BUSY       (1U << 0)
#define I2C_MISS_ACK   (1U << 3)
#define I2C_CMD_EMPTY  (1U << 8)
#define I2C_WR_EMPTY   (1U << 11)
#define I2C_RD_EMPTY   (1U << 14)
#define I2C_CMD_START  (1U << 8)
#define I2C_CMD_READ   (1U << 9)
#define I2C_CMD_WRITE  (1U << 10)
#define I2C_CMD_STOP   (1U << 12)
#define I2C_DATA_VALID (1U << 8)
#define I2C_DATA_LAST  (1U << 9)
#define I2C_DEVICE 0x50
#define I2C_NO_DEVICE 0x60

// Interrupt handler: clears the I2C events, then completes the claim. The I2C source is
// level-triggered, so it must be cleared before completion or it would be taken again.
static volatile uint32_t irq_count;
static volatile uint32_t last_id;
static volatile uint32_t irq_events;

void adr_irq(uint64_t cause) {
  if (cause != IRQ_M_EXT) return;
  uint32_t id = PLIC_CLAIM(CTX_M);
  last_id = id;
  irq_count = irq_count + 1;
  if (id == SRC_I2C) {
    irq_events = *(volatile uint32_t *)(I2C_BASE + I2C_IRQ_STATUS);
    *(volatile uint32_t *)(I2C_BASE + I2C_IRQ_STATUS) = I2C_IRQ_DONE | I2C_IRQ_MISS_ACK;
  }
  PLIC_CLAIM(CTX_M) = id;
}

// Checks a value and, on a mismatch, prints what was read and what was expected.
static void check_value(const char *name, uint32_t got, uint32_t expected) {
  check(name, got == expected);
  if (got != expected) {
    uart_puts("        read ");
    uart_puthex(got);
    uart_puts(" expected ");
    uart_puthex(expected);
    uart_puts("\n");
  }
}


// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// I2C
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
static int i2c_wait_idle(void) {
  WAIT_FOR(!(I2C(I2C_STATUS) & I2C_BUSY));
  return !(I2C(I2C_STATUS) & I2C_BUSY);
}

static void test_i2c(void) {
  // Reset values: idle, all FIFOs empty, prescale at its default of 1.
  check_value("I2C STATUS reset value: idle, FIFOs empty", I2C(I2C_STATUS),
              I2C_CMD_EMPTY | I2C_WR_EMPTY | I2C_RD_EMPTY);
  check_value("I2C PRESCALE reset value is 1", I2C(I2C_PRESCALE), 0x0001);
  check_value("I2C DATA reads 0 when nothing was received", I2C(I2C_DATA), 0);

  // PRESCALE is 16 bits wide: each pattern reads back, and the upper half reads 0.
  static const uint32_t prescale_patterns[] = {0xFFFF, 0xA55A, 0x5AA5, 0x0001, 0x8000};
  int ok = 1;
  for (int i = 0; i < 5; i++) {
    I2C(I2C_PRESCALE) = prescale_patterns[i];
    uint32_t got = I2C(I2C_PRESCALE);
    if (got != prescale_patterns[i]) {
      uart_puts("        wrote ");
      uart_puthex(prescale_patterns[i]);
      uart_puts(" read ");
      uart_puthex(got);
      uart_puts("\n");
      ok = 0;
    }
  }
  check("I2C PRESCALE writes and reads back", ok);
  I2C(I2C_PRESCALE) = 0xFFFFFFFF;
  check_value("I2C PRESCALE upper 16 bits read 0", I2C(I2C_PRESCALE), 0xFFFF);

  // STATUS is read-only apart from write-1-to-clear flags, which are all clear here.
  I2C(I2C_STATUS) = 0xFFFFFFFF;
  check_value("I2C STATUS unchanged by a write", I2C(I2C_STATUS),
              I2C_CMD_EMPTY | I2C_WR_EMPTY | I2C_RD_EMPTY);

  // One write and read-back through the bus, with a fast prescale.
  I2C(I2C_PRESCALE) = 8;
  uint32_t got = 0;
  I2C(I2C_DATA) = 0xC3 | I2C_DATA_LAST;
  I2C(I2C_COMMAND) = I2C_DEVICE | I2C_CMD_START | I2C_CMD_WRITE | I2C_CMD_STOP;
  ok = i2c_wait_idle();
  I2C(I2C_COMMAND) = I2C_DEVICE | I2C_CMD_START | I2C_CMD_READ | I2C_CMD_STOP;
  ok = ok && i2c_wait_idle();
  int valid = 0;
  for (int i = 0; i < 1000 && !valid; i++) {
    uint32_t data = I2C(I2C_DATA);
    if (data & I2C_DATA_VALID) {
      got = data & 0xFF;
      valid = 1;
    }
  }
  check("I2C device at 0x50 returns the byte written", ok && valid && got == 0xC3);
  check("I2C no missed ACK on the transfer", !(I2C(I2C_STATUS) & I2C_MISS_ACK));
  check_value("I2C STATUS back to idle after the transfer", I2C(I2C_STATUS),
              I2C_CMD_EMPTY | I2C_WR_EMPTY | I2C_RD_EMPTY);
  check_value("I2C DATA reads 0 once the byte is taken", I2C(I2C_DATA), 0);
}

// Waits for the I2C interrupt with only the given events enabled, and checks what it saw.
// exact = 1 expects exactly one interrupt. A write to an absent device gives two MISS_ACK
// events, as the unmodified i2c_master still sends the data byte after the address is not
// acknowledged, and each missed ACK raises the interrupt again, so that case uses exact = 0.
static int i2c_irq_after(uint32_t enable, uint32_t device, uint32_t command, int exact) {
  irq_count = 0;
  last_id = 0;
  irq_events = 0;
  I2C(I2C_IRQ_ENABLE) = enable;
  SET_CSR(mie, 1UL << IRQ_M_EXT);
  SET_CSR(mstatus, MSTATUS_MIE);
  if (command & I2C_CMD_WRITE) I2C(I2C_DATA) = 0x3C | I2C_DATA_LAST;
  I2C(I2C_COMMAND) = device | command;
  WAIT_FOR(irq_count != 0);
  i2c_wait_idle();
  CLEAR_CSR(mstatus, MSTATUS_MIE);
  CLEAR_CSR(mie, 1UL << IRQ_M_EXT);
  I2C(I2C_IRQ_ENABLE) = 0;
  int count_ok = exact ? (irq_count == 1) : (irq_count >= 1);
  return count_ok && last_id == SRC_I2C && (irq_events & enable);
}

static void test_i2c_irq(void) {
  // Register access.
  check_value("I2C IRQ_ENABLE reset value is 0", I2C(I2C_IRQ_ENABLE), 0);
  static const uint32_t enable_patterns[] = {0xF, 0x5, 0xA, 0x1, 0x0};
  int ok = 1;
  for (int i = 0; i < 5; i++) {
    I2C(I2C_IRQ_ENABLE) = enable_patterns[i];
    ok &= I2C(I2C_IRQ_ENABLE) == enable_patterns[i];
  }
  check("I2C IRQ_ENABLE writes and reads back", ok);
  I2C(I2C_IRQ_ENABLE) = 0xFFFFFFFF;
  check_value("I2C IRQ_ENABLE upper bits read 0", I2C(I2C_IRQ_ENABLE), 0xF);
  I2C(I2C_IRQ_ENABLE) = 0;

  // The transfer in test_i2c left DONE set. Write 1 clears it; writing 0 does not.
  check_value("I2C IRQ_STATUS shows DONE after a transfer", I2C(I2C_IRQ_STATUS), I2C_IRQ_DONE);
  I2C(I2C_IRQ_STATUS) = 0;
  check_value("I2C IRQ_STATUS DONE kept on a write of 0", I2C(I2C_IRQ_STATUS), I2C_IRQ_DONE);
  I2C(I2C_IRQ_STATUS) = I2C_IRQ_DONE;
  check_value("I2C IRQ_STATUS DONE cleared by a write of 1", I2C(I2C_IRQ_STATUS), 0);

  // RX_READY follows the read queue, and DONE comes with it.
  I2C(I2C_COMMAND) = I2C_DEVICE | I2C_CMD_START | I2C_CMD_READ | I2C_CMD_STOP;
  i2c_wait_idle();
  WAIT_FOR(I2C(I2C_IRQ_STATUS) & I2C_IRQ_RX_READY);
  check_value("I2C IRQ_STATUS shows RX_READY and DONE after a read", I2C(I2C_IRQ_STATUS),
              I2C_IRQ_RX_READY | I2C_IRQ_DONE);
  (void)I2C(I2C_DATA);
  I2C(I2C_IRQ_STATUS) = I2C_IRQ_DONE;
  check_value("I2C IRQ_STATUS clear once the byte is read", I2C(I2C_IRQ_STATUS), 0);

  // No interrupt while all events are disabled.
  irq_count = 0;
  PLIC_PRIORITY(SRC_I2C) = 1;
  PLIC_THRESHOLD(CTX_M) = 0;
  PLIC_ENABLE(CTX_M) = 1U << SRC_I2C;
  // The IRQ_ENABLE checks above enabled DONE while DONE was set, so the line went high and the
  // PLIC holds source 23 pending, even though it was not enabled then. Claim and complete it
  // before enabling interrupts. The line is low now, as IRQ_ENABLE is 0.
  for (int i = 0; i < 4; i++) {
    uint32_t stale = PLIC_CLAIM(CTX_M);
    if (stale == 0) break;
    PLIC_CLAIM(CTX_M) = stale;
  }
  SET_CSR(mie, 1UL << IRQ_M_EXT);
  SET_CSR(mstatus, MSTATUS_MIE);
  I2C(I2C_DATA) = 0x11 | I2C_DATA_LAST;
  I2C(I2C_COMMAND) = I2C_DEVICE | I2C_CMD_START | I2C_CMD_WRITE | I2C_CMD_STOP;
  i2c_wait_idle();
  for (int i = 0; i < 2000; i++) { __asm__ volatile("nop"); }
  CLEAR_CSR(mstatus, MSTATUS_MIE);
  CLEAR_CSR(mie, 1UL << IRQ_M_EXT);
  check("I2C no interrupt while IRQ_ENABLE is 0", irq_count == 0);
  I2C(I2C_IRQ_STATUS) = I2C_IRQ_DONE;

  // Each enabled event reaches the CPU on PLIC source 23.
  check("I2C DONE interrupt reaches the CPU on source 23",
        i2c_irq_after(I2C_IRQ_DONE, I2C_DEVICE,
                      I2C_CMD_START | I2C_CMD_WRITE | I2C_CMD_STOP, 1));
  check("I2C MISS_ACK interrupt reaches the CPU on source 23",
        i2c_irq_after(I2C_IRQ_MISS_ACK, I2C_NO_DEVICE,
                      I2C_CMD_START | I2C_CMD_WRITE | I2C_CMD_STOP, 0));
  check("I2C STATUS miss_ack cleared through IRQ_STATUS", !(I2C(I2C_STATUS) & I2C_MISS_ACK));
  I2C(I2C_IRQ_STATUS) = I2C_IRQ_DONE;
  check_value("I2C IRQ_STATUS clear at the end", I2C(I2C_IRQ_STATUS), 0);
  PLIC_ENABLE(CTX_M) = 0;
  PLIC_PRIORITY(SRC_I2C) = 0;
}

int main(void) {
  adr_test_begin("ADR SoC I2C test");
  test_i2c();
  test_i2c_irq();
  return adr_test_end();
}
