> LIS D'ABORD `prompts/item-lighting-census-contrat.md` — OBLIGATOIRE. Ce qui suit est un RESUME plafonne a 2560 octets ;
> le contrat complet, tous les verdicts et TOUS les refus de l'owner, mot pour mot,
> sont dans ce fichier.

# Fiabiliser les comparaisons ON/OFF pour corriger les blancs HDR

## Defaut cite
- 2026-09-07 : « En gros du foutage de gueule et de la perte de temps j'ai l'impression »
- 2026-09-07 : « Oui mais du coup la comparaison tu peux faire vite, c'est facile de détecter des blanc brûlés sur ON et OFF, et comparé le delta entre les deux, pas besoin d'un truc exact,.on sait qu'il y aura un petit delta, le but et d'éviter que ce soit trop brûlé et trop différent niveau teinte/saturation/luminosité ! Évidemment qu'il va y avoir une différence entre les deux (plus de détail car calcul en HDR,… »
- 2026-09-17 : « Je comprend rien à ce ticket, c'est un bordel sans nom… Tu m'expliques ? Détaille ? »

## Cause connue
Priorite remplacee par correction HDR directe sur instruction owner ; aucune validation de cet item.

## Livrable
Archive des outils et resultats disponibles ; ne pas reprendre ce chantier comme prerequis du HDR. Owner demande des comparaisons statistiques rapides de vues comparables, pas la meme frame exacte ni cinq rejeux.

## Preuve exigee
`refset_replay_maxdiff == 0` dans `reports/lighting-census/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-census x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Aucune correction de textures, modeles HD, herbe, brise ou cadence dans cette priorite. Aucun nouveau travail sur master OFF/historique. Ne pas annuler aveuglement les corrections deja commitees. Pas de masque ni validation owner. HDR ecran natif ulterieur.
