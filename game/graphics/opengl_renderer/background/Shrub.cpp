#include "Shrub.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "common/log/log.h"

#include "game/graphics/gfx.h"
#include "game/mips2c/spart_prof.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

namespace {
// Grecharged-foliage-wind: live-tunable shrub sway amplitude (horizontal, in world units). Mirrors
// GrassRenderer.cpp's grass_droop_len() dual mechanism EXACTLY (cached + throttled with
// (s_throttle++ & 63) so it isn't re-read every frame): Android prop debug.opengoal.foliage.shrub_amp
// / desktop env FOLIAGE_WIND_SHRUB_AMP, interpreted in METERS. Round 2 default 0.16 m (~655 world
// units); round 1's 0.10 m was part of the build the owner called dead ("aucune feuille qui bouge"),
// and 0.045 m before that was sub-pixel past a few metres. Clamped [0.0, 0.3] m. Returns world units
// (meters * 4096). Round 2 also adds a faster low-amplitude flutter harmonic in shrub.vert: the
// round-1 waveform ran at 0.24-0.49 Hz, so its per-FRAME displacement was still sub-pixel even
// though its total excursion was not — big slow drift reads as static at a glance.
// Grecharged-foliage-wind3 : 0,16 -> 0,12 m. Les buissons n'etaient PAS vises par « tempête »
// (16 cm de deplacement horizontal sur un buisson n'en est pas une), mais l'ensemble doit rester
// coherent avec la division par 3,44 du cote TIE. La reduction est declaree ici plutot que glissee.
constexpr float FOLIAGE_WIND_SHRUB_AMP_DEFAULT_M = 0.12f;
static float foliage_wind_shrub_amp() {
  static float s_cached = FOLIAGE_WIND_SHRUB_AMP_DEFAULT_M * 4096.0f;
  static int s_throttle = 0;
  if ((s_throttle++ & 63) != 0) {
    return s_cached;
  }
  char buf[16] = {0};
  bool have = false;
#ifdef __ANDROID__
  if (__system_property_get("debug.opengoal.foliage.shrub_amp", buf) > 0 && buf[0]) {
    have = true;
  }
#else
  const char* e = std::getenv("FOLIAGE_WIND_SHRUB_AMP");
  if (e && e[0]) {
    std::strncpy(buf, e, sizeof(buf) - 1);
    have = true;
  }
#endif
  float m = have ? (float)std::atof(buf) : FOLIAGE_WIND_SHRUB_AMP_DEFAULT_M;
  if (m < 0.0f) m = FOLIAGE_WIND_SHRUB_AMP_DEFAULT_M;  // unparsable/negative -> default
  if (m > 0.3f) m = 0.3f;
  s_cached = m * 4096.0f;  // meters -> world units
  return s_cached;
}
}  // namespace

Shrub::Shrub(const std::string& name, int my_id) : BucketRenderer(name, my_id) {
  m_color_result.resize(TIME_OF_DAY_COLOR_COUNT);
}

Shrub::~Shrub() {
  discard_tree_cache();
}

void Shrub::init_shaders(ShaderLibrary& shaders) {
  m_uniforms.decal = glGetUniformLocation(shaders[ShaderId::SHRUB].id(), "decal");
}

void Shrub::render(DmaFollower& dma, SharedRenderState* render_state, ScopedProfilerNode& prof) {
  if (!m_enabled) {
    while (dma.current_tag_offset() != render_state->next_bucket) {
      dma.read_and_advance();
    }
    return;
  }

  // Grecharged-mesh-browser V2.6-bis isolation: only the targeted mesh renders — drain the
  // bucket exactly like the disabled path.
  if (Gfx::g_global_settings.mb_isolation_on()) {
    Gfx::g_global_settings.mb_cur_isolated_skips++;
    while (dma.current_tag_offset() != render_state->next_bucket) {
      dma.read_and_advance();
    }
    return;
  }

  auto data0 = dma.read_and_advance();
  ASSERT(data0.vif1() == 0 || data0.vifcode1().kind == VifCode::Kind::NOP);
  ASSERT(data0.vif0() == 0 || data0.vifcode0().kind == VifCode::Kind::NOP ||
         data0.vifcode0().kind == VifCode::Kind::MARK);
  ASSERT(data0.size_bytes == 0);

  if (dma.current_tag().kind == DmaTag::Kind::CALL) {
    // renderer didn't run, let's just get out of here.
    for (int i = 0; i < 4; i++) {
      dma.read_and_advance();
    }
    ASSERT(dma.current_tag_offset() == render_state->next_bucket);
    return;
  }
  if (dma.current_tag_offset() == render_state->next_bucket) {
    return;
  }

  auto pc_port_data = dma.read_and_advance();
  ASSERT(pc_port_data.size_bytes == sizeof(TfragPcPortData));
  memcpy(&m_pc_port_data, pc_port_data.data, sizeof(TfragPcPortData));
  m_pc_port_data.level_name[11] = '\0';

  if (render_state->version >= GameVersion::Jak2) {
    // jak 2 proto visibility
    auto proto_mask_data = dma.read_and_advance();
    m_proto_vis_data = proto_mask_data.data;
    m_proto_vis_data_size = proto_mask_data.size_bytes;
  }

  while (dma.current_tag_offset() != render_state->next_bucket) {
    dma.read_and_advance();
  }

  TfragRenderSettings settings;
  settings.camera = m_pc_port_data.camera;

  settings.tree_idx = 0;

  update_render_state_from_pc_settings(render_state, m_pc_port_data);

  m_has_level = setup_for_level(m_pc_port_data.level_name, render_state);
  render_all_trees(settings, render_state, prof);
}

void Shrub::update_load(const LevelData* loader_data) {
  const tfrag3::Level* lev_data = loader_data->level.get();
#ifdef OG_FEAT_PBR
  // Grecharged-pbr-realtime-fusion ROUND 22 (owner defect A): resolve every texture in this level
  // that has a registered PBR material set. Mirrors TFragment::update_load / Tie3, but measures
  // the authored UV density over SHRUB geometry (its own draw/vertex types + 4096-scale
  // texcoords), because the POM amplitude is derived from the material's real feature size in
  // metres — a wrong density means a wrong depth, not just a missing log line.
  m_pbr_draws.clear();
  for (size_t ti = 0; ti < lev_data->textures.size(); ++ti) {
    if (const auto* maps = custom_tex::find_pbr_material(custom_tex::pbr_material_key(lev_data->textures[ti].debug_tpage_name, lev_data->textures[ti].debug_name))) {
      u32 nsamp = 0;
      float dens = measure_uv_density_shrub(*lev_data, (s32)ti, &nsamp);
      const bool measured = dens > 0.f;
      if (!measured) {
        dens = 0.5f;  // not enough samples: fall back to the constant the shaders used to assume
      }
      m_pbr_draws.push_back({(s32)ti, *maps, dens});
      // Only publish to the shared [pom] diag registry when shrub geometry ACTUALLY uses this
      // texture. Most PBR materials are tfrag/tie ground and walls with zero shrub triangles, and
      // an unconditional note would overwrite their real measured density with our 0.5 fallback
      // (diagnostics only — each renderer keeps its own PbrDrawList value — but it would make the
      // dump lie).
      if (measured) {
        custom_tex::pbr_pom_diag_note(lev_data->textures[ti].debug_name, *maps, dens);
      }
      lg::info(
          "pbr uv density (shrub): {} tiles/m={:.3f} tile={:.1f}cm (shader assumed 0.5 => "
          "200.0cm, ratio {:.2f}x) samples={}{}",
          lev_data->textures[ti].debug_name, dens, 100.f / dens, dens / 0.5f, nsamp,
          measured ? "" : " [UNMEASURED - no shrub geometry uses this texture, 0.5 fallback]");
    }
  }
  if (!m_pbr_draws.empty()) {
    lg::info("Grecharged-pbr-materials: Shrub level {} has {} PBR material(s)",
             lev_data->level_name, m_pbr_draws.size());
  }
#endif
  // We changed level!
  discard_tree_cache();
  m_trees.resize(lev_data->shrub_trees.size());

  size_t max_draws = 0;
  u32 time_of_day_count = 0;
  size_t max_num_grps = 0;
  size_t max_inds = 0;

  for (u32 l_tree = 0; l_tree < lev_data->shrub_trees.size(); l_tree++) {
    size_t num_grps = 0;

    const auto& tree = lev_data->shrub_trees[l_tree];
    max_draws = std::max(tree.static_draws.size(), max_draws);
    for (auto& draw : tree.static_draws) {
      (void)draw;
      // num_grps += draw.vis_groups.size(); TODO
      max_num_grps += 1;
    }
    max_num_grps = std::max(max_num_grps, num_grps);

    time_of_day_count = std::max(tree.time_of_day_colors.color_count, time_of_day_count);
    max_inds = std::max(tree.indices.size(), max_inds);
    u32 verts = tree.unpacked.vertices.size();
    // Grecharged-foliage-wind: per-plant sway anchor LUT. color_index is constant per shrub
    // instance (extract_shrub assigns one time-of-day palette slot per instance), so a
    // per-color_index (minY, height) table anchors each plant's own base and normalizes the sway
    // by its own height. Packed 16+16 bit into the same Wx1 RGBA8 texture pattern as the TOD LUT
    // (device-proven; no float textures on the Adreno path). Built once per level load; the
    // shader samples it only when the toggle is ON.
    {
      auto& t = m_trees[l_tree];
      std::vector<float> cmin(TIME_OF_DAY_COLOR_COUNT, 1e30f);
      std::vector<float> cmax(TIME_OF_DAY_COLOR_COUNT, -1e30f);
      float ymin_all = 1e30f, ymax_all = -1e30f;
      for (const auto& v : tree.unpacked.vertices) {
        u32 ci = v.color_index < TIME_OF_DAY_COLOR_COUNT ? v.color_index : 0;
        if (v.y < cmin[ci]) cmin[ci] = v.y;
        if (v.y > cmax[ci]) cmax[ci] = v.y;
        if (v.y < ymin_all) ymin_all = v.y;
        if (v.y > ymax_all) ymax_all = v.y;
      }
      if (ymax_all < ymin_all) {  // empty tree
        ymin_all = 0.f;
        ymax_all = 1.f;
      }
      float range = ymax_all - ymin_all;
      if (range < 1.f) range = 1.f;
      t.wind_lut_base = ymin_all;
      t.wind_lut_scale = range / 65535.0f;
      std::vector<u8> lut(TIME_OF_DAY_COLOR_COUNT * 4);
      for (int ci = 0; ci < TIME_OF_DAY_COLOR_COUNT; ci++) {
        u32 qm = 0, qh = 65535;  // unused entry: base anchor + huge height => zero sway
        if (cmax[ci] >= cmin[ci]) {
          float m = (cmin[ci] - ymin_all) / t.wind_lut_scale;
          float h = (cmax[ci] - cmin[ci]) / t.wind_lut_scale;
          qm = (u32)(m < 0.f ? 0.f : (m > 65535.f ? 65535.f : m));
          qh = (u32)(h < 0.f ? 0.f : (h > 65535.f ? 65535.f : h));
        }
        lut[ci * 4 + 0] = (qm >> 8) & 0xff;
        lut[ci * 4 + 1] = qm & 0xff;
        lut[ci * 4 + 2] = (qh >> 8) & 0xff;
        lut[ci * 4 + 3] = qh & 0xff;
      }
      // Grecharged-pbr-realtime-fusion ROUND 22: unit 11 is the PBR NORMAL MAP now (the shrub
      // program gained the fused PBR path this round). The wind-anchor LUT lives on unit 18 —
      // see shrub.vert's tex_T18 comment. This upload-time bind must match, or the very first
      // frame would leave the LUT parked on the normal map's unit.
      glActiveTexture(GL_TEXTURE18);
      glGenTextures(1, &t.wind_lut_texture);
      glBindTexture(GL_TEXTURE_2D, t.wind_lut_texture);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, TIME_OF_DAY_COLOR_COUNT, 1, 0, GL_RGBA,
                   GL_UNSIGNED_BYTE, lut.data());
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    }
    glGenVertexArrays(1, &m_trees[l_tree].vao);
    glBindVertexArray(m_trees[l_tree].vao);
    m_trees[l_tree].vertex_buffer = loader_data->shrub_vertex_data[l_tree];
    m_trees[l_tree].vert_count = verts;
    m_trees[l_tree].draws = &tree.static_draws;
    m_trees[l_tree].proto_vis_mask.clear();
    m_trees[l_tree].proto_vis_mask.resize(tree.proto_names.size(), true);
    m_trees[l_tree].proto_name_to_idx.clear();
    size_t i = 0;
    for (auto& name : tree.proto_names) {
      m_trees[l_tree].proto_name_to_idx[name].push_back(i++);
    }
    m_trees[l_tree].colors = &tree.time_of_day_colors;
    m_trees[l_tree].index_data = tree.indices.data();
    glBindBuffer(GL_ARRAY_BUFFER, m_trees[l_tree].vertex_buffer);
    glEnableVertexAttribArray(0);
    glEnableVertexAttribArray(1);
    glEnableVertexAttribArray(2);
    glEnableVertexAttribArray(3);

    glVertexAttribPointer(0,                                          // location 0 in the shader
                          3,                                          // 3 values per vert
                          GL_FLOAT,                                   // floats
                          GL_FALSE,                                   // normalized
                          sizeof(tfrag3::ShrubGpuVertex),             // stride
                          (void*)offsetof(tfrag3::ShrubGpuVertex, x)  // offset (0)
    );

    glVertexAttribPointer(1,                                          // location 1 in the shader
                          2,                                          // 3 values per vert
                          GL_FLOAT,                                   // floats
                          GL_FALSE,                                   // normalized
                          sizeof(tfrag3::ShrubGpuVertex),             // stride
                          (void*)offsetof(tfrag3::ShrubGpuVertex, s)  // offset (0)
    );

    glVertexAttribPointer(2,                               // location 1 in the shader
                          3,                               // 4 color components
                          GL_UNSIGNED_BYTE,                // u8
                          GL_TRUE,                         // normalized (255 becomes 1)
                          sizeof(tfrag3::ShrubGpuVertex),  //
                          (void*)offsetof(tfrag3::ShrubGpuVertex, rgba_base)  //
    );

    glVertexAttribIPointer(3,                               // location 2 in the shader
                           1,                               // 1 values per vert
                           GL_UNSIGNED_SHORT,               // u16
                           sizeof(tfrag3::ShrubGpuVertex),  // stride
                           (void*)offsetof(tfrag3::ShrubGpuVertex, color_index)  // offset (0)
    );

    // Grecharged-mesh-consolidation: shrub finally carries a real per-vertex smooth normal (it used
    // to have none, so shrub.frag synthesized one from screen-space derivatives = per-triangle
    // flat).
    glEnableVertexAttribArray(4);
    glVertexAttribPointer(4,                               // location 4 in the shader
                          4,                               // 2-10-10-10 packed
                          GL_INT_2_10_10_10_REV,           // signed 10-bit per component
                          GL_TRUE,                         // normalized to [-1, 1]
                          sizeof(tfrag3::ShrubGpuVertex),  // stride
                          (void*)offsetof(tfrag3::ShrubGpuVertex, nor)  // offset
    );

    // ...and the matching SEAM WEIGHT (1 = displace normally, 0 = do not displace), same meaning as
    // the tfrag/tie attribute so shrub is covered by the weld/audit too.
    glEnableVertexAttribArray(5);
    glVertexAttribPointer(5,                               // location 5 in the shader
                          1,                               // 1 value per vert
                          GL_UNSIGNED_SHORT,               // u16
                          GL_TRUE,                         // normalized (65535 becomes 1)
                          sizeof(tfrag3::ShrubGpuVertex),  // stride
                          (void*)offsetof(tfrag3::ShrubGpuVertex, seam_w)  // offset
    );

    glGenBuffers(1, &m_trees[l_tree].single_draw_index_buffer);
    glGenBuffers(1, &m_trees[l_tree].index_buffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m_trees[l_tree].index_buffer);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER, tree.indices.size() * sizeof(u32), tree.indices.data(),
                 GL_STATIC_DRAW);
    m_trees[l_tree].index_count = (u32)tree.indices.size();

#ifdef OG_FEAT_PBR
    // Owner #4 phantom-lines fix: build the SANITIZED caster index list for the sun shadow
    // depth pass. The static strip stream knits some consecutive instance-groups (no restart
    // at those boundaries — extract_shrub defect), producing sliver triangles hundreds of
    // meters long (village1: 34 with an edge > 30 m, worst 363 m). Drawn into the shadow map
    // by the full-buffer caster pass, they are the owner's long straight phantom shadow
    // lines / the X on the ground. Walk the strip, keep every triangle whose longest edge is
    // sane, store as a plain GL_TRIANGLES list. Main (visible) draws keep the stock stream.
    {
      constexpr float kMaxEdgeMeters = 30.f;
      constexpr float kMaxEdgeSq = (kMaxEdgeMeters * 4096.f) * (kMaxEdgeMeters * 4096.f);
      const auto& vtx = tree.unpacked.vertices;
      std::vector<u32> caster;
      caster.reserve(tree.indices.size() * 3);
      u32 a = UINT32_MAX, b = UINT32_MAX;
      u32 dropped = 0;
      auto edge_sq = [&](u32 i, u32 j) {
        float dx = vtx[i].x - vtx[j].x;
        float dy = vtx[i].y - vtx[j].y;
        float dz = vtx[i].z - vtx[j].z;
        return dx * dx + dy * dy + dz * dz;
      };
      for (u32 idx : tree.indices) {
        if (idx == UINT32_MAX) {
          a = UINT32_MAX;
          b = UINT32_MAX;
          continue;
        }
        if (a != UINT32_MAX && b != UINT32_MAX) {
          if (edge_sq(a, b) <= kMaxEdgeSq && edge_sq(b, idx) <= kMaxEdgeSq &&
              edge_sq(a, idx) <= kMaxEdgeSq) {
            caster.push_back(a);
            caster.push_back(b);
            caster.push_back(idx);
          } else {
            dropped++;
          }
        }
        a = b;
        b = idx;
      }
      glGenBuffers(1, &m_trees[l_tree].caster_index_buffer);
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m_trees[l_tree].caster_index_buffer);
      glBufferData(GL_ELEMENT_ARRAY_BUFFER, caster.size() * sizeof(u32), caster.data(),
                   GL_STATIC_DRAW);
      m_trees[l_tree].caster_index_count = (u32)caster.size();
      // restore the VAO's element binding to the stock stream for the main draws.
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, m_trees[l_tree].index_buffer);
      if (dropped > 0) {
        lg::info("shrub caster sanitize: tree {} kept {} tris, dropped {} sliver tris (> {} m)",
                 l_tree, caster.size() / 3, dropped, (int)kMaxEdgeMeters);
      }
    }
#endif

    // The shrub.vert time-of-day LUT uniform tex_T10 is declared sampler2D
    // (a Wx1 texture, texelFetch(ivec2(i,0))). GLES has no glTexImage1D / 1D
    // textures (the arm64 loader binds those slots to NULL), so upload and
    // bind it as a Wx1 GL_TEXTURE_2D, GL_UNSIGNED_BYTE — matching
    // TFragment.cpp / Tie3.cpp. texelFetch on a Wx1 2D is texel-exact on
    // desktop GL too, so this fixes x86 and Android both.
    glActiveTexture(GL_TEXTURE10);
    glGenTextures(1, &m_trees[l_tree].time_of_day_texture);
    glBindTexture(GL_TEXTURE_2D, m_trees[l_tree].time_of_day_texture);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, TIME_OF_DAY_COLOR_COUNT, 1, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);

    // Gperf-particles round 3: second (ping-pong) TOD texture, created
    // identically. tod_current starts on the primary texture so the flag-off
    // path binds exactly time_of_day_texture.
    glGenTextures(1, &m_trees[l_tree].time_of_day_texture_pp);
    glBindTexture(GL_TEXTURE_2D, m_trees[l_tree].time_of_day_texture_pp);
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, TIME_OF_DAY_COLOR_COUNT, 1, 0, GL_RGBA,
                 GL_UNSIGNED_BYTE, nullptr);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    m_trees[l_tree].tod_flip = 0;
    m_trees[l_tree].tod_current = m_trees[l_tree].time_of_day_texture;
    m_trees[l_tree].tod_cache_valid = false;  // Gperf-particles: fresh level re-interpolates
    // Gperf-particles round 3: this tree's static index list is not cached yet.
    m_trees[l_tree].idx_cached = false;
    m_trees[l_tree].cached_idx_count = 0;

    glBindVertexArray(0);
  }

  m_cache.multidraw_offset_per_stripdraw.resize(max_draws);
  m_cache.multidraw_count_buffer.resize(max_num_grps);
  m_cache.multidraw_index_offset_buffer.resize(max_num_grps);
  m_cache.draw_idx_temp.resize(max_draws);
  m_cache.index_temp.resize(max_inds);
  ASSERT(time_of_day_count <= TIME_OF_DAY_COLOR_COUNT);
}

bool Shrub::setup_for_level(const std::string& level, SharedRenderState* render_state) {
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
    return setup_for_level(level, render_state);
  }

  m_textures = &lev_data->textures;
  m_load_id = lev_data->load_id;

  if (m_level_name != level) {
    update_load(lev_data);
    m_has_level = true;
    m_level_name = level;
  } else {
    m_has_level = true;
  }

  if (tfrag3_setup_timer.getMs() > 5) {
    lg::info("Shrub setup: {:.1f}ms", tfrag3_setup_timer.getMs());
  }

  return m_has_level;
}

void Shrub::discard_tree_cache() {
  for (auto& tree : m_trees) {
    glBindTexture(GL_TEXTURE_2D, tree.time_of_day_texture);
#ifdef __ANDROID__
    fprintf(stderr, "F1E-DELTEX site=shrub-tod tex=%u\n", (unsigned)tree.time_of_day_texture);
#endif
    glDeleteTextures(1, &tree.time_of_day_texture);
    // Gperf-particles round 3: delete the ping-pong TOD texture too.
    glDeleteTextures(1, &tree.time_of_day_texture_pp);
    // Grecharged-foliage-wind: delete the per-plant sway-anchor LUT (rebuilt each level load).
    glDeleteTextures(1, &tree.wind_lut_texture);
    glDeleteBuffers(1, &tree.index_buffer);
    if (tree.caster_index_buffer) {
      glDeleteBuffers(1, &tree.caster_index_buffer);
      tree.caster_index_buffer = 0;
    }
    glDeleteBuffers(1, &tree.single_draw_index_buffer);
    glDeleteVertexArrays(1, &tree.vao);
  }

  m_trees.clear();
}

void Shrub::render_all_trees(const TfragRenderSettings& settings,
                             SharedRenderState* render_state,
                             ScopedProfilerNode& prof) {
  for (u32 i = 0; i < m_trees.size(); i++) {
    render_tree(i, settings, render_state, prof);
  }
}

namespace {
void update_vis_mask(std::vector<bool>& vis_mask,
                     const u8* data,
                     u32 data_size,
                     const std::unordered_map<std::string, std::vector<u32>>& name_to_idx) {
  char name_buffer[256];  // ??

  for (u32 i = 0; i < vis_mask.size(); i++) {
    vis_mask[i] = true;
  }

  const u8* end = data + data_size;
  while (true) {
    int name_idx = 0;
    while (*data) {
      name_buffer[name_idx++] = *data;
      data++;
    }
    if (name_idx) {
      ASSERT(name_idx < 254);
      name_buffer[name_idx] = '\0';
      const auto& it = name_to_idx.find(name_buffer);
      if (it != name_to_idx.end()) {
        for (auto x : name_to_idx.at(name_buffer)) {
          vis_mask[x] = 0;
        }
      }
    }

    while (*data == 0) {
      if (data >= end) {
        return;
      }
      data++;
    }
  }
}
}  // namespace

void Shrub::render_tree(int idx,
                        const TfragRenderSettings& settings,
                        SharedRenderState* render_state,
                        ScopedProfilerNode& prof) {
  Timer tree_timer;
  auto& tree = m_trees.at(idx);
  tree.perf.draws = 0;
  tree.perf.wind_draws = 0;
  if (!m_has_level) {
    return;
  }

  if (m_color_result.size() < tree.colors->color_count) {
    m_color_result.resize(tree.colors->color_count);
  }

  // Gperf-particles: per-draw GL state cache (flag-off = identical old path).
  BgDrawStateCache draw_state_cache;
  GLuint bound_tex = 0;
  int last_texture = -1;

#ifdef OG_FEAT_PBR
  // ★ Grecharged-pbr-realtime-fusion ROUND 22 (owner defect A). Shrub never bound PBR material
  // maps, so ALL vegetation was structurally flat. shrub.frag now carries the same shared fused
  // chunk tfrag3.frag does; this is the per-draw material bind that feeds it. Declared at function
  // scope because the batched draw path returns early and must still call finish().
  PbrDrawBinder pbr_binder;
#endif

  // Gperf-particles: attribute the per-tree TOD/upload/cull/index-build setup
  // separately from the draw submission so A35-PERF can steer the batching work.
  {
    auto setup_prof = prof.make_scoped_child("setup");
    (void)setup_prof;
    Timer setup_timer;
    // Gperf-particles: memoize the TOD interp+upload — when itimes is unchanged
    // vs the last cached value, tod_current already holds the correct palette,
    // so skip both the interpolation and the glTexSubImage2D upload (night
    // hot-path). Behind the perf_tod_skip kill switch; result is byte-identical.
    {
      bool tod_same = tree.tod_cache_valid &&
          memcmp(tree.tod_cache_itimes, settings.camera.itimes, 16 * sizeof(s32)) == 0;
      if (render_state->perf_tod_skip && tod_same) {
        // Gperf-particles: itimes unchanged -> skip interp + palette upload;
        // tod_current retains last frame's palette (byte-identical result).
      } else {
        Timer interp_timer;
        interp_time_of_day(settings.camera.itimes, *tree.colors, m_color_result.data());
        tree.perf.tod_time.add(interp_timer.getSeconds());

        // Gperf-particles round 3: time-of-day texture ping-pong. Flag ON => flip
        // the target texture this frame (so the upload does not touch the texture
        // last frame's draws are still sampling on Adreno), then publish it via
        // tod_current so every later bind uses the same texture. Flag OFF =>
        // tod_current stays time_of_day_texture (byte-identical old path).
        if (render_state->perf_tod_pingpong) {
          tree.tod_flip ^= 1;
          tree.tod_current =
              tree.tod_flip ? tree.time_of_day_texture_pp : tree.time_of_day_texture;
        } else {
          tree.tod_current = tree.time_of_day_texture;
        }
        glActiveTexture(GL_TEXTURE10);
        glBindTexture(GL_TEXTURE_2D, tree.tod_current);
        {
          SpartScopedNs _texsub(g_spart_prof.shrub_texsub);
          glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, tree.colors->color_count, 1, GL_RGBA,
                          GL_UNSIGNED_BYTE, m_color_result.data());
        }
        memcpy(tree.tod_cache_itimes, settings.camera.itimes, 16 * sizeof(s32));
        tree.tod_cache_valid = true;
      }
    }

    first_tfrag_draw_setup(settings.camera, render_state, ShaderId::SHRUB);

#ifdef OG_FEAT_PBR
    // ROUND 22: open the per-draw PBR material bind on the SHRUB program. Must come AFTER
    // first_tfrag_draw_setup (which pushes the frame-constant PBR uniforms and parks the neutral
    // maps on units 11-17) and BEFORE the wind-LUT bind below, which now uses unit 18.
    pbr_binder.begin(render_state->shaders[ShaderId::SHRUB].id(), &m_pbr_draws);
    // [cover] shrub is never the tess program, so every height-mapped shrub draw must land in
    // disp_pom. Its own renderer label keeps it separate in the coverage census.
    pbr_binder.set_coverage_context("shrub", nullptr, false, render_state->frame_idx);
#endif

    // Grecharged-foliage-wind: drive the shrub breeze. Set every frame; strength 0 when OFF makes the
    // shader's sway branch a no-op => byte-identical stock render.
    {
      GLuint sid = render_state->shaders[ShaderId::SHRUB].id();
      static const auto s_t0 = std::chrono::steady_clock::now();
      float u_time = std::chrono::duration<float>(std::chrono::steady_clock::now() - s_t0).count();
      float amp =
          Gfx::recharged_active(Gfx::g_global_settings.recharged_foliage_wind) ? foliage_wind_shrub_amp() : 0.0f;
      if (amp > 0.0f) {
        static bool s_logged = false;
        if (!s_logged) {
          s_logged = true;
          lg::info("[foliage-wind] shrub sway ACTIVE amp={} lut_base={} lut_scale={}", amp,
                   tree.wind_lut_base, tree.wind_lut_scale);
        }
      }
      glUniform1f(glGetUniformLocation(sid, "u_time"), u_time);
      glUniform1f(glGetUniformLocation(sid, "u_wind_strength"), amp);
      glUniform1f(glGetUniformLocation(sid, "u_wind_lut_base"), tree.wind_lut_base);
      glUniform1f(glGetUniformLocation(sid, "u_wind_lut_scale"), tree.wind_lut_scale);
      // ROUND 22: unit 18, NOT 11 — 11-17 are the PBR material maps now (tex_PBR_N..tex_PBR_E,
      // parked by first_tfrag_draw_setup / PbrDrawBinder). Shader.cpp's tex_T<i> auto-bind
      // already points tex_T18 at unit 18; this explicit pair keeps the binding self-contained.
      glUniform1i(glGetUniformLocation(sid, "tex_T18"), 18);
      glActiveTexture(GL_TEXTURE18);
      glBindTexture(GL_TEXTURE_2D, tree.wind_lut_texture);
      // (the active unit is restored to 0 a few lines below, as before)
    }

    glBindVertexArray(tree.vao);
    glBindBuffer(GL_ARRAY_BUFFER, tree.vertex_buffer);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,
                 render_state->no_multidraw ? tree.single_draw_index_buffer : tree.index_buffer);
    glActiveTexture(GL_TEXTURE0);
#ifdef __ANDROID__
    // GLES has no settable restart index (glPrimitiveRestartIndex is NULL in the
    // loader — calling it BLR-to-0 / sig=11 fault=0x0 on the first shrub render,
    // same as the A36 tfrag crash). The fixed-index mode restarts on all-1s,
    // which IS UINT32_MAX for our u32 index buffers — identical semantics.
    glEnable(GL_PRIMITIVE_RESTART_FIXED_INDEX);
#else
    glEnable(GL_PRIMITIVE_RESTART);
    glPrimitiveRestartIndex(UINT32_MAX);
#endif
#ifdef OG_FEAT_PBR
    // Grecharged-realtime-lighting round-3 (owner defect B): shrubs must CAST into the sun
    // shadow map (foliage occludes the sun). Depth-only pass over the FULL static strip
    // buffer, mirroring the TFragment / Tie3 caster passes. pbr_shadow_begin_frame is
    // idempotent per frame (accumulates additively across tfrag/tie/shrub). SHRUB is the
    // active program on entry (first_tfrag_draw_setup above); we restore it after.
    if ((Gfx::recharged_active(Gfx::g_global_settings.recharged_pbr_enable) ||
         Gfx::recharged_active(Gfx::g_global_settings.recharged_rt_light_enable)) &&
        tree.index_count > 0 &&
        (pbr_shadow_caster_mask(render_state->frame_idx) & 4) &&
        pbr_shadow_begin_frame(render_state->frame_idx, settings.camera.trans.data())) {
      auto& sh_st = pbr_shadow_state();
      GLint prev_program = 0, prev_fbo = 0, prev_vp[4] = {0, 0, 0, 0}, prev_depth_func = GL_LEQUAL;
      GLboolean prev_scissor = glIsEnabled(GL_SCISSOR_TEST);
      GLboolean prev_cull = glIsEnabled(GL_CULL_FACE);
      GLboolean prev_poly_off = glIsEnabled(GL_POLYGON_OFFSET_FILL);
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
      const auto& ct = settings.camera.trans;
      glUniform4f(glGetUniformLocation(depth_id, "cam_trans"), ct[0], ct[1], ct[2], ct[3]);

      // Full static shrub geometry (ignore per-frame vis: an off-screen bush must keep
      // casting its on-screen shadow). Owner #4 phantom-lines fix: draw the SANITIZED
      // GL_TRIANGLES caster list (built at load, giant cross-instance sliver tris dropped)
      // instead of the raw strip stream — the slivers were the long straight phantom
      // shadow lines (the X on the ground), under both suns since the map is shared.
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree.caster_index_buffer);
      glDrawElements(GL_TRIANGLES, tree.caster_index_count, GL_UNSIGNED_INT, nullptr);
      sh_st.cast_indices += (u64)tree.caster_index_count;

      // Restore the state the main shrub draw expects.
      glUseProgram((GLuint)prev_program);
      glBindFramebuffer(GL_FRAMEBUFFER, (GLuint)prev_fbo);
      glViewport(prev_vp[0], prev_vp[1], prev_vp[2], prev_vp[3]);
      if (prev_scissor) glEnable(GL_SCISSOR_TEST); else glDisable(GL_SCISSOR_TEST);
      if (prev_cull) glEnable(GL_CULL_FACE); else glDisable(GL_CULL_FACE);
      if (prev_poly_off) glEnable(GL_POLYGON_OFFSET_FILL); else glDisable(GL_POLYGON_OFFSET_FILL);
      glPolygonOffset(0.0f, 0.0f);
      if (!prev_depth_test) glDisable(GL_DEPTH_TEST);
      glDepthMask(prev_depth_mask);
      glDepthFunc(prev_depth_func);
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,
                   render_state->no_multidraw ? tree.single_draw_index_buffer : tree.index_buffer);
    }
    // Shrub RECEIVER bind (defect B): sample the sun map so shrubs receive cast shadows.
    // SHRUB is the active program here, so pbr_shadow_bind_receiver's glUniform calls land on it.
    if ((Gfx::recharged_active(Gfx::g_global_settings.recharged_pbr_enable) ||
         Gfx::recharged_active(Gfx::g_global_settings.recharged_rt_light_enable)) &&
        pbr_shadow_state().valid) {
      pbr_shadow_bind_receiver(render_state->shaders[ShaderId::SHRUB].id(),
                               settings.camera.trans.data());
    }
#endif
    if (m_proto_vis_data) {
      update_vis_mask(tree.proto_vis_mask, m_proto_vis_data, m_proto_vis_data_size,
                      tree.proto_name_to_idx);
    }
    tree.perf.tod_time.add(setup_timer.getSeconds());

    tree.perf.cull_time.add(0);
    Timer index_timer;
    SpartScopedNs _index(g_spart_prof.shrub_index);
    if (render_state->no_multidraw) {
      // Gperf-particles round 3: the shrub single-draw index list is fully
      // level-static (make_all_visible_index_list copies every draw's indices
      // unconditionally — no vis/proto-vis input; proto-vis is applied later at
      // draw time and does not change the list contents). When the flag is on,
      // build + upload once per level load and cache the draw ranges; per frame
      // afterwards skip the rebuild+re-upload entirely (the GL_ELEMENT_ARRAY
      // buffer bind already happened above). Flag OFF => exact old per-frame
      // build+upload into m_cache.draw_idx_temp / m_cache.index_temp.
      if (render_state->perf_shrub_static_idx) {
        if (!tree.idx_cached) {
          if (tree.cached_draw_idx.size() < tree.draws->size()) {
            tree.cached_draw_idx.resize(tree.draws->size());
          }
          u32 idx_buffer_size = make_all_visible_index_list(
              tree.cached_draw_idx.data(), m_cache.index_temp.data(), *tree.draws, tree.index_data);
          tree.cached_idx_count = idx_buffer_size;
          glBufferData(GL_ELEMENT_ARRAY_BUFFER, idx_buffer_size * sizeof(u32),
                       m_cache.index_temp.data(), GL_STATIC_DRAW);
          tree.idx_cached = true;
        }
      } else {
        u32 idx_buffer_size = make_all_visible_index_list(
            m_cache.draw_idx_temp.data(), m_cache.index_temp.data(), *tree.draws, tree.index_data);
        glBufferData(GL_ELEMENT_ARRAY_BUFFER, idx_buffer_size * sizeof(u32),
                     m_cache.index_temp.data(), GL_STREAM_DRAW);
      }
    } else {
      make_all_visible_multidraws(m_cache.multidraw_offset_per_stripdraw.data(),
                                  m_cache.multidraw_count_buffer.data(),
                                  m_cache.multidraw_index_offset_buffer.data(), *tree.draws);
    }

    tree.perf.index_time.add(index_timer.getSeconds());
  }

  Timer draw_timer;
  auto draws_prof = prof.make_scoped_child("draws");

  // Gperf-particles round 3: when the static-index cache is active the per-draw
  // singledraw ranges live in tree.cached_draw_idx; otherwise they're the
  // per-frame m_cache.draw_idx_temp. Only used on the no_multidraw path.
  const std::pair<int, int>* singledraw_table =
      (render_state->no_multidraw && render_state->perf_shrub_static_idx && tree.idx_cached)
          ? tree.cached_draw_idx.data()
          : m_cache.draw_idx_temp.data();

  if (render_state->no_multidraw && render_state->batch_singledraw) {
    // Gperf-batching: merge consecutive draws sharing texture+mode into one
    // glDrawElements (see TFragment.cpp — same contiguity + trailing-restart
    // guarantees; every shrub draw's index stream ends with UINT32_MAX,
    // extract_shrub.cpp). Runs break on proto-vis-masked draws (their index
    // range sits between and must not be drawn) and on double-draw modes.
    const auto& alpha_u = tfrag_alpha_uniforms(render_state->shaders[ShaderId::SHRUB].id());
    size_t draw_idx = 0;
    while (draw_idx < tree.draws->size()) {
      const auto& draw = tree.draws->operator[](draw_idx);
      const auto& singledraw_indices = singledraw_table[draw_idx];
      if (!tree.proto_vis_mask.at(draw.proto_idx) || singledraw_indices.second == 0) {
        draw_idx++;
        continue;
      }

      if ((int)draw.tree_tex_id != last_texture) {
        bound_tex = m_textures->at(draw.tree_tex_id);
        glBindTexture(GL_TEXTURE_2D, bound_tex);
        last_texture = draw.tree_tex_id;
      }
      glUniform1i(m_uniforms.decal, draw.mode.get_decal() ? 1 : 0);
      auto double_draw = setup_tfrag_shader_cached(render_state, draw.mode, ShaderId::SHRUB,
                                                   bound_tex, draw_state_cache);
#ifdef OG_FEAT_PBR
      // ROUND 22: per-draw PBR material bind. NOTE this sits before the run-merging loop below,
      // which already refuses to merge across a texture change — so a merged run is guaranteed to
      // share this draw's material.
      pbr_binder.set((s32)draw.tree_tex_id, draw.mode);
#endif

      int first = singledraw_indices.first;
      int count = singledraw_indices.second;
      u32 run_tris = draw.num_triangles;
      tree.perf.draws++;
      size_t next = draw_idx + 1;
      if (double_draw.kind == DoubleDrawKind::NONE) {
        while (next < tree.draws->size()) {
          const auto& d2 = tree.draws->operator[](next);
          const auto& sd2 = singledraw_table[next];
          if (!tree.proto_vis_mask.at(d2.proto_idx)) {
            break;
          }
          if (sd2.second == 0) {
            next++;
            continue;
          }
          if ((int)d2.tree_tex_id != last_texture || d2.mode.as_int() != draw.mode.as_int() ||
              sd2.first != first + count) {
            break;
          }
          count += sd2.second;
          run_tris += d2.num_triangles;
          tree.perf.draws++;
          next++;
        }
      }

      draws_prof.add_draw_call();
      draws_prof.add_tri(run_tris);
      glDrawElements(GL_TRIANGLE_STRIP, count, GL_UNSIGNED_INT, (void*)(first * sizeof(u32)));

      if (double_draw.kind == DoubleDrawKind::AFAIL_NO_DEPTH_WRITE) {
        tree.perf.draws++;
        draws_prof.add_draw_call();
        glUniform1f(alpha_u.alpha_min, -10.f);
        glUniform1f(alpha_u.alpha_max, double_draw.aref_second);
        glDepthMask(GL_FALSE);
        // depth-mask toggled: cached mode's depth state is now stale.
        draw_state_cache.valid = false;
        glDrawElements(GL_TRIANGLE_STRIP, count, GL_UNSIGNED_INT, (void*)(first * sizeof(u32)));
      }
      draw_idx = next;
    }
#ifdef OG_FEAT_PBR
    // ROUND 22: reset u_pbr_mode to 0 + park the neutral maps before leaving, so no material
    // leaks into the next SHRUB user (the next tree, or the next level).
    pbr_binder.finish();
#endif
    glBindVertexArray(0);
    tree.perf.draw_time.add(draw_timer.getSeconds());
    tree.perf.tree_time.add(tree_timer.getSeconds());
    return;
  }

  for (size_t draw_idx = 0; draw_idx < tree.draws->size(); draw_idx++) {
    const auto& draw = tree.draws->operator[](draw_idx);
    if (!tree.proto_vis_mask.at(draw.proto_idx)) {
      continue;
    }
    const auto& multidraw_indices = m_cache.multidraw_offset_per_stripdraw[draw_idx];
    const auto& singledraw_indices = singledraw_table[draw_idx];

    if (render_state->no_multidraw) {
      if (singledraw_indices.second == 0) {
        continue;
      }
    } else {
      if (multidraw_indices.second == 0) {
        continue;
      }
    }

    if ((int)draw.tree_tex_id != last_texture) {
      bound_tex = m_textures->at(draw.tree_tex_id);
      glBindTexture(GL_TEXTURE_2D, bound_tex);
      last_texture = draw.tree_tex_id;
    }

    glUniform1i(m_uniforms.decal, draw.mode.get_decal() ? 1 : 0);

    auto double_draw = setup_tfrag_shader_cached(render_state, draw.mode, ShaderId::SHRUB, bound_tex,
                                                 draw_state_cache);
#ifdef OG_FEAT_PBR
    // ROUND 22: per-draw PBR material bind (see the batched loop above).
    pbr_binder.set((s32)draw.tree_tex_id, draw.mode);
#endif

    draws_prof.add_draw_call();
    draws_prof.add_tri(draw.num_triangles);

    tree.perf.draws++;

    if (render_state->no_multidraw) {
      glDrawElements(GL_TRIANGLE_STRIP, singledraw_indices.second, GL_UNSIGNED_INT,
                     (void*)(singledraw_indices.first * sizeof(u32)));
    } else {
      glMultiDrawElements(GL_TRIANGLE_STRIP,
                          &m_cache.multidraw_count_buffer[multidraw_indices.first], GL_UNSIGNED_INT,
                          &m_cache.multidraw_index_offset_buffer[multidraw_indices.first],
                          multidraw_indices.second);
    }

    switch (double_draw.kind) {
      case DoubleDrawKind::NONE:
        break;
      case DoubleDrawKind::AFAIL_NO_DEPTH_WRITE: {
        tree.perf.draws++;
        draws_prof.add_draw_call();
        const auto& afail_u = tfrag_alpha_uniforms(render_state->shaders[ShaderId::SHRUB].id());
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
          glDrawElements(GL_TRIANGLE_STRIP, singledraw_indices.second, GL_UNSIGNED_INT,
                         (void*)(singledraw_indices.first * sizeof(u32)));
        } else {
          glMultiDrawElements(
              GL_TRIANGLE_STRIP, &m_cache.multidraw_count_buffer[multidraw_indices.first],
              GL_UNSIGNED_INT, &m_cache.multidraw_index_offset_buffer[multidraw_indices.first],
              multidraw_indices.second);
        }
        break;
      } // AFAIL_NO_DEPTH_WRITE
      default:
        ASSERT(false);
    }
  }

#ifdef OG_FEAT_PBR
  // ROUND 22: reset u_pbr_mode to 0 + park the neutral maps so no material leaks into the next
  // SHRUB user (the next tree, or the next level).
  pbr_binder.finish();
#endif
  glBindVertexArray(0);
  tree.perf.draw_time.add(draw_timer.getSeconds());
  tree.perf.tree_time.add(tree_timer.getSeconds());
}

void Shrub::draw_debug_window() {}
