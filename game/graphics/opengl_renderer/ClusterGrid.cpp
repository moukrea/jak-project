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
constexpr float kMeter = 4096.f;

// Grille alignee MONDE, centree camera : 32 x 16 x 32 cellules de 8 m = 256 x 128 x 256 m. Une
// sphere contre une boite alignee est un test EXACT : une lumiere n'est rangee que dans les
// cellules que son rayon touche vraiment, et shade.glsl coupe au meme rayon.
constexpr int kNX = 32, kNY = 16, kNZ = 32;
constexpr int kCells = kNX * kNY * kNZ;
constexpr float kCell = 8.0f;
constexpr float kFar = 120.0f;  // SPEC §4.9 : au-dela de 120 m, aucune lumiere n'est rangee
constexpr int kMaxLights = 256;
constexpr int kMaxPerCell = 16;  // == LL_MAX_PER_CELL de local_lights.glsl

// Formes des textures : DOIVENT egaler les `& 127 / >> 7` et `& 1023 / >> 10` de
// local_lights.glsl.
constexpr int kCellsTexW = 128;
constexpr int kCellsTexH = kCells / kCellsTexW;
static_assert(kCellsTexW * kCellsTexH == kCells, "cells texture must hold every cluster");
constexpr int kIndexTexW = 1024;
constexpr int kIndexTexH = 64;
constexpr int kMaxIndex = kIndexTexW * kIndexTexH;

// Unites 4, 5, 6 : libres dans tout game/graphics/opengl_renderer (occupees : 0,1,2,8,9,10,14,
// 18,20 ; grep des GL_TEXTURE<N> le 25/09).
constexpr int kUnitLights = 4;
constexpr int kUnitCells = 5;
constexpr int kUnitIndex = 6;

// Image sondee : une sur 60, seulement quand la course de preuve nomme CET item.
constexpr uint64_t kProbeEvery = 60;

struct State {
  bool textures_created = false;
  GLuint tex_lights = 0, tex_cells = 0, tex_index = 0;

  bool active = false;  // la grille de CETTE image est remplie et televersee
  float origin_rel[3] = {0, 0, 0};
  float gain = 0.3f;

  // vacillement : poids du creneau relu dans les itimes, normalise par son maximum observe
  float slot_max[8] = {0, 0, 0, 0, 0, 0, 0, 0};

  // tampons reutilises d'une image a l'autre
  std::vector<float> lights_tex;  // kMaxLights * 4 texels RGBA
  std::vector<float> cells_tex;   // kCells texels RG
  std::vector<float> index_tex;   // kMaxIndex texels R
  std::vector<std::vector<uint16_t>> cell_lists;

  // compteurs publies
  uint64_t frames_active = 0;
  uint64_t lights_loaded_max = 0;
  uint64_t lights_visible_max = 0;
  uint64_t cell_overflow_total = 0;
  uint64_t lights_dropped_total = 0;
  uint64_t flicker_lights_max = 0;
  float flicker_min = 1.f, flicker_max = 0.f;

  // sonde
  bool probe_frame = false;
  uint64_t probes = 0;
  uint64_t probe_lit_last = 0, probe_lit_max = 0, probe_world_last = 0;
  GLuint probe_fbo = 0, probe_tex = 0;
  int probe_w = 0, probe_h = 0;
};

State& state() {
  static State s;
  return s;
}

void make_tex(GLuint* tex, GLint ifmt, int w, int h, GLenum fmt) {
  glGenTextures(1, tex);
  glBindTexture(GL_TEXTURE_2D, *tex);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexImage2D(GL_TEXTURE_2D, 0, ifmt, w, h, 0, fmt, GL_FLOAT, nullptr);
}

void ensure_textures(State& s) {
  if (s.textures_created) {
    return;
  }
  make_tex(&s.tex_lights, GL_RGBA32F, kMaxLights * 4, 1, GL_RGBA);
  make_tex(&s.tex_cells, GL_RG32F, kCellsTexW, kCellsTexH, GL_RG);
  make_tex(&s.tex_index, GL_R32F, kIndexTexW, kIndexTexH, GL_RED);
  glBindTexture(GL_TEXTURE_2D, 0);
  s.lights_tex.assign((size_t)kMaxLights * 4 * 4, 0.f);
  s.cells_tex.assign((size_t)kCells * 2, 0.f);
  s.index_tex.assign((size_t)kMaxIndex, 0.f);
  s.cell_lists.assign(kCells, {});
  s.textures_created = true;
}

float read_gain() {
  float gain = 0.3f;
  char v[96] = {0};
  if (prop_cache::property_get("debug.opengoal.ll.gain", v) > 0 && v[0]) {
    gain = (float)atof(v);
  } else if (const char* e = prop_cache::env_get("OG_LL_GAIN")) {
    gain = (float)atof(e);
  }
  if (!(gain >= 0.0f && gain <= 8.0f)) {
    gain = 0.3f;
  }
  return gain;
}

// Poids RGB du creneau k dans les itimes, decode EXACTEMENT comme interp_time_of_day
// (background_common.cpp) : quad k/2, mot (k%2)*2 + canal/2, demi-mot canal%2, octet bas.
// update-mood-itimes y range times[k].rgb x times[k].w : c'est la valeur que update-mood-flames /
// update-mood-lava animent, donc la meme donnee que le vacillement du cuit d'origine.
float slot_rgb_weight(const math::Vector<s32, 4> itimes[4], int k) {
  const int quad_idx = k / 2;
  const int word_off = (k % 2) * 2;
  float sum = 0.f;
  for (int channel = 0; channel < 3; channel++) {
    const uint32_t word_val = (uint32_t)itimes[quad_idx][word_off + channel / 2];
    const uint32_t hw = (channel % 2) ? (word_val >> 16) : word_val;
    sum += (float)(hw & 0xffu);
  }
  return sum;
}

struct Cand {
  const local_lights::Light* l;
  float rel[3];
  float dist;
  float scale;  // vacillement x gain
};

}  // namespace

void update(SharedRenderState* rs, const GoalBackgroundCameraData& cam) {
  State& s = state();
  s.active = false;
  s.probe_frame = false;
  if (!rs || !rs->loader || !Gfx::recharged_lighting_active() ||
      !autoport_proof::armed_for(kItemId)) {
    return;
  }

  // Vacillement : le maximum observe decroit lentement (demi-vie ~ 20 s a 60 img/s) pour suivre
  // un changement de niveau ou d'heure sans jamais diviser par zero.
  float flick[8];
  for (int k = 0; k < 8; k++) {
    const float w = slot_rgb_weight(cam.itimes, k);
    s.slot_max[k] = std::max(s.slot_max[k] * 0.99943f, w);
    flick[k] = s.slot_max[k] > 0.f ? w / s.slot_max[k] : 0.f;
  }

  const float cam_m[3] = {cam.trans.x() / kMeter, cam.trans.y() / kMeter, cam.trans.z() / kMeter};
  const float half[3] = {kNX * kCell * 0.5f, kNY * kCell * 0.5f, kNZ * kCell * 0.5f};

  static std::vector<Cand> cands;
  cands.clear();
  uint64_t loaded = 0;
  for (LevelData* lev : rs->loader->get_in_use_levels()) {
    loaded += lev->local_lights.size();
    for (const auto& l : lev->local_lights) {
      Cand c;
      c.l = &l;
      float d2 = 0.f;
      bool inside = true;
      for (int i = 0; i < 3; i++) {
        c.rel[i] = l.pos[i] - cam_m[i];
        d2 += c.rel[i] * c.rel[i];
        // la sphere doit toucher la grille
        if (c.rel[i] + l.radius < -half[i] || c.rel[i] - l.radius > half[i]) {
          inside = false;
        }
      }
      c.dist = std::sqrt(d2);
      if (!inside || c.dist - l.radius > kFar) {
        continue;
      }
      const float f = (l.flicker < 8) ? flick[l.flicker] : 1.f;
      c.scale = f * s.gain;
      if (!(c.scale > 0.f) || !(l.intensity > 0.f)) {
        continue;
      }
      cands.push_back(c);
    }
  }
  s.lights_loaded_max = std::max(s.lights_loaded_max, loaded);
  if (cands.empty()) {
    autoport_proof::publish("ll_lights_loaded", loaded);
    autoport_proof::publish("ll_lights_visible", 0);
    return;
  }
  if ((int)cands.size() > kMaxLights) {
    std::nth_element(cands.begin(), cands.begin() + kMaxLights, cands.end(),
                     [](const Cand& a, const Cand& b) { return a.dist < b.dist; });
    s.lights_dropped_total += cands.size() - kMaxLights;
    cands.resize(kMaxLights);
  }

  ensure_textures(s);
  if (s.frames_active % 60 == 0) {
    s.gain = read_gain();
  }
  for (int i = 0; i < 3; i++) {
    s.origin_rel[i] = -half[i];
  }

  // 1) lumieres
  uint64_t flicker_lights = 0;
  for (size_t li = 0; li < cands.size(); li++) {
    const Cand& c = cands[li];
    const auto& l = *c.l;
    float* t = &s.lights_tex[li * 16];
    t[0] = c.rel[0];
    t[1] = c.rel[1];
    t[2] = c.rel[2];
    t[3] = l.radius;
    for (int i = 0; i < 3; i++) {
      t[4 + i] = l.rgb[i] * l.intensity * c.scale;
    }
    t[7] = (float)l.type;
    t[8] = l.dir[0];
    t[9] = l.dir[1];
    t[10] = l.dir[2];
    t[11] = l.cos_outer;
    t[12] = l.cos_inner;
    t[13] = t[14] = t[15] = 0.f;
    if (l.flicker < 8) {
      flicker_lights++;
      const float f = c.scale / std::max(s.gain, 1e-6f);
      s.flicker_min = std::min(s.flicker_min, f);
      s.flicker_max = std::max(s.flicker_max, f);
    }
  }

  // 2) rangement exact sphere / cellule
  for (auto& cl : s.cell_lists) {
    cl.clear();
  }
  uint64_t overflow = 0;
  for (size_t li = 0; li < cands.size(); li++) {
    const Cand& c = cands[li];
    const float r = c.l->radius;
    int lo[3], hi[3];
    for (int i = 0; i < 3; i++) {
      const float g = c.rel[i] - s.origin_rel[i];
      const int n = (i == 0) ? kNX : (i == 1) ? kNY : kNZ;
      lo[i] = std::clamp((int)std::floor((g - r) / kCell), 0, n - 1);
      hi[i] = std::clamp((int)std::floor((g + r) / kCell), 0, n - 1);
    }
    for (int z = lo[2]; z <= hi[2]; z++) {
      for (int y = lo[1]; y <= hi[1]; y++) {
        for (int x = lo[0]; x <= hi[0]; x++) {
          const int cell[3] = {x, y, z};
          float d2 = 0.f;
          for (int i = 0; i < 3; i++) {
            const float g = c.rel[i] - s.origin_rel[i];
            const float mn = cell[i] * kCell, mx = mn + kCell;
            const float q = std::clamp(g, mn, mx) - g;
            d2 += q * q;
          }
          if (d2 >= r * r) {
            continue;
          }
          auto& cl = s.cell_lists[x + kNX * (y + kNY * z)];
          if ((int)cl.size() >= kMaxPerCell) {
            overflow++;
            continue;
          }
          cl.push_back((uint16_t)li);
        }
      }
    }
  }
  uint32_t off = 0;
  for (int ci = 0; ci < kCells; ci++) {
    auto& cl = s.cell_lists[ci];
    if (off + cl.size() > (uint32_t)kMaxIndex) {
      overflow += cl.size();
      cl.clear();
    }
    s.cells_tex[ci * 2] = (float)off;
    s.cells_tex[ci * 2 + 1] = (float)cl.size();
    for (uint16_t li : cl) {
      s.index_tex[off++] = (float)li;
    }
  }
  s.cell_overflow_total += overflow;

  // 3) televersement (fil de rendu)
  glBindTexture(GL_TEXTURE_2D, s.tex_lights);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, (GLsizei)cands.size() * 4, 1, GL_RGBA, GL_FLOAT,
                  s.lights_tex.data());
  glBindTexture(GL_TEXTURE_2D, s.tex_cells);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, kCellsTexW, kCellsTexH, GL_RG, GL_FLOAT,
                  s.cells_tex.data());
  if (off > 0) {
    const int rows = (int)((off + kIndexTexW - 1) / kIndexTexW);
    glBindTexture(GL_TEXTURE_2D, s.tex_index);
    glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, kIndexTexW, rows, GL_RED, GL_FLOAT,
                    s.index_tex.data());
  }
  glBindTexture(GL_TEXTURE_2D, 0);

  s.active = true;
  s.frames_active++;
  s.lights_visible_max = std::max<uint64_t>(s.lights_visible_max, cands.size());
  s.flicker_lights_max = std::max(s.flicker_lights_max, flicker_lights);
  s.probe_frame = autoport_proof::feature_is(kItemId) && (rs->frame_idx % kProbeEvery) == 0;

  autoport_proof::publish("ll_lights_loaded", loaded);
  autoport_proof::publish("ll_lights_loaded_max", s.lights_loaded_max);
  autoport_proof::publish("ll_lights_visible", cands.size());
  autoport_proof::publish("ll_lights_visible_max", s.lights_visible_max);
  autoport_proof::publish("ll_index_entries", off);
  autoport_proof::publish("ll_cell_overflow_total", s.cell_overflow_total);
  autoport_proof::publish("ll_lights_dropped_total", s.lights_dropped_total);
  autoport_proof::publish("ll_frames_active", s.frames_active);
  autoport_proof::publish("ll_flicker_lights_max", s.flicker_lights_max);
  // vacillement observe, en millièmes du maximum du creneau : min < max = la lumiere a bouge
  autoport_proof::publish("ll_flicker_min_permille",
                          (uint64_t)std::lround(std::min(s.flicker_min, 1.f) * 1000.f));
  autoport_proof::publish("ll_flicker_max_permille",
                          (uint64_t)std::lround(std::min(s.flicker_max, 1.f) * 1000.f));
  autoport_proof::publish("ll_gain_milli", (uint64_t)std::lround(s.gain * 1000.f));
}

void bind_program_uniforms(GLuint program) {
  State& s = state();
  // Les unites des echantillonneurs sont posees MEME eteint : un echantillonneur laisse a
  // l'unite 0 partagerait l'unite de tex_T0 — sans effet sur les pixels (non lu), mais on ne
  // laisse pas deux echantillonneurs sur une unite.
  glUniform1i(glu::loc(program, "u_ll_lights"), kUnitLights);
  glUniform1i(glu::loc(program, "u_ll_cells"), kUnitCells);
  glUniform1i(glu::loc(program, "u_ll_index"), kUnitIndex);
  glUniform1i(glu::loc(program, "u_ll_on"), s.active ? 1 : 0);
  glUniform1i(glu::loc(program, "u_ll_proof"), (s.active && s.probe_frame) ? 1 : 0);
  if (!s.active) {
    return;
  }
  glUniform3f(glu::loc(program, "u_ll_origin"), s.origin_rel[0], s.origin_rel[1],
              s.origin_rel[2]);
  glUniform1f(glu::loc(program, "u_ll_inv_cell"), 1.0f / kCell);
  glUniform3i(glu::loc(program, "u_ll_dims"), kNX, kNY, kNZ);
  glActiveTexture(GL_TEXTURE0 + kUnitLights);
  glBindTexture(GL_TEXTURE_2D, s.tex_lights);
  glActiveTexture(GL_TEXTURE0 + kUnitCells);
  glBindTexture(GL_TEXTURE_2D, s.tex_cells);
  glActiveTexture(GL_TEXTURE0 + kUnitIndex);
  glBindTexture(GL_TEXTURE_2D, s.tex_index);
  glActiveTexture(GL_TEXTURE0);
}

void proof_post_opaque(SharedRenderState* rs) {
  State& s = state();
  if (!s.probe_frame || !s.active || !rs) {
    return;
  }
  s.probe_frame = false;  // une seule relecture par image sondee
  GLint prev_read = 0, prev_draw = 0, prev_vp[4] = {0, 0, 0, 0};
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prev_read);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prev_draw);
  glGetIntegerv(GL_VIEWPORT, prev_vp);
  const int w = rs->render_fb_w > 0 ? rs->render_fb_w : prev_vp[2];
  const int h = rs->render_fb_h > 0 ? rs->render_fb_h : prev_vp[3];
  if (w <= 0 || h <= 0 || (int64_t)w * h > 3840 * 2160) {
    return;
  }
  GLboolean prev_scissor = glIsEnabled(GL_SCISSOR_TEST);
  glDisable(GL_SCISSOR_TEST);
  if (!s.probe_fbo || s.probe_w != w || s.probe_h != h) {
    if (s.probe_fbo) {
      glDeleteFramebuffers(1, &s.probe_fbo);
      glDeleteTextures(1, &s.probe_tex);
    }
    glGenTextures(1, &s.probe_tex);
    glBindTexture(GL_TEXTURE_2D, s.probe_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glBindTexture(GL_TEXTURE_2D, 0);
    glGenFramebuffers(1, &s.probe_fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, s.probe_fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, s.probe_tex, 0);
    s.probe_w = w;
    s.probe_h = h;
  }
  // Le tampon de rendu peut etre multi-echantillonne : on le resout dans un FBO simple.
  glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)prev_draw);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, s.probe_fbo);
  glBlitFramebuffer(0, 0, w, h, 0, 0, w, h, GL_COLOR_BUFFER_BIT, GL_NEAREST);

  std::vector<uint8_t> px((size_t)w * h * 4);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, s.probe_fbo);
  glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
  const GLenum err = glGetError();

  glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)prev_read);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)prev_draw);
  if (prev_scissor) {
    glEnable(GL_SCISSOR_TEST);
  }

  if (err != GL_NO_ERROR) {
    autoport_proof::publish("ll_probe_gl_error", (uint64_t)err);
    return;
  }
  // vert = fragment ou les lumieres locales ont ajoute >= 1/255 ; bleu = fragment ombre par
  // shade() sans apport local. Le brouillard de l'hote peut teinter le drapeau : on classe par
  // dominance, pas par egalite.
  uint64_t lit = 0, world = 0;
  for (size_t i = 0; i < px.size(); i += 4) {
    const int r = px[i], g = px[i + 1], b = px[i + 2];
    if (g > r + 60 && g > b + 60) {
      lit++;
      world++;
    } else if (b > r + 60 && b > g + 60) {
      world++;
    }
  }
  s.probes++;
  s.probe_lit_last = lit;
  s.probe_lit_max = std::max(s.probe_lit_max, lit);
  s.probe_world_last = world;
  autoport_proof::note_hit_for(kItemId, lit);
  autoport_proof::publish("ll_probe_frames", s.probes);
  autoport_proof::publish("ll_probe_lit_px_last", lit);
  autoport_proof::publish("ll_probe_lit_px_max", s.probe_lit_max);
  autoport_proof::publish("ll_probe_world_px_last", world);
  autoport_proof::publish("ll_probe_px_total", (uint64_t)w * (uint64_t)h);
}

}  // namespace cluster_grid
