; RUN: llc -march=hexagon -mcpu=hexagonv68 -mattr=+hvx-length128b -O3 < %s -o /dev/null
;
; Check that extracting a non-HVX predicate subvector (e.g. <4 x i1> from
; <16 x i1>) does not crash. The function extractHvxSubvectorPred assumes
; HVX-native predicate sizes; non-HVX predicates should fall through to
; the default lowering.

target datalayout = "e-m:e-p:32:32:32-a:0-n16:32-i64:64:64-i32:32:32-i16:16:16-i1:8:8-f32:32:32-f64:64:64-v32:32:32-v64:64:64-v512:512:512-v1024:1024:1024-v2048:2048:2048"
target triple = "hexagon-unknown-linux-musl"

define <4 x i1> @extract_non_hvx_pred(<16 x i1> %0) {
entry:
  %1 = shufflevector <16 x i1> %0, <16 x i1> zeroinitializer, <4 x i32> <i32 0, i32 1, i32 2, i32 3>
  ret <4 x i1> %1
}
