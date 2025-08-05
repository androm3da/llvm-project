# REQUIRES: hexagon
# RUN: rm -rf %t && split-file %s %t
# RUN: llvm-mc -filetype=obj -triple=hexagon-unknown-elf %t/a.s -o %t/a.o
# RUN: ld.lld %t/a.o -o %t/a
# RUN: llvm-objdump -d --no-show-raw-insn %t/a | FileCheck %s

## Test that we can handle a single large input section that exceeds the
## branch range. Previously this would error with:
## "InputSection too large for range extension thunk"
## With getThunkSectionSpacing() implemented, thunks are pre-allocated
## and this should link successfully.

#--- a.s
.globl _start
_start:
  ## Call to a function that will be very far away
  call end_func
  jumpr r31

## Create a single large section that exceeds the B22_PCREL range (8MB)
## This fills 9MB to ensure we exceed the range
.fill 0x900000, 4, 0x00000000

.globl end_func
end_func:
  jumpr r31

# CHECK: <__hexagon_thunk_end_func{{.*}}>:
# CHECK: <_start>:
# CHECK-NEXT: call {{.*}} <__hexagon_thunk_end_func
# CHECK: <end_func>: