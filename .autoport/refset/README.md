# `refset` — les deux jeux d'images de référence de la refonte de l'éclairage

Posé par l'item **`lighting-census`** (SPEC-refonte-lumiere.md §7.3). **Rejoué à la fermeture de
chaque item suivant de la refonte.**

## Ce que c'est

| Jeu | Condition | Règle |
|---|---|---|
| `origine/` | `recharged_master` **OFF** (`OG_RECHARGED=0`) + `OG_RT_LIGHT=0` | **ne bouge JAMAIS**, `maxdiff == 0` |
| `recharged/` | master **ON** + lumière temps réel **ON** (le préréglage figé) | ne bouge que si l'item le **déclare**, et seulement pour ce qu'il déclare |

Huit images par jeu, une par créneau horaire de `mood-lights-table` (0, 3, 6, 9, 12, 15, 18,
21 h), au point de reprise `village1-hut`, rendues à **320×180, msaa 1** dans le FBO interne —
la taille de la fenêtre de la machine n'entre donc pas dans la comparaison.

## Comment on s'en sert

```bash
bash .autoport/lib/refset.sh replay      # doit finir sur refset_replay_maxdiff=0
```

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

Le déclenchement passe par `render_game_frame` (`game/graphics/pipelines/opengl.cpp`), qui
n'est pas dans `android/CMakeLists.txt` : **c'est un instrument x86**. Sur l'appareil,
`refset_platform=device` et aucune étape ne se lance. Un seul niveau (`village1`) et un seul
vantage sont couverts : les trois autres régimes de la SPEC (`swamp`, `lavatube`, `snow`) et les
vantages multiples ne le sont pas.

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
