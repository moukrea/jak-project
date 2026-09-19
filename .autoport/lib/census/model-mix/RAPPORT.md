# Quel dosage de modèles pour le harnais — ce que disent nos 1 064 essais

*19 septembre 2026. Tout ce qui suit est compté dans nos propres journaux, sauf les tarifs
et les bancs publics, qui viennent des pages officielles citées en fin de document.*

## La réponse en six lignes

Le mélange de modèles n'est **pas** là où se trouve l'argent. Dans un essai, l'agent
principal consomme **86 %** des jetons ; tous les sous-agents réunis en font 14 %. Changer
le modèle des sous-agents fait donc gagner **8 à 11 %**, pas 60 %. Le vrai gisement, c'est
le **volume relu par l'agent principal** : 20,7 millions de jetons de cache par essai.

Le profil que je propose, `panel-sobre`, est écrit dans `model-profiles.json`. **Il n'est
pas activé** : c'est toi qui tranches.

| | aujourd'hui | proposé |
|---|---|---|
| Agent principal | Opus 5, effort élevé | Opus 5, effort élevé *(inchangé)* |
| Sous-agents | Opus 5 | **Sonnet 5** |
| Efforts des sous-agents | élevé / moyen / moyen | **moyen / bas / bas** |
| Coût par essai | **17,25 $** *(mesuré)* | **≈ 15,50 $** *(14,80–15,90)* |

## Ce que chaque profil a réellement coûté et rendu

Un « essai » = un lancement d'agent sur une tâche. « Réussi » = la porte est passée.
« En boucle » = l'essai échoue exactement comme le précédent, trois fois de suite ou plus
— c'est la définition qu'applique déjà le harnais en vol, pas une que j'ai inventée.

| Profil | essais | réussis | en boucle | $ / essai | $ / essai réussi |
|---|---|---|---|---|---|
| Opus 5, effort élevé | 278 | 55,8 % | 4,3 % | 17,25 | **30,92** |
| Opus 4.8 contexte long, effort max | 180 | 66,8 % | 3,3 % | 25,73 | 38,49 |
| Fable 5 contexte long, élevé | 143 | 54,2 % | 2,1 % | 26,38 | 48,64 |
| **Codex (gpt-6-astra), élevé** | 134 | **20,5 %** | **23,1 %** | — | — |
| Opus 5 contexte long, max | 125 | 58,4 % | 5,6 % | 35,82 | 61,33 |
| Opus 4.7, max | 105 | 67,0 % | 2,9 % | 14,24 | 21,24 |
| Fable 5.1 contexte long, élevé | 46 | 46,1 % | 6,5 % | 21,63 | 46,87 |
| *(aucun profil déclaré)* | 28 | **0 %** | **46,4 %** | — | — |

Trois choses sautent aux yeux :

1. **Le « contexte long » se paie 2 fois et ne rend rien.** Opus 5 en contexte long coûte
   **35,82 $** contre **17,25 $** sans, pour 2,6 points de réussite en plus et *davantage*
   de boucles (5,6 % contre 4,3 %). Le mécanisme n'est pas le tarif — la doc officielle est
   formelle, le contexte long d'Anthropic n'a **aucun surcoût**. C'est que le contexte
   n'est plus compacté : l'agent relit 450 000 jetons à chaque tour. La mesure de septembre
   est confirmée sur toute la population, pas sur deux essais.
2. **Codex ne tient pas la route ici.** 20,5 % de réussite et surtout **23,1 % d'essais en
   boucle** — cinq fois le taux de tous les autres. C'est le seul profil où se buter est le
   mode de fonctionnement normal.
3. **28 essais ont tourné sans profil déclaré du tout**, et aucun n'a abouti (46 % en
   boucle). C'est un défaut du harnais, pas un choix de modèle ; il est noté dans FINDINGS.

## Où part l'argent dans un essai

| Étage | part des jetons | messages / essai |
|---|---|---|
| **Agent principal** | **86,4 %** | 93,0 |
| Sous-agent « chercheur » | 10,7 % | 30,4 |
| Sous-agent « implémenteur » | 2,6 % | 6,9 |
| Sous-agent « testeur » | 0,2 % | 1,7 |

À cela s'ajoute le **superviseur** (la session qui pilote) : **3,38 $ par essai** sur la
période Opus 5 — soit 20 % de plus que l'essai lui-même. Sur toute l'histoire du projet, le
superviseur a consommé 16,0 milliards de jetons de cache, environ **11 000 $**. Personne ne
le regardait : il n'apparaît dans aucun compteur d'essai.

C'est ce tableau qui condamne l'idée intuitive « manager fort, sous-agents bon marché » :
les sous-agents ne pèsent presque rien chez nous. J'ai aussi chiffré un modèle *par* étage
(Haiku sur l'implémenteur et le testeur) : **+0,9 %** de gain. Ces deux étages font 2,8 %
des jetons — ça ne vaut pas un troisième modèle à gérer.

## Ce que j'ai vérifié plutôt que de le croire

- **Les tarifs publiés collent à nos factures.** Tarif officiel × nos jetons mesurés
  reproduit le coût que l'outil calcule lui-même, à la quatrième décimale (11,909 $ contre
  11,643 $, l'écart se refermant dès qu'on distingue l'écriture de cache 5 minutes de celle
  d'1 heure). Nos chiffres et les leurs parlent de la même chose.
- **Le routage des sous-agents fonctionne vraiment chez nous.** Un ticket public affirme que
  les réglages de modèle des sous-agents sont ignorés en silence. Sur nos traces,
  **148 étages sur 148** ont bien été facturés au modèle configuré, 0 ignoré. Si ça n'avait
  pas été vrai, toute la recommandation serait sans objet — c'est pourquoi je l'ai mesuré.
- **Fable 5.1 relit le cache moitié moins cher qu'Opus 5** (0,25 $ contre 0,50 $ le million).
  Comme le cache est 99 % du volume, j'ai testé un manager Fable : **14,81 $**, soit à peine
  mieux qu'Opus 5 + Sonnet (14,77 $), et avec un taux de réussite mesuré plus bas. Écarté.

## Les biais — à lire avant de me croire

- **BIAIS — les profils n'ont pas fait les mêmes tâches.** Chaque profil a tourné sur les
  items du moment. Codex a travaillé sur un lot à lui. Comparer les taux de réussite
  compare donc aussi des difficultés différentes, pas seulement des modèles.
- **BIAIS — un essai tué par la plomberie n'est pas un échec du modèle.** Sur 437 échecs,
  **172 viennent de la plomberie de preuve** (preuve absente, appareil injoignable, build,
  verrou) et 265 du fond. Le tri est fait par mots-clés sur les lignes d'erreur : c'est une
  approximation, et elle est plus favorable aux profils qui ont tourné quand la plomberie
  allait mal.
- **BIAIS — la moitié de notre histoire tourne sur des modèles qui n'existent plus.** Opus
  4.7, Opus 4.8 et Fable 5 représentent 428 essais. Leurs chiffres éclairent la méthode,
  ils ne peuvent pas fonder un choix pour demain.
- **BIAIS — la sortie n'est pas attribuable à un étage.** Le flux ne publie qu'un acompte
  par message (7 541 contre 32 646 réellement facturés sur un essai témoin) ; seul le total
  de session est juste. Les parts par étage portent donc sur l'entrée et le cache, soit
  98,7 % des jetons. Les 1,3 % restants sont publiés, pas dissimulés.
- **BIAIS — Sonnet 5 en sous-agent n'a jamais tourné ici.** Le coût projeté tient les jetons
  constants ; le gain de 8 à 11 % est donc solide, mais l'effet sur la **qualité** est une
  promesse des bancs publics, pas une mesure maison. C'est le seul pari du profil proposé.
- **BIAIS — 112 essais n'ont aucun verdict** et 7 sont illisibles. Ils sont comptés dans les
  totaux de coût mais pas dans les taux de réussite.

## Ce que je n'ai pas prouvé

Que `panel-sobre` réussira aussi souvent que le profil actuel. Personne ne peut le savoir
avant de l'avoir fait tourner — c'est pour ça qu'il est écrit mais **pas activé**. Si tu
veux le tester, la bonne mesure n'est pas le coût par essai mais le **coût par essai
réussi** : un profil 10 % moins cher qui rate 10 % plus souvent est une perte.

Le gain vraiment important n'est pas dans ce tableau : c'est les 20,7 millions de jetons que
l'agent principal relit à chaque essai, et les 3,38 $ du superviseur que personne ne compte.
Les deux méritent leur propre chantier.

## Sources externes

17 sources, consultées le 19/09/2026, détaillées dans `sources.json` et résumées en
français dans `notes/recherche-externe.md` : pages de tarifs officielles Anthropic et
OpenAI, documentation des niveaux d'effort, bancs publics (Terminal-Bench 4.0,
Terminal-Bench-Science, CursorBench, AutomationBench), publications sur le routage
multi-modèles, retours d'utilisateurs.

**Là où le publié et le mesuré divergent**, j'ai retenu le mesuré et je le dis :
le contexte long est annoncé « sans surcoût » et nous coûte **2,08 ×** ; le routage des
sous-agents est annoncé cassé par un ticket public et fonctionne **148 fois sur 148** chez
nous ; des blogs annoncent Opus 5 à 96 % sur SWE-bench alors qu'Anthropic n'en publie aucun
score — ces blogs ont été écartés, seul l'officiel est cité.
