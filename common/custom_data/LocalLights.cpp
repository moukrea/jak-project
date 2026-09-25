// lighting-local-lights (SPEC-refonte-lumiere §5.3.8, §5.7.1) : lumieres locales.

#include "LocalLights.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <map>
#include <set>
#include <sstream>

#include "common/common_types.h"
#include "common/custom_data/Tfrag3Data.h"
#include "common/log/log.h"
#include "common/util/FileUtil.h"

namespace local_lights {

namespace {
constexpr float kMeter = 4096.f;

std::string lower(const std::string& s) {
  std::string o = s;
  std::transform(o.begin(), o.end(), o.begin(), [](unsigned char c) { return std::tolower(c); });
  return o;
}

std::vector<std::string> split_ws(const std::string& s) {
  std::vector<std::string> out;
  std::istringstream ss(s);
  std::string tok;
  while (ss >> tok) out.push_back(tok);
  return out;
}

bool parse_f3(const std::string& s, float out[3]) {
  int idx = 0;
  size_t p = 0;
  while (idx < 3) {
    size_t c = s.find(',', p);
    std::string piece = s.substr(p, c == std::string::npos ? std::string::npos : c - p);
    if (piece.empty()) return false;
    try {
      out[idx] = std::stof(piece);
    } catch (...) {
      return false;
    }
    idx++;
    if (c == std::string::npos) break;
    p = c + 1;
  }
  return idx == 3;
}

bool parse_f2(const std::string& s, float out[2]) {
  size_t c = s.find(',');
  if (c == std::string::npos) return false;
  try {
    out[0] = std::stof(s.substr(0, c));
    out[1] = std::stof(s.substr(c + 1));
  } catch (...) {
    return false;
  }
  return true;
}

// meme algebre minimale que tools/light_bake (pas partagee : ce fichier n'a pas acces a main.cpp)
struct V3 {
  float x = 0, y = 0, z = 0;
  V3() = default;
  V3(float a, float b, float c) : x(a), y(b), z(c) {}
  V3 operator+(const V3& o) const { return {x + o.x, y + o.y, z + o.z}; }
  V3 operator-(const V3& o) const { return {x - o.x, y - o.y, z - o.z}; }
  V3 operator*(float s) const { return {x * s, y * s, z * s}; }
};
V3 cross(const V3& a, const V3& b) {
  return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
float len(const V3& a) {
  return std::sqrt(a.x * a.x + a.y * a.y + a.z * a.z);
}

template <typename F>
void for_each_tri(const u32* idx, size_t n, bool use_strips, F&& emit) {
  if (use_strips) {
    u32 a = UINT32_MAX, b = UINT32_MAX, k = 0;
    for (size_t i = 0; i < n; i++) {
      u32 vi = idx[i];
      if (vi == UINT32_MAX) {
        a = b = UINT32_MAX;
        k = 0;
        continue;
      }
      if (a != UINT32_MAX && b != UINT32_MAX) {
        if (k & 1)
          emit(b, a, vi);
        else
          emit(a, b, vi);
      }
      a = b;
      b = vi;
      k++;
    }
  } else {
    for (size_t t = 0; t + 2 < n; t += 3) {
      if (idx[t] != UINT32_MAX && idx[t + 1] != UINT32_MAX && idx[t + 2] != UINT32_MAX) {
        emit(idx[t], idx[t + 1], idx[t + 2]);
      }
    }
  }
}

struct InstanceAcc {
  std::string proto;
  double area_sum = 0;
  V3 centroid_wsum{0, 0, 0};
  float bmin[3] = {1e30f, 1e30f, 1e30f};
  float bmax[3] = {-1e30f, -1e30f, -1e30f};
  double col_wsum[3] = {0, 0, 0};
  double col_w = 0;
  bool used_vertex_color_fallback = false;
};

}  // namespace

std::string default_lexicon_path() {
  auto path = file_util::get_recharged_assets_dir() / "light_emitters.txt";
  auto ext_dir = file_util::get_external_recharged_assets_dir();
  if (ext_dir) {
    auto ext_path = *ext_dir / "light_emitters.txt";
    if (file_util::file_exists(ext_path.string())) {
      path = ext_path;
    }
  }
  return path.string();
}

Lexicon load_lexicon(const std::string& path) {
  Lexicon lex;
  lex.path = path;
  if (!file_util::file_exists(path)) {
    lg::warn(
        "[local-lights] LEXIQUE ABSENT : {} — AUCUN prototype TIE ne sera juge lumiere locale, "
        "tous les candidats tomberont dans lights_unjudged. Ce n'est pas un defaut de rendu, "
        "c'est un asset manquant.",
        path);
    return lex;
  }
  lex.loaded = true;
  std::string text = file_util::read_text_file(path);
  std::istringstream ss(text);
  std::string line;
  int lineno = 0;
  while (std::getline(ss, line)) {
    lineno++;
    size_t b = line.find_first_not_of(" \t\r\n");
    if (b == std::string::npos || line[b] == '#') {
      continue;
    }
    auto toks = split_ws(line);
    if (toks.empty()) continue;
    if (toks[0] == "LUMIERE") {
      if (toks.size() < 2) {
        lex.bad_lines++;
        lg::warn("[local-lights] {}:{} LUMIERE malformee : « {} »", path, lineno, line);
        continue;
      }
      const std::string& proto = toks[1];
      if (lex.judged(proto)) {
        lex.bad_lines++;
        lg::warn("[local-lights] {}:{} prototype « {} » deja juge, ligne ignoree", path, lineno,
                  proto);
        continue;
      }
      Rule r;
      r.proto = proto;
      bool have_type = false, have_rgb = false, have_cd = false, have_r = false;
      bool ok = true;
      for (size_t i = 2; i < toks.size(); i++) {
        size_t eq = toks[i].find('=');
        if (eq == std::string::npos) {
          ok = false;
          break;
        }
        std::string k = toks[i].substr(0, eq);
        std::string v = toks[i].substr(eq + 1);
        if (k == "type") {
          if (v == "point")
            r.type = Type::Point;
          else if (v == "spot")
            r.type = Type::Spot;
          else if (v == "area")
            r.type = Type::Area;
          else {
            ok = false;
            break;
          }
          have_type = true;
        } else if (k == "rgb") {
          if (v == "auto") {
            r.rgb_auto = true;
            have_rgb = true;
          } else {
            float c[3];
            if (!parse_f3(v, c)) {
              ok = false;
              break;
            }
            r.rgb[0] = c[0] / 255.f;
            r.rgb[1] = c[1] / 255.f;
            r.rgb[2] = c[2] / 255.f;
            have_rgb = true;
          }
        } else if (k == "cd") {
          try {
            r.cd = std::stof(v);
          } catch (...) {
            ok = false;
            break;
          }
          have_cd = true;
        } else if (k == "r") {
          try {
            r.r = std::stof(v);
          } catch (...) {
            ok = false;
            break;
          }
          have_r = true;
        } else if (k == "off") {
          if (!parse_f3(v, r.off)) {
            ok = false;
            break;
          }
          r.has_off = true;
        } else if (k == "cone") {
          float c[2];
          if (!parse_f2(v, c)) {
            ok = false;
            break;
          }
          r.cone_inner_deg = c[0];
          r.cone_outer_deg = c[1];
        } else if (k == "flicker") {
          try {
            int f = std::stoi(v);
            if (f < 0 || f > 7) {
              ok = false;
              break;
            }
            r.flicker = (uint8_t)f;
          } catch (...) {
            ok = false;
            break;
          }
        } else {
          ok = false;
          break;
        }
      }
      if (!ok || !have_type || !have_rgb || !have_cd || !have_r) {
        lex.bad_lines++;
        lg::warn("[local-lights] {}:{} LUMIERE malformee (cle inconnue ou champ manquant) : « {} »",
                  path, lineno, line);
        continue;
      }
      lex.lights[proto] = r;
    } else if (toks[0] == "EXCLU") {
      if (toks.size() < 3) {
        lex.bad_lines++;
        lg::warn("[local-lights] {}:{} EXCLU sans raison : « {} »", path, lineno, line);
        continue;
      }
      const std::string& proto = toks[1];
      if (lex.judged(proto)) {
        lex.bad_lines++;
        lg::warn("[local-lights] {}:{} prototype « {} » deja juge, ligne ignoree", path, lineno,
                  proto);
        continue;
      }
      size_t raison_start = line.find(toks[2]);
      std::string raison = raison_start == std::string::npos ? "" : line.substr(raison_start);
      if (raison.empty()) {
        lex.bad_lines++;
        lg::warn("[local-lights] {}:{} EXCLU sans raison : « {} »", path, lineno, line);
        continue;
      }
      lex.excluded[proto] = raison;
    } else {
      lex.bad_lines++;
      lg::warn("[local-lights] {}:{} ligne inconnue (ni LUMIERE ni EXCLU) : « {} »", path, lineno,
                line);
    }
  }
  return lex;
}

bool is_candidate(const std::string& proto) {
  static const char* kTokens[] = {"light",  "lite",  "lamp",     "lant",  "torch",
                                   "glow",   "flame", "candle",   "brazier", "spotlight",
                                   "neon"};
  std::string p = lower(proto);
  for (const char* t : kTokens) {
    if (p.find(t) != std::string::npos) return true;
  }
  return false;
}

uint32_t fnv1a32(const std::string& s) {
  uint32_t h = 2166136261u;
  for (unsigned char c : s) {
    h ^= c;
    h *= 16777619u;
  }
  return h;
}

std::vector<Light> extract(const tfrag3::Level& lev, const Lexicon& lex, ExtractStats* st) {
  ExtractStats local;
  ExtractStats& stats = st ? *st : local;
  stats = ExtractStats{};

  std::vector<Light> out;
  if (lev.tie_trees.empty()) {
    return out;
  }

  // moyenne de texture (RGB, texels alpha>0), ponderee par la surface, en cache par index de
  // texture. Repli explicite sur la couleur de sommet si le fr3 ne porte pas la texture (index
  // hors bornes ou negatif = emplacement de texture animee).
  std::unordered_map<int, std::array<float, 3>> tex_avg_cache;
  int fallback_uses = 0;
  auto texture_avg = [&](int tree_tex_id) -> const std::array<float, 3>* {
    if (tree_tex_id < 0 || (size_t)tree_tex_id >= lev.textures.size()) return nullptr;
    auto it = tex_avg_cache.find(tree_tex_id);
    if (it != tex_avg_cache.end()) return &it->second;
    const auto& tex = lev.textures[(size_t)tree_tex_id];
    double sum[3] = {0, 0, 0};
    double w = 0;
    for (u32 px : tex.data) {
      u8 r = px & 0xff, g = (px >> 8) & 0xff, b = (px >> 16) & 0xff, a = (px >> 24) & 0xff;
      if (a == 0) continue;
      sum[0] += r;
      sum[1] += g;
      sum[2] += b;
      w += 1;
    }
    std::array<float, 3> avg = {1.f, 1.f, 1.f};
    if (w > 0) {
      avg = {(float)(sum[0] / w / 255.0), (float)(sum[1] / w / 255.0), (float)(sum[2] / w / 255.0)};
    }
    return &tex_avg_cache.emplace(tree_tex_id, avg).first->second;
  };

  std::set<std::string> candidate_protos, unjudged_protos;

  const auto& trees = lev.tie_trees[0];
  for (size_t ti = 0; ti < trees.size(); ti++) {
    const auto& tree = trees[ti];
    std::map<uint16_t, InstanceAcc> insts;  // vis_idx_in_pc_bvh -> accumulateur

    for (const auto& draw : tree.static_draws) {
      // les indices des vis_groups d'un StripDraw sont des tranches CONTIGUES du tableau
      // d'indices partage de l'arbre, dans l'ordre des vis_groups (LightBake.cpp collect_trees /
      // main.cpp for_each_tri suivent le meme patron).
      size_t running = draw.unpacked.idx_of_first_idx_in_full_buffer;
      for (const auto& vg : draw.vis_groups) {
        size_t begin = running;
        size_t count = vg.num_inds;
        running += count;
        if (begin + count > tree.unpacked.indices.size()) continue;
        if (vg.tie_proto_idx >= tree.proto_names.size()) continue;
        const std::string& proto = tree.proto_names[vg.tie_proto_idx];
        if (is_candidate(proto)) candidate_protos.insert(proto);
        if (!is_candidate(proto) && !lex.lights.count(proto)) continue;  // pas un emetteur

        InstanceAcc& acc = insts[vg.vis_idx_in_pc_bvh];
        acc.proto = proto;
        const std::array<float, 3>* tavg = texture_avg(draw.tree_tex_id);

        for_each_tri(tree.unpacked.indices.data() + begin, count, tree.use_strips,
                     [&](u32 a, u32 b, u32 c) {
                       if (a >= tree.unpacked.vertices.size() ||
                           b >= tree.unpacked.vertices.size() ||
                           c >= tree.unpacked.vertices.size())
                         return;
                       const auto& va = tree.unpacked.vertices[a];
                       const auto& vb = tree.unpacked.vertices[b];
                       const auto& vc = tree.unpacked.vertices[c];
                       V3 p0(va.x, va.y, va.z), p1(vb.x, vb.y, vb.z), p2(vc.x, vc.y, vc.z);
                       float area = len(cross(p1 - p0, p2 - p0)) * 0.5f;
                       if (area <= 0.f) return;
                       V3 centroid = (p0 + p1 + p2) * (1.f / 3.f);
                       acc.area_sum += area;
                       acc.centroid_wsum = acc.centroid_wsum + centroid * area;
                       for (int k = 0; k < 3; k++) {
                         float x = k == 0 ? p0.x : (k == 1 ? p1.x : p2.x);
                         (void)x;
                       }
                       float xs[3] = {p0.x, p1.x, p2.x};
                       float ys[3] = {p0.y, p1.y, p2.y};
                       float zs[3] = {p0.z, p1.z, p2.z};
                       for (int k = 0; k < 3; k++) {
                         acc.bmin[0] = std::min(acc.bmin[0], xs[k]);
                         acc.bmin[1] = std::min(acc.bmin[1], ys[k]);
                         acc.bmin[2] = std::min(acc.bmin[2], zs[k]);
                         acc.bmax[0] = std::max(acc.bmax[0], xs[k]);
                         acc.bmax[1] = std::max(acc.bmax[1], ys[k]);
                         acc.bmax[2] = std::max(acc.bmax[2], zs[k]);
                       }
                       if (tavg) {
                         acc.col_wsum[0] += (*tavg)[0] * area;
                         acc.col_wsum[1] += (*tavg)[1] * area;
                         acc.col_wsum[2] += (*tavg)[2] * area;
                         acc.col_w += area;
                       } else {
                         acc.used_vertex_color_fallback = true;
                         acc.col_wsum[0] += (va.r + vb.r + vc.r) / 3.0 / 255.0 * area;
                         acc.col_wsum[1] += (va.g + vb.g + vc.g) / 3.0 / 255.0 * area;
                         acc.col_wsum[2] += (va.b + vb.b + vc.b) / 3.0 / 255.0 * area;
                         acc.col_w += area;
                       }
                     });
      }
    }

    stats.instances_seen += (int)insts.size();
    for (auto& [vis_idx, acc] : insts) {
      if (acc.area_sum <= 0.0) continue;
      if (acc.used_vertex_color_fallback) fallback_uses++;
      bool candidate = is_candidate(acc.proto);
      auto it = lex.lights.find(acc.proto);
      if (it == lex.lights.end()) {
        if (candidate && !lex.judged(acc.proto)) {
          unjudged_protos.insert(acc.proto);
        }
        continue;
      }
      const Rule& r = it->second;
      stats.instances_lit++;

      float centroid[3] = {(float)(acc.centroid_wsum.x / acc.area_sum),
                            (float)(acc.centroid_wsum.y / acc.area_sum),
                            (float)(acc.centroid_wsum.z / acc.area_sum)};
      float avg_col[3] = {1, 1, 1};
      if (acc.col_w > 0) {
        avg_col[0] = (float)(acc.col_wsum[0] / acc.col_w);
        avg_col[1] = (float)(acc.col_wsum[1] / acc.col_w);
        avg_col[2] = (float)(acc.col_wsum[2] / acc.col_w);
      }

      Light lt;
      if (r.has_off) {
        float cx = (acc.bmin[0] + acc.bmax[0]) * 0.5f;
        float cz = (acc.bmin[2] + acc.bmax[2]) * 0.5f;
        lt.pos[0] = cx / kMeter + r.off[0];
        lt.pos[1] = acc.bmin[1] / kMeter + r.off[1];
        lt.pos[2] = cz / kMeter + r.off[2];
      } else {
        lt.pos[0] = centroid[0] / kMeter;
        lt.pos[1] = centroid[1] / kMeter;
        lt.pos[2] = centroid[2] / kMeter;
      }
      lt.radius = r.r;
      lt.intensity = r.cd;
      lt.type = r.type;
      lt.flicker = r.flicker;
      lt.source = r.rgb_auto ? 2 : 1;
      lt.proto_hash = fnv1a32(acc.proto);
      lt.dir[0] = 0;
      lt.dir[1] = -1;
      lt.dir[2] = 0;
      if (r.rgb_auto) {
        lt.rgb[0] = avg_col[0];
        lt.rgb[1] = avg_col[1];
        lt.rgb[2] = avg_col[2];
      } else {
        lt.rgb[0] = r.rgb[0];
        lt.rgb[1] = r.rgb[1];
        lt.rgb[2] = r.rgb[2];
      }
      if (r.type == Type::Spot) {
        lt.cos_inner = std::cos(r.cone_inner_deg * 3.14159265f / 180.f);
        lt.cos_outer = std::cos(r.cone_outer_deg * 3.14159265f / 180.f);
      }
      out.push_back(lt);
      stats.lights++;
    }
  }

  stats.protos_candidate = (int)candidate_protos.size();
  stats.protos_unjudged = (int)unjudged_protos.size();
  for (const auto& n : unjudged_protos) stats.unjudged_names.push_back(n);
  std::sort(stats.unjudged_names.begin(), stats.unjudged_names.end());
  if (fallback_uses > 0) {
    lg::warn(
        "[local-lights] {} instance(s) sans donnees de texture dans le fr3 : repli sur la "
        "couleur de sommet moyenne",
        fallback_uses);
  }
  return out;
}

void serialize(const std::vector<Light>& lights, std::vector<uint8_t>& out) {
  out.clear();
  out.resize(4 + lights.size() * kRecordBytes);
  uint32_t count = (uint32_t)lights.size();
  memcpy(out.data(), &count, 4);
  size_t off = 4;
  for (const auto& l : lights) {
    auto put_f = [&](float v) {
      memcpy(out.data() + off, &v, 4);
      off += 4;
    };
    auto put_u = [&](uint32_t v) {
      memcpy(out.data() + off, &v, 4);
      off += 4;
    };
    put_f(l.pos[0]);
    put_f(l.pos[1]);
    put_f(l.pos[2]);
    put_f(l.radius);
    put_f(l.rgb[0]);
    put_f(l.rgb[1]);
    put_f(l.rgb[2]);
    put_f(l.intensity);
    put_f(l.dir[0]);
    put_f(l.dir[1]);
    put_f(l.dir[2]);
    put_f(l.cos_inner);
    put_f(l.cos_outer);
    uint32_t packed = (uint32_t)l.type | ((uint32_t)l.flicker << 8) | ((uint32_t)l.source << 16);
    put_u(packed);
    put_u(l.proto_hash);
    put_u(0);
  }
}

bool deserialize(const uint8_t* data, size_t size, std::vector<Light>& out) {
  out.clear();
  if (size < 4) return false;
  uint32_t count;
  memcpy(&count, data, 4);
  if (4 + (size_t)count * kRecordBytes != size) return false;
  out.resize(count);
  size_t off = 4;
  for (uint32_t i = 0; i < count; i++) {
    Light l;
    auto get_f = [&]() {
      float v;
      memcpy(&v, data + off, 4);
      off += 4;
      return v;
    };
    auto get_u = [&]() {
      uint32_t v;
      memcpy(&v, data + off, 4);
      off += 4;
      return v;
    };
    l.pos[0] = get_f();
    l.pos[1] = get_f();
    l.pos[2] = get_f();
    l.radius = get_f();
    l.rgb[0] = get_f();
    l.rgb[1] = get_f();
    l.rgb[2] = get_f();
    l.intensity = get_f();
    l.dir[0] = get_f();
    l.dir[1] = get_f();
    l.dir[2] = get_f();
    l.cos_inner = get_f();
    l.cos_outer = get_f();
    uint32_t packed = get_u();
    l.type = (Type)(packed & 0xff);
    l.flicker = (uint8_t)((packed >> 8) & 0xff);
    l.source = (uint8_t)((packed >> 16) & 0xff);
    l.proto_hash = get_u();
    get_u();  // reserve
    out[i] = l;
  }
  return true;
}

std::vector<Candidate> load_candidates(const std::string& path, bool* ok) {
  std::vector<Candidate> out;
  if (ok) *ok = false;
  if (!file_util::file_exists(path)) return out;
  std::string text = file_util::read_text_file(path);
  std::istringstream ss(text);
  std::string line;
  while (std::getline(ss, line)) {
    size_t b = line.find_first_not_of(" \t\r\n");
    if (b == std::string::npos || line[b] == '#') continue;
    auto toks = split_ws(line);
    if (toks.size() < 3) continue;
    Candidate c;
    c.proto = toks[0];
    try {
      c.instances = std::stoi(toks[1]);
    } catch (...) {
      continue;
    }
    c.levels = toks[2];
    out.push_back(c);
  }
  if (ok) *ok = true;
  return out;
}

}  // namespace local_lights
