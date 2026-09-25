#pragma once

// lighting-local-lights (SPEC-refonte-lumiere §4.9) : la grille de clusters des lumieres locales.
//
// Remplie sur le FIL DE RENDU, une fois par image (jamais le fil GOAL, SPEC §1.3) : c'est le
// C++ qui range les lumieres du niveau courant dans une grille alignee monde, centree camera,
// et pousse trois textures que shade.glsl echantillonne (u_ll_lights/u_ll_cells/u_ll_index).
//
// Mode ORIGINE bit-identique : tout ce module est un no-op quand `Gfx::recharged_lighting_active()`
// est faux, quand la feature n'est pas armee, ou quand aucune lumiere n'est chargee — les
// uniformes pousses restent a u_ll_on=0, shade.glsl n'y touche pas.

#include <cstdint>

#include "common/custom_data/LocalLights.h"

#include "third-party/glad/include/glad/glad.h"

struct SharedRenderState;
struct GoalBackgroundCameraData;

namespace cluster_grid {

// Une fois par image (background_common.cpp, update_render_state_from_pc_settings, le meme point
// que la camera est lue — une fois par image, PAS first_tfrag_draw_setup qui tourne ~5x/image).
// Construit la grille a partir des lumieres du niveau courant et televerse les trois textures.
void update(SharedRenderState* rs, const GoalBackgroundCameraData& cam);

// A poser dans first_tfrag_draw_setup, une fois par activation de programme (tfrag/tie/etie/
// shrub/hfrag) : uniformes u_ll_* et liaison des trois textures a leurs unites.
void bind_program_uniforms(GLuint program);

// Sonde de preuve (une image sur 60, seulement sous armed_for) : a appeler APRES l'opaque,
// comme pbr_shadow_proof_post_opaque. Lit le framebuffer et compte vert/bleu.
void proof_post_opaque(SharedRenderState* rs);

}  // namespace cluster_grid
