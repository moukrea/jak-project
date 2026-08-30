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

// Tolerance d'accrochage : une frame reelle a moins de 10 % d'un nombre ENTIER de
// ticks est ramenee dessus. Sur un panneau verrouille a 60 Hz, chaque frame vaut alors
// exactement 1 tick, le reste accumule est nul, et rien ne bouge par rapport a avant.
constexpr double kSnapTolerance = 0.10;

// Sous ce facteur du pas fixe, la cadence d'affichage est PLUS RAPIDE que 60 Hz :
// l'horloge se desarme (voir le paragraphe de perimetre ci-dessus).
constexpr double kDisarmFasterThan = 0.95;

// Armee par l'environnement / la propriete Android. Defaut ON ; `OG_FIXED_TICK=0`
// (ou `debug.opengoal.fixed_tick` a "0") desarme — c'est l'ablation SUR LE MEME
// BINAIRE qu'exigent les directives pour un avant/apres honnete.
bool enabled();

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
using PublishFn = void (*)(int armed, int catchup, s32 alpha_micro);
void set_publisher(PublishFn fn);

// Fait avancer l'accumulateur d'UNE image dessinee et rend le nombre de pas de
// 1/60 s dus :
//   0   => horloge NON armee pour cette image (desarmee, ou cadence plus rapide que
//          60 Hz) : le moteur garde son calcul d'origine ;
//   >=1 => cette image consomme 1 tick, les (n-1) autres sont des ticks de RATTRAPAGE
//          que `display-loop` execute sans rien dessiner.
int begin_render_frame();

// Appelee UNE fois par image dessinee, au point de soumission de la chaine DMA
// (`__send-gfx-dma-chain`) — le seul signal « une image vient d'etre produite » qui
// existe sur les DEUX plateformes. Fait avancer l'accumulateur puis publie.
void on_render_frame();

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

}  // namespace fixed_tick
