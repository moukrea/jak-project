# Phase D1 (autoport, bucket D): Android NDK cross-build of `gk` into
# a Bionic-linked aarch64 executable.
#
# This mirrors game/linux-arm64/CMakeLists.txt — same upstream kernel /
# overlord / system / mips2c source files, same fmt + libco vendored
# third-party deps, same --whole-archive force-link so GOAL marker
# symbols survive --gc-sections. The two builds diverge only in:
#
#   * Toolchain — NDK clang via android.toolchain.cmake (set by the
#     forwarder cmake/android-arm64-toolchain.cmake before this
#     subdir is added).
#   * Compat layer — android_arm64_runtime_compat.cpp routes lg::*
#     logging through __android_log_print; the Bionic-vs-glibc shims
#     for pthread_setname_np / mallinfo / execinfo / xdbg live in a
#     separate file (android_arm64_bionic_shims.cpp).
#   * Link libs — Bionic system libs (log, android, dl, m). pthread
#     and rt are folded into libc on Bionic; do not list them.
#
# Out of scope (later bucket D phases own these):
#   * SDL3 / GLES / OpenSLES — D2 wires the renderer + audio surface.
#   * JNI bridge to MainActivity / SDLActivity — D3 wires the
#     SurfaceView via SDL3 Android driver.
#   * APK packaging that bundles this gk binary — D4 ships the APK.

set(JAK_ROOT "${CMAKE_CURRENT_LIST_DIR}/../..")
get_filename_component(JAK_ROOT "${JAK_ROOT}" ABSOLUTE)

# Generated revision header (root CMakeLists writes this on the desktop
# path; the cross-build can run before a desktop build exists). Use a
# placeholder so the kernel sources resolve common/versions/revision.h.
if(NOT EXISTS "${JAK_ROOT}/common/versions/revision.h")
    file(WRITE "${JAK_ROOT}/common/versions/revision.h"
         "#define BUILT_TAG \"\"\n#define BUILT_SHA \"autoport-android-arm64\"\n")
endif()

include_directories(
    "${JAK_ROOT}"
    "${JAK_ROOT}/third-party"
    "${JAK_ROOT}/game"
    "${JAK_ROOT}/third-party/fmt/include"
    # game/settings/settings.h transitively pulls SDL3/SDL.h via gfx.h
    # and srpc.cpp's VBlank handler. We don't *link* SDL3 in bucket D1
    # (that's D3) — but the header is still needed for compile-time
    # type resolution. Honest abort stubs in android_arm64_runtime_compat
    # satisfy any SDL_* references that survive the inliner.
    "${JAK_ROOT}/third-party/SDL/include"
)

# ---------------------------------------------------------------------------
# fmt — vendored, cross-built via NDK clang. Same as linux-arm64.
# ---------------------------------------------------------------------------
set(FMT_INSTALL OFF CACHE BOOL "" FORCE)
set(FMT_TEST    OFF CACHE BOOL "" FORCE)
set(FMT_DOC     OFF CACHE BOOL "" FORCE)
add_subdirectory("${JAK_ROOT}/third-party/fmt" fmt_build EXCLUDE_FROM_ALL)

# ---------------------------------------------------------------------------
# libco — cooperative IOP thread switching. The vendored copy's libco.c
# #ifdef-selects the aarch64 backend automatically.
# ---------------------------------------------------------------------------
add_subdirectory("${JAK_ROOT}/third-party/libco" libco_build EXCLUDE_FROM_ALL)
set_property(TARGET libco PROPERTY POSITION_INDEPENDENT_CODE ON)

# ---------------------------------------------------------------------------
# aarch64 trampoline — upstream `asm_funcs_arm64.s` uses Apple-style `;;`
# block comments; sed rewrites them to GNU `//` before passing to the NDK
# assembler. Same preprocess linux-arm64 + android/ both use.
# ---------------------------------------------------------------------------
enable_language(ASM)
set(CMAKE_ASM_SOURCE_FILE_EXTENSIONS ${CMAKE_ASM_SOURCE_FILE_EXTENSIONS} s)

set(ASM_FUNCS_SRC "${JAK_ROOT}/game/kernel/asm_funcs_arm64.s")
set(ASM_FUNCS_OUT "${CMAKE_BINARY_DIR}/asm_funcs_arm64_gnu.s")
add_custom_command(
    OUTPUT "${ASM_FUNCS_OUT}"
    COMMAND sed -e "s|;;|//|g" -e "s|[[:space:]];[[:space:]]|  // |g" "${ASM_FUNCS_SRC}" > "${ASM_FUNCS_OUT}"
    DEPENDS "${ASM_FUNCS_SRC}"
    COMMENT "D1: rewriting macOS-style ;; comments in asm_funcs_arm64.s for GNU as"
    VERBATIM
)
set_source_files_properties("${ASM_FUNCS_OUT}" PROPERTIES
    LANGUAGE ASM
    GENERATED TRUE
)

# ---------------------------------------------------------------------------
# Kernel + common static library. Same source list as game/linux-arm64/
# (and same curation rationale — see linux-arm64/CMakeLists.txt for the
# per-file justifications). Bionic differs in libc surface, not in C++,
# so the same upstream files build cleanly here.
# ---------------------------------------------------------------------------
add_library(android_arm64_kernel STATIC
    # D1 compat layer — runtime globals + lg::* routing + honest no-ops
    # for the graphics/sound/discord/curl externs the kernel/overlord
    # call into.
    android_arm64_runtime_compat.cpp

    # D1 Bionic-vs-glibc shims — strong-symbol implementations of the
    # entry points where Bionic and glibc actually differ in interface
    # (pthread_setname_np 1-arg form, execinfo absence, xdbg, mallinfo).
    android_arm64_bionic_shims.cpp

    # Common utilities — same subset linux-arm64 + android/ both pick.
    "${JAK_ROOT}/common/util/Assert.cpp"
    "${JAK_ROOT}/common/util/Timer.cpp"
    "${JAK_ROOT}/common/util/BitUtils.cpp"
    "${JAK_ROOT}/common/util/crc32.cpp"
    "${JAK_ROOT}/common/util/FileUtil.cpp"
    "${JAK_ROOT}/common/util/string_util.cpp"
    "${JAK_ROOT}/common/util/os.cpp"
    "${JAK_ROOT}/common/util/print_float.cpp"
    "${JAK_ROOT}/common/util/dgo_util.cpp"
    "${JAK_ROOT}/common/util/diff.cpp"
    "${JAK_ROOT}/common/util/unicode_util.cpp"
    "${JAK_ROOT}/common/util/term_util.cpp"
    "${JAK_ROOT}/common/util/json_util.cpp"
    # NOTE: common/log/log.cpp excluded — routes via fmt::color → stdout
    # (dead on Android). android_arm64_runtime_compat.cpp owns the entire
    # public lg:: API and routes through __android_log_print.
    "${JAK_ROOT}/common/dma/dma.cpp"
    "${JAK_ROOT}/common/dma/dma_copy.cpp"
    "${JAK_ROOT}/common/dma/gs.cpp"
    "${JAK_ROOT}/common/audio/audio_formats.cpp"
    "${JAK_ROOT}/common/versions/versions.cpp"
    "${JAK_ROOT}/common/cross_sockets/XSocket.cpp"
    "${JAK_ROOT}/common/cross_sockets/XSocketServer.cpp"
    "${JAK_ROOT}/common/cross_sockets/XSocketClient.cpp"

    # Kernel common — full subset, the meat of GOAL.
    "${JAK_ROOT}/game/kernel/common/fileio.cpp"
    "${JAK_ROOT}/game/kernel/common/kboot.cpp"
    "${JAK_ROOT}/game/kernel/common/kdgo.cpp"
    "${JAK_ROOT}/game/kernel/common/kdsnetm.cpp"
    "${JAK_ROOT}/game/kernel/common/klink.cpp"
    "${JAK_ROOT}/game/kernel/common/klisten.cpp"
    "${JAK_ROOT}/game/kernel/common/kmalloc.cpp"
    "${JAK_ROOT}/game/kernel/common/kmemcard.cpp"
    "${JAK_ROOT}/game/kernel/common/kprint.cpp"
    "${JAK_ROOT}/game/kernel/common/kscheme.cpp"
    "${JAK_ROOT}/game/kernel/common/ksocket.cpp"
    "${JAK_ROOT}/game/kernel/common/ksound.cpp"
    "${JAK_ROOT}/game/kernel/common/runtime_trace.cpp"

    # Kernel jak1 — same subset linux-arm64 + android/ both pick
    # (kmachine + kboot excluded: they pull graphics + discord + sce).
    "${JAK_ROOT}/game/kernel/jak1/fileio.cpp"
    "${JAK_ROOT}/game/kernel/jak1/kdgo.cpp"
    "${JAK_ROOT}/game/kernel/jak1/klink.cpp"
    "${JAK_ROOT}/game/kernel/jak1/klisten.cpp"
    "${JAK_ROOT}/game/kernel/jak1/kprint.cpp"
    "${JAK_ROOT}/game/kernel/jak1/kscheme.cpp"
    "${JAK_ROOT}/game/kernel/jak1/ksound.cpp"

    # AArch64 trampoline (preprocessed to GNU as).
    "${ASM_FUNCS_OUT}"

    # SCE stubs — pure header impls, minimal deps.
    "${JAK_ROOT}/game/sce/stubs.cpp"
    "${JAK_ROOT}/game/sce/iop.cpp"
    "${JAK_ROOT}/game/sce/deci2.cpp"
    "${JAK_ROOT}/game/sce/libcdvd_ee.cpp"
    "${JAK_ROOT}/game/sce/libdma.cpp"
    "${JAK_ROOT}/game/sce/libscf.cpp"
    "${JAK_ROOT}/game/sce/sif_ee.cpp"
    "${JAK_ROOT}/game/sce/sif_ee_memcard.cpp"

    # System threads + IOP fabric. Pure POSIX, compiles fine on Bionic.
    "${JAK_ROOT}/game/system/SystemThread.cpp"
    "${JAK_ROOT}/game/system/IOP_Kernel.cpp"
    "${JAK_ROOT}/game/system/iop_thread.cpp"
    "${JAK_ROOT}/game/system/Deci2Server.cpp"

    # Overlord (common + jak1). Pure C++ with minimal deps.
    "${JAK_ROOT}/game/overlord/common/dma.cpp"
    "${JAK_ROOT}/game/overlord/common/fake_iso.cpp"
    "${JAK_ROOT}/game/overlord/common/iso.cpp"
    "${JAK_ROOT}/game/overlord/common/iso_api.cpp"
    "${JAK_ROOT}/game/overlord/common/isocommon.cpp"
    "${JAK_ROOT}/game/overlord/common/overlord.cpp"
    "${JAK_ROOT}/game/overlord/common/sbank.cpp"
    "${JAK_ROOT}/game/overlord/common/soundcommon.cpp"
    "${JAK_ROOT}/game/overlord/common/srpc.cpp"
    "${JAK_ROOT}/game/overlord/common/ssound.cpp"
    "${JAK_ROOT}/game/overlord/jak1/dma.cpp"
    "${JAK_ROOT}/game/overlord/jak1/fake_iso.cpp"
    "${JAK_ROOT}/game/overlord/jak1/iso.cpp"
    "${JAK_ROOT}/game/overlord/jak1/iso_api.cpp"
    "${JAK_ROOT}/game/overlord/jak1/iso_queue.cpp"
    "${JAK_ROOT}/game/overlord/jak1/isocommon.cpp"
    "${JAK_ROOT}/game/overlord/jak1/overlord.cpp"
    "${JAK_ROOT}/game/overlord/jak1/ramdisk.cpp"
    "${JAK_ROOT}/game/overlord/jak1/srpc.cpp"
    "${JAK_ROOT}/game/overlord/jak1/ssound.cpp"
    "${JAK_ROOT}/game/overlord/jak1/stream.cpp"

    # mips2c jak1 — same subset linux-arm64 picks.
    "${JAK_ROOT}/game/mips2c/jak1_functions/bones.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/collide_cache.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/collide_edge_grab.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/collide_func.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/collide_mesh.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/collide_probe.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/draw_string.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/generic_effect.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/generic_effect2.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/generic_merc.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/generic_tie.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/joint.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/merc_blend_shape.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/ocean_vu0.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/ocean.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/ripple.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/shadow.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/sky_tng.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/sparticle_launcher.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/sparticle.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/test_func.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/texture.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/tfrag.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/tie_methods.cpp"
    "${JAK_ROOT}/game/mips2c/jak1_functions/time_of_day.cpp"
)

target_compile_features(android_arm64_kernel PUBLIC cxx_std_20)
target_compile_options(android_arm64_kernel PRIVATE
    -fexceptions
    -fcxx-exceptions
    -fdiagnostics-color=always
    -Wall
    -Wno-unused-parameter
    -Wno-sign-compare
    -Wno-format-security
    -Wno-unused-function
    -Wno-unused-variable
    -Wno-unused-but-set-variable
    -Wno-pedantic
    -Wno-deprecated-declarations
)
target_compile_definitions(android_arm64_kernel PRIVATE
    NO_ASAN
    # OG_ANDROID_ARM64 — guard for #ifdef'd compat shims (the runtime_compat
    # + bionic_shims layers test for it where needed).
    OG_ANDROID_ARM64=1
)
target_link_libraries(android_arm64_kernel PUBLIC fmt::fmt libco)
set_target_properties(android_arm64_kernel PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    CXX_VISIBILITY_PRESET default
    VISIBILITY_INLINES_HIDDEN OFF
)

# ---------------------------------------------------------------------------
# gk executable. Entry point lives in android_arm64_main.cpp — a slim
# banner-and-exit that proves the executable links cleanly against
# Bionic. D2+ phases extend this with the kernel-init driver.
# ---------------------------------------------------------------------------
add_executable(gk
    android_arm64_main.cpp
)
target_compile_features(gk PRIVATE cxx_std_20)
target_compile_options(gk PRIVATE
    -fexceptions
    -fcxx-exceptions
    -Wall
    -Wno-unused-parameter
)
target_compile_definitions(gk PRIVATE OG_ANDROID_ARM64=1)

# Force-link the whole kernel archive so the GOAL marker symbols stay in
# the binary's symbol table even when nothing in android_arm64_main.cpp
# directly references them. The D1 validator greps nm --defined-only for
# kmalloc, init_output, klisten_init_globals, etc.
target_link_libraries(gk PRIVATE
    -Wl,--whole-archive
    android_arm64_kernel
    -Wl,--no-whole-archive
    -Wl,--no-gc-sections
    fmt::fmt
    libco
    # Bionic system libs. Note: pthread + rt are folded into libc on
    # Bionic; listing them would produce a "library not found" linker
    # error. dl + m are separate libraries the kernel touches
    # (dlsym + ::sin / ::cos / etc. in scalar floats).
    log       # Android log: __android_log_print used by bionic_shims +
              # runtime_compat for lg::* routing.
    android   # Android NDK helpers (asset manager, configuration).
    dl        # dlopen/dlsym — used by the listener-loader path.
    m         # libm — math.h symbols the upstream kernel calls.
)

# Land the gk binary at build-arm64-android/game/android-arm64/gk.
set_target_properties(gk PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/game/android-arm64"
)
