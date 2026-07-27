// Grecharged-mesh-consolidation: OFFLINE whole-game mesh audit CLI (desktop only).
//
// Loads every level .fr3 of a game, runs the LEGACY/shipped global weld first (so the numbers
// describe the BEFORE state the owner currently sees on device), then runs the exhaustive
// mesh_consolidate() pass and records its MeshAuditReport.
//
// The point is the NO-OMISSIONS METRIC: coincident-but-unshared edges (forgotten welds) counted
// per level, per system, BEFORE and AFTER, plus the honest residual missed_welds_remaining.
//
// Usage: mesh_audit [--game jak1|jak2|jak3] [--fr3-dir DIR] [--level NAME] [--out PATH]
//                   [--csv PATH] [--limit N] [--bake] [--verify-bake]
//
// Read-only on the .fr3 files: nothing is ever written back to disk except the report + csv, and
// (with --bake) the per-level <level>.meshweld precompute sidecars next to the .fr3 files.

#include <algorithm>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <string>
#include <vector>

#include "common/custom_data/MeshConsolidate.h"
#include "common/custom_data/Tfrag3Data.h"
#include "common/util/FileUtil.h"
#include "common/util/Serializer.h"
#include "common/util/compress.h"

#include "fmt/format.h"

// NOTE: FileUtil.h already defines `namespace fs = ghc::filesystem`; reuse it.

static void usage() {
  fmt::print(
      "Usage: mesh_audit [--game jak1|jak2|jak3] [--fr3-dir DIR] [--level NAME] [--out PATH]\n"
      "                  [--csv PATH] [--limit N] [--bake] [--verify-bake]\n"
      "  --game NAME    jak1 (default) | jak2 | jak3\n"
      "  --fr3-dir DIR  fr3 directory (default: <repo>/out/<game>/fr3)\n"
      "  --level NAME   audit only this level (default: every *.fr3, sorted)\n"
      "  --out PATH     report path (default: <repo>/.autoport/reports/\n"
      "                 Grecharged-mesh-consolidation/mesh_audit_<game>.txt)\n"
      "  --csv PATH     csv path (default: same dir, mesh_audit_<game>.csv)\n"
      "  --limit N      audit at most N levels (smoke runs)\n"
      "  --bake         also write the precompute sidecar <fr3-dir>/<level>.meshweld\n"
      "  --verify-bake  round-trip self-test: re-load the fr3, apply the sidecar, and compare it\n"
      "                 field-by-field against the live pass (requires --bake)\n");
}

namespace {

// Everything we keep about a level once its (huge) tfrag3::Level has been freed.
struct LevelResult {
  std::string level;
  tfrag3::MeshAuditReport rep;
};

struct LevelFailure {
  std::string level;
  std::string what;
};

// The exact load+unpack sequence Loader.cpp performs, plus the legacy/shipped global weld. Used for
// BOTH the audited level and the fresh --verify-bake copy so the two start from identical geometry.
void load_level_fr3(const fs::path& fr3_path, tfrag3::Level& lev) {
  auto data = file_util::read_binary_file(fr3_path);
  auto decomp = compression::decompress_zstd(data.data(), data.size());
  Serializer ser(decomp.data(), decomp.size());
  lev.serialize(ser);
  // The packed fr3 leaves tree.unpacked.{vertices,indices} empty until unpack() runs
  // (mirror of Loader.cpp) — the audit reads exactly those arrays.
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
  for (auto& shrub_tree : lev.shrub_trees) {
    shrub_tree.unpack();
  }

  // The legacy/shipped pass FIRST: this is what the device does today, so the audit's
  // "before" numbers are the state the owner is actually looking at.
  tfrag3::reconstruct_level_global_weld(lev);
}

// ---- --verify-bake: flat view of every renderable tree, in gather_level()'s traversal order ----
constexpr int kCmpTfrag = 0, kCmpTie = 1, kCmpShrub = 2;
constexpr const char* kCmpSysName[3] = {"tfrag", "tie", "shrub"};

struct CmpTree {
  int system = 0;
  const void* verts = nullptr;
  size_t count = 0;
  const tfrag3::PackedTimeOfDay* colors = nullptr;
};

struct CmpVert {
  float x = 0, y = 0, z = 0;
  u32 nor = 0;
  u16 color_index = 0;
  u16 seam_w = 0;
};

void collect_cmp_trees(const tfrag3::Level& lev, std::vector<CmpTree>& out) {
  for (const auto& geom : lev.tfrag_trees) {
    for (const auto& t : geom) {
      out.push_back({kCmpTfrag, t.unpacked.vertices.data(), t.unpacked.vertices.size(), &t.colors});
    }
  }
  for (const auto& geom : lev.tie_trees) {
    for (const auto& t : geom) {
      out.push_back({kCmpTie, t.unpacked.vertices.data(), t.unpacked.vertices.size(), &t.colors});
    }
  }
  for (const auto& t : lev.shrub_trees) {
    out.push_back({kCmpShrub, t.unpacked.vertices.data(), t.unpacked.vertices.size(),
                   &t.time_of_day_colors});
  }
}

CmpVert cmp_vert(const CmpTree& t, size_t i) {
  CmpVert o;
  if (t.system == kCmpShrub) {
    const auto& v = ((const tfrag3::ShrubGpuVertex*)t.verts)[i];
    o.x = v.x;
    o.y = v.y;
    o.z = v.z;
    o.nor = v.nor;
    o.color_index = v.color_index;
    o.seam_w = v.seam_w;
  } else {
    const auto& v = ((const tfrag3::PreloadedVertex*)t.verts)[i];
    o.x = v.x;
    o.y = v.y;
    o.z = v.z;
    o.nor = v.nor;
    o.color_index = v.color_index;
    o.seam_w = v.seam_w;
  }
  return o;
}

std::string fbits(float f) {
  u32 b;
  std::memcpy(&b, &f, 4);
  return fmt::format("{:.9g}/0x{:08x}", f, b);
}

// Compares the sidecar-applied level against the live-pass level over the SAME traversal order.
// Prints at most `max_report` mismatch lines; returns the number of mismatches found.
u64 verify_bake_compare(const std::string& level_name,
                        const tfrag3::Level& live,
                        const tfrag3::Level& baked,
                        int max_report) {
  std::vector<CmpTree> a, b;
  collect_cmp_trees(live, a);
  collect_cmp_trees(baked, b);
  u64 bad = 0;
  auto report = [&](const std::string& what, s64 tree, s64 vert, const std::string& lhs,
                    const std::string& rhs) {
    bad++;
    if ((int)bad <= max_report) {
      fmt::print("VERIFY-BAKE {}: MISMATCH {} at {}/{} ({} vs {})\n", level_name, what, tree, vert,
                 lhs, rhs);
    }
  };
  if (a.size() != b.size()) {
    report("tree_count", -1, -1, fmt::format("{}", (u64)a.size()), fmt::format("{}", (u64)b.size()));
    return bad;
  }
  for (size_t ti = 0; ti < a.size() && (int)bad < max_report; ti++) {
    const char* sys = kCmpSysName[a[ti].system];
    if (a[ti].system != b[ti].system) {
      report("system", (s64)ti, -1, kCmpSysName[a[ti].system], kCmpSysName[b[ti].system]);
      continue;
    }
    if (a[ti].count != b[ti].count) {
      report(fmt::format("{}.vert_count", sys), (s64)ti, -1, fmt::format("{}", (u64)a[ti].count),
             fmt::format("{}", (u64)b[ti].count));
      continue;
    }
    for (size_t vi = 0; vi < a[ti].count && (int)bad < max_report; vi++) {
      const CmpVert va = cmp_vert(a[ti], vi);
      const CmpVert vb = cmp_vert(b[ti], vi);
      if (std::memcmp(&va.x, &vb.x, sizeof(float))) {
        report(fmt::format("{}.x", sys), (s64)ti, (s64)vi, fbits(va.x), fbits(vb.x));
      }
      if (std::memcmp(&va.y, &vb.y, sizeof(float))) {
        report(fmt::format("{}.y", sys), (s64)ti, (s64)vi, fbits(va.y), fbits(vb.y));
      }
      if (std::memcmp(&va.z, &vb.z, sizeof(float))) {
        report(fmt::format("{}.z", sys), (s64)ti, (s64)vi, fbits(va.z), fbits(vb.z));
      }
      if (va.nor != vb.nor) {
        report(fmt::format("{}.nor", sys), (s64)ti, (s64)vi, fmt::format("0x{:08x}", va.nor),
               fmt::format("0x{:08x}", vb.nor));
      }
      if (va.color_index != vb.color_index) {
        report(fmt::format("{}.color_index", sys), (s64)ti, (s64)vi,
               fmt::format("{}", va.color_index), fmt::format("{}", vb.color_index));
      }
      if (va.seam_w != vb.seam_w) {
        report(fmt::format("{}.seam_w", sys), (s64)ti, (s64)vi, fmt::format("{}", va.seam_w),
               fmt::format("{}", vb.seam_w));
      }
    }
    if ((int)bad >= max_report) {
      break;
    }
    const auto* ca = a[ti].colors;
    const auto* cb = b[ti].colors;
    if (!ca || !cb) {
      continue;
    }
    if (ca->color_count != cb->color_count) {
      report(fmt::format("{}.colors.color_count", sys), (s64)ti, -1,
             fmt::format("{}", ca->color_count), fmt::format("{}", cb->color_count));
    }
    if (ca->data.size() != cb->data.size()) {
      report(fmt::format("{}.colors.data_size", sys), (s64)ti, -1,
             fmt::format("{}", (u64)ca->data.size()), fmt::format("{}", (u64)cb->data.size()));
    } else if (!ca->data.empty() &&
               std::memcmp(ca->data.data(), cb->data.data(), ca->data.size())) {
      // name the first differing byte so the failure is actionable
      size_t off = 0;
      while (off < ca->data.size() && ca->data[off] == cb->data[off]) {
        off++;
      }
      report(fmt::format("{}.colors.data", sys), (s64)ti, (s64)off,
             fmt::format("0x{:02x}", ca->data[off]), fmt::format("0x{:02x}", cb->data[off]));
    }
  }
  return bad;
}

}  // namespace

int main(int argc, char** argv) {
  std::string game = "jak1";
  std::string fr3_dir;
  std::string only_level;
  std::string out_path;
  std::string csv_path;
  int limit = -1;
  bool do_bake = false;
  bool verify_bake = false;

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
    if (a == "--game") {
      game = need_val("--game");
    } else if (a == "--fr3-dir") {
      fr3_dir = need_val("--fr3-dir");
    } else if (a == "--level") {
      only_level = need_val("--level");
    } else if (a == "--out") {
      out_path = need_val("--out");
    } else if (a == "--csv") {
      csv_path = need_val("--csv");
    } else if (a == "--limit") {
      limit = std::stoi(need_val("--limit"));
    } else if (a == "--bake") {
      do_bake = true;
    } else if (a == "--verify-bake") {
      verify_bake = true;
    } else if (a == "-h" || a == "--help") {
      usage();
      return 0;
    } else {
      fmt::print("error: unknown/unexpected argument '{}'\n", a);
      usage();
      return 2;
    }
  }

  if (game != "jak1" && game != "jak2" && game != "jak3") {
    fmt::print("error: --game must be jak1, jak2 or jak3 (got '{}')\n", game);
    return 2;
  }
  if (verify_bake && !do_bake) {
    fmt::print("error: --verify-bake round-trips the sidecar and therefore requires --bake\n");
    return 2;
  }

  // Resolve the repo so the default fr3 dir / report dir work from anywhere.
  bool have_project = file_util::setup_project_path({});
  if (fr3_dir.empty()) {
    if (!have_project) {
      fmt::print("error: could not resolve the jak-project directory; pass --fr3-dir.\n");
      return 1;
    }
    fr3_dir = (file_util::get_jak_project_dir() / "out" / game / "fr3").string();
  }
  if (out_path.empty() || csv_path.empty()) {
    if (!have_project) {
      fmt::print("error: could not resolve the jak-project directory; pass --out and --csv.\n");
      return 1;
    }
    const fs::path rep_dir =
        file_util::get_jak_project_dir() / ".autoport" / "reports" / "Grecharged-mesh-consolidation";
    file_util::create_dir_if_needed(rep_dir);
    if (out_path.empty()) {
      out_path = (rep_dir / fmt::format("mesh_audit_{}.txt", game)).string();
    }
    if (csv_path.empty()) {
      csv_path = (rep_dir / fmt::format("mesh_audit_{}.csv", game)).string();
    }
  }
  file_util::create_dir_if_needed_for_file(out_path);
  file_util::create_dir_if_needed_for_file(csv_path);

  if (!fs::exists(fr3_dir)) {
    fmt::print("error: fr3 dir not found: {}\n", fr3_dir);
    return 1;
  }

  // ---- enumerate the levels, sorted by filename so the sweep is deterministic ----
  std::vector<fs::path> fr3_files;
  if (!only_level.empty()) {
    fs::path p = fs::path(fr3_dir) / fmt::format("{}.fr3", only_level);
    if (!fs::exists(p)) {
      fmt::print("error: fr3 not found: {}\n", p.string());
      return 1;
    }
    fr3_files.push_back(p);
  } else {
    for (const auto& ent : fs::directory_iterator(fr3_dir)) {
      if (!ent.is_regular_file()) {
        continue;
      }
      if (ent.path().extension().string() == ".fr3") {
        fr3_files.push_back(ent.path());
      }
    }
    std::sort(fr3_files.begin(), fr3_files.end(),
              [](const fs::path& a, const fs::path& b) { return a.filename() < b.filename(); });
  }
  if (limit >= 0 && (int)fr3_files.size() > limit) {
    fr3_files.resize(limit);
  }

  if (fr3_files.empty()) {
    fmt::print("error: no .fr3 files found in {}\n", fr3_dir);
    return 1;
  }

  const auto cfg = tfrag3::mesh_consolidate_config_from_env();

  fmt::print("[mesh_audit] game={} fr3_dir={} levels={} out={} csv={}\n", game, fr3_dir,
             (u64)fr3_files.size(), out_path, csv_path);
  fmt::print("[mesh_audit] cfg weld={:.3f}m wide={:.3f}m crease={:.1f}deg colthr={} bits={}\n",
             cfg.weld_m, cfg.weld_m * cfg.wide_scale, cfg.crease_deg, cfg.col_blend_threshold,
             cfg.bits);

  // Fresh report + csv for this run (then appended level by level, so a long sweep that dies
  // half-way still leaves everything it managed to audit on disk).
  std::ofstream out(out_path, std::ios::out | std::ios::trunc);
  if (!out) {
    fmt::print("error: cannot open out file '{}'\n", out_path);
    return 1;
  }
  std::ofstream csv(csv_path, std::ios::out | std::ios::trunc);
  if (!csv) {
    fmt::print("error: cannot open csv file '{}'\n", csv_path);
    return 1;
  }
  csv << tfrag3::mesh_audit_csv_header();
  csv.flush();

  out << fmt::format("##### MESH AUDIT SWEEP game={} fr3_dir={} levels={} #####\n", game, fr3_dir,
                     (u64)fr3_files.size());
  out << fmt::format("##### cfg weld={:.3f}m wide={:.3f}m crease={:.1f}deg colthr={} bits={}\n",
                     cfg.weld_m, cfg.weld_m * cfg.wide_scale, cfg.crease_deg,
                     cfg.col_blend_threshold, cfg.bits);
  out.flush();

  std::vector<LevelResult> results;
  std::vector<LevelFailure> failures;
  results.reserve(fr3_files.size());

  u64 bakes_written = 0, bake_total_bytes = 0;
  u64 verify_ok_levels = 0, verify_mismatch_levels = 0;
  // ROUND 29 — MIRRORED TIE INSTANCE CENSUS rollup accumulators.
  u64 sum_mirror_matrices = 0, sum_mirror_matrices_mir = 0;
  u64 sum_mirror_groups = 0, sum_mirror_groups_mir = 0;
  u64 sum_mirror_verts = 0, sum_mirror_verts_mir = 0;
  u64 sum_mirror_groups_mir_nor = 0;

  const int n_total = (int)fr3_files.size();
  for (int k = 0; k < n_total; ++k) {
    const fs::path& fr3_path = fr3_files[k];
    const std::string level_name = fr3_path.stem().string();

    tfrag3::MeshAuditReport rep;
    rep.level_name = level_name;
    rep.game_name = game;
    bool ok = false;
    std::string bake_note;  // appended to the per-level progress line
    // ROUND 29 — MIRRORED TIE INSTANCE CENSUS. Filled inside the level scope (the level is freed
    // before the report text is formatted), so it has to live out here.
    tfrag3::TieMirrorCensus mirror;

    try {
      // Scope the (hundreds of MB) level so it is freed before the next one loads.
      {
        tfrag3::Level lev;
        load_level_fr3(fr3_path, lev);

        tfrag3::MeshBakeData bake;
        tfrag3::mesh_consolidate(lev, cfg, &rep, do_bake ? &bake : nullptr);
        // Pure measurement, before the level is freed. Never modifies the level.
        mirror = tfrag3::tie_mirror_census(lev);
        rep.game_name = game;
        if (rep.level_name.empty()) {
          rep.level_name = level_name;
        }

        if (do_bake) {
          const std::string bake_path =
              (fs::path(fr3_dir) / tfrag3::mesh_consolidate_bake_name(level_name)).string();
          u64 bake_bytes = 0;
          bool bake_ok = tfrag3::mesh_consolidate_bake_write(level_name, bake, bake_path);
          if (bake_ok) {
            std::error_code ec;
            const auto sz = fs::file_size(bake_path, ec);
            if (ec) {
              bake_ok = false;
            } else {
              bake_bytes = (u64)sz;
            }
          }
          if (bake_ok) {
            bakes_written++;
            bake_total_bytes += bake_bytes;
            bake_note += fmt::format(" bake={}", bake_bytes);
          } else {
            bake_note += " bake=FAILED";
          }

          if (verify_bake) {
            // THE ROUND-TRIP PROOF: a completely fresh copy of the same fr3, moved forward ONLY by
            // the sidecar, must equal the level the live pass just produced, field for field.
            u64 bad = 0;
            if (!bake_ok) {
              fmt::print("VERIFY-BAKE {}: MISMATCH bake_write_failed at -1/-1 (ok vs FAILED)\n",
                         level_name);
              bad = 1;
            } else {
              tfrag3::Level lev2;
              load_level_fr3(fr3_path, lev2);
              if (!tfrag3::mesh_consolidate_apply_bake(lev2, bake_path, /*do_shrub=*/true)) {
                fmt::print(
                    "VERIFY-BAKE {}: MISMATCH apply_bake_returned_false at -1/-1 (true vs false)\n",
                    level_name);
                bad = 1;
              } else {
                bad = verify_bake_compare(level_name, lev, lev2, 5);
              }
            }
            if (bad == 0) {
              verify_ok_levels++;
              fmt::print("VERIFY-BAKE {}: OK\n", level_name);
            } else {
              verify_mismatch_levels++;
            }
            fflush(stdout);
          }
        }
      }  // lev freed here
      ok = true;
    } catch (const std::exception& e) {
      failures.push_back({level_name, e.what()});
      fmt::print("[{}/{}] {} FAILED: {}\n", k + 1, n_total, level_name, e.what());
      out << fmt::format("===== MESH AUDIT level={} game={} FAILED: {} =====\n", level_name, game,
                         e.what());
      out.flush();
      continue;
    }

    if (ok) {
      out << tfrag3::format_mesh_audit(rep, cfg);
      // ROUND 29 — ONE physical line, alongside the other "-- SECTION --" lines. Kept here rather
      // than inside format_mesh_audit() because the census needs the LEVEL (already freed by then)
      // and not the report struct.
      out << fmt::format("-- TIE MIRRORED INSTANCES (round 29) -- matrices={} mirrored_matrices={} "
                         "groups={} mirrored_groups={} verts={} mirrored_verts={} "
                         "mirrored_groups_with_normals={}\n",
                         mirror.matrices, mirror.mirrored_matrices, mirror.groups,
                         mirror.mirrored_groups, mirror.verts, mirror.mirrored_verts,
                         mirror.mirrored_groups_with_normals);
      sum_mirror_matrices += mirror.matrices;
      sum_mirror_matrices_mir += mirror.mirrored_matrices;
      sum_mirror_groups += mirror.groups;
      sum_mirror_groups_mir += mirror.mirrored_groups;
      sum_mirror_verts += mirror.verts;
      sum_mirror_verts_mir += mirror.mirrored_verts;
      sum_mirror_groups_mir_nor += mirror.mirrored_groups_with_normals;
      out.flush();
      csv << tfrag3::mesh_audit_csv_row(rep);
      csv.flush();
      results.push_back({level_name, rep});

      fmt::print(
          "[{}/{}] {} tris={} coincident_unshared={} missed_welds_remaining={} nrm_max_after={:.3f} "
          "col_max_after={:.1f} pol_pairs={} pol_before={} pol_after={} true_after={} weak_after={} "
          "inward_after={} tanw={} noauth={} voldec={} raydec={} undec={} collincomp={} uvmir={} "
          "uvsplit={} elapsed={:.0f}ms{}\n",
          k + 1, n_total, level_name, rep.total.tris, rep.total.coincident_unshared,
          rep.total.missed_welds, rep.nrm_after.max, rep.col_after.max, rep.orient_pairs_total,
          rep.orient_pairs_inconsistent_before, rep.orient_pairs_inconsistent_after,
          rep.orient_pairs_true_inconsistent_after, rep.orient_pairs_weak_inconsistent_after,
          rep.orient_faces_inward_after, rep.orient_tangent_w_flipped,
          rep.orient_comps_no_authority, rep.orient_comps_volume_decided,
          rep.orient_comps_raycast_decided, rep.orient_comps_undecided,
          rep.orient_comps_collision_incompetent, rep.uv_tris_mirrored,
          rep.uv_verts_handedness_split, rep.elapsed_ms, bake_note);
      fflush(stdout);
    }
  }

  // ---------------------------------------------------------------------------------------------
  // ROLLUP. One physical line per fact (a validator greps this line-wise) — never wrap these.
  // ---------------------------------------------------------------------------------------------
  u64 sum_tris = 0, sum_open_raw = 0, sum_coincident = 0, sum_coincident_pairs = 0;
  u64 sum_open_by_group = 0, sum_missed = 0;
  double max_nrm_before = 0, max_nrm_after = 0, max_col_before = 0, max_col_after = 0;
  u64 levels_clean = 0;
  // round-22 authority-free polarity census
  u64 sum_pairs = 0, sum_pol_before = 0, sum_pol_after = 0, sum_tanw = 0;
  u64 sum_inward_after = 0, levels_pol_clean = 0, levels_inward_clean = 0;
  u64 sum_true = 0, sum_true_b = 0, sum_true_a = 0;
  u64 sum_weak = 0, sum_weak_b = 0, sum_weak_a = 0, levels_true_clean = 0;
  // round-28 second (geometric) orientation authority + UV determinant census
  u64 sum_comps = 0, sum_noauth = 0, sum_noauth_faces = 0;
  u64 sum_voldec = 0, sum_raydec = 0, sum_undec = 0;
  u64 sum_uv_tris = 0, sum_uv_mirrored = 0, sum_uv_degen = 0, sum_uv_split = 0;
  // round-29: components a collision normal reached but was NOT competent to judge
  u64 sum_collincomp = 0;
  for (const auto& r : results) {
    sum_collincomp += r.rep.orient_comps_collision_incompetent;
    sum_comps += r.rep.orient_components;
    sum_noauth += r.rep.orient_comps_no_authority;
    sum_noauth_faces += r.rep.orient_faces_no_authority;
    sum_voldec += r.rep.orient_comps_volume_decided;
    sum_raydec += r.rep.orient_comps_raycast_decided;
    sum_undec += r.rep.orient_comps_undecided;
    sum_uv_tris += r.rep.uv_tris_total;
    sum_uv_mirrored += r.rep.uv_tris_mirrored;
    sum_uv_degen += r.rep.uv_tris_degenerate;
    sum_uv_split += r.rep.uv_verts_handedness_split;
  }
  for (const auto& r : results) {
    sum_pairs += r.rep.orient_pairs_total;
    sum_pol_before += r.rep.orient_pairs_inconsistent_before;
    sum_pol_after += r.rep.orient_pairs_inconsistent_after;
    sum_tanw += r.rep.orient_tangent_w_flipped;
    sum_inward_after += r.rep.orient_faces_inward_after;
    sum_true += r.rep.orient_pairs_true_manifold;
    sum_true_b += r.rep.orient_pairs_true_inconsistent_before;
    sum_true_a += r.rep.orient_pairs_true_inconsistent_after;
    sum_weak += r.rep.orient_pairs_weak;
    sum_weak_b += r.rep.orient_pairs_weak_inconsistent_before;
    sum_weak_a += r.rep.orient_pairs_weak_inconsistent_after;
    if (r.rep.orient_pairs_inconsistent_after == 0) {
      levels_pol_clean++;
    }
    if (r.rep.orient_pairs_true_inconsistent_after == 0) {
      levels_true_clean++;
    }
    if (r.rep.orient_faces_inward_after == 0) {
      levels_inward_clean++;
    }
  }
  for (const auto& r : results) {
    sum_tris += r.rep.total.tris;
    sum_open_raw += r.rep.total.open_raw;
    sum_coincident += r.rep.total.coincident_unshared;
    sum_coincident_pairs += r.rep.total.coincident_unshared_pairs;
    sum_open_by_group += r.rep.total.open_by_group;
    sum_missed += r.rep.total.missed_welds;
    max_nrm_before = std::max(max_nrm_before, r.rep.nrm_before.max);
    max_nrm_after = std::max(max_nrm_after, r.rep.nrm_after.max);
    max_col_before = std::max(max_col_before, r.rep.col_before.max);
    max_col_after = std::max(max_col_after, r.rep.col_after.max);
    if (r.rep.total.missed_welds == 0) {
      levels_clean++;
    }
  }

  std::vector<const LevelResult*> worst;
  worst.reserve(results.size());
  for (const auto& r : results) {
    worst.push_back(&r);
  }
  std::sort(worst.begin(), worst.end(), [](const LevelResult* a, const LevelResult* b) {
    if (a->rep.total.missed_welds != b->rep.total.missed_welds) {
      return a->rep.total.missed_welds > b->rep.total.missed_welds;
    }
    return a->level < b->level;
  });

  std::string roll;
  roll += "##### MESH AUDIT ROLLUP #####\n";
  roll += fmt::format("LEVELS AUDITED: {}\n", (u64)results.size());
  roll += fmt::format("LEVELS FAILED: {}\n", (u64)failures.size());
  for (const auto& f : failures) {
    roll += fmt::format("FAILED LEVEL: {} : {}\n", f.level, f.what);
  }
  roll += fmt::format("TOTAL TRIS: {}\n", sum_tris);
  roll += fmt::format("TOTAL OPEN_RAW: {}\n", sum_open_raw);
  roll += fmt::format("TOTAL COINCIDENT_UNSHARED (BEFORE): {}\n", sum_coincident);
  roll += fmt::format("TOTAL COINCIDENT_UNSHARED_PAIRS: {}\n", sum_coincident_pairs);
  roll += fmt::format("TOTAL OPEN_BY_GROUP: {}\n", sum_open_by_group);
  roll += fmt::format("TOTAL MISSED_WELDS_REMAINING (AFTER): {}\n", sum_missed);
  roll += "WORST 10 LEVELS BY missed_welds_remaining:\n";
  for (size_t i = 0; i < worst.size() && i < 10; ++i) {
    roll += fmt::format("  {} missed={} of coincident_unshared={}\n", worst[i]->level,
                        worst[i]->rep.total.missed_welds, worst[i]->rep.total.coincident_unshared);
  }
  roll += fmt::format("MAX NRM DELTA BEFORE: {:.3f} deg\n", max_nrm_before);
  roll += fmt::format("MAX NRM DELTA AFTER: {:.3f} deg\n", max_nrm_after);
  roll += fmt::format("MAX COL DELTA BEFORE: {:.1f}\n", max_col_before);
  roll += fmt::format("MAX COL DELTA AFTER: {:.1f}\n", max_col_after);
  roll += fmt::format("PER-LEVEL COVERAGE: {}/{} levels audited, {} levels with "
                      "missed_welds_remaining == 0\n",
                      (u64)results.size(), (u64)fr3_files.size(), levels_clean);
  roll += fmt::format("TOTAL ORIENT_PAIRS: {}\n", sum_pairs);
  roll += fmt::format("TOTAL ORIENT_PAIRS_INCONSISTENT_BEFORE: {}\n", sum_pol_before);
  roll += fmt::format("TOTAL ORIENT_PAIRS_INCONSISTENT_AFTER: {}\n", sum_pol_after);
  roll += fmt::format("TOTAL ORIENT_TANGENT_W_FLIPPED: {}\n", sum_tanw);
  roll += fmt::format("TOTAL ORIENT_FACES_INWARD_AFTER: {}\n", sum_inward_after);
  roll += fmt::format("TOTAL ORIENT_PAIRS_TRUE_MANIFOLD: {} inconsistent_before={} "
                      "inconsistent_after={}\n",
                      sum_true, sum_true_b, sum_true_a);
  roll += fmt::format("TOTAL ORIENT_PAIRS_WEAK: {} inconsistent_before={} inconsistent_after={}\n",
                      sum_weak, sum_weak_b, sum_weak_a);
  roll += fmt::format("POLARITY COVERAGE: {}/{} levels with orient_pairs_inconsistent_after == 0, "
                      "{}/{} levels with orient_pairs_true_inconsistent_after == 0, "
                      "{}/{} levels with orient_faces_inward_after == 0\n",
                      levels_pol_clean, (u64)results.size(), levels_true_clean,
                      (u64)results.size(), levels_inward_clean, (u64)results.size());
  // ---- round-28: the SECOND (geometric) orientation authority, one physical line per fact ----
  roll += fmt::format("TOTAL ORIENT_COMPONENTS: {}\n", sum_comps);
  roll += fmt::format("TOTAL ORIENT_COMPS_NO_AUTHORITY: {}\n", sum_noauth);
  roll += fmt::format("TOTAL ORIENT_FACES_NO_AUTHORITY: {}\n", sum_noauth_faces);
  roll += fmt::format("TOTAL ORIENT_COMPS_VOLUME_DECIDED: {}\n", sum_voldec);
  roll += fmt::format("TOTAL ORIENT_COMPS_RAYCAST_DECIDED: {}\n", sum_raydec);
  roll += fmt::format("TOTAL ORIENT_COMPS_UNDECIDED: {} ORIENT_COLL_INCOMPETENT={}\n", sum_undec,
                      sum_collincomp);
  // ROUND 29 — MIRRORED TIE INSTANCE CENSUS, one physical line.
  roll += fmt::format("TIE_MIRROR_TOTAL matrices={} mirrored_matrices={} groups={} "
                      "mirrored_groups={} verts={} mirrored_verts={} "
                      "mirrored_groups_with_normals={}\n",
                      sum_mirror_matrices, sum_mirror_matrices_mir, sum_mirror_groups,
                      sum_mirror_groups_mir, sum_mirror_verts, sum_mirror_verts_mir,
                      sum_mirror_groups_mir_nor);
  roll += fmt::format("TOTAL UV_TRIS: {}\n", sum_uv_tris);
  roll += fmt::format("TOTAL UV_TRIS_MIRRORED: {}\n", sum_uv_mirrored);
  roll += fmt::format("TOTAL UV_TRIS_DEGENERATE: {}\n", sum_uv_degen);
  roll += fmt::format("TOTAL UV_VERTS_HANDEDNESS_SPLIT: {}\n", sum_uv_split);
  if (do_bake) {
    roll += fmt::format("BAKED SIDECARS: {} written, {} total\n", bakes_written, bake_total_bytes);
  }
  if (verify_bake) {
    roll += fmt::format("BAKE ROUND-TRIP: {} OK, {} MISMATCH\n", verify_ok_levels,
                        verify_mismatch_levels);
  }

  out << roll;
  out.flush();
  out.close();
  csv.close();

  fmt::print("\n{}", roll);
  fmt::print("[mesh_audit] wrote {}\n", out_path);
  fmt::print("[mesh_audit] wrote {}\n", csv_path);

  return results.empty() ? 1 : 0;
}
