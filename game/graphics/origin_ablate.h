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
//     `goal_src/` ne serait pas vue. Deux sont NOMMEES et non corrigees a ce jour :
//     `*anim-interp-on*` (`kmachine.cpp:5389`, defaut 1, consomme sans garde par
//     `process-drawable.gc:256`) et `*wind-native-rate*` (`kmachine.cpp:5394`, defaut 1,
//     consomme par `wind.gc:134`). Les deux binaires les posent a 1 : l'ecart est nul PAR
//     CONSTRUCTION, la porte ne peut donc pas les voir. Les gater serait un changement
//     qu'aucune mesure de cet instrument ne pourrait juger.
//   * les SHADERS. Sur x86 ils sont lus du DISQUE a l'execution : les deux binaires lisent les
//     memes fichiers `.glsl`. Une fuite qui vivrait uniquement dans du GLSL atteint sous maitre
//     eteint ne serait pas vue.
//   * LA POLICE ET LE TEXTE. C'est l'exclusion la plus importante, et elle est MESUREE, pas
//     supposee. Le systeme est un trio dont deux tiers vivent dans la donnee que les deux
//     binaires PARTAGENT :
//       - le banc de texte : un seul `<lang>COMMON.TXT` ecrit dans `out/jak1/iso` par
//         `goalc/data_compiler/game_text_common.cpp:75`, empile depuis les trois couches de
//         `game/assets/jak1/game_text.gp` (dont nos JSON de casse mixte). `text.gc:157` le
//         charge par ce nom unique et `fake_iso.cpp:60-64` ne scanne que `get_iso_out_dir()` :
//         les bancs purs de ND (`iso_data/jak1/TEXT/`) ne sont JAMAIS atteignables.
//       - les chasses : `*font12-table*` / `*font24-table*` (`font.gc`) portent les avances
//         Urbanist (a = 13,5756 en 12 et 14,5671 en 24, contre 14,25 et 24,0 en stock) ;
//         `font.o` est dans `GAME.CGO` et `ENGINE.CGO`. `grep -ci recharged font.gc` = 0.
//     Ablater le seul tiers gatable (l'atlas, `is_font_atlas`) ne fabrique donc PAS le jeu de
//     Naughty Dog : ca fabrique une chimere — glyphes ND positionnes par des chasses Urbanist
//     sur nos chaines — qu'aucun binaire livrable ne peut egaler. C'est ce que l'essai 1 a
//     mesure comme « 994 px de fuite » (bande y=128..141 du creneau h12 : encre 776 px cote
//     temoin contre 530 cote juge, 29 composantes contre 26, Jaccard 0,38 : pas les memes
//     formes). Et gater cette page rouvrirait le defaut que l'owner a rapporte le 2026-09-02
//     (« ca utilise des glyphs chinois de la font par defaut du jeu »), dont la correction fut
//     precisement de lui retirer toute porte. `is_font_atlas` n'est donc PAS ablate ici ; la
//     fuite reste NOMMEE dans chaque preuve par le compteur `origin_font_master_bypass`, non
//     nul par construction.
//   * ce qui n'est pas sous `#if !AUTOPORT_ORIGIN_ABLATE`. La liste des sites ablates est dans
//     le rapport de l'item ; ce qui n'y est pas n'est pas prouve.

#define AUTOPORT_ORIGIN_ABLATE 0
