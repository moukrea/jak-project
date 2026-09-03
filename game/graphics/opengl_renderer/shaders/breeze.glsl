// =================================================================================================
// foliage-wind (owner 2026-09-03) — LA LOI DE BRISE. UNE SEULE, PARTAGEE PAR LES TROIS CHEMINS.
//
// CE QU'ELLE REMPLACE, ET POURQUOI. Le round precedent livrait TROIS lois independantes :
//   * shrub.vert        : 3 sinusoides dont la phase etait une fonction de la POSITION MONDE du
//                         sommet, de longueur d'onde 38 cm en x et 31 cm en z (mesure :
//                         2*pi/0.004 = 1571 u = 0.38 m, 2*pi/0.005 = 1257 u = 0.31 m). Un buisson
//                         d'un metre contenait donc DEUX A TROIS periodes completes : ses sommets
//                         partaient en sens opposes. Une onde progressive de 30 cm qui traverse un
//                         maillage n'est pas une brise, c'est une refraction — mot pour mot ce que
//                         l'owner decrit : « une ondulation bizarre comme si c'était pour simuler
//                         une distorsion visuelle sous l'eau ».
//   * tie_sway.glsl     : 2 sinusoides + un terme croise, AMPLITUDE CONSTANTE, 0.26 / 0.71 / 0.47 Hz.
//   * tie_wind.vert     : 3 sinusoides + un BALLANT VERTICAL (`lpos.y -= ... * (0.5 + 0.5*f1)`)
//                         synchronise avec l'horizontale. Horizontal + vertical en quadrature a
//                         frequence constante, c'est la definition d'un mouvement de flottaison.
//
// LES TROIS REGLES QUE CETTE LOI TIENT, ET QUI SONT CHACUNE UN DEFAUT CITE :
//
//   (1) AUCUNE PHASE SPATIALE SOUS L'ECHELLE DE LA PLANTE. La seule variation spatiale est le
//       FRONT DE RAFALE, de longueur d'onde 120 m. Une plante de 2 m voit donc 1,7 % de cycle
//       d'un bout a l'autre, un palmier de 24 m en voit 20 % : la plante PLIE, elle n'ondule
//       jamais. Deux voisines a 3 m l'une de l'autre sont a 2,5 % de cycle : elles bougent
//       ENSEMBLE, ce qui interdit le « un est pris l'autre non » d'origine temporelle.
//
//   (2) UNE RAFALE, PAS UN OSCILLATEUR. L'enveloppe `gust` est une somme de TROIS composantes
//       lentes incommensurables ponderee en 1/f (0,047 / 0,081 / 0,140 Hz), redressee et biaisee
//       vers le calme. La flexion est donc TOUJOURS SOUS LE VENT et sa force RESPIRE, au lieu de
//       traverser la verticale a cadence fixe. C'est la difference entre « une légère brise avec
//       des variations » et le pendule que l'owner refuse.
//
//   (3) LES FEUILLES NE FREMISSENT QUE DANS LA RAFALE. Le terme rapide (1,40 et 2,13 Hz) a son
//       amplitude MULTIPLIEE par l'enveloppe. Dans le calme il se tait. Un fremissement d'amplitude
//       constante lit comme une vibration mecanique, jamais comme du vent.
//
//   (4) STRICTEMENT HORIZONTAL. Aucune composante verticale, dans aucun terme : une plante ne
//       s'enfonce pas dans le sol et ne flotte pas. C'est ce qui reste du ballant vertical de
//       tie_wind.vert.
//
// SPECTRE PUBLIE (Hz) : 0,047 0,081 0,140 (rafale) — 0,187 0,122 (respiration et derive) —
// 1,400 2,133 (feuilles), plus l'intermodulation rafale x feuilles. Aucune raie ne porte la
// majorite de l'energie : c'est l'exigence « un spectre de brise, pas une seule frequence ».
//
// UNITES. Tout est en unites monde GOAL (4096 = 1 m). `t` est en secondes.
// =================================================================================================

// Le front de rafale : 2*pi / (120 m * 4096) — 120 m est LA constante qui interdit l'ondulation.
#define BREEZE_GUST_K 1.27828e-5

// Le moteur de brise. `wpos` : position monde (celle de la plante, ou celle du sommet — a 120 m
// de longueur d'onde les deux donnent la meme rafale). `dir` : cap du vent, normalise (x, z).
// `ph01` : phase propre a la plante, dans [0, 1), CONSTANTE sur toute la plante.
// Renvoie : .x = flexion sous le vent (positive, ~[0.08, 1.10]), .y = derive laterale (signee),
//           .z = gain de fremissement de feuille, dans [0.25, 1.0].
vec3 breeze_drive(vec3 wpos, vec2 dir, float ph01, float t) {
  float travel = dot(wpos.xz, dir) * BREEZE_GUST_K;
  float pp = ph01 * 6.2831853;
  // trois composantes lentes incommensurables, ponderees en 1/f
  float g1 = sin(t * 0.2971 - travel + pp * 0.31);
  float g2 = sin(t * 0.5107 - travel * 1.73 + pp * 0.77 + 1.7);
  float g3 = sin(t * 0.8807 - travel * 2.91 + pp * 0.29 + 4.1);
  float swell = 0.50 * g1 + 0.31 * g2 + 0.19 * g3;  // [-1, 1]
  // redressee et biaisee vers le calme : l'exposant 1.7 fait passer plus de temps en bas qu'en
  // haut, donc de vraies accalmies entre les rafales.
  float gust = 0.16 + 0.84 * pow(0.5 + 0.5 * swell, 1.7);
  // la respiration : la flexion reste sous le vent (le facteur ne change jamais de signe) mais
  // son intensite varie a 0,187 Hz.
  float along = gust * (0.80 + 0.30 * sin(t * 1.1731 + pp * 1.19 + travel * 0.6));
  float cross = gust * 0.28 * sin(t * 0.7639 + pp * 1.61 + 2.3);
  return vec3(along, cross, 0.25 + 0.75 * gust);
}

// Le deplacement HORIZONTAL d'un sommet, en unites monde.
//   `w`          : poids de balancement du sommet — 0 au pied de SA plante, 1 a sa couronne. Il
//                  porte AUSSI le facteur de taille de la plante (voir foliage_wind.h) : c'est
//                  pour cela qu'une seule amplitude `bend_u` sert a toutes les tailles.
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
