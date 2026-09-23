# Un chantier invisible (harnais, rien a tester par l'owner) ne parle jamais de capture ni de build a tester dans son commentaire

## Defaut cite
- 2026-09-23 : « Bah c'est le genre de chantier qui nécessite pas de capture, donc c'est attendu qu'il n'y ait pas de capture, gaspillage d'énergie là ! »

## Cause connue
JAK-240 (harness-linear-learned-limit-can-rise, owner_test=False), 23/09 05:35 : le commentaire de fin du worker se termine par « Capture impossible : reglage interne du harnais, rien ne change a l'ecran. Build a tester : 2971e3-c666da ». La porte CLOSE-GATE/capture (orchestrator.py:2445) ne s'applique PAS a cet item (owner_test=False) : le worker l'a ecrit par habitude, lu dans DIRECTIVES.md:91-96 (paragraphe capture, global a tous les items). Bruit pour l'owner, et un « build a tester » sur un chantier qu'il n'a pas a tester.

## Livrable
1. Recenser AVANT : commentaires de fin d'essai sur des items owner_test=False qui mentionnent capture ou build a tester (7 jours).
2. Structurel, pas de prose : `linear_sync.py --comment` sur un item owner_test=False refuse `--no-capture`/`--attach` de capture et retire la ligne automatique « Build a tester » ; le paragraphe capture n'est rendu dans le prompt que pour un item owner_test=True (sortir la regle de DIRECTIVES vers le rendu du prompt si c'est le seul moyen).
3. `invisible_item_capture_mentions` = commentaires d'items owner_test=False qui parlent de capture ou de build a tester ; doit valoir 0.
CONTROLE POSITIF (item invisible fabrique qui tente --no-capture -> refuse) + CONTROLE NEGATIF (item visible : capture toujours exigee).

## Preuve exigee
`invisible_item_capture_mentions == 0` dans `reports/harness-invisible-item-comment-has-no-capture-boilerplate/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-invisible-item-comment-has-no-capture-boilerplate x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
