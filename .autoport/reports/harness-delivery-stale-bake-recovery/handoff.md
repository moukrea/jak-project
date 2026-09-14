## ÉTABLI
DIRECTIVES va1dbd6abb3
Correctif a9317464c4 conservé ; aucun code changé aux essais 3 à 6.
Essai 3 : proof_run x86 sortie 0 ; delivery_stale_bake_defects=0, 22 cas, crash=0, frames=3407.
Course 20260914T180449Z-399350-6086d017 ; proof_attempt_id=harness-delivery-stale-bake-recovery@3#1789409029.
validator-003.txt : generic vert puis refus acquis Urbanist, identique à l’essai 2.
validator-004.txt et validator-005.txt : refus d’identité, preuve essai 3 conservée.
Essai 6 : production_diff_since_attempt_5_rc=0 ; notes/recovery-audit-attempt-6.log.
Orchestrateur parent PID 383084 sans TMPDIR/TMP/TEMP, comme aux essais 4 et 5.
Code actuel : orchestrator.py:1816 hérite l’environnement ; font-urbanist.sh:137 utilise mktemp sans chemin.
Sonde historique essai 4 : /tmp EDQUOT errno=122 ; hors /tmp 18 octets écrits et fsync réussi.
Rejeu acquis essai 3 hors /tmp déjà vert : source=bundled-police binds=1 EXIT_CODE=0.
Item harness-suite-temporary-files-outside-quota toujours open, aucun rapport ; livraison depends_on=[].
## TENTÉ
Audit lecture seule ciblé ; aucune nouvelle sonde quota ni course, conformément au handoff précédent.
proof.txt et proof.seal restent ceux de l’essai 3 : aucune preuve de l’essai 6.
Le statut historique timeout/gk reste perdu ; sa cause exacte n’est pas démontrée.
Rapport/FINDINGS conservent le rouge HERITE test_pin_props et les autres dettes.
Aucun appareil, build réel, démon relancé, orchestrateur, validateur ou backlog modifié par ce worker.
## RESTE
Le pilotage autorisé doit garantir des temporaires hors quota aux acquis lors de la fermeture.
Étendre explicitement harness-suite-temporary-files-outside-quota à cette collecte et poser la dépendance.
NE PAS rejouer le worker livraison avant cette correction : deux refus acquis puis trois reprises sans correctif.
Après correction, renouveler une seule preuve pour l’identité du nouvel essai et laisser les portes juger.
Chargement des scripts par les démons et livraison réelle non prouvés ; réservés au pilotage autorisé.
Essai 6 au plafond : fermeture machine non obtenue, aucune validation owner à attendre (owner_test=false).
