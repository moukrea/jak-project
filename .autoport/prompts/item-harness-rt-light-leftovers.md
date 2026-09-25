# Plus aucune trace de rt-light dans le harnais : proprietes de preuve, recensements et table de correspondance a jour

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par le worker de lighting-rt-light-toggle-removed, non corrige ; ouvert sous la delegation de l'owner pour les signalements de harnais.
`.autoport/lib/proof_run.sh:106,113,1311,1512` et `lib/refset.sh:129` posent encore OG_RT_LIGHT / debug.opengoal.rt.light (plus lus) ; proof_env/proof_props de lighting-local-lights, lighting-legacy-purge, lighting-census les portent ; `lib/census/census-false-reds.sh:249` pointe vers `light_census_rb_bad_u_rt_light_on`, desormais `..._u_lighting_on`.

## Livrable
1. Retirer toutes ces traces.
2. `rt_light_harness_leftovers` = occurrences restantes ; doit valoir 0.
CONTROLE POSITIF + CONTROLE NEGATIF.

## Preuve exigee
`rt_light_harness_leftovers == 0` dans `reports/harness-rt-light-leftovers/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-rt-light-leftovers x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
