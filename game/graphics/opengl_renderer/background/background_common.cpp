

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
#include "game/graphics/pipelines/opengl.h"
#include "game/system/autoport_proof.h"
AUTOPORT_FEATURE_SITE("gl-uniforms-off-cost");
AUTOPORT_FEATURE_SITE("lighting-off-math-still-runs");

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
// GLSL-style smoothstep (C1 Hermite ramp), clamped to [0,1]. Used for the sun/green-sun
// elevation crossfade so the yellow<->green handoff is gradual in BOTH intensity and colour.
static inline float rt_smoothstep(float e0, float e1, float x) {
  float t = (x - e0) / (e1 - e0);
  t = t < 0.f ? 0.f : (t > 1.f ? 1.f : t);
  return t * t * (3.f - 2.f * t);
}

// Right-handed lookAt into column-major float[16].
static void pbr_look_at(PbrV3 eye, PbrV3 center, PbrV3 up, float out[16]) {
  PbrV3 f = pv_norm(pv_sub(center, eye));  // forward (-z)
  PbrV3 s = pv_norm(pv_cross(f, up));      // right (+x)
  PbrV3 u = pv_cross(s, f);                // true up (+y)
  // column 0
  out[0] = s.x;
  out[1] = u.x;
  out[2] = -f.x;
  out[3] = 0.f;
  // column 1
  out[4] = s.y;
  out[5] = u.y;
  out[6] = -f.y;
  out[7] = 0.f;
  // column 2
  out[8] = s.z;
  out[9] = u.z;
  out[10] = -f.z;
  out[11] = 0.f;
  // column 3 (translation)
  out[12] = -pv_dot(s, eye);
  out[13] = -pv_dot(u, eye);
  out[14] = pv_dot(f, eye);
  out[15] = 1.f;
}

// Right-handed orthographic projection into column-major float[16], NDC z in [-1,1].
static void pbr_ortho(float l,
                      float r,
                      float b,
                      float t,
                      float n,
                      float fpl,
                      float out[16]) {
  for (int i = 0; i < 16; i++) {
    out[i] = 0.f;
  }
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

// Read the shadow-map quality prop ONCE per frame (Android prop / desktop env), cached on
// frame_idx so this never re-reads on every begin_frame call within a frame. Default ON.
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
}  // namespace

void pbr_shadow_ensure_resources() {
  auto& st = pbr_shadow_state();
  if (st.fbo[0] || st.depth_tex[0]) {
    return;  // already tried once (valid or permanently failed)
  }
  gl_query_census::Armed _ap("pbr-shadow-resources");
  // Save FBO + viewport; we bind our own to clear the fresh depth textures to 1.0.
  GLint prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0};
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev_fbo);
  glGetIntegerv(GL_VIEWPORT, prev_vp);

  // ROUND-4 Very High (8192) tier VRAM/limit guard: clamp the requested shadow-map size to
  // the driver's GL_MAX_TEXTURE_SIZE so a weak GPU (Adreno 618) never asks for an
  // unsupported allocation. (Genuine OOM at the top tier is caught below via glGetError.)
  {
    const GLint max_tex = gl_query_census::limit(GL_MAX_TEXTURE_SIZE);
    if (max_tex > 0 && st.size > max_tex) {
      st.size = max_tex;
    }
    while (glGetError() != GL_NO_ERROR) {
    }
  }

  st.valid = true;
  for (int i = 0; i < 2; i++) {
    glGenTextures(1, &st.depth_tex[i]);
    glBindTexture(GL_TEXTURE_2D, st.depth_tex[i]);
    // DEPTH_COMPONENT16 + NEAREST: the maximally-compatible shadow-map config on mobile
    // (Adreno 618 returned constant 1.0 from the compare sampler with the classier
    // DEPTH_COMPONENT24 + LINEAR config — device-proven this phase). The 4-tap PCF in
    // tfrag3.frag still smooths the edge.
    glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT16, st.size, st.size, 0, GL_DEPTH_COMPONENT,
                 GL_UNSIGNED_SHORT, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    // MANUAL compare (COMPARE_MODE NONE + plain sampler2D + in-shader ref<=d test):
    // the Adreno 618 GLES driver returned a constant 1.0 through the HW compare path
    // (sampler2DShadow, REF_TO_TEXTURE, proven with a 0.25-cleared map this phase);
    // depth-as-float sampling works everywhere. tfrag3.frag does 4 manual PCF taps.
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_NONE);

    glGenFramebuffers(1, &st.fbo[i]);
    glBindFramebuffer(GL_FRAMEBUFFER, st.fbo[i]);
    glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, st.depth_tex[i], 0);
    GLenum none = GL_NONE;
    glDrawBuffers(1, &none);
    glReadBuffer(GL_NONE);  // GLES3 has glReadBuffer, so unguarded is fine.

    if (glCheckFramebufferStatus(GL_FRAMEBUFFER) != GL_FRAMEBUFFER_COMPLETE) {
      lg::error("Grecharged-pbr-materials: shadow-map FBO incomplete; disabling sun shadows");
      st.valid = false;
    } else {
      // Clear the depth texture to 1.0 so an unrendered map means fully lit.
      glViewport(0, 0, st.size, st.size);
#ifdef __ANDROID__
      glClearDepthf(1.0f);
#else
      glClearDepth(1.0);
#endif
      glClear(GL_DEPTH_BUFFER_BIT);
    }
  }

  // ROUND-4: if the driver rejected the top-tier allocation (GL_OUT_OF_MEMORY / unsupported),
  // fall back to a safe 2048 map and re-allocate instead of crashing or rendering broken.
  if (glGetError() != GL_NO_ERROR && st.size > 2048) {
    lg::warn("Grecharged-realtime-lighting: shadow-map {}x{} alloc failed; falling back to 2048",
             st.size, st.size);
    glDeleteFramebuffers(2, st.fbo);
    glDeleteTextures(2, st.depth_tex);
    st.fbo[0] = 0;
    st.fbo[1] = 0;
    st.depth_tex[0] = 0;
    st.depth_tex[1] = 0;
    st.size = 2048;
    st.valid = true;
    glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
    glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
    glBindTexture(GL_TEXTURE_2D, 0);
    pbr_shadow_ensure_resources();
    return;
  }

  // Restore prior FBO + viewport.
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

bool pbr_shadow_begin_frame(u64 frame_idx, const float* cam_trans) {
  auto& st = pbr_shadow_state();
  // ROUND 2: shadows are driven by EITHER the pbr-materials toggle OR the sun-only realtime-
  // lighting toggle (they are independent — the dev state is pbr-materials OFF, realtime
  // lighting ON, so gating on pbr_enable alone would silently kill the sun's cast shadows).
  // SPEC §6.2 : les ombres portees sont SOUS l'eclairage recharge. Eteindre l'eclairage passe
  // par ici, remet `read_valid` a faux, et pbr_shadow_bind_receiver pousse alors
  // u_pbr_shadow_on = 0 — le composite E de shade.glsl s'eteint avec le reste.
  if (!(recharged_gating::on(recharged_gating::kLighting) ||
        recharged_gating::on(recharged_gating::kRtLight)) ||
      !pbr_shadowmap_enabled_for_frame(frame_idx)) {
    // Feature off: also invalidate the read side so receivers stop sampling a map that
    // will no longer be refreshed (stale-matrix shadows glued to the old camera pos).
    st.read_valid = false;
    st.have_mvp = false;
    return false;
  }
  // lighting-legacy-purge (2026-09-11) : la QUALITE et la DISTANCE de l'ombre portee ne sont plus
  // des reglages. Elles valent ce que le jeu LIVRAIT — RechargedFixed::kRtShadowRes (2048, le
  // palier « Med » ou l'ancienne echelle tombait deja) et kRtShadowDist (150 m de demi-etendue,
  // dans les bornes 15..200 de l'ancien clamp) — donc ni le paliers-snap, ni le clamp, ni les
  // surcharges de propriete `debug.opengoal.rt.shadowres` / `.shadowdist` n'ont plus d'objet : une
  // surcharge de propriete sur un reglage supprime est exactement la survivance que cet item
  // retire. La resolution ne changeant plus en cours de course, la reallocation des textures de
  // profondeur part avec elle : la premiere allocation suffit.
  st.shadow_half = RechargedFixed::kRtShadowDist;
  if (!st.depth_tex[0]) {
    st.size = RechargedFixed::kRtShadowRes;
  }
  pbr_shadow_ensure_resources();
  if (!st.valid) {
    return false;
  }

  if (st.frame == frame_idx) {
    // Same frame: the write map was already cleared + mvp computed this frame; keep
    // rendering additively across trees/renderers without re-clearing.
    return st.have_mvp;
  }

  // Debug telemetry (env OG_PBR_SHADOW_DEBUG / prop debug.opengoal.pbr.shadowdbg=1):
  // caster index count + buffer state once a second; on desktop also a depth readback of
  // last frame's completed write map (glReadPixels on a depth attachment is desktop-GL
  // only) + a periodic internal screenshot. Answers "did the depth pass draw anything
  // and does the map contain occluders" without needing a visual capture.
#ifdef __ANDROID__
  {
    char v[PROP_VALUE_MAX];
    st.debug = __system_property_get("debug.opengoal.pbr.shadowdbg", v) > 0 && v[0] == '1';
  }
#else
  st.debug = std::getenv("OG_PBR_SHADOW_DEBUG") != nullptr;
#endif
  if (st.debug && st.valid && st.have_mvp && frame_idx % 60 == 0) {
#ifndef __ANDROID__
    gl_query_census::Armed _ap_dbg("pbr-shadow-debug");
    GLint dbg_prev_fbo = 0;
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &dbg_prev_fbo);
    glBindFramebuffer(GL_FRAMEBUFFER, st.fbo[st.write]);
    static std::vector<float> dbg_buf;
    dbg_buf.resize((size_t)st.size * st.size);
    glReadPixels(0, 0, st.size, st.size, GL_DEPTH_COMPONENT, GL_FLOAT, dbg_buf.data());
    size_t lt = 0;
    float mn = 1.f;
    for (float d : dbg_buf) {
      if (d < 0.999f) {
        lt++;
      }
      if (d < mn) {
        mn = d;
      }
    }
    lg::info("PBR-SHADOW-DBG frame={} cast_idx={} frac(depth<0.999)={:.4f} min={:.4f}",
             frame_idx, st.cast_indices, (double)lt / dbg_buf.size(), mn);
    // Owner-repro phantom-lines diagnostic: env OG_PBR_SHADOW_DUMP=<dir> also writes the
    // raw depth map as an 8-bit PGM + the matrix/meta, so sliver/bogus casters are visible
    // directly in the map instead of inferred from the ground artifact. Desktop-only.
    if (const char* dump_dir = std::getenv("OG_PBR_SHADOW_DUMP")) {
      char path[512];
      snprintf(path, sizeof(path), "%s/shadowmap_f%06llu.pgm", dump_dir,
               (unsigned long long)frame_idx);
      if (FILE* f = fopen(path, "wb")) {
        fprintf(f, "P5\n%d %d\n255\n", st.size, st.size);
        static std::vector<unsigned char> dump8;
        dump8.resize(dbg_buf.size());
        for (size_t i = 0; i < dbg_buf.size(); i++) {
          float d = dbg_buf[i];
          dump8[i] = (unsigned char)(d >= 1.0f ? 255 : (d < 0.f ? 0 : d * 255.f));
        }
        fwrite(dump8.data(), 1, dump8.size(), f);
        fclose(f);
        snprintf(path, sizeof(path), "%s/shadowmap_f%06llu.txt", dump_dir,
                 (unsigned long long)frame_idx);
        if (FILE* m = fopen(path, "w")) {
          fprintf(m, "size=%d half=%.2f light=%d cam=%.2f %.2f %.2f\nmvp=", st.size,
                  st.shadow_half, st.shadow_light, st.write_cam[0] / 4096.f,
                  st.write_cam[1] / 4096.f, st.write_cam[2] / 4096.f);
          for (int i = 0; i < 16; i++) {
            fprintf(m, "%.6f ", st.mvp[i]);
          }
          fprintf(m, "\n");
          fclose(m);
        }
      }
    }
    glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)dbg_prev_fbo);
    if (frame_idx % 600 == 0) {
      // Periodic internal screenshot (headless-friendly visual): lands in the standard
      // screenshots dir via the engine's own pipeline.
      g_want_screenshot = true;
    }
#else
    lg::info("PBR-SHADOW-DBG frame={} cast_idx={} write={} read_valid={} legacy={:.2f}",
             frame_idx, st.cast_indices, st.write, (int)st.read_valid, st.legacy_strength);
#endif
  }
  st.cast_indices = 0;

  // NEW FRAME: promote last frame's completed write buffer to the read side (receivers
  // sample it with its matching matrix), then start writing into the other buffer. On a
  // frame gap (pause, level load) the pair may be stale; keep it read_valid anyway — map
  // and matrix are still mutually consistent, shadows just freeze until the next pass.
  if (st.have_mvp) {
    memcpy(st.read_mvp, st.mvp, sizeof(st.read_mvp));
    // Suspect (d): promote the camera anchor together with the matrix — the read map is
    // only meaningful around the cam_trans it was written with.
    memcpy(st.read_cam, st.write_cam, sizeof(st.read_cam));
    // Item 1: promote which light (yellow=0 / green=1) this completed map was rendered from,
    // together with its matrix, so receivers attribute the occlusion to the matching term.
    st.read_shadow_light = st.shadow_light;
    st.read_valid = true;
    st.write = 1 - st.write;
  }
  st.have_mvp = false;

  // Legacy-receiver darkening strength (owner clarification 2026-07-18: the world's
  // shadow must land on NON-PBR ground too). Prop-tunable for device calibration so
  // already-baked painted shadows don't double-darken into black.
  st.legacy_strength = 0.35f;
  // Round-5: full-caster-set toggle (default ON = the fix; 0 = old vis-culled repro).
  st.cast_full = true;
#ifdef __ANDROID__
  {
    char v[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.pbr.legacyshadow", v) > 0 && v[0]) {
      st.legacy_strength = (float)atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.castfull", v) > 0 && v[0]) {
      st.cast_full = atoi(v) != 0;
    }
  }
#else
  if (const char* e = std::getenv("OG_PBR_LEGACY_SHADOW")) {
    st.legacy_strength = (float)std::atof(e);
  }
  if (const char* e = std::getenv("OG_PBR_CASTFULL")) {
    st.cast_full = std::atoi(e) != 0;
  }
#endif

  // ---- Compute the light matrix (camera-relative meters). ----
  const auto& gs = Gfx::settings();
  // Round-5 addendum suspect (c) — ATTRIBUTABILITY: shadows must extend opposite the
  // VISIBLE sun. Primary = the sky-dome sun direction (*sky-parms* upload-data sun 0 pos,
  // the exact camera->sun vector sparticle-track-sun places the sun sprite with) — it
  // tracks the true sun elevation across the TOD. current-shadow CANNOT align: update-
  // mood-shadow-direction hard-clamps it to a constant ~65deg (y=-0.9063), which is why
  // every world shadow was short+steep and unattributable. Fallbacks: current-shadow
  // (sun below horizon / pre-push), then the light-group blend (pre-any-push).
  PbrV3 dir = {0.f, 0.f, 0.f};
  st.shadow_light = 0;  // default: the yellow sun owns the shadow (day)
  // OWNER PLAYTEST #4 — the yellow<->green shadow-map handoff must not be a brutal step. The single
  // depth map is rendered from whichever sun is HIGHER in the sky (max elevation), so ownership flips
  // at the elevation CROSSOVER rather than the instant the yellow sun clips the horizon. The cast-shadow
  // STRENGTH is faded by the owning sun's own elevation weight (u_rt_shadow_conf, computed in
  // first_tfrag_draw_setup): at the crossover both suns are below the ramp so their weights (and the
  // shadow) are ~0 => the ownership flip is invisible (stepless). A sun owns the map only while it is
  // within its elevation ramp (down to the low end -0.05); below that its light term (and its shadow) is 0.
  {
    PbrV3 ss = {gs.recharged_pbr_sky_sun[0], gs.recharged_pbr_sky_sun[1],
                gs.recharged_pbr_sky_sun[2]};
    PbrV3 gsun = {gs.recharged_pbr_green_sun[0], gs.recharged_pbr_green_sun[1],
                  gs.recharged_pbr_green_sun[2]};
    float ssl = std::sqrt(pv_dot(ss, ss));
    float gln = std::sqrt(pv_dot(gsun, gsun));
    float sun_up = (ssl > 1e-3f) ? ss.y / ssl : -2.f;    // yellow elevation sine (-2 = unpushed)
    float grn_up = (gln > 1e-3f) ? gsun.y / gln : -2.f;  // green  elevation sine
    const float OWN_LO = -0.05f;                          // == ambient elevation-ramp low end (attempt-9)
    if (sun_up >= grn_up && sun_up > OWN_LO) {
      dir = {ss.x / ssl, ss.y / ssl, ss.z / ssl};  // yellow is the higher sun -> it casts
      st.shadow_light = 0;
    } else if (grn_up > sun_up && grn_up > OWN_LO) {
      dir = {gsun.x / gln, gsun.y / gln, gsun.z / gln};  // green is the higher sun -> it casts (item 1)
      st.shadow_light = 1;
    }
  }
  if (pv_dot(dir, dir) < 1e-8f) {
    // Neither sun above the horizon: fall back to current-shadow (light-travel; negate for
    // surface->light). Attribute to the yellow-sun term (shadow_light=0) — that term is ~0 here
    // (night fade), so the fallback map is effectively invisible, no artifact.
    st.shadow_light = 0;
    dir = {-gs.recharged_pbr_shadow[0], -gs.recharged_pbr_shadow[1],
           -gs.recharged_pbr_shadow[2]};
  }
  if (pv_dot(dir, dir) < 1e-8f && gs.recharged_pbr_lg_valid) {
    // Fallback (shadow vector not pushed yet): weighted light-group blend as before.
    for (int i = 0; i < 3; i++) {
      PbrV3 ld = {-gs.recharged_pbr_lg_dir[i][0], -gs.recharged_pbr_lg_dir[i][1],
                  -gs.recharged_pbr_lg_dir[i][2]};  // GOAL dir is light-travel; want surface->light
      float ll = std::sqrt(pv_dot(ld, ld));
      if (ll < 1e-5f) {
        continue;  // degenerate dir
      }
      float lum = 0.2126f * gs.recharged_pbr_lg_color[i][0] +
                  0.7152f * gs.recharged_pbr_lg_color[i][1] +
                  0.0722f * gs.recharged_pbr_lg_color[i][2];
      float wi = gs.recharged_pbr_lg_level[i] * lum;
      dir.x += (ld.x / ll) * wi;
      dir.y += (ld.y / ll) * wi;
      dir.z += (ld.z / ll) * wi;
    }
  }
  PbrV3 L = pv_norm(dir);  // surface->sun unit vector
  if (pv_dot(L, L) < 1e-4f) {
    return false;
  }

  // ROUND 2: the sun "eye" distance and ortho far plane scale with the Shadow Distance so
  // the whole box stays enclosed at any range (eye must sit beyond the box half-extent).
  const float half = st.shadow_half;        // Shadow Distance: ortho half-extent (meters)
  const float eyed = half * 2.0f + 40.0f;   // sun eye distance from the box center
  PbrV3 eye = {L.x * eyed, L.y * eyed, L.z * eyed};
  PbrV3 target = {0.f, 0.f, 0.f};
  PbrV3 up = std::fabs(L.y) > 0.95f ? PbrV3{1.f, 0.f, 0.f} : PbrV3{0.f, 1.f, 0.f};

  float view[16];
  pbr_look_at(eye, target, up, view);

  // TEXEL SNAP (stable-shadow trick), round-5 corrected: the shadow space is
  // CAMERA-RELATIVE meters (shaders subtract cam_trans), so the camera's translation is
  // what shifts world geometry across the light-space texel grid — quantize ITS projection
  // onto the light right/up axes to whole texels. (The previous snap quantized the view
  // translation of the space's origin, which depends only on the sun direction — a no-op
  // for camera movement.) The window itself is a constant-size box centered on the camera
  // position, so camera ROTATION cannot change the fit (the round-5 rotation bug was the
  // vis-culled caster set, fixed in the depth passes). Ortho spans 80 world units across
  // 1024 texels.
  const float texel_world = (2.0f * half) / (float)st.size;
  // Camera position in meters; its light-space x/y via the s/u rows of the view matrix.
  const float cmx = cam_trans[0] / 4096.f, cmy = cam_trans[1] / 4096.f,
              cmz = cam_trans[2] / 4096.f;
  float tx = view[0] * cmx + view[4] * cmy + view[8] * cmz;
  float ty = view[1] * cmx + view[5] * cmy + view[9] * cmz;
  view[12] += tx - std::floor(tx / texel_world) * texel_world;
  view[13] += ty - std::floor(ty / texel_world) * texel_world;

  float proj[16];
  pbr_ortho(-half, half, -half, half, 0.5f, eyed + half + 10.0f, proj);

  pbr_mat_mul(proj, view, st.mvp);
  st.write_cam[0] = cam_trans[0];
  st.write_cam[1] = cam_trans[1];
  st.write_cam[2] = cam_trans[2];
  st.have_mvp = true;
  st.frame = frame_idx;

  // Clear the WRITE depth map for the new frame (state save/restore).
  GLint prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0};
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev_fbo);
  glGetIntegerv(GL_VIEWPORT, prev_vp);
  glBindFramebuffer(GL_FRAMEBUFFER, st.fbo[st.write]);
  glViewport(0, 0, st.size, st.size);
  GLboolean prev_depth_mask = GL_TRUE;
  glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);
  glDepthMask(GL_TRUE);
  // Debug probe (prop debug.opengoal.pbr.cleardepth / OG_PBR_CLEARDEPTH): clearing the
  // map to e.g. 0.25 must darken every in-box receiver if the compare+binding chain
  // works — isolates receiver-side failures from caster-side ones. Default 1.0 = normal.
  float clear_depth = 1.0f;
#ifdef __ANDROID__
  {
    char cv[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.pbr.cleardepth", cv) > 0 && cv[0]) {
      clear_depth = atof(cv);
    }
  }
  glClearDepthf(clear_depth);
#else
  if (const char* ce = std::getenv("OG_PBR_CLEARDEPTH")) {
    clear_depth = (float)std::atof(ce);
  }
  glClearDepth(clear_depth);
#endif
  glClear(GL_DEPTH_BUFFER_BIT);
  glDepthMask(prev_depth_mask);
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
  return true;
}

void pbr_shadow_bind_receiver(GLuint program, const float* cam_trans) {
  auto& st = pbr_shadow_state();
  if (!st.valid) {
    return;
  }
  GLint mvp_loc = glu::loc(program, "u_pbr_shadow_mvp");
  GLint tex_loc = glu::loc(program, "tex_PBR_SHADOW");
  GLint on_loc = glu::loc(program, "u_pbr_shadow_on");
  // gl-uniforms-dead-seven : `u_pbr_legacy_shadow` n'est declare dans AUCUN shader de
  // l'arbre — le recensement rend 0 lecteur sur tous les programmes lies. Sa poussee est
  // retiree ; `st.legacy_strength` reste lu par les proprietes de debug, sans destinataire.
  GLint cd_loc = glu::loc(program, "u_pbr_shadow_cam_delta");
  if (tex_loc >= 0) {
    glUniform1i(tex_loc, 9);
  }
  // ALWAYS bind the READ-side depth texture on unit 9 (even when no completed map exists
  // yet: it is cleared-to-1.0 = fully lit). Receivers sample LAST frame's completed map —
  // the write side is mid-accumulation and would miss casters drawn in later buckets
  // (tie hut onto tfrag ground). Prevents the unbound/type-mismatch sampler class (the
  // old magenta lesson).
  glActiveTexture(GL_TEXTURE9);
  glBindTexture(GL_TEXTURE_2D, st.depth_tex[1 - st.write]);
  glActiveTexture(GL_TEXTURE0);
  if (mvp_loc >= 0) {
    glUniformMatrix4fv(mvp_loc, 1, GL_FALSE, st.read_mvp);
  }
  if (cd_loc >= 0) {
    // Suspect (d) re-anchor: the read map was written around read_cam; the receiver's
    // v_fringe_rel uses the CURRENT camera. rel_at_write = v_fringe_rel + (cam_now -
    // read_cam)/4096 — without this every shadow trails the camera by one frame of motion
    // (continuous displacement during the owner's orbit repro).
    glUniform3f(cd_loc, (cam_trans[0] - st.read_cam[0]) / 4096.f,
                (cam_trans[1] - st.read_cam[1]) / 4096.f,
                (cam_trans[2] - st.read_cam[2]) / 4096.f);
  }
  if (on_loc >= 0) {
    const int shadow_on = (st.valid && st.read_valid) ? 1 : 0;
    glUniform1i(on_loc, shadow_on);
    lighting_census::gate_shadow(shadow_on);
  }
  // Item 1: which light (0 = yellow sun / 1 = green sun) the READ-side map was rendered from,
  // so the shader applies the cast-shadow occlusion to the MATCHING directional term.
  GLint sl_loc = glu::loc(program, "u_rt_shadow_light");
  if (sl_loc >= 0) {
    glUniform1i(sl_loc, st.read_shadow_light);
  }
  // lighting-legacy-purge (2026-09-11) : `u_rt_shadow_range` et `u_rt_shadow_res` ne sont plus
  // pousses — les deux grandeurs sont desormais des CONSTANTES (RechargedFixed::kRtShadowDist /
  // kRtShadowRes), ecrites en dur cote shader. Continuer a les pousser rendrait -1 a
  // `glGetUniformLocation` et la ligne ne serait que du bruit.
  if (st.debug) {
    static int dbg_calls = 0;
    if (dbg_calls++ % 240 == 0) {
      lg::info(
          "PBR-SHADOW-DBG bind_receiver prog={} mvp_loc={} tex_loc={} on_loc={} "
          "on={} read_mvp0={:.4f}",
          program, mvp_loc, tex_loc, on_loc, (st.valid && st.read_valid) ? 1 : 0,
          st.read_mvp[0]);
    }
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
      // GOAL dir is light-travel (sun->surface); shader wants surface->light, so negate.
      float d[3] = {-gs.recharged_pbr_lg_dir[i][0], -gs.recharged_pbr_lg_dir[i][1],
                    -gs.recharged_pbr_lg_dir[i][2]};
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
  {
    const float* ss = gs.recharged_pbr_sky_sun;
    float ssl = std::sqrt(ss[0] * ss[0] + ss[1] * ss[1] + ss[2] * ss[2]);
    if (ssl > 1e-3f && ss[1] / ssl > 0.02f) {
      light_dir[0] = ss[0] / ssl;
      light_dir[1] = ss[1] / ssl;
      light_dir[2] = ss[2] / ssl;
    }
  }
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
    float rc[3];
    for (int i = 0; i < 3; i++) {
      rc[i] = (0.5f + 0.5f * (msc[i] / mx)) * rt_intensity;
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
    float owning_up = (pbr_shadow_state().shadow_light == 1) ? green_up_raw : sun_up_raw;
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
      ho.frame = render_state->frame_idx;
      ho.sunelev += handoff_alpha * (rt_sun_elev - ho.sunelev);
      ho.moon += handoff_alpha * (moon_scale - ho.moon);
      ho.conf += handoff_alpha * (rt_shadow_conf - ho.conf);
      ho.ambY += handoff_alpha * (ambW_y_raw - ho.ambY);
      ho.ambG += handoff_alpha * (ambW_g_raw - ho.ambG);
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
               pbr_shadow_state().shadow_light);
    }
  }
#endif
  lgt_3f(id, "u_rt_moon_dir", moon_dir[0], moon_dir[1], moon_dir[2]);
  lgt_3f(id, "u_rt_moon_color",
              MOON_GREEN[0] * moon_scale, MOON_GREEN[1] * moon_scale, MOON_GREEN[2] * moon_scale);
  lgt_1f(id, "u_rt_shadow_conf", rt_shadow_conf);  // playtest #4 stepless shadow handoff

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
    float shc[9][3];
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
    lgt_1i(id, "u_rt_flat_normal", rt_flat_normal);
    lgt_3fv(id, "u_rt_sh[0]", 9, &shc[0][0]);

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
