// Grecharged-pbr-realtime-fusion: OFFLINE tessellation audit CLI (desktop only, no device).
//
// Measures the ACHIEVED tessellation factors and the generated-triangle cost of the REAL level
// geometry, by mirroring exactly what the runtime does:
//   * the fr3 load+unpack sequence of tools/mesh_audit/main.cpp (== Loader.cpp),
//   * TFragment::build_tess_tri_buffer()'s strip -> triangle-list expansion (one patch/triangle),
//   * the `tess_opaque_kind` gate (only tfrag trees of kind NORMAL/DIRT/ICE are ever tessellated),
//   * the level law of shaders/tfrag3_tess.tesc (camera distance in METRES = |wp - cam| / 4096).
//
// Two laws are evaluated per patch: the OLD (shipped today) tesc law, and the NEW proposed law.
// Read-only: nothing is written except the report.
//
// Usage: tess_audit [--fr3 PATH] [--cam-m X Y Z] [--cam X Y Z] [--tess-max N] [--geom N] [--out P]
//                   [--seg-near M] [--seg-d0 M] [--seg-far M] [--seg-exp P] [--feature-cm C]
//                   [--ground-cos C] [--consolidate] [--subdiv MAX_EDGE_M] [--subdiv-rounds N]

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "common/custom_data/MeshConsolidate.h"
#include "common/custom_data/MeshSubdivide.h"
#include "common/custom_data/Tfrag3Data.h"
#include "common/util/FileUtil.h"
#include "common/util/Serializer.h"
#include "common/util/compress.h"

#include "fmt/format.h"
// ROUND 28: the density law is now a function of the height map's MEASURED feature wavelength, so
// this tool has to decode the real PNGs exactly as the loader does (stbi_load, STBI_rgb_alpha).
#include "third-party/stb_image/stb_image.h"

// NOTE: FileUtil.h already defines `namespace fs = ghc::filesystem`; reuse it.

static void usage() {
  fmt::print(
      "Usage: tess_audit [--fr3 PATH] [--cam-m X Y Z] [--cam X Y Z] [--tess-max N] [--geom N]\n"
      "                  [--out PATH] [--seg-near M] [--seg-d0 M] [--seg-far M] [--seg-exp P]\n"
      "                  [--feature-cm C] [--ground-cos C]\n"
      "  --fr3 PATH      level fr3 (default: <repo>/out/jak1/fr3/village1.fr3)\n"
      "  --cam-m X Y Z   camera position in METRES (multiplied by 4096 internally)\n"
      "  --cam X Y Z     camera position in GAME UNITS\n"
      "                  (neither given: centroid of all tessellable tfrag vertices)\n"
      "  --tess-max N    NEW-law ceiling (default 32)\n"
      "  --geom N        tfrag geom LOD to audit (default 0 = Gfx::g_global_settings.lod_tfrag,\n"
      "                  the only geom TFragment draws at a time)\n"
      "  --out PATH      report path (default: <repo>/.autoport/reports/\n"
      "                  Grecharged-pbr-realtime-fusion/tess_audit.txt)\n"
      "  --seg-near M    EDGE law: target segment size in metres at/below --seg-d0 (default 0.05)\n"
      "  --seg-d0 M      EDGE law: distance where the target segment size starts growing "
      "(default 4.0)\n"
      "  --seg-far M     EDGE law: ceiling of the target segment size (default 1.0)\n"
      "  --seg-exp P     EDGE law: SUPERLINEAR LOD ramp exponent applied to (d/seg_d0) past\n"
      "                  --seg-d0, i.e. seg_target(d) = clamp(seg_near*pow(max(d,seg_d0)/seg_d0,P),\n"
      "                  seg_near, seg_far). P=1 is the old purely linear ramp (default 1.5)\n"
      "  --feature-cm C  reference relief feature wavelength in cm, for v/feature (default 5.0)\n"
      "  --ground-cos C  |face normal.y| threshold above which a patch is GROUND (default 0.707)\n"
      "  --fade-lo M     EDGE law: distance where the amplitude-matched density fade starts "
      "(default 20.0)\n"
      "  --fade-hi M     EDGE law: distance where the fade reaches level 1 (default 30.0)\n"
      "  --consolidate   run the shipped mesh consolidation first (sidecar if present, else live),\n"
      "                  so seam weights and snapped positions match the runtime\n"
      "  --subdiv M      round #19 offline pre-subdivision: refine every tess-eligible tfrag\n"
      "                  triangle until its longest edge is <= M metres (default 0 = off)\n"
      "  --subdiv-rounds N  refinement round cap for --subdiv (default 3)\n"
      "  --r28           ROUND 28: add section R28, the FEATURE-AWARE density law head-to-head\n"
      "                  (round-27 shipped law vs the round-28 law) with the per-material\n"
      "                  lambda MEASURED from the real *_height.png and the per-material UV\n"
      "                  density measured from the index buffer. Default OFF: every other\n"
      "                  section of the report is bit-identical with or without this flag.\n"
      "  --tex-root P    where --r28 looks for <mat>/<mat>_height.png (default:\n"
      "                  <repo>/custom_assets/jak1/recharged_textures)\n");
}

namespace {

constexpr float kUnitsPerM = 4096.f;
// tfrag3_tess.tese: #define WORLD_TILES_PER_M 0.5
constexpr double kWorldTilesPerM = 0.5;
// resolution of the shipped PBR height maps.
constexpr double kHeightMapRes = 2048.0;

// The exact load+unpack sequence Loader.cpp / tools/mesh_audit performs.
// (The shipped Loader additionally runs tfrag3::reconstruct_level_global_weld() here; it is NOT
// run in this tool. The weld only re-points indices at coincident vertices within 0.03 m, so patch
// geometry -- edge lengths and camera distances -- is unaffected at this measurement's resolution.)
void load_level_fr3(const fs::path& fr3_path, tfrag3::Level& lev) {
  auto data = file_util::read_binary_file(fr3_path);
  auto decomp = compression::decompress_zstd(data.data(), data.size());
  Serializer ser(decomp.data(), decomp.size());
  lev.serialize(ser);
  // The packed fr3 leaves tree.unpacked.{vertices,indices} empty until unpack() runs.
  for (auto& tie_tree : lev.tie_trees) {
    for (auto& tree : tie_tree) {
      tree.unpack();
    }
  }
  for (auto& t_tree : lev.tfrag_trees) {
    for (auto& tree : t_tree) {
      tree.unpack();
    }
  }
  // shrub too: the .meshweld sidecar's fingerprint covers every tree the consolidation gathers,
  // so skipping shrub here would make every sidecar look stale and force the slow live pass.
  for (auto& shrub_tree : lev.shrub_trees) {
    shrub_tree.unpack();
  }
}

// TFragment.cpp `tess_opaque_kind`.
bool tess_opaque_kind(tfrag3::TFragmentTreeKind kind) {
  return kind == tfrag3::TFragmentTreeKind::NORMAL || kind == tfrag3::TFragmentTreeKind::DIRT ||
         kind == tfrag3::TFragmentTreeKind::ICE;
}

struct Vec3 {
  float x = 0, y = 0, z = 0;
};

double dist(const Vec3& a, const Vec3& b) {
  const double dx = (double)a.x - b.x, dy = (double)a.y - b.y, dz = (double)a.z - b.z;
  return std::sqrt(dx * dx + dy * dy + dz * dz);
}

// GLSL mix/clamp, in double.
double clampd(double v, double lo, double hi) {
  return v < lo ? lo : (v > hi ? hi : v);
}

// OLD (shipped) tfrag3_tess.tesc law: per-edge level from the edge MIDPOINT distance.
double old_edge_level(double d_m) {
  const double t = clampd((d_m - 8.0) / 22.0, 0.0, 1.0);
  return 12.0 * (1.0 - t) + 1.0 * t;  // mix(12.0, 1.0, t)
}

// NEW law.
double new_edge_level(double d_m, double tess_max) {
  return clampd(128.0 / std::max(d_m, 0.5), 1.0, tess_max);
}

// OWNER #18 EDGE law: level from the WORLD-SPACE EDGE LENGTH against a distance-LOD'd target
// segment size, so a huge ground triangle gets a far higher factor than a small wall triangle at
// the same distance (which a distance-only law cannot do).
// round #19: the ramp past seg_d0 is SUPERLINEAR -- (d/seg_d0)^seg_exp -- so the near field keeps a
// fine target segment size while the far field sheds cost faster than the old purely linear ramp.
// seg_exp == 1.0 reproduces the linear form exactly (pow(x, 1.0) == x).
double seg_target_m(double d_m, double seg_near, double seg_d0, double seg_far, double seg_exp) {
  const double d = std::max(d_m, seg_d0);
  // The seg_exp == 1.0 branch keeps the ORIGINAL expression association bit-for-bit:
  // (seg_near*d)/seg_d0 is not the same double as seg_near*(d/seg_d0). It is not a shortcut for
  // pow (pow(x, 1.0) is already exact), only an associativity guarantee.
  const double target =
      (seg_exp == 1.0) ? (seg_near * d / seg_d0) : (seg_near * std::pow(d / seg_d0, seg_exp));
  return clampd(target, seg_near, seg_far);
}
// GLSL smoothstep.
double smoothstepd(double e0, double e1, double x) {
  const double t = clampd((x - e0) / (e1 - e0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}
double edge_law_level(double edge_m, double d_m, double tess_max, double seg_near, double seg_d0,
                      double seg_far, double seg_exp, double fade_lo, double fade_hi) {
  double lvl = edge_m / seg_target_m(d_m, seg_near, seg_d0, seg_far, seg_exp);
  // AMPLITUDE-MATCHED DENSITY FADE (shipped tfrag3_tess.tesc): the tese fades the displacement
  // amplitude to exactly zero between fade_lo and fade_hi, so the LEVEL fades on the same curve --
  // vertices generated in that band would be displaced by nothing.
  const double w = 1.0 - smoothstepd(fade_lo, fade_hi, d_m);
  lvl = 1.0 + (lvl - 1.0) * w;  // mix(1.0, lvl, w)
  return clampd(lvl, 1.0, tess_max);
}

// GL fractional_odd_spacing rounds a level up to the next ODD integer.
int next_odd_ge(double level) {
  int c = (int)std::ceil(level - 1e-6);
  if (c < 1) {
    c = 1;
  }
  if ((c % 2) == 0) {
    c += 1;
  }
  return c;
}

// per-law accumulators for one distance band.
struct LawBand {
  u64 patches = 0;
  double sum_inner = 0.0;
  double max_inner = 0.0;
  u64 gen_tris = 0;
  double sum_spacing_m = 0.0;
  double sum_mip_lod = 0.0;
};

constexpr int kNumBands = 6;
const char* kBandNames[kNumBands] = {"[0,5)", "[5,10)", "[10,20)", "[20,30)", "[30,40)", "[40,inf)"};

int band_of(double dmin_m) {
  if (dmin_m < 5.0)
    return 0;
  if (dmin_m < 10.0)
    return 1;
  if (dmin_m < 20.0)
    return 2;
  if (dmin_m < 30.0)
    return 3;
  if (dmin_m < 40.0)
    return 4;
  return 5;
}

void accumulate(LawBand& b, double inner, double mean_edge_m) {
  b.patches++;
  b.sum_inner += inner;
  if (inner > b.max_inner) {
    b.max_inner = inner;
  }
  const int L = next_odd_ge(inner);
  b.gen_tris += (u64)L * (u64)L;
  const double spacing_m = mean_edge_m / std::max(inner, 1.0);
  b.sum_spacing_m += spacing_m;
  const double texels_per_sample = spacing_m * kWorldTilesPerM * kHeightMapRes;
  b.sum_mip_lod += std::log2(std::max(texels_per_sample, 1.0));
}

double percentile(const std::vector<float>& sorted, double p) {
  if (sorted.empty()) {
    return 0.0;
  }
  double idx = p * (double)(sorted.size() - 1);
  size_t i0 = (size_t)std::floor(idx);
  size_t i1 = std::min(i0 + 1, sorted.size() - 1);
  double f = idx - (double)i0;
  return (double)sorted[i0] * (1.0 - f) + (double)sorted[i1] * f;
}

// percentile over an UNSORTED sample: sorts a COPY so the accumulator keeps its insertion order.
double pct(const std::vector<float>& v, double p) {
  if (v.empty()) {
    return 0.0;
  }
  std::vector<float> s = v;
  std::sort(s.begin(), s.end());
  return percentile(s, p);
}

double meanf(const std::vector<float>& v) {
  if (v.empty()) {
    return 0.0;
  }
  double sum = 0.0;
  for (float x : v) {
    sum += x;
  }
  return sum / (double)v.size();
}

// ---- OWNER #18: per-orientation accumulators, one cell per [law][class][band] ----
constexpr int kNumLaws = 2;    // 0 = SHIPPED (128/d), 1 = EDGE (world-space edge length)
constexpr int kNumClasses = 2;  // 0 = GROUND, 1 = WALL
const char* kLawNames[kNumLaws] = {"SHIPPED law (128/d)", "EDGE law (world-space edge length)"};
const char* kClassNames[kNumClasses] = {"GROUND", "WALL"};

struct ClassBand {
  u64 patches = 0;
  double sum_inner = 0.0;
  double max_inner = 0.0;
  u64 gen_tris = 0;
  double sum_spacing_m = 0.0;
  double sum_mip_lod = 0.0;
  std::vector<float> edges_m;    // three per patch
  std::vector<float> spacing_m;  // one per patch
};

// same cost model / spacing definition as accumulate(), with the raw samples kept for p90.
void accumulate_cls(ClassBand& b, double inner, double e0, double e1, double e2) {
  b.patches++;
  b.sum_inner += inner;
  if (inner > b.max_inner) {
    b.max_inner = inner;
  }
  const int L = next_odd_ge(inner);
  b.gen_tris += (u64)L * (u64)L;
  const double mean_edge_m = (e0 + e1 + e2) / 3.0;
  const double spacing_m = mean_edge_m / std::max(inner, 1.0);
  b.sum_spacing_m += spacing_m;
  const double texels_per_sample = spacing_m * kWorldTilesPerM * kHeightMapRes;
  b.sum_mip_lod += std::log2(std::max(texels_per_sample, 1.0));
  b.edges_m.push_back((float)e0);
  b.edges_m.push_back((float)e1);
  b.edges_m.push_back((float)e2);
  b.spacing_m.push_back((float)spacing_m);
}

// per-material near-field (< 15 m) accumulator.
struct MatStat {
  u64 patches = 0;
  u64 ground = 0;
  u64 wall = 0;
  double sum_edge_m = 0.0;              // sum of the per-patch MEAN edge length
  double sum_edge_spacing_m = 0.0;      // EDGE-law spacing
  double sum_shipped_spacing_m = 0.0;   // SHIPPED-law spacing
  // section I: does this material ship a *_height.png (i.e. a displacement SOURCE)?
  bool has_height = false;
  double ground_area_m2 = 0.0;             // GROUND-only world-space area, < 15 m
  double sum_ground_edge_spacing_m = 0.0;  // GROUND-only EDGE-law spacing, < 15 m
  // section I2: SIGNED split via the SMOOTH (renderer) normal, < 15 m.
  u64 floor_patches = 0;
  u64 ceiling_patches = 0;
  double floor_area_m2 = 0.0;
  double ceiling_area_m2 = 0.0;
  double sum_floor_edge_spacing_m = 0.0;
  // section U: AUTHORED UV density samples (texture TILES per world METRE). PreloadedVertex::s/t
  // are the authored texture coordinates in tile units; the tese instead projects the height map in
  // world space at WORLD_TILES_PER_M, so these samples say how far the authoring is from that.
  std::vector<float> uv_dens_tri;         // sqrt(uv_area_tiles2 / world_area_m2), one per triangle
  std::vector<float> uv_dens_edge;        // |duv|_tiles / |dpos|_m, one per triangle EDGE
  std::vector<float> uv_dens_tri_ground;  // uv_dens_tri restricted to GROUND triangles
};

// section U: per-material sample cap, so a huge level cannot blow the accumulators up.
constexpr size_t kUvSampleCap = 200000;
void uv_push(std::vector<float>& v, float x) {
  if (v.size() < kUvSampleCap) {
    v.push_back(x);
  }
}

// Copy of the file-static unpack_gl_normal_2_10_10_10() in common/custom_data/TFrag3Data.cpp:
// PreloadedVertex::nor is a 2_10_10_10 packed field (stored int = component * 511), and this is the
// SMOOTH per-vertex normal the renderer actually lights with. Returns a zero vector if the packed
// normal is empty (vertex never got a normal).
Vec3 unpack_gl_normal_2_10_10_10(u32 packed) {
  auto sext10 = [](u32 v) -> int {
    v &= 0x3ffu;
    return (v & 0x200u) ? (int)v - 1024 : (int)v;
  };
  const double nx = (double)sext10(packed);
  const double ny = (double)sext10(packed >> 10);
  const double nz = (double)sext10(packed >> 20);
  const double l = std::sqrt(nx * nx + ny * ny + nz * nz);
  if (l < 1e-6) {
    return Vec3{0.f, 0.f, 0.f};
  }
  return Vec3{(float)(nx / l), (float)(ny / l), (float)(nz / l)};
}

// SIGNED orientation: the unsigned |n.y| test cannot tell a floor from a ceiling.
constexpr int kNumSigned = 3;
const char* kSignedNames[kNumSigned] = {"FLOOR", "CEILING", "WALL"};
int signed_class(double ny_unit, double ground_cos) {
  if (ny_unit >= ground_cos) {
    return 0;  // FLOOR (faces up)
  }
  if (ny_unit <= -ground_cos) {
    return 1;  // CEILING (faces down)
  }
  return 2;  // WALL
}

// ---- section I: GROUND displacement-source coverage, cumulative distance ranges ----
constexpr int kNumRanges = 4;
const double kRangeMax[kNumRanges] = {5.0, 10.0, 15.0, 30.0};
const char* kRangeNames[kNumRanges] = {"< 5 m", "< 10 m", "< 15 m", "< 30 m"};

struct DispRange {
  u64 patches = 0;    // GROUND patches with dmin < range
  u64 patches_h = 0;  // ... whose material ships a height map
  double area_m2 = 0.0;
  double area_m2_h = 0.0;
};

// The materials that actually ship a *_height.png under
// custom_assets/jak1/recharged_textures (i.e. the ones the PBR/displacement path can relieve).
const std::set<std::string>& pbr_materials() {
  static const std::set<std::string> s = {
      "vil-beach-01",          "vil-beachrock",           "vil-hut-roof-tile-01",
      "vil-wallplaster",       "vil1-jng-leafyground",    "vil1-sages-stonewall-01",
      "vil1-sages-strawroof-01"};
  return s;
}

// ===============================================================================================
// ROUND 28 — the shipped density law is a function of the material's MEASURED feature wavelength.
// Everything in this block is a LINE-FOR-LINE port of the shipping runtime, so the numbers this
// tool reports are the numbers the GPU is handed:
//   * measure_height_lambda_tiles  <- game/graphics/opengl_renderer/loader/LoaderStages.cpp:45-129
//   * measure_uv_density_tfrag     <- game/graphics/opengl_renderer/background/background_common.cpp
//                                     :541-604 (pbr_collect_uv_density) + :661-674
//   * tess_lambda_world_m / tess_seg_target_m / edge_level
//                                  <- game/graphics/opengl_renderer/shaders/tfrag3_tess.tesc
// NOTHING here is tabulated: the lambdas are decoded out of the real PNGs at run time, the UV
// densities out of the real index buffer.
// ===============================================================================================

// LoaderStages.cpp:45 measure_height_lambda_tiles(), with the ReplacementImage fields passed
// directly (w, h, rgba as RGBA8 — exactly what stbi_load(..., STBI_rgb_alpha) produces, which is
// what custom_tex::lookup_suffixed() hands the runtime copy).
float measure_height_lambda_tiles(int w, int h, const std::vector<u8>& rgba) {
  if (w <= 0 || h <= 0 || rgba.size() < (size_t)w * (size_t)h * 4u) {
    return 0.25f;
  }
  // (a) R channel / 255, SUBSAMPLED so neither dimension exceeds 1024.
  const int step = std::max(1, std::max(w, h) / 1024);
  const int cw0 = std::max(1, (w + step - 1) / step);
  const int ch0 = std::max(1, (h + step - 1) / step);
  std::vector<float> buf((size_t)cw0 * (size_t)ch0);
  for (int y = 0; y < ch0; y++) {
    for (int x = 0; x < cw0; x++) {
      const size_t src = ((size_t)(y * step) * (size_t)w + (size_t)(x * step)) * 4u;
      buf[(size_t)y * (size_t)cw0 + (size_t)x] = rgba[src] * (1.f / 255.f);
    }
  }
  auto variance = [](const std::vector<float>& v) -> double {
    if (v.empty()) {
      return 0.0;
    }
    double s = 0.0, s2 = 0.0;
    for (float f : v) {
      s += (double)f;
      s2 += (double)f * (double)f;
    }
    const double n = (double)v.size();
    const double mean = s / n;
    return std::max(s2 / n - mean * mean, 0.0);
  };
  // (b) a flat map has no feature scale at all.
  const double var0 = variance(buf);
  if (var0 < 1e-8) {
    return 0.25f;
  }
  // (c) halve the resolution until the variance has halved.
  const double target = 0.5 * var0;
  double var_prev = var0;
  int cw = cw0, ch = ch0;
  int l_last = 0;
  float l_star = 0.f;
  bool crossed = false;
  for (int l = 1; cw >= 2 && ch >= 2 && l <= 12; l++) {
    const int nw = cw / 2, nh = ch / 2;  // truncate odd dims
    std::vector<float> down((size_t)nw * (size_t)nh);
    for (int y = 0; y < nh; y++) {
      for (int x = 0; x < nw; x++) {
        const size_t r0 = (size_t)(2 * y) * (size_t)cw + (size_t)(2 * x);
        const size_t r1 = (size_t)(2 * y + 1) * (size_t)cw + (size_t)(2 * x);
        down[(size_t)y * (size_t)nw + (size_t)x] =
            0.25f * (buf[r0] + buf[r0 + 1] + buf[r1] + buf[r1 + 1]);
      }
    }
    buf.swap(down);
    cw = nw;
    ch = nh;
    l_last = l;
    const double var_l = variance(buf);
    if (var_l <= target) {
      // crossing interpolated in LOG variance (see the runtime comment).
      double t = 0.0;
      if (var_prev > 0.0 && var_l > 0.0) {
        const double denom = std::log(var_prev) - std::log(var_l);
        t = (std::log(var_prev) - std::log(target)) / std::max(denom, 1e-12);
      }
      l_star = (float)((double)(l - 1) + std::clamp(t, 0.0, 1.0));
      crossed = true;
      break;
    }
    var_prev = var_l;
  }
  if (!crossed) {
    l_star = (float)l_last;
  }
  // (d) the wavelength is twice the box size at the median-energy scale.
  const float lambda_texels = std::exp2(l_star + 1.0f);
  const float lambda_tiles = lambda_texels / (float)std::max(cw0, ch0);
  // (e)
  return std::clamp(lambda_tiles, 1.0f / 1024.0f, 1.0f);
}

// The container stb_image ACTUALLY decoded, from the file's magic bytes. Not cosmetic: a *_height
// file that is really a JPEG is lossy, so its measured lambda is decoder-dependent (two decoders
// disagree in the low bits of the IDCT) and its height field carries ringing the tessellation will
// displace. stb_image sniffs the format and does not care about the extension, so neither can this.
const char* image_container(const fs::path& p) {
  std::ifstream f(p.string(), std::ios::binary);
  if (!f) {
    return "unreadable";
  }
  unsigned char m[8] = {0};
  f.read((char*)m, 8);
  if (f.gcount() >= 8 && m[0] == 0x89 && m[1] == 'P' && m[2] == 'N' && m[3] == 'G') {
    return "PNG";
  }
  if (f.gcount() >= 3 && m[0] == 0xFF && m[1] == 0xD8 && m[2] == 0xFF) {
    return "JPEG (LOSSY -- .png extension only)";
  }
  return "unknown container";
}

// <tex-root>/<tpage>/<material>/<material>_height.png, resolved by material name (the tpage
// directory is not known here, and the loader keys on the material name anyway).
bool find_height_png(const fs::path& tex_root, const std::string& mat, fs::path* out) {
  if (!fs::exists(tex_root)) {
    return false;
  }
  const std::string want = mat + "_height.png";
  for (auto it = fs::recursive_directory_iterator(tex_root);
       it != fs::recursive_directory_iterator(); ++it) {
    if (!it->is_regular_file()) {
      continue;
    }
    if (it->path().filename().string() == want) {
      *out = it->path();
      return true;
    }
  }
  return false;
}

// background_common.cpp kUvDensityMaxSamples / pbr_collect_uv_density / measure_uv_density_tfrag.
constexpr size_t kUvDensityMaxSamples = 8192;

void pbr_collect_uv_density(const std::vector<tfrag3::StripDraw>& draws,
                            const std::vector<u32>& indices,
                            const std::vector<tfrag3::PreloadedVertex>& verts,
                            s32 tex_idx,
                            std::vector<float>& out) {
  for (const auto& draw : draws) {
    if (draw.tree_tex_id != tex_idx) {
      continue;
    }
    u64 count = 0;
    for (const auto& vg : draw.vis_groups) {
      count += vg.num_inds;
    }
    const u64 first = draw.unpacked.idx_of_first_idx_in_full_buffer;
    for (u64 k = 0; k + 1 < count; ++k) {
      if (out.size() >= kUvDensityMaxSamples) {
        return;
      }
      const u64 ia = first + k;
      const u64 ib = ia + 1;
      if (ib >= indices.size()) {
        break;
      }
      const u32 va = indices[ia];
      const u32 vb = indices[ib];
      if (va == vb) {
        continue;  // strip restart / degenerate
      }
      if (va >= verts.size() || vb >= verts.size()) {
        continue;
      }
      const auto& pa = verts[va];
      const auto& pb = verts[vb];
      const float dx = pa.x - pb.x;
      const float dy = pa.y - pb.y;
      const float dz = pa.z - pb.z;
      const float dm = std::sqrt(dx * dx + dy * dy + dz * dz) * (1.f / 4096.f);
      const float du = pa.s - pb.s;
      const float dv = pa.t - pb.t;
      const float dt = std::sqrt(du * du + dv * dv);
      if (dm < 1e-4f || dt < 1e-6f) {
        continue;
      }
      out.push_back(dt / dm);
    }
  }
}

float pbr_uv_density_median(const std::vector<float>& samples) {
  if (samples.size() < 16) {
    return 0.f;  // "unknown" — callers fall back to 0.5
  }
  std::vector<float> copy = samples;
  const size_t mid = copy.size() / 2;
  std::nth_element(copy.begin(), copy.begin() + mid, copy.end());
  return copy[mid];
}

float measure_uv_density_tfrag(const tfrag3::Level& lev, s32 tex_idx, u32* out_samples) {
  std::vector<float> samples;
  samples.reserve(1024);
  // GEOM 0 only, exactly as the runtime does (the lower LODs share the authored UVs).
  for (const auto& tree : lev.tfrag_trees[0]) {
    pbr_collect_uv_density(tree.draws, tree.unpacked.indices, tree.unpacked.vertices, tex_idx,
                           samples);
    if (samples.size() >= kUvDensityMaxSamples) {
      break;
    }
  }
  if (out_samples) {
    *out_samples = (u32)samples.size();
  }
  return pbr_uv_density_median(samples);
}

// ---- the per-material inputs of the ROUND 28 law, as the runtime resolves them ----
// PbrDrawBinder::set(): u_pbr_uv_per_m = measured density (0.5 if the draw has no material or the
// measurement returned "unknown"), u_pbr_height_lambda = the map's measured wavelength (0.25 if the
// draw has no height map). Those two identity defaults land on lambda_world_m = 0.5 m.
struct MatLambda {
  double lambda_tiles = 0.25;  // u_pbr_height_lambda
  double uv_per_m = 0.5;       // u_pbr_uv_per_m
  bool lambda_measured = false;
  bool uv_measured = false;
  u32 uv_samples = 0;
  int png_w = 0, png_h = 0;
  std::string png_path;
  std::string container = "-";
  std::string note;
  // tfrag3_tess.tesc tess_lambda_world_m()
  double world_m() const {
    return clampd(lambda_tiles, 0.002, 1.0) / std::max(uv_per_m, 1e-3);
  }
};

// ---- tfrag3_tess.tesc, ROUND 28 constant block ----
constexpr double kTessSegPerFeature = 8.0;  // TESS_SEG_PER_FEATURE
constexpr double kTessSegFeatMin = 0.5;     // TESS_SEG_FEAT_MIN
constexpr double kTessSegFeatMax = 4.0;     // TESS_SEG_FEAT_MAX
constexpr double kTessSpfRelease = 1.5;     // TESS_SPF_RELEASE
constexpr double kTessSpfKeep = 2.5;        // TESS_SPF_KEEP

struct R28Params {
  double seg_near = 0.025;  // u_pbr_tess_seg
  double seg_d0 = 5.0;      // TESS_SEG_D0_M
  double seg_far = 0.60;    // TESS_SEG_FAR_M
  double seg_exp = 1.5;     // TESS_SEG_EXP
  double fade_lo = 40.0;    // TESS_FADE_LO_M
  double fade_hi = 60.0;    // TESS_FADE_HI_M
  double tess_max = 64.0;   // u_pbr_tess_max
};

// tfrag3_tess.tesc tess_seg_target_m(). `r28 == false` is the round-27/shipped law: the same
// function with the feature clamp removed (bisect bit 1 set).
double r28_seg_target_m(double d_m, double lambda_world_m, bool r28, const R28Params& p) {
  double near_m = p.seg_near;
  if (r28) {
    near_m = clampd(lambda_world_m * (1.0 / kTessSegPerFeature), near_m * kTessSegFeatMin,
                    near_m * kTessSegFeatMax);
  }
  return clampd(near_m * std::pow(std::max(d_m, p.seg_d0) * (1.0 / p.seg_d0), p.seg_exp), near_m,
                std::max(p.seg_far, near_m));
}

// tfrag3_tess.tesc edge_level(). `r28 == false` drops BOTH lambda-dependent steps (the feature
// clamp above and the spf release ramp below), i.e. exactly the round-27 shipped law.
double r28_edge_level(double len_m,
                      double d_m,
                      double lambda_world_m,
                      bool r28,
                      const R28Params& p) {
  const double cap = std::max(p.tess_max, 1.0);
  double lvl = len_m / r28_seg_target_m(d_m, lambda_world_m, r28, p);
  lvl = 1.0 + (lvl - 1.0) * (1.0 - smoothstepd(p.fade_lo, p.fade_hi, d_m));  // mix(1, lvl, 1-ss)
  lvl = clampd(lvl, 1.0, cap);
  if (r28) {
    const double spf = lambda_world_m * lvl / std::max(len_m, 1e-6);
    lvl = 1.0 + (lvl - 1.0) * smoothstepd(kTessSpfRelease, kTessSpfKeep, spf);
  }
  return clampd(lvl, 1.0, cap);
}

// ---- ROUND 28 report bands (the deliverable asks for 0-5 / 5-10 / 10-20 / 20-40) ----
constexpr int kR28Bands = 5;
const char* kR28BandNames[kR28Bands] = {"[0,5)", "[5,10)", "[10,20)", "[20,40)", "[40,inf)"};
int r28_band_of(double dmin_m) {
  if (dmin_m < 5.0)
    return 0;
  if (dmin_m < 10.0)
    return 1;
  if (dmin_m < 20.0)
    return 2;
  if (dmin_m < 40.0)
    return 3;
  return 4;
}

struct R28Cell {
  u64 patches = 0;
  double sum_inner = 0.0;
  double max_inner = 0.0;
  u64 gen_tris = 0;
  double sum_spacing_m = 0.0;  // mean_edge / inner, per patch
  double sum_spf = 0.0;        // lambda_world_m / spacing, per patch
  u64 patches_at_cap = 0;
  u64 patches_level1 = 0;  // level collapsed to 1 (far gate, fade, or spf release)
};

void r28_accum(R28Cell& c, double inner, double mean_edge_m, double lambda_world_m, double cap) {
  c.patches++;
  c.sum_inner += inner;
  if (inner > c.max_inner) {
    c.max_inner = inner;
  }
  const int L = next_odd_ge(inner);
  c.gen_tris += (u64)L * (u64)L;
  const double spacing_m = mean_edge_m / std::max(inner, 1.0);
  c.sum_spacing_m += spacing_m;
  c.sum_spf += spacing_m > 0.0 ? lambda_world_m / spacing_m : 0.0;
  if (inner >= cap - 1e-9) {
    c.patches_at_cap++;
  }
  if (inner <= 1.0 + 1e-9) {
    c.patches_level1++;
  }
}

void r28_merge(R28Cell& dst, const R28Cell& s) {
  dst.patches += s.patches;
  dst.sum_inner += s.sum_inner;
  dst.max_inner = std::max(dst.max_inner, s.max_inner);
  dst.gen_tris += s.gen_tris;
  dst.sum_spacing_m += s.sum_spacing_m;
  dst.sum_spf += s.sum_spf;
  dst.patches_at_cap += s.patches_at_cap;
  dst.patches_level1 += s.patches_level1;
}

}  // namespace

int main(int argc, char** argv) {
  std::string fr3_path_s;
  std::string out_path;
  double tess_max = 32.0;
  int geom = 0;
  // OWNER #18 EDGE-law parameters.
  double seg_near = 0.05;
  double seg_d0 = 4.0;
  double seg_far = 1.0;
  // round #19: superlinear LOD ramp exponent past seg_d0 (1.0 == the old linear ramp).
  double seg_exp = 1.5;
  double feature_cm = 5.0;
  double ground_cos = 0.707;
  // shipped tesc amplitude-matched density fade band.
  double fade_lo = 20.0;
  double fade_hi = 30.0;
  // round #19: offline pre-subdivision of the large ground patches (0 = off = the shipped mesh).
  double subdiv_m = 0.0;
  int subdiv_rounds = 3;
  // run the owner-validated mesh consolidation first, exactly as Loader.cpp does, so the seam
  // weights (which decide what can displace at all) and the snapped positions are the real ones.
  bool do_consolidate = false;
  // ROUND 28: feature-aware density law head-to-head (opt-in, adds section R28 and nothing else).
  bool do_r28 = false;
  std::string tex_root_s;
  bool have_cam = false;
  bool cam_from_metres = false;
  Vec3 cam;  // game units

  for (int i = 1; i < argc; ++i) {
    std::string a = argv[i];
    auto need_val = [&](const char* name) -> std::string {
      if (i + 1 >= argc) {
        fmt::print("error: {} requires a value\n", name);
        usage();
        std::exit(2);
      }
      return argv[++i];
    };
    auto need_vec3 = [&](const char* name, float scale) {
      if (i + 3 >= argc) {
        fmt::print("error: {} requires X Y Z\n", name);
        usage();
        std::exit(2);
      }
      cam.x = std::stof(argv[++i]) * scale;
      cam.y = std::stof(argv[++i]) * scale;
      cam.z = std::stof(argv[++i]) * scale;
      have_cam = true;
    };
    if (a == "--fr3") {
      fr3_path_s = need_val("--fr3");
    } else if (a == "--cam-m") {
      need_vec3("--cam-m", kUnitsPerM);
      cam_from_metres = true;
    } else if (a == "--cam") {
      need_vec3("--cam", 1.f);
      cam_from_metres = false;
    } else if (a == "--tess-max") {
      tess_max = std::stod(need_val("--tess-max"));
    } else if (a == "--geom") {
      geom = std::stoi(need_val("--geom"));
    } else if (a == "--seg-near") {
      seg_near = std::stod(need_val("--seg-near"));
    } else if (a == "--seg-d0") {
      seg_d0 = std::stod(need_val("--seg-d0"));
    } else if (a == "--seg-far") {
      seg_far = std::stod(need_val("--seg-far"));
    } else if (a == "--seg-exp") {
      seg_exp = std::stod(need_val("--seg-exp"));
    } else if (a == "--feature-cm") {
      feature_cm = std::stod(need_val("--feature-cm"));
    } else if (a == "--ground-cos") {
      ground_cos = std::stod(need_val("--ground-cos"));
    } else if (a == "--fade-lo") {
      fade_lo = std::stod(need_val("--fade-lo"));
    } else if (a == "--fade-hi") {
      fade_hi = std::stod(need_val("--fade-hi"));
    } else if (a == "--subdiv") {
      subdiv_m = std::stod(need_val("--subdiv"));
    } else if (a == "--subdiv-rounds") {
      subdiv_rounds = std::stoi(need_val("--subdiv-rounds"));
    } else if (a == "--consolidate") {
      do_consolidate = true;
    } else if (a == "--r28") {
      do_r28 = true;
    } else if (a == "--tex-root") {
      tex_root_s = need_val("--tex-root");
    } else if (a == "--out") {
      out_path = need_val("--out");
    } else if (a == "-h" || a == "--help") {
      usage();
      return 0;
    } else {
      fmt::print("error: unknown/unexpected argument '{}'\n", a);
      usage();
      return 2;
    }
  }

  if (tess_max < 1.0) {
    fmt::print("error: --tess-max must be >= 1 (got {})\n", tess_max);
    return 2;
  }
  if (geom < 0 || geom >= tfrag3::TFRAG_GEOS) {
    fmt::print("error: --geom must be in [0,{}) (got {})\n", tfrag3::TFRAG_GEOS, geom);
    return 2;
  }
  if (seg_near <= 0.0) {
    fmt::print("error: --seg-near must be > 0 (got {})\n", seg_near);
    usage();
    return 2;
  }
  if (seg_d0 <= 0.0) {
    fmt::print("error: --seg-d0 must be > 0 (got {})\n", seg_d0);
    usage();
    return 2;
  }
  if (seg_far < seg_near) {
    fmt::print("error: --seg-far must be >= --seg-near (got {} < {})\n", seg_far, seg_near);
    usage();
    return 2;
  }
  if (seg_exp <= 0.0) {
    fmt::print("error: --seg-exp must be > 0 (got {})\n", seg_exp);
    usage();
    return 2;
  }
  if (feature_cm <= 0.0) {
    fmt::print("error: --feature-cm must be > 0 (got {})\n", feature_cm);
    usage();
    return 2;
  }
  if (ground_cos <= 0.0 || ground_cos >= 1.0) {
    fmt::print("error: --ground-cos must be in (0,1) (got {})\n", ground_cos);
    usage();
    return 2;
  }
  if (fade_lo <= 0.0) {
    fmt::print("error: --fade-lo must be > 0 (got {})\n", fade_lo);
    usage();
    return 2;
  }
  if (fade_hi <= fade_lo) {
    fmt::print("error: --fade-hi must be > --fade-lo (got {} <= {})\n", fade_hi, fade_lo);
    usage();
    return 2;
  }

  const bool have_project = file_util::setup_project_path({});
  if (fr3_path_s.empty()) {
    if (!have_project) {
      fmt::print("error: could not resolve the jak-project directory; pass --fr3.\n");
      return 1;
    }
    fr3_path_s =
        (file_util::get_jak_project_dir() / "out" / "jak1" / "fr3" / "village1.fr3").string();
  }
  if (out_path.empty()) {
    if (!have_project) {
      fmt::print("error: could not resolve the jak-project directory; pass --out.\n");
      return 1;
    }
    const fs::path rep_dir = file_util::get_jak_project_dir() / ".autoport" / "reports" /
                             "Grecharged-pbr-realtime-fusion";
    file_util::create_dir_if_needed(rep_dir);
    out_path = (rep_dir / "tess_audit.txt").string();
  }
  file_util::create_dir_if_needed_for_file(out_path);

  const fs::path fr3_path(fr3_path_s);
  if (!fs::exists(fr3_path)) {
    fmt::print("error: fr3 not found: {}\n", fr3_path.string());
    return 1;
  }

  tfrag3::Level lev;
  try {
    load_level_fr3(fr3_path, lev);
  } catch (const std::exception& e) {
    fmt::print("error: failed to load {}: {}\n", fr3_path.string(), e.what());
    return 1;
  }

  // ---- reproduce the runtime geometry pipeline, so the density this tool measures is the density
  // the GPU actually sees. Loader.cpp order: global weld -> mesh consolidation (sidecar, else live)
  // -> pre-subdivision. The consolidation matters here for more than tidiness: it is what writes the
  // per-vertex SEAM WEIGHTS, and a fully pinned triangle is deliberately not subdivided.
  std::string prep_note = "prep: none (raw fr3 unpack)";
  if (do_consolidate) {
    tfrag3::reconstruct_level_global_weld(lev);
    const auto cfg = tfrag3::mesh_consolidate_config_from_env();
    const fs::path bake = fr3_path.parent_path() / tfrag3::mesh_consolidate_bake_name(lev.level_name);
    if (tfrag3::mesh_consolidate_apply_bake(lev, bake.string(), true)) {
      prep_note = fmt::format("prep: global weld + consolidation from sidecar {}", bake.string());
    } else {
      tfrag3::MeshAuditReport rep;
      tfrag3::mesh_consolidate(lev, cfg, &rep);
      prep_note = "prep: global weld + LIVE consolidation (no usable sidecar)";
    }
  }
  std::string subdiv_note = "pre-subdivision: OFF";
  if (subdiv_m > 0.0) {
    tfrag3::SubdivConfig scfg;
    scfg.max_edge_m = (float)subdiv_m;
    scfg.max_rounds = subdiv_rounds;
    scfg.only_geom = geom;  // the runtime refines only the geom LOD TFragment draws
    tfrag3::SubdivStats sst;
    // Same "has a displacement source" bound the runtime applies, resolved here from the shipped
    // recharged_textures material list instead of the live custom-assets index.
    tfrag3::mesh_presubdivide_level(lev, scfg, &sst, [](const tfrag3::Texture& t) {
      return pbr_materials().count(t.debug_name) > 0;
    });
    subdiv_note = tfrag3::format_subdiv_stats(sst, scfg);
  }

  // ---- ROUND 28: resolve the per-material law inputs the runtime pushes as uniforms ----
  // Order matches the runtime: the loader preps the geometry (weld/consolidate/subdivide) and THEN
  // TFragment::update_load measures the UV density off the prepped index buffer, so this block sits
  // after the prep above. The lambdas come out of the shipped PNGs (stb_image, same decode as
  // custom_tex::lookup_suffixed) — nothing is tabulated.
  std::map<std::string, MatLambda> mat_lambda;
  std::string r28_lambda_log;
  fs::path tex_root;
  if (do_r28) {
    if (!tex_root_s.empty()) {
      tex_root = fs::path(tex_root_s);
    } else if (have_project) {
      tex_root = file_util::get_jak_project_dir() / "custom_assets" / "jak1" / "recharged_textures";
    } else {
      fmt::print("error: --r28 needs --tex-root (could not resolve the jak-project directory)\n");
      return 1;
    }
    if (!fs::exists(tex_root)) {
      fmt::print("error: --r28 texture root does not exist: {}\n", tex_root.string());
      return 1;
    }
    for (size_t ti = 0; ti < lev.textures.size(); ++ti) {
      const std::string& name = lev.textures[ti].debug_name;
      if (mat_lambda.count(name)) {
        continue;
      }
      fs::path png;
      if (!find_height_png(tex_root, name, &png)) {
        continue;  // no height map => the runtime identity defaults (0.25 tiles, 0.5 tiles/m)
      }
      MatLambda ml;
      ml.png_path = png.string();
      ml.container = image_container(png);
      int w = 0, h = 0;
      unsigned char* data = stbi_load(png.string().c_str(), &w, &h, nullptr, STBI_rgb_alpha);
      if (!data) {
        ml.note = fmt::format("PNG DECODE FAILED ({}) -- identity default used", png.string());
        mat_lambda[name] = ml;
        continue;
      }
      std::vector<u8> rgba((size_t)w * (size_t)h * 4u);
      std::memcpy(rgba.data(), data, rgba.size());
      stbi_image_free(data);
      ml.png_w = w;
      ml.png_h = h;
      ml.lambda_tiles = measure_height_lambda_tiles(w, h, rgba);
      ml.lambda_measured = true;
      u32 nsamp = 0;
      const float dens = measure_uv_density_tfrag(lev, (s32)ti, &nsamp);
      ml.uv_samples = nsamp;
      if (dens > 0.f) {
        ml.uv_per_m = dens;
        ml.uv_measured = true;
      } else {
        // TFragment::update_load: `if (dens <= 0.f) dens = 0.5f;`
        ml.note = fmt::format("UV density unknown ({} samples < 16) -- runtime 0.5 fallback",
                              nsamp);
      }
      mat_lambda[name] = ml;
    }
    for (const auto& [name, ml] : mat_lambda) {
      r28_lambda_log += fmt::format(
          "  {:<28} lambda_tiles={:.6f} ({}) uv_per_m={:.6f} ({}, {} samples) "
          "lambda_world_m={:.6f} img={}x{} container={} {}{}\n",
          name, ml.lambda_tiles,
          ml.lambda_measured ? "MEASURED from the map" : "identity default", ml.uv_per_m,
          ml.uv_measured ? "MEASURED from index buffer" : "runtime 0.5 fallback", ml.uv_samples,
          ml.world_m(), ml.png_w, ml.png_h, ml.container, ml.png_path,
          ml.note.empty() ? "" : ("  NOTE: " + ml.note));
    }
  }
  // Every material NOT in mat_lambda uses this: the runtime identity (0.25 tiles / 0.5 tiles/m).
  const MatLambda kIdentityLambda;

  // ---- per-geom tree census (informational) + camera centroid over the audited geom ----
  std::string geom_census;
  for (int g = 0; g < tfrag3::TFRAG_GEOS; ++g) {
    u64 tess_trees = 0, all_trees = lev.tfrag_trees[g].size();
    for (const auto& t : lev.tfrag_trees[g]) {
      if (tess_opaque_kind(t.kind)) {
        tess_trees++;
      }
    }
    geom_census += fmt::format("{}geom{}: {} trees ({} tessellable)", g ? ", " : "", g, all_trees,
                               tess_trees);
  }

  u64 centroid_n = 0;
  double cx = 0, cy = 0, cz = 0;
  for (const auto& tree : lev.tfrag_trees[geom]) {
    if (!tess_opaque_kind(tree.kind)) {
      continue;
    }
    for (const auto& v : tree.unpacked.vertices) {
      cx += v.x;
      cy += v.y;
      cz += v.z;
      centroid_n++;
    }
  }
  if (!have_cam) {
    if (centroid_n == 0) {
      fmt::print("error: no tessellable tfrag vertices in geom {} of {}; pass --cam/--cam-m.\n",
                 geom, fr3_path.string());
      return 1;
    }
    cam.x = (float)(cx / (double)centroid_n);
    cam.y = (float)(cy / (double)centroid_n);
    cam.z = (float)(cz / (double)centroid_n);
  }

  // ---- main pass: expand every draw to patches, evaluate both laws ----
  LawBand old_band[kNumBands], new_band[kNumBands];
  u64 trees_counted = 0, draws_counted = 0, patches_total = 0, verts_counted = 0;
  u64 oob_draws = 0;
  std::vector<float> edge_len_m;  // every patch edge, metres

  // OWNER #18: orientation-split accumulators + degenerate census + per-material near field.
  ClassBand cls_band[kNumLaws][kNumClasses][kNumBands];
  // section G2: EDGE law, GROUND patches whose material actually ships a displacement source
  // (*_height.png). A GROUND patch without one cannot be displaced at ANY tessellation level, so
  // its spacing/v-per-feature contribution is meaningless -- this is the only population where
  // density can turn into relief.
  ClassBand gh_band[kNumBands];
  u64 class_patches[kNumClasses] = {0, 0};
  u64 degenerate_patches = 0;
  std::map<std::string, MatStat> mat_stats;
  DispRange disp[kNumRanges];        // section I  (unsigned GROUND)
  DispRange disp_floor[kNumRanges];  // section I2 (FLOOR only, SMOOTH normal)
  DispRange disp_floor_f[kNumRanges];  // section I2 (FLOOR only, FACE/winding normal)
  u64 signed_face[kNumSigned] = {0, 0, 0};
  u64 signed_smooth[kNumSigned] = {0, 0, 0};
  u64 confusion[kNumSigned][kNumSigned] = {};
  u64 smooth_missing = 0;  // patch whose 3 corner normals sum to ~0 (no usable smooth normal)
  u64 smooth_partial = 0;  // patch with at least one corner carrying no packed normal

  // ---- ROUND 28 accumulators: [band][law], law 0 = round-27 shipped, law 1 = round 28 ----
  using R28MatCells = std::array<std::array<R28Cell, 2>, kR28Bands>;
  std::map<std::string, R28MatCells> r28_mat;
  R28Cell r28_all[2][kR28Bands];
  R28Cell r28_cls[2][kNumClasses][kR28Bands];
  R28Params p28;
  p28.seg_near = seg_near;
  p28.seg_d0 = seg_d0;
  p28.seg_far = seg_far;
  p28.seg_exp = seg_exp;
  p28.fade_lo = fade_lo;
  p28.fade_hi = fade_hi;
  p28.tess_max = tess_max;

  for (const auto& tree : lev.tfrag_trees[geom]) {
    if (!tess_opaque_kind(tree.kind)) {
      continue;
    }
    trees_counted++;
    verts_counted += tree.unpacked.vertices.size();
    const auto& verts = tree.unpacked.vertices;
    const auto& inds = tree.unpacked.indices;
    // TFragment.cpp: tree_cache.draw_mode = tree.use_strips ? GL_TRIANGLE_STRIP : GL_TRIANGLES
    const bool strips = tree.use_strips;

    // one patch (a,b,c) -> both laws. `mat` is the near-field accumulator of the draw's material
    // (resolved once per draw; null is never passed, the guard is defensive).
    auto emit_patch = [&](u32 i0, u32 i1, u32 i2, MatStat* mat, double lambda_world_m,
                          R28MatCells* r28cells) {
      if (i0 >= verts.size() || i1 >= verts.size() || i2 >= verts.size()) {
        return;
      }
      const Vec3 p0{verts[i0].x, verts[i0].y, verts[i0].z};
      const Vec3 p1{verts[i1].x, verts[i1].y, verts[i1].z};
      const Vec3 p2{verts[i2].x, verts[i2].y, verts[i2].z};
      patches_total++;

      // OpenGL triangle convention (mirrors the tesc): outer level i is the edge opposite vertex i.
      const Vec3 m0{0.5f * (p1.x + p2.x), 0.5f * (p1.y + p2.y), 0.5f * (p1.z + p2.z)};
      const Vec3 m1{0.5f * (p2.x + p0.x), 0.5f * (p2.y + p0.y), 0.5f * (p2.z + p0.z)};
      const Vec3 m2{0.5f * (p0.x + p1.x), 0.5f * (p0.y + p1.y), 0.5f * (p0.z + p1.z)};

      const double e0 = dist(p1, p2) / kUnitsPerM;
      const double e1 = dist(p2, p0) / kUnitsPerM;
      const double e2 = dist(p0, p1) / kUnitsPerM;
      edge_len_m.push_back((float)e0);
      edge_len_m.push_back((float)e1);
      edge_len_m.push_back((float)e2);
      const double mean_edge_m = (e0 + e1 + e2) / 3.0;

      const double d0 = dist(m0, cam) / kUnitsPerM;
      const double d1 = dist(m1, cam) / kUnitsPerM;
      const double d2 = dist(m2, cam) / kUnitsPerM;

      const double dmin = std::min(std::min(dist(p0, cam), dist(p1, cam)), dist(p2, cam)) /
                          kUnitsPerM;
      const int band = band_of(dmin);

      // OLD law
      double inner_old;
      if (dmin > 30.0) {
        inner_old = 1.0;
      } else {
        inner_old = std::max(std::max(old_edge_level(d0), old_edge_level(d1)), old_edge_level(d2));
      }
      accumulate(old_band[band], inner_old, mean_edge_m);

      // NEW law
      double inner_new;
      if (dmin > 30.0) {
        inner_new = 1.0;
      } else {
        inner_new = std::max(std::max(new_edge_level(d0, tess_max), new_edge_level(d1, tess_max)),
                             new_edge_level(d2, tess_max));
      }
      accumulate(new_band[band], inner_new, mean_edge_m);

      // ---- OWNER #18: orientation class from the face normal (game Y is up) ----
      const double ux = (double)p1.x - p0.x, uy = (double)p1.y - p0.y, uz = (double)p1.z - p0.z;
      const double vx = (double)p2.x - p0.x, vy = (double)p2.y - p0.y, vz = (double)p2.z - p0.z;
      const double nx = uy * vz - uz * vy;
      const double ny = uz * vx - ux * vz;
      const double nz = ux * vy - uy * vx;
      const double nlen = std::sqrt(nx * nx + ny * ny + nz * nz);
      int cls;
      if (nlen < 1e-12) {
        degenerate_patches++;
        cls = 1;  // WALL
      } else {
        const double upness = std::fabs(ny) / nlen;  // == |normalize(cross(p1-p0, p2-p0)).y|
        cls = (upness >= ground_cos) ? 0 : 1;
      }
      class_patches[cls]++;

      // ---- section U: AUTHORED UV DENSITY (texture tiles per world metre) ----
      // Purely a property of the authoring (positions + uvs), so it is measured on EVERY patch of
      // the audited geom, with no camera-distance gate. `nlen` above is |cross(p1-p0,p2-p0)| in
      // game units^2, i.e. exactly 2x the world-space triangle area.
      if (mat) {
        const double su[3] = {(double)verts[i0].s, (double)verts[i1].s, (double)verts[i2].s};
        const double sv[3] = {(double)verts[i0].t, (double)verts[i1].t, (double)verts[i2].t};
        const double world_area_m2 = 0.5 * nlen / ((double)kUnitsPerM * (double)kUnitsPerM);
        const double duv1x = su[1] - su[0], duv1y = sv[1] - sv[0];
        const double duv2x = su[2] - su[0], duv2y = sv[2] - sv[0];
        const double uv_area = 0.5 * std::fabs(duv1x * duv2y - duv1y * duv2x);  // tiles^2
        if (world_area_m2 > 1e-9 && uv_area > 1e-12) {
          const float dens = (float)std::sqrt(uv_area / world_area_m2);
          uv_push(mat->uv_dens_tri, dens);
          if (cls == 0) {
            uv_push(mat->uv_dens_tri_ground, dens);
          }
        }
        // per-EDGE density. e2 = |p0p1|, e0 = |p1p2|, e1 = |p2p0| (already in metres).
        const double edge_m3[3] = {e2, e0, e1};
        const int ea[3] = {0, 1, 2};
        const int eb[3] = {1, 2, 0};
        for (int k = 0; k < 3; ++k) {
          const double dm = edge_m3[k];
          const double dsx = su[eb[k]] - su[ea[k]];
          const double dsy = sv[eb[k]] - sv[ea[k]];
          const double dt = std::sqrt(dsx * dsx + dsy * dsy);
          if (dm > 1e-4 && dt > 1e-6) {
            uv_push(mat->uv_dens_edge, (float)(dt / dm));
          }
        }
      }

      // EDGE law: each edge is levelled by ITS OWN world-space length at ITS OWN midpoint dist.
      double inner_edge;
      if (dmin > 30.0) {
        inner_edge = 1.0;
      } else {
        const double l0 = edge_law_level(e0, d0, tess_max, seg_near, seg_d0, seg_far, seg_exp,
                                         fade_lo, fade_hi);
        const double l1 = edge_law_level(e1, d1, tess_max, seg_near, seg_d0, seg_far, seg_exp,
                                         fade_lo, fade_hi);
        const double l2 = edge_law_level(e2, d2, tess_max, seg_near, seg_d0, seg_far, seg_exp,
                                         fade_lo, fade_hi);
        inner_edge = std::max(std::max(l0, l1), l2);
      }

      accumulate_cls(cls_band[0][cls][band], inner_new, e0, e1, e2);
      accumulate_cls(cls_band[1][cls][band], inner_edge, e0, e1, e2);
      // section G2: same EDGE-law cell, restricted to GROUND *with* a displacement source.
      if (cls == 0 && mat && mat->has_height) {
        accumulate_cls(gh_band[band], inner_edge, e0, e1, e2);
      }

      // ---- ROUND 28: the two laws, evaluated with THIS draw's measured lambda_world_m ----
      // Whole-patch far gate is the tesc's own (main(): dmin > TESS_FADE_HI_M => passthrough),
      // i.e. --fade-hi, NOT the hardcoded 30 m the legacy sections above still use.
      if (do_r28) {
        const int b28 = r28_band_of(dmin);
        for (int law = 0; law < 2; ++law) {
          const bool r28 = (law == 1);
          double inner;
          if (dmin > p28.fade_hi) {
            inner = 1.0;
          } else {
            const double l0 = r28_edge_level(e0, d0, lambda_world_m, r28, p28);
            const double l1 = r28_edge_level(e1, d1, lambda_world_m, r28, p28);
            const double l2 = r28_edge_level(e2, d2, lambda_world_m, r28, p28);
            inner = std::max(std::max(l0, l1), l2);
          }
          r28_accum(r28_all[law][b28], inner, mean_edge_m, lambda_world_m, p28.tess_max);
          r28_accum(r28_cls[law][cls][b28], inner, mean_edge_m, lambda_world_m, p28.tess_max);
          if (r28cells) {
            r28_accum((*r28cells)[b28][law], inner, mean_edge_m, lambda_world_m, p28.tess_max);
          }
        }
      }

      if (mat && dmin < 15.0) {
        mat->patches++;
        if (cls == 0) {
          mat->ground++;
        } else {
          mat->wall++;
        }
        mat->sum_edge_m += mean_edge_m;
        mat->sum_edge_spacing_m += mean_edge_m / std::max(inner_edge, 1.0);
        mat->sum_shipped_spacing_m += mean_edge_m / std::max(inner_new, 1.0);
      }

      // ---- section I: GROUND displacement-source coverage, by patch count AND world area ----
      if (cls == 0) {
        // |cross(p1-p0, p2-p0)| = 2 * triangle area, in game units^2.
        const double area_m2 = 0.5 * nlen / ((double)kUnitsPerM * (double)kUnitsPerM);
        const bool has_h = mat && mat->has_height;
        for (int rr = 0; rr < kNumRanges; ++rr) {
          if (dmin < kRangeMax[rr]) {
            disp[rr].patches++;
            disp[rr].area_m2 += area_m2;
            if (has_h) {
              disp[rr].patches_h++;
              disp[rr].area_m2_h += area_m2;
            }
          }
        }
        if (mat && dmin < 15.0) {
          mat->ground_area_m2 += area_m2;
          mat->sum_ground_edge_spacing_m += mean_edge_m / std::max(inner_edge, 1.0);
        }
      }

      // ---- section I2: SIGNED orientation, evaluated with BOTH normals ----
      // The unsigned |n.y| test above cannot separate a floor from a ceiling; these can.
      const double area_m2_all = 0.5 * nlen / ((double)kUnitsPerM * (double)kUnitsPerM);
      const int fcls = signed_class(nlen < 1e-12 ? 0.0 : ny / nlen, ground_cos);
      const Vec3 sn0 = unpack_gl_normal_2_10_10_10(verts[i0].nor);
      const Vec3 sn1 = unpack_gl_normal_2_10_10_10(verts[i1].nor);
      const Vec3 sn2 = unpack_gl_normal_2_10_10_10(verts[i2].nor);
      const bool zero0 = (sn0.x == 0.f && sn0.y == 0.f && sn0.z == 0.f);
      const bool zero1 = (sn1.x == 0.f && sn1.y == 0.f && sn1.z == 0.f);
      const bool zero2 = (sn2.x == 0.f && sn2.y == 0.f && sn2.z == 0.f);
      if (zero0 || zero1 || zero2) {
        smooth_partial++;
      }
      const double ssx = (double)sn0.x + sn1.x + sn2.x;
      const double ssy = (double)sn0.y + sn1.y + sn2.y;
      const double ssz = (double)sn0.z + sn1.z + sn2.z;
      const double sslen = std::sqrt(ssx * ssx + ssy * ssy + ssz * ssz);
      int scls;
      if (sslen < 1e-6) {
        smooth_missing++;
        scls = 2;  // WALL (no usable smooth normal)
      } else {
        scls = signed_class(ssy / sslen, ground_cos);
      }
      signed_face[fcls]++;
      signed_smooth[scls]++;
      confusion[fcls][scls]++;

      const bool has_h2 = mat && mat->has_height;
      if (scls == 0) {  // FLOOR by the renderer's normal
        for (int rr = 0; rr < kNumRanges; ++rr) {
          if (dmin < kRangeMax[rr]) {
            disp_floor[rr].patches++;
            disp_floor[rr].area_m2 += area_m2_all;
            if (has_h2) {
              disp_floor[rr].patches_h++;
              disp_floor[rr].area_m2_h += area_m2_all;
            }
          }
        }
      }
      if (fcls == 0) {  // FLOOR by the winding normal
        for (int rr = 0; rr < kNumRanges; ++rr) {
          if (dmin < kRangeMax[rr]) {
            disp_floor_f[rr].patches++;
            disp_floor_f[rr].area_m2 += area_m2_all;
            if (has_h2) {
              disp_floor_f[rr].patches_h++;
              disp_floor_f[rr].area_m2_h += area_m2_all;
            }
          }
        }
      }
      if (mat && dmin < 15.0) {
        if (scls == 0) {
          mat->floor_patches++;
          mat->floor_area_m2 += area_m2_all;
          mat->sum_floor_edge_spacing_m += mean_edge_m / std::max(inner_edge, 1.0);
        } else if (scls == 1) {
          mat->ceiling_patches++;
          mat->ceiling_area_m2 += area_m2_all;
        }
      }
    };

    for (const auto& draw : tree.draws) {
      draws_counted++;
      // OWNER #18: the draw's material name (negative tree_tex_id = animated texture slot).
      const std::string mat_name =
          (draw.tree_tex_id >= 0 && (size_t)draw.tree_tex_id < lev.textures.size())
              ? lev.textures[draw.tree_tex_id].debug_name
              : fmt::format("<anim{}>", draw.tree_tex_id);
      MatStat* mat = &mat_stats[mat_name];
      mat->has_height = pbr_materials().count(mat_name) > 0;
      // ROUND 28: the per-draw uniforms PbrDrawBinder::set pushes for THIS material.
      double lambda_world_m = kIdentityLambda.world_m();
      R28MatCells* r28cells = nullptr;
      if (do_r28) {
        auto mlit = mat_lambda.find(mat_name);
        lambda_world_m = (mlit != mat_lambda.end()) ? mlit->second.world_m()
                                                    : kIdentityLambda.world_m();
        r28cells = &r28_mat[mat_name];
      }
      const u32 first = draw.unpacked.idx_of_first_idx_in_full_buffer;
      u32 count = 0;
      for (const auto& grp : draw.vis_groups) {
        count += grp.num_inds;
      }
      if ((u64)first + (u64)count > (u64)inds.size()) {
        oob_draws++;
        continue;
      }
      if (strips) {
        u32 a = UINT32_MAX, b = UINT32_MAX;
        int strip_pos = 0;
        for (u32 k = 0; k < count; k++) {
          const u32 idx = inds[first + k];
          if (idx == UINT32_MAX) {
            a = b = UINT32_MAX;
            strip_pos = 0;
            continue;
          }
          if (strip_pos < 2) {
            if (strip_pos == 0) {
              a = idx;
            } else {
              b = idx;
            }
            strip_pos++;
          } else {
            const u32 c = idx;
            u32 t0, t1, t2;
            if ((strip_pos & 1) == 0) {
              t0 = a;
              t1 = b;
              t2 = c;
            } else {
              t0 = b;
              t1 = a;
              t2 = c;
            }
            if (t0 != t1 && t1 != t2 && t0 != t2) {  // skip degenerates
              emit_patch(t0, t1, t2, mat, lambda_world_m, r28cells);
            }
            a = b;
            b = c;
            strip_pos++;
          }
        }
      } else {
        for (u32 k = 0; k + 2 < count; k += 3) {
          const u32 t0 = inds[first + k];
          const u32 t1 = inds[first + k + 1];
          const u32 t2 = inds[first + k + 2];
          if (t0 == UINT32_MAX || t1 == UINT32_MAX || t2 == UINT32_MAX) {
            continue;
          }
          if (t0 != t1 && t1 != t2 && t0 != t2) {
            emit_patch(t0, t1, t2, mat, lambda_world_m, r28cells);
          }
        }
      }
    }
  }

  // ---- report ----
  std::string r;
  auto line = [&](const std::string& s) { r += s; r += "\n"; };

  line("##### TESS AUDIT (offline, desktop) #####");
  line(fmt::format("fr3               : {}", fr3_path.string()));
  line(fmt::format("level             : {}", lev.level_name));
  line(fmt::format("geom LOD audited  : {}  (Gfx::g_global_settings.lod_tfrag default = 0; "
                   "TFragment draws one geom at a time)",
                   geom));
  line(fmt::format("tfrag tree census : {}", geom_census));
  line(fmt::format("geometry prep     : {}", prep_note));
  line(fmt::format("subdivision       : {}", subdiv_m > 0.0 ? "ON" : "OFF"));
  line(subdiv_note);
  line(fmt::format("camera (game u)   : {:.1f} {:.1f} {:.1f}", cam.x, cam.y, cam.z));
  line(fmt::format("camera (metres)   : {:.3f} {:.3f} {:.3f}", cam.x / kUnitsPerM,
                   cam.y / kUnitsPerM, cam.z / kUnitsPerM));
  line(fmt::format("camera source     : {}",
                   have_cam ? (cam_from_metres ? "SUPPLIED via --cam-m (metres)"
                                               : "SUPPLIED via --cam (game units)")
                            : fmt::format("CENTROID of all {} tessellable tfrag vertices (geom {})",
                                          centroid_n, geom)));
  line(fmt::format("tess_max (NEW law): {:.0f}", tess_max));
  line("triangle estimate : GL fractional_odd_spacing rounds a tess level up to the next ODD "
       "integer, so with L = next odd integer >= inner level (L>=1), generated triangles per patch "
       "~= L*L. L*L is the standard triangle-domain count for inner level L; this is an ESTIMATE "
       "(the exact count also depends on the three outer levels).");
  line("distance          : |world - cam| / 4096 (metres), exactly as tfrag3_tess.tesc's "
       "cam_dist_m(); edge level uses the edge MIDPOINT distance, the far gate uses dmin = min "
       "corner distance.");
  line("band-limit        : texels_per_sample = spacing_m * WORLD_TILES_PER_M(0.5) * 2048 "
       "(shipped height-map resolution); matched_mip_lod = log2(max(texels_per_sample, 1)).");
  line("OLD law           : if dmin > 30 -> all levels 1; else outer_i = mix(12,1,clamp((d_i-8)/"
       "22,0,1)); inner = max(outer).");
  line(fmt::format("NEW law           : if dmin > 30 -> all levels 1; else outer_i = clamp(128/"
                   "max(d_i,0.5), 1, {:.0f}); inner = max(outer).",
                   tess_max));
  line(fmt::format("seg law params    : EDGE law (section F/G/H): if dmin > 30 -> all levels 1; "
                   "else seg_target(d) = clamp(seg_near*pow(max(d,seg_d0)/seg_d0, seg_exp), "
                   "seg_near, seg_far), "
                   "lvl_i = edge_i_m / seg_target(d_i), lvl_i = mix(1, lvl_i, 1 - "
                   "smoothstep({:.1f}, {:.1f}, d_i)) [AMPLITUDE-MATCHED DENSITY FADE, the tese "
                   "fades displacement amplitude to 0 over the same band], outer_i = clamp(lvl_i, "
                   "1, {:.0f}); inner = max(outer). seg_near={:.3f}m seg_d0={:.3f}m "
                   "seg_far={:.3f}m seg_exp={:.3f} fade={:.1f}..{:.1f}m; feature ref = {:.2f} cm",
                   fade_lo, fade_hi, tess_max, seg_near, seg_d0, seg_far, seg_exp, fade_lo, fade_hi,
                   feature_cm));
  line(fmt::format("ground threshold  : GROUND when |face normal.y| >= {:.4f} (game Y is up), else "
                   "WALL; degenerate faces (|cross| < 1e-12) counted and classed WALL",
                   ground_cos));
  line("");

  line("##### B) TESSELLABLE-GEOMETRY CENSUS (kind NORMAL/DIRT/ICE) #####");
  line(fmt::format("trees             : {}", trees_counted));
  line(fmt::format("draws             : {}", draws_counted));
  line(fmt::format("vertices          : {}", verts_counted));
  line(fmt::format("patches (tris)    : {}", patches_total));
  if (oob_draws) {
    line(fmt::format("draws SKIPPED (index range out of bounds): {}", oob_draws));
  }
  {
    std::vector<float> sorted = edge_len_m;
    std::sort(sorted.begin(), sorted.end());
    double sum = 0.0;
    for (float v : sorted) {
      sum += v;
    }
    const double mean = sorted.empty() ? 0.0 : sum / (double)sorted.size();
    line(fmt::format("patch edges       : {}", sorted.size()));
    line("patch EDGE LENGTH distribution (metres):");
    line(fmt::format("  min={:.4f}  p10={:.4f}  median={:.4f}  mean={:.4f}  p90={:.4f}  max={:.4f}",
                     sorted.empty() ? 0.f : sorted.front(), percentile(sorted, 0.10),
                     percentile(sorted, 0.50), mean, percentile(sorted, 0.90),
                     sorted.empty() ? 0.f : sorted.back()));
  }
  line("");

  auto band_table = [&](const char* title, const LawBand* bands) {
    line(title);
    line("  band(m)     patches       mean_inner   max_inner   est_gen_tris    mean_spacing_cm   "
         "mean_mip_lod");
    for (int b = 0; b < kNumBands; ++b) {
      const auto& x = bands[b];
      const double n = (double)std::max<u64>(x.patches, 1);
      line(fmt::format("  {:<10} {:>11}   {:>10.3f}   {:>9.3f}   {:>12}   {:>15.3f}   {:>12.3f}",
                       kBandNames[b], x.patches, x.patches ? x.sum_inner / n : 0.0, x.max_inner,
                       x.gen_tris, x.patches ? (x.sum_spacing_m / n) * 100.0 : 0.0,
                       x.patches ? x.sum_mip_lod / n : 0.0));
    }
  };

  line("##### C) DISTANCE-BAND TABLE (bands by dmin) #####");
  band_table("--- OLD law (shipped today) ---", old_band);
  line("");
  band_table("--- NEW law (this round) ---", new_band);
  line("");

  // ---- D) totals + near-camera subtotal ----
  auto sum_over = [&](const LawBand* bands, int b0, int b1, LawBand& out) {
    for (int b = b0; b < b1; ++b) {
      out.patches += bands[b].patches;
      out.sum_inner += bands[b].sum_inner;
      out.max_inner = std::max(out.max_inner, bands[b].max_inner);
      out.gen_tris += bands[b].gen_tris;
      out.sum_spacing_m += bands[b].sum_spacing_m;
      out.sum_mip_lod += bands[b].sum_mip_lod;
    }
  };
  LawBand old_all, new_all, old_near, new_near;
  sum_over(old_band, 0, kNumBands, old_all);
  sum_over(new_band, 0, kNumBands, new_all);
  sum_over(old_band, 0, 2, old_near);  // [0,5) + [5,10) = < 10 m
  sum_over(new_band, 0, 2, new_near);

  auto ratio = [](u64 a, u64 b) { return b ? (double)a / (double)b : 0.0; };

  line("##### D) TOTALS #####");
  line(fmt::format("TOTALS      : patches={}  est_gen_tris OLD={}  NEW={}  ratio NEW/OLD={:.3f}",
                   old_all.patches, old_all.gen_tris, new_all.gen_tris,
                   ratio(new_all.gen_tris, old_all.gen_tris)));
  line(fmt::format(
      "NEAR (<10m) : patches={}  est_gen_tris OLD={}  NEW={}  ratio NEW/OLD={:.3f}",
      old_near.patches, old_near.gen_tris, new_near.gen_tris,
      ratio(new_near.gen_tris, old_near.gen_tris)));
  line("");

  const double old_near_mean = old_near.patches ? old_near.sum_inner / (double)old_near.patches : 0.0;
  const double new_near_mean = new_near.patches ? new_near.sum_inner / (double)new_near.patches : 0.0;
  line("##### E) SUMMARY #####");
  line(fmt::format("OLD mean inner level near camera = {:.2f}, NEW = {:.2f} (ceiling {:.0f})",
                   old_near_mean, new_near_mean, tess_max));

  // ---- F) OWNER #18: orientation-split tables (SHIPPED vs the new EDGE law) ----
  line("");
  line(std::string(80, '='));
  line(fmt::format("F. ORIENTATION-SPLIT TABLE  (GROUND = |face normal.y| >= {:.3f}, else WALL)",
                   ground_cos));
  line(fmt::format("   patches: GROUND={} WALL={} degenerate={}", class_patches[0], class_patches[1],
                   degenerate_patches));
  line(fmt::format("   EDGE law params: seg_near={:.3f}m seg_d0={:.3f}m seg_far={:.3f}m "
                   "seg_exp={:.3f} tess_max={:.0f} fade=mix(1,lvl,1-smoothstep({:.1f},{:.1f},"
                   "d_mid)) [amplitude-matched density fade]",
                   seg_near, seg_d0, seg_far, seg_exp, tess_max, fade_lo, fade_hi));
  line(fmt::format("   v/feature = {:.2f} cm reference feature wavelength / mean segment size",
                   feature_cm));

  // one per-band table over any ClassBand[kNumBands] population (used by F and by G2).
  auto cls_table_of = [&](const std::string& title, const ClassBand* bands) {
    line(title);
    line("  band(m)     patches       mean_inner   max_inner   est_gen_tris   mean_edge_m   "
         "p90_edge_m   mean_spacing_cm   p90_spacing_cm   v/feature   mean_mip_lod");
    for (int b = 0; b < kNumBands; ++b) {
      const auto& x = bands[b];
      const double n = (double)std::max<u64>(x.patches, 1);
      const double mean_sp_cm = x.patches ? (x.sum_spacing_m / n) * 100.0 : 0.0;
      line(fmt::format("  {:<10} {:>11}   {:>10.3f}   {:>9.3f}   {:>12}   {:>11.4f}   {:>10.4f}   "
                       "{:>15.3f}   {:>14.3f}   {:>9.2f}   {:>12.3f}",
                       kBandNames[b], x.patches, x.patches ? x.sum_inner / n : 0.0, x.max_inner,
                       x.gen_tris, meanf(x.edges_m), pct(x.edges_m, 0.90), mean_sp_cm,
                       pct(x.spacing_m, 0.90) * 100.0,
                       mean_sp_cm > 0.0 ? feature_cm / mean_sp_cm : 0.0,
                       x.patches ? x.sum_mip_lod / n : 0.0));
    }
  };
  for (int law = 0; law < kNumLaws; ++law) {
    for (int cls = 0; cls < kNumClasses; ++cls) {
      cls_table_of(fmt::format("--- {} | {} ---", kLawNames[law], kClassNames[cls]),
                   cls_band[law][cls]);
      line("");
    }
  }

  // ---- G) ground near-field (<10 m) head-to-head ----
  auto merge_bands = [&](const ClassBand* bands, int b0, int b1) {
    ClassBand o;
    for (int b = b0; b < b1; ++b) {
      const auto& x = bands[b];
      o.patches += x.patches;
      o.sum_inner += x.sum_inner;
      o.max_inner = std::max(o.max_inner, x.max_inner);
      o.gen_tris += x.gen_tris;
      o.sum_spacing_m += x.sum_spacing_m;
      o.sum_mip_lod += x.sum_mip_lod;
      o.edges_m.insert(o.edges_m.end(), x.edges_m.begin(), x.edges_m.end());
      o.spacing_m.insert(o.spacing_m.end(), x.spacing_m.begin(), x.spacing_m.end());
    }
    return o;
  };
  auto merge_cls = [&](int law, int cls, int b0, int b1) {
    return merge_bands(cls_band[law][cls], b0, b1);
  };
  const ClassBand g_ship = merge_cls(0, 0, 0, 2);  // GROUND, bands [0,5)+[5,10) = < 10 m
  const ClassBand g_edge = merge_cls(1, 0, 0, 2);
  const ClassBand w_ship = merge_cls(0, 1, 0, 2);
  const ClassBand w_edge = merge_cls(1, 1, 0, 2);
  auto mean_sp_cm_of = [](const ClassBand& x) {
    return x.patches ? (x.sum_spacing_m / (double)x.patches) * 100.0 : 0.0;
  };
  auto near_line = [&](const char* tag, const ClassBand& x) {
    const double msp = mean_sp_cm_of(x);
    return fmt::format("  {}: patches={} mean_inner={:.3f} mean_spacing_cm={:.3f} "
                       "p90_spacing_cm={:.3f} v/feature={:.2f} gen_tris={}",
                       tag, x.patches, x.patches ? x.sum_inner / (double)x.patches : 0.0, msp,
                       pct(x.spacing_m, 0.90) * 100.0, msp > 0.0 ? feature_cm / msp : 0.0,
                       x.gen_tris);
  };
  u64 tot_ship = 0, tot_edge = 0;
  for (int cls = 0; cls < kNumClasses; ++cls) {
    for (int b = 0; b < kNumBands; ++b) {
      tot_ship += cls_band[0][cls][b].gen_tris;
      tot_edge += cls_band[1][cls][b].gen_tris;
    }
  }
  line("G. GROUND NEAR-FIELD SUMMARY (<10 m)");
  line(near_line("SHIPPED", g_ship));
  line(near_line("EDGE   ", g_edge));
  line(fmt::format("  WALL near-field for comparison — SHIPPED: mean_spacing_cm={:.3f} gen_tris={} "
                   "| EDGE: mean_spacing_cm={:.3f} gen_tris={}",
                   mean_sp_cm_of(w_ship), w_ship.gen_tris, mean_sp_cm_of(w_edge),
                   w_edge.gen_tris));
  line(fmt::format("  TOTAL gen_tris (all bands): SHIPPED={} EDGE={} ratio EDGE/SHIPPED={:.3f}",
                   tot_ship, tot_edge, ratio(tot_edge, tot_ship)));

  // ---- G2) the ONLY population where tessellation density can become relief ----
  // A GROUND patch whose material ships no *_height.png has no displacement source: no tess level
  // can put relief on it, so mixing it into the G numbers dilutes v/feature into meaninglessness.
  // Same EDGE law, same columns as F, restricted to GROUND && material has_height.
  line("");
  line("G2. GROUND *WITH A DISPLACEMENT SOURCE* — the only surface where density can become relief");
  line(fmt::format("   population: GROUND (|face normal.y| >= {:.3f}) AND the draw's material ships "
                   "a *_height.png; EDGE law only",
                   ground_cos));
  cls_table_of(fmt::format("--- {} | GROUND with height map ---", kLawNames[1]), gh_band);
  {
    const ClassBand gh_near = merge_bands(gh_band, 0, 2);  // [0,5) + [5,10) = < 10 m
    const ClassBand& gh_b0 = gh_band[0];                   // [0,5) alone
    const double msp_near = mean_sp_cm_of(gh_near);
    const double msp_b0 = mean_sp_cm_of(gh_b0);
    line(near_line("EDGE   ", gh_near));
    line(fmt::format("G2 NEAR (<10m) GROUND v/feature {:.2f} | patches={} mean_spacing_cm={:.3f} "
                     "gen_tris={}",
                     msp_near > 0.0 ? feature_cm / msp_near : 0.0, gh_near.patches, msp_near,
                     gh_near.gen_tris));
    line(fmt::format("G2 [0,5)m GROUND v/feature {:.2f} | patches={} mean_spacing_cm={:.3f} "
                     "gen_tris={}",
                     msp_b0 > 0.0 ? feature_cm / msp_b0 : 0.0, gh_b0.patches, msp_b0,
                     gh_b0.gen_tris));
  }

  // ---- H) near-field material census (which materials the relief law actually has to serve) ----
  line("");
  line("H. MATERIALS WITHIN 15 m (top 15 by patch count)");
  {
    std::vector<std::pair<std::string, MatStat>> mats(mat_stats.begin(), mat_stats.end());
    std::sort(mats.begin(), mats.end(), [](const auto& a, const auto& b) {
      if (a.second.patches != b.second.patches) {
        return a.second.patches > b.second.patches;
      }
      return a.first < b.first;
    });
    line(fmt::format("  {:<32}  {:>9}  {:>8}  {:>11}  {:>20}  {:>23}  {:>4}", "material",
                     "patches", "ground%", "mean_edge_m", "EDGE mean_spacing_cm",
                     "SHIPPED mean_spacing_cm", "PBR?"));
    int shown = 0;
    for (const auto& [name, m] : mats) {
      if (m.patches == 0) {
        continue;
      }
      if (shown >= 15) {
        break;
      }
      shown++;
      const double n = (double)m.patches;
      line(fmt::format("  {:<32}  {:>9}  {:>7.1f}%  {:>11.4f}  {:>20.3f}  {:>23.3f}  {:>4}", name,
                       m.patches, 100.0 * (double)m.ground / n, m.sum_edge_m / n,
                       (m.sum_edge_spacing_m / n) * 100.0, (m.sum_shipped_spacing_m / n) * 100.0,
                       pbr_materials().count(name) ? "yes" : "no"));
    }
    if (shown == 0) {
      line("  (no tessellable tfrag patch within 15 m of the camera)");
    }
  }

  // ---- I) can the GROUND the owner is looking at be displaced AT ALL? ----
  // A material with no *_height.png has NO displacement source: no tessellation level can put
  // relief on it. Counted per patch AND weighted by world-space area (what the eye sees).
  line("");
  line(fmt::format("I. GROUND DISPLACEMENT-SOURCE COVERAGE  (GROUND = |face normal.y| >= {:.3f}; "
                   "source = the material ships a *_height.png)",
                   ground_cos));
  {
    std::string hm_list;
    for (const auto& m : pbr_materials()) {
      hm_list += (hm_list.empty() ? "" : ", ") + m;
    }
    line(fmt::format("   height-map materials ({}): {}", pbr_materials().size(), hm_list));
  }
  line(fmt::format("  {:<8}  {:>14}  {:>12}  {:>7}  {:>10}  {:>15}  {:>14}  {:>10}  {:>13}",
                   "range", "ground_patches", "with_height", "with%", "without%", "ground_area_m2",
                   "area_with_m2", "area_with%", "area_without%"));
  for (int rr = 0; rr < kNumRanges; ++rr) {
    const auto& x = disp[rr];
    const double pc = x.patches ? 100.0 * (double)x.patches_h / (double)x.patches : 0.0;
    const double pa = x.area_m2 > 0.0 ? 100.0 * x.area_m2_h / x.area_m2 : 0.0;
    line(fmt::format("  {:<8}  {:>14}  {:>12}  {:>6.1f}%  {:>9.1f}%  {:>15.2f}  {:>14.2f}  "
                     "{:>9.1f}%  {:>12.1f}%",
                     kRangeNames[rr], x.patches, x.patches_h, pc, 100.0 - pc, x.area_m2,
                     x.area_m2_h, pa, 100.0 - pa));
  }
  {
    const auto& x = disp[1];  // < 10 m
    const double pc = x.patches ? 100.0 * (double)x.patches_h / (double)x.patches : 0.0;
    const double pa = x.area_m2 > 0.0 ? 100.0 * x.area_m2_h / x.area_m2 : 0.0;
    line(fmt::format("  VERDICT: GROUND with a displacement source within 10 m: {} patches "
                     "({:.1f}%) / {:.2f} m^2 ({:.1f}%)",
                     x.patches_h, pc, x.area_m2_h, pa));
  }
  line("  --- top 10 GROUND materials by GROUND AREA within 15 m (height-map authoring priority) "
       "---");
  {
    std::vector<std::pair<std::string, MatStat>> mats(mat_stats.begin(), mat_stats.end());
    std::sort(mats.begin(), mats.end(), [](const auto& a, const auto& b) {
      if (a.second.ground_area_m2 != b.second.ground_area_m2) {
        return a.second.ground_area_m2 > b.second.ground_area_m2;
      }
      return a.first < b.first;
    });
    line(fmt::format("  {:<32}  {:>14}  {:>14}  {:>10}  {:>20}", "material", "ground_patches",
                     "ground_area_m2", "has_height", "EDGE mean_spacing_cm"));
    int shown = 0;
    for (const auto& [name, m] : mats) {
      if (m.ground == 0) {
        continue;
      }
      if (shown >= 10) {
        break;
      }
      shown++;
      line(fmt::format("  {:<32}  {:>14}  {:>14.2f}  {:>10}  {:>20.3f}", name, m.ground,
                       m.ground_area_m2, m.has_height ? "yes" : "no",
                       (m.sum_ground_edge_spacing_m / (double)m.ground) * 100.0));
    }
    if (shown == 0) {
      line("  (no GROUND patch within 15 m of the camera)");
    }
  }

  // ---- I2) SIGNED orientation: the |n.y| test above lumps CEILINGS in with FLOORS ----
  line("");
  line(fmt::format("I2. SIGNED ORIENTATION SPLIT  (FLOOR = n.y >= +{:.3f}, CEILING = n.y <= "
                   "-{:.3f}, else WALL)",
                   ground_cos, ground_cos));
  line(fmt::format("   face normal (winding cross(p1-p0,p2-p0)) : FLOOR={} CEILING={} WALL={}",
                   signed_face[0], signed_face[1], signed_face[2]));
  line(fmt::format("   smooth normal (PreloadedVertex::nor, the one the renderer lights with) : "
                   "FLOOR={} CEILING={} WALL={}",
                   signed_smooth[0], signed_smooth[1], signed_smooth[2]));
  line(fmt::format("   smooth-normal quality: patches with >=1 corner carrying no packed normal={}, "
                   "patches with no usable smooth normal at all (counted WALL)={}",
                   smooth_partial, smooth_missing));
  line("   CONFUSION face(row) x smooth(col), patches:");
  line(fmt::format("     {:<12}  {:>10}  {:>10}  {:>10}", "face\\smooth", kSignedNames[0],
                   kSignedNames[1], kSignedNames[2]));
  for (int i = 0; i < kNumSigned; ++i) {
    line(fmt::format("     {:<12}  {:>10}  {:>10}  {:>10}", kSignedNames[i], confusion[i][0],
                     confusion[i][1], confusion[i][2]));
  }
  {
    const u64 agree = confusion[0][0] + confusion[1][1] + confusion[2][2];
    const u64 flips = confusion[0][1] + confusion[1][0];
    const double n = (double)std::max<u64>(patches_total, 1);
    line(fmt::format("   agreement: {}/{} ({:.1f}%)  FLOOR<->CEILING sign flips: {} ({:.2f}%)",
                     agree, patches_total, 100.0 * (double)agree / n, flips,
                     100.0 * (double)flips / n));
  }
  auto disp_table = [&](const char* what, const DispRange* d) {
    line(fmt::format("--- {} coverage ---", what));
    line(fmt::format("  {:<8}  {:>14}  {:>12}  {:>7}  {:>10}  {:>15}  {:>14}  {:>10}  {:>13}",
                     "range", "floor_patches", "with_height", "with%", "without%", "floor_area_m2",
                     "area_with_m2", "area_with%", "area_without%"));
    for (int rr = 0; rr < kNumRanges; ++rr) {
      const auto& x = d[rr];
      const double pc = x.patches ? 100.0 * (double)x.patches_h / (double)x.patches : 0.0;
      const double pa = x.area_m2 > 0.0 ? 100.0 * x.area_m2_h / x.area_m2 : 0.0;
      line(fmt::format("  {:<8}  {:>14}  {:>12}  {:>6.1f}%  {:>9.1f}%  {:>15.2f}  {:>14.2f}  "
                       "{:>9.1f}%  {:>12.1f}%",
                       kRangeNames[rr], x.patches, x.patches_h, pc, 100.0 - pc, x.area_m2,
                       x.area_m2_h, pa, 100.0 - pa));
    }
  };
  disp_table("FLOOR ONLY (smooth/renderer normal)", disp_floor);
  disp_table("FLOOR ONLY (face/winding normal, for comparison)", disp_floor_f);
  {
    const auto& x = disp_floor[1];  // < 10 m
    const double pc = x.patches ? 100.0 * (double)x.patches_h / (double)x.patches : 0.0;
    const double pa = x.area_m2 > 0.0 ? 100.0 * x.area_m2_h / x.area_m2 : 0.0;
    line(fmt::format("  VERDICT (FLOOR only, smooth normal): FLOOR with a displacement source "
                     "within 10 m: {} patches ({:.1f}%) / {:.2f} m^2 ({:.1f}%)",
                     x.patches_h, pc, x.area_m2_h, pa));
    const auto& y = disp_floor_f[1];
    const double pcf = y.patches ? 100.0 * (double)y.patches_h / (double)y.patches : 0.0;
    const double paf = y.area_m2 > 0.0 ? 100.0 * y.area_m2_h / y.area_m2 : 0.0;
    line(fmt::format("  VERDICT (FLOOR only, face normal)   : FLOOR with a displacement source "
                     "within 10 m: {} patches ({:.1f}%) / {:.2f} m^2 ({:.1f}%)",
                     y.patches_h, pcf, y.area_m2_h, paf));
  }
  line("  --- top 10 FLOOR materials by FLOOR AREA within 15 m (smooth normal; authoring priority) "
       "---");
  {
    std::vector<std::pair<std::string, MatStat>> mats(mat_stats.begin(), mat_stats.end());
    std::sort(mats.begin(), mats.end(), [](const auto& a, const auto& b) {
      if (a.second.floor_area_m2 != b.second.floor_area_m2) {
        return a.second.floor_area_m2 > b.second.floor_area_m2;
      }
      return a.first < b.first;
    });
    line(fmt::format("  {:<32}  {:>14}  {:>14}  {:>10}  {:>20}", "material", "floor_patches",
                     "floor_area_m2", "has_height", "EDGE mean_spacing_cm"));
    int shown = 0;
    for (const auto& [name, m] : mats) {
      if (m.floor_patches == 0) {
        continue;
      }
      if (shown >= 10) {
        break;
      }
      shown++;
      line(fmt::format("  {:<32}  {:>14}  {:>14.2f}  {:>10}  {:>20.3f}", name, m.floor_patches,
                       m.floor_area_m2, m.has_height ? "yes" : "no",
                       (m.sum_floor_edge_spacing_m / (double)m.floor_patches) * 100.0));
    }
    if (shown == 0) {
      line("  (no FLOOR patch within 15 m of the camera)");
    }
  }
  line("  --- top 5 CEILING materials by CEILING AREA within 15 m (what the UNSIGNED test lumped "
       "into GROUND) ---");
  {
    std::vector<std::pair<std::string, MatStat>> mats(mat_stats.begin(), mat_stats.end());
    std::sort(mats.begin(), mats.end(), [](const auto& a, const auto& b) {
      if (a.second.ceiling_area_m2 != b.second.ceiling_area_m2) {
        return a.second.ceiling_area_m2 > b.second.ceiling_area_m2;
      }
      return a.first < b.first;
    });
    line(fmt::format("  {:<32}  {:>16}  {:>16}  {:>10}", "material", "ceiling_patches",
                     "ceiling_area_m2", "has_height"));
    int shown = 0;
    for (const auto& [name, m] : mats) {
      if (m.ceiling_patches == 0) {
        continue;
      }
      if (shown >= 5) {
        break;
      }
      shown++;
      line(fmt::format("  {:<32}  {:>16}  {:>16.2f}  {:>10}", name, m.ceiling_patches,
                       m.ceiling_area_m2, m.has_height ? "yes" : "no"));
    }
    if (shown == 0) {
      line("  (no CEILING patch within 15 m of the camera)");
    }
  }

  // ---- U) AUTHORED UV DENSITY vs the tese's hardcoded world projection ----
  // tfrag3_tess.tese samples the height map in a WORLD-SPACE projection at WORLD_TILES_PER_M = 0.5
  // (one tile = 2 m). The fragment path samples at the AUTHORED uv (tex_coord.xy * u_pbr_uv_tile).
  // This section measures the REAL authored density so the mismatch can be quantified per material.
  line("");
  line(std::string(80, '='));
  line("=== SECTION U: AUTHORED UV DENSITY / TILE WORLD SIZE (per material) ===");
  line(fmt::format(
      "density = texture tiles per world metre; tile_cm = 100/density = world size of ONE texture "
      "tile; the shader's tess path assumes {:.1f} tiles/m ({:.1f} cm).",
      kWorldTilesPerM, 100.0 / kWorldTilesPerM));
  line("  tri-density  : sqrt(uv_area_tiles2 / world_area_m2), one sample per TRIANGLE.");
  line("  edge-density : |duv|_tiles / |dpos|_m, one sample per triangle EDGE.");
  line("  population   : EVERY tessellable tfrag patch of the audited geom -- no camera-distance "
       "gate, UV density is a static authoring property. Per-material sample cap = 200000.");
  line("  checker_cm   : tile_cm / 8 = world size of ONE square of an 8x8-squares-per-tile "
       "checkerboard test pattern.");
  line(fmt::format("  ratio        : MEDIAN tri-density / {:.1f}; ratio > 1 means the authored "
                   "texture is FINER (tiles faster) than the tess path's world projection assumes.",
                   kWorldTilesPerM));
  {
    bool any_capped = false;
    auto u_header = [&]() {
      line(fmt::format("  {:<32}  {:>3}  {:>9}  {:>9}  {:>9}  {:>9}  {:>9}  {:>9}  {:>10}  {:>8}",
                       "material", "hgt", "tris", "p25", "MEDIAN", "p75", "edge_med", "tile_cm",
                       "checker_cm", "ratio"));
    };
    auto u_row = [&](const std::string& name, bool has_h, const std::vector<float>& tri,
                     const std::vector<float>& edge) {
      std::string s_tris = "-", s_p25 = "-", s_med = "-", s_p75 = "-", s_emed = "-", s_tile = "-",
                  s_chk = "-", s_ratio = "-";
      if (!tri.empty()) {
        const double med = pct(tri, 0.50);
        s_tris = fmt::format("{}{}", tri.size(), tri.size() >= kUvSampleCap ? "*" : "");
        if (tri.size() >= kUvSampleCap) {
          any_capped = true;
        }
        s_p25 = fmt::format("{:.4f}", pct(tri, 0.25));
        s_med = fmt::format("{:.4f}", med);
        s_p75 = fmt::format("{:.4f}", pct(tri, 0.75));
        if (med > 0.0) {
          const double tile_cm = 100.0 / med;
          s_tile = fmt::format("{:.2f}", tile_cm);
          s_chk = fmt::format("{:.2f}", tile_cm / 8.0);
          s_ratio = fmt::format("{:.3f}", med / kWorldTilesPerM);
        }
      }
      if (!edge.empty()) {
        s_emed = fmt::format("{:.4f}", pct(edge, 0.50));
        if (edge.size() >= kUvSampleCap) {
          any_capped = true;
        }
      }
      line(fmt::format("  {:<32}  {:>3}  {:>9}  {:>9}  {:>9}  {:>9}  {:>9}  {:>9}  {:>10}  {:>8}",
                       name, has_h ? "Y" : "N", s_tris, s_p25, s_med, s_p75, s_emed, s_tile, s_chk,
                       s_ratio));
    };

    std::vector<std::pair<std::string, MatStat>> mats(mat_stats.begin(), mat_stats.end());
    std::sort(mats.begin(), mats.end(), [](const auto& a, const auto& b) {
      if (a.second.uv_dens_tri.size() != b.second.uv_dens_tri.size()) {
        return a.second.uv_dens_tri.size() > b.second.uv_dens_tri.size();
      }
      return a.first < b.first;
    });

    line("");
    line("--- U1) ALL MATERIALS (every triangle, sorted by triangle count) ---");
    u_header();
    int shown = 0;
    for (const auto& [name, m] : mats) {
      if (m.uv_dens_tri.empty()) {
        continue;
      }
      shown++;
      u_row(name, m.has_height, m.uv_dens_tri, m.uv_dens_edge);
    }
    if (shown == 0) {
      line("  (no tessellable tfrag triangle with a measurable UV area)");
    }

    line("");
    line("--- U2) THE 7 PBR (height-map) MATERIALS, always listed so levels are comparable ---");
    u_header();
    for (const auto& name : pbr_materials()) {
      auto it = mat_stats.find(name);
      static const std::vector<float> kEmpty;
      if (it == mat_stats.end()) {
        u_row(name, true, kEmpty, kEmpty);
      } else {
        u_row(name, true, it->second.uv_dens_tri, it->second.uv_dens_edge);
      }
    }

    line("");
    line(fmt::format("--- U3) GROUND TRIANGLES ONLY (|face normal.y| >= {:.3f}), materials with >= "
                     "32 ground triangles ---",
                     ground_cos));
    u_header();
    std::vector<std::pair<std::string, MatStat>> gmats(mat_stats.begin(), mat_stats.end());
    std::sort(gmats.begin(), gmats.end(), [](const auto& a, const auto& b) {
      if (a.second.uv_dens_tri_ground.size() != b.second.uv_dens_tri_ground.size()) {
        return a.second.uv_dens_tri_ground.size() > b.second.uv_dens_tri_ground.size();
      }
      return a.first < b.first;
    });
    int gshown = 0;
    for (const auto& [name, m] : gmats) {
      if (m.uv_dens_tri_ground.size() < 32) {
        continue;
      }
      gshown++;
      // edge-density is not split by orientation; the column is the material's all-edge median.
      u_row(name, m.has_height, m.uv_dens_tri_ground, m.uv_dens_edge);
    }
    if (gshown == 0) {
      line("  (no material with >= 32 GROUND triangles)");
    }

    // ---- U4) triangle-count-weighted medians (pooling the per-triangle samples IS the
    // triangle-count weighting: every triangle contributes exactly one sample) ----
    std::vector<float> pool_all, pool_h, pool_ground;
    for (const auto& [name, m] : mat_stats) {
      pool_all.insert(pool_all.end(), m.uv_dens_tri.begin(), m.uv_dens_tri.end());
      if (m.has_height) {
        pool_h.insert(pool_h.end(), m.uv_dens_tri.begin(), m.uv_dens_tri.end());
      }
      pool_ground.insert(pool_ground.end(), m.uv_dens_tri_ground.begin(),
                         m.uv_dens_tri_ground.end());
    }
    auto summary = [&](const char* tag, const std::vector<float>& v) {
      if (v.empty()) {
        line(fmt::format("  {:<44}: tris=0  median=-  tile_cm=-  ratio=-", tag));
        return;
      }
      const double med = pct(v, 0.50);
      line(fmt::format("  {:<44}: tris={}  median={:.4f} tiles/m  tile_cm={:.2f}  ratio_vs_{:.1f}="
                       "{:.3f}  (p25={:.4f} p75={:.4f})",
                       tag, v.size(), med, med > 0.0 ? 100.0 / med : 0.0, kWorldTilesPerM,
                       med / kWorldTilesPerM, pct(v, 0.25), pct(v, 0.75)));
    };
    line("");
    line("--- U4) TRIANGLE-COUNT-WEIGHTED MEDIAN DENSITY (all per-triangle samples pooled) ---");
    summary("ALL materials", pool_all);
    summary("materials WITH a height map", pool_h);
    summary("GROUND triangles (all materials)", pool_ground);
    if (any_capped) {
      line(fmt::format("  NOTE: at least one sample vector hit the per-material cap of {} (marked "
                       "'*'); its percentiles are over the first {} samples in draw order.",
                       kUvSampleCap, kUvSampleCap));
    }
  }

  // ===============================================================================================
  // R28) THE FEATURE-AWARE DENSITY LAW, HEAD TO HEAD
  // ===============================================================================================
  if (do_r28) {
    line("");
    line(std::string(100, '='));
    line("=== SECTION R28: FEATURE-AWARE TESSELLATION DENSITY LAW (round-27 shipped vs round 28) ===");
    line("");
    line("LAWS (both are tfrag3_tess.tesc, ported line for line; OLD == NEW with the two");
    line("lambda-dependent steps removed, i.e. exactly what bisect bit 1 restores):");
    line(fmt::format("  lambda_world_m       = clamp(height_lambda_tiles, 0.002, 1.0) / max(uv_per_m, "
                     "1e-3)"));
    line(fmt::format("  seg_target(d)        : near_m = {:.4f} (--seg-near, u_pbr_tess_seg)",
                     p28.seg_near));
    line(fmt::format("     [NEW only]          near_m = clamp(lambda_world_m/{:.1f}, near_m*{:.1f}, "
                     "near_m*{:.1f})",
                     kTessSegPerFeature, kTessSegFeatMin, kTessSegFeatMax));
    line(fmt::format("                        return clamp(near_m*pow(max(d,{:.1f})/{:.1f}, {:.2f}), "
                     "near_m, max({:.2f}, near_m))",
                     p28.seg_d0, p28.seg_d0, p28.seg_exp, p28.seg_far));
    line(fmt::format("  edge_level(a,b)      : d = cam_dist_m(0.5*(a+b)); len_m = |b-a|/4096"));
    line(fmt::format("                        lvl = len_m / seg_target(d)"));
    line(fmt::format("                        lvl = mix(1, lvl, 1 - smoothstep({:.1f}, {:.1f}, d))",
                     p28.fade_lo, p28.fade_hi));
    line(fmt::format("                        lvl = clamp(lvl, 1, {:.0f})", p28.tess_max));
    line(fmt::format("     [NEW only]          spf = lambda_world_m*lvl/max(len_m,1e-6); "
                     "lvl = mix(1, lvl, smoothstep({:.1f}, {:.1f}, spf))",
                     kTessSpfRelease, kTessSpfKeep));
    line(fmt::format("                        return clamp(lvl, 1, {:.0f})", p28.tess_max));
    line(fmt::format("  whole-patch far gate : dmin > {:.1f} m => all levels 1 (tesc main(); this is "
                     "TESS_FADE_HI_M, NOT the",
                     p28.fade_hi));
    line("                         hardcoded 30 m the legacy sections A-U of this report still use)");
    line("  inner level          : max of the three outer levels (tesc: gl_TessLevelInner[0])");
    line("  gen tris per patch   : L*L with L = next ODD integer >= inner (GL fractional_odd_spacing)");
    line("  segment size         : mean patch edge / inner level (the same definition sections F/G "
         "use)");
    line("  segments per feature : lambda_world_m / segment size  (== the shader's own spf, since");
    line("                         spf = lambda*lvl/len = lambda/(len/lvl))");
    line("");
    line("PER-MATERIAL LAW INPUTS — lambda MEASURED from the shipped PNG with the exact");
    line("LoaderStages.cpp:measure_height_lambda_tiles() algorithm (stb_image decode, R channel),");
    line("uv_per_m MEASURED from this level's index buffer with the exact");
    line("background_common.cpp:measure_uv_density_tfrag() walk (geom 0, median of <=8192 edges).");
    line(fmt::format("  texture root: {}", tex_root.string()));
    r += r28_lambda_log;
    line(fmt::format("  every OTHER material (no *_height.png): runtime identity defaults "
                     "lambda_tiles={:.2f} uv_per_m={:.2f} => lambda_world_m={:.4f} m",
                     kIdentityLambda.lambda_tiles, kIdentityLambda.uv_per_m,
                     kIdentityLambda.world_m()));
    line("");

    const char* law_name[2] = {"OLD (round-27 shipped, feature-blind)",
                               "NEW (round-28 feature-aware)"};
    line(fmt::format("LEGEND: OLD = {} | NEW = {}", law_name[0], law_name[1]));
    line("");

    // ---- (A) per-material segments-per-feature, OLD vs NEW ----
    line(std::string(100, '-'));
    line("R28-A) SEGMENTS PER FEATURE, OLD vs NEW, per material per distance band");
    line("       (a band with no patch of that material AT THIS VANTAGE is printed as "
         "'NO PATCHES' — never interpolated)");
    auto mat_table = [&](const std::string& name) {
      auto it = r28_mat.find(name);
      auto lit = mat_lambda.find(name);
      const MatLambda& ml = (lit != mat_lambda.end()) ? lit->second : kIdentityLambda;
      line("");
      line(fmt::format("--- {} : lambda_tiles={:.6f} uv_per_m={:.6f} => lambda_world_m={:.6f} m "
                       "({:.3f} cm/feature) ---",
                       name, ml.lambda_tiles, ml.uv_per_m, ml.world_m(), ml.world_m() * 100.0));
      if (it == r28_mat.end()) {
        line("    NO PATCHES ANYWHERE in the audited geom for this material (no draw references it).");
        return;
      }
      line(fmt::format("  {:<10}  {:>9}  | {:>12}  {:>10}  {:>9}  | {:>12}  {:>10}  {:>9}  | "
                       "{:>9}  {:>9}",
                       "band(m)", "patches", "OLD seg_cm", "OLD seg/ft", "OLD lvl", "NEW seg_cm",
                       "NEW seg/ft", "NEW lvl", "seg NEW/OLD", "spf NEW/OLD"));
      for (int b = 0; b < kR28Bands; ++b) {
        const R28Cell& o = it->second[b][0];
        const R28Cell& n = it->second[b][1];
        if (o.patches == 0) {
          line(fmt::format("  {:<10}  {:>9}  | {}", kR28BandNames[b], 0,
                           "NO PATCHES of this material in this band at this vantage"));
          continue;
        }
        const double no = (double)o.patches, nn = (double)n.patches;
        const double o_seg = (o.sum_spacing_m / no) * 100.0;
        const double n_seg = (n.sum_spacing_m / nn) * 100.0;
        const double o_spf = o.sum_spf / no;
        const double n_spf = n.sum_spf / nn;
        line(fmt::format("  {:<10}  {:>9}  | {:>12.3f}  {:>10.3f}  {:>9.2f}  | {:>12.3f}  "
                         "{:>10.3f}  {:>9.2f}  | {:>9.3f}  {:>9.3f}",
                         kR28BandNames[b], o.patches, o_seg, o_spf, o.sum_inner / no, n_seg, n_spf,
                         n.sum_inner / nn, o_seg > 0.0 ? n_seg / o_seg : 0.0,
                         o_spf > 0.0 ? n_spf / o_spf : 0.0));
      }
    };
    // the three the deliverable names first, then every other PBR material for context.
    for (const char* m : {"vil-wallplaster", "vil1-sages-strawroof-01", "vil-beach-01"}) {
      mat_table(m);
    }
    line("");
    line("--- the remaining height-map materials, same table ---");
    for (const auto& m : pbr_materials()) {
      if (m == "vil-wallplaster" || m == "vil1-sages-strawroof-01" || m == "vil-beach-01") {
        continue;
      }
      mat_table(m);
    }

    // ---- (B) whole-level generated triangles, OLD vs NEW ----
    line("");
    line(std::string(100, '-'));
    line(fmt::format("R28-B) TOTAL GENERATED TRIANGLES AT THIS VANTAGE, WHOLE LEVEL, cap {:.0f}",
                     p28.tess_max));
    R28Cell tot[2];
    for (int law = 0; law < 2; ++law) {
      for (int b = 0; b < kR28Bands; ++b) {
        r28_merge(tot[law], r28_all[law][b]);
      }
    }
    line(fmt::format("  TOTAL patches      : {}", tot[0].patches));
    line(fmt::format("  TOTAL gen_tris OLD : {}", tot[0].gen_tris));
    line(fmt::format("  TOTAL gen_tris NEW : {}", tot[1].gen_tris));
    line(fmt::format("  ratio NEW/OLD      : {:.4f}  ({:+.1f}%)",
                     tot[0].gen_tris ? (double)tot[1].gen_tris / (double)tot[0].gen_tris : 0.0,
                     tot[0].gen_tris ? 100.0 * ((double)tot[1].gen_tris / (double)tot[0].gen_tris -
                                                1.0)
                                     : 0.0));
    line("");
    line("  --- per DISTANCE BAND (bands by dmin) ---");
    line(fmt::format("  {:<10}  {:>10}  | {:>14}  {:>14}  {:>9}  | {:>10}  {:>10}  | {:>11}  "
                     "{:>11}",
                     "band(m)", "patches", "gen_tris OLD", "gen_tris NEW", "NEW/OLD",
                     "lvl OLD", "lvl NEW", "at-cap OLD", "at-cap NEW"));
    for (int b = 0; b < kR28Bands; ++b) {
      const R28Cell& o = r28_all[0][b];
      const R28Cell& n = r28_all[1][b];
      if (o.patches == 0) {
        line(fmt::format("  {:<10}  {:>10}  | NO PATCHES in this band at this vantage",
                         kR28BandNames[b], 0));
        continue;
      }
      line(fmt::format("  {:<10}  {:>10}  | {:>14}  {:>14}  {:>9.4f}  | {:>10.3f}  {:>10.3f}  | "
                       "{:>11}  {:>11}",
                       kR28BandNames[b], o.patches, o.gen_tris, n.gen_tris,
                       o.gen_tris ? (double)n.gen_tris / (double)o.gen_tris : 0.0,
                       o.sum_inner / (double)o.patches, n.sum_inner / (double)n.patches,
                       o.patches_at_cap, n.patches_at_cap));
    }
    line("");
    line(fmt::format("  --- per CLASS (GROUND = |face normal.y| >= {:.3f}, else WALL) x band ---",
                     ground_cos));
    for (int c = 0; c < kNumClasses; ++c) {
      R28Cell ctot[2];
      line(fmt::format("  {} :", kClassNames[c]));
      line(fmt::format("    {:<10}  {:>10}  | {:>14}  {:>14}  {:>9}  | {:>10}  {:>10}  | {:>12}  "
                       "{:>12}",
                       "band(m)", "patches", "gen_tris OLD", "gen_tris NEW", "NEW/OLD", "lvl OLD",
                       "lvl NEW", "seg_cm OLD", "seg_cm NEW"));
      for (int b = 0; b < kR28Bands; ++b) {
        const R28Cell& o = r28_cls[0][c][b];
        const R28Cell& n = r28_cls[1][c][b];
        r28_merge(ctot[0], o);
        r28_merge(ctot[1], n);
        if (o.patches == 0) {
          line(fmt::format("    {:<10}  {:>10}  | NO PATCHES of this class in this band at this "
                           "vantage",
                           kR28BandNames[b], 0));
          continue;
        }
        line(fmt::format("    {:<10}  {:>10}  | {:>14}  {:>14}  {:>9.4f}  | {:>10.3f}  {:>10.3f}  "
                         "| {:>12.3f}  {:>12.3f}",
                         kR28BandNames[b], o.patches, o.gen_tris, n.gen_tris,
                         o.gen_tris ? (double)n.gen_tris / (double)o.gen_tris : 0.0,
                         o.sum_inner / (double)o.patches, n.sum_inner / (double)n.patches,
                         (o.sum_spacing_m / (double)o.patches) * 100.0,
                         (n.sum_spacing_m / (double)n.patches) * 100.0));
      }
      line(fmt::format("    {:<10}  {:>10}  | {:>14}  {:>14}  {:>9.4f}", "TOTAL", ctot[0].patches,
                       ctot[0].gen_tris, ctot[1].gen_tris,
                       ctot[0].gen_tris ? (double)ctot[1].gen_tris / (double)ctot[0].gen_tris
                                        : 0.0));
    }

    // ---- (C) where is vil-beach-01 at this vantage? ----
    line("");
    line(std::string(100, '-'));
    line("R28-C) vil-beach-01 OCCUPANCY AT THIS VANTAGE (nearest band it actually occupies)");
    {
      auto it = r28_mat.find("vil-beach-01");
      if (it == r28_mat.end()) {
        line("  vil-beach-01 has NO patch anywhere in the audited geom.");
      } else {
        u64 within15 = 0;
        int nearest = -1;
        for (int b = 0; b < kR28Bands; ++b) {
          const u64 pn = it->second[b][0].patches;
          if (pn && nearest < 0) {
            nearest = b;
          }
          if (b <= 1) {  // [0,5) + [5,10) — fully inside 15 m
            within15 += pn;
          }
        }
        line(fmt::format("  patches within 10 m: {}", within15));
        line(fmt::format("  nearest occupied band: {}", nearest < 0 ? "NONE"
                                                                    : kR28BandNames[nearest]));
        for (int b = 0; b < kR28Bands; ++b) {
          line(fmt::format("    {:<10} patches={}", kR28BandNames[b], it->second[b][0].patches));
        }
        line("  (if the near bands are empty, re-run this tool with a --cam-m that stands on the "
             "beach; the tool prints no interpolated numbers for empty bands.)");
      }
    }
    // A camera-independent hint for (C): where the beach patches actually ARE.
    {
      double bx = 0, by = 0, bz = 0;
      u64 bn = 0;
      float minx = 1e30f, miny = 1e30f, minz = 1e30f;
      float maxx = -1e30f, maxy = -1e30f, maxz = -1e30f;
      s32 beach_tex = -1;
      for (size_t ti = 0; ti < lev.textures.size(); ++ti) {
        if (lev.textures[ti].debug_name == "vil-beach-01") {
          beach_tex = (s32)ti;
          break;
        }
      }
      if (beach_tex >= 0) {
        for (const auto& tree : lev.tfrag_trees[geom]) {
          if (!tess_opaque_kind(tree.kind)) {
            continue;
          }
          for (const auto& draw : tree.draws) {
            if (draw.tree_tex_id != beach_tex) {
              continue;
            }
            u32 cnt = 0;
            for (const auto& g : draw.vis_groups) {
              cnt += g.num_inds;
            }
            const u32 f = draw.unpacked.idx_of_first_idx_in_full_buffer;
            for (u32 k = 0; k < cnt; ++k) {
              if ((u64)f + k >= tree.unpacked.indices.size()) {
                break;
              }
              const u32 vi = tree.unpacked.indices[f + k];
              if (vi >= tree.unpacked.vertices.size()) {
                continue;
              }
              const auto& v = tree.unpacked.vertices[vi];
              bx += v.x;
              by += v.y;
              bz += v.z;
              bn++;
              minx = std::min(minx, v.x);
              miny = std::min(miny, v.y);
              minz = std::min(minz, v.z);
              maxx = std::max(maxx, v.x);
              maxy = std::max(maxy, v.y);
              maxz = std::max(maxz, v.z);
            }
          }
        }
      }
      if (bn) {
        line(fmt::format("  vil-beach-01 geometry: {} referenced verts, centroid (metres) = "
                         "{:.2f} {:.2f} {:.2f}",
                         bn, bx / (double)bn / kUnitsPerM, by / (double)bn / kUnitsPerM,
                         bz / (double)bn / kUnitsPerM));
        line(fmt::format("  vil-beach-01 AABB (metres): min {:.2f} {:.2f} {:.2f}  max {:.2f} {:.2f} "
                         "{:.2f}",
                         minx / kUnitsPerM, miny / kUnitsPerM, minz / kUnitsPerM, maxx / kUnitsPerM,
                         maxy / kUnitsPerM, maxz / kUnitsPerM));
      } else {
        line("  vil-beach-01 geometry: no vertex referenced by a tessellable tfrag draw.");
      }
    }
  }

  fmt::print("{}", r);
  std::ofstream out(out_path, std::ios::out | std::ios::trunc);
  if (!out) {
    fmt::print("error: cannot open out file '{}'\n", out_path);
    return 1;
  }
  out << r;
  out.close();
  fmt::print("\n[tess_audit] report written to {}\n", out_path);
  return 0;
}
