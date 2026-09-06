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

## La garde est intermittente : rejoue deux fois avant de conclure

**Mesuré le 2026-09-06.** Trois rejeux, **même binaire** (`sha=fbf84cf9802b7c11`) et **mêmes
références octet pour octet** (vérifié par `git hash-object` sur les 16 PNG) :

| Rejeu | Condition de lancement | `refset_replay_maxdiff` |
|---|---|---|
| 1 | juste après 45 s d'attente sur `deploy-in-progress` (constructeur) | **188** (diffpx 191192) |
| 2 | machine au repos, course de preuve 900 s | 0 |
| 3 | machine au repos, rejeu indépendant 240 s | 0 |

Une reconstruction complète de `out/jak1/iso` (tous les `.DGO`, les 26 `.VIS`, les 24 bancs de
texte) a eu lieu entre la capture et le rejeu 1. Elle est **hors de cause** : une recapture
faite après cette reconstruction rend des octets identiques à ceux d'avant.

**Ce qu'il faut en faire, à la fermeture de chaque item :**

1. Ne rejoue pas pendant qu'un constructeur tourne, ni juste après. L'attente intégrée à
   `proof_run` (verrou + `pgrep` + âge de `GAME.CGO`) n'a pas suffi dans le rejeu 1.
2. **Un `maxdiff != 0` isolé ne prouve rien.** Rejoue une seconde fois, machine au repos, avant
   de l'appeler régression.
3. Un écart qui touche les 16 images des DEUX jeux à la fois accuse la caméra ou l'ordonnancement,
   pas une couche d'ombrage : le bras ORIGINE est master OFF et n'a aucune raison de bouger.
4. Le sens de l'erreur est rassurant : l'instabilité fait monter `maxdiff`, donc elle produit un
   faux ROUGE, jamais un faux vert.

Ce point n'est pas résolu : il est nommé et mesuré, pas corrigé.
