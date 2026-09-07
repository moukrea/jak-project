# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-08 : « Le contraste c'est normal non qu'il soit différent,.si on a plus de détails dans les ombres et lumières... Faut juste plus que ce soit brûlé avec par example le ciel blanc..  enfin a toi de me dire »
- 2026-09-08 : « Faut trouver l'équilibre, et n'oublie pas les autres niveaux j'ai l'impression que tu retombes dans tes travers »

## Cause connue
Seuil contraste95% OFF inadapte au tone mapping : deciles differents, baisse gradient ne prouve pas perte detail. Garder mesures, corriger brulures/couleurs et couverture, sans faux vert.

## Livrable
Corriger blancs HDR et coherence artistique SDR. Tous21niveaux, ciel visible en exterieur, interieurs et hutte Sandover, heures0/3/6/9/12/15/18/21. Eclairage seul ON/OFF, autres effets identiques, vues comparables sans frame exacte. Processus frais par niveau ; rejeter vues noires/non representatives. ImageMagick : blancs/quasi-blancs, luminosite, teinte/saturation, details ; tableau couverture, deltas ON/OFF et avant/apres. Calibrer ensemble avec poids equilibre par niveau/heure, pas domination plage ; bilan par niveau et pires derives, puis residus locaux lisses. SPEC §4.5 : Direction artistique commune, reglages/LUT SDR et HDR distincts autorises. Base HDR sans ecretage premature ; domaine/encodage/plage des LUT declares. Ne pas reutiliser compression SDR pour HDR. Separation logique, fusion GPU permise. Dans hdr_tonemap_defects, compter ecretage premature ou transformation de sortie incorrecte ; verification programmatique avec valeurs >1 et profil identite, via proof_run.sh/generic. Ne pas attendre sortie ecran HDR pour corriger SDR. Contraste ON/OFF : diagnostic, seuil95% non bloquant (SPEC §4.5). Juger brulures/ciels delaves avec ecretage, quasi-blancs, couleur/luma et aplats ; ne pas conclure sur seul gradient ni seul RGB255. Priorite captures manquantes/corrections, pas outillage general ni reparation parcours monolithique.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Pas de census, baseline historique, cinq rejeux/frame exacte. Aucun changement textures/modeles HD/herbe/brise/cadence. Ne pas masquer brulures par assombrissement global excessif. Pas de validation owner ; sortie ecran HDR native ensuite.
