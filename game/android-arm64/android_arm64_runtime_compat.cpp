// Phase D1 (autoport, bucket D): Android NDK runtime compat layer for
// the bucket-D android-arm64 cross-build of `gk`. This file is a port
// of `game/linux-arm64/linux_arm64_runtime_compat.cpp` with two
// differences:
//
//   1. Logging routes via `__android_log_print` rather than the desktop
//      `fmt::color` -> stdout path. The lg::internal:: entry points
//      override common/log/log.cpp's (excluded from this build because
//      its body's `fmt::color` is dead on Android — same approach
//      `android/android_runtime_compat.cpp` uses for the libgk.so
//      Activity build).
//
//   2. Runtime globals (g_ee_main_mem etc.) follow the linux-arm64
//      pattern: declared nullptr / default-constructed and owned by
//      whatever D2+ driver replaces android_arm64_main.cpp. D1's
//      banner-and-exit main() doesn't touch them.
//
// Everything else (Gfx::g_global_settings, Mips2C globals, snd_*
// no-ops, jak{N}::InitMachineScheme stubs, GlobalProfiler stubs,
// lzokay::decompress, REPL::find_repl_username, _call_goal8 SysV
// wrapper, kmachine globals + InitCD/InitVideo/InitSoundScheme +
// kboot_init_globals + CacheFlush) is mechanically identical to the
// linux-arm64 compat. Same upstream, same shimmable surface.
//
// NB on xdbg: linux-arm64 owns xdbg::ThreadID + get_current_thread_id
// + allow_debugging in its compat file. We instead put those in
// android_arm64_bionic_shims.cpp because Bionic's <sys/user.h>
// restrictions arguably belong with the other Bionic-vs-glibc shims.
// The runtime_compat layer here therefore omits xdbg.

#include <android/log.h>
#include <pthread.h>
#include <sys/mman.h>
#include <unistd.h>

#include <atomic>
#include <cerrno>
#include <cstdarg>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>

#include "common/common_types.h"
#include "common/log/log.h"
#include "common/versions/versions.h"
#include "game/common/game_common_types.h"
#include "game/system/background_worker.h"

// ---------------------------------------------------------------------------
// Runtime globals normally owned by game/runtime.cpp.
//
// game/runtime.cpp is too entangled with SDL3/ImGui/discord/CLI11 to
// cross-build on Bionic; we own the two-or-three globals it owns
// upstream. g_ee_main_mem stays nullptr at D1 — the future D2+ driver
// will mmap EE_MAIN_MEM_SIZE before the kernel-init chain runs.
// ---------------------------------------------------------------------------

u8* g_ee_main_mem = nullptr;
GameVersion g_game_version = GameVersion::Jak1;
std::thread::id g_main_thread_id;
int g_server_port = 8112;  // DECI2_PORT — duplicated to avoid pulling listener_common.h

BackgroundWorker g_background_worker;

// ---------------------------------------------------------------------------
// CacheFlush — declared in game/kernel/common/kmachine.h; upstream body
// is in kmachine.cpp which we don't compile (graphics deps). Use the
// portable builtin; same shape as both the linux-arm64 and Android
// libgk.so builds.
// ---------------------------------------------------------------------------
void CacheFlush(void* mem, int size) {
    __builtin___clear_cache(reinterpret_cast<char*>(mem),
                            reinterpret_cast<char*>(mem) + size);
}

// ---------------------------------------------------------------------------
// Logging surface — routes lg::log/info/warn/print into
// __android_log_print so the upstream `lg::` templates land in
// `adb logcat -s opengoal-gk` rather than a stdout pipe nobody reads.
//
// common/log/log.cpp is *excluded* from this build (its body uses
// fmt::color → stdout which Bionic doesn't really support and which
// logcat doesn't read anyway). We own the entire public lg:: API
// here — the templates in common/log/log.h dispatch through the
// internal:: entry points so this is the smallest surface that
// captures every lg:: call without forking the header.
// ---------------------------------------------------------------------------

namespace {
constexpr const char* kAndroidLogTag = "opengoal-gk";

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

// Configuration entry points — kept here so common/log/log.cpp can stay
// excluded. Bodies are no-ops since logcat ignores file/stdout/level
// hints; the runtime can still call them without #ifdef.
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
// mips2c_table — same situation as the libgk.so build: mips2c_table.cpp's
// static init pulls every jak{1,2,3} link callback. Excluding it means
// we own the globals here. Empty maps → klink falls back to GOAL-bytecode
// path (the correct behavior when mips2c isn't actively driving game
// logic — at D1 we don't reach the kernel boot anyway).
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// _call_goal8_asm_systemv — mips2c_private.h's #ifdef __linux__ branch
// hardcodes this x86 SysV name. On aarch64 (linux + android both) the
// trampoline is named _call_goal8_asm_arm64 (in asm_funcs_arm64.s).
// Thin wrapper so the jak1 mips2c TUs link without touching the upstream
// header. Same as the linux-arm64 compat layer.
// ---------------------------------------------------------------------------
extern "C" {
u64 _call_goal8_asm_arm64(void* func, u64* arg_array, u64 zero, u64 pp,
                          u64 st, void* off);
u64 _call_goal8_asm_systemv(void* func, u64* arg_array, u64 zero, u64 pp,
                            u64 st, void* off) {
    return _call_goal8_asm_arm64(func, arg_array, zero, pp, st, off);
}
}  // extern "C"

// ---------------------------------------------------------------------------
// Gfx::g_global_settings — overlord/jak1/srpc.cpp's VBlank handler reads
// `g_global_settings.target_fps`. Default-construct so target_fps is its
// upstream default (60.0f) — exactly the desktop fallback when target_fps
// hasn't been overridden.
// ---------------------------------------------------------------------------
#include "game/graphics/gfx.h"

namespace Gfx {
GfxGlobalSettings g_global_settings;
}  // namespace Gfx

// ---------------------------------------------------------------------------
// jak{1,2,3}::InitMachineScheme — upstream lives in jak{N}/kmachine.cpp.
// We don't compile those (graphics/sce/discord). The function populates
// the GOAL scheme namespace with kernel-side builtins, called from
// kscheme.cpp::InitHeapAndSymbol. D1's banner-and-exit main() doesn't
// call that path; the no-op body is the honest behavior: if anyone ever
// calls it on Android, the GOAL kernel will see no kernel builtins and
// complain — which is the truth at D1, fixed by D2+.
//
// jak{2,3}::initialize_sql_db + run_sql_query — same situation: desktop
// SQLite REPL helper, not driven on Android. Returns empty response.
// ---------------------------------------------------------------------------
#include "common/sqlite/sqlite.h"

namespace jak1 {
void InitMachineScheme() {}
}  // namespace jak1
namespace jak2 {
void InitMachineScheme() {}
void initialize_sql_db() {}
sqlite::GenericResponse run_sql_query(const std::string&) { return {}; }
}  // namespace jak2
namespace jak3 {
void InitMachineScheme() {}
void initialize_sql_db() {}
sqlite::GenericResponse run_sql_query(const std::string&) { return {}; }
}  // namespace jak3

// ---------------------------------------------------------------------------
// snd::SoundFlavaHack — set by ksound.cpp::set_flava_hack. The real var
// lives in 989snd's ame_handler.cpp; we own it here so the kscheme
// callable resolves. Value has no audible effect until 989snd is wired.
// ---------------------------------------------------------------------------
namespace snd {
u64 SoundFlavaHack = 0;
}  // namespace snd

// ---------------------------------------------------------------------------
// GlobalProfiler — common/global_profiler/GlobalProfiler.cpp is excluded
// (pulls compression::compress_zstd_no_header → libzstd, not vendored).
// IOP_Kernel + iop_thread call prof() / scoped_prof. No-op stubs satisfy
// the link; no dump sink is active anyway.
// ---------------------------------------------------------------------------
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

// ---------------------------------------------------------------------------
// REPL::find_repl_username — common/repl/repl_wrapper.cpp is excluded
// (it depends on replxx which we don't cross-build). jak2/jak3 kboot
// reference it; jak1 does not, but the symbol must still resolve to
// keep the per-game-version kboot link clean.
// ---------------------------------------------------------------------------
namespace REPL {
std::string find_repl_username() { return "android-arm64"; }
}  // namespace REPL

// ---------------------------------------------------------------------------
// lzokay::decompress — used by FileUtil.cpp::decompress_dgo. The lzokay
// header may inline-define this in the desktop build; on the cross-build
// the symbol can fall through to here. Returns Success with out_size=0
// — the jak1 DGOs we ship are extracted (already-decompressed), so the
// LZO path is not exercised at boot. Same behavior as the linux-arm64
// compat layer.
// ---------------------------------------------------------------------------
namespace lzokay {
enum class EResult {
    LookbehindOverrun = -4, OutputOverrun = -3, InputOverrun = -2,
    Error = -1, Success = 0, InputNotConsumed = 1,
};
EResult decompress(const unsigned char* /*src*/, std::size_t /*src_size*/,
                   unsigned char* /*dst*/, std::size_t /*dst_size*/,
                   std::size_t& out_size) {
    out_size = 0;
    return EResult::Success;
}
}  // namespace lzokay

// ---------------------------------------------------------------------------
// Sound surface — 989snd / sndshim.cpp not cross-compiled here. Provide
// no-op shims for the snd_* + sceSd* surface the overlord/jak1 sources
// reference. Each matches sndshim.h byte-for-byte; same set as the
// linux-arm64 compat layer.
// ---------------------------------------------------------------------------
#include "game/sound/sndshim.h"

using sceSdTransIntrHandler = int (*)(int, void*);
extern "C++" {
u32  sceSdGetSwitch(u32);
u32  sceSdGetAddr(u32);
void sceSdSetSwitch(u32, u32);
void sceSdSetAddr(u32, u32);
void sceSdSetParam(u32, u32);
void sceSdSetTransIntrHandler(s32, sceSdTransIntrHandler, void*);
u32  sceSdVoiceTrans(s32, s32, const void*, u32, u32);
}

u32  sceSdGetSwitch(u32) { return 0; }
u32  sceSdGetAddr(u32) { return 0; }
void sceSdSetSwitch(u32, u32) {}
void sceSdSetAddr(u32, u32) {}
void sceSdSetParam(u32, u32) {}
void sceSdSetTransIntrHandler(s32, sceSdTransIntrHandler, void*) {}
u32  sceSdVoiceTrans(s32, s32, const void*, u32, u32) { return 0; }

void snd_StartSoundSystem() {}
void snd_StopSoundSystem() {}
s32  snd_GetTick() { return 0; }
void snd_RegisterIOPMemAllocator(AllocFun, FreeFun) {}
int  snd_LockVoiceAllocator(bool) { return 0; }
void snd_UnlockVoiceAllocator() {}
s32  snd_ExternVoiceAlloc(s32, s32) { return -1; }
u32  snd_SRAMMalloc(u32) { return 0; }
void snd_SRAMMarkUsed(u32, u32) {}
void snd_SetMixerMode(s32, s32) {}
void snd_SetGroupVoiceRange(s32, s32, s32) {}
void snd_SetReverbDepth(s32, s32, s32) {}
void snd_SetReverbType(s32, s32) {}
void snd_SetPanTable(s16*) {}
void snd_SetPlayBackMode(s32) {}
s32  snd_SoundIsStillPlaying(s32) { return 0; }
void snd_StopSound(s32) {}
u32  snd_GetSoundID(s32) { return 0; }
void snd_SetSoundVolPan(s32, s32, s32) {}
void snd_SetMasterVolume(s32, s32) {}
void snd_UnloadBank(snd::BankHandle) {}
void snd_ResolveBankXREFS() {}
void snd_ContinueAllSoundsInGroup(u8) {}
void snd_PauseAllSoundsInGroup(u8) {}
void snd_SetMIDIRegister(s32, u8, u8) {}
void snd_SetGlobalExcite(u8) {}
s32  snd_PlaySoundVolPanPMPB(snd::BankHandle, s32, s32, s32, s32, s32) { return 0; }
s32  snd_PlaySoundByNameVolPanPMPB(snd::BankHandle, char*, char*, s32, s32, s32, s32) { return 0; }
void snd_SetSoundPitchModifier(s32, s32) {}
void snd_SetSoundPitchBend(s32, s32) {}
void snd_PauseSound(s32) {}
void snd_ContinueSound(s32) {}
void snd_AutoPitch(s32, s32, s32, s32) {}
void snd_AutoPitchBend(s32, s32, s32, s32) {}
snd::BankHandle snd_BankLoadEx(const char*, s32, u32, u32) { return nullptr; }
void snd_BankLoadFromIOPPartialEx_Start() {}
void snd_BankLoadFromIOPPartialEx(const u8*, u32, u32, u32) {}
snd::BankHandle snd_BankLoadFromIOPPartialEx_Completion() { return nullptr; }
s32  snd_GetVoiceStatus(s32) { return 0; }
s32  snd_GetFreeSPUDMA() { return 0; }
void snd_FreeSPUDMA(s32) {}
void snd_keyOnVoiceRaw(u32, u32) {}
void snd_keyOffVoiceRaw(u32, u32) {}
s32  snd_GetSoundUserData(snd::BankHandle, char*, s32, char*, SFXUserData*) { return 0; }
void snd_SetSoundReg(s32, s32, u8) {}

// ---------------------------------------------------------------------------
// kmachine-equivalent globals + stubs.
//
// jak1's kmachine.cpp owns these globals + functions but the file pulls
// graphics/discord/sce-libgraph transitively. D1's banner-and-exit doesn't
// reach the kernel boot, but the symbols must still resolve at link time.
// Each definition matches the upstream prototype/type exactly with a
// no-op or default-constructed body. None of them is `weak`. None of
// them emits a synthetic log marker.
// ---------------------------------------------------------------------------
#include "common/util/Timer.h"
#include "game/kernel/common/kmachine.h"
#include "game/kernel/jak1/kmachine.h"
#include "game/sce/libpad.h"  // SCE_PAD_DMA_BUFFER_SIZE

OverlordDataSource isodrv = fakeiso;
u32 modsrc = 1;
u32 reboot_iop = 1;
const char* init_types[] = {"fakeiso", "deviso", "iso_cd"};
u8 pad_dma_buf[2 * SCE_PAD_DMA_BUFFER_SIZE] = {};
u32 vif1_interrupt_handler = 0;
u32 vblank_interrupt_handler = 0;
Timer ee_clock_timer;

jak1::AutoSplitterBlock g_auto_splitter_block_jak1;

void kmachine_init_globals_common() {
    std::memset(pad_dma_buf, 0, sizeof(pad_dma_buf));
    isodrv = fakeiso;
    modsrc = 1;
    reboot_iop = 1;
    vif1_interrupt_handler = 0;
    vblank_interrupt_handler = 0;
    ee_clock_timer = Timer();
}

void InitCD() {}
void InitVideo() {}
void InitSoundScheme() {}

namespace jak1 {
// jak1::kboot_init_globals lives in jak1/kboot.cpp upstream as an empty
// body; we don't compile that TU because it transitively #includes
// jak1/kmachine.h whose graphics deps don't cross-compile here. Same
// empty body, lives in compat instead.
void kboot_init_globals() {}
}  // namespace jak1
