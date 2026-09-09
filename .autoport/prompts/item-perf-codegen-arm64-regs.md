# Le compilateur GOAL utilise les 31 registres de l'arm64

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Register.h:135-142 : mapping x86 conserve, 10 GPR et 14 V allouables (Register.cpp:60), X18-X28 et V3-V15 morts. Allocator_v2.cpp:657-709 force les feeders de pointeur de fonction en saved-first (A6). Trampolines C : 4 STP Q24-Q31 + check X30 (7 instr) a chaque FFI. Fichiers verrouilles par le cookbook (IGenARM64.h, IR.h).

## Livrable
X18-X28 ouverts comme saved supplementaires (callee-saved AAPCS : gratuits a travers les appels C), V3-V15 comme temporaires, trampoline allege quand aucun Q n'est vivant, check X30 sous prop. codegen_lot_defects comme au lot 1 ; spills par fonction publies avant/apres sur 5 marqueurs.

## Preuve exigee
`codegen_lot_defects == 0` dans `reports/perf-codegen-arm64-regs/proof.txt`.
Le proof se produit par `lib/proof_run.sh perf-codegen-arm64-regs device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : identique au pixel et a la pose.

## Hors perimetre
Pas de changement de l'ABI GOAL<->C visible des .s sans mise a jour des deux cotes dans le meme commit. Ne touche a aucune feature validee.
