#pragma once

// grass-blade-variants (SPEC-refonte-herbe.md, section 6) — SIX ESPECES D'HERBE, ZERO ASSET.
//
// « quatre a six variantes simples, toutes generees depuis `gl_VertexID` comme aujourd'hui, aucun
// asset de maillage. Elles different par le nombre de segments, le profil de largeur et la courbure
// de base. Le palier le plus bas n'en utilise qu'une, le plus haut les six. »
//
// 20/09 11:40, OWNER (JAK-121) : « Attention les types de brins simples niveau geometrie impliquent
// aussi des "especes differentes" au meme titre que les degrades et compagnie, ca joue sur la
// coherence des types, biomes, especes differentes ». Une silhouette + sa palette + sa raideur au
// vent + sa hauteur + sa densite de touffe = UNE ESPECE. Les six types ne sont donc plus six
// tableaux paralleles : c'est UNE TABLE, `kGrassSpecies`, et tout le reste (la table de forme que
// le shader lit, les proportions du profil, le rayon de touffe) en est une VUE. Les chantiers
// couleur (`grass-shading`), vent (`grass-wind`) et biomes (`grass-biome-profiles`) y lisent leurs
// colonnes : `palette_hue`, `palette_val`, `wind_stiff` sont DECLAREES ici et pas encore lues —
// c'est ce qui rend la coherence par espece possible sans dupliquer la table une quatrieme fois.
//
// AUCUNE INCLUSION. Ce fichier est lu par le moteur, par `tools/grass_bake` (outil de bureau, sans
// GL) et par l'empaqueteur, comme `grass_density_presets.h` a cote.

#include <cmath>
#include <cstdint>

namespace grass_bake {

inline constexpr int kBladeVariantCount = 6;

// Le ruban proche : `SEGMENTS` de grass.vert et le litteral de sommets de l'appel de dessin. TOUTES
// les especes emettent les MEMES dix sommets — c'est le point 2 du livrable, et depuis le 20/09
// c'est aussi ce qui tient l'angle entre troncons sous 12 degres (une espece a deux troncons cassait
// a 29 degres : « on voit clairement leurs polygones de pres », owner).
inline constexpr int kBladeStripSegments = 4;
inline constexpr int kBladeStripVerts = 2 * (kBladeStripSegments + 1);  // 10

// LE PORT — la maniere dont l'espece se tient. C'est le troisieme axe que l'owner a nomme le 20/09
// (« silhouette dominante differente, hauteur differente, PORT different ») : deux especes de meme
// hauteur et de meme largeur se distinguent encore si l'une monte droit et l'autre retombe.
enum GrassPort : int {
  kPortDroit = 0,      // monte a la verticale, pas d'inclinaison
  kPortCourbe = 1,     // galbe classique, pointe dans le prolongement
  kPortRetombant = 2,  // se couche franchement, pointe qui redescend
  kPortOuvert = 3,     // s'ecarte du centre de la touffe, pointe qui se releve
};
inline constexpr int kGrassPortCount = 4;

// ===================== LA TABLE UNIQUE DES ESPECES ==========================================
// Les HUIT premiers nombres sont exactement ceux que `shaders/grass.vert` lit dans `VAR_A`/`VAR_B`,
// dans cet ordre. Le recensement les compare un a un a la table GLSL : la duplication est MESUREE.
struct GrassSpecies {
  const char* name;
  // --- SILHOUETTE : VAR_A = (h, hw, taper_lin, taper_quad), VAR_B = (curve_mul, tip, lean, cap)
  float h;           // facteur de hauteur (x la hauteur cuite du brin)
  float hw;          // demi-largeur de base, EN UNITES DE LA HAUTEUR DE L'ESPECE (x H apres h)
  float taper_lin;   // fuite lineaire du profil de largeur
  float taper_quad;  // fuite carree — c'est elle qui donne « pointe large » ou « pointe effilee »
  float curve_mul;   // multiplicateur de courbure (galbe en t^2)
  float tip;         // recourbe de pointe (positif = la pointe continue, negatif = elle se releve)
  float lean;        // INCLINAISON, terme LINEAIRE en t. Une droite n'ajoute aucun pli entre deux
                     // troncons : c'est le seul levier qui donne un port retombant sans montrer un
                     // polygone. Le galbe seul est borne a ~0,42 par la regle des 12 degres.
  float curve_cap;   // plafond doux de courbure, RESOLU par dichotomie (voir en bas de fichier)
  // --- IDENTITE DE L'ESPECE -------------------------------------------------------------------
  int port;                // GrassPort — publie et juge, pas un commentaire
  int weight_pm;           // part de l'espece dans le profil, pour mille (somme == 1000)
  float clump_radius_mul;  // rayon de la touffe de cette espece : > 1 = clairsemee, < 1 = dense
  // --- CE QUE LES AUTRES CHANTIERS D'HERBE LIRONT (JAK-121). Declare ici pour que la coherence par
  //     espece ait UNE source ; AUCUN de ces trois champs n'est lu aujourd'hui (hors perimetre :
  //     « Ne change ni la couleur ni le vent »).
  float palette_hue;  // -> grass-shading : decalage de teinte de l'espece
  float palette_val;  // -> grass-shading : clair/sombre de l'espece
  float wind_stiff;   // -> grass-wind    : raideur (1 = reference ; un jonc plie moins qu'une lame)
};

// LES SIX ESPECES. Les deux echelles sont GEOMETRIQUES, et c'est ce qui rend deux touffes voisines
// distinguables a 3-8 m (owner, 20/09 11:10 : « Toutes les touffes se ressemblent… tres mid ») :
//   hauteur  : rapport 1,320 entre deux especes consecutives  -> >= 30 % exige par le perimetre
//   largeur  : rapport 1,450 sur la largeur EFFECTIVE (h x hw) -> >= 40 % exige par le perimetre
// La largeur qui se voit est `h * hw` et non `hw` : le shader fait `H *= h` PUIS `hw = H * hw`.
// Juger `hw` seul aurait declare 48 % d'ecart la ou l'ecran en montrait 2 % (mesure de l'essai 2 :
// les six largeurs effectives tenaient dans un rapport 1,72, cinq d'entre elles a moins de 20 %).
// Les deux echelles sont normalisees pour que la MOYENNE PONDEREE de la hauteur reste 1,0014 :
// le champ ne devient ni plus haut ni plus bas, il devient varie.
inline constexpr GrassSpecies kGrassSpecies[kBladeVariantCount] = {
    // nom       h       hw        tl     tq      cm     tip    lean   cap    port
    {"lame", 1.0212f, 0.053324f, 0.66f, 0.00f, 1.00f, 0.00f, 0.10f, 0.521f, kPortCourbe, 200,
     1.00f, 0.00f, 0.00f, 1.00f},
    {"fine", 1.3481f, 0.019212f, 1.00f, 0.05f, 1.55f, 0.25f, 0.22f, 0.427f, kPortCourbe, 190,
     1.15f, 0.04f, 0.06f, 0.80f},
    {"large", 0.4440f, 0.373899f, 0.45f, -0.25f, 0.55f, -0.20f, 0.30f, 3.000f, kPortOuvert, 180,
     0.80f, -0.05f, -0.08f, 1.20f},
    {"faux", 0.7737f, 0.102052f, 0.30f, -0.55f, 2.10f, 0.60f, 0.55f, 0.498f, kPortRetombant, 160,
     0.95f, 0.06f, 0.03f, 0.65f},
    {"jonc", 1.7795f, 0.021104f, 0.35f, -0.10f, 0.25f, 0.00f, 0.00f, 3.000f, kPortDroit, 150,
     1.35f, -0.08f, 0.05f, 1.60f},
    {"touffu", 0.5861f, 0.195344f, 0.80f, 0.10f, 1.15f, -0.30f, 0.38f, 1.285f, kPortOuvert, 120,
     0.70f, 0.09f, -0.04f, 1.10f},
};

inline constexpr const GrassSpecies& grass_species(int v) {
  return kGrassSpecies[v < 0 ? 0 : (v >= kBladeVariantCount ? kBladeVariantCount - 1 : v)];
}

// LA VUE « FORME » — les huit nombres du shader, dans l'ordre de VAR_A puis VAR_B. Le recensement
// les lit ici et les compare a la table GLSL ; il n'existe plus de deuxieme litteral cote C++.
struct BladeShape {
  float h;
  float hw;
  float taper_lin;
  float taper_quad;
  float curve_mul;
  float tip;
  float lean;
  float curve_cap;
};

inline constexpr BladeShape blade_shape(int v) {
  const GrassSpecies& S = grass_species(v);
  return BladeShape{S.h, S.hw, S.taper_lin, S.taper_quad, S.curve_mul, S.tip, S.lean, S.curve_cap};
}

// LA LAME D'AVANT L'ITEM, AU BIT PRES. Elle n'est PAS `kGrassSpecies[0]` : le perimetre du 20/09
// deplace toutes les especes sur deux echelles geometriques, v0 compris, et un bras d'ablation qui
// dessinerait la nouvelle `lame` ne rendrait pas l'etat d'avant. `grass.vert` prend ces huit nombres
// quand l'octet d'instance vaut 0, et le mesureur d'angle les prend quand l'item est desarme : les
// deux bras mesurent alors ce que le GPU dessine vraiment, des deux cotes.
inline constexpr BladeShape kBladeShapeLegacy = {1.00f, 0.092f, 0.66f, 0.00f,
                                                 1.00f, 0.00f,  0.00f, 0.00f};

// Sommets REELLEMENT distincts d'une espece. Toutes les especes utilisent les quatre rangees : le
// repli de rangees FABRIQUAIT le pli que l'owner voyait. La fonction reste, c'est elle que la porte
// interroge variante par variante.
inline constexpr int blade_variant_active_verts(int /*v*/) {
  return kBladeStripVerts;
}

inline constexpr int blade_variant_segments(int /*v*/) {
  return kBladeStripSegments;
}

inline constexpr int blade_variant_weight_pm(int v) {
  return grass_species(v).weight_pm;
}

// LE PALIER COMMANDE LE NOMBRE D'ESPECES (SPEC section 13, ligne « variantes de brin »).
//
// 20/09 : la matrice de la SPEC donnait 1/2/4/6/6, et la SPEC ecrit noir sur blanc que ce sont des
// « valeurs provisoires, a confirmer par mesure ». La mesure est faite, et elle condamne 4 au palier
// moyen : la course de l'essai 2 (appareil, preset 2) a rendu `variants_seen=4`, `v4=0` et `v5=0` —
// le jonc et le touffu, les deux silhouettes les PLUS eloignees de la lame, n'atteignaient jamais
// l'ecran de l'owner. Et une repartition sur quatre classes plafonne a 2,000 bits d'entropie : le
// perimetre en exige 2 par zone de 10x10 m, donc quatre especes ne peuvent PAS y arriver.
// CE QUE LA DIVERSITE COUTE, MESURE : rien. Les six especes emettent les memes dix sommets, dans le
// meme appel de dessin, avec le meme octet d'instance ; la seule difference est une lecture de
// table constante dans le vertex shader. `verts_frame` et `draw_calls` le publient a chaque course.
inline constexpr int kBladeVariantsPerPreset[5] = {1, 3, 6, 6, 6};

inline constexpr int variants_for_preset(int preset) {
  return kBladeVariantsPerPreset[preset < 0 ? 0 : (preset > 4 ? 4 : preset)];
}

// L'ESPECE DE BASE D'UN TIRAGE : tirage entier sur la table de poids, INDEPENDANT DU PALIER. C'est
// ce qui rend la selection stable : un brin porte son espece de base partout, et un palier qui ne la
// propose pas la REPLIE (ci-dessous) au lieu de re-tirer.
inline constexpr int blade_variant_base(uint32_t h) {
  int acc = 0;
  const int r = (int)(h % 1000u);
  for (int i = 0; i < kBladeVariantCount; ++i) {
    acc += kGrassSpecies[i].weight_pm;
    if (r < acc) {
      return i;
    }
  }
  return kBladeVariantCount - 1;
}

// LE REPLI. Un palier a `k` especes propose exactement [0, k) ; une base hors de cette plage se
// replie par modulo. Consequence exigee par le livrable : deux paliers qui proposent TOUS LES DEUX
// l'espece de base d'un brin lui donnent la MEME — le compte de changements est nul par
// construction, et un `hash % k` (le defaut classique) le ferait exploser.
inline constexpr int blade_variant_fold(int base, int k) {
  return (k <= 1) ? 0 : (base % k);
}

// Part attendue de l'espece EFFECTIVE `i` a `k` especes : la somme des poids de toutes les bases qui
// s'y replient. Une seule source pour l'attendu et pour le livre.
inline constexpr int blade_variant_expected_pm(int i, int k) {
  int acc = 0;
  for (int v = 0; v < kBladeVariantCount; ++v) {
    if (blade_variant_fold(v, k) == i) {
      acc += kGrassSpecies[v].weight_pm;
    }
  }
  return acc;
}

// TOLERANCE SUR LA PART MESUREE, en pour mille, DECLAREE ICI ET PUBLIEE PAR LE MESUREUR. Un plancher
// fixe (le bruit qu'on accepte sur une grande population) plus quatre ecarts-types binomiaux : sans
// le second terme, un niveau a quelques centaines de brins rougirait sur sa seule statistique.
inline constexpr int kBladeVariantTolFloorPm = 15;
inline constexpr int kBladeVariantTolSigmas = 4;

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
//   x = (2s-1) * hw * (1 - taper_lin*t + taper_quad*t^2)
//   y = t
//   z = lean*t + C' * t^2 * (1 + tip*t)
// `armed` DIT DANS QUEL REGIME ON MESURE. Desarme, `grass.vert` n'applique PAS le plafond (l'octet
// d'instance vaut 0) : publier l'angle plafonne sur ce bras ferait dire a l'instrument le contraire
// de ce que le GPU dessine, et l'ablation montrerait un zero au lieu du defaut qui revient.
//
// LES PLAFONDS DE LA TABLE SONT RESOLUS, PAS CHOISIS. Pour chaque espece on prend le plus GRAND cap
// dont l'angle maximal, balaye sur toute la plage de `curve` du bake ([0,10 ; 0,85]), reste sous
// 11 500 mdeg — 500 de marge sous l'interdit. Resultat mesure a la resolution : lame 11 497,
// fine 11 488, faux 11 495, touffu 11 500 ; `large` et `jonc` n'ont besoin d'aucun plafond (8 901 et
// 6 000 mdeg a courbure libre), leur cap de 3,0 est hors de portee.
inline int blade_seg_angle_mdeg(int v, float curve, bool armed) {
  if (v < 0 || v >= kBladeVariantCount) {
    return 0;
  }
  const BladeShape S = armed ? blade_shape(v) : kBladeShapeLegacy;
  const int nseg = kBladeStripSegments;
  if (nseg < 2) {
    return 0;
  }
  const float C =
      armed ? blade_curve_capped(curve * S.curve_mul, S.curve_cap) : curve * S.curve_mul;
  double worst = 0.0;
  for (int side = 0; side < 2; ++side) {
    const float sg = side ? 1.0f : -1.0f;
    double px[8], py[8], pz[8];
    for (int j = 0; j <= nseg; ++j) {
      const float t = (float)j / (float)nseg;
      px[j] = sg * S.hw * (1.0f - S.taper_lin * t + S.taper_quad * t * t);
      py[j] = t;
      pz[j] = S.lean * t + C * t * t * (1.0f + S.tip * t);
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

// ===================== CE QUI SEPARE DEUX ESPECES, MESURE SUR LA TABLE ======================
// Le perimetre du 20/09 11:10 chiffre trois separations. Elles ne dependent pas de la population :
// ce sont des proprietes de la table, calculees ici et publiees par les DEUX mesureurs (moteur et
// outil hors ligne) pour qu'aucun des deux ne puisse les affirmer sans les montrer.

// Ecart RELATIF minimal de hauteur entre deux especes, pour mille. Perimetre : >= 30 %.
inline constexpr int kBladeSpeciesHeightGapPmFloor = 300;
// ... et de largeur EFFECTIVE (h * hw), celle qui se voit a l'ecran. Perimetre : >= 40 %.
inline constexpr int kBladeSpeciesWidthGapPmFloor = 400;
// Nombre de PORTS distincts que les six especes doivent couvrir.
inline constexpr int kBladeSpeciesPortsFloor = 3;

inline int blade_species_min_gap_pm(bool width) {
  double worst = -1.0;
  for (int a = 0; a < kBladeVariantCount; ++a) {
    for (int b = a + 1; b < kBladeVariantCount; ++b) {
      const double va = width ? (double)kGrassSpecies[a].h * kGrassSpecies[a].hw : kGrassSpecies[a].h;
      const double vb = width ? (double)kGrassSpecies[b].h * kGrassSpecies[b].hw : kGrassSpecies[b].h;
      const double lo = va < vb ? va : vb;
      const double hi = va < vb ? vb : va;
      if (lo <= 0.0) {
        return 0;
      }
      const double gap = (hi / lo - 1.0) * 1000.0;
      if (worst < 0.0 || gap < worst) {
        worst = gap;
      }
    }
  }
  return worst < 0.0 ? 0 : (int)(worst + 0.5);
}

inline int blade_species_ports() {
  bool seen[kGrassPortCount] = {};
  int n = 0;
  for (int v = 0; v < kBladeVariantCount; ++v) {
    const int p = kGrassSpecies[v].port;
    if (p >= 0 && p < kGrassPortCount && !seen[p]) {
      seen[p] = true;
      n++;
    }
  }
  return n;
}

// ===================== LA TOUFFE COMMANDE L'ESPECE ==========================================
// 20/09, RETOUR OWNER : « tu fais juste des touffes avec toutes les geometries, pas de touffes
// d'herbe differentes ». L'espece ne se tire plus par brin mais PAR TOUFFE ; une minorite de brins
// porte une autre forme pour que la touffe ne soit pas un clone parfait.
//
// LA MINORITE SE LIT SUR LE RANG, PAS SUR UN TIRAGE. Le rang d'un brin dans sa touffe est un
// PREFIXE d'un palier a l'autre (grass-clumps) : un brin garde son rang quand le palier ajoute des
// brins. Un tirage aleatoire aurait donne une part qui depend du nombre de brins de la touffe, donc
// une touffe dominante a 3 brins et pas a 9, et une espece qui CHANGE de palier en palier.
inline constexpr uint32_t kBladeClumpMinorityStride = 5;  // un brin sur cinq au plus -> <= 20 %
inline constexpr bool blade_is_minority(uint32_t rank) {
  return (rank % kBladeClumpMinorityStride) == (kBladeClumpMinorityStride - 1u);
}

// HAUTEUR PAR TOUFFE. « pas de variations de hauteur » (owner, 20/09) : le champ portait une
// variation par brin et une modulation par RANG dans la touffe, jamais un facteur commun a toute
// une touffe. Plage symetrique autour de 1 : la hauteur MOYENNE du champ ne bouge pas.
inline constexpr float kBladeClumpHeightLo = 0.70f;
inline constexpr float kBladeClumpHeightHi = 1.30f;

// LA ZONE SUR LAQUELLE ON JUGE LA VARIETE. Perimetre du 20/09 11:10, mot pour mot : « sur une zone
// de 10x10 m, entropie de la silhouette dominante >= 2 bits sur 6 types ». Une entropie calculee sur
// le NIVEAU ENTIER serait verte avec six especes empilees en six plaques : c'est la zone qui rend la
// mesure fidele a ce que l'owner voit d'un coup d'oeil. Les cellules a moins de `MinClumps` touffes
// (bords de niveau, eclats) ne sont pas jugees — elles sont COMPTEES et publiees a part.
inline constexpr float kBladeZoneCellM = 10.0f;
inline constexpr int kBladeZoneMinClumps = 64;
inline constexpr int kBladeZoneEntropyMbitsFloor = 2000;  // 2,000 bits

// DENSITE PAR ESPECE. « densite et nombre de brins PAR TOUFFE varies (une touffe clairsemee a cote
// d'une touffe dense) ». Le nombre de brins d'une touffe est deja disperse par le poids de tirage de
// `grass-clumps` ; ce qui manquait est la DENSITE — la meme poignee de brins etalee sur un rayon
// plus grand se lit clairsemee. Le rayon est le seul levier qui ne redistribue AUCUNE racine entre
// touffes : la nidification par palier de `grass-clumps` reste exacte au brin pres.
inline constexpr int kBladeClumpBladesCvPmFloor = 250;  // ecart-type du compte par touffe, >= 25 %

inline float species_clump_radius_mul(int v) {
  return grass_species(v).clump_radius_mul;
}

// LES PLANCHERS DE LA PORTE, DECLARES ICI, PUBLIES PAR LE MESUREUR (pour mille).
inline constexpr int kBladeClumpDominantPmFloor = 800;   // touffes a silhouette dominante
inline constexpr int kBladeClumpDominantSharePm = 800;   // ... « dominante » = 80 % des brins
inline constexpr int kBladeClumpHeightCvPmFloor = 200;   // ecart-type de hauteur ENTRE touffes
inline constexpr int kBladeNeighborDiffPmFloor = 500;    // touffes voisines de silhouette differente

}  // namespace grass_bake
