## Verify that Hexagon binary analysis produces function statistics.

# RUN: llvm-mc -filetype=obj -triple=hexagon-unknown-linux-musl %s -o %t.o
# RUN: ld.lld %t.o -o %t.exe --emit-relocs -e _start
# RUN: llvm-bolt-binary-analysis --scanners=hexagon-stats %t.exe 2>&1 \
# RUN:   | FileCheck %s

# CHECK: Hexagon Binary Statistics
# CHECK: Functions total: 2
# CHECK: with CFG: 2
# CHECK: Total instructions: 4

  .text
  .globl _start
  .type _start,@function
  .p2align 4
_start:
  call foo
  jumpr r31
  .size _start, .-_start

  .globl foo
  .type foo,@function
  .p2align 4
foo:
  r0 = #0
  jumpr r31
  .size foo, .-foo
