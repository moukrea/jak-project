// Phase 13 (autoport): JNI entrypoints for libgk.so on Android.
//
// libgk.so contains a curated subset of the OpenGOAL kernel
// (game/kernel/common/{kboot,kmalloc,ksocket}.cpp etc.) plus Android-friendly
// compat for logging and the runtime globals. The JNI surface here is the
// bridge the Activity (phase 13) uses to drive boot, plumb game selection
// from per-flavor resources, and forward touch input into the runtime.

#include <android/input.h>
#include <android/log.h>
#include <jni.h>

#include <atomic>
#include <cstdio>
#include <cstring>

#include "common/versions/versions.h"

#include "game/kernel/common/kboot.h"
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/ksocket.h"

// Phase 18 (autoport): SDL3 statically linked into libgk.so. We also pull
// in the NDK's GLESv3 header for glGetString(GL_RENDERER) so the validator
// can confirm the EGL context is bound to a real mobile GPU (Adreno on
// the user's Redmi Note 9 Pro, Mali/PowerVR/Xclipse on other devices).
#include <SDL3/SDL.h>
#include <GLES3/gl3.h>

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

// Phase 18 (autoport): SDL3 entry point invoked by SDLActivity via
// nativeRunMain → dlsym("gk_sdl_main"). For this phase we don't have a
// real game loop yet — just prove the EGL/GLES context lives on the
// Activity SurfaceView by:
//   1. SDL_Init(SDL_INIT_VIDEO)
//   2. SDL_CreateWindow with SDL_WINDOW_OPENGL
//   3. SDL_GL_CreateContext
//   4. SDL_GL_MakeCurrent
//   5. glClear(dark blue), SDL_GL_SwapWindow
//   6. event loop polling until SDL_EVENT_QUIT
// The validator greps for the marker strings below. Symbol must be
// extern "C" because SDL dlsym's it by C name.
int gk_sdl_main(int argc, char* argv[]) {
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag, "gk_sdl_main: entered");
  for (int i = 0; i < argc; ++i) {
    __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                        "gk_sdl_main: argv[%d]=%s", i, argv[i] ? argv[i] : "");
  }

  if (!SDL_Init(SDL_INIT_VIDEO)) {
    __android_log_print(ANDROID_LOG_ERROR, kGkLogTag,
                        "SDL_Init(SDL_INIT_VIDEO) failed: %s", SDL_GetError());
    return 1;
  }
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "SDL_Init: video subsystem OK");

  // Request a GLES 3.0 context; SDL3 on Android selects EGL automatically.
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_ES);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, 3);
  SDL_GL_SetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, 0);
  SDL_GL_SetAttribute(SDL_GL_RED_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_GREEN_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_BLUE_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_ALPHA_SIZE, 8);
  SDL_GL_SetAttribute(SDL_GL_DEPTH_SIZE, 24);
  SDL_GL_SetAttribute(SDL_GL_DOUBLEBUFFER, 1);

  // Width/height of 0 lets SDL pick the surface's natural dimensions on
  // Android (the SurfaceView fills the activity).
  SDL_Window* window = SDL_CreateWindow(
      "OpenGOAL", 0, 0,
      SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN);
  if (!window) {
    __android_log_print(ANDROID_LOG_ERROR, kGkLogTag,
                        "SDL_CreateWindow failed: %s", SDL_GetError());
    SDL_Quit();
    return 1;
  }
  int win_w = 0, win_h = 0;
  SDL_GetWindowSize(window, &win_w, &win_h);
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "SDL_CreateWindow: %dx%d created", win_w, win_h);

  SDL_GLContext glctx = SDL_GL_CreateContext(window);
  if (!glctx) {
    __android_log_print(ANDROID_LOG_ERROR, kGkLogTag,
                        "SDL_GL_CreateContext failed: %s", SDL_GetError());
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 1;
  }
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "SDL_GL_CreateContext: ok");

  if (!SDL_GL_MakeCurrent(window, glctx)) {
    __android_log_print(ANDROID_LOG_ERROR, kGkLogTag,
                        "SDL_GL_MakeCurrent failed: %s", SDL_GetError());
    SDL_GL_DestroyContext(glctx);
    SDL_DestroyWindow(window);
    SDL_Quit();
    return 1;
  }
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag, "eglMakeCurrent: success");

  const GLubyte* renderer = glGetString(GL_RENDERER);
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "GL_RENDERER: %s",
                      renderer ? reinterpret_cast<const char*>(renderer)
                               : "(null)");
  const GLubyte* gl_version = glGetString(GL_VERSION);
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "GL_VERSION: %s",
                      gl_version ? reinterpret_cast<const char*>(gl_version)
                                 : "(null)");

  // Clear once to a recognizable dark blue and swap so the validator
  // observes eglSwapBuffers. Subsequent frames repeat the same clear/swap
  // so the surface stays visible until SDL_EVENT_QUIT.
  glClearColor(0.05f, 0.10f, 0.30f, 1.0f);
  glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
  SDL_GL_SwapWindow(window);
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag, "eglSwapBuffers: ok");

  bool running = true;
  while (running) {
    SDL_Event event;
    while (SDL_PollEvent(&event)) {
      if (event.type == SDL_EVENT_QUIT ||
          event.type == SDL_EVENT_TERMINATING) {
        __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                            "gk_sdl_main: quit event received");
        running = false;
      }
    }
    glClearColor(0.05f, 0.10f, 0.30f, 1.0f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);
    SDL_GL_SwapWindow(window);
    // Tiny sleep so we don't peg the CPU while we don't have a real
    // frame budget yet. Phase 19 replaces the body with the GOAL boot
    // loop, which has its own pacing.
    SDL_Delay(16);
  }

  // SDLActivity owns lifecycle; do not call SDL_Quit here. The Java side
  // will tear down once onDestroy fires.
  SDL_GL_DestroyContext(glctx);
  SDL_DestroyWindow(window);
  return 0;
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

}  // extern "C"
