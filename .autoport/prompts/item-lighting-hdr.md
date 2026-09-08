# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-08 : « Alors attends, c'est pas mal dans la mesure où il y a moins de blancs brûlés, mais par example dans le ciel, à Off on voit quand même plus de nuages blancs que a off (ils sont attendus), les orbes d'eco bleue à on on voi… »

## Cause connue
Retour owner : nuages/eclairs eco/soleil ecrases, sol hutte et portail violets. Porte actuelle ne compte que exces clipped/white/nearwhite, ignore suppression voulue et derive locale. Cause moteur a isoler, pas attribuee sans preuve.

## Livrable
Corriger les5cas owner de proof_plan : nuages blancs, eclairs eco bleue, soleil couchant, sol devant hutte Sage vert, warp gate violet. Le build a tester est REFUSE artistiquement ; cumul par lots deja implemente, ne pas le refaire. Reproduire d abord ces cas eclairage seul ON/OFF, autres effets identiques, vues/horaires comparables ; sequence courte pour eclairs, aucune frame exacte. Mesures ImageMagick par regions : presence/nuances des blancs voulus, couleur, luminance, aplats ; chiffres image entiere seuls insuffisants. Isoler courbe/domaines couleur/composition additive et transparence avant ajustement ; pas nouveau bloom ou nouvelles particules pour masquer defaut. Corriger rendu et etendre diagnostic/porte hdr_tonemap_defects aux regressions ciblees (absence ou cas non exerce non valide), sans generic modifie ni seuil arbitraire. Blancs attendus OFF conserves ; pas minimisation du nombre de blancs, pas zero blanc comme succes. Comparer AVANT/APRES et publier limites. Puis verifier equilibre21niveaux/8h/ciels/interieurs/hutte par lots ; reutiliser preuves compatibles, autres donnees historiques pour diagnostic. Ajustements locaux permis si justifies, profils SDR/HDR distincts autorises ; sortie HDR native ensuite. Priorite correction concrete des5cas, pas nouveaux outils generaux, pas reprise census.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Pas de census, baseline historique, cinq rejeux/frame exacte. Aucun changement textures/modeles HD/herbe/brise/cadence. Ne pas masquer brulures par assombrissement global excessif. Pas de validation owner ; sortie ecran HDR native ensuite.
