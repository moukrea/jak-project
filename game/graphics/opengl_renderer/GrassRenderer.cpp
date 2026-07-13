#include "GrassRenderer.h"
#include "game/graphics/opengl_renderer/GrassOccluders.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

#include "common/custom_data/Tfrag3Data.h"
#include "common/log/log.h"
#include "common/util/FileUtil.h"

#include "game/graphics/opengl_renderer/loader/Loader.h"

namespace {

// Grecharged-grass-precompute-mode: hash_u32/hash_f + all placement constants + the scan-internal
// texture helpers moved to GrassBakeCore (grass_bake namespace / GrassBakeCore.cpp). This TU keeps
// only the renderer-side debug knobs (grass_debug_mode, grass_tilt_amount) and instrumentation
// constants (CHUNK_M, OLD_WINDOW_M).
using grass_bake::hash_f;

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
//
// Grecharged-grass-precompute-mode: the placement constants (U, BASE_H, GROUND_UPNESS,
// UPNESS_LIP_MAX, MAX_TRI_AREA, D_TARGET, MAX_INSTANCES, BUDGET_SAFETY, LIGHT_GAIN, OCC_*,
// FLOOR_*) moved to grass_bake (GrassBakeCore.h). Only the renderer-side instrumentation
// constants stay here.
constexpr float U = grass_bake::U;        // GOAL world units per meter (renderer-side alias of grass_bake::U)
constexpr float CHUNK_M = 8.0f;           // instrumentation chunk size (m)
constexpr float OLD_WINDOW_M = 64.0f;     // the REMOVED camera window (for the fix diagnostic)

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
  using grass_bake::GrassInstance;  // vertex-layout offsets below reference the POD stride
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
  using clk = std::chrono::steady_clock;
  m_instances.clear();
  m_instance_count = 0;
  m_droop_start = 0;  // Grecharged-grass-overhang
  m_chunks.clear();
  m_cached_level = nullptr;
  m_cached_load_id = UINT64_MAX;
  m_inst_tri.clear();       // POLISH#9: per-instance source-tri map (rebuilt below)
  m_bake = grass_bake::BakeData{};   // Grecharged-grass-precompute-mode: per-tri baked-light source
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

  // Grecharged-grass-precompute-mode: floor-gap threshold prop read (moved OUT of scan; passed in).
  float floor_gap_m = grass_bake::FLOOR_GAP_M;
  bool floor_gap_overridden = false;
#ifdef __ANDROID__
  {
    char gbuf[16] = {0};
    if (__system_property_get("debug.opengoal.grass_floorgap", gbuf) > 0 && gbuf[0]) {
      float gv = (float)atof(gbuf);
      if (gv > 0.01f && gv < 2.5f) {
        floor_gap_m = gv;
        floor_gap_overridden = true;
      }
    }
  }
#endif

  const bool want_pre = Gfx::g_global_settings.recharged_grass_precomputed;
  const auto tA = clk::now();

  bool from_bake = false;
  // Resolve fr3 size (used both to validate a bake and as scan input).
  const std::string fr3_path =
      (file_util::get_jak_project_dir() / "out" / "jak1" / "fr3" / "training.fr3").string();
  u64 fr3_size = 0;
  {
    std::error_code ec;
    auto fs = std::filesystem::file_size(fr3_path, ec);
    if (!ec) {
      fr3_size = (u64)fs;
    }
  }

  if (want_pre && !floor_gap_overridden) {
    const std::string bake_path =
        (file_util::get_jak_project_dir() / "out" / "jak1" / "fr3" / "training.grassbake").string();
    grass_bake::BakeData loaded;
    std::string reason;
    if (!grass_bake::load_bake(loaded, bake_path)) {
      reason = "load failed";
    } else if (loaded.level_name != "training") {
      reason = "level mismatch";
    } else {
      u64 cur_fr3 = 0;
      bool have_fr3 = false;
      try {
        cur_fr3 = (u64)std::filesystem::file_size(fr3_path);
        have_fr3 = true;
      } catch (...) {
        have_fr3 = false;
      }
      if (!have_fr3 || loaded.fr3_size != cur_fr3) {
        reason = "fr3 size mismatch";
      } else if (loaded.floor_gap_m != floor_gap_m) {
        reason = "floor-gap mismatch";
      } else if (Gfx::g_global_settings.recharged_grass_density > loaded.bake_density_pct + 0.01f) {
        reason = "density slider above bake density";
      } else {
        from_bake = true;
        m_bake = std::move(loaded);
      }
    }
    if (!from_bake) {
      lg::info("[recharged-grass] PRECOMPUTED unavailable ({}) -> LIVE fallback", reason);
    }
  }

  if (!from_bake) {
    m_bake = grass_bake::scan_level(*lev, "training", fr3_size,
                                    {Gfx::g_global_settings.recharged_grass_density, floor_gap_m});
  }

  const auto tB = clk::now();
  auto res = grass_bake::expand(m_bake, Gfx::g_global_settings.recharged_grass_density);
  m_instances = std::move(res.instances);
  m_inst_tri = std::move(res.inst_tri);
  m_instance_count = (int)m_instances.size();
  m_droop_start = res.droop_start;
  // Grecharged-grass-overhang census: droop instances built (drawn only while the toggle is ON).
  lg::info(
      "[recharged-grass] GOVERHANG expand: droop_tris={} droop_instances={} (tail [{}..{}), toggle={}"
      " — near-LOD 3D droop over the lip faces, far LOD stays the stock alpha texture, no cards)",
      (int)m_bake.droop.size(), m_instance_count - m_droop_start, m_droop_start, m_instance_count,
      Gfx::g_global_settings.recharged_grass_overhang ? "ON" : "OFF");

  // Recompute `density` exactly as expand() did, for the STATIC place summary log.
  int budget;
  float density;
  {
    float dens_scale = std::min(2.5f, std::max(0.5f,
                                               Gfx::g_global_settings.recharged_grass_density / 100.0f));
    budget = (int)((float)grass_bake::MAX_INSTANCES * dens_scale);
    density = grass_bake::D_TARGET;
    if (m_bake.total_area_m2 > 1.0f &&
        m_bake.total_area_m2 * grass_bake::D_TARGET > grass_bake::BUDGET_SAFETY * (float)budget) {
      density = grass_bake::BUDGET_SAFETY * (float)budget / m_bake.total_area_m2;
    }
  }

  m_cached_density = Gfx::g_global_settings.recharged_grass_density;

  // ROUND#14 CAPTURE AID: RIMCAND dump (uses m_instances + gspare + m_bake.tris flags&1 for TIE).
  {
    const float U = grass_bake::U;
    struct Cand { float mx, my, mz; bool tie; };
    std::unordered_map<s64, Cand> best;  // one highest candidate per 6 m cell
    const float cinv = 1.0f / (6.0f * U);
    for (size_t i = 0; i < m_instances.size(); ++i) {
      const auto& gi = m_instances[i];
      if (gi.gspare > 0.15f * U) continue;  // near a true rim only
      s64 cx = (s64)std::floor(gi.px * cinv), cz = (s64)std::floor(gi.pz * cinv);
      s64 k = (cx << 32) ^ (cz & 0xffffffffLL);
      bool tie = (i < m_inst_tri.size() && m_inst_tri[i] < m_bake.tris.size())
                     ? (m_bake.tris[m_inst_tri[i]].flags & 1u) != 0
                     : false;
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
    const float U = grass_bake::U;
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
  const auto tExpandEnd = clk::now();  // expand + summary/RIMCAND/chunk logs done

  // The big "training STATIC place" summary (identical format). occ_culled/total come from expand();
  // scan stats (draws/tris/area/objpt buckets) come from m_bake.stats (identical on live + bake paths).
  {
    const int occ_culled = res.occ_culled;
    lg::info(
        "[recharged-grass] training STATIC place (whole-level, camera-independent): {} grass-ground "
        "draws ({} TIE), {} tris kept (giant {}, maxArea {:.0f}m2), area {:.0f} m2, density {:.0f}/m2 -> "
        "{} instances in {} chunks (POLISH#5 density {:.0f}% -> budget {}). ROUND#13 PER-INSTANCE "
        "object-hide (NO 0.5m cell nuke, NO 3x3 dilation): occ_culled {} of {} instances ({:.3f}%) — each "
        "blade tested vs {} NON-grass-TIE object-point buckets (grass-TIE platforms EXCLUDED = no self-cull) "
        "within radius {:.2f}m + contact band [{:.2f},{:.2f}]m; a blade is culled ONLY if a real object "
        "vertex is that close, so OPEN grass (no object) is NEVER culled = occ ~0 there, NO block-shaped "
        "bald holes. No camera window, no move-rebuild -> nothing de-instances while moving.",
        m_bake.stats.considered_draws, m_bake.stats.tie_draws, m_bake.stats.tris_kept,
        m_bake.stats.giant_tris, m_bake.stats.max_area, m_bake.total_area_m2, density,
        m_instance_count, (int)m_chunks.size(),
        Gfx::g_global_settings.recharged_grass_density, budget, occ_culled,
        m_instance_count + occ_culled,
        100.0f * (float)occ_culled / (float)std::max(1, m_instance_count + occ_culled),
        m_bake.stats.occ_objpt_buckets, grass_bake::OCC_RADIUS_M, grass_bake::OCC_LO_M,
        grass_bake::OCC_HI_M);
  }

  // Only commit the cache once the level is actually loaded (grass draws found), OR the bake loaded
  // successfully (bake path has no considered_draws) — a transient placement is not frozen incomplete.
  if (m_bake.stats.considered_draws > 0 || from_bake) {
    m_cached_level = (const void*)lev;
    m_cached_load_id = ld->load_id;
    m_cached_precomputed = want_pre;
    m_cached_floor_gap = floor_gap_m;
  }

  ensure_gl();
  glBindVertexArray(m_vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_instance_vbo);
  glBufferData(GL_ARRAY_BUFFER,
               (GLsizeiptr)(m_instance_count * sizeof(grass_bake::GrassInstance)),
               m_instances.empty() ? nullptr : m_instances.data(), GL_STATIC_DRAW);
  glBindVertexArray(0);
  glBindBuffer(GL_ARRAY_BUFFER, 0);

  // POLISH#9: populate the dynamic ground baked-light buffer for the CURRENT time of day right now.
  m_light_valid = false;
  update_light(rs);

  const auto tC = clk::now();
  auto ms = [](clk::time_point a, clk::time_point b) {
    return std::chrono::duration<float, std::milli>(b - a).count();
  };
  // source = tA..tB (load_bake OR scan); expand+logs = tB..tExpandEnd; upload+light = tExpandEnd..tC.
  lg::info(
      "[recharged-grass] PLACE-TIME mode={} total={:.0f}ms (source={:.0f}ms expand+logs={:.0f}ms "
      "upload+light={:.0f}ms) instances={}",
      from_bake ? "precomputed" : "live", ms(tA, tC), ms(tA, tB), ms(tB, tExpandEnd),
      ms(tExpandEnd, tC), m_instance_count);
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
  if (m_instance_count <= 0 || m_bake.tris.empty() || (int)m_inst_tri.size() < m_instance_count) {
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
  std::vector<std::array<u8, 3>> tri_rgb(m_bake.tris.size());
  for (size_t j = 0; j < m_bake.tris.size(); ++j) {
    for (int ch = 0; ch < 3; ++ch) {
      if (!valid) {
        tri_rgb[j][ch] = 128;
        continue;
      }
      float acc = 0.f;
      for (int p = 0; p < 8; ++p) {
        acc += m_bake.tris[j].pal[p][ch] * (float)w[p][ch];
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
      m_cached_density != Gfx::g_global_settings.recharged_grass_density ||
      m_cached_precomputed != Gfx::g_global_settings.recharged_grass_precomputed) {
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
  // Grecharged-grass-overhang: the droop instances sit at the buffer TAIL. The blade pass draws
  // them only while the toggle is ON; the card pass ALWAYS stops before them (owner: at distance
  // the ORIGINAL alpha overhang texture shows, no grass cards). Flipping the toggle changes only
  // these counts — no rebuild, and OFF is bit-identical to a build without the droop tail.
  const int nondroop_n = std::min(m_droop_start, m_instance_count);
  const int blade_total =
      Gfx::g_global_settings.recharged_grass_overhang ? m_instance_count : nondroop_n;
  const int draw_n = (s_maxinst > 0 && s_maxinst < blade_total) ? s_maxinst : blade_total;
  const int card_n = (s_maxinst > 0 && s_maxinst < nondroop_n) ? s_maxinst : nondroop_n;

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

  // MID: X-cross cards (12-vert, 4 triangles). card_n stops before the droop tail: droop NEVER
  // has a card tier (far LOD = the game's own alpha overhang texture).
  glUniform1i(mode_loc, 1);
  glDrawArraysInstanced(GL_TRIANGLES, 0, 12, card_n);
  prof.add_draw_call();
  prof.add_tri(card_n * 4);
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
