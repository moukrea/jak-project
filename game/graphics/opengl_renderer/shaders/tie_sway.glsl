// =================================================================================================
// Grecharged-foliage-wind3 (owner 2026-08-31, defaut D2 : « tous les arbres ne sont pas impactés »)
// BALANCEMENT DU TIE STATIQUE — chunk partage.
//
// Trois programmes dessinent du TIE statique et doivent donc bouger IDENTIQUEMENT, sinon la passe
// de base et la passe de reflet d'un meme objet envmappe se decolleraient :
//   * tfrag3.vert    (TIE non-envmappe, Tie3.cpp:1119)
//   * etie_base.vert (passe de base envmappee, Tie3.cpp:1119)
//   * etie.vert      (passe additive de reflet, Tie3.cpp:1660)
// Le code vit ICI et une seule fois ; Shader.cpp:201-267 le recopie verbatim chez les trois.
//
// LE PIEGE, ET C'EST LE VERROU (a) : `tfrag3.vert` est AUSSI le shader du terrain TFRAG
// (TFragment.cpp:660,1249,1350) et du shrub. Un uniforme laisse a sa derniere valeur ferait
// ONDULER LE SOL. `first_tfrag_draw_setup` (background_common.cpp) ecrit donc
// `u_tie_sway_amp = 0` a CHAQUE activation de programme, pour TOUS les appelants, et Tie3 ne le
// releve que juste apres, sur ses propres passes.
// VERROU (b), independant : le VAO du TFRAG n'active pas l'attribut 7, et `glVertexAttrib4f(7, 0,
// 0, 0, 1)` est pousse explicitement a cote de l'uniforme. La specification OpenGL garantit deja
// (0,0,0,1) pour un attribut desactive, mais aucune mesure de cet arbre ne l'a jamais verifie sur
// l'Adreno, et l'historique du depot interdit de se fier a une garantie non mesuree.
//
// AMPLITUDE. `u_tie_sway_amp` est en UNITES MONDE (4096 = 1 m) et vaut le deplacement horizontal a
// la couronne. Elle est STRICTEMENT SOUS le chemin VENT : celui-ci applique un cisaillement sans
// dimension (0,12 par defaut) multiplie par la HAUTEUR du sommet, donc ~2,1 m au sommet d'un
// palmier de 17,5 m, contre 0,10 m ici. C'est la hierarchie que l'owner a posee : « ceux qui n'en
// ont pas doivent en recevoir une, PLUS LEGERE ».
//
// ATTRIBUT 7, DEUX OCTETS NORMALISES. Ni le poids ni la phase ne se calculent dans le shader : ils
// arrivent tout cuits, derives au chargement par TieTree::unpack() de l'ancrage et de l'identite de
// CHAQUE INSTANCE (voir Tfrag3Data.h). Le shader ne sait pas ce qu'est un palmier — il applique un
// poids, et le poids vaut 0 partout ailleurs.
//   .x = poids  (0 au pied de la plante, 1 a sa couronne, 0 sur tout ce qui n'est pas vegetal)
//   .y = phase  (constante sur toute la plante, decorrelee d'une plante a l'autre)
// La phase NE PEUT PAS se deriver dans le shader : la position varie a l'interieur de la plante
// (elle la dechirerait) et `time_of_day_index` identifie le PROTOTYPE sur TIE (tous les palmiers
// bougeraient en synchronisme parfait). Elle est donc une donnee, comme le poids.
layout (location = 7) in vec2 tie_sway_in;

uniform float u_tie_sway_amp;   // unites monde (4096 = 1 m) ; 0 = ETEINT, le bloc est saute
uniform float u_tie_sway_time;  // secondes, horloge murale monotone
uniform vec2 u_tie_sway_dir;    // cap du vent, normalise (x, z)

vec3 tie_sway_apply(vec3 wpos, vec2 sw) {
  if (u_tie_sway_amp <= 0.0 || sw.x <= 0.0) {
    return wpos;
  }
  float ph = sw.y * 6.2831853;
  // Deux sinusoides INCOMMENSURABLES (rapport irrationnel) : la somme ne se repete pas, donc l'oeil
  // n'accroche pas de periode. 0,26 Hz et 0,71 Hz — la bande que le round 2 a mesuree comme
  // perceptible, sous la frequence de fremissement des feuilles du chemin vent.
  float s1 = sin(u_tie_sway_time * 1.6336 + ph);
  float s2 = sin(u_tie_sway_time * 4.4611 + ph * 1.7 + 0.9);
  float sway = 0.62 * s1 + 0.38 * s2;
  // Terme croise, plus petit : la couronne trace une ellipse au lieu de glisser sur une droite.
  float cross_t = sin(u_tie_sway_time * 2.9531 + ph * 1.3 + 2.1);
  vec2 d = u_tie_sway_dir;
  vec2 disp = (d * sway + vec2(-d.y, d.x) * cross_t * 0.35) * (u_tie_sway_amp * sw.x);
  // HORIZONTAL uniquement : pas de composante verticale, une plante ne s'enfonce pas dans le sol.
  wpos.x += disp.x;
  wpos.z += disp.y;
  return wpos;
}
