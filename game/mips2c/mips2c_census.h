#pragma once

// mips2c_census — QUI TOURNE, ET COMBIEN DE TEMPS, DANS LES FONCTIONS MIPS2C.
//
// POURQUOI CE FICHIER EXISTE (perf-mips2c-neon, essai 10).
// -------------------------------------------------------
// Neuf essais ont cherche un noyau vectorise bit-a-bit sans jamais MESURER ce que les noyaux
// mips2c coutent. L'owner demande, le 16/09 : « t'es sur qu'il n'y a aucun gain ? ». Un candidat
// de plus ne repond pas a cette question : seul un chiffre le fait. Le plafond du gain
// atteignable par une vectorisation PARFAITE de tout mips2c est, exactement, le temps passe
// dans mips2c. Ce recensement le produit.
//
// LE POINT D'APPEL UNIQUE. `LinkedFunctionTable::reg()` est le SEUL endroit ou le pointeur C++
// d'une fonction mips2c est lu pour etre grave dans le stub GOAL (x86 mips2c_table.cpp:709,
// arm64 mips2c_table_jak1_arm64.cpp). Le code GOAL n'appelle jamais `execute()` autrement : il
// saute au stub. Substituer le pointeur ICI couvre les 94 fonctions jak1 sans toucher un seul
// corps — et une liste de sites connus n'aurait prouve que la liste.
//
// CE QUE LE BINAIRE DE L'OWNER VOIT : RIEN. Le shim n'est pose que si le harnais NOMME cet item
// (`autoport_proof::feature_is`), jamais sur `armed()` — qui rend vrai par defaut et mettrait
// donc l'instrument dans le jeu livre. Hors mesure, `wrap()` rend `exec` inchange et le stub
// grave est celui d'avant, a l'octet pres.

#include "common/common_types.h"

namespace Mips2C {
namespace census {

// Rend le pointeur a graver dans le stub : un shim qui compte et chronometre quand le harnais
// mesure cet item, `exec` lui-meme sinon. `name` est le nom GOAL enregistre.
u64 (*wrap(const char* name, u64 (*exec)(void*)))(void*);

// Publie le recensement. Appele une fois par image sur le fil GOAL.
void frame_boundary();

}  // namespace census
}  // namespace Mips2C
