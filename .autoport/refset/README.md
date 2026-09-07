# `refset` — les deux jeux d'images de référence de la refonte de l'éclairage

Posé par l'item **`lighting-census`** (SPEC-refonte-lumiere.md §7.3). **Rejoué à la fermeture de
chaque item suivant de la refonte.**

## Ce que c'est

| Jeu | Condition | Règle |
|---|---|---|
| `origine/` | `recharged_master` **OFF** (`OG_RECHARGED=0`) + `OG_RT_LIGHT=0` | **ne bouge JAMAIS**, `maxdiff == 0` |
| `recharged/` | master **ON** + lumière temps réel **ON** (le préréglage figé) | ne bouge que si l'item le **déclare**, et seulement pour ce qu'il déclare |

**TROIS JEUX, 26 VUES, 21 NIVEAUX, 552 IMAGES PAR COURSE** (owner 2026-09-07 : « Faut quand même
mesurer aussi les intérieurs, mais faut mesurer aussi les extérieurs […] Tous les niveaux ! » et
« Assures toi de bien tester tous les niveaux qui ont un ciel avec ont bien le ciel visible à
l'écran […] avec des heures fixes pour être sûr de bien calibrer »).

| | |
|---|---|
| vue 0 (`<jeu>/hHH.png`) | hutte de Sandover, **huit** créneaux — le vantage historique |
| 21 vues (`<jeu>/<continue>-hHH.png`) | une par niveau jouable, **huit** créneaux |
| `village1-out` | le deuxième point de vue de Sandover — l'extérieur, **huit** créneaux, parce que la hutte ne montre aucun ciel et ne peut donc pas répondre pour `village1` |
| 4 vues | un second point de vue dans un niveau déjà couvert huit fois — **9 h et 21 h** |

## LA CAMÉRA EST POSÉE, PAS SUIVIE

Jusqu'au 2026-09-07 les vues étaient cadrées par la caméra du jeu, et **aucune ne montrait de
ciel** : au mieux 119 ‰ (`beach-start`), huit vues sur 26 à zéro, pour une porte à 150 ‰.
Ce n'était pas un mauvais choix de points de reprise. `target-continue`
(`target-death.gc:149-167`) recopie bien le `camera-rot` du continue-point dans le combineur,
puis passe la caméra en `cam-fixed` **puis en `cam-string`** — et `cam-string`
(`cam-states.gc:1579`) se replace derrière Jak, à hauteur d'épaule, à l'horizontale. Le
`camera-rot` de la donnée n'est qu'une pose de départ, jetée en quelques images.

Sous `refset`, la caméra est donc **imposée** : `*external-cam-mode*` à `'locked` court-circuite
le combineur (`cam-update.gc:334` → `move-camera-from-pad:169-190`, où `'locked` coupe aussi la
lecture de la manette) et `*save-camera-inv-rot*` est recopié tel quel dans
`(-> *math-camera* inv-camera-rot)`. La pose est **calculée en C++** à partir de la seule donnée
du point de reprise — sa position et le quaternion de cap de Jak, relevés par `level_warp_run`
juste avant le `(start 'play ...)`. Aucun état de la caméra du jeu n'entre dans le calcul.

Ce que ça achète en plus n'est pas accessoire : le point de repos de `cam-string` était la
**première source de non-déterminisme du rejeu** (`refset.h` : 0,02 m d'écart entre deux courses
identiques, 27 000 px sur 57 600). Une caméra calculée de constantes n'a pas de point de repos.

La table est dans `game/graphics/refset.cpp` (`kVantages`) ; chaque `cont` est un
`continue-point` vérifié dans `goal_src/jak1/engine/level/level-info.gc`. Les images sont
rendues à **320×180, msaa 1** dans le FBO interne — la taille de la fenêtre de la machine
n'entre donc pas dans la comparaison.

**Le jeu compte 21 niveaux jouables, pas 22.** 27 `.gd` dans `goal_src/jak1/dgos/`, moins
`kernel`/`engine`/`game` et `dem`/`int`/`tit`. Les deux candidats restants n'existent pas dans le
jeu de l'owner : `halfpipe` (`level-info.gc:2359`, `:nickname 'none`) et `test-zone` (`:2476`)
n'ont **aucun DGO**. Les 21 sont couverts.

## LA PORTE DU CIEL — deux grandeurs qui ne partagent AUCUNE variable

| grandeur | d'où elle vient |
|---|---|
| `refset_sky_levels` | de la **donnée du jeu** : `level-load-info.sky` (`level-h.gc:108`), le champ que `sky-draw` teste lui-même (`sky-tng.gc:901`) avant d'émettre le DMA du ciel. Le fil GOAL le recopie pour chaque niveau ACTIF (`pc-refset-note-level`). Ni la table des vues, ni les pixels. |
| `refset_sky_missing` | des **pixels** : le nombre de couples (niveau à ciel, créneau) dont aucune vue ne montre ≥ 150 ‰ d'arrière-plan. `refset_sky_missing_list` nomme chaque couple manquant **avec sa valeur mesurée**. |

Si l'ensemble de départ se déduisait des pixels qu'il juge, la porte serait un miroir de sa
propre sortie : une vue qui regarde un mur sortirait de la liste et la porte resterait verte
sans avoir rien vu. C'est exactement le faux vert que le superviseur a nommé le 2026-09-07.
`refset_sky_unknown` nomme les niveaux dont le fil GOAL n'a jamais rendu compte — sans lui, un
niveau jamais visité allégerait la porte en silence.
`refset_bgh_<vue>` publie la grandeur brute créneau par créneau (`h09:119`) : sans elle, on ne
saurait pas lequel manque ni de combien.

**LA COUVERTURE EST MESURÉE, PAS DÉCLARÉE.** `refset_levels` compte les niveaux nommés par le
CHARGEUR au moment d'une photo. `refset_sky_views` et `refset_interior_views` se lisent sur la
fraction de pixels d'arrière-plan du tampon de PROFONDEUR, relue au bucket `DEPTH_CUE` (tout le
3D a écrit, aucun 2D encore) : la profondeur est effacée à 0 et le décor teste en GEQUAL, donc
un pixel resté à 0 est un pixel que rien n'a couvert. Convention déjà en service :
`ao_ssao.frag:67`. Une vue dont le niveau attendu n'était pas en service ne compte ni comme
ciel ni comme intérieur (`refset_views_without_level`) — sans ce filtre, un monde pas encore
chargé se lirait comme « 100 % de ciel », ce qu'il a fait dans la tournée d'essai du 2026-09-07
(`citadel-start` 934 à 1000 ‰).

**UNE ARRIVÉE SUR UN VANTAGE COÛTE DEUX TÉLÉPORTS.** Le premier lance le chargement du niveau,
on attend `OG_REFSET_LOAD_SETTLE` frames de LOGIQUE, le second repart d'un monde complet et
c'est lui qui pose l'ancre. Mesure du 2026-09-07 : avec 300 frames d'attente, sept vantages
étaient photographiés sur un monde ABSENT et `refset_levels` valait 14 sur 21.

## Comment on s'en sert

```bash
bash .autoport/lib/refset.sh replay 1500   # doit finir sur refset_replay_maxdiff=0
```

La tournée complète dure ~25 min : 26 arrivées à 1200 + 180 frames de logique et 148 étapes à
180. Le défaut de 360 s coupait la course au 7e vantage, et une course coupée rend 254 — pas une
mesure.

La grandeur est publiée **par le moteur**, pas par le script : `refset_replay_maxdiff`,
`refset_replay_diffpx`, et une ligne `refset_d_<jeu>_h<hh>=<maxdiff>` par image. Quand un écart
apparaît, le PNG réellement rendu est écrit dans
`.autoport/reports/lighting-census/refset-actual/` et se localise hors ligne :

```bash
python3 .autoport/tools/refset_compare.py .autoport/refset \
        .autoport/reports/lighting-census/refset-actual
```

## Recapturer

**`origine/` ne se recapture pas.** Si `origine` bouge, c'est une régression de la règle 1.1 du
contrat, pas une référence à rafraîchir.

`recharged/` se recapture uniquement quand un item a **déclaré** son changement et que le
superviseur l'a tranché :

```bash
bash .autoport/lib/refset.sh capture     # réécrit LES DEUX jeux
git add .autoport/refset && git commit
```

## Ce qui rend la course reproductible

Quatre leviers, tous préexistants dans l'arbre :

1. `OG_LEVEL_WARP=village1-hut` + `OG_LEVEL_WARP_POS` — point de reprise nommé.
2. `OG_PAD_REPLAY_REPLAY=neutral.inputs` — pas de temps fixe de 1/60 s par image, entrée
   neutralisée, toutes les sources d'alea forcées à une graine fixe.
3. L'**ancre** est un état, pas une durée : `*target*` vivant **et** le warp de niveau a déjà
   lancé `(start 'play …)`. Sans le second terme, l'ancre se pose sur le Jak du menu-titre et le
   chargement de niveau — de durée variable en frames de logique — entre dans la mesure.
   L'alea est refixé **à cette ancre-là**.
4. La capture est appariée à la **frame de logique** de la chaîne DMA rendue, pas au numéro
   d'image du renderer. `refset_slip_min` et `refset_slip_max` publient l'écart entre les deux :
   ils doivent être **égaux**, sinon l'appariement n'est pas stable et la porte ne vaut rien.

## Portée honnête

Le déclenchement x86 passe par `render_game_frame` (`game/graphics/pipelines/opengl.cpp`) ; sur
l'appareil c'est `refset_capture_if_step` (`android/android_opengl_renderer.cpp`) et les deux
familles d'images vivent dans des dossiers de noms différents (re-rendu en résolution interne
d'un côté, sous-échantillonnage 4:3 de l'autre). **La sonde de scène — ciel et niveaux — est
x86 seule** : elle vit dans `OpenGLRenderer.cpp`, que `android/CMakeLists.txt` ne compile pas.
Sur appareil, `refset_sky_views` et `refset_levels` valent donc 0 et ne prouvent rien.

**Le régime de modèles est STOCK pour toute la course, y compris dans le jeu RECHARGED.** Le
choix `enhanced`/`stock` d'un niveau est pris UNE fois à son chargement (`Loader.cpp:546`) et ne
se refait jamais ; le maître est posé à 0 par le LANCEUR (sans quoi le fil de chargement gagne
la course, voir plus bas), et les 26 chargements ont tous lieu pendant une étape de phase 1.
`hd_fr3_enhanced=0` / `hd_fr3_stock` le publient. Cette garde protège donc l'ÉCLAIRAGE, pas la
substitution de modèles HD — laquelle a ses propres items.

**Les items validés sur le vantage historique ne sont pas redéfinis.** `OG_REFSET_VANTAGES=legacy`
restreint la tournée aux 8 (ou 24) étapes de la hutte de Sandover ; c'est ce que le `proof_env`
de `lighting-origin-bitexact` et de `refset-replay-stable` épingle. Les grandeurs par jeu
(`refpix_maxdiff_*`, les verdicts de `lighting-hdr`) ne comptent que les photos de ce vantage.

## L'intermittence est fermee : la cause etait une course d'amorcage

**Etabli par l'item `refset-replay-stable` le 2026-09-06.** L'ancienne consigne de ce paragraphe
— « rejoue deux fois avant de conclure » — n'a plus lieu d'etre : elle demandait de vivre avec
un instrument dont on ignorait la cause. La voici.

### Ce qui rendait le chiffre intermittent

1. **Une course entre le fil de chargement et le fil GOAL.** `refset::enabled()` posait
   `OG_RECHARGED=0` a sa PREMIERE image GOAL, alors que le fil de chargement avait deja choisi
   le regime de modeles du premier niveau. Mesure a la capture : `HD-MODELS fr3-select GAME:
   ENHANCED` est journalise **3,9 s AVANT** `[recharged-master] override -> 0`. `GAME.fr3` est le
   niveau commun, jamais evince, dessine dans les 16 etapes des DEUX jeux : il partait en modeles
   HD alors que l'etape 1 veut le master ETEINT, et ce choix ne se refait JAMAIS. Lequel des deux
   fils gagne depend de la charge de la machine — d'ou un ecart bimodal (188 ou 0).
   Ferme au POINT DE PRODUCTION : `OG_RECHARGED=0 OG_RT_LIGHT=0` sont poses par le LANCEUR
   (`lib/refset.sh` et le `proof_env` du backlog), donc la variable existe avant le premier octet
   execute. Verifie : override et `fr3-select GAME: STOCK` tombent dans la MEME milliseconde, et
   `hd_fr3_enhanced=0` pour `hd_fr3_stock=4` niveaux choisis.
2. **Le cache de 0,25 s de `recharged_master_active()`** — une entree de montre MURALE dans une
   decision qui atteint le pixel. Sous `OG_REFSET`, la valeur est relue a chaque appel
   (`gfx.h`, `refset_pins_master()`).
3. **Le jeu de DONNEES n'etait pas dans la cle du registre.** `out/jak1/iso` est reecrit par le
   constructeur ; deux rejeux qui encadrent une reconstruction n'ont pas lu la meme donnee. Effet
   mesure : `refpix_maxdiff_origine` passe de 211 a 0 sur la seule reconstruction. `data=` est
   desormais dans la cle (contenu, jamais une date) : une reconstruction perime les lignes d'avant
   au lieu de les faire mentir, et il n'y a rien a effacer.

### La grandeur qui le dit, et ou la lire

Le moteur tient `<dir>/replay-ledger.txt`, une ligne par rejeu COMPLET :

    bin=<empreinte du binaire> refs=<empreinte des 16 references> data=<empreinte des 57 fichiers> maxdiff=<n> diffpx=<n>

et publie `refset_replay_flaky` = nombre de paires de rejeux CONSECUTIFS, a cle identique, dont
le `maxdiff` differe, plus `refset_replay_runs` = son denominateur. Sentinelles : **255** = la
course n'a pas pu se mesurer ; **254** = moins de CINQ rejeux au registre. Ni l'une ni l'autre ne
vaut zero.

**Mesure de sortie :** cinq rejeux, meme binaire (`bin=e8f509128950aaf6`), memes references
(`refs=285e8fce78144a9c`) et memes donnees (`data=d8d118f44998b750`) rendent le meme
`maxdiff=122` **et le meme `diffpx=200508`** — a l'unite pres, donc les pixels rendus sont
identiques, ce n'est pas un accord de seuil. `refset_replay_flaky=0` sur `refset_replay_runs=5`.

### Ce qui reste vrai, et n'est PAS de l'intermittence

* Le jeu **ORIGINE** est bit-identique sur ses huit creneaux (`refset_d_origine_h*=0`).
* Le jeu **RECHARGED** est a 87..122, **de facon reproductible**. Cause : le regime de modeles
  d'un niveau est choisi UNE fois au chargement et ne se refait jamais, alors que le plan bascule
  le master entre l'etape 8 et l'etape 9 ; `GAME` reste donc STOCK pour les 16 etapes, tandis que
  les references `recharged/` ont ete capturees avec `GAME` en ENHANCED. Le ramener a zero demande
  de recharger le niveau au milieu du plan ou de recapturer `recharged/` — une decision de la
  refonte de l'eclairage. **Ce n'est pas une tolerance a relever.**
* Trou nomme, non ferme : `data_fingerprint()` est calculee a la FIN de la course. Une
  reconstruction qui commence apres le demarrage du `gk` rendrait une cle qui ne decrit pas la
  donnee chargee. L'attente de `proof_run` ne couvre que le DEBUT de la course. Ne rejoue donc
  toujours pas pendant qu'un constructeur tourne.
