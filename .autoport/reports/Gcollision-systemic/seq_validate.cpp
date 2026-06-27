// Gcollision-systemic — on-device validation of the EXACT instruction sequences
// the goalc arm64 fix emits for scalar float_to_int32 and vector ftoi_vf.
//
// The assembler-reference run already proved each instruction word my IGenARM64
// encoders produce matches llvm/clang's encoding bit-for-bit. This harness proves
// the SEQUENCE LOGIC is correct on real arm64 hardware: it runs the verbatim
// 9-instruction scalar sequence and 5-instruction vector sequence (as inline asm,
// same mnemonics/registers the emitter emits) over the collision input space and
// compares to (a) the bare FCVTZS (the bug) and (b) the x86 cvttss2si/cvttps2dq
// semantics (the C reference, proven == x86 by conv_sweep). Expect: asm == cvttss2si
// for ALL inputs, asm != bare on NaN/+ovf/+Inf.
#include <cstdio>
#include <cstdint>
#include <cstring>
#include <cmath>

// ---- the emitted SCALAR sequence (IR_FloatToInt::do_codegen_arm64) ----
// fcvtzs w0,s; movz x16,#0x8000,lsl16; movz x17,#0xffff; movk x17,#0x7fff,lsl16;
// cmp x0,x17; csel x0,x16,x0,eq; fcmp s,s; csel x0,x16,x0,vs; sxtw x0,w0
// NOTE: the 4 NEW encoders (csel, movi.4s, fcmgt.4s, bif.16b) are emitted via
// `.inst <word>` using the EXACT u32 my IGenARM64 formulas produce, so this tests
// the encoder words themselves (not the assembler's mnemonics). The pre-existing
// encoders (fcvtzs, movz/movk, cmp, fcmp, sxtw, ldr/str q) stay as mnemonics.
static int64_t asm_scalar(float x) {
  int64_t r;
  asm volatile(
      "fmov s0, %s1\n"
      "fcvtzs w0, s0\n"
      "movz x16, #0x8000, lsl #16\n"
      "movz x17, #0xffff\n"
      "movk x17, #0x7fff, lsl #16\n"
      "cmp x0, x17\n"
      ".inst 0x9a800200\n"  // csel x0, x16, x0, eq   (my encoder word)
      "fcmp s0, s0\n"
      ".inst 0x9a806200\n"  // csel x0, x16, x0, vs   (my encoder word)
      "sxtw x0, w0\n"
      "mov %0, x0\n"
      : "=r"(r)
      : "w"(x)
      : "s0", "x0", "x16", "x17", "cc");
  return r;
}

// ---- the emitted VECTOR sequence (IR_VFMath2Asm FTOI do_codegen_arm64) ----
// movi v0.4s,#0x4f,lsl24; fcmgt v1.4s,v0.4s,Vn; fcvtzs Vd.4s,Vn;
// movi v2.4s,#0x80,lsl24; bif Vd.16b,v2.16b,v1.16b   (here Vn=v5, Vd=v6)
static void asm_vec(int32_t* out, const float* in) {
  asm volatile(
      "ldr q5, [%1]\n"
      ".inst 0x4f0265e0\n"  // movi v0.4s, #0x4f, lsl #24   (goalc encoder word)
      ".inst 0x6ea5e401\n"  // fcmgt v1.4s, v0.4s, v5.4s    (goalc encoder word)
      "fcvtzs v6.4s, v5.4s\n"
      ".inst 0x4f046402\n"  // movi v2.4s, #0x80, lsl #24   (goalc encoder word)
      ".inst 0x6ee11c46\n"  // bif v6.16b, v2.16b, v1.16b   (goalc encoder word, base 0x6EE01C00)
      "str q6, [%0]\n"
      :
      : "r"(out), "r"(in)
      : "v0", "v1", "v2", "v5", "v6", "memory");
}

// bare FCVTZS (current device behavior = the bug)
static int64_t bare_scalar(float f) { return (int64_t)(int32_t)f; }
// x86 cvttss2si semantics (the fix target; proven == x86 by conv_sweep)
static int64_t x86_scalar(float f) {
  int32_t r;
  if (!(f >= -2147483648.0f && f < 2147483648.0f))
    r = (int32_t)0x80000000;
  else
    r = (int32_t)f;
  return (int64_t)r;
}

int main() {
  uint64_t st = 0xD1B54A32D192ED03ull;
  auto rr = [&]() { st = st * 6364136223846793005ull + 1442695040888963407ull; return (uint32_t)(st >> 32); };
  auto fr = [&](float lo, float hi) { return lo + (hi - lo) * (rr() / 4294967296.0f); };

  const int N = 200000;
  long sc_vs_x86 = 0, sc_vs_bare = 0, vec_vs_x86 = 0;
  long nan_n = 0, ovf_n = 0;
  for (int i = 0; i < N; i++) {
    float f;
    switch (i % 8) {
      case 0: f = fr(-8e6f, 8e6f); break;
      case 1: f = fr(-2.2e9f, 2.2e9f); break;
      case 2: { float a = fr(1e3f, 8e6f); f = a * a; } break;
      case 3: { float a = fr(-8e6f, -1e3f); f = a * a; } break;
      case 4: { float a = fr(1.0f, 9e5f), b = fr(0.0f, 1e-6f); f = a / b; } break;
      case 5: { float a = fr(-1.0f, 1.0f), b = fr(-1e-7f, 1e-7f); f = a / b; } break;
      case 6: { float a = fr(-1e-7f, 1e-7f), b = fr(-1e-7f, 1e-7f); f = a / b; } break;
      default: f = fr(-1e3f, 1e3f); break;
    }
    if (i % 53 == 0) f = std::nanf("");
    if (i % 97 == 0) f = INFINITY;
    if (i % 101 == 0) f = -INFINITY;

    int64_t s_asm = asm_scalar(f), s_x86 = x86_scalar(f), s_bare = bare_scalar(f);
    if (s_asm != s_x86) sc_vs_x86++;
    if (s_asm != s_bare) sc_vs_bare++;
    if (std::isnan(f)) nan_n++;
    if (f >= 2147483648.0f || f <= -2147483648.0f || std::isinf(f)) ovf_n++;

    // vector: pack 4 varied lanes
    float lanes[4] = {f, fr(-8e6f, 8e6f), (i % 7 == 0) ? std::nanf("") : fr(-2.2e9f, 2.2e9f),
                      [&] { float a = fr(-1.0f, 1.0f), b = fr(-1e-7f, 1e-7f); return a / b; }()};
    int32_t vout[4];
    asm_vec(vout, lanes);
    for (int l = 0; l < 4; l++)
      if ((int64_t)vout[l] != (int64_t)(int32_t)x86_scalar(lanes[l])) vec_vs_x86++;
  }
  printf("N=%d\n", N);
  printf("SCALAR seq vs x86 cvttss2si: %ld mismatches (expect 0)\n", sc_vs_x86);
  printf("SCALAR seq vs bare FCVTZS  : %ld differ (the bug it fixes; >0 expected)\n", sc_vs_bare);
  printf("VECTOR seq vs x86 cvttps2dq: %ld lane-mismatches over %d lanes (expect 0)\n", vec_vs_x86, N * 4);
  printf("inputs: NaN=%ld out-of-range=%ld\n", nan_n, ovf_n);
  printf("%s\n", (sc_vs_x86 == 0 && vec_vs_x86 == 0 && sc_vs_bare > 0)
                     ? "RESULT: SEQUENCES == x86, DIFFER FROM BARE (CORRECT)"
                     : "RESULT: FAILURE");
  return 0;
}
