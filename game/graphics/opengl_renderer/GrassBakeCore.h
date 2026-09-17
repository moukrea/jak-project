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
};
ExpandResult expand(const BakeData& d, float density_slider_pct);

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

bool save_bake(const BakeData& d, const std::string& path);
bool load_bake(BakeData& d, const std::string& path);  // false on missing/magic/version mismatch

}  // namespace grass_bake
