## Verify that BOLT can fully rewrite a binary containing hardware loop
## instructions (loop0/endloop0). The loop end is encoded in parse bits
## (bits [15:14] = 0x8000) which BOLT tracks via the HexLoopEnd
## annotation and re-encodes through createBundle with LoopBits.

# RUN: llvm-mc -filetype=obj -triple=hexagon-unknown-linux-musl %s -o %t.o
# RUN: ld.lld %t.o -o %t.exe --emit-relocs -e _start
# RUN: llvm-bolt %t.exe -o %t.bolt 2>&1 | FileCheck --check-prefix=BOLT %s
# RUN: llvm-objdump -d %t.bolt | FileCheck %s

# BOLT-NOT: BOLT-ERROR

# CHECK-LABEL: <test_hwloop>:
# CHECK:       loop0(
# CHECK:       :endloop0

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
  jumpr r31
  .size test_hwloop, .-test_hwloop
