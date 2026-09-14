## ÉTABLI
DIRECTIVES va1dbd6abb3
Correction du harnais terminée ; proof_run x86 unique : delivery_stale_bake_defects=0, 22 cas, crash=0, frames=3356.
Suite complète : 626 passed in 111.57s ; hooks : 16 OK, sortie 0.
Empreinte verdict_sources après course : a92a34608c584b87, identique à proof.txt.
PID 60363 absent et .auto_build_apk.pid absent ; publieur 59525 vivant ; notes/daemon-status.txt.
## TENTÉ
Banc exécute les vrais scripts dans des dépôts isolés avec faux compilateurs/Gradle/ADB/GitHub.
Pannes cuisson, sidecar partiel, ARM64, Gradle, pack HD, sources changées, anciennes sorties : refus puis reprise vérifiés.
Aucun appareil, build APK réel ou redémarrage de démon exécuté ; aucun validateur modifié.
## RESTE
L’orchestrateur doit lancer generic.sh et décider la fermeture machine.
Chargement des nouveaux scripts et reprise effective des démons par le pilotage autorisé, sans prétendre les avoir livrés.
Traiter les défauts hors correction consignés dans FINDINGS.txt ; pas de validation owner attendue (owner_test=false).
