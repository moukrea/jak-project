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

// LE POIDS DE BALANCEMENT D'UN SOMMET, SIGNE, sur 16 bits, POUR LES TROIS CHEMINS (essai 7).
//   `y`       hauteur monde du sommet
//   `base_y`  hauteur monde du PIVOT de son instance : `ymin` pour le TIE ; pour un buisson le SOL
//             trouve sous lui (Tfrag3Data.h, `foliage_wind_finalize_level`), sinon `ymin`
//   `ymax`    plus haut sommet de son instance
//
// UN CISAILLEMENT PUR, ET C'EST LE CORRECTIF DU « GLISSE SUR LE SOL ». Owner 2026-09-03 : « certains
// sont placés plus bas que le sol pour le style volontairement... mais avec l'animation, bah du coup
// ils ont l'air de glisser sur le sol ». L'essai 6 rendait rigides les 30 % du bas (smoothstep^2)
// depuis `ymin` — mais (a) `ymin` est SOUS le terrain pour une plante enfoncee, donc la ligne de sol
// pouvait etre au-dessus des 30 % ; et surtout (b) le GPU interpole LINEAIREMENT entre deux sommets :
// entre un sommet enterre (poids 0) et un sommet visible (poids > 0), la ligne de sol recoit une
// fraction du deplacement du sommet visible, quelle que soit la loi. La seule loi que l'interpolation
// lineaire respecte EXACTEMENT est une loi LINEAIRE en y : le deplacement vaut `s * (y - base_y)`, il
// est NEGATIF sous le pivot (partie invisible, enfoncee), NUL au pivot pour TOUT triangle, quelle que
// soit la tessellation. C'est d'ailleurs exactement la forme du vent NATIF de ND (do_wind_math :
// `mat[r].x += s.x * mat[r].y`, un cisaillement de la matrice d'instance), donc une plante qui recoit
// les deux termes se deforme de la meme famille de mouvement.
//
// Le facteur de taille est REPLIE dedans, de sorte que le shader n'ait qu'une seule amplitude a
// connaitre, quelle que soit la plante. Borne a [-1, 1] : une plante enfoncee de plus que sa hauteur
// visible sature sous le sol, ou personne ne la voit.
inline s16 sway_weight_s16(float y, float base_y, float ymax) {
  const float span = ymax - base_y;
  if (!(span > 0.f)) {  // couvre aussi NaN
    return 0;
  }
  float u = (y - base_y) / span;
  if (!(u > -1.f)) {  // couvre aussi NaN
    u = -1.f;
  }
  if (u > 1.f) {
    u = 1.f;
  }
  const float w = u * size_factor(span / 4096.f);
  int q = (int)std::lround(w * 32767.f);
  if (q < -32767) {
    q = -32767;
  }
  if (q > 32767) {
    q = 32767;
  }
  return (s16)q;
}

// La meme loi, NON quantifiee, pour le recensement : la flexion relative attendue d'un sommet.
inline float sway_weight_f(float y, float base_y, float ymax) {
  return (float)sway_weight_s16(y, base_y, ymax) / 32767.f;
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
