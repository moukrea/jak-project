// int_div_parity test generator (runs on the HOST, x86-64).
//
// For a large set of (a, b) int64 pairs it:
//   1. Builds the four x86 32-bit division/modulo kernels (idiv/udiv/imod/
//      umod), for three different argument registers each (RCX, RSI, R9),
//      using the real goalc x86 emitter (IGenX86.cpp) with EXACTLY the
//      sequence IR_IntegerMath::do_codegen_x86 emits.
//   2. Executes those kernels natively on the host CPU for every pair,
//      catching SIGFPE (divide-by-zero, INT_MIN/-1 overflow) with
//      sigsetjmp/siglongjmp, and records one x86-truth result per (pair,
//      genre): the returned int64 value, or a trap + trap class.
//   3. Emits build/cases.bin: the pairs, the x86-truth table, and standalone
//      arm64 machine code for the NEW (int_div_w) and BEFORE (the previous,
//      64-bit int_div_x) sequences the arm64 runner (runner.c) will execute
//      under qemu/on-device and compare against the x86-truth table.
//
// Nothing here touches goalc/ or IGenARM64.*/IGenX86.*: it only calls into
// the real, unmodified translation units compiled alongside it (see
// CMakeLists.txt).
#include <signal.h>
#include <sys/mman.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <csetjmp>
#include <array>
#include <fstream>
#include <string>
#include <utility>
#include <vector>

#include "goalc/emitter/IGenARM64.h"
#include "goalc/emitter/IGenX86.h"
#include "goalc/emitter/Register.h"

using emitter::InstructionARM64;
using emitter::InstructionX86;
using emitter::Register;
namespace A64 = emitter::IGen::ARM64;
namespace X86 = emitter::IGen::X86;

// Forward declaration for the NEW arm64 int-divide helper, not declared in
// the locked IGenARM64.h header — mirrored exactly like
// goalc/compiler/IR.cpp:39-50 and .autoport/tests/codegen_scalar/gen.cpp.
namespace emitter {
namespace IGen {
namespace ARM64 {
InstructionARM64 int_div_w(Register dst, Register arg, bool is_signed, bool is_mod);
}
}  // namespace IGen
}  // namespace emitter

namespace {

// ---------------------------------------------------------------------------
// The BEFORE (perf-codegen-arm64-scalar-era) 64-bit int_div_x sequence,
// reproduced locally: it no longer exists in IGenARM64.cpp.
//   quotient: CBNZ Xm,.+8 (0xB5000040|m) ; UDF #0xBEEF ; SDIV/UDIV Xd,Xd,Xm
//   modulo:   CBNZ Xm,.+8 ; UDF ; xDIV X16,Xd,Xm ; MSUB Xd,X16,Xm,Xd
std::vector<uint32_t> before_int_div_x(int d, int m, bool is_signed, bool is_mod) {
  const uint32_t dd = (uint32_t)d, mm = (uint32_t)m;
  const uint32_t div = is_signed ? 0x9AC00C00u : 0x9AC00800u;
  const uint32_t cbnz = 0xB5000040u | mm;
  const uint32_t udf = 0x0000BEEFu;
  if (!is_mod) {
    return {cbnz, udf, div | (mm << 16) | (dd << 5) | dd};
  }
  return {
      cbnz, udf,
      div | (mm << 16) | (dd << 5) | 16u,
      0x9B008000u | (mm << 16) | (dd << 10) | (16u << 5) | dd,
  };
}

std::vector<uint32_t> words_of(const InstructionARM64& i) {
  std::vector<uint32_t> w;
  w.push_back(i.encoding);
  for (auto e : i.extra_words) w.push_back(e);
  return w;
}

// ---------------------------------------------------------------------------
// x86 kernels: real machine code built with the real x86 emitter, executed
// natively on the host, matching goalc/compiler/IR.cpp's
// IR_IntegerMath::do_codegen_x86 exactly (dst constrained to RAX there).
// ---------------------------------------------------------------------------
enum Genre : uint32_t { GENRE_IDIV = 0, GENRE_UDIV = 1, GENRE_IMOD = 2, GENRE_UMOD = 3 };
const char* genre_name(uint32_t g) {
  switch (g) {
    case GENRE_IDIV: return "idiv";
    case GENRE_UDIV: return "udiv";
    case GENRE_IMOD: return "imod";
    case GENRE_UMOD: return "umod";
  }
  return "?";
}

std::vector<uint8_t> assemble(const std::vector<InstructionX86>& instrs) {
  std::vector<uint8_t> out;
  uint8_t buf[16];
  for (auto& i : instrs) {
    uint8_t len = i.emit(buf);
    out.insert(out.end(), buf, buf + len);
  }
  return out;
}

// Builds one x86 kernel: int64 kernel(int64 a /*rdi*/, int64 b /*rsi*/).
// mov rax, rdi ; [mov arg, rsi if arg != rsi] ; <genre sequence on arg> ; ret
std::vector<uint8_t> build_x86_kernel(uint32_t genre, Register arg) {
  std::vector<InstructionX86> instrs;
  instrs.push_back(X86::mov_gpr64_gpr64(Register(emitter::RAX), Register(emitter::RDI)));
  if (arg.id() != emitter::RSI) {
    instrs.push_back(X86::mov_gpr64_gpr64(arg, Register(emitter::RSI)));
  }
  switch (genre) {
    case GENRE_IDIV:
      instrs.push_back(X86::cdq());
      instrs.push_back(X86::idiv_gpr32(arg));
      instrs.push_back(
          X86::movsx_r64_r32(Register(emitter::RAX), Register(emitter::RAX)));
      break;
    case GENRE_UDIV:
      instrs.push_back(X86::xor_gpr64_gpr64(Register(emitter::RDX), Register(emitter::RDX)));
      instrs.push_back(X86::unsigned_div_gpr32(arg));
      instrs.push_back(
          X86::movsx_r64_r32(Register(emitter::RAX), Register(emitter::RAX)));
      break;
    case GENRE_IMOD:
      instrs.push_back(X86::cdq());
      instrs.push_back(X86::idiv_gpr32(arg));
      instrs.push_back(
          X86::movsx_r64_r32(Register(emitter::RAX), Register(emitter::RDX)));
      break;
    case GENRE_UMOD:
      instrs.push_back(X86::xor_gpr64_gpr64(Register(emitter::RDX), Register(emitter::RDX)));
      instrs.push_back(X86::unsigned_div_gpr32(arg));
      instrs.push_back(
          X86::movsx_r64_r32(Register(emitter::RAX), Register(emitter::RDX)));
      break;
  }
  instrs.push_back(X86::ret());
  return assemble(instrs);
}

typedef int64_t (*x86_kernel_fn)(int64_t, int64_t);

sigjmp_buf g_jmp;
volatile int g_fault_seen;
void sigfpe_handler(int) {
  g_fault_seen = 1;
  siglongjmp(g_jmp, 1);
}

// Runs kernel(a, b) natively, trapping SIGFPE. Returns true if it faulted.
bool run_x86_kernel(x86_kernel_fn fn, int64_t a, int64_t b, int64_t* out_value) {
  struct sigaction sa, old;
  memset(&sa, 0, sizeof(sa));
  sa.sa_handler = sigfpe_handler;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGFPE, &sa, &old);
  g_fault_seen = 0;
  bool faulted = false;
  if (sigsetjmp(g_jmp, 1) == 0) {
    *out_value = fn(a, b);
  } else {
    faulted = true;
  }
  sigaction(SIGFPE, &old, nullptr);
  return faulted;
}

// ---------------------------------------------------------------------------
// Test values and pairs.
// ---------------------------------------------------------------------------
uint64_t xorshift64(uint64_t* s) {
  uint64_t x = *s;
  x ^= x << 13;
  x ^= x >> 7;
  x ^= x << 17;
  *s = x;
  return x;
}

std::vector<int64_t> build_values() {
  return {
      0, 1, -1, 2, -2, 3, -3, 7, -7, 100, -100,
      (int64_t)INT32_MAX, (int64_t)INT32_MIN, (int64_t)INT32_MIN + 1, (int64_t)INT32_MAX - 1,
      0x80000000ll, 0xFFFFFFFFll,
      (int64_t)0x7FFFFFFF00000005ll,
      0x100000000ll, -0x100000000ll, 0x100000001ll, 0x100000003ll,
      (int64_t)0xFFFFFFFF00000001ull,
      (int64_t)0xFFFFFFFF80000000ull,
      (int64_t)0x00000001FFFFFFFFull,
      (int64_t)0x12345678ABCDEF01ull,
      INT64_MAX, INT64_MIN, INT64_MIN + 1,
      (int64_t)0x5555555555555555ull,
      (int64_t)0xAAAAAAAAAAAAAAAAull,
      (int64_t)0x80000000FFFFFFFFull,
      4, -4, 5, -5, 8, -8, 16, -16, 1000, -1000, 0x7FFFFFFFll, 0xFFFFFFFEll,
  };
}

struct Pair {
  int64_t a, b;
};

std::vector<Pair> build_pairs() {
  std::vector<Pair> pairs;
  auto v = build_values();
  for (auto a : v) {
    for (auto b : v) {
      pairs.push_back({a, b});
    }
  }
  uint64_t seed = 0xD101D3517E5EEDull;
  for (int i = 0; i < 60000; i++) {
    int64_t a, b;
    int which = i % 4;
    if (which == 0) {
      a = (int64_t)xorshift64(&seed);
      b = (int64_t)xorshift64(&seed);
    } else if (which == 1) {
      a = (int32_t)xorshift64(&seed);
      b = (int32_t)xorshift64(&seed);
    } else if (which == 2) {
      a = (int64_t)(uint32_t)xorshift64(&seed) | ((xorshift64(&seed) & 1) ? 0x100000000ll : 0);
      b = (int64_t)(uint32_t)xorshift64(&seed) | ((xorshift64(&seed) & 1) ? 0x100000000ll : 0);
    } else {
      a = (int64_t)(xorshift64(&seed) % 2000) - 1000;
      int32_t hi = (int32_t)xorshift64(&seed);
      a |= ((int64_t)hi << 32) & 0xFFFFFFFF00000000ll;
      b = (int64_t)(xorshift64(&seed) % 2000) - 1000;
    }
    pairs.push_back({a, b});
  }
  return pairs;
}

// ---------------------------------------------------------------------------
// arm64 kernel envelope (matches codegen_scalar's add_div_kernel shape):
// int64 kernel(int64 a /*x0*/, int64 b /*x1*/) -> int64 (x0).
// ---------------------------------------------------------------------------
constexpr uint32_t kMovXdXm(uint32_t d, uint32_t m) {
  return 0xAA0003E0u | (m << 16) | d;
}
constexpr uint32_t kRet = 0xD65F03C0u;

std::vector<uint32_t> build_arm64_kernel(int d, int m, bool sgn, bool mod, bool before) {
  std::vector<uint32_t> code;
  code.push_back(kMovXdXm(17, 1));  // x17 = b
  code.push_back(kMovXdXm((uint32_t)d, 0));  // xd = a
  code.push_back(kMovXdXm((uint32_t)m, 17));  // xm = b
  std::vector<uint32_t> seq =
      before ? before_int_div_x(d, m, sgn, mod)
             : words_of(A64::int_div_w(Register(d), Register(m), sgn, mod));
  code.insert(code.end(), seq.begin(), seq.end());
  if (d != 0) {
    code.push_back(kMovXdXm(0, (uint32_t)d));
  }
  code.push_back(kRet);
  return code;
}

}  // namespace

int main() {
  auto pairs = build_pairs();
  printf("int_div_pairs=%zu\n", pairs.size());

  // x86 kernels: 4 genres x 3 argument registers.
  const Register arg_regs[] = {Register(emitter::RCX), Register(emitter::RSI), Register(emitter::R9)};
  std::vector<uint8_t> code_pages;
  struct HostKernel {
    x86_kernel_fn fn;
  };
  HostKernel host[4][3];
  {
    // One big RWX mapping for all 12 kernels, 64 bytes apart (plenty).
    size_t page = 4096;
    void* mem = mmap(nullptr, page, PROT_READ | PROT_WRITE | PROT_EXEC,
                     MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    uint8_t* base = (uint8_t*)mem;
    size_t off = 0;
    for (uint32_t g = 0; g < 4; g++) {
      for (int r = 0; r < 3; r++) {
        auto bytes = build_x86_kernel(g, arg_regs[r]);
        memcpy(base + off, bytes.data(), bytes.size());
        host[g][r].fn = (x86_kernel_fn)(base + off);
        off += 64;
      }
    }
  }
  uint64_t x86_kernels = 12, x86_executions = 0, variant_disagree = 0;
  uint64_t traps_zero = 0, traps_overflow = 0, traps_other = 0;

  // results[pair][genre]
  struct Result {
    int64_t value;
    uint32_t trap;
    uint32_t trap_class;  // 0 none, 1 zero, 2 overflow, 3 other
  };
  std::vector<std::array<Result, 4>> results(pairs.size());

  for (size_t pi = 0; pi < pairs.size(); pi++) {
    int64_t a = pairs[pi].a, b = pairs[pi].b;
    for (uint32_t g = 0; g < 4; g++) {
      bool signed_genre = (g == GENRE_IDIV || g == GENRE_IMOD);
      bool zero_case = (uint32_t)b == 0;
      bool overflow_case =
          signed_genre && (int32_t)a == (int32_t)0x80000000 && (int32_t)b == -1;
      int64_t agreed_value = 0;
      bool agreed_faulted = false;
      bool first = true;
      bool disagree_here = false;
      for (int r = 0; r < 3; r++) {
        int64_t v = 0;
        bool faulted = run_x86_kernel(host[g][r].fn, a, b, &v);
        x86_executions++;
        if (first) {
          agreed_value = v;
          agreed_faulted = faulted;
          first = false;
        } else if (faulted != agreed_faulted || (!faulted && v != agreed_value)) {
          disagree_here = true;
        }
      }
      if (disagree_here) variant_disagree++;
      uint32_t trap_class = 0;
      if (agreed_faulted) {
        if (zero_case) {
          trap_class = 1;
          traps_zero++;
        } else if (overflow_case) {
          trap_class = 2;
          traps_overflow++;
        } else {
          trap_class = 3;
          traps_other++;
        }
      }
      results[pi][g] = {agreed_value, (uint32_t)(agreed_faulted ? 1 : 0), trap_class};
    }
  }

  printf("int_div_x86_kernels=%llu\n", (unsigned long long)x86_kernels);
  printf("int_div_x86_executions=%llu\n", (unsigned long long)x86_executions);
  printf("int_div_x86_variant_disagree=%llu\n", (unsigned long long)variant_disagree);
  printf("int_div_x86_traps_zero=%llu\n", (unsigned long long)traps_zero);
  printf("int_div_x86_traps_overflow=%llu\n", (unsigned long long)traps_overflow);
  printf("int_div_x86_traps_other=%llu\n", (unsigned long long)traps_other);
  printf("int_div_x86_instr_per_div=3\n");

  // arm64 kernels: (d,m) x genre x {NEW,BEFORE}.
  const std::pair<int, int> dm_pairs[] = {{0, 1}, {0, 8}, {8, 1}, {3, 8}, {8, 3}, {15, 9}, {1, 0}};
  struct ArmKernel {
    uint32_t variant, genre;
    std::vector<uint32_t> code;
  };
  std::vector<ArmKernel> arm_kernels;
  int words_div_after = -1, words_mod_after = -1;
  for (auto [d, m] : dm_pairs) {
    for (uint32_t g = 0; g < 4; g++) {
      bool sgn = (g == GENRE_IDIV || g == GENRE_UDIV) ? (g == GENRE_IDIV) : (g == GENRE_IMOD);
      // sgn: idiv/imod -> signed; udiv/umod -> unsigned.
      sgn = (g == GENRE_IDIV || g == GENRE_IMOD);
      bool mod = (g == GENRE_IMOD || g == GENRE_UMOD);
      arm_kernels.push_back({0, g, build_arm64_kernel(d, m, sgn, mod, false)});
      arm_kernels.push_back({1, g, build_arm64_kernel(d, m, sgn, mod, true)});
      if (d == 0 && m == 1) {
        auto raw = words_of(A64::int_div_w(Register(d), Register(m), sgn, mod));
        if (!mod) words_div_after = (int)raw.size();
        else words_mod_after = (int)raw.size();
      }
    }
  }
  printf("int_div_words_div_before=3\n");
  printf("int_div_words_mod_before=4\n");
  printf("int_div_words_div_after=%d\n", words_div_after);
  printf("int_div_words_mod_after=%d\n", words_mod_after);
  printf("int_div_exec_div_before=2\n");
  printf("int_div_exec_mod_before=3\n");
  printf("int_div_exec_div_after=%d\n", words_div_after - 1);
  printf("int_div_exec_mod_after=%d\n", words_mod_after - 1);

  // --- write build/cases.bin ---
  std::ofstream f("build/cases.bin", std::ios::binary);
  auto w32 = [&](uint32_t v) { f.write((const char*)&v, 4); };
  auto w64 = [&](int64_t v) { f.write((const char*)&v, 8); };

  f.write("IDVP", 4);
  w32(1);                            // version
  w32((uint32_t)pairs.size());       // n_pairs
  w32((uint32_t)arm_kernels.size());  // n_kernels
  uint32_t header_bytes = 8 * 4;
  uint32_t pairs_offset = header_bytes;
  uint32_t pairs_bytes = (uint32_t)pairs.size() * 16;
  uint32_t results_offset = pairs_offset + pairs_bytes;
  uint32_t results_bytes = (uint32_t)pairs.size() * 4 * 16;  // 4 genres * (i64+u32+u32)
  uint32_t kernel_table_offset = results_offset + results_bytes;
  uint32_t kernel_table_bytes = (uint32_t)arm_kernels.size() * 16;  // variant,genre,off,n
  uint32_t code_offset = kernel_table_offset + kernel_table_bytes;
  code_offset = (code_offset + 4095) & ~4095u;
  w32(pairs_offset);
  w32(results_offset);
  w32(kernel_table_offset);
  w32(code_offset);

  for (auto& p : pairs) {
    w64(p.a);
    w64(p.b);
  }
  for (auto& r4 : results) {
    for (auto& r : r4) {
      w64(r.value);
      w32(r.trap);
      w32(r.trap_class);
    }
  }
  std::vector<uint32_t> code;
  std::vector<uint32_t> koff, kn;
  for (auto& k : arm_kernels) {
    koff.push_back((uint32_t)code.size());
    kn.push_back((uint32_t)k.code.size());
    code.insert(code.end(), k.code.begin(), k.code.end());
  }
  for (size_t i = 0; i < arm_kernels.size(); i++) {
    w32(arm_kernels[i].variant);
    w32(arm_kernels[i].genre);
    w32(koff[i]);
    w32(kn[i]);
  }
  uint32_t pos = kernel_table_offset + kernel_table_bytes;
  while (pos < code_offset) {
    w32(0);
    pos += 4;
  }
  f.write((const char*)code.data(), code.size() * 4);
  f.close();

  return 0;
}
