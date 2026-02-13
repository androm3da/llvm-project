# REQUIRES: x86
# RUN: rm -rf %t && split-file %s %t
# RUN: llvm-mc -filetype=obj -triple=x86_64 %t/a.s -o %t/a.o
# RUN: llvm-mc -filetype=obj -triple=x86_64 %t/b.s -o %t/b.o
# RUN: llvm-mc -filetype=obj -triple=x86_64 %t/comdat.s -o %t/comdat.o
# RUN: llvm-mc -filetype=obj -triple=x86_64 %t/caller.s -o %t/caller.o
# RUN: llvm-mc -filetype=obj -triple=x86_64 %t/b-only-sym.s -o %t/b-only-sym.o
# RUN: llvm-mc -filetype=obj -triple=x86_64 %t/ref-only-sym.s -o %t/ref-only-sym.o
# RUN: llvm-mc -filetype=obj -triple=x86_64 %t/mixed.s -o %t/mixed.o
# RUN: llvm-mc -filetype=obj -triple=x86_64 %t/nonstandard-a.s -o %t/nonstandard-a.o
# RUN: llvm-mc -filetype=obj -triple=x86_64 %t/nonstandard-b.s -o %t/nonstandard-b.o

## Test .gnu.linkonce deduplication: two objects with the same
## .gnu.linkonce.t.foo -- only the first is kept, no duplicate error.
# RUN: ld.lld %t/a.o %t/b.o -o %t/out
# RUN: llvm-objdump -d %t/out | FileCheck --check-prefix=DEDUP %s
# DEDUP:      <foo>:
# DEDUP-NEXT:  movl $0x1, %eax
# DEDUP-NOT:   movl $0x2, %eax

## Test output section mapping: .gnu.linkonce.TYPE.* maps to the
## corresponding standard output section.
# RUN: llvm-readelf -S %t/out | FileCheck --check-prefix=SECTIONS %s
# SECTIONS-DAG: .text{{[ \t]}}
# SECTIONS-DAG: .data{{[ \t]}}
# SECTIONS-DAG: .rodata{{[ \t]}}
# SECTIONS-DAG: .bss{{[ \t]}}
# SECTIONS-DAG: .sdata{{[ \t]}}
# SECTIONS-DAG: .data.rel.ro{{[ \t]}}
# SECTIONS-DAG: .tdata{{[ \t]}}
# SECTIONS-DAG: .tbss{{[ \t]}}

## Test COMDAT interop: .gnu.linkonce.t.bar deduplicates against
## a COMDAT group with signature "bar".
# RUN: ld.lld %t/a.o %t/comdat.o -o %t/out2
# RUN: llvm-objdump -d %t/out2 | FileCheck --check-prefix=COMDAT %s
# COMDAT:      <bar>:
# COMDAT-NEXT:  movl $0xa, %eax
# COMDAT-NOT:   movl $0x14, %eax

## Reverse order: COMDAT first, then .gnu.linkonce -- COMDAT wins.
# RUN: ld.lld %t/comdat.o %t/a.o -o %t/out3
# RUN: llvm-objdump -d %t/out3 | FileCheck --check-prefix=COMDAT-REV %s
# COMDAT-REV:      <bar>:
# COMDAT-REV-NEXT:  movl $0x14, %eax
# COMDAT-REV-NOT:   movl $0xa, %eax

## A reference from a live section to a symbol in a kept .gnu.linkonce section
## resolves normally.
# RUN: ld.lld %t/a.o %t/b.o %t/caller.o -o %t/out4
# RUN: llvm-objdump -d %t/out4 | FileCheck --check-prefix=KEPT %s
# KEPT:      <_start>:
# KEPT:       callq {{.*}} <foo>
# KEPT:      <foo>:
# KEPT-NEXT:  movl $0x1, %eax

## A symbol defined only in the discarded copy (absent from the kept copy) is
## an error.
# RUN: not ld.lld --threads=1 %t/a.o %t/b-only-sym.o %t/ref-only-sym.o -o /dev/null 2>&1 \
# RUN:   | FileCheck --check-prefix=ERR %s
# ERR: error: relocation refers to a symbol in a discarded section: bar_only_in_b

## A section-relative relocation from a non-debug allocatable section to a
## discarded .gnu.linkonce section produces a warning under -r.
# RUN: ld.lld -r --threads=1 %t/a.o %t/mixed.o -o /dev/null 2>&1 \
# RUN:   | FileCheck --check-prefix=WARN %s
# WARN: warning: relocation refers to a discarded section: .gnu.linkonce.t.foo

## Non-standard .gnu.linkonce names (no TYPE.NAME pattern) are not deduplicated
## but link without errors; both sections and symbols appear in the output.
# RUN: ld.lld %t/a.o %t/nonstandard-a.o %t/nonstandard-b.o -o %t/out5
# RUN: llvm-readelf -S %t/out5 | FileCheck --check-prefix=NONSTD-SEC %s
# RUN: llvm-readelf -s %t/out5 | FileCheck --check-prefix=NONSTD-SYM %s
# NONSTD-SEC-DAG: .gnu.linkonce.irq_vector_table
# NONSTD-SEC-DAG: .gnu.linkonce.sw_isr_table
# NONSTD-SYM-DAG: {{.*}} GLOBAL {{.*}} irq_sym
# NONSTD-SYM-DAG: {{.*}} GLOBAL {{.*}} sw_sym

#--- a.s
.section .gnu.linkonce.t.foo,"ax",@progbits
.globl foo
foo:
  movl $1, %eax
  ret

.section .gnu.linkonce.t.bar,"ax",@progbits
.globl bar
bar:
  movl $10, %eax
  ret

.section .gnu.linkonce.d.mydata,"aw",@progbits
.globl mydata
mydata:
  .long 42

.section .gnu.linkonce.ro.myrodata,"a",@progbits
.globl myrodata
myrodata:
  .long 99

.section .gnu.linkonce.b.mybss,"aw",@nobits
.globl mybss
mybss:
  .long 0

.section .gnu.linkonce.s.mysdata,"aw",@progbits
.globl mysdata
mysdata:
  .long 7

.section .gnu.linkonce.d.rel.ro.myrelro,"aw",@progbits
.globl myrelro
myrelro:
  .long 55

.section .gnu.linkonce.td.mytdata,"awT",@progbits
.globl mytdata
mytdata:
  .long 1

.section .gnu.linkonce.tb.mytbss,"awT",@nobits
.globl mytbss
mytbss:
  .long 0

.globl _start
.text
_start:
  call foo
  call bar

#--- b.s
.section .gnu.linkonce.t.foo,"ax",@progbits
.globl foo
foo:
  movl $2, %eax
  ret

#--- comdat.s
.section .text.bar,"axG",@progbits,bar,comdat
.globl bar
bar:
  movl $20, %eax
  ret

#--- caller.s
## A separate object that calls foo; should resolve to the kept definition.
.text
.globl caller
caller:
  call foo

#--- b-only-sym.s
## Discarded copy that also defines bar_only_in_b, which is absent from a.s.
.section .gnu.linkonce.t.foo,"ax",@progbits
.globl foo
foo:
  movl $2, %eax
  ret
.globl bar_only_in_b
bar_only_in_b:
  movl $3, %eax
  ret

#--- ref-only-sym.s
## References bar_only_in_b, which lives only in the discarded linkonce copy.
.text
.globl ref_bar
ref_bar:
  call bar_only_in_b

#--- mixed.s
## Contains both a .gnu.linkonce.t.foo copy (discarded when linked with a.o)
## and a non-debug allocatable section with a section-relative relocation into
## it.  Under -r this triggers the "relocation refers to a discarded section"
## warning, mirroring the COMDAT behaviour tested in comdat-discarded-reloc.s.
.section .gnu.linkonce.t.foo,"ax",@progbits
.globl foo
foo:
  movl $2, %eax
  ret

.section .data.ref,"aw",@progbits
  .quad .gnu.linkonce.t.foo

#--- nonstandard-a.s
.section .gnu.linkonce.irq_vector_table,"aw",@progbits
.globl irq_sym
irq_sym:
  .long 100

#--- nonstandard-b.s
.section .gnu.linkonce.sw_isr_table,"aw",@progbits
.globl sw_sym
sw_sym:
  .long 100
