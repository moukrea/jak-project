# Restes de l'archivage en cours d'essai et des ecritures de statut perimees : plus d'orphelin, plus de travail invisible, plus de statut ramene en arriere

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par les workers de harness-owner-archive-of-running-item-is-safe et harness-linear-owner-move-reads-fresh-item (reports/<id>/FINDINGS.txt), non corrige ; ouvert par le superviseur le 23/09 sous la delegation de l'owner pour les signalements de harnais.
(1) `orchestrator.py:_kill("archived")` tue le groupe du worker ; un gk de preuve lance hors du groupe n'est pas mesure : orphelin possible. (2) `linear_sync.py:worker_comment_refused` ne vise que les essais : un commentaire du superviseur sur un ticket archive le ressort des archives (on_ticket revive=True), defaisant l'archivage de l'owner. (3) `orchestrator.py:_archived_on_disk` : fenetre de 5 s pendant laquelle le worker ecrit encore reports/<id>/. (4) `_archived_exit` commite le travail coupe sous [autoport/owner-archive], invisible dans status et Linear. (5) `linear_sync.py:1045-1052` adopt_owner_issues choisit l'id sur la copie en memoire : deux adoptions simultanees = deux items au meme id. (6) `backlog.py:set_status(iid, <statut lu en memoire>, champ=...)` reste le seul moyen generique de poser un champ : tout appelant qui « garde » le statut ainsi le ramene en arriere ; scripts de labo reports/ao-prepass-tie-alpha/notes/pin-attempt5.py:31 et reports/perf-codegen-arm64-calls/notes/a10/props.py:23 font de meme.

## Livrable
1. Traiter les six ; en particulier une API `set_field(iid, champ, valeur)` qui ne touche pas au statut, et l'id d'adoption choisi sous verrou.
2. Un commentaire du superviseur sur un ticket archive par l'owner ne le desarchive pas (ou le dit).
3. Le travail coupe par un archivage est nomme dans les notes de l'item.
4. `archive_status_leftovers` = somme des cas fabriques qui reproduisent chacun des six ; doit valoir 0.
CONTROLE POSITIF par cas + CONTROLE NEGATIF.

## Preuve exigee
`archive_status_leftovers == 0` dans `reports/harness-archive-and-status-write-leftovers/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-archive-and-status-write-leftovers x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
