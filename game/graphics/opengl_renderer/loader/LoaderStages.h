#pragma once

#include "game/graphics/opengl_renderer/loader/common.h"

std::vector<std::unique_ptr<LoaderStage>> make_loader_stages();
u64 add_texture(TexturePool& pool, const tfrag3::Texture& tex, bool is_common);

// Grecharged-managed-assets: actual bytes uploaded by the last add_texture()
// call on this thread. Replacements (user PNGs, managed KTX2 packs) can be
// far larger than the baked texture — the per-frame streaming budgets must
// count what was really uploaded, not tex.w*h*4 (the audited hitch source).
extern thread_local u64 g_last_add_texture_bytes;

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