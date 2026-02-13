# REQUIRES: hexagon
# RUN: rm -rf %t && split-file %s %t
# RUN: llvm-mc -filetype=obj -triple=hexagon-unknown-elf %t/a.s -o %t/a.o
# RUN: llvm-mc -filetype=obj -triple=hexagon-unknown-elf %t/b.s -o %t/b.o

## Test 1: All four R_HEX_GPREL16_* relocations resolve correctly.
## Verify .sdata section, _SDA_BASE_ symbol, and disassembly.
# RUN: ld.lld %t/a.o %t/b.o -o %t/out
# RUN: llvm-readelf -s -S %t/out | FileCheck %s --check-prefix=ELF
# RUN: llvm-objdump --no-print-imm-hex -d -j .text %t/out | FileCheck %s --check-prefix=DIS

## Verify .sdata output section exists.
# ELF:      .sdata PROGBITS

## Verify _SDA_BASE_ is defined.
# ELF:      Symbol table '.symtab'
# ELF-DAG:  {{[0-9a-f]+}} {{.*}} HIDDEN {{.*}} _SDA_BASE_
# ELF-DAG:  {{[0-9a-f]+}} {{.*}} GLOBAL {{.*}} .CONST_00000001
# ELF-DAG:  {{[0-9a-f]+}} {{.*}} GLOBAL {{.*}} .CONST_00000002

## Verify R_HEX_GPREL16_0 (byte), R_HEX_GPREL16_1 (halfword),
## R_HEX_GPREL16_2 (word), and R_HEX_GPREL16_3 (doubleword) resolve.
## The GP-relative offsets should reflect symbol positions within .sdata.
## byte_const at offset 0, half_const at offset 2, word_const (.CONST_00000001)
## at offset 4, dword_const (.CONST_00000002) at offset 8.
# DIS:      <_start>:
# DIS-NEXT: { r0 = memb(gp+#0) }
# DIS-NEXT: { r0 = memh(gp+#2) }
# DIS-NEXT: { r0 = memw(gp+#4) }
# DIS-NEXT: { r1:0 = memd(gp+#8) }

## Test 2: Verify _SDA_BASE_ value equals .sdata section address.
## Both should be the same address since _SDA_BASE_ = start of .sdata.
# RUN: llvm-readelf -s -S %t/out | FileCheck %s --check-prefix=ADDR

## Match .sdata address then verify _SDA_BASE_ has the same value.
## .sdata address appears in the section headers; _SDA_BASE_ in symtab.
# ADDR:      .sdata PROGBITS [[ADDR:[0-9a-f]+]]
# ADDR:      [[ADDR]] {{.*}} _SDA_BASE_

#--- a.s
## Small-data constant pool entries in .gnu.linkonce sections.
## The linker maps .gnu.linkonce.l4.* and .gnu.linkonce.l8.* to .sdata.

## Byte constant (for R_HEX_GPREL16_0 testing).
.section .sdata,"aw",@progbits
.globl byte_const
byte_const:
  .byte 0xAB

## Halfword constant (for R_HEX_GPREL16_1 testing).
.globl half_const
.p2align 1
half_const:
  .half 0xCDEF

## GP-relative 4-byte constant pool entry.
.section .gnu.linkonce.l4..CONST_00000001,"aw",@progbits
.globl .CONST_00000001
.p2align 2
.CONST_00000001:
  .word 0x42280000

## GP-relative 8-byte constant pool entry.
.section .gnu.linkonce.l8..CONST_00000002,"aw",@progbits
.globl .CONST_00000002
.p2align 3
.CONST_00000002:
  .8byte 0x4050000000000000

.section .text,"ax",@progbits
.globl _start
_start:
  ## R_HEX_GPREL16_0: memb(gp+#offset) -- byte load, no shift
  { r0 = memb(gp+#byte_const) }
  ## R_HEX_GPREL16_1: memh(gp+#offset) -- halfword load, shift by 1
  { r0 = memh(gp+#half_const) }
  ## R_HEX_GPREL16_2: memw(gp+#offset) -- word load, shift by 2
  { r0 = memw(gp+#.CONST_00000001) }
  ## R_HEX_GPREL16_3: memd(gp+#offset) -- doubleword load, shift by 3
  { r1:0 = memd(gp+#.CONST_00000002) }

#--- b.s
## Duplicate linkonce sections -- should be deduplicated.
.section .gnu.linkonce.l4..CONST_00000001,"aw",@progbits
.globl .CONST_00000001
.p2align 2
.CONST_00000001:
  .word 0x42280000

.section .gnu.linkonce.l8..CONST_00000002,"aw",@progbits
.globl .CONST_00000002
.p2align 3
.CONST_00000002:
  .8byte 0x4050000000000000
