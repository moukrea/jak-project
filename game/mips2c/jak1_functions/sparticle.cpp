// clang-format off
//--------------------------MIPS2C---------------------
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <ctime>

#include "game/mips2c/mips2c_private.h"
#include "game/kernel/jak1/kscheme.h"
#if defined(__ANDROID__)
#include <sys/system_properties.h>
#endif
using namespace jak1;
namespace Mips2C::jak1 {

// Geco-spheres TEMPORARY diagnostic gate — env OG_SPART_DUMP / Android prop
// debug.opengoal.spart.dump (same switch as the SPART-INIT dump in
// sparticle_launcher.cpp). Value "1" arms immediately; a value N>1 arms N
// seconds after the first particle launch (so the capped dump skips the boot/
// title particle flood and captures the post-warp eco launches instead).
static bool geco_spart_dump_armed() {
  static long s_delay = -2;  // -2 = unread, -1 = off, 0 = armed, >0 = arm-at (epoch s)
  if (s_delay == -2) {
    s_delay = -1;
    const char* v = std::getenv("OG_SPART_DUMP");
#if defined(__ANDROID__)
    char pbuf[92] = {0};
    if (!v && __system_property_get("debug.opengoal.spart.dump", pbuf) > 0 && pbuf[0]) {
      v = pbuf;
    }
#endif
    if (v && v[0]) {
      long n = std::atol(v);
      if (n == 1) {
        s_delay = 0;
      } else if (n > 1) {
        s_delay = (long)time(nullptr) + n;
      }
    }
  }
  if (s_delay > 0 && (long)time(nullptr) >= s_delay) {
    s_delay = 0;
  }
  return s_delay == 0;
}
namespace sp_process_block_3d {
struct Cache {
  void* sp_frame_time; // *sp-frame-time*
  void* quaternion; // quaternion*!
  void* sp_free_particle; // sp-free-particle
  void* sp_relaunch_particle_3d; // sp-relaunch-particle-3d
} cache;

u64 execute(void* ctxt) {
  auto* c = (ExecutionContext*)ctxt;
  bool bc = false;
  u32 call_addr = 0;
  bool cop1_bc = false;
  c->daddiu(sp, sp, -160);                          // daddiu sp, sp, -160
  c->sd(ra, 0, sp);                                 // sd ra, 0(sp)
  c->sd(fp, 8, sp);                                 // sd fp, 8(sp)
  c->mov64(fp, t9);                                 // or fp, t9, r0
  c->sq(s0, 48, sp);                                // sq s0, 48(sp)
  c->sq(s1, 64, sp);                                // sq s1, 64(sp)
  c->sq(s2, 80, sp);                                // sq s2, 80(sp)
  c->sq(s3, 96, sp);                                // sq s3, 96(sp)
  c->sq(s4, 112, sp);                               // sq s4, 112(sp)
  c->sq(s5, 128, sp);                               // sq s5, 128(sp)
  c->sq(gp, 144, sp);                               // sq gp, 144(sp)
  c->mov64(gp, a0);                                 // or gp, a0, r0
  c->mov64(s5, a1);                                 // or s5, a1, r0
  c->mov64(s4, a2);                                 // or s4, a2, r0
  c->mov64(s0, a3);                                 // or s0, a3, r0
  c->mov64(s3, t0);                                 // or s3, t0, r0
  c->mov64(s2, t1);                                 // or s2, t1, r0
  c->daddiu(s1, sp, 16);                            // daddiu s1, sp, 16
  c->sq(r0, 0, s1);                                 // sq r0, 0(s1)
  c->load_symbol(v1, cache.sp_frame_time);          // lw v1, *sp-frame-time*(s7)
  c->lqc2(vf16, 0, v1);                             // lqc2 vf16, 0(v1)
  c->mov128_gpr_vf(v1, vf16);                       // qmfc2.i v1, vf16
  c->andi(v1, v1, 255);                             // andi v1, v1, 255
  c->sq(v1, 32, sp);                                // sq v1, 32(sp)
  // nop                                            // sll r0, r0, 0

  block_1:
  c->lw(v1, 128, s5);                               // lw v1, 128(s5)
#if defined(__aarch64__)
  // Gd2 (arm64): `beq v1, s7` tests "is (-> cpuinfo valid) == #f?" — skip an
  // INVALID 3D-particle slot. GOAL pointers are 32-bit, but in the mips2c
  // ExecutionContext on arm64 they carry inconsistent upper-32: gpr s7 is the
  // full host symbol base (0x7f0014fd24) while a #f field loaded via sign-extended
  // `lw` arrives as the bare 32-bit GOAL offset (0x14fd24). A full-64 `sgpr64`
  // compare then MISSES #f (proven on-device: full=0 lo=1), so the invalid slot is
  // NOT skipped and its stale `func` field (+112) is later jalr'd as a function =
  // the wild-callback SIGSEGV that got this builder noop'd. Compare the 32-bit GOAL
  // pointer (low32), which is representation-agnostic. x86 is unaffected (operands
  // consistent there). Same bug class as sp-launch-particles-var (Gnewgame/Gsprite).
  bc = c->gpr_addr(v1) == c->gpr_addr(s7);          // beq v1, s7 (32-bit GOAL ptr)
#else
  bc = c->sgpr64(v1) == c->sgpr64(s7);              // beq v1, s7, L83
#endif
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_34;}                          // branch non-likely

#if defined(__aarch64__)
  bc = c->gpr_addr(s2) == c->gpr_addr(s7);          // beq s2, s7 (32-bit GOAL ptr; (paused?) #f-check)
#else
  bc = c->sgpr64(s2) == c->sgpr64(s7);              // beq s2, s7, L71
#endif
  c->lw(v1, 104, s5);                               // lw v1, 104(s5)
  if (bc) {goto block_8;}                           // branch non-likely

  c->andi(v1, v1, 8192);                            // andi v1, v1, 8192
  bc = c->sgpr64(v1) != 0;                          // bne v1, r0, L71
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_8;}                           // branch non-likely

  c->lw(v1, 100, s5);                               // lw v1, 100(s5)
  c->addiu(a0, r0, -1);                             // addiu a0, r0, -1
  bc = c->sgpr64(v1) == c->sgpr64(a0);              // beq v1, a0, L70
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_6;}                           // branch non-likely

  bc = c->sgpr64(v1) == 0;                          // beq v1, r0, L82
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_33;}                          // branch non-likely


  block_6:
  c->lw(a0, 104, s5);                               // lw a0, 104(s5)
  c->andi(v1, a0, 64);                              // andi v1, a0, 64
  c->xor_(a0, a0, v1);                              // xor a0, a0, v1
  bc = c->sgpr64(v1) == 0;                          // beq v1, r0, L83
  c->sw(a0, 104, s5);                               // sw a0, 104(s5)
  if (bc) {goto block_34;}                          // branch non-likely

  c->lw(v1, 124, s5);                               // lw v1, 124(s5)
  //beq r0, r0, L83                                 // beq r0, r0, L83
  c->sw(v1, 44, s4);                                // sw v1, 44(s4)
  goto block_34;                                    // branch always


  block_8:
  c->lw(v1, 100, s5);                               // lw v1, 100(s5)
  c->addiu(a0, r0, -1);                             // addiu a0, r0, -1
  bc = c->sgpr64(v1) == c->sgpr64(a0);              // beq v1, a0, L72
  c->lq(a0, 32, sp);                                // lq a0, 32(sp)
  if (bc) {goto block_11;}                          // branch non-likely

  c->dsubu(a0, v1, a0);                             // dsubu a0, v1, a0
  bc = c->sgpr64(v1) == 0;                          // beq v1, r0, L82
  c->pmaxw(v1, a0, r0);                             // pmaxw v1, a0, r0
  if (bc) {goto block_33;}                          // branch non-likely

  c->sw(v1, 100, s5);                               // sw v1, 100(s5)

  block_11:
  c->lw(a0, 104, s5);                               // lw a0, 104(s5)
  c->andi(v1, a0, 64);                              // andi v1, a0, 64
  c->xor_(a0, a0, v1);                              // xor a0, a0, v1
  bc = c->sgpr64(v1) == 0;                          // beq v1, r0, L73
  c->sw(a0, 104, s5);                               // sw a0, 104(s5)
  if (bc) {goto block_13;}                          // branch non-likely

  c->lw(v1, 124, s5);                               // lw v1, 124(s5)
  c->sw(v1, 44, s4);                                // sw v1, 44(s4)

  block_13:
  c->lw(t9, 112, s5);                               // lw t9, 112(s5)
  bc = c->sgpr64(t9) == 0;                          // beq t9, r0, L74
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_15;}                          // branch non-likely

  c->daddiu(sp, sp, -96);                           // daddiu sp, sp, -96
  c->sq(gp, 0, sp);                                 // sq gp, 0(sp)
  c->sq(s5, 16, sp);                                // sq s5, 16(sp)
  c->sq(s4, 32, sp);                                // sq s4, 32(sp)
  c->sq(s0, 48, sp);                                // sq s0, 48(sp)
  c->sq(s3, 64, sp);                                // sq s3, 64(sp)
  c->mov64(a0, gp);                                 // or a0, gp, r0
  c->mov64(a1, s5);                                 // or a1, s5, r0
  c->mov64(a2, s4);                                 // or a2, s4, r0
  call_addr = c->gprs[t9].du32[0];                  // function call:
  c->sq(s2, 80, sp);                                // sq s2, 80(sp)
  c->jalr(call_addr);                               // jalr ra, t9
  c->lq(gp, 0, sp);                                 // lq gp, 0(sp)
  c->lq(s5, 16, sp);                                // lq s5, 16(sp)
  c->lq(s4, 32, sp);                                // lq s4, 32(sp)
  c->lq(s0, 48, sp);                                // lq s0, 48(sp)
  c->lq(s3, 64, sp);                                // lq s3, 64(sp)
  c->lq(s2, 80, sp);                                // lq s2, 80(sp)
  c->daddiu(sp, sp, 96);                            // daddiu sp, sp, 96

  block_15:
  c->lw(a1, 120, s5);                               // lw a1, 120(s5)
  c->lw(v1, 116, s5);                               // lw v1, 116(s5)
  bc = c->sgpr64(a1) == 0;                          // beq a1, r0, L75
  c->lq(a0, 32, sp);                                // lq a0, 32(sp)
  if (bc) {goto block_18;}                          // branch non-likely

  c->dsubu(v1, v1, a0);                             // dsubu v1, v1, a0
  bc = ((s64)c->sgpr64(v1)) >= 0;                   // bgez v1, L75
  c->sw(v1, 116, s5);                               // sw v1, 116(s5)
  if (bc) {goto block_18;}                          // branch non-likely

  c->daddiu(sp, sp, -96);                           // daddiu sp, sp, -96
  c->sq(gp, 0, sp);                                 // sq gp, 0(sp)
  c->sq(s5, 16, sp);                                // sq s5, 16(sp)
  c->sq(s4, 32, sp);                                // sq s4, 32(sp)
  c->sq(s0, 48, sp);                                // sq s0, 48(sp)
  c->sq(s3, 64, sp);                                // sq s3, 64(sp)
  c->sq(s2, 80, sp);                                // sq s2, 80(sp)
  c->mov64(a0, gp);                                 // or a0, gp, r0
  c->mov64(a3, s4);                                 // or a3, s4, r0
  c->mov64(a2, s5);                                 // or a2, s5, r0
  c->load_symbol(t9, cache.sp_relaunch_particle_3d);// lw t9, sp-relaunch-particle-3d(s7)
  call_addr = c->gprs[t9].du32[0];                  // function call:
  c->sll(v0, ra, 0);                                // sll v0, ra, 0
  c->jalr(call_addr);                               // jalr ra, t9
  c->lq(gp, 0, sp);                                 // lq gp, 0(sp)
  c->lq(s5, 16, sp);                                // lq s5, 16(sp)
  c->lq(s4, 32, sp);                                // lq s4, 32(sp)
  c->lq(s0, 48, sp);                                // lq s0, 48(sp)
  c->lq(s3, 64, sp);                                // lq s3, 64(sp)
  c->lq(s2, 80, sp);                                // lq s2, 80(sp)
  c->daddiu(sp, sp, 96);                            // daddiu sp, sp, 96

  block_18:
  c->lqc2(vf8, 0, s4);                              // lqc2 vf8, 0(s4)
  c->lqc2(vf9, 16, s4);                             // lqc2 vf9, 16(s4)
  c->lqc2(vf10, 32, s4);                            // lqc2 vf10, 32(s4)
  c->lqc2(vf11, 16, s5);                            // lqc2 vf11, 16(s5)
  c->lqc2(vf12, 32, s5);                            // lqc2 vf12, 32(s5)
  c->lqc2(vf13, 48, s5);                            // lqc2 vf13, 48(s5)
  c->lqc2(vf14, 64, s5);                            // lqc2 vf14, 64(s5)
  c->lwc1(f0, 96, s5);                              // lwc1 f0, 96(s5)
  c->mfc1(v1, f0);                                  // mfc1 v1, f0
  c->vmul_bc(DEST::xyzw, BC::z, vf14, vf14, vf16);  // vmulz.xyzw vf14, vf14, vf16
  bc = c->sgpr64(v1) == 0;                          // beq v1, r0, L76
  c->vadd(DEST::xyz, vf11, vf11, vf14);             // vadd.xyz vf11, vf11, vf14
  if (bc) {goto block_20;}                          // branch non-likely

  c->mov128_vf_gpr(vf15, v1);                       // qmtc2.i vf15, v1
  c->vsub_bc(DEST::w, BC::x, vf15, vf0, vf15);      // vsubx.w vf15, vf0, vf15
  c->vmul_bc(DEST::xyzw, BC::w, vf15, vf15, vf16);  // vmulw.xyzw vf15, vf15, vf16
  c->vsub_bc(DEST::w, BC::w, vf15, vf0, vf15);      // vsubw.w vf15, vf0, vf15
  c->vmul_bc(DEST::xyz, BC::w, vf11, vf11, vf15);   // vmulw.xyz vf11, vf11, vf15

  block_20:
  c->vmul_bc(DEST::xyzw, BC::y, vf17, vf11, vf16);  // vmuly.xyzw vf17, vf11, vf16
  c->vmul_bc(DEST::xyzw, BC::y, vf18, vf12, vf16);  // vmuly.xyzw vf18, vf12, vf16
  c->vmul_bc(DEST::xyzw, BC::y, vf19, vf13, vf16);  // vmuly.xyzw vf19, vf13, vf16
  c->vadd(DEST::xyzw, vf8, vf8, vf17);              // vadd.xyzw vf8, vf8, vf17
  c->vadd_bc(DEST::w, BC::w, vf9, vf9, vf18);       // vaddw.w vf9, vf9, vf18
  c->vadd(DEST::xyzw, vf10, vf10, vf19);            // vadd.xyzw vf10, vf10, vf19
  c->vmax_bc(DEST::xyzw, BC::x, vf10, vf10, vf0);   // vmaxx.xyzw vf10, vf10, vf0
  c->sqc2(vf11, 16, s5);                            // sqc2 vf11, 16(s5)
  c->sqc2(vf8, 0, s4);                              // sqc2 vf8, 0(s4)
  c->sqc2(vf9, 16, s4);                             // sqc2 vf9, 16(s4)
  c->sqc2(vf10, 32, s4);                            // sqc2 vf10, 32(s4)
  c->mov64(v1, s1);                                 // or v1, s1, r0
  c->mov64(a0, s4);                                 // or a0, s4, r0
  c->lwc1(f0, 16, a0);                              // lwc1 f0, 16(a0)
  c->lwc1(f1, 20, a0);                              // lwc1 f1, 20(a0)
  c->lwc1(f3, 24, a0);                              // lwc1 f3, 24(a0)
  c->swc1(f0, 0, v1);                               // swc1 f0, 0(v1)
  c->swc1(f1, 4, v1);                               // swc1 f1, 4(v1)
  c->swc1(f3, 8, v1);                               // swc1 f3, 8(v1)
  c->fprs[f2] = 1.0;                                // lwc1 f2, L157(fp)
  c->muls(f3, f3, f3);                              // mul.s f3, f3, f3
  c->subs(f2, f2, f3);                              // sub.s f2, f2, f3
  c->muls(f1, f1, f1);                              // mul.s f1, f1, f1
  c->subs(f1, f2, f1);                              // sub.s f1, f2, f1
  c->muls(f0, f0, f0);                              // mul.s f0, f0, f0
  c->subs(f0, f1, f0);                              // sub.s f0, f1, f0
  c->sqrts(f0, f0);                                 // sqrt.s f0, f0
  c->swc1(f0, 12, v1);                              // swc1 f0, 12(v1)
  c->mfc1(a0, f0);                                  // mfc1 a0, f0
  c->load_symbol(v1, cache.sp_frame_time);          // lw v1, *sp-frame-time*(s7)
  c->lwc1(f0, 0, v1);                               // lwc1 f0, 0(v1)
  c->mfc1(v1, f0);                                  // mfc1 v1, f0
  c->andi(v1, v1, 255);                             // andi v1, v1, 255
  c->daddiu(v1, v1, -10);                           // daddiu v1, v1, -10
  bc = ((s64)c->sgpr64(v1)) < 0;                    // bltz v1, L77
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_22;}                          // branch non-likely

  c->load_symbol(t9, cache.quaternion);             // lw t9, quaternion*!(s7)
  c->mov64(a0, s1);                                 // or a0, s1, r0
  c->mov64(a1, s1);                                 // or a1, s1, r0
  c->daddiu(a2, s5, 80);                            // daddiu a2, s5, 80
  call_addr = c->gprs[t9].du32[0];                  // function call:
  c->sll(v0, ra, 0);                                // sll v0, ra, 0
  c->jalr(call_addr);                               // jalr ra, t9

  block_22:
  c->load_symbol(t9, cache.quaternion);             // lw t9, quaternion*!(s7)
  c->mov64(a0, s1);                                 // or a0, s1, r0
  c->mov64(a1, s1);                                 // or a1, s1, r0
  c->daddiu(a2, s5, 80);                            // daddiu a2, s5, 80
  call_addr = c->gprs[t9].du32[0];                  // function call:
  c->sll(v0, ra, 0);                                // sll v0, ra, 0
  c->jalr(call_addr);                               // jalr ra, t9
  c->mov64(a0, s4);                                 // or a0, s4, r0
  c->mov64(v1, s1);                                 // or v1, s1, r0
  c->lwc1(f0, 12, v1);                              // lwc1 f0, 12(v1)
  c->mtc1(f1, r0);                                  // mtc1 f1, r0
  cop1_bc = c->fprs[f0] < c->fprs[f1];              // c.lt.s f0, f1
  bc = !cop1_bc;                                    // bc1f L78
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_24;}                          // branch non-likely

  c->lqc2(vf1, 16, a0);                             // lqc2 vf1, 16(a0)
  c->lqc2(vf2, 0, v1);                              // lqc2 vf2, 0(v1)
  c->vsub(DEST::xyz, vf1, vf0, vf2);                // vsub.xyz vf1, vf0, vf2
  c->sqc2(vf1, 16, a0);                             // sqc2 vf1, 16(a0)
  c->mov128_gpr_vf(a0, vf1);                        // qmfc2.i a0, vf1
  //beq r0, r0, L79                                 // beq r0, r0, L79
  // nop                                            // sll r0, r0, 0
  goto block_25;                                    // branch always


  block_24:
  c->lqc2(vf1, 16, a0);                             // lqc2 vf1, 16(a0)
  c->lqc2(vf2, 0, v1);                              // lqc2 vf2, 0(v1)
  c->vadd(DEST::xyz, vf1, vf0, vf2);                // vadd.xyz vf1, vf0, vf2
  c->sqc2(vf1, 16, a0);                             // sqc2 vf1, 16(a0)
  c->mov128_gpr_vf(a0, vf1);                        // qmfc2.i a0, vf1

  block_25:
  c->mov128_gpr_vf(v1, vf10);                       // qmfc2.i v1, vf10
  c->lw(a0, 104, s5);                               // lw a0, 104(s5)
  c->andi(a1, a0, 2);                               // andi a1, a0, 2
  bc = c->sgpr64(a1) == 0;                          // beq a1, r0, L80
  c->andi(a1, a0, 4);                               // andi a1, a0, 4
  if (bc) {goto block_28;}                          // branch non-likely

  bc = c->sgpr64(v1) != 0;                          // bne v1, r0, L80
  c->pextuw(a2, v1, r0);                            // pextuw a2, v1, r0
  if (bc) {goto block_28;}                          // branch non-likely

  bc = c->sgpr64(a2) == 0;                          // beq a2, r0, L82
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_33;}                          // branch non-likely


  block_28:
  bc = c->sgpr64(a1) == 0;                          // beq a1, r0, L81
  c->andi(a0, a0, 1);                               // andi a0, a0, 1
  if (bc) {goto block_30;}                          // branch non-likely

  c->pcpyud(v1, v1, r0);                            // pcpyud v1, v1, r0
  c->pexew(v1, v1);                                 // pexew v1, v1
  bc = ((s64)c->sgpr64(v1)) <= 0;                   // blez v1, L82
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_33;}                          // branch non-likely


  block_30:
  bc = c->sgpr64(a0) == 0;                          // beq a0, r0, L83
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_34;}                          // branch non-likely

  c->mov128_gpr_vf(v1, vf8);                        // qmfc2.i v1, vf8
  c->pcpyud(v1, v1, r0);                            // pcpyud v1, v1, r0
  c->pexew(v1, v1);                                 // pexew v1, v1
  bc = ((s64)c->sgpr64(v1)) < 0;                    // bltz v1, L82
  c->mov128_gpr_vf(v1, vf9);                        // qmfc2.i v1, vf9
  if (bc) {goto block_33;}                          // branch non-likely

  c->pcpyud(v1, v1, r0);                            // pcpyud v1, v1, r0
  c->pexew(v1, v1);                                 // pexew v1, v1
  bc = ((s64)c->sgpr64(v1)) >= 0;                   // bgez v1, L83
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_34;}                          // branch non-likely


  block_33:
  c->load_symbol(t9, cache.sp_free_particle);       // lw t9, sp-free-particle(s7)
  c->mov64(a0, gp);                                 // or a0, gp, r0
  c->mov64(a1, s0);                                 // or a1, s0, r0
  c->mov64(a2, s5);                                 // or a2, s5, r0
  c->mov64(a3, s4);                                 // or a3, s4, r0
  call_addr = c->gprs[t9].du32[0];                  // function call:
  c->sll(v0, ra, 0);                                // sll v0, ra, 0
  c->jalr(call_addr);                               // jalr ra, t9

  block_34:
  c->daddiu(s3, s3, -1);                            // daddiu s3, s3, -1
  c->daddiu(s5, s5, 144);                           // daddiu s5, s5, 144
  c->daddiu(s4, s4, 48);                            // daddiu s4, s4, 48
  bc = c->sgpr64(s3) != 0;                          // bne s3, r0, L69
  c->daddiu(s0, s0, 1);                             // daddiu s0, s0, 1
  if (bc) {goto block_1;}                           // branch non-likely

  c->mov64(v0, s0);                                 // or v0, s0, r0
  c->ld(ra, 0, sp);                                 // ld ra, 0(sp)
  c->ld(fp, 8, sp);                                 // ld fp, 8(sp)
  c->lq(gp, 144, sp);                               // lq gp, 144(sp)
  c->lq(s5, 128, sp);                               // lq s5, 128(sp)
  c->lq(s4, 112, sp);                               // lq s4, 112(sp)
  c->lq(s3, 96, sp);                                // lq s3, 96(sp)
  c->lq(s2, 80, sp);                                // lq s2, 80(sp)
  c->lq(s1, 64, sp);                                // lq s1, 64(sp)
  c->lq(s0, 48, sp);                                // lq s0, 48(sp)
  //jr ra                                           // jr ra
  c->daddiu(sp, sp, 160);                           // daddiu sp, sp, 160
  goto end_of_function;                             // return

  // nop                                            // sll r0, r0, 0
  // nop                                            // sll r0, r0, 0
  // nop                                            // sll r0, r0, 0
  end_of_function:
  return c->gprs[v0].du64[0];
}

void link() {
  cache.sp_frame_time = intern_from_c("*sp-frame-time*").c();
  cache.quaternion = intern_from_c("quaternion*!").c();
  cache.sp_free_particle = intern_from_c("sp-free-particle").c();
  cache.sp_relaunch_particle_3d = intern_from_c("sp-relaunch-particle-3d").c();
  gLinkedFunctionTable.reg("sp-process-block-3d", execute, 256);
}

} // namespace sp_process_block_3d
} // namespace Mips2C

//--------------------------MIPS2C---------------------
#include "game/mips2c/mips2c_private.h"

namespace Mips2C::jak1 {
namespace sp_process_block_2d {
struct Cache {
  void* sp_frame_time; // *sp-frame-time*
  void* sp_free_particle; // sp-free-particle
  void* sp_orbiter; // sp-orbiter
  void* sp_relaunch_particle_2d; // sp-relaunch-particle-2d
} cache;

u64 execute(void* ctxt) {
  auto* c = (ExecutionContext*)ctxt;
  bool bc = false;
  u32 call_addr = 0;
  bool geco_log_this_relaunch = false;  // Geco-spheres TEMPORARY diagnostic
  bool geco_log_this_orb = false;       // Geco-spheres TEMPORARY diagnostic
  c->daddiu(sp, sp, -128);                          // daddiu sp, sp, -128
  c->sd(ra, 0, sp);                                 // sd ra, 0(sp)
  c->sq(s0, 16, sp);                                // sq s0, 16(sp)
  c->sq(s1, 32, sp);                                // sq s1, 32(sp)
  c->sq(s2, 48, sp);                                // sq s2, 48(sp)
  c->sq(s3, 64, sp);                                // sq s3, 64(sp)
  c->sq(s4, 80, sp);                                // sq s4, 80(sp)
  c->sq(s5, 96, sp);                                // sq s5, 96(sp)
  c->sq(gp, 112, sp);                               // sq gp, 112(sp)
  c->mov64(gp, a0);                                 // or gp, a0, r0
  c->mov64(s5, a1);                                 // or s5, a1, r0
  c->mov64(s4, a2);                                 // or s4, a2, r0
  c->mov64(s1, a3);                                 // or s1, a3, r0
  c->mov64(s3, t0);                                 // or s3, t0, r0
  c->mov64(s2, t1);                                 // or s2, t1, r0
  c->load_symbol(v1, cache.sp_frame_time);          // lw v1, *sp-frame-time*(s7)
  c->lqc2(vf9, 0, v1);                              // lqc2 vf9, 0(v1)
  c->mov128_gpr_vf(v1, vf9);                        // qmfc2.i v1, vf9
  c->andi(s0, v1, 255);                             // andi s0, v1, 255

  block_1:
  c->lw(v1, 128, s5);                               // lw v1, 128(s5)
#if defined(__aarch64__)
  // Gbirds-anim (arm64): mirror the sp_process_block_3d block_1 fix onto the 2D block,
  // which was never given it. `beq v1, s7` tests "(-> cpuinfo valid) == #f?" (skip dead
  // slot); `beq s2, s7` is the (paused?) #f-check that routes a LIVE particle to block_8,
  // the func-dispatch path. On arm64 a full-64 `sgpr64` compare MISSES #f (a GOAL ptr
  // loaded via sign-extended `lw` is the bare low-32 offset while gpr s7 is the full host
  // symbol base), so a live 2D bird never takes s2==#f -> block_8 -> its bird-bob-func
  // (+112) never dispatches -> the title sagehut-seagulls render but stay frozen (no bob).
  // Compare the representation-agnostic 32-bit GOAL ptr (low32), exactly like the 3D block.
  bc = c->gpr_addr(v1) == c->gpr_addr(s7);          // beq v1, s7 (32-bit GOAL ptr)
#else
  bc = c->sgpr64(v1) == c->sgpr64(s7);              // beq v1, s7, L97
#endif
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_31;}                          // branch non-likely

#if defined(__aarch64__)
  bc = c->gpr_addr(s2) == c->gpr_addr(s7);          // beq s2, s7 (32-bit GOAL ptr; (paused?) #f-check)
#else
  bc = c->sgpr64(s2) == c->sgpr64(s7);              // beq s2, s7, L87
#endif
  c->lw(v1, 104, s5);                               // lw v1, 104(s5)
  if (bc) {goto block_8;}                           // branch non-likely

  c->andi(v1, v1, 8192);                            // andi v1, v1, 8192
  bc = c->sgpr64(v1) != 0;                          // bne v1, r0, L87
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_8;}                           // branch non-likely

  c->lw(v1, 100, s5);                               // lw v1, 100(s5)
  c->addiu(a0, r0, -1);                             // addiu a0, r0, -1
  bc = c->sgpr64(v1) == c->sgpr64(a0);              // beq v1, a0, L86
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_6;}                           // branch non-likely

  bc = c->sgpr64(v1) == 0;                          // beq v1, r0, L96
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_30;}                          // branch non-likely


  block_6:
  c->lw(a0, 104, s5);                               // lw a0, 104(s5)
  c->andi(v1, a0, 64);                              // andi v1, a0, 64
  c->xor_(a0, a0, v1);                              // xor a0, a0, v1
  bc = c->sgpr64(v1) == 0;                          // beq v1, r0, L97
  c->sw(a0, 104, s5);                               // sw a0, 104(s5)
  if (bc) {goto block_31;}                          // branch non-likely

  c->lw(v1, 124, s5);                               // lw v1, 124(s5)
  //beq r0, r0, L97                                 // beq r0, r0, L97
  c->sw(v1, 44, s4);                                // sw v1, 44(s4)
  goto block_31;                                    // branch always


  block_8:
  c->lw(v1, 100, s5);                               // lw v1, 100(s5)
  c->addiu(a0, r0, -1);                             // addiu a0, r0, -1
  bc = c->sgpr64(v1) == c->sgpr64(a0);              // beq v1, a0, L88
  c->dsubu(a0, v1, s0);                             // dsubu a0, v1, s0
  if (bc) {goto block_11;}                          // branch non-likely

  bc = c->sgpr64(v1) == 0;                          // beq v1, r0, L96
  c->pmaxw(v1, a0, r0);                             // pmaxw v1, a0, r0
  if (bc) {goto block_30;}                          // branch non-likely

  c->sw(v1, 100, s5);                               // sw v1, 100(s5)

  block_11:
  c->lw(a0, 104, s5);                               // lw a0, 104(s5)
  c->andi(v1, a0, 64);                              // andi v1, a0, 64
  c->xor_(a0, a0, v1);                              // xor a0, a0, v1
  bc = c->sgpr64(v1) == 0;                          // beq v1, r0, L89
  c->sw(a0, 104, s5);                               // sw a0, 104(s5)
  if (bc) {goto block_13;}                          // branch non-likely

  c->lw(v1, 124, s5);                               // lw v1, 124(s5)
  c->sw(v1, 44, s4);                                // sw v1, 44(s4)

  block_13:
  c->lw(t9, 112, s5);                               // lw t9, 112(s5)
  bc = c->sgpr64(t9) == 0;                          // beq t9, r0, L90
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_15;}                          // branch non-likely

  c->daddiu(sp, sp, -80);                           // daddiu sp, sp, -80
  c->sq(gp, 0, sp);                                 // sq gp, 0(sp)
  c->sq(s5, 16, sp);                                // sq s5, 16(sp)
  c->sq(s4, 32, sp);                                // sq s4, 32(sp)
  c->sq(s1, 48, sp);                                // sq s1, 48(sp)
  c->mov64(a0, gp);                                 // or a0, gp, r0
  c->mov64(a1, s5);                                 // or a1, s5, r0
  c->mov64(a2, s4);                                 // or a2, s4, r0
  call_addr = c->gprs[t9].du32[0];                  // function call:
  c->sq(s3, 64, sp);                                // sq s3, 64(sp)
  c->jalr(call_addr);                               // jalr ra, t9
  c->lq(gp, 0, sp);                                 // lq gp, 0(sp)
  c->lq(s5, 16, sp);                                // lq s5, 16(sp)
  c->lq(s4, 32, sp);                                // lq s4, 32(sp)
  c->lq(s1, 48, sp);                                // lq s1, 48(sp)
  c->lq(s3, 64, sp);                                // lq s3, 64(sp)
  c->daddiu(sp, sp, 80);                            // daddiu sp, sp, 80
  // Geco-spheres TEMPORARY diagnostic: the per-particle GOAL :func (e.g.
  // eco-fadeout, arm64-goalc-compiled) just ran; it is supposed to REFILL
  // next-time (cpuinfo+116) each frame to postpone the relaunch-to-fadeout.
  // Log what it left there (x86-vs-device diff). Gated like SPART-INIT.
  if (geco_spart_dump_armed()) {
    static int s_count = 0;
    if (s_count < 8000) {
      s_count++;
      u32 fn = 0, nt = 0, nl = 0;
      memcpy(&fn, g_ee_main_mem + c->gpr_addr(s5) + 112, 4);
      memcpy(&nt, g_ee_main_mem + c->gpr_addr(s5) + 116, 4);
      memcpy(&nl, g_ee_main_mem + c->gpr_addr(s5) + 120, 4);
      printf("SPART-FUNC cpu=%x fn=%x nt=%u nl=%x\n", c->gpr_addr(s5), fn, nt, nl);
      fflush(stdout);
    }
  }

  block_15:
  c->lw(a1, 120, s5);                               // lw a1, 120(s5)
  c->lw(v1, 116, s5);                               // lw v1, 116(s5)
  bc = c->sgpr64(a1) == 0;                          // beq a1, r0, L91
  c->dsubu(a0, v1, s0);                             // dsubu a0, v1, s0
  if (bc) {goto block_18;}                          // branch non-likely

  c->daddiu(v1, a0, -1);                            // daddiu v1, a0, -1
  bc = ((s64)c->sgpr64(v1)) >= 0;                   // bgez v1, L91
  c->sw(a0, 116, s5);                               // sw a0, 116(s5)
  if (bc) {goto block_18;}                          // branch non-likely

  c->daddiu(sp, sp, -96);                           // daddiu sp, sp, -96
  c->sq(gp, 0, sp);                                 // sq gp, 0(sp)
  c->sq(s5, 16, sp);                                // sq s5, 16(sp)
  c->sq(s4, 32, sp);                                // sq s4, 32(sp)
  c->sq(s1, 48, sp);                                // sq s1, 48(sp)
  c->sq(s3, 64, sp);                                // sq s3, 64(sp)
  c->sq(s2, 80, sp);                                // sq s2, 80(sp)
  c->mov64(a0, gp);                                 // or a0, gp, r0
  c->mov64(a3, s4);                                 // or a3, s4, r0
  c->mov64(a2, s5);                                 // or a2, s5, r0
  // Geco-spheres TEMPORARY diagnostic: a 2D particle's next-time countdown just
  // expired -> it relaunches into its next-launcher (the fadeout stage). On x86
  // this only happens when intended; if the arm64-compiled :func failed to
  // postpone, a relaunch STORM shows up here. Log cpuinfo + its func + launcher.
  geco_log_this_relaunch = false;
  if (geco_spart_dump_armed()) {
    static int s_count = 0;
    if (s_count < 8000) {
      s_count++;
      geco_log_this_relaunch = true;
      u32 fn = 0, nl = 0;
      float pre[4], col[4];
      memcpy(&fn, g_ee_main_mem + c->gpr_addr(s5) + 112, 4);
      memcpy(&nl, g_ee_main_mem + c->gpr_addr(s5) + 120, 4);
      memcpy(pre, g_ee_main_mem + c->gpr_addr(s4) + 0, 16);
      memcpy(col, g_ee_main_mem + c->gpr_addr(s4) + 32, 16);
      printf("SPART-RELAUNCH cpu=%x fn=%x nl=%x pos=%.0f,%.0f,%.0f col=%.0f,%.0f,%.0f,%.0f\n",
             c->gpr_addr(s5), fn, nl, pre[0], pre[1], pre[2], col[0], col[1], col[2], col[3]);
      fflush(stdout);
    }
  }
  c->load_symbol(t9, cache.sp_relaunch_particle_2d);// lw t9, sp-relaunch-particle-2d(s7)
  call_addr = c->gprs[t9].du32[0];                  // function call:
  c->sll(v0, ra, 0);                                // sll v0, ra, 0
  c->jalr(call_addr);                               // jalr ra, t9
  c->lq(gp, 0, sp);                                 // lq gp, 0(sp)
  c->lq(s5, 16, sp);                                // lq s5, 16(sp)
  c->lq(s4, 32, sp);                                // lq s4, 32(sp)
  c->lq(s1, 48, sp);                                // lq s1, 48(sp)
  c->lq(s3, 64, sp);                                // lq s3, 64(sp)
  c->lq(s2, 80, sp);                                // lq s2, 80(sp)
  c->daddiu(sp, sp, 96);                            // daddiu sp, sp, 96
  // Geco-spheres TEMPORARY diagnostic: what did sp-relaunch-particle-2d
  // (GOAL-compiled, arm64-suspect) do to this particle? Pairs with the
  // SPART-RELAUNCH line above.
  if (geco_log_this_relaunch) {
    float post[4], col[4], vel[4];
    memcpy(post, g_ee_main_mem + c->gpr_addr(s4) + 0, 16);
    memcpy(col, g_ee_main_mem + c->gpr_addr(s4) + 32, 16);
    memcpy(vel, g_ee_main_mem + c->gpr_addr(s5) + 16, 16);
    printf("SPART-RELPOST cpu=%x pos=%.0f,%.0f,%.0f col=%.0f,%.0f,%.0f,%.0f vel=%g,%g,%g\n",
           c->gpr_addr(s5), post[0], post[1], post[2], col[0], col[1], col[2], col[3], vel[0],
           vel[1], vel[2]);
    fflush(stdout);
  }

  block_18:
  c->lqc2(vf1, 0, s4);                              // lqc2 vf1, 0(s4)
  c->lqc2(vf2, 16, s4);                             // lqc2 vf2, 16(s4)
  c->lqc2(vf3, 32, s4);                             // lqc2 vf3, 32(s4)
  c->lqc2(vf4, 16, s5);                             // lqc2 vf4, 16(s5)
  c->lqc2(vf5, 32, s5);                             // lqc2 vf5, 32(s5)
  c->lqc2(vf6, 48, s5);                             // lqc2 vf6, 48(s5)
  c->lqc2(vf7, 64, s5);                             // lqc2 vf7, 64(s5)
  c->lwc1(f0, 96, s5);                              // lwc1 f0, 96(s5)
  c->mfc1(v1, f0);                                  // mfc1 v1, f0
  c->vmul_bc(DEST::xyzw, BC::z, vf7, vf7, vf9);     // vmulz.xyzw vf7, vf7, vf9
  bc = c->sgpr64(v1) == 0;                          // beq v1, r0, L92
  c->vadd(DEST::xyz, vf4, vf4, vf7);                // vadd.xyz vf4, vf4, vf7
  if (bc) {goto block_20;}                          // branch non-likely

  c->mov128_vf_gpr(vf8, v1);                        // qmtc2.i vf8, v1
  c->vsub_bc(DEST::w, BC::x, vf8, vf0, vf8);        // vsubx.w vf8, vf0, vf8
  c->vmul_bc(DEST::xyzw, BC::w, vf8, vf8, vf9);     // vmulw.xyzw vf8, vf8, vf9
  c->vsub_bc(DEST::w, BC::w, vf8, vf0, vf8);        // vsubw.w vf8, vf0, vf8
  c->vmul_bc(DEST::xyz, BC::w, vf4, vf4, vf8);      // vmulw.xyz vf4, vf4, vf8

  block_20:
  c->vmul_bc(DEST::xyzw, BC::y, vf10, vf4, vf9);    // vmuly.xyzw vf10, vf4, vf9
  c->vmul_bc(DEST::xyzw, BC::y, vf11, vf5, vf9);    // vmuly.xyzw vf11, vf5, vf9
  c->vmul_bc(DEST::xyzw, BC::y, vf12, vf6, vf9);    // vmuly.xyzw vf12, vf6, vf9
  c->vadd(DEST::xyzw, vf1, vf1, vf10);              // vadd.xyzw vf1, vf1, vf10
  c->vadd(DEST::zw, vf2, vf2, vf11);                // vadd.zw vf2, vf2, vf11
  c->vadd(DEST::xyzw, vf3, vf3, vf12);              // vadd.xyzw vf3, vf3, vf12
  c->vmax_bc(DEST::xyzw, BC::x, vf3, vf3, vf0);     // vmaxx.xyzw vf3, vf3, vf0
  c->sqc2(vf4, 16, s5);                             // sqc2 vf4, 16(s5)
  c->sqc2(vf1, 0, s4);                              // sqc2 vf1, 0(s4)
  c->sqc2(vf2, 16, s4);                             // sqc2 vf2, 16(s4)
  c->sqc2(vf3, 32, s4);                             // sqc2 vf3, 32(s4)
  // Geco-spheres TEMPORARY diagnostic: per-frame evolution of eco-signature 2D
  // particles AFTER the aging stores — sprite pos/scale (s4+0..31), color quad
  // (s4+32), cpuinfo fade quad (s5+48). Eco filter: yellow-born sparkle
  // (r=g=255,b=0) or green cloud/shaft (b==0, g>=128, a<=64 while r<=128).
  if (geco_spart_dump_armed()) {
    static int s_count = 0;
    if (s_count < 8000) {
      float col[4], fade[4], pos[4], sc[4];
      memcpy(col, g_ee_main_mem + c->gpr_addr(s4) + 32, 16);
      memcpy(fade, g_ee_main_mem + c->gpr_addr(s5) + 48, 16);
      bool sparkle = col[0] > 200.f && col[1] > 200.f && col[2] == 0.f;
      bool greenish = col[2] == 0.f && col[1] >= 100.f && col[0] <= 130.f;
      if (sparkle || greenish || fade[0] < -1.f) {
        s_count++;
        memcpy(pos, g_ee_main_mem + c->gpr_addr(s4) + 0, 16);
        memcpy(sc, g_ee_main_mem + c->gpr_addr(s4) + 16, 16);
        printf("SPART-AGE cpu=%x col=%.1f,%.1f,%.1f,%.1f fade=%.3f,%.3f,%.3f,%.3f pos=%.0f,%.0f,%.0f sxy=%.1f,%.1f\n",
               c->gpr_addr(s5), col[0], col[1], col[2], col[3], fade[0], fade[1], fade[2], fade[3],
               pos[0], pos[1], pos[2], sc[0], sc[3]);
        fflush(stdout);
      }
    }
  }
  c->lwc1(f0, 24, s4);                              // lwc1 f0, 24(s4)
  c->cvtws(f0, f0);                                 // cvt.w.s f0, f0
  c->mfc1(v1, f0);                                  // mfc1 v1, f0
  c->dsll32(v1, v1, 16);                            // dsll32 v1, v1, 16
  c->dsra32(v1, v1, 16);                            // dsra32 v1, v1, 16
  c->mtc1(f0, v1);                                  // mtc1 f0, v1
  c->cvtsw(f0, f0);                                 // cvt.s.w f0, f0
  c->swc1(f0, 24, s4);                              // swc1 f0, 24(s4)
  c->lw(v1, 104, s5);                               // lw v1, 104(s5)
  c->andi(v1, v1, 128);                             // andi v1, v1, 128
  bc = c->sgpr64(v1) == 0;                          // beq v1, r0, L93
  c->load_symbol(t9, cache.sp_orbiter);             // lw t9, sp-orbiter(s7)
  if (bc) {goto block_22;}                          // branch non-likely

  // Geco-spheres TEMPORARY diagnostic (attempt 2, DECISIVE): sp-orbiter is the
  // bit7 orbit-update (GOAL-compiled, arm64-suspect) that positions every eco
  // cloud/starflash particle around its bound center each frame. Dump its full
  // input state here and the resulting sprite position after the call; the
  // x86-vs-device first-divergent-field names the broken computation.
  geco_log_this_orb = false;
  if (geco_spart_dump_armed()) {
    static int s_count = 0;
    if (s_count < 20000) {
      s_count++;
      geco_log_this_orb = true;
      float rad = 0.f, om = 0.f, vsx[4], rq[4], pre[4], col[4];
      u32 usr = 0;
      memcpy(&rad, g_ee_main_mem + c->gpr_addr(s5) + 8, 4);   // radius
      memcpy(&om, g_ee_main_mem + c->gpr_addr(s5) + 12, 4);   // omega
      memcpy(vsx, g_ee_main_mem + c->gpr_addr(s5) + 16, 16);  // vel-sxvel
      memcpy(rq, g_ee_main_mem + c->gpr_addr(s5) + 80, 16);   // rotvel3d quat
      memcpy(&usr, g_ee_main_mem + c->gpr_addr(s5) + 108, 4); // user-pntr = orbit center
      memcpy(pre, g_ee_main_mem + c->gpr_addr(s4) + 0, 16);   // sprite pos pre
      memcpy(col, g_ee_main_mem + c->gpr_addr(s4) + 32, 16);  // sprite rgba
      float ctr[3] = {0.f, 0.f, 0.f};
      if (usr > 16 && usr < (u32)(EE_MAIN_MEM_SIZE - 12)) {
        memcpy(ctr, g_ee_main_mem + usr, 12);
      }
      float sfty = 0.f;
      {
        u32 v = 0;
        memcpy(&v, cache.sp_frame_time, 4);
        if (v > 16 && v < (u32)(EE_MAIN_MEM_SIZE - 8)) {
          memcpy(&sfty, g_ee_main_mem + v + 4, 4);
        }
      }
      printf("SPART-ORBPRE cpu=%x om=%g rad=%g vsx=%g,%g,%g sfty=%g rq=%g,%g,%g,%g usr=%x "
             "ctr=%g,%g,%g pre=%g,%g,%g col=%.0f,%.0f,%.0f,%.0f\n",
             c->gpr_addr(s5), om, rad, vsx[0], vsx[1], vsx[2], sfty, rq[0], rq[1], rq[2], rq[3],
             usr, ctr[0], ctr[1], ctr[2], pre[0], pre[1], pre[2], col[0], col[1], col[2], col[3]);
      fflush(stdout);
    }
  }
  c->daddiu(sp, sp, -96);                           // daddiu sp, sp, -96
  c->sq(gp, 0, sp);                                 // sq gp, 0(sp)
  c->sq(s5, 16, sp);                                // sq s5, 16(sp)
  c->sq(s4, 32, sp);                                // sq s4, 32(sp)
  c->sq(s1, 48, sp);                                // sq s1, 48(sp)
  c->sq(s3, 64, sp);                                // sq s3, 64(sp)
  c->mov64(a0, gp);                                 // or a0, gp, r0
  c->mov64(a1, s5);                                 // or a1, s5, r0
  c->mov64(a2, s4);                                 // or a2, s4, r0
  call_addr = c->gprs[t9].du32[0];                  // function call:
  c->sq(s2, 80, sp);                                // sq s2, 80(sp)
  c->jalr(call_addr);                               // jalr ra, t9
  c->lq(gp, 0, sp);                                 // lq gp, 0(sp)
  c->lq(s5, 16, sp);                                // lq s5, 16(sp)
  c->lq(s4, 32, sp);                                // lq s4, 32(sp)
  c->lq(s1, 48, sp);                                // lq s1, 48(sp)
  c->lq(s3, 64, sp);                                // lq s3, 64(sp)
  c->lq(s2, 80, sp);                                // lq s2, 80(sp)
  c->daddiu(sp, sp, 96);                            // daddiu sp, sp, 96
  // Geco-spheres TEMPORARY diagnostic: what sp-orbiter left behind. Pairs with
  // the SPART-ORBPRE line above (same cpu=).
  if (geco_log_this_orb) {
    float rad = 0.f, om = 0.f, rq[4], post[4];
    memcpy(&rad, g_ee_main_mem + c->gpr_addr(s5) + 8, 4);
    memcpy(&om, g_ee_main_mem + c->gpr_addr(s5) + 12, 4);
    memcpy(rq, g_ee_main_mem + c->gpr_addr(s5) + 80, 16);
    memcpy(post, g_ee_main_mem + c->gpr_addr(s4) + 0, 16);
    printf("SPART-ORBPOST cpu=%x om=%g rad=%g rq=%g,%g,%g,%g post=%g,%g,%g\n", c->gpr_addr(s5),
           om, rad, rq[0], rq[1], rq[2], rq[3], post[0], post[1], post[2]);
    fflush(stdout);
  }

  block_22:
  c->lq(v1, 32, s4);                                // lq v1, 32(s4)
  c->lw(a0, 104, s5);                               // lw a0, 104(s5)
  c->andi(a1, a0, 2);                               // andi a1, a0, 2
  bc = c->sgpr64(a1) == 0;                          // beq a1, r0, L94
  c->andi(a1, a0, 4);                               // andi a1, a0, 4
  if (bc) {goto block_25;}                          // branch non-likely

  bc = c->sgpr64(v1) != 0;                          // bne v1, r0, L94
  c->pextuw(t4, v1, r0);                            // pextuw t4, v1, r0
  if (bc) {goto block_25;}                          // branch non-likely

  bc = c->sgpr64(t4) == 0;                          // beq t4, r0, L96
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_30;}                          // branch non-likely


  block_25:
  bc = c->sgpr64(a1) == 0;                          // beq a1, r0, L95
  c->andi(a0, a0, 1);                               // andi a0, a0, 1
  if (bc) {goto block_27;}                          // branch non-likely

  c->pcpyud(t4, v1, r0);                            // pcpyud t4, v1, r0
  c->pexew(t4, t4);                                 // pexew t4, r0, t4
  bc = ((s64)c->sgpr64(t4)) <= 0;                   // blez t4, L96
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_30;}                          // branch non-likely


  block_27:
  bc = c->sgpr64(a0) == 0;                          // beq a0, r0, L97
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_31;}                          // branch non-likely

  c->mov128_gpr_vf(v1, vf1);                        // qmfc2.i v1, vf1
  c->pcpyud(v1, v1, r0);                            // pcpyud v1, v1, r0
  c->pexew(v1, v1);                                 // pexew v1, r0, v1
  bc = ((s64)c->sgpr64(v1)) < 0;                    // bltz v1, L96
  c->mov128_gpr_vf(v1, vf2);                        // qmfc2.i v1, vf2
  if (bc) {goto block_30;}                          // branch non-likely

  c->pcpyud(v1, v1, r0);                            // pcpyud v1, v1, r0
  c->pexew(v1, v1);                                 // pexew v1, r0, v1
  bc = ((s64)c->sgpr64(v1)) >= 0;                   // bgez v1, L97
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_31;}                          // branch non-likely

  block_30:
  c->load_symbol(t9, cache.sp_free_particle);       // lw t9, sp-free-particle(s7)
  c->mov64(a0, gp);                                 // or a0, gp, r0
  c->mov64(a1, s1);                                 // or a1, s1, r0
  c->mov64(a2, s5);                                 // or a2, s5, r0
  c->mov64(a3, s4);                                 // or a3, s4, r0
  call_addr = c->gprs[t9].du32[0];                  // function call:
  c->sll(v0, ra, 0);                                // sll v0, ra, 0
  c->jalr(call_addr);                               // jalr ra, t9

  block_31:
  c->daddiu(s3, s3, -1);                            // daddiu s3, s3, -1
  c->daddiu(s5, s5, 144);                           // daddiu s5, s5, 144
  c->daddiu(s4, s4, 48);                            // daddiu s4, s4, 48
  bc = c->sgpr64(s3) != 0;                          // bne s3, r0, L85
  c->daddiu(s1, s1, 1);                             // daddiu s1, s1, 1
  if (bc) {goto block_1;}                           // branch non-likely

  c->mov64(v0, s1);                                 // or v0, s1, r0
  c->ld(ra, 0, sp);                                 // ld ra, 0(sp)
  c->lq(gp, 112, sp);                               // lq gp, 112(sp)
  c->lq(s5, 96, sp);                                // lq s5, 96(sp)
  c->lq(s4, 80, sp);                                // lq s4, 80(sp)
  c->lq(s3, 64, sp);                                // lq s3, 64(sp)
  c->lq(s2, 48, sp);                                // lq s2, 48(sp)
  c->lq(s1, 32, sp);                                // lq s1, 32(sp)
  c->lq(s0, 16, sp);                                // lq s0, 16(sp)
  //jr ra                                           // jr ra
  c->daddiu(sp, sp, 128);                           // daddiu sp, sp, 128
  goto end_of_function;                             // return

  // nop                                            // sll r0, r0, 0
  // nop                                            // sll r0, r0, 0
  // nop                                            // sll r0, r0, 0
  end_of_function:
  return c->gprs[v0].du64[0];
}

void link() {
  cache.sp_frame_time = intern_from_c("*sp-frame-time*").c();
  cache.sp_free_particle = intern_from_c("sp-free-particle").c();
  cache.sp_orbiter = intern_from_c("sp-orbiter").c();
  cache.sp_relaunch_particle_2d = intern_from_c("sp-relaunch-particle-2d").c();
  gLinkedFunctionTable.reg("sp-process-block-2d", execute, 256);
}

} // namespace sp_process_block_2d
} // namespace Mips2C
