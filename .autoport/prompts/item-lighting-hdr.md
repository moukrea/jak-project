# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-09 : « Comment ça se fait, encore une fois, que j'ai pas de rapports toutes les trentes minutes ? J'ai l'impression que tu fous plus rien depuis 19h »
- 2026-09-09 : « Justement c'est assi ton but de voir quand ça coince et corriger en conséquence, là tu vois le workers ne bougeait plus du coup ça perd du temps de fou pour rien, si tu check toutes les trentes minutes tu peux identifier et corriger, sinon t'es juste un reporteur qui peut aussi ajouter des trucs au… »

## Cause connue
Reprise49 : restriction Redmi-only obsolete corrigee dans consignes et proof_run ; disponibilite USB a constater par worker. Cinq defauts et couverture restent non valides.

## Livrable
Reprise42 selon proof_plan.recovery_attempt_42. Owner : refonte lumiere HDR uniquement. Pas poursuite autonome HD/cache/allocateur/menu ; signaler blocages annexes et poursuivre vues exploitables sans declarer couverture absente validee. Navigation OFF ne bloque plus travail visuel : ne pas repeter taps aveugles. Priorite sol vraie hutte et assombrissement piece/portail : vues jouables, captures detaillees via proof_run, contribution responsable avant nouveau reglage global. Etendre aux autres niveaux sans attendre perfection plage. Nuages/soleil et eco restent obligatoires; reutiliser diagnostics existants sans rejouer pistes negatives. Portail:10s animees apres chaque reset, tracees. Comparaisons regionales couleur/eclat/details et ensemble image, pas compteur blancs seul. Final: cinqcas,21niveaux8h/ciels/interieurs/vraie hutte par lots compatibles, menuOFF/persistance et crash0. Pas egalite pixel/rejeu exact comme prealable. Aucun ancien binaire comme preuve sans compatibilite; aucun owner-ok.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Pas de census, baseline historique, cinq rejeux/frame exacte. Aucun changement textures/modeles HD/herbe/brise/cadence. Ne pas masquer brulures par assombrissement global excessif. Pas de validation owner ; sortie ecran HDR native ensuite.
