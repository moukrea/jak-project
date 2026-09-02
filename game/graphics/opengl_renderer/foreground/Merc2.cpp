#include "Merc2.h"

#include "game/system/npc_flicker.h"

#ifdef __ANDROID__
#include <unistd.h>

#include "common/util/FileUtil.h"
#endif

// Gd3-jak: property-armed (env OG_GD3_CENSUS / prop debug.opengoal.gd3.census, OFF
// by default) observability for the always-on NaN merc-bone repair in handle_pc_model.
// When armed, logs GD3-MERC lines (Jak's effect enable-mask / visible tris / bones
// repaired) to stdout (dup2'd to logcat tag GK_STDOUT on Android). The repair itself
// is unconditional on arm64; this gate only controls the diagnostic print.
#include <algorithm>
#include <atomic>
#include <bitset>
#include <cmath>
#include <cstdlib>
#include <cstring>

#include "common/log/log.h"
#include <chrono>
#include <map>
#include <mutex>
#include <set>
#include <unordered_map>
#include <vector>
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif
#ifdef OG_FEAT_HD_MODELS
#include "game/graphics/opengl_renderer/EyeRenderer.h"  // hd_eye_blerc_gain
#endif
// Grecharged-title-logo-fullres: the camera-anchored 3D overlays of the two logo screens.
// Names are the merc-ctrl names the GOAL side puts in the merc DMA header (the decompiler-only
// "-jg"/"-mg" suffixes are NOT part of the runtime name); verified against the strings in
// out/jak1/fr3/title.fr3 and the loader's "merc-load lvl=title model=..." lines.
//   logo-*   : the JAK AND DAXTER title logo, its volumetric light shafts and its black card
//   ndi-*    : the Naughty Dog boot logo, the same construction on a black background
// These are the only merc models in the game that are pinned in front of the camera by a
// joint-mod every frame, i.e. the only ones for which "draw it after the UI composite" is
// equivalent to "draw it where it already was", so the list is deliberately explicit rather
// than a prefix match.
static bool merc2_is_native_overlay_model(const char* name) {
  static const char* kNames[] = {
      "logo-english-lod0",        "logo-japan-lod0", "logo-volumes-english-lod0",
      "logo-volumes-japan-lod0",  "logo-black-lod0", "logo-cam-lod0",
      "ndi-lod0",                 "ndi-volumes-lod0", "ndi-cam-lod0",
  };
  for (const char* n : kNames) {
    if (!strcmp(name, n)) {
      return true;
    }
  }
  return false;
}

static bool gd3_bones_on() {
  static const bool s_on = [] {
    if (std::getenv("OG_GD3_CENSUS")) {
      return true;
    }
#ifdef __ANDROID__
    char buf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.gd3.census", buf) > 0 && buf[0] == '1') {
      return true;
    }
#endif
    return false;
  }();
  return s_on;
}

// F1 (Geyser Rock gameplay) observability — property-armed (env OG_F1_CENSUS /
// prop debug.opengoal.f1.census, OFF by default), mirrors the gd3 idiom above.
// When armed and Jak (eichar) is drawn, reads Jak's authoritative world position
// (-> *target* control trans) straight out of EE memory and prints an F1-STATE
// line (plus a one-shot "engine: state=in-game" marker the first time a valid
// target is seen in a loaded level). Diagnostic only; no behavior change.
static bool f1_census_on() {
  static const bool s_f1_census = [] {
    if (std::getenv("OG_F1_CENSUS")) {
      return true;
    }
#ifdef __ANDROID__
    char buf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.f1.census", buf) > 0 && buf[0] == '1') {
      return true;
    }
#endif
    return false;
  }();
  return s_f1_census;
}

// OWNER ROUND#21 (Grecharged-grass-poc): object-clip completeness CENSUS — property-armed
// (env OG_GRASS_CENSUS / prop debug.opengoal.grass.census, OFF by default). When armed, EVERY
// merc model drawn logs one R21CENSUS line with its recovered WORLD position and whether the
// grass object-clip handles it (TRAMPLE / CULL / none), so the training-level ground objects
// (button, eco vents, planks, decor, crates...) can be audited against the grass coverage
// instead of guessing which names the allowlist misses. Diagnostic only; no behavior change.
static bool grass_census_on() {
  static const bool s_grass_census = [] {
    if (std::getenv("OG_GRASS_CENSUS")) {
      return true;
    }
#ifdef __ANDROID__
    char buf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.grass.census", buf) > 0 && buf[0] == '1') {
      return true;
    }
#endif
    return false;
  }();
  return s_grass_census;
}

// Gecho-pool: Merc2 model-name census (env OG_GECHO_MERC / prop debug.opengoal.gecho.merc,
// OFF by default). Logs which merc models render through Merc2 each frame, to locate where the
// dark-eco-pool (model "water-anim-misty") goes on arm64. Diagnostic only; no behavior change.
static bool gecho_merc_on() {
  static const bool s_on = [] {
    if (std::getenv("OG_GECHO_MERC")) {
      return true;
    }
#ifdef __ANDROID__
    char buf[PROP_VALUE_MAX] = {0};
    if (__system_property_get("debug.opengoal.gecho.merc", buf) > 0 && buf[0] == '1') {
      return true;
    }
#endif
    return false;
  }();
  return s_on;
}

#include "common/global_profiler/GlobalProfiler.h"
#include "common/util/fnv.h"
#include "common/util/simd_util.h"

#include "game/graphics/opengl_renderer/EyeRenderer.h"
#include "game/graphics/opengl_renderer/background/background_common.h"
#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/GrassOccluders.h"

// F1 census: kernel symbol lookup + EE memory base for the (-> *target* control
// trans) probe below. Mirrors game/graphics/sceGraphicsInterface.cpp's use of
// jak1::intern_from_c + g_ee_main_mem (same established cross-TU pattern).
#include "common/goal_constants.h"

#include "game/kernel/common/kscheme.h"
#include "game/kernel/jak1/kscheme.h"
#include "game/runtime.h"

#include "third-party/imgui/imgui.h"

// F1a bisection knobs: the first merc draw SIGSEGVs inside the Adreno driver
// with state-legal parameters (runs 4-8). Toggle GL stages off via marker
// files in the app files dir (run-as touch, no rebuild):
//   f1a_merc_nodraw — skip the glDrawElements calls (all other state runs)
//   f1a_merc_noubo  — skip glBindBufferRange of the bones UBO
//   f1a_merc_notex  — skip glBindTexture
namespace {
#ifdef __ANDROID__
// Lazy: get_jak_project_dir() is only valid after JNI hands over the files
// dir — static-init evaluation killed the app at library load (run-9).
bool f1a_merc_knob(const char* name) {
  auto p = file_util::get_jak_project_dir() / name;
  return access(p.string().c_str(), F_OK) == 0;
}
struct F1aKnobs {
  bool nodraw, noubo, notex;
};
const F1aKnobs& f1a_knobs() {
  static const F1aKnobs k = [] {
    F1aKnobs r{f1a_merc_knob("f1a_merc_nodraw"), f1a_merc_knob("f1a_merc_noubo"),
               f1a_merc_knob("f1a_merc_notex")};
    fprintf(stderr, "F1A-MERC-KNOBS nodraw=%d noubo=%d notex=%d\n", (int)r.nodraw, (int)r.noubo,
            (int)r.notex);
    return r;
  }();
  return k;
}
#define f1a_nodraw (f1a_knobs().nodraw)
#define f1a_noubo (f1a_knobs().noubo)
#define f1a_notex (f1a_knobs().notex)
#else
constexpr bool f1a_nodraw = false;
constexpr bool f1a_noubo = false;
constexpr bool f1a_notex = false;
#endif
}  // namespace

/* Merc 2 renderer:
 The merc2 renderer is the main "foreground" renderer, which draws characters, collectables,
 and even some water.

 The PC format renderer does the usual tricks of buffering stuff head of time as much as possible.
 The main trick here is to buffer up draws and upload "bones" (skinning matrix) for many draws all
 at once.

 The other tricky part is "mod vertices", which may be modified by the game.
 We know ahead of time which vertices could be modified, and have a way to upload only those
 vertices.

 Each "merc model" corresponds to a merc-ctrl in game. There's one merc-ctrl per LOD of an
 art-group. So generally, this will be something like "jak" or "orb" or "some enemy".

 Each model is made up of "effect"s. There are a number of per-effect settings, like environment
 mapping. Generally, the purpose of an "effect" is to divide up a model into parts that should be
 rendered with a different configuration.

 Within each model, there are fragments. These correspond to how much data can be uploaded to VU1
 memory. For the most part, fragments are not considered by the PC renderer. The only exception is
 updating vertices - we must read the data from the game, which is stored in fragments.

 Per level, there is an FR3 file loaded by the loader. Each merc renderer can access multiple
 levels.
*/

/*!
 * Remaining ideas for optimization:
 * - port blerc to C++, do it in the rendering thread and avoid the lock.
 * - combine envmap draws per effect (might require some funky indexing stuff, or multidraw)
 * - smaller vertex formats for mod-vertex
 * - AVX version of vertex conversion math
 * - eliminate the "copy" step of vertex modification
 * - batch uploading the vertex modification data
 */

std::mutex g_merc_data_mutex;

Merc2::Merc2(ShaderLibrary& shaders, const std::vector<GLuint>* anim_slot_array)
    : m_anim_slot_array(anim_slot_array) {
  ASSERT(fnv64("the quick brown fox jumps over the lazy dog") == 0x7404cea13ff89bb0);

  // Set up main vertex array. This will point to the data stored in the .FR3 level file, and will
  // be uploaded to the GPU by the Loader.
  glGenVertexArrays(1, &m_vao);
  glBindVertexArray(m_vao);

  // Bone buffer to store skinning matrices for multiple draws
  glGenBuffers(1, &m_bones_buffer);
  glBindBuffer(GL_UNIFORM_BUFFER, m_bones_buffer);

  // zero initialize the bone buffer.
  std::vector<u8> temp(MAX_SHADER_BONE_VECTORS * sizeof(math::Vector4f));
  glBufferData(GL_UNIFORM_BUFFER, MAX_SHADER_BONE_VECTORS * sizeof(math::Vector4f), temp.data(),
               GL_DYNAMIC_DRAW);
  glBindBuffer(GL_UNIFORM_BUFFER, 0);

  // annoyingly, glBindBufferRange can have alignment restrictions that vary per platform.
  // the GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT gives us the minimum alignment for views into the bone
  // buffer. The bone buffer stores things per-16-byte "quadword".
  GLint val;
  glGetIntegerv(GL_UNIFORM_BUFFER_OFFSET_ALIGNMENT, &val);
  if (val <= 16) {
    // somehow doubt this can happen, but just in case
    m_opengl_buffer_alignment = 1;
  } else {
    m_opengl_buffer_alignment = val / 16;  // number of bone vectors
    if (m_opengl_buffer_alignment * 16 != (u32)val) {
      ASSERT_MSG(false,
                 fmt::format("opengl uniform buffer alignment is {}, which is strange\n", val));
    }
  }

  // initialize draw buffers, these will store lists of draws to flush.
  for (int i = 0; i < MAX_LEVELS; i++) {
    auto& draws = m_level_draw_buckets.emplace_back();
    draws.draws.resize(MAX_DRAWS_PER_LEVEL);
    draws.envmap_draws.resize(MAX_ENVMAP_DRAWS_PER_LEVEL);
    // Grecharged-title-logo-fullres: native-overlay pools, sized once here so alloc_normal_draw
    // can hand out raw Draw* into them without any reallocation hazard.
    draws.native_draws.resize(MAX_NATIVE_DRAWS_PER_LEVEL);
    draws.native_envmap_draws.resize(MAX_NATIVE_DRAWS_PER_LEVEL);
  }

  m_mod_vtx_temp.resize(MAX_MOD_VTX);
  m_mod_vtx_unpack_temp.resize(MAX_MOD_VTX * 2);

  for (auto& x : m_effect_debug_mask) {
    x = true;
  }

  init_shader_common(shaders[ShaderId::MERC2], &m_merc_uniforms, true);
  init_shader_common(shaders[ShaderId::EMERC], &m_emerc_uniforms, false);
  m_emerc_uniforms.fade = glGetUniformLocation(shaders[ShaderId::EMERC].id(), "fade");

#ifdef __ANDROID__
  // F1a self-test (knob f1a_merc_selftest): one minimal MERC2 draw at init —
  // 3 zeroed vertices, indices {0,1,2}, bones UBO range [0,16K). The first
  // REAL merc draw SIGSEGVs inside the Adreno driver with state-legal
  // params; if THIS draw crashes too, the fault is the program+driver
  // (deferred pipeline compile of the per-vertex UBO-array indexing), fully
  // independent of game data.
  if (f1a_merc_knob("f1a_merc_selftest")) {
    GLuint vb = 0, ib = 0;
    glGenBuffers(1, &vb);
    glGenBuffers(1, &ib);
    std::vector<tfrag3::MercVertex> verts(3);
    memset(verts.data(), 0, sizeof(tfrag3::MercVertex) * 3);
    for (auto& v : verts) {
      v.weights[0] = 1.f;
    }
    glBindVertexArray(m_vao);
    glBindBuffer(GL_ARRAY_BUFFER, vb);
    glBufferData(GL_ARRAY_BUFFER, sizeof(tfrag3::MercVertex) * 3, verts.data(), GL_STATIC_DRAW);
    const u32 idx[3] = {0, 1, 2};
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ib);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, sizeof(idx), idx, GL_STATIC_DRAW);
    setup_merc_vao();
    glBindBufferRange(GL_UNIFORM_BUFFER, 1, m_bones_buffer, 0, 128 * sizeof(ShaderMercMat));
    shaders[ShaderId::MERC2].activate();
    fprintf(stderr, "F1A-MERC-SELFTEST drawing...\n");
    glDrawElements(GL_TRIANGLES, 3, GL_UNSIGNED_INT, 0);
    GLenum e = glGetError();
    glFinish();
    fprintf(stderr, "F1A-MERC-SELFTEST survived err=0x%x\n", (unsigned)e);
    glBindVertexArray(0);
    glDeleteBuffers(1, &vb);
    glDeleteBuffers(1, &ib);
  }
#endif
}

Merc2::~Merc2() {
  for (auto& x : m_mod_vtx_buffers) {
    glDeleteBuffers(1, &x.vertex);
    glDeleteVertexArrays(1, &x.vao);
  }

  glDeleteBuffers(1, &m_bones_buffer);
  glDeleteVertexArrays(1, &m_vao);
}

/*!
 * Modify vertices for blerc.
 */
void blerc_avx(const u32* i_data,
               const u32* i_data_end,
               const tfrag3::BlercFloatData* floats,
               const float* weights,
               tfrag3::MercVertex* out,
               float multiplier) {
  // store a table of weights. It's faster to load the 16-bytes of weights than load and broadcast
  // the float.
  __m128 weights_table[Merc2::kMaxBlerc];
  for (int i = 0; i < Merc2::kMaxBlerc; i++) {
    weights_table[i] = _mm_set1_ps(weights[i] * multiplier);
  }

  // loop over vertices
  while (i_data != i_data_end) {
    // load the base position
    __m128 pos = _mm_load_ps(floats->v);
    __m128 nrm = _mm_load_ps(floats->v + 4);
    floats++;

    // loop over targets
    while (*i_data != tfrag3::Blerc::kTargetIdxTerminator) {
      // get the weights for this target, from the game data.
      __m128 weight_multiplier = weights_table[*i_data];
      // get the pos/normal offset for this target.
      __m128 posm = _mm_load_ps(floats->v);
      __m128 nrmm = _mm_load_ps(floats->v + 4);
      floats++;

      // apply weights and add
      posm = _mm_mul_ps(posm, weight_multiplier);
      nrmm = _mm_mul_ps(nrmm, weight_multiplier);
      pos = _mm_add_ps(pos, posm);
      nrm = _mm_add_ps(nrm, nrmm);

      i_data++;
    }
    i_data++;

    // store final position/normal.
    _mm_store_ps(out[*i_data].pos, pos);
    _mm_store_ps(out[*i_data].normal, nrm);
    i_data++;
  }
}
namespace {
float blerc_multiplier = 1.f;
}

#ifdef OG_FEAT_HD_MODELS
// ==============================================================================================
// Grecharged-hd-eye-scale, ROUND 2 — the channel that actually makes an HD eyeball big.
//
// Round 1 compressed jak1's cartoon iris ZOOM (the sprite scale inside the 32x32 eye tile) and
// the owner's verdict on that build was "absolutely no difference: Daxter's eyes still double
// and the two eyes TOUCH". He is right, and the iris zoom cannot produce that symptom — it is a
// TEXTURE-space scale bounded by the eye's own UV footprint, so it can darken more of an eyeball
// but it can never move one eyeball's surface towards the other. A bone scale cannot either:
// both eye draws of every one of these models are rigidly skinned to ONE bone (Daxter b9, weight
// 1.0 on all 504 eye index refs, hd_merc_swap skin-stats), and a transform common to both eyes
// maps gap -> S*gap, i.e. a growing eye moves its partner away by exactly as much.
//
// blerc CAN, and does. It is a per-vertex displacement field, so it grows each eyeball about its
// OWN centre and the two inner surfaces march towards each other. And the HD pipeline hands it a
// field it was never calibrated for: tools/hd_merc_swap `port_blerc` copies the jak2/jak3 DONOR's
// authored per-vertex deltas VERBATIM (main.cpp:1434) and only re-indexes the target id onto a
// jak1 driver channel (main.cpp:1433). Nothing reconciles the donor's delta magnitude — nor its
// much rounder, much closer-set eyeballs — with jak1's weight curve
// (w = (byte - 64) * 64, bones.gc:891-897; unity is 8192, so an authored byte of 255 overdrives
// the donor's delta to 1.49x).
//
// WHY IT LANDS HARDER ON HD THAN ON THE ORIGINAL — measured at the bind on the shipped GAME.fr3:
//     Daxter original  sidekick-lod0 : eye span 583.83, the two eye clouds 404.19 apart
//     Daxter HD        dax-hd-lod0   : eye span 574.56, the two eye clouds 309.69 apart
// Same eye SIZE, but the HD pair starts 23% CLOSER together, and its donor deltas grow the eye
// about 1.7x faster per weight unit. Identical growth therefore closes the HD gap first. The
// asymmetry is geometric and inherited, not a gain any artist chose.
//
// THE FIX — a CEILING set by jak1's own model, not a blanket attenuation. Per frame and per eye
// pair, the whole eyeball blerc displacement is scaled by one factor k <= 1, chosen as the
// loosest value that keeps BOTH of the owner's symptoms inside what the ORIGINAL model reaches:
//     growth  : the eye's fractional radius change stays <= blerc_grow_cap
//     touching: the two eye clouds stay >= (1 - blerc_close_cap) * their bind distance apart
// k = 1 on every frame that is already inside both, so ordinary HD facial animation is bit-exact
// jak1 and only the pathological frames are pulled back. Nothing outside the two eyeball clouds
// is touched — lids, brows, mouth, the rest of the face and every non-HD model are untouched.
//
// The caps are the measured worst case of jak1's OWN Daxter in the same scene (leg legSTOCK,
// 110 s at village1-hut): growth +0.2629 and 19.8% closure. On the same scene the HD model
// reached +0.5588 and closed 99.92% of its gap — 0.24 units between the two eyeballs, i.e. they
// meet, which is exactly what the owner reported.
//
// An earlier cut of this damped only the DILATION mode (least-squares uniform scale about each
// eye's own centroid); the live trace refuted it: removing 70% of the dilation alone still left
// the two clouds 22.6 apart, because the donor's field TRANSLATES and SHEARS each eyeball inwards
// as much as it inflates it. The dilation `s` is still computed and reported — it is the eye's
// fractional radius change, the cross-model-comparable form of "how much bigger did it get".
// Caps of 0 (or a blerc_gain of 1.0 with both caps huge) restore jak1 exactly, bit for bit.
//
// THE INSTRUMENT. Every model that has an eye PAIR in its blerc pool is measured, HD or stock:
// per frame, the minimum vertex-to-vertex distance between the left and the right eye cloud
// after blerc, both BEFORE the fix (raw) and AFTER it. The owner's symptom is "the two eyes
// touch", so that distance is the number, and it is read off the very vertices the GPU is about
// to draw.
// ==============================================================================================
namespace {
constexpr int kEyeGapInner = 64;  // innermost verts per eye kept for the per-frame gap search

struct EyeGeom {
  bool ok = false;
  bool hd = false;
  // fingerprint: a level unload/reload can put a DIFFERENT MercEffect at the same address, and a
  // stale vertex-index list would then index a pool it does not belong to.
  size_t pool_size = 0, blerc_ints = 0;
  u8 eye_id[2] = {0xff, 0xff};    // [0] = even id (left), [1] = odd id (right)
  std::vector<u32> flex[2];       // eye verts blerc can move: the dilation basis + the fix set
  std::vector<u32> inner[2];      // the kEyeGapInner verts closest to the other eye
  float centroid[2][3] = {};      // centroid of flex[e] at bind
  float inertia[2] = {0.f, 0.f};  // sum |p - centroid|^2 over flex[e] — the dilation denominator
  float radius[2] = {0.f, 0.f};   // bind bounding-sphere radius of eye e — the socket falloff unit
  float span = 0.f;               // largest bind bbox span over the two eye clouds
  float bind_gap = 0.f;           // min vertex-to-vertex distance between the clouds at bind
};

struct EyeGapStat {
  bool hd = false;
  u64 frames = 0, att_frames = 0, bisect_frames = 0;
  float gain = 1.f, k_min = 1.f;
  float span = 0.f, bind_gap = 0.f;
  float raw_gap_min = 1e30f, gap_min = 1e30f;
  double gap_sum = 0.0;
  float raw_grow_max = 0.f, grow_max = 0.f;
};

// Scratch for the iterative close solve: the RAW blerc displacement of the flex verts, saved so a
// second candidate k can be applied from the original field instead of from an already-damped one.
// Render thread only, same single-threaded contract as s_eye_geom above; never shrinks, so the
// steady state is allocation-free.
std::vector<float> s_eye_raw;
constexpr int kCloseIters = 12;  // 2^-12 of k — far finer than the 0.01 unit the gap is printed at

std::unordered_map<const tfrag3::MercEffect*, EyeGeom> s_eye_geom;
std::map<std::string, EyeGapStat> s_eye_gap;
u64 s_eye_gap_calls = 0;
int s_eye_gap_trace = -1;  // -1 = not probed yet

float cloud_gap(const std::vector<u32>& a,
                const std::vector<u32>& b,
                const tfrag3::MercVertex* v) {
  float best = 1e30f;
  for (u32 ia : a) {
    const float* pa = v[ia].pos;
    for (u32 ib : b) {
      const float* pb = v[ib].pos;
      const float dx = pa[0] - pb[0], dy = pa[1] - pb[1], dz = pa[2] - pb[2];
      const float d2 = dx * dx + dy * dy + dz * dz;
      if (d2 < best) {
        best = d2;
      }
    }
  }
  return best >= 1e30f ? 0.f : std::sqrt(best);
}

// Same minimum-distance search over two explicit xyz point lists. The socket lives in ANOTHER
// MercEffect, whose own blerc pass overwrites the shared temp buffer, so the eyeball it is
// measured against has to be carried as points, not as indices into a buffer that is already gone.
float pts_gap(const std::vector<float>& a, const std::vector<float>& b) {
  float best = 1e30f;
  for (size_t i = 0; i + 2 < a.size(); i += 3) {
    for (size_t j = 0; j + 2 < b.size(); j += 3) {
      const float dx = a[i] - b[j], dy = a[i + 1] - b[j + 1], dz = a[i + 2] - b[j + 2];
      const float d2 = dx * dx + dy * dy + dz * dz;
      if (d2 < best) {
        best = d2;
      }
    }
  }
  return best >= 1e30f ? 0.f : std::sqrt(best);
}

// ================================================================================================
// ROUND 3 — THE SOCKET. Owner 2026-08-14 09:20, verbatim: « Certes ses yeux ne grossissent plus
// autant quand ils grossissent, mais ses eye sockets eux c'est comme avant, ce qui fait que ses
// yeux flottent dans le vide quand ils grossissent car les sockets grossissent toujours autant ! »
//
// He is right, and the cause is MEASURED, not supposed (hd_merc_swap blerc-stats on the shipped
// GAME.fr3): the eyeball and the face that holds it are driven by THE SAME blerc targets but live
// in two different MercEffects. Daxter HD effect 5 `programmer_eye_right` carries eye_id — the
// GLOBE; effect 4 `daxter-orange` carries none — the SOCKET; and target 25, the dilating one,
// moves 251 globe vertices and 836 socket vertices. Same partition on jak1's own model (effect 2
// globe / effect 0 face), so the coupling is a property of BOTH. Round 2's damping only ever
// reaches an effect that has an eye_id draw (eye_geom_for) and apply_k only walks the globe's flex
// set, so the globe was scaled by k and the socket stayed at 1. Before round 2 both were at 1 and
// moved TOGETHER: the pair was coherent even when it was too big. Round 2 broke the coupling, and
// the gap it opens is exactly (1 - k) x the socket's own displacement — largest on the frames
// where the correction bites hardest, which is what "floating in the void when they grow" means.
//
// THE COUPLING IS A FIELD, NOT A SET. A binary "socket = the vertices within R of the eye" would
// leave a damped polygon next to an undamped one, i.e. a STEP in the displacement field — the same
// class of defect the owner already rejected on Keira's hair ("des polygones qui bougent et des
// polygones voisins parfaitement statiques"). So the weight falls CONTINUOUSLY (smoothstep, zero
// slope at both ends) from 1 on the eyeball to 0 away from it, over a length derived from the
// eyeball's OWN bind radius, and every socket vertex gets k_v = 1 - w_v (1 - k). On the eyeball
// w = 1 so k_v = k; far away w = 0 so k_v = 1 and jak1's face is bit-identical. blerc_orbit = 0
// reproduces round 2 exactly and is the positive control.
//
// THE ORDER TRAP, named before it could bite. model_mod_blerc_draws walked the effects by
// increasing index and uploaded each one to the GPU right after its own blerc pass, so the socket
// (effect 4) left for the GPU before the globe (effect 5) had produced k. Reusing k in that order
// would apply the PREVIOUS frame's factor: bit-exact at rest and wrong the instant the face
// animates — undetectable by any still measurement. The loop below therefore resolves the
// eye-bearing effect FIRST.
// ================================================================================================
struct EyeSolve {
  bool armed = false;
  const tfrag3::MercEffect* eye_effect = nullptr;
  float centroid[2][3] = {};
  float radius[2] = {0.f, 0.f};
  float k = 1.f;                          // the factor the eyeball was actually scaled by
  float orbit = 0.f, r0 = 1.f, r1 = 2.f;  // how much of it the socket inherits, and over what
  float s_globe[2] = {0.f, 0.f};          // per-eye RAW dilation, for the coupling ratio
  std::vector<float> bind[2];             // the eyeball's inner cloud at bind
  std::vector<float> raw[2];              // ... as raw blerc left it
  std::vector<float> out[2];              // ... as the GPU is about to get it
};
EyeSolve s_eye_solve;

// ---------------------------------------------------------------------------------------------
// The socket side of the pair. Everything here is per NON-eye effect of the SAME model, on the
// same frame, after that effect's own blerc pass and before its upload.
// ---------------------------------------------------------------------------------------------
struct OrbitGeom {
  bool ok = false;                                 // has at least one vertex to couple
  bool meas = false;                               // has enough rim vertices to measure the seam
  size_t pool_size = 0, blerc_ints = 0;
  const tfrag3::MercEffect* eye_effect = nullptr;  // whose centroids these weights were built from
  float r0 = 0.f, r1 = 0.f;                        // and with which falloff
  std::vector<u32> vtx;                            // blerc-movable verts of this effect, w > 0
  std::vector<float> w;                            // parallel to vtx, in (0, 1]
  std::vector<u32> rim[2];                         // the socket verts nearest eye e — the seam probe
  float inertia[2] = {0.f, 0.f};                   // sum |p - c_e|^2 over rim[e]
  float bind_seam[2] = {0.f, 0.f};                 // eyeball-to-socket distance with NO blerc at all
};
std::unordered_map<const tfrag3::MercEffect*, OrbitGeom> s_orbit_geom;

// Built once per effect.  `gidx` is the level's shared merc index array; a mod draw's indices
// address the effect's OWN mod vertex pool (same convention as hd_merc_swap skin-stats).
const EyeGeom& eye_geom_for(const std::string& name,
                            const tfrag3::MercEffect& effect,
                            const std::vector<u32>& gidx) {
  auto it = s_eye_geom.find(&effect);
  if (it != s_eye_geom.end()) {
    if (it->second.pool_size == effect.mod.vertices.size() &&
        it->second.blerc_ints == effect.mod.blerc.int_data.size()) {
      return it->second;
    }
    s_eye_geom.erase(it);  // address reused by a different effect after a level swap
  }
  if (s_eye_geom.size() > 512) {
    s_eye_geom.clear();  // bounded: entries are only rebuilt on demand
    s_orbit_geom.clear();  // the socket weights are keyed on an eye effect that just went away
  }
  EyeGeom g;
  g.hd = name.find("-hd") != std::string::npos;
  g.pool_size = effect.mod.vertices.size();
  g.blerc_ints = effect.mod.blerc.int_data.size();
  const auto& pool = effect.mod.vertices;
  std::set<u32> all[2], flex[2];
  auto scan = [&](const std::vector<tfrag3::MercDraw>& draws) {
    for (const auto& d : draws) {
      if (d.eye_id == 0xff) {
        continue;
      }
      const int e = d.eye_id & 1;
      g.eye_id[e] = d.eye_id;
      for (u32 k = 0; k < d.index_count; k++) {
        const size_t ii = (size_t)d.first_index + k;
        if (ii >= gidx.size()) {
          break;
        }
        const u32 vi = gidx[ii];
        if (vi == UINT32_MAX || vi >= pool.size()) {
          continue;
        }
        all[e].insert(vi);
      }
    }
  };
  scan(effect.mod.mod_draw);
  scan(effect.mod.fix_draw);
  if (all[0].empty() || all[1].empty()) {
    return s_eye_geom.emplace(&effect, g).first->second;  // not an eye pair: never measured
  }
  // Only the vertices blerc can actually reach may be re-fitted, otherwise the correction would
  // pull STATIC eye vertices inward. int_data is [tgt..., TERMINATOR, dest] per vertex.
  {
    const auto& idat = effect.mod.blerc.int_data;
    size_t i = 0;
    while (i < idat.size()) {
      while (i < idat.size() && idat[i] != tfrag3::Blerc::kTargetIdxTerminator) {
        i++;
      }
      i++;
      if (i < idat.size()) {
        const u32 dest = idat[i++];
        for (int e = 0; e < 2; e++) {
          if (all[e].count(dest)) {
            flex[e].insert(dest);
          }
        }
      }
    }
  }
  for (int e = 0; e < 2; e++) {
    g.flex[e].assign(flex[e].begin(), flex[e].end());
    double c[3] = {0, 0, 0};
    for (u32 vi : g.flex[e]) {
      for (int a = 0; a < 3; a++) {
        c[a] += pool[vi].pos[a];
      }
    }
    if (!g.flex[e].empty()) {
      for (int a = 0; a < 3; a++) {
        g.centroid[e][a] = (float)(c[a] / (double)g.flex[e].size());
      }
    }
    double in = 0;
    for (u32 vi : g.flex[e]) {
      double d2 = 0;
      for (int a = 0; a < 3; a++) {
        const double r = pool[vi].pos[a] - g.centroid[e][a];
        d2 += r * r;
      }
      in += d2;
    }
    g.inertia[e] = (float)in;
    // span is PER EYE (the eyeball's own size), never the pair's combined bbox — the latter
    // would just re-measure the inter-eye distance.
    float mn[3] = {1e30f, 1e30f, 1e30f}, mx[3] = {-1e30f, -1e30f, -1e30f};
    float rad2 = 0.f;
    for (u32 vi : all[e]) {
      float d2 = 0.f;
      for (int a = 0; a < 3; a++) {
        mn[a] = std::min(mn[a], pool[vi].pos[a]);
        mx[a] = std::max(mx[a], pool[vi].pos[a]);
        const float r = pool[vi].pos[a] - g.centroid[e][a];
        d2 += r * r;
      }
      rad2 = std::max(rad2, d2);
    }
    // the eyeball's OWN bind radius about its OWN centroid: the length the socket falloff is
    // expressed in, so nothing about the coupling is a number picked in absolute model units.
    g.radius[e] = std::sqrt(rad2);
    g.span = std::max({g.span, mx[0] - mn[0], mx[1] - mn[1], mx[2] - mn[2]});
  }
  // bind gap over the FULL clouds (exact, once), and the inner subsets used per frame
  std::vector<u32> a0(all[0].begin(), all[0].end()), a1(all[1].begin(), all[1].end());
  g.bind_gap = cloud_gap(a0, a1, pool.data());
  for (int e = 0; e < 2; e++) {
    const float* other = g.centroid[1 - e];
    std::vector<std::pair<float, u32>> rank;
    const std::set<u32>& src = all[e];
    for (u32 vi : src) {
      float d2 = 0;
      for (int a = 0; a < 3; a++) {
        const float d = pool[vi].pos[a] - other[a];
        d2 += d * d;
      }
      rank.push_back({d2, vi});
    }
    std::sort(rank.begin(), rank.end());
    for (size_t k = 0; k < rank.size() && k < (size_t)kEyeGapInner; k++) {
      g.inner[e].push_back(rank[k].second);
    }
  }
  g.ok = !g.flex[0].empty() && !g.flex[1].empty() && g.inertia[0] > 0.f && g.inertia[1] > 0.f;
  lg::info(
      "[eyegap] geom model={} hd={} eyes={}/{} flex={}/{} span={:.2f} rad={:.2f}/{:.2f} "
      "bind_gap={:.2f} ok={}",
      name, (int)g.hd, g.eye_id[0], g.eye_id[1], g.flex[0].size(), g.flex[1].size(), g.span,
      g.radius[0], g.radius[1], g.bind_gap, (int)g.ok);
  return s_eye_geom.emplace(&effect, g).first->second;
}

// Runs on the render thread right after blerc_avx and before the upload, so `out` is exactly
// what the GPU is about to draw.
void eye_blerc_measure_and_damp(const std::string& name,
                                const tfrag3::MercEffect& effect,
                                const std::vector<u32>& gidx,
                                tfrag3::MercVertex* out) {
  const EyeGeom& g = eye_geom_for(name, effect, gidx);
  if (!g.ok) {
    return;
  }
  if (s_eye_gap_trace < 0) {
    s_eye_gap_trace = getenv("OG_EYEGAP_TRACE") ? 1 : 0;
  }
  const auto& pool = effect.mod.vertices;
  // A non-HD model is MEASURED, never touched: orbit 0 means its socket inherits nothing, while
  // valid falloff radii keep its socket instrumented — that is what makes it a reference and not
  // a second treatment. (Leaving the radii at 0 would silently drop the stock socket reading.)
  HdEyeBlercCaps cap{1.f, 1e9f, 1e9f, 0.f, 1.f, 2.f};
  if (g.hd) {
    cap = hd_eye_blerc_caps(g.eye_id[0]);
  }

  // (1) the RAW numbers, off the blerc output exactly as jak1 + the donor produced it
  const float raw_gap = cloud_gap(g.inner[0], g.inner[1], out);
  // dilation mode per eye: with the centroid as origin sum(r_i) = 0, so a rigid translation drops
  // out of the fit and `s` is purely the eye's fractional radius change.
  float s_eye[2] = {0.f, 0.f};
  for (int e = 0; e < 2; e++) {
    double num = 0;
    for (u32 vi : g.flex[e]) {
      const float* p = pool[vi].pos;
      const float* c = out[vi].pos;
      for (int a = 0; a < 3; a++) {
        num += (double)(c[a] - p[a]) * (double)(p[a] - g.centroid[e][a]);
      }
    }
    s_eye[e] = (float)(num / (double)g.inertia[e]);
  }
  const float raw_grow = std::max(s_eye[0], s_eye[1]);

  // Carry the eyeball's inner cloud out of this effect. The socket is a DIFFERENT MercEffect and
  // its own blerc pass reuses the same temp buffer, so by the time the seam can be measured these
  // vertices no longer exist anywhere else. bind = the defect-absent reading, raw = what jak1 plus
  // the donor produce, out = what the GPU is handed.
  for (int e = 0; e < 2; e++) {
    s_eye_solve.bind[e].clear();
    s_eye_solve.raw[e].clear();
    for (u32 vi : g.inner[e]) {
      for (int a = 0; a < 3; a++) {
        s_eye_solve.bind[e].push_back(pool[vi].pos[a]);
      }
      for (int a = 0; a < 3; a++) {
        s_eye_solve.raw[e].push_back(out[vi].pos[a]);
      }
    }
  }

  // (2) the loosest k <= 1 that puts BOTH symptoms inside jak1's own ceiling.
  const float floor_gap = g.bind_gap * (1.f - cap.close);
  float k = 1.f;
  bool solve_close = false;
  if (g.hd) {
    k = std::min(k, cap.gain);
    // GROWTH is exactly linear in k: the dilation fit is linear in the displacement, so scaling
    // the field by k scales `s` by k. One division is the exact answer, no iteration needed.
    if (raw_grow > cap.grow && raw_grow > 1e-6f) {
      k = std::min(k, cap.grow / raw_grow);
    }
    // DISTANCE is not. The gap is a MINIMUM over vertex pairs, and the pair that realises it
    // changes as the field is scaled, so the closed form below is only a first guess — it was
    // the whole solve until 2026-08-11, when the x86 leg measured what it actually delivers:
    // ceiling asked for 19.80% closure, Daxter HD came out at 25.38%, i.e. 28% past a number
    // that is supposed to be a ceiling. A bound that is only approximately held is not a bound,
    // and this is the owner's headline symptom ("les deux yeux se TOUCHENT"), so it is solved
    // exactly below instead of being traded against a looser cap in the data.
    if (raw_gap < floor_gap && g.bind_gap > raw_gap + 1e-4f) {
      k = std::min(k, (g.bind_gap - floor_gap) / (g.bind_gap - raw_gap));
      solve_close = true;
    }
    if (k < 0.f) {
      k = 0.f;
    }
  }
  const bool damped = k < 0.9999f;
  // Any candidate k must be applied to the RAW field, not to an already-damped one, so snapshot
  // it before the first write.
  if (damped) {
    s_eye_raw.clear();
    for (int e = 0; e < 2; e++) {
      for (u32 vi : g.flex[e]) {
        for (int a = 0; a < 3; a++) {
          s_eye_raw.push_back(out[vi].pos[a]);
        }
      }
    }
  }
  auto apply_k = [&](float kk) {
    size_t j = 0;
    for (int e = 0; e < 2; e++) {
      for (u32 vi : g.flex[e]) {
        const float* p = pool[vi].pos;
        float* c = out[vi].pos;
        for (int a = 0; a < 3; a++, j++) {
          c[a] = p[a] + kk * (s_eye_raw[j] - p[a]);
        }
      }
    }
  };
  int bisect_used = 0;
  if (damped) {
    apply_k(k);
    // Bisect on the REAL distance. The bracket is valid by construction: inner[] is a SUBSET of
    // the cloud bind_gap was minimised over, so gap(0) >= bind_gap >= floor_gap — k=0 is always
    // admissible — while the guess above is the only candidate that can violate. Each halving is
    // one 64x64 distance search on the <=41 frames per thousand that need it at all.
    if (solve_close && cloud_gap(g.inner[0], g.inner[1], out) < floor_gap) {
      float lo = 0.f, hi = k;
      for (int it = 0; it < kCloseIters; it++) {
        const float mid = 0.5f * (lo + hi);
        apply_k(mid);
        if (cloud_gap(g.inner[0], g.inner[1], out) >= floor_gap) {
          lo = mid;
        } else {
          hi = mid;
        }
        bisect_used++;
      }
      k = lo;
      apply_k(k);
    }
  }
  const float out_grow = k * raw_grow;

  // Hand the solved factor to the socket pass. `armed` is cleared per model, so a socket can only
  // ever inherit the k of the eyeball of ITS OWN model, on THIS frame.
  s_eye_solve.armed = true;
  s_eye_solve.eye_effect = &effect;
  s_eye_solve.k = k;
  s_eye_solve.orbit = g.hd ? cap.orbit : 0.f;
  s_eye_solve.r0 = cap.orbit_r0;
  s_eye_solve.r1 = cap.orbit_r1;
  for (int e = 0; e < 2; e++) {
    s_eye_solve.radius[e] = g.radius[e];
    s_eye_solve.s_globe[e] = s_eye[e];
    for (int a = 0; a < 3; a++) {
      s_eye_solve.centroid[e][a] = g.centroid[e][a];
    }
    s_eye_solve.out[e].clear();
    for (u32 vi : g.inner[e]) {
      for (int a = 0; a < 3; a++) {
        s_eye_solve.out[e].push_back(out[vi].pos[a]);
      }
    }
  }

  // (3) the gap the GPU will actually get
  const float out_gap = damped ? cloud_gap(g.inner[0], g.inner[1], out) : raw_gap;

  auto& st = s_eye_gap[name];
  st.hd = g.hd;
  st.gain = g.hd ? cap.gain : 1.f;
  st.span = g.span;
  st.bind_gap = g.bind_gap;
  st.frames++;
  st.att_frames += damped ? 1 : 0;
  st.bisect_frames += bisect_used ? 1 : 0;
  st.k_min = std::min(st.k_min, k);
  st.raw_gap_min = std::min(st.raw_gap_min, raw_gap);
  st.gap_min = std::min(st.gap_min, out_gap);
  st.gap_sum += out_gap;
  st.raw_grow_max = std::max(st.raw_grow_max, raw_grow);
  st.grow_max = std::max(st.grow_max, out_grow);
  if (s_eye_gap_trace) {
    lg::info(
        "[eyegap-f] n={} model={} raw_gap={:.2f} gap={:.2f} raw_grow={:.4f} grow={:.4f} k={:.4f} "
        "bis={}",
        s_eye_gap_calls, name, raw_gap, out_gap, raw_grow, out_grow, k, bisect_used);
  }
}


struct OrbitStat {
  u64 frames = 0, coupled = 0;
  float k_min = 1.f;
  float bind_seam = 0.f;
  // the coupling itself: s_socket / s_globe must not be changed by the damping — that IS what
  // "coupled" means, and publishing only one of the two is what let round 2 read as green.
  double ratio_raw_sum = 0.0, ratio_out_sum = 0.0;
  u64 ratio_n = 0;
  float s_globe_raw_max = 0.f, s_globe_out_max = 0.f;
  float s_orbit_raw_max = 0.f, s_orbit_out_max = 0.f;
  // seam error against the PREDICTION seam_bind + k (seam_raw - seam_bind): scaling a coupled pair
  // by k must move its seam by k too. `half` is the socket left undamped = round 2 = the defect.
  float err_half_max = 0.f, err_out_max = 0.f;
  float seam_half_max = 0.f, seam_out_max = 0.f;
};
std::map<std::string, OrbitStat> s_orbit_stat;

// Weights are a function of the eyeball's bind geometry only, so they are built once per effect
// and reused. The key carries the eye effect and the two radii: a level swap that reuses the
// address, or a data retune of the falloff, must not silently keep an old field.
const OrbitGeom& orbit_geom_for(const tfrag3::MercEffect& effect) {
  auto it = s_orbit_geom.find(&effect);
  if (it != s_orbit_geom.end()) {
    const OrbitGeom& c = it->second;
    if (c.pool_size == effect.mod.vertices.size() &&
        c.blerc_ints == effect.mod.blerc.int_data.size() &&
        c.eye_effect == s_eye_solve.eye_effect && c.r0 == s_eye_solve.r0 &&
        c.r1 == s_eye_solve.r1) {
      return c;
    }
    s_orbit_geom.erase(it);
  }
  if (s_orbit_geom.size() > 512) {
    s_orbit_geom.clear();
  }
  OrbitGeom o;
  o.pool_size = effect.mod.vertices.size();
  o.blerc_ints = effect.mod.blerc.int_data.size();
  o.eye_effect = s_eye_solve.eye_effect;
  o.r0 = s_eye_solve.r0;
  o.r1 = s_eye_solve.r1;
  const auto& pool = effect.mod.vertices;
  std::vector<std::pair<float, u32>> rank[2];
  // Only vertices blerc can actually MOVE are candidates: a static face vertex has nothing to
  // damp, and re-fitting it would drag geometry the cartoon effect never touched.
  const auto& idat = effect.mod.blerc.int_data;
  size_t i = 0;
  while (i < idat.size()) {
    while (i < idat.size() && idat[i] != tfrag3::Blerc::kTargetIdxTerminator) {
      i++;
    }
    i++;
    if (i >= idat.size()) {
      break;
    }
    const u32 dest = idat[i++];
    if (dest >= pool.size()) {
      continue;
    }
    int best_e = 0;
    float best_d = 1e30f;
    for (int e = 0; e < 2; e++) {
      if (s_eye_solve.radius[e] <= 1e-6f) {
        continue;
      }
      float d2 = 0.f;
      for (int a = 0; a < 3; a++) {
        const float r = pool[dest].pos[a] - s_eye_solve.centroid[e][a];
        d2 += r * r;
      }
      const float d = std::sqrt(d2) / s_eye_solve.radius[e];
      if (d < best_d) {
        best_d = d;
        best_e = e;
      }
    }
    if (best_d >= o.r1) {
      continue;  // jak1's face out here is bit-identical, by construction
    }
    float wgt = 1.f;
    if (best_d > o.r0) {
      const float u = (o.r1 - best_d) / (o.r1 - o.r0);
      wgt = u * u * (3.f - 2.f * u);  // smoothstep: value AND slope are 0 at r1, 1 at r0
    }
    if (wgt <= 1e-4f) {
      continue;
    }
    o.vtx.push_back(dest);
    o.w.push_back(wgt);
    if (wgt > 0.5f) {
      rank[best_e].push_back({best_d, dest});
    }
  }
  for (int e = 0; e < 2; e++) {
    std::sort(rank[e].begin(), rank[e].end());
    for (size_t r = 0; r < rank[e].size() && r < (size_t)kEyeGapInner; r++) {
      o.rim[e].push_back(rank[e][r].second);
    }
    double in = 0;
    std::vector<float> pts;
    for (u32 vi : o.rim[e]) {
      double d2 = 0;
      for (int a = 0; a < 3; a++) {
        const double r = pool[vi].pos[a] - s_eye_solve.centroid[e][a];
        d2 += r * r;
        pts.push_back(pool[vi].pos[a]);
      }
      in += d2;
    }
    o.inertia[e] = (float)in;
    o.bind_seam[e] = pts_gap(s_eye_solve.bind[e], pts);
  }
  o.ok = !o.vtx.empty();
  o.meas = o.rim[0].size() >= 4 && o.rim[1].size() >= 4 && o.inertia[0] > 0.f && o.inertia[1] > 0.f;
  lg::info(
      "[eyeorb] geom verts={} rim={}/{} r0={:.2f} r1={:.2f} bind_seam={:.3f}/{:.3f} ok={} meas={}",
      o.vtx.size(), o.rim[0].size(), o.rim[1].size(), o.r0, o.r1, o.bind_seam[0], o.bind_seam[1],
      (int)o.ok, (int)o.meas);
  return s_orbit_geom.emplace(&effect, o).first->second;
}

void orbit_blerc_couple(const std::string& name,
                        const tfrag3::MercEffect& effect,
                        tfrag3::MercVertex* out) {
  if (!s_eye_solve.armed || &effect == s_eye_solve.eye_effect ||
      effect.mod.blerc.int_data.empty()) {
    return;
  }
  const OrbitGeom& o = orbit_geom_for(effect);
  if (!o.ok) {
    return;
  }
  const auto& pool = effect.mod.vertices;
  const float k = s_eye_solve.k;
  const float orb = s_eye_solve.orbit;

  // (1) the socket as round 2 leaves it: moved by the full donor field while the globe next to it
  // has already been pulled back to k. This is the owner's defect, read on the same frame.
  float s_orb_raw[2] = {0.f, 0.f}, seam_raw[2] = {0.f, 0.f}, seam_half[2] = {0.f, 0.f};
  std::vector<float> pts;
  for (int e = 0; e < 2 && o.meas; e++) {
    double num = 0;
    pts.clear();
    for (u32 vi : o.rim[e]) {
      const float* p = pool[vi].pos;
      const float* c = out[vi].pos;
      for (int a = 0; a < 3; a++) {
        num += (double)(c[a] - p[a]) * (double)(p[a] - s_eye_solve.centroid[e][a]);
        pts.push_back(c[a]);
      }
    }
    s_orb_raw[e] = (float)(num / (double)o.inertia[e]);
    seam_raw[e] = pts_gap(s_eye_solve.raw[e], pts);
    seam_half[e] = pts_gap(s_eye_solve.out[e], pts);
  }

  // (2) the coupling. k_v = 1 - w_v (1 - k) x orbit — an identity wherever w is 0, so jak1's face
  // away from the eyes is bit-for-bit untouched, and an identity everywhere when k is already 1.
  const bool couple = k < 0.9999f && orb > 0.f;
  if (couple) {
    for (size_t j = 0; j < o.vtx.size(); j++) {
      const u32 vi = o.vtx[j];
      const float kv = 1.f - o.w[j] * (1.f - k) * orb;
      const float* p = pool[vi].pos;
      float* c = out[vi].pos;
      for (int a = 0; a < 3; a++) {
        c[a] = p[a] + kv * (c[a] - p[a]);
      }
    }
  }

  // (3) the socket the GPU actually gets
  float s_orb_out[2] = {0.f, 0.f}, seam_out[2] = {0.f, 0.f};
  for (int e = 0; e < 2 && o.meas; e++) {
    if (!couple) {
      s_orb_out[e] = s_orb_raw[e];
      seam_out[e] = seam_half[e];
      continue;
    }
    double num = 0;
    pts.clear();
    for (u32 vi : o.rim[e]) {
      const float* p = pool[vi].pos;
      const float* c = out[vi].pos;
      for (int a = 0; a < 3; a++) {
        num += (double)(c[a] - p[a]) * (double)(p[a] - s_eye_solve.centroid[e][a]);
        pts.push_back(c[a]);
      }
    }
    s_orb_out[e] = (float)(num / (double)o.inertia[e]);
    seam_out[e] = pts_gap(s_eye_solve.out[e], pts);
  }

  if (!o.meas) {
    return;
  }
  auto& st = s_orbit_stat[name];
  st.frames++;
  st.coupled += couple ? 1 : 0;
  st.k_min = std::min(st.k_min, k);
  st.bind_seam = 0.5f * (o.bind_seam[0] + o.bind_seam[1]);
  for (int e = 0; e < 2; e++) {
    const float sg_raw = s_eye_solve.s_globe[e], sg_out = k * s_eye_solve.s_globe[e];
    st.s_globe_raw_max = std::max(st.s_globe_raw_max, sg_raw);
    st.s_globe_out_max = std::max(st.s_globe_out_max, sg_out);
    st.s_orbit_raw_max = std::max(st.s_orbit_raw_max, s_orb_raw[e]);
    st.s_orbit_out_max = std::max(st.s_orbit_out_max, s_orb_out[e]);
    if (std::abs(sg_raw) > 1e-3f && std::abs(sg_out) > 1e-6f) {
      st.ratio_raw_sum += s_orb_raw[e] / sg_raw;
      st.ratio_out_sum += s_orb_out[e] / sg_out;
      st.ratio_n++;
    }
    // scaling a COUPLED pair by k moves its seam by k: this is a prediction, not a ratio to a
    // baseline that drifts, and both candidates are judged against the same number.
    const float pred = o.bind_seam[e] + k * (seam_raw[e] - o.bind_seam[e]);
    st.err_half_max = std::max(st.err_half_max, std::abs(seam_half[e] - pred));
    st.err_out_max = std::max(st.err_out_max, std::abs(seam_out[e] - pred));
    st.seam_half_max = std::max(st.seam_half_max, seam_half[e]);
    st.seam_out_max = std::max(st.seam_out_max, seam_out[e]);
  }
  if (s_eye_gap_trace) {
    lg::info(
        "[eyeorb-f] n={} model={} k={:.4f} orbit={:.3f} sg_raw={:.4f} sg_out={:.4f} "
        "so_raw={:.4f} so_out={:.4f} seam_bind={:.3f} seam_raw={:.3f} seam_half={:.3f} "
        "seam_out={:.3f}",
        s_eye_gap_calls, name, k, orb, s_eye_solve.s_globe[0], k * s_eye_solve.s_globe[0],
        s_orb_raw[0], s_orb_out[0], o.bind_seam[0], seam_raw[0], seam_half[0], seam_out[0]);
  }
}

void eye_blerc_heartbeat() {
  if (++s_eye_gap_calls % 600) {
    return;
  }
  for (const auto& [nm, st] : s_eye_gap) {
    if (!st.frames) {
      continue;
    }
    lg::info(
        "[eyegap] model={} hd={} gain={:.3f} frames={} damped={} bisect={} span={:.2f} "
        "bind_gap={:.2f} raw_gap_min={:.2f} gap_min={:.2f} gap_mean={:.2f} raw_grow_max={:.4f} "
        "grow_max={:.4f} raw_close={:.4f} close={:.4f}",
        nm, (int)st.hd, st.gain, st.frames, st.att_frames, st.bisect_frames, st.span, st.bind_gap,
        st.raw_gap_min, st.gap_min, st.gap_sum / (double)st.frames, st.raw_grow_max, st.grow_max,
        st.bind_gap > 0.f ? 1.f - st.raw_gap_min / st.bind_gap : 0.f,
        st.bind_gap > 0.f ? 1.f - st.gap_min / st.bind_gap : 0.f);
  }
  for (const auto& [nm, st] : s_orbit_stat) {
    if (!st.frames) {
      continue;
    }
    lg::info(
        "[eyeorb] model={} frames={} coupled={} k_min={:.4f} seam_bind={:.3f} "
        "s_globe_raw_max={:.4f} s_globe_out_max={:.4f} s_orbit_raw_max={:.4f} "
        "s_orbit_out_max={:.4f} ratio_raw={:.4f} ratio_out={:.4f} seam_half_max={:.3f} "
        "seam_out_max={:.3f} err_half_max={:.3f} err_out_max={:.3f}",
        nm, st.frames, st.coupled, st.k_min, st.bind_seam, st.s_globe_raw_max,
        st.s_globe_out_max, st.s_orbit_raw_max, st.s_orbit_out_max,
        st.ratio_n ? st.ratio_raw_sum / (double)st.ratio_n : 0.0,
        st.ratio_n ? st.ratio_out_sum / (double)st.ratio_n : 0.0, st.seam_half_max,
        st.seam_out_max, st.err_half_max, st.err_out_max);
  }
}
}  // namespace
#endif

void Merc2::model_mod_blerc_draws(int num_effects,
                                  const tfrag3::MercModel* model,
                                  const LevelData* lev,
                                  ModBuffers* mod_opengl_buffers,
                                  const float* blerc_weights,
                                  MercDebugStats* stats) {
  int eye_first = -1;
#ifdef OG_FEAT_HD_MODELS
  // A model's eyeball and the socket around it are DIFFERENT effects driven by the SAME blerc
  // targets, and each effect is uploaded to the GPU right after its own blerc pass. In source
  // order the socket would therefore leave before the eyeball's factor k exists, and reusing k
  // would silently apply the PREVIOUS frame's value — exact at rest, wrong as soon as the face
  // animates. So the eye-bearing effect is resolved FIRST and every other effect follows.
  s_eye_solve.armed = false;  // a socket may only ever inherit the k of its OWN model, this frame
  for (int ei = 0; ei < num_effects && eye_first < 0; ei++) {
    const auto& e = model->effects[ei];
    if (e.mod.mod_draw.empty()) {
      continue;
    }
    for (const auto* dl : {&e.mod.mod_draw, &e.mod.fix_draw}) {
      for (const auto& d : *dl) {
        if (d.eye_id != 0xff) {
          eye_first = ei;
          break;
        }
      }
      if (eye_first >= 0) {
        break;
      }
    }
  }
#endif
  // loop over effects. Pass 0 is the eye-bearing effect alone (none when eye_first < 0), pass 1 is
  // everything else, in source order — so the ordinary path is byte-for-byte the old one.
  for (int pass = 0; pass < 2; pass++) {
  for (int ei = 0; ei < num_effects; ei++) {
    if ((pass == 0) != (ei == eye_first)) {
      continue;
    }
    const auto& effect = model->effects[ei];
    // some effects might have no mod draw info, and no modifiable vertices
    if (effect.mod.mod_draw.empty()) {
      continue;
    }

    // grab opengl buffer
    auto opengl_buffers = alloc_mod_vtx_buffer(lev);
    mod_opengl_buffers[ei] = opengl_buffers;

    // check that we have enough room for the finished thing.
    if (effect.mod.vertices.size() > MAX_MOD_VTX) {
      fmt::print("More mod vertices than MAX_MOD_VTX. {} > {}\n", effect.mod.vertices.size(),
                 MAX_MOD_VTX);
      ASSERT_NOT_REACHED();
    }

    // start with the correct vertices from the model data:
    memcpy(m_mod_vtx_temp.data(), effect.mod.vertices.data(),
           sizeof(tfrag3::MercVertex) * effect.mod.vertices.size());

    // do blerc math
    const auto* f_data = effect.mod.blerc.float_data.data();
    const u32* i_data = effect.mod.blerc.int_data.data();
    const u32* i_data_end = i_data + effect.mod.blerc.int_data.size();
    blerc_avx(i_data, i_data_end, f_data, blerc_weights, m_mod_vtx_temp.data(), blerc_multiplier);

#ifdef OG_FEAT_HD_MODELS
    // Grecharged-hd-eye-scale round 2: measure the two eyes' edge-to-edge distance on the
    // vertices that are about to be uploaded, and damp the DILATION mode on HD eyes only.
    // Round 3: and hand that same factor, continuously faded, to the SOCKET in the sibling
    // effects — round 2 damped one half of a coupled pair and the owner saw the eye come loose.
    if (ei == eye_first) {
      eye_blerc_measure_and_damp(model->name, effect, lev->level->merc_data.indices,
                                 m_mod_vtx_temp.data());
    } else {
      orbit_blerc_couple(model->name, effect, m_mod_vtx_temp.data());
    }
#endif

    // and upload to GPU
    stats->num_uploads++;
    stats->num_upload_bytes += effect.mod.vertices.size() * sizeof(tfrag3::MercVertex);
    {
      glBindBuffer(GL_ARRAY_BUFFER, opengl_buffers.vertex);
      glBufferData(GL_ARRAY_BUFFER, effect.mod.vertices.size() * sizeof(tfrag3::MercVertex),
                   m_mod_vtx_temp.data(), GL_DYNAMIC_DRAW);
    }
  }
  }
#ifdef OG_FEAT_HD_MODELS
  eye_blerc_heartbeat();
#endif
}

// We can run into a problem where adding a PC model would overflow the
// preallocated draw/bone buffers.
// So we break this part into two functions:
// - init_pc_model, which doesn't allocate bones/draws

void Merc2::model_mod_draws(int num_effects,
                            const tfrag3::MercModel* model,
                            const LevelData* lev,
                            const u8* input_data,
                            const u8* ee_base,
                            ModBuffers* mod_opengl_buffers,
                            MercDebugStats* stats) {
  auto p = scoped_prof("update-verts");

  // loop over effects. Mod vertices are done per effect (possibly a bad idea?)
  for (int ei = 0; ei < num_effects; ei++) {
    const auto& effect = model->effects[ei];
    // some effects might have no mod draw info, and no modifiable vertices
    if (effect.mod.mod_draw.empty()) {
      continue;
    }

    prof().begin_event("start1");
    // grab opengl buffer
    auto opengl_buffers = alloc_mod_vtx_buffer(lev);
    mod_opengl_buffers[ei] = opengl_buffers;

    // check that we have enough room for the finished thing.
    if (effect.mod.vertices.size() > MAX_MOD_VTX) {
      fmt::print("More mod vertices than MAX_MOD_VTX. {} > {}\n", effect.mod.vertices.size(),
                 MAX_MOD_VTX);
      ASSERT_NOT_REACHED();
    }

    // check that we have enough room for unpack
    if (effect.mod.expect_vidx_end > MAX_MOD_VTX) {
      fmt::print("More mod vertices (temp) than MAX_MOD_VTX. {} > {}\n", effect.mod.expect_vidx_end,
                 MAX_MOD_VTX);
      ASSERT_NOT_REACHED();
    }

    // start with the "correct" vertices from the model data:
    memcpy(m_mod_vtx_temp.data(), effect.mod.vertices.data(),
           sizeof(tfrag3::MercVertex) * effect.mod.vertices.size());

    // get pointers to the fragment and fragment control data
    u32 goal_addr;
    memcpy(&goal_addr, input_data + 4 * ei, 4);
    // The EE base, NOT reconstructed from the transfer pointer: under chain
    // copy-mode (Android, A42) setup.data points into the copy buffer and the
    // merc fragment data referenced by GOAL address lives outside the copied
    // chain. On desktop zero-copy this is the identical pointer
    // (setup.data - setup.data_offset == g_ee_main_mem).
    const u8* ee0 = ee_base;
    const u8* merc_effect = ee0 + goal_addr;
    u16 frag_cnt;
    memcpy(&frag_cnt, merc_effect + 18, 2);
    ASSERT(frag_cnt >= effect.mod.fragment_mask.size());
    u32 frag_goal;
    memcpy(&frag_goal, merc_effect, 4);
    u32 frag_ctrl_goal;
    memcpy(&frag_ctrl_goal, merc_effect + 4, 4);
    const u8* frag = ee0 + frag_goal;
    const u8* frag_ctrl = ee0 + frag_ctrl_goal;

    // loop over frags
    u32 vidx = 0;
    // u32 st_vif_add = model->st_vif_add;
    float xyz_scale = model->xyz_scale;
    prof().end_event();
    {
      // we're going to look at data that the game may be modifying.
      // in the original game, they didn't have any lock, but I think that the
      // scratchpad access from the EE would effectively block the VIF1 DMA, so you'd
      // hopefully never get a partially updated model (which causes obvious holes).
      // this lock is not ideal, and can block the rendering thread while blerc_execute runs,
      // which can take up to 2ms on really blerc-heavy scenes
      std::unique_lock<std::mutex> lk(g_merc_data_mutex);
      [[maybe_unused]] int frags_done = 0;
      auto p = scoped_prof("vert-math");

      // loop over fragments
      for (u32 fi = 0; fi < effect.mod.fragment_mask.size(); fi++) {
        frags_done++;
        u8 mat_xfer_count = frag_ctrl[3];

        // we create a mask of fragments to skip because they have no vertices.
        // the indexing data assumes that we skip the other fragments.
        if (effect.mod.fragment_mask[fi]) {
          // read fragment metadata
          u8 unsigned_four_count = frag_ctrl[0];
          u8 lump_four_count = frag_ctrl[1];
          u32 mm_qwc_off = frag[10];
          float float_offsets[3];
          memcpy(float_offsets, &frag[mm_qwc_off * 16], 12);
          u32 my_u4_count = ((unsigned_four_count + 3) / 4) * 16;
          u32 my_l4_count = my_u4_count + ((lump_four_count + 3) / 4) * 16;

          // loop over vertices in the fragment and unpack
          for (u32 w = my_u4_count / 4; w < (my_l4_count / 4) - 2; w += 3) {
            // positions
            u32 q0w = 0x4b010000 + frag[w * 4 + (0 * 4) + 3];
            u32 q1w = 0x4b010000 + frag[w * 4 + (1 * 4) + 3];
            u32 q2w = 0x4b010000 + frag[w * 4 + (2 * 4) + 3];

            // normals
            u32 q0z = 0x47800000 + frag[w * 4 + (0 * 4) + 2];
            u32 q1z = 0x47800000 + frag[w * 4 + (1 * 4) + 2];
            u32 q2z = 0x47800000 + frag[w * 4 + (2 * 4) + 2];

            // uvs
            u32 q2x = model->st_vif_add + frag[w * 4 + (2 * 4) + 0];
            u32 q2y = model->st_vif_add + frag[w * 4 + (2 * 4) + 1];

            auto* pos_array = m_mod_vtx_unpack_temp[vidx].pos;
            memcpy(&pos_array[0], &q0w, 4);
            memcpy(&pos_array[1], &q1w, 4);
            memcpy(&pos_array[2], &q2w, 4);
            pos_array[0] += float_offsets[0];
            pos_array[1] += float_offsets[1];
            pos_array[2] += float_offsets[2];
            pos_array[0] *= xyz_scale;
            pos_array[1] *= xyz_scale;
            pos_array[2] *= xyz_scale;

            auto* nrm_array = m_mod_vtx_unpack_temp[vidx].nrm;
            memcpy(&nrm_array[0], &q0z, 4);
            memcpy(&nrm_array[1], &q1z, 4);
            memcpy(&nrm_array[2], &q2z, 4);
            nrm_array[0] += -65537;
            nrm_array[1] += -65537;
            nrm_array[2] += -65537;

            auto* uv_array = m_mod_vtx_unpack_temp[vidx].uv;
            memcpy(&uv_array[0], &q2x, 4);
            memcpy(&uv_array[1], &q2y, 4);
            uv_array[0] += model->st_magic;
            uv_array[1] += model->st_magic;

            vidx++;
          }
        }

        // next control
        frag_ctrl += 4 + 2 * mat_xfer_count;

        // next frag
        u32 mm_qwc_count = frag[11];
        frag += mm_qwc_count * 16;
      }

      // sanity check
      if (effect.mod.expect_vidx_end != vidx) {
        fmt::print("---------- BAD {}/{}\n", effect.mod.expect_vidx_end, vidx);
        ASSERT(false);
      }
    }

    {
      auto pp = scoped_prof("copy");
      // now copy the data in merc original vertex order to the output.
      for (u32 vi = 0; vi < effect.mod.vertices.size(); vi++) {
        u32 addr = effect.mod.vertex_lump4_addr[vi];
        if (addr < vidx) {
          memcpy(&m_mod_vtx_temp[vi], &m_mod_vtx_unpack_temp[addr], 32);
          m_mod_vtx_temp[vi].st[0] = m_mod_vtx_unpack_temp[addr].uv[0];
          m_mod_vtx_temp[vi].st[1] = m_mod_vtx_unpack_temp[addr].uv[1];
        }
      }
    }

    // and upload to GPU
    stats->num_uploads++;
    stats->num_upload_bytes += effect.mod.vertices.size() * sizeof(tfrag3::MercVertex);
    {
      auto pp = scoped_prof("update-verts-upload");
      glBindBuffer(GL_ARRAY_BUFFER, opengl_buffers.vertex);
      glBufferData(GL_ARRAY_BUFFER, effect.mod.vertices.size() * sizeof(tfrag3::MercVertex),
                   m_mod_vtx_temp.data(), GL_DYNAMIC_DRAW);
    }
  }
}

#ifdef OG_FEAT_HD_MODELS
// Grecharged-hd-models4: PER-ACTOR coverage. The M1 suppression was global (any jak-hd submit
// armed a name-TTL that dropped EVERY 'eichar-lod0' packet) — which blanked the ND-logo's eichar
// actor, an actor no companion covered. Now: GOAL registers companion-pid -> driver-pid at spawn
// (pc-hd-cover!) and unregisters at despawn (pc-hd-uncover!); every pc-merc packet carries its
// owner process pid (bones.gc writes it at name+120); a driver's stock draw is suppressed ONLY
// while its own companion's packet is actually processed with the HD model FOUND (per-driver TTL
// refreshed in handle_pc_model, drained once per render()). No coverage => stock draw survives,
// so an uncovered actor can never be suppressed into invisibility.
struct HdCoverPair {
  u32 companion_pid;
  u32 driver_pid;
};
static std::mutex s_hd_cover_mutex;  // pairs: written EE-thread (GOAL), read render-thread
static std::vector<HdCoverPair> s_hd_cover_pairs;
static std::unordered_map<u32, int> s_hd_driver_ttl;  // render-thread only

// CYCLE-3 FLICKER DETECTOR (metrics not eyeballs). AVERTISSEMENT, MESURE LE 2026-09-01 : ce
// detecteur ne voit QUE les acteurs couverts par un modele HD, et son compteur `gaps` ne peut se
// declencher que sur une fenetre de 25 a 32 appels de rendu (`gap > 24 && gap < 4000`), car toute
// absence plus longue efface sa propre trace (`s_hd_last_arm_call` est efface a l'expiration du
// TTL et au fail-open). Une disparition de 3 images ou plus n'y apparait donc nulle part sauf
// dans `expiries`, qui n'a jamais ete gate. Le recensement qui porte le verdict est desormais
// game/system/npc_flicker.cpp. jak1 makes 16 Merc2::render calls per frame
// (16 Merc2BucketRenderers sharing this instance), so TTL 32 = ~2 frames and a healthy covered
// actor re-arms every ~16 calls. Counters are always on; logging is event-driven + a periodic
// heartbeat, so a healthy run stays quiet and the cutscene proof leg can grep blackouts=0.
static u64 s_hd_render_call_idx = 0;                       // render-thread only
static std::unordered_map<u32, u64> s_hd_last_arm_call;    // driver_pid -> render call idx
static u64 s_hd_submit_gap_events = 0;
static u64 s_hd_ttl_expiries = 0;
// fail-open episodes: a stock packet arrived while the companion was silent past the blackout
// threshold — suppression is DROPPED and the stock model draws (a <=2-frame stock flash instead
// of an invisible actor). Level-load hitches (DGO swaps re-instantiate actors while companions
// respawn) are the expected source. Counted for the heartbeat, NOT gated.
static u64 s_hd_failopen_events = 0;
static bool s_hd_ever_armed = false;  // heartbeat stays silent until the first companion arms

// CYCLE-3 (Keira black-eyes-on-blink): dynamic eye slots referenced by actively-submitting HD
// companion draws. Armed alongside the pid TTL, drained in render(); EyeRenderer consults this
// to skip the full-tile lid blit for these slots (see Merc2.h). Render-thread only.
static int s_hd_eye_slot_ttl[256] = {};

// CYCLE-4 (visible blink): donor eyelid GL texture per covered slot (0 = none). hd_merc_swap
// ports the donor's own lid texture into enhanced GAME.fr3 with debug_name "<model>-lid"
// (e.g. "keira-hd-lid"); we resolve it against the model's level texture list at slot arming
// and hand the GL handle to the EyeRenderer, which paints it at the driver's lid position
// instead of skipping the blit. TexturePool cannot be used here — its lookup is keyed by VRAM
// address, and ported donor textures must NOT enter the pool at donor combo ids (donor pages
// are OOB/aliased in the jak1 page directory). A model without a ported lid keeps the cycle-3
// skip = fail-safe, never the stock jak1 lid on donor eye UVs.
static u64 s_hd_eye_slot_lid_gl[256] = {};

struct HdLidCacheEntry {
  const void* level = nullptr;  // LevelData identity — re-resolve if the level was reloaded
  u64 gl = 0;
};
static std::unordered_map<std::string, HdLidCacheEntry> s_hd_lid_cache;

static u64 hd_lid_gl_for_model(const char* name, const LevelData* lev) {
  if (!name || !lev || !lev->level) {
    return 0;
  }
  auto& entry = s_hd_lid_cache[name];
  if (entry.level == lev) {
    return entry.gl;
  }
  entry.level = lev;
  entry.gl = 0;
  // "<base>-lod0" -> "<base>-lid"
  std::string want(name);
  auto lod = want.rfind("-lod");
  if (lod != std::string::npos) {
    want.resize(lod);
  }
  want += "-lid";
  const auto& texs = lev->level->textures;
  for (size_t i = 0; i < texs.size() && i < lev->textures.size(); i++) {
    if (texs[i].debug_name == want) {
      entry.gl = lev->textures[i];
      break;
    }
  }
  return entry.gl;
}

bool merc2_hd_eye_slot_covered(u8 slot) {
  return s_hd_eye_slot_ttl[slot] > 0;
}

u64 merc2_hd_eye_slot_lid_gl(u8 slot) {
  return s_hd_eye_slot_ttl[slot] > 0 ? s_hd_eye_slot_lid_gl[slot] : 0;
}

void merc2_hd_cover(u32 companion_pid, u32 driver_pid) {
  std::lock_guard<std::mutex> lock(s_hd_cover_mutex);
  for (auto& p : s_hd_cover_pairs) {
    if (p.companion_pid == companion_pid) {
      p.driver_pid = driver_pid;
      return;
    }
  }
  s_hd_cover_pairs.push_back({companion_pid, driver_pid});
}

// CYCLE-3 FLICKER FIX: uncover must drop the driver's suppression TTL IMMEDIATELY. Leaving it
// to drain kept the stock draw hidden for ~2 more frames after a companion died (cutscene actor
// churn, respawn) — a per-despawn NPC blackout. The TTL map is render-thread-owned, so the EE
// thread queues the pid here (under the cover mutex) and the render-thread drain erases it on
// its next call — one render call of latency, not two frames.
static std::vector<u32> s_hd_uncover_pending;  // driver pids; guarded by s_hd_cover_mutex

void merc2_hd_uncover(u32 companion_pid) {
  std::lock_guard<std::mutex> lock(s_hd_cover_mutex);
  for (const auto& p : s_hd_cover_pairs) {
    if (p.companion_pid == companion_pid) {
      s_hd_uncover_pending.push_back(p.driver_pid);
      break;
    }
  }
  std::erase_if(s_hd_cover_pairs,
                [&](const HdCoverPair& p) { return p.companion_pid == companion_pid; });
}
#endif

/*!
 * Setup draws for a model, given the DMA data generated by the GOAL code.
 */
// ─── Ghd-skin-origin-stretch (cycle 4) — LA SONDE « HDSKIN » ────────────────────────────
// Un seul thread de rendu, une seule instance de compteurs. Une « image » est un frame_idx
// distinct ou au moins un paquet merc a ete consomme ; une image est MAUVAISE si au moins un
// os consomme etait non fini ou a plus de 40 m du premier os fini de son paquet. Les paquets HD
// (« <char>-hd-lod0 ») ont leur propre colonne : c'est ce que l'owner regarde.
// Sortie : HDSKINEV (cap 80, un evenement par paquet mauvais, avec le slot le plus loin) et
// HDSKIN (battement toutes les 300 images, cumul depuis le demarrage) — sur stdout, donc dans
// le logcat de l'appareil sous `opengoal-gk` comme les marqueurs GOAL.
namespace {
struct HdSkinStats {
  u64 last_frame = ~0ull;
  u64 frames = 0, bad_frames = 0, hd_frames = 0, hd_bad_frames = 0;
  u64 packets = 0, hd_packets = 0;
  u64 nan_bones = 0, far_bones = 0, hd_nan_bones = 0, hd_far_bones = 0, repaired = 0, missing = 0;
  float worst_m = 0.f;
  bool cur_bad = false, cur_hd = false, cur_hd_bad = false;
  int ev_logs = 0;     // cap des evenements NON HD (bruit : les gros maillages `medres-*`)
  int ev_logs_hd = 0;  // cap des evenements HD — la colonne que l'owner regarde
  u64 next_hb = 300;
};
HdSkinStats s_hdskin;

void hdskin_close_frame() {
  if (s_hdskin.last_frame == ~0ull) {
    return;
  }
  s_hdskin.frames++;
  if (s_hdskin.cur_bad) {
    s_hdskin.bad_frames++;
  }
  if (s_hdskin.cur_hd) {
    s_hdskin.hd_frames++;
  }
  if (s_hdskin.cur_hd_bad) {
    s_hdskin.hd_bad_frames++;
  }
  s_hdskin.cur_bad = s_hdskin.cur_hd = s_hdskin.cur_hd_bad = false;
  if (s_hdskin.frames >= s_hdskin.next_hb) {
    s_hdskin.next_hb += 300;
    printf("HDSKIN frames=%llu bad_frames=%llu hd_frames=%llu hd_bad_frames=%llu packets=%llu "
           "hd_packets=%llu nan_bones=%llu far_bones=%llu hd_nan_bones=%llu hd_far_bones=%llu "
           "repaired=%llu missing=%llu worst_m=%.1f\n",
           (unsigned long long)s_hdskin.frames, (unsigned long long)s_hdskin.bad_frames,
           (unsigned long long)s_hdskin.hd_frames, (unsigned long long)s_hdskin.hd_bad_frames,
           (unsigned long long)s_hdskin.packets, (unsigned long long)s_hdskin.hd_packets,
           (unsigned long long)s_hdskin.nan_bones, (unsigned long long)s_hdskin.far_bones,
           (unsigned long long)s_hdskin.hd_nan_bones, (unsigned long long)s_hdskin.hd_far_bones,
           (unsigned long long)s_hdskin.repaired, (unsigned long long)s_hdskin.missing,
           s_hdskin.worst_m);
    fflush(stdout);
  }
}

void hdskin_note_packet(u64 frame_idx,
                        const char* name,
                        bool is_hd,
                        int slots,
                        int nan_bones,
                        int far_bones,
                        int far_slot,
                        float far_worst,
                        const float* tref,
                        int ref_slot,
                        int missing,
                        const std::string& far_list) {
  if (frame_idx != s_hdskin.last_frame) {
    hdskin_close_frame();
    s_hdskin.last_frame = frame_idx;
  }
  s_hdskin.packets++;
  if (is_hd) {
    s_hdskin.hd_packets++;
    s_hdskin.cur_hd = true;
  }
  const bool bad = nan_bones > 0 || far_bones > 0 || missing > 0;
  if (!bad) {
    return;
  }
  s_hdskin.cur_bad = true;
  s_hdskin.nan_bones += nan_bones;
  s_hdskin.far_bones += far_bones;
  s_hdskin.missing += (u64)missing;
  if (is_hd) {
    s_hdskin.cur_hd_bad = true;
    s_hdskin.hd_nan_bones += nan_bones;
    s_hdskin.hd_far_bones += far_bones;
  }
  const float worst_m = far_worst / 4096.f;
  if (worst_m > s_hdskin.worst_m) {
    s_hdskin.worst_m = worst_m;
  }
  if (is_hd ? (s_hdskin.ev_logs_hd < 80) : (s_hdskin.ev_logs < 20)) {
    if (is_hd) {
      s_hdskin.ev_logs_hd++;
    } else {
      s_hdskin.ev_logs++;
    }
    printf("HDSKINEV frame=%llu model=%s hd=%d used=%d nan=%d far=%d miss=%d far_slot=%d "
           "far_m=%.1f ref_slot=%d ref_cam_m=%.1f ref_cam=(%.2f,%.2f,%.2f) far_list=%s\n",
           (unsigned long long)frame_idx, name, is_hd ? 1 : 0, slots, nan_bones, far_bones,
           missing, far_slot, worst_m, ref_slot,
           tref ? std::sqrt(tref[12] * tref[12] + tref[13] * tref[13] + tref[14] * tref[14]) /
                      4096.f
                : -1.f,
           tref ? tref[12] / 4096.f : 0.f, tref ? tref[13] / 4096.f : 0.f,
           tref ? tref[14] / 4096.f : 0.f, far_list.empty() ? "-" : far_list.c_str());
    fflush(stdout);
  }
}

void hdskin_note_repair(int repaired) {
  s_hdskin.repaired += (u64)repaired;
}

// LES SLOTS QUE LES SOMMETS UTILISENT VRAIMENT. La chaine de slots du paquet liste tous les os du
// modele, y compris `align` (slot 0), qui porte une matrice MODEL-SPACE dans un emplacement
// world-space (jak-hd.gc, en-tete l.49-50) : mesure sur x86, slot 0 de jak-hd-lod0 a
// 2 097 152 m de la camera sur chaque image, sans qu'aucun sommet ne le lise. Compter un os que
// personne ne lit ferait de la sonde une constante. Le masque est calcule UNE fois par modele et
// par chargement de niveau, depuis les indices de dessin et les poids des sommets (le shader ne
// lit mats[1]/mats[2] que si leur poids est > 0 — meme regle ici).
struct HdSkinModelInfo {
  u64 load_id = ~0ull;
  bool valid = false;
  bool known = false;
  int n_used = 0;
  std::bitset<128> used;
};
std::unordered_map<const tfrag3::MercModel*, HdSkinModelInfo> s_hdskin_models;

const HdSkinModelInfo& hdskin_model_info(const tfrag3::MercModel* model, const LevelData* lev) {
  auto& e = s_hdskin_models[model];
  if (e.valid && e.load_id == lev->load_id) {
    return e;
  }
  e = HdSkinModelInfo{};
  e.load_id = lev->load_id;
  e.valid = true;
  // Le masque est calcule par le chargeur AVANT la liberation des sommets CPU
  // (Loader.cpp compute_merc_used_bone_masks) : ici les sommets n'existent plus
  // (A58-MERCFREE), seul le masque survit. Vide = inconnu -> on juge TOUS les slots
  // fournis (la sonde devient plus severe, jamais plus laxiste).
  if (model->used_bone_mask_rt.size() >= 128) {
    for (int b = 0; b < 128; b++) {
      if (model->used_bone_mask_rt[b]) {
        e.used.set(b);
      }
    }
    e.known = true;
  } else {
    e.used.set();
    e.known = false;
  }
  e.n_used = (int)e.used.count();
  // une ligne par modele et par chargement : ce que la sonde considere comme LU par les sommets
  {
    std::string used_list;
    for (int b = 0; b < 128; b++) {
      if (e.used.test(b)) {
        used_list += std::to_string(b) + ",";
      }
    }
    printf("HDSKINMODEL model=%s load_id=%llu max_bones=%u known=%d used=%d list=%s\n",
           model->name.c_str(), (unsigned long long)lev->load_id, model->max_bones, e.known ? 1 : 0,
           e.n_used, e.known ? used_list.c_str() : "all");
    fflush(stdout);
  }
  return e;
}

// ─── Ghd-skin-origin-stretch — LA SONDE « HDSKINLEN » : l'ETIREMENT de chaque os HD ─────────
// HDSKIN juge une POSITION (un os a plus de 40 m de la reference du paquet). Ce que l'owner voit
// est un ETIREMENT : des sommets tires loin de leurs voisins — et un os deplace de 2 m le produit
// deja, sous le seuil de HDSKIN. La grandeur qui le mesure sans seuil de distance est la LONGUEUR
// DE L'OS : distance entre le joint k et son parent, calculee sur les matrices que le GPU
// CONSOMME (skel_matrix_buffer, apres la reparation Gd3), comparee a la longueur de REPOS de ce
// meme os (pose de bind). tmat(slot s) = bindinv[k] x W[k] x camera est rigide : une longueur
// d'os ne change qu'avec l'animation, et aucune animation ne double la longueur d'un os.
// Position camera du joint k = [bx,by,bz,1] . tmat (convention vecteur-ligne, ligne r =
// f[4r..4r+3], translation f[12..14]), avec k = s - 1 (slot 0 = align).
// Le rig (parent + position de bind de chaque joint, unites moteur) est enregistre par GOAL, par
// compagnon HD (pid), via pc-hd-skel-joint! (jak1/kmachine.cpp) : GOAL ecrit sur le thread jeu,
// la sonde lit sur le thread de rendu, d'ou le verrou et la COPIE locale a chaque paquet
// (~1,8 Ko, un paquet HD par personnage et par image).
struct HdRig {
  int n = 0;           // 1 + le plus grand k enregistre
  u8 parent[128];      // 255 = racine / inconnu
  u8 e[128];           // joint PILOTE du modele stock lu par k (255 = aucun)
  u8 mode[128];        // mode de reciblage : 0 monde, 1 local, 2 colle, 3 orientation
  float bp[128][3];    // position de bind du joint k, unites moteur (4096 u = 1 m)
  bool have[128];
  u64 last_seen = 0;   // derniere image ou un paquet de ce compagnon a ete juge (purge par age)
  HdRig() {
    std::memset(parent, 255, sizeof(parent));
    std::memset(e, 255, sizeof(e));
    std::memset(mode, 0, sizeof(mode));
    std::memset(bp, 0, sizeof(bp));
    std::memset(have, 0, sizeof(have));
  }
};
std::mutex s_hd_rigs_mutex;  // s_hd_rigs : ecrit thread jeu (GOAL), lu thread de rendu
std::unordered_map<u32, HdRig> s_hd_rigs;

// ─── L'ANNEAU GOAL (sonde « HDRING ») — L'ATTRIBUTION DECISIVE ──────────────────────────
// Le squelette GOAL etait PROPRE (joints a 0,000 m de la commande) a l'image ou le GPU consommait
// des chaines de 4,5 m. Or pos = [bindpos,1] . bindinv . W . cam = W.t . cam EXACTEMENT
// (bindpos . bindinv = origine) : les translations CONSOMMEES different donc de celles ECRITES.
// Pour le prouver par image, GOAL tient un anneau global (jak-hd.gc `*hd-ring*`) : 11
// emplacements x 4 images x 128 joints de vecteurs W.t (monde, 16 o), `*hd-ring-cam*` = 44
// matrices camera-rot (64 o, vecteur-ligne comme tmat), `*hd-ring-stamp*` = 44 vecteurs dont le
// premier u32 est l'estampille d'image (`real-frame-counter`, bas 32 bits). Cellule
// c = emplacement*4 + (stamp & 3) ; joint k de la cellule = ring[c*128 + k]. bones.gc ecrit la
// meme estampille aux octets 124..127 du nom de CHAQUE paquet merc : un paquet s'apparie a sa
// cellule quand les deux estampilles sont egales, sinon la cellule a deja ete recyclee.
// Les adresses sont des offsets GOAL dans ee_main_memory, ecrits une fois par GOAL (thread jeu)
// et lus par le rendu : atomiques ; l'emplacement par pid partage le verrou du rig.
constexpr int HD_RING_SLOTS = 11;
constexpr int HD_RING_FRAMES = 4;
constexpr int HD_RING_JOINTS = 128;
std::atomic<u32> s_hd_ring_addr{0}, s_hd_ring_cam_addr{0}, s_hd_ring_stamp_addr{0};
std::unordered_map<u32, int> s_hd_ring_slots;  // pid -> emplacement (0..10), sous s_hd_rigs_mutex
// d_goal = |pos derivee - (W.t ecrit par GOAL) . cam| : sous 0,10 m, « GOAL l'avait ecrit tel
// quel » (ring_ok) ; au-dela, corrompu entre l'ecriture et la consommation (ring_bad). Et sur
// TOUS les os juges, 0,25 m est le troisieme critere de verdict, independant du bind et du stock.
// (HD_RING_OK_U supprime : l attribution ring_ok/ring_bad suit ring_bad_bone, sans camera)
constexpr float HD_RING_FAR_U = 1024.0f;

// ─── LA POSE COMMANDEE (sonde « HDCMD ») ─────────────────────────────────────────────────
// Owner (porte refondue le 2026-09-02 21:05) : les os « s'etirent subitement, pas dans un sens
// ou ils sont censes s'etirer, pas lie a l'animation ». Le detecteur compare donc l'os RENDU a
// l'os que l'animation en cours COMMANDE. Fait etabli : pour un joint HD k en mode 0 mappe sur
// le joint pilote e, le reciblage commande W_k = bind_hd_k . bindinv_e . A_e, donc sa position
// camera commandee vaut [bindpos_hd_k, 1] . tmat_stock(e+1), ou tmat_stock est la matrice du
// paquet merc STOCK du pilote (`eichar-lod0`, owner_pid = pid du pilote) dans la MEME image —
// meme camera, meme convention vecteur-ligne. GOAL SOUMET ce paquet stock a chaque image, meme
// quand il est supprime (branche « suppress pid », qui `return` AVANT la lecture des matrices) :
// la capture se fait donc en tete de la branche stock, avant tout retour. Thread de rendu seul.
struct HdStockCapture {
  u64 frame_idx = ~0ull;
  std::bitset<128> provided;
  float tmat[128][16];
};
std::unordered_map<u32 /*driver pid*/, HdStockCapture> s_hd_stock;

// Copie de la chaine de slots + t-mtx (64 octets) du paquet stock du pilote `driver_pid`.
// `slots` pointe sur la chaine de 128 octets, les adresses GOAL suivent (une par qw).
void hd_stock_capture(const u8* slots, const u8* ee_base, u64 frame_idx, u32 driver_pid) {
  const u32* addrs = reinterpret_cast<const u32*>(slots + 128);
  HdStockCapture& cap = s_hd_stock[driver_pid];
  cap.frame_idx = frame_idx;
  cap.provided.reset();
  for (int j = 0; j < 128; j++) {
    if (slots[j] == 0xff) {
      break;
    }
    const int slot = slots[j];
    if (slot >= 128) {
      continue;
    }
    u32 addr;
    std::memcpy(&addr, &addrs[j * 4], 4);
    std::memcpy(cap.tmat[slot], ee_base + addr, 64);
    cap.provided.set(slot);
  }
}

// Derniere t-mtx consommee par slot et par pid, pour `same` / `psame` : une matrice IDENTIQUE AU
// BIT a celle de l'image precedente, alors que le personnage bouge, est une matrice que GOAL n'a
// pas reecrite (lue avant remplissage). Le sens de `same` depend de l'ecart d'images (`gap`) :
// il est publie a cote. `dev` : ecart rendu/commande de l'image precedente, pour « subit »
// (saut_m = dev - dev_prev). Thread de rendu seul.
struct HdLenLast {
  u64 last_frame = ~0ull;
  std::bitset<128> valid;
  std::array<std::array<u8, 64>, 128> tmat{};
  std::bitset<128> dev_valid;
  float dev[128] = {};
};
std::unordered_map<u32, HdLenLast> s_hd_len_last;

// SEUIL D'ETIREMENT : ETIRE si L > HD_LEN_RATIO * L0 + HD_LEN_FLOOR_U. Ratio 2 : aucune
// animation ne double une longueur d'os. Plancher 0,25 m (1024 u) : les joints d'aide
// COINCIDENTS avec leur parent ont L0 = 0, et tout ecart y serait un ratio infini — sous 0,25 m,
// un tel ecart n'est pas l'etirement que l'owner decrit (des metres).
constexpr float HD_LEN_RATIO = 2.0f;
constexpr float HD_LEN_FLOOR_U = 1024.0f;
// SEUIL D'ECART A LA COMMANDE : cmd_bad si |rendu - commande| > 0,25 m (1024 u), ou non fini.
constexpr float HD_CMD_DEV_U = 1024.0f;
// Angle rendu/commande publie seulement si les deux vecteurs d'os font plus de 0,05 m (205 u).
constexpr float HD_CMD_ANGLE_MIN_U = 204.8f;
// LA BASE (echelle) DE LA MATRICE. Mesure Redmi dev6-nat (finalboss images 720-723, snow
// 690-694) : le squelette GOAL est propre (joints a 0,000 m de la commande) mais le GPU consomme
// des chaines d'os de 4,5 m (jak-hd k=6->11->12, ratio 13-80) pendant 4-5 images aux transitions
// stance->walk. Positions justes, produit GPU faux : c'est la BASE de tmat qui explose pendant
// que la translation reste juste — pos = bindpos . tmat multiplie bindpos par une base x13.
// tmat = bindinv . W . cam, donc une base saine vaut l'echelle d'animation du pilote (~1) :
// lignes r0=|f[0..2]|, r1=|f[4..6]|, r2=|f[8..10]|. scl_bad si une ligne depasse 5 ou tombe sous
// 0,2 : le squash & stretch legitime de Daxter reste dessous, une base x13 est dehors.
constexpr float HD_SCL_MAX_ROW = 5.0f;
constexpr float HD_SCL_MIN_ROW = 0.2f;
// L'ECHELLE JUGEE EST RELATIVE A LA COMMANDE. Mesure : Daxter k=4 rend x4,5 sur une ligne
// pendant `sidekick-attack-from-stance` avec un ecart NUL a la commande — c'est le squash &
// stretch de ND, et le paquet stock du pilote le porte aussi ; l'absolu [0,2 ; 5] le comptait
// (707 os sur la preuve). Le verdict compare donc chaque ligne de l'os HD a la ligne
// correspondante de la t-mtx stock du pilote : ratio hors [0,5 ; 2] = scl_bad. Une ligne stock
// sous 1e-6 (nulle) rend le ratio indefini : non juge. L'absolu reste un diagnostic
// (scl_abs_bones).
constexpr float HD_SCL_REL_MAX = 2.0f;
constexpr float HD_SCL_REL_MIN = 0.5f;
constexpr float HD_SCL_STOCK_ROW_EPS = 1e-6f;
// |w - 1| au-dela duquel une t-mtx n'est pas affine (f[15], ligne 3 colonne w)
constexpr float HD_W_EPS = 1e-4f;

struct HdLenStats {
  u64 last_frame = ~0ull;
  u64 frames = 0, hd_frames = 0, hd_stretch_frames = 0;
  u64 hd_stretch_bones = 0, bones_judged = 0, packets_judged = 0, hd_packets_norig = 0;
  u64 torn_bones = 0, same_bones = 0, nan_bones = 0, null_bones = 0, rep_bones = 0;
  float worst_ratio = 0.f, worst_m = 0.f;
  // le VERDICT est l'union : un os est mauvais s'il est etire (longueur), loin de sa commande,
  // OU porte par une base hors d'echelle
  u64 hd_bad_frames = 0, hd_bad_bones = 0;
  u64 cmd_judged = 0, cmd_bones = 0, cmd_frames = 0, cmd_nostock = 0;
  float cmd_worst_m = 0.f;
  u64 scl_bones = 0, scl_frames = 0;  // echelle RELATIVE au stock (le verdict)
  float scl_worst = 0.f;              // pire facteur relatif : max(rel_max, 1/rel_min)
  u64 scl_abs_bones = 0;   // diagnostic : lignes hors [0,2 ; 5] en absolu (l'ancien critere)
  u64 scl_unjudged = 0;    // os sans reference stock (ou sous une racine) : echelle non jugee
  u64 stock_w_bad = 0;     // os compares (cmd) dont la t-mtx STOCK a |w - 1| > 1e-4
  u64 hd_w_bad = 0;        // os juges dont la t-mtx HD a |w - 1| > 1e-4
  // anneau GOAL : ring_ok/ring_bad sur les os MAUVAIS apparies (d_goal < / >= 0,10 m),
  // ring_nostamp = paquets HD sans cellule appariee, ring_judged/ring_far sur TOUS les os juges
  u64 ring_ok = 0, ring_bad = 0, ring_nostamp = 0, ring_judged = 0, ring_far = 0;
  bool cur_hd = false, cur_hd_stretch = false, cur_hd_bad = false, cur_cmd = false,
       cur_scl = false;
  int ev_logs = 0;      // cap des lignes HDLENEV
  int ev_logs_cmd = 0;  // cap des lignes HDCMDEV (separe : l'un ne doit pas etouffer l'autre)
  u64 next_hb = 300;
};
HdLenStats s_hdlen;

// Meme cadence que HDSKIN (une image = un frame_idx ou au moins un paquet merc a ete consomme,
// battement toutes les 300 images) : les deux battements tombent sur les memes images.
void hdlen_close_frame() {
  if (s_hdlen.last_frame == ~0ull) {
    return;
  }
  s_hdlen.frames++;
  if (s_hdlen.cur_hd) {
    s_hdlen.hd_frames++;
  }
  if (s_hdlen.cur_hd_stretch) {
    s_hdlen.hd_stretch_frames++;
  }
  if (s_hdlen.cur_hd_bad) {
    s_hdlen.hd_bad_frames++;
  }
  if (s_hdlen.cur_cmd) {
    s_hdlen.cmd_frames++;
  }
  if (s_hdlen.cur_scl) {
    s_hdlen.scl_frames++;
  }
  s_hdlen.cur_hd = s_hdlen.cur_hd_stretch = s_hdlen.cur_hd_bad = s_hdlen.cur_cmd =
      s_hdlen.cur_scl = false;
  if (s_hdlen.frames >= s_hdlen.next_hb) {
    s_hdlen.next_hb += 300;
    int rigs = 0;
    {
      std::lock_guard<std::mutex> lock(s_hd_rigs_mutex);
      rigs = (int)s_hd_rigs.size();
    }
    // les pids GOAL ne sont jamais reutilises : un compagnon mort laisserait ses 8 Ko de
    // dernieres matrices pour toujours — on oublie ce qui n'a pas ete vu depuis 3000 images.
    for (auto it = s_hd_len_last.begin(); it != s_hd_len_last.end();) {
      if (it->second.last_frame + 3000 < s_hdlen.last_frame) {
        it = s_hd_len_last.erase(it);
      } else {
        ++it;
      }
    }
    // meme regle pour les rigs : `pc-hd-uncover!` est appele pendant la vie du compagnon (miroir
    // hidden), donc le rig ne meurt pas avec lui mais par age — les pids ne sont jamais reutilises
    {
      std::lock_guard<std::mutex> lock(s_hd_rigs_mutex);
      for (auto it = s_hd_rigs.begin(); it != s_hd_rigs.end();) {
        if (it->second.last_seen + 3000 < s_hdlen.last_frame) {
          it = s_hd_rigs.erase(it);
        } else {
          ++it;
        }
      }
    }
    // meme regle pour les captures stock (8 Ko par pilote)
    for (auto it = s_hd_stock.begin(); it != s_hd_stock.end();) {
      if (it->second.frame_idx + 3000 < s_hdlen.last_frame) {
        it = s_hd_stock.erase(it);
      } else {
        ++it;
      }
    }
    printf("HDSKINLEN frames=%llu hd_frames=%llu hd_stretch_frames=%llu hd_stretch_bones=%llu "
           "bones_judged=%llu torn=%llu same=%llu nan=%llu null=%llu rep=%llu worst_ratio=%.2f "
           "worst_m=%.2f rigs=%d norig=%llu hd_bad_frames=%llu hd_bad_bones=%llu "
           "cmd_judged=%llu cmd_bones=%llu cmd_frames=%llu cmd_worst_m=%.2f cmd_nostock=%llu "
           "scl_bones=%llu scl_frames=%llu scl_worst=%.2f ring_ok=%llu ring_bad=%llu "
           "ring_nostamp=%llu ring_judged=%llu ring_far=%llu stock_w_bad=%llu hd_w_bad=%llu "
           "scl_abs_bones=%llu scl_unjudged=%llu\n",
           (unsigned long long)s_hdlen.frames, (unsigned long long)s_hdlen.hd_frames,
           (unsigned long long)s_hdlen.hd_stretch_frames,
           (unsigned long long)s_hdlen.hd_stretch_bones, (unsigned long long)s_hdlen.bones_judged,
           (unsigned long long)s_hdlen.torn_bones, (unsigned long long)s_hdlen.same_bones,
           (unsigned long long)s_hdlen.nan_bones, (unsigned long long)s_hdlen.null_bones,
           (unsigned long long)s_hdlen.rep_bones, s_hdlen.worst_ratio, s_hdlen.worst_m, rigs,
           (unsigned long long)s_hdlen.hd_packets_norig,
           (unsigned long long)s_hdlen.hd_bad_frames, (unsigned long long)s_hdlen.hd_bad_bones,
           (unsigned long long)s_hdlen.cmd_judged, (unsigned long long)s_hdlen.cmd_bones,
           (unsigned long long)s_hdlen.cmd_frames, s_hdlen.cmd_worst_m,
           (unsigned long long)s_hdlen.cmd_nostock, (unsigned long long)s_hdlen.scl_bones,
           (unsigned long long)s_hdlen.scl_frames, s_hdlen.scl_worst,
           (unsigned long long)s_hdlen.ring_ok, (unsigned long long)s_hdlen.ring_bad,
           (unsigned long long)s_hdlen.ring_nostamp, (unsigned long long)s_hdlen.ring_judged,
           (unsigned long long)s_hdlen.ring_far, (unsigned long long)s_hdlen.stock_w_bad,
           (unsigned long long)s_hdlen.hd_w_bad, (unsigned long long)s_hdlen.scl_abs_bones,
           (unsigned long long)s_hdlen.scl_unjudged);
    fflush(stdout);
  }
}

// Longueurs des trois lignes de base de la t-mtx f (convention vecteur-ligne : ligne r =
// f[4r..4r+2]). Une base saine vaut ~1 sur chaque ligne.
void hdlen_rows(const float* f, float rows[3]) {
  for (int r = 0; r < 3; r++) {
    const float* v = f + 4 * r;
    rows[r] = std::sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]);
  }
}

// Le pire facteur d'echelle d'une base : max(max(r), 1/min(r)) quand min(r) > 0 ; une ligne
// NULLE (min = 0) rend max(r) seul — l'inverse serait infini et ne se publie pas en %.2f.
float hdlen_row_worst(const float rows[3]) {
  const float mx = std::max(rows[0], std::max(rows[1], rows[2]));
  const float mn = std::min(rows[0], std::min(rows[1], rows[2]));
  return (mn > 0.f) ? std::max(mx, 1.f / mn) : mx;
}

// Appele pour CHAQUE paquet (HD ou non) : c'est ce qui tient le compte d'images commun.
void hdlen_note_frame(u64 frame_idx) {
  if (frame_idx != s_hdlen.last_frame) {
    hdlen_close_frame();
    s_hdlen.last_frame = frame_idx;
  }
}

// Position camera du joint de bind b sous la t-mtx f (convention vecteur-ligne).
void hdlen_joint_pos(const float* f, const float* b, float out[3]) {
  out[0] = b[0] * f[0] + b[1] * f[4] + b[2] * f[8] + f[12];
  out[1] = b[0] * f[1] + b[1] * f[5] + b[2] * f[9] + f[13];
  out[2] = b[0] * f[2] + b[1] * f[6] + b[2] * f[10] + f[14];
}
}  // namespace

void merc2_hd_skel_joint(u32 companion_pid,
                         int k,
                         int parent,
                         int e,
                         int mode,
                         float bx,
                         float by,
                         float bz) {
  if (k < 0 || k >= 128) {
    return;
  }
  std::lock_guard<std::mutex> lock(s_hd_rigs_mutex);
  HdRig& rig = s_hd_rigs[companion_pid];
  rig.parent[k] = (parent >= 0 && parent < 128) ? (u8)parent : 255;
  rig.e[k] = (e >= 0 && e < 128) ? (u8)e : 255;
  rig.mode[k] = (mode >= 0 && mode < 255) ? (u8)mode : 255;
  rig.bp[k][0] = bx;
  rig.bp[k][1] = by;
  rig.bp[k][2] = bz;
  rig.have[k] = true;
  rig.n = std::max(rig.n, k + 1);
}

void merc2_hd_skel_forget(u32 companion_pid) {
  std::lock_guard<std::mutex> lock(s_hd_rigs_mutex);
  s_hd_rigs.erase(companion_pid);
  // l'emplacement d'anneau meurt avec le rig : les pids GOAL sont monotones, la map ne se
  // viderait jamais autrement
  s_hd_ring_slots.erase(companion_pid);
}

void merc2_hd_ring(u32 ring_addr, u32 cam_addr, u32 stamp_addr) {
  s_hd_ring_addr.store(ring_addr);
  s_hd_ring_cam_addr.store(cam_addr);
  s_hd_ring_stamp_addr.store(stamp_addr);
}

void merc2_hd_ring_slot(u32 companion_pid, int slot) {
  std::lock_guard<std::mutex> lock(s_hd_rigs_mutex);
  if (slot < 0 || slot >= HD_RING_SLOTS) {
    s_hd_ring_slots.erase(companion_pid);
    return;
  }
  s_hd_ring_slots[companion_pid] = slot;
}

void Merc2::handle_pc_model(const DmaTransfer& setup,
                            SharedRenderState* render_state,
                            ScopedProfilerNode& proff,
                            MercDebugStats* stats) {
  auto p = scoped_prof("init-pc");

  // the format of the data is:
  //  ;; name   (128 char, 8 qw)
  //  ;; lights (7 qw x 1)
  //  ;; matrix slot string (128 char, 8 qw)
  //  ;; matrices (7 qw x N)
  //  ;; flags    (num-effects, effect-alpha-ignore, effect-disable)
  //  ;; fades    (u32 x N), padding to qw aligned
  //  ;; pointers (u32 x N), padding

  // Get the name
  const u8* input_data = setup.data;
  ASSERT(strlen((const char*)input_data) < 127);
  char name[128];
  strcpy(name, (const char*)setup.data);
  input_data += 128;

  // Look up the model by name in the loader.
  // This will return a reference to this model's data, plus a reference to the level's data
  // for stuff shared between models of the same level
  auto model_ref = render_state->loader->get_merc_model(name);

  // Gcutscene-npc-flicker (owner 2026-08-31) : le pid du proprietaire voyage dans les octets morts
  // du champ de nom et GOAL l'ecrit INCONDITIONNELLEMENT (bones.gc:947, `#when FLAG_HD_MODELS` qui
  // vaut #t dans tous les builds). Le lire ici, HORS du bloc HD, est ce qui rend le recensement
  // identique modeles HD allumes et eteints — donc l'ablation possible SUR LE MEME BINAIRE.
  u32 owner_pid = 0;
  memcpy(&owner_pid, setup.data + 120, sizeof(owner_pid));
  // Ghd-skin-origin-stretch (sonde HDRING) : l'estampille d'image du paquet, octets 124..127,
  // ecrite par bones.gc avec la meme valeur que la cellule de l'anneau GOAL a cette image.
  u32 pkt_stamp = 0;
  memcpy(&pkt_stamp, setup.data + 124, sizeof(pkt_stamp));
  const bool is_hd_packet = strstr(name, "-hd-lod0") != nullptr;
  // Le personnage que l'owner voit est le DRIVER. Un paquet de compagnon HD est donc compte SOUS
  // LE PID DE SON DRIVER, sinon « le PNJ est-il visible ? » n'a pas de reponse quand la
  // couverture est active.
  u32 census_pid = owner_pid;
#ifdef OG_FEAT_HD_MODELS
  // Grecharged-hd-models4 PER-ACTOR coverage (see the block at the HdCoverPair definition).
  if (is_hd_packet) {
    // an HD companion packet ("<char>-hd-lod0"): log throttled per model name (first submission
    // + one line every 600 — one-shot rolled off the Honor's ~1-minute logcat ring buffer).
    static std::unordered_map<std::string, u64> s_hd_submit_counts;
    u64& n = s_hd_submit_counts[name];
    if (n++ % 600 == 0) {
      lg::warn("[hd-render] SUBMITTED name='{}' found={} submits={}", name, model_ref ? 1 : 0, n);
    }
    // refresh this driver's suppression ONLY when the replacement is actually drawable (model
    // found). TTL decremented once per render() call — jak1 makes 16 of those per frame (16
    // Merc2BucketRenderers share this instance), so TTL 32 = ~2 FRAMES (the old "~4 frames"
    // claim was wrong by 2x) — the stock draw returns by itself when the companion despawns,
    // and merc2_hd_uncover clears it same-frame on explicit despawn.
    // La paire de couverture se resout TOUJOURS (le recensement en a besoin meme quand le modele
    // HD n'est pas resident) ; l'ARMEMENT du TTL, lui, garde exactement sa condition d'avant.
    u32 driver_pid = 0;
    if (owner_pid != 0) {
      std::lock_guard<std::mutex> lock(s_hd_cover_mutex);
      for (const auto& p : s_hd_cover_pairs) {
        if (p.companion_pid == owner_pid) {
          driver_pid = p.driver_pid;
          break;
        }
      }
    }
    if (driver_pid != 0) {
      census_pid = driver_pid;
    }
    if (model_ref && owner_pid != 0) {
      if (driver_pid != 0) {
        // flicker detector: a healthy companion re-arms every ~16 render calls (one frame). A
        // gap of more than ~1.5 frames while still covered means frames were skipped (cull
        // divergence / streamed-out model) — each one is a candidate visible blink.
        auto arm_it = s_hd_last_arm_call.find(driver_pid);
        if (arm_it != s_hd_last_arm_call.end()) {
          u64 gap = s_hd_render_call_idx - arm_it->second;
          if (gap > 24 && gap < 4000) {
            s_hd_submit_gap_events++;
            if (s_hd_submit_gap_events <= 20 || s_hd_submit_gap_events % 50 == 0) {
              lg::warn("[hd-flicker] GAP name='{}' driver_pid={} calls={}", name, driver_pid, gap);
            }
          }
        }
        s_hd_last_arm_call[driver_pid] = s_hd_render_call_idx;
        s_hd_driver_ttl[driver_pid] = 32;
        s_hd_ever_armed = true;
        // arm the HD-covered eye slots (lid-blit suppression, see merc2_hd_eye_slot_covered),
        // and record this model's donor lid GL texture for the EyeRenderer blink paint (cycle 4).
        const u64 lid_gl = hd_lid_gl_for_model(name, model_ref->level);
        for (const auto& eff : model_ref->model->effects) {
          for (const auto& d : eff.all_draws) {
            if (d.eye_id != 0xff) {
              s_hd_eye_slot_ttl[d.eye_id] = 32;
              s_hd_eye_slot_lid_gl[d.eye_id] = lid_gl;
            }
          }
        }
      }
    }
  } else if (owner_pid != 0) {
    // Ghd-skin-origin-stretch (sonde HDCMD) — CAPTURE DE LA POSE COMMANDEE. Ce paquet stock
    // est celui du PILOTE si son pid est le driver d'une paire de couverture ; ses matrices sont
    // la commande que le reciblage du compagnon a lue. Prise ICI, avant la suppression
    // ci-dessous (qui `return` avant la lecture des matrices) et avant le fail-open : dans les
    // deux cas le paquet a ete soumis avec des matrices ecrites, c'est ce qu'on veut lire.
    // Seulement si le compagnon a un rig enregistre : sans rig, rien ne saurait la consommer.
    {
      u32 companion_pid = 0;
      {
        std::lock_guard<std::mutex> lock(s_hd_cover_mutex);
        for (const auto& cp : s_hd_cover_pairs) {
          if (cp.driver_pid == owner_pid) {
            companion_pid = cp.companion_pid;
            break;
          }
        }
      }
      bool has_rig = false;
      if (companion_pid != 0) {
        std::lock_guard<std::mutex> lock(s_hd_rigs_mutex);
        has_rig = s_hd_rigs.find(companion_pid) != s_hd_rigs.end();
      }
      if (has_rig) {
        // memes offsets que la lecture des matrices plus bas : lights, +16 water (jak1), slots
        const u8* slots = input_data + sizeof(VuLights) +
                          (render_state->version == GameVersion::Jak1 ? 16 : 0);
        hd_stock_capture(slots, (const u8*)render_state->ee_main_memory,
                         render_state->frame_idx, owner_pid);
      }
    }
    // a stock packet: drop it ONLY if ITS OWN pid is covered by an actively-submitting companion.
    // Renderer-level (never GOAL draw-status: skip-bones on *target* propagated to the sidekick
    // and swallowed Daxter on M1 builds 10-12). Uncovered same-name actors (ND logo) draw stock.
    auto it = s_hd_driver_ttl.find(owner_pid);
    if (it != s_hd_driver_ttl.end() && it->second > 0) {
      // FAIL-OPEN (cycle-3 boundary fix): if the companion has been silent past the blackout
      // threshold (~1.25 frames), suppressing this stock packet would leave the actor invisible
      // this frame — the owner-visible cutscene flicker (x86 leg caught it exactly at the
      // echo-intro MIS.DGO swap: actors re-instantiate and submit stock while their companions
      // are still respawning). End the coverage episode instead and let the STOCK model draw;
      // the companion re-arms coverage on its next submit. A <=2-frame stock flash at a load
      // boundary beats an invisible actor. BLACKOUT (suppressed AND silent) is now structurally
      // impossible; fail-open episodes are counted in the heartbeat for honesty, not gated.
      auto arm_it = s_hd_last_arm_call.find(owner_pid);
      if (arm_it == s_hd_last_arm_call.end() ||
          s_hd_render_call_idx - arm_it->second > 20) {
        s_hd_failopen_events++;
        if (s_hd_failopen_events <= 20 || s_hd_failopen_events % 50 == 0) {
          lg::warn("[hd-render] FAIL-OPEN pid={} name='{}' since_arm={} — drawing stock",
                   owner_pid, name,
                   arm_it == s_hd_last_arm_call.end()
                       ? (u64)0
                       : s_hd_render_call_idx - arm_it->second);
        }
        s_hd_driver_ttl.erase(it);
        if (arm_it != s_hd_last_arm_call.end()) {
          s_hd_last_arm_call.erase(arm_it);
        }
        // fall through to the normal stock draw below
      } else {
        static std::unordered_map<u32, u64> s_hd_suppress_counts;
        u64& n = s_hd_suppress_counts[owner_pid];
        if (n++ % 600 == 0) {
          lg::warn("[hd-render] suppress pid={} name='{}' (covered per-actor)", owner_pid, name);
        }
        npc_flicker::note_draw(owner_pid, npc_flicker::Outcome::kSuppressed, false);
        return;
      }
    }
  }
#endif
  // Gcutscene-npc-flicker — CONTROLE POSITIF, sur le binaire livre et eteint par defaut. Voir
  // game/system/npc_flicker.h : injecter une disparition doit faire MONTER le compteur, sinon le
  // zero publie n'est pas une mesure. C'est exactement le bras qui manquait a la garde de
  // Grecharged-hd-models4/5.
  if (npc_flicker::inject_drop(name)) {
    npc_flicker::note_draw(census_pid, npc_flicker::Outcome::kSuppressed, is_hd_packet);
    return;
  }
  if (!model_ref) {
    // it can fail, if the game is faster than the loader. In this case, we just don't draw.
    // Gcutscene-npc-flicker : c'est une DISPARITION de l'acteur, et jusqu'ici elle n'etait
    // comptee que dans un champ de statistiques que rien ne publie.
    npc_flicker::note_draw(census_pid, npc_flicker::Outcome::kMissing, is_hd_packet);
    stats->num_missing_models++;
    return;
  }
  npc_flicker::note_draw(census_pid, npc_flicker::Outcome::kDrawn, is_hd_packet);

  // next, we need to check if we have enough room to draw this effect.
  const LevelData* lev = model_ref->level;
  const tfrag3::MercModel* model = model_ref->model;

  // each model uses only 1 light.
  if (m_next_free_light >= MAX_LIGHTS) {
    fmt::print("MERC2 out of lights, consider increasing MAX_LIGHTS\n");
    flush_draw_buckets(render_state, proff, stats);
  }

  // models use many bones. First check if we need to flush:
  int bone_count = model->max_bones + 1;
  if (m_next_free_bone_vector + m_opengl_buffer_alignment + bone_count * 8 >
      MAX_SHADER_BONE_VECTORS) {
    fmt::print("MERC2 out of bones, consider increasing MAX_SHADER_BONE_VECTORS\n");
    flush_draw_buckets(render_state, proff, stats);
  }

  // also sanity check that we have enough to draw the model
  if (m_opengl_buffer_alignment + bone_count * 8 > MAX_SHADER_BONE_VECTORS) {
    fmt::print(
        "MERC2 doesn't have enough bones to draw a model, increase MAX_SHADER_BONE_VECTORS\n");
    ASSERT_NOT_REACHED();
  }

  // next, we need to find a bucket that holds draws for this level (will have the right buffers
  // bound for drawing)
  LevelDrawBucket* lev_bucket = nullptr;
  for (u32 i = 0; i < m_next_free_level_bucket; i++) {
    if (m_level_draw_buckets[i].level == lev) {
      lev_bucket = &m_level_draw_buckets[i];
      break;
    }
  }

  if (!lev_bucket) {
    // no existing bucket, allocate a new one.
    if (m_next_free_level_bucket >= m_level_draw_buckets.size()) {
      // out of room, flush
      // fmt::print("MERC2 out of levels, consider increasing MAX_LEVELS\n");
      flush_draw_buckets(render_state, proff, stats);
    }
    // alloc a new one
    lev_bucket = &m_level_draw_buckets[m_next_free_level_bucket++];
    lev_bucket->reset();
    lev_bucket->level = lev;
  }

  // next check draws:
  if (lev_bucket->next_free_draw + model->max_draws >= lev_bucket->draws.size()) {
    // out of room, flush
    fmt::print("MERC2 out of draws, consider increasing MAX_DRAWS_PER_LEVEL\n");
    flush_draw_buckets(render_state, proff, stats);
    if (model->max_draws >= lev_bucket->draws.size()) {
      ASSERT_NOT_REACHED_MSG("MERC2 draw buffer not big enough");
    }
  }

  // same for envmap draws
  if (lev_bucket->next_free_envmap_draw + model->max_draws >= lev_bucket->envmap_draws.size()) {
    // out of room, flush
    fmt::print("MERC2 out of envmap draws, consider increasing MAX_ENVMAP_DRAWS_PER_LEVEL\n");
    flush_draw_buckets(render_state, proff, stats);
    if (model->max_draws >= lev_bucket->envmap_draws.size()) {
      ASSERT_NOT_REACHED_MSG("MERC2 envmap draw buffer not big enough");
    }
  }

  // Next part of input data is the lights
  VuLights current_lights;
  memcpy(&current_lights, input_data, sizeof(VuLights));
  input_data += sizeof(VuLights);

  u64 uses_water = 0;
  if (render_state->version == GameVersion::Jak1) {
    // jak 1 figures out water at runtime sadly
    memcpy(&uses_water, input_data, 8);
    input_data += 16;
  }

  // Next part is the matrix slot string. The game sends us a bunch of bone matrices,
  // but they may not be in order, or include all bones. The matrix slot string tells
  // us which bones go where. (the game doesn't go in order because it follows the merc format)
  ShaderMercMat skel_matrix_buffer[MAX_SKEL_BONES];
  auto* matrix_array = (const u32*)(input_data + 128);
  // Ghd-skin-origin-stretch (sonde HDSKINLEN) : l'adresse GOAL de chaque slot est gardee pour
  // RELIRE la matrice apres coup et savoir si GOAL l'a reecrite pendant qu'on la consommait.
  u32 hd_slot_addr[MAX_SKEL_BONES] = {};
  int i;
  for (i = 0; i < 128; i++) {
    if (input_data[i] == 0xff) {  // indicates end of string.
      break;
    }
    // read goal addr of matrix (matrix data isn't known at merc dma time, bones runs after)
    u32 addr;
    memcpy(&addr, &matrix_array[i * 4], 4);
    // EE base from render_state, not from the transfer pointer: the bone
    // matrices are referenced by GOAL address and are NOT part of the DMA
    // chain (bones runs after merc DMA), so under chain copy-mode the
    // setup.data-based reconstruction points off the end of the copy buffer
    // (run-3 crash: Merc2::handle_pc_model+0x378). Desktop zero-copy:
    // identical pointer.
    const u8* real_addr = (const u8*)render_state->ee_main_memory + addr;
    ASSERT(input_data[i] < MAX_SKEL_BONES);
    hd_slot_addr[input_data[i]] = addr;
    // get the matrix data
    memcpy(&skel_matrix_buffer[input_data[i]], real_addr, sizeof(MercMat));
  }

  // OWNER ROUND#18 (Grecharged-grass-poc): capture ground-object world positions for the grass
  // object-clip. Crates + the warp-gate button are merc actors (not TIE / not in static level data), so
  // the grass renderer can't see them at level load. Snapshot the first bone's world XYZ (tmat is
  // column-major: translation = floats 12,13,14). Gated by the grass toggle so OFF is byte-identical
  // stock (zero extra work). Substring match covers all crate variants ("crate-wood-lod0" etc.) and the
  // warp-gate switch/arch. radius is the visible ground-contact footprint (kept tight to avoid a halo).
  if (Gfx::recharged_active(Gfx::g_global_settings.recharged_grass) && i > 0) {
    // OWNER Q&A 2026-07-12: STATIC unbreakable actors (warp-gate button, blue eco valve) -> CULL the
    // grass; BREAKABLE actors (crates, scarecrows) -> TRAMPLE it (flatten like Jak, NOT hidden), so
    // when they break the grass at their spot returns. Substring match covers every lod/variant name.
    float r_m = 0.f;
    bool trample = false;
    if (std::strstr(name, "crate")) {                 // breakable -> flatten (grass survives a broken crate)
      r_m = 0.9f;
      trample = true;
    } else if (std::strstr(name, "scarecrow")) {      // breakable -> flatten
      r_m = 0.7f;
      trample = true;
    } else if (std::strstr(name, "warp")) {           // static warp-gate button -> cull
      r_m = 1.5f;
    } else if (std::strstr(name, "ecovalve")) {       // static blue eco valve -> cull
      r_m = 1.0f;
    } else if (std::strstr(name, "plat-eco")) {       // ROUND#21 census: training blue-eco vent -> cull
      r_m = 1.2f;
    } else if (std::strstr(name, "speaker")) {        // ROUND#21 census: ground speaker at spawn -> cull
      r_m = 0.6f;
    }
    int root_slot = input_data[0];  // first bone in the slot string = the root/align joint
    // ROUND#21 census: run the world-recovery for EVERY drawn model when armed, so unhandled
    // ground objects (planks, decor, vents...) show up with usable world coords.
    // ROUND#21b SELF-CALIBRATION (owner playtest forensics): the recovered world Y ran ~+8-10 m HIGH
    // (crates at y=17-18 where Jak walks at y=7-9), so the shader's [-2.5..+1] m object Y-band rejected
    // EVERY cull/flatten -> "l'herbe passe toujours au travers" while the jak-pos path (true GOAL coords)
    // worked (jump-ease OK). Jak's own merc model ('eichar') runs through this SAME recovery, and his
    // TRUE world pos is known (recharged_jak_pos) -> per-frame error E = recovered(eichar) - true(jak),
    // subtracted from every other capture. Whatever the convention error is, it cancels. Captures are
    // gated on a FRESH calibration (<0.5 s) so title/attract/garbage-camera frames can't emit junk.
    if ((r_m > 0.f || grass_census_on() || std::strstr(name, "eichar")) &&
        root_slot < MAX_SKEL_BONES) {
      const float* t = reinterpret_cast<const float*>(&skel_matrix_buffer[root_slot]);
      // ROUND#19: the merc bone translation is in the game's merc CAMERA space (m_low_memory.perspective
      // maps it to clip), NOT world — device forensics showed the round#18 captures landing ~1300m from
      // the level. Recover world by equating the two pipelines' clip output for the same point:
      //   -M3 - M*world == P*bone  (M = tfrag/grass camera matrix, both shaders add the same hvdf after)
      // and solving the 3x3 linear system. Convention-exact; a degenerate det skips the capture.
      const auto& P = m_low_memory.perspective;       // merc: clip_linear = P0*bx + P1*by + P2*bz + P3
      const auto& M = render_state->camera_matrix;    // grass/tfrag: clip_linear = -M3 - M0*x - M1*y - M2*z
      float Cx = P[0].x() * t[12] + P[1].x() * t[13] + P[2].x() * t[14] + P[3].x();
      float Cy = P[0].y() * t[12] + P[1].y() * t[13] + P[2].y() * t[14] + P[3].y();
      float Cz = P[0].z() * t[12] + P[1].z() * t[13] + P[2].z() * t[14] + P[3].z();
      // A[r][c] = M_c[r] (column c of the grass camera matrix); rhs[r] = -M3[r] - C[r].
      float A00 = M[0].x(), A01 = M[1].x(), A02 = M[2].x();
      float A10 = M[0].y(), A11 = M[1].y(), A12 = M[2].y();
      float A20 = M[0].z(), A21 = M[1].z(), A22 = M[2].z();
      float b0 = -M[3].x() - Cx, b1 = -M[3].y() - Cy, b2 = -M[3].z() - Cz;
      float det = A00 * (A11 * A22 - A12 * A21) - A01 * (A10 * A22 - A12 * A20) +
                  A02 * (A10 * A21 - A11 * A20);
      if (std::fabs(det) >= 1e-12f) {                 // degenerate -> skip this frame's capture (no garbage)
        float inv = 1.0f / det;
        float wx = (b0 * (A11 * A22 - A12 * A21) - A01 * (b1 * A22 - A12 * b2) +
                    A02 * (b1 * A21 - A11 * b2)) * inv;
        float wy = (A00 * (b1 * A22 - A12 * b2) - b0 * (A10 * A22 - A12 * A20) +
                    A02 * (A10 * b2 - b1 * A20)) * inv;
        float wz = (A00 * (A11 * b2 - b1 * A21) - A01 * (A10 * b2 - b1 * A20) +
                    b0 * (A10 * A21 - A11 * A20)) * inv;
        // ROUND#21b self-calibration state: E = recovered(eichar) - true(jak), stamped with a
        // monotonic time so stale calibrations (title/attract, load blackouts) gate captures OFF.
        static float s_cal[3] = {0.f, 0.f, 0.f};
        static double s_cal_t = -1.0;
        auto now_s = [] {
          return std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch())
              .count();
        };
        if (std::strstr(name, "eichar")) {
          const auto& jt = Gfx::g_global_settings.recharged_jak_pos;
          if (jt[3] > 0.5f) {
            s_cal[0] = wx - jt[0];
            s_cal[1] = wy - jt[1];
            s_cal[2] = wz - jt[2];
            s_cal_t = now_s();
            static double s_cal_log_t = -100.0;
            if (s_cal_t - s_cal_log_t > 30.0) {
              s_cal_log_t = s_cal_t;
              fmt::print("[recharged-grass] R21CAL eichar-vs-jak err=({:.2f} {:.2f} {:.2f})m — "
                         "subtracted from every object capture\n",
                         s_cal[0] / 4096.f, s_cal[1] / 4096.f, s_cal[2] / 4096.f);
            }
          }
        }
        const bool cal_fresh = s_cal_t > 0.0 && (now_s() - s_cal_t) < 0.5;
        const float cwx = wx - s_cal[0], cwy = wy - s_cal[1], cwz = wz - s_cal[2];
        // ROUND#21c OWNER VETO: the merc->world recovery is DEAD (two failed rounds; the eichar
        // calibration collapsed ALL captures onto Jak => a flattened circle FOLLOWING him, while real
        // crates got nothing). Object capture application is DISABLED until positions come from the
        // GAME side (GOAL->C++ channel like recharged_jak_pos - exact world coords, no camera math).
        // Census/logging stays for diagnostics. Re-enable via debug.opengoal.grass.mercocc=1 only.
        static const bool s_mercocc = [] {
#ifdef __ANDROID__
          char b[PROP_VALUE_MAX] = {0};
          if (__system_property_get("debug.opengoal.grass.mercocc", b) > 0 && b[0] == '1') return true;
#endif
          return false;
        }();
        if (s_mercocc && r_m > 0.f && cal_fresh) {  // DISABLED by default (owner veto)
          if (trample) {
            grass_occ::add_trample(cwx, cwy, cwz, r_m * 4096.f);
          } else {
            grass_occ::add(cwx, cwy, cwz, r_m * 4096.f);
          }
          static std::set<std::string> s_seen_occ;
          if (s_seen_occ.insert(name).second) {
            fmt::print("[recharged-grass] ROUND#18 object-{} captured: '{}' r={}m at ({:.1f} {:.1f} {:.1f})m (calibrated)\n",
                       trample ? "TRAMPLE" : "CULL", name, r_m, cwx / 4096.f, cwy / 4096.f, cwz / 4096.f);
          }
        }
        // ROUND#21 object-clip completeness census (one line per unique model when armed).
        if (grass_census_on()) {
          static std::set<std::string> s_census_seen;
          if (s_census_seen.insert(name).second) {
            fmt::print("[recharged-grass] R21CENSUS model='{}' at ({:.1f} {:.1f} {:.1f})m cal={} handled={}\n",
                       name, cwx / 4096.f, cwy / 4096.f, cwz / 4096.f, cal_fresh ? 1 : 0,
                       r_m > 0.f ? (trample ? "TRAMPLE" : "CULL") : "none");
          }
        }
      }
    }
  }

  // === Ghd-skin-origin-stretch (cycle 4) — SONDE AU POINT DE CONSOMMATION GPU ==========
  // Owner 2026-09-02 : « Le modèle HD qui s'étire c'est pas corrigé du tout. » La preuve du
  // cycle 3 etait prise dans le SQUELETTE GOAL, sur x86. Ici on lit ce que le GPU va REELLEMENT
  // consommer, sur la machine ou l'owner voit le defaut : pour chaque paquet merc, chaque os
  // utilise (la chaine de slots) est teste (a) FINI ? et (b) A MOINS DE 40 m DU PREMIER OS FINI
  // du meme paquet (espace camera : un os parque a l'origine du monde, a la camera, ou a une
  // pose d'une image anterieure est loin de ses voisins des que le personnage bouge). Le compte
  // est tenu PAR IMAGE (frame_idx), avant toute reparation, et publie sous cap puis en battement.
  // Toujours actif, toutes plateformes : le meme instrument sur x86 et sur l'appareil.
  int hd_ref_slot = -1;  // l'os de REFERENCE du paquet : fini, utilise, dans le groupe majoritaire
  {
    const HdSkinModelInfo& minfo = hdskin_model_info(model, lev);
    int nan_bones = 0, far_bones = 0, far_slot = -1, n_fin = 0;
    float far_worst = 0.f;
    // 1) finitude, sur les seuls slots que des sommets lisent
    bool fin[MAX_SKEL_BONES] = {};
    std::bitset<128> provided;
    for (int j = 0; j < i; j++) {
      int slot = input_data[j];
      if (slot >= MAX_SKEL_BONES) {
        continue;
      }
      provided.set(slot);
      if (!minfo.used.test(slot)) {
        continue;
      }
      const float* f = reinterpret_cast<const float*>(&skel_matrix_buffer[slot]);
      bool ok = true;
      for (int k = 0; k < 16; k++) {
        if (!std::isfinite(f[k])) {
          ok = false;
          break;
        }
      }
      if (ok) {
        fin[slot] = true;
        n_fin++;
        if (hd_ref_slot < 0) {
          hd_ref_slot = slot;
        }
      } else {
        nan_bones++;
      }
    }
    // 2) distance a la reference ; si la MAJORITE en est loin, c'est la reference qui est
    //    l'intrus (cas mesure : `align`) — on la reprend dans le groupe majoritaire et on recompte.
    // Ghd-skin-origin-stretch (cycle 5) — LA LISTE des slots loin, pas seulement le pire : un
    // residu d'UNE image (finalboss, Redmi, 16:46:55 : 9 os de Jak et 6 de Daxter a 43-45 m,
    // 1,4 s apres un respawn) ne s'attribue a un mecanisme qu'en sachant QUELS joints partent,
    // et ou (position camera de chacun, en metres). Format : slot:dist_m@(x,y,z);...
    std::string far_list;
    auto count_far = [&](int ref, bool record) {
      int nfar = 0;
      const float* tr = reinterpret_cast<const float*>(&skel_matrix_buffer[ref]);
      for (int j = 0; j < i; j++) {
        int slot = input_data[j];
        if (slot >= MAX_SKEL_BONES || !fin[slot] || slot == ref) {
          continue;
        }
        const float* f = reinterpret_cast<const float*>(&skel_matrix_buffer[slot]);
        double dx = (double)f[12] - tr[12], dy = (double)f[13] - tr[13], dz = (double)f[14] - tr[14];
        double d = std::sqrt(dx * dx + dy * dy + dz * dz);
        if (d > 163840.0) {  // 40 m en unites moteur (4096 u = 1 m)
          nfar++;
          if (record && d > far_worst) {
            far_worst = (float)d;
            far_slot = slot;
          }
          if (record && far_list.size() < 900) {
            char b[96];
            snprintf(b, sizeof(b), "%d:%.1f@(%.1f,%.1f,%.1f);", slot, d / 4096.0, f[12] / 4096.f,
                     f[13] / 4096.f, f[14] / 4096.f);
            far_list += b;
          }
        }
      }
      return nfar;
    };
    if (hd_ref_slot >= 0 && n_fin >= 2) {
      far_bones = count_far(hd_ref_slot, false);
      if (far_bones * 2 > n_fin) {
        // reprendre la reference dans le groupe majoritaire : le premier slot fini LOIN de l'intrus
        const float* tr = reinterpret_cast<const float*>(&skel_matrix_buffer[hd_ref_slot]);
        int ref2 = -1;
        for (int j = 0; j < i && ref2 < 0; j++) {
          int slot = input_data[j];
          if (slot >= MAX_SKEL_BONES || !fin[slot] || slot == hd_ref_slot) {
            continue;
          }
          const float* f = reinterpret_cast<const float*>(&skel_matrix_buffer[slot]);
          double dx = (double)f[12] - tr[12], dy = (double)f[13] - tr[13], dz = (double)f[14] - tr[14];
          if (std::sqrt(dx * dx + dy * dy + dz * dz) > 163840.0) {
            ref2 = slot;
          }
        }
        if (ref2 >= 0) {
          hd_ref_slot = ref2;
        }
      }
      far_bones = count_far(hd_ref_slot, true);
    }
    const float* tref =
        hd_ref_slot >= 0 ? reinterpret_cast<const float*>(&skel_matrix_buffer[hd_ref_slot]) : nullptr;
    // slots que des sommets lisent et que le paquet NE FOURNIT PAS : le shader y lirait la pile
    const int missing = (int)(minfo.used & ~provided).count();
    hdskin_note_packet(render_state->frame_idx, name, is_hd_packet, minfo.n_used, nan_bones,
                       far_bones, far_slot, far_worst, tref, hd_ref_slot, missing, far_list);
  }

  // === Gd3-jak FIX (always-on, arm64): repair non-finite merc bone matrices =====
  // In the new-game intro cinematic a degenerate root-motion align frame can bake a
  // NaN into Jak's control.trans (1/0 in matrix-inv-scale!, ENGINE.CGO — which is
  // not rebuildable on the device, see feedback-game-cgo-rebuild-unsafe), and it
  // cascades through the whole skeleton. The Adreno GLES driver then FAULTS (sig=11,
  // GL-thread crash inside libGLESv2_adreno during the merc draw) on the NaN bone
  // data, and Jak flickers invisible on that frame. We cannot fix the CGO root, so
  // repair at the merc boundary. x86 never produces NaN here so this is compiled out on desktop.
  //
  // Ghd-skin-origin-stretch (cycle 4) — CE QUE LA REPARATION REMPLACAIT, ET POURQUOI C'ETAIT
  // L'ETIREMENT DE L'OWNER. Elle restaurait « le dernier jeu d'os entierement fini » du modele,
  // pris sur une image ANTERIEURE : une matrice merc est en ESPACE CAMERA (bones-mtx-calc
  // post-multiplie camera-rot), donc l'os restaure posait le sommet la ou il ETAIT A L'ECRAN a
  // cette image-la, rendu avec la camera COURANTE — le modele s'etirait de tout ce que le
  // personnage et la camera avaient parcouru depuis, d'autant plus qu'ils vont vite (zoomer).
  // Et quand un os du modele etait DURABLEMENT non fini, l'instantane ne se rafraichissait plus
  // jamais : la pose de secours vieillissait sans borne. Sur x86, sans reparation, un sommet NaN
  // est simplement ecarte par le GPU (un trou d'une image, invisible) : c'est la difference
  // x86/appareil que l'owner mesure de ses yeux.
  // CE QU'ELLE FAIT MAINTENANT : un os non fini est remplace par le PREMIER OS FINI DU MEME PAQUET
  // (meme image, meme camera) — ses sommets s'effondrent sur le personnage, a la place d'un pic.
  // Sans aucun os fini dans le paquet (le cas d'origine, squelette entier NaN), identite comme avant.
  const bool gd3_is_jak = gd3_bones_on() && std::strstr(name, "eichar") != nullptr;
  int gd3_bones_repaired = 0;
  // Ghd-skin-origin-stretch (sonde HDSKINLEN) : les slots que la reparation a REECRITS dans la
  // copie locale. Sur ces slots la copie ne reflete plus la memoire GOAL, donc « GOAL a reecrit
  // la matrice pendant qu'on la consommait » n'est plus decidable (torn=-1). Sur x86 le bloc
  // est compile hors : le tableau reste a zero.
  bool hd_repaired_slot[MAX_SKEL_BONES] = {};
#ifdef __aarch64__
  {
    static const ShaderMercMat kIdent = []() {
      ShaderMercMat m;
      float* p = reinterpret_cast<float*>(&m);
      for (int z = 0; z < 32; z++) {
        p[z] = 0.f;
      }
      p[0] = p[5] = p[10] = p[15] = 1.f;  // tmat = identity
      p[16] = p[21] = p[26] = 1.f;        // nmat = identity
      return m;
    }();
    bool any_bad = false;
    for (int j = 0; j < i && !any_bad; j++) {
      int slot = input_data[j];
      if (slot >= MAX_SKEL_BONES) {
        continue;
      }
      const float* f = reinterpret_cast<const float*>(&skel_matrix_buffer[slot]);
      for (int k = 0; k < 7 * 4; k++) {  // tmat[4] + nmat[3], skip pad
        if (!std::isfinite(f[k])) {
          any_bad = true;
          break;
        }
      }
    }
    if (any_bad) {
      // la reference est prise AVANT toute ecriture : un slot repare ne peut pas servir de source
      ShaderMercMat ref_copy = (hd_ref_slot >= 0) ? skel_matrix_buffer[hd_ref_slot] : kIdent;
      {
        // la reference est finie par sa tmat ; sa nmat peut ne pas l'etre (os a echelle nulle,
        // det = 0 -> 1/0 dans bones-mtx-calc) : elle est assainie a l'identite avant copie.
        float* rf = reinterpret_cast<float*>(&ref_copy);
        bool nbad = false;
        for (int k = 16; k < 7 * 4; k++) {
          if (!std::isfinite(rf[k])) {
            nbad = true;
            break;
          }
        }
        if (nbad) {
          for (int k = 16; k < 32; k++) {
            rf[k] = 0.f;
          }
          rf[16] = rf[21] = rf[26] = 1.f;
        }
      }
      for (int j = 0; j < i; j++) {
        int slot = input_data[j];
        if (slot >= MAX_SKEL_BONES) {
          continue;
        }
        float* f = reinterpret_cast<float*>(&skel_matrix_buffer[slot]);
        // Separate the transform matrix (tmat, floats 0-15) from the normal matrix
        // (nmat, floats 16-27). bones-mtx-calc derives nmat as the inverse-transpose of
        // tmat scaled by 1/det. A LEGITIMATELY degenerate (zero-scale) bone has det==0,
        // so the mips2c vdiv (1/0) yields inf and the whole nmat becomes NaN while the
        // tmat stays finite & correct. This happens IDENTICALLY on x86 (which has no
        // repair, so the collapsed bone simply renders invisible -- correct). Restore the
        // whole bone ONLY when the tmat (the position) is itself corrupt; when only the
        // nmat is non-finite, KEEP the finite tmat and sanitize just the nmat to identity
        // so Adreno never sees a NaN. This makes the arm64 logo render match x86 exactly.
        bool tmat_bad = false;
        for (int k = 0; k < 16; k++) {
          if (!std::isfinite(f[k])) {
            tmat_bad = true;
            break;
          }
        }
        bool nmat_bad = false;
        for (int k = 16; k < 7 * 4; k++) {
          if (!std::isfinite(f[k])) {
            nmat_bad = true;
            break;
          }
        }
        if (tmat_bad) {
          skel_matrix_buffer[slot] = ref_copy;
          gd3_bones_repaired++;
          hd_repaired_slot[slot] = true;
        } else if (nmat_bad) {
          // keep the finite, correct tmat; reset only the normal matrix to identity.
          for (int k = 16; k < 32; k++) {
            f[k] = 0.f;
          }
          f[16] = f[21] = f[26] = 1.f;  // nmat = identity
          gd3_bones_repaired++;
          hd_repaired_slot[slot] = true;
        }
      }
    }
  }
#endif
  hdskin_note_repair(gd3_bones_repaired);

  // === Ghd-skin-origin-stretch — SONDES « HDSKINLEN » et « HDCMD » (voir HdLenStats) ========
  // Placees APRES la reparation Gd3 : c'est skel_matrix_buffer tel qu'il part au GPU qui est
  // juge, pas ce que GOAL a ecrit. Chaque os HD fourni et LU par des sommets (minfo.used) dont
  // le parent est fourni est mesure deux fois :
  //   LONGUEUR : L = |pos(k) - pos(parent)| en espace camera contre L0, la meme distance en
  //              pose de bind (len_bad, HDLENEV) ;
  //   COMMANDE : dev = |pos(k) - cmd(k)|, ou cmd(k) = [bindpos_k, 1] . tmat_stock(e+1) est la
  //              position que l'animation du PILOTE commande a ce joint dans la MEME image
  //              (cmd_bad, HDCMDEV) — mode 0 seulement, pilote e mappe, capture stock de
  //              l'image courante.
  // Le VERDICT par os est l'union (hd_bad_bones / hd_bad_frames). Attributs qui separent les
  // mecanismes :
  //   nan   : L non finie (matrice non finie qui a survecu, ou x86 sans reparation)
  //   null  : les 16 floats de la t-mtx sont nuls (os jamais ecrit : sommets a l'origine)
  //   torn  : la memoire GOAL relue MAINTENANT differe de ce qu'on a copie — GOAL a reecrit
  //           la matrice pendant qu'on la consommait ; -1 si la reparation a modifie la copie
  //   same  : t-mtx identique au bit a celle du paquet precedent du meme pid (a lire avec gap)
  //   psame : idem pour le parent ; rep : slot reecrit par la reparation Gd3
  //   saut  : dev - dev de l'image precedente (« subitement » : l'ecart apparait d'un coup)
  hdlen_note_frame(render_state->frame_idx);
  if (is_hd_packet && owner_pid != 0) {
    s_hdlen.cur_hd = true;
    HdRig rig;
    bool have_rig = false;
    {
      std::lock_guard<std::mutex> lock(s_hd_rigs_mutex);
      auto it = s_hd_rigs.find(owner_pid);
      if (it != s_hd_rigs.end()) {
        it->second.last_seen = render_state->frame_idx;
        rig = it->second;
        have_rig = true;
      }
    }
    if (!have_rig) {
      // un zero d'etirement sans rig serait un zero vide : compte et publie dans le battement
      s_hdlen.hd_packets_norig++;
    } else {
      const HdSkinModelInfo& minfo = hdskin_model_info(model, lev);
      std::bitset<128> provided;
      for (int j = 0; j < i; j++) {
        int slot = input_data[j];
        if (slot < MAX_SKEL_BONES) {
          provided.set(slot);
        }
      }
      // LA COMMANDE : la capture stock du PILOTE de ce compagnon, si elle date de cette image.
      // Sans paire de couverture (builds sans HD) ou sans capture de l'image courante, aucun os
      // n'est compare et le paquet compte dans cmd_nostock — jamais un zero silencieux.
      u32 driver_pid = 0;
#ifdef OG_FEAT_HD_MODELS
      {
        std::lock_guard<std::mutex> lock(s_hd_cover_mutex);
        for (const auto& cp : s_hd_cover_pairs) {
          if (cp.companion_pid == owner_pid) {
            driver_pid = cp.driver_pid;
            break;
          }
        }
      }
#endif
      const HdStockCapture* stock = nullptr;
      s64 stock_gap = -1;  // -1 = aucune capture pour ce pilote ; 0 = meme image
      if (driver_pid != 0) {
        auto sit = s_hd_stock.find(driver_pid);
        if (sit != s_hd_stock.end()) {
          stock_gap = (s64)(render_state->frame_idx - sit->second.frame_idx);
          if (stock_gap == 0) {
            stock = &sit->second;
          }
        }
      }
      if (!stock) {
        s_hdlen.cmd_nostock++;
      }
      // L'ANNEAU GOAL : la cellule de CE paquet (emplacement du pid, image de l'estampille).
      // Appariee seulement si l'estampille de la cellule est celle du paquet — sinon la cellule
      // a ete recyclee (ou l'anneau/l'emplacement n'est pas enregistre) : ring_nostamp.
      const u8* ee_base = (const u8*)render_state->ee_main_memory;
      const float* ring_cam = nullptr;  // camera-rot de la cellule (16 floats, vecteur-ligne)
      const float* ring_wt = nullptr;   // ring[c*128 + 0] : joint k = ring_wt + 4*k
      bool stamp_ok = false;
      {
        int ring_slot = -1;
        {
          std::lock_guard<std::mutex> lock(s_hd_rigs_mutex);
          auto rs = s_hd_ring_slots.find(owner_pid);
          if (rs != s_hd_ring_slots.end()) {
            ring_slot = rs->second;
          }
        }
        const u32 ring_addr = s_hd_ring_addr.load();
        const u32 cam_addr = s_hd_ring_cam_addr.load();
        const u32 stamp_addr = s_hd_ring_stamp_addr.load();
        if (ring_slot >= 0 && ring_addr != 0 && cam_addr != 0 && stamp_addr != 0) {
          const int c = ring_slot * HD_RING_FRAMES + (int)(pkt_stamp & 3u);
          u32 ring_stamp = 0;
          std::memcpy(&ring_stamp, ee_base + stamp_addr + c * 16, sizeof(ring_stamp));
          if (ring_stamp == pkt_stamp) {
            stamp_ok = true;
            ring_cam = reinterpret_cast<const float*>(ee_base + cam_addr + c * 64);
            ring_wt = reinterpret_cast<const float*>(ee_base + ring_addr +
                                                     (c * HD_RING_JOINTS) * 16);
          }
        }
        if (!stamp_ok) {
          s_hdlen.ring_nostamp++;
        }
        // controle de l'anneau lui-meme, en face de HDRINGDBG (GOAL) : adresse, cellule, et le
        // joint 2 tel qu'on le relit — une ligne toutes les 300 images HD
        static u64 s_ringdbg_next = 0;
        if (render_state->frame_idx >= s_ringdbg_next) {
          s_ringdbg_next = render_state->frame_idx + 300;
          const int c = (ring_slot >= 0) ? ring_slot * HD_RING_FRAMES + (int)(pkt_stamp & 3u) : -1;
          printf("HDRINGDBGC pid=%u slot=%d cell=%d stamp=%u ring_addr=%u stamp_ok=%d wt2=(%.1f,%.1f,%.1f)\n",
                 owner_pid, ring_slot, c, pkt_stamp, ring_addr, stamp_ok ? 1 : 0,
                 ring_wt ? ring_wt[8] : -1.f, ring_wt ? ring_wt[9] : -1.f, ring_wt ? ring_wt[10] : -1.f);
          fflush(stdout);
        }
      }
      // `same` et `dev_prev` se lisent AVANT la mise a jour de la memoire du pid
      HdLenLast& last = s_hd_len_last[owner_pid];
      const u64 gap =
          (last.last_frame == ~0ull) ? 0 : (render_state->frame_idx - last.last_frame);
      std::bitset<128> same_now;
      for (int s = 0; s < MAX_SKEL_BONES; s++) {
        if (provided.test(s) && last.valid.test(s) &&
            std::memcmp(&skel_matrix_buffer[s], last.tmat[s].data(), 64) == 0) {
          same_now.set(s);
        }
      }
      float new_dev[MAX_SKEL_BONES] = {};
      std::bitset<128> new_dev_valid;
      struct HdLenHit {
        int k, parent;
        float len, rest, ratio, dev;
        float pos[3], ppos[3];
        float rows[3], prows[3], t[3];
        float goal_cam[3], d_goal;  // anneau GOAL : d_goal = -1 sans cellule appariee
        float stock_rows[3], hd_w;  // lignes de la t-mtx stock (-1 sans stock), w de l'os HD
        int nan, null, torn, same, psame, rep;
      };
      struct HdCmdHit {
        int k, e;
        float dev, dev_prev, saut, len_cmd, len_ren, angle;
        float ren[3], cmd[3];
        float rows[3], prows[3], t[3];
        float goal_cam[3], d_goal;
        float stock_rows[3], stock_w, hd_w;
        int torn, same, rep;
      };
      constexpr int HD_LEN_EV_PER_PACKET = 8;  // au plus 8 os publies par paquet, par sonde
      HdLenHit hits[HD_LEN_EV_PER_PACKET];
      HdCmdHit chits[HD_LEN_EV_PER_PACKET];
      int n_stretched = 0;  // TOUS les os etires (longueur) du paquet, publies ou non
      int n_lenev = 0;      // os candidats a HDLENEV : etires, base hors d'echelle, ou loin
                            // de ce que GOAL a ecrit
      int n_cmd = 0;        // TOUS les os loin de leur commande, publies ou non
      s_hdlen.packets_judged++;
      for (int k = 0; k < rig.n && k < MAX_SKEL_BONES - 1; k++) {
        const int s = k + 1;
        if (!rig.have[k] || !provided.test(s) || !minfo.used.test(s)) {
          continue;
        }
        const int pk = rig.parent[k];  // joint parent (255 = racine : rien a mesurer)
        if (pk == 255 || !rig.have[pk]) {
          continue;
        }
        const int ps = pk + 1;
        if (ps >= MAX_SKEL_BONES || !provided.test(ps)) {
          continue;
        }
        const float* f = reinterpret_cast<const float*>(&skel_matrix_buffer[s]);
        const float* pf = reinterpret_cast<const float*>(&skel_matrix_buffer[ps]);
        float pos[3], ppos[3];
        hdlen_joint_pos(f, rig.bp[k], pos);
        hdlen_joint_pos(pf, rig.bp[pk], ppos);
        const float dx = pos[0] - ppos[0], dy = pos[1] - ppos[1], dz = pos[2] - ppos[2];
        const float len = std::sqrt(dx * dx + dy * dy + dz * dz);
        const float bx = rig.bp[k][0] - rig.bp[pk][0], by = rig.bp[k][1] - rig.bp[pk][1],
                    bz = rig.bp[k][2] - rig.bp[pk][2];
        const float rest = std::sqrt(bx * bx + by * by + bz * bz);
        s_hdlen.bones_judged++;
        // LE PARENT EST-IL UN VRAI OS ? Les joints-racines du rig (align k=0, prejoint k=1 :
        // parent 255) portent une matrice MODEL-SPACE qu'aucun sommet ne lit. Mesure x86 c6inj1 :
        // le « bone » main->prejoint de Jak rend 15,2 m pour 1,44 m de repos A CHAQUE IMAGE
        // (298 evenements sur 600 cote squelette, `same=294` ici) — une constante, pas un
        // etirement. Un joint dont le parent est une racine n'a pas de longueur d'os mesurable :
        // il reste juge par l'ecart a la pose COMMANDEE, plus bas.
        const bool len_ok = rig.parent[pk] != 255;
        const bool is_nan = len_ok && !std::isfinite(len);
        const bool len_bad = len_ok && (is_nan || (len > HD_LEN_RATIO * rest + HD_LEN_FLOOR_U));

        // --- la t-mtx STOCK du pilote de ce joint (meme image), reference commune de la
        //     commande et de l'echelle : mode 0, pilote mappe, slot e+1 fourni par le stock ---
        const float* stock_f = nullptr;
        if (stock && rig.mode[k] == 0 && rig.e[k] != 255) {
          const int es = rig.e[k] + 1;
          if (es < MAX_SKEL_BONES && stock->provided.test(es)) {
            stock_f = stock->tmat[es];
          }
        }
        // LE w DES MATRICES. Cause trouvee cote GOAL : une composante w != 1 sur la ligne 3 des
        // matrices pilote, multipliee par cam3 (l'origine du monde en camera) deplace le joint
        // de (1 - w3) x |cam3| (10 m a finalboss). Le correctif GOAL rend les matrices HD
        // affines ; le paquet STOCK, lui, n'est pas notre chemin et porte encore w3 ~ 0,998 :
        // la commande derivee du stock est donc elle-meme deplacee de (1 - w3) x |cam3|
        // (cmd_bones=54252 avec le correctif arme, ring_far=0). f[15] des deux matrices est
        // publie a cote de chaque ecart : c'est la preuve que l'ecart est porte par le w stock.
        const float hd_w = f[15];
        const float stock_w = stock_f ? stock_f[15] : -1.f;
        if (std::fabs(hd_w - 1.f) > HD_W_EPS) {
          s_hdlen.hd_w_bad++;
        }
        if (stock_f && std::fabs(stock_w - 1.f) > HD_W_EPS) {
          s_hdlen.stock_w_bad++;
        }

        // --- la base : lignes de l'os et du parent, RELATIVES a la ligne correspondante de la
        //     t-mtx stock du pilote (voir HD_SCL_REL_MAX). L'absolu [0,2 ; 5] reste publie en
        //     diagnostic (scl_abs_bones) mais ne juge plus. ---
        float rows[3], prows[3], stock_rows[3] = {-1.f, -1.f, -1.f};
        hdlen_rows(f, rows);
        hdlen_rows(pf, prows);
        const float rmax = std::max(rows[0], std::max(rows[1], rows[2]));
        const float rmin = std::min(rows[0], std::min(rows[1], rows[2]));
        // comme la longueur (len_ok) : pas sur un joint dont le parent est une racine du rig —
        // mesure x86 c6ring3 : 248 « echelles » et 952 « longueurs GOAL » toutes sur k=2
        // (main -> prejoint, matrice model-space), a chaque image, jamais lues par un sommet
        const bool scl_abs_bad = len_ok && (!std::isfinite(rmax) || !std::isfinite(rmin) ||
                                            rmax > HD_SCL_MAX_ROW || rmin < HD_SCL_MIN_ROW);
        if (scl_abs_bad) {
          s_hdlen.scl_abs_bones++;
        }
        bool scl_bad = false;
        if (stock_f) {
          hdlen_rows(stock_f, stock_rows);
        }
        if (stock_f && len_ok && stock_rows[0] >= HD_SCL_STOCK_ROW_EPS &&
            stock_rows[1] >= HD_SCL_STOCK_ROW_EPS && stock_rows[2] >= HD_SCL_STOCK_ROW_EPS) {
          float rel[3];
          for (int r = 0; r < 3; r++) {
            rel[r] = rows[r] / stock_rows[r];
          }
          const float rel_max = std::max(rel[0], std::max(rel[1], rel[2]));
          const float rel_min = std::min(rel[0], std::min(rel[1], rel[2]));
          scl_bad = !std::isfinite(rel_max) || !std::isfinite(rel_min) ||
                    rel_max > HD_SCL_REL_MAX || rel_min < HD_SCL_REL_MIN;
          if (scl_bad) {
            s_hdlen.scl_bones++;
            s_hdlen.cur_scl = true;
            // le pire facteur RELATIF : max(rel_max, 1/rel_min) quand rel_min > 0
            const float w = hdlen_row_worst(rel);
            if (std::isfinite(w) && w > s_hdlen.scl_worst) {
              s_hdlen.scl_worst = w;
            }
          }
        } else {
          // sans reference stock (pas de capture, hors mode 0, pilote non fourni, ligne stock
          // nulle) ou sous une racine : l'echelle n'est pas jugee, et ca se compte
          s_hdlen.scl_unjudged++;
        }

        // --- la commande ---
        bool cmd_ok = false, cmd_bad = false;
        float dev = -1.f, dev_prev = -1.f, saut = 0.f, len_cmd = -1.f, angle = -1.f;
        float cmd[3] = {0.f, 0.f, 0.f};
        if (stock_f) {
          hdlen_joint_pos(stock_f, rig.bp[k], cmd);
          const float cx = pos[0] - cmd[0], cy = pos[1] - cmd[1], cz = pos[2] - cmd[2];
          dev = std::sqrt(cx * cx + cy * cy + cz * cz);
          cmd_ok = true;
          s_hdlen.cmd_judged++;
          cmd_bad = !std::isfinite(dev) || dev > HD_CMD_DEV_U;
          // « subit » : dev_prev = -1 sans echantillon anterieur, et le saut vaut alors dev
          // entier (l'ecart est apparu dans la fenetre d'observation)
          dev_prev = last.dev_valid.test(s) ? last.dev[s] : -1.f;
          saut = (dev_prev >= 0.f) ? dev - dev_prev : dev;
          new_dev[s] = dev;
          new_dev_valid.set(s);
          if (std::isfinite(dev) && dev / 4096.f > s_hdlen.cmd_worst_m) {
            s_hdlen.cmd_worst_m = dev / 4096.f;
          }
          // longueur et direction commandees de l'os, si le parent est lui aussi commande
          if (rig.mode[pk] == 0 && rig.e[pk] != 255) {
            const int eps = rig.e[pk] + 1;
            if (eps < MAX_SKEL_BONES && stock->provided.test(eps)) {
              float cmd_p[3];
              hdlen_joint_pos(stock->tmat[eps], rig.bp[pk], cmd_p);
              const float vx = cmd[0] - cmd_p[0], vy = cmd[1] - cmd_p[1],
                          vz = cmd[2] - cmd_p[2];
              len_cmd = std::sqrt(vx * vx + vy * vy + vz * vz);
              // angle entre l'os rendu (dx,dy,dz) et l'os commande (vx,vy,vz), en degres,
              // seulement si les deux font plus de 0,05 m : sous ca, la direction est du bruit
              if (len > HD_CMD_ANGLE_MIN_U && len_cmd > HD_CMD_ANGLE_MIN_U &&
                  std::isfinite(len) && std::isfinite(len_cmd)) {
                float c = (dx * vx + dy * vy + dz * vz) / (len * len_cmd);
                c = std::max(-1.f, std::min(1.f, c));
                angle = std::acos(c) * (180.f / 3.14159265f);
              }
            }
          }
        }
        // --- l'anneau GOAL, sur TOUS les os juges : ce que le squelette a ECRIT pour ce joint
        //     a cette image (W.t monde), passe par la camera-rot de la meme cellule, contre la
        //     position derivee de ce que le GPU consomme. Independant du bind (longueur) et du
        //     paquet stock (commande) : troisieme critere de verdict. ---
        float goal_cam[3] = {0.f, 0.f, 0.f};
        float d_goal = -1.f;
        bool ring_bad_bone = false;
        if (stamp_ok) {
          const float* wt = ring_wt + 4 * k;
          hdlen_joint_pos(ring_cam, wt, goal_cam);
          const float gx = pos[0] - goal_cam[0], gy = pos[1] - goal_cam[1],
                      gz = pos[2] - goal_cam[2];
          d_goal = std::sqrt(gx * gx + gy * gy + gz * gz);
          s_hdlen.ring_judged++;
          // LE VERDICT DE L'ANNEAU EST SANS CAMERA. Mesure x86 c6ring2 : `d_goal` (position
          // derivee contre W.t passe par la camera-rot lue au :post du compagnon) valait 255 m sur
          // TOUS les os des 900 premieres images (ecran-titre : la camera de `*math-camera*` au
          // moment du :post n'est pas celle que bones-mtx-calc applique en fin d'image), puis
          // ~0 en jeu — et a 30 images/s une camera qui suit un personnage a 10 m/s bouge de
          // 0,33 m par image, plus que le seuil. On compare donc la LONGUEUR d'os consommee
          // (|pos_k - pos_p|, espace camera, rigide) a la longueur ECRITE par GOAL
          // (|W.t_k - W.t_p|, monde) : invariante par toute transformation rigide, donc par la
          // camera, quelle qu'elle soit. `d_goal` reste publie comme diagnostic.
          const float* wtp = ring_wt + 4 * pk;
          const float wx = wt[0] - wtp[0], wy = wt[1] - wtp[1], wz = wt[2] - wtp[2];
          const float glen = std::sqrt(wx * wx + wy * wy + wz * wz);
          const float d_len = std::fabs(len - glen);
          ring_bad_bone = len_ok && (!std::isfinite(d_len) || d_len > HD_RING_FAR_U);
          if (ring_bad_bone) {
            s_hdlen.ring_far++;
          }
        }
        if (!len_bad && !cmd_bad && !scl_bad && !ring_bad_bone) {
          continue;
        }
        // --- attributs communs, calcules une fois par os mauvais (union des quatre) ---
        s_hdlen.hd_bad_bones++;
        s_hdlen.cur_hd_bad = true;
        // attribution : GOAL l'avait-il ecrit tel quel (ring_ok), ou l'os a-t-il ete corrompu
        // entre l'ecriture et la consommation (ring_bad) ? Seulement sur une cellule appariee.
        // Sans camera (voir plus haut) : la longueur d'os consommee est-elle celle que GOAL a
        // ecrite ? `ring_bad_bone` est exactement « non » ; `ring_ok` = l'os est mauvais (bind,
        // commande ou echelle) MAIS a la longueur ecrite par GOAL — le defaut est ne dans GOAL.
        if (stamp_ok) {
          if (!ring_bad_bone) {
            s_hdlen.ring_ok++;
          } else {
            s_hdlen.ring_bad++;
          }
        }
        bool all_zero = true;
        for (int z = 0; z < 16; z++) {
          if (f[z] != 0.f) {
            all_zero = false;
            break;
          }
        }
        const int a_null = all_zero ? 1 : 0;
        const int a_rep = hd_repaired_slot[s] ? 1 : 0;
        int a_torn;
        if (hd_repaired_slot[s]) {
          a_torn = -1;
        } else {
          const u8* now = (const u8*)render_state->ee_main_memory + hd_slot_addr[s];
          a_torn = (std::memcmp(now, &skel_matrix_buffer[s], 64) != 0) ? 1 : 0;
        }
        const int a_same = same_now.test(s) ? 1 : 0;
        const int a_psame = same_now.test(ps) ? 1 : 0;
        // HDLENEV : os etire (longueur), a base hors d'echelle, OU loin de ce que GOAL a ecrit —
        // les lignes de base, la translation brute et la position ecrite par GOAL publiees a
        // cote departagent « base explosee », « translation fausse » et « corrompu apres
        // l'ecriture ». Les compteurs de longueur (hd_stretch_bones, nan/null/rep/torn/same) ne
        // comptent que les os ETIRES, comme avant.
        if (len_bad || scl_bad || ring_bad_bone) {
          HdLenHit scratch;
          HdLenHit& h = (n_lenev < HD_LEN_EV_PER_PACKET) ? hits[n_lenev] : scratch;
          n_lenev++;
          h.k = k;
          h.parent = pk;
          h.len = len;
          h.rest = rest;
          // ratio = -1 quand L0 = 0 (joint coincident) : « infini » ne se publie pas en %.2f
          h.ratio = (rest > 0.f && std::isfinite(len)) ? len / rest : -1.f;
          h.dev = cmd_ok ? dev : -1.f;
          std::memcpy(h.pos, pos, sizeof(pos));
          std::memcpy(h.ppos, ppos, sizeof(ppos));
          std::memcpy(h.rows, rows, sizeof(rows));
          std::memcpy(h.prows, prows, sizeof(prows));
          h.t[0] = f[12];
          h.t[1] = f[13];
          h.t[2] = f[14];
          std::memcpy(h.goal_cam, goal_cam, sizeof(goal_cam));
          h.d_goal = d_goal;
          std::memcpy(h.stock_rows, stock_rows, sizeof(stock_rows));
          h.hd_w = hd_w;
          h.nan = is_nan ? 1 : 0;
          h.null = a_null;
          h.rep = a_rep;
          h.torn = a_torn;
          h.same = a_same;
          h.psame = a_psame;
          if (len_bad) {
            n_stretched++;
            s_hdlen.hd_stretch_bones++;
            s_hdlen.nan_bones += h.nan;
            s_hdlen.null_bones += h.null;
            s_hdlen.rep_bones += h.rep;
            s_hdlen.torn_bones += (h.torn == 1) ? 1 : 0;
            s_hdlen.same_bones += h.same;
            if (!is_nan) {
              if (h.ratio > s_hdlen.worst_ratio) {
                s_hdlen.worst_ratio = h.ratio;
              }
              if (len / 4096.f > s_hdlen.worst_m) {
                s_hdlen.worst_m = len / 4096.f;
              }
            }
          }
        }
        if (cmd_bad) {
          HdCmdHit scratch;
          HdCmdHit& c = (n_cmd < HD_LEN_EV_PER_PACKET) ? chits[n_cmd] : scratch;
          n_cmd++;
          c.k = k;
          c.e = rig.e[k];
          c.dev = dev;
          c.dev_prev = dev_prev;
          c.saut = saut;
          c.len_cmd = len_cmd;
          c.len_ren = len;
          c.angle = angle;
          std::memcpy(c.ren, pos, sizeof(pos));
          std::memcpy(c.cmd, cmd, sizeof(cmd));
          std::memcpy(c.rows, rows, sizeof(rows));
          std::memcpy(c.prows, prows, sizeof(prows));
          c.t[0] = f[12];
          c.t[1] = f[13];
          c.t[2] = f[14];
          std::memcpy(c.goal_cam, goal_cam, sizeof(goal_cam));
          c.d_goal = d_goal;
          std::memcpy(c.stock_rows, stock_rows, sizeof(stock_rows));
          c.stock_w = stock_w;
          c.hd_w = hd_w;
          c.torn = a_torn;
          c.same = a_same;
          c.rep = a_rep;
          s_hdlen.cmd_bones++;
          s_hdlen.cur_cmd = true;
        }
      }
      if (n_stretched > 0) {
        s_hdlen.cur_hd_stretch = true;
      }
      if (n_lenev > 0) {
        // au plus 8 os par paquet, 150 lignes en tout : le battement porte le reste
        for (int e = 0; e < n_lenev && e < HD_LEN_EV_PER_PACKET && s_hdlen.ev_logs < 150; e++) {
          const HdLenHit& h = hits[e];
          s_hdlen.ev_logs++;
          printf("HDLENEV frame=%llu model=%s pid=%u k=%d parent=%d len_m=%.3f rest_m=%.3f "
                 "ratio=%.2f pos=(%.2f,%.2f,%.2f) ppos=(%.2f,%.2f,%.2f) nan=%d null=%d torn=%d "
                 "same=%d psame=%d gap=%llu rep=%d n_stretched=%d dev_m=%.3f stock_gap=%lld "
                 "rows=(%.2f,%.2f,%.2f) prows=(%.2f,%.2f,%.2f) t=(%.2f,%.2f,%.2f) "
                 "stamp_ok=%d goal_cam=(%.2f,%.2f,%.2f) d_goal_m=%.3f "
                 "stock_rows=(%.2f,%.2f,%.2f) hd_w=%.4f\n",
                 (unsigned long long)render_state->frame_idx, name, owner_pid, h.k, h.parent,
                 h.len / 4096.f, h.rest / 4096.f, h.ratio, h.pos[0] / 4096.f, h.pos[1] / 4096.f,
                 h.pos[2] / 4096.f, h.ppos[0] / 4096.f, h.ppos[1] / 4096.f, h.ppos[2] / 4096.f,
                 h.nan, h.null, h.torn, h.same, h.psame, (unsigned long long)gap, h.rep,
                 n_stretched, h.dev >= 0.f ? h.dev / 4096.f : -1.f, (long long)stock_gap,
                 h.rows[0], h.rows[1], h.rows[2], h.prows[0], h.prows[1], h.prows[2],
                 h.t[0] / 4096.f, h.t[1] / 4096.f, h.t[2] / 4096.f, stamp_ok ? 1 : 0,
                 h.goal_cam[0] / 4096.f, h.goal_cam[1] / 4096.f, h.goal_cam[2] / 4096.f,
                 h.d_goal >= 0.f ? h.d_goal / 4096.f : -1.f, h.stock_rows[0], h.stock_rows[1],
                 h.stock_rows[2], h.hd_w);
        }
        fflush(stdout);
      }
      if (n_cmd > 0) {
        for (int e = 0; e < n_cmd && e < HD_LEN_EV_PER_PACKET && s_hdlen.ev_logs_cmd < 150;
             e++) {
          const HdCmdHit& c = chits[e];
          s_hdlen.ev_logs_cmd++;
          printf("HDCMDEV frame=%llu model=%s pid=%u drv=%u k=%d e=%d dev_m=%.3f "
                 "dev_prev_m=%.3f saut_m=%.3f len_cmd_m=%.3f len_ren_m=%.3f angle_deg=%.1f "
                 "ren=(%.2f,%.2f,%.2f) cmd=(%.2f,%.2f,%.2f) torn=%d same=%d rep=%d "
                 "stock_gap=%lld rows=(%.2f,%.2f,%.2f) prows=(%.2f,%.2f,%.2f) "
                 "t=(%.2f,%.2f,%.2f) stamp_ok=%d goal_cam=(%.2f,%.2f,%.2f) d_goal_m=%.3f "
                 "stock_rows=(%.2f,%.2f,%.2f) stock_w=%.4f hd_w=%.4f\n",
                 (unsigned long long)render_state->frame_idx, name, owner_pid, driver_pid, c.k,
                 c.e, c.dev / 4096.f, c.dev_prev >= 0.f ? c.dev_prev / 4096.f : -1.f,
                 c.saut / 4096.f, c.len_cmd >= 0.f ? c.len_cmd / 4096.f : -1.f,
                 c.len_ren / 4096.f, c.angle, c.ren[0] / 4096.f, c.ren[1] / 4096.f,
                 c.ren[2] / 4096.f, c.cmd[0] / 4096.f, c.cmd[1] / 4096.f, c.cmd[2] / 4096.f,
                 c.torn, c.same, c.rep, (long long)stock_gap, c.rows[0], c.rows[1], c.rows[2],
                 c.prows[0], c.prows[1], c.prows[2], c.t[0] / 4096.f, c.t[1] / 4096.f,
                 c.t[2] / 4096.f, stamp_ok ? 1 : 0, c.goal_cam[0] / 4096.f,
                 c.goal_cam[1] / 4096.f, c.goal_cam[2] / 4096.f,
                 c.d_goal >= 0.f ? c.d_goal / 4096.f : -1.f, c.stock_rows[0], c.stock_rows[1],
                 c.stock_rows[2], c.stock_w, c.hd_w);
        }
        fflush(stdout);
      }
      // memoire du pid pour le prochain paquet : les t-mtx CONSOMMEES (post-reparation) et
      // l'ecart a la commande de chaque os compare
      for (int s = 0; s < MAX_SKEL_BONES; s++) {
        if (provided.test(s)) {
          std::memcpy(last.tmat[s].data(), &skel_matrix_buffer[s], 64);
        }
        last.dev[s] = new_dev[s];
      }
      last.valid = provided;
      last.dev_valid = new_dev_valid;
      last.last_frame = render_state->frame_idx;
    }
  }

  // Gjak2-visuals probe: per-model one-shot of bone-translation magnitude and
  // light colors — the white wash bisects to the plain-merc bucket family, and
  // huge-but-finite garbage matrices (wrong-address reads) or blown lights
  // pass the NaN repair above untouched. Diffable our-x86 (env GJ2VIS_TFTREE)
  // vs device (always). Logs each model once, and once more if it turns huge.
  {
#ifdef __ANDROID__
    static const bool s_merc_dump = true;
#else
    static const bool s_merc_dump = getenv("GJ2VIS_TFTREE") != nullptr;
#endif
    if (s_merc_dump) {
      float max_t = 0.f;
      for (int j = 0; j < i; j++) {
        int slot = input_data[j];
        if (slot >= MAX_SKEL_BONES) {
          continue;
        }
        const float* f = reinterpret_cast<const float*>(&skel_matrix_buffer[slot]);
        for (int k = 12; k < 15; k++) {  // tmat translation row
          float a = std::fabs(f[k]);
          if (a > max_t) {
            max_t = a;
          }
        }
      }
      const bool huge = max_t > 1e8f;
      static std::set<std::string> s_seen_models;
      static std::set<std::string> s_seen_huge;
      bool log_it = huge ? s_seen_huge.insert(name).second : s_seen_models.insert(name).second;
      if (log_it) {
        fprintf(stderr,
                "GJ2VIS-MERCMODEL name=%s bones=%d maxT=%.3e huge=%d "
                "l0=(%.2f %.2f %.2f) l1=(%.2f %.2f %.2f) l2=(%.2f %.2f %.2f) amb=(%.2f %.2f "
                "%.2f)\n",
                name, i, max_t, huge ? 1 : 0, current_lights.color0.x(), current_lights.color0.y(),
                current_lights.color0.z(), current_lights.color1.x(), current_lights.color1.y(),
                current_lights.color1.z(), current_lights.color2.x(), current_lights.color2.y(),
                current_lights.color2.z(), current_lights.ambient.x(), current_lights.ambient.y(),
                current_lights.ambient.z());
      }
    }
  }

  input_data += 128 + 16 * i;

  // Next part is some flags
  struct PcMercFlags {
    u64 enable_mask;
    u64 ignore_alpha_mask;
    u8 effect_count;
    u8 bitflags;
  };
  auto* flags = (const PcMercFlags*)input_data;
  int num_effects = flags->effect_count;  // mostly just a sanity check
  ASSERT(num_effects < kMaxEffect);
  u64 current_ignore_alpha_bits = flags->ignore_alpha_mask;  // shader settings
  u64 current_effect_enable_bits = flags->enable_mask;       // mask for game to disable an effect
  bool model_uses_mod = flags->bitflags & 1;  // if we should update vertices from game.
  bool model_disables_fog = flags->bitflags & 2;
  bool model_uses_pc_blerc = flags->bitflags & 4;
  bool model_disables_envmap = flags->bitflags & 8;
  bool model_no_texture = flags->bitflags & 16;
  input_data += 32;

  float blerc_weights[kMaxBlerc];
  if (model_uses_pc_blerc) {
    memcpy(blerc_weights, input_data, kMaxBlerc * sizeof(float));
    input_data += kMaxBlerc * sizeof(float);
  }

  // Next is "fade data", indicating the color/intensity of envmap effect
  u8 fade_buffer[4 * kMaxEffect];
  memset(fade_buffer, 0, sizeof(fade_buffer));  // custom models can have MORE effects than GOAL
                                                // sent fades for; their tail must not be garbage
  for (int ei = 0; ei < num_effects; ei++) {
    for (int j = 0; j < 4; j++) {
      fade_buffer[ei * 4 + j] = input_data[ei * 4 + j];
    }
  }
  input_data += (((num_effects * 4) + 15) / 16) * 16;

  // Next is pointers to merc data, needed so we can update vertices

  // custom models are likely to have a different number of effects than what GOAL reports, update
  // the count here (after reading DMA) so we don't potentially go out of bounds when we do
  // blerc/mod draws
  if (model->effects.at(0).all_draws.at(0).no_strip) {
    num_effects = model->effects.size();
    // GOAL builds enable_mask (and fades) from the merc-ctrl's effect count — 1 for fabricated
    // HD-actor shells — so fr3 effects beyond it would be skipped by the enable check below.
    // Enable them; GOAL keeps authority over the effects it actually knows.
    current_effect_enable_bits |= ~0ull << flags->effect_count;
    // CYCLE-3 (Daxter fur holes / missing lower face): PS2 semantics — an ENVMAP effect's
    // texture alpha is the envmap/sheen INTENSITY MASK, not opacity (TCC_RGB; jak3's
    // foreground.gc forces ignore-alpha=1 on envmap effects). Daxter's head texture is 51%
    // alpha<8, so rendering it with ignore_alpha=0 made merc2.frag discard half his head.
    // GOAL's ignore_alpha_mask only covers the fabricated shell effect, so derive the bits
    // from the fr3 itself (has_envmap ported from the donor by hd_merc_swap) for ALL effects.
    for (size_t ei = 0; ei < model->effects.size() && ei < 64; ei++) {
      if (model->effects[ei].has_envmap) {
        current_ignore_alpha_bits |= 1ull << ei;
        // GOAL also sent no envmap FADES for effects it doesn't know (their tail is zeroed
        // above) and a zero fade SKIPS the envmap draw entirely (try_alloc_envmap_draw).
        // Default to neutral full intensity: 0x80/255 doubled by the emerc shader = 1.0.
        if (ei < (size_t)kMaxEffect) {
          u8* f = fade_buffer + 4 * ei;
          if (!f[0] && !f[1] && !f[2] && !f[3]) {
            f[0] = f[1] = f[2] = f[3] = 0x80;
          }
        }
      }
    }
  }

  // will hold opengl buffers for the updated vertices
  ModBuffers mod_opengl_buffers[kMaxEffect];
  if (model_uses_pc_blerc) {
    model_mod_blerc_draws(num_effects, model, lev, mod_opengl_buffers, blerc_weights, stats);
  } else if (model_uses_mod) {  // only if we've enabled, this path is slow.
    model_mod_draws(num_effects, model, lev, input_data,
                    (const u8*)render_state->ee_main_memory, mod_opengl_buffers, stats);
  }

  // stats
  stats->num_models++;
  for (const auto& effect : model_ref->model->effects) {
    bool envmap = effect.has_envmap && !model_disables_envmap;
    stats->num_effects++;
    stats->num_predicted_draws += effect.all_draws.size();
    if (envmap) {
      stats->num_envmap_effects++;
      stats->num_predicted_draws += effect.all_draws.size();
    }
    for (const auto& draw : effect.all_draws) {
      stats->num_predicted_tris += draw.num_triangles;
      if (envmap) {
        stats->num_predicted_tris += draw.num_triangles;
      }
    }
  }

  if (stats->collect_debug_model_list) {
    auto& d = stats->model_list.emplace_back();
    d.name = model->name;
    d.level = model_ref->level->level->level_name;
    for (auto& e : model->effects) {
      auto& de = d.effects.emplace_back();
      de.envmap = e.has_envmap;
      de.envmap_mode = e.envmap_mode;
      for (auto& draw : e.all_draws) {
        auto& dd = de.draws.emplace_back();
        dd.mode = draw.mode;
        dd.num_tris = draw.num_triangles;
      }
    }
  }

  // allocate bones in shared bone buffer to be sent to GPU at flush-time
  u32 first_bone = alloc_bones(bone_count, skel_matrix_buffer);

  // allocate lights
  if (current_lights.w1) {
    if (render_state->version != GameVersion::Jak3) {
      current_lights.w1 = 0;  // force off merc fade in jak2/1 - a bunch of stuff uses this
    }
  }
  u32 lights = alloc_lights(current_lights);
  stats->num_lights++;

  u64 hash = fnv64(model->name);

  DrawArgs args;
  args.lev_bucket = lev_bucket;
  args.jak1_water_mode = uses_water;
  args.disable_fog = model_disables_fog;
  args.hash = hash;
  args.lights = lights;
  args.first_bone = first_bone;
  args.no_texture = render_state->version == GameVersion::Jak3 && model_no_texture;
  // Grecharged-title-logo-fullres: route the title/ND logo family out of the render-scaled 3D
  // pass so it can be replayed at native resolution after the UI composite. Every condition must
  // hold, so the stock path is what runs whenever the feature is off, the master is off, the
  // split is inactive (RENDER SCALE 100% => begin_2d_ui_pass is nullptr) or the game isn't jak1.
  // Models that stream vertices per frame (blerc / mod-vtx) are excluded: their vertex buffers
  // are recycled within the frame, so a deferred replay would read someone else's geometry.
  args.defer_native = render_state->version == GameVersion::Jak1 &&
                      render_state->begin_2d_ui_pass && !model_uses_pc_blerc && !model_uses_mod &&
                      merc2_is_native_overlay_model(name) &&
                      Gfx::recharged_active(Gfx::g_global_settings.recharged_crisp_title_logo);

  // loop over effects, creating draws for each
  int gd3_vis_tris = 0;  // Gd3-jak: tris surviving the enable/debug filter (Jak's visible count)
  for (size_t ei = 0; ei < model->effects.size(); ei++) {
    args.fade = fade_buffer + 4 * ei;

    // game has disabled it?
    if (!(current_effect_enable_bits & (1ull << ei))) {
      continue;
    }

    // imgui menu disabled it?
    if (!m_effect_debug_mask[ei]) {
      continue;
    }

    bool ignore_alpha = !!(current_ignore_alpha_bits & (1ull << ei));
    args.ignore_alpha = ignore_alpha;
    auto& effect = model->effects[ei];
    if (gd3_is_jak) {
      for (const auto& d : effect.all_draws) {
        gd3_vis_tris += d.num_triangles;
      }
    }

    bool should_envmap = effect.has_envmap && !model_disables_envmap;
    bool should_mod = (model_uses_pc_blerc || model_uses_mod) && effect.has_mod_draw;

    if (should_mod) {
      // draw as two parts, fixed and mod

      // do fixed draws:
      for (auto& fdraw : effect.mod.fix_draw) {
        alloc_normal_draw(fdraw, args);
        if (should_envmap) {
          try_alloc_envmap_draw(fdraw, effect.envmap_mode, effect.envmap_texture, args);
        }
      }

      // do mod draws
      for (auto& mdraw : effect.mod.mod_draw) {
        auto n = alloc_normal_draw(mdraw, args);
        // modify the draw, set the mod flag and point it to the opengl buffer
        n->flags |= MOD_VTX;
        n->mod_vtx_buffer = mod_opengl_buffers[ei];
        if (should_envmap) {
          auto e = try_alloc_envmap_draw(mdraw, effect.envmap_mode, effect.envmap_texture, args);
          if (e) {
            e->flags |= MOD_VTX;
            e->mod_vtx_buffer = mod_opengl_buffers[ei];
          }
        }
      }
    } else {
      // no mod, just do all_draws
      for (auto& draw : effect.all_draws) {
        if (should_envmap) {
          try_alloc_envmap_draw(draw, effect.envmap_mode, effect.envmap_texture, args);
        }
        alloc_normal_draw(draw, args);
      }
    }
  }

  // Gd3-jak observability (property-armed via debug.opengoal.gd3.census / OG_GD3_CENSUS,
  // OFF by default — mirrors the gpose tripwire precedent). Confirms Jak (eichar) draws
  // with effects enabled and finite bones after the repair above. repaired_total>0 proves
  // the NaN-bone class was hit and fixed (the sig=11 Adreno fault + pose-blink cause).
  if (gd3_is_jak) {
    static int s_jak_tick = 0;
    static long long s_repaired_total = 0;
    s_repaired_total += gd3_bones_repaired;
    if (gd3_bones_repaired > 0 || (s_jak_tick++ % 16) == 0) {
      fmt::print(
          "GD3-MERC model={} neff={} enable=0x{:x} ialpha=0x{:x} visible={} repaired_now={} "
          "repaired_total={}\n",
          name, num_effects, (unsigned long long)current_effect_enable_bits,
          (unsigned long long)current_ignore_alpha_bits, gd3_vis_tris, gd3_bones_repaired,
          s_repaired_total);
      fflush(stdout);
    }
  }

  // Gecho-pool Merc2 census (TEMPORARY): log models rendering via Merc2. Always logs any
  // model whose name looks pool/water-related; samples others every 32 calls to bound volume.
  if (gecho_merc_on()) {
    const bool poolish = std::strstr(name, "water") || std::strstr(name, "eco") ||
                         std::strstr(name, "anim") || std::strstr(name, "misty") ||
                         std::strstr(name, "ripple");
    static int s_merc_tick = 0;
    if (poolish || (s_merc_tick++ % 32) == 0) {
      printf("GECHO-MERC model=%s neff=%d tris=%d poolish=%d\n", name, num_effects, gd3_vis_tris,
             poolish ? 1 : 0);
      fflush(stdout);
    }
  }

  // F1 (Geyser Rock) observability — property-armed via OG_F1_CENSUS /
  // debug.opengoal.f1.census, OFF by default and INDEPENDENT of the gd3 gate
  // above (the gd3 gate is coupled to OG_GD3_CENSUS, so we re-derive the eichar
  // check here from `name` rather than reusing gd3_is_jak). Each time Jak
  // (eichar) is drawn we read his authoritative world position directly from EE
  // memory: (-> *target* control trans). Offsets obtained from goalc on a live
  // x86 listener:
  //   CONTROL_OFFSET = 108  ((&-> (the-as target ptr0) control); control is
  //                          :overlay-at root -> the process-drawable root field)
  //   TRANS_OFFSET   = 12   ((&-> (the-as control-info ptr0) trans x); trans is
  //                          a vector :inline inside the trsqv-derived control-info)
  // GOAL pointer convention: host addr = g_ee_main_mem + goal_offset (mirrors
  // sceGraphicsInterface.cpp's *math-camera* probe). #f / unbound == s7.offset.
  if (f1_census_on() && std::strstr(name, "eichar") != nullptr &&
      g_game_version == GameVersion::Jak1 && g_ee_main_mem) {
    constexpr u32 CONTROL_OFFSET = 108;
    constexpr u32 TRANS_OFFSET = 12;
    auto s_tgt = jak1::intern_from_c("*target*");
    u32 tgt = s_tgt.offset ? s_tgt->value : 0;
    // skip when not in gameplay: symbol unbound (0) or #f (== s7.offset)
    if (tgt != 0 && tgt != s7.offset && tgt < (u32)(EE_MAIN_MEM_SIZE - 4)) {
      // control == process-drawable root: a 4-byte GOAL pointer to a control-info
      u32 ctrl = 0;
      std::memcpy(&ctrl, g_ee_main_mem + tgt + CONTROL_OFFSET, 4);
      if (ctrl != 0 && ctrl != s7.offset &&
          ctrl < (u32)(EE_MAIN_MEM_SIZE - (TRANS_OFFSET + 12))) {
        float tx = 0.f, ty = 0.f, tz = 0.f;
        std::memcpy(&tx, g_ee_main_mem + ctrl + TRANS_OFFSET + 0, 4);
        std::memcpy(&ty, g_ee_main_mem + ctrl + TRANS_OFFSET + 4, 4);
        std::memcpy(&tz, g_ee_main_mem + ctrl + TRANS_OFFSET + 8, 4);
        // genuine in-game marker: fire exactly once, gated on a valid target in
        // a loaded level (so it never prints from the title/attract path).
        static bool s_f1_in_game_announced = false;
        if (!s_f1_in_game_announced) {
          s_f1_in_game_announced = true;
          printf("engine: state=in-game\n");
          fflush(stdout);
        }
        printf("F1-STATE tx=%f ty=%f tz=%f\n", tx, ty, tz);
        fflush(stdout);
      }
    }
  }
}

void Merc2::draw_debug_window(MercDebugStats* stats) {
  ImGui::Text("Models   : %d", stats->num_models);
  ImGui::Text("Effects  : %d", stats->num_effects);
  ImGui::Text("Draws (p): %d", stats->num_predicted_draws);
  ImGui::Text("Tris  (p): %d", stats->num_predicted_tris);
  ImGui::Text("Bones    : %d", stats->num_bones_uploaded);
  ImGui::Text("Lights   : %d", stats->num_lights);
  ImGui::Text("Dflush   : %d", stats->num_draw_flush);

  ImGui::Text("EEffects : %d", stats->num_envmap_effects);
  ImGui::Text("ETris    : %d", stats->num_envmap_tris);

  ImGui::Text("Uploads  : %d", stats->num_uploads);
  ImGui::Text("Upload kB: %d", stats->num_upload_bytes / 1024);

  ImGui::Checkbox("Debug", &stats->collect_debug_model_list);

  ImGui::SliderFloat("blerc-nightmare", &blerc_multiplier, -3, 3);

  if (stats->collect_debug_model_list) {
    for (int i = 0; i < kMaxEffect; i++) {
      ImGui::Checkbox(fmt::format("e{:02d}", i).c_str(), &m_effect_debug_mask[i]);
    }

    for (const auto& model : stats->model_list) {
      if (ImGui::TreeNode(model.name.c_str())) {
        ImGui::Text("Level: %s\n", model.level.c_str());
        for (const auto& e : model.effects) {
          for (const auto& d : e.draws) {
            ImGui::Text("%s", d.mode.to_string().c_str());
          }
          ImGui::Separator();
        }
        ImGui::TreePop();
      }
    }
  }
}

void Merc2::init_shader_common(Shader& shader, Uniforms* uniforms, bool include_lights) {
  auto id = shader.id();
  shader.activate();
  if (include_lights) {
    uniforms->light_direction[0] = glGetUniformLocation(id, "light_dir0_fade");
    uniforms->light_direction[1] = glGetUniformLocation(id, "light_dir1_fade_en");
    uniforms->light_direction[2] = glGetUniformLocation(id, "light_dir2");
    uniforms->light_color[0] = glGetUniformLocation(id, "light_col0");
    uniforms->light_color[1] = glGetUniformLocation(id, "light_col1");
    uniforms->light_color[2] = glGetUniformLocation(id, "light_col2");
    uniforms->light_ambient = glGetUniformLocation(id, "light_ambient");
  }

  uniforms->hvdf_offset = glGetUniformLocation(id, "hvdf_offset");

  uniforms->fog = glGetUniformLocation(id, "fog_constants");
  uniforms->decal = glGetUniformLocation(id, "decal_enable");

  uniforms->fog_color = glGetUniformLocation(id, "fog_color");
  uniforms->perspective_matrix = glGetUniformLocation(id, "perspective_matrix");
  uniforms->ignore_alpha = glGetUniformLocation(id, "ignore_alpha");

  uniforms->gfx_hack_no_tex = glGetUniformLocation(id, "gfx_hack_no_tex");
}

void Merc2::switch_to_merc2(SharedRenderState* render_state) {
  render_state->shaders[ShaderId::MERC2].activate();

  // set uniforms that we know from render_state
  glUniform4f(m_merc_uniforms.fog_color, render_state->fog_color[0] / 255.f,
              render_state->fog_color[1] / 255.f, render_state->fog_color[2] / 255.f,
              render_state->fog_intensity / 255);
  glUniform1i(m_merc_uniforms.gfx_hack_no_tex, Gfx::g_global_settings.hack_no_tex);
#ifdef OG_FEAT_PBR
  // ROUND 22 PER-PIXEL SCREEN-COVERAGE INSTRUMENTATION (owner defect A step 1): merc2 draws are
  // tagged magenta in debug mode 30 so the coverage census can attribute every screen pixel to the
  // program that drew it. No-op at mode 0 (the shader only reads it in the two debug branches).
  pbr_push_debug_tag(render_state->shaders[ShaderId::MERC2].id());
#endif
}

void Merc2::switch_to_emerc(SharedRenderState* render_state) {
  render_state->shaders[ShaderId::EMERC].activate();
  // set uniforms that we know from render_state
  glUniform4f(m_emerc_uniforms.fog_color, render_state->fog_color[0] / 255.f,
              render_state->fog_color[1] / 255.f, render_state->fog_color[2] / 255.f,
              render_state->fog_intensity / 255);
  glUniform1i(m_emerc_uniforms.gfx_hack_no_tex, Gfx::g_global_settings.hack_no_tex);
#ifdef OG_FEAT_PBR
  // ROUND 22 coverage instrumentation: emerc draws are tagged lime in debug mode 30.
  pbr_push_debug_tag(render_state->shaders[ShaderId::EMERC].id());
#endif
}

/*!
 * Main merc2 rendering.
 */
void Merc2::render(DmaFollower& dma,
                   SharedRenderState* render_state,
                   ScopedProfilerNode& prof,
                   MercDebugStats* stats) {
  // Gcutscene-npc-flicker : une image RENDUE de plus. Merc2::render est appele 16 fois par image
  // (16 Merc2BucketRenderers partagent cette instance) — le module deduplique sur frame_idx.
  npc_flicker::end_render_frame(render_state->frame_idx);
#ifdef OG_FEAT_HD_MODELS
  s_hd_render_call_idx++;
  // CYCLE-3 FLICKER FIX: erase TTLs of freshly-uncovered drivers NOW (queued EE-side) so the
  // stock draw returns the same frame the companion despawns, not two frames later.
  {
    std::lock_guard<std::mutex> lock(s_hd_cover_mutex);
    for (u32 pid : s_hd_uncover_pending) {
      s_hd_driver_ttl.erase(pid);
      s_hd_last_arm_call.erase(pid);
    }
    s_hd_uncover_pending.clear();
  }
  // drain the eye-slot coverage TTLs (armed with the pid TTLs, read by EyeRenderer); the donor
  // lid record falls with the TTL (an uncovered slot must revert to the stock lid path).
  for (int i = 0; i < 256; i++) {
    if (s_hd_eye_slot_ttl[i] > 0 && --s_hd_eye_slot_ttl[i] == 0) {
      s_hd_eye_slot_lid_gl[i] = 0;
    }
  }
  // drain the per-driver coverage TTLs (armed in handle_pc_model on companion submits).
  for (auto it = s_hd_driver_ttl.begin(); it != s_hd_driver_ttl.end();) {
    if (--(it->second) <= 0) {
      // flicker detector: a natural expiry means a still-covered driver went >2 frames without
      // its companion submitting — every one of these is a potential visible pop to stock.
      s_hd_ttl_expiries++;
      s_hd_last_arm_call.erase(it->first);
      it = s_hd_driver_ttl.erase(it);
    } else {
      ++it;
    }
  }
  // detector heartbeat every 3600 render calls (~225 frames): the cutscene proof leg greps
  // these lines and requires blackouts=0 gaps=0 across the scene. Silent until the first
  // companion ever arms (HD off / stock build => zero log traffic).
  if (s_hd_render_call_idx % 3600 == 0 && s_hd_ever_armed) {
    // Gcutscene-npc-flicker : `blackouts=` A ETE RETIRE DE CETTE LIGNE. Son compteur etait
    // declare, imprime, et jamais incremente depuis 45b7140ca7 (le correctif fail-open avait
    // supprime son unique site). Trois jambes de preuve exigeaient `blackouts=0` : une clause
    // qu'aucun chemin de code ne pouvait violer. Publier un zero qui ne peut pas etre autre
    // chose n'est pas une mesure. Le recensement honnete vit desormais dans
    // game/system/npc_flicker.cpp, et .autoport/npc_flicker_selftest.sh echoue si un compteur
    // publie redevient muet.
    lg::warn("[hd-flicker] calls={} gaps={} expiries={} failopens={}", s_hd_render_call_idx,
             s_hd_submit_gap_events, s_hd_ttl_expiries, s_hd_failopen_events);
  }
#endif
  bool hack = stats->collect_debug_model_list;
  *stats = {};
  stats->collect_debug_model_list = hack;
  if (stats->collect_debug_model_list) {
    stats->model_list.clear();
  }

  switch_to_merc2(render_state);

  {
    auto pp = scoped_prof("handle-all-dma");
    // iterate through the dma chain, filling buckets
    handle_all_dma(dma, render_state, prof, stats);
  }

  {
    auto pp = scoped_prof("flush-buckets");
    // flush buckets to draws
    flush_draw_buckets(render_state, prof, stats);
  }
}

u32 Merc2::alloc_lights(const VuLights& lights) {
  ASSERT(m_next_free_light < MAX_LIGHTS);
  u32 light_idx = m_next_free_light;
  m_lights_buffer[m_next_free_light++] = lights;
  static_assert(sizeof(VuLights) == 7 * 16);
  return light_idx;
}

std::string Merc2::ShaderMercMat::to_string() const {
  return fmt::format("tmat:\n{}\n{}\n{}\n{}\n", tmat[0].to_string_aligned(),
                     tmat[1].to_string_aligned(), tmat[2].to_string_aligned(),
                     tmat[3].to_string_aligned());
}

/*!
 * Main MERC2 function to handle DMA
 */
void Merc2::handle_all_dma(DmaFollower& dma,
                           SharedRenderState* render_state,
                           ScopedProfilerNode& prof,
                           MercDebugStats* stats) {
  // process the first tag. this is just jumping to the merc-specific dma.
  auto data0 = dma.read_and_advance();
  ASSERT(data0.vif1() == 0 || data0.vifcode1().kind == VifCode::Kind::NOP);
  ASSERT(data0.vif0() == 0 || data0.vifcode0().kind == VifCode::Kind::NOP ||
         data0.vifcode0().kind == VifCode::Kind::MARK);
  ASSERT(data0.size_bytes == 0);
  if (dma.current_tag().kind == DmaTag::Kind::CALL) {
    // renderer didn't run, let's just get out of here.
    for (int i = 0; i < 4; i++) {
      dma.read_and_advance();
    }
    ASSERT(dma.current_tag_offset() == render_state->next_bucket);
    return;
  }

  if (dma.current_tag_offset() == render_state->next_bucket) {
    return;
  }
  // if we reach here, there's stuff to draw
  // this handles merc-specific setup DMA
  handle_setup_dma(dma, render_state);

  // handle each merc transfer
  while (dma.current_tag_offset() != render_state->next_bucket) {
    handle_merc_chain(dma, render_state, prof, stats);
  }
  ASSERT(dma.current_tag_offset() == render_state->next_bucket);
}

namespace {
void set_uniform(GLuint uniform, const math::Vector3f& val) {
  glUniform3f(uniform, val.x(), val.y(), val.z());
}
void set_uniform(GLuint uniform, const math::Vector4f& val) {
  glUniform4f(uniform, val.x(), val.y(), val.z(), val.w());
}
}  // namespace

void Merc2::handle_setup_dma(DmaFollower& dma, SharedRenderState* render_state) {
  auto first = dma.read_and_advance();

  // 10 quadword setup packet
  ASSERT(first.size_bytes == 10 * 16);

  // transferred vifcodes
  {
    auto vif0 = first.vifcode0();
    auto vif1 = first.vifcode1();
    // STCYCL 4, 4
    ASSERT(vif0.kind == VifCode::Kind::STCYCL);
    auto vif0_st = VifCodeStcycl(vif0);
    ASSERT(vif0_st.cl == 4 && vif0_st.wl == 4);
    // STMOD
    ASSERT(vif1.kind == VifCode::Kind::STMOD);
    ASSERT(vif1.immediate == 0);
  }

  // 1 qw with 4 vifcodes.
  u32 vifcode_data[4];
  memcpy(vifcode_data, first.data, 16);
  {
    auto vif0 = VifCode(vifcode_data[0]);
    ASSERT(vif0.kind == VifCode::Kind::BASE);
    ASSERT(vif0.immediate == MercDataMemory::BUFFER_BASE);
    auto vif1 = VifCode(vifcode_data[1]);
    ASSERT(vif1.kind == VifCode::Kind::OFFSET);
    ASSERT((s16)vif1.immediate == MercDataMemory::BUFFER_OFFSET);
    auto vif2 = VifCode(vifcode_data[2]);
    ASSERT(vif2.kind == VifCode::Kind::NOP);
    auto vif3 = VifCode(vifcode_data[3]);
    ASSERT(vif3.kind == VifCode::Kind::UNPACK_V4_32);
    VifCodeUnpack up(vif3);
    ASSERT(up.addr_qw == MercDataMemory::LOW_MEMORY);
    ASSERT(!up.use_tops_flag);
    ASSERT(vif3.num == 8);
  }

  // 8 qw's of low memory data
  memcpy(&m_low_memory, first.data + 16, sizeof(LowMemory));

  switch_to_merc2(render_state);
  set_uniform(m_merc_uniforms.hvdf_offset, m_low_memory.hvdf_offset);
  set_uniform(m_merc_uniforms.fog, m_low_memory.fog);
  glUniformMatrix4fv(m_merc_uniforms.perspective_matrix, 1, GL_FALSE,
                     &m_low_memory.perspective[0].x());
  switch_to_emerc(render_state);
  set_uniform(m_emerc_uniforms.hvdf_offset, m_low_memory.hvdf_offset);
  set_uniform(m_emerc_uniforms.fog, m_low_memory.fog);
  glUniformMatrix4fv(m_emerc_uniforms.perspective_matrix, 1, GL_FALSE,
                     &m_low_memory.perspective[0].x());

  // 1 qw with another 4 vifcodes.
  u32 vifcode_final_data[4];
  memcpy(vifcode_final_data, first.data + 16 + sizeof(LowMemory), 16);
  {
    ASSERT(VifCode(vifcode_final_data[0]).kind == VifCode::Kind::FLUSHE);
    ASSERT(vifcode_final_data[1] == 0);
    ASSERT(vifcode_final_data[2] == 0);
    VifCode mscal(vifcode_final_data[3]);
    ASSERT(mscal.kind == VifCode::Kind::MSCAL);
    ASSERT(mscal.immediate == 0);
  }

  // TODO: process low memory initialization

  if (render_state->version == GameVersion::Jak1) {
    auto second = dma.read_and_advance();
    ASSERT(second.size_bytes == 32);  // setting up test register.
    auto nothing = dma.read_and_advance();
    ASSERT(nothing.size_bytes == 0);
    ASSERT(nothing.vif0() == 0);
    ASSERT(nothing.vif1() == 0);
  } else {
    auto second = dma.read_and_advance();
    ASSERT(second.size_bytes == 48);  // setting up test/zbuf register.
    // todo z write mask stuff.
    auto nothing = dma.read_and_advance();
    ASSERT(nothing.size_bytes == 0);
    ASSERT(nothing.vif0() == 0);
    ASSERT(nothing.vif1() == 0);
  }
}

namespace {
bool tag_is_nothing_next(const DmaFollower& dma) {
  return dma.current_tag().kind == DmaTag::Kind::NEXT && dma.current_tag().qwc == 0 &&
         dma.current_tag_vif0() == 0 && dma.current_tag_vif1() == 0;
}
}  // namespace

void Merc2::handle_merc_chain(DmaFollower& dma,
                              SharedRenderState* render_state,
                              ScopedProfilerNode& prof,
                              MercDebugStats* stats) {
  while (tag_is_nothing_next(dma)) {
    auto nothing = dma.read_and_advance();
    ASSERT(nothing.size_bytes == 0);
  }
  if (dma.current_tag().kind == DmaTag::Kind::CALL) {
    for (int i = 0; i < 4; i++) {
      dma.read_and_advance();
    }
    return;
  }

  auto init = dma.read_and_advance();
  int skip_count = 2;
  if (render_state->version >= GameVersion::Jak2) {
    skip_count = 1;
  }

  while (init.vifcode1().kind == VifCode::Kind::PC_PORT) {
    // flush_pending_model(render_state, prof);
    handle_pc_model(init, render_state, prof, stats);
    for (int i = 0; i < skip_count; i++) {
      auto link = dma.read_and_advance();
      ASSERT(link.vifcode0().kind == VifCode::Kind::NOP);
      ASSERT(link.vifcode1().kind == VifCode::Kind::NOP);
      ASSERT(link.size_bytes == 0);
    }
    init = dma.read_and_advance();
  }

  if (init.vifcode0().kind == VifCode::Kind::FLUSHA) {
    int num_skipped = 0;
    while (dma.current_tag_offset() != render_state->next_bucket) {
      dma.read_and_advance();
      num_skipped++;
    }
    ASSERT(num_skipped < 4);
    return;
  }
}

/*!
 * Queue up some bones to be included in the bone buffer.
 * Returns the index of the first bone vector.
 */
u32 Merc2::alloc_bones(int count, ShaderMercMat* data) {
  u32 first_bone_vector = m_next_free_bone_vector;
  ASSERT(count * 8 + first_bone_vector <= MAX_SHADER_BONE_VECTORS);

  // model should have under 128 bones.
  ASSERT(count <= MAX_SKEL_BONES);

  // iterate over each bone we need
  for (int i = 0; i < count; i++) {
    auto& skel_mat = data[i];
    auto* shader_mat = &m_shader_bone_vector_buffer[m_next_free_bone_vector];
    int bv = 0;

    // and copy to the large bone buffer.
    for (int j = 0; j < 4; j++) {
      shader_mat[bv++] = skel_mat.tmat[j];
    }

    for (int j = 0; j < 3; j++) {
      shader_mat[bv++] = skel_mat.nmat[j];
    }

    m_next_free_bone_vector += 8;
  }

  auto b0 = m_next_free_bone_vector;
  m_next_free_bone_vector += m_opengl_buffer_alignment - 1;
  m_next_free_bone_vector /= m_opengl_buffer_alignment;
  m_next_free_bone_vector *= m_opengl_buffer_alignment;
  ASSERT(b0 <= m_next_free_bone_vector);
  ASSERT(first_bone_vector + count * 8 <= m_next_free_bone_vector);
  return first_bone_vector;
}

Merc2::ModBuffers Merc2::alloc_mod_vtx_buffer(const LevelData* lev) {
  if (m_next_mod_vtx_buffer >= m_mod_vtx_buffers.size()) {
    GLuint b;
    glGenBuffers(1, &b);
    GLuint vao;
    glGenVertexArrays(1, &vao);
    glBindVertexArray(vao);
    glBindBuffer(GL_ARRAY_BUFFER, b);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, lev->merc_indices);
    setup_merc_vao();
    m_mod_vtx_buffers.push_back({vao, b});
  }
  return m_mod_vtx_buffers[m_next_mod_vtx_buffer++];
}

Merc2::Draw* Merc2::try_alloc_envmap_draw(const tfrag3::MercDraw& mdraw,
                                          const DrawMode& envmap_mode,
                                          u32 envmap_texture,
                                          const DrawArgs& args) {
  bool nonzero_fade = false;
  for (int i = 0; i < 4; i++) {
    if (args.fade[i]) {
      nonzero_fade = true;
      break;
    }
  }
  if (!nonzero_fade) {
    return nullptr;
  }

  // Grecharged-title-logo-fullres: native-overlay models go to their own pool (replayed at native
  // res after the UI composite); everything else takes the stock pool, unchanged.
  Draw* draw;
  if (args.defer_native &&
      args.lev_bucket->next_free_native_envmap_draw < (u32)MAX_NATIVE_DRAWS_PER_LEVEL) {
    draw = &args.lev_bucket->native_envmap_draws[args.lev_bucket->next_free_native_envmap_draw++];
  } else {
    draw = &args.lev_bucket->envmap_draws[args.lev_bucket->next_free_envmap_draw++];
  }
  draw->flags = 0;
  draw->first_index = mdraw.first_index;
  draw->index_count = mdraw.index_count;
  draw->mode = envmap_mode;
  draw->hash = 0;
  if (args.jak1_water_mode) {
    draw->mode.enable_ab();
    draw->mode.disable_depth_write();
  }
  draw->texture = envmap_texture;
  draw->first_bone = args.first_bone;
  draw->light_idx = args.lights;
  draw->num_triangles = mdraw.num_triangles;
  draw->no_strip = mdraw.no_strip;
  for (int i = 0; i < 4; i++) {
    draw->fade[i] = args.fade[i];
  }
  return draw;
}

Merc2::Draw* Merc2::alloc_normal_draw(const tfrag3::MercDraw& mdraw, const DrawArgs& args) {
  // Grecharged-title-logo-fullres: see try_alloc_envmap_draw. Callers dereference the result
  // unconditionally, so a full native pool falls back to the stock pool (draw stays in the scaled
  // pass — merely not crisp) instead of returning null.
  Draw* draw;
  if (args.defer_native &&
      args.lev_bucket->next_free_native_draw < (u32)MAX_NATIVE_DRAWS_PER_LEVEL) {
    draw = &args.lev_bucket->native_draws[args.lev_bucket->next_free_native_draw++];
  } else {
    draw = &args.lev_bucket->draws[args.lev_bucket->next_free_draw++];
  }
  draw->flags = 0;
  draw->first_index = mdraw.first_index;
  draw->index_count = mdraw.index_count;
  draw->mode = mdraw.mode;
  draw->hash = args.hash;
  if (args.jak1_water_mode) {
    draw->mode.set_ab(true);
    draw->mode.disable_depth_write();
  }

  if (args.disable_fog) {
    draw->mode.set_fog(false);
    // but don't toggle it the other way?
  }

  draw->texture = mdraw.eye_id == 0xff ? mdraw.tree_tex_id : (0xefffff00 | mdraw.eye_id);
  draw->first_bone = args.first_bone;
  draw->light_idx = args.lights;
  draw->num_triangles = mdraw.num_triangles;
  draw->no_strip = mdraw.no_strip;
  if (args.ignore_alpha) {
    draw->flags |= IGNORE_ALPHA;
  }
  if (args.no_texture) {
    draw->flags |= NO_TEXTURE;
  }
  for (int i = 0; i < 4; i++) {
    draw->fade[i] = 0;
  }
  return draw;
}

void Merc2::setup_merc_vao() {
#ifdef __ANDROID__
  // GLES has no settable restart index (glPrimitiveRestartIndex is NULL in
  // the loader). Fixed-index mode restarts on all-1s == UINT32_MAX for our
  // u32 index buffers — identical semantics (same gate as TFragment).
  glEnable(GL_PRIMITIVE_RESTART_FIXED_INDEX);
#else
  glEnable(GL_PRIMITIVE_RESTART);
  glPrimitiveRestartIndex(UINT32_MAX);
#endif
  glEnableVertexAttribArray(0);
  glEnableVertexAttribArray(1);
  glEnableVertexAttribArray(2);
  glEnableVertexAttribArray(3);
  glEnableVertexAttribArray(4);
  glEnableVertexAttribArray(5);
  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_GEQUAL);

  glVertexAttribPointer(0,                                        // location 0 in the shader
                        3,                                        // 3 values per vert
                        GL_FLOAT,                                 // floats
                        GL_FALSE,                                 // normalized
                        sizeof(tfrag3::MercVertex),               // stride
                        (void*)offsetof(tfrag3::MercVertex, pos)  // offset (0)
  );

  glVertexAttribPointer(1,                                              // location 1 in the
                        3,                                              // 3 values per vert
                        GL_FLOAT,                                       // floats
                        GL_FALSE,                                       // normalized
                        sizeof(tfrag3::MercVertex),                     // stride
                        (void*)offsetof(tfrag3::MercVertex, normal[0])  // offset (0)
  );

  glVertexAttribPointer(2,                                               // location 1 in the
                        3,                                               // 3 values per vert
                        GL_FLOAT,                                        // floats
                        GL_FALSE,                                        // normalized
                        sizeof(tfrag3::MercVertex),                      // stride
                        (void*)offsetof(tfrag3::MercVertex, weights[0])  // offset (0)
  );

  glVertexAttribPointer(3,                                          // location 1 in the shader
                        2,                                          // 3 values per vert
                        GL_FLOAT,                                   // floats
                        GL_FALSE,                                   // normalized
                        sizeof(tfrag3::MercVertex),                 // stride
                        (void*)offsetof(tfrag3::MercVertex, st[0])  // offset (0)
  );

  glVertexAttribPointer(4,                                            // location 1 in the shader
                        4,                                            // 3 values per vert
                        GL_UNSIGNED_BYTE,                             // floats
                        GL_TRUE,                                      // normalized
                        sizeof(tfrag3::MercVertex),                   // stride
                        (void*)offsetof(tfrag3::MercVertex, rgba[0])  // offset (0)
  );

  glVertexAttribIPointer(5,                                            // location 0 in the
                         4,                                            // 3 floats per vert
                         GL_UNSIGNED_BYTE,                             // u8's
                         sizeof(tfrag3::MercVertex),                   //
                         (void*)offsetof(tfrag3::MercVertex, mats[0])  // offset in array
  );
}

void Merc2::flush_draw_buckets(SharedRenderState* render_state,
                               ScopedProfilerNode& prof,
                               MercDebugStats* stats) {
  stats->num_draw_flush++;

  // Gperf-batching: upload this flush's bone window ONCE (it is identical for
  // every level bucket — the old per-bucket re-upload was redundant), and at a
  // RING cursor instead of offset 0. Writing offset 0 every flush hits a UBO
  // still being read by in-flight draws => implicit driver sync per flush
  // (~0.6-1.0ms each, the bones-ub cost in the round-3 breakdown). The ring
  // advances by aligned windows and orphans the storage on wrap, so no upload
  // ever overlaps a live read. first_bone offsets stay window-relative; draws
  // bind at (bones_base + first_bone).
  u32 bones_base = 0;
  {
    auto bones_prof = prof.make_scoped_child("bones-ub");
    glBindBuffer(GL_UNIFORM_BUFFER, m_bones_buffer);
    if (render_state->batch_singledraw) {
      u32 base = m_bones_ring_base;  // aligned: advanced by aligned amounts only
      if (base + m_next_free_bone_vector > MAX_SHADER_BONE_VECTORS) {
        // wrap: orphan so draws still reading the old storage keep it alive
        glBufferData(GL_UNIFORM_BUFFER, MAX_SHADER_BONE_VECTORS * sizeof(math::Vector4f), nullptr,
                     GL_DYNAMIC_DRAW);
        base = 0;
      }
      glBufferSubData(GL_UNIFORM_BUFFER, base * sizeof(math::Vector4f),
                      m_next_free_bone_vector * sizeof(math::Vector4f),
                      m_shader_bone_vector_buffer);
      bones_base = base;
      u32 next = base + m_next_free_bone_vector + m_opengl_buffer_alignment - 1;
      next = next / m_opengl_buffer_alignment * m_opengl_buffer_alignment;
      m_bones_ring_base = next;
    } else {
      glBufferSubData(GL_UNIFORM_BUFFER, 0, m_next_free_bone_vector * sizeof(math::Vector4f),
                      m_shader_bone_vector_buffer);
    }
    glBindBuffer(GL_UNIFORM_BUFFER, 0);
  }

  for (u32 li = 0; li < m_next_free_level_bucket; li++) {
    const auto& lev_bucket = m_level_draw_buckets[li];
    const auto* lev = lev_bucket.level;
    glBindVertexArray(m_vao);
    glBindBuffer(GL_ARRAY_BUFFER, lev->merc_vertices);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, lev->merc_indices);
    // Gperf-batching: name the flush-phase costs in the A35-PERF dump —
    // the per-bucket table showed merc ms far above its draw-call count
    // (e.g. 6.4ms/64dr) and the suspects are the per-flush BO defuse maps
    // (driver syncs), the VAO respecification, and the bone UBO upload.
    // Dedupe both when batch_singledraw: the defuse contract is "this
    // level's BOs read-mapped once per FRAME before its first merc draws"
    // (F1a run-16/17: per-frame coverage is what defuses; per-flush
    // repetition within the frame is redundant sync cost), and the m_vao
    // attribs only need respecifying when the level vertex buffer changes.
    bool skip_defuse = false;
    bool skip_vao = false;
    if (render_state->batch_singledraw) {
      if (m_defuse_frame != render_state->frame_idx) {
        m_defuse_frame = render_state->frame_idx;
        m_num_defused_levs = 0;
      }
      for (int i = 0; i < m_num_defused_levs; i++) {
        if (m_defused_levs[i].first == (const void*)lev &&
            m_defused_levs[i].second == lev->load_id) {
          skip_defuse = true;
          break;
        }
      }
      if (!skip_defuse && m_num_defused_levs < (int)m_defused_levs.size()) {
        m_defused_levs[m_num_defused_levs++] = {(const void*)lev, lev->load_id};
      }
      skip_vao = m_vao_vertex_buffer == lev->merc_vertices && m_vao_load_id == lev->load_id;
    } else {
      // kill switch active: unconditional setups leave the VAO in arbitrary
      // per-flush state — invalidate so re-enabling starts fresh
      m_vao_vertex_buffer = 0;
      m_vao_load_id = UINT64_MAX;
    }
    if (!skip_defuse) {
      auto defuse_prof = prof.make_scoped_child("defuse");
#ifdef __ANDROID__
    // F1a Adreno workaround: specific merc glDrawElements SIGSEGV inside
    // the driver (null+0x28) with state-legal, GPU==CPU-verified data.
    // A read-only map+unmap of the index BO immediately before the draws
    // defuses it deterministically (run-16: the killer draw executed on
    // exactly the frames a per-draw map probe covered and faulted on the
    // first frame past its cap; a load-time-only sync decayed by draw
    // time, run-17). Tiny mapped range, read-only — forces the driver to
    // finalize the BO for this frame's draws. Cost: one map/unmap per
    // level bucket per frame.
    {
      void* p = glMapBufferRange(GL_ELEMENT_ARRAY_BUFFER, 0, 16, GL_MAP_READ_BIT);
      if (p) {
        glUnmapBuffer(GL_ELEMENT_ARRAY_BUFFER);
      }
    }
    // F1d: same defuse for the VERTEX buffer — the one draw-state object no
    // prior touch covered. The first merc draw consuming a freshly-loaded
    // level's vertex BO faults in the driver's draw-state walk (run5/run7:
    // misty 2/2, identical fault 8 ms AFTER a load-completion glFinish, with
    // the index BO mapped+memcmp'd and the texture/FBO verified at the same
    // draw). A read-only map forces the driver to materialize the BO's
    // internal storage object, which command-drain (glFinish) does not.
    {
      void* p = glMapBufferRange(GL_ARRAY_BUFFER, 0, 16, GL_MAP_READ_BIT);
      if (p) {
        glUnmapBuffer(GL_ARRAY_BUFFER);
      }
    }
#endif
    }
    if (!skip_vao) {
      auto vao_prof = prof.make_scoped_child("vao");
      setup_merc_vao();
      m_vao_vertex_buffer = lev->merc_vertices;
      m_vao_load_id = lev->load_id;
    }
    stats->num_bones_uploaded += m_next_free_bone_vector;

    switch_to_merc2(render_state);
    {
      auto draws_prof = prof.make_scoped_child("draws");
      do_draws(lev_bucket.draws.data(), lev, lev_bucket.next_free_draw, m_merc_uniforms,
               draws_prof, false, render_state, bones_base);
    }
    if (lev_bucket.next_free_envmap_draw) {
      switch_to_emerc(render_state);
      auto edraws_prof = prof.make_scoped_child("env-draws");
      do_draws(lev_bucket.envmap_draws.data(), lev, lev_bucket.next_free_envmap_draw,
               m_emerc_uniforms, edraws_prof, true, render_state, bones_base);
    }

    // Grecharged-title-logo-fullres: this bucket's native-overlay draws are deliberately NOT
    // drawn here — keeping them out of the render-scaled scene FBO is the whole point. Snapshot
    // everything the replay needs that this flush is about to recycle (the bone window is
    // re-filled from 0 by the next flush, m_lights_buffer likewise, and m_low_memory is rewritten
    // by the next bucket's setup DMA); the geometry itself stays put in the LEVEL's persistent GL
    // buffers, so it needs no copy.
    if (lev_bucket.next_free_native_draw || lev_bucket.next_free_native_envmap_draw) {
      auto& batch = m_deferred_native.emplace_back();
      batch.lev = lev;
      batch.low_memory = m_low_memory;
      batch.bones.assign(m_shader_bone_vector_buffer,
                         m_shader_bone_vector_buffer + m_next_free_bone_vector);
      std::vector<std::pair<u32, u32>> light_map;  // original light_idx -> index in batch.lights
      auto take = [&](Draw d) {
        u32 idx = UINT32_MAX;
        for (const auto& p : light_map) {
          if (p.first == d.light_idx) {
            idx = p.second;
            break;
          }
        }
        if (idx == UINT32_MAX) {
          idx = (u32)batch.lights.size();
          batch.lights.push_back(m_lights_buffer[d.light_idx]);
          light_map.emplace_back(d.light_idx, idx);
        }
        d.light_idx = (u16)idx;
        return d;
      };
      for (u32 i = 0; i < lev_bucket.next_free_native_draw; i++) {
        batch.draws.push_back(take(lev_bucket.native_draws[i]));
      }
      for (u32 i = 0; i < lev_bucket.next_free_native_envmap_draw; i++) {
        batch.envmap_draws.push_back(take(lev_bucket.native_envmap_draws[i]));
      }
    }
  }

  m_next_free_light = 0;
  m_next_free_bone_vector = 0;
  m_next_free_level_bucket = 0;
  m_next_mod_vtx_buffer = 0;
}

/*!
 * Grecharged-title-logo-fullres: replay the stashed title/ND-logo draws at NATIVE resolution.
 * Called by the frame orchestrator from inside begin_ui_pass(), AFTER the scaled scene has been
 * upscale-blitted into the native UI FBO and its depth cleared, and BEFORE the 2D HUD/sprite
 * pass — so the logo lands on top of the (upscaled) flythrough, blends against the real
 * background, keeps its own self-occlusion via the UI FBO's depth buffer, and is itself overdrawn
 * by the menu/PRESS START text exactly as in the single-FBO pipeline.
 *
 * Nothing here reaches the GPU unless models were stashed, which requires the toggle ON, the
 * Recharged master ON, jak1, and an active render-scale split.
 */
void Merc2::draw_deferred_native_draws(SharedRenderState* render_state) {
  if (m_deferred_native.empty()) {
    return;
  }
  // begin_ui_pass() is reached from inside Sprite3::render, which keeps issuing location-based
  // glUniform calls for ITS program after we return: save/restore the caller's program and VAO or
  // those calls hit the merc program (GL_INVALID_OPERATION flood + corrupted HUD sprites). Same
  // hazard, same fix as Generic2::draw_deferred_hud_draws.
  GLint prev_program = 0;
  GLint prev_vao = 0;
  glGetIntegerv(GL_CURRENT_PROGRAM, &prev_program);
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prev_vao);

  // do_draws wants a profiler node and this pass sits outside the bucket tree; a local root keeps
  // its draw-call/tri counters out of the per-bucket breakdown instead of misattributing them.
  ProfilerNode prof_node("crisp-title-logo");
  ScopedProfilerNode prof(&prof_node);

  // PERMANENT activity counter, not a capture: the presence of this line IS the proof that the
  // native replay ran on device, and its absence is the proof that OFF takes the stock path.
  // Throttled to one line per 300 replayed frames (~10 s at 30 fps), first frame always logged.
  {
    static u64 s_replay_frames = 0;
    if ((s_replay_frames++ % 300) == 0) {
      size_t nd = 0, ne = 0;
      for (const auto& b : m_deferred_native) {
        nd += b.draws.size();
        ne += b.envmap_draws.size();
      }
      lg::info("[crisp-logo] native replay: batches={} draws={} envmap={} fb={}x{} frame={}",
               m_deferred_native.size(), nd, ne, render_state->render_fb_w,
               render_state->render_fb_h, s_replay_frames - 1);
    }
  }

  const u32 saved_free_light = m_next_free_light;

  for (auto& batch : m_deferred_native) {
    if (!batch.lev || batch.draws.empty()) {
      continue;
    }
    // Lights: do_draws reads m_lights_buffer[draw.light_idx]. The flush already reset the light
    // allocator, so write the snapshot back at 0..n — the stashed draws were re-indexed to match.
    const size_t num_lights = std::min(batch.lights.size(), (size_t)MAX_LIGHTS);
    for (size_t i = 0; i < num_lights; i++) {
      m_lights_buffer[i] = batch.lights[i];
    }

    // Bones: re-upload this batch's window. Use the same ring cursor as flush_draw_buckets when
    // batching is on, so this upload never lands on a window in-flight draws are still reading.
    u32 bones_base = 0;
    if (!batch.bones.empty()) {
      const u32 n_bone_vec = (u32)batch.bones.size();
      glBindBuffer(GL_UNIFORM_BUFFER, m_bones_buffer);
      if (render_state->batch_singledraw) {
        u32 base = m_bones_ring_base;
        if (base + n_bone_vec > MAX_SHADER_BONE_VECTORS) {
          glBufferData(GL_UNIFORM_BUFFER, MAX_SHADER_BONE_VECTORS * sizeof(math::Vector4f), nullptr,
                       GL_DYNAMIC_DRAW);
          base = 0;
        }
        glBufferSubData(GL_UNIFORM_BUFFER, base * sizeof(math::Vector4f),
                        n_bone_vec * sizeof(math::Vector4f), batch.bones.data());
        bones_base = base;
        u32 next = base + n_bone_vec + m_opengl_buffer_alignment - 1;
        next = next / m_opengl_buffer_alignment * m_opengl_buffer_alignment;
        m_bones_ring_base = next;
      } else {
        glBufferSubData(GL_UNIFORM_BUFFER, 0, n_bone_vec * sizeof(math::Vector4f),
                        batch.bones.data());
      }
      glBindBuffer(GL_UNIFORM_BUFFER, 0);
    }

    glBindVertexArray(m_vao);
    glBindBuffer(GL_ARRAY_BUFFER, batch.lev->merc_vertices);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, batch.lev->merc_indices);
    setup_merc_vao();
    // the shared VAO now points at this level's buffers outside the flush loop's bookkeeping —
    // invalidate its cache so the next frame's first flush respecifies the attribs.
    m_vao_vertex_buffer = 0;
    m_vao_load_id = UINT64_MAX;

    // handle_setup_dma pushes these once per merc bucket; we are outside every bucket now, so
    // restore the snapshot taken when this batch was stashed.
    m_low_memory = batch.low_memory;
    switch_to_merc2(render_state);
    set_uniform(m_merc_uniforms.hvdf_offset, m_low_memory.hvdf_offset);
    set_uniform(m_merc_uniforms.fog, m_low_memory.fog);
    glUniformMatrix4fv(m_merc_uniforms.perspective_matrix, 1, GL_FALSE,
                       &m_low_memory.perspective[0].x());
    do_draws(batch.draws.data(), batch.lev, (u32)batch.draws.size(), m_merc_uniforms, prof, false,
             render_state, bones_base);

    if (!batch.envmap_draws.empty()) {
      switch_to_emerc(render_state);
      set_uniform(m_emerc_uniforms.hvdf_offset, m_low_memory.hvdf_offset);
      set_uniform(m_emerc_uniforms.fog, m_low_memory.fog);
      glUniformMatrix4fv(m_emerc_uniforms.perspective_matrix, 1, GL_FALSE,
                         &m_low_memory.perspective[0].x());
      do_draws(batch.envmap_draws.data(), batch.lev, (u32)batch.envmap_draws.size(),
               m_emerc_uniforms, prof, true, render_state, bones_base);
    }
  }

  m_next_free_light = saved_free_light;
  m_deferred_native.clear();
  glBindVertexArray(prev_vao);
  glUseProgram(prev_program);
}

#ifdef __ANDROID__
// F1a crash forensics: raw stores per draw, formatted only by the SIGSEGV
// dump (runs 4/5 fault inside libGLESv2_adreno with no walkable caller).
struct F1aMercDrawInfo {
  u32 di, num_draws, tex, first_bone, index_count, first_index;
  u32 vao, vtx_buf, idx_buf;
  int envmap, mod_vtx, no_strip;
  // F1e: texture-bind + framebuffer state at the draw (branch: 0=cached
  // 1=level 2=eye 3=anim 4=invalid; tex_is: 0=dead-name 1=alive 2=unknown).
  u32 tex_branch, tex_name, tex_is, tex_size, tex_binding;
  u32 fbo_binding, fbo_status, gl_err;
  u32 load_id, fsl;
};
volatile F1aMercDrawInfo gk_f1a_last_merc_draw = {};
#endif

void Merc2::do_draws(const Draw* draw_array,
                     const LevelData* lev,
                     u32 num_draws,
                     const Uniforms& uniforms,
                     ScopedProfilerNode& prof,
                     bool set_fade,
                     SharedRenderState* render_state,
                     u32 bones_base) {
  glBindVertexArray(m_vao);
#ifdef __ANDROID__
  // F1f — fix the Adreno first-merc-draw-after-load SIGSEGV (fault=0x28,
  // pc=libGLESv2_adreno+0x13a414) on the first textured merc draw of a freshly
  // revealed level. The driver's per-draw resource-validation walk iterates the
  // uniform-buffer binding points the merc program references and dereferences
  // each bound buffer object at +0x28. ub_bones is reassigned to UBO binding
  // point 1 (Shader.cpp glUniformBlockBinding) and its data is bound there, but
  // on this driver the validation walk still checks UBO binding point 0 (the
  // block's pre-reassignment default); that slot is NULL, and a level reveal's
  // glDeleteBuffers churn keeps it NULL, so the draw reads [NULL+0x28] and
  // crashes. (Proven by the fault register dump: x28=1 binding-points, index
  // x17=0, x10=[ctx+0*0x20+0x2900]=NULL; the 0x2900 table is GL_UNIFORM_BUFFER
  // bindings — id 7 — NOT texture units, which is why every texture-unit
  // experiment failed.) Bind a valid buffer to UBO point 0 so the walk
  // dereferences a live object. The shader still reads its bones from point 1,
  // so rendering is unchanged; point 0 is validation-only.
  glBindBufferBase(GL_UNIFORM_BUFFER, 0, m_bones_buffer);
#endif
  s32 last_tex = INT32_MIN;
  int last_light = -1;
  bool normal_vtx_buffer_bound = true;

  bool fog_on = true;

  // Gperf-batching (Android, render_state->batch_singledraw): skip redundant
  // per-draw GL state. Merc dominates the draw count (~420 of 571 draws on
  // Geyser Rock) and every draw re-issued 3 uniforms + a full
  // setup_opengl_from_draw_mode (~12 GL calls) + glBindBufferRange even when
  // nothing changed. Caches are per-do_draws-call (program switches between
  // calls). The draw-mode setup key includes the texture: setup writes
  // wrap/filter params onto the BOUND texture object, so a texture change
  // always forces a fresh setup pass.
  const bool cache_state = render_state->batch_singledraw;
  s32 last_ignore_alpha = INT32_MIN;
  s32 last_decal = -1;
  s32 last_no_tex = -1;
  s64 last_first_bone = -1;
  u32 last_setup_mode = 0;
  s32 last_setup_tex = INT32_MIN;
  bool last_setup_mips = false;
  bool have_setup = false;

  for (u32 di = 0; di < num_draws; di++) {
    auto& draw = draw_array[di];
    if (draw.flags & MOD_VTX) {
      glBindVertexArray(draw.mod_vtx_buffer.vao);
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, lev->merc_indices);
      glBindBuffer(GL_ARRAY_BUFFER, lev->merc_vertices);
      normal_vtx_buffer_bound = false;
    } else {
      if (!normal_vtx_buffer_bound) {
        glBindVertexArray(m_vao);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, lev->merc_indices);
        glBindBuffer(GL_ARRAY_BUFFER, lev->merc_vertices);
        normal_vtx_buffer_bound = true;
      }
    }
    {
      s32 ignore_alpha = draw.flags & DrawFlags::IGNORE_ALPHA;
      if (!cache_state || ignore_alpha != last_ignore_alpha) {
        glUniform1i(uniforms.ignore_alpha, ignore_alpha);
        last_ignore_alpha = ignore_alpha;
      }
    }

    if (fog_on && !draw.mode.get_fog_enable()) {
      // on -> off
      glUniform4f(uniforms.fog_color, render_state->fog_color[0] / 255.f,
                  render_state->fog_color[1] / 255.f, render_state->fog_color[2] / 255.f, 0);
      fog_on = false;
    } else if (!fog_on && draw.mode.get_fog_enable()) {
      glUniform4f(uniforms.fog_color, render_state->fog_color[0] / 255.f,
                  render_state->fog_color[1] / 255.f, render_state->fog_color[2] / 255.f,
                  render_state->fog_intensity / 255);
      fog_on = true;
    }
    bool use_mipmaps_for_filtering = true;
#ifdef __ANDROID__
    u32 f1e_branch = 0;  // cached — unit 0 keeps the previous draw's binding
#endif
    if (draw.texture != last_tex) {
      if (draw.texture < (int)lev->textures.size() && draw.texture >= 0) {
        if (!f1a_notex)
        glBindTexture(GL_TEXTURE_2D, lev->textures.at(draw.texture));
#ifdef __ANDROID__
        f1e_branch = 1;
        gk_f1a_last_merc_draw.tex_name = lev->textures.at(draw.texture);
#endif
      } else if ((draw.texture & 0xffffff00) == 0xefffff00) {
        if (render_state->version == GameVersion::Jak3 ||
            render_state->version == GameVersion::JakX) {
          auto maybe_eye =
              render_state->eye_renderer->lookup_eye_texture_hash(draw.hash, (draw.texture & 1));
          if (maybe_eye) {
            glBindTexture(GL_TEXTURE_2D, *maybe_eye);
          }
        } else {
          auto maybe_eye = render_state->eye_renderer->lookup_eye_texture(draw.texture & 0xff);
          if (maybe_eye) {
            glBindTexture(GL_TEXTURE_2D, *maybe_eye);
          }
        }

        use_mipmaps_for_filtering = false;
#ifdef __ANDROID__
        f1e_branch = 2;
#endif
      } else if (draw.texture < 0) {
        int slot = -(draw.texture + 1);
        // Gjak2-render (Android): the curated renderer has no TextureAnimator, so
        // the anim-slot array is empty; jak2 merc draws DO reference anim slots
        // (jak1's never did). Bind nothing (placeholder texture state) instead of
        // std::out_of_range-aborting. Desktop always populates the array; neutral.
        // Grecharged-hd-models5: on jak1 the POINTER itself is null (no TextureAnimator at
        // all, OpenGLRenderer.h anim_slot_array()) and the M3 bonus donors (jak2/jak3 Jak)
        // ship anim-slot draws — guard the pointer too, or jak1 SIGSEGVs on first submit.
        // The bake rebinds these draws to static textures; this is defense-in-depth.
        if (m_anim_slot_array && slot >= 0 && (size_t)slot < m_anim_slot_array->size()) {
          glBindTexture(GL_TEXTURE_2D, m_anim_slot_array->at(slot));
          // Gjak2-visuals probe: one-shot per anim slot actually bound by a
          // merc draw — diffable our-x86 (env GJ2VIS_SKY) vs device (always)
          // to see which title surfaces depend on animator output.
          {
#ifdef __ANDROID__
            static const bool s_slot_dump = true;
#else
            static const bool s_slot_dump = getenv("GJ2VIS_SKY") != nullptr;
#endif
            if (s_slot_dump) {
              static bool s_slot_seen[128] = {};
              if (slot < 128 && !s_slot_seen[slot]) {
                s_slot_seen[slot] = true;
                fprintf(stderr, "GJ2VIS-MERCSLOT slot=%d tex=%u\n", slot,
                        (unsigned)m_anim_slot_array->at(slot));
              }
            }
          }
#ifdef __ANDROID__
          f1e_branch = 3;
          gk_f1a_last_merc_draw.tex_name = m_anim_slot_array->at(slot);
#endif
        }
#ifdef __ANDROID__
        else {
          f1e_branch = 3;
        }
#endif
      } else {
        fmt::print("Invalid draw.texture is {}, would have crashed.\n", draw.texture);
#ifdef __ANDROID__
        // stdout is buffered and dies with the process — mirror to stderr.
        fprintf(stderr, "F1E-TEX-INVALID draw.texture=%d size=%zu lev=%s\n", draw.texture,
                lev->textures.size(), lev->level->level_name.c_str());
        f1e_branch = 4;
#endif
      }
      last_tex = draw.texture;
    }

    if ((int)draw.light_idx != last_light && !set_fade) {
      const auto& l0_dir = m_lights_buffer[draw.light_idx].direction0;
      const auto& l1_dir = m_lights_buffer[draw.light_idx].direction1;
      float fade = 1.f;
      float fade_enable = 0.f;
      if (m_lights_buffer[draw.light_idx].w1) {
        fade = m_lights_buffer[draw.light_idx].w2 / 128.f;
        fade_enable = 1.f;
      }
      math::Vector4f l0_dir_f(l0_dir.x(), l0_dir.y(), l0_dir.z(), fade);
      set_uniform(uniforms.light_direction[0], l0_dir_f);
      math::Vector4f l1_dir_f(l1_dir.x(), l1_dir.y(), l1_dir.z(), fade_enable);
      set_uniform(uniforms.light_direction[1], l1_dir_f);
      set_uniform(uniforms.light_direction[2], m_lights_buffer[draw.light_idx].direction2);
      set_uniform(uniforms.light_color[0], m_lights_buffer[draw.light_idx].color0);
      set_uniform(uniforms.light_color[1], m_lights_buffer[draw.light_idx].color1);
      set_uniform(uniforms.light_color[2], m_lights_buffer[draw.light_idx].color2);
      set_uniform(uniforms.light_ambient, m_lights_buffer[draw.light_idx].ambient);
      last_light = draw.light_idx;
    }

    {
      s32 decal = draw.mode.get_decal() ? 1 : 0;
      if (!cache_state || decal != last_decal) {
        glUniform1i(uniforms.decal, decal);
        last_decal = decal;
      }
      s32 no_tex = (draw.flags & NO_TEXTURE) != 0 ? 1 : 0;
      if (!cache_state || no_tex != last_no_tex) {
        glUniform1i(uniforms.gfx_hack_no_tex, no_tex);
        last_no_tex = no_tex;
      }
    }

#ifndef __ANDROID__
    // F1a oracle twin of the Android crash forensics: same fields, env-gated,
    // first draws only — diffing this against the device F1A-MERC-DRAW dump
    // separates "wrong data on Android" from "legal data, driver fault".
    {
      static const bool s_dump = getenv("F1A_MERC_DUMP") != nullptr;
      static int s_dumped = 0;
      if (s_dump && s_dumped < 40) {
        s_dumped++;
        fprintf(stderr,
                "F1A-MERC-DRAW lev=%s di=%u/%u tex=0x%x first_bone=%u idx=%u+%u envmap=%d mod=%d "
                "nostrip=%d\n",
                lev->level->level_name.c_str(), di, num_draws, (u32)draw.texture, draw.first_bone,
                draw.index_count, draw.first_index, set_fade ? 1 : 0,
                (draw.flags & MOD_VTX) ? 1 : 0, draw.no_strip ? 1 : 0);
      }
    }
#endif
#ifdef __ANDROID__
    // F1a guard: a draw whose index range exceeds the level's actual merc
    // index buffer means the model reference and the bound buffers disagree
    // (cross-level name collision / stale reference) — on Adreno that draw
    // SIGSEGVs inside the driver (runs 4-7, fault 0x28, no GL error). Name
    // it and skip instead of crashing; the log discriminates data-mismatch
    // from driver-quirk.
    if ((u64)draw.first_index + draw.index_count > lev->level->merc_data.indices.size()) {
      static int s_f1a_oob = 0;
      if (s_f1a_oob++ < 20) {
        fprintf(stderr,
                "F1A-MERC-OOB draw idx=%u+%u > level idx-buf=%zu (lev=%s tex=%d envmap=%d)\n",
                draw.first_index, draw.index_count, lev->level->merc_data.indices.size(),
                lev->level->level_name.c_str(), draw.texture, (int)set_fade);
      }
      continue;
    }
    // F1A-MERC-VERIFY (first few draws): the minimal self-test draw survives
    // on this driver, so the crash is data-dependent. Validate the draw's
    // index window on the CPU copy (min/max index vs vertex count) and
    // memcmp the live GPU index buffer (glMapBufferRange) against the fr3
    // CPU copy — separates "corrupt source data" / "sheared GL upload" /
    // "driver chokes on legal data".
    {
      // Title AND sibling village draws verified clean and executed (runs
      // 12-15). The killer is ONE stable draw: first_index=64945, count=117,
      // tex=0x225, di=0 of l1-pris's 53-draw list. Verify exactly it.
      static int s_f1a_verify = 0;
      if (s_f1a_verify < 6 && draw.first_index == 64945) {
        s_f1a_verify++;
        const auto& cpu_idx = lev->level->merc_data.indices;
        u32 mn = UINT32_MAX, mx = 0;
        u32 restarts = 0;
        for (u32 k = 0; k < draw.index_count; k++) {
          u32 v = cpu_idx[draw.first_index + k];
          if (v == UINT32_MAX) {
            restarts++;
            continue;
          }
          mn = std::min(mn, v);
          mx = std::max(mx, v);
        }
        int gpu_match = -1;
        void* mapped = glMapBufferRange(GL_ELEMENT_ARRAY_BUFFER, sizeof(u32) * draw.first_index,
                                        sizeof(u32) * draw.index_count, GL_MAP_READ_BIT);
        if (mapped) {
          gpu_match =
              memcmp(mapped, cpu_idx.data() + draw.first_index, sizeof(u32) * draw.index_count)
                  ? 0
                  : 1;
          glUnmapBuffer(GL_ELEMENT_ARRAY_BUFFER);
        }
        fprintf(stderr,
                "F1A-MERC-VERIFY lev=%s idx=%u+%u min=%u max=%u restarts=%u verts=%zu "
                "gpu-match=%d err=0x%x\n",
                lev->level->level_name.c_str(), draw.first_index, draw.index_count, mn, mx,
                restarts, lev->merc_vertex_count, gpu_match, glGetError());
      }
    }
    {
      gk_f1a_last_merc_draw.di = di;
      gk_f1a_last_merc_draw.num_draws = num_draws;
      gk_f1a_last_merc_draw.tex = (u32)draw.texture;
      gk_f1a_last_merc_draw.first_bone = draw.first_bone;
      gk_f1a_last_merc_draw.index_count = draw.index_count;
      gk_f1a_last_merc_draw.first_index = draw.first_index;
      gk_f1a_last_merc_draw.vao = (draw.flags & MOD_VTX) ? draw.mod_vtx_buffer.vao : m_vao;
      gk_f1a_last_merc_draw.vtx_buf = lev->merc_vertices;
      gk_f1a_last_merc_draw.idx_buf = lev->merc_indices;
      gk_f1a_last_merc_draw.envmap = set_fade ? 1 : 0;
      gk_f1a_last_merc_draw.mod_vtx = (draw.flags & MOD_VTX) ? 1 : 0;
      gk_f1a_last_merc_draw.no_strip = draw.no_strip ? 1 : 0;
      gk_f1a_last_merc_draw.tex_branch = f1e_branch;
      // F1e: Adreno 618 (V@0502) draw-state validation sync + probe. The
      // FIRST l1-pris-merc glDrawElements at the title-intro reveal can
      // fault inside the driver: sig=11 fault=0x28 pc=libGLESv2_adreno
      // +0x13a414 (LDR x6,[x10,#0x28], x10 loaded as NULL from +0x900 of a
      // live driver object) — 3/3 deterministic in the F1d-era builds
      // (F1d-routed-logcat-run3 lines 5920/13463/22664), environment-
      // sensitive (0/4+ reveals the next day on both probe-on and
      // probe-off builds). Same driver bug class as the F1a index-BO
      // map+unmap (commit 3c5d2c7cc): querying draw state on the API
      // thread (texture liveness, bindings, FBO completeness, error flush)
      // at the first draw of each merc flush forces the driver to
      // validate/finalize the state its draw-time walk would otherwise
      // trip over. Kept armed at di==0 and at the historical killer draw
      // (first_index 64945); the snapshot doubles as SIGSEGV-dump
      // forensics (read by gk_sigsegv_diag, no GL calls in the handler).
      if (di == 0 || draw.first_index == 64945) {
        const u32 nm = gk_f1a_last_merc_draw.tex_name;
        gk_f1a_last_merc_draw.tex_is = nm ? (glIsTexture(nm) ? 1 : 0) : 2;
        GLint v = 0;
        glGetIntegerv(GL_TEXTURE_BINDING_2D, &v);
        gk_f1a_last_merc_draw.tex_binding = (u32)v;
        v = 0;
        glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &v);
        gk_f1a_last_merc_draw.fbo_binding = (u32)v;
        gk_f1a_last_merc_draw.fbo_status = glCheckFramebufferStatus(GL_DRAW_FRAMEBUFFER);
        gk_f1a_last_merc_draw.gl_err = glGetError();
        gk_f1a_last_merc_draw.tex_size = (u32)lev->textures.size();
        gk_f1a_last_merc_draw.load_id = (u32)lev->load_id;
        gk_f1a_last_merc_draw.fsl = (u32)lev->frames_since_last_used;
        static u32 s_f1e_probe_n = 0;
        if (draw.first_index == 64945 && (s_f1e_probe_n++ % 30) == 0) {
          fprintf(stderr,
                  "F1E-PROBE lev=%s di=%u/%u tex=0x%x branch=%u name=%u is=%u size=%u bind=%u "
                  "fbo=%u status=0x%x err=0x%x load_id=%u fsl=%u\n",
                  lev->level->level_name.c_str(), di, num_draws, (u32)draw.texture, f1e_branch, nm,
                  gk_f1a_last_merc_draw.tex_is, gk_f1a_last_merc_draw.tex_size,
                  gk_f1a_last_merc_draw.tex_binding, gk_f1a_last_merc_draw.fbo_binding,
                  gk_f1a_last_merc_draw.fbo_status, gk_f1a_last_merc_draw.gl_err,
                  gk_f1a_last_merc_draw.load_id, gk_f1a_last_merc_draw.fsl);
        }
      }
    }
#endif

    if (set_fade) {
      math::Vector4f fade =
          math::Vector4f(draw.fade[0], draw.fade[1], draw.fade[2], draw.fade[3]) / 255.f;
      set_uniform(uniforms.fade, fade);
      ASSERT(draw.mode.get_alpha_blend() == DrawMode::AlphaBlend::SRC_0_DST_DST);
    }

    if (m_lights_buffer[draw.light_idx].w1 && !set_fade) {
      DrawMode mode = draw.mode;
      mode.set_alpha_blend(DrawMode::AlphaBlend::SRC_DST_SRC_DST);
      mode.set_ab(true);
      setup_opengl_from_draw_mode(mode, GL_TEXTURE0, use_mipmaps_for_filtering);
      // this branch ends on a setup_opengl_from_draw_mode(draw.mode) — record it
      last_setup_mode = draw.mode.as_int();
      last_setup_tex = last_tex;
      last_setup_mips = use_mipmaps_for_filtering;
      have_setup = true;

      prof.add_draw_call(2);
      prof.add_tri(draw.num_triangles * 2);
      // Clamp the bound range to the buffer end: the fixed 128-matrix window
      // overhangs for draws whose bones sit in the last 16KB of the bone
      // buffer. Per GL spec offset+size > buffer is an ERROR and leaves the
      // binding point EMPTY — desktop drivers then silently read the stale
      // previous binding; Adreno dereferences the missing BO and crashes in
      // the driver (F1a runs 4/5, fault 0x28). The shader never reads past
      // its declared block contents for the actual bone count.
      if (!f1a_noubo && (!cache_state || (s64)draw.first_bone != last_first_bone)) {
        glBindBufferRange(
            GL_UNIFORM_BUFFER, 1, m_bones_buffer,
            sizeof(math::Vector4f) * (bones_base + draw.first_bone),
            std::min((GLsizeiptr)(128 * sizeof(ShaderMercMat)),
                     (GLsizeiptr)(MAX_SHADER_BONE_VECTORS * sizeof(math::Vector4f) -
                                  sizeof(math::Vector4f) * (bones_base + draw.first_bone))));
        last_first_bone = draw.first_bone;
      }
      // draw rgb
      const auto& l1_dir = m_lights_buffer[draw.light_idx].direction1;
      math::Vector4f l1_dir_f(l1_dir.x(), l1_dir.y(), l1_dir.z(), 1);
      set_uniform(uniforms.light_direction[1], l1_dir_f);
      glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_FALSE);
      if (!f1a_nodraw) {
        glDrawElements(draw.no_strip ? GL_TRIANGLES : GL_TRIANGLE_STRIP, draw.index_count,
                       GL_UNSIGNED_INT, (void*)(sizeof(u32) * draw.first_index));
      }
      // draw a
      setup_opengl_from_draw_mode(draw.mode, GL_TEXTURE0, use_mipmaps_for_filtering);
      math::Vector4f l1_dir_f_off(l1_dir.x(), l1_dir.y(), l1_dir.z(), -1);
      set_uniform(uniforms.light_direction[1], l1_dir_f_off);
      glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_TRUE);
      if (!f1a_nodraw) {
        glDrawElements(draw.no_strip ? GL_TRIANGLES : GL_TRIANGLE_STRIP, draw.index_count,
                       GL_UNSIGNED_INT, (void*)(sizeof(u32) * draw.first_index));
      }
      glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);

    } else {
      if (!cache_state || !have_setup || draw.mode.as_int() != last_setup_mode ||
          last_tex != last_setup_tex || use_mipmaps_for_filtering != last_setup_mips) {
        setup_opengl_from_draw_mode(draw.mode, GL_TEXTURE0, use_mipmaps_for_filtering);
        last_setup_mode = draw.mode.as_int();
        last_setup_tex = last_tex;
        last_setup_mips = use_mipmaps_for_filtering;
        have_setup = true;
      }
      prof.add_draw_call();
      prof.add_tri(draw.num_triangles);
      // Same end-of-buffer clamp as the two-pass path above.
      if (!f1a_noubo && (!cache_state || (s64)draw.first_bone != last_first_bone)) {
        glBindBufferRange(
            GL_UNIFORM_BUFFER, 1, m_bones_buffer,
            sizeof(math::Vector4f) * (bones_base + draw.first_bone),
            std::min((GLsizeiptr)(128 * sizeof(ShaderMercMat)),
                     (GLsizeiptr)(MAX_SHADER_BONE_VECTORS * sizeof(math::Vector4f) -
                                  sizeof(math::Vector4f) * (bones_base + draw.first_bone))));
        last_first_bone = draw.first_bone;
      }
      if (!f1a_nodraw) {
        glDrawElements(draw.no_strip ? GL_TRIANGLES : GL_TRIANGLE_STRIP, draw.index_count,
                       GL_UNSIGNED_INT, (void*)(sizeof(u32) * draw.first_index));
      }
    }
  }

  if (!normal_vtx_buffer_bound) {
    glBindVertexArray(m_vao);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, lev->merc_indices);
    glBindBuffer(GL_ARRAY_BUFFER, lev->merc_vertices);
  }
}
