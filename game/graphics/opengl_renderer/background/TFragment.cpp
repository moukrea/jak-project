#include "TFragment.h"

#include <bit>
#include <cstdio>
#include <cstring>

#include "game/graphics/opengl_renderer/dma_helpers.h"
#include "game/kernel/jak2/kscheme.h"

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
              pc[i] += std::popcount(static_cast<unsigned char>(transfers[i].data[b]));
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
  // Grecharged-grass-overhang2: resolve the fringe alpha textures the near droop replaces.
  // Grecharged-grass-overhang7: gate widened from "training" to the grass allowlist — the owner
  // plays at Sentinel Beach, which uses the same bch-* textures and now gets the droop/fall tail.
  m_fringe_tex_a = m_fringe_tex_b = -1;
  if (grass_level_enabled(lev_data->level_name)) {
    for (size_t ti = 0; ti < lev_data->textures.size(); ++ti) {
      const auto& tn = lev_data->textures[ti].debug_name;
      if (tn == "bch-grassfringe") {
        m_fringe_tex_a = (s32)ti;
      } else if (tn == "bch-leafyground-hang-2x1") {
        m_fringe_tex_b = (s32)ti;
      }
    }
  }
#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials: resolve every texture in this level that has a
  // registered PBR material set (no level-name gating).
  m_pbr_draws.clear();
  for (size_t ti = 0; ti < lev_data->textures.size(); ++ti) {
    if (const auto* maps = custom_tex::find_pbr_material(lev_data->textures[ti].debug_name)) {
      // Grecharged-pbr-realtime-fusion ROUND 20: measure THIS material's authored UV density from
      // the level's own geometry, so the tess displacement uses the material's real feature size
      // instead of the shaders' hardcoded 0.5 tiles/m. 0 = not enough samples => keep the old 0.5.
      u32 nsamp = 0;
      float dens = measure_uv_density_tfrag(*lev_data, (s32)ti, &nsamp);
      if (dens <= 0.f) {
        dens = 0.5f;
      }
      m_pbr_draws.push_back({(s32)ti, *maps, dens});
      // [pom] device diagnostic: the measured density is geometry-derived, so this is the only
      // place that knows it — hand it to the diag registry the pbr_tan_diag.txt writer reads.
      custom_tex::pbr_pom_diag_note(lev_data->textures[ti].debug_name, *maps, dens);
      lg::info(
          "pbr uv density: {} tiles/m={:.3f} tile={:.1f}cm (shader assumed 0.5 => 200.0cm, ratio "
          "{:.2f}x) samples={}",
          lev_data->textures[ti].debug_name, dens, 100.f / dens, dens / 0.5f, nsamp);
    }
  }
  if (!m_pbr_draws.empty()) {
    lg::info("Grecharged-pbr-materials: level {} has {} PBR material(s)", lev_data->level_name,
             m_pbr_draws.size());
  }
#endif

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
#ifdef OG_FEAT_PBR
        tree_cache.index_count = (u32)tree.unpacked.indices.size();
#endif
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

        // Grecharged-directional-ambient ROOT-CAUSE FIX: smooth per-vertex normal (2-10-10-10),
        // reconstructed at load in TfragTree::unpack(). Feeds the realtime-lighting smooth-normal
        // path; harmless (unread) on the stock path, matching the TIE VAO which already binds this.
        glEnableVertexAttribArray(3);
        glVertexAttribPointer(3,                                // location 3 in the shader
                              4,                                // 2-10-10-10 packed
                              GL_INT_2_10_10_10_REV,            // signed 10-bit per component
                              GL_TRUE,                          // normalized to [-1, 1]
                              sizeof(tfrag3::PreloadedVertex),  // stride
                              (void*)offsetof(tfrag3::PreloadedVertex, nor)  // offset
        );
        // Grecharged-mesh-consolidation: per-vertex SEAM WEIGHT (1 = displace normally, 0 = do not
        // displace). mesh_consolidate() zeroes it at boundaries whose two sides cannot displace
        // identically, so the tessellation evaluation shader can fade displacement to exactly zero
        // along a shared edge on BOTH sides — that is what closes the see-through slits. Bound here
        // (before the tangent VBO swaps GL_ARRAY_BUFFER below) so it reads the vertex buffer.
        glEnableVertexAttribArray(6);
        glVertexAttribPointer(6, 1, GL_UNSIGNED_SHORT, GL_TRUE, sizeof(tfrag3::PreloadedVertex),
                              (void*)offsetof(tfrag3::PreloadedVertex, seam_w));
        // REOPEN#7: per-vertex tangent at location 5 (free on the tfrag VAO) from the parallel
        // tangent VBO => the PBR frag builds a CONTINUOUS TBN (no screen-derivative cracks). Uses
        // the SAME [geom][tree_idx] index as tree_cache.vertex_buffer above.
        glBindBuffer(GL_ARRAY_BUFFER, loader_data->tfrag_tangent_data[geom][tree_idx]);
        glEnableVertexAttribArray(5);
        glVertexAttribPointer(5, 4, GL_FLOAT, GL_FALSE, sizeof(float) * 4, (void*)0);
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

#ifdef OG_FEAT_PBR
  // REOPEN #3 TESSELLATION: route the MAIN OPAQUE COLOR pass through the tess program when
  // Displacement == Tessellation (mode 2), the context supports the tess stages, and PBR
  // materials are enabled (the same gate that governs PbrDrawBinder use — the tess stages only
  // do anything when a PBR height map is bound per-draw). Shadow/depth passes and the rt-off
  // fallback stay on the plain TFRAG3 program (visual-only displacement on the color pass;
  // caveat: the sun shadow map is cast from the UN-displaced geometry, so a displaced ridge's
  // self-shadow can be off by the displacement height — acceptable for v1, small vs the ~1 m
  // relief). Only for opaque tfrag kinds (the tess index expansion + patch cost is pointless on
  // transparent trees).
  const bool tess_supported = gl_context_supports_tessellation();
  const bool tess_pbr_gate = Gfx::recharged_active(Gfx::g_global_settings.recharged_pbr_enable);
  // OWNER 2026-07-26 ("bah elle devrait pouvoir tourner partout !"): the kind allowlist was a
  // second source of flat chunks — TRANS/LOWRES/WATER trees could never be tessellated whatever
  // their maps. Every tfrag tree kind is eligible now; the per-draw `u_pbr_mode & 16` test in the
  // tess-eval is the real gate (a draw with no height map displaces by zero anyway) and the tesc
  // distance law already collapses far patches to level 1, so the cost stays bounded. This
  // supersedes the "only for opaque tfrag kinds" note above: NORMAL, TRANS, DIRT, ICE, LOWRES,
  // LOWRES_TRANS and WATER all qualify — only the INVALID sentinel is excluded.
  const bool tess_kind_eligible = tree.kind != tfrag3::TFragmentTreeKind::INVALID;
  // Driver-defensive: require the tess PROGRAM to have actually built+linked (gl_tfrag3_tess_
  // program_ok) in addition to the per-shader .okay() and the capability query. A driver that
  // advertises tessellation but leaves glPatchParameteri unresolved would otherwise crash here.
  const bool use_tess = Gfx::g_global_settings.recharged_pbr_displacement == 2 && tess_supported &&
                        gl_tfrag3_tess_program_ok() && tess_pbr_gate && tess_kind_eligible &&
                        render_state->shaders[ShaderId::TFRAG3_TESS].okay();
  const ShaderId tfrag_shader_id = use_tess ? ShaderId::TFRAG3_TESS : ShaderId::TFRAG3;
#else
  const ShaderId tfrag_shader_id = ShaderId::TFRAG3;
#endif

  first_tfrag_draw_setup(settings.camera, render_state, tfrag_shader_id);

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
#ifdef OG_FEAT_PBR
  // Round-4 mandate B: index count of the buffer currently bound to
  // GL_ELEMENT_ARRAY_BUFFER, for the sun shadow depth pass below.
  //   no_multidraw path: the freshly-built single-draw index list (length = idx_buffer_size).
  //   multidraw path: the resident static full index buffer (tree.index_count, from load).
  u32 pbr_depth_index_count = 0;
#endif
  if (render_state->no_multidraw) {
    u32 idx_buffer_size = make_index_list_from_vis_string(
        m_cache.draw_idx_temp.data(), m_cache.index_temp.data(), *tree.draws, m_cache.vis_temp,
        tree.index_data, &total_tris);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, idx_buffer_size * sizeof(u32), m_cache.index_temp.data(),
                 GL_STREAM_DRAW);
#ifdef OG_FEAT_PBR
    pbr_depth_index_count = idx_buffer_size;
#endif
  } else {
    total_tris = make_multidraws_from_vis_string(
        m_cache.multidraw_offset_per_stripdraw.data(), m_cache.multidraw_count_buffer.data(),
        m_cache.multidraw_index_offset_buffer.data(), *tree.draws, m_cache.vis_temp);
#ifdef OG_FEAT_PBR
    pbr_depth_index_count = tree.index_count;
#endif
  }

  prof.add_tri(total_tris);

#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials round-4 mandate B: sun shadow depth pass. Perf-gated — only
  // runs when a PBR material is registered in this level (m_pbr_draws non-empty) and the
  // runtime PBR toggle is on. Only for NORMAL tfrag geometry (kind == NORMAL). The tree
  // VAO + element buffer are already bound; primitive restart is enabled process-wide for
  // these strips (see the glEnable(GL_PRIMITIVE_RESTART[_FIXED_INDEX]) above). Renders the
  // camera-vis-culled geometry into the 1024 depth FBO from the mood-sun direction, in the
  // SAME camera-relative-meters space as the tfrag3.vert v_fringe_rel varying.
  // begin_frame runs for EVERY tree kind (not just NORMAL casters): the frame transition
  // inside it promotes last frame's completed map to the read side, which receivers of
  // any kind need before their draws sample it.
  // Round-5 addendum 2 (mandate F, world-wide): no m_pbr_draws gate — the sun shadow +
  // world relight apply to the whole world when the feature is on, not just levels with
  // a registered PBR material.
  const bool pbr_shadow_frame_ok =
      (Gfx::recharged_active(Gfx::g_global_settings.recharged_pbr_enable) ||
       Gfx::recharged_active(Gfx::g_global_settings.recharged_rt_light_enable)) &&
      pbr_shadow_begin_frame(render_state->frame_idx, settings.camera.trans.data());
  // cast_full: the vis-culled count being 0 (camera facing away from every caster) is
  // EXACTLY the owner's pop-on-rotation repro — the full static buffer must still cast.
  // ROUND 2 (owner defect #3 — complete caster set): cast from ALL opaque tfrag kinds, not
  // just NORMAL. TRANS / LOWRES_TRANS / WATER are transparent and are deliberately excluded.
  // OWNER #4 (phantom straight shadow lines): LOWRES is EXCLUDED from the caster set. The
  // lowres far-LOD hull is a coarse duplicate of the world (e.g. ~1900 tris, mean edge
  // 85m) that sits up to +57m ABOVE the walkable hires ground in 465 measured 2m-cells; the
  // main pass hides it near the player (PVS / hires draws instead) but cast_full ignores
  // vis, so its giant straight-edged plates shadowed the real terrain from nothing — the
  // long straight phantom lines. The hires NORMAL/DIRT/ICE kinds cover every surface the
  // player sees inside the shadow box; distant-surround shading is already in the baked.
  const bool pbr_tfrag_opaque_caster =
      tree.kind == tfrag3::TFragmentTreeKind::NORMAL ||
      tree.kind == tfrag3::TFragmentTreeKind::DIRT ||
      tree.kind == tfrag3::TFragmentTreeKind::ICE;
  if (pbr_shadow_frame_ok && pbr_tfrag_opaque_caster &&
      (pbr_shadow_caster_mask(render_state->frame_idx) & 1) &&
      (pbr_depth_index_count > 0 ||
       (pbr_shadow_state().cast_full && tree.index_count > 0))) {
    auto& sh_st = pbr_shadow_state();
    // Save the GL state the depth pass mutates.
    GLint prev_program = 0, prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0}, prev_depth_func = GL_LEQUAL;
    GLboolean prev_scissor = glIsEnabled(GL_SCISSOR_TEST);
    GLboolean prev_cull = glIsEnabled(GL_CULL_FACE);
    GLboolean prev_poly_off = glIsEnabled(GL_POLYGON_OFFSET_FILL);
    // DEPTH_TEST is per-DrawMode state (setup_opengl_from_draw_mode) — whatever the last
    // draw left. Depth WRITES only happen when the test is enabled, so the depth-only
    // pass must force it on (device chain reaches here with it off → empty map).
    GLboolean prev_depth_test = glIsEnabled(GL_DEPTH_TEST);
    GLboolean prev_depth_mask = GL_TRUE;
    glGetIntegerv(GL_CURRENT_PROGRAM, &prev_program);
    glGetIntegerv(GL_FRAMEBUFFER_BINDING, &prev_fbo);
    glGetIntegerv(GL_VIEWPORT, prev_vp);
    glGetIntegerv(GL_DEPTH_FUNC, &prev_depth_func);
    glGetBooleanv(GL_DEPTH_WRITEMASK, &prev_depth_mask);

    glBindFramebuffer(GL_FRAMEBUFFER, sh_st.fbo[sh_st.write]);
    glViewport(0, 0, sh_st.size, sh_st.size);
    glDisable(GL_SCISSOR_TEST);
    glDisable(GL_CULL_FACE);
    glEnable(GL_DEPTH_TEST);
    glDepthMask(GL_TRUE);
    glDepthFunc(GL_LEQUAL);
    glEnable(GL_POLYGON_OFFSET_FILL);
    glPolygonOffset(2.0f, 4.0f);

    const auto& depth_sh = render_state->shaders[ShaderId::PBR_DEPTH];
    depth_sh.activate();
    GLuint depth_id = depth_sh.id();
    glUniformMatrix4fv(glGetUniformLocation(depth_id, "u_smvp"), 1, GL_FALSE, sh_st.mvp);
    // cam_trans = the SAME source the main pass uploads (settings.camera.trans).
    const auto& ct = settings.camera.trans;
    glUniform4f(glGetUniformLocation(depth_id, "cam_trans"), ct[0], ct[1], ct[2], ct[3]);

    if (sh_st.debug) {
      while (glGetError() != GL_NO_ERROR) {
      }
    }
    if (sh_st.cast_full && tree.index_count > 0) {
      // Round-5 owner bug fix: the caster set must IGNORE camera visibility (an off-screen
      // hut must keep casting its on-screen shadow — vis-culled casters pop shadows in/out
      // on camera rotation). Draw the FULL static tree index buffer, then rebind the
      // frame's element buffer for the main pass.
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree.index_buffer);
      glDrawElements(tree.draw_mode, tree.index_count, GL_UNSIGNED_INT, nullptr);
      sh_st.cast_indices += (u64)tree.index_count;
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, render_state->no_multidraw
                                                ? tree.single_draw_index_buffer
                                                : tree.index_buffer);
    } else {
      glDrawElements(tree.draw_mode, pbr_depth_index_count, GL_UNSIGNED_INT, nullptr);
      sh_st.cast_indices += (u64)pbr_depth_index_count;
    }
    if (sh_st.debug) {
      GLenum dbg_err = glGetError();
      if (dbg_err != GL_NO_ERROR) {
        lg::warn("PBR-SHADOW-DBG tfrag depth pass glerr=0x{:x} idx={}", (u32)dbg_err,
                 pbr_depth_index_count);
      }
    }

    // Restore everything.
    glUseProgram((GLuint)prev_program);
    glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
    glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
    if (prev_scissor) {
      glEnable(GL_SCISSOR_TEST);
    } else {
      glDisable(GL_SCISSOR_TEST);
    }
    if (prev_cull) {
      glEnable(GL_CULL_FACE);
    } else {
      glDisable(GL_CULL_FACE);
    }
    if (prev_poly_off) {
      glEnable(GL_POLYGON_OFFSET_FILL);
    } else {
      glDisable(GL_POLYGON_OFFSET_FILL);
    }
    glPolygonOffset(0.0f, 0.0f);
    if (!prev_depth_test) {
      glDisable(GL_DEPTH_TEST);
    }
    glDepthMask(prev_depth_mask);
    glDepthFunc(prev_depth_func);
  }
  // Round-4 mandate B receiver bind: bind the shadow matrix + sampler on the TFRAG3
  // program for this tree's draws. Runs regardless of whether the depth pass ran this
  // frame (last frame's map, or the cleared-to-1.0 map, is acceptable).
  if ((Gfx::recharged_active(Gfx::g_global_settings.recharged_pbr_enable) ||
       Gfx::recharged_active(Gfx::g_global_settings.recharged_rt_light_enable)) &&
      pbr_shadow_state().valid) {
    pbr_shadow_bind_receiver(render_state->shaders[tfrag_shader_id].id(),
                             settings.camera.trans.data());
  }
#endif
  // Gjak2-visuals TOD state dump — the diffable our-x86-vs-device probe (the
  // x86-first discipline): full itimes weights, frame fog color, first TOD
  // colors. Device: always, ~5 s cadence; desktop: env GJ2VIS_TFTREE only, so
  // the oracle binary behaves identically unless explicitly probed.
  {
#ifdef __ANDROID__
    static const bool s_tod_dump = true;
#else
    static const bool s_tod_dump = getenv("GJ2VIS_TFTREE") != nullptr;
#endif
    if (s_tod_dump) {
      static int s_tod_ctr = 0;
      if ((s_tod_ctr++ % 300) == 0) {
        const auto& it = settings.camera.itimes;
        const u8* c0 = (const u8*)m_color_result.data();
        const u8* fc = render_state->fog_color.data();
        // Near-white histogram of the interpolated TOD palette — a blown
        // sse2neon interp would show here as a large near-white fraction.
        int white_cnt = 0;
        const int tod_total = (int)tree.colors->color_count;
        for (int ci = 0; ci < tod_total; ci++) {
          const u8* c = c0 + ci * 4;
          if (c[0] >= 0xF0 && c[1] >= 0xF0 && c[2] >= 0xF0) {
            white_cnt++;
          }
        }
        fprintf(stderr, "GJ2VIS-TODWHITE lvl=%s tree=%d white=%d/%d\n", m_level_name.c_str(),
                settings.tree_idx, white_cnt, tod_total);
        fprintf(stderr,
                "GJ2VIS-TOD lvl=%s tree=%d fog=(%.4f %.3f %.3f) hvdfw=%.3f "
                "itimes=%08x,%08x,%08x,%08x|%08x,%08x,%08x,%08x|"
                "%08x,%08x,%08x,%08x|%08x,%08x,%08x,%08x fogcol=%02x%02x%02x%02x "
                "tod0=%02x%02x%02x%02x tod1=%02x%02x%02x%02x\n",
                m_level_name.c_str(), settings.tree_idx, settings.camera.fog.x(),
                settings.camera.fog.y(), settings.camera.fog.z(), settings.camera.hvdf_off.w(),
                (u32)it[0].x(), (u32)it[0].y(),
                (u32)it[0].z(), (u32)it[0].w(), (u32)it[1].x(), (u32)it[1].y(), (u32)it[1].z(),
                (u32)it[1].w(), (u32)it[2].x(), (u32)it[2].y(), (u32)it[2].z(), (u32)it[2].w(),
                (u32)it[3].x(), (u32)it[3].y(), (u32)it[3].z(), (u32)it[3].w(), fc[0], fc[1],
                fc[2], fc[3], c0[0], c0[1], c0[2], c0[3], c0[4], c0[5], c0[6], c0[7]);
      }
    }
  }
  // Gjak2-visuals clock probe: the searchlight flood + texture-anim freeze
  // both hang off GOAL clocks that stop ticking on the device (~18 s in)
  // while camera/TOD clocks keep running. tick! (jak2 timer.gc:250) freezes a
  // clock when (logand clock.mask *kernel-context*.prevent-from-run) != 0, so
  // dump master-mode, prevent-from-run, and the frame-counters of the two
  // clock families side by side. Offsets from decompiler all-types (display
  // clocks: game=44 base=48 real=52 entity=68 part=72 camera=80; clock
  // frame-counter=24 ratio=12 spf=80; kernel-context prevent-from-run=4;
  // cpad-list cpads0=8, hw-cpad valid=4 button0=6; basic fields read at
  // offset-4). Diffable our-x86 (env GJ2VIS_TFTREE) vs device (always).
  if (render_state->version == GameVersion::Jak2) {
#ifdef __ANDROID__
    static const bool s_clk_dump = true;
#else
    static const bool s_clk_dump = getenv("GJ2VIS_TFTREE") != nullptr;
#endif
    if (s_clk_dump) {
      static int s_clk_ctr = 0;
      if ((s_clk_ctr++ % 300) == 0) {
        const u8* ee = (const u8*)render_state->ee_main_memory;
        auto rd_u32 = [&](u32 addr) {
          u32 v = 0;
          memcpy(&v, ee + addr, 4);
          return v;
        };
        auto rd_s64 = [&](u32 addr) {
          s64 v = 0;
          memcpy(&v, ee + addr, 8);
          return v;
        };
        auto rd_f32 = [&](u32 addr) {
          float v = 0;
          memcpy(&v, ee + addr, 4);
          return v;
        };
        auto ok = [](u32 a) { return a > 0x1000 && a < 0x8000000; };
        u32 disp = ::jak2::intern_from_c("*display*")->value();
        u32 kctx = ::jak2::intern_from_c("*kernel-context*")->value();
        u32 mm = ::jak2::intern_from_c("*master-mode*")->value();
        u32 cpl = ::jak2::intern_from_c("*cpad-list*")->value();
        const char* mmn = "?";
        if (mm == ::jak2::intern_from_c("game").offset) {
          mmn = "game";
        } else if (mm == ::jak2::intern_from_c("pause").offset) {
          mmn = "pause";
        } else if (mm == ::jak2::intern_from_c("menu").offset) {
          mmn = "menu";
        } else if (mm == ::jak2::intern_from_c("progress").offset) {
          mmn = "progress";
        } else if (mm == ::jak2::intern_from_c("freeze").offset) {
          mmn = "freeze";
        }
        u32 prevent = ok(kctx) ? rd_u32(kctx + 4 - 4) : 0xdead;
        auto clk = [&](int disp_off, s64* fc, float* ratio, u32* mask, float* spf) {
          u32 p = ok(disp) ? rd_u32(disp + disp_off - 4) : 0;
          if (ok(p)) {
            *fc = rd_s64(p + 24 - 4);
            *ratio = rd_f32(p + 12 - 4);
            *mask = rd_u32(p + 8 - 4);
            *spf = rd_f32(p + 80 - 4);
          }
        };
        s64 fc_ent = -1, fc_base = -1, fc_game = -1, fc_part = -1, fc_real = -1, fc_cam = -1;
        float r_ent = -1, r_base = -1, r_game = -1, r_part = -1, r_real = -1, r_cam = -1;
        u32 m_ent = 0, m_base = 0, m_game = 0, m_part = 0, m_real = 0, m_cam = 0;
        float s_ent = -1, s_base = -1, s_game = -1, s_part = -1, s_real = -1, s_cam = -1;
        clk(68, &fc_ent, &r_ent, &m_ent, &s_ent);
        clk(48, &fc_base, &r_base, &m_base, &s_base);
        clk(44, &fc_game, &r_game, &m_game, &s_game);
        clk(72, &fc_part, &r_part, &m_part, &s_part);
        clk(52, &fc_real, &r_real, &m_real, &s_real);
        clk(80, &fc_cam, &r_cam, &m_cam, &s_cam);
        u32 pad0 = ok(cpl) ? rd_u32(cpl + 8 - 4) : 0;
        u32 pad_valid = ok(pad0) ? ee[pad0 + 4 - 4] : 0xff;
        u32 pad_btn = 0;
        if (ok(pad0)) {
          memcpy(&pad_btn, ee + pad0 + 6 - 4, 2);
        }
        fprintf(stderr,
                "GJ2VIS-CLOCK mm=%s(0x%x) prevent=0x%x ent=%lld(r=%.2f m=0x%x spf=%.4f) "
                "game=%lld part=%lld base=%lld real=%lld cam=%lld pad0(v=%02x b=%04x)\n",
                mmn, mm, prevent, (long long)fc_ent, r_ent, m_ent, s_ent, (long long)fc_game,
                (long long)fc_part, (long long)fc_base, (long long)fc_real, (long long)fc_cam,
                pad_valid, pad_btn);
        // Round 2: the six clocks not covered above (the texture-anim freeze
        // increments by the DISPLAY process's clock spf — likely frame-clock),
        // plus the sky anim's own frame-time/delta/mod read from GOAL memory
        // (*sky-texture-anim-array* array-data[1]; texture-anim is a structure
        // → no -4; the array itself is a basic → -4).
        s64 fc_frm = -1, fc_rfrm = -1, fc_tgt = -1, fc_ses = -1, fc_u0 = -1, fc_tgc = -1;
        float s_frm = -1, s_rfrm = -1, s_tgt = -1, s_ses = -1, s_u0 = -1, s_tgc = -1;
        float r_frm = -1, r_rfrm = -1, r_tgt = -1, r_ses = -1, r_u0 = -1, r_tgc = -1;
        u32 m_frm = 0, m_rfrm = 0, m_tgt = 0, m_ses = 0, m_u0 = 0, m_tgc = 0;
        clk(56, &fc_frm, &r_frm, &m_frm, &s_frm);
        clk(60, &fc_rfrm, &r_rfrm, &m_rfrm, &s_rfrm);
        clk(64, &fc_tgt, &r_tgt, &m_tgt, &s_tgt);
        clk(40, &fc_ses, &r_ses, &m_ses, &s_ses);
        clk(84, &fc_u0, &r_u0, &m_u0, &s_u0);
        clk(88, &fc_tgc, &r_tgc, &m_tgc, &s_tgc);
        float tf = ok(disp) ? rd_f32(disp + 92 - 4) : -1.f;
        float dr = ok(disp) ? rd_f32(disp + 96 - 4) : -1.f;
        u32 sky_arr = ::jak2::intern_from_c("*sky-texture-anim-array*")->value();
        float a1_time = -1.f, a1_delta = -1.f, a1_mod = -1.f;
        if (ok(sky_arr)) {
          u32 a1 = rd_u32(sky_arr + 16 - 4 + 1 * 4);
          if (ok(a1)) {
            a1_time = rd_f32(a1 + 52);
            a1_delta = rd_f32(a1 + 56);
            a1_mod = rd_f32(a1 + 60);
          }
        }
        fprintf(stderr,
                "GJ2VIS-CLOCK2 frame=%lld(r=%.2f m=0x%x spf=%.4f) rframe=%lld(spf=%.4f) "
                "tgt=%lld(spf=%.4f) ses=%lld u0=%lld tgc=%lld tf=%.2f dog=%.2f "
                "skyanim1(t=%.1f d=%.3f mod=%.1f)\n",
                (long long)fc_frm, r_frm, m_frm, s_frm, (long long)fc_rfrm, s_rfrm,
                (long long)fc_tgt, s_tgt, (long long)fc_ses, (long long)fc_u0, (long long)fc_tgc,
                tf, dr, a1_time, a1_delta, a1_mod);
        // Round 3: the BUCKET_2 vis/fog cursor corruption — is the
        // display-frame's global-buf FIELD itself corrupt in GOAL memory, or
        // only the value the caller passes? Dump on-screen + both frames'
        // global-buf object pointers and their base cursors (dma-buffer:
        // allocated-length@4 base@8 end@12, basic → offset-4).
        u32 onscr = ok(disp) ? rd_u32(disp + 4 - 4) : 0xdead;
        u32 f0 = ok(disp) ? rd_u32(disp + 12 - 4) : 0;
        u32 f1 = ok(disp) ? rd_u32(disp + 16 - 4) : 0;
        u32 gb0 = ok(f0) ? rd_u32(f0 + 40 - 4) : 0;
        u32 gb1 = ok(f1) ? rd_u32(f1 + 40 - 4) : 0;
        u32 gb0_base = ok(gb0) ? rd_u32(gb0 + 8 - 4) : 0;
        u32 gb1_base = ok(gb1) ? rd_u32(gb1 + 8 - 4) : 0;
        u32 gb0_len = ok(gb0) ? rd_u32(gb0 + 4 - 4) : 0;
        u32 gb1_len = ok(gb1) ? rd_u32(gb1 + 4 - 4) : 0;
        fprintf(stderr,
                "GJ2VIS-GBUF onscr=%u f0=0x%x f1=0x%x gb0=0x%x(base=0x%x len=%u) "
                "gb1=0x%x(base=0x%x len=%u)\n",
                onscr, f0, f1, gb0, gb0_base, gb0_len, gb1, gb1_base, gb1_len);
      }
    }
  }

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

  // Grecharged-grass-overhang2: per-draw fringe near-fade uniform. Set only on state CHANGES (draws
  // are texture-sorted, so this is a couple of glUniform4f per frame) and ALWAYS left at 0 so other
  // TFRAG3 users are untouched; 0 = stock shader path.
  const GrassFringeFade fringe_fade = grass_fringe_fade_params();
  GLint fringe_loc = -2;  // -2 = not queried yet
  bool fringe_on_state = false;
  auto set_fringe = [&](bool want) {
    if (want == fringe_on_state) {
      return;
    }
    if (fringe_loc == -2) {
      fringe_loc = glGetUniformLocation(render_state->shaders[ShaderId::TFRAG3].id(), "u_fringe_fade");
    }
    if (fringe_loc >= 0) {
      glUniform4f(fringe_loc, want ? 1.f : 0.f, fringe_fade.start_m, fringe_fade.end_m,
                  fringe_fade.dbg);
    }
    fringe_on_state = want;
  };

#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials round-4: per-draw PBR material bind via the shared
  // PbrDrawBinder (same code Tie3 now uses). Units 11-15 are free in this renderer
  // (base tex = 0, TOD LUT = 10); shared TFRAG3 program so u_pbr_mode is restored to 0
  // in binder.finish() at the end of the draw loop. Round-4 coverage unification: the
  // binder no longer excludes alpha-blended (TRANS "vis-alpha" tree) draws — those now
  // take the PBR path too; alpha still comes from the legacy fragment_color*T0 product
  // in the shader, only rgb is relit.
  PbrDrawBinder pbr_binder;
  pbr_binder.begin(render_state->shaders[tfrag_shader_id].id(), &m_pbr_draws);
  // [cover] ROUND 21 DISPLACEMENT COVERAGE: hand the binder the two things only this caller knows —
  // which renderer owns the draws, and whether the program bound above is the TESS one (use_tess is
  // exactly what first_tfrag_draw_setup turned into u_pbr_tess_active). The tree kind is free here.
  // tfrag_tree_names[] entries are constexpr string literals, so storing the pointer is safe.
  pbr_binder.set_coverage_context("tfrag", tfrag3::tfrag_tree_names[(int)tree.kind], use_tess,
                                  render_state->frame_idx);
  auto set_pbr = [&](s32 tex_id, const DrawMode& mode) { pbr_binder.set(tex_id, mode); };
#endif

#ifdef OG_FEAT_PBR
  // REOPEN #3 TESSELLATION color pass. A dedicated draw loop over the tree's draws using the
  // per-tree flat triangle-list buffer (GL_PATCHES, 3 verts/patch). Whole-tree (vis-culling is
  // dropped — visual-only displacement; the tess control stage still culls cost via its per-edge
  // far-gate level=1). Reuses setup_tfrag_shader_cached / PbrDrawBinder on the TFRAG3_TESS
  // program. Double-draw (alpha-fail) is handled the same way. Skips the plain loop below.
  // Belt-and-braces null guard: glPatchParameteri is a loaded fn-ptr; calling it when NULL
  // crashes. If it is unresolved, do NOT enter the tess path — fall through to the plain
  // TFRAG3 draw loop below. (use_tess already gates on gl_tfrag3_tess_program_ok(), which
  // checks the same pointer; this is a last-line-of-defense at the actual call site.)
  if (use_tess && glPatchParameteri != nullptr) {
    build_tess_tri_buffer(tree);
    ASSERT(m_textures);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree.tess_index_buffer);
    glPatchParameteri(GL_PATCH_VERTICES, 3);
    GLint tess_decal_loc =
        glGetUniformLocation(render_state->shaders[ShaderId::TFRAG3_TESS].id(), "decal");
    const auto& tess_alpha_u =
        tfrag_alpha_uniforms(render_state->shaders[ShaderId::TFRAG3_TESS].id());
    for (size_t draw_idx = 0; draw_idx < tree.draws->size(); draw_idx++) {
      const auto& draw = tree.draws->operator[](draw_idx);
      const auto& rng = tree.tess_tri_ranges[draw_idx];
      if (rng.second == 0) {
        continue;
      }
      s32 tex_idx = draw.tree_tex_id;
      if (tex_idx >= 0) {
        bound_tex = m_textures->at(tex_idx);
      } else {
        bound_tex = ((size_t)(-(tex_idx + 1)) < m_anim_slot_array->size()
                         ? m_anim_slot_array->at(-(tex_idx + 1))
                         : 0);
        gj2vis_probe_bg_slot(-(tex_idx + 1), bound_tex);
      }
      glBindTexture(GL_TEXTURE_2D, bound_tex);
      auto double_draw = setup_tfrag_shader_cached(render_state, draw.mode, ShaderId::TFRAG3_TESS,
                                                   bound_tex, draw_state_cache);
      if (tess_decal_loc != -1) {
        glUniform1i(tess_decal_loc, draw.mode.get_decal() ? 1 : 0);
      }
      set_pbr(draw.tree_tex_id, draw.mode);
      tree.tris_this_frame += draw.num_triangles;
      tree.draws_this_frame++;
      prof.add_draw_call();
      glDrawElements(GL_PATCHES, rng.second, GL_UNSIGNED_INT, (void*)(rng.first * sizeof(u32)));
      if (double_draw.kind == DoubleDrawKind::AFAIL_NO_DEPTH_WRITE) {
        prof.add_draw_call();
        if (tess_alpha_u.alpha_min != -1) {
          glUniform1f(tess_alpha_u.alpha_min, -10.f);
        }
        if (tess_alpha_u.alpha_max != -1) {
          glUniform1f(tess_alpha_u.alpha_max, double_draw.aref_second);
        }
        glDepthMask(GL_FALSE);
        draw_state_cache.valid = false;
        glDrawElements(GL_PATCHES, rng.second, GL_UNSIGNED_INT, (void*)(rng.first * sizeof(u32)));
      }
    }
    pbr_binder.finish();
    set_fringe(false);
    glBindVertexArray(0);
    return;
  }
#endif

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
        bound_tex = ((size_t)(-(tex_idx + 1)) < m_anim_slot_array->size() ? m_anim_slot_array->at(-(tex_idx + 1)) : 0);
        gj2vis_probe_bg_slot(-(tex_idx + 1), bound_tex);
      }
      glBindTexture(GL_TEXTURE_2D, bound_tex);
      auto double_draw = setup_tfrag_shader_cached(render_state, draw.mode, ShaderId::TFRAG3,
                                                   bound_tex, draw_state_cache);
      glUniform1i(m_uniforms.decal, draw.mode.get_decal() ? 1 : 0);
      set_fringe(fringe_fade.on && draw.tree_tex_id >= 0 &&
                 (draw.tree_tex_id == m_fringe_tex_a || draw.tree_tex_id == m_fringe_tex_b));
#ifdef OG_FEAT_PBR
      set_pbr(draw.tree_tex_id, draw.mode);
#endif

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
      bound_tex = ((size_t)(-(tex_idx + 1)) < m_anim_slot_array->size() ? m_anim_slot_array->at(-(tex_idx + 1)) : 0);
      gj2vis_probe_bg_slot(-(tex_idx + 1), bound_tex);
    }
    glBindTexture(GL_TEXTURE_2D, bound_tex);
    auto double_draw = setup_tfrag_shader_cached(render_state, draw.mode, ShaderId::TFRAG3,
                                                 bound_tex, draw_state_cache);
    glUniform1i(m_uniforms.decal, draw.mode.get_decal() ? 1 : 0);
    set_fringe(fringe_fade.on && draw.tree_tex_id >= 0 &&
               (draw.tree_tex_id == m_fringe_tex_a || draw.tree_tex_id == m_fringe_tex_b));
#ifdef OG_FEAT_PBR
    set_pbr(draw.tree_tex_id, draw.mode);
#endif
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
  // Grecharged-grass-overhang2: leave the fringe fade off for any subsequent TFRAG3 user.
  set_fringe(false);
#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials: the TFRAG3 program is shared; reset PBR mode to 0 and
  // park units 11-15 on the neutral 1x1 defaults (magenta-class hardening) so no
  // material map leaks into later draws this frame. Restores active unit 0.
  pbr_binder.finish();
#endif
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
#ifdef OG_FEAT_PBR
        // REOPEN #3 TESSELLATION: free the lazily-built flat triangle-list buffer.
        if (tree.tess_index_buffer) {
          glDeleteBuffers(1, &tree.tess_index_buffer);
          tree.tess_index_buffer = 0;
        }
#endif
        glDeleteVertexArrays(1, &tree.vao);
      }
    }
    m_cached_trees[geom].clear();
  }
}

#ifdef OG_FEAT_PBR
// REOPEN #3 TESSELLATION: expand each draw's static strip+restart index range (from
// tree.unpacked.indices, the resident static full buffer) into a flat TRIANGLE-LIST index
// stream suitable for GL_PATCHES (3 verts/patch). One flat buffer for the whole tree, built
// LAZILY on first tess draw; per-draw (first, count) flat ranges recorded in tess_tri_ranges.
//
// Strip semantics match the main pass: UINT32_MAX restarts a strip; within a strip, triangle i
// is (v[i], v[i+1], v[i+2]) with the winding flipping on odd i (GL_TRIANGLE_STRIP). Degenerate
// triangles (a repeated index — common at strip stitches) are skipped. When the tree is a plain
// GL_TRIANGLES stream (use_strips == false), the indices are already a flat triangle list and we
// copy them straight through (still dropping any restart sentinels and degenerates defensively).
void TFragment::build_tess_tri_buffer(TFragment::TreeCache& tree) {
  if (tree.tess_index_buffer != 0 || tree.draws == nullptr || tree.index_data == nullptr) {
    return;
  }
  const bool strips = (tree.draw_mode == GL_TRIANGLE_STRIP);
  std::vector<u32> flat;
  flat.reserve(tree.index_count * 2 + 3);
  tree.tess_tri_ranges.assign(tree.draws->size(), {0u, 0u});

  for (size_t di = 0; di < tree.draws->size(); di++) {
    const auto& draw = tree.draws->operator[](di);
    u32 first = draw.unpacked.idx_of_first_idx_in_full_buffer;
    u32 count = 0;
    for (const auto& grp : draw.vis_groups) {
      count += grp.num_inds;
    }
    u32 range_first = (u32)flat.size();
    if (strips) {
      // walk the strip range, restarting on UINT32_MAX, emitting one triangle per advancing vert.
      u32 a = UINT32_MAX, b = UINT32_MAX;
      int strip_pos = 0;  // position within the current strip (for winding)
      for (u32 k = 0; k < count; k++) {
        u32 idx = tree.index_data[first + k];
        if (idx == UINT32_MAX) {
          a = b = UINT32_MAX;
          strip_pos = 0;
          continue;
        }
        if (strip_pos < 2) {
          if (strip_pos == 0) {
            a = idx;
          } else {
            b = idx;
          }
          strip_pos++;
        } else {
          u32 c = idx;
          // winding: even strip_pos (>=2) => (a,b,c); odd => (b,a,c)
          u32 t0, t1, t2;
          if ((strip_pos & 1) == 0) {
            t0 = a;
            t1 = b;
            t2 = c;
          } else {
            t0 = b;
            t1 = a;
            t2 = c;
          }
          if (t0 != t1 && t1 != t2 && t0 != t2) {  // skip degenerates
            flat.push_back(t0);
            flat.push_back(t1);
            flat.push_back(t2);
          }
          a = b;
          b = c;
          strip_pos++;
        }
      }
    } else {
      // plain triangle list: copy in groups of 3, dropping any sentinel/degenerate.
      for (u32 k = 0; k + 2 < count; k += 3) {
        u32 t0 = tree.index_data[first + k];
        u32 t1 = tree.index_data[first + k + 1];
        u32 t2 = tree.index_data[first + k + 2];
        if (t0 == UINT32_MAX || t1 == UINT32_MAX || t2 == UINT32_MAX) {
          continue;
        }
        if (t0 != t1 && t1 != t2 && t0 != t2) {
          flat.push_back(t0);
          flat.push_back(t1);
          flat.push_back(t2);
        }
      }
    }
    tree.tess_tri_ranges[di] = {range_first, (u32)flat.size() - range_first};
  }

  tree.tess_index_count = (u32)flat.size();
  glGenBuffers(1, &tree.tess_index_buffer);
  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree.tess_index_buffer);
  glBufferData(GL_ELEMENT_ARRAY_BUFFER, flat.size() * sizeof(u32),
               flat.empty() ? nullptr : flat.data(), GL_STATIC_DRAW);
}
#endif

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
