    .section .text, "ax"
    .globl _start
_start:
    li t0, 0x40000100
    li t1, 0x12345678
    sw t1, 0(t0)
1:  j 1b
