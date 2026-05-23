// Phase 13/18/20 (autoport): JNI entrypoints for libgk.so on Android.
//
// libgk.so contains a curated subset of the OpenGOAL kernel
// (game/kernel/common/{kboot,kmalloc,ksocket}.cpp etc.) plus Android-friendly
// compat for logging and the runtime globals. The JNI surface here is the
// bridge the Activity (phase 13) uses to drive boot, plumb game selection
// from per-flavor resources, and forward touch input into the runtime.
//
// Phase 20: gk_sdl_main no longer demos a clear-color loop; it assembles
// the desktop-style argv (--game/--portable/-fakeiso/-iso-data) and calls
// into goal_main (android/android_goal_main.cpp). The game name + data
// root are pushed in from the Java side via NativeGk.setSelectedGame and
// NativeGk.setDataRoot before SDLActivity.super.onCreate runs, so by the
// time the SDL thread dlsym's gk_sdl_main the globals below are populated.

#include <android/input.h>
#include <android/log.h>
#include <jni.h>
#include <setjmp.h>
#include <signal.h>
#include <ucontext.h>

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "common/versions/versions.h"

#include "common/goal_constants.h"

#include "game/kernel/common/kboot.h"
#include "game/kernel/common/klink.h"
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/kmemcard.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/common/ksocket.h"
#include "game/runtime.h"

// A11: jak1::InitHeapAndSymbol exposes a chainable hook that fires
// between the kernel-CGO load and the kernel-version check. We chain
// onto whatever android_runtime_compat.cpp installed and add a sym-bind
// of `__pc-get-mips2c` so the texture CGO's def-mips2c top-level can
// resolve mips2c funcs. Without this, the sym slot reads 0 at the BLR
// site and the host(0)=ee_base path SIGILLs (texture-sym-zero, per the
// A10 next-blocker report).
extern "C" void (*g_jak1_pre_kernel_version_check_hook)(void);

#include "android_input_audio.h"
#include "android_renderer.h"

// goal_main lives in android_goal_main.cpp for Android, game/main.cpp for
// desktop. C++ linkage on both sides — matches the forward declaration at
// the top of game/main.cpp.
int goal_main(int argc, char** argv);

namespace {
constexpr const char* kGkVersion =
    "OpenGOAL gk (Android arm64-v8a, autoport phase 13 runtime)";
constexpr const char* kGkLogTag = "opengoal-gk";

// Phase 13: the touch event ring is a placeholder until SDL is wired up
// natively. We just log incoming events so they're observable in logcat
// and keep an atomic counter so smoke tests can assert input plumbing.
// Phase 14+ replace this with SDL_PushEvent().
std::atomic<uint32_t> g_touch_events_seen{0};

// Repeat startGame calls (e.g. after a configuration change) must be idempotent.
std::atomic<bool> g_runtime_booted{false};

// Phase 20: game name + data root pushed from Java via the setSelectedGame /
// setDataRoot JNI methods on NativeGk. Both are strdup'd at the JNI boundary
// and intentionally never freed — they live for the process lifetime, and
// gk_sdl_main reads them on the SDL thread without further synchronisation
// because setSelectedGame / setDataRoot are guaranteed (by MainActivity) to
// complete before super.onCreate triggers the SDL thread.
const char* g_selected_game = nullptr;
const char* g_data_root = nullptr;

// Phase 27 (autoport): emit a load marker at .so load time so the validator
// can prove libgk.so reached dlopen() — the runtime's earliest observable
// signal. Marked __attribute__((constructor)) so it runs before any other
// libgk code, including the SDL JNI_OnLoad path. The validator greps
// logcat for the literal "libgk.so loaded" string.
__attribute__((constructor))
void gk_load_marker() {
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "libgk.so loaded (%s)", kGkVersion);
}
}  // namespace

extern "C" {

const char* gk_version_string(void) {
  return kGkVersion;
}

int gk_print_version(void) {
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag, "%s", kGkVersion);
  std::fprintf(stdout, "%s\n", kGkVersion);
  return 0;
}

int gk_init_runtime(void) {
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "gk_init_runtime: initializing kernel core");
  kboot_init_globals_common();
  kmalloc_init_globals_common();
  kprint_init_globals_common();
  InitListenerConnect();
  InitCheckListener();
  return 0;
}

namespace {
// A11 sym-bind-trace: chain a __pc-get-mips2c binder onto the
// pre_kernel_version_check hook android_runtime_compat installed at
// .so load time. After both constructors have finished (any caller of
// this helper runs after .so load), capturing the current hook value
// and replacing it with a lambda that calls the captured value first
// is safe. Idempotent via static-local guard: gk_sdl_main can be
// re-entered without double-chaining the lambda.
//
// Why not in gk_init_runtime: MainActivity never invokes
// NativeGk.init in the current Android flow (only setSelectedGame +
// setDataRoot are called before super.onCreate triggers the SDL
// thread). gk_sdl_main IS reached on every boot, so installation
// happens here just before goal_main.
void a11_install_pc_mips2c_hook_once() {
  static bool installed = false;
  if (installed) return;
  installed = true;
  static const auto prev = g_jak1_pre_kernel_version_check_hook;
  g_jak1_pre_kernel_version_check_hook = []() {
    if (prev) prev();
    klink_a11_ensure_pc_mips2c_bound();
    // A12 sym-bind: register `rpc-call`, `rpc-busy?`, `test-load-dgo-c`
    // (see klink.cpp::klink_a12_ensure_sound_rpc_bound for rationale).
    // Android's runtime-compat override of jak1::InitMachineScheme
    // similarly omits InitSoundScheme, so gsound's top-level BLR to
    // `rpc-call` lands at ee_base unless we bind here.
    klink_a12_ensure_sound_rpc_bound();
  };
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "A11-DIAG sym-bind-trace: chained "
                      "klink_a11_ensure_pc_mips2c_bound + "
                      "klink_a12_ensure_sound_rpc_bound onto "
                      "g_jak1_pre_kernel_version_check_hook (prev=%p)",
                      (void*)prev);
}
}  // namespace

// Boot the runtime for a specific game. Phase 13 only validates APK
// structure, so this stays light: it logs intent, initializes the kernel
// once, and stores the chosen game name. Phase 14+ replace the body with
// the equivalent of `game/main.cpp` (argv assembly and the runtime boot
// loop), reading game data from data_root via -fakeiso.
int gk_start_game(const char* game_name, const char* data_root) {
  if (!game_name) {
    game_name = "jak1";
  }
  if (!data_root) {
    data_root = "";
  }
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "gk_start_game: game='%s' data_root='%s'", game_name,
                      data_root);

  bool expected = false;
  if (g_runtime_booted.compare_exchange_strong(expected, true)) {
    gk_init_runtime();
  } else {
    __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                        "gk_start_game: runtime already booted");
  }
  return 0;
}

// Phase 18: SDL3 provides its own JNI_OnLoad (libSDL3.a → SDL_android.c).
// Both ours and SDL's would otherwise multiply-define the symbol. SDL's
// version sets up the JNI environment SDLActivity relies on, so keep
// theirs; the libgk-version banner is now emitted from gk_sdl_main.

JNIEXPORT jstring JNICALL
Java_org_opengoal_gk_NativeGk_version(JNIEnv* env, jclass /*clazz*/) {
  return env->NewStringUTF(kGkVersion);
}

JNIEXPORT jint JNICALL
Java_org_opengoal_gk_NativeGk_init(JNIEnv* /*env*/, jclass /*clazz*/) {
  return gk_init_runtime();
}

JNIEXPORT jint JNICALL
Java_org_opengoal_gk_NativeGk_startGame(JNIEnv* env, jclass /*clazz*/,
                                       jstring j_game_name,
                                       jstring j_data_root) {
  const char* game_name =
      j_game_name ? env->GetStringUTFChars(j_game_name, nullptr) : nullptr;
  const char* data_root =
      j_data_root ? env->GetStringUTFChars(j_data_root, nullptr) : nullptr;

  const jint rc = gk_start_game(game_name, data_root);

  if (game_name) {
    env->ReleaseStringUTFChars(j_game_name, game_name);
  }
  if (data_root) {
    env->ReleaseStringUTFChars(j_data_root, data_root);
  }
  return rc;
}

// Phase 20 (autoport): SDL3 entry point invoked by SDLActivity via
// nativeRunMain → dlsym("gk_sdl_main"). The argc/argv SDL hands us are
// derived from MainActivity.getArguments(); we ignore them here and rebuild
// the canonical desktop argv from the JNI-pushed globals instead, so the
// runtime sees exactly what the desktop entry would have seen.
namespace {
// A6 attempt 5: safe-read helper. The pre-A6 handler did a raw memcpy of
// pc-256..pc+16 every time, which secondary-SEGV'd when the first signal
// was a BLR-to-NULL with PC = g_ee_main_mem (the read range crosses the
// PROT_NONE / unmapped page below EE). The secondary SEGV obscured the
// real GOAL bytecode bytes around the BLR. We install a tiny nested
// handler with siglongjmp so a failed read just returns false and lets
// us move on to the next address.
namespace gk_diag {
sigjmp_buf safe_read_env;
volatile sig_atomic_t safe_read_jumped = 0;
void safe_read_handler(int /*sig*/, siginfo_t* /*info*/, void* /*ctx*/) {
  safe_read_jumped = 1;
  siglongjmp(safe_read_env, 1);
}
bool safe_read_u32(uintptr_t addr, uint32_t* out) {
  struct sigaction old_segv{}, old_bus{}, sa{};
  sa.sa_sigaction = &safe_read_handler;
  sa.sa_flags = SA_SIGINFO | SA_NODEFER;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGSEGV, &sa, &old_segv);
  sigaction(SIGBUS, &sa, &old_bus);
  bool ok = false;
  if (sigsetjmp(safe_read_env, 1) == 0) {
    safe_read_jumped = 0;
    memcpy(out, reinterpret_cast<const void*>(addr), 4);
    ok = !safe_read_jumped;
  }
  sigaction(SIGSEGV, &old_segv, nullptr);
  sigaction(SIGBUS, &old_bus, nullptr);
  return ok;
}

// A11-DIAG: identify the sym whose value slot the failing BLR loaded
// from. Mirrors linux_arm64_main.cpp::gk_diag::dump_sym_name_at_slot —
// both handlers share the same `texture-sym-zero` line shape so the
// device logcat and the qemu_repro stderr trace can be diff'd directly.
//
// Layout (jak1::InitHeapAndSymbol, see kscheme.cpp ~L1770):
//   SymbolTable2 .. LastSymbol            : Symbol{u32} value slots
//   slot + SYM_INFO_OFFSET                : SymInfo{u32 hash; u32 str_off}
//   g_ee_main_mem + str_off + 4           : null-terminated UTF-8 name
//
// Safe-read each field so a malformed slot can't secondary-SEGV the
// handler — the same protection the existing LR/PC byte loop uses.
bool dump_sym_name_at_slot(uintptr_t slot_host_addr) {
  if (!g_ee_main_mem) return false;
  const uintptr_t ee_lo = reinterpret_cast<uintptr_t>(g_ee_main_mem);
  const uintptr_t ee_hi = ee_lo + EE_MAIN_MEM_SIZE;
  if (slot_host_addr < ee_lo || slot_host_addr >= ee_hi) return false;

  const uintptr_t sym_lo = ee_lo + SymbolTable2.offset;
  const uintptr_t sym_hi = ee_lo + LastSymbol.offset;
  const bool in_sym_range = (slot_host_addr >= sym_lo && slot_host_addr < sym_hi);

  uint32_t slot_value = 0;
  if (!safe_read_u32(slot_host_addr, &slot_value)) return false;

  const uintptr_t info_addr = slot_host_addr + jak1::SYM_INFO_OFFSET;
  if (info_addr + 8 > ee_hi) return false;
  uint32_t hash = 0, str_offset = 0;
  if (!safe_read_u32(info_addr, &hash)) return false;
  if (!safe_read_u32(info_addr + 4, &str_offset)) return false;

  char name_buf[129];
  name_buf[0] = 0;
  if (str_offset != 0 && str_offset < EE_MAIN_MEM_SIZE) {
    const uintptr_t name_host = ee_lo + str_offset + 4;  // skip String::len
    for (size_t i = 0; i + 4 < sizeof(name_buf); i += 4) {
      uint32_t word = 0;
      if (!safe_read_u32(name_host + i, &word)) break;
      bool stop = false;
      for (int j = 0; j < 4; ++j) {
        char c = static_cast<char>((word >> (j * 8)) & 0xff);
        if (c == 0) { stop = true; break; }
        name_buf[i + j] = c;
      }
      if (stop) break;
      name_buf[i + 4] = 0;
    }
  }
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A11-DIAG texture-sym-zero: slot=0x%lx "
                      "value=0x%x info=0x%lx hash=0x%x str=0x%x name=\"%s\" "
                      "in_sym_range=%d",
                      (unsigned long)slot_host_addr, (unsigned)slot_value,
                      (unsigned long)info_addr, (unsigned)hash,
                      (unsigned)str_offset,
                      name_buf[0] ? name_buf : "<empty>", in_sym_range ? 1 : 0);
  return true;
}

// A12-DIAG: backward-provenance trace for stack-loaded fn-ptr=0 SIGILL.
// Mirrors game/linux-arm64/linux_arm64_main.cpp::dump_stack_fnptr_zero_chain
// — line shapes are identical so a device logcat and qemu_repro stderr
// are diff-able. See the qemu-side header comment for the chain shape.
void dump_stack_fnptr_zero_chain(uintptr_t lr, uintptr_t sp) {
  // Step 1: lr-4 must be BLR Xt.
  uint32_t blr_enc = 0;
  if (!safe_read_u32(lr - 4, &blr_enc)) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A12-DIAG stack-fnptr-zero: lr-4 unreadable");
    return;
  }
  if ((blr_enc & 0xFFFFFC1Fu) != 0xD63F0000u) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A12-DIAG stack-fnptr-zero: lr-4 enc=0x%08x is not BLR Xn",
                        (unsigned)blr_enc);
    return;
  }
  uint32_t blr_target_reg = (blr_enc >> 5) & 0x1f;

  // Step 2: count pre-decrement SP pushes.
  uint32_t push_bytes = 0;
  for (intptr_t d = -8; d >= -64; d -= 4) {
    uint32_t enc = 0;
    if (!safe_read_u32(lr + d, &enc)) break;
    bool is_stp_pre_sp = ((enc & 0xFFFF83E0u) == 0xA9BF03E0u);
    bool is_str_pre_sp = ((enc & 0xFFFFFFE0u) == 0xF81F0FE0u);
    if (!is_stp_pre_sp && !is_str_pre_sp) break;
    push_bytes += 16;
  }

  // Step 3: skip optional ADD Xt, Xt, X15 (GOAL→host).
  intptr_t scan_offset = -4 - (intptr_t)push_bytes - 4;
  {
    uint32_t add_enc = 0;
    if (safe_read_u32(lr + scan_offset, &add_enc)) {
      uint32_t expected =
          0x8B0F0000u | (blr_target_reg << 5) | blr_target_reg;
      if ((add_enc & 0xFFE0FFE0u) == expected) {
        scan_offset -= 4;
      }
    }
  }

  // Step 4: LDR Xt, [SP, #imm].
  intptr_t ldr_off = 0;
  uint32_t ldr_imm = 0;
  bool ldr_found = false;
  for (intptr_t d = scan_offset; d >= -240; d -= 4) {
    uint32_t enc = 0;
    if (!safe_read_u32(lr + d, &enc)) break;
    if ((enc & 0xFFC003E0u) != 0xF94003E0u) continue;
    uint32_t rt = enc & 0x1fu;
    if (rt != blr_target_reg) continue;
    ldr_imm = ((enc >> 10) & 0xfffu) * 8u;
    ldr_off = d;
    ldr_found = true;
    break;
  }
  if (!ldr_found) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A12-DIAG stack-fnptr-zero: no LDR X%u,[SP,#?] "
                        "in lr-240..lr-4 (BLR target X%u, push_bytes=%u) — "
                        "non-call_r64 shape",
                        (unsigned)blr_target_reg, (unsigned)blr_target_reg,
                        (unsigned)push_bytes);
    return;
  }
  uintptr_t slot_host = sp + (uintptr_t)push_bytes + (uintptr_t)ldr_imm;
  uint32_t slot_lo = 0, slot_hi = 0;
  uint64_t slot_val = 0;
  if (safe_read_u32(slot_host, &slot_lo) &&
      safe_read_u32(slot_host + 4, &slot_hi)) {
    slot_val = (uint64_t)slot_lo | ((uint64_t)slot_hi << 32);
  }
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A12-DIAG stack-fnptr-zero: blr-pc=0x%lx "
                      "ldr-pc=0x%lx blr-target=X%u slot=[SP,#%u] "
                      "(current sp+%u host=0x%lx) value=0x%lx",
                      (unsigned long)(lr - 4), (unsigned long)(lr + ldr_off),
                      (unsigned)blr_target_reg, (unsigned)ldr_imm,
                      (unsigned)((uint32_t)push_bytes + ldr_imm),
                      (unsigned long)slot_host, (unsigned long)slot_val);
  if (slot_val != 0) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A12-DIAG stack-fnptr-zero: slot value is "
                        "NON-zero — BLR target may have been corrupted "
                        "post-LDR; stopping trace");
    return;
  }

  // Step 5: STR Xs, [SP, #ldr_imm].
  intptr_t str_off = 0;
  uint32_t str_src_reg = 0;
  bool str_found = false;
  for (intptr_t d = ldr_off - 4; d >= -244; d -= 4) {
    uint32_t enc = 0;
    if (!safe_read_u32(lr + d, &enc)) break;
    if ((enc & 0xFFC003E0u) != 0xF90003E0u) continue;
    uint32_t imm = ((enc >> 10) & 0xfffu) * 8u;
    if (imm != ldr_imm) continue;
    str_src_reg = enc & 0x1fu;
    str_off = d;
    str_found = true;
    break;
  }
  if (!str_found) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A12-DIAG provenance-trace: no STR X?,[SP,#%u] "
                        "before LDR — slot uninitialised or set via STP / "
                        "different addressing mode",
                        (unsigned)ldr_imm);
    return;
  }
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A12-DIAG provenance-trace: stored-by=0x%lx "
                      "inst=STR X%u,[SP,#%u]  source-reg=X%u",
                      (unsigned long)(lr + str_off), (unsigned)str_src_reg,
                      (unsigned)ldr_imm, (unsigned)str_src_reg);

  // Step 6: LDR W/X to source-reg from a non-SP base.
  intptr_t mem_ldr_off = 0;
  uint32_t mem_ldr_base_reg = 0;
  uint32_t mem_ldr_imm = 0;
  bool mem_ldr_is_w = false;
  bool mem_ldr_found = false;
  for (intptr_t d = str_off - 4; d >= -252; d -= 4) {
    uint32_t enc = 0;
    if (!safe_read_u32(lr + d, &enc)) break;
    bool is_ldr_w = ((enc & 0xFFC00000u) == 0xB9400000u);
    bool is_ldr_x = ((enc & 0xFFC00000u) == 0xF9400000u);
    if (!is_ldr_w && !is_ldr_x) continue;
    uint32_t rt = enc & 0x1fu;
    if (rt != str_src_reg) continue;
    uint32_t rn = (enc >> 5) & 0x1fu;
    if (rn == 31u) continue;
    mem_ldr_base_reg = rn;
    mem_ldr_imm = ((enc >> 10) & 0xfffu) * (is_ldr_w ? 4u : 8u);
    mem_ldr_off = d;
    mem_ldr_is_w = is_ldr_w;
    mem_ldr_found = true;
    break;
  }
  if (!mem_ldr_found) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A12-DIAG provenance-trace: no LDR W/X%u,[X?,#?] "
                        "before STR — source from MOV or computed value",
                        (unsigned)str_src_reg);
    return;
  }
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A12-DIAG provenance-trace: originating-load=0x%lx "
                      "inst=LDR %s%u,[X%u,#%u]",
                      (unsigned long)(lr + mem_ldr_off),
                      mem_ldr_is_w ? "W" : "X", (unsigned)str_src_reg,
                      (unsigned)mem_ldr_base_reg, (unsigned)mem_ldr_imm);

  // Step 7: ADRP+ADD pair.
  uint32_t add_enc = 0, adrp_enc = 0;
  if (!safe_read_u32(lr + mem_ldr_off - 4, &add_enc)) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A12-DIAG provenance-trace: instr before LDR unreadable");
    return;
  }
  if (((add_enc >> 23) & 0x1ffu) != 0x122u) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A12-DIAG provenance-trace: instr before LDR is "
                        "not ADD imm12 (enc=0x%08x); base reg X%u may have been "
                        "set via MOV",
                        (unsigned)add_enc, (unsigned)mem_ldr_base_reg);
    return;
  }
  uint32_t add_rd = add_enc & 0x1fu;
  uint32_t add_rn = (add_enc >> 5) & 0x1fu;
  uint32_t add_imm12 = (add_enc >> 10) & 0xfffu;
  if (add_rd != mem_ldr_base_reg || add_rn != mem_ldr_base_reg) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A12-DIAG provenance-trace: ADD before LDR not "
                        "ADD X%u,X%u,#imm12 (rd=%u rn=%u)",
                        (unsigned)mem_ldr_base_reg, (unsigned)mem_ldr_base_reg,
                        (unsigned)add_rd, (unsigned)add_rn);
    return;
  }
  if (!safe_read_u32(lr + mem_ldr_off - 8, &adrp_enc)) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A12-DIAG provenance-trace: instr before ADD unreadable");
    return;
  }
  if (((adrp_enc >> 24) & 0x9fu) != 0x90u) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A12-DIAG provenance-trace: instr before ADD is "
                        "not ADRP (enc=0x%08x)",
                        (unsigned)adrp_enc);
    return;
  }
  uint32_t adrp_rd = adrp_enc & 0x1fu;
  if (adrp_rd != mem_ldr_base_reg) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A12-DIAG provenance-trace: ADRP doesn't "
                        "target X%u (rd=%u)",
                        (unsigned)mem_ldr_base_reg, (unsigned)adrp_rd);
    return;
  }
  uint32_t adrp_immlo = (adrp_enc >> 29) & 0x3u;
  uint32_t adrp_immhi = (adrp_enc >> 5) & 0x7ffffu;
  int32_t imm21 = (int32_t)((adrp_immhi << 2) | adrp_immlo);
  if (imm21 & (1 << 20)) imm21 -= (1 << 21);
  uintptr_t adrp_pc = lr + mem_ldr_off - 8;
  uintptr_t adrp_page = adrp_pc & ~uintptr_t(0xfff);
  uintptr_t adrp_target = adrp_page + ((intptr_t)imm21 << 12);
  uintptr_t sym_slot = adrp_target + (uintptr_t)add_imm12 + (uintptr_t)mem_ldr_imm;
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A12-DIAG provenance-trace: adrp-pc=0x%lx "
                      "adrp-target=0x%lx add-imm12=0x%x ldr-imm12=0x%x "
                      "sym_slot=0x%lx",
                      (unsigned long)adrp_pc, (unsigned long)adrp_target,
                      (unsigned)add_imm12, (unsigned)mem_ldr_imm,
                      (unsigned long)sym_slot);
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A12-DIAG sym-walk-back:");
  dump_sym_name_at_slot(sym_slot);
}
}  // namespace gk_diag

void gk_sigsegv_diag(int sig, siginfo_t* info, void* ucontext) {
  // Diag-only: dump PC bytes and registers so we can decode the crashing
  // GOAL bytecode at offset (PC - g_ee_main_mem). Re-raise after dumping
  // by restoring SIG_DFL.
  auto* uc = reinterpret_cast<ucontext_t*>(ucontext);
  uintptr_t pc = uc->uc_mcontext.pc;
  uintptr_t lr = uc->uc_mcontext.regs[30];
  uintptr_t fault = info ? reinterpret_cast<uintptr_t>(info->si_addr) : 0;
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG sig=%d fault=0x%lx pc=0x%lx lr=0x%lx",
                      sig, (unsigned long)fault, (unsigned long)pc,
                      (unsigned long)lr);
  for (int i = 0; i < 32; i++) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG x%d=0x%lx", i,
                        (unsigned long)uc->uc_mcontext.regs[i]);
  }

  // A12-DIAG: tie the failing BLR to the originating sym slot via a
  // backward provenance trace (BLR Xt → LDR Xt,[SP,#N] → STR Xs,[SP,#N]
  // → LDR Ws,[Xb,#0] → ADRP+ADD → sym name). Runs only on sig=4 (SIGILL).
  if (sig == SIGILL) {
    gk_diag::dump_stack_fnptr_zero_chain(lr, (uintptr_t)uc->uc_mcontext.sp);
  }

  // A11-DIAG: identify which symbol's value slot the failing BLR loaded.
  // X16 = the LDR base reg from A5's sym-MEM emit; X9 = the BLR target.
  // The line shape matches gk_diag::dump_sym_name_at_slot in
  // game/linux-arm64/linux_arm64_main.cpp so device logcat and
  // qemu_repro stderr are diff-able.
  gk_diag::dump_sym_name_at_slot(
      (uintptr_t)uc->uc_mcontext.regs[16]);
  gk_diag::dump_sym_name_at_slot(
      (uintptr_t)uc->uc_mcontext.regs[9]);

  // A6 attempt 5+: dump bytes around LR (return address). When PC is a
  // BLR-to-NULL jump landing at EE base, LR points at the instruction
  // *after* the BLR — so LR-4 = the BLR, LR-8.. = what loaded the (NULL)
  // function pointer into the BLR target register. Extended to lr-256
  // so we can trace back through the call_r64 prologue + arg shuffle to
  // the source of the NULL value (typically the prior call's return).
  for (intptr_t d = -256; d <= 16; d += 4) {
    uintptr_t addr = lr + d;
    uint32_t insn = 0;
    if (gk_diag::safe_read_u32(addr, &insn)) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG lr%+ld @ 0x%lx = 0x%08x",
                          (long)d, (unsigned long)addr, insn);
    } else {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG lr%+ld @ 0x%lx = <unreadable>",
                          (long)d, (unsigned long)addr);
    }
  }
  // PC bytes (safe-read; original loop secondary-SEGV'd on EE-base BLR).
  for (intptr_t d = -32; d <= 16; d += 4) {
    uintptr_t addr = pc + d;
    uint32_t insn = 0;
    if (gk_diag::safe_read_u32(addr, &insn)) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG pc%+ld @ 0x%lx = 0x%08x",
                          (long)d, (unsigned long)addr, insn);
    } else {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG pc%+ld @ 0x%lx = <unreadable>",
                          (long)d, (unsigned long)addr);
    }
  }
  struct sigaction sa{};
  sa.sa_handler = SIG_DFL;
  sigaction(sig, &sa, nullptr);
  raise(sig);
}

void gk_install_sigsegv_diag() {
  struct sigaction sa{};
  sa.sa_sigaction = &gk_sigsegv_diag;
  sa.sa_flags = SA_SIGINFO;
  sigaction(SIGSEGV, &sa, nullptr);
  sigaction(SIGBUS, &sa, nullptr);
  sigaction(SIGILL, &sa, nullptr);
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "gk_install_sigsegv_diag: installed");
}
}  // namespace

int gk_sdl_main(int /*argc_ignored*/, char** /*argv_ignored*/) {
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag, "gk_sdl_main: entered");
  gk_install_sigsegv_diag();

  // A11: install the chained pre-kernel-version hook before goal_main
  // is called. By gk_sdl_main entry every global ctor has finished, so
  // capturing whatever android_runtime_compat installed and chaining
  // our binder is race-free.
  a11_install_pc_mips2c_hook_once();

  // Phase 23 (autoport): bring up the SDL virtual gamepad + audio
  // device on the SDL main thread, before goal_main hands us off to
  // the renderer. The renderer's later SDL_Init(SDL_INIT_VIDEO) is
  // idempotent w.r.t. the AUDIO/JOYSTICK subsystems initialised here.
  android_input_audio::init();

  const char* game_name = g_selected_game ? g_selected_game : "jak1";
  const char* data_root = g_data_root ? g_data_root : "";
  if (!*data_root) {
    __android_log_print(ANDROID_LOG_ERROR, kGkLogTag,
                        "gk_sdl_main: data_root unset — NativeGk.setDataRoot "
                        "was not called before SDL thread launch");
    return 1;
  }

  // Canonical argv shape:
  //   gk --game <name> --portable -fakeiso -iso-data <data_root> -boot -debug-mem
  // The runtime accepts CLI11 long flags AND the legacy kmachine `-foo`
  // flags interleaved; main.cpp re-parses both layers (CLI11 first, the
  // rest passed through to InitParms).
  //
  // Phase D4 (autoport): `-boot` flips MasterDebug=0 + DiskBoot=1. That
  //   1. skips InitGoalProto/sceDeci2Open (no deci2 server on Android),
  //      avoiding a SIGSEGV during InitMachine when MasterDebug=1.
  //   2. makes InitMachineScheme actually call load_and_link_dgo_from_c
  //      for GAME.CGO, which is what generates the `link finish:` markers
  //      the D4 validator greps for.
  // `-debug-mem` mirrors the desktop validator smoke test so the
  // memory-layout behaviour matches Linux-arm64.
  const char* argv[] = {
      "gk",
      "--game",     game_name,
      "--portable",
      "-fakeiso",
      "-iso-data",  data_root,
      "-boot",
      "-debug-mem",
      nullptr,
  };
  const int argc = (int)(sizeof(argv) / sizeof(argv[0])) - 1;

  __android_log_print(
      ANDROID_LOG_INFO, kGkLogTag,
      "goal_main: argv=[%s,%s,%s,%s,%s,%s,%s,%s,%s]",
      argv[0], argv[1], argv[2], argv[3], argv[4], argv[5], argv[6], argv[7], argv[8]);

  const int rc = goal_main(argc, const_cast<char**>(argv));
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag, "goal_main: returned %d", rc);
  return rc;
}

// Phase 20: per-process globals pushed in from Java BEFORE the SDL thread
// launches. Idempotent: a second call replaces the previous strdup'd value
// (we leak the old one — process-lifetime memory, never freed).
JNIEXPORT void JNICALL
Java_org_opengoal_gk_NativeGk_setSelectedGame(JNIEnv* env, jclass /*clazz*/,
                                              jstring j_game_name) {
  if (!j_game_name) {
    return;
  }
  const char* s = env->GetStringUTFChars(j_game_name, nullptr);
  if (s) {
    g_selected_game = ::strdup(s);
    env->ReleaseStringUTFChars(j_game_name, s);
    __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                        "NativeGk.setSelectedGame: %s",
                        g_selected_game ? g_selected_game : "(null)");
  }
}

JNIEXPORT void JNICALL
Java_org_opengoal_gk_NativeGk_setDataRoot(JNIEnv* env, jclass /*clazz*/,
                                          jstring j_data_root) {
  if (!j_data_root) {
    return;
  }
  const char* s = env->GetStringUTFChars(j_data_root, nullptr);
  if (s) {
    g_data_root = ::strdup(s);
    env->ReleaseStringUTFChars(j_data_root, s);
    __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                        "NativeGk.setDataRoot: %s",
                        g_data_root ? g_data_root : "(null)");
  }
}

JNIEXPORT void JNICALL
Java_org_opengoal_gk_NativeGk_onPadButton(JNIEnv* /*env*/, jclass /*clazz*/,
                                          jint sdl_button, jboolean pressed) {
  // Phase E1 (autoport): emit a marker the device-side validator can
  // grep for to prove a gamepad event actually crossed the JNI
  // boundary into native code (and from there into the GOAL kernel via
  // on_pad_button → CPad). The string "onPadButton" matches the
  // validator's PADBTN_HITS regex.
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "onPadButton: sdl_button=%d pressed=%d "
                      "(JNI route from Java SDLActivity)",
                      (int)sdl_button, pressed == JNI_TRUE ? 1 : 0);
  android_input_audio::on_pad_button((int)sdl_button, pressed == JNI_TRUE);
}

JNIEXPORT void JNICALL
Java_org_opengoal_gk_NativeGk_onTouchEvent(JNIEnv* /*env*/, jclass /*clazz*/,
                                          jint x, jint y, jint action) {
  const uint32_t n =
      g_touch_events_seen.fetch_add(1, std::memory_order_relaxed);
  const char* action_str = "unknown";
  switch (action) {
    case AMOTION_EVENT_ACTION_DOWN: action_str = "down"; break;
    case AMOTION_EVENT_ACTION_UP: action_str = "up"; break;
    case AMOTION_EVENT_ACTION_MOVE: action_str = "move"; break;
    case AMOTION_EVENT_ACTION_CANCEL: action_str = "cancel"; break;
    default: break;
  }
  __android_log_print(ANDROID_LOG_DEBUG, kGkLogTag,
                      "touch[%u]: action=%s x=%d y=%d", n, action_str, x, y);
}

// Phase D3 (autoport): expose the renderer's sustained-swap counter to
// Java. Returns the cumulative SDL_GL_SwapWindow count since the most
// recent android_renderer_run entry. Two readers: NativeGk's Java
// callers (e.g. a watchdog in the Activity), and the D4 device-side
// validator that asserts the count grows monotonically while the APK
// is foregrounded.
JNIEXPORT jlong JNICALL
Java_org_opengoal_gk_NativeGk_getRendererFrameCount(JNIEnv* /*env*/,
                                                    jclass /*clazz*/) {
  return (jlong)android_renderer_frame_count();
}

// Phase E2 (autoport): JNI bridge that exposes the SDL open-gamepad
// count to the Activity's UI-thread poller. MainActivity calls this
// every second; when the count transitions 0 → N the touch overlay
// auto-hides with a `gamepad detected: hiding touch overlay` marker
// the E2 prompt requires for observable behaviour.
JNIEXPORT jint JNICALL
Java_org_opengoal_gk_NativeGk_getOpenGamepadCount(JNIEnv* /*env*/,
                                                  jclass /*clazz*/) {
  return (jint)android_input_audio::open_gamepad_count();
}

// Phase E3 (autoport): drive kmemcard's deterministic save writer from
// Java. write_test_save_to_path lives in game/kernel/common/kmemcard.cpp
// and produces a 67584-byte bank file (header + zero body + footer) that
// is byte-identical to what the desktop x86_64 build produces under the
// same call — every input to mc_checksum is platform-independent.
// Returns 0 on success, non-zero on I/O failure. The Activity logs the
// outcome with the literal marker string `test save written:` so the
// e3_run.sh harness can grep for it before adb-pulling the result.
JNIEXPORT jint JNICALL
Java_org_opengoal_gk_NativeGk_writeTestSave(JNIEnv* env, jclass /*clazz*/,
                                            jstring j_path) {
  if (!j_path) {
    __android_log_print(ANDROID_LOG_ERROR, kGkLogTag,
                        "writeTestSave: null path");
    return 1;
  }
  const char* path_c = env->GetStringUTFChars(j_path, nullptr);
  if (!path_c) {
    return 2;
  }
  const std::string path(path_c);
  env->ReleaseStringUTFChars(j_path, path_c);

  // The kmemcard module owns a small block of static globals that
  // pc_game_save_synch reads; write_test_save_to_path doesn't touch
  // them but the kernel sometimes runs before this is called, so
  // initialising here is idempotent + cheap.
  kmemcard_init_globals();

  const bool ok = write_test_save_to_path(path);
  if (!ok) {
    __android_log_print(ANDROID_LOG_ERROR, kGkLogTag,
                        "writeTestSave: write_test_save_to_path failed for %s",
                        path.c_str());
    return 3;
  }
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "test save written: %s", path.c_str());
  return 0;
}

}  // extern "C"
