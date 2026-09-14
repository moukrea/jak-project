## ÉTABLI
DIRECTIVES va1dbd6abb3
Correctif a9317464c4 conservé ; aucun code changé aux essais 3, 4 et 5.
Essai 3 : proof_run x86 sortie 0 ; delivery_stale_bake_defects=0, 22 cas, crash=0, frames=3407.
Course 20260914T180449Z-399350-6086d017 ; proof_attempt_id=harness-delivery-stale-bake-recovery@3#1789409029.
validator-003.txt : generic vert puis refus acquis Urbanist, identique à l’essai 2.
validator-004.txt : refus d’identité de preuve (essai 3 conservé contre essai courant 4).
Essai 5 : production_diff_since_attempt_4_rc=0 ; notes/recovery-audit-attempt-5.log.
Même trace actuelle : orchestrateur parent PID 383084 sans TMPDIR/TMP/TEMP.
Code actuel : orchestrator.py:1816 hérite l’environnement ; font-urbanist.sh:137 utilise mktemp sans chemin.
Sonde historique essai 4 : /tmp EDQUOT errno=122 ; hors /tmp 18 octets écrits et fsync réussi.
Rejeu acquis essai 3 hors /tmp déjà vert : source=bundled-police binds=1 EXIT_CODE=0.
Item harness-suite-temporary-files-outside-quota toujours open, aucun dossier de rapport.
## TENTÉ
Audit researcher lecture seule et constat local des sources/environnement parent ; aucune course rejouée.
Pas de nouvelle sonde quota ni proof_run : aucune correction préalable depuis le handoff essai 4.
proof.txt reste celui de l’essai 3 ; il ne constitue PAS une preuve de l’essai 5.
Le statut historique timeout/gk est perdu ; sa cause exacte n’est pas démontrée.
Rapport/FINDINGS conservent le rouge HERITE test_pin_props et les autres dettes.
Aucun appareil, build réel, démon relancé, orchestrateur, validateur ou backlog modifié par ce worker.
## RESTE
Le pilotage autorisé doit garantir des temporaires hors quota aux acquis lors de la fermeture.
Étendre explicitement harness-suite-temporary-files-outside-quota à cette collecte et poser la dépendance.
NE PAS rejouer le worker livraison avant cette correction : deux refus acquis puis deux reprises sans correctif.
Après correction, renouveler une seule preuve pour l’identité du nouvel essai et laisser les portes juger.
Chargement des scripts par les démons et livraison réelle non prouvés ; réservés au pilotage autorisé.
owner_test=false : aucun arbitrage esthétique ni jeton owner attendu ; fermeture machine non obtenue.
