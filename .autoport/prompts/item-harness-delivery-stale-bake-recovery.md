# La fabrication des APK reprend apres un refus de donnees precalculees perimees

## Defaut cite
- 2026-09-14 : « Reprends le rôle superviseur et le travail autorisé. Lis .autoport/SWITCH_HANDOFF.md et .autoport/SUPERVISOR_CATCHUP.md, puis les handoffs et FINDINGS récents. Rends compte du rattrapage, vérifie la santé du harnais et entretiens la file. Relance les démons de build/livraison listés dans .autoport/.backend.json si arrêtés. Pas de code jeu ni de contact appareil. La veille externe de run-codex.sh entretient l’orchestrateur. »

## Cause connue
Reprise superviseur du 14/09 : auto_build_apk.txt a 16:34:56, gradle ECHEC : STALE BAKE common/custom_data/TFrag3Data.cpp plus recent que out/jak1/fr3/beach.meshweld. Le repere .last_apk_build_commit porte e903a79e12 mais le dernier build publie porte dd49ad8f5b. Les deux arbres different dans le moteur ; le repere ne prouve donc pas la livraison. Les demons ont ete repris avec ADB=/usr/bin/false (aucun contact appareil).

## Livrable
Reparer la reprise de construction au point de production : les donnees de cuisson requises doivent etre remises a jour par le chemin de build autorise avant empaquetage, sans reconfiguration CMake ni modification du format moteur. Un echec ne doit pas etre memorise comme une construction reussie ni abandonne jusqu au prochain changement moteur. Banc isole couvrant donnees perimees, echec de cuisson, succes puis absence de changement : tentative retentee apres echec, repere avance seulement sur APK complet, publication reservee a un artefact coherent. Publier delivery_stale_bake_defects et les populations testees via le producteur de preuve. Ne pas lancer de campagne ni contacter un appareil.

## Preuve exigee
`delivery_stale_bake_defects == 0` dans `reports/harness-delivery-stale-bake-recovery/proof.txt`.
Le proof se produit par `lib/proof_run.sh harness-delivery-stale-bake-recovery x86` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : La livraison de nouveaux builds reprend ; pas de validation visuelle..

## Hors perimetre
Aucun fichier moteur, aucun appareil, aucune relance de l orchestrateur. Pas de suppression des gardes STALE BAKE. Ne pas retoucher les mesures AO.
