# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-07 : « Je sais pas ce que ça change pour notre plan de refonte et sa spec... Ça doit bien changer des trucs non ? Tu peux y réfléchir un peu et pas juste consigner ça dans une footnote je sais pas trop où ? »

## Cause connue
Essai12 : blancs reduits sur premiers cas ; contraste insuffisant et parcours monolithique plante au marais. 10/21 niveaux en service ne prouvent pas leur visibilite. Reutiliser correction et outils existants.

## Livrable
Corriger blancs HDR et coherence artistique SDR. Tous21niveaux, ciel visible en exterieur, interieurs et hutte Sandover, heures0/3/6/9/12/15/18/21. Eclairage seul ON/OFF, autres effets identiques, vues comparables sans frame exacte. Processus frais par niveau ; rejeter vues noires/non representatives. ImageMagick : blancs/quasi-blancs, luminosite, teinte/saturation, details ; tableau couverture, deltas ON/OFF et avant/apres. Iterer courbe/exposition globales sur ensemble puis residus par niveau, transitions lissees. SPEC §4.5 : etalonnage artistique commun en domaine HDR declare, puis transformation sortie SDR distincte. LUT facultative : domaine/encodage/plage explicites, sans compression SDR integree ni ecretage a1 ; conserver nuances >1. Reglages specifiques SDR separes. Dans hdr_tonemap_defects, compter perte de plage avant sortie ou melange etalonnage/sortie ; verification programmatique avec valeurs >1 et profil identite, via proof_run.sh/generic. Ne pas attendre sortie ecran HDR pour corriger SDR. Mesurer cout GPU HDR/resolve sur cas comparables si instrumentation disponible, sinon non mesure ; aucun nouveau toggle impose. Priorite captures manquantes/corrections, pas outillage general ni reparation parcours monolithique.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Pas de census, baseline historique, cinq rejeux/frame exacte. Aucun changement textures/modeles HD/herbe/brise/cadence. Ne pas masquer brulures par assombrissement global excessif. Pas de validation owner ; sortie ecran HDR native ensuite.
