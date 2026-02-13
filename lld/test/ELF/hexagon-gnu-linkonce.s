# REQUIRES: hexagon
# RUN: rm -rf %t && split-file %s %t
# RUN: llvm-mc -filetype=obj -triple=hexagon-unknown-elf %t/a.s -o %t/a.o
# RUN: llvm-mc -filetype=obj -triple=hexagon-unknown-elf %t/b.s -o %t/b.o

## Hexagon's compiler emits small-data constants into .gnu.linkonce.l8.*
## sections with global symbols. Verify deduplication and no duplicate
## symbol errors.
# RUN: ld.lld %t/a.o %t/b.o -o %t/out
# RUN: llvm-readelf -s %t/out | FileCheck %s

# CHECK:     Symbol table '.symtab'
# CHECK-DAG: {{.*}} GLOBAL {{.*}} .CONST_00000001
# CHECK-DAG: {{.*}} GLOBAL {{.*}} .CONST_00000002

#--- a.s
.section .gnu.linkonce.l8..CONST_00000001,"a",@progbits
.globl .CONST_00000001
.CONST_00000001:
  .8byte 1

.section .gnu.linkonce.l8..CONST_00000002,"a",@progbits
.globl .CONST_00000002
.CONST_00000002:
  .8byte 2

.globl _start
_start:
  nop

#--- b.s
.section .gnu.linkonce.l8..CONST_00000001,"a",@progbits
.globl .CONST_00000001
.CONST_00000001:
  .8byte 1

.section .gnu.linkonce.l8..CONST_00000002,"a",@progbits
.globl .CONST_00000002
.CONST_00000002:
  .8byte 2
