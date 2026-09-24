#version 410 core

// lighting-shadows (SPEC §4.8) : caster ACTEUR (merc) dans une tuile de l'atlas d'ombre.
// Meme squelette / meme UBO `ub_bones` que merc2.vert, copies mot pour mot pour que la matrice
// de peau soit LA MEME que la passe couleur. Seule la projection change : `u_merc_smvp`,
// fournie par l'implementeur B, mappe l'espace vue (unites GOAL) direct vers le clip de la
// tuile visee.
layout (location = 0) in vec3 position_in;
layout (location = 2) in vec3 weights_in;
layout (location = 5) in uvec3 mats;

struct MercMatrixData {
  mat4 X;
  mat3 R;
  vec4 pad;
};

layout (std140) uniform ub_bones {
  MercMatrixData bones[128];
};

uniform mat4 u_merc_smvp;

void main() {
  vec4 p = vec4(position_in, 1.0);
  // NOTE : merc2.vert utilise `-X*p` (sa propre convention de signe) ; ici c'est du POSITIF —
  // l'espace vue direct que `pbr_shadow_merc_mvp` attend en entree (voir background_common.cpp,
  // Mc = S * T * inverse(Rgl)).
  vec4 v = bones[mats[0]].X * p * weights_in[0];
  if (weights_in[1] > 0.0) {
    v += bones[mats[1]].X * p * weights_in[1];
  }
  if (weights_in[2] > 0.0) {
    v += bones[mats[2]].X * p * weights_in[2];
  }
  gl_Position = u_merc_smvp * vec4(v.xyz, 1.0);
}
