# SPDX-License-Identifier: Apache-2.0
# Bare-metal checks for the Sophon extension profile, within Croc's 4 KiB SRAM.
# SOC_SMOKE ends after the instruction checks; the core test continues with
# CLIC stimuli supplied by tb_sophon_extensions through core_wrap's ports.
.option norvc
.option norelax

.section .vectors, "ax", @progbits
  j _start

.macro seed base
  .irp r,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16,17,18,19,20,21,22,23,24,25,26,27,28,29,30,31
    li x\r, (\base + \r)
  .endr
.endm

.macro phase value
  li t0, 0x10000f00
  li t1, \value
  sw t1, 0(t0)
.endm

.macro wait_count value
1:
  li t0, 0x10000f00
  lw t1, 4(t0)
  li t2, \value
  bltu t1, t2, 1b
  csrrci x0, mstatus, 8
.endm

.section .text._start, "ax", @progbits
.globl _start
_start:
  la sp, __stack_pointer$
  la gp, __global_pointer$
  csrw mie, x0
  csrw mstatus, x0
  la t0, standard_trap
  csrw mtvec, t0
  li t0, 0x10000f00
  .irp off,0,4,8,12,16,20,24
    sw x0, \off(t0)
  .endr
  li t1, 0x12345678
  csrw mtval, t1
  csrr t2, mtval
  bne t1, t2, fail
  li t1, 0x13579bdf
  csrw minstreth, t1
  csrr t2, minstreth
  bne t1, t2, fail

  # Three independent images, a full PUSH, then LIFO restore of every GPR.
  seed 0x100
  .insn r 0x2b, 1, 0x02, x0, x1, x31
  seed 0x200
  .insn r 0x2b, 1, 0x02, x0, x1, x31
  seed 0x300
  .insn r 0x2b, 1, 0x02, x0, x1, x31
  seed 0x400
  .insn r 0x2b, 1, 0x02, x0, x1, x31
  .insn r 0x2b, 1, 0x42, x0, x1, x31
  li t0, 0x30a
  bne a0, t0, fail
  .insn r 0x2b, 1, 0x42, x0, x1, x31
  li t0, 0x20a
  bne a0, t0, fail
  .insn r 0x2b, 1, 0x42, x0, x1, x31
  li t0, 0x10a
  bne a0, t0, fail
  # Empty POP with zero batch length: depth must stay zero.
  .insn r 0x2b, 1, 0x42, x0, x0, x0
  # Existing legacy snapshot read/write (bank zero).
  seed 0x500
  .insn r 0x2b, 1, 0x00, x0, x1, x31
  seed 0x600
  .insn r 0x2b, 1, 0x40, x0, x1, x31
  li t0, 0x50a
  bne a0, t0, fail
  # Unsupported SREG operation must report eei_error and suppress writeback.
  .insn r 0x2b, 1, 0x01, x0, x1, x31

  la sp, __stack_pointer$
  la gp, __global_pointer$
  la t0, standard_trap
  csrw mtvec, t0
  # Ordinary illegal instruction: mcause=2, followed by a misaligned load.
  li t0, 0x10000f00
  li t1, 2
  sw t1, 16(t0)
  .word 0xffffffff
  li t0, 0x10000f00
  li t1, 4
  sw t1, 16(t0)
  li t2, 0x10000002
  lw a5, 0(t2)
  lw t1, 12(t0)
  li t2, 2
  bne t1, t2, fail
#if SOC_SMOKE
  j success
#endif

  la t0, vector_table
  csrw 0x307, t0
  la t0, direct_trap
  ori t0, t0, 3
  csrw mtvec, t0
  csrw 0x347, x0
  phase 1
  .rept 16
    nop
  .endr
  csrrsi x0, mstatus, 8
  wait_count 1

  la t0, fast_trap
  ori t0, t0, 3
  csrw mtvec, t0
  phase 2
  csrrsi x0, mstatus, 8
  wait_count 2
  phase 3
  csrrsi x0, mstatus, 8
  wait_count 3
  li t0, 100
  csrw 0x347, t0
  phase 4
  csrrsi x0, mstatus, 8
  wait_count 4
  csrw 0x347, x0

  la t0, direct_trap
  ori t0, t0, 3
  csrw mtvec, t0
  phase 5
  csrrsi x0, mstatus, 8
  wait_count 8

  la t0, standard_trap
  csrw mtvec, t0
  li t0, 0x888
  csrw mie, t0
  phase 6
  csrrsi x0, mstatus, 8
1:
  li t0, 0x10000f00
  lw t1, 24(t0)
  li t2, 1
  bltu t1, t2, 1b
  phase 7
2:
  lw t1, 24(t0)
  li t2, 2
  bltu t1, t2, 2b
  phase 8
3:
  lw t1, 24(t0)
  li t2, 3
  bltu t1, t2, 3b
success:
  li t0, 0x03000008
  li t1, 1
  sw t1, 0(t0)
1: j 1b
fail:
  li t0, 0x03000008
  li t1, 3
  sw t1, 0(t0)
1: j 1b

.section .text, "ax", @progbits
.balign 64
direct_trap:
  .insn r 0x2b, 1, 0x02, x0, x1, x31
  csrrsi a0, 0x345, 1
  beqz a0, direct_tail
direct_service:
  lw a1, 0(a0)
  csrrsi x0, mstatus, 8
  jalr a1
  csrrci x0, mstatus, 8
  csrrsi a0, 0x345, 1
  bnez a0, direct_service
direct_tail:
  csrrci x0, mstatus, 8
  .insn r 0x2b, 1, 0x42, x0, x1, x31
  mret
.balign 64
fast_trap:
  .insn r 0x2b, 1, 0x03, x0, x1, x31
  .insn b 0x2b, 2, x0, x0, fast_tail
fast_service:
  lw a1, 0(a0)
  jalr a1
  csrrci x0, mstatus, 8
  csrrsi a0, 0x345, 1
  bnez a0, fast_service
fast_tail:
  csrrci x0, mstatus, 8
  .insn r 0x2b, 1, 0x42, x0, x1, x31
  mret

irq_body:
  li t0, 0x10000f00
  lw t1, 4(t0)
  addi t1, t1, 1
  sw t1, 4(t0)
  csrr t1, mcause
  andi t1, t1, 31
  sw t1, 8(t0)
  li t2, 48
1:
  addi t2, t2, -1
  bnez t2, 1b
  ret
shv_trap:
  jal irq_body
  csrrci x0, mstatus, 8
  .insn r 0x2b, 1, 0x42, x0, x1, x31
  mret

.balign 64
standard_trap:
  .insn r 0x2b, 1, 0x02, x0, x1, x31
  csrr t1, mcause
  bltz t1, standard_irq
  li t0, 0x10000f00
  lw t2, 16(t0)
  bne t1, t2, fail
  li t2, 4
  bne t1, t2, 1f
  csrr t1, mtval
  li t2, 0x10000002
  bne t1, t2, fail
1:
  lw t1, 12(t0)
  addi t1, t1, 1
  sw t1, 12(t0)
  # POP restores the saved mepc; advance it after POP using restored t0/t1.
  .insn r 0x2b, 1, 0x42, x0, x1, x31
  csrrw t0, mscratch, t0
  csrr t0, mepc
  addi t0, t0, 4
  csrw mepc, t0
  csrrw t0, mscratch, t0
  mret
standard_irq:
  li t0, 0x10000f00
  lw t1, 24(t0)
  addi t1, t1, 1
  sw t1, 24(t0)
  .insn r 0x2b, 1, 0x42, x0, x1, x31
  mret

.section .rodata, "a", @progbits
.balign 64
vector_table:
  .rept 20
    .word irq_body
  .endr
  .word shv_trap
  .rept 11
    .word irq_body
  .endr
