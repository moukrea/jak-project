#version 410 core

// lighting-ao-indirect (SPEC-refonte-lumiere §4.6) : LA PREPASSE DE PROFONDEUR vue camera.
// Meme entree que pbr_depth.vert (attribut 0 = position MONDE absolue, unites de jeu) et
// EXACTEMENT la projection de tfrag3.vert (pc_camera + cam_trans + SCISSOR_ADJUST * HEIGHT_SCALE,
// tokens substitues a l'execution comme partout) : la profondeur ecrite est celle que la passe
// principale ecrira pour la meme geometrie, a l'arrondi pres. Pas de vent : la prepasse ne dessine
// que l'opaque statique.
//
// REFUS OWNER DU 2026-09-10 (b) : « sur les shrubs, ca ignore la partie transparente et y applique
// quand meme l'occlusion ambiante dessus ». La prepasse portait un fragment shader vide : les texels
// TRANSPARENTS du feuillage a decoupe ecrivaient de la profondeur, l'estimateur les prenait pour des
// occluders pleins, et l'ombre d'AO du quad flottait au-dessus des brins. SPEC §4.6 le disait deja :
// « pas de texture sauf pour l'alpha-test du feuillage (qui doit y participer) ». D'ou la coordonnee
// de texture, sortie ici.
//
// LA LOCATION 1 EST LA MEME POUR LES TROIS FAMILLES : tfrag3.vert:4, shrub.vert:4 et le TIE (qui
// partage tfrag3.vert) declarent tous `layout (location = 1) in vec3 tex_coord_in`. Le VAO du shrub
// n'y pousse que deux flottants (Shrub.cpp:282-288) — shrub.vert le declare deja en vec3 et vit
// avec, la troisieme composante n'est jamais lue.
layout (location = 0) in vec3 position_in;
layout (location = 1) in vec3 tex_coord_in;

uniform vec4 cam_trans;
uniform mat4 pc_camera;

out vec3 tex_coord;

void main() {
  vec3 vert = position_in - cam_trans.xyz;
  vec4 transformed = -pc_camera[3];
  transformed.w = 0.0;
  transformed -= pc_camera[0] * vert.x;
  transformed -= pc_camera[1] * vert.y;
  transformed -= pc_camera[2] * vert.z;
  transformed.y *= SCISSOR_ADJUST * HEIGHT_SCALE;
  gl_Position = transformed;
  tex_coord = tex_coord_in;
}
