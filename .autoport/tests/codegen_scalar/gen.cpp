// perf-codegen-arm64-scalar test generator (runs on the HOST, x86-64).
//
// 1. Checks the shared float->int model (model.h) against the real x86
//    CVTTSS2SI instruction over all 2^32 float bit patterns.
// 2. Checks the ScalarStats detector (game/system/codegen_arm64_scalar.h)
//    against the NEW sequences goalc emits today (IGenARM64.cpp) and the
//    LEGACY sequences goalc used to emit (legacy.h, reproduced from
//    commit ff7b7ba1e0).
// 3. Emits build/cases.bin: standalone arm64 machine code for every kernel
//    the arm64 runner (runner.c) will execute, new AND legacy, for every
//    family (float->int, integer divide, swizzle, pshuf).
//
// Nothing here touches goalc/ or IGenARM64.*: it only calls into the real,
// unmodified translation unit compiled alongside it (see CMakeLists.txt).
#include <xmmintrin.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#include "goalc/emitter/IGenARM64.h"
#include "goalc/emitter/Register.h"
#include "game/system/codegen_arm64_scalar.h"

#include "legacy.h"
#include "model.h"

using emitter::InstructionARM64;
using emitter::Register;
namespace A = emitter::IGen::ARM64;

// Forward declarations for the NEW arm64 emitter helpers, NOT declared in the
// locked IGenARM64.h header — mirrored exactly like goalc/compiler/IR.cpp:39-50.
namespace emitter {
namespace IGen {
namespace ARM64 {
InstructionARM64 float_to_int32_x86(Register dst, Register src);
InstructionARM64 int_div_w(Register dst, Register arg, bool is_signed, bool is_mod);
}  // namespace ARM64
}  // namespace IGen
}  // namespace emitter

namespace {

std::vector<uint32_t> words_of(const InstructionARM64& i) {
  std::vector<uint32_t> w;
  w.push_back(i.encoding);
  for (auto e : i.extra_words) w.push_back(e);
  return w;
}

// ---------------------------------------------------------------------------
// Step 1: float->int model vs the real x86 CVTTSS2SI.
// ---------------------------------------------------------------------------
uint64_t check_f2i_model_vs_x86() {
  uint64_t mismatches = 0;
  uint32_t bits = 0;
  do {
    float f;
    std::memcpy(&f, &bits, sizeof(f));
    int64_t model = model_f2i_bits(bits);
    int64_t hw = (int64_t)_mm_cvtt_ss2si(_mm_set_ss(f));
    if (model != hw) {
      if (mismatches < 8) {
        std::fprintf(stderr, "f2i model mismatch: bits=0x%08x f=%g model=%lld x86=%lld\n", bits,
                     (double)f, (long long)model, (long long)hw);
      }
      mismatches++;
    }
    bits++;
  } while (bits != 0);
  return mismatches;
}

// The perf-codegen-arm64-scalar-era ("BEFORE") 64-bit sequence int_div_x
// used to emit, prior to being renamed/replaced by int_div_w's 32-bit form.
// Reproduced locally (int_div_x no longer exists in IGenARM64.cpp):
//   quotient: CBNZ Xm,.+8 (0xB5000040|m) ; UDF #0xBEEF ; SDIV/UDIV Xd,Xd,Xm
//   modulo:   CBNZ Xm,.+8 ; UDF ; xDIV X16,Xd,Xm ; MSUB Xd,X16,Xm,Xd
std::vector<uint32_t> before_int_div_x(Register dst, Register arg, bool is_signed, bool is_mod) {
  const uint32_t d = (uint32_t)dst.id() & 31u;
  const uint32_t m = (uint32_t)arg.id() & 31u;
  const uint32_t div = is_signed ? 0x9AC00C00u : 0x9AC00800u;
  const uint32_t cbnz = 0xB5000040u | m;
  const uint32_t udf = 0x0000BEEFu;
  if (!is_mod) {
    return {cbnz, udf, div | (m << 16) | (d << 5) | d};
  }
  return {
      cbnz, udf,
      div | (m << 16) | (d << 5) | 16u,                     // xDIV X16, Xd, Xm
      0x9B008000u | (m << 16) | (d << 10) | (16u << 5) | d,  // MSUB Xd, X16, Xm, Xd
  };
}

// ---------------------------------------------------------------------------
// Step 2: detector vs new/legacy sequences.
// ---------------------------------------------------------------------------
uint64_t check_matcher() {
  uint64_t defects = 0;

  auto expect = [&](const char* what, bool ok) {
    if (!ok) {
      std::fprintf(stderr, "matcher defect: %s\n", what);
      defects++;
    }
  };

  // float -> int
  for (int d : {0, 3, 8, 15}) {
    for (int n : {16, 17, 31}) {
      auto neu = words_of(A::float_to_int32_x86(Register(d), Register(n)));
      auto stats = codegen_arm64::inspect_scalar(neu.data(), neu.size());
      expect("f2i new d/n", stats.f2i_new == 1 && stats.f2i_old == 0);

      auto leg = cgsc_legacy::legacy_float_to_int32(Register(d), Register(n));
      auto lstats = codegen_arm64::inspect_scalar(leg.data(), leg.size());
      expect("f2i legacy d/n", lstats.f2i_old == 1);
    }
  }

  // integer divide
  const std::pair<int, int> div_pairs[] = {{0, 1}, {0, 8}, {8, 1}, {3, 8}, {8, 3}, {15, 9}, {1, 0}};
  for (auto [d, m] : div_pairs) {
    for (bool sgn : {true, false}) {
      for (bool mod : {true, false}) {
        auto neu = words_of(A::int_div_w(Register(d), Register(m), sgn, mod));
        auto stats = codegen_arm64::inspect_scalar(neu.data(), neu.size());
        expect("div new", stats.div_new == 1 && stats.div_total == 1);

        auto leg = cgsc_legacy::legacy_int_div(Register(d), Register(m), sgn, mod);
        auto lstats = codegen_arm64::inspect_scalar(leg.data(), leg.size());
        expect("div legacy new_count==0", lstats.div_new == 0);

        auto before = before_int_div_x(Register(d), Register(m), sgn, mod);
        auto bstats = codegen_arm64::inspect_scalar(before.data(), before.size());
        expect("div before: total==1, new==0", bstats.div_total == 1 && bstats.div_new == 0);
      }
    }
  }

  // swizzle cross products
  for (uint8_t imm : {0x09, 0x12}) {
    for (auto [dst, src] : {std::pair{17, 17}, std::pair{18, 17}, std::pair{16, 31}}) {
      auto neu = words_of(A::swizzle_vf(Register(dst), Register(src), imm));
      auto stats = codegen_arm64::inspect_scalar(neu.data(), neu.size());
      expect("swz new cross", stats.swz_cross_new >= 1 && stats.swz_old == 0);

      auto leg = cgsc_legacy::legacy_swizzle(Register(dst), Register(src), imm);
      auto lstats = codegen_arm64::inspect_scalar(leg.data(), leg.size());
      expect("swz legacy old", lstats.swz_old == 1);
    }
  }
  // All 256 swizzle imms and both pshuf halves: new sequences must never
  // read back as legacy, and total div_total==div_new never applies here
  // (not a divide family) — check f2i_old/swz_old/pshuf_old absence only.
  for (int imm = 0; imm < 256; imm++) {
    for (auto [dst, src] : {std::pair{17, 17}, std::pair{18, 17}, std::pair{16, 31}}) {
      auto neu = words_of(A::swizzle_vf(Register(dst), Register(src), (uint8_t)imm));
      auto stats = codegen_arm64::inspect_scalar(neu.data(), neu.size());
      if (stats.swz_old != 0 || stats.f2i_old != 0) {
        std::fprintf(stderr,
                     "matcher defect: swz new never legacy imm=0x%02x dst=%d src=%d "
                     "swz_old=%llu nwords=%zu\n",
                     imm, dst, src, (unsigned long long)stats.swz_old, neu.size());
        defects++;
      }
    }
    for (int half = 0; half < 2; half++) {
      for (auto [dst, src] : {std::pair{17, 17}, std::pair{18, 17}}) {
        auto neu = words_of(half == 0 ? A::vpshuflw(Register(dst), Register(src), (uint8_t)imm)
                                       : A::vpshufhw(Register(dst), Register(src), (uint8_t)imm));
        auto stats = codegen_arm64::inspect_scalar(neu.data(), neu.size());
        expect("pshuf new never legacy", stats.pshuf_old == 0 && stats.f2i_old == 0);
      }
    }
  }

  return defects;
}

// ---------------------------------------------------------------------------
// Step 3: cases.bin — kernel machine code.
// ---------------------------------------------------------------------------
constexpr uint32_t kMovXdXm(uint32_t d, uint32_t m) {
  return 0xAA0003E0u | (m << 16) | d;
}
constexpr uint32_t kMovVdVn(uint32_t d, uint32_t n) {
  return 0x4EA01C00u | (n << 16) | (n << 5) | d;
}
constexpr uint32_t kLdrQ(uint32_t t, uint32_t n, uint32_t imm) {
  return 0x3DC00000u | ((imm / 16) << 10) | (n << 5) | t;
}
constexpr uint32_t kStrQ(uint32_t t, uint32_t n, uint32_t imm) {
  return 0x3D800000u | ((imm / 16) << 10) | (n << 5) | t;
}
constexpr uint32_t kMovzX8(uint32_t imm16) {
  return 0xD2800008u | (imm16 << 5);
}
constexpr uint32_t kMovkX8(uint32_t imm16) {
  return 0xF2A00008u | (imm16 << 5);
}
constexpr uint32_t kRet = 0xD65F03C0u;

enum Kind : uint32_t { KIND_F2I = 1, KIND_DIV = 2, KIND_SWZ = 3, KIND_PSHUF = 4 };
enum Variant : uint32_t { VAR_NEW = 0, VAR_LEGACY = 1 };

struct Kernel {
  uint32_t kind, variant, p0, p1, p2, p3;
  std::vector<uint32_t> code;  // full function body, including RET
};

std::vector<Kernel> g_kernels;

void add_f2i_kernel(int d, int n, bool full_sweep, bool legacy) {
  std::vector<uint32_t> code;
  code.push_back(kMovVdVn((uint32_t)n, 0));
  std::vector<uint32_t> seq = legacy ? cgsc_legacy::legacy_float_to_int32(Register(d), Register(n))
                                     : words_of(A::float_to_int32_x86(Register(d), Register(n)));
  code.insert(code.end(), seq.begin(), seq.end());
  code.push_back(kMovXdXm(0, (uint32_t)d));
  code.push_back(kRet);
  g_kernels.push_back({KIND_F2I, legacy ? VAR_LEGACY : VAR_NEW, (uint32_t)d, (uint32_t)n,
                       full_sweep ? 1u : 0u, 0u, code});
}

void add_div_kernel(int d, int m, bool sgn, bool mod, bool legacy) {
  std::vector<uint32_t> code;
  code.push_back(kMovXdXm(17, 1));
  code.push_back(kMovXdXm((uint32_t)d, 0));
  code.push_back(kMovXdXm((uint32_t)m, 17));
  bool has8 = (d == 8 || m == 8);
  if (!has8) {
    code.push_back(kMovzX8(0xCAFE));
    code.push_back(kMovkX8(0xBEEF));
  }
  std::vector<uint32_t> seq = legacy ? cgsc_legacy::legacy_int_div(Register(d), Register(m), sgn, mod)
                                     : words_of(A::int_div_w(Register(d), Register(m), sgn, mod));
  code.insert(code.end(), seq.begin(), seq.end());
  code.push_back(kMovXdXm(17, (uint32_t)d));
  code.push_back(kMovXdXm(1, 8));
  code.push_back(kMovXdXm(0, 17));
  code.push_back(kRet);
  uint32_t p0 = sgn ? 1u : 0u, p1 = mod ? 1u : 0u;
  g_kernels.push_back({KIND_DIV, legacy ? VAR_LEGACY : VAR_NEW, p0, p1, (uint32_t)d, (uint32_t)m,
                       code});
}

void add_swz_kernel(int imm, int dst, int src, bool legacy) {
  std::vector<uint32_t> code;
  code.push_back(kLdrQ((uint32_t)src, 0, 0));
  if (dst != src) code.push_back(kLdrQ((uint32_t)dst, 0, 16));
  code.push_back(kLdrQ(20, 0, 32));
  std::vector<uint32_t> seq = legacy
      ? cgsc_legacy::legacy_swizzle(Register(dst), Register(src), (uint8_t)imm)
      : words_of(A::swizzle_vf(Register(dst), Register(src), (uint8_t)imm));
  code.insert(code.end(), seq.begin(), seq.end());
  code.push_back(kStrQ((uint32_t)dst, 1, 0));
  code.push_back(kStrQ(20, 1, 16));
  code.push_back(kRet);
  g_kernels.push_back({KIND_SWZ, legacy ? VAR_LEGACY : VAR_NEW, (uint32_t)imm, (uint32_t)dst,
                       (uint32_t)src, 0u, code});
}

void add_pshuf_kernel(int imm, int half, int dst, int src, bool legacy) {
  std::vector<uint32_t> code;
  code.push_back(kLdrQ((uint32_t)src, 0, 0));
  if (dst != src) code.push_back(kLdrQ((uint32_t)dst, 0, 16));
  code.push_back(kLdrQ(20, 0, 32));
  std::vector<uint32_t> seq =
      legacy ? cgsc_legacy::legacy_pshuf(Register(dst), Register(src), (uint8_t)imm, half * 4)
             : words_of(half == 0 ? A::vpshuflw(Register(dst), Register(src), (uint8_t)imm)
                                  : A::vpshufhw(Register(dst), Register(src), (uint8_t)imm));
  code.insert(code.end(), seq.begin(), seq.end());
  code.push_back(kStrQ((uint32_t)dst, 1, 0));
  code.push_back(kStrQ(20, 1, 16));
  code.push_back(kRet);
  g_kernels.push_back({KIND_PSHUF, legacy ? VAR_LEGACY : VAR_NEW, (uint32_t)imm, (uint32_t)half,
                       (uint32_t)dst, (uint32_t)src, code});
}

void build_kernels() {
  for (int d : {0, 3, 8, 15}) {
    for (int n : {16, 17, 31}) {
      bool fs = (d == 3 && n == 17);
      add_f2i_kernel(d, n, fs, false);
      add_f2i_kernel(d, n, fs, true);
    }
  }
  const std::pair<int, int> div_pairs[] = {{0, 1}, {0, 8}, {8, 1}, {3, 8}, {8, 3}, {15, 9}, {1, 0}};
  for (auto [d, m] : div_pairs) {
    for (bool sgn : {true, false}) {
      for (bool mod : {true, false}) {
        add_div_kernel(d, m, sgn, mod, false);
        add_div_kernel(d, m, sgn, mod, true);
      }
    }
  }
  const std::pair<int, int> swz_pairs[] = {{17, 17}, {18, 17}, {16, 31}};
  for (int imm = 0; imm < 256; imm++) {
    for (auto [dst, src] : swz_pairs) {
      add_swz_kernel(imm, dst, src, false);
      add_swz_kernel(imm, dst, src, true);
    }
  }
  const std::pair<int, int> pshuf_pairs[] = {{17, 17}, {18, 17}};
  for (int imm = 0; imm < 256; imm++) {
    for (int half = 0; half < 2; half++) {
      for (auto [dst, src] : pshuf_pairs) {
        add_pshuf_kernel(imm, half, dst, src, false);
        add_pshuf_kernel(imm, half, dst, src, true);
      }
    }
  }
}

uint32_t align16_words(uint32_t nwords) {
  uint32_t nbytes = nwords * 4;
  uint32_t rem = nbytes % 16;
  if (rem == 0) return nwords;
  return nwords + (16 - rem) / 4;
}

void report_size_stats() {
  auto find = [&](uint32_t kind, uint32_t var, uint32_t p0, int p1 = -1, int p2 = -1,
                  int p3 = -1) -> const Kernel* {
    for (auto& k : g_kernels) {
      if (k.kind != kind || k.variant != var || k.p0 != p0) continue;
      if (p1 >= 0 && k.p1 != (uint32_t)p1) continue;
      if (p2 >= 0 && k.p2 != (uint32_t)p2) continue;
      if (p3 >= 0 && k.p3 != (uint32_t)p3) continue;
      return &k;
    }
    return nullptr;
  };
  auto seqlen = [&](const Kernel* k, int envelope_words) {
    return k ? (int)k->code.size() - envelope_words : -1;
  };
  // f2i envelope: MOV Vn + MOV X0,Xd + RET = 3 words around the sequence.
  printf("gen_f2i_words_new=%d\n", seqlen(find(KIND_F2I, VAR_NEW, 3, 17), 3));
  printf("gen_f2i_words_legacy=%d\n", seqlen(find(KIND_F2I, VAR_LEGACY, 3, 17), 3));

  int div_new_max = 0, div_legacy_max = 0;
  for (auto& k : g_kernels) {
    if (k.kind != KIND_DIV) continue;
    // div envelope: 3 MOVs (+2 sentinel words if applicable) + 3 MOVs + RET.
    bool has8 = (k.p2 == 8 || k.p3 == 8);
    int env = has8 ? 7 : 9;
    int len = (int)k.code.size() - env;
    if (k.variant == VAR_NEW) div_new_max = std::max(div_new_max, len);
    else div_legacy_max = std::max(div_legacy_max, len);
  }
  printf("gen_div_words_new_max=%d\n", div_new_max);
  printf("gen_div_words_legacy_max=%d\n", div_legacy_max);

  // swz envelope: dst!=src -> 2 LDR + 1 LDR(witness) + 2 STR + RET = 6;
  // dst==src -> 1 LDR + 1 LDR(witness) + 2 STR + RET = 5.
  auto swz_env = [](int dst, int src) { return dst != src ? 6 : 5; };
  printf("gen_swz09_words_new_alias=%d\n",
         seqlen(find(KIND_SWZ, VAR_NEW, 0x09, 17, 17), swz_env(17, 17)));
  printf("gen_swz12_words_new_alias=%d\n",
         seqlen(find(KIND_SWZ, VAR_NEW, 0x12, 17, 17), swz_env(17, 17)));
  printf("gen_swz09_words_legacy=%d\n",
         seqlen(find(KIND_SWZ, VAR_LEGACY, 0x09, 17, 17), swz_env(17, 17)));

  int swz_new_max = 0, swz_legacy_max = 0;
  for (auto& k : g_kernels) {
    if (k.kind != KIND_SWZ) continue;
    int env = swz_env((int)k.p1, (int)k.p2);
    int len = (int)k.code.size() - env;
    if (k.variant == VAR_NEW) swz_new_max = std::max(swz_new_max, len);
    else swz_legacy_max = std::max(swz_legacy_max, len);
  }
  printf("gen_swz_words_new_max=%d\n", swz_new_max);
  printf("gen_swz_words_legacy_max=%d\n", swz_legacy_max);

  printf("gen_pshuf88_words_new=%d\n",
         seqlen(find(KIND_PSHUF, VAR_NEW, 0x88, 0, 17, 17), swz_env(17, 17)));
  printf("gen_pshuf88_words_legacy=%d\n",
         seqlen(find(KIND_PSHUF, VAR_LEGACY, 0x88, 0, 17, 17), swz_env(17, 17)));
}

void write_cases_bin(const std::string& path) {
  const uint32_t n = (uint32_t)g_kernels.size();
  struct Entry {
    uint32_t kind, variant, p0, p1, p2, p3, code_word_offset, n_words;
  };
  std::vector<Entry> entries(n);
  std::vector<uint32_t> code;
  for (uint32_t i = 0; i < n; i++) {
    auto& k = g_kernels[i];
    uint32_t off = (uint32_t)code.size();
    entries[i] = {k.kind, k.variant, k.p0, k.p1, k.p2, k.p3, off, (uint32_t)k.code.size()};
    code.insert(code.end(), k.code.begin(), k.code.end());
    uint32_t padded = align16_words((uint32_t)code.size());
    code.resize(padded, kRet);  // pad with RET (harmless, never reached)
  }

  const uint32_t header_words = 4;  // magic(1)+version(1)+n_kernels(1)+code_offset(1)
  const uint32_t table_words = n * 8;
  uint32_t code_offset_bytes = (header_words + table_words) * 4;
  // round code_offset up to a multiple of 4096
  code_offset_bytes = (code_offset_bytes + 4095) & ~4095u;

  std::ofstream f(path, std::ios::binary);
  f.write("CGSC", 4);
  uint32_t version = 1;
  f.write(reinterpret_cast<const char*>(&version), 4);
  f.write(reinterpret_cast<const char*>(&n), 4);
  f.write(reinterpret_cast<const char*>(&code_offset_bytes), 4);
  for (auto& e : entries) {
    f.write(reinterpret_cast<const char*>(&e), sizeof(Entry));
  }
  uint32_t pos = header_words * 4 + table_words * 4;
  while (pos < code_offset_bytes) {
    uint32_t zero = 0;
    f.write(reinterpret_cast<const char*>(&zero), 4);
    pos += 4;
  }
  f.write(reinterpret_cast<const char*>(code.data()), code.size() * 4);
  f.close();
}

}  // namespace

int main() {
  build_kernels();
  printf("gen_kernels=%zu\n", g_kernels.size());

  uint64_t f2i_mismatches = check_f2i_model_vs_x86();
  printf("host_f2i_model_cases=4294967296\n");
  printf("host_f2i_model_mismatches=%llu\n", (unsigned long long)f2i_mismatches);

  uint64_t defects = check_matcher();
  printf("host_matcher_defects=%llu\n", (unsigned long long)defects);

  report_size_stats();

  write_cases_bin("build/cases.bin");
  return 0;
}
