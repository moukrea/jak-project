# Un appel de fonction GOAL coute deux instructions, pas huit

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Backend arm64 = traduction 1:1 du modele x86 (IGenARM64.cpp). Appel : ADD + 3 STP + BLR + 3 LDP (:1831-1882) pour sauver X3/X5/X10/X11/X12/X23 « saved » x86 mais caller-saved en AAPCS. Symbole : ADRP+ADD+LDR (IR.cpp:636-674, marqueur A5), s7/X14 inutilise. Acces memoire : ADD X16,Xaddr,X15 avant chaque load/store (:1198-1347), jamais [Xn,Xm]. Trampoline GOAL->C ~45 instr (kscheme.cpp jak1:856-982) avec check X30 toujours actif. pc-prof appele 20-30 fois par image vers un stub (gcommon.gc:29).

## Livrable
Lot 1 : enrobage d'appel reduit aux saved vivants (ou sauvegarde en prologue callee), LDR [X14,#imm12] pour les symboles a moins de 16 Ko, forme [Xn,Xm] ou base pre-ajoutee pour les acces, pc-prof branche sur perf-instruments ou coupe sans recepteur. Le moteur publie codegen_lot_defects = (refset_replay_maxdiff != 0) + (boot non survecu 600 images) + (instructions par appel sur 5 fonctions marqueurs > cible). goalc rebati, GAME/ENGINE.CGO regeneres et verifies par grep -a, references refset recapturees une fois avec cause nommee.

## Preuve exigee
`codegen_lot_defects == 0` dans `reports/perf-codegen-arm64-calls/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-codegen-arm64-calls device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : identique au pixel ; goal_busy_ms baisse.

## Hors perimetre
Pas de changement de convention d'appel visible du C++ (asm_funcs_arm64.s, kscheme) dans ce lot. Ne touche a aucune feature validee.
