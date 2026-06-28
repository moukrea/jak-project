// nanroot_optest.cpp — Gcollision-nanroot op-level differential.
//
// Proves the arm64 min/max NaN divergence vs the x86 oracle, and that the
// proposed FIXED arm64 sequence matches x86 bit-for-bit.
//
// GOAL `fmin`/`fmax` (FloatMath MIN_SS/MAX_SS) and `.min.vf`/`.max.vf`
// (VFMath3 min_vf/max_vf) compile to:
//   x86  : MINSS/MAXSS (scalar), MINPS/MAXPS (vector)
//   arm64: FMIN/FMAX  (scalar), FMIN.4S/FMAX.4S (vector)   <-- BEFORE
//
// x86 MINSS dst,src semantics: dst = (dst < src) ? dst : src.  The compare is
// FALSE when unordered (a NaN is involved), so the result is SRC (operand 2).
// i.e. min(NaN, x) = x, min(x, NaN) = NaN-comes-from-src... actually: result is
// always the SECOND operand on any NaN. So a clamp like (fmax v 0.0) SANITIZES
// a NaN v to 0.0 on x86.
// ARM FMIN/FMAX PROPAGATE NaN: fmin(NaN,x)=NaN, fmin(x,NaN)=NaN. So the same
// clamp PROPAGATES the NaN on arm64. -> "x86 finite, arm64 NaN".
//
// FIXED arm64 sequence (the translation-layer fix):
//   scalar min: FCMP a,b ; FCSEL d,a,b,MI         (MI = a<b ordered; NaN->b)
//   scalar max: FCMP b,a ; FCSEL d,a,b,MI         (MI = b<a ordered => a>b; NaN->b)
//   vector min: FCMGT mask, b, a ; BIF a, b, mask (mask=a<b lanes; res=mask?a:b)
//   vector max: FCMGT mask, a, b ; BIF a, b, mask (mask=a>b lanes; res=mask?a:b)
// (a=dst/operand1, b=src/operand2; BIF Vd,Vn,Vm => Vd = Vm?Vd:Vn)
//
// Build x86 :  g++   -O2 -o optest_x86 nanroot_optest.cpp
// Build arm :  $CXX  -O2 -o optest_arm nanroot_optest.cpp   (NDK aarch64 clang++)
// Output    :  "<variant> <op> a=<hex8> b=<hex8> r=<hex8>"  (one per pair)
//   compare arm-before vs x86 (MUST DIFFER on NaN rows) and arm-fixed vs x86
//   (MUST be byte-identical on every row).

#include <cstdint>
#include <cstdio>
#include <cstring>

static uint32_t fb(float f) { uint32_t u; std::memcpy(&u, &f, 4); return u; }
static float bf(uint32_t u) { float f; std::memcpy(&f, &u, 4); return f; }

// Representative inputs: NaNs (qNaN/sNaN, both operand positions), +/-Inf, +/-0,
// ordered pairs both directions, equal, and ordinary collision-ish magnitudes.
static const uint32_t kVals[] = {
    0x7fc00000u,  // +qNaN
    0xffc00000u,  // -qNaN
    0x7fa00000u,  // sNaN
    0x7f800000u,  // +Inf
    0xff800000u,  // -Inf
    0x00000000u,  // +0
    0x80000000u,  // -0
    0x3f800000u,  // 1.0
    0x40000000u,  // 2.0
    0xbf800000u,  // -1.0
    0x4b000000u,  // 8388608.0 (collision-ish)
    0xcb000000u,  // -8388608.0
};
static const int kN = sizeof(kVals) / sizeof(kVals[0]);

#if defined(__x86_64__)
#include <xmmintrin.h>
static float s_min(float a, float b) { asm("minss %1, %0" : "+x"(a) : "x"(b)); return a; }
static float s_max(float a, float b) { asm("maxss %1, %0" : "+x"(a) : "x"(b)); return a; }
static float v_min(float a, float b) {
  __m128 va = _mm_set_ss(a), vb = _mm_set_ss(b); float o;
  asm("minps %1, %0" : "+x"(va) : "x"(vb)); _mm_store_ss(&o, va); return o;
}
static float v_max(float a, float b) {
  __m128 va = _mm_set_ss(a), vb = _mm_set_ss(b); float o;
  asm("maxps %1, %0" : "+x"(va) : "x"(vb)); _mm_store_ss(&o, va); return o;
}
static void run() {
  for (int i = 0; i < kN; i++)
    for (int j = 0; j < kN; j++) {
      float a = bf(kVals[i]), b = bf(kVals[j]);
      printf("x86 minss a=%08x b=%08x r=%08x\n", kVals[i], kVals[j], fb(s_min(a, b)));
      printf("x86 maxss a=%08x b=%08x r=%08x\n", kVals[i], kVals[j], fb(s_max(a, b)));
      printf("x86 minps a=%08x b=%08x r=%08x\n", kVals[i], kVals[j], fb(v_min(a, b)));
      printf("x86 maxps a=%08x b=%08x r=%08x\n", kVals[i], kVals[j], fb(v_max(a, b)));
    }
}

#elif defined(__aarch64__)
#include <arm_neon.h>
// BEFORE: bare FMIN/FMAX (current goalc arm64 backend)
static float sb_min(float a, float b) { asm("fmin %s0, %s0, %s1" : "+w"(a) : "w"(b)); return a; }
static float sb_max(float a, float b) { asm("fmax %s0, %s0, %s1" : "+w"(a) : "w"(b)); return a; }
static float vb_min(float a, float b) {
  float32x4_t va = vdupq_n_f32(a), vb = vdupq_n_f32(b), r;
  asm("fmin %0.4s, %1.4s, %2.4s" : "=w"(r) : "w"(va), "w"(vb)); return vgetq_lane_f32(r, 0);
}
static float vb_max(float a, float b) {
  float32x4_t va = vdupq_n_f32(a), vb = vdupq_n_f32(b), r;
  asm("fmax %0.4s, %1.4s, %2.4s" : "=w"(r) : "w"(va), "w"(vb)); return vgetq_lane_f32(r, 0);
}
// FIXED: replicate x86 minss/maxss/minps/maxps "return operand-2 on unordered"
static float sf_min(float a, float b) {
  float d; asm("fcmp %s1, %s2\n\tfcsel %s0, %s1, %s2, mi" : "=w"(d) : "w"(a), "w"(b) : "cc"); return d;
}
static float sf_max(float a, float b) {
  float d; asm("fcmp %s2, %s1\n\tfcsel %s0, %s1, %s2, mi" : "=w"(d) : "w"(a), "w"(b) : "cc"); return d;
}
static float vf_min(float a, float b) {
  float32x4_t va = vdupq_n_f32(a), vb = vdupq_n_f32(b), mask, res = va;
  asm("fcmgt %0.4s, %3.4s, %2.4s\n\t"   // mask = (b > a) = (a < b)
      "bif %1.16b, %3.16b, %0.16b"       // res(a) = mask ? res(a) : b
      : "=&w"(mask), "+w"(res) : "w"(va), "w"(vb));
  return vgetq_lane_f32(res, 0);
}
static float vf_max(float a, float b) {
  float32x4_t va = vdupq_n_f32(a), vb = vdupq_n_f32(b), mask, res = va;
  asm("fcmgt %0.4s, %2.4s, %3.4s\n\t"   // mask = (a > b)
      "bif %1.16b, %3.16b, %0.16b"       // res(a) = mask ? res(a) : b
      : "=&w"(mask), "+w"(res) : "w"(va), "w"(vb));
  return vgetq_lane_f32(res, 0);
}
static void run() {
  for (int i = 0; i < kN; i++)
    for (int j = 0; j < kN; j++) {
      float a = bf(kVals[i]), b = bf(kVals[j]);
      printf("arm-before minss a=%08x b=%08x r=%08x\n", kVals[i], kVals[j], fb(sb_min(a, b)));
      printf("arm-before maxss a=%08x b=%08x r=%08x\n", kVals[i], kVals[j], fb(sb_max(a, b)));
      printf("arm-before minps a=%08x b=%08x r=%08x\n", kVals[i], kVals[j], fb(vb_min(a, b)));
      printf("arm-before maxps a=%08x b=%08x r=%08x\n", kVals[i], kVals[j], fb(vb_max(a, b)));
      printf("arm-fixed minss a=%08x b=%08x r=%08x\n", kVals[i], kVals[j], fb(sf_min(a, b)));
      printf("arm-fixed maxss a=%08x b=%08x r=%08x\n", kVals[i], kVals[j], fb(sf_max(a, b)));
      printf("arm-fixed minps a=%08x b=%08x r=%08x\n", kVals[i], kVals[j], fb(vf_min(a, b)));
      printf("arm-fixed maxps a=%08x b=%08x r=%08x\n", kVals[i], kVals[j], fb(vf_max(a, b)));
    }
}
#else
static void run() { printf("unsupported arch\n"); }
#endif

int main() { run(); return 0; }
