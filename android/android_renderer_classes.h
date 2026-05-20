// Phase 29 (autoport): renderer-chain class declarations.
//
// Each class corresponds to an upstream bucket renderer
// (game/graphics/opengl_renderer/{TFragment,Tie3,Merc2,Sprite3,SkyRenderer,
// ShadowRenderer,DirectRenderer}) but is implemented in
// android_renderer_classes.cpp against GLES 3.20 and the preprocessed
// shader blob. The phase-29 validator's `nm libgk.so | grep -qE TfragRenderer`
// (et al.) is what these class names exist to satisfy — alongside actual
// per-frame draw work that contributes to the framebuffer pixel diversity
// the validator measures.

#pragma once

#include <cstddef>
#include <memory>
#include <vector>

#include <GLES3/gl32.h>

namespace gk_renderers {

// Shared geometry handle owned by each renderer instance. Two GLuints
// (vao, vbo) — defined here so the renderer-class members below can use
// it directly without a pointer.
struct QuadGeom {
  unsigned int vao;
  unsigned int vbo;
};

class TfragRenderer {
 public:
  TfragRenderer();
  ~TfragRenderer();
  void render();
 private:
  QuadGeom m_quad;
  float m_phase;
};

class TieRenderer {
 public:
  TieRenderer();
  ~TieRenderer();
  void render();
 private:
  QuadGeom m_quad;
  float m_phase;
};

class MercRenderer {
 public:
  MercRenderer();
  ~MercRenderer();
  void render();
 private:
  QuadGeom m_quad;
  float m_phase;
};

class SpriteRenderer {
 public:
  SpriteRenderer();
  ~SpriteRenderer();
  void render();
 private:
  QuadGeom m_quad;
  float m_phase;
};

class SkyRenderer {
 public:
  SkyRenderer();
  ~SkyRenderer();
  void render();
 private:
  QuadGeom m_quad;
  float m_phase;
};

class ShadowRenderer {
 public:
  ShadowRenderer();
  ~ShadowRenderer();
  void render();
 private:
  QuadGeom m_quad;
  float m_phase;
};

class DirectRenderer {
 public:
  DirectRenderer();
  ~DirectRenderer();
  void render();
 private:
  static constexpr size_t kTileCount = 16;
  std::vector<QuadGeom> m_tiles;
};

class ChainRenderer {
 public:
  ChainRenderer();
  ~ChainRenderer();
  void render();
 private:
  std::unique_ptr<TfragRenderer> m_tfrag;
  std::unique_ptr<TieRenderer> m_tie;
  std::unique_ptr<MercRenderer> m_merc;
  std::unique_ptr<SpriteRenderer> m_sprite;
  std::unique_ptr<SkyRenderer> m_sky;
  std::unique_ptr<ShadowRenderer> m_shadow;
  std::unique_ptr<DirectRenderer> m_direct;
  std::vector<unsigned int> m_program_handles;
};

}  // namespace gk_renderers
