; RUN: llc --mtriple=hexagon -O2 -mattr=+hvxv79,+hvx-length128b \
; RUN:   -verify-machineinstrs %s -o /dev/null

define void @fptoui_in_loop(ptr %src, ptr %dst, i32 %n) {
entry:
  br label %loop

loop:
  %iv = phi i32 [ 0, %entry ], [ %iv.next, %loop ]
  %gep.src = getelementptr inbounds <16 x float>, ptr %src, i32 %iv
  %vec = load <16 x float>, ptr %gep.src, align 128
  %pred = fptoui <16 x float> %vec to <16 x i1>
  %ext = sext <16 x i1> %pred to <16 x i32>
  %gep.dst = getelementptr inbounds <16 x i32>, ptr %dst, i32 %iv
  store <16 x i32> %ext, ptr %gep.dst, align 128
  %iv.next = add nuw i32 %iv, 1
  %cmp = icmp ult i32 %iv.next, %n
  br i1 %cmp, label %loop, label %exit

exit:
  ret void
}
