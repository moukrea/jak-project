#pragma once

// naming_census — LA MESURE DE L'ITEM `recharged-naming`.
//
// CE QUE L'OWNER DEMANDE (2026-09-11, mot pour mot) : « "Jak and Daxter: The Precursor Legacy"
// doit etre nomme "Jak and Daxter: Recharged" (sans mention d'OpenGOAL) ».
//
// LE PIEGE QU'ON REFUSE : UNE LISTE DE SITES NE PROUVE QUE LA LISTE.
// ------------------------------------------------------------------
// La facon evidente de « recenser chaque endroit ou le jeu se nomme » est d'ecrire la liste des
// endroits connus et de verifier chacun. Cette mesure est vide : elle rend zero le jour ou un
// vingt-et-unieme site apparait ailleurs, et zero encore le jour ou un site de la liste cesse
// d'exister. Ici on BALAIE des artefacts entiers et on laisse le CONTENU designer les sites :
//
//   1. LES DONNEES LIVREES. Tout `*.CGO`, `*.DGO`, `*.TXT`, `*.go` du dossier iso est lu OCTET
//      PAR OCTET et on y compte les jetons interdits. Aucune connaissance du format n'est
//      requise, donc aucun site ne peut se cacher derriere un conteneur qu'on aurait oublie de
//      savoir lire : le litteral GOAL du statut Discord, le bandeau speedrun, les bancs de
//      texte des 23 langues et les sous-titres tombent dans le meme filet.
//   2. LES BANCS DE TEXTE, PAR IDENTIFIANT ET PAR LANGUE. Le balayage brut dit qu'un jeton
//      interdit n'est nulle part ; il ne dit pas que le bon nom est quelque part. Les bancs
//      `<n>COMMON.TXT` sont donc relus champ par champ et la ligne-titre de CHAQUE langue
//      installee (`#xf06` + `#xf07`, ce que `draw-title-credits` dessine) doit valoir
//      exactement le nom demande. Une langue ou elle manque est un site FAUX, pas un site
//      absent : c'est la « chaine traduite oubliee » du livrable.
//   3. LES SITES D'EXECUTION. Le titre que SDL porte REELLEMENT sur la fenetre et le nom donne
//      au mixeur audio de l'OS, releves au point d'appel par `note_product_name_use`
//      (common/versions/versions.h) et relus ici. Un site releve mais jamais ecrit se voit :
//      il manque a l'appel et le recensement est declare VIDE.
//   4. L'EMPAQUETAGE. Le nom au lanceur Android ne vient d'aucun code que ce binaire execute :
//      il est fige par gradle dans `app_name`. On lit donc les fichiers qui le DECLARENT et on
//      juge chaque chaine entre guillemets qui nomme un jeu. C'est une lecture de source, pas
//      d'APK, et le rapport le dit : `naming_pkg_sites` publie combien de declarations ont ete
//      trouvees, pour qu'un zero obtenu parce que le depot n'est pas lisible ne puisse pas se
//      lire « rien a redire ».
//
// LES JETONS INTERDITS, ET POURQUOI PAS « Precursor » TOUT SEUL.
// -------------------------------------------------------------
// Les Precurseurs sont un PEUPLE du jeu : « Lost Precursor City », « Precursor orbs », « 90
// Precursor orbs » — mesure du 2026-09-11 : le mot apparait dans 34 des 46 bancs livres. Le
// jeton est donc « Precursor Legacy » (insensible a la casse : de-DE portait « PRECURSOR
// LEGACY »), jamais « Precursor ».
// « OpenGOAL » se compte en casse EXACTE : l'identifiant de paquet `org.opengoal.gk.jak1` et
// les chemins `/storage/emulated/0/OpenGOAL` sont hors perimetre (les renommer casse les
// installations et les sauvegardes de l'owner), et la casse les separe toute seule.
// Trois emplois d'« OpenGOAL » dans les donnees livrees ne nomment PAS le produit et sont
// comptes a part, par leur CONTEXTE et non par leur fichier (`naming_data_opengoal_tooling`) :
//   « Created by OpenGOAL build »        — estampille d'outil dans chaque `-ag.go`, jamais lue
//                                          par le joueur ;
//   « not supported in OpenGOAL »        — message d'erreur du noyau vers la console.
// Tout autre « OpenGOAL » dans les donnees livrees compte comme un site faux. C'est ce qui a
// rendu le bandeau speedrun (« OpenGOAL Version: », GAME.CGO + ENGINE.CGO) visible.
//
// LA VACUITE EST UN ECHEC, PAS UN ZERO. Un instrument qui n'a rien regarde ne dit pas « zero
// defaut » : moins de 20 langues lues, moins de 100 fichiers de donnees balayes, la ligne-titre
// d'aucune langue trouvee, un site d'execution manquant ou aucune declaration d'empaquetage
// lue, et `naming_wrong_sites` publie une sentinelle hors de portee de la porte.

#include <cstdint>

namespace naming_census {

// Une passe complete. Appelee depuis `pc_autoport_frame()`. Ne fait rien tant que le harnais
// n'a pas nomme cet item : le balayage lit 223 Mo de donnees livrees, c'est un instrument de
// mesure et il n'a aucune raison de couter une seconde au joueur. La CORRECTION, elle, est dans
// les donnees et les chaines : elle ne depend d'aucun drapeau.
void tick();

}  // namespace naming_census
