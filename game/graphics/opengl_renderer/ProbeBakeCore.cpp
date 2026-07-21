// Grecharged-lightprobes: OFFLINE, GL-free light-probe baker core. See ProbeBakeCore.h.
//
// Pipeline: collect stock baked per-vertex radiance (8 TOD keyframes, suns included) + collision
// -> regular grid over the geometry AABB -> per baked cell, CAPTURE a small environment cubemap by
// binning the nearest surrounding lit surface per texel (occlusion) + sky/ground fill -> project to
// L2 irradiance SH (diffuse, drop-in for rt_sh_ambient) and keep the cube (reflection anchors).
// Interiors auto-detected by a ceiling ray on the collision mesh.

#include "ProbeBakeCore.h"

#include <algorithm>
#include <cmath>
#include <cstring>
#include <fstream>
#include <unordered_map>

#include "common/custom_data/Tfrag3Data.h"
#include "common/util/compress.h"

#include "fmt/format.h"

namespace probe_bake {

namespace {

constexpr int FACE = PRB_CUBE_FACE;
constexpr float GU_PER_M = 4096.0f;

// ---- byte buffer helpers (mirror GrassBakeCore) ----
template <typename T>
void put(std::vector<u8>& b, T v) {
  const u8* p = reinterpret_cast<const u8*>(&v);
  b.insert(b.end(), p, p + sizeof(T));
}
void put_bytes(std::vector<u8>& b, const void* p, size_t n) {
  const u8* c = reinterpret_cast<const u8*>(p);
  b.insert(b.end(), c, c + n);
}
template <typename T>
bool get(const std::vector<u8>& b, size_t& off, T& v) {
  if (off + sizeof(T) > b.size())
    return false;
  std::memcpy(&v, b.data() + off, sizeof(T));
  off += sizeof(T);
  return true;
}
bool get_bytes(const std::vector<u8>& b, size_t& off, void* p, size_t n) {
  if (off + n > b.size())
    return false;
  std::memcpy(p, b.data() + off, n);
  off += n;
  return true;
}

// ---- SH (real, L2) basis, matches shader rt_sh_ambient() ----
inline void sh_basis(float x, float y, float z, float Y[PRB_NUM_SH]) {
  Y[0] = 0.282095f;
  Y[1] = 0.488603f * y;
  Y[2] = 0.488603f * z;
  Y[3] = 0.488603f * x;
  Y[4] = 1.092548f * x * y;
  Y[5] = 1.092548f * y * z;
  Y[6] = 0.315392f * (3.0f * z * z - 1.0f);
  Y[7] = 1.092548f * x * z;
  Y[8] = 0.546274f * (x * x - y * y);
}
// cosine-convolution (A_l/pi) baked into the coeffs, so shader Sum(sh[c]*Y_c(n)) = ambient radiance.
constexpr float kAl[PRB_NUM_SH] = {1.0f,  2.0f / 3.0f, 2.0f / 3.0f, 2.0f / 3.0f, 0.25f,
                                   0.25f, 0.25f,       0.25f,       0.25f};

// ---- cube map convention (matches GL_TEXTURE_CUBE_MAP face order +X,-X,+Y,-Y,+Z,-Z) ----
inline void face_uv_to_dir(int face, float u, float v, float& x, float& y, float& z) {
  switch (face) {
    case 0: x = 1;  y = -v; z = -u; break;   // +X
    case 1: x = -1; y = -v; z = u;  break;   // -X
    case 2: x = u;  y = 1;  z = v;  break;   // +Y
    case 3: x = u;  y = -1; z = -v; break;   // -Y
    case 4: x = u;  y = -v; z = 1;  break;   // +Z
    default: x = -u; y = -v; z = -1; break;  // -Z
  }
  float l = std::sqrt(x * x + y * y + z * z);
  x /= l; y /= l; z /= l;
}
inline void dir_to_face_texel(float x, float y, float z, int& face, int& iu, int& iv) {
  float ax = std::fabs(x), ay = std::fabs(y), az = std::fabs(z);
  float u, vv;
  if (ax >= ay && ax >= az) {
    if (x > 0) { face = 0; u = -z / ax; vv = -y / ax; }
    else { face = 1; u = z / ax; vv = -y / ax; }
  } else if (ay >= ax && ay >= az) {
    if (y > 0) { face = 2; u = x / ay; vv = z / ay; }
    else { face = 3; u = x / ay; vv = -z / ay; }
  } else {
    if (z > 0) { face = 4; u = x / az; vv = -y / az; }
    else { face = 5; u = -x / az; vv = -y / az; }
  }
  iu = (int)((u * 0.5f + 0.5f) * FACE);
  iv = (int)((vv * 0.5f + 0.5f) * FACE);
  iu = iu < 0 ? 0 : (iu >= FACE ? FACE - 1 : iu);
  iv = iv < 0 ? 0 : (iv >= FACE ? FACE - 1 : iv);
}
inline float area_element(float x, float y) {
  return std::atan2(x * y, std::sqrt(x * x + y * y + 1.0f));
}
inline float texel_solid_angle(int iu, int iv) {
  float u0 = ((float)iu / FACE) * 2.0f - 1.0f, u1 = ((float)(iu + 1) / FACE) * 2.0f - 1.0f;
  float v0 = ((float)iv / FACE) * 2.0f - 1.0f, v1 = ((float)(iv + 1) / FACE) * 2.0f - 1.0f;
  return area_element(u0, v0) - area_element(u0, v1) - area_element(u1, v0) + area_element(u1, v1);
}

struct Sample {
  float x, y, z;
  u8 rgb[PRB_NUM_TOD][3];  // stock baked color per TOD keyframe (suns included)
};

struct Tri {
  float p0[3], e1[3], e2[3];
  float ny;  // sign only: <0 => ceiling (down-facing)
};

// spatial hash keys
struct Key3 {
  s32 a, b, c;
  bool operator==(const Key3& o) const { return a == o.a && b == o.b && c == o.c; }
};
struct Key3Hash {
  std::size_t operator()(const Key3& k) const {
    return (std::size_t)(k.a * 73856093) ^ (std::size_t)(k.b * 19349663) ^
           (std::size_t)(k.c * 83492791);
  }
};
struct Key2 {
  s32 a, b;
  bool operator==(const Key2& o) const { return a == o.a && b == o.b; }
};
struct Key2Hash {
  std::size_t operator()(const Key2& k) const {
    return (std::size_t)(k.a * 73856093) ^ (std::size_t)(k.b * 19349663);
  }
};

// Moller-Trumbore, only positive t, up to tmax. Ray origin o, dir d (unit).
bool ray_tri(const float o[3], const float d[3], const Tri& t, float tmax, float& thit) {
  const float EPS = 1e-6f;
  float h[3] = {d[1] * t.e2[2] - d[2] * t.e2[1], d[2] * t.e2[0] - d[0] * t.e2[2],
                d[0] * t.e2[1] - d[1] * t.e2[0]};
  float a = t.e1[0] * h[0] + t.e1[1] * h[1] + t.e1[2] * h[2];
  if (a > -EPS && a < EPS)
    return false;
  float f = 1.0f / a;
  float s[3] = {o[0] - t.p0[0], o[1] - t.p0[1], o[2] - t.p0[2]};
  float u = f * (s[0] * h[0] + s[1] * h[1] + s[2] * h[2]);
  if (u < 0 || u > 1)
    return false;
  float q[3] = {s[1] * t.e1[2] - s[2] * t.e1[1], s[2] * t.e1[0] - s[0] * t.e1[2],
                s[0] * t.e1[1] - s[1] * t.e1[0]};
  float vv = f * (d[0] * q[0] + d[1] * q[1] + d[2] * q[2]);
  if (vv < 0 || u + vv > 1)
    return false;
  float tt = f * (t.e2[0] * q[0] + t.e2[1] * q[1] + t.e2[2] * q[2]);
  if (tt > EPS && tt <= tmax) {
    thit = tt;
    return true;
  }
  return false;
}

}  // namespace

ProbeGrid bake_level(const tfrag3::Level& lev,
                     const std::string& level_name,
                     u64 fr3_size,
                     const BakeParams& p) {
  ProbeGrid g;
  g.params = p;
  g.fr3_size = fr3_size;
  std::strncpy(g.level_name, level_name.c_str(), sizeof(g.level_name) - 1);

  const float cell = p.cell_m * GU_PER_M;
  const float gather = p.gather_radius_m * GU_PER_M;
  const float gather2 = gather * gather;
  const float ceilmax = p.ceiling_probe_m * GU_PER_M;
  g.cell_gu = cell;

  // ---------- 1. collect baked surface radiance samples ----------
  std::vector<Sample> samples;
  auto add_from = [&](const std::vector<std::pair<std::array<float, 3>, u16>>& verts,
                      const tfrag3::PackedTimeOfDay& colors) {
    if (colors.color_count == 0)
      return;
    for (const auto& vc : verts) {
      u16 ci = vc.second;
      if (ci >= colors.color_count)
        continue;
      Sample s;
      s.x = vc.first[0];
      s.y = vc.first[1];
      s.z = vc.first[2];
      for (int tod = 0; tod < PRB_NUM_TOD; tod++)
        for (int ch = 0; ch < 3; ch++)
          s.rgb[tod][ch] = colors.read(ci, tod, ch);
      samples.push_back(s);
    }
  };
  {
    std::vector<std::pair<std::array<float, 3>, u16>> buf;
    for (const auto& geo : lev.tfrag_trees)
      for (const auto& tree : geo) {
        buf.clear();
        buf.reserve(tree.unpacked.vertices.size());
        for (const auto& v : tree.unpacked.vertices)
          buf.push_back({{v.x, v.y, v.z}, v.color_index});
        add_from(buf, tree.colors);
      }
    for (const auto& geo : lev.tie_trees)
      for (const auto& tree : geo) {
        buf.clear();
        buf.reserve(tree.unpacked.vertices.size());
        for (const auto& v : tree.unpacked.vertices)
          buf.push_back({{v.x, v.y, v.z}, v.color_index});
        add_from(buf, tree.colors);
      }
    for (const auto& tree : lev.shrub_trees) {
      buf.clear();
      buf.reserve(tree.unpacked.vertices.size());
      for (const auto& v : tree.unpacked.vertices)
        buf.push_back({{v.x, v.y, v.z}, v.color_index});
      add_from(buf, tree.time_of_day_colors);
    }
  }

  fmt::print("[probe-bake] level='{}' surface samples={} collision verts={}\n", level_name,
             (u64)samples.size(), (u64)lev.collision.vertices.size());
  if (samples.size() < (size_t)std::max(1, p.min_samples)) {
    fmt::print("[probe-bake] not enough samples, empty grid.\n");
    return g;
  }

  // ---------- 2. EXPLORABLE AABB + grid ----------
  // The level fr3 includes distant LOD / neighbour visual geometry (extent tens of km). The
  // COLLISION mesh, by contrast, only covers where the player can walk / collide == the explorable
  // world, so it is the correct probe-grid bound. Percentile-clip it too (safety vs stray tris),
  // and pad up a little in Y so ceilings/roofs above the top walkable surface are inside the grid.
  float mn[3], mx[3];
  {
    const float PCT_LO = 0.002f, PCT_HI = 0.998f;
    const auto& cv = lev.collision.vertices;
    const bool use_coll = cv.size() >= 12;
    size_t n = use_coll ? cv.size() : samples.size();
    size_t step = std::max<size_t>(1, n / 300000);
    for (int ax = 0; ax < 3; ax++) {
      std::vector<float> v;
      v.reserve(n / step + 1);
      for (size_t i = 0; i < n; i += step) {
        float val;
        if (use_coll)
          val = ax == 0 ? cv[i].x : (ax == 1 ? cv[i].y : cv[i].z);
        else
          val = ax == 0 ? samples[i].x : (ax == 1 ? samples[i].y : samples[i].z);
        v.push_back(val);
      }
      std::sort(v.begin(), v.end());
      mn[ax] = v[(size_t)(v.size() * PCT_LO)];
      mx[ax] = v[std::min(v.size() - 1, (size_t)(v.size() * PCT_HI))];
    }
    mx[1] += p.ceiling_probe_m * GU_PER_M;  // room for roofs above the highest floor
  }
  for (int i = 0; i < 3; i++) {
    g.origin_gu[i] = mn[i] - cell;  // 1-cell pad
    g.dims[i] = (s32)std::ceil((mx[i] - mn[i]) / cell) + 3;
    if (g.dims[i] > 512) g.dims[i] = 512;  // safety clamp
  }
  fmt::print("[probe-bake] AABB m=({:.1f},{:.1f},{:.1f})..({:.1f},{:.1f},{:.1f}) grid={}x{}x{} "
             "cell={:.1f}m\n",
             mn[0] / GU_PER_M, mn[1] / GU_PER_M, mn[2] / GU_PER_M, mx[0] / GU_PER_M,
             mx[1] / GU_PER_M, mx[2] / GU_PER_M, g.dims[0], g.dims[1], g.dims[2], p.cell_m);

  // ---------- 3. sample spatial hash (bin = gather) ----------
  std::unordered_map<Key3, std::vector<u32>, Key3Hash> shash;
  auto sbin = [&](float x, float y, float z) {
    return Key3{(s32)std::floor(x / gather), (s32)std::floor(y / gather), (s32)std::floor(z / gather)};
  };
  for (u32 i = 0; i < samples.size(); i++)
    shash[sbin(samples[i].x, samples[i].y, samples[i].z)].push_back(i);

  // ---------- 4. collision tris + xz hash (bin = cell) for ceiling ray ----------
  std::vector<Tri> tris;
  {
    const auto& cv = lev.collision.vertices;
    tris.reserve(cv.size() / 3);
    for (size_t k = 0; k + 2 < cv.size(); k += 3) {
      Tri t;
      t.p0[0] = cv[k].x; t.p0[1] = cv[k].y; t.p0[2] = cv[k].z;
      t.e1[0] = cv[k + 1].x - cv[k].x; t.e1[1] = cv[k + 1].y - cv[k].y; t.e1[2] = cv[k + 1].z - cv[k].z;
      t.e2[0] = cv[k + 2].x - cv[k].x; t.e2[1] = cv[k + 2].y - cv[k].y; t.e2[2] = cv[k + 2].z - cv[k].z;
      t.ny = (float)cv[k].ny;
      tris.push_back(t);
    }
  }
  // Only CEILING candidates (down-facing, ny<0) matter for interior detection; skip the huge
  // up-facing ground tris entirely (they would blow up the xz hash). A tri spanning an absurd
  // number of cells goes on a "big" list checked for every interior test.
  std::unordered_map<Key2, std::vector<u32>, Key2Hash> chash;
  std::vector<u32> big_ceiling;
  auto cbin = [&](float x, float z) { return Key2{(s32)std::floor(x / cell), (s32)std::floor(z / cell)}; };
  u64 chash_inserts = 0;
  for (u32 i = 0; i < tris.size(); i++) {
    const Tri& t = tris[i];
    if (t.ny >= 0)
      continue;  // ceilings only
    float x0 = t.p0[0], z0 = t.p0[2];
    float px1 = x0 + t.e1[0], pz1 = z0 + t.e1[2], px2 = x0 + t.e2[0], pz2 = z0 + t.e2[2];
    float xmn = std::min({x0, px1, px2}), xmx = std::max({x0, px1, px2});
    float zmn = std::min({z0, pz1, pz2}), zmx = std::max({z0, pz1, pz2});
    s32 bx0 = (s32)std::floor(xmn / cell), bx1 = (s32)std::floor(xmx / cell);
    s32 bz0 = (s32)std::floor(zmn / cell), bz1 = (s32)std::floor(zmx / cell);
    if ((s64)(bx1 - bx0 + 1) * (bz1 - bz0 + 1) > 256) {
      big_ceiling.push_back(i);
      continue;
    }
    for (s32 bx = bx0; bx <= bx1; bx++)
      for (s32 bz = bz0; bz <= bz1; bz++) {
        chash[Key2{bx, bz}].push_back(i);
        chash_inserts++;
      }
  }
  fmt::print("[probe-bake] ceiling tris hashed (inserts={}, big={})\n", chash_inserts,
             (u64)big_ceiling.size());
  std::fflush(stdout);

  // ---------- 4b. candidate cells = a probe LAYER above each WALKABLE surface (all heights) ----------
  // Owner spec: "one probe layer just above EACH walkable collision surface" at all explorable
  // heights, NOT a brute-force dense volume. Splat a short vertical band (BAND cells, ~standing
  // height) above every up-facing collision triangle. Only these cells (+ their interiors) are
  // baked => probes exactly where geometry is rendered, at every platform/ledge/floor/roof.
  const s32 DX = g.dims[0], DY = g.dims[1], DZ = g.dims[2];
  const size_t NCELL = (size_t)DX * DY * DZ;
  std::vector<u8> candidate(NCELL, 0);
  auto cellidx = [&](s32 ix, s32 iy, s32 iz) -> size_t {
    return ((size_t)iz * DY + iy) * DX + ix;
  };
  const int BAND = 3;  // cells above a floor (~standing/jump height)
  u64 cand_marked = 0;
  {
    const auto& cv = lev.collision.vertices;
    auto mark = [&](float x, float y, float z) {
      s32 ix = (s32)std::floor((x - g.origin_gu[0]) / cell);
      s32 iz = (s32)std::floor((z - g.origin_gu[2]) / cell);
      s32 iy = (s32)std::floor((y - g.origin_gu[1]) / cell);
      if (ix < 0 || ix >= DX || iz < 0 || iz >= DZ) return;
      for (int l = 0; l <= BAND; l++) {
        s32 jy = iy + l;
        if (jy < 0 || jy >= DY) continue;
        u8& c = candidate[cellidx(ix, jy, iz)];
        if (!c) { c = 1; cand_marked++; }
      }
    };
    for (size_t k = 0; k + 2 < cv.size(); k += 3) {
      if (cv[k].ny <= 0) continue;  // walkable = up-facing
      mark(cv[k].x, cv[k].y, cv[k].z);
      mark(cv[k + 1].x, cv[k + 1].y, cv[k + 1].z);
      mark(cv[k + 2].x, cv[k + 2].y, cv[k + 2].z);
      // centroid too (fills large tris)
      mark((cv[k].x + cv[k + 1].x + cv[k + 2].x) / 3.0f,
           (cv[k].y + cv[k + 1].y + cv[k + 2].y) / 3.0f,
           (cv[k].z + cv[k + 1].z + cv[k + 2].z) / 3.0f);
    }
  }
  fmt::print("[probe-bake] candidate cells (walkable band, BAND={}): {} of {} lattice\n", BAND,
             cand_marked, (u64)NCELL);
  std::fflush(stdout);

  // ---------- 5. global sky / ground radiance per TOD (top-luma average) ----------
  float sky_rad[PRB_NUM_TOD][3], gnd_rad[PRB_NUM_TOD][3];
  {
    size_t step = std::max<size_t>(1, samples.size() / 20000);
    for (int tod = 0; tod < PRB_NUM_TOD; tod++) {
      std::vector<float> lum;
      for (size_t i = 0; i < samples.size(); i += step) {
        const u8* c = samples[i].rgb[tod];
        lum.push_back((0.299f * c[0] + 0.587f * c[1] + 0.114f * c[2]) / 255.0f);
      }
      std::sort(lum.begin(), lum.end());
      float thr = lum.empty() ? 0.f : lum[(size_t)(lum.size() * 0.85f)];
      double acc[3] = {0, 0, 0};
      u64 n = 0;
      for (size_t i = 0; i < samples.size(); i += step) {
        const u8* c = samples[i].rgb[tod];
        float l = (0.299f * c[0] + 0.587f * c[1] + 0.114f * c[2]) / 255.0f;
        if (l >= thr) {
          acc[0] += c[0]; acc[1] += c[1]; acc[2] += c[2]; n++;
        }
      }
      for (int ch = 0; ch < 3; ch++) {
        float v = n ? (float)(acc[ch] / n) / 255.0f : 0.5f;
        sky_rad[tod][ch] = v * p.sky_gain;
        gnd_rad[tod][ch] = v * 0.35f * p.sky_gain;  // dim ground bounce
      }
    }
  }

  // ---------- 6. iterate grid cells ----------
  // per-texel direction + SH-basis*solid-angle precompute (so the per-cell projection is one pass).
  const int NT = 6 * FACE * FACE;
  static float texdir[6 * FACE * FACE][3];
  static float texYsa[6 * FACE * FACE][PRB_NUM_SH];  // Y_c(dir) * texel_solid_angle
  for (int f = 0; f < 6; f++)
    for (int iv = 0; iv < FACE; iv++)
      for (int iu = 0; iu < FACE; iu++) {
        int ti = f * FACE * FACE + iv * FACE + iu;
        float u = ((iu + 0.5f) / FACE) * 2.0f - 1.0f, v = ((iv + 0.5f) / FACE) * 2.0f - 1.0f;
        face_uv_to_dir(f, u, v, texdir[ti][0], texdir[ti][1], texdir[ti][2]);
        float sa = texel_solid_angle(iu, iv);
        float Y[PRB_NUM_SH];
        sh_basis(texdir[ti][0], texdir[ti][1], texdir[ti][2], Y);
        for (int c = 0; c < PRB_NUM_SH; c++)
          texYsa[ti][c] = Y[c] * sa;
      }

  std::vector<float> texD(NT);
  std::vector<u32> texSi(NT);
  const int kMaxGather = 8000;  // cap dense cells (nearest-per-texel converges well before this)
  // Reflection anchors: at most one per ANCHOR_SPACING^3 region (the runtime binds ONE cube at a
  // time, nearest to the camera, so a spread handful covers the level), capped. Interiors dedup on
  // a finer spacing so every room gets its own reflection.
  std::unordered_map<Key3, u8, Key3Hash> anchor_bins;
  const int ANCHOR_SPACING = 4;      // exterior: one per 4 cells (~16 m)
  const int ANCHOR_SPACING_IN = 2;   // interior: one per 2 cells (~8 m)
  const size_t kMaxAnchors = 900;

  for (s32 iz = 0; iz < g.dims[2]; iz++) {
    for (s32 iy = 0; iy < g.dims[1]; iy++) {
      for (s32 ix = 0; ix < g.dims[0]; ix++) {
        if (!candidate[cellidx(ix, iy, iz)]) continue;  // only bake the walkable band + interiors
        float cx = g.origin_gu[0] + (ix + 0.5f) * cell;
        float cy = g.origin_gu[1] + (iy + 0.5f) * cell;
        float cz = g.origin_gu[2] + (iz + 0.5f) * cell;

        // gather nearby samples (3x3x3 bins), keeping the NEAREST sample per cube texel (occlusion)
        Key3 kc = sbin(cx, cy, cz);
        int ngather = 0;
        for (int t = 0; t < NT; t++) texD[t] = -1.0f;

        for (s32 db = -1; db <= 1 && ngather < kMaxGather; db++)
          for (s32 da = -1; da <= 1 && ngather < kMaxGather; da++)
            for (s32 dc = -1; dc <= 1 && ngather < kMaxGather; dc++) {
              auto it = shash.find(Key3{kc.a + da, kc.b + db, kc.c + dc});
              if (it == shash.end()) continue;
              for (u32 si : it->second) {
                const Sample& s = samples[si];
                float dx = s.x - cx, dy = s.y - cy, dz = s.z - cz;
                float d2 = dx * dx + dy * dy + dz * dz;
                if (d2 > gather2 || d2 < 1e-3f) continue;
                if (++ngather >= kMaxGather) break;
                float d = std::sqrt(d2);
                int face, iu, iv;
                dir_to_face_texel(dx / d, dy / d, dz / d, face, iu, iv);
                int ti = face * FACE * FACE + iv * FACE + iu;
                if (texD[ti] < 0.0f || d < texD[ti]) {
                  texD[ti] = d;      // nearest wins => occlusion
                  texSi[ti] = si;    // which lit surface this texel sees
                }
              }
            }
        if (ngather < p.min_samples) continue;

        // openness (upper-hemisphere empty texels = sky visibility)
        int up_total = 0, up_empty = 0;
        for (int t = 0; t < NT; t++)
          if (texdir[t][1] > 0.2f) { up_total++; if (texD[t] < 0.0f) up_empty++; }
        float openness = up_total ? (float)up_empty / up_total : 1.0f;

        // interior detection: a down-facing collision ceiling overhead AND low sky openness (a real
        // ROOM has both a roof and walls). Requiring low openness rejects tree-canopy / bridge /
        // cliff-overhang false positives that still see open sky around them.
        u8 interior = 0;
        if (openness < 0.40f) {
          float o[3] = {cx, cy, cz}, d[3] = {0, 1, 0}, thit;
          auto it = chash.find(cbin(cx, cz));
          if (it != chash.end()) {
            for (u32 tri_i : it->second)
              if (ray_tri(o, d, tris[tri_i], ceilmax, thit)) { interior = 1; break; }
          }
          if (!interior)
            for (u32 tri_i : big_ceiling)
              if (ray_tri(o, d, tris[tri_i], ceilmax, thit)) { interior = 1; break; }
        }

        ProbeCell pc;
        pc.ix = (s16)ix; pc.iy = (s16)iy; pc.iz = (s16)iz;
        pc.interior = interior;
        pc.openness = openness;

        // reflection anchor: one per spacing^3 region (finer indoors), capped.
        bool anchor = false;
        if (g.refl.size() < kMaxAnchors) {
          int sp = interior ? ANCHOR_SPACING_IN : ANCHOR_SPACING;
          Key3 abk{ix / sp, iy / sp, iz / sp};
          if (!anchor_bins.count(abk)) {
            anchor = true;
            anchor_bins[abk] = 1;
          }
        }
        std::vector<u8> anchor_cube;
        if (anchor) anchor_cube.resize(PRB_NUM_TOD * NT * 3);

        // ONE texel pass: capture radiance per texel (occlusion sample or sky/ground fill) and
        // accumulate all 8 TOD SH coeffs + the anchor cube together.
        double coeff[PRB_NUM_TOD][PRB_NUM_SH][3] = {};
        for (int t = 0; t < NT; t++) {
          const u8* occ = (texD[t] >= 0.0f) ? samples[texSi[t]].rgb[0] : nullptr;
          const bool up = texdir[t][1] > 0;
          const float* ys = texYsa[t];
          for (int tod = 0; tod < PRB_NUM_TOD; tod++) {
            float E0, E1, E2;
            if (occ) {
              const u8* cc = samples[texSi[t]].rgb[tod];
              E0 = cc[0] / 255.0f; E1 = cc[1] / 255.0f; E2 = cc[2] / 255.0f;
            } else {
              const float* f = up ? sky_rad[tod] : gnd_rad[tod];
              E0 = f[0]; E1 = f[1]; E2 = f[2];
            }
            if (anchor) {
              u8* dst = &anchor_cube[(tod * NT + t) * 3];
              dst[0] = (u8)std::min(255.0f, E0 * 255.0f);
              dst[1] = (u8)std::min(255.0f, E1 * 255.0f);
              dst[2] = (u8)std::min(255.0f, E2 * 255.0f);
            }
            double* cf = &coeff[tod][0][0];
            for (int c = 0; c < PRB_NUM_SH; c++) {
              cf[c * 3 + 0] += (double)E0 * ys[c];
              cf[c * 3 + 1] += (double)E1 * ys[c];
              cf[c * 3 + 2] += (double)E2 * ys[c];
            }
          }
        }
        for (int tod = 0; tod < PRB_NUM_TOD; tod++)
          for (int c = 0; c < PRB_NUM_SH; c++)
            for (int ch = 0; ch < 3; ch++)
              pc.sh[tod][c][ch] = (float)(coeff[tod][c][ch] * kAl[c] * p.probe_gain);

        if (anchor) {
          pc.refl_anchor = 1;
          ReflProbe rp;
          rp.pos_gu[0] = cx; rp.pos_gu[1] = cy; rp.pos_gu[2] = cz;
          rp.interior = interior;
          rp.cell_ix = (s16)ix; rp.cell_iy = (s16)iy; rp.cell_iz = (s16)iz;
          rp.cube = std::move(anchor_cube);
          g.refl.push_back(std::move(rp));
        }
        g.cells.push_back(std::move(pc));
        if (interior) g.n_interior++;
      }
    }
    if ((iz % 8) == 0 || iz == g.dims[2] - 1) {
      fmt::print("[probe-bake] z-layer {}/{}  baked={} interior={} anchors={}\n", iz, g.dims[2],
                 (u64)g.cells.size(), g.n_interior, (u64)g.refl.size());
      std::fflush(stdout);
    }
  }
  g.n_valid = (u32)g.cells.size();
  g.n_refl = (u32)g.refl.size();

  fmt::print("[probe-bake] baked cells={} (interior={}) reflection anchors={} ({} bytes cube each)\n",
             g.n_valid, g.n_interior, g.n_refl, (u64)(PRB_NUM_TOD * NT * 3));
  return g;
}

bool save_probes(const ProbeGrid& g, const std::string& path) {
  std::vector<u8> buf;
  put<u32>(buf, PRB_MAGIC);
  put<u32>(buf, PRB_FORMAT_VERSION);
  put<u32>(buf, (u32)tfrag3::TFRAG3_VERSION);
  put_bytes(buf, g.level_name, sizeof(g.level_name));
  put<u64>(buf, g.fr3_size);
  put_bytes(buf, g.origin_gu, sizeof(g.origin_gu));
  put<float>(buf, g.cell_gu);
  put_bytes(buf, g.dims, sizeof(g.dims));
  put<u32>(buf, g.n_valid);
  put<u32>(buf, g.n_interior);
  put<u32>(buf, g.n_refl);
  // params (device-tunable, informational)
  put<float>(buf, g.params.cell_m);
  put<float>(buf, g.params.gather_radius_m);
  put<float>(buf, g.params.probe_gain);
  put<float>(buf, g.params.sky_gain);

  put<u32>(buf, (u32)g.cells.size());
  for (const auto& c : g.cells) {
    put<s16>(buf, c.ix); put<s16>(buf, c.iy); put<s16>(buf, c.iz);
    put<u8>(buf, c.interior); put<u8>(buf, c.refl_anchor);
    put<float>(buf, c.openness);
    put_bytes(buf, c.sh, sizeof(c.sh));
  }
  put<u32>(buf, (u32)g.refl.size());
  for (const auto& r : g.refl) {
    put_bytes(buf, r.pos_gu, sizeof(r.pos_gu));
    put<u8>(buf, r.interior);
    put<s16>(buf, r.cell_ix); put<s16>(buf, r.cell_iy); put<s16>(buf, r.cell_iz);
    put<u32>(buf, (u32)r.cube.size());
    put_bytes(buf, r.cube.data(), r.cube.size());
  }

  std::vector<u8> comp = compression::compress_zstd(buf.data(), buf.size());
  std::ofstream f(path, std::ios::binary | std::ios::trunc);
  if (!f)
    return false;
  f.write(reinterpret_cast<const char*>(comp.data()), (std::streamsize)comp.size());
  return (bool)f;
}

bool load_probes(ProbeGrid& g, const std::string& path) {
  std::ifstream f(path, std::ios::binary | std::ios::ate);
  if (!f)
    return false;
  std::streamsize sz = f.tellg();
  if (sz <= 0)
    return false;
  f.seekg(0, std::ios::beg);
  std::vector<u8> comp((size_t)sz);
  if (!f.read(reinterpret_cast<char*>(comp.data()), sz))
    return false;
  std::vector<u8> buf;
  try {
    buf = compression::decompress_zstd(comp.data(), comp.size());
  } catch (const std::exception&) {
    return false;
  }
  size_t off = 0;
  u32 magic = 0, fmt = 0, tfv = 0;
  if (!get(buf, off, magic) || magic != PRB_MAGIC)
    return false;
  if (!get(buf, off, fmt) || fmt != PRB_FORMAT_VERSION)
    return false;
  if (!get(buf, off, tfv) || tfv != (u32)tfrag3::TFRAG3_VERSION)
    return false;
  ProbeGrid tmp;
  if (!get_bytes(buf, off, tmp.level_name, sizeof(tmp.level_name)))
    return false;
  tmp.level_name[31] = 0;
  if (!get(buf, off, tmp.fr3_size))
    return false;
  if (!get_bytes(buf, off, tmp.origin_gu, sizeof(tmp.origin_gu)))
    return false;
  if (!get(buf, off, tmp.cell_gu))
    return false;
  if (!get_bytes(buf, off, tmp.dims, sizeof(tmp.dims)))
    return false;
  if (!get(buf, off, tmp.n_valid) || !get(buf, off, tmp.n_interior) || !get(buf, off, tmp.n_refl))
    return false;
  if (!get(buf, off, tmp.params.cell_m) || !get(buf, off, tmp.params.gather_radius_m) ||
      !get(buf, off, tmp.params.probe_gain) || !get(buf, off, tmp.params.sky_gain))
    return false;
  u32 ncells = 0;
  if (!get(buf, off, ncells))
    return false;
  tmp.cells.resize(ncells);
  for (auto& c : tmp.cells) {
    if (!get(buf, off, c.ix) || !get(buf, off, c.iy) || !get(buf, off, c.iz) ||
        !get(buf, off, c.interior) || !get(buf, off, c.refl_anchor) || !get(buf, off, c.openness) ||
        !get_bytes(buf, off, c.sh, sizeof(c.sh)))
      return false;
  }
  u32 nrefl = 0;
  if (!get(buf, off, nrefl))
    return false;
  tmp.refl.resize(nrefl);
  for (auto& r : tmp.refl) {
    u32 cn = 0;
    if (!get_bytes(buf, off, r.pos_gu, sizeof(r.pos_gu)) || !get(buf, off, r.interior) ||
        !get(buf, off, r.cell_ix) || !get(buf, off, r.cell_iy) || !get(buf, off, r.cell_iz) ||
        !get(buf, off, cn))
      return false;
    r.cube.resize(cn);
    if (!get_bytes(buf, off, r.cube.data(), cn))
      return false;
  }
  g = std::move(tmp);
  return true;
}

}  // namespace probe_bake
