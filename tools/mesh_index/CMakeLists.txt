# Grecharged-mesh-browser: offline index exporter (desktop only). Distils a tess_sign per-level
# CSV into the compact mesh-browser index the game loads on demand. No dependency on the tess/PBR
# source owned by the parallel round — it only reads the CSV that tool already emits.
add_executable(mesh_index main.cpp)
