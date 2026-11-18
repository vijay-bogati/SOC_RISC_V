/***************************************************************
 Project name                  : ADR SoC
 File Name                     : boot_rom.S
 Module/class Name             : Boot ROM program
 Author                        : Vijay Bogati
 Description                   : Boot ROM stub, runs from the reset vector and jumps to SRAM
***************************************************************/

    .section .text
    .globl _start
_start:
    li   t0, 0x80000000
    jr   t0
