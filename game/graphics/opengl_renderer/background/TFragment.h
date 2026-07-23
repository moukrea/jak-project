#pragma once

#include "common/dma/gs.h"
#include "common/math/Vector.h"

#include "game/graphics/opengl_renderer/BucketRenderer.h"
#include "game/graphics/opengl_renderer/DirectRenderer.h"
#include "game/graphics/opengl_renderer/background/Tie3.h"
#ifdef OG_FEAT_PBR
#include "game/graphics/opengl_renderer/loader/CustomTextureReplacements.h"
#endif

using math::Matrix4f;
using math::Vector4f;

struct TFragData {
  Vector4f fog;          // 0   656 (vf01)
  Vector4f val;          // 1   657 (vf02)
  GifTag str_gif;        // 2   658 (vf06)
  GifTag fan_gif;        // 3   659
  GifTag ad_gif;         // 4   660
  Vector4f hvdf_offset;  // 5   661 (vf10)
  Vector4f hmge_scale;   // 6   662 (vf11)
  Vector4f invh_scale;   // 7   663
  Vector4f ambient;      // 8   664
  Vector4f guard;        // 9   665
  Vector4f k0s[2];       // 10/11 666, 667
  Vector4f k1s[2];       // 12/13 668, 669

  std::string print() const;
};
static_assert(sizeof(TFragData) == 0xe0, "TFragData size");

struct TFragBufferedData {
  u8 pad[328 * 16];
};
static_assert(sizeof(TFragBufferedData) == 328 * 16);

class TFragment : public BucketRenderer {
 public:
  TFragment(const std::string& name,
            int my_id,
            const std::vector<tfrag3::TFragmentTreeKind>& trees,
            bool child_mode,
            int level_id,
            const std::vector<GLuint>* anim_slot_array);
  ~TFragment();
  void render(DmaFollower& dma, SharedRenderState* render_state, ScopedProfilerNode& prof) override;
  void draw_debug_window() override;
  void init_shaders(ShaderLibrary& shaders) override;

  void render_all_trees(int geom,
                        const TfragRenderSettings& settings,
                        SharedRenderState* render_state,
                        ScopedProfilerNode& prof);

  void render_matching_trees(int geom,
                             const std::vector<tfrag3::TFragmentTreeKind>& trees,
                             const TfragRenderSettings& settings,
                             SharedRenderState* render_state,
                             ScopedProfilerNode& prof);

  void render_tree(int geom,
                   const TfragRenderSettings& settings,
                   SharedRenderState* render_state,
                   ScopedProfilerNode& prof);

  bool setup_for_level(const std::vector<tfrag3::TFragmentTreeKind>& tree_kinds,
                       const std::string& level,
                       SharedRenderState* render_state);
  void discard_tree_cache();

  void render_tree_cull_debug(const TfragRenderSettings& settings,
                              SharedRenderState* render_state,
                              ScopedProfilerNode& prof);

  void update_load(const std::vector<tfrag3::TFragmentTreeKind>& tree_kinds,
                   const LevelData* loader_data);

  int lod() const { return Gfx::g_global_settings.lod_tfrag; }
  struct DebugVertex {
    math::Vector3f position;
    math::Vector4f rgba;
  };

 private:
  void handle_initialization(DmaFollower& dma);
  bool m_child_mode = false;

  // GS setup data
  u8 m_test_setup[32];

  // VU data
  TfragPcPortData m_pc_port_data;

  // buffers
  TFragBufferedData m_buffered_data[2];

  enum TFragDataMem {
    Buffer0_Start = 0,
    TFragMatrix0 = 5,

    Buffer1_Start = 328,
    TFragMatrix1 = TFragMatrix0 + Buffer1_Start,

    TFragFrameData = 656,
    TFragKickZoneData = 670,
  };

  enum TFragProgMem {
    TFragSetup = 0,
  };

  std::vector<tfrag3::TFragmentTreeKind> m_tree_kinds;
  int m_level_id;

  static constexpr int GEOM_MAX = 3;

  struct TreeCache {
    tfrag3::TFragmentTreeKind kind = tfrag3::TFragmentTreeKind::INVALID;
    GLuint vertex_buffer = -1;
    GLuint index_buffer = -1;
    GLuint single_draw_index_buffer = -1;
    GLuint time_of_day_texture = -1;
    // Gperf-particles round 3: second TOD texture + flip bit for the Adreno
    // ping-pong; tod_current is set at TOD-update time and used by the draw
    // bind. Flag OFF => tod_current == time_of_day_texture (old path).
    GLuint time_of_day_texture_pp = -1;
    u8 tod_flip = 0;
    GLuint tod_current = -1;
    s32 tod_cache_itimes[16] = {0};   // Gperf-particles: last itimes (4x Vector<s32,4>) for memoize
    bool tod_cache_valid = false;
    GLuint vao = -1;
    u32 vert_count = 0;
    const std::vector<tfrag3::StripDraw>* draws = nullptr;
    const tfrag3::PackedTimeOfDay* colors = nullptr;
    const tfrag3::BVH* vis = nullptr;
    const u32* index_data = nullptr;
    u64 draw_mode = 0;
#ifdef OG_FEAT_PBR
    // Grecharged-pbr-materials round-4 mandate B: total index count of the resident static
    // full index buffer (tree.index_buffer) uploaded at load. The sun shadow depth pass
    // draws the whole tree on the multidraw path where no per-frame count is otherwise
    // computed.
    u32 index_count = 0;
    // REOPEN #3 TESSELLATION: a flat TRIANGLE-LIST index buffer (GL_PATCHES with 3 verts) built
    // LAZILY on first tess draw from the static strip+restart stream (tree.unpacked.indices).
    // tess_tri_ranges[i] = the (first, count) flat-index range for tree.draws[i]; whole-tree
    // (no vis-culling — visual-only displacement on the color pass). Freed with the tree.
    GLuint tess_index_buffer = 0;   // 0 = not yet built
    u32 tess_index_count = 0;
    std::vector<std::pair<u32, u32>> tess_tri_ranges;  // per-draw (first_flat_idx, flat_count)
#endif

    void reset_stats() {
      rendered_this_frame = false;
      tris_this_frame = 0;
      draws_this_frame = 0;
    }
    bool rendered_this_frame = false;
    int tris_this_frame = 0;
    int draws_this_frame = 0;
    bool allowed = true;
    bool forced = false;
    bool cull_debug = false;

    bool freeze_itimes = false;
    math::Vector<s32, 4> itimes_debug[4];
  };

#ifdef OG_FEAT_PBR
  // REOPEN #3 TESSELLATION: lazily build tree.tess_index_buffer (a flat triangle-list from the
  // static strip stream) + tree.tess_tri_ranges. No-op if already built.
  static void build_tess_tri_buffer(TreeCache& tree);
#endif

  struct {
    GLuint decal;
  } m_uniforms;

  struct Cache {
    std::vector<u8> vis_temp;
    std::vector<std::pair<int, int>> draw_idx_temp;
    std::vector<u32> index_temp;
    std::vector<std::pair<int, int>> multidraw_offset_per_stripdraw;
    std::vector<GLsizei> multidraw_count_buffer;
    std::vector<void*> multidraw_index_offset_buffer;
  } m_cache;

  std::string m_level_name;

  const std::vector<GLuint>* m_textures = nullptr;
  std::array<std::vector<TreeCache>, GEOM_MAX> m_cached_trees;

  std::vector<math::Vector<u8, 4>> m_color_result;

  GLuint m_debug_vao = -1;
  GLuint m_debug_verts = -1;

  u64 m_load_id = -1;

  // in theory could be up to 4096, I think, but we don't see that many...
  // should be easy to increase
  static constexpr int TIME_OF_DAY_COLOR_COUNT = 8192;

  static constexpr int DEBUG_TRI_COUNT = 4096;
  std::vector<DebugVertex> m_debug_vert_data;

  bool m_has_level = false;
  const std::vector<GLuint>* m_anim_slot_array;

  // Grecharged-grass-overhang2: tree_tex_id values of the painted fringe alpha textures for the
  // CURRENT level (training only); -1 = none. Draws with these textures get the near fade while
  // the droop toggle is ON.
  s32 m_fringe_tex_a = -1;
  s32 m_fringe_tex_b = -1;

#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials: per-level list of textures with a registered PBR
  // material set (resolved in update_load; no level-name gating). Type + per-draw
  // bind now shared with Tie3 via background_common's PbrDrawBinder (round-4).
  PbrDrawList m_pbr_draws;
#endif
};
