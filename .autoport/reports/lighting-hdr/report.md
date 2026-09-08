DIRECTIVES v0ba5e280ac
Essai50 : HDR non validé, aucun appareil USB disponible lors du run officiel ; aucune preuve actuelle.
Le handoff49 « Redmi seul autorisé » est périmé : choix USB courant, Honor autorisé, sans ANDROID_SERIAL imposé.
Constat : adb devices -l retourne 0 et une liste vide ; pick_device.sh retourne 3 (notes/essai50/adb-devices.* et pick-device.*).
Commande : AUTOPORT_BACKEND=codex AUTOPORT_PROOF_WAIT_MAX=0 bash .autoport/lib/proof_run.sh lighting-hdr device --timeout 30
Enveloppe historique neutralisant le fallback kill par motif ; argv exact dans notes/essai50/usb-proof-run.json.
Exécution UTC 2026-09-08T23:13:07.664834+00:00 → 23:13:08.343100+00:00, retour 3 en 0,678 s.
Trace exacte : [pick_device] AUCUN appareil joint par USB. Branche-en un (n'importe lequel : le harnais
Suite exacte :               s'adapte et la preuve dira lequel). Une adresse reseau ne compte pas.
Source : notes/essai50/usb-proof-run.stderr ; usb-proof-run.json consigne proof_exists_after=false.
Les huit lignes de proof.txt sont indisponibles : fichier absent ; aucune valeur inventée ni ancienne preuve réutilisée.
Changements : rapport, handoff et notes de reprise ; aucun changement rendu/harnais, build ou déploiement.
Les corrections43 shade.glsl et44 du jugement portail sont conservées ; les diagnostics historiques ne valident pas cet essai.
Blocage transmis par ce rapport : ne pas répéter le même run sans changement de disponibilité USB ; Honor convient aussi.
Owner : Options > Recharged, sol devant vraie hutte, pièce/portail après 10 s animées, nuages, soleil couchant, éclairs éco et Lighting ON/OFF.
non prouvé : cinq cas corrigés, couverture 21 niveaux × 8 h/ciels/intérieurs/vraie hutte, menu OFF/persistance, crash0, activation et fraîcheur actuelles.
Validateur réservé à l'orchestrateur, non lancé par le worker ; aucun owner-ok.
