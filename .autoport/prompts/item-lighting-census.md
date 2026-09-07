# Fiabiliser les comparaisons ON/OFF pour corriger les blancs HDR

## Defaut cite
- 2026-09-07 : « Tu devrais pouvoir continuer »
- 2026-09-07 : « Heuuu le framework devrait utiliser astra pas spark, spark est bête ! »
- 2026-09-07 : « avec une distribution intelligente du niveau d'effort comme on fait pour Claude code avec Fable 5.1 et Opus 5 par example »

## Cause connue
Essai33 : delta71/190pixels localise au bucket shrub. Baseline vent NATIF actif, candidat le supprime quand master OFF ; causalite unique encore a prouver. Baseline construite, chargements et etats observes apparies : reutiliser acquis32/33.

## Livrable
Arbitrage superviseur : autorise dans lighting-census le diagnostic causal cible et la correction minimale du mouvement NATIF historique supprime en mode origine/OFF. C est une regression OFF bloquant la reference HDR, pas la reprise du chantier foliage-wind. Prouver la causalite et retablir le comportement historique dans le candidat ; ne pas figer ni modifier le renderer/shaders de reference pour obtenir egalite. Brise enrichie/interactions/nouveaux effets restent differes. Reutiliser baseline et traces33 ; ne pas refaire bootstrap/FR3/exports/chargements/etats observes.
References candidates NEUVES, qualification independante avant adoption,575 historiques intacts. ON/OFF peuvent differer ; chaque mode doit se rejouer exactement. Trois modes,tous21niveaux livres (>=20,manquants nommes),8heures fixes0/3/6/9/12/15/18/21,>=4interieurs,ciel>=15% par cas a ciel,sky_missing=0 ; Sunkenb reste manquant sans demonstration. Provenance et etat rejouable, puis cinq rejeux exacts et refset_replay_maxdiff=0 ; draws classes/temps GPU conserves. Aucun seuil assoupli. Suite : correction HDR/tonemap SDR.

## Preuve exigee
`refset_replay_maxdiff == 0` dans `reports/lighting-census/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-census x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Aucun masque, tolerance ou gel du rendu livre pour effacer un ecart. Les origines historiques restent intactes ; le nouveau jeu a une provenance distincte et doit etre qualifie avant adoption. Preuve par proof_run.sh, generic.sh inchange. Ni brise ni cadence. Aucun owner-ok.
