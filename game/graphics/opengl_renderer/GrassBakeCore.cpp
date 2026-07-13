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
    bt.flags = (r.is_tie ? 1u : 0u) | (r.is_lip ? 2u : 0u) | (r.is_dup ? 4u : 0u);
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
      res.instances.push_back(gi);
      res.inst_tri.push_back((u32)tj);
    }
  }
  res.scatter_kept = scatter_kept;
  res.occ_culled = occ_culled;
  return res;
}

// ===========================================================================
// Serialization (flat buffer + zstd).
// ===========================================================================
namespace {
constexpr u32 GBK_MAGIC = 0x314B4247;   // 'GBK1'
constexpr u32 GBK_FORMAT_VERSION = 1;

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
  }
  put_bytes(buf, d.keep.data(), d.keep.size() * sizeof(u8));
  put_bytes(buf, d.rim_q.data(), d.rim_q.size() * sizeof(u16));

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
        !get(buf, off, t.cand_count) || !get(buf, off, t.cand_base) || !get(buf, off, t.flags)) {
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

  d = std::move(tmp);
  return true;
}

}  // namespace grass_bake
