# REQUIRES: hexagon
# RUN: rm -rf %t && split-file %s %t
# RUN: llvm-mc -filetype=obj -triple=hexagon-unknown-elf %t/a.s -o %t/a.o

## Verify that .gnu.linkonce.l4.*, .gnu.linkonce.l8.*, and
## .gnu.linkonce.la.* sections all map to .sdata output section.
## This mirrors what the Hexagon compiler emits for constant pools:
## l4 = 4-byte literal, l8 = 8-byte literal, la = address literal.
## (ported from eld test: Hexagon/standalone/linkerscript/MatchRegEx)
# RUN: ld.lld %t/a.o -o %t/out
# RUN: llvm-readelf -S -s %t/out | FileCheck %s

## All three linkonce literal sections should be merged into .sdata.
# CHECK:      .sdata PROGBITS

## Verify symbols from all three section types are present.
# CHECK:      Symbol table '.symtab'
# CHECK-DAG:  {{[0-9a-f]+}} {{.*}} GLOBAL {{.*}} l4_const
# CHECK-DAG:  {{[0-9a-f]+}} {{.*}} GLOBAL {{.*}} l8_const
# CHECK-DAG:  {{[0-9a-f]+}} {{.*}} GLOBAL {{.*}} la_const

## There should be no separate .gnu.linkonce.l[48a] output sections.
# CHECK-NOT:  .gnu.linkonce.l

#--- a.s
## .gnu.linkonce.l4.* -- 4-byte constant pool entry.
.section .gnu.linkonce.l4.CONST_0000FFFC,"aw",@progbits
.globl l4_const
.p2align 2
l4_const:
  .word 10

## .gnu.linkonce.l8.* -- 8-byte constant pool entry.
.section .gnu.linkonce.l8.CONST_0000FFFD,"aw",@progbits
.globl l8_const
.p2align 3
l8_const:
  .8byte 20

## .gnu.linkonce.la.* -- address-sized constant pool entry.
.section .gnu.linkonce.la.CONST_0000FFFE,"aw",@progbits
.globl la_const
.p2align 2
la_const:
  .word 30

.section .text,"ax",@progbits
.globl _start
_start:
  nop
