// lighting-bake (SPEC-refonte-lumiere §5) : outil HORS LIGNE, sur le patron de tools/mesh_audit.
//
// Pour chaque niveau : charge le fr3 EXACTEMENT comme le chargeur (unpack, soudure globale, puis le
// compagnon .meshweld qui retouche normales et palette), lit la mood-lights-table du niveau dans
// mood-tables.gc, lance des rayons contre la geometrie soudee (BVH sur tfrag + tie developpes +
// shrub, LOD 0) et decompose chaque index de couleur de la palette A :
//   physᵢ = ambᵢ·skyvis + lgtᵢ·max(N·Lᵢ,0)·visᵢ      artᵢ = bakedᵢ / physᵢ
//   palette B = ambᵢ·skyvis·artᵢ                       direct = lgtᵢ·max(N·Lᵢ,0)·visᵢ·artᵢ
// et ecrit <fr3-dir>/<niveau>.lightbake. Le fr3 n'est JAMAIS ecrit : il est relu apres le bake et
// compare octet pour octet (`fr3_bytes_changed`).
//
// Usage: light_bake [--bake] [--verify] [--rays N] [--fr3-dir DIR] [--mood-file F]
//                   [--report FILE] [--csv FILE] [--no-enhanced] [--threads N] niveaux...

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <fstream>
#include <map>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

#include "common/custom_data/LightBake.h"
#include "common/custom_data/LocalLights.h"
#include "common/custom_data/MeshConsolidate.h"
#include "common/custom_data/Tfrag3Data.h"
#include "common/util/FileUtil.h"
#include "common/util/Serializer.h"
#include "common/util/compress.h"

#include "fmt/format.h"

using namespace tfrag3;
namespace lb = tfrag3::lightbake;

namespace {

constexpr float kMeter = 4096.f;
constexpr float kOriginOffset = 0.03f * kMeter;  // decalage de l'origine le long de N
constexpr float kTmin = 1.f;
constexpr float kFar = 1e12f;
constexpr int kMaxReps = 4;  // sommets representatifs par index de couleur

// ------------------------------------------------------------------ petite algebre
struct V3 {
  float x = 0, y = 0, z = 0;
  V3() = default;
  V3(float a, float b, float c) : x(a), y(b), z(c) {}
  V3 operator+(const V3& o) const { return {x + o.x, y + o.y, z + o.z}; }
  V3 operator-(const V3& o) const { return {x - o.x, y - o.y, z - o.z}; }
  V3 operator*(float s) const { return {x * s, y * s, z * s}; }
  float operator[](int i) const { return i == 0 ? x : (i == 1 ? y : z); }
};
float dot(const V3& a, const V3& b) {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}
V3 cross(const V3& a, const V3& b) {
  return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
float len(const V3& a) {
  return std::sqrt(dot(a, a));
}
V3 norm(const V3& a) {
  float l = len(a);
  return l > 1e-12f ? a * (1.f / l) : V3(0, 0, 0);
}
void onb(const V3& n, V3& t, V3& b) {
  V3 a = std::fabs(n.x) > 0.9f ? V3(0, 1, 0) : V3(1, 0, 0);
  t = norm(cross(a, n));
  b = cross(n, t);
}

V3 unpack_nor(u32 p) {
  auto sx = [](u32 v) -> int {
    int x = (int)(v & 0x3ffu);
    return (x & 0x200) ? x - 0x400 : x;
  };
  return norm(V3((float)sx(p), (float)sx(p >> 10), (float)sx(p >> 20)));
}

// octaedrique 2 × u8
void oct_encode(const V3& n, u8* out) {
  float s = std::fabs(n.x) + std::fabs(n.y) + std::fabs(n.z);
  float u = s > 0 ? n.x / s : 0, v = s > 0 ? n.z / s : 0;
  if (n.y < 0) {
    float ou = u, ov = v;
    u = (1.f - std::fabs(ov)) * (ou >= 0 ? 1.f : -1.f);
    v = (1.f - std::fabs(ou)) * (ov >= 0 ? 1.f : -1.f);
  }
  out[0] = (u8)std::lround((u * 0.5f + 0.5f) * 255.f);
  out[1] = (u8)std::lround((v * 0.5f + 0.5f) * 255.f);
}

float radical_inverse(u32 b) {
  b = (b << 16u) | (b >> 16u);
  b = ((b & 0x55555555u) << 1u) | ((b & 0xAAAAAAAAu) >> 1u);
  b = ((b & 0x33333333u) << 2u) | ((b & 0xCCCCCCCCu) >> 2u);
  b = ((b & 0x0F0F0F0Fu) << 4u) | ((b & 0xF0F0F0F0u) >> 4u);
  b = ((b & 0x00FF00FFu) << 8u) | ((b & 0xFF00FF00u) >> 8u);
  return (float)b * 2.3283064365386963e-10f;
}

// ------------------------------------------------------------------ BVH (occlusion seulement)
struct Tri {
  V3 v0, e1, e2;
};
struct Node {
  float bmin[3], bmax[3];
  u32 first;  // feuille : premier triangle ; interne : enfant gauche (droit = gauche + 1)
  u32 count;  // 0 = interne
};

class Bvh {
 public:
  std::vector<Tri> tris;
  std::vector<Node> nodes;
  float lo[3] = {1e30f, 1e30f, 1e30f}, hi[3] = {-1e30f, -1e30f, -1e30f};

  void build() {
    const size_t n = tris.size();
    std::vector<u32> idx(n);
    cen_.resize(n);
    tlo_.resize(n);
    thi_.resize(n);
    for (u32 i = 0; i < n; i++) {
      idx[i] = i;
      const Tri& t = tris[i];
      V3 a = t.v0, b = t.v0 + t.e1, c = t.v0 + t.e2;
      for (int k = 0; k < 3; k++) {
        tlo_[i].v[k] = std::min({a[k], b[k], c[k]});
        thi_[i].v[k] = std::max({a[k], b[k], c[k]});
        cen_[i].v[k] = (tlo_[i].v[k] + thi_[i].v[k]) * 0.5f;
        lo[k] = std::min(lo[k], tlo_[i].v[k]);
        hi[k] = std::max(hi[k], thi_[i].v[k]);
      }
    }
    nodes.reserve(2 * n / 2 + 1);
    nodes.push_back({});
    if (n) {
      build_rec(0, idx, 0, (u32)n);
    }
    std::vector<Tri> sorted(n);
    for (size_t i = 0; i < n; i++) {
      sorted[i] = tris[idx[i]];
    }
    tris.swap(sorted);
    cen_.clear();
    tlo_.clear();
    thi_.clear();
  }

  bool occluded(const V3& o, const V3& d, float tmax) const {
    if (nodes.empty() || tris.empty()) {
      return false;
    }
    float inv[3] = {1.f / d.x, 1.f / d.y, 1.f / d.z};
    u32 stack[128];
    int sp = 0;
    stack[sp++] = 0;
    while (sp) {
      const Node& nd = nodes[stack[--sp]];
      float t0 = kTmin, t1 = tmax;
      bool miss = false;
      for (int k = 0; k < 3 && !miss; k++) {
        float ta = (nd.bmin[k] - o[k]) * inv[k];
        float tb = (nd.bmax[k] - o[k]) * inv[k];
        if (ta > tb) std::swap(ta, tb);
        t0 = ta > t0 ? ta : t0;
        t1 = tb < t1 ? tb : t1;
        miss = t0 > t1;
      }
      if (miss) {
        continue;
      }
      if (nd.count) {
        for (u32 i = nd.first; i < nd.first + nd.count; i++) {
          if (hit(tris[i], o, d, tmax)) {
            return true;
          }
        }
      } else if (sp < 126) {
        stack[sp++] = nd.first;
        stack[sp++] = nd.first + 1;
      }
    }
    return false;
  }

 private:
  struct F3 {
    float v[3];
  };
  std::vector<F3> cen_, tlo_, thi_;

  static bool hit(const Tri& t, const V3& o, const V3& d, float tmax) {
    V3 p = cross(d, t.e2);
    float det = dot(t.e1, p);
    if (std::fabs(det) < 1e-12f) {
      return false;
    }
    float id = 1.f / det;
    V3 s = o - t.v0;
    float u = dot(s, p) * id;
    if (u < 0.f || u > 1.f) {
      return false;
    }
    V3 q = cross(s, t.e1);
    float v = dot(d, q) * id;
    if (v < 0.f || u + v > 1.f) {
      return false;
    }
    float tt = dot(t.e2, q) * id;
    return tt > kTmin && tt < tmax;
  }

  void build_rec(u32 ni, std::vector<u32>& idx, u32 b, u32 e) {
    Node nd;
    float clo[3] = {1e30f, 1e30f, 1e30f}, chi[3] = {-1e30f, -1e30f, -1e30f};
    for (int k = 0; k < 3; k++) {
      nd.bmin[k] = 1e30f;
      nd.bmax[k] = -1e30f;
    }
    for (u32 i = b; i < e; i++) {
      u32 t = idx[i];
      for (int k = 0; k < 3; k++) {
        nd.bmin[k] = std::min(nd.bmin[k], tlo_[t].v[k]);
        nd.bmax[k] = std::max(nd.bmax[k], thi_[t].v[k]);
        clo[k] = std::min(clo[k], cen_[t].v[k]);
        chi[k] = std::max(chi[k], cen_[t].v[k]);
      }
    }
    if (e - b <= 4) {
      nd.first = b;
      nd.count = e - b;
      nodes[ni] = nd;
      return;
    }
    int ax = 0;
    for (int k = 1; k < 3; k++) {
      if (chi[k] - clo[k] > chi[ax] - clo[ax]) ax = k;
    }
    u32 mid = (b + e) / 2;
    std::nth_element(idx.begin() + b, idx.begin() + mid, idx.begin() + e,
                     [&](u32 x, u32 y) { return cen_[x].v[ax] < cen_[y].v[ax]; });
    u32 left = (u32)nodes.size();
    nodes.push_back({});
    nodes.push_back({});
    nd.first = left;
    nd.count = 0;
    nodes[ni] = nd;
    build_rec(left, idx, b, mid);
    build_rec(left + 1, idx, mid, e);
  }
};

template <typename F>
void for_each_tri(const std::vector<u32>& idx, bool use_strips, F&& emit) {
  if (use_strips) {
    u32 a = UINT32_MAX, b = UINT32_MAX, k = 0;
    for (u32 vi : idx) {
      if (vi == UINT32_MAX) {
        a = b = UINT32_MAX;
        k = 0;
        continue;
      }
      if (a != UINT32_MAX && b != UINT32_MAX) {
        if (k & 1) {
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
    for (size_t t = 0; t + 2 < idx.size(); t += 3) {
      if (idx[t] != UINT32_MAX && idx[t + 1] != UINT32_MAX && idx[t + 2] != UINT32_MAX) {
        emit(idx[t], idx[t + 1], idx[t + 2]);
      }
    }
  }
}

V3 vpos(const lb::TreeRef& r, u32 i) {
  const float* f = (const float*)(r.verts + (size_t)i * r.vstride);
  return {f[0], f[1], f[2]};
}
u32 vnor(const lb::TreeRef& r, u32 i) {
  u32 n;
  memcpy(&n, r.verts + (size_t)i * r.vstride + r.off_nor, 4);
  return n;
}
u16 vcol(const lb::TreeRef& r, u32 i) {
  u16 c;
  memcpy(&c, r.verts + (size_t)i * r.vstride + r.off_color_index, 2);
  return c;
}

// ------------------------------------------------------------------ table de mood (GOAL source)
bool parse_vector(const std::string& s, size_t at, float out[4]) {
  size_t p = s.find("(new 'static 'vector", at);
  if (p == std::string::npos) return false;
  size_t e = s.find(')', p);
  if (e == std::string::npos) return false;
  out[0] = out[1] = out[2] = out[3] = 0.f;
  const char* names[4] = {":x ", ":y ", ":z ", ":w "};
  std::string body = s.substr(p, e - p);
  for (int k = 0; k < 4; k++) {
    size_t q = body.find(names[k]);
    if (q != std::string::npos) {
      out[k] = std::strtof(body.c_str() + q + 3, nullptr);
    }
  }
  return true;
}

bool parse_mood_table(const std::string& text, const std::string& table, lb::MoodTable& t,
                      std::string& err) {
  const std::string def = "(define *" + table + "-mood-lights-table*";
  size_t p = text.find(def);
  if (p == std::string::npos) {
    err = "table absente : " + def;
    return false;
  }
  for (int s = 0; s < lb::kSlots; s++) {
    size_t m = text.find("'mood-lights", p + 1);
    if (m == std::string::npos) {
      err = fmt::format("creneau {} absent", s);
      return false;
    }
    auto field = [&](const char* key, float out3[3]) {
      size_t k = text.find(key, m);
      float v[4];
      if (k == std::string::npos || !parse_vector(text, k, v)) return false;
      out3[0] = v[0];
      out3[1] = v[1];
      out3[2] = v[2];
      return true;
    };
    auto& L = t.slot[s];
    if (!field(":direction", L.direction) || !field(":lgt-color", L.lgt) ||
        !field(":amb-color", L.amb) || !field(":shadow", L.shadow)) {
      err = fmt::format("creneau {} incomplet", s);
      return false;
    }
    p = text.find(":shadow", m);
  }
  // mood-tables.gc applique update-mood-shadow-direction a chargement : le moteur voit la table
  // APRES ces appels, la meme transformation est rejouee ici (en float, comme le MIPS).
  const std::string call = "(update-mood-shadow-direction (-> *" + table + "-mood-lights-table* data ";
  for (size_t c = text.find(call); c != std::string::npos; c = text.find(call, c + 1)) {
    int slot = std::atoi(text.c_str() + c + call.size());
    if (slot < 0 || slot >= lb::kSlots) continue;
    auto& L = t.slot[slot];
    L.shadow[0] = -L.direction[0];
    L.shadow[1] = -L.direction[1];
    L.shadow[2] = -L.direction[2];
    if (L.direction[1] < 0.9063f) {
      float f = 0.4226f / std::sqrt(L.shadow[0] * L.shadow[0] + L.shadow[2] * L.shadow[2]);
      L.shadow[0] *= f;
      L.shadow[1] = -0.9063f;
      L.shadow[2] *= f;
    }
  }
  return true;
}

// ------------------------------------------------------------------ chargement (miroir de Loader.cpp)
void load_level(const fs::path& fr3, const fs::path& meshweld, Level& lev, bool& weld_applied) {
  auto data = file_util::read_binary_file(fr3);
  auto decomp = compression::decompress_zstd(data.data(), data.size());
  Serializer ser(decomp.data(), decomp.size());
  lev.serialize(ser);
  for (auto& tt : lev.tie_trees)
    for (auto& t : tt) t.unpack();
  for (auto& tt : lev.tfrag_trees)
    for (auto& t : tt) t.unpack();
  for (auto& t : lev.shrub_trees) t.unpack();
  reconstruct_level_global_weld(lev);
  weld_applied = fs::exists(meshweld) &&
                 mesh_consolidate_apply_bake(lev, meshweld.string(), /*do_shrub=*/true,
                                             /*mesh_unconsumed=*/false);
}

struct LevelStats {
  std::string level;
  std::string fr3;
  bool weld = false;
  u32 trees = 0, colors = 0, colors_used = 0;
  u64 verts = 0, bvh_tris = 0, rays = 0;
  u64 triples = 0, clamped = 0, clamp_low = 0, clamp_high = 0, zero = 0;
  float raw_p[5] = {0, 0, 0, 0, 0};
  double sky_sum = 0, kv_sum = 0;
  u64 sky_n = 0, kv_n = 0, kv_pos = 0, nor_stored = 0, n_up = 0, nvert = 0;
  float art_p50 = 0, art_p95 = 0;
  float maxdelta = 0, maxdelta_b = 0;
  u64 verified = 0;
  std::string regimes;
  double seconds = 0;
  u64 bytes = 0;
  u64 fr3_bytes_changed = 0;
  u64 palette_a_bytes_changed = 0;
  bool ok = false;
  std::string err;
  // lighting-local-lights (SPEC §5.3.8)
  int ll_lights = 0, ll_instances_lit = 0, ll_candidates = 0, ll_unjudged = 0;
};

struct Options {
  bool bake = false, verify = false, enhanced = true;
  bool lights_only = false, emitter_census = false;
  int rays = 64;
  int threads = 0;
  fs::path fr3_dir, mood_file, report, csv;
  fs::path emitters_file;
};

// Ecrit `lights_body` (u32 count + enregistrements, cf. LocalLights.h) comme corps de la section
// kSecLights d'un .lightbake DEJA EXISTANT, en laissant tout le reste du fichier identique a
// l'octet. Ecriture atomique (fichier temporaire + rename).
bool patch_lights_section(const fs::path& path, const std::vector<u8>& lights_body,
                          std::string* err) {
  auto data = file_util::read_binary_file(path);
  size_t p = 0;
  auto need = [&](size_t n) { return p + n <= data.size(); };
  auto get_u32 = [&]() {
    u32 v = 0;
    memcpy(&v, &data[p], 4);
    p += 4;
    return v;
  };
  if (!need(4) || get_u32() != lb::kMagic) {
    if (err) *err = "magic";
    return false;
  }
  if (!need(4) || get_u32() != lb::kVersion) {
    if (err) *err = "version";
    return false;
  }
  if (!need(4)) {
    if (err) *err = "truncated";
    return false;
  }
  u32 nlen = get_u32();
  if (!need(nlen)) {
    if (err) *err = "truncated";
    return false;
  }
  p += nlen;
  if (!need(8)) {
    if (err) *err = "truncated";
    return false;
  }
  get_u32();  // num_verts
  u32 nt = get_u32();
  const size_t per_tree = 1 + 1 + 4 + 4 + 8;
  if (!need((size_t)nt * per_tree)) {
    if (err) *err = "truncated";
    return false;
  }
  p += (size_t)nt * per_tree;
  if (!need(8)) {
    if (err) *err = "truncated";
    return false;
  }
  get_u32();
  get_u32();  // tfrag3_version, mood_hash
  size_t body_start = std::string::npos, body_len = 0, sz_field_pos = 0;
  while (p + 8 <= data.size()) {
    size_t sec_pos = p;
    u32 sec = get_u32();
    u32 sz = get_u32();
    if (!need(sz)) {
      if (err) *err = "section-size";
      return false;
    }
    if (sec == (u32)lb::kSecLights) {
      body_start = p;
      body_len = sz;
      sz_field_pos = sec_pos + 4;
      break;
    }
    p += sz;
  }
  if (body_start == std::string::npos) {
    if (err) *err = "no-lights-section";
    return false;
  }
  std::vector<u8> out;
  out.reserve(data.size() - body_len + lights_body.size());
  out.insert(out.end(), data.begin(), data.begin() + sz_field_pos);
  u32 newsz = (u32)lights_body.size();
  const u8* szp = (const u8*)&newsz;
  out.insert(out.end(), szp, szp + 4);
  out.insert(out.end(), lights_body.begin(), lights_body.end());
  out.insert(out.end(), data.begin() + body_start + body_len, data.end());
  fs::path tmp = path;
  tmp += ".tmp";
  file_util::write_binary_file(tmp, out.data(), out.size());
  fs::rename(tmp, path);
  return true;
}

LevelStats bake_level(const Options& opt, const std::string& level, const std::string& mood_text,
                      const local_lights::Lexicon& lex) {
  LevelStats st;
  st.level = level;
  auto t_start = std::chrono::steady_clock::now();
  fs::path fr3 = opt.fr3_dir / (level + ".fr3");
  if (opt.enhanced && fs::exists(opt.fr3_dir / "enhanced" / (level + ".fr3"))) {
    fr3 = opt.fr3_dir / "enhanced" / (level + ".fr3");
  }
  st.fr3 = fr3.string();
  if (!fs::exists(fr3)) {
    st.err = "fr3 absent";
    return st;
  }
  const auto fr3_before = file_util::read_binary_file(fr3);

  lb::Bake bake;
  std::string err;
  if (!parse_mood_table(mood_text, level, bake.mood, err)) {
    st.err = err;
    return st;
  }
  bake.level_name = level;
  bake.tfrag3_version = TFRAG3_VERSION;
  bake.mood_hash = lb::mood_hash(bake.mood);
  for (int s = 0; s < lb::kSlots; s++) {
    bake.regime[s] = lb::classify_regime(bake.mood.slot[s]);
    st.regimes += fmt::format("{}{}", s ? "," : "", lb::regime_name(bake.regime[s]));
  }

  Level lev;
  load_level(fr3, opt.fr3_dir / mesh_consolidate_bake_name(level), lev, st.weld);
  const auto refs = lb::collect_trees(lev);
  std::vector<std::vector<u8>> palette_before;
  for (const auto& r : refs) palette_before.push_back(r.colors->data);

  // --- BVH : LOD 0 de tfrag et tie (les LOD sont des copies superposees du meme monde) + shrub
  Bvh bvh;
  for (const auto& r : refs) {
    if (r.geom != 0) continue;
    for_each_tri(*r.indices, r.use_strips, [&](u32 a, u32 b, u32 c) {
      if (a >= r.vcount || b >= r.vcount || c >= r.vcount) return;
      V3 p0 = vpos(r, a), p1 = vpos(r, b), p2 = vpos(r, c);
      V3 e1 = p1 - p0, e2 = p2 - p0;
      if (len(cross(e1, e2)) < 1e-6f) return;
      bvh.tris.push_back({p0, e1, e2});
    });
  }
  st.bvh_tris = bvh.tris.size();
  bvh.build();

  V3 Ldir[lb::kSlots];
  float cone[lb::kSlots];
  int cone_rays[lb::kSlots];
  for (int s = 0; s < lb::kSlots; s++) {
    const auto& m = bake.mood.slot[s];
    Ldir[s] = norm(V3(m.direction[0], m.direction[1], m.direction[2]));
    switch (bake.regime[s]) {
      case lb::kRegDome:  // la cle EST le ciel : cone de 60°
        cone[s] = 60.f;
        cone_rays[s] = 16;
        break;
      case lb::kRegLow:  // source basse : 90° vers la source
        cone[s] = 90.f;
        cone_rays[s] = 16;
        break;
      default:  // directionnelle : rayon central + 4 dans un cone de 2°
        cone[s] = 2.f;
        cone_rays[s] = 5;
        break;
    }
  }

  std::atomic<u64> rays{0};
  std::mutex stat_mu;
  std::vector<float> residuals, raw_art;

  bake.trees.resize(refs.size());
  for (size_t ti = 0; ti < refs.size(); ti++) {
    const auto& r = refs[ti];
    auto& tb = bake.trees[ti];
    const auto& A = *r.colors;
    tb.system = r.system;
    tb.geom = r.geom;
    tb.color_count = A.color_count;
    tb.palette_a_hash = lb::palette_hash(A);
    if (getenv("LIGHT_BAKE_DIAG")) fmt::print("diag palette tree {} {:016x}\n", ti, tb.palette_a_hash);
    tb.vert_count = (u32)r.vcount;
    tb.palette_b = A.data;  // borne depassee / index sans sommet : B = A
    tb.skyvis.assign(A.color_count, 0);
    tb.ao.assign(A.color_count, 0);
    tb.keyvis.assign((size_t)A.color_count * lb::kSlots, 0);
    tb.art.assign((size_t)A.color_count * lb::kSlots * 3, 0);
    tb.bent_n.assign(2 * r.vcount, 128);
    st.trees++;
    st.colors += A.color_count;
    st.verts += r.vcount;

    // surface par sommet + normale de repli (faces orientees vers le haut : l'enroulement des
    // strips est pile ou face, la normale STOCKEE fait foi quand elle existe)
    std::vector<float> area(r.vcount, 0.f);
    std::vector<V3> facc(r.vcount);
    for_each_tri(*r.indices, r.use_strips, [&](u32 a, u32 b, u32 c) {
      if (a >= r.vcount || b >= r.vcount || c >= r.vcount) return;
      V3 n = cross(vpos(r, b) - vpos(r, a), vpos(r, c) - vpos(r, a));
      float ar = 0.5f * len(n);
      if (n.y < 0) n = n * -1.f;
      for (u32 v : {a, b, c}) {
        area[v] += ar / 3.f;
        facc[v] = facc[v] + n;
      }
    });
    std::vector<V3> nrm(r.vcount);
    for (u32 v = 0; v < r.vcount; v++) {
      V3 n = unpack_nor(vnor(r, v));
      nrm[v] = len(n) > 0.5f ? n : norm(facc[v]);
      st.nor_stored += len(n) > 0.5f;
      st.nvert++;
      st.n_up += nrm[v].y > 0.f;
      if (len(nrm[v]) < 0.5f) nrm[v] = V3(0, 1, 0);
    }
    // CSR : index de couleur -> sommets
    std::vector<u32> start(A.color_count + 1, 0), list(r.vcount);
    for (u32 v = 0; v < r.vcount; v++) {
      u16 c = vcol(r, v);
      if (c < A.color_count) start[c + 1]++;
    }
    for (u32 c = 0; c < A.color_count; c++) start[c + 1] += start[c];
    {
      std::vector<u32> fill(start.begin(), start.end() - 1);
      for (u32 v = 0; v < r.vcount; v++) {
        u16 c = vcol(r, v);
        if (c < A.color_count) list[fill[c]++] = v;
      }
    }
    std::vector<V3> bent(A.color_count);

    std::atomic<u32> next{0};
    auto worker = [&]() {
      std::vector<float> local_res, local_raw;
      u64 local_low = 0, local_high = 0, local_zero = 0;
      double diag_sky = 0, diag_kv = 0;
      u64 diag_sky_n = 0, diag_kv_n = 0, diag_kv_pos = 0;
      u64 local_rays = 0, local_trip = 0, local_clamp = 0, local_used = 0;
      for (;;) {
        u32 c = next.fetch_add(1);
        if (c >= A.color_count) break;
        const u32 n = start[c + 1] - start[c];
        if (n == 0) continue;  // index sans sommet : reste B = A, art = 0
        local_used++;
        const u32* vs = &list[start[c]];
        u32 reps[kMaxReps];
        u32 nr = std::min<u32>(n, kMaxReps);
        for (u32 k = 0; k < nr; k++) reps[k] = vs[(u64)k * n / nr];
        float wsum = 0;
        for (u32 k = 0; k < nr; k++) wsum += area[reps[k]] + 1e-3f;

        // --- visibilite du ciel + normale coudee
        const int per = std::max(8, opt.rays / (int)nr);
        float sky = 0;
        V3 bsum;
        for (u32 k = 0; k < nr; k++) {
          const u32 v = reps[k];
          const V3 N = nrm[v];
          V3 T, B;
          onb(N, T, B);
          const V3 o = vpos(r, v) + N * kOriginOffset;
          const float rot = radical_inverse(c * 2654435761u + k);
          int free = 0;
          for (int i = 0; i < per; i++) {
            float u = (i + 0.5f) / per, w = radical_inverse((u32)i) + rot;
            w -= std::floor(w);
            float rr = std::sqrt(u), ph = 6.2831853f * w;
            V3 d = norm(T * (rr * std::cos(ph)) + B * (rr * std::sin(ph)) + N * std::sqrt(1.f - u));
            if (!bvh.occluded(o, d, kFar)) {
              free++;
              bsum = bsum + d;
            }
          }
          local_rays += per;
          sky += (area[v] + 1e-3f) / wsum * ((float)free / per);
        }
        bent[c] = len(bsum) > 1e-6f ? norm(bsum) : nrm[reps[0]];
        const u8 sky_q = (u8)std::lround(std::clamp(sky, 0.f, 1.f) * 255.f);
        tb.skyvis[c] = sky_q;
        diag_sky += sky;
        diag_sky_n++;
        tb.ao[c] = sky_q;  // l'AO cosinus EST la visibilite du ciel (SPEC §5.3.3)

        // --- visibilite de la cle, par creneau
        for (int s = 0; s < lb::kSlots; s++) {
          const V3 L = Ldir[s];
          if (len(L) < 0.5f) continue;
          double ndl_w = 0, w_all = 0;
          u32 best = vs[0];
          float best_ndl = -2.f;
          for (u32 i = 0; i < n; i++) {
            float d = dot(nrm[vs[i]], L);
            float w = area[vs[i]] + 1e-3f;
            ndl_w += w * std::max(d, 0.f);
            w_all += w;
            if (d > best_ndl) {
              best_ndl = d;
              best = vs[i];
            }
          }
          const float ndl = (float)(ndl_w / w_all);
          diag_kv_n++;
          if (ndl <= 0.f) continue;  // terme nul : visᵢ non calcule
          V3 T, B;
          onb(L, T, B);
          const float ca = std::cos(cone[s] * 3.14159265f / 180.f);
          float vis = 0, vw = 0;
          auto trace_from = [&](u32 v, float weight) {
            const V3 o = vpos(r, v) + nrm[v] * kOriginOffset;
            int free = 0;
            for (int i = 0; i < cone_rays[s]; i++) {
              V3 d = L;
              if (i > 0) {
                // uniforme en angle solide dans le cone
                float u = (i - 0.5f) / (cone_rays[s] - 1);
                float cz = 1.f - u * (1.f - ca);
                float sz = std::sqrt(std::max(0.f, 1.f - cz * cz));
                float ph = 6.2831853f * (radical_inverse((u32)i) + 0.37f * s);
                d = norm(T * (sz * std::cos(ph)) + B * (sz * std::sin(ph)) + L * cz);
              }
              if (!bvh.occluded(o, d, kFar)) free++;
            }
            local_rays += cone_rays[s];
            vis += weight * ((float)free / cone_rays[s]);
            vw += weight;
          };
          for (u32 k = 0; k < nr; k++) {
            if (dot(nrm[reps[k]], L) > 0.f) trace_from(reps[k], area[reps[k]] + 1e-3f);
          }
          if (vw == 0.f) trace_from(best, 1.f);
          vis /= vw;
          tb.keyvis[(size_t)c * lb::kSlots + s] =
              (u8)std::lround(std::clamp(ndl * vis, 0.f, 1.f) * 255.f);
          diag_kv += ndl * vis;
          diag_kv_pos += vis > 0.f;
        }

        // --- decomposition, a partir des valeurs QUANTIFIEES que le moteur relira
        for (int s = 0; s < lb::kSlots; s++) {
          const u8 kv = tb.keyvis[(size_t)c * lb::kSlots + s];
          const auto& m = bake.mood.slot[s];
          for (int ch = 0; ch < 3; ch++) {
            const size_t o = lb::palette_offset(c, s, ch);
            const float a = A.data[o];
            const float ph = lb::phys(m, ch, kv);
            local_trip++;
            if (a == 0.f) local_zero++;
            u16 q = 0;
            if (ph > 1e-4f) {
              const float art = (a / lb::kPaletteOne) / ph;
              if (a > 0.f) {
                local_raw.push_back(art);
                if (art < lb::kArtMin) local_low++;
                if (art > lb::kArtMax) local_high++;
              }
              if (art >= lb::kArtMin && art <= lb::kArtMax) {
                q = (u16)std::lround(art * lb::kArtScale);
              }
            }
            tb.art[((size_t)c * lb::kSlots + s) * 3 + ch] = q;
            if (q == 0) {
              if (a > 0.f) local_clamp++;
              continue;  // B = A deja en place
            }
            const float art_q = q / lb::kArtScale;
            local_res.push_back(std::fabs(art_q - 1.f));
            const float ind = lb::kPaletteOne * m.amb[ch] * art_q;
            tb.palette_b[o] = (u8)std::clamp<long>(std::lround(ind), 0, 255);
          }
        }
      }
      rays += local_rays;
      std::lock_guard<std::mutex> lk(stat_mu);
      residuals.insert(residuals.end(), local_res.begin(), local_res.end());
      raw_art.insert(raw_art.end(), local_raw.begin(), local_raw.end());
      st.clamp_low += local_low;
      st.zero += local_zero;
      st.sky_sum += diag_sky;
      st.sky_n += diag_sky_n;
      st.kv_sum += diag_kv;
      st.kv_n += diag_kv_n;
      st.kv_pos += diag_kv_pos;
      st.clamp_high += local_high;
      st.triples += local_trip;
      st.clamped += local_clamp;
      st.colors_used += (u32)local_used;
    };
    int nt = opt.threads > 0 ? opt.threads : (int)std::max(1u, std::thread::hardware_concurrency());
    std::vector<std::thread> pool;
    for (int i = 0; i < nt; i++) pool.emplace_back(worker);
    for (auto& t : pool) t.join();
    if (getenv("LIGHT_BAKE_DIAG")) {
      double ss = 0; u64 up = 0, ns = 0;
      for (u32 c = 0; c < A.color_count; c++) ss += tb.skyvis[c] / 255.0;
      for (u32 v = 0; v < r.vcount; v++) { up += nrm[v].y > 0; ns += len(unpack_nor(vnor(r, v))) > 0.5f; }
      fmt::print("diag tree {} {} g{} colors={} verts={} sky_mean={:.3f} n_up={:.3f} nor_stored={:.3f}\n", ti,
                 lb::system_name(r.system), r.geom, A.color_count, r.vcount,
                 A.color_count ? ss / A.color_count : 0, r.vcount ? (double)up / r.vcount : 0,
                 r.vcount ? (double)ns / r.vcount : 0);
    }

    for (u32 v = 0; v < r.vcount; v++) {
      u16 c = vcol(r, v);
      V3 b = c < A.color_count && len(bent[c]) > 0.5f ? bent[c] : nrm[v];
      oct_encode(b, &tb.bent_n[2 * v]);
    }
  }
  st.rays = rays.load();
  if (!residuals.empty()) {
    auto pct = [&](double p) {
      size_t k = std::min(residuals.size() - 1, (size_t)(p * residuals.size()));
      std::nth_element(residuals.begin(), residuals.begin() + k, residuals.end());
      return residuals[k];
    };
    st.art_p50 = pct(0.50);
    st.art_p95 = pct(0.95);
  }
  if (!raw_art.empty()) {
    const double ps[5] = {0.05, 0.25, 0.5, 0.75, 0.95};
    for (int i = 0; i < 5; i++) {
      size_t k = std::min(raw_art.size() - 1, (size_t)(ps[i] * raw_art.size()));
      std::nth_element(raw_art.begin(), raw_art.begin() + k, raw_art.end());
      st.raw_p[i] = raw_art[k];
    }
  }

  // palette A : jamais touchee par le bake
  for (size_t i = 0; i < refs.size(); i++) {
    const auto& now = refs[i].colors->data;
    for (size_t k = 0; k < now.size(); k++) st.palette_a_bytes_changed += now[k] != palette_before[i][k];
  }

  // la verification que le moteur fera, sur TOUS les index
  auto vr = lb::verify(lev, bake, bake.mood, 1, UINT64_MAX);
  st.maxdelta = vr.maxdelta;
  st.maxdelta_b = vr.maxdelta_b;
  st.verified = vr.indices_checked;
  if (!vr.accepted || vr.trees_rejected) {
    st.err = "verify: " + vr.reject_reason + fmt::format(" rejected={}", vr.trees_rejected);
  }
  bake.stats = fmt::format(
      "level={} trees={} colors={} colors_used={} rays={} art_residual_p50={:.4f} "
      "art_residual_p95={:.4f} art_clamped_frac={:.4f} regimes={}",
      level, st.trees, st.colors, st.colors_used, st.rays, st.art_p50, st.art_p95,
      st.triples > st.zero ? (double)st.clamped / (st.triples - st.zero) : 0.0, st.regimes);

  local_lights::ExtractStats llst;
  auto ll_lights = local_lights::extract(lev, lex, &llst);
  st.ll_lights = llst.lights;
  st.ll_instances_lit = llst.instances_lit;
  st.ll_candidates = llst.protos_candidate;
  st.ll_unjudged = llst.protos_unjudged;

  if (opt.bake) {
    auto bytes = lb::serialize(bake);
    st.bytes = bytes.size();
    const auto out_path = opt.fr3_dir / lb::lightbake_name(level);
    file_util::write_binary_file(out_path, bytes.data(), bytes.size());
    std::vector<u8> lights_body;
    local_lights::serialize(ll_lights, lights_body);
    std::string perr;
    if (!patch_lights_section(out_path, lights_body, &perr)) {
      st.err = "lights-patch: " + perr;
    }
    st.bytes = fs::file_size(out_path);
    // relecture : ce que le moteur lira
    lb::Bake back;
    std::string derr;
    auto disk = file_util::read_binary_file(out_path);
    if (!lb::deserialize(disk, back, &derr)) {
      st.err = "relecture: " + derr;
    } else {
      auto vr2 = lb::verify(lev, back, bake.mood, 1, UINT64_MAX);
      st.maxdelta = std::max(st.maxdelta, vr2.maxdelta);
    }
  }
  const auto fr3_after = file_util::read_binary_file(fr3);
  st.fr3_bytes_changed = fr3_after.size() != fr3_before.size() ? std::max(fr3_after.size(), fr3_before.size()) : 0;
  for (size_t k = 0; k < std::min(fr3_after.size(), fr3_before.size()); k++) {
    st.fr3_bytes_changed += fr3_after[k] != fr3_before[k];
  }
  st.seconds =
      std::chrono::duration<double>(std::chrono::steady_clock::now() - t_start).count();
  st.ok = st.err.empty();
  return st;
}

}  // namespace

int main(int argc, char** argv) {
  Options opt;
  std::vector<std::string> levels;
  for (int i = 1; i < argc; i++) {
    std::string a = argv[i];
    auto next = [&]() { return i + 1 < argc ? std::string(argv[++i]) : std::string(); };
    if (a == "--bake") opt.bake = true;
    else if (a == "--verify") opt.verify = true;
    else if (a == "--no-enhanced") opt.enhanced = false;
    else if (a == "--rays") opt.rays = std::max(8, std::atoi(next().c_str()));
    else if (a == "--threads") opt.threads = std::atoi(next().c_str());
    else if (a == "--fr3-dir") opt.fr3_dir = next();
    else if (a == "--mood-file") opt.mood_file = next();
    else if (a == "--report") opt.report = next();
    else if (a == "--csv") opt.csv = next();
    else if (a == "--emitters") opt.emitters_file = next();
    else if (a == "--lights-only") opt.lights_only = true;
    else if (a == "--emitter-census") opt.emitter_census = true;
    else if (a == "--probe-cell" || a == "--overrides") {
      next();
      fmt::print(stderr, "[light_bake] {} : sondes/overrides non cuits en version {}\n", a,
                 lb::kVersion);
    } else if (a == "-h" || a == "--help") {
      fmt::print("light_bake [--bake] [--verify] [--rays N] [--fr3-dir DIR] [--mood-file F]\n"
                 "           [--emitters FILE] [--lights-only] [--emitter-census]\n"
                 "           [--report FILE] [--csv FILE] [--no-enhanced] [--threads N] niveaux...\n");
      return 0;
    } else levels.push_back(a);
  }
  file_util::setup_project_path({});
  const fs::path root = file_util::get_jak_project_dir();
  if (opt.fr3_dir.empty()) opt.fr3_dir = root / "out" / "jak1" / "fr3";
  if (opt.mood_file.empty())
    opt.mood_file = root / "goal_src" / "jak1" / "engine" / "gfx" / "mood" / "mood-tables.gc";
  if (opt.emitters_file.empty()) opt.emitters_file = local_lights::default_lexicon_path();
  const local_lights::Lexicon lex = local_lights::load_lexicon(opt.emitters_file.string());

  if (opt.emitter_census) {
    // Recense TOUS les *.fr3 du dossier, sans se limiter aux quatre niveaux par defaut.
    std::map<std::string, std::pair<int, std::vector<std::string>>> per_proto;  // instances, niveaux
    int total_instances = 0;
    for (const auto& ent : fs::directory_iterator(opt.fr3_dir)) {
      if (!ent.is_regular_file() || ent.path().extension() != ".fr3") continue;
      const std::string lvl = ent.path().stem().string();
      Level lev;
      bool weld = false;
      load_level(ent.path(), opt.fr3_dir / mesh_consolidate_bake_name(lvl), lev, weld);
      if (lev.tie_trees.empty()) continue;
      for (const auto& tree : lev.tie_trees[0]) {
        // dedoublonne par instance (vis_idx_in_pc_bvh) : une meme instance peut apparaitre dans
        // plusieurs vis_groups (un par texture/draw), elle ne compte qu'une fois.
        std::map<uint16_t, std::string> inst_proto;
        for (const auto& draw : tree.static_draws) {
          for (const auto& vg : draw.vis_groups) {
            if (vg.tie_proto_idx >= tree.proto_names.size()) continue;
            const std::string& proto = tree.proto_names[vg.tie_proto_idx];
            if (!local_lights::is_candidate(proto)) continue;
            inst_proto[vg.vis_idx_in_pc_bvh] = proto;
          }
        }
        for (const auto& [vis_idx, proto] : inst_proto) {
          auto& e = per_proto[proto];
          e.first++;
          total_instances++;
          if (std::find(e.second.begin(), e.second.end(), lvl) == e.second.end()) {
            e.second.push_back(lvl);
          }
        }
      }
    }
    int unjudged = 0;
    std::vector<std::string> unjudged_names;
    std::string body;
    for (const auto& [proto, info] : per_proto) {
      if (!lex.judged(proto)) {
        unjudged++;
        unjudged_names.push_back(proto);
      }
    }
    std::vector<std::pair<std::string, std::pair<int, std::vector<std::string>>>> sorted(
        per_proto.begin(), per_proto.end());
    std::sort(sorted.begin(), sorted.end(),
              [](const auto& a, const auto& b) { return a.second.first > b.second.first; });
    body += fmt::format(
        "# light_candidates.txt — recense {} (lighting-local-lights) : proto instances niveaux\n"
        "# total prototypes candidats={} instances={}\n",
        opt.fr3_dir.string(), (int)sorted.size(), total_instances);
    for (const auto& [proto, info] : sorted) {
      std::string levs;
      for (size_t i = 0; i < info.second.size(); i++) {
        if (i) levs += ",";
        levs += info.second[i];
      }
      body += fmt::format("{} {} {}\n", proto, info.first, levs);
    }
    file_util::write_text_file(opt.fr3_dir / "light_candidates.txt", body);
    fmt::print("[light_bake] census candidates={} instances={} unjudged={}\n", (int)sorted.size(),
               total_instances, unjudged);
    if (!unjudged_names.empty()) {
      std::string names;
      for (size_t i = 0; i < unjudged_names.size(); i++) {
        if (i) names += ",";
        names += unjudged_names[i];
      }
      fmt::print("[light_bake] unjudged: {}\n", names);
    }
    return 0;
  }

  if (levels.empty()) levels = {"village1", "swamp", "lavatube", "snow"};
  const std::string mood_text = file_util::read_text_file(opt.mood_file);

  if (opt.lights_only) {
    bool all_ok = true;
    for (const auto& lvl : levels) {
      fs::path fr3 = opt.fr3_dir / (lvl + ".fr3");
      if (opt.enhanced && fs::exists(opt.fr3_dir / "enhanced" / (lvl + ".fr3"))) {
        fr3 = opt.fr3_dir / "enhanced" / (lvl + ".fr3");
      }
      fs::path lb_path = opt.fr3_dir / lb::lightbake_name(lvl);
      if (!fs::exists(fr3) || !fs::exists(lb_path)) {
        fmt::print("[light_bake] {} : fr3 ou .lightbake absent, ignore\n", lvl);
        all_ok = false;
        continue;
      }
      Level lev;
      bool weld = false;
      load_level(fr3, opt.fr3_dir / mesh_consolidate_bake_name(lvl), lev, weld);
      local_lights::ExtractStats llst;
      auto lights = local_lights::extract(lev, lex, &llst);
      std::vector<u8> body;
      local_lights::serialize(lights, body);
      std::string perr;
      if (!patch_lights_section(lb_path, body, &perr)) {
        fmt::print("[light_bake] {} : echec patch lights ({})\n", lvl, perr);
        all_ok = false;
        continue;
      }
      fmt::print("[light_bake] {} lights={} instances_lit={} candidates={} unjudged={}\n", lvl,
                 llst.lights, llst.instances_lit, llst.protos_candidate, llst.protos_unjudged);
    }
    return all_ok ? 0 : 2;
  }

  std::string report, csv =
      "level,fr3,weld,trees,colors,colors_used,verts,bvh_tris,rays,art_residual_p50,"
      "art_residual_p95,art_clamped_frac,art_zero_frac,bake_reconstruction_maxdelta,maxdelta_b,verified,"
      "palette_a_bytes_changed,fr3_bytes_changed,probes,probe_bytes,lights,bytes,seconds,regimes,ok\n";
  float worst = 0;
  bool all_ok = true;
  for (const auto& lvl : levels) {
    auto st = bake_level(opt, lvl, mood_text, lex);
    const double cf = st.triples > st.zero ? (double)st.clamped / (st.triples - st.zero) : 0.0;
    std::string blk = fmt::format(
        "== light_bake {} ==\n"
        "fr3={} meshweld_applied={}\n"
        "trees={} colors={} colors_used={} verts={} bvh_tris={} rays={}\n"
        "art_residual_p50={:.4f} art_residual_p95={:.4f} art_clamped_frac={:.4f} art_zero_frac={:.4f}\n"
        "bake_reconstruction_maxdelta={:.4f} maxdelta_b={:.4f} verified_indices={}\n"
        "palette_a_bytes_changed={} fr3_bytes_changed={}\n"
        "art_raw_p05_p25_p50_p75_p95={:.3f},{:.3f},{:.3f},{:.3f},{:.3f} art_clamped_low={} art_clamped_high={}\n"
        "regimes={}\n"
        "probes=0 probe_bytes=0 lights={} lights_instances_lit={} lights_candidates={} "
        "lights_unjudged={}\n"
        "bytes={} seconds={:.1f} ok={}{}\n",
        st.level, st.fr3, st.weld, st.trees, st.colors, st.colors_used, st.verts, st.bvh_tris,
        st.rays, st.art_p50, st.art_p95, cf, st.triples ? (double)st.zero / st.triples : 0.0, st.maxdelta, st.maxdelta_b, st.verified,
        st.palette_a_bytes_changed, st.fr3_bytes_changed, st.raw_p[0], st.raw_p[1], st.raw_p[2],
        st.raw_p[3], st.raw_p[4], st.clamp_low, st.clamp_high, st.regimes, st.ll_lights,
        st.ll_instances_lit, st.ll_candidates, st.ll_unjudged, st.bytes, st.seconds,
        st.ok ? 1 : 0, st.err.empty() ? "" : " err=" + st.err);
    fmt::print("{}", blk);
    fmt::print("[light_bake] {} lights={} instances_lit={} candidates={} unjudged={}\n", st.level,
               st.ll_lights, st.ll_instances_lit, st.ll_candidates, st.ll_unjudged);
    fmt::print("diag skyvis_mean={:.3f} keyvis_mean={:.3f} keyvis_lit_frac={:.3f} nor_stored_frac={:.3f} n_up_frac={:.3f}\n",
               st.sky_n ? st.sky_sum / st.sky_n : 0, st.kv_n ? st.kv_sum / st.kv_n : 0,
               st.kv_n ? (double)st.kv_pos / st.kv_n : 0, st.nvert ? (double)st.nor_stored / st.nvert : 0,
               st.nvert ? (double)st.n_up / st.nvert : 0);
    std::fflush(stdout);
    report += blk;
    csv += fmt::format("{},{},{},{},{},{},{},{},{},{:.4f},{:.4f},{:.4f},{:.4f},{:.4f},{:.4f},{},{},{},0,0,0,{},{:.1f},{},{}\n",
                       st.level, st.fr3, st.weld, st.trees, st.colors, st.colors_used, st.verts,
                       st.bvh_tris, st.rays, st.art_p50, st.art_p95, cf, st.triples ? (double)st.zero / st.triples : 0.0, st.maxdelta,
                       st.maxdelta_b, st.verified, st.palette_a_bytes_changed,
                       st.fr3_bytes_changed, st.bytes, st.seconds, st.regimes, st.ok ? 1 : 0);
    worst = std::max(worst, st.maxdelta);
    all_ok = all_ok && st.ok && st.palette_a_bytes_changed == 0 && st.fr3_bytes_changed == 0;
  }
  if (!opt.report.empty()) file_util::write_text_file(opt.report, report);
  if (!opt.csv.empty()) file_util::write_text_file(opt.csv, csv);
  if (opt.verify && (worst > 2.f || !all_ok)) {
    fmt::print("light_bake --verify: ECHEC (maxdelta={:.4f}, ok={})\n", worst, all_ok);
    return 1;
  }
  return all_ok ? 0 : 2;
}
