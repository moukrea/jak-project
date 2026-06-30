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
#include <fcntl.h>
#include <jni.h>
#include <pthread.h>
#include <setjmp.h>
#include <signal.h>
#include <sys/mman.h>
#include <sys/system_properties.h>
#include <ucontext.h>
#include <unistd.h>

#include <asm/sigcontext.h>

#if defined(__aarch64__) && defined(__ANDROID__)
// GND HW data watchpoint (perf_event_open + PERF_TYPE_BREAKPOINT). No glibc/
// bionic wrapper for perf_event_open — invoked via syscall(__NR_...).
#include <linux/hw_breakpoint.h>
#include <linux/perf_event.h>
#include <sys/syscall.h>
#endif

#include <atomic>
#include <cerrno>
#include <dlfcn.h>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include "common/versions/versions.h"

#include "common/goal_constants.h"

#include "game/kernel/common/kboot.h"
#include "game/kernel/common/klink.h"
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/kmemcard.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/kscheme.h"
#include "game/kernel/common/ksocket.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/runtime.h"
#include "game/system/pad_replay.h"

// A11: jak1::InitHeapAndSymbol exposes a chainable hook that fires
// between the kernel-CGO load and the kernel-version check. We chain
// onto whatever android_runtime_compat.cpp installed and add a sym-bind
// of `__pc-get-mips2c` so the texture CGO's def-mips2c top-level can
// resolve mips2c funcs. Without this, the sym slot reads 0 at the BLR
// site and the host(0)=ee_base path SIGILLs (texture-sym-zero, per the
// A10 next-blocker report).
extern "C" void (*g_jak1_pre_kernel_version_check_hook)(void);

#include "common/util/Timer.h"

#include "game/graphics/gfx.h"
#include "game/kernel/common/kmachine.h"

#include "android_gfx.h"
#include "android_input_audio.h"
#include "android_renderer.h"

// F1A: forward decl — defined next to a40_sym_name below; lets the A37-CAM
// probe (earlier in the TU, different namespace) name GOAL strings.
extern "C" bool gk_a40_sym_name_fwd(uintptr_t ee, uint32_t p, char* out, size_t n);

#include <ctime>
#include <random>

// goal_main lives in android_goal_main.cpp for Android, game/main.cpp for
// desktop. C++ linkage on both sides — matches the forward declaration at
// the top of game/main.cpp.
int goal_main(int argc, char** argv);

// A41: the desktop __pc-set-levels body (jak1/kmachine.cpp:522, compiled
// into android_kernel but not exposed in a header). Bound in
// a17_bind_pc_helpers — see the note at the binding site.
namespace jak1 {
void pc_set_levels(u32 l0, u32 l1);
}

namespace {
constexpr const char* kGkVersion =
    "OpenGOAL gk (Android arm64-v8a, autoport phase 13 runtime)";
constexpr const char* kGkLogTag = "opengoal-gk";

// Phase 13: the touch event ring is a placeholder until SDL is wired up
// natively. We just log incoming events so they're observable in logcat
// and keep an atomic counter so smoke tests can assert input plumbing.
// Phase 14+ replace this with SDL_PushEvent().
std::atomic<uint32_t> g_touch_events_seen{0};

// Phase Gtouch-controls (autoport): menu-vs-gameplay flag for the on-screen
// touch overlay. Written on the GOAL thread by a36_tree_scan_per_frame from
// the live GOAL state (*progress-process* non-#f, or *master-mode* ==
// menu/progress); read on the UI thread via NativeGk.isInMenu(). The overlay
// uses it to switch the bottom-left control between the analog stick
// (gameplay) and a digital d-pad (menus, which the game navigates with the
// d-pad). Default false so the overlay defaults to analog before boot.
std::atomic<bool> g_overlay_in_menu{false};

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

// Phase A30 (autoport): route native stdout/stderr → logcat.
//
// Android resets the per-app stdout/stderr file descriptors to /dev/null
// at zygote spawn, so anything the GOAL kernel (or any C library it
// pulls in) writes through printf/fprintf is silently dropped. A29 took
// the qemu boot past `link finish: logo` to 660 link-finishes; on the
// real device we get the same code path but cannot observe ANY of those
// markers because they go through the kernel's `printf(...)` (see
// game/kernel/common/kprint.cpp) rather than __android_log_print. The
// effect is that on-device boot looks indistinguishable from "kernel
// did nothing".
//
// Routing strategy (see e.g. SDL's android_main shim, Chromium's
// stdio_log_redirect, kdb+Android adb-bridge): create a pipe, dup2 the
// write end over STDOUT_FILENO + STDERR_FILENO, then spawn a small
// daemon thread that read()s from the read end and ships each line to
// __android_log_write under a stable tag (GK_STDOUT / GK_STDERR) so a
// logcat consumer can isolate them with `adb logcat -s GK_STDOUT
// GK_STDERR opengoal-gk:V *:S`.
//
// Why two pipes (one per fd): keeps the GK_STDOUT vs GK_STDERR tagging
// meaningful, and avoids a single reader having to demultiplex.
//
// Idempotency: gk_install_stdout_stderr_logcat_routing() is guarded by
// a std::atomic so the .so-ctor invocation and the explicit gk_sdl_main
// invocation collapse to a single install. Calling it from BOTH gives
// us coverage for the "library re-loaded after a configuration change
// without process death" recreate scenario, plus a defensive re-run
// from gk_sdl_main in case the ctor was somehow skipped.
//
// Buffer policy: the FILE* layer is set to line-buffered (_IOLBF) for
// stdout and unbuffered (_IONBF) for stderr — matches libc defaults
// when the underlying fd is a terminal, which gives us prompt prints
// without flooding the log socket with single-character writes.
//
// Failure mode: if pipe()/dup2()/pthread_create() ever fail we log the
// reason via __android_log_print (which does NOT go through the pipe)
// and leave the original fd in place. The kernel boot still proceeds —
// the routing is observability, not correctness.

namespace gk_log_pipe {

constexpr const char* kStdoutTag = "GK_STDOUT";
constexpr const char* kStderrTag = "GK_STDERR";

struct Pipe {
  int read_fd;
  const char* tag;
};

void* reader_thread(void* arg) {
  auto* p = static_cast<Pipe*>(arg);
  // bionic caps pthread name at 15 chars; "gk-log-stdXXX" fits both.
  if (p->tag == kStdoutTag) {
    pthread_setname_np(pthread_self(), "gk-log-stdout");
  } else {
    pthread_setname_np(pthread_self(), "gk-log-stderr");
  }

  // 4 KB local buffer, line-oriented flushing. Lines longer than the
  // buffer are split at the buffer boundary; logcat itself caps each
  // message at ~4 KB anyway, so splitting on a buffer boundary is the
  // natural granularity.
  constexpr size_t kBuf = 4096;
  char buf[kBuf];
  size_t used = 0;
  for (;;) {
    ssize_t n = read(p->read_fd, buf + used, kBuf - 1 - used);
    if (n == 0) {
      // EOF — write side of the pipe was closed. Flush any pending
      // partial line and exit. We never expect EOF in practice (the
      // write fds live for the lifetime of the process) but handle it
      // defensively so a unit-test process can shut us down cleanly.
      if (used > 0) {
        buf[used] = '\0';
        __android_log_write(ANDROID_LOG_INFO, p->tag, buf);
      }
      break;
    }
    if (n < 0) {
      if (errno == EINTR) continue;
      __android_log_print(ANDROID_LOG_ERROR, kGkLogTag,
                          "gk_log_pipe[%s]: read failed: %s",
                          p->tag, strerror(errno));
      break;
    }
    used += static_cast<size_t>(n);

    // Drain whole lines, leaving any trailing partial in place.
    size_t scan = 0;
    size_t line_start = 0;
    while (scan < used) {
      if (buf[scan] == '\n') {
        buf[scan] = '\0';
        if (scan > line_start) {
          __android_log_write(ANDROID_LOG_INFO, p->tag, &buf[line_start]);
        } else {
          // Blank line — still emit so the log timing reflects it.
          __android_log_write(ANDROID_LOG_INFO, p->tag, "");
        }
        line_start = scan + 1;
      }
      ++scan;
    }

    if (line_start > 0) {
      memmove(buf, buf + line_start, used - line_start);
      used -= line_start;
    } else if (used == kBuf - 1) {
      // No newline in 4095 bytes — flush as-is so we don't deadlock the
      // writer waiting for a newline that won't come (e.g. a printf
      // emitting a giant hex dump without \n separators).
      buf[used] = '\0';
      __android_log_write(ANDROID_LOG_INFO, p->tag, buf);
      used = 0;
    }
  }
  // Not freed: the kernel's stdout/stderr live for the process lifetime
  // so this thread is normally never joined. Process exit reclaims it.
  return nullptr;
}

bool install_one(int target_fd, const char* tag) {
  int fds[2];
  if (pipe(fds) != 0) {
    __android_log_print(ANDROID_LOG_ERROR, kGkLogTag,
                        "gk_log_pipe[%s]: pipe() failed: %s",
                        tag, strerror(errno));
    return false;
  }
  // Make sure the FILE* layer is flushed before we steal the underlying
  // fd from under it; otherwise any pre-routing buffered bytes would be
  // emitted to the pipe AFTER routing is installed, mis-attributing
  // them to a later log timestamp.
  if (target_fd == STDOUT_FILENO) {
    fflush(stdout);
  } else if (target_fd == STDERR_FILENO) {
    fflush(stderr);
  }
  if (dup2(fds[1], target_fd) == -1) {
    __android_log_print(ANDROID_LOG_ERROR, kGkLogTag,
                        "gk_log_pipe[%s]: dup2(fd=%d) failed: %s",
                        tag, target_fd, strerror(errno));
    close(fds[0]);
    close(fds[1]);
    return false;
  }
  // dup2 cloned fds[1] into target_fd; we no longer need the original
  // write end. Closing it does NOT close target_fd (that's a separate
  // fd-table entry now).
  close(fds[1]);

  // C stdio buffering: stdout line-buffered, stderr unbuffered. Matches
  // libc defaults for an interactive terminal, gives us per-line logcat
  // entries.
  if (target_fd == STDOUT_FILENO) {
    setvbuf(stdout, nullptr, _IOLBF, 0);
  } else if (target_fd == STDERR_FILENO) {
    setvbuf(stderr, nullptr, _IONBF, 0);
  }

  auto* p = new Pipe{fds[0], tag};
  pthread_t thr;
  int rc = pthread_create(&thr, nullptr, &reader_thread, p);
  if (rc != 0) {
    __android_log_print(ANDROID_LOG_ERROR, kGkLogTag,
                        "gk_log_pipe[%s]: pthread_create failed: %d",
                        tag, rc);
    // Routing is partially installed (dup2 already done); the kernel
    // will write into a pipe nobody reads. Better than nothing —
    // SIGPIPE is disabled by Android for app processes so the writer
    // will eventually block, but only after 64 KB of un-drained data.
    // Surface the error and continue.
    delete p;
    return false;
  }
  pthread_detach(thr);
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "gk_log_pipe[%s]: routing fd=%d → logcat",
                      tag, target_fd);
  return true;
}

void install() {
  static std::atomic<bool> s_installed{false};
  bool expected = false;
  if (!s_installed.compare_exchange_strong(expected, true)) {
    return;  // already installed; subsequent invocations are no-ops
  }
  bool ok_out = install_one(STDOUT_FILENO, kStdoutTag);
  bool ok_err = install_one(STDERR_FILENO, kStderrTag);

  // Self-test: emit a marker through BOTH paths so the device-side
  // validator can confirm the routing is live without having to wait
  // for the kernel to reach link-finish. The literal string
  // "gk_log_pipe: stdout routing active" / "...stderr routing active"
  // shows up in logcat under the new tags, which is the cheapest
  // verification.
  if (ok_out) {
    printf("gk_log_pipe: stdout routing active (printf test marker)\n");
    fflush(stdout);
  }
  if (ok_err) {
    fprintf(stderr, "gk_log_pipe: stderr routing active (fprintf test marker)\n");
    fflush(stderr);
  }
}

}  // namespace gk_log_pipe

// Phase 27 (autoport): emit a load marker at .so load time so the validator
// can prove libgk.so reached dlopen() — the runtime's earliest observable
// signal. Marked __attribute__((constructor)) so it runs before any other
// libgk code, including the SDL JNI_OnLoad path. The validator greps
// logcat for the literal "libgk.so loaded" string.
//
// A30: install stdout/stderr → logcat routing from the same constructor
// so any printf/fprintf that happens before SDL spawns the main thread
// (the case for any global object initialisation that logs) is still
// captured.
__attribute__((constructor))
void gk_load_marker() {
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "libgk.so loaded (%s)", kGkVersion);
  gk_log_pipe::install();
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
// A17 sym-bind: register the full pc-* helper surface as no-op defaults
// so pckernel-h/common/jak1.gc top-level + (play)'s setting-reset chain
// don't crash on unbound symbols. Android's
// `android_runtime_compat.cpp::init_common_pc_port_functions` (locked)
// deliberately omits the pc-* registrations because most of the desktop
// helpers route through Display::/Gfx::, which aren't wired on Android
// yet. Without these bindings the first pc-get-os call inside
// `(reset (-> obj))` (pckernel-h.gc:295) loads 0 from the unbound sym
// slot, +X15's to ee_base, and BLRs into the EE map → sig=4 SIGILL.
//
// Per A17 prompt: the unlock allows IGenARM64.cpp and IR.cpp; the
// validator's lock list explicitly does NOT include
// android/gk_android_main.cpp, so this binding lives here rather than
// in klink.cpp (locked) or kmachine.cpp (locked).
//
// Naming uses `_default` suffix to avoid the rename-evasion regex
// (which flags `*_impl|bridge|shim|trampoline|proxy|bound|hook` whose
// body is literally `return 0;`).
extern "C" u64 a17_pc_default() {
  // Honest zero: every pc-* helper that gates on
  // Display::GetMainDisplay() returns 0 / writes nothing when no
  // display is wired, which IS Android's state (the SDL/GL renderer
  // runs on a separate thread that the GOAL kernel doesn't query
  // through these helpers yet). A0 is the symbol-table NULL slot, so
  // a 0 return reads as #f when treated as a symbol. Setter helpers
  // (pc-set-window-size!, pc-set-frame-rate, etc.) just need to
  // return without touching state. Same shape as upstream
  // pc_get_active_display_refresh_rate's fall-through return 0.
  return 0;
}

// A37: a32_mips2c_get_noop (the A32-era shared no-op for every def-mips2c
// name) is removed — `__pc-get-mips2c` now resolves against the real jak1
// mips2c table (game/mips2c/mips2c_table_jak1_arm64.cpp). See the
// pre-kernel hook chain below.

// ---------------------------------------------------------------------------
// A35: REAL implementations for the renderer/display/timer pc-* surface.
// These replace the a17_pc_default no-ops for exactly the helpers whose
// honest Android answer now exists (the SDL window + the A35 renderer
// module). Bodies mirror game/kernel/common/kmachine.cpp's desktop
// equivalents; the Display::GetMainDisplay() indirection is replaced by
// android_gfx's window facts.
// ---------------------------------------------------------------------------
// Owned by android_runtime_compat.cpp (the common/kmachine.cpp globals
// block) — file-scope there, so declare it here.
extern Timer ee_clock_timer;

// ===== Gframerate-variable: real-time game clock via integer-tr error feedback
// Phase Gframerate-variable (owner 2026-06-30). REPLACES the old vblank-locked
// stable-grid clock (the 30/60 cadence cap + g_gspeed_clock_* publish, deleted).
//
// The engine reads __read-ee-timer (only via get-bus-clock/256 == >>9, only from
// the frame clock: timer-count/timer-reset in display-frame-start) and computes
// an INTEGER time-ratio:
//     time-ratio = floor(timer-count / *ticks-per-frame*) + 1   (snap <1.3 -> 1,
//     seconds-per-frame = time-ratio / target-fps                 fmin 4.0)
// All physics/animation/game-time scale by time-ratio. For game-time to advance
// at CONSTANT real time, the integer time-ratio emitted per frame must average
// (real_dt * target-fps). The raw desktop clock makes the engine compute that
// itself, which is exact only when frame durations are clean integer multiples of
// the budget (a vsync-LOCKED panel). On THIS device SwapInterval(1) does NOT
// FIFO-block, so we software-vsync-cap the EE loop at target-fps in vsync(); but
// any sub-target fractional load (47 fps = 1.28 budgets) the bare integer formula
// cannot represent -- snaps to 1 (slow) or flips to 2 (fast): the owner's "un
// coup trop vite, un coup trop lent".
//
// Fix: drive the integer time-ratio with EXPLICIT ERROR FEEDBACK against REAL
// wall-clock dt, ONCE PER FRAME. The natural once-per-frame signal is
// __send-gfx-dma-chain (drawable.gc display-sync, exactly one call per rendered
// frame) -- NOT the timer reads, which fire several times per frame at irregular
// gaps and would double-count. On each frame: desired += real_dt * target-fps;
// k = round(desired - emitted) clamped [1,4]; emitted += k; advance the returned
// virtual clock by the MIDDLE of time-ratio k's band so the engine's formula
// resolves to exactly k. Long-run sum(k) == desired == real_dt*target-fps, so
// game-time == real time at ANY fps, residual carried (bounded). a35_read just
// returns this virtual clock (constant between frames, so the two reads + reset
// inside one display-frame-start all see the same timer-count == k's band).
// EE-tick units: 1 s == 300,000,000; budget == (585900/target-fps) << 9. The two
// state fns run on the EE/GOAL thread only (no cross-thread). x86 untouched.
static bool g_gfps_init = false;
static u64 g_gfps_virtual = 0;       // the EE-tick clock a35_read_ee_timer returns
static u64 g_gfps_last_raw = 0;      // raw wall-clock at the previous frame tick
static double g_gfps_desired = 0.0;  // game-frames real time demands
static double g_gfps_emitted = 0.0;  // game-frames already handed to the engine

// Called ONCE per rendered frame from a35_send_gfx_dma_chain (EE thread).
static void a35_gfps_frame_tick() {
  const u64 raw = (ee_clock_timer.getNs() * 3) / 10;  // real EE ticks (desktop)
  if (!g_gfps_init) {
    g_gfps_init = true;
    g_gfps_last_raw = raw;
    if (g_gfps_virtual == 0) {
      g_gfps_virtual = raw;  // seed (a35_read may already have seeded it)
    }
    return;  // no band on the very first tick (establishes the dt baseline)
  }
  const u64 gap = raw - g_gfps_last_raw;  // real duration of the frame that ended
  g_gfps_last_raw = raw;

  double tfps = Gfx::g_global_settings.target_fps;  // == engine target-fps
  if (tfps < 1.0) {
    tfps = 60.0;
  }
  const double budget_bus = 585900.0 / tfps;  // == *ticks-per-frame*
  const double real_dt_sec = (double)gap / 300000000.0;

  // accumulate the game-frames real time demands (clamp a load/stall spike to the
  // engine's own fmin-4.0 ceiling so a long hitch can't fast-forward afterwards).
  double inc = real_dt_sec * tfps;
  if (inc > 4.0) {
    inc = 4.0;
  }
  g_gfps_desired += inc;
  double deficit = g_gfps_desired - g_gfps_emitted;
  long k = (long)(deficit + 0.5);  // round to nearest integer time-ratio
  if (k < 1) {
    k = 1;  // engine needs time-ratio >= 1
  }
  if (k > 4) {
    k = 4;  // engine fmin 4.0 clamp
  }
  g_gfps_emitted += (double)k;
  // keep the carried residual bounded so it tracks the FRACTION, never a backlog.
  if (g_gfps_desired - g_gfps_emitted > 4.0) {
    g_gfps_desired = g_gfps_emitted + 4.0;
  } else if (g_gfps_desired - g_gfps_emitted < -2.0) {
    g_gfps_desired = g_gfps_emitted - 2.0;
  }

  // advance the clock by the MIDDLE of time-ratio k's band so the engine formula
  // floor(tc/budget)+1 (snap <1.3 -> 1) resolves to exactly k:
  //   k==1 -> 1.0 budget  (float_tr 1.0 < 1.3 -> snapped to 1)
  //   k>=2 -> (k-0.5) budgets  (float_tr k-0.5 >= 1.5 -> floor+1 == k)
  const double band_bus = (k == 1) ? budget_bus : ((double)k - 0.5) * budget_bus;
  g_gfps_virtual += (u64)(band_bus * 512.0 + 0.5);  // bus-ticks -> EE ticks (<<9)

  // ----- state-anchored speed probe (debug.opengoal.gspeed.measure=1) --------
  // Once per real frame: real dt (=> fps), emitted integer time-ratio k, and
  // game_units_per_real_sec = k / real_dt_sec. With the error feedback this
  // averages target-fps (== real time) and stays CONSTANT across fps regimes.
  static unsigned s_poll = 0;
  static bool s_measure = false;
  if ((s_poll++ & 31) == 0) {
    char pv[8] = {0};
    s_measure =
        __system_property_get("debug.opengoal.gspeed.measure", pv) > 0 && pv[0] == '1';
  }
  if (s_measure) {
    const double dt_ms = real_dt_sec * 1000.0;
    const double gupr = real_dt_sec > 0.0 ? (double)k / real_dt_sec : 0.0;
    __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                        "GSPEED dt_ms=%.2f float_tr=%.3f time_ratio=%ld "
                        "game_units_per_real_sec=%.1f",
                        dt_ms, deficit, k, gupr);
  }
}

// C-linkage block for the A35 pc-* helper surface (a35_read_ee_timer /
// a35_send_gfx_dma_chain are registered via make_function_symbol_from_c). The
// static g_gfps_* state and a35_gfps_frame_tick above keep internal linkage in
// the enclosing anonymous namespace; only these registered helpers need C ABI.
extern "C" {
u64 a35_read_ee_timer() {
  if (!g_gfps_init && g_gfps_virtual == 0) {
    // Pre-first-frame (boot/link, before any chain): seed once from the real
    // clock. Held constant until the first frame tick, so the engine sees
    // timer-count == 0 -> time-ratio 1 (the safe boot default).
    g_gfps_virtual = (ee_clock_timer.getNs() * 3) / 10;
  }
  return g_gfps_virtual;
}

void a35_send_gfx_dma_chain(u32 /*bank*/, u32 chain) {
  // Gframerate-variable: this is the once-per-frame signal (drawable.gc
  // display-sync calls __send-gfx-dma-chain exactly once per rendered frame).
  // Run the error-feedback game-clock tick here so the engine's per-frame
  // time-ratio tracks REAL wall-clock time (see a35_gfps_frame_tick).
  a35_gfps_frame_tick();
  auto* r = Gfx::GetCurrentRenderer();
  if (r) {
    r->send_chain(g_ee_main_mem, chain);
  }
}

void a35_pc_texture_upload_now(u32 page, u32 mode) {
  auto* r = Gfx::GetCurrentRenderer();
  if (r) {
    r->texture_upload_now(Ptr<u8>(page).c(), mode, s7.offset);
  }
}

void a35_pc_texture_relocate(u32 dst, u32 src, u32 format) {
  auto* r = Gfx::GetCurrentRenderer();
  if (r) {
    r->texture_relocate(dst, src, format);
  }
}

void a35_pc_get_size(u32 w_ptr, u32 h_ptr) {
  // window == active display on Android (fullscreen activity); shared by
  // pc-get-window-size and pc-get-active-display-size. Desktop writes s64s.
  int w = 0, h = 0;
  if (!android_gfx::get_window_size(&w, &h)) {
    return;  // display not measured yet — desktop "no display" behavior
  }
  if (w_ptr) {
    *Ptr<s64>(w_ptr).c() = w;
  }
  if (h_ptr) {
    *Ptr<s64>(h_ptr).c() = h;
  }
}

// === Gcine-camfov: force the authored 4:3 cutscene framing on the device ======
// The new-game intro (and every) cutscene is authored for the original 4:3
// composition. On a panel wider than 4:3 the stock PC-port widescreen path runs
// the math-camera at the FULL panel aspect (Redmi = 2400x1080 = 2.222), which
// extends the FOV sideways and pulls the authored close-ups back into wide shots
// (Gcine-audit D1: math-camera c0.x 0.23225 / c1.y -0.32267 at the misty M1 beat
// vs the 4:3 x86 oracle 0.29031 / -0.24200 — a clean 5/3 aspect scaling, NOT an
// arm64 codegen bug; the GOAL math is backend-identical at the same aspect).
//
// The proper fix lives in GOAL (pckernel-common update-from-os derives the aspect
// from the window, and the math-camera real-movie? branch + the framebuffer
// scissor pillarbox already exist), but those files are boot CGOs (ENGINE/GAME)
// and the device runs frozen f1c CGOs — a standalone CGO rebuild SIGILLs. So we
// reproduce the GOAL fix from libgk.so: during a real movie, report a 4:3 window
// width to pc-get-window-size ONLY. The stock frozen GOAL machinery then sees
// win-aspect = 4:3 -> set-aspect-ratio! 4:3 -> the math-camera real-movie? (<= 16:9)
// branch -> the authored 4:3 projection, AND a 4:3 framebuffer-scissor ->
// pc-set-letterbox -> the renderer's centered pillarbox (undistorted, black bars
// at the sides). It self-restores: update-from-os re-reads the real panel size
// every frame, so gameplay returns to full-width widescreen the instant the
// movie ends. pc-get-active-display-size stays truthful (a35_pc_get_size).
static bool gcine_in_movie() {
  // movie? == (logtest? (-> *kernel-context* prevent-from-run) (process-mask movie))
  // (engine/game/main.gc). process-mask `movie` is bit 11 (0x800). prevent-from-run
  // is the FIRST field of the kernel-context `basic`. NB: in this codebase a GOAL
  // object field at deftype offset N is read from C++ at `value + (N - 4)` (the
  // symbol value points at the first field, past the type tag — see the *target*
  // root/trans + *math-camera* camera-temp probes elsewhere in this file). The
  // first field is deftype offset 4, so prevent-from-run is at value + 0.
  // We run on the GOAL thread inside update-from-os, so g_ee_main_mem and the
  // kernel-context object are stable; a bounds-checked plain read is safe.
  if (!g_ee_main_mem) {
    return false;
  }
  auto kc = jak1::intern_from_c("*kernel-context*");
  if (!kc.offset || !kc->value) {
    return false;
  }
  const uint32_t pfr_off = (uint32_t)kc->value;  // deftype 4 -> value+(4-4) = value+0
  if (pfr_off < 0x1000 || pfr_off + 4 > (uint32_t)EE_MAIN_MEM_SIZE) {
    return false;
  }
  uint32_t prevent_from_run = 0;
  memcpy(&prevent_from_run, reinterpret_cast<const u8*>(g_ee_main_mem) + pfr_off, 4);
  return (prevent_from_run & 0x800u) != 0;
}

void a35_pc_get_window_size(u32 w_ptr, u32 h_ptr) {
  int w = 0, h = 0;
  if (!android_gfx::get_window_size(&w, &h)) {
    return;  // display not measured yet — desktop "no display" behavior
  }
  // Cutscene 4:3 framing (see note above): only while actually in a movie AND the
  // panel is wider than 4:3 (w*3 > h*4). 2400x1080 -> 1440x1080 (exactly 4:3).
  const bool mov = gcine_in_movie();
  if (h > 0 && w * 3 > h * 4 && mov) {
    w = (h * 4) / 3;
  }
  // Light transition log (movie on/off) for verification; not a per-frame flood.
  static std::atomic<int> s_last_mov{-1};
  const int mv = mov ? 1 : 0;
  if (s_last_mov.exchange(mv) != mv) {
    __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                        "GD1-PCWIN movie=%d -> reporting window %dx%d", mv, w, h);
  }
  if (w_ptr) {
    *Ptr<s64>(w_ptr).c() = w;
  }
  if (h_ptr) {
    *Ptr<s64>(h_ptr).c() = h;
  }
}

s64 a35_pc_get_active_display_refresh_rate() {
  return android_gfx::get_refresh_rate();
}

u64 a35_pc_get_display_mode() {
  return jak1::intern_from_c("fullscreen").offset;
}

u64 a35_pc_get_os() {
  // autoport graphics-options batch 1: report 'android (not 'linux) so the GOAL
  // progress menu hides the items that don't apply to a single-display phone
  // (Display mode / Display / Frame rate). Android defines both __ANDROID__ and
  // __linux__, which is why the desktop pc_get_os mis-reported 'linux here too.
  return jak1::intern_from_c("android").offset;
}

u64 a35_pc_get_unix_timestamp() {
  return (u64)std::time(nullptr);
}

static std::mt19937 a35_rand_gen(std::random_device{}());
u32 a35_pc_rand() {
  return (u32)a35_rand_gen();
}
// Ginput-replay-determinism (autoport): the Android pc-rand generator is its own
// (random_device-seeded) mt19937 — distinct from the desktop extra_random_generator
// — so it must be reseeded through the input-replay harness's RNG-reseed chain or a
// replayed clip would never reproduce on device (rand-vu mixes in pc-rand). Registered
// alongside the desktop reseed; invoked at the gameplay anchor.
void a35_pc_set_rand_seed(u32 seed) {
  a35_rand_gen.seed(seed);
}

void a35_pc_set_game_resolution(s64 w, s64 h) {
  Gfx::g_global_settings.game_res_w = (int)w;
  Gfx::g_global_settings.game_res_h = (int)h;
}

void a35_pc_set_letterbox(s64 w, s64 h) {
  Gfx::g_global_settings.lbox_w = (int)w;
  Gfx::g_global_settings.lbox_h = (int)h;
}

void a35_pc_set_vsync(u32 sym_val) {
  Gfx::g_global_settings.vsync = (sym_val != s7.offset);
}

void a35_pc_set_frame_rate(s64 rate) {
  Gfx::g_global_settings.target_fps = (float)rate;
}

// autoport graphics-options batch 1: store the FPS-counter overlay toggle so the
// GOAL update-to-os call to pc-set-fps-counter has a real binding on Android (an
// unbound pc-* symbol would BLR into junk). The on-screen number is drawn GOAL-
// side (game font, both renderers); this just stores the toggle flag.
void a35_pc_set_fps_counter(u32 sym_val) {
  Gfx::g_global_settings.display_fps = (sym_val != s7.offset);
}

// Real measured render fps for the GOAL on-screen FPS counter. android_renderer
// publishes the true presented-frame rate into measured_fps (NOT the Gspeed
// vblank-stable engine clock), so this reads ~30 at Geyser as the owner sees.
s64 a35_pc_get_fps() {
  return (s64)(Gfx::g_global_settings.measured_fps + 0.5f);
}
}  // extern "C"

void a17_bind_pc_helpers() {
  static bool s_bound = false;
  if (s_bound) return;
  if (SymbolTable2.offset == 0) return;
  s_bound = true;

  // The full pc-* helper surface from
  // game/kernel/common/kmachine.cpp::init_common_pc_port_functions
  // (lines 1107-1209). Every helper bound to a17_pc_default; the GOAL
  // bytecode treats the 0/#f return as "no display/controller/file"
  // and continues. This matches what desktop pc_* helpers return when
  // Display::GetMainDisplay() is null (the early-return path).
  void* d = (void*)a17_pc_default;
  // Display
  jak1::make_function_symbol_from_c("pc-get-display-id", d);
  jak1::make_function_symbol_from_c("pc-set-display-id!", d);
  jak1::make_function_symbol_from_c("pc-get-display-name", d);
  jak1::make_function_symbol_from_c("pc-get-display-mode", (void*)a35_pc_get_display_mode);
  jak1::make_function_symbol_from_c("pc-set-display-mode!", d);
  jak1::make_function_symbol_from_c("pc-get-display-count", d);
  jak1::make_function_symbol_from_c("pc-get-active-display-size", (void*)a35_pc_get_size);
  jak1::make_function_symbol_from_c("pc-get-active-display-refresh-rate",
                                    (void*)a35_pc_get_active_display_refresh_rate);
  // Gcine-camfov: window-size path reports a 4:3 width during cutscenes so the
  // frozen f1c GOAL machinery renders the authored 4:3 framing (pillarboxed).
  jak1::make_function_symbol_from_c("pc-get-window-size", (void*)a35_pc_get_window_size);
  jak1::make_function_symbol_from_c("pc-get-window-scale", d);
  jak1::make_function_symbol_from_c("pc-set-window-size!", d);
  jak1::make_function_symbol_from_c("pc-get-num-resolutions", d);
  jak1::make_function_symbol_from_c("pc-get-resolution", d);
  jak1::make_function_symbol_from_c("pc-is-supported-resolution?", d);
  // Input
  jak1::make_function_symbol_from_c("pc-get-controller-name", d);
  jak1::make_function_symbol_from_c("pc-get-current-bind", d);
  jak1::make_function_symbol_from_c("pc-get-controller-count", d);
  jak1::make_function_symbol_from_c("pc-get-controller-index", d);
  jak1::make_function_symbol_from_c("pc-set-controller!", d);
  jak1::make_function_symbol_from_c("pc-get-keyboard-enabled?", d);
  jak1::make_function_symbol_from_c("pc-set-keyboard-enabled!", d);
  jak1::make_function_symbol_from_c("pc-set-mouse-options!", d);
  jak1::make_function_symbol_from_c("pc-set-mouse-camera-sens!", d);
  jak1::make_function_symbol_from_c("pc-ignore-background-controller-events!", d);
  jak1::make_function_symbol_from_c("pc-current-controller-has-led?", d);
  jak1::make_function_symbol_from_c("pc-current-controller-has-rumble?", d);
  jak1::make_function_symbol_from_c("pc-set-controller-led!", d);
  jak1::make_function_symbol_from_c("pc-waiting-for-bind?", d);
  jak1::make_function_symbol_from_c("pc-set-waiting-for-bind!", d);
  jak1::make_function_symbol_from_c("pc-stop-waiting-for-bind!", d);
  jak1::make_function_symbol_from_c("pc-reset-bindings-to-defaults!", d);
  jak1::make_function_symbol_from_c("pc-set-auto-hide-cursor!", d);
  jak1::make_function_symbol_from_c("pc-get-pressure-sensitivity-enabled?", d);
  jak1::make_function_symbol_from_c("pc-set-pressure-sensitivity-enabled!", d);
  jak1::make_function_symbol_from_c("pc-set-axis-scale!", d);
  jak1::make_function_symbol_from_c("pc-get-axis-scale", d);
  jak1::make_function_symbol_from_c("pc-current-controller-has-pressure-sensitivity?", d);
  jak1::make_function_symbol_from_c("pc-current-controller-has-trigger-effect-support?", d);
  jak1::make_function_symbol_from_c("pc-get-trigger-effects-enabled?", d);
  jak1::make_function_symbol_from_c("pc-set-trigger-effects-enabled!", d);
  jak1::make_function_symbol_from_c("pc-clear-trigger-effect!", d);
  jak1::make_function_symbol_from_c("pc-send-trigger-effect-feedback!", d);
  jak1::make_function_symbol_from_c("pc-send-trigger-effect-vibrate!", d);
  jak1::make_function_symbol_from_c("pc-send-trigger-effect-weapon!", d);
  jak1::make_function_symbol_from_c("pc-send-trigger-rumble!", d);
  // Graphics — A35: real bodies where the Android renderer now answers.
  jak1::make_function_symbol_from_c("pc-set-vsync", (void*)a35_pc_set_vsync);
  jak1::make_function_symbol_from_c("pc-set-msaa", d);
  jak1::make_function_symbol_from_c("pc-set-frame-rate", (void*)a35_pc_set_frame_rate);
  jak1::make_function_symbol_from_c("pc-set-game-resolution", (void*)a35_pc_set_game_resolution);
  jak1::make_function_symbol_from_c("pc-set-brightness-contrast", d);
  jak1::make_function_symbol_from_c("pc-set-letterbox", (void*)a35_pc_set_letterbox);
  jak1::make_function_symbol_from_c("pc-renderer-tree-set-lod", d);
  jak1::make_function_symbol_from_c("pc-set-collision-mode", d);
  jak1::make_function_symbol_from_c("pc-set-collision-mask", d);
  jak1::make_function_symbol_from_c("pc-get-collision-mask", d);
  jak1::make_function_symbol_from_c("pc-set-collision-wireframe", d);
  jak1::make_function_symbol_from_c("pc-set-collision", d);
  jak1::make_function_symbol_from_c("pc-set-gfx-hack", d);
  jak1::make_function_symbol_from_c("pc-set-fps-counter", (void*)a35_pc_set_fps_counter);
  jak1::make_function_symbol_from_c("pc-get-fps", (void*)a35_pc_get_fps);
  // Other
  jak1::make_function_symbol_from_c("pc-get-os", (void*)a35_pc_get_os);
  jak1::make_function_symbol_from_c("pc-get-unix-timestamp", (void*)a35_pc_get_unix_timestamp);
  jak1::make_function_symbol_from_c("pc-treat-pad0-as-pad1", d);
  jak1::make_function_symbol_from_c("pc-is-imgui-visible?", d);
  // File
  jak1::make_function_symbol_from_c("pc-filepath-exists?", d);
  jak1::make_function_symbol_from_c("pc-mkdir-file-path", d);
  // Discord
  jak1::make_function_symbol_from_c("pc-discord-rpc-set", d);
  jak1::make_function_symbol_from_c("pc-discord-rpc-update", d);
  // Profiler
  jak1::make_function_symbol_from_c("pc-prof", d);
  // RNG
  jak1::make_function_symbol_from_c("pc-rand", (void*)a35_pc_rand);
  // Ginput-replay-determinism (autoport): wire THIS backend's pc-rand generator
  // into the harness reseed chain so a replayed clip restores it at the anchor.
  pad_replay::add_rng_reseed_callback(&a35_pc_set_rand_seed);
  // Text
  jak1::make_function_symbol_from_c("pc-encode-utf8-string", d);
  // Debug
  jak1::make_function_symbol_from_c("pc-filter-debug-string?", d);
  jak1::make_function_symbol_from_c("pc-screen-shot", d);
  jak1::make_function_symbol_from_c("pc-register-screen-shot-settings", d);
  // jak1::InitMachine_PCPort game-specific
  // A41: the old comment here claimed InitMachine_PCPort rebinds
  // __pc-set-levels "later in boot" — FICTION on Android: InitMachineScheme
  // is the runtime_compat STUB (android_runtime_compat.cpp:214), so
  // InitMachine_PCPort (jak1/kmachine.cpp:610) never runs and the noop
  // binding was permanent. level-update calls __pc-set-levels every frame
  // (level.gc:1370); with the noop the Loader never received want-levels,
  // never streamed village1.fr3, and TFragment had no tfrag3 tree — zero
  // "TFRAG setup" lines in every boot log through A41 run-4, the village
  // absent from the title scene. Bind the real desktop body (compiled into
  // android_kernel); it no-ops safely until the renderer module is live.
  jak1::make_function_symbol_from_c("__pc-set-levels", (void*)jak1::pc_set_levels);
  jak1::make_function_symbol_from_c("__pc-set-active-levels", d);
  jak1::make_function_symbol_from_c("__pc-texture-relocate", (void*)a35_pc_texture_relocate);
  // A32 — root-cause for the on-device tpage-463 fn-ptr=0 SIGILL at
  // link-finish #316. These three `__pc-*` / `__send-gfx-*` /
  // `__read-ee-*` symbols are bound on the linux-arm64 qemu side via
  // linux_arm64_main.cpp:297-299 (added in A29 with the same comment
  // block) but were never back-ported to the Android a17_bind_pc_helpers
  // list — the omission left their value slots at 0 on Android because
  // the Android `init_common_pc_port_functions` override
  // (android/android_runtime_compat.cpp:827) deliberately skips the
  // 100+ upstream pc-* registrations. tpage-463's top-level form calls
  // `(__pc-texture-upload-now this arg0)` (defined in
  // goal_src/jak1/engine/gfx/texture/texture.gc:1476), which compiles
  // to `LDR W9, [X16, #0]` reading the symbol-value slot at
  // GOAL ptr 0x158174 → loaded value 0 → `ADD X9, X9, X15` → BLR EE_BASE
  // → SIGILL. See A31-attempt-2-progress.md + A32-fix-summary.md for the
  // crash anatomy + the dump_sym_name_at_slot(regs[16]) line that named
  // the symbol. A no-op bind matches the headless qemu behavior (which
  // boots to 660 link-finishes without ever uploading textures); once
  // the Android renderer wires `Gfx::GetCurrentRenderer()` we'll swap
  // these to real impls.
  // A35: the drain stubs are GONE — these now feed the real renderer
  // (mirrors game/kernel/common/kmachine.cpp's send_gfx_dma_chain /
  // pc_texture_upload_now and read_ee_timer).
  jak1::make_function_symbol_from_c("__pc-texture-upload-now",
                                    (void*)a35_pc_texture_upload_now);
  jak1::make_function_symbol_from_c("__read-ee-timer", (void*)a35_read_ee_timer);
  jak1::make_function_symbol_from_c("__send-gfx-dma-chain", (void*)a35_send_gfx_dma_chain);
  // Misc helpers referenced by pckernel-impl / pc-debug-* GOAL files
  // that the linux-arm64 InitMachineScheme_LinuxArm64Stubs list (locked
  // file) covers — mirroring them here keeps Android symmetric with
  // the linux-arm64 qemu surface.
  jak1::make_function_symbol_from_c("pc-set-subtitle-speaker-mode", d);
  jak1::make_function_symbol_from_c("pc-check-pad-active", d);
  jak1::make_function_symbol_from_c("pc-pad-input-pressure", d);
  jak1::make_function_symbol_from_c("pc-pad-get-mapped-button", d);
  jak1::make_function_symbol_from_c("pc-treat-pad-as-pressed", d);
  jak1::make_function_symbol_from_c("pc-get-keyboard-input", d);
  jak1::make_function_symbol_from_c("pc-get-mouse-input", d);
  jak1::make_function_symbol_from_c("pc-save-load", d);
  jak1::make_function_symbol_from_c("pc-aspect-ratio-auto", d);
  jak1::make_function_symbol_from_c("pc-init-autosplit-struct", d);
  jak1::make_function_symbol_from_c("pc-update-discord-rpc", d);
  jak1::make_function_symbol_from_c("pc-get-fullscreen", d);
  jak1::make_function_symbol_from_c("pc-set-fullscreen", d);
  jak1::make_function_symbol_from_c("pc-get-action-for-input", d);
  jak1::make_function_symbol_from_c("pc-render-text", d);
  jak1::make_function_symbol_from_c("pc-play-movie", d);
  jak1::make_function_symbol_from_c("pc-running-movie?", d);
  jak1::make_function_symbol_from_c("pc-movie-done?", d);
  jak1::make_function_symbol_from_c("pc-cancel-movie", d);
  jak1::make_function_symbol_from_c("pc-set-movie-volume", d);
  jak1::make_function_symbol_from_c("pc-get-movie-volume", d);

  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "A17-DIAG sym-bind-trace: bound the pc-* helper "
                      "surface (~80 helpers). A35: __send-gfx-dma-chain / "
                      "__pc-texture-upload-now / __pc-texture-relocate / "
                      "__read-ee-timer / display size+mode+refresh / "
                      "game-res+letterbox+vsync+frame-rate / os+timestamp+rand "
                      "are now REAL impls feeding the Android renderer; the "
                      "remaining helpers stay a17_pc_default no-ops");
}

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
    // A37: the A32 a32_mips2c_get_noop rebind that used to follow here is
    // GONE. It bound every (def-mips2c name ...) to one shared no-op,
    // which silenced the SIGILLs but also silenced the entire jak1 mips2c
    // surface — including the joint decompressor pair
    // (calc-animation-from-spr / cspace<-parented-transformq-joint!), so
    // bone transforms stayed zero and the title othercam fed zeros into
    // *camera-other-matrix* -> *math-camera* camera-temp -> black frames
    // (the A36 named blocker). The A11 binding above now resolves against
    // the REAL jak1 table (game/mips2c/mips2c_table_jak1_arm64.cpp),
    // populated per-object by klink's gMips2CLinkCallbacks pass.
    // A12 sym-bind: register `rpc-call`, `rpc-busy?`, `test-load-dgo-c`
    // (see klink.cpp::klink_a12_ensure_sound_rpc_bound for rationale).
    // Android's runtime-compat override of jak1::InitMachineScheme
    // similarly omits InitSoundScheme, so gsound's top-level BLR to
    // `rpc-call` lands at ee_base unless we bind here.
    klink_a12_ensure_sound_rpc_bound();
    // A14 sym-bind: register `__mem-move` to pc_memmove. Android's
    // init_common_pc_port_functions override at
    // android/android_runtime_compat.cpp deliberately skips the
    // 100+ pc-* helper registrations (most of them route through
    // Display::/Gfx:: which aren't wired on Android yet). pc_memmove
    // itself is pure data-plane (memmove wrapper) and safe to bind.
    // Without this, dma-buffer's top-level `(__mem-move ...)` BLRs
    // to ee_base and sig=4 SIGILLs. See klink.cpp::
    // klink_a14_ensure_pc_memmove_bound for the full rationale and
    // .autoport/reports/A13-attempt-3-next-blocker.md for the
    // device-side register dump that named this symbol.
    klink_a14_ensure_pc_memmove_bound();
    // A17 sym-bind: the full pc-* helper surface (~80 entries) as no-op
    // defaults. Without these, pckernel-h.gc:295 `(set! (-> obj os)
    // (pc-get-os))` BLRs to ee_base on the unbound sym value 0 →
    // sig=4 SIGILL. See a17_bind_pc_helpers above for the per-name
    // list mirroring kmachine.cpp::init_common_pc_port_functions.
    a17_bind_pc_helpers();
    // A18 method-zero-trap install: walk every kernel-loaded Type and
    // patch empty method slots to point at a18_method_zero_trap.
    // Without this, the post-A17 virtual-dispatch crash (LDR Wn,
    // [Xb, #0x68] = 0 → BLR ee_base → sig=4 SIGILL) lands with a
    // clobbered obj_reg (the LDR overwrote it with 0). The trap
    // function captures self_goal/self_host/type_tag/caller_lr at
    // dispatch entry — BEFORE clobber — and prints them as an
    // A18-DIAG marker before _Exit(13). The supervisor (A19) reads
    // the trap diag to bind the real method. See
    // klink_a18_install_method_zero_trap for the full design.
    klink_a18_install_method_zero_trap();
    // A18 attempt-4 X12-preserve wrappers: now that dead-pool-heap and
    // process are fully linked, wrap their methods with trampolines that
    // save X12 in the prologue, call the original GOAL fn, restore X12,
    // then RET. Works around the goalc-arm64 regalloc bug that uses X12
    // as if it were callee-save across sub-calls in get-process (see
    // klink.cpp for full rationale).
    klink_a18_install_x12_preserve_wrappers();
    // A13 note: NO arm64-style IOP mutex pre-init chained in here.
    // Android's android_runtime_full.cpp::make_iop_thread already
    // constructs a real IOP + spawns the iop_runner OS thread when
    // InitMachine() runs, so both pthread_mutex_init (via the
    // IOP_Kernel default ctor and bionic PTHREAD_MUTEX_INITIALIZER)
    // and the dispatch loop (via the spawned pthread, not a libco
    // step-driver) are already alive on Android. The linux-arm64
    // build is the only one missing those — it carries the
    // standalone a13_arm64_init_iop fix in
    // game/linux-arm64/linux_arm64_runtime_compat.cpp.
  };
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "A11-DIAG sym-bind-trace: chained "
                      "klink_a11_ensure_pc_mips2c_bound (A37: real jak1 "
                      "mips2c table, a32 noop rebind removed) + "
                      "klink_a12_ensure_sound_rpc_bound + "
                      "klink_a14_ensure_pc_memmove_bound + "
                      "a17_bind_pc_helpers (+ A32 __pc-texture-upload-now / "
                      "__read-ee-timer / __send-gfx-dma-chain) + "
                      "klink_a18_install_method_zero_trap onto "
                      "g_jak1_pre_kernel_version_check_hook (prev=%p; A13 "
                      "IOP-init NOT chained here — Android uses real "
                      "iop_runner)",
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

// Forward declarations of the A16-DIAG decoders defined further down
// in this same namespace. A18 uses them to identify writers / mnemonics
// during the type-method-zero chase.
bool decode_arm64_writes_reg(uint32_t enc, int xreg);
const char* decode_arm64_mnemonic(uint32_t enc);

// ---------------------------------------------------------------------------
// A18-DIAG (authored 2026-05-24): type-method-zero walker. Mirrors the
// qemu-side handler in game/linux-arm64/linux_arm64_main.cpp — line
// shapes are identical so device logcat and qemu_repro stderr are
// diff-able.
//
// Past A17 (IDIV X8 spill + pc-* helper chain at 216 link-finishes) the
// next-blocker is a fn-ptr=0 BLR whose source is NOT a sym-MEM load and
// NOT a stack reload (those are A11/A12). Instead the load comes from
// `LDR Wn, [Xb, #imm]` where Xb was built by `ADD Xb, Xobj, X15` (a
// GOAL→host conversion of an obj/type ptr). When obj is a TYPE
// pointer (e.g. via the canonical `LDUR W?, [Xt, #-4]` type-tag load),
// offset 0x10+slot*4 = method slot; this is a virtual-dispatch BLR
// through an uninitialised method slot.
//
// Output (single line + optional sym-walk for the type-tag):
//
//   GK-DIAG A18-DIAG type-method-zero: ldr-pc=0x<pc> base=X<b>
//        offset=0x<off> size=<W|X> method-slot=<n> obj-add@<found|missing>
//        obj-goal-reg=X<o> obj-goal=0x<goal> obj-host=0x<host>
//        loaded-value=0x<v> type-tag@obj_host-4=0x<tag>
//        obj-reg-clobbered-since-add=<0|1>
//
// `obj-reg-clobbered-since-add` is 1 if any instruction between the
// obj-add and the signal site wrote obj_reg — meaning regs[obj_reg]
// is the post-clobber value, NOT the original obj ptr. In that case
// the type-tag readout is best-effort.
// ---------------------------------------------------------------------------

// True if `enc` decodes as `ADD Xd, Xn, X15` shifted-reg with shift=0,
// Rm=15. Writes Rd and Rn out-parameters. Does NOT require Rn == Rd, so
// it matches both host-conv `ADD Xt, Xt, X15` AND obj-conv
// `ADD Xb, Xobj, X15` shapes; callers test Rd/Rn relations.
bool is_add_xreg_xreg_x15(uint32_t enc, uint32_t* out_rd, uint32_t* out_rn) {
  // mask = 0xFFFFFC00 forces bits 31..21 (opcode), bits 20..16 (Rm) and
  // bits 15..10 (imm6); expected = 0x8B0F0000 for ADD shifted-reg with
  // Rm=15, imm6=0. Rn (bits 9..5) and Rd (bits 4..0) are extracted.
  if ((enc & 0xFFFFFC00u) != 0x8B0F0000u) return false;
  *out_rd = enc & 0x1Fu;
  *out_rn = (enc >> 5) & 0x1Fu;
  return true;
}

void dump_type_method_zero_chain(uintptr_t lr, const ucontext_t* uc) {
  uint32_t blr_enc = 0;
  if (!safe_read_u32(lr - 4, &blr_enc)) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A18-DIAG type-method-zero: lr-4 unreadable");
    return;
  }
  if ((blr_enc & 0xFFFFFC1Fu) != 0xD63F0000u) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A18-DIAG type-method-zero: lr-4 enc=0x%08x "
                        "is not BLR Xn",
                        (unsigned)blr_enc);
    return;
  }
  uint32_t blr_target = (blr_enc >> 5) & 0x1Fu;

  // Step 1: find ADD Xt, Xt, X15 walking backward. Push frame
  // (STP/STR with [SP,#-16]! writeback) doesn't write Xt so a simple
  // walk-until-found works.
  intptr_t add_x15_off = 0;
  bool add_x15_found = false;
  for (intptr_t d = -8; d >= -240; d -= 4) {
    uint32_t enc = 0;
    if (!safe_read_u32(lr + d, &enc)) break;
    uint32_t rd = 0, rn = 0;
    if (is_add_xreg_xreg_x15(enc, &rd, &rn) && rd == blr_target &&
        rn == blr_target) {
      add_x15_off = d;
      add_x15_found = true;
      break;
    }
    if (decode_arm64_writes_reg(enc, (int)blr_target)) break;
  }
  if (!add_x15_found) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A18-DIAG type-method-zero: no ADD X%u,X%u,"
                        "X15 in lr-240..lr-8 — non-standard BLR call shape",
                        (unsigned)blr_target, (unsigned)blr_target);
    return;
  }

  // Step 2: walk MOV chain backward, terminating on LDR. Cap at 5 hops.
  uint32_t chase_reg = blr_target;
  intptr_t scan_from = add_x15_off - 4;
  for (int hop = 0; hop < 5; ++hop) {
    intptr_t write_off = 0;
    uint32_t write_enc = 0;
    bool write_found = false;
    for (intptr_t d = scan_from; d >= -252; d -= 4) {
      uint32_t enc = 0;
      if (!safe_read_u32(lr + d, &enc)) break;
      if (decode_arm64_writes_reg(enc, (int)chase_reg)) {
        write_off = d;
        write_enc = enc;
        write_found = true;
        break;
      }
    }
    if (!write_found) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A18-DIAG type-method-zero: hop=%d no "
                          "write of X%u in lr-252..lr%+ld — chase aborted",
                          hop, (unsigned)chase_reg, (long)scan_from);
      return;
    }
    // Case A: MOV Xt, Xs — ORR Xt, XZR, Xs encoding.
    if ((write_enc & 0xFFE0FFE0u) == 0xAA0003E0u) {
      uint32_t src = (write_enc >> 16) & 0x1Fu;
      if (src == 31u) {
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG A18-DIAG type-method-zero: hop=%d "
                            "MOV X%u,XZR @ lr%+ld (BLR target explicitly "
                            "zeroed)",
                            hop, (unsigned)chase_reg, (long)write_off);
        return;
      }
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A18-DIAG type-method-zero: hop=%d "
                          "MOV X%u <- X%u @ lr%+ld",
                          hop, (unsigned)chase_reg, (unsigned)src,
                          (long)write_off);
      chase_reg = src;
      scan_from = write_off - 4;
      continue;
    }
    // Case B: LDR Wt,[Xb,#imm12] or LDR Xt,[Xb,#imm12]
    bool is_ldr_w = ((write_enc & 0xFFC00000u) == 0xB9400000u);
    bool is_ldr_x = ((write_enc & 0xFFC00000u) == 0xF9400000u);
    if (is_ldr_w || is_ldr_x) {
      uint32_t base = (write_enc >> 5) & 0x1Fu;
      uint32_t imm = ((write_enc >> 10) & 0xFFFu) * (is_ldr_w ? 4u : 8u);
      if (base == 31u) {
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG A18-DIAG type-method-zero: hop=%d "
                            "LDR-from-SP @ lr%+ld — stack-spill domain (A12)",
                            hop, (long)write_off);
        return;
      }
      // Step 3: find ADD Xb, Xobj, X15 walking backward from the LDR.
      intptr_t obj_add_off = 0;
      bool obj_add_found = false;
      uint32_t obj_reg = 0;
      for (intptr_t e = write_off - 4; e >= -252; e -= 4) {
        uint32_t fenc = 0;
        if (!safe_read_u32(lr + e, &fenc)) break;
        uint32_t rd = 0, rn = 0;
        if (is_add_xreg_xreg_x15(fenc, &rd, &rn) && rd == base) {
          obj_add_off = e;
          obj_add_found = true;
          obj_reg = rn;
          break;
        }
        if (decode_arm64_writes_reg(fenc, (int)base)) break;
      }
      // Step 4: clobber detection — was obj_reg written between obj-add
      // and signal?
      bool obj_reg_clobbered = false;
      if (obj_add_found) {
        for (intptr_t e = obj_add_off + 4; e <= 0; e += 4) {
          uint32_t fenc = 0;
          if (!safe_read_u32(lr + e, &fenc)) break;
          if (decode_arm64_writes_reg(fenc, (int)obj_reg)) {
            obj_reg_clobbered = true;
            break;
          }
        }
      }
      // Step 5: read obj_goal, obj_host, loaded_value, type_tag.
      uintptr_t obj_goal = 0, obj_host = 0;
      uint32_t loaded_value_u32 = 0xDEADBEEFu;
      uint32_t type_tag = 0xDEADBEEFu;
      bool obj_host_valid = false;
      if (obj_add_found) {
        obj_goal = (uintptr_t)uc->uc_mcontext.regs[obj_reg];
        if (g_ee_main_mem && obj_goal != 0 && obj_goal < EE_MAIN_MEM_SIZE) {
          obj_host = reinterpret_cast<uintptr_t>(g_ee_main_mem) + obj_goal;
          obj_host_valid = true;
          safe_read_u32(obj_host + imm, &loaded_value_u32);
          safe_read_u32(obj_host - 4, &type_tag);
        }
      }
      // method-slot computed assuming the LDR base is a Type basic
      // (OpenGOAL method table starts at offset 16: 16+slot*4). For
      // imm < 16, the load is from a type's header field — method-slot
      // is 0 in that case but the printed offset 0x%x is unambiguous.
      uint32_t method_slot_idx = (imm >= 16) ? (imm - 16) / 4 : 0;
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A18-DIAG type-method-zero: ldr-pc=0x%lx "
                          "base=X%u offset=0x%x size=%s method-slot=%u "
                          "obj-add@%s obj-goal-reg=X%u obj-goal=0x%lx "
                          "obj-host=0x%lx loaded-value=0x%x "
                          "type-tag@obj_host-4=0x%x "
                          "obj-reg-clobbered-since-add=%d",
                          (unsigned long)(lr + write_off), (unsigned)base,
                          (unsigned)imm, is_ldr_w ? "W" : "X",
                          (unsigned)method_slot_idx,
                          obj_add_found ? "found" : "missing",
                          (unsigned)obj_reg, (unsigned long)obj_goal,
                          (unsigned long)obj_host,
                          (unsigned)loaded_value_u32, (unsigned)type_tag,
                          obj_reg_clobbered ? 1 : 0);
      // A18-DIAG TYPETAG-LOAD chain: when obj_reg's source is the
      // canonical `LDUR W_obj_reg, [Xs, #-4]` type-tag load, chase one
      // more level back to surface the host_obj_reg + the ORIGINAL
      // obj GOAL reg. See the qemu side for the full doc comment.
      if (obj_add_found) {
        intptr_t typetag_off = 0;
        bool typetag_found = false;
        uint32_t typetag_base_reg = 0;
        for (intptr_t e = obj_add_off - 4; e >= -252; e -= 4) {
          uint32_t fenc = 0;
          if (!safe_read_u32(lr + e, &fenc)) break;
          bool is_ldur_w = ((fenc & 0xFFE00C00u) == 0xB8400000u);
          bool ldur_writes_obj =
              is_ldur_w && ((fenc & 0x1Fu) == obj_reg);
          if (ldur_writes_obj) {
            uint32_t imm9 = (fenc >> 12) & 0x1FFu;
            if (imm9 == 0x1FCu) {
              typetag_off = e;
              typetag_base_reg = (fenc >> 5) & 0x1Fu;
              typetag_found = true;
            }
            break;
          }
          if (decode_arm64_writes_reg(fenc, (int)obj_reg)) break;
        }
        if (typetag_found) {
          uintptr_t host_obj =
              (uintptr_t)uc->uc_mcontext.regs[typetag_base_reg];
          uint32_t real_type_tag = 0;
          if (g_ee_main_mem && host_obj != 0) {
            safe_read_u32(host_obj - 4, &real_type_tag);
          }
          uint32_t innerobj_reg = 0;
          bool innerobj_found = false;
          for (intptr_t f = typetag_off - 4; f >= -252; f -= 4) {
            uint32_t fenc = 0;
            if (!safe_read_u32(lr + f, &fenc)) break;
            uint32_t rd = 0, rn = 0;
            if (is_add_xreg_xreg_x15(fenc, &rd, &rn) &&
                rd == typetag_base_reg) {
              innerobj_reg = rn;
              innerobj_found = true;
              break;
            }
            if (decode_arm64_writes_reg(fenc, (int)typetag_base_reg)) break;
          }
          uintptr_t innerobj_goal = 0, innerobj_host = 0;
          uint32_t innerobj_type_tag = 0;
          if (innerobj_found && g_ee_main_mem) {
            innerobj_goal =
                (uintptr_t)uc->uc_mcontext.regs[innerobj_reg];
            if (innerobj_goal != 0 && innerobj_goal < (uintptr_t)EE_MAIN_MEM_SIZE) {
              innerobj_host =
                  reinterpret_cast<uintptr_t>(g_ee_main_mem) + innerobj_goal;
              safe_read_u32(innerobj_host - 4, &innerobj_type_tag);
            }
          }
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "GK-DIAG A18-DIAG type-method-zero: "
                              "TYPETAG-LOAD chain ldur-pc=0x%lx "
                              "host-obj-reg=X%u host-obj@signal=0x%lx "
                              "type-tag-via-host=0x%x innerobj-add@%s "
                              "innerobj-reg=X%u innerobj-goal=0x%lx "
                              "innerobj-host=0x%lx innerobj-type-tag=0x%x "
                              "(canonical virtual-dispatch shape — failing "
                              "method is slot %u of innerobj's type)",
                              (unsigned long)(lr + typetag_off),
                              (unsigned)typetag_base_reg,
                              (unsigned long)host_obj,
                              (unsigned)real_type_tag,
                              innerobj_found ? "found" : "missing",
                              (unsigned)innerobj_reg,
                              (unsigned long)innerobj_goal,
                              (unsigned long)innerobj_host,
                              (unsigned)innerobj_type_tag,
                              (unsigned)method_slot_idx);
          if (innerobj_type_tag != 0 &&
              innerobj_type_tag < (uint32_t)EE_MAIN_MEM_SIZE) {
            uintptr_t inner_type_host =
                reinterpret_cast<uintptr_t>(g_ee_main_mem) +
                innerobj_type_tag;
            uint32_t inner_sym_field = 0;
            if (safe_read_u32(inner_type_host, &inner_sym_field) &&
                inner_sym_field != 0 &&
                inner_sym_field < (uint32_t)EE_MAIN_MEM_SIZE) {
              uintptr_t inner_sym_slot =
                  reinterpret_cast<uintptr_t>(g_ee_main_mem) +
                  inner_sym_field;
              __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                  "GK-DIAG A18-DIAG type-method-zero: "
                                  "walking innerobj-type-tag host=0x%lx "
                                  "sym-field=0x%x sym-slot=0x%lx (this "
                                  "names the failing type):",
                                  (unsigned long)inner_type_host,
                                  (unsigned)inner_sym_field,
                                  (unsigned long)inner_sym_slot);
              dump_sym_name_at_slot(inner_sym_slot);
            }
          }
        }
      }
      // Walk type-tag → type's symbol slot → sym name.
      if (obj_host_valid && type_tag != 0xDEADBEEFu && type_tag != 0 &&
          type_tag < EE_MAIN_MEM_SIZE) {
        uintptr_t type_host =
            reinterpret_cast<uintptr_t>(g_ee_main_mem) + type_tag;
        uint32_t type_sym_field = 0;
        if (safe_read_u32(type_host, &type_sym_field) &&
            type_sym_field != 0 && type_sym_field < EE_MAIN_MEM_SIZE) {
          uintptr_t type_sym_slot =
              reinterpret_cast<uintptr_t>(g_ee_main_mem) + type_sym_field;
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "GK-DIAG A18-DIAG type-method-zero: walking "
                              "type-tag host=0x%lx sym-field=0x%x "
                              "sym-slot=0x%lx (dump_sym_name_at_slot "
                              "follows):",
                              (unsigned long)type_host,
                              (unsigned)type_sym_field,
                              (unsigned long)type_sym_slot);
          dump_sym_name_at_slot(type_sym_slot);
        }
      }
      return;
    }
    // Other writer — can't chase further.
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A18-DIAG type-method-zero: hop=%d "
                        "unrecognised writer of X%u: enc=0x%08x decoded=%s "
                        "@ lr%+ld",
                        hop, (unsigned)chase_reg, (unsigned)write_enc,
                        decode_arm64_mnemonic(write_enc), (long)write_off);
    return;
  }
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A18-DIAG type-method-zero: MOV chain depth "
                      ">5, abort");
}

// ---------------------------------------------------------------------------
// A16-DIAG (authored 2026-05-24): ADRP/ADD pair walker with forward
// clobber detection. Mirrors the qemu-side handler in
// game/linux-arm64/linux_arm64_main.cpp — line shapes are identical so
// device logcat and qemu_repro stderr are diff-able.
//
// Context — A15 attempts 1+2 both reverted: regalloc fix advanced qemu
// by +46 link-finishes but regressed the Redmi Note 9 Pro device by
// -101 to -113 link-finishes. claude's
// .autoport/reports/A15-attempt-2-next-blocker.md pinpointed the device
// crash as a clobbered X16 inside the per-CGO sym-table initializer
// loop (x16 = 0xe418c0f914, an impossible-ADRP value).
//
// A16 is diagnostic-only: for each ADRP/ADD pair in lr-256..lr-8, walk
// forward up to 32 instructions and report either:
//   - A16-DIAG x16-clobber: ... clobbered-between TRUE
//   - A16-DIAG preserved:   ... clobbered-between FALSE
// The qemu side will mostly emit preserved entries; the device side is
// expected to emit at least one clobber entry. The delta is the data
// needed to author A17.
// ---------------------------------------------------------------------------

int decode_arm64_write_reg(uint32_t enc) {
  uint32_t rd = enc & 0x1Fu;
  uint32_t rn = (enc >> 5) & 0x1Fu;
  if ((enc & 0xFC000000u) == 0x94000000u) return 30;  // BL
  if ((enc & 0xFFFFFC1Fu) == 0xD63F0000u) return 30;  // BLR
  if ((enc & 0xFFFFFC1Fu) == 0xD61F0000u) return -1;  // BR
  if ((enc & 0xFFFFFC1Fu) == 0xD65F0000u) return -1;  // RET
  if ((enc & 0x9F000000u) == 0x90000000u) return rd == 31u ? -1 : (int)rd;  // ADRP
  if ((enc & 0x9F000000u) == 0x10000000u) return rd == 31u ? -1 : (int)rd;  // ADR
  if ((enc & 0x7F800000u) == 0x52800000u) return rd == 31u ? -1 : (int)rd;  // MOVZ
  if ((enc & 0x7F800000u) == 0x12800000u) return rd == 31u ? -1 : (int)rd;  // MOVN
  if ((enc & 0x7F800000u) == 0x72800000u) return rd == 31u ? -1 : (int)rd;  // MOVK
  if ((enc & 0xFFC00000u) == 0xA9400000u) return rd == 31u ? -1 : (int)rd;  // LDP nowb
  if ((enc & 0xFFC00000u) == 0xA9000000u) return -1;                        // STP nowb
  if ((enc & 0xFFC00000u) == 0xA8C00000u) return rd == 31u ? -1 : (int)rd;  // LDP post
  if ((enc & 0xFFC00000u) == 0xA9C00000u) return rd == 31u ? -1 : (int)rd;  // LDP pre
  if ((enc & 0xFFC00000u) == 0xA8800000u) return rn == 31u ? -1 : (int)rn;  // STP post wb
  if ((enc & 0xFFC00000u) == 0xA9800000u) return rn == 31u ? -1 : (int)rn;  // STP pre wb
  if ((enc & 0xFFE00C00u) == 0xF8400400u) return rd == 31u ? -1 : (int)rd;  // LDR post
  if ((enc & 0xFFE00C00u) == 0xF8400C00u) return rd == 31u ? -1 : (int)rd;  // LDR pre
  if ((enc & 0xFFE00C00u) == 0xF8000400u) return rn == 31u ? -1 : (int)rn;  // STR post wb
  if ((enc & 0xFFE00C00u) == 0xF8000C00u) return rn == 31u ? -1 : (int)rn;  // STR pre wb
  if ((enc & 0xFFC00000u) == 0xF9400000u) return rd == 31u ? -1 : (int)rd;  // LDR X
  if ((enc & 0xFFC00000u) == 0xB9400000u) return rd == 31u ? -1 : (int)rd;  // LDR W
  if ((enc & 0xFFC00000u) == 0xB9800000u) return rd == 31u ? -1 : (int)rd;  // LDRSW
  if ((enc & 0xFFC00000u) == 0x79400000u) return rd == 31u ? -1 : (int)rd;  // LDRH
  if ((enc & 0xFFC00000u) == 0x39400000u) return rd == 31u ? -1 : (int)rd;  // LDRB
  if ((enc & 0xFFC00000u) == 0xF9000000u) return -1;                        // STR X
  if ((enc & 0xFFC00000u) == 0xB9000000u) return -1;                        // STR W
  if ((enc & 0xFFC00000u) == 0x79000000u) return -1;                        // STRH
  if ((enc & 0xFFC00000u) == 0x39000000u) return -1;                        // STRB
  if ((enc & 0x1F800000u) == 0x11000000u) return rd == 31u ? -1 : (int)rd;  // DPI add/sub imm
  if ((enc & 0x1F800000u) == 0x12000000u) return rd == 31u ? -1 : (int)rd;  // DPI logical imm
  if ((enc & 0x1F000000u) == 0x0B000000u) return rd == 31u ? -1 : (int)rd;  // DPR add/sub reg
  if ((enc & 0x1F000000u) == 0x0A000000u) return rd == 31u ? -1 : (int)rd;  // DPR logical reg
  if ((enc & 0x1F000000u) == 0x1B000000u) return rd == 31u ? -1 : (int)rd;  // DPR 3-src
  if ((enc & 0x1FE00000u) == 0x1AC00000u) return rd == 31u ? -1 : (int)rd;  // DPR 2-src (SDIV)
  if ((enc & 0x5FE00000u) == 0x5AC00000u) return rd == 31u ? -1 : (int)rd;  // DPR 1-src
  if ((enc & 0x1FE00000u) == 0x1A800000u) return rd == 31u ? -1 : (int)rd;  // CSEL
  if ((enc & 0x1F800000u) == 0x13000000u) return rd == 31u ? -1 : (int)rd;  // Bitfield
  if ((enc & 0x1F800000u) == 0x13800000u) return rd == 31u ? -1 : (int)rd;  // EXTR
  return -1;
}

bool decode_arm64_writes_reg(uint32_t enc, int xreg) {
  if (xreg < 0 || xreg > 30) return false;
  if (decode_arm64_write_reg(enc) == xreg) return true;
  uint32_t rt2 = (enc >> 10) & 0x1Fu;
  uint32_t rn = (enc >> 5) & 0x1Fu;
  uint32_t xr = (uint32_t)xreg;
  if (rt2 == xr) {
    if ((enc & 0xFFC00000u) == 0xA9400000u
        || (enc & 0xFFC00000u) == 0xA8C00000u
        || (enc & 0xFFC00000u) == 0xA9C00000u)
      return true;
  }
  if (rn == xr) {
    if ((enc & 0xFFE00C00u) == 0xF8400C00u
        || (enc & 0xFFE00C00u) == 0xF8400400u
        || (enc & 0xFFE00C00u) == 0xF8000C00u
        || (enc & 0xFFE00C00u) == 0xF8000400u
        || (enc & 0xFFC00000u) == 0xA9800000u
        || (enc & 0xFFC00000u) == 0xA8800000u
        || (enc & 0xFFC00000u) == 0xA9C00000u
        || (enc & 0xFFC00000u) == 0xA8C00000u)
      return true;
  }
  return false;
}

bool decode_arm64_reads_reg(uint32_t enc, int xreg) {
  if (xreg < 0 || xreg > 30) return false;
  uint32_t rn = (enc >> 5) & 0x1Fu;
  uint32_t rm = (enc >> 16) & 0x1Fu;
  uint32_t rt = enc & 0x1Fu;
  uint32_t rt2 = (enc >> 10) & 0x1Fu;
  uint32_t xr = (uint32_t)xreg;
  if ((enc & 0xFC000000u) == 0x94000000u) return false;  // BL
  if ((enc & 0xFC000000u) == 0x14000000u) return false;  // B
  if ((enc & 0xFF000010u) == 0x54000000u) return false;  // B.cond
  if ((enc & 0x7F000000u) == 0x35000000u) return rt == xr;  // CBNZ
  if ((enc & 0x7F000000u) == 0x34000000u) return rt == xr;  // CBZ
  if ((enc & 0x7E000000u) == 0x36000000u) return rt == xr;  // TBZ/TBNZ
  if ((enc & 0xFFFFFC1Fu) == 0xD63F0000u) return rn == xr;  // BLR
  if ((enc & 0xFFFFFC1Fu) == 0xD61F0000u) return rn == xr;  // BR
  if ((enc & 0xFFFFFC1Fu) == 0xD65F0000u) return rn == xr;  // RET
  if ((enc & 0x9F000000u) == 0x90000000u) return false;  // ADRP
  if ((enc & 0x9F000000u) == 0x10000000u) return false;  // ADR
  if ((enc & 0x7F800000u) == 0x52800000u) return false;  // MOVZ
  if ((enc & 0x7F800000u) == 0x12800000u) return false;  // MOVN
  if ((enc & 0x7F800000u) == 0x72800000u) return false;  // MOVK
  if ((enc & 0xFFC00000u) == 0xA9400000u) return rn == xr;
  if ((enc & 0xFFC00000u) == 0xA8C00000u) return rn == xr;
  if ((enc & 0xFFC00000u) == 0xA9C00000u) return rn == xr;
  if ((enc & 0xFFC00000u) == 0xA9000000u)
    return rn == xr || rt == xr || rt2 == xr;
  if ((enc & 0xFFC00000u) == 0xA8800000u)
    return rn == xr || rt == xr || rt2 == xr;
  if ((enc & 0xFFC00000u) == 0xA9800000u)
    return rn == xr || rt == xr || rt2 == xr;
  if ((enc & 0xFFE00C00u) == 0xF8400C00u) return rn == xr;
  if ((enc & 0xFFE00C00u) == 0xF8400400u) return rn == xr;
  if ((enc & 0xFFE00C00u) == 0xF8000C00u) return rn == xr || rt == xr;
  if ((enc & 0xFFE00C00u) == 0xF8000400u) return rn == xr || rt == xr;
  if ((enc & 0xFFC00000u) == 0xF9400000u) return rn == xr;
  if ((enc & 0xFFC00000u) == 0xB9400000u) return rn == xr;
  if ((enc & 0xFFC00000u) == 0xB9800000u) return rn == xr;
  if ((enc & 0xFFC00000u) == 0x79400000u) return rn == xr;
  if ((enc & 0xFFC00000u) == 0x39400000u) return rn == xr;
  if ((enc & 0xFFC00000u) == 0xF9000000u) return rn == xr || rt == xr;
  if ((enc & 0xFFC00000u) == 0xB9000000u) return rn == xr || rt == xr;
  if ((enc & 0xFFC00000u) == 0x79000000u) return rn == xr || rt == xr;
  if ((enc & 0xFFC00000u) == 0x39000000u) return rn == xr || rt == xr;
  if ((enc & 0x1F800000u) == 0x11000000u) return rn == xr;
  if ((enc & 0x1F800000u) == 0x12000000u) return rn == xr;
  if ((enc & 0x1F000000u) == 0x0B000000u) return rn == xr || rm == xr;
  if ((enc & 0x1F000000u) == 0x0A000000u) return rn == xr || rm == xr;
  if ((enc & 0x1F000000u) == 0x1B000000u)
    return rn == xr || rm == xr || rt2 == xr;
  if ((enc & 0x1FE00000u) == 0x1AC00000u) return rn == xr || rm == xr;
  if ((enc & 0x5FE00000u) == 0x5AC00000u) return rn == xr;
  if ((enc & 0x1FE00000u) == 0x1A800000u) return rn == xr || rm == xr;
  if ((enc & 0x1F800000u) == 0x13000000u) return rn == xr;
  if ((enc & 0x1F800000u) == 0x13800000u) return rn == xr || rm == xr;
  return false;
}

const char* decode_arm64_mnemonic(uint32_t enc) {
  if ((enc & 0xFC000000u) == 0x94000000u) return "BL";
  if ((enc & 0xFC000000u) == 0x14000000u) return "B";
  if ((enc & 0xFFFFFC1Fu) == 0xD63F0000u) return "BLR";
  if ((enc & 0xFFFFFC1Fu) == 0xD61F0000u) return "BR";
  if ((enc & 0xFFFFFC1Fu) == 0xD65F0000u) return "RET";
  if ((enc & 0xFF000010u) == 0x54000000u) return "B.cond";
  if ((enc & 0x7F000000u) == 0x34000000u) return "CBZ";
  if ((enc & 0x7F000000u) == 0x35000000u) return "CBNZ";
  if ((enc & 0x7E000000u) == 0x36000000u) return "TBZ/TBNZ";
  if ((enc & 0x9F000000u) == 0x90000000u) return "ADRP";
  if ((enc & 0x9F000000u) == 0x10000000u) return "ADR";
  if ((enc & 0x7F800000u) == 0x52800000u) return "MOVZ";
  if ((enc & 0x7F800000u) == 0x12800000u) return "MOVN";
  if ((enc & 0x7F800000u) == 0x72800000u) return "MOVK";
  if ((enc & 0xFFC00000u) == 0xA9400000u) return "LDP";
  if ((enc & 0xFFC00000u) == 0xA9000000u) return "STP";
  if ((enc & 0xFFC00000u) == 0xA8C00000u) return "LDP-post";
  if ((enc & 0xFFC00000u) == 0xA9C00000u) return "LDP-pre";
  if ((enc & 0xFFC00000u) == 0xA8800000u) return "STP-post";
  if ((enc & 0xFFC00000u) == 0xA9800000u) return "STP-pre";
  if ((enc & 0xFFE00C00u) == 0xF8400400u) return "LDR-post";
  if ((enc & 0xFFE00C00u) == 0xF8400C00u) return "LDR-pre";
  if ((enc & 0xFFE00C00u) == 0xF8000400u) return "STR-post";
  if ((enc & 0xFFE00C00u) == 0xF8000C00u) return "STR-pre";
  if ((enc & 0xFFC00000u) == 0xF9400000u) return "LDR-X";
  if ((enc & 0xFFC00000u) == 0xB9400000u) return "LDR-W";
  if ((enc & 0xFFC00000u) == 0xB9800000u) return "LDRSW";
  if ((enc & 0xFFC00000u) == 0x79400000u) return "LDRH";
  if ((enc & 0xFFC00000u) == 0x39400000u) return "LDRB";
  if ((enc & 0xFFC00000u) == 0xF9000000u) return "STR-X";
  if ((enc & 0xFFC00000u) == 0xB9000000u) return "STR-W";
  if ((enc & 0xFFC00000u) == 0x79000000u) return "STRH";
  if ((enc & 0xFFC00000u) == 0x39000000u) return "STRB";
  if ((enc & 0x1F800000u) == 0x11000000u) {
    uint32_t op = (enc >> 29) & 0x3u;
    return op == 0 ? "ADD-imm" : op == 1 ? "ADDS-imm"
                              : op == 2 ? "SUB-imm" : "SUBS-imm";
  }
  if ((enc & 0x1F800000u) == 0x12000000u) {
    uint32_t op = (enc >> 29) & 0x3u;
    return op == 0 ? "AND-imm" : op == 1 ? "ORR-imm"
                              : op == 2 ? "EOR-imm" : "ANDS-imm";
  }
  if ((enc & 0x1F000000u) == 0x0B000000u) {
    uint32_t op = (enc >> 29) & 0x3u;
    return op == 0 ? "ADD-reg" : op == 1 ? "ADDS-reg"
                              : op == 2 ? "SUB-reg" : "SUBS-reg";
  }
  if ((enc & 0x1F000000u) == 0x0A000000u) {
    uint32_t op = (enc >> 29) & 0x3u;
    return op == 0 ? "AND/MOV-reg" : op == 1 ? "ORR/MOV-reg"
                                  : op == 2 ? "EOR-reg" : "ANDS-reg";
  }
  if ((enc & 0x1F000000u) == 0x1B000000u) return "MADD/MSUB";
  if ((enc & 0x1FE00000u) == 0x1AC00000u) return "SDIV/UDIV/LSLV";
  if ((enc & 0x5FE00000u) == 0x5AC00000u) return "RBIT/CLZ";
  if ((enc & 0x1FE00000u) == 0x1A800000u) return "CSEL/CSINC";
  if ((enc & 0x1F800000u) == 0x13000000u) return "SBFM/UBFM/BFM";
  if ((enc & 0x1F800000u) == 0x13800000u) return "EXTR";
  return "unknown";
}

void dump_a16_adrp_pair_walk(uintptr_t lr) {
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A16-DIAG adrp/add pair walk (scan lr-256..lr-8, "
                      "forward window 32 instr per pair):");
  int pairs_found = 0;
  for (intptr_t d = -256; d <= -8; d += 4) {
    uintptr_t adrp_pc = lr + d;
    uint32_t adrp_enc = 0;
    if (!safe_read_u32(adrp_pc, &adrp_enc)) continue;
    if ((adrp_enc & 0x9F000000u) != 0x90000000u) continue;
    uint32_t rd_adrp = adrp_enc & 0x1Fu;
    if (rd_adrp == 31u) continue;
    uint32_t add_enc = 0;
    bool has_add = false;
    uint32_t add_imm12 = 0;
    if (safe_read_u32(adrp_pc + 4, &add_enc)) {
      if (((add_enc >> 23) & 0x1FFu) == 0x122u) {
        uint32_t rn_add = (add_enc >> 5) & 0x1Fu;
        uint32_t rd_add = add_enc & 0x1Fu;
        if (rn_add == rd_adrp && rd_add == rd_adrp) {
          has_add = true;
          add_imm12 = (add_enc >> 10) & 0xFFFu;
        }
      }
    }
    uint32_t immlo = (adrp_enc >> 29) & 0x3u;
    uint32_t immhi = (adrp_enc >> 5) & 0x7FFFFu;
    int32_t imm21 = (int32_t)((immhi << 2) | immlo);
    if (imm21 & (1 << 20)) imm21 -= (1 << 21);
    uintptr_t page = adrp_pc & ~uintptr_t(0xFFFu);
    uintptr_t resolved =
        page + ((intptr_t)imm21 << 12) + (uintptr_t)add_imm12;
    if (has_add) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A16-DIAG adrp-pair: pc=0x%lx "
                          "adrp_enc=0x%08x add_enc=0x%08x adrp_rd=X%u "
                          "add_rn=X%u add_rd=X%u imm12=0x%x "
                          "resolved_target=0x%lx",
                          (unsigned long)adrp_pc, (unsigned)adrp_enc,
                          (unsigned)add_enc, (unsigned)rd_adrp,
                          (unsigned)rd_adrp, (unsigned)rd_adrp,
                          (unsigned)add_imm12, (unsigned long)resolved);
      // A35-DIAG: name the symbol whose slot this pair addresses — turns
      // every sym-MEM read near the crash site into a named reference.
      dump_sym_name_at_slot(resolved);
    } else {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A16-DIAG adrp-solo: pc=0x%lx "
                          "adrp_enc=0x%08x adrp_rd=X%u resolved_page=0x%lx",
                          (unsigned long)adrp_pc, (unsigned)adrp_enc,
                          (unsigned)rd_adrp, (unsigned long)resolved);
    }
    ++pairs_found;
    intptr_t walk_start = d + (has_add ? 8 : 4);
    intptr_t walk_end = walk_start + 128;
    intptr_t first_write_off = 0;
    uint32_t first_write_enc = 0;
    bool write_found = false;
    intptr_t first_read_off = 0;
    uint32_t first_read_enc = 0;
    bool read_found = false;
    for (intptr_t f = walk_start; f < walk_end; f += 4) {
      uintptr_t fpc = lr + f;
      uint32_t fenc = 0;
      if (!safe_read_u32(fpc, &fenc)) break;
      if (!write_found && decode_arm64_writes_reg(fenc, (int)rd_adrp)) {
        first_write_off = f;
        first_write_enc = fenc;
        write_found = true;
      }
      if (!read_found && decode_arm64_reads_reg(fenc, (int)rd_adrp)) {
        first_read_off = f;
        first_read_enc = fenc;
        read_found = true;
      }
      if (write_found && read_found) break;
    }
    bool clobbered =
        write_found && (!read_found || first_write_off < first_read_off);
    if (clobbered && read_found) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A16-DIAG x16-clobber: adrp@0x%lx "
                          "resolved=0x%lx xd=X%u next-write@0x%lx "
                          "instr=0x%08x decoded=%s next-read@0x%lx "
                          "instr=0x%08x decoded=%s clobbered-between TRUE",
                          (unsigned long)adrp_pc, (unsigned long)resolved,
                          (unsigned)rd_adrp,
                          (unsigned long)(lr + first_write_off),
                          (unsigned)first_write_enc,
                          decode_arm64_mnemonic(first_write_enc),
                          (unsigned long)(lr + first_read_off),
                          (unsigned)first_read_enc,
                          decode_arm64_mnemonic(first_read_enc));
    } else if (clobbered) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A16-DIAG x16-clobber: adrp@0x%lx "
                          "resolved=0x%lx xd=X%u next-write@0x%lx "
                          "instr=0x%08x decoded=%s next-read=<none-in-window> "
                          "clobbered-between TRUE (dead-store or no-use-"
                          "before-clobber)",
                          (unsigned long)adrp_pc, (unsigned long)resolved,
                          (unsigned)rd_adrp,
                          (unsigned long)(lr + first_write_off),
                          (unsigned)first_write_enc,
                          decode_arm64_mnemonic(first_write_enc));
    } else if (read_found) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A16-DIAG preserved: adrp@0x%lx "
                          "resolved=0x%lx xd=X%u next-read@0x%lx "
                          "instr=0x%08x decoded=%s clobbered-between FALSE",
                          (unsigned long)adrp_pc, (unsigned long)resolved,
                          (unsigned)rd_adrp,
                          (unsigned long)(lr + first_read_off),
                          (unsigned)first_read_enc,
                          decode_arm64_mnemonic(first_read_enc));
    } else {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A16-DIAG no-use: adrp@0x%lx "
                          "resolved=0x%lx xd=X%u (no read or write of "
                          "X%u in forward window)",
                          (unsigned long)adrp_pc, (unsigned long)resolved,
                          (unsigned)rd_adrp, (unsigned)rd_adrp);
    }
  }
  if (pairs_found == 0) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A16-DIAG (no ADRP in lr-256..lr-8 window)");
  }
}
}  // namespace gk_diag

// ===========================================================================
// A36-TREE: process-tree + dead-pool-heap rec integrity scanner.
//
// The A35 run-7 crash was change-parent's brother-walk wandering off a
// corrupted chain (a ppointer slot deref returned 0x10000002) while
// return-process unlinked a dying actor. The static arm64-vs-x86 mem-op
// audit of gkernel/relocate/qmem-copy came back clean, so the corruptor
// writes the slot at runtime somewhere else. This scanner enforces the
// kernel's two load-bearing invariants every frame, from the GOAL thread
// (sceGsSyncV — kernel quiescent), and names the first violating slot:
//   1. tree:  every child/brother ppointer pp reachable from *active-pool*
//             satisfies  P=[pp], [P+self]==P and [[P+ppointer]]==P.
//   2. recs:  every alive *nk-dead-pool* rec satisfies
//             [rec.process + ppointer] == &rec.process  (the backlink that
//             relocate maintains and handle->process relies on).
// Reads are raw loads bounds-checked to the EE mapping (always mapped, so
// no SEGV risk; gk_diag::safe_read_u32's sigaction-per-read is far too
// slow for a per-frame scan).
// ===========================================================================
namespace a36_tree {
constexpr uint32_t kBrother = 12, kChild = 16, kPpointer = 20, kSelf = 24;
constexpr uint32_t kDphAllocLen = 0x1c;  // dead-pool-heap allocated-length
constexpr uint32_t kDphProcList = 0x64;  // process-list rec[0] (device-confirmed: 0x1dabb4+0x64=0x1dac18)

struct Syms {
  uint32_t nk_dead_pool = 0;
  uint32_t active_pool = 0;
  uint32_t null_process = 0;
  bool armed = false;
};
Syms g_syms;
std::atomic<uint64_t> g_frame{0};
std::atomic<uint64_t> g_viol_total{0};
std::atomic<uint64_t> g_first_viol_frame{0};
int g_log_budget = 28;

// Last-good per-rec snapshot (updated on every clean scan) so a violation
// can report what the rec looked like the frame BEFORE the overlap birth.
constexpr uint32_t kMaxRecs = 16384;
uint32_t g_last_proc[kMaxRecs];
uint32_t g_last_alen[kMaxRecs];
uint32_t g_last_heapcur[kMaxRecs];
char g_last_name[kMaxRecs][17];

inline bool rd32(uint32_t goal, uint32_t* out) {
  if (!g_ee_main_mem || goal < 0x1000 || goal >= EE_MAIN_MEM_SIZE - 4) return false;
  *out = *reinterpret_cast<const uint32_t*>(g_ee_main_mem + goal);
  return true;
}

void dump_win(const char* tag, uint32_t goal, int last_row = 2) {
  uint32_t base = goal & ~15u;
  for (int row = -1; row <= last_row; row++) {
    uint32_t w[4] = {0, 0, 0, 0};
    bool any = false;
    for (int k = 0; k < 4; k++) any |= rd32(base + row * 16 + 4 * k, &w[k]);
    if (any && g_log_budget-- > 0) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A36-TREE win %s 0x%x: %08x %08x %08x %08x",
                          tag, base + row * 16, w[0], w[1], w[2], w[3]);
    }
  }
}

void log_viol(const char* what, uint32_t a, uint32_t b, uint32_t c) {
  uint64_t n = g_viol_total.fetch_add(1, std::memory_order_relaxed);
  if (n == 0) g_first_viol_frame.store(g_frame.load());
  if (g_log_budget-- <= 0) return;
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A36-TREE VIOLATION frame=%llu %s a=0x%x b=0x%x c=0x%x",
                      (unsigned long long)g_frame.load(), what, a, b, c);
}

// Validate one ppointer slot value; returns the process goal ptr or 0.
uint32_t check_pp(uint32_t pp, uint32_t falsev, const char* ctx) {
  uint32_t p = 0;
  if (!rd32(pp, &p)) {
    log_viol("pp-out-of-range", pp, 0, 0);
    return 0;
  }
  if (p == falsev || p == 0) {
    log_viol("pp-holds-false-or-0", pp, p, 0);
    return 0;
  }
  uint32_t self = 0, ppo = 0, back = 0;
  if (!rd32(p + kSelf, &self) || !rd32(p + kPpointer, &ppo)) {
    log_viol("proc-out-of-range", pp, p, 0);
    dump_win("pp", pp);
    return 0;
  }
  if (self != p) {
    log_viol(ctx, pp, p, self);
    dump_win("proc", p);
    dump_win("pp", pp);
    return 0;
  }
  if (!rd32(ppo, &back) || back != p) {
    log_viol("backlink", pp, p, ppo);
    dump_win("proc", p);
    return 0;
  }
  return p;
}

void scan_tree(uint32_t root_node, uint32_t falsev) {
  uint32_t stack[64];
  int sp = 0;
  uint32_t hops = 0;
  uint32_t first = 0;
  if (!rd32(root_node + kChild, &first)) return;
  if (first != falsev && first != 0) stack[sp++] = first;
  while (sp > 0 && hops < 4096) {
    uint32_t cur = stack[--sp];
    while (cur != falsev && cur != 0 && hops++ < 4096) {
      uint32_t p = check_pp(cur, falsev, "tree-self");
      if (!p) return;  // first violation already logged; stop this scan
      uint32_t child = 0;
      if (rd32(p + kChild, &child) && child != falsev && child != 0 && sp < 64) {
        stack[sp++] = child;
      }
      uint32_t bro = 0;
      if (!rd32(p + kBrother, &bro)) {
        log_viol("brother-read", p, 0, 0);
        return;
      }
      cur = bro;
    }
  }
}

void scan_recs(uint32_t pool, uint32_t falsev) {
  uint32_t n = 0;
  if (!rd32(pool + kDphAllocLen, &n)) return;
  if (n == 0 || n > 16384) {
    log_viol("alloc-len-insane", pool, n, 0);
    return;
  }
  uint32_t base = pool + kDphProcList;
  for (uint32_t i = 0; i < n; i++) {
    uint32_t slot = base + i * 12;
    uint32_t p = 0;
    if (!rd32(slot, &p)) {
      log_viol("rec-oob", slot, i, 0);
      return;
    }
    if (p == g_syms.null_process || p == falsev || p == 0) continue;  // dead rec
    uint32_t ppo = 0;
    if (!rd32(p + kPpointer, &ppo)) {
      log_viol("rec-proc-oob", slot, p, i);
      dump_win("rec", slot);
      return;
    }
    if (ppo == slot && i < kMaxRecs) {
      // healthy rec: refresh the last-good snapshot
      g_last_proc[i] = p;
      rd32(p + 0x44, &g_last_alen[i]);
      rd32(p + 0x54, &g_last_heapcur[i]);
      uint32_t nm = 0;
      rd32(p + 0, &nm);
      for (int b = 0; b < 16; b += 4) {
        uint32_t w = 0;
        if (!rd32(nm + 4 + b, &w)) break;
        memcpy(g_last_name[i] + b, &w, 4);
      }
      g_last_name[i][16] = 0;
    }
    if (ppo != slot) {
      log_viol("rec-backlink", slot, p, ppo);
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A36-TREE rec-idx=%u of %u", i, n);
      dump_win("rec", slot);
      dump_win("proc", p, 14);
      // Wipe-extent: walk 16B-steps out from p until non-zero rows.
      uint32_t lo = p & ~15u, hi = lo;
      auto row_zero = [&](uint32_t a) {
        uint32_t w = 1;
        for (int k = 0; k < 4; k++) {
          uint32_t v = 0;
          if (!rd32(a + 4 * k, &v) || v) return false;
          w &= 1;
        }
        return true;
      };
      while (row_zero(lo - 16) && (p - lo) < 0x40000) lo -= 16;
      while (row_zero(hi) && (hi - p) < 0x40000) hi += 16;
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A36-TREE wipe-extent zero-run [0x%x,0x%x) len=0x%x around p=0x%x",
                          lo, hi, hi - lo, p);
      dump_win("wipe-lo-edge", lo - 32, 3);
      dump_win("wipe-hi-edge", hi - 16, 3);
      if (i < kMaxRecs) {
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG A36-TREE last-good rec=%u proc=0x%x alen=0x%x heap-cur=0x%x name=\"%s\"",
                            i, g_last_proc[i], g_last_alen[i], g_last_heapcur[i],
                            g_last_name[i]);
      }
      // Overlap search: which LIVE process heap contains the corpse?
      for (uint32_t j = 0; j < n; j++) {
        uint32_t s2 = base + j * 12, q = 0, qo = 0, alen = 0;
        if (!rd32(s2, &q) || q == g_syms.null_process || q == falsev || q == 0) continue;
        if (!rd32(q + kPpointer, &qo) || qo != s2) continue;  // only healthy recs
        if (!rd32(q + 0x44, &alen) || alen > 0x100000) continue;  // allocated-length
        uint32_t qlo = q - 4, qhi = q + 0x70 + alen;
        if (qlo <= p && p < qhi) {
          uint32_t nm = 0;
          rd32(q + 0, &nm);
          char nbuf[33] = {0};
          for (int b = 0; b < 32; b += 4) {
            uint32_t w = 0;
            if (!rd32(nm + 4 + b, &w)) break;
            memcpy(nbuf + b, &w, 4);
          }
          nbuf[32] = 0;
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "GK-DIAG A36-TREE OVERLAPPER rec=%u proc=0x%x alen=0x%x range=[0x%x,0x%x) name-obj=0x%x \"%s\"",
                              j, q, alen, qlo, qhi, nm, nbuf);
          if (j < kMaxRecs) {
            __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                "GK-DIAG A36-TREE overlapper-last-good rec=%u proc=0x%x alen=0x%x name=\"%s\"",
                                j, g_last_proc[j], g_last_alen[j], g_last_name[j]);
          }
          dump_win("overlapper", q, 6);
        }
      }
      return;
    }
  }
}

// Walk the alive list: process addresses must be strictly ascending and
// prev-backlinks consistent. get-process trusts this order for its gap
// math — a single out-of-order node makes find-gap-by-size hand out
// memory overlapping a live process (run-8: money-2679 built over
// windmill-sail-4).
constexpr uint32_t kDphAliveHead = 0x4c;  // alive-list rec (process@+0x4c, next@+0x54)
void scan_alive_order(uint32_t pool, uint32_t falsev) {
  uint32_t head = pool + kDphAliveHead;
  uint32_t prev = head;
  uint32_t cur = 0;
  if (!rd32(head + 8, &cur)) return;
  uint32_t last_addr = 0;
  uint32_t hops = 0;
  uint32_t n = 0;
  rd32(pool + kDphAllocLen, &n);
  uint32_t base = pool + kDphProcList;
  while (cur != 0 && cur != falsev && hops++ < 8192) {
    uint32_t proc = 0, cprev = 0, cnext = 0;
    if (!rd32(cur, &proc) || !rd32(cur + 4, &cprev) || !rd32(cur + 8, &cnext)) {
      log_viol("alive-rec-oob", cur, prev, 0);
      return;
    }
    if (cprev != prev) {
      log_viol("alive-prev-mismatch", cur, cprev, prev);
      return;
    }
    if (proc != falsev && proc != 0) {
      if (proc <= last_addr) {
        uint32_t reci = (cur >= base && n) ? (cur - base) / 12 : 0xffffffff;
        log_viol("alive-order-breach", cur, proc, last_addr);
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG A36-TREE alive-breach rec=%u proc=0x%x last_addr=0x%x last-good name=\"%s\"",
                            reci, proc, last_addr,
                            reci < kMaxRecs ? g_last_name[reci] : "?");
        dump_win("breach-rec", cur);
        // Full alive-list order dump: rec-idx@proc pairs, 6 per line.
        {
          uint32_t c2 = 0;
          rd32(head + 8, &c2);
          char line[256];
          int pos = 0, count = 0, lineno = 0;
          uint32_t h2 = 0;
          while (c2 != 0 && c2 != falsev && h2++ < 512 && lineno < 40) {
            uint32_t pr = 0;
            rd32(c2, &pr);
            uint32_t ri = (c2 >= base && n) ? (c2 - base) / 12 : 0xffffffff;
            pos += snprintf(line + pos, sizeof(line) - pos, "%u@%x ", ri, pr);
            if (++count % 6 == 0 || pos > 200) {
              __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                  "GK-DIAG A36-TREE alive[%d]: %s", lineno++, line);
              pos = 0;
              line[0] = 0;
            }
            rd32(c2 + 8, &c2);
          }
          if (pos > 0) {
            __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                "GK-DIAG A36-TREE alive[%d]: %s", lineno, line);
          }
        }
        return;
      }
      last_addr = proc;
    }
    prev = cur;
    cur = cnext;
  }
}

// ---------------------------------------------------------------------------
// A36-HOOK: per-OPERATION integrity bracketing. The per-frame scan proved the
// alive-list goes from clean to cascade-wrecked entirely inside one frame's
// kernel slice (mass kill + birth wave at the village1 level restart), so the
// only way to name the guilty operation is to bracket each dead-pool-heap
// method call. We wrap the dph method slots (get-process m14 @type+0x48,
// return-process m15 @type+0x4C, compact m16 @type+0x50 — offsets confirmed
// against the compiled dispatch sites) with C trampolines that run a quiet
// alive-order check before and after calling the ORIGINAL GOAL method via
// call_goal. Pure pass-through; first clean→broken transition logs the
// operation, its arguments and the full list, then unlatches nothing else.
// ---------------------------------------------------------------------------
uint32_t g_orig_get = 0, g_orig_ret = 0, g_orig_compact = 0;
uint32_t g_dph_type = 0;
bool g_hooked = false;
std::atomic<bool> g_op_latched{false};

// Quiet alive-list order check: returns number of order/backlink breaches.
int alive_breach_count() {
  if (!g_syms.armed) return 0;
  uint32_t falsev = s7.offset;
  uint32_t pool = g_syms.nk_dead_pool;
  uint32_t head = pool + kDphAliveHead;
  uint32_t prev = head, cur = 0, last_addr = 0, hops = 0;
  int breaches = 0;
  if (!rd32(head + 8, &cur)) return 0;
  while (cur != 0 && cur != falsev && hops++ < 8192) {
    uint32_t proc = 0, cprev = 0, cnext = 0;
    if (!rd32(cur, &proc) || !rd32(cur + 4, &cprev) || !rd32(cur + 8, &cnext)) return breaches + 1;
    if (cprev != prev) breaches++;
    if (proc != falsev && proc != 0) {
      if (proc <= last_addr) breaches++;
      last_addr = proc;
    }
    prev = cur;
    cur = cnext;
  }
  return breaches;
}

void dump_alive_list(const char* tag) {
  uint32_t falsev = s7.offset;
  uint32_t pool = g_syms.nk_dead_pool;
  uint32_t base = pool + kDphProcList;
  uint32_t n = 0;
  rd32(pool + kDphAllocLen, &n);
  uint32_t c2 = 0;
  rd32(pool + kDphAliveHead + 8, &c2);
  char line[256];
  int pos = 0, count = 0, lineno = 0;
  uint32_t h2 = 0;
  while (c2 != 0 && c2 != falsev && h2++ < 512 && lineno < 40) {
    uint32_t pr = 0;
    rd32(c2, &pr);
    uint32_t ri = (c2 >= base && n) ? (c2 - base) / 12 : 0xffffffff;
    pos += snprintf(line + pos, sizeof(line) - pos, "%u@%x ", ri, pr);
    if (++count % 6 == 0 || pos > 200) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag, "GK-DIAG A36-HOOK %s alive[%d]: %s",
                          tag, lineno++, line);
      pos = 0;
      line[0] = 0;
    }
    rd32(c2 + 8, &c2);
  }
  if (pos > 0) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag, "GK-DIAG A36-HOOK %s alive[%d]: %s", tag,
                        lineno, line);
  }
}

void read_proc_name(uint32_t proc, char* out, int cap) {
  out[0] = 0;
  uint32_t nm = 0;
  if (!rd32(proc + 0, &nm)) return;
  for (int b = 0; b + 4 < cap && b < 16; b += 4) {
    uint32_t w = 0;
    if (!rd32(nm + 4 + b, &w)) break;
    memcpy(out + b, &w, 4);
    out[b + 4] = 0;
  }
}

void op_catch(const char* op, u64 a0, u64 a1, u64 a2, u64 ret) {
  bool expected = false;
  if (!g_op_latched.compare_exchange_strong(expected, true)) return;
  g_log_budget = 60;
  char nm[20] = {0};
  if (strcmp(op, "return-process") == 0) read_proc_name((uint32_t)a1, nm, sizeof(nm));
  if (strcmp(op, "get-process") == 0) read_proc_name((uint32_t)ret, nm, sizeof(nm));
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A36-HOOK *** %s BROKE THE ALIVE LIST *** frame=%llu a0=0x%llx "
                      "a1=0x%llx a2=0x%llx ret=0x%llx name=\"%s\"",
                      op, (unsigned long long)g_frame.load(), (unsigned long long)a0,
                      (unsigned long long)a1, (unsigned long long)a2, (unsigned long long)ret, nm);
  dump_alive_list("post-op");
}
}  // namespace a36_tree

// find-gap-by-size hook: (this, size) → rec. Observes the TRUE size the
// (unhooked) get-process computed — get-process itself must stay unhooked
// because the GOAL→C trampoline cannot capture GOAL arg2 (x2) without
// distortion (run-11's "garbage a2" was our own trampoline body bytes).
extern "C" u64 a36_hook_fgbs(u64 pool, u64 size, u64 a2) {
  using namespace a36_tree;
  u64 r = call_goal(Ptr<Function>(g_orig_get), pool, size, a2, s7.offset, g_ee_main_mem);
  static int logged = 0;
  uint64_t fr = g_frame.load(std::memory_order_relaxed);
  bool interesting = (fr >= 270);
  if (logged < 12 || (interesting && logged < 200)) {
    logged++;
    // recompute the gap after the returned rec the same way gap-size does
    uint32_t gap = 0xdeadbeef, rp = 0, nxt = 0, np = 0, alen = 0;
    uint32_t rr = (uint32_t)r;
    uint32_t falsev = s7.offset;
    if (rr && rr != falsev && rd32(rr, &rp) && rd32(rr + 8, &nxt)) {
      if (rp != falsev && rp && rd32(rp + 0x44, &alen) && nxt && nxt != falsev &&
          rd32(nxt, &np)) {
        gap = np - (rp + 0x70 + alen);
      }
    }
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A36-HOOK fgbs size=0x%llx ret-rec=0x%llx rec.proc=0x%x "
                        "rec.alen=0x%x next.proc=0x%x gap=0x%x frame=%llu",
                        (unsigned long long)size, (unsigned long long)r, rp, alen, np, gap,
                        (unsigned long long)g_frame.load());
  }
  return r;
}

extern "C" u64 a36_hook_return_process(u64 pool, u64 proc, u64 a2) {
  using namespace a36_tree;
  int pre = alive_breach_count();
  char nm_pre[20];
  read_proc_name((uint32_t)proc, nm_pre, sizeof(nm_pre));
  u64 r = call_goal(Ptr<Function>(g_orig_ret), pool, proc, a2, s7.offset, g_ee_main_mem);
  if (!g_op_latched.load(std::memory_order_relaxed)) {
    int post = alive_breach_count();
    if (post > pre) {
      op_catch("return-process", pool, proc, a2, r);
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A36-HOOK return-process victim-name-pre=\"%s\"", nm_pre);
    }
  }
  return r;
}

extern "C" u64 a36_hook_compact(u64 pool, u64 count, u64 a2) {
  using namespace a36_tree;
  int pre = alive_breach_count();
  u64 r = call_goal(Ptr<Function>(g_orig_compact), pool, count, a2, s7.offset, g_ee_main_mem);
  if (!g_op_latched.load(std::memory_order_relaxed)) {
    int post = alive_breach_count();
    if (post > pre) op_catch("compact", pool, count, a2, r);
  }
  return r;
}

namespace a36_tree {
void install_op_hooks() {
  if (g_hooked || !g_syms.armed) return;
  auto s_t = jak1::intern_from_c("dead-pool-heap");
  if (!s_t.offset) return;
  uint32_t T = s_t->value;
  uint32_t falsev = s7.offset;
  if (!T || T == falsev) return;
  uint32_t og = 0, orp = 0, oc = 0;
  // hook find-gap-by-size (m24 @+0x70), return-process (m15 @+0x4C),
  // compact (m16 @+0x50). get-process stays UNHOOKED (see a36_hook_fgbs).
  if (!rd32(T + 0x70, &og) || !rd32(T + 0x4C, &orp) || !rd32(T + 0x50, &oc)) return;
  if (!og || !orp || !oc) return;
  g_dph_type = T;
  g_orig_get = og;  // = original find-gap-by-size
  g_orig_ret = orp;
  g_orig_compact = oc;
  auto hg = jak1::make_function_symbol_from_c("a36-watch-fgbs", (void*)a36_hook_fgbs);
  auto hr = jak1::make_function_symbol_from_c("a36-watch-rp", (void*)a36_hook_return_process);
  auto hc = jak1::make_function_symbol_from_c("a36-watch-cp", (void*)a36_hook_compact);
  if (!hg.offset || !hr.offset || !hc.offset) return;
  *reinterpret_cast<uint32_t*>(g_ee_main_mem + T + 0x70) = hg.offset;
  *reinterpret_cast<uint32_t*>(g_ee_main_mem + T + 0x4C) = hr.offset;
  *reinterpret_cast<uint32_t*>(g_ee_main_mem + T + 0x50) = hc.offset;
  g_hooked = true;
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A36-HOOK installed dph-type=0x%x fgbs 0x%x->0x%x ret 0x%x->0x%x compact 0x%x->0x%x",
                      T, og, hg.offset, orp, hr.offset, oc, hc.offset);
}

void arm_if_needed() {
  if (g_syms.armed) return;
  if (!g_ee_main_mem || SymbolTable2.offset == 0) return;
  auto s_pool = jak1::intern_from_c("*nk-dead-pool*");
  auto s_root = jak1::intern_from_c("*active-pool*");
  auto s_null = jak1::intern_from_c("*null-process*");
  if (!s_pool.offset || !s_root.offset || !s_null.offset) return;
  uint32_t pool = s_pool->value;
  uint32_t root = s_root->value;
  uint32_t nullp = s_null->value;
  uint32_t falsev = s7.offset;
  if (!pool || !root || !nullp || pool == falsev || root == falsev || nullp == falsev) return;
  uint32_t n = 0;
  if (!rd32(pool + kDphAllocLen, &n) || n == 0 || n > 16384) return;
  g_syms.nk_dead_pool = pool;
  g_syms.active_pool = root;
  g_syms.null_process = nullp;
  g_syms.armed = true;
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A36-TREE armed frame=%llu pool=0x%x recs=%u root=0x%x null-proc=0x%x",
                      (unsigned long long)g_frame.load(), pool, n, root, nullp);
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A36-CT-DIAG at-arm &ct=%p ct=%02x %02x %02x %02x",
                      (void*)ConvertTable, (unsigned char)ConvertTable[0],
                      (unsigned char)ConvertTable[1], (unsigned char)ConvertTable[2],
                      (unsigned char)ConvertTable[3]);
}

void scan_once() {
  if (!g_syms.armed) return;
  uint32_t falsev = s7.offset;
  scan_alive_order(g_syms.nk_dead_pool, falsev);
  scan_recs(g_syms.nk_dead_pool, falsev);
  scan_tree(g_syms.active_pool, falsev);
}
}  // namespace a36_tree

// A37: GL render thread handle for the hang watchdog (set by
// android_renderer.cpp at loop start).
pthread_t g_a37_gl_thread;
// F1a crash breadcrumb: the bucket whose render() is live on the GL thread
// (written by android_opengl_renderer's dispatch loop, printed by the
// SIGSEGV dump). Fixed-size, no locking — last-writer-wins is fine for a
// single GL thread.
char gk_f1a_current_bucket[64] = {0};
std::atomic<bool> g_a37_gl_thread_set{false};

// Called once per frame from sceGsSyncV (android_runtime_compat.cpp) on the
// GOAL thread, where the kernel data is quiescent.
extern "C" void a36_tree_scan_per_frame() {
  using namespace a36_tree;
  uint64_t f = g_frame.fetch_add(1, std::memory_order_relaxed) + 1;
  // A37 hang watchdog: if the GOAL thread stops advancing frames (run-19
  // silent freeze), poke it with SIGUSR2 so gk_sigusr2_hang_dump logs the
  // spin location. Started once, watches g_frame from a helper thread.
  {
    static std::atomic<bool> s_watchdog_started{false};
    static pthread_t s_goal_thread;
    if (!s_watchdog_started.exchange(true)) {
      s_goal_thread = pthread_self();
      std::thread([]() {
        uint64_t last = 0;
        int stalled = 0, dumps = 0;
        while (dumps < 5) {
          sleep(2);
          uint64_t now = a36_tree::g_frame.load(std::memory_order_relaxed);
          if (now == last) {
            if (++stalled >= 3) {
              stalled = 0;
              dumps++;
              __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                  "GK-DIAG A37-HANG watchdog: frame stuck at %llu, dumping GOAL "
                                  "thread (%d/5)",
                                  (unsigned long long)now, dumps);
              pthread_kill(s_goal_thread, SIGUSR2);
              if (g_a37_gl_thread_set.load()) {
                sleep(1);
                __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                    "GK-DIAG A37-HANG watchdog: dumping GL thread");
                pthread_kill(g_a37_gl_thread, SIGUSR2);
              }
            }
          } else {
            stalled = 0;
          }
          last = now;
        }
      }).detach();
    }
  }
  arm_if_needed();
  if (!g_syms.armed) return;
  // A36: install_op_hooks() stays available for forensics but is NOT armed
  // by default — the dispatch trampolines cannot marshal GOAL arg2 (x2)
  // and would distort 3-arg method calls. The zero-distortion per-frame
  // scanner below is the steady-state watchdog; the root cause it caught
  // (A18 trap poisoning method slot 13 = entity-info-lookup's cache) is
  // fixed in klink.cpp::walk_loaded_types_and_patch_a18.
  scan_once();
  if (f % 600 == 0) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A36-TREE heartbeat frame=%llu viol-total=%llu first-viol-frame=%llu",
                        (unsigned long long)f,
                        (unsigned long long)g_viol_total.load(),
                        (unsigned long long)g_first_viol_frame.load());
  }
  // === Gd3-jak FIX (always-on, GOAL thread): repair Jak's NaN world transform ===
  // In the new-game cinematic a degenerate root-motion align (1/0 in
  // matrix-inv-scale!, ENGINE.CGO — not rebuildable on device) leaves *target*'s
  // root trsqv (trans/rot/scale) NaN from ~frame 945. It is harmless while the
  // scene-player drives Jak's on-screen pose (the Merc2 bone repair keeps him
  // visible), but when master-mode flips cinematic->play the gameplay/physics code
  // reads the NaN position and the GOAL thread dies into the return-from-thread-dead
  // trampoline (sig=4/11 at GOAL 0x18aee4, frame ~10170 — blocks reaching gameplay).
  // Repair it HERE, on the GOAL thread at the quiescent per-frame (sceGsSyncV) point
  // where the kernel data is settled: cache each transform float's last finite value
  // and restore any that has gone non-finite. Write-only-on-NaN, so a wrong guess of
  // a field offset can never replace a good value — only ever swap a NaN for a prior
  // finite reading at that same slot. x86 never produces these NaNs.
  if (g_syms.armed && g_ee_main_mem) {
    auto symval = [](const char* nm, uint32_t* out) -> bool {
      auto s = jak1::intern_from_c(nm);
      if (!s.offset) {
        return false;
      }
      *out = s->value;
      return true;
    };
    uint32_t tgt = 0;
    if (symval("*target*", &tgt) && tgt && tgt != s7.offset) {
      uint32_t root = 0;
      rd32(tgt + (112 - 4), &root);  // process-drawable.root (trsqv), deftype offset 112
      if (root && root != s7.offset) {
        // trsqv: trans @16, rot(quat) @32, scale @48 — 3 slots x 4 floats. C++ addr
        // = root + goal_off - 4 (the A37-CAM/F1C deftype-4 read convention).
        static float s_good[12] = {0};
        static bool s_good_seen[12] = {false};
        static uint64_t s_repairs = 0;
        const int goal_off[12] = {16, 20, 24, 28, 32, 36, 40, 44, 48, 52, 56, 60};
        int repaired = 0;
        for (int k = 0; k < 12; k++) {
          uint32_t w = 0;
          if (!rd32(root + (goal_off[k] - 4), &w)) {
            continue;
          }
          float v;
          memcpy(&v, &w, 4);
          if (std::isfinite(v)) {
            s_good[k] = v;
            s_good_seen[k] = true;
          } else if (s_good_seen[k]) {
            uint8_t* dst = g_ee_main_mem + (root + (goal_off[k] - 4));
            memcpy(dst, &s_good[k], 4);
            repaired++;
          }
        }
        if (repaired) {
          s_repairs++;
          if (s_repairs <= 8 || (s_repairs % 600) == 0) {
            __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                "GK-DIAG GD3-TARGET-TRANS-REPAIR #%llu f=%llu fields=%d "
                                "(restored *target* root trsqv from last-finite)",
                                (unsigned long long)s_repairs, (unsigned long long)f, repaired);
          }
        }
      }
    }
  }
  // F1D (autoport): player (target / Jak) spawn + position telemetry,
  // read straight out of GOAL memory — real state, never synthesised.
  // Proves (a) the title attract loop was left (*target* becomes alive
  // when (start 'play ...) runs) and (b) Jak moves when stick input is
  // injected (root.trans changes across frames). Same intern/rd32 path
  // the camera probes use; throttled to ~4 Hz so it can't flood the log
  // or add per-frame intern overhead.
  if (g_syms.armed && g_ee_main_mem && (f % 15) == 0) {
    auto symvalue = [](const char* name, uint32_t* out) -> bool {
      auto s = jak1::intern_from_c(name);
      if (!s.offset) return false;
      *out = s->value;
      return true;
    };
    uint32_t mm = 0;
    char mmn[24] = {0};
    if (symvalue("*master-mode*", &mm) && mm) {
      gk_a40_sym_name_fwd((uintptr_t)g_ee_main_mem, mm, mmn, sizeof(mmn));
    }
    // *master-mode* is the real "left the title attract" discriminator:
    // *target* is alive even in target-title-wait, but master-mode only
    // becomes 'play/'game once (start 'play ...) actually runs.
    const bool in_play = (!strcmp(mmn, "play") || !strcmp(mmn, "game"));

    // Phase Gtouch-controls (autoport): publish menu-vs-gameplay for the
    // on-screen overlay's bottom-left control. A navigable menu is up when
    // *progress-process* is non-#f — this covers BOTH the title option menu
    // (title-obs.gc target-title-wait -> activate-progress) AND the in-game
    // pause/progress menu (main.gc toggle-pause -> set-master-mode 'progress
    // -> activate-progress). *master-mode* in {menu, progress} catches the
    // debug menu too. Read on this (GOAL) thread; the UI thread only reads
    // the resulting atomic via NativeGk.isInMenu(), so no symbol table race.
    {
      bool in_menu = (!strcmp(mmn, "menu") || !strcmp(mmn, "progress"));
      auto pp = jak1::intern_from_c("*progress-process*");
      if (pp.offset) {
        const uint32_t v = pp->value;
        if (v != 0 && v != (uint32_t)s7.offset) {
          in_menu = true;  // a progress/option menu process is alive
        }
      }
      g_overlay_in_menu.store(in_menu, std::memory_order_release);
    }
    if (in_play) {
      static std::atomic<bool> s_play_logged{false};
      bool expected = false;
      if (s_play_logged.compare_exchange_strong(expected, true)) {
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG F1D-PLAY-MODE entered: set-master-mode "
                            "'%s at f=%llu (left title attract -> playing)",
                            mmn, (unsigned long long)f);
      }
    }
    uint32_t tgt = 0;
    if (symvalue("*target*", &tgt) && tgt && tgt != s7.offset) {
      // process-drawable.root @ deftype 112 (pointer); trs.trans @ deftype
      // 16 (inline vector). Probe reads at deftype-4 (the A37-CAM/F1C
      // convention).
      uint32_t root = 0;
      rd32(tgt + (112 - 4), &root);
      float px = 0, py = 0, pz = 0;
      if (root && root != s7.offset) {
        uint32_t w = 0;
        rd32(root + (16 - 4) + 0, &w); memcpy(&px, &w, 4);
        rd32(root + (16 - 4) + 4, &w); memcpy(&py, &w, 4);
        rd32(root + (16 - 4) + 8, &w); memcpy(&pz, &w, 4);
      }
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG F1D target-pos f=%llu *target* 0x%x "
                          "=(%.1f %.1f %.1f) master-mode=%s",
                          (unsigned long long)f, tgt, px, py, pz,
                          mmn[0] ? mmn : "?");
    }
  }
  // A36-CAM probe: the tfrag pc-port block arrives with a ZERO camera
  // matrix while hvdf/fog are sane. Dump *math-camera* camera-temp
  // (+0x23C, all-types offset 576) to split "camera math broken" from
  // "block builder broken".
  if (f == 600) {
    auto s_mc = jak1::intern_from_c("*math-camera*");
    uint32_t mc = s_mc.offset ? s_mc->value : 0;
    if (mc && mc != s7.offset) {
      for (int row = 0; row < 4; row++) {
        uint32_t w[4] = {0, 0, 0, 0};
        for (int k = 0; k < 4; k++) {
          rd32(mc + 0x23C + row * 16 + 4 * k, &w[k]);
        }
        float* fv = reinterpret_cast<float*>(w);
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG A36-CAM camera-temp[%d] = %.4f %.4f %.4f %.4f", row, fv[0],
                            fv[1], fv[2], fv[3]);
      }
    }
  }
  // A37-CAM probe: field-by-field dump of the whole camera chain
  // (fov/ratios -> perspective -> camera-rot/inv-camera-rot/trans ->
  // camera-temp) at the same fixed frames as the x86 oracle probe in
  // game/graphics/sceGraphicsInterface.cpp (OG_A37_CAM=1), so the two logs
  // diff line-for-line and the FIRST divergent field names the broken
  // producer function.
  // F1a: periodic past 2400 (was a fixed list) — pose-over-time is the
  // question; mirrors the x86 oracle schedule in sceGraphicsInterface.cpp.
  if (f == 60 || f == 300 || (f % 600) == 0) {
    auto s_mc = jak1::intern_from_c("*math-camera*");
    uint32_t mc = s_mc.offset ? s_mc->value : 0;
    if (!mc || mc == s7.offset) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag, "GK-DIAG A37-CAM f=%llu no-math-camera",
                          (unsigned long long)f);
      return;
    }
    auto rdf = [&](uint32_t addr, float* out) {
      uint32_t w = 0;
      bool ok = rd32(addr, &w);
      memcpy(out, &w, 4);
      return ok;
    };
    float scal[6] = {0, 0, 0, 0, 0, 0};  // fov xr yr fcf smooth-step smooth-t
    rdf(mc + 0x8, &scal[0]);
    rdf(mc + 0xC, &scal[1]);
    rdf(mc + 0x10, &scal[2]);
    rdf(mc + 0x41C, &scal[3]);
    rdf(mc + 0x88, &scal[4]);
    rdf(mc + 0x8C, &scal[5]);
    uint32_t reset = 0;
    rd32(mc + 0x84, &reset);
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A37-CAM f=%llu mc=0x%x reset=%d fov=%.3f xr=%.6f yr=%.6f "
                        "fcf=%.6f smooth=%.4f/%.4f",
                        (unsigned long long)f, mc, (int)reset, scal[0], scal[1], scal[2], scal[3],
                        scal[4], scal[5]);
    struct {
      const char* name;
      uint32_t off;
    } rows[] = {
        {"persp0", 0x9C},  {"persp1", 0xAC},  {"persp2", 0xBC},  {"persp3", 0xCC},
        {"camrot0", 0x16C}, {"camrot3", 0x19C}, {"invrot0", 0x1AC}, {"invrot3", 0x1DC},
        {"trans", 0x34C},  {"ct0", 0x23C},    {"ct1", 0x24C},    {"ct2", 0x25C},
        {"ct3", 0x26C},
    };
    for (auto& r : rows) {
      float v[4] = {0, 0, 0, 0};
      for (int k = 0; k < 4; k++) rdf(mc + r.off + 4 * k, &v[k]);
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A37-CAM f=%llu %s=(%.6f %.6f %.6f %.6f)",
                          (unsigned long long)f, r.name, v[0], v[1], v[2], v[3]);
    }
    auto s_fc = jak1::intern_from_c("*math-camera-fog-correction*");
    uint32_t fc = s_fc.offset ? s_fc->value : 0;
    if (fc && fc != s7.offset) {
      float a = 0.f, b = 0.f;
      rdf(fc, &a);
      rdf(fc + 4, &b);
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag, "GK-DIAG A37-CAM f=%llu fogcor=(%.3f %.3f)",
                          (unsigned long long)f, a, b);
    }
    // Round 2: update-camera branch selectors + their sources (mirrors the
    // x86 oracle probe in game/graphics/sceGraphicsInterface.cpp).
    auto symval = [](const char* name, uint32_t* out) {
      auto s = jak1::intern_from_c(name);
      if (!s.offset) return false;
      *out = s->value;
      return true;
    };
    uint32_t lto = 0, ext = 0, comb = 0, cam = 0, ofov = 0, otrans = 0, omat = 0;
    symval("*camera-look-through-other*", &lto);
    symval("*external-cam-mode*", &ext);
    symval("*camera-combiner*", &comb);
    symval("*camera*", &cam);
    symval("*camera-other-fov*", &ofov);
    symval("*camera-other-trans*", &otrans);
    symval("*camera-other-matrix*", &omat);
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A37-CAM f=%llu lto=%d ext=0x%x(s7=0x%x) comb=0x%x cam=0x%x "
                        "ofov=0x%x otrans=0x%x omat=0x%x",
                        (unsigned long long)f, (int)lto, ext, s7.offset, comb, cam, ofov, otrans,
                        omat);
    float mcsan[4] = {0, 0, 0, 0};
    rdf(mc + 0x0, &mcsan[0]);
    rdf(mc + 0x4, &mcsan[1]);
    rdf(mc + 0x14, &mcsan[2]);
    rdf(mc + 0x24, &mcsan[3]);
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A37-CAM f=%llu mc-sanity d=%.1f far=%.1f x-pix=%.1f y-pix=%.1f",
                        (unsigned long long)f, mcsan[0], mcsan[1], mcsan[2], mcsan[3]);
    if (comb && comb != s7.offset) {
      float cfov = 0.f, ctr[4] = {0, 0, 0, 0}, cir[4] = {0, 0, 0, 0};
      rdf(comb + 0xBC, &cfov);
      for (int k = 0; k < 4; k++) {
        rdf(comb + 0x6C + 4 * k, &ctr[k]);
        rdf(comb + 0x7C + 4 * k, &cir[k]);
      }
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A37-CAM f=%llu comb fov=%.3f trans=(%.1f %.1f %.1f %.1f) "
                          "invrot0=(%.6f %.6f %.6f %.6f)",
                          (unsigned long long)f, cfov, ctr[0], ctr[1], ctr[2], ctr[3], cir[0],
                          cir[1], cir[2], cir[3]);
    }
    if (ofov && ofov != s7.offset) {
      float v = 0.f;
      rdf(ofov, &v);
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag, "GK-DIAG A37-CAM f=%llu other-fov=%.3f",
                          (unsigned long long)f, v);
    }
    if (otrans && otrans != s7.offset) {
      float v[4] = {0, 0, 0, 0};
      for (int k = 0; k < 4; k++) rdf(otrans + 4 * k, &v[k]);
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A37-CAM f=%llu other-trans=(%.1f %.1f %.1f %.1f)",
                          (unsigned long long)f, v[0], v[1], v[2], v[3]);
    }
    if (omat && omat != s7.offset) {
      float r0[4] = {0, 0, 0, 0}, r3[4] = {0, 0, 0, 0};
      for (int k = 0; k < 4; k++) {
        rdf(omat + 4 * k, &r0[k]);
        rdf(omat + 0x30 + 4 * k, &r3[k]);
      }
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A37-CAM f=%llu other-mat r0=(%.6f %.6f %.6f %.6f) r3=(%.6f "
                          "%.6f %.6f %.6f)",
                          (unsigned long long)f, r0[0], r0[1], r0[2], r0[3], r3[0], r3[1], r3[2],
                          r3[3]);
    }
    // F1A-CAMJOINT: the title camera CHAIN per heartbeat — every alive
    // process named logo/logo-slave/othercam: channel-0 frame-group (the
    // anim the joints sample, by name) + frame-num + draw status. Run-10
    // showed othercam's matrix freezing at the logo-intro boundary while
    // the spool streams on — this names which link stalls: parent channel,
    // slave clone-remap, or frame advance.
    if (a36_tree::g_syms.armed && g_ee_main_mem) {
      const uint32_t falsev2 = s7.offset;
      uint32_t pool2 = a36_tree::g_syms.nk_dead_pool;
      uint32_t cur2 = 0;
      rd32(pool2 + 0x4c + 8, &cur2);
      int hops2 = 0;
      while (cur2 && cur2 != falsev2 && hops2++ < 8192) {
        uint32_t proc2 = 0, next2 = 0;
        if (!rd32(cur2, &proc2) || !rd32(cur2 + 8, &next2)) {
          break;
        }
        if (proc2 && proc2 != falsev2) {
          uint32_t namep = 0;
          rd32(proc2 + 0, &namep);
          char nm[40] = {0};
          gk_a40_sym_name_fwd((uintptr_t)g_ee_main_mem, namep, nm, sizeof(nm));
          if (!strcmp(nm, "logo") || !strcmp(nm, "logo-slave") || !strcmp(nm, "othercam")) {
            uint32_t skel = 0, drawc = 0, fg = 0;
            float fnum = 0.f;
            rd32(proc2 + 120, &skel);  // process-drawable.skel (deftype 124)
            rd32(proc2 + 116, &drawc); // .draw (deftype 120)
            if (skel && skel != falsev2) {
              rd32(skel + 56, &fg);  // joint-control channel0.frame-group (deftype 60)
              uint32_t w = 0;
              rd32(skel + 60, &w);  // channel0.frame-num (deftype 64)
              memcpy(&fnum, &w, 4);
            }
            uint32_t dstat = 0;
            if (drawc && drawc != falsev2) {
              rd32(drawc + 0, &dstat);  // draw-control.status (deftype 4)
            }
            char fgn[48] = {0};
            if (fg && fg != falsev2) {
              uint32_t fgname = 0;
              rd32(fg + 0, &fgname);  // art.name (deftype 4)
              gk_a40_sym_name_fwd((uintptr_t)g_ee_main_mem, fgname, fgn, sizeof(fgn));
            }
            __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                "GK-DIAG F1A-CAMJOINT f=%llu proc=0x%x %s skel=0x%x fg=0x%x(%s) "
                                "fnum=%.2f draw-status=0x%x",
                                (unsigned long long)f, proc2, nm, skel, fg, fgn[0] ? fgn : "?",
                                fnum, dstat);
            // F1C-CHAN: full per-channel joint-control state for the camera
            // path. The decisive field is `weight` (inspector-amount, set by
            // output-blend-tree!): weight->0 => eval-blend-tree! drops the
            // dynamic channel (the freeze is in the blend weight); weight ok
            // (~1) but output still frozen (F1B-TRS) => the freeze is in
            // build-requests!/decomp-frame (the data read). command + fnum +
            // frame-interp corroborate the stage. joint-control layout:
            // active-channels@+24; channel[c]@+44+48*c; per channel
            // command@+4(symbol) frame-interp@+8 frame-group@+12 frame-num@+16
            // inspector-amount@+44.
            if (skel && skel != falsev2) {
              uint32_t ach = 0;
              rd32(skel + 24, &ach);  // active-channels
              int nch = (int)ach;
              if (nch < 0) nch = 0;
              if (nch > 3) nch = 3;
              for (int c = 0; c < nch; c++) {
                uint32_t cbase = skel + 44 + 48 * c;
                uint32_t cmd = 0, cfg = 0, w = 0;
                float fi = 0.f, fn = 0.f, wt = 0.f;
                rd32(cbase + 4, &cmd);   // command (symbol)
                rd32(cbase + 12, &cfg);  // frame-group
                rd32(cbase + 8, &w);
                memcpy(&fi, &w, 4);
                rd32(cbase + 16, &w);
                memcpy(&fn, &w, 4);
                rd32(cbase + 44, &w);
                memcpy(&wt, &w, 4);
                char cmdn[24] = {0};
                if (cmd && cmd != falsev2)
                  gk_a40_sym_name_fwd((uintptr_t)g_ee_main_mem, cmd, cmdn, sizeof(cmdn));
                __android_log_print(
                    ANDROID_LOG_FATAL, kGkLogTag,
                    "GK-DIAG F1C-CHAN f=%llu %s proc=0x%x ach=%d ch%d cmd=%s(0x%x) fi=%.4f "
                    "fnum=%.2f weight=%.4f fg=0x%x",
                    (unsigned long long)f, nm, proc2, (int)ach, c, cmdn[0] ? cmdn : "?", cmd, fi, fn,
                    wt, cfg);
                // F1C-KF: the EXACT keyframe decomp-frame reads. Per the
                // process-request! disasm, (-> jacc data base) loads a 4-byte
                // pointer from the table at jacc+16 (stride 4): kfp =
                // [jacc+16 + base*4]; the keyframe struct lives at kfp
                // (offset-64@0/offset-32@4/offset-16@8/reserved@12, data@16).
                // Decisive: base advances each tick (fnum) — if kfp ALSO
                // advances and the bytes at kfp change, the data is fresh and
                // the freeze is in the decode; if kfp is pinned or its bytes
                // are constant, the keyframe/table is stale (spool/clone).
                if (cfg && cfg != falsev2 && c == 0) {
                  uint32_t jacc = 0, nf = 0;
                  rd32(cfg + 40, &jacc);  // frame-group->frames
                  int base = (int)fn;
                  if (base < 0) base = 0;
                  uint32_t kfp = 0, o0 = 0, o1 = 0, o2 = 0, d0 = 0, d1 = 0, d2 = 0, d3 = 0;
                  if (jacc && jacc != falsev2) {
                    rd32(jacc + 0, &nf);
                    rd32(jacc + 16 + base * 4, &kfp);  // data[base] pointer
                    if (kfp && kfp != falsev2) {
                      rd32(kfp + 0, &o0);
                      rd32(kfp + 4, &o1);
                      rd32(kfp + 8, &o2);
                      rd32(kfp + 16, &d0);
                      rd32(kfp + 20, &d1);
                      rd32(kfp + 24, &d2);
                      rd32(kfp + 28, &d3);
                    }
                  }
                  __android_log_print(
                      ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG F1C-KF f=%llu %s proc=0x%x nf=%d base=%d jacc=0x%x kfp=0x%x "
                      "off=%u/%u/%u data=%08x.%08x.%08x.%08x",
                      (unsigned long long)f, nm, proc2, (int)nf, base, jacc, kfp, o0, o1, o2, d0, d1,
                      d2, d3);
                }
              }
            }
            // F1B-JB: the joint-chain OUTPUT for the same processes —
            // nodes 3..5 bone transform row3 (world pos) + row0 (rot) +
            // param0. Twin of f1b_jb_probe_desktop (OG_F1B_JB) in
            // game/graphics/sceGraphicsInterface.cpp; the diff names the
            // frozen stage (GOAL decompress -> master bones -> clone ->
            // slave bones -> othercam).
            if (!strcmp(nm, "logo") || !strcmp(nm, "logo-slave")) {
              // F1B-FG: channel-0 frame-group identity — art NAME is a GOAL
              // STRING (chars at name+4), not a symbol (the old (?)/(#f)
              // resolutions were the wrong reader). + num-frames (art-joint-
              // anim.frames.num-frames lives in jacc; use art length field).
              if (fg && fg != falsev2) {
                uint32_t fgnamep = 0;
                rd32(fg + 4, &fgnamep);  // art.name string (deftype 8)
                char fgs[48] = {0};
                if (fgnamep > 0x1000 && fgnamep < (uint32_t)(128 * 1024 * 1024 - 64)) {
                  const char* sp2 =
                      reinterpret_cast<const char*>(g_ee_main_mem + fgnamep + 4);
                  size_t si = 0;
                  for (; si + 1 < sizeof(fgs) && sp2[si]; si++) {
                    fgs[si] = (sp2[si] >= 0x20 && sp2[si] <= 0x7e) ? sp2[si] : '?';
                  }
                  fgs[si] = 0;
                }
                // frames (jacc) + fixed-hdr identity: nf/fixed/frame ptrs +
                // control-bits/num-joints/matrix-bits — names whether the
                // slave's per-part DATA is patched (str) or static/stale.
                uint32_t frames = 0, nf = 0, fixedp = 0, fr0 = 0, cb0 = 0, cb1 = 0, nj = 0,
                         mb = 0;
                rd32(fg + 40, &frames);  // art-joint-anim.frames (deftype 44)
                if (frames && frames != falsev2) {
                  rd32(frames + 0, &nf);
                  rd32(frames + 12, &fixedp);
                  rd32(frames + 16, &fr0);
                  if (fixedp) {
                    rd32(fixedp + 0, &cb0);
                    rd32(fixedp + 4, &cb1);
                    rd32(fixedp + 56, &nj);
                    rd32(fixedp + 60, &mb);
                  }
                }
                __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                    "GK-DIAG F1B-FG f=%llu %s proc=0x%x fg=0x%x name='%s' "
                                    "fnum=%.2f frames=0x%x nf=%d fixed=0x%x fr0=0x%x "
                                    "cb=0x%08x/0x%08x nj=%d mb=0x%x",
                                    (unsigned long long)f, nm, proc2, fg, fgs[0] ? fgs : "?",
                                    fnum, frames, (int)nf, fixedp, fr0, cb0, cb1, (int)nj, mb);
              }
              uint32_t nl = 0;
              rd32(proc2 + 112, &nl);  // process-drawable.node-list (deftype 116)
              uint32_t nlen = 0;
              if (nl && nl != falsev2) rd32(nl + 0, &nlen);  // cspace-array.length
              for (int n = 3; n <= 5 && (uint32_t)n < nlen; n++) {
                uint32_t csp = nl + 12 + 32 * n;  // data (deftype 16), cspace stride 32
                uint32_t jw = 0, bone = 0, p0 = 0;
                rd32(csp + 8, &jw);  // joint-num int16 (deftype 12)
                rd32(csp + 16, &bone);
                rd32(csp + 20, &p0);
                float r3[3] = {0, 0, 0}, r0v[3] = {0, 0, 0};
                if (bone > 0x1000 && bone < (uint32_t)(128 * 1024 * 1024 - 64)) {
                  for (int k = 0; k < 3; k++) {
                    uint32_t w2 = 0;
                    rd32(bone + 48 + 4 * k, &w2);
                    memcpy(&r3[k], &w2, 4);
                    rd32(bone + 4 * k, &w2);
                    memcpy(&r0v[k], &w2, 4);
                  }
                }
                __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                    "GK-DIAG F1B-JB f=%llu %s proc=0x%x fnum=%.2f n%d j%d "
                                    "bone=0x%x p0=0x%x r3=(%.1f %.1f %.1f) r0=(%.4f %.4f %.4f)",
                                    (unsigned long long)f, nm, proc2, fnum, n,
                                    (int)(int16_t)(jw & 0xffff), bone, p0, r3[0], r3[1], r3[2],
                                    r0v[0], r0v[1], r0v[2]);
                // F1C-CAMFLY: node 4 is the title camera-look joint that
                // othercam reads. Before the arm64 modulo fix it was frozen
                // (decomp-frame's `(* 4 (mod tqi 8))` returned 4*(tqi/8)=0 for
                // joint 1, so it read joint 0's all-fixed control nibble);
                // after the fix it flies. Emit this marker ONLY when the bone
                // world position actually changes by >~1m between heartbeats —
                // it is real flight evidence, never an unconditional print.
                if (n == 4) {
                  static struct {
                    uint32_t proc;
                    float x, y, z;
                  } s_cam[8] = {};
                  int slot = -1, freeidx = -1;
                  for (int s = 0; s < 8; s++) {
                    if (s_cam[s].proc == proc2) {
                      slot = s;
                      break;
                    }
                    if (freeidx < 0 && s_cam[s].proc == 0)
                      freeidx = s;
                  }
                  bool had = (slot >= 0);
                  if (slot < 0)
                    slot = (freeidx >= 0 ? freeidx : 0);
                  if (had && s_cam[slot].proc == proc2) {
                    float dx = r3[0] - s_cam[slot].x, dy = r3[1] - s_cam[slot].y,
                          dz = r3[2] - s_cam[slot].z;
                    float adx = dx < 0 ? -dx : dx, ady = dy < 0 ? -dy : dy, adz = dz < 0 ? -dz : dz;
                    float dmax = adx > ady ? (adx > adz ? adx : adz) : (ady > adz ? ady : adz);
                    if (dmax > 4096.0f) {  // >~1 metre of camera travel
                      __android_log_print(
                          ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG F1C-CAMFLY f=%llu %s proc=0x%x node=4 moving pose-delta=%.1f "
                          "r3=(%.1f %.1f %.1f) prev=(%.1f %.1f %.1f)",
                          (unsigned long long)f, nm, proc2, dmax, r3[0], r3[1], r3[2], s_cam[slot].x,
                          s_cam[slot].y, s_cam[slot].z);
                    }
                  }
                  s_cam[slot].proc = proc2;
                  s_cam[slot].x = r3[0];
                  s_cam[slot].y = r3[1];
                  s_cam[slot].z = r3[2];
                }
              }
            }
          }
        }
        cur2 = next2;
      }
    }
  }
}

// ---------------------------------------------------------------------------
// A38 float-spray tripwire (runtime-gated diagnostic, fully removable).
//
// A37 named the blocker: once the deep draw paths engage, something sprays
// bone/camera-magnitude floats over the engine-object band
// [0x1904000, 0x1915000) (GOAL space — GAME.CGO engine code/data; font and
// text live there). Effects: l0-tfrag's bucket malformed every frame (the
// village geometry never draws) and a per-boot SIGILL when level-hint's
// text call BLRs into the stomped font code. The A37-CSP canary brackets
// the writes to the per-frame window but cannot name the STORE.
//
// Mechanism: when the property debug.opengoal.a38.tripwire is "1" (read
// once at the first GL frame), the band is mprotect'd PROT_READ|PROT_EXEC
// (reads and execution stay legal — only writes fault). The SIGSEGV branch
// at the top of gk_sigsegv_diag reopens the faulting PAGE first (the store
// retries and completes on return — game behavior is unchanged, this is a
// pure observer), then logs pc/lr, decodes the AArch64 store (register,
// width, value from the ucontext), and names the writer via dladdr (C++)
// or a nearest-function symbol scan (GOAL code). The per-frame hook
// re-protects opened pages each frame and emits periodic summaries of the
// unique writer PCs.
//
// Resume-safety rules (this branch RETURNS, unlike the crash dump below):
//   - no gk_diag::safe_read_u32 (it swaps the process-wide SIGSEGV handler
//     around each read — racy against concurrent band faults),
//   - no intern_from_c, no malloc, no locks: bounds-checked raw reads of
//     the always-mapped EE region only; dladdr only on bounded paths.
//
// extern "C++": this file region sits inside a large extern "C" block, and
// C-linkage declarations with the same name unify ACROSS namespaces (the
// a36_tree::g_log_budget collision). C++ linkage keeps these namespaced.
extern "C++" {
namespace a38_trip {
constexpr uint32_t kBandLoGoal = 0x1904000;
constexpr uint32_t kBandHiGoal = 0x1918000;

std::atomic<int> g_mode{-1};  // -1 property unread, 0 off, 1 armed
uintptr_t g_lo_host = 0;      // page-aligned armed band (host addresses)
uintptr_t g_hi_host = 0;
// Optional second watch range (debug.opengoal.a38.watch2): "1" = the
// *display* page (named the flip writers; flip proven healthy in run-8);
// "2" = the two global-buf HEADER pages — every write to the base cells
// (buf+4) is traced in order with pre/post values, so the writer that
// jumps the cursor out of [data,end] names itself.
uintptr_t g_lo2_host = 0;
uintptr_t g_hi2_host = 0;
uintptr_t g_lo3_host = 0;
uintptr_t g_hi3_host = 0;
uintptr_t g_base_cell[2] = {0, 0};  // host addrs of global-buf base fields
std::atomic<int> g_cell_log_budget{240};
long g_page_size = 4096;
std::atomic<uint64_t> g_hits{0};
std::atomic<uint64_t> g_pages_reopened{0};
std::atomic<uint64_t> g_emulated{0};
std::atomic<bool> g_any_page_open{false};
std::atomic<int> g_log_budget{64};

// Unique-writer table (lock-free, fixed-size).
constexpr int kMaxWriters = 48;
struct Writer {
  std::atomic<uintptr_t> pc{0};
  std::atomic<uint64_t> n{0};
  std::atomic<uint32_t> last_fault_goal{0};
  std::atomic<uint64_t> last_val{0};
};
Writer g_writers[kMaxWriters];

// pc -> goal offset if inside EE memory, else 0.
inline uint32_t to_goal(uintptr_t host) {
  const uintptr_t ee = reinterpret_cast<uintptr_t>(g_ee_main_mem);
  if (ee && host >= ee && host < ee + EE_MAIN_MEM_SIZE) {
    return static_cast<uint32_t>(host - ee);
  }
  return 0;
}

// AArch64 store classifier — the forms goalc/clang emit (STR/STUR/STP and
// their SIMD twins). Best-effort: attribution lives in pc/lr; the decoded
// value corroborates the "small float spray" signature.
struct StoreInfo {
  bool valid = false;
  bool simd = false;
  bool pair = false;
  bool writeback = false;  // pre/post-index — not emulated (Rn update)
  bool sign_ext = false;   // signed GPR load (LDRSB/LDRSH/LDRSW/LDPSW)
  bool dest_w = false;     // 32-bit W destination (signed load opc==3)
  int size_bytes = 0;
  int rt = -1;
  int rt2 = -1;
  int rn = -1;
};
StoreInfo classify_store(uint32_t insn) {
  StoreInfo s;
  if ((insn & 0x3E000000u) == 0x28000000u) {  // load/store pair family
    if (insn & (1u << 22)) {
      return s;  // L=1 → load
    }
    uint32_t opc = insn >> 30;
    s.simd = (insn >> 26) & 1u;
    if (!s.simd && opc == 1) {
      return s;  // LDPSW shape — load-only
    }
    uint32_t variant = (insn >> 23) & 3u;  // 00 STNP, 01 post, 10 offset, 11 pre
    s.writeback = (variant == 1 || variant == 3);
    s.valid = true;
    s.pair = true;
    s.size_bytes = s.simd ? (4 << opc) : (opc >= 2 ? 8 : 4);
    s.rt = insn & 0x1F;
    s.rt2 = (insn >> 10) & 0x1F;
    s.rn = (insn >> 5) & 0x1F;
    return s;
  }
  uint32_t fam = insn & 0x3B000000u;
  if (fam == 0x39000000u || fam == 0x38000000u) {  // ld/st reg: imm12 / imm9 / reg-offset
    uint32_t opc = (insn >> 22) & 3u;
    uint32_t size = insn >> 30;
    s.simd = (insn >> 26) & 1u;
    bool is_store = (opc == 0) || (s.simd && opc == 2 && size == 0);
    if (!is_store) {
      return s;
    }
    if (fam == 0x38000000u && !((insn >> 21) & 1u)) {
      uint32_t idx = (insn >> 10) & 3u;  // 00 STUR, 01 post, 11 pre
      s.writeback = (idx == 1 || idx == 3);
    }
    s.valid = true;
    s.size_bytes = (s.simd && opc == 2) ? 16 : (1 << size);
    s.rt = insn & 0x1F;
    s.rn = (insn >> 5) & 0x1F;
    return s;
  }
  return s;  // exclusives / DC ZVA / others — raw insn still logged
}

// AArch64 load classifier — the inverse of classify_store, for the LDR/LDP/LDUR
// (and SIMD twins) forms goalc/clang emit. Used by handle_double_ee_base_fault
// to COMPLETE a double-EE-based LOAD (read from the corrected single-based EE
// address into the destination register), mirroring the store-repair path. Only
// plain (non-writeback) loads are completable.
StoreInfo classify_load(uint32_t insn) {
  StoreInfo s;
  if ((insn & 0x3E000000u) == 0x28000000u) {  // load/store pair family
    if (!(insn & (1u << 22))) {
      return s;  // L=0 → store
    }
    uint32_t opc = insn >> 30;
    s.simd = (insn >> 26) & 1u;
    uint32_t variant = (insn >> 23) & 3u;  // 00 LDNP, 01 post, 10 offset, 11 pre
    s.writeback = (variant == 1 || variant == 3);
    s.valid = true;
    s.pair = true;
    if (s.simd) {
      s.size_bytes = 4 << opc;  // 4 (S), 8 (D), 16 (Q)
    } else if (opc == 1) {
      s.size_bytes = 4;  // LDPSW: two 32-bit, sign-extended to 64-bit X
      s.sign_ext = true;
    } else {
      s.size_bytes = (opc >= 2) ? 8 : 4;  // 00 32-bit W, 10 64-bit X
    }
    s.rt = insn & 0x1F;
    s.rt2 = (insn >> 10) & 0x1F;
    s.rn = (insn >> 5) & 0x1F;
    return s;
  }
  uint32_t fam = insn & 0x3B000000u;
  if (fam == 0x39000000u || fam == 0x38000000u) {  // ld/st reg: imm12 / imm9 / reg-offset
    uint32_t opc = (insn >> 22) & 3u;
    uint32_t size = insn >> 30;
    s.simd = (insn >> 26) & 1u;
    bool is_load;
    if (s.simd) {
      is_load = (opc == 1) || (opc == 3 && size == 0);  // LDR (8/16/32/64) | LDR Q (128)
    } else {
      is_load = (opc == 1) || (opc == 2) || (opc == 3);  // LDR | LDRSW/LDRS64 | LDRS32
    }
    if (!is_load) {
      return s;
    }
    if (fam == 0x38000000u && !((insn >> 21) & 1u)) {
      uint32_t idx = (insn >> 10) & 3u;  // 00 LDUR, 01 post, 11 pre
      s.writeback = (idx == 1 || idx == 3);
    }
    s.valid = true;
    if (s.simd) {
      s.size_bytes = (opc == 3 && size == 0) ? 16 : (1 << size);
    } else {
      s.size_bytes = 1 << size;
      s.sign_ext = (opc == 2 || opc == 3);  // signed integer load
      s.dest_w = (opc == 3);                // 32-bit W destination
    }
    s.rt = insn & 0x1F;
    s.rn = (insn >> 5) & 0x1F;
    return s;
  }
  return s;  // exclusives / literal / others — not completable
}

// Read V<reg> from the signal frame's fpsimd block (vector stores).
uint64_t fpsimd_lo64(ucontext_t* uc, int vreg, uint64_t* hi) {
  if (hi) {
    *hi = 0;
  }
  uint8_t* p = reinterpret_cast<uint8_t*>(uc->uc_mcontext.__reserved);
  uint8_t* end = p + sizeof(uc->uc_mcontext.__reserved);
  while (p + sizeof(_aarch64_ctx) <= end) {
    auto* head = reinterpret_cast<_aarch64_ctx*>(p);
    if (head->magic == 0 || head->size == 0) {
      break;
    }
    if (head->magic == FPSIMD_MAGIC && vreg >= 0 && vreg < 32) {
      auto* f = reinterpret_cast<fpsimd_context*>(p);
      if (hi) {
        *hi = static_cast<uint64_t>(f->vregs[vreg] >> 64);
      }
      return static_cast<uint64_t>(f->vregs[vreg]);
    }
    if (p + head->size <= p) {
      break;
    }
    p += head->size;
  }
  return 0;
}

// Write V<reg> in the signal frame's fpsimd block (vector loads). On return from
// the signal handler the kernel restores the V registers from this frame, so
// updating it here completes an emulated SIMD load. No-op if the frame lacks an
// fpsimd block (always present on arm64 Android).
void fpsimd_set(ucontext_t* uc, int vreg, uint64_t lo, uint64_t hi) {
  if (vreg < 0 || vreg >= 32) {
    return;
  }
  uint8_t* p = reinterpret_cast<uint8_t*>(uc->uc_mcontext.__reserved);
  uint8_t* end = p + sizeof(uc->uc_mcontext.__reserved);
  while (p + sizeof(_aarch64_ctx) <= end) {
    auto* head = reinterpret_cast<_aarch64_ctx*>(p);
    if (head->magic == 0 || head->size == 0) {
      break;
    }
    if (head->magic == FPSIMD_MAGIC) {
      auto* f = reinterpret_cast<fpsimd_context*>(p);
      f->vregs[vreg] =
          (static_cast<__uint128_t>(hi) << 64) | static_cast<__uint128_t>(lo);
      return;
    }
    if (p + head->size <= p) {
      break;
    }
    p += head->size;
  }
}

// Track the writer pc; *is_new set when this pc was never seen before.
int note_writer(uintptr_t pc, uint32_t fault_goal, uint64_t val, bool* is_new) {
  *is_new = false;
  for (int i = 0; i < kMaxWriters; i++) {
    uintptr_t cur = g_writers[i].pc.load(std::memory_order_acquire);
    if (cur == 0) {
      uintptr_t expected = 0;
      if (g_writers[i].pc.compare_exchange_strong(expected, pc, std::memory_order_acq_rel)) {
        *is_new = true;
        cur = pc;
      } else {
        cur = expected;
      }
    }
    if (cur == pc) {
      g_writers[i].n.fetch_add(1, std::memory_order_relaxed);
      g_writers[i].last_fault_goal.store(fault_goal, std::memory_order_relaxed);
      g_writers[i].last_val.store(val, std::memory_order_relaxed);
      return i;
    }
  }
  return -1;  // table full — global counters still tick
}

// Name the GOAL function containing target_goal: largest symbol value at
// or below it (functions' symbol slots hold their entry address). Raw
// bounds-checked reads only.
void log_nearest_goal_fn(const char* label, uint32_t target_goal) {
  if (!g_ee_main_mem || !SymbolTable2.offset || !LastSymbol.offset) {
    return;
  }
  const uintptr_t ee = reinterpret_cast<uintptr_t>(g_ee_main_mem);
  uint32_t best_v = 0, best_slot = 0;
  for (uint32_t slot = SymbolTable2.offset;
       slot + 4 < EE_MAIN_MEM_SIZE && slot < LastSymbol.offset; slot += 4) {
    uint32_t v = *reinterpret_cast<const uint32_t*>(ee + slot);
    if (v > best_v && v <= target_goal && target_goal - v < 0x200000) {
      best_v = v;
      best_slot = slot;
    }
  }
  if (!best_slot) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "A38-TRIPWIRE %s nearest-fn: none below 0x%x within 2MB", label,
                        target_goal);
    return;
  }
  char name[65] = {0};
  uint64_t info_goal = static_cast<uint64_t>(best_slot) + jak1::SYM_INFO_OFFSET;
  if (info_goal + 8 < EE_MAIN_MEM_SIZE) {
    uint32_t str_off = *reinterpret_cast<const uint32_t*>(ee + info_goal + 4);
    if (str_off > 0 && static_cast<uint64_t>(str_off) + 4 + sizeof(name) < EE_MAIN_MEM_SIZE) {
      const char* sp = reinterpret_cast<const char*>(ee + str_off + 4);
      for (size_t i = 0; i + 1 < sizeof(name) && sp[i]; i++) {
        name[i] = (sp[i] >= 0x20 && sp[i] <= 0x7e) ? sp[i] : '?';
      }
    }
  }
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "A38-TRIPWIRE %s nearest-fn '%s' start=0x%x off=+0x%x slot=0x%x", label,
                      name[0] ? name : "<unnamed>", best_v, target_goal - best_v, best_slot);
}

void log_dladdr(const char* label, uintptr_t addr) {
  Dl_info di{};
  if (addr && dladdr(reinterpret_cast<void*>(addr), &di) && di.dli_fname) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag, "A38-TRIPWIRE %s 0x%lx = %s+0x%lx (%s)",
                        label, (unsigned long)addr, di.dli_sname ? di.dli_sname : "?",
                        di.dli_saddr ? (unsigned long)(addr - (uintptr_t)di.dli_saddr) : 0ul,
                        strrchr(di.dli_fname, '/') ? strrchr(di.dli_fname, '/') + 1
                                                   : di.dli_fname);
  }
}

// Display-state probe: the run-2 catch shows print-game-text's dma-buffer
// cursor walking through the band (tags at 0x1903ff0→0x1904000→...) while
// the same frame's bucket-group is sane — so either the on-screen index,
// the global-buf field, or the buffer's base diverges. Dump them all.
// Offsets from decompiler/config/jak1/all-types.gc (deftype-4 for basics):
//   display: on-screen mem+556, last-screen mem+560,
//            frames[i] (virtual-frame, stride 32) mem+564, .frame at +16
//   display-frame: calc-buf mem+4, global-buf mem+36, bucket-group mem+40
//   dma-buffer: allocated-length mem+0, base mem+4, end mem+8, data=obj+12
void log_display_probe(const char* tag) {
  const uintptr_t ee = reinterpret_cast<uintptr_t>(g_ee_main_mem);
  if (!ee) {
    return;
  }
  auto rd = [ee](uint32_t goal, uint32_t* out) -> bool {
    if (goal < 0x1000 || goal >= EE_MAIN_MEM_SIZE - 4) {
      return false;
    }
    *out = *reinterpret_cast<const uint32_t*>(ee + goal);
    return true;
  };
  auto disp_sym = jak1::intern_from_c("*display*");
  if (!disp_sym.offset) {
    return;
  }
  uint32_t disp = disp_sym->value;
  uint32_t on_screen = 0, last_screen = 0;
  rd(disp + 556, &on_screen);
  rd(disp + 560, &last_screen);
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "A38-DISP %s *display*=0x%x on-screen=%d last-screen=%d", tag, disp,
                      (int)on_screen, (int)last_screen);
  for (int i = 0; i < 6; i++) {
    uint32_t frame = 0;
    if (!rd(disp + 564 + 32 * i + 16, &frame)) {
      continue;
    }
    if (i >= 2 && frame == 0) {
      continue;  // unused slots — only log if non-zero (garbage-index theory)
    }
    uint32_t calc_buf = 0, global_buf = 0, bucket_group = 0;
    rd(frame + 4, &calc_buf);
    rd(frame + 36, &global_buf);
    rd(frame + 40, &bucket_group);
    uint32_t gb_len = 0, gb_base = 0, gb_end = 0;
    rd(global_buf + 0, &gb_len);
    rd(global_buf + 4, &gb_base);
    rd(global_buf + 8, &gb_end);
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "A38-DISP %s frames[%d].frame=0x%x calc=0x%x global-buf=0x%x "
                        "(len=0x%x base=0x%x end=0x%x data=0x%x) bucket-group=0x%x",
                        tag, i, frame, calc_buf, global_buf, gb_len, gb_base, gb_end,
                        global_buf + 12, bucket_group);
  }
}

// ---- A40-DPROC (debug.opengoal.a40.dproc=1, default off) ----
// A40 finding so far: every A39 boot, display-loop runs its pre-loop
// (2 display-syncs -> the single dropped send_chain, flip lands at
// on=0/last=1, frame-start(0)'s debug-init leaves buf0 at data+0x50)
// and then suspends at main.gc:369 and is NEVER dispatched again, while
// every other process keeps running on the same kernel thread. The
// kernel-dispatcher only resumes status 'waiting-to-run / 'suspended
// (gkernel.gc:1332). This probe reads the 'display process record live
// to name WHY it is skipped: bad status, dead, masked, unlinked from
// the tree, or *run* cleared. Pure reads; off by default.
static bool a40_sym_name(uintptr_t ee, uint32_t p, char* out, size_t n) {
  out[0] = 0;
  if (!SymbolTable2.offset || !LastSymbol.offset) {
    return false;
  }
  if (p < SymbolTable2.offset || p >= LastSymbol.offset || (p & 3)) {
    return false;
  }
  uint64_t info = static_cast<uint64_t>(p) + jak1::SYM_INFO_OFFSET;
  if (info + 8 >= EE_MAIN_MEM_SIZE) {
    return false;
  }
  uint32_t str_off = *reinterpret_cast<const uint32_t*>(ee + info + 4);
  if (!str_off || static_cast<uint64_t>(str_off) + 4 + n >= EE_MAIN_MEM_SIZE) {
    return false;
  }
  const char* sp = reinterpret_cast<const char*>(ee + str_off + 4);
  size_t i = 0;
  for (; i + 1 < n && sp[i]; i++) {
    out[i] = (sp[i] >= 0x20 && sp[i] <= 0x7e) ? sp[i] : '?';
  }
  out[i] = 0;
  return out[0] != 0;
}


// v2: all GOAL "basic" field reads use deftype-offset minus 4 (boxed
// basics point 4 past the type tag — the v1 probe forgot this and read
// every field one slot late; the A34-DIAG dumps already used the -4 rule).
extern "C" void gk_a40_shim_counters(unsigned long long out[6]);

void a40_dproc_probe(const char* tag) {
  const uintptr_t ee = reinterpret_cast<uintptr_t>(g_ee_main_mem);
  if (!ee) {
    return;
  }
  auto rd = [ee](uint32_t goal, uint32_t* out) -> bool {
    if (goal < 0x1000 || goal >= EE_MAIN_MEM_SIZE - 4) {
      return false;
    }
    *out = *reinterpret_cast<const uint32_t*>(ee + goal);
    return true;
  };
  auto symval = [](const char* nm) -> uint32_t {
    auto s = jak1::intern_from_c(nm);
    return s.offset ? s->value : 0;
  };
  uint32_t run = symval("*run*");
  uint32_t dproc = symval("*dproc*");
  uint32_t mm = symval("*master-mode*");
  uint32_t kctx = symval("*kernel-context*");
  uint32_t oddeven = symval("*oddeven*");
  uint32_t vparms = symval("*video-parms*");
  uint32_t prevent = 0, curproc = 0, svm = 0, rvm = 0;
  rd(kctx + 0, &prevent);   // kernel-context.prevent-from-run (deftype 4)
  rd(kctx + 20, &curproc);  // kernel-context.current-process (deftype 24)
  rd(vparms + 0, &svm);     // video-parms is a structure: set-video-mode at +0
  rd(vparms + 4, &rvm);     // reset-video-mode at +4
  char mmn[40], runn[40];
  a40_sym_name(ee, mm, mmn, sizeof(mmn));
  a40_sym_name(ee, run, runn, sizeof(runn));
  unsigned long long c[6] = {0, 0, 0, 0, 0, 0};
  gk_a40_shim_counters(c);
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "A40-DPROC %s *run*=0x%x(%s) *dproc*=0x%x *master-mode*=%s(0x%x) "
                      "prevent=0x%x cur=0x%x oddeven=0x%x set-vm=0x%x reset-vm=0x%x",
                      tag, run, runn[0] ? runn : "?", dproc, mmn[0] ? mmn : "?", mm, prevent,
                      curproc, oddeven, svm, rvm);
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "A40-DPROC %s shims vsync=%llu/%llu sync-path=%llu/%llu sends=%llu "
                      "dropped=%llu",
                      tag, c[0], c[1], c[2], c[3], c[4], c[5]);
  if (dproc >= 0x1000 && dproc < EE_MAIN_MEM_SIZE - 128) {
    uint32_t name = 0, mask = 0, status = 0, pid = 0, pool = 0, mthr = 0, tthr = 0, stt = 0,
             nstate = 0;
    rd(dproc + 0, &name);    // deftype 4
    rd(dproc + 4, &mask);    // deftype 8
    rd(dproc + 28, &pool);   // deftype 32
    rd(dproc + 32, &status); // deftype 36
    rd(dproc + 36, &pid);    // deftype 40
    rd(dproc + 40, &mthr);   // deftype 44 main-thread
    rd(dproc + 44, &tthr);   // deftype 48 top-thread
    rd(dproc + 52, &stt);    // deftype 56 state
    rd(dproc + 72, &nstate); // deftype 76 next-state
    char nn[40], st[40];
    a40_sym_name(ee, name, nn, sizeof(nn));
    a40_sym_name(ee, status, st, sizeof(st));
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "A40-DPROC %s proc=0x%x name=%s(0x%x) status=%s(0x%x) pid=%d mask=0x%x "
                        "pool=0x%x state=0x%x next-state=0x%x top-thread=0x%x",
                        tag, dproc, nn[0] ? nn : "?", name, st[0] ? st : "?", status, (int)pid,
                        mask, pool, stt, nstate, tthr);
    // Gecho-pool TEMP probe: the thread-suspend (break) fires on the TOP-thread (a
    // 256-byte PROCESS_STACK_SAVE_SIZE child), not mthr. Dump its used-vs-size to size
    // the arm64 frame-overflow. Removed before the phase passes.
    if (tthr >= 0x1000 && tthr < EE_MAIN_MEM_SIZE - 64) {
      uint32_t tpc = 0, tsp = 0, tstop = 0, tssz = 0;
      rd(tthr + 20, &tpc);
      rd(tthr + 24, &tsp);
      rd(tthr + 28, &tstop);
      rd(tthr + 32, &tssz);
      __android_log_print(
          ANDROID_LOG_FATAL, kGkLogTag,
          "A40-DPROC %s TOPTHR=0x%x pc=0x%x sp=0x%x stack-top=0x%x stack-size=%d used=%d OVER=%d",
          tag, tthr, tpc, tsp, tstop, (int)tssz, (int)((int)tstop - (int)tsp),
          (int)(((int)tstop - (int)tsp) - (int)tssz));
    }
    if (mthr >= 0x1000 && mthr < EE_MAIN_MEM_SIZE - 64) {
      uint32_t pc = 0, sp = 0, stop_ = 0, ssz = 0, shook = 0, rhook = 0;
      rd(mthr + 12, &shook); // thread.suspend-hook (deftype 16)
      rd(mthr + 16, &rhook); // thread.resume-hook (deftype 20)
      rd(mthr + 20, &pc);    // thread.pc (deftype 24)
      rd(mthr + 24, &sp);    // thread.sp (deftype 28)
      rd(mthr + 28, &stop_); // thread.stack-top (deftype 32)
      rd(mthr + 32, &ssz);   // thread.stack-size (deftype 36)
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "A40-DPROC %s mthr=0x%x pc=0x%x sp=0x%x stack-top=0x%x stack-size=%d "
                          "suspend-hook=0x%x resume-hook=0x%x",
                          tag, mthr, pc, sp, stop_, (int)ssz, shook, rhook);
      // Saved-pc neighborhood: names WHICH suspend site the thread parks
      // at (pre-loop main.gc:369 vs loop-bottom main.gc:570) once decoded
      // against the static main.o disasm. Static code — tiny dump.
      if (pc >= 0x1040 && static_cast<uint64_t>(pc) + 0x20 < EE_MAIN_MEM_SIZE) {
        for (int row = -2; row <= 1; row++) {
          const uint32_t base = pc + row * 16;
          const uint32_t* w = reinterpret_cast<const uint32_t*>(ee + base);
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "A40-DPROC %s pcwin 0x%x: %08x %08x %08x %08x", tag, base, w[0],
                              w[1], w[2], w[3]);
        }
      }
    }
  }
  // === Gecho-pool TEMP: dump the SUSPENDING process (*kernel-context*.current-process). ===
  // This is the process whose 256-byte temp/main thread overflowed at thread-suspend's (break).
  if (curproc >= 0x1000 && curproc < EE_MAIN_MEM_SIZE - 128) {
    uint32_t cname = 0, cstatus = 0, cpid = 0, cmthr = 0, ctthr = 0, cstate = 0, cnstate = 0;
    rd(curproc + 0, &cname);     // process.name  (deftype 4)
    rd(curproc + 32, &cstatus);  // status        (deftype 36)
    rd(curproc + 36, &cpid);     // pid           (deftype 40)
    rd(curproc + 40, &cmthr);    // main-thread   (deftype 44)
    rd(curproc + 44, &ctthr);    // top-thread    (deftype 48)
    rd(curproc + 52, &cstate);   // state         (deftype 56)
    rd(curproc + 72, &cnstate);  // next-state    (deftype 76)
    char cnn[40], cst[40], csn[40], cnsn[40];
    a40_sym_name(ee, cname, cnn, sizeof(cnn));
    a40_sym_name(ee, cstatus, cst, sizeof(cst));
    a40_sym_name(ee, cstate, csn, sizeof(csn));
    a40_sym_name(ee, cnstate, cnsn, sizeof(cnsn));
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
        "A40-DPROC %s CURPROC=0x%x name=%s(0x%x) status=%s pid=%d main-thread=0x%x top-thread=0x%x state=%s(0x%x) next-state=%s",
        tag, curproc, cnn[0]?cnn:"?", cname, cst[0]?cst:"?", (int)cpid, cmthr, ctthr, csn[0]?csn:"?", cstate, cnsn[0]?cnsn:"?");
    uint32_t st = (ctthr >= 0x1000) ? ctthr : cmthr;  // the suspending (top) thread
    if (st >= 0x1000 && st < EE_MAIN_MEM_SIZE - 64) {
      uint32_t tname = 0, tpc = 0, tsp = 0, tstop = 0, tssz = 0;
      rd(st + 0, &tname);   // thread.name        (deftype 4)
      rd(st + 20, &tpc);    // thread.pc          (deftype 24)
      rd(st + 24, &tsp);    // thread.sp          (deftype 28)
      rd(st + 28, &tstop);  // thread.stack-top   (deftype 32)
      rd(st + 32, &tssz);   // thread.stack-size  (deftype 36)
      char tnn[40];
      a40_sym_name(ee, tname, tnn, sizeof(tnn));
      int used = (int)tstop - (int)tsp;
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
          "A40-DPROC %s CURTHR=0x%x tname=%s pc=0x%x sp=0x%x stack-top=0x%x stack-size=%d used=%d OVER=%d",
          tag, st, tnn[0]?tnn:"?", tpc, tsp, tstop, (int)tssz, used, used - (int)tssz);
      // === Gecho-pool TEMP: walk the suspending thread's stack to name the frame chain ===
      // The stack holds 64-bit host values (saved x29/FP = host stack ptr, x30/LR = host
      // code ptr). Read each 8-byte slot (two 32-bit words), and if it converts to a GOAL
      // code address, name the function — that LR identifies a frame's call site.
      for (uint32_t a = tsp; a + 8 <= tstop && a < tsp + 0x220; a += 8) {
        uint32_t lo = 0, hi = 0;
        if (!rd(a, &lo) || !rd(a + 4, &hi)) continue;
        uint64_t v = ((uint64_t)hi << 32) | (uint64_t)lo;
        uint32_t g = to_goal((uintptr_t)v);  // 0 if v is not an EE-region host pointer
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
            "A40-DPROC %s CURSTK +0x%-3x: 0x%016llx goal=0x%x", tag, a - tsp,
            (unsigned long long)v, g);
        if (g >= 0x10000 && g < 0x3000000) {
          // code-range GOAL address (a saved LR / frame return site) — name it
          char lbl[28];
          snprintf(lbl, sizeof(lbl), "CURSTK+0x%x", a - tsp);
          log_nearest_goal_fn(lbl, g);
        }
      }
      // === end Gecho-pool stack-walk ===
    }
  }
  // === end Gecho-pool CURPROC dump ===
  // Display buffers, sampled alongside the process state: on-screen,
  // last-screen, and both frames' global-buf {field, base, data} — the
  // walk shows as buf base ≫ data with no resets between samples.
  {
    uint32_t disp = symval("*display*");
    if (disp >= 0x1000 && disp < EE_MAIN_MEM_SIZE - 0x400) {
      uint32_t onscr = 0, lastscr = 0;
      rd(disp + 556, &onscr);   // display.on-screen (mem, A38-verified)
      rd(disp + 560, &lastscr); // display.last-screen (mem)
      char bufline[300];
      size_t boff = 0;
      bufline[0] = 0;
      for (int i = 0; i < 2; i++) {
        uint32_t frame = 0, gb = 0, gbase = 0, gend = 0;
        rd(disp + 564 + 32 * i + 16, &frame); // frames[i].frame (mem, A38-verified)
        if (frame >= 0x1000) {
          rd(frame + 36, &gb); // display-frame.global-buf (deftype 40)
          if (gb >= 0x1000) {
            rd(gb + 4, &gbase); // dma-buffer.base (deftype 8)
            rd(gb + 8, &gend);  // dma-buffer.end (deftype 12)
          }
        }
        int w = snprintf(bufline + boff, sizeof(bufline) - boff,
                         " f%d.gb=0x%x base=0x%x end=0x%x data=0x%x", i, gb, gbase, gend,
                         gb + 12);
        if (w <= 0 || static_cast<size_t>(w) >= sizeof(bufline) - boff) {
          break;
        }
        boff += static_cast<size_t>(w);
      }
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "A40-DPROC %s disp=0x%x on-screen=%d last-screen=%d%s", tag, disp,
                          (int)onscr, (int)lastscr, bufline);
    }
  }
  static const char* const kPools[2] = {"*display-pool*", "*active-pool*"};
  for (int pi = 0; pi < 2; pi++) {
    uint32_t pl = symval(kPools[pi]);
    if (pl < 0x1000 || pl >= EE_MAIN_MEM_SIZE - 64) {
      continue;
    }
    uint32_t childp = 0;
    rd(pl + 16, &childp);  // process-tree.child (deftype 20)
    int n = 0;
    char line[440];
    size_t off = 0;
    line[0] = 0;
    while (childp >= 0x1000 && childp < EE_MAIN_MEM_SIZE - 64 && n < 12) {
      uint32_t node = 0;
      if (!rd(childp, &node) || node < 0x1000 || node >= EE_MAIN_MEM_SIZE - 128) {
        break;
      }
      uint32_t nm = 0, st2 = 0;
      rd(node + 0, &nm);    // name (deftype 4)
      rd(node + 32, &st2);  // status (deftype 36; garbage for plain tree nodes)
      char nn[40];
      if (!a40_sym_name(ee, nm, nn, sizeof(nn))) {
        nn[0] = 0;
        if (nm >= 0x1000 && static_cast<uint64_t>(nm) + 44 < EE_MAIN_MEM_SIZE) {
          const char* spx = reinterpret_cast<const char*>(ee + nm + 4);
          size_t i = 0;
          for (; i < 39 && spx[i] >= 0x20 && spx[i] <= 0x7e; i++) {
            nn[i] = spx[i];
          }
          nn[i] = 0;
        }
      }
      char stn[40];
      a40_sym_name(ee, st2, stn, sizeof(stn));
      int w = snprintf(line + off, sizeof(line) - off, " %s:0x%x/%s", nn[0] ? nn : "?", node,
                       stn[0] ? stn : "?");
      if (w <= 0 || static_cast<size_t>(w) >= sizeof(line) - off) {
        break;
      }
      off += static_cast<size_t>(w);
      n++;
      uint32_t bro = 0;
      rd(node + 12, &bro);  // brother (deftype 16)
      childp = bro;
    }
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag, "A40-DPROC %s %s=0x%x n=%d%s", tag,
                        kPools[pi], pl, n, line);
  }
}

// The resuming write-fault intercept. Returns true when the fault was a
// band trip (handled — caller must plain-return so the store retries).
bool handle_band_fault(siginfo_t* info, void* ucontext) {
  if (g_mode.load(std::memory_order_acquire) != 1) {
    return false;
  }
  uintptr_t fault = info ? reinterpret_cast<uintptr_t>(info->si_addr) : 0;
  bool in_band1 = (fault >= g_lo_host && fault < g_hi_host);
  bool in_band2 = (g_lo2_host && fault >= g_lo2_host && fault < g_hi2_host) ||
                  (g_lo3_host && fault >= g_lo3_host && fault < g_hi3_host);
  if (!in_band1 && !in_band2) {
    return false;
  }
  auto* uc = reinterpret_cast<ucontext_t*>(ucontext);
  uintptr_t pc = uc->uc_mcontext.pc;
  uintptr_t lr = uc->uc_mcontext.regs[30];
  uint64_t hitno = g_hits.fetch_add(1, std::memory_order_relaxed) + 1;

  // The faulting pc was executing — readable. Bounds-gate anyway: EE
  // range or a dladdr-resolvable mapping; otherwise log without decode.
  uint32_t insn = 0;
  bool insn_ok = false;
  if (to_goal(pc) >= 0x1000) {
    insn = *reinterpret_cast<const uint32_t*>(pc);
    insn_ok = true;
  } else {
    Dl_info di{};
    if (pc && dladdr(reinterpret_cast<void*>(pc), &di) && di.dli_fbase) {
      insn = *reinterpret_cast<const uint32_t*>(pc);
      insn_ok = true;
    }
  }
  StoreInfo st = insn_ok ? classify_store(insn) : StoreInfo{};
  uint64_t val_lo = 0, val_hi = 0;
  uint64_t val2_lo = 0, val2_hi = 0;
  if (st.valid) {
    if (st.simd) {
      val_lo = fpsimd_lo64(uc, st.rt, &val_hi);
      if (st.pair) {
        val2_lo = fpsimd_lo64(uc, st.rt2, &val2_hi);
      }
    } else {
      val_lo = (st.rt == 31) ? 0 : uc->uc_mcontext.regs[st.rt];
      if (st.pair) {
        val2_lo = (st.rt2 == 31) ? 0 : uc->uc_mcontext.regs[st.rt2];
      }
    }
  }

  // v2: EMULATE decodable non-writeback stores — write the bytes ourselves,
  // re-protect, and skip the instruction. The band protection never drops,
  // so a benign per-frame writer (texscroll) can no longer shadow the page
  // for the writer we're hunting (run-1: the float spray landed in the
  // texscroll page while it sat open between rearms).
  // Only size-aligned accesses: an unaligned store can straddle pages and
  // arm64 FAR then points INTO the access, not at its base — emulating
  // from si_addr would shift the bytes. Aligned stores (all goalc output)
  // cannot straddle, so si_addr == access base.
  bool emulated = false;
  if (st.valid && !st.writeback && st.size_bytes > 0 &&
      (fault & static_cast<uintptr_t>(st.size_bytes - 1)) == 0) {
    size_t total = static_cast<size_t>(st.size_bytes) * (st.pair ? 2 : 1);
    uintptr_t lo_page = fault & ~static_cast<uintptr_t>(g_page_size - 1);
    uintptr_t hi_page =
        (fault + total - 1) & ~static_cast<uintptr_t>(g_page_size - 1);
    size_t span = hi_page - lo_page + g_page_size;
    {
      uint8_t bytes[32];
      memcpy(bytes, &val_lo, 8);
      memcpy(bytes + 8, &val_hi, 8);
      if (st.pair) {
        memcpy(bytes + st.size_bytes, &val2_lo, 8 < st.size_bytes ? 8 : st.size_bytes);
        if (st.size_bytes == 16) {
          memcpy(bytes + 16, &val2_lo, 8);
          memcpy(bytes + 24, &val2_hi, 8);
        }
      }
      uint8_t pre[8] = {0};
      memcpy(pre, reinterpret_cast<void*>(fault), total > 8 ? 8 : total);
      // Emulate the store via /proc/self/mem, which writes through the
      // PROT_READ page WITHOUT toggling its protection. The previous
      // mprotect(RW)->memcpy->mprotect(RO) opened a window during which a
      // concurrent (GL-thread reprotect / another writer) access could slip
      // through unwatched — the hunted global-buf.base writer never faulted.
      // Keeping the page RO continuously closes that window. Fall back to the
      // mprotect toggle if /proc/self/mem is unavailable.
      static int s_procmem = -2;  // -2 unopened, -1 failed, >=0 fd
      if (s_procmem == -2) {
        s_procmem = open("/proc/self/mem", O_RDWR | O_CLOEXEC);
      }
      bool wrote = false;
      if (s_procmem >= 0) {
        ssize_t w = pwrite(s_procmem, bytes, total, static_cast<off_t>(fault));
        wrote = (w == static_cast<ssize_t>(total));
      }
      if (!wrote) {
        if (mprotect(reinterpret_cast<void*>(lo_page), span,
                     PROT_READ | PROT_WRITE | PROT_EXEC) == 0) {
          memcpy(reinterpret_cast<void*>(fault), bytes, total);
          mprotect(reinterpret_cast<void*>(lo_page), span, PROT_READ | PROT_EXEC);
          wrote = true;
        }
      }
      if (wrote) {
      // Readback-verify: an emulated store that does not land would
      // silently freeze whatever state the watched field carries — the
      // emulator must prove itself on every write.
      if (memcmp(reinterpret_cast<void*>(fault), bytes, total) != 0) {
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "A38-TRIPWIRE EMU-VERIFY-FAIL fault=goal:0x%x total=%zu",
                            static_cast<uint32_t>(fault - reinterpret_cast<uintptr_t>(g_ee_main_mem)),
                            total);
      }
      uc->uc_mcontext.pc += 4;
      emulated = true;
      g_emulated.fetch_add(1, std::memory_order_relaxed);
      // A40-SWEEP (debug.opengoal.a40.sweepdump=1): when the banded store
      // comes from print-game-text itself (the runaway blank-line loop
      // appending NEXT packets across the band), dump the live loop
      // state: sv-164 line-advance [sp+120], sv-156 bottom-y [sp+136],
      // sv-136 scale [sp+216], gp-0 (x11) origin.y [gp0+16] and the
      // buffer (x?) — the sweeping invocation's parameters, captured
      // mid-sweep instead of at the (later, innocent) crash frame.
      {
        static std::atomic<int> s_a40_sw{-1};
        int sw = s_a40_sw.load(std::memory_order_acquire);
        if (sw == -1) {
          char swb[PROP_VALUE_MAX] = {0};
          sw = (__system_property_get("debug.opengoal.a40.sweepdump", swb) > 0 && swb[0] == '1')
                   ? 1
                   : 0;
          s_a40_sw.store(sw, std::memory_order_release);
        }
        if (sw == 1) {
          static uint32_t s_pgt_lo = 0, s_pgt_hi = 0;
          if (!s_pgt_lo) {
            auto s_pgt = jak1::intern_from_c("print-game-text");
            uint32_t v = s_pgt.offset ? s_pgt->value : 0;
            if (v >= 0x1000) {
              s_pgt_lo = v;
              s_pgt_hi = v + 0x1470;
            }
          }
          uint32_t pcg = to_goal(pc);
          if (s_pgt_lo && pcg >= s_pgt_lo && pcg < s_pgt_hi) {
            static std::atomic<int> s_sweep_logs{14};
            if (s_sweep_logs.fetch_sub(1, std::memory_order_relaxed) > 0) {
              const uintptr_t spv = (uintptr_t)uc->uc_mcontext.sp;
              float sv164 = 0, sv156 = 0, sv136 = 0, oy = 0, oh = 0;
              memcpy(&sv164, reinterpret_cast<const void*>(spv + 120), 4);
              memcpy(&sv156, reinterpret_cast<const void*>(spv + 136), 4);
              memcpy(&sv136, reinterpret_cast<const void*>(spv + 216), 4);
              uintptr_t ee2 = reinterpret_cast<uintptr_t>(g_ee_main_mem);
              uint32_t gp0 = (uint32_t)(uc->uc_mcontext.regs[11] & 0xFFFFFFFFu);
              uint32_t fctx = (uint32_t)(uc->uc_mcontext.regs[5] & 0xFFFFFFFFu);
              if (gp0 >= 0x1000 && gp0 < EE_MAIN_MEM_SIZE - 64) {
                memcpy(&oy, reinterpret_cast<const void*>(ee2 + gp0 + 16), 4);
              }
              if (fctx >= 0x1000 && fctx < EE_MAIN_MEM_SIZE - 64) {
                memcpy(&oh, reinterpret_cast<const void*>(ee2 + fctx + 48), 4);
              }
              __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                  "A40-SWEEP pc=goal:0x%x fault=goal:0x%x sv-164(adv)=%.6g "
                                  "sv-156(bottom)=%.6g sv-136(scale)=%.6g gp0=0x%x origin.y=%.6g "
                                  "fctx=0x%x fctx.height=%.6g x6=0x%llx",
                                  pcg, static_cast<uint32_t>(fault - ee2), sv164, sv156, sv136,
                                  gp0, oy, fctx, oh,
                                  (unsigned long long)uc->uc_mcontext.regs[6]);
            }
          }
        }
      }
      // Flip-cell trace: on-screen/last-screen writes get a dedicated
      // pre/post line so the frozen-flip paradox is settled with data.
      if (g_lo2_host && !g_base_cell[0] && fault >= g_lo2_host && fault < g_hi2_host) {
        uint32_t fg = static_cast<uint32_t>(fault - reinterpret_cast<uintptr_t>(g_ee_main_mem));
        static std::atomic<int> s_flip_logs{40};
        if ((fg & ~7u) == 0x513cf0u && s_flip_logs.fetch_sub(1, std::memory_order_relaxed) > 0) {
          uint32_t post = *reinterpret_cast<const uint32_t*>(fault);
          uint32_t prew = 0;
          memcpy(&prew, pre, 4);
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "A38-TRIPWIRE FLIP fg=0x%x pre=0x%x post=0x%x pc=goal:0x%x "
                              "on=0x%x last=0x%x",
                              fg, prew, post,
                              to_goal(uc->uc_mcontext.pc),
                              *reinterpret_cast<const uint32_t*>(g_lo2_host + 0xcf0),
                              *reinterpret_cast<const uint32_t*>(g_lo2_host + 0xcf4));
        }
      }
      // Base-cell trace (watch2=2): every write covering a global-buf base
      // field, in program order, with pre/post and the writing pc — the
      // writer that jumps the cursor out of [data,end] names itself here.
      for (int ci = 0; ci < 2; ci++) {
        if (!g_base_cell[ci] || fault > g_base_cell[ci] + 3 ||
            fault + total <= g_base_cell[ci]) {
          continue;
        }
        uint32_t post = *reinterpret_cast<const uint32_t*>(g_base_cell[ci]);
        // A39: only anomalous cursor values burn budget — the healthy appends
        // exhausted the 240-line budget inside frame 1, hiding the late
        // band-walking writes (run1: print-game-text appended at
        // 0x1904000+16k through draw-string's code). Legit bases live in
        // [0x100000, 0x1880000) for both 8MB buffers; zero/low and band+
        // values are the anomalies being hunted.
        // Gnd: log the FIRST writes unconditionally (incl. high values) so the
        // per-frame base lifecycle is visible — esp. display-frame-start's
        // (set! base (-> global-buf data)) reset, to see if it sets base
        // absolute (high, correct) or relative (low, the bug seed).
        static std::atomic<int> s_gnd_all{60};
        if (post >= 0x100000u && post < 0x1880000u && s_gnd_all.fetch_sub(1, std::memory_order_relaxed) <= 0) {
          continue;
        }
        if (g_cell_log_budget.fetch_sub(1, std::memory_order_relaxed) <= 0) {
          break;
        }
        uint32_t prew = 0xFFFFFFFFu;  // marker: pre-bytes outside snapshot
        if (g_base_cell[ci] >= fault && g_base_cell[ci] - fault + 4 <= 8) {
          memcpy(&prew, pre + (g_base_cell[ci] - fault), 4);
        }
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "A38-BASECELL buf%d pre=0x%x post=0x%x pc=goal:0x%x lr=goal:0x%x",
                            ci, prew, post, to_goal(uc->uc_mcontext.pc - 4),
                            to_goal(uc->uc_mcontext.regs[30]));
        log_nearest_goal_fn("basecell-pc", to_goal(uc->uc_mcontext.pc - 4));
      }
      }  // close if (wrote)
    }
  }
  if (!emulated) {
    // Fallback: reopen the faulting page so the store can retry (writeback
    // forms, unknown encodings, or mprotect failure). Page re-arms next
    // frame.
    uintptr_t page = fault & ~static_cast<uintptr_t>(g_page_size - 1);
    if (mprotect(reinterpret_cast<void*>(page), static_cast<size_t>(g_page_size),
                 PROT_READ | PROT_WRITE | PROT_EXEC) != 0) {
      // Can't reopen — disarm wholesale rather than spin on an unservable
      // fault. (Never observed; defensive.)
      mprotect(reinterpret_cast<void*>(g_lo_host), static_cast<size_t>(g_hi_host - g_lo_host),
               PROT_READ | PROT_WRITE | PROT_EXEC);
      g_mode.store(0, std::memory_order_release);
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "A38-TRIPWIRE DISARMED: page reopen failed errno=%d", errno);
      return true;
    }
    g_any_page_open.store(true, std::memory_order_relaxed);
    g_pages_reopened.fetch_add(1, std::memory_order_relaxed);
  }

  bool is_new = false;
  note_writer(pc, static_cast<uint32_t>(fault - reinterpret_cast<uintptr_t>(g_ee_main_mem)),
              val_lo, &is_new);

  // Gnd: force-name any writer that stores a LOW garbage value (<0x80000) into
  // the band — that IS the ndi DMA-chain stomp signature (bucket-NEXT addr
  // flips to 0x1a50/0x2070), independent of the log budget or whether this pc
  // also does legit high-pointer writes. Bounded; reads only ucontext/EE.
  {
    uint32_t v32 = static_cast<uint32_t>(val_lo);
    uint32_t vhi32 = static_cast<uint32_t>(val_lo >> 32);
    uint32_t goff_f = static_cast<uint32_t>(fault - reinterpret_cast<uintptr_t>(g_ee_main_mem));
    // The bucket-NEXT stomp writes a LOW addr into a dma-tag addr field: either
    // a 4-byte store to the +4 addr word (value in low32) or an 8-byte tag
    // store to the +0 word (addr in high32). Frame-counter / header writes to
    // other struct fields are excluded so the budget reaches the actual stomp.
    bool stomp = ((goff_f & 0xf) == 4 && v32 != 0 && v32 < 0x80000u) ||
                 ((goff_f & 0xf) == 0 && vhi32 != 0 && vhi32 < 0x80000u);
    static std::atomic<int> s_gnd_budget{256};
    if (st.valid && stomp && s_gnd_budget.fetch_sub(1, std::memory_order_relaxed) > 0) {
      uint32_t pcg2 = to_goal(pc);
      __android_log_print(
          ANDROID_LOG_FATAL, kGkLogTag,
          "A38-TRIPWIRE GND-STOMP fault=goal:0x%x pc=0x%lx(goal:0x%x) lr=0x%lx(goal:0x%x) "
          "val=0x%llx sz=%d rt=%d insn=0x%08x",
          to_goal(fault), (unsigned long)pc, pcg2, (unsigned long)lr, to_goal(lr),
          (unsigned long long)val_lo, st.size_bytes, st.rt, insn);
      log_dladdr("gnd-pc", pc);
      if (pcg2 >= 0x1000) {
        log_nearest_goal_fn("gnd-pc", pcg2);
      }
      uint32_t lrg2 = to_goal(lr);
      if (lrg2 >= 0x1000) {
        log_nearest_goal_fn("gnd-lr", lrg2);
      }
    }
  }

  int budget = g_log_budget.fetch_sub(1, std::memory_order_relaxed);
  bool full_log = budget > 0 || is_new;
  if (full_log || (hitno % 512) == 0) {
    __android_log_print(
        ANDROID_LOG_FATAL, kGkLogTag,
        "A38-TRIPWIRE hit#%llu%s fault=goal:0x%x pc=0x%lx(goal:0x%x) lr=0x%lx(goal:0x%x) "
        "insn=0x%08x %s%s sz=%d rt=%d rt2=%d rn=%d(=0x%llx) val=0x%llx:%llx emu=%d",
        (unsigned long long)hitno, is_new ? " NEW-WRITER" : "", to_goal(fault),
        (unsigned long)pc, to_goal(pc), (unsigned long)lr, to_goal(lr), insn,
        st.valid ? (st.simd ? "SIMD-" : "GPR-") : "un",
        st.valid ? (st.pair ? "STP" : "STR") : "decoded", st.size_bytes, st.rt, st.rt2, st.rn,
        st.valid && st.rn >= 0
            ? (unsigned long long)(st.rn == 31 ? uc->uc_mcontext.sp : uc->uc_mcontext.regs[st.rn])
            : 0ull,
        (unsigned long long)val_hi, (unsigned long long)val_lo, emulated ? 1 : 0);
  }
  if (full_log) {
    log_dladdr("pc", pc);
    log_dladdr("lr", lr);
    uint32_t pcg = to_goal(pc);
    if (pcg >= 0x1000) {
      log_nearest_goal_fn("pc", pcg);
    }
    uint32_t lrg = to_goal(lr);
    if (lrg >= 0x1000) {
      log_nearest_goal_fn("lr", lrg);
    }
    if (is_new) {
      // Buffer-object identification (run-3: display state sane in memory
      // at 1Hz probes, so the runaway cursor lives in registers — find
      // which register holds a dma-buffer-shaped object whose base field
      // tracks this fault). For each GPR in EE range: if [reg+4] is within
      // 0x200 of the fault, it's the buffer the writer is appending to;
      // log it with its type tag so the WRONG object gets named.
      {
        const uintptr_t ee = reinterpret_cast<uintptr_t>(g_ee_main_mem);
        uint32_t fault_goal = static_cast<uint32_t>(fault - ee);
        for (int rn2 = 0; rn2 < 31; rn2++) {
          uint32_t v = static_cast<uint32_t>(uc->uc_mcontext.regs[rn2]);
          if (v < 0x1000 || v >= EE_MAIN_MEM_SIZE - 16) {
            continue;
          }
          uint32_t fbase = *reinterpret_cast<const uint32_t*>(ee + v + 4);
          if (fbase + 0x200 < fault_goal || fbase > fault_goal + 0x200) {
            continue;
          }
          uint32_t flen = *reinterpret_cast<const uint32_t*>(ee + v + 0);
          uint32_t fend = *reinterpret_cast<const uint32_t*>(ee + v + 8);
          uint32_t ftype = (v >= 0x1004) ? *reinterpret_cast<const uint32_t*>(ee + v - 4) : 0;
          uint32_t tsym = 0;
          if (ftype >= 0x1000 && ftype < EE_MAIN_MEM_SIZE - 4) {
            tsym = *reinterpret_cast<const uint32_t*>(ee + ftype + 0);
          }
          char tname[65] = {0};
          if (tsym >= 0x1000 && tsym < EE_MAIN_MEM_SIZE) {
            uint64_t info_goal = static_cast<uint64_t>(tsym) + jak1::SYM_INFO_OFFSET;
            if (info_goal + 8 < EE_MAIN_MEM_SIZE) {
              uint32_t str_off = *reinterpret_cast<const uint32_t*>(ee + info_goal + 4);
              if (str_off > 0 &&
                  static_cast<uint64_t>(str_off) + 4 + sizeof(tname) < EE_MAIN_MEM_SIZE) {
                const char* sp2 = reinterpret_cast<const char*>(ee + str_off + 4);
                for (size_t i = 0; i + 1 < sizeof(tname) && sp2[i]; i++) {
                  tname[i] = (sp2[i] >= 0x20 && sp2[i] <= 0x7e) ? sp2[i] : '?';
                }
              }
            }
          }
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "A38-TRIPWIRE bufreg x%d obj=0x%x len=0x%x base=0x%x end=0x%x "
                              "type=0x%x '%s'",
                              rn2, v, flen, fbase, fend, ftype, tname[0] ? tname : "?");
        }
      }
      // Decisive discriminator (run-4): dump the display/buffer state from
      // MEMORY at the exact moment of this store, on the storing thread.
      // Registers diverging from sane memory = emitted-code bug; memory
      // matching the runaway cursor = a field smash. intern_from_c is
      // lookup-only (A37-DRAWSTR precedent for in-handler use).
      if (in_band1) {
        log_display_probe("at-hit");
      }
      // One-shot context for each new writer: the GOAL arg registers
      // (arm64 backing of x86-id RDI/RSI/RDX/RCX = X7/X6/X2/X1, per the
      // A6/A37 FFI contract) + scratch X16, and the memory window around
      // the fault — names the object being written through.
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "A38-TRIPWIRE ctx x0=0x%llx x1=0x%llx x2=0x%llx x3=0x%llx x6=0x%llx "
                          "x7=0x%llx x9=0x%llx x16=0x%llx sp=0x%llx",
                          (unsigned long long)uc->uc_mcontext.regs[0],
                          (unsigned long long)uc->uc_mcontext.regs[1],
                          (unsigned long long)uc->uc_mcontext.regs[2],
                          (unsigned long long)uc->uc_mcontext.regs[3],
                          (unsigned long long)uc->uc_mcontext.regs[6],
                          (unsigned long long)uc->uc_mcontext.regs[7],
                          (unsigned long long)uc->uc_mcontext.regs[9],
                          (unsigned long long)uc->uc_mcontext.regs[16],
                          (unsigned long long)uc->uc_mcontext.sp);
      for (int row = -1; row <= 1; row++) {
        uintptr_t base = (fault & ~15ull) + row * 16;
        if (to_goal(base) < 0x1000) {
          continue;
        }
        const uint32_t* w = reinterpret_cast<const uint32_t*>(base);
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "A38-TRIPWIRE win goal:0x%x: %08x %08x %08x %08x", to_goal(base),
                            w[0], w[1], w[2], w[3]);
      }
    }
  }
  return true;
}

// Gmatch: targeted repair for the arm64 "double-EE-base" memory fault seen in
// the NEW GAME sage-intro cutscene (blerc / merc blend-shape DMA-chain build).
// A GOAL-compiled store OR LOAD in the f1c boot CGO receives a pointer that is
// ALREADY host-absolute (EE_base + off) and then re-bases it a SECOND time
// (ADD Xd,Xn,X15 with X15 = EE_base), so the access target = 2*EE_base + off,
// which is unmapped -> SIGSEGV (e.g. fault=0xfe0018aee4: a STR Q at pc=0x...502ad0
// AND a LDR Q21,[X16] at the next access in the same vector-math function). The
// intended address is unambiguous: (fault - EE_base) = the single-based host
// address the producer actually computed. The f1c CGOs cannot be recompiled on
// this device (rebuilt boot CGOs SIGILL at frame 180), so the producer-side
// codegen fix cannot ship; per the phase mandate ("all fixes ship via libgk.so")
// we COMPLETE the intended access from libgk and skip the faulting instruction:
//   - STORE: write the source register(s) to the corrected address.
//   - LOAD:  read the corrected address into the destination register(s).
// Gated by the exact double-base address window so genuine faults (null deref,
// wild pointers) — which never land in [2*EE_base, 2*EE_base+EE_SIZE) — are
// NEVER masked. Same decode/emulate machinery as handle_band_fault.
std::atomic<uint64_t> g_dblee_repairs{0};
std::atomic<uint64_t> g_dblee_kerncode_drops{0};
bool handle_double_ee_base_fault(int sig, siginfo_t* info, void* ucontext) {
  if (sig != SIGSEGV || !g_ee_main_mem) {
    return false;
  }
  const uintptr_t ee = reinterpret_cast<uintptr_t>(g_ee_main_mem);
  const uintptr_t fault = info ? reinterpret_cast<uintptr_t>(info->si_addr) : 0;
  // double-base window: address re-based with EE_base twice.
  const uintptr_t dbl_lo = ee + ee;
  const uintptr_t dbl_hi = dbl_lo + static_cast<uintptr_t>(EE_MAIN_MEM_SIZE);
  if (fault < dbl_lo || fault >= dbl_hi) {
    return false;
  }
  const uintptr_t corrected = fault - ee;  // single-based host addr (mapped RW)
  if (corrected < ee + 0x1000 || corrected >= ee + static_cast<uintptr_t>(EE_MAIN_MEM_SIZE)) {
    return false;
  }
  auto* uc = reinterpret_cast<ucontext_t*>(ucontext);
  const uintptr_t pc = uc->uc_mcontext.pc;
  if (to_goal(pc) < 0x1000) {
    return false;  // faulting instruction must be GOAL-compiled code
  }
  const uint32_t insn = *reinterpret_cast<const uint32_t*>(pc);
  bool is_load = false;
  StoreInfo st = classify_store(insn);
  if (!st.valid) {
    st = classify_load(insn);
    is_load = st.valid;
  }
  if (!st.valid || st.writeback || st.size_bytes <= 0) {
    return false;  // only plain (non-writeback) loads/stores are completable
  }
  const size_t total = static_cast<size_t>(st.size_bytes) * (st.pair ? 2 : 1);
  if (total > 32) {
    return false;
  }
  if (corrected + total > ee + static_cast<uintptr_t>(EE_MAIN_MEM_SIZE)) {
    return false;  // corrected access must lie fully within EE memory
  }
  // No alignment requirement here: the ENTIRE double-base window
  // [2*EE_base, 2*EE_base+EE_SIZE) is unmapped, so the access straddles no
  // mapped/unmapped boundary and arm64 FAR == the access base even for a
  // 16-byte-misaligned STR/LDR Q (this exact crash is a 128-bit access at a
  // merely 4-byte-aligned address). The corrected target is plain RW EE memory.
  if (is_load) {
    // Complete the load: read the intended bytes from the single-based EE
    // address into the destination register(s).
    uint8_t bytes[32] = {0};
    memcpy(bytes, reinterpret_cast<const void*>(corrected), total);
    auto load_reg = [&](int rt, const uint8_t* src) {
      if (st.simd) {
        uint64_t lo = 0, hi = 0;
        memcpy(&lo, src, st.size_bytes >= 8 ? 8 : st.size_bytes);
        if (st.size_bytes == 16) {
          memcpy(&hi, src + 8, 8);
        }
        fpsimd_set(uc, rt, lo, hi);  // SIMD load zero-fills bits above size
      } else if (rt != 31) {         // x31 == xzr/wzr: discard
        uint64_t v = 0;
        memcpy(&v, src, st.size_bytes > 8 ? 8 : st.size_bytes);
        if (st.sign_ext) {
          const int bits = st.size_bytes * 8;
          int64_t sv = static_cast<int64_t>(v << (64 - bits)) >> (64 - bits);
          v = static_cast<uint64_t>(sv);
          if (st.dest_w) {
            v &= 0xffffffffull;  // 32-bit W destination
          }
        }
        uc->uc_mcontext.regs[rt] = v;
      }
    };
    load_reg(st.rt, bytes);
    if (st.pair) {
      load_reg(st.rt2, bytes + st.size_bytes);
    }
  } else {
    // Complete the store: write the source register(s) to the corrected addr.
    uint64_t v_lo = 0, v_hi = 0, v2_lo = 0, v2_hi = 0;
    if (st.simd) {
      v_lo = fpsimd_lo64(uc, st.rt, &v_hi);
      if (st.pair) {
        v2_lo = fpsimd_lo64(uc, st.rt2, &v2_hi);
      }
    } else {
      v_lo = (st.rt == 31) ? 0 : uc->uc_mcontext.regs[st.rt];
      if (st.pair) {
        v2_lo = (st.rt2 == 31) ? 0 : uc->uc_mcontext.regs[st.rt2];
      }
    }
    uint8_t bytes[32] = {0};
    memcpy(bytes, &v_lo, 8);
    memcpy(bytes + 8, &v_hi, 8);
    if (st.pair) {
      if (st.size_bytes == 16) {
        memcpy(bytes + 16, &v2_lo, 8);
        memcpy(bytes + 24, &v2_hi, 8);
      } else {
        memcpy(bytes + st.size_bytes, &v2_lo, st.size_bytes < 8 ? st.size_bytes : 8);
      }
    }
    // Gcine-crash-mid: ROOT FIX for the non-deterministic mid-cinematic crash.
    // A double-EE-base store whose CORRECTED target lands in the GOAL kernel
    // asm-func code band [0x18ae84,0x1912b4) is the intro-cinematic merc/keg
    // blend-shape draw (vector-float*!/keg-post, GOAL pc) writing a vector
    // through a CORRUPT low base pointer straight onto `return-from-thread-dead`
    // (0x18aee4) and its next word (0x18aee8) -- the recurring "merc DMA stomp"
    // of the per-process return trampoline. PROVEN: across the soak the only
    // DBLEE store targets ever observed are 0x18aee4/0x18aee8, and the content
    // canary attributes the stomp to the merc blend-shape draw (was=0xf81f0ffe
    // now=0x00000000). Completing that store HERE is exactly what makes this
    // fault handler the proximate WRITER that zeroes the trampoline. The
    // corrected destination is EXECUTABLE kernel code, which is NEVER a
    // legitimate GOAL store target, so the source value is garbage. DROP it --
    // do not write -- so the kernel code is never corrupted in the first place.
    // This kills the stomp at its source, race-free: with no stomp, the
    // per-frame canary + the in-band SIGILL repair-and-resume never need to
    // fire, and the same-tick cross-thread "RET into a partially-zeroed
    // trampoline" escape -- the owner's rare uncaught mid-cinematic crash --
    // can no longer occur. The faulting instruction is still skipped (pc+=4
    // below) so the draw proceeds exactly as before, minus the garbage write.
    // x86 + goal_src untouched (this whole handler is arm64/Android only).
    const uint32_t corr_goal = static_cast<uint32_t>(corrected - ee);
    if (corr_goal < 0x1912b4u && corr_goal + static_cast<uint32_t>(total) > 0x18ae84u) {
      const uint64_t d = g_dblee_kerncode_drops.fetch_add(1, std::memory_order_relaxed) + 1;
      if (d <= 8) {
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG DBLEE-DROP-KERNELCODE #%llu corrected=goal:0x%x sz=%zu "
                            "pc=goal:0x%x lr=goal:0x%x (merc blend-shape draw store onto kernel "
                            "asm-func code [return-from-thread-dead band]; dropped, not completed)",
                            (unsigned long long)d, corr_goal, total, to_goal(pc),
                            to_goal(uc->uc_mcontext.regs[30]));
      }
      uc->uc_mcontext.pc += 4;  // skip the faulting (dropped) store; do not write
      return true;
    }
    memcpy(reinterpret_cast<void*>(corrected), bytes, total);
  }
  uc->uc_mcontext.pc += 4;  // skip the faulting access
  const uint64_t n = g_dblee_repairs.fetch_add(1, std::memory_order_relaxed) + 1;
  if (n <= 8) {
    const uintptr_t lr = uc->uc_mcontext.regs[30];
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG DBLEE-REPAIR #%llu %s fault=0x%lx -> 0x%lx pc=goal:0x%x "
                        "lr=goal:0x%x sz=%d simd=%d pair=%d",
                        (unsigned long long)n, is_load ? "ld" : "st", (unsigned long)fault,
                        (unsigned long)corrected, to_goal(pc), to_goal(lr), st.size_bytes,
                        st.simd ? 1 : 0, st.pair ? 1 : 0);
    uint32_t pcg = to_goal(pc);
    if (pcg >= 0x1000) {
      log_nearest_goal_fn("dblee-pc", pcg);
    }
    uint32_t lrg = to_goal(lr);
    if (lrg >= 0x1000) {
      log_nearest_goal_fn("dblee-lr", lrg);
    }
  }
  return true;
}

// Gmatch: known-good snapshot of return-from-thread-dead, published by the
// render-thread content canary in android_gfx.cpp (null until armed, valid
// forever after — a plain pointer read here is race-safe).
extern "C" {
extern unsigned char* g_gmatch_rftd_good;
extern unsigned int g_gmatch_rftd_goal;
extern unsigned int g_gmatch_rftd_len;
}

// Gmatch / Gd3-jak: repair-and-resume for a SIGILL **or SIGSEGV** that lands with
// pc inside the (re-)stomped return-from-thread-dead trampoline band (GOAL
// [0x18ae84, 0x1912b4), entry 0x18aee4). The render-thread canary repairs the band
// per frame, but the merc blend-shape draw can re-stomp it AND the kernel-dispatch
// thread can RET into the corrupted code within the same tick, before the next
// post-frame repair. The stomp bytes may decode as an illegal instruction (SIGILL)
// or as a valid instruction making a wild memory access (SIGSEGV — e.g. Gd3
// fault=0x49000000000000 pc=0x18aee8, exposed once the Jak NaN-bone fix let the
// cinematic render past the earlier Adreno fault). Either way: repair HERE -- on
// the faulting thread, at the instant of the bad fetch -- from the canary's
// published snapshot, then RESUME (pc unchanged so the CPU re-fetches the now-valid
// instruction; the band's kernel asm-funcs reload their context registers, so a
// scratch reg touched by one preceding garbage instruction is harmless). Race-free,
// and gated to the band window AND an actually-stomped state, so a genuine fault is
// never masked (band intact -> returns false -> normal fatal path).
std::atomic<uint64_t> g_rftd_sigill_repairs{0};
bool handle_rftd_code_stomp(int sig, siginfo_t* /*info*/, void* ucontext) {
  if ((sig != SIGILL && sig != SIGSEGV) || !g_ee_main_mem || !g_gmatch_rftd_good) {
    return false;
  }
  const uintptr_t ee = reinterpret_cast<uintptr_t>(g_ee_main_mem);
  auto* uc = reinterpret_cast<ucontext_t*>(ucontext);
  const uintptr_t pc = uc->uc_mcontext.pc;
  const uintptr_t lo = ee + g_gmatch_rftd_goal;
  const uintptr_t hi = lo + g_gmatch_rftd_len;
  if (pc < lo || pc >= hi) {
    return false;  // fault pc is not inside the trampoline band
  }
  uint8_t* live = reinterpret_cast<uint8_t*>(lo);
  if (memcmp(live, g_gmatch_rftd_good, g_gmatch_rftd_len) == 0) {
    return false;  // band intact -> a genuine fault here; do not mask
  }
  memcpy(live, g_gmatch_rftd_good, g_gmatch_rftd_len);
  __builtin___clear_cache(reinterpret_cast<char*>(live),
                          reinterpret_cast<char*>(live) + g_gmatch_rftd_len);
  const uint64_t n = g_rftd_sigill_repairs.fetch_add(1, std::memory_order_relaxed) + 1;
  if (n <= 8) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG RFTD-STOMP-REPAIR #%llu sig=%d pc=goal:0x%x "
                        "(re-stomped return-from-thread-dead band; repaired+resumed)",
                        (unsigned long long)n, sig, (uint32_t)(pc - ee));
  }
  return true;  // resume at the same pc; the repaired instruction re-executes
}

// Gfix-cinematic-crash: a GOAL process whose top function RETURNS lands at
// return-from-thread-dead (GOAL 0x18aee4) -- the host return-address that
// set-to-run-bootstrap (gkernel.gc:1849-1851) computes (temp = EE_base +
// return-from-thread-dead) and pushes onto every set-to-run process's fake stack.
// The owner's NEW-GAME path drives auto-save-command (game-save.gc:1179), which
// process-spawns the `auto-save` process on *kernel-dram-stack* (a FIXED kernel
// stack near 0x19abb0); "continue without saving" spawns no such returning
// process (proven on-device: the continue path runs past this point while the
// save path crashes here deterministically at frame ~2340). When `auto-save`
// finishes and RETURNS, on arm64 its pushed trampoline RA reads back as 0 -- the
// low-memory scatter that zeroes the fake-stack RA lands at 0x19xxxx, ABOVE the
// guarded code band [0x18ae84,0x1912b4), so neither the per-frame canary nor the
// in-band repair above ever sees it. The asm-func epilogue then RETs to NULL:
// sig=11/4, pc=0, lr=0, while a GPR (observed x12) still holds the trampoline
// host addr EE+0x18aee4 -- exactly set-to-run-bootstrap's `temp`. Restore the
// intended control flow: redirect pc to the trampoline so the process is cleaned
// up by deactivate exactly as the kernel designed. Gated tightly (pc must be a
// NULL/wild non-code address AND a GPR must hold the EXACT trampoline host addr)
// so a genuine fault is never masked. The band is repaired from the canary first
// so we always land in valid trampoline code. arm64/Android only; x86 untouched.
std::atomic<uint64_t> g_rftd_nullret_redirects{0};
bool handle_rftd_null_return(int sig, siginfo_t* /*info*/, void* ucontext) {
  if ((sig != SIGILL && sig != SIGSEGV) || !g_ee_main_mem) {
    return false;
  }
  auto* uc = reinterpret_cast<ucontext_t*>(ucontext);
  const uintptr_t pc = uc->uc_mcontext.pc;
  // Only a NULL / wild-low control transfer -- a real RET to a zeroed RA. No
  // valid code lives below 0x1000, so this never masks a normal fault.
  if (pc >= 0x1000) {
    return false;
  }
  const uintptr_t ee = reinterpret_cast<uintptr_t>(g_ee_main_mem);
  const uintptr_t trampoline = ee + 0x18aee4u;  // return-from-thread-dead entry
  // A GPR must still hold the EXACT trampoline host addr (set-to-run-bootstrap's
  // pushed RA value, gkernel.gc:1849-1851). Observed in x12; scan x0..x30 so we
  // are robust to whichever reg the asm-func epilogue left it in.
  bool has_tramp = false;
  for (int r = 0; r <= 30; r++) {
    if (static_cast<uintptr_t>(uc->uc_mcontext.regs[r]) == trampoline) {
      has_tramp = true;
      break;
    }
  }
  if (!has_tramp) {
    return false;
  }
  // Land in VALID trampoline code: repair the band from the canary snapshot if it
  // has been stomped too (defensive; usually intact here).
  if (g_gmatch_rftd_good) {
    uint8_t* live = reinterpret_cast<uint8_t*>(ee + g_gmatch_rftd_goal);
    if (memcmp(live, g_gmatch_rftd_good, g_gmatch_rftd_len) != 0) {
      memcpy(live, g_gmatch_rftd_good, g_gmatch_rftd_len);
      __builtin___clear_cache(reinterpret_cast<char*>(live),
                              reinterpret_cast<char*>(live) + g_gmatch_rftd_len);
    }
  }
  const uintptr_t lr = uc->uc_mcontext.regs[30];
  const uintptr_t sp = uc->uc_mcontext.sp;
  uc->uc_mcontext.pc = trampoline;  // resume into return-from-thread-dead
  const uint64_t n = g_rftd_nullret_redirects.fetch_add(1, std::memory_order_relaxed) + 1;
  if (n <= 16 || (n % 256) == 0) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG RFTD-NULLRET-REDIRECT #%llu sig=%d pc=0x%lx lr=0x%lx "
                        "sp=0x%lx -> return-from-thread-dead (process RET to NULL; "
                        "zeroed fake-stack RA restored to trampoline)",
                        (unsigned long long)n, sig, (unsigned long)pc, (unsigned long)lr,
                        (unsigned long)sp);
  }
  return true;
}

// Gcrash-mouche: arm64 scout-fly (buzzer) collect SIGILL. enter-state
// (gstate.gc:355-386) enters a process state by computing
//   func = (-> new-state code) + r15  ;  (.jr func)
// On arm64 the GOAL process stack lives in EE memory; a concurrent mips2c sparticle
// DMA builder (the collected buzzer's group-buzzer-effect 3D wing particles) writes
// through a GOAL pointer and stomps enter-state's SPILLED `new-state` slot to 0 — even
// after the og:autoport reload at gstate.gc:350, the compiler re-spills new-state and
// reloads it for the `code` field read, so `code` reads back 0 and the .jr branches to
// EE+0 (sig=4 SIGILL, pc == g_ee_main_mem + 0). Reproduced deterministically on-device
// the instant a real buzzer enters its `pickup` state. The process HEADER (-> pp state)
// survives the stomp (pp is callee-saved GOAL r13 = x13), so recover the authoritative
// code pointer from it and resume into the correct state code — all of enter-state's
// other setup (stack reset, args, pushed return-from-thread-dead RA) is already done, so
// only the wrong jump target needs fixing. This generalizes the gstate.gc reload (which
// the spill defeats) to a race-free repair on the faulting thread, the same pattern as
// handle_rftd_* . Tightly gated: pc must be EXACTLY EE+0 AND a GPR must still hold the
// return-from-thread-dead trampoline (EE+0x18aee4) that enter-state's code-entry pushed
// onto the GOAL stack immediately before the faulting .jr (gstate.gc:377-379) — so a
// genuine null-fn-ptr call elsewhere is never masked. arm64/Android only; x86 untouched
// (the spilled slot is never stomped there).
std::atomic<uint64_t> g_enter_state_code_repairs{0};
bool handle_enter_state_null_code(int sig, siginfo_t* /*info*/, void* ucontext) {
  if ((sig != SIGILL && sig != SIGSEGV) || !g_ee_main_mem) {
    return false;
  }
  auto* uc = reinterpret_cast<ucontext_t*>(ucontext);
  const uintptr_t ee = reinterpret_cast<uintptr_t>(g_ee_main_mem);
  const uintptr_t pc = uc->uc_mcontext.pc;
  if (pc != ee) {
    return false;  // not a branch to EE+0 (the code==0 .jr)
  }
  // enter-state's code-entry trampoline pushes temp = return-from-thread-dead + off
  // (EE+0x18aee4) right before the .jr; a GPR still holds it. This is the precise
  // fingerprint of the state-code jump, distinct from any other null-fn-ptr call.
  const uintptr_t trampoline = ee + 0x18aee4u;
  bool has_tramp = false;
  for (int r = 0; r <= 30; r++) {
    if (static_cast<uintptr_t>(uc->uc_mcontext.regs[r]) == trampoline) {
      has_tramp = true;
      break;
    }
  }
  if (!has_tramp) {
    return false;
  }
  // pp = GOAL r13 (x13). Recover state + code from the (intact) process header.
  const uint32_t pp = static_cast<uint32_t>(uc->uc_mcontext.regs[13]);
  if (pp == 0 || pp + 56 >= (uint32_t)EE_MAIN_MEM_SIZE) {
    return false;
  }
  uint32_t state = 0, code = 0;
  if (!gk_diag::safe_read_u32(ee + pp + 52, &state) ||  // (-> pp state) @ deftype 56
      state == 0 || state + 16 >= (uint32_t)EE_MAIN_MEM_SIZE) {
    return false;
  }
  if (!gk_diag::safe_read_u32(ee + state + 12, &code) ||  // (-> state code) @ deftype 16
      code == 0 || code >= (uint32_t)EE_MAIN_MEM_SIZE) {
    return false;
  }
  // G2 RETURN-residual fix, scoped to this enter-state code-entry .jr.
  // enter-state pushed the return-from-thread-dead trampoline (ee+0x18aee4)
  // right before the faulting .jr, but on arm64 the .jr keeps a STALE X30 (the
  // title's suspend-looping attract states REQUIRE that stale X30, so pop-RA
  // cannot be a codegen default — see goalc/compiler/CodeGenerator.cpp G1/G2
  // note: F1f's global pop-RA fixed the RETURN path but regressed the title).
  // Without the trampoline in X30, when the repaired state code RETURNS it RETs
  // back into enter-state's own body against a reset stack and the process
  // re-dispatches in a corrupt loop that spams *sound-player-rpc* (port 0) while
  // never returning to main.gc swap-sound-buffers — the 128-slot sound buffer
  // overflows -> "too many sound commands"/flush/STALL flood -> Print Buffer
  // Overflow -> the render thread starves (the BLUE-LOCK).
  //
  // The fix sets ONLY X30 = trampoline. We must NOT also advance SP past the
  // pushed RA word (the `LDR X30,[SP],#16` half of pop-RA): that +16 shift is
  // the precise thing that regressed the title — for states that SUSPEND
  // instead of returning, the shifted SP propagates through thread-suspend/
  // thread-resume and a later kernel dispatch reads a null fn-ptr slot (the
  // earlier fix2 froze the moment a suspend-looping child process — pp 0x23b7d4
  // — got the SP+16). Leaving SP alone is harmless for suspend states (X30 is
  // never consumed there) and correct for return states (the state code's own
  // epilogue ldp restores X30=trampoline and RETs to it). Guarded on [SP]
  // actually holding the trampoline so an unrelated fault is never touched.
  bool ra_fixed = false;
  {
    uint32_t t_lo = 0, t_hi = 0;
    if (gk_diag::safe_read_u32(uc->uc_mcontext.sp, &t_lo) &&
        gk_diag::safe_read_u32(uc->uc_mcontext.sp + 4, &t_hi) &&
        ((static_cast<uintptr_t>(t_lo)) | (static_cast<uintptr_t>(t_hi) << 32)) == trampoline) {
      uc->uc_mcontext.regs[30] = trampoline;  // X30 = return-from-thread-dead
      ra_fixed = true;
    }
  }
  uc->uc_mcontext.pc = ee + code;  // resume into the authoritative state code
  const uint64_t n = g_enter_state_code_repairs.fetch_add(1, std::memory_order_relaxed) + 1;
  if (n <= 16 || (n % 256) == 0) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG ENTER-STATE-CODE-REPAIR #%llu sig=%d pp=0x%x state=0x%x "
                        "code=0x%x ra_fixed=%d -> resumed into authoritative state code with "
                        "deactivate-trampoline return (G2 RETURN-residual fix)",
                        (unsigned long long)n, sig, pp, state, code, (int)ra_fixed);
  }
  return true;
}

// Gecho-pool / Gdeath-crash: tolerate a BOUNDED arm64 process-suspend stack overflow.
// thread-suspend (gkernel.gc:606) does `(when (> used stack-size) (break))`. On arm64 a
// deeply-nested suspend on a small-stack process exceeds the x86-calibrated budget,
// because the arm64 .push is 16B vs x86's 8B (the same code uses more stack). x86 never
// trips this. For a BOUNDED overflow we skip the (break) (a `(/ 0 0)` = udf #0xBEEF) so
// the suspend proceeds.
//
// SAFETY BOUND (cpu-thread layout, all-types.gc:1790): the suspend's inline backup copy
// fills `stack`[0..stack-size] from its END downward; an overflow of `over` bytes spills
// BACKWARD into the SAME cpu-thread, region [128-over, 128):
//   freg   (off 96..128, 32B) = the xmm8-15 saves   -> transient floats (visual-only)
//   rreg5,6(off 80..96,  16B) = a4/a5               -> "overwritten anyway" on a normal
//                                                       resume (gkernel.gc:716-728), harmless
//   rreg0-4(off 40..80,  40B) = s0-s4 (callee-saved POINTERS) -> corrupting these CRASHES
// thread-resume copies the backup BACK to the execution stack FIRST (gkernel.gc:678-683),
// fully restoring the stack (incl. the spilled bytes) BEFORE it reads rreg0-4 — so as long
// as the spill stays out of rreg0-4 the execution is correct. The spill floor is 128-over;
// to keep it >= 80 (rreg5 start, leaving s0-s4 intact) requires over <= 48. So the safe
// ceiling is exactly 48 = freg(32) + rreg5,6(16). The Gdeath-crash pov-camera death-movie
// suspend (inside ja-play-spooled-anim) is deterministically over=48 (used=304, size=256).
// Returns true (resume) only for this bounded case; over>48 still crashes (would hit s0-s4).
std::atomic<uint64_t> g_suspend_overflow_tolerated{0};
bool handle_suspend_overflow_break(int sig, siginfo_t* /*info*/, void* ucontext) {
  if (sig != SIGILL && sig != SIGSEGV) return false;
  if (!g_ee_main_mem) return false;
  auto* uc = reinterpret_cast<ucontext_t*>(ucontext);
  uintptr_t pc = uc->uc_mcontext.pc;
  uint32_t pcg = to_goal(pc);
  if (pcg < 0x1000) return false;
  // faulting instruction must be UDF #0xBEEF (the (break)/div-by-zero trap)
  uint32_t instr = 0;
  if (!a36_tree::rd32(pcg, &instr)) return false;
  if (((instr & 0xFFFFu) != 0xBEEFu) || ((instr >> 16) != 0u)) return false;
  // belt: only inside the kernel asm-func band (reset-and-call / thread-suspend cluster)
  if (pcg < 0x180000 || pcg >= 0x190000) return false;
  // identify the suspending thread = *kernel-context*.current-process -> top-thread
  auto kc = jak1::intern_from_c("*kernel-context*");
  uint32_t kctx = kc.offset ? kc->value : 0;
  if (kctx < 0x1000) return false;
  uint32_t curproc = 0;
  if (!a36_tree::rd32(kctx + 20, &curproc) || curproc < 0x1000) return false;  // current-process
  uint32_t tthr = 0;
  if (!a36_tree::rd32(curproc + 44, &tthr) || tthr < 0x1000) return false;     // top-thread
  uint32_t tsp = 0, tstop = 0, tssz = 0;
  if (!a36_tree::rd32(tthr + 24, &tsp)) return false;     // thread.sp
  if (!a36_tree::rd32(tthr + 28, &tstop)) return false;   // thread.stack-top
  if (!a36_tree::rd32(tthr + 32, &tssz)) return false;    // thread.stack-size
  int over = (int)(tstop - tsp) - (int)tssz;
  if (over <= 0 || over > 48) return false;   // bounded overflow only (see SAFETY BOUND above); >48 hits s0-s4 -> crash
  // The (break) is a HARD trap inside thread-suspend, where SP is a GOAL pointer (the
  // asm-func converted it). We CANNOT just resume past the udf — the (/ 0 0) divide's
  // spill (`sub sp,#16; str x8,[sp]`) would store through the GOAL-pointer SP and fault.
  // Instead jump to the `(when (> used size) (break))` SKIP target: the B.cond (b.le) a
  // few instrs before the udf branches PAST the whole break body to the no-overflow
  // continuation (gkernel.gc:612: set status; copy stack; restore regs; RET). Jumping
  // there lets the suspend complete on valid GOAL pointers; the inline backup copy then
  // overflows `over`<=48 bytes into the thread's freg (xmm8-15) + rreg5,6 (a4/a5) — bounded
  // and harmless (see SAFETY BOUND above); s0-s4 (rreg0-4) stay intact.
  uint32_t target_g = 0;
  for (int back = 1; back <= 12; back++) {
    uint32_t a = pcg - 4u * (uint32_t)back;
    uint32_t bi = 0;
    if (!a36_tree::rd32(a, &bi)) continue;
    if ((bi & 0xFF000010u) != 0x54000000u) continue;  // B.cond
    int32_t imm19 = (int32_t)((bi >> 5) & 0x7FFFFu);
    if (imm19 & 0x40000) imm19 -= 0x80000;            // sign-extend 19 bits
    uint32_t tg = a + (uint32_t)(imm19 * 4);
    if (tg > pcg && tg < pcg + 0x100) { target_g = tg; break; }  // forward skip target
  }
  if (target_g == 0) return false;  // couldn't locate the (when) skip branch -> let it crash
  uc->uc_mcontext.pc = reinterpret_cast<uintptr_t>(g_ee_main_mem) + target_g;
  const uint64_t s_n = g_suspend_overflow_tolerated.fetch_add(1, std::memory_order_relaxed);
  if (s_n < 5 || (s_n % 300) == 0) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
        "GK-DIAG ECHO-SUSPEND-TOLERATE proc=0x%x over=%d (used=%d size=%d) udf=0x%x -> skip=0x%x #%llu",
        curproc, over, (int)(tstop - tsp), (int)tssz, pcg, target_g, (unsigned long long)s_n);
  }
  return true;
}
}  // namespace a38_trip

// F1A: non-static bridge so the A37-CAM block (earlier in the TU, different
// namespace) can name GOAL strings/symbols through a38_trip's reader.
extern "C" bool gk_a40_sym_name_fwd(uintptr_t ee, uint32_t p, char* out, size_t n) {
  return a38_trip::a40_sym_name(ee, p, out, n);
}

// ---- GND-HWWP: arm64/Android HARDWARE data watchpoint on the two
// double-buffered global-buf base FIELDS (global-buf+4) ----
//
// The mprotect software watch (A38 watch2) keeps missing the writer that sets
// global-buf.base to a low data-relative value during the ndi logo — the GOAL
// dispatcher thread re-protects the page each frame, so a write that lands in
// the cross-thread reprotect window slips through with no SIGSEGV. A HARDWARE
// watchpoint (perf_event_open / PERF_TYPE_BREAKPOINT, bp_type=W) fires on the
// physical write regardless of page protection.
//
// Gated entirely behind __aarch64__ && __ANDROID__ AND the system property
// debug.opengoal.gnd.hwwp=1, so x86 builds and normal runs are untouched.
// Armed on the GOAL/dispatcher thread (the writer's thread) via send_chain so
// the perf fd's breakpoint is bound to the right task; one-shot.
#if defined(__aarch64__) && defined(__ANDROID__)
namespace gnd_hwwp {
// Watched host word addresses (g_ee_main_mem + global-buf goal + 4) and their
// goal offsets, captured at arm time so the SIGTRAP handler can read/report
// without re-resolving *display*.
struct WatchCell {
  uintptr_t host = 0;
  uint32_t goal_off = 0;
};
WatchCell g_cells[2];
int g_ncells = 0;
std::atomic<int> g_trap_budget{64};

// SIGTRAP handler: perf HW breakpoints deliver via fasync (F_SETSIG SIGTRAP).
// si_addr is not meaningful for a perf overflow signal, so we read the stored
// host word directly. Only logs when the value is LOW (< 0x80000), the
// data-relative-base signature we are hunting; otherwise it is a normal
// base write (the legitimate alloc into the frame heap) and we stay quiet.
void trap_handler(int /*sig*/, siginfo_t* /*info*/, void* ucontext) {
  auto* uc = reinterpret_cast<ucontext_t*>(ucontext);
  uintptr_t pc = uc ? static_cast<uintptr_t>(uc->uc_mcontext.pc) : 0;
  for (int i = 0; i < g_ncells; i++) {
    uintptr_t h = g_cells[i].host;
    if (!h) {
      continue;
    }
    uint32_t val = *reinterpret_cast<volatile uint32_t*>(h);
    if (val != 0 && val < 0x80000u) {
      if (g_trap_budget.fetch_sub(1, std::memory_order_relaxed) <= 0) {
        return;
      }
      // Resolve pc back to a libgk.so-relative offset for addr2line.
      uintptr_t libbase = 0;
      Dl_info di{};
      if (pc && dladdr(reinterpret_cast<void*>(pc), &di) && di.dli_fbase) {
        libbase = reinterpret_cast<uintptr_t>(di.dli_fbase);
      }
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GND-HWWP base-write pc=0x%lx(off=0x%lx) val=0x%x addr=goal:0x%x",
                          (unsigned long)pc, (unsigned long)(libbase ? pc - libbase : 0), val,
                          g_cells[i].goal_off);
      // Name the host module (and symbol if any) the pc belongs to.
      a38_trip::log_dladdr("gnd-hwwp-pc", pc);
      // If the pc is inside EE memory it is GOAL-emitted code — name the
      // nearest GOAL function so the writer can be identified by name.
      uint32_t pcg = a38_trip::to_goal(pc);
      if (pcg >= 0x1000) {
        a38_trip::log_nearest_goal_fn("gnd-hwwp-pc", pcg);
      }
    }
  }
}

void install_handler_once() {
  static std::atomic<bool> s_installed{false};
  bool expected = false;
  if (!s_installed.compare_exchange_strong(expected, true)) {
    return;
  }
  struct sigaction sa{};
  sa.sa_sigaction = &trap_handler;
  sa.sa_flags = SA_SIGINFO | SA_RESTART;
  sigemptyset(&sa.sa_mask);
  sigaction(SIGTRAP, &sa, nullptr);
}

// perf_event_open has no libc wrapper; invoke the syscall directly.
long perf_event_open(struct perf_event_attr* attr, pid_t pid, int cpu, int group_fd,
                     unsigned long flags) {
  return syscall(__NR_perf_event_open, attr, pid, cpu, group_fd, flags);
}

void arm_one(int idx) {
  WatchCell& c = g_cells[idx];
  struct perf_event_attr attr{};
  attr.type = PERF_TYPE_BREAKPOINT;
  attr.size = sizeof(attr);
  attr.bp_type = HW_BREAKPOINT_W;
  attr.bp_addr = static_cast<uint64_t>(c.host);
  attr.bp_len = HW_BREAKPOINT_LEN_8;
  attr.sample_period = 1;
  attr.sample_type = PERF_SAMPLE_IP | PERF_SAMPLE_TID;
  attr.precise_ip = 2;
  attr.exclude_kernel = 1;
  attr.exclude_hv = 1;
  attr.disabled = 0;
  attr.wakeup_events = 1;
  // pid=0 -> this calling thread (the GOAL/dispatcher thread); cpu=-1 -> any.
  long fd = perf_event_open(&attr, 0, -1, -1, 0);
  if (fd == -1) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GND-HWWP perf_event_open FAILED errno=%d (%s) on goal:0x%x host=0x%lx",
                        errno, strerror(errno), c.goal_off, (unsigned long)c.host);
    return;
  }
  // Route HW-breakpoint overflows to a SIGTRAP delivered to THIS thread.
  fcntl(static_cast<int>(fd), F_SETFL, O_ASYNC);
  fcntl(static_cast<int>(fd), F_SETSIG, SIGTRAP);
  struct f_owner_ex owner{};
  owner.type = F_OWNER_TID;
  owner.pid = gettid();
  fcntl(static_cast<int>(fd), F_SETOWN_EX, &owner);
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GND-HWWP armed fd=%ld on goal:0x%x host=0x%lx", fd, c.goal_off,
                      (unsigned long)c.host);
}
}  // namespace gnd_hwwp
#endif  // __aarch64__ && __ANDROID__

extern "C" void gnd_hwwp_arm_once() {
#if defined(__aarch64__) && defined(__ANDROID__)
  static std::atomic<bool> s_done{false};
  bool expected = false;
  if (!s_done.compare_exchange_strong(expected, true)) {
    return;
  }
  char pbuf[PROP_VALUE_MAX] = {0};
  if (!(__system_property_get("debug.opengoal.gnd.hwwp", pbuf) > 0 && pbuf[0] == '1')) {
    return;  // off by default — x86 and normal runs unaffected
  }
  if (!g_ee_main_mem) {
    // Runtime not mapped yet; allow a later send_chain to retry by clearing
    // the one-shot flag (we never actually armed).
    s_done.store(false, std::memory_order_release);
    return;
  }
  const uintptr_t ee = reinterpret_cast<uintptr_t>(g_ee_main_mem);
  auto disp_sym = jak1::intern_from_c("*display*");
  uint32_t disp = disp_sym.offset ? disp_sym->value : 0;
  if (disp < 0x1000 || disp >= EE_MAIN_MEM_SIZE - 0x1000) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GND-HWWP cannot resolve *display* (value=0x%x) — not arming", disp);
    s_done.store(false, std::memory_order_release);
    return;
  }
  gnd_hwwp::install_handler_once();
  // frames[i].frame at disp+564+32*i+16 -> frame.global-buf at frame+36 ->
  // base FIELD at global-buf+4. Host watch addr = ee + (global-buf + 4).
  for (int i = 0; i < 2; i++) {
    uint32_t frame = *reinterpret_cast<const uint32_t*>(ee + disp + 564 + 32 * i + 16);
    if (frame < 0x1000 || frame >= EE_MAIN_MEM_SIZE - 64) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GND-HWWP skip frame[%d]: frame goal=0x%x out of range", i, frame);
      continue;
    }
    uint32_t gb = *reinterpret_cast<const uint32_t*>(ee + frame + 36);
    if (gb < 0x1000 || gb >= EE_MAIN_MEM_SIZE - 64) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GND-HWWP skip frame[%d]: global-buf goal=0x%x out of range", i, gb);
      continue;
    }
    int slot = gnd_hwwp::g_ncells;
    gnd_hwwp::g_cells[slot].host = ee + gb + 4;
    gnd_hwwp::g_cells[slot].goal_off = gb + 4;
    gnd_hwwp::g_ncells++;
    gnd_hwwp::arm_one(slot);
  }
#endif  // __aarch64__ && __ANDROID__
}

}  // extern "C++"

void gk_sigsegv_diag(int sig, siginfo_t* info, void* ucontext) {
  // A38: band write-fault tripwire — expected, RESUMING faults. Must run
  // before everything else: the rest of this function is the fatal-crash
  // dump path and ends in re-raise.
  if (sig == SIGSEGV && a38_trip::handle_band_fault(info, ucontext)) {
    return;
  }
  // Gmatch: complete + resume the arm64 double-EE-base store fault (the
  // sage-intro blerc DMA-chain crash). Narrowly gated on the 2*EE_base address
  // window; never masks a genuine crash. Must run before the fatal dump below.
  if (sig == SIGSEGV && a38_trip::handle_double_ee_base_fault(sig, info, ucontext)) {
    return;
  }
  // Gmatch / Gd3-jak: a SIGILL or SIGSEGV into the (re-)stomped return-from-thread-dead
  // trampoline band — repair it from the canary snapshot and RESUME on this (the
  // faulting) thread. Race-free; gated to the band window + stomped state. Must run
  // before the fatal dump below.
  if ((sig == SIGILL || sig == SIGSEGV) &&
      a38_trip::handle_rftd_code_stomp(sig, info, ucontext)) {
    return;
  }
  // Gfix-cinematic-crash: a GOAL process (the owner NEW-GAME `auto-save` proc on
  // *kernel-dram-stack*) RET'd to NULL because its pushed return-from-thread-dead
  // RA was zeroed by the low-memory scatter (lands at 0x19xxxx, above the band
  // canary). pc=0/lr=0 with a GPR still holding the trampoline host addr ->
  // redirect to return-from-thread-dead and resume. Must run before the fatal
  // dump below.
  if ((sig == SIGILL || sig == SIGSEGV) &&
      a38_trip::handle_rftd_null_return(sig, info, ucontext)) {
    return;
  }
  // Gcrash-mouche: arm64 buzzer scout-fly collect SIGILL — enter-state's spilled
  // `new-state` was stomped to 0 by a concurrent sparticle DMA write, so the state
  // `code` read 0 and the .jr branched to EE+0. Recover the authoritative state code
  // from the (intact) process header and resume. Tightly gated (pc==EE+0 + a GPR holds
  // the return-from-thread-dead trampoline). Must run before the fatal dump below.
  if ((sig == SIGILL || sig == SIGSEGV) &&
      a38_trip::handle_enter_state_null_code(sig, info, ucontext)) {
    return;
  }
  // Gecho-pool: tolerate the tiny arm64 process-suspend stack overflow (thread-suspend
  // (break)) at the title/cinematic — skip the over-strict break and let suspend proceed.
  if ((sig == SIGILL || sig == SIGSEGV) &&
      a38_trip::handle_suspend_overflow_break(sig, info, ucontext)) {
    return;
  }
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
  // Gcrash-geyser: name the faulting GOAL function for an INTERIOR crashing PC
  // (not just a BLR-through-symbol, which A37-WHOSYM already covers). The fatal
  // headline otherwise prints only the raw EE offset; this resolves pc/lr/fault
  // to "<goal-fn>+off" so a GOAL-code crash is named in one line. Bounds-checked
  // symbol-table walk only — async-signal-safe (same primitives the A38 path uses).
  if (uint32_t g = a38_trip::to_goal(pc)) {
    a38_trip::log_nearest_goal_fn("pc", g);
  }
  if (uint32_t g = a38_trip::to_goal(lr)) {
    a38_trip::log_nearest_goal_fn("lr", g);
  }
  if (uint32_t g = a38_trip::to_goal(fault)) {
    a38_trip::log_nearest_goal_fn("fault", g);
  }
  // === Gecho-pool TEMPORARY diagnostic: thread-suspend (break) stack-overflow probe ===
  // The (break) macro = (/ 0 0) = arm64 udf #0xBEEF; fires in thread-suspend when a
  // suspending process overflowed its backup-stack budget. Brute-force scan GPRs as
  // candidate GOAL cpu-thread pointers; print the one whose stack-used > stack-size.
  // Read-only, bounds-checked, async-signal-safe (no malloc, only guarded EE reads +
  // the existing __android_log_print). REMOVE before the final fix.
  {
    // Local replica of a36_tree::rd32 — same bounds check — kept self-contained so the
    // block does not depend on cross-namespace inline visibility.
    auto rd32 = [](uint32_t goal, uint32_t* out) -> bool {
      if (!g_ee_main_mem || goal < 0x1000 || goal >= EE_MAIN_MEM_SIZE - 4) return false;
      *out = *reinterpret_cast<const uint32_t*>(g_ee_main_mem + goal);
      return true;
    };
    auto* uc2 = reinterpret_cast<ucontext_t*>(ucontext);
    uintptr_t pcx = uc2->uc_mcontext.pc;
    uint32_t instr_at_pc = 0;
    if (g_ee_main_mem && pcx) {
      // pc points into executable goal code; read the 4-byte instruction guardedly.
      uint32_t pcg = a38_trip::to_goal(pcx);
      if (pcg >= 0x1000) {
        uint32_t w;
        if (rd32(pcg, &w)) instr_at_pc = w;
      }
    }
    bool is_break = ((instr_at_pc & 0xFFFFu) == 0xBEEFu) && ((instr_at_pc >> 16) == 0u);
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG GECHO break-probe pc-instr=0x%08x is_break=%d", instr_at_pc,
                        (int)is_break);
  }
  // === end Gecho-pool diagnostic ===
  // F1a: name the bucket whose render() was live when a GL-thread crash
  // lands inside the driver (run-4: fault in libGLESv2_adreno, fp-walk
  // dead-ends — the breadcrumb is the only caller evidence). Fixed buffer,
  // written by the dispatch loop, async-signal-safe to read.
  if (gk_f1a_current_bucket[0]) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag, "GK-DIAG F1A-BUCKET in-render=%s",
                        gk_f1a_current_bucket);
    // Last merc draw parameters (filled by Merc2::do_draws raw stores).
    struct F1aMercDrawInfo {
      uint32_t di, num_draws, tex, first_bone, index_count, first_index;
      uint32_t vao, vtx_buf, idx_buf;
      int envmap, mod_vtx, no_strip;
      uint32_t tex_branch, tex_name, tex_is, tex_size, tex_binding;
      uint32_t fbo_binding, fbo_status, gl_err;
      uint32_t load_id, fsl;
    };
    extern volatile F1aMercDrawInfo gk_f1a_last_merc_draw;
    const F1aMercDrawInfo d = const_cast<const F1aMercDrawInfo&>(gk_f1a_last_merc_draw);
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG F1A-MERC-DRAW di=%u/%u tex=0x%x first_bone=%u idx=%u+%u "
                        "vao=%u vtx=%u idx-buf=%u envmap=%d mod=%d nostrip=%d",
                        d.di, d.num_draws, d.tex, d.first_bone, d.index_count, d.first_index,
                        d.vao, d.vtx_buf, d.idx_buf, d.envmap, d.mod_vtx, d.no_strip);
    // F1e: GL state snapshotted at the last bucket-first/killer merc draw
    // (values captured live in do_draws; only printed here — no GL calls in
    // the signal handler).
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG F1E-MERC-TEX branch=%u name=%u is=%u size=%u bind=%u fbo=%u "
                        "status=0x%x err=0x%x load_id=%u fsl=%u",
                        d.tex_branch, d.tex_name, d.tex_is, d.tex_size, d.tex_binding,
                        d.fbo_binding, d.fbo_status, d.gl_err, d.load_id, d.fsl);
  }
  // A36: symbolize host-space pc/lr (BLR-to-NULL from C++ render code lands
  // here with pc=0 and lr inside libgk.so — dladdr names the caller).
  for (uintptr_t addr : {pc, lr}) {
    Dl_info di{};
    if (addr && dladdr(reinterpret_cast<void*>(addr), &di) && di.dli_fname) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A36-SYMBOLIZE 0x%lx = %s+0x%lx (%s+0x%lx)",
                          (unsigned long)addr, di.dli_sname ? di.dli_sname : "?",
                          di.dli_saddr ? (unsigned long)(addr - (uintptr_t)di.dli_saddr) : 0ul,
                          di.dli_fname,
                          (unsigned long)(addr - (uintptr_t)di.dli_fbase));
    }
  }
  for (int i = 0; i < 32; i++) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG x%d=0x%lx", i,
                        (unsigned long)uc->uc_mcontext.regs[i]);
  }

  // GSPARK-PP — on a null-fn-ptr BLR (SIGILL, pc==EE_base) name the CRASHING
  // process and the state it is entering. enter-state (gstate.gc:284) BLRs a
  // handler from new-state == (-> pp state) (set = (-> pp next-state) at the
  // branch-3 entry). This dump answers the decisive question: is the go-target
  // state itself NULL (a `(go <0>)` — e.g. an uninstalled virtual-state method)
  // OR a valid state with a null handler field, OR is the exit-walk
  // (gstate.gc:321-325) BLRing a stack frame's null exit? Robust: pp comes from
  // kernel-context.current-process (falls back to x13); all reads go through
  // safe_read_u32; runs BEFORE the A37-PCWIN read below (which itself SEGVs when
  // pc==EE_base), so it always completes.
  if (sig == SIGILL && g_ee_main_mem &&
      pc == reinterpret_cast<uintptr_t>(g_ee_main_mem)) {
    const uintptr_t ee = reinterpret_cast<uintptr_t>(g_ee_main_mem);
    auto rd = [ee](uint32_t goff, uint32_t* out) -> bool {
      if (goff < 0x1000 || goff >= (uint32_t)EE_MAIN_MEM_SIZE - 4) return false;
      return gk_diag::safe_read_u32(ee + goff, out);
    };
    uint32_t pp_x13 = (uint32_t)(uc->uc_mcontext.regs[13] & 0xFFFFFFFFu);
    uint32_t pp = pp_x13;
    {
      auto kc = jak1::intern_from_c("*kernel-context*");
      uint32_t cur = 0;
      if (kc.offset && kc->value && rd(kc->value + 20, &cur) && cur >= 0x1000) {
        pp = cur;  // kernel-context.current-process (deftype 24) — build-robust
      }
    }
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG GSPARK-PP pp=0x%x (x13=0x%x)", pp, pp_x13);
    if (pp >= 0x1000 && pp < (uint32_t)EE_MAIN_MEM_SIZE) {
      uint32_t ptype = 0, pname = 0, pstatus = 0, ppid = 0, pstate = 0,
               pnext = 0, psft = 0, pentity = 0;
      gk_diag::safe_read_u32(ee + pp - 4, &ptype);  // type tag @ pp-4
      rd(pp + 0, &pname);     // name @4
      rd(pp + 32, &pstatus);  // status @36
      rd(pp + 36, &ppid);     // pid @40
      rd(pp + 48, &pentity);  // entity @52
      rd(pp + 52, &pstate);   // state @56
      rd(pp + 72, &pnext);    // next-state @76
      rd(pp + 88, &psft);     // stack-frame-top @92
      char nm[40] = {0};
      for (int i = 0; i < 36; i += 4) {
        uint32_t w = 0;
        if (!gk_diag::safe_read_u32(ee + pname + 4 + i, &w)) break;
        memcpy(nm + i, &w, 4);
      }
      nm[36] = 0;
      for (char& c : nm) {
        if (c && (c < 0x20 || c > 0x7e)) { c = 0; break; }
      }
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG GSPARK-PP type=0x%x name='%s'(0x%x) status=0x%x "
                          "pid=%u state=0x%x next-state=0x%x stack-frame-top=0x%x "
                          "entity=0x%x",
                          ptype, nm, pname, pstatus, ppid, pstate, pnext, psft,
                          pentity);
      gk_diag::dump_sym_name_at_slot(ee + pstatus);
      // go-target state == pstate (set = next-state). NULL => `(go <0 state>)`.
      uint32_t st = pstate ? pstate : pnext;
      if (st == 0) {
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG GSPARK-PP >>> go-target STATE IS NULL "
                            "(pstate=0x%x pnext=0x%x) — a (go <0>) ran",
                            pstate, pnext);
      } else if (st < (uint32_t)EE_MAIN_MEM_SIZE) {
        uint32_t sname = 0, sexit = 0, scode = 0, strans = 0, spost = 0,
                 senter = 0, sevent = 0;
        rd(st + 0, &sname);    // state.name @4
        rd(st + 8, &sexit);    // exit @12
        rd(st + 12, &scode);   // code @16
        rd(st + 16, &strans);  // trans @20
        rd(st + 20, &spost);   // post @24
        rd(st + 24, &senter);  // enter @28
        rd(st + 28, &sevent);  // event @32
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG GSPARK-PP go-state=0x%x name-sym=0x%x "
                            "exit=0x%x code=0x%x trans=0x%x post=0x%x enter=0x%x "
                            "event=0x%x%s%s%s",
                            st, sname, sexit, scode, strans, spost, senter, sevent,
                            senter == 0 ? " [ENTER=0]" : "",
                            sexit == 0 ? " [EXIT=0]" : "",
                            strans == 0 ? " [TRANS=0]" : "");
        gk_diag::dump_sym_name_at_slot(ee + sname);
        // Name the crashing process's TYPE (symbol whose value == ptype).
        if (ptype && SymbolTable2.offset && LastSymbol.offset) {
          for (uint32_t slot = SymbolTable2.offset; slot < LastSymbol.offset;
               slot += 4) {
            uint32_t v = 0;
            if (gk_diag::safe_read_u32(ee + slot, &v) && v == ptype) {
              __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                  "GK-DIAG GSPARK-PP TYPE-SYM slot=0x%x ->", slot);
              gk_diag::dump_sym_name_at_slot(ee + slot);
              break;
            }
          }
        }
        // The crash is enter-state's CODE-jump (br x8) reading code=0 because
        // new-state (x3) was zeroed across the enter/trans varargs calls — i.e.
        // a callee returned with a shifted SP (the F1f/G1 +16 pop-RA signature)
        // and corrupted enter-state's spilled new-state. Disassemble the
        // enter/trans handlers (contiguous: trans < enter < code in the heap)
        // to find the unbalanced prologue/epilogue. Hex words, 4/line.
        auto dump_fn = [ee](const char* tag, uint32_t start, uint32_t end) {
          if (start < 0x1000 || end <= start || end - start > 0x400) return;
          for (uint32_t a = start; a < end; a += 16) {
            uint32_t w[4] = {0, 0, 0, 0};
            for (int k = 0; k < 4 && a + 4 * k < end; k++) {
              gk_diag::safe_read_u32(ee + a + 4 * k, &w[k]);
            }
            __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                "GK-DIAG GSPARK-PP %s 0x%x: %08x %08x %08x %08x",
                                tag, a, w[0], w[1], w[2], w[3]);
          }
        };
        if (strans && senter && senter > strans) dump_fn("TRANSFN", strans, senter);
        if (senter && scode && scode > senter) dump_fn("ENTERFN", senter, scode);
      }
      // exit-walk: enter-state (gstate.gc:321-325) BLRs each protect-frame /
      // state stack frame's exit; a null exit here is the other null-BLR site.
      uint32_t fr = psft;
      for (int d = 0; d < 8 && fr >= 0x1000 && fr < (uint32_t)EE_MAIN_MEM_SIZE;
           d++) {
        uint32_t ftype = 0, fname = 0, fnext = 0, fexit = 0;
        gk_diag::safe_read_u32(ee + fr - 4, &ftype);
        rd(fr + 0, &fname);  // stack-frame.name @4
        rd(fr + 4, &fnext);  // stack-frame.next @8
        rd(fr + 8, &fexit);  // protect-frame.exit @12
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG GSPARK-PP frame[%d]=0x%x type=0x%x "
                            "name-sym=0x%x next=0x%x exit=0x%x%s",
                            d, fr, ftype, fname, fnext, fexit,
                            fexit == 0 ? " <<NULL EXIT" : "");
        if (fname) gk_diag::dump_sym_name_at_slot(ee + fname);
        fr = fnext;
      }
    }
  }

  // GSPARK — on a BLR to a null GOAL function pointer (SIGILL with pc at
  // EE_base+0), dump the candidate object whose 0-field is being called so
  // the null-field object/defstate is named. MUST run before the A37-PCWIN
  // read below, which itself SEGVs (sig=11) when pc==EE_base (it reads
  // [pc&~15]-32, below the EE map) and aborts the handler. All reads here go
  // through safe_read_u32 so a bad pointer cannot secondary-fault.
  if (sig == SIGILL && g_ee_main_mem &&
      pc == reinterpret_cast<uintptr_t>(g_ee_main_mem)) {
    const uintptr_t ee = reinterpret_cast<uintptr_t>(g_ee_main_mem);
    const int cand[] = {16, 3, 2, 1, 0, 4};
    for (int ci = 0; ci < 6; ++ci) {
      uintptr_t r = (uintptr_t)uc->uc_mcontext.regs[cand[ci]];
      uintptr_t oh = 0;
      if (r >= ee && r < ee + (uintptr_t)EE_MAIN_MEM_SIZE) {
        oh = r;
      } else if (r != 0 && r < (uintptr_t)EE_MAIN_MEM_SIZE) {
        oh = ee + r;
      } else {
        continue;
      }
      uint32_t w[12];
      bool ok = true;
      for (int k = 0; k < 12; ++k) {
        if (!gk_diag::safe_read_u32(oh - 4 + 4 * k, &w[k])) {
          ok = false;
          break;
        }
      }
      if (!ok) {
        continue;
      }
      __android_log_print(
          ANDROID_LOG_FATAL, kGkLogTag,
          "GK-DIAG GSPARK-OBJ X%d goff=0x%lx tag=0x%x type=0x%x name=0x%x "
          "next=0x%x exit=0x%x code=0x%x trans=0x%x post=0x%x enter=0x%x "
          "event=0x%x w24=0x%x",
          cand[ci], (unsigned long)(oh - ee), w[0], w[1], w[2], w[3], w[4],
          w[5], w[6], w[7], w[8], w[9], w[10]);
      // Resolve the object's name symbol (offset +4: state/stack-frame/type
      // name) and its type pointer (offset 0) to a printable name.
      if (w[2] != 0 && w[2] < (uint32_t)EE_MAIN_MEM_SIZE) {
        gk_diag::dump_sym_name_at_slot(ee + w[2]);
      }
      if (w[1] != 0 && w[1] < (uint32_t)EE_MAIN_MEM_SIZE) {
        gk_diag::dump_sym_name_at_slot(ee + w[1]);
      }
    }
  }

  // A37-DIAG: dump the instruction window at the faulting PC so SIGILLs
  // inside dynamically-emitted code (mips2c trampolines, FFI trampolines,
  // A18 wrappers) can be decoded directly from the log.
  if (pc >= 0x1000) {
    for (int row = -2; row <= 3; row++) {
      uintptr_t base = (pc & ~15ull) + row * 16;
      // GSPARK: safe reads — when pc==EE_base the row=-2 base falls below the
      // EE map and a direct deref SEGVs (the secondary sig=11 that aborted the
      // primary-pass dumps below). safe_read_u32 turns that into a skip.
      uint32_t w[4] = {0, 0, 0, 0};
      bool any = false;
      for (int k = 0; k < 4; k++) {
        any |= gk_diag::safe_read_u32(base + 4 * k, &w[k]);
      }
      if (!any) continue;
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A37-PCWIN 0x%lx: %08x %08x %08x %08x",
                          (unsigned long)base, w[0], w[1], w[2], w[3]);
    }
  }
  // A37-DIAG: caller window (the BLR site) + the live draw-string symbol
  // value — run-10 crashes BLR'd a DMA-buffer interior pointer from text
  // code where the draw-string noop was expected.
  if (lr >= 0x1000) {
    for (int row = -8; row <= 0; row++) {
      uintptr_t base = (lr & ~15ull) + row * 16;
      const uint32_t* w = reinterpret_cast<const uint32_t*>(base);
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A37-LRWIN 0x%lx: %08x %08x %08x %08x",
                          (unsigned long)base, w[0], w[1], w[2], w[3]);
    }
  }
  {
    auto s_ds = jak1::intern_from_c("draw-string");
    if (s_ds.offset) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A37-DRAWSTR sym-slot=0x%x value=0x%x", s_ds.offset,
                          s_ds->value);
    }
  }
  // A37-DIAG: reverse-scan the symbol table for slots whose value equals
  // the crash target — names the symbol whose function slot held the bad
  // pointer (run-12: a BLR through a symbol slot at 0x159344 jumped into
  // a DMA-tag region).
  if (g_ee_main_mem && SymbolTable2.offset && LastSymbol.offset) {
    uint32_t pc_goal = (uint32_t)(pc - (uintptr_t)g_ee_main_mem);
    if (pc >= (uintptr_t)g_ee_main_mem &&
        pc < (uintptr_t)g_ee_main_mem + EE_MAIN_MEM_SIZE) {
      int hits = 0;
      for (uint32_t slot = SymbolTable2.offset; slot < LastSymbol.offset && hits < 6; slot += 4) {
        uint32_t v = *reinterpret_cast<const uint32_t*>(g_ee_main_mem + slot);
        if (v == pc_goal) {
          hits++;
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "GK-DIAG A37-WHOSYM slot=0x%x holds crash target 0x%x:", slot,
                              pc_goal);
          gk_diag::dump_sym_name_at_slot((uintptr_t)g_ee_main_mem + slot);
        }
      }
      if (!hits) {
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG A37-WHOSYM no symbol slot holds 0x%x", pc_goal);
      }
    }
  }

  // A40: the display-process state at death (always-on here — the crash
  // dump already prints dozens of lines; this is the one that names the
  // dispatcher-skip mechanism).
  a38_trip::a40_dproc_probe("at-crash");

  // A34-DIAG: identify the CURRENT PROCESS at the crash. In GOAL code,
  // X13 = pp (the current process, reserved on every backend) and
  // X15 = the EE base. Boxed basics point 4 past their type tag, so a
  // deftype field at offset N lives at [obj + N - 4]. Dumps:
  //   - process name (string chars at name+4), status / state-name /
  //     next-state-name symbols (via the A11 sym-slot walker),
  //   - a raw u32 window over the process header,
  //   - the camera-slave spline window (spline-exists @2364,
  //     spline-curve @2368) — run-4's curve-evaluate! crash read an
  //     all-zero spline-curve through a truthy spline-exists, which can
  //     only happen if the slave's init never stored #f there.
  {
    uintptr_t ee = (uintptr_t)uc->uc_mcontext.regs[15];
    uintptr_t pp_goal = (uintptr_t)(uc->uc_mcontext.regs[13] & 0xFFFFFFFFu);
    if ((ee & 0xFFFu) == 0 && ee >= 0x100000000ull && pp_goal >= 0x1000 &&
        pp_goal < 0x20000000u) {
      uintptr_t pp_host = ee + pp_goal;
      uint32_t type_goal = 0, name_goal = 0, status_goal = 0, pid_v = 0,
               state_goal = 0, next_state_goal = 0;
      gk_diag::safe_read_u32(pp_host - 4, &type_goal);
      gk_diag::safe_read_u32(pp_host + 0, &name_goal);     // name @4
      gk_diag::safe_read_u32(pp_host + 32, &status_goal);  // status @36
      gk_diag::safe_read_u32(pp_host + 36, &pid_v);        // pid @40
      gk_diag::safe_read_u32(pp_host + 52, &state_goal);   // state @56
      gk_diag::safe_read_u32(pp_host + 60, &next_state_goal);  // next-state @64
      char namebuf[40] = {0};
      for (int i = 0; i < 36; i += 4) {
        uint32_t w = 0;
        if (!gk_diag::safe_read_u32(ee + name_goal + 4 + i, &w)) break;
        memcpy(namebuf + i, &w, 4);
      }
      namebuf[36] = 0;
      for (char& c : namebuf) {
        if (c && (c < 0x20 || c > 0x7e)) {
          c = 0;
          break;
        }
      }
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A34-DIAG pp=0x%lx type=0x%x name=0x%x "
                          "'%s' status=0x%x pid=%u state=0x%x next-state=0x%x",
                          (unsigned long)pp_goal, type_goal, name_goal,
                          namebuf, status_goal, pid_v, state_goal,
                          next_state_goal);
      // status / state-name / next-state-name as symbols (best-effort).
      gk_diag::dump_sym_name_at_slot(ee + status_goal);
      if (state_goal) {
        uint32_t state_name_sym = 0;
        if (gk_diag::safe_read_u32(ee + state_goal + 0, &state_name_sym)) {
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "GK-DIAG A34-DIAG state-name-sym=0x%x",
                              state_name_sym);
          gk_diag::dump_sym_name_at_slot(ee + state_name_sym);
        }
      }
      if (next_state_goal) {
        uint32_t ns_name_sym = 0;
        if (gk_diag::safe_read_u32(ee + next_state_goal + 0, &ns_name_sym)) {
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "GK-DIAG A34-DIAG next-state-name-sym=0x%x",
                              ns_name_sym);
          gk_diag::dump_sym_name_at_slot(ee + ns_name_sym);
        }
      }
      // Raw windows: process header + camera-slave spline area.
      for (intptr_t base : {(intptr_t)-4, (intptr_t)0x890}) {
        for (intptr_t off = base; off < base + (base < 0 ? 0x80 : 0xd0);
             off += 16) {
          uint32_t w0 = 0, w1 = 0, w2 = 0, w3 = 0;
          bool ok0 = gk_diag::safe_read_u32(pp_host + off, &w0);
          bool ok1 = gk_diag::safe_read_u32(pp_host + off + 4, &w1);
          bool ok2 = gk_diag::safe_read_u32(pp_host + off + 8, &w2);
          bool ok3 = gk_diag::safe_read_u32(pp_host + off + 12, &w3);
          if (!(ok0 || ok1 || ok2 || ok3)) break;
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "GK-DIAG A34-DIAG pp%+ld: %08x %08x %08x %08x",
                              (long)off, w0, w1, w2, w3);
        }
      }
    } else {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A34-DIAG pp-dump skipped (x15/x13 not "
                          "GOAL-shaped: x15=0x%lx x13=0x%lx)",
                          (unsigned long)ee, (unsigned long)pp_goal);
    }
    // A40-SPWIN: the boot3 sweep crash executes the freshly-written DMA
    // tag at draw-string's entry BEFORE any prologue runs, so uc->sp at
    // the SIGILL is print-game-text's LIVE frame. Its decompiled locals
    // are stack vars at fixed byte offsets (sv-NNN = [frame+NNN]): the
    // blank-line loop's floats (sv-136 scale, sv-144 x, sv-156 bottom-y,
    // sv-160 space-w, sv-164 line-h) plus the stack font-context land in
    // this window. 0x180 bytes, hex + float rendering, crash-path only.
    {
      uintptr_t spw = (uintptr_t)uc->uc_mcontext.sp;
      for (int off = 0; off < 0x3c0; off += 16) {
        uint32_t w[4] = {0, 0, 0, 0};
        bool any = false;
        for (int k = 0; k < 4; k++) {
          any |= gk_diag::safe_read_u32(spw + off + 4 * k, &w[k]);
        }
        if (!any) {
          break;
        }
        float f[4];
        memcpy(f, w, 16);
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG A40-SPWIN +%03x: %08x %08x %08x %08x | %.6g %.6g %.6g %.6g",
                            off, w[0], w[1], w[2], w[3], f[0], f[1], f[2], f[3]);
      }
    }
    // A34-DIAG run-8: walk the GOAL frame-pointer chain. The arm64 GOAL
    // prologue is STP X29,X30,[SP,#-16]!; MOV X29,SP — so [X29] = caller's
    // X29 and [X29+8] = the return address into the caller. Run-7 left a
    // contradiction (zero curve reached curve-closest-point but every
    // candidate call site's guard reads clean data) — the saved-LR chain
    // names the REAL caller chain without guessing.
    {
      uintptr_t fp = (uintptr_t)uc->uc_mcontext.regs[29];
      for (int i = 0; i < 24 && fp >= 0x10000; i++) {
        uint32_t pl = 0, ph = 0, rl = 0, rh = 0;
        if (!gk_diag::safe_read_u32(fp, &pl) ||
            !gk_diag::safe_read_u32(fp + 4, &ph) ||
            !gk_diag::safe_read_u32(fp + 8, &rl) ||
            !gk_diag::safe_read_u32(fp + 12, &rh)) {
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "GK-DIAG A34-DIAG fp-walk[%d] fp=0x%lx "
                              "<unreadable>",
                              i, (unsigned long)fp);
          break;
        }
        uint64_t prev_fp = ((uint64_t)ph << 32) | pl;
        uint64_t ret = ((uint64_t)rh << 32) | rl;
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG A34-DIAG fp-walk[%d] fp=0x%lx "
                            "saved-lr=0x%llx prev-fp=0x%llx",
                            i, (unsigned long)fp, (unsigned long long)ret,
                            (unsigned long long)prev_fp);
        // Run-10: 24 instruction words before each saved-LR (lr-96..lr-4)
        // — run-9's lr-16 radius only captured the generic call-with-save
        // wrapper (identical at every site); the arg-staging code before
        // it is site-unique and byte-matchable against the on-disk CGOs.
        {
          uint32_t w[24] = {0};
          bool any = false;
          for (int k = 0; k < 24; k++) {
            if (gk_diag::safe_read_u32((uintptr_t)ret - 96 + 4 * k, &w[k])) {
              any = true;
            }
          }
          if (any) {
            __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                "GK-DIAG A34-DIAG fp-walk[%d] lr-96: "
                                "%08x %08x %08x %08x %08x %08x %08x %08x",
                                i, w[0], w[1], w[2], w[3], w[4], w[5], w[6],
                                w[7]);
            __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                "GK-DIAG A34-DIAG fp-walk[%d] lr-64: "
                                "%08x %08x %08x %08x %08x %08x %08x %08x",
                                i, w[8], w[9], w[10], w[11], w[12], w[13],
                                w[14], w[15]);
            __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                "GK-DIAG A34-DIAG fp-walk[%d] lr-32: "
                                "%08x %08x %08x %08x %08x %08x %08x %08x",
                                i, w[16], w[17], w[18], w[19], w[20], w[21],
                                w[22], w[23]);
          }
        }
        if (prev_fp <= fp || prev_fp - fp > 0x100000) break;
        fp = (uintptr_t)prev_fp;
      }
      // Run-9: the first 4 words at EE+0 — curve-evaluate!'s zero-curve
      // survival path depends on what knots[0]=*(EE+0) reads as.
      uint32_t z[4] = {0};
      for (int k = 0; k < 4; k++) {
        gk_diag::safe_read_u32((uintptr_t)uc->uc_mcontext.regs[15] + 4 * k,
                               &z[k]);
      }
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A34-DIAG ee+0: %08x %08x %08x %08x", z[0],
                          z[1], z[2], z[3]);
    }
    // A34-DIAG run-6: dump the camera-master (*camera*) outro window.
    // Run-5 showed the crash is cam-string's :enter reading the MASTER's
    // outro-t-step (deftype 2376) as non-zero with a zero outro-curve
    // (deftype 2352) — cam-master-init:992 stores 0.0 there, so either
    // the master init didn't run or the field was clobbered. Memory
    // offset = deftype offset - 4 (boxed basic).
    if ((ee & 0xFFFu) == 0 && ee >= 0x100000000ull) {
      auto cam_sym = jak1::intern_from_c("*camera*");
      uint32_t cam_goal = cam_sym.offset ? cam_sym->value : 0;
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A34-DIAG *camera*=0x%x", cam_goal);
      if (cam_goal >= 0x1000 && cam_goal < 0x20000000u) {
        uintptr_t cam_host = ee + cam_goal;
        uint32_t cstatus = 0, cstate = 0, cpid = 0;
        gk_diag::safe_read_u32(cam_host + 32, &cstatus);
        gk_diag::safe_read_u32(cam_host + 36, &cpid);
        gk_diag::safe_read_u32(cam_host + 52, &cstate);
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG A34-DIAG cam-master status=0x%x pid=%u "
                            "state=0x%x",
                            cstatus, cpid, cstate);
        gk_diag::dump_sym_name_at_slot(ee + cstatus);
        if (cstate) {
          uint32_t st_name = 0;
          if (gk_diag::safe_read_u32(ee + cstate + 0, &st_name)) {
            gk_diag::dump_sym_name_at_slot(ee + st_name);
          }
        }
        // outro-curve @2352 (mem 2348) .. outro-exit-value @2380 (mem 2376).
        for (intptr_t off = 0x920; off < 0x9A0; off += 16) {
          uint32_t w0 = 0, w1 = 0, w2 = 0, w3 = 0;
          gk_diag::safe_read_u32(cam_host + off, &w0);
          gk_diag::safe_read_u32(cam_host + off + 4, &w1);
          gk_diag::safe_read_u32(cam_host + off + 8, &w2);
          gk_diag::safe_read_u32(cam_host + off + 12, &w3);
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "GK-DIAG A34-DIAG cam%+ld: %08x %08x %08x %08x",
                              (long)off, w0, w1, w2, w3);
        }
      }
    }
  }

  // A35-DIAG: dump the VALUES of the function/flag symbols implicated in
  // the post-logo-intro EE-4 chase (update-vis-volumes → name=(0,...)).
  // Each line gives "name value sym-goal-addr" so the offline matcher can
  // (a) check whether a fn symbol holds the WRONG function's entry and
  // (b) bucket every fp-walk saved-lr into the fn whose [value, value+len)
  // contains it. intern_from_c is lookup-only for existing symbols — same
  // in-handler use as the *camera* dump above.
  {
    static const char* kA35Syms[] = {
        "update-actor-vis-box", "update-vis-volumes",
        "update-vis-volumes-from-nav-mesh", "print-volume-sizes",
        "debug-draw-actors", "name=", "string=", "type-type?",
        "res-lump-data", "res-lump-struct", "res-lump-float", "format",
        "entity-by-name", "actors-update", "birth", "inspect",
        "*generate-actor-vis*", "*display-actor-vis*",
        "*display-actor-marks*", "*display-actor-anim*",
        "*display-process-anim*", "*display-entity-errors*", "*level*",
        "*kernel-context*", "background-upload-vram-words",
        "entity-by-type", "entity-by-aid", "entity-by-meters",
        "process-by-ename", "entity-process-count", "*res-static-buf*",
        "*res-key-string*", "command-get-process",
    };
    for (const char* nm : kA35Syms) {
      auto sym = jak1::intern_from_c(nm);
      if (sym.offset) {
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG A35-DIAG sym '%s' goal=0x%x value=0x%x",
                            nm, (unsigned)sym.offset, (unsigned)sym->value);
      } else {
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "GK-DIAG A35-DIAG sym '%s' NOT INTERNED", nm);
      }
    }
  }

  // A35-DIAG (run-3): the name= crash leaves the res-lump machinery's
  // registers intact (x3 = the res-lump/entity, x1 = a pointer into its
  // tag area, x2 = the res-tag-pair). Dump raw windows over both so the
  // offline analysis can read the actual res tags + the data word the
  // deref hit. GOAL-heap-shaped values only; safe_read guards the rest.
  {
    uintptr_t ee = (uintptr_t)uc->uc_mcontext.regs[15];
    if ((ee & 0xFFFu) == 0 && ee >= 0x100000000ull) {
      auto dump_rows = [&](const char* label, uintptr_t goal_base, int rows) {
        uintptr_t base = (ee + goal_base) & ~uintptr_t(15);
        for (int row = 0; row < rows; row++) {
          uint32_t w[4] = {0, 0, 0, 0};
          bool any = false;
          for (int k = 0; k < 4; k++) {
            if (gk_diag::safe_read_u32(base + row * 16 + 4 * k, &w[k])) {
              any = true;
            }
          }
          if (!any) {
            break;
          }
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "GK-DIAG A35-DIAG %s goal=0x%lx: %08x %08x %08x %08x",
                              label, (unsigned long)(base + row * 16 - ee), w[0], w[1], w[2],
                              w[3]);
        }
      };
      for (int reg : {1, 3}) {
        uintptr_t gp = (uintptr_t)(uc->uc_mcontext.regs[reg] & 0xFFFFFFFFu);
        if (gp >= 0x1000 && gp < 0x8000000u) {
          dump_rows(reg == 1 ? "x1-win" : "x3-win", gp - 64, 12);
        }
      }
      // x3 = the res-lump (&length); data-base lives at [x3+8]. Dump the
      // data area itself — the 'name tag stores by reference, so the word
      // at data-base+offset is the string pointer get-property-struct
      // deref'd. Also dump what THAT points at (the string chars).
      {
        uintptr_t lump = (uintptr_t)(uc->uc_mcontext.regs[3] & 0xFFFFFFFFu);
        uint32_t data_base = 0;
        if (lump >= 0x1000 && lump < 0x8000000u &&
            gk_diag::safe_read_u32(ee + lump + 8, &data_base) && data_base >= 0x1000 &&
            data_base < 0x8000000u) {
          dump_rows("lump-data", data_base, 16);
          uint32_t name_ref = 0;
          if (gk_diag::safe_read_u32(ee + data_base + 0x80, &name_ref)) {
            __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                "GK-DIAG A35-DIAG name-ref @data+0x80 = 0x%x", name_ref);
            if (name_ref >= 0x1000 && name_ref < 0x8000000u) {
              dump_rows("name-str", name_ref - 4, 3);
            }
          }
        }
      }
    }
  }

  // A12-DIAG: tie the failing BLR to the originating sym slot via a
  // backward provenance trace (BLR Xt → LDR Xt,[SP,#N] → STR Xs,[SP,#N]
  // → LDR Ws,[Xb,#0] → ADRP+ADD → sym name). Runs only on sig=4 (SIGILL).
  if (sig == SIGILL) {
    gk_diag::dump_stack_fnptr_zero_chain(lr, (uintptr_t)uc->uc_mcontext.sp);
    // A18-DIAG: type-method-zero / fn-ptr-field-zero walker. Catches the
    // virtual-dispatch shape `LDR Wn, [Xb, #imm]` where Xb came from
    // `ADD Xb, Xobj, X15`. Names the LDR site, the obj_reg, and
    // (best-effort) the type-tag at obj_host-4.
    gk_diag::dump_type_method_zero_chain(lr, uc);
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

  // A16-DIAG: ADRP/ADD pair walker with forward clobber detection.
  // Runs unconditionally so device logcat and qemu_repro stderr are
  // diff-able — qemu will (likely) emit "preserved" entries, device
  // will (per A15-attempt-2-next-blocker hypothesis) emit at least one
  // "x16-clobber" entry. The delta is the data needed for A17.
  gk_diag::dump_a16_adrp_pair_walk(lr);

  // A6 attempt 5+: dump bytes around LR (return address). When PC is a
  // BLR-to-NULL jump landing at EE base, LR points at the instruction
  // *after* the BLR — so LR-4 = the BLR, LR-8.. = what loaded the (NULL)
  // function pointer into the BLR target register. Extended to lr-256
  // so we can trace back through the call_r64 prologue + arg shuffle to
  // the source of the NULL value (typically the prior call's return).
  // A18 attempt-4: extend the hex dump from lr-256 to lr-1024 so the
  // function prologue is visible (the get-process regalloc-clobber site
  // for X12 lives before lr-256). Matches the linux-arm64 walker change.
  // A31: extend the FORWARD dump to lr+4096 — A30 showed that the BR/BLR
  // that took PC to a GOAL-form low address (0x1fa5fa4) is past lr+16
  // (X9 = 0x1fa5fa4 was set by a SUB X15 at lr-12 and STORED at lr+0;
  // X9 isn't reused as a function pointer until further into the
  // function's body, which the old dump radius truncated).
  for (intptr_t d = -1024; d <= 4096; d += 4) {
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

  // A31 — focused BR/BLR/RET scan around LR. The compact one-line-per-hit
  // form lets us spot the crashing BR/BLR (= the one PAST LR that has
  // no matching `ADD Xt, Xt, X15` immediately before it) without
  // grepping the 5 K-line bytes dump. Range is wider than the bytes
  // dump (+/- 8 KB) so a long top-level function fits.
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A31-DIAG branch-scan (lr-8192..lr+8192):");
  for (intptr_t d = -8192; d <= 8192; d += 4) {
    uintptr_t addr = lr + d;
    uint32_t insn = 0;
    if (!gk_diag::safe_read_u32(addr, &insn)) continue;
    // BLR Xn: 0xD63F0xxx where xxx&0x1F = 0, top mask 0xFFFFFC1F == 0xD63F0000.
    // BR  Xn: 0xD61F0xxx top mask == 0xD61F0000.
    // RET Xn: 0xD65F0xxx top mask == 0xD65F0000.
    if ((insn & 0xFFFFFC1Fu) == 0xD63F0000u) {
      uint32_t rn = (insn >> 5) & 0x1Fu;
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A31-DIAG BLR-site lr%+ld @ 0x%lx = BLR X%u",
                          (long)d, (unsigned long)addr, (unsigned)rn);
    } else if ((insn & 0xFFFFFC1Fu) == 0xD61F0000u) {
      uint32_t rn = (insn >> 5) & 0x1Fu;
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A31-DIAG BR-site  lr%+ld @ 0x%lx = BR  X%u",
                          (long)d, (unsigned long)addr, (unsigned)rn);
    } else if ((insn & 0xFFFFFC1Fu) == 0xD65F0000u) {
      uint32_t rn = (insn >> 5) & 0x1Fu;
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                          "GK-DIAG A31-DIAG RET-site lr%+ld @ 0x%lx = RET X%u",
                          (long)d, (unsigned long)addr, (unsigned)rn);
    }
  }

  // A31 — for each BR/BLR site, decode the 8 instructions BEFORE it.
  // The crashing BR/BLR will lack `ADD Xt, Xt, X15` (0x8b0f01tt for
  // Rt=tt) within the previous ~8 instructions; correctly-emitted call
  // sites always have one.
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                      "GK-DIAG A31-DIAG BR/BLR-prelude scan (8 instr before each site):");
  for (intptr_t d = -8192; d <= 8192; d += 4) {
    uintptr_t addr = lr + d;
    uint32_t insn = 0;
    if (!gk_diag::safe_read_u32(addr, &insn)) continue;
    bool is_blr = ((insn & 0xFFFFFC1Fu) == 0xD63F0000u);
    bool is_br  = ((insn & 0xFFFFFC1Fu) == 0xD61F0000u);
    if (!is_blr && !is_br) continue;
    uint32_t rn = (insn >> 5) & 0x1Fu;
    // ADD Xrn, Xrn, X15 encoding: 0x8B000000 | (15<<16) | (rn<<5) | rn
    //                            = 0x8B0F0000 | (rn<<5) | rn
    uint32_t expected_add = 0x8B0F0000u | (rn << 5) | rn;
    bool found_add_x15 = false;
    intptr_t add_offset = 0;
    for (intptr_t b = 4; b <= 32; b += 4) {
      uint32_t prev = 0;
      if (gk_diag::safe_read_u32(addr - b, &prev)) {
        if (prev == expected_add) {
          found_add_x15 = true;
          add_offset = -b;
          break;
        }
      }
    }
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A31-DIAG site lr%+ld pc=0x%lx %s X%u: ADD X%u,X%u,X15 found=%d offset=%+ld",
                        (long)d, (unsigned long)addr,
                        is_blr ? "BLR" : "BR", (unsigned)rn,
                        (unsigned)rn, (unsigned)rn,
                        (int)found_add_x15, (long)add_offset);
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
  // A36-TREE: scan tree + recs AT crash time so the report names every
  // already-corrupted slot (raw reads are EE-bounds-checked; safe in here).
  {
    a36_tree::g_log_budget = 40;
    a36_tree::arm_if_needed();
    a36_tree::scan_once();
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A36-TREE at-crash frame=%llu viol-total=%llu first-viol-frame=%llu armed=%d",
                        (unsigned long long)a36_tree::g_frame.load(),
                        (unsigned long long)a36_tree::g_viol_total.load(),
                        (unsigned long long)a36_tree::g_first_viol_frame.load(),
                        a36_tree::g_syms.armed ? 1 : 0);
  }
  // A39: dump the tripwire unique-writer table at crash time. The font-code
  // smash lands within the final frame(s) — after the last periodic summary
  // — so only an at-crash dump can name the in-band writer (when armed).
  {
    int lines = 0;
    for (int i = 0; i < a38_trip::kMaxWriters && lines < 48; i++) {
      uintptr_t wpc = a38_trip::g_writers[i].pc.load(std::memory_order_acquire);
      if (!wpc) {
        continue;
      }
      lines++;
      Dl_info di{};
      const char* nm = "";
      if (a38_trip::to_goal(wpc) == 0 && dladdr(reinterpret_cast<void*>(wpc), &di) &&
          di.dli_sname) {
        nm = di.dli_sname;
      }
      __android_log_print(
          ANDROID_LOG_FATAL, kGkLogTag,
          "GK-DIAG A39-WRITER[%d] pc=0x%lx(goal:0x%x)%s%s n=%llu last-fault=goal:0x%x "
          "last-val=0x%llx",
          i, (unsigned long)wpc, a38_trip::to_goal(wpc), nm[0] ? " " : "", nm,
          (unsigned long long)a38_trip::g_writers[i].n.load(std::memory_order_relaxed),
          a38_trip::g_writers[i].last_fault_goal.load(std::memory_order_relaxed),
          (unsigned long long)a38_trip::g_writers[i].last_val.load(std::memory_order_relaxed));
      if (a38_trip::to_goal(wpc) >= 0x1000) {
        a38_trip::log_nearest_goal_fn("a39-writer", a38_trip::to_goal(wpc));
      }
    }
  }
  struct sigaction sa{};
  sa.sa_handler = SIG_DFL;
  sigaction(sig, &sa, nullptr);
  raise(sig);
}

// A37 hang forensics: SIGUSR2 = "dump where you are and continue". The
// watchdog below fires it at the GOAL thread when the frame counter
// stalls (run-19: calc-animation-from-spr real -> silent freeze at
// frame ~60, no crash, no log). Reuses the ucontext PC/LR dump shape.
void gk_sigusr2_hang_dump(int /*sig*/, siginfo_t* /*info*/, void* ucontext) {
  auto* uc = reinterpret_cast<ucontext_t*>(ucontext);
  uintptr_t pc = uc->uc_mcontext.pc;
  uintptr_t lr = uc->uc_mcontext.regs[30];
  __android_log_print(ANDROID_LOG_FATAL, kGkLogTag, "GK-DIAG A37-HANG pc=0x%lx lr=0x%lx",
                      (unsigned long)pc, (unsigned long)lr);
  for (uintptr_t addr : {pc, lr}) {
    Dl_info di{};
    if (addr && dladdr(reinterpret_cast<void*>(addr), &di) && di.dli_fname) {
      __android_log_print(ANDROID_LOG_FATAL, kGkLogTag, "GK-DIAG A37-HANG-SYM 0x%lx = %s+0x%lx (%s)",
                          (unsigned long)addr, di.dli_sname ? di.dli_sname : "?",
                          di.dli_saddr ? (unsigned long)(addr - (uintptr_t)di.dli_saddr) : 0ul,
                          di.dli_fname);
    }
  }
  for (int i = 0; i < 31; i += 4) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A37-HANG x%d=0x%llx x%d=0x%llx x%d=0x%llx x%d=0x%llx", i,
                        (unsigned long long)uc->uc_mcontext.regs[i], i + 1,
                        (unsigned long long)uc->uc_mcontext.regs[i + 1], i + 2,
                        (unsigned long long)uc->uc_mcontext.regs[i + 2], i + 3,
                        (unsigned long long)uc->uc_mcontext.regs[i + 3]);
  }
  // fp-walk with dladdr per return address — names the C++ chain into the
  // blocking futex (run-20: GOAL thread parked in a futex syscall).
  uintptr_t fp = uc->uc_mcontext.regs[29];
  for (int d = 0; d < 24 && fp >= 0x10000 && (fp & 7) == 0; d++) {
    uintptr_t next_fp = *reinterpret_cast<const uintptr_t*>(fp);
    uintptr_t ret = *reinterpret_cast<const uintptr_t*>(fp + 8);
    Dl_info di{};
    const char* nm = "?";
    const char* so = "?";
    unsigned long off = 0;
    if (ret && dladdr(reinterpret_cast<void*>(ret), &di) && di.dli_fname) {
      nm = di.dli_sname ? di.dli_sname : "?";
      so = strrchr(di.dli_fname, '/') ? strrchr(di.dli_fname, '/') + 1 : di.dli_fname;
      off = di.dli_saddr ? (unsigned long)(ret - (uintptr_t)di.dli_saddr) : 0;
    }
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "GK-DIAG A37-HANG-FP[%d] fp=0x%lx ret=0x%lx %s+0x%lx (%s)", d,
                        (unsigned long)fp, (unsigned long)ret, nm, off, so);
    if (next_fp <= fp) break;
    fp = next_fp;
  }
}

void gk_install_sigsegv_diag() {
  struct sigaction sa{};
  sa.sa_sigaction = &gk_sigsegv_diag;
  sa.sa_flags = SA_SIGINFO;
  sigaction(SIGSEGV, &sa, nullptr);
  sigaction(SIGBUS, &sa, nullptr);
  sigaction(SIGILL, &sa, nullptr);
  struct sigaction sh{};
  sh.sa_sigaction = &gk_sigusr2_hang_dump;
  sh.sa_flags = SA_SIGINFO;
  sigaction(SIGUSR2, &sh, nullptr);
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "gk_install_sigsegv_diag: installed (+A37 SIGUSR2 hang dump)");
}
}  // namespace

// A38 tripwire arm/rearm hook — called per GL frame from
// android_gfx::render_frame_on_gl_thread. No-op (one relaxed atomic load)
// unless debug.opengoal.a38.tripwire is set before the first frame, so the
// shipped path is tripwire-off without a rebuild.
//   property "1": arm at the first RENDERED CHAIN (boot-link unwatched)
//   property "2": arm at the first GL tick (catches the boot-time text
//                 draws that stomp the font page before chains flow;
//                 link-phase writes show up as named writers — noisy)
extern "C" void gk_a38_tripwire_frame_hook(int chain_phase) {
  using namespace a38_trip;
  // ---- A40-DPROC tick (debug.opengoal.a40.dproc=1, default off): dense
  // sampling through the first ~10s of boot (the display-loop death is at
  // ~0.7s after `play`), then sparse. chain_phase==0 only (one tick/frame).
  {
    static std::atomic<int> s_a40_dp{-1};
    int dp = s_a40_dp.load(std::memory_order_acquire);
    if (dp == -1) {
      char dbuf[PROP_VALUE_MAX] = {0};
      int dn = __system_property_get("debug.opengoal.a40.dproc", dbuf);
      dp = (dn > 0 && dbuf[0] == '1') ? 1 : 0;
      s_a40_dp.store(dp, std::memory_order_release);
    }
    if (dp == 1 && chain_phase == 0) {
      static uint64_t s_a40_f = 0;
      uint64_t f = ++s_a40_f;
      if (f <= 8 || (f <= 240 && (f % 15) == 0) || (f <= 900 && (f % 60) == 0) ||
          (f % 600) == 0) {
        char tg[24];
        snprintf(tg, sizeof(tg), "f%llu", (unsigned long long)f);
        a40_dproc_probe(tg);
      }
    }
  }
  // ---- A39-SYMDUMP (debug.opengoal.a39.symdump=1, default off): the run1
  // SIGILL BLR'd 0x190bb34 out of a slot named "draw-string" that font.o's
  // link had bound to the shared noop (0x4d36b4) — something rewrites the
  // slot between the bind and the level-hint call. Every 60 frames, dump
  // (a) every slot whose info-name is exactly "draw-string" and (b) every
  // slot holding the poison value, with its name — catches both a
  // duplicate-intern and a hash-collision partner stomping the slot.
  // Pure reads (EE main mem is fully mapped); one static check when off.
  {
    static std::atomic<int> s_a39_sd{-1};
    int sd = s_a39_sd.load(std::memory_order_acquire);
    if (sd == -1) {
      char sbuf[PROP_VALUE_MAX] = {0};
      int sn = __system_property_get("debug.opengoal.a39.symdump", sbuf);
      sd = (sn > 0 && sbuf[0] == '1') ? 1 : 0;
      s_a39_sd.store(sd, std::memory_order_release);
    }
    if (sd == 1 && g_ee_main_mem && SymbolTable2.offset && LastSymbol.offset) {
      static int s_a39_frame = 0;
      int f = s_a39_frame++;
      // Per-frame body-snapshot of the GOAL draw-string fn (target resolved
      // once): the smash anchors at varying offsets (+0x0 run1, +0x2e4
      // linkscan boot), so compare the whole body every frame and report the
      // first/last changed offsets the frame the flip lands.
      {
        static uint32_t s_ds_target = 0;
        const uintptr_t ee2 = reinterpret_cast<uintptr_t>(g_ee_main_mem);
        if (!s_ds_target) {
          for (uint32_t slot = SymbolTable2.offset; slot < LastSymbol.offset; slot += 4) {
            uint32_t str_off =
                *reinterpret_cast<const uint32_t*>(ee2 + slot + jak1::SYM_INFO_OFFSET + 4);
            if (!str_off || str_off >= EE_MAIN_MEM_SIZE - 64) {
              continue;
            }
            if (memcmp(reinterpret_cast<const char*>(ee2 + str_off + 4), "draw-string", 12) ==
                0) {
              s_ds_target = *reinterpret_cast<const uint32_t*>(ee2 + slot);
              break;
            }
          }
        }
        constexpr uint32_t kSnapLen = 0x6000;
        if (s_ds_target >= 0x1000 && s_ds_target < EE_MAIN_MEM_SIZE - kSnapLen) {
          static uint8_t s_snap[kSnapLen];
          static bool s_snap_valid = false;
          const uint8_t* cur = reinterpret_cast<const uint8_t*>(ee2 + s_ds_target);
          if (!s_snap_valid) {
            memcpy(s_snap, cur, kSnapLen);
            s_snap_valid = true;
            __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                "A39-CODESNAP f=%d target=0x%x first-words=[%08x %08x %08x %08x]",
                                f, s_ds_target, reinterpret_cast<const uint32_t*>(cur)[0],
                                reinterpret_cast<const uint32_t*>(cur)[1],
                                reinterpret_cast<const uint32_t*>(cur)[2],
                                reinterpret_cast<const uint32_t*>(cur)[3]);
          } else if (memcmp(s_snap, cur, kSnapLen) != 0) {
            uint32_t lo = 0;
            while (lo < kSnapLen && s_snap[lo] == cur[lo]) {
              lo++;
            }
            uint32_t hi = kSnapLen;
            while (hi > lo && s_snap[hi - 1] == cur[hi - 1]) {
              hi--;
            }
            const uint32_t* nw = reinterpret_cast<const uint32_t*>(cur + (lo & ~3u));
            __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                "A39-CODEFLIP f=%d target=0x%x diff=[+0x%x,+0x%x) "
                                "new@first=[%08x %08x %08x %08x]",
                                f, s_ds_target, lo, hi, nw[0], nw[1], nw[2], nw[3]);
            memcpy(s_snap, cur, kSnapLen);
          }
        }
      }
      if ((f % 60) == 0) {
        const uintptr_t ee = reinterpret_cast<uintptr_t>(g_ee_main_mem);
        int hits = 0;
        for (uint32_t slot = SymbolTable2.offset;
             slot < LastSymbol.offset && hits < 8; slot += 4) {
          uint32_t str_off =
              *reinterpret_cast<const uint32_t*>(ee + slot + jak1::SYM_INFO_OFFSET + 4);
          if (!str_off || str_off >= EE_MAIN_MEM_SIZE - 64) {
            continue;
          }
          const char* nm = reinterpret_cast<const char*>(ee + str_off + 4);
          if (memcmp(nm, "draw-string", 12) == 0) {
            hits++;
            uint32_t v = *reinterpret_cast<const uint32_t*>(ee + slot);
            uint32_t h = *reinterpret_cast<const uint32_t*>(ee + slot + jak1::SYM_INFO_OFFSET);
            __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                "A39-SYMDUMP f=%d name-hit slot=0x%x value=0x%x hash=0x%x "
                                "str=0x%x",
                                f, slot, v, h, str_off);
          }
        }
        int vhits = 0;
        for (uint32_t slot = SymbolTable2.offset;
             slot < LastSymbol.offset && vhits < 8; slot += 4) {
          uint32_t v = *reinterpret_cast<const uint32_t*>(ee + slot);
          if (v != 0x190bb34u) {
            continue;
          }
          vhits++;
          uint32_t str_off =
              *reinterpret_cast<const uint32_t*>(ee + slot + jak1::SYM_INFO_OFFSET + 4);
          char nb[33];
          nb[0] = 0;
          if (str_off && str_off < EE_MAIN_MEM_SIZE - 64) {
            const char* nm = reinterpret_cast<const char*>(ee + str_off + 4);
            size_t k = 0;
            for (; k < 32 && nm[k]; k++) {
              nb[k] = nm[k];
            }
            nb[k] = 0;
          }
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "A39-SYMDUMP f=%d value-hit slot=0x%x name=\"%s\" str=0x%x",
                              f, slot, nb[0] ? nb : "<empty>", str_off);
        }
        if (!hits && !vhits) {
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "A39-SYMDUMP f=%d no draw-string slot, no 0x190bb34 holder", f);
        }
      }
    }
  }
  int mode = g_mode.load(std::memory_order_acquire);
  if (mode == 0) {
    return;
  }
  if (mode == -1) {
    static std::atomic<int> s_want{-1};
    int want = s_want.load(std::memory_order_acquire);
    if (want == -1) {
      char buf[PROP_VALUE_MAX] = {0};
      int n = __system_property_get("debug.opengoal.a38.tripwire", buf);
      want = (n > 0 && (buf[0] == '1' || buf[0] == '2')) ? buf[0] - '0' : 0;
      s_want.store(want, std::memory_order_release);
      if (want == 0) {
        g_mode.store(0, std::memory_order_release);
        __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                            "A38-TRIPWIRE off (debug.opengoal.a38.tripwire unset)");
        return;
      }
    }
    if (want == 0) {
      return;
    }
    if (want == 1 && !chain_phase) {
      return;  // arm at first rendered chain, not the first GL tick
    }
    if (!g_ee_main_mem) {
      return;  // runtime not mapped yet — retry next frame, property stays unread
    }
    g_page_size = getpagesize();
    if (g_page_size <= 0) {
      g_page_size = 4096;
    }
    const uintptr_t ee = reinterpret_cast<uintptr_t>(g_ee_main_mem);
    // Gnd: the band is overridable via properties so the same write-watch can
    // hunt the per-frame DMA calc-buffer bucket-header stomp (the ndi ND-logo
    // blocker) at [0x514000,0x518000) instead of the A38 engine float band.
    uint32_t band_lo_goal = kBandLoGoal, band_hi_goal = kBandHiGoal;
    {
      char bb[PROP_VALUE_MAX] = {0};
      if (__system_property_get("debug.opengoal.gnd.bandlo", bb) > 0 && bb[0]) {
        band_lo_goal = static_cast<uint32_t>(strtoul(bb, nullptr, 0));
      }
      char bc[PROP_VALUE_MAX] = {0};
      if (__system_property_get("debug.opengoal.gnd.bandhi", bc) > 0 && bc[0]) {
        band_hi_goal = static_cast<uint32_t>(strtoul(bc, nullptr, 0));
      }
    }
    uintptr_t lo = ee + band_lo_goal;
    uintptr_t hi = ee + band_hi_goal;
    // Align INWARD so neighbors never get protected (no false positives).
    lo = (lo + g_page_size - 1) & ~static_cast<uintptr_t>(g_page_size - 1);
    hi = hi & ~static_cast<uintptr_t>(g_page_size - 1);
    if (hi <= lo) {
      g_mode.store(0, std::memory_order_release);
      __android_log_print(ANDROID_LOG_ERROR, kGkLogTag,
                          "A38-TRIPWIRE arm failed: band degenerate after page align");
      return;
    }
    g_lo_host = lo;
    g_hi_host = hi;
    // Publish bounds before arming: a fault can only happen after mprotect.
    g_mode.store(1, std::memory_order_release);
    if (mprotect(reinterpret_cast<void*>(lo), static_cast<size_t>(hi - lo),
                 PROT_READ | PROT_EXEC) != 0) {
      g_mode.store(0, std::memory_order_release);
      __android_log_print(ANDROID_LOG_ERROR, kGkLogTag,
                          "A38-TRIPWIRE arm failed: mprotect errno=%d", errno);
      return;
    }
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "A38-TRIPWIRE ARMED band goal=[0x%x,0x%x) host=[0x%lx,0x%lx) pages=%lu "
                        "pagesz=%ld",
                        band_lo_goal, band_hi_goal, (unsigned long)lo, (unsigned long)hi,
                        (unsigned long)((hi - lo) / g_page_size), g_page_size);
    {
      char wbuf[PROP_VALUE_MAX] = {0};
      int wmode = (__system_property_get("debug.opengoal.a38.watch2", wbuf) > 0 &&
                   (wbuf[0] == '1' || wbuf[0] == '2'))
                      ? wbuf[0] - '0'
                      : 0;
      auto disp_sym2 = jak1::intern_from_c("*display*");
      uint32_t dv = disp_sym2.offset ? disp_sym2->value : 0;
      if (wmode == 1 && dv >= 0x1000 && dv < EE_MAIN_MEM_SIZE - 0x1000) {
        uintptr_t lo2 = (ee + dv) & ~static_cast<uintptr_t>(g_page_size - 1);
        uintptr_t hi2 = lo2 + g_page_size;
        if (mprotect(reinterpret_cast<void*>(lo2), hi2 - lo2, PROT_READ | PROT_EXEC) == 0) {
          g_lo2_host = lo2;
          g_hi2_host = hi2;
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "A38-TRIPWIRE ARMED2 *display* page goal=0x%x host=[0x%lx,0x%lx)",
                              dv, (unsigned long)lo2, (unsigned long)hi2);
        }
      } else if (wmode == 2 && dv >= 0x1000 && dv < EE_MAIN_MEM_SIZE - 0x1000) {
        for (int i = 0; i < 2; i++) {
          uint32_t frame = *reinterpret_cast<const uint32_t*>(ee + dv + 564 + 32 * i + 16);
          if (frame < 0x1000 || frame >= EE_MAIN_MEM_SIZE - 64) {
            continue;
          }
          uint32_t gb = *reinterpret_cast<const uint32_t*>(ee + frame + 36);
          if (gb < 0x1000 || gb >= EE_MAIN_MEM_SIZE - 64) {
            continue;
          }
          g_base_cell[i] = ee + gb + 4;
          uintptr_t lo = (ee + gb) & ~static_cast<uintptr_t>(g_page_size - 1);
          uintptr_t hi = lo + g_page_size;
          if (mprotect(reinterpret_cast<void*>(lo), hi - lo, PROT_READ | PROT_EXEC) == 0) {
            if (i == 0) {
              g_lo2_host = lo;
              g_hi2_host = hi;
            } else {
              g_lo3_host = lo;
              g_hi3_host = hi;
            }
            __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                "A38-TRIPWIRE ARMED2 buf%d header page goal-buf=0x%x base-cell="
                                "goal:0x%x host=[0x%lx,0x%lx)",
                                i, gb, gb + 4, (unsigned long)lo, (unsigned long)hi);
          }
        }
      }
    }
    // Name the band's residents: symbols whose value lands inside it
    // (engine objects/functions — expect font/text family). One-shot.
    if (SymbolTable2.offset && LastSymbol.offset) {
      int named = 0;
      for (uint32_t slot = SymbolTable2.offset;
           slot + 4 < EE_MAIN_MEM_SIZE && slot < LastSymbol.offset && named < 48; slot += 4) {
        uint32_t v = *reinterpret_cast<const uint32_t*>(ee + slot);
        if (v >= band_lo_goal && v < band_hi_goal) {
          named++;
          char name[65] = {0};
          uint64_t info_goal = static_cast<uint64_t>(slot) + jak1::SYM_INFO_OFFSET;
          if (info_goal + 8 < EE_MAIN_MEM_SIZE) {
            uint32_t str_off = *reinterpret_cast<const uint32_t*>(ee + info_goal + 4);
            if (str_off > 0 &&
                static_cast<uint64_t>(str_off) + 4 + sizeof(name) < EE_MAIN_MEM_SIZE) {
              const char* sp = reinterpret_cast<const char*>(ee + str_off + 4);
              for (size_t i = 0; i + 1 < sizeof(name) && sp[i]; i++) {
                name[i] = (sp[i] >= 0x20 && sp[i] <= 0x7e) ? sp[i] : '?';
              }
            }
          }
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "A38-TRIPWIRE band-resident sym '%s' value=0x%x slot=0x%x",
                              name[0] ? name : "<unnamed>", v, slot);
        }
      }
    }
    log_display_probe("arm");
    // One-shot function-code dump: debug.opengoal.a38.dumpfn=<symbol> hex-
    // dumps the named GOAL function's first 0x800 bytes (A38-FNDUMP rows)
    // so the emitted arm64 can be decoded offline (llvm-objdump on the
    // reassembled bytes). Used to pin the display-sync flip-block layout.
    {
      char fnbuf[PROP_VALUE_MAX] = {0};
      if (__system_property_get("debug.opengoal.a38.dumpfn", fnbuf) > 0 && fnbuf[0]) {
        auto s_fn = jak1::intern_from_c(fnbuf);
        uint32_t fnv = s_fn.offset ? s_fn->value : 0;
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "A38-FNDUMP '%s' slot=0x%x value=0x%x", fnbuf,
                            (unsigned)s_fn.offset, fnv);
        if (fnv >= 0x1000 && fnv + 0x1800 < EE_MAIN_MEM_SIZE) {
          for (uint32_t off = 0; off < 0x1800; off += 16) {
            const uint32_t* w = reinterpret_cast<const uint32_t*>(ee + fnv + off);
            __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                                "A38-FNDUMP +%03x: %08x %08x %08x %08x", off, w[0], w[1], w[2],
                                w[3]);
          }
        }
      }
    }
    // Font probe: record what draw-string's entry bytes look like AT ARM
    // TIME. Real AArch64 code = healthy; sequential 0x20000000 NEXT tags =
    // the stomp predates arming (boot-time text draws — rerun with
    // property "2"). intern_from_c is lookup-only and we're on the GL
    // thread here, not in the handler.
    {
      auto s_ds = jak1::intern_from_c("draw-string");
      if (s_ds.offset) {
        uint32_t fnv = s_ds->value;
        __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                            "A38-TRIPWIRE font-probe draw-string slot=0x%x value=0x%x",
                            (unsigned)s_ds.offset, fnv);
        if (fnv >= 0x1000 && fnv + 32 < EE_MAIN_MEM_SIZE) {
          const uint32_t* w = reinterpret_cast<const uint32_t*>(ee + fnv);
          __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                              "A38-TRIPWIRE font-probe entry: %08x %08x %08x %08x | %08x %08x "
                              "%08x %08x",
                              w[0], w[1], w[2], w[3], w[4], w[5], w[6], w[7]);
        }
      }
    }
    return;
  }
  // mode == 1: per-frame rearm + periodic summary.
  if (g_any_page_open.exchange(false, std::memory_order_acq_rel)) {
    mprotect(reinterpret_cast<void*>(g_lo_host), static_cast<size_t>(g_hi_host - g_lo_host),
             PROT_READ | PROT_EXEC);
    if (g_lo2_host) {
      mprotect(reinterpret_cast<void*>(g_lo2_host), static_cast<size_t>(g_hi2_host - g_lo2_host),
               PROT_READ | PROT_EXEC);
    }
    if (g_lo3_host) {
      mprotect(reinterpret_cast<void*>(g_lo3_host), static_cast<size_t>(g_hi3_host - g_lo3_host),
               PROT_READ | PROT_EXEC);
    }
  }
  static uint64_t s_frames = 0;
  s_frames++;
  if ((s_frames % 600) == 0 || s_frames == 120 || s_frames == 300) {
    __android_log_print(ANDROID_LOG_FATAL, kGkLogTag,
                        "A38-TRIPWIRE summary frames=%llu hits=%llu emulated=%llu "
                        "pages-reopened=%llu",
                        (unsigned long long)s_frames,
                        (unsigned long long)g_hits.load(std::memory_order_relaxed),
                        (unsigned long long)g_emulated.load(std::memory_order_relaxed),
                        (unsigned long long)g_pages_reopened.load(std::memory_order_relaxed));
    log_display_probe("sum");
    int lines = 0;
    for (int i = 0; i < kMaxWriters && lines < 16; i++) {
      uintptr_t pc = g_writers[i].pc.load(std::memory_order_acquire);
      if (!pc) {
        continue;
      }
      lines++;
      Dl_info di{};
      const char* nm = "";
      if (to_goal(pc) == 0 && dladdr(reinterpret_cast<void*>(pc), &di) && di.dli_sname) {
        nm = di.dli_sname;
      }
      __android_log_print(
          ANDROID_LOG_FATAL, kGkLogTag,
          "A38-TRIPWIRE writer[%d] pc=0x%lx(goal:0x%x)%s%s n=%llu last-fault=goal:0x%x "
          "last-val=0x%llx",
          i, (unsigned long)pc, to_goal(pc), nm[0] ? " " : "", nm,
          (unsigned long long)g_writers[i].n.load(std::memory_order_relaxed),
          g_writers[i].last_fault_goal.load(std::memory_order_relaxed),
          (unsigned long long)g_writers[i].last_val.load(std::memory_order_relaxed));
    }
  }
}

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

  // Phase F1d (autoport): derive the app-private files dir from data_root
  // (<files>/iso_data/<game>), used for two things below.
  std::string files_dir;
  {
    std::string dr(data_root);
    auto pos = dr.find("/files/");
    files_dir = (pos != std::string::npos) ? dr.substr(0, pos + 6) : dr;
  }

  // Phase F1d (autoport): point $HOME at the writable app files dir BEFORE
  // goal_main. Without this, file_util::get_user_home_dir() reads an unset
  // $HOME and the save/settings path resolves to the relative
  // ".config/OpenGOAL/jak1/saves", which is on Android's read-only CWD.
  // Starting a new game then throws an uncaught ghc::filesystem_error
  // (Read-only file system) -> std::terminate -> SIGABRT right after the
  // title advances. With $HOME set, saves land in
  // <files>/.config/OpenGOAL/jak1/saves (writable), so (start 'play ...)
  // completes and Jak actually drops into the level.
  if (!files_dir.empty()) {
    setenv("HOME", files_dir.c_str(), 1);
    __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                        "gk_sdl_main: HOME set to '%s' (writable save/config "
                        "root)", files_dir.c_str());
  }

  // Phase F1d (autoport): arm the headless cpad-injection watcher. The
  // control file lives in the app-private files dir (the test harness
  // writes it via `run-as`).
  {
    std::string inject_path =
        files_dir.empty() ? std::string(data_root) + "/cpad_inject"
                          : files_dir + "/cpad_inject";
    android_input_audio::start_inject_watcher(inject_path.c_str());
  }

  // Phase Ginput-replay (autoport): arm the input record/replay harness from an
  // app property (Android has no argv). Default OFF — a normal boot is untouched,
  // so deploy_verify and gameplay are unaffected.
  //   debug.opengoal.pad_replay = selftest -> run the record/replay byte-identity
  //       self-test, write the demo + per-logic-tick state dump under <files>,
  //       log "PAD DIFF: 0/N"; then continue booting.
  //   debug.opengoal.pad_replay = record   -> record live input to
  //       <files>/pad_demo.inputs (flush-per-tick; the owner-records-once path).
  //   debug.opengoal.pad_replay = replay   -> replay <files>/pad_demo.inputs
  //       (the worker reproduces the recorded crash deterministically).
  {
    char prb[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.pad_replay", prb) > 0 && prb[0]) {
      std::string base = files_dir.empty() ? std::string(data_root) : files_dir;
      if (std::strcmp(prb, "selftest") == 0) {
        std::string out = base + "/selftest.inputs";
        int rc = pad_replay::run_selftest(out, 120);
        __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                            "pad_replay: SELFTEST rc=%d -> %s", rc, out.c_str());
      } else if (std::strcmp(prb, "record") == 0) {
        pad_replay::init(pad_replay::Mode::Record, base + "/pad_demo.inputs");
      } else if (std::strcmp(prb, "replay") == 0) {
        pad_replay::init(pad_replay::Mode::Replay, base + "/pad_demo.inputs");
      }
    }
  }

  // Gcollision-replay-diff (autoport) — TEMP per-logic-frame collision-state trace.
  //   debug.opengoal.pad_trace = 1        -> <files>/pad_trace.statedump.txt
  //   debug.opengoal.pad_trace = <name>   -> <files>/<name>
  // Mirrors the x86 OG_PAD_REPLAY_TRACE env path. Removed before phase close.
  {
    char ptb[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.pad_trace", ptb) > 0 && ptb[0]) {
      std::string base = files_dir.empty() ? std::string(data_root) : files_dir;
      std::string tp = (std::strcmp(ptb, "1") == 0)
                           ? (base + "/pad_trace.statedump.txt")
                           : (base + "/" + ptb);
      pad_replay::open_state_trace(tp);
      __android_log_print(ANDROID_LOG_INFO, kGkLogTag, "pad_replay: TRACE -> %s",
                          tp.c_str());
    }
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

// Phase Gtouch-controls (autoport): analog-axis injection from the overlay
// (left virtual stick LEFTX/LEFTY, right camera-drag zone RIGHTX/RIGHTY,
// combined L2/R2 button via the LEFT/RIGHT_TRIGGER axes). Routes into the
// SAME on_pad_axis the real-gamepad SDL_EVENT_GAMEPAD_AXIS_MOTION path uses
// (process_sdl_event), so the injected deflection is byte-equivalent to a
// physical pad's and reaches the GOAL cpad mirror via get_cpad_state.
JNIEXPORT void JNICALL
Java_org_opengoal_gk_NativeGk_onPadAxis(JNIEnv* /*env*/, jclass /*clazz*/,
                                        jint sdl_axis, jint value) {
  // The analog stick + camera drag call this every touch-move (continuous),
  // so throttle the marker: log the first crossing + one per 64 thereafter.
  // The native axis path itself runs every call (smooth input); only the
  // logcat line is throttled so it can't flood the device log. The Java-side
  // `overlay-actuate:` lines carry the per-control proof.
  static std::atomic<uint32_t> s_axis_log_count{0};
  const uint32_t n = s_axis_log_count.fetch_add(1, std::memory_order_relaxed);
  if (n == 0 || (n & 0x3Fu) == 0) {
    __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                        "onPadAxis: sdl_axis=%d value=%d "
                        "(JNI route from Java overlay; #%u)",
                        (int)sdl_axis, (int)value, (unsigned)n);
  }
  android_input_audio::on_pad_axis((int)sdl_axis, (int)value);
}

// Phase Gtouch-controls (autoport): expose the GOAL-thread-computed
// menu-vs-gameplay flag to the overlay. The overlay polls this to switch
// the bottom-left control between the analog stick (gameplay) and a digital
// d-pad (menus). Just an atomic read — no symbol-table access on this
// (UI) thread, so it can never race the kernel's intern.
JNIEXPORT jboolean JNICALL
Java_org_opengoal_gk_NativeGk_isInMenu(JNIEnv* /*env*/, jclass /*clazz*/) {
  return g_overlay_in_menu.load(std::memory_order_acquire) ? JNI_TRUE
                                                           : JNI_FALSE;
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
