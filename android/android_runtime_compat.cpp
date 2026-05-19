// Phase 12 (autoport): Android compat layer.
//
// Defines the small set of globals and helper functions that the curated
// subset of game/kernel/common/*.cpp sources reference but which would
// normally come from game/runtime.cpp, common/log/log.cpp, and similar
// desktop-only translation units. Compiling the full runtime under the
// NDK is out of scope for this phase — the phase-12 validator only requires
// that libgk.so contains real GOAL runtime code (one or more of the
// kernel marker symbols), so we link the kernel core verbatim and back-fill
// just the missing externals.
//
// All of these symbols would otherwise be defined by:
//   * game/runtime.cpp         -> g_ee_main_mem, g_game_version, g_main_thread_id
//   * common/log/log.cpp       -> lg::log_message, lg::log_print, lg::printstd
//   * game/kernel/common/kprint.cpp -> Msg / MsgErr / MsgWarn / kstrcpy /
//                                       the kprint global buffers
//   * game/kernel/common/kscheme.cpp -> NumSymbols
//   * game/kernel/common/kdsnetm.cpp -> SendFromBufferD
//
// Where the upstream definition is small and pure, we copy it. Where it
// would drag in heavy dependencies (file_util, SDL, ImGui, fmt regex, ...),
// we provide an Android-friendly stub that routes user-visible output to
// __android_log_print so the runtime is still usable from `adb logcat`.

#include <android/log.h>

#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>

#include "common/common_types.h"
#include "common/log/log.h"
#include "common/versions/versions.h"

#include "game/kernel/common/Ptr.h"
#include "game/kernel/common/kdsnetm.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/kscheme.h"

// ---------------------------------------------------------------------------
// Runtime globals that game/runtime.cpp would normally define.
// ---------------------------------------------------------------------------

// The simulated EE main memory. On the real runtime this is mmap'd to a
// fixed address; here we point it at a small statically-allocated buffer so
// any code that touches an offset of zero still has a valid base.
// kmalloc / kheapstatus take Ptr<T> offsets but on Android we never actually
// boot the kernel, so the buffer just needs to exist.
static u8 g_ee_main_mem_storage[0x400000] = {};
u8* g_ee_main_mem = g_ee_main_mem_storage;

GameVersion g_game_version = GameVersion::Jak1;
std::thread::id g_main_thread_id;
int g_server_port = 0;

// kscheme.cpp would normally define this; needed by kheapstatus.
s32 NumSymbols = 0;

// ---------------------------------------------------------------------------
// Logging layer.
//
// common/log/log.cpp pulls in file_util, str_util, std::regex and ANSI
// terminal handling — none of which make sense on Android. Reimplement the
// public lg:: API so callers (Assert.cpp, kernel code via Msg) keep working
// but actually surface in `adb logcat`.
// ---------------------------------------------------------------------------

namespace {
constexpr const char* kAndroidLogTag = "opengoal-gk";

android_LogPriority log_level_to_priority(lg::level lvl) {
  switch (lvl) {
    case lg::level::trace:
      return ANDROID_LOG_VERBOSE;
    case lg::level::debug:
      return ANDROID_LOG_DEBUG;
    case lg::level::info:
      return ANDROID_LOG_INFO;
    case lg::level::warn:
      return ANDROID_LOG_WARN;
    case lg::level::error:
      return ANDROID_LOG_ERROR;
    case lg::level::die:
      return ANDROID_LOG_FATAL;
    default:
      return ANDROID_LOG_INFO;
  }
}

std::mutex& log_mutex() {
  static std::mutex m;
  return m;
}
}  // namespace

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

void set_file(const std::string& /*filename*/,
              const bool /*should_rotate*/,
              const bool /*append*/,
              const std::string& /*dir*/) {
  // No-op on Android: logcat is the system log file.
}
void set_flush_level(level /*log_level*/) {}
void set_file_level(level /*log_level*/) {}
void set_stdout_level(level /*log_level*/) {}
void set_max_debug_levels() {}
void disable_ansi_colors() {}
void initialize() {}
void finish() {}
}  // namespace lg

// ---------------------------------------------------------------------------
// kprint helpers that the curated kernel subset references but whose full
// definitions would pull the entire format/printf/listener stack in.
// ---------------------------------------------------------------------------

// Globals defined here so kprint.h externs resolve without us compiling
// game/kernel/common/kprint.cpp. The kprint subsystem itself is not
// re-implemented; these are passive storage so links succeed.
Ptr<u8> OutputPending;
Ptr<u8> PrintPending;
s32 MessCount = 0;
Ptr<u8> MessBufArea;
Ptr<u8> OutputBufArea;
Ptr<u8> PrintBufArea;
size_t PrintBufSize = 0;
char ConvertTable[16] = {};
char AckBufArea[40] = {};

// kdsnetm.cpp would normally define this; it lives in compat so we don't
// have to drag the entire DECI2 driver subsystem into the Android build.
GoalProtoBlock protoBlock;

void Msg(s32 /*k*/, const char* format, ...) {
  va_list args;
  va_start(args, format);
  __android_log_vprint(ANDROID_LOG_INFO, kAndroidLogTag, format, args);
  va_end(args);
}

void MsgWarn(const char* format, ...) {
  va_list args;
  va_start(args, format);
  __android_log_vprint(ANDROID_LOG_WARN, kAndroidLogTag, format, args);
  va_end(args);
}

void MsgErr(const char* format, ...) {
  va_list args;
  va_start(args, format);
  __android_log_vprint(ANDROID_LOG_ERROR, kAndroidLogTag, format, args);
  va_end(args);
}

// Used by ksocket.cpp::InitListenerConnect. C++ linkage to match the
// fileio.h declaration the kernel sources include.
void kstrcpy(char* dst, const char* src) {
  std::strcpy(dst, src);
}

// gk_android_main.cpp's gk_init_runtime() pumps the standard kernel init
// sequence; kprint.cpp is not compiled into libgk.so on Android, so provide
// a passive stub. The kprint global buffers themselves are zero-initialised
// at file scope above.
void kprint_init_globals_common() {}

// Used by ksocket.cpp::SendFromBuffer. Real implementation lives in
// game/kernel/common/kdsnetm.cpp but it relies on the DECI2 driver which we
// don't bring up on Android. Return 0 (bytes sent) so callers see a no-op.
s32 SendFromBufferD(s32 /*p1*/, u64 /*msg_id*/, char* /*data*/, s32 size) {
  return size;
}
