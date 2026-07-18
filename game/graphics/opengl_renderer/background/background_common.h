#pragma once

#include <cstdio>
#include <cstdlib>
#include <string>
#include <vector>

#include "common/dma/gs.h"
#include "common/math/Vector.h"

#include "game/graphics/opengl_renderer/BucketRenderer.h"
#ifdef OG_FEAT_PBR
#include "game/graphics/opengl_renderer/loader/CustomTextureReplacements.h"
#endif

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

#ifdef OG_FEAT_PBR
// Grecharged-pbr-materials hardening (owner "beaucoup de violet" class): 1x1 neutral
// PBR maps. The tfrag3 program declares tex_PBR_N/R/M/AO on units 11-14 whenever the
// build has PBR; Adreno samples garbage/magenta from an incomplete or unbound unit
// regardless of the u_pbr_mode branch, so those units must ALWAYS carry a complete
// texture during tfrag draws — including when zero PBR materials are registered
// (e.g. a partial albedo-only drop dir). Texel values match the shader's absent-map
// constants (flat normal, rough 0.7, metal 0, ao 1, height 1 = zero POM depth).
// GL-thread only.
struct PbrNeutralMaps {
  GLuint normal_tex = 0, rough_tex = 0, metal_tex = 0, ao_tex = 0, height_tex = 0;
};
const PbrNeutralMaps& pbr_neutral_maps();
// Bind the neutrals to units 11-15 and restore active unit 0.
void pbr_park_neutral_maps();

// Grecharged-pbr-materials round-4 coverage unification: the per-draw PBR material
// bind was originally a lambda local to TFragment's draw loop. Tie3 draws its
// non-envmap categories with the SAME TFRAG3 program but never bound PBR maps, so a
// replaced TIE texture rendered its albedo without the BRDF (the owner-seen
// half-PBR). This helper factors that exact lambda so TFragment and Tie3 share ONE
// implementation. Semantics are byte-identical to the original TFragment lambda when
// no PBR material is registered (empty draw list => set() early-returns, finish() is
// a no-op).
struct PbrDrawEntry {
  s32 tex_idx;
  custom_tex::PbrMaterialMaps maps;
};
using PbrDrawList = std::vector<PbrDrawEntry>;

class PbrDrawBinder {
 public:
  // program = the TFRAG3 program id (u_pbr_mode lives there); draws = the level's
  // resolved PBR material list. ONLY use on paths where the active program IS TFRAG3
  // (never ETIE/ETIE_BASE/envmap).
  void begin(GLuint program, const PbrDrawList* draws);
  // Per-draw: look up tex_id, gate on the runtime toggle + opaque/non-decal rule,
  // bind units 11-15 real-or-neutral, set u_pbr_mode.
  void set(s32 tex_id, const DrawMode& mode);
  // Restore u_pbr_mode to 0 and park the neutral maps if anything was bound. Must be
  // called before the TFRAG3 program is handed to any other renderer.
  void finish();

 private:
  GLuint m_program = 0;
  const PbrDrawList* m_draws = nullptr;
  GLint m_mode_loc = -2;
  int m_cur_mode = 0;
  bool m_bound_any = false;
};

// Grecharged-pbr-materials round-4 mandate B: classic sun SHADOW MAPPING for the PBR
// direct term. A depth-only pass renders the camera-vis-culled tfrag NORMAL geometry into
// a 1024x1024 depth FBO from the mood-sun direction, in the SAME camera-relative-meters
// space as v_fringe_rel = (position_in - cam_trans.xyz)/4096. The PBR fragment path then
// multiplies its ENTIRE direct (multi-light) term by a PCF shadow factor. Indirect/baked-GI
// term untouched. Merc/actor casters are OUT of scope (the stock stencil shadow system
// covers actors). GL-thread only.
struct PbrShadowState {
  GLuint fbo = 0;
  GLuint depth_tex = 0;
  int size = 1024;
  u64 frame = ~0ull;   // frame_idx that last cleared the map
  bool valid = false;  // resources created OK
  bool have_mvp = false;  // mvp computed for the current frame
  float mvp[16];          // column-major light view-proj (camera-relative meters)
};
PbrShadowState& pbr_shadow_state();
void pbr_shadow_ensure_resources();             // lazy FBO/tex creation
bool pbr_shadow_begin_frame(u64 frame_idx);     // true if the depth pass should run
void pbr_shadow_bind_receiver(GLuint program);  // bind matrix+sampler on a TFRAG3-family program
#endif

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
