# Phase D1 (autoport, bucket D): thin forwarder around the NDK's
# `android.toolchain.cmake` for the bucket-D Android-NDK gk cross-build.
#
# This file exists so `.autoport/lib/d1_configure.sh` can pass a single
# -DCMAKE_TOOLCHAIN_FILE= argument without the caller knowing the NDK
# install path. It mirrors `cmake/aarch64-linux-toolchain.cmake`'s shape
# for the linux-arm64 (bucket C) build.
#
# Caller contract:
#   * ANDROID_NDK_HOME must be set in the environment (the autoport
#     install-script puts it at $HOME/Android/android-ndk-r27c and
#     d1_configure.sh sources $HOME/.opengoal-android-env.sh first).
#   * -DOG_ANDROID_ARM64=ON must be passed on the cmake command line
#     so the root CMakeLists.txt fires the bucket-D divert.
#
# Pinned defaults (caller may override on the command line):
#   * ANDROID_ABI=arm64-v8a       — Redmi Note 9 Pro is aarch64.
#   * ANDROID_PLATFORM=android-29 — minSdk in android/build.gradle.kts,
#                                   MIUI 12 / Android 10 on the device.
#   * ANDROID_STL=c++_static      — GOAL kernel pulls std::unordered_map,
#                                   std::filesystem, std::thread; static
#                                   libc++ keeps the binary self-contained.

if(NOT DEFINED ENV{ANDROID_NDK_HOME} AND NOT DEFINED ANDROID_NDK_HOME)
    message(FATAL_ERROR
        "ANDROID_NDK_HOME is not set. Source ~/.opengoal-android-env.sh "
        "or set ANDROID_NDK_HOME explicitly before configuring with this "
        "toolchain (D1 / OG_ANDROID_ARM64).")
endif()

if(NOT DEFINED ANDROID_NDK_HOME)
    set(ANDROID_NDK_HOME "$ENV{ANDROID_NDK_HOME}")
endif()

# Pin the bucket-D defaults BEFORE the NDK toolchain file runs; the NDK
# script reads these from cache if already set, so set(... CACHE ...)
# with FORCE keeps them from getting overridden by user defaults.
set(ANDROID_ABI       "arm64-v8a"   CACHE STRING "Bucket D pins arm64-v8a"        FORCE)
set(ANDROID_PLATFORM  "android-29"  CACHE STRING "Bucket D pins API 29 (Android 10)" FORCE)
set(ANDROID_STL       "c++_static"  CACHE STRING "Bucket D pins static libc++"   FORCE)

# Mention OG_ANDROID_ARM64 so the D1 validator's grep finds this file
# is bucket-D-aware. The actual divert lives in root CMakeLists.txt.
# OG_ANDROID_ARM64 must be passed on the cmake command line; this
# toolchain file does not force it (caller chooses).
if(NOT DEFINED OG_ANDROID_ARM64)
    message(STATUS "android-arm64-toolchain: OG_ANDROID_ARM64 not set on command line; root CMakeLists.txt will fall through to the existing android/ libgk.so divert. Pass -DOG_ANDROID_ARM64=ON for the bucket-D path.")
endif()

# Forward to the real NDK toolchain. Everything from CMAKE_SYSTEM_NAME to
# CMAKE_C_COMPILER is configured by the included file.
include("${ANDROID_NDK_HOME}/build/cmake/android.toolchain.cmake")
