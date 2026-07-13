# Grecharged-grass-precompute-mode: offline grass baker (desktop only).
# GrassBakeCore.cpp is GL-free by design so it compiles straight into this CLI.
add_executable(grass_bake main.cpp ../../game/graphics/opengl_renderer/GrassBakeCore.cpp)
target_link_libraries(grass_bake common fmt)
# Match the runtime build: no FP contraction, so the baked placement is bit-for-bit
# what the device scan would have produced.
set_source_files_properties(../../game/graphics/opengl_renderer/GrassBakeCore.cpp
        PROPERTIES COMPILE_OPTIONS "-ffp-contract=off")
