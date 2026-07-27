// Grecharged-mesh-browser: OFFLINE INDEX EXPORTER.
//
// The debug MESH BROWSER (owner's direct request) needs, per level, a compact catalogue of every
// displaceable mesh so the game can: list them worst-grade-first, filter them, and warp+auto-frame
// the camera onto any one of them. tools/tess_sign already computes exactly this data and writes it
// as a wide per-level CSV (row, shell, system, material, tex_id, the A_sign/B_disp grades, the world
// centroid and the AABB). This tool does ONE thing: it distils that CSV down to the handful of
// columns the on-device browser needs, in a tiny fixed-width text format the game parses at load.
//
// Why a SEPARATE tool and not a --export flag inside tess_sign: a parallel PBR round owns
// tess_sign/main.cpp + MeshConsolidate.cpp + the tess shaders. This converter never touches any of
// them — it only reads the CSV they already emit, so the two rounds cannot collide.
//
// OUTPUT (one file per level, e.g. mesh_index_village1.txt). Plain ASCII, LF-terminated:
//
//   MESHIDX 1 <level-name> <count>
//   <idx> <system> <tex_id> <shell> <graded> <A_sign_x100> <B_disp_x100>
//         <cx> <cy> <cz> <lox> <loy> <loz> <hix> <hiy> <hiz> <material>   (all one line)
//
// * one HEADER line then <count> mesh lines, already sorted worst-grade-first (the CSV row order is
//   the tool's worst-first sort: ascending A_sign, then ascending B_disp, then bigger mesh first).
// * system: 0 = TFRAG, 1 = TIE.
// * graded: 1 if the offline SIGN test produced a grade for this mesh (sign_den > 0), else 0.
//   TIE meshes use per-pixel POM and are ungraded by the sign test (graded 0) — the browser shows
//   "n/a" for them, it does NOT read that as "no PBR maps". EVERY row in the CSV is a displaceable
//   material by construction (tess_sign only emits a row when a <material>_height.png exists), so
//   presence-in-index == has PBR/recharged maps. There is no separate has-maps flag needed.
// * A_sign_x100 / B_disp_x100: the two grades, integer percent ×100 (so 100.00% -> 10000); -1 when
//   ungraded. The worst-first key the browser sorts on is simply the line order (already worst-first),
//   but the raw grades travel too so the browser can DISPLAY them (the confirm/refute loop) and can
//   re-sort or filter on them.
// * cx..hiz: world metres (centroid then AABB lo then AABB hi), for warp + bounding-box auto-frame.
// * material: the runtime texture/material debug_name (last field: it can contain no spaces, so the
//   parser reads it as the tail of the line). This is what the browser prints on screen and exports
//   to files/mesh_select.txt for the owner to quote back.
//
// Usage: mesh_index --csv <tess_sign.csv> --level <name> --out <path>
//        mesh_index --csv <tess_sign.csv> --level <name>            (out defaults next to csv)

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace {

struct Row {
  int system = 0;
  int tex_id = 0;
  int shell = 0;
  bool graded = false;
  double a_sign = -1.0;  // percent, or <0 when ungraded
  double b_disp = -1.0;
  double cx = 0, cy = 0, cz = 0;
  double lox = 0, loy = 0, loz = 0;
  double hix = 0, hiy = 0, hiz = 0;
  std::string material;
};

// Split a CSV line into fields. The material name never contains a comma (verified against the
// tess_sign output), so a plain comma split is safe.
std::vector<std::string> split_csv(const std::string& line) {
  std::vector<std::string> out;
  std::string cur;
  for (char c : line) {
    if (c == ',') {
      out.push_back(cur);
      cur.clear();
    } else if (c != '\r' && c != '\n') {
      cur.push_back(c);
    }
  }
  out.push_back(cur);
  return out;
}

double to_d(const std::string& s, double dflt) {
  if (s.empty()) {
    return dflt;
  }
  try {
    return std::stod(s);
  } catch (...) {
    return dflt;
  }
}

int to_i(const std::string& s, int dflt) {
  if (s.empty()) {
    return dflt;
  }
  try {
    return std::stoi(s);
  } catch (...) {
    return dflt;
  }
}

void usage() {
  std::printf(
      "Usage: mesh_index --csv <tess_sign.csv> --level <name> [--out <path>]\n"
      "  Distils a tess_sign per-level CSV into the compact mesh-browser index.\n"
      "  --csv    the tess_sign CSV to read (required)\n"
      "  --level  the level name written into the header (required)\n"
      "  --out    output path (default: mesh_index_<level>.txt next to the csv)\n");
}

}  // namespace

int main(int argc, char** argv) {
  std::string csv_path, level, out_path;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto next = [&](const char* what) -> std::string {
      if (i + 1 >= argc) {
        std::fprintf(stderr, "mesh_index: %s needs a value\n", what);
        std::exit(2);
      }
      return argv[++i];
    };
    if (a == "--csv") {
      csv_path = next("--csv");
    } else if (a == "--level") {
      level = next("--level");
    } else if (a == "--out") {
      out_path = next("--out");
    } else if (a == "-h" || a == "--help") {
      usage();
      return 0;
    } else {
      std::fprintf(stderr, "mesh_index: unknown arg %s\n", a.c_str());
      usage();
      return 2;
    }
  }
  if (csv_path.empty() || level.empty()) {
    usage();
    return 2;
  }
  if (out_path.empty()) {
    auto slash = csv_path.find_last_of("/\\");
    std::string dir = (slash == std::string::npos) ? std::string() : csv_path.substr(0, slash + 1);
    out_path = dir + "mesh_index_" + level + ".txt";
  }

  std::ifstream in(csv_path);
  if (!in) {
    std::fprintf(stderr, "mesh_index: cannot open %s\n", csv_path.c_str());
    return 1;
  }

  // Read the header, resolve column positions by NAME (robust to CSV column reordering).
  std::string header;
  if (!std::getline(in, header)) {
    std::fprintf(stderr, "mesh_index: empty CSV\n");
    return 1;
  }
  auto cols = split_csv(header);
  auto col = [&](const char* name) -> int {
    for (size_t i = 0; i < cols.size(); i++) {
      if (cols[i] == name) {
        return static_cast<int>(i);
      }
    }
    std::fprintf(stderr, "mesh_index: CSV lacks column '%s'\n", name);
    std::exit(1);
  };
  const int c_shell = col("shell");
  const int c_system = col("system");
  const int c_material = col("material");
  const int c_tex = col("tex_id");
  const int c_asign = col("A_sign_pct");
  const int c_bdisp = col("B_disp_pct");
  const int c_den = col("sign_den");
  const int c_cx = col("centroid_x_m");
  const int c_cy = col("centroid_y_m");
  const int c_cz = col("centroid_z_m");
  const int c_lox = col("aabb_lo_x_m");
  const int c_loy = col("aabb_lo_y_m");
  const int c_loz = col("aabb_lo_z_m");
  const int c_hix = col("aabb_hi_x_m");
  const int c_hiy = col("aabb_hi_y_m");
  const int c_hiz = col("aabb_hi_z_m");

  std::vector<Row> rows;
  std::string line;
  while (std::getline(in, line)) {
    if (line.empty()) {
      continue;
    }
    auto f = split_csv(line);
    int need = std::max({c_shell, c_system, c_material, c_tex, c_asign, c_bdisp, c_den, c_cx, c_cy,
                         c_cz, c_lox, c_loy, c_loz, c_hix, c_hiy, c_hiz});
    if (static_cast<int>(f.size()) <= need) {
      continue;  // malformed / short line
    }
    Row r;
    r.shell = to_i(f[c_shell], 0);
    r.system = (f[c_system] == "TIE") ? 1 : 0;
    r.material = f[c_material];
    r.tex_id = to_i(f[c_tex], 0);
    int den = to_i(f[c_den], 0);
    r.graded = den > 0 && !f[c_asign].empty();
    r.a_sign = r.graded ? to_d(f[c_asign], -1.0) : -1.0;
    r.b_disp = to_d(f[c_bdisp], -1.0);
    r.cx = to_d(f[c_cx], 0);
    r.cy = to_d(f[c_cy], 0);
    r.cz = to_d(f[c_cz], 0);
    r.lox = to_d(f[c_lox], 0);
    r.loy = to_d(f[c_loy], 0);
    r.loz = to_d(f[c_loz], 0);
    r.hix = to_d(f[c_hix], 0);
    r.hiy = to_d(f[c_hiy], 0);
    r.hiz = to_d(f[c_hiz], 0);
    if (r.material.empty()) {
      r.material = "?";
    }
    rows.push_back(std::move(r));
  }

  // The CSV is already worst-first (tess_sign sorts ascending A_sign, then ascending B_disp, then
  // bigger mesh first). Preserve that order verbatim so the browser's line order IS the worst-first
  // order without re-deriving it on device.

  std::ofstream out(out_path);
  if (!out) {
    std::fprintf(stderr, "mesh_index: cannot write %s\n", out_path.c_str());
    return 1;
  }
  out << "MESHIDX 1 " << level << " " << rows.size() << "\n";
  int idx = 0;
  for (const auto& r : rows) {
    int a100 = r.graded ? static_cast<int>(r.a_sign * 100.0 + 0.5) : -1;
    int b100 = (r.b_disp >= 0.0) ? static_cast<int>(r.b_disp * 100.0 + 0.5) : -1;
    // Fixed field order; material LAST (spaceless, read as the line tail).
    char buf[512];
    std::snprintf(buf, sizeof(buf),
                  "%d %d %d %d %d %d %d %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %.3f %s\n", idx,
                  r.system, r.tex_id, r.shell, r.graded ? 1 : 0, a100, b100, r.cx, r.cy, r.cz, r.lox,
                  r.loy, r.loz, r.hix, r.hiy, r.hiz, r.material.c_str());
    out << buf;
    idx++;
  }
  out.close();

  std::printf("mesh_index: wrote %zu meshes for level '%s' -> %s\n", rows.size(), level.c_str(),
              out_path.c_str());
  return 0;
}
