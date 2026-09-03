# Les PNJ clignotent pendant les cinematiques

## Defaut cite
- 2026-09-01 : « les PNJs qui disparaissent, réapparaîssent, etc etc c'est pas réglé du tout, le pire cas que j'ai observé c'est la cinématique avec maire (la première) »
- 2026-09-03 : « bah non c'est toujours pété, première cinématique avec le Maire est le worst offender... c'est pas corrigé du tout »
- 2026-09-03 : « le seau qui excusait portait 478 des 479 episodes »

## Cause connue
Le maire porte deja `culled=1` DANS SA PROPRE SCENE pendant que le compteur de cycles reste a 0 : le culling est range dans une categorie « justifiee » qui ne compte pas. Les trois portes precedentes ont mesure des scenes ou des acteurs qui ne sont pas ceux qui clignotent, et la preuve du 02/09 a ete prise sur PC.

## Livrable
Zero PNJ ecarte du rendu pendant qu'il est dans le champ de la camera, sur la PREMIERE cinematique du MAIRE, mesure sur le Redmi avec les modeles HD installes, plus une garde de non-regression qui echoue si le symptome revient.

## Preuve exigee
`npc_culled_in_frustum == 0` dans `reports/cutscene-npc-flicker/proof.txt`.
Le proof se produit par `lib/proof_run.sh cutscene-npc-flicker device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : la premiere cinematique avec le Maire.

## Hors perimetre
Jak et Daxter ne sont pas concernes : l'owner parle des PNJ. Pas de refonte du culling general. Aucune capture d'ecran ne vaut preuve.
