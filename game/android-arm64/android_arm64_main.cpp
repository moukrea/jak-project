// Phase D1 (autoport, bucket D): banner-and-exit driver for the
// android-arm64 NDK cross-build of `gk`.
//
// D1 mirrors C1's posture for linux-arm64: the binary must build and
// link cleanly against its target libc (Bionic here, glibc there), but
// it does not yet run the kernel-init chain. D2 wires graphics, D3
// wires the SDL3/SurfaceView bridge, D4 reaches title under the APK.
//
// The dual log + stderr write is deliberate — the same banner is
// observable from either `adb logcat -s opengoal-gk` (when pushed to
// a device and run via `adb shell /data/local/tmp/gk`) or from a
// future Bionic-capable qemu-android setup that captures stderr.

#include <android/log.h>

#include <cstdio>
#include <cstdlib>

namespace {
constexpr const char* kBanner =
    "D1: android-arm64 gk built; D2 will wire graphics/runtime";
constexpr const char* kAndroidLogTag = "opengoal-gk";
}  // namespace

int main(int /*argc*/, char** /*argv*/) {
    __android_log_print(ANDROID_LOG_INFO, kAndroidLogTag, "%s", kBanner);
    std::fprintf(stderr, "%s\n", kBanner);
    return 2;
}
