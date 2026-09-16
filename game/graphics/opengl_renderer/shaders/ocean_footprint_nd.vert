#version 410 core

// water-ocean-mesh — L'ORACLE DU RECENSEMENT D'EMPRISE : L'OCEAN DE NAUGHTY DOG, RASTERISE.
//
// POURQUOI CE PROGRAMME N'EST PAS UN MIROIR. La decoupe de la clipmap est RECONSTRUITE depuis les
// masques de l'`ocean-map` ; une porte qui la comparerait a une seconde lecture des memes masques
// serait vraie par construction. Ici l'autre bras vient d'ailleurs : ce sont les sommets que
// l'emulation du microcode VU1 de Naughty Dog produit deja chaque image dans
// `CommonOceanRenderer` (buckets 4 et 63, dont le `glDrawElements` est supprime sous
// `recharged_water` mais dont tout le calcul tourne). Ils portent la hierarchie mid/trans/near,
// les triangles ADC et l'attenuation de houle de ND — rien de tout cela ne vient de notre code.

layout (location = 0) in vec3 position_in;

#include "ocean_common_pos.glsl"

void main() {
  gl_Position = ocean_common_clip(position_in);
}
