# Fiabiliser les comparaisons ON/OFF pour corriger les blancs HDR

## Defaut cite
- 2026-09-07 : « Attention, on s'attend bien sûr a des différences entre on et off quand même hein ! C'est sensé être techniquement plus riche le rendu de base étant plus Riche (HDR) mais faut que le rendu final reste cohérent avec l'original, pas de blancs brûlés, une teinte/saturation similaire, le contraste est s… »
- 2026-09-07 : « Enfin j'y entend pas grand chose mais j'espère m'être fait comprendre »

## Cause connue
Essais 10-11 : memes 24 images entre essais, differentes des references dans x285..315/y13..72 ; hutlamp ecrit du RGB dans cette zone, cause historique inconnue. 564 cas preserves, 108 complements separes. maxdiff=254 signale aussi couverture/rejeux incomplets. Voir handoff et notes/summary-essai11.json.

## Livrable
Corriger le producteur avant de refaire une preuve identique : attribuer programmatiquement la region divergente aux draws/objets, puis corriger sa cause. Stabiliser le temps et l'etat de chaque cas pour que l'ajout d'heures ne decale pas les cas existants. Conserver les origines historiques ; etablir les 108 cas supplementaires separement avec provenance.
Livrer les trois jeux ORIGINE-TOTAL, ORIGINE-LUMIERE et RECHARGED, tous les niveaux livres, interieurs/exterieurs, heures 0/3/6/9/12/15/18/21. Garder draws classes et temps GPU. refset_levels>=20 (21 jouables identifies, manquants nommes), refset_interior_views>=4, cinq rejeux exacts, refset_replay_maxdiff=0. refset_sky_levels issu du moteur ; refset_sky_missing=0 avec ciel>=15% par couple niveau/heure. Sunkenb reste manquant tant que sa visibilite n'est pas tranchee par le chemin de rendu : ne pas le retirer sur ses seuls cadrages a zero.

## Preuve exigee
`refset_replay_maxdiff == 0` dans `reports/lighting-census/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-census x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
L'egalite exacte compare des rejeux d'un MEME mode a sa propre reference ; JAMAIS ON a OFF. Le rendu ON doit pouvoir enrichir contraste et details. SPEC §7.3 : deux origines conservees bit-identiques, aucun masque/tolerance ni recapture pour effacer un ecart. Preuve par proof_run.sh, generic.sh inchange. Brise/cadence hors perimetre.
