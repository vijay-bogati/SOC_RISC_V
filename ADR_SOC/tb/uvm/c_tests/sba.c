/***************************************************************
 Project name                  : ADR SoC
 File Name                     : sba.c
 Module/class Name             : main (test 'sba')
 Author                        : Vijay Bogati
 Description                   : Debug system bus access sizes and errors, run with the UVM JTAG agent (UVM test adr_sba_test)
***************************************************************/

// ADR SoC - debug system bus access (SBA) checks (ADR_TEST_PLAN NEG-11 to NEG-16). UVM bench only.
// The program asks the bench to act (request SBA_REQUEST) and waits. The bench's debugger then
// makes 8, 16, 32 and 64-bit accesses to SRAM and to two PWM registers, and accesses that must
// fail: misaligned, 128-bit, no target (DECERR) and a gated peripheral (SLVERR). It reports each
// step itself. When it has finished, the program checks from its side that the debugger's
// writes landed where they should and nowhere else, and that the debugger restored CLK_EN.
// The values and addresses are shared with adr_soc_sba_seq in tb/uvm/uvm_sequence/adr_soc_seq_pkg.sv.

#include "adr_lib.h"

#define SBA_REQUEST 1U

// SRAM word the debugger writes in parts. Read through the uncached alias: the debugger's
// writes don't go through the data cache.
#define SBA_WORD    (*(volatile uint64_t *)UNCACHED(0x80070400UL))
#define SBA_RESULT  0xCAFEF00DBEEFA577UL  // 64-bit pattern, then 32, 16 and 8-bit writes over it

// PWM timer 0 channel 1 and 2 thresholds: two 32-bit registers in one 64-bit word.
#define PWM_CH1_TH  (*(volatile uint32_t *)0x10009010UL)
#define PWM_CH2_TH  (*(volatile uint32_t *)0x10009014UL)
#define CH1_VALUE   0x1234U  // written first, must survive the later 32-bit write to CH2
#define CH2_VALUE   0x0ABCU  // last value the debugger wrote to CH2

#define CLK_EN      (*(volatile uint32_t *)0x1000D01CUL)
#define CLK_PWM     (1U << 6)

int main(void) {
  adr_test_begin("ADR SoC debug system bus access test");

  adr_tb_request(SBA_REQUEST);

  check("SRAM word holds the debugger's 64, 32, 16 and 8-bit writes", SBA_WORD == SBA_RESULT);
  check("PWM clock enabled again by the debugger", (CLK_EN & CLK_PWM) != 0);
  check("32-bit write to CH2 left CH1 unchanged", PWM_CH1_TH == CH1_VALUE);
  check("CH2 holds the debugger's last 32-bit write", PWM_CH2_TH == CH2_VALUE);
  return adr_test_end();
}
