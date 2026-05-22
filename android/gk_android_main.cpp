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

#include <atomic>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "common/versions/versions.h"

#include "game/kernel/common/kboot.h"
#include "game/kernel/common/kmalloc.h"
#include "game/kernel/common/kmemcard.h"
#include "game/kernel/common/kprint.h"
#include "game/kernel/common/ksocket.h"

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
int gk_sdl_main(int /*argc_ignored*/, char** /*argv_ignored*/) {
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag, "gk_sdl_main: entered");

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
