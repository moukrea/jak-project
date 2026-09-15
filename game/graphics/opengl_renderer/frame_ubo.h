#pragma once
// frame_ubo — LE BLOC D'UNIFORMES D'IMAGE `ub_frame` (item `lighting-ao-indirect`, amendement
// perf du 2026-09-09, SPEC-refonte-lumiere §4.3).
//
// LE DEFAUT. `first_tfrag_draw_setup` poussait huit uniformes de camera et de brouillard
// (camera, pc_camera, hvdf_offset, cam_trans, fog_constant, fog_min, fog_max, fog_color) par
// appel, donc par arbre et par categorie, sur chacun des cinq hotes du decor : ~200 glUniform
// par image pour des valeurs qui ne changent qu'une fois par image (la camera) ou par bloc de
// visibilite (le brouillard, VisDataHandler). Un bloc std140 de 224 octets, mis a jour a la
// premiere lecture de la camera de l'image et a chaque CHANGEMENT (comparaison a l'octet),
// est lu par les vertex ET fragment shaders des hotes via `#include "frame_ubo.glsl"`, sous
// les MEMES noms qu'avant : le corps des shaders ne bouge pas.
//
// POINT DE LIAISON 2 (ub_bones = 1, PatColors = 0). Shader.cpp lie le bloc de chaque programme
// qui le declare a l'edition de liens.
#include <cstdint>

#include "third-party/glad/include/glad/glad.h"

struct GoalBackgroundCameraData;
struct SharedRenderState;

namespace frame_ubo {

constexpr GLuint kBindingPoint = 2;

// Met le bloc a jour si son contenu a change (camera de `cam`, brouillard de `rs`) et le lie au
// point 2. Appelable a chaque draw : ne televerse qu'au changement.
void update_and_bind(const GoalBackgroundCameraData& cam, const SharedRenderState* rs);

// Shader.cpp, a l'edition de liens : lie `ub_frame` du programme au point 2 s'il le declare.
void bind_program(GLuint program);

// Une fois par image (tete de dispatch) : publie `frame_ubo_uploads_per_frame`.
void frame_begin();

// Proof archive identity; zero if the effective binding is not our cached 224-byte block.
uint64_t contact_bound_hash();

}  // namespace frame_ubo
