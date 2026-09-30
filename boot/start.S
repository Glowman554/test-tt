    .section .text.init, "ax"
    .globl _start
_start:
    /* PSRAM is available after the hardware's 150 us startup holdoff. */
    li sp, 0x41000000
    li t0, 0x00010000
    lw t1, 0(t0)                 /* "INFR" magic */
    li t2, 0x52464e49
    bne t1, t2, boot_fail
    lw t3, 4(t0)                 /* payload byte count */
    beqz t3, boot_fail
    andi t1, t3, 3
    bnez t1, boot_fail
    li t2, 0x00fefff0           /* 16 MiB flash minus header offset */
    bltu t2, t3, boot_fail
    lw t4, 8(t0)                 /* payload entry point */
    li t2, 0x40000000
    bltu t4, t2, boot_fail
    li t1, 0x41000000
    bgeu t4, t1, boot_fail
    li t5, 0x40000000
    addi t0, t0, 16             /* payload begins after the header */
copy_payload:
    lw t1, 0(t0)
    sw t1, 0(t5)
    addi t0, t0, 4
    addi t5, t5, 4
    addi t3, t3, -4
    bnez t3, copy_payload
    fence.i
    jr t4
boot_fail:
    j boot_fail
