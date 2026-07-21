// Grecharged-lightprobes: OFFLINE light-probe baker CLI (desktop only).
//
// Loads a level .fr3 (stock baked lighting + collision), runs the GL-free probe bake
// (probe_bake::bake_level) and writes a compact <level>.probes asset that the Android runtime
// loads (LOCAL irradiance-volume SH + reflection cubemaps). 100% programmatic — no manual placement.
//
// Usage: probe_bake <level-name> [--fr3-dir <dir>] [--out <path>] [--cell <m>] [--gain <f>]

#include <cstdio>
#include <cstdlib>
#include <filesystem>
#include <string>

#include "common/util/FileUtil.h"
#include "common/util/Serializer.h"
#include "common/util/compress.h"
#include "common/custom_data/Tfrag3Data.h"

#include "game/graphics/opengl_renderer/ProbeBakeCore.h"

#include "fmt/format.h"

static void usage() {
  fmt::print(
      "Usage: probe_bake <level-name> [--fr3-dir <dir>] [--out <path>] [--cell <m>] [--gain <f>]\n"
      "  <level-name>   e.g. village1 (loads <fr3-dir>/<level>.fr3)\n"
      "  --fr3-dir DIR  fr3 directory (default: <repo>/out/jak1/fr3)\n"
      "  --out PATH     output path (default: <fr3-dir>/<level>.probes)\n"
      "  --cell M       grid cell size in meters (default 4.0)\n"
      "  --gain F       probe irradiance gain (default 1.0)\n"
      "  --skygain F    sky/ground fill gain (default 1.0)\n"
      "  --dump-interiors PATH  load an existing .probes and print the interior-cell clusters\n"
      "                         (world coords in meters, warp-ready); no bake\n");
}

// --dump-interiors: connected-component clustering of the interior cells (26-neighbourhood) so the
// device A/B harness can warp to EVERY auto-detected interior, not just the one known hut.
static int dump_interiors(const std::string& probes_path) {
  probe_bake::ProbeGrid g;
  if (!probe_bake::load_probes(g, probes_path)) {
    fmt::print("error: load_probes failed on '{}'\n", probes_path);
    return 1;
  }
  struct IC {
    s16 ix, iy, iz;
    int cluster = -1;
  };
  std::vector<IC> ic;
  for (const auto& c : g.cells)
    if (c.interior)
      ic.push_back({c.ix, c.iy, c.iz, -1});
  fmt::print("[probe_dump] level='{}' dims={}x{}x{} cell={:.1f}m interior_cells={}\n", g.level_name,
             g.dims[0], g.dims[1], g.dims[2], g.cell_gu / 4096.f, ic.size());
  int n_clusters = 0;
  for (size_t seed = 0; seed < ic.size(); ++seed) {
    if (ic[seed].cluster >= 0)
      continue;
    int id = n_clusters++;
    std::vector<size_t> stack{seed};
    ic[seed].cluster = id;
    while (!stack.empty()) {
      size_t cur = stack.back();
      stack.pop_back();
      for (size_t j = 0; j < ic.size(); ++j) {
        if (ic[j].cluster >= 0)
          continue;
        if (std::abs(ic[j].ix - ic[cur].ix) <= 1 && std::abs(ic[j].iy - ic[cur].iy) <= 1 &&
            std::abs(ic[j].iz - ic[cur].iz) <= 1) {
          ic[j].cluster = id;
          stack.push_back(j);
        }
      }
    }
  }
  for (int id = 0; id < n_clusters; ++id) {
    double sx = 0, sy = 0, sz = 0;
    int n = 0;
    float min_y = 1e9f;
    for (const auto& c : ic)
      if (c.cluster == id) {
        sx += c.ix;
        sy += c.iy;
        sz += c.iz;
        min_y = std::min(min_y, (float)c.iy);
        n++;
      }
    auto wm = [&](double i, int axis) {
      return (g.origin_gu[axis] + i * g.cell_gu) / 4096.0;
    };
    fmt::print(
        "[probe_dump] interior_cluster id={} cells={} center_m=({:.1f},{:.1f},{:.1f}) floor_y_m={:.1f}\n",
        id, n, wm(sx / n, 0), wm(sy / n, 1), wm(sz / n, 2), wm(min_y, 1));
  }
  fmt::print("[probe_dump] clusters={} DONE.\n", n_clusters);
  return 0;
}

int main(int argc, char** argv) {
  std::string level_name, fr3_dir, out_path;
  probe_bake::BakeParams params;

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
    if (a == "--dump-interiors") {
      return dump_interiors(need_val("--dump-interiors"));
    } else if (a == "--fr3-dir") {
      fr3_dir = need_val("--fr3-dir");
    } else if (a == "--out") {
      out_path = need_val("--out");
    } else if (a == "--cell") {
      params.cell_m = std::stof(need_val("--cell"));
    } else if (a == "--gain") {
      params.probe_gain = std::stof(need_val("--gain"));
    } else if (a == "--skygain") {
      params.sky_gain = std::stof(need_val("--skygain"));
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

  if (fr3_dir.empty()) {
    if (!file_util::setup_project_path({})) {
      fmt::print("error: could not resolve the jak-project directory; pass --fr3-dir explicitly.\n");
      return 1;
    }
    fr3_dir = (file_util::get_jak_project_dir() / "out" / "jak1" / "fr3").string();
  }

  namespace fs = ghc::filesystem;
  fs::path fr3_path = fs::path(fr3_dir) / fmt::format("{}.fr3", level_name);
  if (out_path.empty())
    out_path = (fs::path(fr3_dir) / fmt::format("{}.probes", level_name)).string();

  if (!fs::exists(fr3_path)) {
    fmt::print("error: fr3 not found: {}\n", fr3_path.string());
    return 1;
  }
  u64 fr3_size = 0;
  try {
    fr3_size = (u64)fs::file_size(fr3_path);
  } catch (const std::exception& e) {
    fmt::print("error: cannot stat fr3 '{}': {}\n", fr3_path.string(), e.what());
    return 1;
  }

  fmt::print("[probe_bake] level='{}' fr3='{}' ({} bytes) out='{}' cell={}m gain={}\n", level_name,
             fr3_path.string(), fr3_size, out_path, params.cell_m, params.probe_gain);

  // Load + decompress + deserialize + unpack (mirror of Loader / grass_bake).
  tfrag3::Level lev;
  try {
    auto data = file_util::read_binary_file(fr3_path);
    auto decomp = compression::decompress_zstd(data.data(), data.size());
    Serializer ser(decomp.data(), decomp.size());
    lev.serialize(ser);
    for (auto& tie_tree : lev.tie_trees)
      for (auto& tree : tie_tree)
        tree.unpack();
    for (auto& t_tree : lev.tfrag_trees)
      for (auto& tree : t_tree)
        tree.unpack();
    for (auto& tree : lev.shrub_trees)
      tree.unpack();
  } catch (const std::exception& e) {
    fmt::print("error: failed to load/deserialize fr3: {}\n", e.what());
    return 1;
  }

  probe_bake::ProbeGrid grid = probe_bake::bake_level(lev, level_name, fr3_size, params);
  if (grid.n_valid == 0) {
    fmt::print("error: bake produced 0 probes\n");
    return 1;
  }

  if (!probe_bake::save_probes(grid, out_path)) {
    fmt::print("error: save_probes failed to write '{}'\n", out_path);
    return 1;
  }
  u64 out_size = 0;
  try {
    out_size = (u64)fs::file_size(out_path);
  } catch (...) {
  }

  // Round-trip self-check.
  probe_bake::ProbeGrid rt;
  if (!probe_bake::load_probes(rt, out_path)) {
    fmt::print("error: round-trip load_probes failed on '{}'\n", out_path);
    return 1;
  }
  bool same = rt.n_valid == grid.n_valid && rt.n_interior == grid.n_interior &&
              rt.n_refl == grid.n_refl && rt.cells.size() == grid.cells.size();

  // Report the highest and lowest DC (average irradiance) probe to prove local variation, and a
  // representative interior probe (near Samos's hut).
  auto dc = [](const probe_bake::ProbeCell& c) {
    // slot 4 ~ midday; DC luminance
    float* s = (float*)c.sh[4][0];
    return 0.299f * s[0] + 0.587f * s[1] + 0.114f * s[2];
  };
  float lo = 1e9f, hi = -1e9f;
  for (const auto& c : grid.cells) {
    float d = dc(c);
    lo = std::min(lo, d);
    hi = std::max(hi, d);
  }

  fmt::print("\n[probe_bake] ===== SUMMARY '{}' =====\n", level_name);
  fmt::print("[probe_bake] grid dims={}x{}x{} cell={}m origin_m=({:.1f},{:.1f},{:.1f})\n",
             grid.dims[0], grid.dims[1], grid.dims[2], params.cell_m, grid.origin_gu[0] / 4096.0f,
             grid.origin_gu[1] / 4096.0f, grid.origin_gu[2] / 4096.0f);
  fmt::print("[probe_bake] probes={} interior={} reflection_anchors={}\n", grid.n_valid,
             grid.n_interior, grid.n_refl);
  fmt::print("[probe_bake] midday DC luminance range: min={:.4f} max={:.4f} (local variation)\n", lo,
             hi);
  fmt::print("[probe_bake] wrote '{}' ({} bytes compressed) round-trip={}\n", out_path, out_size,
             same ? "IDENTICAL" : "MISMATCH");
  if (!same)
    return 1;
  fmt::print("[probe_bake] DONE.\n");
  return 0;
}
