#pragma once

// lighting_census — RECENSEMENT DES CINQ CHEMINS D'OMBRAGE DU DECOR + TEMPS GPU PAR PASSE.
//
// POURQUOI. SPEC-refonte-lumiere.md §2.3 : le chemin qui ombre un fragment du decor depend de
// QUATRE booleens d'uniforme, et il y a donc cinq composites exclusifs :
//
//     B · PBR fusionne  : u_rt_light_on != 0 && u_pbr_mode != 0
//     A · modulation    : u_rt_light_on != 0 && u_pbr_mode == 0 && u_rt_probe_on == 0
//     D · sondes        : u_rt_light_on != 0 && u_rt_probe_on != 0        (annonce MORT)
//     C · PBR autonome  : hote legacy && u_rt_light_on == 0 && u_pbr_mode != 0
//     E · relight legacy: sinon, hote legacy && u_pbr_shadow_on != 0
//
// C/E existent seulement dans tfrag3.frag (TFRAG3 et TFRAG3_TESS). Les hotes contournent
// tous shade() quand gfx_hack_no_tex != 0 : ces draws sont non classes.
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
// passes de profondeur et de projecteur d'ombre ne portent pas de couleur ; et un draw sans
// branche applicable a son hote, ou qui contourne shade(), reste hors des chemins de la refonte.
// Les trois seaux sont comptes separement — un seau « exclu » n'est pas un seau « correct ».
//
// TEMPS GPU. Aucun timer GPU n'existait dans cet arbre (seulement du temps CPU mur dans
// Profiler.h). Ici : une paire `glQueryCounter(GL_TIMESTAMP)` autour de chaque bucket, moissonnee
// trois images plus tard pour ne jamais bloquer le pipeline, sommee par passe. Quand
// `glQueryCounter` est absent (GLES sans EXT_disjoint_timer_query), RIEN n'est publie et
// `gpu_timer_supported=0` le dit : une cle sans site d'ecriture est une fausse constante.

#include <cstdint>
#include <vector>

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

// Programme courant et bypass, enregistres par first_tfrag_draw_setup.
void host_paths(bool shade, bool legacy);
void gate_no_tex(int v);

// ── un draw monde vient de partir ───────────────────────────────────────────────────────────
void note_world_draw(Kind k);

// Phase de la course, posee par le jeu de references :
// 0 = libre, 1 = ORIGINE, 2 = RECHARGED, 3 = ORIGINE-LUMIERE.
// Permet de publier la repartition SEPAREMENT pour les trois references.
void set_phase(int phase);

// ── temps GPU par passe ─────────────────────────────────────────────────────────────────────
void pass_begin(const char* bucket_name);
void pass_end();

// Fin d'image : moissonne les requetes de temps, publie periodiquement.
void frame_end();

// Diagnostic only: local snapshots allow a bucket to contain Merc snapshots.
// Enabled only by OG_REFSET_TRACE_ROI=1 during the first 24 capture frames.
struct RoiSnapshot {
  int framebuffer = 0;
  int width = 0, height = 0;
  int viewport[4] = {};
  int x = 0, y = 0, w = 0, h = 0;
  int bytes_per_pixel = 4;
  std::vector<uint8_t> rgba;
};
void roi_frame_begin();
bool roi_active();
RoiSnapshot roi_before();
void roi_after(const RoiSnapshot& before, const char* type, int id, const char* name,
               uint64_t hash = 0, uint32_t first_index = 0, int texture = -1);
void roi_model(uint64_t hash, const char* name);

// Publie tout de suite (fin de course).
void publish();

}  // namespace lighting_census
