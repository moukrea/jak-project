#include "Merc2.h"

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
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <chrono>
#include <mutex>
#include <set>
#include <unordered_map>
#include <vector>
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif
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

void Merc2::model_mod_blerc_draws(int num_effects,
                                  const tfrag3::MercModel* model,
                                  const LevelData* lev,
                                  ModBuffers* mod_opengl_buffers,
                                  const float* blerc_weights,
                                  MercDebugStats* stats) {
  // loop over effects.
  for (int ei = 0; ei < num_effects; ei++) {
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

// CYCLE-3 FLICKER DETECTOR (metrics not eyeballs): a "blackout" is a stock packet suppressed
// while its companion has NOT submitted for more than ~1 frame — the exact frame-level signature
// of the owner-reported cutscene NPC flicker. jak1 makes 16 Merc2::render calls per frame
// (16 Merc2BucketRenderers sharing this instance), so TTL 32 = ~2 frames and a healthy covered
// actor re-arms every ~16 calls. Counters are always on; logging is event-driven + a periodic
// heartbeat, so a healthy run stays quiet and the cutscene proof leg can grep blackouts=0.
static u64 s_hd_render_call_idx = 0;                       // render-thread only
static std::unordered_map<u32, u64> s_hd_last_arm_call;    // driver_pid -> render call idx
static u64 s_hd_blackout_events = 0;
static u64 s_hd_submit_gap_events = 0;
static u64 s_hd_ttl_expiries = 0;
static bool s_hd_ever_armed = false;  // heartbeat stays silent until the first companion arms

// CYCLE-3 (Keira black-eyes-on-blink): dynamic eye slots referenced by actively-submitting HD
// companion draws. Armed alongside the pid TTL, drained in render(); EyeRenderer consults this
// to skip the full-tile lid blit for these slots (see Merc2.h). Render-thread only.
static int s_hd_eye_slot_ttl[256] = {};

bool merc2_hd_eye_slot_covered(u8 slot) {
  return s_hd_eye_slot_ttl[slot] > 0;
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
#ifdef OG_FEAT_HD_MODELS
  // Grecharged-hd-models4 PER-ACTOR coverage (see the block at the HdCoverPair definition).
  u32 owner_pid = 0;
  memcpy(&owner_pid, setup.data + 120, sizeof(owner_pid));
  if (strstr(name, "-hd-lod0")) {
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
    if (model_ref && owner_pid != 0) {
      u32 driver_pid = 0;
      {
        std::lock_guard<std::mutex> lock(s_hd_cover_mutex);
        for (const auto& p : s_hd_cover_pairs) {
          if (p.companion_pid == owner_pid) {
            driver_pid = p.driver_pid;
            break;
          }
        }
      }
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
        // arm the HD-covered eye slots (lid-blit suppression, see merc2_hd_eye_slot_covered).
        for (const auto& eff : model_ref->model->effects) {
          for (const auto& d : eff.all_draws) {
            if (d.eye_id != 0xff) {
              s_hd_eye_slot_ttl[d.eye_id] = 32;
            }
          }
        }
      }
    }
  } else if (owner_pid != 0) {
    // a stock packet: drop it ONLY if ITS OWN pid is covered by an actively-submitting companion.
    // Renderer-level (never GOAL draw-status: skip-bones on *target* propagated to the sidekick
    // and swallowed Daxter on M1 builds 10-12). Uncovered same-name actors (ND logo) draw stock.
    auto it = s_hd_driver_ttl.find(owner_pid);
    if (it != s_hd_driver_ttl.end() && it->second > 0) {
      static std::unordered_map<u32, u64> s_hd_suppress_counts;
      u64& n = s_hd_suppress_counts[owner_pid];
      if (n++ % 600 == 0) {
        lg::warn("[hd-render] suppress pid={} name='{}' (covered per-actor)", owner_pid, name);
      }
      // flicker detector BLACKOUT: this stock draw is being dropped although the companion has
      // not submitted for more than ~1.25 frames — the actor is on screen (its stock packet just
      // arrived) yet nothing will draw it this frame. This is the owner-visible flicker signature
      // and the number the cycle-3 fix must hold at 0 through a full cutscene.
      auto arm_it = s_hd_last_arm_call.find(owner_pid);
      if (arm_it == s_hd_last_arm_call.end() ||
          s_hd_render_call_idx - arm_it->second > 20) {
        s_hd_blackout_events++;
        if (s_hd_blackout_events <= 20 || s_hd_blackout_events % 50 == 0) {
          lg::warn("[hd-flicker] BLACKOUT pid={} name='{}' since_arm={}", owner_pid, name,
                   arm_it == s_hd_last_arm_call.end()
                       ? (u64)0
                       : s_hd_render_call_idx - arm_it->second);
        }
      }
      return;
    }
  }
#endif
  if (!model_ref) {
    // it can fail, if the game is faster than the loader. In this case, we just don't draw.
    stats->num_missing_models++;
    return;
  }

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

  // === Gd3-jak FIX (always-on, arm64): repair non-finite merc bone matrices =====
  // In the new-game intro cinematic a degenerate root-motion align frame can bake a
  // NaN into Jak's control.trans (1/0 in matrix-inv-scale!, ENGINE.CGO — which is
  // not rebuildable on the device, see feedback-game-cgo-rebuild-unsafe), and it
  // cascades through the whole skeleton. The Adreno GLES driver then FAULTS (sig=11,
  // GL-thread crash inside libGLESv2_adreno during the merc draw) on the NaN bone
  // data, and Jak flickers invisible on that frame. We cannot fix the CGO root, so
  // repair at the merc boundary: if any of this model's used bone matrices is
  // non-finite, restore the model's last fully-finite bone set (or identity on the
  // first frame). x86 never produces NaN here so this is compiled out on desktop.
  const bool gd3_is_jak = gd3_bones_on() && std::strstr(name, "eichar") != nullptr;
  int gd3_bones_repaired = 0;
#ifdef __aarch64__
  {
    static std::unordered_map<std::string, std::vector<ShaderMercMat>> s_last_good;
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
    if (!any_bad) {
      // snapshot this fully-finite frame as the model's last-good bones
      auto& snap = s_last_good[model->name];
      snap.assign(skel_matrix_buffer, skel_matrix_buffer + MAX_SKEL_BONES);
    } else {
      auto it = s_last_good.find(model->name);
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
        // repair, so the collapsed bone simply renders invisible -- correct). The old
        // code restored the WHOLE bone for ANY non-finite element, which on arm64
        // replaced the CORRECT tmat with a stale/identity one -> the degenerate logo
        // parts became visible/torn = the owner's "garbled logo". Fix: restore the whole
        // bone ONLY when the tmat (the position) is itself corrupt (the Gd3-jak /
        // Gcine-pose genuine-NaN case); when only the nmat is non-finite, KEEP the
        // finite tmat and sanitize just the nmat to identity so Adreno never sees a NaN.
        // This makes the arm64 logo render match x86 exactly.
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
          skel_matrix_buffer[slot] = (it != s_last_good.end() && slot < (int)it->second.size())
                                         ? it->second[slot]
                                         : kIdent;
          gd3_bones_repaired++;
        } else if (nmat_bad) {
          // keep the finite, correct tmat; reset only the normal matrix to identity.
          for (int k = 16; k < 32; k++) {
            f[k] = 0.f;
          }
          f[16] = f[21] = f[26] = 1.f;  // nmat = identity
          gd3_bones_repaired++;
        }
      }
    }
  }
#endif
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
  // drain the eye-slot coverage TTLs (armed with the pid TTLs, read by EyeRenderer).
  for (int& t : s_hd_eye_slot_ttl) {
    if (t > 0) {
      t--;
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
    lg::warn("[hd-flicker] calls={} blackouts={} gaps={} expiries={}", s_hd_render_call_idx,
             s_hd_blackout_events, s_hd_submit_gap_events, s_hd_ttl_expiries);
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

  Draw* draw = &args.lev_bucket->envmap_draws[args.lev_bucket->next_free_envmap_draw++];
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
  Draw* draw = &args.lev_bucket->draws[args.lev_bucket->next_free_draw++];
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
  }

  m_next_free_light = 0;
  m_next_free_bone_vector = 0;
  m_next_free_level_bucket = 0;
  m_next_mod_vtx_buffer = 0;
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
        if (slot >= 0 && (size_t)slot < m_anim_slot_array->size()) {
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
                restarts, lev->level->merc_data.vertices.size(), gpu_match, glGetError());
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
