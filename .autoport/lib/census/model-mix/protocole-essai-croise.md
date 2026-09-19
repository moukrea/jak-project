# Essai croisé Opus 5 / Fable 5.1 — le protocole, prêt à lancer

Nos journaux ne peuvent pas départager Opus 5 et Fable 5.1 : sur les 8 tâches que les deux
ont réellement traitées, les intervalles se recouvrent largement (41,7–84,8 % contre
34,1–65,9 %). Ce n'est pas une prudence de langage, c'est ce que 15 essais contre 34
permettent de dire. Pour trancher il faut des essais **faits exprès**, pas des essais
repêchés.

Voici ce qu'il faut lancer. Le harnais vérifie, à chaque recensement, que les trois tâches
ci-dessous existent toujours, sont ouvertes, se jugent sans téléphone et n'attendent aucune
tâche parente : un protocole qui nomme des tâches mortes n'est pas un protocole.

## Les trois tâches

Choisies pour une seule raison : **leur verdict est une mesure, pas un avis**. Aucune ne
demande de brancher un téléphone (la plomberie d'appareil est 4 échecs sur 5, elle noierait
le signal) et aucune n'attend que tu regardes quoi que ce soit.

- item `harness-pack-manifest-is-a-build-artefact`
- item `grass-bake-invalidation`
- item `soft-bake-format`

## Les deux bras

Deux profils déjà écrits, identiques au modèle près — mêmes efforts, mêmes sous-agents,
même contexte court. C'est la seule façon pour que l'écart mesuré soit le modèle.

- profil `opus5-sobre`
- profil `fable51-sobre`

## Le déroulé

Six essais : chaque tâche une fois sous chaque profil, **mêmes budgets** (mêmes
`max_retries`, mêmes `max_turns`, mêmes portes). Alterner les bras tâche par tâche plutôt
que faire les trois d'un modèle puis les trois de l'autre : l'état du dépôt bouge, et un
bloc entier joué en second hérite des corrections du premier.

Ordre : tâche 1 sous Opus, tâche 1 sous Fable, tâche 2 sous Fable, tâche 2 sous Opus,
tâche 3 sous Opus, tâche 3 sous Fable.

## Ce qu'on lira à la fin

Les grandeurs sont déjà publiées par le recensement — rien de neuf à écrire :

| grandeur | clé publiée |
|---|---|
| portes tenues par bras | `model_mix_pair_fable_5_1_green_pct` / `..._ref_green_pct` |
| l'intervalle, pas le point | `model_mix_pair_fable_5_1_green_ci` |
| essais qui se butent | `model_mix_pair_fable_5_1_loop_clean` |
| coût par porte tenue | `model_mix_pair_fable_5_1_usd_per_green` |

## Ce que ça coûte, et ce que ça ne prouvera pas

Six essais à 14–28 $ l'unité : **de l'ordre de 100 à 170 $**. Compte une demi-journée.

Ça ne suffira pas à un verdict statistique — 3 contre 3 est encore un petit nombre. Ce que
ça donne, c'est trois **comparaisons directes** sur la même tâche, le même jour, le même
dépôt : là où l'un tient la porte et l'autre non, on peut aller lire les deux journaux côte
à côte et voir *ce qui* a coincé. C'est ce qu'aucun tableau agrégé ne dira jamais.

## Une condition, sinon l'essai est perdu d'avance

**Vérifier le crédit avant de lancer.** 31 des 51 essais Fable 5.1 de notre historique ont
été refusés par l'API (`terminal_reason=api_error`, « You're out of usage credits »). Six
essais refusés produiraient exactement le même faux verdict qu'en septembre. Le refus est
visible dans le journal de l'essai, et le recensement le compte désormais à part.
