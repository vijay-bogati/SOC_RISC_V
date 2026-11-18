/***************************************************************
 Project name                  : ADR SoC
 File Name                     : serial.c
 Module/class Name             : main (test 'serial')
 Author                        : Vijay Bogati
 Description                   : Serial bus test: SPI, QSPI and I2C, against testbench devices
***************************************************************/

// ADR SoC - serial bus test: SPI, QSPI and I2C, against testbench devices.
// Each SPI bus has a memory model on chip select 0, and the I2C bus a one-byte register
// device. Nothing is connected to the other chip selects or I2C addresses.

#include "adr_lib.h"

#define SPI_BASE 0x10004000UL
#define QSPI_BASE 0x10006000UL
#define SPI_REG(base, off) (*(volatile uint32_t *)((base) + (off)))
#define SPI_STATUS 0x00
#define SPI_CLKDIV 0x04
#define SPI_CMD    0x08
#define SPI_ADDR   0x0C
#define SPI_LEN    0x10
#define SPI_DUMMY  0x14
#define SPI_TXFIFO 0x18
#define SPI_RXFIFO 0x20

#define START_READ       0x1U
#define START_WRITE      0x2U
#define START_QUAD_READ  0x4U
#define START_QUAD_WRITE 0x8U
#define STATUS_IDLE      0x1U
#define RX_COUNT(status) (((status) >> 16) & 0xFFU)

#define CMD_READ_ID 0x9FU
#define CMD_READ    0x03U
#define CMD_WRITE   0x02U

#define SRC_SPI 12
#define SRC_QSPI 14

#define I2C_BASE 0x10007000UL
#define I2C_REG(base, off) (*(volatile uint32_t *)((base) + (off)))
#define I2C_STATUS   0x00
#define I2C_COMMAND  0x04
#define I2C_DATA     0x08
#define I2C_PRESCALE 0x0C
#define I2C_BUSY      (1U << 0)
#define I2C_MISS_ACK  (1U << 3)
#define I2C_CMD_START (1U << 8)
#define I2C_CMD_READ  (1U << 9)
#define I2C_CMD_WRITE (1U << 10)
#define I2C_CMD_STOP  (1U << 12)
#define I2C_DATA_VALID (1U << 8)
#define I2C_DATA_LAST  (1U << 9)

static volatile uint32_t irq_count;
static volatile uint32_t last_id;

void adr_irq(uint64_t cause) {
  if (cause != IRQ_M_EXT) return;
  uint32_t id = PLIC_CLAIM(CTX_M);
  last_id = id;
  irq_count = irq_count + 1;
  PLIC_CLAIM(CTX_M) = id;
}

static void pause(void) {
  for (int i = 0; i < 40; i++) { __asm__ volatile("nop"); }
}

static int spi_wait_idle(uint64_t base) {
  pause();
  WAIT_FOR(SPI_REG(base, SPI_STATUS) & STATUS_IDLE);
  return SPI_REG(base, SPI_STATUS) & STATUS_IDLE;
}

// Lengths are in bits. Command and address values are left-aligned in their registers.
static void spi_setup(uint64_t base, uint32_t command, uint32_t address, uint32_t addr_bits,
                      uint32_t data_bits) {
  SPI_REG(base, SPI_CMD) = command << 24;
  SPI_REG(base, SPI_ADDR) = address << 8;
  SPI_REG(base, SPI_LEN) = 8U | (addr_bits << 8) | (data_bits << 16);
  SPI_REG(base, SPI_DUMMY) = 0;
}

static int spi_read_word(uint64_t base, uint32_t start, uint32_t chip, uint32_t *out) {
  SPI_REG(base, SPI_STATUS) = start | (1U << (8 + chip));
  if (!spi_wait_idle(base)) return 0;
  WAIT_FOR(RX_COUNT(SPI_REG(base, SPI_STATUS)) != 0);
  if (RX_COUNT(SPI_REG(base, SPI_STATUS)) == 0) return 0;
  *out = SPI_REG(base, SPI_RXFIFO);
  return 1;
}

static int spi_write_word(uint64_t base, uint32_t start, uint32_t value) {
  SPI_REG(base, SPI_TXFIFO) = value;
  SPI_REG(base, SPI_STATUS) = start | (1U << 8);
  return spi_wait_idle(base);
}

static int spi_id_ok(uint64_t base, uint32_t start, uint32_t expected) {
  uint32_t id = 0;
  spi_setup(base, CMD_READ_ID, 0, 0, 24);
  return spi_read_word(base, start, 0, &id) && (id & 0xFFFFFF) == expected;
}

static int spi_write_then_read(uint64_t base, uint32_t wr, uint32_t rd, uint32_t address,
                               uint32_t value) {
  uint32_t got = 0;
  spi_setup(base, CMD_WRITE, address, 24, 32);
  if (!spi_write_word(base, wr, value)) return 0;
  spi_setup(base, CMD_READ, address, 24, 32);
  return spi_read_word(base, rd, 0, &got) && got == value;
}

static void test_spi_bus(uint64_t base, uint32_t id, uint32_t source, const char *id_name,
                         const char *data_name, const char *addr_name, const char *cs_name,
                         const char *irq_name) {
  SPI_REG(base, SPI_CLKDIV) = 3;
  check(id_name, spi_id_ok(base, START_READ, id));
  check(data_name, spi_write_then_read(base, START_WRITE, START_READ, 0x10, 0x11223344));

  // A second location must not overwrite the first.
  int ok = spi_write_then_read(base, START_WRITE, START_READ, 0x20, 0xA5C3F00F);
  uint32_t first = 0;
  spi_setup(base, CMD_READ, 0x10, 24, 32);
  ok = ok && spi_read_word(base, START_READ, 0, &first) && first == 0x11223344;
  check(addr_name, ok);

  // Chip select 1 has no device, so the data lines stay low.
  uint32_t absent = 0xFFFFFFFF;
  spi_setup(base, CMD_READ_ID, 0, 0, 24);
  check(cs_name, spi_read_word(base, START_READ, 1, &absent) && (absent & 0xFFFFFF) == 0);

  // End of transfer raises the interrupt.
  PLIC_PRIORITY(source) = 1;
  PLIC_THRESHOLD(CTX_M) = 0;
  PLIC_ENABLE(CTX_M) = 1U << source;
  // Earlier transfers already latched this edge source. Clear that before the real test.
  uint32_t stale = PLIC_CLAIM(CTX_M);
  if (stale) PLIC_CLAIM(CTX_M) = stale;
  irq_count = 0;
  last_id = 0;
  SET_CSR(mie, 1UL << IRQ_M_EXT);
  SET_CSR(mstatus, MSTATUS_MIE);
  uint32_t ignored;
  spi_setup(base, CMD_READ_ID, 0, 0, 24);
  ok = spi_read_word(base, START_READ, 0, &ignored);
  WAIT_FOR(irq_count != 0);
  CLEAR_CSR(mstatus, MSTATUS_MIE);
  CLEAR_CSR(mie, 1UL << IRQ_M_EXT);
  PLIC_ENABLE(CTX_M) = 0;
  PLIC_PRIORITY(source) = 0;
  check(irq_name, ok && irq_count == 1 && last_id == source);
}

static void test_qspi_quad(void) {
  check("QSPI reads ID on four lines", spi_id_ok(QSPI_BASE, START_QUAD_READ, 0xA10003));
  check("QSPI writes and reads on four lines",
        spi_write_then_read(QSPI_BASE, START_QUAD_WRITE, START_QUAD_READ, 0x40, 0xDEADBEEF));

  uint32_t got = 0;
  spi_setup(QSPI_BASE, CMD_WRITE, 0x50, 24, 32);
  int ok = spi_write_word(QSPI_BASE, START_QUAD_WRITE, 0x01234567);
  spi_setup(QSPI_BASE, CMD_READ, 0x50, 24, 32);
  ok = ok && spi_read_word(QSPI_BASE, START_READ, 0, &got) && got == 0x01234567;
  check("data written on four lines reads back on one", ok);
}

// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// I2C
// ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
static int i2c_wait(uint64_t base) {
  pause();
  WAIT_FOR(!(I2C_REG(base, I2C_STATUS) & I2C_BUSY));
  return !(I2C_REG(base, I2C_STATUS) & I2C_BUSY);
}

static int i2c_write_byte(uint64_t base, uint32_t device, uint32_t value) {
  I2C_REG(base, I2C_DATA) = value | I2C_DATA_LAST;
  I2C_REG(base, I2C_COMMAND) = device | I2C_CMD_START | I2C_CMD_WRITE | I2C_CMD_STOP;
  return i2c_wait(base);
}

static int i2c_read_byte(uint64_t base, uint32_t device, uint32_t *out) {
  I2C_REG(base, I2C_COMMAND) = device | I2C_CMD_START | I2C_CMD_READ | I2C_CMD_STOP;
  if (!i2c_wait(base)) return 0;
  uint32_t data = 0;
  for (int i = 0; i < 1000; i++) {
    data = I2C_REG(base, I2C_DATA);
    if (data & I2C_DATA_VALID) {
      *out = data & 0xFF;
      return 1;
    }
  }
  return 0;
}

static void test_i2c_bus(uint64_t base, uint32_t device, uint32_t other_device, uint32_t value,
                         const char *data_name, const char *second_name, const char *miss_name,
                         const char *clear_name) {
  I2C_REG(base, I2C_PRESCALE) = 8;
  uint32_t got = 0;
  check(data_name, i2c_write_byte(base, device, value) && i2c_read_byte(base, device, &got) &&
                       got == value);
  check(second_name, i2c_write_byte(base, device, value ^ 0xFF) &&
                         i2c_read_byte(base, device, &got) && got == (value ^ 0xFF));
  check("no missed ACK on a good transfer", !(I2C_REG(base, I2C_STATUS) & I2C_MISS_ACK));

  // No device answers this address.
  i2c_write_byte(base, other_device, 0x00);
  check(miss_name, I2C_REG(base, I2C_STATUS) & I2C_MISS_ACK);
  I2C_REG(base, I2C_STATUS) = I2C_MISS_ACK;  // write 1 to clear
  check(clear_name, !(I2C_REG(base, I2C_STATUS) & I2C_MISS_ACK));
}

// These offsets have no block, so reads must return the bridge's empty-slot data.
static void test_free_slots(void) {
  const uint32_t empty_slot_data = 0xDEA110C8U;
  uint32_t first = *(volatile uint32_t *)0x10005000UL;
  uint32_t second = *(volatile uint32_t *)0x10008000UL;
  uint32_t third = *(volatile uint32_t *)0x1000F000UL;
  check("free slots return error data",
        first == empty_slot_data && second == empty_slot_data && third == empty_slot_data);
}

int main(void) {
  adr_test_begin("ADR SoC serial bus test");
  test_spi_bus(SPI_BASE, 0xA10001, SRC_SPI, "SPI reads the device ID", "SPI writes and reads",
               "SPI addresses are independent", "SPI chip select 1 is not the device",
               "SPI end-of-transfer interrupt");
  test_spi_bus(QSPI_BASE, 0xA10003, SRC_QSPI, "QSPI reads the device ID on one line",
               "QSPI writes and reads on one line", "QSPI addresses are independent",
               "QSPI chip select 1 is not the device", "QSPI end-of-transfer interrupt");
  test_qspi_quad();
  test_i2c_bus(I2C_BASE, 0x50, 0x60, 0x5A, "I2C writes and reads the device",
               "I2C reads a new value", "I2C reports a missed ACK", "I2C missed ACK clears");
  test_free_slots();
  return adr_test_end();
}
