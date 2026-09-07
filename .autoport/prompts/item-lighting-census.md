# Fiabiliser les comparaisons ON/OFF pour corriger les blancs HDR

## Defaut cite
- 2026-09-07 : « Enfin j'y entend pas grand chose mais j'espère m'être fait comprendre »
- 2026-09-07 : « Mais putain mais c'est pas possible t'es con ou quoi ? S'il s'est arrêté faut comprendre pourquoi et corriger, ça sert a rien si le harnais s'arrête tout seul pour un rien, soit pas débile ! »

## Cause connue
Essai12 : fuite GL tonemapping corrigee (7290->0 erreurs), references encore divergentes. Phase/RNG/naissance de la lampe historiques non enregistres. Meme message sentinelle254 malgre sources corrigees : le harnais confondait echec global et absence de changement. Reprise : reconstruire un protocole reproductible, pas chercher encore une phase perdue.

## Livrable
Arbitrage superviseur : etablir des references candidates NEUVES dans un dossier distinct, etat initial enregistre et rejouable (RNG/horloges/acteurs), rendu d'origine independamment identifie. Lire reference_recovery dans le backlog. Conserver les575 references historiques et leurs ecarts comme archive ; aucun ecrasement. Qualifier le candidat contre un binaire/source de reference identifie, donnees et etat identiques ; capturer puis rejouer le meme correctif ne prouve PAS l'absence de regression. L'adoption exige cette qualification, la provenance et cinq rejeux exacts.
Trois modes compares chacun a SA reference, jamais egalite ON/OFF. Tous niveaux livres (21 identifies,>=20, manquants nommes), interieurs>=4, heures0/3/6/9/12/15/18/21. Ciel>=15% par cas a ciel, sky_missing=0 ; Sunkenb reste manquant sans demonstration. Conserver draws classes/temps GPU et refset_replay_maxdiff=0 ; aucune sentinelle supprimee pour verdir. Debloquer ensuite la correction HDR/tonemap SDR.

## Preuve exigee
`refset_replay_maxdiff == 0` dans `reports/lighting-census/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-census x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Aucun masque, tolerance ou gel du rendu livre pour effacer un ecart. Les origines historiques restent intactes ; le nouveau jeu a une provenance distincte et doit etre qualifie avant adoption. Preuve par proof_run.sh, generic.sh inchange. Ni brise ni cadence. Aucun owner-ok.
