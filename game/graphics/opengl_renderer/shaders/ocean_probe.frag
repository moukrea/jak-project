#version 410 core

// water-ocean-mesh (SPEC-refonte-eau §8, controle causal 1) — CE QUE LE GPU A VRAIMENT LU.
//
// POURQUOI UNE PASSE, ET PAS UN CALCUL CPU. Comparer deux transcriptions CPU de la meme formule
// serait un miroir : vrai par construction, infalsifiable. Ici le chiffre sort du GPU, apres le
// vrai aller-retour — capture au DMA, empaquetage, upload de texture, echantillonnage par le
// MEME `ocean_layer_a()` que la clipmap utilise pour deplacer ses sommets. Un modulo faux, une
// echelle fausse, une frame de retard, un format de texture qui arrondit : tout cela se voit ici
// et nulle part ailleurs.
//
// L'ENCODAGE. On rend la couche A en 1/256 d'unite GOAL, biaisee de 2^23, sur trois octets d'une
// cible RGBA8 — le SEUL format dont `glReadPixels` est garanti sur GLES 3.2. Un R32F relu
// directement ne l'est pas. Le facteur etait 1024 au premier essai : la course du 2026-09-10 a
// rendu `maxdelta_q1024 = 16777216` PILE, c'est-a-dire 2^24 — la signature d'un champ de 24 bits
// qui deborde, pas d'un ecart de hauteur. Mesuree, la houle depasse les +-5456 unites deduites de
// la table cuite. A 1/256, le champ tient +-32768 unites (+-8 m) et l'entier reste sous 2^24, donc
// EXACT dans la mantisse d'un flottant 32 bits. 1/256 d'unite GOAL vaut 0,95 micrometre : trois
// ordres de grandeur sous le millimetre de la porte. L'alpha vaut 1 :
// c'est le temoin qu'un fragment a bien tourne, sans quoi une cible restee noire se lirait comme
// « hauteur zero » au lieu de « rien n'a ete mesure ».

#include "ocean_layer_a.glsl"

uniform vec4 u_probe_xz[64];  // xy = position monde du sommet de clipmap n

out vec4 color;

void main() {
  int k = int(gl_FragCoord.y) * 8 + int(gl_FragCoord.x);
  float a = ocean_layer_a(u_probe_xz[k].xy);
  int q = int(round(a * 256.0)) + 8388608;
  color = vec4(float(q & 255) / 255.0, float((q >> 8) & 255) / 255.0,
               float((q >> 16) & 255) / 255.0, 1.0);
}
