; RUN: llc -march=hexagon -mcpu=hexagonv68 -mattr=+hvx-length128b -O3 < %s -o /dev/null
;
; Check that createHvxPrefixPred correctly splits the i64 P2D result into
; i32 halves when Bytes == BitBytes (e.g. v2i1 with BitBytes == 4).
; Previously the i64 was passed directly to VINSERTW0 which expects i32,
; triggering a BitTracker assertion (WD >= WS).

target datalayout = "e-m:e-p:32:32:32-a:0-n16:32-i64:64:64-i32:32:32-i16:16:16-i1:8:8-f32:32:32-f64:64:64-v32:32:32-v64:64:64-v512:512:512-v1024:1024:1024-v2048:2048:2048"
target triple = "hexagon-unknown-linux-musl"

define i16 @prefix_pred_split(<8 x i32> %0) {
entry:
  %1 = icmp eq <8 x i32> %0, zeroinitializer
  %2 = shufflevector <8 x i1> %1, <8 x i1> zeroinitializer, <16 x i32> <i32 0, i32 1, i32 2, i32 3, i32 4, i32 5, i32 6, i32 7, i32 8, i32 9, i32 10, i32 11, i32 12, i32 13, i32 14, i32 15>
  %3 = bitcast <16 x i1> %2 to i16
  %4 = call i16 @llvm.ctpop.i16(i16 %3)
  ret i16 %4
}

declare i16 @llvm.ctpop.i16(i16) #0

attributes #0 = { nocallback nocreateundeforpoison nofree nosync nounwind speculatable willreturn memory(none) }
