// =================================================================================================
// foliage-wind (owner 2026-09-03) — LE BALANCEMENT DE LA VEGETATION STATIQUE : TIE **ET** SHRUB.
//
// QUATRE programmes dessinent de la vegetation statique et doivent bouger sous la MEME loi, sinon
// deux plantes voisines que l'oeil lit comme identiques divergent (« deux identiques côté à côte...
// un est pris l'autre non ») :
//   * tfrag3.vert    (TIE non-envmappe, Tie3.cpp)
//   * etie_base.vert (passe de base envmappee, Tie3.cpp)
//   * etie.vert      (passe additive de reflet, Tie3.cpp)
//   * shrub.vert     (buissons, Shrub.cpp)
// Le code vit ICI et une seule fois ; Shader.cpp le recopie verbatim chez les quatre. La loi
// TEMPORELLE elle-meme est dans breeze.glsl, jumelle ligne pour ligne de
// foliage_wind.cpp::breeze_offset (le chemin VENT du TIE, calcule sur CPU, l'emprunte aussi).
//
// LE PIEGE, ET C'EST LE VERROU (a) : `tfrag3.vert` est AUSSI le shader du terrain TFRAG. Un uniforme
// laisse a sa derniere valeur ferait ONDULER LE SOL. `first_tfrag_draw_setup` (background_common.cpp)
// ecrit donc `u_tie_sway_amp = 0` a CHAQUE activation de programme, pour TOUS les appelants, et seuls
// Tie3 et Shrub le relevent juste apres, sur leurs propres passes, via foliage_wind::push_uniforms.
// VERROU (b), independant : le VAO du TFRAG n'active pas les attributs 7/8/9, et
// `glVertexAttrib4f(7, 0, 0, 0, 1)` (et 8, 9) est pousse explicitement a cote de l'uniforme, donc le
// poids vaut 0 la ou aucun VBO de balancement n'est lie.
//
// L'ENREGISTREMENT DE BALANCEMENT (FoliageWindLaw.h : SwayRecord, 8 octets par sommet, derive au
// chargement par TFrag3Data.cpp de l'ancrage et de l'identite de CHAQUE INSTANCE) :
//   attribut 7  poids, GL_SHORT normalise -> [-1, 1], x TIE_SWAY_SCALE. 0 au tronc d'un arbre (30 %
//               du bas) et sur tout ce qui n'est pas vegetal ; LINEAIRE et SIGNE pour un buisson
//               (negatif sous le sol : le GPU interpole lineairement, donc la ligne de sol est
//               EXACTEMENT immobile). A la couronne il porte AUSSI le facteur de taille de la plante,
//               donc une seule amplitude sert a toutes les tailles.
//   attribut 8  phase, GL_UNSIGNED_BYTE normalise -> [0, 1) : constante sur toute la plante,
//               decorrelee d'une plante a l'autre.
//   attribut 9  (shrub seulement, lu par shrub.vert) index d'instance, entier.
// Ni l'un ni l'autre ne se calcule ici : la position varie a l'interieur de la plante (elle la
// dechirerait) et le shader ne sait pas ce qu'est un palmier.
#include "breeze.glsl"

layout (location = 7) in float tie_sway_w_in;
layout (location = 8) in float tie_sway_ph_in;

// = foliage_law::kSwayScale
#define TIE_SWAY_SCALE 4.0
// (poids, phase) tels que les quatre programmes les consomment
#define tie_sway_in vec2(tie_sway_w_in * TIE_SWAY_SCALE, tie_sway_ph_in)

uniform float u_tie_sway_amp;      // flexion de couronne d'une plante de reference (>= 8 m), unites
                                   // monde (4096 = 1 m) ; 0 = ETEINT, le bloc est saute
uniform float u_tie_sway_time;     // secondes, horloge de brise (figee en pause)
uniform vec2  u_tie_sway_dir;      // cap du vent, normalise (x, z)
uniform float u_tie_sway_flutter;  // part de l'amplitude reservee au fremissement de feuille

vec3 tie_sway_apply(vec3 wpos, vec2 sw) {
  if (u_tie_sway_amp <= 0.0 || sw.x == 0.0) {
    return wpos;
  }
  vec2 o = breeze_offset(wpos, u_tie_sway_dir, sw.y, u_tie_sway_time, sw.x, u_tie_sway_amp,
                         u_tie_sway_flutter);
  // HORIZONTAL uniquement : pas de composante verticale, une plante ne s'enfonce pas dans le sol.
  wpos.x += o.x;
  wpos.z += o.y;
  return wpos;
}
