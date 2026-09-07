# Fiabiliser les comparaisons ON/OFF pour corriger les blancs HDR

## Defaut cite
- 2026-09-07 : « Assures toi de bien tester tous les niveaux qui ont un ciel avec ont bien le ciel visible à l'écran, aussi faut tester à différents moment de la journée (sunrise, sunset, noon, night, etc.) avec des heures fixes pour être sûr de bien calibrer »
- 2026-09-07 : « demerdes toi pour HDR/Blanc brûlés, c'est la top priorité, la brise et la cadence c'est sensé être tout en bas de la pile, je t'ai jamais dit de reprendre ça ! La top priorité c'est la refonte du lighting, commençant par reprendre le HDR/blancs brûlés ! »

## Cause connue
Essais 7-9 : refset_replay_maxdiff=254 est une sentinelle de couverture/rejeux incomplets, pas la cause. 24 PNG identiques entre essais 8/9 different des origines seulement en x285..315/y13..72. Objet non attribue ; hutlamp reste une hypothese. Le passage 564->672 etapes decale le temps absolu vent/herbe ; 108 references nouvelles restent a etablir. Voir handoff essai9 et notes/journal-essai7.md.

## Livrable
Corriger le producteur avant de refaire une preuve identique : attribuer programmatiquement la region divergente aux draws/objets, puis corriger sa cause. Stabiliser le temps et l'etat de chaque cas pour que l'ajout d'heures ne decale pas les cas existants. Conserver les origines historiques ; etablir les 108 cas supplementaires separement avec provenance.
Livrer les trois jeux ORIGINE-TOTAL, ORIGINE-LUMIERE et RECHARGED, tous les niveaux livres, interieurs/exterieurs, heures 0/3/6/9/12/15/18/21. Garder draws classes et temps GPU. refset_levels>=20 (21 jouables identifies, manquants nommes), refset_interior_views>=4, cinq rejeux exacts, refset_replay_maxdiff=0. refset_sky_levels issu du moteur ; refset_sky_missing=0 avec ciel>=15% par couple niveau/heure. Sunkenb reste manquant tant que sa visibilite n'est pas tranchee par le chemin de rendu : ne pas le retirer sur ses seuls cadrages a zero.

## Preuve exigee
`refset_replay_maxdiff == 0` dans `reports/lighting-census/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-census x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
SPEC-refonte-lumiere.md §7.3 : deux origines bit-identiques, aucune tolerance ni masque ni recapture pour effacer les ecarts. Preuve via lib/proof_run.sh, jugement generic.sh inchange. Pas de brise, cadence ou nouvelle feature : seuls les correctifs necessaires aux comparaisons HDR. Aucun verdict visuel.
