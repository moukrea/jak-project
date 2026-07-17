// Grecharged-grass-precompute-mode: OFFLINE grass baker CLI (desktop only).
//
// Loads a level .fr3, runs the GL-free grass placement scan (grass_bake::scan_level)
// at the slider-max density, and writes a compact <level>.grassbake table file that
// the Android runtime loads instead of doing the (ANR-inducing) live scan.
//
// Usage: grass_bake <level-name> [--fr3-dir <dir>] [--out <path>] [--density <pct>]

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>

#include "common/util/FileUtil.h"
#include "common/util/Serializer.h"
#include "common/util/compress.h"
#include "common/custom_data/Tfrag3Data.h"

#include "game/graphics/opengl_renderer/GrassBakeCore.h"

#include "fmt/format.h"

// NOTE: FileUtil.h already defines `namespace fs = ghc::filesystem`; reuse it.

static void usage() {
  fmt::print(
      "Usage: grass_bake <level-name> [--fr3-dir <dir>] [--out <path>] [--density <pct>]\n"
      "  <level-name>   e.g. training (loads <fr3-dir>/<level>.fr3)\n"
      "  --fr3-dir DIR  fr3 directory (default: <repo>/out/jak1/fr3)\n"
      "  --out PATH     output path (default: <fr3-dir>/<level>.grassbake)\n"
      "  --density PCT  bake candidate density (default: 250 = slider max)\n"
      "  --dump PREFIX  write PREFIX_instances.csv + PREFIX_tris.csv of the ship-default\n"
      "                 (slider 150) expansion, for offline placement analysis\n");
}

int main(int argc, char** argv) {
  std::string level_name;
  std::string fr3_dir;
  std::string out_path;
  std::string dump_prefix;
  float density = 250.0f;  // slider maximum; runtime slider densities are exact prefixes

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
    if (a == "--fr3-dir") {
      fr3_dir = need_val("--fr3-dir");
    } else if (a == "--out") {
      out_path = need_val("--out");
    } else if (a == "--dump") {
      dump_prefix = need_val("--dump");
    } else if (a == "--density") {
      density = std::stof(need_val("--density"));
    } else if (a == "-h" || a == "--help") {
      usage();
      return 0;
    } else if (!a.empty() && a[0] == '-') {
      fmt::print("error: unknown option '{}'\n", a);
      usage();
      return 2;
    } else if (level_name.empty()) {
      level_name = a;
    } else {
      fmt::print("error: unexpected extra argument '{}'\n", a);
      usage();
      return 2;
    }
  }

  if (level_name.empty()) {
    fmt::print("error: missing <level-name>\n");
    usage();
    return 2;
  }

  // Resolve the fr3 directory. Default = <repo>/out/jak1/fr3 via the project dir.
  if (fr3_dir.empty()) {
    if (!file_util::setup_project_path({})) {
      fmt::print(
          "error: could not resolve the jak-project directory; pass --fr3-dir explicitly.\n");
      return 1;
    }
    fr3_dir = (file_util::get_jak_project_dir() / "out" / "jak1" / "fr3").string();
  }

  fs::path fr3_path = fs::path(fr3_dir) / fmt::format("{}.fr3", level_name);
  if (out_path.empty()) {
    out_path = (fs::path(fr3_dir) / fmt::format("{}.grassbake", level_name)).string();
  }

  if (!fs::exists(fr3_path)) {
    fmt::print("error: fr3 not found: {}\n", fr3_path.string());
    return 1;
  }

  // fr3_size MUST be the on-disk (compressed) byte size — the runtime validates the
  // bake against std::filesystem::file_size of the fr3.
  u64 fr3_size = 0;
  try {
    fr3_size = (u64)fs::file_size(fr3_path);
  } catch (const std::exception& e) {
    fmt::print("error: cannot stat fr3 '{}': {}\n", fr3_path.string(), e.what());
    return 1;
  }

  fmt::print("[grass_bake] level='{}' fr3='{}' ({} bytes) out='{}' density={}\n", level_name,
             fr3_path.string(), fr3_size, out_path, density);

  // Load + decompress + deserialize the level (mirror of Loader.cpp:190-206).
  tfrag3::Level lev;
  try {
    auto data = file_util::read_binary_file(fr3_path);
    auto decomp = compression::decompress_zstd(data.data(), data.size());
    Serializer ser(decomp.data(), decomp.size());
    lev.serialize(ser);
    // The scan reads tree.unpacked.{vertices,indices}, which the packed fr3 leaves
    // empty until unpack() runs (mirror of Loader.cpp:213-229). Without this the
    // scan sees zero vertices and matches zero grass draws.
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
  } catch (const std::exception& e) {
    fmt::print("error: failed to load/deserialize fr3: {}\n", e.what());
    return 1;
  }

  // Scan (prints the [recharged-grass] instrumentation lines).
  grass_bake::BakeData bake;
  try {
    bake = grass_bake::scan_level(lev, level_name, fr3_size,
                                  {density, grass_bake::FLOOR_GAP_M});
  } catch (const std::exception& e) {
    fmt::print("error: scan_level failed: {}\n", e.what());
    return 1;
  }

  // Save.
  if (!grass_bake::save_bake(bake, out_path)) {
    fmt::print("error: save_bake failed to write '{}'\n", out_path);
    return 1;
  }

  u64 out_size = 0;
  try {
    out_size = (u64)fs::file_size(out_path);
  } catch (...) {
  }

  // Self-check expands at the shipping default (150) and at the bake density.
  auto e150 = grass_bake::expand(bake, 150.0f);
  auto eBake = grass_bake::expand(bake, density);

  fmt::print("\n[grass_bake] ===== BAKE SUMMARY '{}' =====\n", level_name);
  fmt::print("[grass_bake] scan: considered_draws={} tie_draws={} tris_kept={} giant_tris={} "
             "max_area={:.1f} m2\n",
             bake.stats.considered_draws, bake.stats.tie_draws, bake.stats.tris_kept,
             bake.stats.giant_tris, bake.stats.max_area);
  fmt::print("[grass_bake] scan: total_area={:.1f} m2  floor_gap={:.2f} m  bake_density={:.1f}\n",
             bake.total_area_m2, bake.floor_gap_m, bake.bake_density_pct);
  fmt::print("[grass_bake] tables: ntris={} ncand={} (keep bytes={}, rim_q entries={})\n",
             (u64)bake.tris.size(), (u64)bake.keep.size(), (u64)bake.keep.size(),
             (u64)bake.rim_q.size());
  fmt::print("[grass_bake] expand @slider=150 (ship default): instances={} scatter_kept={} "
             "occ_culled={}\n",
             (u64)e150.instances.size(), e150.scatter_kept, e150.occ_culled);
  fmt::print("[grass_bake] expand @slider={:.0f} (bake density): instances={} scatter_kept={} "
             "occ_culled={}\n",
             density, (u64)eBake.instances.size(), eBake.scatter_kept, eBake.occ_culled);
  fmt::print("[grass_bake] wrote '{}' ({} bytes compressed)\n", out_path, out_size);

  // Grecharged-grass-overhang4: offline placement dump (ship-default expansion) so the banding /
  // seam / tip-violation metrics can be computed by .autoport analysis and compared across
  // placement generations (round-3 rows vs round-4 scatter) with ONE metric implementation.
  if (!dump_prefix.empty()) {
    FILE* fi = std::fopen((dump_prefix + "_instances.csv").c_str(), "w");
    FILE* ft = std::fopen((dump_prefix + "_tris.csv").c_str(), "w");
    if (!fi || !ft) {
      fmt::print("error: --dump cannot open '{}_*.csv'\n", dump_prefix);
      return 1;
    }
    std::fprintf(fi, "idx,px,py,pz,h,yaw,tint,curve,phase,gspare,nx,ny,nz,nspare,tri\n");
    for (size_t i = 0; i < e150.instances.size(); ++i) {
      const auto& g = e150.instances[i];
      std::fprintf(fi, "%zu,%.3f,%.3f,%.3f,%.3f,%.5f,%.5f,%.5f,%.5f,%.3f,%.6f,%.6f,%.6f,%.5f,%u\n",
                   i, g.px, g.py, g.pz, g.h, g.yaw, g.tint, g.curve, g.phase, g.gspare, g.nx, g.ny,
                   g.nz, g.nspare, e150.inst_tri[i]);
    }
    std::fprintf(ft, "idx,p0x,p0y,p0z,e1x,e1y,e1z,e2x,e2y,e2z,nx,ny,nz,flags,area_m2\n");
    for (size_t t = 0; t < bake.tris.size(); ++t) {
      const auto& tr = bake.tris[t];
      std::fprintf(ft, "%zu,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.3f,%.6f,%.6f,%.6f,%u,%.4f\n",
                   t, tr.p0[0], tr.p0[1], tr.p0[2], tr.e1[0], tr.e1[1], tr.e1[2], tr.e2[0],
                   tr.e2[1], tr.e2[2], tr.nx, tr.ny, tr.nz, tr.flags, tr.area_m2);
    }
    std::fclose(fi);
    std::fclose(ft);
    fmt::print("[grass_bake] dumped {} instances (droop_start={} trans_start={}) + {} tris to "
               "'{}_*.csv'\n",
               (u64)e150.instances.size(), e150.droop_start, e150.trans_start,
               (u64)bake.tris.size(), dump_prefix);
  }

  // Grecharged-grass-overhang: round-trip self-check — load the written bake back and prove the
  // expanded field (walkable + droop tail) is byte-identical to the in-memory scan's expansion.
  {
    grass_bake::BakeData rt;
    if (!grass_bake::load_bake(rt, out_path)) {
      fmt::print("error: round-trip load_bake failed on '{}'\n", out_path);
      return 1;
    }
    auto rtE = grass_bake::expand(rt, 150.0f);
    bool same = rtE.instances.size() == e150.instances.size() &&
                rtE.droop_start == e150.droop_start &&
                (rtE.instances.empty() ||
                 std::memcmp(rtE.instances.data(), e150.instances.data(),
                             rtE.instances.size() * sizeof(grass_bake::GrassInstance)) == 0);
    fmt::print("[grass_bake] round-trip @150: {} (instances={} droop_start={} droop_tris={})\n",
               same ? "IDENTICAL" : "MISMATCH", (u64)rtE.instances.size(), rtE.droop_start,
               (u64)rt.droop.size());
    if (!same) {
      return 1;
    }
  }
  fmt::print("[grass_bake] DONE.\n");
  return 0;
}
