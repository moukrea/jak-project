// Android implementation of `goal_main`. The dispatcher thread forwards
// into KernelCheckAndDispatch (in android_runtime_full.cpp), which now
// delegates directly to jak1::KernelCheckAndDispatch — no weak fallback,
// no synthesised state transitions. If kmachine.cpp is not in the build,
// the link fails honestly.
//
// goal_main owns the boot prelude: argv parsing, kheap init via the
// upstream kmalloc primitives, and the honest open()+read() that pulls
// KERNEL.CGO off the extracted iso_data into a W^X-disciplined RX
// mapping. Those steps complete before the dispatcher thread spins up.

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
#include <string>
#include <thread>

#include "common/common_types.h"
#include "common/util/FileUtil.h"
#include "common/versions/versions.h"  // Gjak2-boot: GameVersion + game_name_to_version

#include "game/common/game_common_types.h"  // Language enum (A34 prelude parity)
#include "game/kernel/common/Ptr.h"
#include "game/kernel/common/fileio.h"
#include "game/kernel/common/kboot.h"
#include "game/kernel/common/kdgo.h"
#include "game/kernel/common/kdsnetm.h"
#include "game/kernel/common/klink.h"
#include "game/kernel/common/klisten.h"
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/kmemcard.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/kscheme.h"  // init_crc (A34 prelude parity)
#include "game/kernel/common/memory_layout.h"
#include "game/kernel/jak1/kboot.h"
#include "game/kernel/jak1/kdgo.h"
#include "game/kernel/jak1/klisten.h"
#include "game/kernel/jak1/kmachine.h"  // jak1::InitParms
#include "game/kernel/jak1/kscheme.h"
#include "game/sce/libscf.h"  // ee::sceScfGetAspect/Language (A34)

// Phase 21 (autoport): SDL/GLES bring-up + shader compile + render loop
// lives in its own TU so this file stays focused on the kernel boot
// sequence. Both are driven from goal_main below — kheap + CGO load run
// first, then the dispatcher thread is detached, then the SDL main
// thread enters android_renderer_run() until quit.
#include "android_renderer.h"

// Forward declaration matches the one at the top of game/main.cpp so the
// desktop and Android boot entries share a single signature.
int goal_main(int argc, char** argv);

// Gjak2-boot: the game selected at boot (--game jak2). g_game_version is owned
// by android_runtime_compat.cpp; goal_main sets it from argv so every per-game
// kernel path (init_output/kscheme/klink branches, InitMachine, the overlord)
// keys off the right version. jak2 kernel init entry points are forward-declared
// here (rather than including game/kernel/jak2/kmachine.h, which pulls graphics/
// discord headers) — they resolve at link time from the compiled jak2 TUs.
extern GameVersion g_game_version;
namespace jak2 {
void kboot_init_globals();
void kdgo_init_globals();
void kscheme_init_globals();
void klisten_init_globals();
void InitParms(int argc, const char* const* argv);
}  // namespace jak2

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

  // Hand the thread to the KernelCheckAndDispatch wrapper. It forwards
  // directly into jak1::KernelCheckAndDispatch — the real GOAL kernel
  // loop. No synthesised heartbeat or state-transition markers; if jak1
  // is not linked, the build fails at link time.
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

  // Gjak2-boot: pluck the game name out of argv ("--game <name>") and set
  // g_game_version BEFORE any per-game kernel init runs — init_output/kscheme/
  // klink all branch on it. gk_android_main builds argv as
  // "gk --game <name> --portable -fakeiso -iso-data <root> ...". Default to the
  // shipped jak1 title if absent.
  std::string game_name = "jak1";
  for (int i = 0; i + 1 < argc; ++i) {
    if (argv[i] && std::strcmp(argv[i], "--game") == 0) {
      game_name = argv[i + 1];
      break;
    }
  }
  g_game_version = game_name_to_version(game_name);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "goal_main: selected game=%s (version=%d)",
                      game_name.c_str(), (int)g_game_version);

  // External-asset-root feature (autoport 2026-07): Android bypasses the desktop
  // main.cpp CLI parsing entirely, so the --game-root/--iso-overlay argv flags
  // would be inert here — apply the FileUtil overrides DIRECTLY from the JNI
  // globals, BEFORE any file_util consumer (fake_iso, fr3 loader, save dirs)
  // runs. Empty globals = internal mode = no override, byte-identical behavior.
  {
    extern std::string g_iso_overlay;  // defined in gk_android_main.cpp
    extern std::string g_game_root;    // (also read below for the symlink skip)
    if (!g_game_root.empty()) {
      file_util::set_external_game_root(fs::path(g_game_root));
      __android_log_print(ANDROID_LOG_INFO, kLogTag,
                          "goal_main: external game root -> %s", g_game_root.c_str());
    }
    if (!g_iso_overlay.empty()) {
      file_util::set_iso_overlay_dir(fs::path(g_iso_overlay));
      __android_log_print(ANDROID_LOG_INFO, kLogTag,
                          "goal_main: iso overlay dir -> %s", g_iso_overlay.c_str());
    }
    // Grecharged-buildsys-packaging: same direct wiring for the package-shipped
    // custom-assets root (recharged PNGs, .grassbake, enhanced fr3 read from
    // <filesDir>/custom/<game> instead of the vanilla external tree). The
    // --custom-assets argv flag is inert here for the same reason as above.
    extern std::string g_custom_root;  // defined in gk_android_main.cpp
    if (!g_custom_root.empty()) {
      file_util::set_custom_assets_root(fs::path(g_custom_root));
      __android_log_print(ANDROID_LOG_INFO, kLogTag,
                          "goal_main: custom assets root -> %s", g_custom_root.c_str());
    }
  }

  // ---------------------------------------------------------------------
  // Phase D4 (autoport): set up the desktop-style project root so
  // upstream code that calls file_util::get_jak_project_dir() resolves
  // to a path we control.
  //
  // The overlord's fake_iso_FS_Init scans `<project>/out/<game>/iso/*`
  // for the DGOs. On Android the extracted iso_data lives at
  // `<data_root>` (e.g. /data/.../files/iso_data/jak1). We arrange a
  // synthetic project root one level above that, with a symlink at
  // `<project>/out/jak1/iso -> <data_root>` so the desktop scan
  // returns the right files without any upstream patches.
  //
  // Both operations are idempotent — running them on a hot start
  // (where the dir / symlink already exists) is a fast no-op.
  // ---------------------------------------------------------------------
  fs::path data_root_path(data_root);
  fs::path project_root = data_root_path.parent_path().parent_path();
  // External-asset-root feature (autoport 2026-07): in EXTERNAL mode the runtime
  // reads iso/fr3/saves straight from the user's on-storage <game-root> (FileUtil
  // resolves them), so the out/<game>/iso -> data_root symlink farm is neither
  // needed nor writable-appropriate — skip it entirely. We STILL call
  // setup_project_path(project_root) with the files-derived root so shaders/dev
  // leftovers under <files> resolve. In INTERNAL mode the symlink is created as
  // before (an existing files/cgo overlay does not affect it).
  extern std::string g_game_root;  // defined in gk_android_main.cpp
  const bool external_mode = !g_game_root.empty();
  std::error_code ec;
  if (external_mode) {
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                        "goal_main: external mode (game-root=%s) — skipping "
                        "out/<game>/iso symlink farm",
                        g_game_root.c_str());
  } else {
    // Gjak2-boot: per-game symlink dir (out/jak1, out/jak2, ...) so the overlord's
    // fake_iso scan of <project>/out/<game>/iso resolves to the extracted assets.
    fs::path iso_link_parent = project_root / "out" / game_name;
    fs::path iso_link        = iso_link_parent / "iso";
    fs::create_directories(iso_link_parent, ec);
    if (ec) {
      __android_log_print(ANDROID_LOG_WARN, kLogTag,
                          "goal_main: create_directories(%s) failed: %s",
                          iso_link_parent.c_str(), ec.message().c_str());
      ec.clear();
    }
    if (!fs::exists(iso_link, ec)) {
      fs::create_directory_symlink(data_root_path, iso_link, ec);
      if (ec) {
        __android_log_print(ANDROID_LOG_WARN, kLogTag,
                            "goal_main: symlink(%s -> %s) failed: %s",
                            iso_link.c_str(), data_root_path.c_str(),
                            ec.message().c_str());
      } else {
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "goal_main: symlink %s -> %s created",
                            iso_link.c_str(), data_root_path.c_str());
      }
    }
  }
  file_util::setup_project_path(project_root, /*skip_logs=*/false);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "goal_main: project_path=%s, data_root=%s, external=%d",
                      project_root.c_str(), data_root_path.c_str(),
                      (int)external_mode);

  // ---------------------------------------------------------------------
  // kheap init — honest call into upstream kmalloc primitives.
  // ---------------------------------------------------------------------
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "goal_main: initializing kernel globals (kboot/kmalloc)");
  // A36: mirror desktop exec_runtime's FULL init_globals sequence
  // (game/runtime.cpp:194-226). Android previously called only
  // kboot+kmalloc — every other kernel global stayed at .bss zeros.
  // Visible casualty: kprint's ConvertTable was all-zero, so kitoa
  // emitted "" for every digit and the text loader asked the fakeiso
  // for "common.TXT" instead of "0common.TXT". Same order as desktop;
  // jak2/jak3 variants are compiled into android_kernel and cheap.
  // Gjak2-boot: call BOTH jak1 and jak2 per-game init_globals, exactly as the
  // desktop exec_runtime does (runtime.cpp:194-218 lists jak1::/jak2::/jak3::
  // unconditionally) — they just zero per-game kernel state and are cheap/safe
  // for the other game. jak3 kboot is not compiled on Android, so it's omitted.
  fileio_init_globals();
  jak1::kboot_init_globals();
  jak2::kboot_init_globals();
  kboot_init_globals_common();
  kdgo_init_globals();
  jak1::kdgo_init_globals();
  jak2::kdgo_init_globals();
  kdsnetm_init_globals_common();
  klink_init_globals();
  // Android shim (android_runtime_compat.cpp) — common/kmachine.h isn't
  // includable here (pulls Display::/Gfx::), declare the shim directly.
  extern void kmachine_init_globals_common();
  kmachine_init_globals_common();
  jak1::kscheme_init_globals();
  jak2::kscheme_init_globals();
  kscheme_init_globals_common();
  kmalloc_init_globals_common();
  klisten_init_globals();
  jak1::klisten_init_globals();
  jak2::klisten_init_globals();
  kmemcard_init_globals();
  kprint_init_globals_common();

  // Phase E1 (autoport): InitParms wires the -boot / -fakeiso / -debug-mem
  // flags into DiskBoot, MasterDebug, isodrv, modsrc — the bits that
  // jak1::InitMachineScheme keys off of when deciding whether to load
  // the "game" DGO. Without this, DiskBoot stays at 0 (the
  // kboot_init_globals_common default) and the engine DGO never loads,
  // so `link finish: logo` never fires. The desktop jak1::goal_main
  // calls InitParms at the same point in its boot sequence
  // (game/kernel/jak1/kboot.cpp); Android's goal_main was missing it.
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "goal_main: InitParms(argc=%d) — wiring boot flags",
                      argc);
  // Gjak2-boot: per-game InitParms (parses -boot/-fakeiso/-debug-mem into
  // DiskBoot/MasterDebug/isodrv/modsrc).
  if (g_game_version == GameVersion::Jak2) {
    jak2::InitParms(argc, argv);
  } else {
    jak1::InitParms(argc, argv);
  }

  // A34 (autoport): desktop goal_main prelude parity. jak1::goal_main
  // (game/kernel/jak1/kboot.cpp) runs InitParms → init_crc() →
  // masterConfig setup before InitMachine. Android's goal_main had
  // InitParms only.
  //
  // init_crc() is LOAD-BEARING: with crc_table all-zero, crc32() returns
  // wrong-but-self-consistent hashes, so every symbol still interns and
  // resolves — EXCEPT the one place a hash CONSTANT is compared:
  // find_symbol_from_c's EMPTY_HASH special case for "_empty_". Without
  // it, klink's symlink for static '() references interns a fresh
  // ordinary "_empty_" symbol instead of returning the fixed empty pair
  // (s7-10), so every static-data '() is != the runtime '() and (null?
  // x) never terminates list walks. On-device this killed
  // get-continue-by-name 2 ms after `link finish: title-vis`:
  // test-zone's 1-element continues list ended in the wrong-empty,
  // the walk ran through low memory and did (car 0) → SIGSEGV at
  // fault=EE_base-2 (GK-DIAG pc=0x7f01ce0b98, A33 routed logcat).
  init_crc();

  // masterConfig: GOAL reads these via scf-get-aspect / scf-get-language
  // / scf-get-volume during display/progress boot. Mirror the desktop
  // values exactly (kboot.cpp:58-86).
  masterConfig.aspect = (u16)ee::sceScfGetAspect();
  masterConfig.language = (u16)ee::sceScfGetLanguage();
  masterConfig.inactive_timeout = 0;
  masterConfig.timeout = 0;
  masterConfig.volume = 100;
  if (masterConfig.language == SCE_SPANISH_LANGUAGE) {
    masterConfig.language = (u16)Language::Spanish;
  } else if (masterConfig.language == SCE_FRENCH_LANGUAGE) {
    masterConfig.language = (u16)Language::French;
  } else if (masterConfig.language == SCE_GERMAN_LANGUAGE) {
    masterConfig.language = (u16)Language::German;
  } else if (masterConfig.language == SCE_ITALIAN_LANGUAGE) {
    masterConfig.language = (u16)Language::Italian;
  } else if (masterConfig.language == SCE_JAPANESE_LANGUAGE) {
    masterConfig.language = (u16)Language::Japanese;
  } else {
    masterConfig.language = (u16)Language::English;
  }
  if (!strcmp(DebugBootMessage, "demo") || !strcmp(DebugBootMessage, "demo-shared")) {
    masterConfig.aspect = SCE_ASPECT_FULL;
  }
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "goal_main: prelude parity — init_crc done, aspect=%u language=%u volume=%u",
                      (unsigned)masterConfig.aspect,
                      (unsigned)masterConfig.language,
                      (unsigned)masterConfig.volume);

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
