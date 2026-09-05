# Le systeme de build unifie, le packaging et l'installation

## Defaut cite
- 2026-07-17 : « je pense 217 en premier … en autonomie »

## Cause connue
Aucun cycle n'a encore etabli de cause sur cet item.

## Livrable
Le defaut ci-dessus corrige dans le moteur, livre dans un build, et une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh recharged-buildsys device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : l'installation elle-meme : telecharge l'APK et l'archive d'assets, installe par-dessus, verifie que tes sauvegardes sont la.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
