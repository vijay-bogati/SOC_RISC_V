/***************************************************************
 Project name                  : ADR SoC
 File Name                     : aes.c
 Module/class Name             : main (test 'aes')
 Author                        : Vijay Bogati
 Description                   : AES test, using the published example vectors from FIPS-197
***************************************************************/

#include "adr_lib.h"

#define AES_BASE 0x1000B000UL
#define AES(off)   (*(volatile uint32_t *)(AES_BASE + (off)))
#define AES_CTRL   AES(0x00)
#define AES_STATUS AES(0x04)
#define AES_IRQ_EN AES(0x08)
#define AES_KEY(i) AES(0x10 + 4 * (i))
#define AES_IN(i)  AES(0x30 + 4 * (i))
#define AES_OUT(i) AES(0x40 + 4 * (i))

#define CTRL_START   1U
#define CTRL_DECRYPT 2U
#define CTRL_KEY(n)  ((uint32_t)(n) << 2)
#define STATUS_BUSY  1U
#define STATUS_DONE  2U
#define SRC_AES 20

// FIPS-197 Appendix C: one plaintext, and the same key pattern at three lengths.
static const uint32_t plain_c[4] = {0x00112233, 0x44556677, 0x8899AABB, 0xCCDDEEFF};
static const uint32_t key_c[8] = {0x00010203, 0x04050607, 0x08090A0B, 0x0C0D0E0F,
                                  0x10111213, 0x14151617, 0x18191A1B, 0x1C1D1E1F};
static const uint32_t cipher_128[4] = {0x69C4E0D8, 0x6A7B0430, 0xD8CDB780, 0x70B4C55A};
static const uint32_t cipher_192[4] = {0xDDA97CA4, 0x864CDFE0, 0x6EAF70A0, 0xEC0D7191};
static const uint32_t cipher_256[4] = {0x8EA2B7CA, 0x516745BF, 0xEAFC4990, 0x4B496089};

// FIPS-197 Appendix B: a second, unrelated key and plaintext.
static const uint32_t plain_b[4] = {0x3243F6A8, 0x885A308D, 0x313198A2, 0xE0370734};
static const uint32_t key_b[8] = {0x2B7E1516, 0x28AED2A6, 0xABF71588, 0x09CF4F3C};
static const uint32_t cipher_b[4] = {0x3925841D, 0x02DC09FB, 0xDC118597, 0x196A0B32};

static volatile uint32_t irq_count;
static volatile uint32_t last_id;

void adr_irq(uint64_t cause) {
  if (cause != IRQ_M_EXT) return;
  uint32_t id = PLIC_CLAIM(CTX_M);
  last_id = id;
  irq_count = irq_count + 1;
  if (id == SRC_AES) AES_STATUS = STATUS_DONE;
  PLIC_CLAIM(CTX_M) = id;
}

static void load(const uint32_t key[8], int key_words, const uint32_t in[4]) {
  for (int i = 0; i < 8; i++) AES_KEY(i) = (i < key_words) ? key[i] : 0;
  for (int i = 0; i < 4; i++) AES_IN(i) = in[i];
}

static int run_matches(uint32_t size, uint32_t mode, const uint32_t expected[4]) {
  AES_CTRL = CTRL_START | mode | CTRL_KEY(size);
  WAIT_FOR(AES_STATUS & STATUS_DONE);
  if (!(AES_STATUS & STATUS_DONE)) return 0;
  int ok = 1;
  for (int i = 0; i < 4; i++) ok &= AES_OUT(i) == expected[i];
  AES_STATUS = STATUS_DONE;
  return ok;
}

static void vector_pair(const char *enc_name, const char *dec_name, uint32_t size,
                        const uint32_t key[8], int key_words, const uint32_t plain[4],
                        const uint32_t cipher[4]) {
  load(key, key_words, plain);
  check(enc_name, run_matches(size, 0, cipher));
  load(key, key_words, cipher);
  check(dec_name, run_matches(size, CTRL_DECRYPT, plain));
}

static void test_vectors(void) {
  vector_pair("AES-128 encrypts the FIPS-197 C.1 vector", "AES-128 decrypts it", 0, key_c, 4,
              plain_c, cipher_128);
  vector_pair("AES-192 encrypts the FIPS-197 C.2 vector", "AES-192 decrypts it", 1, key_c, 6,
              plain_c, cipher_192);
  vector_pair("AES-256 encrypts the FIPS-197 C.3 vector", "AES-256 decrypts it", 2, key_c, 8,
              plain_c, cipher_256);
  vector_pair("AES-128 encrypts the FIPS-197 B vector", "and decrypts it", 0, key_b, 4, plain_b,
              cipher_b);
}

static void test_control(void) {
  check("idle and not done after those runs", AES_STATUS == 0);

  // Changing only the key must change the result, proving nothing is left over.
  load(key_b, 4, plain_c);
  AES_CTRL = CTRL_START | CTRL_KEY(0);
  uint32_t busy_seen = AES_STATUS & STATUS_BUSY;
  WAIT_FOR(AES_STATUS & STATUS_DONE);
  check("busy is set during a run", busy_seen != 0);
  check("done is set after a run", (AES_STATUS & (STATUS_BUSY | STATUS_DONE)) == STATUS_DONE);
  int differs = 0;
  for (int i = 0; i < 4; i++) differs |= AES_OUT(i) != cipher_128[i];
  check("a different key gives a different result", differs);
  AES_STATUS = STATUS_DONE;
  check("writing status clears done", !(AES_STATUS & STATUS_DONE));

  // Key registers are write-only.
  check("key registers do not read back", AES_KEY(0) == 0 && AES_KEY(1) == 0);
}

static void test_interrupt(void) {
  PLIC_PRIORITY(SRC_AES) = 1;
  PLIC_THRESHOLD(CTX_M) = 0;
  PLIC_ENABLE(CTX_M) = 1U << SRC_AES;
  irq_count = 0;
  last_id = 0;

  load(key_c, 4, plain_c);
  AES_IRQ_EN = 0;
  AES_CTRL = CTRL_START | CTRL_KEY(0);
  WAIT_FOR(AES_STATUS & STATUS_DONE);
  check("no interrupt when not enabled", !(PLIC_PENDING & (1U << SRC_AES)));
  AES_STATUS = STATUS_DONE;

  SET_CSR(mie, 1UL << IRQ_M_EXT);
  SET_CSR(mstatus, MSTATUS_MIE);
  AES_IRQ_EN = 1;
  AES_CTRL = CTRL_START | CTRL_KEY(0);
  WAIT_FOR(irq_count != 0);
  CLEAR_CSR(mstatus, MSTATUS_MIE);
  CLEAR_CSR(mie, 1UL << IRQ_M_EXT);
  AES_IRQ_EN = 0;
  PLIC_ENABLE(CTX_M) = 0;
  PLIC_PRIORITY(SRC_AES) = 0;
  check("done raises the AES interrupt", irq_count == 1 && last_id == SRC_AES);
  check("result is right when run under interrupt",
        AES_OUT(0) == cipher_128[0] && AES_OUT(3) == cipher_128[3]);
}

int main(void) {
  adr_test_begin("ADR SoC AES test");
  test_vectors();
  test_control();
  test_interrupt();
  return adr_test_end();
}
