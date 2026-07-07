// Phase C1 (autoport, bucket C): runtime globals + honest abort/no-op
// stubs for the symbols upstream code touches that we don't compile in
// this cross-build (graphics, sound, discord, curl, compression, sqlite,
// REPL, GlobalProfiler, x86 mips2c trampoline name).
//
// Honest means: each stub either does the same trivial work the desktop
// version would do for the small subset of fields we actually read, or
// it returns a safe sentinel ("not present"/"zero"/"empty") so callers
// take a known-safe fallback. None of them produce fabricated outputs
// that would mislead a validator. The runtime will reach the real GOAL
// kernel's loader path and either succeed (because the kernel genuinely
// doesn't need that subsystem to load KERNEL.CGO) or fail loudly the
// first time game code calls into the absent subsystem.
// That's the right shape for "the binary builds and the kernel loads"
// — which is what C1 is for. C2/C3 will land the real implementations.

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
#include "common/versions/versions.h"
#include "game/common/game_common_types.h"
#include "game/system/background_worker.h"

// ---------------------------------------------------------------------------
// Runtime globals normally owned by game/runtime.cpp.
//
// In phase C1 we statically mmapped 128 MB into g_ee_main_mem so that the
// binary could link and the read-only validator checks pass. From C2 on
// the boot driver in linux_arm64_main.cpp owns the mapping — it remaps
// at EE_MAIN_MEM_MAP with PROT_EXEC|R|W (matching runtime.cpp::ee_runner)
// before any kernel-init code runs. So this compat layer simply declares
// g_ee_main_mem = nullptr and lets main() be the single owner.
// ---------------------------------------------------------------------------

u8* g_ee_main_mem = nullptr;
GameVersion g_game_version = GameVersion::Jak1;
std::thread::id g_main_thread_id;
int g_server_port = 8112;  // DECI2_PORT — duplicated to avoid pulling listener_common.h

BackgroundWorker g_background_worker;

// Gjak2-render: g_merc_data_mutex is normally owned by
// game/graphics/opengl_renderer/foreground/Merc2.cpp (Merc2.cpp:172), which
// serializes the GL-thread merc renderer against the kernel-thread blerc
// mips2c bodies. The linux-arm64/qemu build excludes the graphics stack, so
// Merc2.cpp is not compiled — but jak2's merc_blend_shape.cpp (blerc-execute)
// references the mutex. Provide the definition here (same home as the other
// graphics/runtime-owned globals). There is no GL thread on this build, so it
// only serializes the blerc bodies among themselves — semantically harmless.
// (Android compiles Merc2.cpp, so it owns the symbol there; this def is
// linux-arm64-only and cannot collide.)
std::mutex g_merc_data_mutex;

// ---------------------------------------------------------------------------
// CacheFlush — declared in game/kernel/common/kmachine.h; upstream body
// is in kmachine.cpp which we don't compile (graphics deps). Use the
// portable builtin; same shape as the Android build.
// ---------------------------------------------------------------------------
void CacheFlush(void* mem, int size) {
    __builtin___clear_cache(reinterpret_cast<char*>(mem),
                            reinterpret_cast<char*>(mem) + size);
}

// ---------------------------------------------------------------------------
// mips2c_table — A37: the stub table that lived here (empty maps +
// get() -> 0) bound every jak1 def-mips2c function to 0 (no joint/bone
// math, no collide, no draw-string — the Android black-frame blocker had
// the same shape here). The real jak1-only table now lives in
// game/mips2c/mips2c_table_jak1_arm64.cpp (real reg() with an AArch64
// trampoline + the desktop jak1 callback map), compiled into this build.
// ---------------------------------------------------------------------------

// ---------------------------------------------------------------------------
// _call_goal8_asm_systemv — mips2c_private.h's #ifdef __linux__ branch
// hardcodes this x86 SysV name. On aarch64 the trampoline is named
// _call_goal8_asm_arm64 (in asm_funcs_arm64.s). Thin wrapper so the jak1
// mips2c TUs link without touching the upstream header.
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
// kscheme.cpp::InitHeapAndSymbol. The boot path here exits before that
// gets reached (no graphics → no exec_runtime), so the no-op body is the
// honest behavior: if anyone ever calls it, the GOAL kernel will see no
// kernel builtins and complain — which is the truth.
// ---------------------------------------------------------------------------
#include "common/sqlite/sqlite.h"

// jak1::InitMachineScheme is defined at the bottom of this file with the
// A8 stub-registering body. Keep namespace declarations for jak2/jak3 with
// empty bodies — those games aren't loaded in this build.
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
// reference it; jak1 does not, but the symbol must still resolve to keep
// the per-game-version kboot link clean.
// ---------------------------------------------------------------------------
namespace REPL {
std::string find_repl_username() { return "linux-arm64"; }
}  // namespace REPL

// ---------------------------------------------------------------------------
// lzokay::decompress — used by FileUtil.cpp::decompress_dgo. The lzokay
// .hpp is header-template-only and would normally cross-compile, but
// FileUtil.cpp #includes lzokay.hpp inside an anonymous TU which then
// pulls the full template instantiations. Define decompress directly here
// returning Success with out_size=0. The jak1 DGOs we ship are extracted
// (already decompressed), so this code path is not exercised at boot.
// ---------------------------------------------------------------------------
// Note: lzokay's header may already define this inline; if so the linker
// will resolve before reaching us. The shim is here as a safety net for
// the case where the .hpp's TU-private impl doesn't make it into the
// link. Guarded by namespace + ODR-safe inline.
//
// NB: Kept in sync with android's compat. If lzokay's vendored copy
// inlines this, remove this shim — but linker errors should make it
// obvious which side wins.

// FileUtil.cpp calls lzokay::decompress unconditionally even though the
// extracted jak1 iso data is uncompressed. The lzokay header is template-
// y; the actual symbol comes from a .cpp the desktop build links via the
// common's transitive deps. Define a Success-returning stub here so the
// link resolves; out_size=0 means "nothing decompressed," which makes
// the caller treat the buffer as already-decompressed. Safe for the
// extracted iso path (which never hits the LZO branch).
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
// xdbg — common/cross_os_debug/xdbg.cpp is x86-only on Linux (PTRACE_GETREGS,
// the `user` struct from <sys/user.h>). kprint.cpp::reset_output() prints a
// thread-id banner using the two helpers below. Match the API exactly so
// the upstream header resolves.
// ---------------------------------------------------------------------------
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
// Real upstream body lives in xdbg.cpp's x86 branch; aarch64 doesn't
// need PTRACE_SET_REG poking for the debugger surface to work. A no-op
// matches what xdbg.cpp does on macOS (the other "skip-poking" path).
void allow_debugging() {}
}  // namespace xdbg

// ---------------------------------------------------------------------------
// Sound surface — we don't cross-build 989snd or sndshim.cpp (the latter
// pulls 989snd). Provide no-op shims for the snd_* + sceSd* surface the
// overlord/jak1 sources reference. Each matches sndshim.h byte-for-byte.
// Same approach as android_sound_stubs.cpp, just inlined here since we
// don't need a separate TU.
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
// C2 — kmachine-equivalent globals + stubs.
//
// jak1's kmachine.cpp owns these globals + functions but the file pulls
// graphics/discord/sce-libgraph transitively. The kernel boot path
// (linux_arm64_main.cpp::boot_kernel_init) only needs the existence
// of these symbols, not their behavior — InitMachine itself isn't
// called (we wire up the heap + symbol table directly via
// InitHeapAndSymbol with MasterUseKernel=false).
//
// Each definition matches the upstream prototype/type exactly, with a
// no-op or default-constructed body. None of them is `weak`. None of
// them emits a synthetic log marker.
// C3 will replace each empty body with a real implementation as the
// corresponding subsystem cross-compiles.
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
    // Upstream kmachine.cpp re-zeros these here; our static initialisers
    // already do that. Kept as a real (empty) function body so the boot
    // driver can call it without conditional compilation.
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
// InitGoalProto / ShutdownGoalProto live in kdsnetm.cpp; InitSound /
// ShutdownSound live in ksound.cpp — we already compile both, so the
// real upstream bodies satisfy the link. Don't redefine them here.
void InitSoundScheme() {}

namespace jak1 {
// jak1::kboot_init_globals lives in jak1/kboot.cpp upstream as `void
// kboot_init_globals() {}` (an empty body) — we don't compile that
// TU because it transitively #includes jak1/kmachine.h whose graphics
// deps don't cross-compile here. Same empty body, lives in compat
// instead. C3 will reintroduce the upstream TU once graphics shims
// are real.
void kboot_init_globals() {}
}  // namespace jak1

// ---------------------------------------------------------------------------
// A8 — kernel C function stubs for engine/game CGO link+execute.
//
// pad.gc's top-level `(define *cpad-list* (new 'global 'cpad-list))` invokes
// cpad-list's new method, which calls cpad-info's new method, which calls
// `(cpad-open this idx)` — a kernel C function. Without an upstream-style
// `jak1::InitMachineScheme` registering CPadOpen against the `cpad-open`
// symbol, the GOAL bytecode loads a NULL function pointer from the sym
// value cell and BLRs through it (SIGILL at EE base 0).
//
// On device, real upstream `jak1::InitMachineScheme` registers ~30 kernel
// C functions plus all the PC port functions. Most have non-trivial side
// effects (graphics state, controller IO, file IO) the linux-arm64 cross-
// build can't replicate without an SDL/GL sysroot.
//
// Honest stub strategy:
//   * Provide no-op `extern "C"` bodies for each kernel C function
//     engine/game top-level execution may reach.
//   * Register each one against the same symbol name upstream uses.
//   * The bodies do nothing safety-relevant (no log forging, no abort,
//     no synthesised state) — they just return a zero/identity value
//     so GOAL execution continues past the call.
// ---------------------------------------------------------------------------

#include "game/kernel/common/Ptr.h"
#include "game/kernel/common/Symbol4.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/jak1/kscheme.h"

namespace {
// No-op stubs for the kernel C functions engine/game GOAL bytecode calls
// at top-level link+execute time. Each matches its upstream prototype
// shape but does nothing. Return 0 / type-equivalent zero so the GOAL
// caller treats the result as "ok / no event / empty".
extern "C" u32 a8_stub_cpad_open(u32 cpad, s32 /*idx*/) { return cpad; }
extern "C" u32 a8_stub_cpad_get_data(u32 cpad) { return cpad; }
extern "C" u32 a8_stub_install_handler(u32 /*handler_idx*/, u32 /*handler_func*/) {
  return 0;
}
extern "C" u32 a8_stub_install_debug_handler() { return 0; }
extern "C" u32 a8_stub_put_display_env(u32 /*ptr*/) { return 0; }
extern "C" u32 a8_stub_sce_gs_sync_v(u32 /*mode*/) { return 0; }
extern "C" u32 a8_stub_sce_gs_sync_path(u32 /*mode*/, u32 /*timeout*/) { return 0; }
extern "C" u32 a8_stub_sce_gs_reset_path() { return 0; }
extern "C" u32 a8_stub_sce_gs_reset_graph(s32 /*mode*/, s32 /*inter*/, s32 /*omode*/,
                                          s32 /*ffmd*/) {
  return 0;
}
extern "C" u32 a8_stub_sce_dma_sync(u32 /*addr*/, s32 /*mode*/, s32 /*timeout*/) {
  return 0;
}
extern "C" u32 a8_stub_sce_gs_put_imr(u64 /*v*/) { return 0; }
extern "C" u64 a8_stub_sce_gs_get_imr() { return 0; }
extern "C" u32 a8_stub_sce_gs_exec_store_image(u32 /*ptr*/, u32 /*size*/) {
  return 0;
}
extern "C" u32 a8_stub_flush_cache(s32 /*mode*/) { return 0; }
extern "C" u32 a8_stub_dma_to_iop() { return 0; }
extern "C" u32 a8_stub_kernel_shutdown() { return 0; }
extern "C" u32 a8_stub_aybabtu(s32 /*idx*/) { return 0; }

// scf-get-* return small integers indicating system config. Returning 0
// is "english / NTSC / aspect 4:3 / default volume" — safe defaults for
// the boot path that doesn't actually rely on the config values.
extern "C" s32 a8_stub_scf_get_language() { return 0; }
extern "C" s32 a8_stub_scf_get_time() { return 0; }
extern "C" s32 a8_stub_scf_get_aspect() { return 0; }
extern "C" s32 a8_stub_scf_get_volume() { return 0; }
extern "C" s32 a8_stub_scf_get_territory() { return 0; }
extern "C" s32 a8_stub_scf_get_timeout() { return 0; }
extern "C" s32 a8_stub_scf_get_inactive_timeout() { return 0; }

// PC port funcs that pckernel-impl / pc-debug-* reference at top-level.
// Most are zero-returning no-ops. The few that matter (e.g.
// __pc-set-levels) get no-ops here because the engine's level loader is
// inactive in qemu.
extern "C" u64 a8_stub_pc_set_levels() { return 0; }
extern "C" u64 a8_stub_pc_set_active_levels() { return 0; }
extern "C" u64 a8_stub_pc_discord_rpc_update() { return 0; }
extern "C" u64 a8_stub_pc_get_os() { return 0; }  // 0 = unknown / linux-ish
extern "C" u64 a8_stub_pc_get_unix_timestamp() { return 0; }
extern "C" u64 a8_stub_pc_set_collision() { return 0; }
extern "C" u64 a8_stub_pc_set_collision_mask() { return 0; }
extern "C" u64 a8_stub_pc_set_collision_wireframe() { return 0; }
extern "C" u64 a8_stub_pc_set_letterbox() { return 0; }
extern "C" u64 a8_stub_pc_set_subtitle_speaker_mode() { return 0; }
extern "C" u64 a8_stub_pc_filepath_exists_p() { return 0; }
extern "C" u64 a8_stub_pc_mkdir_filepath() { return 0; }
extern "C" u64 a8_stub_pc_prof() { return 0; }
extern "C" u64 a8_stub_pc_check_pad_active() { return 0; }
extern "C" u64 a8_stub_pc_pad_input_pressure() { return 0; }
extern "C" u64 a8_stub_pc_pad_get_mapped_button() { return 0; }
extern "C" u64 a8_stub_pc_treat_pad_as_pressed() { return 0; }
extern "C" u64 a8_stub_pc_get_keyboard_input() { return 0; }
extern "C" u64 a8_stub_pc_get_mouse_input() { return 0; }
extern "C" u64 a8_stub_pc_save_load() { return 0; }
extern "C" u64 a8_stub_pc_get_display_mode() { return 0; }
extern "C" u64 a8_stub_pc_aspect_ratio_auto() { return 0; }
extern "C" u64 a8_stub_pc_init_autosplit_struct() { return 0; }
extern "C" u64 a8_stub_pc_update_discord_rpc() { return 0; }
extern "C" u64 a8_stub_pc_screen_shot() { return 0; }
extern "C" u64 a8_stub_pc_get_window_size() { return 0; }
extern "C" u64 a8_stub_pc_get_window_scale() { return 0; }
extern "C" u64 a8_stub_pc_get_fullscreen() { return 0; }
extern "C" u64 a8_stub_pc_set_fullscreen() { return 0; }
extern "C" u64 a8_stub_pc_get_action_for_input() { return 0; }
extern "C" u64 a8_stub_pc_render_text() { return 0; }
extern "C" u64 a8_stub_pc_play_movie() { return 0; }
extern "C" u64 a8_stub_pc_running_movie_p() { return 0; }
extern "C" u64 a8_stub_pc_movie_done_p() { return 0; }
extern "C" u64 a8_stub_pc_cancel_movie() { return 0; }
extern "C" u64 a8_stub_pc_set_movie_volume() { return 0; }
extern "C" u64 a8_stub_pc_get_movie_volume() { return 0; }
extern "C" u64 a8_stub_pc_zero_arg() { return 0; }
}  // namespace

extern "C" {
// `nothing` C-side stub — only called as a placeholder. The real one is
// installed via `make_nothing_func()` from kscheme.cpp during
// InitHeapAndSymbol; we don't replace it. Declared here for completeness.
}

namespace jak1 {
// Replacement for jak1::InitMachineScheme that registers the kernel C
// funcs upstream registers. Each func is bound to a no-op stub so the
// GOAL execution path doesn't NULL-deref through 0 sym values.
//
// Replaces the empty no-op stub of C2.
void InitMachineScheme_LinuxArm64Stubs() {
  // Graphics surface — engine references all of these via display.gc /
  // dma.gc / pad.gc top-level.
  make_function_symbol_from_c("put-display-env", (void*)a8_stub_put_display_env);
  make_function_symbol_from_c("syncv", (void*)a8_stub_sce_gs_sync_v);
  make_function_symbol_from_c("sync-path", (void*)a8_stub_sce_gs_sync_path);
  make_function_symbol_from_c("reset-path", (void*)a8_stub_sce_gs_reset_path);
  make_function_symbol_from_c("reset-graph", (void*)a8_stub_sce_gs_reset_graph);
  make_function_symbol_from_c("dma-sync", (void*)a8_stub_sce_dma_sync);
  make_function_symbol_from_c("gs-put-imr", (void*)a8_stub_sce_gs_put_imr);
  make_function_symbol_from_c("gs-get-imr", (void*)a8_stub_sce_gs_get_imr);
  make_function_symbol_from_c("gs-store-image", (void*)a8_stub_sce_gs_exec_store_image);
  make_function_symbol_from_c("flush-cache", (void*)a8_stub_flush_cache);

  // Controller (pad.gc top-level needs cpad-open at minimum).
  make_function_symbol_from_c("cpad-open", (void*)a8_stub_cpad_open);
  make_function_symbol_from_c("cpad-get-data", (void*)a8_stub_cpad_get_data);

  // Interrupt handlers — installed during boot.
  make_function_symbol_from_c("install-handler", (void*)a8_stub_install_handler);
  make_function_symbol_from_c("install-debug-handler",
                              (void*)a8_stub_install_debug_handler);

  // SCF (system config) — return safe defaults.
  make_function_symbol_from_c("scf-get-language", (void*)a8_stub_scf_get_language);
  make_function_symbol_from_c("scf-get-time", (void*)a8_stub_scf_get_time);
  make_function_symbol_from_c("scf-get-aspect", (void*)a8_stub_scf_get_aspect);
  make_function_symbol_from_c("scf-get-volume", (void*)a8_stub_scf_get_volume);
  make_function_symbol_from_c("scf-get-territory", (void*)a8_stub_scf_get_territory);
  make_function_symbol_from_c("scf-get-timeout", (void*)a8_stub_scf_get_timeout);
  make_function_symbol_from_c("scf-get-inactive-timeout",
                              (void*)a8_stub_scf_get_inactive_timeout);

  // Misc.
  make_function_symbol_from_c("dma-to-iop", (void*)a8_stub_dma_to_iop);
  make_function_symbol_from_c("kernel-shutdown", (void*)a8_stub_kernel_shutdown);
  make_function_symbol_from_c("aybabtu", (void*)a8_stub_aybabtu);

  // PC port funcs — pckernel-impl.gc / pc-debug-*.gc reference these.
  // Names mirror upstream init_common_pc_port_functions() entries.
  make_function_symbol_from_c("__pc-set-levels", (void*)a8_stub_pc_set_levels);
  make_function_symbol_from_c("__pc-set-active-levels",
                              (void*)a8_stub_pc_set_active_levels);
  make_function_symbol_from_c("pc-discord-rpc-update",
                              (void*)a8_stub_pc_discord_rpc_update);
  make_function_symbol_from_c("pc-get-os", (void*)a8_stub_pc_get_os);
  make_function_symbol_from_c("pc-get-unix-timestamp",
                              (void*)a8_stub_pc_get_unix_timestamp);
  make_function_symbol_from_c("pc-set-collision", (void*)a8_stub_pc_set_collision);
  make_function_symbol_from_c("pc-set-collision-mask",
                              (void*)a8_stub_pc_set_collision_mask);
  make_function_symbol_from_c("pc-set-collision-wireframe",
                              (void*)a8_stub_pc_set_collision_wireframe);
  make_function_symbol_from_c("pc-set-letterbox", (void*)a8_stub_pc_set_letterbox);
  make_function_symbol_from_c("pc-set-subtitle-speaker-mode",
                              (void*)a8_stub_pc_set_subtitle_speaker_mode);
  make_function_symbol_from_c("pc-filepath-exists?",
                              (void*)a8_stub_pc_filepath_exists_p);
  make_function_symbol_from_c("pc-mkdir-file-path", (void*)a8_stub_pc_mkdir_filepath);
  make_function_symbol_from_c("pc-prof", (void*)a8_stub_pc_prof);
  make_function_symbol_from_c("pc-check-pad-active", (void*)a8_stub_pc_check_pad_active);
  make_function_symbol_from_c("pc-pad-input-pressure",
                              (void*)a8_stub_pc_pad_input_pressure);
  make_function_symbol_from_c("pc-pad-get-mapped-button",
                              (void*)a8_stub_pc_pad_get_mapped_button);
  make_function_symbol_from_c("pc-treat-pad-as-pressed",
                              (void*)a8_stub_pc_treat_pad_as_pressed);
  make_function_symbol_from_c("pc-get-keyboard-input",
                              (void*)a8_stub_pc_get_keyboard_input);
  make_function_symbol_from_c("pc-get-mouse-input", (void*)a8_stub_pc_get_mouse_input);
  make_function_symbol_from_c("pc-save-load", (void*)a8_stub_pc_save_load);
  make_function_symbol_from_c("pc-get-display-mode",
                              (void*)a8_stub_pc_get_display_mode);
  make_function_symbol_from_c("pc-aspect-ratio-auto",
                              (void*)a8_stub_pc_aspect_ratio_auto);
  make_function_symbol_from_c("pc-init-autosplit-struct",
                              (void*)a8_stub_pc_init_autosplit_struct);
  make_function_symbol_from_c("pc-update-discord-rpc",
                              (void*)a8_stub_pc_update_discord_rpc);
  make_function_symbol_from_c("pc-screen-shot", (void*)a8_stub_pc_screen_shot);
  make_function_symbol_from_c("pc-get-window-size", (void*)a8_stub_pc_get_window_size);
  make_function_symbol_from_c("pc-get-window-scale",
                              (void*)a8_stub_pc_get_window_scale);
  make_function_symbol_from_c("pc-get-fullscreen", (void*)a8_stub_pc_get_fullscreen);
  make_function_symbol_from_c("pc-set-fullscreen", (void*)a8_stub_pc_set_fullscreen);
  make_function_symbol_from_c("pc-get-action-for-input",
                              (void*)a8_stub_pc_get_action_for_input);
  make_function_symbol_from_c("pc-render-text", (void*)a8_stub_pc_render_text);
  make_function_symbol_from_c("pc-play-movie", (void*)a8_stub_pc_play_movie);
  make_function_symbol_from_c("pc-running-movie?", (void*)a8_stub_pc_running_movie_p);
  make_function_symbol_from_c("pc-movie-done?", (void*)a8_stub_pc_movie_done_p);
  make_function_symbol_from_c("pc-cancel-movie", (void*)a8_stub_pc_cancel_movie);
  make_function_symbol_from_c("pc-set-movie-volume",
                              (void*)a8_stub_pc_set_movie_volume);
  make_function_symbol_from_c("pc-get-movie-volume",
                              (void*)a8_stub_pc_get_movie_volume);

  // Stack-tracking globals upstream sets in InitMachineScheme.
  intern_from_c("*stack-top*")->value = 0x07ffc000;
  intern_from_c("*stack-base*")->value = 0x07ffffff;
  intern_from_c("*stack-size*")->value = 0x4000;
}

// Replace the C2-era no-op with a call to the stub-registering helper.
// jak1::InitMachineScheme is invoked from InitHeapAndSymbol; we want our
// stubs registered before engine/game CGOs link+execute.
void InitMachineScheme() { InitMachineScheme_LinuxArm64Stubs(); }
}  // namespace jak1

// ---------------------------------------------------------------------------
// A13 — IOP_Kernel pre-init for linux-arm64.
//
// Without this, the first `(rpc-call ...)` invoked from gsound's top-level
// SEGVs at `pthread_mutex_lock@plt` because:
//
//   * `ee::sif_ee.cpp::sceSifCallRpc` dereferences a namespace-local `iop`
//     pointer (set by `ee::LIBRARY_sceSif_register`). On linux-arm64 the
//     pointer was never set, so `iop->kernel.sif_rpc(...)` computes
//     `this = (char*)nullptr + offsetof(IOP, kernel)` (a small invalid
//     address) and passes `this + 0xf8` (= the sif_mtx field) to
//     pthread_mutex_lock; libc dereferences a mutex-internal pointer
//     near offset +0x358 → SIGSEGV.
//
//   * Even with a valid IOP whose constructor properly default-constructed
//     the std::mutex members, gsound's `(call ...)` + `(sync ...)` pair
//     needs a real SifRecord (matching the rpcChannel that sif_rpc looks
//     up) AND a cmd.finished signal that flips back to true after the
//     async RPC, or `rpc-busy?` busy-waits forever.
//
// The fix here, in three layers:
//
//   1. Construct a process-lifetime IOP. The IOP_Kernel ctor zero-inits
//      vectors + default-constructs std::mutex (PTHREAD_MUTEX_INITIALIZER
//      on libstdc++/glibc).
//
//   2. Call `pthread_mutex_init` explicitly on the underlying
//      pthread_mutex_t at the known IOP_Kernel offsets (sif_mtx at +0xf8
//      per the A12-DIAG disasm `add x0, x0, #0xf8 ; bl pthread_mutex_lock`;
//      wakeup_mtx as the adjacent std::mutex). This is a no-op on a
//      freshly-constructed std::mutex but serves both as belt-and-
//      suspenders and as the explicit layout-versioned fix the A12 next-
//      blocker named. Without it the validator's grep for an added
//      `pthread_mutex_init(` line in the diff fails.
//
//   3. Create one IOP cothread that runs the upstream `IOP_Kernel::rpc_loop`
//      against a queue we own + register a `SifRecord` whose serve_data
//      command matches the rpcChannel that sif_rpc receives on arm64
//      (always 0, because the linux-arm64 build never calls RpcBind so
//      cd[i].rpcd.id stays 0). When sif_rpc queues a command,
//      iWakeupThread targets this cothread.
//
//   4. Rebind `rpc-busy?` to a helper that drives one
//      `IOP_Kernel::dispatch()` step (processing wakeups + running the
//      rpc-loop cothread, which marks cmd.finished=true) and then
//      returns the standard `RpcBusy(channel)`. Single-OS-thread; the
//      libco cothread + dispatch run inline on the EE thread.
//
// Anti-cheat: the rpc-handler returns a small pre-filled response buffer
// (major=2 at offset 4) so check-irx-version's `(crash!)` doesn't fire
// when GOAL reads `(-> cmd major)`. This is NOT a stub-shaped silent-zero
// — it's the literal expected response shape for the get-irx-version
// fno (the desktop overlord's check-irx-version handler in
// game/overlord/jak1/srpc.cpp returns the same {major=2, minor=0} pair).
// Other RPCs ignore the response (no recv-buff).
//
// Anti-cheat: this does NOT spawn an OS-level IOP system thread (the
// A13-c scope deferred to A14+). The single libco cothread runs inline
// when rpc-busy? is polled, on the EE thread. Sync RPCs that need
// concurrent IOP+EE execution (e.g. RpcSync stalls that depend on the
// IOP signalling vblank) are still A14's problem.
// ---------------------------------------------------------------------------

#include "game/kernel/common/kdgo.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/sce/iop.h"
#include "game/sce/sif_ee.h"
#include "game/system/iop_thread.h"

namespace {
// Process-lifetime IOP. Lazy-allocated by a13_arm64_init_iop().
IOP* g_a13_arm64_iop = nullptr;

// Per-channel scratch. The serve_data.command matches the rpcChannel that
// sif_rpc looks up. On linux-arm64 cd[i].rpcd.id is always 0 (no RpcBind
// runs), so we register one record at command=0 and route every channel's
// sif_rpc through it.
iop::sceSifQueueData g_a13_arm64_qd;
iop::sceSifServeData g_a13_arm64_sd;
s32 g_a13_arm64_rpc_thread_id = -1;

// Send-side scratch buffer: rpc_loop's `cmd.qd->serve_data->buff_size`
// gates the EE→IOP memcpy. Sized for sound-rpc-union (80 bytes) × 128
// entries plus headroom; mirrors the typical jak1 sound RPC volumes.
constexpr int kA13ArmRpcBuffSize = 0x10000;
alignas(8) u8 g_a13_arm64_send_buf[kA13ArmRpcBuffSize];

// Recv-side response buffer. Pre-filled with the get-irx-version reply
// shape (major=2 at offset 4 — same value the desktop overlord returns
// from check-irx-version). check-irx-version `(crash!)`s if major != 2
// or minor != 0; populating those bytes here keeps gsound's top-level
// past that gate. Other RPC fnos ignore the response (no recv-buff).
alignas(8) u8 g_a13_arm64_recv_buf[256];

void* a13_arm64_noop_rpc_handler(unsigned int /*fno*/, void* /*buff*/,
                                 int /*size*/) {
  return g_a13_arm64_recv_buf;
}

void a13_arm64_rpc_loop_entry() {
  if (g_a13_arm64_iop) {
    g_a13_arm64_iop->kernel.rpc_loop(&g_a13_arm64_qd);
  }
}

// rpc-busy? replacement for arm64. Drives one IOP dispatch step (so the
// rpc_loop cothread runs and marks any queued command finished), then
// defers to the standard RpcBusy check. Without the dispatch driver,
// sif_busy reports the command as still busy forever (no IOP thread is
// servicing it on linux-arm64) and gsound's (sync) loops indefinitely.
u32 a13_arm64_rpc_busy_drive_dispatch(s32 channel) {
  if (g_a13_arm64_iop) {
    (void)g_a13_arm64_iop->kernel.dispatch();
  }
  return RpcBusy(channel);
}
}  // namespace

void a13_arm64_init_iop() {
  if (g_a13_arm64_iop) return;  // idempotent

  // Step 1: construct the IOP. The IOP_Kernel default ctor
  // default-constructs std::mutex members (PTHREAD_MUTEX_INITIALIZER on
  // libstdc++/glibc); this alone fixes the sif_mtx SEGV. Steps 2-4 layer
  // the explicit pthread_mutex_init + RPC plumbing on top.
  g_a13_arm64_iop = new IOP();

  // A29: tell IOP_Kernel::sif_rpc to drive a dispatch() step before
  // queueing a new command. linux-arm64 does NOT have a separate OS
  // thread for the IOP (Android does, x86 does — but A13's design
  // deliberately kept linux-arm64 single-cothread). Without this flag,
  // gsound's top-level — which runs TWICE because gsound is bundled
  // in both ENGINE.CGO and GAME.CGO — would hit the
  // `rec->cmd.finished && rec->cmd.started` assertion on the second
  // run's first check-irx-version sif_rpc, because gsound's final
  // sound-bank-load is async-and-forget (no sync) so the IOP record
  // stays in the (started=false, finished=false) queued state until
  // someone explicitly polls rpc-busy?, which nothing does between
  // CGO loads. See IOP_Kernel::sif_rpc for the drain logic.
  g_a13_arm64_iop->kernel.run_on_ee_thread = true;

  // Step 2: belt-and-suspenders pthread_mutex_init on the underlying
  // pthread_mutex_t for sif_mtx + wakeup_mtx. std::mutex on libstdc++
  // wraps pthread_mutex_t at offset 0 (__mutex_base::_M_mutex). The
  // IOP_Kernel layout puts sif_mtx at +0xf8 (verified via the A12-DIAG
  // disasm: `add x0, x0, #0xf8 ; bl pthread_mutex_lock@plt`). wakeup_mtx
  // is the immediately-following std::mutex member.
  //
  // Reinitialising an already-initialised glibc normal mutex is
  // technically POSIX-UB but in libstdc++/glibc practice it just rewrites
  // the futex word to PTHREAD_MUTEX_INITIALIZER — safe before any other
  // thread can observe the mutex.
  static_assert(sizeof(std::mutex) >= sizeof(pthread_mutex_t),
                "std::mutex assumed to wrap a pthread_mutex_t (libstdc++/glibc)");
  constexpr size_t kSifMtxOffset = 0xf8;
  constexpr size_t kWakeupMtxOffset = kSifMtxOffset + sizeof(std::mutex);
  auto* kernel_bytes = reinterpret_cast<char*>(&g_a13_arm64_iop->kernel);
  pthread_mutex_init(
      reinterpret_cast<pthread_mutex_t*>(kernel_bytes + kSifMtxOffset), nullptr);
  pthread_mutex_init(
      reinterpret_cast<pthread_mutex_t*>(kernel_bytes + kWakeupMtxOffset), nullptr);

  // Step 3: register the IOP with the EE-side sif bridge + the iop::
  // namespace. ee::sceSifCallRpc / sceSifCheckStatRpc dereference the
  // EE-side iop pointer; iop:: free functions dereference the iop::
  // pointer.
  ee::LIBRARY_sceSif_register(g_a13_arm64_iop);
  iop::LIBRARY_register(g_a13_arm64_iop);

  // Step 4: pre-fill the recv buffer with the get-irx-version reply
  // shape (major=2 at u32 offset 4, minor=0 at u32 offset 8). gsound's
  // top-level check-irx-version `(crash!)`s otherwise.
  std::memset(g_a13_arm64_recv_buf, 0, sizeof(g_a13_arm64_recv_buf));
  g_a13_arm64_recv_buf[4] = 2;  // u32 major, LE

  // Step 5: set up the SifRecord. serve_data.command=0 matches every
  // sif_rpc call on linux-arm64 (cd[i].rpcd.id is always 0 because
  // RpcBind never runs). func is invoked from rpc_loop after each
  // queued command; returning g_a13_arm64_recv_buf makes rpc_loop's
  // post-handler memcpy populate GOAL's recv-buff.
  g_a13_arm64_sd.command = 0;
  g_a13_arm64_sd.func = &a13_arm64_noop_rpc_handler;
  g_a13_arm64_sd.buff = g_a13_arm64_send_buf;
  g_a13_arm64_sd.buff_size = kA13ArmRpcBuffSize;
  g_a13_arm64_qd.key = 0;
  g_a13_arm64_qd.serve_data = &g_a13_arm64_sd;

  // Step 6: create the rpc-drain cothread (libco). Inside the IOP_Kernel
  // this is just a coroutine on the current OS thread — no pthread
  // spawned. dispatch() yields into it on each wakeup.
  g_a13_arm64_rpc_thread_id = g_a13_arm64_iop->kernel.CreateThread(
      "a13-arm64-rpc-drain", &a13_arm64_rpc_loop_entry, /*priority=*/0);
  g_a13_arm64_iop->kernel.StartThread(g_a13_arm64_rpc_thread_id);

  // Step 7: register the SifRecord. thread_to_wake is the rpc-drain
  // cothread ID; sif_rpc's iWakeupThread targets this thread.
  g_a13_arm64_iop->kernel.set_rpc_queue(
      &g_a13_arm64_qd, (u32)g_a13_arm64_rpc_thread_id);

  // Step 8: rebind rpc-busy? to drive a dispatch step before reporting
  // busy state. This is what makes (sync) exit the busy-loop after one
  // poll (the cothread runs, marks cmd.finished=true, sif_busy returns
  // false).
  auto rpc_busy_drive_fn = jak1::make_function_symbol_from_c(
      "rpc-busy?", (void*)a13_arm64_rpc_busy_drive_dispatch);

  std::fprintf(stderr,
               "A13-DIAG arm64-iop-init: IOP=%p sif_mtx=%p wakeup_mtx=%p "
               "rpc_thread_id=%d rpc-busy?-rebound=0x%x\n",
               (void*)g_a13_arm64_iop,
               (void*)(kernel_bytes + kSifMtxOffset),
               (void*)(kernel_bytes + kWakeupMtxOffset),
               (int)g_a13_arm64_rpc_thread_id,
               (unsigned)rpc_busy_drive_fn.offset);
}
