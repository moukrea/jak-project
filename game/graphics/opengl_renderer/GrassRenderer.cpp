#include "GrassRenderer.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <string>
#include <unordered_map>
#include <unordered_set>

#include "common/custom_data/Tfrag3Data.h"
#include "common/log/log.h"

#include "game/graphics/opengl_renderer/loader/Loader.h"

namespace {

// deterministic integer hash -> float in [0,1). Stable frame-to-frame so the
// grass field never shimmers, and (crucially) independent of the camera so the
// same ground always gets the same instances no matter where the player stands.
inline u32 hash_u32(u32 x) {
  x ^= x >> 16;
  x *= 0x7feb352du;
  x ^= x >> 15;
  x *= 0x846ca68bu;
  x ^= x >> 16;
  return x;
}
inline float hash_f(u32 seed) {
  return static_cast<float>(hash_u32(seed) >> 8) * (1.0f / 16777216.0f);  // 24-bit -> [0,1)
}

// ---------------------------------------------------------------------------
// CULLING FIX (owner feedback #2, 2026-07-10) — the real root cause.
// ---------------------------------------------------------------------------
// The previous build placed grass only within MAX_PLACE_DIST (64 m) of the
// *build-time* camera, rebuilt the whole field every REBUILD_MOVE_DIST (20 m) of
// movement, and graded the per-triangle instance count by the build-time camera
// distance (density_at()). While walking this produced EXACTLY the owner's bugs:
//   * ground beyond 64 m had zero grass and stayed empty until a rebuild fired
//     -> "des zones qui chargent pas" (zones that don't load),
//   * the 20 m rebuild snapped in a whole new field at once -> pop-in while moving,
//   * each rebuild re-graded density by the NEW camera distance, so a chunk that
//     was now farther lost its instances -> "des zones entières qui disparaissent
//     en dépit du fait qu'on soit à proximité" (whole zones de-instance).
// FIX: placement is now WHOLE-LEVEL and CAMERA-INDEPENDENT. Every qualifying
// training-ground triangle is scattered ONCE at level load at a UNIFORM density
// (auto-scaled to a budget so it stays bounded on any level size) into a static
// buffer. Walking never rebuilds and never re-grades, so no chunk can pop/vanish.
// All LOD (near blade / mid card / far nothing) is done per-instance in the
// shader from the live camera — the GPU decides visibility every frame over the
// complete field. This is the standard robust grass approach.
constexpr float U = 4096.0f;              // GOAL world units per meter
constexpr float BASE_H = 1550.0f;         // ~0.38 m nominal blade height (owner asked TWICE for longer grass)
// OWNER POLISH#3: relaxed 0.7 -> 0.40 so SLOPED / bumpy grass-textured platforms
// qualify. Placement already samples the ACTUAL per-triangle surface (barycentric
// on the real tri plane, gi.py below), so this is NOT a flat/min-Y reference; the
// old 0.7 gate simply REJECTED the non-flat tris of bumpy platforms, leaving grass
// only on their flattest (often lowest) tris -> looked like grass sunk under the
// surface / whole platforms skipped.
// OWNER POLISH#5: 0.40 admitted faces up to ~66° -> steep rock lips still got blades
// ("brins dans les parties verticales"). Tightened to 0.50 (rejects faces steeper than
// 60° from horizontal) as the SECONDARY safety net behind the texture filter — bumpy
// grass platforms (<~45°) still qualify, but steep/vertical rock faces do not. Kept as
// abs(ny) (winding-agnostic): a vertical wall has abs(ny)/nlen ~= 0, so it is rejected.
constexpr float GROUND_UPNESS = 0.50f;    // face-normal.y threshold for "walkable ground"
constexpr float MAX_TRI_AREA = 300.0f;    // m^2; reject implausibly huge (spurious) triangles
constexpr float D_TARGET = 150.0f;        // tufts/m^2 uniform (dense lawn); auto-reduced to fit budget
// OWNER POLISH#3: density++ (owner's #1 ask, 3rd time). The uniform field is budget-
// clamped, so raising the ceiling directly raises density (near blades AND mid cards).
constexpr int MAX_INSTANCES = 640000;     // total instance ceiling for the whole-level static field
constexpr float BUDGET_SAFETY = 0.9f;     // keep expected count under the ceiling so NO triangle is
                                          // ever starved (a mid-list cap hit would re-create the bug)

// culling-instrumentation constants (chunk size only; the LOD reach is now the two
// ADJUSTABLE distances, read live from the settings in render()).
constexpr float CHUNK_M = 8.0f;           // instrumentation chunk size (m)
constexpr float OLD_WINDOW_M = 64.0f;     // the REMOVED camera window (for the fix diagnostic)

// OWNER POLISH#4: hide grass under overlapping non-grass 3D objects (crates/props/models).
// A coarse world-space XZ occupancy grid: a cell that has grass AND a TIE (instanced model)
// vertex hovering in [grassY+OCC_LO, grassY+OCC_HI] above it is culled, so grass never pokes
// through an object sitting on the grass. TIE-only (real placed models) — NOT tfrag terrain,
// so cliffs/slopes next to grass do not falsely cull it.
constexpr float OCC_CELL_M = 0.6f;        // occupancy cell size (m)
constexpr float OCC_LO_M = 0.10f;         // object must be at least this far above the grass to occlude
constexpr float OCC_HI_M = 8.0f;          // ...and no more than this (ignore far ceilings / high bridges)
// OWNER POLISH#6 (2026-07-10): "il y a toujours de l'herbe qui passe au travers d'objets posés sur le
// sol ... des brins sortir d'un gros caillou". The POLISH#4 cull point-sampled TIE vertices into 0.6 m
// cells: a big rock's large faces have SPARSE vertices, so interior cells above the object had no vertex
// and kept their grass -> blades still poked out of the MIDDLE of the rock. Fix: after collecting the
// occluded cells, DILATE them into their 3x3 neighbourhood so the whole footprint (interior included) is
// culled, and scan EVERY TIE geo (not just geo 0) for occluders.

// Training-level grassy-ground textures. Texture-driven, no hand authoring. Curated
// exact names PLUS a substring net (grass / leafy / moss) so any grassy-ground texture
// VARIANT is covered — OWNER POLISH#4: "il reste des plateformes avec des textures d'herbe
// qui n'ont pas d'herbe" (grass-textured platforms still missing grass). tra-grass is the
// elevated grassy terrain; tra-beachrock the green mossy ground the player stands on at the
// Geyser Rock spawn; the *-grassfringe / leafyground fringes blend them.
inline bool name_has(const std::string& n, const char* sub) {
  return n.find(sub) != std::string::npos;
}
// OWNER POLISH#5 (2026-07-10): "on a encore des brins dans les parties verticales / sans herbe" —
// rock/vertical faces STILL got grass. Owner clarification: filter by TEXTURE FIRST — "si sur une
// normale c'est de la roche, pas d'herbe". 'tra-beachrock' is a ROCK-named texture (NOT in the owner's
// grass reference set: tra-grass + bch-grassfringe + bch-leafyground-hang-2x1). It textured sloped
// rock that passed the walkable-ground gate -> "des brins sortir de la roche". REMOVED from the grass
// set entirely (tfrag AND tie): only genuinely grass-named textures get grass now. tfrag and tie share
// the same strict set. (A substring net previously over-matched a village backdrop 'vil1-medres-grass',
// 46k m2 of huge tris, collapsing density — so exact names, not substrings.)
inline bool is_grass_ground(const std::string& n) {
  return n == "tra-grass" || n == "bch-grassfringe" || n == "bch-leafyground-hang-2x1";
}
inline bool is_grass_ground_tie(const std::string& n) {
  return n == "tra-grass" || n == "bch-grassfringe" || n == "bch-leafyground-hang-2x1";
}
// A ground-ish texture we did NOT match — logged as a candidate so a missed grass variant
// surfaces on-device (POLISH#4 "still-missing platforms" diagnostic).
inline bool looks_groundish(const std::string& n) {
  return name_has(n, "ground") || name_has(n, "grass") || name_has(n, "leafy") ||
         name_has(n, "moss") || name_has(n, "beach") || name_has(n, "dirt") ||
         name_has(n, "sand") || name_has(n, "rock") || name_has(n, "mud");
}

// POLISH#4: average RGB (0..1) of a decoded RGBA8888 texture (0xAABBGGRR little-endian),
// skipping near-transparent texels. Subsampled for speed on big textures. This is the
// ground colour the grass is tinted toward so it never clashes with the texture showing
// through. Falls back to a neutral grass-green if the texture has no pixel data client-side.
inline void avg_tex_color(const tfrag3::Texture& t, float& r, float& g, float& b) {
  const size_t px = (size_t)t.w * (size_t)t.h;
  if (px == 0 || t.data.size() < px) {
    r = 0.24f; g = 0.34f; b = 0.14f;
    return;
  }
  const u32* d = t.data.data();
  size_t step = std::max<size_t>(1, px / 4096);  // cap ~4096 samples
  double sr = 0, sg = 0, sb = 0;
  u64 n = 0;
  for (size_t i = 0; i < px; i += step) {
    u32 c = d[i];
    if (((c >> 24) & 0xffu) < 16u) {  // skip transparent
      continue;
    }
    sr += (c & 0xffu);
    sg += (c >> 8) & 0xffu;
    sb += (c >> 16) & 0xffu;
    n++;
  }
  if (n == 0) {
    r = 0.24f; g = 0.34f; b = 0.14f;
    return;
  }
  r = (float)(sr / (double)n) / 255.0f;
  g = (float)(sg / (double)n) / 255.0f;
  b = (float)(sb / (double)n) / 255.0f;
}

}  // namespace

GrassRenderer::GrassRenderer() = default;

GrassRenderer::~GrassRenderer() {
  if (m_gl_ready) {
    glDeleteVertexArrays(1, &m_vao);
    glDeleteBuffers(1, &m_instance_vbo);
  }
}

void GrassRenderer::ensure_gl() {
  if (m_gl_ready) {
    return;
  }
  glGenVertexArrays(1, &m_vao);
  glGenBuffers(1, &m_instance_vbo);
  glBindVertexArray(m_vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_instance_vbo);
  // per-instance: vec4 pos+height, vec4 yaw/tint/curve/phase, vec4 ground-colour rgb+spare
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 4, GL_FLOAT, GL_FALSE, sizeof(GrassInstance), (void*)0);
  glVertexAttribDivisor(0, 1);
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(GrassInstance),
                        (void*)(4 * sizeof(float)));
  glVertexAttribDivisor(1, 1);
  // POLISH#4: ground-texture average colour (location 2), so each blade matches the ground.
  glEnableVertexAttribArray(2);
  glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, sizeof(GrassInstance),
                        (void*)(8 * sizeof(float)));
  glVertexAttribDivisor(2, 1);
  glBindVertexArray(0);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  m_gl_ready = true;
}

void GrassRenderer::rebuild(SharedRenderState* rs) {
  m_instances.clear();
  m_instance_count = 0;
  m_chunks.clear();
  m_cached_level = nullptr;
  m_cached_load_id = UINT64_MAX;

  if (!rs->loader) {
    return;
  }
  const LevelData* ld = rs->loader->get_tfrag3_level("training");
  if (!ld || !ld->level) {
    return;
  }
  const tfrag3::Level* lev = ld->level.get();

  int considered_draws = 0;  // grass-ground draws matched (tfrag + tie)
  int tie_draws = 0;         // of those, how many came from TIE (placed models / platforms)
  int tris_kept = 0;         // qualifying walkable-ground triangles
  int giant_tris = 0;        // rejected as implausibly large (spurious reconstruction)
  float total_area_m2 = 0.0f;
  float max_area = 0.0f;
  // POLISH#6: area-weighted sum of per-triangle BAKED LUMA (0..255). Divided by total area after
  // PHASE 1 to get the level's mean baked brightness; each instance's baked light is then stored
  // RELATIVE to that mean, so grass darkens only where the ground is baked-darker than average
  // (no global brightness shift — see the gspare write in PHASE 2).
  double baked_area_sum = 0.0;

  // POLISH#4: per-texture average colour cache (the ground colour each blade is tinted to).
  std::unordered_map<s32, std::array<float, 3>> texcol;
  // POLISH#4 diagnostic: ground-ish textures we did NOT match — a missed grass VARIANT shows
  // up here on-device, explaining any "platform with a grass texture but no grass".
  std::unordered_map<std::string, int> unmatched_ground;

  // A qualifying walkable-ground triangle anywhere in the level. Collected in
  // PHASE 1 (no camera filter), then scattered at a uniform density in PHASE 2.
  struct TriRec {
    float p0x, p0y, p0z;   // base vertex
    float e1x, e1y, e1z;   // edge to v1
    float e2x, e2y, e2z;   // edge to v2
    float area_m2;
    float gr, gg, gb;      // POLISH#4: average colour of this triangle's ground texture
    float raw_baked;       // POLISH#6: average baked-light luma (0..255) of this triangle's vertices
    u32 seed;              // deterministic per-triangle seed (triangle identity, camera-independent)
  };
  std::vector<TriRec> tris;

  // ---- PHASE 1: collect ALL qualifying ground triangles (WHOLE LEVEL). ----
  // No camera window — the field must be complete so nothing can fail to load or
  // de-instance while moving. Scans BOTH the highest-detail tfrag geometry (geo 0)
  // AND the TIE instanced models (geo 0): POLISH#4 — some grass-textured PLATFORMS are
  // TIE, not tfrag, so the old tfrag-only scan left them bare. Vertices are world-space,
  // 4096 = 1 m. StripDraw + unpacked{vertices,indices} are the same layout for both.
  auto scan_draws = [&](const std::vector<tfrag3::StripDraw>& draws,
                        const std::vector<tfrag3::PreloadedVertex>& verts,
                        const std::vector<u32>& idx, bool use_strips, bool is_tie,
                        const tfrag3::PackedTimeOfDay& colors) {
    if (verts.empty() || idx.empty()) {
      return;
    }
    // POLISH#6: average baked-light luma (0..255) of one vertex, reading the SAME time-of-day
    // palette (tree.colors, indexed by PreloadedVertex.color_index) the tfrag/TIE renderer uses.
    // Averaged over the 8 palettes -> a camera/time-independent RELATIVE brightness (the training
    // level's time of day is fixed). This is how the grass learns "this patch of ground is baked
    // darker than that one" so it can darken to match instead of floating as a flat bright green.
    auto vlum = [&](u32 vi) -> float {
      u16 cidx = verts[vi].color_index;
      if (colors.color_count == 0 || cidx >= colors.color_count) {
        return 128.0f;  // neutral (no baked data) -> ends up ~= level mean -> no change
      }
      float s = 0.f;
      for (int p = 0; p < 8; ++p) {
        s += 0.299f * colors.read((int)cidx, p, 0) + 0.587f * colors.read((int)cidx, p, 1) +
             0.114f * colors.read((int)cidx, p, 2);
      }
      return s * (1.0f / 8.0f);
    };
    for (const auto& draw : draws) {
      if (draw.tree_tex_id < 0 || (size_t)draw.tree_tex_id >= lev->textures.size()) {
        continue;
      }
      const std::string& tname = lev->textures[draw.tree_tex_id].debug_name;
      bool matched = is_tie ? is_grass_ground_tie(tname) : is_grass_ground(tname);
      if (!matched) {
        if (looks_groundish(tname)) {
          unmatched_ground[tname]++;
        }
        continue;
      }
      considered_draws++;
      if (is_tie) {
        tie_draws++;
      }

      // ground colour for this draw's texture (cached; POLISH#4 colour-match).
      float gcr, gcg, gcb;
      auto it = texcol.find(draw.tree_tex_id);
      if (it == texcol.end()) {
        avg_tex_color(lev->textures[draw.tree_tex_id], gcr, gcg, gcb);
        texcol[draw.tree_tex_id] = {gcr, gcg, gcb};
      } else {
        gcr = it->second[0]; gcg = it->second[1]; gcb = it->second[2];
      }

      // This draw's slice of the shared index buffer. The AUTHORITATIVE length is
      // the sum of the draw's vis_groups' num_inds — the EXACT slice the scene
      // renderer uploads (see make_all_visible_index_list in background_common.cpp).
      u32 begin = draw.unpacked.idx_of_first_idx_in_full_buffer;
      u32 len = 0;
      for (const auto& g : draw.vis_groups) {
        len += g.num_inds;
      }
      if (len == 0 || begin >= idx.size()) {
        continue;
      }
      if (begin + len > idx.size()) {
        len = (u32)(idx.size() - begin);
      }

      // record one triangle (vertex indices a,b,ci) if it is walkable ground and
      // not an implausibly large (spurious) triangle.
      auto consider_tri = [&](u32 a, u32 b, u32 ci) {
        if (a == UINT32_MAX || b == UINT32_MAX || ci == UINT32_MAX) return;
        if (a == b || b == ci || a == ci) return;
        if (a >= verts.size() || b >= verts.size() || ci >= verts.size()) return;
        const auto& p0 = verts[a];
        const auto& p1 = verts[b];
        const auto& p2 = verts[ci];
        float e1x = p1.x - p0.x, e1y = p1.y - p0.y, e1z = p1.z - p0.z;
        float e2x = p2.x - p0.x, e2y = p2.y - p0.y, e2z = p2.z - p0.z;
        float nx = e1y * e2z - e1z * e2y;
        float ny = e1z * e2x - e1x * e2z;
        float nz = e1x * e2y - e1y * e2x;
        float nlen = std::sqrt(nx * nx + ny * ny + nz * nz);
        if (nlen <= 1e-3f) return;
        float area_m2 = (0.5f * nlen) / (U * U);
        max_area = std::max(max_area, area_m2);
        if (area_m2 > MAX_TRI_AREA) {  // spurious level-spanning triangle
          giant_tris++;
          return;
        }
        float upness = std::fabs(ny) / nlen;  // 1.0 = perfectly flat ground
        if (upness <= GROUND_UPNESS || area_m2 <= 1e-4f) return;
        TriRec r;
        r.p0x = p0.x; r.p0y = p0.y; r.p0z = p0.z;
        r.e1x = e1x; r.e1y = e1y; r.e1z = e1z;
        r.e2x = e2x; r.e2y = e2y; r.e2z = e2z;
        r.area_m2 = area_m2;
        r.gr = gcr; r.gg = gcg; r.gb = gcb;
        float bl = (vlum(a) + vlum(b) + vlum(ci)) * (1.0f / 3.0f);  // POLISH#6 triangle baked luma
        r.raw_baked = bl;
        r.seed = (begin ^ (a * 2654435761u) ^ (ci * 40503u) ^ (is_tie ? 0x9e3779b9u : 0u));
        tris.push_back(r);
        tris_kept++;
        total_area_m2 += area_m2;
        baked_area_sum += (double)bl * (double)area_m2;
      };

      if (use_strips) {
        // one restart-delimited triangle strip: each new vertex closes a triangle
        // with the previous two.
        u32 a = UINT32_MAX, b = UINT32_MAX;
        for (u32 k = begin; k < begin + len; ++k) {
          u32 ci = idx[k];
          if (ci == UINT32_MAX) {  // strip restart
            a = UINT32_MAX;
            b = UINT32_MAX;
            continue;
          }
          consider_tri(a, b, ci);
          a = b;
          b = ci;
        }
      } else {
        // plain triangle list: discrete triples.
        for (u32 k = begin; k + 2 < begin + len; k += 3) {
          consider_tri(idx[k], idx[k + 1], idx[k + 2]);
        }
      }
    }
  };

  // tfrag ground (geo 0)
  for (const auto& tree : lev->tfrag_trees[0]) {
    scan_draws(tree.draws, tree.unpacked.vertices, tree.unpacked.indices, tree.use_strips, false,
               tree.colors);
  }
  // TIE instanced models / platforms (geo 0 only, to avoid duplicate LOD placement)
  if (!lev->tie_trees.empty()) {
    for (const auto& tree : lev->tie_trees[0]) {
      scan_draws(tree.static_draws, tree.unpacked.vertices, tree.unpacked.indices, tree.use_strips,
                 true, tree.colors);
    }
  }

  // ---- PHASE 2: scatter at a UNIFORM density over the whole level. ----
  // Density is a single world-space constant (no camera grading), auto-reduced so
  // the expected instance total stays safely under the ceiling — that way the cap
  // is NEVER hit mid-list, so no triangle/chunk is ever starved (a mid-list cap
  // hit is what de-instances distant chunks). Placement is a pure function of
  // triangle identity, so it is identical every level load and stable forever.
  // OWNER POLISH#5: the instance budget is now SLIDER-DRIVEN (Recharged Settings "GRASS DENSITY",
  // a percent where 100 = the baseline MAX_INSTANCES). The effective density has always been
  // budget-clamped (D_TARGET=150/m2 is never reached), so scaling the budget directly scales the
  // visible density of near blades AND cards. Clamped to [0.5x, 2.5x] renderer-side for memory
  // safety (2.5x ~= 1.6M instances). A density change re-scatters (see m_cached_density in render()).
  float dens_scale = std::min(2.5f, std::max(0.5f,
                                             Gfx::g_global_settings.recharged_grass_density / 100.0f));
  int budget = (int)((float)MAX_INSTANCES * dens_scale);
  m_cached_density = Gfx::g_global_settings.recharged_grass_density;

  // POLISH#6: the level's area-weighted mean baked luma. Each instance stores its baked light
  // RELATIVE to this (raw/ref), so an average-lit patch gets 1.0 (grass unchanged) and only
  // baked-darker patches darken — the grass responds to lighting without a global brightness shift.
  float baked_ref = 128.0f;
  if (total_area_m2 > 1e-3f && baked_area_sum > 0.0) {
    baked_ref = (float)(baked_area_sum / (double)total_area_m2);
    if (baked_ref < 1.0f) {
      baked_ref = 1.0f;
    }
  }

  float density = D_TARGET;
  if (total_area_m2 > 1.0f && total_area_m2 * D_TARGET > BUDGET_SAFETY * (float)budget) {
    density = BUDGET_SAFETY * (float)budget / total_area_m2;
  }

  m_instances.reserve(std::min<size_t>(budget, (size_t)(total_area_m2 * density) + 64));
  for (const auto& r : tris) {
    if ((int)m_instances.size() >= budget) break;
    float fn = r.area_m2 * density;
    int n = (int)fn;
    if (hash_f(r.seed + 99u) < (fn - (float)n)) {
      n += 1;
    }
    for (int i = 0; i < n; ++i) {
      if ((int)m_instances.size() >= budget) break;
      u32 sd = r.seed + (u32)i * 3266489917u;
      float r1 = hash_f(sd + 1u);
      float r2 = hash_f(sd + 2u);
      if (r1 + r2 > 1.0f) {
        r1 = 1.0f - r1;
        r2 = 1.0f - r2;
      }
      GrassInstance gi;
      gi.px = r.p0x + r1 * r.e1x + r2 * r.e2x;
      gi.py = r.p0y + r1 * r.e1y + r2 * r.e2y;
      gi.pz = r.p0z + r1 * r.e1z + r2 * r.e2z;
      gi.h = BASE_H * (0.50f + 1.55f * hash_f(sd + 3u));   // OWNER POLISH#3: wider SIZE variation
      gi.yaw = hash_f(sd + 4u) * 6.2831853f;
      gi.tint = hash_f(sd + 5u);
      gi.curve = 0.10f + 0.75f * hash_f(sd + 6u);          // wider CURVATURE variation
      gi.phase = hash_f(sd + 7u);
      gi.gr = r.gr; gi.gg = r.gg; gi.gb = r.gb;  // POLISH#4 ground colour
      // POLISH#6: per-instance BAKED-LIGHT multiplier (relative to the level mean). Applied in the
      // shader so blades over baked-dark ground darken to match it (owner: "l'herbe n'est pas
      // influencée par l'éclairage ... l'herbe (texture plate) en dessous est plus foncée").
      gi.gspare = std::min(1.35f, std::max(0.45f, r.raw_baked / baked_ref));
      m_instances.push_back(gi);
    }
  }

  // ---- POLISH#4: hide grass under overlapping non-grass 3D objects (TIE models). ----
  // A coarse XZ occupancy grid: for each grass cell we know the ground Y; if a TIE (placed
  // model) vertex hovers in [+OCC_LO, +OCC_HI] above that ground, the object sits ON the
  // grass, so drop the grass in that cell (no more blades poking through crates/props/models).
  // TIE-only (real objects) — tfrag terrain is intentionally excluded so cliffs/slopes next to
  // grass never falsely cull it.
  int occ_culled = 0;
  if (!m_instances.empty() && !lev->tie_trees.empty()) {
    const float inv = 1.0f / (OCC_CELL_M * U);
    auto cellkey = [inv](float x, float z) -> s64 {
      s64 gx = (s64)std::floor(x * inv);
      s64 gz = (s64)std::floor(z * inv);
      return (gx << 32) ^ (gz & 0xffffffffLL);
    };
    std::unordered_map<s64, float> cell_ground_y;
    cell_ground_y.reserve(m_instances.size());
    for (const auto& gi : m_instances) {
      s64 k = cellkey(gi.px, gi.pz);
      auto it = cell_ground_y.find(k);
      if (it == cell_ground_y.end() || gi.py < it->second) {
        cell_ground_y[k] = gi.py;  // lowest grass py in the cell = the ground surface
      }
    }
    std::unordered_set<s64> occluded;
    const float lo = OCC_LO_M * U, hi = OCC_HI_M * U;
    // POLISH#6: scan EVERY TIE geo (not just geo 0) so a placed object in any LOD bucket occludes.
    for (const auto& geo : lev->tie_trees) {
      for (const auto& tree : geo) {
        for (const auto& v : tree.unpacked.vertices) {
          s64 k = cellkey(v.x, v.z);
          auto it = cell_ground_y.find(k);
          if (it == cell_ground_y.end()) continue;
          float dy = v.y - it->second;
          if (dy > lo && dy < hi) {
            occluded.insert(k);
          }
        }
      }
    }
    // POLISH#6: DILATE the occluded cells into their 3x3 neighbourhood. A big rock's large faces
    // have SPARSE vertices, so the point-sampled pass left interior cells above the object un-culled
    // and blades poked out of its MIDDLE. Growing every occluded cell by one cell closes those gaps
    // so the whole object footprint is covered. (cellkey packs gx in the high 32 bits, gz in the low
    // 32 as a signed value — unpack the same way to regrow.)
    if (!occluded.empty()) {
      std::unordered_set<s64> grown;
      grown.reserve(occluded.size() * 9);
      for (s64 k : occluded) {
        s64 gx = k >> 32;
        s64 gz = (s64)(s32)(k & 0xffffffffLL);
        for (s64 dz = -1; dz <= 1; ++dz) {
          for (s64 dx = -1; dx <= 1; ++dx) {
            grown.insert(((gx + dx) << 32) ^ ((gz + dz) & 0xffffffffLL));
          }
        }
      }
      occluded.swap(grown);
    }
    if (!occluded.empty()) {
      std::vector<GrassInstance> keep;
      keep.reserve(m_instances.size());
      for (const auto& gi : m_instances) {
        if (occluded.count(cellkey(gi.px, gi.pz))) {
          occ_culled++;
          continue;
        }
        keep.push_back(gi);
      }
      m_instances.swap(keep);
    }
  }

  m_instance_count = (int)m_instances.size();

  // Build the chunk grid (culling instrumentation only — proves completeness).
  {
    std::unordered_map<s64, ChunkInfo> grid;
    grid.reserve(4096);
    const float inv = 1.0f / (CHUNK_M * U);
    for (const auto& gi : m_instances) {
      s64 gx = (s64)std::floor(gi.px * inv);
      s64 gz = (s64)std::floor(gi.pz * inv);
      s64 key = (gx << 32) ^ (gz & 0xffffffffLL);
      auto& c = grid[key];
      c.cx += gi.px;
      c.cz += gi.pz;
      c.count += 1;
    }
    m_chunks.reserve(grid.size());
    for (auto& kv : grid) {
      ChunkInfo c = kv.second;
      c.cx /= (float)c.count;  // chunk centroid
      c.cz /= (float)c.count;
      m_chunks.push_back(c);
    }
  }

  // Only commit the cache once the level is actually loaded (grass draws found),
  // so a transient (level still streaming) placement is not frozen incomplete —
  // if no draws matched we leave the cache invalid and retry next frame.
  if (considered_draws > 0) {
    m_cached_level = (const void*)lev;
    m_cached_load_id = ld->load_id;
  }

  ensure_gl();
  glBindVertexArray(m_vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_instance_vbo);
  glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)(m_instance_count * sizeof(GrassInstance)),
               m_instances.empty() ? nullptr : m_instances.data(), GL_STATIC_DRAW);
  glBindVertexArray(0);
  glBindBuffer(GL_ARRAY_BUFFER, 0);

  lg::info(
      "[recharged-grass] training STATIC place (whole-level, camera-independent): {} grass-ground "
      "draws ({} TIE), {} tris kept (giant {}, maxArea {:.0f}m2), area {:.0f} m2, density {:.0f}/m2 -> "
      "{} instances in {} chunks (POLISH#5 density {:.0f}% -> budget {}); occlusion culled {} "
      "under-object instances (POLISH#6 dilated); bakedRef {:.0f} (POLISH#6 light-response). No camera "
      "window, no move-rebuild -> nothing de-instances while moving.",
      considered_draws, tie_draws, tris_kept, giant_tris, max_area, total_area_m2, density,
      m_instance_count, (int)m_chunks.size(), Gfx::g_global_settings.recharged_grass_density, budget,
      occ_culled, baked_ref);
  // POLISH#4 "still-missing platforms" diagnostic: any ground-ish texture we did NOT place on.
  for (const auto& kv : unmatched_ground) {
    lg::info("[recharged-grass] UNMATCHED ground-ish texture '{}' ({} draws) — not placed",
             kv.first, kv.second);
  }
}

void GrassRenderer::render(SharedRenderState* rs, ScopedProfilerNode& prof) {
  if (!rs->has_pc_data) {
    return;
  }
  // Hard-scope to the training level: get_tfrag3_level returns null anywhere else.
  const LevelData* ld = rs->loader ? rs->loader->get_tfrag3_level("training") : nullptr;
  if (!ld || !ld->level) {
    return;
  }
  // Rebuild ONLY on level change / reload, OR when the DENSITY slider changed (POLISH#5 —
  // a new density means a new instance budget, so the static field must be re-scattered).
  // Placement is otherwise camera-independent (whole-level, uniform), so walking NEVER
  // triggers a rebuild — that is the culling fix: no pop-in, no de-instancing while moving.
  if (m_cached_level != (const void*)ld->level.get() || m_cached_load_id != ld->load_id ||
      m_cached_density != Gfx::g_global_settings.recharged_grass_density) {
    rebuild(rs);
  }
  if (m_instance_count <= 0) {
    return;
  }

  // monotonic seconds for the breeze
  static const auto t0 = std::chrono::steady_clock::now();
  float u_time =
      std::chrono::duration<float>(std::chrono::steady_clock::now() - t0).count();

  auto& shader = rs->shaders[ShaderId::GRASS];
  shader.activate();
  GLuint id = shader.id();

  glUniformMatrix4fv(glGetUniformLocation(id, "camera"), 1, GL_FALSE,
                     rs->camera_matrix[0].data());
  glUniform4f(glGetUniformLocation(id, "hvdf_offset"), rs->camera_hvdf_off[0],
              rs->camera_hvdf_off[1], rs->camera_hvdf_off[2], rs->camera_hvdf_off[3]);
  glUniform4f(glGetUniformLocation(id, "camera_position"), rs->camera_pos[0], rs->camera_pos[1],
              rs->camera_pos[2], rs->camera_pos[3]);
  glUniform1f(glGetUniformLocation(id, "fog_constant"), rs->camera_fog.x());
  glUniform1f(glGetUniformLocation(id, "u_time"), u_time);
  const auto& jp = Gfx::g_global_settings.recharged_jak_pos;
  glUniform4f(glGetUniformLocation(id, "u_jak_pos"), jp[0], jp[1], jp[2], jp[3]);
  // POLISH#4: adjustable LOD reach (Recharged Settings sliders), passed in WORLD units to
  // match cam_dist. Clamped to a sane range so a bad settings value can't break the LOD.
  float near_m = std::min(80.0f, std::max(8.0f, Gfx::g_global_settings.recharged_grass_near_dist));
  float card_m = std::min(200.0f, std::max(near_m + 5.0f,
                                           Gfx::g_global_settings.recharged_grass_card_dist));
  glUniform1f(glGetUniformLocation(id, "u_near_dist"), near_m * U);
  glUniform1f(glGetUniformLocation(id, "u_card_dist"), card_m * U);
  // POLISH#4: Jak's ledge-grab point (parts the ledge-top grass while he hangs).
  const auto& jl = Gfx::g_global_settings.recharged_jak_ledge;
  glUniform4f(glGetUniformLocation(id, "u_jak_ledge"), jl[0], jl[1], jl[2], jl[3]);

  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_GEQUAL);
  glDepthMask(GL_TRUE);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  glBindVertexArray(m_vao);
  GLint mode_loc = glGetUniformLocation(id, "u_mode");

  // NEAR: individual blades (10-vert triangle strip)
  glUniform1i(mode_loc, 0);
  glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 10, m_instance_count);
  prof.add_draw_call();
  prof.add_tri(m_instance_count * 8);

  // MID: X-cross cards (12-vert, 4 triangles)
  glUniform1i(mode_loc, 1);
  glDrawArraysInstanced(GL_TRIANGLES, 0, 12, m_instance_count);
  prof.add_draw_call();
  prof.add_tri(m_instance_count * 4);

  glBindVertexArray(0);

  // ---- CULLING INSTRUMENTATION (owner feedback #2): prove that every in-range
  // chunk stays DRAWN while MOVING. Throttled to ~1 log / 30 frames. With the
  // static whole-level field, chunks_drawn == chunks_in_range every frame
  // (dropped == 0) — exactly the property the old camera-windowed / 20 m-rebuild
  // path violated. `beyond_old_window` counts chunks the OLD code would have
  // dropped (past its 64 m camera window) that are STILL placed now.
  m_frame++;
  if ((m_frame % 30) == 0 && !m_chunks.empty()) {
    // LOD reach is now the two ADJUSTABLE distances (mirrors the shader B_END / C_OUT1).
    float blade_end_m = std::min(80.0f, std::max(8.0f,
                                                 Gfx::g_global_settings.recharged_grass_near_dist));
    float card_out_m = std::min(200.0f, std::max(blade_end_m + 5.0f,
                                                 Gfx::g_global_settings.recharged_grass_card_dist));
    float cx = rs->camera_pos.x(), cy = rs->camera_pos.y(), cz = rs->camera_pos.z();
    float mvx = cx - m_last_log_cam[0], mvz = cz - m_last_log_cam[2];
    bool moving = (mvx * mvx + mvz * mvz) > (0.5f * U) * (0.5f * U);
    int in_lod = 0, drawn = 0, in_blade = 0, beyond_old_window = 0;
    for (const auto& ch : m_chunks) {
      float dx = ch.cx - cx, dz = ch.cz - cz;
      float dm = std::sqrt(dx * dx + dz * dz) / U;
      if (dm < card_out_m) {
        in_lod++;
        drawn++;  // static complete field: an in-range chunk is ALWAYS drawn
      }
      if (dm < blade_end_m) {
        in_blade++;
      }
      if (dm > OLD_WINDOW_M) {
        beyond_old_window++;
      }
    }
    lg::info(
        "[recharged-grass] frame {} cam=({:.0f},{:.0f}) moving={} chunks={} in_lod(<{:.0f}m)={} "
        "drawn={} DROPPED={} blade(<{:.0f}m)={} | {} chunks beyond the OLD 64m window are STILL "
        "placed (they de-instanced in the old build)",
        m_frame, cx / U, cz / U, moving ? 1 : 0, (int)m_chunks.size(), card_out_m, in_lod, drawn,
        in_lod - drawn, blade_end_m, in_blade, beyond_old_window);
    m_last_log_cam[0] = cx;
    m_last_log_cam[1] = cy;
    m_last_log_cam[2] = cz;
  }
}
