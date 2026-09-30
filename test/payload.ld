ENTRY(_start)
SECTIONS {
    . = 0x40000000;
    .text : { *(.text) }
    /DISCARD/ : { *(.comment) *(.eh_frame) *(.riscv.attributes) }
}
