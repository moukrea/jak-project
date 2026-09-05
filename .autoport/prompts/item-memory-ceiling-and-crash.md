# Chargement interminable et plantage par manque de memoire

## Defaut cite
- 2026-08-26 : « le logo apparait bien apres le son qui est sense etre la au moment de son apparition [...] C'est je crois le pire truc honnetement »
- 2026-08-26 : « le logo apparaît bien après le son qui est sensé être là au moment de son apparition (donc on le voit jamais casser au travers de l'écran noir avec le halo lumineux comme c'est prévu dans le jeu, alors qu'aucun problème sur x86, Redmi ou Honor... C'est je crois le pire truc honnêtement »
- 2026-08-26 : « ça crash quand je charge la partie (black screen avec la musique en fond... puis crash) »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh memory-ceiling-and-crash device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : charge une sauvegarde et enchaine trois niveaux : plus de chargement interminable ni de plantage.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
