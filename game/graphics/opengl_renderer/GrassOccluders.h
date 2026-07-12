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
//
// OWNER Q&A 2026-07-12: TWO categories. STATIC unbreakable actors (warp-gate button, blue eco valve)
// are CULLED (grass hidden under them). BREAKABLE actors (crates, scarecrows) are TRAMPLED (grass
// flattened like Jak's footstep, NOT hidden) — so when the object is broken the grass springs back.
// OWNER ROUND#21: the TRAMPLE list is no longer a raw per-frame swap. Because it is rebuilt from
// Merc2 draws every frame, a BROKEN crate vanished from one frame to the next and the grass under it
// snapped upright instantly — the same jarring pop the owner flagged on Jak's jump. publish(dt) now
// folds the frame's captures into a persistent per-object strength that eases IN (~0.25 s) when an
// object is (re)captured and OUT (~0.6 s) after it disappears, published alongside the positions.
namespace grass_occ {
// {world x, y, z (GOAL units, 4096 = 1 m), ground-contact radius (GOAL units)}
extern std::vector<std::array<float, 4>> g_building;        // CULL (static unbreakable actors)
extern std::vector<std::array<float, 4>> g_published;
extern std::vector<std::array<float, 4>> g_tramp_building;  // TRAMPLE (breakable actors -> flatten)
extern std::vector<std::array<float, 4>> g_tramp_published;
extern std::vector<float> g_tramp_strength;                  // ROUND#21: eased 0..1 per published entry
void add(float x, float y, float z, float r_world);          // Merc2 -> CULL building (capped)
void add_trample(float x, float y, float z, float r_world);  // Merc2 -> TRAMPLE building (capped)
void publish(float dt);  // grass -> swap CULL, ease TRAMPLE strengths (dt = seconds since last call)
}  // namespace grass_occ
