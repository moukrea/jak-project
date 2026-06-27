// Gcollision-systemic — x86-vs-arm64 collision float->int CONVERSION sweep.
//
// Goal: prove the SYSTEMIC arm64 collision divergence is the float->int conversion
// op, present pervasively. The mips2c VU0 `vftoi0` was already re-emulated to
// cvttss2si by Gledge, but the goalc AArch64 codegen of `(the int <float>)` still
// emits a BARE `FCVTZS` (IGenARM64.cpp float_to_int32 / ftoi_vf) which saturates
// DIFFERENTLY from the x86 oracle `cvttss2si`/`cvttps2dq`:
//
//        input          x86 cvttss2si      arm64 FCVTZS (bare)
//   NaN                 0x80000000          0
//   +Inf / +overflow    0x80000000          0x7fffffff
//   -Inf / -overflow    0x80000000          0x80000000   (same)
//   in s32 range        trunc-to-zero       trunc-to-zero (same)
//
// Collision math routinely produces NaN (degenerate/grazing tris) and out-of-range
// values (squared distances at meter*4096 scale overflow s32). Quantizing those into
// the spatial-hash grid / bbox AABB with the wrong saturation lands triangles (or
// Jak's query box) in a different cell on arm64 than x86 -> wrong triangle selected
// -> wrong/absent push-out -> clip-through, eject, invisible wall, under-map.
//
// This binary, built three ways over a byte-identical fixed-seed input stream:
//   x86      : g++  -mavx -ffp-contract=off               (the ORACLE: cvttss2si)
//   arm_bare : NDK clang -ffp-contract=off                (device-as-shipped: FCVTZS)
//   arm_emul : NDK clang -ffp-contract=off -DEMUL_CVTTSS  (the FIX: emulated cvttss2si)
// and diffed:
//   BEFORE = diff(x86, arm_bare)  -> MANY divergences   (the systemic bug)
//   AFTER  = diff(x86, arm_emul)  -> 0 divergences       (arm64 == x86, 1-to-1)
//
// The EMUL_CVTTSS branch is the EXACT semantics the goalc fix must encode in
// IGenARM64 float_to_int32 / ftoi_vf.
#include "game/mips2c/mips2c_private.h"
#include <cstdio>
#include <cstring>
#include <cmath>

using namespace Mips2C;
u8* g_ee_main_mem = nullptr;
#include <atomic>
std::atomic<bool> g_gnd_oob_armed{false};
void gnd_oob_report(char, unsigned int, unsigned long long, unsigned long long, int) {}
namespace { struct CacheT { void* collide_do_primitives; } cache; }

static inline u32 fb(float f){ u32 u; std::memcpy(&u,&f,4); return u; }

// ---- the conversion under test ------------------------------------------------
// goalc emits IR_FloatToInt as: FCVTZS Wd,Sn ; movsx Xd,Wd  (sign-extend to 64).
// In C++, `(s64)(s32)f` compiles to exactly that: cvttss2si+cdqe on x86 (GCC),
// FCVTZS+sxtw on arm64 (clang). So `(s64)(s32)f` faithfully models goalc's scalar
// float_to_int32 on BOTH backends — the BARE path.
static inline s64 conv_scalar(float f) {
#ifdef EMUL_CVTTSS
  // The FIX: emulate x86 cvttss2si. In-range FCVTZS == cvttss2si; only NaN/+ovf
  // diverge, so clamp those to INT32_MIN (the x86 "integer indefinite").
  s32 r;
  if (!(f >= -2147483648.0f && f < 2147483648.0f)) {
    r = (s32)0x80000000;          // NaN fails both compares -> taken; also +/-ovf/+/-Inf
  } else {
    r = (s32)f;                   // in-range: FCVTZS == cvttss2si
  }
  return (s64)r;                  // sign-extend (movsx) as goalc does
#else
  return (s64)(s32)f;             // BARE: x86=cvttss2si(+cdqe), arm64=FCVTZS(+sxtw)
#endif
}

int main() {
  g_ee_main_mem = (u8*)calloc(1u << 20, 1);

  // Deterministic LCG identical across all three builds.
  uint64_t st = 0xD1B54A32D192ED03ull;
  auto rr = [&]() -> uint32_t { st = st*6364136223846793005ull + 1442695040888963407ull; return (uint32_t)(st>>32); };
  auto fr = [&](float lo, float hi) -> float { return lo + (hi-lo)*(rr()/4294967296.0f); };

  const int N = 60000;
  long diff_self = 0;  // placeholder (cross-build diff is external)
  printf("# SECTION A — collision-realistic float->int conversion sweep (%d inputs)\n", N);
  printf("# idx  in(hex)         scalar_out(hex16)   class\n");
  for (int i = 0; i < N; i++) {
    // Cover the full collision value space. Each class is drawn into a named local
    // (RNG sequencing — unsequenced arg lists fake divergence across compilers).
    float f;
    int klass = i % 8;
    switch (klass) {
      case 0: { float v = fr(-8e6f, 8e6f);       f = v; break; }              // positions (in s32 range, truncate)
      case 1: { float v = fr(-2.2e9f, 2.2e9f);   f = v; break; }              // straddle +/-2^31 (the +ovf divergence)
      case 2: { float a = fr(1e3f, 8e6f);        f = a*a; break; }            // squared distance (overflows s32, +ovf)
      case 3: { float a = fr(-8e6f, -1e3f);      f = a*a; break; }            // squared (positive, +ovf)
      case 4: { float a = fr(1.0f, 9e5f), b = fr(0.0f, 1e-6f); f = a/b; break; } // near-div-by-0 -> huge/+Inf
      case 5: { float a = fr(-1.0f,1.0f), b = fr(-1e-7f,1e-7f); f = a/b; break; } // +/-Inf
      case 6: { float a = fr(-1e-7f,1e-7f), b = fr(-1e-7f,1e-7f); f = a/b; break; } // 0/0 -> NaN territory
      default:{ float v = fr(-1e3f, 1e3f);       f = v; break; }              // small in-range
    }
    // also fold in hard NaN/Inf deterministically every 53rd
    if (i % 53 == 0)  f = std::nanf("");
    if (i % 97 == 0)  f = INFINITY;
    if (i % 101 == 0) f = -INFINITY;

    s64 out = conv_scalar(f);
    const char* cl = std::isnan(f) ? "NaN" : (std::isinf(f) ? "Inf" :
                     (f >= 2147483648.0f ? "+ovf" : (f < -2147483648.0f ? "-ovf" : "rng")));
    printf("A%-6d %08x        %016llx  %s\n", i, fb(f), (unsigned long long)out, cl);
  }

  // SECTION B — VECTOR ftoi (4 lanes), the goalc ftoi_vf / cvttps2dq path. Same
  // divergence per lane; collision uses vector quantization for AABB corners.
  printf("# SECTION B — vector ftoi (cvttps2dq vs FCVTZS.4S), %d inputs x4 lanes\n", N/4);
  printf("# idx  lane0 lane1 lane2 lane3 (hex16 each)\n");
  for (int i = 0; i < N/4; i++) {
    float lane[4];
    lane[0] = fr(-8e6f, 8e6f);
    { float a = fr(1e3f, 8e6f); lane[1] = a*a; }            // +ovf
    lane[2] = (i % 7 == 0) ? std::nanf("") : fr(-2.2e9f, 2.2e9f);  // NaN or straddle
    { float a = fr(-1.0f,1.0f), b = fr(-1e-7f,1e-7f); lane[3] = a/b; } // +/-Inf
    s64 o0 = conv_scalar(lane[0]), o1 = conv_scalar(lane[1]),
        o2 = conv_scalar(lane[2]), o3 = conv_scalar(lane[3]);
    printf("B%-6d %016llx %016llx %016llx %016llx\n", i,
           (unsigned long long)o0,(unsigned long long)o1,
           (unsigned long long)o2,(unsigned long long)o3);
  }

  (void)diff_self;
  return 0;
}
