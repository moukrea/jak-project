# Grecharged-pbr-realtime-fusion: offline tessellation-factor audit (desktop only).
# lighting-legacy-purge 2026-09-11 : MeshSubdivide.cpp a quitte la librairie `common` (il ne doit plus etre compile dans le jeu). Les deux outils hors-jeu qui l'utilisent vraiment le compilent desormais eux-memes.
add_executable(tess_audit main.cpp "${CMAKE_SOURCE_DIR}/common/custom_data/MeshSubdivide.cpp")
# stb_image: --r28 decodes the real *_height.png with the SAME decoder the loader uses.
target_link_libraries(tess_audit common fmt stb_image)
