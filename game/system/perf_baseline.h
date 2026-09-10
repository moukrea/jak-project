#pragma once

// perf_baseline — LA LIGNE DE BASE DU JEU STOCK, MESUREE PAR LE MOTEUR, CELLULE PAR CELLULE.
//
// POURQUOI. L'item `perf-stock-baseline` demande un point de depart chiffre AVANT toute
// optimisation : 3 vantages x 5 echelles de rendu, et pour chaque cellule le temps d'image, le
// temps du fil GOAL, le temps GPU, le temps CPU du fil GL et le nombre d'acteurs. Rien de tout
// cela n'existait : `frame_ms` p50/p95 est absent du depot, `gl_cpu_ms` n'a aucune cle publiee,
// et le temps GPU n'existe que sous forme de cumul jamais remis a zero. Une campagne qui
// changerait le comportement du moteur ne mesurerait pas le jeu stock : ce module ne fait que
// LIRE, plus une seule ecriture — la resolution de rendu, voir ci-dessous.
//
// L'ECHELLE DE RENDU EST IMPOSEE AU POINT DE PRODUCTION, ET C'EST LE COEUR DU DISPOSITIF.
// L'auto-echelle GOAL (`dynamic-render-scale-update` -> `pc-set-game-resolution`) est un
// CONTROLEUR SOUS L'INSTRUMENT : elle reagit a la cadence que la campagne fabrique, donc les
// cinq cellules d'un vantage ne seraient pas comparables entre elles. Aucun reglage C++ ne
// l'eteint (verifie) ; elle n'est eteignable que par settings.ini ou le menu, c'est-a-dire pas
// depuis une course. On la NEUTRALISE donc la ou sa decision devient une resolution :
// `pc_set_game_resolution`. Le controleur continue de tourner, sa sortie est jetee — et on
// publie COMBIEN de fois elle a ete jetee (`base_autoscale_overrides`) et ce qu'il demandait
// (`base_autoscale_goal_w_last`), sans quoi « la campagne a impose l'echelle » ne se
// distinguerait pas de « la fonction n'a jamais ete appelee ».
//
// CE QUI EST PUBLIE, par `autoport_proof`, v in {village1_hut, beach, jungle}, s in
// {25,40,60,80,100} :
//   base_<v>_s<s>_frame_ms_p50 / _p95   percentiles des deltas entre deux images DESSINEES
//   base_<v>_s<s>_goal_busy_ms          perf_instruments::snapshot(), a la fermeture
//   base_<v>_s<s>_gpu_ms_total          DELTA du bracket pleine-image de lighting_census
//   base_<v>_s<s>_gl_cpu_ms             moyenne du temps CPU du fil GL sur la fenetre
//   base_<v>_s<s>_actors_active         perf_instruments::snapshot(), a la fermeture
//   base_<v>_s<s>_frames / _res         le denominateur du percentile et la resolution imposee
//   perf_baseline_expected / _missing / _missing_cells / _metrics_missing / _cells_done
// `perf_baseline_missing` se calcule en RELISANT `autoport_proof::has_key`, jamais une variable
// interne : la table qui sera moissonnee fait foi.
//
// ARMEMENT. Rien ne tourne sauf si le harnais nomme cet item (`AUTOPORT_FEATURE` /
// `debug.opengoal.feature`) ou si le reglage `OG_PERF_BASELINE` /
// `debug.opengoal.perf.baseline` est pose. `armed_for("perf-stock-baseline")` desarme tout.
// Desarme, `resolution_override` rend faux, `note_drawn_frame` sort a sa premiere ligne et
// `take_warp_request` rend faux : le binaire de l'owner ne change pas de comportement.
//
// FILS. `note_drawn_frame` tourne sur le fil GL (c'est lui qui fait avancer la machine a
// etats), `resolution_override` / `take_warp_request` / `warp_pos_override` sur le fil GOAL.
// Tout ce qui traverse est atomique, sauf la demande de teleport (nom + position) qui est un
// couple de chaines et vit sous `std::mutex`.

#include <cstddef>
#include <cstdint>

namespace perf_baseline {

// Vrai quand la campagne tourne (voir ARMEMENT). Lisible depuis n'importe quel fil.
bool enabled();

// ── fil GOAL ────────────────────────────────────────────────────────────────────────────────
// `pc_set_game_resolution` va ecrire (*w, *h). Vrai => la campagne impose SA resolution et
// remplace les valeurs pointees ; faux => on ne touche a rien.
bool resolution_override(int* w, int* h);

// Une demande de teleport est-elle en attente ? Vrai une seule fois par demande : le nom du
// point de reprise est copie dans `name` et la position (metres, "x y z", "" si aucune) dans
// `pos`.
bool take_warp_request(char* name, size_t ncap, char* pos, size_t pcap);

// La position du DERNIER teleport consomme, "" si aucune. Lue par `level_warp_run`.
const char* warp_pos_override();

// ── fil GL ──────────────────────────────────────────────────────────────────────────────────
// Une image vient d'etre DESSINEE ; `gl_cpu_ms` est le temps CPU du fil graphique pour cette
// image (hors attente de vsync). Fait avancer la machine a etats de la campagne.
void note_drawn_frame(double gl_cpu_ms);

}  // namespace perf_baseline
