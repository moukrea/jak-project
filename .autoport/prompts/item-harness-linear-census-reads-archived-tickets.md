# Les garde-fous qui lisent Linear retrouvent aussi les tickets archives : archiver un ticket ne fait plus rougir un acquis

## Defaut cite
- 2026-09-23 : « Ok »

## Cause connue
Signale par le worker de harness-linear-sync-never-creates-two-tickets-for-one-item (reports/.../FINDINGS.txt), non corrige ; l'owner a dit « Ok » pour l'ouvrir le 23/09 (JAK-229).
`.autoport/lib/census/harness-linear-own-identity.sh:115` cherche le ticket de l'item sans `includeArchived` ; le superviseur a archive JAK-180 le 23/09 a 22:39:55Z (169 tickets termines archives sur ordre de l'owner, quota Linear) -> `linear_author_kind=erreur`, `lid_author_distinct=1`, `linear_identity_defects=1` : un acquis VALIDE rougit sans aucun changement de code. Avec l'archivage automatique (harness-linear-auto-archive-when-space-runs-out), ca se reproduira sur tout ticket archive.

## Livrable
1. Recenser TOUTES les lectures Linear du harnais (census, acquis, linear_sync, owner_sla) qui cherchent un ticket par id ou identifiant sans `includeArchived`.
2. Chacune retrouve le ticket archive (ou le desarchive si elle doit y ecrire).
3. `linear_archived_blind_reads` = lectures qui ratent un ticket archive ; doit valoir 0. L'acquis identite repasse au vert sur JAK-180 archive.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`linear_archived_blind_reads == 0` dans `reports/harness-linear-census-reads-archived-tickets/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-census-reads-archived-tickets x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
