// lighting-bake (SPEC-refonte-lumiere §5) : format du compagnon .lightbake et verification de la
// reconstruction, partages par tools/light_bake et par le chargeur du moteur.

#include "LightBake.h"

#include <algorithm>
#include <cmath>
#include <cstddef>
#include <cstring>

namespace tfrag3 {
namespace lightbake {

namespace {

constexpr u32 kFnvBasis = 2166136261u;
constexpr u32 kFnvPrime = 16777619u;

void fnv_bytes(u32& h, const void* p, size_t n) {
  const u8* b = (const u8*)p;
  for (size_t i = 0; i < n; i++) {
    h ^= b[i];
    h *= kFnvPrime;
  }
}

float lum(const float* c) {
  return 2.f * c[0] + 4.f * c[1] + c[2];
}

struct W {
  std::vector<u8> d;
  void raw(const void* p, size_t n) {
    const u8* b = (const u8*)p;
    d.insert(d.end(), b, b + n);
  }
  void u8v(u8 v) { d.push_back(v); }
  void u16v(u16 v) { raw(&v, 2); }
  void u32v(u32 v) { raw(&v, 4); }
  void u64v(u64 v) { raw(&v, 8); }
  void f32v(float v) { raw(&v, 4); }
  void str(const std::string& s) {
    u32v((u32)s.size());
    raw(s.data(), s.size());
  }
  // section prefixee par son identifiant et sa taille
  size_t begin(Section s) {
    u32v((u32)s);
    u32v(0);
    return d.size();
  }
  void end(size_t start) {
    u32 sz = (u32)(d.size() - start);
    memcpy(&d[start - 4], &sz, 4);
  }
};

struct R {
  const u8* p;
  const u8* e;
  bool ok = true;
  bool need(size_t n) {
    if (!ok || (size_t)(e - p) < n) {
      ok = false;
      return false;
    }
    return true;
  }
  template <typename T>
  T get() {
    T v{};
    if (need(sizeof(T))) {
      memcpy(&v, p, sizeof(T));
      p += sizeof(T);
    }
    return v;
  }
  bool bytes(void* out, size_t n) {
    if (!need(n)) {
      return false;
    }
    memcpy(out, p, n);
    p += n;
    return true;
  }
  std::string str() {
    u32 n = get<u32>();
    std::string s;
    if (need(n)) {
      s.assign((const char*)p, n);
      p += n;
    }
    return s;
  }
};

template <typename T>
void write_vec(W& w, const std::vector<T>& v) {
  w.u32v((u32)v.size());
  w.raw(v.data(), v.size() * sizeof(T));
}

template <typename T>
bool read_vec(R& r, std::vector<T>& v, size_t expect) {
  u32 n = r.get<u32>();
  if (!r.ok || n != expect) {
    return false;
  }
  v.resize(n);
  return r.bytes(v.data(), (size_t)n * sizeof(T));
}

}  // namespace

u32 mood_hash(const MoodTable& t) {
  u32 h = kFnvBasis;
  auto q = [&](float f) {
    s32 v = (s32)std::lround((double)f * 1e4);
    fnv_bytes(h, &v, 4);
  };
  for (const auto& m : t.slot) {
    for (int i = 0; i < 3; i++) q(m.direction[i]);
    for (int i = 0; i < 3; i++) q(m.lgt[i]);
    for (int i = 0; i < 3; i++) q(m.amb[i]);
    for (int i = 0; i < 3; i++) q(m.shadow[i]);
  }
  return h;
}

// SPEC §3.2, seuils explicites.
u8 classify_regime(const MoodLight& m) {
  const float l = lum(m.lgt);
  const float a = lum(m.amb);
  const float elev = m.direction[1];
  if (l < 0.02f) {
    return kRegAmbOnly;
  }
  if (elev < -0.2f) {
    return kRegLow;
  }
  if (a < 1e-4f) {
    return kRegSourceOnly;
  }
  const float chroma =
      std::max(std::fabs(m.lgt[0] - m.lgt[1]), std::fabs(m.lgt[1] - m.lgt[2]));
  if (elev > 0.85f && chroma < 0.06f) {
    return kRegDome;
  }
  if (l / a < 1.f) {
    return kRegAmbient;
  }
  return kRegKey;
}

const char* regime_name(u8 r) {
  switch (r) {
    case kRegKey:
      return "cle";
    case kRegDome:
      return "dome";
    case kRegAmbient:
      return "ambiante";
    case kRegLow:
      return "basse";
    case kRegAmbOnly:
      return "seule";
    case kRegSourceOnly:
      return "source";
    default:
      return "?";
  }
}

const char* system_name(u8 s) {
  return s == 0 ? "tfrag" : (s == 1 ? "tie" : "shrub");
}

std::vector<TreeRef> collect_trees(const Level& lev) {
  std::vector<TreeRef> out;
  for (u8 gi = 0; gi < (u8)lev.tfrag_trees.size(); gi++) {
    for (const auto& t : lev.tfrag_trees[gi]) {
      TreeRef r;
      r.system = 0;
      r.geom = gi;
      r.colors = &t.colors;
      r.verts = (const u8*)t.unpacked.vertices.data();
      r.vcount = t.unpacked.vertices.size();
      r.vstride = sizeof(PreloadedVertex);
      r.indices = &t.unpacked.indices;
      r.use_strips = t.use_strips;
      r.off_nor = offsetof(PreloadedVertex, nor);
      r.off_color_index = offsetof(PreloadedVertex, color_index);
      out.push_back(r);
    }
  }
  for (u8 gi = 0; gi < (u8)lev.tie_trees.size(); gi++) {
    for (const auto& t : lev.tie_trees[gi]) {
      TreeRef r;
      r.system = 1;
      r.geom = gi;
      r.colors = &t.colors;
      r.verts = (const u8*)t.unpacked.vertices.data();
      r.vcount = t.unpacked.vertices.size();
      r.vstride = sizeof(PreloadedVertex);
      r.indices = &t.unpacked.indices;
      r.use_strips = t.use_strips;
      r.off_nor = offsetof(PreloadedVertex, nor);
      r.off_color_index = offsetof(PreloadedVertex, color_index);
      out.push_back(r);
    }
  }
  for (const auto& t : lev.shrub_trees) {
    TreeRef r;
    r.system = 2;
    r.geom = 0;
    r.colors = &t.time_of_day_colors;
    r.verts = (const u8*)t.unpacked.vertices.data();
    r.vcount = t.unpacked.vertices.size();
    r.vstride = sizeof(ShrubGpuVertex);
    r.indices = &t.indices;
    r.use_strips = true;
    r.off_nor = offsetof(ShrubGpuVertex, nor);
    r.off_color_index = offsetof(ShrubGpuVertex, color_index);
    out.push_back(r);
  }
  return out;
}

u64 palette_hash(const PackedTimeOfDay& p) {
  u64 h = 1469598103934665603ull;
  for (u8 b : p.data) {
    h ^= b;
    h *= 1099511628211ull;
  }
  h ^= p.color_count;
  h *= 1099511628211ull;
  return h;
}

std::string lightbake_name(const std::string& level_name) {
  return level_name + ".lightbake";
}

std::vector<u8> serialize(const Bake& b) {
  W w;
  w.u32v(kMagic);
  w.u32v(kVersion);
  // --- empreinte ---
  w.str(b.level_name);
  u32 num_verts = 0;
  for (const auto& t : b.trees) {
    num_verts += t.vert_count;
  }
  w.u32v(num_verts);
  w.u32v((u32)b.trees.size());
  for (const auto& t : b.trees) {
    w.u8v(t.system);
    w.u8v(t.geom);
    w.u32v(t.vert_count);
    w.u32v(t.color_count);
    w.u64v(t.palette_a_hash);
  }
  w.u32v(b.tfrag3_version);
  w.u32v(b.mood_hash);

  auto per_tree = [&](Section s, auto&& body) {
    size_t st = w.begin(s);
    for (u32 i = 0; i < (u32)b.trees.size(); i++) {
      w.u32v(i);
      body(b.trees[i]);
    }
    w.end(st);
  };
  per_tree(kSecPaletteB, [&](const TreeBake& t) {
    w.u32v(t.color_count);
    write_vec(w, t.palette_b);
  });
  per_tree(kSecSkyvis, [&](const TreeBake& t) { write_vec(w, t.skyvis); });
  per_tree(kSecAo, [&](const TreeBake& t) { write_vec(w, t.ao); });
  per_tree(kSecBentN, [&](const TreeBake& t) { write_vec(w, t.bent_n); });
  per_tree(kSecKeyVis, [&](const TreeBake& t) { write_vec(w, t.keyvis); });
  per_tree(kSecArt, [&](const TreeBake& t) { write_vec(w, t.art); });

  {
    size_t st = w.begin(kSecRegime);
    w.raw(b.regime, kSlots);
    for (const auto& m : b.mood.slot) {
      for (int i = 0; i < 3; i++) w.f32v(m.amb[i]);
    }
    for (const auto& m : b.mood.slot) {
      for (int i = 0; i < 3; i++) w.f32v(m.lgt[i]);
    }
    // la table entiere, pour que le rapport et le moteur relisent ce avec quoi on a cuit
    for (const auto& m : b.mood.slot) {
      for (int i = 0; i < 3; i++) w.f32v(m.direction[i]);
      for (int i = 0; i < 3; i++) w.f32v(m.shadow[i]);
    }
    w.end(st);
  }
  // Sondes, lumieres et visibilite par lumiere : sections presentes, VIDES dans la version 1
  // (non cuites par cet essai — voir le rapport de l'item). count = 0 est explicite.
  {
    size_t st = w.begin(kSecProbes);
    for (int i = 0; i < 4; i++) w.f32v(0.f);
    for (int i = 0; i < 3; i++) w.u32v(0);
    w.u32v(0);
    w.end(st);
  }
  {
    size_t st = w.begin(kSecLights);
    w.u32v(0);
    w.u32v(0);
    w.end(st);
  }
  {
    size_t st = w.begin(kSecLightVis);
    w.u32v(0);
    w.end(st);
  }
  {
    size_t st = w.begin(kSecStats);
    w.str(b.stats);
    w.end(st);
  }
  return std::move(w.d);
}

bool deserialize(const std::vector<u8>& data, Bake& b, std::string* err) {
  auto fail = [&](const char* why) {
    if (err) {
      *err = why;
    }
    return false;
  };
  R r{data.data(), data.data() + data.size()};
  if (r.get<u32>() != kMagic) {
    return fail("magic");
  }
  if (r.get<u32>() != kVersion) {
    return fail("version");
  }
  b.level_name = r.str();
  r.get<u32>();  // num_verts : redondant avec les arbres
  u32 nt = r.get<u32>();
  if (!r.ok || nt > 100000) {
    return fail("header");
  }
  b.trees.assign(nt, TreeBake{});
  for (auto& t : b.trees) {
    t.system = r.get<u8>();
    t.geom = r.get<u8>();
    t.vert_count = r.get<u32>();
    t.color_count = r.get<u32>();
    t.palette_a_hash = r.get<u64>();
  }
  b.tfrag3_version = r.get<u32>();
  b.mood_hash = r.get<u32>();
  if (!r.ok) {
    return fail("header");
  }
  while (r.ok && r.p < r.e) {
    u32 sec = r.get<u32>();
    u32 sz = r.get<u32>();
    if (!r.need(sz)) {
      return fail("section-size");
    }
    R s{r.p, r.p + sz};
    r.p += sz;
    auto per_tree = [&](auto&& body) {
      for (u32 i = 0; i < nt; i++) {
        if (s.get<u32>() != i || !body(b.trees[i])) {
          return false;
        }
      }
      return s.ok;
    };
    bool ok = true;
    switch (sec) {
      case kSecPaletteB:
        ok = per_tree([&](TreeBake& t) {
          if (s.get<u32>() != t.color_count) {
            return false;
          }
          return read_vec(s, t.palette_b, (size_t)((t.color_count + 3) / 4) * 128);
        });
        break;
      case kSecSkyvis:
        ok = per_tree([&](TreeBake& t) { return read_vec(s, t.skyvis, t.color_count); });
        break;
      case kSecAo:
        ok = per_tree([&](TreeBake& t) { return read_vec(s, t.ao, t.color_count); });
        break;
      case kSecBentN:
        ok = per_tree([&](TreeBake& t) { return read_vec(s, t.bent_n, 2 * (size_t)t.vert_count); });
        break;
      case kSecKeyVis:
        ok = per_tree(
            [&](TreeBake& t) { return read_vec(s, t.keyvis, (size_t)t.color_count * kSlots); });
        break;
      case kSecArt:
        ok = per_tree(
            [&](TreeBake& t) { return read_vec(s, t.art, (size_t)t.color_count * kSlots * 3); });
        break;
      case kSecRegime:
        s.bytes(b.regime, kSlots);
        for (auto& m : b.mood.slot) {
          for (int i = 0; i < 3; i++) m.amb[i] = s.get<float>();
        }
        for (auto& m : b.mood.slot) {
          for (int i = 0; i < 3; i++) m.lgt[i] = s.get<float>();
        }
        for (auto& m : b.mood.slot) {
          for (int i = 0; i < 3; i++) m.direction[i] = s.get<float>();
          for (int i = 0; i < 3; i++) m.shadow[i] = s.get<float>();
        }
        ok = s.ok;
        break;
      case kSecStats:
        b.stats = s.str();
        ok = s.ok;
        break;
      default:
        // sondes / lumieres / visibilite par lumiere : non consommees par le moteur (version 1)
        break;
    }
    if (!ok) {
      return fail("section");
    }
  }
  for (const auto& t : b.trees) {
    if (t.palette_b.empty() || t.skyvis.size() != t.color_count ||
        t.keyvis.size() != (size_t)t.color_count * kSlots ||
        t.art.size() != (size_t)t.color_count * kSlots * 3) {
      return fail("missing-section");
    }
  }
  return r.ok ? true : fail("truncated");
}

VerifyResult verify(const Level& lev, const Bake& b, const MoodTable& live, u32 stride, u64 cap) {
  VerifyResult res;
  if (b.tfrag3_version != TFRAG3_VERSION) {
    res.reject_reason = "tfrag3_version";
    return res;
  }
  if (b.mood_hash != mood_hash(live)) {
    res.reject_reason = "mood_hash";
    return res;
  }
  const auto refs = collect_trees(lev);
  if (refs.size() != b.trees.size()) {
    res.reject_reason = "num_trees";
    return res;
  }
  if (stride == 0) {
    stride = 1;
  }
  res.accepted = true;
  for (size_t ti = 0; ti < refs.size(); ti++) {
    const auto& ref = refs[ti];
    const auto& tb = b.trees[ti];
    const auto& A = *ref.colors;
    if (ref.system != tb.system || ref.geom != tb.geom || A.color_count != tb.color_count ||
        A.data.size() != tb.palette_b.size() || palette_hash(A) != tb.palette_a_hash) {
      res.trees_rejected++;
      continue;
    }
    res.trees_checked++;
    for (u32 c = 0; c < tb.color_count && res.indices_checked < cap; c += stride) {
      res.indices_checked++;
      for (int s = 0; s < kSlots; s++) {
        const u8 kv = tb.keyvis[(size_t)c * kSlots + s];
        const auto& m = live.slot[s];
        for (int ch = 0; ch < 3; ch++) {
          const size_t o = palette_offset(c, s, ch);
          const float a = A.data[o];
          const float bb = tb.palette_b[o];
          const u16 q = tb.art[((size_t)c * kSlots + s) * 3 + ch];
          res.values_checked++;
          if (q == 0) {
            res.clamped_checked++;
            res.maxdelta = std::max(res.maxdelta, std::fabs(bb - a));
            res.maxdelta_b = std::max(res.maxdelta_b, std::fabs(bb - a));
            continue;
          }
          const float art = q / kArtScale;
          const float ind = kPaletteOne * m.amb[ch] * art;
          const float dir = kPaletteOne * m.lgt[ch] * (kv / 255.f) * art;
          res.maxdelta = std::max(res.maxdelta, std::fabs(bb + dir - a));
          res.maxdelta_b = std::max(res.maxdelta_b, std::fabs(std::round(ind) - bb));
        }
        // l'alpha n'est pas de la lumiere : B le recopie
        const size_t oa = palette_offset(c, s, 3);
        res.maxdelta = std::max(res.maxdelta, std::fabs((float)tb.palette_b[oa] - A.data[oa]));
      }
    }
  }
  return res;
}

}  // namespace lightbake
}  // namespace tfrag3
