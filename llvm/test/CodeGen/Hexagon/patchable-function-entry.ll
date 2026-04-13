;; Test the function attribute "patchable-function-entry".
; RUN: llc -mtriple=hexagon < %s | FileCheck %s

define void @f0() "patchable-function-entry"="0" {
; CHECK-LABEL: f0:
; CHECK-NEXT:  .Lfunc_begin0:
; CHECK-NOT:     nop
; CHECK:         jumpr r31
; CHECK-NOT:   .section __patchable_function_entries
  ret void
}

define void @f1() "patchable-function-entry"="1" {
; CHECK-LABEL: f1:
; CHECK-NEXT:  .Lfunc_begin1:
; CHECK:         nop
; CHECK:         jumpr r31
; CHECK:       .section __patchable_function_entries,"awo",@progbits,f1{{$}}
; CHECK-NEXT:  .p2align 2
; CHECK-NEXT:  .word .Lfunc_begin1
  ret void
}

$f2 = comdat any
define void @f2() "patchable-function-entry"="2" comdat {
; CHECK-LABEL: f2:
; CHECK-NEXT:  .Lfunc_begin2:
; CHECK:         nop
; CHECK:         nop
; CHECK:         jumpr r31
; CHECK:       .section __patchable_function_entries,"awoG",@progbits,f2,f2,comdat{{$}}
; CHECK-NEXT:  .p2align 2
; CHECK-NEXT:  .word .Lfunc_begin2
  ret void
}

;; -fpatchable-function-entry=3,2
;; "patchable-function-prefix" emits NOPs before the function entry label.
define void @f3_2() "patchable-function-entry"="1" "patchable-function-prefix"="2" {
; CHECK-LABEL: .type f3_2,@function
; CHECK-NEXT:  .Ltmp0:
; CHECK:         nop
; CHECK:         nop
; CHECK:       f3_2:
; CHECK:         nop
; CHECK:         jumpr r31
; CHECK:       .Lfunc_end3:
; CHECK-NEXT:  .size f3_2, .Lfunc_end3-f3_2
; CHECK:       .section __patchable_function_entries,"awo",@progbits,f3_2{{$}}
; CHECK-NEXT:  .p2align 2
; CHECK-NEXT:  .word .Ltmp0
  %frame = alloca i8, i32 16
  ret void
}
