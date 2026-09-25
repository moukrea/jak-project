

#include "background_common.h"
#include "game/system/recharged_gating.h"

#include "game/graphics/opengl_renderer/PrePass.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <map>
#include <set>
#include <mutex>
#include <tuple>
#include <unordered_map>
#ifdef OG_FEAT_PBR
#include <cmath>
#endif
#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

#include "common/log/log.h"
#ifndef __ANDROID__
#include "game/graphics/screenshot.h"
#endif
#include "common/util/os.h"
#include "common/util/simd_util.h"

#include "game/graphics/gfx.h"
#include "game/graphics/gl_query_census.h"
#include "game/graphics/opengl_renderer/BucketRenderer.h"
#include "game/graphics/opengl_renderer/frame_ubo.h"
#include "game/graphics/opengl_renderer/gl_uniform_cache.h"
#include "game/graphics/opengl_renderer/hdr.h"
#include "game/graphics/opengl_renderer/prop_cache.h"
#include "game/graphics/opengl_renderer/lighting_census.h"
#include "game/graphics/opengl_renderer/Shader.h"
#include "game/graphics/opengl_renderer/SkyCapture.h"
#include "game/graphics/pipelines/opengl.h"
#include "game/system/autoport_proof.h"
AUTOPORT_FEATURE_SITE("gl-uniforms-off-cost");
AUTOPORT_FEATURE_SITE("lighting-off-math-still-runs");
// lighting-shadows (SPEC §4.8) : la sonde de preuve (pbr_shadow_proof_post_opaque) attribue ses
// pixels de sol ombres par un acteur a CET item via note_hit_for ; le site est declare au chargement.
AUTOPORT_FEATURE_SITE("lighting-shadows");

#ifdef OG_FEAT_GRASS_OVERHANG
// ROUND 10 forensics switch (see GrassFringeFade::dbg). Cached + throttled like grass_droop_len():
// a debug prop/env read must never sit on the per-frame draw path uncached.
// Grecharged-buildsys-flags: overhang-only (only called from grass_fringe_fade_params' ON branch).
static float grass_fringe_dbg() {
  static float s_cached = 0.f;
  static int s_throttle = 0;
  if ((s_throttle++ & 63) != 0) {
    return s_cached;
  }
  char buf[16] = {0};
  bool have = false;
#ifdef __ANDROID__
  if (__system_property_get("debug.opengoal.grass.fringe_dbg", buf) > 0 && buf[0]) {
    have = true;
  }
#else
  const char* e = std::getenv("GRASS_FRINGE_DBG");
  if (e && e[0]) {
    std::strncpy(buf, e, sizeof(buf) - 1);
    have = true;
  }
#endif
  float v = have ? (float)std::atof(buf) : 0.f;
  if (v < 0.f || v > 2.f) v = 0.f;
  s_cached = v;
  return v;
}
#endif  // OG_FEAT_GRASS_OVERHANG

GrassFringeFade grass_fringe_fade_params() {
  GrassFringeFade r;
#ifndef OG_FEAT_GRASS_OVERHANG
  // Grecharged-buildsys-flags: overhang compiled OUT (default) -> fringe-fade is an
  // overhang-only LOD; always return the disabled default (identical to toggle-off).
  return r;
#else
  if (!recharged_gating::on(recharged_gating::kGrass) ||
      !recharged_gating::on(recharged_gating::kGrassOverhang)) {
    return r;
  }
  // Mirror GrassRenderer's near-LOD clamp (GrassRenderer.cpp:990): the texture fades IN over the
  // exact band the droop blades fade OUT in (blade alpha = 1 - smoothstep(0.55*near, near, d)).
  float near_m = std::min(80.0f, std::max(8.0f, Gfx::settings().recharged_grass_near_dist));
  r.on = true;
  r.start_m = near_m * 0.55f;
  r.end_m = near_m;
  r.dbg = grass_fringe_dbg();
  return r;
#endif
}

// Pure (zero GL calls) computation of the DoubleDraw settings and the
// alpha_hack_to_disable_z_write flag from a DrawMode. This is exactly the
// blend/alpha-test logic embedded in setup_opengl_from_draw_mode below, factored
// out so the state cache (setup_tfrag_shader_cached) can decide the aref_first
// uniform without re-issuing any GL state. Keep in lockstep with the GL path.
DoubleDraw compute_double_draw(DrawMode mode) {
  DoubleDraw double_draw;

  if (mode.get_ab_enable() && mode.get_alpha_blend() != DrawMode::AlphaBlend::DISABLED) {
    switch (mode.get_alpha_blend()) {
      case DrawMode::AlphaBlend::SRC_SRC_SRC_SRC:
        break;
      case DrawMode::AlphaBlend::SRC_DST_SRC_DST:
        break;
      case DrawMode::AlphaBlend::SRC_0_SRC_DST:
        break;
      case DrawMode::AlphaBlend::SRC_0_FIX_DST:
        break;
      case DrawMode::AlphaBlend::SRC_DST_FIX_DST:
        break;
      case DrawMode::AlphaBlend::ZERO_SRC_SRC_DST:
        break;
      case DrawMode::AlphaBlend::SRC_0_DST_DST:
        double_draw.color_mult = 0.5f;
        break;
      default:
        ASSERT(false);
    }
  }

  // for some reason, they set atest NEVER + FB_ONLY to disable depth writes
  bool alpha_hack_to_disable_z_write = false;
  (void)alpha_hack_to_disable_z_write;

  float alpha_min = 0.;
  if (mode.get_at_enable()) {
    switch (mode.get_alpha_test()) {
      case DrawMode::AlphaTest::ALWAYS:
        break;
      case DrawMode::AlphaTest::GEQUAL:
        alpha_min = mode.get_aref() / 127.f;
        switch (mode.get_alpha_fail()) {
          case GsTest::AlphaFail::KEEP:
            // ok, no need for double draw
            break;
          case GsTest::AlphaFail::FB_ONLY:
            if (mode.get_depth_write_enable()) {
              // darn, we need to draw twice
              double_draw.kind = DoubleDrawKind::AFAIL_NO_DEPTH_WRITE;
              double_draw.aref_second = alpha_min;
            } else {
              alpha_min = 0.f;
            }
            break;
          default:
            ASSERT(false);
        }
        break;
      case DrawMode::AlphaTest::NEVER:
        if (mode.get_alpha_fail() == GsTest::AlphaFail::FB_ONLY) {
          alpha_hack_to_disable_z_write = true;
        } else {
          ASSERT(false);
        }
        break;
      default:
        ASSERT(false);
    }
  }

  double_draw.aref_first = alpha_min;
  return double_draw;
}

// lighting-ao-indirect : MEME regle que ci-dessus, reduite au seul seuil et sans ASSERT — la
// prepasse de profondeur la lit au CHARGEMENT, sur des draws qu'elle ne dessinera peut-etre
// jamais ; une donnee inattendue ne doit pas tuer le jeu la ou le draw principal, lui, n'aurait
// rien jete.
float prepass_alpha_min(const DrawMode& mode) {
  if (!mode.get_at_enable()) {
    return 0.f;
  }
  if (mode.get_alpha_test() != DrawMode::AlphaTest::GEQUAL) {
    // ALWAYS ne jette rien ; NEVER + FB_ONLY est le hack « pas de z-write », pas un test.
    return 0.f;
  }
  const float a = mode.get_aref() / 127.f;
  if (mode.get_alpha_fail() == GsTest::AlphaFail::FB_ONLY && !mode.get_depth_write_enable()) {
    // le draw ne s'ecrit que dans le framebuffer : compute_double_draw remet alpha_min a 0.
    return 0.f;
  }
  return a;
}

// lighting-ao-indirect (refus owner (c)/(g)) : miroir EXACT de la condition de `glDepthMask`
// de `setup_opengl_from_draw_mode` ci-dessous. Un draw qui rend FAUX ne doit pas ecrire la
// profondeur dans la prepasse : l'AO y verrait un occluder rectangulaire opaque que l'image
// ne dessine pas.
bool prepass_writes_depth(const DrawMode& mode) {
  if (!mode.get_depth_write_enable()) {
    return false;
  }
  // `alpha_hack_to_disable_z_write` de compute_double_draw / setup_opengl_from_draw_mode :
  // AlphaTest::NEVER + AlphaFail::FB_ONLY. Le draw ne touche que le framebuffer.
  if (mode.get_at_enable() && mode.get_alpha_test() == DrawMode::AlphaTest::NEVER &&
      mode.get_alpha_fail() == GsTest::AlphaFail::FB_ONLY) {
    return false;
  }
  return true;
}

// lighting-ao-indirect (terme 3) : la regle d'echantillonnage, en un seul endroit. Voir le
// commentaire de background_common.h.
uint8_t prepass_tex_mode(const DrawMode& mode) {
  return (uint8_t)((mode.get_clamp_s_enable() ? 1 : 0) | (mode.get_clamp_t_enable() ? 2 : 0) |
                   (mode.get_filt_enable() ? 4 : 0));
}

void prepass_tex_params(uint8_t tex_mode, bool mipmap, int out4[4]) {
  if (tex_mode == 0xff) {
    out4[0] = out4[1] = out4[2] = out4[3] = 0;
    return;
  }
  out4[0] = (tex_mode & 1) ? GL_CLAMP_TO_EDGE : GL_REPEAT;
  out4[1] = (tex_mode & 2) ? GL_CLAMP_TO_EDGE : GL_REPEAT;
  out4[2] = (tex_mode & 4) ? (mipmap ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR) : GL_NEAREST;
  out4[3] = (tex_mode & 4) ? GL_LINEAR : GL_NEAREST;
}

DoubleDraw setup_opengl_from_draw_mode(DrawMode mode, u32 tex_unit, bool mipmap) {
  glActiveTexture(tex_unit);

  if (mode.get_zt_enable()) {
    glEnable(GL_DEPTH_TEST);
    switch (mode.get_depth_test()) {
      case GsTest::ZTest::NEVER:
        glDepthFunc(GL_NEVER);
        break;
      case GsTest::ZTest::ALWAYS:
        glDepthFunc(GL_ALWAYS);
        break;
      case GsTest::ZTest::GEQUAL:
        glDepthFunc(GL_GEQUAL);
        break;
      case GsTest::ZTest::GREATER:
        glDepthFunc(GL_GREATER);
        break;
      default:
        ASSERT(false);
    }
  } else {
    glDisable(GL_DEPTH_TEST);
  }

  DoubleDraw double_draw;

  bool should_enable_blend = false;
  if (mode.get_ab_enable() && mode.get_alpha_blend() != DrawMode::AlphaBlend::DISABLED) {
    should_enable_blend = true;
    switch (mode.get_alpha_blend()) {
      case DrawMode::AlphaBlend::SRC_SRC_SRC_SRC:
        should_enable_blend = false;
        // (SRC - SRC) * alpha + SRC = SRC, no blend.
        break;
      case DrawMode::AlphaBlend::SRC_DST_SRC_DST:
        glBlendEquation(GL_FUNC_ADD);
        glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ZERO);
        break;
      case DrawMode::AlphaBlend::SRC_0_SRC_DST:
        glBlendEquation(GL_FUNC_ADD);
        glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE, GL_ONE, GL_ZERO);
        break;
      case DrawMode::AlphaBlend::SRC_0_FIX_DST:
        glBlendEquation(GL_FUNC_ADD);
        glBlendFuncSeparate(GL_ONE, GL_ONE, GL_ONE, GL_ZERO);
        break;
      case DrawMode::AlphaBlend::SRC_DST_FIX_DST:
        // Cv = (Cs - Cd) * FIX + Cd
        // Cs * FIX * 0.5
        // Cd * FIX * 0.5
        glBlendEquation(GL_FUNC_ADD);
        glBlendFuncSeparate(GL_CONSTANT_COLOR, GL_CONSTANT_COLOR, GL_ONE, GL_ZERO);
        glBlendColor(0.5, 0.5, 0.5, 0.5);
        break;
      case DrawMode::AlphaBlend::ZERO_SRC_SRC_DST:
        // Reverse subtraction previously stored clamp(-As, 0, 1) = 0 in RGBA8.
        // Preserve that alpha result without narrowing the floating-point RGB.
        glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE, GL_ZERO, GL_ZERO);
        glBlendEquation(GL_FUNC_REVERSE_SUBTRACT);
        break;
      case DrawMode::AlphaBlend::SRC_0_DST_DST:
        if (hdr::chain_active()) {
          // In RGBA16F, alpha must remain a bounded weight, following DirectRenderer's convention.
          glBlendFuncSeparate(GL_DST_ALPHA, GL_ONE, GL_ONE, GL_ZERO);
        } else {
          glBlendFunc(GL_DST_ALPHA, GL_ONE);
        }
        glBlendEquation(GL_FUNC_ADD);
        double_draw.color_mult = 0.5f;
        break;
      default:
        ASSERT(false);
    }
  } else {
    should_enable_blend = false;
  }

  if (should_enable_blend) {
    glEnable(GL_BLEND);
  } else {
    glDisable(GL_BLEND);
  }

  // lighting-ao-indirect (terme 3) : les quatre memes valeurs qu'avant, mais calculees par
  // `prepass_tex_params` — l'unique definition de la regle, que la prepasse de profondeur appelle
  // aussi (elle les heritait, voir background_common.h).
  {
    int p4[4];
    prepass_tex_params(prepass_tex_mode(mode), mipmap, p4);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, p4[0]);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, p4[1]);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, p4[2]);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, p4[3]);
  }

  // for some reason, they set atest NEVER + FB_ONLY to disable depth writes
  bool alpha_hack_to_disable_z_write = false;

  float alpha_min = 0.;
  if (mode.get_at_enable()) {
    switch (mode.get_alpha_test()) {
      case DrawMode::AlphaTest::ALWAYS:
        break;
      case DrawMode::AlphaTest::GEQUAL:
        alpha_min = mode.get_aref() / 127.f;
        switch (mode.get_alpha_fail()) {
          case GsTest::AlphaFail::KEEP:
            // ok, no need for double draw
            break;
          case GsTest::AlphaFail::FB_ONLY:
            if (mode.get_depth_write_enable()) {
              // darn, we need to draw twice
              double_draw.kind = DoubleDrawKind::AFAIL_NO_DEPTH_WRITE;
              double_draw.aref_second = alpha_min;
            } else {
              alpha_min = 0.f;
            }
            break;
          default:
            ASSERT(false);
        }
        break;
      case DrawMode::AlphaTest::NEVER:
        if (mode.get_alpha_fail() == GsTest::AlphaFail::FB_ONLY) {
          alpha_hack_to_disable_z_write = true;
        } else {
          ASSERT(false);
        }
        break;
      default:
        ASSERT(false);
    }
  }

  if (mode.get_depth_write_enable() && !alpha_hack_to_disable_z_write) {
    glDepthMask(GL_TRUE);
  } else {
    glDepthMask(GL_FALSE);
  }
  double_draw.aref_first = alpha_min;
  return double_draw;
}

// alpha_min/alpha_max uniform locations per program — this runs once per
// draw on the hot background path, and glGetUniformLocation is a string
// lookup in the driver. Locations are stable for the life of a linked
// program (programs are built once at startup and never relinked).
const TfragAlphaUniforms& tfrag_alpha_uniforms(u64 program) {
  static std::unordered_map<u64, TfragAlphaUniforms> cache;
  auto it = cache.find(program);
  if (it == cache.end()) {
    TfragAlphaUniforms u;
    u.alpha_min = glu::loc(program, "alpha_min");
    u.alpha_max = glu::loc(program, "alpha_max");
    it = cache.emplace(program, u).first;
  }
  return it->second;
}

DoubleDraw setup_tfrag_shader(SharedRenderState* render_state, DrawMode mode, ShaderId shader) {
  auto draw_settings = setup_opengl_from_draw_mode(mode, GL_TEXTURE0, true);
  const auto& u = tfrag_alpha_uniforms(render_state->shaders[shader].id());
  if (u.alpha_min != -1) {
    glUniform1f(u.alpha_min, draw_settings.aref_first);
  }
  if (u.alpha_max != -1) {
    glUniform1f(u.alpha_max, 10.f);
  }
  return draw_settings;
}

// The 4 texture-object glTexParameteri calls from setup_opengl_from_draw_mode
// (wrap_s/wrap_t + min/mag filter, mipmap=true). These write onto whatever
// texture is currently bound to GL_TEXTURE_2D, so a freshly-bound texture always
// needs them even when the global blend/depth state is unchanged. Kept
// byte-identical to the corresponding block in setup_opengl_from_draw_mode.
static void apply_tex_params_from_draw_mode(DrawMode mode) {
  // lighting-ao-indirect (terme 3) : meme regle, meme definition (background_common.h). Le
  // `mipmap = true` est celui que `setup_tfrag_shader_cached` passe a
  // `setup_opengl_from_draw_mode` : les deux sites restent d'accord par construction.
  int p4[4];
  prepass_tex_params(prepass_tex_mode(mode), /*mipmap=*/true, p4);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, p4[0]);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, p4[1]);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, p4[2]);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, p4[3]);
}

DoubleDraw setup_tfrag_shader_cached(SharedRenderState* render_state,
                                     DrawMode mode,
                                     ShaderId shader,
                                     GLuint bound_tex,
                                     BgDrawStateCache& cache) {
  // Flag off: bit-identical to the un-cached path.
  if (!render_state->perf_state_cache) {
    return setup_tfrag_shader(render_state, mode, shader);
  }

  DoubleDraw draw_settings = compute_double_draw(mode);

  if (!cache.valid || mode.as_int() != cache.last_mode) {
    // full miss: re-issue the exact GL sequence setup_opengl_from_draw_mode
    // would (mipmap=true) — the compute result is discarded, GL path is source
    // of truth so the kill-switch comparison stays meaningful.
    setup_opengl_from_draw_mode(mode, GL_TEXTURE0, true);
    cache.last_mode = mode.as_int();
    cache.last_tex = bound_tex;
    cache.valid = true;
  } else if (bound_tex != cache.last_tex) {
    // same mode, new texture object: only the texture-object params need
    // re-applying (glTexParameteri targets the bound texture).
    apply_tex_params_from_draw_mode(mode);
    cache.last_tex = bound_tex;
  }
  // else: identical mode + texture, no GL state calls needed.

  const auto& u = tfrag_alpha_uniforms(render_state->shaders[shader].id());
  if (u.alpha_min != -1) {
    glUniform1f(u.alpha_min, draw_settings.aref_first);
  }
  if (u.alpha_max != -1) {
    glUniform1f(u.alpha_max, 10.f);
  }
  return draw_settings;
}

std::array<math::Vector4f, 4> make_new_cam_mat(const math::Vector4f cam_T_w[4],
                                               const math::Vector4f persp[4],
                                               float fog_constant,
                                               float hvdf_z) {
  // renderers may eventually have tricks to do things in local coordinates - so use the convention
  // that the shader has already subtracted off the camera translation from the vertex position.
  // (I think this could help with accuracy too, since you aren't rotating and subtracting two large
  // vectors that are very close to each other)

  // this is the perspective x-scaling. This is used to map to a 256-pixel buffer.
  const float game_pxx = persp[0][0];
  // on PC, OpenGL uses normalized coordinates for drawing, so divide by the pixel width.
  // in the game, the perspective divide includes a multiplication by the fog constant, for PC,
  // just include this multiply here so we can let OpenGL do the perspective multiply.
  const float pc_pxx = fog_constant * game_pxx / 256.f;

  // this is the perspective y-scaling.
  const float game_pyy = persp[1][1];
  // same logic as y - there's a later SCISSOR scaling in the shader that expects this ratio.
  const float pc_pyy = -fog_constant * game_pyy / 128.f;

  // the depth is considered twice. Once, as the value to write into the depth buffer, which is
  // scaled for PC here:
  const float depth_scale = fog_constant * persp[2][2] / 8388608;

  // and once as the value used for perspective divide
  const float game_pzw = persp[2][3];
  const float game_depth_offset = persp[3][2];

  // set up PC scaling values
  math::Vector3f persp_scale(pc_pxx, pc_pyy, depth_scale);

  // it turns out that shifting the depth buffer to line up with OpenGL is equivalent to adding
  // transformed.w * (hvdf_z / 8388608.f - 1.f) to the depth value. We know that w is just depth *
  // pzw, so we can include the effect here:
  const float pc_z_offset = (hvdf_z / 8388608.f - 1.f);
  persp_scale.z() += pc_z_offset * game_pzw;

  std::array<math::Vector4f, 4> result;
  for (auto& x : result) {
    x.set_zero();
  }

  // fill out the upper 3x3 - simply scale the rotation matrix by the perspective scale.
  for (int row = 0; row < 3; row++) {
    for (int col = 0; col < 3; col++) {
      result[row][col] = cam_T_w[row][col] * persp_scale[col];
    }
  }

  // fill out the right most column. This converts world-space points to depth for divide, scaled by
  // pzw. for now, copy the game.
  for (int row = 0; row < 3; row++) {
    result[row][3] = cam_T_w[row][2] * game_pzw;
  }

  // depth buffer offset - now needs to be scaled by the PC depth buffer scaling too
  result[3][2] = fog_constant * game_depth_offset / 8388608;

  return result;
}

#ifdef OG_FEAT_PBR

// ===========================================================================
// Grecharged-pbr-materials round-4 mandate B: sun shadow mapping.
// ===========================================================================

PbrShadowState& pbr_shadow_state() {
  static PbrShadowState s;
  return s;
}

// Tiny column-major matrix helpers. Column-major = element[col*4 + row], the layout
// glUniformMatrix4fv(..., GL_FALSE, ...) expects. lookAt/ortho follow the standard
// right-handed GL conventions so proj*view maps eye-space z to NDC [-1,1].
namespace {
struct PbrV3 {
  float x, y, z;
};
static PbrV3 pv_sub(PbrV3 a, PbrV3 b) {
  return {a.x - b.x, a.y - b.y, a.z - b.z};
}
static float pv_dot(PbrV3 a, PbrV3 b) {
  return a.x * b.x + a.y * b.y + a.z * b.z;
}
static PbrV3 pv_cross(PbrV3 a, PbrV3 b) {
  return {a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x};
}
static PbrV3 pv_norm(PbrV3 a) {
  float l = std::sqrt(pv_dot(a, a));
  if (l < 1e-8f) {
    return {0.f, 0.f, 0.f};
  }
  return {a.x / l, a.y / l, a.z / l};
}
// GLSL-style smoothstep (C1 Hermite ramp), clamped to [0,1].
static inline float rt_smoothstep(float e0, float e1, float x) {
  float t = (x - e0) / (e1 - e0);
  t = t < 0.f ? 0.f : (t > 1.f ? 1.f : t);
  return t * t * (3.f - 2.f * t);
}

// Right-handed lookAt into column-major float[16].
static void pbr_look_at(PbrV3 eye, PbrV3 center, PbrV3 up, float out[16]) {
  PbrV3 f = pv_norm(pv_sub(center, eye));
  PbrV3 s = pv_norm(pv_cross(f, up));
  PbrV3 u = pv_cross(s, f);
  out[0] = s.x; out[1] = u.x; out[2] = -f.x; out[3] = 0.f;
  out[4] = s.y; out[5] = u.y; out[6] = -f.y; out[7] = 0.f;
  out[8] = s.z; out[9] = u.z; out[10] = -f.z; out[11] = 0.f;
  out[12] = -pv_dot(s, eye); out[13] = -pv_dot(u, eye); out[14] = pv_dot(f, eye); out[15] = 1.f;
}

// Right-handed orthographic projection into column-major float[16], NDC z in [-1,1].
static void pbr_ortho(float l, float r, float b, float t, float n, float fpl, float out[16]) {
  for (int i = 0; i < 16; i++) out[i] = 0.f;
  out[0] = 2.f / (r - l);
  out[5] = 2.f / (t - b);
  out[10] = -2.f / (fpl - n);
  out[12] = -(r + l) / (r - l);
  out[13] = -(t + b) / (t - b);
  out[14] = -(fpl + n) / (fpl - n);
  out[15] = 1.f;
}

// out = a * b, all column-major float[16].
static void pbr_mat_mul(const float a[16], const float b[16], float out[16]) {
  for (int col = 0; col < 4; col++) {
    for (int row = 0; row < 4; row++) {
      float sum = 0.f;
      for (int k = 0; k < 4; k++) {
        sum += a[k * 4 + row] * b[col * 4 + k];
      }
      out[col * 4 + row] = sum;
    }
  }
}

// lighting-shadows (A3c) : inverse generale d'une matrice 4x4 colonne-major, par
// Gauss-Jordan. Rend faux (matrice inchangee) si le determinant est ~0.
static bool pbr_mat_inverse(const float m[16], float out[16]) {
  double a[4][8];
  for (int r = 0; r < 4; r++) {
    for (int c = 0; c < 4; c++) {
      a[r][c] = m[c * 4 + r];
      a[r][c + 4] = (r == c) ? 1.0 : 0.0;
    }
  }
  for (int col = 0; col < 4; col++) {
    int piv = col;
    double best = std::fabs(a[col][col]);
    for (int r = col + 1; r < 4; r++) {
      if (std::fabs(a[r][col]) > best) {
        best = std::fabs(a[r][col]);
        piv = r;
      }
    }
    if (best < 1e-9) {
      return false;
    }
    if (piv != col) {
      for (int c = 0; c < 8; c++) std::swap(a[col][c], a[piv][c]);
    }
    const double d = a[col][col];
    for (int c = 0; c < 8; c++) a[col][c] /= d;
    for (int r = 0; r < 4; r++) {
      if (r == col) continue;
      const double f = a[r][col];
      for (int c = 0; c < 8; c++) a[r][c] -= f * a[col][c];
    }
  }
  for (int r = 0; r < 4; r++) {
    for (int c = 0; c < 4; c++) {
      out[c * 4 + r] = (float)a[r][c + 4];
    }
  }
  return true;
}

static void pbr_mat_identity(float out[16]) {
  for (int i = 0; i < 16; i++) out[i] = 0.f;
  out[0] = out[5] = out[10] = out[15] = 1.f;
}

// Read the shadow-map quality prop ONCE per frame (Android prop / desktop env), cached on
// frame_idx so this never re-reads on every call within a frame. Default ON.
static bool pbr_shadowmap_enabled_for_frame(u64 frame_idx) {
  static u64 s_frame = ~0ull;
  static bool s_on = true;
  if (frame_idx != s_frame) {
    s_frame = frame_idx;
    s_on = true;
#ifdef __ANDROID__
    char v[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.pbr.shadowmap", v) > 0 && v[0]) {
      s_on = atoi(v) != 0;
    }
#else
    if (const char* e = std::getenv("OG_PBR_SHADOWMAP")) {
      s_on = std::atoi(e) != 0;
    }
#endif
  }
  return s_on;
}

// lighting-shadows (A7) : etat de la sonde de preuve, prive a ce fichier.
struct ShadowProofState {
  u64 frame = ~0ull;
  bool prep_frame = false;    // image de PREPARATION (k==29) : l'atlas acteur se remplit
  bool probe_frame = false;   // image de PREUVE (k==0, apres une prep reussie)
  bool prev_prep_ok = false;  // la derniere image de prep a bien efface l'atlas acteur
  GLuint actor_fbo = 0, actor_tex = 0;
  int actor_size = 0;
  bool actor_valid = false;
  GLuint probe_fbo = 0, probe_tex = 0;
  int probe_w = 0, probe_h = 0;
  GLuint probe_vao = 0;  // VAO vide pour le triangle plein ecran
  u64 hit = 0, world = 0, probes = 0;
  // lighting-shadows essai 6 : chaque sonde ne mesure plus qu'UNE famille (rotation 1..4), donc
  // `shadow_actor_px`/`shadow_probe_world_px` (au-dessus) restent ceux de la famille sondee CETTE
  // image ; les cumuls PAR famille vivent ici (0 inutilise, 1 tfrag, 2 tie, 3 shrub, 4 merc).
  u64 fam_hit[5] = {0, 0, 0, 0, 0};
  u64 fam_world[5] = {0, 0, 0, 0, 0};
  u64 fam_probes[5] = {0, 0, 0, 0, 0};
  GLenum last_gl_error = GL_NO_ERROR;
};
ShadowProofState& shadow_proof_state() {
  static ShadowProofState s;
  return s;
}
}  // namespace

void pbr_shadow_ensure_resources() {
  auto& st = pbr_shadow_state();
  // lighting-shadows partie B : taille DESIREE (reglage joueur, palier plateforme si Auto ou hors
  // bornes), bornee par GL_MAX_TEXTURE_SIZE comme avant. Cascades/half sont desormais relus a
  // chaque image (voir plus bas) : ici on ne fixe que ce qui commande l'ALLOCATION GPU.
  int desired_size = Gfx::recharged_shadow_atlas_px();
  {
    const GLint max_tex = gl_query_census::limit(GL_MAX_TEXTURE_SIZE);
    if (max_tex > 0 && desired_size > max_tex) {
      desired_size = max_tex;
    }
  }

  const bool have_resources = st.fbo[0] || st.depth_tex[0];
  if (have_resources && desired_size == st.size) {
    return;  // deja alloue a la bonne taille
  }
  const int fallback_size = have_resources ? st.size : 0;

  gl_query_census::Armed _ap("pbr-shadow-resources");
  GLint prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0};
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev_fbo);
  glGetIntegerv(GL_VIEWPORT, prev_vp);

  if (have_resources) {
    // La taille voulue a change (reglage joueur) : detruit proprement l'atlas principal avant de
    // le recreer. L'atlas acteur de preuve (shadow_proof_state) se recree tout seul : sa garde
    // compare deja `sp.actor_size != st.size`.
    glDeleteFramebuffers(2, st.fbo);
    glDeleteTextures(2, st.depth_tex);
    st.fbo[0] = 0; st.fbo[1] = 0;
    st.depth_tex[0] = 0; st.depth_tex[1] = 0;
  }
  while (glGetError() != GL_NO_ERROR) {
  }

  // lighting-shadows partie B : en cas d'echec d'allocation, retombe sur la taille PRECEDENTE
  // (si on en avait une valide) plutot que de toujours viser 2048 — un reglage 8192 qui echoue
  // sur un moteur deja a 4096 ne doit pas redescendre plus bas que necessaire. Boucle NON
  // recursive : au plus deux tentatives (desired_size, puis le repli).
  const int retry_size = (fallback_size > 0 && fallback_size < desired_size) ? fallback_size : 2048;
  int try_size = desired_size;
  for (int attempt = 0; attempt < 2; attempt++) {
    st.size = try_size;
    st.tile_px = st.size / 2;
    st.valid = true;
    for (int i = 0; i < 2; i++) {
      glGenTextures(1, &st.depth_tex[i]);
      glBindTexture(GL_TEXTURE_2D, st.depth_tex[i]);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT16, st.size, st.size, 0,
                   GL_DEPTH_COMPONENT, GL_UNSIGNED_SHORT, nullptr);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_NONE);

      glGenFramebuffers(1, &st.fbo[i]);
      glBindFramebuffer(GL_FRAMEBUFFER, st.fbo[i]);
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, st.depth_tex[i],
                              0);
      GLenum none = GL_NONE;
      glDrawBuffers(1, &none);
      glReadBuffer(GL_NONE);

      if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
        lg::error("lighting-shadows: atlas FBO incomplet; ombres portees desactivees");
        st.valid = false;
      } else {
        glViewport(0, 0, st.size, st.size);
#ifdef __ANDROID__
        glClearDepthf(1.0f);
#else
        glClearDepth(1.0);
#endif
        glClear(GL_DEPTH_BUFFER_BIT);
      }
    }

    if (glGetError() == GL_NO_ERROR || try_size <= retry_size || attempt == 1) {
      break;
    }
    lg::warn("lighting-shadows: atlas {}x{} alloc failed; repli sur {}", try_size, try_size,
             retry_size);
    glDeleteFramebuffers(2, st.fbo);
    glDeleteTextures(2, st.depth_tex);
    st.fbo[0] = 0; st.fbo[1] = 0;
    st.depth_tex[0] = 0; st.depth_tex[1] = 0;
    try_size = retry_size;
  }

  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
  glBindTexture(GL_TEXTURE_2D, 0);
}

int pbr_shadow_caster_mask(u64 frame_idx) {
  static u64 s_mask_frame = ~0ull;
  static int s_mask = 7;
  if (frame_idx != s_mask_frame) {
    s_mask_frame = frame_idx;
    s_mask = 7;
#ifdef __ANDROID__
    char v[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.pbr.castermask", v) > 0 && v[0]) {
      s_mask = atoi(v);
    }
#else
    if (const char* e = std::getenv("OG_PBR_CASTER_MASK")) {
      s_mask = std::atoi(e);
    }
#endif
  }
  return s_mask;
}

// Tuile t : x in [(t&1)*tile_px, +tile_px), y in [(t>>1)*tile_px, +tile_px).
static void pbr_shadow_tile_viewport(const PbrShadowState& st, int t, int out4[4]) {
  out4[0] = (t & 1) * st.tile_px;
  out4[1] = (t >> 1) * st.tile_px;
  out4[2] = st.tile_px;
  out4[3] = st.tile_px;
}

bool pbr_shadow_write_ready(u64 frame_idx) {
  auto& st = pbr_shadow_state();
  return st.valid && st.have_mvp && st.frame == frame_idx;
}

bool pbr_shadow_bind_write_tile(int tile) {
  auto& st = pbr_shadow_state();
  if (!st.valid || tile < 0 || tile >= kShadowTiles || !st.tile_on[tile]) {
    return false;
  }
  int vp[4];
  pbr_shadow_tile_viewport(st, tile, vp);
  glBindFramebuffer(GL_FRAMEBUFFER, st.fbo[st.write]);
  glViewport(vp[0], vp[1], vp[2], vp[3]);
  glDisable(GL_SCISSOR_TEST);
  return true;
}

const float* pbr_shadow_merc_mvp(int tile) {
  auto& st = pbr_shadow_state();
  if (tile < 0 || tile >= kShadowTiles || !st.tile_on[tile] || !st.merc_mvp_valid[tile]) {
    return nullptr;
  }
  return st.merc_mvp[tile];
}

bool pbr_shadow_view_to_world(const float view[3], float out_world[3]) {
  auto& st = pbr_shadow_state();
  float inv[16];
  if (!pbr_mat_inverse(st.cam_rot, inv)) {
    return false;
  }
  for (int r = 0; r < 3; r++) {
    out_world[r] = inv[0 * 4 + r] * view[0] + inv[1 * 4 + r] * view[1] + inv[2 * 4 + r] * view[2] +
                   inv[3 * 4 + r];
  }
  return true;
}

void pbr_shadow_note_cast(u32 cls, u64 indices) {
  auto& st = pbr_shadow_state();
  int idx = (cls == kShadowCastTfrag) ? 0 : (cls == kShadowCastTie) ? 1
            : (cls == kShadowCastShrub) ? 2 : (cls == kShadowCastMerc) ? 3 : -1;
  if (idx < 0) {
    return;
  }
  st.class_idx[idx] += indices;
  if (indices > 0) {
    st.class_mask_frame |= cls;
    st.class_mask_run |= cls;
  }
}

bool pbr_shadow_merc_cast_enabled(u64 frame_idx) {
  return pbr_shadow_write_ready(frame_idx) && autoport_proof::armed_for("lighting-shadows") &&
        Gfx::recharged_actor_shadow_mode() == 0;
}

float pbr_shadow_actor_dist_m() {
  return Gfx::recharged_actor_shadow_dist_m();
}

bool pbr_shadow_read_has_actors() {
  auto& st = pbr_shadow_state();
  return st.valid && (st.read_class_mask & kShadowCastMerc) != 0;
}

float pbr_shadow_read_range_m() {
  auto& st = pbr_shadow_state();
  return st.half[st.cascades > 0 ? st.cascades - 1 : 2];
}

float pbr_shadow_actor_cutoff_m() {
  if (!pbr_shadow_read_has_actors()) {
    return 0.f;
  }
  return std::min(pbr_shadow_actor_dist_m(), 0.9f * pbr_shadow_read_range_m());
}

// lighting-shadows, partie A : frontiere partagee atlas/aplat, lue par le thread GOAL depuis
// bones.gc via pc-actor-shadow-blob-skip?. Ecrite une fois par image sur le thread de rendu.
static std::atomic<float> g_actor_blob_cutoff_m{0.f};

float pbr_shadow_actor_blob_cutoff_m_threadsafe() {
  return g_actor_blob_cutoff_m.load(std::memory_order_relaxed);
}

static std::atomic<u64> g_blob_drawn_cur{0};
static std::atomic<u64> g_blob_skipped_cur{0};
static std::atomic<u64> g_blob_drawn_total{0};
static std::atomic<u64> g_blob_skipped_total{0};
static std::atomic<u64> g_actor_shadow_frames_swapped{0};

void pbr_actor_blob_note(bool skipped) {
  if (skipped) {
    g_blob_skipped_cur.fetch_add(1, std::memory_order_relaxed);
    g_blob_skipped_total.fetch_add(1, std::memory_order_relaxed);
  } else {
    g_blob_drawn_cur.fetch_add(1, std::memory_order_relaxed);
    g_blob_drawn_total.fetch_add(1, std::memory_order_relaxed);
  }
}

void pbr_actor_blob_frame_end(u64 frame_idx, u64 blob_tris) {
  const u64 drawn = g_blob_drawn_cur.exchange(0, std::memory_order_relaxed);
  const u64 skipped = g_blob_skipped_cur.exchange(0, std::memory_order_relaxed);
  const int mode = Gfx::recharged_actor_shadow_mode();
  const u64 atlas_draws = pbr_shadow_atlas_draws_cast();
  if (mode == 0 && skipped > 0 && atlas_draws > 0) {
    g_actor_shadow_frames_swapped.fetch_add(1, std::memory_order_relaxed);
  }
  if (frame_idx % 60 == 0) {
    autoport_proof::publish("actor_shadow_mode", (u64)mode);
    autoport_proof::publish("actor_shadow_blob_drawn", drawn);
    autoport_proof::publish("actor_shadow_blob_skipped", skipped);
    autoport_proof::publish("actor_shadow_blob_tris", blob_tris);
    autoport_proof::publish("actor_shadow_atlas_draws", atlas_draws);
    autoport_proof::publish("actor_shadow_cutoff_cm",
                            (u64)(pbr_shadow_actor_blob_cutoff_m_threadsafe() * 100.f));
    autoport_proof::publish("actor_shadow_blob_drawn_total",
                            g_blob_drawn_total.load(std::memory_order_relaxed));
    autoport_proof::publish("actor_shadow_blob_skipped_total",
                            g_blob_skipped_total.load(std::memory_order_relaxed));
    autoport_proof::publish("actor_shadow_frames_swapped",
                            g_actor_shadow_frames_swapped.load(std::memory_order_relaxed));
  }
}

bool pbr_shadow_actor_prep_frame(u64 frame_idx) {
  auto& sp = shadow_proof_state();
  return autoport_proof::feature_is("lighting-shadows") && sp.frame == frame_idx && sp.prep_frame;
}

bool pbr_shadow_bind_actor_tile(int tile) {
  auto& sp = shadow_proof_state();
  auto& st = pbr_shadow_state();
  if (!sp.prep_frame || !sp.actor_valid || tile < 0 || tile >= kShadowTiles || !st.tile_on[tile]) {
    return false;
  }
  int vp[4];
  pbr_shadow_tile_viewport(st, tile, vp);
  glBindFramebuffer(GL_FRAMEBUFFER, sp.actor_fbo);
  glViewport(vp[0], vp[1], vp[2], vp[3]);
  glDisable(GL_SCISSOR_TEST);
  return true;
}

// ── (A2) QUEL ASTRE PORTE QUOI ────────────────────────────────────────────────────────────────
// SPEC §3.4/§4.8 : deux astres, deux ombres, AUCUNE attribution ni fondu — chacun a sa propre
// tuile (les cascades pour le dominant, la tuile 3 pour le second), active selon sa hauteur et
// son poids, sans jamais fondre l'un dans l'autre.
// ── lighting-regimes (SPEC §3.2, §3.3, §4.11) : LA CLE N'EST PAS TOUJOURS UN SOLEIL ────────────
// LE DEFAUT. La direction de la lumiere cle etait ECRASEE, a chaque image ou le soleil du ciel est
// au-dessus de l'horizon, par la position de ce soleil (`recharged_pbr_sky_sun`) — sans regarder
// si le niveau en MONTRE un. Dans 16 niveaux de jeu sur 20 (pas de ciel, ou `sun-fade = 0` : le
// sprite n'est jamais cree, time-of-day.gc:45), la lumiere venait d'un astre que le joueur ne voit
// pas. Et hors de l'ecrasement, la clé prenait `-direction` du creneau, c'est-a-dire l'OPPOSE de la
// lumiere (`direction` pointe VERS elle : village1 a midi y = +0,966 ; l'outil de bake la prend
// telle quelle et sa decomposition tient) — faute invisible tant que l'ecrasement la recouvrait.
// LA REGLE (SPEC §4.11, a la lettre). La cle est la direction du CRENEAU, interpolee entre les
// deux creneaux actifs par leur poids de morph. Elle n'est remplacee par la position de l'astre
// QUE SI (a) sun-fade > 0, (b) l'astre est au-dessus de l'horizon, (c) l'angle entre les deux est
// sous 30°. Le passage se fait en fondu (t de 0 a 1 entre 30° et 20°, et sur 0,02..0,08 de
// sinus d'elevation) : t > 0 exige les trois conditions, donc aucun ecrasement hors regle, et la
// cle ne saute jamais d'une image a l'autre.
// LE REGIME PILOTE LE DIRECT (§4.11, tableau) : poids direct, rayon de penombre, speculaire, par
// regime, melanges par les poids des deux creneaux ; sun-fade multiplie la part de l'ASTRE.
// L'AUDIT (`regime_sun_override_wrong`) tourne dans les DEUX bras : il recalcule (a)(b)(c) depuis
// les memes entrees et compte les images ou la cle a ete prise a l'astre sans elles. Bras arme :
// zero par la regle ; bras `--off` : l'ancien ecrasement, compte tel qu'il est.
namespace regime {
constexpr const char* kItem = "lighting-regimes";
AUTOPORT_FEATURE_SITE(kItem);

//                             cle   dome  amb.  basse seule source
constexpr float kDirect[6]   = {1.0f, 0.45f, 0.25f, 1.0f, 0.0f, 1.0f};
constexpr float kPenumbra[6] = {1.0f, 4.0f, 3.0f, 2.0f, 1.0f, 1.0f};
constexpr float kSpec[6]     = {1.0f, 0.25f, 0.4f, 1.0f, 0.0f, 1.0f};
constexpr float kCos30 = 0.8660254f;
constexpr float kCos20 = 0.9396926f;
// Contraste directionnel de l'ambiante (SPEC 6.2, « selon niveau ») : la forme du ciel capturee
// est COMPRESSEE vers 1 de ce facteur puis bornee a [0,6 ; 1,4]. Une forme brute de ciel seul vaut
// ~2 vers le haut et ~0 vers le bas : sans compression, toute face tournee vers le bas tombe au noir.
constexpr float kAmbContrast = 0.5f;

struct Frame {
  u64 frame = ~0ull;
  bool armed = false;         // `armed_for(kItem)` ET un regime pousse par GOAL
  PbrV3 slot_key = {0.f, 1.f, 0.f};  // cle du creneau, vers la lumiere
  PbrV3 key = {0.f, 1.f, 0.f};       // cle retenue
  float t = 0.f;              // part de la cle prise a l'astre
  float direct_w = 1.f, penumbra = 1.f, spec_w = 1.f;
  float sun_fade = 1.f;
  float elev = 1.f;           // rampe d'elevation de l'astre (1 tant que le ciel n'est pas pousse)
  float sun_up = -2.f;        // sinus d'elevation de l'astre (-2 tant qu'il n'est pas pousse)
  float slot_lgt[3] = {1.f, 1.f, 1.f};
  int dominant = 0;
  bool matched = false;       // au moins un creneau retrouve dans la table
  // entrees de l'audit, calculees independamment de `t`
  bool cond_a = false, cond_b = false, cond_c = false;
  float slot_sun_cos = -2.f;
};
Frame g_frame;

struct Audit {
  u64 frame = ~0ull;
  u64 audited = 0, wrong = 0, from_astre = 0, from_slot = 0, fade_applied = 0;
  u64 hist[6] = {0, 0, 0, 0, 0, 0};
  u64 hits = 0;
  double cos_sum = 0.0;
  u64 cos_n = 0;
  // essai 2 : SIGNE de la direction envoyee au shader contre chaque creneau cuite qui la compose,
  // et poids direct la nuit sur un niveau a soleil visible.
  u64 dir_frame = ~0ull;
  u64 dir_checked = 0, dir_wrong = 0;
  float dir_dot_min = 2.f;
  u64 night_frames = 0, night_direct_frames = 0;
};
Audit g_audit;

const Frame& frame(u64 frame_idx) {
  Frame& f = g_frame;
  if (f.frame == frame_idx) {
    return f;
  }
  f = Frame();
  f.frame = frame_idx;
  const auto& gs = Gfx::settings();
  f.sun_fade = std::max(0.f, std::min(1.f, gs.recharged_sun_fade));
  // La cle du creneau : les directions de creneau posees par `update-mood-palette` dans l'humeur de
  // chacun des deux niveaux, ponderees par leur morph et par `current-interp`. Une direction de
  // creneau est constante ; seuls les poids avancent (avec l'heure, avec la distance aux niveaux),
  // donc la somme est continue sans lissage.
  float w[4];
  float ws = 0.f;
  for (int i = 0; i < 4; i++) {
    w[i] = std::max(0.f, gs.recharged_regime_w[i]);
    ws += w[i];
  }
  if (gs.recharged_regime_valid && ws > 1e-6f) {
    PbrV3 k = {0.f, 0.f, 0.f};
    float dom_w[6] = {0.f, 0.f, 0.f, 0.f, 0.f, 0.f};
    f.direct_w = f.penumbra = f.spec_w = 0.f;
    f.slot_lgt[0] = f.slot_lgt[1] = f.slot_lgt[2] = 0.f;
    f.matched = true;
    for (int i = 0; i < 4; i++) {
      if (w[i] <= 0.f) {
        continue;
      }
      const float wi = w[i] / ws;
      const float* d = gs.recharged_regime_slot_dir[i];
      k.x += wi * d[0];
      k.y += wi * d[1];
      k.z += wi * d[2];
      const u8 r = std::min<u8>(gs.recharged_regime[i], 5);
      f.direct_w += wi * kDirect[r];
      f.penumbra += wi * kPenumbra[r];
      f.spec_w += wi * kSpec[r];
      dom_w[r] += wi;
      for (int j = 0; j < 3; j++) {
        f.slot_lgt[j] += wi * gs.recharged_regime_slot_lgt[i][j];
      }
      f.matched = f.matched && gs.recharged_regime_matched[i];
    }
    if (pv_dot(k, k) > 1e-8f) {
      f.slot_key = pv_norm(k);
    }
    for (int r = 1; r < 6; r++) {
      if (dom_w[r] > dom_w[f.dominant]) {
        f.dominant = r;
      }
    }
    f.armed = autoport_proof::armed_for(kItem);
  }
  // L'astre et les trois conditions.
  const float* ss = gs.recharged_pbr_sky_sun;
  const float ssl = std::sqrt(ss[0] * ss[0] + ss[1] * ss[1] + ss[2] * ss[2]);
  PbrV3 sun = {0.f, 1.f, 0.f};
  float sun_up = -1.f;
  if (ssl > 1e-3f) {
    sun = {ss[0] / ssl, ss[1] / ssl, ss[2] / ssl};
    sun_up = sun.y;
  }
  f.slot_sun_cos = pv_dot(f.slot_key, sun);
  f.cond_a = f.sun_fade > 0.f;
  f.cond_b = ssl > 1e-3f && sun_up > 0.02f;
  f.cond_c = f.slot_sun_cos > kCos30;
  if (f.armed) {
    f.t = (f.cond_a && f.cond_b && f.cond_c)
              ? rt_smoothstep(0.02f, 0.08f, sun_up) * rt_smoothstep(kCos30, kCos20, f.slot_sun_cos)
              : 0.f;
    const PbrV3 m = {f.slot_key.x + (sun.x - f.slot_key.x) * f.t,
                     f.slot_key.y + (sun.y - f.slot_key.y) * f.t,
                     f.slot_key.z + (sun.z - f.slot_key.z) * f.t};
    f.key = pv_dot(m, m) > 1e-8f ? pv_norm(m) : f.slot_key;
    // sun-fade multiplie la part directe de l'ASTRE, et seulement elle.
    f.direct_w *= 1.f + (f.sun_fade - 1.f) * f.t;
    // LA NUIT (essai 2). La ou un soleil se voit (sun-fade > 0), le direct suit son elevation comme
    // avant la refonte : la rampe (-0,05 .. 0,18) de `u_rt_sun_elev`, 0 quand l'astre est couche.
    // Le creneau de nuit reste la cle (direction, teinte) mais n'eclaire plus en plein. Sans ciel
    // ou sans soleil visible (sun-fade = 0 : lave, grotte, marais), l'heure n'y change rien.
    f.elev = ssl > 1e-3f ? rt_smoothstep(-0.05f, 0.18f, sun_up) : 1.f;
    f.direct_w *= 1.f + (f.elev - 1.f) * f.sun_fade;
  }
  f.sun_up = ssl > 1e-3f ? sun_up : -2.f;
  return f;
}

// Une fois par image, sur le chemin eclaire : `from_astre` dit si la cle retenue vient de l'astre.
void audit(u64 frame_idx, bool from_astre) {
  Audit& a = g_audit;
  if (a.frame == frame_idx) {
    return;
  }
  a.frame = frame_idx;
  const Frame& f = frame(frame_idx);
  a.audited++;
  if (from_astre) {
    a.from_astre++;
    if (!(f.cond_a && f.cond_b && f.cond_c)) {
      a.wrong++;
    }
    if (f.armed && f.sun_fade < 1.f) {
      a.fade_applied++;
    }
  } else {
    a.from_slot++;
  }
  if (f.cond_b && f.slot_sun_cos > -1.5f) {
    a.cos_sum += f.slot_sun_cos;
    a.cos_n++;
  }
  if (f.armed) {
    a.hist[f.dominant]++;
    if (f.matched) {
      a.hits++;
      autoport_proof::note_hit_for(kItem);
    }
  }
  autoport_proof::publish("regime_sun_override_wrong", a.wrong);
  autoport_proof::publish("regime_audited_frames", a.audited);
  autoport_proof::publish("regime_key_from_astre_frames", a.from_astre);
  autoport_proof::publish("regime_key_from_slot_frames", a.from_slot);
  autoport_proof::publish("key_dir_source", from_astre ? 1 : 0);
  autoport_proof::publish("sun_fade_applied", a.fade_applied);
  autoport_proof::publish("regime_read_frames", a.hits);
  for (int i = 0; i < 6; i++) {
    static const char* kHist[6] = {"regime_hist_0", "regime_hist_1", "regime_hist_2",
                                   "regime_hist_3", "regime_hist_4", "regime_hist_5"};
    autoport_proof::publish(kHist[i], a.hist[i]);
  }
  // Temoin de SIGNE : cosinus moyen creneau/astre quand l'astre est leve, decale de +1 (x1000).
  // Un signe faux sur la direction du creneau le ferait tomber franchement sous 1000.
  if (a.cos_n) {
    autoport_proof::publish("regime_slot_sun_cos_p1000",
                            (u64)std::lround((a.cos_sum / a.cos_n + 1.0) * 1000.0));
  }
  autoport_proof::publish("regime_sun_fade_x1000", (u64)std::lround(f.sun_fade * 1000.f));
  autoport_proof::publish("regime_sky", Gfx::settings().recharged_sky ? 1 : 0);
  autoport_proof::publish("regime_dominant", (u64)f.dominant);
}

// essai 2, une fois par image : `dir` = light_dir[0..2], la cle que `u_rt_sun_dir` emporte. Pour
// chaque creneau qui la compose (poids > 0), le produit scalaire avec la direction du creneau telle
// que la table la porte (et que l'outil de bake la prend) doit etre > 0 ; une negation le rendrait
// franchement negatif. Tourne dans les deux bras.
void audit_dir(u64 frame_idx, const float* dir) {
  Audit& a = g_audit;
  if (a.dir_frame == frame_idx) {
    return;
  }
  a.dir_frame = frame_idx;
  const auto& gs = Gfx::settings();
  if (!gs.recharged_regime_valid) {
    return;
  }
  const PbrV3 k = {dir[0], dir[1], dir[2]};
  for (int i = 0; i < 4; i++) {
    if (!(gs.recharged_regime_w[i] > 0.f)) {
      continue;
    }
    const float* d = gs.recharged_regime_slot_dir[i];
    const PbrV3 sd = {d[0], d[1], d[2]};
    if (pv_dot(sd, sd) < 1e-8f) {
      continue;
    }
    const float c = pv_dot(k, pv_norm(sd));
    a.dir_checked++;
    if (!(c > 0.f)) {
      a.dir_wrong++;
    }
    a.dir_dot_min = std::min(a.dir_dot_min, c);
  }
  autoport_proof::publish("regime_dir_sign_checked", a.dir_checked);
  autoport_proof::publish("regime_dir_sign_wrong", a.dir_wrong);
  if (a.dir_dot_min <= 1.5f) {
    autoport_proof::publish("regime_dir_dot_min_p1000",
                            (u64)std::lround((a.dir_dot_min + 1.f) * 1000.f));
  }
}

// essai 2, une fois par image, sur la valeur REELLEMENT poussee dans `u_rt_sun_elev` (apres le
// lissage) : la nuit (astre sous -0,05) sur un niveau sun-fade = 1, elle doit valoir 0.
void audit_night(u64 frame_idx, float uploaded_direct) {
  Audit& a = g_audit;
  const Frame& f = frame(frame_idx);
  if (!f.armed) {
    return;
  }
  static u64 s_frame = ~0ull;
  if (s_frame == frame_idx) {
    return;
  }
  s_frame = frame_idx;
  const bool night = f.sun_fade >= 1.f && f.sun_up < -0.05f && f.sun_up > -1.5f;
  if (night) {
    a.night_frames++;
    if (f.direct_w > 0.f) {
      a.night_direct_frames++;
    }
  }
  autoport_proof::publish("regime_direct_w_x1000", (u64)std::lround(std::max(0.f, uploaded_direct) * 1000.f));
  if (f.sun_up > -1.5f) {
    autoport_proof::publish("regime_sun_up_p1000", (u64)std::lround((f.sun_up + 1.f) * 1000.f));
  }
  autoport_proof::publish("regime_night_frames", a.night_frames);
  autoport_proof::publish("regime_night_direct_frames", a.night_direct_frames);
}

// SPEC §4.10 : la FORME vient du ciel capture (SkyCapture), le NIVEAU et la TEINTE de l'amb-color
// du creneau. Sans ciel (ou avant la premiere capture) : une SH ISOTROPE sur l'amb-color, c'est-a-
// dire aucune forme — les sondes du §4.12 ne sont pas encore cuites.
inline float env_luma(const float c[3]) {
  return (2.f * c[0] + 4.f * c[1] + c[2]) / 7.f;
}
void env_sh(float out[9][3], float strength, u64 frame_idx) {
  const auto& gs = Gfx::settings();
  const float* a = gs.recharged_pbr_lg_valid ? gs.recharged_pbr_lg_ambi : gs.recharged_pbr_ambient;
  float tgt[3];
  for (int k = 0; k < 3; k++) {
    tgt[k] = std::max(0.f, a[k]) * strength;
  }
  constexpr float Y00 = 0.282095f;
  bool measured = gs.recharged_sky && sky_capture::sh(out);
  if (measured) {
    // La DISTRIBUTION est celle de la LUMINANCE du ciel, une seule forme pour les trois canaux :
    // chaque canal vaut forme x amb-color[canal] / moyenne. La moyenne sur la sphere tombe donc
    // EXACTEMENT sur l'amb-color (le niveau ET la teinte sont ceux de la table), et le rapport que
    // le shader forme (SH(N) / moyenne) est le meme sur les trois canaux : le ciel ne teinte rien.
    float shl[9];
    for (int i = 0; i < 9; i++) {
      shl[i] = env_luma(out[i]);
    }
    const float lm = shl[0] * Y00;
    if (lm > 1e-6f) {
      for (int i = 0; i < 9; i++) {
        for (int k = 0; k < 3; k++) {
          out[i][k] = shl[i] * (tgt[k] / lm);
        }
      }
    } else {
      measured = false;
    }
  }
  if (!measured) {
    for (int i = 0; i < 9; i++) {
      out[i][0] = out[i][1] = out[i][2] = 0.f;
    }
    for (int k = 0; k < 3; k++) {
      out[0][k] = tgt[k] / Y00;
    }
  }
  static u64 s_frame = ~0ull;
  static u64 s_measured_frames = 0;
  if (s_frame == frame_idx) {
    return;
  }
  s_frame = frame_idx;
  if (measured) {
    s_measured_frames++;
  }
  float mean[3] = {out[0][0] * Y00, out[0][1] * Y00, out[0][2] * Y00};
  const float lt = env_luma(tgt);
  const double delta = lt > 1e-6f ? std::fabs(env_luma(mean) - lt) / lt : 0.0;
  autoport_proof::publish("env_source", measured ? 1 : 0);
  autoport_proof::publish("env_measured_frames", s_measured_frames);
  autoport_proof::publish("env_amb_tone_delta_ppm", (u64)std::lround(delta * 1e6));
  autoport_proof::publish("sky_capture_bins_seen_now", (u64)sky_capture::bins_seen());
  // Temoin de FORME : irradiance vers le haut / vers le bas (x1000). Isotrope = 1000.
  float up[3], dn[3];
  for (int k = 0; k < 3; k++) {
    const float even = out[0][k] * Y00 - out[6][k] * 0.315392f - out[8][k] * 0.546274f;
    up[k] = even + out[1][k] * 0.488603f;
    dn[k] = even - out[1][k] * 0.488603f;
  }
  const float ld = env_luma(dn);
  if (ld > 1e-6f) {
    autoport_proof::publish("env_sh_up_down_x1000", (u64)std::lround(std::max(0.f, env_luma(up)) / ld * 1000.f));
  }
}
}  // namespace regime

bool regime_sky_capture_wanted() {
  return autoport_proof::armed_for(regime::kItem) && Gfx::settings().recharged_sky &&
         Gfx::lighting_active(true);
}

void pbr_shadow_first_camera(SharedRenderState* rs, const GoalBackgroundCameraData& cam) {
  auto& st = pbr_shadow_state();
  const u64 frame_idx = rs->frame_idx;

  if (!(recharged_gating::on(recharged_gating::kLighting) ||
        recharged_gating::on(recharged_gating::kRtLight)) ||
      !pbr_shadowmap_enabled_for_frame(frame_idx)) {
    st.read_tile_on[0] = st.read_tile_on[1] = st.read_tile_on[2] = st.read_tile_on[3] = false;
    st.have_mvp = false;
    return;
  }
  pbr_shadow_ensure_resources();
  if (!st.valid) {
    return;
  }
  if (st.frame == frame_idx) {
    return;  // deja calcule cette image (plusieurs appels du meme point d'entree)
  }

#ifdef __ANDROID__
  { char v[PROP_VALUE_MAX];
    st.debug = __system_property_get("debug.opengoal.pbr.shadowdbg", v) > 0 && v[0] == '1'; }
#else
  st.debug = std::getenv("OG_PBR_SHADOW_DEBUG") != nullptr;
#endif

  if (prepass::census_lighting_pinned()) {
    prepass::note_lightpin_shadow_skipped();
    return;
  }

  // Bascule/promotion : ce que l'ECRITURE vient de completer devient la LECTURE.
#ifndef __ANDROID__
  // Mise au point de bureau (env OG_SHADOW_ATLAS_STATS=1) : par tuile de l'atlas LU (et de l'atlas
  // acteur), le nombre de texels couverts (profondeur < 0,999) et leur boite englobante. Ce n'est
  // pas une preuve : c'est ce qui dit OU la profondeur des projecteurs atterrit.
  if (std::getenv("OG_SHADOW_ATLAS_STATS") && frame_idx % 300 == 0 && st.read_tile_on[0]) {
    static std::vector<float> s_stats_buf;
    auto buf_last = [&]() -> const std::vector<float>& { return s_stats_buf; };
    auto stats = [&](GLuint fbo, const char* what) {
      auto& buf = s_stats_buf;
      buf.resize((size_t)st.size * st.size);
      GLint pf = 0;
      glGetIntegerv(GL_READ_FRAMEBUFFER_BINDING, &pf);
      glBindFramebuffer(GL_READ_FRAMEBUFFER, fbo);
      glPixelStorei(GL_PACK_ALIGNMENT, 4);
      glReadPixels(0, 0, st.size, st.size, GL_DEPTH_COMPONENT, GL_FLOAT, buf.data());
      glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)pf);
      for (int t = 0; t < kShadowTiles; t++) {
        int vp[4];
        pbr_shadow_tile_viewport(st, t, vp);
        u64 n = 0;
        int x0 = 1 << 30, y0 = 1 << 30, x1 = -1, y1 = -1;
        float mn = 1.f;
        for (int y = 0; y < vp[3]; y++) {
          for (int x = 0; x < vp[2]; x++) {
            float d = buf[(size_t)(vp[1] + y) * st.size + (vp[0] + x)];
            if (d < 0.999f) {
              n++;
              x0 = std::min(x0, x); y0 = std::min(y0, y); x1 = std::max(x1, x); y1 = std::max(y1, y);
              mn = std::min(mn, d);
            }
          }
        }
        lg::info("SHADOW-ATLAS-STATS frame={} {} tile={} on={} covered={} bbox=({},{})-({},{}) min={:.4f}",
                 frame_idx, what, t, (int)st.read_tile_on[t], n, x0, y0, x1, y1, mn);
      }
    };
    stats(st.fbo[st.write], "read");  // pas encore bascule : st.write porte l'image PRECEDENTE ici
    auto& spd = shadow_proof_state();
    if (spd.actor_valid) {
      static std::vector<float> main_copy;
      main_copy = buf_last();
      stats(spd.actor_fbo, "actor");
      // Dans la tuile 1, la ou l'atlas acteur est couvert : profondeur acteur vs profondeur de
      // l'atlas complet (sol + acteur) au MEME texel.
      const auto& act = buf_last();
      int vp[4];
      pbr_shadow_tile_viewport(st, 1, vp);
      u64 n = 0, main_closer = 0, equal = 0;
      double sa = 0, sm = 0;
      for (int y = 0; y < vp[3]; y++) {
        for (int x = 0; x < vp[2]; x++) {
          size_t i = (size_t)(vp[1] + y) * st.size + (vp[0] + x);
          if (act[i] < 0.999f) {
            n++;
            sa += act[i];
            sm += main_copy[i];
            if (main_copy[i] < act[i] - 1e-4f) main_closer++;
            if (std::fabs(main_copy[i] - act[i]) <= 1e-4f) equal++;
          }
        }
      }
      lg::info("SHADOW-ATLAS-CMP frame={} tile=1 actor_texels={} mean_actor={:.4f} mean_main={:.4f} main_closer={} equal={}",
               frame_idx, n, n ? sa / n : 0.0, n ? sm / n : 0.0, main_closer, equal);
    }
  }
#endif
  if (st.have_mvp) {
    for (int t = 0; t < kShadowTiles; t++) {
      memcpy(st.read_tile_mvp[t], st.tile_mvp[t], sizeof(st.read_tile_mvp[t]));
    }
    memcpy(st.read_tile_on, st.tile_on, sizeof(st.read_tile_on));
    memcpy(st.read_texel_world, st.texel_world, sizeof(st.read_texel_world));
    st.read_key_light = st.key_light;
    st.read_class_mask = st.class_mask_frame;
    memcpy(st.read_cam, st.write_cam, sizeof(st.read_cam));
    st.write = 1 - st.write;
  }
  g_actor_blob_cutoff_m.store(
      Gfx::recharged_actor_shadow_mode() == 0 ? pbr_shadow_actor_cutoff_m() : 0.f,
      std::memory_order_relaxed);
  st.have_mvp = false;
  st.class_mask_frame = 0;
  // Les compteurs publies sont ceux de l'image PRECEDENTE, COMPLETE : a ce point de l'image
  // courante, les merc n'ont pas encore dessine (ils tirent dans leurs buckets, plus tard).
  static u64 s_prev_class_idx[4] = {0, 0, 0, 0};
  for (int i = 0; i < 4; i++) {
    s_prev_class_idx[i] = st.class_idx[i];
    st.class_idx[i] = 0;
  }
  for (int t = 0; t < kShadowTiles; t++) st.merc_mvp_valid[t] = false;

  // ---- Quel astre est haut, et lequel domine ----
  const auto& gs = Gfx::settings();
  PbrV3 sun_dir = {0.f, 1.f, 0.f}, moon_dir = {0.f, 1.f, 0.f};
  {
    PbrV3 ss = {gs.recharged_pbr_sky_sun[0], gs.recharged_pbr_sky_sun[1], gs.recharged_pbr_sky_sun[2]};
    float ssl = std::sqrt(pv_dot(ss, ss));
    if (ssl > 1e-4f) sun_dir = {ss.x / ssl, ss.y / ssl, ss.z / ssl};
    PbrV3 gm = {gs.recharged_pbr_green_sun[0], gs.recharged_pbr_green_sun[1], gs.recharged_pbr_green_sun[2]};
    float gml = std::sqrt(pv_dot(gm, gm));
    if (gml > 1e-4f) moon_dir = {gm.x / gml, gm.y / gml, gm.z / gml};
  }
  const float OWN_LO = -0.05f;
  bool sun_up = sun_dir.y > OWN_LO;
  bool moon_up = moon_dir.y > OWN_LO;
  // lighting-regimes (SPEC §4.11) : les cascades de la cle suivent la CLE retenue — le creneau,
  // ou l'astre quand la regle l'autorise — et non plus le soleil du ciel. Une source basse (lave,
  // y < 0) porte des ombres vers le haut : elle est « levee » des qu'elle a un poids direct.
  // Le soleil vert n'est un astre que la ou un astre se voit (sun-fade > 0).
  {
    const auto& rgs = regime::frame(frame_idx);
    if (rgs.armed) {
      sun_dir = rgs.key;
      sun_up = rgs.direct_w > 0.f;
      moon_up = moon_up && rgs.sun_fade > 0.f;
    }
  }
  // lighting-shadows partie B : cascades/distance relues CHAQUE image (le reglage joueur peut
  // changer sans reallocation de l'atlas, qui ne depend que de la taille en pixels).
  st.cascades = Gfx::recharged_shadow_cascades_effective();
  {
    const float D = Gfx::recharged_shadow_dist_m();
    if (st.cascades >= 3) {
      st.half[0] = std::min(8.f, D);
      st.half[1] = std::min(32.f, D);
    } else {
      st.half[0] = std::min(20.f, D);
      st.half[1] = D;
    }
    st.half[2] = D;
    st.half[3] = D;
  }

  int key = 0;
  if (sun_up && moon_up) {
    key = (st.w_moon > st.w_sun) ? 1 : 0;
  } else if (sun_up) {
    key = 0;
  } else if (moon_up) {
    key = 1;
  } else {
    key = 0;  // repli : ni l'un ni l'autre haut, la cascade porte le soleil (invisible, poids ~0)
  }
  st.key_light = key;
  const PbrV3 key_dir = (key == 0) ? sun_dir : moon_dir;
  const bool second_up = (key == 0) ? moon_up : sun_up;
  const PbrV3 second_dir = (key == 0) ? moon_dir : sun_dir;
  const float total_w = st.w_sun + st.w_moon;
  const bool second_on = second_up && total_w > 1e-4f &&
                        ((key == 0) ? st.w_moon : st.w_sun) > 0.05f * total_w &&
                        autoport_proof::armed_for("lighting-shadows") &&
                        Gfx::recharged_shadow_second_on();

  for (int t = 0; t < kShadowTiles; t++) {
    st.tile_on[t] = (t < st.cascades) || (t == 3 && second_on);
  }

  // Distance/z commune : bornee par la cascade la plus large (150).
  const float far_half = st.half[3];
  const float eyed = far_half * 2.0f + 40.0f;
  const float ortho_near = 0.5f;
  const float ortho_far = eyed + far_half + 10.0f;

  const float cmx = cam.trans[0] / 4096.f, cmy = cam.trans[1] / 4096.f, cmz = cam.trans[2] / 4096.f;

  auto build_tile = [&](int t, PbrV3 L) {
    if (!st.tile_on[t]) {
      return;
    }
    L = pv_norm(L);
    if (pv_dot(L, L) < 1e-6f) {
      st.tile_on[t] = false;
      return;
    }
    PbrV3 eye = {L.x * eyed, L.y * eyed, L.z * eyed};
    PbrV3 up = std::fabs(L.y) > 0.95f ? PbrV3{1.f, 0.f, 0.f} : PbrV3{0.f, 1.f, 0.f};
    float view[16];
    pbr_look_at(eye, {0.f, 0.f, 0.f}, up, view);
    const float half = st.half[t];
    const float texel_world = (2.0f * half) / (float)st.tile_px;
    float tx = view[0] * cmx + view[4] * cmy + view[8] * cmz;
    float ty = view[1] * cmx + view[5] * cmy + view[9] * cmz;
    view[12] += tx - std::floor(tx / texel_world) * texel_world;
    view[13] += ty - std::floor(ty / texel_world) * texel_world;
    float proj[16];
    pbr_ortho(-half, half, -half, half, ortho_near, ortho_far, proj);
    pbr_mat_mul(proj, view, st.tile_mvp[t]);
    st.texel_world[t] = texel_world;
  };

  for (int t = 0; t < st.cascades && t < 3; t++) {
    build_tile(t, key_dir);
  }
  build_tile(3, second_dir);

  st.write_cam[0] = cam.trans[0];
  st.write_cam[1] = cam.trans[1];
  st.write_cam[2] = cam.trans[2];
  st.have_mvp = true;
  st.frame = frame_idx;

  // Camera rotation (colonne c = ligne GOAL c), pour view->world des acteurs (Merc2).
  for (int c = 0; c < 4; c++) {
    for (int r = 0; r < 4; r++) {
      st.cam_rot[c * 4 + r] = cam.rot[c][r];
    }
  }
  // Mc = S(1/4096) * T(-write_cam) * inverse(Rgl) : vue GOAL -> monde camera-relatif metres.
  float rinv[16];
  const bool rot_ok = pbr_mat_inverse(st.cam_rot, rinv);
  if (rot_ok) {
    float T[16];
    pbr_mat_identity(T);
    T[12] = -st.write_cam[0]; T[13] = -st.write_cam[1]; T[14] = -st.write_cam[2];
    float TR[16];
    pbr_mat_mul(T, rinv, TR);
    float S[16];
    pbr_mat_identity(S);
    S[0] = S[5] = S[10] = 1.0f / 4096.0f;
    float Mc[16];
    pbr_mat_mul(S, TR, Mc);
    for (int i = 0; i < 16; i++) {
      st.merc_view_to_rel[i] = Mc[i];
    }
    st.merc_view_to_rel_valid = true;
    for (int t = 0; t < kShadowTiles; t++) {
      if (!st.tile_on[t]) {
        continue;
      }
      pbr_mat_mul(st.tile_mvp[t], Mc, st.merc_mvp[t]);
      st.merc_mvp_valid[t] = true;
    }
  } else {
    st.merc_view_to_rel_valid = false;
  }

  // Preuve : nouvelle image -> avance la sonde (avant de dessiner quoi que ce soit dans l'atlas).
  pbr_shadow_proof_frame_begin(frame_idx);

  // ---- Effacement de l'atlas d'ECRITURE (toute l'etendue, pas juste les tuiles actives) ----
  GLint prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0};
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev_fbo);
  glGetIntegerv(GL_VIEWPORT, prev_vp);
  GLboolean prev_depth_mask = GL_TRUE;
  glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);
  glBindFramebuffer(GL_FRAMEBUFFER, st.fbo[st.write]);
  glViewport(0, 0, st.size, st.size);
  glDepthMask(GL_TRUE);
#ifdef __ANDROID__
  glClearDepthf(1.0f);
#else
  glClearDepth(1.0);
#endif
  glClear(GL_DEPTH_BUFFER_BIT);

  // ---- Casters STATIQUES, par tuile active ----
  GLint prev_cull = glIsEnabled(GL_CULL_FACE);
  GLboolean prev_scissor = glIsEnabled(GL_SCISSOR_TEST);
  GLboolean prev_poly_off = glIsEnabled(GL_POLYGON_OFFSET_FILL);
  GLboolean prev_depth_test = glIsEnabled(GL_DEPTH_TEST);
  GLint prev_depth_func = GL_LEQUAL;
  glGetIntegerv(GL_DEPTH_FUNC, &prev_depth_func);
  GLint prev_vao = 0;
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prev_vao);

  const int kind_mask = pbr_shadow_caster_mask(frame_idx);
  glDisable(GL_CULL_FACE);
  glDisable(GL_SCISSOR_TEST);
  glEnable(GL_DEPTH_TEST);
  glDepthMask(GL_TRUE);
  glDepthFunc(GL_LEQUAL);
  glEnable(GL_POLYGON_OFFSET_FILL);
  glPolygonOffset(2.0f, 4.0f);

  for (int t = 0; t < kShadowTiles; t++) {
    if (!st.tile_on[t]) {
      continue;
    }
    int vp[4];
    pbr_shadow_tile_viewport(st, t, vp);
    glViewport(vp[0], vp[1], vp[2], vp[3]);
    uint64_t out_idx[3] = {0, 0, 0};
    prepass::draw_shadow_casters(rs, cam, st.tile_mvp[t], kind_mask, out_idx);
    pbr_shadow_note_cast(kShadowCastTfrag, out_idx[0]);
    pbr_shadow_note_cast(kShadowCastTie, out_idx[1]);
    pbr_shadow_note_cast(kShadowCastShrub, out_idx[2]);
  }

  glBindVertexArray((GLuint)prev_vao);
  glPolygonOffset(0.0f, 0.0f);
  if (!prev_poly_off) glDisable(GL_POLYGON_OFFSET_FILL);
  if (prev_cull) glEnable(GL_CULL_FACE);
  if (prev_scissor) glEnable(GL_SCISSOR_TEST);
  if (!prev_depth_test) glDisable(GL_DEPTH_TEST);
  glDepthMask(prev_depth_mask);
  glDepthFunc(prev_depth_func);
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);

  if (st.debug && frame_idx % 240 == 0) {
    lg::info("PBR-SHADOW-DBG atlas={} tile_px={} cascades={} key={} tiles={}{}{}{} idx=({},{},{})",
             st.size, st.tile_px, st.cascades, st.key_light, (int)st.tile_on[0],
             (int)st.tile_on[1], (int)st.tile_on[2], (int)st.tile_on[3], st.class_idx[0],
             st.class_idx[1], st.class_idx[2]);
  }

  // ── (A8) PUBLICATIONS ─────────────────────────────────────────────────────────────────────
  if (autoport_proof::feature_is("lighting-shadows") && frame_idx % 60 == 0) {
    int popcount = 0;
    for (u32 m = st.class_mask_run; m; m >>= 1) popcount += (m & 1);
    autoport_proof::publish("shadow_caster_classes", (uint64_t)popcount);
    autoport_proof::publish("shadow_caster_class_mask", (uint64_t)st.class_mask_run);
    autoport_proof::publish("shadow_cast_idx_tfrag", s_prev_class_idx[0]);
    autoport_proof::publish("shadow_cast_idx_tie", s_prev_class_idx[1]);
    autoport_proof::publish("shadow_cast_idx_shrub", s_prev_class_idx[2]);
    autoport_proof::publish("shadow_cast_idx_merc", s_prev_class_idx[3]);
    autoport_proof::publish("shadow_lights_active", (uint64_t)(1 + (st.tile_on[3] ? 1 : 0)));
    autoport_proof::publish("shadow_key_light", (uint64_t)st.key_light);
    autoport_proof::publish("shadow_actor_mode", (uint64_t)Gfx::recharged_actor_shadow_mode());
    autoport_proof::publish("shadow_lighting_active", Gfx::recharged_lighting_active() ? 1 : 0);
    autoport_proof::publish("shadow_armed", autoport_proof::armed_for("lighting-shadows") ? 1 : 0);
    autoport_proof::publish("shadow_cascades", (uint64_t)st.cascades);
    for (int c = 0; c < 3; c++) {
      char key[32];
      snprintf(key, sizeof(key), "cascade_texel_world_mm_%d", c);
      autoport_proof::publish(key, (uint64_t)(st.texel_world[c] * 1000.0f + 0.5f));
    }
    autoport_proof::publish("shadow_second_texel_world_mm",
                            (uint64_t)(st.texel_world[3] * 1000.0f + 0.5f));
    autoport_proof::publish("shadow_atlas_bytes",
                            (uint64_t)2 * (uint64_t)st.size * (uint64_t)st.size * 2ull);
    // lighting-shadows partie B : les cinq reglages, publies sans garde `feature_is` comme
    // demande (les autres `shadow_*` ci-dessus le sont deja).
    autoport_proof::publish("shadow_atlas_px", (uint64_t)st.size);
    autoport_proof::publish("shadow_dist_m", (uint64_t)Gfx::recharged_shadow_dist_m());
    autoport_proof::publish("shadow_strength_pct",
                            (uint64_t)(Gfx::recharged_shadow_strength_frac() * 100.f + 0.5f));
    autoport_proof::publish("shadow_second_setting",
                            Gfx::recharged_shadow_second_on() ? 1 : 0);
  }
}

// ── (A5) POIDS DES DEUX ASTRES ──────────────────────────────────────────────────────────────
// Appele depuis first_tfrag_draw_setup une fois les poids finaux connus (voir plus bas).
void pbr_shadow_note_weights(float w_sun, float w_moon) {
  auto& st = pbr_shadow_state();
  st.w_sun = w_sun < 0.f ? 0.f : (w_sun > 1.f ? 1.f : w_sun);
  st.w_moon = w_moon < 0.f ? 0.f : (w_moon > 1.f ? 1.f : w_moon);
}

void pbr_shadow_bind_receiver(GLuint program, const float* cam_trans) {
  auto& st = pbr_shadow_state();
  if (!st.valid) {
    return;
  }
  GLint tex_loc = glu::loc(program, "tex_PBR_SHADOW");
  GLint on_loc = glu::loc(program, "u_pbr_shadow_on");
  GLint cd_loc = glu::loc(program, "u_pbr_shadow_cam_delta");
  GLint tile_mvp_loc = glu::loc(program, "u_shadow_tile_mvp");
  GLint tiles_loc = glu::loc(program, "u_shadow_tiles");
  GLint split_loc = glu::loc(program, "u_shadow_split");
  GLint strength_loc = glu::loc(program, "u_shadow_strength");
  GLint texel_loc = glu::loc(program, "u_shadow_texel");
  GLint tile_px_loc = glu::loc(program, "u_shadow_tile_px");
  GLint key_loc = glu::loc(program, "u_shadow_key");
  GLint proof_loc = glu::loc(program, "u_shadow_proof");
  GLint actor_loc = glu::loc(program, "tex_SHADOW_ACTOR");

  if (tex_loc >= 0) {
    glUniform1i(tex_loc, 9);
  }
  glActiveTexture(GL_TEXTURE9);
  glBindTexture(GL_TEXTURE_2D, st.depth_tex[1 - st.write]);
  // lighting-shadows (A6) : unite 14 pour l'atlas ACTEUR de preuve, libre (verifie : ni 8 ni 9
  // ni 18, seules unites occupees par l'AO d'ecran et les cartes d'ombre/vent dans cet arbre).
  auto& sp = shadow_proof_state();
  glActiveTexture(GL_TEXTURE14);
  GLuint actor_tex = (sp.actor_valid && sp.actor_tex) ? sp.actor_tex : st.depth_tex[1 - st.write];
  glBindTexture(GL_TEXTURE_2D, actor_tex);
  glActiveTexture(GL_TEXTURE0);
  if (actor_loc >= 0) {
    glUniform1i(actor_loc, 14);
  }

  if (tile_mvp_loc >= 0) {
    glUniformMatrix4fv(tile_mvp_loc, kShadowTiles, GL_FALSE, &st.read_tile_mvp[0][0]);
  }
  int mask = 0;
  for (int t = 0; t < kShadowTiles; t++) {
    if (st.read_tile_on[t]) mask |= (1 << t);
  }
  if (tiles_loc >= 0) glUniform1i(tiles_loc, mask);
  if (split_loc >= 0) {
    glUniform4f(split_loc, st.half[0], st.half[1], st.half[2], (float)st.cascades);
  }
  if (strength_loc >= 0) {
    glUniform1f(strength_loc, Gfx::recharged_shadow_strength_frac());
  }
  if (texel_loc >= 0) {
    glUniform4f(texel_loc, st.read_texel_world[0], st.read_texel_world[1], st.read_texel_world[2],
                st.read_texel_world[3]);
  }
  if (tile_px_loc >= 0) glUniform1f(tile_px_loc, (float)st.tile_px);
  if (key_loc >= 0) glUniform1i(key_loc, st.read_key_light);
  if (proof_loc >= 0) {
    int proof_mode = (sp.probe_frame && sp.actor_valid) ? 1 : 0;
#ifndef __ANDROID__
    // Mise au point de bureau (env OG_SHADOW_PROOF_MODE=2) : « acteur » = l'atlas acteur a du contenu
    // a cet endroit, sans comparaison de profondeur. Separe un echantillonneur muet d'une comparaison
    // fausse. Jamais pose par le harnais.
    if (proof_mode == 1) {
      static const int s_mode = std::getenv("OG_SHADOW_PROOF_MODE") ? std::atoi(std::getenv("OG_SHADOW_PROOF_MODE")) : 1;
      proof_mode = s_mode == 2 ? 2 : 1;
    }
#endif
    glUniform1i(proof_loc, proof_mode);
  }
  if (cd_loc >= 0) {
    glUniform3f(cd_loc, (cam_trans[0] - st.read_cam[0]) / 4096.f,
                (cam_trans[1] - st.read_cam[1]) / 4096.f,
                (cam_trans[2] - st.read_cam[2]) / 4096.f);
  }
  if (on_loc >= 0) {
    // Une carte LUE n'existe qu'apres une bascule : sans tuile de cascade lue, aucune ombre
    // (les matrices lues seraient nulles).
    const int shadow_on = (st.valid && (mask & 1)) ? 1 : 0;
    glUniform1i(on_loc, shadow_on);
    lighting_census::gate_shadow(shadow_on);
  }
  if (st.debug) {
    static int dbg_calls = 0;
    if (dbg_calls++ % 240 == 0) {
      lg::info("PBR-SHADOW-DBG bind_receiver prog={} tiles=0x{:x} key={}", program, mask,
               st.read_key_light);
    }
  }
}

float pbr_shadow_read_key_weight() {
  auto& st = pbr_shadow_state();
  return (st.read_key_light == 0) ? st.w_sun : st.w_moon;
}

float pbr_shadow_read_second_weight() {
  auto& st = pbr_shadow_state();
  if (!st.read_tile_on[3]) {
    return 0.f;
  }
  return (st.read_key_light == 0) ? st.w_moon : st.w_sun;
}

PbrMercRegimeCache& pbr_merc_regime_cache() {
  static PbrMercRegimeCache s_cache;
  return s_cache;
}

void pbr_push_merc_regime_uniforms(GLuint program) {
  auto& mc = pbr_merc_regime_cache();
  GLint light_on_loc = glu::loc(program, "u_rt_light_on");
  GLint regime_loc = glu::loc(program, "u_rt_regime");
  GLint sun_loc = glu::loc(program, "u_rt_sun_dir");
  GLint moon_loc = glu::loc(program, "u_rt_moon_dir");
  const int light_on = mc.valid ? mc.light_on : 0;
  if (light_on_loc >= 0) {
    glUniform1i(light_on_loc, light_on);
  }
  if (regime_loc >= 0) {
    glUniform4f(regime_loc, mc.regime[0], mc.regime[1], mc.regime[2], mc.regime[3]);
  }
  if (sun_loc >= 0) {
    glUniform3f(sun_loc, mc.sun_dir[0], mc.sun_dir[1], mc.sun_dir[2]);
  }
  if (moon_loc >= 0) {
    glUniform3f(moon_loc, mc.moon_dir[0], mc.moon_dir[1], mc.moon_dir[2]);
  }
}

bool pbr_shadow_bind_merc_receiver(GLuint program, bool on) {
  GLint on_loc = glu::loc(program, "u_pbr_shadow_on");
  auto& st = pbr_shadow_state();
  const bool ready = on && st.valid && st.merc_view_to_rel_valid;
  if (!ready) {
    if (on_loc >= 0) {
      glUniform1i(on_loc, 0);
    }
    return false;
  }
  // lighting-shadows essai 6 (SPEC §4) : le decalage caméra lu devient write_cam - read_cam,
  // exactement ce que TFragment.cpp:765 passe au decor — `pbr_shadow_bind_receiver` calcule ce
  // decalage a partir du meme `st.write_cam`.
  pbr_shadow_bind_receiver(program, st.write_cam);
  GLint view_to_rel_loc = glu::loc(program, "u_merc_view_to_rel");
  if (view_to_rel_loc >= 0) {
    glUniformMatrix4fv(view_to_rel_loc, 1, GL_FALSE, st.merc_view_to_rel);
  }
  GLint w_loc = glu::loc(program, "u_merc_shadow_w");
  if (w_loc >= 0) {
    glUniform2f(w_loc, pbr_shadow_read_key_weight(), pbr_shadow_read_second_weight());
  }
  pbr_push_merc_regime_uniforms(program);
  // `pbr_shadow_bind_receiver` decide seul si une cascade LUE existe (mask & 1) ; c'est la valeur
  // reelle de u_pbr_shadow_on apres l'appel, pas seulement notre garde `ready`.
  int mask = 0;
  for (int t = 0; t < kShadowTiles; t++) {
    if (st.read_tile_on[t]) mask |= (1 << t);
  }
  return st.valid && (mask & 1) != 0;
}

// ── (A7) PREUVE : ATLAS ACTEUR + SONDE STENCIL/COULEUR ──────────────────────────────────────
// Mesuree seulement sous `autoport_proof::feature_is("lighting-shadows")`. Toutes les 30 images
// (k = frame_idx % 30) : k==29 est l'image de PREPARATION (l'atlas acteur, une texture DEPTH16
// separee de meme geometrie que l'atlas principal, est efface puis les merc y ecrivent AUSSI,
// en plus de l'atlas normal — implementeur B) ; k==0 est l'image de PREUVE, seulement si la
// preparation precedente a reellement tourne.
void pbr_shadow_proof_frame_begin(u64 frame_idx) {
  auto& sp = shadow_proof_state();
  sp.frame = frame_idx;
  if (!autoport_proof::feature_is("lighting-shadows")) {
    sp.prep_frame = false;
    sp.probe_frame = false;
    return;
  }
  const u64 k = frame_idx % 30;
  sp.probe_frame = (k == 0) && sp.prev_prep_ok;
  sp.prep_frame = (k == 29);
  if (!sp.prep_frame && k != 0) {
    sp.prev_prep_ok = false;
  }
  if (sp.prep_frame) {
    auto& st = pbr_shadow_state();
    if (!sp.actor_valid || sp.actor_size != st.size) {
      if (sp.actor_fbo) {
        glDeleteFramebuffers(1, &sp.actor_fbo);
        glDeleteTextures(1, &sp.actor_tex);
        sp.actor_fbo = 0;
        sp.actor_tex = 0;
      }
      glGenTextures(1, &sp.actor_tex);
      glBindTexture(GL_TEXTURE_2D, sp.actor_tex);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT16, st.size, st.size, 0,
                   GL_DEPTH_COMPONENT, GL_UNSIGNED_SHORT, nullptr);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
      glGenFramebuffers(1, &sp.actor_fbo);
      glBindFramebuffer(GL_FRAMEBUFFER, sp.actor_fbo);
      glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, sp.actor_tex, 0);
      GLenum none = GL_NONE;
      glDrawBuffers(1, &none);
      glReadBuffer(GL_NONE);
      sp.actor_valid = glCheckFramebufferStatus(GL_FRAMEBUFFER) == GL_FRAMEBUFFER_COMPLETE;
      sp.actor_size = st.size;
    }
    if (sp.actor_valid) {
      GLint prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0};
      glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev_fbo);
      glGetIntegerv(GL_VIEWPORT, prev_vp);
      GLboolean prev_mask = GL_TRUE;
      glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_mask);
      const GLboolean prev_scis = glIsEnabled(GL_SCISSOR_TEST);
      glBindFramebuffer(GL_FRAMEBUFFER, sp.actor_fbo);
      glViewport(0, 0, sp.actor_size, sp.actor_size);
      // glClear obeit au masque d'ecriture de profondeur et au scissor HERITES : on les ouvre, sinon
      // l'atlas acteur garderait le contenu d'une sonde precedente (ou l'indefini de l'allocation).
      glDepthMask(GL_TRUE);
      glDisable(GL_SCISSOR_TEST);
#ifdef __ANDROID__
      glClearDepthf(1.0f);
#else
      glClearDepth(1.0);
#endif
      glClear(GL_DEPTH_BUFFER_BIT);
      glDepthMask(prev_mask);
      if (prev_scis) glEnable(GL_SCISSOR_TEST);
      glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
      glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
      sp.prev_prep_ok = true;
    } else {
      sp.prev_prep_ok = false;
    }
  }
}

static void ensure_probe_vao(ShadowProofState& sp) {
  if (sp.probe_vao) {
    return;
  }
  glGenVertexArrays(1, &sp.probe_vao);
}

// lighting-shadows essai 6 : familles du STENCIL DE PREUVE. `prepass::world_bucket_family` ne
// connait que tfrag/tie/shrub (1/2/3) ; les seaux MERC opaques de niveau (ropebridge etc.) sont
// AU-DELA de la borne `bucket_id > 30` que la sonde appliquait a tout le monde — on l'etend
// UNIQUEMENT pour ces seaux-la (famille 4), le reste de la porte est inchange.
int pbr_shadow_proof_bucket_family(int bucket_id) {
  using B = jak1::BucketId;
  switch ((B)bucket_id) {
    case B::MERC_TFRAG_TEX_LEVEL0:  // seaux merc des niveaux : les acteurs (ropebridge, PNJ, Jak)
    case B::MERC_TFRAG_TEX_LEVEL1:
    case B::MERC_AFTER_ALPHA:
    case B::MERC_PRIS_LEVEL0:
    case B::MERC_PRIS_LEVEL1:
    case B::MERC_EYES_AFTER_PRIS:
    case B::MERC_AFTER_PRIS:
      return 4;  // merc
    default:
      break;
  }
  if (bucket_id > 30) {
    return 0;
  }
  return prepass::world_bucket_family(bucket_id);  // 0 (non-monde), 1 tfrag, 2 tie, 3 shrub
}

bool pbr_shadow_proof_family_active() {
  return shadow_proof_state().probe_frame;
}

void pbr_shadow_proof_before_bucket(int bucket_id) {
  auto& sp = shadow_proof_state();
  const int fam = pbr_shadow_proof_bucket_family(bucket_id);
  // Un seau <= 30 non-monde pose 0 (comme avant) : sinon il heriterait la famille du seau precedent.
  if (!sp.probe_frame || (bucket_id > 30 && fam == 0)) {
    return;
  }
  glEnable(GL_STENCIL_TEST);
  glStencilMask(0xFF);
  glStencilFunc(GL_ALWAYS, fam, 0xFF);
  glStencilOp(GL_KEEP, GL_KEEP, GL_REPLACE);
}

void pbr_shadow_proof_post_opaque(SharedRenderState* rs) {
  auto& sp = shadow_proof_state();
  if (!sp.probe_frame || !rs) {
    return;
  }
  ensure_probe_vao(sp);
  GLint prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0}, prev_program = 0;
  glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &prev_fbo);
  glGetIntegerv(GL_VIEWPORT, prev_vp);
  glGetIntegerv(GL_CURRENT_PROGRAM, &prev_program);
  GLboolean prev_depth_test = glIsEnabled(GL_DEPTH_TEST);
  GLboolean prev_blend = glIsEnabled(GL_BLEND);
  GLboolean prev_cull = glIsEnabled(GL_CULL_FACE);
  GLboolean prev_scissor = glIsEnabled(GL_SCISSOR_TEST);
  GLboolean prev_color_mask[4] = {GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE};
  glGetBooleanv(GL_COLOR_WRITEMASK, prev_color_mask);
  GLint prev_vao = 0;
  glGetIntegerv(GL_VERTEX_ARRAY_BINDING, &prev_vao);

  const int w = rs->render_fb_w > 0 ? rs->render_fb_w : prev_vp[2];
  const int h = rs->render_fb_h > 0 ? rs->render_fb_h : prev_vp[3];
  if (w <= 0 || h <= 0 || (int64_t)w * h > 3840 * 2160) {
    glDisable(GL_STENCIL_TEST);
    return;
  }

  glDisable(GL_DEPTH_TEST);
  glDisable(GL_BLEND);
  glDisable(GL_CULL_FACE);
  glDisable(GL_SCISSOR_TEST);
  glColorMask(GL_TRUE, GL_TRUE, GL_TRUE, GL_TRUE);
  // lighting-shadows essai 6 : chaque sonde tourne sur UNE famille (1 tfrag, 2 tie, 3 shrub,
  // 4 merc) — le triangle SHADOW_PROBE peint (efface) tout ce qui n'est PAS cette famille, la
  // sonde ne mesure donc plus que les pixels de la famille rotative CETTE image.
  const int fam = 1 + (int)(sp.probes % 4);
  glEnable(GL_STENCIL_TEST);
  glStencilMask(0x00);
  glStencilFunc(GL_NOTEQUAL, fam, 0xFF);
  glStencilOp(GL_KEEP, GL_KEEP, GL_KEEP);

  glViewport(0, 0, w, h);
  const auto& sh = rs->shaders[ShaderId::SHADOW_PROBE];
  sh.activate();
  glBindVertexArray(sp.probe_vao);
  glDrawArrays(GL_TRIANGLES, 0, 3);

  // Instantane sans MSAA pour la relecture (blit vers un FBO couleur mono-echantillon).
  if (!sp.probe_fbo || sp.probe_w != w || sp.probe_h != h) {
    if (sp.probe_fbo) {
      glDeleteFramebuffers(1, &sp.probe_fbo);
      glDeleteTextures(1, &sp.probe_tex);
    }
    glGenTextures(1, &sp.probe_tex);
    glBindTexture(GL_TEXTURE_2D, sp.probe_tex);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glGenFramebuffers(1, &sp.probe_fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, sp.probe_fbo);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, sp.probe_tex, 0);
    sp.probe_w = w;
    sp.probe_h = h;
  }
  glBindFramebuffer(GL_READ_FRAMEBUFFER, (GLuint)prev_fbo);
  glBindFramebuffer(GL_DRAW_FRAMEBUFFER, sp.probe_fbo);
  glBlitFramebuffer(0, 0, w, h, 0, 0, w, h, GL_COLOR_BUFFER_BIT, GL_NEAREST);

  std::vector<uint8_t> px((size_t)w * h * 4);
  glPixelStorei(GL_PACK_ALIGNMENT, 1);
  glBindFramebuffer(GL_READ_FRAMEBUFFER, sp.probe_fbo);
  glReadBuffer(GL_COLOR_ATTACHMENT0);
  glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, px.data());
  const GLenum rd_err = glGetError();
  sp.last_gl_error = rd_err;

  u64 hit = 0, world = 0, blue = 0, cyan = 0;
  if (rd_err == GL_NO_ERROR) {
    for (size_t i = 0; i < px.size(); i += 4) {
      const uint8_t r = px[i], g = px[i + 1], b = px[i + 2];
      // L'hote applique son brouillard APRES shade() : les drapeaux arrivent melanges a la couleur
      // de brouillard. On tranche donc sur l'ECART entre canaux (magenta : R et B au-dessus de G ;
      // vert : G au-dessus de R et B), pas sur des valeurs pures. Le noir (non-decor) ne passe ni
      // l'un ni l'autre.
      const int ri = r, gi = g, bi = b;
      const bool is_hit = ri > gi + 40 && bi > gi + 40;
      const bool is_blue = bi > ri + 40 && bi > gi + 40;                    // ombre du decor
      const bool is_cyan = gi > ri + 40 && bi > ri + 40 && !is_blue && std::abs(gi - bi) < 60;
      const bool is_world =
          is_hit || is_blue || is_cyan || (gi > ri + 40 && gi > bi + 40);
      if (is_blue) blue++;
      if (is_cyan) cyan++;
      if (is_hit) hit++;
      if (is_world) world++;
    }
  }
  sp.hit = hit;
  sp.world = world;
  sp.fam_hit[fam] += hit;
  sp.fam_world[fam] += world;
  sp.fam_probes[fam] += 1;
#ifndef __ANDROID__
  // Mise au point de bureau seulement (env OG_SHADOW_PROBE_DUMP=<fichier.ppm>) : le tampon RELU de la
  // premiere sonde, brut. Ce n'est pas une preuve : c'est ce qui permet de compter a la main ce que
  // le compteur a vu.
  if (const char* dump = std::getenv("OG_SHADOW_PROBE_DUMP")) {
    static bool s_dumped = false;
    if (!s_dumped && rd_err == GL_NO_ERROR && sp.probes >= 3) {
      s_dumped = true;
      if (FILE* f = fopen(dump, "wb")) {
        fprintf(f, "P6\n%d %d\n255\n", w, h);
        for (size_t i = 0; i < px.size(); i += 4) {
          fwrite(&px[i], 1, 3, f);
        }
        fclose(f);
      }
    }
  }
#endif
  sp.probes++;
  // `hits` = pixels de sol ombres par un acteur (SPEC §7.2), cumules sur toutes les sondes.
  autoport_proof::note_hit_for("lighting-shadows", hit);

  glClearStencil(0);
  glDisable(GL_SCISSOR_TEST);
  glStencilMask(0xFF);
  glClear(GL_STENCIL_BUFFER_BIT);
  glDisable(GL_STENCIL_TEST);

  glBindVertexArray((GLuint)prev_vao);
  glUseProgram((GLuint)prev_program);
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
  glColorMask(prev_color_mask[0], prev_color_mask[1], prev_color_mask[2], prev_color_mask[3]);
  if (prev_depth_test) glEnable(GL_DEPTH_TEST);
  if (prev_blend) glEnable(GL_BLEND);
  if (prev_cull) glEnable(GL_CULL_FACE);
  if (prev_scissor) glEnable(GL_SCISSOR_TEST);

  {  // une sonde toutes les 30 images : on publie chacune. Depuis essai 6, une sonde ne mesure
    // plus qu'UNE famille (rotation ci-dessus) : `shadow_actor_px` est desormais celui de la
    // famille sondee CETTE image, pas la somme des quatre.
    autoport_proof::publish("shadow_actor_px", sp.hit);
    autoport_proof::publish("shadow_probe_world_px", sp.world);
    autoport_proof::publish("shadow_probe_static_px", blue);
    autoport_proof::publish("shadow_probe_disagree_px", cyan);
    autoport_proof::publish("shadow_probes", sp.probes);
    autoport_proof::publish("shadow_probe_gl_error", (uint64_t)sp.last_gl_error);
    static const char* const kFamNames[5] = {"", "tfrag", "tie", "shrub", "merc"};
    autoport_proof::publish("shadow_recv_hit_tfrag", sp.fam_hit[1]);
    autoport_proof::publish("shadow_recv_hit_tie", sp.fam_hit[2]);
    autoport_proof::publish("shadow_recv_hit_shrub", sp.fam_hit[3]);
    autoport_proof::publish("shadow_recv_hit_merc", sp.fam_hit[4]);
    autoport_proof::publish("shadow_recv_world_tfrag", sp.fam_world[1]);
    autoport_proof::publish("shadow_recv_world_tie", sp.fam_world[2]);
    autoport_proof::publish("shadow_recv_world_shrub", sp.fam_world[3]);
    autoport_proof::publish("shadow_recv_world_merc", sp.fam_world[4]);
    autoport_proof::publish("shadow_recv_probes_tfrag", sp.fam_probes[1]);
    autoport_proof::publish("shadow_recv_probes_tie", sp.fam_probes[2]);
    autoport_proof::publish("shadow_recv_probes_shrub", sp.fam_probes[3]);
    autoport_proof::publish("shadow_recv_probes_merc", sp.fam_probes[4]);
    u64 families_hit = 0;
    std::string zero_names;
    for (int f = 1; f <= 4; f++) {
      if (sp.fam_hit[f] > 0) {
        families_hit++;
      } else if (sp.fam_world[f] > 0) {
        if (!zero_names.empty()) {
          zero_names += ",";
        }
        zero_names += kFamNames[f];
      }
    }
    autoport_proof::publish("shadow_recv_families_hit", families_hit);
    autoport_proof::publish_text("shadow_recv_families_zero",
                                 zero_names.empty() ? "-" : zero_names.c_str());
  }
}

// ROUND 22 (owner defect A step 1 — MEASURE the coverage before porting anything). The PBR debug
// selector used to be a LOCAL inside first_tfrag_draw_setup, so only the four background programs
// that go through that setup could be told which debug mode is active. The new per-pixel coverage
// modes (30 = program tag, 31 = displacement tag) have to reach hfrag/merc2/generic/emerc too, so
// the computation is hoisted here verbatim.
// Semantics are IDENTICAL to the old inline code: default 0 (= normal render), overridden by the
// android prop debug.opengoal.pbr.debug or, on desktop, by OG_PBR_DEBUG. Deliberately NOT cached —
// the old code re-read the prop on every first_tfrag_draw_setup call (~5x/frame) and a setprop
// therefore took effect on the next frame; caching would silently change that. The new callers are
// per-level-bucket (a handful per frame), so the cost is in the same class as before.
int pbr_debug_mode() {
  int pbr_debug = 0;
#ifdef __ANDROID__
  char v[PROP_VALUE_MAX];
  if (__system_property_get("debug.opengoal.pbr.debug", v) > 0) {
    pbr_debug = atoi(v);
  }
#else
  if (const char* e = getenv("OG_PBR_DEBUG")) {
    pbr_debug = atoi(e);
  }
#endif
  return pbr_debug;
}

// Push u_pbr_debug onto an arbitrary program. Programs that do not declare the uniform yield
// location -1, and glUniform1i(-1, ...) is a documented no-op, so this is safe everywhere.
// Requires `program` to be the ACTIVE program (glUseProgram) — every caller pushes it right after
// its own .activate().
void pbr_push_debug_tag(GLuint program) {
  glUniform1i(glu::loc(program, "u_pbr_debug"), pbr_debug_mode());
}

// ── gl-uniforms-off-cost ─────────────────────────────────────────────────────────────────────
// LE DEFAUT MESURE. `first_tfrag_draw_setup` poussait ses 70 uniformes de la famille ECLAIRAGE
// SANS AUCUNE CONDITION, y compris quand l'ECLAIRAGE RECHARGE est ETEINT. Dans cet etat les
// quatre portes que les shaders consultent valent toutes zero et rien ne peut les relever :
//   u_rt_light_on   `Gfx::lighting_active(...)` le met a 0 ; `rt-light` a le meme parent.
//   u_pbr_shadow_on le receveur n'est meme pas APPELE : ses trois appelants le gardent derriere
//                   `recharged_gating::on(kLighting) || on(kRtLight)` (TFragment.cpp, Tie3.cpp,
//                   Shrub.cpp).
// Aucune des valeurs poussees n'est donc lue par un chemin actif du shader, et le processeur
// payait 54 recherches de nom + 54 appels de pilote PAR HOTE ET PAR IMAGE pour rien.
//
// CE QUI CONTINUE D'ETRE POUSSE, ETEINT (`lgt_keep_1i`) — et pourquoi :
//   * les PORTES elles-memes (u_pbr_shadow_on, u_rt_light_on) : ne PAS les pousser
//     laisserait le programme sur la valeur ALLUMEE de l'image precedente et rallumerait
//     l'eclairage. Un uniforme est un etat de programme. (Les portes et les unites de texture de
//     la pile de MATERIAUX ont disparu avec elle — lighting-legacy-purge.)
//   * l'unite de texture de la carte d'ombres : une unite non posee retombe a 0, deux
//     echantillonneurs sur la meme unite est le piege de completude connu de cet arbre.
//   * u_pbr_debug : tfrag3.frag le lit HORS de toute porte d'eclairage (les modes de recensement
//     de couverture 30/31).
//
// LE COMPTEUR N'EST PAS UN MIROIR DE LA GARDE. Il est incremente DANS le wrapper qui fait
// l'appel GL, pas au point de decision : un site d'eclairage qui echapperait a la garde serait
// COMPTE et ferait ECHOUER `uniform_off_pushes == 0`. Temoin INDEPENDANT, produit par un module
// que cet item ne touche pas : `uniform_lookup_hits_per_frame` (gl_uniform_cache.cpp) — toute
// poussee passe par `glu::loc`, donc sa chute mesure la meme chose par un autre chemin.
namespace lgt {
struct Census {
  bool measured = false;  // le harnais mesure CET item (les DEUX bras de l'ablation)
  bool own = false;       // le harnais mesure gl-uniforms-off-cost LUI-MEME, pas un voisin
  bool armed = false;     // notre correctif est-il arme ? (`armed_for`, jamais `armed`)
  bool lit = false;       // regime de l'appel en cours
  uint64_t pushes_off = 0, pushes_on = 0, skipped_off = 0;
  uint64_t kept_off = 0, kept_on = 0;
  uint64_t setups_off = 0, setups_on = 0;
  uint64_t ns_off = 0, ns_on = 0;
  // Le livrable demande le compte PAR IMAGE, pas par appel : `first_tfrag_draw_setup` tourne
  // une fois par arbre / categorie / niveau, donc plusieurs fois par image et un nombre de fois
  // qui depend du point de vue. On regroupe donc sur `render_state->frame_idx`, l'indice
  // d'image du renderer, jamais sur un compte d'appels suppose.
  uint64_t frames_off = 0, frames_on = 0;
  uint64_t last_frame = ~0ull;
};
inline Census g_c;  // fil GL uniquement

// Compte l'appel GL qui SUIT, dans le regime courant. Les sites SAUTABLES et les sites
// DELIBEREMENT CONSERVES sont comptes SEPAREMENT : melanger les deux rendrait la porte
// `uniform_off_pushes == 0` inatteignable et, surtout, cacherait ce qui reste pousse.
inline void count_push(bool kept) {
  if (!g_c.measured) {
    return;
  }
  if (g_c.lit) {
    (kept ? g_c.kept_on : g_c.pushes_on)++;
  } else {
    (kept ? g_c.kept_off : g_c.pushes_off)++;
  }
}

// Faux = ce site est saute (eclairage eteint ET correctif arme).
inline bool site() {
  if (g_c.lit || !g_c.armed) {
    count_push(false);
    return true;
  }
  if (g_c.measured) {
    g_c.skipped_off++;
  }
  return false;
}
}  // namespace lgt

// Sites SAUTABLES : eclairage eteint, la valeur n'est lue par aucun chemin actif.
inline void lgt_1i(GLuint id, const char* n, GLint a) {
  if (lgt::site()) {
    glUniform1i(glu::loc(id, n), a);
  }
}
inline void lgt_1f(GLuint id, const char* n, GLfloat a) {
  if (lgt::site()) {
    glUniform1f(glu::loc(id, n), a);
  }
}
inline void lgt_2f(GLuint id, const char* n, GLfloat a, GLfloat b) {
  if (lgt::site()) {
    glUniform2f(glu::loc(id, n), a, b);
  }
}
inline void lgt_3f(GLuint id, const char* n, GLfloat a, GLfloat b, GLfloat c) {
  if (lgt::site()) {
    glUniform3f(glu::loc(id, n), a, b, c);
  }
}
inline void lgt_4f(GLuint id, const char* n, GLfloat a, GLfloat b, GLfloat c, GLfloat d) {
  if (lgt::site()) {
    glUniform4f(glu::loc(id, n), a, b, c, d);
  }
}
inline void lgt_3fv(GLuint id, const char* n, GLsizei cnt, const GLfloat* v) {
  if (lgt::site()) {
    glUniform3fv(glu::loc(id, n), cnt, v);
  }
}
// Sites TOUJOURS pousses (portes, unites de texture, lecteurs hors porte) : comptes, jamais sautes.
inline void lgt_keep_1i(GLuint id, const char* n, GLint a) {
  lgt::count_push(true);
  glUniform1i(glu::loc(id, n), a);
}
// Idem, pour le SEUL vecteur conserve : `u_rt_sun_dir`. Les cinq programmes monde le passent a
// `normalize()` SANS AUCUNE GARDE quand ils remplissent `Surface` (etie_base.frag:84,
// tie_wind.frag:83, shrub.frag:77). Ne pas le pousser le laisserait a (0,0,0) au premier
// programme d'une session eclairage-eteint, et `normalize(vec3(0))` rend NaN. Ce NaN n'atteint
// pas l'image — `s.shadow_ndl` n'est lu que sous `u_pbr_shadow_on != 0`, porte tenue a 0 — mais
// fabriquer une classe de valeur qui n'existait pas, sur un pilote Adreno, pour economiser UNE
// poussee sur soixante-dix, est un mauvais marche. C'est la seule exception de ce genre : aucun
// autre uniforme saute n'est divise ni normalise hors garde par un hote.
inline void lgt_keep_3f(GLuint id, const char* n, GLfloat a, GLfloat b, GLfloat c) {
  lgt::count_push(true);
  glUniform3f(glu::loc(id, n), a, b, c);
}

// ── lighting-off-math-still-runs ─────────────────────────────────────────────────────────────
// LE DEFAUT, MESURE PAR L'ITEM PRECEDENT. `gl-uniforms-off-cost` a coupe les POUSSEES, pas les
// CALCULS : eclairage eteint, sa preuve du 10/09 donne `uniform_off_pushes=0` et
// `uniform_off_skipped_per_setup=52`, et pourtant `uniform_setup_ns_per_frame_off=341068` ns —
// 0,34 ms par image, sur 16 appels, a produire des valeurs que PLUS AUCUN chemin actif ne recoit.
// Le gros du reliquat est la projection L2 de l'ambiante procedurale : 256 echantillons de
// Fibonacci, un `sin` et un `cos` chacun, 9 coefficients sur 3 canaux, recalcules a chaque appel.
// Elle tourne alors que ses deux seuls consommateurs (`u_rt_sh[0]`, `u_rt_flat_normal`) sont sautes.
//
// CE QUI REND LA COUPE SURE, et c'est MESURE, pas suppose : une valeur dont le SEUL consommateur
// est une poussee de la famille SAUTABLE est morte des l'instant ou la poussee est sautee —
// `uniform_off_pushes=0` sur 16248 images le dit. Il ne reste donc a examiner que ce qui SORT
// autrement : une poussee CONSERVEE, un global, un recensement, une statique. Chacun est nomme
// ici, et chacun est soit RE-HEBERGE (le regime eteint impose une constante, on l'ecrit
// directement), soit la raison ecrite de GARDER son bloc.
//
// CE QUI SORT DES BLOCS, ET CE QU'ON EN FAIT :
//   `u_rt_sun_dir` (poussee CONSERVEE) — `light_dir[0..2]` part a (0,1,0), sa valeur
//       d'initialisation. Les trois shaders qui le `normalize()` HORS GARDE (etie_base.frag:84,
//       tie_wind.frag:83, shrub.frag:77) ne rangent le resultat que dans `s.shadow_ndl`, lu sous
//       `u_pbr_shadow_on != 0` — porte tenue a 0 ; shade.glsl:269 le lit sous `u_rt_light_on != 0`,
//       a 0 lui aussi. La valeur n'atteint donc aucune image : seule sa NON-DEGENERESCENCE compte
//       (un `normalize(vec3(0))` rendrait NaN sur Adreno), et (0,1,0) est unitaire. C'est un
//       re-hebergement exact, pas une approximation.
//   `u_rt_light_on` (poussee CONSERVEE) — reste 0 SANS calcul : `Gfx::lighting_active(x)` vaut
//       `x && recharged_lighting_active()` (gfx.h:589-591), donc eteint le resultat est 0 quelle
//       que soit l'entree. Les deux lectures d'environnement et le `recharged_gating::on()` qui le
//       precedent ne peuvent pas le relever. `lighting_census::gate_rt_light()` recoit la meme
//       constante, au meme endroit qu'avant.
//   l'enregistrement de la porte de sondes — remonte HORS du bloc d'ambiante : c'etait une
//       constante, elle n'a jamais eu besoin du calcul qui l'entourait. SUPPRIME depuis
//       (census-false-reds, 2026-09-12) : plus aucun shader ne declare cet uniforme.
//   le lissage de transition (EMA attempt-10/11) — ses statiques sortent du corps de la fonction
//       pour pouvoir etre INVALIDEES quand le bloc est saute. Sinon, a la rallumee, l'EMA
//       ramperait pendant ~10 images depuis une valeur vieille de N images : l'a-coup que
//       attempt-10 avait precisement supprime. Invalidees, elles se re-sement sur la valeur brute
//       a la premiere image rallumee, ce qui est exactement le comportement de l'amorcage.
//   `g_pbr_glob_*` et `pbr_cover_publish_gates(...)` — N'EXISTENT PLUS. Les deux sortaient de la
//       pile de matiere, SUPPRIMEE de l'arbre par `lighting-legacy-purge` (2026-09-12). La famille
//       GARDEE, qui n'avait que ces deux blocs, est donc VIDE : `lighting_math_blocks_guarded`
//       publie 0, et `lighting_off_kept_blocks` vaut 0 parce qu'il n'y a plus rien a garder — ce
//       n'est pas un zero de construction, c'est le compte d'une famille dont les deux membres
//       sont partis avec leur code.
namespace lgtmath {

// LES BLOCS. Deux familles, et l'ordre compte : tout ce qui est < `kBlockedCount` appartient a la
// famille BLOQUEE — celle que la porte `lighting_off_math_blocks == 0` juge.
enum Block : int {
  // ── famille BLOQUEE : sortie consommee UNIQUEMENT par des poussees sautables ────────────────
  kSunDir = 0,      // normalisation du vecteur soleil d'ombre (repli du groupe de lumieres)
  kLightGroup,      // les 3 lumieres directes (dir + couleur) + l'override du soleil visible
  kRtGate,          // composition de `u_rt_light_on` et lecture de l'intensite
  kSunColor,        // teinte soleil normalisee puis melangee vers le blanc
  kSunElev,         // elevation du soleil jaune (smoothstep sur la sinusoide d'elevation)
  kGreenSun,        // direction et poids d'elevation du soleil VERT
  kShadowConf,      // confiance de l'ombre portee du soleil proprietaire
  kHandoffEma,      // passe-bas temporel des cinq scalaires de transition
  kFlatNormal,      // lecture du basculement normale plate (mise au point)
  kAmbientSh,       // ambiante hemispherique + PROJECTION L2 (256 echantillons) + normalisation
  // `kPbrAmbient` (couleur d'ambiante PBR) et `kExposure` (`hdr::chain_active()` et le choix
  // d'exposition) ONT QUITTE CETTE TABLE avec les poussees qu'ils entouraient : `u_pbr_ambient` et
  // `u_pbr_exposure` sont partis avec la pile de matiere (lighting-legacy-purge, 2026-09-12). Une
  // legende qui nomme un bloc supprime fait croire a un masque de fuite qu'aucun code ne peut
  // lever. L'exposition, elle, n'est pas perdue : le site unique est `hdr.cpp` (`u_hdr_exposure`).
  kBlockedCount,
  // ── famille GARDEE : sortie consommee AILLEURS, la raison est ecrite ─────────────────────────
  // ELLE EST VIDE DEPUIS lighting-legacy-purge (2026-09-12). Elle n'a jamais eu que deux membres,
  // `kPbrParams` (les surcharges des scalaires de matiere et le clamp de relief) et `kMatGlobals`
  // (`g_pbr_glob_*`, relus par le binder de matiere). Les DEUX blocs, leurs sorties et leur
  // consommateur ont quitte l'arbre avec la pile de matiere : il ne reste rien a garder, et une
  // legende qui nommerait encore ces deux blocs decrirait du code supprime.
  // Le MECANISME reste : un futur bloc dont la sortie est consommee hors de cette fonction se
  // declare ici, apres `kBlockedCount`, et `block()` le comptera dans `kept_*` sans jamais le
  // sauter. Les deux denominateurs sont publies (`lighting_math_blocks_blocked` /
  // `lighting_math_blocks_guarded`), donc le 0 de `lighting_off_kept_blocks` se lit.
  kBlockCount = kBlockedCount
};

struct Census {
  bool measured = false;  // le harnais mesure CET item (les DEUX bras de l'ablation)
  bool armed = false;     // notre correctif est-il arme ? (`armed_for`, jamais `armed`)
  bool lit = false;       // regime de l'appel en cours, fige pour l'image par RechargedFrameScope
  uint64_t ran_off = 0;   // LA PORTE : corps de bloc BLOQUE execute, eclairage eteint
  uint64_t ran_on = 0;
  uint64_t skipped_off = 0;  // LE COMPTE D'AVANT : ce que le defaut executait et qu'on supprime
  uint64_t kept_off = 0, kept_on = 0;
  uint32_t reached_off = 0;  // masque des blocs BLOQUES vraiment ATTEINTS eteint
  uint32_t ran_off_mask = 0;  // masque des blocs BLOQUES qui ont FUITE eteint (nomme le coupable)
};
inline Census g_m;  // fil GL uniquement, comme `lgt::g_c`

// LES STATIQUES DU LISSAGE, sorties du corps de `first_tfrag_draw_setup` — voir l'en-tete.
struct HandoffEma {
  u64 frame = ~0ull;
  float sunelev = 1.0f, moon = 0.0f, conf = 0.0f, ambY = 1.0f, ambG = 0.0f;
  bool seeded = false;
};
inline HandoffEma g_ho;

// Vrai si le corps du bloc doit tourner. LE COMPTEUR N'EST PAS UN MIROIR DE LA GARDE : il est
// incremente ICI, au seul endroit qui decide, et le masque `ran_off_mask` NOMME tout bloc qui
// s'executerait quand meme — une porte a zero qui ne dirait pas QUI a fuite serait un demi-verdict.
inline bool block(int id) {
  if (id >= kBlockedCount) {  // famille GARDEE : jamais sautee, comptee a part
    if (g_m.measured) {
      (g_m.lit ? g_m.kept_on : g_m.kept_off)++;
    }
    return true;
  }
  if (g_m.lit || !g_m.armed) {
    if (g_m.measured) {
      if (g_m.lit) {
        g_m.ran_on++;
      } else {
        g_m.ran_off++;
        g_m.ran_off_mask |= 1u << id;
      }
    }
    return true;
  }
  if (g_m.measured) {
    g_m.skipped_off++;
    g_m.reached_off |= 1u << id;
    // `hits` du VALIDATEUR : il ne compte que sous CET item (`measured`), sinon un item voisin
    // verrait son propre `hits` rempli par un chemin qu'il n'a pas demande.
    autoport_proof::note_hit_for("lighting-off-math-still-runs");
  }
  return false;
}

// Vrai quand le regime allume (ou le bras desarme) autorise un geste qui n'est pas un bloc : le
// vidage de mise au point Android, qui IMPRIMERAIT des valeurs par defaut si les blocs qui les
// produisent ont ete sautes. Ce n'est pas un calcul, il ne consomme donc pas de numero de bloc —
// en consommer un ferait diverger `skipped_per_setup` entre x86 et arm64.
inline bool lit_or_disarmed() {
  return g_m.lit || !g_m.armed;
}

inline uint32_t popcount(uint32_t v) {
  uint32_t n = 0;
  for (; v; v &= v - 1) {
    n++;
  }
  return n;
}
}  // namespace lgtmath

// Ouvre et ferme le recensement d'UN appel de `first_tfrag_draw_setup`. `lit` est lu UNE fois :
// sous `Gfx::RechargedFrameScope` (OpenGLRenderer.cpp:1089) la valeur est deja figee pour toute
// l'image, tous les sites d'un meme appel s'accordent donc. Le chronometre ne tourne QUE sous
// mesure : le binaire de l'owner ne paie pas l'instrument.
struct LgtSetupScope {
  std::chrono::steady_clock::time_point t0;
  explicit LgtSetupScope(uint64_t frame_idx) {
    // lighting-off-math-still-runs : le CHRONOMETRE tourne aussi sous CET item, et sous la MEME
    // grandeur (`uniform_setup_ns_per_frame_off`). C'est la condition pour que les deux mesures se
    // comparent : meme instrument, meme denominateur, meme nom. Le `hits=` de gl-uniforms-off-cost
    // reste, lui, reserve a gl-uniforms-off-cost (`s_own` ci-dessous) — un compteur partage qui
    // monterait sous un autre item rendrait « rien ne prouve que la feature a tire » indeclenchable.
    static const bool s_own = autoport_proof::feature_is("gl-uniforms-off-cost");
    static const bool s_math = autoport_proof::feature_is("lighting-off-math-still-runs");
    static const bool s_measured = s_own || s_math;
    static const bool s_armed = autoport_proof::armed_for("gl-uniforms-off-cost");
    static const bool s_math_armed = autoport_proof::armed_for("lighting-off-math-still-runs");
    auto& c = lgt::g_c;
    c.measured = s_measured;
    c.own = s_own;
    c.armed = s_armed;
    c.lit = Gfx::recharged_lighting_active();
    auto& m = lgtmath::g_m;
    m.measured = s_math;
    m.armed = s_math_armed;
    m.lit = c.lit;
    if (s_measured) {
      if (frame_idx != c.last_frame) {
        c.last_frame = frame_idx;
        (c.lit ? c.frames_on : c.frames_off)++;
      }
      t0 = std::chrono::steady_clock::now();
    }
  }
  ~LgtSetupScope() {
    auto& c = lgt::g_c;
    if (!c.measured) {
      return;
    }
    const uint64_t ns = (uint64_t)std::chrono::duration_cast<std::chrono::nanoseconds>(
                            std::chrono::steady_clock::now() - t0)
                            .count();
    if (c.lit) {
      c.setups_on++;
      c.ns_on += ns;
    } else {
      c.setups_off++;
      c.ns_off += ns;
      if (c.own && c.armed) {
        // `hits` est un compteur PARTAGE : son denominateur propre est `uniform_off_setups`.
        autoport_proof::note_hit_for("gl-uniforms-off-cost");
      }
    }
    // LA PORTE : poussees de la famille SAUTABLE faites alors que l'eclairage est ETEINT.
    autoport_proof::publish("uniform_off_pushes", c.pushes_off);
    autoport_proof::publish("uniform_on_pushes", c.pushes_on);
    autoport_proof::publish("uniform_off_skipped", c.skipped_off);
    // CE QUI RESTE POUSSE, ETEINT, ET QUI N'EST PAS CACHE : les 17 portes / unites de texture /
    // lecteurs hors garde. Une porte a zero qui tairait ce chiffre serait un demi-verdict.
    autoport_proof::publish("uniform_off_kept_pushes", c.kept_off);
    autoport_proof::publish("uniform_on_kept_pushes", c.kept_on);
    autoport_proof::publish("uniform_off_setups", c.setups_off);
    autoport_proof::publish("uniform_on_setups", c.setups_on);
    // LE COMPTE PAR IMAGE que le livrable demande, et le TEMOIN DE COUVERTURE de la porte :
    // `uniform_off_frames` a zero voudrait dire que la course n'est jamais passee par l'etat
    // eteint — `uniform_off_pushes == 0` serait alors vert par INACTION, pas par correction.
    autoport_proof::publish("uniform_off_frames", c.frames_off);
    autoport_proof::publish("uniform_on_frames", c.frames_on);
    autoport_proof::publish("uniform_off_pushes_per_frame",
                            c.frames_off ? c.pushes_off / c.frames_off : 0);
    autoport_proof::publish("uniform_off_skipped_per_frame",
                            c.frames_off ? c.skipped_off / c.frames_off : 0);
    autoport_proof::publish("uniform_off_kept_per_frame",
                            c.frames_off ? c.kept_off / c.frames_off : 0);
    autoport_proof::publish("uniform_on_pushes_per_frame",
                            c.frames_on ? (c.pushes_on + c.kept_on) / c.frames_on : 0);
    autoport_proof::publish("uniform_off_setups_per_frame",
                            c.frames_off ? c.setups_off / c.frames_off : 0);
    // Cout CPU par IMAGE des appels de `first_tfrag_draw_setup`, les deux regimes cote a cote.
    autoport_proof::publish("uniform_setup_ns_per_frame_off",
                            c.frames_off ? c.ns_off / c.frames_off : 0);
    autoport_proof::publish("uniform_setup_ns_per_frame_on",
                            c.frames_on ? c.ns_on / c.frames_on : 0);
    autoport_proof::publish("uniform_off_skipped_per_setup",
                            c.setups_off ? c.skipped_off / c.setups_off : 0);
    autoport_proof::publish("uniform_off_kept_per_setup",
                            c.setups_off ? c.kept_off / c.setups_off : 0);
    autoport_proof::publish("uniform_on_pushes_per_setup",
                            c.setups_on ? (c.pushes_on + c.kept_on) / c.setups_on : 0);
    autoport_proof::publish("uniform_off_pushes_per_setup",
                            c.setups_off ? c.pushes_off / c.setups_off : 0);
    autoport_proof::publish("uniform_setup_ns_off", c.setups_off ? c.ns_off / c.setups_off : 0);
    autoport_proof::publish("uniform_setup_ns_on", c.setups_on ? c.ns_on / c.setups_on : 0);
    // Le regime, publie A COTE de la valeur : un drapeau non epingle, c'est le reglage laisse
    // par un autre item qui decide.
    autoport_proof::publish("uniform_off_gate_armed", c.armed ? 1u : 0u);
    autoport_proof::publish("uniform_regime_lighting", c.lit ? 1u : 0u);
    autoport_proof::publish("uniform_regime_master", Gfx::recharged_master_active() ? 1u : 0u);

    // ── lighting-off-math-still-runs : le recensement des BLOCS DE CALCUL ────────────────────
    // Publie depuis le meme endroit que le recensement des poussees, avec les MEMES
    // denominateurs (`frames_off`, `setups_off`), pour que les deux items se lisent cote a cote.
    const auto& m = lgtmath::g_m;
    if (!m.measured) {
      return;
    }
    // LA PORTE. Un zero obtenu parce que la course n'est JAMAIS passee par l'etat eteint serait
    // un vert par INACTION : sans couverture on publie une SENTINELLE, jamais zero. Le plancher
    // est mesure sur la population NON filtree — les images de la course, pas les blocs.
    const uint64_t kNoCoverage = 9999;
    const bool covered = c.frames_off >= 60 && c.setups_off >= 60;
    autoport_proof::publish("lighting_off_math_blocks", covered ? m.ran_off : kNoCoverage);
    // QUI a fuite, si la porte n'est pas verte : le masque des blocs BLOQUES executes eteint.
    autoport_proof::publish("lighting_off_math_leak_mask", m.ran_off_mask);
    // LE COMPTE D'AVANT, non nul : ce que le defaut executait a chaque appel et qui ne s'execute
    // plus. C'est le pendant exact de `uniform_off_skipped` chez gl-uniforms-off-cost.
    autoport_proof::publish("lighting_off_math_blocks_skipped", m.skipped_off);
    autoport_proof::publish("lighting_off_math_blocks_skipped_per_setup",
                            c.setups_off ? m.skipped_off / c.setups_off : 0);
    autoport_proof::publish("lighting_off_math_blocks_skipped_per_frame",
                            c.frames_off ? m.skipped_off / c.frames_off : 0);
    // TEMOIN DE NON-VACUITE, et le plus important des trois : le nombre de blocs BLOQUES
    // DISTINCTS reellement ATTEINTS eteint. S'il est sous `lighting_math_blocks_blocked`, un bloc
    // n'a jamais ete rencontre et son zero ne prouve rien pour lui.
    autoport_proof::publish("lighting_off_math_blocks_reached",
                            lgtmath::popcount(m.reached_off));
    autoport_proof::publish("lighting_off_math_reached_mask", m.reached_off);
    autoport_proof::publish("lighting_math_blocks_declared", (uint64_t)lgtmath::kBlockCount);
    autoport_proof::publish("lighting_math_blocks_blocked", (uint64_t)lgtmath::kBlockedCount);
    autoport_proof::publish("lighting_math_blocks_kept",
                            (uint64_t)(lgtmath::kBlockCount - lgtmath::kBlockedCount));
    // CE QUI TOURNE ENCORE, ETEINT, ET POURQUOI : la famille GARDEE, comptee separement. Une
    // porte a zero qui tairait ce chiffre cacherait ce qui reste.
    autoport_proof::publish("lighting_off_kept_blocks", m.kept_off);
    autoport_proof::publish("lighting_off_kept_blocks_per_setup",
                            c.setups_off ? m.kept_off / c.setups_off : 0);
    autoport_proof::publish_text("lighting_kept_block_list", "pbr_params,mat_globals");
    // Le bras ALLUME, pour que « 0 eteint » se lise contre un non-zero allume.
    autoport_proof::publish("lighting_on_math_blocks", m.ran_on);
    autoport_proof::publish("lighting_on_math_blocks_per_setup",
                            c.setups_on ? m.ran_on / c.setups_on : 0);
    // Les denominateurs, publies A COTE de la valeur.
    autoport_proof::publish("lighting_math_frames_off", c.frames_off);
    autoport_proof::publish("lighting_math_frames_on", c.frames_on);
    autoport_proof::publish("lighting_math_setups_off", c.setups_off);
    autoport_proof::publish("lighting_math_setups_on", c.setups_on);
    autoport_proof::publish("lighting_math_covered", covered ? 1u : 0u);
    // Le regime, epingle a cote de la valeur : un drapeau non epingle, c'est le reglage laisse
    // par un autre item qui decide.
    autoport_proof::publish("lighting_math_armed", m.armed ? 1u : 0u);
    autoport_proof::publish("lighting_math_regime_lighting", c.lit ? 1u : 0u);
    autoport_proof::publish("lighting_math_regime_master",
                            Gfx::recharged_master_active() ? 1u : 0u);
  }
};
#endif

#ifndef OG_FEAT_PBR
bool regime_sky_capture_wanted() {
  return false;
}
#endif

void first_tfrag_draw_setup(const GoalBackgroundCameraData& settings,
                            SharedRenderState* render_state,
                            ShaderId shader) {
#ifdef OG_FEAT_PBR
  // gl-uniforms-off-cost : ouvre le recensement pour CET appel (voir le bloc `lgt` ci-dessus).
  LgtSetupScope lgt_scope(render_state->frame_idx);
#endif
  const auto& sh = render_state->shaders[shader];
  sh.activate();
  auto id = sh.id();
#ifdef OG_FEAT_PBR
  // lighting-legacy-purge (2026-09-12) : le second argument est parti avec les composites qu'il
  // designait. `legacy_host` disait « cet hote porte AUSSI C et E » ; les deux sont SUPPRIMES de
  // shade.glsl, TFRAG3 n'a plus rien de plus que les trois autres.
  lighting_census::host_paths(shader == ShaderId::TFRAG3 || shader == ShaderId::ETIE_BASE ||
                              shader == ShaderId::TIE_WIND || shader == ShaderId::SHRUB);
#else
  lighting_census::host_paths(false);
#endif
  glUniform1i(glu::loc(id, "gfx_hack_no_tex"), Gfx::settings().hack_no_tex);
  lighting_census::gate_no_tex(Gfx::settings().hack_no_tex);
  glUniform1i(glu::loc(id, "decal"), false);
  glUniform1i(glu::loc(id, "tex_T0"), 0);
  // lighting-ao-indirect : la texture d'AO d'ecran (unite 8) et ses uniformes, pour chaque
  // programme qui inclut shade.glsl (no-op documente sur les autres : location -1).
  prepass::bind_screen_ao(id, render_state);
  // -----------------------------------------------------------------------------------------
  // Grecharged-foliage-wind3 (owner 2026-08-31, defaut D2) — LE VERROU (a) DU BALANCEMENT TIE.
  //
  // `tfrag3.vert` porte le balancement du TIE statique, et il est AUSSI le vertex shader du
  // TERRAIN TFRAG (TFragment.cpp:660, :1249, :1350). Un uniforme reste a sa DERNIERE valeur dans
  // son programme : sans cette ligne, le premier arbre TIE balance laisserait `u_tie_sway_amp`
  // arme et le SOL ONDULERAIT. Le point d'ecriture est donc UNIQUE et il est ici — a chaque
  // activation de programme, pour TOUS les appelants (Tie3 :1120 et :1660, TFragment :660,
  // Shrub :605) — et seul Tie3 le releve, juste apres, sur ses propres passes.
  // Un programme qui ne declare pas l'uniforme rend -1, et glUniform sur -1 est un no-op
  // documente : la ligne est donc sans effet partout ailleurs.
  glUniform1f(glu::loc(id, "u_tie_sway_amp"), 0.0f);
  glUniform1i(glu::loc(id, "u_tie_contact_on"), 0);
  glVertexAttribI4ui(10, 0u, 0u, 0u, 0u);
  glUniform1f(glu::loc(id, "u_tie_sway_time"), 0.0f);
  glUniform2f(glu::loc(id, "u_tie_sway_dir"), 0.7071f, 0.7071f);
  glUniform1f(glu::loc(id, "u_tie_sway_flutter"), 0.0f);
  // VERROU (b), INDEPENDANT du premier. L'attribut 7 (poids + phase de balancement) n'est active
  // que par le VAO du TIE ; celui du TFRAG (TFragment.cpp:443-494) ne l'active pas. La
  // specification OpenGL dit qu'un attribut desactive rend la valeur generique courante, et cette
  // ligne la MET a poids 0 — au lieu de se fier a la valeur par defaut (0,0,0,1), qui est garantie
  // par la spec mais qu'aucune mesure de cet arbre n'a jamais verifiee sur l'Adreno. Deux verrous
  // valent mieux qu'un : celui-ci tient meme si un uniforme etait optimise (loc -1).
  glVertexAttrib4f(7, 0.f, 0.f, 0.f, 1.f);
  // Essai 11 : l'enregistrement de balancement fait 8 octets et trois attributs y pointent — 7 le
  // poids (GL_SHORT), 8 la phase (GL_UNSIGNED_BYTE), 9 l'index d'instance (entier, shrub). Les trois
  // sont mis a zero ici pour tout VAO qui ne les active pas.
  glVertexAttrib4f(8, 0.f, 0.f, 0.f, 1.f);
  glVertexAttribI4ui(9, 0u, 0u, 0u, 0u);
  // lighting-ao-indirect (amendement §4.3) : camera, pc_camera, hvdf_offset, cam_trans,
  // fog_constant/min/max et fog_color vivent dans le bloc ub_frame (frame_ubo.cpp), televerse
  // au changement seulement et lu par les shaders des cinq hotes sous les memes noms.
  frame_ubo::update_and_bind(settings, render_state);

#ifdef OG_FEAT_PBR
  // Round-4 mandate B (shadow map): always advertise the shadow sampler on unit 9 and
  // default u_pbr_shadow_on OFF; pbr_shadow_bind_receiver upgrades it per-renderer. Parking
  // the depth texture on unit 9 here mismatch-proofs every TFRAG3-family user (magenta
  // class) even before/without a receiver bind.
  lgt_keep_1i(id, "tex_PBR_SHADOW", 9);
  lgt_keep_1i(id, "u_pbr_shadow_on", 0);
  lighting_census::gate_shadow(0);
  if (pbr_shadow_state().valid) {
    glActiveTexture(GL_TEXTURE9);
    // Park the READ-side map (the one receivers sample; any complete depth tex works
    // here since u_pbr_shadow_on defaults OFF — this is unit-completeness hardening).
    glBindTexture(GL_TEXTURE_2D,
                  pbr_shadow_state().depth_tex[1 - pbr_shadow_state().write]);
    glActiveTexture(GL_TEXTURE0);
  }
  const auto& gs = Gfx::settings();
  // Sun direction is surface->sun; the GOAL shadow vector is light-travel (sun->surface), so negate.
  // lighting-off-math-still-runs : les valeurs d'initialisation SONT celles de la branche
  // degeneree ci-dessous — bloc saute, `sd`/`sl` restent (0,1,0)/1, exactement ce que le repli du
  // groupe de lumieres produisait deja quand le vecteur d'ombre n'est pas encore pousse.
  float sd[3] = {0.f, 1.f, 0.f};
  float sl = 1.f;
  if (lgtmath::block(lgtmath::kSunDir)) {
    sd[0] = -gs.recharged_pbr_shadow[0];
    sd[1] = -gs.recharged_pbr_shadow[1];
    sd[2] = -gs.recharged_pbr_shadow[2];
    sl = std::sqrt(sd[0] * sd[0] + sd[1] * sd[1] + sd[2] * sd[2]);
    if (sl < 1e-5f) {
      sd[0] = 0.f;
      sd[1] = 1.f;
      sd[2] = 0.f;
      sl = 1.f;
    }
  }
  // The mood tables store sun-color / env-color as 0..255-scale floats (e.g.
  // village1 sun-color (255,128,0)); pushing them raw made lit explode ~100x and
  // clamp to saturated hues. Scale to 0..1 HERE (GL boundary) so GOAL keeps
  // pushing the raw engine values (1:1 pass-through in the pc layer).
  float sun_scale = 1.0f / 255.0f;
  float amb_scale = 1.0f / 255.0f;
  float pbr_shadow_bias = 0.0f;  // debug compare-ref override (see tfrag3.frag)
  // Per-channel isolation viz (critique 2 "prove each map does work"): value semantics
  // documented at the u_pbr_debug uniform in tfrag3.frag. 0 (absent) = normal render.
  // ROUND 22: the prop/env read moved to pbr_debug_mode() above so the non-background renderers
  // (hfrag/merc2/generic/emerc) can be told the same mode. Value is unchanged.
  int pbr_debug = pbr_debug_mode();
#ifdef __ANDROID__
  // Device-tunable calibration for the PoC: debug props override the defaults so
  // exposure/scale can be dialed without a rebuild. Absent props = defaults.
  {
    char v[PROP_VALUE_MAX];
    if (prop_cache::property_get("debug.opengoal.pbr.sunscale", v) > 0) {
      sun_scale = atof(v);
    }
    if (prop_cache::property_get("debug.opengoal.pbr.ambscale", v) > 0) {
      amb_scale = atof(v);
    }
    // (debug.opengoal.pbr.debug is read by pbr_debug_mode() at the pbr_debug initialiser above.)
    if (prop_cache::property_get("debug.opengoal.pbr.shadowbias", v) > 0) {
      pbr_shadow_bias = atof(v);
    }
  }
#else
  // (OG_PBR_DEBUG is read by pbr_debug_mode() at the pbr_debug initialiser above.)
  if (const char* e = prop_cache::env_get("OG_PBR_SHADOWBIAS")) {
    pbr_shadow_bias = atof(e);
  }
#endif
  lgt_keep_1i(id, "u_pbr_debug", pbr_debug);

  // Round-4 multi-light (mandate C): build 3 direct lights from *time-of-day-context*
  // light-group 0 (soleil dir0 + lune verte dir1 + fill dir2). Seule la direction de la
  // lumiere 0 survit a la purge des materiaux : c'est elle que `u_rt_sun_dir` recoit, donc
  // l'ombrage temps reel, le biais de pente de la carte d'ombres et la passe de profondeur
  // s'accordent tous sur la meme position du soleil.
  // lighting-off-math-still-runs : les initialiseurs comptent. `light_dir[0..2]` = (0,1,0) est la
  // valeur que la poussee CONSERVEE `u_rt_sun_dir` emporte quand le bloc est saute : unitaire,
  // donc jamais NaN sous les trois `normalize()` hors garde des shaders monde, et jamais lue
  // puisque `u_rt_light_on` et `u_pbr_shadow_on` valent 0.
  float light_dir[9] = {0.f, 1.f, 0.f, 0.f, 1.f, 0.f, 0.f, 1.f, 0.f};
  if (lgtmath::block(lgtmath::kLightGroup)) {
  if (gs.recharged_pbr_lg_valid) {
    for (int i = 0; i < 3; i++) {
      // lighting-regimes (essai 2) : la direction d'une lumiere de light-group pointe DEJA VERS la
      // lumiere (village1 a midi y = +0,966 ; tools/light_bake/main.cpp:475 la prend telle quelle
      // et sa decomposition tient). L'ancienne negation envoyait la lumiere du cote OPPOSE.
      float d[3] = {gs.recharged_pbr_lg_dir[i][0], gs.recharged_pbr_lg_dir[i][1],
                    gs.recharged_pbr_lg_dir[i][2]};
      float dl = std::sqrt(d[0] * d[0] + d[1] * d[1] + d[2] * d[2]);
      float lvl = gs.recharged_pbr_lg_level[i];
      if (dl < 1e-5f || lvl <= 0.0f) {
        // Degenerate / disabled light: black it out so the shader loop skips it.
        light_dir[i * 3 + 0] = 0.f;
        light_dir[i * 3 + 1] = 1.f;
        light_dir[i * 3 + 2] = 0.f;
      } else {
        light_dir[i * 3 + 0] = d[0] / dl;
        light_dir[i * 3 + 1] = d[1] / dl;
        light_dir[i * 3 + 2] = d[2] / dl;
      }
    }
  } else {
    // Startup fallback (no GOAL push yet): light0 = the single-sun computation above,
    // lights 1/2 black.
    light_dir[0] = sd[0] / sl;
    light_dir[1] = sd[1] / sl;
    light_dir[2] = sd[2] / sl;
    for (int k = 3; k < 9; k++) {
      light_dir[k] = (k % 3 == 1) ? 1.f : 0.f;  // (0,1,0) dirs
    }
  }
  // Round-5 suspect (c) coherence: when the visible-sun dome vector is valid (pushed +
  // above horizon), light 0's DIRECTION follows it — so N.L shading (PBR + mandate-F
  // world relight), the slope bias, and the shadow map all agree on where the sun is.
  // Colors/levels stay the mood light-group's (energy/palette unchanged).
  // lighting-regimes (SPEC §4.11) : sous l'item arme, la cle est celle du REGIME (voir le
  // namespace `regime` plus haut) ; l'ancien ecrasement inconditionnel ne subsiste que dans le
  // bras desarme, et l'audit le compte dans les deux.
  const auto& rgf = regime::frame(render_state->frame_idx);
  if (rgf.armed) {
    light_dir[0] = rgf.key.x;
    light_dir[1] = rgf.key.y;
    light_dir[2] = rgf.key.z;
    regime::audit(render_state->frame_idx, rgf.t > 0.f);
  } else {
    const float* ss = gs.recharged_pbr_sky_sun;
    float ssl = std::sqrt(ss[0] * ss[0] + ss[1] * ss[1] + ss[2] * ss[2]);
    const bool overridden = ssl > 1e-3f && ss[1] / ssl > 0.02f;
    if (overridden) {
      light_dir[0] = ss[0] / ssl;
      light_dir[1] = ss[1] / ssl;
      light_dir[2] = ss[2] / ssl;
    }
    regime::audit(render_state->frame_idx, overridden);
  }
  regime::audit_dir(render_state->frame_idx, light_dir);
  }  // lighting-off-math-still-runs : fin du bloc `kLightGroup`

  // === Grecharged-realtime-lighting (2026-07-19 REWRITE): SUN-ONLY path uniforms. ===
  // Master toggle comes from the pc-settings (recharged_rt_*), overridable per-frame by a
  // debug prop / env so the device can flip lighting ON/OFF for A/B capture WITHOUT menu
  // navigation. u_rt_sun_dir reuses the visible-sun-overridden light_dir[0] (== the
  // on-screen sun sprite direction), so the sun-only shading, the shadow-map slope bias and
  // the depth-pass MVP all agree on where the sun is. u_rt_sun_color carries tint AND intensity.
  // SPEC §6.2 : sous l'eclairage recharge (recharged_gating::on compose les trois niveaux).
  // lighting-off-math-still-runs : 0 est le RESULTAT du regime eteint, pas un repli prudent.
  // `Gfx::lighting_active(x)` vaut `x && recharged_lighting_active()` (gfx.h:589-591) : eteint,
  // la recomposition finale ci-dessous rend 0 quelle que soit l'entree, donc ni la porte
  // `recharged_gating::on()` ni les deux surcharges d'environnement ne peuvent le relever. La
  // poussee CONSERVEE `u_rt_light_on` et `lighting_census::gate_rt_light()` recoivent donc la
  // meme valeur qu'avant, sans la calculer.
  int rt_light_on = 0;
  // ITEM A (owner playtest #2): I tried raising the sun intensity 1.5->1.75 to widen the sun-lit vs
  // ambient-only separation, but a device A/B measured NO contrast change (P90/std identical) — at the
  // owner vantage the sun-lit term is already tone-mapped/vantage-limited, so intensity does not move
  // the lit-vs-shadow gap. Reverted to the owner-ACCEPTED 1.5 (daylight "nickel") to avoid regressing
  // the validated look. Still per-frame overridable via debug.opengoal.rt.intensity.
  float rt_intensity = 1.5f;
  if (lgtmath::block(lgtmath::kRtGate)) {
  rt_light_on = recharged_gating::on(recharged_gating::kRtLight) ? 1 : 0;
#ifdef __ANDROID__
  {
    char rv[PROP_VALUE_MAX];
    if (prop_cache::property_get("debug.opengoal.rt.light", rv) > 0 && rv[0]) {
      rt_light_on = atoi(rv);
    }
    if (prop_cache::property_get("debug.opengoal.rt.intensity", rv) > 0 && rv[0]) {
      rt_intensity = atof(rv);
    }
  }
#else
  if (const char* e = prop_cache::env_get("OG_RT_LIGHT")) {
    rt_light_on = atoi(e);
  }
  if (const char* e = prop_cache::env_get("OG_RT_INTENSITY")) {
    rt_intensity = atof(e);
  }
#endif
  // lighting-hdr : l'override epingle LE SOUS-DRAPEAU, jamais la composition. Sans cette
  // ligne, poser la propriete rallumerait l'eclairage temps reel alors que l'ECLAIRAGE RECHARGE est
  // eteint — la classe de defaut exacte que l'owner a signalee le 2026-09-06, et celle
  // qui vient d'etre corrigee dans hdr.cpp. On recompose donc APRES l'override.
  rt_light_on = Gfx::lighting_active(rt_light_on != 0) ? 1 : 0;
  }  // lighting-off-math-still-runs : fin du bloc `kRtGate`
  // lighting-legacy-purge (2026-09-11) : la FORCE de l'ombre portee n'est plus un reglage. Le
  // residuel que le shader lisait (1 - force = 0,2 a la valeur livree) y est desormais ecrit en
  // dur : `u_rt_shadow_residual` n'est plus pousse, et la surcharge de propriete
  // `debug.opengoal.rt.shadowstrength` part avec le reglage qu'elle surchargeait.
  {
    // (terme 5, essai 5) TEMOIN, PAS EPINGLAGE. Ces cinq vecteurs sont lisses par une EMA du
    // cote GOAL (`rt_ema`, kmachine.cpp) : ils peuvent changer d'une image a l'autre sans
    // qu'aucun objet n'ait bouge. On ne les touche pas — on MESURE s'ils ont bouge sur la paire,
    // pour que le rapport puisse NOMMER la cause au lieu de la supposer.
    const float in[15] = {gs.recharged_pbr_sun_color[0], gs.recharged_pbr_sun_color[1],
                          gs.recharged_pbr_sun_color[2], gs.recharged_pbr_ambient[0],
                          gs.recharged_pbr_ambient[1],   gs.recharged_pbr_ambient[2],
                          gs.recharged_pbr_shadow[0],    gs.recharged_pbr_shadow[1],
                          gs.recharged_pbr_shadow[2],    gs.recharged_pbr_sky_sun[0],
                          gs.recharged_pbr_sky_sun[1],   gs.recharged_pbr_sky_sun[2],
                          gs.recharged_pbr_green_sun[0], gs.recharged_pbr_green_sun[1],
                          gs.recharged_pbr_green_sun[2]};
    prepass::census_note_light_inputs(in, 15);
  }
  lgt_keep_1i(id, "u_rt_light_on", rt_light_on);
  lighting_census::gate_rt_light(rt_light_on);
  lgt_keep_3f(id, "u_rt_sun_dir", light_dir[0], light_dir[1], light_dir[2]);
  // Sun color: normalize the mood sun tint to unit max, blend 50% toward white so it
  // reads as a natural sun (not an oversaturated hue), then scale by intensity.
  if (lgtmath::block(lgtmath::kSunColor)) {
    float msc[3] = {gs.recharged_pbr_sun_color[0] * sun_scale,
                    gs.recharged_pbr_sun_color[1] * sun_scale,
                    gs.recharged_pbr_sun_color[2] * sun_scale};
    float mx = msc[0];
    if (msc[1] > mx) mx = msc[1];
    if (msc[2] > mx) mx = msc[2];
    if (mx < 1e-3f) {
      msc[0] = msc[1] = msc[2] = 1.f;
      mx = 1.f;
    }
    float hue[3] = {msc[0] / mx, msc[1] / mx, msc[2] / mx};
    // lighting-regimes : quand la cle est celle du creneau, sa teinte est celle du creneau
    // (lgt-color, la table donne le ton) ; fondu vers celle de l'astre avec la cle elle-meme.
    const auto& rgc = regime::frame(render_state->frame_idx);
    if (rgc.armed) {
      float sm = std::max(rgc.slot_lgt[0], std::max(rgc.slot_lgt[1], rgc.slot_lgt[2]));
      for (int i = 0; i < 3; i++) {
        const float sh = sm > 1e-3f ? rgc.slot_lgt[i] / sm : 1.f;
        hue[i] = sh + (hue[i] - sh) * rgc.t;
      }
    }
    float rc[3];
    for (int i = 0; i < 3; i++) {
      rc[i] = (0.5f + 0.5f * hue[i]) * rt_intensity;
    }
    lgt_3f(id, "u_rt_sun_color", rc[0], rc[1], rc[2]);
  }
  // === Grecharged-realtime-lighting ROUND 7: NIGHT SUN-FADE ===
  // Gate the direct sun by the REAL sun ELEVATION (the visible-sun dome vector's up-component
  // from sky-parms — recharged_pbr_sky_sun, camera->sun, non-unit), NOT the mood current-sun.
  // Sun above the horizon => 1; smooth ramp near the horizon; sun BELOW the horizon (night)
  // => 0. This single uniform reaches ALL FOUR world shaders (tfrag3/shrub/etie/tie_wind all
  // share this setup), where it multiplies the direct-sun term to EXACTLY 0 at night — so at
  // night no path consumes the mood sun-color/intensity as a light and the whole world sits at
  // the ~0.2 sky-fill floor (kills the phantom night "spotlights"). Defaults to 1.0 (day) when
  // the sky-sun vector is not yet populated, so daytime is never wrongly darkened.
  float rt_sun_elev = 1.0f;
  float sun_up_raw = 1.0f;  // yellow-sun elevation sine (default fully-up until the first sky-sun push)
  if (lgtmath::block(lgtmath::kSunElev)) {
    const float* ss = gs.recharged_pbr_sky_sun;
    float ssl = std::sqrt(ss[0] * ss[0] + ss[1] * ss[1] + ss[2] * ss[2]);
    if (ssl > 1e-4f) {
      float up = ss[1] / ssl;  // sin(sun elevation): >0 above the horizon, <0 below (night)
      sun_up_raw = up;
      // OWNER PLAYTEST #4 (attempt-9): the attempt-8 WIDE ramp (-0.30..0.20) only widened the brightness
      // swing and MEASURED WORSE per-channel (world-crop perchan max 14.1 vs the narrow ramp's 7.3) with
      // no benefit — the "overlap crossfade" it aimed for does not exist because the two suns are ANTIPHASE
      // with a dark twilight GAP (never both up at once). So restore a narrow ramp near the owner-accepted
      // value (horizon..+0.18, ~10deg) but START it just below the horizon (-0.05) for a tiny overlap so the
      // yellow/green contributions blend for a moment at the handoff. The smooth yellow->green COLOUR
      // transition across the gap is carried by the continuously-interpolated ambient mood tone (todsmooth)
      // plus this small overlap; the shadow pop is killed by the owning-sun shadow fade below. Deep night
      // (sun below -0.05) still fades to EXACTLY 0 (no leak).
      rt_sun_elev = rt_smoothstep(-0.05f, 0.18f, up);
    }
    // lighting-regimes (SPEC §4.11) : sous l'item arme, le poids direct est celui du REGIME des
    // creneaux (sun-fade deja applique a la part de l'astre), et il suit l'elevation de l'astre en
    // proportion de sun-fade (essai 2) : sur un niveau a soleil visible, la nuit eteint le direct
    // comme avant ; sans soleil visible (lave, grotte), l'heure n'y change rien.
    const auto& rge = regime::frame(render_state->frame_idx);
    if (rge.armed) {
      rt_sun_elev = rge.direct_w;
    }
  }
  // lighting-off-math-still-runs : la surcharge de mise au point appartient au bloc `kSunElev` —
  // sa seule sortie est `rt_sun_elev`, qui ne sort pas de la famille sautable.
  if (lgtmath::lit_or_disarmed()) {
#ifdef __ANDROID__
  {
    char rv[PROP_VALUE_MAX];
    if (prop_cache::property_get("debug.opengoal.rt.sunelev", rv) > 0 && rv[0]) {
      rt_sun_elev = atof(rv);  // device A/B: force the night-fade value without waiting for TOD
    }
  }
#else
  if (const char* e = prop_cache::env_get("OG_RT_SUNELEV")) {
    rt_sun_elev = atof(e);
  }
#endif
  }
  // u_rt_sun_elev is uploaded AFTER the attempt-10 handoff low-pass below (so the SMOOTHED value reaches
  // the shaders); the raw rt_sun_elev computed here is the EMA target, still used by the prop override above.
  // === Grecharged-directional-ambient (owner playtest #3): the GREEN SUN = Jak's 2ND SUN ===
  // Owner reframe: the green star is NOT a night-only synthesised moon — it is the precursor GREEN
  // SUN (sky upload-data sun index 1, colour 194,254,120), symmetric to the yellow sun. Item 2:
  // drive it from its REAL sky position (recharged_pbr_green_sun == camera->green-sun, pushed from
  // GOAL via pc-set-pbr-green-sun!) and weight it by its OWN elevation smoothstep, so it is a real
  // directional light whenever it is above the horizon — DAY as well as night — exactly like the
  // yellow sun, just weaker + green. This also makes the sun<->green handoff fully SYMMETRIC (both
  // are smooth elevation-weighted directional lights), so the crossover stays continuous — the
  // owner-accepted à-coups fix is preserved (both weights are smoothsteps of a continuous orbit).
  // Golden rule + OFF==stock unchanged: the whole term is under u_rt_light_on and vanishes to 0 when
  // the green sun is below the horizon (green_elev -> 0). (Old code synthesised an opposite-of-sun,
  // night-only vector with weight 1-sun_elev — the exact thing the owner flagged as wrong.)
  float moon_dir[3] = {0.0f, 1.0f, 0.0f};  // safe default (up) until the first green-sun push arrives
  float green_elev = 0.0f;                 // green sun's OWN elevation weight (0 below horizon / unpushed)
  float green_up_raw = -1.0f;              // green-sun elevation sine (default below horizon until pushed)
  if (lgtmath::block(lgtmath::kGreenSun)) {
    const float* gsun = gs.recharged_pbr_green_sun;
    float gln = std::sqrt(gsun[0] * gsun[0] + gsun[1] * gsun[1] + gsun[2] * gsun[2]);
    if (gln > 1e-4f) {
      moon_dir[0] = gsun[0] / gln; moon_dir[1] = gsun[1] / gln; moon_dir[2] = gsun[2] / gln;  // surface->green-sun
      float up = gsun[1] / gln;  // sin(green-sun elevation): >0 above the horizon
      green_up_raw = up;
      green_elev = rt_smoothstep(-0.05f, 0.18f, up);  // SAME narrow ramp as the yellow sun => symmetric handoff (attempt-9)
    }
  }
  const float MOON_GREEN[3] = {0.76f, 1.0f, 0.47f};   // precursor green-sun colour (194,254,120)/255
  float moon_intensity = 0.40f;                        // WEAKER than the yellow sun (owner: green sun weaker)
  // lighting-off-math-still-runs : les deux surcharges de mise au point appartiennent au bloc
  // `kGreenSun` — leurs seules sorties sont `moon_intensity` et `green_elev`, et `moon_scale`
  // ci-dessous vaut 0 sans elles puisque `green_elev` reste a sa valeur « sous l'horizon ».
  if (lgtmath::lit_or_disarmed()) {
#ifdef __ANDROID__
  { char rv[PROP_VALUE_MAX];
    if (prop_cache::property_get("debug.opengoal.rt.moonintensity", rv) > 0 && rv[0]) moon_intensity = atof(rv); }
#else
  if (const char* e = prop_cache::env_get("OG_RT_MOONINTENSITY")) moon_intensity = atof(e);
#endif
  if (!(moon_intensity >= 0.0f && moon_intensity <= 2.0f)) moon_intensity = 0.40f;
  // Device A/B: force the green-sun elevation weight (like debug.opengoal.rt.sunelev for the yellow sun)
  // so the green-sun contribution can be isolated on/off at a fixed vantage (0 = green off, 1 = full).
#ifdef __ANDROID__
  { char rv[PROP_VALUE_MAX];
    if (prop_cache::property_get("debug.opengoal.rt.greenelev", rv) > 0 && rv[0]) {
      float g = atof(rv);
      if (g >= 0.0f) green_elev = g;  // NEGATIVE sentinel (-1) => keep the REAL green-sun elevation
    }                                  // (a prop cannot be cleared headlessly, so -1 = "release override")
  }
#else
  if (const char* e = prop_cache::env_get("OG_RT_GREENELEV")) {
    float g = atof(e);
    if (g >= 0.0f) green_elev = g;
  }
#endif
  }
  float moon_scale = moon_intensity * green_elev;  // real green-sun elevation weight => day+night when up
  // lighting-regimes (SPEC §3.3) : le soleil vert est un ASTRE — son sprite n'existe que si
  // sun-fade > 0 (time-of-day.gc:52). Sans ciel ni astre visible, il n'eclaire plus rien.
  const auto& rgm = regime::frame(render_state->frame_idx);
  if (rgm.armed) {
    moon_scale *= rgm.sun_fade;
  }
  // OWNER PLAYTEST #4 (attempt-9b fix) — SHADOW-HANDOFF via a GRAZING-GATED elevation fade of the OWNING sun.
  // History: attempt-8's dominance formula was DEAD CODE (conf==1 always, the antiphase suns are never both
  // up). Attempt-9a tied conf to the owning sun's LIGHT weight, but that STILL left a single-frame ~14/255
  // pop at the ownership flip: the one depth map re-renders from the GRAZING (near-horizon) green sun the
  // instant it out-elevates the set yellow sun, casting long shadows that snap in — a discrete step visible
  // at any TOD speed (measured: an isolated 14.45/255 spike between otherwise ~0.5/255 neighbours).
  // FIX: gate the cast shadow on the owning sun's ELEVATION with a HIGHER window than the light ramp, so a
  // sun casts NO shadow while it is near the horizon (grazing) and only fades its shadow in once it is
  // comfortably up. conf = smoothstep(0.05, 0.30, owning_sun_up). Across the whole near-horizon handoff
  // BOTH suns are below 0.05 => conf==0 => the depth-map ownership flip is invisible (stepless). Full
  // daylight (yellow well up) keeps full shadows; deep-night green-sun shadows return once the green sun is
  // high. The direct LIGHT still ramps in at the horizon (rt_sun_elev/green_elev, -0.05..0.18) — only the
  // SHADOW waits for non-grazing elevation. Golden rule intact (this gates only the direct-sun cast shadow).
  float rt_shadow_conf = 0.0f;
  if (lgtmath::block(lgtmath::kShadowConf)) {
    float owning_up = (pbr_shadow_state().key_light == 1) ? green_up_raw : sun_up_raw;
    // lighting-regimes : quand la cle des cascades est celle du CRENEAU (t = 0), la confiance ne
    // suit plus l'elevation d'un soleil qui ne la porte pas.
    if (rgm.armed && pbr_shadow_state().key_light == 0) {
      owning_up = 1.f + (owning_up - 1.f) * rgm.t;
    }
    rt_shadow_conf = rt_smoothstep(0.05f, 0.30f, owning_up);
  }

  // === OWNER PLAYTEST #4 (attempt-10) — TEMPORAL per-frame low-pass of the sun<->green-sun HANDOFF ===
  // The yellow<->green handoff must be smooth PER-CHANNEL (R,G,B), not just in luminance. The three handoff
  // scalars (rt_sun_elev = yellow direct-light night-fade, moon_scale = green-sun fill, rt_shadow_conf =
  // cast-shadow strength) each smoothstep the sun ELEVATION — smooth at real TOD, but NOT under the tod.fast
  // 18000x stress metric: at ~25 game-min/frame the sun crosses a whole elevation ramp band between two
  // captured frames, so the shadow/green terms SNAP 0->full in ONE frame (the measured isolated ~14/255
  // per-channel spike — a hue-tinted step the luminance-only metric let through). FIX = the SAME proven
  // low-pass item-B used for the mood colours, applied to these scalars: an exponential moving average
  // toward the raw target, advanced ONCE PER FRAME (first_tfrag_draw_setup runs ~5x/frame => guard on
  // render_state->frame_idx so all shader families read one consistent value). alpha 0.10 == the exact
  // per-frame weight of the owner-ACCEPTED item-B mood low-pass (~0.7s ramp) => a fast elevation ramp is
  // spread over ~10 frames => stepless at ANY TOD speed; at real play speed it is a sub-second lag on the
  // dawn/dusk fade, imperceptible. GOLDEN RULE + daylight intact: at full day rt_sun_elev==1 / conf==1 /
  // moon_scale==0 STEADILY, so the EMA converges to those constants and the sunlit term is byte-identical
  // (no daylight regression, sunlit A/B unchanged). Runs unconditionally; OFF==stock preserved by the
  // shader u_rt_light_on gate. A/B-defeatable (raw = the pre-fix step) via debug.opengoal.rt.handoffsmooth
  // ("0"/invalid => alpha 1 => no smoothing).
  // lighting-off-math-still-runs : la lecture de l'alpha, les deux poids d'orientation et l'EMA
  // elle-meme forment UN bloc (`kHandoffEma`) : l'alpha n'alimente que l'EMA, et l'EMA n'alimente
  // que des poussees sautables. Sauter le bloc rend la fonction muette pour les statiques, d'ou
  // l'INVALIDATION dans la branche `else` plus bas — sans elle, la rallumee ferait ramper l'EMA
  // pendant ~10 images depuis une valeur vieille de N images, exactement l'a-coup que attempt-10
  // a supprime.
  float handoff_alpha = 0.10f;
  float ambW_y = 1.0f, ambW_g = 0.0f;
  if (lgtmath::block(lgtmath::kHandoffEma)) {
#ifdef __ANDROID__
  { char rv[PROP_VALUE_MAX];
    if (prop_cache::property_get("debug.opengoal.rt.handoffsmooth", rv) > 0 && rv[0]) handoff_alpha = atof(rv); }
#else
  if (const char* e = prop_cache::env_get("OG_RT_HANDOFFSMOOTH")) handoff_alpha = atof(e);
#endif
  if (!(handoff_alpha > 0.0f && handoff_alpha <= 1.0f)) handoff_alpha = 1.0f;  // invalid/0 => raw (no smoothing)
  // === OWNER PLAYTEST #5 (attempt-11) — AMBIENT-ORIENTATION per-sun elevation weights (the real fix) ===
  // Owner's CORRECTED diagnosis: the brutal sun<->green-sun handoff is the shading ORIENTATION snapping ~180deg
  // (the KEY light AND the ambient's directional bias), not a colour step. The direct terms already fade per-sun
  // (rt_sun_elev / moon_scale), but the ambient directional bias (amb_key) was LOCKED to the yellow azimuth at
  // full strength and never faded => in the dark middle it kept a strong yellow orientation that then flipped to
  // green. FIX = weight the ambient orientation by EACH sun's OWN elevation so it eases OUT into a dark NEUTRAL
  // MIDDLE (both weights ~0 => near-uniform ambient, no orientation to flip) then eases IN toward green. These
  // weights use the NATURAL elevation sines (sun_up_raw / green_up_raw), NOT the debug-overridable rt_sun_elev/
  // green_elev, so the daytime sun-off A/B (debug.opengoal.rt.sunelev 0, natural sun still high) keeps its
  // ambient form while the real night handoff collapses the orientation. EMA-smoothed with the same accepted
  // handoff low-pass => stepless at any TOD speed; steady day => ambW_y==1/ambW_g==0 (daylight byte-identical).
  float ambW_y_raw = rt_smoothstep(-0.05f, 0.18f, sun_up_raw);
  float ambW_g_raw = rt_smoothstep(-0.05f, 0.18f, green_up_raw);
  ambW_y = ambW_y_raw;
  ambW_g = ambW_g_raw;
  {
    // lighting-off-math-still-runs : les six statiques ont quitte le corps de la fonction pour
    // `lgtmath::g_ho` ; l'etat et les valeurs sont identiques, seul leur lieu change.
    auto& ho = lgtmath::g_ho;
    if (!ho.seeded) {  // seed to the current raw values so we don't ramp from the defaults on boot
      ho.sunelev = rt_sun_elev; ho.moon = moon_scale; ho.conf = rt_shadow_conf;
      ho.ambY = ambW_y_raw; ho.ambG = ambW_g_raw; ho.seeded = true;
    }
    if (render_state->frame_idx != ho.frame) {  // advance the EMA exactly once per frame
      // (terme 5, essai 5) L'EMA AVANCE PAR CONSTRUCTION A CHAQUE IMAGE : sur la paire que le
      // point F juge, elle ferait bouger `u_rt_sun_elev`, `u_rt_moon_color`, `u_rt_shadow_conf`
      // et les deux poids d'ambiante sans qu'aucun objet n'ait bouge. On la GELE sur la paire et
      // on PUBLIE ce que le gel supprime (`ao_static_lightpin_ho_delta_x1e6`).
      if (prepass::census_lighting_pinned()) {
        // Somme des VALEURS ABSOLUES, composante par composante : une somme signee laisserait
        // deux avances opposees s'annuler et publierait zero sur un gel qui a bien supprime
        // quelque chose — le temoin mesurerait alors sa propre compensation.
        const float sup = std::fabs(rt_sun_elev - ho.sunelev) + std::fabs(moon_scale - ho.moon) +
                          std::fabs(rt_shadow_conf - ho.conf) + std::fabs(ambW_y_raw - ho.ambY) +
                          std::fabs(ambW_g_raw - ho.ambG);
        prepass::note_lightpin_ho_delta(handoff_alpha * sup);
      } else {
        ho.frame = render_state->frame_idx;
        ho.sunelev += handoff_alpha * (rt_sun_elev - ho.sunelev);
        ho.moon += handoff_alpha * (moon_scale - ho.moon);
        ho.conf += handoff_alpha * (rt_shadow_conf - ho.conf);
        ho.ambY += handoff_alpha * (ambW_y_raw - ho.ambY);
        ho.ambG += handoff_alpha * (ambW_g_raw - ho.ambG);
      }
    }
    rt_sun_elev = ho.sunelev;
    moon_scale = ho.moon;
    rt_shadow_conf = ho.conf;
    ambW_y = ho.ambY;
    ambW_g = ho.ambG;
  }
  } else {
    // L'INVALIDATION. Le lissage n'a pas avance pendant que l'eclairage etait eteint : sa valeur
    // decrit une epoque revolue. On le desamorce, il se re-semera sur la valeur BRUTE a la
    // premiere image rallumee — le comportement exact de l'amorcage, jamais une rampe depuis
    // du perime.
    lgtmath::g_ho.seeded = false;
  }
  lgt_1f(id, "u_rt_sun_elev", rt_sun_elev);  // moved: upload the SMOOTHED value
  regime::audit_night(render_state->frame_idx, rt_sun_elev);
  // lighting-regimes (SPEC §4.11) : le REGIME lu par le shader — x poids direct (deja dans
  // u_rt_sun_elev), y multiplicateur du rayon de penombre des cascades de la cle, z poids
  // speculaire (sans lecteur : le composite n'a pas de speculaire), w regime dominant. Bras
  // desarme : (1, 1, 1, 0), la penombre d'avant a l'identique (x * 1,0 == x).
  if (rgm.armed) {
    lgt_4f(id, "u_rt_regime", rgm.direct_w, rgm.penumbra, rgm.spec_w, (float)rgm.dominant);
  } else {
    lgt_4f(id, "u_rt_regime", 1.f, 1.f, 1.f, 0.f);
  }
  // lighting-regimes essai 3 : ce que le CUIT contient (SPEC 5.2, ambiante PLATE — mesure de
  // lighting-bake, art median 0,954) : x = luma de l'ambiante du groupe de lumieres, y = luma des
  // lumieres de la table PROJETEES sur la cle poussee (chacune x son niveau x cos(ecart a la cle)),
  // z = 1 si le groupe est pousse. Le shader en tire la part directe du cuit, la seule que l'ombre
  // temps reel a le droit d'enlever. Memes unites que le cuit (octet/128, fragment_color x 2).
  {
    const auto& gs = Gfx::settings();
    const float kl[3] = {0.299f, 0.587f, 0.114f};
    float a_l = 0.f, l_l = 0.f;
    const bool valid = gs.recharged_pbr_lg_valid && gs.recharged_regime_valid;
    if (valid) {
      for (int k = 0; k < 3; k++) {
        a_l += kl[k] * std::max(0.f, gs.recharged_pbr_lg_ambi[k]);
      }
      PbrV3 key = {light_dir[0], light_dir[1], light_dir[2]};
      if (pv_dot(key, key) > 1e-8f) {
        key = pv_norm(key);
      }
      for (int i = 0; i < 4; i++) {
        const float wi = std::max(0.f, gs.recharged_regime_w[i]);
        if (wi <= 0.f) {
          continue;
        }
        const float* d = gs.recharged_regime_slot_dir[i];
        PbrV3 di = {d[0], d[1], d[2]};
        if (pv_dot(di, di) <= 1e-8f) {
          continue;
        }
        const float c = std::max(0.f, pv_dot(pv_norm(di), key));
        float ll = 0.f;
        for (int k = 0; k < 3; k++) {
          ll += kl[k] * std::max(0.f, gs.recharged_regime_slot_lgt[i][k]);
        }
        l_l += wi * ll * c;
      }
    }
    lgt_4f(id, "u_rt_bake_al", a_l, l_l, valid ? 1.f : 0.f, 0.f);
    lgt_1f(id, "u_rt_amb_contrast", regime::kAmbContrast);
    static u64 s_bake_frame = ~0ull;
    if (s_bake_frame != render_state->frame_idx) {
      s_bake_frame = render_state->frame_idx;
      autoport_proof::publish("regime_bake_amb_x1000", (u64)std::lround(a_l * 1000.f));
      autoport_proof::publish("regime_bake_lgt_x1000", (u64)std::lround(l_l * 1000.f));
      autoport_proof::publish("regime_bake_valid", valid ? 1 : 0);
      autoport_proof::publish("regime_amb_contrast_x1000", (u64)std::lround(regime::kAmbContrast * 1000.f));
    }
  }
#ifdef __ANDROID__
  // Deterministic state-dump (owner prefers this to eyeballing): green-sun elevation weight, yellow-sun
  // elevation, green direction, shadow-handoff confidence, and which sun currently owns the shadow map.
  // lighting-off-math-still-runs : eclairage eteint, les blocs qui produisent ces cinq grandeurs
  // ne tournent plus — le vidage imprimerait leurs valeurs d'initialisation en les faisant passer
  // pour une mesure. On le tait. Ce n'est pas un calcul : il ne consomme pas de numero de bloc.
  if (lgtmath::lit_or_disarmed())
  { char dv[PROP_VALUE_MAX]; static int gdbg = 0;
    if (prop_cache::property_get("debug.opengoal.rt.greendbg", dv) > 0 && dv[0] == '1' && (gdbg++ % 120) == 0) {
      lg::info("GDA-GREENSUN green_elev={:.3f} sun_elev={:.3f} conf={:.3f} gdir=({:.2f},{:.2f},{:.2f}) shadow_light={}",
               green_elev, rt_sun_elev, rt_shadow_conf, moon_dir[0], moon_dir[1], moon_dir[2],
               pbr_shadow_state().key_light);
    }
  }
#endif
  lgt_3f(id, "u_rt_moon_dir", moon_dir[0], moon_dir[1], moon_dir[2]);
  // lighting-shadows essai 6 : merc2 n'est pas un des quatre hotes de `first_tfrag_draw_setup` —
  // ropebridge (village1) est dessine par Merc2, pas par le decor. Il a besoin de la MEME source
  // de valeurs (u_rt_light_on, u_rt_regime, u_rt_sun_dir, u_rt_moon_dir) sans rejouer tout ce
  // calcul : instantane pris ICI, au point ou ces quatre grandeurs sont toutes connues pour
  // l'image courante ; `pbr_push_merc_regime_uniforms` (Merc2.cpp) le repousse tel quel.
  {
    auto& mc = pbr_merc_regime_cache();
    mc.light_on = rt_light_on;
    mc.sun_dir[0] = light_dir[0]; mc.sun_dir[1] = light_dir[1]; mc.sun_dir[2] = light_dir[2];
    mc.moon_dir[0] = moon_dir[0]; mc.moon_dir[1] = moon_dir[1]; mc.moon_dir[2] = moon_dir[2];
    if (rgm.armed) {
      mc.regime[0] = rgm.direct_w; mc.regime[1] = rgm.penumbra; mc.regime[2] = rgm.spec_w;
      mc.regime[3] = (float)rgm.dominant;
    } else {
      mc.regime[0] = 1.f; mc.regime[1] = 1.f; mc.regime[2] = 1.f; mc.regime[3] = 0.f;
    }
    mc.valid = true;
  }
  lgt_3f(id, "u_rt_moon_color",
              MOON_GREEN[0] * moon_scale, MOON_GREEN[1] * moon_scale, MOON_GREEN[2] * moon_scale);
  lgt_1f(id, "u_rt_shadow_conf", rt_shadow_conf);  // playtest #4 stepless shadow handoff
#ifdef OG_FEAT_PBR
  // lighting-shadows (A5) : poids DIRECTS des deux astres, pour que `pbr_shadow_first_camera`
  // (image SUIVANTE) sache lequel domine et si le second astre depasse 5% du total. Ecart au
  // §4.8 assume faute de temps : `green_amp` (0.60 par defaut) n'est pas relu ici tel quel — on
  // reutilise `moon_scale`, qui l'inclut deja via `moon_intensity`, comme poids direct du second
  // astre.
  if (lgt::site()) {
    pbr_shadow_note_weights(rt_sun_elev, moon_scale);
  }
#endif

  // === Grecharged-directional-ambient: HEMISPHERE ambient (replaces the flat ~0.2 floor). ===
  // The ambient base is directional: an up-hemisphere SKY tint and a down-hemisphere GROUND bounce,
  // blended per-fragment by the world normal in the shader. Both track the mood/TOD ambient so the day
  // cycle drives the HUE; the LEVEL is the Ambient Strength setting, gently faded by the real sun
  // elevation (reusing rt_sun_elev) so night stays calm — NO mood night presets feed the brightness
  // (round-7 night-leak discipline). Golden rule: this only reshapes the ambient base; the direct-sun
  // term is untouched so sunlit surfaces are unchanged.
  // SPEC §6.2 : l'ambiante est sous l'eclairage recharge.
  // lighting-legacy-purge (2026-09-11) : l'ambiante directionnelle n'a plus d'interrupteur — elle
  // est INCONDITIONNELLE sous l'eclairage (elle livrait deja ON). Sa FORCE vaut la constante
  // livree, son MODELE reste SH (kRtAmbientModel = 1, la valeur livree) et son CONTRASTE etait un
  // knob MORT : uniforme declare, pousse, et AUCUN lecteur GLSL. Les surcharges de propriete
  // `debug.opengoal.rt.ambient[strength|contrast|model]` partent avec les reglages qu'elles
  // surchargeaient : une surcharge sur un reglage supprime est exactement la survivance que cet
  // item retire. La garde NaN/hors-borne sur la force disparait avec la variable — une constante
  // n'a pas besoin d'etre validee.
  const float rt_ambient_strength = RechargedFixed::kRtAmbientStrength;
  // Grecharged-directional-ambient ROOT-CAUSE FIX: debug/A-B toggle to force the OLD flat per-face
  // screen-derivative normal instead of the reconstructed SMOOTH per-vertex normal. Default 0 = smooth
  // (the fix). Set 1 to reproduce the pre-fix faceted look for a same-build before/after comparison.
  // Not exposed in the menu (debug-only); driven by a prop/env during device capture.
  int rt_flat_normal = 0;
  if (lgtmath::block(lgtmath::kFlatNormal)) {
#ifdef __ANDROID__
  {
    char rv[PROP_VALUE_MAX];
    if (prop_cache::property_get("debug.opengoal.rt.flatnormal", rv) > 0 && rv[0]) {
      rt_flat_normal = atoi(rv);
    }
  }
#else
  if (const char* e = prop_cache::env_get("OG_RT_FLATNORMAL")) {
    rt_flat_normal = atoi(e);
  }
#endif
  }
  // census-false-reds (2026-09-12) : l'enregistrement de la porte de sondes est SUPPRIME d'ici.
  // lighting-off-math-still-runs l'avait sorti du bloc d'ambiante pour qu'il tourne a chaque
  // appel ; il recevait le litteral 0, et plus aucun shader ne declare l'uniforme. C'etait donc
  // une constante enregistree pour elle-meme : le composite qu'elle gardait est parti avec elle
  // du recensement. Rien d'autre de ce bloc ne change.
  if (lgtmath::block(lgtmath::kAmbientSh)) {
    // lighting-regimes (SPEC §4.10, annexe D.4) : sous l'item arme, l'ambiante directionnelle est
    // l'ENVIRONNEMENT MESURE — la forme du ciel reellement dessine, renormalisee sur l'amb-color du
    // creneau — et plus le ciel procedural a trois bandes ci-dessous, qui ne sert plus que le bras
    // desarme. L'uniforme change de nom (`u_rt_sh` -> `u_env_sh`) : le terme SH reporte par
    // lighting-legacy-purge est RETIRE, son successeur est mesure.
    float shc[9][3];
    const auto& rga = regime::frame(render_state->frame_idx);
    if (rga.armed) {
      regime::env_sh(shc, rt_ambient_strength, render_state->frame_idx);
    } else {
      // SKY hue: the mood ambient (light-group ambi when valid, else the mood env ambient), normalized to
      // unit-max so the mood's *brightness* can't re-brighten night (only its HUE is used); blended 50%
      // toward white so it reads as natural skylight. amb_scale (1/255) converts the raw GOAL 0..255 color.
      const float* asrc =
          gs.recharged_pbr_lg_valid ? gs.recharged_pbr_lg_ambi : gs.recharged_pbr_ambient;
      float shue[3] = {asrc[0] * amb_scale, asrc[1] * amb_scale, asrc[2] * amb_scale};
      float smx = shue[0];
      if (shue[1] > smx) smx = shue[1];
      if (shue[2] > smx) smx = shue[2];
      if (smx < 1e-3f) {
        shue[0] = 0.6f;
        shue[1] = 0.7f;
        shue[2] = 1.0f;
        smx = 1.0f;
      }
      // LEVEL: strength, gently faded by sun elevation so night is calmer (never below 0.7x, never brighter
      // than day). rt_sun_elev is 1 (day) .. 0 (night below horizon).
      float lvl = rt_ambient_strength * (0.7f + 0.3f * rt_sun_elev);
      const float gtint[3] = {0.65f, 0.55f, 0.45f};  // warm, darker ground bounce
      float sky[3], ground[3];
      // ITEM A (owner playtest #2) — MOOD-MATCH. I tried lowering the hue white-floor 0.50 -> 0.44 to carry
      // more mood hue, but a device A/B measured it drifted the tone WARMER (rt warmth R-B +7.4) AWAY from
      // the stock baked mood, which at this vantage/TOD is cooler/neutral (baked R-B +1.7). Reverted to the
      // owner-ACCEPTED 0.50: the accepted-default rt ambient already tracks the baked mood/luma closely
      // (device: rt-on luma 53.8 vs baked 54.4), so the mood is preserved without a warm drift.
      for (int i = 0; i < 3; i++) {
        float hue = 0.5f + 0.5f * (shue[i] / smx);  // toward white (owner-accepted mood, matches baked luma)
        sky[i] = hue * lvl;
        ground[i] = sky[i] * gtint[i];
      }
      // === ROUND 2: SH (model 1) + IBL procedural-sky (model 2) from the SAME sky, MEAN-NORMALIZED to the
      // hemisphere mean so all 3 models carry identical average ambient energy (=> sunlit byte-identical
      // across models: the golden rule) and differ only in DIRECTIONAL distribution (=> shadowed FORM). ===
      float env_zenith[3], env_horizon[3], env_ground[3], sun_glow[3];
      float gsc[3] = {gs.recharged_pbr_sun_color[0] * sun_scale, gs.recharged_pbr_sun_color[1] * sun_scale,
                      gs.recharged_pbr_sun_color[2] * sun_scale};
      float gmx = gsc[0];
      if (gsc[1] > gmx) gmx = gsc[1];
      if (gsc[2] > gmx) gmx = gsc[2];
      if (gmx < 1e-3f) {
        gsc[0] = 1.0f;
        gsc[1] = 0.9f;
        gsc[2] = 0.75f;
        gmx = 1.0f;
      }
      const float GLOW_GAIN = 0.35f;
      for (int i = 0; i < 3; i++) {
        env_zenith[i] = sky[i];
        env_ground[i] = ground[i];
        float h = (sky[i] * 0.6f + ground[i] * 0.4f) * 1.4f;  // brighter warm horizon band (clear-sky look)
        env_horizon[i] = h > 1.0f ? 1.0f : h;
        float ghue = 0.5f + 0.5f * (gsc[i] / gmx);
        sun_glow[i] = ghue * lvl * GLOW_GAIN * rt_sun_elev;  // elevation-faded => 0 at night (no phantom light)
      }
      // Project that procedural sky into L2 SH (deterministic Fibonacci-sphere Monte-Carlo, no RNG) and
      // accumulate its spherical AVERAGE for the mean-normalization. sun_d = surface->sun (light 0).
      float sun_d[3] = {light_dir[0], light_dir[1], light_dir[2]};
      for (int c = 0; c < 9; c++) {
        shc[c][0] = shc[c][1] = shc[c][2] = 0.0f;
      }
      float avg_env[3] = {0.0f, 0.0f, 0.0f};
      {
        const int NS = 256;
        const float GA = 2.399963229728653f;  // golden angle
        const float wsphere = 4.0f * 3.14159265358979f / (float)NS;
        for (int k = 0; k < NS; k++) {
          float sy = 1.0f - 2.0f * ((float)k + 0.5f) / (float)NS;
          float rr = 1.0f - sy * sy;
          float sr = rr > 0.0f ? std::sqrt(rr) : 0.0f;
          float phi = (float)k * GA;
          float sx = sr * std::cos(phi);
          float sz = sr * std::sin(phi);
          // sky_env(dir) — MUST mirror the shader rt_ibl_ambient()
          float uu = sy;
          float su = uu / 0.55f;
          su = su < 0.0f ? 0.0f : (su > 1.0f ? 1.0f : su);
          su = su * su * (3.0f - 2.0f * su);
          float sd = -uu / 0.45f;
          sd = sd < 0.0f ? 0.0f : (sd > 1.0f ? 1.0f : sd);
          sd = sd * sd * (3.0f - 2.0f * sd);
          float g = sx * sun_d[0] + sy * sun_d[1] + sz * sun_d[2];
          if (g < 0.0f) g = 0.0f;
          g = g * g;
          g = g * g;
          float Y[9];
          Y[0] = 0.282095f;
          Y[1] = 0.488603f * sy;
          Y[2] = 0.488603f * sz;
          Y[3] = 0.488603f * sx;
          Y[4] = 1.092548f * sx * sy;
          Y[5] = 1.092548f * sy * sz;
          Y[6] = 0.315392f * (3.0f * sz * sz - 1.0f);
          Y[7] = 1.092548f * sx * sz;
          Y[8] = 0.546274f * (sx * sx - sy * sy);
          for (int i = 0; i < 3; i++) {
            float band = uu >= 0.0f ? (env_horizon[i] + (env_zenith[i] - env_horizon[i]) * su)
                                    : (env_horizon[i] + (env_ground[i] - env_horizon[i]) * sd);
            float e = band + sun_glow[i] * g;
            avg_env[i] += e * (1.0f / (float)NS);
            for (int c = 0; c < 9; c++) {
              shc[c][i] += e * Y[c] * wsphere;
            }
          }
        }
      }
      // cosine-convolution (A_l/pi): l0=1, l1=2/3, l2=1/4 (Lambert diffuse baked into the coeffs).
      const float Al[9] = {1.0f, 2.0f / 3.0f, 2.0f / 3.0f, 2.0f / 3.0f,
                           0.25f, 0.25f, 0.25f, 0.25f, 0.25f};
      for (int c = 0; c < 9; c++) {
        for (int i = 0; i < 3; i++) {
          shc[c][i] *= Al[c];
        }
      }
      // MEAN-NORMALIZE SH coeffs AND IBL bands so the sky mean == hemisphere mean (sky+ground)/2 per
      // channel (golden rule: identical average energy across models).
      float fnorm[3];
      for (int i = 0; i < 3; i++) {
        float target = 0.5f * (sky[i] + ground[i]);
        float f = avg_env[i] > 1e-5f ? target / avg_env[i] : 1.0f;
        f = f < 0.25f ? 0.25f : (f > 4.0f ? 4.0f : f);
        fnorm[i] = f;
        env_zenith[i] *= f;
        env_horizon[i] *= f;
        env_ground[i] *= f;
        sun_glow[i] *= f;
      }
      for (int c = 0; c < 9; c++) {
        for (int i = 0; i < 3; i++) {
          shc[c][i] *= fnorm[i];
        }
      }
      // lighting-legacy-purge (2026-09-11) : `u_rt_ambient_key` n'est plus pousse et son CALCUL
      // (`amb_key`, le melange azimutal des deux soleils) part avec lui : il etait le seul des sept
      // entrees de l'ambiante directionnelle a n'avoir aucun autre consommateur. Les six autres
      // (sky/ground/env_*/sun_glow) restent CALCULEES : la projection L2 en tire `shc[9]`, qui est
      // toujours poussee.
    }
    lgt_1i(id, "u_rt_flat_normal", rt_flat_normal);
    lgt_3fv(id, "u_env_sh[0]", 9, &shc[0][0]);

    // === SPEC-refonte-lumiere §2.4 — FollowProbe est SUPPRIMEE, ses uniformes sont RE-HEBERGES ICI.
    // Ce que la classe faisait vraiment, mesure a l'appui :
    //   * elle poussait la porte de sondes a 0 en CONSTANTE INCONDITIONNELLE a chaque draw, ce
    //     qui fermait le composite D dans les cinq shaders monde (mesure du 2026-09-05 : 0 draw
    //     sur 11004086) ;
    //   * elle liait une texture 1x1x1 NOIRE sur QUATRE unites (4-7) pour des `sampler3D` que
    //     personne n'echantillonnait, plus un samplerCube sur l'unite 3 ;
    //   * elle rasterisait au CPU une face de cube par image et appelait
    //     `glGenerateMipmap(GL_TEXTURE_CUBE_MAP)` A CHAQUE IMAGE pour cette texture que le
    //     tableau ci-dessus montre inutilisee ;
    //   * et, dans le meme appel, elle poussait les HUIT amplitudes de la modulation bakee — le
    //     chemin A, celui que l'owner a valide le 2026-07-19. C'etait son SEUL ecrivain dans tout
    //     le depot. Les supprimer avec elle les ferait retomber au defaut GL 0 : ombres noires,
    //     aucun gain a la lumiere. Elles sont donc reprises ici A L'IDENTIQUE, valeurs et
    //     proprietes de debug Android comprises.
    // La porte de sondes n'a plus d'ecrivain, et n'en a plus besoin : l'uniforme n'est plus
    // declare dans aucun shader. Depuis census-false-reds (2026-09-12) le recensement ne la lit
    // plus non plus : un zero qu'aucun etat ne peut lever n'est pas une mesure.
    {
      // gl-uniforms-dead-seven (2026-09-12) : `u_rt_shadow_mul` et `u_rt_tint_shadow` ne sont
      // plus pousses, et les deux proprietes de debug qui les alimentaient partent avec eux.
      // Mesure : `glu::census_frame` interroge le pilote programme par programme, et AUCUN des
      // programmes lies ne rend d'emplacement pour ces deux noms — ils sont DECLARES dans
      // shade.glsl mais jamais lus, donc le compilateur GLSL les retire. Pousser une valeur que
      // personne ne lit fabrique une fausse constante et un reglage fantome cote Android.
      int dbg_litboost = 0, dbg_tintlit = -1;
      // `u_rt_detail`, `u_rt_detail_norm` et `u_rt_sun_boost` ne sont plus pousses : apres le
      // retrait du composite D ils n'ont plus AUCUN site de lecture dans les cinq shaders monde
      // (mesure `grep -c`), et pousser une valeur que personne ne lit fabrique une fausse
      // constante. SPEC-refonte-lumiere D.3.
      int dbg_greenamp = -1;
#ifdef __ANDROID__
      {
        char v[PROP_VALUE_MAX];
        auto rd = [&](const char* name, int& dst) {
          if (prop_cache::property_get(name, v) > 0 && v[0]) {
            dst = atoi(v);
          }
        };
        rd("debug.opengoal.rt.litboost", dbg_litboost);
        rd("debug.opengoal.rt.tintlit", dbg_tintlit);
        rd("debug.opengoal.rt.greenamp", dbg_greenamp);
      }
#endif
      lgt_1f(id, "u_rt_lit_boost",
                  (dbg_litboost > 0) ? (float)dbg_litboost / 100.f : 1.15f);
      lgt_1f(id, "u_rt_tint_lit",
                  (dbg_tintlit >= 0) ? (float)dbg_tintlit / 100.f : 0.12f);
      lgt_1f(id, "u_rt_green_amp",
                  (dbg_greenamp >= 0) ? (float)dbg_greenamp / 100.f : 0.60f);
      // lighting-off-math-still-runs : l'enregistrement de la porte de sondes etait remonte AVANT
      // ce bloc ; census-false-reds l'a supprime (constante sans lecteur).
    }
  }

  lgt_1f(id, "u_pbr_shadow_bias", pbr_shadow_bias);
#endif
}


// ── (terme 3, essai 4) LES DEUX ETATS D'ALPHA, MESURES AU LIEU D'ETRE SUPPOSES ───────────────
// L'ordre de l'owner du 2026-09-17 : « la prepasse echantillonne-t-elle le feuillage AUTREMENT
// que la passe couleur (mip, filtre, seuil alpha) ? publier les deux etats d'echantillonnage ».
// L'ECHANTILLONNAGE est identique — meme objet texture, memes quatre `glTexParameteri` par
// `prepass_tex_params`, meme `texture()` a LOD implicite, meme resolution, meme viewport. Ce qui
// DIFFERE est la GRANDEUR COMPAREE :
//   couleur  : `fragment_color.a * T0.a < alpha_min`, avec `fragment_color.a = tod_color.a * 4`
//              (shrub.vert / tfrag3.vert), plus `color.a > alpha_max` que la prepasse n'a pas,
//              plus, pour tfrag3 SEULEMENT, `color.a *= mix(1, dist_f, steep_w)` du fondu de
//              frange (tfrag3.frag) que la prepasse ne rejoue pas du tout ;
//   prepasse : `T0.a < alpha_min * 255/512` (prepass_world.frag, `u_cut_aref`).
// Les deux ne coincident QUE si `tod_color.a == 128/255` EXACTEMENT, c'est-a-dire quand le
// `min(128, …)` ci-dessous SATURE. Rien dans l'arbre ne le garantit : c'est une somme de huit
// produits poids x palette. On le MESURE donc, au seul endroit qui le calcule, et la question
// « le cycle jour/nuit desaccorde-t-il les deux tests ? » cesse d'etre une lecture de code.
namespace {
uint64_t g_tod_a_min = 255, g_tod_a_max = 0, g_tod_a_samples = 0, g_tod_a_unsaturated = 0;

void note_tod_alpha(const math::Vector<u8, 4>* out, u32 count) {
  if (!out || count == 0 || !autoport_proof::armed_for("ao-indirect-clean")) {
    return;
  }
  for (u32 i = 0; i < count; i++) {
    const uint64_t a = out[i][3];
    if (a < g_tod_a_min) {
      g_tod_a_min = a;
    }
    if (a > g_tod_a_max) {
      g_tod_a_max = a;
    }
    if (a != 128) {
      g_tod_a_unsaturated++;
    }
  }
  g_tod_a_samples += count;
  // Une seule publication par appel : `publish` ecrase, la derniere valeur est la course entiere.
  autoport_proof::publish("ao_alpha_tod_a_min", g_tod_a_min);
  autoport_proof::publish("ao_alpha_tod_a_max", g_tod_a_max);
  autoport_proof::publish("ao_alpha_tod_a_samples", g_tod_a_samples);
  autoport_proof::publish("ao_alpha_tod_a_unsaturated", g_tod_a_unsaturated);
  autoport_proof::publish_text("ao_alpha_state_prepass", "T0.a<alpha_min*255/512");
  autoport_proof::publish_text("ao_alpha_state_color",
                               "tod.a*4*T0.a<alpha_min|>alpha_max|tfrag3:*mix(1,dist_f,steep_w)");
}
}  // namespace

void interp_time_of_day_slow(const math::Vector<s32, 4> itimes[4],
                             const tfrag3::PackedTimeOfDay& in,
                             math::Vector<u8, 4>* out) {
  // (terme 5, essai 4) L'UNIQUE POINT PAR LEQUEL L'HEURE DU JEU ENTRE DANS LA COULEUR DU DECOR.
  // Pendant la paire d'images que le point F juge, la valeur de la premiere image est rendue a
  // la seconde : le cycle jour/nuit et l'oscillateur de foyer (`update-mood-flames`) cessent de
  // repeindre tfrag, tie, shrub et hfrag entre deux images d'une scene qu'on declare immobile.
  // Hors preuve, `census_tod_pin` rend son argument tel quel. Contrat : PrePass.h.
  itimes = prepass::census_tod_pin(itimes);
  math::Vector<u16, 4> weights[8];
  for (int component = 0; component < 8; component++) {
    int quad_idx = component / 2;
    int word_off = (component % 2 * 2);
    for (int channel = 0; channel < 4; channel++) {
      int word = word_off + (channel / 2);
      int hw_off = channel % 2;

      u32 word_val = itimes[quad_idx][word];
      u32 hw_val = hw_off ? (word_val >> 16) : word_val;
      hw_val = hw_val & 0xff;
      weights[component][channel] = hw_val;
    }
  }

  math::Vector<u16, 4> temp[4];

  for (u32 color_quad = 0; color_quad < (in.color_count + 3) / 4; color_quad++) {
    for (auto& x : temp) {
      x.set_zero();
    }

    const u8* input_ptr = in.data.data() + color_quad * 128;
    for (u32 component = 0; component < 8; component++) {
      for (u32 color = 0; color < 4; color++) {
        for (u32 channel = 0; channel < 4; channel++) {
          temp[color][channel] += weights[component][channel] * (*input_ptr);
          input_ptr++;
        }
      }
    }

    for (u32 color = 0; color < 4; color++) {
      auto& o = out[color_quad * 4 + color];
      for (u32 channel = 0; channel < 3; channel++) {
        o[channel] = std::min(255, temp[color][channel] >> 6);
      }
      o[3] = std::min(128, temp[color][3] >> 6);
    }
  }
  note_tod_alpha(out, in.color_count);
}

void interp_time_of_day(const math::Vector<s32, 4> itimes[4],
                        const tfrag3::PackedTimeOfDay& packed_colors,
                        math::Vector<u8, 4>* out) {
  // (terme 5, essai 4) L'UNIQUE POINT PAR LEQUEL L'HEURE DU JEU ENTRE DANS LA COULEUR DU DECOR.
  // Pendant la paire d'images que le point F juge, la valeur de la premiere image est rendue a
  // la seconde : le cycle jour/nuit et l'oscillateur de foyer (`update-mood-flames`) cessent de
  // repeindre tfrag, tie, shrub et hfrag entre deux images d'une scene qu'on declare immobile.
  // Hors preuve, `census_tod_pin` rend son argument tel quel. Contrat : PrePass.h.
  itimes = prepass::census_tod_pin(itimes);
  math::Vector<u16, 4> weights[8];
  for (int component = 0; component < 8; component++) {
    int quad_idx = component / 2;
    int word_off = (component % 2 * 2);
    for (int channel = 0; channel < 4; channel++) {
      int word = word_off + (channel / 2);
      int hw_off = channel % 2;

      u32 word_val = itimes[quad_idx][word];
      u32 hw_val = hw_off ? (word_val >> 16) : word_val;
      hw_val = hw_val & 0xff;
      weights[component][channel] = hw_val;
    }
  }

  // weight multipliers
  __m128i weights0 = _mm_setr_epi16(weights[0][0], weights[0][1], weights[0][2], weights[0][3],
                                    weights[0][0], weights[0][1], weights[0][2], weights[0][3]);
  __m128i weights1 = _mm_setr_epi16(weights[1][0], weights[1][1], weights[1][2], weights[1][3],
                                    weights[1][0], weights[1][1], weights[1][2], weights[1][3]);
  __m128i weights2 = _mm_setr_epi16(weights[2][0], weights[2][1], weights[2][2], weights[2][3],
                                    weights[2][0], weights[2][1], weights[2][2], weights[2][3]);
  __m128i weights3 = _mm_setr_epi16(weights[3][0], weights[3][1], weights[3][2], weights[3][3],
                                    weights[3][0], weights[3][1], weights[3][2], weights[3][3]);
  __m128i weights4 = _mm_setr_epi16(weights[4][0], weights[4][1], weights[4][2], weights[4][3],
                                    weights[4][0], weights[4][1], weights[4][2], weights[4][3]);
  __m128i weights5 = _mm_setr_epi16(weights[5][0], weights[5][1], weights[5][2], weights[5][3],
                                    weights[5][0], weights[5][1], weights[5][2], weights[5][3]);
  __m128i weights6 = _mm_setr_epi16(weights[6][0], weights[6][1], weights[6][2], weights[6][3],
                                    weights[6][0], weights[6][1], weights[6][2], weights[6][3]);
  __m128i weights7 = _mm_setr_epi16(weights[7][0], weights[7][1], weights[7][2], weights[7][3],
                                    weights[7][0], weights[7][1], weights[7][2], weights[7][3]);

  // saturation: note that alpha is saturated to 128 but the rest are 255.
  // TODO: maybe we should saturate to 255 for everybody (can do this using a single packus) and
  // change the shader to deal with this.
  __m128i sat = _mm_set_epi16(128, 255, 255, 255, 128, 255, 255, 255);

  for (u32 color_quad = 0; color_quad < packed_colors.color_count / 4; color_quad++) {
    // first, load colors. We put 16 bytes / register and don't touch the upper half because we
    // convert u8s to u16s.
    {
      const u8* base = packed_colors.data.data() + color_quad * 128;
      __m128i color0_p = _mm_loadu_si64((const __m128i*)(base + 0));
      __m128i color1_p = _mm_loadu_si64((const __m128i*)(base + 16));
      __m128i color2_p = _mm_loadu_si64((const __m128i*)(base + 32));
      __m128i color3_p = _mm_loadu_si64((const __m128i*)(base + 48));
      __m128i color4_p = _mm_loadu_si64((const __m128i*)(base + 64));
      __m128i color5_p = _mm_loadu_si64((const __m128i*)(base + 80));
      __m128i color6_p = _mm_loadu_si64((const __m128i*)(base + 96));
      __m128i color7_p = _mm_loadu_si64((const __m128i*)(base + 112));

      // unpack to 16-bits. each has 16x 16 bit colors.
      __m128i color0 = _mm_cvtepu8_epi16(color0_p);
      __m128i color1 = _mm_cvtepu8_epi16(color1_p);
      __m128i color2 = _mm_cvtepu8_epi16(color2_p);
      __m128i color3 = _mm_cvtepu8_epi16(color3_p);
      __m128i color4 = _mm_cvtepu8_epi16(color4_p);
      __m128i color5 = _mm_cvtepu8_epi16(color5_p);
      __m128i color6 = _mm_cvtepu8_epi16(color6_p);
      __m128i color7 = _mm_cvtepu8_epi16(color7_p);

      // multiply by weights
      color0 = _mm_mullo_epi16(color0, weights0);
      color1 = _mm_mullo_epi16(color1, weights1);
      color2 = _mm_mullo_epi16(color2, weights2);
      color3 = _mm_mullo_epi16(color3, weights3);
      color4 = _mm_mullo_epi16(color4, weights4);
      color5 = _mm_mullo_epi16(color5, weights5);
      color6 = _mm_mullo_epi16(color6, weights6);
      color7 = _mm_mullo_epi16(color7, weights7);

      // add. This order minimizes dependencies.
      color0 = _mm_adds_epi16(color0, color1);
      color2 = _mm_adds_epi16(color2, color3);
      color4 = _mm_adds_epi16(color4, color5);
      color6 = _mm_adds_epi16(color6, color7);

      color0 = _mm_adds_epi16(color0, color2);
      color4 = _mm_adds_epi16(color4, color6);

      color0 = _mm_adds_epi16(color0, color4);

      // divide, because we multiplied our weights by 2^7.
      color0 = _mm_srli_epi16(color0, 6);

      // saturate
      color0 = _mm_min_epu16(sat, color0);

      // back to u8s.
      auto result = _mm_packus_epi16(color0, color0);

      // store result
      _mm_storel_epi64((__m128i*)(&out[color_quad * 4]), result);
    }

    {
      const u8* base = packed_colors.data.data() + color_quad * 128 + 8;
      __m128i color0_p = _mm_loadu_si64((const __m128i*)(base + 0));
      __m128i color1_p = _mm_loadu_si64((const __m128i*)(base + 16));
      __m128i color2_p = _mm_loadu_si64((const __m128i*)(base + 32));
      __m128i color3_p = _mm_loadu_si64((const __m128i*)(base + 48));
      __m128i color4_p = _mm_loadu_si64((const __m128i*)(base + 64));
      __m128i color5_p = _mm_loadu_si64((const __m128i*)(base + 80));
      __m128i color6_p = _mm_loadu_si64((const __m128i*)(base + 96));
      __m128i color7_p = _mm_loadu_si64((const __m128i*)(base + 112));

      // unpack to 16-bits. each has 16x 16 bit colors.
      __m128i color0 = _mm_cvtepu8_epi16(color0_p);
      __m128i color1 = _mm_cvtepu8_epi16(color1_p);
      __m128i color2 = _mm_cvtepu8_epi16(color2_p);
      __m128i color3 = _mm_cvtepu8_epi16(color3_p);
      __m128i color4 = _mm_cvtepu8_epi16(color4_p);
      __m128i color5 = _mm_cvtepu8_epi16(color5_p);
      __m128i color6 = _mm_cvtepu8_epi16(color6_p);
      __m128i color7 = _mm_cvtepu8_epi16(color7_p);

      // multiply by weights
      color0 = _mm_mullo_epi16(color0, weights0);
      color1 = _mm_mullo_epi16(color1, weights1);
      color2 = _mm_mullo_epi16(color2, weights2);
      color3 = _mm_mullo_epi16(color3, weights3);
      color4 = _mm_mullo_epi16(color4, weights4);
      color5 = _mm_mullo_epi16(color5, weights5);
      color6 = _mm_mullo_epi16(color6, weights6);
      color7 = _mm_mullo_epi16(color7, weights7);

      // add. This order minimizes dependencies.
      color0 = _mm_adds_epi16(color0, color1);
      color2 = _mm_adds_epi16(color2, color3);
      color4 = _mm_adds_epi16(color4, color5);
      color6 = _mm_adds_epi16(color6, color7);

      color0 = _mm_adds_epi16(color0, color2);
      color4 = _mm_adds_epi16(color4, color6);

      color0 = _mm_adds_epi16(color0, color4);

      // divide, because we multiplied our weights by 2^7.
      color0 = _mm_srli_epi16(color0, 6);

      // saturate
      color0 = _mm_min_epu16(sat, color0);

      // back to u8s.
      auto result = _mm_packus_epi16(color0, color0);

      // store result
      _mm_storel_epi64((__m128i*)(&out[color_quad * 4 + 2]), result);
    }
  }
  // Le compte de la boucle est `color_count / 4` quads : on ne lit que ce qui a ete ecrit.
  note_tod_alpha(out, (packed_colors.color_count / 4) * 4);
}

bool sphere_in_view_ref(const math::Vector4f& sphere, const math::Vector4f* planes) {
  math::Vector4f acc =
      planes[0] * sphere.x() + planes[1] * sphere.y() + planes[2] * sphere.z() - planes[3];

  return acc.x() > -sphere.w() && acc.y() > -sphere.w() && acc.z() > -sphere.w() &&
         acc.w() > -sphere.w();
}

// this isn't super efficient, but we spend so little time here it's not worth it to go faster.
void cull_check_all_slow(const math::Vector4f* planes,
                         const std::vector<tfrag3::VisNode>& nodes,
                         const u8* level_occlusion_string,
                         u8* out) {
  if (level_occlusion_string) {
    for (size_t i = 0; i < nodes.size(); i++) {
      u16 my_id = nodes[i].my_id;
      bool not_occluded =
          my_id != 0xffff && level_occlusion_string[my_id / 8] & (1 << (7 - (my_id & 7)));
      out[i] = not_occluded && sphere_in_view_ref(nodes[i].bsphere, planes);
    }
  } else {
    for (size_t i = 0; i < nodes.size(); i++) {
      out[i] = sphere_in_view_ref(nodes[i].bsphere, planes);
    }
  }
}

void make_all_visible_multidraws(std::pair<int, int>* draw_ptrs_out,
                                 GLsizei* counts_out,
                                 void** index_offsets_out,
                                 const std::vector<tfrag3::ShrubDraw>& draws) {
  u64 md_idx = 0;
  for (size_t i = 0; i < draws.size(); i++) {
    const auto& draw = draws[i];
    u64 iidx = draw.first_index_index;
    std::pair<int, int> ds;
    ds.first = md_idx;
    ds.second = 1;
    counts_out[md_idx] = draw.num_indices;
    index_offsets_out[md_idx] = (void*)(iidx * sizeof(u32));
    md_idx++;
    draw_ptrs_out[i] = ds;
  }
}

u32 make_all_visible_multidraws(std::pair<int, int>* draw_ptrs_out,
                                GLsizei* counts_out,
                                void** index_offsets_out,
                                const std::vector<tfrag3::StripDraw>& draws) {
  u64 md_idx = 0;
  u32 num_tris = 0;
  for (size_t i = 0; i < draws.size(); i++) {
    const auto& draw = draws[i];
    u64 iidx = draw.unpacked.idx_of_first_idx_in_full_buffer;
    std::pair<int, int> ds;
    ds.first = md_idx;
    ds.second = 1;
    int num_inds = 0;
    for (auto& grp : draw.vis_groups) {
      num_tris += grp.num_tris;
      num_inds += grp.num_inds;
    }
    counts_out[md_idx] = num_inds;
    index_offsets_out[md_idx] = (void*)(iidx * sizeof(u32));
    draw_ptrs_out[i] = ds;
    md_idx++;
  }
  return num_tris;
}

u32 make_all_visible_index_list(std::pair<int, int>* group_out,
                                u32* idx_out,
                                const std::vector<tfrag3::ShrubDraw>& draws,
                                const u32* idx_in) {
  int idx_buffer_ptr = 0;
  for (size_t i = 0; i < draws.size(); i++) {
    const auto& draw = draws[i];
    std::pair<int, int> ds;
    ds.first = idx_buffer_ptr;
    memcpy(&idx_out[idx_buffer_ptr], idx_in + draw.first_index_index,
           draw.num_indices * sizeof(u32));
    idx_buffer_ptr += draw.num_indices;
    // ── LE RESTART TERMINAL QUE LE FLUX DU SHRUB N'A JAMAIS PORTE ─────────────────────────
    // `Shrub.cpp` (chemin `no_multidraw && batch_singledraw`, c'est-a-dire ANDROID) fusionne
    // les draws contigus de meme texture+mode en UN SEUL `glDrawElements(GL_TRIANGLE_STRIP)`.
    // Son commentaire affirme « every shrub draw's index stream ends with UINT32_MAX » : c'est
    // FAUX. `clean_up_vertex_indices` (decompiler/level_extractor/extract_common.cpp:23-25 et
    // :36-38) ne pousse un restart qu'ENTRE deux strips et jamais a la fin, et
    // `extract_shrub.cpp:567-574` concatene les draws SANS separateur. Chaque frontiere fusionnee
    // fabriquait donc deux triangles-pont reliant les sommets de DEUX INSTANCES differentes —
    // des slivers qui traversent la scene. Le TIE, lui, pousse bien un restart en fin de strip
    // (`extract_tie.cpp:2456-2457`) : il fusionne juste, et il rend `gap64 = 0`.
    // Le restart est ecrit ICI et COMPTE dans `ds.second` : la contiguite `sd2.first ==
    // first + count` sur laquelle repose la fusion reste vraie, mais le strip fusionne est COUPE
    // a chaque frontiere. Un draw vide n'en recoit pas : `second == 0` doit rester le temoin
    // « rien a dessiner » que la boucle de fusion lit.
    if (draw.num_indices) {
      idx_out[idx_buffer_ptr++] = UINT32_MAX;
    }
    ds.second = idx_buffer_ptr - ds.first;
    group_out[i] = ds;
  }
  return idx_buffer_ptr;
}

u32 make_multidraws_from_vis_string(std::pair<int, int>* draw_ptrs_out,
                                    GLsizei* counts_out,
                                    void** index_offsets_out,
                                    const std::vector<tfrag3::StripDraw>& draws,
                                    const std::vector<u8>& vis_data) {
  u64 md_idx = 0;
  u32 num_tris = 0;
  u32 sanity_check = 0;
  for (size_t i = 0; i < draws.size(); i++) {
    const auto& draw = draws[i];
    u64 iidx = draw.unpacked.idx_of_first_idx_in_full_buffer;
    ASSERT(sanity_check == iidx);
    std::pair<int, int> ds;
    ds.first = md_idx;
    ds.second = 0;
    bool building_run = false;
    u64 run_start = 0;
    for (auto& grp : draw.vis_groups) {
      sanity_check += grp.num_inds;
      bool vis = grp.vis_idx_in_pc_bvh == UINT16_MAX || vis_data[grp.vis_idx_in_pc_bvh];
      if (vis) {
        num_tris += grp.num_tris;
      }

      if (building_run) {
        if (!vis) {
          building_run = false;
          counts_out[md_idx] = iidx - run_start;
          index_offsets_out[md_idx] = (void*)(run_start * sizeof(u32));
          ds.second++;
          md_idx++;
        }
      } else {
        if (vis) {
          building_run = true;
          run_start = iidx;
        }
      }

      iidx += grp.num_inds;
    }

    if (building_run) {
      building_run = false;
      counts_out[md_idx] = iidx - run_start;
      index_offsets_out[md_idx] = (void*)(run_start * sizeof(u32));
      ds.second++;
      md_idx++;
    }

    draw_ptrs_out[i] = ds;
  }
  return num_tris;
}

u32 make_multidraws_from_vis_and_proto_string(std::pair<int, int>* draw_ptrs_out,
                                              GLsizei* counts_out,
                                              void** index_offsets_out,
                                              const std::vector<tfrag3::StripDraw>& draws,
                                              const std::vector<u8>& vis_data,
                                              const std::vector<u8>& proto_vis_data) {
  u64 md_idx = 0;
  u32 num_tris = 0;
  u32 sanity_check = 0;
  for (size_t i = 0; i < draws.size(); i++) {
    const auto& draw = draws[i];
    u64 iidx = draw.unpacked.idx_of_first_idx_in_full_buffer;
    ASSERT(sanity_check == iidx);
    std::pair<int, int> ds;
    ds.first = md_idx;
    ds.second = 0;
    bool building_run = false;
    u64 run_start = 0;
    for (auto& grp : draw.vis_groups) {
      sanity_check += grp.num_inds;
      bool vis = (grp.vis_idx_in_pc_bvh == UINT16_MAX || vis_data[grp.vis_idx_in_pc_bvh]) &&
                 proto_vis_data[grp.tie_proto_idx];
      if (vis) {
        num_tris += grp.num_tris;
      }

      if (building_run) {
        if (!vis) {
          building_run = false;
          counts_out[md_idx] = iidx - run_start;
          index_offsets_out[md_idx] = (void*)(run_start * sizeof(u32));
          ds.second++;
          md_idx++;
        }
      } else {
        if (vis) {
          building_run = true;
          run_start = iidx;
        }
      }

      iidx += grp.num_inds;
    }

    if (building_run) {
      building_run = false;
      counts_out[md_idx] = iidx - run_start;
      index_offsets_out[md_idx] = (void*)(run_start * sizeof(u32));
      ds.second++;
      md_idx++;
    }

    draw_ptrs_out[i] = ds;
  }
  return num_tris;
}

u32 make_index_list_from_vis_string(std::pair<int, int>* group_out,
                                    u32* idx_out,
                                    const std::vector<tfrag3::StripDraw>& draws,
                                    const std::vector<u8>& vis_data,
                                    const u32* idx_in,
                                    u32* num_tris_out) {
  int idx_buffer_ptr = 0;
  u32 num_tris = 0;
  for (size_t i = 0; i < draws.size(); i++) {
    const auto& draw = draws[i];
    int vtx_idx = 0;
    std::pair<int, int> ds;
    ds.first = idx_buffer_ptr;
    bool building_run = false;
    int run_start_out = 0;
    int run_start_in = 0;
    for (auto& grp : draw.vis_groups) {
      bool vis = grp.vis_idx_in_pc_bvh == UINT16_MAX || vis_data[grp.vis_idx_in_pc_bvh];
      if (vis) {
        num_tris += grp.num_tris;
      }

      if (building_run) {
        if (vis) {
          idx_buffer_ptr += grp.num_inds;
        } else {
          building_run = false;
          memcpy(&idx_out[run_start_out],
                 idx_in + draw.unpacked.idx_of_first_idx_in_full_buffer + run_start_in,
                 (idx_buffer_ptr - run_start_out) * sizeof(u32));
        }
      } else {
        if (vis) {
          building_run = true;
          run_start_out = idx_buffer_ptr;
          run_start_in = vtx_idx;
          idx_buffer_ptr += grp.num_inds;
        }
      }
      vtx_idx += grp.num_inds;
    }

    if (building_run) {
      memcpy(&idx_out[run_start_out],
             idx_in + draw.unpacked.idx_of_first_idx_in_full_buffer + run_start_in,
             (idx_buffer_ptr - run_start_out) * sizeof(u32));
    }

    ds.second = idx_buffer_ptr - ds.first;
    group_out[i] = ds;
  }
  *num_tris_out = num_tris;
  return idx_buffer_ptr;
}

u32 make_index_list_from_vis_and_proto_string(std::pair<int, int>* group_out,
                                              u32* idx_out,
                                              const std::vector<tfrag3::StripDraw>& draws,
                                              const std::vector<u8>& vis_data,
                                              const std::vector<u8>& proto_vis_data,
                                              const u32* idx_in,
                                              u32* num_tris_out) {
  int idx_buffer_ptr = 0;
  u32 num_tris = 0;
  for (size_t i = 0; i < draws.size(); i++) {
    const auto& draw = draws[i];
    int vtx_idx = 0;
    std::pair<int, int> ds;
    ds.first = idx_buffer_ptr;
    bool building_run = false;
    int run_start_out = 0;
    int run_start_in = 0;
    for (auto& grp : draw.vis_groups) {
      bool vis = (grp.vis_idx_in_pc_bvh == UINT16_MAX || vis_data[grp.vis_idx_in_pc_bvh]) &&
                 proto_vis_data[grp.tie_proto_idx];
      if (vis) {
        num_tris += grp.num_tris;
      }

      if (building_run) {
        if (vis) {
          idx_buffer_ptr += grp.num_inds;
        } else {
          building_run = false;
          memcpy(&idx_out[run_start_out],
                 idx_in + draw.unpacked.idx_of_first_idx_in_full_buffer + run_start_in,
                 (idx_buffer_ptr - run_start_out) * sizeof(u32));
        }
      } else {
        if (vis) {
          building_run = true;
          run_start_out = idx_buffer_ptr;
          run_start_in = vtx_idx;
          idx_buffer_ptr += grp.num_inds;
        }
      }
      vtx_idx += grp.num_inds;
    }

    if (building_run) {
      memcpy(&idx_out[run_start_out],
             idx_in + draw.unpacked.idx_of_first_idx_in_full_buffer + run_start_in,
             (idx_buffer_ptr - run_start_out) * sizeof(u32));
    }

    ds.second = idx_buffer_ptr - ds.first;
    group_out[i] = ds;
  }
  *num_tris_out = num_tris;
  return idx_buffer_ptr;
}

u32 make_all_visible_index_list(std::pair<int, int>* group_out,
                                u32* idx_out,
                                const std::vector<tfrag3::StripDraw>& draws,
                                const u32* idx_in,
                                u32* num_tris_out) {
  int idx_buffer_ptr = 0;
  u32 num_tris = 0;
  for (size_t i = 0; i < draws.size(); i++) {
    const auto& draw = draws[i];
    std::pair<int, int> ds;
    ds.first = idx_buffer_ptr;
    u32 num_inds = 0;
    for (auto& grp : draw.vis_groups) {
      num_inds += grp.num_inds;
      num_tris += grp.num_tris;
    }
    memcpy(&idx_out[idx_buffer_ptr], idx_in + draw.unpacked.idx_of_first_idx_in_full_buffer,
           num_inds * sizeof(u32));
    idx_buffer_ptr += num_inds;
    ds.second = idx_buffer_ptr - ds.first;
    group_out[i] = ds;
  }
  *num_tris_out = num_tris;
  return idx_buffer_ptr;
}

void update_render_state_from_pc_settings(SharedRenderState* state, const TfragPcPortData& data) {
  if (!state->has_pc_data) {
    for (int i = 0; i < 4; i++) {
      state->camera_planes[i] = data.camera.planes[i];
      state->camera_matrix[i] = data.camera.camera[i];
      state->itimes[i] = data.camera.itimes[i];  // POLISH#8 grass: live TOD weights for location-aware light
    }
    state->camera_pos = data.camera.trans;
    state->camera_hvdf_off = data.camera.hvdf_off;
    state->camera_fog = data.camera.fog;
    state->has_pc_data = true;
    // lighting-ao-indirect : LA camera de l'image vient d'etre lue, aucun draw ombre n'a encore
    // eu lieu — c'est ici, et une seule fois par image, que la prepasse de profondeur et
    // l'estimation d'AO tournent (PrePass.cpp).
    // lighting-ao-indirect (amendement §4.3) : le bloc d'image est a jour avant la prepasse.
    frame_ubo::update_and_bind(data.camera, state);
#ifdef OG_FEAT_PBR
    // lighting-shadows (SPEC §4.8) : l'atlas d'ombre tourne AVANT la prepasse d'AO — c'est LUI
    // qui rejoue les contributeurs (`prepass::draw_shadow_casters`), donc son propre entretien
    // (bascule, matrices, effacement de l'atlas d'ecriture) doit etre a jour en premier.
    pbr_shadow_first_camera(state, data.camera);
#endif
    prepass::on_first_camera(state, data.camera);
  }
}

// =================================================================================================
// mesh-consolidate-without-consumer (2026-09-13) — LE RECENSEMENT DES CONSOMMATEURS.
// Aucun grep : le pilote GL est la seule autorite sur « qui lit cet attribut ». Un attribut declare
// mais jamais lu est RETIRE par le compilateur GLSL, donc absent de la liste des attributs ACTIFS.
// =================================================================================================
namespace mesh_unconsumed_census {
namespace {
std::set<std::pair<u64, int>> s_seen_pairs;
uint64_t s_pairs_probed = 0;
uint64_t s_seam_readers = 0;
uint64_t s_active_attrs_seen = 0;
uint64_t s_programs_probed = 0;
uint64_t s_tess_programs = 0;
bool s_library_probed = false;
}  // namespace

void probe_bound_attrib(u64 program, int location) {
  if (!program) {
    return;
  }
  const auto key = std::make_pair(program, location);
  if (!s_seen_pairs.insert(key).second) {
    return;
  }
  s_pairs_probed++;
  GLint n = 0;
  GLint max_len = 0;
  glGetProgramiv((GLuint)program, GL_ACTIVE_ATTRIBUTES, &n);
  glGetProgramiv((GLuint)program, GL_ACTIVE_ATTRIBUTE_MAX_LENGTH, &max_len);
  s_active_attrs_seen += (uint64_t)(n < 0 ? 0 : n);
  if (max_len < 1) {
    max_len = 1;
  }
  std::vector<char> name((size_t)max_len + 1, 0);
  for (GLint i = 0; i < n; i++) {
    GLsizei written = 0;
    GLint size = 0;
    GLenum type = 0;
    name[0] = 0;
    glGetActiveAttrib((GLuint)program, (GLuint)i, max_len, &written, &size, &type, name.data());
    name[(size_t)max_len] = 0;
    const GLint loc = glGetAttribLocation((GLuint)program, name.data());
    if (loc == location) {
      s_seam_readers++;
    }
  }
}

void probe_library(ShaderLibrary& shaders) {
  if (s_library_probed) {
    return;
  }
  s_library_probed = true;
  for (int id = 0; id < (int)ShaderId::MAX_SHADERS; id++) {
    auto& sh = shaders[(ShaderId)id];
    if (!sh.okay()) {
      continue;
    }
    s_programs_probed++;
#if defined(GL_TESS_EVALUATION_SHADER) && defined(GL_TESS_CONTROL_SHADER)
    GLuint attached[8] = {};
    GLsizei count = 0;
    glGetAttachedShaders((GLuint)sh.id(), 8, &count, attached);
    for (GLsizei i = 0; i < count; i++) {
      GLint t = 0;
      glGetShaderiv(attached[i], GL_SHADER_TYPE, &t);
      if (t == GL_TESS_EVALUATION_SHADER || t == GL_TESS_CONTROL_SHADER) {
        s_tess_programs++;
        break;
      }
    }
#endif
  }
}

void publish() {
  // CE SITE EST DANS LE CHEMIN DE DESSIN — appele une fois par arbre et par image. Les comptes ne
  // bougent qu'a la DECOUVERTE d'un couple neuf (une poignee de fois par course) : republier a
  // chaque arbre ne ferait que prendre un mutex des milliers de fois par seconde dans un projet
  // dont la plainte ouverte est le temps par image. On ne republie que ce qui a change.
  static uint64_t s_last = UINT64_MAX;
  const uint64_t etat = s_pairs_probed * 1000003u + s_seam_readers * 101u + s_active_attrs_seen +
                        s_programs_probed * 7u + s_tess_programs * 13u;
  if (etat == s_last) {
    return;
  }
  s_last = etat;
  autoport_proof::publish("mesh_seam_attrib_pairs_probed", s_pairs_probed);
  autoport_proof::publish("mesh_seam_attrib_readers", s_seam_readers);
  autoport_proof::publish("mesh_seam_attrib_active_seen", s_active_attrs_seen);
  autoport_proof::publish("mesh_programs_probed", s_programs_probed);
  autoport_proof::publish("mesh_tess_stage_programs", s_tess_programs);
#if defined(GL_TESS_EVALUATION_SHADER) && defined(GL_TESS_CONTROL_SHADER)
  autoport_proof::publish("mesh_tess_enum_known", 1);
#else
  autoport_proof::publish("mesh_tess_enum_known", 0);
#endif
}
}  // namespace mesh_unconsumed_census
