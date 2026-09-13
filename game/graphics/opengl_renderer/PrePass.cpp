#include "PrePass.h"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <unordered_set>
#include <vector>

#include "common/log/log.h"

#include "game/graphics/gfx.h"
#include "game/graphics/gl_query_census.h"
#include "game/graphics/opengl_renderer/AmbientOcclusion.h"
#include "game/graphics/opengl_renderer/background/background_common.h"
#include "game/graphics/opengl_renderer/buckets.h"
#include "game/graphics/opengl_renderer/lighting_census.h"
#include "game/system/autoport_proof.h"
#include "game/graphics/opengl_renderer/gl_uniform_cache.h"

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
AUTOPORT_FEATURE_SITE(kItemId);
// Une image sondee sur N sous mesure : la relecture couleur + stencil pleine resolution coute
// une synchronisation GPU, on ne la paie pas a chaque image.
constexpr uint64_t kProbeEvery = 30;  // 12 etats de recensement a couvrir (etait 60 pour 3)

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

// ── L'ALPHA-TEST DU FEUILLAGE, ET LE DETECTEUR QUI LE JUGE ────────────────────────────────────
// Refus owner du 2026-09-10 (b). L'etat memoise des plages (le programme garde ses uniformes
// entre deux draws, mais pas entre deux passes : tout ceci est remis a une valeur IMPOSSIBLE au
// debut de chaque passe, sinon un uniforme non repose se croit pose).
bool g_cut_armed = true;  // faux = bras de CONTROLE : la decoupe est desarmee, rien d'autre ne bouge
float g_last_aref = -1.f;
float g_last_amb = -1.f;
GLuint g_last_tex = 0xffffffffu;
bool g_cut_uniforms_ok = false;  // les quatre uniformes de la decoupe existent dans le programme
uint64_t g_cut_ranges = 0;    // plages qui portent un test d'alpha
uint64_t g_total_ranges = 0;  // toutes les plages — son denominateur

// La classification : un FBO couleur RGBA8 qui PARTAGE la profondeur de la prepasse. Bureau
// seulement — l'item se prouve sur x86 et une relecture par image n'a rien a faire sur
// l'appareil. Ce qui suit n'existe donc pas dans le .so arm64 : ce n'est pas un drapeau a zero,
// c'est du code qui n'est pas COMPILE.
#ifndef __ANDROID__
GLuint g_class_fbo = 0, g_class_tex = 0;
int g_class_w = 0, g_class_h = 0;
GLuint g_class_depth_src = 0;
int g_class_state = 0;  // 0 = pas encore, 1 = ok, -1 = refuse (publie)
#endif

uint64_t g_alpha_frames = 0;
uint64_t g_on_alpha_px = 0;       // bras LIVRE : le gagnant est sous le seuil -> doit valoir 0
uint64_t g_alpha_cover_px = 0;    // bras LIVRE : pixels gagnes par la prepasse — le denominateur
uint64_t g_alpha_fringe_px = 0;   // bras LIVRE : gagnants dans la bande ambigue (voir le .frag)
uint64_t g_witness_px = 0;        // bras CONTROLE : le meme detecteur, decoupe desarmee -> > 0
uint64_t g_witness_cover_px = 0;  // bras CONTROLE : son propre denominateur

// lighting-ao-indirect (c)/(g) : les plages ECARTEES de la prepasse — les draws que la passe
// principale dessine SANS ecrire la profondeur. Recensees au CHARGEMENT par les contributeurs,
// rejouees par `measure_phantom_occluders` quand `g_noz_pass` est vrai.
bool g_noz_pass = false;
uint64_t g_noz_ranges = 0, g_noz_inds = 0;
uint64_t g_phantom_px = 0, g_phantom_cover_px = 0;
int g_phantom_state = 0;  // 0 = pas encore mesure, 1 = mesure, -1 = non supporte

// Preuve.
bool g_probe_frame = false;
uint64_t g_probe_seq = 0;  // combien d'images sondees ont commence — choisit le palier d'AO
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
  gl_query_census::Armed _ap("prepass-ensure-fbo");
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

// ── LA PASSE, ET SON DETECTEUR ────────────────────────────────────────────────────────────────
// Un passage de prepasse = poser l'etat, dessiner TOUTES les plages de TOUS les contributeurs,
// restaurer. Il est appele deux fois sur une image sondee : une fois pour de vrai (decoupe
// ARMEE, c'est cette profondeur que l'estimateur d'AO consomme), une fois en CONTROLE (decoupe
// DESARMEE). Le detecteur qui les juge est le MEME, et c'est le bras desarme qui prouve qu'il
// sait rendre autre chose que zero : sans lui, `ao_on_alpha_px = 0` serait un vert par inaction.

// Le FBO de classification : une couleur RGBA8 a nous, et LA PROFONDEUR DE LA PREPASSE, partagee.
// C'est ce partage qui rend le test possible : en GL_EQUAL, seul le fragment qui a GAGNE la
// profondeur repasse, donc la couleur relue decrit le fragment que l'estimateur d'AO a vu.
#ifndef __ANDROID__
void ensure_class(int w, int h) {
  if (g_class_fbo && g_class_w == w && g_class_h == h && g_class_depth_src == g_depth_tex) {
    return;
  }
  if (g_class_fbo) {
    glFinish();
    glDeleteFramebuffers(1, &g_class_fbo);
    glDeleteTextures(1, &g_class_tex);
    g_class_fbo = 0;
    g_class_tex = 0;
  }
  g_class_w = w;
  g_class_h = h;
  g_class_depth_src = g_depth_tex;
  glGenTextures(1, &g_class_tex);
  glBindTexture(GL_TEXTURE_2D, g_class_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glGenFramebuffers(1, &g_class_fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, g_class_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, g_class_tex, 0);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_STENCIL_ATTACHMENT, GL_TEXTURE_2D, g_depth_tex, 0);
  GLenum bufs[1] = {GL_COLOR_ATTACHMENT0};
  glDrawBuffers(1, bufs);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    lg::error("[lighting-ao-indirect] FBO de classification incomplet ({}x{})", w, h);
    g_class_state = -1;
  } else {
    g_class_state = 1;
  }
}
#endif

// Dessine toutes les plages de tous les contributeurs. Un contributeur par (renderer, niveau) :
// plusieurs instances d'un renderer (un bucket par categorie) cachent le meme niveau ; la
// premiere qui le nomme dessine, les autres se taisent.
uint64_t draw_all_contributors(SharedRenderState* rs, int* out_levels) {
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
  if (out_levels) {
    *out_levels = (int)seen.size();
  }
  return total;
}

// Remet a une valeur IMPOSSIBLE l'etat memoise par `draw_depth_range`.
void forget_range_state() {
  g_last_aref = -2.f;
  g_last_amb = -2.f;
  g_last_tex = 0xffffffffu;
}

#ifndef __ANDROID__
// Rejoue les MEMES plages en GL_EQUAL contre la profondeur qui vient d'etre ecrite, sans aucun
// discard, et relit la classification du fragment GAGNANT de chaque pixel :
//   R = il est sous le seuil d'alpha      G = il a gagne (denominateur)      B = bande ambigue
// La decoupe du detecteur est TOUJOURS armee : c'est la profondeur d'entree qui distingue les
// deux bras, pas le predicat.
void run_classification(SharedRenderState* rs, int w, int h, uint64_t* on, uint64_t* cover,
                        uint64_t* fringe) {
  ensure_class(w, h);
  if (g_class_state != 1 || !g_shaders) {
    return;
  }
  while (glGetError() != GL_NO_ERROR) {
  }
  const GLuint id = (*g_shaders)[ShaderId::PREPASS_WORLD].id();
  glBindFramebuffer(GL_FRAMEBUFFER, g_class_fbo);
  glViewport(0, 0, w, h);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  GLfloat prev_clear[4] = {0.f, 0.f, 0.f, 0.f};
  glGetFloatv(GL_COLOR_CLEAR_VALUE, prev_clear);
  glClearColor(0.f, 0.f, 0.f, 0.f);
  glClear(GL_COLOR_BUFFER_BIT);
  glClearColor(prev_clear[0], prev_clear[1], prev_clear[2], prev_clear[3]);
  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_EQUAL);
  glDepthMask(GL_FALSE);
  glUniform1i(glu::loc(id, "u_cut_mode"), 1);
  const bool saved_armed = g_cut_armed;
  g_cut_armed = true;
  forget_range_state();
  draw_all_contributors(rs, nullptr);
  g_cut_armed = saved_armed;
  glUniform1i(glu::loc(id, "u_cut_mode"), 0);

  std::vector<uint8_t> px((size_t)w * h * 4);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, g_class_fbo);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
  const GLenum err = glGetError();
  if (err != GL_NO_ERROR) {
    lg::error("[lighting-ao-indirect] relecture de la classification refusee (gl=0x{:x})",
              (unsigned)err);
    g_class_state = -1;
    return;
  }
  for (size_t i = 0; i < px.size(); i += 4) {
    if (px[i + 1] < 128) {
      continue;  // aucun fragment de la prepasse n'a gagne ce pixel
    }
    (*cover)++;
    if (px[i] >= 128) {
      (*on)++;
    } else if (px[i + 2] >= 128) {
      (*fringe)++;
    }
  }
}
#endif

// LE passage. `armed` = la decoupe d'alpha est active (le chemin LIVRE). `classify` = enchaine
// la passe de classification et range ses comptes dans les trois sorties.
uint64_t run_prepass(SharedRenderState* rs,
                     const GoalBackgroundCameraData& cam,
                     int w,
                     int h,
                     bool armed,
                     bool classify,
                     uint64_t* on,
                     uint64_t* cover,
                     uint64_t* fringe,
                     int* out_levels) {
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
  glUniformMatrix4fv(glu::loc(id, "pc_camera"), 1, GL_FALSE, newcam[0].data());
  glUniform4f(glu::loc(id, "cam_trans"), cam.trans[0], cam.trans[1], cam.trans[2],
              cam.trans[3]);
  glUniform1i(glu::loc(id, "tex_T0"), 0);
  glUniform1i(glu::loc(id, "u_cut_mode"), 0);
  // Un uniforme DECLARE mais jamais lu est RETIRE par le compilateur GLSL, et `glu::loc` rend
  // alors -1 : la decoupe serait muette sans qu'une seule erreur ne sorte. On demande au pilote,
  // et on le publie — c'est la seule facon de savoir qui lit.
  g_cut_uniforms_ok = (glu::loc(id, "u_cut_aref") != -1) && (glu::loc(id, "u_cut_amb") != -1) &&
                      (glu::loc(id, "u_cut_mode") != -1) && (glu::loc(id, "tex_T0") != -1);

  g_cut_armed = armed;
  forget_range_state();
  const uint64_t total = draw_all_contributors(rs, out_levels);
  g_cut_armed = true;

#ifndef __ANDROID__
  if (classify && on && cover && fringe) {
    run_classification(rs, w, h, on, cover, fringe);
  }
#else
  (void)classify;
  (void)on;
  (void)cover;
  (void)fringe;
#endif

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
  return total;
}

// lighting-ao-indirect, verdict (c) de l'owner : « publier ce qui est mesure AU POINT DE DESSIN
// du brin d'herbe, pas a l'entree de l'estimateur ». On rejoue les plages ECARTEES — les quads
// de feuillage que la passe principale dessine SANS ecrire la profondeur — contre la
// profondeur LIVREE de la prepasse, en GL_GREATER (convention PS2 : plus grand = plus pres) et
// sans jamais ecrire. La requete d'occlusion rend le nombre EXACT de pixels ou ce quad se
// serait pose DEVANT la geometrie reelle : c'est la population que l'owner voit s'assombrir.
// `ao_phantom_cover_px` est la meme geometrie sans test : le denominateur.
void measure_phantom_occluders(SharedRenderState* rs,
                               const GoalBackgroundCameraData& cam,
                               int w,
                               int h) {
#ifdef __ANDROID__
  // GLES 3 n'a pas GL_SAMPLES_PASSED (seulement GL_ANY_SAMPLES_PASSED, un booleen) : la mesure
  // n'existe pas dans le .so arm64 — ce n'est pas un drapeau a zero, c'est du code non COMPILE.
  (void)rs;
  (void)cam;
  (void)w;
  (void)h;
  g_phantom_state = -1;
#else
  if (!g_shaders || !g_fbo) {
    return;
  }
  // `run_prepass` a deja TOUT restaure en sortant : on refait ici exactement son installation
  // (meme FBO, meme viewport, meme programme, memes uniformes), sans jamais effacer la
  // profondeur qu'elle vient d'ecrire.
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

  glBindFramebuffer(GL_FRAMEBUFFER, g_fbo);
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
  glDisable(GL_SCISSOR_TEST);
  glDisable(GL_CULL_FACE);
  glDisable(GL_BLEND);
  glDisable(GL_STENCIL_TEST);
  glDisable(GL_POLYGON_OFFSET_FILL);
  glEnable(GL_DEPTH_TEST);

  const auto& sh = (*g_shaders)[ShaderId::PREPASS_WORLD];
  sh.activate();
  const GLuint id = sh.id();
  const auto newcam = make_new_cam_mat(cam.rot, cam.perspective, cam.fog.x(), cam.hvdf_off.z());
  glUniformMatrix4fv(glu::loc(id, "pc_camera"), 1, GL_FALSE, newcam[0].data());
  glUniform4f(glu::loc(id, "cam_trans"), cam.trans[0], cam.trans[1], cam.trans[2], cam.trans[3]);
  glUniform1i(glu::loc(id, "tex_T0"), 0);
  glUniform1i(glu::loc(id, "u_cut_mode"), 0);

  glDepthMask(GL_FALSE);
  glDepthFunc(GL_GREATER);
  glColorMask(GL_FALSE, GL_FALSE, GL_FALSE, GL_FALSE);

  GLuint q[2] = {0, 0};
  glGenQueries(2, q);
  g_cut_armed = true;
  g_noz_pass = true;
  forget_range_state();
  glBeginQuery(GL_SAMPLES_PASSED, q[0]);
  draw_all_contributors(rs, nullptr);
  glEndQuery(GL_SAMPLES_PASSED);

  glDepthFunc(GL_ALWAYS);
  forget_range_state();
  glBeginQuery(GL_SAMPLES_PASSED, q[1]);
  draw_all_contributors(rs, nullptr);
  glEndQuery(GL_SAMPLES_PASSED);
  g_noz_pass = false;

  GLuint hit = 0, cover = 0;
  glGetQueryObjectuiv(q[0], GL_QUERY_RESULT, &hit);
  glGetQueryObjectuiv(q[1], GL_QUERY_RESULT, &cover);
  g_phantom_px += hit;
  g_phantom_cover_px += cover;
  glDeleteQueries(2, q);
  g_phantom_state = 1;

  // ---- restauration : exactement l'etat dans lequel `run_prepass` laisse GL ----
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
#endif
}

#ifndef __ANDROID__
void publish_all() {
  autoport_proof::publish("ao_direct_leak_px", g_leak_px);
  autoport_proof::publish("ao_hit_px", g_hit_px);
  autoport_proof::publish("ao_probe_px", g_probe_px);
  // ── (c)/(g) L'OCCLUDER FANTOME ──────────────────────────────────────────────────────────
  // `ao_noz_ranges` / `ao_noz_inds` : ce que la prepasse ECARTE desormais (draws sans z-write).
  // `ao_phantom_px` : les pixels ou ces quads se seraient poses DEVANT la geometrie reelle —
  // la population qui s'assombrissait. `ao_phantom_cover_px` est son denominateur (meme
  // geometrie, sans test de profondeur). `ao_phantom_state` : 0 pas mesure, 1 mesure, 2 non
  // supporte (GLES).
  autoport_proof::publish("ao_noz_ranges", g_noz_ranges);
  autoport_proof::publish("ao_noz_inds", g_noz_inds);
  autoport_proof::publish("ao_phantom_px", g_phantom_px);
  autoport_proof::publish("ao_phantom_cover_px", g_phantom_cover_px);
  autoport_proof::publish("ao_phantom_state", (uint64_t)(g_phantom_state < 0 ? 2 : g_phantom_state));
  autoport_proof::publish("ao_probe_frames", g_probe_frames);
  autoport_proof::publish("ao_leak_excluded_px", g_excluded_px);
  autoport_proof::publish("ao_probe_unmarked_px", g_unmarked_px);
  autoport_proof::publish("ao_prepass_indices", g_last_indices);
  autoport_proof::publish("ao_prepass_levels", (uint64_t)g_last_levels);
  autoport_proof::publish("ao_screen_ao_active", g_ao_valid ? 1 : 0);
  autoport_proof::publish_text("ao_apply_site", "shade.glsl:shade_body");
  // ── (b) L'ALPHA EST RESPECTE ────────────────────────────────────────────────────────────
  // `ao_on_alpha_px` est LA grandeur que le livrable demande : le nombre de pixels dont le
  // fragment que l'estimateur d'AO a vu est un texel sous le seuil d'alpha. Il vaut 0.
  // `ao_alpha_witness_px` est le MEME detecteur sur le MEME contenu, la decoupe desarmee : il
  // est non nul, et c'est lui qui interdit de lire le 0 d'a cote comme un vert par inaction.
  // `ao_alpha_cover_px` / `ao_alpha_witness_cover_px` sont leurs denominateurs.
  // `ao_alpha_fringe_px` compte la bande que le seuil CONSERVATEUR laisse passer (voir
  // prepass_world.frag) : il dit ce que la borne tod.a <= 1 coute reellement.
  autoport_proof::publish("ao_on_alpha_px", g_on_alpha_px);
  autoport_proof::publish("ao_alpha_witness_px", g_witness_px);
  autoport_proof::publish("ao_alpha_cover_px", g_alpha_cover_px);
  autoport_proof::publish("ao_alpha_witness_cover_px", g_witness_cover_px);
  autoport_proof::publish("ao_alpha_fringe_px", g_alpha_fringe_px);
  autoport_proof::publish("ao_alpha_frames", g_alpha_frames);
  // Combien de plages de la prepasse portent un test d'alpha, et sur combien : si ce rapport
  // etait nul, tout le reste serait vide de sens.
  autoport_proof::publish("ao_cut_ranges", g_cut_ranges);
  autoport_proof::publish("ao_total_ranges", g_total_ranges);
  autoport_proof::publish("ao_cut_uniforms_ok", g_cut_uniforms_ok ? 1 : 0);
  // ── (a) AUCUN MOTIF VISIBLE ─────────────────────────────────────────────────────────────
  AmbientOcclusionPass::publish_pattern_census();
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
  // lighting-ao-indirect, verdict (f) : la campagne de cout avance ICI, au debut de l'image,
  // avant que quoi que ce soit d'autre ne lise le mode ou le palier d'AO. Elle mesure un ECART
  // debut-d'image a debut-d'image ; une image SONDEE porte deux relectures et une passe de
  // classification, elle n'a rien a faire dans un releve de temps. D'ou l'ordre : la campagne
  // parle d'abord, la sonde se tait pendant qu'elle tient la parole.
  AmbientOcclusionPass::measure_frame_begin(g_frame);
  g_frame_ran = false;
  g_ao_valid = false;
  g_probe_frame = autoport_proof::feature_is(kItemId) && (g_frame % kProbeEvery) == 0 &&
                  !AmbientOcclusionPass::measure_timing_active();
  if (g_probe_frame) {
    g_probe_seq++;
  }
}

// ── LES PLAGES DE LA PREPASSE ─────────────────────────────────────────────────────────────────
DepthRange make_depth_range(uint32_t gl_tex, float alpha_min, uint32_t first, uint32_t count) {
  DepthRange r;
  r.first = first;
  r.count = count;
  if (gl_tex != 0 && alpha_min > 0.f) {
    r.tex = gl_tex;
    // LA BORNE, ET ELLE EST PROUVEE, PAS SUPPOSEE. La passe principale jette quand
    // `fragment_color.a * T0.a < alpha_min`, avec `fragment_color.a = tod.a * 4`
    // (tfrag3.vert:92-95, shrub.vert:112-119) ; la prepasse n'a pas l'indice de temps-du-jour.
    // Mais l'alpha de la LUT est SATURE A 128, pas a 255, la ou elle est produite :
    // `o[3] = std::min(128, temp[color][3] >> 6)` (background_common.cpp, interp_time_of_day_slow)
    // et le registre `sat = _mm_set_epi16(128, 255, 255, 255, ...)` de la version SIMD.
    // Donc tod.a <= 128/255 et `fragment_color.a <= 4 * 128/255 = 2.008` : le seuil conservateur
    // le plus SERRE qui existe est alpha_min / 2.008. Le prendre a 4 laissait 6x plus de pixels
    // dans la bande ambigue qu'il n'en retirait (mesure du 12/09 : 49 081 contre 7 824).
    // Ce qui reste dans [alpha_min/2.008, alpha_min) est compte : `ao_alpha_fringe_px`.
    r.cut_aref = alpha_min * (255.f / 512.f);
    r.cut_amb = alpha_min;
  }
  return r;
}

uint64_t draw_depth_range(unsigned gl_mode, const DepthRange& r) {
  if (r.count == 0 || !g_shaders) {
    return 0;
  }
  const GLuint id = (*g_shaders)[ShaderId::PREPASS_WORLD].id();
  // Le bras de CONTROLE desarme la decoupe SANS toucher a rien d'autre : meme geometrie, meme
  // programme, meme ordre, meme plages. C'est la seule difference entre les deux bras.
  const float aref = g_cut_armed ? r.cut_aref : 0.f;
  g_total_ranges++;
  if (r.cut_aref > 0.f) {
    g_cut_ranges++;
  }
  if (aref != g_last_aref) {
    glUniform1f(glu::loc(id, "u_cut_aref"), aref);
    g_last_aref = aref;
  }
  if (r.cut_amb != g_last_amb) {
    glUniform1f(glu::loc(id, "u_cut_amb"), r.cut_amb);
    g_last_amb = r.cut_amb;
  }
  // Un sampler declare et non lie rend un comportement indefini sur Adreno : la plage sans test
  // lie quand meme le 1x1 blanc.
  const GLuint want_tex = (r.cut_aref > 0.f && r.tex != 0) ? (GLuint)r.tex : g_white_tex;
  if (want_tex != g_last_tex) {
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, want_tex);
    g_last_tex = want_tex;
  }
  lighting_census::note_world_draw(lighting_census::Kind::DepthOnly);
  glDrawElements((GLenum)gl_mode, (GLsizei)r.count, GL_UNSIGNED_INT,
                 (void*)((size_t)r.first * sizeof(uint32_t)));
  return r.count;
}

// lighting-ao-indirect (c)/(g) : la passe « occluder fantome ». Hors d'elle, les contributeurs
// dessinent leurs plages LIVREES.
bool noz_pass_active() {
  return g_noz_pass;
}

unsigned depth_fbo() {
  return (unsigned)g_fbo;
}

void note_noz_range(uint32_t inds) {
  g_noz_ranges++;
  g_noz_inds += inds;
}

bool screen_ao_active() {
  return g_ao_valid && g_ao.texture() != 0;
}

GLuint screen_ao_texture() {
  return screen_ao_active() ? g_ao.texture() : 0;
}

void on_first_camera(SharedRenderState* rs, const GoalBackgroundCameraData& cam) {
  gl_query_census::Armed _ap("prepass-first-camera");
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

  // ── LE BRAS LIVRE ───────────────────────────────────────────────────────────────────────────
  // La prepasse avec la decoupe d'alpha ARMEE : c'est CETTE profondeur que l'estimateur d'AO
  // consomme, donc c'est elle que le detecteur juge.
  int levels = 0;
  uint64_t on = 0, cover = 0, fringe = 0;
  const uint64_t total = run_prepass(rs, cam, w, h, /*armed=*/true, g_probe_frame, &on, &cover,
                                     &fringe, &levels);
  g_last_indices = total;
  g_last_levels = levels;
  if (g_probe_frame) {
    g_alpha_frames++;
    g_on_alpha_px += on;
    g_alpha_cover_px += cover;
    g_alpha_fringe_px += fringe;
    // (c)/(g) LA MESURE AU POINT DE DESSIN. La profondeur LIVREE vient d'etre ecrite et
    // l'estimateur ne l'a pas encore lue : c'est ICI que les quads ECARTES se comparent a elle.
    measure_phantom_occluders(rs, cam, w, h);
  }

  // (a) LE RECENSEMENT DU MOTIF. `AO_FORCE_QUALITY` est fige pour toute la course : les trois
  // paliers ne peuvent etre juges dans la MEME scene qu'en les alternant d'une image sondee a
  // l'autre. Le cout — la chaine d'AO se redimensionne a chaque bascule — ne se paie qu'une
  // image sur soixante, et seulement sous mesure.
  // (e) DOUZE ETATS, PAS TROIS. L'owner a vu le damier « en qualite faible, teste en SSAO » ET
  // « en qualite elevee, teste en GTAO » : un recensement qui ne couvre qu'un estimateur ne
  // repond pas a son verdict. Et une grandeur qui ne RETROUVE pas le defaut sur le regime
  // d'AVANT ne peut pas prouver sa disparition : la moitie haute des etats rallume l'ancrage
  // MONDE du bruit (`u_ao_legacy_noise`), dans la MEME course et sur la MEME scene.
  //   etat = legacy*6 + mode_idx*3 + palier,  mode_idx : 0 = SSAO, 1 = GTAO
  if (g_probe_frame) {
    const int st = (int)(g_probe_seq % 12);
    AmbientOcclusionPass::set_measure_state(((st % 6) < 3) ? 1 : 3, st % 3, st / 6);
    AmbientOcclusionPass::request_pattern_census(true);
  } else {
    AmbientOcclusionPass::set_measure_state(-1, -1, 0);
  }

  // L'estimation lit la profondeur de la prepasse et ecrit sa texture R8. Elle sauvegarde et
  // restaure elle-meme tout ce qu'elle touche ; le FBO de rendu est deja re-lie — et il DOIT
  // l'etre, parce que `ao_draws_on_scene` compare ses cibles au FBO qu'elle trouve en entrant.
  g_ao_valid = (total > 0) && g_ao.estimate(rs, g_depth_tex, w, h);

  // ── LE BRAS DE CONTROLE ─────────────────────────────────────────────────────────────────────
  // Le MEME dessin, la decoupe DESARMEE : les texels transparents ecrivent a nouveau de la
  // profondeur, et le MEME detecteur les compte. Sans ce bras, `ao_on_alpha_px = 0` ne se
  // distinguerait pas d'un detecteur casse. Il ecrase la profondeur de la prepasse, ce qui est
  // sans consequence : l'estimation vient de la consommer et personne d'autre ne la lit.
  if (g_probe_frame) {
    uint64_t won = 0, wcover = 0, wfringe = 0;
    run_prepass(rs, cam, w, h, /*armed=*/false, true, &won, &wcover, &wfringe, nullptr);
    g_witness_px += won;
    g_witness_cover_px += wcover;
  }
}

void bind_screen_ao(GLuint program, SharedRenderState* rs) {
  const bool on = screen_ao_active();
  const int w = rs ? rs->render_fb_w : 0;
  const int h = rs ? rs->render_fb_h : 0;
  ensure_white();
  glUniform1i(glu::loc(program, "tex_screen_ao"), 8);
  // 0 = pas d'AO, 1 = appliquee a l'indirect, 2 = vue de debug (AO_DEBUG / debug.opengoal.ao.debug)
  const int mode = !on ? 0 : (AmbientOcclusionPass::effective_debug() != 0 ? 2 : 1);
  glUniform1i(glu::loc(program, "u_screen_ao_on"), mode);
  glUniform2f(glu::loc(program, "u_screen_ao_inv_size"), w > 0 ? 1.0f / (float)w : 0.f,
              h > 0 ? 1.0f / (float)h : 0.f);
  glUniform1i(glu::loc(program, "u_ao_proof"), g_probe_frame ? 1 : 0);
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
  gl_query_census::Armed _ap("prepass-proof");
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
  autoport_proof::note_hit_for(kItemId, hits);
  publish_all();
  clear_stencil();
#endif
}

}  // namespace prepass
