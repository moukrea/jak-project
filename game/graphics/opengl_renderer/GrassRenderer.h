#pragma once

#include <string>
#include <vector>

#include "common/common_types.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/BucketRenderer.h"
#include "game/graphics/opengl_renderer/GrassBakeCore.h"

#include "third-party/glad/include/glad/glad.h"

struct LevelData;  // Grecharged-grass-overhang7: loader/common.h; rebuild() now takes the level

// Grecharged-grass-poc (jak1): scatters real 3D grass over the ground triangles whose tfrag
// texture is in the grass set (tra-grass / bch-grassfringe / bch-leafyground-hang-2x1) for the
// levels in the grass allowlist (background_common.h grass_level_enabled: training + beach as of
// overhang7). Renderer-only, gated by Gfx::g_global_settings.recharged_grass (OFF ==
// byte-identical stock render).
//
// CULLING FIX (owner feedback #2, 2026-07-10): placement is WHOLE-LEVEL and
// CAMERA-INDEPENDENT — every qualifying training-ground triangle is scattered
// ONCE at level load, at a uniform density auto-scaled to a budget, into a static
// complete buffer. Walking NEVER rebuilds and NEVER re-grades density, so no
// chunk can pop in, fail to load, or de-instance while moving (the old build
// windowed placement to 64 m of the camera and rebuilt every 20 m with a
// distance-graded density — exactly the "zones disappear while moving" bug).
// All LOD/visibility is done in the shader from the live camera.
//
// Drawn every frame as two instanced passes:
//   NEAR: individual curved/tapered blades (breeze + trample)
//   MID : X-cross grass cards (gentle sway)
//   FAR : nothing (LOD fade in the shader)
class GrassRenderer {
 public:
  GrassRenderer();
  ~GrassRenderer();
  void render(SharedRenderState* render_state, ScopedProfilerNode& prof);

 private:
  void ensure_gl();
  // Grecharged-grass-overhang7: rebuild takes the resolved grass level (allowlist lookup in
  // render()) instead of hardcoding "training" — the owner plays/judges at Sentinel Beach, which
  // carries the same bch-* grass/hang textures and was getting NOTHING from any toggle.
  void rebuild(SharedRenderState* render_state, const LevelData* ld, const std::string& level_name);
  // POLISH#9: recompute the per-instance GROUND baked-light for the CURRENT time of day and
  // re-upload it (throttled to only when the time-of-day weights actually change). This is what
  // makes the grass track the ground's baked lighting BOTH by location (per-triangle) and by
  // TIME (it re-samples the live itimes every frame instead of freezing the value at level load).
  void update_light(SharedRenderState* render_state);

  bool m_gl_ready = false;
  GLuint m_vao = 0;
  GLuint m_instance_vbo = 0;
  GLuint m_light_vbo = 0;   // POLISH#9: per-instance dynamic ground baked-light (u8 rgba, loc 3)

  std::vector<grass_bake::GrassInstance> m_instances;
  int m_instance_count = 0;
  // Grecharged-grass-overhang: droop instances live at the TAIL of m_instances ([m_droop_start,
  // m_instance_count)). Blade pass draws through them only while the overhang toggle is ON; the
  // card pass always stops at m_droop_start (far LOD = the stock alpha texture, never cards).
  int m_droop_start = 0;

  // POLISH#9 dynamic ground baked-light source. Per KEPT triangle we keep its centroid's 8
  // time-of-day palette rows (pal[keyframe][channel], 0..255); update_light() blends them with the
  // live itimes weights to get the EXACT baked colour the ground vertex is drawn with this frame,
  // then multiplies the grass by it (matching the ground's own (palette/255)*2 factor). m_inst_tri
  // maps each surviving instance back to its source triangle (kept through the occlusion cull).
  // Grecharged-grass-precompute-mode: the per-tri baked-light source (pal[8][3]) now lives in the
  // shared bake tables (m_bake.tris[t].pal, identical float[8][3] layout).
  grass_bake::BakeData m_bake;
  std::vector<u32> m_inst_tri;
  std::vector<u8> m_light;                  // 4 bytes/instance (rgba), re-uploaded on TOD change
  s32 m_last_itimes[4][4] = {};             // weights of the last light upload (change-detect throttle)
  bool m_light_valid = false;
  u32 m_light_uploads = 0;                  // POLISH#9: how many times the dynamic light re-uploaded
                                            // (>1 over time == the day cycle is being tracked)

  // Spatial chunk grid over the placed instances — for the culling
  // instrumentation only (owner feedback #2): every frame we log how many chunks
  // are in LOD range vs how many are actually drawn, to PROVE the static field
  // never drops an in-range chunk while moving.
  struct ChunkInfo {
    float cx, cz;  // chunk center in world units (xz)
    int count;     // instances in this chunk
  };
  std::vector<ChunkInfo> m_chunks;

  const void* m_cached_level = nullptr;
  u64 m_cached_load_id = UINT64_MAX;
  // POLISH#5: the density-percent used at the last scatter. A density-slider change
  // (recharged_grass_density) differs from this -> re-scatter the whole static field.
  float m_cached_density = -1.f;
  // Grecharged-grass-precompute-mode cache keys: precomputed-mode toggle + floor-gap threshold.
  bool m_cached_precomputed = false;
  float m_cached_floor_gap = -1.f;

  // instrumentation state (throttled per-frame culling log)
  u64 m_frame = 0;
  float m_last_log_cam[3] = {1e30f, 1e30f, 1e30f};
};
