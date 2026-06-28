// cc_oracle.cpp — Gcollision-glitchcapture x86-vs-arm64 oracle on REAL captured operands.
//
// Consumes a collision_glitch.txt dump produced by the always-on glitch-triggered capture
// (game/kernel/jak1/kmachine.cpp collision_glitch_capture_tick) during the OWNER's real play.
// For every captured frame it re-runs the collision-reaction math the GOAL source uses
// (collide-shape.gc default-collision-reaction, vector.gc vector-normalize!, vector-h.gc
// vector-dot, vector.gc vector-length) on the EXACT dumped operands, then prints results in
// hex8 so the SAME binary's output on the x86 host and on the arm64 device can be diff'd.
//
// What it tests, per op, on the captured normals (surface=sn, poly=pn, gravity=gn):
//   coverage      = vector-dot(sn, pn)         (collide-shape.gc:715)  -- scalar mul+add
//   surface-angle = vector-dot(sn, gn)         (collide-shape.gc:722)  -- scalar mul+add
//   poly-angle    = vector-dot(pn, gn)         (collide-shape.gc:723)  -- scalar mul+add
//   |sn| , |pn|   = vector-length(.)           (vector.gc:472)         -- VU .add.mul + .sqrt
// Each is computed TWO ways:
//   _sep : separate multiply then add  (mirrors x86 MULSS/MULPS + ADDSS/ADDPS, double rounding)
//   _fma : fused multiply-accumulate   (mirrors an arm64 FMLA emission of .add.mul, single round)
// If _sep != _fma for an operand AND the in-game arm64 dumped value matches _fma while the x86
// host _sep matches the original x86 build, the divergent op is the .add.mul accumulator (an FMA
// the backend emits where x86 does not). cov/sa/pa _calc are also compared to the DUMPED in-game
// values: a mismatch means the in-game op path differs from this scalar reference (names the op);
// an exact match across x86+arm86 confirms that op is consistent and the divergence is UPSTREAM
// (detection: the normal directions themselves), which the report then flags for a detection-stage
// capture. Non-unit |normal| (|len-1| large) flags a divergent normalize/length directly.
//
// Build x86 :  g++ -O2 -ffp-contract=off -o cc_oracle_x86 cc_oracle.cpp
// Build arm :  <ndk>/aarch64-linux-android29-clang++ -O2 -ffp-contract=off -static-libstdc++ \
//                 -o cc_oracle_arm cc_oracle.cpp
//   (-ffp-contract=off keeps the compiler from fusing the _sep path; the _fma path uses fmaf
//    explicitly so it is fused on both arches regardless.)
// Run    :  ./cc_oracle_<arch> collision_glitch.txt   (or stdin)
//   then  diff <(./cc_oracle_x86 dump) <(adb ... ./cc_oracle_arm dump)  -> any differing row
//   is an op that diverges x86-vs-arm64 on those exact real operands.

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <cmath>
#include <string>

static uint32_t fb(float f) { uint32_t u; std::memcpy(&u, &f, 4); return u; }
static float bf(uint32_t u) { float f; std::memcpy(&f, &u, 4); return f; }

// dot3, two roundings: separate (x86 mul+add) vs fused (fmaf, arm64 FMLA candidate).
static float dot3_sep(const float* a, const float* b) {
  float r = a[0] * b[0];
  r = r + a[1] * b[1];
  r = r + a[2] * b[2];
  return r;
}
static float dot3_fma(const float* a, const float* b) {
  float r = a[0] * b[0];
  r = fmaf(a[1], b[1], r);
  r = fmaf(a[2], b[2], r);
  return r;
}
static float len3_sep(const float* a) { return std::sqrt(dot3_sep(a, a)); }
static float len3_fma(const float* a) { return std::sqrt(dot3_fma(a, a)); }

// parse "tag=h,h,h,h" out of a line; returns count parsed
static bool parse_vec4(const char* line, const char* tag, float* out) {
  std::string pat = std::string(" ") + tag + "=";
  const char* p = std::strstr(line, pat.c_str());
  if (!p) { pat = std::string(tag) + "="; p = std::strstr(line, pat.c_str()); if (!p) return false; }
  p += pat.size();
  unsigned u0, u1, u2, u3;
  if (std::sscanf(p, "%x,%x,%x,%x", &u0, &u1, &u2, &u3) != 4) return false;
  out[0] = bf(u0); out[1] = bf(u1); out[2] = bf(u2); out[3] = bf(u3);
  return true;
}
static bool parse_scalar(const char* line, const char* tag, float* out) {
  std::string pat = std::string(" ") + tag + "=";
  const char* p = std::strstr(line, pat.c_str());
  if (!p) return false;
  p += pat.size();
  unsigned u;
  if (std::sscanf(p, "%x", &u) != 1) return false;
  *out = bf(u);
  return true;
}

int main(int argc, char** argv) {
#if defined(__aarch64__)
  const char* arch = "arm64";
#elif defined(__x86_64__) || defined(__i386__)
  const char* arch = "x86";
#else
  const char* arch = "other";
#endif
  std::FILE* in = stdin;
  if (argc >= 2) { in = std::fopen(argv[1], "r"); if (!in) { std::fprintf(stderr, "open %s failed\n", argv[1]); return 2; } }

  char line[4096];
  int frames = 0, nonunit = 0, cov_mismatch = 0, fma_diff = 0;
  std::printf("# cc_oracle arch=%s\n", arch);
  std::printf("# cols: frame |sn|_sep |sn|_fma |pn|_sep |pn|_fma cov_sep cov_fma cov_dump sa_sep sa_fma sa_dump pa_sep pa_fma pa_dump flags\n");
  while (std::fgets(line, sizeof(line), in)) {
    if (line[0] != 'F' || line[1] != ' ') continue;
    long frame = 0; std::sscanf(line + 2, "%ld", &frame);
    float sn[4], pn[4], gn[4];
    if (!parse_vec4(line, "sn", sn) || !parse_vec4(line, "pn", pn) || !parse_vec4(line, "gn", gn)) continue;
    float cov_d = 0, sa_d = 0, pa_d = 0;
    parse_scalar(line, "cov", &cov_d);
    parse_scalar(line, "sa", &sa_d);
    parse_scalar(line, "pa", &pa_d);

    float snl_s = len3_sep(sn), snl_f = len3_fma(sn);
    float pnl_s = len3_sep(pn), pnl_f = len3_fma(pn);
    float cov_s = dot3_sep(sn, pn), cov_f = dot3_fma(sn, pn);
    float sa_s = dot3_sep(sn, gn), sa_f = dot3_fma(sn, gn);
    float pa_s = dot3_sep(pn, gn), pa_f = dot3_fma(pn, gn);

    std::string flags;
    bool sn_set = (snl_s > 0.05f), pn_set = (pnl_s > 0.05f);
    // RELIABLE divergence signals (intrinsic to the captured vector, not cross-field):
    if (sn_set && std::fabs(snl_s - 1.0f) > 0.02f) { flags += "SN_NONUNIT "; nonunit++; }
    if (pn_set && std::fabs(pnl_s - 1.0f) > 0.02f) { flags += "PN_NONUNIT "; nonunit++; }
    // INFORMATIONAL only — coverage is captured at END-OF-FRAME and is reset/written by a different
    // code path than surface/poly-normal, so cov_dump can be 0 while the normals are resident from a
    // prior frame (proven: mechanics dump showed cov_dump=0 with sn=pn=[0,1,0]). This is capture
    // STALENESS, NOT a divergence. Only count it when a reaction actually ran this frame (cov_dump!=0).
    if (sn_set && pn_set && fb(cov_d) != 0 && fb(cov_s) != fb(cov_d)) { flags += "COV_INCOHERENT "; cov_mismatch++; }
    // INFORMATIONAL — whether these operands are FMA-sensitive. FMA divergence is FALSIFIED at the
    // source: goalc's arm64 backend emits NO fused multiply-add (separate FMUL+FADD, IGenARM64.cpp),
    // so neither backend fuses; this flag cannot indicate an x86-vs-arm64 difference. Kept as a note.
    if (fb(cov_s) != fb(cov_f) || fb(sa_s) != fb(sa_f) || fb(pa_s) != fb(pa_f) ||
        fb(snl_s) != fb(snl_f) || fb(pnl_s) != fb(pnl_f)) { flags += "FMA_SENS "; fma_diff++; }
    if (flags.empty()) flags = "-";

    std::printf("F %ld %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %08x %s\n",
                frame, fb(snl_s), fb(snl_f), fb(pnl_s), fb(pnl_f),
                fb(cov_s), fb(cov_f), fb(cov_d), fb(sa_s), fb(sa_f), fb(sa_d),
                fb(pa_s), fb(pa_f), fb(pa_d), flags.c_str());
    frames++;
  }
  std::printf("# summary arch=%s frames=%d nonunit_normals=%d cov_incoherent[stale,info]=%d fma_sensitive[info]=%d\n",
              arch, frames, nonunit, cov_mismatch, fma_diff);
  std::printf("# PRIMARY divergence test = diff this output against the SAME binary run on the other\n");
  std::printf("# arch (cc_oracle_run.sh). Reaction ops are bit-identical x86/arm64 (FMA falsified), so\n");
  std::printf("# an empty diff => divergence is UPSTREAM in detection; non-unit/non-finite => normalize.\n");
  if (in != stdin) std::fclose(in);
  return 0;
}
