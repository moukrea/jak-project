#pragma once

// uncap — LE DEBRIDAGE DE LA CADENCE D'AFFICHAGE, ET LA MESURE QUI LE JUGE.
//
// LE DEFAUT (item `framerate-uncap`, owner 2026-09-05) : « on devrait pouvoir unlock le
// framerate, la ca lock a 60 max alors que ca pourrait ne pas etre cap si le pas de temps
// fixe est bien fait ! »
//
// CE QUI VERROUILLAIT A 60.
// -------------------------------------------------------------------------------------
// Le moteur n'avait qu'UN seul reglage de cadence, `Gfx::g_global_settings.target_fps`, et
// il servait a DEUX choses incompatibles :
//   1. la cible du LIMITEUR d'images (combien d'images on dessine par seconde) ;
//   2. la REFERENCE DE TEMPS de toute la logique — `*ticks-per-frame*` (video.gc:38 :
//      585900/target-fps), `seconds-per-frame`, `time-factor` (display.gc:88 : 300/target-fps),
//      donc `DISPLAY_FPS_RATIO`, et l'increment de l'horloge de scene de l'overlord
//      (srpc.cpp : 1024/target-fps par vblank).
// Monter ce reglage a 120 accelerait donc la LOGIQUE a 120 pas/s (le « high fps » amont, avec
// ses correctifs semes dans tout le moteur), et cassait l'horloge de scene : `(s32)(1024/120)`
// vaut 8, donc 960 unites par seconde reelle au lieu de 1024 — 93,75 %.
//
// CE QU'ON FAIT.
// -------------------------------------------------------------------------------------
// On SEPARE les deux. `target_fps` reste la REFERENCE DE TEMPS et ne bouge plus : elle vaut
// 60, donc la logique recoit toujours 60 ticks par seconde reelle, `video-mode` reste 'ntsc,
// `DISPLAY_FPS_RATIO` reste 1,0 et l'increment de scene reste celui de 60 Hz. Un NOUVEAU
// reglage, `Gfx::g_global_settings.display_fps_cap`, pilote le LIMITEUR seul. Les deux
// horloges d'image existantes (`fixed_tick` quand le pas fixe est arme, `render_pace` sinon)
// rendent deja k = 0 sur les images sans tick : au-dessus de 60 img/s elles dessinent des
// images de RENDU SEUL, interpolees par leur alpha. C'est exactement ce que l'owner suppose
// quand il ecrit « si le pas de temps fixe est bien fait ».
//
// CE QUE CE MODULE MESURE, ET POURQUOI CHAQUE CHIFFRE EXISTE.
// -------------------------------------------------------------------------------------
// `uncap_defects` est la SOMME de cinq verdicts. Chacun repond a une clause du livrable, et
// aucun ne peut etre vert en ne mesurant rien :
//
//   uncap_v_cap         LE PLAFOND A BIEN TRAVERSE. Le plafond que le limiteur a REELLEMENT
//                       recu doit depasser la reference de temps du moteur. C'est la panne
//                       silencieuse reelle : le reglage GOAL n'atteignait pas le C++ parce que
//                       la poussee de `update-to-os` etait gardee par `(!= 'fullscreen ...)`
//                       et qu'Android est TOUJOURS en 'fullscreen. Causal : le bras desarme de
//                       l'ablation fait retomber le plafond sur la reference, donc 1.
//
//                       CE VERDICT N'EST PAS « la cadence a depasse 60 ». Elle, on la PUBLIE
//                       (`uncap_regime_entered`, `uncap_over_windows`, `uncap_disp_fps_max_x100`)
//                       sans en faire un defaut : mesure du 2026-09-06, le Redmi Note 9 Pro
//                       plafonne a 46,26 img/s avec l'auto-echelle COLLEE a son plancher
//                       (`avg-fps=18.0 scale=40`) — il n'est pas limite par le remplissage, et
//                       aucun reglage ne le fera passer au-dessus de 60. En faire un defaut
//                       rendait la porte inatteignable sur le seul appareil autorise, quelle
//                       que soit la qualite du correctif. Un rapport qui lit `regime_entered=0`
//                       DOIT ecrire `non prouve` pour les clauses au-dessus de 60.
//   uncap_v_windows     ASSEZ DE MESURE. 1 si moins de 4 fenetres fermees.
//   uncap_v_tick_rate   « la logique recoit toujours 60 ticks par seconde reelle ». Ecart
//                       max, par fenetre de 5 s de temps mural ADMIS, entre ticks/60 et ce
//                       temps mural. Le temps ecrete par le plafond de rattrapage des deux
//                       horloges (k = 4) est RETIRE de la fenetre et COMPTE a part
//                       (`uncap_time_dropped_ms`) : sinon on mesurerait la lenteur de
//                       l'appareil, pas le debridage.
//   uncap_v_scene       « l'horloge des scenes ne derive pas ». Unites de l'horloge de scene
//                       de l'overlord par seconde REELLE, mesurees au vblank, contre 1024.
//   uncap_v_pose        « les animations restent lisses (meme mesure que anim-interp-low-fps) ».
//                       On NE FABRIQUE PAS un troisieme instrument : on lit la grandeur que
//                       l'horloge qui gouverne publie deja pour son propre item —
//                       `tick_pose_err_pct_x100` sous pas fixe, `anim_render_step_err_max_us`
//                       sous `render_pace`. Leur sentinelle « pas de mesure » (999999) compte
//                       comme un DEFAUT, jamais comme un vert.
//
// Le regime est EPINGLE et publie (`uncap_clock`, `uncap_target_fps_x100`, `uncap_cap_fps`) :
// deux machines qui n'ont pas la meme horloge armee ne rendent pas des chiffres comparables,
// et rien ne le disait.

#include "common/common_types.h"

namespace uncap {

// La cadence MAXIMALE que le limiteur d'images doit tenir, en images/s, telle qu'elle doit
// etre passee au limiteur. Ne rend JAMAIS 0 : « illimite » sort a kUnlimitedFps, une valeur
// finie assez haute pour qu'aucun limiteur ne morde, parce que les deux limiteurs traitent
// deja 0 comme « valeur absurde, retombe a 60 ».
// `engine_target_fps` est la reference moteur (`Gfx::g_global_settings.target_fps`) : c'est
// ce qui est rendu quand aucun plafond n'est configure, et c'est aussi ce que rend le bras
// DESARME de l'ablation — desarme, le debridage n'existe pas.
double cap_fps(double engine_target_fps);

// Une image vient d'etre produite. A appeler depuis `__send-gfx-dma-chain`, APRES
// `render_pace::on_render_frame` et `fixed_tick::on_render_frame` : on lit le k qu'elles
// viennent de choisir. Les deux plateformes ont leur propre corps pour ce symbole
// (game/kernel/common/kmachine.cpp cote bureau, android/gk_android_main.cpp cote arm64) :
// les DEUX doivent appeler, ou la plateforme oubliee mesure zero en silence.
void on_render_frame();

// ---------------------------------------------------------------------------------------
// ESSAI 2 — LES TROIS EXIGENCES QUE L'OWNER A AJOUTEES LE 2026-09-07.
// ---------------------------------------------------------------------------------------
// (a) LISTE DE CHOIX. « plutot qu'un slider faudrait des choix comme 30, 45, 60, 75, 90,
//     120, 240, Illimite ». La liste canonique vit ICI, en C++, et le menu GOAL en est le
//     REFLET (progress-pc.gc `*carousell-frame-rate*` + pckernel-common.gc
//     `*frame-rate-choices*`, meme ordre). GOAL pousse ce qu'il OFFRE — combien de choix et
//     lequel est courant (`set_menu_state`) —, et le verdict verifie que le plafond recu est
//     EXACTEMENT l'entree de la liste a cet index. Un curseur, qui ne pousse rien, rend
//     `choices_n = 0` : le defaut se voit sans avoir a regarder l'ecran.
//
// (b) `uncap_ceiling_hz` : LE PLAFOND REELLEMENT ATTEINT, et QUI le pose. L'owner mesure
//     90 img/s constant avec la consigne a 240. Trois grandeurs suffisent a nommer le
//     coupable, et aucune ne se deduit des deux autres :
//       `uncap_panel_hz`      le rafraichissement du panneau, tel que SDL le declare ;
//       `uncap_cap_fps_x100`  le plafond que le limiteur a recu ;
//       `uncap_ceiling_hz`    la cadence de PRESENTATION soutenue la plus haute, comptee sur
//                             les SWAPS (`note_present`) et pas sur la boucle EE — les deux
//                             ne sont 1:1 que dans le mode serialise d'android_gfx.
//     Ce qui plafonnait chez nous est nomme et retire : `SDL_GL_SetSwapInterval(1)` etait
//     appele UNE fois a l'initialisation du renderer Android et plus jamais, et
//     `Gfx::g_global_settings.vsync` n'etait relu par personne sur l'appareil (le seul
//     pousseur, pipelines/opengl.cpp, n'est pas dans android/CMakeLists.txt). Un swap en FIFO
//     sur un panneau 90 Hz rend 90 img/s quoi qu'on demande. `desired_swap_interval()` est
//     desormais LE seul endroit qui decide de cet intervalle, sur les deux plateformes.
//     Ce qui reste hors de notre code est PUBLIE, pas maquille : sur le Redmi le vote
//     `PRIORITY_USER_SETTING_PEAK_REFRESH_RATE` du DisplayManager borne SurfaceFlinger a
//     90 Hz et le panneau n'a qu'un mode 60 Hz.
//
// (c) LA CIBLE DE L'ECHELLE DE RENDU DYNAMIQUE SUIT LE PLAFOND. « aucun sens de pouvoir le
//     definir a 60FPS [...] alors qu'on a defini le max fps a 240 ». La borne haute de cette
//     rangee etait la constante 60 (`:param2 60.0`). Elle vient maintenant d'UNE fonction,
//     `dynscale-target-max` (pckernel-common.gc), qui lit le plafond choisi ; la meme
//     fonction alimente la borne de la rangee ET la valeur poussee ici. Le verdict compare
//     cette valeur au plafond recu : une borne restee a 60 avec un plafond a 240 est rouge.
//
// POURQUOI UN VERDICT DE PLUS N'EST PAS UN VERDICT DE PLAFOND. `uncap_v_ceiling` ne dit PAS
// « on a atteint 240 » — le Redmi ne depasse pas ~44 img/s et une porte qui l'exigerait
// serait inatteignable ici (voir le bloc des verdicts plus bas). Il dit « la cadence de
// presentation a ete MESUREE » : zero swap compte, c'est l'instrument qui est mort, et un
// instrument mort ne doit jamais se lire comme un zero defaut.

// LA LISTE CANONIQUE des choix de cadence, dans l'ordre du menu. La derniere entree est
// negative : c'est « Illimite ». GOAL tient la meme liste dans le meme ordre, et le verdict
// `uncap_v_choices` casse si les deux divergent.
int choice_count();
int choice_fps(int index);  // rend l'entree, negative pour « illimite » ; 0 hors bornes

// CE QUE LE MENU GOAL OFFRE, pousse par `update-to-os` (pc-set-uncap-menu) :
//   choices_n           combien de choix la rangee de cadence propose (8 attendu)
//   choice_index        lequel est courant
//   dynscale_target_max la borne HAUTE de la rangee « MIN TARGET FPS », en img/s
void set_menu_state(int choices_n, int choice_index, int dynscale_target_max);

// LA CONSIGNE DE MESURE, rendue a GOAL (pc-get-frame-rate-cap-override). 0 = aucune. Sans
// elle, le reglage GOAL reste celui que la machine a sauvegarde (60 sur le Redmi) et les
// clauses (a) et (c) seraient jugees dans un regime ou la constante fautive et la regle
// correcte donnent le MEME chiffre — vertes sans rien prouver.
int cap_override_fps();

// LE RAFRAICHISSEMENT DU PANNEAU, pose par la plateforme (android_gfx.cpp cote arm64,
// pipelines/opengl.cpp cote bureau). 0 = inconnu.
void set_panel_hz(int hz);

// L'INTERVALLE DE SWAP QUE LA PRESENTATION DOIT APPLIQUER, et le SEUL endroit qui en decide.
// 0 = pas d'attente du balayage (le plafond demande depasse le panneau, ou l'utilisateur a
// coupe la synchro), 1 = FIFO sur le balayage. A relire a chaque image : le plafond change
// depuis le menu pendant que le jeu tourne.
int desired_swap_interval();

// Ce que la presentation a REELLEMENT applique (retour de SDL_GL_SetSwapInterval).
void note_swap_interval_applied(int interval);

// Une image vient d'etre PRESENTEE (swap). A appeler au site du swap, pas dans la boucle EE :
// `uncap_ceiling_hz` est une cadence de presentation, et les deux ne coincident pas dans le
// mode `overlap` d'android_gfx.
void note_present();

// LE DIVISEUR DE L'HORLOGE DE SCENE : la cadence a laquelle le gestionnaire de VBlank de
// l'overlord est REELLEMENT appele. Ce n'est pas la meme grandeur sur les deux plateformes, et
// c'est l'autre moitie — non citee par l'item — de ce qui casse quand on debride :
//   * Android : un fil DEDIE bat la mesure a `target_fps`, decouple du rendu
//     (android/android_gfx.cpp, pacer Gd1). Le diviseur est donc `target_fps`.
//   * Bureau : `Gfx::vsync()` tire le vblank UNE FOIS PAR SWAP (game/graphics/gfx.cpp:145). Le
//     diviseur est donc la cadence d'AFFICHAGE, c'est-a-dire le plafond du limiteur. Garder
//     `target_fps` ici ferait avancer l'horloge de scene a 240/60 = QUATRE FOIS le temps reel
//     des qu'on debride a 240 img/s.
// Rien ici ne lit la montre : le debit reste une fonction du NOMBRE d'appels au gestionnaire,
// donc un rejeu deterministe le reste. La faiblesse qui subsiste sur BUREAU est celle d'avant
// cet item — l'horloge suit la cadence reellement obtenue, pas le temps mural — simplement
// referencee au plafond au lieu de 60.
double scene_vblank_hz(double engine_target_fps);

// Le VBlank de l'overlord vient de tirer et a ajoute `units_added` a l'horloge de scene
// (`gFakeVAGClock`). Appele depuis le fil IOP, donc n'ecrit que des atomiques.
// Appele a CHAQUE vblank, y compris quand aucune scene ne tourne : la grandeur jugee est le
// DEBIT de l'horloge (unites par seconde reelle), qui est le produit de l'increment que le
// code applique par la cadence reelle du vblank, et ce produit existe qu'une scene soit
// spoolee ou non.
void on_scene_vblank(s32 units_added);

}  // namespace uncap
