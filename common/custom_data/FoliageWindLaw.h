#pragma once

// =================================================================================================
// foliage-wind — LES FONCTIONS QUE LES DEUX BINAIRES DOIVENT PARTAGER.
//
// Elles vivent ICI, en en-tete inline, parce que leurs DEUX appelants ne sont pas dans la meme
// cible de lien : `common/custom_data/TFrag3Data.cpp` (libcommon, il derive les poids par sommet au
// depaquetage de TIE et de SHRUB) et
// `game/graphics/opengl_renderer/background/foliage_wind.cpp` (la cible `game`, elle recense et
// publie la grandeur de la porte). Une copie dans chacun se serait desynchronisee au premier
// reglage — et le recensement aurait alors publie une reponse qui n'est pas celle que le shader
// consomme, c'est-a-dire un chiffre vert sur un defaut vivant.
//
// Le poids par sommet est aussi ce que `shaders/breeze.glsl` multiplie. La loi TEMPORELLE, elle,
// est dans breeze.glsl et dans `foliage_wind.cpp::breeze_offset` : ces deux-la sont jumelles ligne
// pour ligne et leur en-tete le dit.
//
// ESSAI 11 (owner 2026-09-04 : « ça twitch autant côté feuilles que le tronc », et 2026-09-03 :
// « ils ont l'air de glisser sur le sol ») — DEUX LOIS DE HAUTEUR, UN SEUL ENREGISTREMENT.
//   * ARBRE (TIE statique) : `sway_weight_tie` — les 30 % du bas STRICTEMENT immobiles, puis
//     smoothstep^2 : le tronc ne bouge pas, la couronne oui. Positif ou nul.
//   * BUISSON (SHRUB) : `sway_weight_shrub` — LINEAIRE et SIGNE en (y - pivot), ou le pivot est le
//     SOL trouve sous le buisson (Tfrag3Data.cpp, `foliage_wind_finalize_level`), sinon son pied.
//     Pourquoi lineaire : le GPU interpole LINEAIREMENT le long d'une arete. Entre un sommet
//     enterre et un sommet visible, la ligne de sol recoit une fraction du deplacement du sommet
//     visible, quelle que soit la loi — SAUF si la loi est lineaire en y et NEGATIVE sous le pivot :
//     alors le deplacement interpole au pivot vaut EXACTEMENT 0 pour tout triangle, quelle que
//     soit la tessellation. C'est d'ailleurs la forme du vent natif de ND (un cisaillement de la
//     matrice d'instance), donc les deux termes qu'un buisson recoit sont de la meme famille.
// Le poids est donc SIGNE : GL_SHORT normalise, x kSwayScale dans le shader.
//
// ESSAI 16 (owner 2026-09-06 : « Le feuilles de palmiers meriteraient de bouger plus a leur
// extremites qu'a leur bases, de meme pour l'ensemble des shrubs ») — LA COORDONNEE D'ELEMENT.
// L'essai 14 a ECRIT CE PARAGRAPHE SANS ECRIRE LE CODE (commit 166d7b6c02, session interrompue) :
// `tip_ramp` n'existait nulle part. Il existe maintenant, et le moteur le MESURE.
// La loi de hauteur ci-dessus repond « le tronc ne bouge pas, la cime oui ». Elle ne dit RIEN de
// ce qui se passe LE LONG d'une palme : l'attache d'une frondaison et sa pointe sont a la meme
// hauteur (souvent la pointe est PLUS BASSE, elle retombe), donc elles recevaient exactement le
// meme poids et la palme se deplacait d'un bloc. C'est le defaut cite.
//   * ARBRE (TIE statique ET chemin VENT) : le poids porte un second facteur, `tip_ramp(q)`, ou
//     `q` est la coordonnee normalisee DE L'ELEMENT — la portee du sommet depuis l'axe du tronc,
//     ramenee a l'etendue de portee de la COURONNE de SA plante (0 = l'attache, 1 = la pointe).
//     Le rapport pointe/attache est donc une propriete de la LOI (~10 contre 1 en moyenne de
//     bande, 5,45 au pire), pas de la geometrie d'un prototype. Le poids de hauteur en smoothstep^2
//     a ete REMPLACE par une simple porte de sol : voir `ground_gate`, c'est le produit de deux
//     variables qui rendait 0,003 a la premiere mesure x86.
//   * BUISSON (SHRUB) : la loi reste LINEAIRE ET SIGNEE en (y - pivot), inchangee. Un facteur
//     radial y detruirait la propriete qui rend la ligne de sol EXACTEMENT immobile (le GPU
//     interpole lineairement : voir plus haut). Un buisson a deja sa base au sol a poids nul et sa
//     couronne a poids 1 — « la base au sol immobile, les extremites qui bougent plus » y est
//     porte par la hauteur, et le verdict (2) l'exige au millimetre. Son element est donc VERTICAL
//     et sa coordonnee `q` est la hauteur normalisee au-dessus du pivot.
//   * NORMALISATION PAR INSTANCE : le poids ecrit est divise par le maximum de
//     `hauteur x tip_ramp` de SA plante, de sorte que le poids de couronne reste EXACTEMENT le
//     facteur de taille, comme avant. Sans cela deux prototypes voisins de meme taille mais de
//     forme differente auraient vu leur amplitude s'ecarter d'un facteur 2, et
//     `wind_divergent_pairs` (seuil 2,0) serait passe au rouge sur un changement qui ne concerne
//     que l'INTERIEUR des plantes. Effet de bord VOULU : la pointe recoit desormais la flexion que
//     la couronne recevait, et tout le reste de la plante en recoit MOINS.
//   * LA MESURE (verdict 8, `wind_tip_gradient_min`) : les sommets de chaque instance sont ranges
//     en CINQ bandes de `q` et la moyenne de |poids| RELU APRES QUANTIFICATION est prise dans
//     chaque bande. Le gradient d'une instance est bande[4] / bande[0] — une mesure par SEGMENT le
//     long de l'element, pas deux points, et sur ce que le VBO porte reellement.
//
// ESSAI 16, second defaut (« ça doit varier en amplitude, distorsion, direction ») — LE LACET.
// L'amplitude variait deja (`wind_envelope_cv` = 0,48). La DIRECTION, non : le cap moyen etait
// fige et seul un petit terme lateral rapide s'y ajoutait. `breeze.glsl` fait maintenant tourner
// le cap lui-meme par trois composantes lentes (0,015 / 0,025 / 0,039 Hz, +/- 37 deg au plus).
// La DISTORSION suit sans terme neuf : la phase du fremissement de feuille varie avec le poids, et
// le poids couvre desormais 0,06 -> 1 A L'INTERIEUR d'une couronne au lieu d'y etre presque
// constant — la palme ondule sur SA longueur au lieu de fremir en bloc.
// =================================================================================================

#include <algorithm>
#include <cmath>

#include "common/common_types.h"

namespace foliage_law {

// LE FACTEUR DE TAILLE. Une brise ne deplace pas une pousse de 40 cm autant qu'une couronne de
// palmier : la reponse croit avec la hauteur, puis sature a 8 m. `clamp(h, 0.8, 8) / 8`.
//
// C'EST LUI QUI REND LA PORTE `wind_divergent_pairs` TENABLE. La flexion RELATIVE d'une plante
// (deplacement / hauteur) vaut donc `bend * clamp(h,0.8,8) / (8h)` : CONSTANTE sous 0,8 m et sous
// 8 m elle vaut `bend/8`, decroissante en 1/h au-dela. Deux plantes dont les hauteurs sont dans un
// rapport <= 1,5 ne peuvent donc pas voir leurs flexions relatives s'ecarter de plus de 1,5, contre
// un seuil de divergence a 2. La marge est une propriete de la loi, pas un reglage.
inline float size_factor(float height_m) {
  if (!(height_m > 0.f)) {  // couvre aussi NaN
    return 0.1f;            // clamp(0.8, 0.8, 8) / 8
  }
  return std::min(std::max(height_m, 0.8f), 8.0f) * 0.125f;
}

// LA RAMPE D'EXTREMITE. `q` : coordonnee normalisee le long de l'element souple — 0 a l'attache
// (l'axe du tronc pour une palme, la ligne de sol pour un buisson), 1 a la pointe.
// `kTipFloor` n'est pas 0 : une attache PARFAITEMENT figee casse le raccord avec le tronc a l'oeil,
// et un poids nul rendrait le gradient de l'instance infini, donc INFALSIFIABLE. 0,06 laisse
// 18 mm a l'attache pour 300 mm a la pointe.
// L'exposant 1,6 est celui d'une poutre encastree chargee en bout, arrondi : la pointe emporte
// l'essentiel de la course et le premier tiers ne bouge presque pas.
// Moyennes de bande (sommets uniformes en q) : bande[0] = 0,0875 ; bande[4] = 0,855, soit un
// gradient de LOI de ~9,8 pour une porte a 3,0. Le PIRE cas concevable est atteint quand chaque
// bande est concentree sur son bord interieur : `tip_ramp(0,8) / tip_ramp(0,2)` = 5,45. La porte
// est donc tenue par CONSTRUCTION au-dessus de la porte de sol, sans rien supposer de la geometrie
// d'un prototype.
constexpr float kTipFloor = 0.06f;
constexpr float kTipPow = 1.6f;

inline float tip_ramp(float q) {
  if (!(q > 0.f)) {  // couvre aussi NaN
    return kTipFloor;
  }
  if (q > 1.f) {
    q = 1.f;
  }
  return kTipFloor + (1.f - kTipFloor) * std::pow(q, kTipPow);
}

// Le nombre de bandes de `q` du recensement de gradient, et la bande d'un `q`.
constexpr int kTipBands = 5;
// Une bande sous ce nombre de sommets ne rend pas une moyenne : l'instance est declaree NON
// MESUREE (et comptee comme telle), jamais verte par defaut.
constexpr int kTipBandMinVerts = 4;

inline int tip_band_of(float q) {
  if (!(q > 0.f)) {  // couvre aussi NaN
    return 0;
  }
  if (q >= 1.f) {
    return kTipBands - 1;
  }
  const int b = (int)(q * (float)kTipBands);
  return b < 0 ? 0 : (b >= kTipBands ? kTipBands - 1 : b);
}

// LA PORTE DE SOL. Elle vaut 0 sous 10 % de la hauteur de la plante, monte en smoothstep jusqu'a
// 30 %, et 1 au-dessus. Elle ne fait qu'UNE chose : garantir que les 10 % du bas d'un arbre sont
// EXACTEMENT immobiles (`wind_base_to_crown_ratio`, verdict 6, et le pied qui ne glisse pas).
// Ce n'est plus une rampe de reponse : au-dessus de 30 % la reponse est celle de la RAMPE
// D'EXTREMITE seule.
//
// POURQUOI ELLE A REMPLACE LE smoothstep^2 SUR [0,30 %, 100 %] (essai 16, mesure x86) :
// la reponse valait `hauteur x extremite`, un PRODUIT DE DEUX VARIABLES. Sur un prototype large et
// bas — la pointe d'une branche etalee se trouve juste au-dessus des 30 %, l'axe du tronc monte
// jusqu'a 100 % — le facteur de hauteur ecrasait la rampe d'extremite et INVERSAIT le gradient :
// `wind_tip_gradient_min` a rendu 0,003 sur 1873 instances (porte : >= 3,0). Le rapport
// pointe/attache doit etre une propriete de la LOI, ce que le produit ne permettait pas.
// Avec la porte de sol, au-dessus de 30 % la reponse est `tip_ramp(q)` SEULE, donc le rapport des
// moyennes de bande vaut au pire `tip_ramp(0,8) / tip_ramp(0,2)` = 5,45 : la porte a 3,0 est tenue
// par construction, quelle que soit la geometrie du prototype.
// Le tronc reste immobile parce qu'il est sur l'AXE (q ~ 0 -> 6 %), plus parce qu'il est en bas.
// C'est aussi plus juste : une longue branche basse est souple, une branche courte en haut ne
// l'est pas.
inline float ground_gate(float h) {
  if (!(h > 0.10f)) {  // couvre aussi NaN
    return 0.f;
  }
  if (h >= 0.30f) {
    return 1.f;
  }
  const float u = (h - 0.10f) / 0.20f;
  return u * u * (3.f - 2.f * u);
}

// Au-dessus de cette hauteur relative la plante est LIBRE : la porte de sol vaut 1 et la reponse
// est la rampe d'extremite seule. C'est la region ou le gradient (verdict 8) se recense — en
// dessous, la reponse porte la porte de sol et ne dit rien de la forme de l'element.
constexpr float kFreeHeight = 0.30f;

// LA FORME D'UN SOMMET D'ARBRE, SANS le facteur de taille et SANS la normalisation d'instance :
// porte de sol x rampe d'extremite. C'est exactement ce que `tie_wind.vert` calcule pour le
// chemin VENT, et ce que le depaqueteur normalise pour le chemin STATIQUE.
inline float tie_shape(float y, float ymin, float ymax, float q) {
  const float span = ymax - ymin;
  if (!(span > 0.f)) {  // couvre aussi NaN
    return 0.f;
  }
  return ground_gate((y - ymin) / span) * tip_ramp(q);
}

// L'ENREGISTREMENT DE BALANCEMENT PAR SOMMET, 8 octets, parallele au VBO de sommets (TIE statique
// ET shrub), televerse tel quel. Trois attributs pointent dedans :
//   w      attribut 7, GL_SHORT normalise -> [-1, 1], x kSwayScale dans le shader. 0 = fige.
//   inst   attribut 9 (shrub seulement), GL_UNSIGNED_SHORT entier : matrix_idx de l'instance,
//          index du texel de vent NATIF (Shrub.cpp).
//   ph     attribut 8, GL_UNSIGNED_BYTE normalise -> [0, 1) : phase propre de l'instance.
//   flags  bit 0 = le sommet appartient a une instance posee.
struct SwayRecord {
  s16 w = 0;
  u16 inst = 0;
  u8 ph = 0;
  u8 flags = 0;
  u16 pad = 0;
};
static_assert(sizeof(SwayRecord) == 8, "SwayRecord doit faire 8 octets : les VAO le supposent");
constexpr size_t kSwayRecordBytes = sizeof(SwayRecord);
constexpr u8 kSwayFlagInstance = 1;

// Echelle du poids quantifie : le shader lit `short / 32767 * kSwayScale`. 4 laisse de la marge a
// la partie ENFONCEE d'un buisson (poids negatif jusqu'a -3 x facteur de taille) sans jamais
// saturer la partie visible (poids <= 1).
constexpr float kSwayScale = 4.0f;

inline s16 quantize_weight(float w) {
  if (!(w == w)) {  // NaN
    return 0;
  }
  long q = std::lround(w / kSwayScale * 32767.f);
  if (q < -32767) {
    q = -32767;
  }
  if (q > 32767) {
    q = 32767;
  }
  return (s16)q;
}

inline float dequantize_weight(s16 q) {
  return (float)q / 32767.f * kSwayScale;
}

// LE POIDS DE HAUTEUR SEUL (sans rampe d'extremite), garde parce que le chemin VENT et le
// recensement s'en servent comme reference de taille. `y` hauteur monde du sommet, `ymin, ymax`
// celles de SON instance. Nul sur les 30 % du bas (le tronc), smoothstep^2 au-dessus, facteur de
// taille replie. `smoothstep` a une derivee nulle aux deux bouts : pas de cassure a 30 %.
// LE DEPAQUETEUR N'ECRIT PLUS CECI : il ecrit `tie_shape` normalise par instance (essai 16).
inline float sway_weight_tie(float y, float ymin, float ymax) {
  const float span = ymax - ymin;
  if (!(span > 0.f)) {  // couvre aussi NaN
    return 0.f;
  }
  float h = (y - ymin) / span;
  if (!(h > 0.30f)) {  // couvre aussi NaN
    return 0.f;
  }
  if (h > 1.f) {
    h = 1.f;
  }
  const float u = (h - 0.30f) / 0.70f;
  const float s = u * u * (3.f - 2.f * u);
  return s * s * size_factor(span / 4096.f);
}

// LE POIDS D'UN SOMMET DE BUISSON (SHRUB). `base_y` = le PIVOT (sol trouve sous le buisson, sinon
// son pied), `ymax` sa couronne. Lineaire, signe, borne a [-3, 1] avant le facteur de taille : un
// buisson enfonce de plus de trois fois sa hauteur visible sature sous le sol, ou personne ne le
// voit. La hauteur qui porte le facteur de taille est la hauteur VISIBLE (ymax - base_y).
inline float sway_weight_shrub(float y, float base_y, float ymax) {
  const float span = ymax - base_y;
  if (!(span > 0.f)) {  // couvre aussi NaN
    return 0.f;
  }
  float u = (y - base_y) / span;
  if (!(u > -3.f)) {  // couvre aussi NaN
    u = -3.f;
  }
  if (u > 1.f) {
    u = 1.f;
  }
  return u * size_factor(span / 4096.f);
}

// LA PHASE PROPRE D'UNE PLANTE, dans [0, 1), sur 8 bits. Angle d'or sur l'identifiant d'instance :
// constante sur toute la plante (sinon elle se dechire), decorrelee d'une plante a l'autre (sinon
// le decor glisse en bloc).
inline u8 phase_u8(u64 instance_id) {
  const double ph01 = std::fmod((double)instance_id * 0.6180339887498949, 1.0);
  int q = (int)(ph01 * 256.0);
  if (q < 0) {
    q = 0;
  }
  if (q > 255) {
    q = 255;
  }
  return (u8)q;
}

}  // namespace foliage_law
