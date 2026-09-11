#pragma once

// ROUND 20 — the owner's CHECKERBOARD verification method, IN-BUILD.
//
// The owner verified the PBR displacement pipeline by hand-pushing checkerboard PNGs over the
// bundled recharged textures (base + _normal/_roughness/_height) and comparing the size of a
// PAINTED square against the size of a DISPLACED block. That test is the only objective way to
// tell "real displacement" from "a glorified bump map", and it should not require pushing files.
//
// This module synthesises the same pattern procedurally, so the whole method is one property away:
//   debug.opengoal.pbr.testpattern (env OG_PBR_TESTPATTERN):
//     0 = off (default)
//     1 = substitute on materials that ALREADY have PBR maps
//     2 = substitute on EVERY texture
//   debug.opengoal.pbr.testsquares (env OG_PBR_TESTSQUARES): squares per texture TILE (default 8).

#include <vector>

#include "common/common_types.h"

namespace pbr_testpattern {

// 0 = off, 1 = substitute on materials that ALREADY have PBR maps, 2 = substitute on EVERY texture.
int mode();
// True for the FLAT-base modes (3 and 4): same maps, but the base colour carries no pattern, so a
// period measured on screen can only have come from the geometry / the maps.
bool flat_base();

// squares per texture TILE (default 8).
int squares_per_tile();

// The three shared debug maps (normal, roughness, height). Generated once on first call; requires a
// current GL context. Shared by every material — never delete these ids.
struct SharedMaps {
  u32 normal_tex = 0;
  u32 rough_tex = 0;
  u32 height_tex = 0;
};
const SharedMaps& shared_maps();

// true if gl_id is one of the shared debug maps (so the loader's stale-id free loop skips them).
bool owns(u32 gl_id);

// the checker BASE colour, dim x dim RGBA8 (byte order R,G,B,A).
void make_base_rgba(std::vector<u8>& out, int dim);

}  // namespace pbr_testpattern
