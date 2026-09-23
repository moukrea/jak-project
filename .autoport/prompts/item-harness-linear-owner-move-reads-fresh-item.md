# Quand l'owner deplace un ticket, la synchro decide sur l'etat FRAIS de l'item : aucune note ni statut ecrit entre-temps n'est ecrase

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par les workers de harness-linear-learned-limit-can-rise / harness-owner-feedback-write-never-loses-a-return / acquis-hud-eco-gauge (reports/<id>/FINDINGS.txt), non corrige. Ouvert par le superviseur le 23/09 sous la delegation de l'owner pour ce type de signalement (« traite comme tu l'entends », JAK-235/237).
`.autoport/linear_sync.py:946-963` : la reaction a un deplacement Linear decide sur le statut LU EN MEMOIRE (`s = it["status"]`) et recompose `notes` depuis la copie en memoire (953) avant set_status : une note ajoutee entre-temps par un autre ecrivain est ecrasee. Meme famille que harness-owner-feedback-write-never-loses-a-return (corrige pour owner_feedback seulement).

## Livrable
1. Relire l'item sous le verrou avant de decider et de composer les notes.
2. Recenser les autres lecture-en-memoire-puis-ecriture de linear_sync sur le backlog.
3. `linear_sync_stale_item_writes` ; doit valoir 0.
CONTROLE POSITIF fabrique + CONTROLE NEGATIF. Publier le denominateur.

## Preuve exigee
`linear_sync_stale_item_writes == 0` dans `reports/harness-linear-owner-move-reads-fresh-item/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-linear-owner-move-reads-fresh-item x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
