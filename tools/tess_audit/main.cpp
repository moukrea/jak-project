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

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <fstream>
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
      "                  [--out PATH]\n"
      "  --fr3 PATH      level fr3 (default: <repo>/out/jak1/fr3/village1.fr3)\n"
      "  --cam-m X Y Z   camera position in METRES (multiplied by 4096 internally)\n"
      "  --cam X Y Z     camera position in GAME UNITS\n"
      "                  (neither given: centroid of all tessellable tfrag vertices)\n"
      "  --tess-max N    NEW-law ceiling (default 32)\n"
      "  --geom N        tfrag geom LOD to audit (default 0 = Gfx::g_global_settings.lod_tfrag,\n"
      "                  the only geom TFragment draws at a time)\n"
      "  --out PATH      report path (default: <repo>/.autoport/reports/\n"
      "                  Grecharged-pbr-realtime-fusion/tess_audit.txt)\n");
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

}  // namespace

int main(int argc, char** argv) {
  std::string fr3_path_s;
  std::string out_path;
  double tess_max = 32.0;
  int geom = 0;
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

    // one patch (a,b,c) -> both laws.
    auto emit_patch = [&](u32 i0, u32 i1, u32 i2) {
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
    };

    for (const auto& draw : tree.draws) {
      draws_counted++;
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
              emit_patch(t0, t1, t2);
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
            emit_patch(t0, t1, t2);
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
