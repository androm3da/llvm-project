; RUN: llc --mtriple=hexagon -O2 -mattr=+hvxv79,+hvx-length128b %s -o - \
; RUN:   | FileCheck %s
;
; Bug: The custom inserter generates a 32-iteration hardware loop to bit-
; transpose a predicate into 32-bit words, extract the LSBs, and convert
; back to a predicate.  This is a round-trip that accomplishes nothing:
; the result of V6_veqsf + V6_pred_not already IS the correct v32i1
; predicate.  The entire operation should be ~3 HVX instructions with
; no loop.
;
; For comparison, the semantically equivalent `fcmp une %x, zeroinitializer`
; generates loop-free code today (see fcmp_baseline below).

define <16 x i1> @fptoui_v32f32_to_v32i1(<16 x float> %src) {
entry:
  %pred = fptoui <16 x float> %src to <16 x i1>
  ret <16 x i1> %pred
}

; The fptoui path must not contain a hardware loop.
; CHECK-LABEL: fptoui_v32f32_to_v32i1:
; CHECK-NOT:   loop0(

define <16 x i1> @fptosi_v32f32_to_v32i1(<16 x float> %src) {
entry:
  %pred = fptosi <16 x float> %src to <16 x i1>
  ret <16 x i1> %pred
}

; Same for the fptosi path.
; CHECK-LABEL: fptosi_v32f32_to_v32i1:
; CHECK-NOT:   loop0(

; Baseline: fcmp une is semantically equivalent for fp-to-i1 and has
; no loop today.  This function must keep passing to guard against
; regressions.
define <16 x i1> @fcmp_baseline(<16 x float> %src) {
entry:
  %pred = fcmp une <16 x float> %src, zeroinitializer
  ret <16 x i1> %pred
}

; CHECK-LABEL: fcmp_baseline:
; CHECK-NOT:   loop0(
