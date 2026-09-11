#pragma once

// checkpoint_census — LA MESURE DE L'ITEM `builder-checkpoint-steals-work`.
//
// CE QUE L'ITEM DEMANDE. « Un checkpoint du constructeur n'emporte plus le travail d'un
// chantier », porte `checkpoint_stolen_files == 0`. La grandeur ne porte pas sur une image : elle
// porte sur l'historique du depot et sur les scripts du harnais. Le moteur n'en sait rien — mais
// `lib/proof_run.sh` ne moissonne QUE la sortie du moteur, et `validators/generic.sh` ne lit que
// `proof.txt`. Ce module est le seul chemin honnete entre les deux.
//
// LE PARTAGE DU TRAVAIL, ET POURQUOI IL EST LA.
//   - `.autoport/lib/checkpoint_census.py` RECOLTE : il marche l'historique, audite les scripts,
//     et lance `lib/checkpoint_selftest.sh` (le bac a sable). Il n'affirme rien, il imprime des
//     `cle=valeur`.
//   - CE FICHIER JUGE : la somme qui alimente la porte, et la polarite « inconnu = defaut », sont
//     compilees dans `gk`. Le validateur epingle ce binaire par son sha et refuse toute source
//     moteur plus recente que la preuve : le verdict est donc sous garde, meme si la recolte,
//     elle, vit dans un script.
//   - Les empreintes des scripts recoltes sont PUBLIEES (`checkpoint_*_sha`) : la preuve nomme
//     les octets qu'elle a juges, pas un chemin.
//
// « INCONNU = DEFAUT ». Chaque temoin manquant ou degenere AJOUTE au compte, il ne le laisse pas
// a zero : un recensement qui n'a pas tourne, un bac a sable ou il n'y avait rien a voler, un
// controle positif muet, rendent la porte ROUGE. Sans cela une porte `== 0` sur un nettoyage est
// verte par INACTION — c'est le piege que ce harnais a deja paye plusieurs fois.
//
// CE QU'IL NE FAIT PAS. Il ne tourne que si le harnais NOMME cet item (`AUTOPORT_FEATURE`), une
// seule fois par course, et ne change strictement rien au jeu. Sur l'appareil il n'y a ni depot
// ni python : la passe sort a sa premiere ligne, et l'item est `device: false`.

namespace checkpoint_census {

// Appele une fois par image depuis `pc_autoport_frame`. Muet hors mesure.
void tick();

}  // namespace checkpoint_census
