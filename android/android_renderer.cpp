// SDL3 + GLES context bring-up + the A35 game-content render loop.
//
// Phase A35 (autoport): this TU previously maintained an honest clear/swap
// stub ("NO GAME CONTENT RENDERER WIRED"). It now drives the real ported
// renderer: after the GLES 3.2 context is current, android_gfx builds the
// TexturePool + Loader + AndroidOpenGLRenderer (DirectRenderer +
// TextureUploadHandler + EyeRenderer buckets), and every loop iteration
// consumes one DMA chain from the GOAL kernel via the same mutex/cv
// handshake the desktop pipeline uses. When the kernel hasn't produced a
// chain (boot, or kernel death) the loop falls back to the dark-blue clear
// so "no content" stays visibly distinct from "black frame".
//
// Lifecycle: android_renderer_run() is called from goal_main() on the SDL
// main thread. It blocks until MasterExit transitions out of RUNNING or
// until SDL_EVENT_QUIT / SDL_EVENT_TERMINATING arrives.

#include "android_renderer.h"

#include <android/log.h>

#include <SDL3/SDL.h>

#include <sys/system_properties.h>

#include <atomic>
#include <chrono>
#include <cinttypes>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <string>
#include <thread>

#include "common/common_types.h"

#include "game/kernel/common/kboot.h"

#include "android_gfx.h"
#include "android_input_audio.h"

#include "third-party/glad/include/glad/glad.h"

namespace {
constexpr const char* kLogTag = "opengoal-gk";

// Swap-loop heartbeat (phase D3) — JNI readers poll this via
// android_renderer_frame_count().
std::atomic<uint64_t> g_renderer_frame_count{0};
}  // namespace

uint64_t android_renderer_frame_count() {
  return g_renderer_frame_count.load(std::memory_order_relaxed);
}

int android_renderer_run() {
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "android_renderer_run: entered");

  if (!SDL_Init(SDL_INIT_VIDEO)) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "SDL_Init(SDL_INIT_VIDEO) failed: %s",
                        SDL_GetError());
    return 1;
  }
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "SDL_Init: video subsystem OK");

  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK,
                      SDL_GL_CONTEXT_PROFILE_ES);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 2);
  SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
  SDL_GL_SetAttribute(SDL_GL_STENCIL_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

  SDL_Window* window = SDL_CreateWindow(
      "OpenGOAL", 0, 0,
      SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN);
  if (!window) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "SDL_CreateWindow failed: %s", SDL_GetError());
    SDL_Quit();
    return 1;
  }
  int win_w = 0, win_h = 0;
  SDL_GetWindowSize(window, &win_w, &win_h);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "SDL_CreateWindow: %dx%d created", win_w, win_h);

  SDL_GLContext glctx = SDL_GL_CreateContext(window);
  if (!glctx) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "SDL_GL_CreateContext failed: %s",
                        SDL_GetError());
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 1;
  }
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "SDL_GL_CreateContext: ok");

  if (!SDL_GL_MakeCurrent(window, glctx)) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "SDL_GL_MakeCurrent failed: %s", SDL_GetError());
    SDL_GL_DestroyContext(glctx);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 1;
  }
  __android_log_print(ANDROID_LOG_INFO, kLogTag, "eglMakeCurrent: success");

  // A35: real GL entry points + the ported renderer. On failure we keep
  // the clear/swap loop below and say so — never silently.
  const bool renderer_up = android_gfx::init_renderer_on_gl_thread(win_w, win_h);
  if (!renderer_up) {
    __android_log_print(ANDROID_LOG_ERROR, kLogTag,
                        "android_renderer_run: A35 renderer bring-up FAILED — "
                        "maintaining clear/swap loop only (no game content "
                        "possible this run)");
  } else {
    __android_log_print(ANDROID_LOG_INFO, kLogTag,
                        "android_renderer_run: A35 game-content renderer wired "
                        "(DirectRenderer + TextureUploadHandler + EyeRenderer "
                        "buckets; unported buckets skip with named logs)");
  }

  const GLubyte* gl_renderer = glGetString(GL_RENDERER);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "GL_RENDERER: %s",
                      gl_renderer ? reinterpret_cast<const char*>(gl_renderer)
                                  : "(null)");
  const GLubyte* gl_version = glGetString(GL_VERSION);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "GL_VERSION: %s",
                      gl_version ? reinterpret_cast<const char*>(gl_version)
                                 : "(null)");

  glViewport(0, 0, win_w, win_h);
  glDisable(GL_DEPTH_TEST);
  glDisable(GL_CULL_FACE);

  // Pace swaps to the display; if unsupported, fall back to a 16 ms sleep
  // in the idle path below.
  const bool vsync_ok = SDL_GL_SetSwapInterval(1);
  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "SDL_GL_SetSwapInterval(1): %s",
                      vsync_ok ? "ok" : SDL_GetError());

  g_renderer_frame_count.store(0, std::memory_order_relaxed);

  // A37: register this thread with the hang watchdog (gk_android_main)
  // so a frame-counter stall dumps the GL stack alongside the GOAL one.
  extern pthread_t g_a37_gl_thread;
  extern std::atomic<bool> g_a37_gl_thread_set;
  g_a37_gl_thread = pthread_self();
  g_a37_gl_thread_set.store(true);

  // === Phase F3: per-frame render cadence measurement (prop-armed) =========
  // When debug.opengoal.f3.measure=1, record the swap-to-swap delta of every
  // loop iteration (SDL_GetPerformanceCounter) to $HOME/F3-frame-times.csv and
  // report a WINDOW-scoped "sustained swap" counter so the F3 validator's swap
  // count reflects frames-in-the-measured-window (= real render FPS), not the
  // cumulative-since-boot count. The simulation rate is unaffected: the Gd1
  // wall-clock 60 Hz IOP/overlord vblank pacer (android_gfx.cpp) advances the
  // game clock at 60 Hz regardless of this render cadence. OFF by default →
  // zero cost (one cached property read every 15 frames) for all other runs,
  // and the existing cumulative "sustained swap" log (D3/D4) is untouched.
  const uint64_t f3_perf_freq = SDL_GetPerformanceFrequency();
  uint64_t f3_prev_ctr = 0;
  bool f3_have_prev = false;
  bool f3_armed = false;
  uint64_t f3_window_swaps = 0;
  FILE* f3_csv = nullptr;
  unsigned f3_poll = 0;

  bool running = true;
  while (running && MasterExit == RuntimeExitStatus::RUNNING) {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
      // Phase E1: route SDL gamepad events into the GOAL pad path.
      if (android_input_audio::process_sdl_event(event)) {
        continue;
      }
      if (event.type == SDL_EVENT_QUIT ||
          event.type == SDL_EVENT_TERMINATING) {
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "android_renderer_run: quit event received");
        running = false;
      }
    }

    SDL_GetWindowSize(window, &win_w, &win_h);

    bool drew_game = false;
    if (renderer_up) {
      drew_game = android_gfx::render_frame_on_gl_thread(win_w, win_h);
    }

    // A36 canary v2: glad_glClearDepthf went NULL at enter-title with the
    // bucket canary silent and render() never entered — the smash comes from
    // outside the renderer. Check every loop iteration; on flip, dump the
    // neighborhood and KEEP RUNNING (skip the clear) so the run keeps
    // producing evidence instead of dying at the BLR.
    {
      static void* s_canary2 = nullptr;
      static bool s_canary2_init = false;
      static bool s_flipped_logged = false;
      if (!s_canary2_init) {
        s_canary2 = (void*)glad_glClearDepthf;
        s_canary2_init = true;
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "A36-CANARY2 armed &glad_glClearDepthf=%p val=%p",
                            (void*)&glad_glClearDepthf, s_canary2);
      }
      if ((void*)glad_glClearDepthf != s_canary2 && !s_flipped_logged) {
        s_flipped_logged = true;
        const uint64_t* nb = (const uint64_t*)((uintptr_t)&glad_glClearDepthf & ~15ull);
        __android_log_print(ANDROID_LOG_FATAL, kLogTag,
                            "A36-CANARY2 FLIPPED val=%p (was %p) — neighborhood:",
                            (void*)glad_glClearDepthf, s_canary2);
        for (int r = -2; r <= 2; r++) {
          __android_log_print(ANDROID_LOG_FATAL, kLogTag, "A36-CANARY2 %p: %016llx %016llx",
                              (const void*)(nb + r * 2), (unsigned long long)nb[r * 2],
                              (unsigned long long)nb[r * 2 + 1]);
        }
      }
    }
    // Gspeed-flicker fix: NEVER present a buffer the game did not draw this
    // cycle. The vblank-locked pacing below runs the engine at a stable
    // sub-60 rate, so some GL iterations get no fresh chain (render_frame_on_
    // gl_thread times out, or we spin while the engine is mid-frame). The old
    // code unconditionally cleared-to-blue + swapped on every chainless
    // iteration, flashing an undrawn frame between good frames -> the owner's
    // "clignotte noir/bleu" regression. Instead:
    //   * boot, before the FIRST real game frame: keep the dark-blue clear+swap
    //     (the intended boot indicator) so the screen isn't a frozen garbage
    //     buffer while the renderer/level loads.
    //   * once a real game frame has been presented: on a chainless iteration,
    //     do NOT clear and do NOT swap -- the compositor holds the last good
    //     front buffer, so the screen stays on the last drawn frame (no flash).
    // This keeps the constant-speed behavior (clock + pacing still advance only
    // on real drawn frames, below) while eliminating the black/blue flicker.
    static bool s_ever_drew = false;
    bool present_this_cycle;
    if (drew_game) {
      s_ever_drew = true;
      present_this_cycle = true;
    } else if (!s_ever_drew && glad_glClearDepthf) {
      // Boot only: dark-blue clear so a chainless pre-title frame is a clean
      // boot color, not a stale/garbage buffer.
      glViewport(0, 0, win_w, win_h);
      glClearColor(0.05f, 0.10f, 0.30f, 1.0f);
      glClearDepthf(1.0f);
      glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
      present_this_cycle = true;
    } else {
      // Mid-game chainless iteration: hold the last good frame (no swap).
      present_this_cycle = false;
    }

    if (present_this_cycle) {
      SDL_GL_SwapWindow(window);
      android_gfx::post_swap_tick();
    }

    // ===== Gspeed: STABLE frame-rate lock (arm64/Android) ====================
    // The GOAL engine game-clock (drawable.gc display-frame-start) is paced 1:1
    // with this swap loop (vsync() blocks on post_swap_tick's frame_idx). It
    // turns the per-frame wall-clock into an INTEGER time-ratio = floor(elapsed /
    // (1/60 s)) + 1 (clamp <1.3 -> 1.0) that scales ALL physics/animation/game-
    // time. That integer is only correct when every frame is the SAME clean
    // number of vblanks: a steady 60 fps -> ratio 1 (full speed), a steady 30 fps
    // -> ratio 2 (real-time, half the visual frames). The bug the owner sees is
    // that the raw Adreno swap cadence is UNSTABLE (~16-33 ms, 1.0-2.2 vblanks),
    // so the integer ratio quantizes erratically frame-to-frame -> game speed
    // oscillates "sometimes fast / sometimes slow" (Gspeed-device BEFORE).
    //
    // FIX: lock the swap to a STABLE whole-vblank grid anchored at boot, so each
    // frame is a constant integer number of vblanks and the engine's per-frame
    // delta is constant -> constant time-ratio -> constant game speed == real
    // time. We sleep so the NEXT swap lands on the grid edge that is one full
    // STEP (in vblanks) past the previous one; STEP adapts to what the device can
    // actually hold (60 fps when frames fit in ~1 vblank, else 30 fps), and only
    // changes hysteretically so it does not flap. SDL vsync (SwapInterval(1))
    // still aligns the buffer flip to the panel; this only pads the wait so the
    // engine clock sees a stable cadence. 1:1 engine:render is preserved, so the
    // per-rendered-frame crash-repair canaries (A38/Gcine3/Gmatch) keep their
    // cadence. Cutscenes are paced by the separate Gd1 60 Hz IOP pacer. x86 and
    // goal_src untouched (android/ TU). Disable with debug.opengoal.gspeed.off=1.
    {
      using namespace std::chrono;
      static steady_clock::time_point s_work_start{};  // when last release returned
      static bool s_init = false;
      static int s_step = 1;          // vblanks per frame (1=60fps, 2=30fps)
      static int s_over = 0, s_under = 0;
      static unsigned s_offpoll = 0;
      static bool s_off = false;
      constexpr auto kP = nanoseconds(16666667);  // 1/60 s
      if ((s_offpoll++ & 31) == 0) {
        char pv[8] = {0};
        s_off = __system_property_get("debug.opengoal.gspeed.off", pv) > 0 && pv[0] == '1';
      }
      // Only PACE + advance the game-clock on a REAL drawn+presented frame. A
      // chainless iteration (no fresh game frame this cycle) must NOT advance the
      // clock (that would over-advance game-time = the speed bug) and must NOT
      // pad the grid; instead hold briefly so we don't busy-spin, then retry for
      // the chain. This pairs with the "don't swap an undrawn buffer" logic above
      // so a chainless cycle neither flashes nor speeds up game-time.
      if (!s_off && !drew_game) {
        std::this_thread::sleep_for(microseconds(1500));
      }
      if (!s_off && drew_game) {
        auto now = steady_clock::now();
        if (!s_init) { s_init = true; s_work_start = now; }
        // Measure the ACTUAL render+engine work this frame: real time from the
        // previous release-point to now (the just-finished swap), in vblanks.
        double work_vbl = duration_cast<duration<double>>(now - s_work_start).count() /
                          duration_cast<duration<double>>(kP).count();
        // The engine advances `step` whole game-timesteps per `step` real
        // vblanks, so game speed == 60 Hz ONLY if every frame's real duration is
        // EXACTLY `step` vblanks. The device's natural frame time is generally
        // fractional (idle ~1.46 vblanks), so we must CEIL: pick the smallest
        // whole-vblank cadence the work fits inside, then pad up to it. Rounding
        // DOWN (e.g. 1.46 -> 1) is the bug -- it advances 1 step over 1.46 real
        // vblanks => ~41 units/s (too slow). Ceil(1.46)=2 pads to 2 vblanks (30
        // fps) => 2 steps / 2 vblanks => a true 60 Hz. A tiny tolerance keeps a
        // genuine ~1.0-vblank frame at step 1 (don't punish 60 fps into 30).
        // Ceil to the smallest whole-vblank cadence the work fits inside, with a
        // generous tolerance: once we pad to `step` vblanks, the next swap aligns
        // to the FOLLOWING vsync, so the measured work routinely reads slightly
        // OVER an integer (e.g. a step-2 pad measures ~2.2 vblanks). Without a
        // wide tolerance that over-read would promote to step+1 and back, causing
        // the residual tr=2<->3 flap. A 0.45-vblank tolerance absorbs the swap-
        // align jitter so the cadence stays on one integer.
        int need = (int)(work_vbl + (1.0 - 0.45));  // ceil with 0.45-vblank tol
        if (need < 1) need = 1;
        // Hysteresis so a single hitch doesn't flap the step. Promote (slower)
        // only on several consecutive genuinely-over-budget frames; demote
        // (faster) only after a long stable run that comfortably fits the smaller
        // step (work fits step-1 with margin) so we never immediately flap back.
        if (need > s_step) { if (++s_over >= 8) { s_step = need; s_over = 0; s_under = 0; } }
        else if (s_step > 1 && work_vbl < (double)(s_step - 1) - 0.15) {
          if (++s_under >= 150) { s_step--; s_under = 0; }
        } else { s_over = 0; s_under = 0; }
        if (s_step < 1) s_step = 1;
        if (s_step > 4) s_step = 4;  // mirror GOAL (fmin 4.0) clamp
        // Sleep so this frame occupies exactly s_step whole vblanks of real time,
        // measured from the previous release-point -> a STABLE cadence.
        auto release_at = s_work_start + s_step * kP;
        auto spin_floor = release_at - microseconds(500);
        if (steady_clock::now() < spin_floor) std::this_thread::sleep_until(spin_floor);
        while (steady_clock::now() < release_at && MasterExit == RuntimeExitStatus::RUNNING) {}
        // If we fell behind the schedule (work already exceeded s_step vblanks),
        // re-anchor to now so we don't accumulate a sleep backlog.
        auto rel_now = steady_clock::now();
        s_work_start = (rel_now > release_at) ? rel_now : release_at;

        // Drive the engine game-clock off this stable grid: advance the published
        // EE-tick counter by (step - 0.5) frame-budgets so the GOAL floor()+1
        // time-ratio resolves to exactly `step` (step=1 -> 0.5 budgets -> clamp
        // -> ratio 1; step=2 -> 1.5 -> ratio 2). See g_gspeed_clock_ticks note in
        // android_gfx.cpp. *ticks-per-frame* (custom 60 fps) == 9765. Net effect:
        // game advances `step` integer timesteps per real `step` vblanks == a
        // constant real-time 60 Hz, regardless of how many visual frames render.
        {
          constexpr double kTicksPerFrame = 9765.0;
          unsigned long long add =
              (unsigned long long)((double)s_step * kTicksPerFrame - 0.5 * kTicksPerFrame + 0.5);
          android_gfx::g_gspeed_clock_ticks.fetch_add(add, std::memory_order_relaxed);
          android_gfx::g_gspeed_clock_active.store(true, std::memory_order_release);
        }
      }
    }
    // =========================================================================

    // === Phase F3 measurement (prop-armed; see block above the loop) =======
    if ((f3_poll++ % 15) == 0) {
      char pv[8] = {0};
      const bool want =
          __system_property_get("debug.opengoal.f3.measure", pv) > 0 && pv[0] == '1';
      if (want && !f3_armed) {
        f3_armed = true;
        f3_window_swaps = 0;
        f3_have_prev = false;
        const char* home = getenv("HOME");
        std::string p = (home && *home)
                            ? std::string(home) + "/F3-frame-times.csv"
                            : std::string("/data/local/tmp/F3-frame-times.csv");
        if (f3_csv) {
          fclose(f3_csv);
        }
        f3_csv = fopen(p.c_str(), "w");
        if (f3_csv) {
          fprintf(f3_csv, "frame_time_us\n");
        }
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "F3-MEASURE armed: per-frame swap cadence -> %s "
                            "(simulation stays 60 Hz via vblank pacer)",
                            p.c_str());
      } else if (!want && f3_armed) {
        f3_armed = false;
        if (f3_csv) {
          fflush(f3_csv);
          fclose(f3_csv);
          f3_csv = nullptr;
        }
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "F3-MEASURE disarmed: CSV flushed (%" PRIu64
                            " frames in window)",
                            f3_window_swaps);
      }
    }
    const uint64_t f3_now = SDL_GetPerformanceCounter();
    if (f3_armed) {
      if (f3_have_prev && f3_perf_freq) {
        const uint64_t us =
            (uint64_t)((f3_now - f3_prev_ctr) * 1000000ull / f3_perf_freq);
        if (f3_csv) {
          fprintf(f3_csv, "%llu\n", (unsigned long long)us);
          if ((f3_window_swaps % 60) == 0) {
            fflush(f3_csv);
          }
        }
      }
      f3_window_swaps++;
    }
    f3_prev_ctr = f3_now;
    f3_have_prev = true;

    // Keep the global counter monotonic (A37 watchdog heartbeat); report the
    // window-scoped count while F3 is armed so the validator measures FPS in
    // the gameplay window, not the cumulative since-boot total.
    const uint64_t n =
        g_renderer_frame_count.fetch_add(1, std::memory_order_relaxed) + 1;
    const uint64_t report = f3_armed ? f3_window_swaps : n;
    if ((report % 60) == 0) {
      __android_log_print(ANDROID_LOG_INFO, kLogTag,
                          "android_renderer: sustained swap %" PRIu64
                          " (game_frames=%s)",
                          report, drew_game ? "flowing" : "none");
    }

    if (!drew_game && !vsync_ok) {
      SDL_Delay(16);
    }
  }

  if (f3_csv) {
    fflush(f3_csv);
    fclose(f3_csv);
    f3_csv = nullptr;
  }

  SDL_GL_DestroyContext(glctx);
  SDL_DestroyWindow(window);

  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "android_renderer_run: exiting");
  return 0;
}
