#pragma once

// mesh_browser_census — LE RECENSEMENT DE CE QUI RESTE DU NAVIGATEUR DE MESH DE DEBUG.
//
// POURQUOI CE MODULE EXISTE. L'item `mesh-browser-removal` porte une porte `== 0` :
// `mesh_browser_sites == 0`. Une porte de nettoyage est VERTE PAR INACTION par construction —
// publier un zero en dur la passe. Elle n'est honnete que si le zero est MESURE sur le binaire
// livre, et si le recensement a d'abord rendu un NON-ZERO sur le binaire d'avant (garde dans
// `reports/mesh-browser-removal/notes/proof-recensement-AVANT.txt`).
//
// LE COMPTE EST LA SOMME DE QUATRE SONDES INDEPENDANTES qui ne peuvent pas se couvrir l'une
// l'autre (kmachine.cpp, `mesh_browser_census()`) :
//   1. GOAL    — combien de symboles de la FAMILLE du navigateur vivent encore dans la table du
//                runtime (image REELLEMENT chargee : GAME.CGO + ENGINE.CGO).
//   2. C++     — combien de champs du navigateur survivent dans `GfxGlobalSettings`. Reponse
//                calculee PAR LE COMPILATEUR (idiome de detection SFINAE) sur la vraie
//                declaration : re-ajouter un champ rearme la porte sans qu'une ligne de
//                l'instrument ne bouge.
//   3. GATING  — l'option `mesh-browser-checker` existe-t-elle encore dans `recharged_gating` ?
//                C'est la table qui decide qu'une rangee de menu peut exister.
//   4. OVERLAY — combien de pastilles du navigateur l'overlay tactile Android construit encore.
//                Java est HORS de libgk.so : aucune sonde C++ ne peut le voir. C'est donc
//                `TouchOverlayView` qui RAPPORTE son propre recensement par ce module.
//
// LA POLARITE DE LA SONDE 4 EST « INCONNU = DEFAUT ». Tant que Java n'a rien rapporte,
// `overlay_sites()` rend la PENALITE `kUnreportedPenalty` (1), pas 0 : sans cela, un binaire ou
// le rapport n'est pas cable publierait le meme zero qu'un overlay reellement nettoye, et la
// porte serait verte parce que personne n'a regarde. `overlay_reported()` est le temoin qui
// distingue les deux, et la penalite garantit qu'une preuve x86 (aucun Java) ne peut pas passer
// la porte de cet item : elle se prend sur l'appareil, comme l'item l'exige.

#include <cstdint>

namespace mesh_browser_census {

// La valeur que `overlay_sites()` rend tant que Java n'a rien rapporte. 1 = « au moins un site
// inconnu », donc porte ROUGE.
constexpr uint32_t kUnreportedPenalty = 1;

// Appele depuis le pont JNI (`gk_android_main.cpp`), qui le tient de `TouchOverlayView` :
//   `sites`   = pastilles de l'overlay qui appartiennent au navigateur de mesh ;
//   `control` = pastilles qui n'en font PAS partie et qui doivent survivre (SELECT, START...).
// Le temoin `control` rend le zero falsifiable : un recensement qui rend 0 des DEUX cotes dit
// que l'enumeration est cassee, pas que le navigateur a disparu.
void report_overlay(uint32_t sites, uint32_t control);

// Le nombre de pastilles du navigateur encore construites, ou `kUnreportedPenalty` si Java n'a
// pas parle.
uint32_t overlay_sites();

// Les temoins.
uint32_t overlay_control();
uint32_t overlay_reported();  // combien de fois Java a rapporte ; 0 = sonde MUETTE

}  // namespace mesh_browser_census
