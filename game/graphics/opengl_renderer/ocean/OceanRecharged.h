#pragma once

// water-ocean-mesh (SPEC-refonte-eau §5.3, §8) — LA CLIPMAP QUI REMPLACE LE MICROCODE VU1.
//
// CE QUE FAIT CE MODULE. Sous `recharged_water`, les buckets 4 (OCEAN_MID_AND_FAR) et 63
// (OCEAN_NEAR) consomment leur DMA exactement comme avant mais n'emettent plus un seul
// `glDrawElements` : les renderers de Naughty Dog restent VIVANTS, ils avancent le flux, tiennent
// l'ASSERT de fin de bucket et posent le meme etat GL. A leur place, a la position du bucket 63
// (la passe W2a de la SPEC — apres tous les opaques et tous les alphas, la ou la profondeur de
// scene est enfin lisible), ce module dessine une clipmap de trois anneaux deplacee en vertex par
// la houle cuite de Naughty Dog.
//
// CE QU'IL NE FAIT PAS. Aucun modele de lumiere, aucun rivage, aucune ride, aucune physique.
// « Shading provisoire = l'actuel » : le fragment echantillonne la texture d'ocean que ND produit
// deja et la fond vers `far-color`. Les items 2 a 10 de la SPEC prennent la suite.
//
// L'INTERRUPTEUR. Une seule porte, `ocean_recharged_enabled()`, consultee par les trois sites.
// Elle compose `Gfx::water_active()` (master > eau) avec l'armement du harnais : desarme, le
// binaire redevient celui de Naughty Dog dans la MEME scene, ce qui est exactement ce que
// `proof_run.sh --off` doit pouvoir montrer.

#include <array>

#include "common/common_types.h"

#include "game/graphics/opengl_renderer/BucketRenderer.h"

// La porte unique. Vraie quand la clipmap doit remplacer l'ocean d'origine.
bool ocean_recharged_enabled();

class OceanRecharged {
 public:
  static OceanRecharged& get();

  // Appele par OceanNear apres le decodage VIF du bucket 63 : `ocean-near-add-heights` y a pousse
  // les 4096 octets de `*ocean-heights*` (2 x 2048), les 1024 flottants MEMES que
  // `ocean-get-height` lit. C'est la capture de la couche A.
  void note_layer_a(const void* heights_4096_bytes);

  // Appele par OceanTexture quand elle vient de produire la texture d'ocean de cette image.
  void note_ocean_texture(u32 gl_texture);

  // Appele a la fin du bucket 63, apres que le renderer ND a fini de consommer son DMA.
  void draw(SharedRenderState* render_state, ScopedProfilerNode& prof);

 private:
  OceanRecharged() = default;

  struct Ring {
    float step;         // unites GOAL par cellule
    int hole_half;      // demi-trou central, en cellules (0 = pas de trou)
    u32 index_offset;   // en indices, dans l'IBO commun
    u32 index_count;
    float center[2];    // centre monde xz, snappe au pas
  };

  bool ensure_gl();
  bool refresh_ocean_map();
  void rebuild_mask_texture();
  void run_probe(SharedRenderState* render_state);
  void publish();

  // --- geometrie ---------------------------------------------------------------------------
  // 129 x 129 coordonnees de grille entieres partagees par les TROIS anneaux : seuls le pas et le
  // centre changent, par uniforme. Trois plages d'indices decoupent le trou central de chacun.
  static constexpr int kGridCells = 128;
  static constexpr int kGridVerts = kGridCells + 1;
  static constexpr int kNumRings = 3;

  bool m_gl_ready = false;
  bool m_gl_failed = false;
  u32 m_vao = 0;
  u32 m_vbo = 0;
  u32 m_ibo = 0;
  Ring m_rings[kNumRings] = {};

  // --- couche A ----------------------------------------------------------------------------
  std::array<float, 1024> m_layer_a = {};
  bool m_have_layer_a = false;
  bool m_layer_a_fresh = false;
  u32 m_tex_layer_a = 0;

  // --- carte ND ----------------------------------------------------------------------------
  u32 m_map_ptr = 0;           // adresse GOAL de l'`ocean-map` courante
  u32 m_mask_map_ptr = 0;      // celle dont la texture de masque a ete construite
  u32 m_tex_mask = 0;
  float m_start_corner[4] = {0, 0, 0, 0};
  float m_far_color[4] = {0, 0, 0, 0};
  u32 m_ocean_texture = 0;

  // --- sonde de controle -------------------------------------------------------------------
  static constexpr int kProbeSide = 8;
  static constexpr int kProbeCount = kProbeSide * kProbeSide;
  static constexpr int kProbeEveryFrames = 30;
  u32 m_probe_fbo = 0;
  u32 m_probe_tex = 0;
  float m_probe_xz[kProbeCount][4] = {};

  // --- recensement -------------------------------------------------------------------------
  u64 m_frames_drawn = 0;
  u64 m_frames_layer_a_fresh = 0;
  u64 m_frames_layer_a_stale = 0;
  u64 m_verts_moved = 0;
  u64 m_probe_runs = 0;
  u64 m_probe_alpha_missing = 0;
  s64 m_maxdelta_q1024 = -1;
  s64 m_probe_span_q1024 = 0;
  u32 m_mask_skip_cells = 0;
  u32 m_mask_draw_cells = 0;
  u32 m_mask_valid_off0 = 0;
  u32 m_mask_valid_off4 = 0;
  u32 m_mask_index_offset = 0;
  u32 m_mask_fallback = 0;
};
