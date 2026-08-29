#include "LoadingScreenTextures.h"

#include "common/log/log.h"
#include "common/util/FileUtil.h"

#include "game/graphics/pipelines/opengl.h"
#include "third-party/stb_image/stb_image.h"

// Fentes VRAM, dans l'ordre. Voir l'en-tete pour la correspondance avec les constantes GOAL.
static constexpr int kLoadingScreenBaseSlot = 8311;
static const char* kLoadingScreenNames[] = {
    "loading_jak",
    "loading_precursor",
};

static u64 upload_loading_texture(const u8* data, int w, int h) {
  GLuint tex_id;
  glGenTextures(1, &tex_id);
  GLint old_tex;
  glGetIntegerv(GL_ACTIVE_TEXTURE, &old_tex);
  glActiveTexture(GL_TEXTURE0);
  glBindTexture(GL_TEXTURE_2D, tex_id);
  // RGBA byte order is identical on both backends (little-endian).
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, data);
  glGenerateMipmap(GL_TEXTURE_2D);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR_MIPMAP_LINEAR);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
  glActiveTexture(old_tex);
  return tex_id;
}

// Installe `tex_id` (dimensions w x h) dans la fente `slot` du pool.
static void give_to_slot(TexturePool& pool, u64 tex_id, int w, int h, int slot, const char* name) {
  TextureInput in;
  in.gpu_texture = tex_id;
  in.w = w;
  in.h = h;
  in.debug_page_name = "PC-LOADING";
  in.debug_name = name;
  in.id = pool.allocate_pc_port_texture(GameVersion::Jak1);
  pool.give_texture_and_load_to_vram(in, slot);
}

void load_loading_screen_textures(TexturePool& pool, GameVersion version) {
  if (version != GameVersion::Jak1) {
    return;
  }

  auto dir = file_util::get_recharged_assets_dir();

  for (int i = 0; i < (int)(sizeof(kLoadingScreenNames) / sizeof(kLoadingScreenNames[0])); i++) {
    const int slot = kLoadingScreenBaseSlot + i;
    const char* name = kLoadingScreenNames[i];
    auto path = dir / (std::string(name) + ".png");

    int w = 0, h = 0;
    u8* data = nullptr;
    if (fs::exists(path)) {
      // Pas de sous-echantillonnage : ces deux images sont dessinees a leur taille finale, et
      // diviser l'atlas de glyphes le detruirait.
      data = stbi_load(path.string().c_str(), &w, &h, nullptr, STBI_rgb_alpha);
      if (!data) {
        lg::warn("loading-screen: failed to load texture {}", path.string());
      }
    } else {
      lg::warn("loading-screen: missing texture {}", path.string());
    }

    if (data) {
      give_to_slot(pool, upload_loading_texture(data, w, h), w, h, slot, name);
      stbi_image_free(data);
      lg::info("loading-screen: loaded {} ({}x{}) -> vram slot {}", name, w, h, slot);
      continue;
    }

    // REPLI : un texel ENTIEREMENT TRANSPARENT, jamais rien. Sans cette fente remplie,
    // DirectRenderer.cpp:425 ne trouve pas la texture et lie le damier gris 16x16 de
    // TexturePool::get_placeholder_texture() -- l'ecran de chargement montrerait alors un damier
    // la ou doit etre la silhouette. « Une resolution pire que le clip est pire que rien » :
    // un asset absent doit ne RIEN peindre, pas peindre un defaut.
    const u8 clear[4] = {0, 0, 0, 0};
    give_to_slot(pool, upload_loading_texture(clear, 1, 1), 1, 1, slot, name);
    lg::warn("loading-screen: {} absent -> fente {} remplie d'un texel transparent (rien ne sera "
             "dessine, au lieu du damier de remplacement)",
             name, slot);
  }
}
