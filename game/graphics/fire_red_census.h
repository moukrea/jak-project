#pragma once

// fire_red_census — LE RECENSEMENT DE CE QUI DESSINE EN ROUGE SUR OU AU-DESSUS DES FEUX
// (item `fire-red-particles`, owner 2026-09-10 : « un truc louche au dessus des feux, ca fait
// des particules rouges bizarres, probablement un des tests/debugs qui est reste la »).
//
// CE QU'IL COMPTE, ET POURQUOI CES COMPTEURS-LA.
// ---------------------------------------------
// Le foyer du maire de Sandover (`goal_src/jak1/levels/village1/village1-part.gc:505`,
// `group-village1-mayor-fire`) est fait de cinq parts d'ORIGINE :
//   * 410 / 412  `bigpuff`  — la fumee.
//   * 2292 (x60) `hotdot`   — les braises. `:r 256 :g 128 :b 128`, `fade-g/-b -0.711` : elles
//                             VIREENT au rouge en vieillissant. C'est le jeu d'origine.
//   * 411        `middot`   — `:r 256 :g 0 :b 0` et surtout `:a 0.0` SANS `fade-a` : un PORTEUR
//                             invisible, pose a 1..1,5 m AU-DESSUS du foyer, dont le seul role
//                             est de jouer « fire-pop » et de porter (`:binding 2292`) les
//                             braises. Le jeu d'origine ne le montre JAMAIS.
//   * 413        aux-list   — le distordeur de chaleur.
// Donc « une particule rouge au-dessus du feu que le jeu d'origine ne dessine pas » a une
// signature exacte et falsifiable : un sprite de texture `middot`, rouge pur (g et b nuls),
// qui ATTEINT le tampon. Il l'atteint de deux facons, et les deux sont comptees separement :
//   - `carrier_alpha` : son alpha passe le test d'alpha du chemin sprite (`a >= alpha_min`) ;
//   - `carrier_afail` : son alpha ECHOUE le test, mais le melange de son seau ne pondere pas
//                       par l'alpha source (`SRC_0_FIX_DST` / `SRC_DST_FIX_DST`, fix=128/64) et
//                       la seconde passe `AFAIL_NO_DEPTH_WRITE` le dessine quand meme.
// S'y ajoutent deux familles qui ne peuvent appartenir a aucun jeu d'origine :
//   - `nonfinite`   : un sprite dont la position n'est pas finie ou sort du monde. C'est le mode
//                     de panne connu des particules LIEES sur arm64 (`sparticle_launcher.cpp:694`
//                     — quaternion NaN, enfant ne a ±1e9..1e13).
//   - `debug_draw`  : un tirage issu d'un site de dessin rouge de DEBUG (DirectRenderer
//                     `DEBUG_RED`, sondes du GlowRenderer, effacement rouge du TextureAnimator).
//                     Tous sont derriere une case ImGui ; les compter rend leur zero MESURE au
//                     lieu de suppose.
// `fire_debug_particles` est la somme de ces quatre-la, prise au MAXIMUM sur une image : la
// borne demandee par l'item. Les braises d'origine ne sont PAS dedans — elles sont publiees a
// part (`fire_red_sprites_max`) parce que le perimetre interdit d'y toucher.
//
// LE DENOMINATEUR. Un zero obtenu parce que l'instrument n'a rien vu ne vaut rien. On publie
// donc aussi le nombre d'images recensees et le nombre de sprites de feu REELLEMENT dessines :
// un `fire_debug_particles=0` avec `fire_sprites_seen=0` n'est pas un verdict, c'est un silence.

#include <cstdint>

namespace fire_red_census {

// Vrai quand le harnais n'a pas desarme CET item. Defaut : arme (le binaire de l'owner).
bool armed();

// Un sprite de monde d'un seau dont la texture est nommee `texture_name`, tel qu'il part au
// tampon. `x,y,z` = sa position monde brute (unites GOAL), `r,g,b,a` = sa couleur de sommet
// APRES l'empaquetage 8 bits de Sprite3 (donc dans [0,1]), `alpha_min` = le plancher du test
// d'alpha en vigueur pour ce seau, `alpha_blend` = `(int)DrawMode::AlphaBlend` du seau,
// `double_draw` = ce seau fait-il la seconde passe AFAIL.
void note_sprite(const char* texture_name,
                 float x,
                 float y,
                 float z,
                 float r,
                 float g,
                 float b,
                 float a,
                 float alpha_min,
                 int alpha_blend,
                 bool double_draw);

// UN SPRITE 2D AU POINT D'EMPAQUETAGE — l'oracle de la couleur.
//
// POURQUOI CE COMPTEUR EXISTE. `Sprite3::do_block_common` empaquete la couleur que GOAL a ecrite
// (des flottants a l'echelle 0..255, que RIEN ne borne par le HAUT : le seul clamp du chemin
// sparticle est le `vmaxx ... vf0` a >= 0) en quatre octets. Depuis l'amont `f4941706a6`
// (« wrap sprite rgba to 0-255 », 2024-06-04) cet empaquetage etait un REPLIEMENT `(int)v & 0xff`.
// Un `defpart` d'origine qui ecrit `:r 256.0` — le foyer du maire (411, 2292) et le portail de
// teleportation le font — voyait donc son canal rouge rendu NUL, puis basculer d'un coup a 255
// des que le `fade-r` du launcher suivant le faisait passer sous 256. C'est une couleur que la
// donnee de Naughty Dog ne decrit nulle part : elle n'appartient pas au jeu d'origine.
//
// L'ORACLE. On donne a l'instrument la couleur SOURCE et les quatre octets REELLEMENT ecrits
// dans le sommet. La reference est calculee a part, depuis la source seule : la SATURATION
// `v < 0 -> 0 ; v > 255 -> 255 ; sinon (int)v`. Trois grandeurs en sortent :
//   * `pack_foreign`  — le sommet differe de la reference. C'est la grandeur de la PORTE : elle
//                       entre dans `fire_debug_particles` et doit tomber a 0.
//   * `pack_oldwrap`  — le nombre de sprites sur lesquels l'ANCIENNE politique `& 0xff` donnait
//                       une autre couleur que la reference. Ce compte reste NON NUL apres la
//                       correction : c'est lui qui prouve que l'oracle a des dents, et c'est la
//                       taille exacte du defaut que l'owner voyait.
//   * `pack_oor`      — le nombre de sprites dont une composante SOURCE sort de [0,255]. Sans
//                       lui, un `pack_foreign=0` pourrait n'etre qu'une condition absente.
// LE HUD EST A PART, ET CE N'EST PAS UN AMENAGEMENT. Le clignotement « eco bas » du HUD
// (`goal_src/jak1/engine/ui/hud-classes.gc:1276-1279` : `(set! arg3 (* arg3 2))` sur un canal
// vert a 128) s'appuie DELIBEREMENT sur le repliement — c'est ce que la PR amont #3549
// retablissait. Ce n'est pas une particule du monde, l'owner ne parle pas de lui, et la
// correction ne le touche pas : il est compte separement (`fire_pack_foreign_hud`) et n'entre
// pas dans la porte. Tout sprite du monde, lui, y entre.
//
// `sr,sg,sb,sa` : la couleur source, echelle 0..255, non bornee. `pr,pg,pb,pa` : les octets
// ecrits. `texture_name` : l'emetteur, publie nommement dans `fire_pack_emitters`.
void note_pack(const char* texture_name,
               bool hud,
               float sr,
               float sg,
               float sb,
               float sa,
               int pr,
               int pg,
               int pb,
               int pa);

// Un tirage issu d'un site de dessin ROUGE de debug. `site` est son nom, publie tel quel.
void note_debug_red_draw(const char* site);

// Fin d'image : arrete les maxima et publie. Appele une fois par image, du meme endroit que
// `autoport_proof::frame_tick()`.
void end_frame();

}  // namespace fire_red_census
