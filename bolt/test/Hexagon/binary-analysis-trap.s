## Verify that Hexagon trap scanner detects trap0 instructions.

# RUN: llvm-mc -filetype=obj -triple=hexagon-unknown-linux-musl %s -o %t.o
# RUN: ld.lld %t.o -o %t.exe --emit-relocs -e _start
# RUN: llvm-bolt-binary-analysis --scanners=hexagon-trap %t.exe 2>&1 \
# RUN:   | FileCheck %s

# CHECK: trap0(#0xdb)
# CHECK: hexagon-trap scanner found 1 notable instruction(s)

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
  r0 = #42
  trap0(#0xdb)
  .size foo, .-foo
