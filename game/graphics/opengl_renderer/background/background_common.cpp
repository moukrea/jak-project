

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
  if (st.fbo || st.depth_tex) {
    return;  // already tried once (valid or permanently failed)
  }
  // Save FBO + viewport; we bind our own to clear the fresh depth texture to 1.0.
  GLint prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0};
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev_fbo);
  glGetIntegerv(GL_VIEWPORT, prev_vp);

  glGenTextures(1, &st.depth_tex);
  glBindTexture(GL_TEXTURE_2D, st.depth_tex);
  glTexImage2D(GL_TEXTURE_2D, 0, GL_DEPTH_COMPONENT24, st.size, st.size, 0, GL_DEPTH_COMPONENT,
               GL_UNSIGNED_INT, nullptr);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_MODE, GL_COMPARE_REF_TO_TEXTURE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_COMPARE_FUNC, GL_LEQUAL);

  glGenFramebuffers(1, &st.fbo);
  glBindFramebuffer(GL_FRAMEBUFFER, st.fbo);
  glFramebufferTexture2D(GL_FRAMEBUFFER, GL_DEPTH_ATTACHMENT, GL_TEXTURE_2D, st.depth_tex, 0);
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
    st.valid = true;
  }

  // Restore prior FBO + viewport.
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
  glBindTexture(GL_TEXTURE_2D, 0);
}

bool pbr_shadow_begin_frame(u64 frame_idx) {
  auto& st = pbr_shadow_state();
  st.have_mvp = false;
  if (!Gfx::g_global_settings.recharged_pbr_enable) {
    return false;
  }
  if (!pbr_shadowmap_enabled_for_frame(frame_idx)) {
    return false;
  }
  pbr_shadow_ensure_resources();
  if (!st.valid) {
    return false;
  }

  if (st.frame == frame_idx) {
    // Same frame: the map was already cleared + mvp computed this frame; keep rendering
    // additively across trees/levels without re-clearing.
    st.have_mvp = true;
    return true;
  }

  // ---- Compute the light matrix (camera-relative meters). ----
  const auto& gs = Gfx::g_global_settings;
  PbrV3 dir = {0.f, 0.f, 0.f};
  if (gs.recharged_pbr_lg_valid) {
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
  if (pv_dot(dir, dir) < 1e-8f) {
    // Fall back to -recharged_pbr_shadow (light-travel -> surface->light).
    dir = {-gs.recharged_pbr_shadow[0], -gs.recharged_pbr_shadow[1], -gs.recharged_pbr_shadow[2]};
  }
  PbrV3 L = pv_norm(dir);  // surface->sun unit vector
  if (pv_dot(L, L) < 1e-4f) {
    return false;
  }

  PbrV3 eye = {L.x * 100.f, L.y * 100.f, L.z * 100.f};
  PbrV3 target = {0.f, 0.f, 0.f};
  PbrV3 up = std::fabs(L.y) > 0.95f ? PbrV3{1.f, 0.f, 0.f} : PbrV3{0.f, 1.f, 0.f};

  float view[16];
  pbr_look_at(eye, target, up, view);

  // TEXEL SNAP (stable-shadow trick): transform the world origin into light view space,
  // snap x/y to multiples of the world-per-texel size, add the delta back into the view
  // translation. Ortho spans 80 world units across 1024 texels.
  const float texel_world = 80.0f / 1024.0f;
  // origin in view space = view * (0,0,0,1) = column 3 translation.
  float ox = view[12];
  float oy = view[13];
  float sx = std::floor(ox / texel_world) * texel_world;
  float sy = std::floor(oy / texel_world) * texel_world;
  view[12] += (sx - ox);
  view[13] += (sy - oy);

  float proj[16];
  pbr_ortho(-40.f, 40.f, -40.f, 40.f, 0.5f, 200.0f, proj);

  pbr_mat_mul(proj, view, st.mvp);
  st.have_mvp = true;
  st.frame = frame_idx;

  // Clear the depth map for the new frame (state save/restore).
  GLint prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0};
  glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev_fbo);
  glGetIntegerv(GL_VIEWPORT, prev_vp);
  glBindFramebuffer(GL_FRAMEBUFFER, st.fbo);
  glViewport(0, 0, st.size, st.size);
  GLboolean prev_depth_mask = GL_TRUE;
  glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);
  glDepthMask(GL_TRUE);
#ifdef __ANDROID__
  glClearDepthf(1.0f);
#else
  glClearDepth(1.0);
#endif
  glClear(GL_DEPTH_BUFFER_BIT);
  glDepthMask(prev_depth_mask);
  glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
  glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
  return true;
}

void pbr_shadow_bind_receiver(GLuint program) {
  auto& st = pbr_shadow_state();
  if (!st.valid) {
    return;
  }
  GLint mvp_loc = glGetUniformLocation(program, "u_pbr_shadow_mvp");
  GLint tex_loc = glGetUniformLocation(program, "tex_PBR_SHADOW");
  GLint on_loc = glGetUniformLocation(program, "u_pbr_shadow_on");
  if (tex_loc >= 0) {
    glUniform1i(tex_loc, 9);
  }
  // ALWAYS bind the depth texture on unit 9 (even when the pass did not run this frame:
  // the map is cleared-to-1.0 = fully lit). Prevents the unbound/type-mismatch sampler
  // class (the old magenta lesson).
  glActiveTexture(GL_TEXTURE9);
  glBindTexture(GL_TEXTURE_2D, st.depth_tex);
  glActiveTexture(GL_TEXTURE0);
  if (mvp_loc >= 0) {
    glUniformMatrix4fv(mvp_loc, 1, GL_FALSE, st.mvp);
  }
  if (on_loc >= 0) {
    glUniform1i(on_loc, (st.valid && st.have_mvp) ? 1 : 0);
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
    glBindTexture(GL_TEXTURE_2D, pbr_shadow_state().depth_tex);
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
  glUniform3fv(glGetUniformLocation(id, "u_pbr_light_dir"), 3, light_dir);
  glUniform3fv(glGetUniformLocation(id, "u_pbr_light_color"), 3, light_color);

  // u_pbr_ambient: when the light-group is valid, use its ambi color (not the mood-sun
  // env-color). Not read by the lit path (zero visual risk); kept for viz completeness.
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
