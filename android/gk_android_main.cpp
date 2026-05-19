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

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* /*vm*/, void* /*reserved*/) {
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "libgk.so loaded (%s)", kGkVersion);
  return JNI_VERSION_1_6;
}

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
