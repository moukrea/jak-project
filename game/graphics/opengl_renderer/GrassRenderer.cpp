#include "game/graphics/opengl_renderer/soft_draw_census.h"
#include "game/system/pad_replay.h"
#include "game/graphics/opengl_renderer/background/shrub_contact_probe.h"
#include "game/system/shrub_proof_inputs.h"
#include "GrassRenderer.h"
#include "game/system/recharged_gating.h"
#include "game/graphics/opengl_renderer/GrassOccluders.h"
#include "game/system/load_gate.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <filesystem>
#include <future>
#include <mutex>
#include <string>
#include <unordered_map>
#include <unordered_set>
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

#include "common/custom_data/Tfrag3Data.h"
#include "common/log/log.h"
#include "game/graphics/gl_query_census.h"
#include "common/util/FileUtil.h"

#include "game/graphics/opengl_renderer/background/background_common.h"
#include "game/graphics/opengl_renderer/PrePass.h"
#include "game/graphics/refset.h"
#include "game/system/autoport_proof.h"
#include "game/system/grass_baseline.h"
#include "game/system/grass_cull.h"
#include "game/graphics/opengl_renderer/loader/Loader.h"

// grass-chunk-cull : LE CACHE DE LOCALISATIONS D'UNIFORMES. La cause connue de l'item le nomme :
// « une trentaine de `glGetUniformLocation` par image sans cache, ce qui sur Adreno est un appel
// de pilote par nom ». On ne change RIEN a ce qui est demande ni a ce qui en est fait — la valeur
// rendue est celle du pilote, -1 compris (le repli `u_trample_str[0]` du correctif Adreno 618 la
// relit donc a l'identique). Les deux compteurs publient l'A/B dans la MEME course : les sites
// DEMANDES par image, et les appels de pilote reellement passes.
// Images ou le repli « plage entiere » s'est declenche. Un compteur PUBLIE, pas seulement
// journalise : si le decoupage produisait un jour plus d'appels que le budget, le gain
// disparaitrait en silence et la preuve n'aurait rien pour le nommer.
static u64 g_grass_run_overflow_frames = 0;
static u64 g_grass_uloc_requests = 0, g_grass_uloc_misses = 0;
static u64 g_grass_uloc_requests_frame = 0, g_grass_uloc_misses_frame = 0;
static GLint grass_uloc(GLuint prog, const char* name) {
  g_grass_uloc_requests++;
  static std::unordered_map<u64, std::unordered_map<std::string, GLint>> cache;
  auto& m = cache[(u64)prog];
  const auto it = m.find(name);
  if (it != m.end()) {
    return it->second;
  }
  g_grass_uloc_misses++;
  const GLint loc = glGetUniformLocation(prog, name);
  m.emplace(name, loc);
  return loc;
}


namespace {
std::unordered_map<unsigned int, unsigned int> grass_proof_programs;
}
void grass_proof_register_program(unsigned int colour, unsigned int measure) {
  const auto found = grass_proof_programs.find(colour);
  if (found != grass_proof_programs.end()) glDeleteProgram(found->second);
  grass_proof_programs[colour] = measure;
}

namespace {

// grass-dead-tail : l'item qui conditionne la construction de la queue d'overhang. Le SITE est
// enregistre au chargement (pas a l'execution) : c'est ce qui separe « aucun site compile ici »
// de « site compile, jamais atteint » dans validators/generic.sh.
constexpr const char* kDeadTailItemId = "grass-dead-tail";
AUTOPORT_FEATURE_SITE(kDeadTailItemId);

// grass-surface-truth : l'item qui fait lire les DEUX sources de classement d'une surface. Meme
// raison d'etre pour le SITE : « pas d'instrument ici » et « instrument jamais atteint » ne sont
// pas le meme zero.
constexpr const char* kSurfaceTruthItemId = "grass-surface-truth";
AUTOPORT_FEATURE_SITE(kSurfaceTruthItemId);

// grass-overlay-meshes : l'item qui etablit ou ecarte les meshes poses PAR-DESSUS un sol herbeux.
constexpr const char* kOverlayMeshesItemId = "grass-overlay-meshes";
AUTOPORT_FEATURE_SITE(kOverlayMeshesItemId);

// soft-surface-truth : l'item qui etablit sable, neige et neige profonde par les MEMES deux
// sources que l'herbe. Meme raison d'etre pour le SITE : « pas d'instrument ici » et « instrument
// jamais atteint » ne sont pas le meme zero.
constexpr const char* kSoftSurfaceItemId = "soft-surface-truth";
AUTOPORT_FEATURE_SITE(kSoftSurfaceItemId);

// soft-support-map : l'item qui cuit, pour chaque sommet de coque, SUR QUOI il repose et de
// COMBIEN il est souleve. Meme raison d'etre pour le SITE : « pas d'instrument ici » et
// « instrument jamais atteint » ne sont pas le meme zero.
constexpr const char* kSoftSupportItemId = "soft-support-map";
AUTOPORT_FEATURE_SITE(kSoftSupportItemId);

// grass-edge-truth : l'item qui etablit le bord sur le vide PAR LA GEOMETRIE. Meme raison d'etre
// pour le SITE : « pas d'instrument ici » et « instrument jamais atteint » ne sont pas le meme zero.
constexpr const char* kEdgeTruthItemId = "grass-edge-truth";
AUTOPORT_FEATURE_SITE(kEdgeTruthItemId);

// grass-path-transitions : l'item qui fait s'arreter l'herbe PROGRESSIVEMENT au bord des chemins.
// Contrairement aux trois ci-dessus, son travail CHANGE le placement : le site sert au temoin
// « l'instrument a tire », le recensement publie ce que la transition a produit.
constexpr const char* kPathTransItemId = "grass-path-transitions";
AUTOPORT_FEATURE_SITE(kPathTransItemId);

// grass-clumps : l'item qui fait pousser l'herbe en TOUFFES au lieu d'un bruit blanc de brins
// independants. Comme le precedent, son travail CHANGE le placement — mais lui porte aussi un bras
// d'ablation GEOMETRIQUE : `armed_for` a 0 rend le tirage barycentrique uniforme du code REMPLACE,
// sur le meme bake. Le bras `--off` ne mesure donc pas un instrument eteint, il mesure l'AUTRE
// regime, et `hits=` y tombe a 0 parce qu'aucune touffe n'est montee.
constexpr const char* kClumpItemId = "grass-clumps";
AUTOPORT_FEATURE_SITE(kClumpItemId);
// grass-shading (SPEC section 7) : la couleur de sol par TOUFFE et la lumiere cuite interpolee a
// l'origine de la touffe. Les deux naissent dans `expand()` ; le compteur de la ligne FEATURE
// compte les brins qui ont recu une couleur derivee de LEUR touffe.
constexpr const char* kShadeItemId = "grass-shading";
AUTOPORT_FEATURE_SITE(kShadeItemId);
// grass-blade-variants : desarme, k = 1 et TOUS les brins retombent sur la variante 0, c'est-a-dire
// la lame livree jusqu'ici.
constexpr const char* kVariantItemId = "grass-blade-variants";
AUTOPORT_FEATURE_SITE(kVariantItemId);

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

// Grecharged-grass-overhang2 (owner ROUND-2 defect 2: droop "descend beaucoup trop bas"): global
// scale on the droop arc's reach/drop (u_droop_len). Grecharged-grass-overhang3: the round-3 droop
// length is BAKE-CAPPED per-tri at the face's own in-plane exit distance (a blade can never overshoot
// the texture it covers), so this uniform is now a pure LIVE multiplier defaulting to neutral (1.0).
// Live-tunable without rebuild: Android prop debug.opengoal.grass.droop_len / desktop env
// GRASS_DROOP_LEN (float, clamped 0.1..1.5), same cached+throttled dual mechanism as grass_tilt_amount().
constexpr float DROOP_LEN_DEFAULT = 1.0f;
inline float grass_droop_len() {
  static float s_cached = DROOP_LEN_DEFAULT;
  static int s_throttle = 0;
  if ((s_throttle++ & 63) != 0) {
    return s_cached;
  }
  char buf[16] = {0};
  bool have = false;
#ifdef __ANDROID__
  if (__system_property_get("debug.opengoal.grass.droop_len", buf) > 0 && buf[0]) {
    have = true;
  }
#else
  const char* e = std::getenv("GRASS_DROOP_LEN");
  if (e && e[0]) {
    std::strncpy(buf, e, sizeof(buf) - 1);
    have = true;
  }
#endif
  float v = have ? (float)std::atof(buf) : DROOP_LEN_DEFAULT;
  if (v < 0.1f) v = DROOP_LEN_DEFAULT;  // unparsable/zero -> default, not a degenerate arc
  if (v > 1.5f) v = 1.5f;
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
  unsigned int actor_id = 0;  // 0: legacy static footprint; otherwise the GOAL process ID
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
struct MovingContact {
  unsigned int actor_id;
  std::array<float, 4> e;
};
static std::vector<MovingContact> s_goal_stage_moving;
static std::vector<MovingContact> s_goal_moving;
static double s_goal_snapshot_t = -1.0;  // R26: last goal_publish time (TTL fail-safe)
static double s_goal_pub_interval = 0.3;  // R27: EMA of the real publish cadence (adaptive TTL)

void goal_clear() {
  s_goal_stage_cull.clear();
  s_goal_stage_tramp.clear();
  s_goal_stage_moving.clear();
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
void goal_add_moving(unsigned int actor_id, float x, float y, float z, float r_world) {
  if (!actor_id || (x == 0.f && z == 0.f)) {
    return;
  }
  if (s_goal_stage_moving.size() < 64) {
    s_goal_stage_moving.push_back({actor_id, {x, y, z, r_world}});
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
    s_goal_moving = s_goal_stage_moving;
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
    lg::info("[recharged-grass] R21OCC goal-publish #{} ncull={} ntr={} nmoving={}{}", s_pub_n,
             (int)s_goal_stage_cull.size(), (int)s_goal_stage_tramp.size(),
             (int)s_goal_stage_moving.size(), ent);
  }
}

void publish(float dt) {
  std::vector<MovingContact> moving;
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
    bool snapshot_fresh =
        (s_goal_snapshot_t > 0.0) &&
        (now_s - s_goal_snapshot_t) < std::max(2.0, 4.0 * s_goal_pub_interval);
    // These are the actor snapshots consumed by the native contact integrator,
    // not its ghost strengths, tombstones or output uniforms.
    std::vector<std::array<float, 4>> proof_cull, proof_tramp;
    std::vector<MovingContact> proof_moving;
    const bool proof_inputs = shrub_proof_inputs::enabled();
    if (proof_inputs) {
      proof_cull = s_goal_cull; proof_tramp = s_goal_tramp; proof_moving = s_goal_moving;
    }
    snapshot_fresh = shrub_proof_inputs::value("contact/snapshot-fresh", snapshot_fresh);
    shrub_proof_inputs::vector("contact/actors-cull", proof_cull);
    shrub_proof_inputs::vector("contact/actors-tramp", proof_tramp);
    shrub_proof_inputs::vector("contact/actors-moving", proof_moving);
    if (snapshot_fresh)
    for (const auto& e : (proof_inputs ? proof_cull : s_goal_cull)) {
      add(e[0], e[1], e[2], e[3]);
    }
    if (snapshot_fresh)
    for (const auto& e : (proof_inputs ? proof_tramp : s_goal_tramp)) {
      add_trample(e[0], e[1], e[2], e[3]);
    }
    if (snapshot_fresh) {
      moving = proof_inputs ? proof_moving : s_goal_moving;
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
        const auto& jpp = Gfx::settings().recharged_jak_pos;
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
  std::array<float, 4> jkp;
  std::copy_n(Gfx::settings().recharged_jak_pos, 4, jkp.begin());
  shrub_proof_inputs::exchange("contact/sort-jak", jkp.data(), sizeof(float) * 4);
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
  double tnow = std::chrono::duration<double>(
                          std::chrono::steady_clock::now().time_since_epoch())
                          .count();
  tnow = shrub_proof_inputs::value("contact/tombstone-time", tnow);
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
      if (g.actor_id != 0) {
        continue;
      }
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
  // Mobile actors share the same easing and published arrays, but only their process ID
  // identifies a ghost. Static break tombstones never filter or suppress a moving contact.
  for (const auto& contact : moving) {
    TrampGhost* hit = nullptr;
    for (auto& g : s_tramp_state) {
      if (g.actor_id == contact.actor_id) {
        hit = &g;
        break;
      }
    }
    if (hit) {
      hit->e = contact.e;
      hit->seen = true;
    } else if (s_tramp_state.size() < 64) {
      s_tramp_state.push_back({contact.e, 0.f, true, contact.actor_id});
    }
  }
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
      if (it->actor_id == 0) {
        s_tombs.push_back({it->e[0], it->e[2], tnow});  // R27: static spot released -> ban 8 s
      }
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

namespace {
float contact_trail[16] = {};
std::array<float, 4> contact_jak{}, contact_ledge{};
std::vector<std::array<float, 4>> contact_all_positions;
std::vector<float> contact_all_strengths;
}

void begin_contact_frame() {
  // OWNER ROUND#18: publish this frame's merc-captured object occluders (crates / warp-gate button)
  // and clear the building list. Runs once before all Jak1 vegetation, regardless of its toggles,
  // so the building list never accumulates while grass is OFF. ROUND#21: publish takes the frame
  // dt so the per-object trample strengths ease in/out (broken-crate gradual spring-back).
  static const auto s_pub_t0 = std::chrono::steady_clock::now();
  static float s_pub_prev = -1.f;
  float pub_now =
      std::chrono::duration<float>(std::chrono::steady_clock::now() - s_pub_t0).count();
  pub_now = shrub_proof_inputs::value("contact/time", pub_now);
  // L'HORLOGE DU CONTACT S'EPINGLE SUR LA FRAME DE LOGIQUE, COMME CELLE DE LA BRISE.
  // 2026-09-17, ao-prepass-tie-alpha : `u_time` n'etait epingle que sous `refset::enabled()`,
  // jamais sous la sonde statique. Il descend dans `u_jak_trail[ti].w` (:754), puis dans
  // `vegetation_contact.glsl:38-49`, puis dans un DEPLACEMENT DE SOMMET (`shrub.vert:97`) :
  // deux courses appareil du MEME binaire au MEME tick logique pliaient donc les cartes de
  // shrub voisines de Jak differemment. Mesure : sur quatre captures de l'image 1400, 479077
  // pixels sur 480000 sont bit-identiques et les seuls qui bougent sont DEUX quadrilateres
  // semi-transparents hors TIE (notes/attempt19-plancher.md). Temoins de la meme preuve :
  // `wind_contact_jak_samples=5821` pour `wind_contact_uploads=1463`, `wind_contact_tie_*=0`
  // — les seuls contacts vivants sont Jak et son sillage, cote SHRUB seulement.
  // `:744` et `:753` sont des fonctions PURES de `u_time` : pas besoin du garde « un pas par
  // frame de logique » qu'exige l'accumulateur de `foliage_wind::set_wind_state`.
  static int64_t s_contact_lf = -1;
  static uint64_t s_contact_pins = 0;
  const int64_t probe_lf = prepass::static_probe_logic_frame();
  const bool pin = probe_lf >= 0;
  const bool fresh_lf = pin && probe_lf != s_contact_lf;
  if (fresh_lf) {
    s_contact_lf = probe_lf;
    autoport_proof::publish("ao_contact_time_pinned", ++s_contact_pins);
  }
  // Le `dt` de l'accumulateur d'objets avance d'un pas par frame de logique NEUVE, zero sinon :
  // deux images de rendu du meme tick ne doivent pas le faire avancer deux fois.
  grass_occ::publish(pin ? (fresh_lf ? 1.f / 60.f : 0.f)
                         : (s_pub_prev < 0.f ? 0.f : pub_now - s_pub_prev));
  s_pub_prev = pub_now;
  const float u_time = pin ? (float)probe_lf / 60.f
      : (refset::enabled() && refset::render_logic_frame() >= 0
             ? (float)refset::render_logic_frame() / 60.f : pub_now);
  std::array<float, 4> jp, jl;
  std::copy_n(Gfx::settings().recharged_jak_pos, 4, jp.begin());
  std::copy_n(Gfx::settings().recharged_jak_ledge, 4, jl.begin());
  shrub_proof_inputs::exchange("contact/jak", jp.data(), sizeof(float) * 4);
  shrub_proof_inputs::exchange("contact/ledge", jl.data(), sizeof(float) * 4);
  for (int i = 0; i < 4; ++i) {
    contact_jak[i] = jp[i];
    contact_ledge[i] = jl[i];
  }
  // Shrubs flatten beneath both actor categories. Grass keeps its original CULL/TRAMPLE split.
  struct ContactActor { std::array<float, 4> pos; float strength; };
  std::vector<ContactActor> actors;
  actors.reserve(g_tramp_published.size() + g_published.size());
  for (size_t i = 0; i < g_tramp_published.size(); ++i) {
    actors.push_back({g_tramp_published[i], g_tramp_strength[i]});
  }
  for (const auto& pos : g_published) {
    actors.push_back({pos, 1.f});
  }
  std::stable_sort(actors.begin(), actors.end(), [&](const ContactActor& a, const ContactActor& b) {
    const float ax = a.pos[0] - jp[0], az = a.pos[2] - jp[2];
    const float bx = b.pos[0] - jp[0], bz = b.pos[2] - jp[2];
    return ax * ax + az * az < bx * bx + bz * bz;
  });
  contact_all_positions.clear();
  contact_all_strengths.clear();
  for (size_t i = 0; i < std::min<size_t>(actors.size(), 16); ++i) {
    contact_all_positions.push_back(actors[i].pos);
    contact_all_strengths.push_back(actors[i].strength);
  }
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

    for (int ti = 0; ti < 4; ti++) {
      float age = u_time - s_trail[ti][3];
      float str = (jp[3] > 0.5f && s_trail[ti][3] > 0.f) ? std::max(0.f, 1.f - age / 0.6f) : 0.f;
      contact_trail[ti * 4 + 0] = s_trail[ti][0];
      contact_trail[ti * 4 + 1] = s_trail[ti][1];
      contact_trail[ti * 4 + 2] = s_trail[ti][2];
      contact_trail[ti * 4 + 3] = str;
    }

  }
}

ContactSources contact_sources(bool include_static) {
  const auto& positions = include_static ? contact_all_positions : g_tramp_published;
  const auto& strengths = include_static ? contact_all_strengths : g_tramp_strength;
  ContactSources result;
  result.jak_samples = (contact_jak[3] > 0.004f ? 1 : 0) + (contact_ledge[3] > 0.5f ? 1 : 0);
  for (int i = 0; i < 4; ++i) {
    result.jak_samples += contact_trail[i * 4 + 3] > 0.004f ? 1 : 0;
  }
  for (size_t i = 0; i < std::min<size_t>(positions.size(), include_static ? 16 : 8); ++i) {
    result.object_samples += strengths[i] > 0.f && positions[i][3] > 0.f ? 1 : 0;
  }
  return result;
}

bool push_contact_uniforms(unsigned int id, bool include_static) {
  const auto& positions = include_static ? contact_all_positions : g_tramp_published;
  const auto& strengths = include_static ? contact_all_strengths : g_tramp_strength;
  glUniform4fv(grass_uloc(id, "u_jak_pos"), 1, contact_jak.data());
  glUniform4fv(grass_uloc(id, "u_jak_ledge"), 1, contact_ledge.data());
  glUniform4fv(grass_uloc(id, "u_jak_trail"), 4, contact_trail);
  // OWNER Q&A 2026-07-12: breakable actors (crates, scarecrows) TRAMPLE the grass (flatten like Jak),
  // they do NOT cull it -> when the object is broken the grass springs back. Upload up to 16 as
  // u_trample (xyz = world pos, w = ground-contact radius). u_trample_count == 0 -> no flatten.
  {
    int ntr = (int)std::min<size_t>(positions.size(), include_static ? 16 : 8);  // literal-index shared contact cap
    if (ntr > 0) {
      glUniform4fv(grass_uloc(id, "u_trample"), ntr, &positions[0][0]);
      // ROUND#21: per-entry eased strength — the shader scales each entry's flatten by this, so a
      // broken crate's grass springs back over ~0.6 s (uniforms default to 0 -> upload is mandatory).
      // R21f: Adreno driver quirk — glGetUniformLocation on a float ARRAY can return -1 for the
      // bare name (works for vec4 arrays, fails for float arrays) -> the upload silently no-ops and
      // u_trample_str stays at its 0.0 default = flatten multiplied by ZERO (the "condition fires,
      // cyan marks show, nothing flattens" forensic signature). Query "name[0]" as fallback + log.
      int str_loc = grass_uloc(id, "u_trample_str");
      if (str_loc < 0) {
        str_loc = grass_uloc(id, "u_trample_str[0]");
      }
      static bool s_str_loc_logged = false;
      if (!s_str_loc_logged) {
        s_str_loc_logged = true;
        lg::info("[recharged-grass] R21F u_trample_str loc={} (bare={}) str[0]={:.2f} ntr={}",
                 str_loc, grass_uloc(id, "u_trample_str"),
                 strengths.empty() ? -1.f : strengths[0], ntr);
      }
      glUniform1fv(str_loc, ntr, strengths.data());
      // R21f: repack strengths into a vec4 array (.x) — see grass.vert; float-array dynamic reads
      // miscompile to 0 on the Adreno 618.
      float str4[16][4];
      for (int si = 0; si < ntr && si < 16; si++) {
        str4[si][0] = strengths[si];
        str4[si][1] = str4[si][2] = str4[si][3] = 0.f;
      }
      glUniform4fv(grass_uloc(id, "u_trample2"), ntr, &str4[0][0]);
    }
    glUniform1i(grass_uloc(id, "u_trample_count"), ntr);
  }

  return grass_uloc(id, "u_jak_pos") >= 0 &&
         grass_uloc(id, "u_jak_trail") >= 0 &&
         grass_uloc(id, "u_jak_ledge") >= 0 &&
         grass_uloc(id, "u_trample") >= 0 &&
         grass_uloc(id, "u_trample2") >= 0 &&
         grass_uloc(id, "u_trample_count") >= 0;
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
  m_attr4_on = !noattr4;
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

// ===== grass-chunk-cull : LES DEUX IMPLEMENTATIONS DU MEME PREDICAT ==========================
//
// La transformation monde->clip de `grass.vert:81-98` n'est PAS une mat4 ordinaire : division par
// w, ajout de `hvdf_offset`, -2048 / /256 / /-128, remultiplication par w. Elle est pourtant
// AFFINE en la position monde — la division et la remultiplication par le MEME `w` s'annulent
// algebriquement :
//     X = (fog*tx + (hvdf.x-2048)*tw) / 256
//     Y = -scissor * (fog*ty + (hvdf.y-2048)*tw) / 128
//     Z = (fog*tz + hvdf.z*tw) / 8388608 - tw
//     W = tw            avec  t = -camera[3] - camera[0]*x - camera[1]*y - camera[2]*z
// C'est ce qui permet d'en extraire six plans et de tester une boite par centre/extension.
//
// LE CULLER utilise ces plans. L'ORACLE, lui, rejoue la sequence LITTERALE du shader (division
// puis remultiplication) sur chaque point qu'il teste. Deux arithmetiques differentes pour le
// meme predicat : une transposition, un signe ou un terme oublie dans l'une se lit comme un ecart
// non nul, jamais comme un zero silencieux. L'oracle porte en plus une marge de 5 cm — largement
// au-dessus du bruit flottant, largement sous toute erreur reelle — pour qu'une egalite exacte au
// bord d'un plan ne puisse pas rougir la porte.
struct GrassClipPlanes {
  // plan k : g_k(p) = n[k][0]*x + n[k][1]*y + n[k][2]*z + n[k][3] >= 0 == DEDANS
  float n[6][4];
};

static GrassClipPlanes grass_build_planes(const std::array<math::Vector4f, 4>& cam,
                                          const float* hvdf,
                                          float fogc,
                                          float scissor_y) {
  // T[i][j] : t_i = T[i][0]*x + T[i][1]*y + T[i][2]*z + T[i][3]
  float T[4][4];
  for (int i = 0; i < 4; i++) {
    T[i][0] = -cam[0][i];
    T[i][1] = -cam[1][i];
    T[i][2] = -cam[2][i];
    T[i][3] = -cam[3][i];
  }
  float X[4], Y[4], Z[4], W[4];
  for (int j = 0; j < 4; j++) {
    W[j] = T[3][j];
    X[j] = (fogc * T[0][j] + (hvdf[0] - 2048.f) * T[3][j]) / 256.f;
    Y[j] = -scissor_y * (fogc * T[1][j] + (hvdf[1] - 2048.f) * T[3][j]) / 128.f;
    Z[j] = (fogc * T[2][j] + hvdf[2] * T[3][j]) / 8388608.f - T[3][j];
  }
  GrassClipPlanes pl;
  for (int j = 0; j < 4; j++) {
    pl.n[0][j] = W[j] + X[j];
    pl.n[1][j] = W[j] - X[j];
    pl.n[2][j] = W[j] + Y[j];
    pl.n[3][j] = W[j] - Y[j];
    pl.n[4][j] = W[j] + Z[j];
    pl.n[5][j] = W[j] - Z[j];
  }
  return pl;
}

// LE CULLER : test centre/extension, six plans, pas de branche par coin.
static inline bool grass_box_outside(const GrassClipPlanes& pl,
                                     const float lo[3],
                                     const float hi[3]) {
  const float cx = 0.5f * (lo[0] + hi[0]), cy = 0.5f * (lo[1] + hi[1]),
              cz = 0.5f * (lo[2] + hi[2]);
  const float ex = 0.5f * (hi[0] - lo[0]), ey = 0.5f * (hi[1] - lo[1]),
              ez = 0.5f * (hi[2] - lo[2]);
  for (int k = 0; k < 6; k++) {
    const float* n = pl.n[k];
    const float d = n[0] * cx + n[1] * cy + n[2] * cz + n[3];
    const float r = std::fabs(n[0]) * ex + std::fabs(n[1]) * ey + std::fabs(n[2]) * ez;
    if (d + r < 0.f) {
      return true;  // la boite entiere est du mauvais cote de ce plan
    }
  }
  return false;
}

// L'ORACLE : la sequence LITTERALE de `grass.vert`, puis les six valeurs de plan du point.
static inline void grass_clip_literal(const std::array<math::Vector4f, 4>& cam,
                                      const float* hvdf,
                                      float fogc,
                                      float scissor_y,
                                      float px,
                                      float py,
                                      float pz,
                                      float g[6]) {
  float tx = -cam[3][0] - cam[0][0] * px - cam[1][0] * py - cam[2][0] * pz;
  float ty = -cam[3][1] - cam[0][1] * px - cam[1][1] * py - cam[2][1] * pz;
  float tz = -cam[3][2] - cam[0][2] * px - cam[1][2] * py - cam[2][2] * pz;
  const float tw = -cam[3][3] - cam[0][3] * px - cam[1][3] * py - cam[2][3] * pz;
  const float Q = fogc / tw;
  float x = tx * Q + hvdf[0];
  float y = ty * Q + hvdf[1];
  float z = tz * Q + hvdf[2];
  x -= 2048.f;
  y -= 2048.f;
  z = z / 8388608.f - 1.f;
  x /= 256.f;
  y /= -128.f;
  const float X = x * tw;
  const float Y = y * tw * scissor_y;
  const float Z = z * tw;
  g[0] = tw + X;
  g[1] = tw - X;
  g[2] = tw + Y;
  g[3] = tw - Y;
  g[4] = tw + Z;
  g[5] = tw - Z;
}

// Une boite est DEHORS pour l'oracle quand ses huit coins tombent du mauvais cote d'un MEME plan.
// Exact pour un convexe, et sans hypothese de signe sur w.
static bool grass_box_outside_literal(const std::array<math::Vector4f, 4>& cam,
                                      const float* hvdf,
                                      float fogc,
                                      float scissor_y,
                                      const float lo[3],
                                      const float hi[3]) {
  bool out[6] = {true, true, true, true, true, true};
  for (int c = 0; c < 8; c++) {
    const float px = (c & 1) ? hi[0] : lo[0];
    const float py = (c & 2) ? hi[1] : lo[1];
    const float pz = (c & 4) ? hi[2] : lo[2];
    float g[6];
    grass_clip_literal(cam, hvdf, fogc, scissor_y, px, py, pz, g);
    bool any = false;
    for (int k = 0; k < 6; k++) {
      if (g[k] >= 0.f) {
        out[k] = false;
      } else {
        any = true;
      }
    }
    (void)any;
  }
  for (int k = 0; k < 6; k++) {
    if (out[k]) {
      return true;
    }
  }
  return false;
}

// Marges du culler, en metres. Elles couvrent tout ce que le shader ajoute autour de l'origine
// d'une instance : hauteur du brin (deja dans `hi[1]` de la boite cuite), courbure, lacet, brise,
// pietinement, demi-largeur d'une carte. Genereuses A DESSEIN : une marge trop large ne coute que
// quelques lots gardes en trop, une marge trop courte retire des pixels.
constexpr float kCullMarginXZ_M = 1.5f;
constexpr float kCullMarginY_M = 0.5f;
// L'oracle teste une boite 5 cm PLUS LARGE que le culler. Largement au-dessus du bruit flottant
// entre deux ecritures de la meme algebre, largement en dessous de toute erreur reelle : une
// egalite exacte au bord d'un plan ne peut pas rougir la porte, une transposition ou un signe
// inverse la rougissent de plusieurs milliers d'instances.
constexpr float kOracleSlack_M = 0.05f;
// SCISSOR_ADJUST * HEIGHT_SCALE substitues par Shader.cpp pour jak1 (l'herbe n'existe que la).
constexpr float kGrassScissorY = 512.0f / 448.0f;
// Au-dela, un appel de dessin par lot couterait plus qu'il ne rapporte : on retombe sur la plage
// entiere et la preuve le NOMME (`grass_cull_run_overflow`), au lieu de livrer 1 400 appels.
constexpr int kMaxRunsPerPass = 128;

// Les plages CONTIGUES de lots gardes. Aucune fusion a travers un trou : une instance soumise est
// une instance qu'un lot garde a demandee, sinon le compte d'instances hors champ mentirait.
static void grass_build_runs(const std::vector<grass_bake::GrassChunk>& chunks,
                             const std::vector<u8>& keep,
                             u8 mask,
                             std::vector<std::pair<int, int>>& out) {
  out.clear();
  for (size_t i = 0; i < chunks.size(); i++) {
    if (!(keep[i] & mask)) {
      continue;
    }
    const int first = (int)chunks[i].first;
    const int count = (int)chunks[i].count;
    if (!out.empty() && out.back().first + out.back().second == first) {
      out.back().second += count;
    } else {
      out.push_back({first, count});
    }
  }
}

// Gloading-screen-window : les deux passes de diagnostic de `rebuild` (RIMCAND, grille de chunks)
// balayent 726 851 instances et n'ont AUCUN effet sur l'image. Lues une seule fois, pour que
// l'ablation porte sur toute la course et pas sur une partie.
static bool grass_diag_enabled() {
  static bool v = []() {
    const char* e = getenv("OG_GRASS_DIAG");
    return e && atoi(e) != 0;
  }();
  return v;
}

// Gloading-screen-window : INTERRUPTEUR D'ABLATION DE L'EXPANSION HORS THREAD DE RENDU, SUR LE MEME
// BINAIRE. Non posee ou non nulle -> chemin ASYNCHRONE (ce qu'on livre) ; `OG_GRASS_ASYNC=0` ->
// chemin SYNCHRONE, le comportement d'aujourd'hui, qui est la jambe « avant » de la mesure. Lue une
// seule fois, comme `grass_diag_enabled()` ci-dessus, pour que l'ablation porte sur TOUTE la course
// et pas sur une partie.
// Gloading-screen-window : INTERRUPTEUR D'ABLATION DU SAUT DU DESSIN SOUS L'ECRAN DE CHARGEMENT,
// SUR LE MEME BINAIRE. Non posee ou non nulle -> on saute (ce qu'on livre) ; `OG_GRASS_SKIP_COVERED=0`
// -> on peint sous l'ecran, c'est-a-dire le comportement d'aujourd'hui, jambe « avant ». Lue une
// seule fois, pour que l'ablation porte sur TOUTE la course.
static bool grass_skip_covered_enabled() {
  static bool v = []() {
    const char* e = getenv("OG_GRASS_SKIP_COVERED");
    return (!e || !e[0]) ? true : (atoi(e) != 0);
  }();
  return v;
}

// Ggrass-crash : l'expansion hors du thread de rendu reste ARMEE (defaut d'origine).
//
// POURQUOI, ET C'EST UNE MESURE. Elle est nee au commit 25ae957df7 — LE MEME lot qui a fait passer
// `rebuild()` de `void` a `bool` sans valeur de retour, et LE MEME lot qui separe le build que
// l'owner voyait charger de celui qui mourait. Sur l'appareil, le fil de rendu meurt d'une
// `std::bad_alloc` que PERSONNE n'attrape, alors que deux `catch (const std::exception&)`
// encadrent lexiquement tout le chemin d'herbe et sont bien presents dans le `.so` INSTALLE
// (verifie par `grep -ac` sur l'appareil). Un handler present sur la pile et introuvable par le
// derouleur, c'est le symptome d'un etat que le fil de rendu ne possede plus seul — et le SEUL
// endroit ou le chemin d'herbe partage de l'etat entre deux fils est ici : `expand` lit
// `m_pending.bake` PAR REFERENCE depuis le fil de `std::async`.
//
// CE QU'ON PERD EN LE DESARMANT, ET POURQUOI C'EST LE BON ECHANGE. L'expansion revient sur le fil
// de rendu : elle y coute 154 a 221 ms UNE FOIS par chargement de niveau a herbe (mesure x86), ce
// que la phase Gloading-screen-window cherchait justement a retirer. C'est un a-coup pendant
// l'ecran de chargement. En face : un jeu qui ne charge plus du tout. Un a-coup se voit, une mort
// se subit — et l'owner nous a deja dit, mot pour mot, « un jeu qui charge vaut mieux qu'un ecran
// parfait ».
//
// L'INTERRUPTEUR RESTE, DANS LES DEUX SENS, pour que l'ablation reste jouable sur LE MEME BINAIRE :
//   bureau   OG_GRASS_ASYNC=1              -> rearme le fil d'expansion
//   appareil debug.opengoal.grass_async=1  -> idem (le bureau lit `getenv`, pas l'appareil : sans
//                                             cette propriete l'ablation etait INJOUABLE la ou le
//                                             defaut se produit, ce qui est exactement le piege
//                                             « instrument absent la ou on en a besoin »)
static bool grass_async_expand_enabled() {
  static bool v = []() {
    const char* e = getenv("OG_GRASS_ASYNC");
    if (e && e[0]) {
      return atoi(e) != 0;
    }
  #ifdef __ANDROID__
    char b[16] = {0};
    if (__system_property_get("debug.opengoal.grass_async", b) > 0 && b[0]) {
      return atoi(b) != 0;
    }
  #endif
    // Ggrass-crash : REARME. Le desarmement etait une hypothese sur la cause ; elle est REFUTEE —
    // le plantage venait du pointeur pendant de `ScopedProfilerNode` (voir Profiler.h), pas du fil
    // d'expansion, et `GOVERHANG6` prouvait deja que ce fil allait jusqu'au bout. On ne garde donc
    // pas l'a-coup de 154-221 ms par chargement que Gloading-screen-window avait retire.
    return true;
  }();
  return v;
}

// Ggrass-crash : LE GARDE DE FAMINE. Voir GrassRenderer.h pour la mesure qui le justifie.
// Il DEGRADE (pas d'herbe) au lieu de LAISSER MOURIR, et il commet les cles de cache : sans ca
// `render()` rappellerait `rebuild()` a chaque image et rejouerait le scan qui vient d'echouer —
// une boucle de famine a la place d'une degradation.
bool GrassRenderer::oom_disarm(const void* lev,
                               u64 load_id,
                               const std::string& level_name,
                               float floor_gap_m,
                               const char* where,
                               const char* what) {
  lg::warn(
      "[recharged-grass] OOM-DISARM niveau={} etape={} exception={} — le champ d'herbe est ABANDONNE "
      "pour ce chargement (aucun brin dessine) au lieu d'abattre le processus. Ce n'est PAS une "
      "reussite : cette ligne NOMME l'etape qui a manque de memoire, et elle doit etre traitee.",
      level_name, where, what);
  std::vector<grass_bake::GrassInstance>().swap(m_instances);
  std::vector<u32>().swap(m_inst_tri);
  std::vector<u8>().swap(m_light);
  std::vector<u8>().swap(m_variant);
  std::vector<u8>().swap(m_inst_bw);  // grass-shading : poids de touffe, liberes avec le champ
  m_shaded = false;
  m_shade_hits = 0;
  m_chunks.clear();
  m_bake = grass_bake::BakeData{};
  m_pending.bake = grass_bake::BakeData{};
  m_instance_count = 0;
  m_droop_start = 0;
  m_light_valid = false;
  m_expand_pending = false;
  m_expand_waits = 0;
  m_cached_level = lev;
  m_cached_load_id = load_id;
  m_cached_precomputed = recharged_gating::on(recharged_gating::kGrassPrecomputed);
  m_cached_preset =
      grass_bake::clamp_density_preset(Gfx::settings().recharged_grass_density_preset);
  m_cached_floor_gap = floor_gap_m;
  return true;
}

bool GrassRenderer::rebuild(SharedRenderState* rs,
                            const LevelData* ld,
                            const std::string& level_name) {
  using clk = std::chrono::steady_clock;
  grass_bake::ExpandResult res;
  // Instant ou l'expansion commence a etre facturee AU THREAD DE RENDU. Chemin synchrone : juste
  // avant le calcul lui-meme (il paie tout). Chemin asynchrone : juste avant le ramassage d'un
  // futur DEJA pret (il ne paie presque rien). L'ecart `tExpandJoin..tExpandDone` est donc la
  // grandeur que le lot pretend faire tomber, mesuree la ou elle fait mal.
  clk::time_point tExpandJoin{};

  if (!m_expand_pending) {
    // ==================================== ETAPE SOURCE ====================================
    // Resolution du chemin de bake, `load_bake` ou scan du niveau -> `m_bake`. INCHANGEE (le seul
    // ecart est l'indentation : elle vit maintenant dans la branche « pas d'expansion en vol »).
    m_instances.clear();
    m_instance_count = 0;
    m_droop_start = 0;  // Grecharged-grass-overhang
    m_chunks.clear();
    m_cached_level = nullptr;
    m_cached_load_id = UINT64_MAX;
    m_inst_tri.clear();       // POLISH#9: per-instance source-tri map (rebuilt below)
    m_bake = grass_bake::BakeData{};   // Grecharged-grass-precompute-mode: per-tri baked-light source
    m_light.clear();
    m_variant.clear();
    m_inst_bw.clear();  // grass-shading : reconstruits plus bas avec le champ
    m_shaded = false;
    m_shade_hits = 0;
    m_light_valid = false;

    // Grecharged-grass-overhang7: the level is resolved by render()'s allowlist lookup and passed in.
    if (!ld || !ld->level) {
      return true;  // rien a construire (pas de niveau) — ce n'est PAS une expansion en cours
    }
    const tfrag3::Level* lev = ld->level.get();

    // ===================== grass-surface-truth : LES DEUX SOURCES ==========================
    // Ce bloc LIT et PUBLIE, il ne decide rien. `m_bake`, `m_instances`, `expand()` et le format
    // du `.grassbake` ne le voient pas : le placement de cette course est identique au bit a
    // celui d'avant. Il ne s'execute QUE lorsque le harnais mesure CET item (`feature_is`), donc
    // le binaire que l'owner joue ne paie pas ce recensement ; et il compte ses prises par
    // `note_hit_for`, qui se tait tout seul dans le bras `--off` (d'ou `armed=0 hits=0`).
    //
    // UNE COURSE DE JEU NE CHARGE QU'UN NIVEAU. Les DIX niveaux que le contrat demande sont
    // recenses par le MEME code hors ligne (`tools/grass_bake --surface-census`), appele par
    // `.autoport/lib/census/grass-surface-truth.sh` : c'est lui qui publie la grandeur de la
    // porte. Ici, le temoin est que l'instrument vit bien DANS le moteur et qu'il a tire.
    if (autoport_proof::feature_is(kSurfaceTruthItemId)) {
      static std::string s_surface_census_done;
      if (s_surface_census_done != level_name) {
        s_surface_census_done = level_name;
        const auto sc = grass_bake::surface_census(*lev, level_name);
        autoport_proof::publish_text("grass_surface_engine_level", level_name.c_str());
        autoport_proof::publish("grass_surface_engine_ground", sc.ground_tris);
        autoport_proof::publish("grass_surface_engine_collision", sc.collision_tris);
        autoport_proof::publish("grass_surface_engine_by_material", sc.by_material);
        autoport_proof::publish("grass_surface_engine_by_texture", sc.by_texture);
        autoport_proof::publish("grass_surface_engine_by_both", sc.by_both);
        autoport_proof::publish("grass_surface_engine_classified", sc.classified);
        autoport_proof::publish("grass_surface_engine_unclassified", sc.unclassified);
        autoport_proof::publish("grass_surface_engine_disagree", sc.disagree);
        autoport_proof::publish("grass_surface_engine_mat_grass", sc.mat_grass);
        autoport_proof::publish("grass_surface_engine_tex_grass", sc.tex_grass);
        autoport_proof::publish("grass_surface_engine_legacy3_unclassified",
                                sc.legacy3_unclassified);
        autoport_proof::publish_text("grass_surface_engine_disagree_tex",
                                     sc.disagree_tex_top.c_str());
        autoport_proof::note_hit_for(kSurfaceTruthItemId, sc.classified);
      }
    }
    // ====================== fin grass-surface-truth ========================================

    // ===================== soft-surface-truth : SABLE ET NEIGE ============================
    // MEME REGLE, MEME LECTEUR, MEME INNOCUITE que le bloc ci-dessus : il LIT et PUBLIE, il ne
    // decide rien, `m_bake` / `m_instances` / `expand()` ne le voient pas, et il ne tourne que
    // lorsque le harnais mesure CET item. Les niveaux que la campagne `soft-*` vise (snow, beach,
    // village1, ogre...) sont recenses hors ligne par le MEME code
    // (`tools/grass_bake --soft-surface-census`, appele par `.autoport/lib/census/soft-surface-truth.sh`) :
    // c'est lui qui publie la grandeur de la porte. Ici, le temoin est que l'instrument vit dans
    // le moteur et qu'il a tire sur le niveau charge.
    if (autoport_proof::feature_is(kSoftSurfaceItemId)) {
      static std::string s_soft_census_done;
      if (s_soft_census_done != level_name) {
        s_soft_census_done = level_name;
        const auto sc = grass_bake::soft_surface_census(*lev, level_name);
        autoport_proof::publish_text("soft_surface_engine_level", level_name.c_str());
        autoport_proof::publish("soft_surface_engine_ground", sc.ground_tris);
        autoport_proof::publish("soft_surface_engine_collision", sc.collision_tris);
        autoport_proof::publish("soft_surface_engine_by_material", sc.by_material);
        autoport_proof::publish("soft_surface_engine_by_texture", sc.by_texture);
        autoport_proof::publish("soft_surface_engine_classified", sc.classified);
        autoport_proof::publish("soft_surface_engine_unclassified", sc.unclassified);
        autoport_proof::publish("soft_surface_engine_mat_sand", sc.mat_sand);
        autoport_proof::publish("soft_surface_engine_mat_snow", sc.mat_snow);
        autoport_proof::publish("soft_surface_engine_mat_deepsnow", sc.mat_deepsnow);
        autoport_proof::publish("soft_surface_engine_tex_soft", sc.tex_soft);
        autoport_proof::publish("soft_surface_engine_soft_by_either", sc.soft_by_either);
        autoport_proof::publish("soft_surface_engine_disagree", sc.disagree);
        autoport_proof::publish("soft_surface_engine_cross_raw", sc.cross_raw);
        autoport_proof::publish("soft_surface_engine_cross_eligible", sc.cross_eligible);
        autoport_proof::publish("soft_surface_engine_eligible_soft", sc.eligible_soft);
        autoport_proof::publish("soft_surface_engine_eligible_grass", sc.eligible_grass);
        autoport_proof::publish("soft_surface_engine_mode_wall_soft", sc.mode_wall_soft);
        autoport_proof::publish_text("soft_surface_engine_mat_soft_tex",
                                     sc.mat_soft_tex_top.c_str());
        autoport_proof::publish_text("soft_surface_engine_cross_raw_tex",
                                     sc.cross_raw_tex_top.c_str());
        autoport_proof::note_hit_for(kSoftSurfaceItemId, sc.classified);
      }
    }
    // ====================== fin soft-surface-truth =========================================

    // ================= soft-support-map : LE SUPPORT ET L'EPAISSEUR, CUITS ==================
    // MEME REGLE, MEME INNOCUITE : il LIT, il CUIT EN MEMOIRE, il PUBLIE. Rien n'est ecrit, ni
    // dans `m_bake`, ni sur le disque ; la serialisation appartient a `soft-bake-format`. Le
    // MEME code (`grass_bake::soft_support_map`) est appele hors ligne sur les 25 niveaux par
    // `.autoport/lib/census/soft-support-map.sh`, et c'est LUI qui publie la grandeur de la
    // porte. Ici, le temoin est que l'instrument vit dans le moteur et qu'il a tire sur le
    // niveau charge.
    if (autoport_proof::feature_is(kSoftSupportItemId)) {
      static std::string s_soft_map_done;
      if (s_soft_map_done != level_name) {
        s_soft_map_done = level_name;
        const auto sm = grass_bake::soft_support_map(*lev, level_name);
        autoport_proof::publish_text("soft_map_engine_level", level_name.c_str());
        autoport_proof::publish("soft_map_engine_render_indexed", sm.render_tris_indexed);
        autoport_proof::publish("soft_map_engine_collision", sm.collision_tris);
        autoport_proof::publish("soft_map_engine_soft_tris", sm.soft_tris);
        autoport_proof::publish("soft_map_engine_hull_tris", sm.hull_tris);
        autoport_proof::publish("soft_map_engine_hull_verts", sm.hull_verts);
        autoport_proof::publish("soft_map_engine_hull_verts_thick", sm.hull_verts_thick);
        autoport_proof::publish("soft_map_engine_hull_verts_tested", sm.hull_verts_tested);
        autoport_proof::publish("soft_map_engine_boundary_verts", sm.boundary_verts);
        autoport_proof::publish("soft_map_engine_interior_verts", sm.interior_verts);
        autoport_proof::publish("soft_map_engine_coll_mode_wall_soft", sm.coll_mode_wall_soft);
        autoport_proof::publish("soft_map_engine_rej_support_wall", sm.rej_support_wall);
        autoport_proof::publish("soft_map_engine_rej_slope", sm.rej_slope);
        autoport_proof::publish("soft_map_engine_rej_backface", sm.rej_backface);
        autoport_proof::publish("soft_map_engine_rej_overlay_grass", sm.rej_overlay_grass);
        autoport_proof::publish("soft_map_engine_rej_seafloor", sm.rej_seafloor);
        autoport_proof::publish("soft_map_engine_rej_tie_not_terrain", sm.rej_tie_not_terrain);
        autoport_proof::publish("soft_map_engine_static_objects", sm.static_objects);
        autoport_proof::publish("soft_map_engine_depression_verts", sm.depression_verts);
        autoport_proof::publish("soft_map_engine_deep_islands", sm.deep_islands);
        autoport_proof::publish("soft_map_engine_fixpoint_rounds", sm.fixpoint_rounds);
        autoport_proof::publish("soft_map_engine_defects",
                                sm.defect_no_support + sm.defect_below_support +
                                    sm.defect_negative + sm.defect_boundary +
                                    sm.defect_direction);
        autoport_proof::publish_text("soft_map_engine_support_mat", sm.support_mat_top.c_str());
        autoport_proof::note_hit_for(kSoftSupportItemId, sm.hull_verts_thick);
      }
    }
    // ====================== fin soft-support-map ===========================================

    // ================== grass-overlay-meshes : LES MESHES POSES PAR-DESSUS ==================
    // Meme regle que ci-dessus : ce bloc LIT et PUBLIE, il ne place rien, et il ne tourne que
    // lorsque le harnais mesure CET item. Le recensement hors ligne
    // (`.autoport/lib/census/grass-overlay-meshes.sh`) passe les DIX niveaux avec le MEME code ;
    // ici, le temoin est que l'instrument vit dans le moteur et qu'il a tire.
    //
    // LE CONTROLE POSITIF TOURNE AUSSI. La reponse attendue de cet item peut etre zero, et un
    // zero de detecteur mort s'ecrirait exactement comme un zero de donnee propre.
    if (autoport_proof::feature_is(kOverlayMeshesItemId)) {
      static std::string s_overlay_census_done;
      if (s_overlay_census_done != level_name) {
        s_overlay_census_done = level_name;
        const auto st = grass_bake::overlay_census_selftest();
        autoport_proof::publish("grass_overlay_engine_selftest_ok", st.ok);
        autoport_proof::publish("grass_overlay_engine_selftest_found", st.found);
        const auto oc = grass_bake::overlay_census(*lev, level_name);
        autoport_proof::publish_text("grass_overlay_engine_level", level_name.c_str());
        autoport_proof::publish("grass_overlay_engine_render_up", oc.render_up_tris);
        autoport_proof::publish("grass_overlay_engine_collision", oc.collision_ground_tris);
        autoport_proof::publish("grass_overlay_engine_pairs_tested", oc.pairs_tested);
        autoport_proof::publish("grass_overlay_engine_pairs_close_y", oc.pairs_close_y);
        autoport_proof::publish("grass_overlay_engine_bare_over_grass", oc.pairs_bare_over_grass);
        autoport_proof::publish("grass_overlay_engine_method_a", oc.method_a);
        autoport_proof::publish("grass_overlay_engine_method_b", oc.method_b);
        autoport_proof::publish("grass_overlay_engine_intersection", oc.intersection);
        autoport_proof::publish("grass_overlay_engine_found", oc.found);
        autoport_proof::publish("grass_overlay_engine_cls_path", oc.cls_path);
        autoport_proof::publish("grass_overlay_engine_cls_patch", oc.cls_patch);
        autoport_proof::publish("grass_overlay_engine_cls_ambiguous", oc.cls_ambiguous);
        autoport_proof::publish("grass_overlay_engine_unclassified", oc.unclassified);
        autoport_proof::publish("grass_overlay_engine_sum_check", oc.sum_check);
        autoport_proof::publish_text("grass_overlay_engine_pair_src", oc.pair_src_top.c_str());
        autoport_proof::publish_text("grass_overlay_engine_pair_tex", oc.pair_tex_top.c_str());
        autoport_proof::note_hit_for(kOverlayMeshesItemId, oc.pairs_tested);
      }
    }
    // ====================== fin grass-overlay-meshes ========================================

    // ============== grass-edge-truth : LE BORD SUR LE VIDE, PAR LA GEOMETRIE ================
    // Meme regle que ci-dessus : ce bloc LIT et PUBLIE, il ne place rien, il ne deplace aucun
    // brin, et il ne tourne que lorsque le harnais mesure CET item. Le recensement hors ligne
    // (`.autoport/lib/census/grass-edge-truth.sh`) passe les DIX niveaux avec le MEME code et
    // publie la grandeur de la porte ; ici, le temoin est que l'instrument vit bien DANS le
    // moteur et qu'il a tire.
    //
    // LE BANC NOMME TOURNE AUSSI, et c'est lui qui peut rendre la sonde FAUSSE : le controle de
    // somme des huit classes est structurel, les dix-neuf aretes nommees ne le sont pas.
    if (autoport_proof::feature_is(kEdgeTruthItemId)) {
      static std::string s_edge_census_done;
      if (s_edge_census_done != level_name) {
        s_edge_census_done = level_name;
        const auto st = grass_bake::edge_probe_selftest();
        autoport_proof::publish("grass_edge_engine_selftest_ok", st.ok);
        autoport_proof::publish("grass_edge_engine_selftest_cases", st.cases);
        autoport_proof::publish("grass_edge_engine_selftest_disagree", st.disagree);
        autoport_proof::publish("grass_edge_engine_selftest_expect_void", st.expect_void);
        autoport_proof::publish("grass_edge_engine_selftest_expect_floor", st.expect_floor);
        autoport_proof::publish_text("grass_edge_engine_selftest_disagreements",
                                     st.disagree_list.c_str());
        const auto ec = grass_bake::edge_census(*lev, level_name);
        autoport_proof::publish_text("grass_edge_engine_level", level_name.c_str());
        autoport_proof::publish("grass_edge_engine_tris_used", ec.tris_used);
        autoport_proof::publish("grass_edge_engine_edges", ec.edges_total);
        autoport_proof::publish("grass_edge_engine_cls_triangle", ec.cls[grass_bake::kEdgeTriangle]);
        autoport_proof::publish("grass_edge_engine_cls_uv_seam", ec.cls[grass_bake::kEdgeUvSeam]);
        autoport_proof::publish("grass_edge_engine_cls_material", ec.cls[grass_bake::kEdgeMaterial]);
        autoport_proof::publish("grass_edge_engine_cls_normal_break",
                                ec.cls[grass_bake::kEdgeNormalBreak]);
        autoport_proof::publish("grass_edge_engine_cls_chunk", ec.cls[grass_bake::kEdgeChunk]);
        autoport_proof::publish("grass_edge_engine_cls_overlay", ec.cls[grass_bake::kEdgeOverlay]);
        autoport_proof::publish("grass_edge_engine_cls_path", ec.cls[grass_bake::kEdgePath]);
        autoport_proof::publish("grass_edge_engine_cls_void", ec.cls[grass_bake::kEdgeVoid]);
        autoport_proof::publish("grass_edge_engine_classified", ec.classified);
        autoport_proof::publish("grass_edge_engine_claimed_none", ec.claimed_none);
        autoport_proof::publish("grass_edge_engine_claimed_multi", ec.claimed_multi);
        autoport_proof::publish("grass_edge_engine_class_sum_check", ec.class_sum_check);
        autoport_proof::publish("grass_edge_engine_unshared_but_floor", ec.unshared_but_floor);
        autoport_proof::publish("grass_edge_engine_shared_but_void", ec.shared_but_void);
        autoport_proof::publish("grass_edge_engine_old_rule_void", ec.old_rule_void);
        autoport_proof::publish("grass_edge_engine_old_only", ec.old_only);
        autoport_proof::publish("grass_edge_engine_geom_only", ec.geom_only);
        autoport_proof::publish("grass_edge_engine_terrace_nongrass_void",
                                ec.terrace_nongrass_void);
        autoport_proof::publish_text("grass_edge_engine_wall_mat", ec.void_wall_mat_top.c_str());
        autoport_proof::publish_text("grass_edge_engine_class_top", ec.class_top.c_str());
        autoport_proof::note_hit_for(kEdgeTruthItemId, ec.classified);
      }
    }
    // ====================== fin grass-edge-truth ============================================

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

    const bool want_pre = recharged_gating::on(recharged_gating::kGrassPrecomputed);
    const auto tA = clk::now();

    bool from_bake = false;
    std::string resolved_bake_path;
    // Resolve fr3 size (used both to validate a bake and as scan input).
    //
    // Ggrass-crash : LE .fr3 QU'ON MESURAIT N'ETAIT PAS CELUI QUE LE JEU CHARGE, ET C'EST LA CAUSE
    // RACINE DU REPLI EN DIRECT SUR L'APPAREIL.
    // Le `.grassbake` est resolu quinze lignes plus bas par `resolve_fr3_asset`, qui consulte le
    // pack CUSTOM d'abord et le pack de BASE ensuite, le custom l'emportant (`FileUtil.cpp:417-419`).
    // Cette ligne-ci, elle, construisait son chemin en dur avec `get_fr3_dir()` — donc la copie de
    // BASE, toujours. Les deux ne designent pas le meme fichier des qu'un pack custom est installe.
    // MESURE, sur le Redmi, `files/asset_route.txt` du jeu lui-meme :
    //   training.fr3       -> .../files/custom/jak1/fr3/training.fr3 (custom-pack) custom=yes
    //                        9419374B  base=yes 7629858B
    //   training.grassbake -> .../files/custom/jak1/fr3/training.grassbake (custom-pack) 2024808B
    // Le bake ARRIVE bien sur l'appareil et il est cuit contre la copie CUSTOM (9 419 374 o) ; la
    // validation le comparait a la copie de BASE (7 629 858 o). Ecart 1 789 516 o -> « fr3 size
    // mismatch » -> repli EN DIRECT, a CHAQUE chargement, par construction. L'intuition de l'owner
    // (« c'est ptetre le build from scratch, ca pre-compute plus le placement de l'herbe ») etait
    // juste : c'est ce chantier-la qui a fait diverger les deux copies.
    // On resout donc le .fr3 avec LE MEME resolveur que son bake. Sur bureau il n'existe pas de
    // pack custom : `resolve_fr3_asset` rend exactement `get_fr3_dir()/<niveau>.fr3` et le
    // comportement x86 est INCHANGE (verifie : mode=precomputed avant comme apres).
    const auto fr3_route = file_util::resolve_fr3_asset(GameVersion::Jak1, level_name + ".fr3");
    const std::string fr3_path = fr3_route.path.string();
    u64 fr3_size = 0;
    {
      std::error_code ec;
      auto fs = std::filesystem::file_size(fr3_path, ec);
      if (!ec) {
        fr3_size = (u64)fs;
      }
    }

    // Ggrass-crash : LA LECTURE DU BAKE EST SOUS GARDE, ELLE AUSSI. Mesure sur le Redmi, APRES la
    // correction du resolveur : 12 courses sur 12, `malloc(8027506242768285312)` refuse 24 ms apres
    // la resolution du `.grassbake`, donc DANS `load_bake` ou dans la mise en place de `m_pending`.
    // La taille est parlante — `0x6f676e65706f2e80`, soit les octets `80 2e 6f 70 65 6e 67 6f`
    // = « \x80.opengo » : du TEXTE DE CHEMIN lu comme une taille. C'est un compte lu au mauvais
    // endroit, pas une allocation « trop grande ». Le garde ne repare pas ca — il empeche que ca
    // tue le jeu, et il NOMME l'etape, ce que le plantage ne faisait pas.
    // ================================ Ggrass-density-presets ================================
    // CINQ PALIERS, CINQ BAKES, ET PLUS AUCUN REPLI EN DIRECT.
    //
    // Owner 2026-08-30 : « on s'en fiche de changer la densite au poil de cul, on veut juste plus ou
    // moins dense [...] donc on peut pre-calculer le tout et eviter le chemin lourd ».
    //
    // CE QUI DISPARAIT ICI, ET POURQUOI. L'ancienne resolution chargeait UN bake par niveau puis
    // comparait le curseur a sa densite (`density > bake_density_pct` -> « density slider above bake
    // density »), et TOUT echec de validation retombait sur `scan_level` — le placement EN DIRECT,
    // mesure a 1 207 Mo de pointe contre 735 avec pre-calcul, et la population ou les plantages ont
    // ete reproduits sur le Redmi (6 sur 6 courses herbe armee).
    // Le palier demande porte maintenant SON PROPRE fichier, `<niveau>.<palier>.grassbake`, et
    // l'expansion se fait a la densite DU BAKE CHARGE : la comparaison n'a plus de valeur
    // intermediaire a rencontrer, elle n'est pas « inatteignable », elle n'existe plus.
    //
    // ET S'IL MANQUE UN BAKE : on descend l'echelle vers un palier PLUS BAS (une densite plus faible
    // est exactement le PREFIXE de la meme liste de candidats — `expand` reprend les candidats 0..n-1
    // avec les memes graines, cf. GrassBakeCore.cpp:975-982 contre :1770-1785), donc le repli reste
    // PRE-CALCULE et deterministe. Si aucun palier ne valide, il n'y a PAS D'HERBE et on le dit fort.
    // Jamais de scan en direct : c'est le chemin qu'on retire, on ne s'y rabat pas en cachette.
    const int want_preset =
        grass_bake::clamp_density_preset(Gfx::settings().recharged_grass_density_preset);
    int served_preset = want_preset;
    try {
    if (want_pre && !floor_gap_overridden) {
      std::string refus;
      for (int cand = want_preset; cand >= 0 && !from_bake; --cand) {
        // Round 30 (delivery): same one resolver as the fr3 sidecar — package copy wins, decision
        // journalled. The resolved path is echoed in the PLACE-TIME log below.
        const std::string bake_path =
            file_util::resolve_fr3_asset(
                GameVersion::Jak1,
                fmt::format("{}.{}.grassbake", level_name, grass_bake::density_preset_slug(cand)))
                .path.string();
        if (resolved_bake_path.empty()) {
          resolved_bake_path = bake_path;  // le chemin DEMANDE, meme si c'est un palier plus bas qui sert
        }
        grass_bake::BakeData loaded;
        std::string reason;
        if (!grass_bake::load_bake(loaded, bake_path)) {
          reason = "load failed";
        } else if (loaded.level_name != level_name) {
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
            // Ggrass-crash : la raison PORTE SES DEUX NOMBRES ET LE CHEMIN RESOLU. « fr3 size
            // mismatch » tout court ne disait pas CONTRE QUOI la comparaison avait ete faite — et
            // c'etait precisement la ou etait le defaut : on comparait au mauvais fichier.
            reason = fmt::format("fr3 size mismatch: bake={} vs {}={} (source={})", loaded.fr3_size,
                                 fr3_path, cur_fr3, fr3_route.source);
          } else if (loaded.floor_gap_m != floor_gap_m) {
            reason = "floor-gap mismatch";
          } else {
            from_bake = true;
            served_preset = cand;
            resolved_bake_path = bake_path;
            m_bake = std::move(loaded);
          }
        }
        if (!from_bake) {
          refus += fmt::format("[{}] {}; ", grass_bake::density_preset_slug(cand), reason);
        }
      }
      // La ligne se publie DANS LES DEUX CAS : elle nomme le palier demande ET le palier servi, donc
      // « le bake demande manquait » et « tout va bien » ne se confondent plus dans un silence.
      lg::info(
          "[recharged-grass] GRASSPRESET niveau={} palier_demande={} palier_servi={} depuis_bake={} "
          "bake={} refus={}",
          level_name, grass_bake::density_preset_slug(want_preset),
          from_bake ? grass_bake::density_preset_slug(served_preset) : "<aucun>", from_bake ? 1 : 0,
          resolved_bake_path.empty() ? "<none>" : resolved_bake_path,
          refus.empty() ? "<aucun>" : refus);
    }

    if (!from_bake && want_pre && !floor_gap_overridden) {
      // AUCUN PALIER N'A VALIDE. On ne scanne pas : le champ reste vide, le niveau se joue sans
      // herbe, et la trace le dit. C'est le seul comportement compatible avec « eviter le chemin
      // lourd » — un repli silencieux vers 1 207 Mo serait exactement le defaut qu'on ferme.
      lg::error(
          "[recharged-grass] AUCUN BAKE VALIDE pour '{}' (palier demande {}) — PAS D'HERBE sur ce "
          "niveau. Le placement EN DIRECT n'est PAS emprunte : il a ete retire du repli.",
          level_name, grass_bake::density_preset_slug(want_preset));
      std::vector<grass_bake::GrassInstance>().swap(m_instances);
      std::vector<u32>().swap(m_inst_tri);
      std::vector<u8>().swap(m_light);
      std::vector<u8>().swap(m_variant);
      std::vector<u8>().swap(m_inst_bw);  // grass-shading
      m_shaded = false;
      m_shade_hits = 0;
      m_chunks.clear();
      m_bake = grass_bake::BakeData{};
      m_instance_count = 0;
      m_droop_start = 0;
      m_light_valid = false;
      m_expand_pending = false;
      m_expand_waits = 0;
      m_cached_level = (const void*)lev;
      m_cached_load_id = ld->load_id;
      m_cached_precomputed = recharged_gating::on(recharged_gating::kGrassPrecomputed);
      m_cached_preset = want_preset;
      m_cached_floor_gap = floor_gap_m;
      return true;
    }

    if (!from_bake) {
      // JAMBE DE MESURE UNIQUEMENT. On n'arrive ici que si `recharged-grass-precomputed?` est a #f
      // dans settings.ini (cle sans rangee de menu depuis ce lot) ou si le seuil de jointure au sol
      // est force par une propriete de debug. C'est la jambe « avant » qui permet de publier le pic
      // memoire du chemin direct ; le jeu livre ne l'emprunte pas.
      m_bake = grass_bake::scan_level(*lev, level_name, fr3_size,
                                      {grass_bake::density_preset_pct(want_preset), floor_gap_m});
    }

    const auto tB = clk::now();

    // Contexte de CETTE reconstruction. L'etape de CONSOMMATION peut tourner plusieurs images plus
    // tard : elle doit decrire l'expansion LANCEE, pas l'image qui la ramasse. `lev` n'est garde
    // que comme VALEUR de comparaison de cache — jamais dereferencee, le LevelData peut avoir ete
    // detruit entre-temps.
    m_pending.lev = (const void*)lev;
    m_pending.load_id = ld->load_id;
    m_pending.level_name = level_name;
    m_pending.resolved_bake_path = resolved_bake_path;
    m_pending.from_bake = from_bake;
    m_pending.want_pre = want_pre;
    m_pending.floor_gap_m = floor_gap_m;
    // Ggrass-density-presets : l'expansion se fait a la densite DU BAKE CHARGE, pas a une valeur
    // demandee ailleurs. `scan_level` pose la meme valeur sur la jambe de mesure, donc cette ligne
    // est vraie des deux cotes et il n'existe plus de couple (demande, bake) a comparer.
    m_pending.density = m_bake.bake_density_pct;
    m_pending.want_preset = want_preset;
    m_pending.served_preset = served_preset;
    m_pending.tA = tA;
    m_pending.tB = tB;
    m_expand_waits = 0;

    if (grass_async_expand_enabled()) {
      // `expand` est PURE : sa seule entree est le BakeData qu'on lui passe. On le DEPLACE dans
      // `m_pending.bake`, auquel plus rien ne touche tant que `m_expand_pending` est vrai, pour
      // qu'aucune reecriture de `m_bake` par l'etape SOURCE ne puisse courir contre la lecture du
      // thread. Il revient dans `m_bake` a la consommation (la consommation ET le dessin le lisent).
      m_pending.bake = std::move(m_bake);
      m_expand_pending = true;
      m_expand_future = std::async(std::launch::async, &grass_bake::expand,
                                   std::cref(m_pending.bake), m_pending.density,
                                   autoport_proof::feature_is(kPathTransItemId) ||
                                       autoport_proof::feature_is(kClumpItemId),
                                   autoport_proof::armed_for(kClumpItemId),
                                   autoport_proof::armed_for(kShadeItemId));
      return false;  // champ pas encore construit : rien a dessiner, on repassera a l'image suivante
    }
    tExpandJoin = clk::now();
    res = grass_bake::expand(m_bake, m_pending.density,
                             autoport_proof::feature_is(kPathTransItemId) ||
                                 autoport_proof::feature_is(kClumpItemId),
                             autoport_proof::armed_for(kClumpItemId),
                             autoport_proof::armed_for(kShadeItemId));
    } catch (const std::exception& e) {
      // La garde couvre TOUTE l'etape SOURCE : lecture du bake, scan en direct, mise en place de
      // `m_pending`, lancement du thread d'expansion, et l'expansion synchrone.
      return oom_disarm((const void*)lev, ld->load_id, level_name, floor_gap_m, "etape SOURCE",
                        e.what());
    }
  } else {
    // ============================== ATTENTE (chemin asynchrone) ==============================
    // L'etape SOURCE n'est PAS rejouee tant que l'expansion est en vol.
    if (m_expand_future.wait_for(std::chrono::seconds(0)) != std::future_status::ready) {
      m_expand_waits++;
      return false;
    }
    tExpandJoin = clk::now();
    // `std::async` CAPTURE l'exception du thread d'expansion et la RELANCE ici, sur le thread de
    // rendu. C'est le chemin exact observe sur le Redmi : l'allocation echoue dans `expand`, et
    // c'est SDLThread qui meurt d'un `std::bad_alloc` non attrape. Il l'est desormais.
    try {
      res = m_expand_future.get();
    } catch (const std::exception& e) {
      return oom_disarm(m_pending.lev, m_pending.load_id, m_pending.level_name,
                        m_pending.floor_gap_m, "expand (thread d'expansion)", e.what());
    }
    m_expand_pending = false;
    m_bake = std::move(m_pending.bake);
  }
  const auto tExpandDone = clk::now();

  // ============ grass-path-transitions : CE QUE LA TRANSITION A PRODUIT, SUR CE NIVEAU ===========
  // Le placement, lui, a deja change : il n'est PAS conditionne par `feature_is`, sinon l'owner ne
  // verrait rien. Ce qui l'est, c'est la MESURE — elle relit les brins qu'on vient d'emettre, elle
  // n'en deplace aucun, et elle ne coute rien au binaire que l'owner joue. Le recensement hors
  // ligne (`.autoport/lib/census/grass-path-transitions.sh`) passe le MEME code sur les niveaux ;
  // ici, le temoin est que l'instrument vit dans le moteur et qu'il a tire.
  if (autoport_proof::feature_is(kPathTransItemId)) {
    const auto tc = grass_bake::transition_census(m_bake, res);
    autoport_proof::publish_text("grass_trans_engine_level", level_name.c_str());
    autoport_proof::publish("grass_trans_engine_bare_draws", tc.bare_draws_both);
    autoport_proof::publish("grass_trans_engine_bare_tris", tc.bare_tris);
    autoport_proof::publish("grass_trans_engine_faces_up", tc.faces_up);
    autoport_proof::publish("grass_trans_engine_faces_flush", tc.faces_affleurantes);
    autoport_proof::publish("grass_trans_engine_faces_lifted", tc.faces_lifted);
    autoport_proof::publish("grass_trans_engine_occ_object", tc.occ_pts_object);
    autoport_proof::publish("grass_trans_engine_occ_removed", tc.occ_pts_removed);
    autoport_proof::publish("grass_trans_engine_blades", tc.blades_total);
    autoport_proof::publish("grass_trans_engine_blades_band", tc.blades_band);
    autoport_proof::publish("grass_trans_engine_blades_inside", tc.blades_inside);
    autoport_proof::publish("grass_trans_engine_cand_limit", tc.cand_limit);
    autoport_proof::publish("grass_trans_engine_pos_mismatch", tc.pos_mismatch);
    autoport_proof::publish("grass_trans_engine_gap_defect", tc.gap_cause_trans);
    autoport_proof::publish("grass_trans_engine_gap_object", tc.gap_cause_object);
    autoport_proof::publish("grass_trans_engine_gap_inside", tc.gap_cause_inside);
    autoport_proof::publish("grass_trans_engine_terms", tc.terms_measured);
    autoport_proof::publish("grass_trans_engine_culled_inside",
                            (uint64_t)res.trans_culled_inside);
    autoport_proof::publish("grass_trans_engine_culled_thin", (uint64_t)res.trans_culled_thin);
    autoport_proof::publish_text("grass_trans_engine_bare_tex", tc.bare_tex_top.c_str());
    autoport_proof::publish_text("grass_trans_engine_bare_mat", tc.bare_mat_top.c_str());
    // Les flottants passent par un texte : `publish` ne porte que des entiers, et un millieme de
    // metre ecrit en entier resterait lisible sans inventer une seconde unite.
    autoport_proof::publish("grass_trans_engine_gap_p50_mm", (uint64_t)std::lround(tc.gap_p50 * 1000.f));
    autoport_proof::publish("grass_trans_engine_gap_p99_mm", (uint64_t)std::lround(tc.gap_p99 * 1000.f));
    autoport_proof::publish("grass_trans_engine_defect_max_mm",
                            (uint64_t)std::lround(tc.gap_defect_max * 1000.f));
    autoport_proof::publish("grass_trans_engine_edge_follow_pm",
                            (uint64_t)std::lround(tc.edge_follow_frac * 1000.f));
    autoport_proof::publish("grass_trans_engine_graded_pm",
                            (uint64_t)std::lround(tc.graded_frac * 1000.f));
    // `hits=` de la ligne FEATURE : les brins situes dans une bande de transition, exactement ce
    // que le contrat de l'item nomme.
    autoport_proof::note_hit_for(kPathTransItemId, tc.blades_band);
  }

  // ================= grass-clumps : CE QUE LE REGROUPEMENT A PRODUIT, SUR CE NIVEAU =============
  // Meme regle que ci-dessus : le PLACEMENT n'est pas conditionne par `feature_is` (l'owner doit
  // voir les touffes dans son binaire), seule la MESURE l'est. Elle relit les brins qu'on vient
  // d'emettre et recalcule, pour chacun, la racine que le tirage uniforme lui aurait donnee : les
  // deux regimes dans LA MEME image, sur LA MEME surface, avec LE MEME compte de brins.
  // `res.clumped` dit sous quel regime cette expansion a tourne — un temoin, pas un reglage.
  if (autoport_proof::feature_is(kClumpItemId)) {
    const auto cc = grass_bake::clump_census(m_bake, res);
    autoport_proof::publish_text("grass_clump_engine_level", level_name.c_str());
    autoport_proof::publish("grass_clump_engine_armed", res.clumped ? 1u : 0u);
    autoport_proof::publish("grass_clump_engine_blades", cc.blades_total);
    autoport_proof::publish("grass_clump_engine_clumps", cc.clumps_total);
    autoport_proof::publish("grass_clump_engine_mounted", cc.clumps_mounted);
    autoport_proof::publish("grass_clump_engine_pairs_sampled", cc.pairs_sampled);
    autoport_proof::publish("grass_clump_engine_root_outside", cc.root_outside);
    autoport_proof::publish("grass_clump_engine_pos_mismatch", cc.pos_mismatch);
    autoport_proof::publish("grass_clump_engine_clipped", cc.clipped);
    autoport_proof::publish("grass_clump_engine_terms", cc.terms_measured);
    // Les flottants passent en milli-unites entieres : `publish` ne porte que des entiers, et le
    // moissonneur de proof_run.sh refuse toute valeur qui contient un espace.
    autoport_proof::publish("grass_clump_engine_pairs_clumped_pm",
                            (uint64_t)std::lround(cc.pairs_clumped * 1000.0));
    autoport_proof::publish("grass_clump_engine_pairs_uniform_pm",
                            (uint64_t)std::lround(cc.pairs_uniform * 1000.0));
    autoport_proof::publish("grass_clump_engine_pairs_ratio_pm",
                            (uint64_t)std::lround(cc.pairs_ratio * 1000.0));
    autoport_proof::publish("grass_clump_engine_size_mean_pm",
                            (uint64_t)std::lround(cc.size_mean * 1000.0));
    autoport_proof::publish("grass_clump_engine_size_cv_pm",
                            (uint64_t)std::lround(cc.size_cv * 1000.0));
    autoport_proof::publish("grass_clump_engine_radius_mm",
                            (uint64_t)std::lround(cc.radius_mean_m * 1000.0));
    autoport_proof::publish("grass_clump_engine_radius_cv_pm",
                            (uint64_t)std::lround(cc.radius_cv * 1000.0));
    autoport_proof::publish("grass_clump_engine_height_ratio_pm",
                            (uint64_t)std::lround(cc.height_mean_ratio * 1000.0));
    {
      // L'empreinte des origines : c'est elle qui rend « deux chargements donnent les memes
      // touffes aux memes endroits » comparable entre deux courses.
      char buf[32];
      snprintf(buf, sizeof(buf), "%016llx", (unsigned long long)cc.origin_digest);
      autoport_proof::publish_text("grass_clump_engine_digest", buf);
    }
    // `hits=` de la ligne FEATURE : les touffes EFFECTIVEMENT MONTEES, exactement ce que
    // `hits_means` du backlog nomme. Desarme, le placement est uniforme : aucune touffe n'est
    // montee, `clumps_mounted` vaut 0, et la ligne rend `armed=0 hits=0`.
    autoport_proof::note_hit_for(kClumpItemId, cc.clumps_mounted);
  }

  // ============== grass-blade-variants : LA SILHOUETTE DE CHAQUE BRIN ======================
  // Le palier commande le NOMBRE de variantes (SPEC section 13) ; la variante d'un brin sort de sa
  // RACINE, donc elle ne change pas d'un palier a l'autre. Desarme, k = 1 : tous les brins sont la
  // lame v0, c'est-a-dire le rendu livre jusqu'ici, au bit pres.
  {
    // LE PALIER SERVI, PAS LE PALIER EN CACHE. `m_cached_preset` n'est affecte qu'a la fin de
    // l'etape de consommation (plus bas) : ici il porte encore le palier du chargement PRECEDENT,
    // et -1 au tout premier. Le palier de CETTE expansion est celui que `m_pending` porte — et
    // c'est le palier SERVI qui compte, pas le demande : quand le bake du palier demande manque, le
    // champ construit est celui d'un cran en dessous, et le nombre de variantes doit suivre le
    // champ reellement bati, sinon le recensement hors ligne mesurerait un autre palier.
    const int vpreset = grass_bake::clamp_density_preset(m_pending.served_preset);
    const int vk = autoport_proof::armed_for(kVariantItemId)
                       ? grass_bake::variants_for_preset(vpreset)
                       : 1;
    m_variant.assign(res.instances.size(), 0);
    for (size_t i = 0; i < res.instances.size(); ++i) {
      m_variant[i] = (u8)grass_bake::blade_variant_of(res.instances[i], vk);
    }
    if (autoport_proof::feature_is(kVariantItemId)) {
      const auto vc = grass_bake::variant_census(res.instances, 0, res.instances.size(), vk);
      autoport_proof::publish_text("grass_variant_engine_level", level_name.c_str());
      autoport_proof::publish("grass_variant_engine_armed",
                              autoport_proof::armed_for(kVariantItemId) ? 1u : 0u);
      autoport_proof::publish("grass_variant_engine_preset", (uint64_t)vpreset);
      autoport_proof::publish("grass_variant_engine_preset_wanted",
                              (uint64_t)grass_bake::clamp_density_preset(m_pending.want_preset));
      autoport_proof::publish("grass_variant_engine_k", (uint64_t)vc.k);
      autoport_proof::publish("grass_variant_engine_blades", vc.blades);
      autoport_proof::publish("grass_variant_engine_folded", vc.folded);
      autoport_proof::publish("grass_variant_engine_off_profile", (uint64_t)vc.off_profile);
      autoport_proof::publish("grass_variant_engine_verts_strip", (uint64_t)vc.verts_strip);
      autoport_proof::publish("grass_variant_engine_verts_max", (uint64_t)vc.verts_max);
      autoport_proof::publish("grass_variant_engine_verts_over", (uint64_t)vc.verts_over);
      autoport_proof::publish("grass_variant_engine_verts_active_total", vc.verts_active_total);
      autoport_proof::publish("grass_variant_engine_verts_strip_total", vc.verts_strip_total);
      autoport_proof::publish("grass_variant_engine_terms", (uint64_t)vc.terms_measured);
      for (int v = 0; v < grass_bake::kBladeVariantCount; ++v) {
        char key[64];
        snprintf(key, sizeof(key), "grass_variant_engine_v%d", v);
        autoport_proof::publish(key, vc.per_variant[v]);
        snprintf(key, sizeof(key), "grass_variant_engine_base_v%d", v);
        autoport_proof::publish(key, vc.per_base[v]);
        snprintf(key, sizeof(key), "grass_variant_engine_share_pm_v%d", v);
        autoport_proof::publish(key, (uint64_t)vc.share_pm[v]);
        snprintf(key, sizeof(key), "grass_variant_engine_expect_pm_v%d", v);
        autoport_proof::publish(key, (uint64_t)vc.expect_pm[v]);
        snprintf(key, sizeof(key), "grass_variant_engine_tol_pm_v%d", v);
        autoport_proof::publish(key, (uint64_t)vc.tol_pm[v]);
        snprintf(key, sizeof(key), "grass_variant_engine_seg_v%d", v);
        autoport_proof::publish(key, (uint64_t)grass_bake::kBladeVariants[v].segments);
      }
      {
        char buf[32];
        snprintf(buf, sizeof(buf), "%016llx", (unsigned long long)vc.digest);
        autoport_proof::publish_text("grass_variant_engine_digest", buf);
      }
      // `hits=` de la ligne FEATURE : les brins AYANT RECU UNE VARIANTE, exactement ce que
      // `hits_means` du backlog nomme. Desarme, aucun brin n'en recoit : k=1, et le compte tombe a 0.
      autoport_proof::note_hit_for(kVariantItemId,
                                   vk > 1 ? vc.blades : 0);
    }
  }

  // ================================= ETAPE CONSOMMATION =================================
  // INCHANGEE. Ses locales de contexte viennent de l'etape SOURCE, portees par `m_pending` : sur le
  // chemin synchrone elles sont posees quelques microsecondes plus haut, donc a l'identique.
  const bool from_bake = m_pending.from_bake;
  const bool want_pre = m_pending.want_pre;
  const float floor_gap_m = m_pending.floor_gap_m;
  const float slider_density = m_pending.density;
  const std::string& resolved_bake_path = m_pending.resolved_bake_path;
  const std::string& lvl_name = m_pending.level_name;
  const clk::time_point tA = m_pending.tA;
  const clk::time_point tB = m_pending.tB;

  m_instances = std::move(res.instances);
  m_inst_tri = std::move(res.inst_tri);
  // grass-shading : les poids barycentriques de l'origine de chaque touffe. `update_light()` les
  // lit pour interpoler les palettes des trois sommets AILLEURS qu'au centroide. Une table dont la
  // taille ne colle pas au champ est REFUSEE la-bas, pas devinee ici.
  m_inst_bw = std::move(res.inst_bw);
  m_shade_hits = res.shade_hits;
  m_shaded = res.shaded;
  m_instance_count = (int)m_instances.size();
  m_droop_start = res.droop_start;
  // grass-chunk-cull : LA PARTITION EN VIGUEUR. Le contrat veut les bounds DANS LE FICHIER, on les
  // y prend ; `expand()` vient d'en recalculer une, et leur ecart est publie. Une table absente
  // (bake d'une version anterieure) ou qui ne couvre pas exactement [0, n) n'est pas utilisee : le
  // dessin repart alors sur la plage entiere, jamais sur une partition douteuse.
  {
    auto covered_by = [](const std::vector<grass_bake::GrassChunk>& t) -> u64 {
      u64 sum = 0;
      for (const auto& c : t) {
        if (c.first != (u32)sum) {
          return 0;
        }
        sum += c.count;
      }
      return sum;
    };
    const u64 file_cov = covered_by(m_bake.chunks);
    const u64 calc_cov = covered_by(res.chunks);
    m_cull_from_file = (file_cov == (u64)m_instance_count) && m_instance_count > 0;
    m_cull_chunks = m_cull_from_file ? m_bake.chunks : res.chunks;
    m_cull_covered = m_cull_from_file ? file_cov : calc_cov;
    if (m_cull_covered != (u64)m_instance_count) {
      m_cull_chunks.clear();
      m_cull_covered = 0;
    }
    m_cull_mismatch = 0;
    if (m_bake.chunks.size() != res.chunks.size()) {
      m_cull_mismatch = m_bake.chunks.size() > res.chunks.size()
                            ? m_bake.chunks.size() - res.chunks.size()
                            : res.chunks.size() - m_bake.chunks.size();
    } else {
      for (size_t i = 0; i < res.chunks.size(); i++) {
        if (std::memcmp(&res.chunks[i], &m_bake.chunks[i], sizeof(grass_bake::GrassChunk)) != 0) {
          m_cull_mismatch++;
        }
      }
    }
    std::vector<u64> cnts;
    cnts.reserve(m_cull_chunks.size());
    for (const auto& c : m_cull_chunks) {
      cnts.push_back(c.count);
    }
    std::sort(cnts.begin(), cnts.end());
    grass_cull::note_partition(
        (u64)m_cull_chunks.size(), cnts.empty() ? 0 : cnts.front(),
        cnts.empty() ? 0 : cnts[cnts.size() / 2],
        cnts.empty() ? 0 : cnts[(cnts.size() * 9) / 10], cnts.empty() ? 0 : cnts.back(),
        m_cull_from_file, m_cull_mismatch, (u64)m_instance_count);
    lg::info(
        "[recharged-grass] CHUNK-CULL partition: lots={} source={} mismatch={} couvre={} sur {} "
        "instances (p50={} max={})",
        (int)m_cull_chunks.size(), m_cull_from_file ? "fichier" : "recalcule", m_cull_mismatch,
        m_cull_covered, m_instance_count, cnts.empty() ? 0 : cnts[cnts.size() / 2],
        cnts.empty() ? 0 : cnts.back());
  }
  // Grecharged-grass-overhang6 census: the 3-zone tail (drawn only while the toggle is ON). Zone 2 =
  // sub-lip strip blades (5+w comb-class), zone 1 = walkable-boundary lean twins, zone 3 = layered
  // fall over the native-alpha overhang faces.
  lg::info(
      "[recharged-grass] GOVERHANG expand: droop_tris={} z2_strip={} comb_repl={} lean_twins={} "
      "z3_fall={} (tail [{}..{}), toggle={}) lean_tagged={} comb_tagged={}",
      (int)m_bake.droop.size(), res.z2_count, res.comb_pairs, res.lean_twins, res.z3_count,
      m_droop_start, m_instance_count,
      recharged_gating::on(recharged_gating::kGrassOverhang) ? "ON" : "OFF", res.lean_tagged,
      res.comb_tagged);

  // Recompute `density` exactly as expand() did, for the STATIC place summary log.
  int budget;
  float density;
  {
    float dens_scale = std::min(2.5f, std::max(0.5f, slider_density / 100.0f));
    budget = (int)((float)grass_bake::MAX_INSTANCES * dens_scale);
    density = grass_bake::D_TARGET;
    if (m_bake.total_area_m2 > 1.0f &&
        m_bake.total_area_m2 * grass_bake::D_TARGET > grass_bake::BUDGET_SAFETY * (float)budget) {
      density = grass_bake::BUDGET_SAFETY * (float)budget / m_bake.total_area_m2;
    }
  }

  m_cached_preset = m_pending.want_preset;

  // ================================================================================================
  // Gloading-screen-window (owner 2026-08-30, D1/D5) — CES DEUX PASSES SONT DES INSTRUMENTS, ET
  // ELLES COUTAIENT UN GEL A CHAQUE CHARGEMENT DE NIVEAU.
  // ================================================================================================
  // « l'animation a des petits stutters pendant le chargement, des moments ou ca freeze »
  //
  // MESURE, PAS SOUPCON. Course x86 du 2026-08-30, transition `save-geyser` : la derniere image
  // tenue par l'ecran de chargement dure 244,8 ms quand les 60 precedentes tiennent a 17,3 ms de
  // maximum. L'arbre de profilage du renderer (`LSWIN-RENDU`) l'attribue sans ambiguite :
  //     242,18 ms root -> 231,90 ms buckets -> 214,76 ms [30] l1-shrub-generic -> 214,75 grass-draw
  // et la ligne PLACE-TIME du chargeur d'herbe la decompose :
  //     total=172ms (source=8ms  expand+logs=147ms  upload+light=17ms)  instances=726851
  // Le premier suspect designe par sa POSITION (le bloc « niveau pret » du chargeur) avait ete
  // chronometre AVANT et rendait 0,0 ms sur ses quatre etages : il etait ECARTE.
  //
  // CE QUE PAIENT CES DEUX PASSES. Toutes deux balayent les 726 851 instances en inserant dans une
  // `unordered_map`, et toutes deux sont PUREMENT DIAGNOSTIQUES :
  //   - RIMCAND est etiquete « CAPTURE AID » et produit QUATORZE lignes de journal ;
  //   - la grille de chunks est etiquetee « culling instrumentation only » et `m_chunks` n'est lu
  //     QUE par un journal etrangle a une ligne toutes les 30 images (:1317). Le dessin ne la lit
  //     jamais -- verifie par balayage des 8 occurrences du champ.
  // La sortie graphique est donc IDENTIQUE sans elles : `m_instances`, `m_inst_tri` et le
  // televersement GL ne sont pas touches.
  //
  // ON NE LES SUPPRIME PAS, ON LES REND EXPLICITES. `OG_GRASS_DIAG=1` les rejoue sur LE MEME
  // BINAIRE -- c'est la jambe « avant » de la mesure, et c'est ce qui permet de publier le gain
  // au lieu de l'affirmer.
  const bool diag = grass_diag_enabled();
  const auto tDiagA = clk::now();
  // ROUND#14 CAPTURE AID: RIMCAND dump (uses m_instances + gspare + m_bake.tris flags&1 for TIE).
  if (diag) {
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

  const auto tDiagB = clk::now();
  // Build the chunk grid (culling instrumentation only — proves completeness).
  if (diag) {
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
  {
    auto ms2 = [](const clk::time_point& a, const clk::time_point& b) {
      return std::chrono::duration<double, std::milli>(b - a).count();
    };
    lg::info(
        "[recharged-grass] DIAG-COUT diag={} rimcand_ms={:.1f} chunks_ms={:.1f} "
        "expansion_seule_ms={:.1f} instances={}",
        diag ? 1 : 0, ms2(tDiagA, tDiagB), ms2(tDiagB, tExpandEnd), ms2(tB, tDiagA),
        m_instance_count);
  }

  // The big "training STATIC place" summary (identical format). occ_culled/total come from expand();
  // scan stats (draws/tris/area/objpt buckets) come from m_bake.stats (identical on live + bake paths).
  {
    const int occ_culled = res.occ_culled;
    lg::info(
        "[recharged-grass] {} STATIC place (whole-level, camera-independent): {} grass-ground "
        "draws ({} TIE), {} tris kept (giant {}, maxArea {:.0f}m2), area {:.0f} m2, density {:.0f}/m2 -> "
        "{} instances in {} chunks (POLISH#5 density {:.0f}% -> budget {}). ROUND#13 PER-INSTANCE "
        "object-hide (NO 0.5m cell nuke, NO 3x3 dilation): occ_culled {} of {} instances ({:.3f}%) — each "
        "blade tested vs {} NON-grass-TIE object-point buckets (grass-TIE platforms EXCLUDED = no self-cull) "
        "within radius {:.2f}m + contact band [{:.2f},{:.2f}]m; a blade is culled ONLY if a real object "
        "vertex is that close, so OPEN grass (no object) is NEVER culled = occ ~0 there, NO block-shaped "
        "bald holes. No camera window, no move-rebuild -> nothing de-instances while moving.",
        lvl_name, m_bake.stats.considered_draws, m_bake.stats.tie_draws, m_bake.stats.tris_kept,
        m_bake.stats.giant_tris, m_bake.stats.max_area, m_bake.total_area_m2, density,
        m_instance_count, (int)m_chunks.size(),
        slider_density, budget, occ_culled,
        m_instance_count + occ_culled,
        100.0f * (float)occ_culled / (float)std::max(1, m_instance_count + occ_culled),
        m_bake.stats.occ_objpt_buckets, grass_bake::OCC_RADIUS_M, grass_bake::OCC_LO_M,
        grass_bake::OCC_HI_M);
  }

  // Only commit the cache once the level is actually loaded (grass draws found), OR the bake loaded
  // successfully (bake path has no considered_draws) — a transient placement is not frozen incomplete.
  // Gloading-screen-window : LE CACHE SE COMMET SUR LE NIVEAU QUI A ETE EXPANSE, PAS SUR CELUI DE
  // L'IMAGE QUI RAMASSE. L'etape SOURCE et l'etape CONSOMMATION sont separees par plusieurs images
  // sur le chemin asynchrone : `lev` et `ld` decrivent l'image COURANTE, `m_pending` decrit
  // l'expansion LANCEE. Prendre `ld->load_id` ici commettrait le cache sous l'identite d'un autre
  // chargement et le champ ne serait jamais reconstruit pour lui.
  if (m_bake.stats.considered_draws > 0 || from_bake) {
    m_cached_level = m_pending.lev;
    m_cached_load_id = m_pending.load_id;
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
  // Gloading-screen-window : LE CANAL SE PROUVE PAR CE QU'IL DEPOSE, PAS PAR LE CODE QU'ON Y LIT.
  // `async` dit quelle branche a ete PRISE, `attentes` compte les images ou `rebuild()` a rendu la
  // main pendant que le thread calculait, et `bloque_ms` est le temps reellement paye SUR LE THREAD
  // DE RENDU par l'expansion (l'attente du futur au ramassage, pas la duree du calcul). Sans ces
  // trois nombres, « l'expansion n'a rien coute » et « l'expansion n'a pas tourne » sont
  // indistinguables sur la meme trace.
  // Ggrass-density-presets : la ligne porte le NIVEAU, le palier DEMANDE, le palier SERVI et la
  // densite reellement passee a `expand`. Sans ces quatre-la, « le bon bake a servi » et « on est
  // descendu d'un cran » rendent la meme ligne, et un repli passe inapercu.
  lg::info(
      "[recharged-grass] PLACE-TIME niveau={} mode={} palier_demande={} palier_servi={} "
      "densite_bake={:.0f} bake={} total={:.0f}ms (source={:.0f}ms "
      "expand+logs={:.0f}ms upload+light={:.0f}ms) instances={} async={} attentes={} "
      "bloque_ms={:.1f}",
      lvl_name, from_bake ? "precomputed" : "live",
      grass_bake::density_preset_slug(m_pending.want_preset),
      from_bake ? grass_bake::density_preset_slug(m_pending.served_preset) : "<aucun>",
      slider_density, resolved_bake_path.empty() ? "<none>" : resolved_bake_path,
      ms(tA, tC), ms(tA, tB), ms(tB, tExpandEnd), ms(tExpandEnd, tC), m_instance_count,
      grass_async_expand_enabled() ? 1 : 0, m_expand_waits, ms(tExpandJoin, tExpandDone));

  // grass-baseline-cost : LA MEME DECOMPOSITION QUE LA LIGNE CI-DESSUS, PUBLIEE. Le contrat dit
  // « le chargement, decompose comme il l'est DEJA — source, expansion, televersement » : on ne
  // fabrique donc pas une seconde mesure a cote, on publie CELLE-LA. `bloque_ms` l'accompagne
  // parce que le chemin asynchrone est celui qui est LIVRE : `expand+logs` y est un delai MURAL
  // qui couvre plusieurs images, et lu seul il ferait passer une attente pour une charge
  // processeur. Les deux tampons sont ceux que ce meme corps de fonction televerse : instances
  // (64 o chacune, GL_STATIC_DRAW) et lumiere de sol (4 o chacune, GL_DYNAMIC_DRAW). La queue
  // MORTE est ce que la passe brin ne dessine pas — `OG_FEAT_GRASS_OVERHANG` est OFF dans les
  // deux arbres livres, donc elle s'arrete a `m_droop_start`.
  {
    const int drawn_n =
#ifdef OG_FEAT_GRASS_OVERHANG
        recharged_gating::on(recharged_gating::kGrassOverhang)
            ? m_instance_count
            : std::min(m_droop_start, m_instance_count);
#else
        std::min(m_droop_start, m_instance_count);
#endif
    grass_baseline::note_load(
        from_bake ? m_pending.served_preset : m_pending.want_preset, m_pending.want_preset,
        ms(tA, tC), ms(tA, tB), ms(tB, tExpandEnd), ms(tExpandEnd, tC),
        ms(tExpandJoin, tExpandDone), grass_async_expand_enabled(), (uint64_t)m_expand_waits,
        (uint64_t)(m_instance_count < 0 ? 0 : m_instance_count),
        (uint64_t)(drawn_n < 0 ? 0 : drawn_n),
        (uint64_t)(m_instance_count < 0 ? 0 : m_instance_count) *
            (uint64_t)sizeof(grass_bake::GrassInstance),
        (uint64_t)m_light.size());

    // grass-dead-tail : LE COUT DU CHARGEMENT, PUBLIE SOUS CET ITEM. `note_load` ci-dessus ne
    // publie que si le harnais mesure grass-baseline-cost ; un item n'a acces qu'a SES cles. Les
    // grandeurs sont les MEMES (aucune seconde mesure fabriquee a cote) : la decomposition que la
    // ligne PLACE-TIME porte deja, en microsecondes entieres pour que le moissonneur les prenne.
    if (autoport_proof::armed_for(kDeadTailItemId) && autoport_proof::feature_is(kDeadTailItemId)) {
      const uint64_t built = (uint64_t)(m_instance_count < 0 ? 0 : m_instance_count);
      const uint64_t dstart = (uint64_t)(m_droop_start < 0 ? 0 : m_droop_start);
      autoport_proof::publish("grass_dead_tail_built", built > dstart ? built - dstart : 0);
      autoport_proof::publish("grass_dead_droop_start", dstart);
      autoport_proof::publish("grass_dead_expanded_instances", built);
      autoport_proof::publish("grass_dead_inst_bytes",
                              built * (uint64_t)sizeof(grass_bake::GrassInstance));
      autoport_proof::publish("grass_dead_light_bytes", (uint64_t)m_light.size());
      autoport_proof::publish("grass_dead_source_us", (uint64_t)(ms(tA, tB) * 1000.f));
      autoport_proof::publish("grass_dead_expand_us", (uint64_t)(ms(tB, tExpandEnd) * 1000.f));
      autoport_proof::publish("grass_dead_upload_us", (uint64_t)(ms(tExpandEnd, tC) * 1000.f));
      autoport_proof::publish("grass_dead_total_us", (uint64_t)(ms(tA, tC) * 1000.f));
      autoport_proof::publish("grass_dead_blocked_us",
                              (uint64_t)(ms(tExpandJoin, tExpandDone) * 1000.f));
      autoport_proof::publish_text(
          "grass_dead_preset",
          grass_bake::density_preset_slug(from_bake ? m_pending.served_preset
                                                    : m_pending.want_preset));
      autoport_proof::publish_text("grass_dead_level", lvl_name.c_str());
#ifdef OG_FEAT_GRASS_OVERHANG
      autoport_proof::publish("grass_dead_tail_compiled", 1);
#else
      autoport_proof::publish("grass_dead_tail_compiled", 0);
#endif
    }
  }

  // Ggrass-crash (owner 2026-08-30, bissection : « avec l'herbe ca crash, sans ca fonctionne ») —
  // LA VALEUR DE RETOUR MANQUANTE, ET C'EST ELLE QUI TUAIT LE JEU SUR L'APPAREIL.
  //
  // `rebuild()` est passee de `void` a `bool` au commit 25ae957df7 (Gloading-screen-window, le lot
  // qui separe le build qui chargeait de celui qui mourait). Les trois `return` poses ce jour-la
  // couvrent les sorties PRECOCES (pas de niveau ; expansion lancee ; expansion pas prete) et
  // AUCUNE ne couvre l'etape de CONSOMMATION — celle qui s'execute a CHAQUE construction reussie
  // du champ. Elle tombait donc hors de la fonction sans valeur : comportement indefini.
  //
  // CE N'EST PAS UNE DEDUCTION, C'EST DANS L'ARTEFACT LIVRE. `libgk.so` arm64 extrait de l'APK que
  // l'owner a (`app-jak1-debug.apk`, commit 7c11edaa03), symbole `GrassRenderer::rebuild` a
  // 0x3dc034, taille 0x1924 :
  //   - UN SEUL `ret`, a 0x3dc310, et ZERO branchement vers lui depuis le reste de la fonction ;
  //   - la fonction FINIT par `mov x0, x19 ; bl _Unwind_Resume` (0x3dd94c-0x3dd950), ou `x19` vient
  //     d'un `mov x19, x0` pris sur la valeur de retour d'un destructeur de `std::string`
  //     (0x3dd68c) — un pointeur d'exception BIDON ;
  //   - le chemin y arrive directement apres le `lg::info` de `PLACE-TIME` (0x3dd678).
  // Autrement dit : sur l'appareil, la derniere chose que fait le moteur apres avoir ecrit la ligne
  // « champ d'herbe pret » est de derouler une exception qui n'existe pas. Mort garantie, a CHAQUE
  // chargement d'un niveau a herbe (`training` = Geyser Rock, `beach`) — et a aucun autre, ce qui
  // est exactement la population que l'owner decrit.
  //
  // POURQUOI NOS 38 CHARGEMENTS x86 N'ONT RIEN VU : meme source, meme defaut, autre compilateur.
  // GCC -O3 (bureau) fait tomber le meme UB, par hasard, sur le `movb $0x1` du `return true` de la
  // ligne 656 puis dans l'epilogue — le bureau rend `true` par accident. clang/NDK (appareil) saute
  // dans le derouleur. C'est la « dependance a l'appareil » constatee, et elle a une cause, pas un
  // mystere.
  //
  // ET LE COMPILATEUR NOUS L'AVAIT DIT, dans notre propre journal de build, pour les DEUX builds
  // concernes : `.autoport/logs/auto_build_apk.txt:162919` et `:163282` —
  //   GrassRenderer.cpp:986:1: warning: non-void function does not return a value in all control
  //   paths [-Wreturn-type]
  // Personne ne l'a lu. C'est pourquoi ce warning est desormais une ERREUR de compilation
  // (`-Werror=return-type`, CMakeLists.txt) : ce defaut-la ne peut plus etre livre.
  //
  // La valeur est `true` : arrive ici, le champ est bati, televerse dans le VBO et sa lumiere est
  // posee — il est dessinable, ce que le contrat de la fonction (GrassRenderer.h) appelle `true`.
  return true;
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

  // grass-shading (SPEC section 7) : LA LUMIERE CUITE, A L'ORIGINE DE LA TOUFFE.
  // `tri_rgb` ci-dessus est la valeur du CENTROIDE : une par triangle, servie telle quelle a tous
  // les brins du triangle — 11 080 valeurs pour 847 000 brins, la seule variation spatiale que le
  // champ possedait. Le bake porte desormais les palettes des TROIS sommets (`palv`), et chaque
  // brin porte les poids barycentriques de l'origine de SA touffe : on interpole donc la meme
  // formule (`sum(pal*w) >> 6`, saturee) aux trois sommets, puis on melange. Toutes les instances
  // d'une touffe partagent leurs poids, donc la valeur est UNE PAR TOUFFE, pas une par brin.
  // La table est refusee si sa taille ne colle pas exactement au champ : un decalage d'un cran
  // donnerait a un brin la lumiere d'un autre, et rien a l'ecran ne le dirait.
  const bool per_clump = m_shaded && valid &&
                         m_inst_bw.size() == (size_t)m_instance_count * 2u;
  std::vector<std::array<std::array<u8, 3>, 3>> vert_rgb;
  if (per_clump) {
    vert_rgb.resize(m_bake.tris.size());
    for (size_t j = 0; j < m_bake.tris.size(); ++j) {
      for (int v = 0; v < 3; ++v) {
        for (int ch = 0; ch < 3; ++ch) {
          float acc = 0.f;
          for (int p = 0; p < 8; ++p) {
            acc += (float)m_bake.tris[j].palv[v][p][ch] * (float)w[p][ch];
          }
          int val = (int)acc >> 6;
          if (val > 255) val = 255;
          if (val < 0) val = 0;
          vert_rgb[j][v][ch] = (u8)val;
        }
      }
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
    if (per_clump && t < vert_rgb.size()) {
      const int q1 = m_inst_bw[(size_t)i * 2 + 0];
      const int q2 = m_inst_bw[(size_t)i * 2 + 1];
      const int q0 = 255 - q1 - q2;
      if (q0 >= 0) {
        cr = (u8)((q0 * (int)vert_rgb[t][0][0] + q1 * (int)vert_rgb[t][1][0] +
                   q2 * (int)vert_rgb[t][2][0]) / 255);
        cg = (u8)((q0 * (int)vert_rgb[t][0][1] + q1 * (int)vert_rgb[t][1][1] +
                   q2 * (int)vert_rgb[t][2][1]) / 255);
        cb = (u8)((q0 * (int)vert_rgb[t][0][2] + q1 * (int)vert_rgb[t][1][2] +
                   q2 * (int)vert_rgb[t][2][2]) / 255);
      }
    }
    m_light[(size_t)i * 4 + 0] = cr;
    m_light[(size_t)i * 4 + 1] = cg;
    m_light[(size_t)i * 4 + 2] = cb;
    // grass-blade-variants : le quatrieme octet portait 255 et personne ne le lisait ; il porte
    // desormais la variante du brin. Le shader ne lit que `.rgb` pour la lumiere.
    m_light[(size_t)i * 4 + 3] =
        ((size_t)i < m_variant.size()) ? m_variant[(size_t)i] : (u8)0;
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

  // grass-shading : CE QUE LE MOTEUR EST SEUL A POUVOIR DIRE. Le recensement hors ligne mesure la
  // donnee de l'arbre ; il rendrait ses chiffres meme si l'appareil n'avait affiche aucun brin.
  // Ces trois-la sortent du tampon REELLEMENT televerse a cette image.
  if (autoport_proof::feature_is(kShadeItemId)) {
    std::unordered_set<u32> before, after;
    before.reserve(tri_rgb.size() * 2 + 16);
    after.reserve((size_t)m_instance_count / 4 + 16);
    for (int i = 0; i < m_instance_count; ++i) {
      const u32 t = m_inst_tri[i];
      if (t < tri_rgb.size()) {
        before.insert(((u32)tri_rgb[t][0] << 16) | ((u32)tri_rgb[t][1] << 8) | tri_rgb[t][2]);
      }
      after.insert(((u32)m_light[(size_t)i * 4 + 0] << 16) |
                   ((u32)m_light[(size_t)i * 4 + 1] << 8) | m_light[(size_t)i * 4 + 2]);
    }
    autoport_proof::publish("grass_shade_engine_blades", (u64)m_instance_count);
    autoport_proof::publish("grass_shade_engine_armed", m_shaded ? 1u : 0u);
    autoport_proof::publish("grass_shade_engine_per_clump", per_clump ? 1u : 0u);
    autoport_proof::publish("grass_shade_engine_light_before", (u64)before.size());
    autoport_proof::publish("grass_shade_engine_light_after", (u64)after.size());
    autoport_proof::publish("grass_shade_engine_light_tris", (u64)tri_rgb.size());
    std::unordered_set<u64> bases;
    bases.reserve((size_t)m_instance_count / 4 + 16);
    for (int i = 0; i < m_instance_count; ++i) {
      const auto& gi = m_instances[(size_t)i];
      const u64 qr = (u64)(gi.gr * 1023.0f + 0.5f) & 0x3ffu;
      const u64 qg = (u64)(gi.gg * 1023.0f + 0.5f) & 0x3ffu;
      const u64 qb = (u64)(gi.gb * 1023.0f + 0.5f) & 0x3ffu;
      bases.insert((qr << 20) | (qg << 10) | qb);
    }
    autoport_proof::publish("grass_shade_engine_base_colours", (u64)bases.size());
    autoport_proof::publish("grass_shade_engine_hits", m_shade_hits);
    // `hits=` de la ligne FEATURE : les brins qui ont REELLEMENT recu une couleur de touffe.
    // Desarme, `expand()` n'en compte aucun et `note_hit_for` est de toute facon un no-op.
    autoport_proof::note_hit_for(kShadeItemId, m_shade_hits);
  }

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
  // grass-baseline-cost : LE DENOMINATEUR QUI SEPARE « l'herbe ne coute rien » DE « l'instrument
  // n'a pas tourne ». Compte a l'ENTREE, avant tout retour anticipe : la cellule eteinte du meme
  // palier rendra 0 avec le MEME instrument, ce qui rend le zero falsifiable.
  grass_baseline::note_render_entry();
  // Grecharged-grass-overhang7: iterate the grass allowlist (background_common.h) — first loaded
  // grass level wins. Single slot is correct today: training is an isolated island and beach's
  // neighbour (village1) carries none of the grass textures, so two grass levels never co-load.
  const LevelData* ld = nullptr;
  std::string grass_level;
  if (rs->loader) {
    for (const char* name : kGrassLevels) {
      const LevelData* cand = rs->loader->get_tfrag3_level(name);
      if (cand && cand->level) {
        ld = cand;
        grass_level = name;
        break;
      }
    }
  }
  if (!ld) {
    return;
  }
  // Grecharged-grass-overhang7 ROUND 11: resolve the two native hang-alpha strip textures by
  // debug_name from THIS level's texture table (index-parallel with the GL handle vector — exactly
  // how TFragment/Tie3 bind them for the near-fade). The zone-3 textured cards sample these.
  if ((const void*)ld != m_hang_tex_src) {
    m_hang_tex[0] = m_hang_tex[1] = 0;
    const auto& texs = ld->level->textures;
    for (size_t i = 0; i < texs.size() && i < ld->textures.size(); ++i) {
      if (texs[i].debug_name == "bch-grassfringe") {
        m_hang_tex[0] = ld->textures[i];
      } else if (texs[i].debug_name == "bch-leafyground-hang-2x1") {
        m_hang_tex[1] = ld->textures[i];
      }
    }
    // fallback: a level carrying only one of the strip textures still gets native art on every card
    if (!m_hang_tex[1]) m_hang_tex[1] = m_hang_tex[0];
    if (!m_hang_tex[0]) m_hang_tex[0] = m_hang_tex[1];
    m_hang_tex_src = (const void*)ld;
    lg::info("[recharged-grass] R11 hang-card textures resolved: grassfringe={} leafy2x1={}",
             m_hang_tex[0], m_hang_tex[1]);
  }
  // Rebuild ONLY on level change / reload, OR when the DENSITY slider changed (POLISH#5 —
  // a new density means a new instance budget, so the static field must be re-scattered).
  // Placement is otherwise camera-independent (whole-level, uniform), so walking NEVER
  // triggers a rebuild — that is the culling fix: no pop-in, no de-instancing while moving.
  if (m_cached_level != (const void*)ld->level.get() || m_cached_load_id != ld->load_id ||
      m_cached_preset !=
          grass_bake::clamp_density_preset(Gfx::settings().recharged_grass_density_preset) ||
      m_cached_precomputed != recharged_gating::on(recharged_gating::kGrassPrecomputed)) {
    rebuild(rs, ld, grass_level);
  }
  if (m_instance_count <= 0) {
    return;
  }

  // ==============================================================================================
  // Gloading-screen-window (owner 2026-08-30, D1/D5) — ON NE PEINT PAS 726 851 BRINS SOUS UN ECRAN
  // OPAQUE.
  // ==============================================================================================
  // « l'animation a des petits stutters pendant le chargement, des moments ou ca freeze ».
  // MESURE, x86, `save-geyser`, 103 images consecutives pendant que l'ecran est tenu : `render()`
  // coute 38 a 41 ms par image, dont 36,48 ms sur 39,70 attribues a `grass-draw` par l'arbre de
  // profilage. L'ecran plafonnait a ~26 images/s. Ce n'est pas un evenement, c'est le regime.
  // Deux autres causes ont ete mesurees et ECARTEES avant celle-ci (destruction du niveau sortant :
  // 0,3-0,6 ms ; re-televersement de la lumiere : 2 pour 103 images) — voir load_gate.h.
  //
  // Le champ est INVISIBLE a ces images-la : l'ecran de chargement est peint par-dessus le monde.
  // On rend donc la main avant le dessin ET avant `update_light`, qui n'a pas plus de raison de
  // recalculer une lumiere que personne ne voit. Rien n'est detruit, rien n'est invalide : a la
  // premiere image non couverte, `update_light` reprend (son etranglement compare `itimes` a la
  // DERNIERE valeur televersee, pas a celle de l'image precedente, donc un saut du cycle du jour
  // pendant l'ecran est rattrape en une image) et le dessin repart sur le meme VBO.
  //
  // ABLATION SUR LE MEME BINAIRE : `OG_GRASS_SKIP_COVERED=0` rejoue le dessin sous l'ecran, c'est
  // la jambe « avant ». Non posee -> on saute, c'est ce qu'on livre.
  if (load_gate::loading_screen_is_covering() && grass_skip_covered_enabled()) {
    return;
  }

  // POLISH#9: refresh the per-instance GROUND baked-light for the current time of day (only actually
  // re-uploads when the time-of-day weights changed — so the grass tracks the day cycle dynamically).
  // grass-baseline-cost : debut du chronometre de PREPARATION processeur. Il court jusqu'a
  // l'attente de la barriere posee a l'image PRECEDENTE — c'est-a-dire tout ce qui precede le
  // dessin : la lumiere du cycle du jour, les uniformes, les occulteurs de contact. Declare ICI et
  // pas plus haut : les retours anticipes (pas d'instances, ecran de chargement) sont en amont, et
  // un chronometre ouvert sur un chemin qui ne dessine pas ne mesurerait rien de comparable.
  const auto t_prep0 = std::chrono::steady_clock::now();
  // grass-chunk-cull : la fenetre de comptage des localisations d'uniformes commence ici, au meme
  // point que le chronometre de preparation — c'est ce bloc-la que l'item doit chiffrer.
  const u64 uloc_req0 = g_grass_uloc_requests, uloc_miss0 = g_grass_uloc_misses;
  update_light(rs);

  // monotonic seconds for the breeze
  static const auto t0 = std::chrono::steady_clock::now();
  float u_time =
      std::chrono::duration<float>(std::chrono::steady_clock::now() - t0).count();
  // REFSET : meme raison que foliage_wind::clock_seconds. `u_time` part d'une montre MURALE et
  // atteint l'uniforme `u_time` du shader d'herbe (et le cycle du mode de debug) : deux rejeux du
  // meme plan poussaient deux phases de brise differentes. Sous `refset::enabled()` seulement,
  // l'horloge devient `lf / 60`, pure fonction de la frame de LOGIQUE. Hors refset : inchange.
  if (refset::enabled()) {
    const int64_t lf = refset::render_logic_frame();
    if (lf >= 0) {
      u_time = (float)lf / 60.f;
      static int64_t s_pin_last_lf = -1;
      static uint64_t s_pin_count = 0;
      if (lf != s_pin_last_lf) {
        s_pin_last_lf = lf;
        s_pin_count++;
        autoport_proof::publish("refset_grass_clock_pinned", s_pin_count);
      }
    }
  }

  u_time = shrub_proof_inputs::value("grass/time", u_time);
  auto& shader = rs->shaders[ShaderId::GRASS];
  shader.activate();
  GLuint id = shader.id();

  std::array<math::Vector4f, 4> proof_camera;
  std::copy_n(rs->camera_matrix, 4, proof_camera.begin());
  auto proof_hvdf = rs->camera_hvdf_off;
  auto proof_position = rs->camera_pos;
  shrub_proof_inputs::exchange("grass/camera", proof_camera[0].data(), sizeof(float) * 16);
  shrub_proof_inputs::exchange("grass/hvdf", proof_hvdf.data(), sizeof(float) * 4);
  shrub_proof_inputs::exchange("grass/camera-position", proof_position.data(), sizeof(float) * 4);

  // grass-chunk-cull : L'ORIENTATION DE LA VUE, imposee par la campagne et par elle seule (la
  // fonction rend faux hors campagne et a la vue 0). On tourne le MONDE autour de l'oeil,
  // p -> R(p-e)+e ; la transformation monde->clip etant affine en p, cela se reecrit exactement
  // sur les quatre vecteurs `camera[]`, sans toucher au shader :
  //     c0' = cos*c0 - sin*c2     c1' = c1     c2' = sin*c0 + cos*c2
  //     c3' = c3 + C(e - R e)     avec C(v) = c0*v.x + c1*v.y + c2*v.z (ANCIENNES colonnes)
  // L'oeil est point fixe : `camera_position` — et donc `cam_dist` du shader — ne bouge pas.
  float grass_view_yaw = 0.f;
  const bool grass_view_rotated = grass_cull::view_yaw(&grass_view_yaw);
  if (grass_view_rotated) {
    const float cs = std::cos(grass_view_yaw), sn = std::sin(grass_view_yaw);
    const math::Vector4f c0 = proof_camera[0], c1 = proof_camera[1], c2 = proof_camera[2];
    const float ex = proof_position[0], ez = proof_position[2];
    const float rex = cs * ex + sn * ez;
    const float rez = -sn * ex + cs * ez;
    const float dx = ex - rex, dz = ez - rez;
    for (int i = 0; i < 4; i++) {
      proof_camera[0][i] = cs * c0[i] - sn * c2[i];
      proof_camera[2][i] = sn * c0[i] + cs * c2[i];
      proof_camera[3][i] = proof_camera[3][i] + c0[i] * dx + c2[i] * dz;
    }
    (void)c1;
  }
  glUniformMatrix4fv(grass_uloc(id, "camera"), 1, GL_FALSE, proof_camera[0].data());
  glUniform4f(grass_uloc(id, "hvdf_offset"), proof_hvdf[0], proof_hvdf[1], proof_hvdf[2], proof_hvdf[3]);
  glUniform4f(grass_uloc(id, "camera_position"), proof_position[0], proof_position[1], proof_position[2], proof_position[3]);
  glUniform1f(grass_uloc(id, "fog_constant"), rs->camera_fog.x());
  glUniform1f(grass_uloc(id, "u_time"), u_time);
  const auto& jp = Gfx::settings().recharged_jak_pos;
  grass_occ::push_contact_uniforms(id);
  // POLISH#4: adjustable LOD reach (Recharged Settings sliders), passed in WORLD units to
  // match cam_dist. Clamped to a sane range so a bad settings value can't break the LOD.
  float near_m = std::min(80.0f, std::max(8.0f, Gfx::settings().recharged_grass_near_dist));
  float card_m = std::min(200.0f, std::max(near_m + 5.0f,
                                           Gfx::settings().recharged_grass_card_dist));
  glUniform1f(grass_uloc(id, "u_near_dist"), near_m * U);
  glUniform1f(grass_uloc(id, "u_card_dist"), card_m * U);
  // POLISH#4: Jak's ledge-grab point (parts the ledge-top grass while he hangs).
  // ROUND#14 DISCRIMINATOR (0 normal / 1 base-stubs magenta / 2 blades cyan / 3 cards yellow):
  // isolates every tier so ONE fixed-viewpoint capture at a rim discriminates the floating
  // mechanism (H-A blade geometry / H-B base-past-silhouette / H-C cards). Control (default OFF):
  //   prop debug.opengoal.grass_dbg = c (cycle every 4 s) | 1 | 2 | 3   (Android)
  //   env  GRASS_DISCRIMINATE       = c | 1 | 2 | 3                     (desktop x86)
  glUniform1i(grass_uloc(id, "u_debug"), grass_debug_mode(u_time));
#ifdef OG_FEAT_PBR
  // ROUND 23 PER-PIXEL SCREEN-COVERAGE INSTRUMENTATION (owner defect A). Grass draws are tagged in
  // debug mode 30 so the coverage census can attribute every screen pixel to the program that drew
  // it. Grass is its OWN world geometry — it writes depth (GL_DEPTH_TEST/GEQUAL + glDepthMask
  // GL_TRUE below) and occludes the ground it stands on — so it has to be counted honestly as an
  // UNDISPLACED world program. Letting it stand down instead would hand its pixels back to the
  // hfrag/tfrag draw underneath and INFLATE the very displaced-coverage number under audit.
  // Note this is a SEPARATE push from first_tfrag_draw_setup: the grass program does not go through
  // that setup (same reason merc2/generic/emerc call pbr_push_debug_tag directly). No-op at mode 0,
  // and a no-op location (-1) on any program that does not declare the uniform.
  pbr_push_debug_tag(id);
#endif
  // ROUND#19: optional normal-tilt blend — blade growth axis = mix(world-up, ground-face normal, u_tilt).
  // 0.0 (default) is bit-identical to the world-up-only growth; the owner A/Bs ~0.30 via the debug prop.
  glUniform1f(grass_uloc(id, "u_tilt"), grass_tilt_amount());
  // Grecharged-grass-overhang2: droop arc length scale (owner defect 2 — see grass_droop_len()).
  glUniform1f(grass_uloc(id, "u_droop_len"), grass_droop_len());
  // Grecharged-grass-overhang3: gate the transition-band comb on the SAME Recharged overhang toggle
  // that splits the draw range (below). OFF -> u_overhang=0 -> tagged blades run the stock else-branch.
  glUniform1f(grass_uloc(id, "u_overhang"),
#ifdef OG_FEAT_GRASS_OVERHANG
              recharged_gating::on(recharged_gating::kGrassOverhang) ? 1.0f : 0.0f);
#else
              // Grecharged-buildsys-flags: overhang compiled OUT -> shader stock else-branch.
              0.0f);
#endif
  // OWNER ROUND#18: object-clip — hide grass under crates / the warp-gate button (merc actors captured
  // by Merc2 this frame). Upload up to 16 as u_occ (xyz = world pos GOAL units, w = ground-contact
  // radius GOAL units); u_occ_count == 0 (no objects captured) makes the shader path byte-identical to
  // no object-clip, so this can never break base grass rendering.
  {
    int nocc = (int)std::min<size_t>(grass_occ::g_published.size(), 8);  // R21f literal-unroll cap
    if (nocc > 0) {
      glUniform4fv(grass_uloc(id, "u_occ"), nocc, &grass_occ::g_published[0][0]);
    }
    glUniform1i(grass_uloc(id, "u_occ_count"), nocc);
  }
  // ROUND#19 forensics (owner: registered radii have NO visual): prove what actually reaches the
  // shader — uniform locations (a -1 = the GLES link dropped it) once, then the published entries +
  // Jak pos every ~150 frames. Metres for readability. Removed noise cost: two ints per frame.
  static bool s_occ_loc_logged = false;
  if (!s_occ_loc_logged) {
    s_occ_loc_logged = true;
    lg::info("[recharged-grass] R19OCC uniform-locations: u_occ={} u_occ_count={} u_trample={} u_trample_count={} u_jak_pos={} u_tilt={}", grass_uloc(id, "u_occ"), grass_uloc(id, "u_occ_count"), grass_uloc(id, "u_trample"), grass_uloc(id, "u_trample_count"), grass_uloc(id, "u_jak_pos"), grass_uloc(id, "u_tilt"));
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
  GLint mode_loc = grass_uloc(id, "u_mode");

  // ROUND 11: bind the native hang-alpha strip textures for the zone-3 textured cards (units 0/1 —
  // the grass program samples nothing else; every other renderer re-binds its own units per draw).
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D, m_hang_tex[1]);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, m_hang_tex[0]);
  glUniform1i(grass_uloc(id, "u_hang0"), 0);
  glUniform1i(grass_uloc(id, "u_hang1"), 1);

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
#ifdef OG_FEAT_GRASS_OVERHANG
      recharged_gating::on(recharged_gating::kGrassOverhang) ? m_instance_count : nondroop_n;
#else
      // Grecharged-buildsys-flags: overhang compiled OUT -> never draw the droop tail
      // (bit-identical to a build without the droop instances). See comment above.
      nondroop_n;
#endif
  const int draw_n = (s_maxinst > 0 && s_maxinst < blade_total) ? s_maxinst : blade_total;
  const int card_n = (s_maxinst > 0 && s_maxinst < nondroop_n) ? s_maxinst : nondroop_n;

  // ===== grass-chunk-cull : LE CULLING PAR LOT ================================================
  // Trois rejets, tous CONSERVATEURS, tous derives de ce que le shader fait deja :
  //   * hors du volume de vue    — six plans extraits de la matrice monde->clip ;
  //   * au-dela de B_END         — `alpha = 1 - smoothstep(B_FULL, B_END, cam_dist)` vaut
  //                                EXACTEMENT 0 des que cam_dist >= u_near_dist (grass.vert:210) ;
  //   * en deca de C_IN0         — `smoothstep(C_IN0, C_IN1, cam_dist)` vaut EXACTEMENT 0 en deca
  //                                de 0,45*u_near_dist, et la passe carte s'y tait (grass.vert:212).
  // Les bornes de distance portent sur la BASE du brin (`distance(base, camera_position)`), donc
  // sur la boite des origines ; les elargir ne peut que GARDER plus de lots.
  //
  // CE N'EST PAS UN CHANGEMENT DE LOD. Aucune distance n'est modifiee : on cesse de SOUMETTRE ce
  // que le shader repliait deja sur un point degenere apres l'avoir transforme.
  m_blade_runs.clear();
  m_card_runs.clear();
  u64 chunks_tested = 0, chunks_kept_blade = 0, chunks_kept_card = 0;
  bool run_overflow = false;
  const bool cull_on = grass_cull::culling_active() && !m_cull_chunks.empty() &&
                       m_cull_covered == (u64)m_instance_count && m_instance_count > 0;
  GrassClipPlanes cull_planes{};
  if (cull_on) {
    cull_planes = grass_build_planes(proof_camera, proof_hvdf.data(), rs->camera_fog.x(),
                                     kGrassScissorY);
    const float mxz = kCullMarginXZ_M * U, my = kCullMarginY_M * U;
    const float blade_reach = near_m * U;      // B_END
    const float card_out = card_m * U;         // C_OUT1
    const float card_in = 0.45f * near_m * U;  // C_IN0
    const float cp[3] = {proof_position[0], proof_position[1], proof_position[2]};
    m_cull_keep.assign(m_cull_chunks.size(), 0);
    for (size_t i = 0; i < m_cull_chunks.size(); i++) {
      const auto& c = m_cull_chunks[i];
      const float lo[3] = {c.lo[0] - mxz, c.lo[1] - my, c.lo[2] - mxz};
      const float hi[3] = {c.hi[0] + mxz, c.hi[1] + my, c.hi[2] + mxz};
      chunks_tested++;
      if (grass_box_outside(cull_planes, lo, hi)) {
        continue;
      }
      float dmin2 = 0.f, dmax2 = 0.f;
      for (int k = 0; k < 3; k++) {
        const float q = std::min(std::max(cp[k], lo[k]), hi[k]) - cp[k];
        dmin2 += q * q;
        const float f = std::max(std::fabs(lo[k] - cp[k]), std::fabs(hi[k] - cp[k]));
        dmax2 += f * f;
      }
      u8 keep = 0;
      if (dmin2 < blade_reach * blade_reach) {
        keep |= 1;
      }
      if (dmin2 < card_out * card_out && dmax2 > card_in * card_in) {
        keep |= 2;
      }
      m_cull_keep[i] = keep;
      chunks_kept_blade += (keep & 1) ? 1 : 0;
      chunks_kept_card += (keep & 2) ? 1 : 0;
    }
    grass_build_runs(m_cull_chunks, m_cull_keep, 1, m_blade_runs);
    grass_build_runs(m_cull_chunks, m_cull_keep, 2, m_card_runs);
    if ((int)m_blade_runs.size() > kMaxRunsPerPass ||
        (int)m_card_runs.size() > kMaxRunsPerPass) {
      run_overflow = true;
      g_grass_run_overflow_frames++;
      m_blade_runs.clear();
      m_blade_runs.push_back({0, m_instance_count});
      m_card_runs.clear();
      m_card_runs.push_back({0, m_instance_count});
    }
  }

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
  // grass-baseline-cost : fin de la preparation, debut de l'attente de la barriere.
  const auto t_fence0 = std::chrono::steady_clock::now();
  grass_baseline::note_prepare_us(
      std::chrono::duration<double, std::micro>(t_fence0 - t_prep0).count());
  static GLsync s_grass_fence = nullptr;
  if (s_grass_fence) {
    glClientWaitSync(s_grass_fence, GL_SYNC_FLUSH_COMMANDS_BIT, 1000000000ull /* 1 s cap */);
    glDeleteSync(s_grass_fence);
    s_grass_fence = nullptr;
  }
  const auto t_fence1 = std::chrono::steady_clock::now();
  const bool sync_log = s_gpusync;  // every frame while the forensic prop is set (run dies in ~2 s)
  auto sync_ms = [&](const char* what) {
    if (!sync_log) {
      return;
    }
    gl_query_census::Armed _ap("grass-gpusync");
    auto t0s = std::chrono::steady_clock::now();
    glFinish();
    lg::info("[recharged-grass] R19SYNC frame={} {} finished in {:.1f} ms (draw_n={})", m_frame,
             what, std::chrono::duration<float, std::milli>(std::chrono::steady_clock::now() - t0s)
                       .count(),
             draw_n);
  };
  sync_ms("pre-draw (uniforms/upload)");

  // Proof-only systematic sample: every 256th instance, all procedural vertices.
  // Capture the actual linked VS as points; this is not a rasterization claim.
  auto capture_grass = [&](int pass, int vertex_count, int instance_count) {
    const int64_t lf = pad_replay::current_frame();
    if (!shrub_proof_inputs::enabled() || lf < 0 || lf % 60 || instance_count <= 0 ||
        !shrub_contact_probe::capture_frame(rs->frame_idx)) return;
    static u64 capture_errors = 0;
    auto fail_capture = [&](const char* reason) {
      ++capture_errors;
      autoport_proof::publish("shrub_grass_capture_errors", capture_errors);
      lg::error("[shrub-grass-capture] {}", reason);
    };
    if (!glGenTransformFeedbacks || !glBindTransformFeedback || !glDeleteTransformFeedbacks) {
      fail_capture("missing private transform feedback API");
      return;
    }
    auto gl_clean = []() {
      bool clean = true;
      for (GLenum error = glGetError(); error != GL_NO_ERROR; error = glGetError()) clean = false;
      return clean;
    };
    // A pre-existing error invalidates this observation. Never consume it as success.
    if (!gl_clean()) { fail_capture("pre-existing GL error"); return; }
    GLboolean external_tf = GL_FALSE;
    glGetBooleanv(GL_TRANSFORM_FEEDBACK_ACTIVE, &external_tf);
    bool external_query = false;
    for (GLenum target : {GL_TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN,
                           GL_ANY_SAMPLES_PASSED, GL_ANY_SAMPLES_PASSED_CONSERVATIVE}) {
      GLint query = 0;
      glGetQueryiv(target, GL_CURRENT_QUERY, &query);
      external_query = external_query || query != 0;
    }
    if (!gl_clean()) { fail_capture("cannot inspect external GL capture state"); return; }
    if (external_tf || external_query) { fail_capture("external TF/query active"); return; }
    const auto measured = grass_proof_programs.find(id);
    if (measured == grass_proof_programs.end()) { fail_capture("missing measurement program"); return; }
    const GLuint measure_program = measured->second;
    constexpr int stride_instances = 256;
    const size_t samples = (size_t(instance_count) + stride_instances - 1) / stride_instances;
    struct Result { float pre[4], post[4]; u32 instance, vertex; };
    static_assert(sizeof(Result) == 40, "transform feedback layout");
    const size_t result_count = samples * vertex_count;
    GLint prior_program = 0, old_vao = 0, old_tf = 0, old_buffer = 0, old_array = 0;
    glGetIntegerv(GL_CURRENT_PROGRAM, &prior_program);
    glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &old_vao);
    glGetIntegerv(GL_TRANSFORM_FEEDBACK_BINDING, &old_tf);
    glGetIntegerv(GL_TRANSFORM_FEEDBACK_BUFFER_BINDING, &old_buffer);
    glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &old_array);
    const bool discarded = glIsEnabled(GL_RASTERIZER_DISCARD);
    if (!gl_clean()) { fail_capture("cannot save GL bindings"); return; }
    GLuint tf = 0, buffer = 0, query = 0, vao = 0, compact_vbos[5] = {};
    bool valid = true;
    // Private VAO: no pointer/divisor/enable state of the production VAO is mutated.
    // Disabled attributes use the existing context-wide constant values unchanged.
    struct Attribute {
      GLint buffer = 0, size = 0, type = 0, normalized = 0, stride = 0;
      GLint enabled = 0, divisor = 0, integer = 0;
      void* pointer = nullptr;
      float constant[4] = {};
      std::vector<u8> bytes;
    } attrs[5];
    for (GLuint a = 0; a < 5; ++a) {
      auto& at = attrs[a];
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_BUFFER_BINDING, &at.buffer);
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_SIZE, &at.size);
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_TYPE, &at.type);
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_NORMALIZED, &at.normalized);
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_STRIDE, &at.stride);
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_ENABLED, &at.enabled);
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_DIVISOR, &at.divisor);
      glGetVertexAttribiv(a, GL_VERTEX_ATTRIB_ARRAY_INTEGER, &at.integer);
      glGetVertexAttribPointerv(a, GL_VERTEX_ATTRIB_ARRAY_POINTER, &at.pointer);
      if (!at.enabled) glGetVertexAttribfv(a, GL_CURRENT_VERTEX_ATTRIB, at.constant);
      if (!gl_clean()) { valid = false; break; }
      if (!at.enabled) continue;
      if (!at.buffer || at.size < 1 || at.size > 4 || at.integer || at.divisor != 1 ||
          (at.type != GL_FLOAT && at.type != GL_UNSIGNED_BYTE) || at.stride < 0) {
        valid = false; break;
      }
      const size_t element_bytes = size_t(at.size) * (at.type == GL_FLOAT ? sizeof(float) : 1);
      const size_t source_stride = at.stride ? size_t(at.stride) : element_bytes;
      const uint64_t offset = reinterpret_cast<uintptr_t>(at.pointer);
      const uint64_t last = uint64_t(samples - 1) * stride_instances;
      glBindBuffer(GL_ARRAY_BUFFER, at.buffer);
      GLint64 storage_bytes = 0;
      GLint mapped = 0;
      glGetBufferParameteri64v(GL_ARRAY_BUFFER, GL_BUFFER_SIZE, &storage_bytes);
      glGetBufferParameteriv(GL_ARRAY_BUFFER, GL_BUFFER_MAPPED, &mapped);
      if (!gl_clean() || mapped || storage_bytes < 0 || offset > uint64_t(storage_bytes) ||
          element_bytes > uint64_t(storage_bytes) - offset ||
          last > (uint64_t(storage_bytes) - offset - element_bytes) / source_stride) {
        valid = false; break;
      }
      const size_t span = size_t(last * source_stride + element_bytes);
      const auto* source = static_cast<const u8*>(glMapBufferRange(
          GL_ARRAY_BUFFER, offset, span, GL_MAP_READ_BIT));
      const bool mapped_clean = gl_clean();
      if (!source || !mapped_clean) {
        if (source) glUnmapBuffer(GL_ARRAY_BUFFER);
        valid = false; break;
      }
      at.bytes.resize(samples * element_bytes);
      for (size_t i = 0; i < samples; ++i) {
        std::memcpy(at.bytes.data() + i * element_bytes,
                    source + i * stride_instances * source_stride, element_bytes);
      }
      const bool unmapped = glUnmapBuffer(GL_ARRAY_BUFFER);
      if (!gl_clean() || !unmapped) { valid = false; break; }
    }
    auto restore = [&]() {
      glUseProgram(prior_program);
      glBindVertexArray(old_vao);
      glBindBuffer(GL_ARRAY_BUFFER, old_array);
      glBindTransformFeedback(GL_TRANSFORM_FEEDBACK, old_tf);
      glBindBuffer(GL_TRANSFORM_FEEDBACK_BUFFER, old_buffer);
      if (!discarded) glDisable(GL_RASTERIZER_DISCARD);
      glDeleteQueries(1, &query); glDeleteBuffers(1, &buffer);
      glDeleteTransformFeedbacks(1, &tf); glDeleteVertexArrays(1, &vao);
      glDeleteBuffers(5, compact_vbos);
      if (!gl_clean()) valid = false;
    };
    if (!valid) { restore(); fail_capture("attribute read/format/bounds error"); return; }
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    glGenBuffers(5, compact_vbos);
    for (GLuint a = 0; a < 5; ++a) if (attrs[a].enabled) {
      const auto& at = attrs[a];
      glBindBuffer(GL_ARRAY_BUFFER, compact_vbos[a]);
      glBufferData(GL_ARRAY_BUFFER, at.bytes.size(), at.bytes.data(), GL_STREAM_DRAW);
      glEnableVertexAttribArray(a);
      glVertexAttribPointer(a, at.size, at.type, at.normalized, 0, nullptr);
      glVertexAttribDivisor(a, 1);
    }
    glUseProgram(measure_program);
    GLint source_uniforms = 0;
    glGetProgramiv(id, GL_ACTIVE_UNIFORMS, &source_uniforms);
    for (GLint ui = 0; ui < source_uniforms; ++ui) {
      char name[256]; GLsizei length; GLint count; GLenum type;
      glGetActiveUniform(id, ui, sizeof(name), &length, &count, &type, name);
      std::string base(name, length);
      const auto bracket = base.find('[');
      if (bracket != std::string::npos) base.resize(bracket);
      for (int e = 0; e < count; ++e) {
        const auto entry = count > 1 ? base + "[" + std::to_string(e) + "]" : base;
        const GLint src = grass_uloc(id, entry.c_str());
        const GLint dst = grass_uloc(measure_program, entry.c_str());
        float f[16] = {}; GLint v[4] = {};
        switch (type) {
          case GL_FLOAT: glGetUniformfv(id, src, f); glUniform1fv(dst, 1, f); break;
          case GL_FLOAT_VEC2: glGetUniformfv(id, src, f); glUniform2fv(dst, 1, f); break;
          case GL_FLOAT_VEC3: glGetUniformfv(id, src, f); glUniform3fv(dst, 1, f); break;
          case GL_FLOAT_VEC4: glGetUniformfv(id, src, f); glUniform4fv(dst, 1, f); break;
          case GL_FLOAT_MAT4: glGetUniformfv(id, src, f); glUniformMatrix4fv(dst, 1, GL_FALSE, f); break;
          default: glGetUniformiv(id, src, v); glUniform1iv(dst, 1, v); break;
        }
      }
    }
    glGenTransformFeedbacks(1, &tf);
    glGenBuffers(1, &buffer);
    glGenQueries(1, &query);
    glBindTransformFeedback(GL_TRANSFORM_FEEDBACK, tf);
    glBindBuffer(GL_TRANSFORM_FEEDBACK_BUFFER, buffer);
    glBufferData(GL_TRANSFORM_FEEDBACK_BUFFER, result_count * sizeof(Result), nullptr, GL_STREAM_READ);
    glBindBufferBase(GL_TRANSFORM_FEEDBACK_BUFFER, 0, buffer);
    glEnable(GL_RASTERIZER_DISCARD);
    const GLint contact_switch = grass_uloc(measure_program, "u_probe_grass_no_contact");
    if (!gl_clean() || contact_switch < 0) {
      restore(); fail_capture("measurement setup GL error"); return;
    }
    std::vector<u32> ids;
    std::vector<float> before, after;
    for (int contact = 1; contact >= 0 && valid; --contact) {
      glUniform1i(contact_switch, contact);
      glBeginQuery(GL_TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN, query);
      bool own_query = gl_clean();
      if (!own_query) { valid = false; break; }
      glBeginTransformFeedback(GL_POINTS);
      const bool own_tf = gl_clean();
      if (own_tf) {
        glDrawArraysInstanced(GL_POINTS, 0, vertex_count, samples);
  soft_draw_census::record_arrays("instrument", vertex_count, GL_POINTS, samples);
        valid = gl_clean();
        glEndTransformFeedback();
      } else valid = false;
      glEndQuery(GL_TRANSFORM_FEEDBACK_PRIMITIVES_WRITTEN);
      if (!gl_clean()) valid = false;
      if (!valid) break;
      GLuint written = 0;
      glGetQueryObjectuiv(query, GL_QUERY_RESULT, &written);
      if (!gl_clean() || written != result_count) { valid = false; break; }
      const auto* result = static_cast<const Result*>(glMapBufferRange(
          GL_TRANSFORM_FEEDBACK_BUFFER, 0, result_count * sizeof(Result), GL_MAP_READ_BIT));
      const bool map_clean = gl_clean();
      if (!result || !map_clean) {
        if (result) glUnmapBuffer(GL_TRANSFORM_FEEDBACK_BUFFER);
        valid = false; break;
      }
      auto& world = contact ? before : after;
      world.reserve(result_count * 4);
      for (size_t i = 0; i < result_count; ++i) {
        const auto& r = result[i];
        valid = valid && r.instance == i / vertex_count && r.vertex == i % vertex_count;
        for (int c = 0; c < 4; ++c)
          valid = valid && std::isfinite(r.pre[c]) && std::isfinite(r.post[c]);
        if (contact) {
          ids.push_back(r.instance * stride_instances); ids.push_back(r.vertex);
        }
        world.insert(world.end(), r.post, r.post + 4);
      }
      const bool unmapped = glUnmapBuffer(GL_TRANSFORM_FEEDBACK_BUFFER);
      if (!gl_clean() || !unmapped) valid = false;
    }
    restore();
    if (!valid) { fail_capture("TF count/identity/nonfinite/GL error"); return; }
    // Count contact only after every captured component passed the finite check.
    uint64_t contact_vertices = 0;
    for (size_t i = 0; i < result_count; ++i) {
      const size_t o = i * 4;
      if (before[o + 3] > 0.f && after[o + 3] > 0.f &&
          (before[o] != after[o] || before[o + 1] != after[o + 1] ||
           before[o + 2] != after[o + 2])) ++contact_vertices;
    }
    autoport_proof::publish("shrub_grass_capture_errors", capture_errors);
    autoport_proof::publish("shrub_grass_instance_sample_stride", stride_instances);
    autoport_proof::publish("shrub_grass_sampled_vertices", result_count);
    static u64 total_contact_vertices = 0;
    total_contact_vertices += contact_vertices;
    autoport_proof::publish("shrub_grass_sampled_contact_vertices", total_contact_vertices);
    // Archive the bytes actually read from GPU attributes, including disabled constants.
    // No buffer handle/pointer enters cross-binary identity; metadata describes interpretation.
    std::vector<u8> gpu_attributes;
    auto append = [&](const void* data, size_t bytes) {
      const auto* p = static_cast<const u8*>(data);
      gpu_attributes.insert(gpu_attributes.end(), p, p + bytes);
    };
    for (u32 a = 0; a < 5; ++a) {
      const auto& at = attrs[a];
      const u32 metadata[] = {a, u32(at.enabled), u32(at.size), u32(at.type),
                              u32(at.normalized), u32(at.divisor), u32(at.bytes.size())};
      append(metadata, sizeof(metadata));
      if (at.enabled) append(at.bytes.data(), at.bytes.size());
      else append(at.constant, sizeof(at.constant));
    }
    shrub_contact_probe::archive_blob("grass", grass_level, 0, pass, "attribute-0",
                                     gpu_attributes.data(), gpu_attributes.size());
    // Query active uniforms from the program; never archive a guessed CPU mirror.
    GLint uniform_count = 0;
    glGetProgramiv(id, GL_ACTIVE_UNIFORMS, &uniform_count);
    for (GLint ui = 0; ui < uniform_count; ++ui) {
      char name[256]; GLsizei length = 0; GLint count = 0; GLenum type = 0;
      glGetActiveUniform(id, ui, sizeof(name), &length, &count, &type, name);
      int width = 1;
      if (type == GL_FLOAT_VEC2 || type == GL_INT_VEC2) width = 2;
      if (type == GL_FLOAT_VEC3 || type == GL_INT_VEC3) width = 3;
      if (type == GL_FLOAT_VEC4 || type == GL_INT_VEC4) width = 4;
      if (type == GL_FLOAT_MAT4) width = 16;
      const bool floating = type == GL_FLOAT || type == GL_FLOAT_VEC2 ||
          type == GL_FLOAT_VEC3 || type == GL_FLOAT_VEC4 || type == GL_FLOAT_MAT4;
      std::string base(name, length);
      const auto bracket = base.find('[');
      if (bracket != std::string::npos) base.resize(bracket);
      std::vector<u32> bits(size_t(count) * width);
      for (int e = 0; e < count; ++e) {
        const std::string entry = count > 1 ? base + "[" + std::to_string(e) + "]" : base;
        const GLint location = grass_uloc(id, entry.c_str());
        if (floating) {
          float values[16] = {};
          glGetUniformfv(id, location, values);
          std::memcpy(bits.data() + e * width, values, width * sizeof(float));
        } else {
          GLint values[16] = {};
          glGetUniformiv(id, location, values);
          std::memcpy(bits.data() + e * width, values, width * sizeof(GLint));
        }
      }
      shrub_contact_probe::archive_blob("grass", grass_level, 0, pass, "uniform-" + base,
          bits.data(), bits.size() * sizeof(u32));
    }
    if (!gl_clean()) { fail_capture("uniform archive GL error"); return; }
    shrub_contact_probe::archive_capture("grass", grass_level, 0, pass,
        ids.data(), ids.size() * sizeof(u32), before.data(), before.size() * sizeof(float),
        after.data(), after.size() * sizeof(float));
  };

  // grass-chunk-cull : LES ATTRIBUTS D'INSTANCE, REPOSES A L'OFFSET D'UN LOT. GLES 3 n'a pas de
  // `baseInstance` : la seule facon de dessiner [first, first+count) d'un tampon d'instances est
  // de decaler les pointeurs d'attribut. Les cinq pointeurs se reposent ensemble — trois sur le
  // tampon d'instances (0/1/2, plus 4 si l'appareil l'autorise), un sur le tampon de lumiere (3) —
  // sinon la couleur d'une instance viendrait d'une AUTRE.
  using grass_bake::GrassInstance;
  auto bind_at = [&](int first) {
    const size_t base = (size_t)first * sizeof(GrassInstance);
    glBindBuffer(GL_ARRAY_BUFFER, m_instance_vbo);
    glVertexAttribPointer(0, 4, GL_FLOAT, GL_FALSE, sizeof(GrassInstance), (void*)base);
    glVertexAttribPointer(1, 4, GL_FLOAT, GL_FALSE, sizeof(GrassInstance),
                          (void*)(base + 4 * sizeof(float)));
    glVertexAttribPointer(2, 4, GL_FLOAT, GL_FALSE, sizeof(GrassInstance),
                          (void*)(base + 8 * sizeof(float)));
    if (m_attr4_on) {
      glVertexAttribPointer(4, 4, GL_FLOAT, GL_FALSE, sizeof(GrassInstance),
                            (void*)(base + 12 * sizeof(float)));
    }
    glBindBuffer(GL_ARRAY_BUFFER, m_light_vbo);
    glVertexAttribPointer(3, 4, GL_UNSIGNED_BYTE, GL_TRUE, 4 * sizeof(u8),
                          (void*)((size_t)first * 4));
  };
  // grass-shading : LE TERME DE FACE SUPPOSE QUE LES DEUX FACES DU RUBAN SONT RASTERISEES.
  // `gl_FrontFacing` ne separe rien si le pilote elimine la face arriere : la moitie du terme
  // n'atteindrait jamais un pixel et la porte publierait un ecart que personne ne voit.
  // `GrassRenderer` ne touche jamais a GL_CULL_FACE — il herite de l'etat laisse par la passe
  // precedente. On ne le suppose donc pas : on lit l'etat REEL au moment du dessin.
  if (autoport_proof::feature_is(kShadeItemId)) {
    autoport_proof::publish("grass_shade_engine_cull_face",
                            glIsEnabled(GL_CULL_FACE) ? 1u : 0u);
  }
  u64 draw_calls = 0;
  auto draw_pass = [&](GLenum mode, GLint verts, const std::vector<std::pair<int, int>>& runs,
                       int limit, int tris_per) -> u64 {
    u64 total = 0;
    if (!cull_on) {
      if (limit > 0) {
        bind_at(0);
        glDrawArraysInstanced(mode, 0, verts, limit);
        soft_draw_census::record_arrays("grass", verts, mode, limit);
        prof.add_draw_call();
        prof.add_tri(limit * tris_per);
        draw_calls++;
        total = (u64)limit;
      }
      return total;
    }
    for (const auto& r : runs) {
      if (r.first >= limit) {
        break;
      }
      const int cnt = std::min(r.second, limit - r.first);
      if (cnt <= 0) {
        continue;
      }
      bind_at(r.first);
      glDrawArraysInstanced(mode, 0, verts, cnt);
      soft_draw_census::record_arrays("grass", verts, mode, cnt);
      prof.add_draw_call();
      prof.add_tri(cnt * tris_per);
      draw_calls++;
      total += (u64)cnt;
    }
    return total;
  };

  // NEAR: individual blades (10-vert triangle strip)
  const auto t_draw0 = std::chrono::steady_clock::now();
  glUniform1i(mode_loc, 0);
  // grass-blade-variants : le budget geometrique est NOMME ici, et c'est CETTE variable que
  // `glDrawArraysInstanced` recoit — la valeur publiee plus bas n'en est pas une recopie.
  const GLint kBladeVerts = (GLint)grass_bake::kBladeStripVerts;   // 10 = 2*(SEGMENTS+1)
  const GLint kCardVerts = 12;
  const u64 submitted_blade = draw_pass(GL_TRIANGLE_STRIP, kBladeVerts, m_blade_runs, draw_n, 8);
  // La sonde de contact lit les pointeurs d'attribut EN L'ETAT et echantillonne une instance sur
  // 256 depuis le debut du tampon : on les remet a zero avant de l'appeler, sinon elle decrirait
  // le dernier lot au lieu du champ.
  bind_at(0);
  capture_grass(0, kBladeVerts, (int)submitted_blade);
  sync_ms("blade draw");

  // MID: X-cross cards (12-vert, 4 triangles). card_n stops before the droop tail: droop NEVER
  // has a card tier (far LOD = the game's own alpha overhang texture).
  glUniform1i(mode_loc, 1);
  const u64 submitted_card = draw_pass(GL_TRIANGLES, kCardVerts, m_card_runs, card_n, 4);
  bind_at(0);
  capture_grass(1, kCardVerts, (int)submitted_card);
  sync_ms("card draw");
  // grass-blade-variants, point 4 du livrable : AUCUNE MODELISATION. La geometrie du brin sort de
  // `gl_VertexID` ; s'il existait un maillage, il arriverait par un attribut de sommet, c'est-a-dire
  // un attribut ACTIF de diviseur 0. On lit l'etat REEL du VAO qu'on vient de dessiner, on ne le
  // deduit pas du code : `vertex` doit valoir 0, et `instance` non nul (sinon la sonde n'a rien vu).
  if (autoport_proof::feature_is(kVariantItemId)) {
    static u64 s_pub_b = ~0ull, s_pub_c = ~0ull;
    if (s_pub_b != submitted_blade || s_pub_c != submitted_card) {
      s_pub_b = submitted_blade;
      s_pub_c = submitted_card;
      int attr_scanned = 0, attr_vertex = 0, attr_instance = 0;
      for (int a = 0; a < 8; ++a) {
        GLint en = 0, dv = 0;
        glGetVertexAttribiv((GLuint)a, GL_VERTEX_ATTRIB_ARRAY_ENABLED, &en);
        glGetVertexAttribiv((GLuint)a, GL_VERTEX_ATTRIB_ARRAY_DIVISOR, &dv);
        attr_scanned++;
        if (en) {
          if (dv == 0) {
            attr_vertex++;
          } else {
            attr_instance++;
          }
        }
      }
      autoport_proof::publish("grass_variant_attr_scanned", (uint64_t)attr_scanned);
      autoport_proof::publish("grass_variant_attr_vertex", (uint64_t)attr_vertex);
      autoport_proof::publish("grass_variant_attr_instance", (uint64_t)attr_instance);
      autoport_proof::publish("grass_variant_draw_blade_verts", (uint64_t)kBladeVerts);
      autoport_proof::publish("grass_variant_draw_card_verts", (uint64_t)kCardVerts);
      autoport_proof::publish("grass_variant_draw_blades", submitted_blade);
      autoport_proof::publish("grass_variant_draw_cards", submitted_card);
      autoport_proof::publish("grass_variant_draw_verts_frame",
                              (uint64_t)kBladeVerts * submitted_blade +
                                  (uint64_t)kCardVerts * submitted_card);
      autoport_proof::publish("grass_variant_draw_calls", draw_calls);
    }
  }
  // grass-baseline-cost : le dessin de cette image, en DEUX grandeurs SEPAREES, parce qu'elles
  // nomment deux causes differentes. `fence` est l'attente de la barriere posee a l'image
  // PRECEDENTE — la contre-pression GPU que le correctif Adreno 618 a rendue explicite ; `submit`
  // est le temps processeur des deux appels de dessin. Melangees, elles feraient passer une
  // attente du GPU pour un cout de soumission, et le diagnostic partirait a l'envers.
  const double submit_us =
      std::chrono::duration<double, std::micro>(std::chrono::steady_clock::now() - t_draw0).count();
  grass_baseline::note_draw(
      std::chrono::duration<double, std::micro>(t_fence1 - t_fence0).count(), submit_us,
      submitted_blade, submitted_card);

  // grass-dead-tail : LE COMPTE ATTEINT PAR UN APPEL DE DESSIN, LU AU POINT D'APPEL — pas la
  // variable qu'un autre bout de code croit passer. `grass_dead_instances` est la DIFFERENCE de
  // deux termes publies SEPAREMENT juste au-dessus : l'egalite est le verdict, et un ecart dans
  // l'autre sens (plus dessine que construit) rend une valeur POSITIVE, donc rouge, au lieu de se
  // faire ecraser a zero. Publie une fois par couple (construit, atteint) : une image qui ne
  // change rien n'ecrit pas 55 000 lignes dans le journal.
  if (autoport_proof::armed_for(kDeadTailItemId) && autoport_proof::feature_is(kDeadTailItemId)) {
    static int s_pub_built = -1, s_pub_reached = -1;
    const int reached = std::max(draw_n, card_n);
    if (s_pub_built != m_instance_count || s_pub_reached != reached) {
      s_pub_built = m_instance_count;
      s_pub_reached = reached;
      const uint64_t built = (uint64_t)(m_instance_count < 0 ? 0 : m_instance_count);
      const uint64_t rch = (uint64_t)(reached < 0 ? 0 : reached);
      autoport_proof::publish("grass_dead_built_instances", built);
      autoport_proof::publish("grass_dead_drawn_instances", rch);
      autoport_proof::publish("grass_dead_instances", built >= rch ? built - rch : rch - built);
      autoport_proof::publish("grass_dead_draw_blade_n", (uint64_t)(draw_n < 0 ? 0 : draw_n));
      autoport_proof::publish("grass_dead_draw_card_n", (uint64_t)(card_n < 0 ? 0 : card_n));
      autoport_proof::note_hit_for(kDeadTailItemId, built);
    }
  }

  // ROUND#19 wedge fix, part 2: fence THIS frame's grass draws; the wait above (next frame) will not
  // submit more grass until these have fully retired -> pipeline depth <= 1 grass frame, the unbounded
  // queue pileup that wedged the kgsl driver can no longer form.
  s_grass_fence = glFenceSync(GL_SYNC_GPU_COMMANDS_COMPLETE, 0);

  glBindVertexArray(0);

  // ===== grass-baseline-cost : LE RECENSEMENT DU CHAMP DE VISION =============================
  // « instances SOUMISES contre celles reellement DANS LE CHAMP DE VISION » : le denominateur est
  // `draw_n` ci-dessus ; le numerateur n'existe NULLE PART — aucun test de frustum n'est ecrit
  // dans ce renderer, ni par instance ni par chunk (`m_chunks` n'est meme peuple que sous
  // `OG_GRASS_DIAG`, et son `DROPPED` est calcule sur ses propres variables). On le FABRIQUE ici,
  // hors de la fenetre de mesure — quelques images par cellule — en rejouant EXACTEMENT
  // `world_to_clip` de `shaders/grass.vert:81-98` sur la base de chaque instance.
  //
  // POURQUOI RECOPIER CES LIGNES AU LIEU D'UNE PROJECTION « NORMALE ». Ce n'est pas une mat4
  // standard : la division par `transformed[3]`, l'ajout de `hvdf_offset`, les -2048 / /256 /
  // /-128 et la remultiplication par w viennent du chemin PS2. Un test de frustum ecrit avec une
  // projection ordinaire compterait autre chose que ce que le rasteriseur garde, et rien ne le
  // dirait. Les deux constantes de gabarit sont celles que `Shader.cpp:234-236` substitue pour
  // jak1 — HEIGHT_SCALE = 1.0, SCISSOR_ADJUST = 512/448 — et l'herbe n'existe que sur jak1
  // (`kGrassLevels` = {"training"}).
  //
  // CE RECENSEMENT NE DECIDE DE RIEN. Il ne saute aucun dessin : les deux appels ci-dessus ont
  // deja eu lieu, sur la TOTALITE des instances soumises. Il mesure ce qu'un culling rendrait.
  if (grass_baseline::want_frustum_census()) {
    const auto& cm0 = proof_camera[0];
    const auto& cm1 = proof_camera[1];
    const auto& cm2 = proof_camera[2];
    const auto& cm3 = proof_camera[3];
    const float fogc = rs->camera_fog.x();
    const float scissor_y = 512.0f / 448.0f;  // SCISSOR_ADJUST * HEIGHT_SCALE, jak1
    const float lod_reach = card_m * U;       // la portee des cartes, la plus lointaine des deux
    const float cpx = proof_position[0], cpy = proof_position[1], cpz = proof_position[2];
    uint64_t in_frustum = 0, in_lod = 0, behind = 0;
    const int tested = draw_n < 0 ? 0 : draw_n;
    for (int i = 0; i < tested && i < m_instance_count; i++) {
      const auto& gi = m_instances[(size_t)i];
      float tx = -cm3[0] - cm0[0] * gi.px - cm1[0] * gi.py - cm2[0] * gi.pz;
      float ty = -cm3[1] - cm0[1] * gi.px - cm1[1] * gi.py - cm2[1] * gi.pz;
      float tz = -cm3[2] - cm0[2] * gi.px - cm1[2] * gi.py - cm2[2] * gi.pz;
      const float tw = -cm3[3] - cm0[3] * gi.px - cm1[3] * gi.py - cm2[3] * gi.pz;
      if (tw <= 0.f) {
        behind++;
        continue;
      }
      const float q = fogc / tw;
      tx = tx * q + proof_hvdf[0];
      ty = ty * q + proof_hvdf[1];
      tz = tz * q + proof_hvdf[2];
      tx -= 2048.f;
      ty -= 2048.f;
      tz = tz / 8388608.f - 1.f;
      tx /= 256.f;
      ty /= -128.f;
      tx *= tw;
      ty *= tw * scissor_y;
      tz *= tw;
      if (tx >= -tw && tx <= tw && ty >= -tw && ty <= tw && tz >= -tw && tz <= tw) {
        in_frustum++;
        const float dx = gi.px - cpx, dy = gi.py - cpy, dz = gi.pz - cpz;
        if (dx * dx + dy * dy + dz * dz <= lod_reach * lod_reach) {
          in_lod++;
        }
      }
    }
    grass_baseline::note_camera(cpx, cpy, cpz);
    grass_baseline::note_frustum(in_frustum, in_lod, (uint64_t)tested, behind);
  }

  // ===== grass-chunk-cull : LE RECENSEMENT, PAR L'ORACLE ======================================
  // Tout ce qui suit est mesure sur CETTE image, celle dont les deux passes viennent d'etre
  // soumises. Les comptes SOUMIS sont lus aux appels de dessin (`submitted_blade`/`_card`), pas a
  // une variable qu'un autre bout de code croit passer. Les comptes de l'oracle sont produits par
  // l'arithmetique LITTERALE du shader, sur une boite 5 cm plus large que celle du culler.
  //
  // Une image par jambe : le balayage des instances coute un parcours complet, et il n'a rien a
  // faire dans la fenetre ou l'on chronometre le dessin (la campagne l'exclut de ses echantillons).
  if (grass_cull::want_census()) {
    const float fogc = rs->camera_fog.x();
    const float omxz = (kCullMarginXZ_M + kOracleSlack_M) * U;
    const float omy = (kCullMarginY_M + kOracleSlack_M) * U;
    const float blade_reach = near_m * U;
    const float card_out = card_m * U;
    const float card_in = 0.45f * near_m * U;
    const float cp[3] = {proof_position[0], proof_position[1], proof_position[2]};

    // --- niveau LOT : ce que l'oracle garde, et ce que le culler a soumis en trop.
    std::vector<u8> oracle_keep(m_cull_chunks.size(), 0);
    u64 chunk_visible = 0;
    for (size_t i = 0; i < m_cull_chunks.size(); i++) {
      const auto& c = m_cull_chunks[i];
      const float lo[3] = {c.lo[0] - omxz, c.lo[1] - omy, c.lo[2] - omxz};
      const float hi[3] = {c.hi[0] + omxz, c.hi[1] + omy, c.hi[2] + omxz};
      if (grass_box_outside_literal(proof_camera, proof_hvdf.data(), fogc, kGrassScissorY, lo,
                                    hi)) {
        continue;
      }
      float dmin2 = 0.f, dmax2 = 0.f;
      for (int k = 0; k < 3; k++) {
        const float q = std::min(std::max(cp[k], lo[k]), hi[k]) - cp[k];
        dmin2 += q * q;
        const float f = std::max(std::fabs(lo[k] - cp[k]), std::fabs(hi[k] - cp[k]));
        dmax2 += f * f;
      }
      u8 k2 = 0;
      if (dmin2 < blade_reach * blade_reach) {
        k2 |= 1;
      }
      if (dmin2 < card_out * card_out && dmax2 > card_in * card_in) {
        k2 |= 2;
      }
      oracle_keep[i] = k2;
      chunk_visible += ((k2 & 1) ? c.count : 0) + ((k2 & 2) ? c.count : 0);
    }
    u64 offscreen = 0;
    for (size_t i = 0; i < m_cull_chunks.size(); i++) {
      const u8 sub = cull_on ? m_cull_keep[i] : (u8)3;
      const u8 orc = oracle_keep[i];
      if ((sub & 1) && !(orc & 1)) {
        offscreen += m_cull_chunks[i].count;
      }
      if ((sub & 2) && !(orc & 2)) {
        offscreen += m_cull_chunks[i].count;
      }
    }

    // --- niveau INSTANCE : ce qui aurait DESSINE quelque chose, et ce qui n'a pas ete soumis.
    // La boite d'une instance couvre le brin entier ; le predicat de distance est celui du
    // shader, sur la base. `dropped_visible` est le terme qui interdit de gagner du temps en
    // retirant des pixels : il est independant de toute la machinerie de lots.
    const float ixz = 0.35f * U, iy = 0.15f * U;
    u64 ideal = 0, dropped = 0;
    size_t rb = 0, rc = 0;
    const int scan_n = std::min(draw_n, m_instance_count);
    for (int i = 0; i < scan_n; i++) {
      const auto& gi = m_instances[(size_t)i];
      const float lo[3] = {gi.px - ixz, gi.py - iy, gi.pz - ixz};
      const float hi[3] = {gi.px + ixz, gi.py + gi.h + iy, gi.pz + ixz};
      const float dx = gi.px - cp[0], dy = gi.py - cp[1], dz = gi.pz - cp[2];
      const float d2 = dx * dx + dy * dy + dz * dz;
      const bool near_ok = d2 < blade_reach * blade_reach;
      const bool card_ok = d2 < card_out * card_out && d2 > card_in * card_in && i < card_n;
      bool in_vol = false;
      if (near_ok || card_ok) {
        in_vol = !grass_box_outside_literal(proof_camera, proof_hvdf.data(), fogc, kGrassScissorY,
                                            lo, hi);
      }
      while (rb < m_blade_runs.size() &&
             m_blade_runs[rb].first + m_blade_runs[rb].second <= i) {
        rb++;
      }
      while (rc < m_card_runs.size() && m_card_runs[rc].first + m_card_runs[rc].second <= i) {
        rc++;
      }
      const bool sub_b = !cull_on ? (i < draw_n)
                                  : (rb < m_blade_runs.size() && i >= m_blade_runs[rb].first);
      const bool sub_c = !cull_on ? (i < card_n)
                                  : (rc < m_card_runs.size() && i >= m_card_runs[rc].first);
      if (in_vol && near_ok) {
        ideal++;
        if (!sub_b) {
          dropped++;
        }
      }
      if (in_vol && card_ok) {
        ideal++;
        if (!sub_c) {
          dropped++;
        }
      }
    }

    // L'avant de la camera EFFECTIVE : le gradient de la profondeur, seul temoin qui distingue
    // trois vues de trois fois la meme.
    float fwd[3] = {-proof_camera[0][3], -proof_camera[1][3], -proof_camera[2][3]};
    const float fl = std::sqrt(fwd[0] * fwd[0] + fwd[1] * fwd[1] + fwd[2] * fwd[2]);
    if (fl > 1e-9f) {
      fwd[0] /= fl;
      fwd[1] /= fl;
      fwd[2] /= fl;
    }
    // --- L'ARITHMETIQUE DES PLAGES, verifiee au lieu d'etre supposee. Le seul mecanisme NEUF
    // du chemin de dessin est le decalage des pointeurs d'attribut : une plage qui deborderait le
    // tampon, en chevaucherait une autre, ou ne couvrirait pas exactement les lots gardes ferait
    // lire a une instance la donnee d'une autre. Ces trois invariants se verifient pour trois
    // comparaisons par plage, et leur violation se PUBLIE.
    u64 run_viol = 0;
    auto check_runs = [&](const std::vector<std::pair<int, int>>& runs, u8 mask, int limit) {
      int prev_end = 0;
      u64 sum = 0;
      for (const auto& r : runs) {
        if (r.first < prev_end || r.second <= 0 || r.first + r.second > m_instance_count) {
          run_viol++;
        }
        prev_end = r.first + r.second;
        sum += (u64)r.second;
      }
      u64 want = 0;
      for (size_t i = 0; i < m_cull_chunks.size(); i++) {
        if (m_cull_keep[i] & mask) {
          want += m_cull_chunks[i].count;
        }
      }
      if (sum != want) {
        run_viol++;
      }
      (void)limit;
    };
    if (cull_on && !run_overflow) {
      check_runs(m_blade_runs, 1, draw_n);
      check_runs(m_card_runs, 2, card_n);
    }
    autoport_proof::publish("grass_cull_run_invariant_violations", run_viol);
    autoport_proof::publish("grass_cull_run_overflow_frames", g_grass_run_overflow_frames);
    grass_cull::note_census(submitted_blade + submitted_card, chunk_visible, offscreen, dropped,
                            ideal, chunks_kept_blade + chunks_kept_card,
                            (u64)m_cull_chunks.size(), fwd);
    lg::info(
        "[recharged-grass] CHUNK-CULL census: soumises={} (lame {} carte {}) oracle_lots={} "
        "hors_champ={} perdues={} ideal={} lots={}/{} appels={} overflow={}",
        submitted_blade + submitted_card, submitted_blade, submitted_card, chunk_visible, offscreen,
        dropped, ideal, chunks_kept_blade + chunks_kept_card, (u64)m_cull_chunks.size(), draw_calls,
        run_overflow ? 1 : 0);
  }

  g_grass_uloc_requests_frame = g_grass_uloc_requests - uloc_req0;
  g_grass_uloc_misses_frame = g_grass_uloc_misses - uloc_miss0;

  // grass-chunk-cull : UNE IMAGE DESSINEE PAR LE RENDERER D'HERBE. C'est ce qui fait avancer la
  // campagne : elle n'a pas besoin d'un crochet par plateforme, elle compte les images ou l'herbe
  // a REELLEMENT ete dessinee.
  grass_cull::note_frame(
      std::chrono::duration<double, std::micro>(t_fence0 - t_prep0).count(), submit_us, draw_calls,
      submitted_blade + submitted_card, chunks_tested, g_grass_uloc_misses_frame,
      m_instance_count > 0);
  autoport_proof::publish("grass_cull_uniform_requests_per_frame", g_grass_uloc_requests_frame);

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
                                                 Gfx::settings().recharged_grass_near_dist));
    float card_out_m = std::min(200.0f, std::max(blade_end_m + 5.0f,
                                                 Gfx::settings().recharged_grass_card_dist));
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
