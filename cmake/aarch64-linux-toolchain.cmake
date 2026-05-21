# Phase 26 (autoport): CMake toolchain file for cross-compiling
# goal_stress_arm64 to aarch64-linux (glibc), executable under
# qemu-aarch64-static.
#
# Why clang+lld over the Fedora aarch64-linux-gnu-g++:
#   * Fedora's cross GCC is built with --without-headers --disable-threads
#     and the sysroot rpm (sysroot-aarch64-fc43-glibc) lays files out under
#     /usr/aarch64-redhat-linux/sys-root/fc43/, NOT under
#     /usr/aarch64-linux-gnu/lib/ where the phase-26 validator expects
#     ld-linux-aarch64.so.1. So the Fedora cross GCC cannot link
#     C++/threads at all on a stock host.
#   * Debian's libstdc++/libc/gcc-cross packages place the same files in
#     the Debian-style /usr/aarch64-linux-gnu/{include,lib}/ layout the
#     validator already grew up around. Installing them once via a
#     throwaway debian:bookworm container and mirroring to host gives
#     clang a complete aarch64 sysroot.
#   * clang accepts --target=aarch64-linux-gnu out of the box, and pairing
#     it with the LLVM lld linker avoids version mismatch issues with the
#     Fedora binutils ld which rejects Debian's libstdc++ crtbeginS.o due
#     to a relocation type mismatch.
#
# This toolchain is intentionally NOT generic — it expects the very
# specific Debian-mirrored layout the phase-26 implementation set up
# (see .autoport/logs for the docker install command). Re-installing
# from scratch on a different host requires running that command again.

set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_SYSTEM_PROCESSOR aarch64)

# Use the host's clang and lld; --target= does the cross-compile work.
find_program(CMAKE_C_COMPILER NAMES clang)
find_program(CMAKE_CXX_COMPILER NAMES clang++)
find_program(_OG_ARM64_LLD NAMES ld.lld)
if(NOT _OG_ARM64_LLD)
    message(FATAL_ERROR "ld.lld not found — install lld package")
endif()

set(_OG_ARM64_SYSROOT_INC "/usr/aarch64-linux-gnu/include")
set(_OG_ARM64_SYSROOT_CXX_INC "/usr/aarch64-linux-gnu/include/c++/12")
set(_OG_ARM64_SYSROOT_CXX_TGT_INC "/usr/aarch64-linux-gnu/include/c++/12/aarch64-linux-gnu")
set(_OG_ARM64_LIB_DIR "/usr/aarch64-linux-gnu/lib")
set(_OG_ARM64_GCC_DIR "/usr/aarch64-linux-gnu/lib/gcc-cross/12")

set(_OG_ARM64_TARGET_FLAGS
    "--target=aarch64-linux-gnu -mlittle-endian \
    -nostdinc -nostdinc++ \
    -isystem ${_OG_ARM64_SYSROOT_CXX_INC} \
    -isystem ${_OG_ARM64_SYSROOT_CXX_TGT_INC} \
    -isystem ${_OG_ARM64_SYSROOT_INC} \
    -isystem /usr/lib/clang/21/include")

set(CMAKE_C_FLAGS_INIT   "${_OG_ARM64_TARGET_FLAGS}")
set(CMAKE_CXX_FLAGS_INIT "${_OG_ARM64_TARGET_FLAGS}")
set(CMAKE_ASM_FLAGS_INIT "--target=aarch64-linux-gnu -mlittle-endian")

# Tell clang to use lld and the right startup objects + libs. We force
# -nostdlib then add Scrt1.o + crti.o + crtbeginS.o + crtendS.o + crtn.o
# explicitly so clang doesn't fall back to /usr/lib64 host x86 objects.
set(_OG_ARM64_LINKER_FLAGS
    "--target=aarch64-linux-gnu -fuse-ld=lld \
    -nostdlib -nodefaultlibs -nostartfiles \
    ${_OG_ARM64_LIB_DIR}/Scrt1.o \
    ${_OG_ARM64_LIB_DIR}/crti.o \
    ${_OG_ARM64_GCC_DIR}/crtbeginS.o \
    -L${_OG_ARM64_GCC_DIR} -L${_OG_ARM64_LIB_DIR} \
    -Wl,-dynamic-linker,/lib/ld-linux-aarch64.so.1 \
    -lstdc++ -lm -lc -lpthread -lgcc_s -lgcc \
    -ldl -lrt \
    ${_OG_ARM64_GCC_DIR}/crtendS.o \
    ${_OG_ARM64_LIB_DIR}/crtn.o")

set(CMAKE_EXE_LINKER_FLAGS_INIT    "${_OG_ARM64_LINKER_FLAGS}")
set(CMAKE_SHARED_LINKER_FLAGS_INIT "${_OG_ARM64_LINKER_FLAGS}")

# Don't search the host /usr for anything; only the explicit -isystem /
# -L paths we set above.
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
set(CMAKE_FIND_ROOT_PATH "/usr/aarch64-linux-gnu")

# Pick the right cross-build target up-front. The toolchain itself is
# target-agnostic: it only configures the cross compiler + sysroot. Two
# downstream consumers gate on configure-time options:
#
#   OG_ARM64_STRESS  -> tools/arm64-stress/   (phase 26 / B2 — the qemu
#                       decode-stress harness, goal_stress_arm64)
#   OG_LINUX_ARM64   -> game/linux-arm64/     (bucket C — the real gk
#                       cross-build that boots under qemu-aarch64-static)
#
# The earlier revision unconditionally forced OG_ARM64_STRESS=ON in the
# cache, which made this toolchain unusable for anything else. Bucket C
# (phase C1) needs OG_LINUX_ARM64 to win, so the default is now opt-in:
#   * Pass -DOG_LINUX_ARM64=ON   -> game/linux-arm64/ subdir.
#   * Pass -DOG_ARM64_STRESS=ON  -> tools/arm64-stress/ subdir.
# If neither is passed the root CMakeLists.txt falls through to the
# desktop path (which will fail on this cross toolchain — that's the
# honest signal the caller forgot to pick a target).
