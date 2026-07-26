# Grecharged-pbr-realtime-fusion: offline tessellation-factor audit (desktop only).
add_executable(tess_audit main.cpp)
# stb_image: --r28 decodes the real *_height.png with the SAME decoder the loader uses.
target_link_libraries(tess_audit common fmt stb_image)
