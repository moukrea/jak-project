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
// "Outward" is decided PER FACE by the SAME cascade common/custom_data/MeshConsolidate.cpp runs —
// VOLX (exact signed volume on a CLOSED shell) -> RAYF (the per-face escape-ray vote, "lancer de
// rayon sortant": the visible side of a surface is the side with open space on it) -> COLL (the
// competence-filtered collision verdict) -> ESC (shell escape asymmetry) -> UNDECIDED, ungraded.
// An instrument whose notion of outward is not the pipeline's own measures the gap between the two
// instruments instead of the defect, which is what the previous revision (a per-shell signed volume
// deciding on OPEN shells, plus a RAYF-vs-VOL conflict exclusion) was doing on ~40% of faces.
//
// A second sign metric, A_cons, needs NO outward authority at all: it asks only whether the three
// stored corner normals of a face agree with that face about which side is out. It is what
// separates a vertex-normal defect from a disagreement between outward authorities.
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
#include "common/custom_data/MeshOrient.h"
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
      "                 [--max-verts-per-mesh N] [--rayf-k N] [--summary-only]\n"
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
      "  --max-verts-per-mesh N  generated-vertex sampling cap per mesh (default 200000)\n"
      "  --summary-only    write ONLY the header/legend, section D and section E (the totals). The\n"
      "                    giant per-row tables (A, A2, C), the per-mesh rows of B and the CSV are\n"
      "                    skipped: a 26-level sweep writes ~1 GB of tables otherwise. Every number\n"
      "                    is measured exactly as without the flag; only the printing is reduced.\n");
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
// THE OUTWARD AUTHORITY NO LONGER LIVES HERE. It was MOVED to common/custom_data/MeshOrient.{h,cpp}
// and this tool now CALLS it (mesh_orient_faces), which is the whole point: the pipeline
// (MeshConsolidate.cpp pass 11) and this grader used to each decide "outward" independently and
// disagreed on ~25% of vertices, so the instrument measured the gap between the two instruments
// instead of the defect. The constants below are ALIASES of the shared ones — the legend prints
// them, and aliasing rather than re-declaring means a threshold can never drift between the tool's
// documentation and the code that ran.
constexpr double kEscMargin = tfrag3::kOrientEscMargin;    // TIER ESC needs the winner 25% ahead
constexpr double kEscMaxM = tfrag3::kOrientEscMaxM;        // TIER ESC free-distance cap
// ROUND 29's collision competence filter (MeshConsolidate.cpp:1415 / :1420).
constexpr double kCollParallelMin = tfrag3::kOrientCollParallelMin;
constexpr double kCollConfMin = tfrag3::kOrientCollConfMin;

// ---- TIER RAYF: the PER-FACE outward ray test, the PRIMARY ground truth (§5a) ----
// It needs no propagation and no global orientation whatsoever: each face decides alone, from the
// open space on its two sides. Every number here is a compile-time constant, every direction is a
// pure function of the face's own geometric normal, and there is NO RNG, no clock and no
// address-dependent ordering anywhere, so the verdict is bit-reproducible run to run and independent
// of the thread count.
constexpr double kRayfProbeM = tfrag3::kOrientRayfProbeM;  // probe offset either side, metres
constexpr double kRayfMaxM = tfrag3::kOrientRayfMaxM;      // no hit within this => the ray ESCAPED
constexpr double kRayfTMinM = tfrag3::kOrientRayfTMinM;    // hits closer than this are ignored
constexpr int kRayfKDefault = tfrag3::kOrientRayfKDefault;  // rays per hemisphere
constexpr int kRayfMinMargin = tfrag3::kOrientRayfMinMargin;  // below this margin the face abstains

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

// ---- THE OUTWARD-AUTHORITY MACHINERY MOVED OUT --------------------------------------------------
// The exact-float-triple weld grouping, the edge table and shells, the relative-winding BFS, the
// signed volume, the BVH and both ray tiers, the collision verdict and the five-step cascade all
// used to be written out here. They now live in common/custom_data/MeshOrient.{h,cpp} and this tool
// calls mesh_orient_faces() for every one of them. Nothing was re-derived on the way: the pipeline
// and this grader run the SAME code, so a number this tool prints is a number the bake acted on.
// The exact-float-triple key itself is tfrag3::mesh_pos_key — §4b's shrub membership test needs the
// same notion of "same position" the weld grouping used, and there is only one of it now.

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
  // ---- IS THE SHELL A CLOSED SURFACE? ----
  // CLOSED iff every one of the shell's edges (undirected weld-group pair) is used by EXACTLY TWO of
  // its faces. This is the precondition under which the divergence theorem — hence the signed-volume
  // criterion — is EXACT rather than an approximation about an arbitrary origin.
  bool closed = false;
  u32 open_edges = 0;              // edges used by a number of faces other than exactly two
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
  // ---- THE A_sign EXCLUSION (§3b v_nonorient), round 33. The SAME exclusion A_cons has carried since
  // it was introduced, and for the same reason: a generated vertex sitting on a face at least one
  // corner of which is NON-ORIENTABLE has NO representable per-vertex normal that could be correctly
  // signed for every face incident to that corner, so grading it is grading an IMPOSSIBILITY. Left in,
  // it makes A_sign unable to reach 100% however good the pipeline gets — the score would be bounded
  // by a property of the AUTHORED GEOMETRY that no bake can touch — and the gate would be measuring
  // the level's fold-backs instead of the pass's work. Counted over EXACTLY the population that would
  // otherwise have entered sign_den (amp > 0, h != 0.5, an outward verdict), so
  // sign_den + sign_excl_nonorient is A_sign's denominator as it stood BEFORE the exclusion and
  // nothing is hidden by it. That pre-exclusion sum is also, deliberately, A_lit's denominator below.
  u64 sign_excl_nonorient = 0;
  // ---- A_cons — THE FACE-LOCAL CONSISTENCY INVARIANT, which needs NO outward authority at all.
  // Every corner normal of a face must agree with that face about which side is out:
  //     fcons(f) = sign(dot(n_geom(f), N_a + N_b + N_c))          (0 => the face is skipped)
  //     the generated vertex is CORRECT iff dot(N_interp, n_geom(f) * fcons(f)) > 0 .
  // Its denominator is A_sign's EXCEPT that an outward verdict is NOT required, so a face on an
  // UNDECIDED shell still contributes: self-consistency is a property of the face alone. It
  // isolates the vertex-normal CLUSTERING defect from a disagreement between outward authorities.
  u64 a_cons_ok = 0, a_cons_den = 0;
  // ---- THE A_cons EXCLUSION (§3b v_nonorient): generated vertices sitting on a face at least one
  // corner of which is NON-ORIENTABLE — no unit vector at all has a strictly positive dot product
  // with the outward direction of every face incident to that corner, so NO per-vertex normal, right
  // or wrong, could give all of them a correctly-signed displacement. The per-vertex format cannot
  // express a right answer there, so the vertex is REMOVED from cons_den rather than scored wrong.
  // Counted over EXACTLY the population that would otherwise have entered cons_den (amp > 0,
  // h != 0.5, fcons != 0), so a_cons_den + cons_excl_nonorient is the denominator as it was before.
  u64 cons_excl_nonorient = 0;
  // ---- THE PARALLAX (POM) TIER's sign, per FACE CORNER. Distance-INDEPENDENT: it reads only the
  // face's UV parameterisation and the vertex tangent frame the fragment shader rebuilds. See the
  // block comment above grade_parallax_row() for why this is a TANGENT question, not a normal one.
  u64 p_den = 0;           // gradeable face corners (real UV frame AND a usable vertex tangent)
  u64 p_ok = 0;            // ... of those, corners whose (T,B) maps UV to world in the + sense
  u64 p_u_wrong = 0;       // dot(T, dP/du) <= 0                      -> parallax wrong in U
  u64 p_w_wrong = 0;       // dot(T,dP/du) > 0 but dot(B, dP/dv) <= 0 -> the HANDEDNESS (.w) defect
  u64 p_tan_fallback = 0;  // dot(t,t) <= 0.04: the shader abandons the vertex tangent (no UV info)
  u64 p_tan_degen = 0;     // the Gram-Schmidt tangent collapsed onto the normal
  u64 p_no_normal = 0;     // the corner has no usable stored normal
  // the corner's vertex is in §3b's v_nontan set: its incident faces disagree about UV HANDEDNESS, so
  // ONE per-vertex tangent (T plus a single sign w) cannot serve them all and NO tangent the format
  // can carry is right there. Tested BEFORE the three buckets above, deliberately: it is a property
  // of the AUTHORED UV LAYOUT and not of anything the bake wrote, so it is the CAUSE and the stored
  // tangent's state is the symptom. Not gradeable, never scored as correct.
  u64 p_nonrep = 0;
  u64 p_degen = 0;         // FACES whose UV mapping is degenerate (|det| <= 1e-12): no sign at all
  u64 disp_nz = 0;
  u64 live = 0;             // generated verts with amp > 0            -> B_live%
  u64 patches_live = 0;     // patches with >= 1 vertex at amp > 0     -> B_patch%
  u64 z_seam = 0, z_falloff = 0, z_h_mid = 0, z_amp = 0, z_not_tess = 0;
  // the STRUCTURALLY EXEMPT **AND NOT LIVE** generated vertices — the denominator correction B_req
  // needs. z_seam / z_not_tess are the RAW cause counters and are NOT a subset of the not-live
  // population (a seam-pinned vertex is not live, but a TIE vertex generally IS), which is exactly
  // why `live / (gverts - z_*)` used to print an impossible 100.4052%.
  u64 exempt_dead = 0;
  u64 z_patch_dead = 0;     // verts of a patch with NO live vertex at all
  // ---- B_perm's denominator: the PERMITTED generated vertices. A vertex is PERMITTED when at least
  // one of the patch corners contributing a non-zero barycentric weight sits in a weld group a pin is
  // NOT GEOMETRICALLY NECESSARY for (grp_pin_needed, §4b). The whole point of this pair is that it is
  // computed from TOPOLOGY — texture ids, systems, open edges, incident-face angles — and NEVER from
  // the measured amplitude, which is what makes B_perm falsifiable where B_req is not.
  u64 perm_den = 0;   // PERMITTED generated vertices
  u64 perm_live = 0;  // ... of those, the ones with amp > 0
  // faces / generated vertices decided by each OUTWARD tier
  u64 f_rayf = 0, f_vol = 0, f_esc = 0, f_und = 0;
  u64 v_rayf = 0, v_vol = 0, v_esc = 0, v_und = 0;
  u64 f_volx = 0, f_both = 0;   // VOLX = exact volume on a CLOSED shell
  u64 v_volx = 0, v_both = 0;
  u64 f_coll = 0, v_coll = 0;   // COLL = the competence-filtered collision verdict
  // f_vol / v_vol / f_both / v_both are UNREACHABLE since the cascade revision that deleted the
  // open-shell volume tier and the CONFLICT rule. They are kept, at zero, so the table and the CSV
  // keep their columns; a non-zero value in either is a BUG.
  // the CONFLICT population: faces where RAYF and VOL hand this face OPPOSITE outward directions.
  // Since the cascade revision this is a PUBLISHED DIAGNOSTIC and NOT an exclusion: such a face is
  // graded by RAYF like any other. The count stays because a contradiction between two independent
  // criteria is worth stating out loud.
  u64 f_conflict = 0, v_conflict = 0;
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
  // A_lit% — THE SPEC-LITERAL CONTROL COLUMN, AND IT DOES NOT MOVE. Its denominator is deliberately
  // the PRE-EXCLUSION population (sign_den + sign_excl_nonorient), i.e. every generated vertex with
  // amp > 0, h != 0.5 and an outward verdict — exactly the population it had before A_sign started
  // excluding the NON-ORIENTABLE corners in round 33, and sign_ok_lit is still counted over all of
  // it. A control column that moved when the measured column's denominator moved would stop being a
  // control: the whole point of A_lit is that it is the mandate's own expression, evaluated on the
  // mandate's own population, so that the derivation in the header ("structurally capped near the
  // white-texel share") stays checkable against it.
  double a_lit_pct() const {
    const u64 den_pre = sign_den + sign_excl_nonorient;
    return den_pre ? 100.0 * (double)sign_ok_lit / (double)den_pre : -1.0;
  }
  // A_cons% — the FACE-LOCAL consistency invariant. -1.0 == n/a (no gradeable vertex), same
  // convention as a_pct(). Independent of every outward authority: a mesh can be UNGRADED in
  // A_sign and still be measured here.
  double a_cons_pct() const {
    return a_cons_den ? 100.0 * (double)a_cons_ok / (double)a_cons_den : -1.0;
  }
  // P_sign% — the PARALLAX tier's sign grade. -1.0 == n/a (no gradeable corner at all), the same
  // convention a_pct() uses so pct_or_na() prints "n/a" and the CSV writes an empty cell.
  double p_pct() const { return p_den ? 100.0 * (double)p_ok / (double)p_den : -1.0; }
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
  // This is the RAW cause count, printed in the `exempt` column.
  u64 exempt() const { return system == kSysTie ? z_not_tess : z_seam; }
  // B_req% = live / (generated - exempt_dead). THE ARITHMETIC FIX: the subtrahend must be the
  // vertices that are BOTH structurally exempt AND not live, otherwise the denominator can shrink
  // below the numerator and the percentage exceeds 100 (it printed 100.4052% OVERALL). exempt_dead
  // is a subset of the not-live population by construction, so live <= gverts - exempt_dead and the
  // ratio is bounded by 100% as a matter of arithmetic, not of luck.
  double b_req_pct() const {
    return gverts > exempt_dead ? 100.0 * (double)live / (double)(gverts - exempt_dead) : -1.0;
  }
  // B_perm% = PERMITTED live / PERMITTED generated. THE DENOMINATOR B_req SHOULD HAVE HAD: exempt_dead
  // is derived from the MEASURED amplitude (a vertex is subtracted BECAUSE it came out dead), which
  // makes B_req 100% by construction and therefore worthless as a gate. perm_den is derived from
  // TOPOLOGY ALONE — a corner is excluded only where a pin is GEOMETRICALLY NECESSARY (two referenced
  // members of its weld group would displace differently) — so the measurement can fail against it:
  // if the pipeline pins a group this test says need not be pinned, B_perm drops below 100%.
  // -1.0 == n/a (an EMPTY permitted denominator), the same convention as a_pct().
  double b_perm_pct() const { return perm_den ? 100.0 * (double)perm_live / (double)perm_den : -1.0; }
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
  // OWNER SCOPE ("pars du principe que absolument tous les mesh auront du PBR"): the perimeter is
  // the WHOLE GAME, not the 7 materials that happen to ship a _height.png today. With this flag
  // every texture is treated as displaceable and every mesh is graded against the SYNTHETIC
  // CHECKER, whose height field is known exactly — which is precisely what the debug material is
  // for and what makes total coverage possible now instead of after the art lands.
  bool all_textures = false;
  // --summary-only: emit sections D and E (and the legend) only. The per-mesh and per-shell tables
  // are the whole size of the report — a 26-level sweep writes about a gigabyte of them — and a
  // sweep only ever reads the totals. NOTHING about the measurement changes: every mesh is still
  // evaluated, every counter still accumulated; the flag gates PRINTING only.
  bool summary_only = false;
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
    } else if (a == "--all-textures") {
      all_textures = true;
    } else if (a == "--summary-only") {
      summary_only = true;
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
  fmt::print("[tess_sign] discovered {} displaceable material(s) under {}{}\n", displaceable.size(),
             tex_root_s, all_textures ? "  (--all-textures: EVERY texture graded)" : "");
  // ONE gate, used by every site below, so the whole-game mode cannot be applied in one place and
  // forgotten in another. Still no material name in this file: --all-textures says "all", it does
  // not name anything.
  auto name_is_displaceable = [&](const std::string& n) {
    return all_textures || displaceable.count(n) > 0;
  };
  auto tex_is_displaceable = [&](const tfrag3::Texture& t) {
    return name_is_displaceable(t.debug_name);
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
    // ROUND 32 — the refinement INVENTS vertices after mesh_consolidate's pass 12 / 12c have run,
    // and it interpolates their frames (normal = normalized parent sum, tangent = summed T carrying
    // parent A's handedness verbatim, re-orthogonalised against nothing). Re-establish both
    // invariants on the REFINED mesh. This is the same call pair, in the same order, that
    // Loader.cpp makes after its own subdivision — if it were only here, this grader would be
    // measuring a mesh the device never sees.
    u64 pr_ok = 0, pr_unsat = 0, pr_den = 0;
    const u64 pr_fix = tfrag3::mesh_positivity_repair_level(lev, &pr_ok, &pr_unsat, &pr_den);
    u64 tr_ok = 0, tr_unsat = 0, tr_den = 0;
    const u64 tr_fix =
        tfrag3::retangent_positive_from_final_normals(lev, &tr_ok, &tr_unsat, &tr_den);
    subdiv_note += fmt::format(
        "post-subdivision positivity: normals den={} ok={} repaired={} unsat={} | tangents den={} "
        "ok={} repaired={} unsat={}\n",
        pr_den, pr_ok, pr_fix, pr_unsat, tr_den, tr_ok, tr_fix, tr_unsat);
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
    if (!name_is_displaceable(lev.textures[ti].debug_name)) {
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
  // §4 + §5 WELD GROUPS, SHELLS AND THE OUTWARD AUTHORITY — ONE SHARED IMPLEMENTATION.
  //
  // Everything from here down to the cascade used to be written out in this file: the exact-float-
  // triple weld grouping, the edge table, the shells, the relative-winding BFS, the signed volume,
  // the BVH, TIER RAYF, TIER ESC, the collision verdict and the five-step cascade. It now lives in
  // common/custom_data/MeshOrient.{h,cpp} and the MESH PIPELINE CALLS THE SAME FUNCTION
  // (MeshConsolidate.cpp pass 11). That is the whole point of the extraction: the two used to decide
  // "outward" independently and disagreed on ~25% of vertices, so this instrument was measuring the
  // gap between the two instruments instead of the defect it exists to measure. There is now no gap
  // that CAN exist — a verdict this tool grades against is bit-for-bit the verdict that was baked.
  //
  // Nothing below re-derives a verdict. It only unpacks MeshOrientResult into the shapes the rest of
  // the report already speaks (Face::wg, Shell, ftier, osign), so every number section A/B/C/D/E
  // printed before the extraction is still printed, from the shared authority.
  // ---------------------------------------------------------------------------------------------
  // A MESH FACE is a face drawn with a DISPLACEABLE texture: exactly the population section A grades
  // and exactly the CANDIDATE population handed to the shared authority (TIER RAYF runs over it, and
  // the per-shell tiers only speak for a shell owning one).
  std::vector<u8> face_is_mesh(faces.size(), 0);
  u64 n_mesh_faces = 0;
  for (u32 f = 0; f < faces.size(); f++) {
    if (faces[f].tex >= 0 && (size_t)faces[f].tex < lev.textures.size() &&
        name_is_displaceable(lev.textures[faces[f].tex].debug_name)) {
      face_is_mesh[f] = 1;
      n_mesh_faces++;
    }
  }
  // The shared authority is caller-agnostic on purpose (it must not depend on tfrag3::Level), so the
  // tool hands it flat arrays. These are COPIES of data this tool already holds, bit-identical to it.
  std::vector<math::Vector3f> orient_pos;
  orient_pos.reserve(gv.size());
  for (const auto& v : gv) {
    orient_pos.emplace_back(v.x, v.y, v.z);
  }
  std::vector<std::array<u32, 3>> orient_faces;
  orient_faces.reserve(faces.size());
  for (const auto& f : faces) {
    orient_faces.push_back({f.v[0], f.v[1], f.v[2]});
  }
  // lev.collision is a POINT CLOUD of (position, normal) samples — CollisionMesh has no faces — so
  // that is what the authority is given.
  std::vector<math::Vector3f> orient_coll_pos, orient_coll_nor;
  orient_coll_pos.reserve(lev.collision.vertices.size());
  orient_coll_nor.reserve(lev.collision.vertices.size());
  for (const auto& cv : lev.collision.vertices) {
    orient_coll_pos.emplace_back(cv.x, cv.y, cv.z);
    orient_coll_nor.emplace_back((float)cv.nx, (float)cv.ny, (float)cv.nz);
  }

  // ---- ROUND 33: THE ORIENT INPUT IS THE PIPELINE'S, DOWN TO THE FACE POPULATION -----------------
  // THIS TOOL PASSES NO face_is_candidate, AND THAT IS THE WHOLE POINT. MeshConsolidate.cpp pass 6c
  // (:2459-2468) hands mesh_orient_faces() the level and nothing else: no candidate filter, and the
  // DEFAULT rays_per_hemi. Since round 33 the verdict is decided PER SHELL by a BALLOT of that
  // shell's faces' escape-ray margins (MeshOrient.h:28-32), so the face population is not a
  // presentation detail — it is an INPUT TO THE VERDICT. Narrow it to the displaceable faces here and
  // a shell whose ballot the pipeline resolved with the help of its non-displaceable majority can be
  // resolved the OTHER WAY in this tool, from bit-identical geometry. The grader would then be
  // measuring the gap between two instruments again, which is the exact defect the extraction into
  // common/custom_data/MeshOrient.{h,cpp} exists to make impossible. SAME POPULATION, SAME VERDICT:
  // only then is a number this tool prints a number the bake actually acted on.
  // face_is_mesh above is still computed and still used — it is section A's row population and the
  // `mesh faces (displaceable)` disclosure — it is simply not allowed to narrow the ORIENT input.
  tfrag3::MeshOrientInput oin;
  oin.positions = &orient_pos;
  oin.faces = &orient_faces;
  oin.coll_vertices = &orient_coll_pos;
  oin.coll_normals = &orient_coll_nor;
  oin.units_per_m = (float)kUnitsPerM;
  // --rayf-k is now the ONE remaining knob on this side that can move a shell verdict, and the
  // pipeline always bakes with tfrag3::kOrientRayfKDefault (pass 6c never assigns rays_per_hemi).
  // Turning it is legitimate as a SENSITIVITY STUDY and illegitimate as a GRADE, so say so out loud —
  // on stdout at the call site and on its own physical line of the report — and let no number
  // produced under a non-default K be quoted as the baked pipeline's grade.
  oin.rays_per_hemi = rayf_k;
  std::string rayf_k_warning;
  if (rayf_k != tfrag3::kOrientRayfKDefault) {
    rayf_k_warning = fmt::format(
        "*** WARNING: --rayf-k {} DIFFERS FROM THE PIPELINE'S tfrag3::kOrientRayfKDefault {} — the "
        "RAYF ballot that decides every shell verdict is run here with a ray count MeshConsolidate.cpp "
        "pass 6c never bakes with, so THIS GRADE IS NO LONGER COMPARABLE WITH THE BAKED PIPELINE and "
        "must not be quoted as one; re-run without --rayf-k for a comparable grade ***",
        rayf_k, tfrag3::kOrientRayfKDefault);
    fmt::print("[tess_sign] {}\n", rayf_k_warning);
  }
  const tfrag3::MeshOrientResult orient = tfrag3::mesh_orient_faces(oin);

  // ---- unpack: weld groups ----
  const std::vector<u32>& vert_group = orient.vert_group;
  const u32 n_groups = orient.weld_groups;
  const u64 n_edges = orient.edge_count;
  for (auto& f : faces) {
    for (int e = 0; e < 3; e++) {
      f.wg[e] = vert_group[f.v[e]];
    }
  }
  // ---- unpack: shells ----
  const std::vector<u32>& shell_of = orient.shell_of;
  const u32 n_shells = orient.shell_count;
  std::vector<Shell> shells(n_shells);
  for (u32 f = 0; f < faces.size(); f++) {
    shells[shell_of[f]].faces.push_back(f);
  }
  for (u32 s = 0; s < n_shells; s++) {
    Shell& sh = shells[s];
    sh.gsign = (int)orient.shell_gsign[s];
    sh.tier = tfrag3::mesh_orient_shell_tier_name(orient.shell_tier[s]);
    sh.vol_sign = (int)orient.shell_vol_sign[s];
    sh.v6_over_l3 = orient.shell_v6_over_l3[s];
    sh.winding_conflicts = orient.shell_winding_conflicts[s];
    sh.coll_speaks = orient.shell_coll_speaks[s] != 0;
    sh.coll_sign = (int)orient.shell_coll_sign[s];
    sh.has_displaceable = orient.shell_has_candidate[s] != 0;
    sh.esc_ratio = orient.shell_esc_ratio[s];
    sh.closed = orient.shell_closed[s] != 0;
    sh.open_edges = orient.shell_open_edges[s];
    sh.rayf_voted = orient.shell_rayf_voted[s];
    sh.rayf_agree = orient.shell_rayf_agree[s];
    sh.rayf_disagree = orient.shell_rayf_disagree[s];
  }
  fmt::print("[tess_sign] shells={} weld_groups={} edges={} mesh_faces={}\n", n_shells, n_groups,
             n_edges, n_mesh_faces);
  fmt::print("[tess_sign] BVH built over {} faces ({} nodes) in {:.1f} s\n", faces.size(),
             orient.bvh_nodes, orient.bvh_seconds);

  // ---- unpack: the per-face relative winding, the RAYF vote and its saturation disclosure ----
  const std::vector<s8>& rel = orient.rel;
  const std::vector<s8>& rayf_vote = orient.rayf_vote;
  const double rayf_seconds = orient.rayf_seconds;
  const u64 rayf_sat_blocked = orient.rayf_sat_all_blocked;
  const u64 rayf_sat_open = orient.rayf_sat_all_open;
  const double rayf_mean_plus = orient.rayf_mean_escapes_plus;
  const double rayf_mean_minus = orient.rayf_mean_escapes_minus;
  fmt::print("[tess_sign] tier RAYF done: {} of {} mesh faces voted, K={} per hemisphere, {} "
             "threads, {:.1f} s (mean escapes +{:.2f}/-{:.2f}, saturated all-blocked {} "
             "all-open {})\n",
             orient.rayf_voted, orient.candidate_faces, rayf_k, orient.threads_used, rayf_seconds,
             rayf_mean_plus, rayf_mean_minus, rayf_sat_blocked, rayf_sat_open);
  fmt::print("[tess_sign] tier ESC done\n");

  // ---- geometry helpers the rest of the tool uses (the authority holds its own copy) ----
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

  // ---- the BAKED per-vertex normals: DIAGNOSIS ONLY, and it stays in this tool ------------------
  // sh.baked_sign is the sign of the area-weighted agreement between the shell's rel[]-corrected
  // face normals and the normals actually STORED on its vertices. It is deliberately NOT part of the
  // shared authority: those normals are the very quantity the A_sign grade measures, so letting them
  // define "outward" would make the grade circular. The accumulation is the one the shared
  // collision pass runs (same faces, same area gate), scored against the baked normals instead.
  for (u32 s = 0; s < n_shells; s++) {
    Shell& sh = shells[s];
    if (!sh.has_displaceable) {
      continue;
    }
    double agree_prev = 0;
    for (u32 f : sh.faces) {
      const V3 nraw = face_cross(f) * (double)rel[f];
      const double area = len(nraw);
      if (!(area > 1e-6)) {
        continue;
      }
      const V3 n = nraw * (1.0 / area);
      for (int e = 0; e < 3; e++) {
        const V3& pn = gv[faces[f].v[e]].nor;
        if (len(pn) > 1e-6) {
          agree_prev += area * dot(n, pn);
        }
      }
    }
    sh.baked_sign = std::abs(agree_prev) > 1e-3 ? (agree_prev > 0 ? 1 : -1) : 0;
  }
  fmt::print("[tess_sign] authority diagnosis done (collision is now a DECISION tier below RAYF)\n");

  // ===============================================================================================
  // THE PER-FACE OUTWARD DIRECTION AND ITS TIER, as decided by the shared authority:
  //
  //        VOLX (exact volume on a CLOSED shell)
  //     -> RAYF (the per-face escape-ray vote)
  //     -> COLL (the competence-filtered collision verdict, carried by rel[])
  //     -> ESC  (the shell escape-distance asymmetry, last resort)
  //     -> UNDECIDED (the face is NOT graded)
  //
  // osign[f] is the multiplier on the face's own gn: outward(f) = osign[f] * gn(f).
  //
  // Two tiers this tool used to have are UNREACHABLE by construction and are kept, at zero, only so
  // the tables and the CSV keep their columns: VOL (the open-shell signed volume — origin-dependent,
  // so not a well-defined quantity, let alone a verdict) and BOTH (rays and volume concurring — a
  // label on a verdict RAYF now issues alone). A non-zero count in either is a BUG.
  //
  // The RAYF-vs-VOL CONFLICT is a PUBLISHED DIAGNOSTIC and NOT an exclusion: a face where the two
  // independent criteria pull apart is still graded, by RAYF, exactly as if the volume test had
  // stayed silent. Sending it to UNDECIDED threw away a verdict on the strength of a criterion that
  // has no standing on an open shell.
  // ===============================================================================================
  constexpr u8 kTierRayf = 0, kTierVol = 1, kTierEsc = 2, kTierUnd = 3, kTierVolx = 4,
               kTierBoth = 5, kTierColl = 6;
  const char* kTierName[7] = {"RAYF", "VOL", "ESC", "UNDECIDED", "VOLX", "BOTH", "COLL"};
  const std::vector<s8>& osign = orient.face_sign;
  std::vector<u8> ftier(faces.size(), kTierUnd);
  for (u32 f = 0; f < faces.size(); f++) {
    switch (orient.face_tier[f]) {
      case tfrag3::kOrientVolx:
        ftier[f] = kTierVolx;
        break;
      case tfrag3::kOrientRayf:
        ftier[f] = kTierRayf;
        break;
      case tfrag3::kOrientColl:
        ftier[f] = kTierColl;
        break;
      case tfrag3::kOrientEsc:
        ftier[f] = kTierEsc;
        break;
      default:
        ftier[f] = kTierUnd;
        break;
    }
  }
  const std::vector<u8>& face_conflict = orient.face_rayf_vs_vol_conflict;
  const u64 n_conflict_diag = orient.rayf_vs_vol_conflict_faces;

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
          !name_is_displaceable(lev.textures[tex].debug_name)) {
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

  // ===============================================================================================
  // §3b WHAT THE PER-VERTEX FORMAT CANNOT EXPRESS — TWO IMPOSSIBILITY SETS, FROM GEOMETRY ALONE.
  //
  // Everything in this section is computed from POSITIONS, TEXCOORDS, INDICES and TEXTURE IDS ONLY.
  // Nothing here reads a stored normal, a stored tangent or a stored seam weight, and that
  // independence is the entire point: a set derived from the BAKED data would let the bake manufacture
  // its own exclusion by writing something bad, and the exclusion would stop being a statement about
  // the ORIGINAL geometry. These are statements about the original geometry, which the bake cannot
  // alter and cannot argue with.
  //
  //   v_nonorient[i] : NO REPRESENTABLE normal — none of the 2^30 values three signed 10-bit fields
  //                    can hold — has a dot product above 1e-3 with the outward direction of every
  //                    face incident to vertex i. The format carries ONE normal per vertex and the
  //                    .tese displaces along the interpolation of those normals, so no per-vertex
  //                    normal WHATSOEVER can give every incident face a correctly-signed displacement
  //                    there. Such a vertex is removed from A_cons's AND A_sign's denominator rather
  //                    than scored wrong: the data format cannot express a right answer. The predicate
  //                    is tfrag3::mesh_best_packed_normal(), the function the REPAIR pass itself calls
  //                    (MeshConsolidate.cpp:2791) — see the derivation at the loop below.
  //   v_nontan[i]    : the faces incident to i disagree about UV HANDEDNESS, so one per-vertex tangent
  //                    (T plus a single sign w) cannot serve them all — derivation at the loop below.
  //                    Such a corner is removed from P_sign's denominator, same reasoning.
  // ===============================================================================================
  // ---- the per-face UNIT ORIENTED normal ------------------------------------------------------
  // n_f = normalize(cross(p1-p0, p2-p0) * rel[f]) — the expression §4b's pin-flag block (:2038-2088)
  // uses for a group's incident normals. rel[] is the shared authority's relative winding
  // (orient.rel): it makes the incident normals of one shell mutually comparable WITHOUT deciding
  // which side is out, which is all a SIMULTANEOUS-SATISFIABILITY question needs — that question is
  // invariant under a global flip of the whole shell. A face whose cross product is shorter than
  // 1e-12 states no direction: it is stored as exactly zero and skipped by every consumer below.
  // NOTE, since round 33: v_nonorient below does NOT read this array. It builds its constraint set
  // from osign[f] (the shell VERDICT, not the relative winding) because that is the set
  // MeshConsolidate.cpp pass 12 repairs against (:2755, face_normal(f) * fsign[f]), and the two must
  // ask one question. face_nu keeps rel[] because the pin block's crease clustering is an ANGLE test
  // between two incident faces, which no global flip can change.
  std::vector<V3> face_nu(faces.size(), V3{0.0, 0.0, 0.0});
  u64 n_face_no_dir = 0;
  for (u32 f = 0; f < faces.size(); f++) {
    const V3 nr = face_cross(f) * (rel[f] != 0 ? (double)rel[f] : 1.0);
    const double l = len(nr);
    if (l > 1e-12) {
      face_nu[f] = nr * (1.0 / l);
    } else {
      n_face_no_dir++;
    }
  }
  // ---- face_ou: the same unit normals oriented by the VERDICT (osign), not by the relative winding.
  // The crease clause of grp_pin_needed is an angle test and is happy with face_nu, but the
  // REPRESENTABILITY clause is not: "does one direction serve all of these" is invariant under
  // flipping the WHOLE set and is NOT invariant under flipping some of it, and rel[] is only defined
  // up to a per-shell constant. A weld group whose incident faces sit in two different shells — two
  // shells can share a vertex without sharing an edge, so this is a real population, not a corner
  // case — would be handed a constraint set differing from the pipeline's by a partial flip, and the
  // two would answer differently on exactly the groups the guarantee depends on.
  // MeshConsolidate pass 12d builds its set from ores.face_sign (:2891-2905, the same field this
  // array is oriented by) and SKIPS any group touching a face the cascade left UNDECIDED, precisely
  // because this tool cannot see what pass 6's flood fill would have answered there. The matching
  // skip is in the pin block below.
  std::vector<V3> face_ou(faces.size(), V3{0.0, 0.0, 0.0});
  for (u32 f = 0; f < faces.size(); f++) {
    if (osign[f] == 0) {
      continue;  // the cascade abstained: no verdict-oriented direction exists for this face
    }
    const V3 nr = face_cross(f) * (double)osign[f];
    const double l = len(nr);
    if (l > 1e-12) {
      face_ou[f] = nr * (1.0 / l);
    }
  }
  // ---- the per-face UV HANDEDNESS, from the TEXCOORDS alone ------------------------------------
  // det = du1*dv2 - du2*dv1, exactly as grade_parallax_row() computes it below and as
  // TFrag3Data.cpp:2028-2043 computes it when it BUILDS the tangents. 0 here = degenerate
  // (|det| <= 1e-12): the face defines no UV frame at all, the very triangles TFrag3Data.cpp:2036
  // skips, and it takes no part in the handedness test.
  std::vector<s8> face_uv_sign(faces.size(), 0);
  u64 n_face_uv_degen = 0;
  for (u32 f = 0; f < faces.size(); f++) {
    const u32* c = faces[f].v;
    const double du1 = (double)gv[c[1]].s - (double)gv[c[0]].s;
    const double dv1 = (double)gv[c[1]].t - (double)gv[c[0]].t;
    const double du2 = (double)gv[c[2]].s - (double)gv[c[0]].s;
    const double dv2 = (double)gv[c[2]].t - (double)gv[c[0]].t;
    const double det = du1 * dv2 - du2 * dv1;
    if (std::abs(det) > 1e-12) {
      face_uv_sign[f] = det > 0.0 ? (s8)1 : (s8)-1;
    } else {
      n_face_uv_degen++;
    }
  }
  // ---- CSR vertex -> incident faces, ascending face index (determinism) ------------------------
  std::vector<u32> vfoff(gv.size() + 1, 0);
  for (const auto& fc : faces) {
    for (int e = 0; e < 3; e++) {
      vfoff[fc.v[e] + 1]++;
    }
  }
  for (size_t i = 0; i < gv.size(); i++) {
    vfoff[i + 1] += vfoff[i];
  }
  std::vector<u32> vfflat(vfoff[gv.size()]);
  {
    std::vector<u32> cur(vfoff.begin(), vfoff.end() - 1);
    for (u32 f = 0; f < faces.size(); f++) {
      for (int e = 0; e < 3; e++) {
        vfflat[cur[faces[f].v[e]]++] = f;
      }
    }
  }
  // ---- v_nonorient: does a REPRESENTABLE normal exist that serves every incident face? ----------
  // THE DECISION IS NO LONGER MADE HERE. It is tfrag3::mesh_best_packed_normal(outs, 1e-3f, nullptr)
  // (declared MeshOrient.h:156-162, implemented MeshOrient.cpp:71-200), and MeshConsolidate.cpp
  // pass 12 calls THE SAME FUNCTION with the SAME 1e-3 tolerance (:2791, kPosEps at :2651) when it
  // REPAIRS a vertex — as does pass 12d for a whole weld group (:2913).
  //
  // WHY THAT MATTERS MORE THAN IT LOOKS. This test used to re-implement a Badoiu-Clarkson Chebyshev
  // iteration in double, over UNIT VECTORS IN R^3. The pass's question is not that question: the
  // .tese displaces along the STORED normal, which is three signed 10-bit fields, so what the pass can
  // deliver is one of 2^30 REPRESENTABLE directions, not an arbitrary unit vector. A float-only test
  // therefore calls a vertex FIXABLE that the pass provably cannot fix (the cone is real but narrower
  // than the quantisation step), and that vertex then stays in the graded denominator and fails
  // forever, with no explanation available anywhere in the report. The pipeline's repair pass and this
  // exclusion now ask the IDENTICAL QUESTION THROUGH THE IDENTICAL FUNCTION, so a vertex cannot be
  // "fixable in the grader's opinion but unrepairable in the pass's" — the two verdicts are the same
  // bytes out of the same code.
  // The function canonicalises its input (MeshOrient.cpp:75-106: pack, sort, unique), so it is a pure
  // function of the SET of incident directions and this loop's iteration order cannot move it.
  constexpr float kNonOrientEps = 1e-3f;  // == MeshConsolidate.cpp:2651 kPosEps, pass 12
  std::vector<u8> v_nonorient(gv.size(), 0);
  u64 n_nonorient = 0, n_nonorient_fold = 0, n_nonorient_cancel = 0;
  {
    const auto t0 = std::chrono::steady_clock::now();
    std::vector<math::Vector3f> outs;
    for (u32 i = 0; i < (u32)gv.size(); i++) {
      outs.clear();
      for (u32 k = vfoff[i]; k < vfoff[i + 1]; k++) {
        const u32 f = vfflat[k];
        // outward(f) = osign[f] * cross(p1-p0, p2-p0), normalized — the SAME per-face outward the
        // sign classification grades against (§9, :2295-2299) and the same constraint set pass 12
        // builds (MeshConsolidate.cpp:2753-2760, face_normal(f) * fsign[f], normalized). Two kinds of
        // face state NO direction and are skipped by the one length test: a DEGENERATE face (cross
        // product under the epsilon) and an UNDECIDED face (osign == 0, every tier abstained), whose
        // product is exactly the zero vector. Neither constrains anything, so neither may make a
        // vertex look impossible.
        const V3 nr = face_cross(f) * (double)osign[f];
        const double l = len(nr);
        if (l > 1e-12) {
          const V3 u = nr * (1.0 / l);
          outs.emplace_back((float)u.x, (float)u.y, (float)u.z);
        }
      }
      if (outs.empty()) {
        continue;  // no incident direction at all: nothing to satisfy, and nothing to exclude
      }
      if (tfrag3::mesh_best_packed_normal(outs, kNonOrientEps, nullptr)) {
        continue;  // a REPRESENTABLE normal serves every incident face: the format can be right here
      }
      v_nonorient[i] = 1;
      n_nonorient++;
      // THE GEOMETRIC CHARACTER of the residual, so that it is a named shape and not a bare number.
      // Both sub-counts are DIRECT tests on the constraint set — neither ever depended on the
      // iteration that used to live here, and neither decides anything: the verdict above is already
      // final. They are not exclusive and do not partition the failing set, exactly as before.
      //   EXACT-CANCEL: the incident outwards sum to (near) nothing, so there is no mean to start
      //   from and no Chebyshev centre exists — the same degenerate exit the shared function takes at
      //   MeshOrient.cpp:127-129.
      math::Vector3f acc(0.f, 0.f, 0.f);
      for (const auto& u : outs) {
        acc += u;
      }
      if (!(acc.length() > 1e-6f)) {
        n_nonorient_cancel++;
      }
      //   FOLD-BACK / FIN: two incident faces whose outward directions have a NEGATIVE dot product.
      //   The surface doubles back on itself through that vertex, and no single direction can be on
      //   the outward side of both sheets at once.
      bool fold = false;
      for (size_t a = 0; a + 1 < outs.size() && !fold; a++) {
        for (size_t b = a + 1; b < outs.size(); b++) {
          if (outs[a].dot(outs[b]) < 0.f) {
            fold = true;
            break;
          }
        }
      }
      n_nonorient_fold += fold ? 1 : 0;
    }
    fmt::print("[tess_sign] NON-ORIENTABLE vertices: {} of {} ({} fold-back/fin, {} exact-cancel), "
               "{} faces with no direction, {:.1f} s\n",
               n_nonorient, gv.size(), n_nonorient_fold, n_nonorient_cancel, n_face_no_dir,
               std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count());
  }
  // ---- v_nontan: do the incident faces agree about UV HANDEDNESS? ------------------------------
  // WHY ONE TANGENT CANNOT SERVE TWO HANDEDNESSES. The fragment shader rebuilds the UV frame as
  //     T = normalize(t.xyz - N*dot(N, t.xyz)) ;   B = cross(N, T) * (t.w < 0 ? -1 : +1)
  // and it is correct on a face iff dot(T, dP/du) > 0 AND dot(B, dP/dv) > 0. On a face whose UV det is
  // POSITIVE (right-handed) cross(N, dP/du) points along +dP/dv, so the B constraint on the tangent
  // angle COINCIDES with the T constraint — one tangent satisfies both. On a face whose det is NEGATIVE
  // the two are ANTIPODAL: cross(N,T) points along -dP/dv, and only w < 0 recovers it. But w is ONE
  // sign per VERTEX: it selects which handedness that vertex serves. A vertex whose incident faces MIX
  // handedness therefore has no representable frame — whichever w ships, every incident face of the
  // other handedness is wrong, and no bake, however careful, can fix it. This is a property of the
  // ORIGINAL AUTHORED UV LAYOUT, read here from the texcoords and the indices alone.
  std::vector<u8> v_nontan(gv.size(), 0);
  u64 n_nontan = 0;
  for (u32 i = 0; i < (u32)gv.size(); i++) {
    s8 first = 0;
    for (u32 k = vfoff[i]; k < vfoff[i + 1]; k++) {
      const s8 sg = face_uv_sign[vfflat[k]];
      if (sg == 0) {
        continue;  // that face has no UV frame at all: it states no handedness
      }
      if (first == 0) {
        first = sg;
      } else if (sg != first) {
        v_nontan[i] = 1;
        n_nontan++;
        break;
      }
    }
  }
  fmt::print("[tess_sign] NON-REPRESENTABLE-TANGENT vertices: {} of {} (incident faces mix UV "
             "handedness), {} UV-degenerate faces\n",
             n_nontan, gv.size(), n_face_uv_degen);

  // ===============================================================================================
  // §4a THE PARALLAX (POM) TIER'S SIGN — P_sign%.
  //
  // WHY THIS IS A TANGENT-FRAME QUESTION AND NOT A NORMAL QUESTION.
  // The tessellation tier displaces along the surface NORMAL, so A_sign% is entirely a question of
  // which way N points. The parallax tier never moves a vertex: it moves the TEXTURE COORDINATE,
  // and a UV offset can only be built in the frame the UVs themselves define. The fragment shader
  // (pbr_fused.glsl:12-29) rebuilds that frame per fragment from the interpolated per-vertex
  // tangent:
  //     T = normalize(v_tangent.xyz - N * dot(N, v_tangent.xyz));       // Gram-Schmidt against N
  //     B = cross(N, T) * (v_tangent.w < 0.0 ? -1.0 : 1.0);             // .w = HANDEDNESS
  // then marches (pbr_fused.glsl:172-173 and :264-292):
  //     Vt = normalize(vec3(dot(Vv,T), dot(Vv,B), max(dot(Vv,N), 0.0)));
  //     P  = (Vt.xy / max(Vt.z, 0.20)) * depth_uv * ... ;  and the loop does `uv -= duv_step`,
  // i.e. a NET UV offset of -(Vt.xy / Vt.z) * depth * frac — the standard parallax formula, which
  // walks the ray BACK into the height field (pom_carve(), pbr_helpers.glsl:202-208, makes h the
  // depth BELOW the polygon, so the correct march is backwards along the view ray).
  // That produces correct relief IF AND ONLY IF the basis actually maps UV to world in the POSITIVE
  // sense: T along +dP/du and B along +dP/dv. If it does not, the march walks the height field the
  // wrong way and the relief inverts or shears.
  //
  // The two halves fail INDEPENDENTLY, which is exactly why this needs its own column:
  //   * dot(T, dP/du) <= 0  -> the tangent itself is reversed: parallax wrong in U.
  //   * dot(B, dP/dv) <= 0  -> T is right but the stored HANDEDNESS .w is wrong, so cross(N,T) is
  //     flipped: the parallax inverts in V ONLY while the tessellation tier, which reads N alone,
  //     stays perfectly correct. A mesh can therefore be green in A_sign and broken in parallax.
  // .w is produced offline by reconstruct_tfrag_tangents() (common/custom_data/TFrag3Data.cpp:
  // 2015-2131) as sign(dot(cross(N,T), bit_acc)) over the Lengyel per-triangle accumulation, and
  // that function also has three fallback exits (no normal / no UV tangent / Gram-Schmidt kill)
  // which write a Frisvad basis carrying NO UV information at all — the shader mirrors the last of
  // those with its own `dot(v_tangent.xyz, v_tangent.xyz) > 0.04` test. A corner that lands in the
  // fallback has no parallax sign to grade, so it is counted apart and never scored as correct.
  //
  // The test below is therefore per FACE CORNER and reads nothing else: no camera, no tessellation
  // level, no checker, no height scale. It is run once here over the same face population section A
  // grades (m.faces IS the face_is_mesh set, both come from name_is_displaceable), and re-run from
  // evaluate(store=true) — it zeroes its own counters first, so re-running at another --dist-m can
  // neither double-count nor leave a stale value, and it returns the identical numbers every time.
  // ===============================================================================================
  auto grade_parallax_row = [&](MeshRow& m) {
    m.p_den = m.p_ok = m.p_u_wrong = m.p_w_wrong = 0;
    m.p_tan_fallback = m.p_tan_degen = m.p_no_normal = m.p_degen = m.p_nonrep = 0;
    for (u32 f : m.faces) {  // ascending face order => deterministic
      const u32 corner[3] = {faces[f].v[0], faces[f].v[1], faces[f].v[2]};
      // ---- the face's UV->world Jacobian (Lengyel, the same algebra TFrag3Data.cpp:2028-2043
      // uses to BUILD the tangents; positions in GAME UNITS, texcoords in tile units) ----
      const V3 p0 = pos(corner[0]), p1 = pos(corner[1]), p2 = pos(corner[2]);
      const V3 e1 = p1 - p0, e2 = p2 - p0;
      const double du1 = (double)gv[corner[1]].s - (double)gv[corner[0]].s;
      const double dv1 = (double)gv[corner[1]].t - (double)gv[corner[0]].t;
      const double du2 = (double)gv[corner[2]].s - (double)gv[corner[0]].s;
      const double dv2 = (double)gv[corner[2]].t - (double)gv[corner[0]].t;
      const double det = du1 * dv2 - du2 * dv1;
      if (!(std::abs(det) > 1e-12)) {
        // Degenerate UV parameterisation (TFrag3Data.cpp:2036 skips the very same triangles):
        // this face defines no UV direction, so it has NO parallax sign. Never scored as correct.
        m.p_degen++;
        continue;
      }
      const double r = 1.0 / det;
      const V3 dPdu = (e1 * dv2 - e2 * dv1) * r;
      const V3 dPdv = (e1 * (-du2) + e2 * du1) * r;
      for (int e = 0; e < 3; e++) {
        const GVert& v = gv[corner[e]];
        // §3b: the corner's vertex has incident faces of BOTH UV handednesses, so no per-vertex
        // (T, w) the format can carry is right for all of them. Tested FIRST, before anything that
        // reads the stored tangent or normal: this is the CAUSE — a property of the authored UV
        // layout — and whatever the bake then wrote into the tangent is the symptom. Removed from the
        // denominator, never scored correct.
        if (v_nontan[corner[e]]) {
          m.p_nonrep++;
          continue;
        }
        const V3 N = v.nor;  // the STORED smooth normal, scaled by nothing
        if (len(N) < 1e-6) {
          m.p_no_normal++;
          continue;
        }
        const V3 t_raw{(double)v.tx, (double)v.ty, (double)v.tz};
        if (!(dot(t_raw, t_raw) > 0.04)) {
          // pbr_fused.glsl:12-29 exactly: below this threshold the shader drops the vertex tangent
          // and builds a Frisvad/Duff basis from N alone, which carries no UV information => there
          // is nothing to grade here (and nothing this test could call correct).
          m.p_tan_fallback++;
          continue;
        }
        const V3 t_gs = t_raw - N * dot(N, t_raw);  // the shader's Gram-Schmidt
        if (len(t_gs) < 1e-6) {
          m.p_tan_degen++;
          continue;
        }
        const V3 T = normalized(t_gs);
        const V3 B = cross(N, T) * (v.tw < 0.f ? -1.0 : 1.0);  // sign() of .w, as the shader does
        m.p_den++;
        if (!(dot(T, dPdu) > 0.0)) {
          m.p_u_wrong++;
        } else if (!(dot(B, dPdv) > 0.0)) {
          m.p_w_wrong++;  // T is right, the handedness is not
        } else {
          m.p_ok++;
        }
      }
    }
  };
  {
    u64 pok = 0, pden = 0, pdeg = 0, pnr = 0;
    for (auto& m : meshes) {
      grade_parallax_row(m);
      pok += m.p_ok;
      pden += m.p_den;
      pdeg += m.p_degen;
      pnr += m.p_nonrep;
    }
    fmt::print("[tess_sign] parallax sign graded: {}/{} corners correct, {} UV-degenerate faces, "
               "{} corners EXCLUDED as non-representable (mixed UV handedness)\n",
               pok, pden, pdeg, pnr);
  }

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
  // ---- grp_pin_needed[g]: is a pin GEOMETRICALLY NECESSARY on this weld group? -------------------
  // TRUE iff two referenced members of the group would displace DIFFERENTLY, which is the one and only
  // condition the crack-guard pin exists for. Computed from TOPOLOGY ALONE (texture ids, systems, open
  // edges, incident-face angles) and NEVER from a stored normal, a stored seam weight or a measured
  // amplitude, which is what makes it an INDEPENDENT yardstick for the pins that actually shipped —
  // and an UPPER BOUND on what the consolidation pass may legitimately pin. It is B_perm's denominator
  // (see the accessor b_perm_pct() and the header paragraph on B_perm). Filled in the same pass as the
  // four pin-reason flags above, from the same CSR and the same cfg-derived crease threshold.
  std::vector<u8> grp_pin_needed(n_groups, 0);
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
    // The shared authority already walked the edge table and published exactly this flag, so the
    // tool does not build a second edge table that could disagree with the one that oriented the
    // level.
    for (u32 g = 0; g < n_groups; g++) {
      if (orient.group_has_open_edge[g]) {
        grp_open[g] = 1;
      }
    }
    // SHRUB presence, by exact position. Shrub is in mesh_consolidate's weld universe
    // (MeshConsolidate.cpp:345-348) but NOT in this tool's face universe — it is never tessellated
    // and never graded — so without this a tfrag<->shrub junction would look unexplained. The
    // population is the shrub vertices the draws actually reference (:682-698).
    std::unordered_map<tfrag3::MeshPosKey, u8, tfrag3::MeshPosKeyHash> shrub_pos;
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
          shrub_pos.emplace(tfrag3::mesh_pos_key(sv.x, sv.y, sv.z), (u8)1);
          n_shrub_refs++;
        }
      }
    }
    for (u32 g = 0; g < n_groups; g++) {
      if (grp_rep[g] == UINT32_MAX) {
        continue;
      }
      const auto& p = gv[grp_rep[g]];
      if (shrub_pos.count(tfrag3::mesh_pos_key(p.x, p.y, p.z))) {
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
    // the group's incident outward directions, in the shared feasibility function's own type. Hoisted
    // out of the loop and cleared per group: one allocation for the level, not one per weld group.
    std::vector<math::Vector3f> grp_outs;
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
      // ---- ROUND 32: THE PIN RULE IS NO LONGER THE CREASE-CLUSTER PROXY --------------------------
      // mesh_consolidate pass 12b pins a group iff its REFERENCED MEMBERS DO NOT ALL CARRY THE SAME
      // NORMAL — the exact condition under which two coincident vertex indices displace along
      // different axes and the surface tears open. The old test here ("the incident faces fall into
      // two or more crease clusters AND the group has at least two members") reproduced pass 7's
      // clustering, which is only a PROXY for that and over-fires: two members can land in different
      // clusters and still end up carrying the SAME normal, in which case the edge between them
      // cannot tear and needs no pin. Re-derive the rule the pass actually applies, on the same
      // bytes, so PIN_UNEXPLAINED keeps measuring a real disagreement between the pass and this test
      // instead of a difference of definition.
      // Members come from the incident FACE CORNERS, i.e. exactly the REFERENCED ones (pass 12b skips
      // the unreferenced). Normals are compared as unpacked triples: both sides come from one packed
      // u32 through one unpack, so equal packed values compare equal here by construction.
      {
        bool have = false, differ = false;
        V3 first{0.0, 0.0, 0.0};
        for (u32 k = i0; k < i1 && !differ; k++) {
          const u32 f = iflat[k];
          for (int e = 0; e < 3; e++) {
            if (faces[f].wg[e] != g) {
              continue;  // that corner belongs to a different weld group
            }
            const V3& nv = gv[faces[f].v[e]].nor;
            if (!have) {
              first = nv;
              have = true;
            } else if (nv.x != first.x || nv.y != first.y || nv.z != first.z) {
              differ = true;
              break;
            }
          }
        }
        if (differ) {
          grp_crease[g] = 1;  // MeshConsolidate.cpp pass 12b: members differ => the edge would tear
        }
      }
      // ---- grp_pin_needed[g]: IS A PIN GEOMETRICALLY NECESSARY HERE? -----------------------------
      // The pin exists for exactly one reason: two referenced members of a welded position that
      // displace DIFFERENTLY separate, and the surface tears open. So a pin is NECESSARY iff two such
      // members could not displace alike, which is decidable from geometry alone:
      //   * MULTI-TEXTURE  — the group's incident faces carry more than one tree_tex_id, so the two
      //     sides sample a DIFFERENT height map through DIFFERENT per-draw amplitude uniforms and
      //     cannot displace alike whatever their normals are;
      //   * MULTI-SYSTEM   — the incident faces span more than one system, and TIE is never routed
      //     through the tessellation program at all, so one side moves and the other cannot;
      //   * OPEN BOUNDARY  — a welded group edge used by exactly ONE face: there is no other side to
      //     match, so nothing constrains the displacement and the pin is the safe answer. Read from
      //     orient.group_has_open_edge via grp_open, the same source §4b's pinOPEN attribution uses;
      //   * MULTI-CREASE   — the group's referenced members cannot all carry the SAME normal. THIS
      //     CLAUSE IS THE CAUSE OF THE SHIPPED PIN AND NOT THE SHIPPED PIN ITSELF, and it is tested
      //     WITHOUT READING ONE STORED NORMAL: pass 7 assigns a member the normal of the crease
      //     CLUSTER its corner falls in, so two members can only end up with different normals when
      //     the group's incident faces fall in more than one cluster — i.e. iff two incident faces
      //     have dot(n_a, n_b) < crease_cos under pass 7's own rule and threshold. (grp_crease above
      //     reads the stored normals, on purpose, because it audits what the pass DID; this one must
      //     not, because it bounds what the pass MAY do.)
      // The result is an UPPER BOUND on the pins a correct pass may set, computed from geometry alone,
      // and that is exactly what makes B_perm falsifiable in the direction that matters: if the pass
      // pins a group this test says need not be pinned, the pinned vertices stay in B_perm's
      // denominator while contributing nothing to its numerator, and B_perm drops below 100%.
      {
        bool need = grp_material[g] != 0 || grp_system[g] != 0 || grp_open[g] != 0;
        for (u32 ka = i0; ka < i1 && !need; ka++) {
          const V3& na = face_nu[iflat[ka]];
          if (!(dot(na, na) > 0.0)) {
            continue;  // that face states no direction, so it joins no cluster
          }
          for (u32 kb = ka + 1; kb < i1; kb++) {
            const V3& nb = face_nu[iflat[kb]];
            if (!(dot(nb, nb) > 0.0)) {
              continue;
            }
            if (dot(na, nb) < crease_cos) {
              need = true;  // two incident faces cannot share one crease cluster
              break;
            }
          }
        }
        // ---- FIFTH CLAUSE (round 33): CAN ONE STORED NORMAL SERVE THE GROUP AT ALL? ---------------
        // The four clauses above enumerate the reasons the group's members MUST displace differently.
        // There is one further reason a pin survives that none of them can see, and it is not about
        // the geometry disagreeing with itself — it is about the FORMAT. MeshConsolidate pass 12d
        // (:2878-2932) unifies the normal of every group for which the four clauses are FALSE, and
        // then does exactly one more thing: it asks mesh_best_packed_normal() for a value the three
        // signed 10-bit fields can actually hold that serves the union of the group's incident
        // outwards, and where there is none it gives up and counts the group in
        // rep.group_unify_unrepresentable (:2913-2916, :2936). Such a group KEEPS ITS PIN however
        // correct the pipeline is.
        // So the same call belongs here, with the same 1e-3 tolerance: a group the pipeline could not
        // unify is a group this test must not expect to be live, or B_perm would carry a permanently
        // unreachable population and the two sides would drift apart into a passing liveness score
        // that no pass could ever earn. Same function, same question, no drift.
        // The constraint set is face_nu[] over the group's incident faces — already unit, already
        // oriented, and already what the crease loop just above compared. An EMPTY set (every incident
        // face degenerate) makes the shared function return false (MeshOrient.cpp:72-74/107-109) and
        // so lands here as need = true, which is also what pass 12d does with it: uo.empty() takes the
        // `continue` at :2909-2911 and the group is never unified.
        // The UNDECIDED skip, mirroring MeshConsolidate.cpp pass 12d (:2891-2905). A group touching a
        // face the cascade abstained on is one pass 12d refuses to unify, because the orientation it
        // would have to use there is pass 6's flood-fill answer and this tool cannot see it. Both
        // sides therefore declare the pin necessary. That is conservative in the safe direction: it
        // only ever REMOVES vertices from B_perm's denominator, so it can lower the liveness score
        // but can never manufacture a passing one.
        if (!need) {
          for (u32 k = i0; k < i1; k++) {
            if (osign[iflat[k]] == 0) {
              need = true;
              break;
            }
          }
        }
        if (!need) {
          grp_outs.clear();
          for (u32 k = i0; k < i1; k++) {
            const V3& n = face_ou[iflat[k]];
            if (!(dot(n, n) > 0.0)) {
              continue;  // that face states no direction, so it constrains nothing
            }
            grp_outs.emplace_back((float)n.x, (float)n.y, (float)n.z);
          }
          if (!tfrag3::mesh_best_packed_normal(grp_outs, 1e-3f, nullptr)) {
            need = true;  // no representable normal serves the union: pass 12d cannot unify it
          }
        }
        grp_pin_needed[g] = need ? 1 : 0;
      }
    }
    fmt::print("[tess_sign] pin-reason group flags built in {:.1f} s\n",
               std::chrono::duration<double>(std::chrono::steady_clock::now() - t0).count());
    {
      u64 need = 0, with_faces = 0;
      for (u32 g = 0; g < n_groups; g++) {
        if (ioff[g] == ioff[g + 1]) {
          continue;
        }
        with_faces++;
        need += grp_pin_needed[g] ? 1 : 0;
      }
      fmt::print("[tess_sign] pin GEOMETRICALLY NECESSARY on {} of {} groups with incident faces "
                 "({:.2f}%) — B_perm's topology-only denominator\n",
                 need, with_faces, with_faces ? 100.0 * (double)need / (double)with_faces : 0.0);
    }
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
    u64 sign_excl_nonorient = 0;        // A_sign's NON-ORIENTABLE exclusion (§3b), level-wide
    u64 live = 0, patches = 0, patches_live = 0, exempt = 0;
    u64 exempt_dead = 0;  // structurally exempt AND not live — B_req's real subtrahend
    u64 a_cons_ok = 0, a_cons_den = 0;  // the face-local consistency invariant
    u64 cons_excl_nonorient = 0;        // ... and the NON-ORIENTABLE population removed from it
    u64 perm_den = 0, perm_live = 0;    // B_perm: the topology-only PERMITTED denominator
    u64 gverts_tfrag = 0, disp_nz_tfrag = 0, live_tfrag = 0;
    u64 v_rayf = 0, v_vol = 0, v_esc = 0, v_und = 0;
    u64 v_volx = 0, v_both = 0, v_conflict = 0, v_coll = 0;
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
        m.sign_excl_nonorient = 0;
        m.a_cons_ok = m.a_cons_den = m.cons_excl_nonorient = 0;
        m.perm_den = m.perm_live = 0;
        m.disp_nz = 0;
        m.live = 0;
        m.patches_live = 0;
        m.z_seam = m.z_falloff = m.z_h_mid = m.z_amp = m.z_not_tess = 0;
        m.exempt_dead = 0;
        m.z_patch_dead = 0;
        m.f_rayf = m.f_vol = m.f_esc = m.f_und = 0;
        m.v_rayf = m.v_vol = m.v_esc = m.v_und = 0;
        m.f_volx = m.f_both = m.v_volx = m.v_both = 0;
        m.f_coll = m.v_coll = 0;
        m.f_conflict = m.v_conflict = 0;
        m.disp_sum_cm = 0;
        m.disp_max_cm = 0;
        m.inner_sum = 0;
        m.spacing_sum_m = 0;
        m.capped = false;
        // §4a: the parallax columns are zeroed and recomputed HERE too, with the rest of the
        // per-row counters, so a second evaluate() at another --dist-m can never double-count.
        // It is a per-FACE test, deliberately outside the per-generated-vertex loop below (which
        // the --max-verts-per-mesh cap can cut short), so P_sign% stays a property of the mesh and
        // is bit-identical at every inspection distance.
        grade_parallax_row(m);
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
      u64 local_cons_den = 0, local_cons_ok = 0;  // A_cons
      u64 local_cons_excl = 0;                    // ... its NON-ORIENTABLE exclusion (§3b)
      u64 local_sign_excl = 0;                    // A_sign's NON-ORIENTABLE exclusion (§3b)
      u64 local_perm_den = 0, local_perm_live = 0;  // B_perm's topology-only denominator
      u64 local_exempt_dead = 0;                  // structurally exempt AND not live
      u64 local_patches = 0, local_patches_live = 0;
      u64 lv_tier[7] = {0, 0, 0, 0, 0, 0, 0};
      u64 lv_conflict = 0;  // generated vertices on a RAYF-vs-VOL conflict face (DIAGNOSTIC)
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
        // outward(f) = osign[f] * gn(f), with osign decided PER FACE by the cascade
        // VOLX -> RAYF -> COLL -> ESC -> UNDECIDED. 0-length when every tier abstained.
        const V3 gn_face = normalized(face_cross(f));
        const V3 outward = (osign[f] != 0) ? gn_face * (double)osign[f] : V3{0, 0, 0};
        const bool have_outward = osign[f] != 0;
        const u8 tier_here = ftier[f];
        const bool conflict_here = face_conflict[f] != 0;
        // ---- A_cons: the FACE-LOCAL consistency reference, computed from this face ALONE ----
        // fcons(f) = sign(dot(n_geom, N_a + N_b + N_c)): which way round the face's own three
        // STORED corner normals collectively believe the face faces. It needs no shell, no ray, no
        // collision mesh and no winding propagation, so it is available on an UNDECIDED face too.
        // fcons == 0 (a degenerate face, or three corner normals that cancel exactly) means the
        // face states no belief at all: it is SKIPPED and counted nowhere, never scored as correct.
        const V3 ncorner_sum = gv[ia].nor + gv[ib].nor + gv[ic].nor;
        const double cons_dot = dot(gn_face, ncorner_sum);
        const int fcons = cons_dot > 0.0 ? 1 : (cons_dot < 0.0 ? -1 : 0);
        const V3 cons_ref = gn_face * (double)fcons;
        // ---- §3b: the two ORIGINAL-DATA impossibilities this patch inherits ----
        // NON-ORIENTABLE: a corner of this face admits no per-vertex normal that is correctly signed
        // for all of ITS incident faces, so the interpolated normal over this patch cannot be held to
        // the A_cons invariant — every generated vertex of the patch leaves cons_den (below).
        const bool face_nonorient = v_nonorient[ia] || v_nonorient[ib] || v_nonorient[ic];
        // PIN NECESSITY per corner, for B_perm. Same `g < n_groups` guard the pin attribution uses.
        const u32 wg0 = faces[f].wg[0], wg1 = faces[f].wg[1], wg2 = faces[f].wg[2];
        const bool pin_need0 = wg0 < n_groups && grp_pin_needed[wg0];
        const bool pin_need1 = wg1 < n_groups && grp_pin_needed[wg1];
        const bool pin_need2 = wg2 < n_groups && grp_pin_needed[wg2];
        u64 face_verts = 0, face_live = 0;
        if (store) {
          switch (tier_here) {
            case kTierRayf:
              m.f_rayf++;
              break;
            case kTierVol:
              m.f_vol++;  // unreachable since the cascade revision: the open-shell VOL tier is gone
              break;
            case kTierVolx:
              m.f_volx++;
              break;
            case kTierBoth:
              m.f_both++;  // unreachable since the cascade revision: RAYF outranks VOL outright
              break;
            case kTierColl:
              m.f_coll++;
              break;
            case kTierEsc:
              m.f_esc++;
              break;
            default:
              m.f_und++;
              break;
          }
          if (conflict_here) {
            m.f_conflict++;
          }
        }
        local_patches++;

        // ---- ONE generated vertex (.tese:191-421). `bary` is gl_TessCoord. ----
        auto do_vertex = [&](double bx, double by, double bz) {
          local_verts++;
          face_verts++;
          lv_tier[tier_here]++;
          if (conflict_here) {
            lv_conflict++;
          }
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
          // THE B_req SUBTRAHEND, tracked at the SAME sites as the z_seam / z_not_tess raw counters
          // above but qualified by NOT LIVE. A structural exemption only removes a vertex from the
          // requirement if the vertex was actually going to fail it: exempting a LIVE vertex shrinks
          // the denominator without shrinking the numerator, which is exactly how B_req reached an
          // impossible 100.4052%. The selector mirrors exempt() (TIE => the whole row, otherwise the
          // seam pin) so the two can never disagree about which vertex is exempt.
          if (amp <= 0.0 && (tessellated ? (seam == 0.0) : true)) {
            local_exempt_dead++;
          }
          // ===== B_perm's DENOMINATOR — PERMITTED DISPLACEMENT, DECIDED BY TOPOLOGY ============
          // A generated vertex is PERMITTED iff at least one patch corner with a NON-ZERO barycentric
          // weight sits in a weld group a pin is not GEOMETRICALLY NECESSARY for. This MIRRORS the
          // seam interpolation above: seam_lin is the barycentric blend of the corners' seam weights,
          // so it is 0 only when EVERY contributing corner is pinned; a vertex is therefore PERMITTED
          // exactly when at least one contributing corner need not have been pinned. The test reads
          // grp_pin_needed, which never touches an amplitude, a stored normal or a stored seam weight
          // — so unlike exemptDEAD (which subtracts a vertex BECAUSE it measured dead, and thereby
          // makes B_req 100% by construction) this denominator cannot be satisfied by construction.
          const bool permitted =
              (bx > 0.0 && !pin_need0) || (by > 0.0 && !pin_need1) || (bz > 0.0 && !pin_need2);
          if (permitted) {
            local_perm_den++;
            if (amp > 0.0) {
              local_perm_live++;
            }
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
          //
          // §3b EXCLUSION, ROUND 33 — THE SAME ONE A_cons HAS CARRIED SINCE IT WAS INTRODUCED (see
          // the A_cons block just below, and MeshRow::sign_excl_nonorient at the struct). If any
          // corner of this face is NON-ORIENTABLE then NO representable per-vertex normal — not the
          // baked one, not a hypothetical perfect one — can be correctly signed for every face
          // incident to that corner: tfrag3::mesh_best_packed_normal() said so, and that is the very
          // function MeshConsolidate.cpp pass 12 (:2791) uses when it tries to REPAIR the vertex, so
          // the pipeline has already proved it cannot fix it. Scoring such a vertex is scoring an
          // IMPOSSIBILITY, and it caps A_sign below 100% forever on a property of the AUTHORED
          // GEOMETRY that no bake can touch — the gate would then be measuring the level's fold-backs
          // rather than the pass's work. The exclusion A_cons already applies for exactly this reason
          // is just as valid here; its absence was an inconsistency, not a policy. The vertices leave
          // the denominator and are COUNTED (sign_excl_nonorient), never scored either way, so
          // sign_den + sign_excl_nonorient is the pre-exclusion denominator and section E prints it.
          //
          // A_lit IS DELIBERATELY NOT EXCLUDED. It is the spec-literal control column: it keeps the
          // pre-exclusion population as both its numerator's scope and its denominator (a_lit_pct()
          // divides by sign_den + sign_excl_nonorient), so its value is bit-for-bit what it was before
          // this exclusion existed and the header's structural-cap derivation stays checkable.
          if (amp > 0.0 && h != 0.5 && have_outward) {
            const double nd = dot(N, outward);
            if ((h - 0.5) * nd > 0.0) {
              local_ok_lit++;  // A_lit: the FULL, pre-exclusion population
            }
            if (face_nonorient) {
              local_sign_excl++;
            } else {
              local_den++;
              const double along = disp * nd;  // displacement component along outward
              if ((h - 0.5) * along > 0.0) {
                local_ok++;
              }
            }
          }
          // ===== A_cons — THE FACE-LOCAL CONSISTENCY INVARIANT ========================
          // The SAME population as A_sign except that an outward verdict is NOT required: a face
          // on an UNDECIDED shell still has a well-defined self-consistency. The reference is the
          // face's own plane oriented by its own corner normals (cons_ref), so this measures
          // whether the interpolated normal the .tese displaces along still points to the side its
          // own three corners voted for — the vertex-normal CLUSTERING question, with the outward
          // authority taken entirely out of the loop.
          // §3b EXCLUSION: if any corner of the face is NON-ORIENTABLE, no per-vertex normal — not the
          // baked one, not a hypothetical perfect one — can be correctly signed for every face
          // incident to that corner. The per-vertex format cannot express a right answer there, so the
          // vertex is REMOVED from the denominator instead of being scored wrong. It is counted in
          // cons_excl_nonorient over exactly this population, so cons_den + cons_excl_nonorient is the
          // denominator as it stood before the exclusion and nothing is hidden by it.
          if (amp > 0.0 && h != 0.5 && fcons != 0) {
            if (face_nonorient) {
              local_cons_excl++;
            } else {
              local_cons_den++;
              if (dot(N, cons_ref) > 0.0) {
                local_cons_ok++;
              }
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
        m.sign_excl_nonorient = local_sign_excl;
        m.a_cons_den = local_cons_den;
        m.a_cons_ok = local_cons_ok;
        m.cons_excl_nonorient = local_cons_excl;
        m.perm_den = local_perm_den;
        m.perm_live = local_perm_live;
        m.exempt_dead = local_exempt_dead;
        m.disp_nz = local_nz;
        m.live = local_live;
        m.patches_live = local_patches_live;
        m.v_rayf = lv_tier[kTierRayf];
        m.v_vol = lv_tier[kTierVol];
        m.v_esc = lv_tier[kTierEsc];
        m.v_und = lv_tier[kTierUnd];
        m.v_volx = lv_tier[kTierVolx];
        m.v_both = lv_tier[kTierBoth];
        m.v_coll = lv_tier[kTierColl];
        m.v_conflict = lv_conflict;
      }
      agg.gverts += local_verts;
      agg.sign_den += local_den;
      agg.sign_ok += local_ok;
      agg.sign_ok_lit += local_ok_lit;
      agg.sign_excl_nonorient += local_sign_excl;
      agg.a_cons_den += local_cons_den;
      agg.a_cons_ok += local_cons_ok;
      agg.cons_excl_nonorient += local_cons_excl;
      agg.perm_den += local_perm_den;
      agg.perm_live += local_perm_live;
      agg.disp_nz += local_nz;
      agg.live += local_live;
      agg.patches += local_patches;
      agg.patches_live += local_patches_live;
      // the RAW structurally exempt population: seam == 0 on tfrag, the WHOLE mesh on TIE
      agg.exempt += (m.system == kSysTie) ? local_verts : local_seam0;
      // ... and the part of it that is ALSO not live, which is the only part B_req may subtract
      agg.exempt_dead += local_exempt_dead;
      if (m.system != kSysTie) {
        agg.gverts_tfrag += local_verts;
        agg.disp_nz_tfrag += local_nz;
        agg.live_tfrag += local_live;
      }
      agg.v_rayf += lv_tier[kTierRayf];
      agg.v_vol += lv_tier[kTierVol];
      agg.v_esc += lv_tier[kTierEsc];
      agg.v_und += lv_tier[kTierUnd];
      agg.v_volx += lv_tier[kTierVolx];
      agg.v_both += lv_tier[kTierBoth];
      agg.v_coll += lv_tier[kTierColl];
      agg.v_conflict += lv_conflict;
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
  // the FACE COUNT decided by each outward tier, compact, in CASCADE ORDER:
  // X=VOLX (exact volume, closed shell) R=RAYF C=COLL (competence-filtered collision) E=ESC
  // U=UNDECIDED (not graded), and D= the DIAGNOSTIC count of faces where RAYF and VOL contradict
  // each other. D is NOT an exclusion any more and is NOT a subset of U: those faces are graded by
  // RAYF. X+R+C+E+U = the faces. (The old B=BOTH and V=VOL entries are gone with their tiers.)
  auto tierf_str = [](const MeshRow& m) {
    return fmt::format("X{}/R{}/C{}/E{}/U{}/D{}", m.f_volx, m.f_rayf, m.f_coll, m.f_esc, m.f_und,
                       m.f_conflict);
  };
  auto tierv_str = [](const MeshRow& m) {
    return fmt::format("X{}/R{}/C{}/E{}/U{}/D{}", m.v_volx, m.v_rayf, m.v_coll, m.v_esc, m.v_und,
                       m.v_conflict);
  };
  auto mesh_line = [&](u32 mi) {
    const auto& m = meshes[mi];
    const Shell& sh = shells[m.shell];
    return fmt::format(
        "{} {} {} {:>7.2f} {:>7.2f} {:>7.2f} {} {} {}  {:<5} {:>6} {:<32} {:<11} {:>5} {:<8} {:>7} "
        "{:>7}{} {:>9} {:>9} {:>7.2f} {:>8.3f} {:>8.3f} {:>7.2f} {:>7.3f}  {:<26} "
        "({:8.2f} {:7.2f} {:8.2f})  {}",
        pct_or_na(m.a_pct()), pct_or_na(m.a_cons_pct()), pct_or_na(m.p_pct()), m.b_live_pct(),
        m.b_pct(), m.b_patch_pct(), pct_or_na(m.b_req_pct()), pct_or_na(m.b_perm_pct()),
        pct_or_na(m.a_lit_pct()),
        kSysName[m.system], m.shell, tierf_str(m), rayf_vs_vol(sh),
        sh.winding_conflicts, coll_vs_truth(sh), m.faces.size(), m.faces_sampled,
        m.capped ? "*" : " ", m.gverts, m.exempt(), m.mean_inner(), m.disp_mean_cm(), m.disp_max_cm,
        m.verts_per_square(), m.upm, m.mat, m.centroid.x, m.centroid.y, m.centroid.z,
        m.named.empty() ? "-" : m.named);
  };
  const std::string mesh_hdr = fmt::format(
      "{:>7} {:>7} {:>7} {:>7} {:>7} {:>7} {:>7} {:>7} {:>7}  {:<5} {:>6} {:<32} {:<11} {:>5} {:<8} "
      "{:>7} {:>8} {:>9} {:>9} {:>7} {:>8} {:>8} {:>7} {:>7}  {:<26} {:^29}  {}",
      "A_sign%", "A_cons%", "P_sign%", "B_live%", "B_disp%", "B_patch", "B_req%", "B_perm%", "A_lit%",
      "sys",
      "shell", "tierFACES", "rayf_vs_vol", "wcf", "coll_vs_", "faces", "sampled", "gverts", "exempt",
      "meanInn", "dispMean", "dispMax", "v/sq", "upm", "material", "centroid (metres)",
      "named-case");
  // the SECOND per-mesh line: the zero-reason counters, the per-tier VERTEX counts and the
  // seam-pin reason attribution. Same row order as section A.
  auto mesh2_line = [&](u32 mi) {
    const auto& m = meshes[mi];
    return fmt::format(
        "{:<5} {:>6} {:<38} {} {:>9} {:>9} {:>9} {:>9} {:>9} {:>9} {:>9} {:>10} {:>11} {:>7} {:>7} "
        "{:>7} {:>7} {:>7} {:>9} {:>7}  {:<26} {}",
        kSysName[m.system], m.shell, tierv_str(m), pct_or_na(m.a_cons_pct()), m.a_cons_ok,
        m.a_cons_den, m.z_seam, m.z_falloff, m.z_h_mid, m.z_amp, m.z_not_tess, m.exempt_dead,
        m.z_patch_dead, m.pin_src, m.pin_material, m.pin_system, m.pin_open,
        m.pin_crease, m.pin_unexplained, m.pin_unexplained_subdiv, m.mat,
        m.named.empty() ? "-" : m.named);
  };
  const std::string mesh2_hdr = fmt::format(
      "{:<5} {:>6} {:<38} {:>7} {:>9} {:>9} {:>9} {:>9} {:>9} {:>9} {:>9} {:>10} {:>11} {:>7} {:>7} "
      "{:>7} {:>7} {:>7} {:>9} {:>7}  {:<26} {}",
      "sys", "shell", "tierVERTS", "A_cons%", "cons_ok", "cons_den", "z_seam", "z_falloff",
      "z_h_mid", "z_amp", "z_notess", "exemptDEAD", "z_patchdead", "pin_src", "pinMAT", "pinSYS",
      "pinOPEN", "pinCRSE", "PIN_UNEXP", "(subdv)", "material", "named-case");

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
  line("    ROUND 33: its denominator EXCLUDES the generated vertices of a face with a NON-ORIENTABLE");
  line("    corner, exactly as A_cons's does and for the same reason — no REPRESENTABLE per-vertex");
  line("    normal can be correctly signed there (tfrag3::mesh_best_packed_normal(), the function the");
  line("    repair pass MeshConsolidate.cpp:2791 itself calls, says so), and grading an impossibility");
  line("    would cap the score below 100% on a property of the authored geometry no bake can touch.");
  line("    They are COUNTED, never scored: section E prints the count and the pre-exclusion");
  line("    denominator, and A_lit below keeps the FULL population so the control column cannot move.");
  line("  * A_lit% = the mandate's LITERAL expression `(h - 0.5) * nd > 0`, reported for full");
  line("    disclosure and NOT used as the grade. It is the same formula with one factor of (h-0.5)");
  line("    dropped, so it demands nd > 0 on white texels and nd < 0 on black ones — i.e. it demands");
  line("    the surface be outward- and inward-facing at once. On a checkerboard (half white, half");
  line("    black BY CONSTRUCTION) it can therefore never exceed roughly the white-texel share, and");
  line("    can never reach the mandate's own 100% target. Measured before the correction: 50.04%");
  line("    level-wide and 50.15 / 49.90 / 49.52% on the three sage-hut cases — a coin flip that");
  line("    graded the broken ground floor and the known-good upper floor IDENTICALLY, i.e. it did");
  line("    not measure the defect. A_sign is the corrected metric and the one that discriminates.");
  line("  * A_cons% = THE FACE-LOCAL CONSISTENCY INVARIANT: every corner normal of a face must agree");
  line("    with that face about which side is out. It is INDEPENDENT of the outward authority and");
  line("    isolates the vertex-normal clustering defect from an authority disagreement.");
  line("        fcons(f) = sign( dot( n_geom(f), N_a + N_b + N_c ) )     N_* = the STORED corner normals");
  line("        a generated vertex is A_cons-CORRECT iff  dot(N_interp, n_geom(f) * fcons(f)) > 0");
  line("    n_geom is the face's own winding normal, UNSIGNED by any tier. The denominator is A_sign's");
  line("    (amp > 0 and h != 0.5) MINUS the requirement that the face have an outward verdict: a face");
  line("    on an UNDECIDED shell still has a well-defined self-consistency, so it is graded here. A");
  line("    face whose fcons is 0 — degenerate, or three corner normals that cancel exactly — states no");
  line("    belief and is SKIPPED entirely, never scored as correct. A_cons < 100% is a fact about the");
  line("    MESH DATA that no outward authority, right or wrong, can explain away: the face and its own");
  line("    corners contradict each other. A_sign can only be 100% where A_cons is.");
  line("  * Vertices with h == 0.5 EXACTLY, or amp == 0, have NO SIGN: they are counted in their own");
  line("    buckets (z_h_mid / z_seam / z_falloff / z_amp) and NEVER as correct.");
  line("");
  line("--- THE FIVE LIVENESS COLUMNS, each zero with a COMPUTABLE CAUSE ---------------------------");
  line("A mesh can be 100% correctly SIGNED and still be flat, so liveness is measured separately —");
  line("and split five ways so that no zero can hide behind another:");
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
  line("  * B_req%   = verts with amp > 0 / (all generated verts - exemptDEAD), where exemptDEAD is the");
  line("    population that is BOTH structurally exempt AND not live. There are exactly TWO structural");
  line("    exemptions and nothing else is ever exempt:");
  line("      (a) seam == 0 — the CRACK-GUARD PIN. mesh_consolidate pins a vertex whose two sides");
  line("          cannot displace alike (MeshConsolidate.cpp:2205-2252); the .tese then multiplies the");
  line("          amplitude by seam (.tese:416) so displacement is EXACTLY zero there. That is a");
  line("          deliberate design decision, not a defect — see the pinMAT/pinSYS/pinOPEN/pinCRSE");
  line("          columns, which prove it one vertex at a time.");
  line("      (b) z_not_tess — the mesh is TIE, and no tessellation program is ever bound for it, so");
  line("          the whole row is structurally exempt.");
  line("    THE ARITHMETIC, and the bug it fixes. z_seam and z_not_tess are RAW CAUSE COUNTS and are");
  line("    NOT a subset of the not-live population: a seam-pinned vertex is not live, but a TIE vertex");
  line("    generally IS (amp is a function of the material and the distance, not of which program is");
  line("    bound). Subtracting the raw count could therefore drive the denominator BELOW the numerator");
  line("    — B_req OVERALL printed 100.4052%, an impossible number. The subtrahend is now exemptDEAD,");
  line("    counted at the SAME two sites but only when the vertex is not live (amp <= 0), so");
  line("    live <= gverts - exemptDEAD holds by construction and B_req is bounded by 100% as a matter");
  line("    of arithmetic. Section E prints an explicit violation line if it ever is not.");
  line("    The raw z_seam / z_not_tess counters and the `exempt` column are printed UNCHANGED; the");
  line("    second per-mesh line carries exemptDEAD next to them. B_req reads n/a only when EVERY");
  line("    generated vertex of the row is exempt AND dead, i.e. when there is nothing to require.");
  line("  * B_perm%  = PERMITTED verts with amp > 0 / PERMITTED generated verts — THE DENOMINATOR B_req");
  line("    SHOULD HAVE HAD, and the one that can actually fail. B_req divides by");
  line("    (generated - exemptDEAD), and exemptDEAD is derived from the MEASURED amplitude: a vertex is");
  line("    subtracted BECAUSE it came out dead. That makes B_req 100% by construction — it is retained");
  line("    above and in the CSV for continuity, but it IS NOT A GATE and must not be read as one.");
  line("    B_perm's denominator is built from TOPOLOGY ALONE, before any measurement:");
  line("      a WELD GROUP needs a pin (grp_pin_needed) iff two of its referenced members could not");
  line("      displace alike, which is true iff ANY of");
  line("        - its incident faces carry more than one texture id  (different height map, different");
  line("          per-draw amplitude uniforms: the two sides cannot displace alike);");
  line("        - its incident faces span more than one SYSTEM (TIE is never routed through the");
  line("          tessellation program, so one side moves and the other cannot);");
  line("        - it has an OPEN BOUNDARY edge (there is no other side to match);");
  line("        - its incident faces do not all fit in ONE crease cluster, i.e. two of them have");
  line("          dot(n_a, n_b) < cos(crease_deg) under pass 7's own rule and threshold. THIS IS THE");
  line("          CAUSE OF THE SHIPPED PIN, NOT THE SHIPPED PIN: the pass pins when the members' normals");
  line("          actually differ, and the members' normals can only differ when the incident faces fall");
  line("          in more than one crease cluster. It is tested WITHOUT READING ONE STORED NORMAL.");
  line("      a GENERATED VERTEX is PERMITTED iff at least one patch corner with a non-zero barycentric");
  line("      weight sits in a group that does NOT need a pin. That mirrors the seam interpolation the");
  line("      .tese performs: seam is 0 only when EVERY contributing corner is pinned.");
  line("    grp_pin_needed is therefore an UPPER BOUND on what the consolidation pass may legitimately");
  line("    pin, computed from geometry alone — and that is exactly what makes B_perm falsifiable in the");
  line("    direction that matters: IF THE PASS PINS A GROUP THIS TEST SAYS NEED NOT BE PINNED, those");
  line("    vertices stay in the denominator, contribute nothing to the numerator, and B_perm drops");
  line("    below 100%. Nothing in the measurement can move the denominator. 'n/a' = the row has no");
  line("    permitted vertex at all (every corner of every patch sits in a group a pin is necessary");
  line("    for), which is a statement about the geometry and not about the tier.");
  line("  * z_patch_dead counts the vertices of patches with no live vertex at all — the same");
  line("    population B_patch% measures, expressed in vertices.");
  line("");
  line("--- WHAT THE PER-VERTEX FORMAT CANNOT EXPRESS (two ORIGINAL-DATA limits, and the ONLY two) ---");
  line("Two things are impossible to get right in this vertex format no matter what the bake writes, and");
  line("both are computed HERE from POSITIONS, TEXCOORDS, INDICES and TEXTURE IDS ALONE — never from a");
  line("stored normal, a stored tangent or a stored seam weight. That independence is the whole point: a");
  line("limit derived from the baked data would let the bake manufacture its own exclusion by writing");
  line("something bad. These are statements about the ORIGINAL AUTHORED GEOMETRY, which the bake can");
  line("neither alter nor argue with. Both are EXCLUDED FROM THEIR DENOMINATOR — not scored correct, and");
  line("not scored wrong — and both are reported in full in section E.");
  line("  * NON-ORIENTABLE VERTEX (v_nonorient): no single unit vector has a strictly positive dot");
  line("    product with the outward direction of every face incident to that vertex. The format carries");
  line("    ONE normal per vertex and the .tese displaces along the interpolation of those normals, so");
  line("    NO per-vertex normal whatsoever — not the baked one, not a hypothetical perfect one — can");
  line("    give every incident face a correctly-signed displacement there. The decision procedure is");
  line("    the SAME Badoiu-Clarkson Chebyshev iteration and the SAME 1e-3 tolerance MeshConsolidate.cpp");
  line("    pass 12 uses (:2694-2726, kPosEps at :2651): start at the normalized mean of the incident");
  line("    unit outwards, then up to 256 times step a shrinking 1/(it+2) fraction towards the currently");
  line("    WORST one and renormalize. That identity is deliberate — the pass's \"unsatisfiable\" and this");
  line("    grader's \"impossible\" must be ONE predicate, or the grader would exclude vertices the pass");
  line("    repaired, or keep scoring vertices the pass proved it could not. A generated vertex on a face");
  line("    with ANY non-orientable corner leaves A_cons's denominator (cons_EXCL_nonorient counts them");
  line("    over exactly that population, so cons_den + cons_EXCL is the denominator as it stood).");
  line("    The FOLD-BACK subset — vertices with two incident faces whose outwards have a NEGATIVE dot");
  line("    product — is reported separately, so the residual has a named geometric character (a fin,");
  line("    a surface doubling back through the vertex) instead of being a bare number.");
  line("  * NON-REPRESENTABLE TANGENT (v_nontan): the vertex's incident faces disagree about UV");
  line("    HANDEDNESS (the sign of det = du1*dv2 - du2*dv1 differs between two of them). For a face");
  line("    with right-handed UV the dP/du and dP/dv constraints on the tangent angle COINCIDE; for a");
  line("    left-handed one they are ANTIPODAL, and only w < 0 recovers them. w is ONE sign per VERTEX,");
  line("    so it selects which handedness that vertex serves: a vertex whose incident faces MIX");
  line("    handedness has no representable frame, and whichever w ships, every incident face of the");
  line("    other handedness is wrong. This is a property of the ORIGINAL AUTHORED UV LAYOUT and no bake");
  line("    can fix it. Such a face CORNER leaves P_sign's denominator (bucket p_nonrep), and it is");
  line("    tested BEFORE the tangent-fallback / gram-schmidt / no-normal buckets on purpose: the UV");
  line("    layout is the CAUSE, and whatever the bake then wrote into the tangent is the symptom.");
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
  line("--- GROUND TRUTH \"OUTWARD\": PER FACE, THE SAME CASCADE THE MESH PIPELINE RUNS --------------");
  line("outward(f) = osign[f] * normalize(cross(p1-p0, p2-p0)) — the face's OWN stored winding scaled");
  line("by a sign decided by this cascade, in this order, PER FACE:");
  line("        VOLX  ->  RAYF  ->  COLL  ->  ESC  ->  UNDECIDED (the face is NOT graded)");
  line("It is the SAME ORDER common/custom_data/MeshConsolidate.cpp applies. That is not a detail: an");
  line("instrument whose notion of \"outward\" differs from the pipeline's measures the gap between the");
  line("two instruments and calls it a renderer defect. The previous revision differed on about 40% of");
  line("faces, for the two reasons named under REMOVED below.");
  line("");
  line("  TIER VOLX (EXACT, per face, on a CLOSED shell): if every edge of the face's shell is used by");
  line("      exactly TWO of its faces, the shell bounds a volume and the divergence theorem makes the");
  line("      signed volume EXACT — its sign settles inside-vs-outside with no free parameter, no");
  line("      origin dependence and no sampling error. outward(f) = vol_sign(shell) * rel[f] * gn(f).");
  line("      EXACTNESS OUTRANKS SAMPLING: the escape-ray tier below is a finite sample of K directions");
  line("      per hemisphere and answers \"which side has more open space\", which is only a PROXY for");
  line("      \"which side is outside\" — and the proxy is measurably wrong on a small prop half-buried");
  line("      in the terrain around it, where both sides are largely blocked.");
  line("  TIER RAYF (per face, NO propagation, NO global orientation) — \"lancer de rayon");
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
  line("    WHY IT OUTRANKS THE SIGNED VOLUME ON AN OPEN SHELL, where VOLX cannot apply:");
  line("      (1) for an OPEN shell the cone volume about the bbox centre is ORIGIN-DEPENDENT, so the");
  line("          signed-volume criterion is not even well defined there;");
  line("      (2) a per-shell verdict has to be CARRIED to each face through the relative-winding BFS,");
  line("          and ONE bad link in that BFS — a fabricated adjacency across an edge incident to 3+");
  line("          faces, a mirrored copy, a decimated LOD triangle chained onto the full-res mesh —");
  line("          flips a whole sub-tree of faces and poisons the shell.");
  line("      RAYF has neither failure mode: nothing is propagated, and a face's verdict depends on");
  line("      nothing but its own geometry and the level around it.");
  line(fmt::format("  TIER COLL (per shell, carried by rel[]): the COLLISION verdict, area-weighted over the"));
  line(fmt::format("      shell's faces and filtered by the round-29 competence test — a face contributes"));
  line(fmt::format("      only when |dot(n, coll_n)| > {:g} (MeshConsolidate.cpp:1415) and the shell speaks",
                   kCollParallelMin));
  line(fmt::format("      only when the area-weighted confidence exceeds {:g} (:1420). Then",
                   kCollConfMin));
  line("      outward(f) = coll_sign(shell) * rel[f] * gn(f).");
  line("      WHY THE ROUND-29 AUTHORITY IS ALLOWED TO DECIDE AT ALL. Round 29 did not show that the");
  line("      collision normals are worthless; it showed that they were let to OUTRANK an exact signed");
  line("      volume through a competence gate that was vacuous. Here they outrank NOTHING: they are");
  line("      consulted only on a face where the exact volume cannot apply (open shell) AND the rays");
  line("      abstained. On that residue the alternative is not a better authority, it is NO authority:");
  line("      the face would go ungraded. A filtered verdict is strictly more than silence, and it sits");
  line("      where it can never displace a stronger one. The `coll_vs_` column keeps scoring it.");
  line(fmt::format("  TIER ESC (last resort, per shell): escape-distance asymmetry marched against the"));
  line(fmt::format("      whole-level BVH, free distance capped at {:g} m, winner's mean must lead by",
                   kEscMaxM));
  line(fmt::format("      >= {:.0f}%. Run ONLY for a shell that still owns a mesh face RAYF abstained on.",
                   (kEscMargin - 1.0) * 100.0));
  line("      It is admitted here ONLY when the shell verdict actually came from the escape march: a");
  line("      shell verdict of SIGNED-VOLUME provenance is refused, because that is the deleted tier.");
  line("  else UNDECIDED: reported as such, and the face is NOT graded. There is NO \"keep what was");
  line("      there\" fallback.");
  line("  REMOVED in this revision, and why — these two were the ~40% authority disagreement:");
  line("      (a) TIER VOL, the per-shell signed volume DECIDING ON AN OPEN SHELL. The cone volume about");
  line("          the bbox centre has no theorem behind it once the surface is not closed: it is");
  line("          origin-dependent, hence not a well-defined quantity, let alone a verdict. The number");
  line("          is STILL COMPUTED — VOLX needs it on a closed shell and the rayf_vs_vol column needs");
  line("          it everywhere — it simply never decides on an open shell. Its tier columns are gone");
  line("          from the tables and its CSV columns f_vol / v_vol / f_both / v_both stay at 0; a");
  line("          non-zero value in any of them is a BUG.");
  line("      (b) THE RAYF-vs-VOL CONFLICT EXCLUSION, which sent a face to UNDECIDED when the rays and");
  line("          the (open-shell, hence meaningless) volume disagreed. It discarded a verdict on the");
  line("          strength of a criterion that no longer has standing. Rays now simply outrank volume.");
  line("      (c) with them, TIER BOTH: it labelled a verdict RAYF now issues alone.");
  line("  REMOVED in an earlier revision: the old per-shell TIER B \"RAY\" (outward-ray PARITY over the");
  line("      shell's own faces). Parity needs a closed shell and a trustworthy crossing count, both of");
  line("      which the per-face escape test does without.");
  line("  tierFACES / tierVERTS columns give the FACE and generated-VERTEX count each tier decided, as");
  line("      X<volx>/R<rayf>/C<coll>/E<esc>/U<undecided>/D<diagnostic>, per mesh and in the totals.");
  line("      X+R+C+E+U = the faces. D is NOT one of them and NOT a subset of U: it is the DIAGNOSTIC");
  line("      count of faces where RAYF and VOL contradict each other, and those faces ARE graded, by");
  line("      RAYF, like any other.");
  line("  rayf_vs_vol (section A and C) scores the TWO INDEPENDENT criteria against each other on the");
  line("      shell's own mesh faces: they agree on face f iff rayf_vote[f] == vol_sign * rel[f]. It is");
  line("      a PUBLISHED DIAGNOSTIC and nothing more: since the cascade revision a DISAGREE suppresses");
  line("      no verdict, because on an open shell only one of the two criteria still has standing.");
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
  line(fmt::format("distinct edges          : {}", n_edges));
  line(fmt::format("SHELL COUNT            : {}", n_shells));
  line(fmt::format("mesh faces (displaceable): {}  = the RAYF population", n_mesh_faces));
  line(fmt::format("meshes (rows in A)     : {}", meshes.size()));
  line(fmt::format("sampling cap           : {} generated vertices per mesh", max_verts_per_mesh));
  line(fmt::format("RAYF pass              : K={} rays per hemisphere, {:.1f} s wall clock, {} threads"
                   " (per-face independent, so the thread count cannot move a single bit)",
                   rayf_k, rayf_seconds, std::max(1u, std::thread::hardware_concurrency())));
  line(fmt::format("ORIENT population      : ALL {} faces — NO face_is_candidate filter, exactly as "
                   "MeshConsolidate.cpp pass 6c (:2459-2468) calls it. The round-33 shell verdict is a "
                   "BALLOT of the shell's faces, so a filter on one side and not the other would give "
                   "the two runs different verdicts from the same geometry.",
                   faces.size()));
  // ONE PHYSICAL LINE, deliberately: grepped, never wrapped. Emitted ONLY when --rayf-k is off the
  // pipeline's default, in which case every A_sign / A_cons number below rests on shell verdicts the
  // bake never computed.
  if (!rayf_k_warning.empty()) {
    line(rayf_k_warning);
  }
  line("");
  line(subdiv_note);
  line("--- format_mesh_audit(rep, cfg) ----------------------------------------------------------");
  line(mesh_audit_text);

  // ---- A) PER-MESH TABLE ----------------------------------------------------------------------
  // --summary-only suppresses the ROWS of A, A2, B and the whole of C. Every one of those rows was
  // still MEASURED — the totals below are computed from exactly the same per-mesh state — only the
  // printing is skipped, because a 26-level sweep of the full tables runs to about a gigabyte.
  line("");
  line(std::string(100, '='));
  line("### A) PER-MESH TABLE (one line per mesh, sorted WORST FIRST by A_sign% then B_live%)");
  line("");
  if (summary_only) {
    line(fmt::format("--summary-only: the {} per-mesh rows of this section are SUPPRESSED. They were "
                     "measured exactly as usual and every total in section E is computed from them; "
                     "only the printing is skipped. Re-run without --summary-only for the table.",
                     meshes.size()));
  }
  if (!summary_only) {
  line("columns: A_sign% = correct-sign share of the vertices that HAVE a sign (amp>0 and h!=0.5);");
  line("         'n/a' = that denominator is EMPTY (nothing measurable here). Those UNGRADED rows are");
  line("         sorted to the END of the table, after every graded row, so the wrongly-signed meshes");
  line("         are at the head instead of being buried under the fully seam-pinned micro-meshes;");
  line("         their count is in section E. A_cons% = the FACE-LOCAL consistency invariant derived in");
  line("         the header: it needs NO outward authority, so it is graded on UNDECIDED faces too and");
  line("         its denominator is generally LARGER than A_sign's. A_sign can only be 100% where");
  line("         A_cons is; BOTH denominators EXCLUDE the vertices of faces with a NON-ORIENTABLE");
  line("         corner, which no representable per-vertex normal could serve (see the header, and the");
  line("         two EXCLUDED NON-ORIENTABLE lines in section E). A_lit% does NOT exclude them: it is");
  line("         the spec-literal control and keeps the pre-exclusion denominator.");
  line("         B_live / B_disp / B_patch / B_req / B_perm are the five liveness columns derived in");
  line("         the header (B_req's n/a = every generated vertex of the row is exempt AND not live).");
  line("         B_perm% is the one to read: its denominator is the PERMITTED vertices, decided by");
  line("         TOPOLOGY alone, so unlike B_req — which is 100% by construction and is NOT a gate — it");
  line("         can fail. 'n/a' = the row has no permitted vertex at all.");
  line("         tierFACES = the FACE count each outward tier decided, X=VOLX (exact volume on a CLOSED");
  line("         shell) R=RAYF C=COLL (competence-filtered collision) E=ESC U=UNDECIDED (not graded),");
  line("         and D = the DIAGNOSTIC count of faces where RAYF and VOL contradict each other. D is");
  line("         no longer an exclusion and is not a subset of U: those faces are graded by RAYF.");
  line("         rayf_vs_vol = per-face RAYF majority against");
  line("         the shell's signed-volume verdict, a PUBLISHED DIAGNOSTIC that suppresses no verdict.");
  line("         wcf = winding conflicts of the shell. coll_vs_ = how the COLLISION authority compares");
  line("         to the shell fallback verdict; it is a decision tier only BELOW RAYF (see the cascade");
  line("         above), never above it. A '*' after `sampled` means the per-mesh sampling cap bit.");
  line("         exempt = structurally exempt generated vertices, the RAW cause count (seam==0, or the");
  line("         whole TIE row); B_req subtracts only the not-live part of it, printed as exemptDEAD in");
  line("         section A2.");
  line("         v/sq = generated vertices across one checker square. dispMean/dispMax in CENTIMETRES.");
  line("         P_sign% = the OTHER tier: the share of face CORNERS whose tangent frame maps UV to");
  line("         world in the POSITIVE sense, i.e. T along +dP/du AND B = cross(N,T)*sign(.w) along");
  line("         +dP/dv. That is the only condition under which the shader's UV march carves relief");
  line("         the right way round; a wrong .w flips B and inverts the parallax in V ONLY, which");
  line("         leaves A_sign (a pure NORMAL question) perfectly green. It is a per-corner property");
  line("         of the mesh: no camera, no tessellation level, no checker enter it, so it does not");
  line("         move with --dist-m. 'n/a' = no gradeable corner (degenerate UVs, or every corner");
  line("         took the shader's Frisvad tangent fallback, or every corner is NON-REPRESENTABLE).");
  line("         The five skip buckets and the U-vs-.w split are in section E and in the CSV");
  line("         (p_u_wrong / p_w_wrong / p_tan_* / p_degen / p_nonrep, the last being the corners whose");
  line("         incident faces mix UV handedness, which one per-vertex tangent cannot serve).");
  line("");
  line(mesh_hdr);
  line(std::string(mesh_hdr.size(), '-'));
  for (u32 mi : order) {
    line(mesh_line(mi));
  }
  }  // !summary_only

  // ---- A2) PER-MESH ZERO REASONS + SEAM-PIN ATTRIBUTION ---------------------------------------
  if (!summary_only) {
  line("");
  line(std::string(100, '='));
  line("### A2) PER-MESH ZERO REASONS AND SEAM-PIN ATTRIBUTION (same row order as section A)");
  line("");
  line("tierVERTS = generated-VERTEX count per outward tier. A_cons% / cons_ok / cons_den are the");
  line("face-local consistency invariant and its raw counts (denominator: amp>0 and h!=0.5, WITHOUT");
  line("the outward requirement, over faces whose three corner normals state a belief). z_* are");
  line("generated-vertex counts; exemptDEAD is the structurally-exempt AND not-live subset, i.e. the");
  line("only population B_req may subtract from its denominator;");
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
  }  // !summary_only

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
    u64 hits = 0, den = 0, ok = 0, ok_lit = 0, gvv = 0, nz = 0, lv = 0, ex = 0, exd = 0, pat = 0,
        pat_live = 0;
    u64 cons_ok = 0, cons_den = 0, cons_excl = 0;
    u64 sign_excl = 0;  // A_sign's NON-ORIENTABLE exclusion over this case's rows
    u64 perm_lv = 0, perm_dn = 0, pnonrep = 0;
    u64 fR = 0, fE = 0, fU = 0, vR = 0, vE = 0, vU = 0;
    u64 fX = 0, fCo = 0, fD = 0, vX = 0, vCo = 0, vD = 0;
    u64 ps = 0, pm = 0, py = 0, po = 0, pc = 0, pu = 0;
    std::vector<u32> case_rows;
    if (!summary_only) {
      line(mesh_hdr);
    }
    for (u32 mi : order) {
      if (meshes[mi].named.find(nb.name) == std::string::npos) {
        continue;
      }
      const auto& m = meshes[mi];
      hits++;
      den += m.sign_den;
      ok += m.sign_ok;
      ok_lit += m.sign_ok_lit;
      sign_excl += m.sign_excl_nonorient;
      cons_ok += m.a_cons_ok;
      cons_den += m.a_cons_den;
      cons_excl += m.cons_excl_nonorient;
      perm_lv += m.perm_live;
      perm_dn += m.perm_den;
      pnonrep += m.p_nonrep;
      gvv += m.gverts;
      nz += m.disp_nz;
      lv += m.live;
      ex += m.exempt();
      exd += m.exempt_dead;
      pat += m.faces_sampled;
      pat_live += m.patches_live;
      fR += m.f_rayf;
      fE += m.f_esc;
      fU += m.f_und;
      vR += m.v_rayf;
      vE += m.v_esc;
      vU += m.v_und;
      fX += m.f_volx;
      fCo += m.f_coll;
      fD += m.f_conflict;
      vX += m.v_volx;
      vCo += m.v_coll;
      vD += m.v_conflict;
      ps += m.pin_src;
      pm += m.pin_material;
      py += m.pin_system;
      po += m.pin_open;
      pc += m.pin_crease;
      pu += m.pin_unexplained;
      named_shells.insert(m.shell);
      case_rows.push_back(mi);
      if (!summary_only) {
        line(mesh_line(mi));
      }
    }
    if (!hits) {
      line("  (no mesh centroid falls inside this box)");
    } else {
      if (!summary_only) {
        line("");
        line("  " + mesh2_hdr);
        for (u32 mi : case_rows) {
          line("  " + mesh2_line(mi));
        }
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
      // A_lit divides by the PRE-EXCLUSION denominator (den + sign_excl), exactly as a_lit_pct() does
      // per row: the control column must not move when A_sign's denominator does.
      line(fmt::format("  CASE A_sign = {}  ({}/{} vertices; {} more EXCLUDED as NON-ORIENTABLE)"
                       "     A_lit = {}",
                       den ? fmt::format("{:.2f}%", 100.0 * (double)ok / (double)den)
                           : std::string("n/a"),
                       ok, den, sign_excl,
                       (den + sign_excl) ? fmt::format("{:.2f}%", 100.0 * (double)ok_lit /
                                                                      (double)(den + sign_excl))
                                         : std::string("n/a")));
      line(fmt::format("  CASE A_cons = {}  ({}/{} vertices, no outward authority required; {} more "
                       "EXCLUDED as NON-ORIENTABLE)",
                       cons_den
                           ? fmt::format("{:.2f}%", 100.0 * (double)cons_ok / (double)cons_den)
                           : std::string("n/a"),
                       cons_ok, cons_den, cons_excl));
      line(fmt::format("  CASE B_live = {:.2f}% ({}/{})   B_disp = {:.2f}% ({}/{})   B_patch = {}"
                       "   B_req = {}",
                       gvv ? 100.0 * (double)lv / (double)gvv : 0.0, lv, gvv,
                       gvv ? 100.0 * (double)nz / (double)gvv : 0.0, nz, gvv,
                       pat ? fmt::format("{:.2f}% ({}/{})",
                                         100.0 * (double)pat_live / (double)pat, pat_live, pat)
                           : std::string("n/a"),
                       gvv > exd ? fmt::format("{:.2f}% ({}/{})",
                                               100.0 * (double)lv / (double)(gvv - exd), lv,
                                               gvv - exd)
                                 : std::string("n/a")));
      line(fmt::format("  CASE B_perm = {}   <== the TOPOLOGY-ONLY denominator (B_req above is 100% by "
                       "construction and is NOT a gate)",
                       perm_dn ? fmt::format("{:.2f}% ({}/{})",
                                             100.0 * (double)perm_lv / (double)perm_dn, perm_lv,
                                             perm_dn)
                               : std::string("n/a")));
      line(fmt::format("  CASE P_sign non-representable corners EXCLUDED (mixed UV handedness): {}",
                       pnonrep));
      line(fmt::format("  CASE exempt = {} raw ({} of them also NOT LIVE — only those are subtracted "
                       "by B_req)",
                       ex, exd));
      line(fmt::format("  CASE tierFACES = X{}/R{}/C{}/E{}/U{}/D{}   "
                       "tierVERTS = X{}/R{}/C{}/E{}/U{}/D{}",
                       fX, fR, fCo, fE, fU, fD, vX, vR, vCo, vE, vU, vD));
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
  if (!summary_only) {
  line("gsign/tier = the SHELL-LEVEL verdict and the tier that produced it (VOL / ESC / UNDECIDED). It");
  line("is NOT the primary authority: a face is decided by VOLX then the per-face RAYF tier, and only");
  line("then by anything shell-level. A shell can therefore read UNDECIDED here while every one of its");
  line("mesh faces is decided — check the tierFACES column of section A. Note that a tier of VOL here");
  line("no longer DECIDES anything on an OPEN shell: that tier was deleted from the cascade, and the");
  line("ESC door explicitly refuses a shell verdict of signed-volume provenance. ESC is also only run");
  line("when a mesh face of the shell actually needs it, so esc_ratio is 0 on shells RAYF covered.");
  line("vol_sign is the SIGNED-VOLUME verdict alone; rayf_voted/agree/DISAGREE and rayf_vs_vol score the");
  line("two INDEPENDENT geometric criteria against each other over the shell's mesh faces (they agree on");
  line("face f iff rayf_vote[f] == vol_sign * rel[f]). A DISAGREE row is a shell where the two criteria");
  line("pull apart; it is PUBLISHED AS A DIAGNOSTIC and suppresses nothing, because on an open shell");
  line("only the rays still have standing.");
  line("closed = every edge of the shell is used by EXACTLY TWO of its faces, and open_edge counts the");
  line("ones that are not: only on a closed shell is the signed volume EXACT (divergence theorem), and");
  line("only there does it outrank the escape-ray sample (tier VOLX). coll_* is the COLLISION authority");
  line("scored against the shell verdict; it DECIDES a face only where VOLX and RAYF both could not");
  line("(tier COLL). baked_* stays DIAGNOSIS ONLY — the baked normals are the very quantity A_sign");
  line("grades, so letting them define outward would make the grade circular.");
  line("");
  const std::string shell_hdr = fmt::format(
      "{:>6} {:>7} {:>7} {:<9} {:>6} {:>8} {:>12} {:>6} {:>9} {:>8} {:>8} {:>9} {:<11} {:>5} {:<9} "
      "{:>6} {:<9} {:>6} {:>9}",
      "shell", "faces", "meshes", "tier", "gsign", "vol_sign", "|V6|/L^3", "wcf", "esc_ratio",
      "rayf_vot", "rayf_agr", "rayf_DIS", "rayf_vs_vol", "coll", "coll_vs_", "baked", "baked_vs_",
      "closed", "open_edge");
  line(shell_hdr);
  line(std::string(shell_hdr.size(), '-'));
  }  // !summary_only
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
        "{:<9} {:>6} {:<9} {:>6} {:>9}",
        s, sh.faces.size(), meshes_per_shell[s], sh.tier,
        sh.gsign == 0 ? "0" : (sh.gsign > 0 ? "+1" : "-1"),
        sh.vol_sign == 0 ? "0" : (sh.vol_sign > 0 ? "+1" : "-1"), sh.v6_over_l3,
        sh.winding_conflicts, sh.esc_ratio, sh.rayf_voted, sh.rayf_agree, sh.rayf_disagree,
        rayf_vs_vol(sh), sh.coll_speaks ? (sh.coll_sign > 0 ? "+1" : "-1") : "-", coll_vs_truth(sh),
        sh.baked_sign == 0 ? "0" : (sh.baked_sign > 0 ? "+1" : "-1"), baked_vs_truth(sh),
        sh.closed ? "yes" : "no", sh.open_edges);
  };
  if (summary_only) {
    line(fmt::format("--summary-only: the {} shell rows of this section are SUPPRESSED. They were "
                     "computed exactly as usual and the shell totals in section E are derived from "
                     "them; only the printing is skipped.",
                     shell_order.size()));
  } else {
    for (u32 s : shell_order) {
      line(shell_line(s));
    }
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
  // A_cons's own row census, and the FULLY-FLAT row count (B_live% == 0: every vertex pinned).
  u64 n_cons_na = 0, n_cons_graded = 0, n_cons100 = 0, n_fully_flat = 0;
  u64 n_breq_over_100 = 0;  // rows violating the B_req bound — must stay 0, see the assertion below
  // B_perm's own row census, with the same n/a convention: an empty PERMITTED denominator is no grade.
  u64 n_perm_na = 0, n_perm_graded = 0, n_perm100 = 0;
  // the rows whose scores actually LOST population to the two §3b impossibility sets.
  u64 n_rows_nonorient = 0, n_rows_nontan = 0;
  u32 worst_a = UINT32_MAX, worst_b = UINT32_MAX, worst_live = UINT32_MAX,
      worst_patch = UINT32_MAX, worst_req = UINT32_MAX, worst_p = UINT32_MAX,
      worst_cons = UINT32_MAX, worst_perm = UINT32_MAX;
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
    // same idiom for the PARALLAX tier: rows with an empty p_den carry no grade and cannot be the
    // worst GRADED row.
    if (m.p_pct() >= 0 && (worst_p == UINT32_MAX || m.p_pct() < meshes[worst_p].p_pct())) {
      worst_p = i;
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
    // B_req's bound, checked per row rather than asserted in prose.
    if (m.b_req_pct() > 100.0) {
      n_breq_over_100++;
    }
    // A_cons's census, with the same n/a convention as A_sign: an empty denominator is no grade.
    if (m.a_cons_pct() < 0) {
      n_cons_na++;
    } else {
      n_cons_graded++;
      if (m.a_cons_pct() >= 100.0) {
        n_cons100++;
      }
      if (worst_cons == UINT32_MAX || m.a_cons_pct() < meshes[worst_cons].a_cons_pct()) {
        worst_cons = i;
      }
    }
    // B_perm's census, same n/a convention: an empty PERMITTED denominator carries no grade and
    // cannot be the worst GRADED row.
    if (m.b_perm_pct() < 0) {
      n_perm_na++;
    } else {
      n_perm_graded++;
      if (m.b_perm_pct() >= 100.0) {
        n_perm100++;
      }
      if (worst_perm == UINT32_MAX || m.b_perm_pct() < meshes[worst_perm].b_perm_pct()) {
        worst_perm = i;
      }
    }
    // the rows whose scores actually lost population to the two ORIGINAL-DATA impossibilities.
    if (m.cons_excl_nonorient) {
      n_rows_nonorient++;
    }
    if (m.p_nonrep) {
      n_rows_nontan++;
    }
    // FULLY FLAT: not one generated vertex of the row receives a non-zero amplitude.
    if (m.b_live_pct() <= 0.0) {
      n_fully_flat++;
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
  // ONE PHYSICAL LINE, deliberately: grepped, never wrapped. Modelled on the A_cons line below, and
  // for the identical reason — see the §3b block at the do_vertex A_sign test.
  line(fmt::format("A_sign EXCLUDED NON-ORIENTABLE : {}  generated vertices on a face with a "
                   "NON-ORIENTABLE corner ({:.4f}% of the pre-exclusion denominator {}) — no "
                   "representable per-vertex normal can serve them, so they are OUT of the "
                   "denominator, NOT scored",
                   agg_main.sign_excl_nonorient,
                   (agg_main.sign_den + agg_main.sign_excl_nonorient)
                       ? 100.0 * (double)agg_main.sign_excl_nonorient /
                             (double)(agg_main.sign_den + agg_main.sign_excl_nonorient)
                       : 0.0,
                   agg_main.sign_den + agg_main.sign_excl_nonorient));
  line(fmt::format("A_cons OVERALL              : {}   (the face-local consistency invariant: NO "
                   "outward authority is involved)",
                   agg_main.a_cons_den
                       ? fmt::format("{:.4f}%  ({}/{})",
                                     100.0 * (double)agg_main.a_cons_ok /
                                         (double)agg_main.a_cons_den,
                                     agg_main.a_cons_ok, agg_main.a_cons_den)
                       : std::string("n/a")));
  // ONE PHYSICAL LINE, deliberately: grepped, never wrapped.
  line(fmt::format("A_cons EXCLUDED NON-ORIENTABLE : {}  generated vertices on a face with a "
                   "NON-ORIENTABLE corner ({:.4f}% of the pre-exclusion denominator {}) — no "
                   "per-vertex normal could serve them, so they are OUT of the denominator, NOT scored",
                   agg_main.cons_excl_nonorient,
                   (agg_main.a_cons_den + agg_main.cons_excl_nonorient)
                       ? 100.0 * (double)agg_main.cons_excl_nonorient /
                             (double)(agg_main.a_cons_den + agg_main.cons_excl_nonorient)
                       : 0.0,
                   agg_main.a_cons_den + agg_main.cons_excl_nonorient));
  // A_lit's denominator is the PRE-EXCLUSION population, unchanged by round 33's A_sign exclusion:
  // the spec-literal control column must be evaluated on the mandate's own population or it stops
  // being a control. Same expression as a_lit_pct() per row.
  line(fmt::format("A_lit  OVERALL (spec literal): {}   <-- structurally capped near the white-texel"
                   " share; see the derivation in the header",
                   (agg_main.sign_den + agg_main.sign_excl_nonorient)
                       ? fmt::format("{:.4f}%  ({}/{})",
                                     100.0 * (double)agg_main.sign_ok_lit /
                                         (double)(agg_main.sign_den +
                                                  agg_main.sign_excl_nonorient),
                                     agg_main.sign_ok_lit,
                                     agg_main.sign_den + agg_main.sign_excl_nonorient)
                       : std::string("n/a")));
  line("");
  line("---- THE FIVE LIVENESS NUMBERS, each with the mesh that owns the WORST value ----");
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
  const double b_req_overall =
      agg_main.gverts > agg_main.exempt_dead
          ? 100.0 * (double)agg_main.live / (double)(agg_main.gverts - agg_main.exempt_dead)
          : -1.0;
  line(fmt::format("B_req   OVERALL             : {}   exempt {} raw of {} generated verts, of which "
                   "{} are ALSO not live (the only ones subtracted)",
                   b_req_overall >= 0
                       ? fmt::format("{:.4f}%  ({}/{})", b_req_overall, agg_main.live,
                                     agg_main.gverts - agg_main.exempt_dead)
                       : std::string("n/a"),
                   agg_main.exempt, agg_main.gverts, agg_main.exempt_dead));
  // THE BOUND, CHECKED RATHER THAN CLAIMED. exempt_dead is a subset of the not-live population, so
  // live <= gverts - exempt_dead must hold and B_req cannot exceed 100%. It printed 100.4052% before
  // the subtrahend was corrected; this line exists so that a regression announces itself instead of
  // being read as a number.
  if (b_req_overall > 100.0 || n_breq_over_100) {
    line(fmt::format("   B_req BOUND VIOLATED     : OVERALL {:.4f}% and {} per-mesh rows exceed 100% "
                     "— that is ARITHMETICALLY IMPOSSIBLE and is a BUG in the exempt accounting",
                     b_req_overall, n_breq_over_100));
  } else {
    line("   B_req bound              : OK, <= 100% overall and on every row (the subtrahend is the "
         "structurally-exempt AND not-live population, a subset of the not-live one)");
  }
  if (worst_req != UINT32_MAX) {
    line(fmt::format("   WORST B_req              : {:.2f}%  {}", meshes[worst_req].b_req_pct(),
                     owner_of(worst_req)));
  }
  // ---- B_perm: the denominator the MEASUREMENT CANNOT MOVE -------------------------------------
  // B_req's subtrahend is derived from the measured amplitude (a vertex is removed BECAUSE it came out
  // dead), so B_req is 100% by construction: it is retained above for continuity and IS NOT A GATE.
  // B_perm divides by the PERMITTED generated vertices — those with at least one contributing patch
  // corner in a weld group a pin is not GEOMETRICALLY NECESSARY for, decided from texture ids, systems,
  // open edges and incident-face angles ALONE. If the pipeline pins a group this test says need not be
  // pinned, those vertices stay in the denominator and B_perm falls below 100%.
  const double b_perm_overall =
      agg_main.perm_den ? 100.0 * (double)agg_main.perm_live / (double)agg_main.perm_den : -1.0;
  line(fmt::format("B_perm  OVERALL             : {}   <== THE LIVENESS GATE: the denominator is the "
                   "PERMITTED generated vertices, decided by TOPOLOGY ALONE (B_req is 100% by "
                   "construction and is NOT a gate)",
                   b_perm_overall >= 0
                       ? fmt::format("{:.4f}%  ({}/{})", b_perm_overall, agg_main.perm_live,
                                     agg_main.perm_den)
                       : std::string("n/a")));
  line(fmt::format("   NOT-PERMITTED verts      : {}  of {} generated ({:.4f}%) — every contributing "
                   "corner sits in a group a pin is GEOMETRICALLY NECESSARY for",
                   agg_main.gverts - agg_main.perm_den, agg_main.gverts,
                   agg_main.gverts
                       ? 100.0 * (double)(agg_main.gverts - agg_main.perm_den) /
                             (double)agg_main.gverts
                       : 0.0));
  line(fmt::format("meshes at B_perm = 100%     : {}  of {} GRADED meshes ({:.2f}%)  ({} rows n/a)",
                   n_perm100, n_perm_graded,
                   n_perm_graded ? 100.0 * (double)n_perm100 / (double)n_perm_graded : 0.0,
                   n_perm_na));
  if (worst_perm != UINT32_MAX) {
    line(fmt::format("   WORST B_perm             : {:.2f}%  {}", meshes[worst_perm].b_perm_pct(),
                     owner_of(worst_perm)));
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
  // ONE PHYSICAL LINE, deliberately: this line is grepped, never wrapped.
  line(fmt::format(
      "FULLY-FLAT MESHES            : {}  (rows whose B_live% == 0: every vertex of the mesh is "
      "pinned — this is the owner's \"chunk completely flat\")",
      n_fully_flat));
  line("");
  if (worst_a != UINT32_MAX) {
    line(fmt::format("WORST A_sign                : {:.2f}%  {}", meshes[worst_a].a_pct(),
                     owner_of(worst_a)));
  }
  // ONE PHYSICAL LINE, deliberately: grepped, never wrapped.
  if (worst_cons != UINT32_MAX) {
    line(fmt::format("WORST A_cons                 : {:.2f}%  {}", meshes[worst_cons].a_cons_pct(),
                     owner_of(worst_cons)));
  }
  // ---- the PARALLAX tier's own totals (§4a). Distance-independent, so unlike A/B these numbers
  // are the same at every --dist-m and are absent from the distance sweep in section F. ----
  {
    u64 p_ok = 0, p_den = 0, p_uw = 0, p_ww = 0, p_fb = 0, p_td = 0, p_nn = 0, p_dg = 0, p_nr = 0;
    u64 p_na_rows = 0, p_100_rows = 0, p_graded_rows = 0;
    for (const auto& m : meshes) {  // meshes is an ordered vector => a deterministic sum
      p_ok += m.p_ok;
      p_den += m.p_den;
      p_uw += m.p_u_wrong;
      p_ww += m.p_w_wrong;
      p_fb += m.p_tan_fallback;
      p_td += m.p_tan_degen;
      p_nn += m.p_no_normal;
      p_dg += m.p_degen;
      p_nr += m.p_nonrep;
      if (m.p_pct() < 0) {
        p_na_rows++;
      } else {
        p_graded_rows++;
        if (m.p_pct() >= 100.0) {
          p_100_rows++;
        }
      }
    }
    line("");
    line(fmt::format("P_sign OVERALL              : {}   (face CORNERS whose tangent frame maps UV "
                     "to world in the + sense)",
                     p_den ? fmt::format("{:.4f}%  ({}/{})", 100.0 * (double)p_ok / (double)p_den,
                                         p_ok, p_den)
                           : std::string("n/a")));
    line(fmt::format("   wrong in U (T reversed)  : {}   ({:.4f}% of graded corners)", p_uw,
                     p_den ? 100.0 * (double)p_uw / (double)p_den : 0.0));
    line(fmt::format("   wrong in V (.w HANDEDNESS): {}   ({:.4f}% of graded corners)  <== "
                     "parallax INVERTED while the tessellation tier stays correct",
                     p_ww, p_den ? 100.0 * (double)p_ww / (double)p_den : 0.0));
    line(fmt::format("   ungradeable corners      : tangent-fallback {} (shader drops to Frisvad, "
                     "dot(t,t) <= 0.04), gram-schmidt-degenerate {}, no normal {}, NON-REPRESENTABLE "
                     "{} (the vertex's incident faces MIX UV handedness, so one per-vertex (T,w) "
                     "cannot serve them — an ORIGINAL-UV-LAYOUT limit, tested first, excluded from the "
                     "denominator and never scored)",
                     p_fb, p_td, p_nn, p_nr));
    line(fmt::format("   UV-degenerate faces      : {}  (|det| <= 1e-12: the face defines no UV "
                     "direction, so it has no parallax sign)",
                     p_dg));
    if (worst_p != UINT32_MAX) {
      line(fmt::format("WORST P_sign                : {:.2f}%  {}", meshes[worst_p].p_pct(),
                       owner_of(worst_p)));
    }
    line(fmt::format("meshes at P_sign = 100%     : {}  of {} GRADED meshes ({:.2f}%)  <== THE "
                     "PARALLAX GATE ({} rows n/a)",
                     p_100_rows, p_graded_rows,
                     p_graded_rows ? 100.0 * (double)p_100_rows / (double)p_graded_rows : 0.0,
                     p_na_rows));
    line("");
  }
  // ---- §3b WHAT THE PER-VERTEX FORMAT CANNOT EXPRESS: the two ORIGINAL-DATA limits, level-wide ----
  // Each figure below is computed from POSITIONS, TEXCOORDS, INDICES and TEXTURE IDS ALONE — no stored
  // normal, no stored tangent, no stored seam weight, no measured amplitude enters any of them. They
  // are limits of the AUTHORED GEOMETRY that the per-vertex vertex format cannot express, so the
  // affected population is EXCLUDED FROM ITS DENOMINATOR rather than scored: not counted correct, and
  // not counted wrong. Every line here is ONE physical line, deliberately: they are grepped.
  {
    u64 p_nr_tot = 0, p_den_tot = 0;
    for (const auto& m : meshes) {
      p_nr_tot += m.p_nonrep;
      p_den_tot += m.p_den;
    }
    const u64 p_pre_tot = p_nr_tot + p_den_tot;  // P_sign's denominator BEFORE the exclusion
    line("---- ORIGINAL-DATA LIMITS (computed from positions/uvs/indices alone; EXCLUDED, not scored) ----");
    line(fmt::format("NON-ORIENTABLE VERTICES     : {}  of {} global vertices ({:.4f}%) — no"
                     " REPRESENTABLE normal (3x signed 10 bits) has a dot above 1e-3 with the outward"
                     " direction of EVERY incident face, so NO per-vertex normal can be correctly signed"
                     " there (decided by tfrag3::mesh_best_packed_normal(), the SAME function"
                     " MeshConsolidate.cpp pass 12 repairs a vertex with, at the same 1e-3 tolerance)",
                     n_nonorient, gv.size(),
                     gv.size() ? 100.0 * (double)n_nonorient / (double)gv.size() : 0.0));
    line(fmt::format("   of them FOLD-BACK / FIN  : {}  ({:.2f}% of the non-orientable set) — two "
                     "incident faces whose outward directions have a NEGATIVE dot product: the surface "
                     "doubles back through the vertex.  EXACT-CANCEL (incident outwards sum to zero): {}",
                     n_nonorient_fold,
                     n_nonorient ? 100.0 * (double)n_nonorient_fold / (double)n_nonorient : 0.0,
                     n_nonorient_cancel));
    line(fmt::format("   A_cons GENERATED VERTS EXCLUDED : {}  ({:.4f}% of the pre-exclusion "
                     "denominator {}), affecting {} of {} mesh rows",
                     agg_main.cons_excl_nonorient,
                     (agg_main.a_cons_den + agg_main.cons_excl_nonorient)
                         ? 100.0 * (double)agg_main.cons_excl_nonorient /
                               (double)(agg_main.a_cons_den + agg_main.cons_excl_nonorient)
                         : 0.0,
                     agg_main.a_cons_den + agg_main.cons_excl_nonorient, n_rows_nonorient,
                     meshes.size()));
    // A_sign carries the SAME exclusion since round 33 — the two denominators differ (A_sign demands
    // an outward verdict, A_cons does not), so the two counts are stated separately and neither is
    // inferable from the other. A_lit is NOT excluded: it keeps the pre-exclusion population.
    line(fmt::format("   A_sign GENERATED VERTS EXCLUDED : {}  ({:.4f}% of the pre-exclusion "
                     "denominator {}) — A_lit keeps the FULL population and is unaffected",
                     agg_main.sign_excl_nonorient,
                     (agg_main.sign_den + agg_main.sign_excl_nonorient)
                         ? 100.0 * (double)agg_main.sign_excl_nonorient /
                               (double)(agg_main.sign_den + agg_main.sign_excl_nonorient)
                         : 0.0,
                     agg_main.sign_den + agg_main.sign_excl_nonorient));
    line(fmt::format("NON-REPRESENTABLE-TANGENT VERTICES : {}  of {} global vertices ({:.4f}%) — the "
                     "vertex's incident faces disagree about UV HANDEDNESS (the sign of "
                     "du1*dv2-du2*dv1), and .w is ONE sign per vertex, so one per-vertex tangent cannot "
                     "serve both: a limit of the ORIGINAL AUTHORED UV LAYOUT",
                     n_nontan, gv.size(),
                     gv.size() ? 100.0 * (double)n_nontan / (double)gv.size() : 0.0));
    line(fmt::format("   P_sign FACE CORNERS EXCLUDED : {}  ({:.4f}% of the pre-exclusion denominator "
                     "{}), affecting {} of {} mesh rows",
                     p_nr_tot, p_pre_tot ? 100.0 * (double)p_nr_tot / (double)p_pre_tot : 0.0,
                     p_pre_tot, n_rows_nontan, meshes.size()));
    line("   Neither set can be manufactured by the bake: both are properties of the ORIGINAL geometry");
    line("   and its UV layout, read from positions, texcoords, indices and texture ids only. They are");
    line("   the ONLY two exclusions of this kind, and each one is reported here in full.");
    line("");
  }
  line(fmt::format("meshes at A_sign = 100%     : {}  of {} GRADED meshes ({:.2f}%)  <== THE GATE",
                   n_a100, meshes.size() - n_na,
                   (meshes.size() - n_na)
                       ? 100.0 * (double)n_a100 / (double)(meshes.size() - n_na)
                       : 0.0));
  // ONE PHYSICAL LINE, deliberately: grepped, never wrapped. GRADED here means a non-empty A_cons
  // denominator, which does NOT require an outward verdict — so this population differs from, and is
  // generally larger than, the A_sign one above.
  line(fmt::format("meshes at A_cons = 100%      : {}  of {} GRADED meshes ({:.2f}%)", n_cons100,
                   n_cons_graded,
                   n_cons_graded ? 100.0 * (double)n_cons100 / (double)n_cons_graded : 0.0));
  line(fmt::format("meshes with A_cons = n/a    : {}  (empty denominator: no vertex with amp>0 and "
                   "h!=0.5 on a face whose corner normals state a belief)",
                   n_cons_na));
  line(fmt::format("meshes at A_sign = 0%       : {}  (every graded vertex moves the WRONG WAY)",
                   n_a_zero));
  line(fmt::format("meshes at 100/100           : {}  ({:.2f}%)", n_perfect,
                   meshes.empty() ? 0.0 : 100.0 * (double)n_perfect / (double)meshes.size()));
  line("   (100/100 additionally demands B_disp == 100%, which the CHECKER itself makes unreachable:");
  line("    its box-filtered mips contain texels that are EXACTLY 127.5/255 = 0.5, and every");
  line("    seam-pinned vertex has amp == 0. A_sign = 100% is the SIGN gate; B_disp is the separate");
  line("    liveness one.)");
  line(fmt::format("meshes with A_sign = n/a    : {}  (empty denominator: every vertex was either "
                   "amp==0 or exactly h==0.5, or sat on a face the cascade left UNDECIDED)",
                   n_na));
  line(fmt::format("meshes on an UNDECIDED shell: {}", n_undecided_meshes));
  line(fmt::format("shells in section C         : {}  of which UNDECIDED {}", shell_order.size(),
                   n_shell_undecided));
  line(fmt::format("meshes where the cap bit    : {}  (--max-verts-per-mesh {})", n_capped,
                   max_verts_per_mesh));
  {
    u64 zs = 0, zf = 0, zh = 0, za = 0, zn = 0, zp = 0, zed = 0;
    u64 fR = 0, fV = 0, fE = 0, fU = 0, fX = 0, fB = 0, fC = 0, fCo = 0;
    for (const auto& m : meshes) {
      zs += m.z_seam;
      zf += m.z_falloff;
      zh += m.z_h_mid;
      za += m.z_amp;
      zn += m.z_not_tess;
      zp += m.z_patch_dead;
      zed += m.exempt_dead;
      fR += m.f_rayf;
      fV += m.f_vol;
      fE += m.f_esc;
      fU += m.f_und;
      fX += m.f_volx;
      fB += m.f_both;
      fCo += m.f_coll;
      fC += m.f_conflict;
    }
    line("");
    line(fmt::format("zero-reason totals          : z_seam={} z_falloff={} z_h_mid={} z_amp={} "
                     "z_not_tess={} z_patch_dead={} exempt_dead={}",
                     zs, zf, zh, za, zn, zp, zed));
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
    const u64 f_all = fX + fR + fCo + fE + fU;
    line(fmt::format("OUTWARD TIER, FACES         : VOLX={} RAYF={} COLL={} ESC={} "
                     "UNDECIDED={}  (of {} mesh faces counted once per mesh row)",
                     fX, fR, fCo, fE, fU, f_all));
    line(fmt::format("OUTWARD TIER, GEN. VERTICES : VOLX={} RAYF={} COLL={} ESC={} UNDECIDED={}",
                     agg_main.v_volx, agg_main.v_rayf, agg_main.v_coll, agg_main.v_esc,
                     agg_main.v_und));
    line("   VOLX = the shell is CLOSED, so the signed volume is EXACT (divergence theorem) and it");
    line("   outranks the escape-ray SAMPLE. COLL = the competence-filtered collision verdict, which");
    line("   is consulted ONLY where VOLX cannot apply and RAYF abstained.");
    line(fmt::format("   REMOVED TIERS, still counted so a regression is visible: VOL={} faces "
                     "BOTH={} faces (both must be 0: the open-shell volume tier and the CONFLICT "
                     "exclusion were deleted from the cascade)",
                     fV, fB));
    line(fmt::format("rayf_vs_vol CONFLICT (DIAGNOSTIC) : {} faces  ({} generated vertices)  -> "
                     "GRADED BY RAYF, not excluded",
                     fC, agg_main.v_conflict));
    line(fmt::format("   ({} faces level-wide by the per-face cascade, before the per-mesh-row "
                     "restriction). This population is NOT part of UNDECIDED any more:",
                     n_conflict_diag));
    line("   UNDECIDED means every tier of the cascade stayed silent on the face. A RAYF-vs-VOL");
    line("   contradiction is published as a diagnostic and suppresses no verdict, because on an OPEN");
    line("   shell the signed volume has no standing to contradict the rays with.");
    line(fmt::format("   EXACT (VOLX) share of the graded work: {:.2f}% of faces, {:.2f}% of "
                     "vertices",
                     f_all ? 100.0 * (double)fX / (double)f_all : 0.0,
                     agg_main.gverts
                         ? 100.0 * (double)agg_main.v_volx / (double)agg_main.gverts
                         : 0.0));
    line(fmt::format("   RAYF share of the graded work: {:.2f}% of faces, {:.2f}% of vertices",
                     f_all ? 100.0 * (double)fR / (double)f_all : 0.0,
                     agg_main.gverts ? 100.0 * (double)agg_main.v_rayf / (double)agg_main.gverts
                                     : 0.0));
    line(fmt::format("   COLL share of the graded work: {:.2f}% of faces, {:.2f}% of vertices",
                     f_all ? 100.0 * (double)fCo / (double)f_all : 0.0,
                     agg_main.gverts ? 100.0 * (double)agg_main.v_coll / (double)agg_main.gverts
                                     : 0.0));
  }
  // ---- CLOSED vs OPEN shells: the precondition of the EXACT (VOLX) tier --------------------------
  {
    u64 sh_closed = 0, sh_open = 0, f_closed = 0, f_open = 0;
    u64 gc = 0, go = 0, gfc = 0, gfo = 0, open_edge_tot = 0;
    for (const auto& sh : shells) {
      if (sh.closed) {
        sh_closed++;
        f_closed += sh.faces.size();
      } else {
        sh_open++;
        f_open += sh.faces.size();
        open_edge_tot += sh.open_edges;
      }
    }
    for (u32 s : shell_order) {
      if (shells[s].closed) {
        gc++;
        gfc += shells[s].faces.size();
      } else {
        go++;
        gfo += shells[s].faces.size();
      }
    }
    line("");
    line(fmt::format("SHELLS CLOSED / OPEN        : closed={} ({} faces)  open={} ({} faces)  "
                     "[CLOSED = every edge of the shell is used by EXACTLY TWO of its faces; the {} "
                     "open edges are the rest]",
                     sh_closed, f_closed, sh_open, f_open, open_edge_tot));
    line(fmt::format("   of the shells in section C: closed={} ({} faces)  open={} ({} faces)", gc,
                     gfc, go, gfo));
    line("   Only a CLOSED shell bounds a volume, so only there is the signed-volume sign EXACT and");
    line("   allowed to outrank the escape-ray sample (tier VOLX).");
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
    line("   opposite outward directions. It is PUBLISHED AS A DIAGNOSTIC and excludes nothing: on an");
    line("   OPEN shell the signed volume is origin-dependent and has no standing, so the rays decide");
    line("   and the disagreement is a fact about the geometry rather than a reason to abstain.");
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
                       // A_lit over the PRE-EXCLUSION denominator, as a_lit_pct() and section E do:
                       // the control column does not follow A_sign's denominator.
                       (a.sign_den + a.sign_excl_nonorient)
                           ? fmt::format("{:.4f}", 100.0 * (double)a.sign_ok_lit /
                                                       (double)(a.sign_den +
                                                                a.sign_excl_nonorient))
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
  if (summary_only) {
    // --summary-only: the CSV is one line per mesh and is exactly the bulk the flag exists to avoid.
    fmt::print("[tess_sign] --summary-only: CSV not written ({} rows skipped)\n", meshes.size());
  } else {
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
         "aabb_lo_z_m,aabb_hi_x_m,aabb_hi_y_m,aabb_hi_z_m,inspection_distance_m,"
         // §4a the PARALLAX tier, appended at the END so every pre-existing column keeps its index
         "P_sign_pct,p_ok,p_den,p_u_wrong,p_w_wrong,p_tan_fallback,p_tan_degen,p_degen,"
         // the cascade's populations, likewise appended at the END. f_vol / v_vol / f_both / v_both
         // above are now always 0: those tiers were deleted from the cascade.
         "f_volx,f_both,f_conflict,v_volx,v_both,v_conflict,shell_closed,shell_open_edges,"
         // the COLL tier, A_cons and the corrected B_req subtrahend, appended after those
         "f_coll,v_coll,A_cons_pct,a_cons_ok,a_cons_den,exempt_dead,"
         // §3b/§4c: B_perm's topology-only denominator and the two ORIGINAL-DATA exclusions, appended
         // last so every pre-existing column keeps its index. An empty B_perm_pct cell is the n/a case.
         "B_perm_pct,perm_live,perm_den,cons_excl_nonorient,p_nonrep,"
         // round 33: A_sign's own NON-ORIENTABLE exclusion. Appended as the LAST column so every
         // pre-existing column keeps its index. sign_den is now POST-exclusion, so A_sign's
         // pre-exclusion denominator — which is also A_lit_pct's denominator — is
         // sign_den + sign_excl_nonorient.
         "sign_excl_nonorient\n";
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
      s += fmt::format("{:.4f},{:.4f},{:.4f},{:.4f},{:.4f},{:.4f},{:.4f},{:.4f},{:.4f},{:.4f},",
                       m.centroid.x, m.centroid.y, m.centroid.z, m.aabb_lo.x, m.aabb_lo.y,
                       m.aabb_lo.z, m.aabb_hi.x, m.aabb_hi.y, m.aabb_hi.z, dist_m);
      // §4a the PARALLAX tier, same ordinal as the header's trailing group. An empty P_sign_pct
      // cell is the n/a case, exactly as A_sign_pct writes it above.
      s += fmt::format("{},{},{},{},{},{},{},{},",
                       m.p_pct() < 0 ? std::string("") : fmt::format("{:.6f}", m.p_pct()), m.p_ok,
                       m.p_den, m.p_u_wrong, m.p_w_wrong, m.p_tan_fallback, m.p_tan_degen,
                       m.p_degen);
      s += fmt::format("{},{},{},{},{},{},{},{},", m.f_volx, m.f_both, m.f_conflict, m.v_volx,
                       m.v_both, m.v_conflict, sh.closed ? 1 : 0, sh.open_edges);
      // the COLL tier, A_cons (empty cell = n/a, same convention as A_sign_pct) and exempt_dead
      s += fmt::format("{},{},{},{},{},{},", m.f_coll, m.v_coll,
                       m.a_cons_pct() < 0 ? std::string("")
                                          : fmt::format("{:.6f}", m.a_cons_pct()),
                       m.a_cons_ok, m.a_cons_den, m.exempt_dead);
      // §3b/§4c: B_perm (empty cell = n/a, same convention) and the two ORIGINAL-DATA exclusions,
      // then round 33's A_sign exclusion as the trailing column.
      s += fmt::format("{},{},{},{},{},{}\n",
                       m.b_perm_pct() < 0 ? std::string("")
                                          : fmt::format("{:.6f}", m.b_perm_pct()),
                       m.perm_live, m.perm_den, m.cons_excl_nonorient, m.p_nonrep,
                       m.sign_excl_nonorient);
      c << s;
    }
    c.flush();
    if (!c) {
      fmt::print("error: failed writing '{}'\n", csv_path);
      return 1;
    }
  }
  fmt::print("[tess_sign] report -> {}\n[tess_sign] csv    -> {}\n", out_path,
             summary_only ? std::string("(skipped: --summary-only)") : csv_path);
  return 0;
}
