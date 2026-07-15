#pragma once

#include <cstdio>
#include <cstdlib>
#include <string>

#include "common/math/Vector.h"

#include "game/graphics/opengl_renderer/BucketRenderer.h"

// Gjak2-visuals probe: one-shot per background (tie/tfrag) anim-slot bind —
// diffable our-x86 (env GJ2VIS_SKY) vs device (always) to see which title
// surfaces depend on TextureAnimator output slots.
inline void gj2vis_probe_bg_slot(int slot, unsigned tex) {
#ifdef __ANDROID__
  static const bool s_on = true;
#else
  static const bool s_on = getenv("GJ2VIS_SKY") != nullptr;
#endif
  if (s_on) {
    static bool s_seen[128] = {};
    if (slot >= 0 && slot < 128 && !s_seen[slot]) {
      s_seen[slot] = true;
      fprintf(stderr, "GJ2VIS-BGSLOT slot=%d tex=%u\n", slot, tex);
    }
  }
}

struct GoalBackgroundCameraData {
  math::Vector4f planes[4];
  math::Vector<s32, 4> itimes[4];
  math::Vector4f camera[4];
  math::Vector4f hvdf_off;
  math::Vector4f fog;
  math::Vector4f trans;
  math::Vector4f rot[4];
  math::Vector4f perspective[4];
};

// data passed from game to PC renderers
// the GOAL code assumes this memory layout.
struct TfragPcPortData {
  GoalBackgroundCameraData camera;
  char level_name[32];
};
static_assert(sizeof(TfragPcPortData) == 16 * 25);

// inputs to background renderers.
struct TfragRenderSettings {
  GoalBackgroundCameraData camera;
  int tree_idx;
  bool debug_culling = false;
  const u8* occlusion_culling = nullptr;
};

enum class DoubleDrawKind { NONE, AFAIL_NO_DEPTH_WRITE };

struct DoubleDraw {
  DoubleDrawKind kind = DoubleDrawKind::NONE;
  float aref_first = 0.;
  float aref_second = 0.;
  float color_mult = 1.;
};

// cached alpha_min/alpha_max uniform locations for a linked program (hot path:
// looked up once per program instead of per draw)
struct TfragAlphaUniforms {
  s32 alpha_min = -1;
  s32 alpha_max = -1;
};
const TfragAlphaUniforms& tfrag_alpha_uniforms(u64 program);

// Grecharged-grass-overhang2: near-fade params for the painted grass-fringe alpha strips (the 3D
// droop covers them near; far keeps the stock texture). x=enable, distances in METERS to match the
// tfrag3 shader's meter-scaled varying. Returns on=false unless BOTH recharged grass toggles are ON.
struct GrassFringeFade {
  bool on = false;
  float start_m = 0.f;
  float end_m = 0.f;
  // Grecharged-grass-overhang7 ROUND 10 forensics (painted strip still visible at the owner's close
  // judging distance): debug.opengoal.grass.fringe_dbg (Android) / GRASS_FRINGE_DBG (desktop).
  // 0 = stock (default). 1 = ignore the steepness gate (fade EVERY texel of the two fringe textures
  // near). 2 = don't fade; paint the gate state instead (magenta = would-fade steep face, cyan =
  // gate-blocked flat-ish face) — one close capture then names WHY a tuft survived the fade.
  float dbg = 0.f;
};
GrassFringeFade grass_fringe_fade_params();

// Grecharged-grass-overhang7: levels the recharged grass system covers. Round-7 root cause: the
// whole system (placement + fringe fade) was hardcoded to "training" while the owner plays and
// judges at Sentinel Beach — every lip there kept the stock painted overhang no matter the toggle.
// The GBK7 texture set (tra-grass / bch-grassfringe / bch-leafyground-hang-2x1) matches ONLY these
// two levels (16-level census 2026-07-14); other levels use differently-named grass textures and
// stay stock until they get their own curated set + bake.
inline constexpr const char* kGrassLevels[] = {"training", "beach"};
inline bool grass_level_enabled(const std::string& name) {
  for (const char* n : kGrassLevels) {
    if (name == n) {
      return true;
    }
  }
  return false;
}

DoubleDraw setup_tfrag_shader(SharedRenderState* render_state, DrawMode mode, ShaderId shader);
DoubleDraw setup_opengl_from_draw_mode(DrawMode mode, u32 tex_unit, bool mipmap);

// Pure computation of DoubleDraw settings from a DrawMode (no GL calls) — used
// by the tfrag-family state cache to pick the alpha uniform without re-issuing
// GL state.
DoubleDraw compute_double_draw(DrawMode mode);

// Gperf-particles: per-draw GL state cache for the tfrag-family loops. A local
// cache lives at the top of each tree-render function (per-render reset). When
// render_state->perf_state_cache is off, setup_tfrag_shader_cached is exactly
// setup_tfrag_shader.
struct BgDrawStateCache {
  u32 last_mode;
  GLuint last_tex;
  bool valid = false;
};
DoubleDraw setup_tfrag_shader_cached(SharedRenderState* rs,
                                     DrawMode mode,
                                     ShaderId shader,
                                     GLuint bound_tex,
                                     BgDrawStateCache& cache);

void first_tfrag_draw_setup(const GoalBackgroundCameraData& settings,
                            SharedRenderState* render_state,
                            ShaderId shader);

void interp_time_of_day(const math::Vector<s32, 4> itimes[4],
                        const tfrag3::PackedTimeOfDay& packed_colors,
                        math::Vector<u8, 4>* out);

void cull_check_all_slow(const math::Vector4f* planes,
                         const std::vector<tfrag3::VisNode>& nodes,
                         const u8* level_occlusion_string,
                         u8* out);
bool sphere_in_view_ref(const math::Vector4f& sphere, const math::Vector4f* planes);

void update_render_state_from_pc_settings(SharedRenderState* state, const TfragPcPortData& data);

void make_all_visible_multidraws(std::pair<int, int>* draw_ptrs_out,
                                 GLsizei* counts_out,
                                 void** index_offsets_out,
                                 const std::vector<tfrag3::ShrubDraw>& draws);

u32 make_all_visible_multidraws(std::pair<int, int>* draw_ptrs_out,
                                GLsizei* counts_out,
                                void** index_offsets_out,
                                const std::vector<tfrag3::StripDraw>& draws);

u32 make_multidraws_from_vis_string(std::pair<int, int>* draw_ptrs_out,
                                    GLsizei* counts_out,
                                    void** index_offsets_out,
                                    const std::vector<tfrag3::StripDraw>& draws,
                                    const std::vector<u8>& vis_data);

u32 make_all_visible_index_list(std::pair<int, int>* group_out,
                                u32* idx_out,
                                const std::vector<tfrag3::StripDraw>& draws,
                                const u32* idx_in,
                                u32* num_tris_out);

u32 make_index_list_from_vis_string(std::pair<int, int>* group_out,
                                    u32* idx_out,
                                    const std::vector<tfrag3::StripDraw>& draws,
                                    const std::vector<u8>& vis_data,
                                    const u32* idx_in,
                                    u32* num_tris_out);

u32 make_all_visible_index_list(std::pair<int, int>* group_out,
                                u32* idx_out,
                                const std::vector<tfrag3::ShrubDraw>& draws,
                                const u32* idx_in);

u32 make_multidraws_from_vis_and_proto_string(std::pair<int, int>* draw_ptrs_out,
                                              GLsizei* counts_out,
                                              void** index_offsets_out,
                                              const std::vector<tfrag3::StripDraw>& draws,
                                              const std::vector<u8>& vis_data,
                                              const std::vector<u8>& proto_vis_data);

u32 make_index_list_from_vis_and_proto_string(std::pair<int, int>* group_out,
                                              u32* idx_out,
                                              const std::vector<tfrag3::StripDraw>& draws,
                                              const std::vector<u8>& vis_data,
                                              const std::vector<u8>& proto_vis_data,
                                              const u32* idx_in,
                                              u32* num_tris_out);
