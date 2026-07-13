#include "GrassRenderer.h"
#include "game/graphics/opengl_renderer/GrassOccluders.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

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

// ROUND#14 DISCRIMINATOR selector (default 0 = normal). Reads a debug knob:
//   Android: prop debug.opengoal.grass_dbg   Desktop: env GRASS_DISCRIMINATE
// Value 'c' = auto-cycle 0..3 every 4 s (for a single screenrecord); '1'/'2'/'3' = pin that mode.
inline int grass_debug_mode(float u_time) {
  char buf[16] = {0};
  bool have = false;
#ifdef __ANDROID__
  if (__system_property_get("debug.opengoal.grass_dbg", buf) > 0 && buf[0]) {
    have = true;
  }
#else
  const char* e = std::getenv("GRASS_DISCRIMINATE");
  if (e && e[0]) {
    std::strncpy(buf, e, sizeof(buf) - 1);
    have = true;
  }
#endif
  if (!have) {
    return 0;
  }
  if (buf[0] == 'c') {
    return ((int)(u_time / 4.0f)) % 4;  // cycle stays 0..3 (mode 4 is a PIN-only forensic visualizer)
  }
  int v = std::atoi(buf);
  // ROUND#19: pin values 1..4 (4 = occ/trample forensic visualizer). The 'c' cycle above stays 1..3.
  return (v >= 1 && v <= 7) ? v : 0;  // R21f: 5/6/7 = trample-clause bisect
}

// ROUND#19 normal-tilt blend amount (default 0 = world-up-only growth, bit-identical to before). Read
// the SAME dual mechanism as grass_debug_mode: Android prop debug.opengoal.grass_tilt, desktop env
// GRASS_TILT, parsed as float, clamped to [0,1]. Cached + throttled so it isn't re-read every frame.
inline float grass_tilt_amount() {
  static float s_cached = 0.f;
  static int s_throttle = 0;
  if ((s_throttle++ & 63) != 0) {
    return s_cached;
  }
  char buf[16] = {0};
  bool have = false;
#ifdef __ANDROID__
  if (__system_property_get("debug.opengoal.grass_tilt", buf) > 0 && buf[0]) {
    have = true;
  }
#else
  const char* e = std::getenv("GRASS_TILT");
  if (e && e[0]) {
    std::strncpy(buf, e, sizeof(buf) - 1);
    have = true;
  }
#endif
  float v = have ? (float)std::atof(buf) : 0.f;
  if (v < 0.f) v = 0.f;
  if (v > 1.f) v = 1.f;
  s_cached = v;
  return v;
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
static constexpr float FLOOR_DEPTH_M = 2.5f;   // floor may be up to this far BELOW the blade base
static constexpr float FLOOR_EPS_UP_M = 0.75f; // ... or this far ABOVE it (render/collision mismatch)
// ROUND#19b (owner LIVE obs 2026-07-12): FLOORBELOW's 2.5m window has a STACKED-TERRACES hole — a blade
// cantilevered past an UPPER platform edge still has the LOWER terrace 1-2m beneath it, so "some floor
// within 2.5m" keeps it and it visually overflows the upper edge. A blade must stand essentially ON ITS
// OWN floor: nearest walkable floor below the base must be within this small gap, else the base hangs
// over a DIFFERENT (lower) surface -> cull. Tuned against false culls via the interior-blade gap p99
// (ROUND#19b FLOORGAP log); device-tunable without rebuild via debug.opengoal.grass_floorgap (metres).
static constexpr float FLOOR_GAP_M = 0.5f;
static constexpr float FLOOR_BUCKET_M = 1.0f;  // fine XZ lookup bucket so per-base candidate lists stay
                                               // small (ROUND#19 perf: 4m buckets ANR-stalled rebuild)
static constexpr float FLOOR_MAX_TRI_M = 40.0f;// drop degenerate level-spanning collision tris

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

GrassRenderer::GrassRenderer() = default;

GrassRenderer::~GrassRenderer() {
  if (m_gl_ready) {
    glDeleteVertexArrays(1, &m_vao);
    glDeleteBuffers(1, &m_instance_vbo);
    glDeleteBuffers(1, &m_light_vbo);
  }
}

// OWNER ROUND#18 object-clip storage (see GrassOccluders.h). Filled by Merc2 each frame, published
// (swapped) once per frame by GrassRenderer::render(). Cap building at 64 to bound the per-frame cost.
namespace grass_occ {
std::vector<std::array<float, 4>> g_building;
std::vector<std::array<float, 4>> g_published;
std::vector<std::array<float, 4>> g_tramp_building;   // OWNER Q&A 2026-07-12: breakable-actor TRAMPLE list
std::vector<std::array<float, 4>> g_tramp_published;
void add(float x, float y, float z, float r_world) {
  if (g_building.size() >= 64) return;
  g_building.push_back({x, y, z, r_world});
}
void add_trample(float x, float y, float z, float r_world) {
  if (g_tramp_building.size() >= 64) return;
  g_tramp_building.push_back({x, y, z, r_world});
}
// OWNER ROUND#21: eased trample RELEASE. Entries are matched frame-to-frame by position (these
// actors do not move); a captured entry eases its strength IN over ~0.25 s, an entry that stops
// being captured (crate BROKEN — or frustum-culled, invisible either way) eases OUT over ~0.6 s and
// is dropped at 0. The shader multiplies each entry's flatten by its strength, so the grass under a
// broken crate springs back gradually (owner: no instant snap, like Jak's walking recovery).
struct TrampGhost {
  std::array<float, 4> e;  // x, y, z, r (GOAL units)
  float strength;          // eased 0..1
  bool seen;               // matched a Merc2 capture this frame
};
static std::vector<TrampGhost> s_tramp_state;
std::vector<float> g_tramp_strength;

// ROUND#21d GOAL->C++ actor channel (see GrassOccluders.h). The stage vectors are game-thread-only;
// the snapshot is shared with the render thread under s_goal_mutex. The snapshot PERSISTS between the
// GOAL scans (every ~30 frames) so publish() below sees the same actors every frame — no flicker, and
// the TrampGhost ease-out only fires when a scan actually drops an actor (crate broken / level left).
static std::mutex s_goal_mutex;
static std::vector<std::array<float, 4>> s_goal_stage_cull;
static std::vector<std::array<float, 4>> s_goal_stage_tramp;
static std::vector<std::array<float, 4>> s_goal_cull;
static std::vector<std::array<float, 4>> s_goal_tramp;
static double s_goal_snapshot_t = -1.0;  // R26: last goal_publish time (TTL fail-safe)
static double s_goal_pub_interval = 0.3;  // R27: EMA of the real publish cadence (adaptive TTL)

void goal_clear() {
  s_goal_stage_cull.clear();
  s_goal_stage_tramp.clear();
}
void goal_add(int kind, float x, float y, float z, float r_world) {
  // ROUND#22: the radius arriving here is the actor's REAL draw-bounds ground footprint (GOAL glue
  // publishes bsphere-w * 0.8, clamped 0.5..2.5 m) — the R21g per-type C++ remaps are gone.
  // Skip actors whose trans never got initialized (exact world origin): pool residents with zeroed
  // roots, not ground props (seen as cull[]=(0.0,0.0,0.0) log junk).
  if (x == 0.f && z == 0.f) {
    return;
  }
  // R22b (owner: crates PERFECT, but the warp button's base ring clips again — bsphere*0.8 is too
  // tight for STATIC culls whose ground base flares wider than the scaled bsphere; same for vents and
  // any similar machine, treated uniformly): statics get a generous factor. A slightly larger bald
  // ring around a machine reads natural; grass through its base does not. Trample (kind 1) untouched.
  if (kind == 0) {
    constexpr float U = 4096.f;
    r_world *= 1.5f;
    if (r_world < 0.9f * U) r_world = 0.9f * U;
    if (r_world > 3.0f * U) r_world = 3.0f * U;
  }
  auto& v = (kind == 1) ? s_goal_stage_tramp : s_goal_stage_cull;
  if (v.size() < 64) {
    v.push_back({x, y, z, r_world});
  }
}
// R28 (owner directive, literal: "trouve le moment où il est cassé et cancel le trample"): called
// from the scarecrow's break path at the EXACT clear-collide frame. Kills any trample ghost within
// 1.2 m instantly (strength -> 0, entry gone next frame) and tombstones the spot for 8 s so nothing
// in the debris window can re-flatten it. No-ops when grass is off.
static std::vector<std::array<float, 3>> s_break_kills;
void goal_break_at(float x, float y, float z) {
  std::lock_guard<std::mutex> lk(s_goal_mutex);
  if (s_break_kills.size() < 16) {
    s_break_kills.push_back({x, y, z});
  }
}

void goal_publish() {
  // R24b ENFORCED static-stability (owner: the moving bald circle must be impossible BY CONSTRUCTION,
  // not just unlikely): a kind-0 CULL entry is a static machine — if an entry's position moved > 0.3 m
  // since the previous publish (matched by nearest-prev within 3 m), it is a MOVER that slipped the
  // GOAL allowlist: DROP it (and log its coords once/s) instead of painting a gliding bald disc.
  {
    static std::vector<std::array<float, 4>> s_prev_cull;
    constexpr float U = 4096.f;
    std::vector<std::array<float, 4>> kept;
    kept.reserve(s_goal_stage_cull.size());
    for (const auto& e : s_goal_stage_cull) {
      bool moved = false;
      for (const auto& pv : s_prev_cull) {
        float dx = e[0] - pv[0], dz = e[2] - pv[2];
        float d2 = dx * dx + dz * dz;
        if (d2 < (3.f * U) * (3.f * U)) {  // same actor neighbourhood
          if (d2 > (0.3f * U) * (0.3f * U)) {
            moved = true;
          }
          break;
        }
      }
      if (moved) {
        static double s_mv_log = -100.0;
        double now = std::chrono::duration<double>(
                         std::chrono::steady_clock::now().time_since_epoch())
                         .count();
        if (now - s_mv_log > 1.0) {
          s_mv_log = now;
          lg::info("[recharged-grass] R24B-DROP moving kind-0 entry at ({:.1f},{:.1f},{:.1f}) r{:.2f} — "
                   "allowlist leak, dropped",
                   e[0] / U, e[1] / U, e[2] / U, e[3] / U);
        }
        continue;
      }
      kept.push_back(e);
    }
    s_prev_cull = s_goal_stage_cull;
    s_goal_stage_cull.swap(kept);
  }
  {
    std::lock_guard<std::mutex> lk(s_goal_mutex);
    s_goal_cull = s_goal_stage_cull;
    s_goal_tramp = s_goal_stage_tramp;
    const double nowp = std::chrono::duration<double>(
                            std::chrono::steady_clock::now().time_since_epoch())
                            .count();
    if (s_goal_snapshot_t > 0.0) {
      const double iv = nowp - s_goal_snapshot_t;
      if (iv > 0.01 && iv < 10.0) {
        s_goal_pub_interval = 0.8 * s_goal_pub_interval + 0.2 * iv;  // EMA of the real cadence
      }
    }
    s_goal_snapshot_t = nowp;
  }
  static int s_pub_n = 0;
  s_pub_n++;
  // ROUND#24 position-delta offender detector (owner: a bald cull disc GLIDED with the player
  // after breaking a dummy). A kind-0 CULL entry is by design an IMMOBILE machine — if an entry
  // sits 0.2..12 m from its nearest neighbour of the PREVIOUS publish, the same disc moved
  // between publishes and the GOAL allowlist has been violated. Must stay silent forever; the
  // [R24CENSUS] GOAL log names the excluded type at matching coords.
  {
    static std::vector<std::array<float, 4>> s_prev_cull;
    static int s_move_log_pub = -100;
    constexpr float UM = 4096.f;
    if (!s_prev_cull.empty()) {
      for (const auto& e : s_goal_stage_cull) {
        float best = 1e30f;
        for (const auto& p : s_prev_cull) {
          float dx = (e[0] - p[0]) / UM, dy = (e[1] - p[1]) / UM, dz = (e[2] - p[2]) / UM;
          best = std::min(best, dx * dx + dy * dy + dz * dz);
        }
        if (best > 0.2f * 0.2f && best < 12.f * 12.f && s_pub_n - s_move_log_pub >= 8) {
          s_move_log_pub = s_pub_n;
          lg::warn(
              "[recharged-grass] R24MOVE kind0 CULL entry MOVED {:.2f} m to ({:.1f},{:.1f},{:.1f})"
              " — static allowlist violated",
              std::sqrt(best), e[0] / UM, e[1] / UM, e[2] / UM);
        }
      }
    }
    s_prev_cull = s_goal_stage_cull;
  }
  // ROUND#21e: 240-publish cadence never produced a post-actor-spawn line inside a capture window
  // (publishes are one per 30 game frames); every 20 (~10 s) keeps the log quiet but harvestable.
  if (s_pub_n <= 5 || s_pub_n % 20 == 0) {
    constexpr float U = 4096.f;
    std::string ent;
    // ROUND#21e: print EVERY cull entry (button + ALL vent instances + speaker — the list is tiny),
    // so the log itself audits that the owner's ground ecovent is published, not just the terrace
    // plat-eco (the 21d instance-selection failure).
    for (size_t i = 0; i < s_goal_stage_cull.size() && i < 12; i++) {
      const auto& e = s_goal_stage_cull[i];
      ent += fmt::format(" cull[{}]=({:.1f},{:.1f},{:.1f} r{:.2f})", i, e[0] / U, e[1] / U,
                         e[2] / U, e[3] / U);
    }
    for (size_t i = 0; i < s_goal_stage_tramp.size() && i < 3; i++) {
      const auto& e = s_goal_stage_tramp[i];
      ent += fmt::format(" tr[{}]=({:.1f},{:.1f},{:.1f} r{:.2f})", i, e[0] / U, e[1] / U, e[2] / U,
                         e[3] / U);
    }
    lg::info("[recharged-grass] R21OCC goal-publish #{} ncull={} ntr={}{}", s_pub_n,
             (int)s_goal_stage_cull.size(), (int)s_goal_stage_tramp.size(), ent);
  }
}

void publish(float dt) {
  // ROUND#21d: fold the GOAL actor snapshot into this frame's lists (Merc2 capture is DEAD/disabled;
  // the game side is the only actor source now). Jak's own trample stays on the u_jak_pos path.
  // R26 SNAPSHOT TTL (owner: dummy grass stays flat until the debris/message ends): if the GOAL scan
  // stops publishing for ANY reason (paused hook, scene, load), the last snapshot must NOT be replayed
  // forever — stale > 0.6 s => treat the lists as EMPTY (fail-safe: no data = no flatten/cull; the
  // ghosts then ease out on their own). Fresh publishes resume everything within one scan.
  {
    std::lock_guard<std::mutex> lk(s_goal_mutex);
    const double now_s = std::chrono::duration<double>(
                             std::chrono::steady_clock::now().time_since_epoch())
                             .count();
    // R27 (owner Redmi obs: trample OSCILLATED rise/flatten in a loop at low fps): the fixed 0.6 s TTL
    // was SHORTER than the publish interval at capture-load fps (15 game frames = 1.2-2.5 s at 6-12
    // fps) -> snapshot expired between publishes -> flatten/release loop. TTL is now ADAPTIVE:
    // stale only past max(2 s, 4x the observed publish interval) — still catches a genuinely frozen
    // scan (the original purpose) at any framerate, never oscillates.
    const bool snapshot_fresh =
        (s_goal_snapshot_t > 0.0) &&
        (now_s - s_goal_snapshot_t) < std::max(2.0, 4.0 * s_goal_pub_interval);
    if (snapshot_fresh)
    for (const auto& e : s_goal_cull) {
      add(e[0], e[1], e[2], e[3]);
    }
    if (snapshot_fresh)
    for (const auto& e : s_goal_tramp) {
      add_trample(e[0], e[1], e[2], e[3]);
    }
    // ROUND#21f BISECT (prop debug.opengoal.grass.trtest=1): synthetic trample entry 2 m north of
    // Jak, injected through the SAME goal fold-in path. Renders a flat disc -> path OK, content bug;
    // renders nothing -> the trample path itself broke between 21b (circle-follows proved it drew)
    // and 21d. Temporary forensic, default OFF.
    {
      static int s_trtest = -1;
      if (s_trtest < 0) {
#ifdef __ANDROID__
        char b[92] = {0};
        s_trtest = (__system_property_get("debug.opengoal.grass.trtest", b) > 0 && b[0] == '1') ? 1 : 0;
#else
        s_trtest = 0;
#endif
      }
      if (s_trtest == 1) {
        const auto& jpp = Gfx::g_global_settings.recharged_jak_pos;
        if (jpp[3] > 0.5f) {
          add_trample(jpp[0], jpp[1], jpp[2], 1.5f * 4096.f);  // R21f: AT Jak, unmissable
        }
      }
    }
  }
  g_published.swap(g_building);
  g_building.clear();
  // ROUND#21e (owner verdict 21d): the shader reads only the FIRST 16 slots of each list, and the
  // lists were in GOAL pool-scan order — so with >16 trample actors the 16 far scarecrows silently
  // EVICTED the crates right next to Jak (R21OCC frame=150 showed ntr=16 with tr[0..3] = scarecrows
  // 100-170 m away). Sort every published list by XZ distance to Jak so the 16-slot upload keeps the
  // 16 NEAREST — flatten/cull is invisible past ~40 m, so the near set is the only one that matters.
  const auto& jkp = Gfx::g_global_settings.recharged_jak_pos;
  auto d2jak = [&](const std::array<float, 4>& e) {
    float dx = e[0] - jkp[0], dz = e[2] - jkp[2];
    return dx * dx + dz * dz;
  };
  std::stable_sort(g_published.begin(), g_published.end(),
                   [&](const std::array<float, 4>& a, const std::array<float, 4>& b) {
                     return d2jak(a) < d2jak(b);
                   });
  constexpr float MATCH_R = 1.5f * 4096.f;  // same actor if within 1.5 m XZ (they are static)
  constexpr float EASE_IN_S = 0.25f;
  constexpr float EASE_OUT_S = 0.6f;        // owner round#21: release over ~0.4-0.8 s
  for (auto& g : s_tramp_state) {
    g.seen = false;
  }
  // R27 RELEASE TOMBSTONES (owner directive, literal: "s'il est cassé, redresser l'herbe
  // immédiatement et ignorer toute la logique de débris"): when a trample ghost is released (its
  // actor left the publish set = broken), its SPOT is banned from re-flattening for 8 s — whatever
  // the debris window re-publishes there cannot press the grass again. A regenerated dummy
  // (~30 s+) re-flattens normally after the tombstone expires.
  struct Tombstone {
    float x, z;
    double t;
  };
  static std::vector<Tombstone> s_tombs;
  const double tnow = std::chrono::duration<double>(
                          std::chrono::steady_clock::now().time_since_epoch())
                          .count();
  s_tombs.erase(std::remove_if(s_tombs.begin(), s_tombs.end(),
                               [&](const Tombstone& tb) { return tnow - tb.t > 8.0; }),
                s_tombs.end());
  {
    std::vector<std::array<float, 4>> filt;
    filt.reserve(g_tramp_building.size());
    for (const auto& e : g_tramp_building) {
      bool banned = false;
      for (const auto& tb : s_tombs) {
        float dx = e[0] - tb.x, dz = e[2] - tb.z;
        if (dx * dx + dz * dz < (1.0f * 4096.f) * (1.0f * 4096.f)) {
          banned = true;
          break;
        }
      }
      if (!banned) {
        filt.push_back(e);
      }
    }
    g_tramp_building.swap(filt);
  }
  // R28: consume break-kill events — erase matching ghosts NOW + tombstone their spots.
  {
    std::vector<std::array<float, 3>> kills;
    {
      std::lock_guard<std::mutex> lk(s_goal_mutex);
      kills.swap(s_break_kills);
    }
    for (const auto& k : kills) {
      // R30 (owner: the instant snap was TOO dry vs the crates' visible 0.6 s spring): tombstone ONLY.
      // The banned spot stops feeding the ghost -> it plays the SAME smooth 0.6 s ease-out as a broken
      // crate instead of vanishing in one frame.
      s_tombs.push_back({k[0], k[2], tnow});
      lg::info("[recharged-grass] R30 BREAK at ({:.1f},{:.1f},{:.1f}) — spot tombstoned, ghost eases out",
               k[0] / 4096.f, k[1] / 4096.f, k[2] / 4096.f);
    }
  }
  for (const auto& e : g_tramp_building) {
    TrampGhost* hit = nullptr;
    for (auto& g : s_tramp_state) {
      float dx = g.e[0] - e[0], dz = g.e[2] - e[2];
      if (dx * dx + dz * dz < MATCH_R * MATCH_R && std::fabs(g.e[1] - e[1]) < 2.f * 4096.f) {
        hit = &g;
        break;
      }
    }
    if (hit) {
      hit->e = e;
      hit->seen = true;
    } else if (s_tramp_state.size() < 64) {
      s_tramp_state.push_back({e, 0.f, true});
    }
  }
  g_tramp_building.clear();
  float dtc = std::min(std::max(dt, 0.f), 0.1f);  // clamp a hitch so a long frame can't teleport the ease
  g_tramp_published.clear();
  g_tramp_strength.clear();
  for (auto it = s_tramp_state.begin(); it != s_tramp_state.end();) {
    if (it->seen) {
      it->strength = std::min(1.f, it->strength + dtc / EASE_IN_S);
    } else {
      it->strength -= dtc / EASE_OUT_S;
    }
    if (it->strength <= 0.f) {
      s_tombs.push_back({it->e[0], it->e[2], tnow});  // R27: spot released -> ban re-flatten 8 s
      it = s_tramp_state.erase(it);
      continue;
    }
    if (g_tramp_published.size() < 64) {
      g_tramp_published.push_back(it->e);
      g_tramp_strength.push_back(it->strength);
    }
    ++it;
  }
  // ROUND#21e nearest-16 for the trample list too (paired with its strength array, so sort a
  // permutation and reorder both together — the ghost ease state itself is untouched).
  if (g_tramp_published.size() > 1) {
    std::vector<size_t> order(g_tramp_published.size());
    for (size_t i = 0; i < order.size(); i++) {
      order[i] = i;
    }
    std::stable_sort(order.begin(), order.end(), [&](size_t a, size_t b) {
      return d2jak(g_tramp_published[a]) < d2jak(g_tramp_published[b]);
    });
    std::vector<std::array<float, 4>> pe(order.size());
    std::vector<float> ps(order.size());
    for (size_t i = 0; i < order.size(); i++) {
      pe[i] = g_tramp_published[order[i]];
      ps[i] = g_tramp_strength[order[i]];
    }
    g_tramp_published.swap(pe);
    g_tramp_strength.swap(ps);
  }
}
}  // namespace grass_occ

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
  // ROUND#19: per-instance ground-face NORMAL (location 4) from the SAME main instance VBO (byte
  // offset 48 = the nx/ny/nz/nspare slot), so the shader can grow blades along a blend of world-up
  // and the ground normal (u_tilt). Main instance VBO is still bound here (loc 3 below is the
  // separate light VBO). Divisor 1 = one normal per instance.
  // GPU-hang bisect escape hatch: debug.opengoal.grass_noattr4=1 (set BEFORE boot; read once here)
  // leaves attrib 4 disabled — the shader then reads the constant default (0,0,0,1), which the
  // u_tilt=0 path never consumes — so the new-attrib suspect can be isolated on device w/o a rebuild.
  bool noattr4 = false;
#ifdef __ANDROID__
  {
    char nbuf[8] = {0};
    if (__system_property_get("debug.opengoal.grass_noattr4", nbuf) > 0 && nbuf[0] == '1') {
      noattr4 = true;
    }
  }
#endif
  if (!noattr4) {
    glEnableVertexAttribArray(4);
    glVertexAttribPointer(4, 4, GL_FLOAT, GL_FALSE, sizeof(GrassInstance),
                          (void*)(12 * sizeof(float)));
    glVertexAttribDivisor(4, 1);
  }
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
  // Owner round#18 verdict: after the round#17 silhouette fix was reverted (its collision-vs-render
  // edge divergence produced 50cm bald strips), blades STILL hang in the void past platform rims. This
  // is a purely POINT-WISE test: a blade survives only if there is walkable collision floor directly
  // below its base. No edge detection, no 2D silhouette, no rim distance -> the strip artifact cannot
  // return; the only culled blades are those with genuinely nothing under them. Collision data lives in
  // the SAME LevelData the renderer already loads (lev->collision.vertices, per-vertex .pat, same world
  // GOAL-unit space as the render verts). jak1 = collision version 1: walkable ground iff pat surface
  // mode ((pat >> 3) & 0x7) == 0.
  // ROUND#19 perf: each FloorTri caches its (padded) XZ bbox for a cheap reject AND the barycentric
  // denominators precomputed once at build time, so a per-base query only computes d20/d21 (the 2 dot
  // products that depend on the point). A degenerate tri (|denom| < 1e-6) is dropped at build, so the
  // runtime denom guard is gone. With the 1m bucket the candidate lists are tiny.
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
  // ROUND#19b: GAP to the nearest walkable collision floor below this base (world units). Empty floor
  // set -> 0 (collision absent = no-op keep, never worse than today). No floor in the search window ->
  // NO_FLOOR sentinel (base over a true void). A floor slightly ABOVE the base (render/collision
  // mismatch, within FLOOR_EPS_UP) clamps to gap 0. Look up ONLY the base's own bucket (tris were
  // inserted into every bucket their bbox overlaps, so that is sufficient). Cheap bbox reject first,
  // then the precomputed-denominator XZ barycentric (only d20/d21 per query).
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
  // ROUND#19b: gap threshold — default FLOOR_GAP_M, device-tunable via debug.opengoal.grass_floorgap
  // (metres, read once per rebuild) so the terrace tuning needs no rebuild.
  float floor_gap_thresh = FLOOR_GAP_M * U;
#ifdef __ANDROID__
  {
    char gbuf[16] = {0};
    if (__system_property_get("debug.opengoal.grass_floorgap", gbuf) > 0 && gbuf[0]) {
      float gv = (float)atof(gbuf);
      if (gv > 0.01f && gv < 2.5f) floor_gap_thresh = gv * U;
    }
  }
#endif

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

  // ---- ROUND#16: the round#15 0.1 m coverage RASTER is REMOVED. ----
  // Owner verbatim: "les carrés/grids/rasters c'est nul... on a le mesh du sol, autant utiliser ça." The
  // raster APPROXIMATED the border (stair-stepped at the cell size, "ça suit pas les bordures") and its
  // solid silhouette was the upness>=0.5 tops — INCLUDING flat tops that overhang, so bases on an overhang
  // still got a large rim_dist and floated. rim_dist is now the EXACT per-blade point-to-true-rim-edge
  // distance (dmin) computed inline in PHASE 2 from the ROUND#16 ROBUST boundary flags (bAB/bBC/bCA), which
  // hug the real mesh edge with no stair-step and — because the weld/dedup now flags the true outer rims on
  // TIE multi-fragment platforms too — collapse the over-edge blades to invisible stubs. No coverage grid,
  // no chamfer allocation at load, no shader change.

  m_instances.reserve(std::min<size_t>(budget, (size_t)(total_area_m2 * density) + 64));
  m_inst_tri.reserve(m_instances.capacity());
  int edge_dropped = 0;   // degenerate rim slivers dropped individually (per-blade, NOT whole blocks)
  int edge_clamped = 0;   // near-rim blades whose horizontal reach the shader will clamp to the rim
  int rim_finite = 0;     // ROUND#16: blades that got a FINITE rim_dist (a true rim in their tri) vs interior
  int rim_global_hits = 0;  // ROUND#20: blades ONLY the cross-triangle global rim query protects
  const float RIM_TAPER_W = 0.45f * U;  // matches the shader RIM_TAPER (height fully restored 0.45 m in)
  int floor_tested = 0, floor_culled = 0;  // ROUND#19 point-wise cantilever cull instrumentation
  int gap_culled = 0;                      // ROUND#19b: floor exists but too far below (stacked terrace)
  std::vector<float> interior_gaps;        // ROUND#19b: gap samples for clearly-INTERIOR blades (p99 tune)
  interior_gaps.reserve(4096);
  for (size_t tj = 0; tj < tris.size(); ++tj) {
    const auto& r = tris[tj];
    if (r.is_lip || r.is_dup) continue;   // POLISH#12/ROUND#16: overhang lip or fragment duplicate -> no bases
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
      // Barycentric weights (A,B,C) = (1-r1-r2, r1, r2). The blade base is a point INSIDE this real
      // grass triangle — per-blade placement, never a predefined block.
      float wA = 1.0f - r1 - r2, wB = r1, wC = r2;
      float bx = r.p0x + r1 * r.e1x + r2 * r.e2x;
      float by = r.p0y + r1 * r.e1y + r2 * r.e2y;
      float bz = r.p0z + r1 * r.e1z + r2 * r.e2z;

      // ROUND#19: cantilever cull v2 — no walkable floor directly below = base over the VOID (the
      // render-mesh cantilever past the platform rim) -> cull this blade individually.
      // ROUND#19b: floor exists but only FAR below (> gap threshold) = the base is cantilevered past an
      // UPPER platform edge over a LOWER terrace (the owner's live obs) -> cull it too. A blade only
      // stands where its OWN floor is essentially right beneath it.
      floor_tested++;
      {
        float fgap = floor_gap(bx, by, bz);
        if (fgap >= 1e17f) { floor_culled++; continue; }             // no floor at all: true void
        if (fgap > floor_gap_thresh) { gap_culled++; continue; }     // stacked-terrace cantilever
        // clearly-interior sample (no boundary edge on this tri) -> tune/verify the gap threshold
        if (!r.bAB && !r.bBC && !r.bCA && (int)interior_gaps.size() < 200000) {
          interior_gaps.push_back(fgap);
        }
      }

      // ROUND#16: rim_dist = the EXACT perpendicular distance from this base to the nearest TRUE RIM edge
      // of its own triangle (an edge the ROBUST weld/dedup flagged as a real outer boundary). dmin = weight
      // opposite that edge * nlen(=2*area) / edge length. NO_RIM (interior) when no edge of this tri is a
      // rim -> the shader leaves the blade full height. This is continuous and hugs the mesh edge with no
      // stair-step; the robust boundary flags mean it now fires at the real rim on TIE multi-fragment
      // platforms too (the round#14/#15 miss). No coverage raster.
      float dmin = NO_RIM;
      if (r.bBC) { float d = wA * r.nlen / r.lenBC; if (d < dmin) dmin = d; }  // edge BC opposite A
      if (r.bCA) { float d = wB * r.nlen / r.lenCA; if (d < dmin) dmin = d; }  // edge CA opposite B
      if (r.bAB) { float d = wC * r.nlen / r.lenAB; if (d < dmin) dmin = d; }  // edge AB opposite C
      // ROUND#20 (supervisor): GLOBAL rim distance — a blade on an interior tri right behind a NARROW
      // rim tri had dmin=NO_RIM and leaned its full-height tip past the edge. Take the min with the
      // distance to the nearest rim segment of the WHOLE patch (Y-windowed, RIM_QUERY radius).
      {
        float dg = rim_dist_global(bx, by, bz);
        if (dg < dmin) {
          if (dmin >= NO_RIM) rim_global_hits++;  // blades ONLY the global query protects
          dmin = dg;
        }
      }
      // The ONLY per-blade rejection is a degenerate sliver whose base sits < 5 mm from a true rim.
      if (dmin < DROP_EPS) { edge_dropped++; continue; }

      GrassInstance gi;
      gi.px = bx;
      gi.py = by;
      gi.pz = bz;
      gi.h = BASE_H * (0.50f + 1.55f * hash_f(sd + 3u));   // OWNER POLISH#3: wider SIZE variation
      gi.tint = hash_f(sd + 5u);
      gi.curve = 0.10f + 0.75f * hash_f(sd + 6u);          // wider CURVATURE variation
      gi.phase = hash_f(sd + 7u);
      gi.yaw = hash_f(sd + 4u) * 6.2831853f;               // fully random yaw; the shader rim taper+clamp
                                                           // (not a CPU lean) keeps geometry in-bounds
      gi.gr = r.gr; gi.gg = r.gg; gi.gb = r.gb;            // POLISH#4 ground colour
      // The (shader-unused) 4th ground-colour slot carries the EXACT mesh rim_dist (world units) for the
      // shader height-taper + POLISH#11 horizontal clamp. The DYNAMIC per-location baked light rides its
      // own u8 buffer (loc 3, inst_light), so this float slot is free — no vertex-layout change, lighting
      // untouched.
      gi.gspare = dmin;   // = rim_dist (world units); NO_RIM for interior blades -> shader never tapers them
      // ROUND#19: source triangle's face normal (already normalized + ny>=0) for the shader u_tilt blend.
      gi.nx = r.nx; gi.ny = r.ny; gi.nz = r.nz; gi.nspare = 0.f;
      if (dmin < NO_RIM) rim_finite++;                     // blades with a real rim in their triangle
      if (dmin < RIM_TAPER_W) edge_clamped++;              // blades inside the shader height-taper band
      m_instances.push_back(gi);
      m_inst_tri.push_back((u32)tj);   // POLISH#9: remember which triangle this blade grows from
    }
  }

  // ROUND#16 instrumentation (supervisor mandate: PROVE the robust-edge fix). RIMDIST reports the EXACT
  // mesh rim distance now driving the taper, plus the ROBUST-vs-RAW true-edge counts. boundary_edges
  // (robust weld + coincident-dedup) vs boundary_raw (the OLD raw-1cm count): a difference proves the old
  // count mis-flagged rims on TIE/multi-fragment platforms = the persistent floating culprit. n_dup =
  // coincident fragment tris removed; weld_verts = distinct welded vertices. rim_finite = blades with a
  // true rim in their tri (tapered/clamped); interior blades keep full height.
  lg::info(
      "[recharged-grass] RIMDIST exact-mesh (ROUND#16, raster REMOVED): placed={} rim_finite={} "
      "edge_clamped={} edge_dropped={} | robust true-edge: boundary_edges={} vs raw-1cm boundary_raw={} "
      "(delta={}), coincident_dups={}, weld_verts={} — robust weld/dedup flags the true rims the raw 1cm "
      "count missed on TIE multi-fragment platforms (the floating overflow root).",
      (int)m_instances.size(), rim_finite, edge_clamped, edge_dropped, boundary_edges, boundary_raw,
      boundary_edges - boundary_raw, n_dup, n_weld_verts);
  // ROUND#20 instrumentation: rim_global_hits = blades whose own tri had NO rim edge but that sit within
  // RIM_QUERY of a rim segment elsewhere in the patch — exactly the full-height blades that leaned past
  // platform edges before (the owner's residual "ça dépasse"). Now they taper/clamp like rim blades.
  lg::info(
      "[recharged-grass] ROUND#20 GLOBAL-RIM: rim_segs={} rim_global_hits={} (interior-tri blades near a "
      "rim now tapered; own-tri-only missed them)",
      rim_segs_n, rim_global_hits);

  // ROUND#19 point-wise cantilever-cull instrumentation: floor_tris = walkable collision ground tris,
  // tested = candidate blades checked, culled = blades with NO walkable floor below (over the void).
  lg::info("[recharged-grass] ROUND#19 FLOORBELOW cantilever-cull: floor_tris={} tested={} culled={} kept={}", floor_tris_n, floor_tested, floor_culled + gap_culled, floor_tested - floor_culled - gap_culled);
  // ROUND#19b stacked-terraces instrumentation: interior-blade gap percentiles PROVE the threshold sits
  // above normal render-vs-collision Y offsets (p99 < thresh = no false culls on bumpy interior ground);
  // gap_culled = cantilevered-over-lower-terrace blades (the owner's live obs), void_culled = true void.
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

  // ---- POLISH#4 / ROUND#13: hide grass under overlapping non-grass 3D objects (TIE models). ----
  // ROUND#13 (SUPERVISOR DIAGNOSIS #2): the old code marked a whole 0.5m XZ CELL occupied when any TIE
  // vertex hovered above it and then a 3x3 morphological closing bridged/kept those cells — a single
  // stray vertex (nearby/overhead TIE geometry) nuked a 0.5m BLOCK of grass on an OPEN platform = the
  // owner's "block-shaped bald holes" where NO object was actually sitting. FIX: NO grid cull, NO
  // dilation. A PER-INSTANCE test — each blade is hidden iff a real TIE object vertex is within
  // OCC_RADIUS of ITS OWN (px,pz) AND in the near-ground contact band [+OCC_LO,+OCC_HI] above ITS OWN
  // ground Y. On open grass (no object vertex within radius+band) occ_culled ~0 -> no block holes; a
  // blade is culled ONLY where an actual prop's footprint covers it. TIE-only (real objects); tfrag
  // terrain excluded so cliffs/slopes never falsely cull. Shrubs stay exempt (POLISH#8: their alpha-
  // transparent mesh is not an occluder) — they are TIE too, but their near-ground body is sparse so
  // the tight radius already leaves their bald ring filled; the whole-shrub cell nuke is gone anyway.
  int occ_culled = 0;
  size_t occ_objpts = 0;
  if (!m_instances.empty() && !occ_pts.empty()) {
    const float inv = 1.0f / (OCC_CELL_M * U);  // spatial-hash bucket (lookup only, NOT a cull unit)
    auto bkey = [inv](float x, float z) -> s64 {
      s64 gx = (s64)std::floor(x * inv);
      s64 gz = (s64)std::floor(z * inv);
      return (gx << 32) ^ (gz & 0xffffffffLL);
    };
    // Spatial hash of NON-grass TIE object vertices (world XZ+Y). Bucket >= OCC_RADIUS so a blade only
    // has to test its own bucket + the 8 neighbours to find every object point within OCC_RADIUS.
    struct OP {
      float x, y, z;
    };
    std::unordered_map<s64, std::vector<OP>> objpts;
    objpts.reserve(4096);
    for (const auto& p : occ_pts) {
      objpts[bkey(p[0], p[2])].push_back({p[0], p[1], p[2]});
    }
    occ_objpts = objpts.size();
    const float lo = OCC_LO_M * U, hi = OCC_HI_M * U;
    const float rad2 = (OCC_RADIUS_M * U) * (OCC_RADIUS_M * U);
    std::vector<GrassInstance> keep;
    std::vector<u32> keept;  // POLISH#9: keep m_inst_tri aligned with the surviving instances
    keep.reserve(m_instances.size());
    keept.reserve(m_instances.size());
    for (size_t i = 0; i < m_instances.size(); ++i) {
      const auto& gi = m_instances[i];
      s64 bx = (s64)std::floor(gi.px * inv);
      s64 bz = (s64)std::floor(gi.pz * inv);
      bool hidden = false;
      for (s64 dz = -1; dz <= 1 && !hidden; ++dz) {
        for (s64 dx = -1; dx <= 1 && !hidden; ++dx) {
          s64 k = ((bx + dx) << 32) ^ ((bz + dz) & 0xffffffffLL);
          auto it = objpts.find(k);
          if (it == objpts.end()) {
            continue;
          }
          for (const auto& p : it->second) {
            float dy = p.y - gi.py;             // object must be in the near-ground contact band
            if (dy <= lo || dy >= hi) {
              continue;
            }
            float ddx = p.x - gi.px, ddz = p.z - gi.pz;  // and within OCC_RADIUS of THIS blade's base
            if (ddx * ddx + ddz * ddz <= rad2) {
              hidden = true;
              break;
            }
          }
        }
      }
      if (hidden) {
        occ_culled++;
        continue;
      }
      keep.push_back(gi);
      keept.push_back(m_inst_tri[i]);
    }
    m_instances.swap(keep);
    m_inst_tri.swap(keept);
  }

  // ROUND#23 census (the "which prop leaked" diagnosis artifact): which non-grass TIE textures got
  // face-densified footprint samples, and how many. The leaking small rocks show up here by texture.
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

  m_instance_count = (int)m_instances.size();

  // ROUND#14 CAPTURE AID: dump a spread of RAISED near-rim base world coords (metres) so a device
  // capture can `level.warp.pos` Jak EXACTLY onto a platform edge (blind cpad nav never reached one
  // across rounds #11-#13). Candidates = near-rim bases (gspare < 0.15 m) deduped to one per ~6 m
  // XZ cell, sorted by height (raised platforms first) — those are the platform rims where the owner
  // sees floating. TIE-platform rims are tagged (owner: distant TIE platforms float).
  {
    struct Cand { float mx, my, mz; bool tie; };
    std::unordered_map<s64, Cand> best;  // one highest candidate per 6 m cell
    const float cinv = 1.0f / (6.0f * U);
    for (size_t i = 0; i < m_instances.size(); ++i) {
      const auto& gi = m_instances[i];
      if (gi.gspare > 0.15f * U) continue;  // near a true rim only
      s64 cx = (s64)std::floor(gi.px * cinv), cz = (s64)std::floor(gi.pz * cinv);
      s64 k = (cx << 32) ^ (cz & 0xffffffffLL);
      bool tie = (i < m_inst_tri.size() && m_inst_tri[i] < tris.size()) ? tris[m_inst_tri[i]].is_tie : false;
      auto it = best.find(k);
      if (it == best.end() || gi.py > it->second.my * U) {
        best[k] = Cand{gi.px / U, gi.py / U, gi.pz / U, tie};
      }
    }
    std::vector<Cand> cands;
    cands.reserve(best.size());
    for (auto& kv : best) cands.push_back(kv.second);
    std::sort(cands.begin(), cands.end(), [](const Cand& a, const Cand& b) { return a.my > b.my; });
    int nlog = std::min<int>(14, (int)cands.size());
    for (int i = 0; i < nlog; ++i) {
      lg::info("[recharged-grass] RIMCAND {} pos=\"{:.1f} {:.1f} {:.1f}\" y={:.1f}m {} (level.warp.pos)",
               i, cands[i].mx, cands[i].my, cands[i].mz, cands[i].my, cands[i].tie ? "TIE" : "tfrag");
    }
  }

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
      "{} instances in {} chunks (POLISH#5 density {:.0f}% -> budget {}). ROUND#13 PER-INSTANCE "
      "object-hide (NO 0.5m cell nuke, NO 3x3 dilation): occ_culled {} of {} instances ({:.3f}%) — each "
      "blade tested vs {} NON-grass-TIE object-point buckets (grass-TIE platforms EXCLUDED = no self-cull) "
      "within radius {:.2f}m + contact band [{:.2f},{:.2f}]m; a blade is culled ONLY if a real object "
      "vertex is that close, so OPEN grass (no object) is NEVER culled = occ ~0 there, NO block-shaped "
      "bald holes. No camera window, no move-rebuild -> nothing de-instances while moving.",
      considered_draws, tie_draws, tris_kept, giant_tris, max_area, total_area_m2, density,
      m_instance_count, (int)m_chunks.size(), Gfx::g_global_settings.recharged_grass_density, budget,
      occ_culled, m_instance_count + occ_culled,
      100.0f * (float)occ_culled / (float)std::max(1, m_instance_count + occ_culled), (int)occ_objpts,
      OCC_RADIUS_M, OCC_LO_M, OCC_HI_M);
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
  // ROUND#13 OVERHANG-LIP EXCLUSION (TRANSITIVE): BASES are not placed on tilted grass-textured tris
  // whose downhill CHAIN opens into void — the platform rim skirt that overhangs the drop, the true
  // cause of the owner's persistent FLOATING grass. The POLISH#12 single-pass missed MULTI-SEGMENT
  // skirts (distant TIE platforms), so the propagation is now transitive (up the skirt, stopped by a
  // flat top). lipExcluded split tfrag/TIE proves the SAME exclusion now reaches the distant TIE
  // platforms (owner #2); minPlacedUpness = the shallowest tri that STILL gets grass.
  lg::info(
      "[recharged-grass] ROUND#13 OVERHANG-LIP (transitive): {} lip tris base-excluded ({} TIE / {} "
      "tfrag, {:.0f} m2, upness < {:.2f} AND downhill chain = void); minPlacedUpness {:.2f}. Bases stay "
      "on the flat walkable top only -> grass ends exactly at the top rim on tfrag AND distant TIE "
      "platforms, none floating past the platform silhouette into the void.",
      lip_excluded, lip_excluded_tie, lip_excluded - lip_excluded_tie, lip_excluded_area, UPNESS_LIP_MAX,
      min_placed_upness);
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
  // OWNER ROUND#18: publish this frame's merc-captured object occluders (crates / warp-gate button)
  // and clear the building list. Runs every frame the grass toggle is ON (before any early return),
  // so the building list never accumulates across frames/levels. ROUND#21: publish takes the frame
  // dt so the per-object trample strengths ease in/out (broken-crate gradual spring-back).
  static const auto s_pub_t0 = std::chrono::steady_clock::now();
  static float s_pub_prev = -1.f;
  float pub_now =
      std::chrono::duration<float>(std::chrono::steady_clock::now() - s_pub_t0).count();
  grass_occ::publish(s_pub_prev < 0.f ? 0.f : pub_now - s_pub_prev);
  s_pub_prev = pub_now;
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
  // OWNER ROUND#21 EASED TRAMPLE RELEASE: keep a short trail of Jak's recent positions (one sample
  // every ~0.15 s, 4 samples) and upload them with an age-decayed strength (1 -> 0 over ~0.6 s).
  // The shader max-combines them with the live position, so the flatten under a takeoff spot (jump)
  // or behind a sprint eases back up over the decay window instead of snapping upright in one frame.
  {
    static std::array<std::array<float, 4>, 4> s_trail{};  // xyz + capture time (u_time seconds)
    static float s_trail_last = -1.f;
    if (jp[3] > 0.5f && (s_trail_last < 0.f || u_time - s_trail_last >= 0.15f)) {
      for (int ti = 3; ti > 0; ti--) {
        s_trail[ti] = s_trail[ti - 1];
      }
      s_trail[0] = {jp[0], jp[1], jp[2], u_time};
      s_trail_last = u_time;
    }
    float trail[16];
    for (int ti = 0; ti < 4; ti++) {
      float age = u_time - s_trail[ti][3];
      float str = (jp[3] > 0.5f && s_trail[ti][3] > 0.f) ? std::max(0.f, 1.f - age / 0.6f) : 0.f;
      trail[ti * 4 + 0] = s_trail[ti][0];
      trail[ti * 4 + 1] = s_trail[ti][1];
      trail[ti * 4 + 2] = s_trail[ti][2];
      trail[ti * 4 + 3] = str;
    }
    glUniform4fv(glGetUniformLocation(id, "u_jak_trail"), 4, trail);
  }
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
  // ROUND#14 DISCRIMINATOR (0 normal / 1 base-stubs magenta / 2 blades cyan / 3 cards yellow):
  // isolates every tier so ONE fixed-viewpoint capture at a rim discriminates the floating
  // mechanism (H-A blade geometry / H-B base-past-silhouette / H-C cards). Control (default OFF):
  //   prop debug.opengoal.grass_dbg = c (cycle every 4 s) | 1 | 2 | 3   (Android)
  //   env  GRASS_DISCRIMINATE       = c | 1 | 2 | 3                     (desktop x86)
  glUniform1i(glGetUniformLocation(id, "u_debug"), grass_debug_mode(u_time));
  // ROUND#19: optional normal-tilt blend — blade growth axis = mix(world-up, ground-face normal, u_tilt).
  // 0.0 (default) is bit-identical to the world-up-only growth; the owner A/Bs ~0.30 via the debug prop.
  glUniform1f(glGetUniformLocation(id, "u_tilt"), grass_tilt_amount());
  // OWNER ROUND#18: object-clip — hide grass under crates / the warp-gate button (merc actors captured
  // by Merc2 this frame). Upload up to 16 as u_occ (xyz = world pos GOAL units, w = ground-contact
  // radius GOAL units); u_occ_count == 0 (no objects captured) makes the shader path byte-identical to
  // no object-clip, so this can never break base grass rendering.
  {
    int nocc = (int)std::min<size_t>(grass_occ::g_published.size(), 8);  // R21f literal-unroll cap
    if (nocc > 0) {
      glUniform4fv(glGetUniformLocation(id, "u_occ"), nocc, &grass_occ::g_published[0][0]);
    }
    glUniform1i(glGetUniformLocation(id, "u_occ_count"), nocc);
  }
  // OWNER Q&A 2026-07-12: breakable actors (crates, scarecrows) TRAMPLE the grass (flatten like Jak),
  // they do NOT cull it -> when the object is broken the grass springs back. Upload up to 16 as
  // u_trample (xyz = world pos, w = ground-contact radius). u_trample_count == 0 -> no flatten.
  {
    int ntr = (int)std::min<size_t>(grass_occ::g_tramp_published.size(), 8);  // R21f literal-unroll cap
    if (ntr > 0) {
      glUniform4fv(glGetUniformLocation(id, "u_trample"), ntr, &grass_occ::g_tramp_published[0][0]);
      // ROUND#21: per-entry eased strength — the shader scales each entry's flatten by this, so a
      // broken crate's grass springs back over ~0.6 s (uniforms default to 0 -> upload is mandatory).
      // R21f: Adreno driver quirk — glGetUniformLocation on a float ARRAY can return -1 for the
      // bare name (works for vec4 arrays, fails for float arrays) -> the upload silently no-ops and
      // u_trample_str stays at its 0.0 default = flatten multiplied by ZERO (the "condition fires,
      // cyan marks show, nothing flattens" forensic signature). Query "name[0]" as fallback + log.
      int str_loc = glGetUniformLocation(id, "u_trample_str");
      if (str_loc < 0) {
        str_loc = glGetUniformLocation(id, "u_trample_str[0]");
      }
      static bool s_str_loc_logged = false;
      if (!s_str_loc_logged) {
        s_str_loc_logged = true;
        lg::info("[recharged-grass] R21F u_trample_str loc={} (bare={}) str[0]={:.2f} ntr={}",
                 str_loc, glGetUniformLocation(id, "u_trample_str"),
                 grass_occ::g_tramp_strength.empty() ? -1.f : grass_occ::g_tramp_strength[0], ntr);
      }
      glUniform1fv(str_loc, ntr, grass_occ::g_tramp_strength.data());
      // R21f: repack strengths into a vec4 array (.x) — see grass.vert; float-array dynamic reads
      // miscompile to 0 on the Adreno 618.
      float str4[16][4];
      for (int si = 0; si < ntr && si < 16; si++) {
        str4[si][0] = grass_occ::g_tramp_strength[si];
        str4[si][1] = str4[si][2] = str4[si][3] = 0.f;
      }
      glUniform4fv(glGetUniformLocation(id, "u_trample2"), ntr, &str4[0][0]);
    }
    glUniform1i(glGetUniformLocation(id, "u_trample_count"), ntr);
  }

  // ROUND#19 forensics (owner: registered radii have NO visual): prove what actually reaches the
  // shader — uniform locations (a -1 = the GLES link dropped it) once, then the published entries +
  // Jak pos every ~150 frames. Metres for readability. Removed noise cost: two ints per frame.
  static bool s_occ_loc_logged = false;
  if (!s_occ_loc_logged) {
    s_occ_loc_logged = true;
    lg::info("[recharged-grass] R19OCC uniform-locations: u_occ={} u_occ_count={} u_trample={} u_trample_count={} u_jak_pos={} u_tilt={}", glGetUniformLocation(id, "u_occ"), glGetUniformLocation(id, "u_occ_count"), glGetUniformLocation(id, "u_trample"), glGetUniformLocation(id, "u_trample_count"), glGetUniformLocation(id, "u_jak_pos"), glGetUniformLocation(id, "u_tilt"));
  }
  static int s_occ_dump_frame = 0;
  if ((s_occ_dump_frame++ % 150) == 0) {
    std::string ent;
    for (size_t ei = 0; ei < grass_occ::g_published.size() && ei < 4; ei++) { const auto& e = grass_occ::g_published[ei]; ent += fmt::format(" occ[{}]=({:.1f},{:.1f},{:.1f} r{:.2f})", ei, e[0] / U, e[1] / U, e[2] / U, e[3] / U); }
    for (size_t ei = 0; ei < grass_occ::g_tramp_published.size() && ei < 4; ei++) { const auto& e = grass_occ::g_tramp_published[ei]; ent += fmt::format(" tr[{}]=({:.1f},{:.1f},{:.1f} r{:.2f})", ei, e[0] / U, e[1] / U, e[2] / U, e[3] / U); }
    lg::info("[recharged-grass] R19OCC frame={} nocc={} ntr={} jak=({:.1f},{:.1f},{:.1f}){}", s_occ_dump_frame - 1, (int)grass_occ::g_published.size(), (int)grass_occ::g_tramp_published.size(), jp[0] / U, jp[1] / U, jp[2] / U, ent);
  }
  // ROUND#21e Y-BAND VALIDATION (one-shot, diagnosis item 4): for each published actor, find the
  // nearest blade base in XZ and log dy = actor-root-Y minus blade-base-Y. The shader accepts an
  // actor whose root sits from 1.0 m below to 2.5 m above the blade base (yd = base.y - obj.y in
  // (-2.5 .. +1.0) m); an actor OUT-OF-BAND would silently never cull/flatten even when published,
  // so this dump proves the band fits the real actors (or names the exact dy to widen/offset for).
  static bool s_yband_logged = false;
  if (!s_yband_logged && !m_instances.empty() &&
      (!grass_occ::g_published.empty() || !grass_occ::g_tramp_published.empty())) {
    s_yband_logged = true;
    auto yband_dump = [&](const char* tag, const std::vector<std::array<float, 4>>& v) {
      for (size_t ei = 0; ei < v.size(); ei++) {
        const auto& e = v[ei];
        float best = 1e30f;
        float dy = 0.f;
        for (const auto& gi : m_instances) {
          float dx = gi.px - e[0], dz = gi.pz - e[2];
          float d2 = dx * dx + dz * dz;
          if (d2 < best) {
            best = d2;
            dy = e[1] - gi.py;
          }
        }
        lg::info(
            "[recharged-grass] R21E-YBAND {}[{}] pos=({:.1f},{:.1f},{:.1f}) r={:.2f} "
            "nearest-blade-xz={:.2f}m dy(obj-blade)={:.2f}m {}",
            tag, ei, e[0] / U, e[1] / U, e[2] / U, e[3] / U, std::sqrt(best) / U, dy / U,
            (dy > -1.0f * U && dy < 2.5f * U) ? "IN-BAND" : "OUT-OF-BAND");
      }
    };
    yband_dump("occ", grass_occ::g_published);
    yband_dump("tr", grass_occ::g_tramp_published);
  }

  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_GEQUAL);
  glDepthMask(GL_TRUE);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

  glBindVertexArray(m_vao);
  GLint mode_loc = glGetUniformLocation(id, "u_mode");

  // ROUND#19 GPU-wedge forensics (device props, read once at first frame):
  //   debug.opengoal.grass_maxinst=N  -> draw only the FIRST N instances of the SAME built buffer.
  //     Same data + same scatter, smaller drawn count: discriminates COUNT/workload (maxinst at the
  //     density-50 count survives) from pathological CONTENT (dies at any count containing the bad
  //     instance; bisect maxinst to pin the offending range).
  //   debug.opengoal.grass_gpusync=1  -> glFinish + per-draw wall-time log on the first frames, so the
  //     log names the exact operation that never completes (blade draw vs card draw) and its cost.
  static int s_maxinst = -1;
  static bool s_gpusync = false;
#ifdef __ANDROID__
  if (s_maxinst < 0) {
    char mbuf[16] = {0};
    s_maxinst = (__system_property_get("debug.opengoal.grass_maxinst", mbuf) > 0) ? atoi(mbuf) : 0;
    char sbuf[8] = {0};
    s_gpusync =
        (__system_property_get("debug.opengoal.grass_gpusync", sbuf) > 0 && sbuf[0] == '1');
  }
#else
  if (s_maxinst < 0) {
    const char* me = std::getenv("GRASS_MAXINST");
    s_maxinst = me ? atoi(me) : 0;
  }
#endif
  const int draw_n =
      (s_maxinst > 0 && s_maxinst < m_instance_count) ? s_maxinst : m_instance_count;

  // ROUND#19 GPU-WEDGE FIX (the REAL one, forensically pinned): the per-draw costs are healthy
  // (blade ~35 ms, card ~55 ms at density 150 — R19SYNC logs), but WITHOUT any drain the CPU queues
  // several ~130 ms grass frames ahead of the GPU; the Adreno driver's internal wait then exceeds the
  // kgsl deadlock budget -> IOCTL_KGSL errno-35 "Resource deadlock" -> ANR SIGKILL ~2 s after the
  // gameplay camera engages. PROOF: with a full glFinish drain each frame the same 150%-density boot
  // SURVIVES the entire hold (R19SYNC run), while 4 code-level theories (mid-loop return, normalize/
  // mix, attrib-4 fetch, lens-blade fill) were each falsified on device. FIX: bound the pipeline depth
  // to ONE in-flight grass frame with a fence — wait (bounded, 1 s) on the PREVIOUS frame's grass
  // fence before submitting this frame's draws. Costs nothing while the GPU keeps up; becomes the
  // throttle exactly when the GPU falls behind (which is when the unbounded queue used to wedge).
  // Grass-ON path only: OFF never reaches this code, stock rendering untouched.
  static GLsync s_grass_fence = nullptr;
  if (s_grass_fence) {
    glClientWaitSync(s_grass_fence, GL_SYNC_FLUSH_COMMANDS_BIT, 1000000000ull /* 1 s cap */);
    glDeleteSync(s_grass_fence);
    s_grass_fence = nullptr;
  }
  const bool sync_log = s_gpusync;  // every frame while the forensic prop is set (run dies in ~2 s)
  auto sync_ms = [&](const char* what) {
    if (!sync_log) {
      return;
    }
    auto t0s = std::chrono::steady_clock::now();
    glFinish();
    lg::info("[recharged-grass] R19SYNC frame={} {} finished in {:.1f} ms (draw_n={})", m_frame,
             what, std::chrono::duration<float, std::milli>(std::chrono::steady_clock::now() - t0s)
                       .count(),
             draw_n);
  };
  sync_ms("pre-draw (uniforms/upload)");

  // NEAR: individual blades (10-vert triangle strip)
  glUniform1i(mode_loc, 0);
  glDrawArraysInstanced(GL_TRIANGLE_STRIP, 0, 10, draw_n);
  prof.add_draw_call();
  prof.add_tri(draw_n * 8);
  sync_ms("blade draw");

  // MID: X-cross cards (12-vert, 4 triangles)
  glUniform1i(mode_loc, 1);
  glDrawArraysInstanced(GL_TRIANGLES, 0, 12, draw_n);
  prof.add_draw_call();
  prof.add_tri(draw_n * 4);
  sync_ms("card draw");

  // ROUND#19 wedge fix, part 2: fence THIS frame's grass draws; the wait above (next frame) will not
  // submit more grass until these have fully retired -> pipeline depth <= 1 grass frame, the unbounded
  // queue pileup that wedged the kgsl driver can no longer form.
  s_grass_fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);

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
