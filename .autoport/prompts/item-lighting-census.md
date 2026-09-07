# Fiabiliser les comparaisons ON/OFF pour corriger les blancs HDR

## Defaut cite
- 2026-09-07 : « Tu devrais pouvoir continuer »
- 2026-09-07 : « Heuuu le framework devrait utiliser astra pas spark, spark est bête ! »
- 2026-09-07 : « avec une distribution intelligente du niveau d'effort comme on fait pour Claude code avec Fable 5.1 et Opus 5 par example »

## Cause connue
Essai35 : regression native OFF corrigee ; origine/h00 baseline33/candidat35 maxdiff0/diffpx0. Qualification globale absente : producteur v2 reste missing-state-and-baseline. Ne pas refaire diagnostic shrub ni acquis32/33/35.

## Livrable
Arbitrage superviseur : implementer la transition VERIFIABLE de qualification/adoption dans le producteur et les outils dedies, avec controles de provenance, etat rejouable et comparaison independante baseline/candidat. Pas de changement manuel v2 vers v1, ni gate fabriquee. Les campagnes necessaires sont autorisees VIA proof_run.sh : lots courts bornes et reprenables par cas/niveau, progression persistante, reutilisation seulement si empreintes identiques. La contrainte runs courts ne supprime pas la couverture ni les cinq rejeux. Ne pas rebâtir/retester les acquis sans modification pertinente.
References candidates NEUVES, qualification independante avant adoption,575 historiques intacts. ON/OFF peuvent differer ; chaque mode doit se rejouer exactement. Trois modes,tous21niveaux livres (>=20,manquants nommes),8heures fixes0/3/6/9/12/15/18/21,>=4interieurs,ciel>=15% par cas a ciel,sky_missing=0 ; Sunkenb reste manquant sans demonstration. Provenance et etat rejouable, puis cinq rejeux exacts et refset_replay_maxdiff=0 ; draws classes/temps GPU conserves. Aucun seuil assoupli. Suite : correction HDR/tonemap SDR.

## Preuve exigee
`refset_replay_maxdiff == 0` dans `reports/lighting-census/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-census x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Aucun masque, tolerance ou gel du rendu livre pour effacer un ecart. Les origines historiques restent intactes ; le nouveau jeu a une provenance distincte et doit etre qualifie avant adoption. Preuve par proof_run.sh, generic.sh inchange. Ni brise ni cadence. Aucun owner-ok.
