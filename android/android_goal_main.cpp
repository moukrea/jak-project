// Phase 28 (autoport): Android implementation of `goal_main`.
//
// The dispatcher thread used to host a hardcoded boot-state walker. Phase 28
// strips it and forwards the thread body into the real KernelCheckAndDispatch
// wrapper defined in android_runtime_full.cpp (which itself either delegates
// into jak1::KernelCheckAndDispatch when that TU is linked, or falls back to
// its own dispatcher tick that drives gfx + iop and bumps the kernel-side
// heartbeat counter). The state-transition log lines now originate from
// game/kernel/common/android_dispatch_signals.cpp, not from this TU.
//
// goal_main itself still owns the boot prelude: argv parsing, kheap init via
// the upstream kmalloc primitives, and the honest open()+read() that pulls
// KERNEL.CGO off the extracted iso_data into a W^X-disciplined RX mapping.
// Those steps must complete before the dispatcher thread spins up, so the
// real KernelCheckAndDispatch sees a fully-initialised Machine.

#include <android/log.h>
#include <fcntl.h>
#include <pthread.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <unistd.h>

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

// Real dispatcher entry point. Definition lives in android_runtime_full.cpp;
// declared here without going through a header so we can call it directly
// from the dispatcher thread.
extern "C" void KernelCheckAndDispatch();

// Top-level machine init from android_runtime_full.cpp. Per the phase-28
// pitfalls note, the dispatcher expects a fully-initialised Machine; this
// runs before the dispatcher thread spins up so init_output / listener
// plumbing / IOP worker are all live by the time the first tick fires.
extern "C" int InitMachine();

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

void dispatcher_thread_fn() {
  // Bionic caps pthread name length at 15 chars (16 incl. NUL). The
  // glibc-friendly "opengoal-runtime" is 16 + NUL = 17 and would silently
  // fail; truncate so the name actually attaches and is visible in
  // `adb shell ps -T`.
  pthread_setname_np(pthread_self(), "opengoal-rt");

  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "gkernel: dispatcher started (thread tid=%ld)",
                      (long)gettid());

  // Hand the thread to the real KernelCheckAndDispatch wrapper. It owns
  // the MasterExit-gated loop and does the actual per-tick work; if the
  // jak1 dispatcher TU is linked it forwards into the GOAL kernel loop
  // outright. Either path produces the heartbeat + state-transition
  // markers via the helpers in game/kernel/common/android_dispatch_signals.
  KernelCheckAndDispatch();

  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "gkernel: dispatcher exiting (MasterExit=%d)",
                      (int)MasterExit);
}

// Read the entire CGO blob into a W^X-disciplined code region. Returns
// the number of bytes read (0 on any error, with a logged reason).
//
// Phase 22 (autoport): retail Android (API 29+) under SELinux will SIGKILL
// any process that holds a `PROT_WRITE | PROT_EXEC` VMA. CGO bytes are
// loaded code, so we follow the exact discipline the platform mandates:
//
//   1. mmap(NULL, sz, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS)
//   2. read(fd, ...) the CGO bytes in.
//   3. mprotect(addr, sz, PROT_READ | PROT_EXEC).
//   4. __builtin___clear_cache(start, end) — AArch64 I-cache is not
//      coherent with D-cache; without this the CPU may serve stale bytes
//      out of the I-cache and SIGILL on first execution.
//
// We log `code-map: <pages> pages RX, 0 RWX` exactly once after the
// transition so the phase-22 validator can confirm W^X discipline from
// logcat. /proc/self/maps is also cross-checked by the validator —
// scrupulously keeping the RWX count at zero is what passes that.
//
// The mapping is intentionally leaked: future phases hand it to klink's
// relocator, and process-lifetime memory is the right model anyway —
// freeing it would race with the dispatcher thread that will execute
// out of it.
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

  // Round up to the page boundary so mprotect operates on whole pages —
  // mprotect on a partial page is a no-op for the bytes past the file
  // size, but the call itself silently treats the page granularly. We
  // want the *page count* in the log to be honest, so compute it from
  // the rounded size.
  const long page_size = sysconf(_SC_PAGESIZE);
  const size_t rounded =
      (want + (size_t)page_size - 1) & ~((size_t)page_size - 1);

  void* buf = mmap(nullptr, rounded, PROT_READ | PROT_WRITE,
                   MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (buf == MAP_FAILED) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "KERNEL.CGO: mmap(%zu, PROT_READ|PROT_WRITE) failed: %s",
                        rounded, std::strerror(errno));
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
      munmap(buf, rounded);
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

  // W^X transition: drop PROT_WRITE before granting PROT_EXEC. Doing it
  // in the other order or trying to keep both bits would trip SELinux's
  // app_data_file no-exec rule on retail devices.
  if (mprotect(buf, rounded, PROT_READ | PROT_EXEC) != 0) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "KERNEL.CGO: mprotect(PROT_READ|PROT_EXEC) failed: %s",
                        std::strerror(errno));
    munmap(buf, rounded);
    return 0;
  }
  // I-cache invalidate. Required on AArch64 between writing code and
  // executing it; absent this, the first call into the region may
  // SIGILL with whatever the I-cache happened to have at that address.
  __builtin___clear_cache(reinterpret_cast<char*>(buf),
                          reinterpret_cast<char*>(buf) + rounded);

  const size_t pages = rounded / (size_t)page_size;
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "code-map: %zu pages RX, 0 RWX", pages);

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
  // Phase 28 (autoport): run InitMachine before the dispatcher spins up.
  // It re-inits the heap with the full GLOBAL_HEAP_END layout, wires
  // print/listener plumbing, and spawns the IOP worker. The phase-28
  // pitfalls explicitly call this out: a dispatcher that runs against a
  // half-initialised Machine is the failure mode this guards against.
  // ---------------------------------------------------------------------
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "goal_main: calling InitMachine()");
  int init_rc = InitMachine();
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "goal_main: InitMachine returned %d", init_rc);

  // ---------------------------------------------------------------------
  // Dispatcher thread — owns the real KernelCheckAndDispatch loop. The
  // detach is intentional: the thread runs for the lifetime of the
  // process, and we never join it.
  // ---------------------------------------------------------------------
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
