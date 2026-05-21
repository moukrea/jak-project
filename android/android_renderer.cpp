// SDL3 + GLES context bring-up. This is the honest minimum the activity
// needs to prove the platform substrate works: SDL_Init, an SDL window,
// a GLES 3.2 context, glClear + SDL_GL_SwapWindow.
//
// No game-content rendering happens here. The supervisor rollback on
// 2026-05-20 removed the phase-29 gradient-quad "chain renderer" that
// was used to game the phase-29 pixel-diversity validator. The real
// OpenGL renderer (game/graphics/opengl_renderer/) has not been ported
// to Android yet — until it has, android_renderer_run() just maintains
// the swap chain and a known-color clear so the activity stays alive.
//
// Lifecycle: android_renderer_run() is called from goal_main() on the
// SDL main thread. It blocks until MasterExit transitions out of
// RUNNING or until SDL_EVENT_QUIT / SDL_EVENT_TERMINATING arrives.
//
// Phase D3 (autoport): the swap loop is the observable heartbeat the
// supervisor's reality checks key off. To make "eglSwapBuffers
// sustained" verifiable without a device, we keep a process-lifetime
// std::atomic<uint64_t> frame counter and emit an __android_log_print
// marker every 60 frames. The counter is exposed through
// android_renderer_frame_count() so the JNI bridge in
// gk_android_main.cpp can hand it to Java when D4 starts probing.

#include "android_renderer.h"

#include <android/log.h>

#include <SDL3/SDL.h>
#include <GLES3/gl32.h>

#include <atomic>
#include <cinttypes>
#include <cstdint>

#include "common/common_types.h"
#include "game/kernel/common/kboot.h"

namespace {
constexpr const char* kLogTag = "opengoal-gk";

// Phase D3 (autoport): the swap-loop heartbeat. Static-storage atomic
// so concurrent JNI readers from the Java thread (via
// Java_org_opengoal_gk_NativeGk_getRendererFrameCount) observe a
// well-defined value without acquiring a lock. Reset to 0 on each
// android_renderer_run entry so a quick exit+relaunch sees a fresh
// counter rather than stale state from the previous run.
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

  __android_log_print(ANDROID_LOG_WARN, kLogTag,
                      "android_renderer_run: NO GAME CONTENT RENDERER WIRED "
                      "— maintaining clear/swap loop only. The real OpenGL "
                      "renderer port is bucket D in REDESIGN.md.");

  // Phase D3 (autoport): start the frame counter at zero on every entry
  // so the sustained-swap evidence reflects this invocation only.
  g_renderer_frame_count.store(0, std::memory_order_relaxed);

  bool running = true;
  while (running && MasterExit == RuntimeExitStatus::RUNNING) {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
      if (event.type == SDL_EVENT_QUIT ||
          event.type == SDL_EVENT_TERMINATING) {
        __android_log_print(ANDROID_LOG_INFO, kLogTag,
                            "android_renderer_run: quit event received");
        running = false;
      }
    }

    // Dark blue clear. Distinguishable from a black framebuffer (so we
    // know the GLES path is alive) but visibly not game content.
    glClearColor(0.05f, 0.10f, 0.30f, 1.0f);
    glClearDepthf(1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    SDL_GL_SwapWindow(window);

    const uint64_t n =
        g_renderer_frame_count.fetch_add(1, std::memory_order_relaxed) + 1;
    if ((n % 60) == 0) {
      __android_log_print(ANDROID_LOG_INFO, kLogTag,
                          "android_renderer: sustained swap %" PRIu64, n);
    }

    SDL_Delay(16);
  }

  SDL_GL_DestroyContext(glctx);
  SDL_DestroyWindow(window);

  __android_log_print(ANDROID_LOG_INFO, kLogTag,
                      "android_renderer_run: exiting");
  return 0;
}
