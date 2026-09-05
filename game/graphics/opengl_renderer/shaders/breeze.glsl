// =================================================================================================
// foliage-wind (owner 2026-09-03 / 2026-09-04) — LA LOI DE BRISE. UNE SEULE, PARTAGEE PAR LES TROIS
// CHEMINS (TIE statique, TIE vent, shrub). Jumelle ligne pour ligne de
// game/graphics/opengl_renderer/background/foliage_wind.cpp::breeze_offset : toute constante changee
// ici l'est aussi la-bas, dans le meme ordre.
//
// CE QUE L'OWNER A REFUSE, DANS L'ORDRE, ET CE QUE CETTE LOI EN FAIT :
//   * 2026-09-03 « une ondulation bizarre comme si c'était pour simuler une distorsion visuelle sous
//     l'eau » : c'etait une onde de 30 cm qui traversait le maillage (phase spatiale a l'echelle du
//     sommet). REGLE (1) : AUCUNE phase spatiale sous l'echelle de la plante. La seule variation
//     spatiale est le FRONT DE RAFALE, de longueur d'onde 120 m ; une plante plie d'un bloc, deux
//     voisines a 3 m plient ensemble.
//   * 2026-09-04 « un mouvement très binaire, juste un tilt, aucune variation, aucune ondulation » :
//     c'etait une flexion toujours sous le vent dont seule l'intensite respirait. REGLE (2) : la
//     couronne OSCILLE autour de sa flexion moyenne (trois composantes de balancement, 0,35 / 0,56 /
//     0,77 Hz, incommensurables, modulees par la rafale) — c'est le retour elastique d'un arbre apres
//     une bouffee, pas un pendule a frequence fixe. REGLE (3) : l'enveloppe est une RAFALE, somme de
//     cinq composantes lentes incommensurables (0,040 a 0,25 Hz) redressee et biaisee vers le calme,
//     donc de vraies accalmies et de vraies bouffees (coefficient de variation de l'enveloppe ~0,5).
//   * 2026-09-04 « ça twitch autant côté feuilles que le tronc » : ce n'est pas cette loi, c'est le
//     POIDS de hauteur (FoliageWindLaw.h : tronc rigide) et, pour les palmiers du chemin vent, le
//     passage de la flexion ajoutee du cisaillement de matrice au sommet-shader (tie_wind.vert).
//   * REGLE (4) : STRICTEMENT HORIZONTAL. Aucune composante verticale : une plante ne flotte pas.
//   * REGLE (5) : LES FEUILLES NE FREMISSENT QUE DANS LA RAFALE (1,40 et 2,13 Hz, gain x enveloppe).
//
// SPECTRE (Hz) du deplacement d'un sommet de couronne, mesure par le moteur (`wind_spectrum_peak_pct`,
// FFT sur la course) : rafale 0,040 0,065 0,105 0,160 0,250 — balancement 0,350 0,5625 0,770 —
// lateral 0,44 0,22 — feuilles 1,40 2,13, plus les intermodulations. Aucune raie ne porte plus de
// ~27 % de l'energie hors continu (conception : 24-27 % selon la phase ; porte a 40 %).
//
// UNITES. Tout est en unites monde GOAL (4096 = 1 m). `t` est en secondes.
// =================================================================================================

// Le front de rafale : 2*pi / (120 m * 4096) — 120 m est LA constante qui interdit l'ondulation.
#define BREEZE_GUST_K 1.27828e-5

// Le moteur de brise. `wpos` : position monde (celle de la plante, ou celle du sommet — a 120 m
// de longueur d'onde les deux donnent la meme rafale). `dir` : cap du vent, normalise (x, z).
// `ph01` : phase propre a la plante, dans [0, 1), CONSTANTE sur toute la plante.
// Renvoie : .x = flexion sous le vent (~[-0.03, 1.15], moyenne ~0.24), .y = derive laterale (signee),
//           .z = gain de fremissement de feuille, dans [0.34, 1.0].
vec3 breeze_drive(vec3 wpos, vec2 dir, float ph01, float t) {
  float travel = dot(wpos.xz, dir) * BREEZE_GUST_K;
  float pp = ph01 * 6.2831853;
  // la rafale : cinq composantes lentes incommensurables, poids decroissants mais VOISINS (aucune
  // ne domine), sommees dans [-1, 1]
  float g = 0.30 * sin(t * 0.2513 - travel + pp * 0.31)
          + 0.27 * sin(t * 0.4084 - travel * 1.73 + pp * 0.77 + 1.7)
          + 0.22 * sin(t * 0.6597 - travel * 2.91 + pp * 0.29 + 4.1)
          + 0.13 * sin(t * 1.0053 - travel * 1.31 + pp * 1.13 + 2.6)
          + 0.08 * sin(t * 1.5708 + pp * 0.53 + 0.9);
  // redressee et biaisee vers le calme : l'exposant 1.6 fait passer plus de temps en bas qu'en haut
  float gust = 0.12 + 0.88 * pow(clamp(0.5 + 0.5 * g, 0.0, 1.0), 1.6);
  // le balancement : flexion moyenne + retour elastique a trois composantes, le tout module par la
  // rafale (dans le calme la couronne se pose ; dans la bouffee elle plie ET oscille)
  float sway = 0.55 + 0.30 * sin(t * 2.1991 + pp * 1.19 + travel * 0.6)
                    + 0.18 * sin(t * 3.5343 + pp * 2.03 + 1.1)
                    + 0.10 * sin(t * 4.8381 + pp * 0.71 + 2.9);
  float along = gust * sway;
  float cross = gust * (0.22 * sin(t * 2.7646 + pp * 1.61 + 2.3) + 0.10 * sin(t * 1.3823 + pp * 0.4));
  return vec3(along, cross, 0.25 + 0.75 * gust);
}

// Le deplacement HORIZONTAL d'un sommet, en unites monde.
//   `w`          : poids de balancement du sommet — 0 au pied de SA plante, 1 a sa couronne. Il
//                  porte AUSSI le facteur de taille de la plante (FoliageWindLaw.h) : c'est pour
//                  cela qu'une seule amplitude `bend_u` sert a toutes les tailles. Peut etre NEGATIF
//                  (partie enfoncee d'un buisson) : la loi est alors lineaire a travers le sol.
//   `bend_u`     : flexion de couronne d'une plante de reference (>= 8 m), en unites monde.
//   `flutter_f`  : fraction de `bend_u` reservee au fremissement de feuille.
// La phase du fremissement ne varie qu'avec `w` — donc avec la hauteur du sommet DANS SA PLANTE.
// Jamais avec sa position monde : c'est la regle (1) ci-dessus, et c'est tout le defaut.
vec2 breeze_offset(vec3 wpos, vec2 dir, float ph01, float t, float w, float bend_u,
                   float flutter_f) {
  vec3 d = breeze_drive(wpos, dir, ph01, t);
  vec2 perp = vec2(-dir.y, dir.x);
  vec2 o = (dir * d.x + perp * d.y) * (bend_u * w);
  float lf1 = sin(t * 8.7965 + ph01 * 12.566 + w * 2.9);
  float lf2 = sin(t * 13.4035 + ph01 * 7.3 + w * 4.1 + 1.3);
  o += (dir * (0.62 * lf1 + 0.38 * lf2) + perp * (lf2 * 0.45)) * (bend_u * w * flutter_f * d.z);
  return o;
}
