#pragma once

// Grecharged-ambient-occlusion: screen-space ambient occlusion for the OpenGOAL
// renderer (desktop GL 4.1 + Android GLES 3.2). Three interchangeable estimators
// (SSAO / HBAO / GTAO) selected by Gfx::settings().recharged_ao_mode, at a
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

#include <cstdint>

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

  // ── LE RECENSEMENT DU MOTIF (refus owner du 2026-09-10 (a)) ──────────────────────────────
  // Sous mesure seulement. La preuve fait tourner DOUZE etats dans UNE course en les alternant
  // d'une image sondee a l'autre, parce que `AO_FORCE_MODE`/`AO_FORCE_QUALITY` sont figes pour
  // toute la course. `request_pattern_census(true)` demande la relecture du tampon d'AO de
  // cette image et l'accumulation des grandeurs de l'etat courant.
  // L'etat complet d'une image sondee : quel ESTIMATEUR (1 = SSAO,
  // 3 = GTAO), quel PALIER (0..2), et quel regime de BRUIT (0 = livre, 1 = le temoin d'avant).
  // L'owner a vu le damier « en qualite faible (SSAO) » ET « en qualite elevee (GTAO) » : une
  // grandeur qui ne couvre qu'un estimateur ne repond pas a son verdict.
  static void set_measure_state(int mode, int quality, int legacy);
  // ── LA PHASE DE LA TRIADE (terme 5, 2026-09-14) ──────────────────────────────────────────
  // Le contrat (k) dit « variation du tampon d'AO entre deux images CONSECUTIVES ». Jusqu'a
  // l'essai 10 le recensement comparait deux images du MEME etat, donc separees d'un tour
  // complet des douze etats — 360 images de jeu, six secondes pendant lesquelles les acteurs
  // du village marchent. La sonde tire desormais TROIS images de suite sur le meme etat :
  // phase 0 = l'image lourde d'avant (elle porte aussi le redimensionnement de la chaine et
  // les relectures de stencil), phase 1 = l'image de REFERENCE, phase 2 = celle qu'on compare.
  // Seule la phase 2 alimente `ao_static_cam_delta_px`, et son ecart a la reference vaut
  // EXACTEMENT une image. -1 = cette image n'est pas sondee.
  static void set_census_pair_phase(int phase);
  static void request_pattern_census(bool on);
  // Publie ao_pattern_* . Appele par le module de prepasse quand il publie le reste.
  static void publish_pattern_census();

  // ── LA SOMME QUE LA PORTE LIT (`ao_owner_defects`) ───────────────────────────────────────
  // Les termes que la prepasse mesure (fuite sur le direct, ecart de prepasse sous vent, alpha
  // sur l'appareil) lui sont remis ici ; les quatre autres viennent de ce module. La somme est
  // publiee par `publish_pattern_census()`, apres que la prepasse a depose les siens.
  static void set_prepass_defect_terms(uint64_t direct_leak_px,
                                       uint64_t sway_gap_px,
                                       uint64_t on_alpha_device_px,
                                       int measured_mask);

  // ── LA CAMPAGNE DE COUT (refus owner (f) du 2026-09-12) ──────────────────────────────────
  // Un debut d'image. Fait avancer la campagne de cout ; sans effet hors mesure. `frame` est le
  // compteur d'images de la prepasse. Elle demarre TARD (image 3000) pour laisser la phase de
  // recensement produire les cles de porte avant de prendre le reste de la course.
  static void measure_frame_begin(uint64_t frame);
  // VRAI pendant la campagne de cout : la prepasse suspend ses images SONDEES, dont les
  // relectures fausseraient le temps par image qu'on est en train de mesurer.
  static bool measure_timing_active();
  // Publie ao_us_* . Appelee avec le reste du recensement.
  static void publish_cost_census();

  // La texture d'AO pleine resolution de la derniere estimation (0 si aucune).
  GLuint texture() const { return m_ao_full_tex; }
  int texture_w() const { return m_ao_full_w; }
  int texture_h() const { return m_ao_full_h; }

 private:
  void ensure_quad();
  void ensure_targets(int ao_w, int ao_h, int full_w, int full_h);
  // Cible de la passe de RAPPORT du recensement, allouee paresseusement (hors mesure : absente).
  void ensure_scratch(int full_w, int full_h);
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

  // lighting-ao-indirect, refus owner du 2026-09-13 (« sur les facades meme en eleve on a un
  // aspect pixelise »). La chaine de flou compte desormais QUATRE passes : H puis V a la
  // resolution du tampon (boite de 4, pas de 1 — elle ANNULE la tuile 4x4 des estimateurs),
  // puis H puis V en PLEINE resolution au pas DOUBLE. La composition des deux boites donne une
  // boite de 8 texels par axe : l'ecart-type du bruit residuel tombe d'un facteur 3 au lieu de
  // 2, ce que `ao_flatstep_*` mesure. Cette cible-ci est l'intermediaire de la passe H pleine
  // resolution ; la passe V finale ecrit toujours dans `m_ao_full_tex`, que shade() lit.
  GLuint m_ao_scratch_fbo = 0;
  GLuint m_ao_scratch_tex = 0;

  // Output-size hint (window-keyed AO chain sizing; 0 == fall back to depth size).
  int m_hint_w = 0, m_hint_h = 0;

  int m_err_logged = 0;
};
