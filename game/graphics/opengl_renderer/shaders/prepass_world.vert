#version 410 core

// lighting-ao-indirect (SPEC-refonte-lumiere §4.6) : LA PREPASSE DE PROFONDEUR vue camera.
// Meme entree que pbr_depth.vert (attribut 0 = position MONDE absolue, unites de jeu) et
// EXACTEMENT la projection de tfrag3.vert (pc_camera + cam_trans + SCISSOR_ADJUST * HEIGHT_SCALE,
// tokens substitues a l'execution comme partout) : la profondeur ecrite est celle que la passe
// principale ecrira pour la meme geometrie, a l'arrondi pres. Pas de vent, pas d'alpha : la
// prepasse ne dessine que l'opaque statique.
layout (location = 0) in vec3 position_in;

uniform vec4 cam_trans;
uniform mat4 pc_camera;

void main() {
  vec3 vert = position_in - cam_trans.xyz;
  vec4 transformed = -pc_camera[3];
  transformed.w = 0.0;
  transformed -= pc_camera[0] * vert.x;
  transformed -= pc_camera[1] * vert.y;
  transformed -= pc_camera[2] * vert.z;
  transformed.y *= SCISSOR_ADJUST * HEIGHT_SCALE;
  gl_Position = transformed;
}
