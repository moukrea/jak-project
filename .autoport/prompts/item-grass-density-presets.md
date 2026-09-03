# Cinq paliers de densite d'herbe au lieu d'un curseur

## Defaut cite
- 2026-08-30 : « on s'en fiche de changer la densite au poil de cul, on veut juste plus ou moins dense — very low / low / medium / high / very high c'est assez, donc on peut pre-calculer le tout et eviter le chemin lourd »
- 2026-08-30 : « sur la plage [...] ca n'a jamais ete visible, tu peux completement dismiss »

## Cause connue
Aucun cycle n'a tourne. L'owner a deja tranche la forme : cinq paliers nommes, pas un curseur continu.

## Livrable
Cinq paliers nommes very low / low / medium / high / very high dans les options, pre-calcules, avec le cout memoire de chacun.

## Preuve exigee
Aucun critere machine n'est encore ecrit pour cet item. Ecris-le d'abord (une seule ligne `CLE=VALEUR` emise par le moteur), pose-le dans `backlog.yaml`, puis prouve-le.
Le proof se produit par `lib/proof_run.sh grass-density-presets x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged > densite d'herbe : cinq paliers.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
