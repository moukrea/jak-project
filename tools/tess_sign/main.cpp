// Grecharged-pbr-realtime-fusion: TESS SIGN TEST — an OFFLINE CPU PORT of
// game/graphics/opengl_renderer/shaders/tfrag3_tess.tesc + tfrag3_tess.tese that measures, per mesh,
// the SIGN and the NON-ZERO-NESS of the tessellation displacement.
//
// THE QUESTION THIS TOOL ANSWERS, and why it exists. Every previous round reasoned about plausible
// CAUSES of the owner's "le displacement rentre au lieu de sortir" (grass, derivative TBN, mirrored
// instances, a global density law, delivery) without ever measuring the OUTPUT SIGN itself. This
// tool measures exactly that, programmatically, per mesh:
//   * WHITE checker squares (height 255, h > 0.5) must move ALONG the surface's OUTWARD direction,
//   * BLACK squares (height 0, h < 0.5) must move AGAINST it.
// "Outward" is established PURELY GEOMETRICALLY and NEVER from lev.collision — the collision
// authority is what produced the round-29 defect, so here it is only ever REPORTED alongside, never
// believed. The PRIMARY authority is PER FACE and needs no propagation at all (tier RAYF, "lancer de
// rayon sortant": the visible side of a surface is the side with open space on it); the per-shell
// signed volume (VOL) and escape asymmetry (ESC) are only fallbacks for the faces RAYF cannot call.
//
// Read-only with respect to the game: nothing under game/graphics/opengl_renderer/shaders/ is
// touched, and this file is a standalone COPY of the tools/tess_audit helpers (that tool is not
// refactored).
//
// Usage: see usage() below.

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <set>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#include "common/custom_data/MeshConsolidate.h"
#include "common/custom_data/MeshSubdivide.h"
#include "common/custom_data/Tfrag3Data.h"
#include "common/util/FileUtil.h"
#include "common/util/Serializer.h"
#include "common/util/compress.h"
#include "common/util/md5.h"

#include "fmt/format.h"

// NOTE: FileUtil.h already defines `namespace fs = ghc::filesystem`; reuse it.

static void usage() {
  fmt::print(
      "Usage: tess_sign [--fr3 PATH] [--tex-root PATH] [--dist-m D] [--sweep] [--tess-max N]\n"
      "                 [--tess-seg M] [--relief R] [--geom N] [--geom-tie N] [--subdiv M]\n"
      "                 [--subdiv-rounds N] [--force-live] [--use-sidecar] [--geom-orient]\n"
      "                 [--named-case NAME x0 x1 y0 y1 z0 z1] [--out PATH] [--csv PATH]\n"
      "                 [--max-verts-per-mesh N] [--rayf-k N]\n"
      "  --fr3 PATH        level fr3 (default <repo>/out/jak1/fr3/village1.fr3)\n"
      "  --tex-root PATH   root scanned for <name>_height.png (default\n"
      "                    <repo>/custom_assets/jak1/recharged_textures)\n"
      "  --dist-m D        canonical INSPECTION DISTANCE in metres (default 3.0)\n"
      "  --sweep           also emit section F, the distance-sweep diagnostic table\n"
      "  --tess-max N      u_pbr_tess_max (default 64)\n"
      "  --tess-seg M      u_pbr_tess_seg (default 0.025)\n"
      "  --relief R        the relief slider; u_pbr_height_scale = 0.05*R (default 1.5)\n"
      "  --geom N          tfrag geom LOD (default 0)\n"
      "  --geom-tie N      tie geom LOD (default 0)\n"
      "  --subdiv M        pre-subdivision longest-edge target in metres (default 1.6, 0 = off)\n"
      "  --subdiv-rounds N pre-subdivision round cap (default 3)\n"
      "  --force-live      ignore the .meshweld sidecar and run mesh_consolidate live (DEFAULT ON)\n"
      "  --use-sidecar     opposite of --force-live: try the sidecar first\n"
      "  --geom-orient     OR 512 (kMeshBitGeomOrient) into the mesh_consolidate config bits: the\n"
      "                    deep, offline-only PER-FACE geometric orientation authority\n"
      "  --rayf-k N        rays per hemisphere in the per-face RAYF tier (default 13)\n"
      "  --named-case NAME x0 x1 y0 y1 z0 z1\n"
      "                    label meshes whose CENTROID falls in this METRE box. Repeatable.\n"
      "  --out PATH        report path (default <repo>/.autoport/reports/\n"
      "                    Grecharged-pbr-realtime-fusion/tess_sign.txt)\n"
      "  --csv PATH        csv path (default: tess_sign.csv next to --out)\n"
      "  --max-verts-per-mesh N  generated-vertex sampling cap per mesh (default 200000)\n");
}

namespace {

// ===============================================================================================
// CONSTANTS
// ===============================================================================================
constexpr double kUnitsPerM = 4096.0;

// ---- tfrag3_tess.tesc / .tese COMPILE-TIME constants (cited at every use site below) ----
constexpr double kTessSegD0M = 5.0;         // .tesc:95  TESS_SEG_D0_M
constexpr double kTessSegFarM = 0.60;       // .tesc:96  TESS_SEG_FAR_M
constexpr double kTessSegExp = 1.5;         // .tesc:118 TESS_SEG_EXP
constexpr double kTessFadeLoM = 40.0;       // .tesc:107 TESS_FADE_LO_M
constexpr double kTessFadeHiM = 60.0;       // .tesc:108 TESS_FADE_HI_M
constexpr double kTessSpacingSafety = 1.25; // .tese:128 TESS_SPACING_SAFETY
constexpr double kTessLodBias = 0.5;        // .tese:133 TESS_LOD_BIAS
constexpr double kTessDepthK = 5.0;         // .tese:55  TESS_DEPTH_K
constexpr double kPbrDriveExp = 1.4;        // .tese:81  PBR_DRIVE_EXP
constexpr double kTessDepthMaxRatio = 1.25; // .tese:82  TESS_DEPTH_MAX_RATIO
constexpr double kTessDepthMaxM = 0.15;     // .tese:83  TESS_DEPTH_MAX_M
constexpr double kTessDispUnitsPerM = 4096.0;  // .tese:51 TESS_DISP_UNITS_PER_M
constexpr double kSeamBand = 0.25;          // .tese:382 SEAM_BAND

// ---- UNIFORM TRUTH. Read from background_common.cpp, NOT from the (dead) GLSL #defines.
// background_common.cpp:1792 height_scale = 0.05f, :2020 height_scale *= relief
// background_common.cpp:1851 pbr_tess_max = 64.0f      (:1997 clamped to GL_MAX_TESS_GEN_LEVEL)
// background_common.cpp:1863 pbr_tess_seg = 0.025f      (:2036 clamped to [0.01, 2.0])
// background_common.cpp:2032 u_pbr_displacement = 2 when the Displacement setting is Tessellation
// background_common.cpp:1999 u_pbr_bisect = 0 by default (no A/B bit set)
// LoaderStages.cpp:419-425  the CHECKER's u_pbr_height_stat = (0.5, 1.0) and
//                           u_pbr_height_lambda = 2.0 / squares_per_tile = 2.0/8 = 0.25
constexpr double kPbrHeightLambda = 0.25;
constexpr double kPbrHeightStatMean = 0.5;
constexpr double kPbrHeightStatNorm = 1.0;
// PbrTestPattern.cpp:20 kMapDim, :264 squares_per_tile() default 8.
constexpr int kCheckerDim = 256;
constexpr int kCheckerSquaresPerTile = 8;
// PbrDrawBinder::set (background_common.cpp:884) pushes 0.5 when the measurement is "unknown".
constexpr double kUvPerMFallback = 0.5;

// ---- ground-truth tier constants (§5) ----
constexpr double kVolEps = 1e-3;                 // TIER VOL: |V6| > kVolEps * L^3
constexpr double kRayEdgeEps = 1e-6;             // Moller-Trumbore ambiguity margin
constexpr double kProbeEpsM = 0.01;              // 1 cm probe offset (TIER ESC)
constexpr int kMaxSampleFaces = 64;              // TIER ESC sampled faces per shell
constexpr double kEscMargin = 1.25;              // TIER ESC needs the winner 25% ahead
constexpr double kEscMaxM = 60.0;                // TIER ESC free-distance cap
// ROUND 29's collision competence filter (MeshConsolidate.cpp:1415 / :1420).
constexpr double kCollParallelMin = 0.35;
constexpr double kCollConfMin = 0.15;

// ---- TIER RAYF: the PER-FACE outward ray test, the PRIMARY ground truth (§5a) ----
// It needs no propagation and no global orientation whatsoever: each face decides alone, from the
// open space on its two sides. Every number here is a compile-time constant, every direction is a
// pure function of the face's own geometric normal, and there is NO RNG, no clock and no
// address-dependent ordering anywhere, so the verdict is bit-reproducible run to run and independent
// of the thread count.
constexpr double kRayfProbeM = 0.02;   // probe offset either side of the face, metres (= 81.92 units)
constexpr double kRayfMaxM = 200.0;    // a ray ESCAPES when it finds no hit within this distance
constexpr double kRayfTMinM = 0.001;   // hits closer than this are ignored
constexpr int kRayfKDefault = 13;      // rays per hemisphere
constexpr int kRayfMinMargin = 2;      // |esc_plus - esc_minus| must reach this or the face abstains
constexpr double kRayfOcclEps = 1e-9;  // an edge-grazing hit COUNTS as a hit (conservative: it can
                                       // only ever say "did not escape", never invent an escape)

// The fixed 13-point (or --rayf-k point) hemisphere spiral, in the local frame of gn. Cosine-ish
// stratified: the i-th ray takes the stratum u = (i+0.5)/K of the projected-area measure, so
// sin(theta) = sqrt(u) and cos(theta) = sqrt(1-u), and the azimuth advances by the golden angle. The
// MINUS-side set is the EXACT MIRROR of the plus-side set (same tangential part, z negated), so the
// two hemispheres are sampled symmetrically and esc_plus / esc_minus cannot be biased against each
// other by the choice of frame.
constexpr double kGoldenConj = 0.6180339887498948482;

// ===============================================================================================
// SMALL MATH
// ===============================================================================================
struct V3 {
  double x = 0, y = 0, z = 0;
};
inline V3 operator+(const V3& a, const V3& b) { return V3{a.x + b.x, a.y + b.y, a.z + b.z}; }
inline V3 operator-(const V3& a, const V3& b) { return V3{a.x - b.x, a.y - b.y, a.z - b.z}; }
inline V3 operator*(const V3& a, double s) { return V3{a.x * s, a.y * s, a.z * s}; }
inline double dot(const V3& a, const V3& b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
inline V3 cross(const V3& a, const V3& b) {
  return V3{a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
inline double len(const V3& a) { return std::sqrt(dot(a, a)); }
inline V3 normalized(const V3& a) {
  const double l = len(a);
  return l > 0 ? a * (1.0 / l) : V3{0, 0, 0};
}

// Duff/Frisvad BRANCHLESS orthonormal basis (Duff et al., JCGT 6(1), 2017). (b1, b2, n) is
// orthonormal and every component is a pure arithmetic function of n — copysign is not a branch — so
// the RAYF direction set built from it is a pure function of the face's own geometric normal. No
// RNG, no clock, no address- or order-dependence anywhere.
inline void branchless_onb(const V3& n, V3* b1, V3* b2) {
  const double sg = std::copysign(1.0, n.z);
  const double a = -1.0 / (sg + n.z);
  const double b = n.x * n.y * a;
  *b1 = V3{1.0 + sg * n.x * n.x * a, sg * b, -sg * n.x};
  *b2 = V3{b, sg + n.y * n.y * a, -n.y};
}

// GLSL clamp / mix / smoothstep, in double.
inline double clampd(double v, double lo, double hi) {
  return v < lo ? lo : (v > hi ? hi : v);
}
inline double mixd(double a, double b, double t) { return a + (b - a) * t; }
inline double smoothstepd(double e0, double e1, double x) {
  const double t = clampd((x - e0) / (e1 - e0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}

// GL fractional_odd_spacing rounds a level up to the next ODD integer.
// (Bit-identical to tools/tess_audit's next_odd_ge.)
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

// ===============================================================================================
// LOAD (copied from tools/tess_audit/main.cpp:106-127 == Loader.cpp's unpack sequence)
// ===============================================================================================
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
  // shrub too: the .meshweld sidecar's fingerprint covers every tree the consolidation gathers.
  for (auto& shrub_tree : lev.shrub_trees) {
    shrub_tree.unpack();
  }
}

// Copy of the file-static unpack_gl_normal_2_10_10_10() in common/custom_data/TFrag3Data.cpp.
// PreloadedVertex::nor is a 2_10_10_10 packed field; this is the SMOOTH per-vertex normal the
// renderer lights with, and the one tfrag3_tess.tese barycentric-interpolates into `N`.
V3 unpack_gl_normal_2_10_10_10(u32 packed) {
  auto sext10 = [](u32 v) -> int {
    v &= 0x3ffu;
    return (v & 0x200u) ? (int)v - 1024 : (int)v;
  };
  const double nx = (double)sext10(packed);
  const double ny = (double)sext10(packed >> 10);
  const double nz = (double)sext10(packed >> 20);
  const double l = std::sqrt(nx * nx + ny * ny + nz * nz);
  if (l < 1e-6) {
    return V3{0, 0, 0};
  }
  return V3{nx / l, ny / l, nz / l};
}

// ===============================================================================================
// §7 uv_per_m — a VERBATIM port of background_common.cpp:541-693
// (kUvDensityMaxSamples :541, pbr_collect_uv_density :543, pbr_uv_density_median :650,
//  measure_uv_density_tfrag :661, measure_uv_density_tie :678)
// ===============================================================================================
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
      // positions are GAME UNITS (4096 per metre), texcoords are TILE units.
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

float measure_uv_density_tie(const tfrag3::Level& lev, s32 tex_idx, u32* out_samples) {
  std::vector<float> samples;
  samples.reserve(1024);
  // TieTree's unpacked vertices are the same tfrag3::PreloadedVertex type and its static_draws are
  // the same tfrag3::StripDraw, so the exact same edge walk applies (background_common.cpp:678).
  for (const auto& tree : lev.tie_trees[0]) {
    pbr_collect_uv_density(tree.static_draws, tree.unpacked.indices, tree.unpacked.vertices, tex_idx,
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

// ===============================================================================================
// §8 THE CHECKER — an exact reproduction of PbrTestPattern.cpp's HEIGHT map plus the mip chain
// glGenerateMipmap builds, and of the GL_LINEAR_MIPMAP_LINEAR / GL_REPEAT fetch.
//
// PARITY, stated explicitly (PbrTestPattern.cpp:51 checker_at, :126-138 profile_h with the
// round-26 default height_profile()==0, :155-157 make_height_rgba):
//   checker_at(px,py,cell) = ((px/cell) + (py/cell)) & 1
//   height texel          = checker_at ? 255 : 0
// so CELL (0,0) is checker 0 = height 0 = BLACK, and the WHITE albedo square (make_base_rgba:285
// paints 215 when checker_at == 1) is exactly the height-255 square. WHITE => h > 0.5 => must move
// OUT; BLACK => h < 0.5 => must move IN.
// ===============================================================================================
class Checker {
 public:
  Checker() {
    const int cell = kCheckerDim / kCheckerSquaresPerTile;  // PbrTestPattern.cpp:44 cell_size
    m_dim.push_back(kCheckerDim);
    std::vector<float> l0((size_t)kCheckerDim * kCheckerDim);
    for (int py = 0; py < kCheckerDim; py++) {
      for (int px = 0; px < kCheckerDim; px++) {
        const int c = ((px / cell) + (py / cell)) & 1;
        l0[(size_t)py * kCheckerDim + px] = c ? 255.f : 0.f;
      }
    }
    m_levels.push_back(std::move(l0));
    // The FULL mip chain 0..8 by successive 2x2 box averaging in float — what glGenerateMipmap does.
    while (m_dim.back() > 1) {
      const int pd = m_dim.back();
      const int nd = pd / 2;
      const auto& prev = m_levels.back();
      std::vector<float> nxt((size_t)nd * nd);
      for (int y = 0; y < nd; y++) {
        for (int x = 0; x < nd; x++) {
          const size_t r0 = (size_t)(2 * y) * pd + (size_t)(2 * x);
          const size_t r1 = (size_t)(2 * y + 1) * pd + (size_t)(2 * x);
          nxt[(size_t)y * nd + x] = 0.25f * (prev[r0] + prev[r0 + 1] + prev[r1] + prev[r1 + 1]);
        }
      }
      m_dim.push_back(nd);
      m_levels.push_back(std::move(nxt));
    }
    m_max_lod = (int)m_levels.size() - 1;  // 8 for a 256 map
  }

  int max_lod() const { return m_max_lod; }

  // textureLod(tex_PBR_H, uv, lod).r, in 0..1. GL_REPEAT wrap, half-texel centres, trilinear.
  double sample(double u, double v, double lod) const {
    const double l = clampd(lod, 0.0, (double)m_max_lod);
    const int l0 = (int)std::floor(l);
    const int l1 = std::min(l0 + 1, m_max_lod);
    const double f = l - (double)l0;
    const double a = bilinear(l0, u, v);
    const double b = bilinear(l1, u, v);
    return mixd(a, b, f) * (1.0 / 255.0);
  }

 private:
  double bilinear(int lvl, double u, double v) const {
    const int dim = m_dim[(size_t)lvl];
    const auto& img = m_levels[(size_t)lvl];
    const double cx = u * (double)dim - 0.5;
    const double cy = v * (double)dim - 0.5;
    const double fx0 = std::floor(cx);
    const double fy0 = std::floor(cy);
    const double fx = cx - fx0;
    const double fy = cy - fy0;
    const int x0 = wrap((long long)fx0, dim);
    const int y0 = wrap((long long)fy0, dim);
    const int x1 = wrap((long long)fx0 + 1, dim);
    const int y1 = wrap((long long)fy0 + 1, dim);
    const double t00 = img[(size_t)y0 * dim + x0];
    const double t10 = img[(size_t)y0 * dim + x1];
    const double t01 = img[(size_t)y1 * dim + x0];
    const double t11 = img[(size_t)y1 * dim + x1];
    return mixd(mixd(t00, t10, fx), mixd(t01, t11, fx), fy);
  }
  static int wrap(long long i, int dim) {
    long long m = i % (long long)dim;
    if (m < 0) {
      m += dim;
    }
    return (int)m;
  }
  std::vector<std::vector<float>> m_levels;
  std::vector<int> m_dim;
  int m_max_lod = 0;
};

// ===============================================================================================
// §6 THE SHADER PORT. Every step cites its shader line.
// ===============================================================================================

// .tesc:123-132 (and the bit-identical .tese:144-151) tess_seg_target_m().
double tess_seg_target_m(double d, double seg_near) {
  return clampd(seg_near * std::pow(std::max(d, kTessSegD0M) * (1.0 / kTessSegD0M), kTessSegExp),
                seg_near, std::max(kTessSegFarM, seg_near));
}

// .tesc:134-149 edge_level(). u_pbr_bisect == 0, so the legacy distance-only branch (:138) is dead.
double edge_level(double len_gu, double d, double tess_max, double seg_near) {
  const double cap = std::max(tess_max, 1.0);
  double lvl = (len_gu * (1.0 / kUnitsPerM)) / tess_seg_target_m(d, seg_near);
  // (b) the density fades with the displacement amplitude it exists to carry (.tesc:147).
  lvl = mixd(1.0, lvl, 1.0 - smoothstepd(kTessFadeLoM, kTessFadeHiM, d));
  return clampd(lvl, 1.0, cap);
}

// .tese:156-163 tess_spacing_m(). u_pbr_bisect == 0 so the legacy estimate branch (:157) is dead.
double tess_spacing_m(double d, double seg_near) {
  return clampd(tess_seg_target_m(d, seg_near) * kTessSpacingSafety, 0.005, 8.0);
}

// .tese:110-112 hnorm(). For the CHECKER u_pbr_height_stat == (0.5, 1.0) (LoaderStages.cpp:419-420),
// so this is the IDENTITY on [0,1] — implemented anyway, so a real map could be dropped in.
double hnorm(double h) {
  return clampd((h - kPbrHeightStatMean) * kPbrHeightStatNorm + 0.5, 0.0, 1.0);
}

// ===============================================================================================
// §3 THE TRIANGLE UNIVERSE — one flat face list over the whole level.
// ===============================================================================================
constexpr int kSysTfrag = 0;
constexpr int kSysTie = 1;
const char* kSysName[2] = {"TFRAG", "TIE"};

struct GVert {
  float x = 0, y = 0, z = 0;   // world position, GAME UNITS
  float s = 0, t = 0;          // authored texcoord, TILE units
  V3 nor;                      // unpacked smooth normal (zero if the vertex has none)
  float tx = 0, ty = 0, tz = 0, tw = 0;  // unpacked.tangents (zero when absent)
  float seam = 1.f;            // seam_w / 65535
  u8 subdiv_new = 0;           // 1 = CREATED by the pre-subdivision pass (index >= the pre-pass
                               // vertex count of its tree), so its seam is INHERITED from its two
                               // parents rather than decided by mesh_consolidate for its own group.
};

struct Face {
  u32 v[3] = {0, 0, 0};    // into the global vertex list
  u32 wg[3] = {0, 0, 0};   // weld group of each corner
  s32 tex = -1;            // draw.tree_tex_id
  u8 system = 0;           // kSysTfrag / kSysTie
  u16 tree = 0;
};

// ---- exact-float-triple weld groups (§4) --------------------------------------------------------
// mesh_consolidate() has snapped coincident positions BIT-IDENTICAL, so exact equality is the right
// test. -0.0f is canonicalised to +0.0f so bitwise equality means float equality.
struct PosKey {
  u32 x, y, z;
  bool operator==(const PosKey& o) const { return x == o.x && y == o.y && z == o.z; }
};
struct PosKeyHash {
  size_t operator()(const PosKey& k) const {
    u64 h = 1469598103934665603ull;
    for (u32 w : {k.x, k.y, k.z}) {
      for (int b = 0; b < 4; b++) {
        h ^= (u64)((w >> (8 * b)) & 0xffu);
        h *= 1099511628211ull;
      }
    }
    return (size_t)h;
  }
};
PosKey pos_key(float x, float y, float z) {
  auto bits = [](float f) -> u32 {
    if (f == 0.f) {
      f = 0.f;  // collapse -0.0f onto +0.0f
    }
    u32 u;
    std::memcpy(&u, &f, 4);
    return u;
  };
  return PosKey{bits(x), bits(y), bits(z)};
}

// ---- union-find over faces (shells) ------------------------------------------------------------
struct DSU {
  std::vector<u32> p;
  void init(size_t n) {
    p.resize(n);
    for (size_t i = 0; i < n; i++) {
      p[i] = (u32)i;
    }
  }
  u32 find(u32 a) {
    while (p[a] != a) {
      p[a] = p[p[a]];
      a = p[a];
    }
    return a;
  }
  void unite(u32 a, u32 b) {
    a = find(a);
    b = find(b);
    if (a == b) {
      return;
    }
    // always attach to the LOWER root: deterministic representative.
    if (a < b) {
      p[b] = a;
    } else {
      p[a] = b;
    }
  }
};

// ---- a BVH over the whole level face list, for the TIER B/C ray work -------------------------
struct Bvh {
  struct Node {
    double lo[3] = {0, 0, 0};
    double hi[3] = {0, 0, 0};
    u32 left = 0;    // child index (interior) or 0
    u32 first = 0;   // first entry in `order` (leaf)
    u32 count = 0;   // 0 = interior
  };
  std::vector<Node> nodes;
  std::vector<u32> order;

  void build(const std::vector<Face>& faces, const std::vector<GVert>& verts) {
    const size_t n = faces.size();
    order.resize(n);
    std::vector<double> cen(n * 3);
    std::vector<double> flo(n * 3), fhi(n * 3);
    for (size_t f = 0; f < n; f++) {
      order[f] = (u32)f;
      double lo[3] = {1e300, 1e300, 1e300}, hi[3] = {-1e300, -1e300, -1e300};
      for (int e = 0; e < 3; e++) {
        const auto& p = verts[faces[f].v[e]];
        const double q[3] = {p.x, p.y, p.z};
        for (int k = 0; k < 3; k++) {
          lo[k] = std::min(lo[k], q[k]);
          hi[k] = std::max(hi[k], q[k]);
        }
      }
      for (int k = 0; k < 3; k++) {
        flo[f * 3 + k] = lo[k];
        fhi[f * 3 + k] = hi[k];
        cen[f * 3 + k] = 0.5 * (lo[k] + hi[k]);
      }
    }
    nodes.clear();
    nodes.reserve(std::max<size_t>(1, 2 * n / 4 + 2));
    if (n == 0) {
      nodes.emplace_back();
      return;
    }
    build_rec(0, (u32)n, flo, fhi, cen);
  }

  // Visit every face whose AABB the ray may cross. `visit(face)` is called once per candidate.
  template <typename F>
  void traverse(const double o[3], const double d[3], double tmax, F&& visit) const {
    if (nodes.empty()) {
      return;
    }
    double inv[3];
    for (int k = 0; k < 3; k++) {
      inv[k] = (d[k] != 0.0) ? 1.0 / d[k] : 1e300;
    }
    u32 stack[128];
    int sp = 0;
    stack[sp++] = 0;
    while (sp > 0) {
      const Node& nd = nodes[stack[--sp]];
      if (!slab(nd, o, inv, tmax)) {
        continue;
      }
      if (nd.count) {
        for (u32 i = 0; i < nd.count; i++) {
          visit(order[nd.first + i]);
        }
      } else {
        if (sp + 2 <= 128) {
          stack[sp++] = nd.left;
          stack[sp++] = nd.left + 1;
        }
      }
    }
  }

  // OCCLUSION query: stops at the FIRST face for which test(face) is true. `test` must be a pure
  // function of (ray, face) so the answer cannot depend on the visit order.
  template <typename F>
  bool any_hit(const double o[3], const double d[3], double tmax, F&& test) const {
    if (nodes.empty()) {
      return false;
    }
    double inv[3];
    for (int k = 0; k < 3; k++) {
      inv[k] = (d[k] != 0.0) ? 1.0 / d[k] : 1e300;
    }
    u32 stack[128];
    int sp = 0;
    stack[sp++] = 0;
    while (sp > 0) {
      const Node& nd = nodes[stack[--sp]];
      if (!slab(nd, o, inv, tmax)) {
        continue;
      }
      if (nd.count) {
        for (u32 i = 0; i < nd.count; i++) {
          if (test(order[nd.first + i])) {
            return true;
          }
        }
      } else {
        if (sp + 2 <= 128) {
          stack[sp++] = nd.left;
          stack[sp++] = nd.left + 1;
        }
      }
    }
    return false;
  }

 private:
  static bool slab(const Node& nd, const double o[3], const double inv[3], double tmax) {
    double t0 = 0.0, t1 = tmax;
    for (int k = 0; k < 3; k++) {
      double a = (nd.lo[k] - o[k]) * inv[k];
      double b = (nd.hi[k] - o[k]) * inv[k];
      if (a > b) {
        std::swap(a, b);
      }
      t0 = std::max(t0, a);
      t1 = std::min(t1, b);
      if (t0 > t1) {
        return false;
      }
    }
    return true;
  }
  u32 build_rec(u32 first, u32 count, const std::vector<double>& flo,
                const std::vector<double>& fhi, const std::vector<double>& cen) {
    const u32 me = (u32)nodes.size();
    nodes.emplace_back();
    Node nd;
    for (int k = 0; k < 3; k++) {
      nd.lo[k] = 1e300;
      nd.hi[k] = -1e300;
    }
    for (u32 i = 0; i < count; i++) {
      const u32 f = order[first + i];
      for (int k = 0; k < 3; k++) {
        nd.lo[k] = std::min(nd.lo[k], flo[(size_t)f * 3 + k]);
        nd.hi[k] = std::max(nd.hi[k], fhi[(size_t)f * 3 + k]);
      }
    }
    if (count <= 8) {
      nd.first = first;
      nd.count = count;
      nodes[me] = nd;
      return me;
    }
    int axis = 0;
    double best = -1;
    for (int k = 0; k < 3; k++) {
      const double ext = nd.hi[k] - nd.lo[k];
      if (ext > best) {
        best = ext;
        axis = k;
      }
    }
    const u32 mid = count / 2;
    std::nth_element(order.begin() + first, order.begin() + first + mid,
                     order.begin() + first + count, [&](u32 a, u32 b) {
                       const double ca = cen[(size_t)a * 3 + axis];
                       const double cb = cen[(size_t)b * 3 + axis];
                       return ca < cb || (ca == cb && a < b);  // total order => deterministic
                     });
    nd.count = 0;
    nodes[me] = nd;
    const u32 l = build_rec(first, mid, flo, fhi, cen);
    build_rec(first + mid, count - mid, flo, fhi, cen);
    nodes[me].left = l;
    return me;
  }
};

// Moller-Trumbore in double, same contract as MeshConsolidate.cpp:1432-1466:
//   +1 clean forward hit (t written), 0 clean miss, -1 AMBIGUOUS (throw the whole ray away).
int ray_tri(const double o[3], const double d[3], const V3& v0, const V3& v1, const V3& v2,
            double* out_t) {
  const double e1[3] = {v1.x - v0.x, v1.y - v0.y, v1.z - v0.z};
  const double e2[3] = {v2.x - v0.x, v2.y - v0.y, v2.z - v0.z};
  const double pv[3] = {d[1] * e2[2] - d[2] * e2[1], d[2] * e2[0] - d[0] * e2[2],
                        d[0] * e2[1] - d[1] * e2[0]};
  const double det = e1[0] * pv[0] + e1[1] * pv[1] + e1[2] * pv[2];
  if (!(std::abs(det) > 1e-12)) {
    return 0;  // ray parallel to the plane: it skims, it does not cross
  }
  const double inv = 1.0 / det;
  const double tv[3] = {o[0] - v0.x, o[1] - v0.y, o[2] - v0.z};
  const double bu = (tv[0] * pv[0] + tv[1] * pv[1] + tv[2] * pv[2]) * inv;
  const double qv[3] = {tv[1] * e1[2] - tv[2] * e1[1], tv[2] * e1[0] - tv[0] * e1[2],
                        tv[0] * e1[1] - tv[1] * e1[0]};
  const double bv = (d[0] * qv[0] + d[1] * qv[1] + d[2] * qv[2]) * inv;
  const double bw = 1.0 - bu - bv;
  if (bu < -kRayEdgeEps || bv < -kRayEdgeEps || bw < -kRayEdgeEps) {
    return 0;
  }
  if (bu < kRayEdgeEps || bv < kRayEdgeEps || bw < kRayEdgeEps) {
    return -1;  // within 1e-6 of an edge/vertex: the crossing count is not trustworthy
  }
  const double tt = (e2[0] * qv[0] + e2[1] * qv[1] + e2[2] * qv[2]) * inv;
  if (tt < -kRayEdgeEps) {
    return 0;  // strictly behind the ray origin
  }
  if (tt < kRayEdgeEps) {
    return -1;  // the probe point sits ON this triangle
  }
  if (out_t) {
    *out_t = tt;
  }
  return 1;
}

// TIER RAYF's OCCLUSION test: does this triangle block the ray somewhere in (tmin, tmax]? Unlike
// ray_tri() above it does NOT need a trustworthy crossing COUNT (RAYF counts nothing, it only asks
// "is there anything there"), so an edge-grazing hit is ACCEPTED as a hit instead of poisoning the
// ray. That bias is one-directional and therefore safe: it can only ever turn an escape into a
// non-escape, never invent an escape, and it applies identically to both sides of the face.
inline bool ray_tri_occl(const double o[3], const double d[3], const V3& v0, const V3& v1,
                         const V3& v2, double tmin, double tmax) {
  const double e1[3] = {v1.x - v0.x, v1.y - v0.y, v1.z - v0.z};
  const double e2[3] = {v2.x - v0.x, v2.y - v0.y, v2.z - v0.z};
  const double pv[3] = {d[1] * e2[2] - d[2] * e2[1], d[2] * e2[0] - d[0] * e2[2],
                        d[0] * e2[1] - d[1] * e2[0]};
  const double det = e1[0] * pv[0] + e1[1] * pv[1] + e1[2] * pv[2];
  if (!(std::abs(det) > 1e-12)) {
    return false;  // parallel to the plane: it skims, it does not block
  }
  const double inv = 1.0 / det;
  const double tv[3] = {o[0] - v0.x, o[1] - v0.y, o[2] - v0.z};
  const double bu = (tv[0] * pv[0] + tv[1] * pv[1] + tv[2] * pv[2]) * inv;
  const double qv[3] = {tv[1] * e1[2] - tv[2] * e1[1], tv[2] * e1[0] - tv[0] * e1[2],
                        tv[0] * e1[1] - tv[1] * e1[0]};
  const double bv = (d[0] * qv[0] + d[1] * qv[1] + d[2] * qv[2]) * inv;
  const double bw = 1.0 - bu - bv;
  if (bu < -kRayfOcclEps || bv < -kRayfOcclEps || bw < -kRayfOcclEps) {
    return false;
  }
  const double tt = (e2[0] * qv[0] + e2[1] * qv[1] + e2[2] * qv[2]) * inv;
  return tt > tmin && tt <= tmax;
}

// ---- §5 diagnosis-only: MeshConsolidate.cpp:233-291 CollisionAuthority, reproduced verbatim ----
struct CollisionAuthority {
  std::unordered_map<u64, std::vector<u32>> cells;
  const std::vector<tfrag3::CollisionMesh::Vertex>* verts = nullptr;
  double cell = 1.0 * kUnitsPerM;
  double accept2 = (1.5 * kUnitsPerM) * (1.5 * kUnitsPerM);

  static u64 key(s64 x, s64 y, s64 z) {
    // any injective-enough mixing; only used as a hash bucket, the distance test is exact.
    u64 h = 1469598103934665603ull;
    for (s64 v : {x, y, z}) {
      h ^= (u64)v;
      h *= 1099511628211ull;
    }
    return h;
  }
  void build(const tfrag3::CollisionMesh& mesh) {
    verts = &mesh.vertices;
    cells.reserve(mesh.vertices.size() / 4 + 1);
    for (u32 i = 0; i < mesh.vertices.size(); i++) {
      const auto& v = mesh.vertices[i];
      cells[key((s64)std::floor(v.x / cell), (s64)std::floor(v.y / cell),
                (s64)std::floor(v.z / cell))]
          .push_back(i);
    }
  }
  // false = no collision vertex within 1.5 m (no authority here)
  bool nearest_normal(const V3& p, V3* out) const {
    if (!verts || verts->empty()) {
      return false;
    }
    const s64 cx = (s64)std::floor(p.x / cell);
    const s64 cy = (s64)std::floor(p.y / cell);
    const s64 cz = (s64)std::floor(p.z / cell);
    double best = accept2;
    int best_i = -1;
    for (int dz = -1; dz <= 1; dz++) {
      for (int dy = -1; dy <= 1; dy++) {
        for (int dx = -1; dx <= 1; dx++) {
          auto it = cells.find(key(cx + dx, cy + dy, cz + dz));
          if (it == cells.end()) {
            continue;
          }
          for (u32 ci : it->second) {
            const auto& cv = (*verts)[ci];
            const V3 dd{cv.x - p.x, cv.y - p.y, cv.z - p.z};
            const double d2 = dot(dd, dd);
            if (d2 < best) {
              best = d2;
              best_i = (int)ci;
            }
          }
        }
      }
    }
    if (best_i < 0) {
      return false;
    }
    const auto& cv = (*verts)[best_i];
    V3 n{(double)cv.nx, (double)cv.ny, (double)cv.nz};
    const double l = len(n);
    if (!(l > 1e-6)) {
      return false;
    }
    *out = n * (1.0 / l);
    return true;
  }
};

// ---- per-shell ground truth ------------------------------------------------------------------
struct Shell {
  u32 root = 0;
  std::vector<u32> faces;          // ascending face index (determinism)
  int gsign = 0;                   // +1 / -1 ; 0 = UNDECIDED (the SHELL-level fallback verdict)
  const char* tier = "UNDECIDED";  // which SHELL tier produced gsign (VOL / ESC / UNDECIDED)
  int vol_sign = 0;                // the SIGNED-VOLUME verdict alone, 0 = the volume test is silent
  double v6_over_l3 = 0.0;
  u64 winding_conflicts = 0;
  bool coll_speaks = false;
  int coll_sign = 0;
  int baked_sign = 0;              // sign of the area-weighted agreement of the BAKED normals
  bool has_displaceable = false;
  double esc_ratio = 0.0;          // tier ESC diagnostic
  // ---- per-face RAYF vs the shell VOL verdict (two INDEPENDENT geometric criteria) ----
  u64 rayf_voted = 0;              // mesh faces of this shell with a non-zero RAYF vote
  u64 rayf_agree = 0;              // ... of those, faces where vote == vol_sign * rel[f]
  u64 rayf_disagree = 0;           // ... and faces where it is the opposite
};

// One row of section A: a (shell, texture, system) mesh.
struct MeshRow {
  u32 shell = 0;
  s32 tex = -1;
  int system = 0;
  std::string mat;
  std::vector<u32> faces;
  // measurement at the canonical distance
  u64 faces_sampled = 0;
  u64 gverts = 0;
  u64 sign_den = 0;   // amp > 0 AND h != 0.5
  u64 sign_ok = 0;
  u64 sign_ok_lit = 0;  // the spec's LITERAL (h-0.5)*nd > 0 — see the report's derivation
  u64 disp_nz = 0;
  u64 live = 0;             // generated verts with amp > 0            -> B_live%
  u64 patches_live = 0;     // patches with >= 1 vertex at amp > 0     -> B_patch%
  u64 z_seam = 0, z_falloff = 0, z_h_mid = 0, z_amp = 0, z_not_tess = 0;
  u64 z_patch_dead = 0;     // verts of a patch with NO live vertex at all
  // faces / generated vertices decided by each OUTWARD tier
  u64 f_rayf = 0, f_vol = 0, f_esc = 0, f_und = 0;
  u64 v_rayf = 0, v_vol = 0, v_esc = 0, v_und = 0;
  // ---- seam-pin reason attribution, over the mesh's DISTINCT SOURCE vertices with seam_w == 0 ----
  u64 pin_src = 0;          // pinned source vertices (the population of the four counts below)
  u64 pin_material = 0, pin_system = 0, pin_open = 0, pin_crease = 0;
  u64 pin_unexplained = 0;          // none of the four reasons fires  <== a BUG if it is not 0
  u64 pin_unexplained_subdiv = 0;   // ... of those, verts CREATED by the pre-subdivision pass, whose
                                    // pin is INHERITED from two pinned parents
  double disp_sum_cm = 0.0, disp_max_cm = 0.0;
  double inner_sum = 0.0;
  double spacing_sum_m = 0.0;
  bool capped = false;
  double upm = kUvPerMFallback;
  bool upm_measured = false;
  // geometry
  V3 centroid;  // metres
  V3 aabb_lo, aabb_hi;
  std::string named;

  double a_pct() const { return sign_den ? 100.0 * (double)sign_ok / (double)sign_den : -1.0; }
  double a_lit_pct() const {
    return sign_den ? 100.0 * (double)sign_ok_lit / (double)sign_den : -1.0;
  }
  // B_live% — the RAW, UNSHAPED liveness number: the tier applies a non-zero amplitude to this
  // share of the generated vertices. A vertex whose sampled h is exactly 0.5 with amp > 0 IS live
  // (0.5 is the zero CROSSING of the height field, not a flat surface); it is still counted in
  // z_h_mid so nothing is hidden.
  double b_live_pct() const { return gverts ? 100.0 * (double)live / (double)gverts : 0.0; }
  // B_disp% — the share that actually MOVES. Strictly below B_live% by the h == 0.5 population.
  double b_pct() const { return gverts ? 100.0 * (double)disp_nz / (double)gverts : 0.0; }
  // B_patch% — the owner's "des chunks entiers sont juste plats": the share of PATCHES with at least
  // one live vertex. A patch with none is a FLAT patch.
  double b_patch_pct() const {
    return faces_sampled ? 100.0 * (double)patches_live / (double)faces_sampled : 0.0;
  }
  // The ONLY two structural exemptions: (a) seam == 0, the crack-guard pin (a deliberate design
  // decision: displacement is exactly zero along a boundary whose two sides cannot displace alike),
  // and (b) z_not_tess, a TIE mesh no tessellation program ever runs on. NOTHING else is exempt.
  u64 exempt() const { return system == kSysTie ? z_not_tess : z_seam; }
  double b_req_pct() const {
    const u64 e = exempt();
    return gverts > e ? 100.0 * (double)live / (double)(gverts - e) : -1.0;
  }
  double mean_inner() const { return faces_sampled ? inner_sum / (double)faces_sampled : 0.0; }
  double spacing_actual_m() const {
    return faces_sampled ? spacing_sum_m / (double)faces_sampled : 0.0;
  }
  double verts_per_square() const {
    const double square_m = (1.0 / (double)kCheckerSquaresPerTile) / std::max(upm, 1e-3);
    const double sp = spacing_actual_m();
    return sp > 0 ? square_m / sp : 0.0;
  }
  double disp_mean_cm() const { return gverts ? disp_sum_cm / (double)gverts : 0.0; }
};

struct NamedBox {
  std::string name;
  double lo[3] = {0, 0, 0};
  double hi[3] = {0, 0, 0};
};

}  // namespace

int main(int argc, char** argv) {
  // ---------------------------------------------------------------------------------------------
  // §0 CLI
  // ---------------------------------------------------------------------------------------------
  std::string fr3_path_s, tex_root_s, out_path, csv_path;
  double dist_m = 3.0;
  bool sweep = false;
  double tess_max = 64.0;
  double tess_seg = 0.025;
  double relief = 1.5;
  int geom = 0, geom_tie = 0;
  double subdiv_m = 1.6;
  int subdiv_rounds = 3;
  bool force_live = true;
  bool geom_orient = false;
  int rayf_k = kRayfKDefault;
  u64 max_verts_per_mesh = 200000;
  std::vector<NamedBox> named;

  for (int i = 1; i < argc; i++) {
    const std::string a = argv[i];
    auto need_val = [&](const char* flag) -> std::string {
      if (i + 1 >= argc) {
        fmt::print("error: {} needs a value\n", flag);
        std::exit(2);
      }
      return argv[++i];
    };
    if (a == "--fr3") {
      fr3_path_s = need_val("--fr3");
    } else if (a == "--tex-root") {
      tex_root_s = need_val("--tex-root");
    } else if (a == "--dist-m") {
      dist_m = std::stod(need_val("--dist-m"));
    } else if (a == "--sweep") {
      sweep = true;
    } else if (a == "--tess-max") {
      tess_max = std::stod(need_val("--tess-max"));
    } else if (a == "--tess-seg") {
      tess_seg = std::stod(need_val("--tess-seg"));
    } else if (a == "--relief") {
      relief = std::stod(need_val("--relief"));
    } else if (a == "--geom") {
      geom = std::stoi(need_val("--geom"));
    } else if (a == "--geom-tie") {
      geom_tie = std::stoi(need_val("--geom-tie"));
    } else if (a == "--subdiv") {
      subdiv_m = std::stod(need_val("--subdiv"));
    } else if (a == "--subdiv-rounds") {
      subdiv_rounds = std::stoi(need_val("--subdiv-rounds"));
    } else if (a == "--force-live") {
      force_live = true;
    } else if (a == "--use-sidecar") {
      force_live = false;
    } else if (a == "--geom-orient") {
      geom_orient = true;
    } else if (a == "--rayf-k") {
      rayf_k = std::stoi(need_val("--rayf-k"));
    } else if (a == "--max-verts-per-mesh") {
      max_verts_per_mesh = (u64)std::stoll(need_val("--max-verts-per-mesh"));
    } else if (a == "--named-case") {
      if (i + 7 >= argc) {
        fmt::print("error: --named-case needs NAME x0 x1 y0 y1 z0 z1\n");
        return 2;
      }
      NamedBox nb;
      nb.name = argv[++i];
      double v[6];
      for (int k = 0; k < 6; k++) {
        v[k] = std::stod(argv[++i]);
      }
      for (int k = 0; k < 3; k++) {
        nb.lo[k] = std::min(v[2 * k], v[2 * k + 1]);
        nb.hi[k] = std::max(v[2 * k], v[2 * k + 1]);
      }
      named.push_back(nb);
    } else if (a == "--out") {
      out_path = need_val("--out");
    } else if (a == "--csv") {
      csv_path = need_val("--csv");
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
  if (tess_seg <= 0.0) {
    fmt::print("error: --tess-seg must be > 0 (got {})\n", tess_seg);
    return 2;
  }
  if (relief < 0.0) {
    fmt::print("error: --relief must be >= 0 (got {})\n", relief);
    return 2;
  }
  if (dist_m <= 0.0) {
    fmt::print("error: --dist-m must be > 0 (got {})\n", dist_m);
    return 2;
  }
  if (geom < 0 || geom >= tfrag3::TFRAG_GEOS) {
    fmt::print("error: --geom must be in [0,{}) (got {})\n", tfrag3::TFRAG_GEOS, geom);
    return 2;
  }
  if (max_verts_per_mesh < 3) {
    fmt::print("error: --max-verts-per-mesh must be >= 3\n");
    return 2;
  }
  if (rayf_k < 1 || rayf_k > 256) {
    fmt::print("error: --rayf-k must be in [1,256] (got {})\n", rayf_k);
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
  if (tex_root_s.empty()) {
    if (!have_project) {
      fmt::print("error: could not resolve the jak-project directory; pass --tex-root.\n");
      return 1;
    }
    tex_root_s =
        (file_util::get_jak_project_dir() / "custom_assets" / "jak1" / "recharged_textures").string();
  }
  if (out_path.empty()) {
    if (!have_project) {
      fmt::print("error: could not resolve the jak-project directory; pass --out.\n");
      return 1;
    }
    const fs::path rep_dir = file_util::get_jak_project_dir() / ".autoport" / "reports" /
                             "Grecharged-pbr-realtime-fusion";
    file_util::create_dir_if_needed(rep_dir);
    out_path = (rep_dir / "tess_sign.txt").string();
  }
  file_util::create_dir_if_needed_for_file(out_path);
  if (csv_path.empty()) {
    csv_path = (fs::path(out_path).parent_path() / "tess_sign.csv").string();
  }
  file_util::create_dir_if_needed_for_file(csv_path);

  const fs::path fr3_path(fr3_path_s);
  if (!fs::exists(fr3_path)) {
    fmt::print("error: fr3 not found: {}\n", fr3_path.string());
    return 1;
  }

  // ---------------------------------------------------------------------------------------------
  // §1 LOAD + PREP (mirrors Loader.cpp:415-520: global weld -> consolidation -> pre-subdivision)
  // ---------------------------------------------------------------------------------------------
  std::string fr3_md5 = "(unhashed)";
  u64 fr3_bytes = 0;
  {
    auto raw = file_util::read_binary_file(fr3_path);
    fr3_bytes = raw.size();
    fr3_md5 = md5::hex(raw.data(), raw.size());
  }
  tfrag3::Level lev;
  try {
    load_level_fr3(fr3_path, lev);
  } catch (const std::exception& e) {
    fmt::print("error: failed to load {}: {}\n", fr3_path.string(), e.what());
    return 1;
  }
  fmt::print("[tess_sign] loaded {} ({} bytes, md5 {})\n", fr3_path.string(), fr3_bytes, fr3_md5);

  tfrag3::reconstruct_level_global_weld(lev);
  auto cfg = tfrag3::mesh_consolidate_config_from_env();
  // --geom-orient: the DEEP, OFFLINE-ONLY per-face geometric orientation authority a peer is adding
  // to MeshConsolidate as kMeshBitGeomOrient. MeshConsolidate.h currently documents the bit
  // (MeshConsolidate.h:138, "round-31 PER-FACE GEOMETRIC OUTWARD VOTE (kMeshBitGeomOrient)") but does
  // not yet DEFINE the constant, so the literal 512 is used here; it is the same value.
  constexpr u32 kMeshBitGeomOrientLocal = 512;
  if (geom_orient) {
    cfg.bits |= kMeshBitGeomOrientLocal;
  }
  std::string prep_note;
  std::string mesh_audit_text;
  if (force_live) {
    cfg.bits |= tfrag3::kMeshBitForceLive;
    tfrag3::MeshAuditReport rep;
    tfrag3::mesh_consolidate(lev, cfg, &rep);
    prep_note = "global weld + LIVE mesh_consolidate (kMeshBitForceLive; --force-live is the default)";
    mesh_audit_text = tfrag3::format_mesh_audit(rep, cfg);
  } else {
    const fs::path bake =
        fr3_path.parent_path() / tfrag3::mesh_consolidate_bake_name(lev.level_name);
    if (tfrag3::mesh_consolidate_apply_bake(lev, bake.string(), true)) {
      prep_note = fmt::format("global weld + consolidation from sidecar {}", bake.string());
      mesh_audit_text = "(sidecar path: no live MeshAuditReport is produced)\n";
    } else {
      tfrag3::MeshAuditReport rep;
      tfrag3::mesh_consolidate(lev, cfg, &rep);
      prep_note = fmt::format(
          "global weld + LIVE mesh_consolidate (no usable sidecar at {})", bake.string());
      mesh_audit_text = tfrag3::format_mesh_audit(rep, cfg);
    }
  }
  fmt::print("[tess_sign] prep: {}\n", prep_note);

  // ---------------------------------------------------------------------------------------------
  // §2 DISPLACEABLE MATERIALS — DATA-DRIVEN. Recursively scan --tex-root for <name>_height.png.
  // NOTHING is hardcoded: dropping 50-200 new map sets in makes them displaceable automatically.
  // ---------------------------------------------------------------------------------------------
  std::set<std::string> displaceable;
  if (!fs::exists(tex_root_s)) {
    fmt::print("error: --tex-root does not exist: {}\n", tex_root_s);
    return 1;
  }
  for (auto it = fs::recursive_directory_iterator(fs::path(tex_root_s));
       it != fs::recursive_directory_iterator(); ++it) {
    if (!it->is_regular_file()) {
      continue;
    }
    const std::string fn = it->path().filename().string();
    const std::string suffix = "_height.png";
    if (fn.size() > suffix.size() &&
        fn.compare(fn.size() - suffix.size(), suffix.size(), suffix) == 0) {
      displaceable.insert(fn.substr(0, fn.size() - suffix.size()));
    }
  }
  fmt::print("[tess_sign] discovered {} displaceable material(s) under {}\n", displaceable.size(),
             tex_root_s);
  auto tex_is_displaceable = [&](const tfrag3::Texture& t) {
    return displaceable.count(t.debug_name) > 0;
  };

  // ---------------------------------------------------------------------------------------------
  // §1.4 PRE-SUBDIVISION, exactly as the runtime orders it (after the consolidation).
  // ---------------------------------------------------------------------------------------------
  // The vertex count of every tree this tool will walk, BEFORE the pre-subdivision pass. The pass
  // only ever APPENDS (MeshSubdivide.cpp:236-238 reserve + push_back, the midpoint cache hands back
  // indices into the growing array), so a local index >= this count identifies a vertex CREATED by
  // the subdivision, whose seam_w is the LINEAR average of its two parents (MeshSubdivide.cpp:271)
  // rather than a mesh_consolidate verdict on its own weld group. §4's pin attribution needs that
  // distinction to avoid blaming an inherited pin on a missing reason.
  std::vector<size_t> tfrag_verts_before(lev.tfrag_trees[geom].size(), 0);
  std::vector<size_t> tie_verts_before(lev.tie_trees[geom_tie].size(), 0);
  for (size_t i = 0; i < lev.tfrag_trees[geom].size(); i++) {
    tfrag_verts_before[i] = lev.tfrag_trees[geom][i].unpacked.vertices.size();
  }
  for (size_t i = 0; i < lev.tie_trees[geom_tie].size(); i++) {
    tie_verts_before[i] = lev.tie_trees[geom_tie][i].unpacked.vertices.size();
  }

  std::string subdiv_note = "pre-subdivision: OFF (--subdiv 0)";
  if (subdiv_m > 0.0) {
    tfrag3::SubdivConfig scfg = tfrag3::mesh_subdiv_config_from_env();
    scfg.max_edge_m = (float)subdiv_m;
    scfg.max_rounds = subdiv_rounds;
    scfg.only_geom = geom;
    scfg.only_geom_tie = geom_tie;
    scfg.include_tie = false;  // TIE is never tessellated (Tie3.cpp, see the provenance block)
    tfrag3::SubdivStats sst;
    tfrag3::mesh_presubdivide_level(lev, scfg, &sst, tex_is_displaceable, nullptr);
    subdiv_note = tfrag3::format_subdiv_stats(sst, scfg);
  }
  fmt::print("[tess_sign] {}", subdiv_note);

  // ---------------------------------------------------------------------------------------------
  // §7 uv_per_m, measured PER MATERIAL and PER SYSTEM off the PREPPED index buffers — the same
  // order the runtime uses (TFragment::update_load measures after the loader preps the geometry).
  // ---------------------------------------------------------------------------------------------
  struct UvEntry {
    double tfrag = kUvPerMFallback;
    double tie = kUvPerMFallback;
    bool tfrag_measured = false, tie_measured = false;
    u32 tfrag_samples = 0, tie_samples = 0;
  };
  std::map<std::string, UvEntry> uv_by_mat;   // reported table
  std::vector<UvEntry> uv_by_tex(lev.textures.size());
  for (size_t ti = 0; ti < lev.textures.size(); ti++) {
    if (!displaceable.count(lev.textures[ti].debug_name)) {
      continue;
    }
    UvEntry e;
    u32 ns = 0;
    const float vt = measure_uv_density_tfrag(lev, (s32)ti, &ns);
    e.tfrag_samples = ns;
    if (vt > 0.f) {
      e.tfrag = vt;
      e.tfrag_measured = true;
    }
    ns = 0;
    const float ve = measure_uv_density_tie(lev, (s32)ti, &ns);
    e.tie_samples = ns;
    if (ve > 0.f) {
      e.tie = ve;
      e.tie_measured = true;
    }
    uv_by_tex[ti] = e;
    uv_by_mat[lev.textures[ti].debug_name] = e;
  }
  fmt::print("[tess_sign] uv_per_m measured for {} displaceable texture(s)\n", uv_by_mat.size());

  // ---------------------------------------------------------------------------------------------
  // §3 THE TRIANGLE UNIVERSE
  // ---------------------------------------------------------------------------------------------
  std::vector<GVert> gv;
  std::vector<Face> faces;
  u64 n_tfrag_trees = 0, n_tie_trees = 0, n_degenerate = 0, n_oob = 0;
  // CHANGE 2: the proto-local wind instances are DROPPED from the universe. These count what was
  // dropped, exactly.
  u64 n_wind_draws_dropped = 0, n_wind_faces_dropped = 0, n_wind_stream_inds_dropped = 0;

  auto push_tree_verts = [&](const std::vector<tfrag3::PreloadedVertex>& verts,
                             const std::vector<math::Vector4f>& tans, size_t n_before) -> u32 {
    const u32 base = (u32)gv.size();
    const bool have_tan = tans.size() == verts.size();
    gv.reserve(gv.size() + verts.size());
    for (size_t i = 0; i < verts.size(); i++) {
      const auto& v = verts[i];
      GVert g;
      g.x = v.x;
      g.y = v.y;
      g.z = v.z;
      g.s = v.s;
      g.t = v.t;
      g.nor = unpack_gl_normal_2_10_10_10(v.nor);
      if (have_tan) {
        g.tx = tans[i].x();
        g.ty = tans[i].y();
        g.tz = tans[i].z();
        g.tw = tans[i].w();
      }
      g.seam = (float)((double)v.seam_w / 65535.0);
      g.subdiv_new = (u8)(i >= n_before ? 1 : 0);
      gv.push_back(g);
    }
    return base;
  };

  // The strip / plain-list walk. Winding convention is bit-identical to
  // MeshConsolidate.cpp:200-228 for_each_tri and to tools/tess_audit/main.cpp:1586-1635
  // (UINT32_MAX primitive restart, even/odd winding swap inside a strip), plus the degenerate skip.
  // `drop` = walk the stream exactly as if it were being gathered, but COUNT the faces instead of
  // adding them to the universe. That is how the dropped wind-draw face count is made exact.
  auto walk_tris = [&](const std::vector<u32>& idx, u32 first, u64 count, bool strips, u32 vbase,
                       size_t vcount, s32 tex, u8 system, u16 tree, bool drop) {
    auto emit = [&](u32 a, u32 b, u32 c) {
      if (a == b || b == c || a == c) {
        if (!drop) {
          n_degenerate++;
        }
        return;
      }
      if (a >= vcount || b >= vcount || c >= vcount) {
        if (!drop) {
          n_oob++;
        }
        return;
      }
      if (drop) {
        n_wind_faces_dropped++;
        return;
      }
      Face f;
      f.v[0] = vbase + a;
      f.v[1] = vbase + b;
      f.v[2] = vbase + c;
      f.tex = tex;
      f.system = system;
      f.tree = tree;
      faces.push_back(f);
    };
    if ((u64)first + count > (u64)idx.size()) {
      if (!drop) {
        n_oob++;
      }
      return;
    }
    if (strips) {
      u32 a = UINT32_MAX, b = UINT32_MAX, k = 0;
      for (u64 j = 0; j < count; j++) {
        const u32 vi = idx[first + j];
        if (vi == UINT32_MAX) {
          a = b = UINT32_MAX;
          k = 0;
          continue;
        }
        if (a != UINT32_MAX && b != UINT32_MAX) {
          if ((k & 1) != 0) {
            emit(b, a, vi);
          } else {
            emit(a, b, vi);
          }
        }
        a = b;
        b = vi;
        k++;
      }
    } else {
      for (u64 j = 0; j + 2 < count; j += 3) {
        const u32 t0 = idx[first + j], t1 = idx[first + j + 1], t2 = idx[first + j + 2];
        if (t0 == UINT32_MAX || t1 == UINT32_MAX || t2 == UINT32_MAX) {
          continue;
        }
        emit(t0, t1, t2);
      }
    }
  };

  // ---- tfrag. THE SHIPPED GATE is TFragment.cpp:617-632: `tree.kind != INVALID`. The
  // NORMAL/DIRT/ICE allowlist tools/tess_audit/main.cpp:130 uses is STALE — the owner removed it on
  // 2026-07-26 ("bah elle devrait pouvoir tourner partout !") and TFragment.cpp:625 now reads
  //   const bool tess_kind_eligible = tree.kind != tfrag3::TFragmentTreeKind::INVALID;
  for (size_t tri = 0; tri < lev.tfrag_trees[geom].size(); tri++) {
    const auto& tree = lev.tfrag_trees[geom][tri];
    if (tree.kind == tfrag3::TFragmentTreeKind::INVALID) {
      continue;
    }
    n_tfrag_trees++;
    const u32 base = push_tree_verts(tree.unpacked.vertices, tree.unpacked.tangents,
                                     tfrag_verts_before[tri]);
    for (const auto& draw : tree.draws) {
      u64 count = 0;
      for (const auto& g : draw.vis_groups) {
        count += g.num_inds;
      }
      walk_tris(tree.unpacked.indices, draw.unpacked.idx_of_first_idx_in_full_buffer, count,
                tree.use_strips, base, tree.unpacked.vertices.size(), draw.tree_tex_id, kSysTfrag,
                (u16)tri, false);
    }
  }
  // ---- tie. NOT tessellated: Tie3.cpp:737 binds `use_envmap ? ETIE_BASE : TFRAG3`, Tie3.cpp:1158
  // binds ETIE and Tie3.cpp:1546 binds TIE_WIND — all vert+frag programs with NO tessellation
  // control/evaluation stage — and there is no glPatchParameteri and no GL_PATCHES anywhere in
  // Tie3.cpp (verified by grep over the whole file). TIE relief is per-pixel POM instead.
  for (size_t tri = 0; tri < lev.tie_trees[geom_tie].size(); tri++) {
    const auto& t = lev.tie_trees[geom_tie][tri];
    n_tie_trees++;
    const u32 base =
        push_tree_verts(t.unpacked.vertices, t.unpacked.tangents, tie_verts_before[tri]);
    for (const auto& draw : t.static_draws) {
      u64 count = 0;
      for (const auto& g : draw.vis_groups) {
        count += g.num_inds;
      }
      walk_tris(t.unpacked.indices, draw.unpacked.idx_of_first_idx_in_full_buffer, count,
                t.use_strips, base, t.unpacked.vertices.size(), draw.tree_tex_id, kSysTie,
                (u16)tri, false);
    }
    // CHANGE 2 — instanced_wind_draws are DROPPED from the face universe, not merely flagged.
    // Their vertices live in PROTOTYPE-LOCAL space: TieTree::unpack leaves the matrix_idx == -1
    // groups untransformed, so a wind vertex's x/y/z is an offset inside its prototype and NOT a
    // world coordinate. Three consequences, each of which alone disqualifies them here:
    //   (1) mesh_consolidate() never sees them — gather_level (MeshConsolidate.cpp:340-347) walks
    //       only unpacked.indices, so no weld group, no snapped position and no seam verdict of
    //       theirs exists;
    //   (2) TIE_WIND is a separate GL program (Tie3.cpp:1546) with no tessellation control or
    //       evaluation stage, so nothing would ever displace them;
    //   (3) mixed into a world-space face list their proto-local positions fabricate shells,
    //       fabricate BVH occluders and fabricate table rows out of coordinates that mean nothing.
    // InstancedStripDraw addresses its indices DIRECTLY through vertex_index_stream (Tfrag3Data.h
    // :259-274), and Tie3.cpp:1627/1647 draws it with the SAME tree.draw_mode (Tie3.cpp:216, derived
    // from use_strips), so the walk below is the one that WOULD have gathered them — it counts them
    // instead, to report the exact size of the drop.
    for (const auto& draw : t.instanced_wind_draws) {
      n_wind_draws_dropped++;
      n_wind_stream_inds_dropped += draw.vertex_index_stream.size();
      walk_tris(draw.vertex_index_stream, 0, draw.vertex_index_stream.size(), t.use_strips, base,
                t.unpacked.vertices.size(), draw.tree_tex_id, kSysTie, (u16)tri, true);
    }
  }
  fmt::print("[tess_sign] faces={} gverts={} (tfrag trees {}, tie trees {}; DROPPED wind draws {} /"
             " faces {})\n",
             faces.size(), gv.size(), n_tfrag_trees, n_tie_trees, n_wind_draws_dropped,
             n_wind_faces_dropped);
  if (faces.empty()) {
    fmt::print("error: no faces gathered — nothing to grade.\n");
    return 1;
  }

  // ---------------------------------------------------------------------------------------------
  // §4 WELD GROUPS + SHELLS
  // ---------------------------------------------------------------------------------------------
  std::vector<u32> vert_group(gv.size(), UINT32_MAX);
  u32 n_groups = 0;
  {
    std::unordered_map<PosKey, u32, PosKeyHash> pos_to_group;
    pos_to_group.reserve(gv.size() * 2);
    for (const auto& f : faces) {
      for (int e = 0; e < 3; e++) {
        const u32 vi = f.v[e];
        if (vert_group[vi] != UINT32_MAX) {
          continue;
        }
        const auto k = pos_key(gv[vi].x, gv[vi].y, gv[vi].z);
        auto it = pos_to_group.find(k);
        if (it == pos_to_group.end()) {
          pos_to_group.emplace(k, n_groups);
          vert_group[vi] = n_groups++;
        } else {
          vert_group[vi] = it->second;
        }
      }
    }
  }
  for (auto& f : faces) {
    for (int e = 0; e < 3; e++) {
      f.wg[e] = vert_group[f.v[e]];
    }
  }

  // Edge table: undirected weld-group pair -> the faces on it, with the traversal direction.
  struct EdgeRef {
    u32 face;
    s8 dir;  // +1 = the face traverses lo->hi, -1 = hi->lo
  };
  std::unordered_map<u64, std::vector<EdgeRef>> edges;
  edges.reserve(faces.size() * 2);
  auto edge_key = [](u32 a, u32 b) -> u64 {
    return a < b ? ((u64)a << 32) | (u64)b : ((u64)b << 32) | (u64)a;
  };
  for (u32 f = 0; f < faces.size(); f++) {
    for (int e = 0; e < 3; e++) {
      const u32 a = faces[f].wg[e];
      const u32 b = faces[f].wg[(e + 1) % 3];
      if (a == b) {
        continue;  // a weld-collapsed edge is not an edge
      }
      edges[edge_key(a, b)].push_back(EdgeRef{f, (s8)(a < b ? 1 : -1)});
    }
  }

  // SHELL = connected component of faces where adjacency is "shares at least TWO weld groups",
  // i.e. shares an EDGE. (Union-find; the chain within one edge's face list is enough to connect
  // them all, and it keeps the pass linear on the rare 3+-incident edges.)
  DSU dsu;
  dsu.init(faces.size());
  for (const auto& kv : edges) {
    for (size_t i = 1; i < kv.second.size(); i++) {
      dsu.unite(kv.second[0].face, kv.second[i].face);
    }
  }
  std::vector<u32> shell_of(faces.size(), 0);
  std::map<u32, u32> root_to_shell;  // ordered => shell ids are deterministic
  for (u32 f = 0; f < faces.size(); f++) {
    root_to_shell.emplace(dsu.find(f), 0);
  }
  {
    u32 next = 0;
    for (auto& kv : root_to_shell) {
      kv.second = next++;
    }
  }
  for (u32 f = 0; f < faces.size(); f++) {
    shell_of[f] = root_to_shell[dsu.find(f)];
  }
  const u32 n_shells = (u32)root_to_shell.size();
  std::vector<Shell> shells(n_shells);
  // A MESH FACE is a face drawn with a DISPLACEABLE texture: exactly the population section A grades
  // and exactly the population the per-face RAYF tier is run over.
  std::vector<u8> face_is_mesh(faces.size(), 0);
  u64 n_mesh_faces = 0;
  for (u32 f = 0; f < faces.size(); f++) {
    shells[shell_of[f]].faces.push_back(f);
    if (faces[f].tex >= 0 && (size_t)faces[f].tex < lev.textures.size() &&
        displaceable.count(lev.textures[faces[f].tex].debug_name)) {
      shells[shell_of[f]].has_displaceable = true;
      face_is_mesh[f] = 1;
      n_mesh_faces++;
    }
  }
  fmt::print("[tess_sign] shells={} weld_groups={} edges={} mesh_faces={}\n", n_shells, n_groups,
             edges.size(), n_mesh_faces);

  // ---------------------------------------------------------------------------------------------
  // §5 GROUND TRUTH. Per shell, purely geometric. lev.collision is REPORTED, never believed.
  // ---------------------------------------------------------------------------------------------
  auto pos = [&](u32 vi) { return V3{gv[vi].x, gv[vi].y, gv[vi].z}; };
  // cross(p1-p0, p2-p0): length == 2*area, direction == the stored winding's geometric normal.
  auto face_cross = [&](u32 f) {
    const V3 p0 = pos(faces[f].v[0]), p1 = pos(faces[f].v[1]), p2 = pos(faces[f].v[2]);
    return cross(p1 - p0, p2 - p0);
  };
  auto face_centroid = [&](u32 f) {
    const V3 p0 = pos(faces[f].v[0]), p1 = pos(faces[f].v[1]), p2 = pos(faces[f].v[2]);
    return (p0 + p1 + p2) * (1.0 / 3.0);
  };

  std::vector<s8> rel(faces.size(), 0);
  // (a) RELATIVE WINDING by BFS over the shell's edge adjacency. Computed for EVERY shell now, not
  // just the ones owning a mesh: §4's CREASE pin attribution has to cluster the faces incident to a
  // weld group, and those faces can belong to a shell that owns no displaceable material at all.
  // This cannot change any verdict — the tiers below still only read rel[] on displaceable shells.
  {
    std::vector<u32> queue;
    for (u32 s = 0; s < n_shells; s++) {
      queue.clear();
      const u32 seed = shells[s].faces.front();
      rel[seed] = 1;
      queue.push_back(seed);
      for (size_t qi = 0; qi < queue.size(); qi++) {
        const u32 f = queue[qi];
        for (int e = 0; e < 3; e++) {
          const u32 a = faces[f].wg[e], b = faces[f].wg[(e + 1) % 3];
          if (a == b) {
            continue;
          }
          auto it = edges.find(edge_key(a, b));
          if (it == edges.end()) {
            continue;
          }
          s8 my_dir = (s8)(a < b ? 1 : -1);
          for (const auto& er : it->second) {
            if (er.face == f || rel[er.face] != 0) {
              continue;
            }
            // consistently wound <=> they traverse the shared pair in OPPOSITE order
            const bool consistent = (er.dir != my_dir);
            rel[er.face] = (s8)(rel[f] * (consistent ? 1 : -1));
            queue.push_back(er.face);
          }
        }
      }
    }
  }
  // winding_conflicts: edges whose two (rel-corrected) traversals are NOT opposite. Counted once per
  // edge, after the BFS, so it is a property of the shell and not of the visit order.
  for (const auto& kv : edges) {
    const auto& lst = kv.second;
    bool conflict = false;
    for (size_t i = 1; i < lst.size() && !conflict; i++) {
      const u32 fa = lst[i - 1].face, fb = lst[i].face;
      if (rel[fa] == 0 || rel[fb] == 0) {
        continue;
      }
      if ((int)lst[i - 1].dir * (int)rel[fa] == (int)lst[i].dir * (int)rel[fb]) {
        conflict = true;
      }
    }
    if (conflict && !lst.empty()) {
      shells[shell_of[lst[0].face]].winding_conflicts++;
    }
  }

  // (b) TIER VOL — SIGNED VOLUME. Unchanged from the previous revision, but it is now a FALLBACK:
  // it only ever decides a face the per-face RAYF tier below abstained on. Its verdict is also kept
  // SEPARATELY in sh.vol_sign so that the two independent geometric criteria can be scored against
  // each other per shell (the rayf_vs_vol column), which is the case the owner must see.
  for (u32 s = 0; s < n_shells; s++) {
    auto& sh = shells[s];
    if (!sh.has_displaceable) {
      continue;
    }
    V3 lo{1e300, 1e300, 1e300}, hi{-1e300, -1e300, -1e300};
    for (u32 f : sh.faces) {
      for (int e = 0; e < 3; e++) {
        const V3 p = pos(faces[f].v[e]);
        lo = V3{std::min(lo.x, p.x), std::min(lo.y, p.y), std::min(lo.z, p.z)};
        hi = V3{std::max(hi.x, p.x), std::max(hi.y, p.y), std::max(hi.z, p.z)};
      }
    }
    const V3 c = (lo + hi) * 0.5;
    // L = the MAX BBOX EXTENT (this tool's own definition; MeshConsolidate.cpp:1505 uses the bbox
    // DIAGONAL instead, which is a strictly larger L and therefore a strictly stricter threshold).
    const double L = std::max(std::max(hi.x - lo.x, hi.y - lo.y), hi.z - lo.z);
    double v6 = 0;
    for (u32 f : sh.faces) {
      const u32 i0 = faces[f].v[0];
      const u32 i1 = rel[f] < 0 ? faces[f].v[2] : faces[f].v[1];
      const u32 i2 = rel[f] < 0 ? faces[f].v[1] : faces[f].v[2];
      // Translate by the bbox CENTRE: world coordinates are 4096/m, so a raw triple product runs to
      // ~1e15 and the enclosed volume is lost to cancellation.
      const V3 a = pos(i0) - c, b = pos(i1) - c, d = pos(i2) - c;
      v6 += dot(a, cross(b, d));
    }
    sh.v6_over_l3 = (L > 0.0) ? (v6 / (L * L * L)) : 0.0;
    if (L > 0.0 && std::abs(v6) > kVolEps * L * L * L) {
      sh.gsign = v6 > 0 ? 1 : -1;
      sh.vol_sign = sh.gsign;
      sh.tier = "VOL";
    }
  }
  // Sampled faces for TIER B / TIER C: up to 64 of the shell's LARGEST faces, chosen
  // deterministically (descending |cross|, ties broken on the LOWER face index).
  auto sample_faces = [&](const Shell& sh) {
    std::vector<std::pair<double, u32>> byarea;
    byarea.reserve(sh.faces.size());
    for (u32 f : sh.faces) {
      const double a = len(face_cross(f));
      if (a > 1e-6) {
        byarea.emplace_back(a, f);
      }
    }
    std::sort(byarea.begin(), byarea.end(), [](const auto& x, const auto& y) {
      if (x.first != y.first) {
        return x.first > y.first;
      }
      return x.second < y.second;
    });
    if (byarea.size() > (size_t)kMaxSampleFaces) {
      byarea.resize(kMaxSampleFaces);
    }
    return byarea;
  };

  // ONE accelerator over the WHOLE level face list, built once, deterministically (nth_element on a
  // TOTAL order, so no address- or input-order dependence), and used by BOTH ray tiers.
  Bvh bvh;
  {
    const auto t0 = std::chrono::steady_clock::now();
    bvh.build(faces, gv);
    fmt::print("[tess_sign] BVH built over {} faces ({} nodes) in {:.1f} s\n", faces.size(),
               bvh.nodes.size(),
               std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count());
  }

  // ===============================================================================================
  // (c) TIER RAYF — THE PRIMARY GROUND TRUTH. PER FACE, NO PROPAGATION, NO GLOBAL ORIENTATION.
  //
  // "Lancer de rayon sortant": the visible side of a surface is the side that has OPEN SPACE on it.
  // For each face, take its own stored winding's geometric normal gn, put one probe 0.02 m along +gn
  // and one 0.02 m along -gn, and fire K rays from each into the corresponding hemisphere. A ray
  // ESCAPES when it finds nothing within 200 m. The side that escapes more is the outward side.
  //
  // Why this replaces the per-shell volume as the PRIMARY authority: (1) for an OPEN shell the cone
  // volume about the bbox centre is ORIGIN-DEPENDENT, so it is not even well defined; (2) the shell
  // verdict has to be carried to each face through the relative-winding BFS, and ONE bad link in that
  // BFS (a fabricated adjacency across an edge incident to 3+ faces, a mirrored copy, a decimated LOD
  // triangle chained onto the full-res mesh) flips a whole sub-tree of faces and poisons the shell.
  // RAYF has neither failure mode: nothing is propagated, and a face's verdict depends on nothing but
  // that face's own geometry and the level around it.
  // ===============================================================================================
  std::vector<s8> rayf_vote(faces.size(), 0);
  std::vector<u8> rayf_plus(faces.size(), 0), rayf_minus(faces.size(), 0);
  double rayf_seconds = 0.0;
  {
    // the mesh faces, ascending, so the work partition is a pure function of the face list
    std::vector<u32> rayf_faces;
    rayf_faces.reserve(n_mesh_faces);
    for (u32 f = 0; f < faces.size(); f++) {
      if (face_is_mesh[f]) {
        rayf_faces.push_back(f);
      }
    }
    const double probe = kRayfProbeM * kUnitsPerM;   // 0.02 m = 81.92 game units
    const double tmax = kRayfMaxM * kUnitsPerM;      // 200 m
    const double tmin = kRayfTMinM * kUnitsPerM;     // 0.001 m
    const auto t0 = std::chrono::steady_clock::now();
    std::atomic<u64> next_chunk{0};
    const u64 chunk = 256;
    const u64 n_chunks = (rayf_faces.size() + chunk - 1) / chunk;
    // ONE FACE = ONE INDEPENDENT PROBLEM, and every input of that problem is either a compile-time
    // constant or a pure function of the face's own normal, so the result written into
    // rayf_vote[f] is identical whatever thread computes it and whatever order the chunks are
    // claimed in. The parallelism cannot move a single bit of the verdict.
    auto worker = [&]() {
      for (;;) {
        const u64 c = next_chunk.fetch_add(1);
        if (c >= n_chunks) {
          return;
        }
        const u64 lo = c * chunk;
        const u64 hi = std::min<u64>(lo + chunk, rayf_faces.size());
        for (u64 ii = lo; ii < hi; ii++) {
          const u32 f = rayf_faces[ii];
          const V3 gn = normalized(face_cross(f));
          if (len(gn) < 0.5) {
            continue;  // degenerate face: no normal, no vote
          }
          const V3 cen = face_centroid(f);
          V3 t1, t2;
          branchless_onb(gn, &t1, &t2);
          int esc[2] = {0, 0};
          for (int side = 0; side < 2; side++) {
            const double sgn = side == 0 ? 1.0 : -1.0;
            const V3 p = cen + gn * (sgn * probe);
            const double o[3] = {p.x, p.y, p.z};
            for (int i = 0; i < rayf_k; i++) {
              // the fixed spiral: stratum u of the projected-area measure, golden-angle azimuth
              const double u = ((double)i + 0.5) / (double)rayf_k;
              const double r = std::sqrt(u);
              const double zz = std::sqrt(std::max(0.0, 1.0 - u));
              const double phi = 2.0 * 3.14159265358979323846 * kGoldenConj * (double)i;
              const double cp = std::cos(phi), sp2 = std::sin(phi);
              // the MINUS set is the exact mirror of the PLUS set: same tangential part, z negated
              const V3 dirv = normalized(t1 * (r * cp) + t2 * (r * sp2) + gn * (sgn * zz));
              const double d[3] = {dirv.x, dirv.y, dirv.z};
              const bool blocked = bvh.any_hit(o, d, tmax, [&](u32 cand) {
                if (cand == f) {
                  return false;  // never the source face itself
                }
                return ray_tri_occl(o, d, pos(faces[cand].v[0]), pos(faces[cand].v[1]),
                                    pos(faces[cand].v[2]), tmin, tmax);
              });
              if (!blocked) {
                esc[side]++;
              }
            }
          }
          rayf_plus[f] = (u8)esc[0];
          rayf_minus[f] = (u8)esc[1];
          const int diff = esc[0] - esc[1];
          if (std::abs(diff) >= kRayfMinMargin) {
            rayf_vote[f] = (s8)(diff > 0 ? 1 : -1);
          }
        }
      }
    };
    const unsigned nthreads = std::max(1u, std::thread::hardware_concurrency());
    std::vector<std::thread> pool;
    for (unsigned t = 1; t < nthreads; t++) {
      pool.emplace_back(worker);
    }
    worker();
    for (auto& th : pool) {
      th.join();
    }
    rayf_seconds =
        std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count();
    u64 voted = 0;
    for (u32 f : rayf_faces) {
      if (rayf_vote[f] != 0) {
        voted++;
      }
    }
    fmt::print("[tess_sign] tier RAYF done: {} of {} mesh faces voted, K={} per hemisphere, {} "
               "threads, {:.1f} s\n",
               voted, rayf_faces.size(), rayf_k, nthreads, rayf_seconds);
  }

  // (d) TIER ESC — ESCAPE-DISTANCE ASYMMETRY against the WHOLE level BVH.
  for (u32 s = 0; s < n_shells; s++) {
    auto& sh = shells[s];
    if (!sh.has_displaceable || sh.gsign != 0) {
      continue;
    }
    // ESC is the LAST resort: it only has to speak for a shell that still owns a mesh face RAYF
    // abstained on. If RAYF called every one of them there is nothing left for it to decide.
    bool needs_fallback = false;
    for (u32 f : sh.faces) {
      if (face_is_mesh[f] && rayf_vote[f] == 0) {
        needs_fallback = true;
        break;
      }
    }
    if (!needs_fallback) {
      continue;
    }
    const auto sampled = sample_faces(sh);
    if (sampled.empty()) {
      continue;
    }
    const double cap = kEscMaxM * kUnitsPerM;
    double sum_plus = 0, sum_minus = 0;
    u32 n = 0;
    for (const auto& sf : sampled) {
      const u32 f = sf.second;
      const V3 gn = normalized(face_cross(f));
      const V3 dir_out = gn * (double)rel[f];
      const V3 cen = face_centroid(f);
      for (int side = 0; side < 2; side++) {
        const V3 dd = side == 0 ? dir_out : dir_out * -1.0;
        const V3 p = cen + dd * (kProbeEpsM * kUnitsPerM);
        const double o[3] = {p.x, p.y, p.z};
        const double d[3] = {dd.x, dd.y, dd.z};
        double best = cap;
        bvh.traverse(o, d, cap, [&](u32 cand) {
          if (cand == f) {
            return;
          }
          double t = 0;
          if (ray_tri(o, d, pos(faces[cand].v[0]), pos(faces[cand].v[1]), pos(faces[cand].v[2]),
                      &t) == 1) {
            if (t < best) {
              best = t;
            }
          }
        });
        if (side == 0) {
          sum_plus += best;
        } else {
          sum_minus += best;
        }
      }
      n++;
    }
    if (!n) {
      continue;
    }
    const double mp = sum_plus / (double)n, mm = sum_minus / (double)n;
    const double hi2 = std::max(mp, mm), lo2 = std::min(mp, mm);
    sh.esc_ratio = lo2 > 0 ? hi2 / lo2 : (hi2 > 0 ? 1e9 : 1.0);
    if (sh.esc_ratio >= kEscMargin) {
      sh.gsign = (mp > mm) ? 1 : -1;
      sh.tier = "ESC";
    }
  }
  fmt::print("[tess_sign] tier ESC done\n");

  // ===============================================================================================
  // (e) THE PER-FACE OUTWARD DIRECTION AND ITS TIER. This is the single place the tier ORDER lives:
  //        RAYF (per face, no propagation)  ->  VOL (shell signed volume)  ->  ESC  ->  UNDECIDED
  // osign[f] is the multiplier on the face's own gn: outward(f) = osign[f] * gn(f).
  // ===============================================================================================
  constexpr u8 kTierRayf = 0, kTierVol = 1, kTierEsc = 2, kTierUnd = 3;
  const char* kTierName[4] = {"RAYF", "VOL", "ESC", "UNDECIDED"};
  std::vector<s8> osign(faces.size(), 0);
  std::vector<u8> ftier(faces.size(), kTierUnd);
  for (u32 f = 0; f < faces.size(); f++) {
    if (rayf_vote[f] != 0) {
      osign[f] = rayf_vote[f];
      ftier[f] = kTierRayf;
      continue;
    }
    const Shell& sh = shells[shell_of[f]];
    if (sh.gsign != 0 && rel[f] != 0) {
      osign[f] = (s8)(sh.gsign * (int)rel[f]);
      ftier[f] = std::strcmp(sh.tier, "VOL") == 0 ? kTierVol : kTierEsc;
    }
  }

  // rayf_vs_vol — the two INDEPENDENT geometric criteria, scored against each other PER SHELL over
  // the shell's own mesh faces. They agree on face f iff  rayf_vote[f] == vol_sign * rel[f], i.e.
  // iff they hand that face the same outward direction. When the signed-volume test never spoke for
  // the shell (an open shell, or |V6| under the threshold) the comparison is reported as vol-silent
  // rather than being silently scored as agreement.
  for (u32 f = 0; f < faces.size(); f++) {
    if (!face_is_mesh[f] || rayf_vote[f] == 0) {
      continue;
    }
    Shell& sh = shells[shell_of[f]];
    sh.rayf_voted++;
    if (sh.vol_sign == 0 || rel[f] == 0) {
      continue;
    }
    if ((int)rayf_vote[f] == sh.vol_sign * (int)rel[f]) {
      sh.rayf_agree++;
    } else {
      sh.rayf_disagree++;
    }
  }

  // (e) DIAGNOSIS ONLY — what the pipeline's own authorities say. Never used for a decision here.
  CollisionAuthority coll;
  const bool have_coll = !lev.collision.vertices.empty();
  if (have_coll) {
    coll.build(lev.collision);
  }
  for (u32 s = 0; s < n_shells; s++) {
    auto& sh = shells[s];
    if (!sh.has_displaceable) {
      continue;
    }
    // (i) the COLLISION verdict, MeshConsolidate.cpp:1646-1665 + the round-29 competence filter.
    double agree_coll = 0, coll_area = 0, agree_prev = 0;
    bool any_coll = false;
    for (u32 f : sh.faces) {
      const V3 nraw = face_cross(f) * (double)rel[f];
      const double area = len(nraw);
      if (!(area > 1e-6)) {
        continue;
      }
      const V3 n = nraw * (1.0 / area);
      if (have_coll) {
        V3 cn;
        if (coll.nearest_normal(face_centroid(f), &cn)) {
          const double d = dot(n, cn);
          if (std::abs(d) > kCollParallelMin) {  // kCollParallelMin, MeshConsolidate.cpp:1415
            any_coll = true;
            agree_coll += area * d;
            coll_area += area;
          }
        }
      }
      // (ii) the BAKED per-vertex normals of the shell, same accumulation as agree_prev.
      for (int e = 0; e < 3; e++) {
        const V3& pn = gv[faces[f].v[e]].nor;
        if (len(pn) > 1e-6) {
          agree_prev += area * dot(n, pn);
        }
      }
    }
    const double coll_conf = coll_area > 0.0 ? (agree_coll / coll_area) : 0.0;
    sh.coll_speaks = any_coll && std::abs(coll_conf) > kCollConfMin;  // :1420 kCollConfMin
    sh.coll_sign = sh.coll_speaks ? (agree_coll > 0 ? 1 : -1) : 0;
    sh.baked_sign = std::abs(agree_prev) > 1e-3 ? (agree_prev > 0 ? 1 : -1) : 0;
  }
  fmt::print("[tess_sign] authority diagnosis done\n");

  // ---------------------------------------------------------------------------------------------
  // §4 MESH = (shell id, texture id, system) restricted to DISPLACEABLE textures. Every non-empty
  // triple is one row: no size filter, no row cap.
  // ---------------------------------------------------------------------------------------------
  std::vector<MeshRow> meshes;
  {
    std::map<std::array<u64, 3>, u32> key_to_row;  // ordered => deterministic row order
    for (u32 f = 0; f < faces.size(); f++) {
      const s32 tex = faces[f].tex;
      if (tex < 0 || (size_t)tex >= lev.textures.size() ||
          !displaceable.count(lev.textures[tex].debug_name)) {
        continue;
      }
      const std::array<u64, 3> k{(u64)shell_of[f], (u64)tex, (u64)faces[f].system};
      auto it = key_to_row.find(k);
      if (it == key_to_row.end()) {
        MeshRow m;
        m.shell = shell_of[f];
        m.tex = tex;
        m.system = faces[f].system;
        m.mat = lev.textures[tex].debug_name;
        const auto& uv = uv_by_tex[(size_t)tex];
        m.upm = (m.system == kSysTie) ? uv.tie : uv.tfrag;
        m.upm_measured = (m.system == kSysTie) ? uv.tie_measured : uv.tfrag_measured;
        key_to_row.emplace(k, (u32)meshes.size());
        meshes.push_back(m);
        it = key_to_row.find(k);
      }
      meshes[it->second].faces.push_back(f);
    }
  }
  // centroid + AABB in metres, and the --named-case label.
  for (auto& m : meshes) {
    V3 lo{1e300, 1e300, 1e300}, hi{-1e300, -1e300, -1e300}, sum{0, 0, 0};
    u64 n = 0;
    for (u32 f : m.faces) {
      for (int e = 0; e < 3; e++) {
        const V3 p = pos(faces[f].v[e]);
        lo = V3{std::min(lo.x, p.x), std::min(lo.y, p.y), std::min(lo.z, p.z)};
        hi = V3{std::max(hi.x, p.x), std::max(hi.y, p.y), std::max(hi.z, p.z)};
        sum = sum + p;
        n++;
      }
    }
    const double inv = n ? 1.0 / (double)n : 0.0;
    m.centroid = V3{sum.x * inv / kUnitsPerM, sum.y * inv / kUnitsPerM, sum.z * inv / kUnitsPerM};
    m.aabb_lo = V3{lo.x / kUnitsPerM, lo.y / kUnitsPerM, lo.z / kUnitsPerM};
    m.aabb_hi = V3{hi.x / kUnitsPerM, hi.y / kUnitsPerM, hi.z / kUnitsPerM};
    for (const auto& nb : named) {
      if (m.centroid.x >= nb.lo[0] && m.centroid.x <= nb.hi[0] && m.centroid.y >= nb.lo[1] &&
          m.centroid.y <= nb.hi[1] && m.centroid.z >= nb.lo[2] && m.centroid.z <= nb.hi[2]) {
        m.named = m.named.empty() ? nb.name : (m.named + "+" + nb.name);
      }
    }
  }
  fmt::print("[tess_sign] meshes={}\n", meshes.size());

  // ---------------------------------------------------------------------------------------------
  // §4b SEAM-PIN REASON ATTRIBUTION. Every vertex with seam == 0 has its pin EXPLAINED, by
  // recomputing the four pin reasons of MeshConsolidate.cpp:2216-2252 from the geometry this tool
  // already has:
  //   MATERIAL : the weld group is referenced by faces with different tree_tex_id  (:2218)
  //   SYSTEM   : the weld group spans more than one of tfrag / tie / shrub          (:2219)
  //   OPEN     : a welded GROUP edge of the group is used by exactly one face       (:2220)
  //   CREASE   : the group's incident faces fall into >= 2 clusters at the crease
  //              threshold AND the group has >= 2 referenced members                (:2221)
  // A pin matching NONE of the four is a PIN_UNEXPLAINED — a bug, and its position is printed.
  // ---------------------------------------------------------------------------------------------
  std::vector<u8> grp_material(n_groups, 0), grp_system(n_groups, 0), grp_open(n_groups, 0),
      grp_crease(n_groups, 0);
  std::vector<u32> grp_members(n_groups, 0);
  {
    const auto t0 = std::chrono::steady_clock::now();
    // members + one representative position per group (every member shares it bit-identically:
    // mesh_consolidate wrote the group mean back to all of them, MeshConsolidate.cpp:1297-1309)
    std::vector<u32> grp_rep(n_groups, UINT32_MAX);
    for (u32 vi = 0; vi < gv.size(); vi++) {
      const u32 g = vert_group[vi];
      if (g == UINT32_MAX) {
        continue;
      }
      grp_members[g]++;
      if (grp_rep[g] == UINT32_MAX) {
        grp_rep[g] = vi;
      }
    }
    // OPEN: a group edge used exactly once, both of whose endpoints are then marked
    // (MeshConsolidate.cpp:858-861).
    for (const auto& kv : edges) {
      if (kv.second.size() != 1) {
        continue;
      }
      const u32 ga = (u32)(kv.first >> 32), gb = (u32)(kv.first & 0xffffffffu);
      if (ga < n_groups) {
        grp_open[ga] = 1;
      }
      if (gb < n_groups) {
        grp_open[gb] = 1;
      }
    }
    // SHRUB presence, by exact position. Shrub is in mesh_consolidate's weld universe
    // (MeshConsolidate.cpp:345-348) but NOT in this tool's face universe — it is never tessellated
    // and never graded — so without this a tfrag<->shrub junction would look unexplained. The
    // population is the shrub vertices the draws actually reference (:682-698).
    std::unordered_map<PosKey, u8, PosKeyHash> shrub_pos;
    u64 n_shrub_refs = 0;
    for (const auto& t : lev.shrub_trees) {
      for (const auto& d : t.static_draws) {
        for (u32 k = 0; k < d.num_indices; k++) {
          const size_t ii = (size_t)d.first_index_index + k;
          if (ii >= t.indices.size()) {
            break;
          }
          const u32 li = t.indices[ii];
          if (li == UINT32_MAX || li >= t.unpacked.vertices.size()) {
            continue;
          }
          const auto& sv = t.unpacked.vertices[li];
          shrub_pos.emplace(pos_key(sv.x, sv.y, sv.z), (u8)1);
          n_shrub_refs++;
        }
      }
    }
    for (u32 g = 0; g < n_groups; g++) {
      if (grp_rep[g] == UINT32_MAX) {
        continue;
      }
      const auto& p = gv[grp_rep[g]];
      if (shrub_pos.count(pos_key(p.x, p.y, p.z))) {
        grp_system[g] = 1;  // spans tfrag/tie AND shrub
      }
    }
    fmt::print("[tess_sign] shrub weld population: {} referenced verts, {} distinct positions\n",
               n_shrub_refs, shrub_pos.size());

    // CSR group -> incident (face, corner), then MATERIAL / SYSTEM / CREASE per group.
    std::vector<u32> ioff(n_groups + 1, 0);
    for (const auto& f : faces) {
      for (int e = 0; e < 3; e++) {
        ioff[f.wg[e] + 1]++;
      }
    }
    for (u32 g = 0; g < n_groups; g++) {
      ioff[g + 1] += ioff[g];
    }
    std::vector<u32> iflat(ioff[n_groups]);
    {
      std::vector<u32> cur(ioff.begin(), ioff.end() - 1);
      for (u32 f = 0; f < faces.size(); f++) {
        for (int e = 0; e < 3; e++) {
          iflat[cur[faces[f].wg[e]]++] = f;
        }
      }
    }
    // the crease threshold is mesh_consolidate's own (MeshConsolidate.h:210 crease_deg = 60, .cpp:511
    // crease_cos = cos(crease_deg)), read from the SAME cfg the consolidation ran with.
    const double crease_cos = std::cos((double)cfg.crease_deg * 3.14159265358979323846 / 180.0);
    std::vector<std::pair<double, u32>> byarea;
    std::vector<V3> cunit;
    for (u32 g = 0; g < n_groups; g++) {
      const u32 i0 = ioff[g], i1 = ioff[g + 1];
      if (i0 == i1) {
        continue;
      }
      s32 tex0 = -2;
      u32 sysmask = 0;
      byarea.clear();
      for (u32 k = i0; k < i1; k++) {
        const u32 f = iflat[k];
        if (tex0 == -2) {
          tex0 = faces[f].tex;
        } else if (faces[f].tex != tex0) {
          grp_material[g] = 1;
        }
        sysmask |= 1u << faces[f].system;
        const V3 nr = face_cross(f) * (rel[f] != 0 ? (double)rel[f] : 1.0);
        const double a = len(nr);
        if (a > 1e-6) {
          byarea.emplace_back(a, k);
        }
      }
      if (sysmask && (sysmask & (sysmask - 1u))) {
        grp_system[g] = 1;  // more than one bit set: the group spans two systems
      }
      // cluster the incident faces by crease angle, LARGEST FACE FIRST and ties broken on the lower
      // slot, exactly as MeshConsolidate.cpp:1904-1936 does, so the cluster COUNT matches.
      std::sort(byarea.begin(), byarea.end(), [](const auto& x, const auto& y) {
        return x.first != y.first ? x.first > y.first : x.second < y.second;
      });
      cunit.clear();
      for (const auto& od : byarea) {
        const u32 f = iflat[od.second];
        const V3 un = face_cross(f) * ((rel[f] != 0 ? (double)rel[f] : 1.0) / od.first);
        bool found = false;
        for (const auto& c : cunit) {
          if (dot(un, c) >= crease_cos) {
            found = true;
            break;
          }
        }
        if (!found) {
          cunit.push_back(un);
        }
      }
      if (cunit.size() >= 2 && grp_members[g] >= 2) {
        grp_crease[g] = 1;  // :2221 crease AND refcount2
      }
    }
    fmt::print("[tess_sign] pin-reason group flags built in {:.1f} s\n",
               std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count());
  }

  // per mesh, over its DISTINCT SOURCE vertices with seam == 0 (a pin is a property of a weld group,
  // not of a generated vertex), and once more level-wide over distinct vertices.
  struct PinSample {
    V3 p_m;
    u32 mesh = 0;
    u32 group = 0;
    bool subdiv_new = false;
    u32 members = 0;
  };
  std::vector<PinSample> pin_unexplained_samples;
  u64 tot_pin_src = 0, tot_pin_material = 0, tot_pin_system = 0, tot_pin_open = 0,
      tot_pin_crease = 0, tot_pin_unexpl = 0, tot_pin_unexpl_subdiv = 0;
  {
    std::vector<u32> stamp(gv.size(), UINT32_MAX);
    std::vector<u8> seen_global(gv.size(), 0);
    for (u32 mi = 0; mi < meshes.size(); mi++) {
      auto& m = meshes[mi];
      for (u32 f : m.faces) {
        for (int e = 0; e < 3; e++) {
          const u32 vi = faces[f].v[e];
          if (stamp[vi] == mi) {
            continue;
          }
          stamp[vi] = mi;
          if (gv[vi].seam != 0.f) {
            continue;
          }
          const u32 g = vert_group[vi];
          m.pin_src++;
          const bool mat = g < n_groups && grp_material[g];
          const bool sys = g < n_groups && grp_system[g];
          const bool opn = g < n_groups && grp_open[g];
          const bool crs = g < n_groups && grp_crease[g];
          m.pin_material += mat;
          m.pin_system += sys;
          m.pin_open += opn;
          m.pin_crease += crs;
          const bool none = !(mat || sys || opn || crs);
          if (none) {
            m.pin_unexplained++;
            m.pin_unexplained_subdiv += gv[vi].subdiv_new ? 1 : 0;
          }
          if (!seen_global[vi]) {
            seen_global[vi] = 1;
            tot_pin_src++;
            tot_pin_material += mat;
            tot_pin_system += sys;
            tot_pin_open += opn;
            tot_pin_crease += crs;
            if (none) {
              tot_pin_unexpl++;
              tot_pin_unexpl_subdiv += gv[vi].subdiv_new ? 1 : 0;
              if (pin_unexplained_samples.size() < 20) {
                PinSample ps;
                ps.p_m = V3{gv[vi].x / kUnitsPerM, gv[vi].y / kUnitsPerM, gv[vi].z / kUnitsPerM};
                ps.mesh = mi;
                ps.group = g;
                ps.subdiv_new = gv[vi].subdiv_new != 0;
                ps.members = g < n_groups ? grp_members[g] : 0;
                pin_unexplained_samples.push_back(ps);
              }
            }
          }
        }
      }
    }
    fmt::print("[tess_sign] pin attribution: {} pinned source verts, {} UNEXPLAINED ({} of them "
               "created by the pre-subdivision)\n",
               tot_pin_src, tot_pin_unexpl, tot_pin_unexpl_subdiv);
  }

  // ---------------------------------------------------------------------------------------------
  // §6 THE CPU PORT OF THE TESS STAGES.
  //
  // THE INSPECTION-DISTANCE CONVENTION: instead of placing a camera anywhere, EVERY distance the two
  // shader stages consume (the .tesc level law's edge-midpoint distance and whole-patch gate, the
  // .tese's spacing/band-limit and amplitude fade) is fed the SAME value d = --dist-m. The mesh is
  // declared to be viewed from d metres. The grade is therefore a property OF THE MESH, not of a
  // vantage, and two meshes on opposite sides of the level are graded on equal terms.
  // ---------------------------------------------------------------------------------------------
  const Checker checker;
  const double height_scale = 0.05 * relief;  // background_common.cpp:1792 + :2020
  const double rel_slider = height_scale * 20.0;                    // .tese:407
  const double drive = std::pow(std::max(rel_slider, 0.0), kPbrDriveExp);  // .tese:409
  const double hs = 0.05 * drive;                                   // .tese:410

  struct Agg {
    u64 sign_den = 0, sign_ok = 0, sign_ok_lit = 0, gverts = 0, disp_nz = 0;
    u64 live = 0, patches = 0, patches_live = 0, exempt = 0;
    u64 gverts_tfrag = 0, disp_nz_tfrag = 0, live_tfrag = 0;
    u64 v_rayf = 0, v_vol = 0, v_esc = 0, v_und = 0;
  };

  // Evaluate every mesh at inspection distance d. `store` = write the per-mesh columns too.
  auto evaluate = [&](double d, bool store) -> Agg {
    Agg agg;
    const double falloff = 1.0 - smoothstepd(40.0, 60.0, d);        // .tese:398
    const double spacing_m = tess_spacing_m(d, tess_seg);           // .tese:156-163
    for (auto& m : meshes) {
      if (store) {
        m.faces_sampled = 0;
        m.gverts = 0;
        m.sign_den = 0;
        m.sign_ok = 0;
        m.sign_ok_lit = 0;
        m.disp_nz = 0;
        m.live = 0;
        m.patches_live = 0;
        m.z_seam = m.z_falloff = m.z_h_mid = m.z_amp = m.z_not_tess = 0;
        m.z_patch_dead = 0;
        m.f_rayf = m.f_vol = m.f_esc = m.f_und = 0;
        m.v_rayf = m.v_vol = m.v_esc = m.v_und = 0;
        m.disp_sum_cm = 0;
        m.disp_max_cm = 0;
        m.inner_sum = 0;
        m.spacing_sum_m = 0;
        m.capped = false;
      }
      // ---- per-material constants (.tese:234-235, :328-355, :407-415) ----
      const double upm = std::max(m.upm, 0.0) > 0.0 ? m.upm : kUvPerMFallback;
      const double tile_m = 1.0 / std::max(upm, 1e-3);              // .tese:235
      const double texels = spacing_m * upm * (double)kCheckerDim;  // .tese:330
      const double hlod =
          clampd(std::log2(std::max(texels, 1e-3)) + kTessLodBias * smoothstepd(1.0, 2.0, texels),
                 0.0, 12.0);                                        // .tese:355
      const double lambda_world_m = clampd(kPbrHeightLambda, 0.002, 1.0) * tile_m;  // .tese:411
      double amp_m = hs * kTessDepthK * lambda_world_m;                             // .tese:412
      amp_m = std::min(amp_m, kTessDepthMaxRatio * lambda_world_m);                 // .tese:413
      amp_m = std::min(amp_m, kTessDepthMaxM * drive);                              // .tese:414
      amp_m = std::max(amp_m, 0.005 * rel_slider);                                  // .tese:415
      const bool tessellated = (m.system != kSysTie);

      u64 local_verts = 0, local_den = 0, local_ok = 0, local_ok_lit = 0, local_nz = 0,
          local_live = 0, local_seam0 = 0;
      u64 local_patches = 0, local_patches_live = 0;
      u64 lv_tier[4] = {0, 0, 0, 0};
      for (u32 f : m.faces) {
        if (local_verts >= max_verts_per_mesh) {
          if (store) {
            m.capped = true;
          }
          break;
        }
        const u32 ia = faces[f].v[0], ib = faces[f].v[1], ic = faces[f].v[2];
        const V3 p0 = pos(ia), p1 = pos(ib), p2 = pos(ic);
        const double e0 = len(p1 - p2), e1 = len(p2 - p0), e2 = len(p0 - p1);  // game units
        // ---- .tesc:151-188 main(): the per-edge levels and the whole-patch far gate ----
        double l0 = 1.0, l1 = 1.0, l2 = 1.0;
        if (tessellated && d <= kTessFadeHiM) {
          // outer level i opposes vertex i (.tesc:179-183)
          l0 = edge_level(e0, d, tess_max, tess_seg);
          l1 = edge_level(e1, d, tess_max, tess_seg);
          l2 = edge_level(e2, d, tess_max, tess_seg);
        }
        const double inner = std::max(std::max(l0, l1), l2);  // .tesc:187
        const int n0 = next_odd_ge(l0), n1 = next_odd_ge(l1), n2 = next_odd_ge(l2);
        const int ni = next_odd_ge(inner);
        const double mean_edge_m = (e0 + e1 + e2) / (3.0 * kUnitsPerM);
        if (store) {
          m.faces_sampled++;
          m.inner_sum += inner;
          m.spacing_sum_m += mean_edge_m / std::max(inner, 1.0);
        }
        // outward(f) = osign[f] * gn(f), with osign decided PER FACE by the tier cascade
        // RAYF -> VOL -> ESC -> UNDECIDED. 0-length only when every tier abstained on this face.
        const V3 outward =
            (osign[f] != 0) ? normalized(face_cross(f)) * (double)osign[f] : V3{0, 0, 0};
        const bool have_outward = osign[f] != 0;
        const u8 tier_here = ftier[f];
        u64 face_verts = 0, face_live = 0;
        if (store) {
          switch (tier_here) {
            case kTierRayf:
              m.f_rayf++;
              break;
            case kTierVol:
              m.f_vol++;
              break;
            case kTierEsc:
              m.f_esc++;
              break;
            default:
              m.f_und++;
              break;
          }
        }
        local_patches++;

        // ---- ONE generated vertex (.tese:191-421). `bary` is gl_TessCoord. ----
        auto do_vertex = [&](double bx, double by, double bz) {
          local_verts++;
          face_verts++;
          lv_tier[tier_here]++;
          // .tese:192-197 barycentric interpolation + the normalized normal
          const double s = bx * gv[ia].s + by * gv[ib].s + bz * gv[ic].s;
          const double t = bx * gv[ia].t + by * gv[ib].t + bz * gv[ic].t;
          const V3 nrm = gv[ia].nor * bx + gv[ib].nor * by + gv[ic].nor * bz;
          const double nlen2 = dot(nrm, nrm);
          const V3 N = nlen2 > 1e-8 ? nrm * (1.0 / std::sqrt(nlen2)) : V3{0.0, 1.0, 0.0};
          // .tese:367-384 the seam band (SEAM_BAND 0.25)
          const double seam_lin =
              clampd(bx * gv[ia].seam + by * gv[ib].seam + bz * gv[ic].seam, 0.0, 1.0);
          const double seam = smoothstepd(0.0, kSeamBand, seam_lin);
          // .tese:264 huv = uv3.xy — the AUTHORED texcoord, multiplied by NOTHING
          const double h = hnorm(checker.sample(s, t, hlod));  // .tese:359
          const double amp = amp_m * kTessDispUnitsPerM * falloff * seam;  // .tese:416
          const double disp = (h - 0.5) * amp;                             // .tese:420
          // NOTE: the gradient-normal block (.tese:462-489) is deliberately NOT applied. It runs
          // AFTER `world += N * disp` (.tese:421) and only rewrites the EMITTED SHADING normal, so it
          // cannot change the direction the vertex already moved in — it is not part of the sign.
          if (store) {
            const double cm = std::abs(disp) / kUnitsPerM * 100.0;
            m.disp_sum_cm += cm;
            m.disp_max_cm = std::max(m.disp_max_cm, cm);
            if (seam == 0.0) {
              m.z_seam++;
            }
            if (falloff == 0.0) {
              m.z_falloff++;
            }
            if (h == 0.5) {
              m.z_h_mid++;
            }
            if (amp_m == 0.0) {
              m.z_amp++;
            }
            if (!tessellated) {
              m.z_not_tess++;
            }
          }
          // LIVE = the tier applies a non-zero amplitude here. A live vertex whose h is EXACTLY 0.5
          // does not move, but it is the zero CROSSING of the height field, not a flat surface, so it
          // is live; it is counted in z_h_mid at the same time so nothing is hidden.
          if (amp > 0.0) {
            local_live++;
            face_live++;
          }
          if (seam == 0.0) {
            local_seam0++;  // tracked unconditionally: the sweep needs it too
          }
          if (disp != 0.0) {
            local_nz++;
          }
          // ===== §9 SIGN CLASSIFICATION ==============================================
          // THE REQUIREMENT, verbatim: "White, h>0.5, must move ALONG outward; black must move
          // against it." The shader moves the vertex by  N * disp  with  disp = (h-0.5)*amp
          // (.tese:420-421), so the displacement's component along outward is
          //     along = disp * dot(N, outward)  =  (h-0.5) * amp * nd .
          // "White moves along outward"  <=>  along > 0 when h > 0.5
          // "Black moves against it"     <=>  along < 0 when h < 0.5
          // both of which are the ONE condition   (h - 0.5) * along > 0 .
          // Since along = (h-0.5)*amp*nd and amp > 0, that reduces algebraically to nd > 0 — the
          // same test for white AND black, which is the whole point: one surface either has its
          // normals pointing out or it does not.
          //
          // DEVIATION, DELIBERATE AND REPORTED: the spec wrote this test as `(h-0.5)*nd > 0`, which
          // is the sign slip of leaving one factor of (h-0.5) out. That expression demands nd > 0 on
          // white texels and nd < 0 on black ones, i.e. it demands the surface be simultaneously
          // outward- and inward-facing; on a checkerboard (half white, half black by construction)
          // it therefore CANNOT exceed ~50% no matter how correct the pipeline is, and cannot reach
          // the mandate's own "100% EVERYWHERE" target. Measured before the correction it returned
          // 50.04% level-wide and 50.15 / 49.90 / 49.52% on the three sage-hut cases — a coin flip
          // that graded the broken ground floor and the known-good upper floor identically, i.e. it
          // did not measure the defect. A_sign is the corrected criterion; A_lit is the spec's
          // literal expression, kept in its own column so nothing is hidden.
          if (amp > 0.0 && h != 0.5 && have_outward) {
            local_den++;
            const double nd = dot(N, outward);
            const double along = disp * nd;  // displacement component along outward
            if ((h - 0.5) * along > 0.0) {
              local_ok++;
            }
            if ((h - 0.5) * nd > 0.0) {
              local_ok_lit++;
            }
          }
        };

        // ---- the generated-vertex set of a `triangles, fractional_odd_spacing` patch ----
        // fractional_odd_spacing shortens the TWO END SEGMENTS of every edge/ring instead of placing
        // the samples at exact k/n. That moves a vertex by at most one segment fraction ALONG the
        // patch, and the sign field (h-0.5)*dot(N,outward) is a continuous function of (uv, N) over
        // the patch, so no such sub-segment shift can flip a sign — only the (measure-zero) exact
        // h == 0.5 crossings move, and those are excluded from the denominator by construction.
        do_vertex(1, 0, 0);
        do_vertex(0, 1, 0);
        do_vertex(0, 0, 1);
        for (int k = 1; k < n0; k++) {  // edge opposite v0 = (v1,v2)
          const double u = (double)k / (double)n0;
          do_vertex(0.0, 1.0 - u, u);
        }
        for (int k = 1; k < n1; k++) {  // edge opposite v1 = (v2,v0)
          const double u = (double)k / (double)n1;
          do_vertex(u, 0.0, 1.0 - u);
        }
        for (int k = 1; k < n2; k++) {  // edge opposite v2 = (v0,v1)
          const double u = (double)k / (double)n2;
          do_vertex(1.0 - u, u, 0.0);
        }
        for (int i = 1; i <= ni - 2; i++) {  // strictly-interior lattice of the inner level
          for (int j = 1; j <= ni - 1 - i; j++) {
            const int k = ni - i - j;
            if (k < 1) {
              continue;
            }
            do_vertex((double)i / ni, (double)j / ni, (double)k / ni);
          }
        }
        // A PATCH with no live vertex at all is a FLAT patch — the owner's "des chunks entiers sont
        // juste plats". Its whole vertex set lands in z_patch_dead.
        if (face_live) {
          local_patches_live++;
        } else if (store) {
          m.z_patch_dead += face_verts;
        }
      }
      if (store) {
        m.gverts = local_verts;
        m.sign_den = local_den;
        m.sign_ok = local_ok;
        m.sign_ok_lit = local_ok_lit;
        m.disp_nz = local_nz;
        m.live = local_live;
        m.patches_live = local_patches_live;
        m.v_rayf = lv_tier[kTierRayf];
        m.v_vol = lv_tier[kTierVol];
        m.v_esc = lv_tier[kTierEsc];
        m.v_und = lv_tier[kTierUnd];
      }
      agg.gverts += local_verts;
      agg.sign_den += local_den;
      agg.sign_ok += local_ok;
      agg.sign_ok_lit += local_ok_lit;
      agg.disp_nz += local_nz;
      agg.live += local_live;
      agg.patches += local_patches;
      agg.patches_live += local_patches_live;
      // the structurally exempt population: seam == 0 on tfrag, the WHOLE mesh on TIE
      agg.exempt += (m.system == kSysTie) ? local_verts : local_seam0;
      if (m.system != kSysTie) {
        agg.gverts_tfrag += local_verts;
        agg.disp_nz_tfrag += local_nz;
        agg.live_tfrag += local_live;
      }
      agg.v_rayf += lv_tier[kTierRayf];
      agg.v_vol += lv_tier[kTierVol];
      agg.v_esc += lv_tier[kTierEsc];
      agg.v_und += lv_tier[kTierUnd];
    }
    return agg;
  };

  const Agg agg_main = evaluate(dist_m, true);
  fmt::print("[tess_sign] evaluated {} generated vertices at d={} m\n", agg_main.gverts, dist_m);

  // ---------------------------------------------------------------------------------------------
  // §10 OUTPUT
  // ---------------------------------------------------------------------------------------------
  // WORST FIRST: ascending A_sign_pct, then ascending B_disp_pct. A row whose denominator is empty
  // (a_pct() == -1) is the worst possible outcome — nothing is measurable there — so it sorts first.
  std::vector<u32> order(meshes.size());
  for (u32 i = 0; i < meshes.size(); i++) {
    order[i] = i;
  }
  std::sort(order.begin(), order.end(), [&](u32 a, u32 b) {
    const double aa = meshes[a].a_pct(), ab = meshes[b].a_pct();
    // UNGRADED rows (a_pct() < 0, i.e. an EMPTY sign denominator) carry no A grade at all, so they
    // are placed AFTER every graded row instead of at the head: otherwise the 2875 fully
    // seam-pinned micro-meshes bury the genuinely WRONGLY-SIGNED meshes the table exists to surface.
    // Within each block the order is exactly the mandated one: ascending A_sign, then ascending
    // B_disp, then larger mesh first.
    const bool ga = aa >= 0, gb = ab >= 0;
    if (ga != gb) {
      return ga;
    }
    if (aa != ab) {
      return aa < ab;
    }
    const double la = meshes[a].b_live_pct(), lb = meshes[b].b_live_pct();
    if (la != lb) {
      return la < lb;  // then the LEAST LIVE first
    }
    const double ba = meshes[a].b_pct(), bb = meshes[b].b_pct();
    if (ba != bb) {
      return ba < bb;
    }
    if (meshes[a].gverts != meshes[b].gverts) {
      return meshes[a].gverts > meshes[b].gverts;  // bigger mesh first at equal grade
    }
    return a < b;
  });

  // how the two INDEPENDENT geometric criteria compare on this shell
  auto rayf_vs_vol = [&](const Shell& sh) -> const char* {
    if (sh.vol_sign == 0) {
      return "vol-silent";
    }
    if (sh.rayf_agree == 0 && sh.rayf_disagree == 0) {
      return "rayf-silent";
    }
    if (sh.rayf_agree > sh.rayf_disagree) {
      return "agree";
    }
    if (sh.rayf_disagree > sh.rayf_agree) {
      return "DISAGREE";
    }
    return "tie";
  };
  auto coll_vs_truth = [&](const Shell& sh) -> const char* {
    if (!sh.coll_speaks) {
      return "silent";
    }
    if (sh.gsign == 0) {
      return "no-truth";
    }
    return sh.coll_sign == sh.gsign ? "agree" : "DISAGREE";
  };
  auto baked_vs_truth = [&](const Shell& sh) -> const char* {
    if (sh.baked_sign == 0) {
      return "silent";
    }
    if (sh.gsign == 0) {
      return "no-truth";
    }
    return sh.baked_sign == sh.gsign ? "agree" : "DISAGREE";
  };
  auto pct_or_na = [](double v) {
    return v < 0 ? std::string("    n/a") : fmt::format("{:7.2f}", v);
  };

  std::string r;
  auto line = [&](const std::string& s) {
    r += s;
    r += "\n";
  };
  // the FACE COUNT decided by each outward tier, compact: R=RAYF V=VOL E=ESC U=UNDECIDED
  auto tierf_str = [](const MeshRow& m) {
    return fmt::format("R{}/V{}/E{}/U{}", m.f_rayf, m.f_vol, m.f_esc, m.f_und);
  };
  auto tierv_str = [](const MeshRow& m) {
    return fmt::format("R{}/V{}/E{}/U{}", m.v_rayf, m.v_vol, m.v_esc, m.v_und);
  };
  auto mesh_line = [&](u32 mi) {
    const auto& m = meshes[mi];
    const Shell& sh = shells[m.shell];
    return fmt::format(
        "{} {:>7.2f} {:>7.2f} {:>7.2f} {} {}  {:<5} {:>6} {:<17} {:<11} {:>5} {:<8} {:>7} {:>7}{} "
        "{:>9} {:>9} {:>7.2f} {:>8.3f} {:>8.3f} {:>7.2f} {:>7.3f}  {:<26} ({:8.2f} {:7.2f} {:8.2f})"
        "  {}",
        pct_or_na(m.a_pct()), m.b_live_pct(), m.b_pct(), m.b_patch_pct(), pct_or_na(m.b_req_pct()),
        pct_or_na(m.a_lit_pct()), kSysName[m.system], m.shell, tierf_str(m), rayf_vs_vol(sh),
        sh.winding_conflicts, coll_vs_truth(sh), m.faces.size(), m.faces_sampled,
        m.capped ? "*" : " ", m.gverts, m.exempt(), m.mean_inner(), m.disp_mean_cm(), m.disp_max_cm,
        m.verts_per_square(), m.upm, m.mat, m.centroid.x, m.centroid.y, m.centroid.z,
        m.named.empty() ? "-" : m.named);
  };
  const std::string mesh_hdr = fmt::format(
      "{:>7} {:>7} {:>7} {:>7} {:>7} {:>7}  {:<5} {:>6} {:<17} {:<11} {:>5} {:<8} {:>7} {:>8} "
      "{:>9} {:>9} {:>7} {:>8} {:>8} {:>7} {:>7}  {:<26} {:^29}  {}",
      "A_sign%", "B_live%", "B_disp%", "B_patch", "B_req%", "A_lit%", "sys", "shell",
      "tierFACES", "rayf_vs_vol", "wcf", "coll_vs_", "faces", "sampled", "gverts", "exempt",
      "meanInn", "dispMean", "dispMax", "v/sq", "upm", "material", "centroid (metres)",
      "named-case");
  // the SECOND per-mesh line: the zero-reason counters, the per-tier VERTEX counts and the
  // seam-pin reason attribution. Same row order as section A.
  auto mesh2_line = [&](u32 mi) {
    const auto& m = meshes[mi];
    return fmt::format(
        "{:<5} {:>6} {:<17} {:>9} {:>9} {:>9} {:>9} {:>9} {:>11} {:>7} {:>7} {:>7} {:>7} {:>7} "
        "{:>9} {:>7}  {:<26} {}",
        kSysName[m.system], m.shell, tierv_str(m), m.z_seam, m.z_falloff, m.z_h_mid, m.z_amp,
        m.z_not_tess, m.z_patch_dead, m.pin_src, m.pin_material, m.pin_system, m.pin_open,
        m.pin_crease, m.pin_unexplained, m.pin_unexplained_subdiv, m.mat,
        m.named.empty() ? "-" : m.named);
  };
  const std::string mesh2_hdr = fmt::format(
      "{:<5} {:>6} {:<17} {:>9} {:>9} {:>9} {:>9} {:>9} {:>11} {:>7} {:>7} {:>7} {:>7} {:>7} "
      "{:>9} {:>7}  {:<26} {}",
      "sys", "shell", "tierVERTS", "z_seam", "z_falloff", "z_h_mid", "z_amp", "z_notess",
      "z_patchdead", "pin_src", "pinMAT", "pinSYS", "pinOPEN", "pinCRSE", "PIN_UNEXP", "(subdv)",
      "material", "named-case");

  // ---- provenance -----------------------------------------------------------------------------
  line("##### TESS SIGN TEST (offline CPU port of tfrag3_tess.tesc/.tese) #####");
  line("");
  line(fmt::format("fr3                    : {}", fr3_path.string()));
  line(fmt::format("fr3 size / md5         : {} bytes / {}", fr3_bytes, fr3_md5));
  line(fmt::format("level                  : {}", lev.level_name));
  line(fmt::format("tfrag geom / tie geom  : {} / {}", geom, geom_tie));
  line(fmt::format("prep path taken        : {}", prep_note));
  line(fmt::format("--geom-orient          : {}  (mesh_consolidate cfg.bits |= 512, "
                   "kMeshBitGeomOrient: the deep, offline-only PER-FACE geometric orientation "
                   "authority)",
                   geom_orient ? "ON" : "off"));
  line(fmt::format("mesh_consolidate bits  : {}  (crease_deg {:g}, weld_m {:g})", cfg.bits,
                   cfg.crease_deg, cfg.weld_m));
  line(fmt::format("tex root               : {}", tex_root_s));
  line(fmt::format("report / csv           : {} / {}", out_path, csv_path));
  line("");
  line("--- WHAT IS MEASURED, AND WHY THIS TOOL EXISTS -------------------------------------------");
  line("The owner's test, and the only deliverable of this round: take a model, apply tessellation ON");
  line("THE CPU (a faithful port of tfrag3_tess.tesc/.tese, lines cited below), and check");
  line("PROGRAMMATICALLY that WHITE checker squares move OUT and BLACK ones move IN.");
  line("  * A_sign% = the share of generated vertices whose displacement has the CORRECT SIGN.");
  line("    h is fetched exactly as the .tese fetches it, N is the interpolated normalized vertex");
  line("    normal the .tese displaces along, and nd = dot(N, outward). The shader moves the vertex");
  line("    by  N * disp  with  disp = (h - 0.5) * amp  (.tese:420-421), so the displacement's");
  line("    component ALONG OUTWARD is   along = disp * nd = (h - 0.5) * amp * nd .");
  line("    \"White (h>0.5) must move ALONG outward\" is  along > 0 ; \"black (h<0.5) must move");
  line("    AGAINST it\" is  along < 0 ; the single condition covering both is");
  line("        SIGN CORRECT  <=>  (h - 0.5) * along > 0");
  line("    which, because amp > 0 on every counted vertex, reduces algebraically to  nd > 0 : the");
  line("    SAME test for white and for black texels. That is the point — a surface either has its");
  line("    normals pointing outward or it does not. Target 100% EVERYWHERE.");
  line("  * A_lit% = the mandate's LITERAL expression `(h - 0.5) * nd > 0`, reported for full");
  line("    disclosure and NOT used as the grade. It is the same formula with one factor of (h-0.5)");
  line("    dropped, so it demands nd > 0 on white texels and nd < 0 on black ones — i.e. it demands");
  line("    the surface be outward- and inward-facing at once. On a checkerboard (half white, half");
  line("    black BY CONSTRUCTION) it can therefore never exceed roughly the white-texel share, and");
  line("    can never reach the mandate's own 100% target. Measured before the correction: 50.04%");
  line("    level-wide and 50.15 / 49.90 / 49.52% on the three sage-hut cases — a coin flip that");
  line("    graded the broken ground floor and the known-good upper floor IDENTICALLY, i.e. it did");
  line("    not measure the defect. A_sign is the corrected metric and the one that discriminates.");
  line("  * Vertices with h == 0.5 EXACTLY, or amp == 0, have NO SIGN: they are counted in their own");
  line("    buckets (z_h_mid / z_seam / z_falloff / z_amp) and NEVER as correct.");
  line("");
  line("--- THE FOUR LIVENESS COLUMNS, each zero with a COMPUTABLE CAUSE ---------------------------");
  line("A mesh can be 100% correctly SIGNED and still be flat, so liveness is measured separately —");
  line("and split four ways so that no zero can hide behind another:");
  line("  * B_live%  = verts with amp > 0 / ALL generated verts of the mesh. The RAW, UNSHAPED");
  line("    liveness number: the share where the tier applies a non-zero amplitude. A vertex with");
  line("    amp > 0 whose sampled h is EXACTLY 0.5 IS live — 0.5 is the zero CROSSING of the height");
  line("    field, not a flat surface — and it is counted in z_h_mid at the same time, so nothing is");
  line("    hidden by that choice.");
  line("  * B_disp%  = verts with |disp| > 0 / all generated verts. Strictly B_live% minus the");
  line("    h == 0.5 population: what actually MOVES.");
  line("  * B_patch% = patches with >= 1 vertex at amp > 0 / patches evaluated. A patch with none is");
  line("    a FLAT patch: this is the column that matches the owner's \"des chunks entiers sont juste");
  line("    plats\". Its denominator is the patches EVALUATED, which equals every patch of the mesh");
  line("    unless the '*' sampling-cap marker is set on the row.");
  line("  * B_req%   = verts with amp > 0 / verts that are NOT STRUCTURALLY EXEMPT. There are exactly");
  line("    TWO structural exemptions and nothing else is ever exempt:");
  line("      (a) seam == 0 — the CRACK-GUARD PIN. mesh_consolidate pins a vertex whose two sides");
  line("          cannot displace alike (MeshConsolidate.cpp:2205-2252); the .tese then multiplies the");
  line("          amplitude by seam (.tese:416) so displacement is EXACTLY zero there. That is a");
  line("          deliberate design decision, not a defect — see the pinMAT/pinSYS/pinOPEN/pinCRSE");
  line("          columns, which prove it one vertex at a time.");
  line("      (b) z_not_tess — the mesh is TIE, and no tessellation program is ever bound for it, so");
  line("          the whole row is exempt and B_req% reads n/a.");
  line("    The `exempt` column carries the count and the second per-mesh line splits it.");
  line("  * z_patch_dead counts the vertices of patches with no live vertex at all — the same");
  line("    population B_patch% measures, expressed in vertices.");
  line("");
  line("--- THE INSPECTION-DISTANCE CONVENTION ---------------------------------------------------");
  line(fmt::format("Every distance the two stages consume is fed the SAME value d = {:.3f} m: the .tesc",
                   dist_m));
  line("level law's edge-midpoint distance and its whole-patch far gate, and the .tese's spacing /");
  line("band-limit / amplitude fade. The mesh is DECLARED to be viewed from d metres instead of a");
  line("camera being placed somewhere, so the grade is a property OF THE MESH, not of a vantage, and");
  line("two meshes on opposite sides of the level are graded on exactly equal terms.");
  line("");
  line("--- MESH AND SHELL DEFINITIONS -----------------------------------------------------------");
  line("WELD GROUP : one per unique EXACT float position triple (mesh_consolidate has already snapped");
  line("             coincident positions bit-identical, so exact equality is the correct test).");
  line("SHELL      : a connected component of faces over ALL faces of the level (both systems, all");
  line("             materials), where two faces are adjacent iff they share at least TWO weld groups");
  line("             (i.e. an edge). Union-find.");
  line("MESH       : the triple (shell id, texture id, system) restricted to DISPLACEABLE textures.");
  line("             Every such non-empty triple is one row of section A. No size filter, no row cap.");
  line("");
  line("--- GROUND TRUTH \"OUTWARD\": PER FACE FIRST, PURELY GEOMETRIC, NEVER THE COLLISION MESH ----");
  line("outward(f) = osign[f] * normalize(cross(p1-p0, p2-p0)) — the face's OWN stored winding scaled");
  line("by a sign decided by this cascade, in this order, PER FACE:");
  line("");
  line("  TIER RAYF (PRIMARY, per face, NO propagation, NO global orientation) — \"lancer de rayon");
  line("    sortant\": the visible side of a surface is the side that has OPEN SPACE on it.");
  line(fmt::format("      gn = normalize(cross(p1-p0, p2-p0)) from the face's own winding, c = centroid;"));
  line(fmt::format("      probes p_plus = c + {:g} m * gn and p_minus = c - {:g} m * gn ({:g} game units);",
                   kRayfProbeM, kRayfProbeM, kRayfProbeM * kUnitsPerM));
  line(fmt::format("      K = {} rays from each, stratified over the hemisphere about +gn / -gn;", rayf_k));
  line(fmt::format("      a ray ESCAPES iff it finds NO intersection within {:g} m; hits closer than",
                   kRayfMaxM));
  line(fmt::format("      {:g} m are ignored and the source face itself is never tested;", kRayfTMinM));
  line(fmt::format("      vote = sign(esc_plus - esc_minus), and ONLY when |esc_plus - esc_minus| >= {};",
                   kRayfMinMargin));
  line("      then outward(f) = vote * gn(f). One face = one independent problem.");
  line("    THE DIRECTION SET is a pure function of gn and contains no randomness of any kind: the");
  line("    local frame is the BRANCHLESS Duff/Frisvad basis of gn (copysign, no conditional), and the");
  line("    i-th ray takes stratum u = (i+0.5)/K of the projected-area measure — sin(theta) = sqrt(u),");
  line("    cos(theta) = sqrt(1-u) — with the azimuth advancing by the golden angle. The MINUS set is");
  line("    the EXACT MIRROR of the PLUS set (same tangential part, z negated), so the two hemispheres");
  line("    are sampled symmetrically and esc_plus / esc_minus cannot be biased against each other.");
  line("    An edge-grazing hit COUNTS as a hit: that bias is one-directional (it can only turn an");
  line("    escape into a non-escape, never invent an escape) and identical on both sides.");
  line("    WHY THIS IS NOW THE PRIMARY AUTHORITY, and the per-shell volume only a fallback:");
  line("      (1) for an OPEN shell the cone volume about the bbox centre is ORIGIN-DEPENDENT, so the");
  line("          signed-volume criterion is not even well defined there;");
  line("      (2) a per-shell verdict has to be CARRIED to each face through the relative-winding BFS,");
  line("          and ONE bad link in that BFS — a fabricated adjacency across an edge incident to 3+");
  line("          faces, a mirrored copy, a decimated LOD triangle chained onto the full-res mesh —");
  line("          flips a whole sub-tree of faces and poisons the shell.");
  line("      RAYF has neither failure mode: nothing is propagated, and a face's verdict depends on");
  line("      nothing but its own geometry and the level around it.");
  line("  TIER VOL (fallback, per shell): signed volume V6 = sum_f rel[f]*dot(a,cross(b,c)) about the");
  line(fmt::format("      bbox centre; speaks when |V6| > {:g} * L^3, L = MAX BBOX EXTENT. rel[] is the",
                   kVolEps));
  line("      RELATIVE winding from a BFS over the shell's edge adjacency (two faces are consistently");
  line("      wound iff they traverse the shared weld-group pair in OPPOSITE order).");
  line(fmt::format("  TIER ESC (fallback, per shell): escape-distance asymmetry marched against the"));
  line(fmt::format("      whole-level BVH, free distance capped at {:g} m, winner's mean must lead by",
                   kEscMaxM));
  line(fmt::format("      >= {:.0f}%. Run ONLY for a shell that still owns a mesh face RAYF abstained on.",
                   (kEscMargin - 1.0) * 100.0));
  line("  else UNDECIDED: reported as such. There is NO \"keep what was there\" fallback and");
  line("      lev.collision is NEVER consulted for the truth — that authority is exactly what produced");
  line("      the round-29 defect. It appears in section C as a DIAGNOSIS ONLY.");
  line("  REMOVED in this revision: the old per-shell TIER B \"RAY\" (outward-ray PARITY over the");
  line("      shell's own faces). Parity needs a closed shell and a trustworthy crossing count, both of");
  line("      which the per-face escape test does without. The mandated cascade is RAYF -> VOL -> ESC.");
  line("  tierFACES / tierVERTS columns give the FACE and generated-VERTEX count each tier decided,");
  line("      as R<rayf>/V<vol>/E<esc>/U<undecided>, per mesh and in the totals.");
  line("  rayf_vs_vol (section A and C) scores the TWO INDEPENDENT criteria against each other on the");
  line("      shell's own mesh faces: they agree on face f iff rayf_vote[f] == vol_sign * rel[f]. When");
  line("      they DISAGREE neither may be trusted blindly, which is exactly why it is a column.");
  line("");
  line("--- THE PORTED STEPS, WITH THE SHADER LINE FOR EACH ---------------------------------------");
  line("  .tesc:123-132  tess_seg_target_m(d) = clamp(seg*pow(max(d,5)/5, 1.5), seg, max(0.60,seg))");
  line("  .tesc:134-149  edge_level: lvl = (len_gu/4096)/seg_target(d);");
  line("                            lvl = mix(1, lvl, 1 - smoothstep(40,60,d)); clamp(lvl,1,cap)");
  line("  .tesc:179-187  outer level i OPPOSES vertex i; inner = max of the three");
  line("  .tesc:171-177  whole-patch far gate: d > 60 m => every level 1");
  line("  (GL)           fractional_odd_spacing: level -> next ODD integer (next_odd_ge)");
  line("  .tese:192-197  barycentric world/uv3/nor; N = |nrm|>1e-4 ? normalize(nrm) : (0,1,0)");
  line("  .tese:264      huv = uv3.xy — the AUTHORED texcoord, multiplied by NOTHING");
  line("  .tese:156-163  spacing_m = clamp(seg_target(d)*1.25, 0.005, 8.0)");
  line("  .tese:328-355  texels = spacing_m*upm*textureSize; hlod = clamp(log2(texels)");
  line("                          + 0.5*smoothstep(1,2,texels), 0, 12)");
  line("  .tese:359      h = hnorm(textureLod(tex_PBR_H, huv, hlod).r)");
  line("  .tese:110-112  hnorm(h) = clamp((h-mean)*norm + 0.5, 0, 1) — the IDENTITY for the checker");
  line("  .tese:367-384  seam = smoothstep(0, SEAM_BAND=0.25, clamp(bary(seam_w/65535),0,1))");
  line("  .tese:398      falloff = 1 - smoothstep(40, 60, d)");
  line("  .tese:407-420  rel = height_scale*20; drive = pow(rel,1.4); hs = 0.05*drive;");
  line("                 lambda_world_m = clamp(lambda,0.002,1)*tile_m; amp_m = hs*5*lambda_world_m;");
  line("                 amp_m = min(amp_m, 1.25*lambda_world_m); amp_m = min(amp_m, 0.15*drive);");
  line("                 amp_m = max(amp_m, 0.005*rel); amp = amp_m*4096*falloff*seam;");
  line("                 disp = (h-0.5)*amp");
  line("  .tese:462-489  the GRADIENT-NORMAL block is deliberately NOT applied to the sign: it runs");
  line("                 AFTER `world += N*disp` (.tese:421) and only rewrites the emitted SHADING");
  line("                 normal, so it cannot change the direction the vertex already moved in.");
  line("");
  line("--- UNIFORM TRUTH (read from background_common.cpp — the GLSL #define defaults are DEAD) --");
  line("  u_pbr_displacement  = 2            background_common.cpp:2032 (Tessellation)");
  line(fmt::format("  u_pbr_tess_max      = {:g}           background_common.cpp:1851 (clamped :1997)",
                   tess_max));
  line(fmt::format("  u_pbr_tess_seg      = {:g}        background_common.cpp:1863 (clamped :2036)",
                   tess_seg));
  line("  u_pbr_bisect        = 0            background_common.cpp:1999 (no A/B bit set)");
  line(fmt::format("  u_pbr_height_scale  = {:g}        = 0.05 * relief({:g})  bc.cpp:1792 + :2020",
                   height_scale, relief));
  line(fmt::format("  u_pbr_height_stat   = ({:g}, {:g})   LoaderStages.cpp:419-420 (checker => hnorm is"
                   " the identity)",
                   kPbrHeightStatMean, kPbrHeightStatNorm));
  line(fmt::format("  u_pbr_height_lambda = {:g}         LoaderStages.cpp:425 = 2.0/squares_per_tile"
                   " (= 2/{})",
                   kPbrHeightLambda, kCheckerSquaresPerTile));
  line("  u_pbr_uv_per_m      = MEASURED per material AND per system — see section D");
  line("  compile-time (.tesc/.tese): TESS_SEG_D0_M 5.0, TESS_SEG_FAR_M 0.60, TESS_SEG_EXP 1.5,");
  line("    TESS_FADE_LO_M 40.0, TESS_FADE_HI_M 60.0, TESS_SPACING_SAFETY 1.25, TESS_LOD_BIAS 0.5,");
  line("    TESS_DEPTH_K 5.0, PBR_DRIVE_EXP 1.4, TESS_DEPTH_MAX_RATIO 1.25, TESS_DEPTH_MAX_M 0.15,");
  line("    TESS_DISP_UNITS_PER_M 4096.0, SEAM_BAND 0.25");
  line("");
  line("--- THE CHECKER (PbrTestPattern.cpp, reproduced exactly) ---------------------------------");
  line(fmt::format("  kMapDim {} (PbrTestPattern.cpp:20), squares_per_tile {} (:264) => cell {} texels",
                   kCheckerDim, kCheckerSquaresPerTile, kCheckerDim / kCheckerSquaresPerTile));
  line("  height texel = ((px/cell + py/cell) & 1) ? 255 : 0   (:51 checker_at, :128 profile_h with");
  line("  the round-26 default height_profile()==0 hard step, :155-157 make_height_rgba, R=G=B=v)");
  line("  PARITY: cell (0,0) is checker 0 = height 0 = BLACK; the WHITE albedo square (:285 paints");
  line("  215 when checker_at == 1) is exactly the height-255 square. So WHITE => h > 0.5 => must");
  line("  move ALONG outward, BLACK => h < 0.5 => must move AGAINST it.");
  line(fmt::format("  FULL mip chain 0..{} built by successive 2x2 box averaging in float (what",
                   checker.max_lod()));
  line("  glGenerateMipmap does), fetched trilinearly with GL_REPEAT and half-texel centres.");
  line("");
  line("--- DISPLACEABLE MATERIALS: DATA-DRIVEN, NOTHING HARDCODED --------------------------------");
  line(fmt::format("Recursive scan of {} for <name>_height.png.", tex_root_s));
  line(fmt::format("  discovered {} material(s):", displaceable.size()));
  {
    std::string acc = "   ";
    for (const auto& n : displaceable) {
      if (acc.size() + n.size() + 2 > 98) {
        line(acc);
        acc = "   ";
      }
      acc += " " + n;
    }
    if (acc.size() > 3) {
      line(acc);
    }
  }
  line("A tfrag3::Texture is displaceable iff its debug_name is in that set. Drop 50-200 new map sets");
  line("in and they become displaceable with no code change — no material name appears in this tool.");
  line("");
  line("--- TRIANGLE UNIVERSE ---------------------------------------------------------------------");
  line(fmt::format("tfrag: lev.tfrag_trees[{}] , every tree with kind != INVALID. THE SHIPPED GATE is",
                   geom));
  line("  TFragment.cpp:617-632 — `tess_kind_eligible = tree.kind != INVALID`. The NORMAL/DIRT/ICE");
  line("  allowlist tools/tess_audit/main.cpp:130 still uses is STALE (the owner removed it on");
  line("  2026-07-26: \"bah elle devrait pouvoir tourner partout !\"), so this tool uses the shipped rule.");
  line("tie: lev.tie_trees[" + std::to_string(geom_tie) +
       "] static_draws ONLY (see the wind drop below). tessellated = FALSE:");
  line("  Tie3.cpp:737 binds `use_envmap ? ETIE_BASE : TFRAG3`, Tie3.cpp:1158 binds ETIE and");
  line("  Tie3.cpp:1546 binds TIE_WIND — all vert+frag programs with NO tessellation control or");
  line("  evaluation stage — and there is no glPatchParameteri and no GL_PATCHES anywhere in Tie3.cpp.");
  line("  TIE relief is per-pixel POM instead, so a TIE row's B_disp% is 0.00 BY CONSTRUCTION and its");
  line("  whole vertex count lands in z_not_tess. Its A_sign% is still reported: it is the WOULD-BE");
  line("  sign correctness, i.e. a direct measurement of whether that mesh's normals point outward.");
  line("  Its dispMean / dispMax columns are HYPOTHETICAL for the same reason — they are what the");
  line("  tier WOULD move if TIE were ever handed a tessellation program. Read them as such.");
  line("");
  line("--- DROPPED FROM THE UNIVERSE: THE PROTO-LOCAL WIND INSTANCES ------------------------------");
  line(fmt::format("DROPPED: {} instanced_wind_draws, {} faces, {} index-stream entries.",
                   n_wind_draws_dropped, n_wind_faces_dropped, n_wind_stream_inds_dropped));
  line("REASON, in full. instanced_wind_draws vertices live in PROTOTYPE-LOCAL space: TieTree::unpack");
  line("leaves the matrix_idx == -1 groups untransformed (see MeshSubdivide.h's");
  line("tie_wind_static_shared_verts note), so a wind vertex's x/y/z is an offset inside its prototype");
  line("and NOT a world coordinate. Three consequences, each of which alone disqualifies them here:");
  line("  (1) mesh_consolidate() NEVER SEES THEM — gather_level (MeshConsolidate.cpp:340-347) walks");
  line("      only unpacked.indices — so no weld group, no snapped position and no seam verdict of");
  line("      theirs exists to be graded;");
  line("  (2) TIE_WIND is a SEPARATE GL program (Tie3.cpp:1546) with no tessellation control or");
  line("      evaluation stage, so nothing would ever displace them;");
  line("  (3) mixed into a WORLD-SPACE face list their proto-local positions FABRICATE shells,");
  line("      fabricate BVH occluders (which would corrupt the RAYF escape test for real faces) and");
  line("      fabricate table rows out of coordinates that mean nothing.");
  line("The previous revision included them and merely flagged them; they were polluting the shells and");
  line("the table, so they are now removed from the face universe outright. static_draws are KEPT.");
  line("");
  line("--- SEAM-PIN REASON ATTRIBUTION (why every seam == 0 vertex is pinned) ---------------------");
  line("Every vertex with seam == 0 has its pin explained by RECOMPUTING the four pin reasons of");
  line("MeshConsolidate.cpp:2216-2252 from the geometry this tool already has. The population is the");
  line("mesh's DISTINCT SOURCE vertices with seam_w == 0 (a pin is a property of a WELD GROUP, not of a");
  line("generated vertex), so these counts are vertex counts and NOT the z_seam generated-vertex count.");
  line("  pinMAT  (:2218 group_multitex)    the weld group is referenced by faces with different");
  line("                                    tree_tex_id — the height map is bound PER DRAW, so the two");
  line("                                    sides cannot sample the same height;");
  line("  pinSYS  (:2219 group_multisystem) the group spans more than one of tfrag / tie / shrub. Shrub");
  line("                                    is not in this tool's FACE universe (never tessellated,");
  line("                                    never graded) but IS in mesh_consolidate's WELD universe");
  line("                                    (:345-348), so shrub membership is detected by exact");
  line("                                    position against the shrub draws' referenced vertices");
  line("                                    (:682-698) — otherwise a tfrag<->shrub junction would look");
  line("                                    unexplained;");
  line("  pinOPEN (:2220 group_open)        a welded GROUP edge of the group is used by exactly ONE");
  line("                                    face (:858-861) — a genuine boundary, nothing to match;");
  line(fmt::format("  pinCRSE (:2221)                   the group's incident faces fall into >= 2 clusters at"));
  line(fmt::format("                                    the crease threshold ({:g} deg, cos {:.4f}, the SAME",
                   cfg.crease_deg,
                   std::cos((double)cfg.crease_deg * 3.14159265358979323846 / 180.0)));
  line("                                    cfg the consolidation ran with) AND the group has >= 2");
  line("                                    referenced members. Clustering is largest-face-first with");
  line("                                    ties on the lower slot, as :1904-1936, and the incident");
  line("                                    normals are oriented by rel[] (this tool's relative-winding");
  line("                                    BFS) since mesh_consolidate's own fsign[] is internal.");
  line("The four are NOT mutually exclusive — a group can be pinned for several reasons at once and is");
  line("counted under each, exactly as rep.seam_verts_material/_system/_open/_crease are.");
  line("PIN_UNEXP counts pins matching NONE of the four. THAT IS A BUG and section E prints up to 20 of");
  line("their positions. Its (subdv) sub-count is the pins carried by a vertex CREATED by the");
  line("pre-subdivision pass, whose seam_w is the LINEAR average of two already-pinned parents");
  line("(MeshSubdivide.cpp:271) rather than a verdict on its own group — those are explained by");
  line("INHERITANCE and are not evidence of a missing reason.");
  line("");
  line(fmt::format("faces gathered         : {}  (degenerate skipped {}, out-of-range {})",
                   faces.size(), n_degenerate, n_oob));
  line(fmt::format("global vertices        : {}", gv.size()));
  line(fmt::format("weld groups            : {}", n_groups));
  line(fmt::format("distinct edges          : {}", edges.size()));
  line(fmt::format("SHELL COUNT            : {}", n_shells));
  line(fmt::format("mesh faces (displaceable): {}  = the RAYF population", n_mesh_faces));
  line(fmt::format("meshes (rows in A)     : {}", meshes.size()));
  line(fmt::format("sampling cap           : {} generated vertices per mesh", max_verts_per_mesh));
  line(fmt::format("RAYF pass              : K={} rays per hemisphere, {:.1f} s wall clock, {} threads"
                   " (per-face independent, so the thread count cannot move a single bit)",
                   rayf_k, rayf_seconds, std::max(1u, std::thread::hardware_concurrency())));
  line("");
  line(subdiv_note);
  line("--- format_mesh_audit(rep, cfg) ----------------------------------------------------------");
  line(mesh_audit_text);

  // ---- A) PER-MESH TABLE ----------------------------------------------------------------------
  line("");
  line(std::string(100, '='));
  line("### A) PER-MESH TABLE (one line per mesh, sorted WORST FIRST by A_sign% then B_live%)");
  line("");
  line("columns: A_sign% = correct-sign share of the vertices that HAVE a sign (amp>0 and h!=0.5);");
  line("         'n/a' = that denominator is EMPTY (nothing measurable here). Those UNGRADED rows are");
  line("         sorted to the END of the table, after every graded row, so the wrongly-signed meshes");
  line("         are at the head instead of being buried under the fully seam-pinned micro-meshes;");
  line("         their count is in section E. B_live / B_disp / B_patch / B_req are the four liveness");
  line("         columns derived in the header (B_req's n/a = every vertex of the row is structurally");
  line("         exempt, which is what a TIE row is). tierFACES = the FACE count each outward tier");
  line("         decided, R=RAYF V=VOL E=ESC U=UNDECIDED. rayf_vs_vol = per-face RAYF majority against");
  line("         the shell's signed-volume verdict. wcf = winding conflicts of the shell. coll_vs_ =");
  line("         how the COLLISION authority compares to the shell fallback verdict (DIAGNOSIS ONLY —");
  line("         it decides nothing here). A '*' after `sampled` means the per-mesh sampling cap bit.");
  line("         exempt = structurally exempt generated vertices (seam==0, or the whole TIE row).");
  line("         v/sq = generated vertices across one checker square. dispMean/dispMax in CENTIMETRES.");
  line("");
  line(mesh_hdr);
  line(std::string(mesh_hdr.size(), '-'));
  for (u32 mi : order) {
    line(mesh_line(mi));
  }

  // ---- A2) PER-MESH ZERO REASONS + SEAM-PIN ATTRIBUTION ---------------------------------------
  line("");
  line(std::string(100, '='));
  line("### A2) PER-MESH ZERO REASONS AND SEAM-PIN ATTRIBUTION (same row order as section A)");
  line("");
  line("tierVERTS = generated-VERTEX count per outward tier. z_* are generated-vertex counts;");
  line("z_patchdead = vertices of patches with NO live vertex at all. pin* are DISTINCT SOURCE vertex");
  line("counts over the mesh's seam==0 vertices and are NOT mutually exclusive; PIN_UNEXP matching none");
  line("of the four is a BUG (see section E), and (subdv) is the part of it carried by vertices the");
  line("pre-subdivision created, whose pin is inherited from two pinned parents.");
  line("");
  line(mesh2_hdr);
  line(std::string(mesh2_hdr.size(), '-'));
  for (u32 mi : order) {
    line(mesh2_line(mi));
  }

  // ---- B) NAMED CASES -------------------------------------------------------------------------
  line("");
  line(std::string(100, '='));
  line("### B) NAMED CASES (--named-case boxes, in metres; a mesh is labelled when its CENTROID is in)");
  line("");
  if (named.empty()) {
    line("(no --named-case given)");
  }
  std::set<u32> named_shells;
  for (const auto& nb : named) {
    line(fmt::format("--- {}  box x[{:.2f},{:.2f}] y[{:.2f},{:.2f}] z[{:.2f},{:.2f}]", nb.name,
                     nb.lo[0], nb.hi[0], nb.lo[1], nb.hi[1], nb.lo[2], nb.hi[2]));
    u64 hits = 0, den = 0, ok = 0, ok_lit = 0, gvv = 0, nz = 0, lv = 0, ex = 0, pat = 0,
        pat_live = 0;
    u64 fR = 0, fV = 0, fE = 0, fU = 0, vR = 0, vV = 0, vE = 0, vU = 0;
    u64 ps = 0, pm = 0, py = 0, po = 0, pc = 0, pu = 0;
    std::vector<u32> case_rows;
    line(mesh_hdr);
    for (u32 mi : order) {
      if (meshes[mi].named.find(nb.name) == std::string::npos) {
        continue;
      }
      const auto& m = meshes[mi];
      hits++;
      den += m.sign_den;
      ok += m.sign_ok;
      ok_lit += m.sign_ok_lit;
      gvv += m.gverts;
      nz += m.disp_nz;
      lv += m.live;
      ex += m.exempt();
      pat += m.faces_sampled;
      pat_live += m.patches_live;
      fR += m.f_rayf;
      fV += m.f_vol;
      fE += m.f_esc;
      fU += m.f_und;
      vR += m.v_rayf;
      vV += m.v_vol;
      vE += m.v_esc;
      vU += m.v_und;
      ps += m.pin_src;
      pm += m.pin_material;
      py += m.pin_system;
      po += m.pin_open;
      pc += m.pin_crease;
      pu += m.pin_unexplained;
      named_shells.insert(m.shell);
      case_rows.push_back(mi);
      line(mesh_line(mi));
    }
    if (!hits) {
      line("  (no mesh centroid falls inside this box)");
    } else {
      line("");
      line("  " + mesh2_hdr);
      for (u32 mi : case_rows) {
        line("  " + mesh2_line(mi));
      }
      line("");
      line(fmt::format("  CASE TOTAL  meshes={}  faces={}  gverts={}", hits,
                       [&] {
                         u64 n = 0;
                         for (u32 mi : case_rows) {
                           n += meshes[mi].faces.size();
                         }
                         return n;
                       }(),
                       gvv));
      line(fmt::format("  CASE A_sign = {}  ({}/{} vertices)     A_lit = {}",
                       den ? fmt::format("{:.2f}%", 100.0 * (double)ok / (double)den)
                           : std::string("n/a"),
                       ok, den,
                       den ? fmt::format("{:.2f}%", 100.0 * (double)ok_lit / (double)den)
                           : std::string("n/a")));
      line(fmt::format("  CASE B_live = {:.2f}% ({}/{})   B_disp = {:.2f}% ({}/{})   B_patch = {}"
                       "   B_req = {}",
                       gvv ? 100.0 * (double)lv / (double)gvv : 0.0, lv, gvv,
                       gvv ? 100.0 * (double)nz / (double)gvv : 0.0, nz, gvv,
                       pat ? fmt::format("{:.2f}% ({}/{})",
                                         100.0 * (double)pat_live / (double)pat, pat_live, pat)
                           : std::string("n/a"),
                       gvv > ex ? fmt::format("{:.2f}% ({}/{})",
                                              100.0 * (double)lv / (double)(gvv - ex), lv,
                                              gvv - ex)
                                : std::string("n/a")));
      line(fmt::format("  CASE tierFACES = R{}/V{}/E{}/U{}   tierVERTS = R{}/V{}/E{}/U{}", fR, fV,
                       fE, fU, vR, vV, vE, vU));
      line(fmt::format("  CASE pins: src={} MAT={} SYS={} OPEN={} CRSE={} UNEXPLAINED={}", ps, pm,
                       py, po, pc, pu));
      // the two independent criteria, over this case's own mesh faces
      u64 ca = 0, cd = 0, cv = 0;
      for (u32 s : [&] {
             std::set<u32> ss;
             for (u32 mi : case_rows) {
               ss.insert(meshes[mi].shell);
             }
             return ss;
           }()) {
        ca += shells[s].rayf_agree;
        cd += shells[s].rayf_disagree;
        cv += shells[s].rayf_voted;
      }
      line(fmt::format("  CASE rayf_vs_vol over the shells above: voted={} agree={} DISAGREE={}", cv,
                       ca, cd));
    }
    line("");
  }

  // ---- C) SHELL AUTHORITY TABLE ---------------------------------------------------------------
  line(std::string(100, '='));
  line("### C) SHELL AUTHORITY TABLE (every shell touching a displaceable material)");
  line("");
  line("gsign/tier = the SHELL-LEVEL FALLBACK verdict and the tier that produced it (VOL / ESC /");
  line("UNDECIDED). It is NOT the primary authority any more: a face is decided by the per-face RAYF");
  line("tier first and only falls back to this. A shell can therefore read UNDECIDED here while every");
  line("one of its mesh faces is decided — check the tierFACES column of section A. ESC is also only");
  line("run when a mesh face of the shell actually needs it, so esc_ratio is 0 on shells RAYF covered.");
  line("vol_sign is the SIGNED-VOLUME verdict alone; rayf_voted/agree/DISAGREE and rayf_vs_vol score the");
  line("two INDEPENDENT geometric criteria against each other over the shell's mesh faces (they agree on");
  line("face f iff rayf_vote[f] == vol_sign * rel[f]). A DISAGREE row is a shell where NEITHER criterion");
  line("may be trusted blindly. coll_* and baked_* are DIAGNOSIS ONLY: what the pipeline's own");
  line("authorities claim, scored against the shell fallback verdict.");
  line("");
  const std::string shell_hdr = fmt::format(
      "{:>6} {:>7} {:>7} {:<9} {:>6} {:>8} {:>12} {:>6} {:>9} {:>8} {:>8} {:>9} {:<11} {:>5} {:<9} "
      "{:>6} {:<9}",
      "shell", "faces", "meshes", "tier", "gsign", "vol_sign", "|V6|/L^3", "wcf", "esc_ratio",
      "rayf_vot", "rayf_agr", "rayf_DIS", "rayf_vs_vol", "coll", "coll_vs_", "baked", "baked_vs_");
  line(shell_hdr);
  line(std::string(shell_hdr.size(), '-'));
  std::vector<u32> meshes_per_shell(n_shells, 0);
  for (const auto& m : meshes) {
    meshes_per_shell[m.shell]++;
  }
  std::vector<u32> shell_order;
  for (u32 s = 0; s < n_shells; s++) {
    if (shells[s].has_displaceable) {
      shell_order.push_back(s);
    }
  }
  auto shell_line = [&](u32 s) {
    const Shell& sh = shells[s];
    return fmt::format(
        "{:>6} {:>7} {:>7} {:<9} {:>6} {:>8} {:>12.4g} {:>6} {:>9.3f} {:>8} {:>8} {:>9} {:<11} {:>5} "
        "{:<9} {:>6} {:<9}",
        s, sh.faces.size(), meshes_per_shell[s], sh.tier,
        sh.gsign == 0 ? "0" : (sh.gsign > 0 ? "+1" : "-1"),
        sh.vol_sign == 0 ? "0" : (sh.vol_sign > 0 ? "+1" : "-1"), sh.v6_over_l3,
        sh.winding_conflicts, sh.esc_ratio, sh.rayf_voted, sh.rayf_agree, sh.rayf_disagree,
        rayf_vs_vol(sh), sh.coll_speaks ? (sh.coll_sign > 0 ? "+1" : "-1") : "-", coll_vs_truth(sh),
        sh.baked_sign == 0 ? "0" : (sh.baked_sign > 0 ? "+1" : "-1"), baked_vs_truth(sh));
  };
  for (u32 s : shell_order) {
    line(shell_line(s));
  }

  // ---- D) uv_per_m ----------------------------------------------------------------------------
  line("");
  line(std::string(100, '='));
  line("### D) uv_per_m PER MATERIAL PER SYSTEM");
  line("");
  line("A VERBATIM port of background_common.cpp measure_uv_density_tfrag (:661) and");
  line("measure_uv_density_tie (:678): the MEDIAN of |d(uv)|_tiles / |d(pos)|_m over the index buffer's");
  line("consecutive-index pairs, GEOM 0 only, capped at 8192 samples; fewer than 16 samples returns 0");
  line("=> the caller falls back to 0.5 (PbrDrawBinder::set, background_common.cpp:884). TFRAG rows use");
  line("the tfrag value and TIE rows the tie value, exactly as the runtime does per draw.");
  line("");
  line(fmt::format("{:<28} {:>10} {:>9} {:>10} {:>10} {:>9} {:>10}", "material", "tfrag_upm",
                   "samples", "src", "tie_upm", "samples", "src"));
  line(std::string(90, '-'));
  for (const auto& kv : uv_by_mat) {
    line(fmt::format("{:<28} {:>10.4f} {:>9} {:>10} {:>10.4f} {:>9} {:>10}", kv.first,
                     kv.second.tfrag, kv.second.tfrag_samples,
                     kv.second.tfrag_measured ? "measured" : "fallback", kv.second.tie,
                     kv.second.tie_samples, kv.second.tie_measured ? "measured" : "fallback"));
  }

  // ---- E) TOTALS ------------------------------------------------------------------------------
  u64 n_perfect = 0, n_na = 0, n_capped = 0, n_undecided_meshes = 0, n_a100 = 0, n_a_zero = 0;
  u32 worst_a = UINT32_MAX, worst_b = UINT32_MAX, worst_live = UINT32_MAX,
      worst_patch = UINT32_MAX, worst_req = UINT32_MAX;
  for (u32 i = 0; i < meshes.size(); i++) {
    const auto& m = meshes[i];
    if (m.a_pct() < 0) {
      n_na++;
    } else {
      if (m.a_pct() >= 100.0) {
        n_a100++;
        if (m.b_pct() >= 100.0) {
          n_perfect++;
        }
      }
      if (m.a_pct() <= 0.0) {
        n_a_zero++;
      }
    }
    if (m.capped) {
      n_capped++;
    }
    if (shells[m.shell].gsign == 0) {
      n_undecided_meshes++;
    }
    if (m.a_pct() >= 0 && (worst_a == UINT32_MAX || m.a_pct() < meshes[worst_a].a_pct())) {
      worst_a = i;
    }
    if (worst_b == UINT32_MAX || m.b_pct() < meshes[worst_b].b_pct()) {
      worst_b = i;
    }
    if (worst_live == UINT32_MAX || m.b_live_pct() < meshes[worst_live].b_live_pct()) {
      worst_live = i;
    }
    if (worst_patch == UINT32_MAX || m.b_patch_pct() < meshes[worst_patch].b_patch_pct()) {
      worst_patch = i;
    }
    if (m.b_req_pct() >= 0 &&
        (worst_req == UINT32_MAX || m.b_req_pct() < meshes[worst_req].b_req_pct())) {
      worst_req = i;
    }
  }
  u64 n_shell_undecided = 0;
  for (u32 s : shell_order) {
    if (shells[s].gsign == 0) {
      n_shell_undecided++;
    }
  }
  line("");
  line(std::string(100, '='));
  line("### E) TOTALS");
  line("");
  line(fmt::format("inspection distance         : {:.3f} m", dist_m));
  line(fmt::format("meshes                      : {}", meshes.size()));
  line(fmt::format("faces in meshes             : {}",
                   [&] {
                     u64 n = 0;
                     for (const auto& m : meshes) {
                       n += m.faces.size();
                     }
                     return n;
                   }()));
  line(fmt::format("generated vertices          : {}", agg_main.gverts));
  line(fmt::format("vertices WITH a sign        : {}  ({:.2f}% of generated)", agg_main.sign_den,
                   agg_main.gverts ? 100.0 * (double)agg_main.sign_den / (double)agg_main.gverts
                                   : 0.0));
  line(fmt::format("A_sign OVERALL              : {}",
                   agg_main.sign_den
                       ? fmt::format("{:.4f}%  ({}/{})",
                                     100.0 * (double)agg_main.sign_ok / (double)agg_main.sign_den,
                                     agg_main.sign_ok, agg_main.sign_den)
                       : std::string("n/a")));
  line(fmt::format("A_lit  OVERALL (spec literal): {}   <-- structurally capped near the white-texel"
                   " share; see the derivation in the header",
                   agg_main.sign_den
                       ? fmt::format("{:.4f}%  ({}/{})",
                                     100.0 * (double)agg_main.sign_ok_lit / (double)agg_main.sign_den,
                                     agg_main.sign_ok_lit, agg_main.sign_den)
                       : std::string("n/a")));
  line("");
  line("---- THE FOUR LIVENESS NUMBERS, each with the mesh that owns the WORST value ----");
  auto owner_of = [&](u32 i) {
    const auto& m = meshes[i];
    return fmt::format("shell {} {} {} (centroid {:.2f} {:.2f} {:.2f} m){}", m.shell,
                       kSysName[m.system], m.mat, m.centroid.x, m.centroid.y, m.centroid.z,
                       m.named.empty() ? "" : "  [" + m.named + "]");
  };
  line(fmt::format("B_live  OVERALL             : {:.4f}%  ({}/{})",
                   agg_main.gverts ? 100.0 * (double)agg_main.live / (double)agg_main.gverts : 0.0,
                   agg_main.live, agg_main.gverts));
  if (worst_live != UINT32_MAX) {
    line(fmt::format("   WORST B_live             : {:.2f}%  {}", meshes[worst_live].b_live_pct(),
                     owner_of(worst_live)));
  }
  line(fmt::format("B_disp  OVERALL             : {:.4f}%  ({}/{})",
                   agg_main.gverts ? 100.0 * (double)agg_main.disp_nz / (double)agg_main.gverts : 0.0,
                   agg_main.disp_nz, agg_main.gverts));
  if (worst_b != UINT32_MAX) {
    line(fmt::format("   WORST B_disp             : {:.2f}%  {}", meshes[worst_b].b_pct(),
                     owner_of(worst_b)));
  }
  line(fmt::format("B_patch OVERALL             : {:.4f}%  ({}/{} patches)",
                   agg_main.patches
                       ? 100.0 * (double)agg_main.patches_live / (double)agg_main.patches
                       : 0.0,
                   agg_main.patches_live, agg_main.patches));
  if (worst_patch != UINT32_MAX) {
    line(fmt::format("   WORST B_patch            : {:.2f}%  {}", meshes[worst_patch].b_patch_pct(),
                     owner_of(worst_patch)));
  }
  line(fmt::format("B_req   OVERALL             : {}   exempt {} of {} generated verts",
                   agg_main.gverts > agg_main.exempt
                       ? fmt::format("{:.4f}%  ({}/{})",
                                     100.0 * (double)agg_main.live /
                                         (double)(agg_main.gverts - agg_main.exempt),
                                     agg_main.live, agg_main.gverts - agg_main.exempt)
                       : std::string("n/a"),
                   agg_main.exempt, agg_main.gverts));
  if (worst_req != UINT32_MAX) {
    line(fmt::format("   WORST B_req              : {:.2f}%  {}", meshes[worst_req].b_req_pct(),
                     owner_of(worst_req)));
  }
  line(fmt::format("TFRAG-ONLY B_live / B_disp  : {:.4f}% / {:.4f}%  over {} generated verts (the "
                   "population a tessellation program is actually bound for)",
                   agg_main.gverts_tfrag
                       ? 100.0 * (double)agg_main.live_tfrag / (double)agg_main.gverts_tfrag
                       : 0.0,
                   agg_main.gverts_tfrag
                       ? 100.0 * (double)agg_main.disp_nz_tfrag / (double)agg_main.gverts_tfrag
                       : 0.0,
                   agg_main.gverts_tfrag));
  line("");
  if (worst_a != UINT32_MAX) {
    line(fmt::format("WORST A_sign                : {:.2f}%  {}", meshes[worst_a].a_pct(),
                     owner_of(worst_a)));
  }
  line(fmt::format("meshes at A_sign = 100%     : {}  of {} GRADED meshes ({:.2f}%)  <== THE GATE",
                   n_a100, meshes.size() - n_na,
                   (meshes.size() - n_na)
                       ? 100.0 * (double)n_a100 / (double)(meshes.size() - n_na)
                       : 0.0));
  line(fmt::format("meshes at A_sign = 0%       : {}  (every graded vertex moves the WRONG WAY)",
                   n_a_zero));
  line(fmt::format("meshes at 100/100           : {}  ({:.2f}%)", n_perfect,
                   meshes.empty() ? 0.0 : 100.0 * (double)n_perfect / (double)meshes.size()));
  line("   (100/100 additionally demands B_disp == 100%, which the CHECKER itself makes unreachable:");
  line("    its box-filtered mips contain texels that are EXACTLY 127.5/255 = 0.5, and every");
  line("    seam-pinned vertex has amp == 0. A_sign = 100% is the SIGN gate; B_disp is the separate");
  line("    liveness one.)");
  line(fmt::format("meshes with A_sign = n/a    : {}  (empty denominator: every vertex was either "
                   "amp==0 or exactly h==0.5, or the shell is UNDECIDED)",
                   n_na));
  line(fmt::format("meshes on an UNDECIDED shell: {}", n_undecided_meshes));
  line(fmt::format("shells in section C         : {}  of which UNDECIDED {}", shell_order.size(),
                   n_shell_undecided));
  line(fmt::format("meshes where the cap bit    : {}  (--max-verts-per-mesh {})", n_capped,
                   max_verts_per_mesh));
  {
    u64 zs = 0, zf = 0, zh = 0, za = 0, zn = 0, zp = 0;
    u64 fR = 0, fV = 0, fE = 0, fU = 0;
    for (const auto& m : meshes) {
      zs += m.z_seam;
      zf += m.z_falloff;
      zh += m.z_h_mid;
      za += m.z_amp;
      zn += m.z_not_tess;
      zp += m.z_patch_dead;
      fR += m.f_rayf;
      fV += m.f_vol;
      fE += m.f_esc;
      fU += m.f_und;
    }
    line("");
    line(fmt::format("zero-reason totals          : z_seam={} z_falloff={} z_h_mid={} z_amp={} "
                     "z_not_tess={} z_patch_dead={}",
                     zs, zf, zh, za, zn, zp));
    // THE SINGLE LARGEST CAUSE of amp == 0, computed and named rather than assumed. z_h_mid is NOT a
    // cause of amp == 0 (such a vertex is LIVE, it merely sits on the height field's zero crossing),
    // so it is excluded from this ranking and reported separately.
    {
      const u64 dead = agg_main.gverts - agg_main.live;
      std::vector<std::pair<u64, const char*>> causes = {
          {zs, "z_seam (the crack-guard pin)"},
          {zn, "z_not_tess (TIE: no tessellation program is ever bound)"},
          {zf, "z_falloff (the distance amplitude fade)"},
          {za, "z_amp (amp_m == 0)"}};
      std::sort(causes.begin(), causes.end(), [](const auto& a, const auto& b) {
        return a.first != b.first ? a.first > b.first : std::strcmp(a.second, b.second) < 0;
      });
      line(fmt::format("verts with amp == 0         : {}  ({:.2f}% of generated)", dead,
                       agg_main.gverts ? 100.0 * (double)dead / (double)agg_main.gverts : 0.0));
      for (const auto& c : causes) {
        line(fmt::format("   {:<58} {:>10}  {:>6.2f}% of the amp==0 population", c.second, c.first,
                         dead ? 100.0 * (double)c.first / (double)dead : 0.0));
      }
      if (!causes.empty()) {
        line(fmt::format("LARGEST CAUSE of amp == 0   : {}  = {} verts, {:.2f}% of the amp==0 "
                         "population ({:.2f}% of all generated verts)",
                         causes.front().second, causes.front().first,
                         dead ? 100.0 * (double)causes.front().first / (double)dead : 0.0,
                         agg_main.gverts
                             ? 100.0 * (double)causes.front().first / (double)agg_main.gverts
                             : 0.0));
      }
      line(fmt::format("   (z_h_mid = {} verts are LIVE with h exactly 0.5: amp > 0, disp == 0 — the "
                       "zero crossing of the height field, NOT a flat surface)",
                       zh));
    }
    line("");
    line(fmt::format("OUTWARD TIER, FACES         : RAYF={} VOL={} ESC={} UNDECIDED={}  (of {} mesh"
                     " faces counted once per mesh row)",
                     fR, fV, fE, fU, fR + fV + fE + fU));
    line(fmt::format("OUTWARD TIER, GEN. VERTICES : RAYF={} VOL={} ESC={} UNDECIDED={}",
                     agg_main.v_rayf, agg_main.v_vol, agg_main.v_esc, agg_main.v_und));
    line(fmt::format("   RAYF share of the graded work: {:.2f}% of faces, {:.2f}% of vertices",
                     (fR + fV + fE + fU) ? 100.0 * (double)fR / (double)(fR + fV + fE + fU) : 0.0,
                     agg_main.gverts ? 100.0 * (double)agg_main.v_rayf / (double)agg_main.gverts
                                     : 0.0));
  }
  // ---- the two INDEPENDENT geometric criteria, scored against each other ----
  {
    u64 sh_agree = 0, sh_dis = 0, sh_volsilent = 0, sh_rayfsilent = 0, sh_tie = 0;
    u64 f_agree = 0, f_dis = 0, f_voted = 0;
    for (u32 s : shell_order) {
      const char* v = rayf_vs_vol(shells[s]);
      if (!std::strcmp(v, "agree")) {
        sh_agree++;
      } else if (!std::strcmp(v, "DISAGREE")) {
        sh_dis++;
      } else if (!std::strcmp(v, "vol-silent")) {
        sh_volsilent++;
      } else if (!std::strcmp(v, "rayf-silent")) {
        sh_rayfsilent++;
      } else {
        sh_tie++;
      }
      f_agree += shells[s].rayf_agree;
      f_dis += shells[s].rayf_disagree;
      f_voted += shells[s].rayf_voted;
    }
    line("");
    line(fmt::format("rayf_vs_vol (shells)        : agree={} DISAGREE={} tie={} vol-silent={} "
                     "rayf-silent={}",
                     sh_agree, sh_dis, sh_tie, sh_volsilent, sh_rayfsilent));
    line(fmt::format("rayf_vs_vol (mesh faces)    : voted={} agree={} DISAGREE={} ({:.2f}% of the "
                     "comparable faces DISAGREE)",
                     f_voted, f_agree, f_dis,
                     (f_agree + f_dis) ? 100.0 * (double)f_dis / (double)(f_agree + f_dis) : 0.0));
    line("   A DISAGREE shell is one where the two INDEPENDENT geometric criteria hand the same face");
    line("   opposite outward directions. Neither may be trusted blindly there; that is the whole");
    line("   reason this column exists.");
  }
  // ---- seam-pin reason attribution ----
  {
    line("");
    line(fmt::format("PINNED SOURCE VERTS (level) : {}  (distinct vertices with seam_w == 0 in a "
                     "graded mesh)",
                     tot_pin_src));
    line(fmt::format("   pinMAT  (multi-texture)  : {:>9}  {:>6.2f}%", tot_pin_material,
                     tot_pin_src ? 100.0 * (double)tot_pin_material / (double)tot_pin_src : 0.0));
    line(fmt::format("   pinSYS  (multi-system)   : {:>9}  {:>6.2f}%", tot_pin_system,
                     tot_pin_src ? 100.0 * (double)tot_pin_system / (double)tot_pin_src : 0.0));
    line(fmt::format("   pinOPEN (open boundary)  : {:>9}  {:>6.2f}%", tot_pin_open,
                     tot_pin_src ? 100.0 * (double)tot_pin_open / (double)tot_pin_src : 0.0));
    line(fmt::format("   pinCRSE (hard crease)    : {:>9}  {:>6.2f}%", tot_pin_crease,
                     tot_pin_src ? 100.0 * (double)tot_pin_crease / (double)tot_pin_src : 0.0));
    line(fmt::format("   PIN_UNEXPLAINED          : {:>9}  {:>6.2f}%   <== a pin matching NONE of the "
                     "four is a BUG",
                     tot_pin_unexpl,
                     tot_pin_src ? 100.0 * (double)tot_pin_unexpl / (double)tot_pin_src : 0.0));
    line(fmt::format("      of which CREATED by the pre-subdivision (pin INHERITED from two pinned "
                     "parents, MeshSubdivide.cpp:271): {}",
                     tot_pin_unexpl_subdiv));
    line(fmt::format("      TRULY unexplained (an ORIGINAL vertex, none of the four reasons): {}",
                     tot_pin_unexpl - tot_pin_unexpl_subdiv));
    line("   (the four are not mutually exclusive, so the four counts may sum past PINNED SOURCE VERTS)");
    if (pin_unexplained_samples.empty()) {
      line("   no unexplained pin exists in this level.");
    } else {
      line(fmt::format("   the first {} UNEXPLAINED pinned vertices, in METRES:",
                       pin_unexplained_samples.size()));
      line(fmt::format("      {:>10} {:>10} {:>10}  {:>9} {:>8} {:>8}  {:<26} {}", "x", "y", "z",
                       "group", "members", "subdiv?", "material", "named-case"));
      for (const auto& ps : pin_unexplained_samples) {
        const auto& m = meshes[ps.mesh];
        line(fmt::format("      {:>10.3f} {:>10.3f} {:>10.3f}  {:>9} {:>8} {:>8}  {:<26} {}",
                         ps.p_m.x, ps.p_m.y, ps.p_m.z, ps.group, ps.members,
                         ps.subdiv_new ? "SUBDIV" : "orig", m.mat,
                         m.named.empty() ? "-" : m.named));
      }
    }
  }
  {
    u64 agree = 0, dis = 0, silent = 0, notruth = 0;
    for (u32 s : shell_order) {
      const char* v = coll_vs_truth(shells[s]);
      if (!std::strcmp(v, "agree")) {
        agree++;
      } else if (!std::strcmp(v, "DISAGREE")) {
        dis++;
      } else if (!std::strcmp(v, "silent")) {
        silent++;
      } else {
        notruth++;
      }
    }
    line(fmt::format("collision vs truth (shells) : agree={} DISAGREE={} silent={} no-truth={}",
                     agree, dis, silent, notruth));
    u64 bagree = 0, bdis = 0, bsilent = 0, bnotruth = 0;
    for (u32 s : shell_order) {
      const char* v = baked_vs_truth(shells[s]);
      if (!std::strcmp(v, "agree")) {
        bagree++;
      } else if (!std::strcmp(v, "DISAGREE")) {
        bdis++;
      } else if (!std::strcmp(v, "silent")) {
        bsilent++;
      } else {
        bnotruth++;
      }
    }
    line(fmt::format("baked normals vs truth      : agree={} DISAGREE={} silent={} no-truth={}",
                     bagree, bdis, bsilent, bnotruth));
  }

  // ---- F) DISTANCE SWEEP ----------------------------------------------------------------------
  if (sweep) {
    line("");
    line(std::string(100, '='));
    line("### F) DISTANCE SWEEP (aggregate A and B at each inspection distance)");
    line("");
    line(fmt::format("{:>8} {:>12} {:>14} {:>12} {:>12} {:>12} {:>12} {:>12}", "d (m)", "gverts",
                     "with_sign", "A_sign%", "B_live%", "B_disp%", "B_patch%", "A_lit%"));
    line(std::string(100, '-'));
    const double ds[] = {2, 3, 5, 10, 20, 30, 40, 50, 60};
    for (double d : ds) {
      const Agg a = evaluate(d, false);
      line(fmt::format("{:>8.1f} {:>12} {:>14} {:>12} {:>12} {:>12} {:>12} {:>12}", d, a.gverts,
                       a.sign_den,
                       a.sign_den ? fmt::format("{:.4f}", 100.0 * (double)a.sign_ok / (double)a.sign_den)
                                  : std::string("n/a"),
                       fmt::format("{:.4f}",
                                   a.gverts ? 100.0 * (double)a.live / (double)a.gverts : 0.0),
                       fmt::format("{:.4f}",
                                   a.gverts ? 100.0 * (double)a.disp_nz / (double)a.gverts : 0.0),
                       fmt::format("{:.4f}", a.patches ? 100.0 * (double)a.patches_live /
                                                             (double)a.patches
                                                       : 0.0),
                       a.sign_den ? fmt::format("{:.4f}",
                                                100.0 * (double)a.sign_ok_lit / (double)a.sign_den)
                                  : std::string("n/a")));
      fmt::print("[tess_sign] sweep d={} done\n", d);
    }
    // The stored per-mesh columns must describe --dist-m, so restore them after the sweep.
    evaluate(dist_m, true);
  }

  // ---- write ----------------------------------------------------------------------------------
  {
    std::ofstream f(out_path, std::ios::out | std::ios::trunc);
    if (!f) {
      fmt::print("error: cannot open --out '{}'\n", out_path);
      return 1;
    }
    f << r;
    f.flush();
    if (!f) {
      fmt::print("error: failed writing '{}'\n", out_path);
      return 1;
    }
  }
  {
    std::ofstream c(csv_path, std::ios::out | std::ios::trunc);
    if (!c) {
      fmt::print("error: cannot open --csv '{}'\n", csv_path);
      return 1;
    }
    c << "row,shell,system,material,tex_id,named_case,A_sign_pct,A_lit_pct,B_live_pct,B_disp_pct,"
         "B_patch_pct,B_req_pct,sign_ok,sign_ok_lit,sign_den,"
         "gverts,live,disp_nz,exempt,patches_live,faces_total,faces_sampled,capped,"
         "mean_inner_level,spacing_actual_m,"
         "verts_per_checker_square,disp_mean_cm,disp_max_cm,uv_per_m,uv_per_m_measured,z_seam,"
         "z_falloff,z_h_mid,z_amp,z_not_tess,z_patch_dead,"
         "f_rayf,f_vol,f_esc,f_undecided,v_rayf,v_vol,v_esc,v_undecided,"
         "pin_src,pin_material,pin_system,pin_open,pin_crease,pin_unexplained,"
         "pin_unexplained_subdiv,shell_tier,shell_gsign,shell_vol_sign,shell_v6_over_l3,"
         "winding_conflicts,rayf_voted,rayf_agree,rayf_disagree,rayf_vs_vol,"
         "esc_ratio,coll_speaks,coll_sign,coll_vs_truth,"
         "baked_sign,baked_vs_truth,centroid_x_m,centroid_y_m,centroid_z_m,aabb_lo_x_m,aabb_lo_y_m,"
         "aabb_lo_z_m,aabb_hi_x_m,aabb_hi_y_m,aabb_hi_z_m,inspection_distance_m\n";
    u32 row = 0;
    for (u32 mi : order) {
      const auto& m = meshes[mi];
      const Shell& sh = shells[m.shell];
      std::string s;
      s += fmt::format("{},{},{},{},{},{},", row++, m.shell, kSysName[m.system], m.mat, m.tex,
                       m.named.empty() ? "-" : m.named);
      s += fmt::format("{},{},", m.a_pct() < 0 ? std::string("") : fmt::format("{:.6f}", m.a_pct()),
                       m.a_lit_pct() < 0 ? std::string("")
                                         : fmt::format("{:.6f}", m.a_lit_pct()));
      s += fmt::format("{:.6f},{:.6f},{:.6f},{},", m.b_live_pct(), m.b_pct(), m.b_patch_pct(),
                       m.b_req_pct() < 0 ? std::string("")
                                         : fmt::format("{:.6f}", m.b_req_pct()));
      s += fmt::format("{},{},{},", m.sign_ok, m.sign_ok_lit, m.sign_den);
      s += fmt::format("{},{},{},{},{},", m.gverts, m.live, m.disp_nz, m.exempt(), m.patches_live);
      s += fmt::format("{},{},{},", m.faces.size(), m.faces_sampled, m.capped ? 1 : 0);
      s += fmt::format("{:.6f},{:.6f},{:.6f},{:.6f},{:.6f},{:.6f},{},", m.mean_inner(),
                       m.spacing_actual_m(), m.verts_per_square(), m.disp_mean_cm(), m.disp_max_cm,
                       m.upm, m.upm_measured ? 1 : 0);
      s += fmt::format("{},{},{},{},{},{},", m.z_seam, m.z_falloff, m.z_h_mid, m.z_amp,
                       m.z_not_tess, m.z_patch_dead);
      s += fmt::format("{},{},{},{},{},{},{},{},", m.f_rayf, m.f_vol, m.f_esc, m.f_und, m.v_rayf,
                       m.v_vol, m.v_esc, m.v_und);
      s += fmt::format("{},{},{},{},{},{},{},", m.pin_src, m.pin_material, m.pin_system, m.pin_open,
                       m.pin_crease, m.pin_unexplained, m.pin_unexplained_subdiv);
      s += fmt::format("{},{},{},{:.6g},{},", sh.tier, sh.gsign, sh.vol_sign, sh.v6_over_l3,
                       sh.winding_conflicts);
      s += fmt::format("{},{},{},{},", sh.rayf_voted, sh.rayf_agree, sh.rayf_disagree,
                       rayf_vs_vol(sh));
      s += fmt::format("{:.6f},{},{},{},{},{},", sh.esc_ratio, sh.coll_speaks ? 1 : 0, sh.coll_sign,
                       coll_vs_truth(sh), sh.baked_sign, baked_vs_truth(sh));
      s += fmt::format("{:.4f},{:.4f},{:.4f},{:.4f},{:.4f},{:.4f},{:.4f},{:.4f},{:.4f},{:.4f}\n",
                       m.centroid.x, m.centroid.y, m.centroid.z, m.aabb_lo.x, m.aabb_lo.y,
                       m.aabb_lo.z, m.aabb_hi.x, m.aabb_hi.y, m.aabb_hi.z, dist_m);
      c << s;
    }
    c.flush();
    if (!c) {
      fmt::print("error: failed writing '{}'\n", csv_path);
      return 1;
    }
  }
  fmt::print("[tess_sign] report -> {}\n[tess_sign] csv    -> {}\n", out_path, csv_path);
  return 0;
}
