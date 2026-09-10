#version 410 core

// water-ocean-mesh (SPEC-refonte-eau §8, controle causal 1) — LA SONDE DE CONTROLE.
// Un triangle plein cadre, sans attribut : la cible fait 8 x 8 texels, donc 64 fragments, donc
// exactement les 64 sommets de clipmap que la porte compare a la hauteur de jeu.

void main() {
  vec2 p = vec2((gl_VertexID << 1) & 2, gl_VertexID & 2);
  gl_Position = vec4(p * 2.0 - 1.0, 0.0, 1.0);
}
