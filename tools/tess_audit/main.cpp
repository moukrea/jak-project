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
//                   [--seg-near M] [--seg-d0 M] [--seg-far M] [--feature-cm C] [--ground-cos C]

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <map>
#include <set>
#include <string>
#include <vector>

#include "common/custom_data/Tfrag3Data.h"
#include "common/util/FileUtil.h"
#include "common/util/Serializer.h"
#include "common/util/compress.h"

#include "fmt/format.h"

// NOTE: FileUtil.h already defines `namespace fs = ghc::filesystem`; reuse it.

static void usage() {
  fmt::print(
      "Usage: tess_audit [--fr3 PATH] [--cam-m X Y Z] [--cam X Y Z] [--tess-max N] [--geom N]\n"
      "                  [--out PATH] [--seg-near M] [--seg-d0 M] [--seg-far M] [--feature-cm C]\n"
      "                  [--ground-cos C]\n"
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
      "  --feature-cm C  reference relief feature wavelength in cm, for v/feature (default 5.0)\n"
      "  --ground-cos C  |face normal.y| threshold above which a patch is GROUND (default 0.707)\n"
      "  --fade-lo M     EDGE law: distance where the amplitude-matched density fade starts "
      "(default 20.0)\n"
      "  --fade-hi M     EDGE law: distance where the fade reaches level 1 (default 30.0)\n");
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
double seg_target_m(double d_m, double seg_near, double seg_d0, double seg_far) {
  return clampd(seg_near * std::max(d_m, seg_d0) / seg_d0, seg_near, seg_far);
}
// GLSL smoothstep.
double smoothstepd(double e0, double e1, double x) {
  const double t = clampd((x - e0) / (e1 - e0), 0.0, 1.0);
  return t * t * (3.0 - 2.0 * t);
}
double edge_law_level(double edge_m, double d_m, double tess_max, double seg_near, double seg_d0,
                      double seg_far, double fade_lo, double fade_hi) {
  double lvl = edge_m / seg_target_m(d_m, seg_near, seg_d0, seg_far);
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
};

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
  double feature_cm = 5.0;
  double ground_cos = 0.707;
  // shipped tesc amplitude-matched density fade band.
  double fade_lo = 20.0;
  double fade_hi = 30.0;
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
    } else if (a == "--feature-cm") {
      feature_cm = std::stod(need_val("--feature-cm"));
    } else if (a == "--ground-cos") {
      ground_cos = std::stod(need_val("--ground-cos"));
    } else if (a == "--fade-lo") {
      fade_lo = std::stod(need_val("--fade-lo"));
    } else if (a == "--fade-hi") {
      fade_hi = std::stod(need_val("--fade-hi"));
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
    auto emit_patch = [&](u32 i0, u32 i1, u32 i2, MatStat* mat) {
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

      // EDGE law: each edge is levelled by ITS OWN world-space length at ITS OWN midpoint dist.
      double inner_edge;
      if (dmin > 30.0) {
        inner_edge = 1.0;
      } else {
        const double l0 = edge_law_level(e0, d0, tess_max, seg_near, seg_d0, seg_far, fade_lo,
                                         fade_hi);
        const double l1 = edge_law_level(e1, d1, tess_max, seg_near, seg_d0, seg_far, fade_lo,
                                         fade_hi);
        const double l2 = edge_law_level(e2, d2, tess_max, seg_near, seg_d0, seg_far, fade_lo,
                                         fade_hi);
        inner_edge = std::max(std::max(l0, l1), l2);
      }

      accumulate_cls(cls_band[0][cls][band], inner_new, e0, e1, e2);
      accumulate_cls(cls_band[1][cls][band], inner_edge, e0, e1, e2);

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
              emit_patch(t0, t1, t2, mat);
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
            emit_patch(t0, t1, t2, mat);
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
                   "else seg_target(d) = clamp(seg_near*max(d,seg_d0)/seg_d0, seg_near, seg_far), "
                   "lvl_i = edge_i_m / seg_target(d_i), lvl_i = mix(1, lvl_i, 1 - "
                   "smoothstep({:.1f}, {:.1f}, d_i)) [AMPLITUDE-MATCHED DENSITY FADE, the tese "
                   "fades displacement amplitude to 0 over the same band], outer_i = clamp(lvl_i, "
                   "1, {:.0f}); inner = max(outer). seg_near={:.3f}m seg_d0={:.3f}m "
                   "seg_far={:.3f}m fade={:.1f}..{:.1f}m; feature ref = {:.2f} cm",
                   fade_lo, fade_hi, tess_max, seg_near, seg_d0, seg_far, fade_lo, fade_hi,
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
                   "tess_max={:.0f} fade=mix(1,lvl,1-smoothstep({:.1f},{:.1f},d_mid)) "
                   "[amplitude-matched density fade]",
                   seg_near, seg_d0, seg_far, tess_max, fade_lo, fade_hi));
  line(fmt::format("   v/feature = {:.2f} cm reference feature wavelength / mean segment size",
                   feature_cm));

  auto cls_table = [&](int law, int cls) {
    line(fmt::format("--- {} | {} ---", kLawNames[law], kClassNames[cls]));
    line("  band(m)     patches       mean_inner   max_inner   est_gen_tris   mean_edge_m   "
         "p90_edge_m   mean_spacing_cm   p90_spacing_cm   v/feature   mean_mip_lod");
    for (int b = 0; b < kNumBands; ++b) {
      const auto& x = cls_band[law][cls][b];
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
      cls_table(law, cls);
      line("");
    }
  }

  // ---- G) ground near-field (<10 m) head-to-head ----
  auto merge_cls = [&](int law, int cls, int b0, int b1) {
    ClassBand o;
    for (int b = b0; b < b1; ++b) {
      const auto& x = cls_band[law][cls][b];
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
