#pragma once

#include <vector>

#include "common/common_types.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/BucketRenderer.h"

#include "third-party/glad/include/glad/glad.h"

// Grecharged-grass-poc (jak1): scatters real 3D grass over the TRAINING level's
// ground triangles whose tfrag texture is "tra-grass". Renderer-only, gated by
// Gfx::g_global_settings.recharged_grass (OFF == byte-identical stock render).
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
  struct GrassInstance {
    float px, py, pz, h;        // world base position (GOAL units) + blade height
    float yaw, tint, curve, phase;
    // POLISH#4: average RGB of the ground TEXTURE under this blade (0..1), so the blade
    // colour is sampled/harmonised with the ground it grows from (no clash with the
    // texture showing through). w spare (kept for 16-byte attribute alignment).
    float gr, gg, gb, gspare;
    // ROUND#19: unit face normal of the ground triangle (world, ny forced >= 0); nspare reserved
    float nx, ny, nz, nspare;
  };

  void ensure_gl();
  void rebuild(SharedRenderState* render_state);
  // POLISH#9: recompute the per-instance GROUND baked-light for the CURRENT time of day and
  // re-upload it (throttled to only when the time-of-day weights actually change). This is what
  // makes the grass track the ground's baked lighting BOTH by location (per-triangle) and by
  // TIME (it re-samples the live itimes every frame instead of freezing the value at level load).
  void update_light(SharedRenderState* render_state);

  bool m_gl_ready = false;
  GLuint m_vao = 0;
  GLuint m_instance_vbo = 0;
  GLuint m_light_vbo = 0;   // POLISH#9: per-instance dynamic ground baked-light (u8 rgba, loc 3)

  std::vector<GrassInstance> m_instances;
  int m_instance_count = 0;

  // POLISH#9 dynamic ground baked-light source. Per KEPT triangle we keep its centroid's 8
  // time-of-day palette rows (pal[keyframe][channel], 0..255); update_light() blends them with the
  // live itimes weights to get the EXACT baked colour the ground vertex is drawn with this frame,
  // then multiplies the grass by it (matching the ground's own (palette/255)*2 factor). m_inst_tri
  // maps each surviving instance back to its source triangle (kept through the occlusion cull).
  struct TriLight {
    float pal[8][3];
  };
  std::vector<TriLight> m_tri_light;
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

  // instrumentation state (throttled per-frame culling log)
  u64 m_frame = 0;
  float m_last_log_cam[3] = {1e30f, 1e30f, 1e30f};
};
