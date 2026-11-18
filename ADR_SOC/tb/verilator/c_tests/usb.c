/***************************************************************
 Project name                  : ADR SoC
 File Name                     : usb.c
 Module/class Name             : main (test 'usb')
 Author                        : Vijay Bogati
 Description                   : USB device test, against the simple host model in the testbench
***************************************************************/

// ADR SoC - USB device test, against the simple host model in the testbench.
// The host resets the bus when the device connects, sends a start of frame, a SETUP to
// endpoint 0 and an OUT to endpoint 1, then polls endpoint 1 with IN tokens. It only ACKs IN
// data with the expected bytes and CRC, so the "sent" status proves the data was right.

#include "adr_lib.h"

#define USB_BASE 0x10015000UL
#define USB(off) (*(volatile uint32_t *)(USB_BASE + (off)))
#define USB_INTR_STATE     USB(0x00)
#define USB_INTR_ENABLE    USB(0x04)
#define USB_CTRL           USB(0x10)
#define USB_EP_OUT_ENABLE  USB(0x14)
#define USB_EP_IN_ENABLE   USB(0x18)
#define USB_STAT           USB(0x1C)
#define USB_AV_OUT         USB(0x20)
#define USB_AV_SETUP       USB(0x24)
#define USB_RX_FIFO        USB(0x28)
#define USB_RX_EN_SETUP    USB(0x2C)
#define USB_RX_EN_OUT      USB(0x30)
#define USB_IN_SENT        USB(0x38)
#define USB_CONFIG_IN(ep)  USB(0x44 + 4 * (ep))
#define USB_BUFFER(id, w)  USB(0x800 + 64 * (id) + 4 * (w))

#define STAT_FRAME(s)    ((s) & 0x7FFU)
#define STAT_SENSE       (1U << 15)
#define STAT_RX_EMPTY    (1U << 31)
#define RX_BUFFER(r)     ((r) & 0x1FU)
#define RX_SIZE(r)       (((r) >> 8) & 0x7FU)
#define RX_SETUP         (1U << 19)
#define RX_EP(r)         (((r) >> 20) & 0xFU)
#define CONFIG_RDY       (1U << 31)
#define INTR_PKT_RECEIVED (1U << 0)

#define SRC_USB 28

static volatile uint32_t irq_count;
static volatile uint32_t last_id;

void adr_irq(uint64_t cause) {
  if (cause != IRQ_M_EXT) return;
  uint32_t id = PLIC_CLAIM(CTX_M);
  last_id = id;
  irq_count = irq_count + 1;
  USB_INTR_ENABLE = 0;  // this interrupt follows the receive FIFO, so mask it here
  PLIC_CLAIM(CTX_M) = id;
}

static int buffer_holds(uint32_t id, uint32_t first, uint32_t len) {
  for (uint32_t i = 0; i < len; i++) {
    uint32_t word = USB_BUFFER(id, i / 4);
    if (((word >> (8 * (i % 4))) & 0xFFU) != first + i) return 0;
  }
  return 1;
}

static void test_registers(void) {
  check("the device starts disabled", USB_CTRL == 0);
  USB_BUFFER(5, 3) = 0xA5C3F00FU;
  check("the packet buffer reads back", USB_BUFFER(5, 3) == 0xA5C3F00FU);
}

static void test_connect(void) {
  USB_AV_SETUP = 0;
  USB_AV_OUT = 1;
  USB_RX_EN_SETUP = 1U << 0;
  USB_RX_EN_OUT = 1U << 1;
  USB_EP_OUT_ENABLE = 3;
  USB_EP_IN_ENABLE = 3;
  USB_CTRL = 1;  // connects the pull-up, which starts the host
  check("the bus is sensed", (USB_STAT & STAT_SENSE) != 0);
  WAIT_FOR(STAT_FRAME(USB_STAT) == 0x123);
  check("a start of frame updates the frame number", STAT_FRAME(USB_STAT) == 0x123);
}

static void test_setup_and_interrupt(void) {
  WAIT_FOR(!(USB_STAT & STAT_RX_EMPTY));
  check("a SETUP packet arrives", !(USB_STAT & STAT_RX_EMPTY));

  PLIC_PRIORITY(SRC_USB) = 1;
  PLIC_THRESHOLD(CTX_M) = 0;
  PLIC_ENABLE(CTX_M) = 1U << SRC_USB;
  irq_count = 0;
  last_id = 0;
  SET_CSR(mie, 1UL << IRQ_M_EXT);
  SET_CSR(mstatus, MSTATUS_MIE);
  USB_INTR_ENABLE = INTR_PKT_RECEIVED;
  WAIT_FOR(irq_count != 0);
  CLEAR_CSR(mstatus, MSTATUS_MIE);
  CLEAR_CSR(mie, 1UL << IRQ_M_EXT);
  PLIC_ENABLE(CTX_M) = 0;
  PLIC_PRIORITY(SRC_USB) = 0;
  check("a received packet raises the interrupt", irq_count == 1 && last_id == SRC_USB);

  uint32_t rx = USB_RX_FIFO;
  check("the SETUP is on endpoint 0 with 8 bytes",
        (rx & RX_SETUP) && RX_EP(rx) == 0 && RX_SIZE(rx) == 8 && RX_BUFFER(rx) == 0);
  check("the SETUP data is right", buffer_holds(RX_BUFFER(rx), 0x40, 8));
}

static void test_out(void) {
  WAIT_FOR(!(USB_STAT & STAT_RX_EMPTY));
  uint32_t rx = USB_RX_FIFO;
  check("an OUT packet arrives on endpoint 1 with 4 bytes",
        !(rx & RX_SETUP) && RX_EP(rx) == 1 && RX_SIZE(rx) == 4 && RX_BUFFER(rx) == 1);
  check("the OUT data is right", buffer_holds(RX_BUFFER(rx), 0x60, 4));
}

static void test_in(void) {
  USB_BUFFER(2, 0) = 0x13121110U;
  USB_BUFFER(2, 1) = 0x17161514U;
  USB_CONFIG_IN(1) = 2U | (8U << 8);
  USB_CONFIG_IN(1) = 2U | (8U << 8) | CONFIG_RDY;
  WAIT_FOR(USB_IN_SENT & (1U << 1));
  check("the host accepts the IN data", (USB_IN_SENT & (1U << 1)) != 0);
  USB_IN_SENT = 1U << 1;
  check("the sent flag clears", (USB_IN_SENT & (1U << 1)) == 0);
}

int main(void) {
  adr_test_begin("ADR SoC USB test");
  test_registers();
  test_connect();
  test_setup_and_interrupt();
  test_out();
  test_in();
  return adr_test_end();
}
