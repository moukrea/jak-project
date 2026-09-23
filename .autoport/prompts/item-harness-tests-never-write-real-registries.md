# Les tests du harnais n'ecrivent plus dans les vrais journaux du harnais, et aucun commentaire Linear ne part sans son chantier

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par les workers de harness-linear-owner-moves-never-lost / harness-linear-archived-structures-not-recreated / harness-invisible-item-comment-has-no-capture-boilerplate / harness-linear-relinks-closed-tickets (reports/<id>/FINDINGS.txt), non corrige ; ouvert par le superviseur le 23/09 sous la delegation de l'owner pour les signalements de harnais.
`tests/harness/test_loop.py`, `tests/harness/test_attempt.py` ecrivent dans le VRAI registre logs/linear_comments.jsonl (60 lignes sur 134 aux items fictifs item-d / item-b), lu par CLOSE-GATE/capture. `linear_sync.py:post_comment` (_rec_of sans _CTX['mp']) : 11 lignes du registre ont item="" -> ces messages echappent a la porte capture et au garde INVISIBLE-CAPTURE.

## Livrable
1. Les tests ecrivent dans un dossier jetable (variable d'environnement), jamais dans .autoport/logs.
2. Un commentaire sans item identifie est refuse ou rattache.
3. Purger les 60 lignes fictives du registre.
4. `registry_pollution` = lignes fictives + lignes sans item ; doit valoir 0.
CONTROLE POSITIF fabrique + CONTROLE NEGATIF. Publier le denominateur.

## Preuve exigee
`registry_pollution == 0` dans `reports/harness-tests-never-write-real-registries/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-tests-never-write-real-registries x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
