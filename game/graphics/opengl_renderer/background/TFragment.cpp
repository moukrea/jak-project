#include "TFragment.h"

#include <cstdio>
#include <cstring>

#include "game/graphics/opengl_renderer/dma_helpers.h"

#include "third-party/imgui/imgui.h"

namespace {
bool looks_like_tfragment_dma(const DmaFollower& follow) {
  return follow.current_tag_vifcode0().kind == VifCode::Kind::STCYCL;
}

bool looks_like_tfrag_init(const DmaFollower& follow) {
  return follow.current_tag_vifcode0().kind == VifCode::Kind::NOP &&
         follow.current_tag_vifcode1().kind == VifCode::Kind::DIRECT &&
         follow.current_tag_vifcode1().immediate == 2;
}
}  // namespace

TFragment::TFragment(const std::string& name,
                     int my_id,
                     const std::vector<tfrag3::TFragmentTreeKind>& trees,
                     bool child_mode,
                     int level_id,
                     const std::vector<GLuint>* anim_slot_array)
    : BucketRenderer(name, my_id),
      m_child_mode(child_mode),
      m_tree_kinds(trees),
      m_level_id(level_id),
      m_anim_slot_array(anim_slot_array) {
  for (auto& buf : m_buffered_data) {
    for (auto& x : buf.pad) {
      x = 0xff;
    }
  }

  glGenVertexArrays(1, &m_debug_vao);
  glBindVertexArray(m_debug_vao);
  glGenBuffers(1, &m_debug_verts);
  glBindBuffer(GL_ARRAY_BUFFER, m_debug_verts);
  glBufferData(GL_ARRAY_BUFFER, DEBUG_TRI_COUNT * 3 * sizeof(DebugVertex), nullptr,
               GL_DYNAMIC_DRAW);
  glEnableVertexAttribArray(0);
  glEnableVertexAttribArray(1);
  glVertexAttribPointer(0,                                      // location 0 in the shader
                        3,                                      // 3 values per vert
                        GL_FLOAT,                               // floats
                        GL_FALSE,                               // normalized
                        sizeof(DebugVertex),                    // stride
                        (void*)offsetof(DebugVertex, position)  // offset (0)
  );

  glVertexAttribPointer(1,                                  // location 1 in the shader
                        4,                                  // 4 values per vert
                        GL_FLOAT,                           // floats
                        GL_FALSE,                           // normalized
                        sizeof(DebugVertex),                // stride
                        (void*)offsetof(DebugVertex, rgba)  // offset (0)
  );
  glBindVertexArray(0);
  // regardless of how many we use some fixed max
  // we won't actually interp or upload to gpu the unused ones, but we need a fixed maximum so
  // indexing works properly.
  m_color_result.resize(TIME_OF_DAY_COLOR_COUNT);
}

TFragment::~TFragment() {
  discard_tree_cache();
  glDeleteVertexArrays(1, &m_debug_vao);
}

void TFragment::render(DmaFollower& dma,
                       SharedRenderState* render_state,
                       ScopedProfilerNode& prof) {
  if (!m_enabled) {
    while (dma.current_tag_offset() != render_state->next_bucket) {
      dma.read_and_advance();
    }
    return;
  }

  // First thing should be a NEXT with two nops.
  // unless we are a child, in which case our parent took this already.
  if (!m_child_mode) {
    auto data0 = dma.read_and_advance();
    ASSERT(data0.vifcode1().kind == VifCode::Kind::NOP);
    ASSERT(data0.vif0() == 0 || data0.vifcode0().kind == VifCode::Kind::MARK);
    ASSERT(data0.size_bytes == 0);
  }

  if (dma.current_tag().kind == DmaTag::Kind::CALL) {
    // renderer didn't run, let's just get out of here.
    for (int i = 0; i < 4; i++) {
      dma.read_and_advance();
    }
    ASSERT(dma.current_tag_offset() == render_state->next_bucket);
    return;
  }

  if (m_my_id == render_state->bucket_for_vis_copy &&
      dma.current_tag_vifcode1().kind == VifCode::Kind::PC_PORT) {
    DmaTransfer transfers[20];
    for (int i = 0; i < render_state->num_vis_to_copy; i++) {
      transfers[i] = dma.read_and_advance();
      auto next0 = dma.read_and_advance();
      ASSERT(next0.size_bytes == 0);
    }

    for (int i = 0; i < render_state->num_vis_to_copy; i++) {
      if (transfers[i].size_bytes == 128 * 16) {
        if (render_state->use_occlusion_culling) {
          render_state->occlusion_vis[i].valid = true;
          memcpy(render_state->occlusion_vis[i].data, transfers[i].data, 128 * 16);
        }
      } else {
        ASSERT(transfers[i].size_bytes == 16);
      }
    }
#ifdef __ANDROID__
    // A42 probe: black terrain with TFRAG setup done — is the GOAL-side
    // occlusion vis string all-zero (update-vis! never completing) or
    // real? Popcount of each level's arriving vis bits, once per 5 s.
    {
      static int s_vis_log_ctr = 0;
      if ((s_vis_log_ctr++ % 300) == 0) {
        int pc[2] = {0, 0};
        for (int i = 0; i < render_state->num_vis_to_copy && i < 2; i++) {
          if (transfers[i].size_bytes == 128 * 16) {
            for (int b = 0; b < 128 * 16; b++) {
              pc[i] += __builtin_popcount(transfers[i].data[b]);
            }
          } else {
            pc[i] = -1;  // empty (level not active)
          }
        }
        fprintf(stderr, "A42-VIS l0=%d l1=%d occl=%d valid0=%d valid1=%d\n", pc[0], pc[1],
                (int)render_state->use_occlusion_culling, (int)render_state->occlusion_vis[0].valid,
                (int)render_state->occlusion_vis[1].valid);
      }
    }
#endif
  }

  if (dma.current_tag().kind == DmaTag::Kind::CALL) {
    // renderer didn't run, let's just get out of here.
    for (int i = 0; i < 4; i++) {
      dma.read_and_advance();
    }
    ASSERT(dma.current_tag_offset() == render_state->next_bucket);
    return;
  }

  std::string level_name;
  while (looks_like_tfrag_init(dma)) {
    handle_initialization(dma);
    if (level_name.empty()) {
      level_name = m_pc_port_data.level_name;
    } else if (level_name != m_pc_port_data.level_name) {
      ASSERT(false);
    }

    while (looks_like_tfragment_dma(dma)) {
      dma.read_and_advance();
    }
  }

  while (dma.current_tag_offset() != render_state->next_bucket) {
    dma.read_and_advance();
  }

  if (level_name.empty()) {
    return;
  }
  {
    setup_for_level(m_tree_kinds, level_name, render_state);
    TfragRenderSettings settings;

    settings.camera = m_pc_port_data.camera;
    settings.tree_idx = 0;
    if (render_state->occlusion_vis[m_level_id].valid) {
      settings.occlusion_culling = render_state->occlusion_vis[m_level_id].data;
    }

    update_render_state_from_pc_settings(render_state, m_pc_port_data);

    auto t3prof = prof.make_scoped_child("t3");
    render_matching_trees(lod(), m_tree_kinds, settings, render_state, t3prof);
  }

  while (dma.current_tag_offset() != render_state->next_bucket) {
    auto tag = dma.current_tag().print();
    dma.read_and_advance();
  }
}

void TFragment::draw_debug_window() {
  for (int i = 0; i < (int)m_cached_trees.at(lod()).size(); i++) {
    auto& tree = m_cached_trees.at(lod()).at(i);
    if (tree.kind == tfrag3::TFragmentTreeKind::INVALID) {
      continue;
    }
    ImGui::PushID(i);
    ImGui::Text("[%d] %10s", i, tfrag3::tfrag_tree_names[(int)m_cached_trees[lod()][i].kind]);
    ImGui::SameLine();
    ImGui::Checkbox("Allow?", &tree.allowed);
    ImGui::SameLine();
    ImGui::Checkbox("Force?", &tree.forced);
    ImGui::SameLine();
    ImGui::Checkbox("cull debug (slow)", &tree.cull_debug);
    ImGui::PopID();
    if (tree.rendered_this_frame) {
      ImGui::Checkbox("freeze itimes", &tree.freeze_itimes);
      ImGui::Text("  tris: %d draws: %d", tree.tris_this_frame, tree.draws_this_frame);
      for (int j = 0; j < 4; j++) {
        ImGui::Text(" itimes[%d] 0x%x 0x%x 0x%x 0x%x", j, tree.itimes_debug[j][0],
                    tree.itimes_debug[j][1], tree.itimes_debug[j][2], tree.itimes_debug[j][3]);
      }
    }
  }
}

void TFragment::init_shaders(ShaderLibrary& shaders) {
  m_uniforms.decal = glGetUniformLocation(shaders[ShaderId::TFRAG3].id(), "decal");
}

void TFragment::handle_initialization(DmaFollower& dma) {
  // Set up test (different between different renderers)
  auto setup_test = dma.read_and_advance();
  ASSERT(setup_test.vif0() == 0);
  ASSERT(setup_test.vifcode1().kind == VifCode::Kind::DIRECT);
  ASSERT(setup_test.vifcode1().immediate == 2);
  ASSERT(setup_test.size_bytes == 32);
  memcpy(m_test_setup, setup_test.data, 32);

  // matrix 0
  auto mat0_upload = dma.read_and_advance();
  unpack_to_stcycl(&m_buffered_data[0].pad[TFragDataMem::TFragMatrix0 * 16], mat0_upload,
                   VifCode::Kind::UNPACK_V4_32, 4, 4, 64, TFragDataMem::TFragMatrix0, false, false);

  // matrix 1
  auto mat1_upload = dma.read_and_advance();
  unpack_to_stcycl(&m_buffered_data[1].pad[TFragDataMem::TFragMatrix0 * 16], mat1_upload,
                   VifCode::Kind::UNPACK_V4_32, 4, 4, 64, TFragDataMem::TFragMatrix1, false, false);

  // data
  auto data_upload = dma.read_and_advance();
  (void)data_upload;

  // call the setup program
  auto mscal_setup = dma.read_and_advance();
  verify_mscal(mscal_setup, TFragProgMem::TFragSetup);

  auto pc_port_data = dma.read_and_advance();
  ASSERT(pc_port_data.size_bytes == sizeof(TfragPcPortData));
  memcpy(&m_pc_port_data, pc_port_data.data, sizeof(TfragPcPortData));
  m_pc_port_data.level_name[11] = '\0';
#ifndef __ANDROID__
  // A42: same dump available on desktop (env-gated) so the Android values
  // can be oracle-diffed field by field.
  static const bool s_a42_cam_dump = getenv("A42_CAM_DUMP") != nullptr;
#else
  static const bool s_a42_cam_dump = true;
#endif
  // A36 probe: tfrag submits 64k tris/frame on-device but the FBO stays
  // all-zero — if the GOAL-built camera block is zero/garbage, every vertex
  // degenerates. One-shot dump of what actually arrived.
  {
    // F1a: 3-shot at init PLUS a 10 s heartbeat (-HB) — the camera POSE
    // over time is the question (does the title course fly or park?).
    // cam1 row added: pitch lives in rows 1/2; trans is the camera position.
    static int s_cam_logged = 0;
    static int s_cam_hb = 0;
    const bool hb = s_a42_cam_dump && (s_cam_hb++ % 600) == 0;
    if (s_a42_cam_dump && (s_cam_logged < 3 || hb)) {
      if (s_cam_logged < 3) {
        s_cam_logged++;
      }
      auto& c = m_pc_port_data.camera;
      fprintf(stderr,
              "A36-TFRAG-CAM%s lvl=%s cam0=(%.3f %.3f %.3f %.3f) cam1=(%.3f %.3f %.3f %.3f) "
              "cam3=(%.3f %.3f %.3f %.3f) "
              "hvdf=(%.1f %.1f %.1f %.1f) trans=(%.1f %.1f %.1f) fog=(%.1f %.1f)\n",
              hb ? "-HB" : "", m_pc_port_data.level_name, c.camera[0].x(), c.camera[0].y(),
              c.camera[0].z(), c.camera[0].w(), c.camera[1].x(), c.camera[1].y(), c.camera[1].z(),
              c.camera[1].w(), c.camera[3].x(), c.camera[3].y(), c.camera[3].z(), c.camera[3].w(),
              c.hvdf_off.x(), c.hvdf_off.y(), c.hvdf_off.z(), c.hvdf_off.w(), c.trans.x(),
              c.trans.y(), c.trans.z(), c.fog.x(), c.fog.y());
    }
  }

  // setup double buffering.
  auto db_setup = dma.read_and_advance();
  ASSERT(db_setup.size_bytes == 0);
  ASSERT(db_setup.vifcode0().kind == VifCode::Kind::BASE &&
         db_setup.vifcode0().immediate == Buffer0_Start);
  ASSERT(db_setup.vifcode1().kind == VifCode::Kind::OFFSET &&
         db_setup.vifcode1().immediate == (Buffer1_Start - Buffer0_Start));
}

std::string TFragData::print() const {
  std::string result;
  result += fmt::format("fog: {}\n", fog.to_string_aligned());
  result += fmt::format("val: {}\n", val.to_string_aligned());
  result += fmt::format("str-gif: {}\n", str_gif.print());
  result += fmt::format("fan-gif: {}\n", fan_gif.print());
  result += fmt::format("ad-gif: {}\n", ad_gif.print());
  result += fmt::format("hvdf_offset: {}\n", hvdf_offset.to_string_aligned());
  result += fmt::format("hmge_scale: {}\n", hmge_scale.to_string_aligned());
  result += fmt::format("invh_scale: {}\n", invh_scale.to_string_aligned());
  result += fmt::format("ambient: {}\n", ambient.to_string_aligned());
  result += fmt::format("guard: {}\n", guard.to_string_aligned());
  result += fmt::format("k0s[0]: {}\n", k0s[0].to_string_aligned());
  result += fmt::format("k0s[1]: {}\n", k0s[1].to_string_aligned());
  result += fmt::format("k1s[0]: {}\n", k1s[0].to_string_aligned());
  result += fmt::format("k1s[1]: {}\n", k1s[1].to_string_aligned());
  return result;
}

void TFragment::update_load(const std::vector<tfrag3::TFragmentTreeKind>& tree_kinds,
                            const LevelData* loader_data) {
  const auto* lev_data = loader_data->level.get();
  discard_tree_cache();
  for (int geom = 0; geom < GEOM_MAX; ++geom) {
    m_cached_trees[geom].clear();
  }

  u32 time_of_day_count = 0;
  size_t vis_temp_len = 0;
  size_t max_draws = 0;
  size_t max_num_grps = 0;
  size_t max_inds = 0;

  for (int geom = 0; geom < GEOM_MAX; ++geom) {
    for (size_t tree_idx = 0; tree_idx < lev_data->tfrag_trees[geom].size(); tree_idx++) {
      const auto& tree = lev_data->tfrag_trees[geom][tree_idx];

      if (std::find(tree_kinds.begin(), tree_kinds.end(), tree.kind) != tree_kinds.end()) {
        auto& tree_cache = m_cached_trees[geom].emplace_back();
        tree_cache.kind = tree.kind;
        max_draws = std::max(tree.draws.size(), max_draws);
        size_t num_grps = 0;
        for (auto& draw : tree.draws) {
          num_grps += draw.vis_groups.size();
        }
        max_num_grps = std::max(max_num_grps, num_grps);
        max_inds = std::max(tree.unpacked.indices.size(), max_inds);
        time_of_day_count = std::max(tree.colors.color_count, time_of_day_count);
        u32 verts = tree.packed_vertices.vertices.size();
        glGenVertexArrays(1, &tree_cache.vao);
        glBindVertexArray(tree_cache.vao);
        // glGenBuffers(1, &tree_cache.vertex_buffer);
        tree_cache.vertex_buffer = loader_data->tfrag_vertex_data[geom][tree_idx];
        tree_cache.vert_count = verts;
        tree_cache.draws = &tree.draws;  // todo - should we just copy this?
        tree_cache.colors = &tree.colors;
        tree_cache.vis = &tree.bvh;
        tree_cache.index_data = tree.unpacked.indices.data();
        tree_cache.draw_mode = tree.use_strips ? GL_TRIANGLE_STRIP : GL_TRIANGLES;
        vis_temp_len = std::max(vis_temp_len, tree.bvh.vis_nodes.size());
        glBindBuffer(GL_ARRAY_BUFFER, tree_cache.vertex_buffer);
        //            glBufferData(GL_ARRAY_BUFFER, verts * sizeof(tfrag3::PreloadedVertex),
        //            nullptr,
        //                         GL_STREAM_DRAW);
        glEnableVertexAttribArray(0);
        glEnableVertexAttribArray(1);
        glEnableVertexAttribArray(2);

        glVertexAttribPointer(0,                                // location 0 in the shader
                              3,                                // 3 values per vert
                              GL_FLOAT,                         // floats
                              GL_FALSE,                         // normalized
                              sizeof(tfrag3::PreloadedVertex),  // stride
                              (void*)offsetof(tfrag3::PreloadedVertex, x)  // offset (0)
        );

        glVertexAttribPointer(1,                                // location 1 in the shader
                              3,                                // 3 values per vert
                              GL_FLOAT,                         // floats
                              GL_FALSE,                         // normalized
                              sizeof(tfrag3::PreloadedVertex),  // stride
                              (void*)offsetof(tfrag3::PreloadedVertex, s)  // offset (0)
        );

        glVertexAttribIPointer(2,                                // location 2 in the shader
                               2,                                // 1 values per vert
                               GL_UNSIGNED_SHORT,                // u16
                               sizeof(tfrag3::PreloadedVertex),  // stride
                               (void*)offsetof(tfrag3::PreloadedVertex, color_index)  // offset (0)
        );
        glGenBuffers(1, &tree_cache.single_draw_index_buffer);
        glGenBuffers(1, &tree_cache.index_buffer);
        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree_cache.index_buffer);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, tree.unpacked.indices.size() * sizeof(u32),
                     tree.unpacked.indices.data(), GL_STREAM_DRAW);

        glGenTextures(1, &tree_cache.time_of_day_texture);
        // A36: Wx1 2D LUT — GLES has no glTexImage1D (NULL loader slot on
        // arm64 device, BLR-to-0). texelFetch(ivec2(i,0)) in tfrag3.vert is
        // texel-exact on desktop GL too. GL_UNSIGNED_BYTE order matches the
        // old REV upload on little-endian.
        glBindTexture(GL_TEXTURE_2D, tree_cache.time_of_day_texture);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, TIME_OF_DAY_COLOR_COUNT, 1, 0, GL_RGBA,
                     GL_UNSIGNED_BYTE, nullptr);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

        // Gperf-particles round 3: second (ping-pong) TOD texture, identical.
        glGenTextures(1, &tree_cache.time_of_day_texture_pp);
        glBindTexture(GL_TEXTURE_2D, tree_cache.time_of_day_texture_pp);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, TIME_OF_DAY_COLOR_COUNT, 1, 0, GL_RGBA,
                     GL_UNSIGNED_BYTE, nullptr);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
        tree_cache.tod_flip = 0;
        tree_cache.tod_current = tree_cache.time_of_day_texture;
        tree_cache.tod_cache_valid = false;  // Gperf-particles: fresh level re-interpolates
        glBindVertexArray(0);
      }
    }
  }

  m_cache.vis_temp.resize(vis_temp_len);
  m_cache.multidraw_offset_per_stripdraw.resize(max_draws);
  m_cache.multidraw_count_buffer.resize(max_num_grps);
  m_cache.multidraw_index_offset_buffer.resize(max_num_grps);
  m_cache.draw_idx_temp.resize(max_draws);
  m_cache.index_temp.resize(max_inds);
  ASSERT(time_of_day_count <= TIME_OF_DAY_COLOR_COUNT);
}

bool TFragment::setup_for_level(const std::vector<tfrag3::TFragmentTreeKind>& tree_kinds,
                                const std::string& level,
                                SharedRenderState* render_state) {
  // make sure we have the level data.
  Timer tfrag3_setup_timer;
  auto lev_data = render_state->loader->get_tfrag3_level(level);

  if (!lev_data) {
    // not loaded
    m_has_level = false;
    m_textures = nullptr;
    m_level_name = "";
    discard_tree_cache();
    return false;
  }

  if (m_has_level && lev_data->load_id != m_load_id) {
    m_has_level = false;
    m_textures = nullptr;
    m_level_name = "";
    discard_tree_cache();
    return setup_for_level(tree_kinds, level, render_state);
  }

  m_load_id = lev_data->load_id;

  if (m_level_name != level) {
    update_load(tree_kinds, lev_data);
    m_has_level = true;
    m_textures = &lev_data->textures;
    m_level_name = level;
  } else {
    m_has_level = true;
  }

  if (tfrag3_setup_timer.getMs() > 5) {
    lg::info("TFRAG setup: {:.1f}ms", tfrag3_setup_timer.getMs());
  }

  return m_has_level;
}

void TFragment::render_tree(int geom,
                            const TfragRenderSettings& settings,
                            SharedRenderState* render_state,
                            ScopedProfilerNode& prof) {
  if (!m_has_level) {
    return;
  }
  auto& tree = m_cached_trees.at(geom).at(settings.tree_idx);
  [[maybe_unused]] const auto* itimes = settings.camera.itimes;

  if (tree.freeze_itimes) {
    itimes = tree.itimes_debug;
  } else {
    for (int i = 0; i < 4; i++) {
      tree.itimes_debug[i] = settings.camera.itimes[i];
    }
  }

  ASSERT(tree.kind != tfrag3::TFragmentTreeKind::INVALID);

  if (m_color_result.size() < tree.colors->color_count) {
    m_color_result.resize(tree.colors->color_count);
  }
  // Gperf-particles: memoize the TOD interp+upload — when itimes is unchanged
  // vs the last cached value, tod_current already holds the correct palette, so
  // skip both the interpolation and the glTexSubImage2D upload (night hot-path).
  // Behind the perf_tod_skip kill switch; result is byte-identical.
  {
    bool tod_same = tree.tod_cache_valid &&
        memcmp(tree.tod_cache_itimes, settings.camera.itimes, 16 * sizeof(s32)) == 0;
    if (render_state->perf_tod_skip && tod_same) {
      // Gperf-particles: itimes unchanged -> skip interp + palette upload;
      // tod_current retains last frame's palette (byte-identical result).
    } else {
      interp_time_of_day(settings.camera.itimes, *tree.colors, m_color_result.data());
      // Gperf-particles round 3: ping-pong the target TOD texture (flag ON) so the
      // upload does not touch the texture last frame's draws are still sampling on
      // Adreno; publish it via tod_current for the bind below. Flag OFF =>
      // tod_current == time_of_day_texture (byte-identical old path). TFragment has
      // exactly this one TOD bind per tree, so no other site can go stale.
      if (render_state->perf_tod_pingpong) {
        tree.tod_flip ^= 1;
        tree.tod_current = tree.tod_flip ? tree.time_of_day_texture_pp : tree.time_of_day_texture;
      } else {
        tree.tod_current = tree.time_of_day_texture;
      }
      glActiveTexture(GL_TEXTURE10);
      // A36: Wx1 2D LUT (see update_load) — REV == BYTE order on little-endian.
      glBindTexture(GL_TEXTURE_2D, tree.tod_current);
      glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, tree.colors->color_count, 1, GL_RGBA,
                      GL_UNSIGNED_BYTE, m_color_result.data());
      memcpy(tree.tod_cache_itimes, settings.camera.itimes, 16 * sizeof(s32));
      tree.tod_cache_valid = true;
    }
  }

  first_tfrag_draw_setup(settings.camera, render_state, ShaderId::TFRAG3);

  glBindVertexArray(tree.vao);
  glBindBuffer(GL_ARRAY_BUFFER, tree.vertex_buffer);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,
               render_state->no_multidraw ? tree.single_draw_index_buffer : tree.index_buffer);
  glActiveTexture(GL_TEXTURE0);
#ifdef __ANDROID__
  // GLES has no settable restart index (glPrimitiveRestartIndex is NULL in
  // the loader — A36 run-23 BLR-to-0 on the first tfrag render). The
  // fixed-index mode restarts on all-1s, which IS UINT32_MAX for our u32
  // index buffers — identical semantics.
  glEnable(GL_PRIMITIVE_RESTART_FIXED_INDEX);
#else
  glEnable(GL_PRIMITIVE_RESTART);
  glPrimitiveRestartIndex(UINT32_MAX);
#endif

  cull_check_all_slow(settings.camera.planes, tree.vis->vis_nodes, settings.occlusion_culling,
                      m_cache.vis_temp.data());

  u32 total_tris;
  if (render_state->no_multidraw) {
    u32 idx_buffer_size = make_index_list_from_vis_string(
        m_cache.draw_idx_temp.data(), m_cache.index_temp.data(), *tree.draws, m_cache.vis_temp,
        tree.index_data, &total_tris);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, idx_buffer_size * sizeof(u32), m_cache.index_temp.data(),
                 GL_STREAM_DRAW);
  } else {
    total_tris = make_multidraws_from_vis_string(
        m_cache.multidraw_offset_per_stripdraw.data(), m_cache.multidraw_count_buffer.data(),
        m_cache.multidraw_index_offset_buffer.data(), *tree.draws, m_cache.vis_temp);
  }

  prof.add_tri(total_tris);
#ifdef __ANDROID__
  // A42 probe: where do the village tris die — culling (vis_temp all
  // zero), index-building, TOD colors (alpha-test kill), GL error, or
  // after rasterization? Once per 5 s per geom.
  bool a42_log_this_frame = false;
  {
    static int s_tree_log_ctr = 0;
    if ((s_tree_log_ctr++ % 300) == 0) {
      a42_log_this_frame = true;
      int vis_cnt = 0;
      for (size_t i = 0; i < tree.vis->vis_nodes.size(); i++) {
        if (m_cache.vis_temp[i]) {
          vis_cnt++;
        }
      }
      const u8* c0 = (const u8*)m_color_result.data();
      fprintf(stderr,
              "A42-TFTREE lvl=%s tree=%d kind=%d nodes=%d vis=%d draws=%d tris=%u occl=%d "
              "fog=(%.6f %.3f %.3f) hvdfw=%.3f tod0=%02x%02x%02x%02x tod1=%02x%02x%02x%02x "
              "itimes0=%08x\n",
              m_level_name.c_str(), settings.tree_idx, (int)tree.kind,
              (int)tree.vis->vis_nodes.size(), vis_cnt, (int)tree.draws->size(), total_tris,
              settings.occlusion_culling ? 1 : 0, settings.camera.fog.x(),
              settings.camera.fog.y(), settings.camera.fog.z(), settings.camera.hvdf_off.w(),
              c0[0], c0[1], c0[2], c0[3], c0[4], c0[5], c0[6], c0[7],
              settings.camera.itimes[0].x());
    }
  }
#endif

  // Gperf-particles: per-draw GL state cache (flag-off = identical old path).
  BgDrawStateCache draw_state_cache;
  GLuint bound_tex = 0;

  if (render_state->no_multidraw && render_state->batch_singledraw) {
    // Gperf-batching: merge consecutive draws that share texture+mode into one
    // glDrawElements. The single-draw index list packs draw ranges adjacently
    // (contiguity re-checked per merge), and every strip already ends with a
    // primitive-restart index (TFrag3Data.cpp unpack), so concatenated ranges
    // keep their strips separate. Draws needing a double-draw pass are issued
    // alone to preserve the exact original draw order.
    ASSERT(m_textures);
    const auto& alpha_u = tfrag_alpha_uniforms(render_state->shaders[ShaderId::TFRAG3].id());
    size_t draw_idx = 0;
    while (draw_idx < tree.draws->size()) {
      const auto& draw = tree.draws->operator[](draw_idx);
      const auto& singledraw_indices = m_cache.draw_idx_temp[draw_idx];
      if (singledraw_indices.second == 0) {
        draw_idx++;
        continue;
      }

      s32 tex_idx = draw.tree_tex_id;
      if (tex_idx >= 0) {
        bound_tex = m_textures->at(tex_idx);
      } else {
        bound_tex = m_anim_slot_array->at(-(tex_idx + 1));
      }
      glBindTexture(GL_TEXTURE_2D, bound_tex);
      auto double_draw = setup_tfrag_shader_cached(render_state, draw.mode, ShaderId::TFRAG3,
                                                   bound_tex, draw_state_cache);
      glUniform1i(m_uniforms.decal, draw.mode.get_decal() ? 1 : 0);

      int first = singledraw_indices.first;
      int count = singledraw_indices.second;
      tree.tris_this_frame += draw.num_triangles;
      tree.draws_this_frame++;
      size_t next = draw_idx + 1;
      if (double_draw.kind == DoubleDrawKind::NONE) {
        while (next < tree.draws->size()) {
          const auto& d2 = tree.draws->operator[](next);
          const auto& sd2 = m_cache.draw_idx_temp[next];
          if (sd2.second == 0) {
            next++;
            continue;
          }
          if (d2.tree_tex_id != draw.tree_tex_id || d2.mode.as_int() != draw.mode.as_int() ||
              sd2.first != first + count) {
            break;
          }
          count += sd2.second;
          tree.tris_this_frame += d2.num_triangles;
          tree.draws_this_frame++;
          next++;
        }
      }

      prof.add_draw_call();
      glDrawElements(tree.draw_mode, count, GL_UNSIGNED_INT, (void*)(first * sizeof(u32)));

      if (double_draw.kind == DoubleDrawKind::AFAIL_NO_DEPTH_WRITE) {
        prof.add_draw_call();
        glUniform1f(alpha_u.alpha_min, -10.f);
        glUniform1f(alpha_u.alpha_max, double_draw.aref_second);
        glDepthMask(GL_FALSE);
        // depth-mask toggled: cached mode's depth state is now stale.
        draw_state_cache.valid = false;
        glDrawElements(tree.draw_mode, count, GL_UNSIGNED_INT, (void*)(first * sizeof(u32)));
      }
      draw_idx = next;
    }
  } else {
  for (size_t draw_idx = 0; draw_idx < tree.draws->size(); draw_idx++) {
    const auto& draw = tree.draws->operator[](draw_idx);
    const auto& multidraw_indices = m_cache.multidraw_offset_per_stripdraw[draw_idx];
    const auto& singledraw_indices = m_cache.draw_idx_temp[draw_idx];

    if (render_state->no_multidraw) {
      if (singledraw_indices.second == 0) {
        continue;
      }
    } else {
      if (multidraw_indices.second == 0) {
        continue;
      }
    }

    ASSERT(m_textures);
    s32 tex_idx = draw.tree_tex_id;
    if (tex_idx >= 0) {
      bound_tex = m_textures->at(draw.tree_tex_id);
    } else {
      bound_tex = m_anim_slot_array->at(-(tex_idx + 1));
    }
    glBindTexture(GL_TEXTURE_2D, bound_tex);
    auto double_draw = setup_tfrag_shader_cached(render_state, draw.mode, ShaderId::TFRAG3,
                                                 bound_tex, draw_state_cache);
    glUniform1i(m_uniforms.decal, draw.mode.get_decal() ? 1 : 0);
    tree.tris_this_frame += draw.num_triangles;
    tree.draws_this_frame++;

    prof.add_draw_call();
    if (render_state->no_multidraw) {
      glDrawElements(tree.draw_mode, singledraw_indices.second, GL_UNSIGNED_INT,
                     (void*)(singledraw_indices.first * sizeof(u32)));
    } else {
      glMultiDrawElements(tree.draw_mode, &m_cache.multidraw_count_buffer[multidraw_indices.first],
                          GL_UNSIGNED_INT,
                          &m_cache.multidraw_index_offset_buffer[multidraw_indices.first],
                          multidraw_indices.second);
    }

    switch (double_draw.kind) {
      case DoubleDrawKind::NONE:
        break;
      case DoubleDrawKind::AFAIL_NO_DEPTH_WRITE: {
        prof.add_draw_call();
        const auto& afail_u = tfrag_alpha_uniforms(render_state->shaders[ShaderId::TFRAG3].id());
        if (afail_u.alpha_min != -1) {
          glUniform1f(afail_u.alpha_min, -10.f);
        }
        if (afail_u.alpha_max != -1) {
          glUniform1f(afail_u.alpha_max, double_draw.aref_second);
        }
        glDepthMask(GL_FALSE);
        // depth-mask toggled: cached mode's depth state is now stale.
        draw_state_cache.valid = false;
        if (render_state->no_multidraw) {
          glDrawElements(tree.draw_mode, singledraw_indices.second, GL_UNSIGNED_INT,
                         (void*)(singledraw_indices.first * sizeof(u32)));
        } else {
          glMultiDrawElements(
              tree.draw_mode, &m_cache.multidraw_count_buffer[multidraw_indices.first],
              GL_UNSIGNED_INT, &m_cache.multidraw_index_offset_buffer[multidraw_indices.first],
              multidraw_indices.second);
        }
        break;
      } // AFAIL_NO_DEPTH_WRITE
      default:
        ASSERT(false);
    }
  }
  }
#ifdef __ANDROID__
  // A42 probe tail: GL error state + an FBO readback where the village
  // should be (left third, mid height) right after this tree's draws.
  if (a42_log_this_frame) {
    GLenum err = glGetError();
    GLint cur_fb = -1, vp[4] = {0, 0, 0, 0};
    glGetIntegerv(GL_DRAW_FRAMEBUFFER_BINDING, &cur_fb);
    glGetIntegerv(GL_VIEWPORT, vp);
    u8 px[4] = {0, 0, 0, 0};
    glReadPixels(vp[2] / 6, vp[3] / 2, 1, 1, GL_RGBA, GL_UNSIGNED_BYTE, px);
    const auto& d0 = tree.draws->empty() ? tfrag3::StripDraw() : tree.draws->front();
    fprintf(stderr,
            "A42-TFGL err=0x%x fb=%d vp=%dx%d px@L=%02x%02x%02x%02x draw0tex=%d mode=0x%llx "
            "drawn=%d/%d\n",
            err, cur_fb, vp[2], vp[3], px[0], px[1], px[2], px[3], (int)d0.tree_tex_id,
            (unsigned long long)d0.mode.as_int(), tree.draws_this_frame, (int)tree.draws->size());
  }
#endif
  glBindVertexArray(0);
}

/*!
 * Render all trees with settings for the given tree.
 * This is intended to be used only for debugging when we can't easily get commands for all trees
 * working.
 */
void TFragment::render_all_trees(int geom,
                                 const TfragRenderSettings& settings,
                                 SharedRenderState* render_state,
                                 ScopedProfilerNode& prof) {
  TfragRenderSettings settings_copy = settings;
  for (size_t i = 0; i < m_cached_trees[geom].size(); i++) {
    if (m_cached_trees[geom][i].kind != tfrag3::TFragmentTreeKind::INVALID) {
      settings_copy.tree_idx = i;
      render_tree(geom, settings_copy, render_state, prof);
    }
  }
}

void TFragment::render_matching_trees(int geom,
                                      const std::vector<tfrag3::TFragmentTreeKind>& trees,
                                      const TfragRenderSettings& settings,
                                      SharedRenderState* render_state,
                                      ScopedProfilerNode& prof) {
  TfragRenderSettings settings_copy = settings;
  for (size_t i = 0; i < m_cached_trees[geom].size(); i++) {
    auto& tree = m_cached_trees[geom][i];
    tree.reset_stats();
    if (!tree.allowed) {
      continue;
    }
    if (std::find(trees.begin(), trees.end(), tree.kind) != trees.end() || tree.forced) {
      tree.rendered_this_frame = true;
      settings_copy.tree_idx = i;
      render_tree(geom, settings_copy, render_state, prof);
      if (tree.cull_debug) {
        render_tree_cull_debug(settings_copy, render_state, prof);
      }
    }
  }
}

void TFragment::discard_tree_cache() {
  m_textures = nullptr;
  for (int geom = 0; geom < GEOM_MAX; ++geom) {
    for (auto& tree : m_cached_trees[geom]) {
      if (tree.kind != tfrag3::TFragmentTreeKind::INVALID) {
        glBindTexture(GL_TEXTURE_1D, tree.time_of_day_texture);
#ifdef __ANDROID__
        fprintf(stderr, "F1E-DELTEX site=tfrag-tod tex=%u\n", (unsigned)tree.time_of_day_texture);
#endif
        glDeleteTextures(1, &tree.time_of_day_texture);
        // Gperf-particles round 3: delete the ping-pong TOD texture too.
        glDeleteTextures(1, &tree.time_of_day_texture_pp);
        glDeleteBuffers(1, &tree.single_draw_index_buffer);
        glDeleteBuffers(1, &tree.index_buffer);
        glDeleteVertexArrays(1, &tree.vao);
      }
    }
    m_cached_trees[geom].clear();
  }
}

namespace {

float frac(float in) {
  return in - (int)in;
}

void debug_vis_draw(int first_root,
                    int tree,
                    int num,
                    int depth,
                    const std::vector<tfrag3::VisNode>& nodes,
                    std::vector<TFragment::DebugVertex>& verts_out) {
  for (int ki = 0; ki < num; ki++) {
    auto& node = nodes.at(ki + tree - first_root);
    ASSERT(node.child_id != 0xffff);
    math::Vector4f rgba{frac(0.4 * depth), frac(0.7 * depth), frac(0.2 * depth), 0.06};
    math::Vector3f center = node.bsphere.xyz();
    float rad = node.bsphere.w();
    math::Vector3f corners[8] = {center, center, center, center};
    corners[0].x() += rad;
    corners[1].x() += rad;
    corners[2].x() -= rad;
    corners[3].x() -= rad;

    corners[0].y() += rad;
    corners[1].y() -= rad;
    corners[2].y() += rad;
    corners[3].y() -= rad;

    for (int i = 0; i < 4; i++) {
      corners[i + 4] = corners[i];
      corners[i].z() += rad;
      corners[i + 4].z() -= rad;
    }

    if (true) {
      for (int i : {0, 4}) {
        verts_out.push_back({corners[0 + i], rgba});
        verts_out.push_back({corners[1 + i], rgba});
        verts_out.push_back({corners[2 + i], rgba});

        verts_out.push_back({corners[1 + i], rgba});  // 0
        verts_out.push_back({corners[3 + i], rgba});
        verts_out.push_back({corners[2 + i], rgba});
      }

      for (int i : {2, 6, 7, 2, 3, 7, 0, 4, 5, 0, 5, 1, 0, 6, 4, 0, 6, 2, 1, 3, 7, 1, 5, 7}) {
        verts_out.push_back({corners[i], rgba});
      }

      constexpr int border0[12] = {0, 4, 6, 2, 2, 6, 3, 7, 0, 1, 2, 3};
      constexpr int border1[12] = {1, 5, 7, 3, 0, 4, 1, 5, 4, 5, 6, 7};
      rgba.w() = 1.0;

      for (int i = 0; i < 12; i++) {
        auto p0 = corners[border0[i]];
        auto p1 = corners[border1[i]];
        auto diff = (p1 - p0).normalized();
        math::Vector3f px = diff.z() == 0 ? math::Vector3f{1, 0, 1} : math::Vector3f{0, 1, 1};
        auto off = diff.cross(px) * 2000;

        verts_out.push_back({p0 + off, rgba});
        verts_out.push_back({p0 - off, rgba});
        verts_out.push_back({p1 - off, rgba});

        verts_out.push_back({p0 + off, rgba});
        verts_out.push_back({p1 + off, rgba});
        verts_out.push_back({p1 - off, rgba});
      }
    }

    if (node.flags) {
      debug_vis_draw(first_root, node.child_id, node.num_kids, depth + 1, nodes, verts_out);
    }
  }
}

}  // namespace

void TFragment::render_tree_cull_debug(const TfragRenderSettings& settings,
                                       SharedRenderState* render_state,
                                       ScopedProfilerNode& prof) {
  // generate debug verts:
  m_debug_vert_data.clear();
  auto& tree = m_cached_trees.at(settings.tree_idx).at(lod());

  debug_vis_draw(tree.vis->first_root, tree.vis->first_root, tree.vis->num_roots, 1,
                 tree.vis->vis_nodes, m_debug_vert_data);

  render_state->shaders[ShaderId::TFRAG3_NO_TEX].activate();
  glUniformMatrix4fv(
      glGetUniformLocation(render_state->shaders[ShaderId::TFRAG3_NO_TEX].id(), "camera"), 1,
      GL_FALSE, settings.camera.camera[0].data());
  glUniform4f(
      glGetUniformLocation(render_state->shaders[ShaderId::TFRAG3_NO_TEX].id(), "hvdf_offset"),
      settings.camera.hvdf_off[0], settings.camera.hvdf_off[1], settings.camera.hvdf_off[2],
      settings.camera.hvdf_off[3]);
  glUniform1f(
      glGetUniformLocation(render_state->shaders[ShaderId::TFRAG3_NO_TEX].id(), "fog_constant"),
      settings.camera.fog.x());
  // glDisable(GL_DEPTH_TEST);
  glEnable(GL_DEPTH_TEST);
  glDepthFunc(GL_GEQUAL);
  glEnable(GL_BLEND);
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);  // ?
  glDepthMask(GL_FALSE);

  glBindVertexArray(m_debug_vao);
  glBindBuffer(GL_ARRAY_BUFFER, m_debug_verts);

  int remaining = m_debug_vert_data.size();
  int start = 0;

  while (remaining > 0) {
    int to_do = std::min(DEBUG_TRI_COUNT * 3, remaining);

    glBufferSubData(GL_ARRAY_BUFFER, 0, to_do * sizeof(DebugVertex),
                    m_debug_vert_data.data() + start);
    glDrawArrays(GL_TRIANGLES, 0, to_do);
    prof.add_draw_call();
    prof.add_tri(to_do / 3);

    remaining -= to_do;
    start += to_do;
  }
}
