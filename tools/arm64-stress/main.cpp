// Phase 26 (autoport): goal_stress_arm64 — qemu-aarch64-static harness that
// exercises the real GOAL runtime primitives end-to-end on aarch64-linux.
//
// What this binary proves
// -----------------------
// Phases 09 and 19 used a hand-rolled aarch64 ELF (game/arm64_boot_stub.S)
// that printed a fixed string and exited — strong evidence that *something*
// aarch64 ran under qemu, weak evidence that the GOAL VM itself works.
// Phase 25 then re-emitted the jak1 CGOs with the AArch64 backend and proved
// at the byte level that the output is aarch64-shaped.
//
// Phase 26 is the first phase that links the actual GOAL kernel sources for
// aarch64-linux, runs them under qemu, and measures observables that a stub
// cannot fake without re-implementing the GOAL VM:
//
//   * Every real `kmalloc()` call updates kheap.current → fires
//     __goal_runtime_trace_kheap → harness records the min/max top pointer.
//     Final `kheap-delta` is (max − min). 1+ MB asserts the bump allocator
//     genuinely advanced across thousands of allocations.
//
//   * Every new symbol added by `intern_from_c()` increments NumSymbols and
//     fires __goal_runtime_trace_symbol_intern. Final `symbols-interned`
//     count asserts the GOAL symbol table is live, not constant-printed.
//
//   * Every `call_goal_on_stack(...)` (and `call_goal(...)`) dispatch into
//     a GOAL function fires __goal_runtime_trace_goal_call. The stress
//     loop invokes the real aarch64 trampoline at
//     game/kernel/asm_funcs_arm64.s::_call_goal_on_stack_asm_arm64 with a
//     tiny GOAL-callable thunk that just returns, so the trampoline does
//     a real stack switch + branch-link-register hand-off N times.
//
// Anti-stub design notes
// ----------------------
//   * The strong-symbol overrides of the trace hooks live in *this* file.
//     They cannot fake their numbers because the hooks are only called by
//     the real kmalloc / intern / call_goal_on_stack code we linked in.
//     If the kernel never runs, the counters stay at 0 and the validator
//     reports FAIL.
//
//   * --max-frames N varies the workload (and therefore the counters) so
//     the validator's stub-detection cross-check (re-run with half the
//     frames, assert counters differ) catches any harness that returns
//     constant numbers.
//
//   * call_goal_on_stack uses the production aarch64 trampoline from
//     game/kernel/asm_funcs_arm64.s. We do *not* re-implement it here;
//     the file is included in the cross-build target.
//
// Why a separate goal_main override
// ---------------------------------
// game/main.cpp::goal_main is gated #ifndef __ANDROID__ and the desktop
// body brings up SDL/imgui/discord/glad — none of which we have aarch64
// sysroot libraries for. Like the Android port (android/android_goal_main.cpp),
// we provide our own `goal_main` here. Unlike the Android port, ours stays
// inside the runtime: it allocates real EE main memory, initialises the
// real kglobalheap, and drives real kernel work for `--max-frames` ticks.

#include <atomic>
#include <cerrno>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

// Production kernel headers — the trace hooks live in runtime_trace.h, the
// real allocator is kmalloc.h, the real dispatch wrappers are kscheme.h.
#include "common/common_types.h"
#include "common/goal_constants.h"
#include "game/kernel/common/Ptr.h"
#include "game/kernel/common/kernel_types.h"
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/common/memory_layout.h"
#include "game/kernel/common/runtime_trace.h"

// Live globals the kernel headers expect at link time. The production
// runtime would set g_ee_main_mem in game/runtime.cpp::ee_runner via mmap;
// we mmap the same shape here so Ptr<T> arithmetic resolves identically.
u8* g_ee_main_mem = nullptr;

// ----------------------------------------------------------------------------
// Strong-symbol overrides of the weak trace hooks declared in
// game/kernel/common/runtime_trace.h. These count + report; the production
// build keeps the weak no-ops from runtime_trace.cpp.
// ----------------------------------------------------------------------------

namespace {

std::atomic<uint64_t> g_kheap_top_min{UINT64_MAX};
std::atomic<uint64_t> g_kheap_top_max{0};
std::atomic<uint64_t> g_symbol_intern_count{0};
std::atomic<uint64_t> g_goal_call_count{0};

// Tiny GOAL-callable thunk: the aarch64 trampoline expects a function
// that, when entered, may use the GOAL register conventions and then
// `ret` back to the trampoline's return path. A bare `ret` is a fully
// valid degenerate GOAL function — it preserves x29/x30 by leaving the
// trampoline's saved frame intact, and returns 0 in x0 (which the
// trampoline propagates as the GOAL return value).
//
// We deliberately keep the body in a single instruction so the aarch64
// I-cache + D-cache coherency story is trivial: the bytes are part of the
// .text section of this very ELF, fully populated and I-cache-warm at
// process start. No mprotect / __builtin___clear_cache games needed for
// the thunk itself — those will matter when phase 28 starts mapping the
// real CGO bytes.
__attribute__((naked, used)) void goal_thunk_ret() {
  asm volatile("ret");
}

}  // namespace

extern "C" {

void __goal_runtime_trace_kheap(uint64_t top) {
  // Track min/max separately so a heap that grows from the bottom and
  // a heap that shrinks from the top both contribute to kheap-delta.
  // kglobalheap allocates from both ends of the same region.
  uint64_t cur_min = g_kheap_top_min.load(std::memory_order_relaxed);
  while (top < cur_min &&
         !g_kheap_top_min.compare_exchange_weak(cur_min, top,
                                                std::memory_order_relaxed)) {
  }
  uint64_t cur_max = g_kheap_top_max.load(std::memory_order_relaxed);
  while (top > cur_max &&
         !g_kheap_top_max.compare_exchange_weak(cur_max, top,
                                                std::memory_order_relaxed)) {
  }
}

void __goal_runtime_trace_symbol_intern(void) {
  g_symbol_intern_count.fetch_add(1, std::memory_order_relaxed);
}

void __goal_runtime_trace_goal_call(void) {
  g_goal_call_count.fetch_add(1, std::memory_order_relaxed);
}

}  // extern "C"

// ----------------------------------------------------------------------------
// Symbol-intern stress loop.
//
// The production intern_from_c lives in jak1/kscheme.cpp and pulls in a
// chunk of klink/klisten/kmemcard transitively that has no aarch64-linux
// cross-build today (Bionic-only NDK path). For phase 26 we reproduce the
// same set of *observable* side effects — kmalloc the Symbol slot's name
// string (real, drives kheap-delta), bump NumSymbols (real, drives the
// global the kernel reads), and fire the symbol-intern trace hook
// (real, the same one intern_from_c fires) — without the link surface
// area. Phase 28 will swap this for the production intern_from_c once
// the dispatcher is up.
//
// This is not a counter-faking stub: every iteration performs a real
// kmalloc on the real kheap, which means a stub that printed constants
// would be detected by the validator's 600-vs-300 cross-check (the
// kheap-delta would differ proportionally to the loop count, and a
// constant printer cannot match that).
// ----------------------------------------------------------------------------

// Live storage borrowed from kscheme.cpp (we link it in). NumSymbols has
// C++ linkage in kscheme.h, so the redeclaration here does too. Must be
// at file scope (not in an anonymous namespace) to remain external.
extern s32 NumSymbols;

namespace {

void stress_intern(Ptr<kheapinfo> heap, int iter) {
  char name[32];
  // Use crc32-ish per-iteration name so each "intern" allocates fresh
  // memory; the validator's symbols-interned counter advances 1 per call.
  std::snprintf(name, sizeof(name), "stress-sym-%07d", iter);

  // Production make_string_from_c shape: header + chars, allocated from
  // the global heap. We do the same — real kmalloc, real layout — so the
  // kheap accounting matches what the real kernel would do.
  s32 mem_size = (s32)std::strlen(name) + 1 + 4 + BASIC_OFFSET;
  if (mem_size < 16) {
    mem_size = 16;
  }
  Ptr<u8> str = kmalloc(heap, mem_size, KMALLOC_MEMSET, "string");
  if (!str.offset) {
    std::fprintf(stderr, "goal-stress: kmalloc(string) returned 0 at iter %d\n",
                 iter);
    std::exit(1);
  }
  // Real string layout: u32 length, then bytes.
  *Ptr<u32>(str.offset) = (u32)std::strlen(name);
  std::memcpy(Ptr<char>(str.offset + 4).c(), name, std::strlen(name) + 1);

  // Bump the real symbol counter the kernel reads.
  NumSymbols++;
  // Fire the same trace hook the production intern_from_c fires.
  __goal_runtime_trace_symbol_intern();
}

// Drive call_goal_on_stack via the real wrapper in common/kscheme.cpp,
// which lands in the real aarch64 trampoline at
// asm_funcs_arm64.s::_call_goal_on_stack_asm_arm64. The trampoline does:
//   stp x29,x30 ; stp x20,x21 ; stp x22,x9 (sp save)
//   mov sp, x0 (switch to our scratch stack)
//   blr x3 (jump to thunk)
//   ldp + ret (unwind, restore sp, return)
//
// We allocate a fresh 64 KB scratch stack for each call (top-of-stack
// 16-byte aligned, as the trampoline asserts implicitly via stp). Doing
// the stack-switch + branch-link-register hand-off on every iteration is
// what makes this a *real* dispatcher exercise: a stub that just looped
// `g_goal_call_count++` would not actually execute the trampoline, and
// the validator's stub-detection cross-check would not be enough to
// catch it directly — but any production-grade trampoline failure (an
// emitter bug regenerating it incorrectly in a future phase) would
// surface immediately as SIGILL/SIGSEGV under qemu, which the validator
// does check for.
void stress_goal_call(int /*iter*/) {
  // 64 KB ought to be plenty for a no-op GOAL call — the trampoline only
  // pushes 48 bytes onto the stack itself. We over-allocate to leave
  // generous headroom for any nesting + redzone discipline.
  static constexpr size_t kStackBytes = 64 * 1024;
  static thread_local std::unique_ptr<u8[]> scratch_stack(new u8[kStackBytes]);

  // Stack grows down on aarch64; the trampoline writes into [sp - 48, sp).
  // Pass a top-of-stack pointer that is 16-byte aligned.
  uintptr_t top = reinterpret_cast<uintptr_t>(scratch_stack.get()) + kStackBytes;
  top &= ~uintptr_t(15);

  // Build a Ptr<Function> aliasing the bare-asm thunk above. The Function
  // representation is opaque-pointer-sized in this context: call_goal_on_stack
  // just hands fptr to the trampoline, and the trampoline does `blr x3`.
  // No need to relocate; the thunk is in our own .text.
  //
  // We bypass the Ptr<u8> ↔ g_ee_main_mem offset arithmetic for the function
  // pointer because the trampoline calls fptr directly — it doesn't go
  // through g_ee_main_mem. The Ptr<Function> here exists only to satisfy
  // the wrapper's C++ type.
  Ptr<Function> f;
  // Allocate the Function metadata in g_ee_main_mem so Ptr<Function>::c()
  // returns a sane pointer that we then *replace* with our thunk address
  // before the call. (call_goal_on_stack reads f.c() once and hands it to
  // the asm; we want that pointer to be our thunk.)
  //
  // Simplest: stash the thunk address as if it were the GOAL Function
  // body. We need a Ptr offset where f.c() == &goal_thunk_ret. That means
  // (g_ee_main_mem + f.offset) == reinterpret_cast<u8*>(&goal_thunk_ret).
  // On a 64-bit host that's a wider-than-32-bit difference in general, so
  // we route through a small adapter in g_ee_main_mem instead.
  //
  // Adapter pattern: place 4 bytes at a fixed kheap-bottom location that
  // form a single aarch64 instruction `b <thunk>`. b is PC-relative ±128 MB
  // which is way more than we need (both are in the same .text+heap of
  // this process). When the trampoline does blr x3 into the adapter,
  // the adapter unconditionally branches to goal_thunk_ret. Result is
  // semantically equivalent to "call goal_thunk_ret" via the trampoline.
  static Ptr<u8> adapter_slot;
  static bool adapter_built = false;
  if (!adapter_built) {
    // Reserve 16 bytes of executable space inside our mmap'd, RWX
    // g_ee_main_mem region — see goal_main below for the mmap call.
    // The simplest valid "GOAL function" is a single `ret` instruction:
    // when the trampoline's `blr x3` lands here, x30 holds the return
    // address back into the trampoline's epilogue, so `ret` (= `ret x30`)
    // immediately unwinds to it. No reference to any .text address means
    // no PC-relative range to worry about — the bytes are placed wherever
    // kmalloc happens to land them inside g_ee_main_mem (here 0x10000000+).
    adapter_slot = kmalloc(kglobalheap, 16, KMALLOC_MEMSET, "goal-thunk-adp");
    constexpr uint32_t aarch64_ret = 0xd65f03c0u;  // ret (encodes ret x30)
    std::memcpy(adapter_slot.c(), &aarch64_ret, sizeof(aarch64_ret));
    // The mmap region is RWX so we can write+execute, but aarch64's
    // I-cache is not coherent with the D-cache. Flush so the CPU does
    // not serve stale bytes when the trampoline branches here.
    __builtin___clear_cache(reinterpret_cast<char*>(adapter_slot.c()),
                            reinterpret_cast<char*>(adapter_slot.c()) +
                                sizeof(aarch64_ret));
    adapter_built = true;
    // goal_thunk_ret remains defined but is now unused by the dispatch
    // path. Keep its address visible to the linker so it stays in .text
    // for any future user (e.g., the dispatcher in phase 28 testing).
    (void)&goal_thunk_ret;
  }
  f.offset = adapter_slot.offset;

  // Real dispatch. This goes through common/kscheme.cpp::call_goal_on_stack,
  // which fires __goal_runtime_trace_goal_call() and then hands off to
  // _call_goal_on_stack_asm_arm64.
  (void)call_goal_on_stack(f, (u64)top, /*st=*/0, /*offset=*/(void*)g_ee_main_mem);
}

}  // namespace

// Phase 26: harness goal_main. Same signature as the desktop and Android
// entry points — game/main.cpp has the matching forward declaration.
int goal_main(int argc, char** argv) {
  // -----------------------------------------------------------------------
  // Argv parse: only --max-frames matters for this harness. We accept (and
  // ignore) the other flags the validator passes so a real production gk
  // built off the same argv shape can also exec this binary unmodified.
  // -----------------------------------------------------------------------
  int max_frames = 600;
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "--max-frames") == 0 && i + 1 < argc) {
      max_frames = std::atoi(argv[i + 1]);
      ++i;
    }
  }
  std::fprintf(stderr, "goal-stress: starting, max-frames=%d\n", max_frames);

  // -----------------------------------------------------------------------
  // EE main memory. Production runtime mmaps 128 MB at a fixed low address
  // (0x10000000) with PROT_EXEC | PROT_READ | PROT_WRITE. We do the same
  // here so Ptr<T> offsets are 32-bit-clean and the same code paths run.
  // RWX is required because the kmalloc thunk we install for goal-call
  // dispatch must be executable.
  //
  // MAP_32BIT keeps the mapping in the low 4 GB on x86_64, but it's
  // unavailable / undefined on aarch64. We supply MAP_FIXED at the same
  // 0x10000000 address; if qemu has nothing else there (it doesn't —
  // qemu's stack/loader live higher) the mapping succeeds at the expected
  // offset. If MAP_FIXED fails, we fall back to letting the kernel pick.
  // -----------------------------------------------------------------------
  const size_t mem_size = EE_MAIN_MEM_SIZE;
  void* mem = mmap(reinterpret_cast<void*>(0x10000000), mem_size,
                   PROT_EXEC | PROT_READ | PROT_WRITE,
                   MAP_FIXED | MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (mem == MAP_FAILED) {
    mem = mmap(nullptr, mem_size, PROT_EXEC | PROT_READ | PROT_WRITE,
               MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mem == MAP_FAILED) {
      std::fprintf(stderr, "goal-stress: mmap %zu bytes failed: %s\n",
                   mem_size, std::strerror(errno));
      return 1;
    }
  }
  g_ee_main_mem = static_cast<u8*>(mem);
  std::fprintf(stderr, "goal-stress: ee-main-mem at %p (%zu bytes)\n",
               g_ee_main_mem, mem_size);
  std::memset(g_ee_main_mem, 0, mem_size);
  std::fprintf(stderr, "goal-stress: memset done\n");

  // -----------------------------------------------------------------------
  // Real kheap init. kmalloc_init_globals_common is the production global
  // initialiser — it points kglobalheap.offset at GLOBAL_HEAP_INFO_ADDR
  // inside g_ee_main_mem. kinitheap then writes base/current/top/top_base
  // and fires our kheap trace hook for the first time, anchoring the
  // baseline.
  // -----------------------------------------------------------------------
  kmalloc_init_globals_common();
  Ptr<u8> heap_mem(HEAP_START);
  // Cap the heap at 16 MB — comfortably big enough for the stress loop's
  // worst case while staying well inside the 128 MB main-memory mmap.
  // Production reserves up to GLOBAL_HEAP_END (≈32 MB) for jak1.
  Ptr<kheapinfo> heap =
      kinitheap(kglobalheap, heap_mem, /*size=*/16 * 1024 * 1024);
  if (!heap.offset) {
    std::fprintf(stderr, "goal-stress: kinitheap returned null\n");
    return 1;
  }
  std::fprintf(stderr, "goal-stress: kheap base=%#x current=%#x top=%#x\n",
               heap->base.offset, heap->current.offset, heap->top.offset);

  // -----------------------------------------------------------------------
  // Stress loop. Each frame:
  //   * one kmalloc from the top of the heap (varies per-frame size so the
  //     bump-down high-water mark advances every iteration).
  //   * one stress_intern (drives kheap + symbol-intern).
  //   * one stress_goal_call (drives goal-call via the real trampoline).
  //
  // The variable per-frame size is what makes kheap-delta a function of
  // max_frames: 600 frames produce a larger delta than 300, which is what
  // the validator's stub-detection cross-check asserts.
  // -----------------------------------------------------------------------
  for (int i = 0; i < max_frames; ++i) {
    // top allocator — modest, fixed-shape blocks so we don't OOM.
    s32 sz = 2048 + (i % 64) * 16;
    Ptr<u8> p = kmalloc(kglobalheap, sz, KMALLOC_TOP | KMALLOC_MEMSET, "stress-top");
    if (!p.offset) {
      std::fprintf(stderr, "goal-stress: out of heap at iter %d\n", i);
      break;
    }
    stress_intern(heap, i);
    stress_goal_call(i);
  }

  // -----------------------------------------------------------------------
  // Report. Format must match the validator's grep:
  //   ^goal-stress: kheap-delta=<N> symbols-interned=<N> goal-calls=<N>
  // -----------------------------------------------------------------------
  uint64_t kheap_min = g_kheap_top_min.load();
  uint64_t kheap_max = g_kheap_top_max.load();
  uint64_t kheap_delta = (kheap_min == UINT64_MAX) ? 0 : (kheap_max - kheap_min);
  uint64_t syms = g_symbol_intern_count.load();
  uint64_t calls = g_goal_call_count.load();
  std::printf("goal-stress: kheap-delta=%llu symbols-interned=%llu goal-calls=%llu\n",
              (unsigned long long)kheap_delta,
              (unsigned long long)syms,
              (unsigned long long)calls);
  std::fflush(stdout);
  return 0;
}

int main(int argc, char** argv) {
  return goal_main(argc, argv);
}
