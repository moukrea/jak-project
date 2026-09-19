#pragma once

// grass-blade-variants (SPEC-refonte-herbe.md, section 6) — SIX SILHOUETTES DE BRIN, ZERO ASSET.
//
// « quatre a six variantes simples, toutes generees depuis `gl_VertexID` comme aujourd'hui, aucun
// asset de maillage. Elles different par le nombre de segments, le profil de largeur et la courbure
// de base. Le palier le plus bas n'en utilise qu'une, le plus haut les six. »
//
// CE FICHIER NE PORTE PAS LA GEOMETRIE. Les parametres de forme (hauteur, largeur, fuite, courbure)
// vivent dans `shaders/grass.vert`, tables `VAR_A`/`VAR_B`, parce que c'est le seul endroit qui les
// consomme. Ici vivent les SEULES grandeurs dont le C++ a besoin : le nombre de segments de chaque
// variante (donc son budget de sommets), les proportions declarees par le profil, la regle de repli
// par palier, et la tolerance. Le recensement `lib/census/grass-blade-variants.sh` VERIFIE que les
// segments declares ici sont ceux de la table GLSL : la duplication est mesuree, pas supposee.
//
// AUCUNE INCLUSION. Ce fichier est lu par le moteur, par `tools/grass_bake` (outil de bureau, sans
// GL) et par l'empaqueteur, comme `grass_density_presets.h` a cote.

#include <cstdint>

namespace grass_bake {

// LES SIX SILHOUETTES. `segments` est le nombre de RANGEES du ruban effectivement distinctes : le
// ruban soumet toujours 2*(kBladeStripSegments+1) sommets, et une variante a moins de segments
// replie ses rangees excedentaires sur la rangee voisine (triangles degeneres, zero fragment). La
// diversite ne coute donc AUCUN sommet de plus — c'est le point 2 du livrable.
struct BladeVariant {
  const char* name;  // nom publie dans la preuve
  int segments;      // rangees distinctes (1..kBladeStripSegments)
};

inline constexpr int kBladeVariantCount = 6;

// v0 est, AU BIT PRES, le brin livre jusqu'ici : la table GLSL lui donne les constantes historiques
// (0.092 de demi-largeur, fuite 0.66, courbure x1, 4 segments) et les expressions sont ecrites pour
// que ses multiplications neutres ne changent aucun arrondi. Desarme, TOUS les brins sont v0.
inline constexpr BladeVariant kBladeVariants[kBladeVariantCount] = {
    {"lame", 4},    // v0 — la lame d'aujourd'hui : fuite lineaire, pointe franche
    {"fine", 4},    // v1 — haute et etroite, tres courbee, pointe effilee
    {"large", 3},   // v2 — courte et large, trois segments, pointe large
    {"faux", 4},    // v3 — large a mi-hauteur, pointe recourbee (fauchee)
    {"jonc", 2},    // v4 — droite et raide, deux segments, bout franc
    {"touffu", 2},  // v5 — petite et trapue, deux segments
};

// Le ruban proche : `SEGMENTS` de grass.vert:68 et le litteral de sommets de l'appel de dessin.
inline constexpr int kBladeStripSegments = 4;
inline constexpr int kBladeStripVerts = 2 * (kBladeStripSegments + 1);  // 10

// Sommets REELLEMENT distincts d'une variante. Jamais superieur a kBladeStripVerts : c'est ce que
// la porte verifie, variante par variante.
inline constexpr int blade_variant_active_verts(int v) {
  return (v < 0 || v >= kBladeVariantCount) ? kBladeStripVerts
                                            : 2 * (kBladeVariants[v].segments + 1);
}

// PROPORTIONS DECLAREES PAR LE PROFIL, en pour mille. `grass-biome-profiles` remplacera cette table
// par une donnee cuite par niveau ; jusque-la c'est LE profil, et il est declare, pas devine.
inline constexpr int kBladeVariantWeightPm[kBladeVariantCount] = {260, 200, 180, 140, 120, 100};

// LE PALIER COMMANDE LE NOMBRE DE VARIANTES (SPEC section 13, ligne « variantes de brin »).
inline constexpr int kBladeVariantsPerPreset[5] = {1, 2, 4, 6, 6};

inline constexpr int variants_for_preset(int preset) {
  return kBladeVariantsPerPreset[preset < 0 ? 0 : (preset > 4 ? 4 : preset)];
}

// LA VARIANTE DE BASE D'UN BRIN : tirage entier sur la table de poids, INDEPENDANT DU PALIER. C'est
// ce qui rend la selection stable : un brin porte sa variante de base partout, et un palier qui ne
// la propose pas la REPLIE (ci-dessous) au lieu de re-tirer.
inline constexpr int blade_variant_base(uint32_t h) {
  int acc = 0;
  const int r = (int)(h % 1000u);
  for (int i = 0; i < kBladeVariantCount; ++i) {
    acc += kBladeVariantWeightPm[i];
    if (r < acc) {
      return i;
    }
  }
  return kBladeVariantCount - 1;
}

// LE REPLI. Un palier a `k` variantes propose exactement [0, k) ; une base hors de cette plage se
// replie par modulo. Consequence exigee par le livrable : deux paliers qui proposent TOUS LES DEUX
// la variante de base d'un brin lui donnent la MEME — le compte de changements est nul par
// construction, et un `hash % k` (le defaut classique) le ferait exploser.
inline constexpr int blade_variant_fold(int base, int k) {
  return (k <= 1) ? 0 : (base % k);
}

// Part attendue de la variante EFFECTIVE `i` a `k` variantes : la somme des poids de toutes les
// bases qui s'y replient. Une seule source pour l'attendu et pour le livre.
inline constexpr int blade_variant_expected_pm(int i, int k) {
  int acc = 0;
  for (int v = 0; v < kBladeVariantCount; ++v) {
    if (blade_variant_fold(v, k) == i) {
      acc += kBladeVariantWeightPm[v];
    }
  }
  return acc;
}

// TOLERANCE SUR LA PART MESUREE, en pour mille, DECLAREE ICI ET PUBLIEE PAR LE MESUREUR. Un plancher
// fixe (le bruit qu'on accepte sur une grande population) plus quatre ecarts-types binomiaux : sans
// le second terme, un niveau a quelques centaines de brins rougirait sur sa seule statistique.
inline constexpr int kBladeVariantTolFloorPm = 15;
inline constexpr int kBladeVariantTolSigmas = 4;

}  // namespace grass_bake
