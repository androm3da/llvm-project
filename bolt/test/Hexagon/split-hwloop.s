## Verify that BOLT does not split a hardware loop setup instruction (loop0)
## away from its target block. When --split-strategy=all is used, every block
## gets its own fragment, but the hardware loop constraint must pin the loop0
## block and its target to the main fragment.

# RUN: llvm-mc -filetype=obj -triple=hexagon-unknown-linux-musl %s -o %t.o
# RUN: ld.lld %t.o -o %t.exe --emit-relocs -e _start
# RUN: llvm-bolt %t.exe -o %t.bolt --split-functions --split-strategy=all \
# RUN:         --print-split --print-only=test_hwloop 2>&1 | FileCheck %s

## The function must be split (proving split-all did run).
# CHECK:   IsSplit     :
# CHECK-SAME: {{ 1$}}
## The loop0 and its target (marked HexLoopEnd) must be in the same fragment
## (no split point between them).
# CHECK:       loop0(
# CHECK-NOT:   HOT-COLD SPLIT POINT
# CHECK:       HexLoopEnd
## There must be at least one split point after the loop body.
# CHECK:       HOT-COLD SPLIT POINT

  .text
  .globl _start
  .type _start,@function
  .p2align 4
_start:
  call test_hwloop
  jumpr r31
  .size _start, .-_start

  .globl test_hwloop
  .type test_hwloop,@function
  .p2align 4
test_hwloop:
  loop0(.Lloop, #4)
.Lloop:
  {
    r0 = add(r0, #1)
    nop
  }:endloop0
  p0 = cmp.eq(r0, #10)
  if (p0) jump .Lskip
  r1 = add(r0, r1)
.Lskip:
  jumpr r31
  .size test_hwloop, .-test_hwloop
