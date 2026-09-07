# Fiabiliser les comparaisons ON/OFF pour corriger les blancs HDR

## Defaut cite
- 2026-09-07 : « Tu devrais pouvoir continuer »
- 2026-09-07 : « Heuuu le framework devrait utiliser astra pas spark, spark est bête ! »
- 2026-09-07 : « avec une distribution intelligente du niveau d'effort comme on fait pour Claude code avec Fable 5.1 et Opus 5 par example »

## Cause connue
Essai37 : qualification stricte et lots livres ; gate254 signifie couverture incomplete, pas delta image. Binaire final1082eb1b117c91f6 :24comparaisons exactes,2254ressources egales,652manquants. Six essais epuises avec progres distincts. Sunkenb charge mais ciel final nul, pose admissible non resolue.

## Livrable
Reprise superviseur apres diagnostic37 : exploiter outils et binaire final existants. Priorite executable : achever cinq rejeux de la racine exterieure candidat (1/5) et baseline (0/5), puis autres lots bornes via refset_campaign.py/proof_run.sh et manifeste des paires. Reprendre recettes et chemins du handoff37 ; ne pas crediter les cinq rejeux du vieux binaire. Traiter Sunkenb separement : identifier pose fixe admissible commune aux bras ; aucun masque/exemption/override calibre cache. Si une nouvelle pose est necessaire, sa recette et provenance doivent etre explicites avant capture, puis qualification independante et rejeux. Ne pas bloquer les autres lots sur Sunkenb ; il reste manquant.
References candidates NEUVES, qualification independante avant adoption,575 historiques intacts. ON/OFF peuvent differer ; chaque mode doit se rejouer exactement. Trois modes,tous21niveaux livres (>=20,manquants nommes),8heures fixes0/3/6/9/12/15/18/21,>=4interieurs,ciel>=15% par cas a ciel,sky_missing=0 ; Sunkenb reste manquant sans demonstration. Provenance et etat rejouable, puis cinq rejeux exacts et refset_replay_maxdiff=0 ; draws classes/temps GPU conserves. Aucun seuil assoupli. Suite : correction HDR/tonemap SDR.

## Preuve exigee
`refset_replay_maxdiff == 0` dans `reports/lighting-census/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-census x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Aucun masque, tolerance ou gel du rendu livre pour effacer un ecart. Les origines historiques restent intactes ; le nouveau jeu a une provenance distincte et doit etre qualifie avant adoption. Preuve par proof_run.sh, generic.sh inchange. Ni brise ni cadence. Aucun owner-ok.
