#pragma once

// lighting_census — RECENSEMENT DES CHEMINS D'OMBRAGE DU DECOR + TEMPS GPU PAR PASSE.
//
// POURQUOI. SPEC-refonte-lumiere.md §2.3 : le chemin qui ombre un fragment du decor depend de
// booleens d'uniforme, et il y a donc des composites exclusifs :
//
//     B · PBR fusionne  : u_rt_light_on != 0 && u_pbr_mode != 0
//     A · modulation    : u_rt_light_on != 0 && u_pbr_mode == 0
//     C · PBR autonome  : hote legacy && u_rt_light_on == 0 && u_pbr_mode != 0
//     E · relight legacy: sinon, hote legacy && u_pbr_shadow_on != 0
//
// Le composite D (« sondes ») a ete RETIRE le 2026-09-12 (census-false-reds) : sa porte n'est
// declaree par aucun shader et son enregistreur recevait un litteral, donc `light_census_D` etait
// un zero de CONSTRUCTION et non un compte. Voir l'en-tete de `lighting_census.cpp`.
//
// C/E existent seulement dans tfrag3.frag (TFRAG3 et TFRAG3_TESS). Les hotes contournent
// tous shade() quand gfx_hack_no_tex != 0 : ces draws sont non classes.
//
// Personne ne pouvait dire lequel avait dessine un pixel, donc aucun item de la refonte ne
// pouvait prouver qu'il n'avait rien casse. Ce module compte, PAR DRAW, dans quel chemin le
// draw est tombe, et publie la repartition par `autoport_proof`.
//
// AU SITE DE DECISION, PAS DEDUIT. Les valeurs sont enregistrees LA OU ELLES SONT POUSSEES
// (`glUniform1i`), c'est-a-dire exactement ce que l'objet programme contient quand le draw
// part. Les sites de poussee de `game/graphics/` :
//   u_pbr_shadow_on   background_common.cpp  (first_tfrag_draw_setup, pbr_shadow_bind_receiver)
//   u_rt_light_on     background_common.cpp  (first_tfrag_draw_setup)
// `u_pbr_mode` A QUITTE CETTE LISTE (lighting-legacy-purge, 2026-09-12) : la pile de matiere qui
// la poussait — `PbrDrawBinder::set` / `::finish` — a QUITTE L'ARBRE, et plus aucun shader ne la
// declare. Ses deux denominateurs etant tombes a zero, la porte n'aurait plus pu etre en
// desaccord avec quoi que ce soit.
//
// UNE OMBRE N'EST PAS UNE MESURE. Un miroir CPU de ce qu'on croit avoir pousse serait
// infalsifiable. Une fois par image, sur un draw dont l'indice tourne, le module RELIT les
// uniformes sur le programme reellement lie (`glGetUniformiv`) et compare. Les deux
// compteurs `light_census_rb_checks` / `light_census_rb_mismatch` sont publies cote a cote :
// un ecart non nul dit que le recensement ment, et ou.
//
// ET LA RELECTURE REND SES DENOMINATEURS. Une porte dont AUCUN programme lie ne declare
// l'uniforme ne peut pas etre en desaccord : son `light_census_rb_bad_<nom>` vaut 0 quoi qu'il
// arrive. `light_census_gate_progs_<nom>` (programmes ou le nom repond) et
// `light_census_gate_writes_<nom>` (appels de l'enregistreur) sont donc publies par porte, et
// `census_engine_dead_gates` compte celles dont aucun des deux canaux ne peut bouger.
//
// LE SEAU « NON CLASSE » EST DETAILLE. `hfrag.frag` ne declare AUCUN de ces uniformes ; les
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
  Hfrag,     // hfrag : le programme ne declare aucun de ces uniformes
  DepthOnly  // prepasse de profondeur / projecteur d'ombre : aucune couleur produite
};

// Le harnais mesure-t-il cet item et est-il arme ? (`armed_for("lighting-census")`, jamais
// `armed()` : un `armed()` global desarmerait le correctif d'un autre item.)
bool active();

// ── enregistrement des portes, AU SITE DE POUSSEE ───────────────────────────────────────────
void gate_rt_light(int v);
void gate_shadow(int v);

// Programme courant et bypass, enregistres par first_tfrag_draw_setup.
void host_paths(bool shade);
void gate_no_tex(int v);

// ── un draw monde vient de partir ───────────────────────────────────────────────────────────
void note_world_draw(Kind k);

// Phase de la course, posee par le jeu de references :
// 0 = libre, 1 = ORIGINE, 2 = RECHARGED, 3 = ORIGINE-LUMIERE.
// Permet de publier la repartition SEPAREMENT pour les trois references.
void set_phase(int phase);

// ── temps GPU par passe ─────────────────────────────────────────────────────────────────────
void pass_begin(const char* bucket_name);
// perf-instruments : meme chose, avec l'indice du bucket jak1 pour publier `gpu_ms_<id>_<nom>`
// bucket par bucket (en plus des passes). Le nom est celui de `name_and_id()`.
void pass_begin_bucket(int bucket_id, const char* name_and_id);
void pass_end();

// Fin d'image : moissonne les requetes de temps, publie periodiquement.
void frame_end();

// Diagnostic only: local snapshots allow a bucket to contain Merc snapshots.
// Enabled only by OG_REFSET_TRACE_ROI=1 during the first 24 capture frames.
// OG_REFSET_TRACE_ROI_RECT=x0,y0,x1,y1 selects inclusive 320x180 capture coordinates
// with top-left origin; defaults to 285,13,315,72. Only unsigned decimal integers
// separated by commas are accepted (no whitespace), with 0<=x0<=x1<320 and
// 0<=y0<=y1<180. Invalid values emit a diagnostic and disable ROI tracing.
// Both environment variables are read once, on the first roi_frame_begin().
// Counts use exact readback bytes per pixel: changed includes RGBA, rgb_changed
// excludes alpha, and alpha_only counts alpha changes with identical RGB bytes.
// rgb_bbox uses capture coordinates; RGB hashes exclude alpha. rgb_maxdiff is
// measured in native HDR float values or RGBA8 code values, not final PNG values.
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

// perf-stock-baseline : LE CUMUL DU BRACKET PLEINE-IMAGE, celui publie sous `gpu_ms_buckets`,
// et le nombre d'images chronometrees. SANS EFFET DE BORD : rien n'est remis a zero (d'autres
// modules lisent le meme cumul) et aucun verrou n'est pris. La campagne de ligne de base lit
// donc PAR DELTA entre deux instants. Faux — et rien n'est ecrit — quand le timer GPU n'est
// pas supporte (GLES sans EXT_disjoint_timer_query).
bool gpu_frame_totals(uint64_t* ns, uint64_t* frames);

// ── lighting-legacy-purge : la part SHADER de `lighting_legacy_sites` ───────────────────────
// Combien des noms d'uniformes de l'ancien monde repondent encore sur un programme REELLEMENT
// LIE (`glGetUniformLocation >= 0`), cumule sur la course. Zero = ces uniformes ne sont plus
// compiles dans ce binaire. Les trois autres fonctions sont les denominateurs sans lesquels ce
// zero ne serait pas falsifiable : le nombre de noms recenses, le nombre de programmes sondes,
// et le nombre de programmes ou un nom SURVIVANT de la refonte a repondu.
uint32_t legacy_uniform_sites();
uint32_t legacy_uniform_censused();
uint64_t legacy_uniform_programs();
uint64_t legacy_uniform_control();
// Combien de programmes LIES lisent encore l'ambiante SH directionnelle (`u_rt_sh[0]`). Un
// uniforme declare mais jamais LU est RETIRE par le compilateur GLSL : ce compte est la seule
// grandeur qui distingue « la feature validee par l'owner a survecu a la purge » de « ses deux
// seuls appelants sont partis avec la pile de matiere et personne ne l'a vu ». Zero est un SITE
// de l'ancien monde au sens de la porte (kmachine.cpp), pas un silence.
uint64_t sh_reader_programs();

// Publie tout de suite (fin de course).
void publish();

}  // namespace lighting_census
