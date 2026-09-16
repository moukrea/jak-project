#pragma once

// grass_baseline — LE COUT REEL DE L'HERBE, MESURE AVANT QU'ON Y TOUCHE.
//
// POURQUOI CE FICHIER EXISTE. L'item `grass-baseline-cost` exige une ligne de base chiffree avant
// toute optimisation de la campagne `grass-*`. Le SEUL chiffre dont on disposait vient d'un
// rapport de plantage d'aout — herbe ON 4,6 a 6,0 img/s contre OFF 20,0 a 21,1 sur le Redmi, un
// facteur 3,5 pour 726 851 instances — et ce rapport le dit lui-meme : « ce cout existait avant,
// il etait simplement invisible parce que le jeu mourait d'abord ». Aucune mesure fine n'existe :
// ni par palier, ni decomposee entre preparation et dessin, ni comparee au nombre d'instances
// reellement dans le champ de vision.
//
// « NE CHANGE RIEN » N'INTERDIT PAS D'INSTRUMENTER. Cinq essais (2 a 6) ont lu la clause hors
// perimetre de l'item comme une interdiction d'ajouter les compteurs, et ont attendu une
// autorisation que personne n'avait a donner. Un compteur qui n'ecrit aucun pixel n'est pas un
// changement de rendu : ce module n'optimise rien, ne regle rien, ne touche aucun shader. Il
// MESURE, et il ne tourne QUE lorsque le harnais nomme cet item.
//
// CE QU'IL PRODUIT, dix cellules (cinq paliers x herbe ALLUMEE/ETEINTE), un seul vantage
// (`training-start`), un seul binaire, a in {on,off}, p in {very_low,low,medium,high,very_high} :
//   grass_<a>_<p>_fps / _frames / _frame_ms_p50 / _frame_ms_p95   la cadence et son denominateur
//   grass_<a>_<p>_render_frames                                   images ou GrassRenderer a tourne
//   grass_<a>_<p>_actors_active / _loadcover_frames               le regime de la cellule
//   grass_on_<p>_prep_us / _fence_us / _submit_us                 la decomposition cote processeur
//   grass_on_<p>_submitted_blade / _submitted_card                instances SOUMISES au dessin
//   grass_on_<p>_frustum_in / _lod / _tested / _behind             instances DANS LE CHAMP DE VISION
//   grass_load_<p>_total_ms / _source_ms / _expand_ms / _upload_ms   le chargement, decompose
//   grass_load_<p>_blocked_ms / _async / _waits                    ce que le fil de rendu a PAYE
//   grass_load_<p>_instances / _drawn / _dead                      construites, dessinees, mortes
//   grass_load_<p>_inst_bytes / _light_bytes                       la memoire des DEUX tampons
//   grass_on_<p>_cam_dm                                           la camera du recensement, en dm
//   grass_baseline_dead_instances                                  la queue morte, seule sur sa ligne
//   grass_baseline_regime_read                                     cellules dont le REGIME a ete relu
//   grass_baseline_vantage_spread_mm / _vantage_cells              « au MEME vantage » : Jak
//   grass_baseline_camera_spread_dm  / _camera_cells               « au MEME vantage » : la camera
//   grass_baseline_gaps                                            ce qui MANQUE, et c'est la porte
//
// « AU MEME VANTAGE » EST UN TERME, PAS UNE AFFIRMATION. Les deux positions sont relues dans la
// table moissonnee et leur ECART est publie en grandeur (mm pour Jak, dm pour la camera), a cote
// du nombre de cellules effectivement comparees. Un ecart qui depasse le seuil compte comme un
// manque et se NOMME ; moins de deux cellules comparables aussi, sinon la porte serait verte par
// inaction. Sans ces deux termes, dix cellules prises sous dix points de vue passaient vertes.
//
// `grass_baseline_gaps` SE CALCULE EN RELISANT `autoport_proof::has_key`, jamais une variable
// interne (patron de `perf_baseline`) : la table qui sera moissonnee fait foi, et une cle refusee
// en silence — caractere illegal, valeur avec un blanc — doit se voir. Un zero se lit « tout est
// mesure », jamais « rien a mesurer » : une cellule dont la fenetre n'a pas atteint 300 images
// compte comme un manque, parce que le contrat le dit (« un releve de moins de 300 images ne
// compte pas »).
//
// LA CELLULE ETEINTE N'EST PAS UN ZERO SUPPOSE. Quand l'herbe est eteinte, `OpenGLRenderer` ne
// prend meme pas la branche du seau 31 : `GrassRenderer::render` n'est jamais appele, et le
// compteur `render_frames` le DIT (0 la, ~300 dans la cellule allumee du meme palier, avec le
// meme instrument). Sans ce compteur, « l'herbe ne coutait rien » et « l'instrument ne tournait
// pas » rendraient la meme ligne.
//
// ARMEMENT. Rien ne tourne sauf si le harnais nomme cet item (`AUTOPORT_FEATURE` /
// `debug.opengoal.feature`). `armed_for("grass-baseline-cost")` desarme tout : le bras `--off`
// de `proof_run.sh` rend donc `armed=0 hits=0` dans la MEME scene. Le binaire de l'owner, qui ne
// porte aucune de ces deux proprietes, ne change pas de comportement — il n'y a pas de reglage
// optionnel qui allumerait la campagne par accident.
//
// LES DEUX ECRITURES, ET POURQUOI ELLES SONT AU POINT DE PRODUCTION. GOAL repousse
// `recharged-grass?` et `recharged-grass-density-preset` A CHAQUE IMAGE (hud-classes-pc.gc:1798
// et :1847). Une campagne qui ecrirait `Gfx::g_global_settings` depuis le fil GL se ferait
// ecraser une image sur deux, et les cellules porteraient le regime de l'autre. Les deux
// surcharges vivent donc dans les ponts qui RECOIVENT la poussee GOAL — `pc_set_recharged_grass`
// et `pc_set_grass_dists` — ou le reglage de la campagne remplace celui du joueur avant d'entrer
// dans le moteur. Hors campagne, les deux fonctions rendent faux et rien n'est touche.
//
// FILS. `note_drawn_frame` tourne sur le fil GL et fait avancer la machine a etats ; les `note_*`
// du renderer aussi. `grass_on_override` / `preset_override` tournent sur le fil GOAL. Tout ce
// qui traverse est atomique.

#include <cstdint>

namespace grass_baseline {

// Vrai quand la campagne tourne (voir ARMEMENT). Lisible depuis n'importe quel fil.
bool enabled();

// ── fil GOAL ────────────────────────────────────────────────────────────────────────────────
// La campagne impose-t-elle l'etat de l'herbe ? Vrai => `*on` est remplace par le sien.
bool grass_on_override(bool* on);
// La campagne impose-t-elle le palier de densite ? Vrai => `*preset` est remplace par le sien.
bool preset_override(int* preset);

// ── fil GL, depuis GrassRenderer ────────────────────────────────────────────────────────────
// `GrassRenderer::render` vient d'etre appele pour cette image (compte le denominateur qui
// separe « l'herbe ne coute rien » de « l'instrument n'a pas tourne »).
void note_render_entry();

// Preparation processeur de cette image : de l'entree de `render()` jusqu'a l'attente de la
// barriere, en microsecondes.
void note_prepare_us(double us);

// Le dessin de cette image, en trois grandeurs SEPAREES, parce qu'elles nomment trois causes
// differentes : `fence_us` est l'attente de la barriere posee a l'image PRECEDENTE (la
// contre-pression GPU que le correctif Adreno 618 a rendue explicite), `submit_us` le temps
// processeur des deux `glDrawArraysInstanced`, et les deux comptes sont les instances REELLEMENT
// passees a ces appels.
void note_draw(double fence_us, double submit_us, uint64_t blade_instances,
               uint64_t card_instances);

// La campagne attend-elle le recensement du champ de vision pour cette image ? Vrai au plus
// quelques images par cellule, JAMAIS pendant la fenetre de mesure : un balayage des 726 851
// instances entrerait dans le temps de preparation qu'on mesure.
bool want_frustum_census();

// Le recensement du champ de vision : instances dont la base tombe dans le volume de vue,
// celles qui y tombent ET restent dans la portee des niveaux de detail, le denominateur
// reellement teste, et celles que la transformation place DERRIERE la camera.
//
// `behind` N'EST PAS DU DECOR. C'est le seul temoin qui rend la convention de signe du chemin
// PS2 falsifiable : la projection de `grass.vert` n'est pas une mat4 standard, et un test de
// frustum ecrit a l'envers publierait `in_frustum` proche de zero sans qu'aucune autre grandeur
// ne proteste. Avec lui, « la camera regarde ailleurs » et « le test est inverse » ne rendent
// plus la meme ligne.
void note_frustum(uint64_t in_frustum, uint64_t in_frustum_lod, uint64_t tested,
                  uint64_t behind);

// LA CAMERA DU RECENSEMENT, relevee dans la MEME image que lui. La position de Jak (publiee pour
// les dix cellules) dit que le joueur n'a pas bouge ; elle ne dit RIEN de l'orientation, et c'est
// l'orientation qui decide du compte dans le champ de vision. Sans ce temoin, deux cellules au
// meme `jak_pos` pourraient rendre deux `frustum_in` differents sans que rien ne nomme la cause.
void note_camera(float x, float y, float z);

// Un champ d'herbe vient d'etre construit : le chargement decompose comme la ligne PLACE-TIME le
// fait deja, plus la memoire des deux tampons et la queue construite-jamais-dessinee.
// `blocked_ms`, `async` et `waits` ne sont pas du decor : sur le chemin ASYNCHRONE — celui qui
// est LIVRE (`grass_async_expand_enabled()` rend vrai par defaut) — `expand_ms` est un delai
// MURAL qui couvre plusieurs images, pas un cout processeur. `blocked_ms` est le temps
// reellement paye SUR LE FIL DE RENDU. Publier l'un sans l'autre ferait lire un delai comme une
// charge.
// `preset` est le palier REELLEMENT SERVI, pas celui qu'on a demande : quand le `.grassbake` du
// palier demande manque, `rebuild()` retombe d'un cran, et publier la decomposition sous le nom
// demande decrirait un champ qui n'a jamais ete charge. `requested` est publie a cote pour que le
// repli se NOMME au lieu de disparaitre — et la cellule du palier non servi restera sans cles,
// donc comptee dans `grass_baseline_gaps`.
void note_load(int preset,
               int requested,
               double total_ms,
               double source_ms,
               double expand_ms,
               double upload_ms,
               double blocked_ms,
               bool async,
               uint64_t waits,
               uint64_t instances,
               uint64_t drawn_instances,
               uint64_t inst_bytes,
               uint64_t light_bytes);

// ── fil GL, une fois par image DESSINEE ─────────────────────────────────────────────────────
// Fait avancer la machine a etats. `gl_cpu_ms` est le temps processeur du fil graphique pour
// cette image (hors attente de synchro verticale).
void note_drawn_frame(double gl_cpu_ms);

}  // namespace grass_baseline
