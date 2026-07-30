# Grecharged-mesh-browser V2.3: offline CPU reference for the reticle pick (desktop only).
# Independent re-implementation of the runtime ray-triangle pick + row resolution, fed by the
# same fr3 + mesh_index files, so a harness can compare device picks 1:1.
add_executable(mb_pick_ref main.cpp)
target_link_libraries(mb_pick_ref common fmt)
