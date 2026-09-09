# float vers int, division et swizzle en une ou deux instructions

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
IGenARM64.cpp : float->int scalaire = 9 instr (:2020-2050, parite de saturation x86 par 2 FCMP + 2 CSEL), division entiere 9-10 (:1174-1326, spill de X8), swizzle general = ORR + 4 INS (:2596-2620) au lieu de TBL/EXT/ZIP (98 sites de produit vectoriel, 2 par cross), .ftoi.vf 5, vpshuflw/hw 6. Collision et physique dependent de la saturation : parite a re-prouver (Gcollision-systemic).

## Livrable
FCVTZS + un CSEL, SDIV 3 operandes sans spill (CBNZ+UDF conserve), TBL/EXT/ZIP pour les motifs 0x09/0x12 et le cas general. codegen_lot_defects comme au lot 1, plus un test de parite exhaustif float->int sur les bornes (NaN, +-inf, > INT_MAX) contre x86.

## Preuve exigee
`codegen_lot_defects == 0` dans `reports/perf-codegen-arm64-scalar/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-codegen-arm64-scalar device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : identique au pixel et a la pose.

## Hors perimetre
Aucun changement de resultat numerique. Ne touche a aucune feature validee.
