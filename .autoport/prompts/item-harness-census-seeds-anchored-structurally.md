# Les recensements du harnais ne dependent plus d'une ligne de code exacte : une reecriture ne les rend plus muets

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par le worker de harness-archived-census-controls-are-alive (reports/.../FINDINGS.txt), non corrige ; ouvert par le superviseur le 23/09 sous la delegation de l'owner pour les signalements de harnais (« traite comme tu l'entends »).
(1) `lib/census/dead-published-keys-round-2.sh:408` : l'ancre `pbr_coverage_note_draw(` n'existe plus dans game/ (git grep : 0) ; si le recensement l'attend encore, il rend « introuvable » a chaque passage. (2) 18 graines restent semees sur un LITTERAL DE LIGNE (harness-linear-pull-reads-archived-tickets.sh:POS, harness-linear-stale-map-never-fakes-an-owner-move.sh:261-389, harness-linear-relink-keeps-owner-comments.sh:281-283) : vivantes aujourd'hui, mortes a la prochaine reecriture. (3) harness-linear-census-reads-archived-tickets.sh:dispatch_key exclut les cles par ligne. (4) le terme G de harness-archived-census-controls-are-alive ne lit que les blocs python (93/102).

## Livrable
1. Recenser TOUTES les ancres et graines de lib/census/*.sh : lesquelles visent un litteral de ligne, lesquelles sont deja mortes.
2. Re-ancrer sur une forme structurelle (noeud d'appel AST, symbole) ; une ancre introuvable = defaut NOMME, jamais un vert.
3. `census_literal_anchors` = graines/ancres sur litteral de ligne + ancres mortes ; doit valoir 0.
CONTROLE POSITIF (reecrire la ligne visee dans une copie jetable -> le controle rougit encore) + CONTROLE NEGATIF.

## Preuve exigee
`census_literal_anchors == 0` dans `reports/harness-census-seeds-anchored-structurally/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-census-seeds-anchored-structurally x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
