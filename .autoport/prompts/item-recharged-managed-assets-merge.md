# Le gestionnaire d'assets avec installation reprenable

## Defaut cite
- 2026-08-26 : « d'abord la branche dont je viens de parler à absorber nickel (dans le framework, pas toi tout seul en autonomie) »
- 2026-08-26 : « le logo apparait bien apres le son qui est sense etre la au moment de son apparition [...] C'est je crois le pire truc honnetement »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh recharged-managed-assets-merge device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : l'installation des assets : coupe-la en cours et relance-la, elle doit reprendre.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
