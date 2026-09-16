# Handoff — perf-codegen-arm64-calls (essai 10, 2026-09-17)
## ETABLI (mesure, pas suppose)
* **Le rejeu bit-exact n'existe pas sur cet appareil.** Reference a10 capturee a 23:26 sous le
  codegen D'AVANT l'item ; MEME binaire (eaf026857583b409), MEMES CGO (data=d3129cf5) rejoues
  20 min plus tard : `maxdiff=35 diffpx=525`. Rien ne differe entre reference et rejeu. Le
  terme `refset_replay_maxdiff != 0` etait donc rouge pour TOUT binaire, celui d'avant compris.
* **Le codegen livre n'est PAS neutre au pixel.** Meme reference, meme binaire, meme plan, meme
  pad : livre `maxdiff=74 diffpx=610` contre temoin `35 / 525` (`refset_control_maxdiff=35`
  dans proof.txt ; registre a 2 lignes dans `notes/a10/replay-ledger.txt`). UN SEUL echantillon
  par bras : 74-35 depasse toute dispersion de repetition vue (16 au plus,
  notes/a9/replay-ledger.txt:4,6) sans etre une distribution.
* **Le gain existe et il est positif** : `codegen_gain_goalwork_us=+124` us/image (travail GOAL
  2737 -> 2613), 22380 / 22140 images par bras. `codegen_gain_us=+5` seulement : cette cle est
  dominee par la cadence (`goal_busy`=16 ms quand le travail GOAL vaut 2,7 ms).
* Appels a 2 instructions sur les 5 marqueurs, 47 sites, 22140 images sans crash. Le bras avant
  mesure 8 instructions : l'ablation est reelle (1778/1650 prologues callee dans GAME/ENGINE).

## TENTE, ET POURQUOI CA N'A PAS SUFFI
* Essais 7-9 comparaient le bras livre a la reference **a2**, capturee sous le codegen LIVRE :
  le candidat y etait juge contre lui-meme (18-20) et le temoin partait avec un handicap de
  construction (59-77). Le vert qu'on y aurait lu etait un vert de miroir.
* A CGO constants, le seul changement de libgk.so deplace le maximum de 59 a 77 : contre une
  reference vieille, la grandeur est dominee par le BINAIRE, pas par ce qu'on croit juger.

## RESTE
1. **Trancher la cause du 74** : quel registre vivant l'enrobage reduit ne sauve-t-il plus ?
   Juger par famille (stencil shrub/tfrag/tie) pour NOMMER le chemin, pas l'ecart global.
2. **Refaire la paire 3 fois** : donner une dispersion aux deux bras avant de conclure.
3. Le regime epingle pointe sur `codegen-calls-a10` (a2 intacte) : ne pas le rendre a a2, la
   mesure deviendrait irreproductible.
