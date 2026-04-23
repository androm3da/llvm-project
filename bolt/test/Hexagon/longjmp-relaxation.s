## Verify that BOLT enables branch relaxation for Hexagon. The LongJmpPass
## should run using the compact code model path (relaxLocalBranches), which
## handles per-fragment branch relaxation using trampolines.

# RUN: llvm-mc -filetype=obj -triple=hexagon-unknown-linux-musl %s -o %t.o
# RUN: ld.lld %t.o -o %t.exe --emit-relocs -e _start
# RUN: llvm-bolt %t.exe -o %t.bolt 2>&1 | FileCheck %s
# RUN: llvm-objdump -d %t.bolt | FileCheck --check-prefix=DISASM %s

# CHECK: BOLT-INFO: relaxing branches for compact code model (<128MB)

# DISASM-LABEL: <test_branch>:
# DISASM:       jump
# DISASM:       jumpr r31

  .text
  .globl _start
  .type _start,@function
  .p2align 4
_start:
  call test_branch
  jumpr r31
  .size _start, .-_start

  .globl test_branch
  .type test_branch,@function
  .p2align 4
test_branch:
  p0 = cmp.eq(r0, #0)
  if (p0) jump .Ltarget
  r0 = add(r0, #1)
.Ltarget:
  jumpr r31
  .size test_branch, .-test_branch
