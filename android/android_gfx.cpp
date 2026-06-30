// Phase A35 (autoport): Android graphics pipeline glue. See android_gfx.h.

#include "android_gfx.h"

#include <android/log.h>
#include <dlfcn.h>
#include <pthread.h>
#include <sys/system_properties.h>

#include <chrono>
#include <condition_variable>
#include <functional>
#include <memory>
#include <mutex>
#include <thread>

#include <SDL3/SDL.h>

#include "common/dma/dma_copy.h"
#include "common/goal_constants.h"
#include "common/log/log.h"
#include "common/util/FileUtil.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/loader/Loader.h"
#include "game/graphics/texture/TexturePool.h"
#include "game/runtime.h"

#include "android_opengl_renderer.h"

#include "third-party/glad/include/glad/glad.h"

// A38 float-spray tripwire arm/rearm (gk_android_main.cpp). One relaxed
// atomic load per frame when the debug property is unset. chain_phase=1
// when called with a rendered chain (the property-"1" arm point).
extern "C" void gk_a38_tripwire_frame_hook(int chain_phase);
// Gcine-pose joint-sanity tripwire: per-frame bucket of cspace joint skips /
// bad bone matrices (defined in game/mips2c/jak1_functions/joint.cpp).
extern "C" void gpose_joint_frame_tick(unsigned long long frame_idx);

// Gmatch: known-good snapshot of the GOAL kernel asm-func return-from-thread-dead
// (the per-process return trampoline at GOAL 0x18aee4). Published here by the
// render-thread content canary (below) and CONSUMED by gk_android_main.cpp's
// SIGILL handler, which repairs-and-resumes when the kernel-dispatch thread RETs
// into a (re-)stomped trampoline — a race the per-frame canary alone cannot win.
// Set exactly once (malloc'd, never freed); a plain pointer read in the handler
// is safe (null until armed, valid forever after).
extern "C" {
unsigned char* g_gmatch_rftd_good = nullptr;     // known-good bytes, or null
// Widened from the original return-from-thread-dead point (0x18aee4/0x80) to the
// whole kernel asm-func code band [0x18ae84, 0x1912b4): the merc blend-shape
// stomp's residual kernel-code hits scatter across this region (observed
// victims: 0x18ae84 return-from-thread, 0x191210/0x191218/0x191240
// process::deactivate). The bounded blerc emulate (common/dma/dma.h) stops the
// PRIMARY high-heap scatter; this band canary + the gk_android_main.cpp SIGILL
// resume handler (which derives its window from these two constants) catch any
// residual kernel-code stomp so the cutscene plays through. Pure code region, so
// snapshot+restore-each-frame is safe. x86 unaffected (#ifdef __aarch64__).
unsigned int g_gmatch_rftd_goal = 0x18ae84;       // GOAL addr of protected region
unsigned int g_gmatch_rftd_len = 0x6430;          // length in bytes -> [0x18ae84,0x1912b4)
}

// Gcine-camfov: the Gintro DMA chain-walk dump (GINTRO-CHAINWALK / GND-PRECOPY-RAW)
// is a per-frame ~14-line render-thread debug flood that has outlived its purpose.
// It runs latency-heavy __android_log_print calls every frame during the new-game
// intro's complex DMA chains — exactly the window where the (separate) blend-shape
// joint OOB stomp races the render thread — so it widens that race AND floods long
// captures. Gate it OFF by default; re-arm with `setprop debug.opengoal.gintro.dbg 1`.
static bool gintro_chainwalk_dbg() {
  static const bool s_on = [] {
    char buf[PROP_VALUE_MAX] = {0};
    return __system_property_get("debug.opengoal.gintro.dbg", buf) > 0 && buf[0] == '1';
  }();
  return s_on;
}

#if defined(__aarch64__) && defined(__ANDROID__)
// GND-HWWP: one-shot arm of the arm64 HARDWARE data watchpoint on the two
// global-buf base fields (gk_android_main.cpp). Called from the GOAL thread.
extern "C" void gnd_hwwp_arm_once();
#endif

namespace android_gfx {
namespace {
constexpr const char* kLogTag = "opengoal-gk";

struct AndroidGfxData {
  // ONE mutex for the whole game-thread<->GL-thread handshake. A37: the
  // previous split (sync_mutex for vsync/post_swap_tick, dma_mutex for
  // send_chain/sync_path) had sync_cv waited under dma_mutex in
  // sync_path() but notified under sync_mutex — a condition_variable
  // used with two different mutexes is UB and loses wakeups; on-device
  // the GOAL thread parked forever in sync_path's cond_wait the moment
  // frame contents got heavier (real mips2c joints), and the desynced
  // frame pacing corrupted the in-flight chain. One mutex, two cvs.
  std::mutex dma_mutex;
  std::condition_variable sync_cv;
  u64 frame_idx = 0;
  u64 frame_idx_of_input_data = 0;

  // dma chain hand-off (same mutex)
  std::condition_variable dma_cv;
  bool has_data_to_render = false;
  const void* chain_data = nullptr;
  u32 chain_offset = 0;
  // Gintro: set once the first chain has been copied, so a corrupt frame can
  // re-present the last good copy (chain_data/chain_offset persist between
  // frames — they point into dma_copier's buffer, overwritten only by run()).
  bool ever_copied = false;

  // A42: upstream's run_dma_copy mode, always-on for Android. Zero-copy
  // hand-off let concurrent writers (run-3: bucket tags walking to 0x0
  // mid-frame, 40 A37-BUCKET-MALFORMED skips, then a renderer drain hang +
  // OOM kill) mutate the chain under the GL thread. The copy is taken on
  // the game thread inside send_chain — the builder is idle there, so the
  // tag stream is complete and stable — and is immutable afterwards, which
  // makes the GL-side A37 probe decisive instead of racy.
  FixedChunkDmaCopier dma_copier{EE_MAIN_MEM_SIZE};

  std::shared_ptr<TexturePool> texture_pool;
  std::shared_ptr<Loader> loader;
  std::unique_ptr<AndroidOpenGLRenderer> renderer;

  std::atomic<float> pmode_alp{1.f};
  std::atomic<u64> frames_rendered{0};
};

AndroidGfxData* g_data = nullptr;
void flush_pending_texture_calls_on_ready();  // A41 queue, defined below
std::atomic<bool> g_renderer_ready{false};
// A42: the IOP vblank hook (desktop gfx.cpp's file-static vsync_callback).
// Set once by make_iop_thread (EE thread, during InitMachine — strictly
// before the dispatcher thread that calls vsync() exists), invoked from
// vsync() on the dispatcher thread. Same lock-free shape as desktop.
std::function<void()> g_vsync_callback;
std::atomic<u32> g_chains_received{0};
std::atomic<u32> g_chains_dropped_pre_init{0};
std::atomic<int> g_window_w{0};
std::atomic<int> g_window_h{0};
std::atomic<int> g_refresh_rate{0};

}  // namespace

// ===== Gspeed: engine game-clock driven by the renderer's stable vblank grid ==
// Published by the GL render loop (android_renderer.cpp) once per swap and read
// by the EE frame-clock timer (a35_read_ee_timer in gk_android_main.cpp). It is
// a monotonically-increasing count of EE timer ticks (the unit GOAL's
// (timer-count #x10000800) consumes; ~585938 ticks/s, *ticks-per-frame*==9765)
// that advances by EXACTLY (step - 0.5) frame-budgets per rendered frame, where
// `step` is the renderer's current stable vblanks-per-frame (1 at 60 fps, 2 at
// 30 fps). The half-budget bias makes the GOAL formula
//   time-ratio = floor(timer_count / 9765) + 1   (clamp <1.3 -> 1.0)
// resolve a `step`-frame to time-ratio == step (step=1 -> 0.5 budgets -> clamp
// -> 1; step=2 -> 1.5 budgets -> floor 1 +1 -> 2), with NO fractional jitter and
// NO off-by-one. Game advances `step` integer timesteps per real `step` vblanks
// == a constant real-time 60 Hz, stable regardless of render load. Zero before
// the renderer publishes (boot): the timer then falls back to wall-clock.
std::atomic<unsigned long long> g_gspeed_clock_ticks{0};
std::atomic<bool> g_gspeed_clock_active{false};

bool get_window_size(int* w, int* h) {
  int ww = g_window_w.load();
  int hh = g_window_h.load();
  if (ww <= 0 || hh <= 0) {
    return false;
  }
  if (w) {
    *w = ww;
  }
  if (h) {
    *h = hh;
  }
  return true;
}

int get_refresh_rate() {
  return g_refresh_rate.load();
}

bool init_renderer_on_gl_thread(int win_w, int win_h) {
  if (g_renderer_ready.load()) {
    return true;
  }

  // Resolve every GL entry point through SDL (EGL/dlsym on Android). The
  // desktop renderer code calls gl* through glad's pointers; GLES 3.2
  // provides the full surface the ported subset uses (verified: no
  // glPolygonMode/glLogicOp/glClipControl on Android paths).
  if (!gladLoadGLLoader((GLADloadproc)SDL_GL_GetProcAddress)) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "A35-RENDER gladLoadGLLoader failed — no GL entry points; "
                        "staying on clear/swap loop");
    return false;
  }
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "A35-RENDER glad loaded GL entry points via SDL_GL_GetProcAddress "
                      "(GL_VERSION=%s)",
                      (const char*)glGetString(GL_VERSION));

  // A36: the desktop-profile glad parses "OpenGL ES 3.2" as version 3.2 and
  // skips its GL_VERSION_4_1 load list — which is where the ES2-core
  // functions (glClearDepthf, glDepthRangef, ...) live in desktop GL. They
  // stay NULL and the first call is a BLR-to-0 (run-19/20: SIGSEGV pc=0 from
  // android_renderer_run's clear). Resolve that family directly; dlsym
  // fallback for drivers whose eglGetProcAddress skips core names.
  {
    auto resolve = [](const char* name) -> void* {
      void* p = (void*)SDL_GL_GetProcAddress(name);
      if (!p) {
        static void* libgles = dlopen("libGLESv2.so", RTLD_NOW | RTLD_GLOBAL);
        if (libgles) {
          p = dlsym(libgles, name);
        }
      }
      return p;
    };
    if (!glad_glClearDepthf) {
      glad_glClearDepthf = (PFNGLCLEARDEPTHFPROC)resolve("glClearDepthf");
    }
    if (!glad_glDepthRangef) {
      glad_glDepthRangef = (PFNGLDEPTHRANGEFPROC)resolve("glDepthRangef");
    }
    if (!glad_glGetShaderPrecisionFormat) {
      glad_glGetShaderPrecisionFormat =
          (PFNGLGETSHADERPRECISIONFORMATPROC)resolve("glGetShaderPrecisionFormat");
    }
    // F1a: same disease, one version line UP — glad gates
    // glVertexAttribDivisor behind its GL_VERSION_3_3 list, above the parsed
    // "ES 3.2", but it is ES 3.0 CORE and the driver exports it. The sprite
    // distort instancing path BLR'd to 0 through the NULL slot
    // (run-2 GK-DIAG: pc=0 lr in Sprite3::opengl_setup_distort+0x52c,
    // GOT slot = glad_glVertexAttribDivisor).
    if (!glad_glVertexAttribDivisor) {
      glad_glVertexAttribDivisor = (PFNGLVERTEXATTRIBDIVISORPROC)resolve("glVertexAttribDivisor");
    }
    // F1a: KHR_debug is core in ES 3.2 — let the driver narrate its own
    // errors (runs 4-6 crash INSIDE libGLESv2_adreno on the first village
    // merc draw with apparently-valid bound state; the message stream is
    // the driver's side of the story). Synchronous so the message lands
    // before the faulting call returns. Capped to keep logcat sane.
    {
      auto p_cb = (void (*)(void (*)(GLenum, GLenum, GLuint, GLenum, GLsizei, const GLchar*,
                                     const void*),
                            const void*))resolve("glDebugMessageCallback");
      if (p_cb) {
        glEnable(0x92E0 /* GL_DEBUG_OUTPUT */);
        glEnable(0x8242 /* GL_DEBUG_OUTPUT_SYNCHRONOUS */);
        p_cb(
            [](GLenum source, GLenum type, GLuint id, GLenum severity, GLsizei,
               const GLchar* message, const void*) {
              static int s_count = 0;
              if (s_count++ < 200) {
                __android_log_print(ANDROID_LOG_WARN, kLogTag,
                                    "F1A-GLDBG src=0x%x type=0x%x id=%u sev=0x%x %s", source, type,
                                    id, severity, message ? message : "");
              }
            },
            nullptr);
        __android_log_print(ANDROID_LOG_INFO, kLogTag, "F1A-GLDBG KHR_debug callback armed");
      }
    }
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                        "A36-RENDER GL4.1-list ES core fns resolved: glClearDepthf=%p "
                        "glDepthRangef=%p",
                        (void*)glad_glClearDepthf, (void*)glad_glDepthRangef);
    if (!glad_glClearDepthf || !glad_glDepthRangef) {
      __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                          "A36-RENDER missing core GLES entry points after fallback");
      return false;
    }
  }

  g_window_w.store(win_w);
  g_window_h.store(win_h);
  {
    auto display = SDL_GetPrimaryDisplay();
    const SDL_DisplayMode* mode = display ? SDL_GetCurrentDisplayMode(display) : nullptr;
    g_refresh_rate.store(mode && mode->refresh_rate > 0 ? (int)mode->refresh_rate : 60);
  }

  auto* data = new AndroidGfxData();
  data->texture_pool = std::make_shared<TexturePool>(GameVersion::Jak1);

  // fr3 dir: <project>/out/jak1/fr3 — LoaderActivity extracts the APK's
  // fr3/ assets (GAME.fr3 + intro/title) there. Loader handles a missing
  // level file by logging; a missing GAME.fr3 would fail load_common, so
  // probe first and run textureless (placeholders) instead of aborting.
  auto fr3_dir = file_util::get_jak_project_dir() / "out" / "jak1" / "fr3";
  if (fs::exists(fr3_dir / "GAME.fr3")) {
    data->loader = std::make_shared<Loader>(fr3_dir, jak1::LEVEL_TOTAL);
  } else {
    __android_log_print(ANDROID_LOG_WARN, kLogTag,
                        "A35-RENDER %s/GAME.fr3 missing — common textures will be "
                        "checkerboard placeholders",
                        fr3_dir.string().c_str());
  }

  data->renderer = std::make_unique<AndroidOpenGLRenderer>(data->texture_pool, data->loader);

  g_data = data;
  g_renderer_ready.store(true);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "A35-RENDER renderer ready (window %dx%d) — game DMA chains will "
                      "now be consumed",
                      win_w, win_h);
  // A41: land the boot-time tpage uploads + font relocates that were
  // queued while the renderer was coming up (see the queue note above).
  flush_pending_texture_calls_on_ready();
  return true;
}

bool renderer_ready() {
  return g_renderer_ready.load();
}

bool render_frame_on_gl_thread(int win_w, int win_h) {
  if (!g_renderer_ready.load()) {
    return false;
  }
  auto* d = g_data;

  g_window_w.store(win_w);
  g_window_h.store(win_h);

  bool got_chain = false;
  {
    std::unique_lock<std::mutex> lock(d->dma_mutex);
    got_chain = d->dma_cv.wait_for(lock, std::chrono::milliseconds(40),
                                   [=] { return d->has_data_to_render; });
  }

  // A37 chain validator: a malformed (cyclic / never-ending) chain makes
  // bucket renderers spin forever in read_and_advance (run-23/24/25: GL
  // thread stuck in SkyRenderer, GOAL parked in sync_path, app frozen).
  // Walk the whole chain with a step cap first; on cap, log a tag window
  // and SKIP the frame — the run keeps producing evidence and pacing.
  if (got_chain) {
    DmaFollower probe(d->chain_data, d->chain_offset);
    constexpr int kMaxSteps = 400000;
    int steps = 0;
    u32 last_offsets[8] = {0};
    while (!probe.ended() && steps < kMaxSteps) {
      last_offsets[steps & 7] = probe.current_tag_offset();
      probe.read_and_advance();
      steps++;
    }
    if (!probe.ended()) {
      static u32 s_loops_logged = 0;
      if (s_loops_logged < 8) {
        s_loops_logged++;
        __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                            "A37-CHAIN-LOOP frame chain did not end after %d steps; recent tag "
                            "offsets: 0x%x 0x%x 0x%x 0x%x 0x%x 0x%x 0x%x 0x%x",
                            kMaxSteps, last_offsets[(steps + 0) & 7], last_offsets[(steps + 1) & 7],
                            last_offsets[(steps + 2) & 7], last_offsets[(steps + 3) & 7],
                            last_offsets[(steps + 4) & 7], last_offsets[(steps + 5) & 7],
                            last_offsets[(steps + 6) & 7], last_offsets[(steps + 7) & 7]);
        for (int k = 0; k < 4; k++) {
          u32 off = last_offsets[(steps + 7 - k) & 7];
          u64 tag = 0, tag2 = 0;
          memcpy(&tag, (const u8*)d->chain_data + off, 8);
          memcpy(&tag2, (const u8*)d->chain_data + off + 8, 8);
          __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                              "A37-CHAIN-LOOP tag@0x%x = %016llx %016llx", off,
                              (unsigned long long)tag, (unsigned long long)tag2);
        }
      }
      std::unique_lock<std::mutex> lock(d->dma_mutex);
      d->has_data_to_render = false;
      d->sync_cv.notify_all();
      return false;
    }
  }

  // A38: property "2" arms at the first GL tick (boot-time writers).
  gk_a38_tripwire_frame_hook(0);

  if (got_chain) {
    // A38: arm (first chain, property-gated) / rearm (per frame) the
    // float-spray tripwire on the engine-object band. Arming at the first
    // RENDERED chain (not the first GL tick) keeps the boot-link phase
    // unwatched — DGO linking writes the band legitimately.
    gk_a38_tripwire_frame_hook(1);
    {
      std::unique_lock<std::mutex> lock(d->dma_mutex);
      d->frame_idx_of_input_data = d->frame_idx;
    }
    AndroidRenderOptions options;
    options.game_res_w = Gfx::g_global_settings.game_res_w;
    options.game_res_h = Gfx::g_global_settings.game_res_h;
    if (options.game_res_w <= 0 || options.game_res_h <= 0) {
      options.game_res_w = 640;
      options.game_res_h = 480;
    }
    options.window_fb_w = win_w;
    options.window_fb_h = win_h;
    // lbox dims come from GOAL via pc-set-letterbox; left at defaults they
    // letterbox the 640x480 game into the window center. If GOAL never set
    // them, scale the draw region to fit the window while keeping aspect.
    options.draw_region_w = Gfx::g_global_settings.lbox_w;
    options.draw_region_h = Gfx::g_global_settings.lbox_h;
    if (options.draw_region_w <= 640 && options.draw_region_h <= 480 && win_h > 0) {
      // GOAL still on defaults — fit 4:3 into the window honestly.
      int fit_h = win_h;
      int fit_w = (fit_h * 4) / 3;
      if (fit_w > win_w) {
        fit_w = win_w;
        fit_h = (fit_w * 3) / 4;
      }
      options.draw_region_w = fit_w;
      options.draw_region_h = fit_h;
    }
    options.pmode_alp_register = d->pmode_alp.load();

    d->renderer->render(DmaFollower(d->chain_data, d->chain_offset), options);

    const auto& st = d->renderer->stats();
    gpose_joint_frame_tick((unsigned long long)st.frame_idx);

    // === Gcine-crash3: process::deactivate code-stomp guard (the fix, arm64) ====
    // In the new-game intro's Gol/Maia portal scene the arm64 envmap merc draw
    // (l0-pris-merc bucket, the villains spawned with 'blend-shape) writes ~0x40
    // bytes -- a miscalculated base in the render/DMA path -- over the GOAL kernel
    // `process::deactivate` method's code in KERNEL.CGO at GOAL 0x191260. The next
    // ORDINARY process deactivation then takes gkernel.gc:1946's `b.ne` into the
    // corrupted bytes (GOAL 0x191278) and executes a non-instruction -> SIGILL
    // (sig 4) -> the app dies and Android returns to the launcher. Confirmed a
    // RUNTIME stomp: the APK's KERNEL.CGO is byte-identical to out/jak1-arm64/iso
    // yet device memory at 0x191260 holds host/native pointers + floats, not
    // deactivate's instructions. The write is a DMA/SIMD-class store the A38
    // mprotect tripwire cannot see (a content canary catches it). KERNEL.CGO is a
    // boot CGO that cannot be standalone-rebuilt/pushed on this device, and the
    // writer lives in the render path, so -- exactly like the Gcine-pose NaN bone
    // repair -- we snapshot deactivate's known-good code once (it is clean for the
    // whole title/flythrough; the title would crash on its first deactivation
    // otherwise) and restore it after every rendered frame, before the GOAL thread
    // runs the next frame's deactivations. The I-cache is flushed so the corrected
    // instructions are re-fetched. x86 is unaffected (#ifdef __aarch64__).
#ifdef __aarch64__
    {
      constexpr u32 kDeactLo = 0x191240, kDeactLen = 0x74;  // [0x191240, 0x1912b4)
      static u8* s_deact_good = nullptr;
      static bool s_deact_reported = false;
      u8* live = g_ee_main_mem + kDeactLo;
      if (!s_deact_good) {
        // Arm only if this really is deactivate's code: the call-trampoline
        // `stp x3,x5,[sp,#-16]!` at GOAL 0x191250 == 0xa9bf17e3. Guards against a
        // future KERNEL.CGO relayout silently repairing the wrong bytes.
        u32 sig = 0;
        memcpy(&sig, g_ee_main_mem + 0x191250, 4);
        if (sig == 0xa9bf17e3u) {
          s_deact_good = (u8*)malloc(kDeactLen);
          memcpy(s_deact_good, live, kDeactLen);
        }
      } else if (memcmp(s_deact_good, live, kDeactLen) != 0) {
        if (!s_deact_reported) {
          s_deact_reported = true;
          u32 off = 0;
          while (off < kDeactLen && s_deact_good[off] == live[off]) off++;
          u32 wasw = 0, noww = 0;
          memcpy(&wasw, s_deact_good + (off & ~3u), 4);
          memcpy(&noww, live + (off & ~3u), 4);
          __android_log_print(
              ANDROID_LOG_FATAL, kLogTag,
              "GCINE3-DEACT-STOMP frame=%llu first=goal:0x%x was=0x%08x now=0x%08x "
              "(envmap merc l0-pris-merc draw stomped process::deactivate code; repaired)",
              (unsigned long long)st.frame_idx, kDeactLo + off, wasw, noww);
        }
        memcpy(live, s_deact_good, kDeactLen);
        __builtin___clear_cache((char*)live, (char*)live + kDeactLen);
      }
    }
#endif

    // === Gmatch: return-from-thread-dead code-stomp guard (arm64) =============
    // The NEW GAME sage-intro cutscene's arm64 blend-shape merc draw uses a
    // corrupted low base pointer (the recurring Gnd/Gcine3 "global-buf.base goes
    // high->low" class) and writes vertex data over the GOAL kernel asm-func
    // `return-from-thread-dead` (gkernel.gc:451) at GOAL 0x18aee4 -- the per-
    // process RETURN TRAMPOLINE that set-to-run-bootstrap (gkernel.gc:1849)
    // pushes onto every process's fake stack. When any process's main thread
    // then RETURNS, control lands at this trampoline; if it has been stomped the
    // CPU executes the overwritten bytes -> SIGILL (sig 4, pc=lr=0x7f0018aee4) ->
    // app death -> Android launcher. Verified: the live symbol-table walk
    // resolves crash target 0x18aee4 == "return-from-thread-dead", and the A37
    // PC-window shows it overwritten (00000000) where its code should be. This is
    // the SAME stomp mechanism the Gcine3 canary above repairs for a DIFFERENT
    // target (process::deactivate @ 0x191240); the sage-intro scene corrupts the
    // base to a different low address. KERNEL.CGO is an un-rebuildable boot CGO
    // and the writer is in the render path, so -- like the deactivate canary --
    // we snapshot the trampoline's clean code once (clean from boot until the
    // cutscene at ~frame 7080) and restore it after every rendered frame, before
    // the GOAL thread runs the next process return. x86 unaffected.
#ifdef __aarch64__
    {
      const u32 kRftdLo = g_gmatch_rftd_goal, kRftdLen = g_gmatch_rftd_len;  // 0x18aee4 / 0x80
      static bool s_rftd_reported = false;
      u8* rlive = g_ee_main_mem + kRftdLo;
      if (!g_gmatch_rftd_good) {
        // Snapshot once, while clean: a non-zero first word means the kernel code
        // is linked and not (yet) stomped; the frame gate keeps the snapshot
        // strictly before the cutscene stomp at ~frame 7080. Publishing the
        // pointer LAST makes the SIGILL handler's null-check race-safe.
        u32 w0 = 0;
        memcpy(&w0, rlive, 4);
        if (w0 != 0 && st.frame_idx < 6000) {
          u8* good = (u8*)malloc(kRftdLen);
          memcpy(good, rlive, kRftdLen);
          g_gmatch_rftd_good = good;
          __android_log_print(ANDROID_LOG_INFO, kLogTag,
                              "GMATCH-RFTD-CANARY armed goal:0x%x len=0x%x sig=0x%08x frame=%llu",
                              kRftdLo, kRftdLen, w0, (unsigned long long)st.frame_idx);
        }
      } else if (memcmp(g_gmatch_rftd_good, rlive, kRftdLen) != 0) {
        if (!s_rftd_reported) {
          s_rftd_reported = true;
          u32 off = 0;
          while (off < kRftdLen && g_gmatch_rftd_good[off] == rlive[off]) off++;
          u32 wasw = 0, noww = 0;
          memcpy(&wasw, g_gmatch_rftd_good + (off & ~3u), 4);
          memcpy(&noww, rlive + (off & ~3u), 4);
          __android_log_print(
              ANDROID_LOG_FATAL, kLogTag,
              "GMATCH-RFTD-STOMP frame=%llu first=goal:0x%x was=0x%08x now=0x%08x "
              "(merc blend-shape draw stomped return-from-thread-dead; repaired)",
              (unsigned long long)st.frame_idx, kRftdLo + off, wasw, noww);
        }
        memcpy(rlive, g_gmatch_rftd_good, kRftdLen);
        __builtin___clear_cache((char*)rlive, (char*)rlive + kRftdLen);
      }
    }
#endif

    const u64 n = d->frames_rendered.fetch_add(1) + 1;
    if (n <= 5 || (n % 60) == 0 || st.buckets_skipped > 0) {
      static u32 s_last_logged_skips = 0;
      if (n <= 5 || (n % 60) == 0 || st.buckets_skipped != s_last_logged_skips) {
        s_last_logged_skips = st.buckets_skipped;
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "A35-RENDER frame=%llu chain_bytes=%u buckets_drawn=%u skipped=%u "
                            "draws=%u tris=%u",
                            (unsigned long long)st.frame_idx, st.chain_bytes, st.buckets_drawn,
                            st.buckets_skipped, st.draw_calls, st.triangles);
      }
    }
  }

  // mark the chain rendered (desktop render_game_frame parity).
  {
    std::unique_lock<std::mutex> lock(d->dma_mutex);
    d->has_data_to_render = false;
    d->sync_cv.notify_all();
  }
  return got_chain;
}

void post_swap_tick() {
  if (!g_renderer_ready.load()) {
    return;
  }
  auto* d = g_data;
  std::unique_lock<std::mutex> lock(d->dma_mutex);
  d->frame_idx++;
  d->sync_cv.notify_all();
}

// A40: entry/exit counters for the GOAL-thread-facing shims. The A40-DPROC
// probe prints them at 1 Hz — they discriminate "display-loop iterates but
// aborts between syncv and the send" from "display-loop is never resumed"
// without any GOAL-side instrumentation. Plain atomics; zero cost when the
// probe property is off (nothing reads them).
std::atomic<u64> g_a40_vsync_entry{0};
std::atomic<u64> g_a40_vsync_exit{0};
std::atomic<u64> g_a40_syncpath_entry{0};
std::atomic<u64> g_a40_syncpath_exit{0};

namespace {
// ===== Gd1-cutscene-clock: wall-clock 60 Hz IOP/overlord VBlank pacer =======
// The jak1 overlord VBlank_Handler (game/overlord/jak1/srpc.cpp:446) advances
// the fake-VAG stream clock — `gFakeVAGClock += 1024/target_fps` per vblank —
// that paces EVERY spooled cutscene. On real PS2 hardware the IOP receives the
// VBlank interrupt at the display rate (60 Hz NTSC) REGARDLESS of how fast the
// EE renders, so with target_fps==60 (gfx.h) the clock advances 1024 units/sec
// = real time. The desktop oracle reproduces this for free: Gfx::vsync() (and
// thus the signal_vblank callback) is fired once per display-refresh swap at a
// flat 60 Hz because the desktop GPU holds 60 fps.
//
// On the Adreno 618 the render rate collapses on heavy content (new-game
// cutscene ~15 fps, village flythrough ~20 fps). The previous code fired the
// IOP vblank exactly once per vsync() call (= once per RENDERED+swapped frame),
// so the vblank — and therefore the cutscene stream clock — ticked at the
// render rate (~15 Hz) instead of 60 Hz. gFakeVAGClock then advanced at
// 15*(1024/60) ~= 0.27x real-time, so cinematics played in fluid slow-motion
// (~3.7x too slow; camera/joints still interpolate per game-frame so it looked
// smooth). Measured deterministically: Grender-audit D1.
//
// Fix: drive signal_vblank() from a dedicated wall-clock 60 Hz thread,
// decoupled from the render-swap cadence, exactly as the desktop's 60 Hz
// display loop does. The consume side (IOP_Kernel::dispatch, which runs the
// handler once per set of the atomic `vblank_recieved` bool) is shared,
// platform-identical code — only the SET rate diverged on Android, so restoring
// a 60 Hz set rate makes Android match desktop. signal_vblank only stores an
// atomic bool, so calling it from this thread is safe; the registered callback
// (android_runtime_full.cpp) also wakes the iop-runner so its <=1 ms idle
// dispatch sleep can't swallow a vblank edge under scheduler jitter. vsync() no
// longer fires the vblank at all — it is purely the game-chain frame-pacing
// barrier now. x86/desktop is untouched (this is an android/ TU).
std::mutex g_pacer_mutex;
std::condition_variable g_pacer_cv;
std::thread g_pacer_thread;
bool g_pacer_should_run = false;

void iop_vblank_pacer_loop() {
  pthread_setname_np(pthread_self(), "iopvbl-pacer");
  using namespace std::chrono;
  // 60 Hz NTSC vblank period. Coupled to target_fps==60 (the increment in
  // VBlank_Handler is 1024/target_fps), matching the desktop's 60 Hz display
  // assumption, so the fake-VAG clock advances 1024 units/sec = real-time.
  const auto period = microseconds(16667);
  auto next = steady_clock::now() + period;
  bool logged = false;
  // Phase F3: when debug.opengoal.f3.measure=1, log one "display tick" per
  // fired vblank. This callback IS the IOP/overlord vblank that advances the
  // game's *display* frame-counter / time at a true wall-clock 60 Hz, decoupled
  // from render swap (the whole point of the Gd1 pacer). Logging it is an
  // honest measurement of the SIMULATION rate for the F3 validator — it stays
  // 60 Hz even when the renderer is capped to 30 FPS. OFF by default (one
  // cached property read every 8 ticks); zero spam for normal runs.
  uint64_t f3_ticks = 0;
  unsigned f3_poll = 0;
  bool f3_on = false;
  for (;;) {
    std::function<void()> cb;
    {
      std::unique_lock<std::mutex> lk(g_pacer_mutex);
      g_pacer_cv.wait_until(lk, next, [] { return !g_pacer_should_run; });
      if (!g_pacer_should_run) {
        return;
      }
      cb = g_vsync_callback;  // copy under lock (set_vsync_callback writes it here)
    }
    if (cb && MasterExit == RuntimeExitStatus::RUNNING) {
      if (!logged) {
        logged = true;
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "Gd1-VBLANK IOP/overlord vblank now paced at wall-clock 60 Hz "
                            "(decoupled from render swap; cutscene clock = real-time)");
      }
      cb();
      if ((f3_poll++ & 7) == 0) {
        char pv[8] = {0};
        f3_on =
            __system_property_get("debug.opengoal.f3.measure", pv) > 0 && pv[0] == '1';
      }
      if (f3_on) {
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "Gd1-VBLANK display tick %llu (simulation 60 Hz; "
                            "render rate decoupled)",
                            (unsigned long long)(++f3_ticks));
      }
    }
    next += period;
    auto now = steady_clock::now();
    if (next < now) {
      // Fell behind (a long stall): resync to now instead of bursting a backlog
      // of zero-sleep ticks. signal_vblank coalesces a backlog into one handler
      // run anyway, so bursting would not advance the clock faster — resyncing
      // just keeps the long-run average at 60 Hz.
      next = now + period;
    }
  }
}
}  // namespace

void set_vsync_callback(std::function<void()> f) {
  bool start = false, stop = false;
  {
    std::unique_lock<std::mutex> lk(g_pacer_mutex);
    g_vsync_callback = std::move(f);
    if (g_vsync_callback && !g_pacer_should_run) {
      g_pacer_should_run = true;
      start = true;
    } else if (!g_vsync_callback && g_pacer_should_run) {
      g_pacer_should_run = false;
      stop = true;
    }
  }
  // Start/stop the pacer OUTSIDE the lock — join() would deadlock against the
  // pacer's own acquisition of g_pacer_mutex.
  if (stop) {
    g_pacer_cv.notify_all();
    if (g_pacer_thread.joinable()) {
      g_pacer_thread.join();
    }
  }
  if (start) {
    g_pacer_thread = std::thread(iop_vblank_pacer_loop);
  }
}

u32 vsync() {
  g_a40_vsync_entry.fetch_add(1, std::memory_order_relaxed);

  // Gd1-cutscene-clock: the IOP/overlord VBlank is NO LONGER fired from here.
  // It used to be fired once per vsync() call (= once per rendered frame), which
  // coupled the cutscene/spool stream clock to the render rate and produced
  // fluid slow-motion cinematics whenever the Adreno dropped below 60 fps (see
  // iop_vblank_pacer_loop above). A dedicated wall-clock 60 Hz pacer thread now
  // owns ALL vblank firing, mirroring the desktop's 60 Hz display loop. vsync()
  // is purely the game-chain frame-pacing barrier: it blocks until the next
  // swap so each game chain corresponds to one rendered frame.

  // Gintro: pre-renderer-ready, HOLD the GOAL dispatcher here instead of letting
  // it free-run. The SDL thread is concurrently bringing the renderer up (glad +
  // 43 shaders + GAME.fr3, ~2 s on the Adreno 618). If we returned 0 immediately
  // the dispatcher would free-run at ~270 Hz and fast-forward the entire
  // pre-title intro (SCE screen + ND/Daxter "ndi-intro") in the ~600 frames
  // before the first frame could be drawn, so those beats would never reach the
  // framebuffer (G1 boot: chains received == dropped == 607). Spin at ~60 Hz to
  // throttle the dispatcher until the renderer is up, then fall through to the
  // swap-chain block so the intro renders in chronological order. The overlord /
  // fake-VAG clock is kept real-time during this window by the pacer thread, not
  // here. The hold (~2 s) is far under the A37 hang-watchdog's 6 s threshold (and
  // that watchdog only logs). The renderer bring-up runs on the SDL thread
  // independently of the dispatcher, so this cannot deadlock.
  if (!g_renderer_ready.load()) {
    while (!g_renderer_ready.load() && MasterExit == RuntimeExitStatus::RUNNING) {
      std::this_thread::sleep_for(std::chrono::microseconds(16600));
    }
    if (!g_renderer_ready.load()) {
      // Shutting down before the renderer ever came up.
      g_a40_vsync_exit.fetch_add(1, std::memory_order_relaxed);
      return 0;
    }
    // Renderer just became ready — fall through to the post-ready path.
  }

  // Post-ready: block on the swap chain so each vsync() corresponds to one
  // rendered+swapped frame (game-chain pacing). The vblank that paces spooled
  // cutscenes is fired separately at wall-clock 60 Hz by the pacer thread. The
  // GAME-CLOCK SPEED fix lives in the quantized frame-clock timer (see
  // a35_read_ee_timer / gspeed_quantized_ee_ticks in gk_android_main.cpp), NOT
  // here -- this barrier stays the 1:1 game-chain<->swap pacer it always was.
  auto* d = g_data;
  std::unique_lock<std::mutex> lock(d->dma_mutex);
  auto init_frame = d->frame_idx_of_input_data;
  d->sync_cv.wait(lock, [=] {
    return (MasterExit != RuntimeExitStatus::RUNNING) || d->frame_idx > init_frame;
  });
  g_a40_vsync_exit.fetch_add(1, std::memory_order_relaxed);
  return d->frame_idx & 1;
}

u32 sync_path() {
  g_a40_syncpath_entry.fetch_add(1, std::memory_order_relaxed);
  if (!g_renderer_ready.load()) {
    g_a40_syncpath_exit.fetch_add(1, std::memory_order_relaxed);
    return 0;
  }
  auto* d = g_data;
  std::unique_lock<std::mutex> lock(d->dma_mutex);
  if (!d->has_data_to_render) {
    g_a40_syncpath_exit.fetch_add(1, std::memory_order_relaxed);
    return 0;
  }
  d->sync_cv.wait(lock, [=] { return !d->has_data_to_render; });
  g_a40_syncpath_exit.fetch_add(1, std::memory_order_relaxed);
  return 0;
}

void send_chain(const void* data, u32 offset) {
  const u32 n = g_chains_received.fetch_add(1) + 1;
  if (!g_renderer_ready.load()) {
    const u32 dropped = g_chains_dropped_pre_init.fetch_add(1) + 1;
    if (dropped == 1) {
      __android_log_print(ANDROID_LOG_WARN, kLogTag,
                          "A35-RENDER send_chain before renderer init — dropping until the GL "
                          "thread finishes bring-up (counted, not silent)");
    }
    return;
  }
#if defined(__aarch64__) && defined(__ANDROID__)
  // GND-HWWP: arm the arm64 HARDWARE data watchpoint on the global-buf base
  // fields from the GOAL/dispatcher thread (this thread is the writer). Gated
  // behind debug.opengoal.gnd.hwwp=1; one-shot, no-op on every later frame.
  gnd_hwwp_arm_once();
#endif
  auto* d = g_data;
  std::unique_lock<std::mutex> lock(d->dma_mutex);
  if (d->has_data_to_render) {
    lg::error("A35-RENDER send_chain called with pending data (frame pacing bug?)");
    return;
  }
  if (n == 1 || (n % 600) == 0) {
    __android_log_print(ANDROID_LOG_INFO, kLogTag, "A35-RENDER send_chain #%u offset=0x%x", n,
                        offset);
  }
  // A42: bounded pre-probe of the live chain, then copy (see dma_copier
  // field note). FixedChunkDmaCopier::run has an unbounded walk + a
  // LOW_PROTECT assert, so a malformed live chain must be caught here —
  // skip the frame instead of hanging/aborting the game thread.
  {
    DmaFollower probe(data, offset);
    constexpr int kMaxSteps = 400000;
    int steps = 0;
    bool low_tag = false;
    int low_kind = -1;
    u32 low_addr = 0, low_qwc = 0;
    bool low_spr = false;
    // Gintro: dump the leading tags of the first few flagged chains to
    // characterize the ndi-intro chain that trips the low-addr guard.
    static std::atomic<u32> s_dump_frames{0};
    const bool do_dump = gintro_chainwalk_dbg() && s_dump_frames.load() < 6;
    int dumped = 0;
    while (!probe.ended() && steps < kMaxSteps) {
      auto tag = probe.current_tag();
      if (do_dump && dumped < 14) {
        dumped++;
        __android_log_print(ANDROID_LOG_WARN, kLogTag,
                            "GINTRO-CHAINWALK step=%d off=0x%x kind=%d spr=%d addr=0x%x qwc=%u",
                            steps, probe.current_tag_offset(), (int)tag.kind, (int)tag.spr,
                            tag.addr, tag.qwc);
      }
      if (tag.addr != 0 && tag.addr <= EE_MAIN_MEM_LOW_PROTECT) {
        low_tag = true;
        low_kind = (int)tag.kind;  // 0=REFE 1=CNT 2=NEXT 3=REF 4=REFS 5=CALL 6=RET 7=END
        low_addr = tag.addr;
        low_qwc = tag.qwc;
        low_spr = tag.spr;
        // GND diag: prove whether the LIVE memory really holds this low addr
        // (follower correct -> real corruption) or the follower mis-read
        // (memory fine -> follower/base bug). Read the tag bytes BOTH via the
        // follower's base and directly via g_ee_main_mem, plus a re-read.
        if (do_dump) {
          u32 mt = probe.current_tag_offset();
          u64 raw_data = 0, raw_ee = 0, raw_ee2 = 0;
          if ((u64)mt + 8 <= EE_MAIN_MEM_SIZE) {
            memcpy(&raw_data, (const u8*)data + mt, 8);
            memcpy(&raw_ee, g_ee_main_mem + mt, 8);
            memcpy(&raw_ee2, g_ee_main_mem + mt, 8);
          }
          __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                              "GND-PRECOPY-RAW off=0x%x data_is_ee=%d base_delta=0x%lx "
                              "raw@data=0x%016llx raw@ee=0x%016llx reread=0x%016llx",
                              mt, (int)((const u8*)data == g_ee_main_mem),
                              (unsigned long)((const u8*)data - g_ee_main_mem),
                              (unsigned long long)raw_data, (unsigned long long)raw_ee,
                              (unsigned long long)raw_ee2);
        }
        break;
      }
      probe.read_and_advance();
      steps++;
    }
    if (!probe.ended() || low_tag) {
      // Gintro diagnostic: dump the FLAGGED tag (kind/spr/addr/qwc), the true
      // (uncapped) skip count, and the 16 bytes AT the flagged NEXT/REF
      // destination (data + addr) so we can tell a legit jump from garbage.
      // addr is only dereferenced for REF/REFE/REFS (kind 0/3/4) and
      // NEXT/CALL (kind 2/5); CNT/RET/END (1/6/7) ignore it.
      static std::atomic<u32> s_precopy_total{0};
      const u32 ntot = s_precopy_total.fetch_add(1) + 1;
      if (do_dump) {
        s_dump_frames.fetch_add(1);
      }
      if (ntot <= 40 || (ntot % 240) == 0) {
        u64 dst0 = 0, dst1 = 0;
        if (low_addr != 0 && (u64)low_addr + 16 <= EE_MAIN_MEM_SIZE) {
          memcpy(&dst0, (const u8*)data + low_addr, 8);
          memcpy(&dst1, (const u8*)data + low_addr + 8, 8);
        }
        __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                            "A42-CHAIN-PRECOPY skip #%u (steps=%d low_tag=%d kind=%d spr=%d "
                            "addr=0x%x qwc=%u off=0x%x dst=0x%016llx %016llx) — skipped",
                            ntot, steps, (int)low_tag, low_kind, (int)low_spr, low_addr, low_qwc,
                            probe.current_tag_offset(), (unsigned long long)dst0,
                            (unsigned long long)dst1);
      }
      // Gintro: this corrupt chain is the arm64 blend-shape/joint OOB stomp
      // (the ndi state spawns Jak+Daxter blend-shape skeletons; their joint-
      // decompress intermittently scribbles a low garbage addr into a per-
      // frame DMA bucket-NEXT — confirmed vs the x86 oracle which never
      // produces a low tag; see Gintro-fix-summary). The chain CANNOT go to
      // the copier (its LOW_PROTECT assert would abort) nor to the renderer
      // (it would follow the garbage NEXT). The old behavior dropped it, but
      // dropping breaks the frame pacing: frame_idx_of_input_data freezes
      // while swaps advance, so vsync() free-runs and fast-forwards the ndi
      // spool, AND the ndi logo black-flashes. Instead, RE-PRESENT the last
      // good copied chain: the renderer redraws the previous ndi frame, the
      // consume cadence stays 1:1 (real-time pacing holds), and the logo is
      // held (a brief stutter) rather than dropped. This makes the ND/Daxter
      // logo render in order despite the OOB; the OOB itself is a separate
      // (deeper, goalc-arm64) defect tracked for its own phase.
      if (d->ever_copied && !d->has_data_to_render) {
        d->has_data_to_render = true;
        d->dma_cv.notify_all();
      }
      return;
    }
  }
  const auto& chain_copy = d->dma_copier.run(data, offset);
  d->chain_data = chain_copy.data.data();
  d->chain_offset = chain_copy.start_offset;
  d->has_data_to_render = true;
  d->ever_copied = true;
  d->dma_cv.notify_all();
}

namespace {
// A41: dropping pre-ready texture calls loses them FOREVER — unlike frame
// chains, they are one-shot. On device the GOAL boot races GL bring-up:
// GAME.CGO's tpage logins (InitMachine, which runs on the SDL thread
// BEFORE android_renderer_run can bring the renderer up) and the
// dispatcher thread's setup-font-texture! upload+relocate all fire before
// renderer-ready (A40 run-1: first send_chain dropped at 10.127s, ready at
// 10.782s), so the font texture never entered the pool and DirectRenderer
// missed at slot 14720 (=0xe6000/64, the relocated 24pt font) every frame
// — the untextured text quads. Desktop never sees this because GL init
// precedes the GOAL kernel. Blocking the caller was tried first and
// deadlocks: the link-time calls run ON the SDL thread, upstream of the
// renderer bring-up they would wait for (A41 run-1: boot parked in
// InitMachine, zero A35-RENDER lines). So: queue pre-ready calls in FIFO
// order and flush them the moment the renderer is up. Both pool ops are
// GL-free and pool-mutex'd — safe from any thread. Upload entries keep the
// GOAL tpage pointer; the texture-page objects live in the global heap and
// nothing unloads them in the ~1s window before the flush (each replay is
// logged so a future violation names itself).
struct PendingTexCall {
  bool is_relocate;
  std::vector<TexturePool::PrecomputedUpload> upload_entries;  // parsed at call time
  u32 dst, src, format;
};
std::mutex g_pending_tex_mutex;        // ordering: take BEFORE the pool mutex
std::vector<PendingTexCall> g_pending_tex_calls;
bool g_pending_tex_flushed = false;

// Parse an upload-now call into slot-link entries WHILE the GOAL page is
// alive. Read-side mirror of TexturePool::handle_upload_now (same mode →
// segment rules, same name construction); pure GOAL-memory reads, no pool,
// no GL — callable on the game thread before the renderer exists. Run-2
// proved replay-by-pointer is unsound: setup-font-texture! kicks the font
// page right after relocating it, so by flush time the queued pointer read
// reused heap and the font's source slot (0x2786) was never linked —
// relocate ASSERT'd 'src' and SIGABRT'd the boot.
std::vector<TexturePool::PrecomputedUpload> snapshot_upload(const u8* tpage,
                                                            int mode,
                                                            u32 s7_ptr) {
  std::vector<TexturePool::PrecomputedUpload> out;
  GoalTexturePage texture_page;
  memcpy(&texture_page, tpage, sizeof(GoalTexturePage));

  bool has_segment[3] = {true, true, true};
  if (mode == -1) {
  } else if (mode == 2) {
    has_segment[0] = false;
    has_segment[1] = false;
  } else if (mode == -2) {
    has_segment[2] = false;
  } else if (mode == 0) {
    has_segment[1] = false;
    has_segment[2] = false;
  } else {
    // handle_upload_now logs and skips these modes; mirror that.
    __android_log_print(ANDROID_LOG_WARN, kLogTag, "A41-TEX snapshot skipping mode %d", mode);
    return out;
  }

  auto goal_str = [&](u32 ptr) -> const char* {
    return ptr == 0 ? "" : (const char*)(g_ee_main_mem + ptr + 4);
  };

  for (int tex_idx = 0; tex_idx < texture_page.length; tex_idx++) {
    GoalTexture tex;
    if (texture_page.try_copy_texture_description(&tex, tex_idx, g_ee_main_mem, tpage, s7_ptr)) {
      for (int mip_idx = 0; mip_idx < tex.num_mips; mip_idx++) {
        if (has_segment[tex.segment_of_mip(mip_idx)]) {
          TexturePool::PrecomputedUpload e;
          e.id = PcTextureId(texture_page.id, tex_idx);
          e.name = std::string(goal_str(texture_page.name_ptr)) + goal_str(tex.name_ptr);
          e.dest = tex.dest[mip_idx];
          out.push_back(std::move(e));
        }
      }
    }
  }
  return out;
}

void run_tex_call(const PendingTexCall& c) {
  if (c.is_relocate) {
    __android_log_print(ANDROID_LOG_INFO, kLogTag, "A41-TEX relocate dst=0x%x src=0x%x fmt=%u",
                        c.dst, c.src, c.format);
    g_data->texture_pool->relocate(c.dst, c.src, c.format);
  } else {
    static u32 s_upload_count = 0;
    const u32 n = ++s_upload_count;
    if (n <= 8 || (n % 100) == 0) {
      __android_log_print(ANDROID_LOG_INFO, kLogTag, "A41-TEX upload #%u (%zu slot links)", n,
                          c.upload_entries.size());
    }
    g_data->texture_pool->handle_upload_precomputed(c.upload_entries);
  }
}

// Pre: g_pending_tex_mutex held, g_renderer_ready true.
void drain_pending_tex_calls_locked() {
  if (g_pending_tex_flushed) {
    return;
  }
  g_pending_tex_flushed = true;
  if (!g_pending_tex_calls.empty()) {
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                        "A41-TEX flushing %zu queued pre-ready texture calls (boot-order race)",
                        g_pending_tex_calls.size());
    for (const auto& c : g_pending_tex_calls) {
      run_tex_call(c);
    }
    g_pending_tex_calls.clear();
    g_pending_tex_calls.shrink_to_fit();
  }
}

void enqueue_or_run_tex_call(const PendingTexCall& c) {
  std::unique_lock<std::mutex> lk(g_pending_tex_mutex);
  if (!g_renderer_ready.load()) {
    static u32 s_queued_logged = 0;
    if (++s_queued_logged <= 8) {
      __android_log_print(ANDROID_LOG_INFO, kLogTag,
                          "A41-TEX queueing pre-ready %s #%u (renderer not up yet)",
                          c.is_relocate ? "relocate" : "upload-now", s_queued_logged);
    }
    g_pending_tex_calls.push_back(c);
    return;
  }
  drain_pending_tex_calls_locked();  // FIFO: anything queued runs first
  run_tex_call(c);
}

void flush_pending_texture_calls_on_ready() {
  std::unique_lock<std::mutex> lk(g_pending_tex_mutex);
  drain_pending_tex_calls_locked();
}
}  // namespace

void texture_upload_now(const u8* tpage, int mode, u32 s7_ptr) {
  // TexturePool::handle_upload_now / handle_upload_precomputed do no GL —
  // they link tpage slots to loader-provided textures (or placeholders)
  // under the pool lock. Safe from the game thread, exactly like desktop
  // gl_texture_upload_now. The page walk happens HERE, while the GOAL page
  // object is guaranteed alive (see snapshot_upload).
  PendingTexCall c{};
  c.is_relocate = false;
  c.upload_entries = snapshot_upload(tpage, mode, s7_ptr);
  enqueue_or_run_tex_call(c);
}

void texture_relocate(u32 dst, u32 src, u32 format) {
  // Rare (jak1: the four font planes at boot). Logged on execute — dst is
  // the pool slot DirectRenderer will look up (font: 0x3800/0x3980).
  PendingTexCall c{};
  c.is_relocate = true;
  c.dst = dst;
  c.src = src;
  c.format = format;
  enqueue_or_run_tex_call(c);
}

void set_pmode_alp(float val) {
  if (!g_renderer_ready.load()) {
    return;
  }
  g_data->pmode_alp.store(val);
}

namespace {
void mod_set_levels(const std::vector<std::string>& levels) {
  if (g_renderer_ready.load() && g_data->loader) {
    g_data->loader->set_want_levels(levels);
  }
}

void mod_set_active_levels(const std::vector<std::string>& levels) {
  if (g_renderer_ready.load() && g_data->loader) {
    g_data->loader->set_active_levels(levels);
  }
}

const GfxRendererModule gRendererAndroid = {
    [](GfxGlobalSettings&) -> int { return 0; },  // init (GL init happens on the SDL thread)
    [](int, int, const char*, GfxGlobalSettings&, GameVersion,
       bool) -> std::shared_ptr<GfxDisplay> { return nullptr; },  // make_display (SDL thread owns)
    []() {},                                                      // exit
    vsync,                                                        // vsync
    sync_path,                                                    // sync_path
    send_chain,                                                   // send_chain
    texture_upload_now,                                           // texture_upload_now
    texture_relocate,                                             // texture_relocate
    mod_set_levels,                                               // set_levels
    mod_set_active_levels,                                        // set_active_levels
    set_pmode_alp,                                                // set_pmode_alp
    GfxPipeline::OpenGL,                                          // pipeline
    "Android GLES 3.2"                                            // name
};
}  // namespace

const GfxRendererModule* renderer_module() {
  return &gRendererAndroid;
}

}  // namespace android_gfx

// A40: shim-counter snapshot for the gk_android_main.cpp 1 Hz probe.
// out[0..5] = vsync_entry, vsync_exit, sync_path_entry, sync_path_exit,
// chains_received, chains_dropped_pre_init.
extern "C" void gk_a40_shim_counters(unsigned long long out[6]) {
  using namespace android_gfx;
  out[0] = g_a40_vsync_entry.load(std::memory_order_relaxed);
  out[1] = g_a40_vsync_exit.load(std::memory_order_relaxed);
  out[2] = g_a40_syncpath_entry.load(std::memory_order_relaxed);
  out[3] = g_a40_syncpath_exit.load(std::memory_order_relaxed);
  out[4] = g_chains_received.load(std::memory_order_relaxed);
  out[5] = g_chains_dropped_pre_init.load(std::memory_order_relaxed);
}
