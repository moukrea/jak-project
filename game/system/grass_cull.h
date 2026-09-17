#pragma once

// grass_cull — LA CAMPAGNE DE L'ITEM `grass-chunk-cull`.
//
// CE QUE L'ITEM DEMANDE, ET CE QUE CE MODULE FAIT.
// -----------------------------------------------
// « Publier, a TROIS ORIENTATIONS DE CAMERA NOMMEES, le compte d'instances soumises et le compte
// d'instances dont la boite englobante intersecte le frustum. L'ecart est le defaut. »
//
// Le CORRECTIF (le culling par lot) vit dans `GrassRenderer` et tourne TOUJOURS : c'est ce que
// l'owner joue, il n'est derriere aucun drapeau. Ce module-ci ne corrige rien — il POSE LE REGIME
// (herbe allumee, palier medium, distances par defaut, orientation), il ALTERNE les deux regimes
// dans la MEME course (culling actif / culling inhibe) et il MESURE. Desarme, il sort a sa
// premiere ligne et le jeu ne sait pas qu'il existe.
//
// POURQUOI ALTERNER DANS UNE SEULE COURSE. Deux courses separees = deux scenes et deux frequences
// qui derivent ; le gain lu serait celui de la derive. Les deux jambes se suivent au MEME vantage,
// sur le MEME binaire, a la MEME orientation : leur difference est le culling et rien d'autre.
//
// L'ORIENTATION, ET SA LIMITE, DITE ICI ET PAS SEULEMENT DANS LE RAPPORT.
// ----------------------------------------------------------------------
// Aucun moyen n'existe dans cet arbre pour imposer un cap a la camera du JEU sans passer par le
// mode `refset` (capture d'images) : `debug.opengoal.level.warp` n'ecrit que la translation du
// point de reprise, jamais son quaternion. Les vues 1 et 2 tournent donc la camera DE L'HERBE
// (la matrice que `GrassRenderer` pousse au shader et dont le culling se sert), pas celle du
// monde. Consequence, publiee avec la mesure (`grass_cull_v<N>_camera_rotated`) :
//   * les comptes de soumission, de frustum et de lots sont EXACTS aux trois vues — culler et
//     dessiner consomment la meme matrice, le recensement aussi ;
//   * la CADENCE n'est honnete qu'a la vue 0, qui est la camera du jeu telle quelle : aux vues
//     1 et 2 les fragments d'herbe sont testes contre un tampon de profondeur ecrit par une
//     AUTRE camera, ce qui ne represente plus le cout GPU reel.
// C'est pour cela que la vue 0 seule porte les jambes longues de cadence.
//
// LE VERDICT. `grass_offscreen_submitted` est une SOMME DE TERMES PUBLIES SEPAREMENT, chacun nul
// quand le culling est correct :
//   * `_gap`              : |soumises - instances des lots que l'oracle garde|, par vue ;
//   * `_dropped_visible`  : instances individuellement DESSINABLES qui n'ont pas ete soumises —
//                           le terme qui interdit de gagner du temps en retirant des pixels ;
//   * `_offscreen`        : instances soumises dans un lot que l'oracle declare hors du volume ;
//   * `chunk_mismatch`    : lots du fichier != lots recalcules (le determinisme de la partition) ;
//   * `missing_terms`     : chaque cle attendue absente, chaque vue vide. Sans lui, une course qui
//                           ne mesure RIEN publierait zero et passerait la porte par inaction.
//
// L'ORACLE N'EST PAS UN MIROIR. Le culler extrait six plans de la matrice monde->clip et fait un
// test centre/extension ; l'oracle rejoue LITTERALEMENT l'arithmetique de `grass.vert` sur chaque
// instance et sur les huit coins de chaque boite. Deux implementations, deux arithmetiques, le
// meme predicat : une erreur de signe, de transposition ou de gabarit dans l'une se lit comme un
// ecart non nul, jamais comme un zero silencieux.

#include <cstdint>

namespace grass_cull {

// Vrai quand le harnais mesure CET item. Lisible depuis n'importe quel fil.
bool enabled();

// ── fil GOAL : le regime, pose au POINT DE PRODUCTION ───────────────────────────────────────
// GOAL repousse ces reglages a chaque image ; une ecriture faite ailleurs serait ecrasee.
bool grass_on_override(bool* on);
bool preset_override(int* preset);
bool dists_override(float* near_m, float* card_m);

// ── fil GL, depuis GrassRenderer::render ────────────────────────────────────────────────────
// Rotation de vue imposee a cette image, en radians autour de l'axe Y du monde, pivot = l'oeil.
// Rend faux hors campagne et a la vue 0 (camera du jeu telle quelle).
bool view_yaw(float* yaw_rad);

// Le culling doit-il agir cette image ? Faux pendant la jambe TEMOIN (tout est soumis).
bool culling_active();

// Cette image porte-t-elle le recensement (le balayage complet des instances) ? Au plus une par
// jambe : il coute un parcours des 616 000 instances et n'a rien a faire dans la fenetre de temps.
bool want_census();

// La partition telle que le renderer l'a resolue (une fois par champ construit).
void note_partition(uint64_t chunks,
                    uint64_t inst_min,
                    uint64_t inst_p50,
                    uint64_t inst_p90,
                    uint64_t inst_max,
                    bool from_file,
                    uint64_t mismatch,
                    uint64_t instances);

// Le recensement d'une image : ce qui a ete SOUMIS (lu aux appels de dessin) et ce que l'oracle
// dit de la meme image. `fwd` est l'avant de la camera EFFECTIVEMENT utilisee — c'est lui qui
// prouve que les trois vues sont trois vues et pas trois fois la meme.
void note_census(uint64_t submitted,
                 uint64_t chunk_visible,
                 uint64_t offscreen,
                 uint64_t dropped_visible,
                 uint64_t ideal,
                 uint64_t chunks_kept,
                 uint64_t chunks_total,
                 const float fwd[3]);

// Une image dessinee par le renderer d'herbe. Fait avancer la machine a etats.
void note_frame(double prep_us,
                double submit_us,
                uint64_t draws,
                uint64_t submitted,
                uint64_t chunks_tested,
                uint64_t uniform_lookups,
                bool field_ready);

}  // namespace grass_cull
