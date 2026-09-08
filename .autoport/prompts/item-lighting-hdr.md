# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-08 : « Faut trouver l'équilibre, et n'oublie pas les autres niveaux j'ai l'impression que tu retombes dans tes travers »
- 2026-09-08 : « Alors attends, c'est pas mal dans la mesure où il y a moins de blancs brûlés, mais par example dans le ciel, à Off on voit quand même plus de nuages blancs que a off (ils sont attendus), les orbes d'eco bleue à on on voit même plus les parricules "éclairs" électriques... Le soleil couchant est jaune… »

## Cause connue
Essais25-30 : eco monopolise six cycles sans correction demontree. Ablation29 : ecart persiste HDR0, populations/fond differents ; cause tone map non etablie. Quatre autres cas sans mesure. Prerequis eco-first supprime ; gate finale conserve les5cas.

## Livrable
Reprise30 : traiter maintenant nuages blancs et soleil couchant, puis sol vraie hutte et portail, sans attendre eco. Exploiter reperes notes30 : nuages SKY_DRAW+PRIM.tme, soleil groupe35/1950-1952. Produire vues comparables eclairage seul ON/OFF et mesures ImageMagick, isoler courbe/composition puis corriger rendu et comparer avant/apres. Utiliser les outils existants ; attribution bornee des regions autorisee, aucun nouveau systeme general ni frame exacte. Preserver blancs voulus, nuances et eclat ; eviter exces brulures/violet/aplats sans nouveau bloom ni assombrissement global. Ne pas optimiser compteur255 seul. Eco reste obligation finale : exploiter ablation29 et traces30, pas repetition clamps/quantification/nommage ou campagnes ORB deja negatives ; absence de temoin ne prouve pas absence effet. Aucun prealable eco pour les autres corrections. Completer owner_regressions pour cas effectivement mesures, absence/echec restent rouges. Ensuite bilan equilibre21niveaux8h/ciels/interieurs/vraie hutte par lots compatibles ; anciens binaires diagnostic uniquement. Profils SDR/HDR distincts permis ; HDR natif ensuite. Aucune validation owner ni porte abaissee.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Pas de census, baseline historique, cinq rejeux/frame exacte. Aucun changement textures/modeles HD/herbe/brise/cadence. Ne pas masquer brulures par assombrissement global excessif. Pas de validation owner ; sortie ecran HDR native ensuite.
