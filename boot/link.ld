ENTRY(_start)
SECTIONS {
    . = 0;
    .text : { *(.text.init) *(.text .text.*) *(.rodata .rodata.*) }
    /DISCARD/ : { *(.comment) *(.eh_frame) *(.riscv.attributes) }
    ASSERT(. <= 0x10000, "boot stage exceeds reserved flash area")
}
