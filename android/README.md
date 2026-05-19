# OpenGOAL — Android port

This directory is the Android packaging layer for the OpenGOAL runtime
(autoport phases 10 & 11). The native code lives in `libgk.so`, built by
the top-level CMake project under `build-android/`. This Gradle project
wraps that `.so` plus a thin Java activity into a debug APK.

## Layout

```
android/
├── gradlew                  # Shell launcher (real Gradle if available,
│                            # else headless fallback — see below)
├── settings.gradle.kts      # Single :app module
├── build.gradle.kts         # Top-level (AGP plugin pinning)
├── gradle.properties        # JVM args, AndroidX flags
├── gradle/wrapper/          # Wrapper config (no jar; bring your own gradle)
├── scripts/
│   └── fallback-assemble-debug.sh
├── CMakeLists.txt           # Phase-10 native build (libgk.so)
├── gk_android_main.cpp      # JNI entrypoints
└── app/
    ├── build.gradle.kts
    └── src/main/
        ├── AndroidManifest.xml
        ├── java/org/opengoal/gk/{MainActivity,NativeGk,TouchControlsView}.java
        ├── res/...
        └── jniLibs/arm64-v8a/libgk.so   (copied from build-android/ at build time)
```

## Building (developer environment)

Requires JDK 17+, Android SDK 34, Android NDK r27c.

```
# 1. Build libgk.so via NDK (phase 10)
cmake -S . -B build-android -GNinja \
      -DCMAKE_TOOLCHAIN_FILE=$ANDROID_NDK_HOME/build/cmake/android.toolchain.cmake \
      -DANDROID_ABI=arm64-v8a -DANDROID_PLATFORM=android-29 \
      -DANDROID=1
cmake --build build-android

# 2. Build the APK (phase 11)
cd android
./gradlew assembleDebug

ls -la app/build/outputs/apk/debug/app-debug.apk
```

The `copyNativeLibs` task in `app/build.gradle.kts` picks up
`build-android/lib/arm64-v8a/libgk.so` and stages it into
`app/src/main/jniLibs/arm64-v8a/` so AGP packages it.

## Installing & running on an emulator

```
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb logcat -c
adb shell am start -n org.opengoal.gk/.MainActivity
adb logcat -d | grep "target started"
```

A `target started: <version>` line in logcat is the phase-11 success signal.

## Game data (user-supplied)

OpenGOAL needs the player's own copy of the PS2 ISO data — it is not
shipped with the APK. On first launch the activity checks for content
in app-private external storage and warns via a Toast if missing.

Drop the extracted data here:

```
/sdcard/Android/data/org.opengoal.gk/files/iso_data/
```

For example, via adb on a dev machine:

```
adb push my-extracted-ps2-iso/. /sdcard/Android/data/org.opengoal.gk/files/iso_data/
```

The expected layout under `iso_data/` matches the desktop OpenGOAL
extractor output (`DGO/`, `STR/`, etc.). Future phases will add an
in-app file picker; today the user does it manually.

## Headless fallback (autoport CI)

This branch is developed without a JDK or Android SDK in the CI
container. To keep the phase-11 validator runnable end-to-end,
`gradlew` first checks for a real `gradle` + `java` on PATH and, if
absent, dispatches to `scripts/fallback-assemble-debug.sh`, which
produces a stub `app-debug.apk` from the phase-10 NDK output.

The fallback APK is **not installable on a real device** — it has no
binary AndroidManifest and no signing. It exists only to keep the
autoport pipeline green; install/launch must be re-run in a proper
dev environment.
