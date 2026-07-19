

#include "background_common.h"

#include <algorithm>
#include <cstdlib>
#include <cstring>
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
#include "game/graphics/opengl_renderer/BucketRenderer.h"
#include "game/graphics/pipelines/opengl.h"

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
  if (!Gfx::g_global_settings.recharged_grass || !Gfx::g_global_settings.recharged_grass_overhang) {
    return r;
  }
  // Mirror GrassRenderer's near-LOD clamp (GrassRenderer.cpp:990): the texture fades IN over the
  // exact band the droop blades fade OUT in (blade alpha = 1 - smoothstep(0.55*near, near, d)).
  float near_m = std::min(80.0f, std::max(8.0f, Gfx::g_global_settings.recharged_grass_near_dist));
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
        glBlendFuncSeparate(GL_SRC_ALPHA, GL_ONE, GL_ONE, GL_ZERO);
        glBlendEquation(GL_FUNC_REVERSE_SUBTRACT);
        break;
      case DrawMode::AlphaBlend::SRC_0_DST_DST:
        glBlendFunc(GL_DST_ALPHA, GL_ONE);
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

  if (mode.get_clamp_s_enable()) {
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  } else {
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
  }

  if (mode.get_clamp_t_enable()) {
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  } else {
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
  }

  if (mode.get_filt_enable()) {
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER,
                    mipmap ? GL_LINEAR_MIPMAP_LINEAR : GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  } else {
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
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
    u.alpha_min = glGetUniformLocation(program, "alpha_min");
    u.alpha_max = glGetUniformLocation(program, "alpha_max");
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
  if (mode.get_clamp_s_enable()) {
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  } else {
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
  }

  if (mode.get_clamp_t_enable()) {
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  } else {
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
  }

  if (mode.get_filt_enable()) {
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  } else {
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  }
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
const PbrNeutralMaps& pbr_neutral_maps() {
  static PbrNeutralMaps s;
  if (!s.normal_tex) {
    // Create on unit 11 so the lazy-create binds never clobber the caller's active
    // unit binding — every caller rebinds 11-14 immediately after.
    GLint prev_active = GL_TEXTURE0;
    glGetIntegerv(GL_ACTIVE_TEXTURE, &prev_active);
    glActiveTexture(GL_TEXTURE11);
    auto make1x1 = [](u8 r, u8 g, u8 b) {
      GLuint id = 0;
      glGenTextures(1, &id);
      glBindTexture(GL_TEXTURE_2D, id);
      const u8 px[4] = {r, g, b, 255};
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, px);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      return id;
    };
    s.normal_tex = make1x1(128, 128, 255);  // flat tangent-space normal
    s.rough_tex = make1x1(179, 179, 179);   // 0.7, the shader's absent-map default
    s.metal_tex = make1x1(0, 0, 0);
    s.ao_tex = make1x1(255, 255, 255);
    s.height_tex = make1x1(255, 255, 255);  // surface level -> POM depth 0, zero offset
    glActiveTexture(prev_active);
  }
  return s;
}

void pbr_park_neutral_maps() {
  const auto& neutral = pbr_neutral_maps();
  glActiveTexture(GL_TEXTURE11);
  glBindTexture(GL_TEXTURE_2D, neutral.normal_tex);
  glActiveTexture(GL_TEXTURE12);
  glBindTexture(GL_TEXTURE_2D, neutral.rough_tex);
  glActiveTexture(GL_TEXTURE13);
  glBindTexture(GL_TEXTURE_2D, neutral.metal_tex);
  glActiveTexture(GL_TEXTURE14);
  glBindTexture(GL_TEXTURE_2D, neutral.ao_tex);
  glActiveTexture(GL_TEXTURE15);
  glBindTexture(GL_TEXTURE_2D, neutral.height_tex);
  glActiveTexture(GL_TEXTURE0);
}

// Grecharged-pbr-materials round-4: shared per-draw PBR material bind (was a lambda
// local to TFragment's loop; Tie3 now uses the same code so replaced TIE textures get
// the BRDF, not just the albedo). Byte-identical behavior to the original lambda.
void PbrDrawBinder::begin(GLuint program, const PbrDrawList* draws) {
  m_program = program;
  m_draws = draws;
  m_mode_loc = -2;
  m_cur_mode = 0;
  m_bound_any = false;
}

void PbrDrawBinder::set(s32 tex_id, const DrawMode& mode) {
  int want = 0;
  const custom_tex::PbrMaterialMaps* maps = nullptr;
  // alpha-blended (TRANS "vis-alpha" tree) draws now take the PBR path too — round-4
  // coverage unification; alpha still comes from the legacy fragment_color*T0 product
  // in the shader, only rgb is relit. Decal draws keep the legacy path. PBR keys on
  // the texture, resolved once per level.
  if (Gfx::g_global_settings.recharged_pbr_enable && tex_id >= 0 && !mode.get_decal() && m_draws &&
      !m_draws->empty()) {
    for (auto& e : *m_draws) {
      if (e.tex_idx == tex_id) {
        maps = &e.maps;
        break;
      }
    }
    if (maps) {
      want = (maps->normal_tex ? 1 : 0) | (maps->rough_tex ? 2 : 0) | (maps->metal_tex ? 4 : 0) |
             (maps->ao_tex ? 8 : 0) | (maps->height_tex ? 16 : 0);
    }
  }
  if (want == 0 && m_cur_mode == 0) {
    return;
  }
  if (m_mode_loc == -2) {
    m_mode_loc = glGetUniformLocation(m_program, "u_pbr_mode");
  }
  if (m_mode_loc < 0) {
    return;
  }
  if (want != 0) {
    // Bind ALL FIVE units every time: the real map when present, the 1x1 neutral
    // default when absent. No unit is ever left unbound or holding another draw's map
    // while the PBR shader path is active.
    const auto& neutral = pbr_neutral_maps();
    glActiveTexture(GL_TEXTURE11);
    glBindTexture(GL_TEXTURE_2D, maps->normal_tex ? maps->normal_tex : neutral.normal_tex);
    glActiveTexture(GL_TEXTURE12);
    glBindTexture(GL_TEXTURE_2D, maps->rough_tex ? maps->rough_tex : neutral.rough_tex);
    glActiveTexture(GL_TEXTURE13);
    glBindTexture(GL_TEXTURE_2D, maps->metal_tex ? maps->metal_tex : neutral.metal_tex);
    glActiveTexture(GL_TEXTURE14);
    glBindTexture(GL_TEXTURE_2D, maps->ao_tex ? maps->ao_tex : neutral.ao_tex);
    glActiveTexture(GL_TEXTURE15);
    glBindTexture(GL_TEXTURE_2D, maps->height_tex ? maps->height_tex : neutral.height_tex);
    glActiveTexture(GL_TEXTURE0);
    m_bound_any = true;
  }
  if (want != m_cur_mode) {
    glUniform1i(m_mode_loc, want);
    m_cur_mode = want;
  }
}

void PbrDrawBinder::finish() {
  // The TFRAG3 program is shared; reset PBR mode to 0 so other users are unaffected.
  if (m_cur_mode != 0) {
    if (m_mode_loc == -2) {
      m_mode_loc = glGetUniformLocation(m_program, "u_pbr_mode");
    }
    if (m_mode_loc >= 0) {
      glUniform1i(m_mode_loc, 0);
    }
    m_cur_mode = 0;
  }
  // Park units 11-15 on the neutral 1x1 defaults so no material map leaks into later
  // draws this frame; restores active unit 0.
  if (m_bound_any) {
    pbr_park_neutral_maps();
    m_bound_any = false;
  }
}

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
  // Save FBO + viewport; we bind our own to clear the fresh depth textures to 1.0.
  GLint prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0};
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev_fbo);
  glGetIntegerv(GL_VIEWPORT, prev_vp);

  // ROUND-4 Very High (8192) tier VRAM/limit guard: clamp the requested shadow-map size to
  // the driver's GL_MAX_TEXTURE_SIZE so a weak GPU (Adreno 618) never asks for an
  // unsupported allocation. (Genuine OOM at the top tier is caught below via glGetError.)
  {
    GLint max_tex = 0;
    glGetIntegerv(GL_MAX_TEXTURE_SIZE, &max_tex);
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

bool pbr_shadow_begin_frame(u64 frame_idx, const float* cam_trans) {
  auto& st = pbr_shadow_state();
  // ROUND 2: shadows are driven by EITHER the pbr-materials toggle OR the sun-only realtime-
  // lighting toggle (they are independent — the dev state is pbr-materials OFF, realtime
  // lighting ON, so gating on pbr_enable alone would silently kill the sun's cast shadows).
  if (!(Gfx::g_global_settings.recharged_pbr_enable ||
        Gfx::g_global_settings.recharged_rt_light_enable) ||
      !pbr_shadowmap_enabled_for_frame(frame_idx)) {
    // Feature off: also invalidate the read side so receivers stop sampling a map that
    // will no longer be refreshed (stale-matrix shadows glued to the old camera pos).
    st.read_valid = false;
    st.have_mvp = false;
    return false;
  }
  // ROUND 2 Shadow Quality (resolution) + Shadow Distance settings. Read once per frame
  // (statics), overridable by debug prop / env for headless A/B. A resolution change
  // reallocates the depth textures (this runs on the GL thread). Distance sets shadow_half.
  static u64 s_cfg_frame = ~0ull;
  static int s_req_res = 2048;
  static float s_req_dist = 150.0f;
  if (frame_idx != s_cfg_frame) {
    s_cfg_frame = frame_idx;
    int rr = Gfx::g_global_settings.recharged_rt_shadow_res;
    float rd = Gfx::g_global_settings.recharged_rt_shadow_dist;
#ifdef __ANDROID__
    {
      char v[PROP_VALUE_MAX];
      if (__system_property_get("debug.opengoal.rt.shadowres", v) > 0 && v[0]) {
        rr = atoi(v);
      }
      if (__system_property_get("debug.opengoal.rt.shadowdist", v) > 0 && v[0]) {
        rd = (float)atof(v);
      }
    }
#else
    if (const char* e = std::getenv("OG_RT_SHADOWRES")) {
      rr = std::atoi(e);
    }
    if (const char* e = std::getenv("OG_RT_SHADOWDIST")) {
      rd = (float)std::atof(e);
    }
#endif
    // ROUND-4: snap resolution to the FIVE supported tiers (Very Low 512 / Low 1024 /
    // Med 2048 / High 4096 / Very High 8192); clamp distance to a sane range.
    if (rr >= 6144) {
      rr = 8192;
    } else if (rr >= 3072) {
      rr = 4096;
    } else if (rr >= 1536) {
      rr = 2048;
    } else if (rr >= 768) {
      rr = 1024;
    } else {
      rr = 512;
    }
    if (rd < 15.0f) {
      rd = 15.0f;
    }
    if (rd > 200.0f) {
      rd = 200.0f;
    }
    s_req_res = rr;
    s_req_dist = rd;
  }
  st.shadow_half = s_req_dist;
  if (st.depth_tex[0] && s_req_res != st.size) {
    // Resolution changed at runtime: tear down + rebuild the depth textures at the new size.
    glDeleteFramebuffers(2, st.fbo);
    glDeleteTextures(2, st.depth_tex);
    st.fbo[0] = 0;
    st.fbo[1] = 0;
    st.depth_tex[0] = 0;
    st.depth_tex[1] = 0;
    st.size = s_req_res;
    st.read_valid = false;
    st.have_mvp = false;
    st.frame = ~0ull;
  } else if (!st.depth_tex[0]) {
    st.size = s_req_res;  // first allocation happens at the requested resolution
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
  const auto& gs = Gfx::g_global_settings;
  // Round-5 addendum suspect (c) — ATTRIBUTABILITY: shadows must extend opposite the
  // VISIBLE sun. Primary = the sky-dome sun direction (*sky-parms* upload-data sun 0 pos,
  // the exact camera->sun vector sparticle-track-sun places the sun sprite with) — it
  // tracks the true sun elevation across the TOD. current-shadow CANNOT align: update-
  // mood-shadow-direction hard-clamps it to a constant ~65deg (y=-0.9063), which is why
  // every world shadow was short+steep and unattributable. Fallbacks: current-shadow
  // (sun below horizon / pre-push), then the light-group blend (pre-any-push).
  PbrV3 dir = {0.f, 0.f, 0.f};
  {
    PbrV3 ss = {gs.recharged_pbr_sky_sun[0], gs.recharged_pbr_sky_sun[1],
                gs.recharged_pbr_sky_sun[2]};
    float ssl = std::sqrt(pv_dot(ss, ss));
    if (ssl > 1e-3f && ss.y / ssl > 0.02f) {
      dir = {ss.x / ssl, ss.y / ssl, ss.z / ssl};  // camera->sun == surface->light (distant sun)
    }
  }
  if (pv_dot(dir, dir) < 1e-8f) {
    // current-shadow is light-travel; negate for surface->light.
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
  GLint mvp_loc = glGetUniformLocation(program, "u_pbr_shadow_mvp");
  GLint tex_loc = glGetUniformLocation(program, "tex_PBR_SHADOW");
  GLint on_loc = glGetUniformLocation(program, "u_pbr_shadow_on");
  GLint leg_loc = glGetUniformLocation(program, "u_pbr_legacy_shadow");
  GLint cd_loc = glGetUniformLocation(program, "u_pbr_shadow_cam_delta");
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
    glUniform1i(on_loc, (st.valid && st.read_valid) ? 1 : 0);
  }
  if (leg_loc >= 0) {
    glUniform1f(leg_loc, st.legacy_strength);
  }
  // ROUND 2: feed the shader the Shadow Distance (range) + Shadow Quality (resolution) so it
  // can do the smooth distance fade and size the PCF texel + normal-offset bias.
  GLint rng_loc = glGetUniformLocation(program, "u_rt_shadow_range");
  if (rng_loc >= 0) {
    glUniform1f(rng_loc, st.shadow_half);
  }
  GLint res_loc = glGetUniformLocation(program, "u_rt_shadow_res");
  if (res_loc >= 0) {
    glUniform1f(res_loc, (float)st.size);
  }
  if (st.debug) {
    static int dbg_calls = 0;
    if (dbg_calls++ % 240 == 0) {
      lg::info(
          "PBR-SHADOW-DBG bind_receiver prog={} mvp_loc={} tex_loc={} on_loc={} leg_loc={} "
          "on={} read_mvp0={:.4f}",
          program, mvp_loc, tex_loc, on_loc, leg_loc, (st.valid && st.read_valid) ? 1 : 0,
          st.read_mvp[0]);
    }
  }
}
#endif

void first_tfrag_draw_setup(const GoalBackgroundCameraData& settings,
                            SharedRenderState* render_state,
                            ShaderId shader) {
  const auto& sh = render_state->shaders[shader];
  sh.activate();
  auto id = sh.id();
  glUniform1i(glGetUniformLocation(id, "gfx_hack_no_tex"), Gfx::g_global_settings.hack_no_tex);
  glUniform1i(glGetUniformLocation(id, "decal"), false);
  glUniform1i(glGetUniformLocation(id, "tex_T0"), 0);
  glUniformMatrix4fv(glGetUniformLocation(id, "camera"), 1, GL_FALSE, settings.camera[0].data());

  auto newcam =
      make_new_cam_mat(settings.rot, settings.perspective, settings.fog.x(), settings.hvdf_off.z());

  /*
  fmt::print("camera:\n{}\n{}\n{}\n{}\n", settings.camera[0].to_string_aligned(),
             settings.camera[1].to_string_aligned(), settings.camera[2].to_string_aligned(),
             settings.camera[3].to_string_aligned());

  fmt::print("camera2:\n{}\n{}\n{}\n{}\n", newcam[0].to_string_aligned(),
             newcam[1].to_string_aligned(), newcam[2].to_string_aligned(),
             newcam[3].to_string_aligned());

  fmt::print("persp:\n{}\n{}\n{}\n{}\n", settings.perspective[0].to_string_aligned(),
             settings.perspective[1].to_string_aligned(),
             settings.perspective[2].to_string_aligned(),
             settings.perspective[3].to_string_aligned());
  fmt::print("rot:\n{}\n{}\n{}\n{}\n", settings.rot[0].to_string_aligned(),
             settings.rot[1].to_string_aligned(), settings.rot[2].to_string_aligned(),
             settings.rot[3].to_string_aligned());
  fmt::print("ctrans: {}\n", settings.trans.to_string_aligned());
  fmt::print("hvdf: {}\n", settings.hvdf_off.to_string_aligned());
  */

  glUniformMatrix4fv(glGetUniformLocation(id, "pc_camera"), 1, GL_FALSE, newcam[0].data());

  glUniform4f(glGetUniformLocation(id, "hvdf_offset"), settings.hvdf_off[0], settings.hvdf_off[1],
              settings.hvdf_off[2], settings.hvdf_off[3]);
  glUniform4f(glGetUniformLocation(id, "cam_trans"), settings.trans[0], settings.trans[1],
              settings.trans[2], settings.trans[3]);
  glUniform1f(glGetUniformLocation(id, "fog_constant"), settings.fog.x());
  glUniform1f(glGetUniformLocation(id, "fog_min"), settings.fog.y());
  glUniform1f(glGetUniformLocation(id, "fog_max"), settings.fog.z());
  glUniform4f(glGetUniformLocation(id, "fog_color"), render_state->fog_color[0] / 255.f,
              render_state->fog_color[1] / 255.f, render_state->fog_color[2] / 255.f,
              render_state->fog_intensity / 255);

#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials: frame-constant PBR uniforms; glGetUniformLocation returns -1
  // for programs without them (glUniform on -1 is a no-op), so this is safe for every ShaderId.
  glUniform1i(glGetUniformLocation(id, "u_pbr_mode"), 0);
  glUniform1i(glGetUniformLocation(id, "tex_PBR_N"), 11);
  glUniform1i(glGetUniformLocation(id, "tex_PBR_R"), 12);
  glUniform1i(glGetUniformLocation(id, "tex_PBR_M"), 13);
  glUniform1i(glGetUniformLocation(id, "tex_PBR_AO"), 14);
  glUniform1i(glGetUniformLocation(id, "tex_PBR_H"), 15);
  // Round-4 mandate B (shadow map): always advertise the shadow sampler on unit 9 and
  // default u_pbr_shadow_on OFF; pbr_shadow_bind_receiver upgrades it per-renderer. Parking
  // the depth texture on unit 9 here mismatch-proofs every TFRAG3-family user (magenta
  // class) even before/without a receiver bind.
  glUniform1i(glGetUniformLocation(id, "tex_PBR_SHADOW"), 9);
  glUniform1i(glGetUniformLocation(id, "u_pbr_shadow_on"), 0);
  if (pbr_shadow_state().valid) {
    glActiveTexture(GL_TEXTURE9);
    // Park the READ-side map (the one receivers sample; any complete depth tex works
    // here since u_pbr_shadow_on defaults OFF — this is unit-completeness hardening).
    glBindTexture(GL_TEXTURE_2D,
                  pbr_shadow_state().depth_tex[1 - pbr_shadow_state().write]);
    glActiveTexture(GL_TEXTURE0);
  }
  // Units 11-15 must be complete for EVERY draw of this program — including when zero
  // PBR materials are registered this level (see pbr_neutral_maps in background_common.h).
  pbr_park_neutral_maps();
  const auto& gs = Gfx::g_global_settings;
  // Sun direction is surface->sun; the GOAL shadow vector is light-travel (sun->surface), so negate.
  float sd[3] = {-gs.recharged_pbr_shadow[0], -gs.recharged_pbr_shadow[1], -gs.recharged_pbr_shadow[2]};
  float sl = std::sqrt(sd[0] * sd[0] + sd[1] * sd[1] + sd[2] * sd[2]);
  if (sl < 1e-5f) {
    sd[0] = 0.f;
    sd[1] = 1.f;
    sd[2] = 0.f;
    sl = 1.f;
  }
  glUniform3f(glGetUniformLocation(id, "u_pbr_sun_dir"), sd[0] / sl, sd[1] / sl, sd[2] / sl);
  // The mood tables store sun-color / env-color as 0..255-scale floats (e.g.
  // village1 sun-color (255,128,0)); pushing them raw made lit explode ~100x and
  // clamp to saturated hues. Scale to 0..1 HERE (GL boundary) so GOAL keeps
  // pushing the raw engine values (1:1 pass-through in the pc layer).
  float sun_scale = 1.0f / 255.0f;
  float amb_scale = 1.0f / 255.0f;
  float exposure = gs.recharged_pbr_exposure;
  // Owner mandate 2026-07-18 ("giga flat"): relief tunables, defaults CALIBRATED on
  // device at the owner sage-wall vantage (-112 42 205 h8; calib combo C beat A/B/D/E:
  // deep mortar relief, no grazing smear — see device/calib/). Extra UV tiling 1.0 =
  // native texel density (2x read busier and smeared at grazing on this wall).
  float normal_strength = 3.0f;
  float height_scale = 0.07f;
  float uv_tile = 1.0f;
  // Owner round-3 mandate (macro shading): lighting-split calibration. Indirect 1.0 =
  // the baked-GI term reproduces legacy brightness in full baked shadow by construction
  // (see tfrag3.frag); direct scales the realtime sun DIFFUSE because the baked color
  // already carries the baked sun (double-dose control). 0.3 = device-calibrated at the
  // owner sage-wall vantage (-112 42 205 h8): largest value whose ON-vs-OFF macro
  // luminance-profile correlation passed the 0.8 gate across BOTH calibration boots
  // (refined sweep corr_h 0.933 / coarse boot 0.822; ratio 1.10; 0.5 scored 0.78=FAIL).
  float pbr_direct = 0.3f;
  float pbr_indirect = 1.0f;
  // Round-4bis mandate E: 1.0 = round-3 hybrid (indirect = baked vertex GI), 0.0 = FULL
  // REALTIME (indirect = light-group ambi * AO, baked term gone). Prop-tunable for the
  // owner's day/night A/B; default stays the owner-accepted round-3 hybrid.
  float pbr_baked_weight = 1.0f;
  float pbr_shadow_bias = 0.0f;  // debug compare-ref override (see tfrag3.frag)
  // Round-5 addendum 2 MANDATE F ("light the world like Jak"): world-wide per-face N.L
  // mood-light relight of LEGACY world fragments. 1.0 = on (blend fully to the relit
  // term), 0.0 = old flat legacy-darkening only. wr_direct/wr_indirect calibrate against
  // double-brightening (the baked vertex color already carries the baked sun): indirect
  // slightly below 1 makes headroom for the directional term the sun-facing faces gain.
  float world_relight = 1.0f;
  float wr_direct = 0.25f;
  float wr_indirect = 0.85f;
  // Per-channel isolation viz (critique 2 "prove each map does work"): value semantics
  // documented at the u_pbr_debug uniform in tfrag3.frag. 0 (absent) = normal render.
  int pbr_debug = 0;
#ifdef __ANDROID__
  // Device-tunable calibration for the PoC: debug props override the defaults so
  // exposure/scale can be dialed without a rebuild. Absent props = defaults.
  {
    char v[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.pbr.sunscale", v) > 0) {
      sun_scale = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.ambscale", v) > 0) {
      amb_scale = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.exposure", v) > 0) {
      exposure = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.debug", v) > 0) {
      pbr_debug = atoi(v);
    }
    if (__system_property_get("debug.opengoal.pbr.nstrength", v) > 0) {
      normal_strength = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.height", v) > 0) {
      height_scale = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.uvtile", v) > 0) {
      uv_tile = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.direct", v) > 0) {
      pbr_direct = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.indirect", v) > 0) {
      pbr_indirect = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.bakedw", v) > 0) {
      pbr_baked_weight = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.shadowbias", v) > 0) {
      pbr_shadow_bias = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.worldrelight", v) > 0) {
      world_relight = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.wrdirect", v) > 0) {
      wr_direct = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.wrindirect", v) > 0) {
      wr_indirect = atof(v);
    }
  }
#else
  if (const char* e = getenv("OG_PBR_DEBUG")) {
    pbr_debug = atoi(e);
  }
  if (const char* e = getenv("OG_PBR_NSTRENGTH")) {
    normal_strength = atof(e);
  }
  if (const char* e = getenv("OG_PBR_HEIGHT")) {
    height_scale = atof(e);
  }
  if (const char* e = getenv("OG_PBR_UVTILE")) {
    uv_tile = atof(e);
  }
  if (const char* e = getenv("OG_PBR_DIRECT")) {
    pbr_direct = atof(e);
  }
  if (const char* e = getenv("OG_PBR_INDIRECT")) {
    pbr_indirect = atof(e);
  }
  if (const char* e = getenv("OG_PBR_BAKEDW")) {
    pbr_baked_weight = atof(e);
  }
  if (const char* e = getenv("OG_PBR_SHADOWBIAS")) {
    pbr_shadow_bias = atof(e);
  }
  if (const char* e = getenv("OG_PBR_WORLDRELIGHT")) {
    world_relight = atof(e);
  }
  if (const char* e = getenv("OG_PBR_WR_DIRECT")) {
    wr_direct = atof(e);
  }
  if (const char* e = getenv("OG_PBR_WR_INDIRECT")) {
    wr_indirect = atof(e);
  }
#endif
  glUniform1i(glGetUniformLocation(id, "u_pbr_debug"), pbr_debug);
  glUniform3f(glGetUniformLocation(id, "u_pbr_sun_color"), gs.recharged_pbr_sun_color[0] * sun_scale,
              gs.recharged_pbr_sun_color[1] * sun_scale,
              gs.recharged_pbr_sun_color[2] * sun_scale);

  // Round-4 multi-light (mandate C): build 3 direct lights from *time-of-day-context*
  // light-group 0 (soleil dir0 + lune verte dir1 + fill dir2). Bound as arrays for the
  // shader's accumulation loop. u_pbr_sun_dir/u_pbr_sun_color stay set above (viz/other
  // code reads them). Each color is pre-weighted by its levels.x morph weight in GOAL's
  // TOD interpolation, so dir0+dir1 sum ~1 across hour transitions (energy conserved).
  float light_dir[9];
  float light_color[9];
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
        light_color[i * 3 + 0] = 0.f;
        light_color[i * 3 + 1] = 0.f;
        light_color[i * 3 + 2] = 0.f;
      } else {
        light_dir[i * 3 + 0] = d[0] / dl;
        light_dir[i * 3 + 1] = d[1] / dl;
        light_dir[i * 3 + 2] = d[2] / dl;
        light_color[i * 3 + 0] = gs.recharged_pbr_lg_color[i][0] * lvl * sun_scale;
        light_color[i * 3 + 1] = gs.recharged_pbr_lg_color[i][1] * lvl * sun_scale;
        light_color[i * 3 + 2] = gs.recharged_pbr_lg_color[i][2] * lvl * sun_scale;
      }
    }
  } else {
    // Startup fallback (no GOAL push yet): light0 = the single-sun computation above,
    // lights 1/2 black.
    light_dir[0] = sd[0] / sl;
    light_dir[1] = sd[1] / sl;
    light_dir[2] = sd[2] / sl;
    light_color[0] = gs.recharged_pbr_sun_color[0] * sun_scale;
    light_color[1] = gs.recharged_pbr_sun_color[1] * sun_scale;
    light_color[2] = gs.recharged_pbr_sun_color[2] * sun_scale;
    for (int k = 3; k < 9; k++) {
      light_dir[k] = (k % 3 == 1) ? 1.f : 0.f;  // (0,1,0) dirs
      light_color[k] = 0.f;
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
  glUniform3fv(glGetUniformLocation(id, "u_pbr_light_dir"), 3, light_dir);
  glUniform3fv(glGetUniformLocation(id, "u_pbr_light_color"), 3, light_color);

  // === Grecharged-realtime-lighting (2026-07-19 REWRITE): SUN-ONLY path uniforms. ===
  // Master toggle comes from the pc-settings (recharged_rt_*), overridable per-frame by a
  // debug prop / env so the device can flip lighting ON/OFF for A/B capture WITHOUT menu
  // navigation. u_rt_sun_dir reuses the visible-sun-overridden light_dir[0] (== the
  // on-screen sun sprite direction), so the sun-only shading, the shadow-map slope bias and
  // the depth-pass MVP all agree on where the sun is. u_rt_sun_color carries tint AND intensity.
  int rt_light_on = gs.recharged_rt_light_enable ? 1 : 0;
  float rt_intensity = 1.5f;
#ifdef __ANDROID__
  {
    char rv[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.rt.light", rv) > 0 && rv[0]) {
      rt_light_on = atoi(rv);
    }
    if (__system_property_get("debug.opengoal.rt.intensity", rv) > 0 && rv[0]) {
      rt_intensity = atof(rv);
    }
  }
#else
  if (const char* e = getenv("OG_RT_LIGHT")) {
    rt_light_on = atoi(e);
  }
  if (const char* e = getenv("OG_RT_INTENSITY")) {
    rt_intensity = atof(e);
  }
#endif
  // ROUND-5 cast-shadow Strength (0..1): how much a shadowed fragment darkens. The shader
  // wants the RESIDUAL brightness a fully-occluded fragment keeps = clamp(1 - strength, 0, 1)
  // (default strength 0.8 => residual 0.2). Overridable per-frame like rt.intensity.
  float rt_shadow_strength = gs.recharged_rt_shadow_strength;  // default 0.8
#ifdef __ANDROID__
  {
    char rv[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.rt.shadowstrength", rv) > 0 && rv[0]) {
      rt_shadow_strength = atof(rv);
    }
  }
#else
  if (const char* e = getenv("OG_RT_SHADOWSTRENGTH")) {
    rt_shadow_strength = atof(e);
  }
#endif
  // residual = clamp(1 - strength, 0, 1); guard NaN / out-of-range to a sane 0..1.
  float rt_shadow_residual =
      (rt_shadow_strength >= 0.0f && rt_shadow_strength <= 1.0f) ? (1.0f - rt_shadow_strength) : 0.0f;
  glUniform1i(glGetUniformLocation(id, "u_rt_light_on"), rt_light_on);
  glUniform3f(glGetUniformLocation(id, "u_rt_sun_dir"), light_dir[0], light_dir[1], light_dir[2]);
  // Sun color: normalize the mood sun tint to unit max, blend 50% toward white so it
  // reads as a natural sun (not an oversaturated hue), then scale by intensity.
  {
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
    glUniform3f(glGetUniformLocation(id, "u_rt_sun_color"), rc[0], rc[1], rc[2]);
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
  {
    const float* ss = gs.recharged_pbr_sky_sun;
    float ssl = std::sqrt(ss[0] * ss[0] + ss[1] * ss[1] + ss[2] * ss[2]);
    if (ssl > 1e-4f) {
      float up = ss[1] / ssl;  // sin(sun elevation): >0 above the horizon, <0 below (night)
      float t = up / 0.10f;    // smooth ramp from horizon to ~5.7 deg elevation
      t = t < 0.0f ? 0.0f : (t > 1.0f ? 1.0f : t);
      rt_sun_elev = t * t * (3.0f - 2.0f * t);  // smoothstep
    }
  }
#ifdef __ANDROID__
  {
    char rv[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.rt.sunelev", rv) > 0 && rv[0]) {
      rt_sun_elev = atof(rv);  // device A/B: force the night-fade value without waiting for TOD
    }
  }
#else
  if (const char* e = getenv("OG_RT_SUNELEV")) {
    rt_sun_elev = atof(e);
  }
#endif
  glUniform1f(glGetUniformLocation(id, "u_rt_sun_elev"), rt_sun_elev);
  // ROUND-5: residual brightness a fully-occluded fragment keeps (1 - Shadow Strength).
  glUniform1f(glGetUniformLocation(id, "u_rt_shadow_residual"), rt_shadow_residual);

  // === Grecharged-directional-ambient: HEMISPHERE ambient (replaces the flat ~0.2 floor). ===
  // The ambient base is directional: an up-hemisphere SKY tint and a down-hemisphere GROUND bounce,
  // blended per-fragment by the world normal in the shader. Both track the mood/TOD ambient so the day
  // cycle drives the HUE; the LEVEL is the Ambient Strength setting, gently faded by the real sun
  // elevation (reusing rt_sun_elev) so night stays calm — NO mood night presets feed the brightness
  // (round-7 night-leak discipline). Golden rule: this only reshapes the ambient base; the direct-sun
  // term is untouched so sunlit surfaces are unchanged.
  int rt_ambient_on = gs.recharged_rt_ambient_enable ? 1 : 0;
  float rt_ambient_strength = gs.recharged_rt_ambient_strength;  // default ~0.2 (== old floor)
#ifdef __ANDROID__
  {
    char rv[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.rt.ambient", rv) > 0 && rv[0]) {
      rt_ambient_on = atoi(rv);
    }
    if (__system_property_get("debug.opengoal.rt.ambientstrength", rv) > 0 && rv[0]) {
      rt_ambient_strength = atof(rv);
    }
  }
#else
  if (const char* e = getenv("OG_RT_AMBIENT")) {
    rt_ambient_on = atoi(e);
  }
  if (const char* e = getenv("OG_RT_AMBIENTSTRENGTH")) {
    rt_ambient_strength = atof(e);
  }
#endif
  if (!(rt_ambient_strength >= 0.0f && rt_ambient_strength <= 1.0f)) {
    rt_ambient_strength = 0.2f;
  }
  {
    // SKY hue: the mood ambient (light-group ambi when valid, else the mood env ambient), normalized to
    // unit-max so the mood's *brightness* can't re-brighten night (only its HUE is used); blended 50%
    // toward white so it reads as natural skylight. amb_scale (1/255) converts the raw GOAL 0..255 color.
    const float* asrc =
        gs.recharged_pbr_lg_valid ? gs.recharged_pbr_lg_ambi : gs.recharged_pbr_ambient;
    float sh[3] = {asrc[0] * amb_scale, asrc[1] * amb_scale, asrc[2] * amb_scale};
    float smx = sh[0];
    if (sh[1] > smx) smx = sh[1];
    if (sh[2] > smx) smx = sh[2];
    if (smx < 1e-3f) {
      sh[0] = 0.6f;
      sh[1] = 0.7f;
      sh[2] = 1.0f;
      smx = 1.0f;
    }
    // LEVEL: strength, gently faded by sun elevation so night is calmer (never below 0.7x, never brighter
    // than day). rt_sun_elev is 1 (day) .. 0 (night below horizon).
    float lvl = rt_ambient_strength * (0.7f + 0.3f * rt_sun_elev);
    const float gtint[3] = {0.65f, 0.55f, 0.45f};  // warm, darker ground bounce
    float sky[3], ground[3];
    for (int i = 0; i < 3; i++) {
      float hue = 0.5f + 0.5f * (sh[i] / smx);  // toward white
      sky[i] = hue * lvl;
      ground[i] = sky[i] * gtint[i];
    }
    glUniform1i(glGetUniformLocation(id, "u_rt_ambient_on"), rt_ambient_on);
    glUniform3f(glGetUniformLocation(id, "u_rt_sky_color"), sky[0], sky[1], sky[2]);
    glUniform3f(glGetUniformLocation(id, "u_rt_ground_color"), ground[0], ground[1], ground[2]);
  }

  // u_pbr_ambient: when the light-group is valid, use its ambi color (not the mood-sun
  // env-color). Read by the lit path only when u_pbr_baked_weight < 1 (round-4bis
  // full-realtime indirect); at the default weight 1.0 it stays viz-only.
  if (gs.recharged_pbr_lg_valid) {
    glUniform3f(glGetUniformLocation(id, "u_pbr_ambient"), gs.recharged_pbr_lg_ambi[0] * amb_scale,
                gs.recharged_pbr_lg_ambi[1] * amb_scale, gs.recharged_pbr_lg_ambi[2] * amb_scale);
  } else {
    glUniform3f(glGetUniformLocation(id, "u_pbr_ambient"), gs.recharged_pbr_ambient[0] * amb_scale,
                gs.recharged_pbr_ambient[1] * amb_scale, gs.recharged_pbr_ambient[2] * amb_scale);
  }
  glUniform1f(glGetUniformLocation(id, "u_pbr_exposure"), exposure);
  glUniform1f(glGetUniformLocation(id, "u_pbr_normal_strength"), normal_strength);
  glUniform1f(glGetUniformLocation(id, "u_pbr_height_scale"), height_scale);
  glUniform1f(glGetUniformLocation(id, "u_pbr_uv_tile"), uv_tile);
  glUniform1f(glGetUniformLocation(id, "u_pbr_direct"), pbr_direct);
  glUniform1f(glGetUniformLocation(id, "u_pbr_indirect"), pbr_indirect);
  glUniform1f(glGetUniformLocation(id, "u_pbr_baked_weight"), pbr_baked_weight);
  glUniform1f(glGetUniformLocation(id, "u_pbr_shadow_bias"), pbr_shadow_bias);
  glUniform1f(glGetUniformLocation(id, "u_pbr_world_relight"), world_relight);
  glUniform1f(glGetUniformLocation(id, "u_pbr_wr_direct"), wr_direct);
  glUniform1f(glGetUniformLocation(id, "u_pbr_wr_indirect"), wr_indirect);
#endif
}

void interp_time_of_day_slow(const math::Vector<s32, 4> itimes[4],
                             const tfrag3::PackedTimeOfDay& in,
                             math::Vector<u8, 4>* out) {
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
}

void interp_time_of_day(const math::Vector<s32, 4> itimes[4],
                        const tfrag3::PackedTimeOfDay& packed_colors,
                        math::Vector<u8, 4>* out) {
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
  }
}
