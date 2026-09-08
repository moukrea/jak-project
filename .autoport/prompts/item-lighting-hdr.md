# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-08 : « T'es sûr ? Parce que je vois littéralement aucune différence entre lighting à off ou on sur le Redmi c'est un peu étrange ! »
- 2026-09-08 : « Aussi, le warp gate n'est pas instantané avec du blanc et tout son panel de couleurs, même en rendu original, donc dans les mesures faut que tu attendes au moins 10 secondes devant ! Sinon ça sera toujours violet/translucide »

## Cause connue
Essai36 : deux crashes AVANT captures : spawn-bird/default-dead-pool0 et intern_from_c/symbol_slot0. Causes profondes non etablies, concurrence non prouvee. Patch menu livre mais retourON/ombres non verifies. Portail10s non mesure car crash.

## Livrable
Reprise36 prioritaire : diagnostiquer et corriger les deux crashes de chargement documentes dans handoff36 et proof_plan.recovery_attempt_36. Correction moteur bornee autorisee ; etablir cause avant patch, ne pas masquer via skip oiseaux/portail, retry identique, hausse settle ou suppression captures. Sources crash conservees ; tests ciblant cause. Puis verifier bouton Lighting en mode normal sans override rt.light : OFF et retourON effectifs, persistance, ombres ; restaurer reglages owner. Mesurer portail apres10secondes animees devant lui et apres chaque purge/warp, temps mural trace. Anciennes captures settle12 non concluantes. Reprendre nuages/soleil puis sol/portail sans prealable eco ; les5cas restent requis. Comparaisons ImageMagick regions ON/OFF et avant/apres, courbe/composition a isoler ; blancs voulus, nuances/eclat conserves sans exces brulures/violet/aplats. Pas nouveau bloom ni compteur255 seul. Pas nouveaux outils generaux/frame exacte ni diagnostics eco negatifs repetes. Final21niveaux8h/ciels/interieurs/vraie hutte par lots compatibles ; aucun ancien binaire comme preuve sans compatibilite. Profils SDR/HDR distincts permis, HDR natif ensuite. Porte finale inchangee ; aucun owner-ok.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Pas de census, baseline historique, cinq rejeux/frame exacte. Aucun changement textures/modeles HD/herbe/brise/cadence. Ne pas masquer brulures par assombrissement global excessif. Pas de validation owner ; sortie ecran HDR native ensuite.
