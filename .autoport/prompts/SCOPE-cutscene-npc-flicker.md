# Périmètre — les PNJ clignotent pendant les cinématiques

## Le défaut, dans les mots de l'owner (2026-08-31, puis 2026-09-03)

> « le problème des modèles des PNJ qui apparaissent, disparaissent et réapparaissent
> plusieurs fois pendant les cinématiques est revenu ! c'est pas la première fois que ça se
> produit, ça me saoule un peu ! » — puis, sur le build du 2 septembre : « bah non c'est
> toujours pété ».

Ce sont les modèles de PNJ, pas Jak ni Daxter. Plusieurs cycles apparition/disparition dans
une même cinématique. Purement visuel : il ne signale aucun effet sur le déroulement.

## Ce qui est déjà établi

* La naissance d'un acteur est conditionnée à la visibilité caméra (établi sur les caisses de
  Sandover). Une cinématique coupe d'un cadrage à l'autre : un PNJ sorti du champ peut être
  défait puis refait à chaque coupe. Même mécanisme, autre objet.
* Le symptôme a déjà été corrigé au moins une fois et il est revenu. Une correction qui ne
  tient pas n'a pas atteint la cause : elle a supprimé le symptôme.

## Livrable

1. La cause nommée, avec le site de code qui la produit, et pourquoi la correction précédente
   n'a pas tenu.
2. Le correctif au point de production, pas au point de constat.
3. Une garde de non-régression que le harnais exécute à chaque fermeture.

## Preuve

Le moteur émet le compteur d'épisodes ; `lib/proof_run.sh` écrit `proof.txt` ;
`validators/generic.sh` juge le `gate:` de l'item. Tu n'écris aucun de ces champs à la main.
Un run sur le Redmi `eae4df44` suffit ; l'ablation seulement si le validateur la demande.

## Hors périmètre

Les modèles HD eux-mêmes (chaîne de reciblage), les cinématiques sautées, la caméra. Si la
mesure montre que le défaut n'existe que sur les modèles HD, dis-le et arrête-toi là : c'est
un autre item.
