#pragma once

#include "game/graphics/opengl_renderer/loader/common.h"

std::vector<std::unique_ptr<LoaderStage>> make_loader_stages();
// `replacing_gl` != 0 : Grecharged-texture-hotreload — re-resoudre une texture DEJA residente.
// La fonction fait exactement le meme travail que pour un chargement (mêmes portes, meme
// precedence, memes cartes PBR), puis, au lieu de donner une nouvelle entree au pool, elle
// SUBSTITUE l'objet GL nomme dans l'entree existante (TexturePool::swap_gl_texture) : tous les
// slots VRAM qui liaient l'ancien objet lient le nouveau a la sortie. Rend l'identifiant GL a
// utiliser desormais — `replacing_gl` lui-meme si la substitution n'a pas pu se faire.
u64 add_texture(TexturePool& pool,
                const tfrag3::Texture& tex,
                bool is_common,
                GLuint replacing_gl = 0);

// Grecharged-managed-assets: actual bytes uploaded by the last add_texture()
// call on this thread. Replacements (user PNGs, managed KTX2 packs) can be
// far larger than the baked texture — the per-frame streaming budgets must
// count what was really uploaded, not tex.w*h*4 (the audited hitch source).
extern thread_local u64 g_last_add_texture_bytes;

// Grecharged-texture-hotreload : empreinte du bloc REELLEMENT televerse par le dernier
// add_texture() de ce thread, et resultat de la substitution dans le pool. Le chargeur compare
// l'empreinte d'avant et d'apres une bascule : c'est ce qui distingue « la texture a ete
// re-resolue » de « l'image envoyee au GPU a change ». Une re-resolution qui renvoie les memes
// octets ne prouve rien sur la bascule.
extern thread_local u64 g_last_add_texture_fp;
extern thread_local bool g_last_add_texture_swapped;

class MercLoaderStage : public LoaderStage {
 public:
  MercLoaderStage();
  bool run(Timer& timer, LoaderInput& data) override;
  void reset() override;

 private:
  bool m_done = false;
  bool m_opengl = false;
  bool m_vtx_uploaded = false;
  u32 m_idx = 0;
};