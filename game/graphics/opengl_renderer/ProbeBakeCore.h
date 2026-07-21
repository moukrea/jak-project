#pragma once
// Grecharged-lightprobes: OFFLINE, GL-free light-probe baker core.
//
// Reads a decoded tfrag3::Level (the STOCK level fr3, e.g. village1) and produces a LOCAL
// environment-probe grid:
//   - a regular 3D irradiance-volume grid (cells baked only where stock geometry exists),
//   - per cell per TOD: L2 irradiance SH (9 coeffs x RGB), in the SAME Y-basis + Al cosine
//     convolution the runtime shader rt_sh_ambient() already evaluates (drop-in local ambient),
//   - sparse per-probe prefiltered reflection cubemaps (PBR IBL / metal / water / Precursor).
//
// The per-probe environment is CAPTURED programmatically by binning the nearby STOCK-baked-lit
// surface radiance into a small cubemap (closest sample per texel = occlusion) + sky/ground fill.
// The baked vertex color is the full lit result (BOTH suns included) => a suns-included HDRI of the
// world, captured with NO manual placement. Interiors are auto-detected by a ceiling ray.
//
// GL-free by design so it compiles straight into both the desktop CLI (tools/probe_bake) and the
// game runtime (for load), exactly like GrassBakeCore.

#include <cstdint>
#include <string>
#include <vector>

#include "common/common_types.h"

namespace tfrag3 {
struct Level;
}

namespace probe_bake {

constexpr u32 PRB_MAGIC = 0x31425250;  // 'PRB1'
constexpr u32 PRB_FORMAT_VERSION = 1;
constexpr int PRB_NUM_TOD = 8;   // time-of-day keyframe palettes
constexpr int PRB_NUM_SH = 9;    // L2 real spherical harmonics
constexpr int PRB_CUBE_FACE = 8; // reflection cube face size (mip0)

struct BakeParams {
  float cell_m = 4.0f;            // grid cell size, meters
  float gather_radius_m = 16.0f;  // surface samples within this radius feed a probe
  int min_samples = 6;            // a cell is baked only if it has >= this many nearby samples
  float ceiling_probe_m = 18.0f;  // an up-ray hitting a down-facing tri within this => INTERIOR
  int refl_exterior_stride = 4;   // reflection anchor every Nth valid exterior cell (interiors: all)
  float probe_gain = 1.0f;        // global irradiance scale (device-tunable)
  float sky_gain = 1.0f;          // sky/ground fill scale (device-tunable)
};

// One baked grid cell (SPARSE storage: only baked cells are kept).
struct ProbeCell {
  s16 ix = 0, iy = 0, iz = 0;  // grid coords
  u8 interior = 0;             // 1 = detected indoors (ceiling overhead)
  u8 refl_anchor = 0;          // 1 = this cell has a reflection cube in ProbeGrid::refl
  float openness = 0.f;        // 0..1 sky visibility (diagnostic)
  // Al-cosine-convolved L2 SH, Y-basis: shader does Sum(sh[c]*Y_c(n)) => local ambient radiance.
  float sh[PRB_NUM_TOD][PRB_NUM_SH][3] = {};
};

// A prefiltered reflection probe (sparse). Face-major RGB8 cube per TOD.
struct ReflProbe {
  float pos_gu[3] = {0, 0, 0};  // world position, game units (4096 = 1 m)
  u8 interior = 0;
  s16 cell_ix = 0, cell_iy = 0, cell_iz = 0;
  // layout: [tod][face 0..5][v*FACE + u][channel 0..2]  (mip0 only; runtime generates mips)
  std::vector<u8> cube;  // size = PRB_NUM_TOD * 6 * FACE * FACE * 3
};

struct ProbeGrid {
  char level_name[32] = {0};
  u64 fr3_size = 0;
  float origin_gu[3] = {0, 0, 0};  // world center of cell (0,0,0), game units
  float cell_gu = 0.f;             // cell size, game units
  s32 dims[3] = {0, 0, 0};         // grid extent in cells
  std::vector<ProbeCell> cells;    // SPARSE: baked cells only
  std::vector<ReflProbe> refl;     // sparse reflection anchors
  // stats / diagnostics
  u32 n_valid = 0, n_interior = 0, n_refl = 0;
  BakeParams params;
};

// Bake a probe grid from a decoded, unpacked level. Prints [probe-bake] instrumentation.
ProbeGrid bake_level(const tfrag3::Level& lev,
                     const std::string& level_name,
                     u64 fr3_size,
                     const BakeParams& p);

// zstd-compressed asset with a validated magic/version/level/fr3_size header (mirror of GrassBake).
bool save_probes(const ProbeGrid& g, const std::string& path);
bool load_probes(ProbeGrid& g, const std::string& path);

}  // namespace probe_bake
