# Savoir quel chemin d'eclairage a dessine chaque pixel, et figer les deux references

## Defaut cite
- 2026-09-07 : « Assures toi de bien tester tous les niveaux qui ont un ciel avec ont bien le ciel visible à l'écran, aussi faut tester à différents moment de la journée (sunrise, sunset, noon, night, etc.) avec des heures fixes pour êtr… »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Cinq composites d'ombrage exclusifs choisis par quatre interrupteurs globaux : personne ne peut dire lequel a dessine un pixel, et aucun item suivant ne peut prouver qu'il n'a rien casse. SPEC 2.3.

## Livrable
L'instrument publie la repartition des draws monde entre les chemins d'ombrage (somme = total) et le temps GPU par passe. Plus TROIS jeux d'images rejouables — ORIGINE-TOTAL (maitre OFF), ORIGINE-LUMIERE (maitre ON, eclairage OFF), RECHARGED — couvrant TOUS les niveaux, exterieurs ET interieurs, aux HUIT HEURES FIXES deja en place (0, 3, 6, 9, 12, 15, 18, 21 h : nuit, lever, midi, coucher).
PORTES, toutes publiees par le moteur :
  * `refset_levels` >= 20 des 22 jouables, chaque manquant NOMME avec sa raison ;
  * `refset_sky_levels` = liste des niveaux qui ONT un ciel, etablie par le moteur et non devinee ;
  * `refset_sky_missing` = 0 — pour CHAQUE couple (niveau a ciel, heure fixe), le ciel occupe >= 15 % de l'image. Un point de vue qui regarde un mur ne compte pas : c'est ce qui a laisse passer le ciel blanc, les huit vues etaient prises au meme endroit devant une hutte ;
  * `refset_interior_views` >= 4 ;
  * `refset_replay_maxdiff` == 0 sur cinq rejeux.

## Preuve exigee
`refset_replay_maxdiff == 0` dans `reports/lighting-census/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-census x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle. Un niveau qui n'existe pas dans le jeu de l'owner (donneur absent) est declare, pas invente.
