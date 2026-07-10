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
// Instances are built once per level load (deterministic hash-scatter on the
// tra-grass triangles), then drawn every frame as two instanced passes:
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
  };

  void ensure_gl();
  void rebuild(SharedRenderState* render_state);

  bool m_gl_ready = false;
  GLuint m_vao = 0;
  GLuint m_instance_vbo = 0;

  std::vector<GrassInstance> m_instances;
  int m_instance_count = 0;

  const void* m_cached_level = nullptr;
  u64 m_cached_load_id = UINT64_MAX;
};
