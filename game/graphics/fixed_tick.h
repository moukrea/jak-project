#pragma once

// Gfixed-tick-interpolation (owner 2026-08-26) — HORLOGE A PAS FIXE + ALPHA D'INTERPOLATION
// DE RENDU.
//
// Ce que le moteur faisait AVANT ce module, et pourquoi ca casse le gameplay :
// la logique avance de `seconds-per-frame = time-ratio / target-fps` secondes par image
// DESSINEE, ou `time-ratio` est un ENTIER derive de la duree reelle de la frame
// (engine/draw/drawable.gc, `display-frame-start`). Le pas de simulation suit donc la
// cadence d'affichage : 1/60 s a 60 fps, 1/25 s a 25 fps, 1/120 s a 120 fps. Un moteur
// concu pour le pas FIXE de la PS2 (1/60 s) ne conserve alors ni les trajectoires
// balistiques ni les seuils d'etat comptes en frames — c'est ce que l'owner decrit :
// « les sauts, les mouvements de camera ça chie un peu dans la colle », sauts trop
// courts, skips, judder de camera (deja documente, game/kernel/jak1/kmachine.cpp).
//
// Ce module remplace ce calcul par un ACCUMULATEUR : le temps reel ecoule est
// accumule, et on en extrait un nombre ENTIER de pas de 1/60 s exactement
// (`kFixedTickSeconds`). Le reste fractionnaire est CONSERVE d'une frame a l'autre —
// c'est ce report qui empeche la derive que l'arrondi entier fabriquait (a 25 fps
// l'ancien calcul rendait 3 pas de 1/60 s pour 40 ms reelles, soit +25 % de temps de
// jeu par seconde reelle).
//
// Le moteur execute ensuite ces N pas comme N TICKS DE LOGIQUE SEPARES (rattrapage,
// cote GOAL dans `display-loop`), au lieu d'un seul pas de N/60 s : c'est ce qui rend
// la trajectoire d'un saut IDENTIQUE a celle de 60 fps.
//
// PERIMETRE DE CETTE ETAPE, DECLARE : l'horloge ne s'arme que si la cadence
// d'affichage est <= 60 Hz. Au-dessus (75/90/120), un pas de 1/60 s n'est pas du
// EVERY frame — il faudrait dessiner des images SANS tick, ce qui suppose de decoupler
// le rendu de la construction de la chaine DMA (le moteur la reconstruit a chaque
// image). Tant que ce decouplage n'est pas fait, l'horloge se DESARME au-dessus de
// 60 Hz et le moteur garde exactement son chemin actuel. C'est l'etape 2, et le
// rapport le dit au lieu de faire semblant.
//
// ALPHA D'INTERPOLATION DE RENDU. Meme avec des ticks fixes, l'image dessinee montre
// l'etat du DERNIER tick alors que le temps reel est deja `acc` secondes plus loin :
// l'erreur temporelle varie d'une image a l'autre, et c'est exactement ce qui se voit
// comme un judder de camera. `render_alpha_micro()` publie ou se situe le temps reel
// entre le tick precedent et le tick courant ; la camera est retimee dessus (slerp de
// la rotation, lerp de la position) par `cam-render-interp!` cote GOAL.
//
// CONVENTION D'ALPHA (celle que `cam-render-interp!` consomme deja) :
//   1.0 == « pose courante », donc AUCUNE interpolation.
//   a in [0,1) == pose interpolee entre le tick precedent (a=0) et le tick courant.
// A cadence VERROUILLEE (60 Hz vsync : chaque frame vaut exactement un tick, le reste
// accumule est nul), on publie 1.0 : la sortie est alors identique au bit a celle
// d'avant ce module. C'est la non-regression a 60 fps, obtenue PAR CONSTRUCTION et
// pas par un reglage.

#include "common/common_types.h"

namespace fixed_tick {

// Le pas de la PS2. Toute la logique de jeu avance par multiples ENTIERS de celui-ci.
constexpr double kFixedTickSeconds = 1.0 / 60.0;

// Plafond de rattrapage par image dessinee (anti spirale de la mort). 4 reprend le
// plafond que le moteur s'impose deja lui-meme (`set-time-ratios`, fmin 4.0).
constexpr int kMaxCatchupTicks = 4;

// Gfixed-tick-anim-interp-2 — L'ACCROCHAGE PAR IMAGE EST REMPLACE PAR UN VERROU DE
// CADENCE HYSTERETIQUE, ET C'EST LE CORRECTIF DE CETTE PHASE.
//
// CE QUI ETAIT FAUX. L'accrochage decidait IMAGE PAR IMAGE : toute image dont la duree
// tombait a moins de 0,10 tick d'un entier etait ramenee dessus ET l'accumulateur etait
// REMIS A ZERO. Sur un panneau verrouille (60,0 Hz) ca ne se voit pas : le reste vaut
// deja zero. Chez l'owner, qui joue vers 20 images/s avec une duree d'image VARIABLE,
// une image sur deux tombait dans la bande et l'autre non — donc le reste sous-tick
// etait fabrique puis DETRUIT en alternance.
//
// Or l'avance de la pose DESSINEE entre deux images vaut exactement
//     k + alpha(n) - alpha(n-1)   ticks,
// c'est-a-dire dt/tick, donc le TEMPS REEL ECOULE... sauf sur une image accrochee, ou
// le reste detruit `r` est retranche. Une image accrochee avance donc de (dt - r), avec
// r pouvant valoir jusqu'a UN TICK ENTIER. Banc hors-ligne, 3000 images a 20 images/s
// avec 12 % de variation de duree d'image (mesure sur la seule horloge, sans le jeu) :
//     accrochage livre : avance de pose min 1,82 max 4,00 tick — amplitude 76 % ;
//     verrou hysteretique : min 2,82 max 3,18 — amplitude 12 %, soit EXACTEMENT la
//     variation reelle de la duree d'image, et rien de plus.
// C'est ca, « c'est jittery PLUS QUE LE FRAMERATE » : l'horloge FABRIQUAIT de la gigue.
//
// CE QUI REMPLACE. Deux regimes, et on ne passe de l'un a l'autre que sur une preuve de
// STABILITE, jamais image par image :
//   - VERROUILLE : la cadence est un multiple entier constant du tick (panneau 60 Hz,
//     limiteur a 30 ou 20 images/s). On declare l'image comme valant exactement N ticks,
//     le reste est nul et alpha vaut 1,0 — c'est le comportement d'avant, au bit pres ;
//   - LIBRE : tout le reste. L'accumulateur n'est JAMAIS remis a zero, alpha vaut
//     acc/tick, et l'avance de pose suit le temps reel a la precision de la montre.
constexpr double kLockTolerance = 0.05;   // ecart max a un entier de ticks, en ticks
constexpr int kLockFrames = 12;           // images consecutives sur la grille avant verrou
constexpr int kUnlockBadFrames = 3;       // images consecutives hors grille avant sortie
constexpr double kPhaseSlew = 0.02;       // glissement de phase max par image, en ticks

// Tolerance de l'ACCROCHAGE LIVRE, conservee UNIQUEMENT pour le bras d'ablation
// `OG_TICK_LOCK=0` : c'est la valeur exacte du build que l'owner a teste.
constexpr double kSnapLegacyTolerance = 0.10;

// essai 3 (2026-09-05) — REFERENCE D'ALPHA UNIFIEE, ET POURQUOI IL EN FALLAIT UNE.
//
// LE DEFAUT. L'essai 2 a conditionne la SUBSTITUTION de la duree a la CONFORMITE de
// l'image (`lock_hit`), mais l'alpha restait decide par l'ETAT (`if (s.locked)
// alpha = 1.0`). Les deux se contredisent exactement sur les images que l'essai 2 a
// carrees : les `kUnlockBadFrames - 1` images HORS grille qui ne font pas encore sortir
// du verrou. Sur celles-la la duree reelle passe entiere dans l'accumulateur (correct)
// et l'alpha est quand meme epingle a 1,0 — donc l'avance de la pose DESSINEE vaut
//     k + alpha(n) - alpha(n-1) = k + 0
// alors que le temps reel a avance de `dt/tick`. L'ecart, jusqu'a un tick entier, est un
// SKIP de la pose, et aucune grandeur publiee ne le voyait : `tick_conserve_err` juge la
// conservation du TEMPS, jamais la position de la POSE. Un vert de plus sur un defaut que
// l'owner voit encore.
//
// LA CAUSE DE FOND. Les deux regimes n'avaient pas la meme REFERENCE. L'extraction par
// plancher (`while (acc >= tick) acc -= tick`) laisse `acc` dans [0, tick) : le dernier
// tick simule est TOUJOURS en retard sur le temps reel, donc la pose ne peut jamais
// l'atteindre — alpha = acc/tick la place un tick entier en arriere (latence constante,
// invisible), tandis que le regime verrouille (alpha = 1,0) la place PILE dessus. Deux
// latences differentes : toute image qui passe de l'une a l'autre deplace la pose d'un
// tick, et c'est pour ca qu'il fallait un glissement de phase a l'entree et un rebase a
// la sortie — deux fabrications de temps de jeu (78 ms sur 173 s a l'essai 2).
//
// CE QUI REMPLACE. Extraction par PLAFOND, sur un reste SIGNE :
//     acc += dt ; k = ceil(acc/tick - kAlphaCeilTol) borne a [0, kMaxCatchupTicks]
//     acc -= k * tick                      // acc vit dans (-tick, kAlphaCeilTol*tick]
//     alpha = 1 + acc/tick                 // dans (0, 1], JAMAIS borne en pratique
// La simulation n'est plus jamais en retard sur le temps reel, la pose est dessinee PILE
// a l'instant reel dans LES DEUX regimes, et l'identite
//     avance de pose = k + alpha(n) - alpha(n-1) = dt/tick
// devient exacte sans aucun cas particulier. A cadence verrouillee `acc` vaut exactement
// zero, donc alpha vaut exactement 1,0 : la sortie 60 img/s reste identique au bit, par
// CONSTRUCTION et non par un `if`. Le glissement de phase et le rebase de sortie
// disparaissent avec le besoin qui les justifiait.
//
// `OG_TICK_ALPHA_UNIFIED=0` restaure le chemin de l'essai 2 sur LE MEME binaire : c'est
// l'avant/apres que les directives exigent, et c'est ce qui a mesure le defaut ci-dessus.
//
// La tolerance du `ceil` n'est PAS un budget d'erreur : elle ne protege que le cas exact
// (une image declaree `lock_n * tick` doit rendre k = lock_n et pas lock_n + 1 sur un ulp).
// Tout ce qu'elle laisse passer est absorbe par l'alpha de l'image suivante, sauf quand
// alpha serait borne au-dessus de 1 — d'ou une valeur au ras de l'epsilon, et pas les
// 0,03 tick (0,5 ms, 3 % d'un tick) que `render_pace` s'accorde.
constexpr double kAlphaCeilTol = 1e-6;

// Gfixed-tick-anim-interp (2026-09-01) — CETTE CONSTANTE NE DESARME PLUS RIEN.
// Elle valait 0.95 et servait a DESARMER l'horloge des que la cadence d'affichage
// depassait ~63 Hz, parce que l'etape 1 ne savait pas dessiner une image sans tick.
// C'est exactement ce que le rapport de Gfixed-tick-interpolation a nomme « ETAPE 2 »,
// et c'est aussi ce qui rendait la phase courante INMESURABLE au-dessus de 60 img/s :
// les deux bras de l'ablation y publiaient `armed=0`, donc la meme ligne.
// Desormais l'horloge reste armee et rend simplement k = 0 tick pour les images qui
// n'en meritent pas ; GOAL met alors `time-ratio` a 0 pour cette image
// (engine/draw/drawable.gc) et la logique n'avance pas. La constante est conservee
// UNIQUEMENT comme seuil de DIAGNOSTIC (`fast_display()`), plus comme decision.
constexpr double kDisarmFasterThan = 0.95;

// Etat d'armement de l'horloge, et QUI le decide.
//
// Deux sources, dans cet ordre de priorite, et la priorite est le point important :
//   1. l'ENVIRONNEMENT (`OG_FIXED_TICK`, ou la propriete Android
//      `debug.opengoal.fixed_tick`). Si elle est posee a "0" ou "1", elle FORCE l'etat
//      et le reglage du joueur est ignore. C'est ce qui rend l'ablation SUR LE MEME
//      BINAIRE possible : une course armee et une course desarmee, meme .so, meme
//      donnees, sans passer par le menu ;
//   2. sinon, le REGLAGE DU JOUEUR, pousse chaque image depuis GOAL par
//      `pc-set-fixed-tick!` (Recharged Settings). Defaut DESARME = comportement
//      d'origine au bit pres.
//
// DEFAUT DESARME (superviseur 2026-08-30) : une reecriture du pas de simulation ne part
// pas armee chez l'owner sans qu'il l'ait demandee. Le menu est la pour qu'il puisse
// l'armer lui-meme, sans adb et sans nouveau build.
bool enabled();

// Reglage du joueur (Recharged Settings). Sans effet quand l'environnement force
// l'etat — voir ci-dessus. Une transition desarme->arme rebase l'accumulateur, sinon la
// premiere image apres l'armement porterait tout le temps ecoule depuis la derniere.
void set_enabled(bool on);

// Sonde de cadence opt-in (`OG_FIXED_TICK_PROBE`, ou la propriete Android
// `debug.opengoal.fixed_tick_probe` a "1") : une ligne par image DESSINEE. Elle est
// OPT-IN au PRODUCTEUR et pas au consommateur — une sonde par-image livree armee a
// deja coute 40 Mo de sortie en 220 s sur l'appareil. Sur Android stdout/stderr sont
// routes vers logcat, donc la meme sonde sert aux deux plateformes.
bool probe_enabled();

// Le harnais de rejeu d'entrees force un pas de temps deterministe (il ecrit
// *ticks-per-frame* a chaque frame, game/kernel/jak1/kmachine.cpp). Dans ce mode
// l'horloge rend exactement 1 tick par image sans lire la montre : la course est
// reproductible et la SEULE difference entre deux framerates cibles est la TAILLE du
// pas — ce qui est precisement la grandeur a mesurer.
void set_deterministic(bool on);

// Publication vers GOAL. Le module reste ignorant de la table des symboles (elle est
// specifique au jeu) : le noyau jak1 enregistre ce rappel dans InitMachineScheme et
// ecrit les trois symboles que `display-frame-start`, `display-loop` et
// `cam-render-interp!` lisent. Si le rappel n'est JAMAIS enregistre (plateforme dont
// le noyau ne passe pas par la), rien n'est publie, `*fixed-tick-armed*` reste a 0 et
// le moteur garde exactement son chemin d'origine : le mode de defaillance est le
// comportement d'avant, jamais un appel dans le vide.
//   armed   : 1 si cette image est pilotee par l'horloge a pas fixe, 0 sinon
//   catchup : nombre de ticks de RATTRAPAGE a executer sans rien dessiner
//   alpha   : alpha d'interpolation de rendu en micro-unites (1e6 == pose courante)
//   skip    : 1 si cette image DESSINEE ne porte AUCUN tick de logique (affichage
//             plus rapide que 1/60 s). C'est l'etape 2 nommee par le rapport de
//             Gfixed-tick-interpolation : au-dessus de 60 Hz il FAUT dessiner des
//             images sans tick, sinon la logique suit la cadence d'affichage.
using PublishFn = void (*)(int armed, int catchup, s32 alpha_micro, int skip);
void set_publisher(PublishFn fn);

// Gfixed-tick-anim-interp — INTERPOLATION DES POSES DE SQUELETTE.
// Deux interrupteurs publies vers GOAL comme VALEURS de symbole (jamais des
// symboles-FONCTION : voir la note ci-dessus sur le SIGILL Android).
//   `anim_interp_enabled()` : OG_ANIM_INTERP / debug.opengoal.animinterp, DEFAUT 1.
//       Mis a 0, le moteur reprend exactement le chemin d'avant cette phase — c'est
//       l'ablation SUR LE MEME BINAIRE qu'exigent les directives.
//   `anim_probe_enabled()`  : OG_ANIM_PROBE / debug.opengoal.animprobe, DEFAUT 0.
//       Sonde par image dessinee ; opt-in au PRODUCTEUR, une sonde par-image livree
//       armee a deja coute 40 Mo de sortie en 220 s.
bool anim_interp_enabled();
bool anim_probe_enabled();
// Grecharged-foliage-wind3 : `wind_native_rate_enabled()` : OG_WIND_NATIVE_RATE /
// debug.opengoal.wind.native_rate, DEFAUT 1. A 0, la brise native reprend le chemin
// « high fps » d'avant cette phase (voir wind.gc). C'est l'ablation sur le meme binaire.
bool wind_native_rate_enabled();

// Fait avancer l'accumulateur d'UNE image dessinee et rend le nombre de pas de
// 1/60 s dus :
//   0   => AUCUN tick pour cette image. Deux cas, que `armed()` distingue :
//          horloge desarmee (le moteur garde son calcul d'origine), ou horloge armee
//          et image de RENDU SEUL (affichage plus rapide que 1/60 s) ;
//   >=1 => cette image consomme 1 tick, les (n-1) autres sont des ticks de RATTRAPAGE
//          que `display-loop` execute sans rien dessiner.
int begin_render_frame();

// Etat de l'horloge pour la DERNIERE image passee par `begin_render_frame`. Separe du
// nombre de ticks, precisement parce que « 0 tick » et « pas armee » ne sont plus la
// meme chose depuis Gfixed-tick-anim-interp.
bool armed_last_frame();

// Cadence d'affichage plus rapide que le pas fixe (moyenne glissante). DIAGNOSTIC.
bool fast_display();

// Appelee UNE fois par image dessinee, au point de soumission de la chaine DMA
// (`__send-gfx-dma-chain`) — le seul signal « une image vient d'etre produite » qui
// existe sur les DEUX plateformes. Fait avancer l'accumulateur puis publie.
//
// `anim_interp_n` est la valeur courante du symbole GOAL `*anim-interp-n*` : le nombre
// cumule de canaux d'animation REELLEMENT retimes (process-drawable-h.gc:176). Elle sert
// a l'invariant de POSE DESSINEE, qui doit se juger au point de LECTURE : un alpha pousse
// que personne ne lit se solde a 1,0 dans le chiffre publie, sinon une correction jamais
// consommee rendrait un vert. Le parametre est OBLIGATOIRE — pas de surcharge sans lui —
// parce qu'une plateforme qu'on oublierait de cabler mesurerait zero en silence.
void on_render_frame(u64 anim_interp_n);

// Alpha d'interpolation de rendu, convention ci-dessus, en micro-unites [0..1000000].
// CONSOMMATEUR : `cam-render-interp!` (goal_src/jak1/engine/camera/cam-update.gc), qui
// slerp la rotation et lerp la position de la camera entre le tick precedent et le
// tick courant. Sans cet alpha, x86 ne faisait AUCUNE interpolation de rendu (le
// binding renvoyait 1e6 en dur, game/kernel/common/kmachine.cpp).
s32 render_alpha_micro();

// Compteurs de PREUVE DE CABLAGE : publies a cote des mesures pour montrer que le
// chemin a reellement tourne, au lieu d'affirmer que le code est present.
u64 total_ticks();
u64 total_render_frames();
u64 total_armed_frames();

// Gfixed-tick-anim-interp-2 — ETAT DU VERROU DE CADENCE, publie a cote des mesures.
// Sans lui, « pas d'amelioration a 30 images/s » et « la condition ne se represente
// pas a 30 images/s verrouillees » sont indistinguables — c'est exactement l'erreur
// que le cycle 1 a commise en publiant un rapport de 0,846 comme un resultat.
//   lock_state()      1 = cadence verrouillee sur un multiple entier de ticks
//   last_dev_ticks()  |dt/tick - entier le plus proche| de la derniere image
//   lock_events()     entrees en verrou ; unlock_events() sorties
//   ceiling_clamps()  images dont la duree a ete ecretee a kMaxCatchupTicks
//   catchup_clamps()  images ou le plafond de rattrapage a JETE du temps de jeu
// Correctif de cette phase ARME (defaut) ou non. A 0 (`OG_TICK_LOCK=0` /
// `debug.opengoal.ticklock`), l'horloge reprend l'accrochage par image tel qu'il a ete
// livre : c'est l'ablation du correctif sur LE MEME binaire.
//
// CE QUE LE MODULE PUBLIE POUR `lib/proof_run.sh` (item `fixed-tick-interpolation`).
// Jusqu'ici AUCUNE de ces grandeurs ne sortait sous forme `cle=valeur` : `ceiling_clamps()`
// et `catchup_clamps()` — c'est-a-dire le temps de jeu JETE — n'existaient que dans la sonde
// `GFT`, elle-meme opt-in derriere `OG_FIXED_TICK_PROBE`. Aucune porte ne pouvait donc lire
// quoi que ce soit de ce chantier, et l'item n'avait pas de `gate:`.
//
//   tick_rate_dev_pct_x100   LA PORTE. Ecart max, sur une fenetre de 5 s de temps mural
//                            ADMIS, entre le temps de jeu emis (ticks/60) et ce temps
//                            mural, en CENTIEMES de pourcent. C'est l'invariant dont
//                            depend « le saut fait la meme hauteur a 25 et a 120 img/s ».
//                            Vaut 999999 s'il y a moins de 8 fenetres : une absence de
//                            mesure doit faire ECHOUER la porte, jamais la passer.
//   tick_rate_windows        fenetres jugees.
//   tick_drift_ms            (temps de jeu emis - temps mural admis), cumule et SIGNE.
//   tick_time_dropped_ms     temps reel JETE par l'ecretage anti-spirale, cumule. Rien
//                            n'est exclu de la mesure : ce qui est jete est compte ici.
//   tick_ceiling_clamps      images dont la duree a ete ecretee.
//   tick_catchup_clamps      images ou le plafond de rattrapage a jete du retard.
//   tick_locked_pct          part des images en cadence VERROUILLEE. A 100, la course est
//                            un temoin et pas un verdict : verrouillee, l'horloge declare
//                            un entier de ticks et l'ecart ne peut pas se manifester.
//   tick_lock_err_pct_x100   ecart max, SUR LES IMAGES DONT LA DUREE EST REELLEMENT
//                            REMPLACEE par `lock_n / 60`, entre cette duree declaree et la
//                            duree reelle. Publie a part parce que c'est du temps
//                            cree/perdu par REMPLACEMENT de la mesure, pas par arrondi
//                            d'accumulateur. Depuis l'essai 2 il est borne par
//                            kLockTolerance / lock_n : seule une image SUR la grille est
//                            substituee.
//   tick_conserve_err_pct_x100
//                            LE DEFAUT DE L'ESSAI 2, mesure PAR IMAGE. Ecart max entre le
//                            temps reel admis d'une image et ce que l'horloge en a fait
//                            (ticks emis + variation de l'accumulateur), tolerance du
//                            verrou retranchee, en centiemes de pourcent d'un tick.
//                            Les transitions declarees (ecretage, encliquetage, sortie de
//                            verrou) en sont exclues et comptees a part.
//   tick_conserve_frames     images jugees par cet invariant.
//   tick_lock_transients     images HORS GRILLE rencontrees pendant que le verrou TIENT.
//                            C'est la CONDITION du defaut : sous 8, la course n'a rien
//                            exerce et `tick_worst_dev_pct_x100` sort hors bande.
//   tick_lock_events / tick_unlock_events   entrees et sorties de verrou.
//   tick_time_fabricated_us  temps de jeu fabrique par le rebase de sortie de verrou.
//   tick_worst_dev_pct_x100  LA PORTE. max(tick_rate_dev_pct_x100, tick_conserve_err_pct_x100),
//                            999999 si l'une des trois conditions de mesure manque.
//   tick_armed / tick_frames / tick_ticks / tick_lock_armed / tick_lock_strict : cablage.
bool tick_lock_enabled();

// essai 2 — a 0, le verrou reprend la substitution INCONDITIONNELLE de l'essai 1 (duree
// d'image remplacee des que l'etat est verrouille, reste accumule detruit). Defaut 1 :
// le correctif est livre. L'interrupteur n'existe que pour l'avant/apres sur le meme binaire.
bool tick_lock_strict();
int lock_state();
double last_dev_ticks();
u64 lock_events();
u64 unlock_events();
u64 ceiling_clamps();
u64 catchup_clamps();

}  // namespace fixed_tick
