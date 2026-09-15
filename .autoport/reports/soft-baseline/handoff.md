## ÉTABLI
DIRECTIVES v1707e53cb2
Essai 2 : preuve USB neuve, serial=eae4df44, sha=b25d6f806ccd9158, frames=2460, crash=0, soft_baseline_gaps=0.
Sept termes de complétude à zéro ; snapshot final image 2460, 19 systèmes, aucun draw non mesuré.
Builds x86/arm64 + APK codes 0 ; .so APK et local identiques, livraison vérifiée par proof_run.
Tests CPU ON/OFF codes 0, 6 575 445 cas avec totaux comparés à une référence scalaire par longueur/topologie.
## TENTÉ
Scan spécialisé par topologie sans cache ; aucun gain significatif mesuré : comptage médian Redmi 0.945294 ms, publication 0.112344 ms.
Le plafond 200 µs reste non tenu ; aucun nouveau banc ni nouvelle campagne pour chercher un vert.
Le vrai refus essai 1 était un test du harnais rouge hérité non signalé ; reproduit en 0.30s, maintenant nommé et trié dans rapport et FINDINGS.
Test concerné : test_proof.py::test_le_bac_a_sable_contient_exactement_ce_que_la_porte_epingle ; inventaire excluant tests/harness/shrub_contact_local.py.
## RESTE
L’orchestrateur doit lancer le validateur ; le worker ne le lance pas.
Le coût exige de supprimer des rescans via résumés attachés aux buffers avec invalidation explicite ; aucun gain garanti par lecture du code.
Extrema continus, provenance sérialisée, coût actuel x86, coût hors census et au chargement, ablation en jeu non prouvés (FINDINGS.txt).
