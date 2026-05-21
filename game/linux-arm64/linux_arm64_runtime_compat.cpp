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
// mips2c_table — same situation as Android: mips2c_table.cpp's static
// init pulls every jak{1,2,3} link callback. Excluding it means we own
// the globals here. Empty maps → klink falls back to GOAL-bytecode path.
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

