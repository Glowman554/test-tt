# rvmodel_macros.h
# DUT-specific macros for the Inferno RV32IMAC core running in verification/testbench.sv.
# SPDX-License-Identifier: BSD-3-Clause

#ifndef _RVMODEL_MACROS_H
#define _RVMODEL_MACROS_H

#define CLINT_BASE_ADDRESS 0x02000000

#define STANDARD_SM_SUPPORTED

#define SIG_ADDRESS 0x80000004

#define RVMODEL_DATA_SECTION \
        .pushsection .tohost,"aw",@progbits;                \
        .balign 8; .global tohost; tohost: .dword 0;         \
        .balign 8; .global fromhost; fromhost: .dword 0;     \
        .popsection

##### TERMINATION #####

#define RVMODEL_HALT_PASS  \
  li x1, 1                ;\
  la t0, tohost           ;\
  write_tohost_pass:      ;\
    sw x1, 0(t0)          ;\
    sw x0, 4(t0)          ;\
    j write_tohost_pass   ;\

#define RVMODEL_HALT_FAIL \
  li x1, 3                ;\
  la t0, tohost           ;\
  write_tohost_fail:      ;\
    sw x1, 0(t0)          ;\
    sw x0, 4(t0)          ;\
    j write_tohost_fail   ;\

##### IO #####

#define RVMODEL_IO_WRITE_STR(_R1, _R2, _R3, _STR_PTR)   \
1:                           ;                       \
  lbu _R1, 0(_STR_PTR)        ;                       \
  beqz _R1, 3f                ;                       \
2:                           ;                       \
  la _R2, tohost              ;                       \
  sw _R1, 0(_R2)              ;                       \
  li _R1, 0x01010000          ;                       \
  sw _R1, 4(_R2)              ;                       \
  addi _STR_PTR, _STR_PTR, 1  ;                       \
  j 1b                        ;                       \
3:

##### Access Fault #####

#define RVMODEL_ACCESS_FAULT_ADDRESS 0x20000000

##### Machine Timer (CLINT, mtime increments every core clock) #####

#define RVMODEL_MTIMECMP_ADDRESS  0x02004000
#define RVMODEL_MTIME_ADDRESS     0x0200BFF8
#define RVMODEL_MAX_CYCLES_PER_TIMER_TICK 1
#define RVMODEL_TIMER_INT_SOON_DELAY 20000
#define RVMODEL_INTERRUPT_LATENCY 16

##### Machine Interrupts #####

#define RVMODEL_MSIP_ADDRESS (CLINT_BASE_ADDRESS + 0x0)

#define RVMODEL_SET_MEXT_INT(_R1, _R2)  \
  li _R1, (1 << 31) | (1 << 11)        ;\
  li _R2, SIG_ADDRESS                  ;\
  sw _R1, 0(_R2)                       ;

#define RVMODEL_CLR_MEXT_INT(_R1, _R2)  \
  li _R1, (1 << 11)                    ;\
  li _R2, SIG_ADDRESS                  ;\
  sw _R1, 0(_R2)                       ;

#endif // _RVMODEL_MACROS_H
