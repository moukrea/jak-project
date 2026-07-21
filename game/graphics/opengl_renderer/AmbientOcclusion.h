#pragma once

// Grecharged-ambient-occlusion: screen-space ambient occlusion for the OpenGOAL
// renderer (desktop GL 4.1 + Android GLES 3.2). Three interchangeable estimators
// (SSAO / HBAO / GTAO) selected by Gfx::g_global_settings.recharged_ao_mode, at a
// per-quality resolution scale from recharged_ao_quality. Renderer-only, composited
// over the OPAQUE scene at the post-opaque bucket-31 insertion point (before grass /
// alpha), so transparent surfaces are excluded by construction. OFF == stock render.

#include "game/graphics/opengl_renderer/BucketRenderer.h"
#include "game/graphics/opengl_renderer/Fbo.h"
#include "game/graphics/opengl_renderer/Shader.h"

#include "third-party/glad/include/glad/glad.h"

class AmbientOcclusionPass {
 public:
  AmbientOcclusionPass() = default;
  ~AmbientOcclusionPass();

  // Live-tunable, debug-overridable resolved mode/quality. Reads the game settings
  // globals unless a debug override (Android system-prop / desktop env) is present.
  // 0=off/1=SSAO/2=HBAO/3=GTAO ; quality 0=low/1=med/2=high.
  static int effective_mode();
  static int effective_quality();
  static int effective_strength();
  static int effective_debug();

  // Store the shader library for render-time use (mirrors the bucket-renderer flow).
  void init_shaders(ShaderLibrary& shaders);

  // Size the AO/blur chain by the WINDOW (not the render-scale-sized FBO) so a dynamic
  // render-scale change never recreates the chain (no churn / no blink). 0 == "no hint,
  // fall back to the render FBO size" (the desktop path leaves it unset).
  void set_output_hint(int w, int h) {
    m_hint_w = w;
    m_hint_h = h;
  }

  // Estimate + blur + composite AO over the opaque scene currently in render_fbo. With
  // estimate=false ("composite-only" defer path) the depth-sampling estimator/blur are
  // skipped and the last AO term is composited over the freshly-recreated FBO.
  void render(SharedRenderState* rs,
              ScopedProfilerNode& prof,
              Fbo* render_fbo,
              bool estimate = true);

 private:
  void ensure_quad();
  void ensure_targets(int ao_w, int ao_h, int full_w, int full_h);
  void ensure_depth_resolve(int w, int h);
  void ensure_scene_copy(int w, int h);
  void free_targets();

  ShaderLibrary* m_shaders = nullptr;

  // fullscreen-quad geometry (matches OpenGLRenderer's screen_vao/vbo layout).
  GLuint m_quad_vao = 0;
  GLuint m_quad_vbo = 0;
  bool m_quad_ready = false;

  // small AO ping-pong targets (R8): raw estimate <-> blur scratch.
  GLuint m_ao_fbo[2] = {0, 0};
  GLuint m_ao_tex[2] = {0, 0};
  int m_ao_w = 0;
  int m_ao_h = 0;

  // full-res AO target (R8): the V blur pass writes here at FULL resolution, doubling as
  // a depth-aware upsample so a sub-full-res AO term never composites blocky (owner
  // tuning #2: GTAO-low pixelation at full render res).
  GLuint m_ao_full_fbo = 0;
  GLuint m_ao_full_tex = 0;
  int m_ao_full_w = 0;
  int m_ao_full_h = 0;

  // depth-resolve FBO (only used when the render FBO is multisampled): a full-res
  // DEPTH24_STENCIL8 texture + a tiny R8 color for guaranteed completeness.
  GLuint m_depth_resolve_fbo = 0;
  GLuint m_depth_resolve_tex = 0;   // sampleable depth texture
  GLuint m_depth_resolve_color = 0;  // 1x1-completeness color
  int m_depth_resolve_w = 0;
  int m_depth_resolve_h = 0;

  // Scene-color copy (RGBA8): the composite reads its SCALAR luminance to mask AO out of
  // direct-lit pixels (REOPEN burn fix). Sized to the AO output (ao_w/ao_h), recreated only
  // on size change.
  GLuint m_scene_tex = 0;
  GLuint m_scene_fbo = 0;
  int m_scene_w = 0, m_scene_h = 0;

  // Output-size hint (window-keyed AO chain sizing; 0 == fall back to render FBO size).
  int m_hint_w = 0, m_hint_h = 0;

  int m_err_logged = 0;
};
