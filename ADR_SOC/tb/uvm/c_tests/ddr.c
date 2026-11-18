/***************************************************************
 Project name                  : ADR SoC
 File Name                     : ddr.c
 Module/class Name             : main (test 'ddr')
 Author                        : Vijay Bogati
 Description                   : DDR4 test: CPU, DMA and instruction fetch against LiteDRAM's memory model
***************************************************************/

// ADR SoC - DDR4 test, against LiteDRAM's memory model. The CPU, DMA and instruction fetch all
// reach it, cached and through the uncached alias.

#include "adr_lib.h"

#define DDR_BASE 0x90000000UL
#define DDR_SIZE 0x02000000UL
#define SRAM_AREA 0x80040000UL

#define DMA_BASE 0x1000E000UL
#define DMA_REG(off) (*(volatile uint32_t *)(DMA_BASE + (off)))
#define DMA_SRC_LO 0x00
#define DMA_SRC_HI 0x04
#define DMA_DST_LO 0x08
#define DMA_DST_HI 0x0C
#define DMA_LEN    0x10
#define DMA_CTRL   0x14
#define DMA_STATUS 0x18
#define STATUS_DONE  2U
#define STATUS_ERROR 4U

#define DDR_CTRL(off) (*(volatile uint32_t *)(0x10020000UL + (off)))
#define DDR_DFII_CONTROL 0x1000

static volatile uint64_t *cached(uint64_t offset) {
  return (volatile uint64_t *)(DDR_BASE + offset);
}
static volatile uint64_t *uncached(uint64_t offset) {
  return (volatile uint64_t *)UNCACHED(DDR_BASE + offset);
}

static void test_control(void) {
  check("the controller starts under hardware control", (DDR_CTRL(DDR_DFII_CONTROL) & 1U) == 1U);
}

static void test_access(void) {
  *uncached(0) = 0x1122334455667788UL;
  check("uncached word reads back", *uncached(0) == 0x1122334455667788UL);

  volatile uint8_t *bytes = (volatile uint8_t *)uncached(0);
  check("byte lanes", bytes[0] == 0x88 && bytes[7] == 0x11);
  bytes[3] = 0xAB;
  check("a byte write changes one byte", *uncached(0) == 0x11223344AB667788UL);

  *cached(0x100) = 0xCAFE0000DEAD0001UL;
  check("a cached write reaches memory", *uncached(0x100) == 0xCAFE0000DEAD0001UL);

  *uncached(DDR_SIZE - 8) = 0x5A5A5A5AA5A5A5A5UL;
  check("the last word works", *uncached(DDR_SIZE - 8) == 0x5A5A5A5AA5A5A5A5UL);
  check("addresses don't wrap", *uncached(0) == 0x11223344AB667788UL);

  uint64_t beyond = *(volatile uint64_t *)(DDR_BASE + DDR_SIZE);
  check("just past the end gets error data", beyond == 0xCA11AB1EBADCAB1EULL);
}

// Rows and banks: writes across a wide range, read back after all have been written.
static void test_spread(void) {
  for (uint64_t off = 0; off < DDR_SIZE; off += 0x20040) {
    *uncached(off) = 0xA000000000000000UL + off;
  }
  int ok = 1;
  for (uint64_t off = 0; off < DDR_SIZE; off += 0x20040) {
    ok &= *uncached(off) == 0xA000000000000000UL + off;
  }
  check("writes across banks and rows read back", ok);
}

static void test_cache_refill(void) {
  for (uint64_t i = 0; i < 8192; i += 8) *cached(0x10000 + i * 8) = 0xB000000000000000UL + i;
  int ok = 1;
  for (uint64_t i = 0; i < 8192; i += 8) ok &= *cached(0x10000 + i * 8) == 0xB000000000000000UL + i;
  check("cache refills over 64 KiB", ok);
}

static int dma_copy(uint64_t src, uint64_t dst, uint32_t len) {
  DMA_REG(DMA_SRC_LO) = (uint32_t)src;
  DMA_REG(DMA_SRC_HI) = (uint32_t)(src >> 32);
  DMA_REG(DMA_DST_LO) = (uint32_t)dst;
  DMA_REG(DMA_DST_HI) = (uint32_t)(dst >> 32);
  DMA_REG(DMA_LEN) = len;
  DMA_REG(DMA_CTRL) = 1;
  WAIT_FOR(DMA_REG(DMA_STATUS) & STATUS_DONE);
  uint32_t status = DMA_REG(DMA_STATUS);
  DMA_REG(DMA_STATUS) = STATUS_DONE | STATUS_ERROR;
  return (status & STATUS_DONE) && !(status & STATUS_ERROR);
}

static void test_dma(void) {
  volatile uint64_t *sram = (volatile uint64_t *)SRAM_AREA;
  for (uint64_t i = 0; i < 512; i++) sram[i] = 0xC000000000000000UL + i;

  int ok = dma_copy(SRAM_AREA, DDR_BASE + 0x40000, 4096);
  for (uint64_t i = 0; i < 512; i++) ok &= *uncached(0x40000 + i * 8) == 0xC000000000000000UL + i;
  check("DMA copies from SRAM to DDR", ok);

  ok = dma_copy(DDR_BASE + 0x40000, DDR_BASE + 0x50003, 1000);
  volatile uint8_t *from = (volatile uint8_t *)uncached(0x40000);
  volatile uint8_t *to = (volatile uint8_t *)uncached(0x50003);
  for (uint32_t i = 0; i < 1000; i++) ok &= from[i] == to[i];
  check("DMA copies within DDR, unaligned", ok);

  // A cached line goes stale here just as it does in SRAM, and the same two remedies work.
  *cached(0x60000) = 1;
  int loaded = *cached(0x60000) == 1;
  *uncached(0x61000) = 2;
  ok = dma_copy(UNCACHED(DDR_BASE) + 0x61000, DDR_BASE + 0x60000, 8);
  check("a cached read goes stale after DMA writes", ok && loaded && *cached(0x60000) == 1);
  check("the uncached alias sees the DMA data", *uncached(0x60000) == 2);
  dcache_invalidate();
  check("invalidating the cache shows the DMA data", *cached(0x60000) == 2);
}

static void test_atomics(void) {
  volatile uint64_t *target = cached(0x70000);
  uint64_t old;
  *target = 40;
  __asm__ volatile("amoadd.d %0, %2, %1" : "=r"(old), "+A"(*target) : "r"(2UL));
  check("amoadd.d", old == 40 && *uncached(0x70000) == 42);

  uint64_t val, fail;
  __asm__ volatile(
      "1: lr.d %0, %2\n"
      "   addi %0, %0, 1\n"
      "   sc.d %1, %0, %2\n"
      "   bnez %1, 1b\n"
      : "=&r"(val), "=&r"(fail), "+A"(*target));
  check("lr.d/sc.d", *uncached(0x70000) == 43 && fail == 0);
}

// addi a0, a0, 1; ret
static void test_execute(void) {
  volatile uint32_t *code = (volatile uint32_t *)(DDR_BASE + 0x80000);
  code[0] = 0x00150513U;
  code[1] = 0x00008067U;
  __asm__ volatile("fence.i");
  uint64_t (*function)(uint64_t) = (uint64_t (*)(uint64_t))(DDR_BASE + 0x80000);
  check("code runs from DDR", function(41) == 42);
}

int main(void) {
  adr_test_begin("ADR SoC DDR4 test");
  test_control();
  test_access();
  test_spread();
  test_cache_refill();
  test_dma();
  test_atomics();
  test_execute();
  return adr_test_end();
}
