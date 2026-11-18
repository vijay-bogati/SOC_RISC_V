/***************************************************************
 Project name                  : ADR SoC
 File Name                     : dma.c
 Module/class Name             : main (test 'dma')
 Author                        : Vijay Bogati
 Description                   : DMA test. The engine copies within SRAM
***************************************************************/

// The CPU's data cache does not see DMA writes, so every destination is an address this
// program has not read before and each is read only after its copy has finished.
// test_coherency() reads a cached buffer on purpose, to show how software deals with this.

#include "adr_lib.h"

#define DMA_BASE 0x1000E000UL
#define DMA_REG(base, ch, off) (*(volatile uint32_t *)((base) + 0x20 * (ch) + (off)))
#define DMA_SRC_LO 0x00
#define DMA_SRC_HI 0x04
#define DMA_DST_LO 0x08
#define DMA_DST_HI 0x0C
#define DMA_LEN    0x10
#define DMA_CTRL   0x14
#define DMA_STATUS 0x18
#define CTRL_START  1U
#define CTRL_IRQ_EN 2U
#define STATUS_BUSY  1U
#define STATUS_DONE  2U
#define STATUS_ERROR 4U

#define BMON_STATUS (*(volatile uint32_t *)0x1000C000UL)
#define BMON_ADDR_LO (*(volatile uint32_t *)0x1000C004UL)
#define READ_ERROR_DMA  (1U << 2)
#define WRITE_ERROR_DMA (1U << 6)
#define UNMAPPED_ADDR 0x40000000UL

#define SRC_DMA 22

#define SRC_AREA 0x80040000UL
// Each use takes a fresh destination, so nothing it reads can already be in the cache.
static uint64_t next_dst = 0x80050000UL;

static volatile uint32_t irq_count;
static volatile uint32_t last_id;
static uint64_t irq_base;
static uint32_t irq_channel;

void adr_irq(uint64_t cause) {
  if (cause != IRQ_M_EXT) return;
  uint32_t id = PLIC_CLAIM(CTX_M);
  last_id = id;
  irq_count = irq_count + 1;
  DMA_REG(irq_base, irq_channel, DMA_STATUS) = STATUS_DONE | STATUS_ERROR;
  PLIC_CLAIM(CTX_M) = id;
}

static uint64_t fresh_dst(uint32_t size) {
  uint64_t dst = next_dst;
  next_dst = (next_dst + size + 0x3F) & ~0x3FUL;
  return dst;
}

static void fill_source(uint32_t seed) {
  volatile uint8_t *src = (volatile uint8_t *)SRC_AREA;
  for (uint32_t i = 0; i < 2048; i++) src[i] = (uint8_t)(i * 7 + seed);
}

static void dma_setup(uint64_t base, uint32_t ch, uint64_t src, uint64_t dst, uint32_t len) {
  DMA_REG(base, ch, DMA_SRC_LO) = (uint32_t)src;
  DMA_REG(base, ch, DMA_SRC_HI) = (uint32_t)(src >> 32);
  DMA_REG(base, ch, DMA_DST_LO) = (uint32_t)dst;
  DMA_REG(base, ch, DMA_DST_HI) = (uint32_t)(dst >> 32);
  DMA_REG(base, ch, DMA_LEN) = len;
}

static int dma_wait(uint64_t base, uint32_t ch) {
  WAIT_FOR(DMA_REG(base, ch, DMA_STATUS) & STATUS_DONE);
  return DMA_REG(base, ch, DMA_STATUS) & STATUS_DONE;
}

static int same_bytes(uint64_t a, uint64_t b, uint32_t len) {
  volatile uint8_t *pa = (volatile uint8_t *)a, *pb = (volatile uint8_t *)b;
  for (uint32_t i = 0; i < len; i++) {
    if (pa[i] != pb[i]) return 0;
  }
  return 1;
}

static int copy_ok(uint64_t base, uint32_t ch, uint32_t src_off, uint32_t dst_off, uint32_t len) {
  uint64_t dst = fresh_dst(len + 16) + dst_off;
  uint64_t src = SRC_AREA + src_off;
  dma_setup(base, ch, src, dst, len);
  DMA_REG(base, ch, DMA_CTRL) = CTRL_START;
  if (!dma_wait(base, ch)) return 0;
  uint32_t status = DMA_REG(base, ch, DMA_STATUS);
  DMA_REG(base, ch, DMA_STATUS) = STATUS_DONE | STATUS_ERROR;
  if (status & (STATUS_ERROR | STATUS_BUSY)) return 0;
  return same_bytes(src, dst, len);
}

static void test_copies(void) {
  fill_source(0x11);
  check("DMA copies 256 aligned bytes", copy_ok(DMA_BASE, 0, 0, 0, 256));
  check("DMA copies one byte", copy_ok(DMA_BASE, 0, 16, 0, 1));
  check("DMA copies from an unaligned source", copy_ok(DMA_BASE, 0, 3, 0, 100));
  check("DMA copies to an unaligned destination", copy_ok(DMA_BASE, 0, 0, 5, 100));
  check("DMA copies with both unaligned", copy_ok(DMA_BASE, 0, 7, 2, 301));
  check("DMA copy longer than one burst", copy_ok(DMA_BASE, 0, 0, 0, 2048));
  // With different alignments, a burst can read one beat more than it writes, and one write
  // burst can need two read bursts. Over a long copy, neither must stop the engine.
  check("DMA long copy, source offset larger", copy_ok(DMA_BASE, 0, 3, 0, 2000));
  check("DMA long copy, destination offset larger", copy_ok(DMA_BASE, 0, 0, 5, 2000));

  // The copy must stop exactly at its length.
  uint64_t dst = fresh_dst(64);
  volatile uint8_t *guard = (volatile uint8_t *)dst;
  guard[10] = 0x5C;  // written through to memory, not allocated in the cache
  dma_setup(DMA_BASE, 1, SRC_AREA, dst, 10);
  DMA_REG(DMA_BASE, 1, DMA_CTRL) = CTRL_START;
  int done = dma_wait(DMA_BASE, 1);
  DMA_REG(DMA_BASE, 1, DMA_STATUS) = STATUS_DONE;
  check("the byte after the length is untouched", done && guard[10] == 0x5C);

  // A zero length finishes at once and touches nothing.
  dma_setup(DMA_BASE, 2, SRC_AREA, fresh_dst(16), 0);
  DMA_REG(DMA_BASE, 2, DMA_CTRL) = CTRL_START;
  check("a zero length finishes without a transfer", DMA_REG(DMA_BASE, 2, DMA_STATUS) == STATUS_DONE);
  DMA_REG(DMA_BASE, 2, DMA_STATUS) = STATUS_DONE;
}

static void test_channels(void) {
  fill_source(0x22);
  uint64_t dst[4];
  for (uint32_t ch = 0; ch < 4; ch++) {
    dst[ch] = fresh_dst(512);
    dma_setup(DMA_BASE, ch, SRC_AREA + 32 * ch, dst[ch], 400 + 8 * ch);
  }
  // Start them all together, so the channels compete.
  for (uint32_t ch = 0; ch < 4; ch++) DMA_REG(DMA_BASE, ch, DMA_CTRL) = CTRL_START;
  int busy_seen = (DMA_REG(DMA_BASE, 3, DMA_STATUS) & STATUS_BUSY) != 0;

  int ok = 1;
  for (uint32_t ch = 0; ch < 4; ch++) {
    ok &= dma_wait(DMA_BASE, ch) != 0;
    ok &= !(DMA_REG(DMA_BASE, ch, DMA_STATUS) & STATUS_ERROR);
    DMA_REG(DMA_BASE, ch, DMA_STATUS) = STATUS_DONE;
    ok &= same_bytes(SRC_AREA + 32 * ch, dst[ch], 400 + 8 * ch);
  }
  check("a waiting channel reports busy", busy_seen);
  check("all 4 channels finish with correct data", ok);
}

// A cached line goes stale when DMA writes to it. Both ways of seeing the new data must work.
static void test_coherency(void) {
  const uint64_t old_value = 0x1111111111111111UL, new_value = 0x2222222222222222UL;
  *(volatile uint64_t *)SRC_AREA = new_value;
  uint64_t dst = fresh_dst(64);
  volatile uint64_t *cached = (volatile uint64_t *)dst;
  volatile uint64_t *uncached = (volatile uint64_t *)UNCACHED(dst);
  *cached = old_value;
  int loaded = *cached == old_value;  // this read puts the line in the cache

  dma_setup(DMA_BASE, 0, SRC_AREA, dst, 8);
  DMA_REG(DMA_BASE, 0, DMA_CTRL) = CTRL_START;
  int done = dma_wait(DMA_BASE, 0);
  DMA_REG(DMA_BASE, 0, DMA_STATUS) = STATUS_DONE;

  check("a cached read goes stale after DMA writes", done && loaded && *cached == old_value);
  check("the uncached alias sees the DMA data", *uncached == new_value);
  dcache_invalidate();
  check("invalidating the cache shows the DMA data", *cached == new_value);
}

static void test_cpu_runs_during_dma(void) {
  fill_source(0x33);
  uint64_t dst = fresh_dst(2048);
  dma_setup(DMA_BASE, 0, SRC_AREA, dst, 2048);
  DMA_REG(DMA_BASE, 0, DMA_CTRL) = CTRL_START;
  volatile uint64_t counter = 0;
  while (DMA_REG(DMA_BASE, 0, DMA_STATUS) & STATUS_BUSY) counter = counter + 1;
  DMA_REG(DMA_BASE, 0, DMA_STATUS) = STATUS_DONE;
  check("the CPU keeps running during a copy", counter > 0);
  check("the copy is still correct", same_bytes(SRC_AREA, dst, 2048));
}

static void test_errors(void) {
  BMON_STATUS = 0xFF;
  dma_setup(DMA_BASE, 0, UNMAPPED_ADDR, fresh_dst(64), 32);
  DMA_REG(DMA_BASE, 0, DMA_CTRL) = CTRL_START;
  int done = dma_wait(DMA_BASE, 0);
  check("a bad source finishes and reports an error",
        done && (DMA_REG(DMA_BASE, 0, DMA_STATUS) & STATUS_ERROR));
  check("the bus monitor records the DMA read error", (BMON_STATUS & READ_ERROR_DMA) != 0);
  check("the bus monitor records the DMA address", BMON_ADDR_LO == (uint32_t)UNMAPPED_ADDR);
  DMA_REG(DMA_BASE, 0, DMA_STATUS) = STATUS_DONE | STATUS_ERROR;
  check("status clears", DMA_REG(DMA_BASE, 0, DMA_STATUS) == 0);

  BMON_STATUS = 0xFF;
  dma_setup(DMA_BASE, 0, SRC_AREA, UNMAPPED_ADDR, 32);
  DMA_REG(DMA_BASE, 0, DMA_CTRL) = CTRL_START;
  done = dma_wait(DMA_BASE, 0);
  check("a bad destination finishes and reports an error",
        done && (DMA_REG(DMA_BASE, 0, DMA_STATUS) & STATUS_ERROR));
  check("the bus monitor records the DMA write error", (BMON_STATUS & WRITE_ERROR_DMA) != 0);
  DMA_REG(DMA_BASE, 0, DMA_STATUS) = STATUS_DONE | STATUS_ERROR;
  BMON_STATUS = 0xFF;

  // The engine must still work after errors.
  fill_source(0x44);
  check("DMA works after an error", copy_ok(DMA_BASE, 0, 0, 0, 64));
}

static int irq_case(uint64_t base, uint32_t ch, uint32_t source) {
  PLIC_PRIORITY(source) = 1;
  PLIC_THRESHOLD(CTX_M) = 0;
  PLIC_ENABLE(CTX_M) = 1U << source;
  irq_count = 0;
  last_id = 0;
  irq_base = base;
  irq_channel = ch;
  SET_CSR(mie, 1UL << IRQ_M_EXT);
  SET_CSR(mstatus, MSTATUS_MIE);
  dma_setup(base, ch, SRC_AREA, fresh_dst(64), 32);
  DMA_REG(base, ch, DMA_CTRL) = CTRL_START | CTRL_IRQ_EN;
  WAIT_FOR(irq_count != 0);
  CLEAR_CSR(mstatus, MSTATUS_MIE);
  CLEAR_CSR(mie, 1UL << IRQ_M_EXT);
  DMA_REG(base, ch, DMA_CTRL) = 0;
  PLIC_ENABLE(CTX_M) = 0;
  PLIC_PRIORITY(source) = 0;
  return irq_count == 1 && last_id == source;
}

static void test_interrupts(void) {
  check("DMA channel 2 finishing raises its interrupt", irq_case(DMA_BASE, 2, SRC_DMA));
  check("DMA channel 3 finishing raises its interrupt", irq_case(DMA_BASE, 3, SRC_DMA));
}

int main(void) {
  adr_test_begin("ADR SoC DMA test");
  test_copies();
  test_channels();
  test_coherency();
  test_cpu_runs_during_dma();
  test_errors();
  test_interrupts();
  return adr_test_end();
}
