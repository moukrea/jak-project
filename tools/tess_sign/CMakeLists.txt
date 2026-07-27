# Grecharged-pbr-realtime-fusion: offline TESS SIGN TEST (desktop only).
# A CPU port of tfrag3_tess.tesc/.tese that grades the SIGN of the tessellation displacement.
add_executable(tess_sign main.cpp)
target_link_libraries(tess_sign common fmt)
