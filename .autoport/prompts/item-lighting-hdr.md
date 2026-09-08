# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-08 : « Aussi, le warp gate n'est pas instantané avec du blanc et tout son panel de couleurs, même en rendu original, donc dans les mesures faut que tu attendes au moins 10 secondes devant ! Sinon ça sera toujours violet/translucide »
- 2026-09-08 : « tu rames vraiment du cul »
- 2026-09-08 : « tu pourrais regarder un peu les captures on vs off histoire de te faire une idee aussi »

## Cause connue
Essai42 : crash hd-mtxarea=FFFFFFFF via hd-mtx-check-all dans menus, avant LightingOFF; cause inconnue, cache compagnons suspect seulement. Rendu41 inchange42. Prompt36 obsolete : menuON/retourON et portail10s deja observes. Deficit piece/portail precede courbe; sol vraie hutte non couvert.

## Livrable
Reprise42 selon proof_plan.recovery_attempt_42. Corriger cause bornee crash hd-mtxarea/cache/compaction sans garde speculative ni supprimer modeles. Navigation OFF ne bloque plus travail visuel : ne pas repeter taps aveugles. Priorite sol vraie hutte et assombrissement piece/portail : vues jouables, captures detaillees via proof_run, contribution responsable avant nouveau reglage global. Etendre aux autres niveaux sans attendre perfection plage. Nuages/soleil et eco restent obligatoires; reutiliser diagnostics existants sans rejouer pistes negatives. Portail:10s animees apres chaque reset, tracees. Comparaisons regionales couleur/eclat/details et ensemble image, pas compteur blancs seul. Final: cinqcas,21niveaux8h/ciels/interieurs/vraie hutte par lots compatibles, menuOFF/persistance et crash0. Pas egalite pixel/rejeu exact comme prealable. Aucun ancien binaire comme preuve sans compatibilite; aucun owner-ok.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Pas de census, baseline historique, cinq rejeux/frame exacte. Aucun changement textures/modeles HD/herbe/brise/cadence. Ne pas masquer brulures par assombrissement global excessif. Pas de validation owner ; sortie ecran HDR native ensuite.
