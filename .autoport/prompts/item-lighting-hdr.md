# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-07 : « Après on peut quand même avoir des adaptations différentes sur écran SDR et écran HDR, le fait de partager les altérations c'était de la supposition, je suis pas expert ! Je compte sur toi mais fais pas de la merde »

## Cause connue
Essai12 : blancs reduits sur premiers cas ; contraste insuffisant et parcours monolithique plante au marais. 10/21 niveaux en service ne prouvent pas leur visibilite. Reutiliser correction et outils existants.

## Livrable
Corriger blancs HDR et coherence artistique SDR. Tous21niveaux, ciel visible en exterieur, interieurs et hutte Sandover, heures0/3/6/9/12/15/18/21. Eclairage seul ON/OFF, autres effets identiques, vues comparables sans frame exacte. Processus frais par niveau ; rejeter vues noires/non representatives. ImageMagick : blancs/quasi-blancs, luminosite, teinte/saturation, details ; tableau couverture, deltas ON/OFF et avant/apres. Iterer courbe/exposition globales sur ensemble puis residus par niveau, transitions lissees. SPEC §4.5 : Direction artistique commune, reglages/LUT SDR et HDR distincts autorises. Base HDR sans ecretage premature ; domaine/encodage/plage des LUT declares. Ne pas reutiliser compression SDR pour HDR. Separation logique, fusion GPU permise. Dans hdr_tonemap_defects, compter ecretage premature ou transformation de sortie incorrecte ; verification programmatique avec valeurs >1 et profil identite, via proof_run.sh/generic. Ne pas attendre sortie ecran HDR pour corriger SDR. Mesurer cout GPU HDR/resolve sur cas comparables si instrumentation disponible, sinon non mesure ; aucun nouveau toggle impose. Priorite captures manquantes/corrections, pas outillage general ni reparation parcours monolithique.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Pas de census, baseline historique, cinq rejeux/frame exacte. Aucun changement textures/modeles HD/herbe/brise/cadence. Ne pas masquer brulures par assombrissement global excessif. Pas de validation owner ; sortie ecran HDR native ensuite.
