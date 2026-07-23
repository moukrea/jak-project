// Grecharged-pbr-realtime-fusion — DYNAMIC FOLLOW-PROBE implementation.
// See FollowProbe.h for the architecture rationale (owner decision 2026-07-23: delete the baked
// probe grid, replace the PBR env source with one amortized camera-centered cubemap).

#include "FollowProbe.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <vector>

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

#include "game/graphics/pipelines/opengl.h"

FollowProbe& FollowProbe::get() {
  static FollowProbe instance;
  return instance;
}

static int tier_res(int tier) {
  // Face resolution per user-settings tier. Amortized 1 face/frame at every tier, so even the
  // HIGH 128px face is a one-time ~16k-texel CPU eval per frame — trivial. HIGH is the Honor
  // (SD 8 Elite Gen 5) showcase; LOW is the Adreno-618 default.
  switch (tier) {
    case 1: return 32;
    case 2: return 64;
    case 3: return 128;
    default: return 0;
  }
}

void FollowProbe::read_debug_props() {
  if (m_props_read) {
    return;
  }
  m_props_read = true;
#ifdef __ANDROID__
  char v[PROP_VALUE_MAX];
  auto rd = [&](const char* name, int& dst) {
    if (__system_property_get(name, v) > 0 && v[0]) {
      dst = atoi(v);
    }
  };
  rd("debug.opengoal.rt.litboost", m_dbg_litboost);
  rd("debug.opengoal.rt.shadowmul", m_dbg_shadowmul);
  rd("debug.opengoal.rt.tintlit", m_dbg_tintlit);
  rd("debug.opengoal.rt.tintshadow", m_dbg_tintshadow);
  rd("debug.opengoal.rt.greenamp", m_dbg_greenamp);
  rd("debug.opengoal.rt.detail", m_dbg_detail);
  rd("debug.opengoal.rt.detailnorm", m_dbg_detail_norm);
  rd("debug.opengoal.rt.sunboost", m_dbg_sunboost);
  rd("debug.opengoal.rt.followprobe", m_dbg_tier_override);
#endif
  // Desktop headless A/B: the follow-probe tier can be forced from the environment.
  if (const char* e = std::getenv("OG_RT_FOLLOWPROBE")) {
    m_dbg_tier_override = atoi(e);
  }
}

// Standard OpenGL cubemap face convention (matches textureLod(samplerCube, dir)). s,t in [-1,1].
void FollowProbe::face_dir(int face, float s, float t, float out[3]) {
  switch (face) {
    case 0: out[0] = 1.f;  out[1] = -t;   out[2] = -s;  break;  // +X
    case 1: out[0] = -1.f; out[1] = -t;   out[2] = s;   break;  // -X
    case 2: out[0] = s;    out[1] = 1.f;  out[2] = t;   break;  // +Y
    case 3: out[0] = s;    out[1] = -1.f; out[2] = -t;  break;  // -Y
    case 4: out[0] = s;    out[1] = -t;   out[2] = 1.f; break;  // +Z
    default:out[0] = -s;   out[1] = -t;   out[2] = -1.f;break;  // -Z
  }
  float l = std::sqrt(out[0] * out[0] + out[1] * out[1] + out[2] * out[2]);
  if (l > 1e-6f) {
    out[0] /= l;
    out[1] /= l;
    out[2] /= l;
  }
}

// Mirror of the shader rt_ibl_ambient() / the C++ sky_env() used to build u_rt_sh: vertical bands
// ground -> warm horizon -> zenith, plus a soft sun-ward glow lobe. Because zenith/horizon/ground/
// sun_glow are the LIVE per-frame procedural sky (current TOD/mood/sun), the captured cube is
// coherent with the world lighting by construction.
void FollowProbe::eval_env(const float dir[3], const FollowProbeEnv& env, float out[3]) {
  float uu = dir[1];
  float su = uu / 0.55f;
  su = su < 0.f ? 0.f : (su > 1.f ? 1.f : su);
  su = su * su * (3.f - 2.f * su);
  float sd = -uu / 0.45f;
  sd = sd < 0.f ? 0.f : (sd > 1.f ? 1.f : sd);
  sd = sd * sd * (3.f - 2.f * sd);
  float g = dir[0] * env.sun_dir[0] + dir[1] * env.sun_dir[1] + dir[2] * env.sun_dir[2];
  if (g < 0.f) {
    g = 0.f;
  }
  g = g * g;
  g = g * g;  // ^4 sun-ward lobe (matches the SH sky_env)
  for (int i = 0; i < 3; i++) {
    float band = uu >= 0.f ? (env.horizon[i] + (env.zenith[i] - env.horizon[i]) * su)
                           : (env.horizon[i] + (env.ground[i] - env.horizon[i]) * sd);
    float e = band + env.sun_glow[i] * g;
    out[i] = e < 0.f ? 0.f : (e > 1.f ? 1.f : e);
  }
}

void FollowProbe::refresh_face(int face, const FollowProbeEnv& env) {
  const int R = m_res;
  std::vector<unsigned char> buf((size_t)R * R * 4);
  for (int y = 0; y < R; y++) {
    float t = 2.f * ((float)y + 0.5f) / (float)R - 1.f;
    for (int x = 0; x < R; x++) {
      float s = 2.f * ((float)x + 0.5f) / (float)R - 1.f;
      float dir[3];
      face_dir(face, s, t, dir);
      float e[3];
      eval_env(dir, env, e);
      size_t o = ((size_t)y * R + x) * 4;
      buf[o + 0] = (unsigned char)(e[0] * 255.f + 0.5f);
      buf[o + 1] = (unsigned char)(e[1] * 255.f + 0.5f);
      buf[o + 2] = (unsigned char)(e[2] * 255.f + 0.5f);
      buf[o + 3] = 255;
    }
  }
  glBindTexture(GL_TEXTURE_CUBE_MAP, m_cube);
  glTexSubImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + face, 0, 0, 0, R, R, GL_RGBA,
                  GL_UNSIGNED_BYTE, buf.data());
}

void FollowProbe::fill_all_faces(const FollowProbeEnv& env) {
  for (int f = 0; f < 6; f++) {
    refresh_face(f, env);
  }
}

void FollowProbe::ensure_gl(int tier) {
  // Dummy 1x1 black textures for the OFF path and the dead SH-volume samplers (driver
  // completeness on strict GLES).
  if (!m_dummy_cube) {
    const unsigned char black[4] = {0, 0, 0, 255};
    glGenTextures(1, &m_dummy_cube);
    glBindTexture(GL_TEXTURE_CUBE_MAP, m_dummy_cube);
    for (int f = 0; f < 6; f++) {
      glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + f, 0, GL_RGBA8, 1, 1, 0, GL_RGBA,
                   GL_UNSIGNED_BYTE, black);
    }
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
  }
  if (!m_dummy_3d) {
    const unsigned char black[4] = {0, 0, 0, 0};
    glGenTextures(1, &m_dummy_3d);
    glBindTexture(GL_TEXTURE_3D, m_dummy_3d);
    glTexImage3D(GL_TEXTURE_3D, 0, GL_RGBA8, 1, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, black);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
  }
  int want = tier_res(tier);
  if (want == 0) {
    return;  // OFF tier: no live cube
  }
  if (m_cube && m_tier == tier && m_res == want) {
    return;  // already built for this tier
  }
  // (Re)build the live cube at the tier resolution with a full mip chain.
  if (m_cube) {
    glDeleteTextures(1, &m_cube);
    m_cube = 0;
  }
  m_res = want;
  m_tier = tier;
  glGenTextures(1, &m_cube);
  glBindTexture(GL_TEXTURE_CUBE_MAP, m_cube);
  std::vector<unsigned char> zero((size_t)want * want * 4, 0);
  for (int f = 0; f < 6; f++) {
    glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + f, 0, GL_RGBA8, want, want, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, zero.data());
  }
  glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
  glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
  m_next_face = 0;
  m_last_capture_frame = ~0ull;  // force the initial full fill in update_and_bind
}

void FollowProbe::update_and_bind(uint32_t program,
                                  const float cam_pos[3],
                                  uint64_t frame_idx,
                                  const FollowProbeEnv& env,
                                  int tier) {
  read_debug_props();
  if (m_dbg_tier_override >= 0) {
    tier = m_dbg_tier_override;
  }
  tier = tier < 0 ? 0 : (tier > 3 ? 3 : tier);

  auto loc = [&](const char* n) { return glGetUniformLocation(program, n); };

  ensure_gl(tier);

  // (1) RE-HOME the baked-modulation amplitude uniforms — ALWAYS. Their only uploader was the
  // deleted LightProbeGrid::bind_and_upload; without this the owner-validated baked-modulation
  // world look regresses to GL-default 0 (black shadows, no lit boost). Exact defaults preserved.
  glUniform1f(loc("u_rt_lit_boost"), (m_dbg_litboost > 0) ? (float)m_dbg_litboost / 100.f : 1.15f);
  glUniform1f(loc("u_rt_shadow_mul"), (m_dbg_shadowmul > 0) ? (float)m_dbg_shadowmul / 100.f : 0.65f);
  glUniform1f(loc("u_rt_tint_lit"), (m_dbg_tintlit >= 0) ? (float)m_dbg_tintlit / 100.f : 0.12f);
  glUniform1f(loc("u_rt_tint_shadow"), (m_dbg_tintshadow >= 0) ? (float)m_dbg_tintshadow / 100.f : 0.12f);
  glUniform1f(loc("u_rt_green_amp"), (m_dbg_greenamp >= 0) ? (float)m_dbg_greenamp / 100.f : 0.60f);
  glUniform1i(loc("u_rt_detail"), (m_dbg_detail >= 0) ? m_dbg_detail : 1);
  glUniform1f(loc("u_rt_detail_norm"), (m_dbg_detail_norm > 0) ? (float)m_dbg_detail_norm / 100.f : 1.0f);
  glUniform1f(loc("u_rt_sun_boost"), (m_dbg_sunboost >= 0) ? (float)m_dbg_sunboost / 100.f : 0.25f);

  // (2) The SH-volume grid is DELETED — force its world-projection OFF and bind dummies so the
  // dead sampler3D declarations stay complete on strict GLES drivers.
  glUniform1i(loc("u_rt_probe_on"), 0);
  for (int b = 0; b < 4; b++) {
    glActiveTexture(GL_TEXTURE4 + b);
    glBindTexture(GL_TEXTURE_3D, m_dummy_3d);
  }
  glUniform1i(loc("u_rt_probe_dc"), 4);
  glUniform1i(loc("u_rt_probe_l1a"), 5);
  glUniform1i(loc("u_rt_probe_l1b"), 6);
  glUniform1i(loc("u_rt_probe_l1c"), 7);

  // (3) The DYNAMIC FOLLOW-PROBE env cube on unit 3 (u_rt_probe_cube).
  m_cam[0] = cam_pos[0];
  m_cam[1] = cam_pos[1];
  m_cam[2] = cam_pos[2];  // probe center follows the camera (owner: near-focus is the design point)
  glActiveTexture(GL_TEXTURE3);
  if (tier <= 0 || !m_cube) {
    // OFF tier => corrected procedural IBL (rt_ibl_ambient) in the shader; bind black dummy so
    // the reflection branch is disabled cleanly.
    glBindTexture(GL_TEXTURE_CUBE_MAP, m_dummy_cube);
    glUniform1i(loc("u_rt_probe_cube"), 3);
    glUniform1i(loc("u_rt_probe_reflections"), 0);
    glUniform1f(loc("u_rt_probe_strength"), 0.f);
  } else {
    // Amortize the capture at 1 face/frame (this fn runs ~5x/frame => guard on frame_idx). On a
    // freshly (re)built cube fill all 6 faces once so it is valid immediately (no black flash).
    if (m_last_capture_frame == ~0ull) {
      fill_all_faces(env);
      glBindTexture(GL_TEXTURE_CUBE_MAP, m_cube);
      glGenerateMipmap(GL_TEXTURE_CUBE_MAP);  // cheap box prefilter => roughness mip chain
      m_last_capture_frame = frame_idx;
      m_next_face = 0;
    } else if (frame_idx != m_last_capture_frame) {
      m_last_capture_frame = frame_idx;
      refresh_face(m_next_face, env);
      m_next_face = (m_next_face + 1) % 6;
      glBindTexture(GL_TEXTURE_CUBE_MAP, m_cube);
      glGenerateMipmap(GL_TEXTURE_CUBE_MAP);
    }
    glActiveTexture(GL_TEXTURE3);
    glBindTexture(GL_TEXTURE_CUBE_MAP, m_cube);
    glUniform1i(loc("u_rt_probe_cube"), 3);
    glUniform1i(loc("u_rt_probe_reflections"), 1);
    glUniform1f(loc("u_rt_probe_strength"), 1.0f);
  }
  glActiveTexture(GL_TEXTURE0);
}
