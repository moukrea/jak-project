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
    bool is_hang_b;                // ROUND 11: that texture is bch-leafyground-hang-2x1 (bit6) — the
                                   // zone-3 cards sample the MATCHING native texels per face
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

  // ====================== grass-path-transitions : LES SOLS NUS POSES ========================
  // Un chemin ou une zone de terre n'est ni de l'herbe ni un objet : c'est une DALLE. On la
  // reconnait par DEUX sources independantes — la geometrie de son draw de rendu (faces plates,
  // draw peu epais, empreinte assez large) et le materiau de collision SOUS elle
  // (`sand|dirt|gravel|stone`). La geometrie se mesure ici, pendant le balayage des draws ; le
  // materiau ne peut l'etre qu'apres la construction de l'index de collision, plus bas. Les deux
  // verdicts sont conserves SEPAREMENT : un draw que seule la geometrie retient est un DESACCORD
  // publie, jamais un recouvrement silencieux.
  struct BareTri {
    float x0, y0, z0, x1, y1, z1, x2, y2, z2;
  };
  struct BareDraw {
    std::string tex;
    bool is_tie = false;
    size_t occ_first = 0, occ_last = 0;  // sa plage dans occ_pts (TIE seulement)
    size_t tri_first = 0, tri_last = 0;  // sa plage dans bare_tris
    float miny = 1e30f, maxy = -1e30f;
    double area_xz = 0.0;    // m^2 projetes en XZ
    double area_full = 0.0;  // m^2 de surface
    double area_up = 0.0;    // ... ponderes par l'upness de chaque face
    u32 f_up = 0, f_bare = 0, f_flush = 0, f_lifted = 0, f_nofloor = 0;  // seconde source
    double area_flush = 0.0;  // aire XZ des faces qui AFFLEURENT un plancher nu
    const char* reason = "-";
    bool geom_ok = false, mat_ok = false, keep_as_bare = false;
  };
  std::vector<BareTri> bare_tris;
  std::vector<BareDraw> bare_draws;

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
      // ROUND 11: WHICH strip texture — the zone-3 textured cards must sample the same texels the
      // face below them natively shows (grassfringe vs the short leafyground fringe).
      bool draw_is_hang_b = (tname == "bch-leafyground-hang-2x1");
      if (!matched) {
        if (looks_groundish(tname)) {
          unmatched_ground[tname]++;
        }
        // grass-path-transitions : ou commence la plage de points d'occultation de CE draw. Si le
        // draw se revele etre un sol nu pose, c'est cette plage exacte qui sortira de
        // l'occultation binaire — et elle seule.
        const size_t occ_first_of_draw = occ_pts.size();
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
        // ---- SOURCE 1 : LA GEOMETRIE DE RENDU. Un feuillage n'est jamais un chemin (POLISH#8) ;
        // on garde les faces qui REGARDENT VERS LE HAUT, on mesure l'upness sur TOUTES les faces
        // (un rocher a un dessus plat mais des flancs, sa moyenne le trahit) et on borne
        // l'epaisseur du draw. Les triangles retenus sont l'EMPREINTE : la distance sera prise sur
        // eux, exactement, jamais sur un nuage de points echantillonne — un pas de 0,35 m posait un
        // plancher de 0,25 m sur toute distance mesuree, et les faces de plus de 6 m n'etaient pas
        // echantillonnees du tout.
        if (!is_foliage(tname)) {
          BareDraw bd;
          bd.tex = tname;
          bd.is_tie = is_tie;
          bd.occ_first = occ_first_of_draw;
          bd.occ_last = occ_pts.size();
          bd.tri_first = bare_tris.size();
          u32 bb = draw.unpacked.idx_of_first_idx_in_full_buffer;
          u32 bl = 0;
          for (const auto& g : draw.vis_groups) {
            bl += g.num_inds;
          }
          if (bl > 2 && bb < idx.size()) {
            if (bb + bl > idx.size()) {
              bl = (u32)(idx.size() - bb);
            }
            for (u32 k = bb + 2; k < bb + bl; ++k) {
              u32 i0 = idx[k - 2], i1 = idx[k - 1], i2 = idx[k];
              if (i0 == UINT32_MAX || i1 == UINT32_MAX || i2 == UINT32_MAX) {
                continue;
              }
              if (i0 >= verts.size() || i1 >= verts.size() || i2 >= verts.size()) {
                continue;
              }
              if (i0 == i1 || i1 == i2 || i0 == i2) {
                continue;  // couture de strip degeneree
              }
              const float ax = verts[i0].x, ay = verts[i0].y, az = verts[i0].z;
              const float e1x = verts[i1].x - ax, e1y = verts[i1].y - ay, e1z = verts[i1].z - az;
              const float e2x = verts[i2].x - ax, e2y = verts[i2].y - ay, e2z = verts[i2].z - az;
              const float cx = e1y * e2z - e1z * e2y;
              const float cy = e1z * e2x - e1x * e2z;
              const float cz = e1x * e2y - e1y * e2x;
              const float nl = std::sqrt(cx * cx + cy * cy + cz * cz);
              if (nl <= 1e-3f) {
                continue;
              }
              const float up = std::fabs(cy) / nl;
              const double a_full = (double)(0.5f * nl) / (4096.0 * 4096.0);
              bd.area_full += a_full;
              bd.area_up += a_full * (double)up;
              bd.miny = std::min(bd.miny, std::min(ay, std::min(verts[i1].y, verts[i2].y)));
              bd.maxy = std::max(bd.maxy, std::max(ay, std::max(verts[i1].y, verts[i2].y)));
              if (up < TRANS_OVL_UPNESS) {
                continue;  // un flanc ne fait pas partie de l'empreinte
              }
              bd.area_xz += (double)(0.5f * std::fabs(cy)) / (4096.0 * 4096.0);
              bare_tris.push_back({ax, ay, az, verts[i1].x, verts[i1].y, verts[i1].z, verts[i2].x,
                                   verts[i2].y, verts[i2].z});
            }
          }
          bd.tri_last = bare_tris.size();
          // LE SEUL FILTRE DE DRAW EST L'AIRE. « Plat » et « bas » etaient des filtres de draw :
          // un chemin qui ondule sur trois metres etait rejete en bloc, et 1 604 points sur
          // 10 757 959 sortaient de l'occultation. La platitude se juge FACE PAR FACE, plus bas,
          // contre le plancher de collision — une dalle affleure le sien, le dessus d'un rocher est
          // souleve. L'aire, elle, reste un filtre de draw : c'est ce qui separe une allee d'un
          // caillou, et elle est publiee pour chaque draw ecarte.
          bd.geom_ok = bd.tri_last > bd.tri_first && bd.area_xz >= (double)TRANS_OVL_MINAREA_M2;
          if (!bd.geom_ok) {
            bd.reason = bd.tri_last > bd.tri_first ? "aire" : "sansface";
            bare_tris.resize(bd.tri_first);  // rien a garder : on ne paie pas la memoire
            bd.tri_last = bd.tri_first;
          }
          bare_draws.push_back(std::move(bd));
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
            fr.is_hang_b = draw_is_hang_b;  // ROUND 11: which strip texture (card texel source)
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
        r.is_hang_b = draw_is_hang_b;  // ROUND 11: which strip texture (bit6, card texel source)
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
  
    u32 mat;  // grass-path-transitions : pat-material (bits 6..11) — la SECONDE source
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
      r.mat = (a.pat >> 6) & 0x3fu;  // grass-path-transitions : lu, pas devine
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

  std::string out_bare_tex_top = "-", out_bare_rej_top = "-", out_bare_mat_top = "-";
  // ================ grass-path-transitions : LA SECONDE SOURCE, PUIS L'EMPREINTE ==============
  // SOURCE 2 : le materiau de collision SOUS chaque face du draw. `floor_mat` rend le materiau du
  // sol marchable le plus HAUT a la verticale d'un point, dans une fenetre de TRANS_OVL_YWIN_M.
  // Un draw n'est un sol nu pose que si les DEUX sources le disent ; le desaccord est compte.
  auto floor_mat = [&](float px, float py, float pz, float* out_y) -> s32 {
    if (floor_tris.empty()) {
      return -1;
    }
    s64 gx = (s64)std::floor(px * floor_inv), gz = (s64)std::floor(pz * floor_inv);
    auto it = floor_grid.find(((u64)(u32)(s32)gx << 32) | (u32)(s32)gz);
    if (it == floor_grid.end()) {
      return -1;
    }
    float bestY = -1e30f;
    s32 best = -1;
    const float ywin = TRANS_OVL_YWIN_M * U;
    for (int ti : it->second) {
      const auto& r = floor_tris[ti];
      if (px < r.minx || px > r.maxx || pz < r.minz || pz > r.maxz) {
        continue;
      }
      const float qx = px - r.p0x, qz = pz - r.p0z;
      const float d20 = qx * r.e1x + qz * r.e1z;
      const float d21 = qx * r.e2x + qz * r.e2z;
      const float u = (r.d11 * d20 - r.d01 * d21) * r.inv_denom;
      const float v = (r.d00 * d21 - r.d01 * d20) * r.inv_denom;
      if (u < -0.02f || v < -0.02f || u + v > 1.02f) {
        continue;
      }
      const float fy = r.p0y + u * r.e1y + v * r.e2y;
      if (std::fabs(fy - py) > ywin) {
        continue;
      }
      if (fy > bestY) {
        bestY = fy;
        best = (s32)r.mat;
      }
    }
    if (out_y) {
      *out_y = bestY;
    }
    return best;
  };

  size_t trans_bare_geom = 0, trans_bare_mat = 0, trans_bare_both = 0, trans_bare_disagree = 0;
  size_t f_up_tot = 0, f_bare_tot = 0, f_flush_tot = 0, f_lift_tot = 0, f_nofl_tot = 0;
  std::unordered_map<u32, u64> bare_mat_hist;  // materiau -> faces plates non-herbe au-dessus
  std::vector<char> occ_is_bare(occ_pts.size(), 0);
  std::vector<u32> bare_keep_tris;  // index dans bare_tris des empreintes RETENUES
  std::vector<char> bare_tri_keep(bare_tris.size(), 0);
  for (auto& bd : bare_draws) {
    if (bd.geom_ok) {
      trans_bare_geom++;
    }
    // SOURCE 2, FACE PAR FACE. Une face plate non-herbe est une EMPREINTE DE SOL NU quand le
    // plancher de collision sous elle porte un materiau nu ET qu'elle AFFLEURE ce plancher. Le
    // dessus d'un rocher porte bien `stone`, mais il est SOULEVE au-dessus du sol : c'est ce qui
    // separe une dalle de chemin d'un objet pose, et c'est ce qui garde
    // `recharged-grass-object-clip` intact.
    for (size_t t = bd.tri_first; t < bd.tri_last; ++t) {
      const auto& bt = bare_tris[t];
      const float cxp = (bt.x0 + bt.x1 + bt.x2) * (1.f / 3.f);
      const float cyp = (bt.y0 + bt.y1 + bt.y2) * (1.f / 3.f);
      const float czp = (bt.z0 + bt.z1 + bt.z2) * (1.f / 3.f);
      float fy = 0.f;
      const s32 m = floor_mat(cxp, cyp, czp, &fy);
      bd.f_up++;
      if (m < 0) {
        bd.f_nofloor++;
        continue;
      }
      bare_mat_hist[(u32)m]++;
      if (!pat_material_is_bare((u32)m)) {
        continue;
      }
      bd.f_bare++;
      if (std::fabs(cyp - fy) > TRANS_OVL_LIFT_M * U) {
        bd.f_lifted++;
        continue;
      }
      bd.f_flush++;
      bare_tri_keep[t] = 1;
      // aire XZ de cette face (recalculee : on n'a garde que ses sommets)
      const float e1x = bt.x1 - bt.x0, e1y = bt.y1 - bt.y0, e1z = bt.z1 - bt.z0;
      const float e2x = bt.x2 - bt.x0, e2y = bt.y2 - bt.y0, e2z = bt.z2 - bt.z0;
      const float cy2 = e1z * e2x - e1x * e2z;
      bd.area_flush += (double)(0.5f * std::fabs(cy2)) / (4096.0 * 4096.0);
    }
    f_up_tot += bd.f_up;
    f_bare_tot += bd.f_bare;
    f_flush_tot += bd.f_flush;
    f_lift_tot += bd.f_lifted;
    f_nofl_tot += bd.f_nofloor;
    bd.mat_ok = bd.area_flush >= (double)TRANS_OVL_MINAREA_M2;
    if (bd.mat_ok) {
      trans_bare_mat++;
    }
    if (bd.geom_ok != bd.mat_ok) {
      trans_bare_disagree++;
      if (!bd.mat_ok && bd.geom_ok) {
        bd.reason = bd.f_bare == 0 ? "materiau" : (bd.f_lifted > bd.f_flush ? "souleve" : "aireplate");
      }
    }
    bd.keep_as_bare = bd.geom_ok && bd.mat_ok;
    if (!bd.keep_as_bare) {
      continue;
    }
    trans_bare_both++;
    for (size_t t = bd.tri_first; t < bd.tri_last; ++t) {
      if (bare_tri_keep[t]) {
        bare_keep_tris.push_back((u32)t);
      }
    }
    // CE DRAW SORT DE L'OCCULTATION BINAIRE. C'est LA correction : ses points ne tuent plus un
    // brin a 0,45 m a la ronde. `recharged-grass-object-clip` ne bouge pas d'un pouce pour tous
    // les autres — un rocher, une caisse, la borne de warp gardent leurs points et leur rayon.
    for (size_t q = bd.occ_first; q < bd.occ_last && q < occ_is_bare.size(); ++q) {
      occ_is_bare[q] = 1;
    }
  }
  // CE QUI EST RETENU, ET CE QUI EST ECARTE, NOMME ET CHIFFRE. Une liste vide s'ecrit "-" :
  // `publish_text` garderait sinon la valeur de la course precedente.
  {
    auto top = [](std::vector<std::pair<std::string, double>>& v, size_t n) -> std::string {
      std::sort(v.begin(), v.end(),
                [](const std::pair<std::string, double>& a,
                   const std::pair<std::string, double>& b) { return a.second > b.second; });
      std::string out;
      for (size_t i = 0; i < v.size() && i < n; ++i) {
        out += (out.empty() ? "" : ",") + v[i].first + ":" +
               std::to_string((long long)std::lround(v[i].second * 100.0));
      }
      return out.empty() ? "-" : out;
    };
    std::vector<std::pair<std::string, double>> kept, rej;
    for (const auto& bd : bare_draws) {
      if (bd.keep_as_bare) {
        kept.push_back({bd.tex, bd.area_flush});
      } else if (bd.area_xz > 0.0) {
        rej.push_back({bd.tex + ":" + bd.reason, bd.area_xz});
      }
    }
    out_bare_tex_top = top(kept, 8);
    out_bare_rej_top = top(rej, 8);
    std::vector<std::pair<std::string, double>> mats;
    for (const auto& kv : bare_mat_hist) {
      const char* nm = pat_material_name(kv.first);
      mats.push_back({nm ? std::string(nm) : ("mat" + std::to_string(kv.first)), (double)kv.second});
    }
    for (auto& m : mats) {
      m.second *= 0.01;  // `top` multiplie par 100 : ici la valeur est un COMPTE de faces, pas une aire
    }
    out_bare_mat_top = top(mats, 8);
  }

  // L'EMPREINTE, PRETE POUR LA REQUETE. Distance XZ EXACTE au triangle (pas a un nuage de points),
  // avec le Y du point le plus proche pour la fenetre verticale.
  struct BareFx {
    float x0, y0, z0, e1x, e1y, e1z, e2x, e2y, e2z;
    float d00, d01, d11, inv_denom;
    float minx, maxx, minz, maxz;
  };
  std::vector<BareFx> bare_fx;
  bare_fx.reserve(bare_keep_tris.size());
  const float BARE_CELL = 2.0f * U;
  const float bare_inv = 1.0f / BARE_CELL;
  const float bare_pad = TRANS_QUERY_M * U;
  std::unordered_map<s64, std::vector<u32>> bare_grid;
  for (u32 ti : bare_keep_tris) {
    const auto& bt = bare_tris[ti];
    BareFx r;
    r.x0 = bt.x0; r.y0 = bt.y0; r.z0 = bt.z0;
    r.e1x = bt.x1 - bt.x0; r.e1y = bt.y1 - bt.y0; r.e1z = bt.z1 - bt.z0;
    r.e2x = bt.x2 - bt.x0; r.e2y = bt.y2 - bt.y0; r.e2z = bt.z2 - bt.z0;
    r.d00 = r.e1x * r.e1x + r.e1z * r.e1z;
    r.d01 = r.e1x * r.e2x + r.e1z * r.e2z;
    r.d11 = r.e2x * r.e2x + r.e2z * r.e2z;
    const float den = r.d00 * r.d11 - r.d01 * r.d01;
    if (std::fabs(den) < 1e-6f) {
      continue;  // sliver vu de dessus : il n'apporte aucune empreinte
    }
    r.inv_denom = 1.0f / den;
    r.minx = std::min(bt.x0, std::min(bt.x1, bt.x2)) - bare_pad;
    r.maxx = std::max(bt.x0, std::max(bt.x1, bt.x2)) + bare_pad;
    r.minz = std::min(bt.z0, std::min(bt.z1, bt.z2)) - bare_pad;
    r.maxz = std::max(bt.z0, std::max(bt.z1, bt.z2)) + bare_pad;
    const u32 fi = (u32)bare_fx.size();
    bare_fx.push_back(r);
    const s64 gx0 = (s64)std::floor(r.minx * bare_inv), gx1 = (s64)std::floor(r.maxx * bare_inv);
    const s64 gz0 = (s64)std::floor(r.minz * bare_inv), gz1 = (s64)std::floor(r.maxz * bare_inv);
    for (s64 gz = gz0; gz <= gz1; ++gz) {
      for (s64 gx = gx0; gx <= gx1; ++gx) {
        bare_grid[((u64)(u32)(s32)gx << 32) | (u32)(s32)gz].push_back(fi);
      }
    }
  }

  // DISTANCE XZ D'UNE RACINE A L'EMPREINTE NUE LA PLUS PROCHE. Rend 0 et `*inside=true` quand la
  // racine est SOUS l'empreinte (le brin pousserait dans le chemin).
  auto path_dist = [&](float bx, float by, float bz, bool* inside) -> float {
    *inside = false;
    if (bare_fx.empty()) {
      return 1.0e18f;
    }
    const s64 gx = (s64)std::floor(bx * bare_inv), gz = (s64)std::floor(bz * bare_inv);
    auto it = bare_grid.find(((u64)(u32)(s32)gx << 32) | (u32)(s32)gz);
    if (it == bare_grid.end()) {
      return 1.0e18f;
    }
    const float ywin = TRANS_OVL_YWIN_M * U;
    float best = 1.0e18f;
    for (u32 fi : it->second) {
      const auto& r = bare_fx[fi];
      if (bx < r.minx || bx > r.maxx || bz < r.minz || bz > r.maxz) {
        continue;
      }
      const float qx = bx - r.x0, qz = bz - r.z0;
      const float d20 = qx * r.e1x + qz * r.e1z;
      const float d21 = qx * r.e2x + qz * r.e2z;
      const float u = (r.d11 * d20 - r.d01 * d21) * r.inv_denom;
      const float v = (r.d00 * d21 - r.d01 * d20) * r.inv_denom;
      if (u >= 0.f && v >= 0.f && u + v <= 1.f) {
        const float fy = r.y0 + u * r.e1y + v * r.e2y;
        if (std::fabs(fy - by) <= ywin) {
          *inside = true;
          return 0.f;
        }
        continue;
      }
      // Hors du triangle : le point le plus proche vit sur l'une des trois aretes, en XZ.
      const float vx[3] = {r.x0, r.x0 + r.e1x, r.x0 + r.e2x};
      const float vy[3] = {r.y0, r.y0 + r.e1y, r.y0 + r.e2y};
      const float vz[3] = {r.z0, r.z0 + r.e1z, r.z0 + r.e2z};
      for (int e = 0; e < 3; ++e) {
        const int a = e, b = (e + 1) % 3;
        const float ex = vx[b] - vx[a], ez = vz[b] - vz[a];
        const float l2 = ex * ex + ez * ez;
        float t = 0.f;
        if (l2 > 1e-6f) {
          t = ((bx - vx[a]) * ex + (bz - vz[a]) * ez) / l2;
          t = t < 0.f ? 0.f : (t > 1.f ? 1.f : t);
        }
        const float px2 = vx[a] + t * ex, pz2 = vz[a] + t * ez;
        const float py2 = vy[a] + t * (vy[b] - vy[a]);
        if (std::fabs(py2 - by) > ywin) {
          continue;
        }
        const float ddx = bx - px2, ddz = bz - pz2;
        const float dd = std::sqrt(ddx * ddx + ddz * ddz);
        if (dd < best) {
          best = dd;
        }
      }
    }
    return best;
  };
  int trans_inside_n = 0, trans_thin_n = 0, trans_band_n = 0;

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
  size_t occ_kept_object = 0, occ_moved_to_field = 0;
  for (size_t q = 0; q < occ_pts.size(); ++q) {
    // grass-path-transitions : un point de sol nu pose N'OCCULTE PLUS. Il pilote un champ de
    // distance, pas un rayon binaire de 0,45 m. Tous les autres points sont inchanges.
    if (q < occ_is_bare.size() && occ_is_bare[q]) {
      occ_moved_to_field++;
      continue;
    }
    const auto& p = occ_pts[q];
    objpts[occ_bkey(p[0], p[2])].push_back({p[0], p[1], p[2]});
    occ_kept_object++;
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
  std::vector<u16> pathq_tbl;  // grass-path-transitions : distance a l'empreinte nue
  std::vector<BakeTri> bake_tris;
  bake_tris.reserve(tris.size());
  u64 cand_running = 0;

  // grass-clumps : LA MEME classe de placement qu'a l'expansion. Les bits `keep`, `rim_q` et
  // `path_q` se decident ci-dessous SUR LA POSITION du candidat : si la cuisson et l'expansion ne
  // partagent pas la formule, le plancher, l'occultation et le chemin sont testes a un endroit ou
  // aucun brin ne pousse. C'est pourquoi la version du format monte avec cet item (voir
  // GBK_FORMAT_VERSION) : un bake d'avant n'est PAS charge, il n'est pas relu de travers.
  ClumpPlacer placer(total_area_m2, true);

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
    bt.flags = (r.is_tie ? 1u : 0u) | (r.is_lip ? 2u : 0u) | (r.is_dup ? 4u : 0u) |
               (r.is_hang ? 32u : 0u) | (r.is_hang_b ? 64u : 0u);
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
    placer.begin(bt);
    for (int i = 0; i < n; ++i) {
      ClumpSite site;
      placer.place(bt, i, site);
      const float r1 = site.r1;
      const float r2 = site.r2;
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

      // ================= grass-path-transitions : LA TRANSITION, TRANCHEE ICI =================
      // Trois cas, et trois seulement :
      //   * la racine est SOUS une empreinte nue -> le brin est retire, le chemin reste degage ;
      //   * elle est dans la bande -> elle est eclaircie par un tirage compare a `trans_density_mul`
      //     d'une distance PERTURBEE par un bruit coherent : la frontiere devient dentelee au lieu
      //     de suivre un decalage constant, et le plancher `TRANS_DENS_FLOOR` interdit le zero qui
      //     refabriquerait la bande pelee ;
      //   * elle est au-dela -> rien ne change, bit a bit.
      // La HAUTEUR, elle, est attenuee a l'expansion depuis `path_q` SANS bruit : une rampe
      // continue ne peut pas dessiner de ligne sur le maillage.
      bool p_inside = false;
      const float p_d = path_dist(bx, by, bz, &p_inside);
      bool trans_keep = true;
      if (p_inside) {
        trans_keep = false;
        trans_inside_n++;
      } else if (p_d < TRANS_QUERY_M * U) {
        float dn = p_d + TRANS_NOISE_AMP_M * U * trans_noise(bx, bz);
        if (dn < 0.f) {
          dn = 0.f;
        }
        // TIRAGE A FAIBLE DISCREPANCE, PAS UN HACHAGE INDEPENDANT. Un Bernoulli independant
        // s'agglutine : mesure sur `training`, 7,6 candidats en moyenne autour d'un echantillon de
        // limite et 4,6 retires, soit 4,5 % des limites laissees nues — la bande pelee revenait par
        // la statistique apres avoir ete retiree par la geometrie. La suite dorée garde une
        // fraction `w` REGULIEREMENT repartie dans l'ordre d'enumeration, qui est lui-meme sans
        // structure spatiale (les positions sortent d'un hachage). Meme densite moyenne, sans trou.
        const float ld = (float)i * 0.61803399f;
        if ((ld - std::floor(ld)) >= trans_density_mul(dn)) {
          trans_keep = false;
          trans_thin_n++;
        } else if (p_d < TRANS_W_M * U) {
          trans_band_n++;
        }
      }
      keep_tbl.push_back((u8)((scatter_keep ? 1u : 0u) | (occ_hidden ? 0u : 2u) |
                              (trans_keep ? 4u : 0u)));
      rimq_tbl.push_back(rim_encode(dmin));
      // `0` est RESERVE a « dans l'empreinte ». Sans ce plancher, un candidat pose exactement sur
      // l'arete rendait 0 lui aussi et le recensement le comptait comme une invasion : 8 faux
      // positifs sur `training`, un compte de defaut fabrique par sa propre quantification.
      pathq_tbl.push_back(p_inside ? (u16)0 : std::max<u16>(1, path_encode(p_d)));
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
      bt.flags = (fr.is_tie ? 1u : 0u) | 8u | (fr.is_hang ? 32u : 0u) |
                 (fr.is_hang_b ? 64u : 0u);  // bit3 = fringe; bit5 = hang face; bit6 = leafy tex
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
  out.path_q = std::move(pathq_tbl);
  out.stats.trans_bare_geom = (u32)trans_bare_geom;
  out.stats.trans_bare_mat = (u32)trans_bare_mat;
  out.stats.trans_bare_both = (u32)trans_bare_both;
  out.stats.trans_bare_disagree = (u32)trans_bare_disagree;
  out.stats.trans_bare_tris = (u32)bare_fx.size();
  out.stats.faces_up = f_up_tot;
  out.stats.faces_bare_mat = f_bare_tot;
  out.stats.faces_affleurantes = f_flush_tot;
  out.stats.faces_lifted = f_lift_tot;
  out.stats.faces_nofloor = f_nofl_tot;
  out.stats.bare_tex_top = out_bare_tex_top;
  out.stats.bare_rej_top = out_bare_rej_top;
  out.stats.bare_mat_top = out_bare_mat_top;
  out.stats.trans_occ_object = (u32)occ_kept_object;
  out.stats.trans_occ_moved = (u32)occ_moved_to_field;
  {
    double ar = 0.0;
    for (const auto& bd : bare_draws) {
      if (bd.keep_as_bare) {
        ar += bd.area_xz;
      }
    }
    out.stats.trans_bare_area_m2 = (float)ar;
  }
  lg::info(
      "[grass-path-transitions] sols nus poses : draws geometrie={} materiau={} LES DEUX={} "
      "desaccord={} ; empreinte tris={} ; points d'occultation objet={} retires={} ; candidats "
      "dans l'empreinte={} eclaircis={} dans la bande={}",
      trans_bare_geom, trans_bare_mat, trans_bare_both, trans_bare_disagree, bare_fx.size(),
      occ_kept_object, occ_moved_to_field, trans_inside_n, trans_thin_n, trans_band_n);
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
// grass-chunk-cull : LE DECOUPAGE. Un seul parcours, dans l'ordre d'emission, aucune allocation
// par instance. Un lot se ferme quand il DEBORDERAIT — la boite testee est celle qu'on aurait APRES
// avoir ajoute l'instance — ce qui garantit que la boite publiee respecte toujours la borne.
void build_chunks(const std::vector<GrassInstance>& inst, std::vector<GrassChunk>& out) {
  out.clear();
  const size_t n = inst.size();
  if (n == 0) {
    return;
  }
  const float maxd = CHUNK_MAX_DIAG_M * 4096.f;
  const float maxd2 = maxd * maxd;
  out.reserve(n / CHUNK_MAX_COUNT + 16);
  GrassChunk c{};
  auto open_at = [&](size_t i) {
    const auto& g = inst[i];
    c.first = (u32)i;
    c.count = 0;
    c.lo[0] = c.hi[0] = g.px;
    c.lo[1] = c.hi[1] = g.py;
    c.lo[2] = c.hi[2] = g.pz;
  };
  open_at(0);
  for (size_t i = 0; i < n; i++) {
    const auto& g = inst[i];
    if (c.count > 0) {
      const float dx = std::max(c.hi[0], g.px) - std::min(c.lo[0], g.px);
      const float dz = std::max(c.hi[2], g.pz) - std::min(c.lo[2], g.pz);
      if (c.count >= CHUNK_MAX_COUNT || dx * dx + dz * dz > maxd2) {
        out.push_back(c);
        open_at(i);
      }
    }
    c.lo[0] = std::min(c.lo[0], g.px);
    c.hi[0] = std::max(c.hi[0], g.px);
    c.lo[1] = std::min(c.lo[1], g.py);
    c.hi[1] = std::max(c.hi[1], g.py + g.h);  // le SOMMET du brin, pas seulement sa racine
    c.lo[2] = std::min(c.lo[2], g.pz);
    c.hi[2] = std::max(c.hi[2], g.pz);
    c.count++;
  }
  out.push_back(c);
}

ExpandResult expand(const BakeData& d, float density_slider_pct, bool want_cand_map,
                    bool clumped) {
  ExpandResult res;
  res.clumped = clumped;
  // grass-clumps : LA MEME classe qu'a la cuisson. `clumped=false` est le bras d'ablation — le
  // tirage uniforme du code REMPLACE, sur le MEME bake. Les bits `keep` restent ceux des positions
  // en touffes : ce bras mesure le regroupement, il n'est pas un etat livrable.
  ClumpPlacer placer(d.total_area_m2, clumped);
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
  // grass-dead-tail : TOUT CE QUI SUIT NE SERT QU'A LA QUEUE D'OVERHANG, ET RIEN NE LA DESSINE
  // quand `OG_FEAT_GRASS_OVERHANG` est OFF — ce qu'il est dans les DEUX arbres livres
  // (build/CMakeCache.txt et build-android/CMakeCache.txt). `GrassRenderer.cpp` borne alors les
  // deux passes a `nondroop_n = droop_start` (:1873-1883) et pousse `u_overhang = 0.0f` en
  // LITTERAL (:1763-1768) : les instances >= droop_start ne sont jamais passees a un
  // `instancecount`, et le `nspare` negatif pose sur les originales n'a aucun lecteur (le shader
  // ne le lit que sous `is_comb_orig && u_overhang > 0.5`, grass.vert:159).
  // Mesure : 110 472 instances de queue sur 726 851 au palier livre, construites, ecrites dans le
  // tampon, televersees (64 o chacune + 4 o de lumiere), jamais dessinees.
  // ON NE SUPPRIME RIEN : on CONDITIONNE, a la compilation, comme les quatre autres sites du
  // meme drapeau. Option ON -> la queue est emise exactement comme avant.
  // ===========================================================================
#ifdef OG_FEAT_GRASS_OVERHANG
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
  // on the segment, and the squared XZ distance to it. ROUND 8: optional seg_out = the winning segment
  // index, so zone-2/3 can inherit the owning WALKABLE lawn tri's colour + baked light (RimDrapeSeg).
  auto nearest_rim_seg = [&](float px, float py, float pz, float ywin, float& ox, float& oz,
                             float& rim_y, float& d2out, u32* seg_out = nullptr) -> bool {
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
            if (seg_out) *seg_out = si;
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
#endif  // OG_FEAT_GRASS_OVERHANG (machinerie de queue)
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
    placer.begin(tri);
    if (want_cand_map) {
      res.tri_n.resize(d.tris.size(), 0u);
      res.tri_n[tj] = (u32)n;
    }
    for (int i = 0; i < n; ++i) {
      if (scatter_kept >= budget) break;
      // LA PLACE SE TIRE AVANT TOUTE PORTE. Le rang d'un brin dans sa touffe compte les candidats
      // d'indice INFERIEUR tombes dans la meme touffe : le sauter pour un candidat ecarte
      // decalerait tous les suivants, et la cuisson — qui, elle, les enumere tous — placerait ses
      // bits `keep` ailleurs que les brins. C'est la seule raison pour laquelle cet appel est ici.
      ClumpSite site;
      placer.place(tri, i, site);
      const u64 ci = tri.cand_base + (u64)i;
      u8 k = d.keep[ci];
      if (!(k & 1)) continue;
      scatter_kept++;
      if (!(k & 2)) {
        occ_culled++;
        continue;
      }
      // grass-path-transitions : le bit2 porte la decision de DENSITE, tranchee a la cuisson (bruit
      // coherent compris) ; `path_q` porte la distance qui attenue la HAUTEUR. Un bake sans table
      // de distance (aucun sol nu retenu) laisse les deux inactifs, sans branche morte.
      const bool have_path = d.path_q.size() == d.keep.size();
      const u16 pq = have_path ? d.path_q[ci] : (u16)0xFFFF;
      if (!(k & 4)) {
        if (pq == 0) {
          res.trans_culled_inside++;
        } else {
          res.trans_culled_thin++;
        }
        continue;
      }
      const u32 sd = site.sd;
      const float r1 = site.r1;
      const float r2 = site.r2;
      float bx = tri.p0[0] + r1 * tri.e1[0] + r2 * tri.e2[0];
      float by = tri.p0[1] + r1 * tri.e1[1] + r2 * tri.e2[1];
      float bz = tri.p0[2] + r1 * tri.e1[2] + r2 * tri.e2[2];
      if (site.clip < 1.0f) {
        res.clump_clipped++;
      }

      GrassInstance gi;
      gi.px = bx;
      gi.py = by;
      gi.pz = bz;
      gi.h = BASE_H * (0.50f + 1.55f * hash_f(sd + 3u));   // OWNER POLISH#3: wider SIZE variation
      // grass-clumps : « des brins dominants et des brins peripheriques ». Le profil est a MOYENNE
      // CONSERVEE, donc il ne touche pas la hauteur moyenne du champ (hors perimetre de cet item).
      gi.h *= clump_height_mul(site.rho);
      {
        const float p_d = path_decode(pq);
        if (p_d < TRANS_W_M * U) {
          gi.h *= trans_height_mul(p_d);   // grass-path-transitions : la hauteur retombe, sans jamais s'annuler
          res.trans_band++;
        } else {
          res.trans_interior++;
        }
      }
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
#ifdef OG_FEAT_GRASS_OVERHANG
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
#endif  // OG_FEAT_GRASS_OVERHANG (marquage + collecte des jumelles)
      placer.mark(site.clump);  // grass-clumps : cette touffe est MONTEE (le `hits=` les compte)
      res.instances.push_back(gi);
      res.inst_tri.push_back((u32)tj);
      if (want_cand_map) {
        res.inst_cand.push_back((u32)ci);  // grass-path-transitions : le recensement, jamais le jeu
      }
    }
  }
  placer.finish();
  res.clumps_total = placer.total_clumps();
  res.clumps_mounted = placer.total_mounted();
  res.clump_origin_digest = placer.origin_digest();
  res.scatter_kept = scatter_kept;
  res.occ_culled = occ_culled;

#ifdef OG_FEAT_GRASS_OVERHANG
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
#endif  // OG_FEAT_GRASS_OVERHANG (exit_dist ne sert qu'aux zones 2 et 3)

  int plane_capped = 0, plane_dropped = 0;
  // grass-dead-tail : lu par le journal de fin d'expansion, donc declare HORS de la garde.
  int z3_texb = 0;

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

  // grass-dead-tail : `trans_start` est pose ICI pour que le build sans overhang le rende egal
  // a `droop_start` (aucune jumelle de comb) au lieu du 0 par defaut, que le dump hors ligne
  // lirait comme une queue commencant a l'instance 0. Le build ON l'ecrase plus bas.
  res.trans_start = (int)res.instances.size();
#ifdef OG_FEAT_GRASS_OVERHANG
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
        // ROUND 8 colour continuity: below-rim strip blades inherit the nearest rim's WALKABLE lawn
        // colour + light tri (the drop face can be dirt-dark); curl blades sit ON walkable tris and
        // keep their own tri colour.
        float cgr = tri.gr, cgg = tri.gg, cgb = tri.gb;
        u32 light_tri = zf.tri;
        if (zf.curl) {
          w = tw;  // the curl mesh's own steepness IS the gradient (upright top -> bent bottom)
          if (w <= COMB_W_MIN) continue;  // flat upper curl: the stock lawn already covers it
        } else {
          float dw;
          float ox2, oz2, ry, d2;
          u32 rsi = 0;
          if (nearest_rim_seg(bx, by, bz, 2.5f * U, ox2, oz2, ry, d2, &rsi)) {
            float depth_m = (ry - by) / U;  // strip drops below the lip -> positive
            dw = Z2_K1 + (1.0f - Z2_K1) * std::clamp(depth_m / Z2_DEPTH_FULL_M, 0.0f, 1.0f);
            const RimDrapeSeg& rs = d.rimdrape[rsi];
            cgr = rs.gr; cgg = rs.gg; cgb = rs.gb;
            light_tri = rs.tri;
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
        gi.gr = cgr; gi.gg = cgg; gi.gb = cgb;
        gi.gspare = 1.0e9f;  // NO_RIM: the strip blade lies along the sub-lip mesh past the rim
        gi.nx = sn[0]; gi.ny = sn[1]; gi.nz = sn[2];  // SMOOTH NORMAL (shader derives dsl + clamp plane)
        gi.nspare = 5.0f + w;  // COMB-class marker (shader band 4.5..6.5), w = nspare - 5
        res.instances.push_back(gi);
        res.inst_tri.push_back(light_tri);
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

  // ---- ZONE 3 ROUND 11 (supervisor DESIGN PIVOT, df1486b45): textured CARDS sampling the game's
  // OWN hang-alpha texels. Ten rounds proved solid-colour blade quads read as plates/strings/foam at
  // the owner's judging distance (camera at the edge) — never as the native art. Each card is one
  // tail instance the shader stretches into a 4-quad vertical strip hung from the true-rim lip,
  // textured with bch-grassfringe / bch-leafyground-hang-2x1 (alpha-cut, the SAME texels the painted
  // strip uses), in Z3C_LAYERS outward-offset layers with per-layer sway + UV offset/flip and
  // per-card length jitter. Near LOD = animated multi-layer copies of the native strip replacing the
  // flat one (the tfrag/TIE fringe-fade still hides it near; restored at distance as the cards LOD
  // out — crossfade, no double-up). The R8-R10 solid fall classes (nspare 7.x) are DELETED.
  int z3_placed = 0;
  {
    // hang-face grid (GCELL cells): cards only hang from rim segments that actually have native-
    // alpha strip faces below them — clean drop-offs keep their stock silhouette. Per entry we keep
    // the face's LOWEST vertex (where the painted strip's texels end -> per-root hang depth) and its
    // texture id (bit6) so each card samples the texels its own face natively shows.
    struct HangPt {
      float x, y, ymin, z;
      bool texb;
    };
    std::unordered_map<u64, std::vector<HangPt>> hang_cent;
    for (const auto& de : d.droop) {
      if (de.tri >= d.tris.size()) continue;
      const BakeTri& ht = d.tris[de.tri];
      if (!(ht.flags & 32u)) continue;
      float cx = ht.p0[0] + (ht.e1[0] + ht.e2[0]) * (1.0f / 3.0f);
      float cy = ht.p0[1] + (ht.e1[1] + ht.e2[1]) * (1.0f / 3.0f);
      float cz = ht.p0[2] + (ht.e1[2] + ht.e2[2]) * (1.0f / 3.0f);
      float ymin = std::min(ht.p0[1], std::min(ht.p0[1] + ht.e1[1], ht.p0[1] + ht.e2[1]));
      hang_cent[gkey((s64)std::floor(cx / GCELL), (s64)std::floor(cz / GCELL))].push_back(
          {cx, cy, ymin, cz, (ht.flags & 64u) != 0u});
    }
    // Probe the strip below a point: deepest strip bottom (hang depth) + majority texture.
    auto hang_probe = [&](float px, float py, float pz, float& depth, bool& texb) -> bool {
      s64 cx = (s64)std::floor(px / GCELL), cz = (s64)std::floor(pz / GCELL);
      bool found = false;
      float deep = 0.f;
      int votes_b = 0, votes_a = 0;
      for (s64 dx = -1; dx <= 1; ++dx)
        for (s64 dz = -1; dz <= 1; ++dz) {
          auto it = hang_cent.find(gkey(cx + dx, cz + dz));
          if (it == hang_cent.end()) continue;
          for (const auto& c : it->second) {
            float ddx = c.x - px, ddz = c.z - pz, dy = py - c.y;
            if (dy > -0.3f * U && dy < Z3_LIP_NEAR_HANG_M * U &&
                ddx * ddx + ddz * ddz < (1.5f * U) * (1.5f * U)) {
              found = true;
              deep = std::max(deep, py - c.ymin);
              if (c.texb) {
                votes_b++;
              } else {
                votes_a++;
              }
            }
          }
        }
      if (found) {
        depth = deep;
        texb = votes_b > votes_a;
      }
      return found;
    };
    const float SP = Z3C_SPACING_M * U;
    const float RPT = Z3C_REPEAT_W_M * U;
    for (u32 si = 0; si < (u32)d.rimdrape.size(); ++si) {
      const RimDrapeSeg& rs = d.rimdrape[si];
      float sx = rs.bx - rs.ax, sy = rs.by - rs.ay, sz = rs.bz - rs.az;
      float seglen = std::sqrt(sx * sx + sy * sy + sz * sz);
      if (seglen < 0.02f * U) continue;
      // segment gate + fallback depth/tex: probe midpoint and both endpoints
      float seg_depth = 0.f;
      bool seg_texb = false, seg_found = false;
      {
        float mx = rs.ax + 0.5f * sx, my = rs.ay + 0.5f * sy, mz = rs.az + 0.5f * sz;
        float dp;
        bool tb;
        if (hang_probe(mx, my, mz, dp, tb)) { seg_found = true; seg_depth = std::max(seg_depth, dp); seg_texb = tb; }
        if (hang_probe(rs.ax, rs.ay, rs.az, dp, tb) && (!seg_found || dp > seg_depth)) { seg_found = true; seg_depth = dp; seg_texb = tb; }
        if (hang_probe(rs.bx, rs.by, rs.bz, dp, tb) && (!seg_found || dp > seg_depth)) { seg_found = true; seg_depth = dp; seg_texb = tb; }
      }
      if (!seg_found) continue;
      int nb = (int)(seglen / SP) + 1;
      for (int layer = 0; layer < Z3C_LAYERS; ++layer) {
        for (int i = 0; i < nb; ++i) {
          if (z3_placed >= Z3C_MAX) break;
          u32 sd = (rs.tri * 2654435761u) ^ (si * 0x9E3779B9u) ^ ((u32)i * 40503u) ^
                   ((u32)layer * 0x5bd1e995u);
          // per-layer stagger + jitter so no two layers share a root line
          float arc = ((float)i + (float)layer / (float)Z3C_LAYERS +
                       (hash_f(sd + 1u) - 0.5f) * 0.35f) *
                      SP;
          float u01 = arc / seglen;
          if (u01 < 0.f || u01 > 1.f) continue;
          float bx = rs.ax + sx * u01;
          float by = rs.ay + sy * u01 - Z3C_SINK_M * U;
          float bz = rs.az + sz * u01;
          // per-root depth/texture (falls back to the segment probe on gaps in the strip)
          float depth = seg_depth;
          bool texb = seg_texb;
          hang_probe(bx, by, bz, depth, texb);
          float h = std::min(std::max(depth + Z3C_DEPTH_MARGIN_M * U, Z3C_DEPTH_MIN_M * U),
                             Z3C_DEPTH_MAX_M * U);
          h *= 0.85f + 0.30f * hash_f(sd + 3u);  // per-card length jitter (ragged strip bottom)
          // don't stab the terrace floor below: iterative shrink against nearby planes (rest tip =
          // root + outw*loff - h, mirrors the shader), FLOORED so a root can never be dropped.
          float loff = (0.05f + 0.105f * (float)layer) * U;  // MUST mirror the shader's card loff
          float basep[3] = {bx, by, bz};
          for (int it = 0; it < 16; ++it) {
            float tip[3] = {bx + rs.ox * loff, by - h, bz + rs.oz * loff};
            if (!tip_violates(basep, tip, rs.tri)) break;
            h *= 0.85f;
          }
          if (h < 0.5f * Z3C_DEPTH_MIN_M * U) h = 0.5f * Z3C_DEPTH_MIN_M * U;
          GrassInstance gi;
          gi.px = bx; gi.py = by; gi.pz = bz;
          gi.h = h;
          gi.yaw = std::atan2(rs.ox, rs.oz);
          gi.tint = hash_f(sd + 5u);
          // u0: continuous along-lip texture phase (arc / one world repeat) — adjacent cards on the
          // same segment continue the SAME texel run, so the strip art tiles like the native draw.
          gi.curve = arc / RPT - std::floor(arc / RPT);
          gi.phase = hash_f(sd + 7u);
          gi.gr = rs.gr; gi.gg = rs.gg; gi.gb = rs.gb;  // walkable lawn colour (round-8 rule)
          gi.gspare = 1.0e9f;  // NO_RIM: the hang over the lip is the intended overhang
          gi.nx = rs.ox; gi.ny = 0.0f; gi.nz = rs.oz;  // unit outward (shader offsets per layer)
          // card class: 9 + layer, +0.5 encodes WHICH hang texture the card samples
          gi.nspare = 9.0f + (float)layer + (texb ? 0.5f : 0.0f);
          res.instances.push_back(gi);
          res.inst_tri.push_back(rs.tri);  // lawn tri light -> brightness continuity at the lip
          z3_placed++;
          if (texb) z3_texb++;
        }
      }
    }
  }
  res.z3_count = z3_placed;
#endif  // OG_FEAT_GRASS_OVERHANG (zones 1, 2, 3 : la queue que rien ne dessine)

  res.plane_capped = plane_capped;
  res.plane_dropped = plane_dropped;
  lg::info("[recharged-grass] GOVERHANG6 zones: lean_tagged={} lean_twins={} (band {:.2f}m) z2_strip={} "
           "z3_fall={} (CARDS layers={} texb={}) comb_repl={} curl_blades={} curl_tilt0={} "
           "plane_capped={} plane_dropped={}",
           res.lean_tagged, res.lean_twins, LEAN_BAND_M, res.z2_count, res.z3_count, Z3C_LAYERS,
           z3_texb, res.comb_pairs, dbg_trans_blades, dbg_trans_tilt0, plane_capped, plane_dropped);
  // grass-chunk-cull : la partition, recalculee depuis les instances qu'on vient d'emettre. Un
  // seul parcours de min/max sur un tableau deja chaud : c'est la meme fonction que l'outil de
  // cuisson appelle, donc les deux cotes ne peuvent pas diverger sans que le moteur le voie.
  build_chunks(res.instances, res.chunks);
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
// grass-chunk-cull: v8: section `chunks` en queue (partition spatiale cuite de l'expansion a
// `bake_density_pct`). Un v7 echoue la garde de version et n'est PAS charge : les cinq bakes
// livres se recuisent par `scripts/shell/build_grass_bakes.sh`.
// grass-clumps: v10 = bump SEMANTIQUE, layout inchange. Les racines ne sont plus un tirage
// barycentrique uniforme mais un placement en TOUFFES, et les bits `keep` / `rim_q` / `path_q` se
// decident SUR CES POSITIONS. Un bake v9 relu par ce binaire aurait ses verdicts de plancher,
// d'occultation et de chemin a des endroits ou plus aucun brin ne pousse — un brin valide
// au-dessus du vide, en silence. La garde de version l'interdit AU POINT DE PRODUCTION : un v9
// n'est pas charge (et le niveau reste sans herbe, il n'y a PAS de repli en direct), donc les cinq
// bakes livres se recuisent par `scripts/shell/build_grass_bakes.sh`.
constexpr u32 GBK_FORMAT_VERSION = 10;

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
  // Ggrass-crash : `off + n` DEBORDE quand `n` vient d'un compte aberrant lu dans le fichier
  // (`ncand * sizeof(u16)` avec ncand ~ 8e18 repasse sous buf.size() par enroulement) — la garde
  // passait alors et le `memcpy` suivait. On soustrait au lieu d'additionner : jamais d'enroulement.
  if (off > buf.size() || n > buf.size() - off) return false;
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

  // grass-chunk-cull (GBK8) : la partition. Ecrite en queue, apres toutes les sections v7, pour
  // qu'un lecteur v8 lise un v8 sans deplacer un seul offset existant.
  put<u32>(buf, (u32)d.chunks.size());
  for (const auto& c : d.chunks) {
    put<u32>(buf, c.first);
    put<u32>(buf, c.count);
    for (int k = 0; k < 3; ++k) {
      put<float>(buf, c.lo[k]);
    }
    for (int k = 0; k < 3; ++k) {
      put<float>(buf, c.hi[k]);
    }
  }

  // grass-path-transitions (GBK9) : la distance a l'empreinte du sol nu, par candidat. Ecrite
  // EN QUEUE, apres toutes les sections v8, pour ne deplacer aucun offset existant. Un compte
  // explicite precede la table : « section absente » et « section tronquee » ne se lisent pas
  // pareil, et un v8 est refuse par la garde de version, jamais lu de travers.
  put<u64>(buf, (u64)d.path_q.size());
  put_bytes(buf, d.path_q.data(), d.path_q.size() * sizeof(u16));
  put<u32>(buf, d.stats.trans_bare_geom);
  put<u32>(buf, d.stats.trans_bare_mat);
  put<u32>(buf, d.stats.trans_bare_both);
  put<u32>(buf, d.stats.trans_bare_disagree);
  put<u32>(buf, d.stats.trans_bare_tris);
  put<u32>(buf, d.stats.trans_occ_object);
  put<u32>(buf, d.stats.trans_occ_moved);
  put<float>(buf, d.stats.trans_bare_area_m2);
  put<u64>(buf, d.stats.faces_up);
  put<u64>(buf, d.stats.faces_bare_mat);
  put<u64>(buf, d.stats.faces_affleurantes);
  put<u64>(buf, d.stats.faces_lifted);
  put<u64>(buf, d.stats.faces_nofloor);
  for (const std::string* sp : {&d.stats.bare_tex_top, &d.stats.bare_rej_top,
                                &d.stats.bare_mat_top}) {
    const u32 n = (u32)std::min<size_t>(sp->size(), 1024);
    put<u32>(buf, n);
    put_bytes(buf, sp->data(), n);
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

// Ggrass-crash : UN COMPTE LU DANS UN FICHIER N'EST PAS UNE TAILLE D'ALLOCATION.
// `load_bake` faisait `resize(n)` AVANT de verifier que `n` elements tiennent encore dans le
// tampon. Un compte aberrant — fichier tronque, ecrit par une autre version, ou desynchronisation
// de format — devenait donc directement `operator new(n * taille)`. MESURE, Redmi, 12 courses sur
// 12 : `malloc(8027506242768285312) failed` puis `std::bad_alloc` non rattrapee puis SIGABRT ;
// `8027506242768285312` = `0x6f676e65706f2e80`, octets `80 2e 6f 70 65 6e 67 6f` = « \x80.opengo »,
// c'est-a-dire du TEXTE lu comme un compte. `keep` etant un `vector<u8>`, la taille demandee EST le
// compte, au bit pres.
// Ce predicat borne le compte par ce qui RESTE reellement a lire, sans jamais multiplier deux
// grandeurs non bornees (la division ne peut pas deborder).
static bool count_fits(const std::vector<u8>& buf, size_t off, u64 count, size_t elem_bytes) {
  if (off > buf.size()) {
    return false;
  }
  const u64 restant = (u64)(buf.size() - off);
  return elem_bytes == 0 || count <= restant / (u64)elem_bytes;
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

  // 216 octets par triangle SUR DISQUE (p0/e1/e2 36 + seed 4 + aire 4 + rgb 12 + normale 12
  // + palette 96 + cand_count 4 + cand_base 8 + flags 4 + 3 normales lissees 36).
  if (!count_fits(buf, off, ntris, 216)) {
    lg::warn("[recharged-grass] load_bake: compte de tris aberrant ({}) dans '{}' — refuse", ntris,
             path);
    return false;
  }
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
  if (!count_fits(buf, off, ncand, sizeof(u8)) ||
      !count_fits(buf, off + (size_t)ncand, ncand, sizeof(u16))) {
    lg::warn("[recharged-grass] load_bake: compte de candidats aberrant ({}) dans '{}' — refuse",
             ncand, path);
    return false;
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
  if (!count_fits(buf, off, ndroop, 12)) {  // tri 4 + ox 4 + oz 4
    lg::warn("[recharged-grass] load_bake: compte de droop aberrant ({}) dans '{}' — refuse",
             ndroop, path);
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
  if (!count_fits(buf, off, nrims, 24)) {  // 6 floats
    lg::warn("[recharged-grass] load_bake: compte de droop-rims aberrant ({}) dans '{}' — refuse",
             nrims, path);
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
  if (!count_fits(buf, off, nrd, 48)) {  // 11 floats + 1 u32
    lg::warn("[recharged-grass] load_bake: compte de rim-drape aberrant ({}) dans '{}' — refuse",
             nrd, path);
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

  // grass-chunk-cull (GBK8) : la partition cuite. Les bornes de sanite sont les MEMES que celles
  // que `build_chunks` respecte par construction ; une table qui ne couvre pas exactement
  // [0, somme des comptes) est refusee ici plutot que de faire sauter des instances au dessin.
  u32 nch = 0;
  if (!get(buf, off, nch)) {
    lg::warn("[recharged-grass] load_bake: truncated chunk count in '{}'", path);
    return false;
  }
  if (!count_fits(buf, off, nch, 32)) {  // 2 u32 + 6 floats
    lg::warn("[recharged-grass] load_bake: compte de chunks aberrant ({}) dans '{}' — refuse", nch,
             path);
    return false;
  }
  tmp.chunks.resize(nch);
  u64 covered = 0;
  for (u32 i = 0; i < nch; ++i) {
    GrassChunk& c = tmp.chunks[i];
    bool okc = get(buf, off, c.first) && get(buf, off, c.count);
    for (int k = 0; k < 3 && okc; ++k) {
      okc = get(buf, off, c.lo[k]);
    }
    for (int k = 0; k < 3 && okc; ++k) {
      okc = get(buf, off, c.hi[k]);
    }
    if (!okc) {
      lg::warn("[recharged-grass] load_bake: truncated chunks[] in '{}'", path);
      return false;
    }
    if (c.first != (u32)covered) {
      lg::warn("[recharged-grass] load_bake: chunks[{}] ne suit pas le precedent ({} != {}) dans "
               "'{}' — refuse",
               i, c.first, covered, path);
      return false;
    }
    covered += c.count;
  }

  // grass-path-transitions (GBK9) : la table de distance a l'empreinte nue.
  u64 npath = 0;
  if (!get(buf, off, npath)) {
    lg::warn("[recharged-grass] load_bake: compte de path_q absent dans '{}'", path);
    return false;
  }
  if (npath != 0 && npath != ncand) {
    lg::warn("[recharged-grass] load_bake: path_q de taille {} pour {} candidats dans '{}' — refuse",
             npath, ncand, path);
    return false;
  }
  if (!count_fits(buf, off, (u32)npath, sizeof(u16))) {
    lg::warn("[recharged-grass] load_bake: compte de path_q aberrant ({}) dans '{}' — refuse",
             npath, path);
    return false;
  }
  tmp.path_q.resize((size_t)npath);
  if (npath && !get_bytes(buf, off, tmp.path_q.data(), (size_t)npath * sizeof(u16))) {
    lg::warn("[recharged-grass] load_bake: truncated path_q[] in '{}'", path);
    return false;
  }
  if (!get(buf, off, tmp.stats.trans_bare_geom) || !get(buf, off, tmp.stats.trans_bare_mat) ||
      !get(buf, off, tmp.stats.trans_bare_both) || !get(buf, off, tmp.stats.trans_bare_disagree) ||
      !get(buf, off, tmp.stats.trans_bare_tris) || !get(buf, off, tmp.stats.trans_occ_object) ||
      !get(buf, off, tmp.stats.trans_occ_moved) ||
      !get(buf, off, tmp.stats.trans_bare_area_m2) || !get(buf, off, tmp.stats.faces_up) ||
      !get(buf, off, tmp.stats.faces_bare_mat) || !get(buf, off, tmp.stats.faces_affleurantes) ||
      !get(buf, off, tmp.stats.faces_lifted) || !get(buf, off, tmp.stats.faces_nofloor)) {
    lg::warn("[recharged-grass] load_bake: compteurs de transition tronques dans '{}'", path);
    return false;
  }
  for (std::string* sp : {&tmp.stats.bare_tex_top, &tmp.stats.bare_rej_top,
                          &tmp.stats.bare_mat_top}) {
    u32 n = 0;
    if (!get(buf, off, n) || n > 1024) {
      lg::warn("[recharged-grass] load_bake: liste de transition aberrante dans '{}'", path);
      return false;
    }
    sp->assign(n, '\0');
    if (n && !get_bytes(buf, off, &(*sp)[0], n)) {
      lg::warn("[recharged-grass] load_bake: liste de transition tronquee dans '{}'", path);
      return false;
    }
  }

  d = std::move(tmp);
  return true;
}

// ===========================================================================================
// grass-surface-truth : LES DEUX SOURCES. Le contrat est dans GrassBakeCore.h.
// ===========================================================================================
//
// CE BLOC NE TOUCHE RIEN. Il ne partage aucune variable avec `scan_level` / `expand`, il
// n'ecrit dans aucune structure cuite, et il n'est appele par aucun chemin de placement. Le
// `.grassbake` produit apres ce commit est octet pour octet celui d'avant ; le recensement de
// l'item le VERIFIE au lieu de l'affirmer.

namespace {

// pat-h.gc:5-27. L'ORDRE EST LE CODE : `grass` vaut 7 parce qu'il est le huitieme de la liste,
// `dirt` 15, `sand` 5, `stone` 0. Une valeur hors de cette table est une valeur que la donnee
// ne nomme pas : la source MATERIAU se tait alors, elle ne fabrique pas un nom de repli.
const char* const kPatMaterialNames[kPatMaterialCount] = {
    "stone", "ice",   "quicksand", "waterbottom", "tar",    "sand",     "wood",   "grass",
    "pcmetal", "snow", "deepsnow",  "hotcoals",    "lava",   "crwood",   "gravel", "dirt",
    "metal", "straw", "tube",      "swamp",       "stopproj", "rotate", "neutral"};
// grass-path-transitions : les cinq identifiants et le predicat « sol nu » vivent desormais dans
// GrassBakeCore.h — `scan_level`, compile AVANT ce bloc, en a besoin. Une seule definition.

// LA REGLE DE LA SOURCE TEXTURE, ET POURQUOI ELLE N'EST PAS LA REGLE DU BAKE. Reprendre
// `is_grass_ground` ici ferait un miroir : la source TEXTURE rendrait le meme verdict que la
// population qu'on cherche justement a elargir, et le desaccord serait nul par construction.
// Le filet est donc un filet de NOMS, publie tel quel, et chaque desaccord qu'il produit est
// NOMME texture par texture pour que les items suivants le curent sur mesure.
inline bool census_tex_is_grassy(const std::string& n) {
  return n.find("grass") != std::string::npos || n.find("leafy") != std::string::npos ||
         n.find("moss") != std::string::npos || n.find("turf") != std::string::npos;
}

// Les TROIS noms exacts qui font l'eligibilite aujourd'hui (GrassBakeCore.cpp:39-44). Recense
// pour chiffrer l'etat d'AVANT, jamais pour decider.
inline bool census_tex_is_legacy3(const std::string& n) {
  return n == "tra-grass" || n == "bch-grassfringe" || n == "bch-leafyground-hang-2x1";
}

// Un triangle de RENDU projete en XZ, prepare pour la requete point-dans-triangle.
struct SurfRenderTri {
  float p0x, p0y, p0z;
  float e1x, e1y, e1z;
  float e2x, e2y, e2z;
  float minx, maxx, minz, maxz;
  float d00, d01, d11, inv_denom;
  // L'ETIQUETTE : index de texture pour un triangle de RENDU, `pat-material` pour un triangle de
  // COLLISION. Le meme index sert aux deux, donc le meme champ porte les deux sens.
  s32 label;
  // LA PROVENANCE. Elle NOMME ce qu'est un mesh pose par-dessus : le tfrag `dirt` est un arbre de
  // terrain a part entiere dans la donnee d'origine (TFragmentTreeKind::DIRT), et une piece TIE
  // n'est pas du terrain du tout — c'est la population que l'occultation d'objets traite deja
  // (SPEC section 9, question 2). Sans elle, « superposition » melangerait un chemin de terre et
  // le plancher d'une hutte.
  u8 src;
};
// TFragmentTreeKind (8 valeurs) puis TIE, puis la collision.
constexpr u8 kSrcTie = 8;
constexpr u8 kSrcCollision = 9;
inline const char* ovl_src_name(u8 s) {
  static const char* const kNames[] = {"tfrag-normal", "tfrag-trans",        "tfrag-dirt",
                                       "tfrag-ice",    "tfrag-lowres",       "tfrag-lowres-trans",
                                       "tfrag-water",  "tfrag-invalid",      "tie",
                                       "collision"};
  return s < 10 ? kNames[s] : "?";
}

constexpr float SURF_BUCKET_M = 4.0f;    // maille XZ de l'index des triangles de rendu
constexpr float SURF_YWIN_M = 1.5f;      // fenetre verticale centroide de collision <-> sol dessine
constexpr float SURF_UPNESS = 0.20f;     // au-dessous, la face est un mur : ce n'est pas un sol
constexpr s64 SURF_MAX_SPAN = 32;        // au-dela, le triangle va dans la liste des geants

// ---------------------------------------------------------------------------------------------
// L'INDEX SPATIAL XZ, PARTAGE PAR LES DEUX RECENSEMENTS (grass-surface-truth, grass-overlay-meshes).
// ---------------------------------------------------------------------------------------------
// `label` porte l'ETIQUETTE du triangle : l'index de texture pour un triangle de RENDU, la valeur
// de `pat-material` pour un triangle de COLLISION. Une SEULE construction, une SEULE sonde : deux
// copies auraient derive l'une de l'autre, et le desaccord entre les deux items serait devenu un
// artefact de recopie au lieu d'une mesure.
struct SurfRenderIndex {
  std::vector<SurfRenderTri> tris;
  std::unordered_map<u64, std::vector<u32>> grid;
  std::vector<u32> big;  // trop etendus pour l'index : balayes lineairement
  float binv = 1.0f / (SURF_BUCKET_M * U);
  u64 draws = 0;
};

// Entre un triangle s'il regarde vers le haut et n'est pas degenere. Rend son indice, ou -1.
s32 surf_index_add(SurfRenderIndex& ix, float ax, float ay, float az, float bx, float by, float bz,
                   float cx, float cy, float cz, s32 label, u8 src) {
  float e1x = bx - ax, e1y = by - ay, e1z = bz - az;
  float e2x = cx - ax, e2y = cy - ay, e2z = cz - az;
  float nx = e1y * e2z - e1z * e2y;
  float ny = e1z * e2x - e1x * e2z;
  float nz = e1x * e2y - e1y * e2x;
  float nlen = std::sqrt(nx * nx + ny * ny + nz * nz);
  if (nlen < 1e-3f) {
    return -1;  // degenere
  }
  if (std::fabs(ny) / nlen < SURF_UPNESS) {
    return -1;  // mur : ce n'est pas un sol
  }
  SurfRenderTri r;
  r.p0x = ax; r.p0y = ay; r.p0z = az;
  r.e1x = e1x; r.e1y = e1y; r.e1z = e1z;
  r.e2x = e2x; r.e2y = e2y; r.e2z = e2z;
  r.d00 = e1x * e1x + e1z * e1z;
  r.d01 = e1x * e2x + e1z * e2z;
  r.d11 = e2x * e2x + e2z * e2z;
  float denom = r.d00 * r.d11 - r.d01 * r.d01;
  if (std::fabs(denom) < 1e-6f) {
    return -1;  // sliver vertical en projection XZ : ne couvre aucun point
  }
  r.inv_denom = 1.0f / denom;
  r.minx = std::min(ax, std::min(bx, cx));
  r.maxx = std::max(ax, std::max(bx, cx));
  r.minz = std::min(az, std::min(bz, cz));
  r.maxz = std::max(az, std::max(bz, cz));
  r.label = label;
  r.src = src;
  u32 ri = (u32)ix.tris.size();
  ix.tris.push_back(r);
  s64 gx0 = (s64)std::floor(r.minx * ix.binv), gx1 = (s64)std::floor(r.maxx * ix.binv);
  s64 gz0 = (s64)std::floor(r.minz * ix.binv), gz1 = (s64)std::floor(r.maxz * ix.binv);
  if ((gx1 - gx0) > SURF_MAX_SPAN || (gz1 - gz0) > SURF_MAX_SPAN) {
    ix.big.push_back(ri);  // un triangle geant n'explose pas l'index : il est balaye a part
    return (s32)ri;
  }
  for (s64 gz = gz0; gz <= gz1; ++gz) {
    for (s64 gx = gx0; gx <= gx1; ++gx) {
      ix.grid[((u64)(u32)(s32)gx << 32) | (u32)(s32)gz].push_back(ri);
    }
  }
  return (s32)ri;
}

// L'ordonnee du plan du triangle a la verticale de (px,pz) — appelee seulement sur un point dont
// on a deja verifie qu'il est DANS le triangle projete.
double surf_tri_y_at(const SurfRenderTri& r, double px, double pz) {
  double qx = px - r.p0x, qz = pz - r.p0z;
  double d20 = qx * r.e1x + qz * r.e1z;
  double d21 = qx * r.e2x + qz * r.e2z;
  double u = ((double)r.d11 * d20 - (double)r.d01 * d21) * (double)r.inv_denom;
  double v = ((double)r.d00 * d21 - (double)r.d01 * d20) * (double)r.inv_denom;
  return (double)r.p0y + u * (double)r.e1y + v * (double)r.e2y;
}

// Rend l'indice du triangle indexe le plus proche VERTICALEMENT du point, dans `ywin`, ou -1.
//
// DEUX FILTRES OPTIONNELS, et ils ne sont pas du confort. `mask` restreint la recherche aux
// triangles qui portent un caractere donne : quand DEUX surfaces sont empilees, « la plus proche »
// rend toujours celle du dessous, si bien qu'une sonde non filtree ne pourrait JAMAIS voir le mesh
// pose par-dessus — la question meme de `grass-overlay-meshes`. `above_only` refuse ce qui est
// SOUS le point : un mesh de sable un metre plus bas n'est pas pose par-dessus.
s32 surf_index_probe_masked(const SurfRenderIndex& ix, float px, float py, float pz, float ywin,
                            const u8* mask, bool above_only, float above_eps) {
  s32 best = -1;
  float bestd = ywin;
  auto probe = [&](u32 ri) {
    const auto& r = ix.tris[ri];
    if (mask && !mask[ri]) {
      return;
    }
    if (px < r.minx || px > r.maxx || pz < r.minz || pz > r.maxz) {
      return;
    }
    float qx = px - r.p0x, qz = pz - r.p0z;
    float d20 = qx * r.e1x + qz * r.e1z;
    float d21 = qx * r.e2x + qz * r.e2z;
    float u = (r.d11 * d20 - r.d01 * d21) * r.inv_denom;
    float v = (r.d00 * d21 - r.d01 * d20) * r.inv_denom;
    if (u < -0.02f || v < -0.02f || u + v > 1.02f) {
      return;
    }
    float y = r.p0y + u * r.e1y + v * r.e2y;
    if (above_only && y < py - above_eps) {
      return;
    }
    float d = std::fabs(y - py);
    if (d < bestd) {
      bestd = d;
      best = (s32)ri;
    }
  };
  s64 gx = (s64)std::floor(px * ix.binv), gz = (s64)std::floor(pz * ix.binv);
  auto it = ix.grid.find(((u64)(u32)(s32)gx << 32) | (u32)(s32)gz);
  if (it != ix.grid.end()) {
    for (u32 ri : it->second) {
      probe(ri);
    }
  }
  for (u32 ri : ix.big) {
    probe(ri);
  }
  return best;
}

s32 surf_index_probe(const SurfRenderIndex& ix, float px, float py, float pz, float ywin) {
  return surf_index_probe_masked(ix, px, py, pz, ywin, nullptr, false, 0.f);
}

// TOUS les triangles de rendu qui regardent vers le haut — tfrag (geo 0) puis TIE (geo 0), la MEME
// enumeration que `scan_level`, SANS son filtre de nom : filtrer ici ramenerait la question a la
// reponse.
void surf_build_render_index(const tfrag3::Level& lev, SurfRenderIndex& ix) {
  auto index_draws = [&](const std::vector<tfrag3::StripDraw>& draws,
                         const std::vector<tfrag3::PreloadedVertex>& verts,
                         const std::vector<u32>& idx, bool use_strips, u8 src) {
    if (verts.empty() || idx.empty()) {
      return;
    }
    for (const auto& draw : draws) {
      if (draw.tree_tex_id < 0 || (size_t)draw.tree_tex_id >= lev.textures.size()) {
        continue;
      }
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
      ix.draws++;
      auto take = [&](u32 i0, u32 i1, u32 i2) {
        if (i0 == UINT32_MAX || i1 == UINT32_MAX || i2 == UINT32_MAX) {
          return;
        }
        if (i0 >= verts.size() || i1 >= verts.size() || i2 >= verts.size()) {
          return;
        }
        if (i0 == i1 || i1 == i2 || i0 == i2) {
          return;  // couture de strip
        }
        const auto& a = verts[i0];
        const auto& b = verts[i1];
        const auto& c = verts[i2];
        surf_index_add(ix, a.x, a.y, a.z, b.x, b.y, b.z, c.x, c.y, c.z, draw.tree_tex_id, src);
      };
      if (use_strips) {
        u32 a = UINT32_MAX, b = UINT32_MAX;
        for (u32 k = begin; k < begin + len; ++k) {
          u32 ci = idx[k];
          if (ci == UINT32_MAX) {
            a = UINT32_MAX;
            b = UINT32_MAX;
            continue;
          }
          take(a, b, ci);
          a = b;
          b = ci;
        }
      } else {
        for (u32 k = begin; k + 2 < begin + len; k += 3) {
          take(idx[k], idx[k + 1], idx[k + 2]);
        }
      }
    }
  };
  for (const auto& tree : lev.tfrag_trees[0]) {
    u8 src = (u8)tree.kind;
    if (src > 7) {
      src = 7;  // hors enum : « invalid », nomme comme tel plutot que fabrique
    }
    index_draws(tree.draws, tree.unpacked.vertices, tree.unpacked.indices, tree.use_strips, src);
  }
  for (const auto& tree : lev.tie_trees[0]) {
    index_draws(tree.static_draws, tree.unpacked.vertices, tree.unpacked.indices, tree.use_strips,
                kSrcTie);
  }
}


// « nom:compte,... », les `top` premiers, tri par compte decroissant puis par nom. Aucun espace :
// `proof_run.sh` jette toute valeur qui en porte un (motif `^cle=[^[:space:]]+$`). Une liste vide
// rend "-", jamais la chaine vide — une cle absente et une cle vide ne se lisent pas pareil.
std::string surf_top_names(const std::unordered_map<std::string, u64>& m, size_t top) {
  std::vector<std::pair<std::string, u64>> v(m.begin(), m.end());
  std::sort(v.begin(), v.end(), [](const auto& a, const auto& b) {
    if (a.second != b.second) {
      return a.second > b.second;
    }
    return a.first < b.first;
  });
  std::string out;
  for (size_t i = 0; i < v.size() && i < top; ++i) {
    std::string name = v[i].first;
    if (name.empty()) {
      name = "(sans-nom)";
    }
    for (char& c : name) {
      if (c == ' ' || c == '\t' || c == ',' || c == ':' || c == '=') {
        c = '_';
      }
    }
    if (!out.empty()) {
      out += ',';
    }
    out += name + ":" + std::to_string(v[i].second);
  }
  return out.empty() ? std::string("-") : out;
}

}  // namespace

const char* pat_material_name(u32 material) {
  return material < kPatMaterialCount ? kPatMaterialNames[material] : nullptr;
}

SurfaceCensus surface_census(const tfrag3::Level& lev, const std::string& level_name) {
  SurfaceCensus c;

  // ---- SOURCE TEXTURE : l'index XZ de TOUS les triangles de rendu qui regardent vers le haut.
  // La population de rendu n'est PAS filtree par nom : filtrer ici ramenerait la question a la
  // reponse (voir census_tex_is_grassy). C'est le MEME index que celui de `grass-overlay-meshes`
  // — une seule construction, donc aucun ecart de recopie entre les deux items.
  SurfRenderIndex rix;
  surf_build_render_index(lev, rix);
  c.render_draws = rix.draws;
  c.render_ground_tris = (u64)rix.tris.size();
  c.textures_seen = (u64)lev.textures.size();

  const float YWIN = SURF_YWIN_M * U;
  // Rend l'index de texture du sol DESSINE le plus proche verticalement du point, ou -1.
  auto tex_at = [&](float px, float py, float pz) -> s32 {
    const s32 ti = surf_index_probe(rix, px, py, pz, YWIN);
    return ti < 0 ? -1 : rix.tris[ti].label;
  };

  // ---- LA POPULATION : le sol tel que la collision du jeu le declare (pat-mode ground).
  std::unordered_map<std::string, u64> disagree_tex, mat_grass_tex, tex_grass_mat;
  const auto& cv = lev.collision.vertices;
  const size_t ntri = cv.size() / 3;
  c.collision_tris = (u64)ntri;
  for (size_t t = 0; t < ntri; ++t) {
    const auto& a = cv[t * 3 + 0];
    const auto& b = cv[t * 3 + 1];
    const auto& d = cv[t * 3 + 2];
    const u32 mode = (a.pat >> 3) & 0x7u;
    switch (mode) {
      case 0: c.mode_ground++; break;
      case 1: c.mode_wall++; break;
      case 2: c.mode_obstacle++; break;
      default: c.mode_other++; break;
    }
    if (mode != 0) {
      continue;  // pat-mode 0 = ground : la meme porte que GrassBakeCore.cpp:816
    }
    c.ground_tris++;

    // SOURCE 1 — LE MATERIAU DE COLLISION, bits 6..11 (pat-h.gc:55). Personne ne les lisait.
    const u32 material = (a.pat >> 6) & 0x3fu;
    const bool mat_ok = material < kPatMaterialCount;
    const bool mat_grass = mat_ok && material == kPatMatGrass;
    if (mat_ok) {
      c.by_material++;
      switch (material) {
        case kPatMatGrass: c.mat_grass++; break;
        case kPatMatSand: c.mat_sand++; break;
        case kPatMatDirt: c.mat_dirt++; break;
        case kPatMatStone: c.mat_stone++; break;
        default: c.mat_other++; break;
      }
    } else {
      c.mat_unnamed++;
    }

    // SOURCE 2 — LE NOM DE LA TEXTURE DE RENDU au-dessus du centroide.
    const float cx = (a.x + b.x + d.x) * (1.0f / 3.0f);
    const float cy = (a.y + b.y + d.y) * (1.0f / 3.0f);
    const float cz = (a.z + b.z + d.z) * (1.0f / 3.0f);
    const s32 tex = tex_at(cx, cy, cz);
    const std::string* tname = nullptr;
    if (tex >= 0 && (size_t)tex < lev.textures.size() && !lev.textures[tex].debug_name.empty()) {
      tname = &lev.textures[tex].debug_name;
    }
    const bool tex_ok = tname != nullptr;
    const bool tex_grass = tex_ok && census_tex_is_grassy(*tname);
    if (tex_ok) {
      c.by_texture++;
      if (tex_grass) {
        c.tex_grass++;
      }
      if (census_tex_is_legacy3(*tname)) {
        c.tex_grass_legacy3++;
      }
    }

    // LE CROISEMENT.
    if (mat_ok && tex_ok) {
      c.by_both++;
    }
    if (mat_ok || tex_ok) {
      c.classified++;
    } else {
      c.unclassified++;
    }
    if (!tex_ok) {
      c.tex_only_unclassified++;
    }
    if (!mat_ok) {
      c.mat_only_unclassified++;
    }

    // LE DESACCORD, DANS LES DEUX SENS, ET IL EST NOMME.
    if (mat_ok && tex_ok && mat_grass != tex_grass) {
      c.disagree++;
      disagree_tex[*tname]++;
      if (mat_grass) {
        c.disagree_mat_grass_tex_not++;
      } else {
        c.disagree_tex_grass_mat_not++;
      }
    }
    if (mat_grass && tex_ok) {
      mat_grass_tex[*tname]++;
    }
    if (tex_grass) {
      const char* mn = pat_material_name(material);
      tex_grass_mat[mn ? std::string(mn) : ("inconnu-" + std::to_string(material))]++;
    }
  }

  c.legacy3_unclassified = c.ground_tris - c.tex_grass_legacy3;
  c.disagree_tex_top = surf_top_names(disagree_tex, 10);
  c.mat_grass_tex_top = surf_top_names(mat_grass_tex, 10);
  c.tex_grass_mat_top = surf_top_names(tex_grass_mat, 10);

  lg::info(
      "[grass-surface-truth] {} : sol={} (collision={}) materiau={} texture={} deux={} "
      "aucune={} desaccord={} rendu={} textures={}",
      level_name, c.ground_tris, c.collision_tris, c.by_material, c.by_texture, c.by_both,
      c.unclassified, c.disagree, c.render_ground_tris, c.textures_seen);
  return c;
}

// ===========================================================================================
// grass-overlay-meshes : LES MESHES POSES PAR-DESSUS UN SOL HERBEUX. Le contrat est dans le .h.
// ===========================================================================================
//
// CE BLOC NE PLACE RIEN. Comme `surface_census`, il ne partage aucune variable avec `scan_level`
// / `expand`, il n'ecrit dans aucune structure cuite et aucun chemin de placement ne l'appelle.

namespace {

// LES SEUILS, NOMMES. Chacun est publie par son terme d'entonnoir : un seuil qui vide la
// population se lit dans `pairs_*`, il ne se devine pas apres coup.
constexpr float OVL_MIN_AREA_M2 = 0.05f;    // aire de recouvrement minimale, en m^2
constexpr double OVL_MIN_AREA_FRAC = 0.05;  // ... et fraction du plus petit des deux triangles
constexpr float OVL_YGAP_M = 1.0f;          // au-dela, deux etages (un pont), pas une superposition
constexpr float OVL_ZFIGHT_M = 0.01f;       // en deca, le dessus est INDECIDABLE
constexpr float OVL_COLL_YWIN_M = 1.5f;     // fenetre verticale de la sonde de collision

// « SABLE OU TERRE » AU SENS DU CONTRAT. Un filet de noms, publie tel quel par les listes de
// textures de chaque classe : ce qu'il rate se voit dans `ambiguous_tex`, pas dans un silence.
inline bool ovl_tex_is_bare(const std::string& n) {
  return n.find("sand") != std::string::npos || n.find("dirt") != std::string::npos ||
         n.find("mud") != std::string::npos || n.find("soil") != std::string::npos ||
         n.find("gravel") != std::string::npos || n.find("earth") != std::string::npos;
}

// Un materiau de collision sur lequel le JEU LUI-MEME a fait autre chose que de l'herbe.
inline bool ovl_material_is_path(u32 m) {
  return pat_material_is_bare(m);
}

// AIRE ET CENTROIDE DU RECOUVREMENT XZ DE DEUX TRIANGLES (Sutherland-Hodgman + lacet).
// EN DOUBLE, ET CE N'EST PAS UN LUXE : les coordonnees montent a ~1e6 unites, leurs produits a
// 1e12, et un float n'a que ~7 chiffres — l'aire d'un recouvrement de 0,05 m^2 (8,4e5 unites^2)
// disparaitrait dans l'erreur d'arrondi de la difference.
double surf_tri_overlap_area(const double A[3][2], const double B[3][2], double& out_cx,
                             double& out_cz) {
  double poly[8][2];
  int n = 3;
  for (int i = 0; i < 3; ++i) {
    poly[i][0] = A[i][0];
    poly[i][1] = A[i][1];
  }
  const double bs = 0.5 * ((B[1][0] - B[0][0]) * (B[2][1] - B[0][1]) -
                           (B[2][0] - B[0][0]) * (B[1][1] - B[0][1]));
  if (std::fabs(bs) < 1e-9) {
    return 0.0;
  }
  static const int kEdge[3][2] = {{0, 1}, {1, 2}, {2, 0}};
  for (int e = 0; e < 3 && n >= 3; ++e) {
    double x0 = B[kEdge[e][0]][0], y0 = B[kEdge[e][0]][1];
    double x1 = B[kEdge[e][1]][0], y1 = B[kEdge[e][1]][1];
    if (bs < 0) {  // toujours dans le sens trigonometrique : « interieur » = « a gauche »
      std::swap(x0, x1);
      std::swap(y0, y1);
    }
    const double ex = x1 - x0, ey = y1 - y0;
    double out[8][2];
    int m = 0;
    for (int i = 0; i < n && m < 7; ++i) {
      const double* P = poly[i];
      const double* Q = poly[(i + 1) % n];
      const double sp = ex * (P[1] - y0) - ey * (P[0] - x0);
      const double sq = ex * (Q[1] - y0) - ey * (Q[0] - x0);
      if (sp >= 0.0) {
        out[m][0] = P[0];
        out[m][1] = P[1];
        ++m;
      }
      if ((sp > 0.0 && sq < 0.0) || (sp < 0.0 && sq > 0.0)) {
        const double t = sp / (sp - sq);
        out[m][0] = P[0] + t * (Q[0] - P[0]);
        out[m][1] = P[1] + t * (Q[1] - P[1]);
        ++m;
      }
    }
    n = m;
    for (int i = 0; i < n; ++i) {
      poly[i][0] = out[i][0];
      poly[i][1] = out[i][1];
    }
  }
  if (n < 3) {
    return 0.0;
  }
  double a2 = 0.0, cx = 0.0, cz = 0.0;
  for (int i = 0; i < n; ++i) {
    const int j = (i + 1) % n;
    const double cr = poly[i][0] * poly[j][1] - poly[j][0] * poly[i][1];
    a2 += cr;
    cx += (poly[i][0] + poly[j][0]) * cr;
    cz += (poly[i][1] + poly[j][1]) * cr;
  }
  if (std::fabs(a2) < 1e-9) {
    return 0.0;
  }
  out_cx = cx / (3.0 * a2);
  out_cz = cz / (3.0 * a2);
  return std::fabs(a2) * 0.5;
}

}  // namespace

OverlayCensus overlay_census(const tfrag3::Level& lev, const std::string& level_name) {
  OverlayCensus c;

  // ---- LA POPULATION : tous les triangles de RENDU qui regardent vers le haut. Le MEME index
  // que `surface_census`, donc aucun ecart de recopie entre les deux items.
  SurfRenderIndex rix;
  surf_build_render_index(lev, rix);
  const size_t n = rix.tris.size();
  c.render_up_tris = (u64)n;
  c.render_big_tris = (u64)rix.big.size();
  c.render_draws = rix.draws;

  // Ce que chaque triangle porte comme NOM, et ce que ce nom dit.
  std::vector<const std::string*> tname(n, nullptr);
  std::vector<u8> grassy(n, 0), bare(n, 0), nongrass(n, 0);
  std::unordered_map<std::string, u64> src_pop;
  for (size_t i = 0; i < n; ++i) {
    const s32 lb = rix.tris[i].label;
    src_pop[ovl_src_name(rix.tris[i].src)]++;
    if (lb >= 0 && (size_t)lb < lev.textures.size() && !lev.textures[lb].debug_name.empty()) {
      tname[i] = &lev.textures[lb].debug_name;
      grassy[i] = census_tex_is_grassy(*tname[i]) ? 1 : 0;
      bare[i] = ovl_tex_is_bare(*tname[i]) ? 1 : 0;
      nongrass[i] = grassy[i] ? 0 : 1;
    }
  }

  // ---- L'INDEX DE COLLISION : le sol declare par le jeu, etiquete par son MATERIAU.
  SurfRenderIndex cix;
  const auto& cv = lev.collision.vertices;
  const size_t ntri = cv.size() / 3;
  for (size_t t = 0; t < ntri; ++t) {
    const auto& a = cv[t * 3 + 0];
    const auto& b = cv[t * 3 + 1];
    const auto& d = cv[t * 3 + 2];
    if (((a.pat >> 3) & 0x7u) != 0) {
      continue;  // pat-mode 0 = ground, la meme porte que surface_census
    }
    c.collision_ground_declared++;
    surf_index_add(cix, a.x, a.y, a.z, b.x, b.y, b.z, d.x, d.y, d.z,
                   (s32)((a.pat >> 6) & 0x3fu), kSrcCollision);
  }
  c.collision_ground_tris = (u64)cix.tris.size();

  const double MIN_AREA = (double)OVL_MIN_AREA_M2 * (double)U * (double)U;
  const double YGAP = (double)OVL_YGAP_M * (double)U;
  const double ZF = (double)OVL_ZFIGHT_M * (double)U;
  const float CYWIN = OVL_COLL_YWIN_M * U;

  // La table des SUPERPOSITIONS TROUVEES, par triangle de rendu : bit 0 = methode A, bit 1 =
  // methode B, bit 2 = ecart sous le z-fighting (le dessus est indecidable).
  std::unordered_map<u32, u8> finding;
  std::unordered_map<std::string, u64> pair_names, pair_srcs;

  auto xz_area = [](const SurfRenderTri& r) {
    return std::fabs(0.5 * ((double)r.e1x * (double)r.e2z - (double)r.e2x * (double)r.e1z));
  };

  // ---- METHODE A : LA GEOMETRIE, SANS PREJUGE.
  auto test_pair = [&](u32 i, u32 j) {
    c.pairs_tested++;
    const auto& A = rix.tris[i];
    const auto& B = rix.tris[j];
    if (A.maxx < B.minx || B.maxx < A.minx || A.maxz < B.minz || B.maxz < A.minz) {
      return;
    }
    c.pairs_bbox++;
    if (A.label == B.label) {
      return;  // meme texture : une seule surface, pas deux meshes
    }
    if (tname[i] && tname[j] && *tname[i] == *tname[j]) {
      return;  // deux entrees de texture, un seul nom : la donnee n'y voit pas deux materiaux
    }
    c.pairs_diff_tex++;
    if (!grassy[i] && !grassy[j]) {
      return;  // le contrat ne retient que les paires dont l'UNE est herbeuse
    }
    c.pairs_one_grassy++;
    const double pa[3][2] = {{A.p0x, A.p0z},
                             {(double)A.p0x + A.e1x, (double)A.p0z + A.e1z},
                             {(double)A.p0x + A.e2x, (double)A.p0z + A.e2z}};
    const double pb[3][2] = {{B.p0x, B.p0z},
                             {(double)B.p0x + B.e1x, (double)B.p0z + B.e1z},
                             {(double)B.p0x + B.e2x, (double)B.p0z + B.e2z}};
    double ox = 0.0, oz = 0.0;
    const double area = surf_tri_overlap_area(pa, pb, ox, oz);
    if (area < MIN_AREA || area < OVL_MIN_AREA_FRAC * std::min(xz_area(A), xz_area(B))) {
      return;  // deux triangles qui se TOUCHENT par une arete ne se superposent pas
    }
    c.pairs_overlap_area++;
    const double dy = surf_tri_y_at(A, ox, oz) - surf_tri_y_at(B, ox, oz);
    if (std::fabs(dy) > YGAP) {
      c.pairs_far_y++;
      return;  // un etage au-dessus d'un autre : un pont, pas un mesh pose par-dessus
    }
    c.pairs_close_y++;
    if (std::fabs(dy) < ZF) {
      // LE DESSUS EST INDECIDABLE. On ne l'arbitre pas : on retient le candidat non herbeux et
      // on le NOMME ambigu.
      c.pairs_coincident++;
      const u32 cand = grassy[i] ? j : i;
      if (!grassy[cand]) {
        finding[cand] |= 4;
      }
      return;
    }
    const u32 top = dy > 0 ? i : j;
    const u32 bot = dy > 0 ? j : i;
    if (grassy[top] && grassy[bot]) {
      c.pairs_both_grassy++;
      return;
    }
    if (grassy[top]) {
      c.pairs_grass_over_bare++;
      return;  // de l'herbe posee sur du nu : l'inverse du cas de l'owner, compte a part
    }
    c.pairs_bare_over_grass++;
    finding[top] |= 1;
    pair_names[(tname[top] ? *tname[top] : std::string("(sans-nom)")) + ">" +
               (tname[bot] ? *tname[bot] : std::string("(sans-nom)"))]++;
    pair_srcs[std::string(ovl_src_name(rix.tris[top].src)) + ">" +
              ovl_src_name(rix.tris[bot].src)]++;
  };

  // Les paires. Un triangle GEANT n'est dans aucune cellule : les paires qui le concernent sont
  // enumerees a part, sinon la moitie du cas de l'owner (une grande pelouse, un petit chemin)
  // serait invisible par construction.
  std::vector<u32> seen(n, UINT32_MAX);
  std::vector<u8> is_big(n, 0);
  for (u32 b : rix.big) {
    is_big[b] = 1;
  }
  for (u32 i = 0; i < (u32)n; ++i) {
    if (is_big[i]) {
      continue;
    }
    const auto& r = rix.tris[i];
    const s64 gx0 = (s64)std::floor(r.minx * rix.binv), gx1 = (s64)std::floor(r.maxx * rix.binv);
    const s64 gz0 = (s64)std::floor(r.minz * rix.binv), gz1 = (s64)std::floor(r.maxz * rix.binv);
    for (s64 gz = gz0; gz <= gz1; ++gz) {
      for (s64 gx = gx0; gx <= gx1; ++gx) {
        auto it = rix.grid.find(((u64)(u32)(s32)gx << 32) | (u32)(s32)gz);
        if (it == rix.grid.end()) {
          continue;
        }
        for (u32 j : it->second) {
          if (j <= i || seen[j] == i) {
            continue;
          }
          seen[j] = i;
          test_pair(i, j);
        }
      }
    }
    for (u32 b : rix.big) {
      test_pair(b < i ? b : i, b < i ? i : b);
    }
  }
  for (size_t bi = 0; bi < rix.big.size(); ++bi) {
    for (size_t bj = bi + 1; bj < rix.big.size(); ++bj) {
      test_pair(rix.big[bi], rix.big[bj]);
    }
  }

  // ---- METHODE B : LA CONTRE-EPREUVE PAR LA COLLISION. Un triangle de collision de materiau
  // `grass` recouvert par un triangle de RENDU texture sable ou terre. Les deux sources ne se
  // copient pas : l'une est le classement des auteurs d'origine, l'autre le nom d'une image.
  for (size_t t = 0; t < cix.tris.size(); ++t) {
    const auto& ct = cix.tris[t];
    if (ct.label != (s32)kPatMatGrass) {
      continue;
    }
    c.method_b_probed++;
    const float px = ct.p0x + (ct.e1x + ct.e2x) / 3.f;
    const float py = ct.p0y + (ct.e1y + ct.e2y) / 3.f;
    const float pz = ct.p0z + (ct.e1z + ct.e2z) / 3.f;
    // SONDE MASQUEE : « le plus proche » rendrait toujours la surface du dessous quand deux
    // meshes sont empiles, donc un mesh POSE PAR-DESSUS ne serait jamais vu.
    //
    // LE MASQUE EST « NON HERBEUX », PAS « QUI S'APPELLE SABLE ». Le filet de noms sable/terre ne
    // rend RIEN sur training : la donnee d'origine y nomme ses sols nus `tra-beachrock`,
    // `jng-smallrocks01`... Chercher le mot « sand » aurait rendu un zero qui ne parle que du
    // filet. Le sous-ensemble dont la texture DIT sable/terre est publie a part.
    const s32 ri =
        surf_index_probe_masked(rix, px, py, pz, CYWIN, nongrass.data(), true, (float)ZF);
    if (ri < 0) {
      // Y avait-il un mesh non herbeux, mais SOUS la collision ? Ce n'est pas « pose par-dessus ».
      if (surf_index_probe_masked(rix, px, py, pz, CYWIN, nongrass.data(), false, 0.f) >= 0) {
        c.method_b_rejected_below++;
      }
      continue;
    }
    c.method_b_coll_tris++;
    if (bare[ri]) {
      c.method_b_named_bare++;
    }
    finding[(u32)ri] |= 2;
  }

  // ---- LA CLASSIFICATION, NOMMEE. L'ordre de parcours est TRIE : une table de hachage ne rend
  // pas deux fois le meme ordre, et un recensement qui change d'ordre change de listes.
  std::vector<u32> fidx;
  fidx.reserve(finding.size());
  for (const auto& kv : finding) {
    fidx.push_back(kv.first);
  }
  std::sort(fidx.begin(), fidx.end());
  c.found = (u64)fidx.size();
  std::unordered_map<std::string, u64> path_names, patch_names, ambig_names, b_names, found_srcs;
  for (u32 ti : fidx) {
    const u8 fl = finding[ti];
    if (fl & 1) {
      c.method_a++;
    }
    if (fl & 2) {
      c.method_b++;
    }
    if ((fl & 3) == 3) {
      c.intersection++;
    }
    const std::string nm = tname[ti] ? *tname[ti] : std::string("(sans-nom)");
    found_srcs[ovl_src_name(rix.tris[ti].src)]++;
    if (fl & 2) {
      b_names[nm]++;
    }
    if (!tname[ti]) {
      c.found_texture_unnamed++;  // temoin : la donnee ne nomme pas l'image, la collision si
    }
    if ((fl & 4) && !(fl & 3)) {
      c.ambig_zfight++;
      ambig_names[nm]++;
      continue;
    }
    const auto& r = rix.tris[ti];
    const float px = r.p0x + (r.e1x + r.e2x) / 3.f;
    const float py = r.p0y + (r.e1y + r.e2y) / 3.f;
    const float pz = r.p0z + (r.e1z + r.e2z) / 3.f;
    const s32 ci = surf_index_probe(cix, px, py, pz, CYWIN);
    if (ci < 0) {
      c.ambig_no_collision++;  // rien dessous : le jeu n'en dit rien, et on le dit
      ambig_names[nm]++;
      continue;
    }
    const u32 mat = (u32)cix.tris[ci].label;
    if (mat >= kPatMaterialCount) {
      c.unclass_material_unnamed++;
      continue;
    }
    if (mat == kPatMatGrass) {
      c.cls_patch++;
      patch_names[nm]++;
    } else if (ovl_material_is_path(mat)) {
      c.cls_path++;
      path_names[nm]++;
    } else {
      c.ambig_material_other++;
      ambig_names[nm]++;
    }
  }
  c.cls_ambiguous = c.ambig_no_collision + c.ambig_material_other + c.ambig_zfight;
  c.unclassified = c.unclass_material_unnamed + c.unclass_no_rule;
  c.sum_check = (c.cls_path + c.cls_patch + c.cls_ambiguous + c.unclassified == c.found) ? 1 : 0;
  c.pair_tex_top = surf_top_names(pair_names, 10);
  c.method_b_tex_top = surf_top_names(b_names, 10);
  c.cls_path_tex_top = surf_top_names(path_names, 10);
  c.cls_patch_tex_top = surf_top_names(patch_names, 10);
  c.ambiguous_tex_top = surf_top_names(ambig_names, 10);
  c.src_population_top = surf_top_names(src_pop, 10);
  c.pair_src_top = surf_top_names(pair_srcs, 10);
  c.found_src_top = surf_top_names(found_srcs, 10);

  lg::info(
      "[grass-overlay-meshes] {} : rendu={} collision={} paires={} retenues={} A={} B={} "
      "inter={} trouve={} chemin={} patch={} ambigu={} aucune={}",
      level_name, c.render_up_tris, c.collision_ground_tris, c.pairs_tested, c.pairs_close_y,
      c.method_a, c.method_b, c.intersection, c.found, c.cls_path, c.cls_patch, c.cls_ambiguous,
      c.unclassified);
  return c;
}

// ---- LE CONTROLE POSITIF. Trois zones fabriquees, trois classes attendues. Il traverse
// `overlay_census()` LUI-MEME : une copie de ses primitives ne prouverait que la copie.
OverlaySelftest overlay_census_selftest() {
  tfrag3::Level lev;
  lev.textures.resize(2);
  lev.textures[0].debug_name = "tra-grass";   // herbeuse (census_tex_is_grassy)
  lev.textures[1].debug_name = "tst-sandpath";  // nue (ovl_tex_is_bare)
  lev.tfrag_trees[0].resize(1);
  auto& tr = lev.tfrag_trees[0][0];
  tr.use_strips = false;

  auto add_tri = [&](float x0, float z0, float side, float y, s32 tex) {
    const u32 base = (u32)tr.unpacked.vertices.size();
    tfrag3::PreloadedVertex v;
    v.x = x0 * U; v.y = y * U; v.z = z0 * U;
    tr.unpacked.vertices.push_back(v);
    v.x = (x0 + side) * U; v.y = y * U; v.z = z0 * U;
    tr.unpacked.vertices.push_back(v);
    v.x = x0 * U; v.y = y * U; v.z = (z0 + side) * U;
    tr.unpacked.vertices.push_back(v);
    tfrag3::StripDraw d;
    d.tree_tex_id = tex;
    d.unpacked.idx_of_first_idx_in_full_buffer = base;
    tfrag3::StripDraw::VisGroup g;
    g.num_inds = 3;
    g.num_tris = 1;
    d.vis_groups.push_back(g);
    tr.draws.push_back(d);
    tr.unpacked.indices.push_back(base + 0);
    tr.unpacked.indices.push_back(base + 1);
    tr.unpacked.indices.push_back(base + 2);
  };
  auto add_coll = [&](float x0, float z0, float side, float y, u32 material) {
    tfrag3::CollisionMesh::Vertex v{};
    v.pat = material << 6;  // pat-mode 0 (ground), materiau dans les bits 6..11
    v.x = x0 * U; v.y = y * U; v.z = z0 * U;
    lev.collision.vertices.push_back(v);
    v.x = (x0 + side) * U; v.y = y * U; v.z = z0 * U;
    lev.collision.vertices.push_back(v);
    v.x = x0 * U; v.y = y * U; v.z = (z0 + side) * U;
    lev.collision.vertices.push_back(v);
  };

  // Trois zones, loin l'une de l'autre : une pelouse, un mesh nu pose 10 cm au-dessus, et ce que
  // la COLLISION dit dessous.
  for (int zone = 0; zone < 3; ++zone) {
    const float ox = 100.f * (float)zone;
    add_tri(ox, 0.f, 20.f, 0.f, 0);          // la pelouse
    add_tri(ox + 2.f, 2.f, 6.f, 0.1f, 1);    // le mesh nu, pose par-dessus
    if (zone == 0) {
      add_coll(ox + 2.f, 2.f, 6.f, 0.f, kPatMatSand);   // le jeu en a fait un vrai chemin
    } else if (zone == 1) {
      add_coll(ox + 2.f, 2.f, 6.f, 0.f, kPatMatGrass);  // la collision dit encore « herbe »
    }
    // zone 2 : AUCUNE collision -> le cas ambigu, nomme.
  }

  const auto oc = overlay_census(lev, "selftest");
  OverlaySelftest r;
  r.method_a = oc.method_a;
  r.method_b = oc.method_b;
  r.intersection = oc.intersection;
  r.found = oc.found;
  r.cls_path = oc.cls_path;
  r.cls_patch = oc.cls_patch;
  r.cls_ambiguous = oc.cls_ambiguous;
  r.unclassified = oc.unclassified;
  r.pairs_tested = oc.pairs_tested;
  // CHAQUE CLASSE DOIT ETRE PRODUITE : une classe morte se voit ici, et un detecteur mort aussi.
  r.ok = (oc.method_a == 3 && oc.method_b == 1 && oc.intersection == 1 && oc.found == 3 &&
          oc.cls_path == 1 && oc.cls_patch == 1 && oc.cls_ambiguous == 1 && oc.unclassified == 0 &&
          oc.sum_check == 1)
             ? 1
             : 0;
  return r;
}

// ===========================================================================================
// grass-edge-truth : LE BORD QUI DONNE SUR LE VIDE, ETABLI PAR LA GEOMETRIE. Contrat dans le .h.
// ===========================================================================================
//
// CE BLOC NE PLACE RIEN. Comme `surface_census` et `overlay_census`, il ne partage aucune
// variable avec `scan_level` / `expand` et aucun chemin de placement ne l'appelle.

namespace {

constexpr u32 kEdgeNoTri = 0xffffffffu;

// Un triangle de SOL (collision, mode 0) prepare pour la sonde XZ et pour les six questions
// que la classification pose de part et d'autre d'une arete.
struct EdgeTri {
  float p0x, p0y, p0z, e1x, e1y, e1z, e2x, e2y, e2z;
  float minx, maxx, minz, maxz;
  float d00, d01, d11, inv_denom;
  float nx, ny, nz;  // normale de face, normalisee et ORIENTEE VERS LE HAUT
  u32 mat;           // pat-material brut (bits 6..11) : la DIFFERENCE se lit meme hors table
  s32 tex;           // index de texture de rendu au centroide, ou -1
  s64 cgx, cgz;      // maille de chunk du centroide
  u8 legacy;         // la texture porte l'un des TROIS noms historiques
};

struct EdgeFloorIndex {
  std::vector<EdgeTri> tris;
  std::unordered_map<u64, std::vector<u32>> grid;
  std::vector<u32> big;
  float binv = 1.0f / (EDGE_BUCKET_M * U);
};

// LA SONDE DE PLANCHER. Rend le sol marchable le plus HAUT a la verticale de (px,pz) dans la
// fenetre [py-drop, py+up], en excluant `skip` (son propre triangle). `any_below` dit qu'un sol
// existe PLUS BAS que la fenetre : « rien du tout » et « trop loin sous les pieds » ne sont pas
// le meme vide, et les deux sont publies.
//
// AUCUNE TOLERANCE BARYCENTRIQUE. `floor_gap` s'en donne une pour qu'un brin pose exactement sur
// une couture ne passe pas au travers ; ici le point sonde est a 35 cm de l'arete, jamais sur une
// couture, et une tolerance de 0,02 sur un triangle de 10 m deborderait de 20 cm — de quoi faire
// dire « le sol continue » a un vrai coin convexe.
s32 edge_floor_probe(const EdgeFloorIndex& ix, float px, float py, float pz, float drop, float up,
                     u32 skip, bool* any_below, bool* selfhit) {
  s32 best = -1;
  float bestY = -1e30f;
  auto probe = [&](u32 ri) {
    const auto& r = ix.tris[ri];
    if (px < r.minx || px > r.maxx || pz < r.minz || pz > r.maxz) {
      return;
    }
    const float qx = px - r.p0x, qz = pz - r.p0z;
    const float d20 = qx * r.e1x + qz * r.e1z;
    const float d21 = qx * r.e2x + qz * r.e2z;
    const float u = (r.d11 * d20 - r.d01 * d21) * r.inv_denom;
    const float v = (r.d00 * d21 - r.d01 * d20) * r.inv_denom;
    if (u < 0.f || v < 0.f || u + v > 1.f) {
      return;
    }
    const float y = r.p0y + u * r.e1y + v * r.e2y;
    if (ri == skip) {
      if (selfhit) {
        *selfhit = true;
      }
      return;
    }
    if (y < py - drop) {
      if (any_below) {
        *any_below = true;
      }
      return;
    }
    if (y > py + up) {
      return;
    }
    if (y > bestY) {
      bestY = y;
      best = (s32)ri;
    }
  };
  const s64 gx = (s64)std::floor(px * ix.binv), gz = (s64)std::floor(pz * ix.binv);
  auto it = ix.grid.find(((u64)(u32)(s32)gx << 32) | (u32)(s32)gz);
  if (it != ix.grid.end()) {
    for (u32 ri : it->second) {
      probe(ri);
    }
  }
  for (u32 ri : ix.big) {
    probe(ri);
  }
  return best;
}

// Ce qu'on sait d'une arete unique du sol. `owner` est le PLUS PETIT indice de triangle qui la
// porte : l'ordre de parcours ne doit rien au hachage.
struct EdgeRec {
  u32 owner = kEdgeNoTri;
  u8 owner_e = 0;
  u32 deg = 0;          // triangles de sol qui la partagent
  u32 legacy_deg = 0;   // ... dont la texture porte l'un des trois noms historiques
  u64 wall_mat_bits = 0;  // materiaux des triangles NON marchables qui la partagent (6 bits -> u64)
  u8 cls = kEdgeClassNone;
};

// La soudure canonique a 3 cm, sur TOUS les sommets de collision — murs compris, sans quoi la
// face de chute d'une terrasse ne partagerait pas l'arete de son sommet.
struct EdgeWeld {
  std::vector<float> x, y, z;
  std::unordered_map<u64, std::vector<u32>> cells;
  float inv = 1.0f / (EDGE_WELD_M * U);
  static u64 key(s64 gx, s64 gy, s64 gz) {
    return ((u64)((u32)(s32)gx & 0x1fffffu) << 42) | ((u64)((u32)(s32)gy & 0x1fffffu) << 21) |
           ((u64)((u32)(s32)gz & 0x1fffffu));
  }
  u32 add(float px, float py, float pz) {
    const s64 gx = (s64)std::floor(px * inv), gy = (s64)std::floor(py * inv),
              gz = (s64)std::floor(pz * inv);
    const float tol = EDGE_WELD_M * U;
    for (s64 dz = -1; dz <= 1; ++dz) {
      for (s64 dy = -1; dy <= 1; ++dy) {
        for (s64 dx = -1; dx <= 1; ++dx) {
          auto it = cells.find(key(gx + dx, gy + dy, gz + dz));
          if (it == cells.end()) {
            continue;
          }
          for (u32 vi : it->second) {
            if (std::fabs(x[vi] - px) <= tol && std::fabs(y[vi] - py) <= tol &&
                std::fabs(z[vi] - pz) <= tol) {
              return vi;
            }
          }
        }
      }
    }
    const u32 vi = (u32)x.size();
    x.push_back(px);
    y.push_back(py);
    z.push_back(pz);
    cells[key(gx, gy, gz)].push_back(vi);
    return vi;
  }
};

inline u64 edge_key(u32 a, u32 b) {
  return a < b ? (((u64)a << 32) | b) : (((u64)b << 32) | a);
}

}  // namespace

const char* edge_class_name(u8 cls) {
  switch (cls) {
    case kEdgeTriangle: return "limite-de-triangle";
    case kEdgeUvSeam: return "couture-uv";
    case kEdgeMaterial: return "separation-de-materiau";
    case kEdgeNormalBreak: return "rupture-de-normale";
    case kEdgeChunk: return "limite-de-chunk";
    case kEdgeOverlay: return "limite-de-mesh-superpose";
    case kEdgePath: return "transition-vers-un-chemin";
    case kEdgeVoid: return "bord-sur-le-vide";
    default: return "aucune";
  }
}

EdgeCensus edge_census(const tfrag3::Level& lev, const std::string& level_name,
                       const EdgeQuery* queries, size_t n_queries, u8* out_class) {
  EdgeCensus c;
  const float OUT = EDGE_OUT_M * U;
  const float OUT_FAR = EDGE_OUT_FAR_M * U;
  const float DROP = EDGE_DROP_M * U;
  const float DROP_FAR = EDGE_DROP_FAR_M * U;
  const float UP = EDGE_UP_M * U;
  const float NCOS = std::cos(EDGE_NORMAL_DEG * 3.14159265358979f / 180.0f);
  const float CHUNK = CHUNK_MAX_DIAG_M * U;
  const float CYWIN = OVL_COLL_YWIN_M * U;
  const float ZF = OVL_ZFIGHT_M * U;

  // ---- LA SOURCE TEXTURE : le MEME index de rendu que `surface_census` et `overlay_census`.
  // Une deuxieme construction aurait derive, et le desaccord entre items serait devenu un
  // artefact de recopie.
  SurfRenderIndex rix;
  surf_build_render_index(lev, rix);
  std::vector<u8> bare(rix.tris.size(), 0);
  for (size_t i = 0; i < rix.tris.size(); ++i) {
    const s32 ti = rix.tris[i].label;
    if (ti >= 0 && (size_t)ti < lev.textures.size() &&
        ovl_tex_is_bare(lev.textures[ti].debug_name)) {
      bare[i] = 1;
    }
  }

  const auto& cv = lev.collision.vertices;
  const size_t ntri = cv.size() / 3;
  c.collision_tris = (u64)ntri;
  c.verts_raw = (u64)cv.size();

  // ---- LA SOUDURE, sur TOUS les sommets de collision.
  EdgeWeld weld;
  std::vector<u32> wid(cv.size(), 0);
  for (size_t i = 0; i < cv.size(); ++i) {
    wid[i] = weld.add(cv[i].x, cv[i].y, cv[i].z);
  }
  c.verts_welded = (u64)weld.x.size();

  // ---- LA POPULATION : les triangles de sol, et ce qu'ils portent.
  EdgeFloorIndex fx;
  std::vector<u32> tri_src;        // indice du triangle de collision d'origine
  std::vector<std::array<u32, 3>> tri_w;  // ses trois sommets soudes
  fx.tris.reserve(ntri);
  const float PAD = 0.05f * U;
  for (size_t t = 0; t < ntri; ++t) {
    const auto& a = cv[t * 3 + 0];
    const auto& b = cv[t * 3 + 1];
    const auto& d = cv[t * 3 + 2];
    if (((a.pat >> 3) & 0x7u) != 0) {
      continue;  // pat-mode 0 = sol marchable : la MEME porte que GrassBakeCore.cpp:816
    }
    c.mode_ground++;
    EdgeTri r;
    r.p0x = a.x; r.p0y = a.y; r.p0z = a.z;
    r.e1x = b.x - a.x; r.e1y = b.y - a.y; r.e1z = b.z - a.z;
    r.e2x = d.x - a.x; r.e2y = d.y - a.y; r.e2z = d.z - a.z;
    r.d00 = r.e1x * r.e1x + r.e1z * r.e1z;
    r.d01 = r.e1x * r.e2x + r.e1z * r.e2z;
    r.d11 = r.e2x * r.e2x + r.e2z * r.e2z;
    const float denom = r.d00 * r.d11 - r.d01 * r.d01;
    if (std::fabs(denom) < 1e-6f) {
      c.tris_xz_degenerate++;  // EXCLU, et compte : aucune direction sortante n'y est definie
      continue;
    }
    r.inv_denom = 1.0f / denom;
    float nx = r.e1y * r.e2z - r.e1z * r.e2y;
    float ny = r.e1z * r.e2x - r.e1x * r.e2z;
    float nz = r.e1x * r.e2y - r.e1y * r.e2x;
    const float nlen = std::sqrt(nx * nx + ny * ny + nz * nz);
    if (nlen < 1e-3f) {
      c.tris_xz_degenerate++;
      continue;
    }
    const float s = (ny < 0.f ? -1.0f : 1.0f) / nlen;  // orientee vers le haut
    r.nx = nx * s; r.ny = ny * s; r.nz = nz * s;
    r.minx = std::min(a.x, std::min(b.x, d.x)) - PAD;
    r.maxx = std::max(a.x, std::max(b.x, d.x)) + PAD;
    r.minz = std::min(a.z, std::min(b.z, d.z)) - PAD;
    r.maxz = std::max(a.z, std::max(b.z, d.z)) + PAD;
    r.mat = (a.pat >> 6) & 0x3fu;
    const float ccx = (a.x + b.x + d.x) * (1.f / 3.f);
    const float ccy = (a.y + b.y + d.y) * (1.f / 3.f);
    const float ccz = (a.z + b.z + d.z) * (1.f / 3.f);
    const s32 ri = surf_index_probe(rix, ccx, ccy, ccz, SURF_YWIN_M * U);
    r.tex = ri < 0 ? -1 : rix.tris[ri].label;
    r.legacy = 0;
    if (r.tex >= 0 && (size_t)r.tex < lev.textures.size() &&
        census_tex_is_legacy3(lev.textures[r.tex].debug_name)) {
      r.legacy = 1;
    }
    r.cgx = (s64)std::floor(ccx / CHUNK);
    r.cgz = (s64)std::floor(ccz / CHUNK);
    const u32 gi = (u32)fx.tris.size();
    fx.tris.push_back(r);
    tri_src.push_back((u32)t);
    tri_w.push_back({wid[t * 3 + 0], wid[t * 3 + 1], wid[t * 3 + 2]});
    if (r.legacy) {
      c.legacy_tris++;
    }
    const s64 gx0 = (s64)std::floor(r.minx * fx.binv), gx1 = (s64)std::floor(r.maxx * fx.binv);
    const s64 gz0 = (s64)std::floor(r.minz * fx.binv), gz1 = (s64)std::floor(r.maxz * fx.binv);
    if ((gx1 - gx0) > SURF_MAX_SPAN || (gz1 - gz0) > SURF_MAX_SPAN) {
      fx.big.push_back(gi);
    } else {
      for (s64 gz = gz0; gz <= gz1; ++gz) {
        for (s64 gx = gx0; gx <= gx1; ++gx) {
          fx.grid[((u64)(u32)(s32)gx << 32) | (u32)(s32)gz].push_back(gi);
        }
      }
    }
  }
  c.tris_used = (u64)fx.tris.size();
  c.edge_slots = c.tris_used * 3;

  // ---- LES ARETES UNIQUES DU SOL.
  std::unordered_map<u64, EdgeRec> edges;
  edges.reserve(c.tris_used * 2 + 16);
  for (u32 g = 0; g < (u32)fx.tris.size(); ++g) {
    for (u8 e = 0; e < 3; ++e) {
      const u32 va = tri_w[g][e], vb = tri_w[g][(e + 1) % 3];
      auto& rec = edges[edge_key(va, vb)];
      rec.deg++;
      if (fx.tris[g].legacy) {
        rec.legacy_deg++;
      }
      if (rec.owner == kEdgeNoTri || g < rec.owner) {
        rec.owner = g;
        rec.owner_e = e;
      }
    }
  }
  // ---- LES MURS QUI PARTAGENT CES ARETES. Deuxieme passe : on MET A JOUR, on ne CREE pas —
  // seules les aretes du sol nous interessent, et c'est la que se lit la face de chute.
  for (size_t t = 0; t < ntri; ++t) {
    const auto& a = cv[t * 3 + 0];
    if (((a.pat >> 3) & 0x7u) == 0) {
      continue;
    }
    const u32 m = (a.pat >> 6) & 0x3fu;
    const u32 w[3] = {wid[t * 3 + 0], wid[t * 3 + 1], wid[t * 3 + 2]};
    for (int e = 0; e < 3; ++e) {
      auto it = edges.find(edge_key(w[e], w[(e + 1) % 3]));
      if (it != edges.end()) {
        it->second.wall_mat_bits |= (1ull << m);
      }
    }
  }

  // ---- LE PARCOURS, TRIE. Une table de hachage ne rend pas deux fois le meme ordre, et un
  // recensement qui change d'ordre change de listes.
  std::vector<u64> ekeys;
  ekeys.reserve(edges.size());
  for (const auto& kv : edges) {
    ekeys.push_back(kv.first);
  }
  std::sort(ekeys.begin(), ekeys.end());
  c.edges_total = (u64)ekeys.size();

  std::unordered_map<std::string, u64> wall_mat_names, mat_pair_names, void_tex_names, class_names;
  bool selfhit = false;
  for (u64 k : ekeys) {
    auto& rec = edges[k];
    const u32 va = (u32)(k >> 32), vb = (u32)(k & 0xffffffffu);
    if (va == vb) {
      c.edges_zero_length++;
      continue;
    }
    if (rec.deg == 1) {
      c.deg1++;
    } else if (rec.deg == 2) {
      c.deg2++;
    } else {
      c.deg3plus++;
    }
    const EdgeTri& T = fx.tris[rec.owner];
    const float pax = weld.x[va], pay = weld.y[va], paz = weld.z[va];
    const float pbx = weld.x[vb], pby = weld.y[vb], pbz = weld.z[vb];
    const float mx = 0.5f * (pax + pbx), my = 0.5f * (pay + pby), mz = 0.5f * (paz + pbz);
    // Le troisieme sommet du triangle porteur, pour savoir de quel cote est « dehors ».
    const u32 v3 = tri_w[rec.owner][(rec.owner_e + 2) % 3];
    const float rx = weld.x[v3], rz = weld.z[v3];
    // LA DIRECTION SORTANTE : la perpendiculaire XZ a l'arete, du cote oppose au 3e sommet.
    // « s'eloigner du 3e sommet » ne suffit pas : sur un triangle obtus cette direction peut ne
    // jamais franchir l'arete.
    float ex = pbx - pax, ez = pbz - paz;
    const float elen = std::sqrt(ex * ex + ez * ez);
    if (elen < 1e-4f) {
      c.edges_zero_length++;
      continue;
    }
    ex /= elen; ez /= elen;
    float ox = ez, oz = -ex;
    if (ox * (rx - mx) + oz * (rz - mz) > 0.f) {
      ox = -ox; oz = -oz;
    }

    // ---- LA SONDE. C'est ELLE qui designe « l'autre cote », jamais la topologie.
    bool any_below = false;
    const s32 B = edge_floor_probe(fx, mx + ox * OUT, my, mz + oz * OUT, DROP, UP, rec.owner,
                                   &any_below, &selfhit);
    // Deux temoins de sensibilite, dans la MEME course : un seuil au couteau se verrait ici.
    bool dummy = false;
    if (edge_floor_probe(fx, mx + ox * OUT_FAR, my, mz + oz * OUT_FAR, DROP, UP, rec.owner, &dummy,
                         nullptr) < 0) {
      c.void_out_far++;
    }
    if (edge_floor_probe(fx, mx + ox * OUT, my, mz + oz * OUT, DROP_FAR, UP, rec.owner, &dummy,
                         nullptr) < 0) {
      c.void_drop_far++;
    }

    const bool has_beyond = B >= 0;
    if (has_beyond) {
      c.beyond_found++;
    } else {
      c.beyond_missing++;
      if (any_below) {
        c.void_with_far_floor++;
      } else {
        c.void_no_floor_at_all++;
      }
    }
    if (T.tex < 0) {
      c.own_unrendered++;
    }
    if (has_beyond && fx.tris[B].tex < 0) {
      c.beyond_unrendered++;
    }
    if (has_beyond && fx.tris[B].mat >= kPatMaterialCount) {
      c.beyond_mat_unnamed++;
    }
    // LES DEUX ECARTS ENTRE TOPOLOGIE ET GEOMETRIE : la faute des onze rounds, chiffree.
    if (rec.deg <= 1 && has_beyond) {
      c.unshared_but_floor++;
    }
    if (rec.deg >= 2 && !has_beyond) {
      c.shared_but_void++;
    }

    // ---- LES HUIT PREDICATS, EVALUES TOUS LES HUIT.
    const bool b_overlay =
        has_beyond && fx.tris[B].mat == kPatMatGrass &&
        surf_index_probe_masked(rix, mx + ox * OUT, my, mz + oz * OUT, CYWIN, bare.data(), true,
                                ZF) >= 0;
    const bool b_path = has_beyond && !b_overlay && T.mat == kPatMatGrass &&
                        ovl_material_is_path(fx.tris[B].mat);
    const bool b_mat =
        has_beyond && !b_overlay && !b_path && fx.tris[B].mat != T.mat;
    const bool b_norm = has_beyond && !b_overlay && !b_path && !b_mat &&
                        (T.nx * fx.tris[B].nx + T.ny * fx.tris[B].ny + T.nz * fx.tris[B].nz) < NCOS;
    const bool b_uv = has_beyond && !b_overlay && !b_path && !b_mat && !b_norm &&
                      fx.tris[B].tex != T.tex;
    const bool b_chunk = has_beyond && !b_overlay && !b_path && !b_mat && !b_norm && !b_uv &&
                         (fx.tris[B].cgx != T.cgx || fx.tris[B].cgz != T.cgz);
    const bool b_tri =
        has_beyond && !b_overlay && !b_path && !b_mat && !b_norm && !b_uv && !b_chunk;
    const bool b_void = !has_beyond;

    const bool claim[kEdgeClassCount] = {false,   b_tri,     b_uv,      b_mat, b_norm,
                                         b_chunk, b_overlay, b_path,    b_void};
    int nclaim = 0;
    u8 cls = kEdgeClassNone;
    for (int i = 1; i < kEdgeClassCount; ++i) {
      if (claim[i]) {
        nclaim++;
        cls = (u8)i;
      }
    }
    if (nclaim == 0) {
      c.claimed_none++;
    } else if (nclaim > 1) {
      c.claimed_multi++;
      cls = kEdgeClassNone;
    } else {
      c.classified++;
      c.cls[cls]++;
      class_names[edge_class_name(cls)]++;
    }
    rec.cls = cls;

    if (cls == kEdgeMaterial) {
      const char* na = pat_material_name(T.mat);
      const char* nb = pat_material_name(fx.tris[B].mat);
      mat_pair_names[std::string(na ? na : "?") + ">" + std::string(nb ? nb : "?")]++;
    }

    // ---- L'ANCIENNE REGLE, REJOUEE SUR LA MEME ARETE.
    bool old_void = false;
    if (rec.legacy_deg >= 1) {
      c.legacy_edges++;
      old_void = rec.legacy_deg <= 1;
      if (old_void) {
        c.old_rule_void++;
      }
      if (b_void) {
        c.geom_void_on_legacy++;
      }
      if (old_void && b_void) {
        c.void_both++;
      } else if (old_void) {
        c.old_only++;
      } else if (b_void) {
        c.geom_only++;
      }
    }

    // ---- LE CAS DU ROUND 4 : la face de chute d'une terrasse.
    if (b_void) {
      if (T.tex >= 0 && (size_t)T.tex < lev.textures.size()) {
        void_tex_names[lev.textures[T.tex].debug_name]++;
      }
      if (rec.wall_mat_bits) {
        c.void_edges_with_wall++;
        for (u32 m = 0; m < 64; ++m) {
          if (rec.wall_mat_bits & (1ull << m)) {
            const char* nm = pat_material_name(m);
            wall_mat_names[nm ? std::string(nm) : ("m" + std::to_string(m))]++;
          }
        }
        if (rec.wall_mat_bits & ~(1ull << kPatMatGrass)) {
          c.terrace_nongrass_void++;
        }
        if (rec.wall_mat_bits & (1ull << kPatMatDirt)) {
          c.terrace_dirt_void++;
          if (old_void) {
            c.terrace_dirt_void_old++;
          }
          if (T.mat == kPatMatGrass) {
            c.terrace_dirt_on_grass++;
          }
        }
        if (rec.wall_mat_bits & (1ull << kPatMatSand)) {
          c.terrace_sand_void++;
        }
        if (rec.wall_mat_bits & (1ull << kPatMatStone)) {
          c.terrace_stone_void++;
        }
      }
    }
  }
  if (selfhit) {
    c.probe_selfhit = 1;
  }

  u64 sum = c.edges_zero_length;
  for (int i = 1; i < kEdgeClassCount; ++i) {
    sum += c.cls[i];
  }
  sum += c.claimed_none + c.claimed_multi;
  c.class_sum_check = (sum == c.edges_total) ? 1 : 0;

  c.void_wall_mat_top = surf_top_names(wall_mat_names, 10);
  c.material_pair_top = surf_top_names(mat_pair_names, 10);
  c.void_tex_top = surf_top_names(void_tex_names, 10);
  c.class_top = surf_top_names(class_names, 10);

  // ---- LE CANAL DU BANC NOMME. La classe rendue est celle que CETTE fonction vient de poser.
  if (queries && out_class && n_queries) {
    for (size_t q = 0; q < n_queries; ++q) {
      out_class[q] = kEdgeClassNone;
      const float tol = EDGE_WELD_M * U * 2.f;
      u32 ia = kEdgeNoTri, ib = kEdgeNoTri;
      for (u32 v = 0; v < (u32)weld.x.size(); ++v) {
        if (std::fabs(weld.x[v] - queries[q].ax) <= tol &&
            std::fabs(weld.y[v] - queries[q].ay) <= tol &&
            std::fabs(weld.z[v] - queries[q].az) <= tol) {
          ia = v;
        }
        if (std::fabs(weld.x[v] - queries[q].bx) <= tol &&
            std::fabs(weld.y[v] - queries[q].by) <= tol &&
            std::fabs(weld.z[v] - queries[q].bz) <= tol) {
          ib = v;
        }
      }
      if (ia == kEdgeNoTri || ib == kEdgeNoTri || ia == ib) {
        continue;
      }
      auto it = edges.find(edge_key(ia, ib));
      if (it != edges.end()) {
        out_class[q] = it->second.cls;
      }
    }
  }

  lg::info(
      "[grass-edge-truth] {} : sol={} aretes={} classees={} vide={} materiau={} chemin={} "
      "superpose={} normale={} uv={} chunk={} triangle={} | ancienne-regle={} vide-seul-geom={} "
      "vide-seul-ancienne={} terrasse-terre={}",
      level_name, c.tris_used, c.edges_total, c.classified, c.cls[kEdgeVoid],
      c.cls[kEdgeMaterial], c.cls[kEdgePath], c.cls[kEdgeOverlay], c.cls[kEdgeNormalBreak],
      c.cls[kEdgeUvSeam], c.cls[kEdgeChunk], c.cls[kEdgeTriangle], c.old_rule_void, c.geom_only,
      c.old_only, c.terrace_dirt_void);
  return c;
}

// -------------------------------------------------------------------------------------------
// LE BANC NOMME : dix cas geometriques, dix-neuf aretes, les reponses ecrites AVANT la course.
// -------------------------------------------------------------------------------------------
namespace {

void edge_add_quad(tfrag3::Level& lev, float x0, float z0, float x1, float z1, float y00,
                   float y10, float y11, float y01, u32 mat, u32 mode) {
  const float P[4][3] = {{x0, y00, z0}, {x1, y10, z0}, {x1, y11, z1}, {x0, y01, z1}};
  const int TRI[2][3] = {{0, 1, 2}, {0, 2, 3}};
  for (auto& t : TRI) {
    for (int k = 0; k < 3; ++k) {
      tfrag3::CollisionMesh::Vertex v{};
      v.x = P[t[k]][0] * U;
      v.y = P[t[k]][1] * U;
      v.z = P[t[k]][2] * U;
      v.pat = (mat << 6) | (mode << 3);
      lev.collision.vertices.push_back(v);
    }
  }
}

void edge_add_flat(tfrag3::Level& lev, float x0, float z0, float x1, float z1, float y, u32 mat,
                   u32 mode) {
  edge_add_quad(lev, x0, z0, x1, z1, y, y, y, y, mat, mode);
}

EdgeQuery edge_q(float ax, float ay, float az, float bx, float by, float bz) {
  return EdgeQuery{ax * U, ay * U, az * U, bx * U, by * U, bz * U};
}

}  // namespace

EdgeSelftest edge_probe_selftest() {
  EdgeSelftest r;
  struct Case {
    const char* name;
    u8 expect;
  };
  std::vector<std::string> verdicts, disagreements;

  auto run = [&](tfrag3::Level& lev, const std::vector<EdgeQuery>& qs,
                 const std::vector<Case>& cases) {
    std::vector<u8> got(qs.size(), kEdgeClassNone);
    edge_census(lev, "selftest", qs.data(), qs.size(), got.data());
    for (size_t i = 0; i < cases.size(); ++i) {
      r.cases++;
      if (cases[i].expect == kEdgeVoid) {
        r.expect_void++;
      } else {
        r.expect_floor++;
      }
      verdicts.push_back(std::string(cases[i].name) + ":" + edge_class_name(got[i]));
      if (got[i] == kEdgeClassNone) {
        r.not_found++;
        r.disagree++;
        disagreements.push_back(std::string(cases[i].name) + ":" +
                                edge_class_name(cases[i].expect) + ">jamais-vue");
      } else if (got[i] != cases[i].expect) {
        r.disagree++;
        disagreements.push_back(std::string(cases[i].name) + ":" +
                                edge_class_name(cases[i].expect) + ">" + edge_class_name(got[i]));
      } else {
        r.agree++;
      }
    }
  };

  // 1. PLATEFORME ETROITE — une bande de 1 m sur 6 m, seule. Son grand cote donne sur le vide ;
  //    sa diagonale interne ne donne sur rien du tout.
  {
    tfrag3::Level lev;
    edge_add_flat(lev, 0, 0, 1, 6, 0, kPatMatGrass, 0);
    run(lev, {edge_q(0, 0, 0, 0, 0, 6), edge_q(0, 0, 0, 1, 0, 6)},
        {{"plateforme_etroite", kEdgeVoid}, {"plateforme_etroite_diagonale", kEdgeTriangle}});
  }
  // 2 & 3. COINS CONVEXE ET CONCAVE — un L de trois carres. Au coin concave (2,2), deux aretes
  //    se touchent et la reponse doit etre OPPOSEE : celle qui sort donne sur le vide, celle qui
  //    est partagee ne donne sur rien.
  {
    tfrag3::Level lev;
    edge_add_flat(lev, 0, 0, 2, 2, 0, kPatMatGrass, 0);
    edge_add_flat(lev, 2, 0, 4, 2, 0, kPatMatGrass, 0);
    edge_add_flat(lev, 0, 2, 2, 4, 0, kPatMatGrass, 0);
    run(lev,
        {edge_q(4, 0, 0, 4, 0, 2), edge_q(2, 0, 0, 4, 0, 0), edge_q(2, 0, 2, 2, 0, 4),
         edge_q(2, 0, 0, 2, 0, 2)},
        {{"coin_convexe_est", kEdgeVoid},
         {"coin_convexe_nord", kEdgeVoid},
         {"coin_concave_sortant", kEdgeVoid},
         {"coin_concave_partage", kEdgeTriangle}});
  }
  // 4. ILOT — un carre de 2 m isole.
  {
    tfrag3::Level lev;
    edge_add_flat(lev, 0, 0, 2, 2, 0, kPatMatGrass, 0);
    run(lev, {edge_q(0, 0, 0, 2, 0, 0), edge_q(0, 0, 0, 2, 0, 2)},
        {{"ilot", kEdgeVoid}, {"ilot_diagonale", kEdgeTriangle}});
  }
  // 5. PENTE PRES D'UNE FALAISE — un plat, puis une pente a 37 degres qui s'arrete dans le vide.
  //    Le bas de la pente est un bord ; sa jonction avec le plat est une RUPTURE DE NORMALE, pas
  //    un bord — c'est exactement la confusion que l'owner interdit.
  {
    tfrag3::Level lev;
    edge_add_flat(lev, 0, 0, 4, 2, 0, kPatMatGrass, 0);
    edge_add_quad(lev, 0, 2, 4, 6, 0, 0, -3, -3, kPatMatGrass, 0);
    run(lev, {edge_q(0, -3, 6, 4, -3, 6), edge_q(0, 0, 2, 4, 0, 2)},
        {{"pente_pres_falaise", kEdgeVoid}, {"pente_jonction", kEdgeNormalBreak}});
  }
  // 6. SURFACES EMPILEES — une marche de 40 cm n'est pas un bord ; un etage de 3 m en est un.
  {
    tfrag3::Level lev;
    edge_add_flat(lev, 0, 0, 8, 8, 0, kPatMatGrass, 0);
    edge_add_flat(lev, 3, 3, 5, 5, 0.4f, kPatMatGrass, 0);
    run(lev, {edge_q(3, 0.4f, 5, 3, 0.4f, 3)}, {{"surfaces_empilees_marche", kEdgeTriangle}});
  }
  {
    tfrag3::Level lev;
    edge_add_flat(lev, 0, 0, 8, 8, 0, kPatMatGrass, 0);
    edge_add_flat(lev, 3, 3, 5, 5, 3.0f, kPatMatGrass, 0);
    run(lev, {edge_q(3, 3.0f, 5, 3, 3.0f, 3)}, {{"surfaces_empilees_etage", kEdgeVoid}});
  }
  // 7. PONT — le flanc du tablier donne sur le vide ; son about touche la rive SANS partager la
  //    moindre arete avec elle. C'est le cas ou la topologie ment et la geometrie dit vrai.
  {
    tfrag3::Level lev;
    edge_add_flat(lev, 0, 0, 4, 6, 0, kPatMatGrass, 0);
    edge_add_flat(lev, 10, 0, 14, 6, 0, kPatMatGrass, 0);
    edge_add_flat(lev, 4, 2, 10, 4, 0, kPatMatGrass, 0);
    run(lev, {edge_q(4, 0, 2, 10, 0, 2), edge_q(4, 0, 2, 4, 0, 4)},
        {{"pont_flanc", kEdgeVoid}, {"pont_about", kEdgeTriangle}});
  }
  // 8. SURPLOMB — un sol existe bien en dessous, trois metres plus bas : c'est un bord quand meme.
  {
    tfrag3::Level lev;
    edge_add_flat(lev, 0, 0, 10, 10, -3, kPatMatGrass, 0);
    edge_add_flat(lev, 2, 2, 6, 6, 0, kPatMatGrass, 0);
    run(lev, {edge_q(6, 0, 2, 6, 0, 6)}, {{"surplomb", kEdgeVoid}});
  }
  // 9. CAVITE — un trou de 2 m au milieu d'un plancher de 6 m. Le rebord du trou est un bord ;
  //    une couture entre deux dalles pleines n'en est pas un.
  {
    tfrag3::Level lev;
    for (int gx = 0; gx < 3; ++gx) {
      for (int gz = 0; gz < 3; ++gz) {
        if (gx == 1 && gz == 1) {
          continue;
        }
        edge_add_flat(lev, gx * 2.f, gz * 2.f, gx * 2.f + 2.f, gz * 2.f + 2.f, 0, kPatMatGrass, 0);
      }
    }
    run(lev, {edge_q(2, 0, 2, 2, 0, 4), edge_q(2, 0, 0, 2, 0, 2)},
        {{"cavite_rebord", kEdgeVoid}, {"cavite_couture", kEdgeTriangle}});
  }
  // 10. BORD PARTIELLEMENT MASQUE — une dalle NON MARCHABLE (mode 2) posee juste au-dela de
  //     l'arete ne comble pas le vide ; une dalle marchable, si.
  {
    tfrag3::Level lev;
    edge_add_flat(lev, 0, 0, 4, 4, 0, kPatMatGrass, 0);
    edge_add_flat(lev, 4, 0, 6, 4, 0, kPatMatStone, 2);
    edge_add_flat(lev, 0, 6, 4, 10, 0, kPatMatGrass, 0);
    edge_add_flat(lev, 4, 6, 6, 10, 0, kPatMatGrass, 0);
    run(lev, {edge_q(4, 0, 0, 4, 0, 4), edge_q(4, 0, 6, 4, 0, 10)},
        {{"bord_masque", kEdgeVoid}, {"bord_masque_controle", kEdgeTriangle}});
  }

  std::string vl, dl;
  for (const auto& s : verdicts) {
    vl += (vl.empty() ? "" : ",") + s;
  }
  for (const auto& s : disagreements) {
    dl += (dl.empty() ? "" : ",") + s;
  }
  r.verdict_list = vl.empty() ? "-" : vl;
  r.disagree_list = dl.empty() ? "-" : dl;
  // LES DEUX POLARITES DOIVENT EXISTER : un banc qui n'attendrait que « vide » serait vert pour
  // une sonde qui repond toujours « vide ».
  r.ok = (r.disagree == 0 && r.expect_void > 0 && r.expect_floor > 0) ? 1 : 0;
  lg::info("[grass-edge-truth] banc nomme : {} cas, {} d'accord, {} desaccords ({})", r.cases,
           r.agree, r.disagree, r.disagree_list);
  return r;
}

// ===========================================================================================
// grass-path-transitions : LE RECENSEMENT. Le contrat est dans GrassBakeCore.h.
// ===========================================================================================
//
// CE BLOC NE PLACE RIEN. Il lit `path_q`, `keep`, `tri_n` et les brins EMIS, et il mesure. Il ne
// relit aucune de ses propres constantes de placement pour juger : `TRANS_DENS_FLOOR`,
// `TRANS_NOISE_AMP_M` et `TRANS_W_M` n'apparaissent dans aucune des quatre grandeurs. Ce qu'il
// lit, ce sont des POSITIONS et des DISTANCES GEOMETRIQUES a l'empreinte du sol nu.

TransitionCensus transition_census(const BakeData& d, const ExpandResult& e) {
  TransitionCensus c;
  c.bare_draws_geom = d.stats.trans_bare_geom;
  c.bare_draws_mat = d.stats.trans_bare_mat;
  c.bare_draws_both = d.stats.trans_bare_both;
  c.bare_draws_disagree = d.stats.trans_bare_disagree;
  c.bare_draws_seen = (u64)d.stats.trans_bare_geom + (u64)d.stats.trans_bare_disagree +
                      (u64)d.stats.trans_bare_mat;
  c.bare_tris = d.stats.trans_bare_tris;
  c.bare_area_m2 = (double)d.stats.trans_bare_area_m2;
  c.occ_pts_object = d.stats.trans_occ_object;
  c.occ_pts_removed = d.stats.trans_occ_moved;
  c.bare_tex_top = d.stats.bare_tex_top.empty() ? "-" : d.stats.bare_tex_top;
  c.bare_rej_top = d.stats.bare_rej_top.empty() ? "-" : d.stats.bare_rej_top;
  c.bare_mat_top = d.stats.bare_mat_top.empty() ? "-" : d.stats.bare_mat_top;
  c.faces_up = d.stats.faces_up;
  c.faces_bare_mat = d.stats.faces_bare_mat;
  c.faces_affleurantes = d.stats.faces_affleurantes;
  c.faces_lifted = d.stats.faces_lifted;
  c.faces_nofloor = d.stats.faces_nofloor;
  c.blades_total = e.instances.size();
  c.population_empty = e.instances.empty() ? 1 : 0;
  c.bare_absent = (c.bare_tris == 0) ? 1 : 0;

  const bool have_path = d.path_q.size() == d.keep.size();
  const bool have_map = e.inst_cand.size() == e.instances.size() && e.tri_n.size() == d.tris.size();
  if (!have_path || !have_map || c.population_empty || c.bare_absent) {
    lg::warn(
        "[grass-path-transitions] recensement IMPOSSIBLE : path_q={} keep={} inst_cand={} "
        "instances={} tri_n={} tris={} empreinte={} — aucune grandeur n'est publiee, et ce n'est "
        "PAS un zero",
        d.path_q.size(), d.keep.size(), e.inst_cand.size(), e.instances.size(), e.tri_n.size(),
        d.tris.size(), c.bare_tris);
    return c;
  }

  // ---- LA GRILLE DES BRINS EMIS (requete « le brin le plus proche »), maille 0,5 m.
  const float NCELL = 0.5f * U;
  const float ninv = 1.0f / NCELL;
  auto nkey = [ninv](float x, float z) -> u64 {
    const s64 gx = (s64)std::floor(x * ninv), gz = (s64)std::floor(z * ninv);
    return ((u64)(u32)(s32)gx << 32) | (u32)(s32)gz;
  };
  std::unordered_map<u64, std::vector<u32>> blade_grid;
  blade_grid.reserve(e.instances.size() / 4 + 16);
  for (u32 k = 0; k < (u32)e.instances.size(); ++k) {
    blade_grid[nkey(e.instances[k].px, e.instances[k].pz)].push_back(k);
  }

  // ---- LA GRILLE DU RECENSEMENT DE DENSITE LOCALE (points 3 et 4), maille TRANS_CELL_M.
  struct Cell {
    u32 cand = 0, kept = 0;
    double sum_d = 0.0, sum_h = 0.0;
  };
  std::unordered_map<u64, Cell> cells;
  const float CINV = 1.0f / (TRANS_CELL_M * U);
  auto ckey = [CINV](float x, float z) -> u64 {
    const s64 gx = (s64)std::floor(x * CINV), gz = (s64)std::floor(z * CINV);
    return ((u64)(u32)(s32)gx << 32) | (u32)(s32)gz;
  };

  // ---- PARCOURS APPARIE : les candidats dans l'ordre d'enumeration, le curseur des brins emis
  // dans le meme ordre. `inst_cand` est strictement croissant, donc un seul curseur suffit.
  std::vector<float> gaps;
  gaps.reserve(4096);
  double band_kept[4] = {0, 0, 0, 0}, band_cand[4] = {0, 0, 0, 0}, band_h[4] = {0, 0, 0, 0};
  double band_elig[4] = {0, 0, 0, 0};  // candidats que plancher ET objet ont laisses passer
  double interior_h_sum = 0.0;
  u64 interior_h_n = 0;
  size_t cursor = 0;
  const float LIMIT = TRANS_LIMIT_BAND_M * U;
  const float W = TRANS_W_M * U;

  struct Limit {
    float x, z;
  };
  std::vector<Limit> limits;
  limits.reserve(4096);
  // TOUS les candidats, avec leurs bits : c'est ce qui permet de NOMMER la cause d'un trou au lieu
  // de l'ecarter en silence.
  struct CandRec {
    float x, z;
    u8 k;        // bits keep 1/2/4
    u8 inside;   // 1 = sous l'empreinte nue : ce candidat N'A PAS a porter d'herbe
  };
  std::vector<CandRec> cand_rec;
  cand_rec.reserve(d.keep.size());
  std::unordered_map<u64, std::vector<u32>> cand_grid;

  // grass-clumps : le recensement recalcule la position des candidats qu'AUCUN brin ne represente.
  // Il doit le faire avec la MEME classe et dans le MEME ordre que l'expansion, sinon `pos_mismatch`
  // accuserait le placement d'une divergence qui serait la sienne.
  ClumpPlacer tplacer(d.total_area_m2, e.clumped);
  for (size_t tj = 0; tj < d.tris.size(); ++tj) {
    const BakeTri& tri = d.tris[tj];
    const u32 n = e.tri_n[tj];
    tplacer.begin(tri);
    for (u32 i = 0; i < n; ++i) {
      const u64 ci = tri.cand_base + (u64)i;
      if (ci >= d.keep.size()) {
        break;
      }
      ClumpSite tsite;
      tplacer.place(tri, (int)i, tsite);
      const float r1 = tsite.r1, r2 = tsite.r2;
      const float bx = tri.p0[0] + r1 * tri.e1[0] + r2 * tri.e2[0];
      const float bz = tri.p0[2] + r1 * tri.e1[2] + r2 * tri.e2[2];
      const u16 pq = d.path_q[ci];
      const float dist = path_decode(pq);
      const bool emitted = cursor < e.inst_cand.size() && e.inst_cand[cursor] == (u32)ci;
      float height = 0.f;
      if (emitted) {
        const auto& gi = e.instances[cursor];
        if (std::fabs(gi.px - bx) > 1.0f || std::fabs(gi.pz - bz) > 1.0f) {
          c.pos_mismatch++;
        }
        height = gi.h;
        ++cursor;
      }

      {
        const u32 ri = (u32)cand_rec.size();
        cand_rec.push_back({bx, bz, d.keep[ci], (u8)(pq == 0 ? 1 : 0)});
        cand_grid[nkey(bx, bz)].push_back(ri);
      }
      c.cand_total++;
      if (pq == 0) {
        c.cand_inside++;
        if (emitted) {
          c.blades_inside++;  // POINT 2 : une racine sur le chemin
        }
      } else if (pq != 0xFFFF) {
        if (dist <= LIMIT) {
          c.cand_limit++;
          limits.push_back({bx, bz});
        }
        if (dist <= W) {
          const int b = (int)(dist / (W * 0.25f));
          const int bi = b < 0 ? 0 : (b > 3 ? 3 : b);
          band_cand[bi] += 1.0;
          if ((d.keep[ci] & 3u) == 3u) {
            band_elig[bi] += 1.0;  // le seul denominateur sur lequel la transition ait decide
          }
          if (emitted) {
            band_kept[bi] += 1.0;
            band_h[bi] += (double)height;
          }
        }
      }
      if (emitted) {
        if (pq != 0xFFFF && dist <= W) {
          c.blades_band++;
        } else {
          c.blades_interior++;
          interior_h_sum += (double)height;
          interior_h_n++;
        }
        if (pq != 0xFFFF) {
          c.blades_tested++;
        }
      }

      // Cellule locale : seuls les candidats a portee d'un sol nu decrivent une transition.
      if (pq != 0xFFFF && pq != 0) {
        Cell& cl = cells[ckey(bx, bz)];
        cl.cand++;
        cl.sum_d += (double)dist;
        if (emitted) {
          cl.kept++;
          cl.sum_h += (double)height;
        }
      }
    }
  }
  c.limit_absent = limits.empty() ? 1 : 0;
  c.band_absent = (c.blades_band == 0) ? 1 : 0;

  // ---- POINT 1 : DE LA LIMITE DE LA ZONE NUE AU BRIN LE PLUS PROCHE.
  if (!limits.empty()) {
    for (const auto& L : limits) {
      float best2 = 1e30f;
      const s64 gx = (s64)std::floor(L.x * ninv), gz = (s64)std::floor(L.z * ninv);
      for (s64 dz = -1; dz <= 1; ++dz) {
        for (s64 dx = -1; dx <= 1; ++dx) {
          auto it = blade_grid.find(((u64)(u32)(s32)(gx + dx) << 32) | (u32)(s32)(gz + dz));
          if (it == blade_grid.end()) {
            continue;
          }
          for (u32 k : it->second) {
            const float ddx = e.instances[k].px - L.x, ddz = e.instances[k].pz - L.z;
            const float dd2 = ddx * ddx + ddz * ddz;
            if (dd2 < best2) {
              best2 = dd2;
            }
          }
        }
      }
      // Rien dans les neuf cellules = au moins 0,5 m ; on le publie a sa borne INFERIEURE, jamais
      // en l'ecartant : un echantillon ecarte est un echantillon qui ne peut plus rougir.
      gaps.push_back(best2 >= 1e29f ? (0.5f * U) : std::sqrt(best2));
    }
    // ---- POURQUOI. Pour chaque echantillon au-dessus du plafond, on regarde les candidats de son
    // voisinage : s'ils sont tous sans plancher, tous occultes par un objet, ou s'il n'y a aucun
    // candidat d'herbe du tout, le trou n'est pas celui de la transition. La cause DOMINANTE est
    // publiee ; aucune n'est ecartee sans compte.
    std::vector<float> defect_gaps;
    double def_cands = 0.0, def_thin = 0.0;
    for (size_t li = 0; li < limits.size(); ++li) {
      const float g = gaps[li];
      if (g / U <= TRANS_GAP_CAP_M) {
        continue;
      }
      c.gap_over_cap++;
      const float R = g;
      const s64 ring = (s64)std::ceil(R * ninv) + 1;
      const s64 gx = (s64)std::floor(limits[li].x * ninv), gz = (s64)std::floor(limits[li].z * ninv);
      u64 n_nofloor = 0, n_object = 0, n_thin = 0, n_any = 0, n_inside = 0;
      for (s64 dz = -ring; dz <= ring; ++dz) {
        for (s64 dx = -ring; dx <= ring; ++dx) {
          auto it = cand_grid.find(((u64)(u32)(s32)(gx + dx) << 32) | (u32)(s32)(gz + dz));
          if (it == cand_grid.end()) {
            continue;
          }
          for (u32 ri : it->second) {
            const auto& cr = cand_rec[ri];
            const float ddx = cr.x - limits[li].x, ddz = cr.z - limits[li].z;
            if (ddx * ddx + ddz * ddz > R * R) {
              continue;
            }
            n_any++;
            if (cr.inside) {
              n_inside++;   // le chemin lui-meme : l'absence d'herbe y est le SUCCES, pas le trou
            } else if (!(cr.k & 1)) {
              n_nofloor++;
            } else if (!(cr.k & 2)) {
              n_object++;
            } else if (!(cr.k & 4)) {
              n_thin++;
            }
          }
        }
      }
      // LA CAUSE DOMINANTE, et les egalites tranchees CONTRE NOUS : a nombre egal, le trou est
      // impute a la transition. Une regle qui s'accorderait le benefice du doute serait un
      // plafond deguise.
      if (n_any == 0) {
        c.gap_cause_nograss++;
      } else if (n_inside > n_thin && n_inside >= n_nofloor && n_inside >= n_object) {
        c.gap_cause_inside++;
      } else if (n_nofloor > n_thin && n_nofloor >= n_object) {
        c.gap_cause_nofloor++;
      } else if (n_object > n_thin) {
        c.gap_cause_object++;
      } else {
        c.gap_cause_trans++;
        defect_gaps.push_back(g / U);
        def_cands += (double)n_any;
        def_thin += (double)n_thin;
      }
    }
    c.gap_defect_frac = (float)((double)c.gap_cause_trans / (double)limits.size());
    if (c.gap_cause_trans) {
      c.gap_defect_cands = (float)(def_cands / (double)c.gap_cause_trans);
      c.gap_defect_thin = (float)(def_thin / (double)c.gap_cause_trans);
    }
    c.gap_defect_max = defect_gaps.empty() ? 0.f
                                           : *std::max_element(defect_gaps.begin(),
                                                               defect_gaps.end());
    std::sort(gaps.begin(), gaps.end());
    auto q = [&](double f) -> float {
      const size_t idx = (size_t)((double)(gaps.size() - 1) * f + 0.5);
      return gaps[idx] / U;
    };
    c.gap_p50 = q(0.50);
    c.gap_p90 = q(0.90);
    c.gap_p99 = q(0.99);
    c.gap_max = gaps.back() / U;
    c.terms_measured++;
  }

  // ---- POINTS 3 ET 4 : LE FRONT ET LA PROGRESSIVITE, sur les cellules assez peuplees.
  std::vector<float> front_d;
  u64 graded = 0;
  for (const auto& kv : cells) {
    const Cell& cl = kv.second;
    if (cl.cand < TRANS_CELL_MIN_CAND) {
      continue;
    }
    const double mean_d = cl.sum_d / (double)cl.cand;
    if (mean_d > (double)W) {
      continue;
    }
    c.band_cells++;
    const double ratio = (double)cl.kept / (double)cl.cand;
    if (ratio > 0.15 && ratio < 0.85) {
      graded++;
    }
    if (std::fabs(ratio - 0.5) <= 0.12) {
      front_d.push_back((float)mean_d);
    }
  }
  if (c.band_cells > 0) {
    c.graded_frac = (float)((double)graded / (double)c.band_cells);
    c.terms_measured++;
  }
  c.front_cells = front_d.size();
  if (!front_d.empty()) {
    std::sort(front_d.begin(), front_d.end());
    const float med = front_d[front_d.size() / 2];
    c.front_median_m = med / U;
    u64 near = 0;
    for (float v : front_d) {
      if (std::fabs(v - med) <= TRANS_FRONT_EPS_M * U) {
        near++;
      }
    }
    c.edge_follow_frac = (float)((double)near / (double)front_d.size());
    c.terms_measured++;
  }

  // ---- POINT 4 (suite) : les quatre tranches de 25 cm, et la monotonie.
  c.interior_height = interior_h_n ? (float)(interior_h_sum / (double)interior_h_n) : -1.f;
  for (int b = 0; b < 4; ++b) {
    if (band_cand[b] > 0.0) {
      c.band_ratio[b] = (float)(band_kept[b] / band_cand[b]);
      c.band_elig[b] = (float)(band_elig[b] / band_cand[b]);
    }
    if (band_elig[b] > 0.0) {
      c.band_dens[b] = (float)(band_kept[b] / band_elig[b]);
    }
    if (band_kept[b] > 0.0 && c.interior_height > 0.f) {
      c.band_height[b] = (float)((band_h[b] / band_kept[b]) / (double)c.interior_height);
    }
  }
  for (int b = 1; b < 4; ++b) {
    if (c.band_ratio[b] >= 0.f && c.band_ratio[b - 1] >= 0.f &&
        c.band_ratio[b] < c.band_ratio[b - 1] - 0.02f) {
      c.mono_ratio_breaks++;
    }
    if (c.band_dens[b] >= 0.f && c.band_dens[b - 1] >= 0.f &&
        c.band_dens[b] < c.band_dens[b - 1] - 0.02f) {
      c.mono_dens_breaks++;
    }
    if (c.band_height[b] >= 0.f && c.band_height[b - 1] >= 0.f &&
        c.band_height[b] < c.band_height[b - 1] - 0.02f) {
      c.mono_height_breaks++;
    }
  }
  // LA RAMPE DOIT EXISTER. Une transition qui ne descend pas est une transition absente, et une
  // porte qu'une valeur neutre satisfait est verte par inaction.
  if (c.band_dens[0] >= 0.f && c.band_dens[3] > 0.f) {
    c.dens_ramp_missing = (c.band_dens[0] <= TRANS_RAMP_MAX * c.band_dens[3]) ? 0 : 1;
  }
  if (c.band_height[0] >= 0.f && c.band_height[3] > 0.f) {
    c.height_ramp_missing = (c.band_height[0] <= TRANS_RAMP_MAX * c.band_height[3]) ? 0 : 1;
  }
  if (c.band_dens[0] >= 0.f && c.band_dens[3] >= 0.f && c.band_height[0] >= 0.f) {
    c.terms_measured++;
  }

  lg::info(
      "[grass-path-transitions] {} brins ({} dans la bande, {} SUR le chemin) ; bande nue p50={:.3f} "
      "p90={:.3f} p99={:.3f} max={:.3f} m (plafond {:.2f}) ; front {} cellules, suivi={:.3f} ; "
      "gradue={:.3f} ; tranches {:.2f}/{:.2f}/{:.2f}/{:.2f} ; termes mesures={}",
      c.blades_total, c.blades_band, c.blades_inside, c.gap_p50, c.gap_p90, c.gap_p99, c.gap_max,
      TRANS_GAP_CAP_M, c.front_cells, c.edge_follow_frac, c.graded_frac, c.band_ratio[0],
      c.band_ratio[1], c.band_ratio[2], c.band_ratio[3], c.terms_measured);
  return c;
}



// ===========================================================================
// grass-clumps : LE RECENSEMENT.
// ===========================================================================
//
// Point 1 du contrat — « LE REGROUPEMENT EST MESURE, pas affirme ». La statistique est le NOMBRE
// MOYEN DE VOISINS a `CLUMP_PAIR_R_M`, calcule DEUX fois : sur les racines livrees, puis sur les
// racines que le tirage uniforme aurait donnees AUX MEMES BRINS, sur LA MEME surface. Le second
// bras n'est pas un miroir : c'est le code REMPLACE, que `ClumpPlacer::place` continue de calculer
// a cote du placement livre (`ClumpSite::u1/u2`).
//
// POURQUOI LA POPULATION EST RESTREINTE. Un brin dont la racine est a moins de `CLUMP_PAIR_R_M`
// d'une arete de son triangle support a une partie de son voisinage hors du triangle. La compter
// mesurerait le DECOUPAGE DU MAILLAGE — identique dans les deux bras, donc un plancher qui
// rapprocherait le rapport de 1 sans rien dire du regroupement. Le denominateur retenu est publie
// (`pairs_sampled`) : un rapport sans son denominateur ne se relit pas.
ClumpCensus clump_census(const BakeData& d, const ExpandResult& e) {
  ClumpCensus c;
  c.origin_digest = 0;
  c.blades_total = e.instances.size();
  if (e.inst_tri.size() != e.instances.size() || e.inst_cand.size() != e.instances.size()) {
    // Sans la carte brin -> candidat, on ne peut PAS savoir quel candidat un brin represente : on
    // apparierait le premier candidat du triangle au premier brin, en sautant ceux que `keep` a
    // ecartes. `terms_measured` reste a 0 — une mesure absente ne dit pas « zero », elle ne dit
    // RIEN, et le juge lit ce compte avant la somme.
    return c;
  }

  // ---- LES ORIGINES DE TOUTES LES TOUFFES DES TRIANGLES PORTEURS.
  // Independante du palier par construction (`clump_of` ne lit que `t.seed` et `c`), donc
  // comparable d'un bake a l'autre ET d'un chargement a l'autre : c'est le point 4 du contrat.
  {
    ClumpPlacer dig(d.total_area_m2, e.clumped);
    for (const BakeTri& t : d.tris) {
      if (t.flags & (2u | 4u)) {
        continue;  // lip / dup : aucun candidat, donc aucune touffe
      }
      dig.begin(t);
      c.clumps_total += dig.clumps();
    }
    dig.finish();
    c.origin_digest = dig.origin_digest();
  }

  // ---- LES DEUX JEUX DE RACINES, DANS L'ORDRE D'EMISSION.
  struct Root {
    float cx, cy, cz;  // racine livree
    float ux, uy, uz;  // racine du tirage uniforme
    u8 interior;       // a plus de CLUMP_PAIR_R_M de toute arete de son triangle support
  };
  std::vector<Root> roots;
  roots.reserve(e.instances.size());
  std::unordered_map<u64, u32> clump_fill;   // (tri << 32 | clump) -> brins emis
  std::unordered_map<u64, float> clump_rad;  // ... -> rayon (unites monde)
  clump_fill.reserve(e.instances.size() / 2 + 16);
  clump_rad.reserve(e.instances.size() / 2 + 16);
  double h_sum = 0.0, h_flat_sum = 0.0;

  const float PR = CLUMP_PAIR_R_M * U;
  ClumpPlacer placer(d.total_area_m2, e.clumped);
  size_t cursor = 0;
  for (size_t tj = 0; tj < d.tris.size() && cursor < e.instances.size(); ++tj) {
    const BakeTri& tri = d.tris[tj];
    if (tri.flags & (2u | 4u)) {
      continue;
    }
    placer.begin(tri);
    // Combien de candidats l'expansion a-t-elle enumeres sur ce triangle ? `tri_n` le dit quand il
    // est rempli ; sinon on borne par `cand_count`, qui le majore toujours.
    const u32 n = (tj < e.tri_n.size() && !e.tri_n.empty()) ? e.tri_n[tj] : tri.cand_count;
    // Rayons perpendiculaires du triangle : la distance barycentrique a chaque arete vaut
    // w * (2*aire) / longueur_de_l_arete_opposee. On la compare a PR sans quitter le barycentrique.
    const float ax = tri.e1[0], ay = tri.e1[1], az = tri.e1[2];
    const float bx = tri.e2[0], by = tri.e2[1], bz = tri.e2[2];
    const float cx = bx - ax, cy = by - ay, cz = bz - az;
    const float lAB = std::sqrt(ax * ax + ay * ay + az * az);       // arete p0->p0+e1
    const float lAC = std::sqrt(bx * bx + by * by + bz * bz);       // arete p0->p0+e2
    const float lBC = std::sqrt(cx * cx + cy * cy + cz * cz);       // arete opposee a p0
    const float twoA = 2.0f * tri.area_m2 * U * U;
    for (u32 i = 0; i < n; ++i) {
      ClumpSite s;
      placer.place(tri, (int)i, s);
      const u64 ci = tri.cand_base + (u64)i;
      const bool emitted = cursor < e.instances.size() && e.inst_cand[cursor] == (u32)ci;
      if (!emitted) {
        continue;
      }
      const GrassInstance& gi = e.instances[cursor];
      ++cursor;
      const float rx = tri.p0[0] + s.r1 * tri.e1[0] + s.r2 * tri.e2[0];
      const float ry = tri.p0[1] + s.r1 * tri.e1[1] + s.r2 * tri.e2[1];
      const float rz = tri.p0[2] + s.r1 * tri.e1[2] + s.r2 * tri.e2[2];
      if (std::fabs(gi.px - rx) > 1.0f || std::fabs(gi.py - ry) > 1.0f ||
          std::fabs(gi.pz - rz) > 1.0f) {
        c.pos_mismatch++;  // le recensement et l'expansion ne placent pas au meme endroit
      }
      // INTEGRITE DE LA RACINE (SPEC section 9) : un barycentrique negatif = une racine hors de son
      // triangle support. L'ecretage le rend impossible ; on le COMPTE quand meme.
      const float w0 = 1.0f - s.r1 - s.r2;
      if (w0 < -1.0e-3f || s.r1 < -1.0e-3f || s.r2 < -1.0e-3f) {
        c.root_outside++;
      }
      if (s.clip < 1.0f) {
        c.clipped++;
      }
      const float hm = e.clumped ? clump_height_mul(s.rho) : 1.0f;
      h_sum += (double)gi.h;
      h_flat_sum += hm > 1.0e-6f ? (double)gi.h / (double)hm : (double)gi.h;
      if (e.clumped) {
        const u64 key = ((u64)tj << 32) | (u64)s.clump;
        clump_fill[key]++;
        clump_rad[key] = s.radius_wu;
      }
      // Interieur : les trois distances aux aretes au-dessus du rayon de comptage.
      u8 inte = 0;
      if (twoA > 1.0e-3f && lAB > 1.0e-3f && lAC > 1.0e-3f && lBC > 1.0e-3f) {
        const float dBC = w0 * twoA / lBC;
        const float dAC = s.r1 * twoA / lAC;
        const float dAB = s.r2 * twoA / lAB;
        inte = (dBC > PR && dAC > PR && dAB > PR) ? 1u : 0u;
      }
      roots.push_back({rx, ry, rz,
                       tri.p0[0] + s.u1 * tri.e1[0] + s.u2 * tri.e2[0],
                       tri.p0[1] + s.u1 * tri.e1[1] + s.u2 * tri.e2[1],
                       tri.p0[2] + s.u1 * tri.e1[2] + s.u2 * tri.e2[2], inte});
    }
  }
  placer.finish();
  c.clumps_mounted = clump_fill.size();

  // ---- POINT 2 : LES TOUFFES NE SE RESSEMBLENT PAS.
  if (!clump_fill.empty()) {
    double sn = 0, sn2 = 0;
    for (const auto& kv : clump_fill) {
      sn += (double)kv.second;
      sn2 += (double)kv.second * (double)kv.second;
    }
    const double nn = (double)clump_fill.size();
    c.size_mean = sn / nn;
    const double var = std::max(0.0, sn2 / nn - c.size_mean * c.size_mean);
    c.size_cv = c.size_mean > 1e-9 ? std::sqrt(var) / c.size_mean : 0.0;
    double sr = 0, sr2 = 0;
    for (const auto& kv : clump_rad) {
      const double r = (double)kv.second / (double)U;
      sr += r;
      sr2 += r * r;
    }
    const double rn = (double)clump_rad.size();
    c.radius_mean_m = sr / rn;
    const double rvar = std::max(0.0, sr2 / rn - c.radius_mean_m * c.radius_mean_m);
    c.radius_cv = c.radius_mean_m > 1e-9 ? std::sqrt(rvar) / c.radius_mean_m : 0.0;
  }
  c.height_mean_ratio = h_flat_sum > 1e-9 ? h_sum / h_flat_sum : 0.0;

  // ---- POINT 1 : LA DISPERSION SPATIALE, LES DEUX BRAS.
  auto mean_neighbours = [&](bool uniform_arm) -> double {
    const float cell = PR;
    const float inv = 1.0f / cell;
    std::unordered_map<u64, std::vector<u32>> grid;
    grid.reserve(roots.size() * 2 + 16);
    for (u32 k = 0; k < (u32)roots.size(); ++k) {
      const Root& r = roots[k];
      const float px = uniform_arm ? r.ux : r.cx, pz = uniform_arm ? r.uz : r.cz;
      const s64 gx = (s64)std::floor(px * inv), gz = (s64)std::floor(pz * inv);
      grid[((u64)(u32)gx << 32) ^ (u64)(u32)gz].push_back(k);
    }
    const float pr2 = PR * PR;
    double tot = 0.0;
    u64 cnt = 0;
    for (u32 k = 0; k < (u32)roots.size(); ++k) {
      const Root& r = roots[k];
      if (!r.interior) {
        continue;
      }
      const float px = uniform_arm ? r.ux : r.cx;
      const float py = uniform_arm ? r.uy : r.cy;
      const float pz = uniform_arm ? r.uz : r.cz;
      const s64 gx = (s64)std::floor(px * inv), gz = (s64)std::floor(pz * inv);
      u32 hit = 0;
      for (s64 dz = -1; dz <= 1; ++dz) {
        for (s64 dx = -1; dx <= 1; ++dx) {
          auto it = grid.find(((u64)(u32)(gx + dx) << 32) ^ (u64)(u32)(gz + dz));
          if (it == grid.end()) {
            continue;
          }
          for (u32 q : it->second) {
            if (q == k) {
              continue;
            }
            const Root& o = roots[q];
            const float ox = uniform_arm ? o.ux : o.cx;
            const float oy = uniform_arm ? o.uy : o.cy;
            const float oz = uniform_arm ? o.uz : o.cz;
            const float ddx = ox - px, ddy = oy - py, ddz = oz - pz;
            if (ddx * ddx + ddy * ddy + ddz * ddz < pr2) {
              hit++;
            }
          }
        }
      }
      tot += (double)hit;
      cnt++;
    }
    if (!uniform_arm) {
      c.pairs_sampled = cnt;
    }
    return cnt ? tot / (double)cnt : 0.0;
  };
  c.pairs_clumped = mean_neighbours(false);
  c.pairs_uniform = mean_neighbours(true);
  c.pairs_ratio = c.pairs_uniform > 1e-9 ? c.pairs_clumped / c.pairs_uniform : 0.0;

  // ---- COMBIEN DE GRANDEURS ONT UNE POPULATION. Un terme sans population n'est pas « a zero »,
  // il n'est PAS MESURE : le juge lit ce compte avant la somme.
  c.terms_measured = 0;
  if (c.blades_total > 0) c.terms_measured++;
  if (c.pairs_sampled > 0) c.terms_measured++;
  if (c.clumps_mounted > 0) c.terms_measured++;
  if (c.pairs_uniform > 1e-9) c.terms_measured++;
  if (c.clumps_total > 0) c.terms_measured++;
  return c;
}

// ---------------------------------------------------------------------------
// Point 3 du contrat : LES PALIERS RESTENT IMBRIQUES.
// ---------------------------------------------------------------------------
//
// Les deux `BakeData` viennent de deux `scan_level` du MEME `.fr3` : leurs `tris` sont alignes
// index par index, ce qu'on VERIFIE (`tris_misaligned`) au lieu de le supposer. Pour chaque
// triangle porteur on compare le nombre de touffes et chaque origine ; puis on verifie que
// l'ensemble des candidats du palier bas est un PREFIXE de celui du palier haut — la propriete
// dont depend « un palier inferieur retire des brins DANS les memes touffes ».
ClumpNestCensus clump_nest_census(const BakeData& lo, const ExpandResult& elo, const BakeData& hi,
                                  const ExpandResult& ehi) {
  ClumpNestCensus c;
  c.blades_low = elo.instances.size();
  c.blades_high = ehi.instances.size();
  const size_t nt = std::min(lo.tris.size(), hi.tris.size());
  if (lo.tris.size() != hi.tris.size()) {
    c.tris_misaligned += (u64)(std::max(lo.tris.size(), hi.tris.size()) - nt);
  }
  ClumpPlacer plo(lo.total_area_m2, true), phi(hi.total_area_m2, true);
  for (size_t tj = 0; tj < nt; ++tj) {
    const BakeTri& a = lo.tris[tj];
    const BakeTri& b = hi.tris[tj];
    if (a.flags & (2u | 4u)) {
      continue;
    }
    if (a.seed != b.seed || std::fabs(a.area_m2 - b.area_m2) > 1e-4f ||
        std::fabs(a.p0[0] - b.p0[0]) > 1e-3f || std::fabs(a.p0[2] - b.p0[2]) > 1e-3f) {
      c.tris_misaligned++;
      continue;
    }
    c.tris_compared++;
    plo.begin(a);
    phi.begin(b);
    if (plo.clumps() != phi.clumps()) {
      c.count_mismatch++;
    }
    const u32 m = std::min(plo.clumps(), phi.clumps());
    for (u32 k = 0; k < m; ++k) {
      float a1, a2, ar, b1, b2, br;
      ClumpPlacer::clump_of(a, k, a1, a2, ar);
      ClumpPlacer::clump_of(b, k, b1, b2, br);
      c.clumps_compared++;
      // 1 mm monde : l'origine est la MEME, ou elle a bouge.
      const float ox = (a1 - b1) * a.e1[0] + (a2 - b2) * a.e2[0];
      const float oy = (a1 - b1) * a.e1[1] + (a2 - b2) * a.e2[1];
      const float oz = (a1 - b1) * a.e1[2] + (a2 - b2) * a.e2[2];
      if (std::sqrt(ox * ox + oy * oy + oz * oz) > 0.001f * U || std::fabs(ar - br) > 0.001f * U) {
        c.origin_moved++;
      }
    }
    // PREFIXE : le palier bas enumere `n_lo` candidats, le haut `n_hi`. La propriete tient si
    // n_lo <= n_hi ET si les `n_lo` premiers candidats du bas ont la MEME touffe et le MEME rang
    // que ceux du haut — ce que `place()` rend verifiable en les rejouant tous les deux.
    const u32 nlo = tj < elo.tri_n.size() ? elo.tri_n[tj] : 0u;
    const u32 nhi = tj < ehi.tri_n.size() ? ehi.tri_n[tj] : 0u;
    if (nlo > nhi) {
      c.prefix_breaks += (u64)(nlo - nhi);
    }
    const u32 nmin = std::min(nlo, nhi);
    for (u32 i = 0; i < nmin; ++i) {
      ClumpSite sa, sb;
      plo.place(a, (int)i, sa);
      phi.place(b, (int)i, sb);
      if (sa.clump != sb.clump || sa.rank != sb.rank ||
          std::fabs(sa.r1 - sb.r1) > 1e-5f || std::fabs(sa.r2 - sb.r2) > 1e-5f) {
        c.prefix_breaks++;
      }
    }
  }
  plo.finish();
  phi.finish();
  return c;
}

}  // namespace grass_bake
