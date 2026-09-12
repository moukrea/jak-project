#pragma once

// menu_dpad_census — LE RECENSEMENT DE L'ITEM `menu-dpad-steps`.
//
// La plainte : « une pression sur la croix deplace d'UN cran, jamais deux ». La grandeur qui
// la juge est `menu_step_overshoots` : le nombre de PRESSIONS (front montant -> front
// descendant) qui ont fait avancer le curseur de plus d'un cran.
//
// POLARITE. Tout inconnu vaut DEFAUT : tant que la campagne n'a pas couvert les trois jambes
// (manette, tactile franc, tactile seme), assez de pressions et au moins deux pages,
// `menu_step_overshoots` ne porte PAS le total mesure mais `9000 + code de vacuite`. Une porte
// verte par inaction — « aucun menu ouvert, donc zero depassement » — est ainsi impossible.

#include <cstdint>

namespace menu_dpad_census {

// Appelé par GOAL, une fois par passage de respond-common (donc une fois par image
// pendant que le menu est ouvert).
//   mask : 1 = haut tenu, 2 = bas tenu, 4 = front haut, 8 = front bas,
//          16 = tap-haut (canal tactile du menu), 32 = tap-bas
//   steps : crans parcourus par CETTE image (0 ou 1)
//   screen : valeur de (-> obj display-state)
void note_frame(int mask, int steps, int screen);

// Appelés par la couche Java via JNI (l'autre agent).
void set_leg(int leg);              // 0 repos, 1 manette, 2 tactile-franc, 3 tactile-seme
void note_gesture(int edges, int legacy_edges);  // fin d'un geste pilote : nb de fronts que
                                    // Java a emis, et nb qu'aurait emis la regle d'ORIGINE
                                    // (seuil nu, sans verrou) pour ce meme geste — le temoin
                                    // de non-vacuite, jamais emis vers le jeu.
void note_geometry(int dead_x100, int arm_inner_x100, int seed_dip_x100);  // px de vue x100
void note_campaign_done(int legs_done); // bitmask : 1 manette, 2 tactile-franc, 4 tactile-seme

int current_screen();   // dernier display-state vu par GOAL, -1 si aucun
bool menu_live();       // vrai si note_frame a ete appele depuis moins de 30 images

// Une fois par image RENDUE, depuis pc_autoport_frame.
void publish_tick();

}  // namespace menu_dpad_census
