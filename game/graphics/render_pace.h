#pragma once

// render_pace — L'HORLOGE DE CADENCE DE RENDU, ET L'ALPHA QUI VA AVEC.
//
// LE DEFAUT (item `anim-interp-low-fps`, owner 2026-09-01 et 2026-09-03 : « très
// jittery quelque soit le framerate, 60 FPS comme 15 fps comme 45 »).
// ---------------------------------------------------------------------------------
// Le pas de simulation d'une image dessinee est un ENTIER de ticks de 1/60 s :
// `display-frame-start` (goal_src/jak1/engine/draw/drawable.gc:1057) calcule
//     time-ratio = (timer-count / *ticks-per-frame*) + 1     [division ENTIERE]
// puis toute la simulation — `frame-num` des animations
// (process-drawable-h.gc:34-38), `seconds-per-frame` de la physique
// (display.gc:70) — est multipliee par ce k. L'affichage, lui, avance de la duree
// REELLE de l'image. Des que cette duree n'est pas un multiple exact du budget, la
// pose DESSINEE ne se trouve pas au bon instant, et l'erreur change de signe d'une
// image a l'autre : c'est la gigue, et elle existe a TOUTES les cadences qui ne sont
// pas un diviseur exact de la cadence cible.
//
// Deux defauts distincts se cumulaient :
//   1. Le choix de k ne suivait AUCUN reste. `floor(dt/budget)+1` arrondit vers le
//      haut a chaque image : a cadence irreguliere le temps de jeu part en avance sur
//      le temps reel sans jamais se recaler.
//   2. Sur bureau il n'y avait AUCUNE interpolation de rendu : `pc_camera_interp_alpha`
//      rendait 1e6 en dur (game/kernel/common/kmachine.cpp), donc `*anim-interp-alpha*`
//      valait 1,0 et `joint-channel-render-frame` sortait en identite a chaque appel.
//      La machinerie de retimage existait et ne tirait jamais.
//   Et sur Android l'alpha valait `(deficit - 0,5)/k` : le `- 0,5` est un retard
//   constant DIVISE PAR k, donc il ALTERNE des que k alterne — il FABRIQUAIT de la
//   gigue au lieu de l'enlever, et il interdisait `alpha == 1,0` a 60 img/s verrouillees.
//
// CE QUE FAIT CE MODULE.
// ---------------------------------------------------------------------------------
// Une horloge a reste borne, une seule, partagee bureau/Android :
//
//     deficit += inc                      inc = duree reelle de l'image, en ticks
//     k        = ceil(deficit - eps)      borne a [1, 4]
//     alpha    = deficit / k              borne a [0, 1]
//     deficit -= k
//
// et la valeur rendue par `__read-ee-timer` est une horloge VIRTUELLE avancee de
// (k - 0,5) budgets, de sorte que la formule `floor(tc/budget)+1` de GOAL retombe
// EXACTEMENT sur le k qu'on a choisi. GOAL n'est pas modifie : c'est son entree qui
// devient coherente.
//
// L'IDENTITE QUI JUSTIFIE LA FORMULE. Si `E(n)` est le temps de jeu cumule en ticks et
// `alpha` le facteur lu par les retimeurs, la pose DESSINEE vaut
//     P(n) = E(n) - (1 - alpha(n)) * k(n)
// et on veut P(n) = D(n), le temps REEL cumule. Comme deficit(n) = D(n) - E(n-1) :
//     alpha(n) = deficit(n) / k(n)                     — sans le `- 0,5` d'Android.
// Le `ceil` (et non le `round` d'Android) garantit deficit <= k, donc alpha <= 1 :
// on interpole toujours ENTRE deux etats simules, jamais au-dela.
//
// 60 IMG/S IDENTIQUE AU BIT. A cadence verrouillee, `inc` vaut 1,000 a la mesure pres.
// Un instant sur la grille (a kGridTol pres) est DECLARE sur la grille : deficit reste
// exactement 1,0, k vaut 1, alpha vaut exactement 1,0 — et `joint-channel-render-frame`
// comme `cam-render-interp!` sortent en identite. Rien n'est interpole, la sortie ne
// bouge pas d'un bit. Le reste n'est PAS remis a zero (l'erreur de la phase precedente :
// detruire le reste retranche jusqu'a un tick entier de l'avance dessinee) ; seule la
// MESURE de l'image est arrondie, de 0,02 tick au plus, et cet arrondi est COMPTE
// (`anim_pace_grid_snaps`) et reste visible dans l'erreur publiee.
//
// LA MESURE. `anim_render_step_err_max_us` est le plus grand ecart, sur une image, entre
// l'avance de la pose DESSINEE et le temps reel ecoule. Elle est calculee avec l'alpha
// REELLEMENT CONSOMME : si `*anim-interp-n*` n'a pas bouge pendant l'image, c'est que
// personne n'a retime, et la mesure prend alpha = 1,0. Une correction poussee mais non lue
// ne peut donc pas rendre un chiffre vert.

#include "common/common_types.h"

namespace render_pace {

// Vrai quand le module gouverne la cadence. Faux sous l'ablation du harnais
// (`AUTOPORT_FEATURE=anim-interp-low-fps` + `..._ARMED=0`) et quand l'horloge a pas fixe
// est armee (elle a sa propre horloge ; deux horloges qui se disputent la meme image ne
// mesurent rien).
bool armed();

// Une image vient d'etre produite. Appele UNE fois par image dessinee, sur le fil GOAL/EE,
// depuis `send_gfx_dma_chain` (bureau) et `a35_send_gfx_dma_chain` (Android).
// `anim_interp_n` est la valeur courante du symbole GOAL `*anim-interp-n*` : le nombre
// cumule de canaux d'animation REELLEMENT retimes. C'est le point de LECTURE.
void on_render_frame(u64 anim_interp_n);

// La valeur que `__read-ee-timer` doit rendre : horloge virtuelle quand le module est arme,
// horloge murale sinon.
u64 ee_timer();

// Alpha sous-image en micro-unites, [0, 1000000]. 1000000 == pose courante == pas
// d'interpolation.
s32 alpha_micro();

// Vrai quand l'image qui vient d'etre preparee ne porte AUCUN tick de logique (affichage plus
// rapide que la cadence cible). Publie vers GOAL par `fixed_tick_publish` sous le nom
// `*render-pace-skip*` ; `display-frame-start` y met `time-ratio` a 0.
bool skip();

// Le k (nombre de ticks de logique) et le reste d'AVANT emission de la derniere image. Ne
// servent qu'aux sondes de diagnostic deja en place ; aucune porte ne les lit.
double last_k();
double last_deficit();

// ---------------------------------------------------------------------------------------
// BALAYAGE DE CADENCE D'AFFICHAGE — LE STIMULUS DE MESURE, ET RIEN D'AUTRE.
// ---------------------------------------------------------------------------------------
// Le defaut de l'owner (2026-09-05) est nomme : « à 30 ça roule nickel, à 60 pareil [...]
// mais sur des framerates autres qu'aux alentours de 30 et 60 ça jitter ». 30 et 60 sont
// exactement les cadences ou les 60 ticks/s de la logique tombent en compte ENTIER par image.
// Mesurer ce defaut demande donc de tenir l'affichage a 45, 50, 75, 90 — des cadences que le
// jeu n'atteint pas tout seul et que NI le bureau NI l'appareil ne savaient imposer :
// `frame_limit_override` vivait dans `game/graphics/pipelines/opengl.cpp`, qui n'est PAS
// compile dans `libgk.so` (android/CMakeLists.txt ne le liste pas). L'item est passe en
// `device: true` : sans ce module, la course appareil ne pouvait exercer aucune des cadences
// que la porte nomme.
//
// `stimulus_fps` deplace la cible du LIMITEUR seul. `Gfx::g_global_settings.target_fps`, donc
// `*ticks-per-frame*` et le budget de `render_pace`, n'est PAS touche : c'est precisement
// l'ecart entre cadence AFFICHEE et cadence CIBLE qui fabrique le defaut.
//
// Consigne : `OG_FRAME_LIMIT_FPS=<f1[,f2,...]>[@<secondes>]` (bureau, environnement) ou
// `debug.opengoal.frame.limit` (appareil, propriete). Absente => rend `target` tel quel, cout
// nul : le binaire de l'owner passe par ici a chaque image et ne change pas de comportement.
//
// LE BALAYAGE NE DEMARRE QU'APRES L'AMORCAGE (kSweepStartFrames images dessinees). Sans cela
// le premier segment tombe dans le chargement du niveau, ou aucun acteur n'anime : la cadence
// serait exercee mais la mesure vide, et une mesure vide se lit comme un zero, c'est-a-dire
// comme un vert.
double stimulus_fps(double target);

// Index du segment courant du balayage (0..n-1), -1 quand aucun balayage n'est demande ou
// qu'il n'a pas encore demarre. Lu depuis un autre fil que celui qui l'ecrit sur bureau.
int stimulus_segment();

// Cadence NOMINALE du segment courant, en images/s. 0 si aucun balayage.
double stimulus_segment_fps();

// Un `SwapWindow` vient d'avoir lieu (fil GL, Android). Sert a UN SEUL recoupement : la
// cadence REELLEMENT AFFICHEE est-elle celle de la boucle EE que `on_render_frame` mesure ?
// Une phase precedente l'a affirme en commentaire (android_gfx.cpp, « present dt == EE dt ») ;
// une affirmation n'est pas une trace, et si les deux divergeaient, tout ce module mesurerait
// une horloge que l'oeil ne voit pas. No-op quand personne n'appelle (bureau).
void note_present();

}  // namespace render_pace
