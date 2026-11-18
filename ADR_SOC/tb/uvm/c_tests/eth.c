/***************************************************************
 Project name                  : ADR SoC
 File Name                     : eth.c
 Module/class Name             : main (test 'eth')
 Author                        : Vijay Bogati
 Description                   : Ethernet test. The testbench loops transmit back to receive at the SerDes interface
***************************************************************/

// The CPU's data cache does not see what the MAC writes, so receive buffers are read uncached.

#include "adr_lib.h"

#define ETH(off) (*(volatile uint32_t *)(0x10014000UL + (off)))
#define ETH_CTRL       ETH(0x00)
#define ETH_STATUS     ETH(0x04)
#define ETH_TX_ADDR_LO ETH(0x08)
#define ETH_TX_ADDR_HI ETH(0x0C)
#define ETH_TX_LEN     ETH(0x10)
#define ETH_TX_START   ETH(0x14)
#define ETH_RX_ADDR_LO ETH(0x18)
#define ETH_RX_ADDR_HI ETH(0x1C)
#define ETH_RX_SIZE    ETH(0x20)
#define ETH_RX_START   ETH(0x24)
#define ETH_RX_LEN     ETH(0x28)

#define CTRL_TX_EN  (1U << 0)
#define CTRL_RX_EN  (1U << 1)
#define CTRL_RX_IRQ (1U << 3)
#define ST_TX_BUSY  (1U << 0)
#define ST_TX_DONE  (1U << 1)
#define ST_TX_ERROR (1U << 2)
#define ST_RX_BUSY  (1U << 3)
#define ST_RX_DONE  (1U << 4)
#define ST_RX_ERROR (1U << 5)
#define ST_CLEAR    0x76U
#define ST_BLOCK_LOCK (1U << 8)
#define ST_HIGH_BER   (1U << 9)

#define BMON_STATUS (*(volatile uint32_t *)0x1000C000UL)
#define READ_ERROR_ETH  (1U << 3)
#define WRITE_ERROR_ETH (1U << 7)
#define UNMAPPED_ADDR 0x40000000UL

#define SRC_ETH 27
#define TX_AREA 0x80040000UL
#define RX_AREA 0x80050000UL

static volatile uint32_t irq_count;
static volatile uint32_t last_id;

void adr_irq(uint64_t cause) {
  if (cause != IRQ_M_EXT) return;
  uint32_t id = PLIC_CLAIM(CTX_M);
  last_id = id;
  irq_count = irq_count + 1;
  ETH_STATUS = ST_CLEAR;
  PLIC_CLAIM(CTX_M) = id;
}

static volatile uint8_t *tx_bytes(void) { return (volatile uint8_t *)TX_AREA; }
static volatile uint8_t *rx_bytes(void) { return (volatile uint8_t *)UNCACHED(RX_AREA); }

static void fill_frame(uint32_t len, uint32_t seed) {
  for (uint32_t i = 0; i < len; i++) tx_bytes()[i] = (uint8_t)(i * 7 + seed);
}

static void start_rx(uint64_t addr, uint32_t size) {
  ETH_RX_ADDR_LO = (uint32_t)addr;
  ETH_RX_ADDR_HI = (uint32_t)(addr >> 32);
  ETH_RX_SIZE = size;
  ETH_RX_START = 1;
}

static void start_tx(uint64_t addr, uint32_t len) {
  ETH_TX_ADDR_LO = (uint32_t)addr;
  ETH_TX_ADDR_HI = (uint32_t)(addr >> 32);
  ETH_TX_LEN = len;
  ETH_TX_START = 1;
}

static int frame_matches(uint32_t len, uint32_t seed) {
  for (uint32_t i = 0; i < len; i++) {
    if (rx_bytes()[i] != (uint8_t)(i * 7 + seed)) return 0;
  }
  return 1;
}

static void test_loopback(void) {
  check("registers start idle", (ETH_STATUS & ST_CLEAR) == 0 && ETH_CTRL == 0);
  WAIT_FOR(ETH_STATUS & ST_BLOCK_LOCK);
  check("the receive side locks onto the blocks",
        (ETH_STATUS & ST_BLOCK_LOCK) && !(ETH_STATUS & ST_HIGH_BER));
  ETH_CTRL = CTRL_TX_EN | CTRL_RX_EN;

  fill_frame(128, 0x11);
  start_rx(RX_AREA, 1024);
  start_tx(TX_AREA, 128);
  WAIT_FOR(ETH_STATUS & ST_RX_DONE);
  uint32_t status = ETH_STATUS;
  check("a frame loops back", (status & ST_TX_DONE) && (status & ST_RX_DONE));
  check("no bus errors on a good frame", !(status & (ST_TX_ERROR | ST_RX_ERROR)));
  check("the received length is right", ETH_RX_LEN == 128);
  check("the received data is right", frame_matches(128, 0x11));
  ETH_STATUS = ST_CLEAR;
  check("status clears", (ETH_STATUS & ST_CLEAR) == 0);

  // Bursts from an address that isn't aligned to the bus width.
  for (uint32_t i = 0; i < 100; i++) *(volatile uint8_t *)(TX_AREA + 3 + i) = (uint8_t)(i * 7 + 0x22);
  start_rx(RX_AREA + 0x400, 1024);
  start_tx(TX_AREA + 3, 100);
  WAIT_FOR(ETH_STATUS & ST_RX_DONE);
  int ok = ETH_RX_LEN == 100;
  for (uint32_t i = 0; i < 100; i++) {
    ok &= *(volatile uint8_t *)(UNCACHED(RX_AREA) + 0x400 + i) == (uint8_t)(i * 7 + 0x22);
  }
  check("an unaligned frame loops back", ok);
  ETH_STATUS = ST_CLEAR;
}

static void test_short_frame(void) {
  fill_frame(20, 0x33);
  for (uint32_t i = 0; i < 64; i++) rx_bytes()[i] = 0xFF;
  start_rx(RX_AREA, 1024);
  start_tx(TX_AREA, 20);
  WAIT_FOR(ETH_STATUS & ST_RX_DONE);
  int ok = ETH_RX_LEN == 60 && frame_matches(20, 0x33);
  for (uint32_t i = 20; i < 60; i++) ok &= rx_bytes()[i] == 0;
  check("a short frame is padded to 60 bytes", ok);
  ETH_STATUS = ST_CLEAR;
}

static void test_small_buffer(void) {
  fill_frame(200, 0x44);
  for (uint32_t i = 0; i < 80; i++) rx_bytes()[i] = 0xFF;
  start_rx(RX_AREA, 64);
  start_tx(TX_AREA, 200);
  WAIT_FOR(ETH_STATUS & ST_RX_DONE);
  int ok = ETH_RX_LEN == 64 && frame_matches(64, 0x44);
  for (uint32_t i = 64; i < 80; i++) ok &= rx_bytes()[i] == 0xFF;
  check("a small buffer cuts the frame at its end", ok);
  WAIT_FOR(ETH_STATUS & ST_TX_DONE);
  ETH_STATUS = ST_CLEAR;
}

static void test_receive_off(void) {
  ETH_CTRL = CTRL_TX_EN;
  fill_frame(64, 0x55);
  start_tx(TX_AREA, 64);
  WAIT_FOR(ETH_STATUS & ST_TX_DONE);
  for (int i = 0; i < 2000; i++) { __asm__ volatile("nop"); }
  check("with receive off, nothing is received", !(ETH_STATUS & (ST_RX_DONE | ST_RX_BUSY)));
  ETH_STATUS = ST_CLEAR;
  ETH_CTRL = CTRL_TX_EN | CTRL_RX_EN;
}

static void test_interrupt(void) {
  PLIC_PRIORITY(SRC_ETH) = 1;
  PLIC_THRESHOLD(CTX_M) = 0;
  PLIC_ENABLE(CTX_M) = 1U << SRC_ETH;
  irq_count = 0;
  last_id = 0;
  SET_CSR(mie, 1UL << IRQ_M_EXT);
  SET_CSR(mstatus, MSTATUS_MIE);
  ETH_CTRL = CTRL_TX_EN | CTRL_RX_EN | CTRL_RX_IRQ;
  fill_frame(64, 0x66);
  start_rx(RX_AREA, 1024);
  start_tx(TX_AREA, 64);
  WAIT_FOR(irq_count != 0);
  CLEAR_CSR(mstatus, MSTATUS_MIE);
  CLEAR_CSR(mie, 1UL << IRQ_M_EXT);
  ETH_CTRL = CTRL_TX_EN | CTRL_RX_EN;
  PLIC_ENABLE(CTX_M) = 0;
  PLIC_PRIORITY(SRC_ETH) = 0;
  check("receive done raises the interrupt", irq_count == 1 && last_id == SRC_ETH);
  ETH_STATUS = ST_CLEAR;
}

static void test_bus_errors(void) {
  BMON_STATUS = 0xFF;
  start_tx(UNMAPPED_ADDR, 32);
  WAIT_FOR(ETH_STATUS & ST_TX_DONE);
  check("a bad transmit address reports an error", (ETH_STATUS & ST_TX_ERROR) != 0);
  check("the bus monitor records the read error", (BMON_STATUS & READ_ERROR_ETH) != 0);
  ETH_STATUS = ST_CLEAR;

  // That frame still goes out, carrying the bus's error data. Collect it, so it isn't taken
  // for the next frame. A driver must treat a transmit error as a frame sent with bad data.
  start_rx(RX_AREA, 1024);
  WAIT_FOR(ETH_STATUS & ST_RX_DONE);
  check("a frame sent after a bus error still arrives", (ETH_STATUS & ST_RX_DONE) != 0);
  ETH_STATUS = ST_CLEAR;

  BMON_STATUS = 0xFF;
  start_rx(UNMAPPED_ADDR, 256);
  fill_frame(64, 0x77);
  start_tx(TX_AREA, 64);
  WAIT_FOR(ETH_STATUS & ST_RX_DONE);
  check("a bad receive address reports an error", (ETH_STATUS & ST_RX_ERROR) != 0);
  check("the bus monitor records the write error", (BMON_STATUS & WRITE_ERROR_ETH) != 0);
  ETH_STATUS = ST_CLEAR;
  BMON_STATUS = 0xFF;

  fill_frame(64, 0x88);
  start_rx(RX_AREA, 1024);
  start_tx(TX_AREA, 64);
  WAIT_FOR(ETH_STATUS & ST_RX_DONE);
  check("it still works after errors", ETH_RX_LEN == 64 && frame_matches(64, 0x88));
  ETH_STATUS = ST_CLEAR;
}

int main(void) {
  adr_test_begin("ADR SoC Ethernet test");
  test_loopback();
  test_short_frame();
  test_small_buffer();
  test_receive_off();
  test_interrupt();
  test_bus_errors();
  return adr_test_end();
}
