# Quand l'espace Linear approche de sa limite de tickets, la synchro archive d'elle-meme les tickets termines, et elle ne plante plus sur un ticket archive

## Defaut cite
- 2026-09-23 : « Archive les tickets terminés, ça devrait se faire automatiquement quand on a un soucis de place. »

## Cause connue
23/09 : `linear_sync.py` plantait a chaque passage sur `issueCreate` -> USAGE_LIMIT_EXCEEDED (« free issue limit », metrique activeIssueCount) : 275 tickets actifs pour une limite de 250 du plan gratuit. Aucun chantier neuf ne recevait son ticket. Le superviseur a archive a la main 169 tickets (157 termines + 12 annules) : reste 106 actifs.
DEUXIEME DEFAUT revele par cet archivage : la synchro plante ensuite (RuntimeError, `Entity not found: Issue`) des qu'elle veut commenter un ticket archive — `announce_verdicts` (linear_sync.py:1132) -> `post_comment` (588). 4 tickets ont du etre desarchives a la main (JAK-176, 191, 192, 193). Un seul appel qui echoue fait tomber TOUTE la synchro, pull compris ou non selon l'ordre.

## Livrable
1. La synchro connait la limite et le nombre de tickets actifs ; au-dela d'un seuil (ex. 85 %), elle archive les tickets termines/annules les plus anciens jusqu'a redescendre sous le seuil, et le journalise.
2. Avant de commenter ou mettre a jour un ticket archive, elle le desarchive (ou le saute en le NOMMANT) ; un appel Linear qui echoue sur un ticket n'arrete plus toute la synchro : il est compte et nomme.
3. USAGE_LIMIT_EXCEEDED declenche l'archivage puis UNE nouvelle tentative, jamais un plantage.
4. `linear_space_defects` = plantages de synchro sur limite ou ticket archive + chantiers actifs sans ticket ; doit valoir 0.
CONTROLE POSITIF : espace simule au-dessus du seuil -> archivage declenche ; ticket archive commente -> pas de plantage. CONTROLE NEGATIF : sous le seuil, rien n'est archive.

## Preuve exigee
`linear_space_defects == 0` dans `reports/harness-linear-auto-archive-when-space-runs-out/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-auto-archive-when-space-runs-out x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
