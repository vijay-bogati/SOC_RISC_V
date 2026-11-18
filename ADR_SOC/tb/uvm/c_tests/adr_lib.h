/***************************************************************
 Project name                  : ADR SoC
 File Name                     : adr_lib.h
 Module/class Name             : Shared test library
 Author                        : Vijay Bogati
 Description                   : Shared helpers for bare-metal tests, with the C-UVM handshake (UVM bench copy)
***************************************************************/

// ADR SoC - shared helpers for bare-metal tests.
#ifndef ADR_LIB_H
#define ADR_LIB_H

#include <stdint.h>

#define UART0_BASE 0x10000000UL
#define UART_REG(n) (*(volatile uint32_t *)(UART0_BASE + 4 * (n)))
enum { UART_THR = 0, UART_IER = 1, UART_FCR = 2, UART_LCR = 3, UART_LSR = 5,
       UART_DLL = 0, UART_DLM = 1 };

// PLIC, shared by the interrupt tests. Context 0 is machine mode, context 1 supervisor.
#define PLIC_BASE         0x0C000000UL
#define PLIC_PRIORITY(s)  (*(volatile uint32_t *)(PLIC_BASE + 4 * (s)))
#define PLIC_PENDING      (*(volatile uint32_t *)(PLIC_BASE + 0x1000))
#define PLIC_ENABLE(c)    (*(volatile uint32_t *)(PLIC_BASE + 0x2000 + 0x80 * (c)))
#define PLIC_THRESHOLD(c) (*(volatile uint32_t *)(PLIC_BASE + 0x200000 + 0x1000 * (c)))
#define PLIC_CLAIM(c)     (*(volatile uint32_t *)(PLIC_BASE + 0x200004 + 0x1000 * (c)))
#define CTX_M 0
#define CTX_S 1

// Spin until a condition holds, so a missing event fails a check rather than hanging.
#define WAIT_LOOPS 200000
#define WAIT_FOR(cond) \
  do { for (int i_ = 0; i_ < WAIT_LOOPS && !(cond); i_++) {} } while (0)

#define READ_CSR(name) ({ uint64_t v_; __asm__ volatile("csrr %0, " #name : "=r"(v_)); v_; })
#define SET_CSR(name, bits) __asm__ volatile("csrs " #name ", %0" : : "r"((uint64_t)(bits)))
#define CLEAR_CSR(name, bits) __asm__ volatile("csrc " #name ", %0" : : "r"((uint64_t)(bits)))

// The data cache doesn't see writes from DMA or other bus masters. Read such a buffer through
// its uncached alias, or invalidate the cache first. Machine mode only: CSR 0x7C1 is CVA6's
// data cache enable, and enabling the cache invalidates all of it.
#define UNCACHED(addr) ((addr) + 0x100000000UL)
static inline void dcache_invalidate(void) {
  __asm__ volatile("csrwi 0x7C1, 0\n csrwi 0x7C1, 1\n fence");
}

#define MSTATUS_MIE (1UL << 3)
#define IRQ_M_SOFT  3
#define IRQ_M_TIMER 7
#define IRQ_S_EXT   9
#define IRQ_M_EXT   11

// Updated by the trap handler.
extern volatile uint64_t trap_cause;  // last mcause
extern volatile uint64_t trap_count;  // exceptions and interrupts taken

// Tests that use interrupts define this. The cause has the interrupt bit removed.
void adr_irq(uint64_t cause);

void uart_puts(const char *s);
void uart_puthex(uint64_t value);
void check(const char *name, int ok);
void adr_test_begin(const char *title);
int adr_test_end(void);  // returns the number of failed checks

// C-UVM handshake (UVM bench only, built with -DADR_TB_SYNC). The program writes a tagged word to
// system control SCRATCH0; the UVM bench sees the APB write and acts on it. For a request, the
// bench writes the same word back into SCRATCH1 when it has done its part.
//   bits 31:24  0xC5, marks a handshake word (other SCRATCH0 values are ignored)
//   bits 23:16  event: 1 end of test, 2 checkpoint, 3 request
//   bits 15:0   argument: failed checks, checkpoint number, or request code
// The end-of-test word is sent by adr_exit, after the end character, so the UART report and its
// cycle count are the same as without the handshake. The sys and misc tests also use the scratch
// registers; they make no requests, and the end word comes after they are done with them.
#define TB_SYNC_CMD        (*(volatile uint32_t *)0x1000D010UL)  // SCRATCH0
#define TB_SYNC_ACK        (*(volatile uint32_t *)0x1000D014UL)  // SCRATCH1
#define TB_SYNC_TAG        0xC5000000U
#define TB_SYNC_END        1U
#define TB_SYNC_CHECKPOINT 2U
#define TB_SYNC_REQUEST    3U
#define TB_SYNC_WORD(event, arg) (TB_SYNC_TAG | ((event) << 16) | ((uint32_t)(arg) & 0xFFFFU))
#ifdef ADR_TB_SYNC
void adr_tb_checkpoint(uint32_t number);  // tell the bench a point was reached
void adr_tb_request(uint32_t code);       // ask the bench to act, and wait until it has
#endif

#endif
