/* int_div_parity test runner — arm64, self-contained, C99.
 *
 * Maps build/cases.bin PROT_READ|PROT_EXEC and calls every arm64 divide
 * kernel it describes (NEW = int_div_w, BEFORE = the old 64-bit int_div_x)
 * on every (a, b) pair, comparing against the x86-truth table gen.cpp
 * baked into the same file. Prints key=value lines on stdout,
 * `int_div_runner_done=1` last.
 */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <signal.h>
#include <ucontext.h>
#include <setjmp.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>

#pragma pack(push, 1)
typedef struct {
  char magic[4];
  uint32_t version, n_pairs, n_kernels;
  uint32_t pairs_offset, results_offset, kernel_table_offset, code_offset;
} Header;
typedef struct {
  uint32_t variant, genre, code_word_offset, n_words;
} KernelEntry;
typedef struct {
  int64_t value;
  uint32_t trap, trap_class;
} X86Result;
#pragma pack(pop)

enum { GENRE_IDIV = 0, GENRE_UDIV = 1, GENRE_IMOD = 2, GENRE_UMOD = 3 };
enum { VAR_NEW = 0, VAR_BEFORE = 1 };

typedef int64_t (*div_fn)(int64_t, int64_t);

static uint8_t* g_map;
static Header* g_hdr;
static int64_t* g_pairs;         /* n_pairs*2 */
static X86Result* g_results;     /* n_pairs*4 */
static KernelEntry* g_kernels;
static uint8_t* g_code_base;

static sigjmp_buf g_jmp;
static volatile int g_trapped;
static volatile uint32_t g_fault_pc_word;
static volatile int g_bad_signal;
static volatile int g_last_signal;

static void sigill_handler(int sig, siginfo_t* info, void* ucontext_v) {
  (void)info;
  ucontext_t* uc = (ucontext_t*)ucontext_v;
  g_last_signal = sig;
#if defined(__aarch64__)
  uint32_t* pc = (uint32_t*)uc->uc_mcontext.pc;
  g_fault_pc_word = *pc;
  g_trapped = (sig == SIGILL && g_fault_pc_word == 0x0000BEEFu);
  if (!g_trapped) g_bad_signal = 1;
#else
  g_bad_signal = 1;
#endif
  siglongjmp(g_jmp, 1);
}

/* Runs kernel(a,b); returns 1 if it trapped (UDF #0xBEEF), 0 with *out set
 * otherwise. Any other signal/PC sets g_bad_signal and counts as a "trap"
 * for control flow (caller must check g_bad_signal separately). */
static int run_arm_kernel(div_fn fn, int64_t a, int64_t b, int64_t* out) {
  struct sigaction sa, old_ill, old_fpe, old_segv, old_bus;
  memset(&sa, 0, sizeof(sa));
  sa.sa_sigaction = sigill_handler;
  sa.sa_flags = SA_SIGINFO;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGILL, &sa, &old_ill);
  sigaction(SIGFPE, &sa, &old_fpe);
  sigaction(SIGSEGV, &sa, &old_segv);
  sigaction(SIGBUS, &sa, &old_bus);
  g_trapped = 0;
  g_bad_signal = 0;
  int result;
  if (sigsetjmp(g_jmp, 1) == 0) {
    *out = fn(a, b);
    result = 0;
  } else {
    result = 1;
  }
  sigaction(SIGILL, &old_ill, NULL);
  sigaction(SIGFPE, &old_fpe, NULL);
  sigaction(SIGSEGV, &old_segv, NULL);
  sigaction(SIGBUS, &old_bus, NULL);
  return result;
}

static void* kernel_ptr(const KernelEntry* e) {
  return (void*)(g_code_base + (size_t)e->code_word_offset * 4);
}

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
  size_t map_len = (size_t)st.st_size;
  g_map = mmap(NULL, map_len, PROT_READ | PROT_EXEC, MAP_PRIVATE, fd, 0);
  if (g_map == MAP_FAILED) {
    perror("mmap");
    return 2;
  }
  close(fd);

  g_hdr = (Header*)g_map;
  if (memcmp(g_hdr->magic, "IDVP", 4) != 0) {
    fprintf(stderr, "bad magic\n");
    return 2;
  }
  g_pairs = (int64_t*)(g_map + g_hdr->pairs_offset);
  g_results = (X86Result*)(g_map + g_hdr->results_offset);
  g_kernels = (KernelEntry*)(g_map + g_hdr->kernel_table_offset);
  g_code_base = g_map + g_hdr->code_offset;

  uint32_t n_pairs = g_hdr->n_pairs;
  uint32_t n_kernels = g_hdr->n_kernels;

  uint64_t compared = 0, mismatch = 0, bad_signal = 0, x86_fault_only = 0;
  uint64_t mismatch_by_genre[4] = {0, 0, 0, 0};
  uint64_t before_mismatch = 0;
  uint64_t detail_printed = 0;
  const char* genre_names[4] = {"idiv", "udiv", "imod", "umod"};

  for (uint32_t ki = 0; ki < n_kernels; ki++) {
    KernelEntry* e = &g_kernels[ki];
    div_fn fn = (div_fn)kernel_ptr(e);
    uint32_t genre = e->genre;
    int is_signed_genre = (genre == GENRE_IDIV || genre == GENRE_IMOD);

    for (uint32_t pi = 0; pi < n_pairs; pi++) {
      int64_t a = g_pairs[pi * 2 + 0];
      int64_t b = g_pairs[pi * 2 + 1];
      X86Result* r = &g_results[pi * 4 + genre];

      int64_t arm_val = 0;
      int arm_trapped = run_arm_kernel(fn, a, b, &arm_val);
      if (arm_trapped && g_bad_signal) {
        bad_signal++;
        continue;
      }

      int mismatch_here = 0;
      if (r->trap) {
        if (r->trap_class == 2 && is_signed_genre) {
          /* x86 faults on INT_MIN/-1 overflow (real hardware #DE); the PS2
           * (and this port) instead renders a value. Not a mismatch as long
           * as arm64 didn't ALSO trap, and rendered the PS2-documented
           * value: INT_MIN (sign-extended) for idiv, 0 for imod. */
          if (arm_trapped) {
            mismatch_here = 1;  /* arm64 must not trap where x86 only overflows */
          } else {
            int64_t want_ps2 = (genre == GENRE_IDIV) ? (int64_t)(int32_t)0x80000000 : 0;
            if (arm_val != want_ps2) mismatch_here = 1;
            if (ki < n_kernels && e->variant == VAR_NEW) x86_fault_only++;
          }
        } else {
          /* zero-divisor or other: both sides must trap. */
          if (!arm_trapped) mismatch_here = 1;
        }
      } else {
        if (arm_trapped || arm_val != r->value) mismatch_here = 1;
      }

      if (e->variant == VAR_NEW) {
        compared++;
        if (mismatch_here) {
          mismatch++;
          mismatch_by_genre[genre]++;
          if (detail_printed < 8) {
            fprintf(stderr,
                    "NEW mismatch #%llu: genre=%s a=0x%llx b=0x%llx x86_trap=%u "
                    "x86_trap_class=%u x86_value=%lld arm_trapped=%d arm_value=%lld\n",
                    (unsigned long long)detail_printed, genre_names[genre],
                    (unsigned long long)a, (unsigned long long)b, r->trap, r->trap_class,
                    (long long)r->value, arm_trapped, (long long)arm_val);
            detail_printed++;
          }
        }
      } else {
        if (mismatch_here) before_mismatch++;
      }
    }
  }

  printf("int_div_arm64_x86_compared=%llu\n", (unsigned long long)compared);
  printf("int_div_arm64_x86_mismatch=%llu\n", (unsigned long long)mismatch);
  printf("int_div_mismatch_idiv=%llu\n", (unsigned long long)mismatch_by_genre[GENRE_IDIV]);
  printf("int_div_mismatch_udiv=%llu\n", (unsigned long long)mismatch_by_genre[GENRE_UDIV]);
  printf("int_div_mismatch_imod=%llu\n", (unsigned long long)mismatch_by_genre[GENRE_IMOD]);
  printf("int_div_mismatch_umod=%llu\n", (unsigned long long)mismatch_by_genre[GENRE_UMOD]);
  printf("int_div_x86_fault_only=%llu\n", (unsigned long long)x86_fault_only);
  printf("int_div_mismatch_incl_x86_faults=%llu\n",
        (unsigned long long)(mismatch + x86_fault_only));
  printf("int_div_before_arm64_x86_mismatch=%llu\n", (unsigned long long)before_mismatch);
  printf("int_div_arm64_bad_signal=%llu\n", (unsigned long long)bad_signal);
  printf("int_div_runner_done=1\n");
  return 0;
}
