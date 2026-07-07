# Phase C1 (autoport, bucket C): aarch64-linux cross-build of the
# OpenGOAL runtime into a real `gk` executable.
#
# Reached from the root CMakeLists.txt's `if(OG_LINUX_ARM64) ...
# add_subdirectory(game/linux-arm64) return() endif()` divert. Mirrors
# android/CMakeLists.txt's structure: cross-compile fmt + libco from
# the vendored third-party sources, compile a curated upstream subset
# of game/kernel + game/system + game/overlord + common/, link with
# honest abort-stubs for the graphics/sound/curl externs (since none
# of those have an aarch64-linux sysroot here yet).
#
# Out of scope for C1 (these are C2/C3/D's problems):
#   * SDL3, libcurl, discord-rpc, OpenGL — link-time satisfied by
#     linux_arm64_runtime_compat.cpp's abort stubs.
#   * jak1/kmachine.cpp + jak1/kboot.cpp — they pull in graphics
#     transitively. Same pattern Android uses.
#   * Reaching the title screen — that's C3.

set(JAK_ROOT "${CMAKE_CURRENT_LIST_DIR}/../..")
get_filename_component(JAK_ROOT "${JAK_ROOT}" ABSOLUTE)

# Generated revision header (the root CMakeLists writes this from the
# regular desktop path; we synthesise a placeholder when missing so the
# cross-build doesn't need the desktop tree to have run first).
if(NOT EXISTS "${JAK_ROOT}/common/versions/revision.h")
    file(WRITE "${JAK_ROOT}/common/versions/revision.h"
         "#define BUILT_TAG \"\"\n#define BUILT_SHA \"autoport-linux-arm64\"\n")
endif()

include_directories(
    "${JAK_ROOT}"
    "${JAK_ROOT}/third-party"
    "${JAK_ROOT}/game"
    "${JAK_ROOT}/third-party/fmt/include"
    # game/settings/settings.h includes SDL3/SDL.h transitively via gfx.h
    # and srpc.cpp's VBlank handler. We don't *link* SDL3 (no aarch64
    # sysroot here yet) — but the header is needed for the compile.
    # Honest abort stubs in linux_arm64_runtime_compat.cpp satisfy any
    # SDL_* references that survive the inliner.
    "${JAK_ROOT}/third-party/SDL/include"
)

# ---------------------------------------------------------------------------
# fmt — vendored, cross-built as a normal static lib.
# ---------------------------------------------------------------------------
set(FMT_INSTALL OFF CACHE BOOL "" FORCE)
set(FMT_TEST    OFF CACHE BOOL "" FORCE)
set(FMT_DOC     OFF CACHE BOOL "" FORCE)
add_subdirectory("${JAK_ROOT}/third-party/fmt" fmt_build EXCLUDE_FROM_ALL)

# ---------------------------------------------------------------------------
# libco — cooperative IOP thread switching. The vendored copy already
# selects the aarch64.c backend via #ifdef in libco.c.
# ---------------------------------------------------------------------------
add_subdirectory("${JAK_ROOT}/third-party/libco" libco_build EXCLUDE_FROM_ALL)
set_property(TARGET libco PROPERTY POSITION_INDEPENDENT_CODE ON)

# ---------------------------------------------------------------------------
# aarch64 trampoline — the upstream file uses Apple-as style `;` line
# comments and `;;` block separators. Both GNU as and clang's integrated
# assembler treat `;` as a statement separator, so rewrite to `//` first.
# Same transform tools/arm64-stress and android/ already do.
# ---------------------------------------------------------------------------
enable_language(ASM)
set(CMAKE_ASM_SOURCE_FILE_EXTENSIONS ${CMAKE_ASM_SOURCE_FILE_EXTENSIONS} s)

set(ASM_FUNCS_SRC "${JAK_ROOT}/game/kernel/asm_funcs_arm64.s")
set(ASM_FUNCS_OUT "${CMAKE_BINARY_DIR}/asm_funcs_arm64_gnu.s")
add_custom_command(
    OUTPUT "${ASM_FUNCS_OUT}"
    COMMAND sed -e "s|;;|//|g" -e "s|[[:space:]];[[:space:]]|  // |g" "${ASM_FUNCS_SRC}" > "${ASM_FUNCS_OUT}"
    DEPENDS "${ASM_FUNCS_SRC}"
    COMMENT "C1: rewriting macOS-style ;; comments in asm_funcs_arm64.s for GNU as"
    VERBATIM
)
set_source_files_properties("${ASM_FUNCS_OUT}" PROPERTIES
    LANGUAGE ASM
    GENERATED TRUE
)

# ---------------------------------------------------------------------------
# Kernel + common static library. Same curation as the Android build, but
# we get to compile common/log/log.cpp verbatim — glibc + a real terminal
# means fmt::color is fine, no logcat redirection needed.
# ---------------------------------------------------------------------------
add_library(linux_arm64_kernel STATIC
    # C1 compat layer — owns runtime globals that game/runtime.cpp owns
    # upstream, plus honest abort-stubs for the graphics/sound/discord/
    # curl externs the kernel + overlord call into.
    linux_arm64_runtime_compat.cpp

    # C3 direct-from-disk DGO loader — wraps jak1::link_and_exec over
    # objects parsed from an on-disk *.CGO file, bypassing IOP/Overlord/
    # RPC. The link engine itself is real upstream code.
    linux_arm64_direct_dgo.cpp

    # Common utilities — same subset Android picks.
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
    "${JAK_ROOT}/common/log/log.cpp"
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

    # Kernel jak1 — same subset Android uses (no kmachine/kboot here:
    # those pull graphics + discord + sce-libgraph).
    "${JAK_ROOT}/game/kernel/jak1/fileio.cpp"
    "${JAK_ROOT}/game/kernel/jak1/kdgo.cpp"
    "${JAK_ROOT}/game/kernel/jak1/klink.cpp"
    "${JAK_ROOT}/game/kernel/jak1/klisten.cpp"
    "${JAK_ROOT}/game/kernel/jak1/kprint.cpp"
    "${JAK_ROOT}/game/kernel/jak1/kscheme.cpp"
    "${JAK_ROOT}/game/kernel/jak1/ksound.cpp"

    # Kernel jak2 — additive for the --game jak2 qemu repro. Same
    # curation rationale as jak1: NO kmachine/kmachine_extras/kboot
    # (graphics + sqlite + discord + sce-libgraph), NO jak2 mips2c/font/
    # overlord/texture_remap. Missing jak2:: externs pulled by these 8
    # TUs are satisfied by honest abort/no-op stubs in
    # linux_arm64_runtime_compat.cpp.
    "${JAK_ROOT}/game/kernel/jak2/fileio.cpp"
    "${JAK_ROOT}/game/kernel/jak2/kdgo.cpp"
    "${JAK_ROOT}/game/kernel/jak2/klink.cpp"
    "${JAK_ROOT}/game/kernel/jak2/klisten.cpp"
    "${JAK_ROOT}/game/kernel/jak2/kprint.cpp"
    "${JAK_ROOT}/game/kernel/jak2/kscheme.cpp"
    "${JAK_ROOT}/game/kernel/jak2/ksound.cpp"
    "${JAK_ROOT}/game/kernel/jak2/kmalloc.cpp"

    # AArch64 trampoline — preprocessed to GNU as.
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

    # System threads + IOP fabric. Pure POSIX, compiles fine on glibc.
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

    # mips2c jak1 — the giant generated switch tables. Pure templates,
    # no external deps beyond kscheme + mips2c_table.h.
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
    # A37: real jak1 mips2c table (callback map + reg()/get() with the
    # AArch64 GOAL-heap trampoline). Replaces the get()->0 stub.
    "${JAK_ROOT}/game/mips2c/mips2c_table_jak1_arm64.cpp"
)

target_compile_features(linux_arm64_kernel PUBLIC cxx_std_20)
target_compile_options(linux_arm64_kernel PRIVATE
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
target_compile_definitions(linux_arm64_kernel PRIVATE
    NO_ASAN
    # OG_LINUX_ARM64 — guard for #ifdef'd compat shims (mostly in
    # linux_arm64_runtime_compat.cpp).
    OG_LINUX_ARM64=1
)
target_link_libraries(linux_arm64_kernel PUBLIC fmt::fmt libco)
set_target_properties(linux_arm64_kernel PROPERTIES
    POSITION_INDEPENDENT_CODE ON
    CXX_VISIBILITY_PRESET default
    VISIBILITY_INLINES_HIDDEN OFF
)

# ---------------------------------------------------------------------------
# gk executable. Entry point lives in linux_arm64_main.cpp — a slim shape
# that mirrors game/main.cpp's `goal_main` body without pulling in the
# desktop CLI11 / discord / gfx-test chain. Real upstream `exec_runtime`
# is still called.
# ---------------------------------------------------------------------------
add_executable(gk
    linux_arm64_main.cpp
)
target_compile_features(gk PRIVATE cxx_std_20)
target_compile_options(gk PRIVATE
    -fexceptions
    -fcxx-exceptions
    -Wall
    -Wno-unused-parameter
)
target_compile_definitions(gk PRIVATE OG_LINUX_ARM64=1)

# Force-link the whole kernel archive so the GOAL marker symbols stay in
# the binary's symbol table even when nothing in linux_arm64_main.cpp
# directly references them. The C1 validator greps nm --defined-only for
# `kmalloc`, `kscheme_init`, `klisten_init_globals`, etc.
target_link_libraries(gk PRIVATE
    -Wl,--whole-archive
    linux_arm64_kernel
    -Wl,--no-whole-archive
    -Wl,--no-gc-sections
    fmt::fmt
    libco
    pthread
    dl
    m
)

# Land the gk binary under build-arm64-linux/game/linux-arm64/gk.
set_target_properties(gk PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/game/linux-arm64"
)
