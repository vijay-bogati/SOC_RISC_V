/***************************************************************
 Project name                  : ADR SoC
 File Name                     : crt0.S
 Module/class Name             : _start (start-up code)
 Author                        : Vijay Bogati
 Description                   : Bare-metal start-up for programs linked to SRAM
***************************************************************/

    .section .text.init
    .globl _start
_start:
    la    t0, trap_entry
    csrw  mtvec, t0

    # Enable the floating-point unit (mstatus.FS = initial).
    li    t0, (1 << 13)
    csrs  mstatus, t0
    csrw  fcsr, zero

    # Clear .bss.
    la    t0, __bss_start
    la    t1, __bss_end
1:  bgeu  t0, t1, 2f
    sd    zero, 0(t0)
    addi  t0, t0, 8
    j     1b
2:
    la    sp, __stack_top
    call  main
    call  adr_exit
3:  j     3b

# All traps: save caller-saved registers and let adr_trap() choose the return address.
    .align 4
trap_entry:
    addi  sp, sp, -128
    sd    ra, 0(sp)
    sd    t0, 8(sp)
    sd    t1, 16(sp)
    sd    t2, 24(sp)
    sd    a0, 32(sp)
    sd    a1, 40(sp)
    sd    a2, 48(sp)
    sd    a3, 56(sp)
    sd    a4, 64(sp)
    sd    a5, 72(sp)
    sd    a6, 80(sp)
    sd    a7, 88(sp)
    sd    t3, 96(sp)
    sd    t4, 104(sp)
    sd    t5, 112(sp)
    sd    t6, 120(sp)
    csrr  a0, mcause
    csrr  a1, mepc
    call  adr_trap
    csrw  mepc, a0
    ld    ra, 0(sp)
    ld    t0, 8(sp)
    ld    t1, 16(sp)
    ld    t2, 24(sp)
    ld    a0, 32(sp)
    ld    a1, 40(sp)
    ld    a2, 48(sp)
    ld    a3, 56(sp)
    ld    a4, 64(sp)
    ld    a5, 72(sp)
    ld    a6, 80(sp)
    ld    a7, 88(sp)
    ld    t3, 96(sp)
    ld    t4, 104(sp)
    ld    t5, 112(sp)
    ld    t6, 120(sp)
    addi  sp, sp, 128
    mret
