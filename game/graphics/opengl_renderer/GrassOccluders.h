#pragma once
#include <array>
#include <vector>

// OWNER ROUND#18 (Grecharged-grass-poc): per-frame world positions of ground-resting OBJECTS
// (crates, the warp-gate button) that the grass renderer must hide grass under. These objects are
// merc ACTORS — NOT TIE, NOT in the static level data — so the grass builder can't see them at level
// load. Merc2 captures their root-bone world position each frame into g_building; the grass renderer
// publishes (swaps building->published, clears building) once per frame and reads g_published to feed
// the grass shader's occlusion uniforms. A 1-frame lag is invisible (crates/button are static). Only
// active while the grass toggle is ON (OFF == stock, no capture).
namespace grass_occ {
// {world x, y, z (GOAL units, 4096 = 1 m), ground-contact radius (GOAL units)}
extern std::vector<std::array<float, 4>> g_building;
extern std::vector<std::array<float, 4>> g_published;
void add(float x, float y, float z, float r_world);  // Merc2 -> building (capped)
void publish();                                      // grass -> swap building into published
}  // namespace grass_occ
