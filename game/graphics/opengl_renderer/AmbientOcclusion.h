#pragma once

// Grecharged-ambient-occlusion: screen-space ambient occlusion for the OpenGOAL
// renderer (desktop GL 4.1 + Android GLES 3.2). Three interchangeable estimators
// (SSAO / HBAO / GTAO) selected by Gfx::g_global_settings.recharged_ao_mode, at a
// per-quality resolution scale from recharged_ao_quality.
//
// lighting-ao-indirect (SPEC-refonte-lumiere §4.7) : cette classe n'est plus qu'un ESTIMATEUR.
// Elle lit une texture de profondeur (celle de la prepasse, PrePass.cpp), estime et floute, et
// ecrit une texture R8 pleine resolution que `shade.glsl` echantillonne pour multiplier le SEUL
// terme indirect. Le composite sur l'image (`ao_composite.frag`, blend GL_ZERO /
// GL_ONE_MINUS_SRC_COLOR), la copie de scene et le masque de luminance ont disparu : ils
// assombrissaient aussi la lumiere directe, et le masque n'etait que le symptome du mauvais
// emplacement. Les trois estimateurs et le flou sont INCHANGES.

#include "game/graphics/opengl_renderer/BucketRenderer.h"
#include "game/graphics/opengl_renderer/Fbo.h"
#include "game/graphics/opengl_renderer/Shader.h"

#include "third-party/glad/include/glad/glad.h"

class AmbientOcclusionPass {
 public:
  AmbientOcclusionPass() = default;
  ~AmbientOcclusionPass();

  // Live-tunable, debug-overridable resolved mode/quality. Reads the game settings
  // globals unless a debug override (Android system-prop / desktop env) is present.
  // 0=off/1=SSAO/2=HBAO/3=GTAO ; quality 0=low/1=med/2=high.
  static int effective_mode();
  static int effective_quality();
  static int effective_strength();
  static int effective_debug();

  // Store the shader library for render-time use (mirrors the bucket-renderer flow).
  void init_shaders(ShaderLibrary& shaders);

  // Size the AO/blur chain by the WINDOW (not the render-scale-sized FBO) so a dynamic
  // render-scale change never recreates the chain (no churn / no blink). 0 == "no hint,
  // fall back to the depth texture size" (the desktop path leaves it unset).
  void set_output_hint(int w, int h) {
    m_hint_w = w;
    m_hint_h = h;
  }

  // Estime + floute l'AO depuis `depth_tex` (taille depth_w x depth_h, convention PS2 :
  // 0 = le plus loin) et l'ecrit dans `texture()`. Ne compose RIEN sur la scene. Rend faux
  // si rien n'a ete produit (mode 0, camera singuliere, pas de shaders). Sauvegarde et
  // restaure tout l'etat GL qu'elle touche.
  bool estimate(SharedRenderState* rs, GLuint depth_tex, int depth_w, int depth_h);

  // La texture d'AO pleine resolution de la derniere estimation (0 si aucune).
  GLuint texture() const { return m_ao_full_tex; }
  int texture_w() const { return m_ao_full_w; }
  int texture_h() const { return m_ao_full_h; }

 private:
  void ensure_quad();
  void ensure_targets(int ao_w, int ao_h, int full_w, int full_h);
  void free_targets();

  ShaderLibrary* m_shaders = nullptr;

  // fullscreen-quad geometry (matches OpenGLRenderer's screen_vao/vbo layout).
  GLuint m_quad_vao = 0;
  GLuint m_quad_vbo = 0;
  bool m_quad_ready = false;

  // small AO ping-pong targets (R8): raw estimate <-> blur scratch.
  GLuint m_ao_fbo[2] = {0, 0};
  GLuint m_ao_tex[2] = {0, 0};
  int m_ao_w = 0;
  int m_ao_h = 0;

  // full-res AO target (R8): the V blur pass writes here at FULL resolution, doubling as
  // a depth-aware upsample so a sub-full-res AO term never reads blocky (owner tuning #2:
  // GTAO-low pixelation at full render res). C'est la texture que shade() echantillonne.
  GLuint m_ao_full_fbo = 0;
  GLuint m_ao_full_tex = 0;
  int m_ao_full_w = 0;
  int m_ao_full_h = 0;

  // Output-size hint (window-keyed AO chain sizing; 0 == fall back to depth size).
  int m_hint_w = 0, m_hint_h = 0;

  int m_err_logged = 0;
};
