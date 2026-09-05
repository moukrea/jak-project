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

// LE POIDS D'UN SOMMET D'ARBRE (TIE statique). `y` hauteur monde du sommet, `ymin, ymax` celles de
// SON instance. Nul sur les 30 % du bas (le tronc), smoothstep^2 au-dessus, facteur de taille
// replie. `smoothstep` a une derivee nulle aux deux bouts : pas de cassure a 30 %.
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
