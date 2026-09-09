# Pas d'ocean, pas de vagues calculees

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
ocean.gc:457-468 : ocean-interp-wave et ocean-generate-verts (VU0 micro emules en mips2c scalaire, 2048 sommets) tournent chaque image AVANT le test *ocean-map*. Gaspillage pur dans les 16 niveaux sans ocean.

## Livrable
Forme minimale seulement : sans carte d'ocean, ni interpolation ni sommets. Le moteur publie ocean_work_without_map (images ou l'interp a tourne sans carte) et goal_bucket_ms_ocean avant/apres. refset_replay_maxdiff == 0 en village1-hut ET sur un vantage avec ocean (beach). Verifier les autres lecteurs de *ocean-verts* (transitions) avant de conditionner.

## Preuve exigee
`ocean_work_without_map == 0` dans `reports/perf-ocean-idle/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-ocean-idle x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : identique au pixel ; la cadence dans les niveaux sans mer (village1, jungle, misty...).

## Hors perimetre
Rien de plus : water-ocean-mesh capte la houle ND au DMA near (ocean-near-add-heights lit *ocean-heights*) pour sa couche A ; toute condition supplementaire lui appartient (SPEC eau 5.2). Ne touche a aucune feature validee.
