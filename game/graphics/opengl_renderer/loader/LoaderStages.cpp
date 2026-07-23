#include "LoaderStages.h"

#include "CustomTextureReplacements.h"
#include "Loader.h"

#include "common/global_profiler/GlobalProfiler.h"

#ifdef OG_FEAT_PBR
// Grecharged-pbr-materials: add_texture reads the custom-assets toggle directly.
#include "game/graphics/gfx.h"
#endif

constexpr float LOAD_BUDGET = 4.5f;

#ifdef __ANDROID__
// GLES has no GL_UNSIGNED_INT_8_8_8_8_REV — glTexImage2D rejects it, the
// texture never gets storage, and every fr3 texture (font + level) samples
// BLACK as an incomplete texture (A41 run-3: zero pool misses yet a black
// frame). On little-endian, RGBA + UNSIGNED_BYTE is byte-identical — the
// same substitution as TexturePool::upload_to_gpu / FramebufferTexturePair.
constexpr GLenum kRgbaTexType = GL_UNSIGNED_BYTE;
#else
constexpr GLenum kRgbaTexType = GL_UNSIGNED_INT_8_8_8_8_REV;
#endif

/*!
 * Upload a texture to the GPU, and give it to the pool.
 */
u64 add_texture(TexturePool& pool, const tfrag3::Texture& tex, bool is_common) {
  // External-asset-root: record every texture key (for the optional dump_keys
  // marker) and look up a user PNG replacement.
  custom_tex::dump_key(tex.debug_tpage_name, tex.debug_name);
  auto rep = custom_tex::lookup(tex.debug_tpage_name, tex.debug_name);

  GLuint gl_tex;
  glActiveTexture(GL_TEXTURE0);
  glGenTextures(1, &gl_tex);
  glBindTexture(GL_TEXTURE_2D, gl_tex);
  if (rep) {
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, rep->w, rep->h, 0, GL_RGBA, kRgbaTexType,
                 rep->rgba.data());
  } else {
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, tex.w, tex.h, 0, GL_RGBA, kRgbaTexType,
                 tex.data.data());
  }
  glGenerateMipmap(GL_TEXTURE_2D);
  float aniso = 0.0f;
  glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY, &aniso);
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY, aniso);
  if (tex.load_to_pool) {
    TextureInput in;
    in.debug_page_name = tex.debug_tpage_name;
    in.debug_name = tex.debug_name;
    // Logical dims must stay the ORIGINAL texture's: src_data below points at the
    // baked buffer, and pool consumers read w*h*4 from it — replacement-sized dims
    // over the original buffer are an OOB crash when the user PNG is larger. The
    // GL object holds the (possibly higher-res) replacement; sampling is normalized.
    in.w = tex.w;
    in.h = tex.h;
    in.gpu_texture = gl_tex;
    in.common = is_common;
    in.id = PcTextureId::from_combo_id(tex.combo_id);
    // src_data is stored as a long-lived pointer by the pool (used for texture
    // animation source comparison). The replacement's rgba buffer is local, so
    // keep src_data pointing at the baked level data even when the GPU texture
    // was swapped for a user PNG.
    in.src_data = (const u8*)tex.data.data();
    pool.give_texture(in);
  }

#ifdef OG_FEAT_PBR
  // Grecharged-pbr-materials: create the companion PBR maps for this texture from
  // suffixed PNGs (user dir or the package-bundled set; see lookup_suffixed for source gating).
  // Grecharged-bundled-textures: PBR maps may come from the USER dir (load_custom_assets-
  // gated inside lookup_suffixed) or the package-BUNDLED set (master-gated) — probe whenever
  // the master is up; lookup_suffixed applies the per-source gates.
  if (Gfx::recharged_master_active()) {
    const auto* n = custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_normal");
    const auto* r = custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_roughness");
    const auto* m = custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_metallic");
    const auto* a = custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_ao");
    const auto* h = custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_height");
    const auto* s = custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_specular");
    const auto* e = custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_emissive");
    // NOTE: lookup_suffixed returns a pointer into a single per-call thread-local
    // buffer, so it must be consumed (uploaded) before the next call. Below we
    // re-fetch each map immediately before its upload to keep that contract.
    if (n || r || m || h || s || e) {
      auto make_map = [&](const custom_tex::ReplacementImage* img) -> u32 {
        if (!img) {
          return 0;
        }
        GLuint id = 0;
        glGenTextures(1, &id);
        glBindTexture(GL_TEXTURE_2D, id);
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, img->w, img->h, 0, GL_RGBA, GL_UNSIGNED_BYTE,
                     img->rgba.data());
        glGenerateMipmap(GL_TEXTURE_2D);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_REPEAT);
        glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_REPEAT);
        return id;
      };
      custom_tex::PbrMaterialMaps maps;
      // Re-fetch each present map immediately before upload (thread-local buffer reuse).
      if (n) {
        maps.normal_tex =
            make_map(custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_normal"));
      }
      if (r) {
        maps.rough_tex = make_map(
            custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_roughness"));
      }
      if (m) {
        maps.metal_tex = make_map(
            custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_metallic"));
      }
      if (a) {
        maps.ao_tex =
            make_map(custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_ao"));
      }
      if (h) {
        maps.height_tex = make_map(
            custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_height"));
      }
      if (s) {
        maps.specular_tex = make_map(
            custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_specular"));
      }
      if (e) {
        maps.emissive_tex = make_map(
            custom_tex::lookup_suffixed(tex.debug_tpage_name, tex.debug_name, "_emissive"));
      }
      // Overwrite registry; free any stale GL ids from a prior level load of the same name.
      auto prev = custom_tex::register_pbr_material(tex.debug_name, maps);
      GLuint old_ids[7] = {prev.normal_tex, prev.rough_tex,    prev.metal_tex,   prev.ao_tex,
                           prev.height_tex, prev.specular_tex, prev.emissive_tex};
      for (GLuint oid : old_ids) {
        if (oid) {
          glDeleteTextures(1, &oid);
        }
      }
      // Restore the base texture binding on unit 0 (what the surrounding loader
      // flow left bound before this block).
      glActiveTexture(GL_TEXTURE0);
      glBindTexture(GL_TEXTURE_2D, gl_tex);
    }
  }
#endif

  return gl_tex;
}

class TextureLoaderStage : public LoaderStage {
 public:
  TextureLoaderStage() : LoaderStage("texture") {}
  bool run(Timer& timer, LoaderInput& data) override {
    constexpr int MAX_TEX_BYTES_PER_FRAME = 1024 * 1024;

    int bytes_this_run = 0;
    int tex_this_run = 0;
    if (data.lev_data->textures.size() < data.lev_data->level->textures.size()) {
      std::unique_lock<std::mutex> tpool_lock(data.tex_pool->mutex());
      while (data.lev_data->textures.size() < data.lev_data->level->textures.size()) {
        auto& tex = data.lev_data->level->textures[data.lev_data->textures.size()];
        data.lev_data->textures.push_back(add_texture(*data.tex_pool, tex, false));
        bytes_this_run += tex.w * tex.h * 4;
        tex_this_run++;
        if (tex_this_run > 20) {
          break;
        }
        if (bytes_this_run > MAX_TEX_BYTES_PER_FRAME || timer.getMs() > LOAD_BUDGET) {
          break;
        }
      }
    }
    return data.lev_data->textures.size() == data.lev_data->level->textures.size();
  }
  void reset() override {}
};

class TfragLoadStage : public LoaderStage {
 public:
  TfragLoadStage() : LoaderStage("tfrag") {}
  bool run(Timer& timer, LoaderInput& data) override {
    if (m_done) {
      return true;
    }

    if (data.lev_data->level->tfrag_trees.front().empty()) {
      m_done = true;
      return true;
    }

    if (!m_opengl_created) {
      for (int geo = 0; geo < tfrag3::TFRAG_GEOS; geo++) {
        auto& in_trees = data.lev_data->level->tfrag_trees[geo];
        for (auto& in_tree : in_trees) {
          GLuint& tree_out = data.lev_data->tfrag_vertex_data[geo].emplace_back();
          glGenBuffers(1, &tree_out);
          glBindBuffer(GL_ARRAY_BUFFER, tree_out);
          glBufferData(GL_ARRAY_BUFFER,
                       in_tree.unpacked.vertices.size() * sizeof(tfrag3::PreloadedVertex), nullptr,
                       GL_STATIC_DRAW);
        }
      }
      m_opengl_created = true;
      return false;
    }

    constexpr u32 CHUNK_SIZE = 32768;
    u32 uploaded_bytes = 0;
    [[maybe_unused]] u32 unique_buffers = 0;

    while (true) {
      bool complete_tree;

      if (data.lev_data->level->tfrag_trees[m_next_geo].empty()) {
        complete_tree = true;
      } else {
        const auto& tree = data.lev_data->level->tfrag_trees[m_next_geo][m_next_tree];
        u32 end_vert_in_tree = tree.unpacked.vertices.size();
        // the number of vertices we'd need to finish the tree right now
        size_t num_verts_left_in_tree = end_vert_in_tree - m_next_vert;
        size_t start_vert_for_chunk;
        size_t end_vert_for_chunk;

        if (num_verts_left_in_tree > CHUNK_SIZE) {
          complete_tree = false;
          // should only do partial
          start_vert_for_chunk = m_next_vert;
          end_vert_for_chunk = start_vert_for_chunk + CHUNK_SIZE;
          m_next_vert += CHUNK_SIZE;
        } else {
          // should do all!
          start_vert_for_chunk = m_next_vert;
          end_vert_for_chunk = end_vert_in_tree;
          complete_tree = true;
        }

        glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->tfrag_vertex_data[m_next_geo][m_next_tree]);
        u32 upload_size =
            (end_vert_for_chunk - start_vert_for_chunk) * sizeof(tfrag3::PreloadedVertex);
        glBufferSubData(GL_ARRAY_BUFFER, start_vert_for_chunk * sizeof(tfrag3::PreloadedVertex),
                        upload_size, tree.unpacked.vertices.data() + start_vert_for_chunk);
        uploaded_bytes += upload_size;
      }

      if (complete_tree) {
        unique_buffers++;
        // and move on to next tree
        m_next_vert = 0;
        m_next_tree++;
        if (m_next_tree >= data.lev_data->level->tfrag_trees[m_next_geo].size()) {
          m_next_tree = 0;
          m_next_geo++;
          if (m_next_geo >= tfrag3::TFRAG_GEOS) {
            m_next_tree = true;
            m_next_tree = 0;
            m_next_geo = 0;
            m_next_vert = 0;
            m_done = true;
            return true;
          }
        }
        return false;
      }

      if (timer.getMs() > LOAD_BUDGET || (uploaded_bytes / 1024) > 2048) {
        return false;
      }
    }
  }

  void reset() override {
    m_done = false;
    m_opengl_created = false;
    m_next_geo = 0;
    m_next_tree = 0;
    m_next_vert = 0;
  }

 private:
  bool m_done = false;
  bool m_opengl_created = false;
  u32 m_next_geo = 0;
  u32 m_next_tree = 0;
  u32 m_next_vert = 0;
};

class ShrubLoadStage : public LoaderStage {
 public:
  ShrubLoadStage() : LoaderStage("shrub") {}
  bool run(Timer& timer, LoaderInput& data) override {
    if (m_done) {
      return true;
    }

    if (data.lev_data->level->shrub_trees.empty()) {
      m_done = true;
      return true;
    }

    if (!m_opengl_created) {
      for (auto& in_tree : data.lev_data->level->shrub_trees) {
        GLuint& tree_out = data.lev_data->shrub_vertex_data.emplace_back();
        glGenBuffers(1, &tree_out);
        glBindBuffer(GL_ARRAY_BUFFER, tree_out);
        glBufferData(GL_ARRAY_BUFFER,
                     in_tree.unpacked.vertices.size() * sizeof(tfrag3::ShrubGpuVertex), nullptr,
                     GL_STATIC_DRAW);
      }
      m_opengl_created = true;
      return false;
    }

    constexpr u32 CHUNK_SIZE = 32768;
    u32 uploaded_bytes = 0;

    while (true) {
      const auto& tree = data.lev_data->level->shrub_trees[m_next_tree];
      u32 end_vert_in_tree = tree.unpacked.vertices.size();
      // the number of vertices we'd need to finish the tree right now
      size_t num_verts_left_in_tree = end_vert_in_tree - m_next_vert;
      size_t start_vert_for_chunk;
      size_t end_vert_for_chunk;

      bool complete_tree;

      if (num_verts_left_in_tree > CHUNK_SIZE) {
        complete_tree = false;
        // should only do partial
        start_vert_for_chunk = m_next_vert;
        end_vert_for_chunk = start_vert_for_chunk + CHUNK_SIZE;
        m_next_vert += CHUNK_SIZE;
      } else {
        // should do all!
        start_vert_for_chunk = m_next_vert;
        end_vert_for_chunk = end_vert_in_tree;
        complete_tree = true;
      }

      glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->shrub_vertex_data[m_next_tree]);
      u32 upload_size =
          (end_vert_for_chunk - start_vert_for_chunk) * sizeof(tfrag3::ShrubGpuVertex);
      glBufferSubData(GL_ARRAY_BUFFER, start_vert_for_chunk * sizeof(tfrag3::ShrubGpuVertex),
                      upload_size, tree.unpacked.vertices.data() + start_vert_for_chunk);
      uploaded_bytes += upload_size;

      if (complete_tree) {
        // and move on to next tree
        m_next_vert = 0;
        m_next_tree++;
        if (m_next_tree >= data.lev_data->level->shrub_trees.size()) {
          m_done = true;
          return true;
        }
      }

      if (timer.getMs() > LOAD_BUDGET || (uploaded_bytes / 128) > 2048) {
        return false;
      }
    }
  }

  void reset() override {
    m_done = false;
    m_opengl_created = false;
    m_next_tree = 0;
    m_next_vert = 0;
  }

 private:
  bool m_done = false;
  bool m_opengl_created = false;
  u32 m_next_tree = 0;
  u32 m_next_vert = 0;
};

class TieLoadStage : public LoaderStage {
 public:
  TieLoadStage() : LoaderStage("tie") {}
  bool run(Timer& timer, LoaderInput& data) override {
    if (m_done) {
      return true;
    }

    if (data.lev_data->level->tie_trees.front().empty()) {
      m_done = true;
      return true;
    }

    if (!m_opengl_created) {
      auto evt = scoped_prof("tie-opengl-create");
      for (int geo = 0; geo < tfrag3::TIE_GEOS; geo++) {
        auto& in_trees = data.lev_data->level->tie_trees[geo];
        for (auto& in_tree : in_trees) {
          LevelData::TieOpenGL& tree_out = data.lev_data->tie_data[geo].emplace_back();
          glGenBuffers(1, &tree_out.vertex_buffer);
          glBindBuffer(GL_ARRAY_BUFFER, tree_out.vertex_buffer);
          glBufferData(GL_ARRAY_BUFFER,
                       in_tree.unpacked.vertices.size() * sizeof(tfrag3::PreloadedVertex), nullptr,
                       GL_STATIC_DRAW);

          glGenBuffers(1, &tree_out.index_buffer);
          glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, tree_out.index_buffer);
          glBufferData(GL_ELEMENT_ARRAY_BUFFER, in_tree.unpacked.indices.size() * sizeof(u32),
                       nullptr, GL_STATIC_DRAW);
        }
      }
      m_opengl_created = true;
      return false;
    }

    if (!m_verts_done) {
      auto evt = scoped_prof("tie-verts");
      constexpr u32 CHUNK_SIZE = 32768;
      u32 uploaded_bytes = 0;

      while (true) {
        const auto& tree = data.lev_data->level->tie_trees[m_next_geo][m_next_tree];
        u32 end_vert_in_tree = tree.unpacked.vertices.size();
        // the number of vertices we'd need to finish the tree right now
        size_t num_verts_left_in_tree = end_vert_in_tree - m_next_vert;
        size_t start_vert_for_chunk;
        size_t end_vert_for_chunk;

        bool complete_tree;

        if (num_verts_left_in_tree > CHUNK_SIZE) {
          complete_tree = false;
          // should only do partial
          start_vert_for_chunk = m_next_vert;
          end_vert_for_chunk = start_vert_for_chunk + CHUNK_SIZE;
          m_next_vert += CHUNK_SIZE;
        } else {
          // should do all!
          start_vert_for_chunk = m_next_vert;
          end_vert_for_chunk = end_vert_in_tree;
          complete_tree = true;
        }

        glBindBuffer(GL_ARRAY_BUFFER,
                     data.lev_data->tie_data[m_next_geo][m_next_tree].vertex_buffer);
        u32 upload_size =
            (end_vert_for_chunk - start_vert_for_chunk) * sizeof(tfrag3::PreloadedVertex);
        {
          auto bsd = scoped_prof(fmt::format("buffer-{}k", upload_size / 1024).c_str());
          glBufferSubData(GL_ARRAY_BUFFER, start_vert_for_chunk * sizeof(tfrag3::PreloadedVertex),
                          upload_size, tree.unpacked.vertices.data() + start_vert_for_chunk);
        }

        uploaded_bytes += upload_size;

        if (complete_tree) {
          // and move on to next tree
          m_next_vert = 0;
          m_next_tree++;
          if (m_next_tree >= data.lev_data->level->tie_trees[m_next_geo].size()) {
            m_next_tree = 0;
            m_next_geo++;
            while (m_next_geo < tfrag3::TIE_GEOS &&
                   data.lev_data->level->tie_trees[m_next_geo].empty()) {
              m_next_geo++;
            }
            if (m_next_geo >= tfrag3::TIE_GEOS) {
              m_verts_done = true;
              m_next_tree = 0;
              m_next_geo = 0;
              m_next_vert = 0;
              return false;
            }
          }
        }

        if (timer.getMs() > LOAD_BUDGET || (uploaded_bytes / 1024) > 2048) {
          return false;
        }
      }
    }

    if (!m_wind_indices_done) {
      auto evt = scoped_prof("tie-wind");
      bool abort = false;
      for (; m_next_geo < tfrag3::TIE_GEOS; m_next_geo++) {
        auto& geo_trees = data.lev_data->level->tie_trees[m_next_geo];
        for (; m_next_tree < geo_trees.size(); m_next_tree++) {
          if (abort) {
            return false;
          }
          auto& in_tree = geo_trees[m_next_tree];
          auto& out_tree = data.lev_data->tie_data[m_next_geo][m_next_tree];
          size_t wind_idx_buffer_len = 0;
          for (auto& draw : in_tree.instanced_wind_draws) {
            wind_idx_buffer_len += draw.vertex_index_stream.size();
          }
          if (wind_idx_buffer_len > 0) {
            out_tree.has_wind = true;
            glGenBuffers(1, &out_tree.wind_indices);
            glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, out_tree.wind_indices);
            std::vector<u32> temp;
            temp.resize(wind_idx_buffer_len);
            u32 off = 0;
            for (auto& draw : in_tree.instanced_wind_draws) {
              memcpy(temp.data() + off, draw.vertex_index_stream.data(),
                     draw.vertex_index_stream.size() * sizeof(u32));
              off += draw.vertex_index_stream.size();
            }

            glBufferData(GL_ELEMENT_ARRAY_BUFFER, wind_idx_buffer_len * sizeof(u32), temp.data(),
                         GL_STATIC_DRAW);
            abort = true;
          }
        }
        m_next_tree = 0;
      }

      m_wind_indices_done = true;
      m_next_geo = 0;
      m_next_vert = 0;
      m_next_tree = 0;

      if (timer.getMs() > LOAD_BUDGET) {
        return false;
      }
    }

    if (!m_indices_done) {
      auto evt = scoped_prof("tie-ind");
      constexpr u32 CHUNK_SIZE = 32768 * 8;
      u32 uploaded_bytes = 0;

      while (true) {
        const auto& tree = data.lev_data->level->tie_trees[m_next_geo][m_next_tree];
        u32 end_ind_in_tree = tree.unpacked.indices.size();
        // the number of indices we'd need to finish the tree right now
        size_t num_inds_left_in_tree = end_ind_in_tree - m_next_vert;
        size_t start_ind_for_chunk;
        size_t end_ind_for_chunk;

        bool complete_tree;

        if (num_inds_left_in_tree > CHUNK_SIZE) {
          complete_tree = false;
          // should only do partial
          start_ind_for_chunk = m_next_vert;
          end_ind_for_chunk = start_ind_for_chunk + CHUNK_SIZE;
          m_next_vert += CHUNK_SIZE;
        } else {
          // should do all!
          start_ind_for_chunk = m_next_vert;
          end_ind_for_chunk = end_ind_in_tree;
          complete_tree = true;
        }

        glBindBuffer(GL_ELEMENT_ARRAY_BUFFER,
                     data.lev_data->tie_data[m_next_geo][m_next_tree].index_buffer);
        u32 upload_size = (end_ind_for_chunk - start_ind_for_chunk) * sizeof(u32);
        glBufferSubData(GL_ELEMENT_ARRAY_BUFFER, start_ind_for_chunk * sizeof(u32), upload_size,
                        tree.unpacked.indices.data() + start_ind_for_chunk);
        uploaded_bytes += upload_size;

        if (complete_tree) {
          // and move on to next tree
          m_next_vert = 0;
          m_next_tree++;
          if (m_next_tree >= data.lev_data->level->tie_trees[m_next_geo].size()) {
            m_next_tree = 0;
            m_next_geo++;
            while (m_next_geo < tfrag3::TIE_GEOS &&
                   data.lev_data->level->tie_trees[m_next_geo].empty()) {
              m_next_geo++;
            }
            if (m_next_geo >= tfrag3::TIE_GEOS) {
              m_indices_done = true;
              m_next_tree = 0;
              m_next_geo = 0;
              m_next_vert = 0;
              m_done = true;
              return true;
            }
          }
        }

        if (timer.getMs() > LOAD_BUDGET || (uploaded_bytes / 1024) > 2048) {
          return false;
        }
      }
    }

    return false;
  }

  void reset() override {
    m_done = false;
    m_opengl_created = false;
    m_next_geo = 0;
    m_next_tree = 0;
    m_next_vert = 0;
    m_verts_done = false;
    m_indices_done = false;
    m_wind_indices_done = false;
  }

 private:
  bool m_done = false;
  bool m_opengl_created = false;
  bool m_verts_done = false;
  bool m_indices_done = false;
  bool m_wind_indices_done = false;
  u32 m_next_geo = 0;
  u32 m_next_tree = 0;
  u32 m_next_vert = 0;
};

class CollideLoaderStage : public LoaderStage {
 public:
  CollideLoaderStage() : LoaderStage("collide") {}
  bool run(Timer& /*timer*/, LoaderInput& data) override {
    if (m_done) {
      return true;
    }
    if (!m_opengl_created) {
      glGenBuffers(1, &data.lev_data->collide_vertices);
      glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->collide_vertices);
      glBufferData(
          GL_ARRAY_BUFFER,
          data.lev_data->level->collision.vertices.size() * sizeof(tfrag3::CollisionMesh::Vertex),
          nullptr, GL_STATIC_DRAW);
      m_opengl_created = true;
      return false;
    }

    u32 start = m_vtx;
    u32 end = std::min((u32)data.lev_data->level->collision.vertices.size(), start + 32768);
    glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->collide_vertices);
    glBufferSubData(GL_ARRAY_BUFFER, start * sizeof(tfrag3::CollisionMesh::Vertex),
                    (end - start) * sizeof(tfrag3::CollisionMesh::Vertex),
                    data.lev_data->level->collision.vertices.data() + start);
    m_vtx = end;

    if (m_vtx == data.lev_data->level->collision.vertices.size()) {
      m_done = true;
      return true;
    } else {
      return false;
    }
  }
  void reset() override {
    m_opengl_created = false;
    m_vtx = 0;
    m_done = false;
  }

 private:
  bool m_opengl_created = false;
  u32 m_vtx = 0;
  bool m_done = false;
};

class StallLoaderStage : public LoaderStage {
 public:
  StallLoaderStage() : LoaderStage("stall") {}
  bool run(Timer&, LoaderInput& /*data*/) override {
    m_count++;
    if (m_count > 10) {
      return true;
    }
    return false;
  }

  void reset() override { m_count = 0; }

 private:
  int m_count = 0;
};

class HfragLoaderStage : public LoaderStage {
 public:
  HfragLoaderStage() : LoaderStage("hfrag") {}
  void reset() override {
    m_done = false;
    m_opengl = false;
    m_vtx_uploaded = false;
    m_idx = 0;
  }

  bool run(Timer&, LoaderInput& data) override {
    if (m_done) {
      return true;
    }

    if (!m_opengl) {
      glGenBuffers(1, &data.lev_data->hfrag_indices);
      glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, data.lev_data->hfrag_indices);
      glBufferData(GL_ELEMENT_ARRAY_BUFFER,
                   data.lev_data->level->hfrag.indices.size() * sizeof(u32), nullptr,
                   GL_STATIC_DRAW);

      glGenBuffers(1, &data.lev_data->hfrag_vertices);
      glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->hfrag_vertices);
      glBufferData(GL_ARRAY_BUFFER,
                   data.lev_data->level->hfrag.vertices.size() * sizeof(tfrag3::HfragmentVertex),
                   nullptr, GL_STATIC_DRAW);
      m_opengl = true;
    }

    if (!m_vtx_uploaded) {
      u32 start = m_idx;
      m_idx = std::min(start + 32768, (u32)data.lev_data->level->hfrag.indices.size());
      glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->hfrag_indices);
      glBufferSubData(GL_ARRAY_BUFFER, start * sizeof(u32), (m_idx - start) * sizeof(u32),
                      data.lev_data->level->hfrag.indices.data() + start);
      if (m_idx != data.lev_data->level->hfrag.indices.size()) {
        return false;
      } else {
        m_idx = 0;
        m_vtx_uploaded = true;
      }
    }

    u32 start = m_idx;
    m_idx = std::min(start + 32768, (u32)data.lev_data->level->hfrag.vertices.size());
    glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->hfrag_vertices);
    glBufferSubData(GL_ARRAY_BUFFER, start * sizeof(tfrag3::HfragmentVertex),
                    (m_idx - start) * sizeof(tfrag3::HfragmentVertex),
                    data.lev_data->level->hfrag.vertices.data() + start);

    if (m_idx != data.lev_data->level->hfrag.vertices.size()) {
      return false;
    } else {
      m_done = true;
      return true;
    }
    return true;
  }

 private:
  bool m_done = false;
  bool m_opengl = false;
  bool m_vtx_uploaded = false;
  u32 m_idx = 0;
};

MercLoaderStage::MercLoaderStage() : LoaderStage("merc") {}
void MercLoaderStage::reset() {
  m_done = false;
  m_opengl = false;
  m_vtx_uploaded = false;
  m_idx = 0;
}

bool MercLoaderStage::run(Timer& /*timer*/, LoaderInput& data) {
  if (m_done) {
    return true;
  }

  if (!m_opengl) {
    glGenBuffers(1, &data.lev_data->merc_indices);
    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, data.lev_data->merc_indices);
    glBufferData(GL_ELEMENT_ARRAY_BUFFER,
                 data.lev_data->level->merc_data.indices.size() * sizeof(u32), nullptr,
                 GL_STATIC_DRAW);

    glGenBuffers(1, &data.lev_data->merc_vertices);
    glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->merc_vertices);
    glBufferData(GL_ARRAY_BUFFER,
                 data.lev_data->level->merc_data.vertices.size() * sizeof(tfrag3::MercVertex),
                 nullptr, GL_STATIC_DRAW);
    m_opengl = true;
  }

  if (!m_vtx_uploaded) {
    u32 start = m_idx;
    m_idx = std::min(start + 32768, (u32)data.lev_data->level->merc_data.indices.size());
    glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->merc_indices);
    glBufferSubData(GL_ARRAY_BUFFER, start * sizeof(u32), (m_idx - start) * sizeof(u32),
                    data.lev_data->level->merc_data.indices.data() + start);
    if (m_idx != data.lev_data->level->merc_data.indices.size()) {
      return false;
    } else {
      m_idx = 0;
      m_vtx_uploaded = true;
    }
  }

  u32 start = m_idx;
  m_idx = std::min(start + 32768, (u32)data.lev_data->level->merc_data.vertices.size());
  glBindBuffer(GL_ARRAY_BUFFER, data.lev_data->merc_vertices);
  glBufferSubData(GL_ARRAY_BUFFER, start * sizeof(tfrag3::MercVertex),
                  (m_idx - start) * sizeof(tfrag3::MercVertex),
                  data.lev_data->level->merc_data.vertices.data() + start);

  if (m_idx != data.lev_data->level->merc_data.vertices.size()) {
    return false;
  } else {
#ifdef __ANDROID__
    // F1a: Adreno 618 (V@0502) SIGSEGVs inside the driver (null+0x28) on
    // specific merc glDrawElements after this stage's chunked
    // glBufferSubData uploads — deterministically, with state-legal,
    // GPU==CPU-verified data (F1a runs 4-16). A read-only
    // glMapBufferRange+unmap of the buffer DEFUSES the draw every time
    // (run-16: the killer draw executed exactly while a per-draw map-sync
    // probe was active and faulted on the first frame past the probe's
    // cap). Force the driver to finalize both BOs once at upload
    // completion — one-time per level, read-only, no behavioral change.
    for (GLenum tgt : {(GLenum)GL_ELEMENT_ARRAY_BUFFER, (GLenum)GL_ARRAY_BUFFER}) {
      GLuint buf = (tgt == GL_ELEMENT_ARRAY_BUFFER) ? data.lev_data->merc_indices
                                                    : data.lev_data->merc_vertices;
      glBindBuffer(tgt, buf);
      GLint64 sz = 0;
      glGetBufferParameteri64v(tgt, GL_BUFFER_SIZE, &sz);
      if (sz > 0) {
        void* p = glMapBufferRange(tgt, 0, (GLsizeiptr)sz, GL_MAP_READ_BIT);
        if (p) {
          glUnmapBuffer(tgt);
        }
      }
      glBindBuffer(tgt, 0);
    }
#endif
    m_done = true;
    for (auto& model : data.lev_data->level->merc_data.models) {
      data.lev_data->merc_model_lookup[model.name] = &model;
      (*data.mercs)[model.name].push_back({&model, data.lev_data->load_id, data.lev_data});
    }
    return true;
  }
  return true;
}

std::vector<std::unique_ptr<LoaderStage>> make_loader_stages() {
  std::vector<std::unique_ptr<LoaderStage>> ret;
  ret.push_back(std::make_unique<TieLoadStage>());
  ret.push_back(std::make_unique<TextureLoaderStage>());
  ret.push_back(std::make_unique<TfragLoadStage>());
  ret.push_back(std::make_unique<ShrubLoadStage>());
  ret.push_back(std::make_unique<CollideLoaderStage>());
  ret.push_back(std::make_unique<MercLoaderStage>());
  ret.push_back(std::make_unique<HfragLoaderStage>());
  ret.push_back(std::make_unique<StallLoaderStage>());
  return ret;
}
