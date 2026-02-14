; RUN: llc -march=hexagon -mcpu=hexagonv68 -mattr=+hvxv68,+hvx-length128b < %s -o /dev/null
;
; Check that widening a zext/sext that would produce a result type exceeding
; HVX pair width (e.g. v128i32 from v128i8) does not crash. The TL_EXTEND
; step-by-step expansion must stay within legal type widths.

target datalayout = "e-m:e-p:32:32:32-a:0-n16:32-i64:64:64-i32:32:32-i16:16:16-i1:8:8-f32:32:32-f64:64:64-v32:32:32-v64:64:64-v512:512:512-v1024:1024:1024-v2048:2048:2048"
target triple = "hexagon-unknown-linux-musl"

define fastcc <16 x i32> @widen_extend_split(<16 x i8> %a, <16 x i8> %b, <16 x i8> %c) {
entry:
  %0 = zext <16 x i8> %a to <16 x i32>
  %1 = zext <16 x i8> %b to <16 x i32>
  %2 = or <16 x i32> %0, %1
  %3 = zext <16 x i8> %c to <16 x i32>
  %4 = or <16 x i32> %2, %3
  ret <16 x i32> %4
}
