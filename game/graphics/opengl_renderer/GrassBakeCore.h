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
constexpr int COMB_MAX = 60000;       // hard ceiling for comb replacement twins
constexpr float NOFF_M = 0.03f;       // root offset along the smooth normal (shader scales by w)
constexpr float DROOP_AREA_DENS = 130.0f;  // droop blades per m^2 of fringe/lip face (scatter)
constexpr float PLANE_CLEAR_M = 0.02f;     // rest tip must clear every nearby tri plane by this
constexpr float SHADER_TILT_DEFAULT = 0.30f;  // u_tilt the rest-pose plane cap assumes

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
  u32 flags;                  // bit0 is_tie, bit1 is_lip, bit2 is_dup, bit3 is_fringe (droop-only tri), bit4 is_transition (ROUND3: curl band, blades combed when toggle ON)
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
};
ExpandResult expand(const BakeData& d, float density_slider_pct);

bool save_bake(const BakeData& d, const std::string& path);
bool load_bake(BakeData& d, const std::string& path);  // false on missing/magic/version mismatch

}  // namespace grass_bake
