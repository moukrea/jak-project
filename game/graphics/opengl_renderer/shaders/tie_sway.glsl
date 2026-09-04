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
// VERROU (b), independant : le VAO du TFRAG n'active pas l'attribut 7, et `glVertexAttrib4f(7, 0,
// 0, 0, 1)` est pousse explicitement a cote de l'uniforme, donc le poids vaut 0 la ou aucun VBO de
// balancement n'est lie.
//
// ATTRIBUT 7, DEUX OCTETS NORMALISES, derives au chargement (TFrag3Data.cpp, TieTree::unpack et
// ShrubTree::unpack) de l'ancrage et de l'identite de CHAQUE INSTANCE, par la loi partagee de
// common/custom_data/FoliageWindLaw.h :
//   .x = poids  (0 au tiers du bas de la plante et sur tout ce qui n'est pas vegetal ; a la
//                couronne il porte AUSSI le facteur de taille de la plante, donc une seule
//                amplitude sert a toutes les tailles)
//   .y = phase  (constante sur toute la plante, decorrelee d'une plante a l'autre)
// Ni l'un ni l'autre ne se calcule ici : la position varie a l'interieur de la plante (elle la
// dechirerait) et le shader ne sait pas ce qu'est un palmier.
#include "breeze.glsl"

layout (location = 7) in vec2 tie_sway_in;

uniform float u_tie_sway_amp;      // flexion de couronne d'une plante de reference (>= 8 m), unites
                                   // monde (4096 = 1 m) ; 0 = ETEINT, le bloc est saute
uniform float u_tie_sway_time;     // secondes, horloge de brise (figee en pause)
uniform vec2  u_tie_sway_dir;      // cap du vent, normalise (x, z)
uniform float u_tie_sway_flutter;  // part de l'amplitude reservee au fremissement de feuille

vec3 tie_sway_apply(vec3 wpos, vec2 sw) {
  if (u_tie_sway_amp <= 0.0 || sw.x <= 0.0) {
    return wpos;
  }
  vec2 o = breeze_offset(wpos, u_tie_sway_dir, sw.y, u_tie_sway_time, sw.x, u_tie_sway_amp,
                         u_tie_sway_flutter);
  // HORIZONTAL uniquement : pas de composante verticale, une plante ne s'enfonce pas dans le sol.
  wpos.x += o.x;
  wpos.z += o.y;
  return wpos;
}
