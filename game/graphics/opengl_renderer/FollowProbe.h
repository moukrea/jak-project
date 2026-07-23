#pragma once

// Grecharged-pbr-realtime-fusion — DYNAMIC FOLLOW-PROBE (owner architecture decision 2026-07-23).
//
// This replaces the DELETED baked LightProbeGrid as the environment source for the PBR ambient
// specular / reflection term. The owner's decision: the 39k baked probe grid was a perf sinkhole;
// for PBR "c'est ce qui est PROCHE de nous qui compte". So instead of a static baked grid we keep
// ONE low-res cubemap centered on the camera, re-rendered from the LIVE world lighting (current
// TOD / mood / sun), amortized 1 face/frame, prefiltered into a roughness mip chain, and bound to
// the exact same shader inputs the old grid fed (u_rt_probe_cube / _on / _reflections / _strength).
// Only the ENV SOURCE changes — the split-sum shader path consumes it unchanged (tfrag3.frag:767).
//
// The class ALSO re-homes the baked-modulation amplitude uniforms (u_rt_lit_boost, u_rt_shadow_mul,
// u_rt_tint_lit, u_rt_tint_shadow, u_rt_green_amp, u_rt_detail, u_rt_detail_norm, u_rt_sun_boost)
// whose ONLY uploader was LightProbeGrid::bind_and_upload — deleting the grid orphaned them, which
// would regress the owner-validated baked-modulation world look to GL-default 0. They are set here
// unconditionally on every draw, exactly as before.
//
// Tiers are USER SETTINGS (owner: same features mobile+PC), read from
// Gfx::g_global_settings.recharged_follow_probe:
//   0 = OFF  -> no cube capture; shader falls back to the corrected procedural IBL (rt_ibl_ambient).
//              This is the owner's "lowest tier = corrected procedural IBL (no capture)".
//   1 = LOW  -> 32px faces   2 = MID -> 64px faces   3 = HIGH -> 128px faces.
// All tiers amortize the capture at 1 face/frame (full refresh every 6 frames).

#include <cstdint>

// The live environment inputs, mirrored from first_tfrag_draw_setup's per-frame procedural sky
// (env_zenith/horizon/ground + sun_glow + surface->sun dir). All linear RGB, matching the shader
// rt_ibl_ambient() bands. Because these carry the current TOD/mood/sun, the captured cube is
// "re-rendered from the live world" by construction (owner requirement).
struct FollowProbeEnv {
  float zenith[3];
  float horizon[3];
  float ground[3];
  float sun_glow[3];
  float sun_dir[3];  // surface->sun, normalized (the visible sky-sun dome direction)
};

class FollowProbe {
 public:
  static FollowProbe& get();

  // Called once per first_tfrag_draw_setup (i.e. per world-shader program, ~5x/frame). It:
  //   (1) sets the re-homed baked-modulation amplitude uniforms (ALWAYS — regression fix),
  //   (2) neutralizes the removed SH-volume grid (u_rt_probe_on=0 + dummy 3D binds so strict
  //       GLES drivers keep the declared samplers complete),
  //   (3) when tier>0, amortizes the live camera cubemap capture (once per frame_idx) and binds
  //       it to u_rt_probe_cube (unit 3) with _reflections=1; when tier==0 binds a black dummy
  //       cube with _reflections=0 (procedural-IBL fallback).
  // `program` is the active GL program; glUniform on a missing location is a safe no-op, so this
  // is valid for every world ShaderId. `cam_pos` is the camera world position (probe center).
  void update_and_bind(uint32_t program,
                       const float cam_pos[3],
                       uint64_t frame_idx,
                       const FollowProbeEnv& env,
                       int tier);

 private:
  FollowProbe() = default;
  void ensure_gl(int tier);
  void refresh_face(int face, const FollowProbeEnv& env);
  void fill_all_faces(const FollowProbeEnv& env);
  static void face_dir(int face, float s, float t, float out[3]);
  static void eval_env(const float dir[3], const FollowProbeEnv& env, float out[3]);
  void read_debug_props();

  unsigned int m_cube = 0;        // live prefiltered env cubemap (GL_TEXTURE_CUBE_MAP, mipmapped)
  unsigned int m_dummy_cube = 0;  // 1x1 black cube (OFF path / driver completeness)
  unsigned int m_dummy_3d = 0;    // 1x1 black 3D (dead SH-volume sampler completeness)
  int m_res = 0;                  // current cube face resolution (0 => not created)
  int m_tier = -1;                // tier the current m_cube was built for
  int m_next_face = 0;            // amortized capture cursor
  uint64_t m_last_capture_frame = ~0ull;
  float m_cam[3] = {0.f, 0.f, 0.f};
  bool m_props_read = false;

  // Re-homed baked-modulation debug tunables (int percent, -1 = unset => owner-plan default).
  int m_dbg_litboost = -1;
  int m_dbg_shadowmul = -1;
  int m_dbg_tintlit = -1;
  int m_dbg_tintshadow = -1;
  int m_dbg_greenamp = -1;
  int m_dbg_detail = -1;
  int m_dbg_detail_norm = -1;
  int m_dbg_sunboost = -1;
  int m_dbg_tier_override = -1;  // debug.opengoal.rt.followprobe forces the tier (headless A/B)
};
