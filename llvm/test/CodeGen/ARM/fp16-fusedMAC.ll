; NOTE: Assertions have been autogenerated by utils/update_llc_test_checks.py
; RUN: llc < %s -mtriple=thumbv8.1-m-none-eabi -mattr=+fullfp16 -fp-contract=fast | FileCheck %s
; RUN: llc < %s -mtriple=thumbv8.1-m-none-eabi -mattr=+fullfp16,+slowfpvfmx -fp-contract=fast | FileCheck %s -check-prefix=DONT-FUSE

; Check generated fp16 fused MAC and MLS.

define arm_aapcs_vfpcc void @fusedMACTest2(half *%a1, half *%a2, half *%a3) {
; CHECK-LABEL: fusedMACTest2:
; CHECK:       @ %bb.0:
; CHECK-NEXT:    vldr.16 s0, [r1]
; CHECK-NEXT:    vldr.16 s2, [r0]
; CHECK-NEXT:    vldr.16 s4, [r2]
; CHECK-NEXT:    vfma.f16 s4, s2, s0
; CHECK-NEXT:    vstr.16 s4, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: fusedMACTest2:
; DONT-FUSE:       @ %bb.0:
; DONT-FUSE-NEXT:    vldr.16 s0, [r1]
; DONT-FUSE-NEXT:    vldr.16 s2, [r0]
; DONT-FUSE-NEXT:    vmul.f16 s0, s2, s0
; DONT-FUSE-NEXT:    vldr.16 s2, [r2]
; DONT-FUSE-NEXT:    vadd.f16 s0, s0, s2
; DONT-FUSE-NEXT:    vstr.16 s0, [r0]
; DONT-FUSE-NEXT:    bx lr

  %f1 = load half, half *%a1, align 2
  %f2 = load half, half *%a2, align 2
  %f3 = load half, half *%a3, align 2
  %1 = fmul half %f1, %f2
  %2 = fadd half %1, %f3
  store half %2, half *%a1, align 2
  ret void
}

define arm_aapcs_vfpcc void @fusedMACTest4(half *%a1, half *%a2, half *%a3) {
; CHECK-LABEL: fusedMACTest4:
; CHECK:       @ %bb.0:
; CHECK-NEXT:    vldr.16 s0, [r2]
; CHECK-NEXT:    vldr.16 s2, [r1]
; CHECK-NEXT:    vldr.16 s4, [r0]
; CHECK-NEXT:    vfms.f16 s4, s2, s0
; CHECK-NEXT:    vstr.16 s4, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: fusedMACTest4:
; DONT-FUSE:       @ %bb.0:
; DONT-FUSE-NEXT:    vldr.16 s0, [r2]
; DONT-FUSE-NEXT:    vldr.16 s2, [r1]
; DONT-FUSE-NEXT:    vmul.f16 s0, s2, s0
; DONT-FUSE-NEXT:    vldr.16 s2, [r0]
; DONT-FUSE-NEXT:    vsub.f16 s0, s2, s0
; DONT-FUSE-NEXT:    vstr.16 s0, [r0]
; DONT-FUSE-NEXT:    bx lr

  %f1 = load half, half *%a1, align 2
  %f2 = load half, half *%a2, align 2
  %f3 = load half, half *%a3, align 2
  %1 = fmul half %f2, %f3
  %2 = fsub half %f1, %1
  store half %2, half *%a1, align 2
  ret void
}

define arm_aapcs_vfpcc void @fusedMACTest6(half *%a1, half *%a2, half *%a3) {
; CHECK-LABEL: fusedMACTest6:
; CHECK:       @ %bb.0:
; CHECK-NEXT:    vldr.16 s0, [r1]
; CHECK-NEXT:    vldr.16 s2, [r0]
; CHECK-NEXT:    vldr.16 s4, [r2]
; CHECK-NEXT:    vfnma.f16 s4, s2, s0
; CHECK-NEXT:    vstr.16 s4, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: fusedMACTest6:
; DONT-FUSE:       @ %bb.0:
; DONT-FUSE-NEXT:    vldr.16 s0, [r1]
; DONT-FUSE-NEXT:    vldr.16 s2, [r0]
; DONT-FUSE-NEXT:    vnmul.f16 s0, s2, s0
; DONT-FUSE-NEXT:    vldr.16 s2, [r2]
; DONT-FUSE-NEXT:    vsub.f16 s0, s0, s2
; DONT-FUSE-NEXT:    vstr.16 s0, [r0]
; DONT-FUSE-NEXT:    bx lr

  %f1 = load half, half *%a1, align 2
  %f2 = load half, half *%a2, align 2
  %f3 = load half, half *%a3, align 2
  %1 = fmul half %f1, %f2
  %2 = fsub half -0.0, %1
  %3 = fsub half %2, %f3
  store half %3, half *%a1, align 2
  ret void
}

define arm_aapcs_vfpcc void @fusedMACTest8(half *%a1, half *%a2, half *%a3) {
; CHECK-LABEL: fusedMACTest8:
; CHECK:       @ %bb.0:
; CHECK-NEXT:    vldr.16 s0, [r1]
; CHECK-NEXT:    vldr.16 s2, [r0]
; CHECK-NEXT:    vldr.16 s4, [r2]
; CHECK-NEXT:    vfnms.f16 s4, s2, s0
; CHECK-NEXT:    vstr.16 s4, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: fusedMACTest8:
; DONT-FUSE:       @ %bb.0:
; DONT-FUSE-NEXT:    vldr.16 s0, [r1]
; DONT-FUSE-NEXT:    vldr.16 s2, [r0]
; DONT-FUSE-NEXT:    vmul.f16 s0, s2, s0
; DONT-FUSE-NEXT:    vldr.16 s2, [r2]
; DONT-FUSE-NEXT:    vsub.f16 s0, s0, s2
; DONT-FUSE-NEXT:    vstr.16 s0, [r0]
; DONT-FUSE-NEXT:    bx lr

  %f1 = load half, half *%a1, align 2
  %f2 = load half, half *%a2, align 2
  %f3 = load half, half *%a3, align 2
  %1 = fmul half %f1, %f2
  %2 = fsub half %1, %f3
  store half %2, half *%a1, align 2
  ret void
}

define arm_aapcs_vfpcc void @test_fma_f16(half *%aa, half *%bb, half *%cc) nounwind readnone ssp {
; CHECK-LABEL: test_fma_f16:
; CHECK:       @ %bb.0: @ %entry
; CHECK-NEXT:    vldr.16 s0, [r1]
; CHECK-NEXT:    vldr.16 s2, [r0]
; CHECK-NEXT:    vldr.16 s4, [r2]
; CHECK-NEXT:    vfma.f16 s4, s2, s0
; CHECK-NEXT:    vstr.16 s4, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: test_fma_f16:
; DONT-FUSE:       @ %bb.0: @ %entry
; DONT-FUSE-NEXT:    vldr.16 s0, [r1]
; DONT-FUSE-NEXT:    vldr.16 s2, [r0]
; DONT-FUSE-NEXT:    vldr.16 s4, [r2]
; DONT-FUSE-NEXT:    vfma.f16 s4, s2, s0
; DONT-FUSE-NEXT:    vstr.16 s4, [r0]
; DONT-FUSE-NEXT:    bx lr
entry:
  %a = load half, half *%aa, align 2
  %b = load half, half *%bb, align 2
  %c = load half, half *%cc, align 2
  %tmp1 = tail call half @llvm.fma.f16(half %a, half %b, half %c) nounwind readnone
  store half %tmp1, half *%aa, align 2
  ret void
}

define arm_aapcs_vfpcc void @test_fnms_f16(half *%aa, half *%bb, half *%cc) nounwind readnone ssp {
; CHECK-LABEL: test_fnms_f16:
; CHECK:       @ %bb.0:
; CHECK-NEXT:    vldr.16 s0, [r1]
; CHECK-NEXT:    vldr.16 s2, [r0]
; CHECK-NEXT:    vldr.16 s4, [r2]
; CHECK-NEXT:    vfma.f16 s4, s2, s0
; CHECK-NEXT:    vstr.16 s4, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: test_fnms_f16:
; DONT-FUSE:       @ %bb.0:
; DONT-FUSE-NEXT:    vldr.16 s0, [r1]
; DONT-FUSE-NEXT:    vldr.16 s2, [r0]
; DONT-FUSE-NEXT:    vldr.16 s4, [r2]
; DONT-FUSE-NEXT:    vfma.f16 s4, s2, s0
; DONT-FUSE-NEXT:    vstr.16 s4, [r0]
; DONT-FUSE-NEXT:    bx lr

  %a = load half, half *%aa, align 2
  %b = load half, half *%bb, align 2
  %c = load half, half *%cc, align 2
  %tmp2 = fsub half -0.0, %c
  %tmp3 = tail call half @llvm.fma.f16(half %a, half %b, half %c) nounwind readnone
  store half %tmp3, half *%aa, align 2
  ret void
}

define arm_aapcs_vfpcc void @test_fma_const_fold(half *%aa, half *%bb) nounwind {
; CHECK-LABEL: test_fma_const_fold:
; CHECK:       @ %bb.0:
; CHECK-NEXT:    vldr.16 s0, [r1]
; CHECK-NEXT:    vldr.16 s2, [r0]
; CHECK-NEXT:    vadd.f16 s0, s2, s0
; CHECK-NEXT:    vstr.16 s0, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: test_fma_const_fold:
; DONT-FUSE:       @ %bb.0:
; DONT-FUSE-NEXT:    vldr.16 s0, [r1]
; DONT-FUSE-NEXT:    vldr.16 s2, [r0]
; DONT-FUSE-NEXT:    vadd.f16 s0, s2, s0
; DONT-FUSE-NEXT:    vstr.16 s0, [r0]
; DONT-FUSE-NEXT:    bx lr

  %a = load half, half *%aa, align 2
  %b = load half, half *%bb, align 2
  %ret = call half @llvm.fma.f16(half %a, half 1.0, half %b)
  store half %ret, half *%aa, align 2
  ret void
}

define arm_aapcs_vfpcc void @test_fma_canonicalize(half *%aa, half *%bb) nounwind {
; CHECK-LABEL: test_fma_canonicalize:
; CHECK:       @ %bb.0:
; CHECK-NEXT:    vldr.16 s0, [r0]
; CHECK-NEXT:    vldr.16 s2, [r1]
; CHECK-NEXT:    vmov.f16 s4, #2.000000e+00
; CHECK-NEXT:    vfma.f16 s2, s0, s4
; CHECK-NEXT:    vstr.16 s2, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: test_fma_canonicalize:
; DONT-FUSE:       @ %bb.0:
; DONT-FUSE-NEXT:    vldr.16 s0, [r0]
; DONT-FUSE-NEXT:    vldr.16 s2, [r1]
; DONT-FUSE-NEXT:    vmov.f16 s4, #2.000000e+00
; DONT-FUSE-NEXT:    vfma.f16 s2, s0, s4
; DONT-FUSE-NEXT:    vstr.16 s2, [r0]
; DONT-FUSE-NEXT:    bx lr

  %a = load half, half *%aa, align 2
  %b = load half, half *%bb, align 2
  %ret = call half @llvm.fma.f16(half 2.0, half %a, half %b)
  store half %ret, half *%aa, align 2
  ret void
}

define arm_aapcs_vfpcc void @fms1(half *%a1, half *%a2, half *%a3) {
; CHECK-LABEL: fms1:
; CHECK:       @ %bb.0:
; CHECK-NEXT:    vldr.16 s0, [r1]
; CHECK-NEXT:    vldr.16 s2, [r0]
; CHECK-NEXT:    vldr.16 s4, [r2]
; CHECK-NEXT:    vfms.f16 s4, s2, s0
; CHECK-NEXT:    vstr.16 s4, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: fms1:
; DONT-FUSE:       @ %bb.0:
; DONT-FUSE-NEXT:    vldr.16 s0, [r1]
; DONT-FUSE-NEXT:    vldr.16 s2, [r0]
; DONT-FUSE-NEXT:    vldr.16 s4, [r2]
; DONT-FUSE-NEXT:    vfms.f16 s4, s2, s0
; DONT-FUSE-NEXT:    vstr.16 s4, [r0]
; DONT-FUSE-NEXT:    bx lr

  %f1 = load half, half *%a1, align 2
  %f2 = load half, half *%a2, align 2
  %f3 = load half, half *%a3, align 2
  %s = fsub half -0.0, %f1
  %ret = call half @llvm.fma.f16(half %s, half %f2, half %f3)
  store half %ret, half *%a1, align 2
  ret void
}

define arm_aapcs_vfpcc void @fms2(half *%a1, half *%a2, half *%a3) {
; CHECK-LABEL: fms2:
; CHECK:       @ %bb.0:
; CHECK-NEXT:    vldr.16 s0, [r1]
; CHECK-NEXT:    vldr.16 s2, [r0]
; CHECK-NEXT:    vldr.16 s4, [r2]
; CHECK-NEXT:    vfms.f16 s4, s2, s0
; CHECK-NEXT:    vstr.16 s4, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: fms2:
; DONT-FUSE:       @ %bb.0:
; DONT-FUSE-NEXT:    vldr.16 s0, [r1]
; DONT-FUSE-NEXT:    vldr.16 s2, [r0]
; DONT-FUSE-NEXT:    vldr.16 s4, [r2]
; DONT-FUSE-NEXT:    vfms.f16 s4, s2, s0
; DONT-FUSE-NEXT:    vstr.16 s4, [r0]
; DONT-FUSE-NEXT:    bx lr

  %f1 = load half, half *%a1, align 2
  %f2 = load half, half *%a2, align 2
  %f3 = load half, half *%a3, align 2
  %s = fsub half -0.0, %f1
  %ret = call half @llvm.fma.f16(half %f2, half %s, half %f3)
  store half %ret, half *%a1, align 2
  ret void
}

define arm_aapcs_vfpcc void @fnma1(half *%a1, half *%a2, half *%a3) {
; CHECK-LABEL: fnma1:
; CHECK:       @ %bb.0:
; CHECK-NEXT:    vldr.16 s0, [r1]
; CHECK-NEXT:    vldr.16 s2, [r0]
; CHECK-NEXT:    vldr.16 s4, [r2]
; CHECK-NEXT:    vfnma.f16 s4, s2, s0
; CHECK-NEXT:    vstr.16 s4, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: fnma1:
; DONT-FUSE:       @ %bb.0:
; DONT-FUSE-NEXT:    vldr.16 s0, [r1]
; DONT-FUSE-NEXT:    vldr.16 s2, [r0]
; DONT-FUSE-NEXT:    vldr.16 s4, [r2]
; DONT-FUSE-NEXT:    vfnma.f16 s4, s2, s0
; DONT-FUSE-NEXT:    vstr.16 s4, [r0]
; DONT-FUSE-NEXT:    bx lr

  %f1 = load half, half *%a1, align 2
  %f2 = load half, half *%a2, align 2
  %f3 = load half, half *%a3, align 2
  %fma = call half @llvm.fma.f16(half %f1, half %f2, half %f3)
  %n1 = fsub half -0.0, %fma
  store half %n1, half *%a1, align 2
  ret void
}

define arm_aapcs_vfpcc void @fnma2(half *%a1, half *%a2, half *%a3) {
; CHECK-LABEL: fnma2:
; CHECK:       @ %bb.0:
; CHECK-NEXT:    vldr.16 s0, [r1]
; CHECK-NEXT:    vldr.16 s2, [r0]
; CHECK-NEXT:    vldr.16 s4, [r2]
; CHECK-NEXT:    vfnma.f16 s4, s2, s0
; CHECK-NEXT:    vstr.16 s4, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: fnma2:
; DONT-FUSE:       @ %bb.0:
; DONT-FUSE-NEXT:    vldr.16 s0, [r1]
; DONT-FUSE-NEXT:    vldr.16 s2, [r0]
; DONT-FUSE-NEXT:    vldr.16 s4, [r2]
; DONT-FUSE-NEXT:    vfnma.f16 s4, s2, s0
; DONT-FUSE-NEXT:    vstr.16 s4, [r0]
; DONT-FUSE-NEXT:    bx lr

  %f1 = load half, half *%a1, align 2
  %f2 = load half, half *%a2, align 2
  %f3 = load half, half *%a3, align 2
  %n1 = fsub half -0.0, %f1
  %n3 = fsub half -0.0, %f3
  %ret = call half @llvm.fma.f16(half %n1, half %f2, half %n3)
  store half %ret, half *%a1, align 2
  ret void
}

define arm_aapcs_vfpcc void @fnms1(half *%a1, half *%a2, half *%a3) {
; CHECK-LABEL: fnms1:
; CHECK:       @ %bb.0:
; CHECK-NEXT:    vldr.16 s0, [r1]
; CHECK-NEXT:    vldr.16 s2, [r0]
; CHECK-NEXT:    vldr.16 s4, [r2]
; CHECK-NEXT:    vfnms.f16 s4, s2, s0
; CHECK-NEXT:    vstr.16 s4, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: fnms1:
; DONT-FUSE:       @ %bb.0:
; DONT-FUSE-NEXT:    vldr.16 s0, [r1]
; DONT-FUSE-NEXT:    vldr.16 s2, [r0]
; DONT-FUSE-NEXT:    vldr.16 s4, [r2]
; DONT-FUSE-NEXT:    vfnms.f16 s4, s2, s0
; DONT-FUSE-NEXT:    vstr.16 s4, [r0]
; DONT-FUSE-NEXT:    bx lr

  %f1 = load half, half *%a1, align 2
  %f2 = load half, half *%a2, align 2
  %f3 = load half, half *%a3, align 2
  %n3 = fsub half -0.0, %f3
  %ret = call half @llvm.fma.f16(half %f1, half %f2, half %n3)
  store half %ret, half *%a1, align 2
  ret void
}

define arm_aapcs_vfpcc void @fnms2(half *%a1, half *%a2, half *%a3) {
; CHECK-LABEL: fnms2:
; CHECK:       @ %bb.0:
; CHECK-NEXT:    vldr.16 s0, [r1]
; CHECK-NEXT:    vldr.16 s2, [r0]
; CHECK-NEXT:    vldr.16 s4, [r2]
; CHECK-NEXT:    vfnms.f16 s4, s2, s0
; CHECK-NEXT:    vstr.16 s4, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: fnms2:
; DONT-FUSE:       @ %bb.0:
; DONT-FUSE-NEXT:    vldr.16 s0, [r1]
; DONT-FUSE-NEXT:    vldr.16 s2, [r0]
; DONT-FUSE-NEXT:    vldr.16 s4, [r2]
; DONT-FUSE-NEXT:    vfnms.f16 s4, s2, s0
; DONT-FUSE-NEXT:    vstr.16 s4, [r0]
; DONT-FUSE-NEXT:    bx lr

  %f1 = load half, half *%a1, align 2
  %f2 = load half, half *%a2, align 2
  %f3 = load half, half *%a3, align 2
  %n1 = fsub half -0.0, %f1
  %fma = call half @llvm.fma.f16(half %n1, half %f2, half %f3)
  %n = fsub half -0.0, %fma
  store half %n, half *%a1, align 2
  ret void
}

define arm_aapcs_vfpcc void @fnms3(half *%a1, half *%a2, half *%a3) {
; CHECK-LABEL: fnms3:
; CHECK:       @ %bb.0:
; CHECK-NEXT:    vldr.16 s0, [r0]
; CHECK-NEXT:    vldr.16 s2, [r1]
; CHECK-NEXT:    vldr.16 s4, [r2]
; CHECK-NEXT:    vfnms.f16 s4, s2, s0
; CHECK-NEXT:    vstr.16 s4, [r0]
; CHECK-NEXT:    bx lr
;
; DONT-FUSE-LABEL: fnms3:
; DONT-FUSE:       @ %bb.0:
; DONT-FUSE-NEXT:    vldr.16 s0, [r0]
; DONT-FUSE-NEXT:    vldr.16 s2, [r1]
; DONT-FUSE-NEXT:    vldr.16 s4, [r2]
; DONT-FUSE-NEXT:    vfnms.f16 s4, s2, s0
; DONT-FUSE-NEXT:    vstr.16 s4, [r0]
; DONT-FUSE-NEXT:    bx lr

  %f1 = load half, half *%a1, align 2
  %f2 = load half, half *%a2, align 2
  %f3 = load half, half *%a3, align 2
  %n2 = fsub half -0.0, %f2
  %fma = call half @llvm.fma.f16(half %f1, half %n2, half %f3)
  %n1 = fsub half -0.0, %fma
  store half %n1, half *%a1, align 2
  ret void
}


declare half @llvm.fma.f16(half, half, half) nounwind readnone
