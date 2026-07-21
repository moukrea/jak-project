#pragma once
// Grecharged-lightprobes: RUNTIME consumer of the baked LOCAL probe grid (village1.probes).
//
// Owns the loaded probe grid + its GL resources and drives the per-frame update:
//   - loads <level>.probes from the external assets dir (clone of the GrassRenderer precomputed load),
//   - each frame blends the 8 baked TOD keyframes -> the current time-of-day using the SAME itimes
//     weights the scene uses, then uploads a dense RGBA8 3D texture per SH band (hardware trilinear),
//   - selects the reflection cube of the anchor nearest the camera and uploads it (samplerCube),
//   - binds the textures + grid uniforms so the 4 world shaders sample LOCAL ambient + reflections.
//
// Encoding: SH coeffs are affine-encoded into unorm8 (stored = coeff/(2*SCALE) + 0.5), which preserves
// trilinear interpolation between valid cells exactly; validity (0/1) rides in the DC texture's alpha
// so the shader can smoothly fall back to the global analytic SH at the grid boundary. Default OFF.

#include <string>

#include "ProbeBakeCore.h"

#include "common/util/FileUtil.h"

#include "third-party/glad/include/glad/glad.h"

class LightProbeGrid {
 public:
  static LightProbeGrid& get();

  // Load <level>.probes for this level if not already loaded (cheap no-op if same level). Safe to
  // call every level-load. Returns true if a grid is resident.
  bool ensure_loaded(const std::string& level_name);

  // Once per frame: blend the 8 TOD keyframes with `itimes` (16 s32 words, as in interp_time_of_day)
  // to the current TOD and refresh the GL textures if needed; pick the nearest reflection cube to the
  // camera (world position, game units). `frame_idx` throttles to one update per frame.
  void update_for_frame(const s32 itimes[4][4], const float cam_pos_gu[3], u64 frame_idx);

  // Bind textures to their units and set the sampler + grid + tuning uniforms on `program`.
  // No-ops (uploads u_rt_probe_on=0) when nothing is resident or the feature is off.
  void bind_and_upload(GLuint program);

  bool loaded() const { return m_loaded; }
  const probe_bake::ProbeGrid& grid() const { return m_grid; }

  // affine unorm8 encode: DC (coeff0, positive, up to ~5) = coeff/RANGE; L1 (signed) = coeff/RANGE+0.5.
  // Shader decodes with the SAME RANGE. Affine => trilinear interpolation between valid cells is exact.
  static constexpr float SH_RANGE = 8.0f;

 private:
  void alloc_textures();
  void rebuild_sh_textures();   // from m_cur_sh (current TOD): all 4 bands at once
  void rebuild_sh_band(int b);  // one band only (amortized TOD upload: 1/4 of the hitch per frame)
  void rebuild_cube();          // from the selected anchor

  bool m_loaded = false;
  bool m_load_failed_level = false;
  std::string m_level;
  probe_bake::ProbeGrid m_grid;

  // current-TOD SH per baked cell (coeff0..3 = DC + L1), RGB. Rebuilt on TOD change.
  std::vector<float> m_cur_sh;  // [cell][4 coeffs][3] laid out flat
  s32 m_last_itimes[4][4] = {};
  bool m_have_last_itimes = false;
  u64 m_last_frame = (u64)-1;
  u64 m_last_sh_frame = (u64)-1;  // last frame the dense SH textures were rebuilt (rate-limit)
  int m_pending_band = -1;        // next SH band to upload (amortized rebuild); -1 = none pending

  // effective feature state for this frame (gfx flags + optional device prop overrides for A/B).
  bool m_eff_on = false, m_eff_refl = false;
  int m_eff_qual = 1;
  float m_eff_str = 1.0f;
  // REOPEN 2026-07-21 baked-detail re-injection A/B overrides (device props, -1 = unset =>
  // shader defaults: layer ON, ratio recentering 1.0). See bind_and_upload().
  int m_dbg_detail = -1;       // debug.opengoal.rt.detail (int: 0 off / 1 on)
  int m_dbg_detail_norm = -1;  // debug.opengoal.rt.detailnorm (int percent)
  int m_dbg_sunboost = -1;     // debug.opengoal.rt.sunboost (int percent; default 25 => 0.25)
  void refresh_effective_flags();

  // GL
  bool m_gl_ready = false;
  GLuint m_tex_sh[4] = {0, 0, 0, 0};  // 3D RGBA8: [0]=DC.rgb+valid.a, [1..3]=L1 coeffs
  GLuint m_tex_cube = 0;              // GL_TEXTURE_CUBE_MAP, current nearest anchor
  GLuint m_dummy3d = 0, m_dummy_cube = 0;
  int m_sel_anchor = -1;
  s32 m_cube_itimes_tag = 0;

  std::vector<u8> m_upload;  // scratch for a 3D texture upload
};
