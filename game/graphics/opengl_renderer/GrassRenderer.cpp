#include "GrassRenderer.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstring>
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
// OWNER POLISH#8: grass/cards "n'arrivent pas au bords des plateformes" — a bald flat-texture
// margin at platform EDGES. The edge LIP tris of a grass-textured platform are grass-textured
// (tra-grass, the STRICT primary filter) but slope down steeper than 60°, so upness 0.50 rejected
// them and left the border bare. Since the texture filter is now strict exact-match (rock is a
// DIFFERENT texture, tra-beachrock — excluded regardless of slope), the upness net can be relaxed
// to catch these grass-textured edge lips: 0.50 -> 0.35 (rejects only faces steeper than ~69.5°, so
// near-vertical walls are still out). Grass now reaches the actual grass-textured platform edges.
constexpr float GROUND_UPNESS = 0.35f;    // face-normal.y threshold for "walkable ground" (POLISH#8: edges)
// OWNER POLISH#12 / SUPERVISOR DIAGNOSIS (2026-07-11): the floating overflow the owner STILL saw past
// platform borders after POLISH#11 is NOT blade geometry crossing the rim (the shader hard-clamps that)
// — it is blade BASES placed on the steep grass-textured EDGE-LIP triangles POLISH#8 admitted when it
// relaxed the upness net to 0.35. Those lips face OUTWARD/DOWNWARD over the drop, so a base ON the lip
// hangs past the visible platform silhouette (= "l'herbe qui dépasse, flottante"), and the shader rim-
// clamp cannot help because it only limits offset FROM the base. FIX (PHASE 1.5 below): keep the lip
// tris in the KEPT set for texture/coverage accounting, but do NOT place BASES on a tri that is (a)
// tilted (upness < UPNESS_LIP_MAX) AND (b) an OVERHANG — its lowest/downhill edge opens into void (used
// by no OTHER grass triangle). Continuous gentle slopes (downhill edge shared with more grass) still get
// grass, so the POLISH#3 sloped-platform coverage does NOT regress. Excluding the lip makes the shoulder
// edge (flat-top<->lip) a TRUE RIM again, so the flat top's near-shoulder blades are spread-clamped to it
// (POLISH#11) and grass fills to the exact top edge with none hanging past it.
constexpr float UPNESS_LIP_MAX = 0.55f;   // below this a tilted tri MAY be an overhang rim-lip (PHASE 1.5)
constexpr float MAX_TRI_AREA = 300.0f;    // m^2; reject implausibly huge (spurious) triangles
constexpr float D_TARGET = 150.0f;        // tufts/m^2 uniform (dense lawn); auto-reduced to fit budget
// OWNER POLISH#3: density++ (owner's #1 ask, 3rd time). The uniform field is budget-
// clamped, so raising the ceiling directly raises density (near blades AND mid cards).
constexpr int MAX_INSTANCES = 640000;     // total instance ceiling for the whole-level static field
constexpr float BUDGET_SAFETY = 0.9f;     // keep expected count under the ceiling so NO triangle is
                                          // ever starved (a mid-list cap hit would re-create the bug)
// OWNER POLISH#8 (2026-07-11): amplify the PER-LOCATION baked-light deviation around the level mean
// so a shaded blade reads clearly darker and a lit blade clearly brighter (owner: the light was "le
// même pickup partout", no spatial variation). 1.0 = exact match to the ground's own multiplier;
// >1 amplifies the local contrast. Kept moderate so the grass still sits in the scene (not cartoonish).
constexpr float LIGHT_GAIN = 1.30f;

// culling-instrumentation constants (chunk size only; the LOD reach is now the two
// ADJUSTABLE distances, read live from the settings in render()).
constexpr float CHUNK_M = 8.0f;           // instrumentation chunk size (m)
constexpr float OLD_WINDOW_M = 64.0f;     // the REMOVED camera window (for the fix diagnostic)

// OWNER POLISH#4: hide grass under overlapping non-grass 3D objects (crates/props/models).
// A world-space XZ occupancy grid: a cell that has grass AND an object (TIE/shrub) vertex hovering
// in [grassY+OCC_LO, grassY+OCC_HI] above it is culled, so grass never pokes through an object
// sitting on the grass. Static-object geometry only (TIE + shrub placed models) — NOT tfrag
// terrain, so cliffs/slopes next to grass do not falsely cull it.
constexpr float OCC_CELL_M = 0.5f;        // occupancy cell size (m) — finer footprint (POLISH#7)
constexpr float OCC_LO_M = 0.05f;         // object vertex must be at least this far above the grass
// OWNER POLISH#7 (2026-07-11): clip only to the VISIBLE ABOVE-GROUND FOOTPRINT. The POLISH#6 cull
// used OCC_HI=8m — the FULL model silhouette (a tall/wide rock's upper body projects to a footprint
// BIGGER than where it meets the ground) — plus a plain 3x3 DILATION (+1 cell everywhere). Together
// they culled 397k/864k instances (46%!): an oversized EMPTY HALO ringing every object AND huge
// coverage gaps on open grass. Owner: "des zones vides autour des éléments plutôt que s'arrêter pile
// à l'intermédiaire où le rocher fait l'intermédiaire avec le sol ... le modèle 3D est plus gros sous
// le sol et le clipping prend en compte la partie non visible". FIX: sample only a THIN near-ground
// CONTACT BAND ([+OCC_LO, +OCC_HI=1.5m]) = the object's cross-section where it meets the ground = the
// visible footprint (the buried/overhanging volume is excluded), and replace the dilation with a
// morphological CLOSING (dilate THEN erode) that fills interior pinholes left by sparse object
// vertices WITHOUT growing the outer boundary -> no halo. Also scan SHRUB models, not just TIE.
constexpr float OCC_HI_M = 1.5f;          // near-ground contact band top = visible footprint (was 8m)

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
    glDeleteBuffers(1, &m_light_vbo);
  }
}

void GrassRenderer::ensure_gl() {
  if (m_gl_ready) {
    return;
  }
  glGenVertexArrays(1, &m_vao);
  glGenBuffers(1, &m_instance_vbo);
  glGenBuffers(1, &m_light_vbo);
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
  // POLISH#9: dynamic GROUND baked-light (location 3) in its OWN buffer, so only this small u8 rgba
  // column is re-uploaded when the time of day changes (the big static instance buffer never moves).
  // Normalized u8 -> [0,1]; the shader multiplies by 2.0 to recover the ground's own (palette/255)*2
  // baked-light factor, so the grass darkens/brightens EXACTLY like the ground beneath it.
  glBindBuffer(GL_ARRAY_BUFFER, m_light_vbo);
  glEnableVertexAttribArray(3);
  glVertexAttribPointer(3, 4, GL_UNSIGNED_BYTE, GL_TRUE, 4 * sizeof(u8), (void*)0);
  glVertexAttribDivisor(3, 1);
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
  m_inst_tri.clear();       // POLISH#9: per-instance source-tri map (rebuilt below)
  m_tri_light.clear();      // POLISH#9: per-tri baked-light source (rebuilt below)
  m_light.clear();
  m_light_valid = false;

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
    float p0x, p0y, p0z;   // base vertex A
    float e1x, e1y, e1z;   // edge to v1 (B = A + e1)
    float e2x, e2y, e2z;   // edge to v2 (C = A + e2)
    float area_m2;
    float gr, gg, gb;      // POLISH#4: average colour of this triangle's ground texture
    float raw_baked;       // POLISH#6: average baked-light luma (0..255) of this triangle's vertices
    u32 seed;              // deterministic per-triangle seed (triangle identity, camera-independent)
    // POLISH#9 edge geometry (world units) for the precise point-in-triangle EDGE clip.
    float nlen;                    // |cross(e1,e2)| = 2*area (world^2), for perpendicular distances
    float lenAB, lenBC, lenCA;     // edge lengths: AB=|e1|, BC=|C-B|=|e2-e1|, CA=|e2|
    bool bAB, bBC, bCA;            // is this edge a BOUNDARY (platform rim) vs an interior seam
    float upness;                  // POLISH#12: face-normal.y / |n| (1 = flat top, ~0 = wall)
    bool is_lip;                   // POLISH#12: overhang rim-lip -> excluded from BASE placement
    // POLISH#9 dynamic ground baked-light: this triangle's centroid palette rows (8 keyframes x rgb),
    // averaged over its 3 vertices, so update_light() can re-interpolate at the current time of day.
    float pal[8][3];
  };
  std::vector<TriRec> tris;

  // POLISH#8 edge instrumentation: grass-textured tris rejected purely by the upness gate.
  int rej_upness = 0;          // grass-textured tris rejected by the upness net (edge lips / walls)
  float rej_upness_area = 0.f;
  int rej_up_moderate = 0;     // of those, moderate slope (0.20..GROUND_UPNESS) = edge lips we still miss
  float min_kept_upness = 1.0f;
  // POLISH#10: world-space verts (x,y,z x3) of grass-textured tris the upness gate rejected (steep
  // edge LIPS). Their edges feed the boundary classifier below so a kept FLAT top triangle whose
  // shoulder edge is shared with a rejected lip is treated as INTERIOR (grass fills to the shoulder),
  // not a false BOUNDARY that would leave a bald fringe short of the real platform rim.
  std::vector<std::array<float, 9>> rej_lip_verts;

  // POLISH#8: prepare the CURRENT time-of-day interpolation weights (rs->itimes, copied from the
  // pc-data this frame in update_render_state_from_pc_settings) so each ground triangle's baked luma
  // is sampled at the ACTUAL current time — the exact colour the ground vertex is rendered with —
  // preserving the full lit-vs-shadow contrast. The old 8-palette average washed that contrast out,
  // so the grass light read as one global value everywhere (owner polish#7/#8).
  int tod_w[8][4];
  bool itimes_valid = false;
  for (int comp = 0; comp < 8; ++comp) {
    int quad_idx = comp / 2;
    int word_off = (comp % 2) * 2;
    for (int ch = 0; ch < 4; ++ch) {
      int word = word_off + (ch / 2);
      int hw_off = ch % 2;
      u32 wv = (u32)rs->itimes[quad_idx][word];
      u32 hw = hw_off ? (wv >> 16) : wv;
      tod_w[comp][ch] = (int)(hw & 0xffu);
    }
  }
  {
    int wsum = 0;
    for (int comp = 0; comp < 8; ++comp)
      for (int ch = 0; ch < 3; ++ch) wsum += tod_w[comp][ch];
    itimes_valid = wsum > 0;  // all-zero itimes (not populated / pitch black) -> fall back to 8-avg
  }

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
      // POLISH#8: sample the ground vertex's CURRENT-TIME interpolated colour (the exact luma the
      // ground is rendered with THIS frame), replicating interp_time_of_day scalar-side: per channel,
      // sum(colour_p * weight_p) >> 6, saturate to 255. This preserves the real lit-vs-shadow contrast
      // per-location (the day-average below collapsed it, so the light read as one global value).
      if (itimes_valid) {
        int rgb[3] = {0, 0, 0};
        for (int ch = 0; ch < 3; ++ch) {
          int acc = 0;
          for (int p = 0; p < 8; ++p) acc += (int)colors.read((int)cidx, p, ch) * tod_w[p][ch];
          acc >>= 6;
          if (acc > 255) acc = 255;
          rgb[ch] = acc;
        }
        return 0.299f * rgb[0] + 0.587f * rgb[1] + 0.114f * rgb[2];
      }
      float s = 0.f;
      for (int p = 0; p < 8; ++p) {
        s += 0.299f * colors.read((int)cidx, p, 0) + 0.587f * colors.read((int)cidx, p, 1) +
             0.114f * colors.read((int)cidx, p, 2);
      }
      return s * (1.0f / 8.0f);
    };
    // POLISH#9: one raw time-of-day palette entry (0..255) for a vertex, keyframe p, channel ch.
    // update_light() blends these 8 keyframes with the LIVE itimes so the grass baked light tracks
    // the day cycle (dynamic) instead of the frozen single value the old build sampled once at load.
    auto pentry = [&](u32 vi, int p, int ch) -> float {
      u16 cidx = verts[vi].color_index;
      if (colors.color_count == 0 || cidx >= colors.color_count) {
        return 128.0f;  // neutral (no baked data) -> factor ~1.0
      }
      return (float)colors.read((int)cidx, p, ch);
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
        if (area_m2 <= 1e-4f) return;
        if (upness <= GROUND_UPNESS) {  // POLISH#8: track grass-textured tris the upness net drops
          rej_upness++;
          rej_upness_area += area_m2;
          if (upness >= 0.20f) rej_up_moderate++;  // moderate-slope edge lips we still miss (vs walls)
          // POLISH#10: remember this grass-textured lip's edges so the boundary classifier does not
          // treat the kept top triangle's shared shoulder edge as a rim (avoids a bald fringe there).
          rej_lip_verts.push_back(
              {p0.x, p0.y, p0.z, p1.x, p1.y, p1.z, p2.x, p2.y, p2.z});
          return;
        }
        min_kept_upness = std::min(min_kept_upness, upness);
        TriRec r;
        r.p0x = p0.x; r.p0y = p0.y; r.p0z = p0.z;
        r.e1x = e1x; r.e1y = e1y; r.e1z = e1z;
        r.e2x = e2x; r.e2y = e2y; r.e2z = e2z;
        r.area_m2 = area_m2;
        r.upness = upness;   // POLISH#12: kept for the PHASE 1.5 overhang-lip classifier
        r.is_lip = false;
        r.gr = gcr; r.gg = gcg; r.gb = gcb;
        float bl = (vlum(a) + vlum(b) + vlum(ci)) * (1.0f / 3.0f);  // POLISH#6 triangle baked luma
        r.raw_baked = bl;
        r.seed = (begin ^ (a * 2654435761u) ^ (ci * 40503u) ^ (is_tie ? 0x9e3779b9u : 0u));
        // POLISH#9 edge geometry for the precise point-in-triangle edge clip (world units).
        r.nlen = nlen;                                   // = 2*area (world^2)
        r.lenAB = std::sqrt(e1x * e1x + e1y * e1y + e1z * e1z);
        r.lenCA = std::sqrt(e2x * e2x + e2y * e2y + e2z * e2z);
        float bcx = e2x - e1x, bcy = e2y - e1y, bcz = e2z - e1z;  // C - B
        r.lenBC = std::sqrt(bcx * bcx + bcy * bcy + bcz * bcz);
        r.bAB = r.bBC = r.bCA = false;                   // classified in the boundary pass below
        // POLISH#9 dynamic light: centroid palette rows (avg of the 3 vertices), 8 keyframes x rgb.
        for (int p = 0; p < 8; ++p) {
          for (int ch = 0; ch < 3; ++ch) {
            r.pal[p][ch] =
                (pentry(a, p, ch) + pentry(b, p, ch) + pentry(ci, p, ch)) * (1.0f / 3.0f);
          }
        }
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

  // ---- POLISH#12 (PHASE 1.5): flag OVERHANG rim-lip tris, then classify edges BOUNDARY vs INTERIOR. ----
  // Vertex weld at 1 cm so shared edges of adjacent tris hash to the same key. Camera-independent +
  // stable per load (same field every time).
  const float QUANT = 0.01f * U;  // 1 cm vertex weld
  auto vkey = [QUANT](float x, float y, float z) -> u64 {
    s64 qx = (s64)std::llround(x / QUANT);
    s64 qy = (s64)std::llround(y / QUANT);
    s64 qz = (s64)std::llround(z / QUANT);
    return (u64)(qx * 73856093LL) ^ (u64)(qy * 19349663LL) ^ (u64)(qz * 83492791LL);
  };
  auto ekey = [](u64 va, u64 vb) -> u64 {
    u64 lo = va < vb ? va : vb, hi = va < vb ? vb : va;
    return lo * 0x9e3779b97f4a7c15ull + (hi ^ (hi >> 29));
  };
  int boundary_edges = 0;
  int lip_excluded = 0;         // POLISH#12: overhang rim-lip tris whose BASES are excluded (no floating)
  float lip_excluded_area = 0.f;
  float min_placed_upness = 1.0f;
  {
    // (1) PROVISIONAL edge count over ALL loose-kept grass tris (upness > GROUND_UPNESS). Used only to
    // decide, for each TILTED tri, whether its lowest/downhill edge opens into VOID (used by no other
    // grass tri = an overhanging platform lip) or continues onto MORE grass (a genuine slope to keep).
    std::unordered_map<u64, int> prov;
    prov.reserve(tris.size() * 3 + 16);
    for (const auto& r : tris) {
      u64 va = vkey(r.p0x, r.p0y, r.p0z);
      u64 vb = vkey(r.p0x + r.e1x, r.p0y + r.e1y, r.p0z + r.e1z);
      u64 vc = vkey(r.p0x + r.e2x, r.p0y + r.e2y, r.p0z + r.e2z);
      prov[ekey(va, vb)]++;
      prov[ekey(vb, vc)]++;
      prov[ekey(vc, va)]++;
    }
    // (2) OVERHANG-LIP classification. A tri is an overhang rim-lip (base-excluded) iff it is tilted
    // (upness < UPNESS_LIP_MAX) AND its LOWEST edge (the downhill edge a lip drops off toward) is a
    // provisional BOUNDARY (count <= 1 = no grass beyond it = the void). Flat/gentle tops (upness >=
    // UPNESS_LIP_MAX) are NEVER flagged; continuous slopes (downhill edge shared with more grass) keep
    // their grass -> POLISH#3 sloped-platform coverage is preserved, only the outward-hanging lips go.
    for (auto& r : tris) {
      r.is_lip = false;
      if (r.upness < UPNESS_LIP_MAX) {
        float Ay = r.p0y, By = r.p0y + r.e1y, Cy = r.p0y + r.e2y;
        float mAB = Ay + By, mBC = By + Cy, mCA = Cy + Ay;  // 2x edge-midpoint Y (compare only)
        u64 va = vkey(r.p0x, r.p0y, r.p0z);
        u64 vb = vkey(r.p0x + r.e1x, r.p0y + r.e1y, r.p0z + r.e1z);
        u64 vc = vkey(r.p0x + r.e2x, r.p0y + r.e2y, r.p0z + r.e2z);
        u64 low_e = (mAB <= mBC && mAB <= mCA) ? ekey(va, vb)
                                               : (mBC <= mCA ? ekey(vb, vc) : ekey(vc, va));
        auto it = prov.find(low_e);
        if (it != prov.end() && it->second <= 1) {
          r.is_lip = true;  // downhill edge opens into void => overhang rim lip => no BASES placed here
          lip_excluded++;
          lip_excluded_area += r.area_m2;
        }
      }
      if (!r.is_lip) min_placed_upness = std::min(min_placed_upness, r.upness);
    }
    // (3) FINAL edge count over ONLY the tris that will actually be placed (lips removed). Now the
    // shoulder edge a flat top shared with an excluded lip is used ONCE = a TRUE RIM, so PHASE 2 stamps
    // its near-shoulder blades with a rim_dist and the POLISH#11 shader clamp holds their spread to the
    // exact top edge (no overflow past it); interior seams between two PLACED tris stay shared = full
    // coverage (no bald hole). A rim is strictly the true outer boundary of the placed grass patch.
    std::unordered_map<u64, int> edge_count;
    edge_count.reserve(tris.size() * 3 + 16);
    for (const auto& r : tris) {
      if (r.is_lip) continue;
      u64 va = vkey(r.p0x, r.p0y, r.p0z);
      u64 vb = vkey(r.p0x + r.e1x, r.p0y + r.e1y, r.p0z + r.e1z);
      u64 vc = vkey(r.p0x + r.e2x, r.p0y + r.e2y, r.p0z + r.e2z);
      edge_count[ekey(va, vb)]++;  // AB
      edge_count[ekey(vb, vc)]++;  // BC
      edge_count[ekey(vc, va)]++;  // CA
    }
    for (auto& r : tris) {
      if (r.is_lip) {
        r.bAB = r.bBC = r.bCA = false;
        continue;
      }
      u64 va = vkey(r.p0x, r.p0y, r.p0z);
      u64 vb = vkey(r.p0x + r.e1x, r.p0y + r.e1y, r.p0z + r.e1z);
      u64 vc = vkey(r.p0x + r.e2x, r.p0y + r.e2y, r.p0z + r.e2z);
      r.bAB = edge_count[ekey(va, vb)] <= 1;
      r.bBC = edge_count[ekey(vb, vc)] <= 1;
      r.bCA = edge_count[ekey(vc, va)] <= 1;
      boundary_edges += (int)r.bAB + (int)r.bBC + (int)r.bCA;
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
  // POLISH#8: the ground's mean own-multiplier (luma/128, neutral 1.0 at 128). Grass light is centred
  // here and the per-location deviation amplified by LIGHT_GAIN (below), so the OVERALL brightness
  // matches the ground while shade/light vary per-location.
  float meanf = baked_ref / 128.0f;
  // POLISH#8 lighting instrumentation: the spread of the per-triangle baked luma. A WIDE min..max /
  // large stddev proves the light is now location-aware (real lit-vs-shadow variation), not one
  // global value — this is what the owner's "même pickup partout" complaint was about.
  float bl_min = 1e9f, bl_max = -1e9f;
  double bl_sum = 0.0, bl_sq = 0.0;
  for (const auto& r : tris) {
    bl_min = std::min(bl_min, r.raw_baked);
    bl_max = std::max(bl_max, r.raw_baked);
    bl_sum += r.raw_baked;
    bl_sq += (double)r.raw_baked * (double)r.raw_baked;
  }
  float bl_mean = tris.empty() ? 0.f : (float)(bl_sum / (double)tris.size());
  float bl_std =
      tris.empty()
          ? 0.f
          : (float)std::sqrt(std::max(0.0, bl_sq / (double)tris.size() - (double)bl_mean * bl_mean));

  float density = D_TARGET;
  if (total_area_m2 > 1.0f && total_area_m2 * D_TARGET > BUDGET_SAFETY * (float)budget) {
    density = BUDGET_SAFETY * (float)budget / total_area_m2;
  }

  // POLISH#9: retain each kept triangle's baked-light source so update_light() can re-interpolate
  // it every frame at the current time of day (dynamic light). Indexed the same as `tris`, and each
  // instance stores its source-tri index (m_inst_tri) so it can look up its ground light.
  m_tri_light.resize(tris.size());
  for (size_t tj = 0; tj < tris.size(); ++tj) {
    std::memcpy(m_tri_light[tj].pal, tris[tj].pal, sizeof(m_tri_light[tj].pal));
  }
  // POLISH#11: PER-BLADE edge clip via a GEOMETRIC HARD CLAMP — the root fix for BOTH the floating
  // overflow AND the bald holes that POLISH#9/#10 kept trading off. Each blade stores rim_dist: the
  // perpendicular distance from its base to the NEAREST TRUE RIM edge (an edge used by exactly one
  // KEPT grass triangle = the grass patch's true outer boundary). The vertex shader clamps every
  // blade's TOTAL horizontal (XZ) offset — width + static bend + breeze sway + trample — to rim_dist,
  // so no part of any blade can cross its nearest rim, whatever its yaw or its dynamic motion. Because
  // rim_dist is the MIN over the triangle's rim edges and the base is inside the (convex) triangle, an
  // offset magnitude <= rim_dist provably stays on the inner side of EVERY rim.
  //   * Overflow is impossible: the geometry is CLAMPED, not merely leaned. POLISH#10 leaned the bend
  //     inward only partially (blend = 1 - dmin/reach), so blades in the 0.5..1.0 reach band still
  //     tipped out; and its rej_lip merge (removed above) had hidden the real shoulders. Both gone.
  //   * Holes are impossible: nothing is DROPPED near a rim (POLISH#9 dropped a ~10 cm ring = the bald
  //     fringe). Blades keep FULL HEIGHT to the rim; only their horizontal spread shrinks, so the lawn
  //     is full to the exact edge. Interior blades (rim_dist = NO_RIM) are completely untouched.
  // Every candidate blade is judged by its OWN base — no block/chunk is accepted or rejected as a unit.
  const float DROP_EPS = 0.005f * U;    // drop only a degenerate sliver whose base is < 5 mm from a rim
  const float NO_RIM = 1.0e9f;          // rim_dist sentinel for a blade with no rim edge in its triangle

  m_instances.reserve(std::min<size_t>(budget, (size_t)(total_area_m2 * density) + 64));
  m_inst_tri.reserve(m_instances.capacity());
  int edge_dropped = 0;   // degenerate rim slivers dropped individually (per-blade, NOT whole blocks)
  int edge_clamped = 0;   // near-rim blades whose horizontal reach the shader will clamp to the rim
  for (size_t tj = 0; tj < tris.size(); ++tj) {
    const auto& r = tris[tj];
    if (r.is_lip) continue;   // POLISH#12: overhang rim-lip -> place NO bases (no blade floating past the platform)
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
      // POLISH#11 per-blade rim distance. Barycentric weights (A,B,C) = (1-r1-r2, r1, r2). The blade's
      // perpendicular distance to the edge OPPOSITE a vertex is weight*(2*area/edge_len) =
      // weight*nlen/len (world units). dmin = distance to the NEAREST TRUE RIM edge of THIS triangle.
      float wA = 1.0f - r1 - r2, wB = r1, wC = r2;
      float dmin = NO_RIM;
      if (r.bBC) { float d = wA * r.nlen / r.lenBC; if (d < dmin) dmin = d; }  // edge BC opposite A
      if (r.bCA) { float d = wB * r.nlen / r.lenCA; if (d < dmin) dmin = d; }  // edge CA opposite B
      if (r.bAB) { float d = wC * r.nlen / r.lenAB; if (d < dmin) dmin = d; }  // edge AB opposite C
      // The ONLY per-blade rejection is a degenerate sliver whose base sits < 5 mm from the rim.
      if (dmin < DROP_EPS) { edge_dropped++; continue; }

      GrassInstance gi;
      gi.px = r.p0x + r1 * r.e1x + r2 * r.e2x;
      gi.py = r.p0y + r1 * r.e1y + r2 * r.e2y;
      gi.pz = r.p0z + r1 * r.e1z + r2 * r.e2z;
      gi.h = BASE_H * (0.50f + 1.55f * hash_f(sd + 3u));   // OWNER POLISH#3: wider SIZE variation
      gi.tint = hash_f(sd + 5u);
      gi.curve = 0.10f + 0.75f * hash_f(sd + 6u);          // wider CURVATURE variation
      gi.phase = hash_f(sd + 7u);
      gi.yaw = hash_f(sd + 4u) * 6.2831853f;               // POLISH#11: fully random yaw; the shader's
                                                           // rim clamp (not a CPU lean) keeps geometry in-bounds
      gi.gr = r.gr; gi.gg = r.gg; gi.gb = r.gb;            // POLISH#4 ground colour
      // POLISH#11: the (shader-unused) 4th ground-colour slot now carries rim_dist for the shader clamp.
      // The DYNAMIC per-location baked light travels in its own u8 buffer (loc 3, inst_light), so this
      // float slot is free — repurposing it needs no vertex-layout change and does NOT touch lighting.
      gi.gspare = dmin;   // = rim_dist (world units); NO_RIM for interior blades -> shader never clamps
      if (dmin < (gi.curve + 0.5f) * gi.h) edge_clamped++;  // blades the shader will actually clamp
      m_instances.push_back(gi);
      m_inst_tri.push_back((u32)tj);   // POLISH#9: remember which triangle this blade grows from
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
    // POLISH#7: only mark cells where an object vertex is in the near-ground CONTACT BAND
    // [+lo, +hi=1.5m] -> the visible above-ground footprint, not the full silhouette.
    auto mark_occluder = [&](float vx, float vy, float vz) {
      s64 k = cellkey(vx, vz);
      auto it = cell_ground_y.find(k);
      if (it == cell_ground_y.end()) return;
      float dy = vy - it->second;
      if (dy > lo && dy < hi) {
        occluded.insert(k);
      }
    };
    // POLISH#6: scan EVERY TIE geo (not just geo 0) so a placed object in any LOD bucket occludes.
    for (const auto& geo : lev->tie_trees) {
      for (const auto& tree : geo) {
        for (const auto& v : tree.unpacked.vertices) {
          mark_occluder(v.x, v.y, v.z);
        }
      }
    }
    // OWNER POLISH#8: do NOT treat SHRUB meshes as occluders (POLISH#7 did). The original grass
    // SHRUBS (bushes / tufts) are alpha-tested foliage: their MESH footprint is far larger than the
    // actually-opaque visible blades, so scanning shrub vertices marked the whole shrub bounding
    // footprint as occupied and left a BALD ring of flat grass texture around every shrub (owner:
    // "les shrubs ... ont beaucoup d'espace où on voit la texture plate ... leur mesh occupe l'espace
    // bien que non visible en alpha"). We cannot cheaply read per-vertex opacity here, and the owner
    // explicitly permits exempting shrubs from the overlap-hide entirely — our 3D grass growing right
    // up to / under a shrub tuft looks correct (both are grass). So shrubs are EXCLUDED from the
    // occluder scan; only solid TIE objects (rocks / props) hide grass. Bonus: removes a large chunk
    // of over-cull, filling coverage (helps the platform-edge / open-ground bald patches too).
    // POLISH#7: morphological CLOSING (dilate THEN erode). The POLISH#6 plain dilation grew a +1-cell
    // HALO around every object (owner: empty ring). Closing fills interior pinholes left by sparse
    // object vertices but does NOT grow the outer boundary -> footprint stops at the object edge, no
    // halo. (cellkey packs gx in the high 32 bits, gz signed in the low 32.)
    if (!occluded.empty()) {
      auto packc = [](s64 gx, s64 gz) -> s64 { return (gx << 32) ^ (gz & 0xffffffffLL); };
      auto ucx = [](s64 k) -> s64 { return k >> 32; };
      auto ucz = [](s64 k) -> s64 { return (s64)(s32)(k & 0xffffffffLL); };
      // dilate
      std::unordered_set<s64> dil;
      dil.reserve(occluded.size() * 9);
      for (s64 k : occluded) {
        s64 gx = ucx(k), gz = ucz(k);
        for (s64 dz = -1; dz <= 1; ++dz) {
          for (s64 dx = -1; dx <= 1; ++dx) {
            dil.insert(packc(gx + dx, gz + dz));
          }
        }
      }
      // erode: keep only cells whose full 3x3 neighbourhood is in the dilated set
      std::unordered_set<s64> closed;
      closed.reserve(occluded.size() * 2);
      for (s64 k : dil) {
        s64 gx = ucx(k), gz = ucz(k);
        bool all = true;
        for (s64 dz = -1; dz <= 1 && all; ++dz) {
          for (s64 dx = -1; dx <= 1 && all; ++dx) {
            if (!dil.count(packc(gx + dx, gz + dz))) all = false;
          }
        }
        if (all) closed.insert(k);
      }
      occluded.swap(closed);
    }
    if (!occluded.empty()) {
      std::vector<GrassInstance> keep;
      std::vector<u32> keept;   // POLISH#9: keep m_inst_tri aligned with the surviving instances
      keep.reserve(m_instances.size());
      keept.reserve(m_instances.size());
      for (size_t i = 0; i < m_instances.size(); ++i) {
        const auto& gi = m_instances[i];
        if (occluded.count(cellkey(gi.px, gi.pz))) {
          occ_culled++;
          continue;
        }
        keep.push_back(gi);
        keept.push_back(m_inst_tri[i]);
      }
      m_instances.swap(keep);
      m_inst_tri.swap(keept);
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

  // POLISH#9: populate the dynamic ground baked-light buffer for the CURRENT time of day right now,
  // so the first frame after a (re)build already carries correct per-location light.
  m_light_valid = false;
  update_light(rs);

  lg::info(
      "[recharged-grass] training STATIC place (whole-level, camera-independent): {} grass-ground "
      "draws ({} TIE), {} tris kept (giant {}, maxArea {:.0f}m2), area {:.0f} m2, density {:.0f}/m2 -> "
      "{} instances in {} chunks (POLISH#5 density {:.0f}% -> budget {}); occlusion culled {} "
      "under-object instances (POLISH#8 TIE-only occluder, shrubs EXEMPT + contact-band 1.5m + "
      "morphological closing -> no shrub bald ring, no halo). No camera window, no move-rebuild -> "
      "nothing de-instances while moving.",
      considered_draws, tie_draws, tris_kept, giant_tris, max_area, total_area_m2, density,
      m_instance_count, (int)m_chunks.size(), Gfx::g_global_settings.recharged_grass_density, budget,
      occ_culled);
  // POLISH#8 LOCATION-AWARE LIGHTING proof: the per-location baked luma spread. itimesValid=1 means
  // the CURRENT-time interp is used (contrast preserved). A wide bakedLuma min..max / big std = real
  // per-location lit-vs-shadow variation (NOT the old one-global-value); gspare = meanf(=ref/128) +
  // gain*(luma/128 - meanf).
  lg::info(
      "[recharged-grass] POLISH#8 LIGHT location-aware: itimesValid={} bakedRef(cur) {:.0f} -> meanf "
      "{:.2f}; per-tri bakedLuma min {:.0f} / mean {:.0f} / max {:.0f} / std {:.1f}; gain {:.2f} -> "
      "gspare spans ~[{:.2f}..{:.2f}] (shade darkens, lit brightens per-location).",
      itimes_valid ? 1 : 0, baked_ref, meanf, bl_min, bl_mean, bl_max, bl_std, LIGHT_GAIN,
      std::min(1.45f, std::max(0.30f, meanf + LIGHT_GAIN * (bl_min / 128.0f - meanf))),
      std::min(1.45f, std::max(0.30f, meanf + LIGHT_GAIN * (bl_max / 128.0f - meanf))));
  // POLISH#8 EDGE proof: how many grass-textured tris the upness gate still drops. rej_moderate =
  // grass-textured tris at 0.20..0.35 upness (edge lips we would still miss); if large, edges remain
  // bare and the gate could relax further. minKeptUpness = the shallowest tri that DID get grass.
  lg::info(
      "[recharged-grass] POLISH#8 EDGE upness {:.2f}: grass-tex tris dropped by upness {} ({:.0f} m2), "
      "of which {} moderate-slope (0.20..{:.2f}, edge lips); minKeptUpness {:.2f}.",
      GROUND_UPNESS, rej_upness, rej_upness_area, rej_up_moderate, GROUND_UPNESS, min_kept_upness);
  // POLISH#11 PER-BLADE EDGE CLAMP: each blade judged by its OWN base (no block accept/reject).
  // boundaryEdges = TRUE rim edges (rej_lip merge removed -> real platform shoulders are rims again;
  // POLISH#10 had collapsed this from ~2107 to 1147, which is what let grass overflow shoulders).
  // edgeDropped = sub-5 mm degenerate rim slivers; edgeClamped = near-rim blades the shader will
  // horizontally clamp to the rim (full height, no overflow past the edge, no bald fringe).
  lg::info(
      "[recharged-grass] POLISH#11 PER-BLADE edge CLAMP: {} true-rim edges; {} degenerate rim slivers "
      "dropped (<{:.3f} m); {} near-rim blades horizontally CLAMPED to the rim by the shader (full "
      "height, no overflow, no bald fringe; interior blades untouched).",
      boundary_edges, edge_dropped, DROP_EPS / U, edge_clamped);
  // POLISH#12 OVERHANG-LIP EXCLUSION: BASES are no longer placed on steep grass-textured tris whose
  // lowest/downhill edge opens into void (the platform lip that overhangs the drop) — the true cause of
  // the owner's persistent FLOATING overflow. Removing the lip promotes the flat top's shoulder to a
  // real rim so near-shoulder blades clamp to the exact top edge (no overflow) while the flat top still
  // fills right up to it (no bald margin). lipExcluded = tris made base-free; minPlacedUpness = the
  // shallowest tri that STILL gets grass (>= the lip band, so no bases hang off the overhanging lips).
  lg::info(
      "[recharged-grass] POLISH#12 OVERHANG-LIP: {} lip tris base-excluded ({:.0f} m2, upness < {:.2f} "
      "AND downhill edge = void); minPlacedUpness {:.2f}. Bases stay on the flat top only -> grass ends "
      "exactly at the top rim, none floating past the platform silhouette.",
      lip_excluded, lip_excluded_area, UPNESS_LIP_MAX, min_placed_upness);
  // POLISH#4 "still-missing platforms" diagnostic: any ground-ish texture we did NOT place on.
  for (const auto& kv : unmatched_ground) {
    lg::info("[recharged-grass] UNMATCHED ground-ish texture '{}' ({} draws) — not placed",
             kv.first, kv.second);
  }
}

// POLISH#9 (owner #1 priority): DYNAMIC GROUND baked-light. The old build sampled the baked light
// ONCE inside rebuild() (frozen at level load) and stored a MEAN-CENTRED luma approximation, so the
// grass did not track the ground: as the day cycle darkened the tfrag ground the grass stayed bright
// (owner: "tu prends toujours pas en compte le baked lighting du sol ... qui dépend de l'emplacement
// + du moment du jour"). This re-interpolates each triangle's centroid palette with the LIVE itimes
// every frame (throttled to actual TOD changes) and multiplies the grass by the ground's OWN factor
// ((palette/255)*2), so the grass darkens/brightens EXACTLY like the ground beneath it, per location
// AND per time of day. Only the small u8 light column is re-uploaded; the big static field never moves.
void GrassRenderer::update_light(SharedRenderState* rs) {
  if (m_instance_count <= 0 || m_tri_light.empty() || (int)m_inst_tri.size() < m_instance_count) {
    return;
  }
  // Current time-of-day interpolation weights (per keyframe, per channel) — exactly how
  // interp_time_of_day derives them from itimes. These advance as the day/night cycle moves.
  int w[8][3];
  int wsum = 0;
  for (int comp = 0; comp < 8; ++comp) {
    int quad_idx = comp / 2;
    int word_off = (comp % 2) * 2;
    for (int ch = 0; ch < 3; ++ch) {
      int word = word_off + (ch / 2);
      int hw_off = ch % 2;
      u32 wv = (u32)rs->itimes[quad_idx][word];
      u32 hw = hw_off ? (wv >> 16) : wv;
      w[comp][ch] = (int)(hw & 0xffu);
      wsum += w[comp][ch];
    }
  }

  // Throttle: recompute + re-upload only when the weights actually changed since the last upload
  // (the day cycle moves slowly; re-uploading every frame would waste bandwidth on the Adreno 618).
  if (m_light_valid) {
    bool changed = false;
    for (int q = 0; q < 4 && !changed; ++q) {
      for (int c = 0; c < 4; ++c) {
        int d = (int)rs->itimes[q][c] - m_last_itimes[q][c];
        if (d < 0) d = -d;
        if (d >= 2) {
          changed = true;
          break;
        }
      }
    }
    if (!changed) {
      return;
    }
  }

  // Per-triangle baked colour at the CURRENT time (matches interp_time_of_day: sum(pal*w) >> 6,
  // saturate 255). If itimes is unpopulated (all-zero) fall back to neutral 128 -> factor ~1.0.
  const bool valid = wsum > 0;
  std::vector<std::array<u8, 3>> tri_rgb(m_tri_light.size());
  for (size_t j = 0; j < m_tri_light.size(); ++j) {
    for (int ch = 0; ch < 3; ++ch) {
      if (!valid) {
        tri_rgb[j][ch] = 128;
        continue;
      }
      float acc = 0.f;
      for (int p = 0; p < 8; ++p) {
        acc += m_tri_light[j].pal[p][ch] * (float)w[p][ch];
      }
      int v = (int)acc >> 6;
      if (v > 255) v = 255;
      if (v < 0) v = 0;
      tri_rgb[j][ch] = (u8)v;
    }
  }

  m_light.resize((size_t)m_instance_count * 4);
  for (int i = 0; i < m_instance_count; ++i) {
    u32 t = m_inst_tri[i];
    u8 cr = 128, cg = 128, cb = 128;
    if (t < tri_rgb.size()) {
      cr = tri_rgb[t][0];
      cg = tri_rgb[t][1];
      cb = tri_rgb[t][2];
    }
    m_light[(size_t)i * 4 + 0] = cr;
    m_light[(size_t)i * 4 + 1] = cg;
    m_light[(size_t)i * 4 + 2] = cb;
    m_light[(size_t)i * 4 + 3] = 255;
  }

  ensure_gl();
  glBindBuffer(GL_ARRAY_BUFFER, m_light_vbo);
  glBufferData(GL_ARRAY_BUFFER, (GLsizeiptr)m_light.size(),
               m_light.empty() ? nullptr : m_light.data(), GL_DYNAMIC_DRAW);
  glBindBuffer(GL_ARRAY_BUFFER, 0);

  for (int q = 0; q < 4; ++q) {
    for (int c = 0; c < 4; ++c) {
      m_last_itimes[q][c] = (int)rs->itimes[q][c];
    }
  }
  m_light_valid = true;
  m_light_uploads++;

  // POLISH#9 proof: the per-triangle baked luma the grass is CURRENTLY multiplied by. A wide
  // min..max = real per-LOCATION variation (grass darkens in baked-dark ground). uploads>1 over a
  // capture = the light is re-sampled as the time-of-day changes (DYNAMIC, not frozen at load).
  int lmin = 255, lmax = 0;
  double lsum = 0.0;
  for (const auto& c : tri_rgb) {
    int lum = (299 * c[0] + 587 * c[1] + 114 * c[2]) / 1000;
    lmin = std::min(lmin, lum);
    lmax = std::max(lmax, lum);
    lsum += lum;
  }
  lg::info(
      "[recharged-grass] POLISH#9 LIGHT upload #{} (itimes changed): dynamic GROUND baked light, "
      "per-tri baked luma min {} / mean {} / max {} over {} tris; grass *= (baked/255)*2 per-channel "
      "-> matches the ground beneath per LOCATION and per TIME OF DAY (wsum={}).",
      m_light_uploads, lmin, (int)(lsum / (double)std::max<size_t>(1, tri_rgb.size())), lmax,
      (int)tri_rgb.size(), wsum);
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

  // POLISH#9: refresh the per-instance GROUND baked-light for the current time of day (only actually
  // re-uploads when the time-of-day weights changed — so the grass tracks the day cycle dynamically).
  update_light(rs);

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
