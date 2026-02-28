; RUN: llc -mtriple=hexagon -mcpu=hexagonv68 -mattr=+hvxv68,+hvx-length128b \
; RUN:   -O2 < %s -o - | FileCheck %s
;
; When a function has variable-sized objects and HVX alignment requirements,
; the aligned pointer (AP) register r16 is computed from the frame pointer via
;   r16 = and(r30, #-128)
; Register-allocator spill code may reference AP-relative frame indices that
; are positioned before the AP definition (PS_aligna). After frame-index
; elimination the spill stores use r16 as a base register before it has been
; initialised, causing writes through a garbage address.
;
; Verify that no store uses r16 as a memory base before the AP definition.

; CHECK-LABEL: test_aligned_spill:

; The AP definition must come before any memory op that uses it.
; Between allocframe and the r16 definition, no store may use r16.

; CHECK:      allocframe
; CHECK-NOT:  memw(r16
; CHECK-NOT:  vmem(r16
; CHECK:      r16 = and(r30,#-128)

define void @test_aligned_spill(i32 %a0, i32 %a1, i32 %a2, i32 %a3,
                                 i32 %a4, i32 %a5,
                                 i32 %n, ptr %dst, ptr %src) #0 {
entry:
  ; Variable-length alloca forces AP register usage.
  %vla = alloca i8, i32 %n, align 128

  ; HVX intrinsics force 128-byte stack alignment.
  %v0 = call <32 x i32> @llvm.hexagon.V6.lvsplatw.128B(i32 %a0)
  %v1 = call <32 x i32> @llvm.hexagon.V6.lvsplatw.128B(i32 %a1)
  %v2 = call <32 x i32> @llvm.hexagon.V6.lvsplatw.128B(i32 %a2)
  %v3 = call <32 x i32> @llvm.hexagon.V6.lvsplatw.128B(i32 %a3)

  ; Create register pressure: every parameter survives across a call.
  %x0 = add i32 %a0, 1
  %x1 = add i32 %a1, 2
  %x2 = add i32 %a2, 3
  %x3 = add i32 %a3, 4
  %x4 = add i32 %a4, 5
  %x5 = add i32 %a5, 6
  %x6 = add i32 %n, 7
  %x7 = mul i32 %a0, %a1
  %x8 = mul i32 %a2, %a3
  %x9 = mul i32 %a4, %a5
  %x10 = add i32 %x7, %x8
  %x11 = add i32 %x9, %x10

  ; Store to VLA (uses aligned pointer).
  store i32 %x11, ptr %vla, align 4

  ; HVX vector operations keep vectors alive across the call.
  %v4 = call <32 x i32> @llvm.hexagon.V6.vaddw.128B(<32 x i32> %v0, <32 x i32> %v1)
  %v5 = call <32 x i32> @llvm.hexagon.V6.vaddw.128B(<32 x i32> %v2, <32 x i32> %v3)
  %v6 = call <32 x i32> @llvm.hexagon.V6.vaddw.128B(<32 x i32> %v4, <32 x i32> %v5)

  ; Call forces values into callee-saved registers.
  call void @use_many(i32 %x0, i32 %x1, i32 %x2, i32 %x3, i32 %x4, i32 %x5)

  ; Use values after call.
  store i32 %x0, ptr %dst, align 4
  %p1 = getelementptr i32, ptr %dst, i32 1
  store i32 %x1, ptr %p1, align 4
  %p2 = getelementptr i32, ptr %dst, i32 2
  store i32 %x2, ptr %p2, align 4
  %p3 = getelementptr i32, ptr %dst, i32 3
  store i32 %x3, ptr %p3, align 4
  %p4 = getelementptr i32, ptr %dst, i32 4
  store i32 %x4, ptr %p4, align 4
  %p5 = getelementptr i32, ptr %dst, i32 5
  store i32 %x5, ptr %p5, align 4
  %p6 = getelementptr i32, ptr %dst, i32 6
  store i32 %x6, ptr %p6, align 4
  %p7 = getelementptr i32, ptr %dst, i32 7
  store i32 %x7, ptr %p7, align 4
  %p8 = getelementptr i32, ptr %dst, i32 8
  store i32 %x8, ptr %p8, align 4
  %p9 = getelementptr i32, ptr %dst, i32 9
  store i32 %x9, ptr %p9, align 4
  %p10 = getelementptr i32, ptr %dst, i32 10
  store i32 %x10, ptr %p10, align 4
  %p11 = getelementptr i32, ptr %dst, i32 11
  store i32 %x11, ptr %p11, align 4

  ; Store vector to aligned area.
  store <32 x i32> %v6, ptr %vla, align 128

  ; More calls consuming various live values.
  call void @use_many(i32 %x7, i32 %x8, i32 %x9, i32 %x10, i32 %x11, i32 %n)
  call void @use_many(i32 %x0, i32 %x3, i32 %x5, i32 %x8, i32 %x10, i32 %x11)

  %p12 = getelementptr i32, ptr %dst, i32 12
  store i32 %x0, ptr %p12, align 4
  %p13 = getelementptr i32, ptr %dst, i32 13
  store i32 %x1, ptr %p13, align 4

  ret void
}

declare <32 x i32> @llvm.hexagon.V6.lvsplatw.128B(i32)
declare <32 x i32> @llvm.hexagon.V6.vaddw.128B(<32 x i32>, <32 x i32>)
declare void @use_many(i32, i32, i32, i32, i32, i32)

attributes #0 = { nounwind }
