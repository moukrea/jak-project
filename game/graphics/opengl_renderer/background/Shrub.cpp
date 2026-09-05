#include "Shrub.h"

#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <cstring>

#include "common/log/log.h"

#include "game/graphics/gfx.h"
#include "game/graphics/opengl_renderer/background/Tie3.h"
#include "game/graphics/opengl_renderer/background/foliage_wind.h"
#include "game/mips2c/spart_prof.h"

#ifdef __ANDROID__
#include <sys/system_properties.h>
#endif

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
  foliage_wind::frame(render_state->frame_idx);
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
      const auto mat_key = custom_tex::pbr_material_key(lev_data->textures[ti].debug_tpage_name,
                                                        lev_data->textures[ti].debug_name);
      // Gpbr-props-reach-draw : une matiere AUTHOREE SANS AUCUNE CARTE n'a rien qui lise la densite
      // UV — elle pilote l'amplitude POM/tessellation, qui exigent toutes deux une carte de hauteur.
      // Sauter la marche de geometrie garde les nouvelles entrees gratuites au chargement.
      const bool has_any_map = maps->normal_tex || maps->rough_tex || maps->metal_tex ||
                               maps->ao_tex || maps->height_tex || maps->specular_tex ||
                               maps->emissive_tex;
      u32 nsamp = 0;
      float dens = 0.5f;
      bool measured = false;
      if (has_any_map) {
        dens = measure_uv_density_shrub(*lev_data, (s32)ti, &nsamp);
        measured = dens > 0.f;
        if (!measured) {
          dens = 0.5f;  // not enough samples: fall back to the constant the shaders used to assume
        }
      }
      m_pbr_draws.push_back({(s32)ti, *maps, dens, mat_key});
      if (has_any_map) {
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
      } else {
        lg::info(
            "pbr authored-only material (shrub): {} (aucune carte compagnon ; u_pbr_mode bit 256, "
            "les constantes authorees de surfaces.json remplacent les cartes absentes)",
            lev_data->textures[ti].debug_name);
      }
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
    // foliage-wind (owner 2026-09-03) : LE RECENSEMENT des buissons de cet arbre, une entree par
    // instance (identite lue dans `instance_groups`, jamais supposee par `color_index`). C'est la
    // population que `wind_divergent_pairs` juge, avec celle du TIE. Le poids de couronne est celui
    // que le VBO porte REELLEMENT (relu apres quantification).
    {
      std::vector<foliage_wind::Instance> pop;
      pop.reserve(tree.sway_instances.size());
      u32 n_ground = 0, n_sunk = 0, n_stiff = 0;
      for (size_t mi = 0; mi < tree.sway_instances.size(); mi++) {
        const auto& si = tree.sway_instances[mi];
        if (!si.valid) {
          continue;
        }
        foliage_wind::Instance in;
        in.anchor_x = si.x;
        in.anchor_z = si.z;
        in.height_m = (si.ymax - si.base_y) / 4096.f;  // hauteur VISIBLE : couronne - pivot
        in.peak_w = si.peak_w;
        in.low_w = si.low_w;
        in.base_w = si.base_w;
        in.sunk_mm = si.sunk_mm;
        in.ground_found = si.ground_found;
        in.shrub = true;
        in.native_stiff = tree.wind_sidecar_ok && foliage_wind::shrub_native_enabled() &&
                          mi < tree.wind_proto_of_inst.size() &&
                          tree.wind_proto_of_inst[mi] < tree.wind_protos.size() &&
                          tree.wind_protos[tree.wind_proto_of_inst[mi]].stiffness > 0.f;
        n_ground += si.ground_found ? 1 : 0;
        n_sunk += si.sunk_mm > 0 ? 1 : 0;
        n_stiff += in.native_stiff ? 1 : 0;
        pop.push_back(in);
      }
      lg::info(
          "[foliage-wind] SHRUB sway-cover lev={} tree={} instances={} verts={} sway_bytes={} "
          "shared_color_slots={} sol_trouve={} enfonces={} natif_raideur={} sidecar={} natif_on={}",
          lev_data->level_name, l_tree, pop.size(), verts, tree.unpacked.sway.size(),
          tree.sway_shared_color_slots, n_ground, n_sunk, n_stiff, tree.wind_sidecar_ok ? 1 : 0,
          foliage_wind::shrub_native_enabled() ? 1 : 0);
      foliage_wind::set_tree(lev_data->level_name, foliage_wind::kSystemShrub, (int)l_tree, 0,
                             std::move(pop));
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

    // foliage-wind (owner 2026-09-03) : poids + phase de balancement, DEUX octets par sommet, sur la
    // LOCATION 7 — la meme que le TIE, parce que c'est le meme chunk (tie_sway.glsl) qui les lit.
    // VBO parallele au VBO de sommets (LoaderStages, etape shrub). Normalise : 0..255 -> 0..1.
    // Essai 11 : SwayRecord de 8 octets (FoliageWindLaw.h) — 7 = poids SIGNE (GL_SHORT normalise),
    // 8 = phase (GL_UNSIGNED_BYTE normalise), 9 = matrix_idx (entier, index du texel de vent natif).
    glBindBuffer(GL_ARRAY_BUFFER, loader_data->shrub_sway_data.at(l_tree));
    glEnableVertexAttribArray(7);
    glVertexAttribPointer(7, 1, GL_SHORT, GL_TRUE, (GLsizei)foliage_law::kSwayRecordBytes,
                          (void*)offsetof(foliage_law::SwayRecord, w));
    glEnableVertexAttribArray(8);
    glVertexAttribPointer(8, 1, GL_UNSIGNED_BYTE, GL_TRUE, (GLsizei)foliage_law::kSwayRecordBytes,
                          (void*)offsetof(foliage_law::SwayRecord, ph));
    glEnableVertexAttribArray(9);
    glVertexAttribIPointer(9, 1, GL_UNSIGNED_SHORT, (GLsizei)foliage_law::kSwayRecordBytes,
                           (void*)offsetof(foliage_law::SwayRecord, inst));
    glBindBuffer(GL_ARRAY_BUFFER, m_trees[l_tree].vertex_buffer);

    // foliage-wind (essai 11) — le vent NATIF : un texel par matrice, l'etat du ressort par
    // emplacement de vent. Cree meme quand le sidecar manque (texels a zero, `wind_active` faux) :
    // c'est l'uniforme `u_shrub_native_on` qui rend le chemin inerte, pas l'absence de texture.
    {
      auto& t = m_trees[l_tree];
      t.src = &tree;
      const size_t n_mat = std::max<size_t>(tree.packed_vertices.matrices.size(), 1);
      t.wind_texels.assign(n_mat * 4, 0.f);
      t.wind_state.assign(((size_t)tree.wind_max_idx + 1) * 4, 0.f);
      t.wind_last_time = 0;
      t.wind_seeded = false;
      t.wind_logged = false;
      t.wind_active = tree.wind_sidecar_ok && tree.wind_instances_stiff > 0 &&
                      foliage_wind::shrub_native_enabled() &&
                      tree.sway_instances.size() == tree.packed_vertices.matrices.size();
      glGenTextures(1, &t.wind_tex);
      glBindTexture(GL_TEXTURE_2D, t.wind_tex);
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, (GLsizei)n_mat, 1, 0, GL_RGBA, GL_FLOAT,
                   t.wind_texels.data());
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
      glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
      glBindTexture(GL_TEXTURE_2D, 0);
    }

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
    foliage_wind::forget(m_level_name, foliage_wind::kSystemShrub);
    m_level_name = "";
    discard_tree_cache();
    return false;
  }

  if (m_has_level && lev_data->load_id != m_load_id) {
    m_has_level = false;
    m_textures = nullptr;
    foliage_wind::forget(m_level_name, foliage_wind::kSystemShrub);
    m_level_name = "";
    discard_tree_cache();
    return setup_for_level(level, render_state);
  }

  m_textures = &lev_data->textures;
  m_load_id = lev_data->load_id;

  if (m_level_name != level) {
    // foliage-wind : le niveau que ce renderer lachait sort de la population du recensement.
    foliage_wind::forget(m_level_name, foliage_wind::kSystemShrub);
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
    glDeleteBuffers(1, &tree.index_buffer);
    if (tree.caster_index_buffer) {
      glDeleteBuffers(1, &tree.caster_index_buffer);
      tree.caster_index_buffer = 0;
    }
    glDeleteBuffers(1, &tree.single_draw_index_buffer);
    glDeleteVertexArrays(1, &tree.vao);
    if (tree.wind_tex) {
      glDeleteTextures(1, &tree.wind_tex);
      tree.wind_tex = 0;
    }
  }

  m_trees.clear();
}

// foliage-wind (essai 11) — LE RESSORT DE ND PAR BUISSON, INTEGRE SUR CPU UNE FOIS PAR IMAGE.
// Meme arithmetique que le TIE (do_wind_math, transcrit de l'EE ; sur PS2 le shrub execute le MEME
// bloc, shrub_asm.md:957-1057) : ring slot `(wind-time + wind-index) & 63`, etat persistant par
// wind-index, raideur du prototype attenuee par la distance camera comme l'EE le fait
// (`stiffness * clamp01(1 - (d - near-stiff) * rlength-stiff)`), `rc_ticks` pas de 1/60 s par image
// dessinee (la correction de cadence D1, la meme que Tie3). Le cisaillement `s` (sans dimension) part
// dans le texel de l'instance ; shrub.vert l'applique en `s * (y - pivot)`, pivot = sol trouve.
void Shrub::update_native_wind(Tree& tree,
                               const TfragRenderSettings& settings,
                               SharedRenderState* render_state) {
  if (!tree.wind_active || !tree.src) {
    return;
  }
  size_t n = 0;
  const auto* ww = (const Tie3::WindWork*)foliage_wind::game_wind_bytes(&n);
  if (!ww || n != sizeof(Tie3::WindWork)) {
    return;  // aucun DMA de vent encore recu par Tie3 sur cette image : rien a integrer
  }
  const auto& src = *tree.src;
  const size_t n_mat = src.packed_vertices.matrices.size();
  if (tree.wind_texels.size() < n_mat * 4 || src.wind_index.size() != n_mat ||
      src.wind_proto_of_inst.size() != n_mat) {
    return;
  }
  const int ticks = foliage_wind::wind_ticks_for(ww->wind_time, tree.wind_last_time,
                                                 tree.wind_seeded, ww->paused != 0);
  const float cx = settings.camera.trans.x(), cy = settings.camera.trans.y(),
              cz = settings.camera.trans.z();
  float peak_s = 0.f;
  u32 integrated = 0;
  for (size_t mi = 0; mi < n_mat; mi++) {
    float* tex = &tree.wind_texels[mi * 4];
    const auto& si = src.sway_instances[mi];
    const auto& proto = src.wind_protos[src.wind_proto_of_inst[mi]];
    const float span_u = si.ymax - si.base_y;
    if (!si.valid || !(proto.stiffness > 0.f) || !(span_u > 0.f)) {
      tex[0] = tex[1] = tex[2] = tex[3] = 0.f;
      continue;
    }
    // (y - pivot) = w * k, avec w = (y - pivot) / span * taille  =>  k = span / taille
    tex[2] = span_u / foliage_law::size_factor(span_u / 4096.f);
    tex[3] = 1.f;
    const u16 widx = src.wind_index[mi];
    if ((size_t)widx * 4 + 3 >= tree.wind_state.size()) {
      tex[0] = tex[1] = 0.f;
      continue;
    }
    // la raideur effective : attenuee par la distance, comme l'EE
    const float dx = si.x - cx, dy = 0.5f * (si.ymin + si.ymax) - cy, dz = si.z - cz;
    const float d = std::sqrt(dx * dx + dy * dy + dz * dz);
    float fade = 1.f - (d - proto.near_stiff) * proto.rlength_stiff;
    fade = std::min(std::max(fade, 0.f), 1.f);
    const float eff = proto.stiffness * fade;
    float* st = &tree.wind_state[(size_t)widx * 4];
    if (ticks <= 0) {
      // aucun tick de logique : on reapplique le cisaillement persiste (vf27 du dernier pas)
      tex[0] = st[0];
      tex[1] = st[1];
    } else {
      std::array<math::Vector4f, 4> scratch;
      float audit[8] = {0, 0, 0, 0, 0, 0, 0, 0};
      for (int k = 0; k < ticks - 1; k++) {
        for (auto& r : scratch) {
          r = math::Vector4f(0, 0, 0, 0);
        }
        do_wind_math(widx, tree.wind_state.data(), *ww, eff, 1.0f, nullptr,
                     ww->wind_time - (u32)(ticks - 1) + (u32)k, scratch, nullptr);
      }
      for (auto& r : scratch) {
        r = math::Vector4f(0, 0, 0, 0);
      }
      do_wind_math(widx, tree.wind_state.data(), *ww, eff, 1.0f, nullptr, ww->wind_time, scratch,
                   audit);
      tex[0] = audit[4];  // vf27.x : le cisaillement stock, deja multiplie par la raideur
      tex[1] = audit[5];  // vf27.z
      foliage_wind::note_native_sample(audit[6], audit[7] > 0.5f);
      integrated++;
    }
    const float mag = std::sqrt(tex[0] * tex[0] + tex[1] * tex[1]);
    if (mag > peak_s) {
      peak_s = mag;
    }
  }
  foliage_wind::note_shrub_native_shear_peak(peak_s);
  glActiveTexture(GL_TEXTURE18);
  glBindTexture(GL_TEXTURE_2D, tree.wind_tex);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, (GLsizei)n_mat, 1, GL_RGBA, GL_FLOAT,
                  tree.wind_texels.data());
  glActiveTexture(GL_TEXTURE0);
  if (!tree.wind_logged) {
    tree.wind_logged = true;
    lg::info("[foliage-wind] SHRUB native ACTIVE lev={} matrices={} raideur_instances={} "
             "integrees={} ticks={} wind_time={} peak_shear={:.4f} — le ressort de ND tourne sur les "
             "buissons (frame {})",
             m_level_name, n_mat, src.wind_instances_stiff, integrated, ticks, ww->wind_time,
             peak_s, render_state->frame_idx);
  }
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

    glBindVertexArray(tree.vao);
    // foliage-wind (owner 2026-09-03) : les uniformes du chunk partage, APRES `first_tfrag_draw_setup`
    // (qui vient d'ecrire 0 dans l'amplitude) et APRES le bind du VAO (pour que la ligne de preuve
    // lise l'etat REEL de l'attribut 7). Option eteinte => amplitude 0 => le bloc du shader est
    // saute et le sommet ressort a l'identique.
    foliage_wind::push_uniforms(render_state->shaders[ShaderId::SHRUB].id(), render_state->frame_idx,
                                "shrub");
    foliage_wind::mark_drawn(m_level_name, foliage_wind::kSystemShrub, idx, 0);
    // foliage-wind (essai 11) : le vent NATIF des buissons — ressort integre, texel par instance,
    // unite de texture 18 (l'ancienne LUT de vent occupait la meme, elle est retiree). Hors option
    // Recharged : c'est du stock restaure ; `u_shrub_native_on` = 0 quand rien n'est pret.
    {
      update_native_wind(tree, settings, render_state);
      const GLuint prog = render_state->shaders[ShaderId::SHRUB].id();
      const GLint on_loc = glGetUniformLocation(prog, "u_shrub_native_on");
      const GLint tex_loc = glGetUniformLocation(prog, "tex_T18");
      const bool on = tree.wind_active && tree.wind_seeded;
      if (on) {
        glActiveTexture(GL_TEXTURE18);
        glBindTexture(GL_TEXTURE_2D, tree.wind_tex);
        glActiveTexture(GL_TEXTURE0);
      }
      if (tex_loc >= 0) {
        glUniform1i(tex_loc, 18);
      }
      if (on_loc >= 0) {
        glUniform1i(on_loc, on ? 1 : 0);
      }
    }
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
