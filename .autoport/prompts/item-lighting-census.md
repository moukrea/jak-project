# Fiabiliser les comparaisons ON/OFF pour corriger les blancs HDR

## Defaut cite
- 2026-09-07 : « Enfin j'y entend pas grand chose mais j'espère m'être fait comprendre »
- 2026-09-07 : « Mais putain mais c'est pas possible t'es con ou quoi ? S'il s'est arrêté faut comprendre pourquoi et corriger, ça sert a rien si le harnais s'arrête tout seul pour un rien, soit pas débile ! »

## Cause connue
Essai18 : budget6 atteint apres corrections distinctes. Bootstrap17 rejoue (5880records) et manifeste des buffers consommes livres. Blocage : aucune baseline adaptee/construite, etat apres chargement incomplet (beach encore loading). Source pre-refonte a9ea15a69062a57335278db7680cd647df3c1e1d identifiee : FR3v44, dix exports reels manquants, aucun delta goalc/mips2c. Voir handoff18 et reference_recovery.

## Livrable
Prochain livrable : construire une baseline ISOLEE au commit de reference_recovery, adapter les dix exports reels et reutiliser bootstrap17/manifeste18. Garder renderer ET shaders historiques separes de HEAD ; pas de stubs. Etablir meme etat APRES chargements et memes donnees/config effectives, puis comparer les modes origine baseline/candidat. Ne pas refaire les audits FR3, bootstrap et inventaires acquis ni rejouer l'archive pour retrouver encore maxdiff195.
References candidates NEUVES, qualification independante avant adoption,575 historiques intacts. ON/OFF peuvent differer ; chaque mode doit se rejouer exactement. Trois modes,tous21niveaux livres (>=20,manquants nommes),8heures fixes0/3/6/9/12/15/18/21,>=4interieurs,ciel>=15% par cas a ciel,sky_missing=0 ; Sunkenb reste manquant sans demonstration. Provenance et etat rejouable, puis cinq rejeux exacts et refset_replay_maxdiff=0 ; draws classes/temps GPU conserves. Aucun seuil assoupli. Suite : correction HDR/tonemap SDR.

## Preuve exigee
`refset_replay_maxdiff == 0` dans `reports/lighting-census/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-census x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Aucun masque, tolerance ou gel du rendu livre pour effacer un ecart. Les origines historiques restent intactes ; le nouveau jeu a une provenance distincte et doit etre qualifie avant adoption. Preuve par proof_run.sh, generic.sh inchange. Ni brise ni cadence. Aucun owner-ok.
