# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-07 : « Bah fais le bordel ! C'est pas possible j'ai l'impression de parler à un demeuré ! Claude Code aurait déjà capturé tous les niveaux à ciel ouvert en étant sûr de voir le ciel sur les captures, plus les niveaux intérieurs… »

## Cause connue
Essai12 : blancs reduits sur premiers cas ; contraste insuffisant et parcours monolithique plante au marais. 10/21 niveaux en service ne prouvent pas leur visibilite. Reutiliser correction et outils existants.

## Livrable
Executer le protocole owner : tous21niveaux, exterieurs avec ciel REELLEMENT visible, interieurs et hutte Sandover obligatoire, heures in-game fixes0/3/6/9/12/15/18/21. Eclairage seul ON/OFF, autres effets identiques, vues comparables sans frame exacte. Capturer par lots/niveaux en processus frais pour eviter accumulation memoire ; ne pas attendre reparation du parcours monolithique. Refuser prises noires/non representatives, distinguer ciel visible et simple niveau charge. ImageMagick obligatoire : statistiques ecretage/quasi-blancs, luminosite, teinte/saturation et details, valeurs ON/OFF et deltas par vue/heure. Ajuster courbe/exposition sur ensemble, iterer avant/apres en preservant details HDR ; etalonnage couleur distinct, reglages fins par niveau ou LUT autorises si justifies par residus mesures, transitions lissees. Corrections globales d abord, pas optimisation pixel-identique. Publier tableau couverture et valeurs, comparaisons iteratives via proof_run.sh ; generic juge preuves, jamais LLM visuel. Couverture incomplete reste explicite. Priorite aux captures manquantes et corrections, pas nouvel outillage general.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Pas de census, baseline historique, cinq rejeux/frame exacte. Aucun changement textures/modeles HD/herbe/brise/cadence. Ne pas masquer brulures par assombrissement global excessif. Pas de validation owner ; sortie ecran HDR native ensuite.
