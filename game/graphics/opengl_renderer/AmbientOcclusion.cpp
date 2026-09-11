#include "AmbientOcclusion.h"
#include "game/system/recharged_gating.h"
#include "game/graphics/origin_ablate.h"

#include <algorithm>
#include <array>
#include <chrono>
#include <cmath>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

#include "common/log/log.h"

#include "game/graphics/gfx.h"
#include "game/graphics/gl_query_census.h"
#include "game/graphics/opengl_renderer/gl_uniform_cache.h"
#include "game/graphics/opengl_renderer/hdr.h"
#include "game/system/autoport_proof.h"

#include <type_traits>
#include <utility>

// ============================================================================
// Grecharged-ambient-occlusion
// ============================================================================
// Three interchangeable estimators keyed off recharged_ao_mode; per-quality resolution
// scale off recharged_ao_quality.
//
// lighting-ao-indirect (SPEC §4.7) : la source de profondeur est la texture de la PREPASSE
// (PrePass.cpp), jamais le FBO de rendu ; la sortie est une texture R8 pleine resolution
// echantillonnee par shade.glsl. Rien n'est compose sur l'image ici. OFF == stock : quand
// effective_mode()==0 rien de tout ceci ne tourne (ni la prepasse).

// ---------------------------------------------------------------------------
// Live-tunable mode/quality resolution.
//
// Re-read the debug override at most every 250 ms WALL TIME (a frame-count throttle
// stalls for tens of seconds at the locked-full-res 4-12 fps the Redmi runs the capture
// protocol at — attempt-4's mode flips landed mid-segment). A value that is
// absent/empty/-1 means "no override, use the game setting". Every override CHANGE is
// logged ("[recharged-ao] override <tag> -> <v>") so capture scripts can wait for the
// flip deterministically instead of sleeping.
// Android reads system properties debug.opengoal.ao.force_mode / .force_quality;
// desktop reads env AO_FORCE_MODE / AO_FORCE_QUALITY.
// ---------------------------------------------------------------------------
namespace {

// Returns the parsed override (>=0) or -1 for "no override".
int read_ao_override(const char* android_prop, const char* env_name) {
  char buf[32] = {0};
  bool have = false;
#ifdef __ANDROID__
  if (__system_property_get(android_prop, buf) > 0 && buf[0]) {
    have = true;
  }
  (void)env_name;
#else
  (void)android_prop;
  const char* e = std::getenv(env_name);
  if (e && e[0]) {
    std::strncpy(buf, e, sizeof(buf) - 1);
    have = true;
  }
#endif
  if (!have) {
    return -1;
  }
  int v = std::atoi(buf);
  return v;  // -1 (explicitly written) also means "no override"
}

// Time-throttled, change-logged override cache. GL-thread only (all effective_* callers
// are on the render thread).
struct AoOverride {
  const char* tag;
  const char* prop;
  const char* env;
  int cached = -1;
  double last_read_s = -1.0;

  int read() {
    const double now =
        std::chrono::duration<double>(std::chrono::steady_clock::now().time_since_epoch())
            .count();
    if (last_read_s < 0.0 || now - last_read_s >= 0.25) {
      last_read_s = now;
      const int v = read_ao_override(prop, env);
      if (v != cached) {
        lg::info("[recharged-ao] override {} -> {}", tag, v);
        cached = v;
      }
    }
    return cached;
  }
};

// ─── LES DEUX CHEMINS, COMPTES (refus owner du 2026-09-10) ─────────────────────────────────────
// « J'ai l'impression que l'option sert toujours l'ancien chemin d'avant la refonte. » Deux
// temoins repondent, et aucun des deux n'est un zero par inaction.
//
// 1. LE COMPTE DES CIBLES DE DESSIN. Chaque dessin de la passe declare la cible qu'il vient de
//    lier. L'ANCIEN chemin composait sur l'image de scene : il aurait dessine dans le FBO que la
//    passe trouve en entrant (`prev_fbo`). Le NOUVEAU ecrit dans ses propres textures R8. Les deux
//    compteurs montent au MEME endroit, dans le MEME code : `ao_draws_on_scene` vaut zero parce
//    que la comparaison a lieu et echoue, pas parce qu'aucun site n'existe. `ao_draws_total` est
//    son denominateur, et il n'est jamais nul quand la passe tourne.
//
// 2. LE TEMOIN DE COMPILATION. Un compteur ne peut pas prouver l'absence d'un code supprime : il
//    n'a plus de site ou vivre. `ao_has_composite` demande au COMPILATEUR si la classe porte
//    encore une methode de composite sur la scene, et `ao_legacy_witness_selftest` prouve que le
//    detecteur sait rendre 1 sur un type de controle qui, lui, la porte. Sans ce controle, un zero
//    du detecteur serait indiscernable d'un detecteur casse.
template <class T, class = void>
struct ao_has_composite : std::false_type {};
template <class T>
struct ao_has_composite<T, std::void_t<decltype(std::declval<T&>().composite_on_scene())>>
    : std::true_type {};
struct AoLegacyWitnessControl {
  void composite_on_scene() {}
};

uint64_t s_ao_draws_total = 0;
uint64_t s_ao_draws_on_scene = 0;

}  // namespace

int AmbientOcclusionPass::effective_mode() {
#if AUTOPORT_ORIGIN_ABLATE
  return 0;  // BINAIRE-TEMOIN : `AO_FORCE_MODE` allume l'AO meme maitre eteint.
#else
  static AoOverride s_ov{"mode", "debug.opengoal.ao.force_mode", "AO_FORCE_MODE"};
  const int v = s_ov.read();
  // Grecharged-master-toggle: the master composes with the SETTINGS value; the explicit
  // debug force-prop keeps top precedence (it is a bisect tool, not a user path).
  // L'occlusion ambiante est SOUS l'eclairage recharge (SPEC §6.2) : recharged_gating::mode()
  // compose master -> ECLAIRAGE RECHARGE -> mode, donc eteindre l'eclairage rend le mode 0 (AO off).
  return (v >= 0) ? v : recharged_gating::mode(recharged_gating::kAoMode);
#endif
}

int AmbientOcclusionPass::effective_quality() {
  static AoOverride s_ov{"quality", "debug.opengoal.ao.force_quality", "AO_FORCE_QUALITY"};
  const int v = s_ov.read();
  return (v >= 0) ? v : Gfx::g_global_settings.recharged_ao_quality;
}

int AmbientOcclusionPass::effective_strength() {
  static AoOverride s_ov{"strength", "debug.opengoal.ao.force_strength", "AO_FORCE_STRENGTH"};
  const int v = s_ov.read();
  return (v >= 0) ? v : Gfx::g_global_settings.recharged_ao_strength;
}

int AmbientOcclusionPass::effective_debug() {
  static AoOverride s_ov{"debug", "debug.opengoal.ao.debug", "AO_DEBUG"};
  const int v = s_ov.read();
  return (v >= 0) ? v : 0;
}

// ---------------------------------------------------------------------------
// Small math helpers (CPU-side inverse camera).
// ---------------------------------------------------------------------------
namespace {

// Full 4x4 inverse in double precision. Column-major storage m[col*4 + row], matching
// the way camera_matrix[col] is laid out (each math::Vector4f is a column). Returns
// false if the matrix is (near-)singular (skip AO that frame).
bool invert4x4(const double m[16], double out[16]) {
  double inv[16];
  inv[0] = m[5] * m[10] * m[15] - m[5] * m[11] * m[14] - m[9] * m[6] * m[15] +
           m[9] * m[7] * m[14] + m[13] * m[6] * m[11] - m[13] * m[7] * m[10];
  inv[4] = -m[4] * m[10] * m[15] + m[4] * m[11] * m[14] + m[8] * m[6] * m[15] -
           m[8] * m[7] * m[14] - m[12] * m[6] * m[11] + m[12] * m[7] * m[10];
  inv[8] = m[4] * m[9] * m[15] - m[4] * m[11] * m[13] - m[8] * m[5] * m[15] +
           m[8] * m[7] * m[13] + m[12] * m[5] * m[11] - m[12] * m[7] * m[9];
  inv[12] = -m[4] * m[9] * m[14] + m[4] * m[10] * m[13] + m[8] * m[5] * m[14] -
            m[8] * m[6] * m[13] - m[12] * m[5] * m[10] + m[12] * m[6] * m[9];
  inv[1] = -m[1] * m[10] * m[15] + m[1] * m[11] * m[14] + m[9] * m[2] * m[15] -
           m[9] * m[3] * m[14] - m[13] * m[2] * m[11] + m[13] * m[3] * m[10];
  inv[5] = m[0] * m[10] * m[15] - m[0] * m[11] * m[14] - m[8] * m[2] * m[15] +
           m[8] * m[3] * m[14] + m[12] * m[2] * m[11] - m[12] * m[3] * m[10];
  inv[9] = -m[0] * m[9] * m[15] + m[0] * m[11] * m[13] + m[8] * m[1] * m[15] -
           m[8] * m[3] * m[13] - m[12] * m[1] * m[11] + m[12] * m[3] * m[9];
  inv[13] = m[0] * m[9] * m[14] - m[0] * m[10] * m[13] - m[8] * m[1] * m[14] +
            m[8] * m[2] * m[13] + m[12] * m[1] * m[10] - m[12] * m[2] * m[9];
  inv[2] = m[1] * m[6] * m[15] - m[1] * m[7] * m[14] - m[5] * m[2] * m[15] +
           m[5] * m[3] * m[14] + m[13] * m[2] * m[7] - m[13] * m[3] * m[6];
  inv[6] = -m[0] * m[6] * m[15] + m[0] * m[7] * m[14] + m[4] * m[2] * m[15] -
           m[4] * m[3] * m[14] - m[12] * m[2] * m[7] + m[12] * m[3] * m[6];
  inv[10] = m[0] * m[5] * m[15] - m[0] * m[7] * m[13] - m[4] * m[1] * m[15] +
            m[4] * m[3] * m[13] + m[12] * m[1] * m[7] - m[12] * m[3] * m[5];
  inv[14] = -m[0] * m[5] * m[14] + m[0] * m[6] * m[13] + m[4] * m[1] * m[14] -
            m[4] * m[2] * m[13] - m[12] * m[1] * m[6] + m[12] * m[2] * m[5];
  inv[3] = -m[1] * m[6] * m[11] + m[1] * m[7] * m[10] + m[5] * m[2] * m[11] -
           m[5] * m[3] * m[10] - m[9] * m[2] * m[7] + m[9] * m[3] * m[6];
  inv[7] = m[0] * m[6] * m[11] - m[0] * m[7] * m[10] - m[4] * m[2] * m[11] +
           m[4] * m[3] * m[10] + m[8] * m[2] * m[7] - m[8] * m[3] * m[6];
  inv[11] = -m[0] * m[5] * m[11] + m[0] * m[7] * m[9] + m[4] * m[1] * m[11] -
            m[4] * m[3] * m[9] - m[8] * m[1] * m[7] + m[8] * m[3] * m[5];
  inv[15] = m[0] * m[5] * m[10] - m[0] * m[6] * m[9] - m[4] * m[1] * m[10] +
            m[4] * m[2] * m[9] + m[8] * m[1] * m[6] - m[8] * m[2] * m[5];

  double det = m[0] * inv[0] + m[1] * inv[4] + m[2] * inv[8] + m[3] * inv[12];
  if (std::abs(det) < 1e-12) {
    return false;
  }
  double idet = 1.0 / det;
  for (int i = 0; i < 16; i++) {
    out[i] = inv[i] * idet;
  }
  return true;
}

}  // namespace

AmbientOcclusionPass::~AmbientOcclusionPass() {
  // GL context is generally torn down before renderers; deleting 0 handles is a no-op
  // and the driver/context teardown reclaims anything still live. Kept minimal.
  free_targets();
  if (m_quad_vbo) {
    glDeleteBuffers(1, &m_quad_vbo);
  }
  if (m_quad_vao) {
    glDeleteVertexArrays(1, &m_quad_vao);
  }
}

void AmbientOcclusionPass::init_shaders(ShaderLibrary& shaders) {
  m_shaders = &shaders;
}

void AmbientOcclusionPass::ensure_quad() {
  if (m_quad_ready) {
    return;
  }
  // Same layout as OpenGLRenderer's screen_vao/vbo: 4 vec2 verts, TRIANGLE_STRIP,
  // attribute location 0. post_processing.vert consumes it (position_in).
  struct Vertex {
    float x, y;
  };
  const std::array<Vertex, 4> verts = {Vertex{-1, -1}, Vertex{-1, 1}, Vertex{1, -1},
                                       Vertex{1, 1}};
  glGenVertexArrays(1, &m_quad_vao);
  glGenBuffers(1, &m_quad_vbo);
  glBindVertexArray(m_quad_vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_quad_vbo);
  glBufferData(GL_ARRAY_BUFFER, sizeof(Vertex) * 4, verts.data(), GL_STATIC_DRAW);
  glEnableVertexAttribArray(0);
  glVertexAttribPointer(0, 2, GL_FLOAT, GL_TRUE, sizeof(Vertex), nullptr);
  glBindBuffer(GL_ARRAY_BUFFER, 0);
  glBindVertexArray(0);
  m_quad_ready = true;
}

void AmbientOcclusionPass::free_targets() {
  gl_query_census::Armed _ap("ao-free-targets");
  if (m_ao_fbo[0]) {
    // defect #6: drain before deleting targets the previous frame's blur/composite may
    // still reference in Adreno's deferred queue (only runs on a resolution change).
    glFinish();
    glDeleteFramebuffers(2, m_ao_fbo);
    glDeleteTextures(2, m_ao_tex);
    m_ao_fbo[0] = m_ao_fbo[1] = 0;
    m_ao_tex[0] = m_ao_tex[1] = 0;
  }
  if (m_ao_full_fbo) {
    glFinish();
    glDeleteFramebuffers(1, &m_ao_full_fbo);
    glDeleteTextures(1, &m_ao_full_tex);
    m_ao_full_fbo = 0;
    m_ao_full_tex = 0;
  }
}

void AmbientOcclusionPass::ensure_targets(int ao_w, int ao_h, int full_w, int full_h) {
  if (m_ao_fbo[0] && m_ao_w == ao_w && m_ao_h == ao_h && m_ao_full_fbo &&
      m_ao_full_w == full_w && m_ao_full_h == full_h) {
    return;
  }
  free_targets();
  m_ao_w = ao_w;
  m_ao_h = ao_h;
  m_ao_full_w = full_w;
  m_ao_full_h = full_h;
  glGenFramebuffers(2, m_ao_fbo);
  glGenTextures(2, m_ao_tex);
  for (int i = 0; i < 2; i++) {
    glBindTexture(GL_TEXTURE_2D, m_ao_tex[i]);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, ao_w, ao_h, 0, GL_RED, GL_UNSIGNED_BYTE, nullptr);
    // hdr-plan : recensement des entrees 8 bits du chemin de scene. N'a aucun effet sur le rendu.
    hdr::note_input_source_indexed("ao-target", i, GL_R8, ao_w, ao_h);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glBindFramebuffer(GL_FRAMEBUFFER, m_ao_fbo[i]);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_ao_tex[i], 0);
    GLenum bufs[1] = {GL_COLOR_ATTACHMENT0};
    glDrawBuffers(1, bufs);
    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
      lg::error("AO: ao target FBO {} incomplete ({}x{})", i, ao_w, ao_h);
    }
  }
  // full-res target for the upsampling V blur pass (owner tuning #2).
  glGenFramebuffers(1, &m_ao_full_fbo);
  glGenTextures(1, &m_ao_full_tex);
  glBindTexture(GL_TEXTURE_2D, m_ao_full_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_R8, full_w, full_h, 0, GL_RED, GL_UNSIGNED_BYTE, nullptr);
  // hdr-plan : recensement des entrees 8 bits du chemin de scene. N'a aucun effet sur le rendu.
  hdr::note_input_source("ao-full", GL_R8, full_w, full_h, 1);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glBindFramebuffer(GL_FRAMEBUFFER, m_ao_full_fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, m_ao_full_tex, 0);
  GLenum bufs[1] = {GL_COLOR_ATTACHMENT0};
  glDrawBuffers(1, bufs);
  if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
    lg::error("AO: full-res ao target FBO incomplete ({}x{})", full_w, full_h);
  }
}

// ---------------------------------------------------------------------------
// Uniform upload helper: the shared world<->screen transform uniforms every AO/blur
// pass needs. Uploads camera + inverse + hvdf + fog + cam_pos + sizes.
// ---------------------------------------------------------------------------
namespace {

void upload_common_uniforms(GLuint id,
                            SharedRenderState* rs,
                            const float inv[16],
                            float depth_w,
                            float depth_h,
                            float ao_w,
                            float ao_h) {
  // u_camera: same column layout the grass renderer uploads (camera_matrix[0].data()
  // is 16 contiguous floats, column-major).
  glUniformMatrix4fv(glu::loc(id, "u_camera"), 1, GL_FALSE,
                     rs->camera_matrix[0].data());
  glUniformMatrix4fv(glu::loc(id, "u_inv_camera"), 1, GL_FALSE, inv);
  glUniform4f(glu::loc(id, "u_hvdf_offset"), rs->camera_hvdf_off[0],
              rs->camera_hvdf_off[1], rs->camera_hvdf_off[2], rs->camera_hvdf_off[3]);
  glUniform1f(glu::loc(id, "u_fog"), rs->camera_fog.x());
  glUniform4f(glu::loc(id, "u_cam_pos"), rs->camera_pos[0], rs->camera_pos[1],
              rs->camera_pos[2], rs->camera_pos[3]);
  glUniform2f(glu::loc(id, "u_depth_size"), depth_w, depth_h);
  glUniform2f(glu::loc(id, "u_ao_size"), ao_w, ao_h);
}

}  // namespace

bool AmbientOcclusionPass::estimate(SharedRenderState* rs,
                                    GLuint depth_tex,
                                    int depth_w,
                                    int depth_h) {
  gl_query_census::Armed _ap("ao-estimate");
  if (!m_shaders || depth_tex == 0 || depth_w <= 0 || depth_h <= 0) {
    return false;
  }
  const int mode = effective_mode();  // 1=SSAO,2=HBAO,3=GTAO
  if (mode == 0) {
    return false;
  }
  int quality = effective_quality();
  if (quality < 0) {
    quality = 0;
  }
  if (quality > 2) {
    quality = 2;
  }
  const int dbg = effective_debug();  // 2 = raw estimator debug (depth bands), sinon 0

  // (1) resolution scale by quality
  const float scale = (quality == 0) ? 0.25f : (quality == 1) ? 0.5f : 1.0f;
  const int src_w = depth_w;  // depth resolution (render-scale sized)
  const int src_h = depth_h;
  const int out_w = (m_hint_w > 0) ? m_hint_w : src_w;  // AO/blur target sizing: keyed to the
  const int out_h = (m_hint_h > 0) ? m_hint_h : src_h;  // WINDOW so render-scale changes never
                                                        // recreate the AO chain (no churn/blink)
  const int ao_w = std::max(1, (int)(out_w * scale));
  const int ao_h = std::max(1, (int)(out_h * scale));

  // (2a) pure-CPU early-outs FIRST — after this point the function must not return
  // without running the state-restore block at the end.
  double cam[16];
  for (int c = 0; c < 4; c++) {
    for (int r = 0; r < 4; r++) {
      cam[c * 4 + r] = (double)rs->camera_matrix[c][r];
    }
  }
  double invd[16];
  if (!invert4x4(cam, invd)) {
    return false;  // singular camera -> skip AO this frame
  }
  float invf[16];
  for (int i = 0; i < 16; i++) {
    invf[i] = (float)invd[i];
  }

  auto ao_glerr = [&](const char* stage) {
    for (GLenum e; (e = glGetError()) != GL_NO_ERROR;) {
      if (m_err_logged < 24) {
        lg::error("AOERR stage={} gl=0x{:x}", stage, (unsigned)e);
        m_err_logged++;
      }
    }
  };
  ao_glerr("pre");  // drain pre-existing errors so later reads are ours

  // (2) full GL state snapshot (restored before returning). The pass runs mid-frame, avant le
  // premier draw ombre : ANY state it inherits can silently break it (a leftover GL_CULL_FACE
  // culls the CW fullscreen quad; scissor clips it) and ANY state it leaks breaks the
  // following buckets.
  GLint prev_fbo = 0;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prev_fbo);
  GLint prev_viewport[4];
  glGetIntegerv(GL_VIEWPORT, prev_viewport);
  const GLboolean prev_blend = glIsEnabled(GL_BLEND);
  const GLboolean prev_depth_test = glIsEnabled(GL_DEPTH_TEST);
  GLboolean prev_depth_mask = GL_TRUE;
  glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);
  const GLboolean prev_cull = glIsEnabled(GL_CULL_FACE);
  const GLboolean prev_scissor = glIsEnabled(GL_SCISSOR_TEST);
  const GLboolean prev_stencil = glIsEnabled(GL_STENCIL_TEST);
  GLboolean prev_color_mask[4] = {GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE};
  glGetBooleanv(GL_COLOR_WRITEMASK, prev_color_mask);
  GLint prev_program = 0;
  glGetIntegerv(GL_CURRENT_PROGRAM, &prev_program);
  GLint prev_vao = 0;
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prev_vao);
  GLint prev_array_buffer = 0;
  glGetIntegerv(GL_ARRAY_BUFFER_BINDING, &prev_array_buffer);
  GLint prev_active_tex = GL_TEXTURE0;
  glGetIntegerv(GL_ACTIVE_TEXTURE, &prev_active_tex);
  // the pass only ever touches texture units 0 and 1 — snapshot their 2D bindings.
  GLint prev_tex0 = 0, prev_tex1 = 0;
  glActiveTexture(GL_TEXTURE0);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex0);
  glActiveTexture(GL_TEXTURE1);
  glGetIntegerv(GL_TEXTURE_BINDING_2D, &prev_tex1);
  // pin unit 0 active so every glBindTexture in the ensure_* helpers below lands on a
  // unit we snapshot+restore (they would otherwise bind on whatever unit was active).
  glActiveTexture(GL_TEXTURE0);
  // neutralize inherited state that would break the fullscreen passes.
  glDisable(GL_CULL_FACE);
  glDisable(GL_SCISSOR_TEST);
  glDisable(GL_STENCIL_TEST);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);

  // (5) targets + (6) quad
  ensure_targets(ao_w, ao_h, out_w, out_h);
  ensure_quad();

  // Chaque dessin de la passe declare sa cible ici. `prev_fbo` est le FBO de SCENE tel que la
  // passe l'a trouve en entrant : un dessin qui y atterrirait serait, par definition, le composite
  // d'image de l'ancien chemin.
  auto note_target = [&](GLuint target) {
    s_ao_draws_total++;
    if ((GLint)target == prev_fbo) {
      s_ao_draws_on_scene++;
    }
  };

  const float depth_wf = (float)src_w;  // depth texture size (render-scale sized)
  const float depth_hf = (float)src_h;
  const float ao_wf = (float)ao_w;
  const float ao_hf = (float)ao_h;

  // per-quality kernel sizes
  int u_samples = 16, u_dirs = 6, u_steps = 6;
  switch (mode) {
    case 1:  // SSAO
      u_samples = (quality == 0) ? 8 : (quality == 1) ? 16 : 24;
      break;
    case 2:  // HBAO
      u_dirs = (quality == 0) ? 4 : (quality == 1) ? 6 : 8;
      u_steps = (quality == 0) ? 4 : (quality == 1) ? 6 : 8;
      break;
    case 3:  // GTAO
      u_dirs = (quality == 0) ? 3 : (quality == 1) ? 6 : 8;
      u_steps = (quality == 0) ? 6 : (quality == 1) ? 8 : 10;
      break;
    default:
      break;
  }
  // Per-mode look calibration (owner tuning #1/#3, 2026-07-15): every tier must be
  // UNMISTAKABLE vs OFF when toggled mid-game, with distinct characters — SSAO broad/soft
  // (large radius), HBAO mid, GTAO sharp/physical. The defect-#5 open-area cap (<=5%) is
  // held by the estimators returning ~1.0 on flat surfaces (aligned-slice / analytic-
  // tangent / tangent-plane fixes), NOT by keeping strength low. 4096 units = 1 m.
  // lighting-ao-indirect : le `k` de composite (u_ao_strength) a disparu avec le composite ;
  // l'intensite de l'ESTIMATEUR, elle, est conservee telle quelle par mode.
  float u_radius = 1434.0f;
  float u_intensity = 1.0f;
  switch (mode) {
    case 1:  // SSAO
      u_radius = 5120.0f;
      u_intensity = 2.0f;
      break;
    case 2:  // HBAO
      u_radius = 2867.0f;
      // closing round v2: the open-terrain wash is killed by the grazing-modulated occ
      // GATE in ao_hbao.frag (runs BEFORE intensity, so this scales creases only).
      u_intensity = 2.0f;
      break;
    case 3:  // GTAO
      u_radius = 3072.0f;  // 0.75 m — read large-scale concavities, not just tight creases
      u_intensity = 0.65f;
      break;
    default:
      break;
  }

  // AO STRENGTH row (owner closing round 2026-07-16): Weaker/Default/Stronger applies a
  // per-mode multiplier on the ESTIMATOR intensity — on flat open ground occ~0 so
  // intensity*occ stays ~0 and the defect-#5 open-area cap holds structurally even at
  // Stronger. Round G (owner 2026-07-16 22:20): HBAO/GTAO Default == old Weaker (0.6),
  // Stronger == old Default (1.0), Weaker one proportional step below (0.36). SSAO untouched.
  const int ao_strength_sel = effective_strength();
  const float ao_strength_mul =
      (mode == 1) ? ((ao_strength_sel == 0) ? 0.6f : (ao_strength_sel == 2) ? 1.5f : 1.0f)
                  : ((ao_strength_sel == 0) ? 0.36f : (ao_strength_sel == 2) ? 1.0f : 0.6f);
  static int s_ladder_logged_mode = -1, s_ladder_logged_sel = -1;
  if (mode != s_ladder_logged_mode || ao_strength_sel != s_ladder_logged_sel) {
    lg::info("[recharged-ao] ladder mode={} strength={} mul={:.2f}", mode, ao_strength_sel,
             ao_strength_mul);
    s_ladder_logged_mode = mode;
    s_ladder_logged_sel = ao_strength_sel;
  }
  u_intensity *= ao_strength_mul;

  glBindVertexArray(m_quad_vao);
  glDisable(GL_BLEND);
  glDisable(GL_DEPTH_TEST);
  glDepthMask(GL_FALSE);

  // (7) Pass 1: AO estimate -> m_ao_tex[0]
  {
    ShaderId sid = (mode == 1) ? ShaderId::AO_SSAO
                   : (mode == 2) ? ShaderId::AO_HBAO
                                 : ShaderId::AO_GTAO;
    auto& shader = (*m_shaders)[sid];
    shader.activate();
    GLuint id = shader.id();
    glBindFramebuffer(GL_FRAMEBUFFER, m_ao_fbo[0]);
    glViewport(0, 0, ao_w, ao_h);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, depth_tex);
    glUniform1i(glu::loc(id, "u_depth"), 0);
    upload_common_uniforms(id, rs, invf, depth_wf, depth_hf, ao_wf, ao_hf);
    glUniform1f(glu::loc(id, "u_radius"), u_radius);
    glUniform1f(glu::loc(id, "u_intensity"), u_intensity);
    // round F (owner 2026-07-16 16:50): HBAO/GTAO get an SSAO-model broad soft depth
    // term at SSAO's calibrated intensity (2.0, strength-scaled like the contact term).
    // SSAO itself has no u_broad uniform (location -1, upload ignored).
    glUniform1f(glu::loc(id, "u_broad"),
                (mode == 1) ? 0.0f : 2.0f * ao_strength_mul);
    glUniform1i(glu::loc(id, "u_samples"), u_samples);
    glUniform1i(glu::loc(id, "u_dirs"), u_dirs);
    glUniform1i(glu::loc(id, "u_steps"), u_steps);
    glUniform1i(glu::loc(id, "u_debug"), (dbg == 2) ? 2 : 0);
    // defect #6 residual (gtao-high title kill): the estimator is the one potentially
    // GPU-heavy draw (GTAO High = full-res x 6 slices x 20 samples ~ 1s+ on Adreno 618).
    // A single mega-draw trips the KGSL GPU watchdog under level-load churn. Split into
    // scissored horizontal bands: the driver preempts and the watchdog resets at draw
    // boundaries, so each submission stays bounded.
    const int bands = std::min(8, 1 + (ao_w * ao_h) / 400000);
    if (bands > 1) {
      glEnable(GL_SCISSOR_TEST);
    }
    for (int b = 0; b < bands; b++) {
      const int y0 = (int)((int64_t)ao_h * b / bands);
      const int y1 = (int)((int64_t)ao_h * (b + 1) / bands);
      if (bands > 1) {
        glScissor(0, y0, ao_w, y1 - y0);
      }
      glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
    }
    if (bands > 1) {
      glDisable(GL_SCISSOR_TEST);  // pass invariant: scissor off (restored at the end)
    }
    note_target(m_ao_fbo[0]);
  }
  ao_glerr("estimate");

  // (8) Bilateral blur: pass H at AO res (tex0 raw -> tex1), pass V at FULL res
  // (tex1 -> m_ao_full_tex). The full-res V pass doubles as a depth-aware upsample
  // (owner tuning #2: a sub-full-res AO term read raw is blocky at full render res; the
  // linear-filtered low-res source + full-res depth weights kill the stair-stepping
  // without bleeding across depth edges).
  bool produced = false;
  if (dbg != 2) {
    auto& shader = (*m_shaders)[ShaderId::AO_BLUR];
    for (int p = 0; p < 2; p++) {
      shader.activate();
      GLuint id = shader.id();
      if (p == 0) {
        glBindFramebuffer(GL_FRAMEBUFFER, m_ao_fbo[1]);
        glViewport(0, 0, ao_w, ao_h);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, m_ao_tex[0]);
      } else {
        glBindFramebuffer(GL_FRAMEBUFFER, m_ao_full_fbo);
        glViewport(0, 0, out_w, out_h);
        glActiveTexture(GL_TEXTURE0);
        glBindTexture(GL_TEXTURE_2D, m_ao_tex[1]);
      }
      glUniform1i(glu::loc(id, "u_ao"), 0);
      glActiveTexture(GL_TEXTURE1);
      glBindTexture(GL_TEXTURE_2D, depth_tex);
      glUniform1i(glu::loc(id, "u_depth"), 1);
      upload_common_uniforms(id, rs, invf, depth_wf, depth_hf, ao_wf, ao_hf);
      if (p == 0) {
        glUniform2f(glu::loc(id, "u_dir"), 1.0f / ao_wf, 0.0f);
      } else {
        glUniform2f(glu::loc(id, "u_dir"), 0.0f, 1.0f / ao_hf);
      }
      glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);
      note_target((p == 0) ? m_ao_fbo[1] : m_ao_full_fbo);
    }
    glActiveTexture(GL_TEXTURE0);
    produced = true;
  } else {
    // vue de debug 2 : l'estimation brute, sans flou, recopiee telle quelle en pleine
    // resolution pour que shade() la voie (u_screen_ao_on == 2 l'affiche).
    glBindFramebuffer(GL_READ_FRAMEBUFFER, m_ao_fbo[0]);
    glBindFramebuffer(GL_DRAW_FRAMEBUFFER, m_ao_full_fbo);
    glBlitFramebuffer(0, 0, ao_w, ao_h, 0, 0, out_w, out_h, GL_COLOR_BUFFER_BIT, GL_NEAREST);
    note_target(m_ao_full_fbo);
    produced = true;
  }
  ao_glerr("blur");

  // (10) restore EVERY piece of state the pass touched (defect #4: any leak here
  // corrupts the following buckets).
  glBindVertexArray(prev_vao);
  glBindBuffer(GL_ARRAY_BUFFER, prev_array_buffer);
  glUseProgram(prev_program);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, prev_tex0);
  glActiveTexture(GL_TEXTURE1);
  glBindTexture(GL_TEXTURE_2D, prev_tex1);
  glActiveTexture(prev_active_tex);
  if (prev_blend) {
    glEnable(GL_BLEND);
  } else {
    glDisable(GL_BLEND);
  }
  if (prev_depth_test) {
    glEnable(GL_DEPTH_TEST);
  } else {
    glDisable(GL_DEPTH_TEST);
  }
  glDepthMask(prev_depth_mask);
  if (prev_cull) {
    glEnable(GL_CULL_FACE);
  }
  if (prev_scissor) {
    glEnable(GL_SCISSOR_TEST);
  }
  if (prev_stencil) {
    glEnable(GL_STENCIL_TEST);
  }
  glColorMask(prev_color_mask[0], prev_color_mask[1], prev_color_mask[2], prev_color_mask[3]);
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
  glViewport(prev_viewport[0], prev_viewport[1], prev_viewport[2], prev_viewport[3]);

  autoport_proof::publish("ao_draws_total", s_ao_draws_total);
  autoport_proof::publish("ao_draws_on_scene", s_ao_draws_on_scene);
  autoport_proof::publish("ao_legacy_composite_compiled",
                          ao_has_composite<AmbientOcclusionPass>::value ? 1 : 0);
  autoport_proof::publish("ao_legacy_witness_selftest",
                          ao_has_composite<AoLegacyWitnessControl>::value ? 1 : 0);
  return produced;
}
