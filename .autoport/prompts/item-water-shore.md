> LIS D'ABORD `prompts/item-water-shore-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Des vagues tranquilles qui arrivent une a une et remontent le sable

## Defaut cite
- 2026-09-09 : « bah je valide, beau boulot ! »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-eau.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. La houle ND monte et descend de +/-0,75 m mais aucune vague n'ARRIVE ; le rivage est un masque d'alpha a 4 couleurs, aucune ecume nommee (SPEC 2.1). Une bande d'ecume constante exige une DISTANCE au rivage, pas une profondeur (SPEC 1.3 d3).

## Livrable
Le compagnon <niveau>.waterbake (shore_sdf par jump flood, shore_dir, floor_depth, flow) produit par tools/water_bake depuis la collision croisee avec le fr3, charge a cote du fr3, ignore proprement si absent/perime (waterbake_missing). Vagues GEOMETRIQUES en vertex en 4 phases sur d (houle 40->12 m, cambrure 12->3 m par la raideur Q, deferlement 3->0 m, jet de rive 0->-4 m), plafond 0,30 m, periode ~7 s, aucune ecume au large ; trois ecumes ; sable mouille via shade(). SPEC 5.5. Publie shore_wave_amp_max_mm (<=300), shore_runup_max_m (<=4), shore_wave_period_s, shore_band_width_var. PREUVE : `FEATURE water-shore armed=1 hits=<vagues arrivees a d=0 (comptees au deferlement)>` + la ligne `wat […suite dans le contrat]

## Preuve exigee
`waterbake_sdf_coverage_pct == 100` dans `reports/water-shore/proof.txt`.
Le proof se produit par `lib/proof_run.sh water-shore device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : la plage de Sandover (beach) : des vagues calmes qui arrivent, se cambrent, deferlent en ecume et lechent le sable avant de se retirer.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_water OFF — et tout sous-reglage d'eau se garde sur recharged_water, jamais sur le master seul (SPEC 1.2 regle 1, 7). La hauteur de JEU (ocean-get-height, ripple-find-height) ne change pas d'un millimetre (regle 2). Aucune physique : l'interaction est simulee pour de faux (SPEC 1.4). Ne touche a aucune feature validee. Pas de mesure visuelle. Pas de tempete, pas de vague au-dessus de 0,30 m. La borne |visuel - jeu| <= 0,45 m reste publiee.
