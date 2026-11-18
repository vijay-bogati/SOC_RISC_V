/***************************************************************
 Project name                  : ADR SoC
 File Name                     : amo.c
 Module/class Name             : main (test 'amo')
 Author                        : Vijay Bogati
 Description                   : Atomics outside SRAM and DDR4: error response, no write, no hang (NEG-06..NEG-10)
***************************************************************/

// ADR SoC - atomics to targets that don't support them (ADR_TEST_PLAN NEG-06 to NEG-10).
// Only SRAM and DDR4 carry out an AXI atomic. Every other target has an ATOP filter in front,
// which answers with SLVERR on B and on the R beat and never passes the write on. The CPU's
// write-through cache sends every RISC-V AMO as AtomicLoad or AtomicSwap (both have an R beat;
// it never sends AtomicStore), takes the R data, which the filter sets to 0, as the old value,
// and does not trap on the error. Each AMO is followed by a plain load from the same target and
// a report line, so a hang shows which access stopped.

#include "adr_lib.h"

#define BMON_BASE    0x1000C000UL
#define BMON(off)    (*(volatile uint32_t *)(BMON_BASE + (off)))
#define BMON_STATUS  BMON(0x00)
#define BMON_ADDR_LO BMON(0x04)
#define BMON_ADDR_HI BMON(0x08)
#define READ_ERROR_CPU  (1U << 0)
#define WRITE_ERROR_CPU (1U << 4)

#define SYS_SCRATCH1_ADDR   0x1000D014UL  // APB slot (system control), read/write
#define PLIC_PRIO1_ADDR     0x0C000004UL  // PLIC source 1 priority, read/write
#define ROM_ADDR            0x00010000UL  // first word of the boot ROM
#define CLINT_MTIMECMP_ADDR 0x02004000UL  // CLINT MTIMECMP, 64 bits
#define DEBUG_DATA0_ADDR    0x00000380UL  // debug memory: abstract data 0 (held at 0 while dmactive = 0)

enum { OP_SWAP = 0, OP_ADD = 1, OP_OR = 2, NUM_OPS = 3 };
static const char *const op_name[NUM_OPS] = {"amoswap", "amoadd", "amoor"};

// Operands chosen so that any write reaching the target changes it.
#define OPERAND 0x5A5A5A5AUL

static uint64_t amo_w(int op, uint64_t addr) {
  uint32_t old = 0xDEADBEEFU;
  volatile uint32_t *p = (volatile uint32_t *)addr;
  uint32_t v = (uint32_t)OPERAND;
  switch (op) {
    case OP_SWAP: __asm__ volatile("amoswap.w %0, %2, %1" : "=r"(old), "+A"(*p) : "r"(v) : "memory"); break;
    case OP_ADD:  __asm__ volatile("amoadd.w %0, %2, %1"  : "=r"(old), "+A"(*p) : "r"(v) : "memory"); break;
    default:      __asm__ volatile("amoor.w %0, %2, %1"   : "=r"(old), "+A"(*p) : "r"(v) : "memory"); break;
  }
  __asm__ volatile("fence");
  return old;
}

static uint64_t amo_d(int op, uint64_t addr) {
  uint64_t old = 0xDEADBEEFDEADBEEFULL;
  volatile uint64_t *p = (volatile uint64_t *)addr;
  uint64_t v = 0x5A5A5A5A5A5A5A5AULL;
  switch (op) {
    case OP_SWAP: __asm__ volatile("amoswap.d %0, %2, %1" : "=r"(old), "+A"(*p) : "r"(v) : "memory"); break;
    case OP_ADD:  __asm__ volatile("amoadd.d %0, %2, %1"  : "=r"(old), "+A"(*p) : "r"(v) : "memory"); break;
    default:      __asm__ volatile("amoor.d %0, %2, %1"   : "=r"(old), "+A"(*p) : "r"(v) : "memory"); break;
  }
  __asm__ volatile("fence");
  return old;
}

static uint64_t load(uint64_t addr, int wide) {
  return wide ? *(volatile uint64_t *)addr : *(volatile uint32_t *)addr;
}

// The check name is "<target>: [<op> ]<what>", built here as the library has no string functions.
static char name_buf[128];

static char *append(char *d, const char *s) {
  while (*s && d < name_buf + sizeof(name_buf) - 1) *d++ = *s++;
  return d;
}

static void report(const char *target, const char *op, const char *what, int ok) {
  char *d = append(name_buf, target);
  d = append(d, ": ");
  if (op) { d = append(d, op); d = append(d, " "); }
  d = append(d, what);
  *d = '\0';
  check(name_buf, ok);
}

// One target: set (or read) a known value, then each AMO in turn. Every AMO must return 0, leave
// the target unchanged and let the following load complete. The bus error monitor must record
// the error at this target's address.
static void amo_target(const char *target, uint64_t addr, int wide, int writable, uint64_t value) {
  if (writable) {
    if (wide) *(volatile uint64_t *)addr = value;
    else      *(volatile uint32_t *)addr = (uint32_t)value;
    __asm__ volatile("fence");
  }
  uint64_t expect = load(addr, wide);
  report(target, 0, "known value in place", !writable || expect == value);

  BMON_STATUS = 0xFF;
  __asm__ volatile("fence");
  for (int op = 0; op < NUM_OPS; op++) {
    uint64_t old = wide ? amo_d(op, addr) : amo_w(op, addr);
    uint64_t now = load(addr, wide);  // reaching here means no hang
    report(target, op_name[op], "returns 0 (error R beat)", old == 0);
    report(target, op_name[op], "leaves the target unchanged", now == expect);
  }

  uint32_t status = BMON_STATUS;
  report(target, 0, "bus monitor: CPU write error recorded", (status & WRITE_ERROR_CPU) != 0);
  report(target, 0, "bus monitor: CPU read error recorded (R beat)", (status & READ_ERROR_CPU) != 0);
  report(target, 0, "bus monitor: no other initiator's error", (status & ~(READ_ERROR_CPU | WRITE_ERROR_CPU)) == 0);
  report(target, 0, "bus monitor: address of the first AMO recorded",
         BMON_ADDR_LO == (uint32_t)addr && BMON_ADDR_HI == (uint32_t)(addr >> 32));
  if (BMON_ADDR_LO != (uint32_t)addr) {
    uart_puts("        recorded address 0x");
    uart_puthex(((uint64_t)BMON_ADDR_HI << 32) | BMON_ADDR_LO);
    uart_puts("\n");
  }
  BMON_STATUS = 0xFF;
}

int main(void) {
  adr_test_begin("ADR SoC atomics outside SRAM and DDR4 (NEG-06..NEG-10)");
  amo_target("NEG-06 APB system control SCRATCH1", SYS_SCRATCH1_ADDR,   0, 1, 0x13572468UL);
  amo_target("NEG-07 PLIC source 1 priority",      PLIC_PRIO1_ADDR,     0, 1, 5);
  amo_target("NEG-08 boot ROM",                    ROM_ADDR,            0, 0, 0);
  amo_target("NEG-09 CLINT MTIMECMP",              CLINT_MTIMECMP_ADDR, 1, 1, 0x7FFFFFFFFFFF0000ULL);
  // With no debugger attached, dmcontrol.dmactive is 0, and the debug module holds its registers in
  // reset (RISC-V Debug 0.13; dm_csrs clears data_q every clock), so a hart write to abstract data 0
  // does not stick and the register reads 0. Check that, then run the AMOs against the value 0.
  *(volatile uint32_t *)DEBUG_DATA0_ADDR = 0x2468ACE0U;
  __asm__ volatile("fence");
  check("NEG-10 debug memory data 0: held at 0 while the debug module is inactive",
        *(volatile uint32_t *)DEBUG_DATA0_ADDR == 0);
  amo_target("NEG-10 debug memory data 0",         DEBUG_DATA0_ADDR,    0, 0, 0);

  // Atomics still work where they are supported: the CPU is not left in a bad state.
  static volatile uint32_t sram_word = 7;
  uint32_t old;
  __asm__ volatile("amoadd.w %0, %2, %1" : "=r"(old), "+A"(sram_word) : "r"(3U) : "memory");
  check("SRAM amoadd.w still works after the errors", old == 7 && sram_word == 10);
  return adr_test_end();
}
