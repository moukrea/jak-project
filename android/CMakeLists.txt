# Phase 10 (autoport): minimal Android NDK build of `gk`.
#
# This subdir is only added by the top-level CMakeLists.txt when ANDROID=1
# (i.e. cmake was invoked with the NDK's android.toolchain.cmake). Its job
# is narrow: produce libgk.so as an aarch64 shared object so the NDK
# toolchain integration can be validated end-to-end. Phase 11 will replace
# this with the full runtime link (SDL3, GLES, OpenAL, libco, ...) and an
# APK packaging step.
#
# Android apps load their native code as a .so via System.loadLibrary,
# so the canonical native artifact here is libgk.so — not a standalone
# `gk` executable. The phase-10 validator accepts either name.

add_library(gk SHARED
    gk_android_main.cpp)

target_compile_features(gk PRIVATE cxx_std_20)

target_compile_options(gk PRIVATE
    -fexceptions
    -fcxx-exceptions
    -fdiagnostics-color=always
    -Wall
    -Wno-unused-parameter)

# bionic + Android logging + JNI come from the NDK sysroot.
target_link_libraries(gk PRIVATE log android)

# Drop the .so somewhere predictable for phase-11 APK packaging.
set_target_properties(gk PROPERTIES
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/lib/${ANDROID_ABI}")
