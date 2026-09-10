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

// Un tirage issu d'un site de dessin ROUGE de debug. `site` est son nom, publie tel quel.
void note_debug_red_draw(const char* site);

// Fin d'image : arrete les maxima et publie. Appele une fois par image, du meme endroit que
// `autoport_proof::frame_tick()`.
void end_frame();

}  // namespace fire_red_census
