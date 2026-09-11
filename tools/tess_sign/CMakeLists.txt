# Grecharged-pbr-realtime-fusion: offline TESS SIGN TEST (desktop only).
# A CPU port of tfrag3_tess.tesc/.tese that grades the SIGN of the tessellation displacement.
# lighting-legacy-purge 2026-09-11 : MeshSubdivide.cpp a quitte la librairie `common` (il ne doit plus etre compile dans le jeu). Les deux outils hors-jeu qui l'utilisent vraiment le compilent desormais eux-memes.
add_executable(tess_sign main.cpp "${CMAKE_SOURCE_DIR}/common/custom_data/MeshSubdivide.cpp")
target_link_libraries(tess_sign common fmt)
