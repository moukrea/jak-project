#include "LoaderStages.h"
#include "game/graphics/opengl_renderer/background/foliage_wind.h"
#include <unordered_map>

#include "CustomTextureReplacements.h"
#include "Loader.h"
#include "ManagedAssets.h"

#include <vector>

#include "common/global_profiler/GlobalProfiler.h"
#include "common/log/log.h"
#include "common/util/rss_census.h"
#include "game/system/asset_manifest.h"
#include "game/graphics/gl_query_census.h"

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
thread_local u64 g_last_add_texture_bytes = 0;
// Grecharged-texture-hotreload (voir LoaderStages.h).
thread_local u64 g_last_add_texture_fp = 0;
thread_local bool g_last_add_texture_swapped = false;

namespace {
// Empreinte ECHANTILLONNEE du bloc reellement televerse. Hacher 16 Mo par texture (2048x2048
// RGBA) coute plus cher que le televersement lui-meme ; 4096 octets repartis sur tout le bloc,
// plus la longueur, les dimensions et le nom de la source, separent un PNG HD de la texture
// d'origine dans tous les cas qui nous interessent (elles n'ont ni la meme taille, ni les memes
// dimensions, ni la meme source). Ce n'est pas un condensat cryptographique et ne pretend pas
// l'etre : c'est un temoin de CHANGEMENT.
u64 upload_fingerprint(const char* tag, int w, int h, const u8* p, size_t n) {
  u64 hsh = 1469598103934665603ull;
  auto mix = [&hsh](u64 v) {
    hsh ^= v;
    hsh *= 1099511628211ull;
  };
  for (const char* c = tag; c && *c; ++c) {
    mix((u8)*c);
  }
  mix((u64)w);
  mix((u64)h);
  mix((u64)n);
  if (p && n) {
    const size_t step = n > 4096 ? n / 4096 : 1;
    for (size_t i = 0; i < n; i += step) {
      mix(p[i]);
    }
  }
  return hsh;
}
}  // namespace

u64 add_texture(TexturePool& pool,
                const tfrag3::Texture& tex,
                bool is_common,
                GLuint replacing_gl) {
  // External-asset-root: record every texture key (for the optional dump_keys
  // marker) and look up a replacement.
  custom_tex::dump_key(tex.debug_tpage_name, tex.debug_name);
  g_last_add_texture_swapped = false;
  // Grecharged-managed-assets: precedence (owner) user > managed > bundled >
  // stock. base_source() decides without decoding pixels: a USER hit keeps
  // the PNG path; otherwise the managed pack outranks the bundled set.
  // Gshield-load-and-crash: one more rung between them —
  //   user PNG > managed KTX2 > BAKED KTX2 > bundled PNG > stock.
  // The baked tier is the bundled set precompressed offline (ASTC + offline mips), so it
  // enters the SAME `managed` variable and takes the same upload branch below: that branch
  // is already proven on device, and duplicating it is how the two would drift apart.
  // autoport 2026-08-26: the whole point of the managed tier is that it does NOT
  // decode a PNG here. A53-TEXLOOKUP times the branch that was taken and names it,
  // so "KTX2 removed the decode" is a measured line and not a claim.
  Timer tex_lookup_timer;
  std::optional<managed_assets::CompressedTex> managed;
  // TRUE when `managed` came from the PRE-BAKED tier rather than the downloaded pack. The only
  // thing it changes is which index the companion maps come from (same-source rule).
  bool managed_is_baked = false;
  // Gfont-regression : la page de police (gamefontnew) ne consulte NI le pack telecharge NI le
  // niveau pre-cuit — un pack qui porterait cette page masquerait l'atlas Urbanist, et le texte
  // du jeu est encode pour lui (voir CustomTextureReplacements.h). Elle passe directement au
  // lookup() PNG, qui la resout sans porte depuis le paquet livre.
  const bool font_page = custom_tex::is_font_atlas(tex.debug_tpage_name);
  if (!font_page && custom_tex::base_source(tex.debug_tpage_name, tex.debug_name) !=
                        custom_tex::BaseSource::User) {
    managed = managed_assets::lookup_base(tex.debug_tpage_name, tex.debug_name);
    // baked_available() est faux des que le PROFIL du GPU n'est pas l'ASTC — pas seulement
    // quand la capacite manque. Mesure du 2026-08-26 : un pilote de bureau GL 4.6 annonce
    // `astc=true` et prenait donc ce chemin, contre ce que ce commentaire affirmait. La garde
    // est maintenant le profil (CustomTextureReplacements.cpp::baked_gpu_reads_astc), donc le
    // chemin PNG du bureau est rigoureusement inchange, et c'est une course qui le dit.
    if (!managed && custom_tex::baked_available()) {
      managed = custom_tex::lookup_baked_base(tex.debug_tpage_name, tex.debug_name);
      managed_is_baked = managed.has_value();
    }
  }
  std::optional<custom_tex::ReplacementImage> rep;
  if (!managed) {
    rep = custom_tex::lookup(tex.debug_tpage_name, tex.debug_name);
  }
  // Evaluated HERE (nothing has dropped `managed` yet). A52-TEXSTALL below re-evaluates its own,
  // deliberately: by then the test pattern or an upload failure may have sent it back to stock.
  const char* tex_lookup_source = managed ? (managed_is_baked ? "baked-ktx2" : "managed-ktx2")
                                  : rep   ? "png"
                                          : "stock";
  const double t_lookup_ms = tex_lookup_timer.getMs();
  if (t_lookup_ms > 100.0) {
    fmt::print("A53-TEXLOOKUP name={} {}x{} source={} decodage={:.0f}ms\n", tex.debug_name,
               managed ? (int)managed->info.width : (rep ? rep->w : 0),
               managed ? (int)managed->info.height : (rep ? rep->h : 0), tex_lookup_source,
               t_lookup_ms);
  }
  Timer tex_call_timer;  // autoport 2026-08-26: attribuer les blocages a un appel GL

  // Grecharged-texture-hotreload : CE QUI PART REELLEMENT VERS LE GPU, decrit sur la branche qui
  // l'envoie. Le chemin d'en-dessous change d'avis en cours de route (le damier jette `managed`,
  // un `upload_bound_texture` rate retombe sur le stock), donc une empreinte deduite APRES coup
  // des variables `managed`/`rep` decrirait parfois une autre image que celle qui a ete envoyee.
  const u8* fp_ptr = nullptr;
  size_t fp_len = 0;
  const char* fp_tag = "stock";
  int fp_w = tex.w, fp_h = tex.h;

  GLuint gl_tex;
  glActiveTexture(GL_TEXTURE0);
  glGenTextures(1, &gl_tex);
  glBindTexture(GL_TEXTURE_2D, gl_tex);
  if (managed) {
    // Managed KTX2: offline mip chain uploaded compressed — NO glGenerateMipmap.
    fp_ptr = managed->payload.data();
    fp_len = managed->payload.size();
    fp_tag = managed_is_baked ? "baked-ktx2" : "managed-ktx2";
    fp_w = (int)managed->info.width;
    fp_h = (int)managed->info.height;
    if (!managed_assets::upload_bound_texture(*managed)) {
      // glTexStorage2D may already have made the storage immutable — the
      // stock fallback needs a fresh texture object.
      glDeleteTextures(1, &gl_tex);
      glGenTextures(1, &gl_tex);
      glBindTexture(GL_TEXTURE_2D, gl_tex);
      managed.reset();
      managed_is_baked = false;
      glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, tex.w, tex.h, 0, GL_RGBA, kRgbaTexType,
                   tex.data.data());
      fp_ptr = (const u8*)tex.data.data();
      fp_len = tex.data.size() * sizeof(tex.data[0]);
      fp_tag = "stock";
      fp_w = tex.w;
      fp_h = tex.h;
    }
  } else if (rep) {
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, rep->w, rep->h, 0, GL_RGBA, kRgbaTexType,
                 rep->rgba.data());
    fp_ptr = rep->rgba.data();
    fp_len = rep->rgba.size();
    fp_tag = rep->src;
    fp_w = rep->w;
    fp_h = rep->h;
  } else {
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, tex.w, tex.h, 0, GL_RGBA, kRgbaTexType,
                 tex.data.data());
    fp_ptr = (const u8*)tex.data.data();
    fp_len = tex.data.size() * sizeof(tex.data[0]);
    fp_tag = "stock";
    fp_w = tex.w;
    fp_h = tex.h;
  }
  g_last_add_texture_fp = upload_fingerprint(fp_tag, fp_w, fp_h, fp_ptr, fp_len);
  if (asset_manifest::enabled()) {
    asset_manifest::record("texture-base",
                           fmt::format("{}/{}/{}/{}x{}", tex.debug_tpage_name, tex.debug_name,
                                       fp_tag, fp_w, fp_h),
                           0, fp_ptr, fp_len);
  }
  const double t_upload_ms = tex_call_timer.getMs();
  // Grecharged-managed-assets: a KTX2 payload already carries its whole mip chain,
  // filtered offline. Regenerating it would both cost the stall this tier exists to
  // remove and overwrite the better chain with a runtime box filter.
  if (!managed) {
    glGenerateMipmap(GL_TEXTURE_2D);
  }
  const double t_mip_ms = tex_call_timer.getMs() - t_upload_ms;
  if (t_upload_ms + t_mip_ms > 100.0) {
    fmt::print("A52-TEXSTALL name={} {}x{} source={} upload={:.0f}ms mipmap={:.0f}ms\n",
               tex.debug_name,
               managed ? (int)managed->info.width : (rep ? rep->w : tex.w),
               managed ? (int)managed->info.height : (rep ? rep->h : tex.h),
               managed ? (managed_is_baked ? "baked-ktx2" : "managed-ktx2")
                       : (rep ? "png" : "stock"),
               t_upload_ms, t_mip_ms);
  }
  // autoport 2026-08-26: glGetFloatv is a SYNCHRONOUS query — it drains the driver's
  // pipeline. Called once per uploaded texture it turned the boot texture burst into
  // 8 stalls of 1.2-2.1 s (94 % of 11.5 s of staging, median stage 6 ms) on the
  // NVIDIA Shield, so the title logo appeared seconds after its sound cue. The value
  // is a fixed hardware limit: query it once per context, not once per texture.
  static const float aniso = [] {
    float a = 0.0f;
    glGetFloatv(GL_MAX_TEXTURE_MAX_ANISOTROPY, &a);
    return a;
  }();
  glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_MAX_ANISOTROPY, aniso);
  if (font_page) {
    // Gfont-regression : ce qui a ete REELLEMENT televerse pour cette page, avec sa source. Le
    // dessin direct relit ce registre au moment ou il LIE la texture (FONTTEX bind) : c'est la
    // preuve au point de lecture, pas au chargement.
    const char* font_src = rep ? rep->src : "stock";
    custom_tex::note_font_atlas_upload(tex.debug_tpage_name + "/" + tex.debug_name, font_src,
                                       gl_tex, rep ? rep->w : tex.w, rep ? rep->h : tex.h);
    fmt::print("FONTTEX upload name={}/{} source={} gl={} w={} h={}\n", tex.debug_tpage_name,
               tex.debug_name, font_src, gl_tex, rep ? rep->w : tex.w, rep ? rep->h : tex.h);
  }
  // Real uploaded bytes for the streaming budgets (see LoaderStages.h).
  g_last_add_texture_bytes = managed ? managed->payload.size()
                             : rep   ? rep->rgba.size() * 4 / 3  // + generated mips
                                     : u64(tex.w) * tex.h * 4 * 4 / 3;
  // Grecharged-texture-hotreload : RE-RESOLUTION D'UNE TEXTURE DEJA RESIDENTE. `replacing_gl`
  // non nul veut dire « cet objet GL est deja donne au pool et deja lie a des slots VRAM ;
  // remplace-le par celui qu'on vient de televerser ». Tout ce qui precede — resolution de la
  // source, portes, televersement, mips, anisotropie — est le chemin du chargement, mot pour
  // mot : c'est la seule facon que les deux ne divergent pas.
  if (replacing_gl) {
    bool swapped = true;
    if (tex.load_to_pool) {
      swapped = pool.swap_gl_texture(PcTextureId::from_combo_id(tex.combo_id), replacing_gl, gl_tex);
    }
    if (!swapped) {
      // Le pool ne connait plus ce couple : on rend l'ancien objet et on ne compte rien. Jeter
      // l'ancien ici le retirerait sous les slots qui le lient encore.
      glDeleteTextures(1, &gl_tex);
      gl_tex = replacing_gl;
    }
    g_last_add_texture_swapped = swapped;
  } else if (tex.load_to_pool) {
    g_last_add_texture_swapped = false;
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
      // Grecharged-texture-hotreload : le regime est estampille au DEBUT de la passe, pas a sa
      // fin. Une bascule qui tombe PENDANT le chargement d'un niveau laisserait sinon un prefixe
      // de textures resolues sous l'ancien regime derriere une estampille neuve — et ce
      // prefixe-la ne serait jamais rattrape.
      if (data.lev_data->textures.empty()) {
        data.lev_data->tex_regime = custom_tex::hotreload_regime();
      }
      while (data.lev_data->textures.size() < data.lev_data->level->textures.size()) {
        auto& tex = data.lev_data->level->textures[data.lev_data->textures.size()];
        data.lev_data->textures.push_back(add_texture(*data.tex_pool, tex, false));
        data.lev_data->tex_upload_fp.push_back(g_last_add_texture_fp);
        // real uploaded bytes: replacements/managed packs are far larger
        // than the baked tex.w*h*4 (the audited budget blindness)
        bytes_this_run += (int)g_last_add_texture_bytes;
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
        // foliage-wind (owner 2026-09-03) : le VBO de balancement, DEUX octets par sommet, televerse
        // d'un bloc (il pese 1/16 du VBO de sommets). Toujours cree, meme option eteinte : c'est
        // l'uniforme d'amplitude a 0 qui rend le chemin inerte, pas l'absence du buffer. Longueur
        // FORCEE sur celle du VBO de sommets, complete a ZERO si le tableau calcule est plus court
        // (meme regle que le TIE, LoaderStages `tie` : un sommet non classe est FIGE).
        GLuint& sway_out = data.lev_data->shrub_sway_data.emplace_back();
        glGenBuffers(1, &sway_out);
        glBindBuffer(GL_ARRAY_BUFFER, sway_out);
        const size_t sway_want = in_tree.unpacked.vertices.size() * foliage_law::kSwayRecordBytes;
        if (in_tree.unpacked.sway.size() == sway_want) {
          glBufferData(GL_ARRAY_BUFFER, sway_want, in_tree.unpacked.sway.data(), GL_STATIC_DRAW);
        } else {
          lg::warn(
              "[foliage-wind] SHRUB sway buffer DESYNCHRONISE lev={} : {} octets calcules pour {} "
              "sommets ({} attendus) — complete a zero, les sommets en trop ne balanceront pas.",
              data.lev_data->level->level_name, in_tree.unpacked.sway.size(),
              in_tree.unpacked.vertices.size(), sway_want);
          std::vector<u8> padded(sway_want, 0);
          const size_t n = std::min(sway_want, in_tree.unpacked.sway.size());
          std::copy(in_tree.unpacked.sway.begin(), in_tree.unpacked.sway.begin() + n,
                    padded.begin());
          glBufferData(GL_ARRAY_BUFFER, sway_want, padded.data(), GL_STATIC_DRAW);
        }
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

          // Grecharged-foliage-wind3 (defaut D2) : VBO parallele du balancement, DEUX octets par
          // sommet (poids + phase d'instance), derive par TieTree::unpack de l'ancrage de CHAQUE
          // instance et du lexique de vegetation. Un
          // seul glBufferData — village1 pese ~3,4 Mo ici contre 52,6 Mo pour les sommets.
          // Toujours cree, meme quand le balancement est ETEINT : c'est l'uniforme d'amplitude a 0
          // qui rend le chemin inerte, pas l'absence du buffer, et un buffer conditionnel donnerait
          // un VAO different selon un reglage.
          //
          // LA LONGUEUR EST FORCEE SUR CELLE DU VBO DE SOMMETS, ET CE N'EST PAS DE LA PARANOIA :
          // `mesh_presubdivide_level` tournait APRES `unpack()` et INVENTAIT des sommets. Cet
          // appel a ete RETIRE par la purge des reglages hereditaires (lighting-legacy-purge,
          // 2026-09-11) : MeshSubdivide.cpp n'est plus compile dans le jeu. Tant que cet appel
          // existait, un tableau plus court laissait l'attribut 7 lire hors des bornes pour les
          // sommets inventes. On complete donc a ZERO : un sommet que la
          // passe de classement n'a pas vu est FIGE, jamais aleatoire — la meme regle que pour un
          // mur, et le cas est dit a voix haute.
          // Runtime-only compact contact indices: 0 is neutral, never inferred from color_index.
          const size_t contact_nv = in_tree.unpacked.vertices.size();
          std::vector<u8> contact_flags(contact_nv, 0);
          bool contact_mapping_ok = true;
          for (const auto& draw : in_tree.static_draws) {
            if (!draw.plain_indices.empty()) {
              contact_mapping_ok = false;  // no prototype-to-index tiling is available for these
            }
            size_t run_i = 0;
            for (const auto& vg : draw.vis_groups) {
              const bool plant = vg.tie_proto_idx < in_tree.proto_names.size() &&
                  foliage_wind::shrub_contact_prototype(in_tree.proto_names[vg.tie_proto_idx]);
              u32 remaining = vg.num_inds;
              while (remaining && run_i < draw.runs.size()) {
                const auto& run = draw.runs[run_i];
                const u32 count = (u32)run.length + 1;
                if (count > remaining) { contact_mapping_ok = false; break; }
                for (size_t v = run.vertex0; v < (size_t)run.vertex0 + run.length; ++v) {
                  if (v < contact_nv) contact_flags[v] |= plant ? 1 : 2;
                  else contact_mapping_ok = false;
                }
                ++run_i;
                remaining -= count;
              }
              if (remaining) contact_mapping_ok = false;
            }
            if (run_i != draw.runs.size()) contact_mapping_ok = false;
          }
          std::unordered_map<u32, const tfrag3::TieTree::SwayInstance*> contact_instances;
          for (const auto& si : in_tree.sway_instances) {
            if (si.valid && si.ymax > si.base_y) contact_instances[si.matrix_idx] = &si;
          }
          std::vector<u32> contact_indices(contact_nv, 0);
          std::vector<std::array<float, 4>> contact_anchors(1, {0.f, 0.f, 0.f, 0.f});
          std::unordered_map<u32, u32> contact_lut_index;
          size_t contact_vi = 0, contact_verts = 0;
          for (const auto& group : in_tree.packed_vertices.matrix_groups) {
            const size_t count = (size_t)(group.end_vert - group.start_vert);
            const auto si_it = contact_instances.find((u32)group.matrix_idx);
            if (group.matrix_idx >= 0 && si_it != contact_instances.end()) {
              for (size_t k = 0; k < count && contact_vi + k < contact_nv; ++k) {
                if (contact_flags[contact_vi + k] != 1) continue;
                auto inserted = contact_lut_index.emplace((u32)group.matrix_idx,
                                                          (u32)contact_anchors.size());
                if (inserted.second) {
                  const auto& si = *si_it->second;
                  contact_anchors.push_back({si.x, si.base_y, si.z, si.ymax - si.base_y});
                }
                contact_indices[contact_vi + k] = inserted.first->second;
                ++contact_verts;
              }
            }
            contact_vi += count;
          }
          contact_mapping_ok = contact_mapping_ok && contact_vi == contact_nv;
          // perf-gl-waits : une limite du contexte, lue UNE fois pour toute la course.
          const GLint contact_max_tex = gl_query_census::limit(GL_MAX_TEXTURE_SIZE);
          if (contact_mapping_ok && contact_verts && contact_anchors.size() <= (size_t)contact_max_tex) {
            glGenBuffers(1, &tree_out.contact_buffer);
            glBindBuffer(GL_ARRAY_BUFFER, tree_out.contact_buffer);
            glBufferData(GL_ARRAY_BUFFER, contact_indices.size() * sizeof(u32),
                         contact_indices.data(), GL_STATIC_DRAW);
            glGenTextures(1, &tree_out.contact_texture);
            glBindTexture(GL_TEXTURE_2D, tree_out.contact_texture);
            glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA32F, (GLsizei)contact_anchors.size(), 1, 0,
                         GL_RGBA, GL_FLOAT, contact_anchors.data());
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
            glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
            glBindTexture(GL_TEXTURE_2D, 0);
          }
          tree_out.contact_mapping_ok = contact_mapping_ok &&
              contact_anchors.size() <= (size_t)contact_max_tex;
          tree_out.contact_instances = contact_anchors.size() - 1;
          tree_out.contact_vertices = contact_verts;
          if (contact_verts || !contact_mapping_ok) {
            lg::info("[foliage-contact] TIE load lev={} geo={} plants={} vertices={} bytes={} mapping_ok={} active={}",
                     data.lev_data->level->level_name, geo, contact_anchors.size() - 1,
                     contact_verts, tree_out.contact_buffer ? contact_indices.size() * sizeof(u32) : 0,
                     contact_mapping_ok, tree_out.contact_texture != 0);
          }
          glGenBuffers(1, &tree_out.sway_buffer);
          glBindBuffer(GL_ARRAY_BUFFER, tree_out.sway_buffer);
          const size_t sway_want = in_tree.unpacked.vertices.size() * foliage_law::kSwayRecordBytes;
          if (in_tree.unpacked.sway.size() == sway_want) {
            glBufferData(GL_ARRAY_BUFFER, sway_want, in_tree.unpacked.sway.data(), GL_STATIC_DRAW);
          } else {
            lg::warn(
                "[foliage-wind] TIE sway buffer DESYNCHRONISE lev={} geo={} : {} octets calcules "
                "pour {} sommets ({} attendus) — complete a zero, les sommets en trop ne "
                "balanceront pas.",
                data.lev_data->level->level_name, geo, in_tree.unpacked.sway.size(),
                in_tree.unpacked.vertices.size(), sway_want);
            std::vector<u8> padded(sway_want, 0);
            const size_t n = std::min(sway_want, in_tree.unpacked.sway.size());
            std::copy(in_tree.unpacked.sway.begin(), in_tree.unpacked.sway.begin() + n,
                      padded.begin());
            glBufferData(GL_ARRAY_BUFFER, sway_want, padded.data(), GL_STATIC_DRAW);
          }
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
    data.lev_data->merc_vertex_count = data.lev_data->level->merc_data.vertices.size();
    // Gmemory-ceiling-and-crash : les deux `glBufferData` ci-dessus RESERVENT le tampon GPU
    // du niveau. Sur un appareil a memoire unifiee la reservation est prise dans la RAM
    // systeme, donc elle entre dans le RSS. Le marqueur l'encadre pour que « ce mapping de
    // 150 Mo vient de la » soit une MESURE et pas une deduction.
    rss_census::mark("merc-bufdata");
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
    gl_query_census::Armed _ap("loader-f1a-defuse");
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
    rss_census::mark("merc-uploade");
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
