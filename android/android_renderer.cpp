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

#include <atomic>
#include <cinttypes>
#include <cstdint>

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

    if (!drew_game) {
      // No chain this frame (boot, paused, or kernel dead): dark-blue
      // clear, visibly distinct from a rendered black game frame.
      glViewport(0, 0, win_w, win_h);
      glClearColor(0.05f, 0.10f, 0.30f, 1.0f);
      glClearDepthf(1.0f);
      glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    }

    SDL_GL_SwapWindow(window);
    android_gfx::post_swap_tick();

    const uint64_t n =
        g_renderer_frame_count.fetch_add(1, std::memory_order_relaxed) + 1;
    if ((n % 60) == 0) {
      __android_log_print(ANDROID_LOG_INFO, kLogTag,
                          "android_renderer: sustained swap %" PRIu64
                          " (game_frames=%s)",
                          n, drew_game ? "flowing" : "none");
    }

    if (!drew_game && !vsync_ok) {
      SDL_Delay(16);
    }
  }

  SDL_GL_DestroyContext(glctx);
  SDL_DestroyWindow(window);

  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "android_renderer_run: exiting");
  return 0;
}
