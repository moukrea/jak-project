# Un build depuis zero doit donner le meme jeu que le notre

## Defaut cite
- 2026-08-29 : « faut t'assurer qu'elle revienne pas par erreur, c'est un truc qui doit se corriger automatiquement au build from scratch quand ça exporte le modèle HD de Jak 2 ou 3 (idem pour les bones, retargeting des squelettes, physique et compagnie... Un utilisateur qui build le jeu from scratch devrait pouvoir avoir le même état que nous) »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh build-from-scratch x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a tester en jeu : c'est la reproductibilite du build.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
