/***************************************************************
 Project name                  : ADR SoC
 File Name                     : link.ld
 Module/class Name             : Linker script
 Author                        : Vijay Bogati
 Description                   : Linker script: program image in SRAM
***************************************************************/

/* ADR SoC - program image in SRAM. */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
  SRAM (rwx) : ORIGIN = 0x80000000, LENGTH = 512K
}

SECTIONS {
  .text : { *(.text.init) *(.text .text.*) } > SRAM
  .rodata : { *(.rodata .rodata.* .srodata .srodata.*) } > SRAM
  .data : { *(.data .data.* .sdata .sdata.*) } > SRAM
  .bss (NOLOAD) : ALIGN(8) {
    __bss_start = .;
    *(.bss .bss.* .sbss .sbss.* COMMON)
    . = ALIGN(8);
    __bss_end = .;
  } > SRAM
  __stack_top = ORIGIN(SRAM) + LENGTH(SRAM);
  /DISCARD/ : { *(.comment) *(.note*) *(.eh_frame*) *(.riscv.attributes) }
}
