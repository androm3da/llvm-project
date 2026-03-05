; RUN: llc --mtriple=hexagon -O2 -mattr=+hvxv79,+hvx-length128b \
; RUN:   -stop-after=finalize-isel %s -o - | FileCheck %s
;
; In the MIR below, bb.1 (the continuation / return block) should NOT list
; itself as a successor.
;
;   bb.1.entry:
;     successors: %bb.1(0x80000000)
;
; After the fix, bb.1 should have NO successors (it is the return block).

define <16 x i1> @fptoui_self_loop(<16 x float> %src) {
entry:
  %pred = fptoui <16 x float> %src to <16 x i1>
  ret <16 x i1> %pred
}

; The return block (bb.1) must not be a successor of itself.
; CHECK-LABEL: name: fptoui_self_loop
; CHECK:       bb.1.entry:
; CHECK-NOT:   successors:
; CHECK:       PS_jmpret
