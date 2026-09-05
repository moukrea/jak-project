#pragma once

// lighting_census — RECENSEMENT DES CINQ CHEMINS D'OMBRAGE DU DECOR + TEMPS GPU PAR PASSE.
//
// POURQUOI. SPEC-refonte-lumiere.md §2.3 : le chemin qui ombre un fragment du decor depend de
// QUATRE booleens d'uniforme, et il y a donc cinq composites exclusifs :
//
//     B · PBR fusionne  : u_rt_light_on != 0 && u_pbr_mode != 0
//     A · modulation    : u_rt_light_on != 0 && u_pbr_mode == 0 && u_rt_probe_on == 0
//     D · sondes        : u_rt_light_on != 0 && u_rt_probe_on != 0        (annonce MORT)
//     C · PBR autonome  : u_rt_light_on == 0 && u_pbr_mode != 0
//     E · relight legacy: sinon, u_pbr_shadow_on != 0
//
// Personne ne pouvait dire lequel avait dessine un pixel, donc aucun item de la refonte ne
// pouvait prouver qu'il n'avait rien casse. Ce module compte, PAR DRAW, dans quel chemin le
// draw est tombe, et publie la repartition par `autoport_proof`.
//
// AU SITE DE DECISION, PAS DEDUIT. Les quatre valeurs sont enregistrees LA OU ELLES SONT
// POUSSEES (`glUniform1i`), c'est-a-dire exactement ce que l'objet programme contient quand le
// draw part. Il n'y a que huit sites de poussee dans tout `game/graphics/` :
//   u_pbr_mode        background_common.cpp  (first_tfrag_draw_setup, PbrDrawBinder::set x2,
//                                             PbrDrawBinder::finish)
//   u_pbr_shadow_on   background_common.cpp  (first_tfrag_draw_setup, pbr_shadow_bind_receiver)
//   u_rt_light_on     background_common.cpp  (first_tfrag_draw_setup)
//   u_rt_probe_on     FollowProbe.cpp        (update_and_bind, constante 0, inconditionnel)
//
// UNE OMBRE N'EST PAS UNE MESURE. Un miroir CPU de ce qu'on croit avoir pousse serait
// infalsifiable. Une fois par image, sur un draw dont l'indice tourne, le module RELIT les
// quatre uniformes sur le programme reellement lie (`glGetUniformiv`) et compare. Les deux
// compteurs `light_census_rb_checks` / `light_census_rb_mismatch` sont publies cote a cote :
// un ecart non nul dit que le recensement ment, et ou.
//
// LE SEAU « NON CLASSE » EST DETAILLE. `hfrag.frag` ne declare AUCUN des quatre uniformes ; les
// passes de profondeur et de projecteur d'ombre ne portent pas de couleur ; et un draw dont les
// quatre portes sont a zero est le rendu d'ORIGINE, pas un chemin de la refonte. Les trois sont
// comptes separement — un seau « exclu » n'est pas un seau « correct ».
//
// TEMPS GPU. Aucun timer GPU n'existait dans cet arbre (seulement du temps CPU mur dans
// Profiler.h). Ici : une paire `glQueryCounter(GL_TIMESTAMP)` autour de chaque bucket, moissonnee
// trois images plus tard pour ne jamais bloquer le pipeline, sommee par passe. Quand
// `glQueryCounter` est absent (GLES sans EXT_disjoint_timer_query), RIEN n'est publie et
// `gpu_timer_supported=0` le dit : une cle sans site d'ecriture est une fausse constante.

#include <cstdint>

namespace lighting_census {

// Nature du draw monde, telle que le renderer la connait a son site d'appel.
enum class Kind : int {
  Tfrag = 0,
  Tie,       // TIE / ETIE, passe de base et passe envmap
  TieWind,   // TIE_WIND
  Shrub,     // arbustes
  Hfrag,     // hfrag : le programme ne declare aucun des quatre uniformes
  DepthOnly  // prepasse de profondeur / projecteur d'ombre : aucune couleur produite
};

// Le harnais mesure-t-il cet item et est-il arme ? (`armed_for("lighting-census")`, jamais
// `armed()` : un `armed()` global desarmerait le correctif d'un autre item.)
bool active();

// ── enregistrement des quatre portes, AU SITE DE POUSSEE ────────────────────────────────────
void gate_rt_light(int v);
void gate_pbr_mode(int v);
void gate_probe(int v);
void gate_shadow(int v);

// ── un draw monde vient de partir ───────────────────────────────────────────────────────────
void note_world_draw(Kind k);

// Phase de la course, posee par le jeu de references : 0 = libre, 1 = ORIGINE, 2 = RECHARGED.
// Permet de publier la repartition SEPAREMENT pour les deux references.
void set_phase(int phase);

// ── temps GPU par passe ─────────────────────────────────────────────────────────────────────
void pass_begin(const char* bucket_name);
void pass_end();

// Fin d'image : moissonne les requetes de temps, publie periodiquement.
void frame_end();

// Publie tout de suite (fin de course).
void publish();

}  // namespace lighting_census
