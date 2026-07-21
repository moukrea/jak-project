# Grecharged-lightprobes: offline light-probe baker (desktop only).
# ProbeBakeCore.cpp is GL-free by design so it compiles straight into this CLI.
add_executable(probe_bake main.cpp ../../game/graphics/opengl_renderer/ProbeBakeCore.cpp)
target_link_libraries(probe_bake common fmt)
# Match the runtime build: no FP contraction, so the baked probe grid is bit-for-bit what the
# device would compute from the same inputs.
set_source_files_properties(../../game/graphics/opengl_renderer/ProbeBakeCore.cpp
        PROPERTIES COMPILE_OPTIONS "-ffp-contract=off")
