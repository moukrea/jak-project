## ÉTABLI
DIRECTIVES va1dbd6abb3
Correctif a9317464c4 inchangé : notes/recovery-audit-attempt-7.log, delivery_production_diff_since_a9317464c4_rc=0.
Préalable 5c260abee5 validated ; validator-002.txt : suite_tmp_defects == 0 tenu.
Code close_gate vérifié : suite_temporary puis env=acq_env avec TMPDIR/TMP/TEMP hors /tmp.
Essai 7 : proof_run x86 sortie 0, delivery_stale_bake_defects=0, 22 cas réussis, crash=0, frames=3398.
Identité harness-delivery-stale-bake-recovery@7#1789411452 ; course 20260914T184641Z-554593-33438d2b.
Durée totale 81 s ; census 20 s ; notes/proof-attempt-7.log et notes/delivery-stale-bake.log.
Démons 311261/59525 vivants, ADB non surchargé ; aucune relance.
Parent orchestrateur 492878 : démarrage 20:34:01, édition orchestrator.py 20:36:09 ; TMPDIR hors /tmp.
TMP/TEMP parent absents ; chargement du nouveau close_gate non prouvé, risque consigné dans FINDINGS.
## TENTÉ
Une seule course de renouvellement, après validation du préalable ; aucun changement de production.
Audit researcher et course tester natifs Codex ; résultats relus par le manager.
Aucun appareil, build réel, validateur, acquis réel, orchestrateur ou backlog touché par ce worker.
Erreur rm /dev/null encore observée pendant la preuve, déjà consignée hors périmètre.
## RESTE
Laisser l’orchestrateur lancer generic puis les portes de fermeture ; aucune fermeture déclarée par le worker.
Si refus acquis : conserver la sortie complète ; ne pas attribuer le timeout historique au quota sans mesure.
Le pilotage doit garantir le chargement du nouveau close_gate ; aucune relance autorisée dans ce worker.
Cuisson/APK réels, publication distante et chargement par les démons restent non prouvés.
Aucune validation owner à attendre : owner_test=false ; aucun essai supplémentaire demandé.
