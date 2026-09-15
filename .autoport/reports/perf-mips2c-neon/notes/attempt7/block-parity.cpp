// Generated from exact before/after engine blocks; laboratory only.
#include <algorithm>
#include <array>
#include <cstdio>
#include <cstring>
#include "game/mips2c/mips2c_private.h"
u8* g_ee_main_mem;
using namespace Mips2C;
// before source sha256=93117b90c7b101bb47373369ef8fcb167b3180ccfcaeb816f83a449f1c36761b
__attribute__((noinline)) bool before(ExecutionContext* c) {
 bool bc = false;
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

 return bc;
}
// after source sha256=713810c6a594adaa76272a9480745666ae9e2e074dcc0b43917534f43c1880e1
__attribute__((noinline)) bool after(ExecutionContext* c) {
 bool bc = false;
  {
    // Keep integration intermediates local, then publish every visible VF register.
    Mips2c_vf r8, r9, r10, r11, r12, r13, r14, r15, r17, r18, r19;
    ASSERT(((c->gpr_src(s4).du32[0] + 0) & 0xf) == 0);
    memcpy(&r8, g_ee_main_mem + c->gpr_src(s4).du32[0] + 0, 16);
    ASSERT(((c->gpr_src(s4).du32[0] + 16) & 0xf) == 0);
    memcpy(&r9, g_ee_main_mem + c->gpr_src(s4).du32[0] + 16, 16);
    ASSERT(((c->gpr_src(s4).du32[0] + 32) & 0xf) == 0);
    memcpy(&r10, g_ee_main_mem + c->gpr_src(s4).du32[0] + 32, 16);
    ASSERT(((c->gpr_src(s5).du32[0] + 16) & 0xf) == 0);
    memcpy(&r11, g_ee_main_mem + c->gpr_src(s5).du32[0] + 16, 16);
    ASSERT(((c->gpr_src(s5).du32[0] + 32) & 0xf) == 0);
    memcpy(&r12, g_ee_main_mem + c->gpr_src(s5).du32[0] + 32, 16);
    ASSERT(((c->gpr_src(s5).du32[0] + 48) & 0xf) == 0);
    memcpy(&r13, g_ee_main_mem + c->gpr_src(s5).du32[0] + 48, 16);
    ASSERT(((c->gpr_src(s5).du32[0] + 64) & 0xf) == 0);
    memcpy(&r14, g_ee_main_mem + c->gpr_src(s5).du32[0] + 64, 16);
    c->lwc1(f0, 96, s5);                            // lwc1 f0, 96(s5)
    c->mfc1(v1, f0);                                // mfc1 v1, f0
    const Mips2c_vf r16 = c->vf_src(vf16);
    const Mips2c_vf zero = c->vf_src(vf0);
    for (int lane = 0; lane < 4; ++lane) {
      r14.f[lane] = r14.f[lane] * r16.f[2];          // vmulz.xyzw
    }
    bc = c->sgpr64(v1) == 0;                        // beq v1, r0, L76
    for (int lane = 0; lane < 3; ++lane) {
      r11.f[lane] = r11.f[lane] + r14.f[lane];      // vadd.xyz
    }
    if (!bc) {
      const auto damping = c->gpr_src(v1);
      memcpy(&r15, &damping, 16);                   // qmtc2.i vf15, v1
      r15.f[3] = zero.f[3] - r15.f[0];             // vsubx.w
      for (int lane = 0; lane < 4; ++lane) {
        r15.f[lane] = r15.f[lane] * r16.f[3];      // vmulw.xyzw
      }
      r15.f[3] = zero.f[3] - r15.f[3];             // vsubw.w
      for (int lane = 0; lane < 3; ++lane) {
        r11.f[lane] = r11.f[lane] * r15.f[3];      // vmulw.xyz
      }
    }
    for (int lane = 0; lane < 4; ++lane) {
      r17.f[lane] = r11.f[lane] * r16.f[1];        // vmuly.xyzw vf17
    }
    for (int lane = 0; lane < 4; ++lane) {
      r18.f[lane] = r12.f[lane] * r16.f[1];        // vmuly.xyzw vf18
    }
    for (int lane = 0; lane < 4; ++lane) {
      r19.f[lane] = r13.f[lane] * r16.f[1];        // vmuly.xyzw vf19
    }
    for (int lane = 0; lane < 4; ++lane) {
      r8.f[lane] = r8.f[lane] + r17.f[lane];       // vadd.xyzw vf8
    }
    r9.f[3] = r9.f[3] + r18.f[3];                 // vaddw.w vf9
    for (int lane = 0; lane < 4; ++lane) {
      r10.f[lane] = r10.f[lane] + r19.f[lane];     // vadd.xyzw vf10
    }
    for (int lane = 0; lane < 4; ++lane) {
      r10.f[lane] = std::max(r10.f[lane], 0.f);    // vmaxx.xyzw vf10
    }
    c->vfs[vf8] = r8;
    c->vfs[vf9] = r9;
    c->vfs[vf10] = r10;
    c->vfs[vf11] = r11;
    c->vfs[vf12] = r12;
    c->vfs[vf13] = r13;
    c->vfs[vf14] = r14;
    if (!bc) {
      c->vfs[vf15] = r15;
    }
    c->vfs[vf17] = r17;
    c->vfs[vf18] = r18;
    c->vfs[vf19] = r19;
  }
  c->sqc2(vf11, 16, s5);                            // sqc2 vf11, 16(s5)
  c->sqc2(vf8, 0, s4);                              // sqc2 vf8, 0(s4)
  c->sqc2(vf9, 16, s4);                             // sqc2 vf9, 16(s4)
  c->sqc2(vf10, 32, s4);                            // sqc2 vf10, 32(s4)

 return bc;
}
static void seed(ExecutionContext& c, unsigned sample) {
  // ±zero, min/max subnormal, min normal, finite extrema, infinities,
  // quiet/signaling NaNs with signs and payloads, plus deterministic bit patterns.
  constexpr uint32_t edge[] = {0, 0x80000000u, 1, 0x80000001u,
    0x007fffffu, 0x807fffffu, 0x00800000u, 0x80800000u,
    0x3f800000u, 0xbf800000u, 0x7f7fffffu, 0xff7fffffu,
    0x7f800000u, 0xff800000u, 0x7fc12345u, 0xffc54321u,
    0x7f812345u, 0xff854321u, 0x3f000001u, 0xbf000001u};
  uint32_t state = 0x9e3779b9u ^ sample;
  auto bits = [&](unsigned index) {
    state ^= state << 13; state ^= state >> 17; state ^= state << 5;
    return sample < 40 ? edge[(sample + index * (sample < 20 ? 0 : 7)) % 20] : state;
  };
  for (unsigned r=0; r<32; ++r)
    for (unsigned lane=0; lane<4; ++lane) c.vfs[r].du32[lane]=bits(r*4+lane);
  for (unsigned lane=0; lane<4; ++lane) c.acc.du32[lane]=bits(128+lane);
  auto q=bits(132); std::memcpy(&c.Q,&q,4);
  c.I=1.25f;
}

int main() {
  // Finite particle-like ranges plus existing raw IEEE edges/random bit patterns.
  constexpr u32 fades[] = {0, 0x80000000u, 0x3f000000u, 0x3f800000u,
                           0x7fc12345u, 0xff854321u};
  constexpr u32 positions[][2] = {{64,256}, {64,64}, {64,48},
                                 {64,80}, {128,64}, {64,128}};
  unsigned cases=0, failures=0, damped=0, bypass=0, finite_cases=0;
  for (unsigned sample=0; sample<168; ++sample)
    for (const auto& pos: positions)
      for (u32 fade: fades) {
        ExecutionContext initial{}; seed(initial, sample);
        // Initialize all GPR bytes too, particularly untouched upper v1 lanes.
        for (unsigned r=0; r<32; ++r)
          for (unsigned lane=0; lane<4; ++lane)
            initial.gprs[r].du32[lane]=0x9e3779b9u*(1+r*4+lane+sample);
        initial.gprs[s4].du32[0]=pos[0]; initial.gprs[s5].du32[0]=pos[1];
        std::array<u8,512> memory{};
        for (unsigned offset=0; offset<memory.size(); offset+=4) {
          u32 bits=initial.vfs[(offset/16)%32].du32[(offset/4)%4];
          if (sample>=104) {
            float value=(int((offset*17+sample*31)%2049)-1024)*0.125f;
            std::memcpy(&bits,&value,4);
          }
          std::memcpy(memory.data()+offset,&bits,4);
        }
        if (sample>=104) {
          initial.vfs[16].f[0]=0.f;
          initial.vfs[16].f[1]=(sample%4)*0.25f;
          initial.vfs[16].f[2]=(sample%7)*0.0625f;
          initial.vfs[16].f[3]=(sample%9)*0.125f;
          ++finite_cases;
        }
        std::memcpy(memory.data()+pos[1]+96,&fade,4);
        ExecutionContext expected=initial, actual=initial;
        auto reference_memory=memory, actual_memory=memory;
        g_ee_main_mem=reference_memory.data(); bool ref_bc=before(&expected);
        g_ee_main_mem=actual_memory.data(); bool actual_bc=after(&actual);
        if (ref_bc) ++bypass; else ++damped;
        bool mismatch=ref_bc!=actual_bc ||
          std::memcmp(&expected,&actual,sizeof(actual)) || reference_memory!=actual_memory;
        if (mismatch) {
          if (failures<12) {
            std::printf("FAIL sample=%u s4=%u s5=%u fade=%08x\n",sample,pos[0],pos[1],fade);
            for (unsigned r=0;r<32;++r) for(unsigned l=0;l<4;++l)
              if(expected.vfs[r].du32[l]!=actual.vfs[r].du32[l])
                std::printf("vf%u.%u before=%08x after=%08x\n",r,l,expected.vfs[r].du32[l],actual.vfs[r].du32[l]);
          }
          ++failures;
        }
        ++cases;
      }
  std::printf("LAB cases=%u finite_memory_cases=%u damped=%u bypass=%u context_and_memory_defects=%u\n",
              cases,finite_cases,damped,bypass,failures);
  std::printf("RESULT %s\n",failures ? "FAIL" : "PASS");
  return failures ? 1 : 0;
}
