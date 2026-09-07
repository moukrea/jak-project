#pragma once

// origin_ablate.h — LE CONSTRUCTEUR DU BINAIRE-TEMOIN DE `lighting-origin-bitexact`.
//
// POURQUOI CE FICHIER EXISTE
// --------------------------
// L'item affirme : « maitre Recharged ETEINT, la sortie est identique AU BIT au jeu
// d'origine ». La SPEC ne laisse aucune latitude sur ce que « le jeu d'origine » veut dire
// (`.autoport/prompts/SPEC-refonte-lumiere.md:98-99`) :
//
//     « Chacun des trois gestes rend un pixel identique a UN BUILD SANS LA COUCHE
//       CONCERNEE. Pas "proche" : identique. »
//
// La reference n'est donc PAS « le meme binaire avec le drapeau a zero » : ce serait la faute
// « porte calculee sur ses propres variables », et surtout ce serait AVEUGLE au defaut que
// l'owner soupconne — du code Recharged qui remplace le vanilla SANS consulter le maitre.
// Un tel site rend exactement la meme image drapeau ON ou OFF ; seule son ABSENCE le montre.
//
// Ce fichier pose donc un unique interrupteur de COMPILATION. A 1, la couche Recharged n'est
// pas « eteinte » : elle n'est pas COMPILEE. Le binaire obtenu ne sert qu'a CAPTURER la
// reference ORIGINE-TOTAL ; c'est le binaire NORMAL qui la rejoue et qui est juge.
// `refset::verdict_master_off_bitexact()` refuse de passer au vert quand la reference a ete
// capturee par le binaire qui rejoue, ET quand elle n'a pas ete capturee par un binaire
// d'ablation (`captured-by.txt` porte les deux informations).
//
// CE QUI RESTE INTACT A 1, ET POURQUOI
// ------------------------------------
// L'INSTRUMENT. `refset`, `autoport_proof`, `pad_replay`, `fixed_tick`, `render_pace`, le warp
// de niveau et les gestes que `refset` applique sous `OG_REFSET` (epinglage de la flamme du
// mood, gel du temps des particules, horloge de vent, mise en sourdine de l'invite 2D) doivent
// etre IDENTIQUES dans les deux binaires : ils changent ce qui est dessine, et s'ils differaient
// la comparaison mesurerait l'instrument au lieu de la couche Recharged. Mesure du 2026-09-07
// qui rend ce point concret : le jeu fige par `lighting-census` differe de 110289 px du meme
// plan rejoue aujourd'hui, et cet ecart est celui de l'INSTRUMENT (essais 6 a 9 de
// `lighting-hdr`), pas d'une fuite.
//
// LA VALEUR COMMITTEE EST 0, ET CE N'EST PAS NEGOCIABLE. Le binaire de l'owner est le binaire
// NORMAL. Le binaire-temoin se fabrique par `.autoport/reports/lighting-origin-bitexact/notes/
// build_ablate.sh`, qui bascule ce fichier a 1, batit, met le binaire de cote, remet 0 et
// rebatit. L'arbre ne reste jamais a 1.
//
// PORTEE HONNETE — ce que ce temoin NE couvre PAS :
//   * le GOAL. Les deux binaires bootent sur les MEMES `.CGO` : une fuite qui vivrait dans
//     `goal_src/` ne serait pas vue.
//   * les SHADERS. Sur x86 ils sont lus du DISQUE a l'execution : les deux binaires lisent les
//     memes fichiers `.glsl`. Une fuite qui vivrait uniquement dans du GLSL atteint sous maitre
//     eteint ne serait pas vue.
//   * ce qui n'est pas sous `#if !AUTOPORT_ORIGIN_ABLATE`. La liste des sites ablates est dans
//     le rapport de l'item ; ce qui n'y est pas n'est pas prouve.

#define AUTOPORT_ORIGIN_ABLATE 0
