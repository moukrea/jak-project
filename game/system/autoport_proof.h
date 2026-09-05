#pragma once

// autoport_proof — LE PUBLICATEUR QUE `lib/proof_run.sh` MOISSONNE.
//
// POURQUOI CE FICHIER EXISTE.
// ---------------------------
// `.autoport/lib/proof_run.sh` ecrit `reports/<id>/proof.txt` et `validators/generic.sh` le juge.
// Le validateur exige DEUX choses que seul le moteur peut produire :
//
//     FEATURE <id-de-l-item> armed=<0|1> hits=<n>      (n > 0, sinon « rien ne prouve que la
//                                                       feature a tire »)
//     <cle>=<valeur>                                   (la grandeur nommee par le `gate:` de
//                                                       l'item, SEULE SUR SA LIGNE)
//
// Aucune des deux n'existait : `grep -rn "AUTOPORT_FEATURE\|debug.opengoal.feature" game/ common/`
// rendait zero le 2026-09-03, alors que `proof_run.sh` pose les deux depuis sa premiere version.
// L'en-tete de `proof_run.sh` le dit lui-meme : « CE QUE LE MOTEUR DOIT EMETTRE (pas encore
// branche) ». Tant que ce module n'existe pas, AUCUN item du backlog ne peut passer sa porte,
// quel que soit le travail fait sur le defaut.
//
// CE QUE CE MODULE N'EST PAS. Il ne juge rien et ne connait aucun item. Il transporte : un
// identifiant lu dans l'environnement (bureau) ou dans une propriete systeme (appareil), un
// compteur que le code de la feature incremente lui-meme, et des couples cle/valeur que ce meme
// code publie. Le verdict reste au validateur.
//
// L'ARMEMENT, ET POURQUOI LE DEFAUT EST « ARME ».
// ----------------------------------------------
// `armed()` rend VRAI quand rien n'est pose. C'est deliberé : une correction livree derriere un
// drapeau eteint par defaut n'existe pas pour l'owner — il joue le binaire tel quel, sans
// propriete. Le desarmement n'a lieu QUE si la propriete `debug.opengoal.feature` nomme
// exactement l'item concerne ET que `debug.opengoal.feature.armed` vaut 0 : c'est le bras
// d'ablation que `proof_run.sh --off` demande, et rien d'autre ne peut y tomber par accident.
//
// LE COMPTEUR. `note_hit()` ne compte que quand la feature est ARMEE. C'est ce qui rend
// l'ablation lisible : le bras desarme doit publier `hits=0`, sinon il ne prouve pas que le
// chemin de code s'est bien tu. Un compteur qui monte des deux cotes ne separe rien.
//
// LES IMAGES. `frame_tick()` publie `AUTOPORT-FRAMES n=<images>`. `proof_run.sh` cherche ce motif
// (ou `PACE-SWAP n=`, ou `A35-RENDER frame=`) pour remplir `frames=` ; sur l'appareil AUCUN des
// trois n'etait emis, donc toute preuve appareil sortait avec `frames=0` et le validateur la
// refusait pour « rien n'a ete dessine assez longtemps ». C'est une panne d'instrument, pas du
// jeu.

#include <cstdint>

namespace autoport_proof {

// Identifiant d'item demande par le harnais, "" si aucun. Env `AUTOPORT_FEATURE` (bureau) ou
// propriete `debug.opengoal.feature` (Android). Lu une seule fois, au premier appel.
const char* feature_id();

// Vrai si le harnais a demande CET item. Un code de feature s'en sert pour savoir s'il est sous
// mesure ; il ne doit JAMAIS s'en servir pour changer son comportement en dehors de l'ablation.
bool feature_is(const char* id);

// Etat d'armement. VRAI par defaut (voir l'en-tete). Faux uniquement quand le harnais a nomme un
// item ET pose `armed=0`.
bool armed();

// Etat d'armement POUR UN ITEM NOMME. Identique a `armed()` quand le harnais parle de CET item,
// VRAI dans tous les autres cas. `armed()` est global : si le harnais mesure l'item A avec
// `armed=0`, il desarme du meme coup le correctif de l'item B, qui n'a rien demande — deux
// features livrees se desarment l'une l'autre et la course ne mesure plus le binaire de l'owner.
// Un correctif qui se debraye consulte donc CETTE fonction avec son propre identifiant.
bool armed_for(const char* id);

// Le chemin de code de la feature vient de tourner. No-op quand la feature est desarmee : c'est
// ce qui fait la difference entre les deux bras de l'ablation.
void note_hit(uint64_t n = 1);

// Une grandeur mesuree, publiee telle quelle sur sa propre ligne (`cle=valeur`). La DERNIERE
// valeur publiee pour une cle gagne — c'est la regle de moissonnage de proof_run.sh. La cle doit
// respecter `[A-Za-z_][A-Za-z0-9_]*` ; une cle qui ne la respecte pas est refusee en silence
// plutot que d'ecrire une ligne que le moissonneur ignorerait.
void publish(const char* key, uint64_t value);

// La meme chose pour une valeur qui n'est pas un entier (un rapport, un coefficient de variation) :
// publiee telle quelle, sans espace (tout caractere blanc est remplace par `_`, sinon le moissonneur
// de proof_run.sh — `^cle=[^[:space:]]+$` — ignorerait la ligne). Une cle porte soit un entier soit
// un texte : le dernier `publish*` gagne.
void publish_text(const char* key, const char* value);

// Une image de plus. A appeler une fois par image, du meme endroit que le reste du recensement.
// Emet periodiquement le bloc complet (images, FEATURE, toutes les cles).
void frame_tick();

// Emet le bloc complet tout de suite (fin de scene, fin de course).
void flush();

}  // namespace autoport_proof
