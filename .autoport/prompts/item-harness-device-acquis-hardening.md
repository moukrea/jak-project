# Les acquis sur appareil partagent une seule garde de preuve, ont leur propre compteur de passage et ne sont pas coupes au milieu d'une course

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par les workers de harness-linear-learned-limit-can-rise / harness-owner-feedback-write-never-loses-a-return / acquis-hud-eco-gauge (reports/<id>/FINDINGS.txt), non corrige. Ouvert par le superviseur le 23/09 sous la delegation de l'owner pour ce type de signalement (« traite comme tu l'entends », JAK-235/237).
(1) `.autoport/acquis/hud-eco-gauge.sh:127` + `acquis/perf-dma-chain-copies.sh:61` : ~100 lignes de controle de preuve scellee dupliquees. (2) `game/system/autoport_proof.cpp:255` (site_hits_ref) : un id d'acquis n'a pas de site, `FEATURE acquis-... hits=` est le compteur GLOBAL : le controle FEATURE des acquis appareil est vacant. (3) `orchestrator.py:2356` coupe chaque acquis a 600 s ; un acquis appareil perime relance une course complete (462 s pour 420 s de duree) : au-dela de ~550 s il sera tue. (4) acquis-hud-eco-gauge juge l'ordre des couches (terme 10) sur les trois types melanges, pas par type. (5) Le terme 13 (opacite au coeur) de la porte de hud-eco-gauge vaut 1 sur l'etat VALIDE par l'owner : toute reouverture repartira d'une porte rouge.

## Livrable
1. Une bibliotheque commune de garde pour les acquis appareil (acquis/_lib.sh ou equivalent).
2. Un acquis a son site de compteur propre (ou la porte l'exige vacant = defaut NOMME).
3. Delai d'un acquis appareil derive de la duree de sa course + marge, publie.
4. Ordre des couches par type d'eco dans l'acquis de la jauge.
5. Terme 13 de hud-eco-gauge recale sur l'etat valide ou ecarte avec raison.
6. `device_acquis_defects` = somme ; doit valoir 0.
CONTROLE POSITIF fabrique + CONTROLE NEGATIF. Publier le denominateur.

## Preuve exigee
`device_acquis_defects == 0` dans `reports/harness-device-acquis-hardening/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-device-acquis-hardening x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
