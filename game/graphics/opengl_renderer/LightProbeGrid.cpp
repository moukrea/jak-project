// Grecharged-lightprobes: runtime consumer of the baked LOCAL probe grid. See LightProbeGrid.h.

#include "LightProbeGrid.h"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

#include "common/log/log.h"

#include "game/graphics/gfx.h"

namespace {
constexpr int CUBE_FACE = probe_bake::PRB_CUBE_FACE;  // 8
constexpr int CUBE_NT = 6 * CUBE_FACE * CUBE_FACE;

// unpack the 8x4 per-(slot,channel) TOD weights exactly like interp_time_of_day().
void unpack_tod_weights(const s32 itimes[4][4], u16 w[8][4]) {
  for (int component = 0; component < 8; component++) {
    int quad_idx = component / 2;
    int word_off = (component % 2) * 2;
    for (int channel = 0; channel < 4; channel++) {
      int word = word_off + (channel / 2);
      int hw_off = channel % 2;
      u32 word_val = (u32)itimes[quad_idx][word];
      u32 hw_val = hw_off ? (word_val >> 16) : word_val;
      w[component][channel] = (u16)(hw_val & 0xff);
    }
  }
}
}  // namespace

LightProbeGrid& LightProbeGrid::get() {
  static LightProbeGrid inst;
  return inst;
}

void LightProbeGrid::refresh_effective_flags() {
#ifdef OG_FEAT_PBR
  const auto& gs = Gfx::g_global_settings;
  // OWNER FINAL ARCHITECTURE (2026-07-21): the probes STOP projecting onto world geometry by
  // default — the world look is BAKED-MODULATION (in the world shaders). The grid is kept as a
  // RESOURCE for future PBR/water; its world projection is the "BAKED AMBIENT" curiosity toggle
  // (recharged_rt_probe_enable, gfx.h default false, menu row default OFF). The Android debug
  // prop below still overrides for headless A/B captures.
  m_eff_on = gs.recharged_rt_probe_enable;
  m_eff_refl = gs.recharged_rt_probe_reflections;
  m_eff_qual = gs.recharged_rt_probe_quality;
  m_eff_str = gs.recharged_rt_probe_strength;
#else
  m_eff_on = false;
  m_eff_refl = false;
  m_eff_qual = 1;
  m_eff_str = 1.0f;
#endif
#ifdef __ANDROID__
  // device A/B overrides (mirror the directional-ambient debug.opengoal.rt.* props).
  char v[PROP_VALUE_MAX];
  if (__system_property_get("debug.opengoal.rt.probe", v) > 0 && v[0])
    m_eff_on = atoi(v) != 0;
  if (__system_property_get("debug.opengoal.rt.probrefl", v) > 0 && v[0])
    m_eff_refl = atoi(v) != 0;
  if (__system_property_get("debug.opengoal.rt.probqual", v) > 0 && v[0])
    m_eff_qual = atoi(v);
  if (__system_property_get("debug.opengoal.rt.probstr", v) > 0 && v[0])
    m_eff_str = (float)atof(v);
  // REOPEN baked-detail layer A/B (default ON / norm 1.0 when the prop is unset).
  if (__system_property_get("debug.opengoal.rt.detail", v) > 0 && v[0])
    m_dbg_detail = atoi(v);
  if (__system_property_get("debug.opengoal.rt.detailnorm", v) > 0 && v[0])
    m_dbg_detail_norm = atoi(v);
  if (__system_property_get("debug.opengoal.rt.sunboost", v) > 0 && v[0])
    m_dbg_sunboost = atoi(v);
  // OWNER FINAL (baked-modulation) amplitude tunables, int percent (litboost 115 = x1.15) —
  // live-dialable on device without a rebuild.
  if (__system_property_get("debug.opengoal.rt.litboost", v) > 0 && v[0])
    m_dbg_litboost = atoi(v);
  if (__system_property_get("debug.opengoal.rt.shadowmul", v) > 0 && v[0])
    m_dbg_shadowmul = atoi(v);
  if (__system_property_get("debug.opengoal.rt.tintlit", v) > 0 && v[0])
    m_dbg_tintlit = atoi(v);
  if (__system_property_get("debug.opengoal.rt.tintshadow", v) > 0 && v[0])
    m_dbg_tintshadow = atoi(v);
  if (__system_property_get("debug.opengoal.rt.greenamp", v) > 0 && v[0])
    m_dbg_greenamp = atoi(v);
#endif
}

bool LightProbeGrid::ensure_loaded(const std::string& level_name) {
  if (m_loaded && m_level == level_name)
    return true;
  if (m_load_failed_level && m_level == level_name)
    return false;  // don't retry a known-missing level every frame

  // OWNER FINAL: keep the asset load LAZY — with no consumer active (world projection off AND
  // reflections off, the shipped default) skip the multi-MB .probes parse entirely; remember
  // the level so flipping a consumer on later loads it from update_for_frame.
  m_pending_level = level_name;
  refresh_effective_flags();
  if (!m_eff_on && !m_eff_refl)
    return false;

  // resolve <level>.probes: external assets/fr3 dir, custom (package) dir wins if present.
  std::string path =
      (file_util::get_fr3_dir(GameVersion::Jak1) / (level_name + ".probes")).string();
  if (auto custom = file_util::get_custom_fr3_dir()) {
    std::string cp = (*custom / (level_name + ".probes")).string();
    if (file_util::file_exists(cp))
      path = cp;
  }

  probe_bake::ProbeGrid g;
  if (!probe_bake::load_probes(g, path)) {
    m_level = level_name;
    m_load_failed_level = true;
    return false;
  }
  if (std::string(g.level_name) != level_name) {
    lg::warn("[lightprobe] level mismatch in '{}' ({} != {})", path, g.level_name, level_name);
    m_level = level_name;
    m_load_failed_level = true;
    return false;
  }

  m_grid = std::move(g);
  m_level = level_name;
  m_loaded = true;
  m_load_failed_level = false;
  m_have_last_itimes = false;
  m_sel_anchor = -1;
  m_cur_sh.assign((size_t)m_grid.cells.size() * 4 * 3, 0.f);
  m_gl_ready = false;  // (re)alloc on next update on the GL thread
  lg::info("[lightprobe] loaded '{}': {} probes ({} interior) {} anchors, grid {}x{}x{}", path,
           m_grid.n_valid, m_grid.n_interior, m_grid.n_refl, m_grid.dims[0], m_grid.dims[1],
           m_grid.dims[2]);
  return true;
}

void LightProbeGrid::alloc_textures() {
  if (m_gl_ready)
    return;
  const s32 DX = m_grid.dims[0], DY = m_grid.dims[1], DZ = m_grid.dims[2];

  // dummies (so unbound sampler units are always valid on strict drivers).
  if (!m_dummy3d) {
    u8 zero4[4] = {128, 128, 128, 0};
    glGenTextures(1, &m_dummy3d);
    glBindTexture(GL_TEXTURE_3D, m_dummy3d);
    glTexImage3D(GL_TEXTURE_3D, 0, GL_RGBA8, 1, 1, 1, 0, GL_RGBA, GL_UNSIGNED_BYTE, zero4);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
  }
  if (!m_dummy_cube) {
    u8 z3[3] = {40, 40, 48};
    glGenTextures(1, &m_dummy_cube);
    glBindTexture(GL_TEXTURE_CUBE_MAP, m_dummy_cube);
    for (int f = 0; f < 6; f++)
      glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + f, 0, GL_RGB8, 1, 1, 0, GL_RGB,
                   GL_UNSIGNED_BYTE, z3);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  }

  for (int b = 0; b < 4; b++) {
    if (!m_tex_sh[b])
      glGenTextures(1, &m_tex_sh[b]);
    glBindTexture(GL_TEXTURE_3D, m_tex_sh[b]);
    glTexImage3D(GL_TEXTURE_3D, 0, GL_RGBA8, DX, DY, DZ, 0, GL_RGBA, GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_3D, GL_TEXTURE_WRAP_R, GL_CLAMP_TO_EDGE);
  }
  if (!m_tex_cube) {
    glGenTextures(1, &m_tex_cube);
    glBindTexture(GL_TEXTURE_CUBE_MAP, m_tex_cube);
    u8 z3[3] = {40, 40, 48};
    for (int f = 0; f < 6; f++)
      glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + f, 0, GL_RGB8, CUBE_FACE, CUBE_FACE, 0, GL_RGB,
                   GL_UNSIGNED_BYTE, nullptr);
    (void)z3;
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_CUBE_MAP, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  }

  if (glGetError() != GL_NO_ERROR) {
    lg::warn("[lightprobe] GL texture alloc error; disabling probe grid");
    m_loaded = false;
    return;
  }
  m_gl_ready = true;
}

void LightProbeGrid::rebuild_sh_textures() {
  for (int b = 0; b < 4; b++)
    rebuild_sh_band(b);
}

void LightProbeGrid::rebuild_sh_band(int b) {
  const s32 DX = m_grid.dims[0], DY = m_grid.dims[1], DZ = m_grid.dims[2];
  const size_t ntex = (size_t)DX * DY * DZ * 4;
  const float inv = 1.0f / LightProbeGrid::SH_RANGE;
  auto enc = [](float v) -> u8 {
    int i = (int)std::lround(v * 255.0f);
    return (u8)(i < 0 ? 0 : (i > 255 ? 255 : i));
  };
  {
    m_upload.assign(ntex, 0);
    // default all texels to invalid: DC neutral 0, others 0.5-bias; validity(a)=0.
    for (size_t t = 0; t < (size_t)DX * DY * DZ; t++) {
      u8* d = &m_upload[t * 4];
      if (b == 0) {
        d[0] = d[1] = d[2] = 0;
        d[3] = 0;  // validity
      } else {
        d[0] = d[1] = d[2] = 128;  // encode(0) for signed L1
        d[3] = 0;
      }
    }
    for (size_t ci = 0; ci < m_grid.cells.size(); ci++) {
      const auto& c = m_grid.cells[ci];
      size_t idx = (((size_t)c.iz * DY) + c.iy) * DX + c.ix;
      if (idx >= (size_t)DX * DY * DZ)
        continue;
      u8* d = &m_upload[idx * 4];
      const float* sh = &m_cur_sh[ci * 12 + (size_t)b * 3];
      if (b == 0) {
        d[0] = enc(sh[0] * inv);
        d[1] = enc(sh[1] * inv);
        d[2] = enc(sh[2] * inv);
        d[3] = 255;  // validity/coverage
      } else {
        d[0] = enc(sh[0] * inv + 0.5f);
        d[1] = enc(sh[1] * inv + 0.5f);
        d[2] = enc(sh[2] * inv + 0.5f);
        // PLAYTEST#1 #1 (containment): the L1a alpha carries the INTERIOR MASK (255 indoors / 0
        // outdoors) so the fragment shader can detect indoor fragments and SNAP to the containing
        // cell instead of letting the smooth trilinear bleed exterior light through the walls.
        // Bands l1b/l1c keep 255 (unused alpha). Invalid cells stay 0 (set in the default fill).
        d[3] = (b == 1) ? (c.interior ? 255 : 0) : 255;
      }
    }
    glBindTexture(GL_TEXTURE_3D, m_tex_sh[b]);
    glTexSubImage3D(GL_TEXTURE_3D, 0, 0, 0, 0, DX, DY, DZ, GL_RGBA, GL_UNSIGNED_BYTE,
                    m_upload.data());
  }
}

void LightProbeGrid::rebuild_cube() {
  if (m_sel_anchor < 0 || m_sel_anchor >= (int)m_grid.refl.size())
    return;
  const auto& rp = m_grid.refl[m_sel_anchor];
  if (rp.cube.size() != (size_t)probe_bake::PRB_NUM_TOD * CUBE_NT * 3)
    return;
  // TOD-blend the anchor cube using the current weights (m_cur_sh already reflects the TOD, but the
  // cube is stored per-slot; recompute weights from m_last_itimes).
  u16 w[8][4];
  unpack_tod_weights(m_last_itimes, w);
  std::vector<u8> face(CUBE_FACE * CUBE_FACE * 3);
  glBindTexture(GL_TEXTURE_CUBE_MAP, m_tex_cube);
  for (int f = 0; f < 6; f++) {
    for (int tx = 0; tx < CUBE_FACE * CUBE_FACE; tx++) {
      int texel = f * CUBE_FACE * CUBE_FACE + tx;
      for (int ch = 0; ch < 3; ch++) {
        u32 acc = 0;
        for (int slot = 0; slot < 8; slot++) {
          const u8* cslot = &rp.cube[((size_t)slot * CUBE_NT + texel) * 3];
          acc += (u32)w[slot][ch] * cslot[ch];
        }
        acc >>= 6;
        face[tx * 3 + ch] = (u8)(acc > 255 ? 255 : acc);
      }
    }
    glTexImage2D(GL_TEXTURE_CUBE_MAP_POSITIVE_X + f, 0, GL_RGB8, CUBE_FACE, CUBE_FACE, 0, GL_RGB,
                 GL_UNSIGNED_BYTE, face.data());
  }
  glGenerateMipmap(GL_TEXTURE_CUBE_MAP);
}

void LightProbeGrid::update_for_frame(const s32 itimes[4][4],
                                      const float cam_pos_gu[3],
                                      u64 frame_idx) {
  if (frame_idx == m_last_frame)
    return;
  m_last_frame = frame_idx;
  refresh_effective_flags();
  // OWNER FINAL: a consumer (world-projection curiosity toggle or reflections) flipped on after
  // the lazy skip at level load — do the real .probes load now.
  if ((m_eff_on || m_eff_refl) && !m_loaded && !m_pending_level.empty())
    ensure_loaded(m_pending_level);
  if (!m_loaded)
    return;
  // PLAYTEST#1b #1 (perf/temporal stability) + OWNER FINAL: with NO consumer active (world
  // projection off AND reflections off — the shipped default), do ZERO per-frame probe work and
  // SKIP the GPU upload entirely (alloc_textures/rebuild_* below never run => no 3D textures, no
  // cubemap on the GPU). OFF must cost nothing, not just render identically. Re-enabling picks up
  // on the next frame (lazy load above + rebuild triggers immediately).
  if (!m_eff_on && !m_eff_refl) {
    m_pending_band = -1;
    return;
  }

  alloc_textures();
  if (!m_gl_ready)
    return;

  // did the TOD weights change ENOUGH? The day cycle moves slowly; tiny per-frame jitter in the mood
  // itimes must NOT trigger a full dense-3D-texture rebuild every frame — that upload is a
  // resolution-INDEPENDENT fixed cost that tanks the framerate (and defeats render scaling). Use a
  // small threshold, and rate-limit the rebuild to at most once per REBUILD_INTERVAL frames (still
  // visually smooth for a multi-minute cycle).
  const u64 REBUILD_INTERVAL = 20;
  long diff = 0;
  for (int a = 0; a < 4; a++)
    for (int b = 0; b < 4; b++)
      diff += std::labs((long)itimes[a][b] - (long)m_last_itimes[a][b]);
  bool tod_changed = !m_have_last_itimes || diff > 8;
  bool do_rebuild =
      tod_changed && (m_last_sh_frame == (u64)-1 || frame_idx - m_last_sh_frame >= REBUILD_INTERVAL);

  if (do_rebuild) {
    m_last_sh_frame = frame_idx;
    std::memcpy(m_last_itimes, itimes, sizeof(m_last_itimes));
    m_have_last_itimes = true;
    u16 w[8][4];
    unpack_tod_weights(itimes, w);
    // blend the 8 baked keyframes -> current TOD, per channel (matches interp_time_of_day math).
    for (size_t ci = 0; ci < m_grid.cells.size(); ci++) {
      const auto& c = m_grid.cells[ci];
      for (int coeff = 0; coeff < 4; coeff++) {
        for (int ch = 0; ch < 3; ch++) {
          float acc = 0.f;
          for (int slot = 0; slot < 8; slot++)
            acc += (float)w[slot][ch] * c.sh[slot][coeff][ch];
          m_cur_sh[ci * 12 + coeff * 3 + ch] = acc * (1.0f / 64.0f);
        }
      }
    }
    // PLAYTEST#1b #1: AMORTIZED upload — one SH band per frame over the next 4 frames instead of a
    // single 4-band (~6.4MB) glTexSubImage3D burst. The burst was a periodic GL-thread hitch (every
    // REBUILD_INTERVAL frames while the TOD advances) => micro-stutter the owner reads as flicker on
    // movement. m_cur_sh stays fixed while the 4 bands drain, so the bands are mutually consistent;
    // REBUILD_INTERVAL(20) >> 4 so a drain never overlaps the next rebuild.
    m_pending_band = 0;
  }
  if (m_pending_band >= 0) {
    rebuild_sh_band(m_pending_band);
    if (++m_pending_band >= 4)
      m_pending_band = -1;
  }

  // nearest reflection anchor to the camera.
  int best = -1;
  float bestd = 1e30f;
  for (size_t i = 0; i < m_grid.refl.size(); i++) {
    const auto& r = m_grid.refl[i];
    float dx = r.pos_gu[0] - cam_pos_gu[0], dy = r.pos_gu[1] - cam_pos_gu[1],
          dz = r.pos_gu[2] - cam_pos_gu[2];
    float d = dx * dx + dy * dy + dz * dz;
    if (d < bestd) {
      bestd = d;
      best = (int)i;
    }
  }
  if (best != m_sel_anchor || do_rebuild) {
    m_sel_anchor = best;
    rebuild_cube();
  }
}

void LightProbeGrid::bind_and_upload(GLuint program) {
  auto loc = [&](const char* n) { return glGetUniformLocation(program, n); };
  bool feat_refl = m_eff_refl;
  int feat_quality = m_eff_qual;
  (void)feat_quality;  // OWNER #3: u_rt_probe_quality uniform folded away; m_eff_qual reserved for PBR-fusion.
  float feat_strength = m_eff_str;
  bool on = m_loaded && m_gl_ready && m_eff_on;
  glUniform1i(loc("u_rt_probe_on"), on ? 1 : 0);
  // OWNER FINAL ARCHITECTURE (baked-modulation) amplitude tunables — the DEFAULT world path's
  // uniforms, needed whenever realtime lighting is on, INDEPENDENT of the probe world-projection
  // state, so they are set BEFORE the probe early-out below. Percent props (-1 = unset =>
  // owner-plan defaults: lit x1.15 warm 0.12, shadow x0.65 cool 0.12, green amplitude 0.60).
  glUniform1f(loc("u_rt_lit_boost"),
              (m_dbg_litboost > 0) ? (float)m_dbg_litboost / 100.0f : 1.15f);
  glUniform1f(loc("u_rt_shadow_mul"),
              (m_dbg_shadowmul > 0) ? (float)m_dbg_shadowmul / 100.0f : 0.65f);
  glUniform1f(loc("u_rt_tint_lit"), (m_dbg_tintlit >= 0) ? (float)m_dbg_tintlit / 100.0f : 0.12f);
  glUniform1f(loc("u_rt_tint_shadow"),
              (m_dbg_tintshadow >= 0) ? (float)m_dbg_tintshadow / 100.0f : 0.12f);
  glUniform1f(loc("u_rt_green_amp"),
              (m_dbg_greenamp >= 0) ? (float)m_dbg_greenamp / 100.0f : 0.60f);
  if (!on) {
    // still bind dummies so the declared samplers are valid on strict drivers.
    for (int b = 0; b < 4; b++) {
      glActiveTexture(GL_TEXTURE4 + b);
      glBindTexture(GL_TEXTURE_3D, m_dummy3d ? m_dummy3d : 0);
    }
    glActiveTexture(GL_TEXTURE3);
    glBindTexture(GL_TEXTURE_CUBE_MAP, m_dummy_cube ? m_dummy_cube : 0);
    glUniform1i(loc("u_rt_probe_dc"), 4);
    glUniform1i(loc("u_rt_probe_l1a"), 5);
    glUniform1i(loc("u_rt_probe_l1b"), 6);
    glUniform1i(loc("u_rt_probe_l1c"), 7);
    glUniform1i(loc("u_rt_probe_cube"), 3);
    glActiveTexture(GL_TEXTURE0);
    return;
  }

  glUniform1i(loc("u_rt_probe_reflections"), feat_refl ? 1 : 0);
  glUniform1f(loc("u_rt_probe_strength"), feat_strength);
  // REOPEN baked-detail layer: ON by default (the re-injection fixes the owner's
  // flat-realtime verdict); prop-gated A/B + ratio recentering without a rebuild.
  glUniform1i(loc("u_rt_detail"), (m_dbg_detail >= 0) ? m_dbg_detail : 1);
  glUniform1f(loc("u_rt_detail_norm"),
              (m_dbg_detail_norm > 0) ? (float)m_dbg_detail_norm / 100.0f : 1.0f);
  // REOPEN #3 modest dynamic-sun boost over the shadowed-baked composite (percent prop).
  glUniform1f(loc("u_rt_sun_boost"),
              (m_dbg_sunboost >= 0) ? (float)m_dbg_sunboost / 100.0f : 0.25f);
  glUniform3f(loc("u_rt_probe_origin"), m_grid.origin_gu[0], m_grid.origin_gu[1],
              m_grid.origin_gu[2]);
  glUniform1f(loc("u_rt_probe_inv_cell"), 1.0f / m_grid.cell_gu);
  glUniform3f(loc("u_rt_probe_dims"), (float)m_grid.dims[0], (float)m_grid.dims[1],
              (float)m_grid.dims[2]);
  glUniform1f(loc("u_rt_probe_range"), LightProbeGrid::SH_RANGE);

  for (int b = 0; b < 4; b++) {
    glActiveTexture(GL_TEXTURE4 + b);
    glBindTexture(GL_TEXTURE_3D, m_tex_sh[b]);
  }
  glActiveTexture(GL_TEXTURE3);
  glBindTexture(GL_TEXTURE_CUBE_MAP, m_tex_cube);
  glUniform1i(loc("u_rt_probe_dc"), 4);
  glUniform1i(loc("u_rt_probe_l1a"), 5);
  glUniform1i(loc("u_rt_probe_l1b"), 6);
  glUniform1i(loc("u_rt_probe_l1c"), 7);
  glUniform1i(loc("u_rt_probe_cube"), 3);
  glActiveTexture(GL_TEXTURE0);
}
