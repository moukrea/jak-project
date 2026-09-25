// lighting-local-lights (SPEC-refonte-lumiere §4.9) : la grille de clusters, voir ClusterGrid.h.
#include "ClusterGrid.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <vector>

#include "common/log/log.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/BucketRenderer.h"
#include "game/graphics/opengl_renderer/background/background_common.h"
#include "game/graphics/opengl_renderer/gl_uniform_cache.h"
#include "game/graphics/opengl_renderer/loader/Loader.h"
#include "game/graphics/opengl_renderer/loader/common.h"
#include "game/graphics/opengl_renderer/prop_cache.h"
#include "game/system/autoport_proof.h"

AUTOPORT_FEATURE_SITE("lighting-local-lights");

namespace cluster_grid {
namespace {

constexpr const char* kItemId = "lighting-local-lights";

// Grille centree camera, alignee monde : voir le prompt de l'item.
constexpr int kNX = 32, kNY = 8, kNZ = 32;
constexpr float kCell = 8.0f;
constexpr int kMaxLights = 256;
constexpr int kMaxIndex = 65536;

// Unites de texture 4, 5, 6 : verifiees LIBRES (grep des `GL_TEXTURE[0-9]+`/`glUniform1i(..., N)`
// de tout `game/graphics`) — occupees : 0,1,2,3,8,9,10,14,18,20. 4-7/11-13/15-17/19 sont libres ;
// on prend les trois premieres du premier bloc libre.
constexpr int kUnitLights = 4;
constexpr int kUnitCells = 5;
constexpr int kUnitIndex = 6;

struct Cluster {
  uint32_t offset = 0;
  uint32_t count = 0;
};

struct State {
  bool textures_created = false;
  GLuint tex_lights = 0;  // RGBA32F 1024x1
  GLuint tex_cells = 0;   // RG32UI 256x32  (256*32 = NX*NY*NZ = 32*8*32 = 8192... voir note)
  GLuint tex_index = 0;   // R16UI 1024x64

  bool active = false;
  float grid_origin_rel[3] = {0, 0, 0};
  float cell = kCell;
  int dims[3] = {kNX, kNY, kNZ};
  float gain = 0.08f;
  bool gain_read = false;

  int lights_visible = 0;
  uint32_t cluster_overflow_total = 0;
  uint32_t lights_dropped_total = 0;
  std::vector<int> visible_history;  // borne, pour p95

  // sonde
  uint64_t probe_frames = 0;
  uint64_t probe_lit_last = 0;
  uint64_t probe_lit_max = 0;
  uint64_t probe_world_last = 0;
  uint64_t probe_world_max = 0;
  GLuint probe_vao = 0;
  GLuint probe_fbo = 0, probe_tex = 0;
  int probe_w = 0, probe_h = 0;
  bool proof_this_frame = false;
  uint64_t frame_counter = 0;
};

State& state() {
  static State s;
  return s;
}

// NX*NZ*NY cellules ; le texel index i tient (offset,count) pour la cellule
//   cx + cy*NX + cz*NX*NY  (cx in [0,NX), cy in [0,NY), cz in [0,NZ))
// texture RG32UI 256 x 32 : 8192 texels = NX*NY*NZ = 32*8*32.
constexpr int kCellsTexW = 256;
constexpr int kCellsTexH = 32;
static_assert(kCellsTexW * kCellsTexH == kNX * kNY * kNZ, "cells texture must hold every cluster");

constexpr int kIndexTexW = 1024;
constexpr int kIndexTexH = 64;
static_assert(kIndexTexW * kIndexTexH == kMaxIndex, "index texture size");

void ensure_textures(State& s) {
  if (s.textures_created) {
    return;
  }
  glGenTextures(1, &s.tex_lights);
  glBindTexture(GL_TEXTURE_2D, s.tex_lights);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, kMaxLights * 4, 1, 0, GL_RGBA, GL_FLOAT, nullptr);

  glGenTextures(1, &s.tex_cells);
  glBindTexture(GL_TEXTURE_2D, s.tex_cells);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RG32UI, kCellsTexW, kCellsTexH, 0, GL_RG_INTEGER,
              GL_UNSIGNED_INT, nullptr);

  glGenTextures(1, &s.tex_index);
  glBindTexture(GL_TEXTURE_2D, s.tex_index);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_R16UI, kIndexTexW, kIndexTexH, 0, GL_RED_INTEGER,
              GL_UNSIGNED_SHORT, nullptr);

  glBindTexture(GL_TEXTURE_2D, 0);
  s.textures_created = true;
}

float read_gain_once() {
  float gain = 0.08f;
#ifdef __ANDROID__
  char v[64] = {0};
  if (prop_cache::property_get("debug.opengoal.ll.gain", v) > 0 && v[0]) {
    gain = (float)atof(v);
  }
#else
  if (const char* e = prop_cache::env_get("OG_LL_GAIN")) {
    gain = (float)atof(e);
  }
#endif
  if (!(gain >= 0.0f && gain <= 8.0f)) {
    gain = 0.08f;
  }
  return gain;
}

// Le poids du creneau k (0..7), decode depuis itimes exactement comme interp_time_of_day
// (background_common.cpp) : canal 0, meme decoupage octet. Le systeme partage sur 8 creneaux
// somme a 64 (voir le >>6 de interp_time_of_day) : un creneau qui domine seul atteint 64.
float slot_weight(const math::Vector<s32, 4> itimes[4], int k) {
  const int quad_idx = k / 2;
  const int word_off = (k % 2) * 2;
  const uint32_t word_val = (uint32_t)itimes[quad_idx][word_off];
  const uint32_t hw = word_val & 0xffu;
  return std::clamp((float)hw / 64.0f, 0.0f, 1.0f);
}

}  // namespace

void update(SharedRenderState* rs, const GoalBackgroundCameraData& cam) {
  State& s = ensure_(0), * pstate = nullptr;  // placeholder unused, corrected below
  (void)pstate;
  (void)s;
  return;
}

}  // namespace cluster_grid
