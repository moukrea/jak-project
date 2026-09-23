# Un deplacement de ticket fait par l'owner n'est jamais ecrase, perdu ni applique deux fois

## Defaut cite
- 2026-09-23 : « Ok tu peux traiter le tout du coup, comme tu l'entends »
- 2026-09-23 : « Vas-y traite comme tu l'entends »

## Cause connue
Signale par les workers de harness-linear-relink-keeps-owner-comments / harness-linear-stale-map-never-fakes-an-owner-move / harness-wake-unanswered-list-carries-its-age / harness-workers-reply-in-the-owner-thread (reports/<id>/FINDINGS.txt). Owner 23/09 : « Ok tu peux traiter le tout du coup, comme tu l'entends » (pose sur JAK-235, applique aussi a la question JAK-237 posee juste avant).
`.autoport/linear_sync.py:push_existing` : un deplacement de l'owner fait entre la lecture (pull_owner) et l'envoi du meme passage est ECRASE (fenetre de quelques secondes toutes les 30 s). `owner_move` : sous le repli « cle de l'owner » (mode != app), un vrai deplacement sans `state_at` n'est pas applique (auteur indistinguable) et est perdu ; carte ET cliche recules sous le `state_at` : un vrai deplacement deja applique est re-applique (priorite remise en tete, message « Note. » repete).

## Livrable
1. L'envoi relit l'etat Linear juste avant d'ecrire et n'ecrase jamais un changement plus recent de l'owner.
2. Un deplacement deja applique porte une trace (id d'historique) et ne l'est jamais deux fois.
3. Sous le repli d'identite, le deplacement est NOMME a l'owner au lieu d'etre perdu.
4. `owner_moves_lost` = deplacements ecrases + perdus + re-appliques ; doit valoir 0.
CONTROLE POSITIF fabrique (le defaut seme rougit la porte et est NOMME) + CONTROLE NEGATIF (cas sain a 0). Publier le denominateur.

## Preuve exigee
`owner_moves_lost == 0` dans `reports/harness-linear-owner-moves-never-lost/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-owner-moves-never-lost x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
