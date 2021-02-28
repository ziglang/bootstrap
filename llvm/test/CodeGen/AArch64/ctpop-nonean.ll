; NOTE: Assertions have been autogenerated by utils/update_llc_test_checks.py
; RUN: llc -mtriple=aarch64-none-linux-gnu -mattr=-neon < %s | FileCheck %s

declare i128 @llvm.ctpop.i128(i128)

define i128 @ctpop_i128(i128 %i) {
; CHECK-LABEL: ctpop_i128:
; CHECK:       // %bb.0:
; CHECK-NEXT:    lsr x8, x1, #1
; CHECK-NEXT:    and x8, x8, #0x5555555555555555
; CHECK-NEXT:    sub x8, x1, x8
; CHECK-NEXT:    lsr x10, x0, #1
; CHECK-NEXT:    and x10, x10, #0x5555555555555555
; CHECK-NEXT:    and x11, x8, #0x3333333333333333
; CHECK-NEXT:    lsr x8, x8, #2
; CHECK-NEXT:    sub x10, x0, x10
; CHECK-NEXT:    and x8, x8, #0x3333333333333333
; CHECK-NEXT:    add x8, x11, x8
; CHECK-NEXT:    and x11, x10, #0x3333333333333333
; CHECK-NEXT:    lsr x10, x10, #2
; CHECK-NEXT:    and x10, x10, #0x3333333333333333
; CHECK-NEXT:    add x10, x11, x10
; CHECK-NEXT:    add x8, x8, x8, lsr #4
; CHECK-NEXT:    add x10, x10, x10, lsr #4
; CHECK-NEXT:    mov x9, #72340172838076673
; CHECK-NEXT:    and x8, x8, #0xf0f0f0f0f0f0f0f
; CHECK-NEXT:    and x10, x10, #0xf0f0f0f0f0f0f0f
; CHECK-NEXT:    mul x8, x8, x9
; CHECK-NEXT:    mul x9, x10, x9
; CHECK-NEXT:    lsr x9, x9, #56
; CHECK-NEXT:    add x0, x9, x8, lsr #56
; CHECK-NEXT:    mov x1, xzr
; CHECK-NEXT:    ret
  %c = call i128 @llvm.ctpop.i128(i128 %i)
  ret i128 %c
}
