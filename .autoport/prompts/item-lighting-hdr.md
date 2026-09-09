# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-09 : « Alors tu me dis aucun progrès ni nouvel essai depuis le précèdent point et tu vois pas le problème ? »
- 2026-09-09 : « mais si t'as pas de téléphone branché... Tu peux quand même faire sous x86 ! Putain tu me saoules ! »

## Cause connue
Arret USB leve pour travail x86 demande par owner. Essai50 ne prouve que indisponibilite USB ; rien ne justifie arret du diagnostic/correction x86.

## Livrable
PRIORITE IMMEDIATE : poursuivre sous x86, sans attendre telephone. Utiliser proof_run.sh lighting-hdr x86 ; adapter lots HDR x86 dans allowlist harnais existante si necessaire. Construire et executer rendu partage, comparer ON/OFF et corriger cinqcas. device:true est verification finale Android, PAS prerequis travail x86. Reprise42 selon proof_plan.recovery_attempt_42. Owner : refonte lumiere HDR uniquement. Pas poursuite autonome HD/cache/allocateur/menu ; signaler blocages annexes et poursuivre vues exploitables sans declarer couverture absente validee. Navigation OFF ne bloque plus travail visuel : ne pas repeter taps aveugles. Priorite sol vraie hutte et assombrissement piece/portail : vues jouables, captures detaillees via proof_run, contribution responsable avant nouveau reglage global. Etendre aux autres niveaux sans attendre perfection plage. Nuages/soleil et eco restent obligatoires; reutiliser diagnostics existants sans rejouer pistes negatives. Portail:10s animees apres chaque reset, tracees. Comparaisons regionales couleur/eclat/details et ensemble image, pas compteur blancs seul. Final: cinqcas,21niveaux8h/ciels/interieurs/vraie hutte par lots compatibles, menuOFF/persistance et crash0. Pas egalite pixel/rejeu exact comme prealable. Aucun ancien binaire comme preuve sans compatibilite; aucun owner-ok.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Pas de census, baseline historique, cinq rejeux/frame exacte. Aucun changement textures/modeles HD/herbe/brise/cadence. Ne pas masquer brulures par assombrissement global excessif. Pas de validation owner ; sortie ecran HDR native ensuite.
