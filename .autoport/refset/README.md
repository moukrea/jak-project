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
