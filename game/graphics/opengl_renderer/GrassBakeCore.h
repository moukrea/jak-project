#pragma once

// Grecharged-grass-precompute-mode: GL-free shared core for the recharged-grass
// placement pipeline, restructured as SCAN -> TABLES -> EXPAND plus a serializer.
//
// This TU must NOT include any GL/glad/loader/BucketRenderer header — it is also
// compiled into a desktop CLI bake tool. Behaviour is a 1:1 move of the owner-
// validated GrassRenderer::rebuild() code; every float expression, constant,
// ordering and log format is preserved.

#include <cmath>
#include <string>
#include <vector>

#include "common/common_types.h"
#include "common/custom_data/Tfrag3Data.h"
// Ggrass-density-presets: la table des cinq paliers, partagee mot pour mot par le moteur, l'outil de
// cuisson hors-ligne et l'empaqueteur. Feuille pure (aucune inclusion GL / loader) : elle peut donc
// entrer ici, qui est aussi compile dans l'outil de bureau.
#include "game/graphics/grass_density_presets.h"

namespace grass_bake {

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
// Placement constants (moved verbatim from GrassRenderer.cpp anonymous namespace).
// ---------------------------------------------------------------------------
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

// OWNER POLISH#4: hide grass under overlapping non-grass 3D objects (crates/props/models).
// OWNER ROUND#13 (2026-07-11) — SUPERVISOR DIAGNOSIS #2: the block-shaped BALD HOLES the owner saw
// on his OWN (open) platform were the object-hide's 0.5m XZ OCCUPANCY GRID + its 3x3 dilation
// (morphological closing): a single stray TIE vertex hovering in the contact band above the grass
// (e.g. the underside of a nearby/overhead TIE structure) marked a whole 0.5m CELL as occupied, and
// the closing bridged/kept clusters -> 0.5m block-shaped holes on grass with NO object actually on it.
// FIX: NO grid cull, NO dilation. A PER-INSTANCE test — a blade is hidden iff a real TIE object vertex
// lies within OCC_RADIUS of ITS OWN (px,pz) AND in the near-ground contact band [+OCC_LO,+OCC_HI]
// above ITS OWN ground Y. On an open platform (no object vertex within the radius+band) occ_culled ~0
// -> no block holes; culls happen ONLY under an actual prop. The XZ grid below is now just a spatial
// hash to find nearby object points (lookup only), never a cull unit.
constexpr float OCC_CELL_M = 0.5f;        // spatial-hash bucket for object-point lookup (>= OCC_RADIUS)
constexpr float OCC_LO_M = 0.05f;         // object vertex must be at least this far above the grass
// ROUND#13: tightened the contact band 1.5m -> 1.0m so only object geometry that actually comes DOWN
// near the grass surface hides it; overhead TIE structure (>1m up) no longer culls the grass below it
// (that was a source of the stray block holes). POLISH#7 kept only the visible above-ground footprint.
constexpr float OCC_HI_M = 1.0f;          // near-ground contact band top = visible footprint (was 1.5m)
constexpr float OCC_RADIUS_M = 0.45f;     // ROUND#13: per-instance hide radius (m) — a blade is culled
                                          // only if an object vertex is this close to ITS OWN base
                                          // (no 0.5m cell nuking, no neighbour dilation)

// ROUND#19 cantilever cull v2 (owner round#18 verdict: blades still hang in the VOID past platform
// rims). Point-wise per-blade test: a blade exists only if there is WALKABLE COLLISION FLOOR directly
// below its base. No 2D silhouette, no edge detection, no rim distance -> the round#17 "50cm straight
// bald strips" (collision-vs-render silhouette divergence along straight collision edges) CANNOT
// return: the only culled blades are those with genuinely nothing under them.
constexpr float FLOOR_DEPTH_M = 2.5f;   // floor may be up to this far BELOW the blade base
constexpr float FLOOR_EPS_UP_M = 0.75f; // ... or this far ABOVE it (render/collision mismatch)
// ROUND#19b (owner LIVE obs 2026-07-12): FLOORBELOW's 2.5m window has a STACKED-TERRACES hole — a blade
// cantilevered past an UPPER platform edge still has the LOWER terrace 1-2m beneath it, so "some floor
// within 2.5m" keeps it and it visually overflows the upper edge. A blade must stand essentially ON ITS
// OWN floor: nearest walkable floor below the base must be within this small gap, else the base hangs
// over a DIFFERENT (lower) surface -> cull. Tuned against false culls via the interior-blade gap p99
// (ROUND#19b FLOORGAP log); device-tunable without rebuild via debug.opengoal.grass_floorgap (metres).
constexpr float FLOOR_GAP_M = 0.5f;
constexpr float FLOOR_BUCKET_M = 1.0f;  // fine XZ lookup bucket so per-base candidate lists stay
                                        // small (ROUND#19 perf: 4m buckets ANR-stalled rebuild)
constexpr float FLOOR_MAX_TRI_M = 40.0f;// drop degenerate level-spanning collision tris

// Grecharged-grass-overhang (owner 2026-07-11): 3D DROOPING grass over platform edges. The placement
// zone is the faces the WALKABLE pass excludes: the overhang-LIP tris (is_lip, upness 0.35..0.55) plus
// the steep grass-textured FRINGE faces (upness <= GROUND_UPNESS — the faces carrying the game's
// painted drooping-grass alpha texture, e.g. bch-grassfringe) which the scan previously dropped
// entirely. Droop blades hang over the drop BY DESIGN, so they are exempt from the rim height-taper
// (gspare = NO_RIM) and from the floor/occ keep tables. NEAR LOD only: the card pass never draws them
// (far = the original alpha texture, no cards).
constexpr float DROOP_DENSITY = 70.0f;     // droop blades per m^2 of lip/fringe face (pre top-bias)
constexpr int DROOP_MAX = 90000;           // hard ceiling for the whole droop pass
constexpr float DROOP_RIM_NEAR_M = 2.5f;   // a FRINGE face must sit this close (XZ) to a true rim —
                                           // steep grass walls far from any walkable edge get nothing
constexpr float DROOP_UPNESS_DIR_MIN = 0.10f;  // below this the ny>=0 normal flip is float-noise, so
                                               // the outward direction falls back to the nearest rim

// Grecharged-grass-overhang2 (owner ROUND-2 verdict 2026-07-13): the round-1 upright->droop switch
// read BINARY ("pas progressif entre l'herbe droite et l'herbe d'overhang"). Fix: for every walkable
// blade within TRANS_BAND_M of a rim that borders the droop zone, expand() emits a TWIN blade in the
// droop TAIL whose yaw points OUTWARD (toward that rim) and whose nspare encodes a lean weight
// (3 + w, w = 1 - rim_dist/band). The shader blends the twin from upright (w~0, faded in) to a
// droop-lite arc (w=1 at the rim), complementing the LOCKED stock rim height-taper which shrinks the
// upright blades over the same band. Tail placement => the overhang toggle stays draw-count-only and
// OFF == stock.
constexpr float TRANS_BAND_M = 0.45f;    // == the shader's RIM_TAPER band, so lean-in mirrors taper-out
constexpr int TRANS_MAX = 60000;         // hard ceiling for the transition twins
constexpr float DROOP_RIM_KEEP_M = 0.8f; // a rim segment within this (XZ) of a droop face = a droop rim
constexpr float DROOP_RIM_YWIN_M = 2.5f; // ... with this much Y tolerance (lip faces drop below the rim)

// Grecharged-grass-overhang3 (owner 2026-07-13: round-2 "failure totale"). The visible "wall drape"
// was the TRANSITION BAND: curved flat-grass-textured tris (upness 0.55..0.95) that the lip
// classifier (UPNESS_LIP_MAX) never catches, so they stayed WALKABLE and grew full-height uprights
// whose bases sit on the curl below the visual lip. Round 3: (A) scan flags them (BakeTri flags
// bit4) by tilt + droop-rim adjacency; expand() tags their blades with a NEGATIVE nspare carrying a
// tilt-derived comb weight, and the shader lies them along the in-plane down-slope when the toggle
// is ON (OFF path bit-identical). (B) droop is rebuilt as mesh-following ROWS rooted at each
// fringe/lip tri's up-slope (rim-shared) edge, per-blade length capped at the tri's own in-plane
// exit distance -> never longer than the texture it covers; same species as platform grass.
constexpr float TRANS_UPNESS_HI = 0.85f;   // tilt steeper than ~32 deg starts to comb (tw > 0)
constexpr float TRANS_UPNESS_LO = 0.45f;   // fully combed (tw = 1) at ~63 deg and steeper
constexpr float TRANS_TRI_NEAR_M = 1.5f;   // transition tri must sit this close (XZ) to a droop rim
constexpr float TRANS_TRI_YWIN_M = 2.5f;   // ... with this Y tolerance (the curl drops below the rim)
constexpr float DROOP_EDGE_DENS = 22.0f;   // droop blades per metre of placement row
constexpr float ROW_STEP_M = 0.28f;        // down-slope spacing between rows on tall fringe faces
constexpr int   DROOP_MAX_ROWS = 6;        // row cap per face
constexpr float DROOP_MIN_LEN_M = 0.07f;   // skip blades shorter than this (invisible slivers)
constexpr float DROOP_EXIT_SAFETY = 0.95f; // blade length cap = this fraction of the tri exit distance

// Grecharged-grass-overhang4 (owner 2026-07-14: round 3 "complètement loupé" — clip-through at the
// floor→overhang transition, brutal per-tri seams, diagonal bands on the overhang). Root causes, all
// per-tri / periodic structure: (a) droop ROWS (root-edge row per tri + 0.28m level-set rows) = the
// diagonal bands; (b) comb weight from the FACE normal = whole triangles flipping state; (c) the
// round-2 twins' straight horizontal chord passing through the curved lip mesh = the clip-through.
// Round 4 removes every per-tri field from the visible math:
//  (1) SMOOTH vertex normals (position-welded, area-weighted over the retained soup) interpolated
//      barycentrically at each blade base — every per-blade quantity below is continuous across tri
//      borders by construction.
//  (2) Comb = PER-BLADE continuous weight w = tilt(n_smooth.y ramp UPNESS_HI->LO) * near(droop-rim
//      distance), delivered as toggle-gated TAIL REPLACEMENT twins: the tagged original keeps its
//      stock bytes except nspare=-(1+w) (unread when OFF -> OFF == stock byte-identical; when ON the
//      shader collapses it in the blade pass and the twin — carrying the smooth normal in nx/ny/nz
//      and w in nspare=5+w — takes over). The round-2/3 transition-twin class is DELETED; the
//      continuous comb field IS the upright->droop transition.
//  (3) Droop rows -> area-uniform barycentric SCATTER; per-blade direction = the smooth normal's
//      in-plane down-slope; the below-plane sag term is gone.
//  (4) Surface constraint: every tail blade's rest arc is plane-capped against nearby tris at
//      placement time and the shader half-space-clamps vertices to the base tangent plane.
constexpr float COMB_NEAR0_M = 0.8f;  // fully combable this close (XZ) to a droop rim ...
constexpr float COMB_NEAR1_M = 1.3f;  // ... fading to zero here. MUST stay < RIM_ENC_MAX_M (1.4):
                                      // the cheap per-blade rim_q pre-filter relies on it.
constexpr float COMB_W_MIN = 0.01f;   // below this the twin would BE the stock blade: no tag
// ROUND 6: every blade on a TRANSITION (bit4) tri now combs by its pure tilt ramp (the owner's zone-2
// "green descending mesh" — ~63k blades on training's 546 m2 curl band), so the old 60k ceiling would
// truncate the curl mid-list. Raised to hold the full band plus the round-4 tilt*near stragglers.
constexpr int COMB_MAX = 150000;      // hard ceiling for comb replacement twins
constexpr float NOFF_M = 0.03f;       // root offset along the smooth normal (shader scales by w)
constexpr float DROOP_AREA_DENS = 130.0f;  // droop blades per m^2 of fringe/lip face (scatter)
constexpr float PLANE_CLEAR_M = 0.02f;     // rest tip must clear every nearby tri plane by this
constexpr float SHADER_TILT_DEFAULT = 0.30f;  // u_tilt the rest-pose plane cap assumes

// Grecharged-grass-overhang5 (owner 2026-07-14: shipped-APK play-test — overhang STILL reads like
// stock, precompute ON or OFF no difference). ROOT CAUSE (device-confirmed): rounds 1-4 place droop
// only on steep GRASS-TEXTURED "fringe" faces (upness <= GROUND_UPNESS). The stepped Sandover
// TERRACES the owner actually looks at have DIRT/ROCK faces — no grass-textured fringe — so they get
// ZERO droop and render identical to stock. Round 5 adds an independent RIM-DRAPE pass: 3D grass
// rooted ON the walkable-grass TRUE-RIM edges (the drop-off lips, boundary edges of placed walkable
// tris — already computed for the LOCKED edge clamp), curling OUTWARD over the convex lip and hanging
// DOWN the face regardless of what texture the face carries. Toggle-gated TAIL (nspare=3) so OFF ==
// stock byte-identical; NEAR-LOD only (the card pass collapses it -> far shows the original alpha
// overhang texture, LOD-alpha crossfade); the walkable-top rim clamp is untouched (additive pass).
// ROUND 6 (owner 2026-07-14): the v6 rim-drape BLADE emission is DELETED (blades hanging from bare
// dirt lip edges rejected). The scan still COLLECTS these true-rim edge segments — they now feed
// ZONE-1's outward-lean directions (the walkable boundary lean twins) in expand().
constexpr float RIMDRAPE_MIN_EDGE_M = 0.06f;  // skip degenerate/near-zero rim segments

// Grecharged-grass-overhang6 (owner 2026-07-14, verbatim 3-zone spec). ZONE 1 = walkable-top blades
// near the grass boundary progressively LEAN toward the void. ZONE 2 = blades ON the flat-green
// sub-lip mesh strip (tra-grass), following it with increasing lean (emitted as 5+w comb-class).
// ZONE 3 = >= 2 LAYERS of grass falling fully downward, covering the native-alpha overhang faces.
constexpr float LEAN_BAND_M = 0.9f;      // zone-1: walkable blades this close (perp) to a true rim lean outward
constexpr float LEAN_K_MIN = 0.04f;      // below this the lean is invisible: no twin, no tag
constexpr int   LEAN_MAX = 90000;        // zone-1 twin ceiling
constexpr float LEAN1_MAX = 0.55f;       // max up->outward axis blend at the rim; MUST equal the shader's
                                         // LEAN1_MAX and Z2_K1 (zone-1 end == zone-2 start: continuity)
constexpr float Z2_AREA_DENS = 110.0f;   // zone-2 blades per m^2 of flat-green sub-lip strip
constexpr int   Z2_MAX = 90000;
constexpr float Z2_K1 = 0.55f;           // zone-2 lean floor at the strip top (== LEAN1_MAX)
constexpr float Z2_DEPTH_FULL_M = 1.2f;  // fully bent (w=1) this far below the owning rim
// ROUND 8 (supervisor's own read of the owner's live view, SUPERVISOR-OWNER-VIEW.png): the v7 fall
// curtain read as a thin dark-olive "eyeliner" strip. Three fixes, all in the toggle-gated tail:
//  (1) COLOR: fall blades inherit the nearest rim segment's WALKABLE-TOP lawn colour + baked-light
//      tri (RimDrapeSeg.gr/gg/gb + .tri, already in GBK6+ bakes) instead of the dark drop-face tri;
//      the 0.82 inner-layer darkening is deleted; the shader's vertical gradient is REVERSED for the
//      fall class (root at the lip = lawn-tip bright) so the lip has no tonal seam.
//  (2) VOLUME: 3 layers at deeper normal offsets + wider blades + a real outward belly (shader).
//  (3) RAGGED: 0.7 m world-XZ cell noise modulates density AND length in coherent clumps along the
//      lip, plus per-blade exit-cap jitter — no uniform band, no outlined ledges.
// ROUND 11 (supervisor DESIGN PIVOT, df1486b45): ten rounds prove solid-colour blade quads cannot
// read as the game's grass art at the owner's judging distance (plates / strings / foam — R8-R10).
// Zone 3 is REBUILT as textured CARDS sampling the game's OWN hang-alpha texels (bch-grassfringe /
// bch-leafyground-hang-2x1 — the exact texels the native painted strip uses; alpha-cut like it),
// hung from the true-rim lip segments in Z3C_LAYERS outward-offset layers with per-layer sway,
// per-layer UV offset/flip (no ghosting) and per-card length jitter. Near view = the NATIVE art
// (texel-identical tufts) with real depth from layering + animation; the flat painted strip stays
// near-hidden (cards replace it, restored at far LOD). Zones 1-2 unchanged from round 10. The
// solid-blade fall classes (nspare 7.x: face scatter + lip root rows) are DELETED.
constexpr int   Z3C_LAYERS = 3;             // pivot spec: 2-3 offset layers; 3 for visible parallax
constexpr float Z3C_SPACING_M = 0.55f;      // along-lip card spacing per layer (< Z3C_WIDTH_M => overlap)
constexpr float Z3C_WIDTH_M = 0.80f;        // card width; MUST equal the shader's 2*CARD_HW
constexpr float Z3C_REPEAT_W_M = 1.6f;      // world width of one full texture repeat (256x128 texels
                                            // => square texels at a 0.8 m strip height); shader RPT
constexpr float Z3C_SINK_M = 0.05f;         // root sink under the lawn plane (card top texels are
                                            // dense grass -> the lip junction is grass-on-grass)
constexpr float Z3C_DEPTH_MARGIN_M = 0.35f; // hang past the deepest strip bottom found below the root
constexpr float Z3C_DEPTH_MIN_M = 0.45f;    // clamp: never shorter than a shallow strip band...
constexpr float Z3C_DEPTH_MAX_M = 2.4f;     // ...never a floor-length curtain
constexpr int   Z3C_MAX = 40000;            // card ceiling (~40x cheaper than the R10 420k blades)
constexpr float Z3_LIP_NEAR_HANG_M = 2.0f;  // cards only where native-alpha hang faces are below

// Grecharged-grass-overhang2 (owner defect 1: the painted overhang alpha texture stayed visible under
// the droop — "ça passe au travers"): the two painted hang-strip textures the NEAR droop replaces.
// The tfrag/TIE renderers fade draws using these textures out near the camera while the overhang
// toggle is ON (crossfaded over the droop blades' own fade band; far keeps the stock strip).
// tra-grass is deliberately EXCLUDED — it textures walkable tops; fading it would hole the ground.
inline bool is_fringe_hang_tex(const std::string& n) {
  return n == "bch-grassfringe" || n == "bch-leafyground-hang-2x1";
}

// ---------------------------------------------------------------------------
// Per-instance POD (moved from GrassRenderer.h). Layout MUST stay 16 floats in
// the same order — the GL attrib offsets depend on it.
// ---------------------------------------------------------------------------
struct GrassInstance {
  float px, py, pz, h;
  float yaw, tint, curve, phase;
  float gr, gg, gb, gspare;   // gspare = rim_dist (world units), NO_RIM=1e9 for interior
  float nx, ny, nz, nspare;
};
static_assert(sizeof(GrassInstance) == 64, "GrassInstance must stay 16 floats");

// LA POSITION D'UN CANDIDAT, EN UN SEUL ENDROIT — pour de bon depuis grass-clumps. Ce fichier
// portait ici un `cand_barycentric()` dont le commentaire annoncait deja « EN UN SEUL ENDROIT »
// alors que `scan_level` et `expand` en gardaient chacun une COPIE inline, et que lui-meme n'etait
// appele que par `transition_census`. Trois copies d'une formule que cet item devait deplacer : la
// fonction a ete retiree et remplacee par `ClumpPlacer` (plus bas), que les trois sites appellent.
// Le tirage uniforme qu'elle rendait reste calcule, par `ClumpPlacer::place` (`ClumpSite::u1/u2`) :
// c'est le bras de comparaison de la porte de grass-clumps.
struct BakeTri;

// ---------------------------------------------------------------------------
// Bake tables.
// ---------------------------------------------------------------------------
struct BakeTri {
  float p0[3], e1[3], e2[3];  // triangle base vertex + edges (world GOAL units)
  u32 seed;
  float area_m2;
  float gr, gg, gb;           // ground-texture average colour
  float nx, ny, nz;           // normalized face normal, ny >= 0
  float pal[8][3];            // day-cycle baked-light keyframes (time-of-day palette rows, centroid avg)
  u32 cand_count;             // candidates enumerated at bake_density_pct
  u64 cand_base;              // first candidate index in keep[]/rim_q[]
  u32 flags;                  // bit0 is_tie, bit1 is_lip, bit2 is_dup, bit3 is_fringe (droop-only tri), bit4 is_transition (ROUND3: curl band, blades combed when toggle ON), bit5 is_hang (tri's source draw carries a native overhang-alpha hang texture — is_fringe_hang_tex), bit6 is_hang_b (ROUND 11: that texture is bch-leafyground-hang-2x1, not bch-grassfringe — zone-3 cards sample the matching texels; 0 in pre-R11 bakes -> grassfringe fallback)
  // Grecharged-grass-overhang4 (GBK5): SMOOTH vertex normals — the area-weighted average of the
  // adjacent face normals at each of the tri's three (welded) vertices, computed once over the whole
  // retained soup (walkable + lip + fringe) at bake time. expand() interpolates these barycentrically
  // at every blade base, so the comb tilt weight and the droop drape direction are CONTINUOUS across
  // every tri border (no per-tri state -> no seams, defect 2). Computed on x86 at bake, read verbatim
  // on device (no cross-platform weld); a v4 bake fails the version check and falls back to live scan.
  float vn0[3], vn1[3], vn2[3];  // smooth normal at p0, p0+e1, p0+e2 (unit, ny>=0-oriented like nx/ny/nz)
};

// ---------------------------------------------------------------------------
// grass-clumps : LA TOUFFE, ET LA SEULE COPIE DE LA FORMULE DE POSITION.
// ---------------------------------------------------------------------------
//
// SPEC section 6. Avant cet item il n'existait AUCUNE touffe : chaque candidat tirait sa position
// d'un barycentre uniforme et ses cinq proprietes de cinq hachages independants. Le mot « tuft »
// du code designait une decoupe de fragment a l'interieur d'une carte.
//
// POURQUOI CETTE CLASSE PLUTOT QU'UNE QUATRIEME COPIE. La formule de position etait ecrite TROIS
// fois — `scan_level` (les bits `keep`, `rim_q` et `path_q` s'y decident, sur la position),
// `expand` (le brin s'y emet) et `transition_census` (il la recalcule pour les candidats qu'aucun
// brin ne represente) — alors que le commentaire de `cand_barycentric` annonce « EN UN SEUL
// ENDROIT ». Deplacer les racines avec trois copies aurait pose les bits `keep` sur des positions
// que plus aucun brin n'occupe : un brin valide au-dessus du vide. Les trois sites passent par
// CECI, et `clump_census` compte l'ecart (`pos_mismatch`) au lieu de le supposer nul.
//
// CE QUI TIENT LA NIDIFICATION DES PALIERS (SPEC sections 4 et 10 : « un changement de preset ne
// redistribue JAMAIS l'herbe »). Un palier bas est le PREFIXE EXACT du tableau de candidats. La
// touffe d'un candidat ne doit donc dependre QUE de son indice :
//   * le NOMBRE de touffes d'un triangle vient de son aire et de la densite du palier MEDIUM,
//     jamais de la densite courante — il est identique dans les cinq bakes du niveau ;
//   * la touffe d'un candidat `i` se tire de `i` seul, donc elle ne change pas quand `n` grandit ;
//   * son RANG `j` dans la touffe est le nombre de candidats d'indice INFERIEUR tombes dans la
//     meme touffe : il ne depend pas de `n` non plus.
// Consequence : un palier inferieur retire des brins DANS les memes touffes, en commencant par les
// peripheriques, et garde le brin dominant (rang 0, au centre). Ce n'est pas affirme ici :
// `clump_census` compte `origin_moved` et `prefix_breaks` entre deux paliers.
//
// CE QUI FAIT QUE DEUX TOUFFES NE SE RESSEMBLENT PAS. Trois tirages independants : l'origine, le
// rayon, et le POIDS. Sans le poids, le compte par touffe serait poissonien (CV 0,45 a 5 brins) ;
// l'etirement `g(u) = 0,5u2 + 0,5u` — monotone, g(0)=0, g(1)=1 — donne aux touffes des poids
// allant de 2,0 a 0,67 fois la moyenne et porte le CV mesure a 0,56.
// ---------------------------------------------------------------------------

// Brins par touffe VISES AU PALIER MEDIUM. Les autres paliers en decoulent par la nidification
// (mesure sur `training` : 1,7 / 3,3 / 5,0 / 6,7 / 8,3), ce qui approche la colonne « brins par
// touffe » de la matrice SPEC section 13 sans jamais redistribuer une racine.
constexpr float CLUMP_BLADES_MEDIUM = 5.0f;
// Rayon d'une touffe, tire uniformement dans cette plage — soit 14 a 30 cm de diametre. Regle sur
// la densite REELLE de `training` (le budget d'instances ramene le palier medium a 44,7 brins/m2,
// et non a `D_TARGET`), puis MESURE sur le niveau : 2,49 fois le voisinage du tirage uniforme a
// 12 cm. Les deux autres plages essayees rendent 1,87 (18-40 cm, trop lache pour se lire) et 2,96
// (11-24 cm, ou la pelouse commence a se lire en plaques isolees).
// `grass-biome-profiles` remplacera ces deux constantes par une donnee cuite par zone.
constexpr float CLUMP_R_MIN_M = 0.070f;
constexpr float CLUMP_R_MAX_M = 0.150f;
// Une touffe plus fournie que le nominal deborde de son rayon ; on borne le debordement.
constexpr float CLUMP_RHO_CAP = 1.40f;
// « des brins dominants et des brins peripheriques » : la hauteur decroit du centre vers le bord.
// Le profil est a MOYENNE CONSERVEE (0,997 mesure) — cet item ne change pas la hauteur moyenne.
constexpr float CLUMP_H_CENTER = 1.30f;
constexpr float CLUMP_H_SLOPE = 0.45f;
constexpr float CLUMP_H_LO = 0.70f;
constexpr float CLUMP_H_HI = 1.35f;
constexpr float CLUMP_BARY_EPS = 1.0e-4f;  // marge barycentrique : la racine reste DANS son support
constexpr u32 CLUMP_SALT = 0x51ED2701u;

// Les seuils que `clump_census` publie AVEC ses mesures : un seuil recopie dans le juge derive du
// code mesure et rend la porte fausse en silence (lecon de `grass-path-transitions`).
constexpr float CLUMP_PAIR_R_M = 0.12f;       // rayon de comptage des voisins
constexpr float CLUMP_RATIO_FLOOR = 1.50f;    // plancher du rapport touffes / uniforme
constexpr float CLUMP_SIZE_CV_FLOOR = 0.30f;  // plancher de dispersion du compte par touffe
constexpr float CLUMP_RADIUS_CV_FLOOR = 0.15f;  // ... et du rayon

inline float clump_height_mul(float rho) {
  const float m = CLUMP_H_CENTER - CLUMP_H_SLOPE * rho;
  return m < CLUMP_H_LO ? CLUMP_H_LO : (m > CLUMP_H_HI ? CLUMP_H_HI : m);
}

// Densite de touffes DU NIVEAU. Derivee de la densite du palier MEDIUM, elle-meme derivee de
// `total_area_m2` (cuit, identique dans les cinq bakes) et du budget d'instances. Elle ne lit
// JAMAIS la densite du palier courant : c'est ce qui fait tenir « les memes touffes aux memes
// endroits » d'un palier a l'autre.
inline float clump_density_for(float total_area_m2) {
  const float budget =
      (float)MAX_INSTANCES * (density_preset_pct(kDensityPresetDefault) / 100.0f);
  float dens = D_TARGET;
  if (total_area_m2 > 1.0f && total_area_m2 * D_TARGET > BUDGET_SAFETY * budget) {
    dens = BUDGET_SAFETY * budget / total_area_m2;
  }
  return dens / CLUMP_BLADES_MEDIUM;
}

// Ce qu'un candidat rend : sa racine, la racine qu'il AURAIT eue au tirage uniforme (le bras de
// comparaison de la porte, calcule au meme endroit pour qu'aucun des deux ne derive), et son
// appartenance.
struct ClumpSite {
  float r1, r2;      // barycentriques de la RACINE livree
  float u1, u2;      // barycentriques du tirage UNIFORME (le code REMPLACE, toujours calcule)
  u32 sd;            // graine du candidat : hauteur, teinte, courbure, phase, lacet la lisent
  u32 clump;         // indice de la touffe DANS SON TRIANGLE
  u32 rank;          // rang du brin dans la touffe (0 = le brin dominant, au centre)
  float rho;         // rayon normalise dans la touffe, APRES ecretage
  float radius_wu;   // rayon de la touffe (unites monde)
  float co1, co2;    // barycentriques de l'ORIGINE de la touffe
  float clip;        // facteur d'ecretage (1 = la racine tenait sans etre raccourcie)
};

class ClumpPlacer {
 public:
  ClumpPlacer(float total_area_m2, bool clumped)
      : m_cdens(clump_density_for(total_area_m2)), m_on(clumped) {}

  bool on() const { return m_on; }
  u32 clumps() const { return m_m; }
  u64 total_clumps() const { return m_tot_clumps; }
  u64 total_mounted() const { return m_tot_mounted; }
  // Empreinte des ORIGINES : quantifiees au millimetre monde, repliees en FNV-1a. Preset-
  // independante par construction, donc comparable d'un palier a l'autre ET d'un chargement a
  // l'autre. C'est le point 4 du contrat de l'item.
  u64 origin_digest() const { return m_digest; }

  // A appeler AVANT la boucle des candidats du triangle, et sur LE MEME ensemble de triangles des
  // trois cotes (scan, expansion, recensement), sans quoi l'empreinte ne serait plus comparable.
  void begin(const BakeTri& t) {
    fold();
    // DESARME, il n'y a PAS « une touffe par triangle » : il n'y a AUCUNE touffe. Un placeur qui
    // rendrait 1 ferait compter au bras `--off` une touffe montee par triangle — un `hits=` non
    // nul sur un regime ou la feature n'existe pas, donc une ablation qui ne separe rien.
    m_m = 0u;
    if (m_on) {
      const long k = std::lround((double)t.area_m2 * (double)m_cdens);
      m_m = k < 1 ? 1u : (u32)k;
    }
    m_fill.assign(m_m, 0u);
    m_seen.assign(m_m, 0u);
    // Base orthonormee du plan du triangle et matrice de Gram de (e1, e2) : un decalage exprime
    // dans le plan se convertit EXACTEMENT en increments barycentriques.
    const float l1 = std::sqrt(t.e1[0] * t.e1[0] + t.e1[1] * t.e1[1] + t.e1[2] * t.e1[2]);
    if (l1 > 1.0e-6f) {
      m_u[0] = t.e1[0] / l1; m_u[1] = t.e1[1] / l1; m_u[2] = t.e1[2] / l1;
    } else {
      m_u[0] = 1.f; m_u[1] = 0.f; m_u[2] = 0.f;
    }
    m_v[0] = t.ny * m_u[2] - t.nz * m_u[1];
    m_v[1] = t.nz * m_u[0] - t.nx * m_u[2];
    m_v[2] = t.nx * m_u[1] - t.ny * m_u[0];
    const float lv = std::sqrt(m_v[0] * m_v[0] + m_v[1] * m_v[1] + m_v[2] * m_v[2]);
    if (lv > 1.0e-6f) {
      m_v[0] /= lv; m_v[1] /= lv; m_v[2] /= lv;
    }
    m_a11 = t.e1[0] * t.e1[0] + t.e1[1] * t.e1[1] + t.e1[2] * t.e1[2];
    m_a12 = t.e1[0] * t.e2[0] + t.e1[1] * t.e2[1] + t.e1[2] * t.e2[2];
    m_a22 = t.e2[0] * t.e2[0] + t.e2[1] * t.e2[1] + t.e2[2] * t.e2[2];
    const float det = m_a11 * m_a22 - m_a12 * m_a12;
    m_inv_det = std::fabs(det) > 1.0e-9f ? 1.0f / det : 0.0f;
    if (m_on) {
      for (u32 c = 0; c < m_m; ++c) {
        float c1, c2, r;
        clump_of(t, c, c1, c2, r);
        const float ox = t.p0[0] + c1 * t.e1[0] + c2 * t.e2[0];
        const float oy = t.p0[1] + c1 * t.e1[1] + c2 * t.e2[1];
        const float oz = t.p0[2] + c1 * t.e1[2] + c2 * t.e2[2];
        mix(ox); mix(oy); mix(oz);
      }
    }
  }

  // Origine (barycentrique) et rayon de la touffe `c` du triangle `t`. Fonction PURE de
  // (t.seed, c) : c'est elle qui rend « l'origine ne bouge pas » verifiable de l'exterieur.
  static void clump_of(const BakeTri& t, u32 c, float& c1, float& c2, float& radius_wu) {
    const u32 cs = hash_u32(t.seed ^ (CLUMP_SALT + c * 2654435761u));
    float a = hash_f(cs + 1u), b = hash_f(cs + 2u);
    if (a + b > 1.0f) {
      a = 1.0f - a;
      b = 1.0f - b;
    }
    c1 = a;
    c2 = b;
    radius_wu = (CLUMP_R_MIN_M + (CLUMP_R_MAX_M - CLUMP_R_MIN_M) * hash_f(cs + 3u)) * U;
  }

  // Le candidat `i` du triangle `t`. A appeler dans l'ordre croissant des `i` : le rang dans la
  // touffe est un compte des candidats INFERIEURS, et c'est lui qui rend la nidification exacte.
  void place(const BakeTri& t, int i, ClumpSite& s) {
    const u32 sd = t.seed + (u32)i * 3266489917u;
    float a = hash_f(sd + 1u), b = hash_f(sd + 2u);
    if (a + b > 1.0f) {
      a = 1.0f - a;
      b = 1.0f - b;
    }
    s.sd = sd;
    s.u1 = a;
    s.u2 = b;
    if (!m_on) {
      s.r1 = a; s.r2 = b; s.co1 = a; s.co2 = b;
      s.clump = 0u; s.rank = 0u; s.rho = 0.f; s.radius_wu = 0.f; s.clip = 1.0f;
      return;
    }
    const float g0 = hash_f(sd + 8u);
    const float g = 0.5f * g0 * g0 + 0.5f * g0;  // poids de touffe : 2,0 -> 0,67 fois la moyenne
    u32 c = (u32)((float)m_m * g);
    if (c >= m_m) {
      c = m_m - 1u;
    }
    const u32 j = m_fill[c]++;
    float c1, c2, R;
    clump_of(t, c, c1, c2, R);
    // Spirale d'or par rang + phase propre a la touffe : les brins d'une touffe ne s'empilent pas
    // sur un rayon. Rayon en RACINE du rang -> repartition en aire, rang 0 au centre.
    const u32 cs = hash_u32(t.seed ^ (CLUMP_SALT + c * 2654435761u));
    const float th = (float)j * 2.39996323f + 6.2831853f * hash_f(cs + 4u);
    float rho = std::sqrt(((float)j + hash_f(sd + 9u)) / (CLUMP_BLADES_MEDIUM + 1.0f));
    if (rho > CLUMP_RHO_CAP) {
      rho = CLUMP_RHO_CAP;
    }
    const float off = R * rho;
    const float ct = std::cos(th), st = std::sin(th);
    const float dx = off * (ct * m_u[0] + st * m_v[0]);
    const float dy = off * (ct * m_u[1] + st * m_v[1]);
    const float dz = off * (ct * m_u[2] + st * m_v[2]);
    const float b1 = dx * t.e1[0] + dy * t.e1[1] + dz * t.e1[2];
    const float b2 = dx * t.e2[0] + dy * t.e2[1] + dz * t.e2[2];
    float d1 = (m_a22 * b1 - m_a12 * b2) * m_inv_det;
    float d2 = (-m_a12 * b1 + m_a11 * b2) * m_inv_det;
    // ECRETAGE. « Aucune racine ne doit migrer » hors de sa surface support (SPEC section 9) : on
    // RACCOURCIT le decalage jusqu'au bord au lieu de rabattre la racine dessus — une touffe
    // coupee par une arete s'aplatit contre elle, elle ne s'y empile pas.
    float sc = 1.0f;
    clip(1.0f - c1 - c2, -(d1 + d2), sc);
    clip(c1, d1, sc);
    clip(c2, d2, sc);
    if (sc < 0.0f) {
      sc = 0.0f;
    }
    s.clump = c;
    s.rank = j;
    s.radius_wu = R;
    s.co1 = c1;
    s.co2 = c2;
    s.clip = sc;
    s.rho = rho * sc;
    s.r1 = c1 + d1 * sc;
    s.r2 = c2 + d2 * sc;
  }

  // Le candidat vient d'etre EMIS : sa touffe est montee. `hits=` de la ligne FEATURE les compte.
  void mark(u32 c) {
    if (c < m_seen.size()) {
      m_seen[c] = 1u;
    }
  }
  // A appeler apres le dernier triangle, sinon le sien manque aux totaux.
  void finish() { fold(); }

 private:
  static void clip(float b, float d, float& s) {
    if (d < -1.0e-12f) {
      const float t = (CLUMP_BARY_EPS - b) / d;
      if (t < s) {
        s = t;
      }
    }
  }
  void mix(float w) {
    const s64 q = (s64)std::llround((double)w * (1000.0 / (double)U));  // millimetre monde
    u64 v = (u64)q;
    for (int k = 0; k < 8; ++k) {
      m_digest ^= (v >> (k * 8)) & 0xFFull;
      m_digest *= 1099511628211ull;
    }
  }
  void fold() {
    if (!m_started) {
      m_started = true;
      return;
    }
    m_tot_clumps += m_m;
    for (u8 v : m_seen) {
      m_tot_mounted += v;
    }
  }

  float m_cdens;
  bool m_on;
  bool m_started = false;
  u32 m_m = 1u;
  std::vector<u32> m_fill;
  std::vector<u8> m_seen;
  float m_u[3] = {1.f, 0.f, 0.f};
  float m_v[3] = {0.f, 0.f, 1.f};
  float m_a11 = 1.f, m_a12 = 0.f, m_a22 = 1.f, m_inv_det = 1.f;
  u64 m_tot_clumps = 0, m_tot_mounted = 0;
  u64 m_digest = 1469598103934665603ull;
};

// Grecharged-grass-overhang: one droop-placement face (a lip or fringe tri) with its scan-resolved
// OUTWARD direction (unit XZ, pointing away from the platform over the drop). Kept per-tri, not
// per-blade — expand() enumerates the blades deterministically from the tri seed.
struct DroopTri {
  u32 tri;         // index into BakeData::tris (a lip tri, or an appended fringe tri)
  float ox, oz;    // unit outward XZ direction (world)
};

// Grecharged-grass-overhang2: a true-rim segment that borders the droop zone (world GOAL units).
// expand() leans walkable-top blades progressively toward these (the upright->droop transition);
// stored in the bake (GBK3) because precomputed mode's rim_q has only a DISTANCE, no direction.
struct DroopRimSeg {
  float ax, ay, az, bx, by, bz;
};

// Grecharged-grass-overhang5: a true-rim (walkable-top drop-off lip) edge segment with its scan-
// resolved OUTWARD horizontal direction (unit XZ, away from the platform interior) and the owning
// walkable tri's baked ground colour + index (for per-instance light). expand() scatters rim-drape
// blades ALONG the segment; each roots at the lip and curls outward+down over the edge.
struct RimDrapeSeg {
  float ax, ay, az, bx, by, bz;  // edge endpoints (world GOAL units)
  float ox, oz;                  // unit outward XZ direction (away from interior, over the drop)
  float gr, gg, gb;              // owning walkable tri ground colour
  u32 tri;                       // owning walkable tri index (into BakeData::tris) for light sampling
};

// grass-chunk-cull : LA PARTITION SPATIALE, CUITE DANS LE FICHIER.
//
// POURQUOI ELLE EST UNE PLAGE CONTIGUE ET NON UNE CELLULE DE GRILLE. Les deux passes de dessin
// lisent le MEME tampon d'instances, dans l'ordre ou `expand()` les emet, et le melange alpha est
// ACTIF (`glEnable(GL_BLEND)`, GrassRenderer.cpp) : reordonner les instances pour les grouper par
// cellule changerait l'ordre de melange des fragments translucides, donc l'image. Le contrat de
// l'item l'interdit (« l'image ne change pas, identique au bit »). Un lot est donc une PLAGE
// CONTIGUE de l'ordre existant, fermee des que sa boite passe `CHUNK_MAX_DIAG_M` ou
// `CHUNK_MAX_COUNT`. Mesure sur training@150 (616 379 instances) : l'ordre d'emission est deja
// spatialement coherent — 1 129 lots, diagonale XZ mediane 5,7 m — et un lot cull-e n'est jamais
// qu'un SOUS-ENSEMBLE retire de la sequence, jamais une permutation.
//
// « Une touffe traversant une frontiere appartient au chunk de son ORIGINE » (SPEC section 10) :
// il n'existe pas encore de touffe, et un brin n'appartient qu'au lot qui contient SA POSITION —
// la boite est celle des origines, etendue vers le haut par la hauteur du brin.
struct GrassChunk {
  u32 first;           // premiere instance du lot dans expand()->instances
  u32 count;           // nombre d'instances du lot
  float lo[3], hi[3];  // boite des ORIGINES, hi[1] releve au sommet du brin (unites monde GOAL)
};

// Taille visee. `CHUNK_MAX_COUNT` borne le nombre d'instances par lot (« un nombre d'instances par
// chunk a peu pres constant », SPEC section 10) ; `CHUNK_MAX_DIAG_M` borne son etendue, sans quoi
// une plage peu coherente produirait une boite qui couvre le niveau et ne serait jamais rejetee.
constexpr float CHUNK_MAX_DIAG_M = 12.0f;
constexpr u32 CHUNK_MAX_COUNT = 1024;

// Deterministe : aucun aleatoire, aucune horloge, un seul parcours dans l'ordre d'emission. Le
// meme tableau d'instances rend le meme decoupage sur x86 et sur arm64.
void build_chunks(const std::vector<GrassInstance>& inst, std::vector<GrassChunk>& out);

struct BakeStats {
  int considered_draws = 0, tie_draws = 0, tris_kept = 0, giant_tris = 0;
  float max_area = 0.f;
  int occ_objpt_buckets = 0;  // spatial-hash object-point bucket count (occ log)
  // grass-path-transitions (GBK9) : les DEUX sources du classement « sol nu pose », comptees a la
  // cuisson. Serialisees : le moteur charge un bake, il ne rescanne pas, et sans elles sa
  // publication confondrait « aucun sol nu » avec « je n'ai pas regarde ».
  u32 trans_bare_geom = 0;      // draws retenus par la GEOMETRIE de rendu
  u32 trans_bare_mat = 0;       // ... par le MATERIAU de collision dessous
  u32 trans_bare_both = 0;      // les deux -> empreinte
  u32 trans_bare_disagree = 0;  // exactement une des deux
  u32 trans_bare_tris = 0;      // triangles d'empreinte retenus
  u32 trans_occ_object = 0;     // points restes occulteurs d'OBJET (comportement inchange)
  u32 trans_occ_moved = 0;      // points sortis de l'occultation binaire
  float trans_bare_area_m2 = 0.f;
  u64 faces_up = 0;            // faces non-herbe regardant vers le haut, examinees
  u64 faces_bare_mat = 0;      // ... dont le plancher de collision porte un materiau NU
  u64 faces_affleurantes = 0;  // ... et qui AFFLEURENT ce plancher -> empreinte
  u64 faces_lifted = 0;        // ... mais SOULEVEES : un dessus d'objet, pas une dalle
  u64 faces_nofloor = 0;       // ... sans plancher sous elles dans la fenetre
  std::string bare_tex_top;    // "texture:aire_cm2,..." des draws RETENUS
  std::string bare_rej_top;    // "texture:raison:aire_cm2,..." des draws ECARTES
  std::string bare_mat_top;    // "materiau:faces,..." sous les faces plates non-herbe
};

struct BakeData {
  std::string level_name;
  u32 tfrag3_version = 0;
  u64 fr3_size = 0;
  float bake_density_pct = 0.f;   // density the candidates were enumerated at
  float floor_gap_m = 0.f;        // floor-gap threshold used at scan time (metres)
  float total_area_m2 = 0.f;      // scan's float area sum (expand's density recompute input)
  std::vector<BakeTri> tris;      // ALL scanned tris incl. lip/dup (cand_count=0 for those);
                                  // Grecharged-grass-overhang: fringe tris are APPENDED at the tail
                                  // (flags bit3) so all pre-existing tri indices are unchanged
  std::vector<u8>  keep;          // per candidate: bit0 scatter_keep (floor+rim pass), bit1 occ_keep
  std::vector<u16> rim_q;         // per candidate: quantized rim_dist; 0xFFFF = NO_RIM/far
  // grass-path-transitions (GBK9) : par candidat, distance XZ EXACTE a l'empreinte du sol nu le
  // plus proche (chemin / terre), quantifiee ; 0 = DANS l'empreinte, 0xFFFF = aucun sol nu a
  // portee. C'est la seule grandeur continue que le placement lit pour attenuer la HAUTEUR ; la
  // DENSITE, elle, est deja tranchee a la cuisson dans `keep` bit2 (bruit coherent compris).
  std::vector<u16> path_q;
  std::vector<DroopTri> droop;    // Grecharged-grass-overhang: droop faces + outward dirs (GBK2)
  std::vector<DroopRimSeg> droop_rims;  // Grecharged-grass-overhang2: droop-zone rim segments (GBK3)
  std::vector<RimDrapeSeg> rimdrape;    // Grecharged-grass-overhang5: walkable-top drop-off lip edges (GBK6)
  // grass-chunk-cull (GBK8) : la partition de l'expansion A LA DENSITE DE CE BAKE. Cuite par
  // `tools/grass_bake`, relue telle quelle par le moteur ; `expand()` la recalcule de son cote et
  // le renderer publie l'ecart, ce qui rend le determinisme falsifiable au lieu d'etre affirme.
  std::vector<GrassChunk> chunks;
  BakeStats stats;
};

// Rim quantization. Shader offsets never exceed ~1m, so any rim >= 1.4m behaves
// identically to NO_RIM; resolution ~0.02mm.
constexpr float RIM_ENC_MAX_M = 1.4f;
inline u16 rim_encode(float d_world) {
  if (d_world >= RIM_ENC_MAX_M * 4096.f) {
    return 0xFFFF;
  }
  return (u16)std::lround(d_world * (65534.0f / (RIM_ENC_MAX_M * 4096.f)));
}
inline float rim_decode(u16 q) {
  if (q == 0xFFFF) {
    return 1.0e9f;  // NO_RIM
  }
  return (float)q * ((RIM_ENC_MAX_M * 4096.f) / 65534.0f);
}

// ---------------------------------------------------------------------------
// grass-path-transitions : LA TRANSITION AU BORD DES CHEMINS ET DES ZONES DE TERRE.
// ---------------------------------------------------------------------------
//
// SPEC section 9 : « TRANSITIONS : jamais binaires. Reduction progressive de densite et de
// hauteur, irregularite du bord par bruit coherent. Ne pas laisser de bande vide entre le
// dernier brin et la limite du chemin. »
//
// CE QUE LE SOCLE FAISAIT, MESURE AVANT D'ETRE CHANGE. Un chemin de `training` n'est pas un trou
// dans le tfrag herbeux : c'est un mesh pose PAR-DESSUS (`grass-overlay-meshes` : 11 210 paires
// sur `training`). Un draw TIE non-herbe devient un OCCULTEUR D'OBJET : ses faces sont
// echantillonnees au pas de 0,35 m et tout brin a moins de `OCC_RADIUS_M` (0,45 m) en XZ d'un de
// ces points est TUE (le test `occ_hidden` de scan_level). Un chemin produit donc un halo pele de
// 45 cm a bord net tout autour de lui : la « bande vide » ET la « decoupe nette » sont CE test.
//
// CE QU'ON MET A LA PLACE, POUR LES RECOUVREMENTS DE SOL SEULEMENT. Un draw reconnu « sol nu »
// par DEUX sources independantes — sa geometrie de rendu est plate et basse, et le materiau de
// collision sous lui est `sand|dirt|gravel|stone` — sort de la population d'occulteurs d'objet et
// entre dans un CHAMP DE DISTANCE : la distance XZ EXACTE du brin a l'empreinte du chemin, prise
// sur les triangles eux-memes et non sur un nuage de points echantillonne.
// `recharged-grass-object-clip`, valide par l'owner, n'est pas touche : un rocher, une caisse ou
// la borne de warp restent des occulteurs binaires a 0,45 m.
constexpr float TRANS_OVL_UPNESS = 0.70f;     // face « posee a plat » : n.y/|n| au moins
constexpr float TRANS_OVL_LIFT_M = 0.35f;     // une DALLE affleure son plancher de collision ;
                                              // le dessus d'un rocher, lui, est SOULEVE
constexpr float TRANS_OVL_MINAREA_M2 = 2.0f;  // aire XZ min : un caillou n'est pas un chemin
constexpr float TRANS_OVL_YWIN_M = 1.00f;     // |dy| max entre l'empreinte et la racine du brin
constexpr float TRANS_W_M = 1.00f;            // largeur DECLAREE de la bande de transition
constexpr float TRANS_DENS_FLOOR = 0.72f;     // densite relative AU BORD — jamais zero, sinon la bande revient
constexpr float TRANS_H_FLOOR = 0.40f;        // hauteur relative AU BORD
constexpr float TRANS_NOISE_AMP_M = 0.35f;    // amplitude du bruit coherent sur la distance
constexpr float TRANS_NOISE_LEN_M = 1.60f;    // longueur d'onde de sa premiere octave
constexpr float TRANS_QUERY_M = 1.35f;        // == TRANS_W_M + TRANS_NOISE_AMP_M : rayon de requete
constexpr float PATH_ENC_MAX_M = 2.5f;        // plafond de quantification de `path_q`
// ---- LES PLAFONDS ET PLANCHERS DU RECENSEMENT, DECLARES AVANT D'ETRE MESURES.
constexpr float TRANS_LIMIT_BAND_M = 0.15f;    // « a la limite de la zone nue » : 0 < d <= ceci
constexpr float TRANS_CELL_M = 0.35f;          // maille du recensement de densite locale
constexpr u32 TRANS_CELL_MIN_CAND = 6;         // sous ce compte, une cellule ne dit rien
constexpr float TRANS_FRONT_EPS_M = 0.05f;     // +/- autour de la mediane du front
constexpr float TRANS_GAP_CAP_M = 0.20f;       // POINT 1 : plafond du 99e centile de la bande nue
constexpr float TRANS_GAP_MAX_CAP_M = 0.60f;   // POINT 1 : plafond dur du PIRE echantillon
constexpr float TRANS_GAP_DEFECT_FRAC = 0.01f; // POINT 1 : part max d'echantillons IMPUTES a la transition
constexpr float TRANS_EDGE_FOLLOW_CAP = 0.35f; // POINT 3 : plafond de rectitude du bord
constexpr float TRANS_GRADED_FLOOR = 0.30f;    // POINT 4 : plancher de cellules a densite moyenne
constexpr float TRANS_RAMP_MAX = 0.90f;        // POINT 4 : le bord doit rendre au plus 90 % du fond de bande

// Quantification de la distance a l'empreinte nue. MEME forme que rim_encode : u16 lineaire,
// 0xFFFF = « aucun sol nu a portee ». 0 = DANS l'empreinte.
inline u16 path_encode(float d_world) {
  if (d_world >= PATH_ENC_MAX_M * 4096.f) {
    return 0xFFFF;
  }
  if (d_world <= 0.f) {
    return 0;
  }
  return (u16)std::lround(d_world * (65534.0f / (PATH_ENC_MAX_M * 4096.f)));
}
inline float path_decode(u16 q) {
  if (q == 0xFFFF) {
    return 1.0e9f;
  }
  return (float)q * ((PATH_ENC_MAX_M * 4096.f) / 65534.0f);
}

// BRUIT COHERENT, ENTIEREMENT DETERMINISTE. Les coins du reseau sont haches par des ENTIERS :
// aucune horloge, aucun flottant en entree du hachage, donc la cuisson x86 et la relecture arm64
// voient la meme valeur. Deux octaves : la premiere creuse les golfes, la seconde dentelle.
inline float trans_lattice(s32 a, s32 b) {
  return hash_f((u32)(a * 73856093) ^ (u32)(b * 19349663)) * 2.0f - 1.0f;
}
inline float trans_noise_octave(float x, float z, float len_world) {
  const float fx = x / len_world, fz = z / len_world;
  const float ix = std::floor(fx), iz = std::floor(fz);
  float tx = fx - ix, tz = fz - iz;
  tx = tx * tx * (3.0f - 2.0f * tx);
  tz = tz * tz * (3.0f - 2.0f * tz);
  const s32 X = (s32)ix, Z = (s32)iz;
  const float n00 = trans_lattice(X, Z), n10 = trans_lattice(X + 1, Z);
  const float n01 = trans_lattice(X, Z + 1), n11 = trans_lattice(X + 1, Z + 1);
  return (n00 * (1.0f - tx) + n10 * tx) * (1.0f - tz) + (n01 * (1.0f - tx) + n11 * tx) * tz;
}
inline float trans_noise(float x, float z) {
  const float L = TRANS_NOISE_LEN_M * 4096.f;
  return 0.70f * trans_noise_octave(x, z, L) + 0.30f * trans_noise_octave(x, z, L * 0.4f);
}
inline float trans_smooth01(float t) {
  if (t <= 0.f) {
    return 0.f;
  }
  if (t >= 1.f) {
    return 1.f;
  }
  return t * t * (3.0f - 2.0f * t);
}
// Densite RELATIVE et hauteur RELATIVE d'un brin a `d` unites-monde de l'empreinte nue. Ni l'une
// ni l'autre ne tombe a zero : un plancher nul REFABRIQUERAIT la bande pelee qu'on retire.
inline float trans_density_mul(float d_world) {
  return TRANS_DENS_FLOOR +
         (1.0f - TRANS_DENS_FLOOR) * trans_smooth01(d_world / (TRANS_W_M * 4096.f));
}
inline float trans_height_mul(float d_world) {
  return TRANS_H_FLOOR + (1.0f - TRANS_H_FLOOR) * trans_smooth01(d_world / (TRANS_W_M * 4096.f));
}

// ---------------------------------------------------------------------------
// API.
// ---------------------------------------------------------------------------
struct ScanParams {
  float cand_density_pct;
  float floor_gap_m;
};
BakeData scan_level(const tfrag3::Level& lev, const std::string& level_name, u64 fr3_size,
                    const ScanParams& p);

struct ExpandResult {
  std::vector<GrassInstance> instances;
  std::vector<u32> inst_tri;    // instance -> tris index
  int scatter_kept = 0;         // pre-occ kept count (budget accounting, for the occ log)
  int occ_culled = 0;
  // grass-path-transitions : ce que la TRANSITION retire, compte separement de ce que
  // l'occultation d'OBJET retire. Confondre les deux causes rendrait le correctif invisible.
  int trans_culled_inside = 0;  // racine DANS l'empreinte d'un sol nu -> le chemin reste degage
  int trans_culled_thin = 0;    // racine dans la bande, eclaircie par le bruit coherent
  int trans_band = 0;           // brins EMIS dont la racine est a moins de TRANS_W_M de l'empreinte
  int trans_interior = 0;       // brins emis hors de portee de tout sol nu
  // Index du candidat dont chaque instance est issue (parallele a `inst_tri`) : le recensement lit
  // `keep`/`path_q` par cet index au lieu de re-enumerer une seconde fois — une re-enumeration
  // serait une COPIE de la boucle de placement, donc une divergence en attente.
  std::vector<u32> inst_cand;
  // Nombre de candidats que l'expansion a REELLEMENT enumeres par triangle (0 pour lip/dup et
  // pour la queue coupee par le budget). Le recensement le lit au lieu de recalculer la densite :
  // recalculer serait une seconde copie de la regle, donc une divergence en attente.
  std::vector<u32> tri_n;
  // Grecharged-grass-overhang: droop instances are appended at the TAIL of instances[]. The renderer
  // draws [0, droop_start) for the card pass always, and [0, droop_start or size) for the blade pass
  // depending on the overhang toggle — so flipping the toggle never needs a rebuild.
  int droop_start = 0;          // == instances.size() when there is no droop data
  // Grecharged-grass-overhang2: the progressive upright->droop transition twins sit after the hang
  // blades, still inside the toggle-gated tail. Census only — the draw split is droop_start.
  // Grecharged-grass-overhang4: the twins class is DELETED; this now marks where the COMB
  // REPLACEMENT twins start (same tail, same census role).
  int trans_start = 0;          // == instances.size() when there are no comb twins
  // Grecharged-grass-overhang3: how many BASE-range walkable blades carry the negative-nspare comb
  // tag (census only; their position/height/order are byte-identical to an untagged build).
  int comb_tagged = 0;
  // Grecharged-grass-overhang4 census: emitted comb replacement twins (== final tagged originals),
  // and how many tail blades the neighbor-plane cap shortened / dropped (the clip-through guard).
  int comb_pairs = 0;
  int plane_capped = 0;
  int plane_dropped = 0;
  // grass-chunk-cull : la partition RECALCULEE depuis les instances qu'on vient d'emettre. Le
  // moteur la compare a celle lue dans le fichier ; l'outil de cuisson y ecrit celle-ci.
  std::vector<GrassChunk> chunks;
  // Grecharged-grass-overhang6 census: zone-1 lean twins (walkable boundary), zone-2 strip scatter
  // (flat-green sub-lip mesh, emitted as 5+w comb-class), zone-3 layered fall (native-alpha faces).
  int lean_tagged = 0;   // walkable originals tagged for a lean twin
  int lean_twins = 0;    // emitted zone-1 twins (== lean_tagged minus cap-dropped)
  int z2_count = 0;
  int z3_count = 0;
  // grass-clumps : ce que le placement en touffes a REELLEMENT monte, compte pendant l'emission.
  u64 clumps_total = 0;         // touffes enumerees sur les triangles porteurs
  u64 clumps_mounted = 0;       // ... portant au moins un brin EMIS : le `hits=` de la ligne FEATURE
  u64 clump_origin_digest = 0;  // empreinte FNV-1a des origines (point 4 du contrat)
  u32 clump_clipped = 0;        // racines dont le decalage a ete raccourci par le bord du triangle
  bool clumped = true;          // le regime sous lequel CETTE expansion a tourne (bras d'ablation)
};
// `want_cand_map` remplit `inst_cand` — le recensement de grass-path-transitions seul en a
// besoin ; le jeu l'appelle a false et ne paie pas les 4 octets par instance.
// `clumped` = le bras d'ablation de grass-clumps. FAUX rend le tirage barycentrique uniforme du
// code REMPLACE, sur le MEME bake : c'est l'oracle non-miroir, pas un zero muet. Le moteur y passe
// `armed_for("grass-clumps")` ; l'outil de cuisson ecrit toujours le regime livre (vrai).
ExpandResult expand(const BakeData& d, float density_slider_pct, bool want_cand_map = false,
                    bool clumped = true);

// ---------------------------------------------------------------------------
// grass-surface-truth : LES DEUX SOURCES QUI DISENT SI UNE SURFACE PORTE DE L'HERBE.
// ---------------------------------------------------------------------------
//
// SPEC sections 2, 3 et 9. L'eligibilite du bake tient a TROIS noms de texture exacts
// (`is_grass_ground`, GrassBakeCore.cpp) ; le detecteur de bord en deduit qu'une arete
// ouvre sur le vide des qu'aucun AUTRE triangle de cette population ne la partage, si
// bien qu'une frontiere de materiau est indiscernable d'un precipice. Or chaque triangle
// de collision de chaque `.fr3` porte deja le classement des auteurs d'origine, dans les
// bits 6..11 de son `pat` (`pat-material`, 23 valeurs, `pat-h.gc:5-27`). AUCUN site C++
// ne les lisait : `GrassBakeCore.cpp:816` ne prend que les bits de mode.
//
// CE RECENSEMENT NE PLACE RIEN. Il lit, il croise, il compte. `scan_level`, `expand` et le
// format du `.grassbake` ne le voient pas : le placement est identique au bit.
//
// LA POPULATION est le SOL tel que le jeu lui-meme le definit : un triangle de collision
// dont le mode vaut 0 (`pat-mode ground`, celui sur lequel Jak marche). Elle vit dans
// TOUS les niveaux, pas seulement ceux qui ont de l'herbe.
//
// LES DEUX SOURCES, lues separement et publiees separement :
//   MATERIAU : `(pat >> 6) & 0x3f`. Elle CLASSE quand la valeur nomme un `pat-material`
//              (< kPatMaterialCount) ; au-dela, la donnee ne dit rien et la source se tait.
//   TEXTURE  : le nom de la texture du triangle de RENDU qui couvre le centroide du
//              triangle de collision (recherche XZ + fenetre verticale). Elle CLASSE quand
//              un tel triangle existe et porte un nom non vide.
// Un triangle qu'AUCUNE des deux ne classe est un trou : c'est `unclassified`, et c'est lui
// que la porte de l'item lit.
//
// LE DESACCORD SE COMPTE. Les deux sources rendent chacune un verdict « herbe / pas herbe » ;
// quand elles divergent sur un triangle que les DEUX classent, on compte, on separe les deux
// sens, et on NOMME les textures impliquees. Un desaccord n'est pas un defaut : c'est la
// donnee dont `grass-edge-truth` et `grass-path-transitions` ont besoin.
struct SurfaceCensus {
  // Population et couverture.
  u64 ground_tris = 0;       // triangles de collision de mode 0 (le sol du jeu)
  u64 collision_tris = 0;    // tous les triangles de collision, mode compris (denominateur)
  // CE QUE LA POPULATION EXCLUT, CHIFFRE. Un seau exclu qu'on ne compte pas est un seau ou le
  // defaut se cache : les faces de chute des terrasses de Sandover sont des MURS (mode 1), donc
  // hors de ce recensement-ci, et `grass-edge-truth` en aura besoin.
  u64 mode_ground = 0, mode_wall = 0, mode_obstacle = 0, mode_other = 0;
  u64 by_material = 0;       // classes par le materiau de collision
  u64 by_texture = 0;        // classes par le nom de texture de rendu
  u64 by_both = 0;
  u64 classified = 0;        // classes par AU MOINS une source  <- `hits=` de l'item
  u64 unclassified = 0;      // classes par AUCUNE des deux      <- la porte
  // Ce que chaque source laisse seule dans le noir. `tex_only_unclassified` est la mesure de
  // l'etat d'AVANT : ce que le regime « trois noms de texture » ne sait pas classer.
  u64 tex_only_unclassified = 0;
  u64 mat_only_unclassified = 0;
  // Repartition par materiau (les quatre que la SPEC nomme, plus les deux seaux restants).
  u64 mat_grass = 0, mat_sand = 0, mat_dirt = 0, mat_stone = 0, mat_other = 0, mat_unnamed = 0;
  // Verdicts « herbe » des deux sources, et l'etat d'AVANT : les trois noms exacts en vigueur.
  u64 tex_grass = 0;
  u64 tex_grass_legacy3 = 0;
  // CE QUE LA REGLE EN VIGUEUR LAISSE SANS VERDICT. Calcule sur la MEME population et la MEME
  // donnee : c'est une comparaison de REGLES, pas la mesure d'un binaire d'avant.
  u64 legacy3_unclassified = 0;
  // Desaccords, dans les deux sens.
  u64 disagree = 0;
  u64 disagree_mat_grass_tex_not = 0;
  u64 disagree_tex_grass_mat_not = 0;
  // Geometrie de rendu indexee pour la source TEXTURE (temoin de non-vacuite).
  u64 render_ground_tris = 0;
  u64 render_draws = 0;
  u64 textures_seen = 0;
  // Noms, sans espace, prets pour `proof.txt` : "nom:compte,nom:compte,..." (10 au plus).
  std::string disagree_tex_top;
  std::string mat_grass_tex_top;   // textures posees SUR un materiau `grass`
  std::string tex_grass_mat_top;   // materiaux SOUS une texture herbeuse
};
// Deterministe, sans GL, sans horloge, sans fil : les memes octets rendent les memes comptes.
SurfaceCensus surface_census(const tfrag3::Level& lev, const std::string& level_name);
// Le nom d'un `pat-material` (pat-h.gc:5-27), ou nullptr hors table.
const char* pat_material_name(u32 material);
constexpr u32 kPatMaterialCount = 23;
// pat-h.gc:5-27, les quatre valeurs que la SPEC nomme plus `gravel`. Elles vivaient dans un
// namespace anonyme du .cpp, DEUX fois, et apres `scan_level` : le placement ne pouvait donc pas
// lire le materiau du sol. Une seule definition, ici, lue par le recensement ET par la cuisson.
constexpr u32 kPatMatStone = 0;
constexpr u32 kPatMatSand = 5;
constexpr u32 kPatMatGrass = 7;
constexpr u32 kPatMatGravel = 14;
constexpr u32 kPatMatDirt = 15;
// Un materiau sur lequel le JEU LUI-MEME a fait autre chose que de l'herbe : la SECONDE source
// qui autorise un recouvrement a piloter une transition (`ovl_material_is_path` appelle celle-ci).
inline bool pat_material_is_bare(u32 m) {
  return m == kPatMatSand || m == kPatMatDirt || m == kPatMatGravel || m == kPatMatStone;
}

// ---------------------------------------------------------------------------
// soft-surface-truth : UNE SURFACE EST DE NEIGE OU DE SABLE SELON DEUX SOURCES.
// ---------------------------------------------------------------------------
//
// SPEC-surfaces-meubles.md, sections 1 et 11. La campagne `soft-*` pose une COQUE de matiere
// sur le sable et la neige ; avant de poser quoi que ce soit il faut savoir OU, et le savoir
// par une mesure. `sand`=5, `snow`=9, `deepsnow`=10 vivent dans les memes bits 6..11 de
// `pat-surface` que `grass`=7 : c'est LE MEME LECTEUR que `grass-surface-truth`, et il est
// APPELE, pas recopie. Ce recensement-ci vit dans le meme fichier, apres lui, et se sert de ses
// helpers d'index et de son predicat de texture herbeuse tels quels — une seconde copie aurait
// derive, et le compte croise des deux campagnes serait devenu un artefact de recopie.
//
// CE RECENSEMENT NE PLACE RIEN, NE CUIT RIEN, N'ECRIT AUCUN FICHIER. Point 4 du contrat :
// l'image est identique au bit. Il lit, il croise, il compte, il NOMME.
//
// LES DEUX SOURCES, lues et publiees separement (point 1) :
//   MATERIAU : `(pat >> 6) & 0x3f`, exactement la lecture de `surface_census`. Elle dit MEUBLE
//              quand la valeur est `sand`, `snow` ou `deepsnow` ; elle se tait quand la valeur
//              ne nomme aucun `pat-material`.
//   TEXTURE  : le nom de la texture du triangle de RENDU qui couvre le centroide, par le MEME
//              index XZ et la MEME sonde. Elle dit MEUBLE quand le nom tombe dans un filet de
//              NOMS publie tel quel (`census_tex_is_sandy` / `census_tex_is_snowy`).
//
// LE DESACCORD SE COMPTE, IL NE SE DEVINE PAS (point 2). `disagree` = les deux sources classent
// et divergent sur « meuble ? » ; les deux sens sont separes et les textures impliquees sont
// NOMMEES par niveau. Un desaccord n'est PAS un defaut de cet item : c'est la donnee que
// `soft-support-map` et `soft-levels` consommeront.
//
// L'ARBITRAGE EST NOMME, ET C'EST LUI QUI REND L'EXCLUSIVITE AVEC L'HERBE (point 3). Chaque
// triangle recoit UNE classe resolue :
//     materiau nomme  -> la classe du MATERIAU tranche      (SPEC decision 12 : une texture de
//                        sable posee sur une collision `grass` est un mesh pose par-dessus, et
//                        la decision 12 l'EXCLUT de la coque tant que `grass-overlay-meshes`
//                        n'a pas mesure ; c'est donc la collision qui a le dernier mot)
//     materiau muet   -> la classe de la TEXTURE, faute de mieux
//     ni l'un ni l'autre -> INCONNUE : le triangle tombe dans `unclassified`, la grandeur de la porte
// Les classes etant exclusives, `cross_eligible` vaut zero par construction — c'est une GARDE,
// pas la mesure. LA MESURE, c'est `cross_raw` : le nombre de triangles que les deux campagnes
// se disputeraient si l'on prenait le OU des deux sources sans arbitrer. Il est publie a cote,
// avec les textures qui le composent, et il n'est PAS nul.
struct SoftSurfaceCensus {
  // Population et denominateurs — memes definitions que `SurfaceCensus`.
  u64 ground_tris = 0;
  u64 collision_tris = 0;
  u64 mode_ground = 0, mode_wall = 0, mode_obstacle = 0, mode_other = 0;
  // CE QUE LA POPULATION EXCLUT, CHIFFRE : les 2 952 triangles de sable en mode MUR de
  // `training` (SPEC section 1) sortent d'ici, et on les compte au lieu de les perdre.
  u64 mode_wall_soft = 0, mode_obstacle_soft = 0, mode_other_soft = 0;
  // Couverture des deux sources sur la population de sol.
  u64 by_material = 0, by_texture = 0, by_both = 0;
  u64 classified = 0;    // au moins une source  <- `hits=` de l'item
  u64 unclassified = 0;  // aucune des deux      <- premier terme de la porte
  u64 tex_only_unclassified = 0, mat_only_unclassified = 0;
  // SOURCE MATERIAU, par classe. `mat_soft` = sand + snow + deepsnow.
  u64 mat_sand = 0, mat_snow = 0, mat_deepsnow = 0, mat_soft = 0;
  u64 mat_grass = 0, mat_unnamed = 0;
  // SOURCE TEXTURE, par classe. `tex_soft` = sableuse ou neigeuse.
  u64 tex_sand = 0, tex_snow = 0, tex_soft = 0, tex_grass = 0;
  // CE QUE LA LISTE DE REJET DU FILET A ECARTE : un nom qui porte « sand »/« beach »/« snow »
  // mais aussi un jeton de matiere dure (`beachrock`, `snow-metalroof-01`). Compte ET nomme.
  u64 tex_reject = 0;
  // LE CROISEMENT DES DEUX SOURCES SUR LA QUESTION « MEUBLE ? ».
  u64 soft_by_material = 0, soft_by_texture = 0, soft_by_both = 0, soft_by_either = 0;
  u64 disagree = 0, disagree_mat_soft_tex_not = 0, disagree_tex_soft_mat_not = 0;
  // LA CLASSE RESOLUE, et l'exclusivite qui en decoule.
  u64 eligible_soft = 0;    // classe resolue sand/snow/deepsnow
  u64 eligible_grass = 0;   // classe resolue grass, par les predicats de `surface_census`
  u64 cross_eligible = 0;   // les deux a la fois — GARDE, nulle par construction
  u64 cross_raw = 0;        // les deux au sens du OU des sources — LA MESURE, non nulle
  u64 overlay_soft_tex_on_grass_mat = 0;  // decision 12 : texture meuble sur collision `grass`
  u64 overlay_grass_tex_on_soft_mat = 0;  // le sens inverse
  // Temoins de non-vacuite de la source TEXTURE.
  u64 render_ground_tris = 0, render_draws = 0, textures_seen = 0;
  // Noms, sans espace, prets pour `proof.txt` : "nom:compte,...".
  std::string mat_soft_tex_top;   // les textures posees SUR un materiau meuble
  std::string tex_soft_mat_top;   // les materiaux SOUS une texture meuble
  std::string disagree_tex_top;   // les textures des desaccords
  std::string cross_raw_tex_top;  // les textures du litige herbe/coque avant arbitrage
  std::string tex_reject_top;     // les noms que la liste de rejet a ecartes
};
// Deterministe, sans GL, sans horloge, sans fil : les memes octets rendent les memes comptes.
SoftSurfaceCensus soft_surface_census(const tfrag3::Level& lev, const std::string& level_name);
// pat-h.gc:5-27 — les deux valeurs de neige, a cote de `kPatMatSand` deja declare ci-dessus.
constexpr u32 kPatMatSnow = 9;
constexpr u32 kPatMatDeepSnow = 10;
// Un materiau que la campagne `soft-*` revendique (SPEC section 1).
inline bool pat_material_is_soft(u32 m) {
  return m == kPatMatSand || m == kPatMatSnow || m == kPatMatDeepSnow;
}

// ---------------------------------------------------------------------------
// grass-overlay-meshes : LES MESHES POSES PAR-DESSUS UN SOL HERBEUX.
// ---------------------------------------------------------------------------
//
// SPEC section 9. L'owner affirme qu'un second mesh est parfois pose AU-DESSUS d'un sol
// herbeux pour simuler l'absence d'herbe. C'est la SEULE de ses affirmations que
// l'investigation n'a su ni confirmer ni infirmer : le seul compteur voisin — les triangles
// strictement coincidents — ne regarde que les triangles DEJA filtres par les trois noms de
// texture d'herbe, si bien qu'un triangle de sable n'y entre jamais.
//
// CE RECENSEMENT MESURE D'ABORD, SANS PREJUGE, et il ne place rien. Un zero se lit « la
// superposition n'existe pas » et c'est une reponse valable ; c'est pourquoi le controle
// positif `overlay_census_selftest()` tourne a cote : sans lui, un zero de detecteur mort et
// un zero de donnee propre s'ecriraient pareil.
//
// DEUX METHODES QUI NE SE COPIENT PAS, chacune publiee seule, puis leur intersection :
//   A — GEOMETRIE : deux triangles de RENDU regardant tous deux vers le haut, dont les
//       empreintes au sol se recouvrent d'une aire franche, separes verticalement de peu, et
//       de textures DIFFERENTES dont l'une est herbeuse.
//   B — COLLISION : un triangle de COLLISION de materiau `grass` (pat bits 6..11) recouvert
//       par un triangle de RENDU texture sable ou terre. La collision et le nom de texture
//       sont deux sources qui ne se copient pas (grass-surface-truth les a separees).
//
// LA CLASSIFICATION EST NOMMEE, jamais arbitree en silence. Chaque superposition trouvee est
// rangee par ce que la COLLISION dit sous elle :
//   `path`   le materiau sous le mesh pose est sable/terre/gravier/pierre : le jeu lui-meme a
//            fait un chemin, le mesh n'est pas qu'un decor.
//   `patch`  le materiau sous lui est encore `grass` : c'est une piece decorative posee sur de
//            l'herbe, et la collision ne le sait pas.
//   `ambiguous` NOMME PAR SA RAISON : aucune collision dessous, materiau qui n'est ni herbe ni
//            chemin, ou ecart vertical sous le seuil de z-fighting (le dessus est indecidable).
// `unclassified` est ce qu'AUCUNE des trois ne nomme — c'est la grandeur de la porte, et c'est
// une somme de termes publies separement.
struct OverlayCensus {
  // Population et denominateurs.
  u64 render_up_tris = 0;      // triangles de rendu regardant vers le haut (la population)
  u64 render_big_tris = 0;     // ... dont trop etendus pour l'index : balayes a part
  u64 render_draws = 0;
  u64 collision_ground_declared = 0;  // triangles de collision de mode `ground` (le denominateur)
  u64 collision_ground_tris = 0;      // ... dont indexables : le reste est un quasi-mur, chiffre ici
  // L'entonnoir, terme par terme : un seuil qui vide la population se lit ici, pas apres coup.
  u64 pairs_tested = 0;        // paires reellement soumises au test        <- `hits=` de l'item
  u64 pairs_bbox = 0;          // ... dont les boites XZ se croisent
  u64 pairs_diff_tex = 0;      // ... et de textures differentes
  u64 pairs_one_grassy = 0;    // ... dont l'une est herbeuse
  u64 pairs_overlap_area = 0;  // ... et dont l'aire de recouvrement depasse le seuil
  u64 pairs_close_y = 0;       // ... et dont l'ecart vertical est faible : LA METHODE A
  u64 pairs_far_y = 0;         // recouvrement franc mais etage : un pont, pas une superposition
  // Ce que les paires retenues racontent.
  u64 pairs_bare_over_grass = 0;  // dessus non herbeux sur dessous herbeux : le cas de l'owner
  u64 pairs_grass_over_bare = 0;  // l'inverse
  u64 pairs_both_grassy = 0;
  u64 pairs_coincident = 0;       // ecart sous le z-fighting : le dessus est indecidable
  // Les deux methodes, en triangles de rendu DISTINCTS, et leur intersection.
  u64 method_a = 0;
  u64 method_b = 0;
  u64 method_b_coll_tris = 0;      // triangles de collision `grass` qui ont produit un B
  u64 method_b_probed = 0;         // triangles de collision `grass` sondes (le denominateur de B)
  u64 method_b_rejected_below = 0; // un mesh nu existe, mais SOUS la collision : pas par-dessus
  u64 method_b_named_bare = 0;     // ... dont la texture du dessus DIT sable/terre/gravier
  u64 intersection = 0;
  u64 found = 0;               // l'union : la population que la classification doit couvrir
  // Les trois classes.
  u64 cls_path = 0, cls_patch = 0, cls_ambiguous = 0;
  u64 ambig_no_collision = 0, ambig_material_other = 0, ambig_zfight = 0;
  // UN NOM DE TEXTURE ABSENT N'EMPECHE PAS DE CLASSER : la classe est lue sur la COLLISION, pas
  // sur le nom. Ce compteur est un TEMOIN publie, pas un terme de la porte — le compter comme
  // « non classe » aurait refuse une superposition que les deux sources savent pourtant nommer.
  u64 found_texture_unnamed = 0;
  // La porte, et les termes dont elle est la somme.
  u64 unclassified = 0;
  u64 unclass_material_unnamed = 0, unclass_no_rule = 0;
  u64 sum_check = 0;           // 1 si classes + unclassified == found
  // Noms, sans espace, prets pour `proof.txt`.
  std::string pair_tex_top;       // "dessus>dessous:compte,..."
  // LA PROVENANCE, qui NOMME ce qu'est le mesh pose : un arbre tfrag `dirt` est du terrain de
  // terre dans la donnee d'origine ; une piece TIE est un OBJET, et l'occultation d'objets la
  // traite deja. Les melanger ferait passer le plancher d'une hutte pour un chemin.
  std::string src_population_top;  // "tfrag-normal:12345,tie:6789,..."
  std::string pair_src_top;        // "tfrag-dirt>tfrag-normal:123,..."
  std::string found_src_top;
  std::string method_b_tex_top;
  std::string cls_path_tex_top;
  std::string cls_patch_tex_top;
  std::string ambiguous_tex_top;
};
// Deterministe, sans GL, sans horloge, sans fil.
OverlayCensus overlay_census(const tfrag3::Level& lev, const std::string& level_name);

// LE CONTROLE POSITIF DE L'INSTRUMENT, ET POURQUOI IL EXISTE. La reponse attendue de cet item
// peut etre ZERO, et un zero de detecteur mort s'ecrit exactement comme un zero de donnee sans
// superposition. Ce banc fabrique un niveau de trois zones — chemin, piece decorative, aucune
// collision — et le fait traverser a `overlay_census()` LUI-MEME, pas a une copie de ses
// primitives. Chaque classe doit etre PRODUITE : une classe morte se voit ici.
struct OverlaySelftest {
  u64 method_a = 0, method_b = 0, intersection = 0, found = 0;
  u64 cls_path = 0, cls_patch = 0, cls_ambiguous = 0, unclassified = 0;
  u64 pairs_tested = 0;
  u64 ok = 0;  // 1 si les trois classes sont produites et `unclassified` vaut 0
};
OverlaySelftest overlay_census_selftest();

// ---------------------------------------------------------------------------
// grass-edge-truth : LE BORD QUI DONNE SUR LE VIDE, ETABLI PAR LA GEOMETRIE.
// ---------------------------------------------------------------------------
//
// SPEC sections 2 et 16. Le detecteur en vigueur (`scan_level`, GrassBakeCore.cpp:596-694)
// declare qu'une arete ouvre sur le vide des qu'AUCUN AUTRE TRIANGLE TEXTURE HERBE ne la
// partage : `edge_count[...] <= 1`. C'est une question de TOPOLOGIE posee sur une population
// filtree par TROIS noms de texture. Aucun test geometrique du vide n'existe nulle part.
// Une frontiere de materiau — pelouse vers terre — porte donc exactement la meme signature
// qu'un precipice, et c'est la cause racine des onze rounds d'overhang.
//
// CE RECENSEMENT NE PLACE RIEN ET NE DEPLACE RIEN. Comme `surface_census` et `overlay_census`
// il ne partage aucune variable avec `scan_level` / `expand`, n'ecrit dans aucune structure
// cuite et n'est appele par aucun chemin de placement : le `.grassbake` est identique au bit.
//
// LA POPULATION : les aretes UNIQUES (sommets soudes a 3 cm) des triangles de collision de
// mode 0 — le sol tel que le jeu le definit, la meme porte que `GrassBakeCore.cpp:816` et que
// `surface_census`. Les triangles degeneres en projection XZ en sont EXCLUS, et cette
// exclusion est COMPTEE (`tris_xz_degenerate`) : un seau exclu qu'on ne compte pas est un
// seau ou le defaut se cache.
//
// LE « DE L'AUTRE COTE » EST TROUVE PAR SONDE, JAMAIS PAR TOPOLOGIE. Pour chaque arete on
// sort de `EDGE_OUT_M` metres dans le plan XZ, PERPENDICULAIREMENT a l'arete, du cote oppose
// au troisieme sommet, et on cherche le sol marchable le plus haut dans la fenetre verticale
// [-EDGE_DROP_M, +EDGE_UP_M] autour du milieu de l'arete. Ce triangle-la — pas le voisin
// topologique — est le « au-dela » qui repond a toutes les questions suivantes. Une arete
// qu'aucun triangle ne partage mais sous laquelle le sol continue N'EST PAS un bord ; une
// arete partagee au-dessus d'un a-pic EN EST un. Les deux ecarts sont comptes
// (`unshared_but_floor`, `shared_but_void`) : c'est la mesure de la faute des onze rounds.
//
// LES HUIT CLASSES DE L'OWNER, EVALUEES COMME HUIT PREDICATS INDEPENDANTS et non par une
// cascade `else if` : chacun porte dans son enonce les negations qui le rendent disjoint des
// sept autres. On les evalue TOUS LES HUIT sur chaque arete et on COMPTE combien la
// reclament. `claimed_none` et `claimed_multi` sont donc des controles de somme sur la forme
// des predicats — ils valent structurellement zero tant que les predicats sont bien formes, et
// c'est dit ici plutot que presente comme une mesure. CE QUI FALSIFIE VRAIMENT LA SONDE est
// ailleurs : `edge_probe_selftest()`, dix-neuf aretes NOMMEES sur les dix cas geometriques de
// la SPEC, chacune portant une reponse ATTENDUE declaree AVANT la course, dans les DEUX
// polarites (onze « vide », huit « le sol continue »). Une sonde qui repondrait toujours
// « vide » y meurt ; une porte qui ne compterait que des attendus « vide » serait verte par
// inaction.
//
//   1 kEdgeTriangle     le sol continue au-dela, et RIEN ne differe : simple pavage.
//   2 kEdgeUvSeam       ... mais le triangle de RENDU qui couvre l'autre cote change de
//                       texture : une couture de fragment, pas un bord.
//   3 kEdgeMaterial     ... mais le `pat-material` change, hors du cas « chemin ».
//   4 kEdgeNormalBreak  ... mais les normales de face rompent de plus de EDGE_NORMAL_DEG.
//   5 kEdgeChunk        ... mais les deux centroides tombent dans deux mailles distinctes de
//                       la grille de `CHUNK_MAX_DIAG_M` que borne grass-chunk-cull.
//   6 kEdgeOverlay      l'autre cote est un mesh POSE PAR-DESSUS : collision `grass`, rendu
//                       nu (sable/terre). La definition de `overlay_census` (methode B).
//   7 kEdgePath         l'autre cote est un chemin fait par le jeu lui-meme : on part d'un
//                       materiau `grass` et on arrive sur sable/terre/gravier/pierre.
//   8 kEdgeVoid         LE VERITABLE BORD : la sonde ne trouve AUCUN sol marchable au-dela.
//
// L'ANCIENNE REGLE EST REJOUEE SUR LA MEME DONNEE, pas citee de memoire : `old_rule_void`
// applique `edge_count <= 1` sur la population des triangles de sol dont la texture de rendu
// porte l'un des TROIS noms historiques. Les deux verdicts sont publies cote a cote, avec
// leur intersection et leurs deux differences.
//
// LE FAUX VERT DU ROUND 4 EST RENDU IMPOSSIBLE par `terrace_dirt_void` : les aretes que la
// GEOMETRIE declare sur le vide et qu'un triangle de collision NON MARCHABLE de materiau
// `dirt` partage — c'est-a-dire le haut d'une terrasse dont la face de chute est EN TERRE, le
// cas exact ou les rounds 1 a 4 ne posaient aucun brin pendant que leurs metriques passaient.
// Ce compte doit etre NON NUL, et il est publie par niveau a cote de ce que l'ancienne regle
// trouvait sur les MEMES aretes.
constexpr float EDGE_OUT_M = 0.35f;       // de combien on sort de l'arete, dans le plan XZ
constexpr float EDGE_DROP_M = 1.0f;       // en deca, une marche : le sol continue
constexpr float EDGE_UP_M = 1.5f;         // au-dessus, une montee : le sol continue aussi
constexpr float EDGE_NORMAL_DEG = 25.0f;  // au-dela, rupture de normale
constexpr float EDGE_WELD_M = 0.03f;      // la MEME soudure canonique que le socle (round 16)
constexpr float EDGE_BUCKET_M = 4.0f;     // maille XZ de l'index de sol marchable
constexpr float EDGE_OUT_FAR_M = 0.70f;   // temoin de sensibilite : deux fois plus loin
constexpr float EDGE_DROP_FAR_M = 2.5f;   // temoin de sensibilite : deux fois et demie plus bas

enum EdgeClass : u8 {
  kEdgeClassNone = 0,
  kEdgeTriangle = 1,
  kEdgeUvSeam = 2,
  kEdgeMaterial = 3,
  kEdgeNormalBreak = 4,
  kEdgeChunk = 5,
  kEdgeOverlay = 6,
  kEdgePath = 7,
  kEdgeVoid = 8,
  kEdgeClassCount = 9,
};
const char* edge_class_name(u8 cls);

// Une arete NOMMEE, interrogee par ses deux extremites (unites GOAL). Le recensement rend la
// classe qu'il lui a donnee LUI-MEME, au milieu de sa boucle : le banc ne rejoue aucune copie
// des primitives.
struct EdgeQuery {
  float ax, ay, az;
  float bx, by, bz;
};

struct EdgeCensus {
  // ---- POPULATION ET CE QU'ELLE EXCLUT, CHIFFRE.
  u64 collision_tris = 0;       // tous les triangles de collision (denominateur)
  u64 mode_ground = 0;          // ... de mode 0
  u64 tris_used = 0;            // ... retenus (non degeneres en XZ)
  u64 tris_xz_degenerate = 0;   // EXCLUS, et nommes : pas de direction sortante definie
  u64 verts_raw = 0, verts_welded = 0;
  u64 edges_total = 0;          // aretes UNIQUES apres soudure  <- le denominateur de tout
  u64 edges_zero_length = 0;    // deux sommets soudes en un : aucune direction sortante
  u64 edge_slots = 0;           // 3 * tris_used (avant deduplication)
  u64 deg1 = 0, deg2 = 0, deg3plus = 0;  // TOPOLOGIE : temoin seul, elle ne decide rien

  // ---- LES HUIT CLASSES.
  u64 cls[kEdgeClassCount] = {};
  u64 classified = 0;      // reclamees par EXACTEMENT une classe  <- `hits=` de l'item
  u64 claimed_none = 0;    // <- terme de la porte
  u64 claimed_multi = 0;   // <- terme de la porte
  u64 class_sum_check = 0; // 1 si la somme des huit classes vaut `edges_total`

  // ---- LA SONDE, ET CE QU'ELLE VOIT.
  u64 beyond_found = 0, beyond_missing = 0;
  u64 probe_selfhit = 0;            // la sonde est retombee sur son propre triangle (garde)
  u64 void_with_far_floor = 0;      // vide, mais un sol existe PLUS BAS que la fenetre
  u64 void_no_floor_at_all = 0;     // vide, et rien du tout dessous
  u64 void_out_far = 0;             // le meme compte a EDGE_OUT_FAR_M  (sensibilite)
  u64 void_drop_far = 0;            // le meme compte a EDGE_DROP_FAR_M (sensibilite)
  u64 unshared_but_floor = 0;       // LA FAUTE DES ONZE ROUNDS, mesuree
  u64 shared_but_void = 0;          // l'ecart inverse, mesure aussi
  u64 own_unrendered = 0;           // aucun triangle de rendu ne couvre ce cote
  u64 beyond_unrendered = 0;        // ... ni celui-la : temoin d'aveuglement de `kEdgeUvSeam`
  u64 beyond_mat_unnamed = 0;       // materiau hors table : la DIFFERENCE reste lisible

  // ---- L'ANCIENNE REGLE, REJOUEE SUR LA MEME DONNEE.
  u64 legacy_tris = 0;        // triangles de sol sous l'un des TROIS noms historiques
  u64 legacy_edges = 0;       // leurs aretes : le denominateur de la comparaison
  u64 old_rule_void = 0;      // `edge_count <= 1` sur cette population
  u64 geom_void_on_legacy = 0;
  u64 old_only = 0;           // l'ancienne dit vide, la geometrie dit non : LES FAUX PRECIPICES
  u64 geom_only = 0;          // la geometrie dit vide, l'ancienne ne le voyait pas
  u64 void_both = 0;

  // ---- LE CAS DU ROUND 4 : LES TERRASSES A FACE DE CHUTE EN TERRE.
  u64 void_edges_with_wall = 0;   // aretes sur le vide qu'un triangle NON marchable partage
  u64 terrace_dirt_void = 0;      // ... et ce triangle est en `dirt`   <- terme de la porte
  u64 terrace_sand_void = 0;
  u64 terrace_stone_void = 0;
  u64 terrace_dirt_void_old = 0;  // combien l'ancienne regle en voyait, sur les MEMES aretes
  // LA GENERALISATION HONNETE. La SPEC annonce des faces de chute EN TERRE a Sandover ; la
  // donnee de collision y repond `stone` et `wood`. Le cas du round 4 n'est pas le materiau
  // `dirt`, c'est une face de chute qui n'est PAS de l'herbe : elle sort de la population des
  // trois noms, et l'ancienne regle ne pouvait pas la distinguer d'un precipice.
  u64 terrace_nongrass_void = 0;
  u64 terrace_dirt_on_grass = 0;  // ... dont le HAUT est un materiau `grass`

  // ---- NOMS, sans espace, prets pour proof.txt ("nom:compte,...", 10 au plus).
  std::string void_wall_mat_top;   // les materiaux des faces de chute
  std::string material_pair_top;   // "grass>dirt:123,..." aux separations de materiau
  std::string void_tex_top;        // les textures de rendu des cotes qui donnent sur le vide
  std::string class_top;           // les huit classes, par compte
};

// Deterministe, sans GL, sans horloge, sans fil : les memes octets rendent les memes comptes.
// `queries` / `out_class` sont le canal du banc nomme : `out_class[i]` recoit la classe que
// CETTE fonction a donnee a l'arete `queries[i]`, ou `kEdgeClassNone` si elle ne l'a pas vue.
EdgeCensus edge_census(const tfrag3::Level& lev, const std::string& level_name,
                       const EdgeQuery* queries = nullptr, size_t n_queries = 0,
                       u8* out_class = nullptr);

// LE BANC NOMME. Dix cas geometriques de la SPEC section 16, dix-neuf aretes, chacune avec sa
// reponse ATTENDUE ecrite dans le code AVANT la course, et les DEUX polarites. Chaque cas
// fabrique un niveau en memoire et le fait traverser a `edge_census()` LUI-MEME.
struct EdgeSelftest {
  u64 cases = 0;
  u64 agree = 0;
  u64 disagree = 0;      // <- terme de la porte
  u64 not_found = 0;     // arete nommee jamais vue : compte AUSSI comme desaccord
  u64 expect_void = 0;   // les deux polarites sont presentes, et c'est publie
  u64 expect_floor = 0;
  u64 ok = 0;
  std::string verdict_list;   // "nom:classe,..." dans l'ordre declare
  std::string disagree_list;  // "nom:attendu>obtenu,..." ou "-"
};
EdgeSelftest edge_probe_selftest();

// ---------------------------------------------------------------------------
// grass-path-transitions : CE QUE LA TRANSITION PRODUIT, MESURE SUR LES BRINS EMIS.
// ---------------------------------------------------------------------------
//
// Le recensement ne relit AUCUNE de ses propres constantes pour juger : il lit des positions de
// brins et des distances geometriques a l'empreinte du sol nu. Les quatre points du contrat :
//   1. PAS DE BANDE VIDE   -> `gap_*` : de chaque candidat pose A LA LIMITE de la zone nue, la
//      distance au brin EMIS le plus proche. Le plafond est declare, les quantiles publies.
//   2. PAS D'INVASION      -> `blades_inside` sur `blades_tested`.
//   3. PAS DE DECOUPE NETTE-> `edge_follow_frac` : part des cellules ou la densite locale croise
//      50 % dont la distance a l'empreinte tient dans +/- 5 cm de la mediane. Une frontiere qui
//      suit un decalage constant rend 1,0 ; une frontiere dentelee rend peu.
//   4. TRANSITION PROGRESSIVE -> `band_ratio[]` / `band_height[]` par tranche de 25 cm, et
//      `graded_frac`, la part des cellules de la bande dont la densite locale n'est ni ~0 ni ~1.
struct TransitionCensus {
  // ---- LES DEUX SOURCES, et ce que chacune seule aurait dit.
  u64 bare_draws_seen = 0;       // draws non-herbe examines (tfrag + tie)
  u64 bare_draws_geom = 0;       // ... retenus par la geometrie de rendu (plats, bas, assez larges)
  u64 bare_draws_mat = 0;        // ... dont le materiau de collision dessous est NU
  u64 bare_draws_both = 0;       // les deux -> RECOUVREMENT DE SOL
  u64 bare_draws_disagree = 0;   // geometrie oui / materiau non, ou l'inverse
  u64 bare_tris = 0;             // triangles d'empreinte retenus
  double bare_area_m2 = 0.0;     // leur aire XZ
  u64 occ_pts_object = 0;        // points d'occultation restes OBJETS (comportement inchange)
  u64 occ_pts_removed = 0;       // points retires de l'occultation binaire (ils sont devenus champ)
  std::string bare_tex_top;      // "texture:aire_dm2,..." des draws RETENUS
  std::string bare_rej_top;      // "texture:raison:aire_dm2,..." des draws ECARTES
  std::string bare_mat_top;      // "materiau:faces,..." sous les faces plates non-herbe
  u64 faces_up = 0;              // faces non-herbe regardant vers le haut, examinees
  u64 faces_bare_mat = 0;        // ... dont le plancher de collision est NU
  u64 faces_affleurantes = 0;    // ... et qui affleurent ce plancher  -> empreinte
  u64 faces_lifted = 0;          // ... mais SOULEVEES : un dessus d'objet, pas une dalle
  u64 faces_nofloor = 0;         // ... sans plancher sous elles dans la fenetre
  // ---- LA POPULATION DE BRINS.
  u64 blades_total = 0;          // instances emises
  u64 blades_tested = 0;         // instances dont la distance a un sol nu est CONNUE (< PATH_ENC_MAX)
  u64 blades_inside = 0;         // POINT 2 : racine DANS l'empreinte nue
  u64 blades_band = 0;           // racine dans [0, TRANS_W_M]
  u64 cand_total = 0;            // candidats enumerables
  u64 cand_inside = 0;           // candidats dans l'empreinte (le chemin, avant coupe)
  u64 cand_limit = 0;            // POINT 1 : candidats A LA LIMITE (0 < d <= LIMIT_BAND)
  // ---- POINT 1 : la bande vide, en metres.
  float gap_p50 = -1.f, gap_p90 = -1.f, gap_p99 = -1.f, gap_max = -1.f;
  u64 gap_over_cap = 0;          // echantillons au-dessus du plafond principal, TOUTES causes
  // POURQUOI UN ECHANTILLON EST NU. Un trou a la limite d'un chemin peut venir de quatre causes,
  // et une seule est la notre. Les ECARTER sans les compter rendrait n'importe quel zero vert :
  // chacune est publiee, et seule `gap_cause_trans` alimente la porte.
  u64 gap_cause_nofloor = 0;   // il n'y a pas de plancher sous ce voisinage (cull de porte-a-faux)
  u64 gap_cause_object = 0;    // un OBJET l'occulte encore a 0,45 m — `recharged-grass-object-clip`
  u64 gap_cause_nograss = 0;   // aucun candidat d'herbe dans le rayon : ce bord n'est pas herbeux
  u64 gap_cause_inside = 0;    // le voisinage est le CHEMIN lui-meme : il doit rester degage
  u64 gap_cause_trans = 0;     // AUCUNE des trois : c'est la transition qui a laisse le trou
  float gap_defect_frac = -1.f;
  float gap_defect_max = -1.f;
  // Ce que le voisinage d'un trou IMPUTE a la transition contient vraiment : sans ces deux
  // nombres, « trop eclairci » et « deja pauvre en candidats » s'ecriraient du meme zero.
  float gap_defect_cands = -1.f;  // candidats moyens dans le rayon
  float gap_defect_thin = -1.f;   // ... dont la transition a retire
  // ---- POINT 3 : la rectitude du bord.
  u64 front_cells = 0;           // cellules de croisement 50 % trouvees
  float front_median_m = -1.f;
  float edge_follow_frac = -1.f;
  // ---- POINT 4 : la progressivite.
  u64 band_cells = 0;
  float graded_frac = -1.f;      // part des cellules de bande a densite locale strictement moyenne
  // DEUX DENOMINATEURS, ET C'EST LE SUJET. `band_ratio` divise par TOUS les candidats de la
  // tranche : sur `beach`, 93 % d'entre eux sont deja retires par le cull de plancher ou par
  // l'occultation d'objet, deux causes qui n'ont rien a voir avec cet item et qui se renforcent
  // pres d'un chemin — la « densite » y decroissait donc a l'envers. `band_dens` divise par les
  // candidats ELIGIBLES (bits plancher et objet tenus) : c'est la seule population sur laquelle
  // la transition decide. Les deux sont publiees, et la part eligible avec, pour que la
  // contamination se LISE au lieu de se deviner.
  float band_ratio[4] = {-1.f, -1.f, -1.f, -1.f};   // contamine — publie pour information
  float band_elig[4] = {-1.f, -1.f, -1.f, -1.f};    // part des candidats eligibles par tranche
  float band_dens[4] = {-1.f, -1.f, -1.f, -1.f};    // densite relative SUR LES ELIGIBLES
  float band_height[4] = {-1.f, -1.f, -1.f, -1.f};  // hauteur moyenne relative par tranche
  float interior_height = -1.f;
  u32 mono_ratio_breaks = 0, mono_height_breaks = 0, mono_dens_breaks = 0;
  // LA RAMPE EXISTE-T-ELLE VRAIMENT ? Un champ qui ne descend pas est un champ absent : une
  // valeur neutre serait un vert par INACTION. `TRANS_RAMP_MAX` est le rapport maximal tolere
  // entre la tranche du bord et celle du fond de bande.
  u8 dens_ramp_missing = 1, height_ramp_missing = 1;
  // ---- Temoins de non-vacuite.
  u8 population_empty = 1;       // aucun brin
  u8 bare_absent = 1;            // aucun sol nu retenu : la mesure ne dit RIEN, elle ne dit pas « zero »
  u8 band_absent = 1;            // aucun brin dans la bande
  u8 limit_absent = 1;           // aucun candidat a la limite
  u64 blades_interior = 0;       // brins hors de portee de tout sol nu
  // TEMOIN DE NON-DIVERGENCE : le recensement recalcule la position d'un candidat emis et la
  // compare a celle du brin. Une seule divergence invaliderait toute mesure prise sur les
  // candidats NON emis, ceux que precisement on veut voir.
  u64 pos_mismatch = 0;
  u32 terms_measured = 0;        // combien des termes ci-dessus ont ete reellement MESURES
};
// Deterministe, sans GL, sans horloge, sans fil. `d` et `e` doivent venir du MEME scan.
TransitionCensus transition_census(const BakeData& d, const ExpandResult& e);

// ---------------------------------------------------------------------------
// grass-clumps : CE QUE LE REGROUPEMENT A PRODUIT, MESURE ET NON AFFIRME.
// ---------------------------------------------------------------------------
//
// « Une touffe qu'aucune mesure ne distingue d'un tirage uniforme n'existe pas. » Le recensement
// calcule donc DEUX fois la meme statistique sur LA MEME population, LA MEME surface et LE MEME
// compte de brins : une fois sur les racines livrees, une fois sur les racines que le tirage
// uniforme — le code REMPLACE, toujours calcule par `ClumpPlacer::place` — leur aurait donnees.
// Ce second bras n'est pas un miroir : c'est l'autre regime, dans la meme image.
//
// La statistique est le NOMBRE MOYEN DE VOISINS a `CLUMP_PAIR_R_M`, restreint aux racines situees
// a plus de ce rayon de toute arete de leur triangle support — sans cette restriction on
// mesurerait le decoupage du maillage, pas le regroupement.
struct ClumpCensus {
  // --- point 1 : la dispersion spatiale, les deux bras
  double pairs_clumped = 0.0;   // voisins moyens a CLUMP_PAIR_R_M, racines livrees
  double pairs_uniform = 0.0;   // ... memes brins, tirage uniforme
  double pairs_ratio = 0.0;     // le rapport que la porte lit
  u64 pairs_sampled = 0;        // racines interieures effectivement comptees (denominateur)
  // --- point 2 : les touffes ne se ressemblent pas
  u64 clumps_total = 0;
  u64 clumps_mounted = 0;
  double size_mean = 0.0, size_cv = 0.0;      // brins par touffe montee
  double radius_mean_m = 0.0, radius_cv = 0.0;
  // --- point 4 et integrite
  u64 origin_digest = 0;    // empreinte des origines de TOUTES les touffes des tris porteurs
  u64 blades_total = 0;
  u64 root_outside = 0;     // racines hors de leur triangle support (SPEC section 9) : doit etre 0
  u64 pos_mismatch = 0;     // ecart entre la racine emise et celle que le recensement recalcule
  u64 clipped = 0;          // racines raccourcies par le bord du triangle (publie, non juge)
  double height_mean_ratio = 0.0;  // hauteur moyenne livree / hauteur moyenne sans profil de touffe
  u32 terms_measured = 0;   // combien des grandeurs ci-dessus ont une population non vide
};
ClumpCensus clump_census(const BakeData& d, const ExpandResult& e);

// Nidification entre DEUX paliers du meme niveau : les origines bougent-elles, et l'ensemble des
// candidats du palier bas est-il un PREFIXE de celui du palier haut ? Les deux `BakeData` viennent
// de deux `scan_level` du meme `.fr3`, donc leurs `tris` sont alignes index par index.
struct ClumpNestCensus {
  u64 tris_compared = 0;
  u64 tris_misaligned = 0;  // meme index, geometrie differente -> comparaison impossible
  u64 clumps_compared = 0;
  u64 origin_moved = 0;     // touffes dont l'origine bouge d'un palier a l'autre : doit etre 0
  u64 count_mismatch = 0;   // triangles dont le NOMBRE de touffes change : doit etre 0
  u64 prefix_breaks = 0;    // candidats du palier bas absents du palier haut : doit etre 0
  u64 blades_low = 0, blades_high = 0;
};
ClumpNestCensus clump_nest_census(const BakeData& lo, const ExpandResult& elo, const BakeData& hi,
                                  const ExpandResult& ehi);


bool save_bake(const BakeData& d, const std::string& path);
bool load_bake(BakeData& d, const std::string& path);  // false on missing/magic/version mismatch

}  // namespace grass_bake
