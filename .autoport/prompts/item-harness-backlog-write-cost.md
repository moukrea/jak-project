# Une ecriture du backlog ne tient plus le verrou pendant pres d'une seconde

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par les workers de harness-linear-learned-limit-can-rise / harness-owner-feedback-write-never-loses-a-return / acquis-hud-eco-gauge (reports/<id>/FINDINGS.txt), non corrige. Ouvert par le superviseur le 23/09 sous la delegation de l'owner pour ce type de signalement (« traite comme tu l'entends », JAK-235/237).
`.autoport/lib/backlog.py:_atomic_write/_dump` : chaque ecriture redumpe ~1 Mo de YAML (0,67 s mesure) EN TENANT le verrou ; 4 ecrivains serialises = ~3 s d'attente ; le recensement de harness-owner-feedback-write-never-loses-a-return dure 45-51 s pour 50 ecritures.

## Livrable
1. Mesurer AVANT (duree sous verrou, p50/p95, sur 50 ecritures).
2. Reduire la duree sous verrou (dump hors verrou avec controle de version, dumper C, etc.) sans perdre l'atomicite ni changer le format du fichier.
3. `backlog_write_locked_ms_p95` publie ; porte `backlog_write_slow` = ecritures > 200 ms sous verrou ; doit valoir 0.
CONTROLE POSITIF fabrique + CONTROLE NEGATIF. Publier le denominateur.

## Preuve exigee
`backlog_write_slow == 0` dans `reports/harness-backlog-write-cost/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-backlog-write-cost x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
