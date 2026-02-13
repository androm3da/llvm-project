# REQUIRES: x86
# RUN: rm -rf %t && split-file %s %t
# RUN: llvm-mc -filetype=obj -triple=x86_64 %t/a.s -o %t/a.o

## Test that linker script wildcard patterns correctly match .gnu.linkonce
## sections and place them in the specified output section.

## With a linker script, .gnu.linkonce sections should be matched by
## wildcard patterns like *(.gnu.linkonce.l[a4].*).
# RUN: ld.lld -T %t/script.ld %t/a.o -o %t/out
# RUN: llvm-readelf -S %t/out | FileCheck %s

# CHECK: .sdata{{.*}} PROGBITS {{[0-9a-f]+}} {{[0-9a-f]+}} 000004 00  WA

## Also test a broader wildcard that matches multiple linkonce types.
# RUN: ld.lld -T %t/script2.ld %t/a.o -o %t/out2
# RUN: llvm-readelf -S %t/out2 | FileCheck --check-prefix=MULTI %s

# MULTI-DAG: .mytext{{.*}} PROGBITS
# MULTI-DAG: .mydata{{.*}} PROGBITS

#--- a.s
.globl _start
_start:
  ret

.section .gnu.linkonce.l4.CONST_0000FFFC,"aw",@progbits
  .long 10

.section .gnu.linkonce.t.myfunc,"ax",@progbits
.globl myfunc
myfunc:
  ret

.section .gnu.linkonce.d.myvar,"aw",@progbits
.globl myvar
myvar:
  .long 42

#--- script.ld
SECTIONS {
  .sdata : { *(.gnu.linkonce.l[a4].*) }
  .text : { *(.text) *(.text.*) *(.gnu.linkonce.t.*) }
  .data : { *(.data) *(.data.*) *(.gnu.linkonce.d.*) }
}

#--- script2.ld
SECTIONS {
  .mytext : { *(.text) *(.text.*) *(.gnu.linkonce.t.*) }
  .mydata : { *(.data) *(.data.*) *(.gnu.linkonce.d.*) *(.gnu.linkonce.l[a4].*) }
}
