#pragma once

// =================================================================================================
// foliage-wind — LES TROIS FONCTIONS QUE LES DEUX BINAIRES DOIVENT PARTAGER.
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

// LE POIDS DE BALANCEMENT D'UN SOMMET, sur 8 bits, POUR LES TROIS CHEMINS.
//   `y`           hauteur monde du sommet
//   `ymin, ymax`  hauteurs monde de SON instance
//
// LE TIERS DU BAS EST RIGIDE, ET C'EST LE CORRECTIF DU « GLISSE SUR LE SOL ». Owner 2026-09-03 :
// « certains sont placés plus bas que le sol pour le style volontairement... mais avec l'animation,
// bah du coup ils ont l'air de glisser sur le sol ». L'ancienne loi (`h*h` mesure depuis `ymin`)
// donnait un poids NON NUL des le premier centimetre au-dessus du sommet le plus bas de la plante.
// Or pour une plante volontairement enfoncee, ce sommet est SOUS le terrain : la ligne ou la plante
// croise le sol portait donc deja du deplacement horizontal, et c'est exactement ce que l'oeil lit
// comme un glissement.
// `smoothstep(0.30, 1.0, h)^2` rend les 30 % du bas STRICTEMENT immobiles. Une plante enfoncee
// jusqu'a 30 % de sa hauteur ne glisse plus ; une plante posee normalement garde un pied rigide, ce
// qui est de toute facon son comportement physique.
//
// Le facteur de taille est REPLIE dedans, de sorte que le shader n'ait qu'une seule amplitude a
// connaitre, quelle que soit la plante.
inline u8 sway_weight_u8(float y, float ymin, float ymax) {
  const float span = ymax - ymin;
  if (!(span > 0.f)) {  // couvre aussi NaN
    return 0;
  }
  float h = (y - ymin) / span;
  if (!(h > 0.30f)) {  // couvre aussi NaN
    return 0;
  }
  if (h > 1.f) {
    h = 1.f;
  }
  const float u = (h - 0.30f) / 0.70f;
  const float s = u * u * (3.f - 2.f * u);  // smoothstep, derivee nulle aux deux bouts
  const float w = s * s * size_factor(span / 4096.f);
  int q = (int)(w * 255.f + 0.5f);
  if (q < 0) {
    q = 0;
  }
  if (q > 255) {
    q = 255;
  }
  return (u8)q;
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
