

#include "background_common.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cstdlib>
#include <cstring>
#include <map>
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
#include "game/graphics/opengl_renderer/BucketRenderer.h"
#include "game/graphics/opengl_renderer/FollowProbe.h"
#include "game/graphics/opengl_renderer/loader/PbrTestPattern.h"
#include "game/graphics/opengl_renderer/Shader.h"
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
  if (!Gfx::recharged_active(Gfx::g_global_settings.recharged_grass) ||
      !Gfx::recharged_active(Gfx::g_global_settings.recharged_grass_overhang)) {
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
    s.rough_tex = make1x1(230, 230, 230);   // 0.9 ROUGH (REOPEN #2: missing map must never read smooth)
    s.metal_tex = make1x1(0, 0, 0);
    s.ao_tex = make1x1(255, 255, 255);
    s.height_tex = make1x1(255, 255, 255);  // surface level -> POM depth 0, zero offset
    s.specular_tex = make1x1(0, 0, 0);      // fusion: F0 map absent (bit32 gates reads)
    s.emissive_tex = make1x1(0, 0, 0);      // fusion: no self-illumination (bit64 gates)
    s.thickness_tex = make1x1(255, 255, 255);  // modern: unit 19 never incomplete (bit1+32 gate it)
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
  glActiveTexture(GL_TEXTURE16);
  glBindTexture(GL_TEXTURE_2D, neutral.specular_tex);
  glActiveTexture(GL_TEXTURE17);
  glBindTexture(GL_TEXTURE_2D, neutral.emissive_tex);
  glActiveTexture(GL_TEXTURE19);  // modern: subsurface thickness (18 is shrub's wind-anchor LUT)
  glBindTexture(GL_TEXTURE_2D, neutral.thickness_tex);
  glActiveTexture(GL_TEXTURE0);
}

// REOPEN #2 A/B killswitch: debug.opengoal.pbr.kill=1 (env OG_PBR_KILL) forces the fused
// PBR material path OFF (u_pbr_mode stays 0) while everything else stays live — proves
// on-device that the new path is ACTIVE (obvious visual delta at the same vantage).
static bool pbr_killswitch() {
  static int cached = -1;
  if (cached < 0) {
    cached = 0;
#ifdef __ANDROID__
    char v[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.pbr.kill", v) > 0) {
      cached = atoi(v) != 0 ? 1 : 0;
    }
#else
    if (const char* e = std::getenv("OG_PBR_KILL")) {
      cached = atoi(e) != 0 ? 1 : 0;
    }
#endif
  }
  return cached == 1;
}

// ===========================================================================
// Grecharged-pbr-realtime-fusion ROUND 20: MEASURED AUTHORED UV DENSITY.
//
// The tessellation displacement samples the height map in a WORLD-SPACE projection at a hardcoded
// 0.5 tiles/m (WORLD_TILES_PER_M) and displaces by a constant amplitude, while the fragment stage
// (parallax / normal / cavity) samples at the AUTHORED uv, so its depth is expressed in UV units
// and is therefore proportional to the real tile size. Wherever a material's authored UV density
// differs from 0.5 tiles/m the two stages describe DIFFERENT-SIZED features on the same surface.
// These helpers measure the real density from the level's own geometry: for every edge of the
// index buffer belonging to a draw that uses this texture, tiles-per-metre = |d(uv)| / |d(pos)|.
// The MEDIAN is robust against the degenerate/stretched edges strips always contain.
// ===========================================================================
namespace {
constexpr size_t kUvDensityMaxSamples = 8192;

void pbr_collect_uv_density(const std::vector<tfrag3::StripDraw>& draws,
                            const std::vector<u32>& indices,
                            const std::vector<tfrag3::PreloadedVertex>& verts,
                            s32 tex_idx,
                            std::vector<float>& out) {
  for (const auto& draw : draws) {
    if (draw.tree_tex_id != tex_idx) {
      continue;
    }
    u64 count = 0;
    for (const auto& vg : draw.vis_groups) {
      count += vg.num_inds;
    }
    const u64 first = draw.unpacked.idx_of_first_idx_in_full_buffer;
    for (u64 k = 0; k + 1 < count; ++k) {
      if (out.size() >= kUvDensityMaxSamples) {
        return;
      }
      const u64 ia = first + k;
      const u64 ib = ia + 1;
      if (ib >= indices.size()) {
        break;
      }
      const u32 va = indices[ia];
      const u32 vb = indices[ib];
      if (va == vb) {
        continue;  // strip restart / degenerate
      }
      if (va >= verts.size() || vb >= verts.size()) {
        continue;
      }
      const auto& pa = verts[va];
      const auto& pb = verts[vb];
      const float dx = pa.x - pb.x;
      const float dy = pa.y - pb.y;
      const float dz = pa.z - pb.z;
      // positions are GAME UNITS (4096 per metre), texcoords are TILE units.
      const float dm = std::sqrt(dx * dx + dy * dy + dz * dz) * (1.f / 4096.f);
      const float du = pa.s - pb.s;
      const float dv = pa.t - pb.t;
      const float dt = std::sqrt(du * du + dv * dv);
      if (dm < 1e-4f || dt < 1e-6f) {
        continue;
      }
      out.push_back(dt / dm);
    }
  }
}

// ROUND 22 — the SHRUB overload (owner defect A: the PBR path is being ported to shrub, and
// without a measured density every shrub material would silently use the 0.5 tiles/m fallback,
// i.e. the WRONG parallax amplitude). Shrub cannot reuse the walk above for two concrete reasons:
//   * ShrubDraw addresses its index range DIRECTLY (first_index_index / num_indices) instead of
//     through StripDraw's vis_groups + unpacked.idx_of_first_idx_in_full_buffer, and
//   * ShrubGpuVertex stores texcoords in 4096-SCALE tile units (shrub.vert divides by 4096 before
//     sampling), whereas PreloadedVertex stores plain tile units.
// Both are handled here, so the number this returns is the SAME quantity as the tfrag/tie one:
// authored texture tiles per world metre.
void pbr_collect_uv_density_shrub(const std::vector<tfrag3::ShrubDraw>& draws,
                                  const std::vector<u32>& indices,
                                  const std::vector<tfrag3::ShrubGpuVertex>& verts,
                                  s32 tex_idx,
                                  std::vector<float>& out) {
  for (const auto& draw : draws) {
    if ((s32)draw.tree_tex_id != tex_idx) {
      continue;
    }
    const u64 first = draw.first_index_index;
    const u64 count = draw.num_indices;
    for (u64 k = 0; k + 1 < count; ++k) {
      if (out.size() >= kUvDensityMaxSamples) {
        return;
      }
      const u64 ia = first + k;
      const u64 ib = ia + 1;
      if (ib >= indices.size()) {
        break;
      }
      const u32 va = indices[ia];
      const u32 vb = indices[ib];
      if (va == vb) {
        continue;  // degenerate
      }
      // UINT32_MAX is the strip-restart code; it fails the bounds test below like any other
      // out-of-range index, which is exactly the behaviour the tfrag/tie walk relies on too.
      if (va >= verts.size() || vb >= verts.size()) {
        continue;
      }
      const auto& pa = verts[va];
      const auto& pb = verts[vb];
      const float dx = pa.x - pb.x;
      const float dy = pa.y - pb.y;
      const float dz = pa.z - pb.z;
      // positions are GAME UNITS (4096 per metre)
      const float dm = std::sqrt(dx * dx + dy * dy + dz * dz) * (1.f / 4096.f);
      const float du = pa.s - pb.s;
      const float dv = pa.t - pb.t;
      // ...and shrub texcoords are 4096-scale TILE units (see shrub.vert: tex_coord.xy /= 4096).
      const float dt = std::sqrt(du * du + dv * dv) * (1.f / 4096.f);
      if (dm < 1e-4f || dt < 1e-6f) {
        continue;
      }
      out.push_back(dt / dm);
    }
  }
}

float pbr_uv_density_median(const std::vector<float>& samples) {
  if (samples.size() < 16) {
    return 0.f;  // "unknown" — callers fall back to 0.5
  }
  std::vector<float> copy = samples;
  const size_t mid = copy.size() / 2;
  std::nth_element(copy.begin(), copy.begin() + mid, copy.end());
  return copy[mid];
}
}  // namespace

// autoport 2026-08-26 — CACHE DE DENSITE UV, POUR POUVOIR LIBERER LES SOMMETS CPU.
// `unpacked.vertices` pese 57,0 Mo par niveau (mesure `A50-LEVRAM`, village1) et il est
// DEJA televerse dans le GPU. Apres chargement, ses seuls lecteurs sont ces trois mesures
// de densite, appelees une fois par niveau depuis le chemin de rendu — donc APRES le
// chargement, ce qui interdisait de liberer le tableau. On memorise le resultat au
// chargement : les mesures deviennent des lectures, et les sommets peuvent partir.
// Cle : (niveau, systeme, index de texture). systeme 0=tfrag 1=tie 2=shrub.
namespace {
std::map<std::tuple<const tfrag3::Level*, int, s32>, std::pair<float, u32>> g_uv_density_cache;
std::mutex g_uv_density_mutex;

bool uv_density_cached(const tfrag3::Level& lev, int system, s32 tex_idx, float* dens,
                       u32* out_samples) {
  std::lock_guard<std::mutex> lk(g_uv_density_mutex);
  const auto it = g_uv_density_cache.find({&lev, system, tex_idx});
  if (it == g_uv_density_cache.end()) {
    return false;
  }
  *dens = it->second.first;
  if (out_samples) {
    *out_samples = it->second.second;
  }
  return true;
}
}  // namespace

void uv_density_store(const tfrag3::Level& lev, int system, s32 tex_idx, float dens, u32 samples) {
  std::lock_guard<std::mutex> lk(g_uv_density_mutex);
  g_uv_density_cache[{&lev, system, tex_idx}] = {dens, samples};
}

void uv_density_forget_level(const tfrag3::Level& lev) {
  std::lock_guard<std::mutex> lk(g_uv_density_mutex);
  for (auto it = g_uv_density_cache.begin(); it != g_uv_density_cache.end();) {
    it = (std::get<0>(it->first) == &lev) ? g_uv_density_cache.erase(it) : std::next(it);
  }
}

float measure_uv_density_tfrag(const tfrag3::Level& lev, s32 tex_idx, u32* out_samples) {
  {
    float cached = 0.f;
    if (uv_density_cached(lev, 0, tex_idx, &cached, out_samples)) {
      return cached;
    }
  }
  std::vector<float> samples;
  samples.reserve(1024);
  // GEOM 0 only: the highest-detail tree carries the authored UVs, and the lower LODs share them.
  for (const auto& tree : lev.tfrag_trees[0]) {
    pbr_collect_uv_density(tree.draws, tree.unpacked.indices, tree.unpacked.vertices, tex_idx,
                           samples);
    if (samples.size() >= kUvDensityMaxSamples) {
      break;
    }
  }
  if (out_samples) {
    *out_samples = (u32)samples.size();
  }
  return pbr_uv_density_median(samples);
}

float measure_uv_density_tie(const tfrag3::Level& lev, s32 tex_idx, u32* out_samples) {
  {
    float cached = 0.f;
    if (uv_density_cached(lev, 1, tex_idx, &cached, out_samples)) {
      return cached;
    }
  }
  std::vector<float> samples;
  samples.reserve(1024);
  // TieTree's unpacked vertices are the same tfrag3::PreloadedVertex type, and its static_draws are
  // the same tfrag3::StripDraw — so the exact same edge walk applies.
  for (const auto& tree : lev.tie_trees[0]) {
    pbr_collect_uv_density(tree.static_draws, tree.unpacked.indices, tree.unpacked.vertices,
                           tex_idx, samples);
    if (samples.size() >= kUvDensityMaxSamples) {
      break;
    }
  }
  if (out_samples) {
    *out_samples = (u32)samples.size();
  }
  return pbr_uv_density_median(samples);
}

float measure_uv_density_shrub(const tfrag3::Level& lev, s32 tex_idx, u32* out_samples) {
  {
    float cached = 0.f;
    if (uv_density_cached(lev, 2, tex_idx, &cached, out_samples)) {
      return cached;
    }
  }
  std::vector<float> samples;
  samples.reserve(1024);
  // Shrub has no geom-LOD array — one tree list, all of it authored.
  for (const auto& tree : lev.shrub_trees) {
    pbr_collect_uv_density_shrub(tree.static_draws, tree.indices, tree.unpacked.vertices, tex_idx,
                                 samples);
    if (samples.size() >= kUvDensityMaxSamples) {
      break;
    }
  }
  if (out_samples) {
    *out_samples = (u32)samples.size();
  }
  return pbr_uv_density_median(samples);
}

// [cover] ROUND 21 DISPLACEMENT COVERAGE: the EFFECTIVE displacement gates, mirrored from
// first_tfrag_draw_setup (which is where the prop/env overrides, the tess->parallax driver demotion
// and the mode-0 height-scale zeroing are all resolved). PbrDrawBinder::set reads them to classify
// each PBR-bound draw against the same conditions the shaders branch on. Diagnostics only: nothing
// in the render path reads these back.
static std::atomic<float> g_cover_height_scale{0.f};
static std::atomic<int> g_cover_bisect{0};
static std::atomic<int> g_cover_debug{0};
static std::atomic<int> g_cover_displacement{1};

static void pbr_cover_publish_gates(float height_scale, int bisect, int debug, int displacement) {
  g_cover_height_scale.store(height_scale, std::memory_order_relaxed);
  g_cover_bisect.store(bisect, std::memory_order_relaxed);
  g_cover_debug.store(debug, std::memory_order_relaxed);
  g_cover_displacement.store(displacement, std::memory_order_relaxed);
}

namespace {
// Gpbr-per-texture-materials : les valeurs GLOBALES que first_tfrag_draw_setup vient de pousser.
// PbrDrawBinder les remultiplie par le facteur DU MATERIAU et finish() les repose telles quelles,
// pour que tout draw qui ne passe pas par le binder (HFRAG en particulier) soit inchange.
// Ecrites et lues sur le SEUL thread GL (setup de programme puis draws du meme thread), d'ou des
// float nus et non des atomiques : ce sont les valeurs POST-clamp, celles que le programme a
// vraiment recues (en particulier height_scale = 0 quand u_pbr_displacement == 0).
// Les initialiseurs sont les valeurs de depart de first_tfrag_draw_setup (3.0 / 0.05 AVANT le
// facteur TEXTURE RELIEF, 0.15 = gfx.h recharged_pbr_spec_intensity), pour qu'un binder qui
// tournerait avant tout setup n'invente pas une valeur. En pratique le setup passe toujours en
// premier et les ecrase ; c'est un filet, pas la source.
float g_pbr_glob_normal_strength = 3.f, g_pbr_glob_height_scale = 0.05f, g_pbr_glob_spec = 0.15f;

// Gpbr-per-texture-materials : emplacements des cinq uniformes de matiere, resolus paresseusement
// comme les m_*_loc du binder (meme glGetUniformLocation, meme regle "-1 = absent du programme"),
// mais tenus PAR PROGRAMME dans un seul endroit plutot qu'en cinq membres de plus que begin()
// devrait remettre en phase. Thread GL uniquement.
struct PbrMatUniformLocs {
  GLint normal_strength = -1;
  GLint height_scale = -1;
  GLint spec_intensity = -1;
  GLint mat = -1;
  GLint mat2 = -1;
};

static const PbrMatUniformLocs& pbr_mat_uniform_locs(GLuint program) {
  static GLuint cached_program = 0;
  static PbrMatUniformLocs locs;
  if (program != cached_program) {
    cached_program = program;
    locs.normal_strength = glGetUniformLocation(program, "u_pbr_normal_strength");
    locs.height_scale = glGetUniformLocation(program, "u_pbr_height_scale");
    locs.spec_intensity = glGetUniformLocation(program, "u_pbr_spec_intensity");
    locs.mat = glGetUniformLocation(program, "u_pbr_mat");
    locs.mat2 = glGetUniformLocation(program, "u_pbr_mat2");
  }
  return locs;
}

// Pousse les cinq uniformes de matiere. `maps == nullptr` => l'IDENTITE : les valeurs globales
// telles que first_tfrag_draw_setup les a poussees, et les constantes que le shader portait en dur.
// C'est le meme jeu de valeurs que finish() repose, donc un draw sans materiau resolu ne peut pas
// heriter des reglages du precedent.
// Gpbr-per-texture-materials — THE RUNTIME PROOF THAT THE KNOBS REACH A DRAW, not just the parser.
// The phase's success criterion (2) is "two distinct materials render measurably different relief in
// the same scene". A [pbrmat] parse line proves a FILE was read; it says nothing about what any draw
// received, and the whole class of defect this fork keeps hitting is a value that moves in a variable
// while no uniform does. So the distinct (relief, depth, spec, rough, F0) sets actually PUSHED are
// collected PER DRAW PASS — the vector is cleared by PbrDrawBinder::begin() — and the high-water
// mark is logged. Two or more entries in one pass IS the measurement; one entry would mean every
// material is receiving the same numbers whatever the surface table says.
std::vector<std::array<float, 5>> g_pbrmat_pass_sets;
size_t g_pbrmat_logged_hwm = 0;
// Gpbr-material-props — the RUN-WIDE census, beside the per-pass one, and it exists because the
// per-pass mark cannot answer this phase's question. A pass only ever sees what the camera happened
// to FRAME, so its high-water mark under-counts by construction: with 25 materials binding maps in
// this level it read 2, and that 2 is a property of where the camera stood, not of the material
// table. This set is never cleared, so every distinct knob set that ever reached a draw is logged
// ONCE with the uniform values it produced. Still one level and one run — a material drawn here is
// in the scene — but no longer hostage to a viewpoint.
std::vector<std::array<float, 5>> g_pbrmat_run_sets;

static void pbr_push_material_uniforms(GLuint program, const custom_tex::PbrMaterialMaps* maps) {
  const auto& l = pbr_mat_uniform_locs(program);
  const float relief = maps ? maps->pm_relief : 1.f;
  const float depth = maps ? maps->pm_relief_depth : 1.f;
  const float spec = maps ? maps->pm_spec : 1.f;
  if (l.normal_strength >= 0) {
    glUniform1f(l.normal_strength, g_pbr_glob_normal_strength * relief);
  }
  if (l.height_scale >= 0) {
    glUniform1f(l.height_scale, g_pbr_glob_height_scale * depth);
  }
  if (l.spec_intensity >= 0) {
    glUniform1f(l.spec_intensity, g_pbr_glob_spec * spec);
  }
  if (l.mat >= 0) {
    glUniform4f(l.mat, maps ? maps->pm_rough_nomap : 0.9f, maps ? maps->pm_metal_nomap : 0.f,
                maps ? maps->pm_reflectance : 0.04f, maps ? maps->pm_normal_y : 1.f);
  }
  if (l.mat2 >= 0) {
    glUniform2f(l.mat2, maps ? maps->pm_rough_scale : 1.f, maps ? maps->pm_metal_scale : 1.f);
  }
  if (!maps) {
    return;  // the finish()/setup identity reset is not a material and must not be counted as one
  }
  const std::array<float, 5> k{relief, depth, spec, maps->pm_rough_nomap, maps->pm_reflectance};
  if (std::find(g_pbrmat_pass_sets.begin(), g_pbrmat_pass_sets.end(), k) ==
      g_pbrmat_pass_sets.end()) {
    g_pbrmat_pass_sets.push_back(k);
    if (g_pbrmat_pass_sets.size() > g_pbrmat_logged_hwm) {
      g_pbrmat_logged_hwm = g_pbrmat_pass_sets.size();
      lg::info(
          "[pbrmat-draw] {} DISTINCT material knob sets pushed in ONE draw pass; newest "
          "relief={:.3f} depth={:.3f} spec={:.3f} rough={:.3f} F0={:.3f} -> "
          "u_pbr_normal_strength={:.4f} u_pbr_height_scale={:.5f} u_pbr_spec_intensity={:.4f}",
          g_pbrmat_pass_sets.size(), k[0], k[1], k[2], k[3], k[4],
          g_pbr_glob_normal_strength * relief, g_pbr_glob_height_scale * depth,
          g_pbr_glob_spec * spec);
    }
  }
  if (std::find(g_pbrmat_run_sets.begin(), g_pbrmat_run_sets.end(), k) ==
      g_pbrmat_run_sets.end()) {
    g_pbrmat_run_sets.push_back(k);
    lg::info(
        "[pbrmat-run] distinct knob set #{} reached a draw: relief={:.3f} depth={:.3f} "
        "spec={:.3f} rough={:.3f} F0={:.3f} -> u_pbr_normal_strength={:.4f} "
        "u_pbr_height_scale={:.5f} u_pbr_spec_intensity={:.4f}",
        g_pbrmat_run_sets.size(), k[0], k[1], k[2], k[3], k[4],
        g_pbr_glob_normal_strength * relief, g_pbr_glob_height_scale * depth,
        g_pbr_glob_spec * spec);
  }
}

}  // namespace

// Grecharged-pbr-materials round-4: shared per-draw PBR material bind (was a lambda
// local to TFragment's loop; Tie3 now uses the same code so replaced TIE textures get
// the BRDF, not just the albedo). Byte-identical behavior to the original lambda.
void PbrDrawBinder::begin(GLuint program, const PbrDrawList* draws) {
  // Grecharged-materials-modern-parity: service a pending surfaces.json re-read HERE, on the GL
  // thread. The request comes from the GOAL kernel thread (the MODERN MATERIALS menu row), and the
  // re-read walks the same material registry a level load writes into — parsing it where the
  // request arrives would be a two-thread mutation of one std::unordered_map. This is the PBR
  // path's existing once-per-renderer GL-thread entry point, so it costs an atomic load per call
  // and nothing else.
  custom_tex::mm_service_reload();
  // Gpbr-per-texture-materials: the distinct-knob-set census is PER DRAW PASS, so that
  // "two materials differ" is a statement about one scene and not about a whole run.
  g_pbrmat_pass_sets.clear();
  m_program = program;
  m_draws = draws;
  m_mode_loc = -2;
  m_dc_loc = -2;
  m_cur_dc[0] = 0.f;
  m_cur_dc[1] = 0.f;
  // (0.5, 1.0) is the IDENTITY height normalisation that first_tfrag_draw_setup pushes as this
  // program's default, so this cached value matches the program state — not a stale guess.
  m_hstat_loc = -2;
  m_cur_hstat[0] = 0.5f;
  m_cur_hstat[1] = 1.0f;
  // ROUND 20: 0.5 tiles/m is the default first_tfrag_draw_setup pushes for u_pbr_uv_per_m, so this
  // cached value matches the program state (same contract as the hstat identity above).
  m_upm_loc = -2;
  m_cur_upm = 0.5f;
  // ROUND 20 correction: same contract for the feature-wavelength uniform — 0.25 tiles is the
  // identity default first_tfrag_draw_setup pushes.
  m_lambda_loc = -2;
  m_cur_lambda = 0.25f;
  m_cur_mode = 0;
  m_bound_any = false;
  // [cover] the draw context is per-caller, not per-program state: cleared here so a binder can
  // never inherit a stale label, and re-supplied by the caller right after begin().
  m_cover_renderer = nullptr;
  m_cover_kind = nullptr;
  m_cover_tess = false;
  m_cover_frame = 0;
}

void PbrDrawBinder::set_coverage_context(const char* renderer,
                                         const char* tree_kind,
                                         bool tess_program,
                                         u64 frame_idx) {
  m_cover_renderer = renderer;
  m_cover_kind = tree_kind;
  m_cover_tess = tess_program;
  m_cover_frame = frame_idx;
}

void PbrDrawBinder::set(s32 tex_id, const DrawMode& mode, bool mb_checker) {
  // Grecharged-mesh-browser V2.2 — the freecam Square toggle's FULL checker material (see the
  // header). Handled FIRST: it must work even when the draw's texture has NO registered PBR
  // material (want would be 0 and the early-out below would skip the bind entirely), and it does
  // not depend on the master PBR toggle — it IS the debug material. The killswitch still wins:
  // it exists to stop a crash loop, and the browser must never fight it.
  if (mb_checker && !pbr_killswitch()) {
    if (m_mode_loc == -2) {
      m_mode_loc = glGetUniformLocation(m_program, "u_pbr_mode");
    }
    if (m_mode_loc >= 0) {
      const auto& sm = pbr_testpattern::shared_maps();
      const auto& neutral = pbr_neutral_maps();
      glActiveTexture(GL_TEXTURE11);
      glBindTexture(GL_TEXTURE_2D, sm.normal_tex ? sm.normal_tex : neutral.normal_tex);
      glActiveTexture(GL_TEXTURE12);
      glBindTexture(GL_TEXTURE_2D, sm.rough_tex ? sm.rough_tex : neutral.rough_tex);
      glActiveTexture(GL_TEXTURE13);
      glBindTexture(GL_TEXTURE_2D, neutral.metal_tex);
      glActiveTexture(GL_TEXTURE14);
      glBindTexture(GL_TEXTURE_2D, neutral.ao_tex);
      glActiveTexture(GL_TEXTURE15);
      glBindTexture(GL_TEXTURE_2D, sm.height_tex ? sm.height_tex : neutral.height_tex);
      glActiveTexture(GL_TEXTURE16);
      glBindTexture(GL_TEXTURE_2D, neutral.specular_tex);
      glActiveTexture(GL_TEXTURE17);
      glBindTexture(GL_TEXTURE_2D, neutral.emissive_tex);
      glActiveTexture(GL_TEXTURE0);
      m_bound_any = true;
      const int cwant = 1 | 2 | 16;  // normal + rough + height: the full checker set
      if (cwant != m_cur_mode) {
        glUniform1i(m_mode_loc, cwant);
        m_cur_mode = cwant;
      }
      // The checker maps are synthetic and well-conditioned: zero normal DC, identity height
      // stats. The height dome's feature wavelength is 2 squares = 2/squares_per_tile tiles —
      // with the default 8 squares/tile that is exactly the 0.25 identity, and off-default
      // square counts keep the tess amplitude at checker-feature scale instead of tile scale.
      if (m_cur_dc[0] != 0.f || m_cur_dc[1] != 0.f) {
        if (m_dc_loc == -2) {
          m_dc_loc = glGetUniformLocation(m_program, "u_pbr_normal_dc");
        }
        if (m_dc_loc >= 0) {
          glUniform2f(m_dc_loc, 0.f, 0.f);
        }
        m_cur_dc[0] = 0.f;
        m_cur_dc[1] = 0.f;
      }
      if (m_cur_hstat[0] != 0.5f || m_cur_hstat[1] != 1.0f) {
        if (m_hstat_loc == -2) {
          m_hstat_loc = glGetUniformLocation(m_program, "u_pbr_height_stat");
        }
        if (m_hstat_loc >= 0) {
          glUniform2f(m_hstat_loc, 0.5f, 1.0f);
        }
        m_cur_hstat[0] = 0.5f;
        m_cur_hstat[1] = 1.0f;
      }
      if (m_cur_upm != 0.5f) {
        if (m_upm_loc == -2) {
          m_upm_loc = glGetUniformLocation(m_program, "u_pbr_uv_per_m");
        }
        if (m_upm_loc >= 0) {
          glUniform1f(m_upm_loc, 0.5f);
        }
        m_cur_upm = 0.5f;
      }
      const float clam = 2.0f / (float)std::max(1, pbr_testpattern::squares_per_tile());
      if (m_cur_lambda != clam) {
        if (m_lambda_loc == -2) {
          m_lambda_loc = glGetUniformLocation(m_program, "u_pbr_height_lambda");
        }
        if (m_lambda_loc >= 0) {
          glUniform1f(m_lambda_loc, clam);
        }
        m_cur_lambda = clam;
      }
      // Gpbr-per-texture-materials: the debug checker is a SYNTHETIC material that surfaces.json
      // does not name, so it takes the identity knobs — same rule as the zeroed DC / identity height
      // stats just above. Without this the checker would inherit the relief and roughness of
      // whatever real material the previous draw bound, and the browser's A/B would read a mixture.
      pbr_push_material_uniforms(m_program, nullptr);
      // V2.2 per-frame proof: the FULL checker set (normal+rough+height, albedo on unit 0 by the
      // caller) was bound on a targeted draw this frame.
      Gfx::g_global_settings.mb_cur_checker_full++;
      return;
    }
    // no u_pbr_mode in this program (non-PBR build): fall through to the normal path.
  }
  int want = 0;
  const custom_tex::PbrMaterialMaps* maps = nullptr;
  // ROUND 20: the matching entry itself, so the per-material measured UV density can be read.
  const PbrDrawEntry* ent = nullptr;
  // alpha-blended (TRANS "vis-alpha" tree) draws now take the PBR path too — round-4
  // coverage unification; alpha still comes from the legacy fragment_color*T0 product
  // in the shader, only rgb is relit. Decal draws keep the legacy path. PBR keys on
  // the texture, resolved once per level.
  if (Gfx::recharged_active(Gfx::g_global_settings.recharged_pbr_enable) && !pbr_killswitch() &&
      tex_id >= 0 && !mode.get_decal() && m_draws &&
      !m_draws->empty()) {
    for (auto& e : *m_draws) {
      if (e.tex_idx == tex_id) {
        maps = &e.maps;
        ent = &e;
        break;
      }
    }
    if (maps) {
      want = (maps->normal_tex ? 1 : 0) | (maps->rough_tex ? 2 : 0) | (maps->metal_tex ? 4 : 0) |
             (maps->ao_tex ? 8 : 0) | (maps->height_tex ? 16 : 0) |
             (maps->specular_tex ? 32 : 0) | (maps->emissive_tex ? 64 : 0) |
             // Grecharged-managed-assets: X/Y-only normal (compressed pack) — the shader
             // reconstructs Z. Only meaningful alongside bit 1.
             ((maps->normal_tex && maps->normal_is_rg) ? 128 : 0);
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
    // [cover] ROUND 21 DISPLACEMENT COVERAGE. This draw is about to bind PBR maps and push
    // u_pbr_mode, so it is exactly one "PBR-bound draw" — count it, and classify HOW (if at all) it
    // receives displacement, using the same conditions the shaders branch on:
    //   tfrag3_tess.tese:180  (mode & 16) && u_pbr_displacement == 2 && u_pbr_height_scale > 0
    //   tfrag3.frag:905/1690  (mode & 16) && u_pbr_debug != 8 && u_pbr_height_scale > 0 &&
    //                         (u_pbr_bisect & 128) == 0 && u_pbr_tess_active == 0
    // Neither open = the owner's FLAT CHUNK. Integer-only, no allocation, and only ever reached on
    // a draw that already does the PBR bind, so PBR-off frames pay nothing.
    if (m_cover_renderer) {
      const bool has_height = (want & 16) != 0;
      const float hs = g_cover_height_scale.load(std::memory_order_relaxed);
      const int bis = g_cover_bisect.load(std::memory_order_relaxed);
      const int dbg = g_cover_debug.load(std::memory_order_relaxed);
      const int disp = g_cover_displacement.load(std::memory_order_relaxed);
      const bool tess_disp = m_cover_tess && disp == 2 && hs > 0.f;
      const bool pom_disp = !m_cover_tess && hs > 0.f && (bis & 128) == 0 && dbg != 8;
      custom_tex::pbr_coverage_note_draw(m_cover_frame, m_cover_renderer, m_cover_kind, has_height,
                                         has_height && tess_disp, has_height && pom_disp);
    }
    // Bind ALL SEVEN units every time: the real map when present, the 1x1 neutral
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
    glActiveTexture(GL_TEXTURE16);
    glBindTexture(GL_TEXTURE_2D, maps->specular_tex ? maps->specular_tex : neutral.specular_tex);
    glActiveTexture(GL_TEXTURE17);
    glBindTexture(GL_TEXTURE_2D, maps->emissive_tex ? maps->emissive_tex : neutral.emissive_tex);
    glActiveTexture(GL_TEXTURE19);  // modern: subsurface thickness
    glBindTexture(GL_TEXTURE_2D, maps->thickness_tex ? maps->thickness_tex : neutral.thickness_tex);
    glActiveTexture(GL_TEXTURE0);
    m_bound_any = true;
  }
  if (want != m_cur_mode) {
    glUniform1i(m_mode_loc, want);
    m_cur_mode = want;
  }
  // Push this material's normal-map DC (mean surface gradient) alongside the mode. Zero when the
  // draw has no normal map, so a map-free draw can never inherit the previous material's tilt.
  const float dcx = (want & 1) ? maps->normal_dc_x : 0.f;
  const float dcy = (want & 1) ? maps->normal_dc_y : 0.f;
  if (dcx != m_cur_dc[0] || dcy != m_cur_dc[1]) {
    if (m_dc_loc == -2) {
      m_dc_loc = glGetUniformLocation(m_program, "u_pbr_normal_dc");
    }
    if (m_dc_loc >= 0) {
      glUniform2f(m_dc_loc, dcx, dcy);
    }
    m_cur_dc[0] = dcx;
    m_cur_dc[1] = dcy;
  }
  // Push this material's height-map statistics (mean, normalisation) alongside the mode. The
  // identity (0.5, 1.0) when the draw has no height map, so a map-free draw can never inherit the
  // previous material's normalisation.
  const float hsm = (want & 16) ? maps->height_mean : 0.5f;
  const float hsn = (want & 16) ? maps->height_norm : 1.0f;
  if (hsm != m_cur_hstat[0] || hsn != m_cur_hstat[1]) {
    if (m_hstat_loc == -2) {
      m_hstat_loc = glGetUniformLocation(m_program, "u_pbr_height_stat");
    }
    if (m_hstat_loc >= 0) {
      glUniform2f(m_hstat_loc, hsm, hsn);
    }
    m_cur_hstat[0] = hsm;
    m_cur_hstat[1] = hsn;
  }
  // ROUND 20: push this material's MEASURED authored UV density (texture tiles per world metre).
  // The tess displacement derives its world-space height LOOKUP RATE from it (so one height-map
  // tile spans exactly one painted tile) and the POM world-depth cap converts its metre limit with
  // it. 0.5 when no material is resolved for this draw => exactly the constant shaders hardcoded.
  const float upm = maps ? ent->uv_per_m : 0.5f;
  if (upm != m_cur_upm) {
    if (m_upm_loc == -2) {
      m_upm_loc = glGetUniformLocation(m_program, "u_pbr_uv_per_m");
    }
    if (m_upm_loc >= 0) {
      glUniform1f(m_upm_loc, upm);
    }
    m_cur_upm = upm;
  }
  // ROUND 20 correction: push this height MAP's characteristic feature wavelength (in tiles), which
  // is what the tess AMPLITUDE follows. Measured tiles are 2.3-7.9 m wide and hold many features
  // each, so scaling the depth by the tile would build metre-tall hills; scaling it by the feature
  // wavelength keeps the relief at feature scale. Identity 0.25 when the draw has no height map, so
  // a map-free draw can never inherit the previous material's wavelength (same rule as the hstat).
  // Gpbr-per-texture-materials: an AUTHORED wavelength (surfaces.json `relief_lambda`, > 0) replaces
  // the MEASURED one. The measured field is left untouched so the re-stamp on the next reload does
  // not destroy it — the override lives only in what is pushed.
  const float lam = (want & 16) ? ((maps->pm_relief_lambda > 0.f) ? maps->pm_relief_lambda
                                                                  : maps->height_lambda_tiles)
                                : 0.25f;
  if (lam != m_cur_lambda) {
    if (m_lambda_loc == -2) {
      m_lambda_loc = glGetUniformLocation(m_program, "u_pbr_height_lambda");
    }
    if (m_lambda_loc >= 0) {
      glUniform1f(m_lambda_loc, lam);
    }
    m_cur_lambda = lam;
  }
  // ===== Gpbr-per-texture-materials: THE PER-TEXTURE MATERIAL KNOBS ==============================
  // Owner 2026-08-28: « on applique un specular truc machin et un relief globalement, ça devrait
  // être texture par texture ». Until now relief/spec were frame-constant and per-PROGRAM (pushed
  // once by first_tfrag_draw_setup) and roughness/metallic/F0 were literals inside the shader, so a
  // sand and a cut-stone wall could not differ. Here they become per-DRAW, multiplied onto the
  // globals the setup pushed.
  // `want == 0 || !maps` => the IDENTITY (globals x 1 and the shader's own constants), so a draw
  // with no resolved material renders exactly as before and cannot inherit the previous one.
  pbr_push_material_uniforms(m_program, (want != 0) ? maps : nullptr);
  // ===== Grecharged-materials-modern-parity: the MODERN MATERIAL STACK block =====================
  // mm_flags already carries the master AND the per-material opt-in: mm_apply_params() cleared it
  // to 0 at load time if either was absent, and re-stamps every registered material when the menu
  // row is toggled. So there is no second gate to keep in sync here — if it is non-zero, this
  // material asked for the layer and the owner switched it on.
  // `want == 0` means this draw resolved no PBR material at all, in which case the modern layer has
  // nothing to ride on and must be off regardless of what the last draw pushed.
  const int mm_want = (want != 0 && maps) ? (int)maps->mm_flags : 0;
  const void* mm_key = (mm_want != 0) ? (const void*)maps : nullptr;
  if (mm_want != m_cur_mm_flags || mm_key != m_cur_mm_maps) {
    if (m_mm_flags_loc == -2) {
      m_mm_flags_loc = glGetUniformLocation(m_program, "u_mm_flags");
      m_mm_sss_loc = glGetUniformLocation(m_program, "u_mm_sss");
      m_mm_sss2_loc = glGetUniformLocation(m_program, "u_mm_sss2");
      m_mm_coat_loc = glGetUniformLocation(m_program, "u_mm_coat");
      m_mm_aniso_loc = glGetUniformLocation(m_program, "u_mm_aniso");
    }
    if (m_mm_flags_loc >= 0) {
      glUniform1i(m_mm_flags_loc, mm_want);
      if (mm_want != 0) {
        // Only pushed for a material that actually opted in. A draw with mm_flags == 0 leaves the
        // parameter uniforms holding the previous material's values, which is harmless precisely
        // because the shader chunk never reads them without the gate.
        if (m_mm_sss_loc >= 0) {
          glUniform4f(m_mm_sss_loc, maps->sss_color[0], maps->sss_color[1], maps->sss_color[2],
                      maps->sss_strength);
        }
        if (m_mm_sss2_loc >= 0) {
          glUniform4f(m_mm_sss2_loc, maps->sss_thickness, maps->sss_power, maps->sss_distort,
                      maps->sss_wrap);
        }
        if (m_mm_coat_loc >= 0) {
          glUniform4f(m_mm_coat_loc, maps->coat_weight, maps->coat_rough, maps->sss_ambient, 0.f);
        }
        if (m_mm_aniso_loc >= 0) {
          glUniform2f(m_mm_aniso_loc, maps->aniso, maps->aniso_angle);
        }
      }
      custom_tex::mm_note_active_draw(mm_want);
    }
    m_cur_mm_flags = mm_want;
    m_cur_mm_maps = mm_key;
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
  // Grecharged-materials-modern-parity: and the modern gate back to 0. The TFRAG3 program is shared
  // with renderers that never call set(), so leaving a non-zero u_mm_flags behind would let a later
  // draw enter the modern chunk carrying the last material's scattering colour.
  if (m_cur_mm_flags != 0) {
    if (m_mm_flags_loc == -2) {
      m_mm_flags_loc = glGetUniformLocation(m_program, "u_mm_flags");
    }
    if (m_mm_flags_loc >= 0) {
      glUniform1i(m_mm_flags_loc, 0);
    }
    m_cur_mm_flags = 0;
    m_cur_mm_maps = nullptr;
  }
  if (m_cur_dc[0] != 0.f || m_cur_dc[1] != 0.f) {
    if (m_dc_loc == -2) {
      m_dc_loc = glGetUniformLocation(m_program, "u_pbr_normal_dc");
    }
    if (m_dc_loc >= 0) {
      glUniform2f(m_dc_loc, 0.f, 0.f);
    }
    m_cur_dc[0] = 0.f;
    m_cur_dc[1] = 0.f;
  }
  // Same for the height normalisation: back to the identity (0.5, 1.0) the program defaults to.
  if (m_cur_hstat[0] != 0.5f || m_cur_hstat[1] != 1.0f) {
    if (m_hstat_loc == -2) {
      m_hstat_loc = glGetUniformLocation(m_program, "u_pbr_height_stat");
    }
    if (m_hstat_loc >= 0) {
      glUniform2f(m_hstat_loc, 0.5f, 1.0f);
    }
    m_cur_hstat[0] = 0.5f;
    m_cur_hstat[1] = 1.0f;
  }
  // ROUND 20: same for the measured UV density — back to the 0.5 tiles/m default the program
  // carries, so no later TFRAG3 user inherits this material's density.
  if (m_cur_upm != 0.5f) {
    if (m_upm_loc == -2) {
      m_upm_loc = glGetUniformLocation(m_program, "u_pbr_uv_per_m");
    }
    if (m_upm_loc >= 0) {
      glUniform1f(m_upm_loc, 0.5f);
    }
    m_cur_upm = 0.5f;
  }
  // ROUND 20 correction: and the feature wavelength back to its 0.25-tile identity.
  if (m_cur_lambda != 0.25f) {
    if (m_lambda_loc == -2) {
      m_lambda_loc = glGetUniformLocation(m_program, "u_pbr_height_lambda");
    }
    if (m_lambda_loc >= 0) {
      glUniform1f(m_lambda_loc, 0.25f);
    }
    m_cur_lambda = 0.25f;
  }
  // Gpbr-per-texture-materials: repose the GLOBAL relief/spec exactly as first_tfrag_draw_setup
  // pushed them, and the shader's own constants for the material vector. The TFRAG3 program is
  // shared with renderers that never call set() (HFRAG in particular), and those must see the
  // frame-constant globals, never the last material's multipliers.
  pbr_push_material_uniforms(m_program, nullptr);
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
  if (!(Gfx::recharged_active(Gfx::g_global_settings.recharged_pbr_enable) ||
        Gfx::recharged_active(Gfx::g_global_settings.recharged_rt_light_enable)) ||
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
  const auto& gs = Gfx::g_global_settings;
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
  // Item 1: which light (0 = yellow sun / 1 = green sun) the READ-side map was rendered from,
  // so the shader applies the cast-shadow occlusion to the MATCHING directional term.
  GLint sl_loc = glGetUniformLocation(program, "u_rt_shadow_light");
  if (sl_loc >= 0) {
    glUniform1i(sl_loc, st.read_shadow_light);
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
  glUniform1i(glGetUniformLocation(program, "u_pbr_debug"), pbr_debug_mode());
}
#endif

void first_tfrag_draw_setup(const GoalBackgroundCameraData& settings,
                            SharedRenderState* render_state,
                            ShaderId shader) {
  const auto& sh = render_state->shaders[shader];
  sh.activate();
  auto id = sh.id();
#ifdef OG_FEAT_PBR
  // ★ OWNER CHECKER VERDICT, BUG B (2026-07-26): "des chunks entiers (LA PLUPART) sont juste
  // PLATS alors que le damier est bien présent". The fragment POM was gated on the GLOBAL setting
  // (u_pbr_displacement != 2), so selecting Tessellation switched the parallax OFF on every draw
  // the tess program does not cover — all TIE props/walls, shrubs, hfrag, the non-opaque tfrag
  // trees, and every patch past the tesc's 30 m gate. Those draws then had NO displacement at all:
  // flat chunks right next to raised ones, exactly what the checkerboard exposed. The suppression
  // has to be per-PROGRAM: only the program that actually runs the tessellation stages may skip
  // the POM, everything else keeps it. Every other caller (Tie3, Shrub, Hfrag) passes a non-tess
  // ShaderId and therefore gets 0 = "run the POM".
  glUniform1i(glGetUniformLocation(id, "u_pbr_tess_active"),
              shader == ShaderId::TFRAG3_TESS ? 1 : 0);
#endif
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
  // IDENTITY height normalisation (mean 0.5, norm 1.0) — the per-draw binder overrides it with the
  // material's measured statistics and restores this default in finish().
  glUniform2f(glGetUniformLocation(id, "u_pbr_height_stat"), 0.5f, 1.0f);
  // ROUND 20: default authored UV density = the 0.5 tiles/m the shaders used to hardcode. The
  // per-draw binder overrides it with the material's measured density, and restores it in finish().
  glUniform1f(glGetUniformLocation(id, "u_pbr_uv_per_m"), 0.5f);
  // ROUND 20 correction: identity feature wavelength (0.25 tile); the per-draw binder overrides it
  // with the height map's measured spectrum and restores this in finish().
  glUniform1f(glGetUniformLocation(id, "u_pbr_height_lambda"), 0.25f);
  glUniform1i(glGetUniformLocation(id, "tex_PBR_N"), 11);
  glUniform1i(glGetUniformLocation(id, "tex_PBR_R"), 12);
  glUniform1i(glGetUniformLocation(id, "tex_PBR_M"), 13);
  glUniform1i(glGetUniformLocation(id, "tex_PBR_AO"), 14);
  glUniform1i(glGetUniformLocation(id, "tex_PBR_H"), 15);
  // Grecharged-pbr-realtime-fusion: specular (F0) + emissive maps on units 16/17
  // (probe samplers sit on 3-7, DirectRenderer starts at 20 — no collision; GLES 3.x
  // guarantees >=32 combined units and the fragment stage uses 14 samplers <= 16).
  glUniform1i(glGetUniformLocation(id, "tex_PBR_S"), 16);
  glUniform1i(glGetUniformLocation(id, "tex_PBR_E"), 17);
  // Grecharged-materials-modern-parity: subsurface THICKNESS on unit 19. 18 is shrub's wind-anchor
  // LUT (tex_T18), 20-29 belong to DirectRenderer, so 19 is the only free slot below the auto-bind
  // range. SAMPLER BUDGET, stated because it is now the binding constraint and not a comfortable
  // one: the world fragment stage declares tex_T0 + 8 PBR maps + the shadow map + 4 probe sampler3D
  // + 1 samplerCube = 15, against a GL_MAX_TEXTURE_IMAGE_UNITS floor of 16 on GLES 3.2. ONE slot
  // left. The next channel that wants a map must pack into an existing one (as _orm does for
  // occlusion/roughness/metallic) rather than take a unit.
  glUniform1i(glGetUniformLocation(id, "tex_PBR_TH"), 19);
  // The modern stack's gate: OFF for every program at setup. The per-draw binder raises it only for
  // a material that opted in, and lowers it again in finish().
  glUniform1i(glGetUniformLocation(id, "u_mm_flags"), 0);
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
  // REOPEN #6 (owner playtest #5: the "~10cm epoxy float" = the POM depth is ~100x too large,
  // the texture swims off the geometry). Calibrated DOWN to a surface-locked micro-relief:
  // 0.02 (was 0.07) UV-space depth. The primary relief now comes from the NORMAL-MAP SHADING
  // (surface-locked, cannot float — normal_strength stays strong); POM only adds a subtle,
  // CLAMPED (see tfrag3.frag surface-lock) occlusion parallax that stays welded to the surface.
  // Tessellation (the real geometric displacement) keeps its ~5cm depth via TESS_DISP_K in the
  // tese (bumped to compensate this reduction) — real vertices never float.
  // REOPEN#7 (owner: the neutered 0.02 was OVER-corrected => displacement invisible): with the new
  // per-vertex-tangent CONTINUOUS TBN the parallax is properly surface-locked, so the depth is
  // restored to a clearly VISIBLE micro-relief (0.05 UV base, * relief slider, then hard-clamped in
  // the shader to 0.08 UV total) — visible depth that stays welded to the surface, no epoxy float.
  float height_scale = 0.05f;
  float uv_tile = 1.0f;
  // Grecharged-pbr-realtime-fusion: emissive intensity multiplier (fused rt+pbr path).
  float emissive_str = 1.0f;
  // REOPEN #2 menu sliders (owner: tunables in SETTINGS, not adb props): TEXTURE RELIEF
  // multiplies normal strength + POM height (1.0 = the previous look; shipped default 1.5
  // = noticeably stronger relief). SPECULAR INTENSITY scales the fused specular sum.
  // Debug props still override for headless calibration.
  float relief = gs.recharged_pbr_texture_relief;
  float spec_intensity = gs.recharged_pbr_spec_intensity;
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
  // ROUND 22: the prop/env read moved to pbr_debug_mode() above so the non-background renderers
  // (hfrag/merc2/generic/emerc) can be told the same mode. Value is unchanged.
  int pbr_debug = pbr_debug_mode();
  // REOPEN #3 TERM BISECTION (owner: sheen survives specular=0): bitmask zeroing ONE
  // fused-path lighting term at a time — semantics documented at u_pbr_bisect in
  // tfrag3.frag. Absent prop = 0 = full path (no behavioural change).
  // REOPEN #10: seed the mask from the IN-MENU "PBR ISOLATE" carousel (recharged_pbr_isolate,
  // resolved to the 0/128/64/192 mask in pc_set_pbr_isolate) so the owner can flip
  // Both / Normal-map-only / Parallax-only / Neither at his vantage with no adb. The debug
  // prop/env below still OVERRIDE it for headless supervisor A/B on the full term set.
  int pbr_bisect = gs.recharged_pbr_isolate;
  // Gpbr-per-texture-materials: bisect BANK 2 (bank 1's 31 bits are all taken). Debug-only:
  // no menu row, no GOAL setter — 0 is the shipped/fixed behaviour.
  int pbr_bisect2 = 0;
  // Grecharged-materials-modern-parity. Deliberately NOT new u_pbr_bisect bits: that mask is FULL
  // (every bit from 1 to 2^30 is allocated, and bit 2 is already double-booked between the green-sun
  // specular and a normal-convention flip, which silently confounds any A/B run on it). The modern
  // stack gets its own two knobs instead — an exposure multiplier and a per-channel isolation viz —
  // so nothing here can collide with an existing killswitch.
  float mm_exposure = 1.0f;
  int mm_debug = 0;
  // REOPEN #3 DISPLACEMENT menu carousel (0 Off / 1 Parallax / 2 Tessellation). Menu value
  // from GOAL via pc-set-pbr-displacement!; debug prop overrides for headless A/B.
  int pbr_displacement = gs.recharged_pbr_displacement;
  // NEAR-FIELD TESSELLATION CEILING (owner playtest #17 "glorified bump"): the shipped tesc capped
  // near-field tessellation at level 12, which under-resolved the height field — the displacement
  // had nowhere near enough vertices to become real depth. This is the ceiling of the new
  // inverse-distance level law, clamped below to what the driver actually allows.
  // OWNER PLAYTEST #18 ("la tessellation manque de relief EN PARTICULIER AU SOL"): raised 32 -> 64
  // together with the tesc's world-space-edge-length law. Measured at the owner's own vantage with
  // tools/tess_audit, the GROUND mean generated-segment size within 5 m is 9.68 cm at cap 32 (the
  // law saturates: mean achieved level 31.99/32) versus 5.60 cm at cap 64, which is what puts the
  // ground inside the mandated 5-10 cm/segment target. 64 is the GL/GLES minimum-maximum for
  // GL_MAX_TESS_GEN_LEVEL and is what both test devices report, and the clamp below still defers to
  // whatever the live driver actually allows.
  float pbr_tess_max = 64.0f;
  // Target size in METRES of one generated tessellation segment in the near field — the density knob
  // the new level law solves for (tfrag3_tess.tesc::tess_seg_target_m). Raising it is the cheapest
  // perf lever (cost ~ 1/seg^2).
  // ROUND #19: 0.06 -> 0.025. At 6 cm the tessellated ground was still ~2.4x coarser than the 5 cm
  // height features it exists to displace (measured GROUND-with-a-height-map v/feature 0.85 within
  // 5 m), which is why the supervisor's device A/B found tessellation moving the ground band by
  // 0.77/255 while the parallax it replaces moved 2.27. 2.5 cm is Nyquist for a 5 cm feature, and it
  // only became REACHABLE this round: at 6 cm a 4.6 m ground patch already saturated the 64-level
  // ceiling, so asking for 2.5 cm without the offline pre-subdivision would simply have been
  // clipped. Measured after pre-subdivision: v/feature 0.85 -> 2.37 within 5 m. This is the
  // TESSELLATION tier's knob — the parallax and stock tiers never reach this code.
  float pbr_tess_seg = 0.025f;
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
    // (debug.opengoal.pbr.debug is read by pbr_debug_mode() at the pbr_debug initialiser above.)
    if (__system_property_get("debug.opengoal.pbr.nstrength", v) > 0) {
      normal_strength = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.height", v) > 0) {
      height_scale = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.uvtile", v) > 0) {
      uv_tile = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.emissive", v) > 0) {
      emissive_str = atof(v);
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
    if (__system_property_get("debug.opengoal.pbr.relief", v) > 0) {
      relief = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.specint", v) > 0) {
      spec_intensity = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.bisect", v) > 0) {
      pbr_bisect = atoi(v);
    }
    if (__system_property_get("debug.opengoal.pbr.bisect2", v) > 0) {
      pbr_bisect2 = atoi(v);
    }
    if (__system_property_get("debug.opengoal.mm.exposure", v) > 0) {
      mm_exposure = atof(v);
    }
    if (__system_property_get("debug.opengoal.mm.debug", v) > 0) {
      mm_debug = atoi(v);
    }
    if (__system_property_get("debug.opengoal.pbr.displacement", v) > 0) {
      pbr_displacement = atoi(v);
    }
    if (__system_property_get("debug.opengoal.pbr.tessmax", v) > 0) {
      pbr_tess_max = atof(v);
    }
    if (__system_property_get("debug.opengoal.pbr.tessseg", v) > 0) {
      // A NEGATIVE value means "not set, keep the compiled default". adb cannot delete a property
      // (setprop '' is an error), so a harness that wants the default back must be able to say so
      // with a value; without this a "-1" would clamp to 0.01 and silently pick 1 cm segments.
      const float sv = atof(v);
      if (sv > 0.f) {
        pbr_tess_seg = sv;
      }
    }
  }
#else
  // (OG_PBR_DEBUG is read by pbr_debug_mode() at the pbr_debug initialiser above.)
  if (const char* e = getenv("OG_PBR_NSTRENGTH")) {
    normal_strength = atof(e);
  }
  if (const char* e = getenv("OG_PBR_HEIGHT")) {
    height_scale = atof(e);
  }
  if (const char* e = getenv("OG_PBR_UVTILE")) {
    uv_tile = atof(e);
  }
  if (const char* e = getenv("OG_PBR_EMISSIVE")) {
    emissive_str = atof(e);
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
  if (const char* e = getenv("OG_PBR_RELIEF")) {
    relief = atof(e);
  }
  if (const char* e = getenv("OG_PBR_SPECINT")) {
    spec_intensity = atof(e);
  }
  if (const char* e = getenv("OG_PBR_BISECT")) {
    pbr_bisect = atoi(e);
  }
  if (const char* e = getenv("OG_PBR_BISECT2")) {
    pbr_bisect2 = atoi(e);
  }
  if (const char* e = getenv("OG_MM_EXPOSURE")) {
    mm_exposure = atof(e);
  }
  if (const char* e = getenv("OG_MM_DEBUG")) {
    mm_debug = atoi(e);
  }
  if (const char* e = getenv("OG_PBR_DISPLACEMENT")) {
    pbr_displacement = atoi(e);
  }
  if (const char* e = getenv("OG_PBR_TESSMAX")) {
    pbr_tess_max = atof(e);
  }
  if (const char* e = getenv("OG_PBR_TESSSEG")) {
    pbr_tess_seg = atof(e);
  }
#endif
  // REOPEN #2: clamp the sliders and fold TEXTURE RELIEF into the relief tunables.
  relief = std::max(0.0f, std::min(relief, 3.0f));
  spec_intensity = std::max(0.0f, std::min(spec_intensity, 3.0f));
  normal_strength *= relief;
  height_scale *= relief;
  // Grecharged-mesh-browser V2.1: record the relief factor these uniforms are pushed with — the
  // proof reads THE VALUE THE SHADER GOT (u_pbr_normal_strength/u_pbr_height_scale scale), not the
  // menu variable (owner: "relief fonctionne pas" — a variable can move while no uniform does).
  Gfx::g_global_settings.mb_cur_relief_x100 = (u32)std::lround(relief * 100.0f);
  // The tess ceiling can never exceed what the driver reports as GL_MAX_TESS_GEN_LEVEL.
  pbr_tess_max = std::clamp(pbr_tess_max, 1.0f, (float)gl_max_tess_gen_level());
  glUniform1i(glGetUniformLocation(id, "u_pbr_debug"), pbr_debug);
  glUniform1i(glGetUniformLocation(id, "u_pbr_bisect"), pbr_bisect);
  glUniform1i(glGetUniformLocation(id, "u_pbr_bisect2"), pbr_bisect2);
  pbr_displacement = std::max(0, std::min(pbr_displacement, 2));
  // Driver-defensive fallback (GL thread): tessellation (mode 2) instant-crashes drivers where
  // the tess entry points/program are unusable. Demote the EFFECTIVE mode to Parallax (1) so the
  // frag shader runs POM (its POM gate is u_pbr_displacement != 2) instead of standing down with
  // no displacement. Warn once.
  if (pbr_displacement == 2 &&
      (!gl_context_supports_tessellation() || !gl_tfrag3_tess_program_ok())) {
    pbr_displacement = 1;
    static bool warned_tess_fallback = false;
    if (!warned_tess_fallback) {
      warned_tess_fallback = true;
      // OWNER PLAYTEST #8: name the EXACT reason for the Tessellation->Parallax demotion so the
      // supervisor's Honor logcat shows why (capability query vs program build), not just silence.
      const char* reason = !gl_context_supports_tessellation()
                               ? "capability query failed (no tess stages / glPatchParameteri NULL)"
                               : "tess program build/link failed";
      lg::warn("[pbr-tess] fallback: displacement Tessellation(2)->Parallax(1) reason=\"{}\"", reason);
      lg::warn(
          "[recharged] tessellation unavailable on this driver — displacement falling back to "
          "Parallax");
    }
  }
  // mode 0 (Off) also zeroes the height scale so BOTH the frag POM and any tess
  // displacement see no height contribution.
  if (pbr_displacement == 0) {
    height_scale = 0.0f;
  }
  // [cover] ROUND 21: publish the EFFECTIVE displacement gates (post prop/env override, post
  // tess->parallax demotion, post mode-0 zeroing) so PbrDrawBinder::set can classify each draw
  // against the very values the shaders were just handed. Reading gs directly there would miss all
  // three corrections. Three relaxed stores per program setup; nothing is rendered from them.
  pbr_cover_publish_gates(height_scale, pbr_bisect, pbr_debug, pbr_displacement);
  glUniform1i(glGetUniformLocation(id, "u_pbr_displacement"), pbr_displacement);
  glUniform1f(glGetUniformLocation(id, "u_pbr_tess_max"), pbr_tess_max);
  // OWNER #18: the near-field target segment size the tesc level law solves for. Clamped to a sane
  // band (1 cm .. 2 m) so a bad prop can neither melt the GPU nor silently disable displacement.
  pbr_tess_seg = std::clamp(pbr_tess_seg, 0.01f, 2.0f);
  glUniform1f(glGetUniformLocation(id, "u_pbr_tess_seg"), pbr_tess_seg);
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
  int rt_light_on = Gfx::recharged_active(gs.recharged_rt_light_enable) ? 1 : 0;
  // ITEM A (owner playtest #2): I tried raising the sun intensity 1.5->1.75 to widen the sun-lit vs
  // ambient-only separation, but a device A/B measured NO contrast change (P90/std identical) — at the
  // owner vantage the sun-lit term is already tone-mapped/vantage-limited, so intensity does not move
  // the lit-vs-shadow gap. Reverted to the owner-ACCEPTED 1.5 (daylight "nickel") to avoid regressing
  // the validated look. Still per-frame overridable via debug.opengoal.rt.intensity.
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
  float sun_up_raw = 1.0f;  // yellow-sun elevation sine (default fully-up until the first sky-sun push)
  {
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
  {
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
#ifdef __ANDROID__
  { char rv[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.rt.moonintensity", rv) > 0 && rv[0]) moon_intensity = atof(rv); }
#else
  if (const char* e = getenv("OG_RT_MOONINTENSITY")) moon_intensity = atof(e);
#endif
  if (!(moon_intensity >= 0.0f && moon_intensity <= 2.0f)) moon_intensity = 0.40f;
  // Device A/B: force the green-sun elevation weight (like debug.opengoal.rt.sunelev for the yellow sun)
  // so the green-sun contribution can be isolated on/off at a fixed vantage (0 = green off, 1 = full).
#ifdef __ANDROID__
  { char rv[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.rt.greenelev", rv) > 0 && rv[0]) {
      float g = atof(rv);
      if (g >= 0.0f) green_elev = g;  // NEGATIVE sentinel (-1) => keep the REAL green-sun elevation
    }                                  // (a prop cannot be cleared headlessly, so -1 = "release override")
  }
#else
  if (const char* e = getenv("OG_RT_GREENELEV")) {
    float g = atof(e);
    if (g >= 0.0f) green_elev = g;
  }
#endif
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
  float owning_up = (pbr_shadow_state().shadow_light == 1) ? green_up_raw : sun_up_raw;
  float rt_shadow_conf = rt_smoothstep(0.05f, 0.30f, owning_up);

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
  float handoff_alpha = 0.10f;
#ifdef __ANDROID__
  { char rv[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.rt.handoffsmooth", rv) > 0 && rv[0]) handoff_alpha = atof(rv); }
#else
  if (const char* e = getenv("OG_RT_HANDOFFSMOOTH")) handoff_alpha = atof(e);
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
  float ambW_y = ambW_y_raw, ambW_g = ambW_g_raw;
  {
    static u64 s_ho_frame = ~0ull;
    static float s_ho_sunelev = 1.0f, s_ho_moon = 0.0f, s_ho_conf = 0.0f;
    static float s_ho_ambY = 1.0f, s_ho_ambG = 0.0f;  // ambient-orientation elevation weights (playtest #5)
    static bool s_ho_seed = false;
    if (!s_ho_seed) {  // seed to the current raw values so we don't ramp from the defaults on boot
      s_ho_sunelev = rt_sun_elev; s_ho_moon = moon_scale; s_ho_conf = rt_shadow_conf;
      s_ho_ambY = ambW_y_raw; s_ho_ambG = ambW_g_raw; s_ho_seed = true;
    }
    if (render_state->frame_idx != s_ho_frame) {  // advance the EMA exactly once per frame
      s_ho_frame = render_state->frame_idx;
      s_ho_sunelev += handoff_alpha * (rt_sun_elev - s_ho_sunelev);
      s_ho_moon += handoff_alpha * (moon_scale - s_ho_moon);
      s_ho_conf += handoff_alpha * (rt_shadow_conf - s_ho_conf);
      s_ho_ambY += handoff_alpha * (ambW_y_raw - s_ho_ambY);
      s_ho_ambG += handoff_alpha * (ambW_g_raw - s_ho_ambG);
    }
    rt_sun_elev = s_ho_sunelev;
    moon_scale = s_ho_moon;
    rt_shadow_conf = s_ho_conf;
    ambW_y = s_ho_ambY;
    ambW_g = s_ho_ambG;
  }
  glUniform1f(glGetUniformLocation(id, "u_rt_sun_elev"), rt_sun_elev);  // moved: upload the SMOOTHED value
#ifdef __ANDROID__
  // Deterministic state-dump (owner prefers this to eyeballing): green-sun elevation weight, yellow-sun
  // elevation, green direction, shadow-handoff confidence, and which sun currently owns the shadow map.
  { char dv[PROP_VALUE_MAX]; static int gdbg = 0;
    if (__system_property_get("debug.opengoal.rt.greendbg", dv) > 0 && dv[0] == '1' && (gdbg++ % 120) == 0) {
      lg::info("GDA-GREENSUN green_elev={:.3f} sun_elev={:.3f} conf={:.3f} gdir=({:.2f},{:.2f},{:.2f}) shadow_light={}",
               green_elev, rt_sun_elev, rt_shadow_conf, moon_dir[0], moon_dir[1], moon_dir[2],
               pbr_shadow_state().shadow_light);
    }
  }
#endif
  glUniform3f(glGetUniformLocation(id, "u_rt_moon_dir"), moon_dir[0], moon_dir[1], moon_dir[2]);
  glUniform3f(glGetUniformLocation(id, "u_rt_moon_color"),
              MOON_GREEN[0] * moon_scale, MOON_GREEN[1] * moon_scale, MOON_GREEN[2] * moon_scale);
  glUniform1f(glGetUniformLocation(id, "u_rt_shadow_conf"), rt_shadow_conf);  // playtest #4 stepless shadow handoff
  // ROUND-5: residual brightness a fully-occluded fragment keeps (1 - Shadow Strength).
  glUniform1f(glGetUniformLocation(id, "u_rt_shadow_residual"), rt_shadow_residual);

  // === Grecharged-directional-ambient: HEMISPHERE ambient (replaces the flat ~0.2 floor). ===
  // The ambient base is directional: an up-hemisphere SKY tint and a down-hemisphere GROUND bounce,
  // blended per-fragment by the world normal in the shader. Both track the mood/TOD ambient so the day
  // cycle drives the HUE; the LEVEL is the Ambient Strength setting, gently faded by the real sun
  // elevation (reusing rt_sun_elev) so night stays calm — NO mood night presets feed the brightness
  // (round-7 night-leak discipline). Golden rule: this only reshapes the ambient base; the direct-sun
  // term is untouched so sunlit surfaces are unchanged.
  int rt_ambient_on = Gfx::recharged_active(gs.recharged_rt_ambient_enable) ? 1 : 0;
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
  // Grecharged-directional-ambient: AZIMUTHAL ambient CONTRAST — the owner's Ambient Contrast control =
  // the directional SPREAD of the ambient base around its mean (a levels/contrast notion, NOT a
  // brightness). From pc-settings; overridable per-frame by a debug prop / env for on-device A/B.
  float rt_ambient_contrast = gs.recharged_rt_ambient_contrast;
#ifdef __ANDROID__
  {
    char rv[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.rt.ambientcontrast", rv) > 0 && rv[0]) {
      rt_ambient_contrast = atof(rv);
    }
  }
#else
  if (const char* e = getenv("OG_RT_AMBIENTCONTRAST")) {
    rt_ambient_contrast = atof(e);
  }
#endif
  // Grecharged-directional-ambient ROUND 2: ambient MODEL selector (0 HEMISPHERE, 1 SH, 2 IBL). From
  // pc-settings; overridable per-frame by a debug prop / env for on-device A/B without menu navigation.
  int rt_ambient_model = gs.recharged_rt_ambient_model;
#ifdef __ANDROID__
  {
    char rv[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.rt.ambientmodel", rv) > 0 && rv[0]) {
      rt_ambient_model = atoi(rv);
    }
  }
#else
  if (const char* e = getenv("OG_RT_AMBIENTMODEL")) {
    rt_ambient_model = atoi(e);
  }
#endif
  if (rt_ambient_model < 0 || rt_ambient_model > 2) {
    rt_ambient_model = 0;
  }
  // Grecharged-directional-ambient ROOT-CAUSE FIX: debug/A-B toggle to force the OLD flat per-face
  // screen-derivative normal instead of the reconstructed SMOOTH per-vertex normal. Default 0 = smooth
  // (the fix). Set 1 to reproduce the pre-fix faceted look for a same-build before/after comparison.
  // Not exposed in the menu (debug-only); driven by a prop/env during device capture.
  int rt_flat_normal = 0;
#ifdef __ANDROID__
  {
    char rv[PROP_VALUE_MAX];
    if (__system_property_get("debug.opengoal.rt.flatnormal", rv) > 0 && rv[0]) {
      rt_flat_normal = atoi(rv);
    }
  }
#else
  if (const char* e = getenv("OG_RT_FLATNORMAL")) {
    rt_flat_normal = atoi(e);
  }
#endif
  {
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
    // Grecharged-directional-ambient (owner playtest #5): AMBIENT orientation = a per-sun elevation-weighted
    // BLEND of the YELLOW-sun and GREEN-sun azimuths (each an azimuthal key + fixed 0.5 up-tilt). Each sun's
    // azimuthal contribution is scaled by its OWN smoothed natural elevation weight (ambW_y / ambW_g), and the
    // MAGNITUDE of the summed key carries the directionality (the shader's rt_shape = 1 + k*dot(N,amb_key) is
    // unchanged):
    //   - one sun comfortably up  => key ~= that sun's unit azimuth (mag ~1) => full directional form;
    //   - DARK NEUTRAL MIDDLE (both suns below the horizon) => both weights ~0 => key -> ~0 => rt_shape -> 1
    //     => the ambient collapses to its near-uniform SH/hemisphere base, NO lateral orientation to "flip";
    //   - the two suns are ANTIPHASE so their azimuthal parts CANCEL through the crossover => the orientation
    //     eases OUT (fades toward neutral) then IN toward green, never snapping ~180deg. Symmetric at dawn.
    // A/B: debug.opengoal.rt.ambfade "0" restores the OLD locked-yellow full-strength key (reproduces the snap).
    float amb_key[3];
    {
      float amb_fade = 1.0f;
#ifdef __ANDROID__
      { char rv[PROP_VALUE_MAX];
        if (__system_property_get("debug.opengoal.rt.ambfade", rv) > 0 && rv[0]) amb_fade = atof(rv); }
#else
      if (const char* e = getenv("OG_RT_AMBFADE")) amb_fade = atof(e);
#endif
      float wY = (amb_fade > 0.5f) ? ambW_y : 1.0f;   // ambfade off => OLD behaviour (yellow, full directionality)
      float wG = (amb_fade > 0.5f) ? ambW_g : 0.0f;
      // per-sun azimuthal key (unit): the sun's horizontal azimuth + a fixed 0.5 up-tilt, normalized.
      float yk[3], gk[3];
      for (int pass = 0; pass < 2; pass++) {
        const float* d = (pass == 0) ? light_dir : moon_dir;  // yellow sun, then green sun
        float* out = (pass == 0) ? yk : gk;
        float hx = d[0], hz = d[2];
        float hl = std::sqrt(hx * hx + hz * hz);
        if (hl > 1e-4f) { float s = 0.85f / hl; out[0] = hx * s; out[1] = 0.5f; out[2] = hz * s; }
        else { out[0] = 0.f; out[1] = 1.f; out[2] = 0.f; }
        float l = std::sqrt(out[0]*out[0] + out[1]*out[1] + out[2]*out[2]);
        out[0] /= l; out[1] /= l; out[2] /= l;
      }
      amb_key[0] = wY * yk[0] + wG * gk[0];
      amb_key[1] = wY * yk[1] + wG * gk[1];
      amb_key[2] = wY * yk[2] + wG * gk[2];
      // clamp magnitude to <=1 (one sun up => full directionality; dark middle => ->0 = neutral). Do NOT
      // re-normalize below 1 — the faded magnitude IS the dark-middle orientation collapse.
      float akl = std::sqrt(amb_key[0]*amb_key[0] + amb_key[1]*amb_key[1] + amb_key[2]*amb_key[2]);
      if (akl > 1.0f) { amb_key[0] /= akl; amb_key[1] /= akl; amb_key[2] /= akl; }
    }
    glUniform1i(glGetUniformLocation(id, "u_rt_ambient_on"), rt_ambient_on);
    glUniform1i(glGetUniformLocation(id, "u_rt_ambient_model"), rt_ambient_model);
    glUniform3f(glGetUniformLocation(id, "u_rt_ambient_key"), amb_key[0], amb_key[1], amb_key[2]);
    glUniform1f(glGetUniformLocation(id, "u_rt_ambient_contrast"), rt_ambient_contrast);
    glUniform1i(glGetUniformLocation(id, "u_rt_flat_normal"), rt_flat_normal);
    glUniform3f(glGetUniformLocation(id, "u_rt_sky_color"), sky[0], sky[1], sky[2]);
    glUniform3f(glGetUniformLocation(id, "u_rt_ground_color"), ground[0], ground[1], ground[2]);
    glUniform3f(glGetUniformLocation(id, "u_rt_env_zenith"), env_zenith[0], env_zenith[1], env_zenith[2]);
    glUniform3f(glGetUniformLocation(id, "u_rt_env_horizon"), env_horizon[0], env_horizon[1], env_horizon[2]);
    glUniform3f(glGetUniformLocation(id, "u_rt_env_ground"), env_ground[0], env_ground[1], env_ground[2]);
    glUniform3f(glGetUniformLocation(id, "u_rt_sun_glow"), sun_glow[0], sun_glow[1], sun_glow[2]);
    glUniform3fv(glGetUniformLocation(id, "u_rt_sh[0]"), 9, &shc[0][0]);

    // === Grecharged-pbr-realtime-fusion: DYNAMIC FOLLOW-PROBE (replaces the deleted LightProbeGrid).
    // Feeds the PBR ambient-specular / reflection term (u_rt_probe_cube, tfrag3.frag:767) from ONE
    // amortized camera-centered cubemap re-rendered from THIS live procedural sky (env_* + sun_glow
    // + surface->sun), tiered by the user setting recharged_follow_probe. The same call also
    // re-homes the baked-modulation amplitude uniforms orphaned by the grid deletion, and forces the
    // removed SH-volume grid off (see FollowProbe.cpp). Runs ~5x/frame; the capture is guarded on
    // frame_idx internally so the 1-face/frame amortization is per-frame, not per-shader.
    FollowProbeEnv fpe;
    for (int i = 0; i < 3; i++) {
      fpe.zenith[i] = env_zenith[i];
      fpe.horizon[i] = env_horizon[i];
      fpe.ground[i] = env_ground[i];
      fpe.sun_glow[i] = sun_glow[i];
      fpe.sun_dir[i] = sun_d[i];
    }
    float fp_cam[3] = {settings.trans[0], settings.trans[1], settings.trans[2]};
    FollowProbe::get().update_and_bind(id, fp_cam, render_state->frame_idx, fpe,
                                       gs.recharged_follow_probe);
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
  // Gpbr-per-texture-materials: memorise the three GLOBAL material values at the exact point they
  // are handed to the program — AFTER the relief multiply and AFTER the `displacement == 0` zeroing
  // of height_scale, so what PbrDrawBinder multiplies by a material factor is the value the shader
  // really got, never a pre-clamp one. finish() reposes these same three numbers.
  g_pbr_glob_normal_strength = normal_strength;
  g_pbr_glob_height_scale = height_scale;
  g_pbr_glob_spec = spec_intensity;
  glUniform1f(glGetUniformLocation(id, "u_pbr_normal_strength"), normal_strength);
  glUniform1f(glGetUniformLocation(id, "u_pbr_height_scale"), height_scale);
  glUniform1f(glGetUniformLocation(id, "u_pbr_uv_tile"), uv_tile);
  glUniform1f(glGetUniformLocation(id, "u_pbr_emissive_str"), emissive_str);
  glUniform1f(glGetUniformLocation(id, "u_pbr_spec_intensity"), spec_intensity);
  // Gpbr-per-texture-materials: the per-material vector, at its IDENTITY — (0.9, 0, 0.04, 1) and
  // (1, 1) ARE the constants the shader used to carry in-line. Pushed here so every program that
  // never sees a PbrDrawBinder (HFRAG, shrub, tie_wind, etie_base) still has a DEFINED value
  // instead of the GL default zero — a zero .w would mirror every normal map's green channel and a
  // zero reflectance would kill dielectric Fresnel.
  glUniform4f(glGetUniformLocation(id, "u_pbr_mat"), 0.9f, 0.f, 0.04f, 1.f);
  glUniform2f(glGetUniformLocation(id, "u_pbr_mat2"), 1.f, 1.f);
  // Grecharged-materials-modern-parity: frame-constant half of the modern stack. Both are the
  // identity by default (exposure 1.0, viz off), so a program that never sees a non-zero u_mm_flags
  // is untouched by them.
  glUniform1f(glGetUniformLocation(id, "u_mm_exposure"), mm_exposure);
  glUniform1i(glGetUniformLocation(id, "u_mm_debug"), mm_debug);
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
