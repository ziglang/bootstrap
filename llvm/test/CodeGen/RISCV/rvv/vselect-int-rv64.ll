; NOTE: Assertions have been autogenerated by utils/update_llc_test_checks.py
; RUN: llc -mtriple=riscv64 -mattr=+experimental-v -verify-machineinstrs < %s | FileCheck %s

define <vscale x 1 x i8> @vmerge_vv_nxv1i8(<vscale x 1 x i8> %va, <vscale x 1 x i8> %vb, <vscale x 1 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv1i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e8,mf8,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v9, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 1 x i1> %cond, <vscale x 1 x i8> %va, <vscale x 1 x i8> %vb
  ret <vscale x 1 x i8> %vc
}

define <vscale x 1 x i8> @vmerge_xv_nxv1i8(<vscale x 1 x i8> %va, i8 signext %b, <vscale x 1 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv1i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e8,mf8,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 1 x i8> undef, i8 %b, i32 0
  %splat = shufflevector <vscale x 1 x i8> %head, <vscale x 1 x i8> undef, <vscale x 1 x i32> zeroinitializer
  %vc = select <vscale x 1 x i1> %cond, <vscale x 1 x i8> %splat, <vscale x 1 x i8> %va
  ret <vscale x 1 x i8> %vc
}

define <vscale x 1 x i8> @vmerge_iv_nxv1i8(<vscale x 1 x i8> %va, <vscale x 1 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv1i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e8,mf8,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 1 x i8> undef, i8 3, i32 0
  %splat = shufflevector <vscale x 1 x i8> %head, <vscale x 1 x i8> undef, <vscale x 1 x i32> zeroinitializer
  %vc = select <vscale x 1 x i1> %cond, <vscale x 1 x i8> %splat, <vscale x 1 x i8> %va
  ret <vscale x 1 x i8> %vc
}

define <vscale x 2 x i8> @vmerge_vv_nxv2i8(<vscale x 2 x i8> %va, <vscale x 2 x i8> %vb, <vscale x 2 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv2i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e8,mf4,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v9, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 2 x i1> %cond, <vscale x 2 x i8> %va, <vscale x 2 x i8> %vb
  ret <vscale x 2 x i8> %vc
}

define <vscale x 2 x i8> @vmerge_xv_nxv2i8(<vscale x 2 x i8> %va, i8 signext %b, <vscale x 2 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv2i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e8,mf4,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 2 x i8> undef, i8 %b, i32 0
  %splat = shufflevector <vscale x 2 x i8> %head, <vscale x 2 x i8> undef, <vscale x 2 x i32> zeroinitializer
  %vc = select <vscale x 2 x i1> %cond, <vscale x 2 x i8> %splat, <vscale x 2 x i8> %va
  ret <vscale x 2 x i8> %vc
}

define <vscale x 2 x i8> @vmerge_iv_nxv2i8(<vscale x 2 x i8> %va, <vscale x 2 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv2i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e8,mf4,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 2 x i8> undef, i8 3, i32 0
  %splat = shufflevector <vscale x 2 x i8> %head, <vscale x 2 x i8> undef, <vscale x 2 x i32> zeroinitializer
  %vc = select <vscale x 2 x i1> %cond, <vscale x 2 x i8> %splat, <vscale x 2 x i8> %va
  ret <vscale x 2 x i8> %vc
}

define <vscale x 4 x i8> @vmerge_vv_nxv4i8(<vscale x 4 x i8> %va, <vscale x 4 x i8> %vb, <vscale x 4 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv4i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e8,mf2,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v9, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 4 x i1> %cond, <vscale x 4 x i8> %va, <vscale x 4 x i8> %vb
  ret <vscale x 4 x i8> %vc
}

define <vscale x 4 x i8> @vmerge_xv_nxv4i8(<vscale x 4 x i8> %va, i8 signext %b, <vscale x 4 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv4i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e8,mf2,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 4 x i8> undef, i8 %b, i32 0
  %splat = shufflevector <vscale x 4 x i8> %head, <vscale x 4 x i8> undef, <vscale x 4 x i32> zeroinitializer
  %vc = select <vscale x 4 x i1> %cond, <vscale x 4 x i8> %splat, <vscale x 4 x i8> %va
  ret <vscale x 4 x i8> %vc
}

define <vscale x 4 x i8> @vmerge_iv_nxv4i8(<vscale x 4 x i8> %va, <vscale x 4 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv4i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e8,mf2,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 4 x i8> undef, i8 3, i32 0
  %splat = shufflevector <vscale x 4 x i8> %head, <vscale x 4 x i8> undef, <vscale x 4 x i32> zeroinitializer
  %vc = select <vscale x 4 x i1> %cond, <vscale x 4 x i8> %splat, <vscale x 4 x i8> %va
  ret <vscale x 4 x i8> %vc
}

define <vscale x 8 x i8> @vmerge_vv_nxv8i8(<vscale x 8 x i8> %va, <vscale x 8 x i8> %vb, <vscale x 8 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv8i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e8,m1,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v9, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 8 x i1> %cond, <vscale x 8 x i8> %va, <vscale x 8 x i8> %vb
  ret <vscale x 8 x i8> %vc
}

define <vscale x 8 x i8> @vmerge_xv_nxv8i8(<vscale x 8 x i8> %va, i8 signext %b, <vscale x 8 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv8i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e8,m1,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 8 x i8> undef, i8 %b, i32 0
  %splat = shufflevector <vscale x 8 x i8> %head, <vscale x 8 x i8> undef, <vscale x 8 x i32> zeroinitializer
  %vc = select <vscale x 8 x i1> %cond, <vscale x 8 x i8> %splat, <vscale x 8 x i8> %va
  ret <vscale x 8 x i8> %vc
}

define <vscale x 8 x i8> @vmerge_iv_nxv8i8(<vscale x 8 x i8> %va, <vscale x 8 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv8i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e8,m1,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 8 x i8> undef, i8 3, i32 0
  %splat = shufflevector <vscale x 8 x i8> %head, <vscale x 8 x i8> undef, <vscale x 8 x i32> zeroinitializer
  %vc = select <vscale x 8 x i1> %cond, <vscale x 8 x i8> %splat, <vscale x 8 x i8> %va
  ret <vscale x 8 x i8> %vc
}

define <vscale x 16 x i8> @vmerge_vv_nxv16i8(<vscale x 16 x i8> %va, <vscale x 16 x i8> %vb, <vscale x 16 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv16i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e8,m2,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v10, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 16 x i1> %cond, <vscale x 16 x i8> %va, <vscale x 16 x i8> %vb
  ret <vscale x 16 x i8> %vc
}

define <vscale x 16 x i8> @vmerge_xv_nxv16i8(<vscale x 16 x i8> %va, i8 signext %b, <vscale x 16 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv16i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e8,m2,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 16 x i8> undef, i8 %b, i32 0
  %splat = shufflevector <vscale x 16 x i8> %head, <vscale x 16 x i8> undef, <vscale x 16 x i32> zeroinitializer
  %vc = select <vscale x 16 x i1> %cond, <vscale x 16 x i8> %splat, <vscale x 16 x i8> %va
  ret <vscale x 16 x i8> %vc
}

define <vscale x 16 x i8> @vmerge_iv_nxv16i8(<vscale x 16 x i8> %va, <vscale x 16 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv16i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e8,m2,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 16 x i8> undef, i8 3, i32 0
  %splat = shufflevector <vscale x 16 x i8> %head, <vscale x 16 x i8> undef, <vscale x 16 x i32> zeroinitializer
  %vc = select <vscale x 16 x i1> %cond, <vscale x 16 x i8> %splat, <vscale x 16 x i8> %va
  ret <vscale x 16 x i8> %vc
}

define <vscale x 32 x i8> @vmerge_vv_nxv32i8(<vscale x 32 x i8> %va, <vscale x 32 x i8> %vb, <vscale x 32 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv32i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e8,m4,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v12, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 32 x i1> %cond, <vscale x 32 x i8> %va, <vscale x 32 x i8> %vb
  ret <vscale x 32 x i8> %vc
}

define <vscale x 32 x i8> @vmerge_xv_nxv32i8(<vscale x 32 x i8> %va, i8 signext %b, <vscale x 32 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv32i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e8,m4,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 32 x i8> undef, i8 %b, i32 0
  %splat = shufflevector <vscale x 32 x i8> %head, <vscale x 32 x i8> undef, <vscale x 32 x i32> zeroinitializer
  %vc = select <vscale x 32 x i1> %cond, <vscale x 32 x i8> %splat, <vscale x 32 x i8> %va
  ret <vscale x 32 x i8> %vc
}

define <vscale x 32 x i8> @vmerge_iv_nxv32i8(<vscale x 32 x i8> %va, <vscale x 32 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv32i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e8,m4,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 32 x i8> undef, i8 3, i32 0
  %splat = shufflevector <vscale x 32 x i8> %head, <vscale x 32 x i8> undef, <vscale x 32 x i32> zeroinitializer
  %vc = select <vscale x 32 x i1> %cond, <vscale x 32 x i8> %splat, <vscale x 32 x i8> %va
  ret <vscale x 32 x i8> %vc
}

define <vscale x 64 x i8> @vmerge_vv_nxv64i8(<vscale x 64 x i8> %va, <vscale x 64 x i8> %vb, <vscale x 64 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv64i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e8,m8,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v16, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 64 x i1> %cond, <vscale x 64 x i8> %va, <vscale x 64 x i8> %vb
  ret <vscale x 64 x i8> %vc
}

define <vscale x 64 x i8> @vmerge_xv_nxv64i8(<vscale x 64 x i8> %va, i8 signext %b, <vscale x 64 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv64i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e8,m8,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 64 x i8> undef, i8 %b, i32 0
  %splat = shufflevector <vscale x 64 x i8> %head, <vscale x 64 x i8> undef, <vscale x 64 x i32> zeroinitializer
  %vc = select <vscale x 64 x i1> %cond, <vscale x 64 x i8> %splat, <vscale x 64 x i8> %va
  ret <vscale x 64 x i8> %vc
}

define <vscale x 64 x i8> @vmerge_iv_nxv64i8(<vscale x 64 x i8> %va, <vscale x 64 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv64i8:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e8,m8,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 64 x i8> undef, i8 3, i32 0
  %splat = shufflevector <vscale x 64 x i8> %head, <vscale x 64 x i8> undef, <vscale x 64 x i32> zeroinitializer
  %vc = select <vscale x 64 x i1> %cond, <vscale x 64 x i8> %splat, <vscale x 64 x i8> %va
  ret <vscale x 64 x i8> %vc
}

define <vscale x 1 x i16> @vmerge_vv_nxv1i16(<vscale x 1 x i16> %va, <vscale x 1 x i16> %vb, <vscale x 1 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv1i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e16,mf4,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v9, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 1 x i1> %cond, <vscale x 1 x i16> %va, <vscale x 1 x i16> %vb
  ret <vscale x 1 x i16> %vc
}

define <vscale x 1 x i16> @vmerge_xv_nxv1i16(<vscale x 1 x i16> %va, i16 signext %b, <vscale x 1 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv1i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e16,mf4,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 1 x i16> undef, i16 %b, i32 0
  %splat = shufflevector <vscale x 1 x i16> %head, <vscale x 1 x i16> undef, <vscale x 1 x i32> zeroinitializer
  %vc = select <vscale x 1 x i1> %cond, <vscale x 1 x i16> %splat, <vscale x 1 x i16> %va
  ret <vscale x 1 x i16> %vc
}

define <vscale x 1 x i16> @vmerge_iv_nxv1i16(<vscale x 1 x i16> %va, <vscale x 1 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv1i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e16,mf4,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 1 x i16> undef, i16 3, i32 0
  %splat = shufflevector <vscale x 1 x i16> %head, <vscale x 1 x i16> undef, <vscale x 1 x i32> zeroinitializer
  %vc = select <vscale x 1 x i1> %cond, <vscale x 1 x i16> %splat, <vscale x 1 x i16> %va
  ret <vscale x 1 x i16> %vc
}

define <vscale x 2 x i16> @vmerge_vv_nxv2i16(<vscale x 2 x i16> %va, <vscale x 2 x i16> %vb, <vscale x 2 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv2i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e16,mf2,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v9, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 2 x i1> %cond, <vscale x 2 x i16> %va, <vscale x 2 x i16> %vb
  ret <vscale x 2 x i16> %vc
}

define <vscale x 2 x i16> @vmerge_xv_nxv2i16(<vscale x 2 x i16> %va, i16 signext %b, <vscale x 2 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv2i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e16,mf2,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 2 x i16> undef, i16 %b, i32 0
  %splat = shufflevector <vscale x 2 x i16> %head, <vscale x 2 x i16> undef, <vscale x 2 x i32> zeroinitializer
  %vc = select <vscale x 2 x i1> %cond, <vscale x 2 x i16> %splat, <vscale x 2 x i16> %va
  ret <vscale x 2 x i16> %vc
}

define <vscale x 2 x i16> @vmerge_iv_nxv2i16(<vscale x 2 x i16> %va, <vscale x 2 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv2i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e16,mf2,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 2 x i16> undef, i16 3, i32 0
  %splat = shufflevector <vscale x 2 x i16> %head, <vscale x 2 x i16> undef, <vscale x 2 x i32> zeroinitializer
  %vc = select <vscale x 2 x i1> %cond, <vscale x 2 x i16> %splat, <vscale x 2 x i16> %va
  ret <vscale x 2 x i16> %vc
}

define <vscale x 4 x i16> @vmerge_vv_nxv4i16(<vscale x 4 x i16> %va, <vscale x 4 x i16> %vb, <vscale x 4 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv4i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e16,m1,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v9, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 4 x i1> %cond, <vscale x 4 x i16> %va, <vscale x 4 x i16> %vb
  ret <vscale x 4 x i16> %vc
}

define <vscale x 4 x i16> @vmerge_xv_nxv4i16(<vscale x 4 x i16> %va, i16 signext %b, <vscale x 4 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv4i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e16,m1,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 4 x i16> undef, i16 %b, i32 0
  %splat = shufflevector <vscale x 4 x i16> %head, <vscale x 4 x i16> undef, <vscale x 4 x i32> zeroinitializer
  %vc = select <vscale x 4 x i1> %cond, <vscale x 4 x i16> %splat, <vscale x 4 x i16> %va
  ret <vscale x 4 x i16> %vc
}

define <vscale x 4 x i16> @vmerge_iv_nxv4i16(<vscale x 4 x i16> %va, <vscale x 4 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv4i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e16,m1,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 4 x i16> undef, i16 3, i32 0
  %splat = shufflevector <vscale x 4 x i16> %head, <vscale x 4 x i16> undef, <vscale x 4 x i32> zeroinitializer
  %vc = select <vscale x 4 x i1> %cond, <vscale x 4 x i16> %splat, <vscale x 4 x i16> %va
  ret <vscale x 4 x i16> %vc
}

define <vscale x 8 x i16> @vmerge_vv_nxv8i16(<vscale x 8 x i16> %va, <vscale x 8 x i16> %vb, <vscale x 8 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv8i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e16,m2,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v10, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 8 x i1> %cond, <vscale x 8 x i16> %va, <vscale x 8 x i16> %vb
  ret <vscale x 8 x i16> %vc
}

define <vscale x 8 x i16> @vmerge_xv_nxv8i16(<vscale x 8 x i16> %va, i16 signext %b, <vscale x 8 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv8i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e16,m2,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 8 x i16> undef, i16 %b, i32 0
  %splat = shufflevector <vscale x 8 x i16> %head, <vscale x 8 x i16> undef, <vscale x 8 x i32> zeroinitializer
  %vc = select <vscale x 8 x i1> %cond, <vscale x 8 x i16> %splat, <vscale x 8 x i16> %va
  ret <vscale x 8 x i16> %vc
}

define <vscale x 8 x i16> @vmerge_iv_nxv8i16(<vscale x 8 x i16> %va, <vscale x 8 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv8i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e16,m2,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 8 x i16> undef, i16 3, i32 0
  %splat = shufflevector <vscale x 8 x i16> %head, <vscale x 8 x i16> undef, <vscale x 8 x i32> zeroinitializer
  %vc = select <vscale x 8 x i1> %cond, <vscale x 8 x i16> %splat, <vscale x 8 x i16> %va
  ret <vscale x 8 x i16> %vc
}

define <vscale x 16 x i16> @vmerge_vv_nxv16i16(<vscale x 16 x i16> %va, <vscale x 16 x i16> %vb, <vscale x 16 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv16i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e16,m4,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v12, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 16 x i1> %cond, <vscale x 16 x i16> %va, <vscale x 16 x i16> %vb
  ret <vscale x 16 x i16> %vc
}

define <vscale x 16 x i16> @vmerge_xv_nxv16i16(<vscale x 16 x i16> %va, i16 signext %b, <vscale x 16 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv16i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e16,m4,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 16 x i16> undef, i16 %b, i32 0
  %splat = shufflevector <vscale x 16 x i16> %head, <vscale x 16 x i16> undef, <vscale x 16 x i32> zeroinitializer
  %vc = select <vscale x 16 x i1> %cond, <vscale x 16 x i16> %splat, <vscale x 16 x i16> %va
  ret <vscale x 16 x i16> %vc
}

define <vscale x 16 x i16> @vmerge_iv_nxv16i16(<vscale x 16 x i16> %va, <vscale x 16 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv16i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e16,m4,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 16 x i16> undef, i16 3, i32 0
  %splat = shufflevector <vscale x 16 x i16> %head, <vscale x 16 x i16> undef, <vscale x 16 x i32> zeroinitializer
  %vc = select <vscale x 16 x i1> %cond, <vscale x 16 x i16> %splat, <vscale x 16 x i16> %va
  ret <vscale x 16 x i16> %vc
}

define <vscale x 32 x i16> @vmerge_vv_nxv32i16(<vscale x 32 x i16> %va, <vscale x 32 x i16> %vb, <vscale x 32 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv32i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e16,m8,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v16, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 32 x i1> %cond, <vscale x 32 x i16> %va, <vscale x 32 x i16> %vb
  ret <vscale x 32 x i16> %vc
}

define <vscale x 32 x i16> @vmerge_xv_nxv32i16(<vscale x 32 x i16> %va, i16 signext %b, <vscale x 32 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv32i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e16,m8,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 32 x i16> undef, i16 %b, i32 0
  %splat = shufflevector <vscale x 32 x i16> %head, <vscale x 32 x i16> undef, <vscale x 32 x i32> zeroinitializer
  %vc = select <vscale x 32 x i1> %cond, <vscale x 32 x i16> %splat, <vscale x 32 x i16> %va
  ret <vscale x 32 x i16> %vc
}

define <vscale x 32 x i16> @vmerge_iv_nxv32i16(<vscale x 32 x i16> %va, <vscale x 32 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv32i16:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e16,m8,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 32 x i16> undef, i16 3, i32 0
  %splat = shufflevector <vscale x 32 x i16> %head, <vscale x 32 x i16> undef, <vscale x 32 x i32> zeroinitializer
  %vc = select <vscale x 32 x i1> %cond, <vscale x 32 x i16> %splat, <vscale x 32 x i16> %va
  ret <vscale x 32 x i16> %vc
}

define <vscale x 1 x i32> @vmerge_vv_nxv1i32(<vscale x 1 x i32> %va, <vscale x 1 x i32> %vb, <vscale x 1 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv1i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e32,mf2,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v9, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 1 x i1> %cond, <vscale x 1 x i32> %va, <vscale x 1 x i32> %vb
  ret <vscale x 1 x i32> %vc
}

define <vscale x 1 x i32> @vmerge_xv_nxv1i32(<vscale x 1 x i32> %va, i32 signext %b, <vscale x 1 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv1i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e32,mf2,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 1 x i32> undef, i32 %b, i32 0
  %splat = shufflevector <vscale x 1 x i32> %head, <vscale x 1 x i32> undef, <vscale x 1 x i32> zeroinitializer
  %vc = select <vscale x 1 x i1> %cond, <vscale x 1 x i32> %splat, <vscale x 1 x i32> %va
  ret <vscale x 1 x i32> %vc
}

define <vscale x 1 x i32> @vmerge_iv_nxv1i32(<vscale x 1 x i32> %va, <vscale x 1 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv1i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e32,mf2,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 1 x i32> undef, i32 3, i32 0
  %splat = shufflevector <vscale x 1 x i32> %head, <vscale x 1 x i32> undef, <vscale x 1 x i32> zeroinitializer
  %vc = select <vscale x 1 x i1> %cond, <vscale x 1 x i32> %splat, <vscale x 1 x i32> %va
  ret <vscale x 1 x i32> %vc
}

define <vscale x 2 x i32> @vmerge_vv_nxv2i32(<vscale x 2 x i32> %va, <vscale x 2 x i32> %vb, <vscale x 2 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv2i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e32,m1,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v9, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 2 x i1> %cond, <vscale x 2 x i32> %va, <vscale x 2 x i32> %vb
  ret <vscale x 2 x i32> %vc
}

define <vscale x 2 x i32> @vmerge_xv_nxv2i32(<vscale x 2 x i32> %va, i32 signext %b, <vscale x 2 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv2i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e32,m1,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 2 x i32> undef, i32 %b, i32 0
  %splat = shufflevector <vscale x 2 x i32> %head, <vscale x 2 x i32> undef, <vscale x 2 x i32> zeroinitializer
  %vc = select <vscale x 2 x i1> %cond, <vscale x 2 x i32> %splat, <vscale x 2 x i32> %va
  ret <vscale x 2 x i32> %vc
}

define <vscale x 2 x i32> @vmerge_iv_nxv2i32(<vscale x 2 x i32> %va, <vscale x 2 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv2i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e32,m1,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 2 x i32> undef, i32 3, i32 0
  %splat = shufflevector <vscale x 2 x i32> %head, <vscale x 2 x i32> undef, <vscale x 2 x i32> zeroinitializer
  %vc = select <vscale x 2 x i1> %cond, <vscale x 2 x i32> %splat, <vscale x 2 x i32> %va
  ret <vscale x 2 x i32> %vc
}

define <vscale x 4 x i32> @vmerge_vv_nxv4i32(<vscale x 4 x i32> %va, <vscale x 4 x i32> %vb, <vscale x 4 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv4i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e32,m2,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v10, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 4 x i1> %cond, <vscale x 4 x i32> %va, <vscale x 4 x i32> %vb
  ret <vscale x 4 x i32> %vc
}

define <vscale x 4 x i32> @vmerge_xv_nxv4i32(<vscale x 4 x i32> %va, i32 signext %b, <vscale x 4 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv4i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e32,m2,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 4 x i32> undef, i32 %b, i32 0
  %splat = shufflevector <vscale x 4 x i32> %head, <vscale x 4 x i32> undef, <vscale x 4 x i32> zeroinitializer
  %vc = select <vscale x 4 x i1> %cond, <vscale x 4 x i32> %splat, <vscale x 4 x i32> %va
  ret <vscale x 4 x i32> %vc
}

define <vscale x 4 x i32> @vmerge_iv_nxv4i32(<vscale x 4 x i32> %va, <vscale x 4 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv4i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e32,m2,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 4 x i32> undef, i32 3, i32 0
  %splat = shufflevector <vscale x 4 x i32> %head, <vscale x 4 x i32> undef, <vscale x 4 x i32> zeroinitializer
  %vc = select <vscale x 4 x i1> %cond, <vscale x 4 x i32> %splat, <vscale x 4 x i32> %va
  ret <vscale x 4 x i32> %vc
}

define <vscale x 8 x i32> @vmerge_vv_nxv8i32(<vscale x 8 x i32> %va, <vscale x 8 x i32> %vb, <vscale x 8 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv8i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e32,m4,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v12, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 8 x i1> %cond, <vscale x 8 x i32> %va, <vscale x 8 x i32> %vb
  ret <vscale x 8 x i32> %vc
}

define <vscale x 8 x i32> @vmerge_xv_nxv8i32(<vscale x 8 x i32> %va, i32 signext %b, <vscale x 8 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv8i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e32,m4,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 8 x i32> undef, i32 %b, i32 0
  %splat = shufflevector <vscale x 8 x i32> %head, <vscale x 8 x i32> undef, <vscale x 8 x i32> zeroinitializer
  %vc = select <vscale x 8 x i1> %cond, <vscale x 8 x i32> %splat, <vscale x 8 x i32> %va
  ret <vscale x 8 x i32> %vc
}

define <vscale x 8 x i32> @vmerge_iv_nxv8i32(<vscale x 8 x i32> %va, <vscale x 8 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv8i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e32,m4,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 8 x i32> undef, i32 3, i32 0
  %splat = shufflevector <vscale x 8 x i32> %head, <vscale x 8 x i32> undef, <vscale x 8 x i32> zeroinitializer
  %vc = select <vscale x 8 x i1> %cond, <vscale x 8 x i32> %splat, <vscale x 8 x i32> %va
  ret <vscale x 8 x i32> %vc
}

define <vscale x 16 x i32> @vmerge_vv_nxv16i32(<vscale x 16 x i32> %va, <vscale x 16 x i32> %vb, <vscale x 16 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv16i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e32,m8,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v16, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 16 x i1> %cond, <vscale x 16 x i32> %va, <vscale x 16 x i32> %vb
  ret <vscale x 16 x i32> %vc
}

define <vscale x 16 x i32> @vmerge_xv_nxv16i32(<vscale x 16 x i32> %va, i32 signext %b, <vscale x 16 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv16i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e32,m8,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 16 x i32> undef, i32 %b, i32 0
  %splat = shufflevector <vscale x 16 x i32> %head, <vscale x 16 x i32> undef, <vscale x 16 x i32> zeroinitializer
  %vc = select <vscale x 16 x i1> %cond, <vscale x 16 x i32> %splat, <vscale x 16 x i32> %va
  ret <vscale x 16 x i32> %vc
}

define <vscale x 16 x i32> @vmerge_iv_nxv16i32(<vscale x 16 x i32> %va, <vscale x 16 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv16i32:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e32,m8,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 16 x i32> undef, i32 3, i32 0
  %splat = shufflevector <vscale x 16 x i32> %head, <vscale x 16 x i32> undef, <vscale x 16 x i32> zeroinitializer
  %vc = select <vscale x 16 x i1> %cond, <vscale x 16 x i32> %splat, <vscale x 16 x i32> %va
  ret <vscale x 16 x i32> %vc
}

define <vscale x 1 x i64> @vmerge_vv_nxv1i64(<vscale x 1 x i64> %va, <vscale x 1 x i64> %vb, <vscale x 1 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv1i64:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e64,m1,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v9, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 1 x i1> %cond, <vscale x 1 x i64> %va, <vscale x 1 x i64> %vb
  ret <vscale x 1 x i64> %vc
}

define <vscale x 1 x i64> @vmerge_xv_nxv1i64(<vscale x 1 x i64> %va, i64 %b, <vscale x 1 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv1i64:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e64,m1,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 1 x i64> undef, i64 %b, i32 0
  %splat = shufflevector <vscale x 1 x i64> %head, <vscale x 1 x i64> undef, <vscale x 1 x i32> zeroinitializer
  %vc = select <vscale x 1 x i1> %cond, <vscale x 1 x i64> %splat, <vscale x 1 x i64> %va
  ret <vscale x 1 x i64> %vc
}

define <vscale x 1 x i64> @vmerge_iv_nxv1i64(<vscale x 1 x i64> %va, <vscale x 1 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv1i64:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e64,m1,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 1 x i64> undef, i64 3, i32 0
  %splat = shufflevector <vscale x 1 x i64> %head, <vscale x 1 x i64> undef, <vscale x 1 x i32> zeroinitializer
  %vc = select <vscale x 1 x i1> %cond, <vscale x 1 x i64> %splat, <vscale x 1 x i64> %va
  ret <vscale x 1 x i64> %vc
}

define <vscale x 2 x i64> @vmerge_vv_nxv2i64(<vscale x 2 x i64> %va, <vscale x 2 x i64> %vb, <vscale x 2 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv2i64:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e64,m2,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v10, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 2 x i1> %cond, <vscale x 2 x i64> %va, <vscale x 2 x i64> %vb
  ret <vscale x 2 x i64> %vc
}

define <vscale x 2 x i64> @vmerge_xv_nxv2i64(<vscale x 2 x i64> %va, i64 %b, <vscale x 2 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv2i64:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e64,m2,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 2 x i64> undef, i64 %b, i32 0
  %splat = shufflevector <vscale x 2 x i64> %head, <vscale x 2 x i64> undef, <vscale x 2 x i32> zeroinitializer
  %vc = select <vscale x 2 x i1> %cond, <vscale x 2 x i64> %splat, <vscale x 2 x i64> %va
  ret <vscale x 2 x i64> %vc
}

define <vscale x 2 x i64> @vmerge_iv_nxv2i64(<vscale x 2 x i64> %va, <vscale x 2 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv2i64:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e64,m2,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 2 x i64> undef, i64 3, i32 0
  %splat = shufflevector <vscale x 2 x i64> %head, <vscale x 2 x i64> undef, <vscale x 2 x i32> zeroinitializer
  %vc = select <vscale x 2 x i1> %cond, <vscale x 2 x i64> %splat, <vscale x 2 x i64> %va
  ret <vscale x 2 x i64> %vc
}

define <vscale x 4 x i64> @vmerge_vv_nxv4i64(<vscale x 4 x i64> %va, <vscale x 4 x i64> %vb, <vscale x 4 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv4i64:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e64,m4,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v12, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 4 x i1> %cond, <vscale x 4 x i64> %va, <vscale x 4 x i64> %vb
  ret <vscale x 4 x i64> %vc
}

define <vscale x 4 x i64> @vmerge_xv_nxv4i64(<vscale x 4 x i64> %va, i64 %b, <vscale x 4 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv4i64:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e64,m4,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 4 x i64> undef, i64 %b, i32 0
  %splat = shufflevector <vscale x 4 x i64> %head, <vscale x 4 x i64> undef, <vscale x 4 x i32> zeroinitializer
  %vc = select <vscale x 4 x i1> %cond, <vscale x 4 x i64> %splat, <vscale x 4 x i64> %va
  ret <vscale x 4 x i64> %vc
}

define <vscale x 4 x i64> @vmerge_iv_nxv4i64(<vscale x 4 x i64> %va, <vscale x 4 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv4i64:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e64,m4,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 4 x i64> undef, i64 3, i32 0
  %splat = shufflevector <vscale x 4 x i64> %head, <vscale x 4 x i64> undef, <vscale x 4 x i32> zeroinitializer
  %vc = select <vscale x 4 x i1> %cond, <vscale x 4 x i64> %splat, <vscale x 4 x i64> %va
  ret <vscale x 4 x i64> %vc
}

define <vscale x 8 x i64> @vmerge_vv_nxv8i64(<vscale x 8 x i64> %va, <vscale x 8 x i64> %vb, <vscale x 8 x i1> %cond) {
; CHECK-LABEL: vmerge_vv_nxv8i64:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e64,m8,ta,mu
; CHECK-NEXT:    vmerge.vvm v8, v16, v8, v0
; CHECK-NEXT:    ret
  %vc = select <vscale x 8 x i1> %cond, <vscale x 8 x i64> %va, <vscale x 8 x i64> %vb
  ret <vscale x 8 x i64> %vc
}

define <vscale x 8 x i64> @vmerge_xv_nxv8i64(<vscale x 8 x i64> %va, i64 %b, <vscale x 8 x i1> %cond) {
; CHECK-LABEL: vmerge_xv_nxv8i64:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a1, zero, e64,m8,ta,mu
; CHECK-NEXT:    vmerge.vxm v8, v8, a0, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 8 x i64> undef, i64 %b, i32 0
  %splat = shufflevector <vscale x 8 x i64> %head, <vscale x 8 x i64> undef, <vscale x 8 x i32> zeroinitializer
  %vc = select <vscale x 8 x i1> %cond, <vscale x 8 x i64> %splat, <vscale x 8 x i64> %va
  ret <vscale x 8 x i64> %vc
}

define <vscale x 8 x i64> @vmerge_iv_nxv8i64(<vscale x 8 x i64> %va, <vscale x 8 x i1> %cond) {
; CHECK-LABEL: vmerge_iv_nxv8i64:
; CHECK:       # %bb.0:
; CHECK-NEXT:    vsetvli a0, zero, e64,m8,ta,mu
; CHECK-NEXT:    vmerge.vim v8, v8, 3, v0
; CHECK-NEXT:    ret
  %head = insertelement <vscale x 8 x i64> undef, i64 3, i32 0
  %splat = shufflevector <vscale x 8 x i64> %head, <vscale x 8 x i64> undef, <vscale x 8 x i32> zeroinitializer
  %vc = select <vscale x 8 x i1> %cond, <vscale x 8 x i64> %splat, <vscale x 8 x i64> %va
  ret <vscale x 8 x i64> %vc
}

