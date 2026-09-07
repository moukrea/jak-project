# Le rendu passe en HDR avec un seul tone map

## Defaut cite
- 2026-09-07 : « Et j'ai pas non plus l'impression que tu couvres tous les niveaux non plus d'ailleurs »
- 2026-09-07 : « En gros du foutage de gueule et de la perte de temps j'ai l'impression »
- 2026-09-07 : « Oui mais du coup la comparaison tu peux faire vite, c'est facile de détecter des blanc brûlés sur ON et OFF, et comparé le delta entre les deux, pas besoin d'un truc exact,.on sait qu'il y aura un petit delta, le but et d'éviter que ce soit trop brûlé et trop différent niveau teinte/saturation/luminosité ! Évidemment qu'il va y avoir une différence entre les deux (plus de détail car calcul en HDR,… »

## Cause connue
Owner constate ciel et elements clairs toujours brules. Les rejeux exacts ont retarde la correction ; ils ne sont plus un prerequis.

## Livrable
Corriger directement HDR/tonemap SDR. Premier lot court sur scenes claires : ON/OFF eclairage seul, meme build et autres effets identiques, vues/heures comparables sans frame exacte. Mesurer programmatiquement pixels ecretes/blancs et quasi-blancs, distributions luminosite/teinte/saturation et detail hautes lumieres ; outils existants ou ImageMagick via preuve tracee proof_run.sh. Publier valeurs ON/OFF et deltas AVANT, corriger exposition/courbe/chemin lineaire selon cause mesuree, puis APRES sur memes vues. Differences HDR attendues, aucune egalite de pixels exigee. Adapter les verdicts HDR qui dependent encore de bitexact/cinq rejeux/qualification historique : mesurer le defaut reel, jamais forcer un succes. Etendre ensuite tous21niveaux/8heures/interieurs/exterieurs ; couverture explicite, aucun succes global sur lot partiel. Pas attendre couverture exhaustive pour la premiere correction.

## Preuve exigee
`hdr_tonemap_defects == 0` dans `reports/lighting-hdr/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-hdr device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : Options > Recharged : le rendu general, et surtout les zones tres lumineuses.

## Hors perimetre
Aucun nouveau travail de frame exacte, cinq rejeux, baseline historique ou qualification census. Aucun jugement visuel LLM. Textures/modeles HD/herbe/brise/cadence identiques ; pas de correction de ces features. Pas de validation owner ; ecran HDR natif ulterieur.
