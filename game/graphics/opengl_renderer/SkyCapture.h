#pragma once

// lighting-regimes (SPEC-refonte-lumiere §4.10) : LA FORME DE L'AMBIANTE VIENT DU CIEL.
//
// Juste apres le bucket SKY_DRAW, le framebuffer de la scene ne contient QUE le ciel que le jeu
// vient de dessiner (degrade, nuages, astres, couleur d'effacement) : aucun decor n'y est encore
// passe. On en tire une vignette 64x32 (blit + lecture asynchrone par PBO, une image sur quatre),
// puis, quand la camera de CETTE image est connue (`pc_camera`, frame_ubo.cpp), chaque case d'une grille de directions
// (8 elevations x 16 azimuts) qui tombe dans le champ recoit la couleur vue dans cette direction.
// La camera tournant, le dome se remplit ; la projection SH L2 de la grille est la DISTRIBUTION
// mesuree. Le NIVEAU et la TEINTE ne viennent pas d'ici : `background_common.cpp` renormalise sur
// l'amb-color du creneau (§4.10, etape 2).
//
// La projection reproduit celle du decor (tfrag3.vert, `pc_camera`) : clip = -(M0 dx + M1 dy + M2 dz),
// la translation s'annulant pour une direction a l'infini, puis y *= 512/448 (jak1).

#include "game/graphics/opengl_renderer/BucketRenderer.h"

namespace sky_capture {

// Appelee apres CHAQUE bucket par les deux boucles de rendu (bureau et Android).
// `sky_bucket` : vrai pour SKY_DRAW. `enabled` : la capture est voulue cette image (item arme,
// eclairage recharge actif, un ciel existe).
void after_bucket(SharedRenderState* rs, bool sky_bucket, bool enabled);

// La matrice `pc_camera` (colonnes, 16 flottants) de l'image `frame_idx`, telle que le decor la
// consomme (frame_ubo.cpp). La capture en vol de cette image s'en sert pour placer ses directions.
void note_pc_camera(const float m[16], u64 frame_idx);

// SH L2 de l'environnement capture, deja convoluee par le cosinus (A_l/pi : 1, 2/3, 1/4), dans la
// base de `shade.glsl` (Y1 = y, Y2 = z, Y3 = x...). Rend false tant que rien n'a ete vu.
bool sh(float out[9][3]);

// Cases de la grille deja vues au moins une fois (0..128).
int bins_seen();

}  // namespace sky_capture
