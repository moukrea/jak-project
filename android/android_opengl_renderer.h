// Phase A35 (autoport): Android GLES 3.2 bucket-dispatch renderer.
//
// This is the OpenGLRenderer SKELETON the A35 mandate asks for: the same
// jak1 bucket-dispatch loop as game/graphics/opengl_renderer/OpenGLRenderer.cpp
// (default-regs parse, 70 buckets, vif interrupt per bucket, FBO render +
// window blit), but instantiating only the renderer subset ported to
// Android so far:
//
//   * DirectRenderer       — DEBUG / DEBUG_NO_ZBUF / SUBTITLE (GIF-packet
//                            immediate prims: text/2D, the first-content
//                            workhorse)
//   * TextureUploadHandler — all ten jak1 *_TEX buckets + PRE_SPRITE_TEX
//                            (feeds TexturePool exactly like desktop)
//   * EyeRenderer          — MERC_EYES_AFTER_PRIS (also consumed by the
//                            tex-bucket eye-dma path)
//
// Every other bucket is a SkipRenderer; the dispatch loop logs ONE
// `A35-RENDER skip bucket=<name> id=<n> (not ported)` line the first time
// that bucket actually carries data — never silently.
#pragma once

#include <array>
#include <memory>
#include <string>
#include <vector>

#include "common/dma/dma_chain_read.h"

#include "game/graphics/opengl_renderer/BucketRenderer.h"
#include "game/graphics/opengl_renderer/Fbo.h"
#include "game/graphics/opengl_renderer/foreground/Generic2.h"
#include "game/graphics/opengl_renderer/Profiler.h"
#include "game/graphics/opengl_renderer/opengl_utils.h"

// Mirrors the desktop RenderOptions subset the Android skeleton honors.
struct AndroidRenderOptions {
  int game_res_w = 640;
  int game_res_h = 480;
  int window_fb_w = 0;
  int window_fb_h = 0;
  int draw_region_w = 0;
  int draw_region_h = 0;
  float pmode_alp_register = 1.f;

  // Render-scaling knob (debug.opengoal.render.scale = 25..400, default set in
  // android_gfx.cpp). The whole 3D scene is rendered into an offscreen FBO
  // sized game_res * (render_scale_pct/100), keeping the 4:3 aspect;
  // do_pcrtc_effects then GL_LINEAR resample-blits that FBO to the native draw
  // region. 100 == original 640x480 behavior. <100 trades sharpness for fill-
  // rate; >100 SUPERSAMPLES the 3D (e.g. 200 -> 1280x960) for crispness. Draw-
  // call/triangle submission is identical at every scale (only the fragment
  // sample count changes). Host-only; GOAL render logic and game_res_w/h are
  // untouched.
  int render_scale_pct = 100;
};

struct AndroidFrameStats {
  u64 frame_idx = 0;
  u32 chain_bytes = 0;
  u32 buckets_with_data = 0;
  u32 buckets_drawn = 0;   // buckets with data handled by a real renderer
  u32 buckets_skipped = 0; // buckets with data handled by SkipRenderer
  u32 draw_calls = 0;
  u32 triangles = 0;

  // GL-thread CPU timing (seconds) from the per-frame Profiler tree. Surfaces
  // the already-measured node durations so a profiling run can attribute the
  // frame budget: render_cpu_s = whole render() call, buckets_cpu_s = bucket
  // dispatch (GL submission), pcrtc_cpu_s = the upscale blit + blackout.
  float render_cpu_s = 0.f;
  float buckets_cpu_s = 0.f;
  float pcrtc_cpu_s = 0.f;
  // Effective offscreen FBO size after render-scaling (for the stat log).
  int fbo_w = 0;
  int fbo_h = 0;
};

class AndroidOpenGLRenderer {
 public:
  AndroidOpenGLRenderer(std::shared_ptr<TexturePool> texture_pool, std::shared_ptr<Loader> loader);

  // Render one frame from the game's DMA chain. Must run on the GL thread.
  void render(DmaFollower dma, const AndroidRenderOptions& settings);

  const AndroidFrameStats& stats() const { return m_stats; }

 private:
  void init_bucket_renderers_jak1();
  void init_bucket_renderers_jak2();
  void setup_frame(const AndroidRenderOptions& settings);
  void dispatch_buckets_jak1(DmaFollower dma, ScopedProfilerNode& prof);
  void dispatch_buckets_jak2(DmaFollower dma, ScopedProfilerNode& prof);
  void do_pcrtc_effects(float alp, SharedRenderState* render_state, ScopedProfilerNode& prof);
  u32 count_chain_bytes(DmaFollower dma);
  // Grender-split: composite the scaled 3D scene FBO into the native-resolution UI
  // FBO and re-target rendering there. Installed into m_render_state.begin_2d_ui_pass
  // when the split is active; idempotent within a frame.
  void begin_ui_pass();

  SharedRenderState m_render_state;
  Profiler m_profiler;
  std::vector<std::unique_ptr<BucketRenderer>> m_bucket_renderers;
  std::vector<bool> m_bucket_ported;
  std::vector<bool> m_skip_logged;

  FullScreenDraw m_blackout_renderer;
  float m_last_pmode_alp = 1.f;

  struct {
    Fbo window;
    Fbo render_buffer;
    Fbo ui_buffer;  // Grender-split: native-res buffer for the 2D UI pass
    Fbo* render_fbo = nullptr;
  } m_fbo_state;

  // Grender-split: true once begin_ui_pass() has composited+switched this frame.
  bool m_ui_pass_active = false;

  std::shared_ptr<Generic2> m_generic2;

  GLuint m_screen_vao = 0;
  GLuint m_screen_vbo = 0;

  AndroidFrameStats m_stats;
};
