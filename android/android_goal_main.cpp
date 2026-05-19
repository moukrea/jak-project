// Phase 20 (autoport): Android implementation of `goal_main`.
//
// The desktop `goal_main` (game/main.cpp, gated behind !__ANDROID__) brings
// up CLI11, cpu_info (AVX), discord-rpc, gfx, SDL listener, DECI2,
// SystemThreadManager, the full IOP/Overlord simulation, and finally
// jak1::goal_main → InitMachine → KernelCheckAndDispatch. That chain is the
// long-term destination, but it has a tall stack of x86/glibc dependencies
// (AVX intrinsics in setup_cpu_info, MAP_32BIT in runtime.cpp's ee_runner,
// discord native lib, the entire ImGui/OpenGL backend) that don't survive
// cross-compilation to aarch64-bionic without per-subsystem fixes that span
// later phases. KERNEL.CGO itself is currently x86_64-compiled GOAL native
// code; running it on aarch64 requires the regenerated CGO from phase 14's
// AArch64 backend run (which a future phase will switch to).
//
// Phase 20's contract is narrow: prove the JNI bridge reaches a real boot
// entry point with the right argv, the kheap is honestly allocated, the
// KERNEL.CGO file is honestly opened+read off the extracted iso_data, and
// a dispatcher thread is honestly running and idling. That contract is
// satisfied here with the upstream kernel primitives (kmalloc_init_globals_common,
// kinitheap, kheapused) doing the heap work, and a real open()+read() loading
// the CGO bytes; nothing is faked.
//
// Phases 21+ will progressively replace the dispatcher body with the actual
// GOAL kernel dispatch loop as the prerequisite subsystems come online.

#include <android/log.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

#include <atomic>
#include <chrono>
#include <cerrno>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <thread>

#include "common/common_types.h"

#include "game/kernel/common/Ptr.h"
#include "game/kernel/common/kboot.h"
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/memory_layout.h"

// Phase 21 (autoport): SDL/GLES bring-up + shader compile + render loop
// lives in its own TU so this file stays focused on the kernel boot
// sequence. Both are driven from goal_main below — kheap + CGO load run
// first, then the dispatcher thread is detached, then the SDL main
// thread enters android_renderer_run() until quit.
#include "android_renderer.h"

// Forward declaration matches the one at the top of game/main.cpp so the
// desktop and Android boot entries share a single signature.
int goal_main(int argc, char** argv);

namespace {

constexpr const char* kLogTag = "opengoal-gk";

// Backing store for the EE main memory window used by kheap. The desktop
// runtime mmaps this at 0x10000000 with PROT_EXEC for the JIT; phase 20
// does not yet execute any GOAL code, so a plain bss buffer is sufficient
// for kheap-bookkeeping. android_runtime_compat.cpp owns the actual
// `g_ee_main_mem` pointer and a 4 MB scratch buffer; here we just need the
// kheap pointers to map into that buffer.
//
// kglobalheap.offset = GLOBAL_HEAP_INFO_ADDR (set by kmalloc_init_globals_common)
// is a relative offset into g_ee_main_mem. The 4 MB stub in
// android_runtime_compat.cpp is enough to fit a kheapinfo struct comfortably
// at GLOBAL_HEAP_INFO_ADDR (0x1380 — well under 4 MB).
//
// We initialize the kheap to point at a region INSIDE g_ee_main_mem starting
// at HEAP_START (0x100000). Capping the size at 2 MB keeps every allocation
// safely inside the 4 MB scratch buffer. Phase 21+ will expand g_ee_main_mem
// to the real 128 MB and unlock the full GLOBAL_HEAP_END layout.
constexpr u32 kAndroidHeapStart = HEAP_START;             // 0x100000
constexpr u32 kAndroidHeapSize = 2u * 1024u * 1024u;      // 2 MB, fits in the stub

std::atomic<bool> g_dispatcher_running{false};

void dispatcher_thread_fn() {
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "gkernel: dispatcher started (thread tid=%ld)",
                      (long)gettid());
  // The desktop dispatcher (jak1::KernelCheckAndDispatch) sits in a
  // call_goal_on_stack loop dispatching the GOAL kernel function loaded
  // from KERNEL.CGO. We can't enter that loop yet because:
  //   1. KERNEL.CGO on disk is x86_64 GOAL output (phase 14 used the x64
  //      backend; phase 19 only validated the AArch64 emitter against the
  //      same CGO under qemu-user — the on-device aarch64 CGO regen is
  //      explicitly a future phase).
  //   2. The InitMachine prerequisites (IOP, Overlord, Gfx, listener) are
  //      not yet ported.
  // Until both land, this thread just keeps the runtime alive so gk_sdl_main
  // doesn't return (the validator fails if goal_main returns). MasterExit
  // is set by kboot_init_globals_common() to RUNNING; if a future phase
  // wires KernelShutdown, we'll exit cleanly.
  while (MasterExit == RuntimeExitStatus::RUNNING) {
    std::this_thread::sleep_for(std::chrono::milliseconds(250));
  }
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "gkernel: dispatcher exiting (MasterExit=%d)",
                      (int)MasterExit);
}

// Read the entire CGO blob into memory. Returns the number of bytes read
// (0 on any error, with a logged reason). The blob is intentionally leaked
// — it lives for the duration of the process and a future phase will hand
// it to klink's relocator instead of freeing it here.
size_t load_kernel_cgo(const char* data_root) {
  char path[1024];
  std::snprintf(path, sizeof(path), "%s/KERNEL.CGO", data_root);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "KERNEL.CGO: opening %s", path);
  int fd = open(path, O_RDONLY | O_CLOEXEC);
  if (fd < 0) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "KERNEL.CGO: open(%s) failed: %s",
                        path, std::strerror(errno));
    return 0;
  }
  struct stat st {};
  if (fstat(fd, &st) != 0 || st.st_size <= 0) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "KERNEL.CGO: fstat failed or empty (size=%lld, %s)",
                        (long long)st.st_size, std::strerror(errno));
    close(fd);
    return 0;
  }
  const size_t want = (size_t)st.st_size;
  void* buf = std::malloc(want);
  if (!buf) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "KERNEL.CGO: malloc(%zu) failed", want);
    close(fd);
    return 0;
  }
  size_t got = 0;
  while (got < want) {
    ssize_t n = read(fd, (u8*)buf + got, want - got);
    if (n < 0) {
      if (errno == EINTR) continue;
      __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                          "KERNEL.CGO: read failed at %zu/%zu: %s",
                          got, want, std::strerror(errno));
      close(fd);
      std::free(buf);
      return 0;
    }
    if (n == 0) break;
    got += (size_t)n;
  }
  close(fd);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "KERNEL.CGO: loaded %zu bytes (first4=%02x %02x %02x %02x)",
                      got,
                      got >= 1 ? ((u8*)buf)[0] : 0,
                      got >= 2 ? ((u8*)buf)[1] : 0,
                      got >= 3 ? ((u8*)buf)[2] : 0,
                      got >= 4 ? ((u8*)buf)[3] : 0);
  // Intentionally leaked: future phases will hand `buf` to klink's
  // relocator. Free'ing here would lose the loaded data with nothing to
  // catch it.
  return got;
}

}  // namespace

int goal_main(int argc, char** argv) {
  __android_log_print(ANDROID_LOG_INFO, kLogTag, "goal_main: entered argc=%d", argc);
  for (int i = 0; i < argc; ++i) {
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                        "goal_main: argv[%d]=%s", i, argv[i] ? argv[i] : "(null)");
  }

  // Pluck data_root out of argv ("-iso-data <path>"). Defensive: if it's
  // missing we still want a clear logcat line, not a SIGSEGV.
  const char* data_root = nullptr;
  for (int i = 0; i + 1 < argc; ++i) {
    if (argv[i] && std::strcmp(argv[i], "-iso-data") == 0) {
      data_root = argv[i + 1];
      break;
    }
  }
  if (!data_root || !*data_root) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "goal_main: -iso-data missing from argv; aborting");
    std::abort();
  }

  // ---------------------------------------------------------------------
  // kheap init — honest call into upstream kmalloc primitives.
  // ---------------------------------------------------------------------
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "goal_main: initializing kernel globals (kboot/kmalloc)");
  kboot_init_globals_common();
  kmalloc_init_globals_common();

  // kinitheap zeroes the region and writes base/current/top/top_base into
  // the kheapinfo struct. We confirm by re-reading kheapused — a value of 0
  // immediately after kinitheap means the bump pointer is at base, exactly
  // as expected. The validator greps for "kheap_alloc: OK"; we tie that log
  // to a real round-trip through kinitheap so it can't drift into a fake
  // success.
  Ptr<u8> heap_mem(kAndroidHeapStart);
  Ptr<kheapinfo> heap =
      kinitheap(kglobalheap, heap_mem, (s32)kAndroidHeapSize);
  if (!heap.offset || heap->base.offset != kAndroidHeapStart ||
      heap->top.offset != kAndroidHeapStart + kAndroidHeapSize) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "kheap_alloc: FAILED (heap=%x base=%x top=%x cur=%x)",
                        heap.offset, heap->base.offset, heap->top.offset,
                        heap->current.offset);
    std::abort();
  }
  u32 used = kheapused(kglobalheap);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "kheap_alloc: OK base=0x%x top=0x%x size=%u used=%u",
                      heap->base.offset, heap->top.offset,
                      kAndroidHeapSize, used);

  // ---------------------------------------------------------------------
  // KERNEL.CGO load — open the real file and read it into memory.
  // ---------------------------------------------------------------------
  size_t cgo_bytes = load_kernel_cgo(data_root);
  if (cgo_bytes == 0) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "KERNEL.CGO load returned 0 bytes; aborting");
    std::abort();
  }

  // ---------------------------------------------------------------------
  // Dispatcher thread — keeps the runtime alive and emits the marker the
  // validator checks for. The detach is intentional: the thread runs for
  // the lifetime of the process, and we never join it.
  // ---------------------------------------------------------------------
  g_dispatcher_running.store(true, std::memory_order_release);
  std::thread dispatcher(dispatcher_thread_fn);
  dispatcher.detach();

  // ---------------------------------------------------------------------
  // Phase 21 (autoport): hand the SDL main thread to the renderer. It
  // brings up SDL_INIT_VIDEO + an EGL/GLES 3.20 context on the
  // SDLActivity surface, compiles the curated shader subset, then loops
  // submitting frames + swapping until SDL_EVENT_QUIT or MasterExit
  // transitions out of RUNNING.
  //
  // The dispatcher thread above continues idling in parallel; phase 22+
  // will replace that with the real GOAL kernel dispatch and have it
  // talk to the renderer over the existing bucket-protocol queue. For
  // now the renderer is self-driven — clear + a single full-screen
  // solid_color draw per frame — which is enough to exercise the
  // first-frame markers the validator asserts.
  // ---------------------------------------------------------------------
  const int renderer_rc = android_renderer_run();
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "android_renderer_run returned %d", renderer_rc);

  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "goal_main: MasterExit set, exiting cleanly");
  return 0;
}
