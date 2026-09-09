#include "PrePass.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <unordered_set>
#include <vector>

#include "common/log/log.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/AmbientOcclusion.h"
#include "game/graphics/opengl_renderer/background/background_common.h"
#include "game/graphics/opengl_renderer/buckets.h"
#include "game/graphics/opengl_renderer/lighting_census.h"
#include "game/system/autoport_proof.h"

// Definie dans background_common.cpp (liaison externe, pas de declaration dans son .h) : LA
// matrice que tfrag3.vert consomme sous le nom `pc_camera`. La prepasse doit projeter avec la
// meme, sinon sa profondeur ne serait pas celle de la passe principale.
std::array<math::Vector4f, 4> make_new_cam_mat(const math::Vector4f cam_T_w[4],
                                               const math::Vector4f persp[4],
                                               float fog_constant,
                                               float hvdf_z);

namespace prepass {
namespace {

constexpr const char* kItemId = "lighting-ao-indirect";
// Une image sondee sur N sous mesure : la relecture couleur + stencil pleine resolution coute
// une synchronisation GPU, on ne la paie pas a chaque image.
constexpr uint64_t kProbeEvery = 60;

std::vector<DepthContributor*> g_contributors;
AmbientOcclusionPass g_ao;
ShaderLibrary* g_shaders = nullptr;

// Le FBO de la prepasse : profondeur seule (DEPTH24_STENCIL8, comme l'attachement du FBO de
// rendu que les estimateurs lisaient avant), aucune couleur.
GLuint g_fbo = 0;
GLuint g_depth_tex = 0;
int g_w = 0, g_h = 0;

// 1x1 blanc : lie sur l'unite 8 quand l'AO est eteinte, pour que l'unite soit toujours
// complete (un sampler declare et non lie rend un comportement indefini sur Adreno).
GLuint g_white_tex = 0;

// Etat d'image.
uint64_t g_frame = 0;
bool g_frame_ran = false;  // on_first_camera a deja tourne cette image
bool g_ao_valid = false;   // g_ao.texture() decrit cette image
uint64_t g_last_indices = 0;
int g_last_levels = 0;

// Preuve.
bool g_probe_frame = false;
uint64_t g_probe_frames = 0;
uint64_t g_probe_px = 0;
uint64_t g_leak_px = 0;
uint64_t g_excluded_px = 0;
uint64_t g_hit_px = 0;
uint64_t g_unmarked_px = 0;
GLuint g_probe_fbo = 0, g_probe_color = 0, g_probe_ds = 0;
int g_probe_w = 0, g_probe_h = 0;
int g_probe_state = 0;  // 0 = pas encore, 1 = ok, -1 = refuse (publie)

void ensure_fbo(int w, int h) {
  if (g_fbo && g_w == w && g_h == h) {
    return;
  }
  if (g_fbo) {
    glFinish();  // meme classe de danger que free_targets : Adreno execute en differe
    glDeleteFramebuffers(1, &g_fbo);
    glDeleteTextures(1, &g_depth_tex);
    g_fbo = 0;
    g_depth_tex = 0;
  }
  g_w = w;
  g_h = h;
  glGenTextures(1, &g_depth_tex);
  glBindTexture(GL_TEXTURE_2D, g_depth_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH24_STENCIL8, w, h, 0, GL_DEPTH_STENCIL,
               GL_UNSIGNED_INT_24_8, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_NONE);
  glGenFramebuffers(1, &g_fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_TEXTURE_2D, g_depth_tex,
                         0);
  // Profondeur seule : meme idiome que le FBO de la carte d'ombre soleil (background_common).
  GLenum none = GL_NONE;
  glDrawBuffers(1, &none);
  glReadBuffer(GL_NONE);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    lg::error("[lighting-ao-indirect] FBO de prepasse incomplet ({}x{})", w, h);
  }
}

void ensure_white() {
  if (g_white_tex) {
    return;
  }
  glGenTextures(1, &g_white_tex);
  glBindTexture(GL_TEXTURE_2D, g_white_tex);
  const uint8_t px = 255;
  glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, 1, 1, 0, GL_RED, GL_UNSIGNED_BYTE, &px);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
}

bool is_world_bucket(int id) {
  using B = jak1::BucketId;
  switch ((B)id) {
    case B::TFRAG_LEVEL0:
    case B::TFRAG_NEAR_LEVEL0:
    case B::TIE_NEAR_LEVEL0:
    case B::TIE_LEVEL0:
    case B::TFRAG_LEVEL1:
    case B::TFRAG_NEAR_LEVEL1:
    case B::TIE_NEAR_LEVEL1:
    case B::TIE_LEVEL1:
    case B::SHRUB_NORMAL_LEVEL0:
    case B::SHRUB_BILLBOARD_LEVEL0:
    case B::SHRUB_TRANS_LEVEL0:
    case B::SHRUB_NORMAL_LEVEL1:
    case B::SHRUB_BILLBOARD_LEVEL1:
    case B::SHRUB_TRANS_LEVEL1:
      return true;
    default:
      return false;
  }
}

#ifndef __ANDROID__
void publish_all() {
  autoport_proof::publish("ao_direct_leak_px", g_leak_px);
  autoport_proof::publish("ao_hit_px", g_hit_px);
  autoport_proof::publish("ao_probe_px", g_probe_px);
  autoport_proof::publish("ao_probe_frames", g_probe_frames);
  autoport_proof::publish("ao_leak_excluded_px", g_excluded_px);
  autoport_proof::publish("ao_probe_unmarked_px", g_unmarked_px);
  autoport_proof::publish("ao_prepass_indices", g_last_indices);
  autoport_proof::publish("ao_prepass_levels", (uint64_t)g_last_levels);
  autoport_proof::publish("ao_screen_ao_active", g_ao_valid ? 1 : 0);
  autoport_proof::publish_text("ao_apply_site", "shade.glsl:shade_body");
}
#endif

}  // namespace

// ------------------------------------------------------------------------- contributeurs ----
DepthContributor::DepthContributor() {
  g_contributors.push_back(this);
}

DepthContributor::~DepthContributor() {
  g_contributors.erase(std::remove(g_contributors.begin(), g_contributors.end(), this),
                       g_contributors.end());
}

// ------------------------------------------------------------------------------- module ----
void init_shaders(ShaderLibrary& shaders) {
  g_shaders = &shaders;
  g_ao.init_shaders(shaders);
}

AmbientOcclusionPass& ao_pass() {
  return g_ao;
}

void set_output_hint(int w, int h) {
  g_ao.set_output_hint(w, h);
}

void frame_begin(SharedRenderState* /*rs*/) {
  g_frame++;
  g_frame_ran = false;
  g_ao_valid = false;
  g_probe_frame = autoport_proof::feature_is(kItemId) && (g_frame % kProbeEvery) == 0;
}

bool screen_ao_active() {
  return g_ao_valid && g_ao.texture() != 0;
}

GLuint screen_ao_texture() {
  return screen_ao_active() ? g_ao.texture() : 0;
}

void on_first_camera(SharedRenderState* rs, const GoalBackgroundCameraData& cam) {
  if (g_frame_ran) {
    return;
  }
  g_frame_ran = true;
  g_last_indices = 0;
  g_last_levels = 0;
  if (!rs || rs->version != GameVersion::Jak1 || !g_shaders) {
    return;
  }
  if (AmbientOcclusionPass::effective_mode() == 0) {
    return;  // AO eteinte : ni prepasse ni estimation — OFF == absence
  }
  // Le bras `--off` du harnais : l'item entier s'efface (prepasse comprise), hits reste a 0.
  if (!autoport_proof::armed_for(kItemId)) {
    return;
  }
  const int w = rs->render_fb_w;
  const int h = rs->render_fb_h;
  if (w <= 0 || h <= 0) {
    return;
  }

  // ---- sauvegarde de l'etat GL : on tourne au milieu du render() d'un renderer de decor ----
  GLint prev_program = 0, prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0}, prev_depth_func = GL_LEQUAL;
  GLint prev_vao = 0;
  const GLboolean prev_scissor = glIsEnabled(GL_SCISSOR_TEST);
  const GLboolean prev_cull = glIsEnabled(GL_CULL_FACE);
  const GLboolean prev_blend = glIsEnabled(GL_BLEND);
  const GLboolean prev_stencil = glIsEnabled(GL_STENCIL_TEST);
  const GLboolean prev_poly_off = glIsEnabled(GL_POLYGON_OFFSET_FILL);
  const GLboolean prev_depth_test = glIsEnabled(GL_DEPTH_TEST);
  GLboolean prev_depth_mask = GL_TRUE;
  GLboolean prev_color_mask[4] = {GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE};
  GLint prev_active_tex = GL_TEXTURE0;
  glGetIntegerv(GL_CURRENT_PROGRAM, &prev_program);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prev_fbo);
  glGetIntegerv(GL_VIEWPORT, prev_vp);
  glGetIntegerv(GL_DEPTH_FUNC, &prev_depth_func);
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prev_vao);
  glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);
  glGetBooleanv(GL_COLOR_WRITEMASK, prev_color_mask);
  glGetIntegerv(GL_ACTIVE_TEXTURE, &prev_active_tex);
  glActiveTexture(GL_TEXTURE0);
  GLint prev_tex0 = 0;
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex0);

  ensure_fbo(w, h);
  ensure_white();

  glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
  // Le viewport COURANT : celui de la scene 3D (0,0,render_fb_w,render_fb_h sur les deux
  // plateformes). La profondeur doit tomber sous le meme gl_FragCoord que la passe principale.
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
  glDisable(GL_SCISSOR_TEST);
  glDisable(GL_CULL_FACE);
  glDisable(GL_BLEND);
  glDisable(GL_STENCIL_TEST);
  glDisable(GL_POLYGON_OFFSET_FILL);
  glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);
  glEnable(GL_DEPTH_TEST);
  glDepthMask(GL_TRUE);
  // Convention PS2 inversee, la meme que le FBO de rendu : efface a 0 (le plus loin), GEQUAL.
  glDepthFunc(GL_GEQUAL);
  glClearDepthf(0.0f);
  glClear(GL_DEPTH_BUFFER_BIT);

  const auto& sh = (*g_shaders)[ShaderId::PREPASS_WORLD];
  sh.activate();
  const GLuint id = sh.id();
  const auto newcam = make_new_cam_mat(cam.rot, cam.perspective, cam.fog.x(), cam.hvdf_off.z());
  glUniformMatrix4fv(glGetUniformLocation(id, "pc_camera"), 1, GL_FALSE, newcam[0].data());
  glUniform4f(glGetUniformLocation(id, "cam_trans"), cam.trans[0], cam.trans[1], cam.trans[2],
              cam.trans[3]);

  // Un contributeur par (renderer, niveau) : plusieurs instances d'un renderer (un bucket par
  // categorie) cachent le meme niveau ; la premiere qui le nomme dessine, les autres se taisent.
  std::unordered_set<std::string> seen;
  uint64_t total = 0;
  for (DepthContributor* c : g_contributors) {
    const std::string& level = c->prepass_level_name();
    if (level.empty()) {
      continue;
    }
    std::string key = c->prepass_kind();
    key += ':';
    key += level;
    if (!seen.insert(key).second) {
      continue;
    }
    total += c->draw_depth_prepass(rs);
  }
  g_last_indices = total;
  g_last_levels = (int)seen.size();

  // ---- restauration ----
  glBindVertexArray((GLuint)prev_vao);
  glUseProgram((GLuint)prev_program);
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
  glColorMask(prev_color_mask[0], prev_color_mask[1], prev_color_mask[2], prev_color_mask[3]);
  if (prev_scissor) {
    glEnable(GL_SCISSOR_TEST);
  }
  if (prev_cull) {
    glEnable(GL_CULL_FACE);
  }
  if (prev_blend) {
    glEnable(GL_BLEND);
  }
  if (prev_stencil) {
    glEnable(GL_STENCIL_TEST);
  }
  if (prev_poly_off) {
    glEnable(GL_POLYGON_OFFSET_FILL);
  }
  if (!prev_depth_test) {
    glDisable(GL_DEPTH_TEST);
  }
  glDepthMask(prev_depth_mask);
  glDepthFunc((GLenum)prev_depth_func);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, (GLuint)prev_tex0);
  glActiveTexture((GLenum)prev_active_tex);

  // L'estimation lit la profondeur de la prepasse et ecrit sa texture R8. Elle sauvegarde et
  // restaure elle-meme tout ce qu'elle touche ; le FBO de rendu est deja re-lie.
  g_ao_valid = (total > 0) && g_ao.estimate(rs, g_depth_tex, w, h);
}

void bind_screen_ao(GLuint program, SharedRenderState* rs) {
  const bool on = screen_ao_active();
  const int w = rs ? rs->render_fb_w : 0;
  const int h = rs ? rs->render_fb_h : 0;
  ensure_white();
  glUniform1i(glGetUniformLocation(program, "tex_screen_ao"), 8);
  // 0 = pas d'AO, 1 = appliquee a l'indirect, 2 = vue de debug (AO_DEBUG / debug.opengoal.ao.debug)
  const int mode = !on ? 0 : (AmbientOcclusionPass::effective_debug() != 0 ? 2 : 1);
  glUniform1i(glGetUniformLocation(program, "u_screen_ao_on"), mode);
  glUniform2f(glGetUniformLocation(program, "u_screen_ao_inv_size"), w > 0 ? 1.0f / (float)w : 0.f,
              h > 0 ? 1.0f / (float)h : 0.f);
  glUniform1i(glGetUniformLocation(program, "u_ao_proof"), g_probe_frame ? 1 : 0);
  glActiveTexture(GL_TEXTURE8);
  glBindTexture(GL_TEXTURE_2D, on ? g_ao.texture() : g_white_tex);
  glActiveTexture(GL_TEXTURE0);
}

// ------------------------------------------------------------------------------- preuve ----
void proof_before_bucket(int bucket_id) {
  if (!g_probe_frame || bucket_id > 30) {
    return;
  }
  // Les buckets monde ecrivent 1, tout le reste (ciel, ocean, merc, generic) ecrit 0 : au
  // bucket 30, stencil == 1 designe exactement les pixels dont la couleur finale vient d'un
  // programme qui passe par shade(). Aucun renderer d'avant le bucket 30 ne touche au stencil.
  glEnable(GL_STENCIL_TEST);
  glStencilMask(0xFF);
  glStencilFunc(GL_ALWAYS, is_world_bucket(bucket_id) ? 1 : 0, 0xFF);
  glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);
}

#ifndef __ANDROID__
namespace {

void ensure_probe(int w, int h) {
  if (g_probe_fbo && g_probe_w == w && g_probe_h == h) {
    return;
  }
  if (g_probe_fbo) {
    glDeleteFramebuffers(1, &g_probe_fbo);
    glDeleteRenderbuffers(1, &g_probe_color);
    glDeleteRenderbuffers(1, &g_probe_ds);
    g_probe_fbo = 0;
  }
  g_probe_w = w;
  g_probe_h = h;
  glGenRenderbuffers(1, &g_probe_color);
  glBindRenderbuffer(GL_RENDERBUFFER, g_probe_color);
  glRenderbufferStorage(GL_RENDERBUFFER, GL_RGBA16F, w, h);
  glGenRenderbuffers(1, &g_probe_ds);
  glBindRenderbuffer(GL_RENDERBUFFER, g_probe_ds);
  glRenderbufferStorage(GL_RENDERBUFFER, GL_DEPTH24_STENCIL8, w, h);
  glGenFramebuffers(1, &g_probe_fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, g_probe_fbo);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_RENDERBUFFER, g_probe_color);
  glFramebufferRenderbuffer(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_RENDERBUFFER,
                            g_probe_ds);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    lg::error("[lighting-ao-indirect] FBO de sonde incomplet ({}x{})", w, h);
    g_probe_state = -1;
  } else {
    g_probe_state = 1;
  }
}

}  // namespace
#endif

void proof_post_opaque(SharedRenderState* rs) {
  if (!g_probe_frame) {
    return;
  }
  // Fin du marquage : le stencil est rendu a zero et eteint pour les buckets d'apres (SHADOW=47
  // compte sur un stencil nul). Le clear honore le scissor, on le coupe le temps du clear.
  auto clear_stencil = [] {
    const GLboolean had_scissor = glIsEnabled(GL_SCISSOR_TEST);
    if (had_scissor) {
      glDisable(GL_SCISSOR_TEST);
    }
    glStencilMask(0xFF);
    glClear(GL_STENCIL_BUFFER_BIT);
    glDisable(GL_STENCIL_TEST);
    if (had_scissor) {
      glEnable(GL_SCISSOR_TEST);
    }
  };
  const int w = rs ? rs->render_fb_w : 0;
  const int h = rs ? rs->render_fb_h : 0;
  if (!rs || w <= 0 || h <= 0 || (size_t)w * h > 3840u * 2160u) {
    clear_stencil();
    return;
  }
#ifdef __ANDROID__
  // GLES 3.2 ne sait pas relire le stencil par glReadPixels : l'instrument est bureau-seul,
  // et il le dit au lieu de publier un zero.
  autoport_proof::publish("ao_probe_unsupported", 1);
  clear_stencil();
  return;
#else
  ensure_probe(w, h);
  if (g_probe_state != 1) {
    autoport_proof::publish("ao_probe_unsupported", 1);
    clear_stencil();
    return;
  }
  while (glGetError() != GL_NO_ERROR) {
  }
  GLint prev_read = 0, prev_draw = 0;
  glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &prev_read);
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prev_draw);
  // Un blit a taille identique : copie simple ou resolution MSAA, et il emporte le stencil
  // (memes formats DEPTH24_STENCIL8 des deux cotes).
  glBindFramebuffer(GL_READ_FRAMEBUFFER, rs->render_fb);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, g_probe_fbo);
  glBlitFramebuffer(0, 0, w, h, 0, 0, w, h, GL_COLOR_BUFFER_BIT | GL_STENCIL_BUFFER_BIT,
                    GL_NEAREST);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, g_probe_fbo);
  std::vector<float> px((size_t)w * h * 4);
  std::vector<uint8_t> st((size_t)w * h);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glReadPixels(0, 0, w, h, GL_RGBA, GL_FLOAT, px.data());
  glReadPixels(0, 0, w, h, GL_STENCIL_INDEX, GL_UNSIGNED_BYTE, st.data());
  const GLenum err = glGetError();
  glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)prev_read);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, (GLuint)prev_draw);
  if (err != GL_NO_ERROR) {
    lg::error("[lighting-ao-indirect] relecture de la sonde refusee (gl=0x{:x})", (unsigned)err);
    g_probe_state = -1;
    autoport_proof::publish("ao_probe_unsupported", 1);
    clear_stencil();
    return;
  }
  uint64_t hits = 0, leak = 0, excl = 0, marked = 0, unmarked = 0;
  for (size_t i = 0; i < st.size(); i++) {
    if (st[i] != 1) {
      unmarked++;
      continue;
    }
    marked++;
    const float* p = &px[i * 4];
    // Drapeaux ecrits par shade() en mode preuve : R = fuite sur le direct, G = l'indirect a
    // recu l'AO, B = chemin exclu de la porte (B/C/E : son indirect n'est pas `base`).
    if (p[2] > 0.5f) {
      excl++;
    } else if (p[0] > 0.5f) {
      leak++;
    }
    if (p[1] > 0.5f) {
      hits++;
    }
  }
  g_probe_frames++;
  g_probe_px += marked;
  g_unmarked_px += unmarked;
  g_leak_px += leak;
  g_excluded_px += excl;
  g_hit_px += hits;
  autoport_proof::note_hit(hits);
  publish_all();
  clear_stencil();
#endif
}

}  // namespace prepass
