/***************************************************************
 Project name                  : ADR SoC
 File Name                     : smoke.c
 Module/class Name             : main (test 'smoke')
 Author                        : Vijay Bogati
 Description                   : First bring-up test: CPU, SRAM, atomics, FPU, CSRs, fabric errors, PMP, UART
***************************************************************/

#include "adr_lib.h"

static void test_integer(void) {
  volatile uint64_t a = 0x123456789ULL, b = 0x1000ULL;
  check("64-bit multiply", a * b == 0x123456789000ULL);
  check("64-bit divide", (a * b) / b == a);
  check("remainder", (a % 0x10000ULL) == 0x6789ULL);
}

static volatile uint8_t mem_area[64];

static void test_memory(void) {
  for (int i = 0; i < 64; i++) mem_area[i] = (uint8_t)(i * 3 + 1);
  int ok = 1;
  for (int i = 0; i < 64; i++) ok &= mem_area[i] == (uint8_t)(i * 3 + 1);
  check("byte write/read", ok);

  volatile uint64_t *d = (volatile uint64_t *)mem_area;
  d[0] = 0x1122334455667788ULL;
  check("byte lanes", mem_area[0] == 0x88 && mem_area[7] == 0x11);
  volatile uint16_t *h = (volatile uint16_t *)&mem_area[2];
  *h = 0xBEEF;
  check("halfword merge", d[0] == 0x11223344BEEF7788ULL);

  // A location far from this image: forces cache-line refills over the fabric.
  volatile uint64_t *far = (volatile uint64_t *)0x80070000UL;
  for (int i = 0; i < 8192; i += 8) far[i] = 0xA5A5000000000000ULL + (uint64_t)i;
  ok = 1;
  for (int i = 0; i < 8192; i += 8) ok &= far[i] == 0xA5A5000000000000ULL + (uint64_t)i;
  check("cache refill across 64 KiB", ok);
}

static volatile uint64_t amo_d;
static volatile uint32_t amo_w;

static void test_atomics(void) {
  uint64_t old;
  amo_d = 40;
  __asm__ volatile("amoadd.d %0, %2, %1" : "=r"(old), "+A"(amo_d) : "r"(2UL));
  check("amoadd.d", old == 40 && amo_d == 42);

  uint32_t oldw;
  amo_w = 7;
  __asm__ volatile("amoswap.w %0, %2, %1" : "=r"(oldw), "+A"(amo_w) : "r"(9U));
  check("amoswap.w", oldw == 7 && amo_w == 9);

  uint64_t val, fail;
  amo_d = 100;
  __asm__ volatile(
      "1: lr.d %0, %2\n"
      "   addi %0, %0, 1\n"
      "   sc.d %1, %0, %2\n"
      "   bnez %1, 1b\n"
      : "=&r"(val), "=&r"(fail), "+A"(amo_d));
  check("lr.d/sc.d", amo_d == 101 && fail == 0);
}

static void test_float(void) {
  volatile double x = 1.5, y = 2.25;
  check("double multiply", (x * y) == 3.375);
  volatile float f = 7.0f;
  check("float divide", (f / 2.0f) == 3.5f);
  check("float to int", (int)(x * 4.0) == 6);
}

static void test_csrs(void) {
  uint64_t misa;
  __asm__ volatile("csrr %0, misa" : "=r"(misa));
  const uint64_t want = (1UL << 63) | (1UL << ('I' - 'A')) | (1UL << ('M' - 'A')) |
                        (1UL << ('A' - 'A')) | (1UL << ('F' - 'A')) | (1UL << ('D' - 'A')) |
                        (1UL << ('C' - 'A')) | (1UL << ('S' - 'A')) | (1UL << ('U' - 'A'));
  check("misa reports RV64IMAFDC, S and U", (misa & want) == want);
}

// The CPU does not raise an exception on an AXI error response: its write-through
// cache path ignores the response code, so faults come only from PMP/PMA checks.
// A bad access therefore completes with the error target's fixed read data.
static void test_bus_errors(void) {
  const uint64_t error_target_data = 0xCA11AB1EBADCAB1EULL;
  const uint32_t empty_slot_data = 0xDEA110C8U;

  uint64_t unmapped = *(volatile uint64_t *)0x40000000UL;
  check("unmapped load gets error-target data, no hang", unmapped == error_target_data);

  uint32_t empty = *(volatile uint32_t *)(UART0_BASE + 0x80000UL);
  check("empty peripheral slot gets error data, no hang", empty == empty_slot_data);
}

// A locked PMP entry applies in machine mode too, so it stays set until reset.
static void test_pmp_fault(void) {
  const uint64_t load_access_fault = 5;
  const uint64_t region = 0x40000000UL;

  __asm__ volatile("csrw pmpaddr0, %0" : : "r"((region >> 2) | 0x1FFUL));
  __asm__ volatile("csrw pmpcfg0, %0" : : "r"(0x98UL));  // locked, NAPOT 4 KiB, no access
  trap_count = 0;
  (void)*(volatile uint64_t *)region;
  check("PMP-protected load traps with access fault",
        trap_count == 1 && trap_cause == load_access_fault);
}

// With the CPU's coprocessor port enabled but unconnected, this instruction hangs the CPU
// instead of trapping, and the run ends in a timeout.
static void test_illegal_instruction(void) {
  const uint64_t illegal_instruction = 2;

  trap_count = 0;
  __asm__ volatile(".word 0xFFFFFFFF");
  check("illegal instruction traps",
        trap_count == 1 && trap_cause == illegal_instruction);
}

int main(void) {
  adr_test_begin("ADR SoC smoke test");
  test_integer();
  test_memory();
  test_atomics();
  test_float();
  test_csrs();
  test_bus_errors();
  test_illegal_instruction();
  test_pmp_fault();
  return adr_test_end();
}
