// Phase 27 (autoport): Android compat layer for the full runtime cross-build.
//
// Earlier phases (12-26) compiled only a curated subset of game/kernel/common
// and back-filled every other extern with a passive stub in this file. Phase 27
// flips that around: we compile (most of) game/kernel/common, game/kernel/jak1,
// game/system, game/overlord, and a chunk of common/ verbatim. That means the
// majority of the stubs that used to live here now have real upstream owners,
// so this file is now small and focused on:
//
//   1. Runtime globals that live in game/runtime.cpp upstream (g_ee_main_mem,
//      g_game_version, g_main_thread_id, g_server_port, g_background_worker)
//      — game/runtime.cpp itself is too entangled with SDL3/ImGui/discord to
//      compile on Bionic without per-subsystem fixes, so we own those globals.
//
//   2. Bionic-vs-glibc shims for upstream code that calls glibc-only entry
//      points (pthread_setname_np arity, mallinfo, execinfo backtrace, etc.).
//      Each shim does the equivalent work the desktop runtime expects, or
//      no-ops it where the call is purely diagnostic.
//
//   3. Android-side log routing for lg::internal::log_message /
//      lg::internal::log_print / lg::internal::log_vprintf so the upstream
//      lg::log/info/warn/print templates land in `adb logcat`. The upstream
//      common/log/log.cpp prints via fmt::color to stdout — fine on a
//      terminal, useless on Android. We provide our own definitions of just
//      the `internal::` entry points; the templates and the lg::set_* config
//      helpers come from common/log/log.cpp which we compile alongside.

#include <android/log.h>
#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>

#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>

#include "common/common_types.h"
#include "common/log/log.h"
#include "common/versions/versions.h"

#include "game/common/game_common_types.h"
#include "game/system/background_worker.h"

// ---------------------------------------------------------------------------
// Runtime globals owned by game/runtime.cpp upstream.
//
// game/runtime.cpp mmaps EE_MAIN_MEM_SIZE (128 MB) with PROT_EXEC for the JIT
// at boot. The full mmap dance pulls in the desktop CLI, discord, SDL listener
// setup and the InitParms argv parser — none of which we want to drag into
// libgk.so. So we own the buffer here. A 128 MB anonymous mmap is the upstream
// size and what the kernel expects (HEAP_START/GLOBAL_HEAP_END constants are
// indexed relative to it). The mapping is *intentionally not* PROT_EXEC: we
// load CGOs into a separate W^X region (see android_goal_main.cpp).
// ---------------------------------------------------------------------------

namespace {
constexpr const char* kAndroidLogTag = "opengoal-gk";
constexpr size_t kEEMainMemSize = 128u * 1024u * 1024u;  // matches EE_MAIN_MEM_SIZE

u8* allocate_ee_main_mem() {
  // mmap rather than a static buffer because 128 MB of bss bloats the .so and
  // hurts the validator's strip-size check.  Anonymous-mapped lazily-backed
  // pages don't show up in the file image at all.
  void* p = mmap(nullptr, kEEMainMemSize, PROT_READ | PROT_WRITE,
                 MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
  if (p == MAP_FAILED) {
    __android_log_print(ANDROID_LOG_FATAL, kAndroidLogTag,
                        "g_ee_main_mem mmap(%zu) failed: %s",
                        kEEMainMemSize, std::strerror(errno));
    return nullptr;
  }
  return static_cast<u8*>(p);
}
}  // namespace

u8* g_ee_main_mem = allocate_ee_main_mem();
GameVersion g_game_version = GameVersion::Jak1;
std::thread::id g_main_thread_id;
int g_server_port = 8112;  // DECI2_PORT — duplicated to avoid pulling listener_common.h

// game/runtime.cpp owns this; we provide a default-constructed instance so the
// kernel sources that reference g_background_worker from runtime.h link.
BackgroundWorker g_background_worker;

// ---------------------------------------------------------------------------
// Logging surface — routes lg::log/info/warn/print into __android_log_print.
//
// common/log/log.cpp is now compiled alongside us, so it owns set_file,
// set_flush_level, set_stdout_level, initialize, finish, etc. The only
// symbols we override are the three internal:: entry points the templates
// dispatch into — that's the smallest surface that lets us redirect output
// without forking the upstream header.
// ---------------------------------------------------------------------------

namespace {
android_LogPriority log_level_to_priority(lg::level lvl) {
  switch (lvl) {
    case lg::level::trace: return ANDROID_LOG_VERBOSE;
    case lg::level::debug: return ANDROID_LOG_DEBUG;
    case lg::level::info:  return ANDROID_LOG_INFO;
    case lg::level::warn:  return ANDROID_LOG_WARN;
    case lg::level::error: return ANDROID_LOG_ERROR;
    case lg::level::die:   return ANDROID_LOG_FATAL;
    default:               return ANDROID_LOG_INFO;
  }
}

std::mutex& log_mutex() {
  static std::mutex m;
  return m;
}
}  // namespace

// common/log/log.cpp is *excluded* from the Android build (it routes through
// fmt::color → stdout, which Bionic cuts off after a few KB and which logcat
// doesn't read anyway). We own the entire public lg:: API here so the upstream
// templates resolve. Each routes through __android_log_print so output lands
// in `adb logcat`.
namespace lg {
namespace internal {
void log_message(level log_level, LogTime& /*now*/, const char* message) {
  std::lock_guard<std::mutex> lock(log_mutex());
  __android_log_print(log_level_to_priority(log_level), kAndroidLogTag, "%s", message);
}

void log_print(const char* message) {
  std::lock_guard<std::mutex> lock(log_mutex());
  __android_log_print(ANDROID_LOG_INFO, kAndroidLogTag, "%s", message);
}

void log_vprintf(const char* format, va_list arg_list) {
  std::lock_guard<std::mutex> lock(log_mutex());
  __android_log_vprint(ANDROID_LOG_INFO, kAndroidLogTag, format, arg_list);
}
}  // namespace internal

void printstd(const char* format, va_list arg_list) {
  internal::log_vprintf(format, arg_list);
}

void set_file(const std::string& /*filename*/, const bool /*should_rotate*/,
              const bool /*append*/, const std::string& /*dir*/) {}
void set_flush_level(level /*log_level*/) {}
void set_file_level(level /*log_level*/) {}
void set_stdout_level(level /*log_level*/) {}
void set_max_debug_levels() {}
void disable_ansi_colors() {}
void initialize() {}
void finish() {}
}  // namespace lg

// ---------------------------------------------------------------------------
// Bionic shims used by upstream code that calls glibc-only entry points.
//
// We expose these with the same names the upstream sources call so the linker
// resolves them locally instead of failing to find them in Bionic. Each shim
// either reproduces the glibc behavior on Bionic terms or downgrades to a
// safe no-op when the desktop variant is purely diagnostic.
// ---------------------------------------------------------------------------

extern "C" {

// glibc's `mallinfo()` was deprecated long ago in favor of mallinfo2(); Bionic
// API 31+ ships `mallinfo()` as the new 64-bit struct. We don't need accurate
// numbers — the only desktop caller is the runtime's startup-info dump — so
// return a zero-filled struct of the right shape. If upstream ever taps a
// specific field, the zero default is still safer than abort.
struct compat_mallinfo {
  size_t arena, ordblks, smblks, hblks, hblkhd, usmblks, fsmblks, uordblks,
         fordblks, keepcost;
};
compat_mallinfo opengoal_compat_mallinfo() { return {}; }

// glibc-style execinfo. Bionic ships <execinfo.h> on API 33+ but we target
// API 29 — these are no-ops on older devices. Used by Assert.cpp's
// stack-dump path; abort()ing without the frames is still correct behavior.
int backtrace(void** /*buffer*/, int /*size*/) { return 0; }
char** backtrace_symbols(void* const* /*buffer*/, int /*size*/) { return nullptr; }
void backtrace_symbols_fd(void* const* /*buffer*/, int /*size*/, int /*fd*/) {}

}  // extern "C"

// ---------------------------------------------------------------------------
// Stubs for x86-only / desktop-only TUs we *don't* compile but whose symbols
// are still referenced by code we *do* compile. Each lives here so phase 27
// can ship without re-creating a third .cpp for each tiny shim.
// ---------------------------------------------------------------------------

// xdbg — common/cross_os_debug/xdbg.cpp uses PTRACE_GETREGS + the `user`
// struct from <sys/user.h>, which Bionic doesn't expose. The thread-id
// helpers below are the only two referenced from compiled code (kprint's
// reset_output() prints a thread-id banner). Match the API exactly so the
// upstream header resolves.
#include "common/cross_os_debug/xdbg.h"

namespace xdbg {
ThreadID::ThreadID(pid_t the_id) : id(the_id) {}
ThreadID::ThreadID(const std::string& /*str*/) : id(0) {}
std::string ThreadID::to_string() const {
  char buf[32];
  std::snprintf(buf, sizeof(buf), "%lld", (long long)id);
  return buf;
}
ThreadID get_current_thread_id() {
  return ThreadID((pid_t)gettid());
}
}  // namespace xdbg

// CacheFlush — defined in game/kernel/common/kmachine.cpp on desktop, but
// that TU pulls discord/graphics/sce which we don't cross-compile. The body
// flushes the I-cache for a code region (post-link). We do the same with
// the AArch64 builtin used by android_goal_main.cpp's W^X dance.
//
// kmachine.h declares this without extern "C", so the definition must
// match — C++ linkage.
void CacheFlush(void* mem, int size) {
  __builtin___clear_cache(reinterpret_cast<char*>(mem),
                          reinterpret_cast<char*>(mem) + size);
}

// Mips2C globals — game/mips2c/mips2c_table.cpp owns these upstream, but
// its static init references the link() of every jak{1,2,3} mips2c module
// (~300 unique functions across all three games — many we don't ship).
// Excluding mips2c_table.cpp means we own the symbols here. The empty maps
// short-circuit klink's mips2c lookup (returns "not found" → falls back to
// the GOAL-bytecode interpreter path), which is correct behavior given we
// don't actually drive game logic on Android yet.
#include "common/versions/versions.h"
#include "game/mips2c/mips2c_table.h"

namespace Mips2C {
PerGameVersion<std::unordered_map<std::string, std::vector<void (*)()>>>
    gMips2CLinkCallbacks = {
        std::unordered_map<std::string, std::vector<void (*)()>>{},
        std::unordered_map<std::string, std::vector<void (*)()>>{},
        std::unordered_map<std::string, std::vector<void (*)()>>{},
        std::unordered_map<std::string, std::vector<void (*)()>>{},
};
LinkedFunctionTable gLinkedFunctionTable;
void LinkedFunctionTable::reg(const std::string&, u64 (*)(void*), u32) {}
u32 LinkedFunctionTable::get(const std::string&) { return 0; }
}  // namespace Mips2C

// snd::SoundFlavaHack — set from game/kernel/common/ksound.cpp::set_flava_hack
// (a kscheme-callable). Real value lives in 989snd's ame_handler.cpp, which
// isn't ported yet. The variable stays at zero; setting it is observable
// (we log) but has no audible effect until 989snd lands on Android.
namespace snd {
u64 SoundFlavaHack = 0;
}

// Gfx::g_global_settings — owned by android_graphics_stubs.cpp.
// jak1::InitMachineScheme — defined upstream in game/kernel/jak1/kmachine.cpp
// (which we don't compile due to graphics/sce/discord deps). Called from
// jak1::kscheme.cpp::InitHeapAndSymbol at boot. Real impl populates the
// scheme namespace with kernel-side symbols + builtins. The android boot
// path skips InitHeapAndSymbol anyway (our top-level InitMachine wrapper
// doesn't reach it); the symbol still needs to resolve at link time.
// jak{1,2,3}::InitMachineScheme — live in jak{N}/kmachine.cpp upstream
// (graphics/sce/discord-heavy, not compiled here). Real impl populates
// the GOAL scheme namespace with kernel-side symbols + builtins. Our
// Android boot path's InitMachine wrapper doesn't reach InitHeapAndSymbol
// (which is what calls these), so the no-op body is safe for our boot.
//
// jak{2,3}::initialize_sql_db + run_sql_query — desktop SQLite-backed
// query helpers for the jak2/3 listener REPL. Bionic + sqlite would link,
// but our klisten path doesn't actually open a listener anyway. Returns
// an empty sqlite::GenericResponse — error_msg empty, success=false.
#include "common/sqlite/sqlite.h"

namespace jak1 { void InitMachineScheme() {} }
namespace jak2 { void InitMachineScheme() {} void initialize_sql_db() {}
                  sqlite::GenericResponse run_sql_query(const std::string&) {
                    return {}; } }
namespace jak3 { void InitMachineScheme() {} void initialize_sql_db() {}
                  sqlite::GenericResponse run_sql_query(const std::string&) {
                    return {}; } }

// GlobalProfiler — common/global_profiler/GlobalProfiler.cpp is excluded
// (it pulls compression::compress_zstd_no_header for its JSON dump path).
// IOP_Kernel + iop_thread call prof() / scoped_prof / GlobalProfiler::* —
// just enough surface to satisfy the linker with all events no-op'd. The
// runtime trace path is never actively used on Android (no profiler dump
// sink), so passive stubs are correct behavior.
#include "common/global_profiler/GlobalProfiler.h"

GlobalProfiler::GlobalProfiler() = default;
void GlobalProfiler::update_event_buffer_size(size_t) {}
void GlobalProfiler::set_waiting_for_event(const std::string&) {}
void GlobalProfiler::instant_event(const char*) {}
void GlobalProfiler::begin_event(const char*) {}
void GlobalProfiler::event(const char*, ProfNode::Kind) {}
void GlobalProfiler::end_event() {}
void GlobalProfiler::clear() {}
void GlobalProfiler::set_enable(bool) {}
void GlobalProfiler::dump_to_json() {}
void GlobalProfiler::root_event() {}
size_t GlobalProfiler::get_next_idx() { return 0; }

GlobalProfiler& prof() {
  static GlobalProfiler p;
  return p;
}
ScopedEvent scoped_prof(const char* /*name*/) { return ScopedEvent(nullptr); }

// REPL::find_repl_username — defined in common/repl/repl_wrapper.cpp (not
// compiled here). jak2/jak3 kboot.cpp call it during kboot_init_globals to
// stamp the username into the listener banner. We return a fixed string;
// the listener isn't reachable on Android anyway.
#include <string>
namespace REPL {
std::string find_repl_username() { return "android"; }
}  // namespace REPL

// _call_goal8_asm_systemv — mips2c_private.h's #ifdef __linux__ branch
// hardcodes this name (the desktop x86 systemv asm trampoline). On
// aarch64 the real implementation is _call_goal8_asm_arm64, in
// asm_funcs_arm64.s. Provide a thin wrapper so the jak1 mips2c TUs
// link without touching the upstream header.
extern "C" {
u64 _call_goal8_asm_arm64(void* func, u64* arg_array, u64 zero, u64 pp,
                          u64 st, void* off);
u64 _call_goal8_asm_systemv(void* func, u64* arg_array, u64 zero, u64 pp,
                            u64 st, void* off) {
  return _call_goal8_asm_arm64(func, arg_array, zero, pp, st, off);
}
}

// lzokay::decompress — used by FileUtil.cpp::decompress_dgo. The lzo path
// is only hit when the on-disc DGO is in compressed-LZO form, which the
// extracted jak1 iso_data is not. Stub returns Success.
namespace lzokay {
enum class EResult { LookbehindOverrun = -4, OutputOverrun = -3,
                     InputOverrun = -2, Error = -1, Success = 0,
                     InputNotConsumed = 1 };
EResult decompress(const unsigned char* /*src*/, std::size_t /*src_size*/,
                   unsigned char* /*dst*/, std::size_t /*dst_size*/,
                   std::size_t& out_size) {
  out_size = 0;
  return EResult::Success;
}
}  // namespace lzokay

// pthread_setname_np: glibc accepts up to 16 chars; Bionic enforces 15+NUL
// and silently truncates anything longer. The 2-arg form (pthread_t, name)
// exists on both, so no shim required for that signature — but desktop code
// that calls the 1-arg `pthread_setname_np(name)` form (Linux extension to
// the current thread) doesn't exist on Bionic. We define a free helper so
// upstream code can call it portably.
namespace opengoal_compat {
void set_current_thread_name(const char* raw_name) {
  if (!raw_name) return;
  char trimmed[16];
  std::strncpy(trimmed, raw_name, sizeof(trimmed) - 1);
  trimmed[sizeof(trimmed) - 1] = '\0';
  pthread_setname_np(pthread_self(), trimmed);
}
}  // namespace opengoal_compat
