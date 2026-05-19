// Phase 10 (autoport): Android NDK cross-build scaffold for OpenGOAL's
// gk runtime. Produces libgk.so for arm64-v8a so the NDK toolchain
// integration can be validated end-to-end. Phase 11 will link the full
// runtime, SDL3, GLES, and OpenAL behind a proper JNI surface.

#include <android/log.h>
#include <jni.h>

#include <cstdio>
#include <cstring>

namespace {
constexpr const char* kGkVersion =
    "OpenGOAL gk (Android arm64-v8a scaffold, autoport phase 10)";
constexpr const char* kGkLogTag = "opengoal-gk";
}  // namespace

extern "C" {

// Stable C entry points usable from a future Android activity or a small
// standalone test harness. Kept extern "C" so name-mangling doesn't get
// in the way of JNI/dlsym lookups.

const char* gk_version_string(void) {
  return kGkVersion;
}

int gk_print_version(void) {
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag, "%s", kGkVersion);
  std::fprintf(stdout, "%s\n", kGkVersion);
  return 0;
}

// Default JNI entry used when libgk.so is loaded via System.loadLibrary.
// Logs once so we can see in `adb logcat` that the right ABI was picked.
JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* /*vm*/, void* /*reserved*/) {
  __android_log_print(ANDROID_LOG_INFO, kGkLogTag,
                      "libgk.so loaded (%s)", kGkVersion);
  return JNI_VERSION_1_6;
}

// Placeholder so an Activity in phase 11 can pull the version string out
// without needing extra wiring. Class name is provisional.
JNIEXPORT jstring JNICALL
Java_org_opengoal_gk_NativeGk_version(JNIEnv* env, jclass /*clazz*/) {
  return env->NewStringUTF(kGkVersion);
}

}  // extern "C"
