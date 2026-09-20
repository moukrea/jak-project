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

#include <cmath>
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
// 20/09, RETOUR OWNER : « certaines des geometries... on voit clairement leurs polygones de pres,
// c'est nul ! ». Les variantes a 2 et 3 segments repliaient des rangees : un brin a deux segments
// casse a 29 degres entre ses deux troncons, et ce pli est CE QU'IL VOIT. Les six variantes
// utilisent donc les QUATRE rangees du ruban — le nombre de sommets SOUMIS ne bouge pas (10, il
// etait deja de 10 pour tout le monde), seule la part repliee disparait. La silhouette se distingue
// desormais par la largeur, la fuite, la hauteur et la courbure, qui ne coutent aucun pli.
inline constexpr BladeVariant kBladeVariants[kBladeVariantCount] = {
    {"lame", 4},    // v0 — la lame d'aujourd'hui : fuite lineaire, pointe franche
    {"fine", 4},    // v1 — haute et etroite, tres courbee, pointe effilee
    {"large", 4},   // v2 — courte et large, pointe large
    {"faux", 4},    // v3 — large a mi-hauteur, pointe recourbee (fauchee)
    {"jonc", 4},    // v4 — droite et raide, bout franc
    {"touffu", 4},  // v5 — petite et trapue
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


// ===================== LA FORME, EN C++ ET EN UNE SEULE TABLE =============================
// Elle vivait dans `shaders/grass.vert` seul. La porte de l'essai 2 doit MESURER un angle entre
// deux troncons emis : elle a besoin de la meme table, et une deuxieme copie non comparee serait
// une divergence en attente. Le recensement compare donc les HUIT nombres de chaque ligne a ceux
// de la table GLSL, pas seulement le nombre de segments comme jusqu'ici.
struct BladeShape {
  float h;            // VAR_A.x — facteur de hauteur
  float hw;           // VAR_A.y — demi-largeur de base (x H)
  float taper_lin;    // VAR_A.z — fuite lineaire
  float taper_quad;   // VAR_A.w — fuite carree
  float curve_mul;    // VAR_B.x — multiplicateur de courbure
  float tip;          // VAR_B.y — recourbe de pointe
  float segments;     // VAR_B.z — rangees distinctes (== kBladeVariants[].segments)
  float curve_cap;    // VAR_B.w — PLAFOND DE COURBURE (0 = aucun ; voir blade_curve_capped)
};

// LE PLAFOND DE COURBURE, PAR VARIANTE. Un brin a quatre troncons ne peut pas tourner de 70 degres
// sans montrer ses plis : chaque plafond est le plus GRAND qui tienne l'angle maximal sous
// kBladeSegAngleCapMdeg sur toute la plage de `curve` du bake ([0,10 ; 0,85]), calcule sur les
// sommets EMIS (les deux bords du ruban, pas l'axe). v4 n'en a pas besoin : 3.0 est hors de portee.
inline constexpr BladeShape kBladeShapes[kBladeVariantCount] = {
    {1.00f, 0.092f, 0.66f,  0.00f, 1.00f,  0.00f, 4.0f, 0.48f},  // v0 lame
    {1.18f, 0.062f, 1.00f,  0.05f, 1.35f,  0.25f, 4.0f, 0.35f},  // v1 fine
    {0.82f, 0.150f, 0.45f, -0.25f, 0.70f,  0.00f, 4.0f, 0.59f},  // v2 large
    {1.05f, 0.105f, 0.30f, -0.55f, 1.60f,  0.45f, 4.0f, 0.27f},  // v3 faux
    {1.30f, 0.055f, 0.35f, -0.10f, 0.45f,  0.00f, 4.0f, 3.00f},  // v4 jonc
    {0.70f, 0.125f, 0.80f,  0.10f, 1.10f, -0.20f, 4.0f, 0.58f},  // v5 touffu
};

// L'ANGLE QU'ON S'INTERDIT (millidegres). Ordre de l'owner du 20/09, chiffre par le perimetre de
// l'item : « l'angle entre deux segments consecutifs reste sous 12 degres a la distance de LOD 0 ».
inline constexpr int kBladeSegAngleCapMdeg = 12000;

// LE PLAFONNEMENT, DOUX. Un `min()` ecraserait la moitie de la population sur la MEME courbure —
// la diversite que l'item doit produire. Cette forme est strictement croissante, elle conserve
// l'ordre des brins entre eux, et elle tend vers `cap` sans jamais l'atteindre.
//   C' = C / sqrt(1 + (C/cap)^2)
inline float blade_curve_capped(float c, float cap) {
  if (cap <= 0.0f) {
    return c;
  }
  const float r = c / cap;
  return c / std::sqrt(1.0f + r * r);
}

// L'ANGLE MAXIMAL ENTRE DEUX TRONCONS CONSECUTIFS, SUR LES SOMMETS EMIS, en millidegres.
// Repere local du brin, normalise par H (l'angle n'en depend pas) et pris au regime de reference du
// LOD 0 : rim_w = rim_h = nearf = heightMul = 1, vent nul — c'est la SILHOUETTE STATIQUE, celle que
// l'owner regarde a l'arret. `grass.vert` emet, pour la rangee j et le cote s :
//   x = (2s-1) * hw * (1 - taper_lin*t + taper_quad*t^2)   y = t   z = C' * t^2 * (1 + tip*t)
// `capped` DIT DANS QUEL REGIME ON MESURE. Desarme, `grass.vert` n'applique PAS le plafond (l'octet
// d'instance vaut 0) : publier l'angle plafonne sur ce bras ferait dire a l'instrument le contraire
// de ce que le GPU dessine, et l'ablation montrerait un zero au lieu du defaut qui revient.
inline int blade_seg_angle_mdeg(int v, float curve, bool capped) {
  if (v < 0 || v >= kBladeVariantCount) {
    return 0;
  }
  const BladeShape& S = kBladeShapes[v];
  const int nseg = (int)S.segments;
  if (nseg < 2) {
    return 0;
  }
  const float C = capped ? blade_curve_capped(curve * S.curve_mul, S.curve_cap)
                         : curve * S.curve_mul;
  double worst = 0.0;
  for (int side = 0; side < 2; ++side) {
    const float sg = side ? 1.0f : -1.0f;
    double px[8], py[8], pz[8];
    for (int j = 0; j <= nseg; ++j) {
      const float t = (float)j / (float)nseg;
      px[j] = sg * S.hw * (1.0f - S.taper_lin * t + S.taper_quad * t * t);
      py[j] = t;
      pz[j] = C * t * t * (1.0f + S.tip * t);
    }
    for (int j = 0; j + 2 <= nseg; ++j) {
      const double ux = px[j + 1] - px[j], uy = py[j + 1] - py[j], uz = pz[j + 1] - pz[j];
      const double wx = px[j + 2] - px[j + 1], wy = py[j + 2] - py[j + 1], wz = pz[j + 2] - pz[j + 1];
      const double nu = std::sqrt(ux * ux + uy * uy + uz * uz);
      const double nw = std::sqrt(wx * wx + wy * wy + wz * wz);
      if (nu <= 0.0 || nw <= 0.0) {
        continue;
      }
      double c = (ux * wx + uy * wy + uz * wz) / (nu * nw);
      c = c > 1.0 ? 1.0 : (c < -1.0 ? -1.0 : c);
      const double a = std::acos(c) * 57295.779513;  // radians -> millidegres
      if (a > worst) {
        worst = a;
      }
    }
  }
  return (int)(worst + 0.5);
}

// ===================== LA TOUFFE COMMANDE LA SILHOUETTE ===================================
// 20/09, RETOUR OWNER : « tu fais juste des touffes avec toutes les geometries, pas de touffes
// d'herbe differentes ». La variante ne se tire plus par brin mais PAR TOUFFE ; une minorite de
// brins porte une autre forme pour que la touffe ne soit pas un clone parfait.
//
// LA MINORITE SE LIT SUR LE RANG, PAS SUR UN TIRAGE. Le rang d'un brin dans sa touffe est un
// PREFIXE d'un palier a l'autre (grass-clumps) : un brin garde son rang quand le palier ajoute des
// brins. Un tirage aleatoire aurait donne une part qui depend du nombre de brins de la touffe,
// donc une touffe dominante a 3 brins et pas a 9, et une variante qui CHANGE de palier en palier.
inline constexpr uint32_t kBladeClumpMinorityStride = 5;  // un brin sur cinq au plus -> <= 20 %
inline constexpr bool blade_is_minority(uint32_t rank) {
  return (rank % kBladeClumpMinorityStride) == (kBladeClumpMinorityStride - 1u);
}

// HAUTEUR PAR TOUFFE. « pas de variations de hauteur » (owner, 20/09) : le champ portait une
// variation par brin et une modulation par RANG dans la touffe, jamais un facteur commun a toute
// une touffe. Plage symetrique autour de 1 : la hauteur MOYENNE du champ ne bouge pas.
inline constexpr float kBladeClumpHeightLo = 0.70f;
inline constexpr float kBladeClumpHeightHi = 1.30f;

// LES TROIS PLANCHERS DE LA PORTE, DECLARES ICI, PUBLIES PAR LE MESUREUR (pour mille).
inline constexpr int kBladeClumpDominantPmFloor = 800;   // touffes a silhouette dominante
inline constexpr int kBladeClumpDominantSharePm = 800;   // ... « dominante » = 80 % des brins
inline constexpr int kBladeClumpHeightCvPmFloor = 150;   // ecart-type de hauteur ENTRE touffes
inline constexpr int kBladeNeighborDiffPmFloor = 500;    // touffes voisines de silhouette differente

}  // namespace grass_bake
