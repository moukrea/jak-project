# Savoir quel chemin d'eclairage a dessine chaque pixel, et figer les deux references

## Defaut cite
- 2026-09-07 : « Faut quand même mesurer aussi les intérieurs, mais faut mesurer aussi les extérieurs, et je pense que plus que juste Sandover Village histoire d'être carré ! Geyser Rock, Sandover Village en extérieur et intérieur de Hut… »

## Cause connue
LIS D'ABORD prompts/SPEC-refonte-lumiere.md : c'est le contrat, il porte le detail que ce prompt ne repete pas. Cinq composites d'ombrage exclusifs choisis par quatre interrupteurs globaux : personne ne peut dire lequel a dessine un pixel, et aucun item suivant ne peut prouver qu'il n'a rien casse. SPEC 2.3.

## Livrable
L'instrument publie la repartition des draws monde entre les chemins d'ombrage (la somme egale le total) et le temps GPU par passe. Plus TROIS jeux d'images de reference rejouables — ORIGINE-TOTAL (maitre OFF), ORIGINE-LUMIERE (maitre ON, eclairage OFF) et RECHARGED — couvrant TOUS LES NIVEAUX du jeu, exterieurs ET interieurs, sur ordre de l'owner : Geyser Rock, Sandover exterieur ET interieur de hutte, Rock Village, le volcan, le marais, la cite precurseur sous l'eau, le village des neiges, le tube de lave, et le reste. Le jeu en compte 22 jouables (dgos hors kernel/engine/game/dem/int/tit). PORTES : `refset_levels` >= 20 des 22 et chaque manquant NOMME avec sa raison ; `refset_sky_views` >= 8, une par niveau exterieur, ciel sur >= 15 % de l'image ; `refset_interior_views` >= 4 ; `refset_replay_maxdiff` == 0 sur cinq rejeux. La version precedente ne portait que huit vues d'UN SEUL point (village1-hut), sans ciel : c'est ce qui a laisse passer le ciel blanc de lighting-hdr.

## Preuve exigee
`refset_replay_maxdiff == 0` dans `reports/lighting-census/proof.txt`.
Le proof se produit par `lib/proof_run.sh lighting-census x86` — jamais a la main, jamais recopie dans le rapport.

## Hors perimetre
Tout ce qui n'est pas cet item. DEUX origines restent bit-identiques — master OFF, et recharged_lighting OFF — et tout sous-reglage d'eclairage se garde sur recharged_lighting, jamais sur le master seul (SPEC 1.1, 6.2, 7.3). Ne touche a aucune feature validee. Pas de mesure visuelle. Un niveau qui n'existe pas dans le jeu de l'owner (donneur absent) est declare, pas invente.
