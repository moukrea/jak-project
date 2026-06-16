//--------------------------MIPS2C---------------------
#include <array>
#include <atomic>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <unordered_map>

#include "game/kernel/jak1/kscheme.h"
#include "game/mips2c/mips2c_private.h"
#ifdef __ANDROID__
#include <sys/system_properties.h>
#include <unistd.h>

#include "common/util/FileUtil.h"
#endif
using namespace jak1;
// clang-format off

// Gcine-pose objective joint-sanity tripwire (arm64-only). The cinematic
// character skeletons come out with NaN bone matrices on arm64 (x86 renders
// them correctly): the per-joint quaternion the animation decompressor feeds
// to cspace<-parented-transformq-joint! is zero/garbage, so
// normalize_frame_quaternions does 1/sqrt(0)=inf, 0*inf=NaN, and the NaN
// rotation/translation flows into the bone matrix and propagates parent->child
// (the owner-reported cinematic "pose blink"). These counters measure it
// objectively: g_nan = bad bone matrices written this frame (cspace),
// g_norm_nan = NaN quaternions emitted by normalize. A per-render-frame tick
// (android_gfx.cpp) buckets them into "glitch frames". g_skips counts the
// leftover A37 suspicious-skip (which never fires here). Armed by
// debug.opengoal.gpose.tripwire=1 / OG_GPOSE / a `gpose` marker file.
#ifdef __aarch64__
namespace gpose {
std::atomic<unsigned> g_calls{0};
std::atomic<unsigned> g_skips{0};
std::atomic<unsigned> g_nan{0};
std::atomic<unsigned> g_norm_nan{0};
std::atomic<unsigned> g_glitch_frames{0};
std::atomic<unsigned long long> g_total_skips{0};
std::atomic<int> g_skip_log{0};
std::atomic<int> g_nan_log{0};
std::atomic<int> g_norm_log{0};
std::atomic<int> g_root_log{0};
std::atomic<unsigned long long> g_repaired{0};
std::atomic<int> g_repaired_log{0};
inline bool enabled() {
  static const bool s_on = [] {
    if (getenv("OG_GPOSE")) {
      return true;
    }
#ifdef __ANDROID__
    char buf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.gpose.tripwire", buf) > 0 && buf[0] == '1') {
      fprintf(stderr, "GPOSE tripwire armed (prop)\n");
      return true;
    }
    auto p = file_util::get_jak_project_dir() / "gpose";
    if (access(p.string().c_str(), F_OK) == 0) {
      fprintf(stderr, "GPOSE tripwire armed (%s)\n", p.string().c_str());
      return true;
    }
#endif
    return false;
  }();
  return s_on;
}
}  // namespace gpose
#endif  // __aarch64__

namespace {
struct Cache {
  void* clear_frame_accumulator; // clear-frame-accumulator
  void* decompress_fixed_data_to_accumulator; // decompress-fixed-data-to-accumulator
  void* decompress_frame_data_pair_to_accumulator; // decompress-frame-data-pair-to-accumulator
  void* decompress_frame_data_to_accumulator; // decompress-frame-data-to-accumulator
  void* normalize_frame_quaternions; // normalize-frame-quaternions
  void* fake_scratchpad_data;  // *fake-scratchpad-data*

} cache;
}

namespace Mips2C::jak1 {
namespace decompress_frame_data_pair_to_accumulator {
u64 execute(void* ctxt) {
  auto* c = (ExecutionContext*)ctxt;
  bool bc = false;
  u32 next_block = 0;
  while(true) {
    switch(next_block) {

      case 0:
        next_block = 1;
        c->daddiu(sp, sp, -64);                           // daddiu sp, sp, -64
        c->sq(a0, 0, sp);                                 // sq a0, 0(sp)
        c->sq(t7, 16, sp);                                // sq t7, 16(sp)
        c->sq(s0, 32, sp);                                // sq s0, 32(sp)
        c->sq(s1, 48, sp);                                // sq s1, 48(sp)
        c->mov128_vf_gpr(vf11, t0);                       // qmtc2.i vf11, t0
        c->daddu(a3, a3, a1);                             // daddu a3, a3, a1
        c->mov128_vf_gpr(vf13, a2);                       // qmtc2.i vf13, a2
        //c->lui(t2, 28672);                                // lui t2, 28672
        get_fake_spad_addr(t2, cache.fake_scratchpad_data, 0, c);
        c->lw(t4, 0, a1);                                 // lw t4, 0(a1)
        c->daddiu(v1, a1, 16);                            // daddiu v1, a1, 16
        c->lw(t5, 4, a1);                                 // lw t5, 4(a1)
        c->daddu(s5, t1, r0);                             // daddu s5, t1, r0
        c->lw(t6, 8, a1);                                 // lw t6, 8(a1)
        c->daddu(t4, t4, v1);                             // daddu t4, t4, v1
        c->vsub_bc(DEST::w, BC::x, vf11, vf0, vf11);      // vsubx.w vf11, vf0, vf11
        c->lw(t7, 0, a3);                                 // lw t7, 0(a3)
        c->vmul_bc(DEST::xyzw, BC::x, vf13, vf14, vf13);  // vmulx.xyzw vf13, vf14, vf13
        c->daddiu(t2, t2, 1760);                          // daddiu t2, t2, 1760
        c->lw(s2, 56, t1);                                // lw s2, 56(t1)
        c->daddu(t5, t5, v1);                             // daddu t5, t5, v1
        c->lw(s4, 60, t1);                                // lw s4, 60(t1)
        c->daddu(t6, t6, v1);                             // daddu t6, t6, v1
        c->addiu(s3, r0, 8);                              // addiu s3, r0, 8
        c->daddiu(s5, s5, 4);                             // daddiu s5, s5, 4
        c->vmul_bc(DEST::xy, BC::w, vf13, vf13, vf11);    // vmulw.xy vf13, vf13, vf11
        c->lw(s0, 4, a3);                                 // lw s0, 4(a3)
        c->vmul_bc(DEST::zw, BC::x, vf13, vf13, vf11);    // vmulx.zw vf13, vf13, vf11
        c->lw(s1, 8, a3);                                 // lw s1, 8(a3)
        // nop                                            // sll r0, r0, 0
        c->daddiu(v1, a3, 16);                            // daddiu v1, a3, 16
        c->daddu(t7, t7, v1);                             // daddu t7, t7, v1
        c->daddu(s0, s0, v1);                             // daddu s0, s0, v1
        c->daddu(s1, s1, v1);                             // daddu s1, s1, v1
        // nop                                            // sll r0, r0, 0
        c->andi(t3, s4, 1);                               // andi t3, s4, 1
        // nop                                            // sll r0, r0, 0
        bc = c->sgpr64(t3) == 0;                          // beq t3, r0, L10
        // nop                                            // sll r0, r0, 0
        if (bc) {next_block = 2;}                         // branch non-likely

        break;

      case 1:
        next_block = 2;
        c->lqc2(vf1, 0, t4);                              // lqc2 vf1, 0(t4)
        c->lqc2(vf2, 16, t4);                             // lqc2 vf2, 16(t4)
        c->lqc2(vf3, 32, t4);                             // lqc2 vf3, 32(t4)
        c->lqc2(vf4, 48, t4);                             // lqc2 vf4, 48(t4)
        c->lqc2(vf5, 0, t7);                              // lqc2 vf5, 0(t7)
        c->lqc2(vf6, 16, t7);                             // lqc2 vf6, 16(t7)
        c->lqc2(vf7, 32, t7);                             // lqc2 vf7, 32(t7)
        c->lqc2(vf8, 48, t7);                             // lqc2 vf8, 48(t7)
        c->lqc2(vf9, 0, a0);                              // lqc2 vf9, 0(a0)
        c->daddiu(t4, t4, 64);                            // daddiu t4, t4, 64
        c->lqc2(vf10, 16, a0);                            // lqc2 vf10, 16(a0)
        c->daddiu(t7, t7, 64);                            // daddiu t7, t7, 64
        c->lqc2(vf11, 32, a0);                            // lqc2 vf11, 32(a0)
        c->lqc2(vf12, 48, a0);                            // lqc2 vf12, 48(a0)
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf1, vf13);       // vmaddax.xyzw acc, vf1, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf9, vf5, vf13);   // vmaddw.xyzw vf9, vf5, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf2, vf13);       // vmaddax.xyzw acc, vf2, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf10, vf6, vf13);  // vmaddw.xyzw vf10, vf6, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf11, vf0);        // vmulaw.xyzw acc, vf11, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf3, vf13);       // vmaddax.xyzw acc, vf3, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf11, vf7, vf13);  // vmaddw.xyzw vf11, vf7, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf12, vf0);        // vmulaw.xyzw acc, vf12, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf4, vf13);       // vmaddax.xyzw acc, vf4, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf12, vf8, vf13);  // vmaddw.xyzw vf12, vf8, vf13
        c->sqc2(vf9, 0, a0);                              // sqc2 vf9, 0(a0)
        c->sqc2(vf10, 16, a0);                            // sqc2 vf10, 16(a0)
        c->sqc2(vf11, 32, a0);                            // sqc2 vf11, 32(a0)
        c->sqc2(vf12, 48, a0);                            // sqc2 vf12, 48(a0)

      case 2:
        next_block = 3;
        c->andi(t3, s4, 2);                               // andi t3, s4, 2
        c->daddiu(a0, a0, 64);                            // daddiu a0, a0, 64
        bc = c->sgpr64(t3) == 0;                          // beq t3, r0, L11
        // nop                                            // sll r0, r0, 0
        if (bc) {next_block = 4;}                         // branch non-likely

        break;

      case 3:
        next_block = 4;
        c->lqc2(vf1, 0, t4);                              // lqc2 vf1, 0(t4)
        c->lqc2(vf2, 16, t4);                             // lqc2 vf2, 16(t4)
        c->lqc2(vf3, 32, t4);                             // lqc2 vf3, 32(t4)
        c->lqc2(vf4, 48, t4);                             // lqc2 vf4, 48(t4)
        c->lqc2(vf5, 0, t7);                              // lqc2 vf5, 0(t7)
        c->lqc2(vf6, 16, t7);                             // lqc2 vf6, 16(t7)
        c->lqc2(vf7, 32, t7);                             // lqc2 vf7, 32(t7)
        c->lqc2(vf8, 48, t7);                             // lqc2 vf8, 48(t7)
        c->lqc2(vf9, 0, a0);                              // lqc2 vf9, 0(a0)
        c->daddiu(t4, t4, 64);                            // daddiu t4, t4, 64
        c->lqc2(vf10, 16, a0);                            // lqc2 vf10, 16(a0)
        c->daddiu(t7, t7, 64);                            // daddiu t7, t7, 64
        c->lqc2(vf11, 32, a0);                            // lqc2 vf11, 32(a0)
        c->lqc2(vf12, 48, a0);                            // lqc2 vf12, 48(a0)
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf1, vf13);       // vmaddax.xyzw acc, vf1, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf9, vf5, vf13);   // vmaddw.xyzw vf9, vf5, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf2, vf13);       // vmaddax.xyzw acc, vf2, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf10, vf6, vf13);  // vmaddw.xyzw vf10, vf6, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf11, vf0);        // vmulaw.xyzw acc, vf11, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf3, vf13);       // vmaddax.xyzw acc, vf3, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf11, vf7, vf13);  // vmaddw.xyzw vf11, vf7, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf12, vf0);        // vmulaw.xyzw acc, vf12, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf4, vf13);       // vmaddax.xyzw acc, vf4, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf12, vf8, vf13);  // vmaddw.xyzw vf12, vf8, vf13
        c->sqc2(vf9, 0, a0);                              // sqc2 vf9, 0(a0)
        c->sqc2(vf10, 16, a0);                            // sqc2 vf10, 16(a0)
        c->sqc2(vf11, 32, a0);                            // sqc2 vf11, 32(a0)
        c->sqc2(vf12, 48, a0);                            // sqc2 vf12, 48(a0)

      case 4:
        next_block = 5;
        c->lw(s4, -4, s5);                                // lw s4, -4(s5)
        c->daddiu(a0, a0, 64);                            // daddiu a0, a0, 64

      case 5:
        next_block = 6;
        c->andi(t3, s4, 15);                              // andi t3, s4, 15
        c->sra(s4, s4, 4);                                // sra s4, s4, 4
        c->sll(t3, t3, 2);                                // sll t3, t3, 2
        c->daddiu(s3, s3, -1);                            // daddiu s3, s3, -1
        c->daddu(t3, t3, t2);                             // daddu t3, t3, t2
        c->daddiu(s2, s2, -1);                            // daddiu s2, s2, -1
        c->lw(t3, 0, t3);                                 // lw t3, 0(t3)
        // nop                                            // sll r0, r0, 0
        // nop                                            // sll r0, r0, 0
        // nop                                            // sll r0, r0, 0
        next_block = 0x4d7666d9 ^ c->gprs[t3].du32[0];    // jr t3
        ASSERT(next_block < 33);
        break;
        // nop                                            // sll r0, r0, 0

      case 6:
        next_block = 7;
        bc = c->sgpr64(s2) == 0;                          // beq s2, r0, L20
        c->daddiu(a0, a0, 48);                            // daddiu a0, a0, 48
        if (bc) {next_block = 32;}                        // branch non-likely

        break;

      case 7:
        next_block = 8;
        bc = c->sgpr64(s3) != 0;                          // bne s3, r0, L12
        // nop                                            // sll r0, r0, 0
        if (bc) {next_block = 5;}                         // branch non-likely

        break;

      case 8:
        next_block = 9;
        c->lw(s4, 0, s5);                                 // lw s4, 0(s5)
        c->daddiu(s5, s5, 4);                             // daddiu s5, s5, 4
        //beq r0, r0, L12                                 // beq r0, r0, L12
        c->addiu(s3, r0, 8);                              // addiu s3, r0, 8
        next_block = 5;                                   // branch always

        break;

      case 9:
        next_block = 10;
        c->lw(s6, 0, t5);                                 // lw s6, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(gp, 0, t6);                                 // lh gp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->lw(s6, 0, s0);                                 // lw s6, 0(s0)
        c->daddiu(s0, s0, 4);                             // daddiu s0, s0, 4
        c->lh(gp, 0, s1);                                 // lh gp, 0(s1)
        c->daddiu(s1, s1, 2);                             // daddiu s1, s1, 2
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->mov128_vf_gpr(vf2, s6);                        // qmtc2.i vf2, s6
        c->vitof0(DEST::xyzw, vf1, vf1);                  // vitof0.xyzw vf1, vf1
        c->vitof0(DEST::xyzw, vf2, vf2);                  // vitof0.xyzw vf2, vf2
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadda_bc(DEST::xyzw, BC::y, vf1, vf13);       // vmadday.xyzw acc, vf1, vf13
        c->vmadd_bc(DEST::xyzw, BC::z, vf3, vf2, vf13);   // vmaddz.xyzw vf3, vf2, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        //beq r0, r0, L13                                 // beq r0, r0, L13
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 10:
        next_block = 11;
        c->ld(s6, 0, t4);                                 // ld s6, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lw(gp, 0, t5);                                 // lw gp, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->ld(s6, 0, t7);                                 // ld s6, 0(t7)
        c->daddiu(t7, t7, 8);                             // daddiu t7, t7, 8
        c->lw(gp, 0, s0);                                 // lw gp, 0(s0)
        c->daddiu(s0, s0, 4);                             // daddiu s0, s0, 4
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->mov128_vf_gpr(vf2, s6);                        // qmtc2.i vf2, s6
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf1, vf13);       // vmaddax.xyzw acc, vf1, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf3, vf2, vf13);   // vmaddw.xyzw vf3, vf2, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        //beq r0, r0, L13                                 // beq r0, r0, L13
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 11:
        next_block = 12;
        c->ld(t9, 0, t4);                                 // ld t9, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->ld(t9, 0, t7);                                 // ld t9, 0(t7)
        c->daddiu(t7, t7, 8);                             // daddiu t7, t7, 8
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf5, t9);                        // qmtc2.i vf5, t9
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->vitof15(DEST::xyzw, vf5, vf5);                 // vitof15.xyzw vf5, vf5
        c->vmula_bc(DEST::xyzw, BC::x, vf4, vf13);        // vmulax.xyzw acc, vf4, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf4, vf5, vf13);   // vmaddw.xyzw vf4, vf5, vf13
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L14
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 13;
          break;
        }

      case 13:
        next_block = 14;
        c->vadd(DEST::xyzw, vf6, vf6, vf4);               // vadd.xyzw vf6, vf6, vf4
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        //beq r0, r0, L13                                 // beq r0, r0, L13
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 14:
        next_block = 15;
        c->ld(t9, 0, t4);                                 // ld t9, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->ld(t9, 0, t7);                                 // ld t9, 0(t7)
        c->daddiu(t7, t7, 8);                             // daddiu t7, t7, 8
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf5, t9);                        // qmtc2.i vf5, t9
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->lw(s6, 0, t5);                                 // lw s6, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(gp, 0, t6);                                 // lh gp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->vitof15(DEST::xyzw, vf5, vf5);                 // vitof15.xyzw vf5, vf5
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->vmula_bc(DEST::xyzw, BC::x, vf4, vf13);        // vmulax.xyzw acc, vf4, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf4, vf5, vf13);   // vmaddw.xyzw vf4, vf5, vf13
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->lw(s6, 0, s0);                                 // lw s6, 0(s0)
        c->daddiu(s0, s0, 4);                             // daddiu s0, s0, 4
        c->lh(gp, 0, s1);                                 // lh gp, 0(s1)
        c->daddiu(s1, s1, 2);                             // daddiu s1, s1, 2
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->mov128_vf_gpr(vf2, s6);                        // qmtc2.i vf2, s6
        c->vitof0(DEST::xyzw, vf1, vf1);                  // vitof0.xyzw vf1, vf1
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L15
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 16;
          break;
        }

      case 16:
        next_block = 17;
        c->vitof0(DEST::xyzw, vf2, vf2);                  // vitof0.xyzw vf2, vf2
        c->vadd(DEST::xyzw, vf6, vf6, vf4);               // vadd.xyzw vf6, vf6, vf4
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadda_bc(DEST::xyzw, BC::y, vf1, vf13);       // vmadday.xyzw acc, vf1, vf13
        c->vmadd_bc(DEST::xyzw, BC::z, vf3, vf2, vf13);   // vmaddz.xyzw vf3, vf2, vf13
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        //beq r0, r0, L13                                 // beq r0, r0, L13
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 17:
        next_block = 18;
        c->ld(t9, 8, t4);                                 // ld t9, 8(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->ld(t9, 8, t7);                                 // ld t9, 8(t7)
        c->daddiu(t7, t7, 8);                             // daddiu t7, t7, 8
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf5, t9);                        // qmtc2.i vf5, t9
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->ld(s6, -8, t4);                                // ld s6, -8(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lw(gp, 0, t5);                                 // lw gp, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->vitof15(DEST::xyzw, vf5, vf5);                 // vitof15.xyzw vf5, vf5
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->vmula_bc(DEST::xyzw, BC::x, vf4, vf13);        // vmulax.xyzw acc, vf4, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf4, vf5, vf13);   // vmaddw.xyzw vf4, vf5, vf13
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->ld(s6, -8, t7);                                // ld s6, -8(t7)
        c->daddiu(t7, t7, 8);                             // daddiu t7, t7, 8
        c->lw(gp, 0, s0);                                 // lw gp, 0(s0)
        c->daddiu(s0, s0, 4);                             // daddiu s0, s0, 4
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->mov128_vf_gpr(vf2, s6);                        // qmtc2.i vf2, s6
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L16
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 19;
          break;
        }

      case 19:
        next_block = 20;
        c->vadd(DEST::xyzw, vf6, vf6, vf4);               // vadd.xyzw vf6, vf6, vf4
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf1, vf13);       // vmaddax.xyzw acc, vf1, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf3, vf2, vf13);   // vmaddw.xyzw vf3, vf2, vf13
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        //beq r0, r0, L13                                 // beq r0, r0, L13
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 20:
        next_block = 21;
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->lw(t8, 0, s0);                                 // lw t8, 0(s0)
        c->daddiu(s0, s0, 4);                             // daddiu s0, s0, 4
        c->lh(fp, 0, s1);                                 // lh fp, 0(s1)
        c->daddiu(s1, s1, 2);                             // daddiu s1, s1, 2
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf8, t8);                        // qmtc2.i vf8, t8
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vitof12(DEST::xyzw, vf8, vf8);                 // vitof12.xyzw vf8, vf8
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf7, vf13);       // vmaddax.xyzw acc, vf7, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf9, vf8, vf13);   // vmaddw.xyzw vf9, vf8, vf13
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L13                                 // beq r0, r0, L13
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 21:
        next_block = 22;
        c->lw(s6, 0, t5);                                 // lw s6, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(gp, 0, t6);                                 // lh gp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->lw(s6, 0, s0);                                 // lw s6, 0(s0)
        c->daddiu(s0, s0, 4);                             // daddiu s0, s0, 4
        c->lh(gp, 0, s1);                                 // lh gp, 0(s1)
        c->daddiu(s1, s1, 2);                             // daddiu s1, s1, 2
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->mov128_vf_gpr(vf2, s6);                        // qmtc2.i vf2, s6
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->vitof0(DEST::xyzw, vf1, vf1);                  // vitof0.xyzw vf1, vf1
        c->vitof0(DEST::xyzw, vf2, vf2);                  // vitof0.xyzw vf2, vf2
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadda_bc(DEST::xyzw, BC::y, vf1, vf13);       // vmadday.xyzw acc, vf1, vf13
        c->vmadd_bc(DEST::xyzw, BC::z, vf3, vf2, vf13);   // vmaddz.xyzw vf3, vf2, vf13
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->lw(t8, 0, s0);                                 // lw t8, 0(s0)
        c->daddiu(s0, s0, 4);                             // daddiu s0, s0, 4
        c->lh(fp, 0, s1);                                 // lh fp, 0(s1)
        c->daddiu(s1, s1, 2);                             // daddiu s1, s1, 2
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf8, t8);                        // qmtc2.i vf8, t8
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vitof12(DEST::xyzw, vf8, vf8);                 // vitof12.xyzw vf8, vf8
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf7, vf13);       // vmaddax.xyzw acc, vf7, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf9, vf8, vf13);   // vmaddw.xyzw vf9, vf8, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L13                                 // beq r0, r0, L13
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 22:
        next_block = 23;
        c->ld(s6, 0, t4);                                 // ld s6, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lw(gp, 0, t5);                                 // lw gp, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->ld(s6, 0, t7);                                 // ld s6, 0(t7)
        c->daddiu(t7, t7, 8);                             // daddiu t7, t7, 8
        c->lw(gp, 0, s0);                                 // lw gp, 0(s0)
        c->daddiu(s0, s0, 4);                             // daddiu s0, s0, 4
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->mov128_vf_gpr(vf2, s6);                        // qmtc2.i vf2, s6
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf1, vf13);       // vmaddax.xyzw acc, vf1, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf3, vf2, vf13);   // vmaddw.xyzw vf3, vf2, vf13
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->lw(t8, 0, s0);                                 // lw t8, 0(s0)
        c->daddiu(s0, s0, 4);                             // daddiu s0, s0, 4
        c->lh(fp, 0, s1);                                 // lh fp, 0(s1)
        c->daddiu(s1, s1, 2);                             // daddiu s1, s1, 2
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf8, t8);                        // qmtc2.i vf8, t8
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vitof12(DEST::xyzw, vf8, vf8);                 // vitof12.xyzw vf8, vf8
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf7, vf13);       // vmaddax.xyzw acc, vf7, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf9, vf8, vf13);   // vmaddw.xyzw vf9, vf8, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L13                                 // beq r0, r0, L13
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 23:
        next_block = 24;
        c->ld(t9, 0, t4);                                 // ld t9, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->ld(t9, 0, t7);                                 // ld t9, 0(t7)
        c->daddiu(t7, t7, 8);                             // daddiu t7, t7, 8
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf5, t9);                        // qmtc2.i vf5, t9
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->vitof15(DEST::xyzw, vf5, vf5);                 // vitof15.xyzw vf5, vf5
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->vmula_bc(DEST::xyzw, BC::x, vf4, vf13);        // vmulax.xyzw acc, vf4, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf4, vf5, vf13);   // vmaddw.xyzw vf4, vf5, vf13
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->lw(t8, 0, s0);                                 // lw t8, 0(s0)
        c->daddiu(s0, s0, 4);                             // daddiu s0, s0, 4
        c->lh(fp, 0, s1);                                 // lh fp, 0(s1)
        c->daddiu(s1, s1, 2);                             // daddiu s1, s1, 2
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf8, t8);                        // qmtc2.i vf8, t8
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vitof12(DEST::xyzw, vf8, vf8);                 // vitof12.xyzw vf8, vf8
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L17
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 25;
          break;
        }

      case 25:
        next_block = 26;
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf7, vf13);       // vmaddax.xyzw acc, vf7, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf9, vf8, vf13);   // vmaddw.xyzw vf9, vf8, vf13
        c->vadd(DEST::xyzw, vf6, vf6, vf4);               // vadd.xyzw vf6, vf6, vf4
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L13                                 // beq r0, r0, L13
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 26:
        next_block = 27;
        c->ld(t9, 0, t4);                                 // ld t9, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->ld(t9, 0, t7);                                 // ld t9, 0(t7)
        c->daddiu(t7, t7, 8);                             // daddiu t7, t7, 8
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf5, t9);                        // qmtc2.i vf5, t9
        c->lw(s6, 0, t5);                                 // lw s6, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(gp, 0, t6);                                 // lh gp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->vitof15(DEST::xyzw, vf5, vf5);                 // vitof15.xyzw vf5, vf5
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->vmula_bc(DEST::xyzw, BC::x, vf4, vf13);        // vmulax.xyzw acc, vf4, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf4, vf5, vf13);   // vmaddw.xyzw vf4, vf5, vf13
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->lw(s6, 0, s0);                                 // lw s6, 0(s0)
        c->daddiu(s0, s0, 4);                             // daddiu s0, s0, 4
        c->lh(gp, 0, s1);                                 // lh gp, 0(s1)
        c->daddiu(s1, s1, 2);                             // daddiu s1, s1, 2
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->mov128_vf_gpr(vf2, s6);                        // qmtc2.i vf2, s6
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->vitof0(DEST::xyzw, vf1, vf1);                  // vitof0.xyzw vf1, vf1
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L18
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 28;
          break;
        }

      case 28:
        next_block = 29;
        c->vitof0(DEST::xyzw, vf2, vf2);                  // vitof0.xyzw vf2, vf2
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadda_bc(DEST::xyzw, BC::y, vf1, vf13);       // vmadday.xyzw acc, vf1, vf13
        c->vmadd_bc(DEST::xyzw, BC::z, vf3, vf2, vf13);   // vmaddz.xyzw vf3, vf2, vf13
        c->vadd(DEST::xyzw, vf6, vf6, vf4);               // vadd.xyzw vf6, vf6, vf4
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->lw(t8, 0, s0);                                 // lw t8, 0(s0)
        c->daddiu(s0, s0, 4);                             // daddiu s0, s0, 4
        c->lh(fp, 0, s1);                                 // lh fp, 0(s1)
        c->daddiu(s1, s1, 2);                             // daddiu s1, s1, 2
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf8, t8);                        // qmtc2.i vf8, t8
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vitof12(DEST::xyzw, vf8, vf8);                 // vitof12.xyzw vf8, vf8
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf7, vf13);       // vmaddax.xyzw acc, vf7, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf9, vf8, vf13);   // vmaddw.xyzw vf9, vf8, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L13                                 // beq r0, r0, L13
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 29:
        next_block = 30;
        c->ld(t9, 8, t4);                                 // ld t9, 8(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->ld(t9, 8, t7);                                 // ld t9, 8(t7)
        c->daddiu(t7, t7, 8);                             // daddiu t7, t7, 8
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf5, t9);                        // qmtc2.i vf5, t9
        c->ld(s6, -8, t4);                                // ld s6, -8(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lw(gp, 0, t5);                                 // lw gp, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->vitof15(DEST::xyzw, vf5, vf5);                 // vitof15.xyzw vf5, vf5
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->vmula_bc(DEST::xyzw, BC::x, vf4, vf13);        // vmulax.xyzw acc, vf4, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf4, vf5, vf13);   // vmaddw.xyzw vf4, vf5, vf13
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->ld(s6, -8, t7);                                // ld s6, -8(t7)
        c->daddiu(t7, t7, 8);                             // daddiu t7, t7, 8
        c->lw(gp, 0, s0);                                 // lw gp, 0(s0)
        c->daddiu(s0, s0, 4);                             // daddiu s0, s0, 4
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->mov128_vf_gpr(vf2, s6);                        // qmtc2.i vf2, s6
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L19
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 31;
          break;
        }

      case 31:
        next_block = 32;
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf1, vf13);       // vmaddax.xyzw acc, vf1, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf3, vf2, vf13);   // vmaddw.xyzw vf3, vf2, vf13
        c->vadd(DEST::xyzw, vf6, vf6, vf4);               // vadd.xyzw vf6, vf6, vf4
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->lw(t8, 0, s0);                                 // lw t8, 0(s0)
        c->daddiu(s0, s0, 4);                             // daddiu s0, s0, 4
        c->lh(fp, 0, s1);                                 // lh fp, 0(s1)
        c->daddiu(s1, s1, 2);                             // daddiu s1, s1, 2
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf8, t8);                        // qmtc2.i vf8, t8
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vitof12(DEST::xyzw, vf8, vf8);                 // vitof12.xyzw vf8, vf8
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadda_bc(DEST::xyzw, BC::x, vf7, vf13);       // vmaddax.xyzw acc, vf7, vf13
        c->vmadd_bc(DEST::xyzw, BC::w, vf9, vf8, vf13);   // vmaddw.xyzw vf9, vf8, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L13                                 // beq r0, r0, L13
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 32:
        next_block = 33;
        c->lq(a0, 0, sp);                                 // lq a0, 0(sp)
        c->lq(t7, 16, sp);                                // lq t7, 16(sp)
        c->lq(s0, 32, sp);                                // lq s0, 32(sp)
        c->lq(s1, 48, sp);                                // lq s1, 48(sp)
        //jr ra                                           // jr ra
        c->daddiu(sp, sp, 64);                            // daddiu sp, sp, 64
        goto end_of_function;                             // return

        //jr ra                                           // jr ra
        c->daddu(sp, sp, r0);                             // daddu sp, sp, r0
        goto end_of_function;                             // return

        // nop                                            // sll r0, r0, 0
        // nop                                            // sll r0, r0, 0
    }
  }
  end_of_function:
  return c->gprs[v0].du64[0];
}

u32 jump_table_vals[16] = {
    0x4d7666df, // = 6 ^ 1299605209
    0x4d7666d0, // = 9 ^ 1299605209
    0x4d7666d2, // = 11 ^ 1299605209
    0x4d7666d7, // = 14 ^ 1299605209
    0x4d7666cd, // = 20 ^ 1299605209
    0x4d7666cc, // = 21 ^ 1299605209
    0x4d7666ce, // = 23 ^ 1299605209
    0x4d7666c3, // = 26 ^ 1299605209
    0x4d7666df, // = 6 ^ 1299605209
    0x4d7666d3, // = 10 ^ 1299605209
    0x4d7666d2, // = 11 ^ 1299605209
    0x4d7666c8, // = 17 ^ 1299605209
    0x4d7666cd, // = 20 ^ 1299605209
    0x4d7666cf, // = 22 ^ 1299605209
    0x4d7666ce, // = 23 ^ 1299605209
    0x4d7666c4, // = 29 ^ 1299605209
};

} // namespace decompress_frame_data_pair_to_accumulator
} // namespace Mips2C

//--------------------------MIPS2C---------------------
#include "game/mips2c/mips2c_private.h"

namespace Mips2C::jak1 {
namespace decompress_frame_data_to_accumulator {
u64 execute(void* ctxt) {
  auto* c = (ExecutionContext*)ctxt;
  bool bc = false;
  u32 next_block = 0;
  while(true) {
    switch(next_block) {

      case 0:
        next_block = 1;
        c->daddiu(sp, sp, -16);                           // daddiu sp, sp, -16
        c->mov128_vf_gpr(vf13, a2);                       // qmtc2.i vf13, a2
        c->sq(a0, 0, sp);                                 // sq a0, 0(sp)
        //c->lui(t2, 28672);                                // lui t2, 28672
        get_fake_spad_addr(t2, cache.fake_scratchpad_data, 0, c);
        c->lw(t4, 0, a1);                                 // lw t4, 0(a1)
        c->daddiu(v1, a1, 16);                            // daddiu v1, a1, 16
        c->lw(t5, 4, a1);                                 // lw t5, 4(a1)
        c->daddu(s5, t1, r0);                             // daddu s5, t1, r0
        c->lw(t6, 8, a1);                                 // lw t6, 8(a1)
        c->daddu(t4, t4, v1);                             // daddu t4, t4, v1
        c->vmul_bc(DEST::xyzw, BC::x, vf13, vf14, vf13);  // vmulx.xyzw vf13, vf14, vf13
        c->daddiu(t2, t2, 1696);                          // daddiu t2, t2, 1696
        c->lw(s2, 56, t1);                                // lw s2, 56(t1)
        c->daddu(t5, t5, v1);                             // daddu t5, t5, v1
        c->lw(s4, 60, t1);                                // lw s4, 60(t1)
        c->daddu(t6, t6, v1);                             // daddu t6, t6, v1
        c->addiu(s3, r0, 8);                              // addiu s3, r0, 8
        c->daddiu(s5, s5, 4);                             // daddiu s5, s5, 4
        c->andi(t3, s4, 1);                               // andi t3, s4, 1
        // nop                                            // sll r0, r0, 0
        bc = c->sgpr64(t3) == 0;                          // beq t3, r0, L22
        // nop                                            // sll r0, r0, 0
        if (bc) {next_block = 2;}                         // branch non-likely

        break;

      case 1:
        next_block = 2;
        c->lqc2(vf1, 0, t4);                              // lqc2 vf1, 0(t4)
        c->lqc2(vf2, 16, t4);                             // lqc2 vf2, 16(t4)
        c->lqc2(vf3, 32, t4);                             // lqc2 vf3, 32(t4)
        c->lqc2(vf4, 48, t4);                             // lqc2 vf4, 48(t4)
        c->lqc2(vf9, 0, a0);                              // lqc2 vf9, 0(a0)
        c->daddiu(t4, t4, 64);                            // daddiu t4, t4, 64
        c->lqc2(vf10, 16, a0);                            // lqc2 vf10, 16(a0)
        // nop                                            // sll r0, r0, 0
        c->lqc2(vf11, 32, a0);                            // lqc2 vf11, 32(a0)
        c->lqc2(vf12, 48, a0);                            // lqc2 vf12, 48(a0)
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf1, vf13);   // vmaddx.xyzw vf9, vf1, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf2, vf13);  // vmaddx.xyzw vf10, vf2, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf11, vf0);        // vmulaw.xyzw acc, vf11, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf11, vf3, vf13);  // vmaddx.xyzw vf11, vf3, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf12, vf0);        // vmulaw.xyzw acc, vf12, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf12, vf4, vf13);  // vmaddx.xyzw vf12, vf4, vf13
        c->sqc2(vf9, 0, a0);                              // sqc2 vf9, 0(a0)
        c->sqc2(vf10, 16, a0);                            // sqc2 vf10, 16(a0)
        c->sqc2(vf11, 32, a0);                            // sqc2 vf11, 32(a0)
        c->sqc2(vf12, 48, a0);                            // sqc2 vf12, 48(a0)

      case 2:
        next_block = 3;
        c->andi(t3, s4, 2);                               // andi t3, s4, 2
        c->daddiu(a0, a0, 64);                            // daddiu a0, a0, 64
        bc = c->sgpr64(t3) == 0;                          // beq t3, r0, L23
        // nop                                            // sll r0, r0, 0
        if (bc) {next_block = 4;}                         // branch non-likely

        break;

      case 3:
        next_block = 4;
        c->lqc2(vf1, 0, t4);                              // lqc2 vf1, 0(t4)
        c->lqc2(vf2, 16, t4);                             // lqc2 vf2, 16(t4)
        c->lqc2(vf3, 32, t4);                             // lqc2 vf3, 32(t4)
        c->lqc2(vf4, 48, t4);                             // lqc2 vf4, 48(t4)
        c->lqc2(vf9, 0, a0);                              // lqc2 vf9, 0(a0)
        c->daddiu(t4, t4, 64);                            // daddiu t4, t4, 64
        c->lqc2(vf10, 16, a0);                            // lqc2 vf10, 16(a0)
        // nop                                            // sll r0, r0, 0
        c->lqc2(vf11, 32, a0);                            // lqc2 vf11, 32(a0)
        c->lqc2(vf12, 48, a0);                            // lqc2 vf12, 48(a0)
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf1, vf13);   // vmaddx.xyzw vf9, vf1, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf2, vf13);  // vmaddx.xyzw vf10, vf2, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf11, vf0);        // vmulaw.xyzw acc, vf11, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf11, vf3, vf13);  // vmaddx.xyzw vf11, vf3, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf12, vf0);        // vmulaw.xyzw acc, vf12, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf12, vf4, vf13);  // vmaddx.xyzw vf12, vf4, vf13
        c->sqc2(vf9, 0, a0);                              // sqc2 vf9, 0(a0)
        c->sqc2(vf10, 16, a0);                            // sqc2 vf10, 16(a0)
        c->sqc2(vf11, 32, a0);                            // sqc2 vf11, 32(a0)
        c->sqc2(vf12, 48, a0);                            // sqc2 vf12, 48(a0)

      case 4:
        next_block = 5;
        c->lw(s4, -4, s5);                                // lw s4, -4(s5)
        c->daddiu(a0, a0, 64);                            // daddiu a0, a0, 64

      case 5:
        next_block = 6;
        c->andi(t3, s4, 15);                              // andi t3, s4, 15
        c->sra(s4, s4, 4);                                // sra s4, s4, 4
        c->sll(t3, t3, 2);                                // sll t3, t3, 2
        c->daddiu(s3, s3, -1);                            // daddiu s3, s3, -1
        c->daddu(t3, t3, t2);                             // daddu t3, t3, t2
        c->daddiu(s2, s2, -1);                            // daddiu s2, s2, -1
        c->lw(t3, 0, t3);                                 // lw t3, 0(t3)
        // nop                                            // sll r0, r0, 0
        // nop                                            // sll r0, r0, 0
        // nop                                            // sll r0, r0, 0
        next_block = 0x7b2191d ^ c->gprs[t3].du32[0];     // jr t3
        ASSERT(next_block < 33);
        break;
        // nop                                            // sll r0, r0, 0

      case 6:
        next_block = 7;
        bc = c->sgpr64(s2) == 0;                          // beq s2, r0, L32
        c->daddiu(a0, a0, 48);                            // daddiu a0, a0, 48
        if (bc) {next_block = 32;}                        // branch non-likely

        break;

      case 7:
        next_block = 8;
        bc = c->sgpr64(s3) != 0;                          // bne s3, r0, L24
        // nop                                            // sll r0, r0, 0
        if (bc) {next_block = 5;}                         // branch non-likely

        break;

      case 8:
        next_block = 9;
        c->lw(s4, 0, s5);                                 // lw s4, 0(s5)
        c->daddiu(s5, s5, 4);                             // daddiu s5, s5, 4
        //beq r0, r0, L24                                 // beq r0, r0, L24
        c->addiu(s3, r0, 8);                              // addiu s3, r0, 8
        next_block = 5;                                   // branch always

        break;

      case 9:
        next_block = 10;
        c->lw(s6, 0, t5);                                 // lw s6, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(gp, 0, t6);                                 // lh gp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->vitof0(DEST::xyzw, vf1, vf1);                  // vitof0.xyzw vf1, vf1
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::y, vf3, vf1, vf13);   // vmaddy.xyzw vf3, vf1, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        //beq r0, r0, L25                                 // beq r0, r0, L25
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 10:
        next_block = 11;
        c->ld(s6, 0, t4);                                 // ld s6, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lw(gp, 0, t5);                                 // lw gp, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf3, vf1, vf13);   // vmaddx.xyzw vf3, vf1, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        //beq r0, r0, L25                                 // beq r0, r0, L25
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 11:
        next_block = 12;
        c->ld(t9, 0, t4);                                 // ld t9, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L26
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 13;
          break;
        }

      case 13:
        next_block = 14;
        c->vmula_bc(DEST::xyzw, BC::w, vf6, vf0);         // vmulaw.xyzw acc, vf6, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf6, vf4, vf13);   // vmaddx.xyzw vf6, vf4, vf13
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        //beq r0, r0, L25                                 // beq r0, r0, L25
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 14:
        next_block = 15;
        c->ld(t9, 0, t4);                                 // ld t9, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->lw(s6, 0, t5);                                 // lw s6, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(gp, 0, t6);                                 // lh gp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vitof0(DEST::xyzw, vf1, vf1);                  // vitof0.xyzw vf1, vf1
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::y, vf3, vf1, vf13);   // vmaddy.xyzw vf3, vf1, vf13
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L27
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 16;
          break;
        }

      case 16:
        next_block = 17;
        c->vmula_bc(DEST::xyzw, BC::w, vf6, vf0);         // vmulaw.xyzw acc, vf6, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf6, vf4, vf13);   // vmaddx.xyzw vf6, vf4, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        //beq r0, r0, L25                                 // beq r0, r0, L25
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 17:
        next_block = 18;
        c->ld(t9, 8, t4);                                 // ld t9, 8(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->ld(s6, -8, t4);                                // ld s6, -8(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lw(gp, 0, t5);                                 // lw gp, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf3, vf1, vf13);   // vmaddx.xyzw vf3, vf1, vf13
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L28
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 19;
          break;
        }

      case 19:
        next_block = 20;
        c->vmula_bc(DEST::xyzw, BC::w, vf6, vf0);         // vmulaw.xyzw acc, vf6, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf6, vf4, vf13);   // vmaddx.xyzw vf6, vf4, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        //beq r0, r0, L25                                 // beq r0, r0, L25
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 20:
        next_block = 21;
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf7, vf13);   // vmaddx.xyzw vf9, vf7, vf13
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L25                                 // beq r0, r0, L25
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 21:
        next_block = 22;
        c->lw(s6, 0, t5);                                 // lw s6, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(gp, 0, t6);                                 // lh gp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->vitof0(DEST::xyzw, vf1, vf1);                  // vitof0.xyzw vf1, vf1
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::y, vf3, vf1, vf13);   // vmaddy.xyzw vf3, vf1, vf13
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf7, vf13);   // vmaddx.xyzw vf9, vf7, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L25                                 // beq r0, r0, L25
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 22:
        next_block = 23;
        c->ld(s6, 0, t4);                                 // ld s6, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lw(gp, 0, t5);                                 // lw gp, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf3, vf1, vf13);   // vmaddx.xyzw vf3, vf1, vf13
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf7, vf13);   // vmaddx.xyzw vf9, vf7, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L25                                 // beq r0, r0, L25
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 23:
        next_block = 24;
        c->ld(t9, 0, t4);                                 // ld t9, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf7, vf13);   // vmaddx.xyzw vf9, vf7, vf13
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L29
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 25;
          break;
        }

      case 25:
        next_block = 26;
        c->vmula_bc(DEST::xyzw, BC::w, vf6, vf0);         // vmulaw.xyzw acc, vf6, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf6, vf4, vf13);   // vmaddx.xyzw vf6, vf4, vf13
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L25                                 // beq r0, r0, L25
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 26:
        next_block = 27;
        c->ld(t9, 0, t4);                                 // ld t9, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->lw(s6, 0, t5);                                 // lw s6, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(gp, 0, t6);                                 // lh gp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->vitof0(DEST::xyzw, vf1, vf1);                  // vitof0.xyzw vf1, vf1
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L30
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 28;
          break;
        }

      case 28:
        next_block = 29;
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vmula_bc(DEST::xyzw, BC::w, vf6, vf0);         // vmulaw.xyzw acc, vf6, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf6, vf4, vf13);   // vmaddx.xyzw vf6, vf4, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::y, vf3, vf1, vf13);   // vmaddy.xyzw vf3, vf1, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf7, vf13);   // vmaddx.xyzw vf9, vf7, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L25                                 // beq r0, r0, L25
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 29:
        next_block = 30;
        c->ld(t9, 8, t4);                                 // ld t9, 8(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->ld(s6, -8, t4);                                // ld s6, -8(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lw(gp, 0, t5);                                 // lw gp, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L31
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 31;
          break;
        }

      case 31:
        next_block = 32;
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vmula_bc(DEST::xyzw, BC::w, vf6, vf0);         // vmulaw.xyzw acc, vf6, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf6, vf4, vf13);   // vmaddx.xyzw vf6, vf4, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf3, vf1, vf13);   // vmaddx.xyzw vf3, vf1, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf7, vf13);   // vmaddx.xyzw vf9, vf7, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L25                                 // beq r0, r0, L25
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 32:
        next_block = 33;
        c->lq(a0, 0, sp);                                 // lq a0, 0(sp)
        // nop                                            // sll r0, r0, 0
        //jr ra                                           // jr ra
        c->daddiu(sp, sp, 16);                            // daddiu sp, sp, 16
        goto end_of_function;                             // return

        //jr ra                                           // jr ra
        c->daddu(sp, sp, r0);                             // daddu sp, sp, r0
        goto end_of_function;                             // return

        // nop                                            // sll r0, r0, 0
        // nop                                            // sll r0, r0, 0
        // nop                                            // sll r0, r0, 0
    }
  }
  end_of_function:
  return c->gprs[v0].du64[0];
}

u32 jump_table_vals[16] = {
    0x7b2191b, // = 6 ^ 129112349
    0x7b21914, // = 9 ^ 129112349
    0x7b21916, // = 11 ^ 129112349
    0x7b21913, // = 14 ^ 129112349
    0x7b21909, // = 20 ^ 129112349
    0x7b21908, // = 21 ^ 129112349
    0x7b2190a, // = 23 ^ 129112349
    0x7b21907, // = 26 ^ 129112349
    0x7b2191b, // = 6 ^ 129112349
    0x7b21917, // = 10 ^ 129112349
    0x7b21916, // = 11 ^ 129112349
    0x7b2190c, // = 17 ^ 129112349
    0x7b21909, // = 20 ^ 129112349
    0x7b2190b, // = 22 ^ 129112349
    0x7b2190a, // = 23 ^ 129112349
    0x7b21900, // = 29 ^ 129112349
};

} // namespace decompress_frame_data_to_accumulator
} // namespace Mips2C

//--------------------------MIPS2C---------------------
#include "game/mips2c/mips2c_private.h"

namespace Mips2C::jak1 {
namespace decompress_fixed_data_to_accumulator {
u64 execute(void* ctxt) {
  auto* c = (ExecutionContext*)ctxt;
  bool bc = false;
  u32 next_block = 0;
  while(true) {
    switch(next_block) {

      case 0:
        next_block = 1;
        c->lq(t4, 0, a1);                                 // lq t4, 0(a1)
        c->daddiu(sp, sp, -16);                           // daddiu sp, sp, -16
        c->lq(t5, 16, a1);                                // lq t5, 16(a1)
        // nop                                            // sll r0, r0, 0
        c->sq(t4, 0, t1);                                 // sq t4, 0(t1)
        // nop                                            // sll r0, r0, 0
        c->sq(t5, 16, t1);                                // sq t5, 16(t1)
        // nop                                            // sll r0, r0, 0
        c->lq(t4, 32, a1);                                // lq t4, 32(a1)
        // nop                                            // sll r0, r0, 0
        c->lq(t5, 48, a1);                                // lq t5, 48(a1)
        // nop                                            // sll r0, r0, 0
        c->sq(t4, 32, t1);                                // sq t4, 32(t1)
        // nop                                            // sll r0, r0, 0
        c->sq(t5, 48, t1);                                // sq t5, 48(t1)
        // nop                                            // sll r0, r0, 0
        c->sq(a0, 0, sp);                                 // sq a0, 0(sp)
        // nop                                            // sll r0, r0, 0
        c->mov128_vf_gpr(vf13, a2);                       // qmtc2.i vf13, a2
        // c->lui(t2, 28672);                                // lui t2, 28672
        get_fake_spad_addr(t2, cache.fake_scratchpad_data, 0, c);
        c->lw(t4, 64, a1);                                // lw t4, 64(a1)
        c->daddiu(v1, a1, 80);                            // daddiu v1, a1, 80
        c->lw(t5, 68, a1);                                // lw t5, 68(a1)
        c->daddu(s5, t1, r0);                             // daddu s5, t1, r0
        c->lw(t6, 72, a1);                                // lw t6, 72(a1)
        c->daddu(t4, t4, v1);                             // daddu t4, t4, v1
        c->vmul_bc(DEST::xyzw, BC::x, vf13, vf14, vf13);  // vmulx.xyzw vf13, vf14, vf13
        c->daddiu(t2, t2, 1632);                          // daddiu t2, t2, 1632
        c->lw(s2, 56, t1);                                // lw s2, 56(t1)
        c->daddu(t5, t5, v1);                             // daddu t5, t5, v1
        c->lw(s4, 60, t1);                                // lw s4, 60(t1)
        c->daddu(t6, t6, v1);                             // daddu t6, t6, v1
        c->addiu(s3, r0, 8);                              // addiu s3, r0, 8
        c->daddiu(s5, s5, 4);                             // daddiu s5, s5, 4
        c->andi(t3, s4, 1);                               // andi t3, s4, 1
        // nop                                            // sll r0, r0, 0
        bc = c->sgpr64(t3) != 0;                          // bne t3, r0, L34
        // nop                                            // sll r0, r0, 0
        if (bc) {next_block = 2;}                         // branch non-likely

        break;

      case 1:
        next_block = 2;
        c->lqc2(vf1, 0, t4);                              // lqc2 vf1, 0(t4)
        c->lqc2(vf2, 16, t4);                             // lqc2 vf2, 16(t4)
        c->lqc2(vf3, 32, t4);                             // lqc2 vf3, 32(t4)
        c->lqc2(vf4, 48, t4);                             // lqc2 vf4, 48(t4)
        c->lqc2(vf9, 0, a0);                              // lqc2 vf9, 0(a0)
        c->daddiu(t4, t4, 64);                            // daddiu t4, t4, 64
        c->lqc2(vf10, 16, a0);                            // lqc2 vf10, 16(a0)
        // nop                                            // sll r0, r0, 0
        c->lqc2(vf11, 32, a0);                            // lqc2 vf11, 32(a0)
        c->lqc2(vf12, 48, a0);                            // lqc2 vf12, 48(a0)
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf1, vf13);   // vmaddx.xyzw vf9, vf1, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf2, vf13);  // vmaddx.xyzw vf10, vf2, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf11, vf0);        // vmulaw.xyzw acc, vf11, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf11, vf3, vf13);  // vmaddx.xyzw vf11, vf3, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf12, vf0);        // vmulaw.xyzw acc, vf12, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf12, vf4, vf13);  // vmaddx.xyzw vf12, vf4, vf13
        c->sqc2(vf9, 0, a0);                              // sqc2 vf9, 0(a0)
        c->sqc2(vf10, 16, a0);                            // sqc2 vf10, 16(a0)
        c->sqc2(vf11, 32, a0);                            // sqc2 vf11, 32(a0)
        c->sqc2(vf12, 48, a0);                            // sqc2 vf12, 48(a0)

      case 2:
        next_block = 3;
        c->andi(t3, s4, 2);                               // andi t3, s4, 2
        c->daddiu(a0, a0, 64);                            // daddiu a0, a0, 64
        bc = c->sgpr64(t3) != 0;                          // bne t3, r0, L35
        // nop                                            // sll r0, r0, 0
        if (bc) {next_block = 4;}                         // branch non-likely

        break;

      case 3:
        next_block = 4;
        c->lqc2(vf1, 0, t4);                              // lqc2 vf1, 0(t4)
        c->lqc2(vf2, 16, t4);                             // lqc2 vf2, 16(t4)
        c->lqc2(vf3, 32, t4);                             // lqc2 vf3, 32(t4)
        c->lqc2(vf4, 48, t4);                             // lqc2 vf4, 48(t4)
        c->lqc2(vf9, 0, a0);                              // lqc2 vf9, 0(a0)
        c->daddiu(t4, t4, 64);                            // daddiu t4, t4, 64
        c->lqc2(vf10, 16, a0);                            // lqc2 vf10, 16(a0)
        // nop                                            // sll r0, r0, 0
        c->lqc2(vf11, 32, a0);                            // lqc2 vf11, 32(a0)
        c->lqc2(vf12, 48, a0);                            // lqc2 vf12, 48(a0)
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf1, vf13);   // vmaddx.xyzw vf9, vf1, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf2, vf13);  // vmaddx.xyzw vf10, vf2, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf11, vf0);        // vmulaw.xyzw acc, vf11, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf11, vf3, vf13);  // vmaddx.xyzw vf11, vf3, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf12, vf0);        // vmulaw.xyzw acc, vf12, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf12, vf4, vf13);  // vmaddx.xyzw vf12, vf4, vf13
        c->sqc2(vf9, 0, a0);                              // sqc2 vf9, 0(a0)
        c->sqc2(vf10, 16, a0);                            // sqc2 vf10, 16(a0)
        c->sqc2(vf11, 32, a0);                            // sqc2 vf11, 32(a0)
        c->sqc2(vf12, 48, a0);                            // sqc2 vf12, 48(a0)

      case 4:
        next_block = 5;
        c->lw(s4, -4, s5);                                // lw s4, -4(s5)
        c->daddiu(a0, a0, 64);                            // daddiu a0, a0, 64

      case 5:
        next_block = 6;
        c->andi(t3, s4, 15);                              // andi t3, s4, 15
        c->sra(s4, s4, 4);                                // sra s4, s4, 4
        c->sll(t3, t3, 2);                                // sll t3, t3, 2
        c->daddiu(s3, s3, -1);                            // daddiu s3, s3, -1
        c->daddu(t3, t3, t2);                             // daddu t3, t3, t2
        c->daddiu(s2, s2, -1);                            // daddiu s2, s2, -1
        c->lw(t3, 0, t3);                                 // lw t3, 0(t3)
        // nop                                            // sll r0, r0, 0
        // nop                                            // sll r0, r0, 0
        // nop                                            // sll r0, r0, 0
        next_block = 0x3ee6b6f0 ^ c->gprs[t3].du32[0];    // jr t3
        ASSERT(next_block < 33);
        break;
        // nop                                            // sll r0, r0, 0

      case 6:
        next_block = 7;
        bc = c->sgpr64(s2) == 0;                          // beq s2, r0, L44
        c->daddiu(a0, a0, 48);                            // daddiu a0, a0, 48
        if (bc) {next_block = 32;}                        // branch non-likely

        break;

      case 7:
        next_block = 8;
        bc = c->sgpr64(s3) != 0;                          // bne s3, r0, L36
        // nop                                            // sll r0, r0, 0
        if (bc) {next_block = 5;}                         // branch non-likely

        break;

      case 8:
        next_block = 9;
        c->lw(s4, 0, s5);                                 // lw s4, 0(s5)
        c->daddiu(s5, s5, 4);                             // daddiu s5, s5, 4
        //beq r0, r0, L36                                 // beq r0, r0, L36
        c->addiu(s3, r0, 8);                              // addiu s3, r0, 8
        next_block = 5;                                   // branch always

        break;

      case 9:
        next_block = 10;
        c->ld(t9, 0, t4);                                 // ld t9, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->lw(s6, 0, t5);                                 // lw s6, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(gp, 0, t6);                                 // lh gp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->vitof0(DEST::xyzw, vf1, vf1);                  // vitof0.xyzw vf1, vf1
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L38
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 11;
          break;
        }

      case 11:
        next_block = 12;
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vmula_bc(DEST::xyzw, BC::w, vf6, vf0);         // vmulaw.xyzw acc, vf6, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf6, vf4, vf13);   // vmaddx.xyzw vf6, vf4, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::y, vf3, vf1, vf13);   // vmaddy.xyzw vf3, vf1, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf7, vf13);   // vmaddx.xyzw vf9, vf7, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L37                                 // beq r0, r0, L37
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 12:
        next_block = 13;
        c->ld(t9, 8, t4);                                 // ld t9, 8(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->ld(s6, -8, t4);                                // ld s6, -8(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lw(gp, 0, t5);                                 // lw gp, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L39
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 14;
          break;
        }

      case 14:
        next_block = 15;
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vmula_bc(DEST::xyzw, BC::w, vf6, vf0);         // vmulaw.xyzw acc, vf6, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf6, vf4, vf13);   // vmaddx.xyzw vf6, vf4, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf3, vf1, vf13);   // vmaddx.xyzw vf3, vf1, vf13
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf7, vf13);   // vmaddx.xyzw vf9, vf7, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L37                                 // beq r0, r0, L37
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 15:
        next_block = 16;
        c->ld(t9, 0, t4);                                 // ld t9, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf7, vf13);   // vmaddx.xyzw vf9, vf7, vf13
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L40
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 17;
          break;
        }

      case 17:
        next_block = 18;
        c->vmula_bc(DEST::xyzw, BC::w, vf6, vf0);         // vmulaw.xyzw acc, vf6, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf6, vf4, vf13);   // vmaddx.xyzw vf6, vf4, vf13
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L37                                 // beq r0, r0, L37
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 18:
        next_block = 19;
        c->lw(s6, 0, t5);                                 // lw s6, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(gp, 0, t6);                                 // lh gp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->vitof0(DEST::xyzw, vf1, vf1);                  // vitof0.xyzw vf1, vf1
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::y, vf3, vf1, vf13);   // vmaddy.xyzw vf3, vf1, vf13
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf7, vf13);   // vmaddx.xyzw vf9, vf7, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L37                                 // beq r0, r0, L37
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 19:
        next_block = 20;
        c->ld(s6, 0, t4);                                 // ld s6, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lw(gp, 0, t5);                                 // lw gp, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf3, vf1, vf13);   // vmaddx.xyzw vf3, vf1, vf13
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf7, vf13);   // vmaddx.xyzw vf9, vf7, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L37                                 // beq r0, r0, L37
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 20:
        next_block = 21;
        c->lw(t8, 0, t5);                                 // lw t8, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(fp, 0, t6);                                 // lh fp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf9, 32, a0);                             // lqc2 vf9, 32(a0)
        c->pextlw(t8, fp, t8);                            // pextlw t8, fp, t8
        c->pextlh(t8, t8, r0);                            // pextlh t8, t8, r0
        c->psraw(t8, t8, 16);                             // psraw t8, t8, 16
        c->mov128_vf_gpr(vf7, t8);                        // qmtc2.i vf7, t8
        c->vitof12(DEST::xyzw, vf7, vf7);                 // vitof12.xyzw vf7, vf7
        c->vmula_bc(DEST::xyzw, BC::w, vf9, vf0);         // vmulaw.xyzw acc, vf9, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf9, vf7, vf13);   // vmaddx.xyzw vf9, vf7, vf13
        c->sqc2(vf9, 32, a0);                             // sqc2 vf9, 32(a0)
        //beq r0, r0, L37                                 // beq r0, r0, L37
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 21:
        next_block = 22;
        c->ld(t9, 0, t4);                                 // ld t9, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->lw(s6, 0, t5);                                 // lw s6, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(gp, 0, t6);                                 // lh gp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vitof0(DEST::xyzw, vf1, vf1);                  // vitof0.xyzw vf1, vf1
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::y, vf3, vf1, vf13);   // vmaddy.xyzw vf3, vf1, vf13
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L41
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 23;
          break;
        }

      case 23:
        next_block = 24;
        c->vmula_bc(DEST::xyzw, BC::w, vf6, vf0);         // vmulaw.xyzw acc, vf6, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf6, vf4, vf13);   // vmaddx.xyzw vf6, vf4, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        //beq r0, r0, L37                                 // beq r0, r0, L37
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 24:
        next_block = 25;
        c->ld(t9, 8, t4);                                 // ld t9, 8(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->ld(s6, -8, t4);                                // ld s6, -8(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lw(gp, 0, t5);                                 // lw gp, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf3, vf1, vf13);   // vmaddx.xyzw vf3, vf1, vf13
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L42
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 26;
          break;
        }

      case 26:
        next_block = 27;
        c->vmula_bc(DEST::xyzw, BC::w, vf6, vf0);         // vmulaw.xyzw acc, vf6, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf6, vf4, vf13);   // vmaddx.xyzw vf6, vf4, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        //beq r0, r0, L37                                 // beq r0, r0, L37
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 27:
        next_block = 28;
        c->ld(t9, 0, t4);                                 // ld t9, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lqc2(vf6, 16, a0);                             // lqc2 vf6, 16(a0)
        c->pextlh(t9, t9, r0);                            // pextlh t9, t9, r0
        c->psraw(t9, t9, 16);                             // psraw t9, t9, 16
        c->mov128_vf_gpr(vf4, t9);                        // qmtc2.i vf4, t9
        c->vitof15(DEST::xyzw, vf4, vf4);                 // vitof15.xyzw vf4, vf4
        c->vmul(DEST::xyzw, vf10, vf4, vf6);              // vmul.xyzw vf10, vf4, vf6
        c->vmula_bc(DEST::xyzw, BC::w, vf10, vf0);        // vmulaw.xyzw acc, vf10, vf0
        c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
        c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
        c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
        c->mov128_gpr_vf(t9, vf10);                       // qmfc2.i t9, vf10
        c->pcpyud(t9, t9, r0);                            // pcpyud t9, t9, r0
        if (((s64)c->sgpr64(t9)) < 0) {                   // bltzl t9, L43
          c->vsub(DEST::xyzw, vf4, vf15, vf4);            // vsub.xyzw vf4, vf15, vf4
          next_block = 29;
          break;
        }

      case 29:
        next_block = 30;
        c->vmula_bc(DEST::xyzw, BC::w, vf6, vf0);         // vmulaw.xyzw acc, vf6, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf6, vf4, vf13);   // vmaddx.xyzw vf6, vf4, vf13
        c->sqc2(vf6, 16, a0);                             // sqc2 vf6, 16(a0)
        //beq r0, r0, L37                                 // beq r0, r0, L37
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 30:
        next_block = 31;
        c->lw(s6, 0, t5);                                 // lw s6, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lh(gp, 0, t6);                                 // lh gp, 0(t6)
        c->daddiu(t6, t6, 2);                             // daddiu t6, t6, 2
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pextlw(s6, gp, s6);                            // pextlw s6, gp, s6
        c->pextlh(s6, s6, r0);                            // pextlh s6, s6, r0
        c->psraw(s6, s6, 16);                             // psraw s6, s6, 16
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->vitof0(DEST::xyzw, vf1, vf1);                  // vitof0.xyzw vf1, vf1
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::y, vf3, vf1, vf13);   // vmaddy.xyzw vf3, vf1, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        //beq r0, r0, L37                                 // beq r0, r0, L37
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 31:
        next_block = 32;
        c->ld(s6, 0, t4);                                 // ld s6, 0(t4)
        c->daddiu(t4, t4, 8);                             // daddiu t4, t4, 8
        c->lw(gp, 0, t5);                                 // lw gp, 0(t5)
        c->daddiu(t5, t5, 4);                             // daddiu t5, t5, 4
        c->lqc2(vf3, 0, a0);                              // lqc2 vf3, 0(a0)
        c->pcpyld(s6, gp, s6);                            // pcpyld s6, gp, s6
        c->mov128_vf_gpr(vf1, s6);                        // qmtc2.i vf1, s6
        c->vmula_bc(DEST::xyzw, BC::w, vf3, vf0);         // vmulaw.xyzw acc, vf3, vf0
        c->vmadd_bc(DEST::xyzw, BC::x, vf3, vf1, vf13);   // vmaddx.xyzw vf3, vf1, vf13
        c->sqc2(vf3, 0, a0);                              // sqc2 vf3, 0(a0)
        //beq r0, r0, L37                                 // beq r0, r0, L37
        // nop                                            // sll r0, r0, 0
        next_block = 6;                                   // branch always

        break;

      case 32:
        next_block = 33;
        c->lq(a0, 0, sp);                                 // lq a0, 0(sp)
        // nop                                            // sll r0, r0, 0
        //jr ra                                           // jr ra
        c->daddiu(sp, sp, 16);                            // daddiu sp, sp, 16
        goto end_of_function;                             // return

        //jr ra                                           // jr ra
        c->daddu(sp, sp, r0);                             // daddu sp, sp, r0
        goto end_of_function;                             // return

        // nop                                            // sll r0, r0, 0
        // nop                                            // sll r0, r0, 0
        // nop                                            // sll r0, r0, 0
    }
  }
  end_of_function:
  return c->gprs[v0].du64[0];
}

u32 jump_table_vals[16] = {
    0x3ee6b6f9, // = 9 ^ 1055307504
    0x3ee6b6ff, // = 15 ^ 1055307504
    0x3ee6b6e2, // = 18 ^ 1055307504
    0x3ee6b6e4, // = 20 ^ 1055307504
    0x3ee6b6e5, // = 21 ^ 1055307504
    0x3ee6b6eb, // = 27 ^ 1055307504
    0x3ee6b6ee, // = 30 ^ 1055307504
    0x3ee6b6f6, // = 6 ^ 1055307504
    0x3ee6b6fc, // = 12 ^ 1055307504
    0x3ee6b6ff, // = 15 ^ 1055307504
    0x3ee6b6e3, // = 19 ^ 1055307504
    0x3ee6b6e4, // = 20 ^ 1055307504
    0x3ee6b6e8, // = 24 ^ 1055307504
    0x3ee6b6eb, // = 27 ^ 1055307504
    0x3ee6b6ef, // = 31 ^ 1055307504
    0x3ee6b6f6, // = 6 ^ 1055307504
};

} // namespace decompress_fixed_data_to_accumulator
} // namespace Mips2C

//--------------------------MIPS2C---------------------
#include "game/mips2c/mips2c_private.h"

namespace Mips2C::jak1 {
namespace normalize_frame_quaternions {
u64 execute(void* ctxt) {
  auto* c = (ExecutionContext*)ctxt;
  bool bc = false;
  c->daddiu(sp, sp, -16);                           // daddiu sp, sp, -16
  c->daddiu(s2, s2, -2);                            // daddiu s2, s2, -2
  c->sw(a0, 0, sp);                                 // sw a0, 0(sp)
  c->daddiu(a0, a0, 128);                           // daddiu a0, a0, 128

#ifdef __aarch64__
  float ng_in_q[4] = {0, 0, 0, 0};
#endif
  block_1:
  c->lqc2(vf4, 16, a0);                             // lqc2 vf4, 16(a0)
  c->lqc2(vf1, 0, a0);                              // lqc2 vf1, 0(a0)
  c->lqc2(vf7, 32, a0);                             // lqc2 vf7, 32(a0)
#ifdef __aarch64__
  // Capture the PRE-normalize decompressed quaternion (in-place at 16(a0)
  // before a0 advances) so the NaN log shows whether the input was already
  // zero/garbage (decompressor/anim-link problem) or sane (normalize math).
  if (gpose::enabled()) {
    u32 ia = (u32)c->sgpr64(a0) + 16;
    if (ia >= 0x1000 && ia < (u32)(128 * 1024 * 1024 - 16)) {
      memcpy(ng_in_q, g_ee_main_mem + ia, 16);
    }
  }
#endif
  c->vmul(DEST::xyzw, vf10, vf4, vf4);              // vmul.xyzw vf10, vf4, vf4
  c->vmove(DEST::w, vf1, vf0);                      // vmove.w vf1, vf0
  c->vmove(DEST::w, vf7, vf0);                      // vmove.w vf7, vf0
  c->vmula_bc(DEST::xyzw, BC::w, vf0, vf10);        // vmulaw.xyzw acc, vf0, vf10
  c->vmadda_bc(DEST::xyzw, BC::z, vf0, vf10);       // vmaddaz.xyzw acc, vf0, vf10
  c->vmadda_bc(DEST::xyzw, BC::y, vf0, vf10);       // vmadday.xyzw acc, vf0, vf10
  c->vmadd_bc(DEST::xyzw, BC::x, vf10, vf0, vf10);  // vmaddx.xyzw vf10, vf0, vf10
  c->sqc2(vf1, 0, a0);                              // sqc2 vf1, 0(a0)
  c->sqc2(vf7, 32, a0);                             // sqc2 vf7, 32(a0)
  c->daddiu(a0, a0, 48);                            // daddiu a0, a0, 48
  c->vrsqrt(vf0, BC::w, vf10, BC::w);               // vrsqrt Q, vf0.w, vf10.w
  c->vwaitq();                                      // vwaitq
  c->vmulq(DEST::xyzw, vf4, vf4);                   // vmulq.xyzw vf4, vf4, Q
  c->daddiu(s2, s2, -1);                            // daddiu s2, s2, -1
  bc = c->sgpr64(s2) != 0;                          // bne s2, r0, L46
  c->sqc2(vf4, -32, a0);                            // sqc2 vf4, -32(a0)
#ifdef __aarch64__
  // Gcine-pose: catch NaN quaternions emitted by the normalize (1/sqrt(0) of a
  // zero/garbage decompressed quat). This is the source the cspace bad-matrix
  // tripwire sees downstream.
  if (gpose::enabled()) {
    // a0 has advanced +48 here; the joint's transformq is in-place:
    // trans@(a0-48), quat@(a0-32), scale@(a0-16). Scan ALL THREE so we learn
    // whether the decompressed accumulator itself carries a NaN (trans/scale
    // included) vs only the quaternion. A NaN here = the NaN is born in the
    // decompressor/source data; a clean accumulator = the NaN is introduced
    // later in the goalc matrix-build (matrix<-transformq! / quaternion->matrix).
    u32 ja = (u32)c->sgpr64(a0) - 48;
    if (ja >= 0x1000 && ja < (u32)(128 * 1024 * 1024 - 48)) {
      float tq[12];
      memcpy(tq, g_ee_main_mem + ja, 48);  // [0..3]=trans [4..7]=quat [8..11]=scale
      bool bad = false;
      for (int i = 0; i < 12; i++) {
        if (!std::isfinite(tq[i])) {
          bad = true;
          break;
        }
      }
      if (bad) {
        gpose::g_norm_nan.fetch_add(1, std::memory_order_relaxed);
        int nl = gpose::g_norm_log.fetch_add(1, std::memory_order_relaxed);
        if (nl < 100) {
          fprintf(stderr,
                  "GPOSE-NORMNAN #%d j@0x%x trans=(%.3g %.3g %.3g) quat=(%.4g %.4g %.4g %.4g) "
                  "scale=(%.3g %.3g %.3g) in_q=(%.4g %.4g %.4g %.4g)\n",
                  nl, ja, tq[0], tq[1], tq[2], tq[4], tq[5], tq[6], tq[7], tq[8], tq[9], tq[10],
                  ng_in_q[0], ng_in_q[1], ng_in_q[2], ng_in_q[3]);
        }
      }
    }
  }
#endif
  if (bc) {goto block_1;}                           // branch non-likely

  c->lw(a0, 0, sp);                                 // lw a0, 0(sp)
  // nop                                            // sll r0, r0, 0
  //jr ra                                           // jr ra
  c->daddiu(sp, sp, 16);                            // daddiu sp, sp, 16
  goto end_of_function;                             // return

  //jr ra                                           // jr ra
  c->daddu(sp, sp, r0);                             // daddu sp, sp, r0
  goto end_of_function;                             // return

  // nop                                            // sll r0, r0, 0
  // nop                                            // sll r0, r0, 0
  end_of_function:
  return c->gprs[v0].du64[0];
}

} // namespace normalize_frame_quaternions
} // namespace Mips2C

//--------------------------MIPS2C---------------------
#include "game/mips2c/mips2c_private.h"

namespace Mips2C::jak1 {
namespace clear_frame_accumulator {
u64 execute(void* ctxt) {
  auto* c = (ExecutionContext*)ctxt;
  bool bc = false;
  c->daddiu(sp, sp, -16);                           // daddiu sp, sp, -16
  // nop                                            // sll r0, r0, 0
  c->sw(a0, 0, sp);                                 // sw a0, 0(sp)
  // nop                                            // sll r0, r0, 0
  c->sq(r0, 0, a0);                                 // sq r0, 0(a0)
  c->daddiu(s2, s2, -2);                            // daddiu s2, s2, -2
  c->sq(r0, 16, a0);                                // sq r0, 16(a0)
  // nop                                            // sll r0, r0, 0
  c->sq(r0, 32, a0);                                // sq r0, 32(a0)
  // nop                                            // sll r0, r0, 0
  c->sq(r0, 48, a0);                                // sq r0, 48(a0)
  // nop                                            // sll r0, r0, 0
  c->sq(r0, 64, a0);                                // sq r0, 64(a0)
  // nop                                            // sll r0, r0, 0
  c->sq(r0, 80, a0);                                // sq r0, 80(a0)
  // nop                                            // sll r0, r0, 0
  c->sq(r0, 96, a0);                                // sq r0, 96(a0)
  // nop                                            // sll r0, r0, 0
  c->sq(r0, 112, a0);                               // sq r0, 112(a0)
  c->daddiu(a0, a0, 128);                           // daddiu a0, a0, 128

  block_1:
  c->sq(r0, 0, a0);                                 // sq r0, 0(a0)
  c->daddiu(s2, s2, -1);                            // daddiu s2, s2, -1
  c->sq(r0, 16, a0);                                // sq r0, 16(a0)
  c->daddiu(a0, a0, 48);                            // daddiu a0, a0, 48
  // nop                                            // sll r0, r0, 0
  // nop                                            // sll r0, r0, 0
  bc = c->sgpr64(s2) != 0;                          // bne s2, r0, L48
  c->sq(r0, -16, a0);                               // sq r0, -16(a0)
  if (bc) {goto block_1;}                           // branch non-likely

  c->lw(a0, 0, sp);                                 // lw a0, 0(sp)
  // nop                                            // sll r0, r0, 0
  //jr ra                                           // jr ra
  c->daddiu(sp, sp, 16);                            // daddiu sp, sp, 16
  goto end_of_function;                             // return

  //jr ra                                           // jr ra
  c->daddu(sp, sp, r0);                             // daddu sp, sp, r0
  goto end_of_function;                             // return

  // nop                                            // sll r0, r0, 0
  // nop                                            // sll r0, r0, 0
  // nop                                            // sll r0, r0, 0
  end_of_function:
  return c->gprs[v0].du64[0];
}
} // namespace clear_frame_accumulator
} // namespace Mips2C


//--------------------------MIPS2C---------------------
#include "game/mips2c/mips2c_private.h"

namespace Mips2C::jak1 {
namespace calc_animation_from_spr {


u64 execute(void* ctxt) {
  auto* c = (ExecutionContext*)ctxt;
#ifdef __ANDROID__
  // F1a: invocation heartbeat — the title camera-slave's channel PLAYS
  // (frame-group fresh, frame-num cycling) yet its joint pose freezes from
  // logo-loop on. Zero calls here past that point = eval skipped for clone
  // channels; climbing calls = decompress runs but its spad inputs are
  // constant. One line per ~5 s of calls. Run-12: ZERO calls in 150 s.
  {
    static int s_f1a_calls = 0;
    if ((s_f1a_calls++ % 300) == 0) {
      fprintf(stderr, "F1A-CALCANIM calls=%d\n", s_f1a_calls);
    }
  }
#else
  // Desktop twin (env-gated): is this even called during the title on the
  // known-good backend? Zero on both = wrong suspect; thousands on desktop
  // = Android's foreground joint pipeline never engages.
  {
    static const bool s_dump = getenv("F1A_MERC_DUMP") != nullptr;
    static int s_f1a_calls = 0;
    if (s_dump && (s_f1a_calls++ % 300) == 0) {
      fprintf(stderr, "F1A-CALCANIM calls=%d\n", s_f1a_calls);
    }
  }
#endif
  bool bc = false;
  [[maybe_unused]] u32 call_addr = 0;
  u32 madr, sadr, qwc;
  c->mov64(v1, a1);                                 // or v1, a1, r0
  c->daddiu(sp, sp, -192);                          // daddiu sp, sp, -192
  c->sq(s0, 0, sp);                                 // sq s0, 0(sp)
  c->sq(s1, 16, sp);                                // sq s1, 16(sp)
  c->sq(s2, 32, sp);                                // sq s2, 32(sp)
  c->sq(s3, 48, sp);                                // sq s3, 48(sp)
  c->sq(s4, 64, sp);                                // sq s4, 64(sp)
  c->sq(s5, 80, sp);                                // sq s5, 80(sp)
  c->sq(s6, 96, sp);                                // sq s6, 96(sp)
  c->sq(t8, 112, sp);                               // sq t8, 112(sp)
  c->sq(t9, 128, sp);                               // sq t9, 128(sp)
  c->sq(gp, 144, sp);                               // sq gp, 144(sp)
  c->sq(fp, 160, sp);                               // sq fp, 160(sp)
  c->sq(ra, 176, sp);                               // sq ra, 176(sp)
  c->daddiu(sp, sp, -16);                           // daddiu sp, sp, -16
  c->mov128_vf_gpr(vf15, r0);                       // qmtc2.i vf15, r0
  c->sw(a1, 0, sp);                                 // sw a1, 0(sp)
  //c->lui(v1, 28672);                                // lui v1, 28672
  get_fake_spad_addr(v1, cache.fake_scratchpad_data, 0, c);
  c->lw(s1, 2400, v1);                              // lw s1, 2400(v1)
  c->daddiu(t7, v1, 1824);                          // daddiu t7, v1, 1824
  c->lui(s0, 4096);                                 // lui s0, 4096
  c->daddiu(t1, v1, 7344);                          // daddiu t1, v1, 7344
  bc = c->sgpr64(s1) == 0;                          // beq s1, r0, L7
  c->ori(s0, s0, 54272);                            // ori s0, s0, 54272 // spr to (d400)
  if (bc) {goto block_12;}                          // branch non-likely

  c->lw(t2, 0, t7);                                 // lw t2, 0(t7)
  c->addiu(t3, r0, 7408);                           // addiu t3, r0, 7408
  c->lw(t4, 4, t7);                                 // lw t4, 4(t7)
  c->addiu(v1, r0, 256);                            // addiu v1, r0, 256
  // c->sw(t2, 16, s0);                                // sw t2, 16(s0)
  madr = c->sgpr64(t2);
  c->vadd_bc(DEST::xyzw, BC::w, vf14, vf15, vf0);   // vaddw.xyzw vf14, vf15, vf0
  //c->sw(t3, 128, s0);                               // sw t3, 128(s0)
  sadr = c->sgpr64(t3);
  // nop                                            // sll r0, r0, 0
  //c->sw(t4, 32, s0);                                // sw t4, 32(s0)
  qwc = c->sgpr64(t4);
  // Unknown instr: sync.l
  //c->sw(v1, 0, s0);                                 // sw v1, 0(s0)
  spad_to_dma_no_sadr_off(cache.fake_scratchpad_data, madr, sadr, qwc);
  // Unknown instr: sync.l
  c->load_symbol(t9, cache.clear_frame_accumulator);// lw t9, clear-frame-accumulator(s7)
  c->vadd(DEST::yz, vf14, vf14, vf14);              // vadd.yz vf14, vf14, vf14
  c->lw(s2, 0, sp);                                 // lw s2, 0(sp)
  // nop                                            // sll r0, r0, 0
  call_addr = c->gprs[t9].du32[0];                  // function call:
  c->vadd(DEST::yz, vf14, vf14, vf14);              // vadd.yz vf14, vf14, vf14
  //c->jalr(call_addr);                               // jalr ra, t9
  clear_frame_accumulator::execute(c);

  block_2:
//  c->lw(v1, 0, s0);                                 // lw v1, 0(s0)
//  // nop                                            // sll r0, r0, 0
//  c->andi(v1, v1, 256);                             // andi v1, v1, 256
//  // nop                                            // sll r0, r0, 0
//  // nop                                            // sll r0, r0, 0
//  // nop                                            // sll r0, r0, 0
//  bc = c->sgpr64(v1) != 0;                          // bne v1, r0, L3
//  // nop                                            // sll r0, r0, 0
//  if (bc) {goto block_2;}                           // branch non-likely

  c->lw(t2, 8, t7);                                 // lw t2, 8(t7)
  c->addiu(t3, r0, 9616);                           // addiu t3, r0, 9616
  c->lw(t4, 12, t7);                                // lw t4, 12(t7)
  c->addiu(v1, r0, 256);                            // addiu v1, r0, 256
  //c->sw(t2, 16, s0);                                // sw t2, 16(s0)
  madr = c->sgpr64(t2);
  // nop                                            // sll r0, r0, 0
  //c->sw(t3, 128, s0);                               // sw t3, 128(s0)
  sadr = c->sgpr64(t3);
  // nop                                            // sll r0, r0, 0
  //c->sw(t4, 32, s0);                                // sw t4, 32(s0)
  qwc = c->sgpr64(t4);
  // Unknown instr: sync.l
  //c->sw(v1, 0, s0);                                 // sw v1, 0(s0)
  spad_to_dma_no_sadr_off(cache.fake_scratchpad_data, madr, sadr, qwc);
  // Unknown instr: sync.l
  c->lw(a2, 16, t7);                                // lw a2, 16(t7)
  //c->lui(a1, 28672);                                // lui a1, 28672
  get_fake_spad_addr(a1, cache.fake_scratchpad_data, 0, c);
  c->load_symbol(t9, cache.decompress_fixed_data_to_accumulator);// lw t9, decompress-fixed-data-to-accumulator(s7)
  c->daddiu(a1, a1, 7408);                          // daddiu a1, a1, 7408
  call_addr = c->gprs[t9].du32[0];                  // function call:
  c->daddiu(s1, s1, -1);                            // daddiu s1, s1, -1
  //c->jalr(call_addr);                               // jalr ra, t9
  decompress_fixed_data_to_accumulator::execute(c);

//  block_4:
//  c->lw(v1, 0, s0);                                 // lw v1, 0(s0)
//  // nop                                            // sll r0, r0, 0
//  c->andi(v1, v1, 256);                             // andi v1, v1, 256
//  // nop                                            // sll r0, r0, 0
//  // nop                                            // sll r0, r0, 0
//  // nop                                            // sll r0, r0, 0
//  bc = c->sgpr64(v1) != 0;                          // bne v1, r0, L4
//  // nop                                            // sll r0, r0, 0
//  if (bc) {goto block_4;}                           // branch non-likely

  bc = c->sgpr64(s1) == 0;                          // beq s1, r0, L5
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_7;}                           // branch non-likely

  c->lw(t2, 24, t7);                                // lw t2, 24(t7)
  c->addiu(t3, r0, 7408);                           // addiu t3, r0, 7408
  c->lw(t4, 28, t7);                                // lw t4, 28(t7)
  c->addiu(v1, r0, 256);                            // addiu v1, r0, 256
  //c->sw(t2, 16, s0);                                // sw t2, 16(s0)
  madr = c->sgpr64(t2);
  // nop                                            // sll r0, r0, 0
  //c->sw(t3, 128, s0);                               // sw t3, 128(s0)
  sadr = c->sgpr64(t3);
  // nop                                            // sll r0, r0, 0
  //c->sw(t4, 32, s0);                                // sw t4, 32(s0)
  qwc = c->sgpr64(t4);
  // Unknown instr: sync.l
  //c->sw(v1, 0, s0);                                 // sw v1, 0(s0)
  spad_to_dma_no_sadr_off(cache.fake_scratchpad_data, madr, sadr, qwc);
  // Unknown instr: sync.l

  block_7:
  c->lw(t0, 20, t7);                                // lw t0, 20(t7)
  //c->lui(a1, 28672);                                // lui a1, 28672
  get_fake_spad_addr(a1, cache.fake_scratchpad_data, 0, c);
  c->lw(a2, 16, t7);                                // lw a2, 16(t7)
  c->daddiu(a1, a1, 9616);                          // daddiu a1, a1, 9616
  bc = c->sgpr64(t0) == 0;                          // beq t0, r0, L6
  // nop                                            // sll r0, r0, 0
  if (bc) {goto block_10;}                          // branch non-likely

  c->lw(a3, 12, t7);                                // lw a3, 12(t7)
  // nop                                            // sll r0, r0, 0
  c->load_symbol(t9, cache.decompress_frame_data_pair_to_accumulator);// lw t9, decompress-frame-data-pair-to-accumulator(s7)
  // nop                                            // sll r0, r0, 0
  call_addr = c->gprs[t9].du32[0];                  // function call:
  c->sll(a3, a3, 3);                                // sll a3, a3, 3
  //c->jalr(call_addr);                               // jalr ra, t9
  decompress_frame_data_pair_to_accumulator::execute(c);
  bc = c->sgpr64(s1) != 0;                          // bne s1, r0, L3
  c->daddiu(t7, t7, 24);                            // daddiu t7, t7, 24
  if (bc) {goto block_2;}                           // branch non-likely

  c->load_symbol(t9, cache.normalize_frame_quaternions);// lw t9, normalize-frame-quaternions(s7)
  // nop                                            // sll r0, r0, 0
  c->lw(s2, 0, sp);                                 // lw s2, 0(sp)
  // nop                                            // sll r0, r0, 0
  call_addr = c->gprs[t9].du32[0];                  // function call:
  // nop                                            // sll r0, r0, 0
  //c->jalr(call_addr);                               // jalr ra, t9
  normalize_frame_quaternions::execute(c);
  c->daddiu(sp, sp, 16);                            // daddiu sp, sp, 16
  // nop                                            // sll r0, r0, 0
  c->lq(s0, 0, sp);                                 // lq s0, 0(sp)
  c->lq(s1, 16, sp);                                // lq s1, 16(sp)
  c->lq(s2, 32, sp);                                // lq s2, 32(sp)
  c->lq(s3, 48, sp);                                // lq s3, 48(sp)
  c->lq(s4, 64, sp);                                // lq s4, 64(sp)
  c->lq(s5, 80, sp);                                // lq s5, 80(sp)
  c->lq(s6, 96, sp);                                // lq s6, 96(sp)
  c->lq(t8, 112, sp);                               // lq t8, 112(sp)
  c->lq(t9, 128, sp);                               // lq t9, 128(sp)
  c->lq(gp, 144, sp);                               // lq gp, 144(sp)
  c->lq(ra, 176, sp);                               // lq ra, 176(sp)
  c->lq(fp, 160, sp);                               // lq fp, 160(sp)
  //jr ra                                           // jr ra
  c->daddiu(sp, sp, 192);                           // daddiu sp, sp, 192
  goto end_of_function;                             // return


  block_10:
  c->load_symbol(t9, cache.decompress_frame_data_to_accumulator);// lw t9, decompress-frame-data-to-accumulator(s7)
  // nop                                            // sll r0, r0, 0
  call_addr = c->gprs[t9].du32[0];                  // function call:
  // nop                                            // sll r0, r0, 0
  //c->jalr(call_addr);                               // jalr ra, t9
  decompress_frame_data_to_accumulator::execute(c);
  bc = c->sgpr64(s1) != 0;                          // bne s1, r0, L3
  c->daddiu(t7, t7, 24);                            // daddiu t7, t7, 24
  if (bc) {goto block_2;}                           // branch non-likely

  c->load_symbol(t9, cache.normalize_frame_quaternions);// lw t9, normalize-frame-quaternions(s7)
  // nop                                            // sll r0, r0, 0
  c->lw(s2, 0, sp);                                 // lw s2, 0(sp)
  // nop                                            // sll r0, r0, 0
  call_addr = c->gprs[t9].du32[0];                  // function call:
  // nop                                            // sll r0, r0, 0
  //c->jalr(call_addr);                               // jalr ra, t9
  normalize_frame_quaternions::execute(c);

  block_12:
  c->daddiu(sp, sp, 16);                            // daddiu sp, sp, 16
  // nop                                            // sll r0, r0, 0
  c->lq(s0, 0, sp);                                 // lq s0, 0(sp)
  c->lq(s1, 16, sp);                                // lq s1, 16(sp)
  c->lq(s2, 32, sp);                                // lq s2, 32(sp)
  c->lq(s3, 48, sp);                                // lq s3, 48(sp)
  c->lq(s4, 64, sp);                                // lq s4, 64(sp)
  c->lq(s5, 80, sp);                                // lq s5, 80(sp)
  c->lq(s6, 96, sp);                                // lq s6, 96(sp)
  c->lq(t8, 112, sp);                               // lq t8, 112(sp)
  c->lq(t9, 128, sp);                               // lq t9, 128(sp)
  c->lq(gp, 144, sp);                               // lq gp, 144(sp)
  c->lq(ra, 176, sp);                               // lq ra, 176(sp)
  c->lq(fp, 160, sp);                               // lq fp, 160(sp)
  //jr ra                                           // jr ra
  c->daddiu(sp, sp, 192);                           // daddiu sp, sp, 192
  goto end_of_function;                             // return

  //jr ra                                           // jr ra
  c->daddu(sp, sp, r0);                             // daddu sp, sp, r0
  goto end_of_function;                             // return

  // nop                                            // sll r0, r0, 0
  // nop                                            // sll r0, r0, 0
  // nop                                            // sll r0, r0, 0
  end_of_function:
  return c->gprs[v0].du64[0];
}

void link() {
  cache.clear_frame_accumulator = intern_from_c("clear-frame-accumulator").c();
  cache.decompress_fixed_data_to_accumulator = intern_from_c("decompress-fixed-data-to-accumulator").c();
  cache.decompress_frame_data_pair_to_accumulator = intern_from_c("decompress-frame-data-pair-to-accumulator").c();
  cache.decompress_frame_data_to_accumulator = intern_from_c("decompress-frame-data-to-accumulator").c();
  cache.normalize_frame_quaternions = intern_from_c("normalize-frame-quaternions").c();
  cache.fake_scratchpad_data = intern_from_c("*fake-scratchpad-data*").c();

  gLinkedFunctionTable.reg("calc-animation-from-spr", execute, 1024);
}

} // namespace calc_animation_from_spr
} // namespace Mips2C

//--------------------------MIPS2C---------------------
#include "game/mips2c/mips2c_private.h"

namespace Mips2C::jak1 {
namespace cspace_parented_transformq_joint {
// A37 canary buffer (shared by the pre/post checks below).
u8* g_a37_csp_canary = nullptr;
// F1b TRS tap (both backends): windowed dump of this function's INPUT
// transformq (= the GOAL decompressor's per-joint output) and OUTPUT bone
// row3. Diffing device vs desktop names whether the title-course freeze is
// upstream (tq frozen => GOAL decompress chain) or at/after this bone
// build (tq moves, bone frozen). Gated by OG_F1B_TRS (desktop env) or the
// f1b_trs marker file in the app files dir (device, run-as touch); 48-call
// window every 8192 calls; no behavior change.
bool f1b_trs_enabled() {
  static const bool s_on = [] {
    if (getenv("OG_F1B_TRS")) {
      return true;
    }
#ifdef __ANDROID__
    auto p = file_util::get_jak_project_dir() / "f1b_trs";
    if (access(p.string().c_str(), F_OK) == 0) {
      fprintf(stderr, "F1B-TRS knob armed (%s)\n", p.string().c_str());
      return true;
    }
#endif
    return false;
  }();
  return s_on;
}

u64 execute(void* ctxt) {
  auto* c = (ExecutionContext*)ctxt;
  bool bc = false;
#ifdef __aarch64__
  // === Gcine-pose fix (arm64) ====================================================
  // Cinematic character skeletons explode to NaN bone matrices on arm64. ROOT
  // CAUSE (objectively localized, see Gpose-fix-summary.md): the new-game intro
  // streams the sage-intro joint anims, but their align joint never finishes its
  // "master slot" link in time on Android ("loader stall"/"could not find a
  // master slot to link"). The root-motion aligner (compute-alignment! ->
  // matrix-inv-scale!, ENGINE.CGO) then reads a degenerate align matrix and does
  // 1.0/(vector-length==0) -> +inf -> NaN in the align quaternion/translation;
  // the goalc root builder (cspace<-transformq+trans!) bakes that NaN actor
  // world-translation into the SKELETON ROOT bone, and THIS body multiplies every
  // child joint by that NaN parent -> the whole skeleton goes NaN -> merc skins to
  // NaN -> the geometry flickers/vanishes (the owner's "pose blink"). It is NOT
  // FTZ (engine-thread FPCR reads 0x0) and the decompressed accumulator
  // (trans/quat/scale) is clean -- the NaN enters only via the root translation.
  // The correct fix is a degenerate-scale guard in matrix-inv-scale! (ENGINE.CGO),
  // but boot CGOs cannot be safely rebuilt/reseeded on this device (libgk.so is
  // pinned to their layout -> SIGILL). So we repair at this propagation boundary,
  // the recurring arm64 joint/merc class: before multiplying, if the PARENT bone
  // matrix has any non-finite element, restore that element from a per-bone
  // last-finite cache (or identity), so a child is never built from a NaN parent.
  // Always-on (the fix), engine-thread only (no lock). x86 path is unchanged.
  {
    static std::unordered_map<u32, std::array<float, 16>> s_lastgood;
    const u32 MX = (u32)(128 * 1024 * 1024 - 64);
    u32 cspace_v = (u32)c->sgpr64(a0);
    if (cspace_v >= 0x1000 && cspace_v < MX) {
      u32 par_cs = 0;
      memcpy(&par_cs, g_ee_main_mem + cspace_v + 0, 4);  // cspace.parent
      if (par_cs >= 0x1000 && par_cs < MX) {
        u32 par_bone = 0;
        memcpy(&par_bone, g_ee_main_mem + par_cs + 16, 4);  // parent.bone (== body's t0)
        if (par_bone >= 0x1000 && par_bone < MX) {
          float* pm = reinterpret_cast<float*>(g_ee_main_mem + par_bone);
          bool finite = true;
          for (int i = 0; i < 16; i++) {
            if (!std::isfinite(pm[i])) {
              finite = false;
              break;
            }
          }
          if (finite) {
            std::array<float, 16> snap;
            memcpy(snap.data(), pm, 64);
            s_lastgood[par_bone] = snap;
          } else {
            static const float kIdent[16] = {1, 0, 0, 0, 0, 1, 0, 0,
                                              0, 0, 1, 0, 0, 0, 0, 1};
            auto it = s_lastgood.find(par_bone);
            const float* good = (it != s_lastgood.end()) ? it->second.data() : kIdent;
            for (int i = 0; i < 16; i++) {
              if (!std::isfinite(pm[i])) {
                pm[i] = good[i];
              }
            }
          }
        }
      }
    }
  }
  // === end Gcine-pose fix ========================================================
#endif
  static u64 s_f1b_n = 0;
  bool f1b_dump = false;
  u32 f1b_a0 = 0, f1b_a1 = 0;
  if (f1b_trs_enabled()) {
    u64 n = s_f1b_n++;
    if ((n & 8191) < 48) {
      f1b_dump = true;
      f1b_a0 = (u32)c->sgpr64(a0);
      f1b_a1 = (u32)c->sgpr64(a1);
    }
  }
  // A37 diag (arm64 bring-up): this body was observed stomping the font
  // object's code through a2 = cspace.bone. Log the pointer args for the
  // first calls and for any bone pointer in the engine-code band so the
  // bad caller/cspace gets named; suspicious calls return without
  // storing (diagnostic only — never fires with healthy bone pointers).
  // arm64-only: the desktop x86 oracle path stays byte-identical.
#ifdef __aarch64__
  {
    static int s_calls = 0;
    u32 a0v = (u32)c->sgpr64(a0);
    u32 a1v = (u32)c->sgpr64(a1);
    u32 bonev = 0, parentv = 0;
    if (a0v >= 0x1000 && a0v < (u32)(128 * 1024 * 1024 - 20)) {
      memcpy(&bonev, g_ee_main_mem + a0v + 16, 4);
      memcpy(&parentv, g_ee_main_mem + a0v, 4);
    }
    bool suspicious = (bonev < 0x100000) || (bonev >= 0x1800000 && bonev < 0x2000000);
    if (gpose::enabled()) {
      gpose::g_calls.fetch_add(1, std::memory_order_relaxed);
      if (suspicious) {
        gpose::g_skips.fetch_add(1, std::memory_order_relaxed);
        gpose::g_total_skips.fetch_add(1, std::memory_order_relaxed);
        int sl = gpose::g_skip_log.fetch_add(1, std::memory_order_relaxed);
        if (sl < 400) {
          // The stale matrix this skip leaves for merc to skin with (its
          // translation row at +48) plus the tq input the GOAL decompressor
          // produced. Tells us if the skipped bone ptr is corrupt vs valid.
          float sx = 0, sy = 0, sz = 0, qx = 0, qy = 0, qz = 0, qw = 0;
          if (bonev >= 0x1000 && bonev < (u32)(128 * 1024 * 1024 - 64)) {
            memcpy(&sx, g_ee_main_mem + bonev + 48, 4);
            memcpy(&sy, g_ee_main_mem + bonev + 52, 4);
            memcpy(&sz, g_ee_main_mem + bonev + 56, 4);
          }
          if (a1v >= 0x1000 && a1v < (u32)(128 * 1024 * 1024 - 64)) {
            memcpy(&qx, g_ee_main_mem + a1v + 16, 4);
            memcpy(&qy, g_ee_main_mem + a1v + 20, 4);
            memcpy(&qz, g_ee_main_mem + a1v + 24, 4);
            memcpy(&qw, g_ee_main_mem + a1v + 28, 4);
          }
          fprintf(stderr,
                  "GPOSE-SKIP #%d csp=0x%x parent=0x%x bone=0x%x stale_t=(%.3f %.3f %.3f) "
                  "in_q=(%.4f %.4f %.4f %.4f)\n",
                  sl, a0v, parentv, bonev, sx, sy, sz, qx, qy, qz, qw);
        }
      }
    }
    if (s_calls < 16 || suspicious) {
      if (s_calls < 200) {
        fprintf(stderr, "A37-CSP call#%d cspace=0x%x tq=0x%x parent=0x%x bone=0x%x%s\n", s_calls,
                a0v, a1v, parentv, bonev, suspicious ? " SUSPICIOUS" : "");
      }
      s_calls++;
      if (suspicious) {
        // F1b: this skip was SILENT past call 200 — make every skipped
        // bone store visible while the TRS tap is armed (capped).
        static int s_f1b_skips = 0;
        if (f1b_trs_enabled() && s_f1b_skips < 200) {
          s_f1b_skips++;
          fprintf(stderr, "F1B-TRS SUSPICIOUS-SKIP #%d csp=0x%x bone=0x%x\n", s_f1b_skips, a0v,
                  bonev);
        }
        return 0;
      }
    } else {
      s_calls++;
    }
    // A37 canary: watch the engine-code band that keeps getting stomped
    // (font object). Snapshot on first call, compare before AND after the
    // body on every call — names whether the stomp happens inside this
    // body or between calls, and at which call number.
    constexpr u32 kCanLo = 0x1900000, kCanLen = 0x18000;
    static bool s_stomp_reported = false;
    if (!g_a37_csp_canary) {
      g_a37_csp_canary = (u8*)malloc(kCanLen);
      memcpy(g_a37_csp_canary, g_ee_main_mem + kCanLo, kCanLen);
      fprintf(stderr, "A37-CSP canary armed [0x%x,0x%x)\n", kCanLo, kCanLo + kCanLen);
    } else if (!s_stomp_reported &&
               memcmp(g_a37_csp_canary, g_ee_main_mem + kCanLo, kCanLen) != 0) {
      s_stomp_reported = true;
      u32 first = 0;
      for (u32 i = 0; i < kCanLen; i += 4) {
        if (memcmp(g_a37_csp_canary + i, g_ee_main_mem + kCanLo + i, 4) != 0) {
          first = kCanLo + i;
          break;
        }
      }
      u32 now = 0, was = 0;
      memcpy(&was, g_a37_csp_canary + (first - kCanLo), 4);
      memcpy(&now, g_ee_main_mem + first, 4);
      fprintf(stderr, "A37-CSP CANARY-STOMP before-call#%d first=0x%x was=0x%08x now=0x%08x\n",
              s_calls, first, was, now);
    }
  }
#endif  // __aarch64__
  // nop                                            // sll r0, r0, 0
  c->lw(a3, 0, a0);                                 // lw a3, 0(a0)
  c->lui(v1, 16256);                                // lui v1, 16256
  c->lqc2(vf5, 16, a1);                             // lqc2 vf5, 16(a1)
  c->mtc1(f0, v1);                                  // mtc1 f0, v1
  c->lw(t0, 16, a3);                                // lw t0, 16(a3)
  // nop                                            // sll r0, r0, 0
  c->lw(a2, 16, a0);                                // lw a2, 16(a0)
  c->vadd(DEST::xyzw, vf6, vf5, vf5);               // vadd.xyzw vf6, vf5, vf5
  c->lwc1(f1, 64, t0);                              // lwc1 f1, 64(t0)
  c->vadd_bc(DEST::x, BC::w, vf2, vf0, vf5);        // vaddw.x vf2, vf0, vf5
  c->lqc2(vf15, 0, a1);                             // lqc2 vf15, 0(a1)
  c->vadd_bc(DEST::y, BC::z, vf2, vf0, vf5);        // vaddz.y vf2, vf0, vf5
  c->lqc2(vf1, 32, a1);                             // lqc2 vf1, 32(a1)
  c->divs_accurate(f4, f0, f1);                              // div.s f4, f0, f1
  c->lqc2(vf7, 0, t0);                              // lqc2 vf7, 0(t0)
  c->vsub_bc(DEST::z, BC::y, vf2, vf0, vf5);        // vsuby.z vf2, vf0, vf5
  c->lqc2(vf8, 16, t0);                             // lqc2 vf8, 16(t0)
  c->vsub_bc(DEST::w, BC::w, vf2, vf0, vf0);        // vsubw.w vf2, vf0, vf0
  c->lqc2(vf9, 32, t0);                             // lqc2 vf9, 32(t0)
  c->vsub_bc(DEST::x, BC::z, vf3, vf0, vf5);        // vsubz.x vf3, vf0, vf5
  c->lqc2(vf10, 48, t0);                            // lqc2 vf10, 48(t0)
  c->vadd_bc(DEST::y, BC::w, vf3, vf0, vf5);        // vaddw.y vf3, vf0, vf5
  c->lwc1(f2, 68, t0);                              // lwc1 f2, 68(t0)
  c->vadd_bc(DEST::z, BC::x, vf3, vf0, vf5);        // vaddx.z vf3, vf0, vf5
  c->sqc2(vf1, 64, a2);                             // sqc2 vf1, 64(a2)
  c->vsub_bc(DEST::w, BC::w, vf3, vf0, vf0);        // vsubw.w vf3, vf0, vf0
  c->lwc1(f3, 72, t0);                              // lwc1 f3, 72(t0)
  c->vadd_bc(DEST::x, BC::y, vf4, vf0, vf5);        // vaddy.x vf4, vf0, vf5
  c->lw(v1, 76, t0);                                // lw v1, 76(t0)
  c->vsub_bc(DEST::y, BC::x, vf4, vf0, vf5);        // vsubx.y vf4, vf0, vf5
  c->mfc1(t1, f4);                                  // mfc1 t1, f4
  c->vadd_bc(DEST::z, BC::w, vf4, vf0, vf5);        // vaddw.z vf4, vf0, vf5
  c->divs_accurate(f4, f0, f2);                              // div.s f4, f0, f2
  c->vsub_bc(DEST::w, BC::w, vf4, vf0, vf0);        // vsubw.w vf4, vf0, vf0
  c->vopmula(vf6, vf2);                             // vopmula.xyz acc, vf6, vf2
  c->vopmsub(vf2, vf2, vf6);                        // vopmsub.xyz vf2, vf2, vf6
  c->vopmula(vf6, vf3);                             // vopmula.xyz acc, vf6, vf3
  c->vopmsub(vf3, vf3, vf6);                        // vopmsub.xyz vf3, vf3, vf6
  c->vopmula(vf6, vf4);                             // vopmula.xyz acc, vf6, vf4
  c->vopmsub(vf4, vf4, vf6);                        // vopmsub.xyz vf4, vf4, vf6
  c->vadd_bc(DEST::x, BC::w, vf2, vf2, vf0);        // vaddw.x vf2, vf2, vf0
  c->vadd_bc(DEST::y, BC::w, vf3, vf3, vf0);        // vaddw.y vf3, vf3, vf0
  c->vadd_bc(DEST::z, BC::w, vf4, vf4, vf0);        // vaddw.z vf4, vf4, vf0
  c->mfc1(t2, f4);                                  // mfc1 t2, f4
  bc = c->sgpr64(v1) != 0;                          // bne v1, r0, L50
  c->divs_accurate(f4, f0, f3);                              // div.s f4, f0, f3
  if (bc) {goto block_2;}                           // branch non-likely

  c->vmul_bc(DEST::xyzw, BC::x, vf2, vf2, vf1);     // vmulx.xyzw vf2, vf2, vf1
  c->vmul_bc(DEST::xyzw, BC::y, vf3, vf3, vf1);     // vmuly.xyzw vf3, vf3, vf1
  c->vmul_bc(DEST::xyzw, BC::z, vf4, vf4, vf1);     // vmulz.xyzw vf4, vf4, vf1
  c->vmula_bc(DEST::xyzw, BC::x, vf7, vf2);         // vmulax.xyzw acc, vf7, vf2
  c->vmadda_bc(DEST::xyzw, BC::y, vf8, vf2);        // vmadday.xyzw acc, vf8, vf2
  c->vmadda_bc(DEST::xyzw, BC::z, vf9, vf2);        // vmaddaz.xyzw acc, vf9, vf2
  c->vmadd_bc(DEST::xyzw, BC::w, vf11, vf10, vf2);  // vmaddw.xyzw vf11, vf10, vf2
  c->vmula_bc(DEST::xyzw, BC::x, vf7, vf3);         // vmulax.xyzw acc, vf7, vf3
  c->vmadda_bc(DEST::xyzw, BC::y, vf8, vf3);        // vmadday.xyzw acc, vf8, vf3
  c->vmadda_bc(DEST::xyzw, BC::z, vf9, vf3);        // vmaddaz.xyzw acc, vf9, vf3
  c->vmadd_bc(DEST::xyzw, BC::w, vf12, vf10, vf3);  // vmaddw.xyzw vf12, vf10, vf3
  c->vmula_bc(DEST::xyzw, BC::x, vf7, vf4);         // vmulax.xyzw acc, vf7, vf4
  c->vmadda_bc(DEST::xyzw, BC::y, vf8, vf4);        // vmadday.xyzw acc, vf8, vf4
  c->vmadda_bc(DEST::xyzw, BC::z, vf9, vf4);        // vmaddaz.xyzw acc, vf9, vf4
  c->vmadd_bc(DEST::xyzw, BC::w, vf13, vf10, vf4);  // vmaddw.xyzw vf13, vf10, vf4
  c->vmula_bc(DEST::xyzw, BC::x, vf7, vf15);        // vmulax.xyzw acc, vf7, vf15
  c->vmadda_bc(DEST::xyzw, BC::y, vf8, vf15);       // vmadday.xyzw acc, vf8, vf15
  c->vmadda_bc(DEST::xyzw, BC::z, vf9, vf15);       // vmaddaz.xyzw acc, vf9, vf15
  c->vmadd_bc(DEST::xyzw, BC::w, vf14, vf10, vf0);  // vmaddw.xyzw vf14, vf10, vf0
  c->sqc2(vf11, 0, a2);                             // sqc2 vf11, 0(a2)
  c->sqc2(vf12, 16, a2);                            // sqc2 vf12, 16(a2)
  c->sqc2(vf13, 32, a2);                            // sqc2 vf13, 32(a2)
  c->sqc2(vf14, 48, a2);                            // sqc2 vf14, 48(a2)
  //jr ra                                           // jr ra
  // nop                                            // sll r0, r0, 0
  goto end_of_function;                             // return


  block_2:
  c->pextlw(t1, t2, t1);                            // pextlw t1, t2, t1
  c->vmul_bc(DEST::xyzw, BC::x, vf2, vf2, vf1);     // vmulx.xyzw vf2, vf2, vf1
  c->vmul_bc(DEST::xyzw, BC::y, vf3, vf3, vf1);     // vmuly.xyzw vf3, vf3, vf1
  c->vmul_bc(DEST::xyzw, BC::z, vf4, vf4, vf1);     // vmulz.xyzw vf4, vf4, vf1
  c->mfc1(t3, f4);                                  // mfc1 t3, f4
  c->pcpyld(t1, t3, t1);                            // pcpyld t1, t3, t1
  c->mov128_vf_gpr(vf16, t1);                       // qmtc2.i vf16, t1
  c->vmul(DEST::xyzw, vf2, vf2, vf16);              // vmul.xyzw vf2, vf2, vf16
  c->vmul(DEST::xyzw, vf3, vf3, vf16);              // vmul.xyzw vf3, vf3, vf16
  c->vmul(DEST::xyzw, vf4, vf4, vf16);              // vmul.xyzw vf4, vf4, vf16
  c->vmula_bc(DEST::xyzw, BC::x, vf7, vf2);         // vmulax.xyzw acc, vf7, vf2
  c->vmadda_bc(DEST::xyzw, BC::y, vf8, vf2);        // vmadday.xyzw acc, vf8, vf2
  c->vmadda_bc(DEST::xyzw, BC::z, vf9, vf2);        // vmaddaz.xyzw acc, vf9, vf2
  c->vmadd_bc(DEST::xyzw, BC::w, vf11, vf10, vf2);  // vmaddw.xyzw vf11, vf10, vf2
  c->vmula_bc(DEST::xyzw, BC::x, vf7, vf3);         // vmulax.xyzw acc, vf7, vf3
  c->vmadda_bc(DEST::xyzw, BC::y, vf8, vf3);        // vmadday.xyzw acc, vf8, vf3
  c->vmadda_bc(DEST::xyzw, BC::z, vf9, vf3);        // vmaddaz.xyzw acc, vf9, vf3
  c->vmadd_bc(DEST::xyzw, BC::w, vf12, vf10, vf3);  // vmaddw.xyzw vf12, vf10, vf3
  c->vmula_bc(DEST::xyzw, BC::x, vf7, vf4);         // vmulax.xyzw acc, vf7, vf4
  c->vmadda_bc(DEST::xyzw, BC::y, vf8, vf4);        // vmadday.xyzw acc, vf8, vf4
  c->vmadda_bc(DEST::xyzw, BC::z, vf9, vf4);        // vmaddaz.xyzw acc, vf9, vf4
  c->vmadd_bc(DEST::xyzw, BC::w, vf13, vf10, vf4);  // vmaddw.xyzw vf13, vf10, vf4
  c->vmula_bc(DEST::xyzw, BC::x, vf7, vf15);        // vmulax.xyzw acc, vf7, vf15
  c->vmadda_bc(DEST::xyzw, BC::y, vf8, vf15);       // vmadday.xyzw acc, vf8, vf15
  c->vmadda_bc(DEST::xyzw, BC::z, vf9, vf15);       // vmaddaz.xyzw acc, vf9, vf15
  c->vmadd_bc(DEST::xyzw, BC::w, vf14, vf10, vf0);  // vmaddw.xyzw vf14, vf10, vf0
  c->sqc2(vf11, 0, a2);                             // sqc2 vf11, 0(a2)
  c->sqc2(vf12, 16, a2);                            // sqc2 vf12, 16(a2)
  c->sqc2(vf13, 32, a2);                            // sqc2 vf13, 32(a2)
  c->sqc2(vf14, 48, a2);                            // sqc2 vf14, 48(a2)
  //jr ra                                           // jr ra
  // nop                                            // sll r0, r0, 0
  goto end_of_function;                             // return

  //jr ra                                           // jr ra
  c->daddu(sp, sp, r0);                             // daddu sp, sp, r0
  goto end_of_function;                             // return

  // nop                                            // sll r0, r0, 0
  // nop                                            // sll r0, r0, 0
  // nop                                            // sll r0, r0, 0
  end_of_function:
#ifdef __aarch64__
  // A37 canary post-check: if the watched band changed DURING this body,
  // the stomp may be inside (or a concurrent thread — see the A37 report).
  {
    constexpr u32 kCanLo = 0x1900000, kCanLen = 0x18000;
    static bool s_inside_reported = false;
    if (g_a37_csp_canary && !s_inside_reported &&
        memcmp(g_a37_csp_canary, g_ee_main_mem + kCanLo, kCanLen) != 0) {
      s_inside_reported = true;
      fprintf(stderr, "A37-CSP CANARY-STOMP INSIDE-body\n");
    }
  }
  // === Gcine-pose output repair (the fix, always-on, arm64) ===================
  // Catch-all companion to the parent-repair at the top: any bone matrix this
  // body just wrote that is non-finite (e.g. a joint whose transformq quaternion
  // arrived NaN from a procedural / joint-mod path, or any residual the
  // parent-repair didn't cover) is repaired element-wise from a per-bone
  // last-finite cache (or identity). After this, no NaN bone matrix ever reaches
  // the merc renderer -> the pose-blink cannot occur. Engine-thread only.
  {
    static std::unordered_map<u32, std::array<float, 16>> s_out_good;
    const u32 RMX = (u32)(128 * 1024 * 1024 - 64);
    u32 a2v = (u32)c->sgpr64(a2);
    if (a2v >= 0x1000 && a2v < RMX) {
      float* m = reinterpret_cast<float*>(g_ee_main_mem + a2v);
      bool finite = true;
      for (int i = 0; i < 16; i++) {
        if (!std::isfinite(m[i])) {
          finite = false;
          break;
        }
      }
      if (finite) {
        std::array<float, 16> snap;
        memcpy(snap.data(), m, 64);
        s_out_good[a2v] = snap;
      } else {
        gpose::g_repaired.fetch_add(1, std::memory_order_relaxed);
        int rl = gpose::g_repaired_log.fetch_add(1, std::memory_order_relaxed);
        if (rl < 50) {
          fprintf(stderr, "GPOSE-REPAIR #%d bone=0x%x (non-finite child repaired)\n", rl, a2v);
        }
        static const float kIdent[16] = {1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1};
        auto it = s_out_good.find(a2v);
        const float* good = (it != s_out_good.end()) ? it->second.data() : kIdent;
        for (int i = 0; i < 16; i++) {
          if (!std::isfinite(m[i])) {
            m[i] = good[i];
          }
        }
      }
    }
  }
  // Gcine-pose: scan the bone matrix this call just wrote (a2 = cspace.bone,
  // rows at +0/+16/+32/+48) for non-finite / absurd values — a pose-blink
  // that shows up as a garbage written matrix (not a skip) is counted here.
  if (gpose::enabled()) {
    u32 a2v = (u32)c->sgpr64(a2);
    if (a2v >= 0x1000 && a2v < (u32)(128 * 1024 * 1024 - 64)) {
      float m[16];
      memcpy(m, g_ee_main_mem + a2v, 64);
      bool bad = false;
      for (int i = 0; i < 16; i++) {
        if (!std::isfinite(m[i]) || std::fabs(m[i]) > 1.0e12f) {
          bad = true;
          break;
        }
      }
      if (bad) {
        gpose::g_nan.fetch_add(1, std::memory_order_relaxed);
        int nl = gpose::g_nan_log.fetch_add(1, std::memory_order_relaxed);
        if (nl < 1000) {
          // Dump cspace's INPUTS to localize where the NaN is born: the
          // transformq (a1: trans@0, quat@16, scale@32) the anim decompressor
          // produced, and the parent bone's translation row (t0+48). Input
          // quat non-finite/zero -> upstream decompressor/normalize; inputs
          // sane -> this body's own math; parent NaN -> inherited cascade.
          u32 a1v = (u32)c->sgpr64(a1);
          u32 t0v = (u32)c->sgpr64(t0);
          float iq[4] = {0, 0, 0, 0}, it[3] = {0, 0, 0}, is[3] = {0, 0, 0}, pr3[4] = {0, 0, 0, 0};
          if (a1v >= 0x1000 && a1v < (u32)(128 * 1024 * 1024 - 64)) {
            memcpy(it, g_ee_main_mem + a1v + 0, 12);
            memcpy(iq, g_ee_main_mem + a1v + 16, 16);
            memcpy(is, g_ee_main_mem + a1v + 32, 12);
          }
          if (t0v >= 0x1000 && t0v < (u32)(128 * 1024 * 1024 - 64)) {
            memcpy(pr3, g_ee_main_mem + t0v + 48, 16);
          }
          fprintf(stderr,
                  "GPOSE-BADMAT #%d bone=0x%x row3=(%.3g %.3g %.3g %.3g) in_q=(%.4g %.4g %.4g %.4g) "
                  "in_t=(%.3g %.3g %.3g) in_s=(%.3g %.3g %.3g) par=0x%x par_r3=(%.3g %.3g %.3g %.3g)\n",
                  nl, a2v, m[12], m[13], m[14], m[15], iq[0], iq[1], iq[2], iq[3], it[0], it[1],
                  it[2], is[0], is[1], is[2], t0v, pr3[0], pr3[1], pr3[2], pr3[3]);
        }
        // ROOT-FINDER: climb cspace.parent until a parent's bone matrix is
        // finite — the last NaN cspace is the ORIGIN. Dump its builder
        // (param0), added-translation vector (param1) value + the matrix's
        // rotation row0 (NaN there => quaternion->matrix bug; finite there but
        // NaN row3 => the added-translation/param1 vector is the NaN source).
        {
          int rl = gpose::g_root_log.fetch_add(1, std::memory_order_relaxed);
          if (rl < 80) {
            auto nan4 = [](const float* f) {
              return !std::isfinite(f[0]) || !std::isfinite(f[1]) || !std::isfinite(f[2]) ||
                     !std::isfinite(f[3]);
            };
            const u32 MX = (u32)(128 * 1024 * 1024 - 64);
            u32 cs = (u32)c->sgpr64(a0);
            u32 par = 0;
            if (cs >= 0x1000 && cs < MX) {
              memcpy(&par, g_ee_main_mem + cs + 0, 4);
            }
            u32 root = 0;
            for (int g = 0; g < 64 && par >= 0x1000 && par < MX; g++) {
              u32 pbone = 0;
              memcpy(&pbone, g_ee_main_mem + par + 16, 4);
              float pr3b[4] = {0, 0, 0, 0};
              if (pbone >= 0x1000 && pbone < MX) {
                memcpy(pr3b, g_ee_main_mem + pbone + 48, 16);
              }
              if (!nan4(pr3b)) break;
              root = par;
              memcpy(&par, g_ee_main_mem + par + 0, 4);
            }
            if (root >= 0x1000 && root < MX) {
              s16 jnum = 0;
              u32 p0 = 0, p1 = 0, rbone = 0, rjoint = 0;
              memcpy(&jnum, g_ee_main_mem + root + 8, 2);
              memcpy(&p0, g_ee_main_mem + root + 20, 4);
              memcpy(&p1, g_ee_main_mem + root + 24, 4);
              memcpy(&rbone, g_ee_main_mem + root + 16, 4);
              memcpy(&rjoint, g_ee_main_mem + root + 4, 4);
              s32 jointno = -1;
              if (rjoint >= 0x1000 && rjoint < MX) {
                memcpy(&jointno, g_ee_main_mem + rjoint + 4, 4);
              }
              float r0[4] = {0, 0, 0, 0}, r3[4] = {0, 0, 0, 0}, pv[4] = {0, 0, 0, 0};
              if (rbone >= 0x1000 && rbone < MX) {
                memcpy(r0, g_ee_main_mem + rbone + 0, 16);
                memcpy(r3, g_ee_main_mem + rbone + 48, 16);
              }
              if (p1 >= 0x1000 && p1 < MX) {
                memcpy(pv, g_ee_main_mem + p1, 16);
              }
              fprintf(stderr,
                      "GPOSE-ROOT #%d root_csp=0x%x jnum=%d jointno=%d param0=0x%x param1=0x%x "
                      "p1v=(%.4g %.4g %.4g %.4g) bone=0x%x r0=(%.3g %.3g %.3g %.3g) "
                      "r3=(%.3g %.3g %.3g %.3g)\n",
                      rl, root, jnum, jointno, p0, p1, pv[0], pv[1], pv[2], pv[3], rbone, r0[0],
                      r0[1], r0[2], r0[3], r3[0], r3[1], r3[2], r3[3]);
            }
          }
        }
      }
    }
  }
#endif  // __aarch64__
  if (f1b_dump && g_ee_main_mem && f1b_a0 >= 0x1000 && f1b_a1 >= 0x1000 &&
      f1b_a0 < (u32)(128 * 1024 * 1024 - 64) && f1b_a1 < (u32)(128 * 1024 * 1024 - 64)) {
    auto rdf = [&](u32 ga) {
      float v;
      memcpy(&v, g_ee_main_mem + ga, 4);
      return v;
    };
    u32 jw = 0, bone = 0;
    memcpy(&jw, g_ee_main_mem + f1b_a0 + 8, 4);   // cspace.joint-num (int16)
    memcpy(&bone, g_ee_main_mem + f1b_a0 + 16, 4);
    float r3x = 0, r3y = 0, r3z = 0;
    if (bone >= 0x1000 && bone < (u32)(128 * 1024 * 1024 - 64)) {
      r3x = rdf(bone + 48);
      r3y = rdf(bone + 52);
      r3z = rdf(bone + 56);
    }
    fprintf(stderr,
            "F1B-TRS n=%llu csp=0x%x j=%d bone=0x%x t=(%.2f %.2f %.2f) "
            "q=(%.4f %.4f %.4f %.4f) s=(%.3f) r3=(%.2f %.2f %.2f)\n",
            (unsigned long long)s_f1b_n, f1b_a0, (int)(s16)(jw & 0xffff), bone, rdf(f1b_a1),
            rdf(f1b_a1 + 4), rdf(f1b_a1 + 8), rdf(f1b_a1 + 16), rdf(f1b_a1 + 20),
            rdf(f1b_a1 + 24), rdf(f1b_a1 + 28), rdf(f1b_a1 + 32), r3x, r3y, r3z);
  }
  return c->gprs[v0].du64[0];
}

// Gcine-pose: called once per rendered frame from android_gfx.cpp. Buckets the
// per-call joint skips / bad matrices accumulated since the last frame into
// "glitch frames" and logs them with the render frame index, so a bash harness
// can count: frames with >=1 skip/bad-matrix == pose-blink frames.
extern "C" void gpose_joint_frame_tick(unsigned long long fidx) {
#ifdef __aarch64__
  if (!gpose::enabled()) {
    return;
  }
  unsigned sk = gpose::g_skips.exchange(0, std::memory_order_relaxed);
  unsigned na = gpose::g_nan.exchange(0, std::memory_order_relaxed);
  unsigned nn = gpose::g_norm_nan.exchange(0, std::memory_order_relaxed);
  unsigned ca = gpose::g_calls.exchange(0, std::memory_order_relaxed);
  if (sk > 0 || na > 0) {
    unsigned gf = gpose::g_glitch_frames.fetch_add(1, std::memory_order_relaxed) + 1;
    fprintf(stderr,
            "GPOSE-GLITCH frame=%llu skips=%u badmat=%u normnan=%u calls=%u glitch_frames=%u "
            "total_skips=%llu\n",
            fidx, sk, na, nn, ca, gf, (unsigned long long)gpose::g_total_skips.load());
  } else {
    (void)ca;
    (void)nn;
  }
#else
  (void)fidx;
#endif
}

void link() {
  gLinkedFunctionTable.reg("cspace<-parented-transformq-joint!", execute, 128);
}

} // namespace cspace<_parented_transformq_joint
} // namespace Mips2C
// add cspace<_parented_transformq_joint::link to the link callback table for the object file.
// FWD DEC:


namespace normalize_frame_quaternions { extern void link(); }

namespace decompress_fixed_data_to_accumulator { extern void link(); }
namespace decompress_frame_data_to_accumulator { extern void link(); }


namespace decompress_frame_data_pair_to_accumulator { extern void link(); }
