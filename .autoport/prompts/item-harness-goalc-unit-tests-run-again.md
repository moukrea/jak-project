# Les tests unitaires du compilateur GOAL tournent de nouveau et sont rebatis avec lui

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par le worker de arm64-integer-division-matches-x86, non corrige ; ouvert sous la delegation de l'owner pour les signalements de harnais.
`build/goalc-test` date du 27/08, n'est jamais rebati par `.autoport/lib/build_x86.sh`, et part en SIGSEGV des le premier test (EmitterAVX.VF_NOP) : AUCUN test unitaire du compilateur n'est executable aujourd'hui. Toute regression de l'emetteur (x86 ou arm64 : division, swizzle, float->int) passe sans bruit.

## Livrable
1. Rebatir goalc-test avec le meme outil de build que gk/goalc (build_x86.sh le couvre), et comprendre le SIGSEGV (binaire perime ou vraie panne).
2. La suite passe (ou chaque echec est nomme et range en item).
3. Une porte de harnais la lance sur tout essai qui touche goalc/.
4. `goalc_unit_tests_broken` = tests en echec ou non lances ; doit valoir 0.
CONTROLE POSITIF (casser une instruction de l'emetteur -> un test rougit) + CONTROLE NEGATIF.

## Preuve exigee
`goalc_unit_tests_broken == 0` dans `reports/harness-goalc-unit-tests-run-again/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-goalc-unit-tests-run-again x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
