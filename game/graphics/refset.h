#pragma once

// refset — LES DEUX JEUX D'IMAGES DE REFERENCE, ET LEUR REJEU.
//
// POURQUOI. SPEC-refonte-lumiere.md §7.3 : la refonte de l'eclairage compte douze items, et
// chacun peut casser silencieusement le rendu d'un autre. La garde est un couple de jeux
// d'images :
//   ORIGINE   (`recharged_master` OFF)  — ne bouge JAMAIS, `maxdiff == 0`.
//   RECHARGED (master ON, prereglage fige) — ne bouge que si l'item le declare.
// Elle est posee par l'item 0 et REJOUEE a la fermeture de chaque item suivant.
//
// AUCUNE IMAGE N'EST UNE PREUVE : LE NOMBRE L'EST. Ce module ne montre rien. Il rejoue une
// course deterministe, relit le tampon de couleur, le compare octet a octet a la reference
// stockee, et publie `refset_replay_maxdiff` (le plus grand ecart absolu par canal, 0..255) et
// `refset_replay_diffpx`. C'est cette grandeur, et elle seule, qui ferme la porte.
//
// D'OU VIENT LE DETERMINISME. Rien d'invente : les quatre leviers existaient deja dans cet
// arbre et sont ceux que le harnais utilise depuis des mois.
//   1. `OG_LEVEL_WARP=<continue>` (+ `_POS`) pose Jak a un point nomme (kmachine.cpp:5660).
//   2. `OG_PAD_REPLAY_REPLAY=<demo>` ancre la course sur l'apparition de *target*, force TOUTES
//      les sources d'alea a une graine fixe, force un pas de temps de 1/60 s par image, et
//      neutralise l'entree (pad_replay.h). L'index est la frame de LOGIQUE, pas l'image
//      dessinee : le boot et le chargement, de duree variable, sont absorbes.
//   3. L'heure du jeu est reposee A CHAQUE IMAGE par `set-time-of-day` (hud-classes-pc.gc:1841)
//      depuis la valeur que ce module publie — l'horloge ne derive pas.
//   4. La capture passe par le chemin de capture d'ecran INTERNE : l'image est rendue a une
//      resolution FIXE (320x180, msaa 1) dans le FBO interne, donc la taille de la fenetre de
//      la machine qui rejoue n'entre pas dans la comparaison.
//   5. LES DEUX SORTIES DU RETIMEUR DE RENDU SONT NEUTRALISEES sous `OG_REFSET` seulement
//      (render_pace.cpp `alpha_micro()` rend 1e6, `skip()` rend faux ; le module RESTE arme, donc
//      `ee_timer()` continue de rendre l'horloge virtuelle).
//      C'etait la derniere entree de montre murale du chemin de dessin, et c'etait LA cause de
//      l'echec de l'essai 1 : `render_pace::alpha_micro()` publie la position du temps REEL
//      entre deux ticks, et deux consommateurs en reecrivent ce qui est dessine —
//      `cam-render-interp!` (cam-update.gc:246) retime trans + inv-camera-rot de *math-camera*,
//      `*anim-interp-alpha*` (drawable.gc:1107) retime les poses d'articulation. Mesure du
//      2026-09-06 : deux courses strictement identiques divergeaient sur la pose camera des
//      l'ancre+7 puis se figeaient a ~0,02 m, alors que la translation de *target* etait
//      bit-identique sur 900 images de logique. La preuve porte `refset_pace_alpha=1000000` et
//      `refset_raw_alpha_min/max` : le second dit que la grandeur supprimee VARIAIT vraiment,
//      sans quoi la neutralisation serait une clause vide.
// La capture est appariee a la frame de LOGIQUE de la chaine DMA rendue, pas au numero d'image
// du renderer : sans ca l'entrelacement des deux fils deciderait, a une frame pres, de quelle
// pose de Jak on garde la photo — et une frame d'ecart suffit a faire mentir la porte.
//
// CE QUI EMPECHE LA PORTE DE SE MENTIR A ELLE-MEME.
//   * En mode `capture`, `refset_replay_maxdiff` n'est PAS publie du tout. Une course qui
//     fabrique ses propres references ne peut donc pas passer la porte.
//   * En mode `replay`, la valeur vaut 254 des la premiere image et ne devient la vraie mesure
//     que lorsque les 16 etapes sont TOUTES faites : une course interrompue est rouge, jamais
//     vide. Une reference absente ou de taille differente rend 255.
//   * Les references sont capturees avec le recensement DESARME et rejouees avec le
//     recensement ARME : `maxdiff == 0` prouve alors, litteralement, que l'item 0 ne change
//     aucun pixel.
//
// LA STABILITE DE L'INSTRUMENT, ET COMMENT ELLE SE PROUVE (item `refset-replay-stable`).
// Un `maxdiff` juste ne suffit pas : il faut qu'il soit LE MEME deux fois. Mesure du 2026-09-06,
// meme binaire et memes references octet pour octet, quatre rejeux : 188, 0, 0, 184. La cause
// est NOMMEE, pas absorbee par une tolerance — `Loader::refresh_recharged_textures` amortissait
// la re-resolution des 2761 textures Recharged sur une borne en MILLISECONDES REELLES ; le jeu
// de references bascule `recharged-master?` a chaque etape, donc la photo tombait avant ou apres
// la fin de la passe selon la charge de la machine. Sous `OG_REFSET` cette borne est retiree et
// seule celle qui se compte en IMAGES reste (Loader.cpp), et `hotreload_rt_bound_hits` publie
// combien de fois la borne retiree AURAIT coupe : a zero, la neutralisation serait une clause
// vide.
// La grandeur de porte est `refset_replay_flaky` : le nombre de paires de rejeux CONSECUTIFS,
// meme binaire et memes references, dont le `maxdiff` differe. Elle porte sur des COURSES, donc
// le moteur tient un registre `<dir>/replay-ledger.txt` (une ligne par rejeu complet, avec
// l'empreinte du binaire et celle des 16 references) et publie le verdict qu'il en lit :
// `refset_replay_runs` lignes retenues, 254 tant qu'il y en a moins de CINQ, 255 si la course
// n'a pas pu se mesurer. Un binaire rebati ou une reference recapturee change une empreinte et
// perime le registre tout seul.
//
// PORTEE HONNETE. Le declenchement de la capture passe par `render_game_frame`
// (game/graphics/pipelines/opengl.cpp), qui n'est PAS dans android/CMakeLists.txt : le jeu de
// references est un instrument x86. C'est aussi la plateforme de la preuve de cet item. Sur
// l'appareil, `refset_platform` vaut `device` et aucune etape ne se lance.

#include <cstdint>

namespace refset {

// Le harnais a-t-il demande un jeu de references ? (env `OG_REFSET=capture|replay`, propriete
// `debug.opengoal.refset`). Faux par defaut : le joueur ne subit jamais ce mode, qui deplace
// l'heure du jeu et bascule le master.
bool enabled();

// L'HORLOGE. `fn` rend *display* actual-frame-counter : +1 par image de logique SIMULEE,
// independamment de la cadence. Enregistree par le noyau jak1 (InitMachineScheme), appelee
// depuis le fil GOAL seulement.
void set_logic_frame_provider(int64_t (*fn)());
int64_t current_logic_frame();

// L'ANCRE, prise AU POINT DE L'EVENEMENT et non par un sondage par image. Appelee par le warp
// de niveau juste apres `(start 'play <continue>)`. Le PREMIER appel n'ancre rien : il arme le
// second warp (voir `wants_rewarp`). C'est le SECOND qui pose l'ancre.
//
// Pourquoi pas un sondage : `pc_autoport_frame` tourne une fois par image RENDUE, alors que le
// compteur de frames de logique avance a chaque image SIMULEE. Pendant un chargement les deux
// se desynchronisent, et l'ancre lue par sondage tombait a 601 dans une course et 600 dans la
// suivante — une frame de logique d'ecart, donc une pose de Jak differente, donc 30 % des
// pixels differents (mesure du 2026-09-06 : maxdiff 172-215, diffpx ~17000 sur 57600).
void note_anchor();

// LE SECOND WARP, ET POURQUOI IL EXISTE. Le chargement du niveau est asynchrone : `(start 'play
// <continue>)` rend la main avant que `village1` soit entierement resident, et la camera passe
// donc quelques images a se poser contre une geometrie incomplete. Son point de repos depend du
// chemin : mesure du 2026-09-06, deux rejeux STRICTEMENT identiques divergent a partir de
// l'ancre+7, se figent a ~0,02 m d'ecart, et rendent 27000 pixels differents sur 57600 — alors
// que la translation de Jak est bit-identique sur 900 images de logique.
// Le second warp re-lance `(start 'play <continue>)` 600 images de logique plus tard, quand le
// niveau est entierement charge : la camera est alors TELEPORTEE depuis un monde complet, et son
// point de repos ne depend plus de la vitesse du disque.
// Rend vrai UNE seule fois, l'image ou il faut le declencher.
bool wants_rewarp();

// Une image de plus (appelee depuis `pc_autoport_frame`, fil GOAL). Fait avancer le plan.
void tick();

// L'heure du jeu que l'etape courante impose, en heure*100 ; -1 quand le module n'impose rien.
// Consomme par `pc_get_tod_hour` (kmachine.cpp), donc applique par GOAL a chaque image.
int tod_override_x100();

// FIL GRAPHIQUE. La chaine DMA qu'on s'apprete a rendre porte la frame de logique `lf`.
// Rend vrai si cette chaine-la est celle qu'une etape attend ; remplit alors le nom de sortie
// et la resolution de capture.
bool capture_for_chain(int64_t lf, char* name_out, int name_cap, int* w, int* h);

// FIL GRAPHIQUE. Le tampon de couleur vient d'etre relu (RGBA, deja retourne a l'endroit).
// Rend vrai si c'etait notre capture — l'appelant n'ecrit alors pas le PNG de capture d'ecran.
bool consume_capture(int w, int h, const void* rgba);

}  // namespace refset
