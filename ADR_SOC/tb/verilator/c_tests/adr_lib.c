/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_lib.c
 Module/class Name             : Shared test library
 Author                        : Vijay Bogati
 Description                   : Shared helpers for bare-metal tests
***************************************************************/

#include "adr_lib.h"

#define END_PASS 0x04
#define END_FAIL 0x15

volatile uint64_t trap_cause;
volatile uint64_t trap_count;
static int failures;

static void uart_putc(char c) {
  while (!(UART_REG(UART_LSR) & 0x20)) {}
  UART_REG(UART_THR) = (uint32_t)c;
}

void uart_puts(const char *s) {
  while (*s) uart_putc(*s++);
}

void uart_puthex(uint64_t value) {
  uart_puts("0x");
  for (int shift = 60; shift >= 0; shift -= 4) {
    uart_putc("0123456789abcdef"[(value >> shift) & 0xF]);
  }
}

void check(const char *name, int ok) {
  uart_puts(ok ? "  PASS  " : "  FAIL  ");
  uart_puts(name);
  uart_putc('\n');
  if (!ok) failures++;
}

void adr_test_begin(const char *title) {
  UART_REG(UART_IER) = 0x00;
  UART_REG(UART_LCR) = 0x80;  // divisor latch access
  UART_REG(UART_DLL) = 0x02;  // smallest divisor this UART accepts
  UART_REG(UART_DLM) = 0x00;
  UART_REG(UART_LCR) = 0x03;  // 8N1
  UART_REG(UART_FCR) = 0x07;  // FIFOs on and cleared
  uart_putc('\n');
  uart_puts(title);
  uart_putc('\n');
}

int adr_test_end(void) {
  uart_puts(failures ? "Some checks FAILED\n" : "All checks passed\n");
  return failures;
}

// Called from crt0 when main returns. The testbench ends the run on this character.
void adr_exit(int failed) {
  while (!(UART_REG(UART_LSR) & 0x40)) {}
  uart_putc(failed ? END_FAIL : END_PASS);
  for (;;) {}
}

__attribute__((weak)) void adr_irq(uint64_t cause) {
  uart_puts("  FAIL  unexpected interrupt ");
  uart_puthex(cause);
  uart_putc('\n');
  adr_exit(1);
}

// Returns the address to resume at.
uint64_t adr_trap(uint64_t cause, uint64_t epc) {
  trap_cause = cause;
  trap_count = trap_count + 1;
  if ((int64_t)cause < 0) {
    adr_irq(cause & 0xFFFUL);
    return epc;
  }
  // Exception: skip the faulting instruction, 2 or 4 bytes long.
  uint16_t low_bits = *(volatile uint16_t *)epc;
  return epc + ((low_bits & 3) == 3 ? 4 : 2);
}
