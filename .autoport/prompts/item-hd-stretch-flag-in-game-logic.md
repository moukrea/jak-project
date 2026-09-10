# Un drapeau de preuve ne doit pas decider du comportement du jeu

## Defaut cite
- 2026-09-10 : « bah c'est debile, c'est des choses a traiter ! OK pas par lui, mais s'il fait que les mentionner et on en fait jamais rien, ca va rester la, et on va potentiellement se trainer cette merde pendant des mois pour rien, pour qu'un jour quelqu'un retrouve l'erreur par hasard et la corrige... DEBILE !!! Si ce que remonte le worker n'est jamais traite par qui que ce soit, ca sert a rien, quel gaspillage… »

## Cause connue
Signale par le worker de perf-ocean-idle et LAISSE EN L'ETAT : `jak-hd.gc:3386` teste `(zero? (__pc-autoport-armed-for "hd-skin-origin-stretch"))`. Un drapeau du HARNAIS de preuve pilote donc du code de JEU, et il est desarme sur l'appareil : le jeu s'y comporte autrement que sous l'instrument. Defaut latent, jamais corrige.

## Livrable
`proof_flag_game_sites` = 0 : aucun site de code de jeu ne consulte `__pc-autoport-armed-for` pour decider d'un comportement. Recenser TOUS les sites, pas seulement celui-la, et publier la liste. Le comportement retenu est celui que l'owner voit sur l'appareil, drapeau desarme ; s'il differe de celui sous instrument, dire lequel est garde et pourquoi.

## Preuve exigee
`proof_flag_game_sites == 0` dans `reports/hd-stretch-flag-in-game-logic/proof.txt`.
Le proof se produit par `lib/proof_run.sh hd-stretch-flag-in-game-logic device` — jamais a la main, jamais recopie dans le rapport.
Ou l'owner regardera : rien a voir : recensement ; owner_test=false.

## Hors perimetre
Ne pas changer le rendu HD lui-meme. On retire la dependance au drapeau, rien d'autre.
