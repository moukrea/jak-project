#include "GrassBakeCore.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <string>
#include <unordered_map>
#include <unordered_set>

#include "common/custom_data/Tfrag3Data.h"
#include "common/log/log.h"
#include "common/util/compress.h"

namespace grass_bake {

namespace {

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
// ROUND#23: foliage TIE draws must NOT become occluders when face-densifying the footprint test
// (POLISH#8: a shrub's alpha-transparent canopy never blocks grass — today it only stays harmless
// because its vertices are sparse). These keep the vertex-only status quo.
inline bool is_foliage(const std::string& n) {
  return name_has(n, "shrub") || name_has(n, "leaf") || name_has(n, "plant") ||
         name_has(n, "fern") || name_has(n, "flower") || name_has(n, "weed") ||
         name_has(n, "vine") || name_has(n, "frond") || name_has(n, "palm") ||
         name_has(n, "bush");
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

// ===========================================================================
// scan_level = today's rebuild() body from "int considered_draws = 0" through the
// occ block + R23 census, restructured SCAN -> TABLES (PHASE 2 became the table
// builder). Every expression / order / lg::info format is preserved.
// ===========================================================================
BakeData scan_level(const tfrag3::Level& lev_ref, const std::string& level_name, u64 fr3_size,
                    const ScanParams& params) {
  const tfrag3::Level* lev = &lev_ref;

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
    float nx, ny, nz;              // ROUND#19: NORMALIZED face normal (world, ny forced >= 0) for u_tilt
    bool is_lip;                   // POLISH#12: overhang rim-lip -> excluded from BASE placement
    bool is_tie;                   // ROUND#13: from a TIE placed model (platform) vs tfrag terrain
    bool is_dup;                   // ROUND#16: coincident duplicate tri (fragment overlap) -> no topology/bases
    bool is_hang;                  // ROUND6: source draw carries a native overhang-alpha hang texture (bit5)
    // POLISH#9 dynamic ground baked-light: this triangle's centroid palette rows (8 keyframes x rgb),
    // averaged over its 3 vertices, so update_light() can re-interpolate at the current time of day.
    float pal[8][3];
  };
  std::vector<TriRec> tris;

  // ROUND#13: occluder points for the per-instance object-hide = vertices of NON-grass TIE draws
  // ONLY (real objects: rocks / props / tree-trunks / the warp-gate). The grass-textured TIE PLATFORMS
  // must NOT occlude their own grass (that self-cull was ~most of the old 14.5%), and tfrag terrain is
  // never an occluder — so open grass with no real object on it is NEVER culled (structural occ ~0).
  std::vector<std::array<float, 3>> occ_pts;
  // ROUND#23 census: face-densified occluder sampling (small low-poly props leaked blades between
  // their sparse vertices). Counts + per-texture census logged after the occ cull.
  size_t r23_dens_tris = 0, r23_dens_pts = 0;
  std::unordered_map<std::string, u32> r23_dens_by_tex;
  // ROUND#23 capture aid: world positions (one per ~10m XZ cell) of ROCK-textured densified faces
  // near grass height — exact level.warp.pos targets for the small-rock leak close-ups.
  std::unordered_map<s64, std::array<float, 3>> r23_rock_spots;

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
  // Grecharged-grass-overhang: the steep grass-textured FRINGE faces (upness <= GROUND_UPNESS) are
  // now RETAINED in their own list — they are the faces carrying the game's painted drooping-grass
  // alpha texture, i.e. the droop placement zone. Kept OUT of `tris` so the walkable pass (topology,
  // density, budget, keep tables) is byte-identical to before; appended to the bake at the tail.
  std::vector<TriRec> fringe_recs;

  // Grecharged-grass-precompute-mode: the itimes-based CURRENT-TIME sampling is gone (no
  // SharedRenderState here). We ALWAYS take the itimes_valid=false path (the 8-palette average
  // fallback that already existed at vlum's tail). vlum/raw_baked/baked_ref/meanf feed ONLY
  // instrumentation logs (gspare is rim_dist since POLISH#11, and per-instance light rides the
  // separate u8 buffer at runtime), so this changes NO geometry or colour — only two log numbers
  // (bakedRef/meanf) and the printed itimesValid flag.
  bool itimes_valid = false;

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
      // Grecharged-grass-precompute-mode: itimes_valid is ALWAYS false here (no render state),
      // so this always takes the 8-palette average fallback below (unchanged geometry/colour).
      if (itimes_valid) {
        // (dead path in the bake TU — kept for a byte-identical structural move)
        return 128.0f;
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
      // ROUND6: does this draw's texture carry the native overhang ALPHA strip (the faces zone-3
      // covers with layered falling grass)? Captured by consider_tri's [&] into each TriRec.is_hang.
      bool draw_is_hang = is_fringe_hang_tex(tname);
      if (!matched) {
        if (looks_groundish(tname)) {
          unmatched_ground[tname]++;
        }
        // ROUND#13: a NON-grass TIE draw is a real solid object (rock / prop / tree-trunk / warp-gate)
        // that can sit ON the grass -> collect its vertices as object-hide occluders. Grass-textured TIE
        // draws are deliberately NOT collected (a grass platform must not occlude its own grass), and
        // tfrag terrain is never collected here -> only genuine objects hide grass.
        if (is_tie) {
          u32 b = draw.unpacked.idx_of_first_idx_in_full_buffer;
          u32 l = 0;
          for (const auto& g : draw.vis_groups) {
            l += g.num_inds;
          }
          if (l > 0 && b < idx.size()) {
            if (b + l > idx.size()) {
              l = (u32)(idx.size() - b);
            }
            for (u32 k = b; k < b + l; ++k) {
              u32 vi = idx[k];
              if (vi != UINT32_MAX && vi < verts.size()) {
                occ_pts.push_back({verts[vi].x, verts[vi].y, verts[vi].z});
              }
            }
            // ROUND#23 (owner R22b: "certains petits rochers ont de l'herbe qui passe au travers"):
            // vertex-only sampling LEAKS on small low-poly props — their vertices sit further apart
            // than OCC_RADIUS (0.45m), so a blade between two rock vertices never finds an occ point.
            // Close the gap with a FOOTPRINT test: decode the strip triangles and add face/edge
            // samples at sub-OCC_RADIUS pitch so every blade under an actual face is covered.
            // Foliage draws (shrubs & co, is_foliage) are skipped — their alpha-transparent canopy
            // must NOT occlude (POLISH#8). Huge faces (edge > 6m: walls/cliffs) keep vertex-only
            // sampling: they are not ground props and densifying them would explode memory.
            if (!is_foliage(tname)) {
              const float SAMP = 0.35f * 4096.f;      // pitch < OCC_RADIUS so no blade slips through
              const float EDGE_MAX = 6.0f * 4096.f;   // not a prop face past this
              for (u32 k = b + 2; k < b + l; ++k) {
                u32 i0 = idx[k - 2], i1 = idx[k - 1], i2 = idx[k];
                if (i0 == UINT32_MAX || i1 == UINT32_MAX || i2 == UINT32_MAX) {
                  continue;
                }
                if (i0 >= verts.size() || i1 >= verts.size() || i2 >= verts.size()) {
                  continue;
                }
                if (i0 == i1 || i1 == i2 || i0 == i2) {
                  continue;  // strip-stitch degenerate
                }
                float ax = verts[i0].x, ay = verts[i0].y, az = verts[i0].z;
                float e1x = verts[i1].x - ax, e1y = verts[i1].y - ay, e1z = verts[i1].z - az;
                float e2x = verts[i2].x - ax, e2y = verts[i2].y - ay, e2z = verts[i2].z - az;
                float d1 = std::sqrt(e1x * e1x + e1y * e1y + e1z * e1z);
                float d2 = std::sqrt(e2x * e2x + e2y * e2y + e2z * e2z);
                float e3x = e2x - e1x, e3y = e2y - e1y, e3z = e2z - e1z;
                float d3 = std::sqrt(e3x * e3x + e3y * e3y + e3z * e3z);
                float m = std::max(d1, std::max(d2, d3));
                if (m <= SAMP || m > EDGE_MAX) {
                  continue;  // already dense enough / not a prop face
                }
                int n = (int)std::ceil(m / SAMP);
                if (n > 24) {
                  n = 24;
                }
                for (int a = 0; a <= n; ++a) {
                  for (int c = 0; c <= n - a; ++c) {
                    if ((a == 0 && c == 0) || (a == n && c == 0) || (a == 0 && c == n)) {
                      continue;  // corners = the existing vertices
                    }
                    float fa = (float)a / (float)n, fc = (float)c / (float)n;
                    occ_pts.push_back(
                        {ax + fa * e1x + fc * e2x, ay + fa * e1y + fc * e2y, az + fa * e1z + fc * e2z});
                    r23_dens_pts++;
                  }
                }
                r23_dens_tris++;
                r23_dens_by_tex[tname]++;
                if (name_has(tname, "rock") || name_has(tname, "stone")) {
                  const float cinv = 1.0f / (10.0f * 4096.f);
                  s64 cx = (s64)std::floor(ax * cinv), cz = (s64)std::floor(az * cinv);
                  s64 ck = (cx << 32) ^ (cz & 0xffffffffLL);
                  if (r23_rock_spots.find(ck) == r23_rock_spots.end()) {
                    r23_rock_spots[ck] = {ax, ay, az};
                  }
                }
              }
            }
          }
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
          // Grecharged-grass-overhang: retain the FRINGE face for the droop pass (same field fill as
          // a kept tri, but into fringe_recs — the walkable accumulators/topology are untouched).
          {
            TriRec fr;
            fr.p0x = p0.x; fr.p0y = p0.y; fr.p0z = p0.z;
            fr.e1x = e1x; fr.e1y = e1y; fr.e1z = e1z;
            fr.e2x = e2x; fr.e2y = e2y; fr.e2z = e2z;
            fr.area_m2 = area_m2;
            fr.upness = upness;
            {
              float inv_nlen = 1.0f / nlen;
              float fnx = nx * inv_nlen, fny = ny * inv_nlen, fnz = nz * inv_nlen;
              if (fny < 0.f) { fnx = -fnx; fny = -fny; fnz = -fnz; }
              fr.nx = fnx; fr.ny = fny; fr.nz = fnz;
            }
            fr.is_lip = false;
            fr.is_tie = is_tie;
            fr.is_dup = false;
            fr.is_hang = draw_is_hang;  // ROUND6: native-alpha hang face -> zone-3 fall placement
            fr.gr = gcr; fr.gg = gcg; fr.gb = gcb;
            fr.raw_baked = (vlum(a) + vlum(b) + vlum(ci)) * (1.0f / 3.0f);
            fr.seed = (begin ^ (a * 2654435761u) ^ (ci * 40503u) ^ (is_tie ? 0x9e3779b9u : 0u));
            fr.nlen = nlen;
            fr.lenAB = std::sqrt(e1x * e1x + e1y * e1y + e1z * e1z);
            fr.lenCA = std::sqrt(e2x * e2x + e2y * e2y + e2z * e2z);
            float bcx = e2x - e1x, bcy = e2y - e1y, bcz = e2z - e1z;
            fr.lenBC = std::sqrt(bcx * bcx + bcy * bcy + bcz * bcz);
            fr.bAB = fr.bBC = fr.bCA = false;
            for (int p = 0; p < 8; ++p) {
              for (int ch = 0; ch < 3; ++ch) {
                fr.pal[p][ch] =
                    (pentry(a, p, ch) + pentry(b, p, ch) + pentry(ci, p, ch)) * (1.0f / 3.0f);
              }
            }
            fringe_recs.push_back(fr);
          }
          return;
        }
        min_kept_upness = std::min(min_kept_upness, upness);
        TriRec r;
        r.p0x = p0.x; r.p0y = p0.y; r.p0z = p0.z;
        r.e1x = e1x; r.e1y = e1y; r.e1z = e1z;
        r.e2x = e2x; r.e2y = e2y; r.e2z = e2z;
        r.area_m2 = area_m2;
        r.upness = upness;   // POLISH#12: kept for the PHASE 1.5 overhang-lip classifier
        // ROUND#19: NORMALIZED face normal, flipped so ny >= 0 (world-up hemisphere), for the shader
        // normal-tilt blend (u_tilt). nlen > 1e-3 guaranteed above; winding-agnostic like `upness`.
        {
          float inv_nlen = 1.0f / nlen;
          float fnx = nx * inv_nlen, fny = ny * inv_nlen, fnz = nz * inv_nlen;
          if (fny < 0.f) { fnx = -fnx; fny = -fny; fnz = -fnz; }
          r.nx = fnx; r.ny = fny; r.nz = fnz;
        }
        r.is_lip = false;
        r.is_tie = is_tie;   // ROUND#13: tfrag-vs-TIE split for the lip/rim instrumentation
        r.is_hang = draw_is_hang;  // ROUND6: native-alpha hang face (bit5)
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

  // ---- ROUND#16 (PHASE 1.5): ROBUST true-edge detection -> overhang-lip base exclusion + exact rim. ----
  // SUPERVISOR CODE READ (2026-07-11): after SEVEN rounds the persistent floating-overflow root is that
  // the boundary detection was the EDGE-COUNT method keyed on a RAW 1 cm vertex quantize. On TIE / multi-
  // fragment grass platforms the SAME physical vertex has slightly different float coords across separate
  // fragments (it does NOT weld at a 1 cm grid, and grid-straddle splits even coincident verts) AND
  // duplicate/coincident tris appear, so a real OUTER rim edge is counted as used by >=2 tris and is NOT
  // flagged a boundary. That single miss disabled BOTH (1) the overhang-lip exclusion (drooping edge lips
  // kept placing bases -> the floating the owner saw) and (2) the exact mesh-edge rim clamp (no taper at
  // the real rim). ROUND#16 fixes the FOUNDATION: weld vertices to a CANONICAL id robust to fragment
  // float mismatch (a NEIGHBOR-PROBE spatial hash, not a raw grid quantize) and DEDUP coincident triangles
  // BEFORE counting, so a shared physical edge is counted once and a real border edge (one triangle in
  // world space) is correctly flagged on TIE multi-fragment platforms too. This is the single fix that
  // unblocks BOTH the lip exclusion and the rim clamp, and it REPLACES the round#15 0.1 m coverage RASTER
  // entirely (owner verbatim: "les grids/rasters c'est nul, on a le mesh du sol, autant utiliser ça") —
  // the rim distance is now the EXACT point-to-true-rim-edge distance (dmin, PHASE 2), continuous and
  // hugging the real mesh edge with no stair-step.
  const float WELD = 0.03f * U;                       // 3 cm canonical weld; neighbor-probe merges up to
                                                      // ~2x that of cross-fragment float mismatch. Grass
                                                      // tri edges are >>6 cm, so distinct verts never merge.
  std::unordered_map<u64, std::vector<int>> wcells;   // quantized cell -> canonical vertex ids inside it
  std::vector<std::array<float, 3>> wverts;           // canonical vertex world positions (GOAL units)
  wcells.reserve(tris.size() * 3 + 16);
  wverts.reserve(tris.size() * 2 + 16);
  auto wcell = [WELD](float x, float y, float z) -> u64 {
    s64 qx = (s64)std::floor(x / WELD), qy = (s64)std::floor(y / WELD), qz = (s64)std::floor(z / WELD);
    return (u64)(qx * 73856093LL) ^ (u64)(qy * 19349663LL) ^ (u64)(qz * 83492791LL);
  };
  // canonical vertex id: return an existing vert within WELD (probing the 27 neighbour cells so a weld
  // never fails on a grid-straddle), else intern a new one. This is what makes the edge count robust.
  auto weld_vertex = [&](float x, float y, float z) -> int {
    s64 cx = (s64)std::floor(x / WELD), cy = (s64)std::floor(y / WELD), cz = (s64)std::floor(z / WELD);
    const float tol2 = WELD * WELD;
    for (s64 dz = -1; dz <= 1; ++dz)
      for (s64 dy = -1; dy <= 1; ++dy)
        for (s64 dx = -1; dx <= 1; ++dx) {
          u64 k = (u64)((cx + dx) * 73856093LL) ^ (u64)((cy + dy) * 19349663LL) ^
                  (u64)((cz + dz) * 83492791LL);
          auto it = wcells.find(k);
          if (it == wcells.end()) continue;
          for (int vid : it->second) {
            float ddx = wverts[vid][0] - x, ddy = wverts[vid][1] - y, ddz = wverts[vid][2] - z;
            if (ddx * ddx + ddy * ddy + ddz * ddz <= tol2) return vid;
          }
        }
    int id = (int)wverts.size();
    wverts.push_back({x, y, z});
    wcells[wcell(x, y, z)].push_back(id);
    return id;
  };
  // edge key from two canonical ids (packed, exact: vert count << 2^21). Triangle key = sorted triple.
  auto ekey2 = [](int a, int b) -> u64 {
    u32 lo = (u32)(a < b ? a : b), hi = (u32)(a < b ? b : a);
    return ((u64)lo << 21) | (u64)hi;
  };
  std::vector<std::array<int, 3>> vids(tris.size());  // canonical vertex ids per tri
  int n_dup = 0;
  {
    std::unordered_set<u64> seen_tri;
    seen_tri.reserve(tris.size() * 2 + 16);
    for (int i = 0; i < (int)tris.size(); ++i) {
      auto& r = tris[i];
      int a = weld_vertex(r.p0x, r.p0y, r.p0z);
      int b = weld_vertex(r.p0x + r.e1x, r.p0y + r.e1y, r.p0z + r.e1z);
      int c = weld_vertex(r.p0x + r.e2x, r.p0y + r.e2y, r.p0z + r.e2z);
      vids[i] = {a, b, c};
      int s0 = a, s1 = b, s2 = c;
      if (s0 > s1) std::swap(s0, s1);
      if (s1 > s2) std::swap(s1, s2);
      if (s0 > s1) std::swap(s0, s1);
      u64 tkey = ((u64)(u32)s0 << 42) | ((u64)(u32)s1 << 21) | (u64)(u32)s2;
      r.is_dup = !seen_tri.insert(tkey).second;   // a fragment-overlap duplicate: no topology, no bases
      if (r.is_dup) n_dup++;
    }
  }
  int boundary_edges = 0;
  int lip_excluded = 0;         // POLISH#12: overhang rim-lip tris whose BASES are excluded (no floating)
  int lip_excluded_tie = 0;     // ROUND#13: of those, how many are TIE (distant platform) tris
  float lip_excluded_area = 0.f;
  float min_placed_upness = 1.0f;
  int n_weld_verts = (int)wverts.size();
  int boundary_raw = 0;         // ROUND#16 instrumentation: OLD raw-1cm boundary count (proves the miss)
  {
    // (1)+(2) OVERHANG-LIP classification — ROUND#13 TRANSITIVE closure over ROBUST adjacency. A tilted
    // tri (upness < UPNESS_LIP_MAX) is an overhang lip iff its LOWEST edge opens into void (used by no
    // OTHER non-dup grass tri) OR is shared with a tri that is ITSELF a lip. Seeded at the void, propagated
    // UP the skirt; a FLAT/gentle top (upness >= UPNESS_LIP_MAX) is NEVER a lip and STOPS the propagation,
    // so continuous walkable slopes keep their grass (POLISH#3 coverage preserved). With the ROBUST weld a
    // multi-fragment skirt's shared edges now dedup, so the seed/propagation is no longer defeated by float
    // mismatch — the exact defect that let bases stay on distant-TIE-platform lips.
    std::unordered_map<u64, std::vector<int>> etris;  // edge -> tri indices sharing it (manifold: <= 2)
    etris.reserve(tris.size() * 3 + 16);
    std::vector<u64> low_edge(tris.size(), 0);        // each tri's lowest (downhill) edge key
    std::vector<char> tilted(tris.size(), 0);         // upness < UPNESS_LIP_MAX -> a lip CANDIDATE
    for (int i = 0; i < (int)tris.size(); ++i) {
      auto& r = tris[i];
      r.is_lip = false;
      if (r.is_dup) continue;                         // duplicates contribute no topology
      int a = vids[i][0], b = vids[i][1], c = vids[i][2];
      u64 eAB = ekey2(a, b), eBC = ekey2(b, c), eCA = ekey2(c, a);
      etris[eAB].push_back(i);
      etris[eBC].push_back(i);
      etris[eCA].push_back(i);
      float Ay = r.p0y, By = r.p0y + r.e1y, Cy = r.p0y + r.e2y;
      float mAB = Ay + By, mBC = By + Cy, mCA = Cy + Ay;  // 2x edge-midpoint Y (compare only)
      low_edge[i] = (mAB <= mBC && mAB <= mCA) ? eAB : (mBC <= mCA ? eBC : eCA);
      tilted[i] = (r.upness < UPNESS_LIP_MAX) ? 1 : 0;
    }
    // reverse index: which tilted tris have edge e as THEIR lowest (downhill) edge — so when a tri on e
    // becomes a lip, we know which tris drop off toward it and must be re-checked.
    std::unordered_map<u64, std::vector<int>> low_users;
    low_users.reserve(tris.size() + 16);
    std::vector<int> work;
    for (int i = 0; i < (int)tris.size(); ++i) {
      if (!tilted[i] || tris[i].is_dup) continue;
      low_users[low_edge[i]].push_back(i);
      const auto& sh = etris[low_edge[i]];  // seed: lowest edge opens into the void (no OTHER grass tri)
      bool boundary = true;
      for (int t : sh) {
        if (t != i) { boundary = false; break; }
      }
      if (boundary) { tris[i].is_lip = true; work.push_back(i); }
    }
    while (!work.empty()) {  // propagate up the skirt: a tilted tri drops toward a lip => it is a lip too
      int n = work.back();
      work.pop_back();
      int a = vids[n][0], b = vids[n][1], c = vids[n][2];
      u64 es[3] = {ekey2(a, b), ekey2(b, c), ekey2(c, a)};
      for (u64 e : es) {
        auto it = low_users.find(e);  // tris whose DOWNHILL edge is e (they drop toward n)
        if (it == low_users.end()) {
          continue;
        }
        for (int t : it->second) {
          if (t == n || tris[t].is_lip || tris[t].is_dup) {
            continue;
          }
          tris[t].is_lip = true;
          work.push_back(t);
        }
      }
    }
    for (int i = 0; i < (int)tris.size(); ++i) {
      if (tris[i].is_dup) continue;
      if (tris[i].is_lip) {
        lip_excluded++;
        lip_excluded_area += tris[i].area_m2;
        if (tris[i].is_tie) {
          lip_excluded_tie++;
        }
      } else {
        min_placed_upness = std::min(min_placed_upness, tris[i].upness);
      }
    }
    // (3) FINAL edge count over ONLY the tris that will actually be PLACED (dup + lip removed). Now a real
    // outer rim edge (drop-off / rock-wall / shoulder shared with an excluded lip) is used ONCE = a TRUE
    // RIM, so PHASE 2 stamps its near-rim blades with an exact rim_dist (dmin) and the shader height-taper
    // + horizontal clamp hold the grass to the exact top edge (no overflow past it, no bald fringe);
    // interior seams between two PLACED tris stay shared = full coverage. Robust across TIE fragments now.
    std::unordered_map<u64, int> edge_count;
    edge_count.reserve(tris.size() * 3 + 16);
    for (int i = 0; i < (int)tris.size(); ++i) {
      const auto& r = tris[i];
      if (r.is_dup || r.is_lip) continue;
      edge_count[ekey2(vids[i][0], vids[i][1])]++;  // AB
      edge_count[ekey2(vids[i][1], vids[i][2])]++;  // BC
      edge_count[ekey2(vids[i][2], vids[i][0])]++;  // CA
    }
    for (int i = 0; i < (int)tris.size(); ++i) {
      auto& r = tris[i];
      if (r.is_dup || r.is_lip) {
        r.bAB = r.bBC = r.bCA = false;
        continue;
      }
      r.bAB = edge_count[ekey2(vids[i][0], vids[i][1])] <= 1;
      r.bBC = edge_count[ekey2(vids[i][1], vids[i][2])] <= 1;
      r.bCA = edge_count[ekey2(vids[i][2], vids[i][0])] <= 1;
      boundary_edges += (int)r.bAB + (int)r.bBC + (int)r.bCA;
    }
    // INSTRUMENTATION (supervisor mandate: PROVE the miss before trusting the swap). Recompute the OLD
    // boundary count the round#15 way — a RAW 1 cm quantize, NO neighbour-probe weld, NO coincident-tri
    // dedup — over the same non-lip placed set. If boundary_edges (robust) differs from boundary_raw, the
    // old 1 cm count mis-flagged rims on TIE/multi-fragment platforms = the floating culprit; the robust
    // count is what the exact rim clamp now runs on.
    {
      const float Q1 = 0.01f * U;
      auto rk = [Q1](float x, float y, float z) -> u64 {
        s64 qx = (s64)std::llround(x / Q1), qy = (s64)std::llround(y / Q1), qz = (s64)std::llround(z / Q1);
        return (u64)(qx * 73856093LL) ^ (u64)(qy * 19349663LL) ^ (u64)(qz * 83492791LL);
      };
      auto rek = [](u64 va, u64 vb) -> u64 {
        u64 lo = va < vb ? va : vb, hi = va < vb ? vb : va;
        return lo * 0x9e3779b97f4a7c15ull + (hi ^ (hi >> 29));
      };
      std::unordered_map<u64, int> ec;
      ec.reserve(tris.size() * 3 + 16);
      for (const auto& r : tris) {
        if (r.is_lip) continue;
        u64 va = rk(r.p0x, r.p0y, r.p0z);
        u64 vb = rk(r.p0x + r.e1x, r.p0y + r.e1y, r.p0z + r.e1z);
        u64 vc = rk(r.p0x + r.e2x, r.p0y + r.e2y, r.p0z + r.e2z);
        ec[rek(va, vb)]++;
        ec[rek(vb, vc)]++;
        ec[rek(vc, va)]++;
      }
      for (const auto& r : tris) {
        if (r.is_lip) continue;
        u64 va = rk(r.p0x, r.p0y, r.p0z);
        u64 vb = rk(r.p0x + r.e1x, r.p0y + r.e1y, r.p0z + r.e1z);
        u64 vc = rk(r.p0x + r.e2x, r.p0y + r.e2y, r.p0z + r.e2z);
        boundary_raw += (int)(ec[rek(va, vb)] <= 1) + (int)(ec[rek(vb, vc)] <= 1) +
                        (int)(ec[rek(vc, va)] <= 1);
      }
    }
  }

  // ---- ROUND#20 (supervisor direct fix): GLOBAL rim distance — segment hash of ALL true-rim edges. ----
  // The own-tri rim_dist (below) only sees a rim edge belonging to the blade's OWN triangle. A full-
  // height blade on the INTERIOR triangle right behind a NARROW rim triangle has rim_dist=NO_RIM and
  // leans its tip past the platform edge — the residual "ça dépasse" no own-tri taper can ever see.
  // Fix: hash every true-rim edge SEGMENT (world space); each blade takes the min of its own-tri exact
  // distance and the distance to the nearest rim segment within RIM_QUERY (XZ metric, Y-windowed so a
  // rim of another storey — terrace above/below — never tapers this one). ~2k segments, O(1) per blade.
  struct RimSeg {
    float ax, ay, az, bx, by, bz;
  };
  std::vector<RimSeg> rim_segs;
  std::unordered_map<s64, std::vector<int>> rim_grid;
  const float RIM_QUERY = 1.2f * U;   // blades further than this from every rim stay full height
  const float RIM_BUCKET = 1.5f * U;  // bucket >= query so a 3x3 lookup suffices
  const float RIM_YWIN = 1.5f * U;    // ignore rim edges of a different storey
  const float rim_inv = 1.0f / RIM_BUCKET;
  {
    auto add_seg = [&](float ax, float ay, float az, float bx2, float by2, float bz2) {
      int si = (int)rim_segs.size();
      rim_segs.push_back({ax, ay, az, bx2, by2, bz2});
      s64 gx0 = (s64)std::floor(std::min(ax, bx2) * rim_inv);
      s64 gx1 = (s64)std::floor(std::max(ax, bx2) * rim_inv);
      s64 gz0 = (s64)std::floor(std::min(az, bz2) * rim_inv);
      s64 gz1 = (s64)std::floor(std::max(az, bz2) * rim_inv);
      for (s64 gz = gz0; gz <= gz1; ++gz)
        for (s64 gx = gx0; gx <= gx1; ++gx)
          rim_grid[(gx << 32) ^ (gz & 0xffffffffLL)].push_back(si);
    };
    for (const auto& r : tris) {
      if (r.is_dup || r.is_lip) continue;
      float Ax = r.p0x, Ay = r.p0y, Az = r.p0z;
      float Bx = r.p0x + r.e1x, By = r.p0y + r.e1y, Bz = r.p0z + r.e1z;
      float Cx = r.p0x + r.e2x, Cy = r.p0y + r.e2y, Cz = r.p0z + r.e2z;
      if (r.bAB) add_seg(Ax, Ay, Az, Bx, By, Bz);
      if (r.bBC) add_seg(Bx, By, Bz, Cx, Cy, Cz);
      if (r.bCA) add_seg(Cx, Cy, Cz, Ax, Ay, Az);
    }
  }
  // min XZ distance from (px,py,pz) to any rim segment within RIM_QUERY, Y-windowed. NO_RIM if none.
  auto rim_dist_global = [&](float px, float py, float pz) -> float {
    if (rim_segs.empty()) return 1.0e9f;
    float best = 1.0e9f;
    s64 gx = (s64)std::floor(px * rim_inv), gz = (s64)std::floor(pz * rim_inv);
    for (s64 dz = -1; dz <= 1; ++dz) {
      for (s64 dx = -1; dx <= 1; ++dx) {
        auto it = rim_grid.find(((gx + dx) << 32) ^ ((gz + dz) & 0xffffffffLL));
        if (it == rim_grid.end()) continue;
        for (int si : it->second) {
          const auto& s = rim_segs[si];
          float abx = s.bx - s.ax, abz = s.bz - s.az;
          float denom = abx * abx + abz * abz;
          float t = denom > 1e-6f ? ((px - s.ax) * abx + (pz - s.az) * abz) / denom : 0.f;
          t = t < 0.f ? 0.f : (t > 1.f ? 1.f : t);
          float cy = s.ay + t * (s.by - s.ay);
          if (std::fabs(cy - py) > RIM_YWIN) continue;  // rim of another storey
          float cx = s.ax + t * abx, cz = s.az + t * abz;
          float ddx = px - cx, ddz = pz - cz;
          float d = std::sqrt(ddx * ddx + ddz * ddz);
          if (d < best) best = d;
        }
      }
    }
    return best <= RIM_QUERY ? best : 1.0e9f;
  };
  int rim_segs_n = (int)rim_segs.size();

  // ---- ROUND#19: build the WALKABLE-FLOOR set + XZ hash for the point-wise cantilever cull. ----
  struct FloorTri {
    float p0x, p0y, p0z, e1x, e1y, e1z, e2x, e2y, e2z;  // world (GOAL units), same space as render tris
    float minx, maxx, minz, maxz;                       // XZ bbox (padded) for the cheap reject
    float d00, d01, d11, inv_denom;                     // precomputed XZ barycentric denominators
  };
  std::vector<FloorTri> floor_tris;
  std::unordered_map<u64, std::vector<int>> floor_grid;  // XZ bucket -> floor tri indices
  {
    const auto& cv = lev->collision.vertices;
    const size_t ntri = cv.size() / 3;
    floor_tris.reserve(ntri);
    const float finv = 1.0f / (FLOOR_BUCKET_M * U);
    const float pad = 0.05f * U;  // bbox pad = the barycentric seam slack, so the reject never over-culls
    for (size_t t = 0; t < ntri; ++t) {
      const auto& a = cv[t * 3 + 0];
      const auto& b = cv[t * 3 + 1];
      const auto& c = cv[t * 3 + 2];
      if (((a.pat >> 3) & 0x7u) != 0) continue;  // jak1 pat-surface mode 0 = walkable ground only
      float minx = std::min(a.x, std::min(b.x, c.x)), maxx = std::max(a.x, std::max(b.x, c.x));
      float minz = std::min(a.z, std::min(b.z, c.z)), maxz = std::max(a.z, std::max(b.z, c.z));
      if ((maxx - minx) > FLOOR_MAX_TRI_M * U || (maxz - minz) > FLOOR_MAX_TRI_M * U) continue;  // bbox guard
      FloorTri r;
      r.p0x = a.x; r.p0y = a.y; r.p0z = a.z;
      r.e1x = b.x - a.x; r.e1y = b.y - a.y; r.e1z = b.z - a.z;
      r.e2x = c.x - a.x; r.e2y = c.y - a.y; r.e2z = c.z - a.z;
      r.d00 = r.e1x * r.e1x + r.e1z * r.e1z;
      r.d01 = r.e1x * r.e2x + r.e1z * r.e2z;
      r.d11 = r.e2x * r.e2x + r.e2z * r.e2z;
      float denom = r.d00 * r.d11 - r.d01 * r.d01;
      if (std::fabs(denom) < 1e-6f) continue;  // degenerate (near-vertical/sliver) -> drop at build
      r.inv_denom = 1.0f / denom;
      r.minx = minx - pad; r.maxx = maxx + pad;
      r.minz = minz - pad; r.maxz = maxz + pad;
      int fi = (int)floor_tris.size();
      floor_tris.push_back(r);
      // insert into every XZ bucket the tri's bbox overlaps, so a point lookup of the own bucket suffices.
      s64 gx0 = (s64)std::floor(minx * finv), gx1 = (s64)std::floor(maxx * finv);
      s64 gz0 = (s64)std::floor(minz * finv), gz1 = (s64)std::floor(maxz * finv);
      for (s64 gz = gz0; gz <= gz1; ++gz)
        for (s64 gx = gx0; gx <= gx1; ++gx)
          floor_grid[((u64)(u32)(s32)gx << 32) | (u32)(s32)gz].push_back(fi);
    }
  }
  const float FLOOR_DEPTH = FLOOR_DEPTH_M * U;
  const float FLOOR_EPS_UP = FLOOR_EPS_UP_M * U;
  const float floor_inv = 1.0f / (FLOOR_BUCKET_M * U);
  constexpr float NO_FLOOR = 1e18f;
  auto floor_gap = [&](float bx, float by, float bz) -> float {
    if (floor_tris.empty()) return 0.f;
    s64 gx = (s64)std::floor(bx * floor_inv), gz = (s64)std::floor(bz * floor_inv);
    auto it = floor_grid.find(((u64)(u32)(s32)gx << 32) | (u32)(s32)gz);
    if (it == floor_grid.end()) return NO_FLOOR;
    float bestY = -NO_FLOOR;  // highest walkable floor within the window = the blade's OWN floor
    for (int ti : it->second) {
      const auto& r = floor_tris[ti];
      if (bx < r.minx || bx > r.maxx || bz < r.minz || bz > r.maxz) continue;  // cheap bbox reject
      float px = bx - r.p0x, pz = bz - r.p0z;
      float d20 = px * r.e1x + pz * r.e1z;
      float d21 = px * r.e2x + pz * r.e2z;
      float u = (r.d11 * d20 - r.d01 * d21) * r.inv_denom;
      float v = (r.d00 * d21 - r.d01 * d20) * r.inv_denom;
      // slack so a base exactly on a shared collision-tri seam can't fall through the crack.
      if (u >= -0.02f && v >= -0.02f && u + v <= 1.02f) {
        float floorY = r.p0y + u * r.e1y + v * r.e2y;
        if (floorY >= by - FLOOR_DEPTH && floorY <= by + FLOOR_EPS_UP && floorY > bestY) {
          bestY = floorY;
        }
      }
    }
    if (bestY <= -NO_FLOOR) return NO_FLOOR;
    float gap = by - bestY;
    return gap > 0.f ? gap : 0.f;
  };
  int floor_tris_n = (int)floor_tris.size();
  // Grecharged-grass-precompute-mode: floor-gap threshold comes from the caller (the #ifdef __ANDROID__
  // prop read moved out to GrassRenderer, which passes the value in via ScanParams).
  float floor_gap_thresh = params.floor_gap_m * U;

  // ---- PHASE 2 -> TABLE builder: density-complete candidate enumeration. ----
  // No budget break here (tables are density-complete; the budget is applied in expand()). The counters
  // and logs now count over ALL candidates at cand_density; the old budget break statistically never
  // fired (BUDGET_SAFETY), so numbers match at equal density.
  float dens_scale = std::min(2.5f, std::max(0.5f, params.cand_density_pct / 100.0f));
  int budget = (int)((float)MAX_INSTANCES * dens_scale);
  (void)budget;  // tables are density-complete; expand() applies the budget

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
  float meanf = baked_ref / 128.0f;
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

  // Build the object-point spatial hash BEFORE the candidate loop (moved up: it only needs occ_pts,
  // filled during the draw scan). Used to evaluate the per-candidate hidden test inline.
  const float occ_inv = 1.0f / (OCC_CELL_M * U);  // spatial-hash bucket (lookup only, NOT a cull unit)
  auto occ_bkey = [occ_inv](float x, float z) -> s64 {
    s64 gx = (s64)std::floor(x * occ_inv);
    s64 gz = (s64)std::floor(z * occ_inv);
    return (gx << 32) ^ (gz & 0xffffffffLL);
  };
  struct OP {
    float x, y, z;
  };
  std::unordered_map<s64, std::vector<OP>> objpts;
  objpts.reserve(4096);
  for (const auto& p : occ_pts) {
    objpts[occ_bkey(p[0], p[2])].push_back({p[0], p[1], p[2]});
  }
  size_t occ_objpts = objpts.size();
  const float occ_lo = OCC_LO_M * U, occ_hi = OCC_HI_M * U;
  const float occ_rad2 = (OCC_RADIUS_M * U) * (OCC_RADIUS_M * U);

  const float DROP_EPS = 0.005f * U;    // drop only a degenerate sliver whose base is < 5 mm from a rim
  const float NO_RIM = 1.0e9f;          // rim_dist sentinel for a blade with no rim edge in its triangle

  int edge_dropped = 0;   // degenerate rim slivers dropped individually (per-blade, NOT whole blocks)
  int edge_clamped = 0;   // near-rim blades whose horizontal reach the shader will clamp to the rim
  int rim_finite = 0;     // ROUND#16: blades that got a FINITE rim_dist (a true rim in their tri) vs interior
  int rim_global_hits = 0;  // ROUND#20: blades ONLY the cross-triangle global rim query protects
  const float RIM_TAPER_W = 0.45f * U;  // matches the shader RIM_TAPER (height fully restored 0.45 m in)
  int floor_tested = 0, floor_culled = 0;  // ROUND#19 point-wise cantilever cull instrumentation
  int gap_culled = 0;                      // ROUND#19b: floor exists but too far below (stacked terrace)
  std::vector<float> interior_gaps;        // ROUND#19b: gap samples for clearly-INTERIOR blades (p99 tune)
  interior_gaps.reserve(4096);

  // Tables. Every candidate index over all tris (in tri order); keep/rim_q are indexed by cand_base+i.
  std::vector<u8> keep_tbl;
  std::vector<u16> rimq_tbl;
  std::vector<BakeTri> bake_tris;
  bake_tris.reserve(tris.size());
  u64 cand_running = 0;

  for (size_t tj = 0; tj < tris.size(); ++tj) {
    const auto& r = tris[tj];
    BakeTri bt;
    bt.p0[0] = r.p0x; bt.p0[1] = r.p0y; bt.p0[2] = r.p0z;
    bt.e1[0] = r.e1x; bt.e1[1] = r.e1y; bt.e1[2] = r.e1z;
    bt.e2[0] = r.e2x; bt.e2[1] = r.e2y; bt.e2[2] = r.e2z;
    bt.seed = r.seed;
    bt.area_m2 = r.area_m2;
    bt.gr = r.gr; bt.gg = r.gg; bt.gb = r.gb;
    bt.nx = r.nx; bt.ny = r.ny; bt.nz = r.nz;
    std::memcpy(bt.pal, r.pal, sizeof(bt.pal));
    bt.flags = (r.is_tie ? 1u : 0u) | (r.is_lip ? 2u : 0u) | (r.is_dup ? 4u : 0u) | (r.is_hang ? 32u : 0u);
    bt.cand_base = cand_running;
    bt.cand_count = 0;

    if (r.is_lip || r.is_dup) {   // POLISH#12/ROUND#16: overhang lip or fragment duplicate -> no bases
      bake_tris.push_back(bt);
      continue;
    }
    float fn = r.area_m2 * density;
    int n = (int)fn;
    if (hash_f(r.seed + 99u) < (fn - (float)n)) {
      n += 1;
    }
    bt.cand_count = (u32)n;
    for (int i = 0; i < n; ++i) {
      u32 sd = r.seed + (u32)i * 3266489917u;
      float r1 = hash_f(sd + 1u);
      float r2 = hash_f(sd + 2u);
      if (r1 + r2 > 1.0f) {
        r1 = 1.0f - r1;
        r2 = 1.0f - r2;
      }
      // Barycentric weights (A,B,C) = (1-r1-r2, r1, r2).
      float wA = 1.0f - r1 - r2, wB = r1, wC = r2;
      float bx = r.p0x + r1 * r.e1x + r2 * r.e2x;
      float by = r.p0y + r1 * r.e1y + r2 * r.e2y;
      float bz = r.p0z + r1 * r.e1z + r2 * r.e2z;

      bool scatter_keep = true;
      // ROUND#19 / ROUND#19b floor cantilever cull.
      floor_tested++;
      {
        float fgap = floor_gap(bx, by, bz);
        if (fgap >= 1e17f) { floor_culled++; scatter_keep = false; }             // no floor at all: true void
        else if (fgap > floor_gap_thresh) { gap_culled++; scatter_keep = false; }  // stacked-terrace cantilever
        else {
          // clearly-interior sample (no boundary edge on this tri) -> tune/verify the gap threshold
          if (!r.bAB && !r.bBC && !r.bCA && (int)interior_gaps.size() < 200000) {
            interior_gaps.push_back(fgap);
          }
        }
      }

      // ROUND#16: rim_dist = the EXACT perpendicular distance from this base to the nearest TRUE RIM edge
      // of its own triangle. NO_RIM (interior) when no edge of this tri is a rim.
      float dmin = NO_RIM;
      if (r.bBC) { float d = wA * r.nlen / r.lenBC; if (d < dmin) dmin = d; }  // edge BC opposite A
      if (r.bCA) { float d = wB * r.nlen / r.lenCA; if (d < dmin) dmin = d; }  // edge CA opposite B
      if (r.bAB) { float d = wC * r.nlen / r.lenAB; if (d < dmin) dmin = d; }  // edge AB opposite C
      {
        float dg = rim_dist_global(bx, by, bz);
        if (dg < dmin) {
          if (dmin >= NO_RIM) rim_global_hits++;  // blades ONLY the global query protects
          dmin = dg;
        }
      }
      // The ONLY per-blade rejection is a degenerate sliver whose base sits < 5 mm from a true rim.
      if (dmin < DROP_EPS) { edge_dropped++; scatter_keep = false; }

      if (scatter_keep) {
        if (dmin < NO_RIM) rim_finite++;                     // blades with a real rim in their triangle
        if (dmin < RIM_TAPER_W) edge_clamped++;              // blades inside the shader height-taper band
      }

      // Occlusion (object-hide) test for candidates that passed the floor+rim pass. Same math as
      // today's post-loop filter; occ_culled counting moves to expand().
      bool occ_hidden = false;
      if (scatter_keep && !objpts.empty()) {
        s64 obx = (s64)std::floor(bx * occ_inv);
        s64 obz = (s64)std::floor(bz * occ_inv);
        for (s64 dz = -1; dz <= 1 && !occ_hidden; ++dz) {
          for (s64 dx = -1; dx <= 1 && !occ_hidden; ++dx) {
            s64 k = ((obx + dx) << 32) ^ ((obz + dz) & 0xffffffffLL);
            auto oit = objpts.find(k);
            if (oit == objpts.end()) {
              continue;
            }
            for (const auto& p : oit->second) {
              float dy = p.y - by;             // object must be in the near-ground contact band
              if (dy <= occ_lo || dy >= occ_hi) {
                continue;
              }
              float ddx = p.x - bx, ddz = p.z - bz;  // and within OCC_RADIUS of THIS blade's base
              if (ddx * ddx + ddz * ddz <= occ_rad2) {
                occ_hidden = true;
                break;
              }
            }
          }
        }
      }

      keep_tbl.push_back((u8)((scatter_keep ? 1u : 0u) | (occ_hidden ? 0u : 2u)));
      rimq_tbl.push_back(rim_encode(dmin));
    }
    cand_running += (u64)n;
    bake_tris.push_back(bt);
  }

  // ---- Grecharged-grass-overhang: droop-candidate table (lip tris + appended fringe tris). ----
  // The droop zone = the faces the walkable pass EXCLUDES: the overhang-lip tris (is_lip) and the
  // steep grass-textured fringe faces (fringe_recs — the game's painted drooping-grass alpha strip).
  // Per face we resolve the OUTWARD direction (unit XZ pointing over the drop):
  //   primary  = the horizontal component of the ny>=0 face normal (the downhill direction — for an
  //              overhang face that is outward; flip-invariant, so the winding ambiguity is moot);
  //   fallback = centroid minus the nearest true-rim point (for near-vertical faces, upness < 0.10,
  //              where the ny>=0 flip is float-noise).
  // FRINGE faces additionally require a true rim within DROOP_RIM_NEAR_M (XZ, Y-windowed) so a steep
  // grass-textured wall far from any walkable edge (not an overhang) gets nothing. Lips are adjacent
  // to the rim by construction (their shoulder edge IS the rim) — no guard needed.
  std::vector<DroopTri> droop_tbl;
  int droop_lips = 0, droop_fringe = 0, fringe_no_rim = 0, droop_dir_fallback = 0;
  float droop_area = 0.f;
  {
    const float DROOP_NEAR = DROOP_RIM_NEAR_M * U;
    const float DROOP_YWIN = 3.0f * U;
    // nearest rim point to (px,py,pz): XZ metric, Y-windowed. Returns squared XZ distance (or 1e30)
    // and writes the closest point. Buckets are RIM_BUCKET (1.5 m); DROOP_NEAR (2.5 m) needs +-2.
    auto nearest_rim = [&](float px, float py, float pz, float& cxo, float& czo) -> float {
      float best = 1e30f;
      if (rim_segs.empty()) return best;
      s64 gx = (s64)std::floor(px * rim_inv), gz = (s64)std::floor(pz * rim_inv);
      for (s64 dz = -2; dz <= 2; ++dz) {
        for (s64 dx = -2; dx <= 2; ++dx) {
          auto it = rim_grid.find(((gx + dx) << 32) ^ ((gz + dz) & 0xffffffffLL));
          if (it == rim_grid.end()) continue;
          for (int si : it->second) {
            const auto& sg = rim_segs[si];
            float abx = sg.bx - sg.ax, abz = sg.bz - sg.az;
            float denom = abx * abx + abz * abz;
            float t = denom > 1e-6f ? ((px - sg.ax) * abx + (pz - sg.az) * abz) / denom : 0.f;
            t = t < 0.f ? 0.f : (t > 1.f ? 1.f : t);
            float cy = sg.ay + t * (sg.by - sg.ay);
            if (std::fabs(cy - py) > DROOP_YWIN) continue;
            float cx = sg.ax + t * abx, cz = sg.az + t * abz;
            float ddx = px - cx, ddz = pz - cz;
            float d2 = ddx * ddx + ddz * ddz;
            if (d2 < best) { best = d2; cxo = cx; czo = cz; }
          }
        }
      }
      return best;
    };
    // resolve one face; tri_idx = FINAL index in bake_tris. Returns false if no direction/rim.
    auto add_droop = [&](u32 tri_idx, const TriRec& r, bool need_rim_guard) -> bool {
      float cx = r.p0x + (r.e1x + r.e2x) * (1.0f / 3.0f);
      float cy = r.p0y + (r.e1y + r.e2y) * (1.0f / 3.0f);
      float cz = r.p0z + (r.e1z + r.e2z) * (1.0f / 3.0f);
      float rx = 0.f, rz = 0.f;
      float rim_d2 = nearest_rim(cx, cy, cz, rx, rz);
      if (need_rim_guard && rim_d2 > DROOP_NEAR * DROOP_NEAR) {
        fringe_no_rim++;
        return false;
      }
      float ox, oz;
      if (r.upness >= DROOP_UPNESS_DIR_MIN) {
        ox = r.nx;  // horizontal component of the ny>=0 normal = downhill = outward over the drop
        oz = r.nz;
      } else if (rim_d2 < 1e29f) {
        ox = cx - rx;  // near-vertical face: point away from the nearest walkable rim
        oz = cz - rz;
        droop_dir_fallback++;
      } else {
        return false;  // vertical face with no rim in reach: no reliable outward direction
      }
      float ol = std::sqrt(ox * ox + oz * oz);
      if (ol < 1e-4f) return false;
      droop_tbl.push_back({tri_idx, ox / ol, oz / ol});
      droop_area += r.area_m2;
      return true;
    };
    for (size_t tj = 0; tj < tris.size(); ++tj) {
      if (tris[tj].is_lip && !tris[tj].is_dup) {
        if (add_droop((u32)tj, tris[tj], false)) droop_lips++;
      }
    }
    for (const auto& fr : fringe_recs) {
      BakeTri bt;
      bt.p0[0] = fr.p0x; bt.p0[1] = fr.p0y; bt.p0[2] = fr.p0z;
      bt.e1[0] = fr.e1x; bt.e1[1] = fr.e1y; bt.e1[2] = fr.e1z;
      bt.e2[0] = fr.e2x; bt.e2[1] = fr.e2y; bt.e2[2] = fr.e2z;
      bt.seed = fr.seed;
      bt.area_m2 = fr.area_m2;
      bt.gr = fr.gr; bt.gg = fr.gg; bt.gb = fr.gb;
      bt.nx = fr.nx; bt.ny = fr.ny; bt.nz = fr.nz;
      std::memcpy(bt.pal, fr.pal, sizeof(bt.pal));
      bt.flags = (fr.is_tie ? 1u : 0u) | 8u | (fr.is_hang ? 32u : 0u);  // bit3 = fringe; bit5 = native-alpha hang face
      bt.cand_base = cand_running;
      bt.cand_count = 0;
      u32 tri_idx = (u32)bake_tris.size();
      // only APPEND the fringe tri when it actually droops — a dropped face would be dead weight
      if (add_droop(tri_idx, fr, true)) {
        bake_tris.push_back(bt);
        droop_fringe++;
      }
    }
  }
  int droop_hang_tris = 0;  // ROUND6 census: droop faces carrying the native overhang-alpha texture (zone 3)
  for (const auto& de : droop_tbl) {
    if (de.tri < bake_tris.size() && (bake_tris[de.tri].flags & 32u)) droop_hang_tris++;
  }
  lg::info(
      "[recharged-grass] GOVERHANG droop zone: lips={} fringe_kept={} (of {} fringe faces; {} no-rim, "
      "{} no-dir) area={:.0f}m2 dir_fallback={} droop_tris={} hang_tris={} (outward = downhill normal, "
      "rim fallback under upness {:.2f}; fringe guard = rim within {:.1f}m)",
      droop_lips, droop_fringe, (int)fringe_recs.size(), fringe_no_rim,
      (int)fringe_recs.size() - droop_fringe - fringe_no_rim, droop_area, droop_dir_fallback,
      (int)droop_tbl.size(), droop_hang_tris, DROOP_UPNESS_DIR_MIN, DROOP_RIM_NEAR_M);

  // ---- Grecharged-grass-overhang2: droop-RIM segments (owner ROUND-2 defect 3). ----
  // Keep the true-rim segments that border the droop zone: a segment is kept when its closest point
  // to some droop face's centroid lies within that face's own XZ bounding radius + DROOP_RIM_KEEP_M
  // (Y-windowed — lip/fringe faces drop below their rim). expand() leans walkable-top blades
  // progressively toward these segments (the upright->droop transition twins); they must ride in the
  // BAKE because precomputed mode's rim_q stores only a distance, never a direction. Rims far from
  // every droop face (bare edges with no overhang below) are NOT kept — leaning grass out over those
  // would re-create the LOCKED-fixed floating-blade overflow.
  std::vector<DroopRimSeg> droop_rim_segs;
  {
    std::vector<char> seg_mark(rim_segs.size(), 0);
    const float ywin = DROOP_RIM_YWIN_M * U;
    for (const auto& de : droop_tbl) {
      const BakeTri& bt = bake_tris[de.tri];
      float cx = bt.p0[0] + (bt.e1[0] + bt.e2[0]) * (1.0f / 3.0f);
      float cy = bt.p0[1] + (bt.e1[1] + bt.e2[1]) * (1.0f / 3.0f);
      float cz = bt.p0[2] + (bt.e1[2] + bt.e2[2]) * (1.0f / 3.0f);
      // face XZ bounding radius from the centroid (max over the three verts)
      float r2max = 0.f;
      for (int vi = 0; vi < 3; ++vi) {
        float vx = bt.p0[0] + (vi == 1 ? bt.e1[0] : 0.f) + (vi == 2 ? bt.e2[0] : 0.f);
        float vz = bt.p0[2] + (vi == 1 ? bt.e1[2] : 0.f) + (vi == 2 ? bt.e2[2] : 0.f);
        float dx = vx - cx, dz = vz - cz;
        float d2 = dx * dx + dz * dz;
        if (d2 > r2max) r2max = d2;
      }
      float keep = std::sqrt(r2max) + DROOP_RIM_KEEP_M * U;
      float keep2 = keep * keep;
      for (size_t si = 0; si < rim_segs.size(); ++si) {
        if (seg_mark[si]) continue;
        const auto& s = rim_segs[si];
        float abx = s.bx - s.ax, abz = s.bz - s.az;
        float denom = abx * abx + abz * abz;
        float t = denom > 1e-6f ? ((cx - s.ax) * abx + (cz - s.az) * abz) / denom : 0.f;
        t = t < 0.f ? 0.f : (t > 1.f ? 1.f : t);
        float sy = s.ay + t * (s.by - s.ay);
        if (std::fabs(sy - cy) > ywin) continue;
        float sx = s.ax + t * abx, sz = s.az + t * abz;
        float dx = cx - sx, dz = cz - sz;
        if (dx * dx + dz * dz <= keep2) seg_mark[si] = 1;
      }
    }
    for (size_t si = 0; si < rim_segs.size(); ++si) {
      if (seg_mark[si]) {
        const auto& s = rim_segs[si];
        droop_rim_segs.push_back({s.ax, s.ay, s.az, s.bx, s.by, s.bz});
      }
    }
    lg::info(
        "[recharged-grass] GOVERHANG2 droop rims: {} of {} true-rim segments border the droop zone "
        "(keep margin {:.2f}m, ywin {:.1f}m) — transition twins lean toward these only",
        (int)droop_rim_segs.size(), (int)rim_segs.size(), DROOP_RIM_KEEP_M, DROOP_RIM_YWIN_M);
  }

  // ---- Grecharged-grass-overhang3: TRANSITION-BAND classification (owner correction 2026-07-13).
  // A placed walkable tri is the curl band iff it is tilted (upness < TRANS_UPNESS_HI) AND its
  // centroid sits within TRANS_TRI_NEAR_M (XZ, Y-windowed) of a droop-rim segment. Genuinely flat
  // tris and tilted grass far from every droop rim are untouched -> the LOCKED edge stack
  // (rim segs / rim_q / keep tables / FLOORBELOW / FLOORGAP) is byte-identical; this only sets
  // flags bit4, which expand() turns into a comb TAG (never a placement change).
  int trans_tris = 0;
  float trans_area = 0.f;
  if (!droop_rim_segs.empty()) {
    const float near_m = TRANS_TRI_NEAR_M * U;
    const float near2 = near_m * near_m;
    const float ywin = TRANS_TRI_YWIN_M * U;
    for (auto& bt : bake_tris) {
      if (bt.flags & (2u | 4u | 8u)) continue;  // lip | dup | fringe: not walkable-base tris
      if (bt.ny >= TRANS_UPNESS_HI) continue;   // genuinely flat: never combed
      float cx = bt.p0[0] + (bt.e1[0] + bt.e2[0]) * (1.0f / 3.0f);
      float cy = bt.p0[1] + (bt.e1[1] + bt.e2[1]) * (1.0f / 3.0f);
      float cz = bt.p0[2] + (bt.e1[2] + bt.e2[2]) * (1.0f / 3.0f);
      bool near_rim = false;
      for (const auto& s : droop_rim_segs) {
        float abx = s.bx - s.ax, abz = s.bz - s.az;
        float denom = abx * abx + abz * abz;
        float t = denom > 1e-6f ? ((cx - s.ax) * abx + (cz - s.az) * abz) / denom : 0.f;
        t = t < 0.f ? 0.f : (t > 1.f ? 1.f : t);
        float sy = s.ay + t * (s.by - s.ay);
        if (std::fabs(sy - cy) > ywin) continue;
        float sx = s.ax + t * abx, sz = s.az + t * abz;
        float dx = cx - sx, dz = cz - sz;
        if (dx * dx + dz * dz <= near2) { near_rim = true; break; }
      }
      if (!near_rim) continue;
      bt.flags |= 16u;
      trans_tris++;
      trans_area += bt.area_m2;
    }
  }
  lg::info(
      "[recharged-grass] GOVERHANG3 transition band: {} walkable tris flagged (area {:.0f}m2, "
      "upness < {:.2f}, within {:.1f}m of a droop rim) — their blades comb in-plane when the "
      "overhang toggle is ON; placement itself untouched",
      trans_tris, trans_area, TRANS_UPNESS_HI, TRANS_TRI_NEAR_M);

  // ROUND#16 instrumentation (RIMDIST). placed = candidates that passed the floor+rim pass (scatter_keep),
  // matching today's m_instances.size() at the point this log fired (pre-occ).
  int placed_pre_occ = 0;
  for (u8 k : keep_tbl) {
    if (k & 1) placed_pre_occ++;
  }
  lg::info(
      "[recharged-grass] RIMDIST exact-mesh (ROUND#16, raster REMOVED): placed={} rim_finite={} "
      "edge_clamped={} edge_dropped={} | robust true-edge: boundary_edges={} vs raw-1cm boundary_raw={} "
      "(delta={}), coincident_dups={}, weld_verts={} — robust weld/dedup flags the true rims the raw 1cm "
      "count missed on TIE multi-fragment platforms (the floating overflow root).",
      placed_pre_occ, rim_finite, edge_clamped, edge_dropped, boundary_edges, boundary_raw,
      boundary_edges - boundary_raw, n_dup, n_weld_verts);
  lg::info(
      "[recharged-grass] ROUND#20 GLOBAL-RIM: rim_segs={} rim_global_hits={} (interior-tri blades near a "
      "rim now tapered; own-tri-only missed them)",
      rim_segs_n, rim_global_hits);

  lg::info("[recharged-grass] ROUND#19 FLOORBELOW cantilever-cull: floor_tris={} tested={} culled={} kept={}", floor_tris_n, floor_tested, floor_culled + gap_culled, floor_tested - floor_culled - gap_culled);
  {
    float p50 = 0.f, p90 = 0.f, p99 = 0.f, pmax = 0.f;
    if (!interior_gaps.empty()) {
      std::sort(interior_gaps.begin(), interior_gaps.end());
      auto at = [&](double q) { return interior_gaps[(size_t)(q * (interior_gaps.size() - 1))]; };
      p50 = at(0.50); p90 = at(0.90); p99 = at(0.99); pmax = interior_gaps.back();
    }
    lg::info(
        "[recharged-grass] ROUND#19b FLOORGAP stacked-terrace cull: gap_thresh={:.0f}cm interior gap "
        "p50={:.0f}cm p90={:.0f}cm p99={:.0f}cm max={:.0f}cm (n={}) | void_culled={} gap_culled={} — "
        "p99 below the threshold = no false culls on bumpy interior ground; gap_culled = blades that "
        "hung past an upper edge over a LOWER terrace",
        floor_gap_thresh / U * 100.f, p50 / U * 100.f, p90 / U * 100.f, p99 / U * 100.f,
        pmax / U * 100.f, (int)interior_gaps.size(), floor_culled, gap_culled);
  }

  // ROUND#23 census (the "which prop leaked" diagnosis artifact).
  if (r23_dens_tris > 0) {
    std::vector<std::pair<std::string, u32>> top(r23_dens_by_tex.begin(), r23_dens_by_tex.end());
    std::stable_sort(top.begin(), top.end(),
                     [](const auto& a, const auto& b) { return a.second > b.second; });
    std::string tex;
    for (size_t i = 0; i < top.size() && i < 8; ++i) {
      tex += fmt::format(" {}={}", top[i].first, top[i].second);
    }
    lg::info("[recharged-grass] R23 footprint densify: tris={} add_pts={} occ_pts_total={} tex:{}",
             r23_dens_tris, r23_dens_pts, occ_pts.size(), tex);
    if (!r23_rock_spots.empty()) {
      constexpr float U = 4096.f;
      std::string spots;
      int shown = 0;
      for (const auto& [k, p] : r23_rock_spots) {
        if (shown++ >= 10) {
          break;
        }
        spots += fmt::format(" ({:.1f} {:.1f} {:.1f})", p[0] / U, p[1] / U, p[2] / U);
      }
      lg::info("[recharged-grass] R23 rock-face warp spots ({} cells):{}", r23_rock_spots.size(),
               spots);
    }
  }

  // POLISH#8 LOCATION-AWARE LIGHTING proof (scan-side). Grecharged-grass-precompute-mode: the bake TU
  // has no render state, so itimes_valid is ALWAYS false here — itimesValid prints 0 and bakedRef/meanf
  // reflect the 8-palette-average fallback (the only two numbers this restructure legitimately shifts;
  // gspare = rim_dist since POLISH#11 and per-instance light rides a separate u8 buffer, so geometry and
  // colour are unaffected).
  lg::info(
      "[recharged-grass] POLISH#8 LIGHT location-aware: itimesValid={} bakedRef(cur) {:.0f} -> meanf "
      "{:.2f}; per-tri bakedLuma min {:.0f} / mean {:.0f} / max {:.0f} / std {:.1f}; gain {:.2f} -> "
      "gspare spans ~[{:.2f}..{:.2f}] (shade darkens, lit brightens per-location).",
      itimes_valid ? 1 : 0, baked_ref, meanf, bl_min, bl_mean, bl_max, bl_std, LIGHT_GAIN,
      std::min(1.45f, std::max(0.30f, meanf + LIGHT_GAIN * (bl_min / 128.0f - meanf))),
      std::min(1.45f, std::max(0.30f, meanf + LIGHT_GAIN * (bl_max / 128.0f - meanf))));
  // POLISH#8 EDGE proof (scan-side).
  lg::info(
      "[recharged-grass] POLISH#8 EDGE upness {:.2f}: grass-tex tris dropped by upness {} ({:.0f} m2), "
      "of which {} moderate-slope (0.20..{:.2f}, edge lips); minKeptUpness {:.2f}.",
      GROUND_UPNESS, rej_upness, rej_upness_area, rej_up_moderate, GROUND_UPNESS, min_kept_upness);
  lg::info(
      "[recharged-grass] POLISH#11 PER-BLADE edge CLAMP: {} true-rim edges; {} degenerate rim slivers "
      "dropped (<{:.3f} m); {} near-rim blades horizontally CLAMPED to the rim by the shader (full "
      "height, no overflow, no bald fringe; interior blades untouched).",
      boundary_edges, edge_dropped, DROP_EPS / U, edge_clamped);
  lg::info(
      "[recharged-grass] ROUND#13 OVERHANG-LIP (transitive): {} lip tris base-excluded ({} TIE / {} "
      "tfrag, {:.0f} m2, upness < {:.2f} AND downhill chain = void); minPlacedUpness {:.2f}. Bases stay "
      "on the flat walkable top only -> grass ends exactly at the top rim on tfrag AND distant TIE "
      "platforms, none floating past the platform silhouette into the void.",
      lip_excluded, lip_excluded_tie, lip_excluded - lip_excluded_tie, lip_excluded_area, UPNESS_LIP_MAX,
      min_placed_upness);
  for (const auto& kv : unmatched_ground) {
    lg::info("[recharged-grass] UNMATCHED ground-ish texture '{}' ({} draws) — not placed",
             kv.first, kv.second);
  }

  // ---- Grecharged-grass-overhang4 (GBK5): SMOOTH VERTEX NORMALS over the retained soup.
  // Owner defect 2 (round 3): per-TRI comb state (flags bit4, from the FACE normal) flipped whole
  // triangles -> visible seams. Cure: give every tri three per-VERTEX smooth normals = the area-
  // weighted average of the adjacent face normals at each welded vertex. expand() interpolates them
  // barycentrically at the blade base, so the comb tilt and the droop drape are CONTINUOUS across
  // every tri border by construction (two adjacent blades on different tris can never jump state).
  // Self-contained weld (isolated from the edge-detect weld above); ny>=0-oriented like the face
  // normals; computed once on x86 at bake, shipped in the .grassbake, read verbatim on device.
  {
    constexpr float SWELD = 0.03f * U;  // same 3 cm canonical grid as the edge weld
    std::unordered_map<u64, std::vector<int>> scells;
    std::vector<std::array<float, 3>> sverts;
    std::vector<std::array<double, 3>> sacc;  // area-weighted normal accumulator per canonical vertex
    scells.reserve(bake_tris.size() * 3 + 16);
    sverts.reserve(bake_tris.size() * 2 + 16);
    auto sweld = [&](float x, float y, float z) -> int {
      s64 cx = (s64)std::floor(x / SWELD), cy = (s64)std::floor(y / SWELD), cz = (s64)std::floor(z / SWELD);
      const float tol2 = SWELD * SWELD;
      for (s64 dz = -1; dz <= 1; ++dz)
        for (s64 dy = -1; dy <= 1; ++dy)
          for (s64 dx = -1; dx <= 1; ++dx) {
            u64 k = (u64)((cx + dx) * 73856093LL) ^ (u64)((cy + dy) * 19349663LL) ^
                    (u64)((cz + dz) * 83492791LL);
            auto it = scells.find(k);
            if (it == scells.end()) continue;
            for (int vid : it->second) {
              float ddx = sverts[vid][0] - x, ddy = sverts[vid][1] - y, ddz = sverts[vid][2] - z;
              if (ddx * ddx + ddy * ddy + ddz * ddz <= tol2) return vid;
            }
          }
      int id = (int)sverts.size();
      sverts.push_back({x, y, z});
      u64 kk = (u64)(cx * 73856093LL) ^ (u64)(cy * 19349663LL) ^ (u64)(cz * 83492791LL);
      scells[kk].push_back(id);
      return id;
    };
    std::vector<std::array<int, 3>> btvids(bake_tris.size(), {-1, -1, -1});
    for (size_t i = 0; i < bake_tris.size(); ++i) {
      const BakeTri& t = bake_tris[i];
      if (t.flags & 4u) continue;  // dup fragment: no independent surface, skip from the average
      int a = sweld(t.p0[0], t.p0[1], t.p0[2]);
      int b = sweld(t.p0[0] + t.e1[0], t.p0[1] + t.e1[1], t.p0[2] + t.e1[2]);
      int c = sweld(t.p0[0] + t.e2[0], t.p0[1] + t.e2[1], t.p0[2] + t.e2[2]);
      btvids[i] = {a, b, c};
    }
    sacc.assign(sverts.size(), {0.0, 0.0, 0.0});
    for (size_t i = 0; i < bake_tris.size(); ++i) {
      if (btvids[i][0] < 0) continue;
      const BakeTri& t = bake_tris[i];
      double wgt = (double)t.area_m2;
      for (int k = 0; k < 3; ++k) {
        int vid = btvids[i][k];
        sacc[vid][0] += (double)t.nx * wgt;
        sacc[vid][1] += (double)t.ny * wgt;
        sacc[vid][2] += (double)t.nz * wgt;
      }
    }
    int smoothed = 0;
    for (size_t i = 0; i < bake_tris.size(); ++i) {
      BakeTri& t = bake_tris[i];
      float* vn[3] = {t.vn0, t.vn1, t.vn2};
      bool any = false;
      for (int k = 0; k < 3; ++k) {
        int vid = (btvids[i][0] < 0) ? -1 : btvids[i][k];
        double nx = t.nx, ny = t.ny, nz = t.nz;
        if (vid >= 0) { nx = sacc[vid][0]; ny = sacc[vid][1]; nz = sacc[vid][2]; }
        double L = std::sqrt(nx * nx + ny * ny + nz * nz);
        if (L < 1e-9) { vn[k][0] = t.nx; vn[k][1] = t.ny; vn[k][2] = t.nz; }
        else { vn[k][0] = (float)(nx / L); vn[k][1] = (float)(ny / L); vn[k][2] = (float)(nz / L); any = true; }
      }
      if (any) smoothed++;
    }
    lg::info("[recharged-grass] GOVERHANG4 smooth normals: {} canonical verts over {} tris "
             "({} tris smoothed) — per-blade barycentric normal kills per-tri comb/droop seams",
             (int)sverts.size(), (int)bake_tris.size(), smoothed);
  }

  // Grecharged-grass-overhang5: collect the walkable-top TRUE-RIM edges (drop-off lips) with their
  // outward horizontal direction + owning tri, for the rim-drape pass in expand(). Reuses the same
  // boundary-edge flags (r.bAB/bBC/bCA) the LOCKED edge clamp already computed above — purely additive,
  // no change to walkable placement, rim distances or the droop/comb tail.
  std::vector<RimDrapeSeg> rimdrape_segs;
  {
    const float min_e2 = (RIMDRAPE_MIN_EDGE_M * U) * (RIMDRAPE_MIN_EDGE_M * U);
    for (size_t tj = 0; tj < tris.size(); ++tj) {
      const auto& r = tris[tj];
      if (r.is_dup || r.is_lip) continue;
      float Ax = r.p0x, Ay = r.p0y, Az = r.p0z;
      float Bx = r.p0x + r.e1x, By = r.p0y + r.e1y, Bz = r.p0z + r.e1z;
      float Cx = r.p0x + r.e2x, Cy = r.p0y + r.e2y, Cz = r.p0z + r.e2z;
      auto add_rd = [&](float ax, float ay, float az, float bx, float by, float bz, float tx,
                        float tz) {
        float dex = bx - ax, dey = by - ay, dez = bz - az;
        if (dex * dex + dey * dey + dez * dez < min_e2) return;  // skip degenerate rim segments
        float mx = (ax + bx) * 0.5f, mz = (az + bz) * 0.5f;      // edge midpoint (XZ)
        float ox = mx - tx, oz = mz - tz;                        // away from interior (third) vertex
        float ol = std::sqrt(ox * ox + oz * oz);
        if (ol < 1e-4f) return;
        RimDrapeSeg s;
        s.ax = ax; s.ay = ay; s.az = az;
        s.bx = bx; s.by = by; s.bz = bz;
        s.ox = ox / ol; s.oz = oz / ol;
        s.gr = r.gr; s.gg = r.gg; s.gb = r.gb;
        s.tri = (u32)tj;
        rimdrape_segs.push_back(s);
      };
      if (r.bAB) add_rd(Ax, Ay, Az, Bx, By, Bz, Cx, Cz);
      if (r.bBC) add_rd(Bx, By, Bz, Cx, Cy, Cz, Ax, Az);
      if (r.bCA) add_rd(Cx, Cy, Cz, Ax, Ay, Az, Bx, Bz);
    }
  }
  lg::info("[recharged-grass] GOVERHANG5 rim-drape: {} true-rim edge segments collected (drape roots)",
           (int)rimdrape_segs.size());

  BakeData out;
  out.level_name = level_name;
  out.tfrag3_version = (u32)tfrag3::TFRAG3_VERSION;
  out.fr3_size = fr3_size;
  out.bake_density_pct = params.cand_density_pct;
  out.floor_gap_m = params.floor_gap_m;
  out.total_area_m2 = total_area_m2;
  out.tris = std::move(bake_tris);
  out.keep = std::move(keep_tbl);
  out.rim_q = std::move(rimq_tbl);
  out.droop = std::move(droop_tbl);  // Grecharged-grass-overhang
  out.droop_rims = std::move(droop_rim_segs);  // Grecharged-grass-overhang2 (GBK3)
  out.rimdrape = std::move(rimdrape_segs);      // Grecharged-grass-overhang5 (GBK6)
  out.stats.considered_draws = considered_draws;
  out.stats.tie_draws = tie_draws;
  out.stats.tris_kept = tris_kept;
  out.stats.giant_tris = giant_tris;
  out.stats.max_area = max_area;
  out.stats.occ_objpt_buckets = (int)occ_objpts;
  return out;
}

// ===========================================================================
// expand: replicates today's budget/order semantics exactly.
// ===========================================================================
ExpandResult expand(const BakeData& d, float density_slider_pct) {
  ExpandResult res;
  float dens_scale = std::min(2.5f, std::max(0.5f, density_slider_pct / 100.0f));
  int budget = (int)((float)MAX_INSTANCES * dens_scale);
  float density = D_TARGET;
  if (d.total_area_m2 > 1.0f && d.total_area_m2 * D_TARGET > BUDGET_SAFETY * (float)budget) {
    density = BUDGET_SAFETY * (float)budget / d.total_area_m2;
  }

  int scatter_kept = 0;
  int occ_culled = 0;
  res.instances.reserve(
      std::min<size_t>(budget, (size_t)(d.total_area_m2 * density) + 64));
  res.inst_tri.reserve(res.instances.capacity());

  // ===========================================================================
  // Grecharged-grass-overhang4 shared machinery. The comb and droop tail geometry, the shader that
  // draws it, and .autoport/goverhang4_placement.py (the objective tip-violation / seam / spacing
  // metrics) MUST agree bit-for-bit on the rest-pose blade shape, or the metrics measure fiction.
  // These helpers are the single C++ copy of that contract; the shader mirrors them and the Python
  // gen==4 branch mirrors them. Constants: SHADER_TILT_DEFAULT, NOFF_M, PLANE_CLEAR_M, COMB_*.
  // ===========================================================================
  const float COMB_TILT = SHADER_TILT_DEFAULT;  // comb up-axis lean; FIXED (not the live u_tilt A/B knob)
  const float NOFF_WU = NOFF_M * U;             // root offset along the smooth normal (world units)
  const float PLANE_CLEAR_WU = PLANE_CLEAR_M * U;
  const float MINLEN_WU = DROOP_MIN_LEN_M * U;

  // in-plane down-slope (steepest descent) of a unit normal; false if the face is flat (dsl undefined).
  auto dsl_of = [](const float n[3], float out[3]) -> bool {
    float h2 = 1.0f - n[1] * n[1];
    if (h2 < 1e-6f) return false;
    float r = std::sqrt(h2);
    out[0] = n[0] * n[1] / r;
    out[1] = (n[1] * n[1] - 1.0f) / r;
    out[2] = n[2] * n[1] / r;
    return true;
  };
  // barycentric SMOOTH normal at (wA:p0, wB:p0+e1, wC:p0+e2); continuous across every welded edge.
  auto bary_smooth = [](const BakeTri& t, float wA, float wB, float wC, float out[3]) {
    float nx = wA * t.vn0[0] + wB * t.vn1[0] + wC * t.vn2[0];
    float ny = wA * t.vn0[1] + wB * t.vn1[1] + wC * t.vn2[1];
    float nz = wA * t.vn0[2] + wB * t.vn1[2] + wC * t.vn2[2];
    float L = std::sqrt(nx * nx + ny * ny + nz * nz);
    if (L < 1e-9f) { out[0] = t.nx; out[1] = t.ny; out[2] = t.nz; }
    else { out[0] = nx / L; out[1] = ny / L; out[2] = nz / L; }
  };
  // nearest droop-rim segment (XZ, Y-windowed) — the per-blade "distance to the overhang edge" that
  // drives the CONTINUOUS comb near() weight (defect 2: no per-tri gate, so no seam).
  const float COMB_RIM_YWIN = 1.5f * U;
  auto nearest_droop_rim = [&](float px, float py, float pz, float& best2, float& rbx,
                               float& rbz) -> bool {
    best2 = 1e30f;
    bool found = false;
    for (const auto& s : d.droop_rims) {
      float abx = s.bx - s.ax, abz = s.bz - s.az;
      float denom = abx * abx + abz * abz;
      float t = denom > 1e-6f ? ((px - s.ax) * abx + (pz - s.az) * abz) / denom : 0.f;
      t = t < 0.f ? 0.f : (t > 1.f ? 1.f : t);
      float sy = s.ay + t * (s.by - s.ay);
      if (std::fabs(sy - py) > COMB_RIM_YWIN) continue;
      float sx = s.ax + t * abx, sz = s.az + t * abz;
      float dx = px - sx, dz = pz - sz;
      float d2 = dx * dx + dz * dz;
      if (d2 < best2) { best2 = d2; rbx = sx; rbz = sz; found = true; }
    }
    return found;
  };

  // Grecharged-grass-overhang6: XZ bucket hash over the TRUE-RIM edge segments (d.rimdrape). Zone-1
  // needs the nearest rim's OUTWARD direction (rim_q is only a distance); zone-2 needs the rim's Y to
  // measure how far below the lip a strip blade sits. Bucket 1.5 m, +-1 cell covers the 0.9 m lean band.
  const float RSEG_CELL = 1.5f * U;
  const float RSEG_YWIN = 1.5f * U;
  const float RSEG_INV = 1.0f / RSEG_CELL;
  std::unordered_map<u64, std::vector<u32>> rseg_grid;
  {
    // insert each rimdrape seg index into every cell its XZ AABB touches (mirror the tgrid insert style)
    rseg_grid.reserve(d.rimdrape.size() * 2 + 16);
    for (u32 si = 0; si < (u32)d.rimdrape.size(); ++si) {
      const RimDrapeSeg& s = d.rimdrape[si];
      float xmn = std::min(s.ax, s.bx), xmx = std::max(s.ax, s.bx);
      float zmn = std::min(s.az, s.bz), zmx = std::max(s.az, s.bz);
      s64 cx0 = (s64)std::floor(xmn * RSEG_INV), cx1 = (s64)std::floor(xmx * RSEG_INV);
      s64 cz0 = (s64)std::floor(zmn * RSEG_INV), cz1 = (s64)std::floor(zmx * RSEG_INV);
      for (s64 cx = cx0; cx <= cx1; ++cx)
        for (s64 cz = cz0; cz <= cz1; ++cz)
          rseg_grid[((u64)(u32)cx << 32) ^ (u64)(u32)cz].push_back(si);
    }
  }
  // nearest true-rim seg to (px,py,pz): closest point on any segment within ywin (Y) and the 3x3 cell
  // neighbourhood. Returns false if none; else writes the seg's outward dir, the Y of the closest point
  // on the segment, and the squared XZ distance to it.
  auto nearest_rim_seg = [&](float px, float py, float pz, float ywin, float& ox, float& oz,
                             float& rim_y, float& d2out) -> bool {
    float best = 1e30f;
    bool found = false;
    s64 gx = (s64)std::floor(px * RSEG_INV), gz = (s64)std::floor(pz * RSEG_INV);
    for (s64 dz = -1; dz <= 1; ++dz) {
      for (s64 dx = -1; dx <= 1; ++dx) {
        auto it = rseg_grid.find(((u64)(u32)(gx + dx) << 32) ^ (u64)(u32)(gz + dz));
        if (it == rseg_grid.end()) continue;
        for (u32 si : it->second) {
          const RimDrapeSeg& s = d.rimdrape[si];
          float abx = s.bx - s.ax, abz = s.bz - s.az;
          float denom = abx * abx + abz * abz;
          float t = denom > 1e-6f ? ((px - s.ax) * abx + (pz - s.az) * abz) / denom : 0.f;
          t = t < 0.f ? 0.f : (t > 1.f ? 1.f : t);
          float sy = s.ay + t * (s.by - s.ay);
          if (std::fabs(sy - py) > ywin) continue;
          float sx = s.ax + t * abx, sz = s.az + t * abz;
          float ddx = px - sx, ddz = pz - sz;
          float d2 = ddx * ddx + ddz * ddz;
          if (d2 < best) {
            best = d2;
            ox = s.ox;
            oz = s.oz;
            rim_y = sy;
            found = true;
          }
        }
      }
    }
    d2out = best;
    return found;
  };

  // XZ tri grid over ALL bake tris (cell 2 m), matching goverhang4_placement.py build_tri_grid — the
  // neighbourhood the tail blades' rest tips are plane-tested against (defect 1: clip-through).
  const float GCELL = 2.0f * U;
  auto gkey = [](s64 cx, s64 cz) -> u64 { return ((u64)(u32)cx << 32) ^ (u64)(u32)cz; };
  std::unordered_map<u64, std::vector<u32>> tgrid;
  tgrid.reserve(d.tris.size() * 2 + 16);
  for (u32 ti = 0; ti < (u32)d.tris.size(); ++ti) {
    const BakeTri& t = d.tris[ti];
    float xs0 = t.p0[0], xs1 = t.p0[0] + t.e1[0], xs2 = t.p0[0] + t.e2[0];
    float zs0 = t.p0[2], zs1 = t.p0[2] + t.e1[2], zs2 = t.p0[2] + t.e2[2];
    float xmn = std::min(xs0, std::min(xs1, xs2)), xmx = std::max(xs0, std::max(xs1, xs2));
    float zmn = std::min(zs0, std::min(zs1, zs2)), zmx = std::max(zs0, std::max(zs1, zs2));
    s64 cx0 = (s64)std::floor(xmn / GCELL), cx1 = (s64)std::floor(xmx / GCELL);
    s64 cz0 = (s64)std::floor(zmn / GCELL), cz1 = (s64)std::floor(zmx / GCELL);
    for (s64 cx = cx0; cx <= cx1; ++cx)
      for (s64 cz = cz0; cz <= cz1; ++cz) tgrid[gkey(cx, cz)].push_back(ti);
  }
  // barycentric inside-test (2x2 normal equations), same tolerances as the Python analyzer.
  auto bary_inside = [](const float proj[3], const BakeTri& t) -> bool {
    float dx = proj[0] - t.p0[0], dy = proj[1] - t.p0[1], dz = proj[2] - t.p0[2];
    float a11 = t.e1[0] * t.e1[0] + t.e1[1] * t.e1[1] + t.e1[2] * t.e1[2];
    float a12 = t.e1[0] * t.e2[0] + t.e1[1] * t.e2[1] + t.e1[2] * t.e2[2];
    float a22 = t.e2[0] * t.e2[0] + t.e2[1] * t.e2[1] + t.e2[2] * t.e2[2];
    float b1 = t.e1[0] * dx + t.e1[1] * dy + t.e1[2] * dz;
    float b2 = t.e2[0] * dx + t.e2[1] * dy + t.e2[2] * dz;
    float det = a11 * a22 - a12 * a12;
    if (std::fabs(det) < 1e-9f) return false;
    float a = (b1 * a22 - b2 * a12) / det;
    float b = (a11 * b2 - a12 * b1) / det;
    return a >= -0.02f && b >= -0.02f && a + b <= 1.04f;
  };
  // does a rest tip poke behind any NEARBY tri surface (past PLANE_CLEAR, projection inside the tri)?
  auto tip_violates = [&](const float base[3], const float tip[3], u32 host) -> bool {
    s64 cx = (s64)std::floor(tip[0] / GCELL), cz = (s64)std::floor(tip[2] / GCELL);
    for (s64 dx = -1; dx <= 1; ++dx)
      for (s64 dz = -1; dz <= 1; ++dz) {
        auto it = tgrid.find(gkey(cx + dx, cz + dz));
        if (it == tgrid.end()) continue;
        for (u32 ti : it->second) {
          if (ti == host) continue;
          const BakeTri& t = d.tris[ti];
          float sd_base = (base[0] - t.p0[0]) * t.nx + (base[1] - t.p0[1]) * t.ny +
                          (base[2] - t.p0[2]) * t.nz;
          if (sd_base < -PLANE_CLEAR_WU) continue;  // base already behind this plane: not our clip
          float sd_tip = (tip[0] - t.p0[0]) * t.nx + (tip[1] - t.p0[1]) * t.ny +
                         (tip[2] - t.p0[2]) * t.nz;
          if (sd_tip >= -PLANE_CLEAR_WU) continue;  // tip in front of the plane: fine
          float proj[3] = {tip[0] - t.nx * sd_tip, tip[1] - t.ny * sd_tip, tip[2] - t.nz * sd_tip};
          if (bary_inside(proj, t)) return true;
        }
      }
    return false;
  };
  // rest tip of a COMB replacement blade (mirrors goverhang4_placement.py compute_tip gen4/comb + the
  // shader). up_axis = (n.x*TILT, 1, n.z*TILT); axis = up_axis*(1-w) + dsl*w; root offset n*NOFF*w;
  // static curve fwdv*curve*h*(1-0.6w); half-space clamp to the base's tangent plane.
  auto tip_comb = [&](const float base[3], const float n[3], float w, float yaw, float curve, float h,
                      float tip[3]) {
    float dv[3];
    bool ok = dsl_of(n, dv);
    float ax0, ax1, ax2;
    if (ok) {
      ax0 = (n[0] * COMB_TILT) * (1.0f - w) + dv[0] * w;
      ax1 = (1.0f) * (1.0f - w) + dv[1] * w;
      ax2 = (n[2] * COMB_TILT) * (1.0f - w) + dv[2] * w;
    } else {
      ax0 = n[0] * COMB_TILT; ax1 = 1.0f; ax2 = n[2] * COMB_TILT;
    }
    float fs = std::sin(yaw), fc = std::cos(yaw);
    float noff = NOFF_WU * w;
    float br0 = base[0] + n[0] * noff, br1 = base[1] + n[1] * noff, br2 = base[2] + n[2] * noff;
    float fwd = curve * h * (1.0f - 0.6f * w);
    float t0 = br0 + ax0 * h + fs * fwd;
    float t1 = br1 + ax1 * h;
    float t2 = br2 + ax2 * h + fc * fwd;
    float db = (t0 - base[0]) * n[0] + (t1 - base[1]) * n[1] + (t2 - base[2]) * n[2];
    if (db < 0.f) { tip[0] = t0 - n[0] * db; tip[1] = t1 - n[1] * db; tip[2] = t2 - n[2] * db; }
    else { tip[0] = t0; tip[1] = t1; tip[2] = t2; }
  };
  // rest tip of a DROOP blade (mirrors compute_tip gen4/droop + the shader): base + n*NOFF + dsl*h,
  // half-space clamped. Pure down-slope drape, no world-up term, no below-plane sag.
  auto tip_droop = [&](const float base[3], const float n[3], float h, float tip[3]) -> bool {
    float dv[3];
    if (!dsl_of(n, dv)) { tip[0] = base[0]; tip[1] = base[1]; tip[2] = base[2]; return false; }
    float t0 = base[0] + n[0] * NOFF_WU + dv[0] * h;
    float t1 = base[1] + n[1] * NOFF_WU + dv[1] * h;
    float t2 = base[2] + n[2] * NOFF_WU + dv[2] * h;
    float db = (t0 - base[0]) * n[0] + (t1 - base[1]) * n[1] + (t2 - base[2]) * n[2];
    if (db < 0.f) { tip[0] = t0 - n[0] * db; tip[1] = t1 - n[1] * db; tip[2] = t2 - n[2] * db; }
    else { tip[0] = t0; tip[1] = t1; tip[2] = t2; }
    return true;
  };
  // shrink a tail blade's length until its rest tip clears every nearby tri plane (or drop it). The
  // metric recomputes the tip from the stored length, so a length that passes here -> 0 violations.
  auto cap_comb = [&](const float base[3], u32 host, const float n[3], float w, float yaw, float curve,
                      float h_nat) -> float {
    float h = h_nat, tip[3];
    for (int it = 0; it < 16; ++it) {
      tip_comb(base, n, w, yaw, curve, h, tip);
      if (!tip_violates(base, tip, host)) return h;
      h *= 0.8f;
      if (h < MINLEN_WU) break;
    }
    return -1.0f;
  };
  auto cap_droop = [&](const float base[3], u32 host, const float n[3], float h_nat) -> float {
    float h = h_nat, tip[3];
    for (int it = 0; it < 16; ++it) {
      if (!tip_droop(base, n, h, tip)) return h_nat;  // flat face: dsl undefined, no cap
      if (!tip_violates(base, tip, host)) return h;
      h *= 0.8f;
      if (h < MINLEN_WU) break;
    }
    return -1.0f;
  };

  // Comb replacement candidates collected in the walkable pass, emitted as TAIL twins after droop.
  struct CombCand {
    u32 orig, tri;
    float px, py, pz, h, yaw, tint, curve, phase, gr, gg, gb, nx, ny, nz, w;
  };
  std::vector<CombCand> comb_list;
  // Grecharged-grass-overhang6 ZONE-1 lean twins collected in the walkable pass, emitted after the
  // comb twins (same collapse/replace tail delivery). ox/oz = nearest true-rim outward dir; k = lean.
  struct LeanCand {
    u32 orig, tri;
    float px, py, pz, h, yaw, tint, curve, phase, gr, gg, gb, ox, oz, k;
  };
  std::vector<LeanCand> lean_list;
  int dbg_trans_blades = 0, dbg_trans_tilt0 = 0;  // ROUND6 curl-band census (zone-2 coverage proof)

  for (size_t tj = 0; tj < d.tris.size(); ++tj) {
    if (scatter_kept >= budget) break;
    const BakeTri& tri = d.tris[tj];
    if (tri.flags & (2u | 4u)) continue;  // lip | dup (cand_count is 0 for these anyway)
    float fn = tri.area_m2 * density;
    int n = (int)fn;
    if (hash_f(tri.seed + 99u) < (fn - (float)n)) {
      n += 1;
    }
    if ((u32)n > tri.cand_count) n = (int)tri.cand_count;  // safety (slider <= bake density)
    for (int i = 0; i < n; ++i) {
      if (scatter_kept >= budget) break;
      u8 k = d.keep[tri.cand_base + (u64)i];
      if (!(k & 1)) continue;
      scatter_kept++;
      if (!(k & 2)) {
        occ_culled++;
        continue;
      }
      u32 sd = tri.seed + (u32)i * 3266489917u;
      float r1 = hash_f(sd + 1u);
      float r2 = hash_f(sd + 2u);
      if (r1 + r2 > 1.0f) {
        r1 = 1.0f - r1;
        r2 = 1.0f - r2;
      }
      float bx = tri.p0[0] + r1 * tri.e1[0] + r2 * tri.e2[0];
      float by = tri.p0[1] + r1 * tri.e1[1] + r2 * tri.e2[1];
      float bz = tri.p0[2] + r1 * tri.e1[2] + r2 * tri.e2[2];

      GrassInstance gi;
      gi.px = bx;
      gi.py = by;
      gi.pz = bz;
      gi.h = BASE_H * (0.50f + 1.55f * hash_f(sd + 3u));   // OWNER POLISH#3: wider SIZE variation
      gi.tint = hash_f(sd + 5u);
      gi.curve = 0.10f + 0.75f * hash_f(sd + 6u);          // wider CURVATURE variation
      gi.phase = hash_f(sd + 7u);
      gi.yaw = hash_f(sd + 4u) * 6.2831853f;               // fully random yaw
      gi.gr = tri.gr; gi.gg = tri.gg; gi.gb = tri.gb;      // POLISH#4 ground colour
      gi.gspare = rim_decode(d.rim_q[tri.cand_base + (u64)i]);  // = rim_dist (world units)
      gi.nx = tri.nx; gi.ny = tri.ny; gi.nz = tri.nz; gi.nspare = 0.f;
      // Grecharged-grass-overhang4: PER-BLADE CONTINUOUS comb tag (replaces the round-3 per-tri bit4
      // flip that flopped whole triangles = the seams). The weight is w = tilt(smooth-normal.y) *
      // near(distance to the nearest DROOP rim) — both factors continuous by construction (the smooth
      // normal is barycentric-interpolated from welded per-vertex normals; the rim distance is to a
      // segment set), so two adjacent blades can never jump state and NO threshold is a line on the
      // mesh. The tagged original keeps its stock bytes except nspare=-(1+w): unread when OFF (stock
      // else-branch, OFF == stock), and a signal to COLLAPSE when ON while its TAIL replacement twin
      // (carrying the smooth normal + w) takes over. gspare (rim_dist) < COMB_NEAR1 is a cheap exact
      // pre-filter: a blade farther than that from ANY rim is farther than COMB_NEAR1 from a droop rim
      // too, so near()=0 and it can't be combed.
      // Grecharged-grass-overhang6: the outer band widened to cover both the comb pre-filter and the
      // zone-1 lean band; ALSO taken unconditionally for blades on TRANSITION (bit4) tris — see below.
      // ZONE-2 CORRECTION (training census: 1896 of 1897 droop faces carry the native-alpha hang
      // texture): the owner's "mesh qui descend avec l'herbe verte plate" is NOT the droop set — it is
      // the TRANSITION curl band (bit4 walkable tra-grass tris, 546 m2 in training). The old comb
      // (tilt * droop-rim-nearness < 1.3 m) reached only ~450 of its ~63k blades, leaving upright grass
      // standing on the descending strip in every prior round. Round 6: a blade ON a bit4 tri is combed
      // by its PURE TILT ramp ("en suivant EXACTEMENT cette partie" — the mesh's own steepness IS the
      // gradient), no proximity gate; elsewhere the round-4 tilt*near rule is unchanged.
      bool tagged = false;  // did this original get a negative nspare (comb OR lean)?
      bool on_trans = (tri.flags & 16u) != 0u;
      if (on_trans) dbg_trans_blades++;
      if (on_trans || gi.gspare < std::max(COMB_NEAR1_M, LEAN_BAND_M) * U) {
        if (on_trans || gi.gspare < COMB_NEAR1_M * U) {
          float wA = 1.0f - r1 - r2, wB = r1, wC = r2;
          float sn[3];
          bary_smooth(tri, wA, wB, wC, sn);
          float tilt = (TRANS_UPNESS_HI - sn[1]) / (TRANS_UPNESS_HI - TRANS_UPNESS_LO);
          tilt = tilt < 0.f ? 0.f : (tilt > 1.f ? 1.f : tilt);
          if (on_trans && tilt <= 0.f) dbg_trans_tilt0++;
          if (tilt > 0.f) {
            float w = on_trans ? tilt : 0.f;  // zone-2: the curl mesh combs by its own steepness
            if (gi.gspare < COMB_NEAR1_M * U) {
              float best2, rbx, rbz;
              if (nearest_droop_rim(bx, by, bz, best2, rbx, rbz)) {
                float dR = std::sqrt(best2);
                float nearw = (COMB_NEAR1_M * U - dR) / ((COMB_NEAR1_M - COMB_NEAR0_M) * U);
                nearw = nearw < 0.f ? 0.f : (nearw > 1.f ? 1.f : nearw);
                if (tilt * nearw > w) w = tilt * nearw;  // round-4 rule still applies off the curl
              }
            }
            if (w > COMB_W_MIN && (int)comb_list.size() < COMB_MAX) {
              gi.nspare = -(1.0f + w);
              tagged = true;
              CombCand cc;
              cc.orig = (u32)res.instances.size();
              cc.tri = (u32)tj;
              cc.px = bx; cc.py = by; cc.pz = bz; cc.h = gi.h;
              cc.yaw = gi.yaw; cc.tint = gi.tint; cc.curve = gi.curve; cc.phase = gi.phase;
              cc.gr = tri.gr; cc.gg = tri.gg; cc.gb = tri.gb;
              cc.nx = sn[0]; cc.ny = sn[1]; cc.nz = sn[2]; cc.w = w;
              comb_list.push_back(cc);
              res.comb_tagged++;
            }
          }
        }
        // ZONE 1 (owner round-6 verbatim): every walkable blade near the grass boundary — ANY true rim,
        // not just droop rims — progressively leans toward the void. Tag the original (collapse when ON)
        // and queue a tail twin carrying the nearest rim's outward dir + the lean weight k (1 at the rim).
        if (!tagged && gi.gspare < LEAN_BAND_M * U) {
          float ox, oz, ry, d2;
          if (nearest_rim_seg(bx, by, bz, RSEG_YWIN, ox, oz, ry, d2) &&
              (int)lean_list.size() < LEAN_MAX) {
            float lean_k = 1.0f - gi.gspare / (LEAN_BAND_M * U);
            if (lean_k > LEAN_K_MIN) {
              gi.nspare = -(1.0f + lean_k);
              lean_list.push_back({(u32)res.instances.size(), (u32)tj, bx, by, bz, gi.h, gi.yaw,
                                   gi.tint, gi.curve, gi.phase, gi.gr, gi.gg, gi.gb, ox, oz, lean_k});
              res.lean_tagged++;
            }
          }
        }
      }
      res.instances.push_back(gi);
      res.inst_tri.push_back((u32)tj);
    }
  }
  res.scatter_kept = scatter_kept;
  res.occ_culled = occ_culled;

  // 2D exit distance from a point along the FACE down-slope: the tri's own texture extent, so a blade
  // never overshoots the painted fringe (the neighbour-plane cap handles clip-through). Hoisted up so
  // BOTH the zone-2 strip pass and the zone-3 fall pass can length-cap against it (round-2 lesson).
  auto exit_dist = [&](const BakeTri& tri, float px, float py, float pz) -> float {
    float n_y = tri.ny;
    float horiz2 = 1.0f - n_y * n_y;
    if (horiz2 < 1e-6f) return 0.f;
    float inv = 1.0f / std::sqrt(horiz2);
    float ux = tri.nx * n_y * inv, uy = (n_y * n_y - 1.0f) * inv, uz = tri.nz * n_y * inv;
    float vx = n_y * uz - tri.nz * uy, vy = tri.nz * ux - tri.nx * uz, vz = tri.nx * uy - n_y * ux;
    float Sx[3], Wx[3];
    float P[3][3] = {{tri.p0[0], tri.p0[1], tri.p0[2]},
                     {tri.p0[0] + tri.e1[0], tri.p0[1] + tri.e1[1], tri.p0[2] + tri.e1[2]},
                     {tri.p0[0] + tri.e2[0], tri.p0[1] + tri.e2[1], tri.p0[2] + tri.e2[2]}};
    for (int vi = 0; vi < 3; ++vi) {
      float dx = P[vi][0] - P[0][0], dy = P[vi][1] - P[0][1], dz = P[vi][2] - P[0][2];
      Sx[vi] = dx * ux + dy * uy + dz * uz;
      Wx[vi] = dx * vx + dy * vy + dz * vz;
    }
    float dx = px - P[0][0], dy = py - P[0][1], dz = pz - P[0][2];
    float ps = dx * ux + dy * uy + dz * uz;
    float pw = dx * vx + dy * vy + dz * vz;
    float best = 1e30f;
    int eidx[3][2] = {{0, 1}, {1, 2}, {2, 0}};
    for (int e = 0; e < 3; ++e) {
      int i0 = eidx[e][0], i1 = eidx[e][1];
      float es = Sx[i1] - Sx[i0], ew = Wx[i1] - Wx[i0];
      if (std::fabs(ew) < 1e-6f) continue;
      float f = (pw - Wx[i0]) / ew;
      if (f < -0.001f || f > 1.001f) continue;
      float t = (Sx[i0] + f * es) - ps;
      if (t > 1.0f && t < best) best = t;
    }
    return best < 1e29f ? best : 0.f;
  };

  int plane_capped = 0, plane_dropped = 0;

  // ---- ZONE 2 (owner round-6): blades ON the flat-green descending mesh, following it EXACTLY with
  // increasing lean ("un peu de mesh qui descend toujours avec l'herbe verte plate... des brins de
  // plus en plus penchés dessus, en suivant EXACTEMENT cette partie"). Training census truth: that
  // mesh is (a) the TRANSITION curl band — bit4 walkable tra-grass tris whose bases the LOCKED
  // FLOORGAP/FLOORBELOW stack rightly culls (the very reason the upright lawn "stops" at the
  // boundary), so coverage must come from this TAIL scatter, never from the keep tables — plus
  // (b) the rare non-hang droop faces below the rim. Emitted as 5+w comb-class instances: the proven
  // round-4 shader math (axis = up*(1-w) + downslope*w, half-space clamped) IS the increasing lean.
  // Weight: on the curl, w = the PURE smooth-normal tilt ramp (near-upright where it meets the lawn,
  // fully bent where the mesh steepens — the mesh drives the gradient); on below-rim strip faces the
  // depth ramp floors it at Z2_K1 (zone-1's end) so the gradient never steps back.
  res.droop_start = (int)res.instances.size();
  int z2_placed = 0;
  {
    struct Z2Face {
      u32 tri;
      float ox, oz;   // outward hint for the smooth-normal flip (curl: its own downhill normal)
      bool curl;      // bit4 transition tri (pure-tilt weight) vs below-rim strip face (depth floor)
    };
    std::vector<Z2Face> z2_faces;
    for (const auto& de : d.droop) {
      if (de.tri >= d.tris.size()) continue;
      if (d.tris[de.tri].flags & 32u) continue;  // native-alpha hang face -> zone 3, not here
      z2_faces.push_back({de.tri, de.ox, de.oz, false});
    }
    for (u32 tj = 0; tj < (u32)d.tris.size(); ++tj) {
      const BakeTri& bt = d.tris[tj];
      if (!(bt.flags & 16u)) continue;           // transition curl band only
      z2_faces.push_back({tj, bt.nx, bt.nz, true});  // ny>=0 normal's horizontal part = downhill
    }
    // Budget pre-pass over the whole zone-2 face set.
    float total_area = 0.f;
    for (const auto& zf : z2_faces) total_area += d.tris[zf.tri].area_m2;
    float adens = Z2_AREA_DENS * dens_scale;
    if (total_area > 1.0f && total_area * adens > 0.9f * (float)Z2_MAX) {
      adens = 0.9f * (float)Z2_MAX / total_area;
    }
    for (const auto& zf : z2_faces) {
      if (z2_placed >= Z2_MAX) break;
      const BakeTri& tri = d.tris[zf.tri];
      float fn = tri.area_m2 * adens;
      int n = (int)fn;
      u32 tseed = tri.seed ^ 0xD4009u;  // unchanged salt, keeps determinism style
      if (hash_f(tseed + 99u) < (fn - (float)n)) n += 1;
      for (int i = 0; i < n; ++i) {
        if (z2_placed >= Z2_MAX) break;
        u32 sd = tseed + (u32)i * 2654435761u;
        float r1d = hash_f(sd + 1u);
        float r2d = hash_f(sd + 2u);
        if (r1d + r2d > 1.0f) { r1d = 1.0f - r1d; r2d = 1.0f - r2d; }
        float bx = tri.p0[0] + r1d * tri.e1[0] + r2d * tri.e2[0];
        float by = tri.p0[1] + r1d * tri.e1[1] + r2d * tri.e2[1];
        float bz = tri.p0[2] + r1d * tri.e1[2] + r2d * tri.e2[2];
        // barycentric SMOOTH normal, oriented OUTWARD (fringe faces can flip inward under ny>=0).
        float sn[3];
        bary_smooth(tri, 1.0f - r1d - r2d, r1d, r2d, sn);
        float ol2 = zf.ox * zf.ox + zf.oz * zf.oz;
        if (ol2 > 1e-8f && sn[0] * zf.ox + sn[2] * zf.oz < 0.f) { sn[0] = -sn[0]; sn[2] = -sn[2]; }
        float tw = (TRANS_UPNESS_HI - sn[1]) / (TRANS_UPNESS_HI - TRANS_UPNESS_LO);
        tw = tw < 0.f ? 0.f : (tw > 1.f ? 1.f : tw);
        float w;
        if (zf.curl) {
          w = tw;  // the curl mesh's own steepness IS the gradient (upright top -> bent bottom)
          if (w <= COMB_W_MIN) continue;  // flat upper curl: the stock lawn already covers it
        } else {
          float dw;
          float ox2, oz2, ry, d2;
          if (nearest_rim_seg(bx, by, bz, 2.5f * U, ox2, oz2, ry, d2)) {
            float depth_m = (ry - by) / U;  // strip drops below the lip -> positive
            dw = Z2_K1 + (1.0f - Z2_K1) * std::clamp(depth_m / Z2_DEPTH_FULL_M, 0.0f, 1.0f);
          } else {
            dw = Z2_K1;
          }
          w = std::max(tw, dw);
        }
        if (w > 0.999f) w = 0.999f;  // keep nspare = 5+w < 6 (inside the 4.5..6.5 shader band)
        float species = BASE_H * (0.50f + 1.55f * hash_f(sd + 3u));
        float ex = exit_dist(tri, bx, by, bz);
        float len = species;
        if (ex > 0.f && ex * DROOP_EXIT_SAFETY < len) len = ex * DROOP_EXIT_SAFETY;
        if (len < MINLEN_WU) continue;
        float base[3] = {bx, by, bz};
        float yaw = std::atan2(sn[0], sn[2]) + (hash_f(sd + 4u) - 0.5f) * 0.6f;
        float curve = 0.10f + 0.75f * hash_f(sd + 6u);
        float capped = cap_comb(base, zf.tri, sn, w, yaw, curve, len);
        if (capped < 0.f) { plane_dropped++; continue; }
        if (capped < len - 1e-3f) plane_capped++;
        GrassInstance gi;
        gi.px = bx; gi.py = by; gi.pz = bz;
        gi.h = capped;
        gi.yaw = yaw;
        gi.tint = hash_f(sd + 5u);
        gi.curve = curve;
        gi.phase = hash_f(sd + 7u);
        gi.gr = tri.gr; gi.gg = tri.gg; gi.gb = tri.gb;
        gi.gspare = 1.0e9f;  // NO_RIM: the strip blade lies along the sub-lip mesh past the rim
        gi.nx = sn[0]; gi.ny = sn[1]; gi.nz = sn[2];  // SMOOTH NORMAL (shader derives dsl + clamp plane)
        gi.nspare = 5.0f + w;  // COMB-class marker (shader band 4.5..6.5), w = nspare - 5
        res.instances.push_back(gi);
        res.inst_tri.push_back(zf.tri);
        z2_placed++;
      }
    }
  }
  res.z2_count = z2_placed;

  // ---- Grecharged-grass-overhang4: COMB REPLACEMENT twins (the continuous upright->droop transition).
  // The round-2/3 transition-twin class (a straight horizontal chord through the curved lip = the
  // clip-through) is DELETED. Each tagged walkable original (nspare<0, collected above) is COLLAPSED by
  // the shader when the toggle is ON and replaced here by a tail twin carrying the SMOOTH NORMAL and w.
  // The twin grows along axis = up*(1-w) + down-slope*w with a n*NOFF*w root lift, plane-capped and
  // half-space-clamped so it lies ON the surface across the whole transition (defect 1). If a twin
  // cannot clear its neighbourhood it is dropped and its original UN-TAGGED, so the toggle-ON field
  // never holes (the un-tagged original just draws the stock rim-tapered stub).
  res.trans_start = (int)res.instances.size();
  int comb_pairs = 0;
  for (const auto& cc : comb_list) {
    float base[3] = {cc.px, cc.py, cc.pz};
    float n[3] = {cc.nx, cc.ny, cc.nz};
    float capped = cap_comb(base, cc.tri, n, cc.w, cc.yaw, cc.curve, cc.h);
    if (capped < 0.f) {
      res.instances[cc.orig].nspare = 0.f;  // un-tag: draws the stock stub when ON, no hole
      plane_dropped++;
      continue;
    }
    if (capped < cc.h - 1e-3f) plane_capped++;
    GrassInstance gi;
    gi.px = cc.px; gi.py = cc.py; gi.pz = cc.pz;
    gi.h = capped;
    gi.yaw = cc.yaw;
    gi.tint = cc.tint;
    gi.curve = cc.curve;
    gi.phase = cc.phase;
    gi.gr = cc.gr; gi.gg = cc.gg; gi.gb = cc.gb;
    gi.gspare = 1.0e9f;  // NO_RIM: a combed blade lies along the surface past the rim's XZ projection
    gi.nx = cc.nx; gi.ny = cc.ny; gi.nz = cc.nz;  // SMOOTH NORMAL
    gi.nspare = 5.0f + cc.w;  // COMB REPLACEMENT marker (shader: nspare > 4.5), w = nspare - 5
    res.instances.push_back(gi);
    res.inst_tri.push_back(cc.tri);
    comb_pairs++;
  }
  res.comb_pairs = comb_pairs;

  // ---- ZONE 1 twins (owner round-6): the walkable boundary lean. Same collapse/replace delivery as
  // the comb class (OFF == stock: tag + tail both unread/undrawn). Plane-capped with the SHADER's
  // rest-pose axis so a leaned blade at an inner corner cannot poke a neighbouring wall.
  int lean_twins = 0;
  for (const auto& lc : lean_list) {
    float kk = lc.k * LEAN1_MAX;
    float axx = lc.ox * kk, axy = 1.0f - kk, axz = lc.oz * kk;   // shader: up*(1-kk) + outw*kk
    // iterative shrink against tgrid planes (mirror cap_droop's loop): rest tip = base + axis*h
    float h = lc.h;
    bool ok = true;
    float base[3] = {lc.px, lc.py, lc.pz};
    for (int it = 0; it < 16; ++it) {
      float tip[3] = {lc.px + axx * h, lc.py + axy * h, lc.pz + axz * h};
      if (!tip_violates(base, tip, lc.tri)) break;
      h *= 0.8f;
      if (h < MINLEN_WU) { ok = false; break; }
    }
    if (!ok) { res.instances[lc.orig].nspare = 0.f; plane_dropped++; continue; }
    if (h < lc.h - 1e-3f) plane_capped++;
    GrassInstance gi;
    gi.px = lc.px; gi.py = lc.py; gi.pz = lc.pz;
    gi.h = h; gi.yaw = lc.yaw; gi.tint = lc.tint; gi.curve = lc.curve; gi.phase = lc.phase;
    gi.gr = lc.gr; gi.gg = lc.gg; gi.gb = lc.gb;
    gi.gspare = 1.0e9f;                       // NO_RIM: the lean past the lip is the intended look
    gi.nx = lc.ox; gi.ny = 0.0f; gi.nz = lc.oz;  // unit outward horizontal dir
    gi.nspare = 3.0f + lc.k;                  // ZONE-1 marker (shader band 2.5..4.5), k = nspare-3
    res.instances.push_back(gi);
    res.inst_tri.push_back(lc.tri);
    lean_twins++;
  }
  res.lean_twins = lean_twins;

  // ---- ZONE 3 (owner round-6): >= 2 LAYERS of grass falling fully DOWNWARD over the faces carrying
  // the native overhang ALPHA texture (is_hang, flags bit5), entirely covering it at near LOD (the
  // tfrag/TIE fringe-fade hides the painted strip near; it restores at distance as these blades fade
  // out — crossfade, no double-up). Two layers root at different normal offsets (shader) for real
  // THICKNESS; per-layer densities/seeds decorrelated; inner layer slightly darkened for depth.
  int z3_placed = 0;
  for (int layer = 0; layer < Z3_LAYERS; ++layer) {
    // Budget pre-pass: hang-subset area * Z3_AREA_DENS * Z3_LAYERS clamped to 0.9*Z3_MAX (per layer).
    float total_area = 0.f;
    for (const auto& de : d.droop) {
      if (de.tri >= d.tris.size()) continue;
      if (!(d.tris[de.tri].flags & 32u)) continue;  // native-alpha hang faces only
      total_area += d.tris[de.tri].area_m2;
    }
    float adens = Z3_AREA_DENS * dens_scale;
    if (total_area > 1.0f && total_area * adens * (float)Z3_LAYERS > 0.9f * (float)Z3_MAX) {
      adens = 0.9f * (float)Z3_MAX / (total_area * (float)Z3_LAYERS);
    }
    for (const auto& de : d.droop) {
      if (z3_placed >= Z3_MAX) break;
      if (de.tri >= d.tris.size()) continue;
      const BakeTri& tri = d.tris[de.tri];
      if (!(tri.flags & 32u)) continue;  // native-alpha hang faces only
      float fn = tri.area_m2 * adens;
      int n = (int)fn;
      u32 tseed = (tri.seed ^ 0xFA110u) + (u32)layer * 0x9E3779B9u;  // per-layer decorrelated seed
      if (hash_f(tseed + 99u) < (fn - (float)n)) n += 1;
      for (int i = 0; i < n; ++i) {
        if (z3_placed >= Z3_MAX) break;
        u32 sd = tseed + (u32)i * 2654435761u;
        float r1d = hash_f(sd + 1u);
        float r2d = hash_f(sd + 2u);
        if (r1d + r2d > 1.0f) { r1d = 1.0f - r1d; r2d = 1.0f - r2d; }
        float bx = tri.p0[0] + r1d * tri.e1[0] + r2d * tri.e2[0];
        float by = tri.p0[1] + r1d * tri.e1[1] + r2d * tri.e2[1];
        float bz = tri.p0[2] + r1d * tri.e1[2] + r2d * tri.e2[2];
        float sn[3];
        bary_smooth(tri, 1.0f - r1d - r2d, r1d, r2d, sn);
        if (sn[0] * de.ox + sn[2] * de.oz < 0.f) { sn[0] = -sn[0]; sn[2] = -sn[2]; }
        float species = BASE_H * Z3_LEN_MUL * (0.70f + 0.60f * hash_f(sd + 3u));
        float ex = exit_dist(tri, bx, by, bz);
        float len = species;
        if (ex > 0.f && ex * 1.05f < len) len = ex * 1.05f;  // covers strip, never descends far past it
        if (len < MINLEN_WU) continue;
        // fall cap: rest tip = base + n*loff + (0,-len,0); iterative 0.8 shrink like zone 1.
        float loff = (0.02f + 0.055f * (float)layer) * U;
        float base[3] = {bx, by, bz};
        float h = len;
        bool ok = true;
        for (int it = 0; it < 16; ++it) {
          float tip[3] = {bx + sn[0] * loff, by + sn[1] * loff - h, bz + sn[2] * loff};
          if (!tip_violates(base, tip, de.tri)) break;
          h *= 0.8f;
          if (h < MINLEN_WU) { ok = false; break; }
        }
        if (!ok) { plane_dropped++; continue; }
        if (h < len - 1e-3f) plane_capped++;
        GrassInstance gi;
        gi.px = bx; gi.py = by; gi.pz = bz;
        gi.h = h;
        gi.yaw = std::atan2(sn[0], sn[2]) + (hash_f(sd + 4u) - 0.5f) * 0.6f;
        gi.tint = hash_f(sd + 5u);
        gi.curve = 0.10f + 0.75f * hash_f(sd + 6u);
        gi.phase = hash_f(sd + 7u);
        if (layer == 0) { gi.gr = tri.gr * 0.82f; gi.gg = tri.gg * 0.82f; gi.gb = tri.gb * 0.82f; }
        else { gi.gr = tri.gr; gi.gg = tri.gg; gi.gb = tri.gb; }
        gi.gspare = 1.0e9f;  // NO_RIM: the fall is the intended overhang
        gi.nx = sn[0]; gi.ny = sn[1]; gi.nz = sn[2];  // SMOOTH NORMAL (outward-oriented)
        gi.nspare = 7.0f + 0.5f * (float)layer;  // ZONE-3 FALL marker (shader nsp > 6.5), layer=(nsp-7)*2
        res.instances.push_back(gi);
        res.inst_tri.push_back(de.tri);
        z3_placed++;
      }
    }
  }
  res.z3_count = z3_placed;

  res.plane_capped = plane_capped;
  res.plane_dropped = plane_dropped;
  lg::info("[recharged-grass] GOVERHANG6 zones: lean_tagged={} lean_twins={} (band {:.2f}m) z2_strip={} "
           "z3_fall={} (layers={}) comb_repl={} curl_blades={} curl_tilt0={} plane_capped={} "
           "plane_dropped={}",
           res.lean_tagged, res.lean_twins, LEAN_BAND_M, res.z2_count, res.z3_count, Z3_LAYERS,
           res.comb_pairs, dbg_trans_blades, dbg_trans_tilt0, plane_capped, plane_dropped);
  return res;
}

// ===========================================================================
// Serialization (flat buffer + zstd).
// ===========================================================================
namespace {
constexpr u32 GBK_MAGIC = 0x314B4247;   // 'GBK1'
// Grecharged-grass-overhang: v2 appends the droop section (fringe tris ride in tris[] with flags
// bit3). A v1 bake fails the version check below -> the runtime's LIVE-scan fallback handles it.
// Grecharged-grass-overhang2: v3 appends the droop-RIM segment section (the progressive
// upright->droop transition needs a rim DIRECTION; rim_q only has a distance). Same fallback rule.
// Grecharged-grass-overhang3: v4 = SEMANTIC bump (flags bit4 transition tris; droop instances now carry the in-plane down-slope in nx/ny/nz and a tri-capped length in h). Same byte layout as v3.
// Grecharged-grass-overhang4: v5 APPENDS three smooth vertex normals per tri (BakeTri.vn0/vn1/vn2)
// AND re-defines the instance semantics — droop carries the SMOOTH NORMAL (not the down-slope) in
// nx/ny/nz, comb is delivered as TAIL REPLACEMENT twins (nspare=5+w). A v4 bake fails the check below.
// Grecharged-grass-overhang5: v6 APPENDS the RIM-DRAPE section (walkable-top drop-off lip edges +
// outward dir + owning tri) that expand() turns into the lip-hanging drape (nspare=3). A v5 bake fails
// the version check -> the runtime's LIVE-scan fallback rebuilds it (scan_level also fills rimdrape).
// Grecharged-grass-overhang6: v7: tri flags bit5 (is_hang) + 3-zone expand semantics (round 6); layout
// identical to v6 (flags/rimdrape sections already serialized — the rimdrape edge table now feeds
// zone-1's outward-lean directions instead of the deleted rim-drape blades).
constexpr u32 GBK_FORMAT_VERSION = 7;

template <typename T>
void put(std::vector<u8>& buf, const T& v) {
  const u8* p = reinterpret_cast<const u8*>(&v);
  buf.insert(buf.end(), p, p + sizeof(T));
}
void put_bytes(std::vector<u8>& buf, const void* data, size_t n) {
  const u8* p = reinterpret_cast<const u8*>(data);
  buf.insert(buf.end(), p, p + n);
}

template <typename T>
bool get(const std::vector<u8>& buf, size_t& off, T& v) {
  if (off + sizeof(T) > buf.size()) return false;
  std::memcpy(&v, buf.data() + off, sizeof(T));
  off += sizeof(T);
  return true;
}
bool get_bytes(const std::vector<u8>& buf, size_t& off, void* data, size_t n) {
  if (off + n > buf.size()) return false;
  std::memcpy(data, buf.data() + off, n);
  off += n;
  return true;
}
}  // namespace

bool save_bake(const BakeData& d, const std::string& path) {
  std::vector<u8> buf;
  put<u32>(buf, GBK_MAGIC);
  put<u32>(buf, GBK_FORMAT_VERSION);
  put<u32>(buf, d.tfrag3_version);
  char lname[32] = {0};
  std::strncpy(lname, d.level_name.c_str(), sizeof(lname) - 1);
  put_bytes(buf, lname, sizeof(lname));
  put<u64>(buf, d.fr3_size);
  put<float>(buf, d.bake_density_pct);
  put<float>(buf, d.floor_gap_m);
  put<float>(buf, d.total_area_m2);
  put<u32>(buf, (u32)d.tris.size());
  put<u64>(buf, (u64)d.keep.size());
  put<u32>(buf, (u32)d.stats.considered_draws);
  put<u32>(buf, (u32)d.stats.tie_draws);
  put<u32>(buf, (u32)d.stats.tris_kept);
  put<u32>(buf, (u32)d.stats.giant_tris);
  put<float>(buf, d.stats.max_area);
  put<u32>(buf, (u32)d.stats.occ_objpt_buckets);

  // tris field-by-field (no struct padding).
  for (const auto& t : d.tris) {
    put_bytes(buf, t.p0, sizeof(t.p0));
    put_bytes(buf, t.e1, sizeof(t.e1));
    put_bytes(buf, t.e2, sizeof(t.e2));
    put<u32>(buf, t.seed);
    put<float>(buf, t.area_m2);
    put<float>(buf, t.gr);
    put<float>(buf, t.gg);
    put<float>(buf, t.gb);
    put<float>(buf, t.nx);
    put<float>(buf, t.ny);
    put<float>(buf, t.nz);
    put_bytes(buf, t.pal, sizeof(t.pal));
    put<u32>(buf, t.cand_count);
    put<u64>(buf, t.cand_base);
    put<u32>(buf, t.flags);
    put_bytes(buf, t.vn0, sizeof(t.vn0));  // GBK5 smooth vertex normals
    put_bytes(buf, t.vn1, sizeof(t.vn1));
    put_bytes(buf, t.vn2, sizeof(t.vn2));
  }
  put_bytes(buf, d.keep.data(), d.keep.size() * sizeof(u8));
  put_bytes(buf, d.rim_q.data(), d.rim_q.size() * sizeof(u16));

  // Grecharged-grass-overhang (GBK2): droop section.
  put<u32>(buf, (u32)d.droop.size());
  for (const auto& de : d.droop) {
    put<u32>(buf, de.tri);
    put<float>(buf, de.ox);
    put<float>(buf, de.oz);
  }

  // Grecharged-grass-overhang2 (GBK3): droop-rim segment section.
  put<u32>(buf, (u32)d.droop_rims.size());
  for (const auto& s : d.droop_rims) {
    put<float>(buf, s.ax);
    put<float>(buf, s.ay);
    put<float>(buf, s.az);
    put<float>(buf, s.bx);
    put<float>(buf, s.by);
    put<float>(buf, s.bz);
  }

  // Grecharged-grass-overhang5 (GBK6): rim-drape lip-edge section.
  put<u32>(buf, (u32)d.rimdrape.size());
  for (const auto& s : d.rimdrape) {
    put<float>(buf, s.ax);
    put<float>(buf, s.ay);
    put<float>(buf, s.az);
    put<float>(buf, s.bx);
    put<float>(buf, s.by);
    put<float>(buf, s.bz);
    put<float>(buf, s.ox);
    put<float>(buf, s.oz);
    put<float>(buf, s.gr);
    put<float>(buf, s.gg);
    put<float>(buf, s.gb);
    put<u32>(buf, s.tri);
  }

  std::vector<u8> comp = compression::compress_zstd(buf.data(), buf.size());
  std::ofstream f(path, std::ios::binary | std::ios::trunc);
  if (!f) {
    lg::warn("[recharged-grass] save_bake: cannot open '{}' for write", path);
    return false;
  }
  f.write(reinterpret_cast<const char*>(comp.data()), (std::streamsize)comp.size());
  return (bool)f;
}

bool load_bake(BakeData& d, const std::string& path) {
  std::ifstream f(path, std::ios::binary | std::ios::ate);
  if (!f) {
    lg::warn("[recharged-grass] load_bake: '{}' missing", path);
    return false;
  }
  std::streamsize sz = f.tellg();
  if (sz <= 0) {
    lg::warn("[recharged-grass] load_bake: '{}' empty", path);
    return false;
  }
  f.seekg(0, std::ios::beg);
  std::vector<u8> comp((size_t)sz);
  if (!f.read(reinterpret_cast<char*>(comp.data()), sz)) {
    lg::warn("[recharged-grass] load_bake: read failed '{}'", path);
    return false;
  }
  std::vector<u8> buf;
  try {
    buf = compression::decompress_zstd(comp.data(), comp.size());
  } catch (const std::exception& e) {
    lg::warn("[recharged-grass] load_bake: decompress failed '{}': {}", path, e.what());
    return false;
  }

  size_t off = 0;
  u32 magic = 0, fmt = 0, tfv = 0;
  if (!get(buf, off, magic) || magic != GBK_MAGIC) {
    lg::warn("[recharged-grass] load_bake: bad magic in '{}'", path);
    return false;
  }
  if (!get(buf, off, fmt) || fmt != GBK_FORMAT_VERSION) {
    lg::warn("[recharged-grass] load_bake: format_version mismatch in '{}'", path);
    return false;
  }
  if (!get(buf, off, tfv) || tfv != (u32)tfrag3::TFRAG3_VERSION) {
    lg::warn("[recharged-grass] load_bake: tfrag3_version mismatch in '{}' ({} != {})", path, tfv,
             (u32)tfrag3::TFRAG3_VERSION);
    return false;
  }
  BakeData tmp;
  tmp.tfrag3_version = tfv;
  char lname[32] = {0};
  if (!get_bytes(buf, off, lname, sizeof(lname))) return false;
  lname[31] = 0;
  tmp.level_name = std::string(lname);
  u32 ntris = 0, sc = 0, td = 0, tk = 0, gt = 0, ob = 0;
  u64 ncand = 0;
  if (!get(buf, off, tmp.fr3_size) || !get(buf, off, tmp.bake_density_pct) ||
      !get(buf, off, tmp.floor_gap_m) || !get(buf, off, tmp.total_area_m2) ||
      !get(buf, off, ntris) || !get(buf, off, ncand) || !get(buf, off, sc) || !get(buf, off, td) ||
      !get(buf, off, tk) || !get(buf, off, gt) || !get(buf, off, tmp.stats.max_area) ||
      !get(buf, off, ob)) {
    lg::warn("[recharged-grass] load_bake: truncated header in '{}'", path);
    return false;
  }
  tmp.stats.considered_draws = (int)sc;
  tmp.stats.tie_draws = (int)td;
  tmp.stats.tris_kept = (int)tk;
  tmp.stats.giant_tris = (int)gt;
  tmp.stats.occ_objpt_buckets = (int)ob;

  tmp.tris.resize(ntris);
  for (u32 i = 0; i < ntris; ++i) {
    BakeTri& t = tmp.tris[i];
    if (!get_bytes(buf, off, t.p0, sizeof(t.p0)) || !get_bytes(buf, off, t.e1, sizeof(t.e1)) ||
        !get_bytes(buf, off, t.e2, sizeof(t.e2)) || !get(buf, off, t.seed) ||
        !get(buf, off, t.area_m2) || !get(buf, off, t.gr) || !get(buf, off, t.gg) ||
        !get(buf, off, t.gb) || !get(buf, off, t.nx) || !get(buf, off, t.ny) ||
        !get(buf, off, t.nz) || !get_bytes(buf, off, t.pal, sizeof(t.pal)) ||
        !get(buf, off, t.cand_count) || !get(buf, off, t.cand_base) || !get(buf, off, t.flags) ||
        !get_bytes(buf, off, t.vn0, sizeof(t.vn0)) || !get_bytes(buf, off, t.vn1, sizeof(t.vn1)) ||
        !get_bytes(buf, off, t.vn2, sizeof(t.vn2))) {  // GBK5 smooth vertex normals
      lg::warn("[recharged-grass] load_bake: truncated tris in '{}'", path);
      return false;
    }
  }
  tmp.keep.resize(ncand);
  if (ncand && !get_bytes(buf, off, tmp.keep.data(), ncand * sizeof(u8))) {
    lg::warn("[recharged-grass] load_bake: truncated keep[] in '{}'", path);
    return false;
  }
  tmp.rim_q.resize(ncand);
  if (ncand && !get_bytes(buf, off, tmp.rim_q.data(), ncand * sizeof(u16))) {
    lg::warn("[recharged-grass] load_bake: truncated rim_q[] in '{}'", path);
    return false;
  }

  // Grecharged-grass-overhang (GBK2): droop section.
  u32 ndroop = 0;
  if (!get(buf, off, ndroop)) {
    lg::warn("[recharged-grass] load_bake: truncated droop count in '{}'", path);
    return false;
  }
  tmp.droop.resize(ndroop);
  for (u32 i = 0; i < ndroop; ++i) {
    DroopTri& de = tmp.droop[i];
    if (!get(buf, off, de.tri) || !get(buf, off, de.ox) || !get(buf, off, de.oz)) {
      lg::warn("[recharged-grass] load_bake: truncated droop[] in '{}'", path);
      return false;
    }
    if (de.tri >= ntris) {
      lg::warn("[recharged-grass] load_bake: droop tri index out of range in '{}'", path);
      return false;
    }
  }

  // Grecharged-grass-overhang2 (GBK3): droop-rim segment section.
  u32 nrims = 0;
  if (!get(buf, off, nrims)) {
    lg::warn("[recharged-grass] load_bake: truncated droop-rim count in '{}'", path);
    return false;
  }
  tmp.droop_rims.resize(nrims);
  for (u32 i = 0; i < nrims; ++i) {
    DroopRimSeg& s = tmp.droop_rims[i];
    if (!get(buf, off, s.ax) || !get(buf, off, s.ay) || !get(buf, off, s.az) ||
        !get(buf, off, s.bx) || !get(buf, off, s.by) || !get(buf, off, s.bz)) {
      lg::warn("[recharged-grass] load_bake: truncated droop_rims[] in '{}'", path);
      return false;
    }
  }

  // Grecharged-grass-overhang5 (GBK6): rim-drape lip-edge section.
  u32 nrd = 0;
  if (!get(buf, off, nrd)) {
    lg::warn("[recharged-grass] load_bake: truncated rim-drape count in '{}'", path);
    return false;
  }
  tmp.rimdrape.resize(nrd);
  for (u32 i = 0; i < nrd; ++i) {
    RimDrapeSeg& s = tmp.rimdrape[i];
    if (!get(buf, off, s.ax) || !get(buf, off, s.ay) || !get(buf, off, s.az) ||
        !get(buf, off, s.bx) || !get(buf, off, s.by) || !get(buf, off, s.bz) ||
        !get(buf, off, s.ox) || !get(buf, off, s.oz) || !get(buf, off, s.gr) ||
        !get(buf, off, s.gg) || !get(buf, off, s.gb) || !get(buf, off, s.tri)) {
      lg::warn("[recharged-grass] load_bake: truncated rimdrape[] in '{}'", path);
      return false;
    }
    if (s.tri >= ntris) {
      lg::warn("[recharged-grass] load_bake: rimdrape tri index out of range in '{}'", path);
      return false;
    }
  }

  d = std::move(tmp);
  return true;
}

}  // namespace grass_bake
