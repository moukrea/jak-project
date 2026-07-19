#pragma once

#include <optional>

#include "common/util/FilteredValue.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/BucketRenderer.h"
#include "game/graphics/opengl_renderer/background/background_common.h"
#include "game/graphics/pipelines/opengl.h"

class Shrub : public BucketRenderer {
 public:
  Shrub(const std::string& name, int my_id);
  ~Shrub();
  void init_shaders(ShaderLibrary& shaders) override;

  bool setup_for_level(const std::string& level, SharedRenderState* render_state);
  void render_all_trees(const TfragRenderSettings& settings,
                        SharedRenderState* render_state,
                        ScopedProfilerNode& prof);
  void render_tree(int idx,
                   const TfragRenderSettings& settings,
                   SharedRenderState* render_state,
                   ScopedProfilerNode& prof);
  void render(DmaFollower& dma, SharedRenderState* render_state, ScopedProfilerNode& prof) override;
  void draw_debug_window() override;

 private:
  void update_load(const LevelData* loader_data);
  void discard_tree_cache();

  struct Tree {
    GLuint vertex_buffer;
    GLuint index_buffer;
    u32 index_count = 0;  // Grecharged-realtime-lighting round-3: full static strip index count, for the shadow caster pass
    GLuint single_draw_index_buffer;
    GLuint time_of_day_texture;
    // Gperf-particles round 3: second TOD texture for the ping-pong path, plus
    // the per-frame flip bit. tod_current is set at TOD-update time to whichever
    // texture this frame's draws should sample, so every subsequent bind uses
    // the same texture (no stale bind). perf_tod_pingpong OFF => tod_current is
    // always time_of_day_texture (identical to the old single-texture path).
    GLuint time_of_day_texture_pp = 0;
    u8 tod_flip = 0;
    GLuint tod_current = 0;
    s32 tod_cache_itimes[16] = {0};   // Gperf-particles: last itimes (4x Vector<s32,4>) for memoize
    bool tod_cache_valid = false;
    GLuint vao;
    u32 vert_count;
    const std::vector<tfrag3::ShrubDraw>* draws = nullptr;
    const std::vector<tfrag3::TieWindInstance>* instance_info = nullptr;
    const tfrag3::PackedTimeOfDay* colors = nullptr;
    const u32* index_data = nullptr;
    std::vector<bool> proto_vis_mask;
    std::unordered_map<std::string, std::vector<u32>> proto_name_to_idx;
    // Gperf-particles round 3: level-static single-draw index cache. When
    // perf_shrub_static_idx is on, the index list (built once by
    // make_all_visible_index_list) and its GPU upload are done a single time at
    // level load; per-frame the build+upload are skipped and the draw loop reads
    // cached_draw_idx instead of m_cache.draw_idx_temp.
    std::vector<std::pair<int, int>> cached_draw_idx;
    bool idx_cached = false;
    u32 cached_idx_count = 0;
    // Grecharged-foliage-wind: Wx1 RGBA8 LUT indexed by color_index (constant per shrub
    // instance): 16-bit packed (minY, height) per plant, for the sway base anchor + per-plant
    // height normalization. Built once at load; sampled only when the toggle is ON.
    GLuint wind_lut_texture = 0;
    float wind_lut_base = 0.f;  // dequant: y = base + q16 * scale
    float wind_lut_scale = 1.f;

    struct {
      u32 draws = 0;
      u32 wind_draws = 0;
      Filtered<float> cull_time;
      Filtered<float> index_time;
      Filtered<float> tod_time;
      Filtered<float> setup_time;
      Filtered<float> draw_time;
      Filtered<float> tree_time;
    } perf;
  };

  struct {
    GLuint decal;
  } m_uniforms;

  std::vector<Tree> m_trees;
  std::string m_level_name;
  const std::vector<GLuint>* m_textures;
  u64 m_load_id = -1;

  std::vector<math::Vector<u8, 4>> m_color_result;

  static constexpr int TIME_OF_DAY_COLOR_COUNT = 8192;
  bool m_has_level = false;

  struct Cache {
    std::vector<std::pair<int, int>> draw_idx_temp;
    std::vector<u32> index_temp;
    std::vector<std::pair<int, int>> multidraw_offset_per_stripdraw;
    std::vector<GLsizei> multidraw_count_buffer;
    std::vector<void*> multidraw_index_offset_buffer;
  } m_cache;
  TfragPcPortData m_pc_port_data;
  const u8* m_proto_vis_data = nullptr;
  int m_proto_vis_data_size = 0;
};
