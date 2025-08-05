# REQUIRES: hexagon
# RUN: rm -rf %t && split-file %s %t
# RUN: llvm-mc -filetype=obj -triple=hexagon-unknown-elf %t/a.s -o %t/a.o
# RUN: ld.lld -T %t/lds %t/a.o -o %t/a
# RUN: llvm-readelf -S %t/a | FileCheck %s --check-prefix=SEC
# RUN: llvm-objdump -d --no-show-raw-insn %t/a | FileCheck %s

## Test that Hexagon's getThunkSectionSpacing() properly handles large sections.
## Previously, without thunk section spacing, large sections would cause
## "InputSection too large for range extension thunk" errors.
## With spacing of ~7.9MB, we should see pre-created thunk sections.

#--- a.s
.section .text.start, "ax", %progbits
.globl _start
_start:
  call far_func
  jumpr r31

## Create a large section that would exceed branch range without thunk spacing
.section .text.large, "ax", %progbits
.fill 0x700000, 4, 0x00000000  ## Fill 7MB with nops

.section .text.middle, "ax", %progbits
middle_func:
  call far_func
  jumpr r31

## Another large section
.section .text.large2, "ax", %progbits
.fill 0x700000, 4, 0x00000000  ## Fill another 7MB

.section .text.end, "ax", %progbits
.globl far_func
far_func:
  jumpr r31

# SEC: .text.thunk PROGBITS
# SEC: .text.thunk PROGBITS

# CHECK: <__hexagon_thunk_far_func{{.*}}>:
# CHECK: <_start>:
# CHECK-NEXT: call {{.*}} <__hexagon_thunk_far_func
# CHECK: <middle_func>:
# CHECK-NEXT: call {{.*}} <__hexagon_thunk_far_func
# CHECK: <far_func>:
# CHECK-NEXT: jumpr r31

#--- lds
SECTIONS {
  . = 0x200000;
  .text : {
    *(.text.start)
    *(.text.large)
    *(.text.middle)
    *(.text.large2)
    *(.text.end)
  }
}
