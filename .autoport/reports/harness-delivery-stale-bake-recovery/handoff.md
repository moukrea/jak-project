## ÉTABLI
DIRECTIVES va1dbd6abb3
Correctif a9317464c4 conservé ; aucun code modifié aux essais 3 et 4.
Essai 3 : proof_run x86 sortie 0 ; delivery_stale_bake_defects=0, 22 cas, crash=0, frames=3407.
Course 20260914T180449Z-399350-6086d017 ; proof_attempt_id=harness-delivery-stale-bake-recovery@3#1789409029.
validator-003.txt : generic vert, puis refus acquis Urbanist ; identique à l’essai 2.
Essai 4 : empreinte recalculée a92a34608c584b87, identique à proof.txt conservé.
/tmp/tmp.pQ35vQ0oxO et /tmp/tmp.Ux3GaWqKpm : chacun 0 octet.
Sonde minimale essai 4 : /tmp écriture refusée EDQUOT errno=122 ; hors /tmp 18 octets écrits.
Orchestrateur PID 383084 : TMPDIR/TMP/TEMP absents ; notes/tmp-quota-attempt-4.log.
Rejeu acquis essai 3 hors /tmp déjà vert : source=bundled-police binds=1 EXIT_CODE=0.
## TENTÉ
Audit researcher lecture seule et tester sonde temporaire uniquement ; aucune course rejouée.
Pas de nouveau proof_run : le défaut porte sur la collecte de fermeture, pas le banc livraison.
proof.txt reste celui de l’essai 3 ; il ne constitue PAS une preuve de l’essai 4.
Le code de sortie historique timeout/gk est perdu ; ne pas prétendre connaître sa cause exacte.
Rapport/FINDINGS gardent le rouge HERITE test_pin_props et les autres dettes.
Aucun appareil, build réel, démon relancé, orchestrateur ou validateur modifié.
## RESTE
Le pilotage autorisé doit garantir des temporaires hors quota aux acquis lors de la fermeture.
Rattacher ce cas de collecte à harness-suite-temporary-files-outside-quota ou borner un item adapté.
NE PAS rejouer le même worker livraison avant cette correction : deux fermetures identiques déjà refusées.
Après correction du pilotage, renouveler une seule preuve pour l’identité du nouvel essai et laisser les portes juger.
Chargement des scripts par les démons et livraison réelle non prouvés ; réservés au pilotage autorisé.
owner_test=false : aucun arbitrage esthétique ni jeton owner attendu ; fermeture machine non obtenue.
