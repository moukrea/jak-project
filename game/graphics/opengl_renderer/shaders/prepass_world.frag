#version 410 core
// lighting-ao-indirect : profondeur seule, plus L'ALPHA-TEST DU FEUILLAGE (SPEC §4.6, refus owner
// du 2026-09-10 (b)).
//
// LE SEUIL. La passe principale jette le fragment quand `fragment_color.a * T0.a < alpha_min`
// (tfrag3.frag:130, shrub.frag:84), avec `fragment_color.a = tod.a * 4.0` dans les DEUX familles
// (tfrag3.vert:92-95, shrub.vert:112-119). La prepasse n'a ni l'indice de temps-du-jour (location 2
// chez tfrag/tie, location 3 chez shrub : pas la meme) ni la LUT, donc elle ne peut pas former
// `fragment_color.a`. Elle prend la borne SUPERIEURE tod.a <= 1 et teste
//     T0.a * 4.0 < alpha_min   <=>   T0.a < u_cut_aref   avec u_cut_aref = alpha_min / 4
// Ce test est CONSERVATEUR par construction : il ne retire QUE des fragments que la passe
// principale jette a coup sur. Ce qu'il laisse passer — la bande T0.a dans [alpha_min/4, alpha_min)
// — n'est pas suppose vide : il est COMPTE et publie, `ao_alpha_fringe_px` (PrePass.cpp).
//
// LES DEUX MODES. u_cut_mode == 0 : le chemin LIVRE, `discard`, aucune couleur (le FBO de la
// prepasse n'a pas d'attachement couleur). u_cut_mode == 1 : la passe de CLASSIFICATION de la
// preuve — aucun discard, profondeur en GL_EQUAL contre la profondeur deja ecrite, et la couleur
// dit ce que le fragment GAGNANT est : R = il est sous le seuil, G = il a gagne (denominateur),
// B = il est dans la bande ambigue. Le meme detecteur juge les deux bras (decoupe armee / decoupe
// desarmee) : c'est le bras desarme qui prouve qu'il sait rendre autre chose que zero.
precision highp float;

in vec3 tex_coord;

uniform sampler2D tex_T0;
uniform float u_cut_aref;  // seuil sur l'alpha de TEXTURE ; <= 0 => aucun test d'alpha
uniform float u_cut_amb;   // haut de la bande ambigue (= alpha_min) ; <= 0 => aucune bande
uniform int u_cut_mode;    // 0 = livre (discard) ; 1 = classification (aucun discard)

out vec4 color;

void main() {
  float ta = 1.0;
  if (u_cut_aref > 0.0) {
    ta = texture(tex_T0, tex_coord.xy).a;
  }
  bool cut = (u_cut_aref > 0.0) && (ta < u_cut_aref);
  if (u_cut_mode == 0) {
    if (cut) {
      discard;
    }
    return;
  }
  bool amb = (u_cut_aref > 0.0) && !cut && (ta < u_cut_amb);
  color = vec4(cut ? 1.0 : 0.0, 1.0, amb ? 1.0 : 0.0, 1.0);
}
