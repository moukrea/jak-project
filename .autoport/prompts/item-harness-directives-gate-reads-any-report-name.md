# La porte DIRECTIVES ne brule plus un essai vert parce que le rapport s'appelle report.md au lieu de report.txt

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par le worker de lighting-shadows : `orchestrator.py:~2488` (GATE DIRECTIVES, livree par harness-directives-promises-are-implemented) ne lit que reports/<id>/report.txt ; l'essai 8 de lighting-shadows avait une porte VERTE et un rapport ecrit sous report.md : l'essai entier a ete refuse et COMPTE dans le plafond. Une porte de forme qui brule un essai de fond = defaut prioritaire (elle peut frapper tous les chantiers).

## Livrable
1. La porte trouve la ligne DIRECTIVES dans le rapport quel que soit son nom (report.txt, report.md, handoff.md) ou, a defaut, dit exactement quel fichier elle attend AVANT la fin de l'essai (au lancement).
2. Un refus de pure forme n'est jamais compte dans le plafond : il est nomme et l'essai est rejoue.
3. Recenser les essais deja refuses pour ce motif et rendre leur budget.
4. `directives_gate_misnamed_refusals` ; doit valoir 0.
CONTROLE POSITIF + CONTROLE NEGATIF.

## Preuve exigee
`directives_gate_misnamed_refusals == 0` dans `reports/harness-directives-gate-reads-any-report-name/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-directives-gate-reads-any-report-name x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
