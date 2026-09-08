# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-08 : « Faut trouver l'équilibre, et n'oublie pas les autres niveaux j'ai l'impression que tu retombes dans tes travers »
- 2026-09-08 : « Alors attends, c'est pas mal dans la mesure où il y a moins de blancs brûlés, mais par example dans le ciel, à Off on voit quand même plus de nuages blancs que a off (ils sont attendus), les orbes d'eco bleue à on on voit même plus les parricules "éclairs" électriques... Le soleil couchant est jaune… »

## Cause connue
Essai24 : eco10012 h12 blancs moyens OFF89.33/ON0, ROI projetee et sequence disponibles. Aucun correctif rendu essai24. owner_regressions() impose encore measured=[] : porte inachevee, pas preuve de correction. Transition deux vues SIGILL ; lots une vue fonctionnent.

## Livrable
Reprise apres essai24 : commencer par corriger la perte lumineuse eco deja reproduite, avec les sequences essai24-projected comme AVANT. Tracer les domaines couleur et la composition jusqu au tone map, modifier le rendu puis mesurer APRES par proof_run, meme vue/heures/config hors correction. Ne pas attendre les5ROIs pour cette correction. Aucun nouveau systeme general de capture. Ensuite traiter nuages, soleil, sol devant vraie hutte Sage vert et portail ; ROI portail actuelle trop large, legacy n est pas la hutte. Brancher owner_regressions sur observations reelles : distinguer mesure et reussite ; absence reste echec, aucun cas valide par simple presence ou zero blanc. Mesures ImageMagick temporelles/regions comparables, pas frame exacte ; conserver blancs voulus OFF et nuances sans exces de brulure ni derive violette. Pas nouveau bloom/particules pour masquer. Puis verifier21niveaux/8h/ciels/interieurs/vraie hutte par lots compatibles. Profils SDR/HDR distincts permis ; HDR natif ensuite. Porte finale inchangee, aucun owner-ok.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Pas de census, baseline historique, cinq rejeux/frame exacte. Aucun changement textures/modeles HD/herbe/brise/cadence. Ne pas masquer brulures par assombrissement global excessif. Pas de validation owner ; sortie ecran HDR native ensuite.
