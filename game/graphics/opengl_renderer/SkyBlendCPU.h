#pragma once

#include "common/dma/dma_chain_read.h"

#include "game/graphics/opengl_renderer/BucketRenderer.h"
#include "game/graphics/opengl_renderer/SkyBlendCommon.h"
#include "game/graphics/pipelines/opengl.h"

class SkyBlendCPU {
 public:
  SkyBlendCPU();
  ~SkyBlendCPU();

  SkyBlendStats do_sky_blends(DmaFollower& dma,
                              SharedRenderState* render_state,
                              ScopedProfilerNode& prof);
  void init_textures(TexturePool& tex_pool, GameVersion version);

 private:
  static constexpr int m_sizes[2] = {32, 64};
  std::vector<u8> m_texture_data[2];
  // hdr-source-range (chantier A) : l'accumulateur FLOTTANT du ciel, en unites de blanc (1,0 =
  // l'ancien 255). Le chemin u8 ci-dessus saturait la somme de ses couches avec
  // `_mm_adds_epu8` : c'etait la, et nulle part ailleurs, que la plage du ciel etait detruite
  // sur l'appareil (`use_sky_cpu` vaut vrai par defaut). Le tableau u8 reste alloue et reste
  // LE chemin livre quand le chantier est desarme ou le maitre Recharged eteint.
  std::vector<float> m_float_data[2];
  bool m_float_target[2] = {false, false};

  struct TexInfo {
    GLuint gl;
    u32 tbp;
    GpuTexture* tex;
  } m_textures[2];
};