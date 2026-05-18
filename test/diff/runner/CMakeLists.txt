# goalc-diff-runner: CLI harness used by the goalc-diff ctest suite.
#
# Intentionally self-contained: no link to compiler/runtime libraries yet.
# Phase 00 ships only the scaffolding; later phases will extend this target
# to call into goalc directly (and into the future arm64 emitter).

add_executable(goalc-diff-runner runner.cpp)
set_target_properties(goalc-diff-runner PROPERTIES
    CXX_STANDARD 20
    CXX_STANDARD_REQUIRED ON
)
