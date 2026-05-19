# Phase 26 (autoport): goal_stress_arm64 — cross-built aarch64-linux ELF
# that runs the real GOAL kernel primitives under qemu-aarch64-static and
# emits observability counters (kheap-delta, symbols-interned, goal-calls)
# the phase-26 validator asserts on.
#
# This subdirectory is only reachable via the OG_ARM64_STRESS=ON branch in
# the top-level CMakeLists.txt — it is *not* added on the normal desktop
# build path. Configure with:
#   cmake -S . -B build-arm64-linux \
#         -DCMAKE_TOOLCHAIN_FILE=$PWD/cmake/aarch64-linux-toolchain.cmake \
#         -DCMAKE_BUILD_TYPE=Release
#
# Files we deliberately do NOT pull in:
#   * SDL/GLES/imgui/discord — no aarch64 sysroot libs and the harness has
#     --no-display semantics anyway (we never render).
#   * The full jak1 kernel/overlord/runtime — most of it transitively pulls
#     graphics + sound + network. Phase 28 will widen this list once the
#     dispatcher is live; for phase 26 we want the smallest set that lets
#     the trace hooks fire honestly.
#
# Files we DO link, and why each is non-stub:
#   * game/kernel/asm_funcs_arm64.s — the real AArch64 dispatcher
#     trampoline. call_goal_on_stack in this harness lands here and does
#     a genuine stack-switch + blr — that's what makes the goal-calls
#     counter mean something.
#   * game/kernel/common/runtime_trace.cpp — weak default trace hooks. The
#     harness binary's main.cpp provides the strong overrides; this file
#     is kept in the link so a *production* gk (no strong override) still
#     has the no-op symbols available.
#   * game/kernel/common/kmalloc.cpp — the real bump allocator. The trace
#     hook fires on every kheap.current move.
#   * game/kernel/common/kscheme.cpp — the real call_goal/call_goal_on_stack
#     wrappers. These call the trace hook *and* hand off to the asm
#     trampoline above.

# Enable ASM language for the AArch64 trampoline. The top-level project()
# call only enables C and CXX by default; calling enable_language(ASM)
# here from a subdir is the supported way to add it without re-declaring
# project().
enable_language(ASM)

set(CMAKE_POSITION_INDEPENDENT_CODE ON)

set(JAK_ROOT "${CMAKE_CURRENT_LIST_DIR}/../..")
get_filename_component(JAK_ROOT "${JAK_ROOT}" ABSOLUTE)

# common/versions/versions.cpp depends on a generated revision.h; for the
# stress harness we don't actually link versions.cpp, but if any future
# inclusion grows, the header must exist. The desktop build emits this
# file too; we synthesize a placeholder only when missing.
if(NOT EXISTS "${JAK_ROOT}/common/versions/revision.h")
    file(WRITE "${JAK_ROOT}/common/versions/revision.h"
         "#define BUILT_TAG \"\"\n#define BUILT_SHA \"autoport-arm64-stress\"\n")
endif()

include_directories(
    "${JAK_ROOT}"
    "${JAK_ROOT}/third-party"
    "${JAK_ROOT}/third-party/fmt/include"
)

# The AArch64 trampoline file uses GAS syntax (.global / .align). It is
# already gated by ARM64_ARCH in game/CMakeLists.txt with a `-arch arm64 -g`
# flag tailored for Apple as(1); we don't want that here. Compile the .s
# file as plain ASM with the cross clang.
set(ASM_TRAMPOLINE_SRC "${JAK_ROOT}/game/kernel/asm_funcs_arm64.s")
# Upstream uses Apple-as-style `;` / `;;` line-comments. Both clang's
# integrated assembler (treats `;` as statement separator) and the
# Fedora aarch64-linux-gnu-as (treats `//` as the line comment) reject
# those. Pre-process the file by rewriting every `;` to `//` — every
# occurrence is already a comment (verified by grep), so the transform
# is a clean syntactic rename.
set(ASM_TRAMPOLINE_GEN "${CMAKE_CURRENT_BINARY_DIR}/asm_funcs_arm64_gnu.S")
add_custom_command(
    OUTPUT "${ASM_TRAMPOLINE_GEN}"
    COMMAND sed -e "s,;,//,g" "${ASM_TRAMPOLINE_SRC}" > "${ASM_TRAMPOLINE_GEN}"
    DEPENDS "${ASM_TRAMPOLINE_SRC}"
    COMMENT "phase-26: normalize asm_funcs_arm64.s comments for GNU as / clang IAS"
    VERBATIM
)
set_source_files_properties("${ASM_TRAMPOLINE_GEN}" PROPERTIES
    LANGUAGE ASM
    GENERATED TRUE
)

add_executable(goal_stress_arm64
    main.cpp
    stubs.cpp
    "${JAK_ROOT}/game/kernel/common/runtime_trace.cpp"
    "${JAK_ROOT}/game/kernel/common/kmalloc.cpp"
    "${JAK_ROOT}/game/kernel/common/kscheme.cpp"
    "${ASM_TRAMPOLINE_GEN}"
)

target_compile_options(goal_stress_arm64 PRIVATE
    -fexceptions
    -fcxx-exceptions
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

target_compile_definitions(goal_stress_arm64 PRIVATE
    NO_ASAN
    NO_FMT_USE_STD
    # ASSERT() expands to a call to private_assert_failed in common/util/Assert.h.
    # We don't link Assert.cpp (it pulls in logging/exception machinery). Define
    # NO_ASSERT to compile every ASSERT down to (void)0, matching what
    # ndebug-style production builds do anyway.
    NO_ASSERT
)

# The validator launches the binary via qemu-aarch64-static. Mark the
# output so the find $BUILD_DIR -name goal_stress_arm64 picks it up at
# any depth.
set_target_properties(goal_stress_arm64 PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/tools/arm64-stress"
)
