/***************************************************************
 Project name                  : ADR SoC
 File Name                     : debug.c
 Module/class Name             : main (test 'debug')
 Author                        : Vijay Bogati
 Description                   : Debug test, run with the JTAG debugger in the testbench (+jtag_test)
***************************************************************/

// First boot: publish values in memory, then spin until the debugger halts the CPU,
// changes registers and resumes. Then check that the debugger's changes arrived.
// The debugger then resets the SoC. Second boot: confirm the reset and end the test.
//
// Memory is used as the mailbox because system bus access reaches SRAM directly.
// Each address is used by one side at a time, in cache lines the program has not read.

#include "adr_lib.h"

#define MB(offset)    (*(volatile uint64_t *)(0x80070000UL + (offset)))
#define MB_READY      MB(0x000)
#define MB_SPIN       MB(0x008)
#define MB_SBA_TARGET MB(0x100)
#define MB_DONE       MB(0x200)
#define MB_BOOT_COUNT MB(0x300)
#define MB_FAILURES   MB(0x308)

#define READY_VALUE  0x52454144UL
#define DONE_VALUE   0x444F4E45UL
#define SBA_PATTERN  0xDEADBEEF12345678UL
#define RESUME_VALUE 0x5A5AUL

extern char adr_spin[];

// s11 holds a value for the debugger to read. s10 and s9 are set by the debugger.
__attribute__((noinline)) static void wait_for_debugger(uint64_t *s10_out, uint64_t *s9_out) {
  register uint64_t s9_reg __asm__("s9");
  register uint64_t s10_reg __asm__("s10");
  __asm__ volatile(
      "li   s11, 0x1122334455667788\n"
      "li   s10, 0\n"
      "li   s9, 0\n"
      ".globl adr_spin\n"
      "adr_spin:\n"
      "beqz s10, adr_spin\n"
      : "=r"(s10_reg), "=r"(s9_reg)
      :
      : "s11");
  *s10_out = s10_reg;
  *s9_out = s9_reg;
}

static void first_boot(void) {
  uint64_t s10_value, s9_value;

  MB_SPIN = (uint64_t)adr_spin;
  MB_READY = READY_VALUE;
  wait_for_debugger(&s10_value, &s9_value);

  check("debugger's register write released the program", s10_value == RESUME_VALUE);
  check("program buffer result is visible after resume", s9_value == 42);
  check("system bus write reached SRAM", MB_SBA_TARGET == SBA_PATTERN);

  int failed = adr_test_end();
  MB_FAILURES = (uint64_t)failed;
  while (!(UART_REG(UART_LSR) & 0x40)) {}  // let the text finish before the reset
  MB_DONE = DONE_VALUE;
  for (;;) {}
}

int main(void) {
  adr_test_begin("ADR SoC debug test");
  uint64_t boot = MB_BOOT_COUNT;
  MB_BOOT_COUNT = boot + 1;
  if (boot == 0) first_boot();

  check("debug reset restarted the program from the boot ROM", boot == 1);
  check("first boot checks passed", MB_FAILURES == 0);
  check("reset cause reports the debug module",
        *(volatile uint32_t *)0x1000D008UL & 2U);
  return adr_test_end();
}
