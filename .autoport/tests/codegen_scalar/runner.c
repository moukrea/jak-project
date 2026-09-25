/* perf-codegen-arm64-scalar test runner — arm64, self-contained, C99.
 *
 * Maps build/cases.bin PROT_READ|PROT_EXEC and calls every kernel it
 * describes (float->int, integer divide, swizzle, pshuf; new and legacy
 * variants), checking each against the shared model (model.h) and, for
 * divide, new against legacy directly. Prints key=value lines on stdout,
 * `parity_done=1` last.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <signal.h>
#include <ucontext.h>
#include <setjmp.h>
#include <time.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <pthread.h>
#include <float.h>

#include "model.h"

/* ---- cases.bin layout (little-endian, matches gen.cpp) ---- */
#pragma pack(push, 1)
typedef struct {
  uint32_t kind, variant, p0, p1, p2, p3, code_word_offset, n_words;
} Entry;
#pragma pack(pop)

enum { KIND_F2I = 1, KIND_DIV = 2, KIND_SWZ = 3, KIND_PSHUF = 4 };
enum { VAR_NEW = 0, VAR_LEGACY = 1 };

typedef int64_t (*f2i_fn)(float);
typedef struct {
  int64_t q;
  uint64_t x8;
} div_ret;
typedef div_ret (*div_fn)(int64_t, int64_t);
typedef void (*vec_fn)(const uint32_t*, uint32_t*);

static uint8_t* g_map;
static size_t g_map_len;
static Entry* g_entries;
static uint32_t g_n_kernels;
static uint8_t* g_code_base;

static void* kernel_ptr(const Entry* e) {
  return (void*)(g_code_base + (size_t)e->code_word_offset * 4);
}

static const Entry* find_kernel(uint32_t kind, uint32_t variant, int p0, int p1, int p2, int p3) {
  for (uint32_t i = 0; i < g_n_kernels; i++) {
    Entry* e = &g_entries[i];
    if (e->kind != kind || e->variant != variant) continue;
    if (p0 >= 0 && e->p0 != (uint32_t)p0) continue;
    if (p1 >= 0 && e->p1 != (uint32_t)p1) continue;
    if (p2 >= 0 && e->p2 != (uint32_t)p2) continue;
    if (p3 >= 0 && e->p3 != (uint32_t)p3) continue;
    return e;
  }
  return NULL;
}

static uint64_t xorshift64(uint64_t* s) {
  uint64_t x = *s;
  x ^= x << 13;
  x ^= x >> 7;
  x ^= x << 17;
  *s = x;
  return x;
}

/* ---------------------------------------------------------------------- */
/* float -> int                                                            */
/* ---------------------------------------------------------------------- */
static uint64_t g_f2i_new_bad, g_f2i_legacy_bad;
static uint64_t g_f2i_cases;

static void f2i_check_one(f2i_fn new_fn, f2i_fn legacy_fn, uint32_t bits) {
  float f;
  memcpy(&f, &bits, sizeof(f));
  int64_t want = model_f2i_bits(bits);
  int64_t got_new = new_fn(f);
  int64_t got_legacy = legacy_fn(f);
  __atomic_fetch_add(&g_f2i_cases, 1, __ATOMIC_RELAXED);
  if (got_new != want) __atomic_fetch_add(&g_f2i_new_bad, 1, __ATOMIC_RELAXED);
  if (got_legacy != want) __atomic_fetch_add(&g_f2i_legacy_bad, 1, __ATOMIC_RELAXED);
}

typedef struct {
  f2i_fn new_fn, legacy_fn;
  uint64_t start, end;  /* half-open range of bit patterns, [start,end) ; 64-bit: the
                           last thread ends at 2^32, which a uint32_t would wrap to 0 */
  uint32_t stride;
} SweepArg;

static uint64_t g_f2i_sweep_cases, g_f2i_sweep_expected;

static void* sweep_thread(void* argp) {
  SweepArg* a = (SweepArg*)argp;
  uint64_t bits = a->start, n = 0;
  for (; bits < a->end; bits += a->stride) {
    f2i_check_one(a->new_fn, a->legacy_fn, (uint32_t)bits);
    n++;
  }
  __atomic_fetch_add(&g_f2i_sweep_cases, n, __ATOMIC_RELAXED);
  return NULL;
}

static void run_f2i_sweep(f2i_fn new_fn, f2i_fn legacy_fn, uint32_t stride) {
  const int nthreads = 4;
  pthread_t th[4];
  SweepArg args[4];
  uint64_t total = 1ull << 32;
  uint64_t chunk = (total + nthreads - 1) / nthreads;
  for (int i = 0; i < nthreads; i++) {
    uint64_t start = chunk * i;
    uint64_t end = start + chunk;
    if (end > total) end = total;
    args[i].new_fn = new_fn;
    args[i].legacy_fn = legacy_fn;
    args[i].start = start;
    args[i].end = end;
    if (end > start) g_f2i_sweep_expected += (end - start + stride - 1) / stride;
    args[i].stride = stride;
    pthread_create(&th[i], NULL, sweep_thread, &args[i]);
  }
  for (int i = 0; i < nthreads; i++) pthread_join(th[i], NULL);
}

static void run_f2i_boundaries(f2i_fn new_fn, f2i_fn legacy_fn) {
  uint32_t bits_list[64];
  int n = 0;
#define ADDF(x) do { float _f = (float)(x); uint32_t _b; memcpy(&_b, &_f, 4); bits_list[n++] = _b; } while (0)
#define ADDB(x) do { bits_list[n++] = (uint32_t)(x); } while (0)
  ADDF(0.0); ADDF(-0.0);
  ADDB(0x00000001u); ADDB(0x80000001u);       /* smallest denormal +/- */
  ADDB(0x007FFFFFu); ADDB(0x807FFFFFu);       /* largest denormal +/- */
  ADDB(0x00800000u); ADDB(0x80800000u);       /* FLT_MIN +/- */
  ADDF(0.5); ADDF(-0.5);
  ADDF(0.99999994f); ADDF(-0.99999994f);
  ADDF(1.0); ADDF(-1.0);
  ADDF(1.5); ADDF(-1.5);
  ADDF(2147483520.0f); ADDF(-2147483520.0f);
  ADDF(2147483648.0f); ADDF(-2147483648.0f);
  ADDF(-2147483904.0f);
  ADDF(4294967296.0f); ADDF(-4294967296.0f);
  ADDF(9.2233720e18f); ADDF(-9.2233720e18f);
  ADDF(FLT_MAX); ADDF(-FLT_MAX);
  ADDB(0x7F800000u); ADDB(0xFF800000u);       /* +/-Inf */
  ADDB(0x7FC00000u);                          /* NaN quiet */
  ADDB(0x7F800001u);                          /* NaN signaling */
  ADDB(0xFFC00000u);
  ADDB(0xFFFFFFFFu);
  ADDB(0x7FFFFFFFu);
#undef ADDF
#undef ADDB
  for (int i = 0; i < n; i++) f2i_check_one(new_fn, legacy_fn, bits_list[i]);

  uint64_t seed = 0x9E3779B97F4A7C15ull;
  for (int i = 0; i < 1000000; i++) {
    uint32_t bits = (uint32_t)xorshift64(&seed);
    f2i_check_one(new_fn, legacy_fn, bits);
  }
}

/* ---------------------------------------------------------------------- */
/* integer divide                                                         */
/* ---------------------------------------------------------------------- */
static uint64_t g_div_new_vs_legacy_bad, g_div_x8_clobbered;
static uint64_t g_div_x86_cases, g_div_new_vs_x86_bad;
static uint64_t g_div_zero_kernels, g_div_zero_trapped;

static sigjmp_buf g_jmp;
static volatile int g_sigill_pc_ok;
static void sigill_handler(int sig, siginfo_t* info, void* ucontext_v) {
  (void)sig;
  (void)info;
  ucontext_t* uc = (ucontext_t*)ucontext_v;
#if defined(__aarch64__)
  uint32_t* pc = (uint32_t*)uc->uc_mcontext.pc;
  g_sigill_pc_ok = (*pc == 0x0000BEEFu);
#else
  g_sigill_pc_ok = 0;
#endif
  siglongjmp(g_jmp, 1);
}

static void div_check_pair(div_fn new_fn, div_fn legacy_fn, int is_signed, int is_mod, int d,
                           int m, int64_t a, int64_t b) {
  div_ret rn = new_fn(a, b);
  div_ret rl = legacy_fn(a, b);
  int has8 = (d == 8 || m == 8);
  if (!has8) {
    if (rn.x8 != 0xBEEFCAFEull) g_div_x8_clobbered++;
    if (rl.x8 != 0xBEEFCAFEull) g_div_x8_clobbered++;
  }
  /* legacy 64-bit domain: new-vs-legacy is only expected to agree where the
   * old 64-bit divide happened to render the same thing as x86 32-bit. */
  int in_x86_domain = 0;
  if (is_signed) {
    if (a >= INT32_MIN && a <= INT32_MAX && b >= INT32_MIN && b <= INT32_MAX &&
        !(a == INT32_MIN && b == -1)) {
      in_x86_domain = 1;
    }
  } else {
    if (a >= 0 && a <= INT32_MAX && b >= 0 && b <= INT32_MAX) {
      in_x86_domain = 1;
    }
  }
  if (in_x86_domain) {
    if (rn.q != rl.q) g_div_new_vs_legacy_bad++;
  }

  /* new-vs-x86-model domain: every pair whose low 32 bits of b are nonzero. */
  if ((uint32_t)b != 0) {
    int64_t want = is_signed ? (is_mod ? model_imod32(a, b) : model_idiv32(a, b))
                             : (is_mod ? model_umod32(a, b) : model_udiv32(a, b));
    g_div_x86_cases++;
    if (rn.q != want) g_div_new_vs_x86_bad++;
  }
}

static void run_div_family(div_fn new_fn, div_fn legacy_fn, int is_signed, int is_mod, int d,
                           int m) {
  int64_t vals[] = {0, 1, -1, 2, -2, 3, -3, 7, -7, 100, -100, INT32_MAX, INT32_MIN,
                    (int64_t)INT32_MAX + 1, (int64_t)INT32_MIN - 1, (int64_t)UINT32_MAX,
                    INT64_MAX, INT64_MIN, INT64_MIN + 1, (int64_t)0x5555555555555555ll,
                    (int64_t)0xAAAAAAAAAAAAAAAAull, (int64_t)0x100000000ll,
                    -(int64_t)0x100000000ll};
  int nv = (int)(sizeof(vals) / sizeof(vals[0]));
  for (int i = 0; i < nv; i++) {
    for (int j = 0; j < nv; j++) {
      int64_t a = vals[i], b = vals[j];
      if ((uint32_t)b == 0) continue;
      div_check_pair(new_fn, legacy_fn, is_signed, is_mod, d, m, a, b);
    }
  }
  uint64_t seed = 0x9E3779B97F4A7C15ull ^ ((uint64_t)d << 32) ^ (uint64_t)m ^
                 ((uint64_t)is_signed << 1) ^ (uint64_t)is_mod;
  for (int i = 0; i < 200000; i++) {
    int64_t a, b;
    int which = i % 3;
    if (which == 0) {
      a = (int64_t)xorshift64(&seed);
      b = (int64_t)xorshift64(&seed);
    } else if (which == 1) {
      a = (int32_t)xorshift64(&seed);
      b = (int32_t)xorshift64(&seed);
    } else {
      a = (int64_t)(xorshift64(&seed) % 2000) - 1000;
      b = (int64_t)(xorshift64(&seed) % 2000) - 1000;
    }
    if ((uint32_t)b == 0) b = 1;
    div_check_pair(new_fn, legacy_fn, is_signed, is_mod, d, m, a, b);
  }

  /* divide by zero trap: only the NEW kernel is required to trap, matching
   * the A26 CBNZ/UDF prefix both new and legacy share. Two zero-kernels:
   * a literal 0, and 0x100000000 (nonzero 64-bit, zero low 32 bits — the
   * trap must fire on the low 32 bits, like x86's 32-bit divisor). */
  struct sigaction sa, old;
  memset(&sa, 0, sizeof(sa));
  sa.sa_sigaction = sigill_handler;
  sa.sa_flags = SA_SIGINFO;
  sigemptyset(&sa.sa_mask);
  const int64_t zero_bs[] = {0, 0x100000000ll};
  for (size_t zi = 0; zi < sizeof(zero_bs) / sizeof(zero_bs[0]); zi++) {
    g_div_zero_kernels++;
    sigaction(SIGILL, &sa, &old);
    g_sigill_pc_ok = 0;
    if (sigsetjmp(g_jmp, 1) == 0) {
      new_fn(1, zero_bs[zi]);
    } else {
      if (g_sigill_pc_ok) g_div_zero_trapped++;
    }
    sigaction(SIGILL, &old, NULL);
  }
}

/* ---------------------------------------------------------------------- */
/* swizzle / pshuf                                                        */
/* ---------------------------------------------------------------------- */
static uint64_t g_swz_cases, g_swz_new_bad, g_swz_legacy_bad, g_swz_canary_bad;
static uint64_t g_pshuf_cases, g_pshuf_new_bad, g_pshuf_legacy_bad, g_pshuf_canary_bad;

static void gen_vector(uint64_t* seed, uint32_t v[4], int idx) {
  static const uint32_t nans[] = {0x7FC00001u, 0xFFC0DEADu, 0x7F812345u, 0xFFABCDEFu};
  for (int i = 0; i < 4; i++) {
    if (idx < 4 && (i == idx % 4)) {
      v[i] = nans[idx % 4];
    } else {
      v[i] = (uint32_t)xorshift64(seed);
    }
  }
}

static void run_swz_pshuf(void) {
  uint64_t seed = 0x9E3779B97F4A7C15ull ^ 0xABCDEF01ull;
  uint32_t in[16][12];  /* 48 bytes = 12 u32 per vector-in buffer, 16 sets */
  for (int s = 0; s < 16; s++) {
    uint32_t v[4];
    gen_vector(&seed, v, s);
    for (int i = 0; i < 4; i++) in[s][i] = v[i];               /* src @ 0 */
    for (int i = 0; i < 4; i++) in[s][4 + i] = 0xDEADBEEFu;    /* alias-witness @16 */
    uint32_t canary[4];
    gen_vector(&seed, canary, -1);
    for (int i = 0; i < 4; i++) in[s][8 + i] = canary[i];      /* canary @32 */
  }

  for (uint32_t imm = 0; imm < 256; imm++) {
    static const int dst_src[][2] = {{17, 17}, {18, 17}, {16, 31}};
    for (int p = 0; p < 3; p++) {
      const Entry* en = find_kernel(KIND_SWZ, VAR_NEW, (int)imm, dst_src[p][0], dst_src[p][1], -1);
      const Entry* el = find_kernel(KIND_SWZ, VAR_LEGACY, (int)imm, dst_src[p][0], dst_src[p][1], -1);
      if (!en || !el) continue;
      vec_fn fn_new = (vec_fn)kernel_ptr(en);
      vec_fn fn_legacy = (vec_fn)kernel_ptr(el);
      for (int s = 0; s < 16; s++) {
        uint32_t src4[4] = {in[s][0], in[s][1], in[s][2], in[s][3]};
        uint32_t want[4];
        model_swizzle(src4, (uint8_t)imm, want);
        uint32_t out_new[8], out_legacy[8];
        fn_new(in[s], out_new);
        fn_legacy(in[s], out_legacy);
        g_swz_cases++;
        if (memcmp(out_new, want, 16) != 0) g_swz_new_bad++;
        if (memcmp(out_legacy, want, 16) != 0) g_swz_legacy_bad++;
        if (memcmp(out_new + 4, &in[s][8], 16) != 0) g_swz_canary_bad++;
        if (memcmp(out_legacy + 4, &in[s][8], 16) != 0) g_swz_canary_bad++;
      }
    }
  }

  for (uint32_t imm = 0; imm < 256; imm++) {
    for (int half = 0; half < 2; half++) {
      static const int dst_src[][2] = {{17, 17}, {18, 17}};
      for (int p = 0; p < 2; p++) {
        const Entry* en =
            find_kernel(KIND_PSHUF, VAR_NEW, (int)imm, half, dst_src[p][0], dst_src[p][1]);
        const Entry* el =
            find_kernel(KIND_PSHUF, VAR_LEGACY, (int)imm, half, dst_src[p][0], dst_src[p][1]);
        if (!en || !el) continue;
        vec_fn fn_new = (vec_fn)kernel_ptr(en);
        vec_fn fn_legacy = (vec_fn)kernel_ptr(el);
        for (int s = 0; s < 16; s++) {
          uint16_t src8[8];
          memcpy(src8, in[s], 16);
          uint16_t want[8];
          model_pshuf(src8, (uint8_t)imm, half, want);
          uint32_t out_new[8], out_legacy[8];
          fn_new(in[s], out_new);
          fn_legacy(in[s], out_legacy);
          g_pshuf_cases++;
          if (memcmp(out_new, want, 16) != 0) g_pshuf_new_bad++;
          if (memcmp(out_legacy, want, 16) != 0) g_pshuf_legacy_bad++;
          if (memcmp(out_new + 4, &in[s][8], 16) != 0) g_pshuf_canary_bad++;
          if (memcmp(out_legacy + 4, &in[s][8], 16) != 0) g_pshuf_canary_bad++;
        }
      }
    }
  }
}

/* ---------------------------------------------------------------------- */
int main(int argc, char** argv) {
  if (argc < 2) {
    fprintf(stderr, "usage: %s <cases.bin>\n", argv[0]);
    return 2;
  }
  int fd = open(argv[1], O_RDONLY);
  if (fd < 0) {
    perror("open");
    return 2;
  }
  struct stat st;
  fstat(fd, &st);
  g_map_len = (size_t)st.st_size;
  g_map = mmap(NULL, g_map_len, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0);
  if (g_map == MAP_FAILED) {
    perror("mmap");
    return 2;
  }
  close(fd);

  if (memcmp(g_map, "CGSC", 4) != 0) {
    fprintf(stderr, "bad magic\n");
    return 2;
  }
  uint32_t version, n_kernels, code_offset;
  memcpy(&version, g_map + 4, 4);
  memcpy(&n_kernels, g_map + 8, 4);
  memcpy(&code_offset, g_map + 12, 4);
  g_n_kernels = n_kernels;
  g_entries = (Entry*)(g_map + 16);
  g_code_base = g_map + code_offset;

  struct timespec t0, t1;
  clock_gettime(CLOCK_MONOTONIC, &t0);

  uint32_t stride = 1;
  const char* stride_env = getenv("CGSC_SWEEP_STRIDE");
  if (stride_env && stride_env[0]) stride = (uint32_t)strtoul(stride_env, NULL, 10);
  if (stride == 0) stride = 1;

  const char* only_div_env = getenv("CGSC_ONLY_DIV");
  int only_div = only_div_env && only_div_env[0] && only_div_env[0] != '0';

  if (!only_div) {
    const Entry* f2i_new_full = find_kernel(KIND_F2I, VAR_NEW, 3, 17, 1, -1);
    const Entry* f2i_legacy_full = find_kernel(KIND_F2I, VAR_LEGACY, 3, 17, 1, -1);
    if (f2i_new_full && f2i_legacy_full) {
      run_f2i_sweep((f2i_fn)kernel_ptr(f2i_new_full), (f2i_fn)kernel_ptr(f2i_legacy_full), stride);
    }
    printf("parity_f2i_sweep_stride=%u\n", stride);
    printf("parity_f2i_sweep_cases=%llu\n", (unsigned long long)g_f2i_sweep_cases);
    printf("parity_f2i_sweep_expected=%llu\n", (unsigned long long)g_f2i_sweep_expected);

    for (uint32_t i = 0; i < g_n_kernels; i++) {
      Entry* e = &g_entries[i];
      if (e->kind != KIND_F2I || e->variant != VAR_NEW) continue;
      if ((int)e->p2 == 1) continue;  /* full-sweep kernel handled above */
      const Entry* legacy = find_kernel(KIND_F2I, VAR_LEGACY, (int)e->p0, (int)e->p1, -1, -1);
      if (!legacy) continue;
      run_f2i_boundaries((f2i_fn)kernel_ptr(e), (f2i_fn)kernel_ptr(legacy));
    }
    printf("parity_f2i_cases=%llu\n", (unsigned long long)g_f2i_cases);
    printf("parity_f2i_new_vs_x86=%llu\n", (unsigned long long)g_f2i_new_bad);
    printf("parity_f2i_legacy_vs_x86=%llu\n", (unsigned long long)g_f2i_legacy_bad);
  }

  for (uint32_t i = 0; i < g_n_kernels; i++) {
    Entry* e = &g_entries[i];
    if (e->kind != KIND_DIV || e->variant != VAR_NEW) continue;
    const Entry* legacy =
        find_kernel(KIND_DIV, VAR_LEGACY, (int)e->p0, (int)e->p1, (int)e->p2, (int)e->p3);
    if (!legacy) continue;
    run_div_family((div_fn)kernel_ptr(e), (div_fn)kernel_ptr(legacy), (int)e->p0, (int)e->p1,
                   (int)e->p2, (int)e->p3);
  }
  printf("parity_div_new_vs_legacy=%llu\n", (unsigned long long)g_div_new_vs_legacy_bad);
  printf("parity_div_x8_clobbered=%llu\n", (unsigned long long)g_div_x8_clobbered);
  printf("parity_div_x86_cases=%llu\n", (unsigned long long)g_div_x86_cases);
  printf("parity_div_new_vs_x86=%llu\n", (unsigned long long)g_div_new_vs_x86_bad);
  printf("parity_div_zero_kernels=%llu\n", (unsigned long long)g_div_zero_kernels);
  printf("parity_div_zero_trapped=%llu\n", (unsigned long long)g_div_zero_trapped);

  if (!only_div) {
    run_swz_pshuf();
    printf("parity_swz_cases=%llu\n", (unsigned long long)g_swz_cases);
    printf("parity_swz_new_bad=%llu\n", (unsigned long long)g_swz_new_bad);
    printf("parity_swz_legacy_bad=%llu\n", (unsigned long long)g_swz_legacy_bad);
    printf("parity_swz_canary_bad=%llu\n", (unsigned long long)g_swz_canary_bad);
    printf("parity_pshuf_cases=%llu\n", (unsigned long long)g_pshuf_cases);
    printf("parity_pshuf_new_bad=%llu\n", (unsigned long long)g_pshuf_new_bad);
    printf("parity_pshuf_legacy_bad=%llu\n", (unsigned long long)g_pshuf_legacy_bad);
    printf("parity_pshuf_canary_bad=%llu\n", (unsigned long long)g_pshuf_canary_bad);
  }

  uint64_t total_bad = g_f2i_new_bad + g_f2i_legacy_bad + g_div_new_vs_legacy_bad +
                       g_div_x8_clobbered + g_div_new_vs_x86_bad + g_swz_new_bad + g_swz_legacy_bad +
                       g_swz_canary_bad + g_pshuf_new_bad + g_pshuf_legacy_bad + g_pshuf_canary_bad +
                       (g_div_zero_kernels - g_div_zero_trapped) +
                       /* an incomplete sweep is a defect, not a smaller green, but only
                        * when the sweep actually ran (CGSC_ONLY_DIV skips it on purpose) */
                       (!only_div &&
                        (g_f2i_sweep_expected == 0 || g_f2i_sweep_cases != g_f2i_sweep_expected));
  uint64_t kernels_run = g_n_kernels;

  clock_gettime(CLOCK_MONOTONIC, &t1);
  double secs = (t1.tv_sec - t0.tv_sec) + (t1.tv_nsec - t0.tv_nsec) / 1e9;

  printf("parity_total_bad=%llu\n", (unsigned long long)total_bad);
  printf("parity_kernels_run=%llu\n", (unsigned long long)kernels_run);
  printf("parity_seconds=%.3f\n", secs);
  printf("parity_done=1\n");
  return 0;
}
