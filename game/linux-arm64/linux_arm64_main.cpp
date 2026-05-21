// Phase C2 (autoport, bucket C): boot driver that exercises the upstream
// OpenGOAL kernel-init chain on aarch64-linux under qemu-aarch64-static.
//
// Replaces the C1 banner-and-exit. Calls the same `*_init_globals*()`
// chain `game/runtime.cpp::ee_runner` calls on desktop, then
// `jak1::InitHeapAndSymbol()` with `MasterUseKernel=false` so the
// kernel-load short-circuit is taken — every step except the actual
// KERNEL.CGO load (which needs the IOP overlord, C3's job) runs.
//
// Milestones the driver hits, in order:
//   - g_ee_main_mem mmapped at EE_MAIN_MEM_MAP (0x2123000000) with
//     PROT_EXEC|R|W — same shape as desktop's ee_runner.
//   - All upstream init_globals_*() called in the runtime.cpp order.
//   - kinitheap(kglobalheap, HEAP_START, GLOBAL_HEAP_END-HEAP_START)
//     succeeds.
//   - init_output() succeeds (allocates print-buf out of the global
//     heap since MasterDebug=false).
//   - jak1::InitHeapAndSymbol() returns 0, after emitting upstream
//     `Initialized GOAL heap in <ms>` (kscheme.cpp:1751) which is the
//     ground-truth C2 milestone.
//   - Driver emits `linux-arm64: C2 kernel-init complete` and
//     `linux-arm64: C2 NumSymbols=<N>` for the validator.
//   - exit(0).
//
// What the driver does NOT do (still C3's job):
//   - Spawn IOP / EE / DECI2 threads.
//   - Load KERNEL.CGO / GAME.CGO via the overlord.
//   - Initialise the renderer / sound / discord.
//   - Run any GOAL bytecode (call_goal_on_stack).
//
// Anti-cheat reminders for future modifications:
//   * Do NOT emit upstream log strings from this driver. The
//     validator (check 18) greps the boot log for the real
//     kscheme.cpp marker as proof real upstream code ran; forging
//     it here would defeat the check. Check 24 enforces this
//     specifically for this file.
//   * Do NOT add weak symbol declarations that other code might
//     satisfy with a stub later — that was the phase-28 cheat.
//     Missing symbols belong in linux_arm64_runtime_compat.cpp with
//     real, named, honest bodies.
//   * Do NOT add synthetic boot-sequence markers (the
//     supervisor's REDESIGN §9-Delete list calls those out by
//     name); fabricated state names defeat the trace-diff oracle.

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>

#include <sys/mman.h>

#include "common/common_types.h"
#include "common/goal_constants.h"
#include "common/log/log.h"
#include "common/versions/revision.h"
#include "common/versions/versions.h"

#include "common/cross_os_debug/xdbg.h"

#include "game/common/game_common_types.h"
#include "game/kernel/common/fileio.h"
#include "game/kernel/common/kboot.h"
#include "game/kernel/common/kdgo.h"
#include "game/kernel/common/kdsnetm.h"
#include "game/kernel/common/klink.h"
#include "game/kernel/common/klisten.h"
#include "game/kernel/common/kmachine.h"
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/kmemcard.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/common/memory_layout.h"
#include "game/kernel/jak1/kboot.h"
#include "game/kernel/jak1/kdgo.h"
#include "game/kernel/jak1/klisten.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/runtime.h"

namespace {
constexpr const char* kPhaseTag = "C2";
constexpr const char* kBuildTag = BUILT_TAG;
constexpr const char* kBuildSha = BUILT_SHA;

void print_banner(std::FILE* out) {
  std::fprintf(out,
               "OpenGOAL gk (linux-arm64 cross-build, phase %s)\n"
               "  built-tag: %s\n"
               "  built-sha: %s\n",
               kPhaseTag, (kBuildTag && *kBuildTag) ? kBuildTag : "(none)",
               (kBuildSha && *kBuildSha) ? kBuildSha : "(unknown)");
}

// Map g_ee_main_mem at the canonical EE_MAIN_MEM_MAP address with the
// same PROT_EXEC|R|W shape ee_runner uses on desktop. The C1 compat
// layer no longer pre-mmaps in a static initializer (it would leak
// 128 MB if both ran); main is the single owner.
bool remap_ee_main_mem() {
  void* p = mmap((void*)EE_MAIN_MEM_MAP, EE_MAIN_MEM_SIZE,
                 PROT_EXEC | PROT_READ | PROT_WRITE,
                 MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
  if (p == MAP_FAILED) {
    // qemu-user or sysctl may refuse the high hint; fall back to a
    // kernel-picked address. The kheap math is offset-based so any
    // base works.
    p = mmap(nullptr, EE_MAIN_MEM_SIZE, PROT_EXEC | PROT_READ | PROT_WRITE,
             MAP_ANONYMOUS | MAP_PRIVATE, -1, 0);
  }
  if (p == MAP_FAILED) {
    std::fprintf(stderr, "linux-arm64: mmap(EE_MAIN_MEM_SIZE=%d) failed: %s\n",
                 EE_MAIN_MEM_SIZE, std::strerror(errno));
    return false;
  }
  std::memset(p, 0, EE_MAIN_MEM_SIZE);
  g_ee_main_mem = (u8*)p;
  return true;
}

// Drive the upstream init_globals_*() chain in the same order
// runtime.cpp::ee_runner uses. The chain is jak1-only (jak2/jak3 init
// calls are intentionally skipped — their static state would consume
// memory without value here).
void init_all_globals() {
  fileio_init_globals();
  jak1::kboot_init_globals();
  kboot_init_globals_common();
  kdgo_init_globals();
  jak1::kdgo_init_globals();
  kdsnetm_init_globals_common();
  klink_init_globals();
  kmachine_init_globals_common();   // compat-layer stub; no-op
  jak1::kscheme_init_globals();
  kscheme_init_globals_common();
  kmalloc_init_globals_common();
  klisten_init_globals();
  jak1::klisten_init_globals();
  kmemcard_init_globals();
  kprint_init_globals_common();
  xdbg::allow_debugging();
}

int boot_kernel_init() {
  if (!remap_ee_main_mem()) {
    return 10;
  }
  std::fprintf(stdout,
               "linux-arm64: g_ee_main_mem mapped at %p (size 0x%x)\n",
               (void*)g_ee_main_mem, EE_MAIN_MEM_SIZE);

  init_all_globals();

  // The honest no-IOP, no-DGO boot path: no debug heap, no GOAL kernel
  // dispatch, no DGO load inside InitHeapAndSymbol. kboot_init_globals_common
  // sets these to 1; we override after the chain has run.
  MasterUseKernel = 0;
  MasterDebug = 0;
  DiskBoot = 0;
  SplashScreen = 0;
  DebugSegment = 0;

  // Mirror InitMachine's heap layout, minus the debug heap. Same
  // constants the desktop kernel uses (memory_layout.h).
  u32 global_heap_size = GLOBAL_HEAP_END - HEAP_START;
  std::fprintf(stdout,
               "linux-arm64: kinitheap(kglobalheap, %#x, %#x)\n",
               (unsigned)HEAP_START, (unsigned)global_heap_size);
  kinitheap(kglobalheap, Ptr<u8>(HEAP_START), global_heap_size);
  // MasterDebug=false, so leave kdebugheap.offset=0 (the upstream
  // "no debug heap" sentinel). kheapused/etc guard with `if
  // (kdebugheap.offset) ...` so this is safe.
  kdebugheap.offset = 0;

  init_output();

  // InitHeapAndSymbol() is the milestone. With MasterUseKernel=false,
  // the upstream code path is:
  //   - kmalloc the symbol table on the global heap.
  //   - set s7, SymbolTable2, LastSymbol, NumSymbols.
  //   - alloc_and_init_type for the type-of-type / symbol / string /
  //     function fundamentals.
  //   - set_fixed_symbol for booleans / nothing / zero-func / etc.
  //   - intern hundreds of types via set_fixed_type / make_function_*.
  //   - emit lg::info("Initialized GOAL heap in {:.2} ms", ...).
  //   - SKIP the `if (MasterUseKernel) { load_and_link_dgo_from_c... }`
  //     block — that's C3.
  //   - intern "*deci-count*".
  //   - call InitListener() — interns 4 symbols + prepends "kernel".
  //   - call jak1::InitMachineScheme() — compat-layer no-op.
  //   - make_function_symbol_from_c("test-function", ...).
  //   - return 0.
  s32 hs_status = jak1::InitHeapAndSymbol();
  if (hs_status < 0) {
    std::fprintf(stderr, "linux-arm64: InitHeapAndSymbol failed: %d\n",
                 hs_status);
    return 20;
  }

  // Post-init proof-of-life: NumSymbols is a real upstream global
  // (`game/kernel/common/kscheme.cpp`). The validator's check 25 parses
  // the NumSymbols= line; a low value means the symbol-table setup
  // silently no-op'd. Healthy value with MasterUseKernel=false is in
  // the low hundreds.
  std::fprintf(stdout,
               "linux-arm64: C2 kernel-init complete (NumSymbols=%u)\n"
               "linux-arm64: C2 NumSymbols=%u\n",
               (unsigned)NumSymbols, (unsigned)NumSymbols);

  return 0;
}
}  // namespace

int goal_main(int argc, char** argv) {
  g_main_thread_id = std::this_thread::get_id();

  bool show_version = false;
  bool show_banner_only = false;
  for (int i = 1; i < argc; ++i) {
    if (std::strcmp(argv[i], "--version") == 0 ||
        std::strcmp(argv[i], "-v") == 0) {
      show_version = true;
    } else if (std::strcmp(argv[i], "--banner-only") == 0) {
      show_banner_only = true;
    }
  }

  print_banner(stdout);

  if (show_version || show_banner_only) {
    return 0;
  }

  return boot_kernel_init();
}

int main(int argc, char** argv) {
  return goal_main(argc, argv);
}
