# Top Level CMakeLists.txt
cmake_minimum_required(VERSION 3.10)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
project(jak)
include(CTest)

# Include third-party modules
set(CMAKE_MODULE_PATH ${PROJECT_SOURCE_DIR}/third-party/cmake/modules/)

# Phase D1 (autoport, bucket D): Android NDK cross-build of `gk` as a
# bucket-D bionic-shim test binary. Distinct from the phase-10 android/
# libgk.so divert below — D1 produces a standalone `gk` executable that
# proves Bionic-linking is clean before SDL3/GLES/Activity work layers
# on top in D2/D3/D4. Configure with:
#   cmake -S . -B build-arm64-android \
#         -DCMAKE_TOOLCHAIN_FILE=$PWD/cmake/android-arm64-toolchain.cmake \
#         -DOG_ANDROID_ARM64=ON -DCMAKE_BUILD_TYPE=Release
# Both branches share the if(ANDROID) gate (set by the NDK toolchain);
# OG_ANDROID_ARM64 picks bucket-D, otherwise the existing phase-10
# Activity-libgk.so divert is preserved unmodified.
option(OG_ANDROID_ARM64 "Build the bucket-D android-arm64 gk (NDK cross-toolchain)" OFF)

# Grecharged-buildsys-flags: build-time feature flags. Each of the four
# "recharged" features is compiled OUT of the binary when its flag is OFF
# (the default => a build byte-for-byte equivalent to stock with all
# toggles off). build.sh flips these ON per flag-set. They are declared
# and applied HERE, before the if(ANDROID) divert, so BOTH the desktop gk
# tree AND the android/ (libgk.so) subtree inherit the compile definitions.
option(OG_FEAT_RECHARGED_HUD   "Compile in the recharged HUD textures/loader"          OFF)
option(OG_FEAT_GRASS_OVERHANG  "Compile in the grass-overhang (rim-drape/3-zone) paths" OFF)
option(OG_FEAT_HD_MODELS       "Compile in the HD/enhanced-models fr3 selection path"   OFF)
option(OG_FEAT_PBR             "Compile in the PBR realtime-lighting/shading path"      OFF)
option(OG_FEAT_PHYSICS         "Compile in the secondary-motion physics sim (needs HD_MODELS)" OFF)
option(OG_FEAT_VULKAN_SUPPORT  "Compile in the Vulkan render pipeline (desktop only)"   OFF)
# Flag-set hash + target triple. build.sh overrides this. It is NOT applied
# globally (that would recompile the world on every flag-set change) — it is
# stamped onto the single marker TU below via set_source_files_properties.
set(OG_FLAG_SET_ID "e3b0c44298fc:linux-x86_64" CACHE STRING "flag-set hash:target stamped into g_og_flag_set_marker")

foreach(feat RECHARGED_HUD GRASS_OVERHANG HD_MODELS PBR PHYSICS VULKAN_SUPPORT)
  if(OG_FEAT_${feat})
    add_compile_definitions(OG_FEAT_${feat}=1)
  endif()
endforeach()

# The flag-set marker TU is game/kernel/common/kboot.cpp — it is compiled
# into BOTH the desktop gk executable and the android_kernel static lib
# (=> libgk.so), and pulls no graphics deps, so it is the one guaranteed
# shared pairing-proof site. OG_FLAG_SET_ID is stamped onto just that file
# (via set_source_files_properties) so changing the flag-set id only
# recompiles kboot.cpp, not the whole tree. NOTE: source-file properties are
# directory-scoped under cmake 3.10, so the stamp is applied inside each
# subdirectory that adds kboot.cpp (game/CMakeLists.txt and
# android/CMakeLists.txt), reading the OG_FLAG_SET_ID cache var declared above.

# Phase 10 (autoport): Android NDK cross-build entry point.
# The NDK's android.toolchain.cmake sets CMAKE_SYSTEM_NAME=Android which
# in turn makes CMake define ANDROID=1. When that's the case, divert to
# the minimal android/ subdir which produces libgk.so for arm64-v8a using
# NDK clang. None of the x86-specific compiler flags, NASM, AVX intrinsics
# or host third-party libs below are reachable on this path — phase 11 will
# fold the full runtime/SDL3/GLES/OpenAL stack into a proper APK build.
if(ANDROID)
    # A36: `char` defaults to UNSIGNED on AArch64 but SIGNED on x86-64. The
    # shared C++ runtime (kprint format parser, kitoa pad/length sentinels,
    # 8.3 name mangling, ...) was written against x86 semantics and uses
    # `char c != -1` sentinel comparisons that misroute when char is
    # unsigned — on-device this broke format's ~D (printed empty for lang 0,
    # so text asked for "common.TXT" instead of "0common.TXT") and turned
    # kitoa's "no pad" (-1) into a 255-byte 0xFF pad smear written into GOAL
    # heap strings. Restore the x86 oracle's semantics globally.
    add_compile_options(-fsigned-char)
    if(OG_ANDROID_ARM64)
        message(STATUS "Bucket D: android-arm64 NDK gk (D1+): ABI=${ANDROID_ABI} platform=${ANDROID_PLATFORM}")
        if(NOT GOALC_BACKEND)
            set(GOALC_BACKEND "arm64" CACHE STRING "GOAL compiler codegen backend" FORCE)
        endif()
        add_compile_definitions(GOALC_BACKEND_ARM64 OG_ANDROID_ARM64=1)
        add_subdirectory(game/android-arm64)
        return()
    endif()
    message(STATUS "Android NDK build: ABI=${ANDROID_ABI} platform=${ANDROID_PLATFORM} NDK=${ANDROID_NDK}")
    if(NOT GOALC_BACKEND)
        set(GOALC_BACKEND "arm64" CACHE STRING "GOAL compiler codegen backend" FORCE)
    endif()
    if(NOT GOALC_BACKEND STREQUAL "arm64")
        message(WARNING "Android build forces GOALC_BACKEND=arm64 (was ${GOALC_BACKEND})")
        set(GOALC_BACKEND "arm64" CACHE STRING "GOAL compiler codegen backend" FORCE)
    endif()
    add_compile_definitions(GOALC_BACKEND_ARM64 OG_ANDROID_NDK_BUILD=1)
    add_subdirectory(android)
    return()
endif()

# Phase 26 (autoport): aarch64-linux cross-build for the qemu stress
# harness (tools/arm64-stress/goal_stress_arm64). Set OG_ARM64_STRESS=ON
# in your CMake toolchain file (see cmake/aarch64-linux-toolchain.cmake)
# and configure into a dedicated build dir (build-arm64-linux/). Diverts
# straight into tools/arm64-stress/ to bypass the desktop dependency
# tree (SDL3/GLES/imgui/discord/curl), none of which have an aarch64
# sysroot here.
option(OG_ARM64_STRESS "Build the phase-26 aarch64 stress harness (cross-toolchain)" OFF)
if(OG_ARM64_STRESS)
    message(STATUS "Phase 26 stress build: aarch64-linux cross-toolchain")
    add_compile_options(-fsigned-char)  # A36: x86 char semantics (see ANDROID block)
    add_subdirectory(tools/arm64-stress)
    return()
endif()

# Phase C1 (autoport, bucket C): aarch64-linux cross-build of the FULL
# gk runtime — the real game/kernel + overlord + system layer, linked
# against vendored fmt/libco, with honest abort-stubs for the
# graphics/sound/curl externs (game/linux-arm64/linux_arm64_runtime_compat.cpp).
# C2 makes the binary actually start under qemu; C3 makes it reach
# title. C1 is purely "the binary builds." Configure with:
#   cmake -S . -B build-arm64-linux \
#         -DCMAKE_TOOLCHAIN_FILE=$PWD/cmake/aarch64-linux-toolchain.cmake \
#         -DOG_LINUX_ARM64=ON -DCMAKE_BUILD_TYPE=Release
option(OG_LINUX_ARM64 "Build the bucket-C aarch64-linux gk (cross-toolchain)" OFF)
if(OG_LINUX_ARM64)
    message(STATUS "Bucket C: aarch64-linux gk cross-toolchain")
    if(NOT GOALC_BACKEND)
        set(GOALC_BACKEND "arm64" CACHE STRING "GOAL compiler codegen backend" FORCE)
    endif()
    add_compile_options(-fsigned-char)  # A36: x86 char semantics (see ANDROID block)
    add_subdirectory(game/linux-arm64)
    return()
endif()

# Default to Release mode
if(NOT CMAKE_BUILD_TYPE)
    set(CMAKE_BUILD_TYPE "Release")
endif()

# Phase 09 (autoport): cross-build a minimal aarch64 `gk` via the
# aarch64-linux-gnu toolchain so the build-arm64 tree can produce an ELF
# qemu-aarch64-static can execute. See game/arm64_boot_stub.S for rationale.
option(OG_ARM64_BOOT_STUB "Build a minimal aarch64 gk via cross-toolchain (phase 09)" OFF)

# Potentially statically build the project
option(STATICALLY_LINK "Build for release purposes (statically link everything)" OFF)
message(STATUS "Statically Link? ${STATICALLY_LINK}")
if(STATICALLY_LINK)
    set(BUILD_SHARED_LIBS OFF)
    set(BUILD_STATIC_LIBS ON)
else()
    set(BUILD_SHARED_LIBS ON)
    set(BUILD_STATIC_LIBS OFF)
endif()

# GOAL compiler code-generation backend selection (Android port phase 01).
# x86  -> the existing x86-64 emitter (default, current behavior)
# arm64 -> the AArch64 scaffold (stubs only, no real codegen yet)
set(GOALC_BACKEND "x86" CACHE STRING "GOAL compiler codegen backend: x86 or arm64")
set_property(CACHE GOALC_BACKEND PROPERTY STRINGS "x86" "arm64")
if(GOALC_BACKEND STREQUAL "arm64")
    message(STATUS "GOALC backend: arm64 (scaffold)")
    add_compile_definitions(GOALC_BACKEND_ARM64)
elseif(GOALC_BACKEND STREQUAL "x86")
    message(STATUS "GOALC backend: x86")
else()
    message(FATAL_ERROR "Unsupported GOALC_BACKEND=${GOALC_BACKEND}; expected x86 or arm64")
endif()

# For clangd
if (EXISTS "${CMAKE_CURRENT_BINARY_DIR}/compile_commands.json" )
    configure_file(
        "${CMAKE_CURRENT_BINARY_DIR}/compile_commands.json"
        "${PROJECT_SOURCE_DIR}/build/compile_commands.json")
endif()

# NOTE - for SDL, i think SDL3 regressed this - https://github.com/libsdl-org/SDL/pull/6455
# a more recent issue - https://github.com/libsdl-org/SDL/issues/12078
if (APPLE)
  enable_language(OBJC)
  execute_process(
    COMMAND xcrun --show-sdk-path
        OUTPUT_VARIABLE MACOSX_SYSROOT
        OUTPUT_STRIP_TRAILING_WHITESPACE
    )
    # Tell CMake to use it
    set(CMAKE_OSX_SYSROOT "${MACOSX_SYSROOT}" CACHE PATH "macOS SDK path" FORCE)
endif()

# Setup compiler flags
if(CMAKE_CXX_COMPILER_ID STREQUAL "Clang")
    message(STATUS "Clang Detected - Setting Defaults")
    set(CMAKE_CXX_FLAGS
        "${CMAKE_CXX_FLAGS} \
        -fcxx-exceptions \
        -fexceptions \
        -fdiagnostics-color=always \
        -mavx \
        -Wall \
        -Wno-c++11-narrowing \
        -Wno-c++98-compat \
        -Wno-deprecated-this-capture \
        -Wno-missing-field-initializers \
        -Wno-sign-compare \
        -Wno-ignored-qualifiers \
        -Werror=return-type \
        -O3 \
        -D_CRT_SECURE_NO_WARNINGS")

    # Increase stack size for windows, who's default is too low
    if(WIN32)
        # Increase the reserved stack size for all threads to 16MB
        # Note: this is only _reserved_ memory, not necessarily _committed_ memory
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${LDFLAGS} -Xlinker /STACK:16000000")
    else()
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -ggdb -g")
    endif()

    # additional c++ and linker flags for release mode for our projects
    if(CMAKE_BUILD_TYPE MATCHES "Release" OR CMAKE_BUILD_TYPE MATCHES "RelWithDebInfo")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3")
    endif()

    if(CMAKE_BUILD_TYPE MATCHES "RelWithDebInfo")
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} ${LDFLAGS} -Xlinker /debug")
    endif()

    # Fuzzing
    if(NOT STATICALLY_LINK AND ASAN_BUILD)
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fsanitize=address -O1")
        message(STATUS "Doing ASAN build")
    endif()

    # Warnings
    set(THIRDPARTY_IGNORED_WARNINGS "-Wno-everything")
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "GNU")
    message(STATUS "GCC detected - Setting Defaults")
    set(CMAKE_CXX_FLAGS
        "${CMAKE_CXX_FLAGS} \
        -Wall \
        -Winit-self \
        -ggdb \
        -Wextra \
        -Wno-cast-align \
        -Wcast-qual \
        -Wdisabled-optimization \
        -Wformat \
        -Wextra \
        -Woverloaded-virtual \
        -Wredundant-decls \
        -Wshadow \
        -Wsign-promo \
        -fdiagnostics-color=always \
        -mavx")

    # additional c++ flags for release mode for our projects
    if(CMAKE_BUILD_TYPE MATCHES "Release")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3")
    endif()
    set(THIRDPARTY_IGNORED_WARNINGS "-w")
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "AppleClang")
    message(STATUS "AppleClang detected - Setting Defaults")
    set(CMAKE_CXX_FLAGS
        "${CMAKE_CXX_FLAGS} \
        -Wall \
        -Winit-self \
        -ggdb \
        -Wextra \
        -Wno-cast-align \
        -Wcast-qual \
        -Wdisabled-optimization \
        -Wformat \
        -Wextra \
        -Woverloaded-virtual \
        -Wredundant-decls \
        -Wshadow \
        -Wsign-promo \
        -fdiagnostics-color=always"
        )

    # TODO - make a proper flag for arm compiling
    if (CMAKE_APPLE_SILICON_PROCESSOR STREQUAL "x86_64")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -mavx")
    else()
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -march=native -mcrc")
    endif()

    # additional c++ flags for release mode for our projects
    if(CMAKE_BUILD_TYPE MATCHES "Release")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -O3")
    endif()
    set(THIRDPARTY_IGNORED_WARNINGS "-w")
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -Wl,-stack_size -Wl,0x20000000")
elseif(CMAKE_CXX_COMPILER_ID STREQUAL "MSVC")
    message(STATUS "MSVC detected - Setting Defaults")

    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /EHsc /utf-8 /arch:AVX")

    # Increase stack size for windows, who's default is too low
    # Increase the reserved stack size for all threads to 16MB
    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} /STACK:16000000,16384")

    # additional c++ and linker flags for specific build types
    if(CMAKE_BUILD_TYPE MATCHES "Release" OR CMAKE_BUILD_TYPE MATCHES "RelWithDebInfo")
        set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} /O2 /Ob2")
    endif()

    if(CMAKE_BUILD_TYPE MATCHES "RelWithDebInfo")
        set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} /DEBUG")
    endif()
    set(THIRDPARTY_IGNORED_WARNINGS "/w")
else()
    message(FATAL_ERROR "Unknown Compiler '${CMAKE_CXX_COMPILER_ID}', get out!")
endif()

# Platform Specific Settings
if(WIN32)
    set(CMAKE_WINDOWS_EXPORT_ALL_SYMBOLS ON)
    set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
    set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
    set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
endif()

# Code Coverage
option(CODE_COVERAGE "Enable Code Coverage Compiler Flags" OFF)

if(CMAKE_CXX_COMPILER_ID STREQUAL "GNU" AND CODE_COVERAGE)
    include(CodeCoverage)
    append_coverage_compiler_flags()
    message(STATUS "Code Coverage build is enabled!")
endif()

function(build_third_party_lib dir_name target_name)
    add_subdirectory(third-party/${dir_name} EXCLUDE_FROM_ALL)
    # Convert all public include dirs to SYSTEM
    get_target_property(INCLUDES ${target_name} INTERFACE_INCLUDE_DIRECTORIES)
    if(INCLUDES)
        set_target_properties(${target_name} PROPERTIES
            INTERFACE_SYSTEM_INCLUDE_DIRECTORIES "${INCLUDES}"
        )
    endif()
endfunction()

# Dependencies and Libraries
# includes relative to top level jak-project folder
include_directories(./)

# build templating engine library
include_directories(SYSTEM third-party/inja)

# libcurl for HTTP requests
# Enable SSL Support, most URLs now-a-days use SSL!
# TODO - probably integrate with ZSTD since we have it already
set(CURL_USE_LIBSSH2 OFF)
set(CURL_ZLIB OFF)
# suddenly became enabled on macOS atleast, only needed for unicode URLs
# wasn't being properly statically linked
set(USE_LIBIDN2 OFF)
if(WIN32)
    set(CURL_USE_SCHANNEL ON) # native Windows SSL support
elseif(APPLE)
    set(CURL_USE_SECTRANSP ON) # native macOS SSL support
else()
    if(STATICALLY_LINK)
        set(OPENSSL_USE_STATIC_LIBS TRUE)
    endif()
    set(CURL_USE_OPENSSL ON) # not native, but seems to be the best choice for linux
endif()
include_directories(third-party/curl/include)
if(STATICALLY_LINK)
    build_third_party_lib(curl libcurl_static)
else()
    build_third_party_lib(curl libcurl_shared)
endif()

# build repl library
build_third_party_lib(replxx replxx)

# SQLite - Jak 2/3's built in editor
add_definitions(-DHAVE_USLEEP=1)
add_definitions(-DSQLITE_THREADSAFE=1)
add_definitions(-DSQLITE_ENABLE_JSON1)
add_definitions(-DSQLITE_ENABLE_RTREE)
build_third_party_lib(sqlite3 sqlite3)

# build tree-sitter parser
include_directories(third-party/tree-sitter/tree-sitter/lib/include)
build_third_party_lib(tree-sitter tree-sitter)

# native OS dialogs for error messages
build_third_party_lib(libtinyfiledialogs libtinyfiledialogs)

# build format library
include_directories(third-party/fmt/include)
build_third_party_lib(fmt fmt)

# build common library
add_subdirectory(common)

# build decompiler
add_subdirectory(decompiler)

# cubeb - audio
build_third_party_lib(cubeb cubeb)

# build LSP
add_subdirectory(lsp)

# build libco and zstd
build_third_party_lib(libco libco)
build_third_party_lib(zstd libzstd_static)

# build SDL
include(SDLOptions)
if(STATICALLY_LINK)
    build_third_party_lib(SDL SDL3-static)
else()
    build_third_party_lib(SDL SDL3-shared)
endif()

# build imgui
include_directories(third-party/glad/include)
include_directories(third-party/SDL/include)
build_third_party_lib(imgui imgui)

# build the game code in C++
add_subdirectory(game)

if(OG_ARM64_BOOT_STUB)
    # Phase 09 cross-build of the aarch64 gk binary. Both the custom command
    # and target live at root scope so the target's phony ninja name is `gk`
    # (no `game/` prefix) — that's the only thing that avoids a collision
    # with the CUSTOM_COMMAND output path build-arm64/game/gk.
    set(_OG_ARM64_AS /usr/bin/aarch64-linux-gnu-as)
    set(_OG_ARM64_LD /usr/bin/aarch64-linux-gnu-ld)
    set(_OG_ARM64_STUB_SRC ${CMAKE_SOURCE_DIR}/game/arm64_boot_stub.S)
    set(_OG_ARM64_STUB_OBJ ${CMAKE_BINARY_DIR}/game/arm64_boot_stub.o)
    set(_OG_ARM64_GK ${CMAKE_BINARY_DIR}/game/gk)
    file(MAKE_DIRECTORY ${CMAKE_BINARY_DIR}/game)
    add_custom_command(
        OUTPUT ${_OG_ARM64_GK}
        COMMAND ${_OG_ARM64_AS} -o ${_OG_ARM64_STUB_OBJ} ${_OG_ARM64_STUB_SRC}
        COMMAND ${_OG_ARM64_LD} -o ${_OG_ARM64_GK} ${_OG_ARM64_STUB_OBJ}
        DEPENDS ${_OG_ARM64_STUB_SRC}
        VERBATIM
    )
    add_custom_target(gk ALL DEPENDS ${_OG_ARM64_GK})
endif()

# build the compiler
add_subdirectory(goalc)

# build standalone tools
add_subdirectory(tools)

# build the gtest libraries
if(WIN32)
    set(gtest_force_shared_crt ON CACHE BOOL "" FORCE)
endif()

build_third_party_lib(googletest gtest)
include(GoogleTest)

# build tests
include(test/CMakeLists.txt)

# differential test harness for the x86 ↔ aarch64 port (phase 00)
add_subdirectory(test/diff)

# build lzokay library
build_third_party_lib(lzokay lzokay)

build_third_party_lib(stb_image stb_image)
# build draco library for tinygltf compression support
include_directories(third-party/draco/src)
add_subdirectory(third-party/draco)
add_compile_definitions(TINYGLTF_ENABLE_DRACO)
build_third_party_lib(tiny_gltf tiny_gltf)
build_third_party_lib(xdelta3 xdelta3)

# discord rich presence
include_directories(third-party/discord-rpc/include)
build_third_party_lib(discord-rpc discord-rpc)

# build zydis third party library for disassembling x86
# TODO - Once under CMake 3.13's policy CMP0077, override with `set()` instead
option(ZYDIS_BUILD_TOOLS "Zydis: Build tools" OFF)
option(ZYDIS_BUILD_EXAMPLES "Zydis: Build examples" OFF)

if(STATICALLY_LINK)
    message(STATUS "Statically linking zydis")
    option(ZYDIS_BUILD_SHARED_LIB "Zydis: Build shared library" OFF)
else()
    message(STATUS "dynamically linking zydis")
    option(ZYDIS_BUILD_SHARED_LIB "Zydis: Build shared library" ON)
endif()

build_third_party_lib(zydis Zydis)

# build capstone third party library for disassembling arm64 (codegen diff tool)
# Only the AArch64 decoder is needed; everything else is disabled to keep the
# build small. Normal variables are honored by capstone's option() calls under
# CMake policy CMP0077.
# NOT on Windows: capstone's C objects each emit MSVC intrinsic port-IO shims
# (__inbyte & co) under GNU-driver clang -> duplicate symbols at lld-link, and
# the codegen-diff tool that consumes it is a linux-side tool anyway
# (goalc/debugger/disassemble.cpp stubs decode_arm64 on _WIN32).
if(NOT WIN32)
set(CAPSTONE_ARCHITECTURE_DEFAULT OFF CACHE BOOL "" FORCE)
set(CAPSTONE_ARM64_SUPPORT ON CACHE BOOL "" FORCE)
set(CAPSTONE_BUILD_SHARED OFF CACHE BOOL "" FORCE)
set(CAPSTONE_BUILD_STATIC ON CACHE BOOL "" FORCE)
set(CAPSTONE_BUILD_TESTS OFF CACHE BOOL "" FORCE)
set(CAPSTONE_BUILD_CSTOOL OFF CACHE BOOL "" FORCE)
build_third_party_lib(capstone capstone-static)
# capstone uses directory-scoped include_directories internally and exposes no
# INTERFACE include dir, so attach one for consumers (e.g. the compiler lib).
target_include_directories(capstone-static SYSTEM INTERFACE
    ${CMAKE_CURRENT_SOURCE_DIR}/third-party/capstone/include)
# consumed by the (potentially shared) compiler lib, so it must be PIC.
set_target_properties(capstone-static PROPERTIES POSITION_INDEPENDENT_CODE ON)
endif()

# windows memory management lib
if(WIN32)
    build_third_party_lib(mman mman)
endif()
