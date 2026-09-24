# Restes des acquis : un acquis coupe ne laisse plus d'orphelin, et tous les acquis passent par la meme garde

## Defaut cite
- (aucun retour de l'owner enregistre sur cet item)

## Cause connue
Signale par le worker de harness-device-acquis-hardening (reports/.../FINDINGS.txt), non corrige ; ouvert sous la delegation de l'owner pour les signalements de harnais.
(1) `orchestrator.py` GATE 3 : un acquis qui depasse son delai voit son `bash` tue, mais PAS ses enfants (proof_run.sh, course appareil) : orphelin possible, qui bloque ensuite le constructeur d'APK (voir memoire feedback_an_engine_outliving_its_proof_run). (2) `acquis/perf-fbo-passes.sh:61` garde sa propre copie de la garde scellee ; `acquis/font-urbanist.sh:55` sonde l'appareil en direct par adb sans preuve scellee ni garde commune. (3) `acquis/hud-eco-gauge.sh` : les fenetres ou deux types d'eco montent ensemble (881 images sur 8321) et celles sans type (420) ne sont attribuees a personne.

## Livrable
1. Couper un acquis tue tout son groupe de processus (et le dit).
2. perf-fbo-passes et font-urbanist passent par lib/acquis_device_guard.py (ou equivalent commun).
3. `acquis_leftovers` = orphelins apres coupure fabriquee + acquis hors garde commune ; doit valoir 0.
CONTROLE POSITIF + CONTROLE NEGATIF.

## Preuve exigee
`acquis_leftovers == 0` dans `reports/harness-acquis-leftovers/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-acquis-leftovers x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas ce defaut. Ne touche a aucune feature deja validee (`./.autoport/autoport status` ne les liste plus). Pas de mesure visuelle : seule la ligne du moteur compte.
